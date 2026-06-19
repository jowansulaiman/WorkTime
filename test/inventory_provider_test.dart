import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/purchase_order.dart';
import 'package:worktime_app/models/stock_movement.dart';
import 'package:worktime_app/models/supplier.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// Simuliert eine offline/fehlschlagende Cloud: Inventar-Schreibzugriffe werfen,
/// Streams bleiben leer (echte Fake-Firestore).
class _OfflineFirestoreService extends FirestoreService {
  _OfflineFirestoreService({required super.firestore});

  @override
  Future<void> saveProduct(Product product) async {
    throw Exception('offline');
  }
}

void main() {
  // Nicht-Demo-Nutzer, damit _maybeSeedLocalDemo NICHT greift und wir mit
  // leerem lokalen Bestand starten.
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

  group('InventoryProvider – lokaler Modus', () {
    test('weist neuen Lieferanten/Artikeln lokale IDs zu und sortiert', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);

      await provider.saveSupplier(const Supplier(orgId: 'org-1', name: 'Zeta'));
      await provider.saveSupplier(const Supplier(orgId: 'org-1', name: 'Alpha'));
      await provider.saveProduct(
        const Product(orgId: 'org-1', siteId: 'site-1', name: 'Feuerzeug'),
      );

      expect(provider.suppliers, hasLength(2));
      expect(provider.suppliers.first.name, 'Alpha'); // alphabetisch sortiert
      expect(provider.suppliers.every((s) => s.id != null), isTrue);
      expect(provider.products.single.id, isNotNull);
    });

    test('persistiert lokal und stellt nach Neustart wieder her', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveSupplier(
        const Supplier(orgId: 'org-1', name: 'Tabak Nord'),
      );
      await provider.saveProduct(
        const Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Zigaretten',
          currentStock: 5,
        ),
      );

      // Neue Provider-Instanz (gleiche SharedPreferences) = App-Neustart.
      final restored = newLocalProvider();
      await restored.updateSession(user);

      expect(restored.suppliers.single.name, 'Tabak Nord');
      expect(restored.products.single.name, 'Zigaretten');
      expect(restored.products.single.currentStock, 5);
    });

    test('adjustStock bucht eine Bewegung mit korrektem balanceAfter', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveProduct(
        const Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Feuerzeug',
          currentStock: 10,
        ),
      );
      final productId = provider.products.single.id!;

      await provider.adjustStock(productId: productId, delta: -3);

      expect(provider.products.single.currentStock, 7);
      expect(provider.recentMovements.single.quantityDelta, -3);
      expect(provider.recentMovements.single.balanceAfter, 7);
      expect(provider.recentMovements.single.type, StockMovementType.adjustment);

      // Persistenz: Bestand und Bewegung ueberleben den Neustart.
      final restored = newLocalProvider();
      await restored.updateSession(user);
      expect(restored.products.single.currentStock, 7);
      expect(restored.recentMovements, hasLength(1));
    });

    test('savePurchaseOrder vergibt eine lokale Bestellnummer', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);

      final id = await provider.savePurchaseOrder(
        const PurchaseOrder(orgId: 'org-1', siteId: 'site-1', supplierId: 's1'),
      );

      expect(id, isNotEmpty);
      expect(provider.purchaseOrders.single.orderNumber, isNotNull);
      expect(provider.purchaseOrders.single.orderNumber, startsWith('BST-'));
    });

    test('receiveOrder begrenzt die Menge auf den offenen Rest und bucht Bestand',
        () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveProduct(
        const Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Feuerzeug',
          currentStock: 0,
        ),
      );
      final productId = provider.products.single.id!;

      final orderId = await provider.savePurchaseOrder(
        PurchaseOrder(
          orgId: 'org-1',
          siteId: 'site-1',
          supplierId: 's1',
          status: PurchaseOrderStatus.ordered,
          items: [
            PurchaseOrderItem(
              productId: productId,
              name: 'Feuerzeug',
              quantityOrdered: 5,
            ),
          ],
        ),
      );

      // 999 angefragt, aber nur 5 offen -> auf 5 begrenzt.
      await provider.receiveOrder(
        orderId: orderId,
        receivedByItemIndex: const {0: 999},
      );

      final order = provider.purchaseOrders.single;
      expect(order.items.single.quantityReceived, 5);
      expect(order.status, PurchaseOrderStatus.received);
      expect(provider.products.single.currentStock, 5);
      expect(
        provider.recentMovements.first.type,
        StockMovementType.receipt,
      );
    });

    test('abgeleitete Sichten: lowStockProducts, openOrders, buildReorderItems',
        () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveProduct(
        const Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Knapp',
          currentStock: 1,
          minStock: 5,
          supplierId: 'sup-1',
        ),
      );
      await provider.saveProduct(
        const Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Genug',
          currentStock: 50,
          minStock: 5,
        ),
      );

      expect(provider.lowStockProducts(), hasLength(1));
      expect(provider.lowStockProducts().single.name, 'Knapp');

      final reorder = provider.buildReorderItems(
        siteId: 'site-1',
        supplierId: 'sup-1',
      );
      expect(reorder, hasLength(1));
      expect(reorder.single.name, 'Knapp');

      await provider.savePurchaseOrder(
        const PurchaseOrder(
          orgId: 'org-1',
          siteId: 'site-1',
          supplierId: 'sup-1',
          status: PurchaseOrderStatus.ordered,
        ),
      );
      expect(provider.openOrders, hasLength(1));
    });

    test(
        'hybrid-Offline: fehlgeschlagener Cloud-Write wirft nicht und wird '
        'lokal persistiert', () async {
      final offline = _OfflineFirestoreService(firestore: firestore);
      // Kein disableAuthentication -> Hybrid-Modus moeglich.
      final provider = InventoryProvider(firestoreService: offline);
      await provider.updateSession(user, hybridStorageEnabled: true);

      // Darf NICHT werfen (frueher: harter Fehler + Datenverlust).
      await provider.saveProduct(
        const Product(
          id: 'p-offline',
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Offline-Artikel',
        ),
      );

      // Lokaler Fallback hat den Artikel persistiert.
      final persisted = await DatabaseService.loadLocalProducts(
        scope: LocalStorageScope.fromUser(user),
      );
      expect(persisted.any((p) => p.id == 'p-offline'), isTrue);
    });

    test('updateSession(null) setzt den Zustand zurueck', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveProduct(
        const Product(orgId: 'org-1', siteId: 'site-1', name: 'X'),
      );
      expect(provider.products, isNotEmpty);

      await provider.updateSession(null);

      expect(provider.products, isEmpty);
      expect(provider.suppliers, isEmpty);
      expect(provider.purchaseOrders, isEmpty);
    });

    test(
        'surfaceSessionError macht einen Sitzungsfehler sichtbar '
        '(fire-and-forget-updatesession)', () {
      final provider = newLocalProvider();
      var notified = false;
      provider.addListener(() => notified = true);

      provider.surfaceSessionError(StateError('boom'));

      expect(provider.errorMessage, isNotNull);
      expect(notified, isTrue,
          reason: 'die UI muss ueber den Fehler benachrichtigt werden');
    });
  });
}
