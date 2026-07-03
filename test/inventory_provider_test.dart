import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/cash_closing.dart';
import 'package:worktime_app/models/cash_count.dart';
import 'package:worktime_app/models/customer_order.dart';
import 'package:worktime_app/models/fridge_refill.dart';
import 'package:worktime_app/models/order_cart.dart';
import 'package:worktime_app/models/pos_daily_stat.dart';
import 'package:worktime_app/models/pos_receipt.dart';
import 'package:worktime_app/models/price_history_entry.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/product_batch.dart';
import 'package:worktime_app/models/purchase_order.dart';
import 'package:worktime_app/models/stock_movement.dart';
import 'package:worktime_app/models/supplier.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/repositories/firestore_inventory_repository.dart';
import 'package:worktime_app/repositories/inventory_repository.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// Handgeschriebener Fake (kein Mockito): delegiert an ein echtes
/// FirestoreInventoryRepository, laesst aber saveProduct fehlschlagen, um den
/// hybrid-Offline-Fallback des Providers zu testen. Haengt damit an der
/// InventoryRepository-Abstraktion statt an der konkreten FirestoreService.
class _OfflineInventoryRepository implements InventoryRepository {
  _OfflineInventoryRepository(FakeFirebaseFirestore firestore)
      : _delegate = FirestoreInventoryRepository(firestore: firestore);

  final InventoryRepository _delegate;

  @override
  Future<void> saveProduct(Product product) async {
    throw Exception('offline');
  }

  @override
  Stream<List<Supplier>> watchSuppliers(String orgId) =>
      _delegate.watchSuppliers(orgId);

  @override
  Stream<List<Product>> watchProducts(String orgId) =>
      _delegate.watchProducts(orgId);

  @override
  Stream<List<PurchaseOrder>> watchPurchaseOrders(String orgId) =>
      _delegate.watchPurchaseOrders(orgId);

  @override
  Stream<List<StockMovement>> watchStockMovements(
    String orgId, {
    String? productId,
    String? siteId,
    int limit = 100,
  }) =>
      _delegate.watchStockMovements(
        orgId,
        productId: productId,
        siteId: siteId,
        limit: limit,
      );

  @override
  Future<List<StockMovement>> getStockMovementsInRange(
    String orgId,
    DateTime from,
    DateTime to, {
    String? siteId,
  }) =>
      _delegate.getStockMovementsInRange(orgId, from, to, siteId: siteId);

  @override
  Future<List<PosReceipt>> getPosReceiptsInRange(
    String orgId,
    DateTime from,
    DateTime to, {
    String? siteId,
  }) =>
      _delegate.getPosReceiptsInRange(orgId, from, to, siteId: siteId);

  @override
  Future<List<CashCount>> getCashCountsInRange(
    String orgId,
    DateTime from,
    DateTime to, {
    String? siteId,
  }) =>
      _delegate.getCashCountsInRange(orgId, from, to, siteId: siteId);

  @override
  Future<void> addCashCount(CashCount count) => _delegate.addCashCount(count);

  @override
  Future<List<CashClosing>> getCashClosingsInRange(
    String orgId,
    String fromDay,
    String toDay, {
    String? siteId,
  }) =>
      _delegate.getCashClosingsInRange(orgId, fromDay, toDay, siteId: siteId);

  @override
  Future<void> createCashClosing(CashClosing closing) =>
      _delegate.createCashClosing(closing);

  @override
  Future<void> markCashClosingBooked({
    required String orgId,
    required String closingId,
  }) =>
      _delegate.markCashClosingBooked(orgId: orgId, closingId: closingId);

  @override
  Future<List<PosDailyStat>> getPosDailyStatsInRange(
    String orgId,
    String fromDay,
    String toDay, {
    String? siteId,
  }) =>
      _delegate.getPosDailyStatsInRange(orgId, fromDay, toDay, siteId: siteId);

  @override
  Future<void> deleteSupplier({
    required String orgId,
    required String supplierId,
  }) =>
      _delegate.deleteSupplier(orgId: orgId, supplierId: supplierId);

  @override
  Future<void> saveSupplier(Supplier supplier) =>
      _delegate.saveSupplier(supplier);

  @override
  Future<void> deleteProduct({
    required String orgId,
    required String productId,
  }) =>
      _delegate.deleteProduct(orgId: orgId, productId: productId);

  @override
  Stream<List<ProductBatch>> watchProductBatches(String orgId) =>
      _delegate.watchProductBatches(orgId);

