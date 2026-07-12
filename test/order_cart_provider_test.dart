import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/order_cart.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/purchase_order.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/repositories/firestore_inventory_repository.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// Provider, dessen zweiter savePurchaseOrder-Aufruf scheitert – um den
/// Teilfehler-/Kompensationspfad von checkoutCart zu prüfen (Subklasse statt
/// Mockito, wie im Projekt üblich).
class _FailSecondOrderProvider extends InventoryProvider {
  _FailSecondOrderProvider({
    required super.firestoreService,
    super.disableAuthentication,
  });

  int calls = 0;

  @override
  Future<String> savePurchaseOrder(PurchaseOrder order) {
    calls++;
    if (calls == 2) {
      throw StateError('boom beim zweiten Lieferanten');
    }
    return super.savePurchaseOrder(order);
  }
}

/// #19: saveOrderList schlaegt fehl (offline) — prueft, dass der Hybrid-Modus
/// lokal zurueckfaellt (kein rethrow) und cloud-only hart wirft
/// (CLAUDE.md-Mutator-Muster).
class _OrderListOfflineRepository extends FirestoreInventoryRepository {
  _OrderListOfflineRepository({required super.firestore});

  @override
  Future<void> saveOrderList(SiteOrderList list) async =>
      throw Exception('offline');
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

