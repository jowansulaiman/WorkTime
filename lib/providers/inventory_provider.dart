import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/local_demo_data.dart';
import '../models/app_user.dart';
import '../models/product.dart';
import '../models/purchase_order.dart';
import '../models/stock_movement.dart';
import '../models/supplier.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';

/// Verwaltet die Warenwirtschaft: Lieferanten, Artikel, Bestellungen und
/// Bestandsbewegungen einer Organisation.
///
/// Im Cloud-/Hybridmodus werden die Daten ueber Firestore-Streams geladen
/// (Offline-Cache aktiv). Im lokalen Entwicklungsmodus ([AppConfig.disableAuthentication]
/// bzw. localStorageOnly) werden sie im Speicher gehalten, damit die App auch
/// ohne Firebase nutzbar bleibt.
class InventoryProvider extends ChangeNotifier {
  InventoryProvider({
    required FirestoreService firestoreService,
    bool? disableAuthentication,
  })  : _firestoreService = firestoreService,
        _forceLocalStorage =
            disableAuthentication ?? AppConfig.disableAuthentication;

  final FirestoreService _firestoreService;
  final bool _forceLocalStorage;
  bool _localStorageOnly = false;
  bool _hybridStorageEnabled = false;

  StreamSubscription<List<Supplier>>? _suppliersSubscription;
  StreamSubscription<List<Product>>? _productsSubscription;
  StreamSubscription<List<PurchaseOrder>>? _ordersSubscription;
  StreamSubscription<List<StockMovement>>? _movementsSubscription;

  AppUserProfile? _currentUser;
  List<Supplier> _suppliers = [];
  List<Product> _products = [];
  List<PurchaseOrder> _orders = [];
  List<StockMovement> _movements = [];
  bool _loading = false;
  String? _errorMessage;
  bool _disposed = false;
  bool _seededLocalDemo = false;
  int _localSeq = 0;

  List<Supplier> get suppliers => _suppliers;
  List<Product> get products => _products;
  List<PurchaseOrder> get purchaseOrders => _orders;
  List<StockMovement> get recentMovements => _movements;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;

  bool get usesLocalStorage => _forceLocalStorage || _localStorageOnly;
  bool get _usesFirestore => !usesLocalStorage;
  bool get usesHybridStorage =>
      !_forceLocalStorage && !_localStorageOnly && _hybridStorageEnabled;
  String? get _orgId => _currentUser?.orgId;