  @override
  Future<void> saveProductBatch(ProductBatch batch) async {
    throw Exception('offline');
  }

  @override
  Future<void> deleteProductBatch({
    required String orgId,
    required String batchId,
  }) =>
      _delegate.deleteProductBatch(orgId: orgId, batchId: batchId);

  @override
  Future<int> adjustProductStock({
    required String orgId,
    required String productId,
    required int delta,
    required StockMovementType type,
    String? reason,
    String? relatedOrderId,
    String? createdByUid,
    String? clientMutationId,
  }) =>
      _delegate.adjustProductStock(
        orgId: orgId,
        productId: productId,
        delta: delta,
        type: type,
        reason: reason,
        relatedOrderId: relatedOrderId,
        createdByUid: createdByUid,
        clientMutationId: clientMutationId,
      );

  @override
  Future<void> setFridgeStock({
    required String orgId,
    required String productId,
    required int fridgeStock,
    required int refilledQty,
    String? createdByUid,
    String? clientMutationId,
  }) =>
      _delegate.setFridgeStock(
        orgId: orgId,
        productId: productId,
        fridgeStock: fridgeStock,
        refilledQty: refilledQty,
        createdByUid: createdByUid,
        clientMutationId: clientMutationId,
      );

  @override
  Future<void> addPriceHistory(PriceHistoryEntry entry) =>
      _delegate.addPriceHistory(entry);

  @override
  Future<List<PriceHistoryEntry>> fetchPriceHistory({
    required String orgId,
    required String productId,
  }) =>
      _delegate.fetchPriceHistory(orgId: orgId, productId: productId);

  @override
  Future<String> savePurchaseOrder(PurchaseOrder order) =>
      _delegate.savePurchaseOrder(order);

  @override
  Future<void> deletePurchaseOrder({
    required String orgId,
    required String orderId,
  }) =>
      _delegate.deletePurchaseOrder(orgId: orgId, orderId: orderId);

  @override
  Stream<List<CustomerOrder>> watchCustomerOrders(String orgId) =>
      _delegate.watchCustomerOrders(orgId);

  @override
  Future<String> saveCustomerOrder(CustomerOrder order) =>
      _delegate.saveCustomerOrder(order);

  @override
  Future<void> deleteCustomerOrder({
    required String orgId,
    required String orderId,
  }) =>
      _delegate.deleteCustomerOrder(orgId: orgId, orderId: orderId);

  @override
  Future<void> receivePurchaseOrder({
    required String orgId,
    required String orderId,
    required Map<int, int> receivedByItemIndex,
    String? createdByUid,
    String? clientMutationId,
  }) =>
      _delegate.receivePurchaseOrder(
        orgId: orgId,
        orderId: orderId,
        receivedByItemIndex: receivedByItemIndex,
        createdByUid: createdByUid,
        clientMutationId: clientMutationId,
      );

  @override
  Stream<List<SiteOrderList>> watchOrderCarts(String orgId) =>
      _delegate.watchOrderCarts(orgId);

  @override
  Stream<List<SiteOrderList>> watchWeeklyOrderLists(String orgId) =>
      _delegate.watchWeeklyOrderLists(orgId);

  @override
  Future<void> saveOrderList(SiteOrderList list) =>
      _delegate.saveOrderList(list);

  @override
  Future<void> deleteOrderList({
    required String orgId,
    required String siteId,
    required OrderListKind kind,
  }) =>
      _delegate.deleteOrderList(orgId: orgId, siteId: siteId, kind: kind);

  @override
  Stream<List<FridgeRefillList>> watchFridgeRefillLists(String orgId) =>
      _delegate.watchFridgeRefillLists(orgId);

  @override
  Future<void> saveFridgeRefillList(FridgeRefillList list) =>
      _delegate.saveFridgeRefillList(list);

  @override
  Future<void> deleteFridgeRefillList({
    required String orgId,
    required String siteId,
  }) =>
      _delegate.deleteFridgeRefillList(orgId: orgId, siteId: siteId);
}

/// Fake fuer den Cloud-Stream-Fehlerpfad: der Lieferanten-Stream schlaegt fehl,
/// die uebrigen Streams liefern (leere) Daten. Prueft, dass onError den
/// errorMessage setzt statt zu crashen (inventory-firestore-fallback-untested).
class _StreamErrorInventoryRepository extends _OfflineInventoryRepository {
  _StreamErrorInventoryRepository(super.firestore);

