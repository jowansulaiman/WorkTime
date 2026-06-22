import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/order_cart.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/purchase_order.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
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
  });
}