  /// Versucht eine Firestore-Mutation. Erfolg -> true (Aufrufer ist fertig).
  /// Im Hybrid-Modus bei Fehler -> false (Aufrufer faellt lokal zurueck, damit
  /// offline nichts verloren geht). Im Cloud-only-Modus wird der Fehler
  /// durchgereicht.
  Future<bool> _tryFirestore(
    String label,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      return true;
    } catch (error) {
      if (!usesHybridStorage) {
        rethrow;
      }
      AppLogger.warning(
        'Inventory: $label offline – lokaler Fallback aktiv',
        error: error,
      );
      return false;
    }
  }

  LocalStorageScope? get _localScope {
    final user = _currentUser;
    if (user == null) {
      return null;
    }
    return LocalStorageScope.fromUser(user);
  }

  // --- Abgeleitete Sichten ------------------------------------------------

  List<Supplier> get activeSuppliers =>
      _suppliers.where((supplier) => supplier.isActive).toList(growable: false);

  List<Product> productsForSite(String? siteId) {
    if (siteId == null || siteId.isEmpty) {
      return _products;
    }
    return _products
        .where((product) => product.siteId == siteId)
        .toList(growable: false);
  }

  /// Artikel, die nachbestellt werden sollten (Bestand <= Meldebestand).
  List<Product> lowStockProducts({String? siteId}) {
    return productsForSite(siteId)
        .where((product) => product.isActive && product.needsReorder)
        .toList(growable: false);
  }

  /// Offene Bestellungen (weder geliefert noch storniert).
  List<PurchaseOrder> get openOrders => _orders
      .where((order) => !order.status.isClosed)
      .toList(growable: false);

  List<PurchaseOrder> ordersForSite(String? siteId) {
    if (siteId == null || siteId.isEmpty) {
      return _orders;
    }
    return _orders
        .where((order) => order.siteId == siteId)
        .toList(growable: false);
  }

  Supplier? supplierById(String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final supplier in _suppliers) {
      if (supplier.id == id) {
        return supplier;
      }
    }
    return null;
  }

  Set<String> get categories {
    final result = <String>{};
    for (final product in _products) {
      final category = product.category?.trim();
      if (category != null && category.isNotEmpty) {
        result.add(category);
      }
    }
    return result;
  }

  /// Erstellt Bestellpositionen aus den nachzubestellenden Artikeln eines
  /// Lieferanten (fuer einen Laden) – Grundlage fuer einen Bestellvorschlag.
  List<PurchaseOrderItem> buildReorderItems({
    required String siteId,
    required String supplierId,
  }) {
    return _products
        .where((product) =>
            product.isActive &&
            product.siteId == siteId &&
            product.supplierId == supplierId &&
            product.needsReorder)
        .map(
          (product) => PurchaseOrderItem(
            productId: product.id,
            name: product.name,
            sku: product.sku,
            unit: product.unit,
            quantityOrdered: product.suggestedReorderQuantity,
            unitPriceCents: product.purchasePriceCents,
          ),
        )
        .toList(growable: false);
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _setError(Object error) {
    _errorMessage = error is StateError ? error.message : error.toString();
    _safeNotify();
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      _safeNotify();
    }
  }

  String? _lastSessionKey;

  String get _storageModeKey => usesLocalStorage
      ? 'local'
      : (_hybridStorageEnabled ? 'hybrid' : 'cloud');

  Future<void> updateSession(
    AppUserProfile? user, {
    bool localStorageOnly = false,
    bool hybridStorageEnabled = false,
  }) async {
    _localStorageOnly = localStorageOnly;
    _hybridStorageEnabled = hybridStorageEnabled;
    final sessionKey =
        user == null ? null : '${user.uid}:${user.orgId}:$_storageModeKey';
    if (sessionKey == _lastSessionKey) {
      _currentUser = user;
      return;
    }
    _lastSessionKey = sessionKey;
    _currentUser = user;

    await _cancelSubscriptions();

    if (user == null) {
      _resetData();
      _seededLocalDemo = false;
      _safeNotify();
      return;
    }

    if (_usesFirestore) {
      _startFirestoreSubscriptions(user.orgId);
    } else {
      // Zuerst persistierte lokale Daten laden, dann ggf. Demo seeden, falls
      // noch nichts vorhanden ist (Plan-Gap inventory-not-locally-persisted).
      await _loadLocalData();
      final seeded = _maybeSeedLocalDemo(user);
      if (seeded) {
        await _persistAllLocal();
      }
      _safeNotify();
    }
  }

  Future<void> _loadLocalData() async {
    final scope = _localScope;
    _suppliers = await DatabaseService.loadLocalSuppliers(scope: scope);
    _products = await DatabaseService.loadLocalProducts(scope: scope);
    _orders = await DatabaseService.loadLocalPurchaseOrders(scope: scope);
    _movements = await DatabaseService.loadLocalStockMovements(scope: scope);
  }

  Future<void> _persistSuppliers() =>
      DatabaseService.saveLocalSuppliers(_suppliers, scope: _localScope);
  Future<void> _persistProducts() =>
      DatabaseService.saveLocalProducts(_products, scope: _localScope);
  Future<void> _persistOrders() =>
      DatabaseService.saveLocalPurchaseOrders(_orders, scope: _localScope);
  Future<void> _persistMovements() =>
      DatabaseService.saveLocalStockMovements(_movements, scope: _localScope);

  Future<void> _persistAllLocal() async {
    await _persistSuppliers();
    await _persistProducts();
    await _persistOrders();
    await _persistMovements();
  }

  /// Befuellt den lokalen Modus einmalig mit Demo-Daten, damit die
  /// Warenwirtschaft ohne Firebase nicht leer ist. Echte lokale Daten
  /// (kein Demo-Nutzer) bleiben unangetastet. Gibt true zurueck, wenn
  /// tatsaechlich Demo-Daten eingesetzt wurden (dann muss persistiert werden).
  bool _maybeSeedLocalDemo(AppUserProfile user) {
    if (_seededLocalDemo || !LocalDemoData.isDemoUser(user)) {
      return false;
    }
    _seededLocalDemo = true;
    var seeded = false;
    if (_suppliers.isEmpty) {
      _suppliers = LocalDemoData.suppliersForOrg(
        orgId: user.orgId,
        createdByUid: user.uid,
      );
      seeded = true;
    }
    if (_products.isEmpty) {
      _products = LocalDemoData.productsForOrg(
        orgId: user.orgId,
        createdByUid: user.uid,
      );
      seeded = true;
    }
    return seeded;
  }

  void _resetData() {
    _suppliers = [];
    _products = [];
    _orders = [];
    _movements = [];
    _loading = false;
  }

  void _startFirestoreSubscriptions(String orgId) {
    _loading = true;
    _safeNotify();

    _suppliersSubscription =
        _firestoreService.watchSuppliers(orgId).listen((items) {
      _suppliers = items;
      _loading = false;
      _safeNotify();
    }, onError: _setError);

    _productsSubscription =
        _firestoreService.watchProducts(orgId).listen((items) {
      _products = items;
      _safeNotify();
    }, onError: _setError);

    _ordersSubscription =
        _firestoreService.watchPurchaseOrders(orgId).listen((items) {
      _orders = items;
      _safeNotify();
    }, onError: _setError);

    _movementsSubscription =
        _firestoreService.watchStockMovements(orgId).listen((items) {
      _movements = items;
      _safeNotify();
    }, onError: _setError);
  }

  Future<void> _cancelSubscriptions() async {
    await _suppliersSubscription?.cancel();
    await _productsSubscription?.cancel();
    await _ordersSubscription?.cancel();
    await _movementsSubscription?.cancel();
    _suppliersSubscription = null;
    _productsSubscription = null;
    _ordersSubscription = null;
    _movementsSubscription = null;
  }

  String _nextLocalId(String prefix) {
    _localSeq += 1;
    return 'local-$prefix-${DateTime.now().microsecondsSinceEpoch}-$_localSeq';
  }

  // --- Lieferanten --------------------------------------------------------

  Future<void> saveSupplier(Supplier supplier) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    final prepared = supplier.copyWith(
      orgId: orgId,
      createdByUid: supplier.createdByUid ?? _currentUser?.uid,
    );
    if (_usesFirestore &&
        await _tryFirestore(
          'saveSupplier',
          () => _firestoreService.saveSupplier(prepared),
        )) {
      return;
    }
    _upsertLocal(
      _suppliers,
      prepared.id == null
          ? prepared.copyWith(id: _nextLocalId('supplier'))
          : prepared,
      (item) => item.id,
    );
    _suppliers.sort((a, b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _persistSuppliers();
    _safeNotify();
  }

  Future<void> deleteSupplier(String supplierId) async {
    final orgId = _orgId;
    if (orgId == null) {
      return;
    }
    if (_usesFirestore &&
        await _tryFirestore(
          'deleteSupplier',
          () => _firestoreService.deleteSupplier(
            orgId: orgId,
            supplierId: supplierId,
          ),
        )) {
      return;
    }
    _suppliers = _suppliers
        .where((supplier) => supplier.id != supplierId)
        .toList(growable: false);
    await _persistSuppliers();
    _safeNotify();
  }

  // --- Artikel ------------------------------------------------------------

  Future<void> saveProduct(Product product) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    final prepared = product.copyWith(
      orgId: orgId,
      createdByUid: product.createdByUid ?? _currentUser?.uid,
    );
    if (_usesFirestore &&
        await _tryFirestore(
          'saveProduct',
          () => _firestoreService.saveProduct(prepared),
        )) {
      return;
    }
    _upsertLocal(
      _products,
      prepared.id == null
          ? prepared.copyWith(id: _nextLocalId('product'))
          : prepared,
      (item) => item.id,
    );
    _products
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _persistProducts();
    _safeNotify();
  }

  Future<void> deleteProduct(String productId) async {
    final orgId = _orgId;
    if (orgId == null) {
      return;
    }
    if (_usesFirestore &&
        await _tryFirestore(
          'deleteProduct',
          () => _firestoreService.deleteProduct(
            orgId: orgId,
            productId: productId,
          ),
        )) {
      return;
    }
    _products = _products
        .where((product) => product.id != productId)
        .toList(growable: false);
    await _persistProducts();
    _safeNotify();
  }

  /// Bucht eine Bestandsaenderung (Korrektur/Abgang). [delta] positiv = Zugang.
  Future<void> adjustStock({
    required String productId,
    required int delta,
    StockMovementType type = StockMovementType.adjustment,
    String? reason,
  }) async {
    final orgId = _orgId;
    if (orgId == null || delta == 0) {
      return;
    }
    if (_usesFirestore &&
        await _tryFirestore(
          'adjustStock',
          () => _firestoreService.adjustProductStock(
            orgId: orgId,
            productId: productId,
            delta: delta,
            type: type,
            reason: reason,
            createdByUid: _currentUser?.uid,
          ),
        )) {
      return;
    }
    _applyLocalStockChange(
      productId: productId,
      delta: delta,
      type: type,
      reason: reason,
    );
    await _persistProducts();
    await _persistMovements();
    _safeNotify();
  }

  /// Setzt den Bestand per Inventur auf [countedStock] und bucht die Differenz.
  Future<void> recordStocktake({
    required Product product,
    required int countedStock,
  }) async {
    final delta = countedStock - product.currentStock;
    if (delta == 0 || product.id == null) {
      return;
    }
    await adjustStock(
      productId: product.id!,
      delta: delta,
      type: StockMovementType.stocktake,
      reason: 'Inventur',
    );
  }

  // --- Bestellungen -------------------------------------------------------

  /// Speichert eine Bestellung und gibt deren Id zurueck.
  Future<String> savePurchaseOrder(PurchaseOrder order) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    final prepared = order.copyWith(
      orgId: orgId,
      createdByUid: order.createdByUid ?? _currentUser?.uid,
    );
    if (_usesFirestore) {
      try {
        return await _firestoreService.savePurchaseOrder(prepared);
      } catch (error) {
        if (!usesHybridStorage) {
          rethrow;
        }
        AppLogger.warning(
          'Inventory: savePurchaseOrder offline – lokaler Fallback aktiv',
          error: error,
        );
      }
    }
    final withId = prepared.id == null
        ? prepared.copyWith(
            id: _nextLocalId('order'),
            orderNumber: prepared.orderNumber ??
                'BST-${DateTime.now().year}-${(_orders.length + 1).toString().padLeft(4, '0')}',
          )
        : prepared;
    _upsertLocal(_orders, withId, (item) => item.id);
    _orders.sort((a, b) => (b.orderNumber ?? '').compareTo(a.orderNumber ?? ''));
    await _persistOrders();
    _safeNotify();
    return withId.id!;
  }

  /// Markiert eine Bestellung als abgeschickt.
  Future<void> markOrderAsOrdered(PurchaseOrder order) async {
    if (order.id == null) {
      return;
    }
    await savePurchaseOrder(
      order.copyWith(
        status: PurchaseOrderStatus.ordered,
        orderedAt: order.orderedAt ?? DateTime.now(),
      ),
    );
  }

  /// Storniert eine Bestellung.
  Future<void> cancelOrder(PurchaseOrder order) async {
    if (order.id == null) {
      return;
    }
    await savePurchaseOrder(
      order.copyWith(status: PurchaseOrderStatus.cancelled),
    );
  }

  Future<void> deletePurchaseOrder(String orderId) async {
    final orgId = _orgId;
    if (orgId == null) {
      return;
    }
    if (_usesFirestore &&
        await _tryFirestore(
          'deletePurchaseOrder',
          () => _firestoreService.deletePurchaseOrder(
            orgId: orgId,
            orderId: orderId,
          ),
        )) {
      return;
    }
    _orders =
        _orders.where((order) => order.id != orderId).toList(growable: false);
    await _persistOrders();
    _safeNotify();
  }

  /// Bucht den Wareneingang fuer eine Bestellung.
  /// [receivedByItemIndex]: Positionsindex -> jetzt zusaetzlich gelieferte Menge.
  Future<void> receiveOrder({
    required String orderId,
    required Map<int, int> receivedByItemIndex,
  }) async {
    final orgId = _orgId;
    if (orgId == null) {
      return;
    }
    if (_usesFirestore &&
        await _tryFirestore(
          'receiveOrder',
          () => _firestoreService.receivePurchaseOrder(
            orgId: orgId,
            orderId: orderId,
            receivedByItemIndex: receivedByItemIndex,
            createdByUid: _currentUser?.uid,
          ),
        )) {
      return;
    }
    _applyLocalReceipt(orderId, receivedByItemIndex);
    await _persistOrders();
    await _persistProducts();
    await _persistMovements();
    _safeNotify();
  }

  // --- Lokale Mutationen (Dev-Modus) -------------------------------------

  void _applyLocalStockChange({
    required String productId,
    required int delta,
    required StockMovementType type,
    String? reason,
    String? relatedOrderId,
  }) {
    final index = _products.indexWhere((product) => product.id == productId);
    if (index < 0) {
      return;
    }
    final product = _products[index];
    final newStock = product.currentStock + delta;
    _products[index] = product.copyWith(currentStock: newStock);
    _products = [..._products];
    _movements = [
      StockMovement(
        id: _nextLocalId('movement'),
        orgId: product.orgId,
        siteId: product.siteId,
        productId: productId,
        productName: product.name,
        type: type,
        quantityDelta: delta,
        balanceAfter: newStock,
        reason: reason,
        relatedOrderId: relatedOrderId,
        createdByUid: _currentUser?.uid,
        createdAt: DateTime.now(),
      ),
      ..._movements,
    ];
  }

  void _applyLocalReceipt(String orderId, Map<int, int> receivedByItemIndex) {
    final orderIndex = _orders.indexWhere((order) => order.id == orderId);
    if (orderIndex < 0) {
      return;
    }
    final order = _orders[orderIndex];
    final updatedItems = <PurchaseOrderItem>[];
    for (var i = 0; i < order.items.length; i++) {
      final item = order.items[i];
      final qty = (receivedByItemIndex[i] ?? 0).clamp(0, item.outstandingQuantity);
      if (qty > 0) {
        updatedItems.add(
          item.copyWith(quantityReceived: item.quantityReceived + qty),
        );
        final productId = item.productId;
        if (productId != null && productId.isNotEmpty) {
          _applyLocalStockChange(
            productId: productId,
            delta: qty,
            type: StockMovementType.receipt,
            reason: 'Wareneingang ${order.orderNumber ?? ''}'.trim(),
            relatedOrderId: orderId,
          );
        }
      } else {
        updatedItems.add(item);
      }
    }
    final updatedOrder = order.copyWith(items: updatedItems);
    final newStatus = updatedOrder.deriveReceiptStatus();
    _orders[orderIndex] = updatedOrder.copyWith(
      status: newStatus,
      receivedAt: newStatus == PurchaseOrderStatus.received
          ? (order.receivedAt ?? DateTime.now())
          : order.receivedAt,
    );
    _orders = [..._orders];
  }

  void _upsertLocal<T>(
    List<T> list,
    T item,
    String? Function(T) idOf,
  ) {
    final id = idOf(item);
    final index = list.indexWhere((existing) => idOf(existing) == id);
    if (index >= 0) {
      list[index] = item;
    } else {
      list.add(item);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSubscriptions();
    super.dispose();
  }
}