  @override
  Stream<List<Supplier>> watchSuppliers(String orgId) =>
      Stream<List<Supplier>>.error(
        StateError('Lieferanten-Stream fehlgeschlagen'),
      );
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

    test('saveBatch/resolveBatch: MHD-Charge, Warnung, Erledigen, Persistenz',
        () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      final now = DateTime(2026, 7, 1, 9);
      await provider.saveBatch(
        ProductBatch(
          orgId: 'org-1',
          siteId: 'site-1',
          productId: 'p-1',
          productName: 'Cola 0,33l',
          expiryDate: DateTime(2026, 7, 2), // morgen → Warnung
        ),
      );
      await provider.saveBatch(
        ProductBatch(
          orgId: 'org-1',
          siteId: 'site-1',
          productId: 'p-2',
          productName: 'Snack',
          expiryDate: DateTime(2026, 8, 1), // weit weg → keine Warnung
        ),
      );

      expect(provider.productBatches, hasLength(2));
      expect(provider.productBatches.every((b) => b.id != null), isTrue);

      final warnings = provider.expiryWarnings(now: now, leadDays: 3);
      expect(warnings.map((w) => w.batch.productName).toList(), ['Cola 0,33l']);
      expect(provider.expiryWarningCount(now: now), 1);

      // Als abverkauft markieren → verschwindet aus der Warnung, bleibt in der
      // Historie.
      final colaId = warnings.single.batch.id!;
      await provider.resolveBatch(colaId, status: BatchStatus.soldOut);
      expect(provider.expiryWarnings(now: now), isEmpty);
      expect(
        provider.productBatches.firstWhere((b) => b.id == colaId).status,
        BatchStatus.soldOut,
      );

      // App-Neustart: Chargen bleiben lokal persistiert.
      final restored = newLocalProvider();
      await restored.updateSession(user);
      expect(restored.productBatches, hasLength(2));
      expect(restored.expiryWarnings(now: now), isEmpty);
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

    test(
      'refillFridge fuellt auf Soll, bucht fridgeRefill-Bewegung, laesst currentStock',
      () async {
        final provider = newLocalProvider();
        await provider.updateSession(user);
        await provider.saveProduct(
          const Product(
            orgId: 'org-1',
            siteId: 'site-1',
            name: 'Cola',
            currentStock: 30,
            inFridge: true,
            fridgeTargetStock: 24,
          ),
        );
        final product = provider.products.single;
        expect(product.fridgeStock, 0); // neue Artikel starten leer

        await provider.refillFridge(product);

        final refilled = provider.products.single;
        expect(refilled.fridgeStock, 24); // auf Soll gesetzt
        expect(refilled.currentStock, 30); // Gesamtbestand UNVERAENDERT
        expect(refilled.warehouseStock, 6); // 30 - 24
        expect(refilled.fridgeNeedsRefill, isFalse);

        final move = provider.recentMovements.single;
        expect(move.type, StockMovementType.fridgeRefill);
        expect(move.quantityDelta, 24);
        expect(move.balanceAfter, 24);

        // Ueberlebt den Neustart.
        final reloaded = newLocalProvider();
        await reloaded.updateSession(user);
        expect(reloaded.products.single.fridgeStock, 24);
      },
    );

    test(
      'saveProduct laesst fridgeStock nach dem Nachfuellen unangetastet (Clobber)',
      () async {
        final provider = newLocalProvider();
        await provider.updateSession(user);
        await provider.saveProduct(
          const Product(
            orgId: 'org-1',
            siteId: 'site-1',
            name: 'Cola',
            currentStock: 30,
            inFridge: true,
            fridgeTargetStock: 24,
          ),
        );
        await provider.refillFridge(provider.products.single);
        expect(provider.products.single.fridgeStock, 24);

        // Manager editiert den Artikel mit einem STALE Objekt (fridgeStock 0).
        final stale = provider.products.single
            .copyWith(fridgeStock: 0, name: 'Cola 0,5l');
        await provider.saveProduct(stale);

        expect(provider.products.single.name, 'Cola 0,5l');
        expect(provider.products.single.fridgeStock, 24); // erhalten
      },
    );

    test('issueStock blockt Bestandsueberzug und bucht sonst einen Abgang',
        () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveProduct(
        const Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Feuerzeug',
          currentStock: 5,
        ),
      );
      final product = provider.products.single;

      // Ueberzug -> harte Sperre, Bestand bleibt, keine Bewegung.
      final error = await provider.issueStock(product: product, quantity: 8);
      expect(error, isNotNull);
      expect(provider.products.single.currentStock, 5);
      expect(provider.recentMovements, isEmpty);

      // Gueltiger Abgang -> gebucht als issue.
      final ok = await provider.issueStock(
        product: provider.products.single,
        quantity: 3,
        reason: 'Verkauf',
      );
      expect(ok, isNull);
      expect(provider.products.single.currentStock, 2);
      expect(provider.recentMovements.single.quantityDelta, -3);
      expect(provider.recentMovements.single.type, StockMovementType.issue);
      expect(provider.recentMovements.single.reason, 'Verkauf');
    });

    test('transferStock lagert zwischen Standorten um (gepaart)', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveProduct(
        const Product(
          orgId: 'org-1',
          siteId: 'site-1',
          siteName: 'Strichmännchen',
          name: 'Feuerzeug',
          currentStock: 10,
        ),
      );
      await provider.saveProduct(
        const Product(
          orgId: 'org-1',
          siteId: 'site-2',
          siteName: 'Tabak Börse',
          name: 'Feuerzeug',
          currentStock: 2,
        ),
      );
      final from = provider.products.firstWhere((p) => p.siteId == 'site-1');
      final to = provider.products.firstWhere((p) => p.siteId == 'site-2');

      // Überzug -> Sperre.
      expect(
        await provider.transferStock(from: from, to: to, quantity: 99),
        isNotNull,
      );

      final ok = await provider.transferStock(from: from, to: to, quantity: 4);
      expect(ok, isNull);
      expect(
        provider.products.firstWhere((p) => p.siteId == 'site-1').currentStock,
        6,
      );
      expect(
        provider.products.firstWhere((p) => p.siteId == 'site-2').currentStock,
        6,
      );
      // Zwei gepaarte transfer-Bewegungen.
      final transfers = provider.recentMovements
          .where((m) => m.type == StockMovementType.transfer)
          .toList();
      expect(transfers, hasLength(2));
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

    test('abgeleitete Sichten: lowStockProducts, openOrders', () async {
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

    test('Warenwert/Marge: Aggregation gesamt und je Standort', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveProduct(
        const Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'A',
          currentStock: 10,
          purchasePriceCents: 100,
          sellingPriceCents: 150,
        ),
      );
      await provider.saveProduct(
        const Product(
          orgId: 'org-1',
          siteId: 'site-2',
          name: 'B',
          currentStock: 5,
          purchasePriceCents: 200,
          sellingPriceCents: 260,
        ),
      );
      // Ohne Preis -> traegt 0 zum Warenwert bei.
      await provider.saveProduct(
        const Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'C',
          currentStock: 7,
        ),
      );

      // Gesamt: 10*100 + 5*200 = 2000 EK.
      expect(provider.totalStockValuePurchaseCents(), 2000);
      // Gesamt VK: 10*150 + 5*260 = 2800; Spanne = 800.
      expect(provider.totalStockValueSellingCents(), 2800);
      expect(provider.totalStockMarginCents(), 800);
      // Je Standort site-1: nur A (C hat keinen Preis).
      expect(provider.totalStockValuePurchaseCents(siteId: 'site-1'), 1000);
      expect(provider.totalStockMarginCents(siteId: 'site-1'), 500);
    });

    test(
        'hybrid-Offline: fehlgeschlagener Cloud-Write wirft nicht und wird '
        'lokal persistiert', () async {
      // Kein disableAuthentication -> Hybrid-Modus moeglich.
      final provider = InventoryProvider(
        firestoreService: firestoreService,
        inventoryRepository: _OfflineInventoryRepository(firestore),
      );
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

  group('InventoryProvider – Cloud-Modus', () {
    test(
        'Stream-onError setzt errorMessage und crasht nicht '
        '(inventory-firestore-fallback-untested)', () async {
      final provider = InventoryProvider(
        firestoreService: firestoreService,
        inventoryRepository: _StreamErrorInventoryRepository(firestore),
      );
      var notified = false;
      provider.addListener(() => notified = true);

      // Reiner Cloud-Modus (kein local/hybrid) -> Firestore-Subscriptions starten.
      await provider.updateSession(user, localStorageOnly: false);
      // Fehler-Event des Streams asynchron durchlaufen lassen.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.errorMessage, isNotNull);
      expect(
        provider.errorMessage,
        contains('Lieferanten-Stream fehlgeschlagen'),
      );
      expect(notified, isTrue);
    });
  });
}
