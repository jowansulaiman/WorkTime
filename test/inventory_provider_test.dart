import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/cash_closing.dart';
import 'package:worktime_app/models/cash_count.dart';
import 'package:worktime_app/models/customer_order.dart';
import 'package:worktime_app/models/delivery_advice.dart';
import 'package:worktime_app/models/fridge_refill.dart';
import 'package:worktime_app/models/order_cart.dart';
import 'package:worktime_app/models/pos_daily_stat.dart';
import 'package:worktime_app/models/pos_receipt.dart';
import 'package:worktime_app/models/price_history_entry.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/scan_event.dart';
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
  Future<String> saveProduct(Product product) async {
    throw FirebaseException(plugin: 'firestore', code: 'unavailable');
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
    throw FirebaseException(plugin: 'firestore', code: 'unavailable');
  }

  @override
  Future<void> deleteProductBatch({
    required String orgId,
    required String batchId,
  }) =>
      _delegate.deleteProductBatch(orgId: orgId, batchId: batchId);

  @override
  Stream<List<DeliveryAdvice>> watchDeliveryAdvices(String orgId) =>
      _delegate.watchDeliveryAdvices(orgId);

  @override
  Future<void> saveDeliveryAdvice(DeliveryAdvice advice) =>
      _delegate.saveDeliveryAdvice(advice);

  @override
  Future<void> deleteDeliveryAdvice({
    required String orgId,
    required String adviceId,
  }) =>
      _delegate.deleteDeliveryAdvice(orgId: orgId, adviceId: adviceId);

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
  Future<int> setProductStock({
    required String orgId,
    required String productId,
    required int newStock,
    StockMovementType type = StockMovementType.stocktake,
    String? reason,
    String? createdByUid,
    String? clientMutationId,
  }) =>
      _delegate.setProductStock(
        orgId: orgId,
        productId: productId,
        newStock: newStock,
        type: type,
        reason: reason,
        createdByUid: createdByUid,
        clientMutationId: clientMutationId,
      );

  @override
  Future<void> transferProductStock({
    required String orgId,
    required String fromProductId,
    required String toProductId,
    required int quantity,
    String? fromReason,
    String? toReason,
    String? createdByUid,
    String? clientMutationId,
  }) =>
      _delegate.transferProductStock(
        orgId: orgId,
        fromProductId: fromProductId,
        toProductId: toProductId,
        quantity: quantity,
        fromReason: fromReason,
        toReason: toReason,
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
  Future<void> addScanEvent(ScanEvent event) => _delegate.addScanEvent(event);

  @override
  Future<List<ScanEvent>> fetchScanEvents(String orgId, {int limit = 500}) =>
      _delegate.fetchScanEvents(orgId, limit: limit);

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
  Future<PurchaseOrder> closePurchaseOrderRemainder({
    required String orgId,
    required String orderId,
    required String reason,
  }) =>
      _delegate.closePurchaseOrderRemainder(
        orgId: orgId,
        orderId: orderId,
        reason: reason,
      );

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
    required Map<int, PurchaseReceiptLine> receivedByItemIndex,
    String? deliveryNoteNumber,
    String? createdByUid,
    String? clientMutationId,
  }) =>
      _delegate.receivePurchaseOrder(
        orgId: orgId,
        orderId: orderId,
        receivedByItemIndex: receivedByItemIndex,
        deliveryNoteNumber: deliveryNoteNumber,
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

/// #48: Nur der Bestellkorb-Stream schlaegt fehl — die uebrige Warenwirtschaft
/// darf davon nicht in den globalen Fehlerzustand gerissen werden.
class _OrderCartStreamErrorRepository extends _OfflineInventoryRepository {
  _OrderCartStreamErrorRepository(super.firestore);

  @override
  Stream<List<SiteOrderList>> watchOrderCarts(String orgId) =>
      Stream<List<SiteOrderList>>.error(
        StateError('orderCarts-Stream fehlgeschlagen'),
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
        receivedByItemIndex: const {0: PurchaseReceiptLine(quantity: 999)},
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

    test(
      'Rest schließen bewahrt Ist-Mengen und blockiert weiteren Wareneingang',
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
                quantityOrdered: 10,
                unitPriceCents: 100,
              ),
            ],
          ),
        );

        await provider.receiveOrder(
          orderId: orderId,
          receivedByItemIndex: const {0: PurchaseReceiptLine(quantity: 4)},
        );
        await provider.closePurchaseOrderRemainder(
          orderId: orderId,
          reason: '  Lieferant kann den Rest nicht liefern  ',
        );

        final closed = provider.purchaseOrders.single;
        expect(closed.status, PurchaseOrderStatus.received);
        expect(closed.items.single.quantityReceived, 4);
        expect(closed.closedAt, isNotNull);
        expect(closed.closedReason, 'Lieferant kann den Rest nicht liefern');
        expect(closed.receivedAt, isNull);
        expect(closed.deliveredTotalCents, 400);
        expect(provider.products.single.currentStock, 4);
        expect(provider.recentMovements, hasLength(1));

        await expectLater(
          provider.receiveOrder(
            orderId: orderId,
            receivedByItemIndex: const {0: PurchaseReceiptLine(quantity: 6)},
          ),
          throwsA(isA<StateError>()),
        );
        expect(provider.purchaseOrders.single.items.single.quantityReceived, 4);
        expect(provider.products.single.currentStock, 4);
        expect(provider.recentMovements, hasLength(1));
      },
    );

    test('Rest schließen verlangt Begründung und mindestens einen Eingang',
        () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      final orderId = await provider.savePurchaseOrder(
        const PurchaseOrder(
          orgId: 'org-1',
          siteId: 'site-1',
          supplierId: 's1',
          status: PurchaseOrderStatus.ordered,
          items: [PurchaseOrderItem(name: 'Ware', quantityOrdered: 10)],
        ),
      );

      await expectLater(
        provider.closePurchaseOrderRemainder(orderId: orderId, reason: '   '),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        provider.closePurchaseOrderRemainder(
          orderId: orderId,
          reason: 'Nicht lieferbar',
        ),
        throwsA(isA<StateError>()),
      );
      expect(provider.purchaseOrders.single.status, PurchaseOrderStatus.ordered);
      expect(provider.purchaseOrders.single.closedAt, isNull);
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

    test(
      'unterwegs-Mengen beachten Status, Standort, Summierung und Mengen-Clamp',
      () async {
        final provider = newLocalProvider();
        await provider.updateSession(user);
        await provider.saveProduct(
          const Product(
            orgId: 'org-1',
            siteId: 'site-1',
            name: 'Teilgedeckt',
            currentStock: 1,
            minStock: 5,
            targetStock: 10,
          ),
        );
        await provider.saveProduct(
          const Product(
            orgId: 'org-1',
            siteId: 'site-1',
            name: 'Voll gedeckt',
            currentStock: 1,
            minStock: 5,
            targetStock: 10,
          ),
        );
        await provider.saveProduct(
          const Product(
            orgId: 'org-1',
            siteId: 'site-2',
            name: 'Anderer Standort',
            currentStock: 1,
            minStock: 5,
            targetStock: 10,
          ),
        );
        final partialId = provider.products
            .firstWhere((product) => product.name == 'Teilgedeckt')
            .id!;
        final coveredId = provider.products
            .firstWhere((product) => product.name == 'Voll gedeckt')
            .id!;
        final otherSiteId = provider.products
            .firstWhere((product) => product.name == 'Anderer Standort')
            .id!;

        Future<void> saveOrder({
          required String siteId,
          required PurchaseOrderStatus status,
          required List<PurchaseOrderItem> items,
        }) =>
            provider.savePurchaseOrder(
              PurchaseOrder(
                orgId: 'org-1',
                siteId: siteId,
                supplierId: 'sup-1',
                status: status,
                items: items,
              ),
            );

        await saveOrder(
          siteId: 'site-1',
          status: PurchaseOrderStatus.ordered,
          items: [
            PurchaseOrderItem(
              productId: partialId,
              name: 'Teilgedeckt',
              quantityOrdered: 4,
              quantityReceived: 2,
            ),
            PurchaseOrderItem(
              productId: coveredId,
              name: 'Voll gedeckt',
              quantityOrdered: 5,
            ),
            const PurchaseOrderItem(
              productId: '',
              name: 'Ohne ID',
              quantityOrdered: 99,
            ),
            const PurchaseOrderItem(
              name: 'Ohne Produktbezug',
              quantityOrdered: 99,
            ),
            PurchaseOrderItem(
              productId: partialId,
              name: 'Überliefert',
              quantityOrdered: 2,
              quantityReceived: 7,
            ),
          ],
        );
        await saveOrder(
          siteId: 'site-1',
          status: PurchaseOrderStatus.partiallyReceived,
          items: [
            PurchaseOrderItem(
              productId: partialId,
              name: 'Teilgedeckt',
              quantityOrdered: 3,
              quantityReceived: 2,
            ),
            PurchaseOrderItem(
              productId: coveredId,
              name: 'Voll gedeckt',
              quantityOrdered: 3,
              quantityReceived: 1,
            ),
          ],
        );
        for (final status in [
          PurchaseOrderStatus.draft,
          PurchaseOrderStatus.received,
          PurchaseOrderStatus.cancelled,
        ]) {
          await saveOrder(
            siteId: 'site-1',
            status: status,
            items: [
              PurchaseOrderItem(
                productId: partialId,
                name: 'Nicht unterwegs',
                quantityOrdered: 50,
              ),
            ],
          );
        }
        await saveOrder(
          siteId: 'site-2',
          status: PurchaseOrderStatus.ordered,
          items: [
            PurchaseOrderItem(
              productId: otherSiteId,
              name: 'Anderer Standort',
              quantityOrdered: 7,
            ),
          ],
        );

        final allIncoming = provider.incomingQuantityByProductId();
        final siteOneIncoming = provider.incomingQuantityByProductId(
          siteId: 'site-1',
        );
        final siteTwoIncoming = provider.incomingQuantityByProductId(
          siteId: 'site-2',
        );

        expect(allIncoming[partialId], 3);
        expect(allIncoming[coveredId], 7);
        expect(allIncoming[otherSiteId], 7);
        expect(siteOneIncoming[partialId], 3);
        expect(siteOneIncoming[coveredId], 7);
        expect(siteOneIncoming, isNot(contains(otherSiteId)));
        expect(siteTwoIncoming, {otherSiteId: 7});
        expect(siteOneIncoming, isNot(contains('')));

        final partial = provider.products.firstWhere(
          (product) => product.id == partialId,
        );
        final covered = provider.products.firstWhere(
          (product) => product.id == coveredId,
        );
        expect(provider.needsReorderAfterIncoming(partial), isTrue);
        expect(provider.needsReorderAfterIncoming(covered), isFalse);
        expect(provider.lowStockProducts(siteId: 'site-1').map((p) => p.id), [
          partialId,
        ]);
        expect(provider.suggestedReorderQuantityAfterIncoming(partial), 6);
        expect(provider.suggestedReorderQuantityAfterIncoming(covered), 0);

        final fixedLotStillBelowThreshold = partial.copyWith(
          currentStock: 0,
          minStock: 10,
          reorderQuantity: 3,
        );
        expect(
          provider.suggestedReorderQuantityAfterIncoming(
            fixedLotStillBelowThreshold,
          ),
          3,
        );
      },
    );

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

  group('InventoryProvider – Umlagerung/Bewegungen/Bestellnummern (lokal)', () {
    test('lokale Bestellnummern kollidieren nach einer Löschung nicht',
        () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);

      PurchaseOrder newOrder() => const PurchaseOrder(
            orgId: 'org-1',
            siteId: 'site-1',
            supplierId: 'sup-1',
            supplierName: 'Tabak Nord',
          );

      final firstId = await provider.savePurchaseOrder(newOrder());
      await provider.savePurchaseOrder(newOrder());
      final numbersBefore =
          provider.purchaseOrders.map((o) => o.orderNumber).toSet();
      expect(numbersBefore, hasLength(2));

      // Erste Bestellung löschen -> die Listenlänge sinkt; die nächste Nummer
      // darf trotzdem NICHT mit einer bestehenden kollidieren (max+1 statt
      // Listenlänge+1).
      await provider.deletePurchaseOrder(firstId);
      await provider.savePurchaseOrder(newOrder());

      final numbers =
          provider.purchaseOrders.map((o) => o.orderNumber).whereType<String>();
      expect(numbers.toSet().length, numbers.length,
          reason: 'Bestellnummern müssen eindeutig bleiben');
    });

    test('movementsForProduct liefert nur Bewegungen des Artikels', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveProduct(const Product(
        orgId: 'org-1',
        siteId: 'site-1',
        name: 'Cola',
        currentStock: 10,
      ));
      await provider.saveProduct(const Product(
        orgId: 'org-1',
        siteId: 'site-1',
        name: 'Fanta',
        currentStock: 10,
      ));
      final cola = provider.products.firstWhere((p) => p.name == 'Cola');
      final fanta = provider.products.firstWhere((p) => p.name == 'Fanta');
      await provider.adjustStock(productId: cola.id!, delta: 3);
      await provider.adjustStock(productId: fanta.id!, delta: -2);
      await provider.adjustStock(productId: cola.id!, delta: -1);

      final movements = await provider.movementsForProduct(cola.id!);
      expect(movements, hasLength(2));
      expect(movements.every((m) => m.productId == cola.id), isTrue);
      // Neueste zuerst.
      expect(movements.first.quantityDelta, -1);
      expect(movements.last.quantityDelta, 3);
    });

    test(
        'transferStockToSite legt den Zielartikel automatisch an und bucht '
        'die Umlagerung', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveProduct(const Product(
        orgId: 'org-1',
        siteId: 'site-1',
        siteName: 'Strichmännchen',
        name: 'Feuerzeug',
        barcode: '4001234',
        category: 'Zubehör',
        sellingPriceCents: 199,
        currentStock: 10,
        minStock: 2,
      ));
      final source = provider.products.single;

      final error = await provider.transferStockToSite(
        from: source,
        toSiteId: 'site-2',
        toSiteName: 'Tabak Börse',
        quantity: 4,
      );

      expect(error, isNull);
      final created = provider.products
          .firstWhere((p) => p.siteId == 'site-2' && p.name == 'Feuerzeug');
      // Stammdaten übernommen, Bestand = umgelagerte Menge.
      expect(created.barcode, '4001234');
      expect(created.category, 'Zubehör');
      expect(created.sellingPriceCents, 199);
      expect(created.minStock, 2);
      expect(created.currentStock, 4);
      expect(
        provider.products.firstWhere((p) => p.id == source.id).currentStock,
        6,
      );
      // Gepaarte transfer-Bewegungen (Abgang Quelle, Zugang Ziel).
      final transfers = provider.recentMovements
          .where((m) => m.type == StockMovementType.transfer)
          .toList();
      expect(transfers, hasLength(2));
    });

    test(
        'transferStockToSite nutzt einen vorhandenen Zielartikel '
        '(Barcode-Match) statt ein Duplikat anzulegen', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveProduct(const Product(
        orgId: 'org-1',
        siteId: 'site-1',
        name: 'Feuerzeug',
        barcode: '4001234',
        currentStock: 10,
      ));
      await provider.saveProduct(const Product(
        orgId: 'org-1',
        siteId: 'site-2',
        name: 'Feuerzeug rot', // anderer Name, gleicher Barcode
        barcode: '4001234',
        currentStock: 1,
      ));
      final source =
          provider.products.firstWhere((p) => p.siteId == 'site-1');

      final error = await provider.transferStockToSite(
        from: source,
        toSiteId: 'site-2',
        quantity: 2,
      );

      expect(error, isNull);
      expect(
        provider.products.where((p) => p.siteId == 'site-2'),
        hasLength(1),
        reason: 'kein Duplikat am Zielstandort',
      );
      expect(
        provider.products
            .firstWhere((p) => p.siteId == 'site-2')
            .currentStock,
        3,
      );
    });

    test('transferStockToSite validiert Menge gegen den Quellbestand',
        () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveProduct(const Product(
        orgId: 'org-1',
        siteId: 'site-1',
        name: 'Feuerzeug',
        currentStock: 3,
      ));
      final source = provider.products.single;

      final error = await provider.transferStockToSite(
        from: source,
        toSiteId: 'site-2',
        quantity: 5,
      );

      expect(error, isNotNull);
      expect(provider.products, hasLength(1),
          reason: 'bei Fehler darf kein Zielartikel entstehen');
      expect(provider.products.single.currentStock, 3);
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

    test(
        'saveProduct ueberschreibt currentStock eines bestehenden Artikels '
        'nicht (H8 Lost-Update)', () async {
      final provider = InventoryProvider(
        firestoreService: firestoreService,
        inventoryRepository: FirestoreInventoryRepository(firestore: firestore),
      );
      addTearDown(provider.dispose);
      await provider.updateSession(user, localStorageOnly: false);

      // Neuanlage: Anfangsbestand MUSS persistiert werden.
      await provider.saveProduct(const Product(
        id: 'p-1',
        orgId: 'org-1',
        siteId: 'site-1',
        siteName: 'Tabak Börse',
        name: 'Pueblo',
        unit: 'Stück',
        currentStock: 10,
        purchasePriceCents: 200,
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final productDoc =
          firestore.collection('organizations').doc('org-1').collection('products');
      expect((await productDoc.doc('p-1').get()).data()!['currentStock'], 10);

      // Paralleler Verkauf (POS/Server): Bestand sinkt auf 9.
      await productDoc.doc('p-1').update({'currentStock': 9});

      // Manager speichert mit eingefrorenem UI-Stand (currentStock 10, neuer
      // Preis): der Serverbestand darf NICHT auf 10 zurueckspringen.
      await provider.saveProduct(const Product(
        id: 'p-1',
        orgId: 'org-1',
        siteId: 'site-1',
        siteName: 'Tabak Börse',
        name: 'Pueblo',
        unit: 'Stück',
        currentStock: 10,
        purchasePriceCents: 250,
      ));
      await Future<void>.delayed(Duration.zero);

      final data = (await productDoc.doc('p-1').get()).data()!;
      expect(data['currentStock'], 9,
          reason: 'die parallel verkaufte Einheit darf nicht als '
              'Phantombestand wiederauferstehen');
      expect(data['purchasePriceCents'], 250,
          reason: 'die eigentliche Aenderung (Preis) muss ankommen');
    });

    test(
        'recordStocktake landet auf dem GEZAEHLTEN Wert, auch wenn das '
        'UI-Objekt veraltet ist (H9)', () async {
      final provider = InventoryProvider(
        firestoreService: firestoreService,
        inventoryRepository: FirestoreInventoryRepository(firestore: firestore),
      );
      addTearDown(provider.dispose);
      await provider.updateSession(user, localStorageOnly: false);

      await provider.saveProduct(const Product(
        id: 'p-1',
        orgId: 'org-1',
        siteId: 'site-1',
        siteName: 'Tabak Börse',
        name: 'Pueblo',
        unit: 'Stück',
        currentStock: 10,
      ));
      await Future<void>.delayed(Duration.zero);

      final productDoc =
          firestore.collection('organizations').doc('org-1').collection('products');
      // Paralleler Abgang: Server ist bei 9, das UI-Objekt kennt noch 10.
      await productDoc.doc('p-1').update({'currentStock': 9});

      const staleUiProduct = Product(
        id: 'p-1',
        orgId: 'org-1',
        siteId: 'site-1',
        siteName: 'Tabak Börse',
        name: 'Pueblo',
        unit: 'Stück',
        currentStock: 10,
      );
      await provider.recordStocktake(
        product: staleUiProduct,
        countedStock: 7,
      );
      await Future<void>.delayed(Duration.zero);

      expect((await productDoc.doc('p-1').get()).data()!['currentStock'], 7,
          reason: 'Inventur muss ABSOLUT auf den gezaehlten Wert setzen '
              '(alte Delta-Rechnung landete bei 6)');

      final movements = await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('stockMovements')
          .get();
      final stocktake = movements.docs
          .map((doc) => doc.data())
          .where((data) => data['type'] == 'stocktake')
          .toList();
      expect(stocktake, hasLength(1));
      expect(stocktake.single['quantityDelta'], -2,
          reason: 'Delta muss aus dem frischen Serverstand (9 -> 7) stammen');
      expect(stocktake.single['balanceAfter'], 7);
    });

    test(
        'transferStock bucht Quelle+Ziel atomar; unzureichender Bestand '
        'bucht NICHTS (H10)', () async {
      final provider = InventoryProvider(
        firestoreService: firestoreService,
        inventoryRepository: FirestoreInventoryRepository(firestore: firestore),
      );
      addTearDown(provider.dispose);
      await provider.updateSession(user, localStorageOnly: false);

      const source = Product(
        id: 'p-quelle',
        orgId: 'org-1',
        siteId: 'site-1',
        siteName: 'Strichmaennchen',
        name: 'Pueblo',
        unit: 'Stück',
        currentStock: 5,
      );
      const target = Product(
        id: 'p-ziel',
        orgId: 'org-1',
        siteId: 'site-2',
        siteName: 'Tabak Börse',
        name: 'Pueblo',
        unit: 'Stück',
        currentStock: 1,
      );
      await provider.saveProduct(source);
      await provider.saveProduct(target);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final error = await provider.transferStock(
        from: source,
        to: target,
        quantity: 2,
      );
      expect(error, isNull);

      final products =
          firestore.collection('organizations').doc('org-1').collection('products');
      expect((await products.doc('p-quelle').get()).data()!['currentStock'], 3);
      expect((await products.doc('p-ziel').get()).data()!['currentStock'], 3);

      final movements = await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('stockMovements')
          .get();
      final transfers = movements.docs
          .map((doc) => doc.data())
          .where((data) => data['type'] == 'transfer')
          .toList();
      expect(transfers, hasLength(2),
          reason: 'Abgang UND Zugang muessen als Bewegung protokolliert sein');

      // Fehlerfall: das (veraltete) UI-Objekt kennt noch Bestand 5, der Server
      // steht nach der ersten Umlagerung bei 3 -> der Client-Vorabcheck laesst
      // Menge 4 durch, die TRANSAKTION muss ablehnen und darf NICHTS buchen
      // (vorher konnte die Quelle belastet bleiben, wenn das Ziel scheiterte).
      final tooMuch = await provider.transferStock(
        from: source,
        to: target,
        quantity: 4,
      );
      expect(tooMuch, isNotNull);
      expect(tooMuch, contains('uebersteigt'));
      expect((await products.doc('p-quelle').get()).data()!['currentStock'], 3,
          reason: 'fehlgeschlagene Umlagerung darf die Quelle nicht belasten');
      expect((await products.doc('p-ziel').get()).data()!['currentStock'], 3);
    });

    test(
        'Bestellkorb-Stream-Fehler setzt nur orderListsLoadFailed, nicht die '
        'globale errorMessage (#48)', () async {
      final provider = InventoryProvider(
        firestoreService: firestoreService,
        inventoryRepository: _OrderCartStreamErrorRepository(firestore),
      );

      await provider.updateSession(user, localStorageOnly: false);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.orderListsLoadFailed, isTrue,
          reason: 'Korb-UI muss den Ladefehler erkennen koennen');
      expect(provider.errorMessage, isNull,
          reason: 'ein Korb-Teilausfall darf nicht die gesamte '
              'Warenwirtschaft als fehlerhaft markieren');
    });
  });

  group('expectedDeliveries (WW-3)', () {
    Future<InventoryProvider> providerWithOrders() async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      Future<void> save(PurchaseOrder order) =>
          provider.savePurchaseOrder(order);

      final today = DateTime.now();
      final todayNoon =
          DateTime(today.year, today.month, today.day, 12);
      // offen + Termin heute (site-1)
      await save(PurchaseOrder(
        orgId: 'org-1',
        siteId: 'site-1',
        supplierId: 'sup-1',
        status: PurchaseOrderStatus.ordered,
        expectedAt: todayNoon,
        items: const [PurchaseOrderItem(name: 'A', quantityOrdered: 1)],
      ));
      // offen + Termin morgen (site-1)
      await save(PurchaseOrder(
        orgId: 'org-1',
        siteId: 'site-1',
        supplierId: 'sup-1',
        status: PurchaseOrderStatus.ordered,
        expectedAt: todayNoon.add(const Duration(days: 1)),
        items: const [PurchaseOrderItem(name: 'B', quantityOrdered: 1)],
      ));
      // offen + Termin heute (site-2)
      await save(PurchaseOrder(
        orgId: 'org-1',
        siteId: 'site-2',
        supplierId: 'sup-1',
        status: PurchaseOrderStatus.ordered,
        expectedAt: todayNoon,
        items: const [PurchaseOrderItem(name: 'C', quantityOrdered: 1)],
      ));
      // Entwurf mit Termin heute → nicht pending
      await save(PurchaseOrder(
        orgId: 'org-1',
        siteId: 'site-1',
        supplierId: 'sup-1',
        status: PurchaseOrderStatus.draft,
        expectedAt: todayNoon,
        items: const [PurchaseOrderItem(name: 'D', quantityOrdered: 1)],
      ));
      return provider;
    }

    test('day-Filter liefert nur heutige offene Termine, site-gescoped',
        () async {
      final provider = await providerWithOrders();
      final heuteSite1 = provider.expectedDeliveries(
        day: DateTime.now(),
        siteId: 'site-1',
      );
      // nur die „heute"-Bestellung von site-1 (nicht morgen, nicht site-2,
      // nicht der Entwurf)
      expect(heuteSite1, hasLength(1));
      expect(heuteSite1.single.items.single.name, 'A');
    });

    test('ohne day-Filter alle offenen Termine, nach Datum sortiert', () async {
      final provider = await providerWithOrders();
      final alleSite1 = provider.expectedDeliveries(siteId: 'site-1');
      expect(alleSite1.map((o) => o.items.single.name), ['A', 'B']);
      // org-weit ohne site-Filter: A, C (heute) + B (morgen) = 3
      final alle = provider.expectedDeliveries();
      expect(alle, hasLength(3));
    });
  });
}
