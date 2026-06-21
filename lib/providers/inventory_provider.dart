import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/local_demo_data.dart';
import '../models/app_user.dart';
import '../models/customer_order.dart';
import '../models/price_history_entry.dart';
import '../models/product.dart';
import '../models/purchase_order.dart';
import '../models/stock_movement.dart';
import '../models/supplier.dart';
import '../repositories/inventory_repository.dart';
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
    InventoryRepository? inventoryRepository,
    bool? disableAuthentication,
    Uuid? uuid,
  })  : _firestoreService = firestoreService,
        _injectedInventory = inventoryRepository,
        _uuid = uuid ?? const Uuid(),
        _forceLocalStorage =
            disableAuthentication ?? AppConfig.disableAuthentication;

  // Provider haengt an der Repository-Abstraktion, nicht mehr an der konkreten
  // FirestoreService-Klasse (no-domain-repository-interfaces-dip). Das
  // Cloud-Repository wird LAZY aufgeloest: Im lokalen/disableAuth-Modus wird es
  // nie beruehrt, sodass FirebaseFirestore.instance ohne konfiguriertes Firebase
  // nicht ausgewertet wird (sonst Crash bereits bei Provider-Konstruktion ->
  // rote Fehlerseite ueberall, wo der Provider gelesen wird).
  final FirestoreService _firestoreService;
  final InventoryRepository? _injectedInventory;
  InventoryRepository get _inventory =>
      _injectedInventory ?? _firestoreService.inventoryRepository;
  final Uuid _uuid;
  final bool _forceLocalStorage;
  bool _localStorageOnly = false;
  bool _hybridStorageEnabled = false;

  StreamSubscription<List<Supplier>>? _suppliersSubscription;
  StreamSubscription<List<Product>>? _productsSubscription;
  StreamSubscription<List<PurchaseOrder>>? _ordersSubscription;
  StreamSubscription<List<StockMovement>>? _movementsSubscription;
  StreamSubscription<List<CustomerOrder>>? _customerOrdersSubscription;

  AppUserProfile? _currentUser;
  List<Supplier> _suppliers = [];
  List<Product> _products = [];
  List<PurchaseOrder> _orders = [];
  List<StockMovement> _movements = [];
  List<PriceHistoryEntry> _priceHistory = [];
  List<CustomerOrder> _customerOrders = [];
  bool _loading = false;
  String? _errorMessage;
  bool _disposed = false;
  bool _seededLocalDemo = false;
  int _localSeq = 0;

  List<Supplier> get suppliers => _suppliers;
  List<Product> get products => _products;
  List<PurchaseOrder> get purchaseOrders => _orders;
  List<StockMovement> get recentMovements => _movements;

  /// Lokal protokollierte Preisaenderungen. Im **local**-Modus die volle
  /// Historie; in **cloud/hybrid** ist die Quelle der Wahrheit die
  /// write-only-Firestore-Subcollection `products/{id}/priceHistory` (analog zu
  /// stockMovements wird sie nicht in den Speicher gestreamt) — dort bleibt diese
  /// In-Memory-Liste daher leer. Ein kuenftiger Historie-View muss in
  /// cloud/hybrid via watchPriceHistory lesen.
  List<PriceHistoryEntry> get priceHistory => _priceHistory;
  List<CustomerOrder> get customerOrders => _customerOrders;
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

  /// Findet einen Artikel anhand seines Barcodes (EAN) — fuer den Scanner.
  ///
  /// Rein clientseitig ueber die bereits gestreamte Artikelliste: kein
  /// Firestore-Index, kein Repo-Zugriff (umgeht den Lazy-Cloud-Repo-Footgun),
  /// deckt local/cloud/hybrid einheitlich ab. Bei mehreren Treffern wird der
  /// erste geliefert — fuer die Mehrfach-Behandlung siehe [productsByBarcode].
  /// Standardmaessig werden nur aktive Artikel beruecksichtigt; mit
  /// [includeInactive] laesst sich ein deaktivierter Artikel finden (z.B. um
  /// eine Reaktivierung statt einer Neuanlage anzubieten).
  Product? productByBarcode(
    String barcode, {
    String? siteId,
    bool includeInactive = false,
  }) {
    final matches = productsByBarcode(
      barcode,
      siteId: siteId,
      includeInactive: includeInactive,
    );
    return matches.isEmpty ? null : matches.first;
  }

  /// Alle (standardmaessig aktiven) Artikel mit exakt diesem Barcode, optional
  /// auf einen Standort beschraenkt. Der Barcode hat KEINE Eindeutigkeits-
  /// Constraint -> ein Code kann je Laden bzw. theoretisch mehrfach vorkommen.
  List<Product> productsByBarcode(
    String barcode, {
    String? siteId,
    bool includeInactive = false,
  }) {
    final code = barcode.trim();
    if (code.isEmpty) {
      return const <Product>[];
    }
    return _products
        .where(
          (product) =>
              (includeInactive || product.isActive) &&
              (product.barcode?.trim() ?? '') == code &&
              (siteId == null || siteId.isEmpty || product.siteId == siteId),
        )
        .toList(growable: false);
  }

  /// Artikel, die nachbestellt werden sollten (Bestand <= Meldebestand).
  List<Product> lowStockProducts({String? siteId}) {
    return productsForSite(siteId)
        .where((product) => product.isActive && product.needsReorder)
        .toList(growable: false);
  }

  // --- Warenwert / Marge --------------------------------------------------

  /// Warenwert (Einkaufspreis × Bestand) der aktiven Artikel, optional je
  /// Standort. In Cent. Beantwortet „wie viel Geld liegt im Regal".
  int totalStockValuePurchaseCents({String? siteId}) {
    return productsForSite(siteId)
        .where((product) => product.isActive)
        .fold<int>(0, (sum, product) => sum + product.stockValuePurchaseCents);
  }

  /// Warenwert zum Verkaufspreis der aktiven Artikel, optional je Standort. Cent.
  int totalStockValueSellingCents({String? siteId}) {
    return productsForSite(siteId)
        .where((product) => product.isActive)
        .fold<int>(0, (sum, product) => sum + product.stockValueSellingCents);
  }

  /// Erwartete Spanne (VK − EK) über den gesamten Bestand, optional je Standort.
  int totalStockMarginCents({String? siteId}) =>
      totalStockValueSellingCents(siteId: siteId) -
      totalStockValuePurchaseCents(siteId: siteId);

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

  // --- Kundenbestellungen (Sonderbestellungen) ---------------------------

  List<CustomerOrder> customerOrdersForSite(String? siteId) {
    if (siteId == null || siteId.isEmpty) {
      return _customerOrders;
    }
    return _customerOrders
        .where((order) => order.siteId == siteId)
        .toList(growable: false);
  }

  /// Offene Kundenbestellungen (weder abgeholt noch storniert).
  List<CustomerOrder> get openCustomerOrders => _customerOrders
      .where((order) => order.status.isOpen)
      .toList(growable: false);

  /// Distinkte Warengruppen über alle Kundenbestellungs-Positionen (für die
  /// Kategorie-Filter im Screen).
  Set<String> get customerOrderCategories {
    final result = <String>{};
    for (final order in _customerOrders) {
      for (final item in order.items) {
        final category = item.category?.trim();
        if (category != null && category.isNotEmpty) {
          result.add(category);
        }
      }
    }
    return result;
  }

  /// Kundenbestellungen, deren Abholtermin innerhalb von [withinDays] liegt
  /// (oder bereits überfällig ist) und die noch nicht vorbereitet sind –
  /// die Grundlage aller "nicht vorbereitet"-Warnungen (Liste, Dashboard,
  /// Benachrichtigungen). Sortiert nach Abholtermin (dringendste zuerst).
  List<CustomerOrder> ordersDueSoonNotPrepared({
    int withinDays = 2,
    String? siteId,
  }) {
    final threshold = DateTime.now().add(Duration(days: withinDays));
    final list = customerOrdersForSite(siteId).where((order) {
      if (order.status.isClosed || order.isPrepared) {
        return false;
      }
      final due = order.pickupDate;
      return due != null && due.isBefore(threshold);
    }).toList();
    list.sort((a, b) => a.pickupDate!.compareTo(b.pickupDate!));
    return list;
  }

  /// Anzahl der bald fälligen, nicht vorbereiteten Kundenbestellungen.
  int dueSoonNotPreparedCount({int withinDays = 2, String? siteId}) =>
      ordersDueSoonNotPrepared(withinDays: withinDays, siteId: siteId).length;

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
    // Mindestbestellmenge des Lieferanten (falls gepflegt) -> Vorschlag darauf
    // anheben, damit die Bestellung die Vorgabe des Lieferanten erfüllt.
    var minOrder = 0;
    for (final supplier in _suppliers) {
      if (supplier.id == supplierId) {
        minOrder = supplier.minOrderQuantity ?? 0;
        break;
      }
    }
    return _products
        .where((product) =>
            product.isActive &&
            product.siteId == siteId &&
            product.supplierId == supplierId &&
            product.needsReorder)
        .map(
          (product) {
            var quantity = product.suggestedReorderQuantity;
            if (minOrder > quantity) {
              quantity = minOrder;
            }
            return PurchaseOrderItem(
              productId: product.id,
              name: product.name,
              sku: product.sku,
              unit: product.unit,
              quantityOrdered: quantity,
              unitPriceCents: product.purchasePriceCents,
            );
          },
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

  /// Macht einen Fehler beim fire-and-forget Sitzungsaufbau in der UI sichtbar
  /// (fire-and-forget-updatesession).
  void surfaceSessionError(Object error) {
    _errorMessage =
        'Daten konnten nicht geladen werden. Bitte später erneut versuchen.';
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
    _priceHistory = await DatabaseService.loadLocalPriceHistory(scope: scope);
    _customerOrders =
        await DatabaseService.loadLocalCustomerOrders(scope: scope);
  }

  Future<void> _persistSuppliers() =>
      DatabaseService.saveLocalSuppliers(_suppliers, scope: _localScope);
  Future<void> _persistProducts() =>
      DatabaseService.saveLocalProducts(_products, scope: _localScope);
  Future<void> _persistOrders() =>
      DatabaseService.saveLocalPurchaseOrders(_orders, scope: _localScope);
  Future<void> _persistMovements() =>
      DatabaseService.saveLocalStockMovements(_movements, scope: _localScope);
  Future<void> _persistPriceHistory() =>
      DatabaseService.saveLocalPriceHistory(_priceHistory, scope: _localScope);
  Future<void> _persistCustomerOrders() =>
      DatabaseService.saveLocalCustomerOrders(_customerOrders,
          scope: _localScope);

  Future<void> _persistAllLocal() async {
    await _persistSuppliers();
    await _persistProducts();
    await _persistOrders();
    await _persistMovements();
    await _persistPriceHistory();
    await _persistCustomerOrders();
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
    if (_customerOrders.isEmpty) {
      _customerOrders = LocalDemoData.customerOrdersForOrg(
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
    _priceHistory = [];
    _customerOrders = [];
    _loading = false;
  }

  void _startFirestoreSubscriptions(String orgId) {
    _loading = true;
    _safeNotify();

    _suppliersSubscription =
        _inventory.watchSuppliers(orgId).listen((items) {
      _suppliers = items;
      _loading = false;
      _safeNotify();
    }, onError: _setError);

    _productsSubscription =
        _inventory.watchProducts(orgId).listen((items) {
      _products = items;
      _safeNotify();
    }, onError: _setError);

    _ordersSubscription =
        _inventory.watchPurchaseOrders(orgId).listen((items) {
      _orders = items;
      _safeNotify();
    }, onError: _setError);

    _movementsSubscription =
        _inventory.watchStockMovements(orgId).listen((items) {
      _movements = items;
      _safeNotify();
    }, onError: _setError);

    _customerOrdersSubscription =
        _inventory.watchCustomerOrders(orgId).listen((items) {
      _customerOrders = items;
      _safeNotify();
    }, onError: _setError);
  }

  Future<void> _cancelSubscriptions() async {
    await _suppliersSubscription?.cancel();
    await _productsSubscription?.cancel();
    await _ordersSubscription?.cancel();
    await _movementsSubscription?.cancel();
    await _customerOrdersSubscription?.cancel();
    _suppliersSubscription = null;
    _productsSubscription = null;
    _ordersSubscription = null;
    _movementsSubscription = null;
    _customerOrdersSubscription = null;
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
          () => _inventory.saveSupplier(prepared),
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
          () => _inventory.deleteSupplier(
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
          () => _inventory.saveProduct(prepared),
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

  /// Aktualisiert EK-/VK-Preis eines Artikels und protokolliert jede tatsaechliche
  /// Aenderung in der Preis-Historie (Audit-Log). Genutzt vom Scanner bei
  /// erkannter Preisabweichung. Nur die uebergebenen (nicht-null) Preise werden
  /// veraendert. Liefert die Zahl der protokollierten Preisaenderungen.
  Future<int> updateProductPrices(
    Product product, {
    int? newPurchaseCents,
    int? newSellingCents,
  }) async {
    if (product.id == null) {
      throw StateError('Artikel ist noch nicht gespeichert.');
    }
    final oldPurchase = product.purchasePriceCents;
    final oldSelling = product.sellingPriceCents;
    final nextPurchase = newPurchaseCents ?? oldPurchase;
    final nextSelling = newSellingCents ?? oldSelling;
    if (nextPurchase == oldPurchase && nextSelling == oldSelling) {
      return 0;
    }

    await saveProduct(
      product.copyWith(
        purchasePriceCents: nextPurchase,
        clearPurchasePrice: nextPurchase == null,
        sellingPriceCents: nextSelling,
        clearSellingPrice: nextSelling == null,
      ),
    );

    var logged = 0;
    if (nextPurchase != oldPurchase) {
      await _recordPriceChange(
        product: product,
        field: PriceField.purchase,
        oldCents: oldPurchase,
        newCents: nextPurchase,
      );
      logged++;
    }
    if (nextSelling != oldSelling) {
      await _recordPriceChange(
        product: product,
        field: PriceField.selling,
        oldCents: oldSelling,
        newCents: nextSelling,
      );
      logged++;
    }
    return logged;
  }

  /// Schreibt einen unveraenderlichen Preis-Historie-Eintrag (Audit-Log). Folgt
  /// demselben Speichermodus-Muster wie [adjustStock]: cloud/hybrid ueber das
  /// Repo (bei hybrid mit lokalem Fallback), local direkt lokal.
  Future<void> _recordPriceChange({
    required Product product,
    required PriceField field,
    required int? oldCents,
    required int? newCents,
  }) async {
    final orgId = _orgId;
    final productId = product.id;
    if (orgId == null || productId == null) {
      return;
    }
    final entry = PriceHistoryEntry(
      orgId: orgId,
      productId: productId,
      field: field,
      oldCents: oldCents,
      newCents: newCents,
      changedByUid: _currentUser?.uid,
      changedAt: DateTime.now(),
    );
    if (_usesFirestore &&
        await _tryFirestore(
          'recordPriceChange',
          () => _inventory.addPriceHistory(entry),
        )) {
      return;
    }
    _priceHistory = [
      entry.copyWith(id: _nextLocalId('price_history')),
      ..._priceHistory,
    ];
    await _persistPriceHistory();
    _safeNotify();
  }

  /// Preis-Historie eines Artikels (neueste zuerst). In cloud/hybrid aus der
  /// Firestore-Subcollection (Quelle der Wahrheit); in local-Modus aus dem
  /// lokalen Spiegel. Der Lazy-Cloud-Repo-Footgun bleibt gewahrt: das Repo wird
  /// nur bei _usesFirestore angefasst.
  Future<List<PriceHistoryEntry>> priceHistoryFor(String productId) async {
    if (_usesFirestore) {
      final orgId = _orgId;
      if (orgId == null) {
        return const <PriceHistoryEntry>[];
      }
      try {
        return await _inventory.fetchPriceHistory(
          orgId: orgId,
          productId: productId,
        );
      } catch (_) {
        // Hybrid-Offline-Fallback: lokalen Spiegel zeigen (ggf. leer).
      }
    }
    return _priceHistory
        .where((entry) => entry.productId == productId)
        .toList(growable: false);
  }

  Future<void> deleteProduct(String productId) async {
    final orgId = _orgId;
    if (orgId == null) {
      return;
    }
    if (_usesFirestore &&
        await _tryFirestore(
          'deleteProduct',
          () => _inventory.deleteProduct(
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
  ///
  /// [clientMutationId] erlaubt eine STABILE Idempotenz-Id von aussen: ohne sie
  /// erzeugt jeder Aufruf eine frische UUID. Die Daten-Idempotenz greift nur auf
  /// dem **Firestore-Pfad** (cloud/hybrid-Erfolg): die Bewegung wird dort unter
  /// der mutationId adressiert (no-idempotency-on-stock-mutations). Der lokale
  /// Pfad (local-Modus + hybrid-Offline-Fallback) bucht synchron und einmalig
  /// und kennt keine Replays; gegen Doppel-Tap schuetzt dort der UI-Guard im
  /// Scanner (in-flight-Sperre + deaktivierte Buttons).
  Future<void> adjustStock({
    required String productId,
    required int delta,
    StockMovementType type = StockMovementType.adjustment,
    String? reason,
    String? clientMutationId,
  }) async {
    final orgId = _orgId;
    if (orgId == null || delta == 0) {
      return;
    }
    // Stabile ID pro Buchung -> ein Retry bzw. Doppel-Scan bucht den Bestand
    // nicht doppelt (no-idempotency-on-stock-mutations).
    final mutationId = clientMutationId ?? _uuid.v4();
    if (_usesFirestore &&
        await _tryFirestore(
          'adjustStock',
          () => _inventory.adjustProductStock(
            orgId: orgId,
            productId: productId,
            delta: delta,
            type: type,
            reason: reason,
            createdByUid: _currentUser?.uid,
            clientMutationId: mutationId,
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

  /// Prueft, ob ein Abgang von [quantity] Stueck fuer [product] zulaessig ist.
  /// Gibt eine deutsche Fehlermeldung zurueck oder `null`, wenn die Buchung ok
  /// ist. Verhindert einen Negativbestand bei Verkauf/Schwund (Korrekturen und
  /// Inventuren duerfen den Bestand dagegen legitim unter null nicht senken,
  /// laufen aber ohnehin nicht ueber diesen Pfad).
  String? validateStockIssue({
    required Product product,
    required int quantity,
  }) {
    if (quantity <= 0) {
      return 'Bitte eine Menge groesser als 0 eingeben.';
    }
    if (product.currentStock - quantity < 0) {
      return 'Abgangsmenge ($quantity) uebersteigt den aktuellen Bestand '
          '(${product.currentStock} ${product.unit}).';
    }
    return null;
  }

  /// Bucht einen Abgang (Verkauf, Schwund, Eigenbedarf) als negative Bewegung
  /// vom Typ [StockMovementType.issue]. Gibt `null` bei Erfolg oder eine
  /// deutsche Fehlermeldung zurueck (z.B. bei Bestandsueberzug). Die eigentliche
  /// Buchung laeuft ueber die atomare [adjustStock]-Transaktion.
  Future<String?> issueStock({
    required Product product,
    required int quantity,
    String? reason,
    String? clientMutationId,
  }) async {
    final error = validateStockIssue(product: product, quantity: quantity);
    if (error != null) {
      return error;
    }
    if (product.id == null) {
      return 'Artikel ist noch nicht gespeichert.';
    }
    await adjustStock(
      productId: product.id!,
      delta: -quantity,
      type: StockMovementType.issue,
      reason: (reason == null || reason.trim().isEmpty)
          ? 'Abgang'
          : reason.trim(),
      clientMutationId: clientMutationId,
    );
    return null;
  }

  /// Lagert [quantity] Stück von [from] (Quelle) nach [to] (Ziel) um — bucht
  /// einen gepaarten Abgang an der Quelle und Eingang am Ziel (Typ transfer).
  /// Gibt `null` bei Erfolg oder eine deutsche Fehlermeldung zurück (z.B.
  /// Bestandsüberzug). Für den Multi-Standort-Betrieb (Strichmännchen ↔ Tabak
  /// Börse): ein Artikel existiert je Laden als eigener Datensatz.
  Future<String?> transferStock({
    required Product from,
    required Product to,
    required int quantity,
  }) async {
    if (quantity <= 0) {
      return 'Bitte eine Menge größer als 0 eingeben.';
    }
    if (from.id == null || to.id == null) {
      return 'Artikel ist noch nicht gespeichert.';
    }
    if (from.id == to.id) {
      return 'Quelle und Ziel müssen unterschiedlich sein.';
    }
    if (from.currentStock - quantity < 0) {
      return 'Menge ($quantity) übersteigt den Bestand der Quelle '
          '(${from.currentStock} ${from.unit}).';
    }
    final toLabel = to.siteName ?? 'Ziel';
    final fromLabel = from.siteName ?? 'Quelle';
    // Die Umlagerung sind zwei getrennte (je atomare) Buchungen. Im cloud-only-
    // Modus kann adjustStock rethrowen -> dann darf der bereits gebuchte Abgang
    // an der Quelle nicht verloren gehen: bei Fehler am Ziel kompensieren wir
    // die Quellbuchung wieder (best-effort) und melden den Fehler.
    try {
      await adjustStock(
        productId: from.id!,
        delta: -quantity,
        type: StockMovementType.transfer,
        reason: 'Umlagerung nach $toLabel',
      );
    } catch (error) {
      return 'Umlagerung fehlgeschlagen (Quelle wurde nicht belastet).';
    }
    try {
      await adjustStock(
        productId: to.id!,
        delta: quantity,
        type: StockMovementType.transfer,
        reason: 'Umlagerung von $fromLabel',
      );
    } catch (error) {
      // Ziel-Buchung fehlgeschlagen -> Abgang an der Quelle zurücknehmen.
      try {
        await adjustStock(
          productId: from.id!,
          delta: quantity,
          type: StockMovementType.transfer,
          reason: 'Storno Umlagerung (Ziel-Buchung fehlgeschlagen)',
        );
      } catch (_) {
        // Kompensation selbst fehlgeschlagen -> in den Fehlertext aufnehmen.
        return 'Umlagerung am Ziel fehlgeschlagen; Quellbuchung konnte NICHT '
            'automatisch zurückgenommen werden – bitte Bestand prüfen.';
      }
      return 'Umlagerung am Ziel fehlgeschlagen – Quellbuchung wurde '
          'zurückgenommen.';
    }
    return null;
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
        return await _inventory.savePurchaseOrder(prepared);
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
          () => _inventory.deletePurchaseOrder(
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
    final mutationId = _uuid.v4();
    if (_usesFirestore &&
        await _tryFirestore(
          'receiveOrder',
          () => _inventory.receivePurchaseOrder(
            orgId: orgId,
            orderId: orderId,
            receivedByItemIndex: receivedByItemIndex,
            createdByUid: _currentUser?.uid,
            clientMutationId: mutationId,
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

  // --- Kundenbestellungen (Sonderbestellungen) ---------------------------

  /// Speichert eine Kundenbestellung und gibt deren Id zurueck.
  Future<String> saveCustomerOrder(CustomerOrder order) async {
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
        return await _inventory.saveCustomerOrder(prepared);
      } catch (error) {
        if (!usesHybridStorage) {
          rethrow;
        }
        AppLogger.warning(
          'Inventory: saveCustomerOrder offline – lokaler Fallback aktiv',
          error: error,
        );
      }
    }
    final withId = prepared.id == null
        ? prepared.copyWith(
            id: _nextLocalId('customerOrder'),
            orderNumber: prepared.orderNumber ??
                'KB-${DateTime.now().year}-${(_customerOrders.length + 1).toString().padLeft(4, '0')}',
          )
        : prepared;
    _upsertLocal(_customerOrders, withId, (item) => item.id);
    await _persistCustomerOrders();
    _safeNotify();
    return withId.id!;
  }

  Future<void> deleteCustomerOrder(String orderId) async {
    final orgId = _orgId;
    if (orgId == null) {
      return;
    }
    if (_usesFirestore &&
        await _tryFirestore(
          'deleteCustomerOrder',
          () => _inventory.deleteCustomerOrder(
            orgId: orgId,
            orderId: orderId,
          ),
        )) {
      return;
    }
    _customerOrders = _customerOrders
        .where((order) => order.id != orderId)
        .toList(growable: false);
    await _persistCustomerOrders();
    _safeNotify();
  }

  /// Markiert eine Kundenbestellung als vorbereitet ([prepared] = true) bzw.
  /// nimmt die Markierung zurueck und setzt sie wieder auf offen.
  Future<void> markCustomerOrderPrepared(
    CustomerOrder order, {
    bool prepared = true,
  }) async {
    if (order.id == null) {
      return;
    }
    await saveCustomerOrder(
      order.copyWith(
        status:
            prepared ? CustomerOrderStatus.prepared : CustomerOrderStatus.open,
        preparedAt: prepared ? DateTime.now() : null,
        clearPreparedAt: !prepared,
      ),
    );
  }

  /// Schliesst eine Kundenbestellung als abgeholt ab. Bei wiederkehrenden
  /// Bestellungen (woechentlich/monatlich) wird automatisch eine offene
  /// Folgebestellung mit dem naechsten Abholtermin angelegt – die Vorbereitung
  /// startet damit wieder bei null.
  Future<void> markCustomerOrderPickedUp(CustomerOrder order) async {
    if (order.id == null) {
      return;
    }
    await saveCustomerOrder(
      order.copyWith(status: CustomerOrderStatus.pickedUp),
    );
    final next = order.nextPickupDate;
    if (order.recurrence.isRecurring && next != null) {
      await saveCustomerOrder(
        CustomerOrder(
          orgId: order.orgId,
          siteId: order.siteId,
          siteName: order.siteName,
          customerName: order.customerName,
          customerContact: order.customerContact,
          status: CustomerOrderStatus.open,
          recurrence: order.recurrence,
          items: order.items,
          notes: order.notes,
          pickupDate: next,
          createdByUid: _currentUser?.uid,
        ),
      );
    }
  }

  /// Storniert eine Kundenbestellung.
  Future<void> cancelCustomerOrder(CustomerOrder order) async {
    if (order.id == null) {
      return;
    }
    await saveCustomerOrder(
      order.copyWith(status: CustomerOrderStatus.cancelled),
    );
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
