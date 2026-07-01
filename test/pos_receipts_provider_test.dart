import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/pos_receipt.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/repositories/firestore_inventory_repository.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

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

  group('PosReceipt – Firestore-Serialisierung', () {
    test('round-trippt Felder, Steuern und Zeilen', () {
      final receipt = PosReceipt(
        orgId: 'org-1',
        siteId: 'site-1',
        cashRegisterId: 7,
        referenceNumber: 'B-100',
        type: 'sales',
        isRevenue: true,
        businessDay: '2026-06-29',
        transactionDate: DateTime(2026, 6, 29, 18, 30),
        grossCents: 1190,
        taxes: const [
          ReceiptTax(ratePercent: 19, netCents: 1000, taxCents: 190, grossCents: 1190),
        ],
        payments: const [
          PaymentLine(method: 'bar', amountCents: 1190, subType: null),
        ],
        lines: const [
          PosReceiptLine(
            productId: 'p1',
            name: 'Cola',
            category: 'Getränke',
            quantity: 2,
            unitPriceCents: 200,
            discountCents: 10,
          ),
        ],
      );

      final restored =
          PosReceipt.fromFirestore('B-100', receipt.toFirestoreMap());

      expect(restored.referenceNumber, 'B-100');
      expect(restored.cashRegisterId, 7);
      expect(restored.isRevenue, isTrue);
      expect(restored.transactionDate, DateTime(2026, 6, 29, 18, 30));
      expect(restored.grossCents, 1190);
      expect(restored.taxes.single.ratePercent, 19);
      expect(restored.taxes.single.taxCents, 190);
      expect(restored.payments.single.method, 'bar');
      expect(restored.payments.single.amountCents, 1190);
      expect(restored.lines.single.quantity, 2);
      expect(restored.lines.single.realizedUnitPriceCents, 190); // 200 - 10
      expect(restored.lines.single.category, 'Getränke');
    });
  });

  Future<void> seedReceipt(
    FakeFirebaseFirestore fs, {
    required String id,
    required String siteId,
    required DateTime at,
    required List<PosReceiptLine> lines,
    bool isRevenue = true,
  }) {
    final receipt = PosReceipt(
      orgId: 'org-1',
      siteId: siteId,
      referenceNumber: id,
      type: isRevenue ? 'sales' : 'cash',
      isRevenue: isRevenue,
      transactionDate: at,
      lines: lines,
    );
    return fs
        .collection('organizations')
        .doc('org-1')
        .collection('posReceipts')
        .doc(id)
        .set(receipt.toFirestoreMap());
  }

  group('getPosReceiptsInRange', () {
    test('filtert auf Zeitraum und Standort', () async {
      final fs = FakeFirebaseFirestore();
      final repo = FirestoreInventoryRepository(firestore: fs);
      await seedReceipt(fs,
          id: 'r1',
          siteId: 'site-1',
          at: asOf.subtract(const Duration(days: 1)),
          lines: const [PosReceiptLine(productId: 'p1', quantity: 1)]);
      await seedReceipt(fs,
          id: 'old',
          siteId: 'site-1',
          at: asOf.subtract(const Duration(days: 90)),
          lines: const []);
      await seedReceipt(fs,
          id: 'other',
          siteId: 'site-2',
          at: asOf.subtract(const Duration(days: 1)),
          lines: const []);

      final result = await repo.getPosReceiptsInRange(
        'org-1',
        asOf.subtract(const Duration(days: 28)),
        asOf,
        siteId: 'site-1',
      );

      expect(result.map((r) => r.referenceNumber), ['r1']);
    });
  });

  group('InventoryProvider.loadAssortmentAnalysis', () {
    test('verrechnet Belege mit EK zu Rohertrag/ABC', () async {
      final fs = FakeFirebaseFirestore();
      await fs
          .collection('organizations')
          .doc('org-1')
          .collection('products')
          .doc('snack')
          .set({
        'orgId': 'org-1',
        'siteId': 'site-1',
        'name': 'Snack',
        'nameLower': 'snack',
        'purchasePriceCents': 50,
        'isActive': true,
      });
      await seedReceipt(fs,
          id: 'r1',
          siteId: 'site-1',
          at: asOf.subtract(const Duration(days: 1)),
          lines: const [
            PosReceiptLine(
                productId: 'snack',
                name: 'Snack',
                category: 'Süßware',
                quantity: 4,
                unitPriceCents: 150),
          ]);

      final service = FirestoreService(firestore: fs);
      final provider = InventoryProvider(firestoreService: service);
      await provider.updateSession(user, localStorageOnly: false);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final analysis = await provider.loadAssortmentAnalysis(
        siteId: 'site-1',
        windowDays: 28,
        asOf: asOf,
      );

      expect(analysis.items, hasLength(1));
      final snack = analysis.items.single;
      expect(snack.quantitySold, 4);
      expect(snack.revenueCents, 600); // 4 × 150
      expect(snack.contributionCents, 400); // 4 × (150 - 50)
      expect(snack.abcClass, 'A');
      expect(analysis.contributionByCategory['Süßware'], 400);
    });

    test('lokaler Modus liefert leere Analyse', () async {
      final provider =
          InventoryProvider(firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()));
      await provider.updateSession(user, localStorageOnly: true);
      final analysis = await provider.loadAssortmentAnalysis(siteId: 'site-1');
      expect(analysis.items, isEmpty);
      expect(analysis.totalContributionCents, 0);
    });
  });
}