  Product product({
    required String id,
    required String name,
    String siteId = 'site-1',
    String? supplierId,
    String? supplierName,
    int? purchasePriceCents,
  }) =>
      Product(
        id: id,
        orgId: 'org-1',
        siteId: siteId,
        siteName: 'Tabak Börse',
        name: name,
        unit: 'Stück',
        supplierId: supplierId,
        supplierName: supplierName,
        purchasePriceCents: purchasePriceCents,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    firestore = FakeFirebaseFirestore();
    firestoreService = FirestoreService(firestore: firestore);
  });

  group('Bestellkorb – lokaler Modus', () {
    test('addToCart legt an und erhoeht die Menge bei erneutem Hinzufuegen',
        () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);

      final p = product(id: 'p-1', name: 'Pueblo Tabak');
      await provider.addToCart(product: p, quantity: 2);
      await provider.addToCart(product: p, quantity: 3);

      final cart = provider.orderCartForSite('site-1');
      expect(cart, isNotNull);
      expect(cart!.items, hasLength(1));
      expect(cart.items.single.quantity, 5); // 2 + 3
      expect(cart.items.single.addedByUid, 'owner-1');
      expect(provider.cartItemCount('site-1'), 1);
    });

    test('setCartItemQuantity setzt die Menge, 0 entfernt die Position',
        () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.addToCart(product: product(id: 'p-1', name: 'A'),
          quantity: 4);

      await provider.setCartItemQuantity(
          siteId: 'site-1', productId: 'p-1', quantity: 9);
      expect(provider.orderCartForSite('site-1')!.items.single.quantity, 9);

      await provider.setCartItemQuantity(
          siteId: 'site-1', productId: 'p-1', quantity: 0);
      expect(provider.orderCartForSite('site-1')!.items, isEmpty);
    });

    test('prefillCartFromWeeklyList ergaenzt nur fehlende Artikel', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);

      // Standard-Wochenliste mit zwei Artikeln.
      await provider.saveWeeklyList(
        const SiteOrderList(
          orgId: 'org-1',
          siteId: 'site-1',
          kind: OrderListKind.weeklyTemplate,
          items: [
            OrderListItem(productId: 'p-1', name: 'Pueblo', quantity: 10),
            OrderListItem(productId: 'p-5', name: 'Feuerzeug', quantity: 4),
          ],
        ),
      );

      // Korb hat p-1 bereits mit abweichender Menge.
      await provider.addToCart(product: product(id: 'p-1', name: 'Pueblo'),
          quantity: 2);

      final added = await provider.prefillCartFromWeeklyList('site-1');
      expect(added, 1, reason: 'nur p-5 fehlt');

      final cart = provider.orderCartForSite('site-1')!;
      expect(cart.items, hasLength(2));
      // Vorhandene Menge bleibt unangetastet.
      expect(cart.itemForProduct('p-1')!.quantity, 2);
      expect(cart.itemForProduct('p-5')!.quantity, 4);

      // Erneutes Vorbefuellen ergaenzt nichts mehr.
      expect(await provider.prefillCartFromWeeklyList('site-1'), 0);
    });

    test('checkoutCart gruppiert je Lieferant, legt Bestellungen an und leert '
        'den Korb', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      // Artikel anlegen, damit checkout Preise live ziehen kann.
      await provider.saveProduct(product(
          id: 'p-1',
          name: 'Pueblo',
          supplierId: 'sup-1',
          supplierName: 'Tabak Nord',
          purchasePriceCents: 250));
      await provider.saveProduct(product(
          id: 'p-2',
          name: 'Drum',
          supplierId: 'sup-1',
          supplierName: 'Tabak Nord'));
      await provider.saveProduct(product(
          id: 'p-3',
          name: 'Lakritz',
          supplierId: 'sup-2',
          supplierName: 'Süßwaren Süd'));
      await provider.saveProduct(product(id: 'p-4', name: 'Diverses'));

      for (final p in provider.products) {
        await provider.addToCart(product: p, quantity: 2);
      }
      expect(provider.orderCartForSite('site-1')!.items, hasLength(4));

      final ids = await provider.checkoutCart('site-1');

      expect(ids, hasLength(3), reason: 'sup-1, sup-2, ohne Lieferant');
      expect(provider.purchaseOrders, hasLength(3));
      expect(
        provider.purchaseOrders.every(
            (o) => o.status == PurchaseOrderStatus.ordered),
        isTrue,
      );

      final nord = provider.purchaseOrders
          .firstWhere((o) => o.supplierId == 'sup-1');
      expect(nord.items, hasLength(2));
      // Preis live aus dem Artikel.
      expect(
        nord.items.firstWhere((i) => i.productId == 'p-1').unitPriceCents,
        250,
      );

      final ohne = provider.purchaseOrders.firstWhere((o) => o.supplierId == '');
      expect(ohne.supplierName, 'Ohne Lieferant');

      // Korb ist nach dem Checkout leer.
      expect(provider.orderCartForSite('site-1')!.items, isEmpty);
      expect(provider.cartItemCount('site-1'), 0);
    });

    test('checkoutCart nimmt Teilerfolge zurueck und laesst den Korb gefuellt',
        () async {
      final provider = _FailSecondOrderProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(user);
      await provider.saveProduct(product(
          id: 'p-1', name: 'Pueblo', supplierId: 'sup-1',
          supplierName: 'Tabak Nord'));
      await provider.saveProduct(product(
          id: 'p-2', name: 'Lakritz', supplierId: 'sup-2',
          supplierName: 'Süßwaren Süd'));
      for (final p in provider.products) {
        await provider.addToCart(product: p, quantity: 1);
      }

      // Zweite Lieferanten-Bestellung schlägt fehl -> Gesamtabbruch.
      await expectLater(
        provider.checkoutCart('site-1'),
        throwsA(isA<StateError>()),
      );

      // Erste (bereits erzeugte) Bestellung wurde kompensierend geloescht,
      // der Korb bleibt vollstaendig erhalten -> sauberer Retry moeglich.
      expect(provider.purchaseOrders, isEmpty);
      expect(provider.orderCartForSite('site-1')!.items, hasLength(2));
    });

    test('Korb ueberlebt einen Neustart (lokale Persistenz)', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.addToCart(
          product: product(id: 'p-1', name: 'Pueblo'), quantity: 7);

      final restored = newLocalProvider();
      await restored.updateSession(user);

      final cart = restored.orderCartForSite('site-1');
      expect(cart, isNotNull);
      expect(cart!.items.single.name, 'Pueblo');
      expect(cart.items.single.quantity, 7);
    });

    test(
        'addToCart-Merge leert Kategorie/Lieferant, wenn der Artikel sie '
        'verloren hat (#71)', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);

      const withMeta = Product(
        id: 'p-1',
        orgId: 'org-1',
        siteId: 'site-1',
        siteName: 'Tabak Börse',
        name: 'Pueblo',
        unit: 'Stück',
        category: 'Drehtabak',
        supplierId: 'sup-1',
        supplierName: 'Tabak Nord',
      );
      const withoutMeta = Product(
        id: 'p-1',
        orgId: 'org-1',
        siteId: 'site-1',
        siteName: 'Tabak Börse',
        name: 'Pueblo',
        unit: 'Stück',
      );

      await provider.addToCart(product: withMeta, quantity: 1);
      await provider.addToCart(product: withoutMeta, quantity: 2);

      final item = provider.orderCartForSite('site-1')!.items.single;
      expect(item.quantity, 3);
      expect(item.category, isNull,
          reason: 'clearCategory muss beim Merge greifen');
      expect(item.supplierId, isNull,
          reason: 'clearSupplier muss beim Merge greifen — sonst gruppiert '
              'checkoutCart unter dem veralteten Lieferanten');
      expect(item.supplierName, isNull);
    });

    test('haelt die Koerbe zweier Laeden getrennt (#70)', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);

      await provider.addToCart(
          product: product(id: 'p-1', name: 'Pueblo'), quantity: 1);
      await provider.addToCart(
          product: product(id: 'p-9', name: 'Zeitung', siteId: 'site-2'),
          quantity: 1);

      expect(
        provider.orderCartForSite('site-1')!.items.single.productId,
        'p-1',
        reason: 'site-1-Korb darf keine site-2-Artikel enthalten',
      );
      expect(
        provider.orderCartForSite('site-2')!.items.single.productId,
        'p-9',
      );
      expect(provider.cartItemCount(), 2,
          reason: 'ohne siteId summiert der Zaehler ueber alle Laeden');
      expect(provider.cartItemCount('site-1'), 1);
      expect(provider.orderCartForSite(null), isNull,
          reason: 'bei zwei Listen gibt es keinen Einzel-Laden-Fallback');
    });

    test(
        'Einzel-Laden-Fallback: orderCartForSite(null) liefert die einzige '
        'Liste (#70)', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.addToCart(
          product: product(id: 'p-1', name: 'Pueblo'), quantity: 4);

      final fallback = provider.orderCartForSite(null);
      expect(fallback, isNotNull);
      expect(fallback!.siteId, 'site-1');
      expect(provider.cartItemCount(null), 1);
    });

    test(
        'checkoutCart entfernt auch Positionen ohne productId '
        '(Name+Einheit-Fallback, #72)', () async {
      // Positionen ohne productId entstehen ueber keinen UI-Pfad, der Fallback
      // in _cartItemKey soll aber gegen Altdaten/kuenftige Freitext-Positionen
      // robust bleiben -> direkt lokal seeden.
      await DatabaseService.saveLocalOrderCarts(
        [
          const SiteOrderList(
            id: 'site-1',
            orgId: 'org-1',
            siteId: 'site-1',
            siteName: 'Tabak Börse',
            items: [
              OrderListItem(name: 'Freitext-Ware', unit: 'Karton', quantity: 2),
            ],
          ),
        ],
        scope: const LocalStorageScope(orgId: 'org-1', userId: 'owner-1'),
      );

      final provider = newLocalProvider();
      await provider.updateSession(user);
      expect(
        provider.orderCartForSite('site-1')!.items.single.productId,
        isNull,
      );

      final ids = await provider.checkoutCart('site-1');

      expect(ids, hasLength(1));
      expect(provider.purchaseOrders.single.supplierName, 'Ohne Lieferant');
      expect(
        provider.purchaseOrders.single.items.single.name,
        'Freitext-Ware',
      );
      expect(provider.orderCartForSite('site-1')!.items, isEmpty,
          reason: 'die Position muss ueber den n:name|unit-Schluessel '
              'entfernt worden sein');
    });
  });

  group('Bestellkorb – Hybrid-Fallback (#19)', () {
    test(
        'addToCart faellt im Hybrid-Modus lokal zurueck (kein Throw) und '
        'persistiert lokal', () async {
      final provider = InventoryProvider(
        firestoreService: firestoreService,
        inventoryRepository: _OrderListOfflineRepository(firestore: firestore),
      );
      await provider.updateSession(user, hybridStorageEnabled: true);

      // Darf trotz fehlgeschlagenem Cloud-Write NICHT werfen.
      await provider.addToCart(
          product: product(id: 'p-1', name: 'Pueblo'), quantity: 2);

      // Der In-Memory-Zustand ist im Hybrid-Modus cloud-autoritativ (Stream);
      // die belastbare Fallback-Invariante ist die LOKALE Persistenz.
      final persisted = await DatabaseService.loadLocalOrderCarts(
        scope: const LocalStorageScope(orgId: 'org-1', userId: 'owner-1'),
      );
      expect(persisted.single.items.single.name, 'Pueblo',
          reason: 'der Hybrid-Fallback muss den Korb lokal spiegeln — sonst '
              'geht ein offline hinzugefuegter Artikel still verloren');
      expect(persisted.single.items.single.quantity, 2);
    });

    test('cloud-only: saveOrderList-Fehler wird rethrown', () async {
      final provider = InventoryProvider(
        firestoreService: firestoreService,
        inventoryRepository: _OrderListOfflineRepository(firestore: firestore),
      );
      await provider.updateSession(user, localStorageOnly: false);

      await expectLater(
        provider.addToCart(
            product: product(id: 'p-1', name: 'Pueblo'), quantity: 1),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Bestellkorb – Cloud-Modus (Firestore-Round-Trip)', () {
    test('addToCart schreibt nach Firestore und der Stream spiegelt es zurueck',
        () async {
      final provider = InventoryProvider(firestoreService: firestoreService);
      await provider.updateSession(user, localStorageOnly: false);

      await provider.addToCart(
        product: product(
            id: 'p-1', name: 'Pueblo', supplierId: 'sup-1',
            supplierName: 'Tabak Nord'),
        quantity: 3,
      );
      // Stream-Emission asynchron durchlaufen lassen.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final cart = provider.orderCartForSite('site-1');
      expect(cart, isNotNull);
      expect(cart!.items.single.quantity, 3);
      expect(cart.items.single.supplierName, 'Tabak Nord');
    });

    Future<void> pump() async {
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    test(
        'checkoutCart im Cloud-Modus legt PurchaseOrders in Firestore an und '
        'leert den Korb-Doc (#67)', () async {
      final provider = InventoryProvider(firestoreService: firestoreService);
      await provider.updateSession(user, localStorageOnly: false);

      await provider.saveProduct(product(
          id: 'p-1',
          name: 'Pueblo',
          supplierId: 'sup-1',
          supplierName: 'Tabak Nord',
          purchasePriceCents: 250));
      await provider.saveProduct(product(
          id: 'p-2',
          name: 'Lakritz',
          supplierId: 'sup-2',
          supplierName: 'Süßwaren Süd'));
      await pump();

      for (final p in provider.products) {
        await provider.addToCart(product: p, quantity: 2);
        await pump();
      }
      expect(provider.orderCartForSite('site-1')!.items, hasLength(2));

      final ids = await provider.checkoutCart('site-1');
      await pump();

      expect(ids, hasLength(2), reason: 'eine Bestellung je Lieferant');
      final orderDocs = await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('purchaseOrders')
          .get();
      expect(orderDocs.docs, hasLength(2),
          reason: 'die Bestellungen muessen wirklich in Firestore liegen');

      final cartDoc = await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('orderCarts')
          .doc('site-1')
          .get();
      expect(cartDoc.data()!['items'], isEmpty,
          reason: 'der Korb-Doc muss nach dem Checkout geleert sein');
      expect(provider.orderCartForSite('site-1')?.items ?? const [], isEmpty);
    });

    test('prefillCartFromWeeklyList im Cloud-Modus (Stream-Round-Trip, #67)',
        () async {
      final provider = InventoryProvider(firestoreService: firestoreService);
      await provider.updateSession(user, localStorageOnly: false);

      await provider.saveWeeklyList(
        const SiteOrderList(
          orgId: 'org-1',
          siteId: 'site-1',
          kind: OrderListKind.weeklyTemplate,
          items: [
            OrderListItem(productId: 'p-1', name: 'Pueblo', quantity: 10),
            OrderListItem(productId: 'p-5', name: 'Feuerzeug', quantity: 4),
          ],
        ),
      );
      await pump();

      final added = await provider.prefillCartFromWeeklyList('site-1');
      await pump();

      expect(added, 2);
      final cartDoc = await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('orderCarts')
          .doc('site-1')
          .get();
      expect(cartDoc.data()!['items'], hasLength(2));
      expect(provider.orderCartForSite('site-1')!.items, hasLength(2));
    });

    test(
        'checkoutCart-Teilfehler im Cloud-Modus: Rollback loescht die erste '
        'Bestellung, Korb-Doc bleibt gefuellt (#67)', () async {
      final provider = _FailSecondOrderProvider(
        firestoreService: firestoreService,
      );
      await provider.updateSession(user, localStorageOnly: false);

      await provider.saveProduct(product(
          id: 'p-1',
          name: 'Pueblo',
          supplierId: 'sup-1',
          supplierName: 'Tabak Nord'));
      await provider.saveProduct(product(
          id: 'p-2',
          name: 'Lakritz',
          supplierId: 'sup-2',
          supplierName: 'Süßwaren Süd'));
      await pump();
      for (final p in provider.products) {
        await provider.addToCart(product: p, quantity: 1);
        await pump();
      }

      await expectLater(
        provider.checkoutCart('site-1'),
        throwsA(isA<StateError>()),
      );
      await pump();

      final orderDocs = await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('purchaseOrders')
          .get();
      expect(orderDocs.docs, isEmpty,
          reason: 'die bereits angelegte erste Bestellung muss kompensierend '
              'geloescht sein (kein Doppel beim Retry)');

      final cartDoc = await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('orderCarts')
          .doc('site-1')
          .get();
      expect(cartDoc.data()!['items'], hasLength(2),
          reason: 'der Korb bleibt fuer einen sauberen Retry vollstaendig');
    });
  });
}
