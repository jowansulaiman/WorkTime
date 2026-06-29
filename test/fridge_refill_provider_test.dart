import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/fridge_refill.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/repositories/firestore_inventory_repository.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// Cloud-Repo, dessen Nachfülllisten-Write scheitert – um den hybrid-Offline-
/// Fallback des Providers zu prüfen (Subklasse statt Mockito, wie im Projekt
/// üblich).
class _FridgeOfflineRepo extends FirestoreInventoryRepository {
  _FridgeOfflineRepo(FakeFirebaseFirestore firestore)
      : super(firestore: firestore);

  @override
  Future<void> saveFridgeRefillList(FridgeRefillList list) async {
    throw Exception('offline');
  }
}

void main() {
  // Nicht-Demo-Nutzer -> kein Demo-Seeding, leerer Start.
  const user = AppUserProfile(
    uid: 'owner-1',
    orgId: 'org-1',
    email: 'owner@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Inhaber'),
  );

  late FakeFirebaseFirestore firestore;
  late FirestoreService firestoreService;

  InventoryProvider newLocalProvider() => InventoryProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    firestore = FakeFirebaseFirestore();
    firestoreService = FirestoreService(firestore: firestore);
  });

  group('Kühlschrank-Nachfüllliste – lokaler Modus', () {
    test('addFridgeRefillItem legt einen Artikel an und denormalisiert', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);

      await provider.addFridgeRefillItem(
        siteId: 'site-1',
        productId: 'p-1',
        name: 'Coca-Cola',
        category: 'Getränke',
        unit: 'Flasche',
        siteName: 'Tabak Börse',
      );

      final list = provider.fridgeRefillListForSite('site-1');
      expect(list, isNotNull);
      expect(list!.items, hasLength(1));
      final item = list.items.single;
      expect(item.productId, 'p-1');
      expect(item.name, 'Coca-Cola');
      expect(item.category, 'Getränke');
      expect(item.unit, 'Flasche');
      expect(item.quantity, 1);
      expect(item.done, isFalse);
      expect(item.addedByUid, 'owner-1');
      expect(item.addedByName, 'Inhaber');
      expect(item.id, isNotEmpty);
      expect(provider.fridgeRefillOpenCount('site-1'), 1);
    });

    test('erneutes Hinzufügen desselben Artikels erhöht die offene Menge',
        () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);

      await provider.addFridgeRefillItem(
          siteId: 'site-1', productId: 'p-1', name: 'Cola', quantity: 2);
      await provider.addFridgeRefillItem(
          siteId: 'site-1', productId: 'p-1', name: 'Cola', quantity: 3);

      final list = provider.fridgeRefillListForSite('site-1')!;
      expect(list.items, hasLength(1));
      expect(list.items.single.quantity, 5);
    });

    test('Freitext-Positionen werden immer als neuer Eintrag angelegt', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);

      await provider.addFridgeRefillItem(siteId: 'site-1', name: 'Wasser');
      await provider.addFridgeRefillItem(siteId: 'site-1', name: 'Wasser');

      final list = provider.fridgeRefillListForSite('site-1')!;
      expect(list.items, hasLength(2));
      expect(list.items.every((i) => i.isFreeText), isTrue);
      expect(list.items.every((i) => i.unit == 'Stück'), isTrue);
    });

    test('setFridgeRefillItemDone hakt ab und reduziert openCount', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.addFridgeRefillItem(
          siteId: 'site-1', productId: 'p-1', name: 'Cola');
      final itemId = provider.fridgeRefillItems('site-1').single.id;

      await provider.setFridgeRefillItemDone(
          siteId: 'site-1', itemId: itemId, done: true);

      final list = provider.fridgeRefillListForSite('site-1')!;
      expect(list.items.single.done, isTrue);
      expect(list.openCount, 0);
      expect(list.doneCount, 1);
    });

    test('setFridgeRefillItemQuantity setzt die Menge, 0 entfernt', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.addFridgeRefillItem(
          siteId: 'site-1', productId: 'p-1', name: 'Cola');
      final itemId = provider.fridgeRefillItems('site-1').single.id;

      await provider.setFridgeRefillItemQuantity(
          siteId: 'site-1', itemId: itemId, quantity: 8);
      expect(provider.fridgeRefillItems('site-1').single.quantity, 8);

      await provider.setFridgeRefillItemQuantity(
          siteId: 'site-1', itemId: itemId, quantity: 0);
      expect(provider.fridgeRefillItems('site-1'), isEmpty);
    });

    test('clearFridgeRefillDone entfernt nur abgehakte Positionen', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.addFridgeRefillItem(
          siteId: 'site-1', productId: 'p-1', name: 'Cola');
      await provider.addFridgeRefillItem(
          siteId: 'site-1', productId: 'p-2', name: 'Fanta');
      final items = provider.fridgeRefillItems('site-1');
      await provider.setFridgeRefillItemDone(
          siteId: 'site-1', itemId: items.first.id, done: true);

      await provider.clearFridgeRefillDone('site-1');

      final remaining = provider.fridgeRefillItems('site-1');
      expect(remaining, hasLength(1));
      expect(remaining.single.name, 'Fanta');
    });

    test('clearFridgeRefillList leert die komplette Liste', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.addFridgeRefillItem(
          siteId: 'site-1', productId: 'p-1', name: 'Cola');

      await provider.clearFridgeRefillList('site-1');

      expect(provider.fridgeRefillItems('site-1'), isEmpty);
      expect(provider.fridgeRefillOpenCount('site-1'), 0);
    });

    test('Liste überlebt einen Neustart (lokale Persistenz)', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.addFridgeRefillItem(
          siteId: 'site-1', productId: 'p-1', name: 'Cola', quantity: 4);

      final restored = newLocalProvider();
      await restored.updateSession(user);

      final list = restored.fridgeRefillListForSite('site-1');
      expect(list, isNotNull);
      expect(list!.items.single.name, 'Cola');
      expect(list.items.single.quantity, 4);
    });

    test('addFridgeRefillItem ignoriert leeren Namen / Menge <= 0', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);

      await provider.addFridgeRefillItem(siteId: 'site-1', name: '   ');
      await provider.addFridgeRefillItem(
          siteId: 'site-1', name: 'Cola', quantity: 0);

      expect(provider.fridgeRefillItems('site-1'), isEmpty);
    });
  });

  group('Kühlschrank-Nachfüllliste – Cloud-Modus (Firestore-Round-Trip)', () {
    test('addFridgeRefillItem schreibt nach Firestore und der Stream spiegelt',
        () async {
      final provider = InventoryProvider(firestoreService: firestoreService);
      await provider.updateSession(user, localStorageOnly: false);

      await provider.addFridgeRefillItem(
        siteId: 'site-1',
        productId: 'p-1',
        name: 'Coca-Cola',
        category: 'Getränke',
        siteName: 'Tabak Börse',
      );
      // Stream-Emission asynchron durchlaufen lassen.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final list = provider.fridgeRefillListForSite('site-1');
      expect(list, isNotNull);
      expect(list!.items.single.name, 'Coca-Cola');
      expect(list.items.single.category, 'Getränke');
    });
  });

  group('Kühlschrank-Nachfüllliste – Hybrid-Offline-Fallback', () {
    test('fehlgeschlagener Cloud-Write wirft nicht und persistiert lokal',
        () async {
      final provider = InventoryProvider(
        firestoreService: firestoreService,
        inventoryRepository: _FridgeOfflineRepo(firestore),
      );
      await provider.updateSession(user, hybridStorageEnabled: true);

      // Darf NICHT werfen -> lokaler Fallback greift (frueher: harter Fehler +
      // Datenverlust).
      await provider.addFridgeRefillItem(
        siteId: 'site-1',
        productId: 'p-1',
        name: 'Cola',
        siteName: 'Tabak Börse',
      );
      // Cloud-Stream-Emission (leer, da der Write fehlschlug) durchlaufen lassen.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Garantie des Hybrid-Fallbacks: die Liste ist LOKAL persistiert (überlebt
      // einen Neustart). Der gestreamte In-Memory-Stand folgt weiterhin der
      // Cloud (wie beim Bestellkorb) — bewusst nicht Teil der Zusicherung.
      final persisted = await DatabaseService.loadLocalFridgeRefillLists(
        scope: LocalStorageScope.fromUser(user),
      );
      expect(persisted, hasLength(1));
      expect(persisted.single.items.single.name, 'Cola');
    });
  });
}
