import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/repositories/firestore_inventory_repository.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// Integrationstests für die nicht-limitierte Bewegungs-Range-Query und die
/// daraus abgeleitete Velocity (P1.1) über `FakeFirebaseFirestore`.
void main() {
  const user = AppUserProfile(
    uid: 'owner-1',
    orgId: 'org-1',
    email: 'owner@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Inhaber'),
  );

  final asOf = DateTime(2026, 6, 30, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  // Seedet einen Artikel mit explizitem createdAt (toFirestoreMap würde
  // serverTimestamp=jetzt schreiben — für Range-Tests brauchen wir feste Daten).
  Future<void> seedProduct(
    FakeFirebaseFirestore fs, {
    required String id,
    required String siteId,
    required int currentStock,
    int? purchasePriceCents,
  }) async {
    await fs
        .collection('organizations')
        .doc('org-1')
        .collection('products')
        .doc(id)
        .set({
      'orgId': 'org-1',
      'siteId': siteId,
      'name': id,
      'nameLower': id,
      'currentStock': currentStock,
      'purchasePriceCents': purchasePriceCents,
      'isActive': true,
    });
  }

  Future<void> seedMovement(
    FakeFirebaseFirestore fs, {
    required String id,
    required String productId,
    required String siteId,
    required int quantityDelta,
    required DateTime createdAt,
    String type = 'issue',
  }) async {
    await fs
        .collection('organizations')
        .doc('org-1')
        .collection('stockMovements')
        .doc(id)
        .set({
      'orgId': 'org-1',
      'siteId': siteId,
      'productId': productId,
      'type': type,
      'quantityDelta': quantityDelta,
      'createdAt': Timestamp.fromDate(createdAt),
    });
  }

  group('getStockMovementsInRange', () {
    test('liefert ohne 100er-Limit alle Bewegungen im Zeitraum, '
        'standortgefiltert', () async {
      final fs = FakeFirebaseFirestore();
      final repo = FirestoreInventoryRepository(firestore: fs);
      // 120 Bewegungen (über dem alten limit=100) im Fenster, 1 außerhalb.
      for (var i = 0; i < 120; i++) {
        await seedMovement(
          fs,
          id: 'm$i',
          productId: 'p1',
          siteId: 'site-1',
          quantityDelta: -1,
          createdAt: asOf.subtract(Duration(days: 1, minutes: i)),
        );
      }
      await seedMovement(
        fs,
        id: 'old',
        productId: 'p1',
        siteId: 'site-1',
        quantityDelta: -99,
        createdAt: asOf.subtract(const Duration(days: 60)),
      );
      // Anderer Standort darf nicht durchschlagen.
      await seedMovement(
        fs,
        id: 'other-site',
        productId: 'p9',
        siteId: 'site-2',
        quantityDelta: -5,
        createdAt: asOf.subtract(const Duration(days: 1)),
      );

      final from = asOf.subtract(const Duration(days: 28));
      final result = await repo.getStockMovementsInRange(
        'org-1',
        from,
        asOf,
        siteId: 'site-1',
      );

      expect(result, hasLength(120));
      expect(result.every((m) => m.siteId == 'site-1'), isTrue);
      expect(result.any((m) => m.id == 'old'), isFalse);
    });
  });

  group('InventoryProvider.computeSiteVelocities (cloud)', () {
    test('berechnet Tagesabsatz/Reichweite aus der Range-Query', () async {
      final fs = FakeFirebaseFirestore();
      await seedProduct(fs,
          id: 'p1', siteId: 'site-1', currentStock: 56, purchasePriceCents: 100);
      await seedProduct(fs,
          id: 'p2', siteId: 'site-1', currentStock: 30); // unbewertet
      // Anderer Standort — darf nicht in der site-1-Auswertung auftauchen.
      await seedProduct(fs, id: 'p9', siteId: 'site-2', currentStock: 5);

      await seedMovement(fs,
          id: 'a',
          productId: 'p1',
          siteId: 'site-1',
          quantityDelta: -28,
          createdAt: asOf.subtract(const Duration(days: 2)));
      await seedMovement(fs,
          id: 'b',
          productId: 'p1',
          siteId: 'site-1',
          quantityDelta: -28,
          createdAt: asOf.subtract(const Duration(days: 5)));

      final service = FirestoreService(firestore: fs);
      final provider = InventoryProvider(firestoreService: service);
      await provider.updateSession(user, localStorageOnly: false);
      // Firestore-Streams (watchProducts) einschwingen lassen.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final velocities = await provider.computeSiteVelocities(
        siteId: 'site-1',
        windowDays: 28,
        asOf: asOf,
      );

      expect(velocities.map((v) => v.productId), containsAll(['p1', 'p2']));
      expect(velocities.any((v) => v.productId == 'p9'), isFalse);

      final p1 = velocities.firstWhere((v) => v.productId == 'p1');
      expect(p1.soldUnits, 56);
      expect(p1.dailyVelocity, 2.0);
      expect(p1.coverageDays, 28.0);
      expect(p1.isValuated, isTrue);

      final p2 = velocities.firstWhere((v) => v.productId == 'p2');
      expect(p2.soldUnits, 0);
      expect(p2.isDeadStock, isTrue);
      expect(p2.isValuated, isFalse);
    });
  });

  group('InventoryProvider.loadShrinkageReport (cloud)', () {
    test('bewertet Inventur-/Korrektur-Bewegungen, ignoriert Verkäufe',
        () async {
      final fs = FakeFirebaseFirestore();
      await seedProduct(fs,
          id: 'p1', siteId: 'site-1', currentStock: 0, purchasePriceCents: 600);
      // Verkauf zählt NICHT, Inventur-Fehlbestand zählt.
      await seedMovement(fs,
          id: 's1',
          productId: 'p1',
          siteId: 'site-1',
          quantityDelta: -100,
          createdAt: asOf.subtract(const Duration(days: 1)));
      await seedMovement(fs,
          id: 'stk',
          productId: 'p1',
          siteId: 'site-1',
          quantityDelta: -5,
          type: 'stocktake',
          createdAt: asOf.subtract(const Duration(days: 1)));

      final service = FirestoreService(firestore: fs);
      final provider = InventoryProvider(firestoreService: service);
      await provider.updateSession(user, localStorageOnly: false);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final report = await provider.loadShrinkageReport(
        siteId: 'site-1',
        windowDays: 30,
        asOf: asOf,
      );

      expect(report.items, hasLength(1));
      expect(report.items.single.netUnits, -5);
      expect(report.shrinkageValueCents, 3000); // 5 × 600
    });
  });

  group('InventoryProvider.loadListingGaps (cloud)', () {
    test('findet Renner des anderen Ladens, der hier fehlt', () async {
      final fs = FakeFirebaseFirestore();
      await seedProduct(fs, id: 'cola', siteId: 'site-1', currentStock: 5);
      // „energy" läuft in site-2, site-1 führt ihn nicht.
      await seedProduct(fs, id: 'energy', siteId: 'site-2', currentStock: 3);
      await seedMovement(fs,
          id: 'e1',
          productId: 'energy',
          siteId: 'site-2',
          quantityDelta: -30,
          createdAt: asOf.subtract(const Duration(days: 1)));

      final service = FirestoreService(firestore: fs);
      final provider = InventoryProvider(firestoreService: service);
      await provider.updateSession(user, localStorageOnly: false);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final gaps = await provider.loadListingGaps(
        siteId: 'site-1',
        windowDays: 28,
        asOf: asOf,
      );

      expect(gaps, hasLength(1));
      expect(gaps.single.sellingProduct.id, 'energy');
      expect(gaps.single.missingSiteId, 'site-1');
      expect(gaps.single.soldUnits, 30);
    });
  });
}
