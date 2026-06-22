import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/local_demo_data.dart';
import '../models/app_user.dart';
import '../models/audit_log_entry.dart';
import '../models/customer_order.dart';
import '../models/order_cart.dart';
import '../models/price_history_entry.dart';
import '../models/product.dart';
import '../models/purchase_order.dart';
import '../models/stock_movement.dart';
import '../models/supplier.dart';
import '../repositories/inventory_repository.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import 'audit_sink.dart';

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
  StreamSubscription<List<SiteOrderList>>? _orderCartsSubscription;
  StreamSubscription<List<SiteOrderList>>? _weeklyListsSubscription;

  AppUserProfile? _currentUser;
  List<Supplier> _suppliers = [];
  List<Product> _products = [];
  List<PurchaseOrder> _orders = [];
  List<StockMovement> _movements = [];
  List<PriceHistoryEntry> _priceHistory = [];
  List<CustomerOrder> _customerOrders = [];
  List<SiteOrderList> _orderCarts = [];
  List<SiteOrderList> _weeklyLists = [];
  bool _loading = false;
  String? _errorMessage;
  bool _disposed = false;
  bool _seededLocalDemo = false;
  int _localSeq = 0;

  AuditSink? _audit;

  /// Senke fuers Aenderungsprotokoll (best-effort). Wird in main.dart verdrahtet.
  void setAuditSink(AuditSink sink) {
    _audit = sink;
  }

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
  List<SiteOrderList> get orderCarts => _orderCarts;
  List<SiteOrderList> get weeklyOrderLists => _weeklyLists;
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

  Product? productById(String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final product in _products) {
      if (product.id == id) {
        return product;
      }
    }
    return null;
  }

  // --- Bestelllisten: Wochen-Bestellkorb + Standard-Wochenliste ----------

  /// Der geteilte Bestellkorb eines Ladens (oder `null`, wenn leer/ungesetzt).
  SiteOrderList? orderCartForSite(String? siteId) =>
      _listForSite(_orderCarts, siteId);

  /// Die Standard-Wochenliste eines Ladens (oder `null`).
  SiteOrderList? weeklyListForSite(String? siteId) =>
      _listForSite(_weeklyLists, siteId);

  SiteOrderList? _listForSite(List<SiteOrderList> lists, String? siteId) {
    if (siteId == null || siteId.isEmpty) {
      // Einzel-Laden-Fallback: genau eine Liste vorhanden -> diese.
      return lists.length == 1 ? lists.first : null;
    }
    for (final list in lists) {
      if (list.siteId == siteId) {
        return list;
      }
    }
    return null;
  }

  /// Anzahl der Positionen im Bestellkorb (über alle Läden, wenn [siteId] null).
  int cartItemCount([String? siteId]) {
    if (siteId == null || siteId.isEmpty) {
      return _orderCarts.fold(0, (sum, cart) => sum + cart.itemCount);
    }
    return orderCartForSite(siteId)?.itemCount ?? 0;
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

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _setError(Object error) {
    _errorMessage = error is StateError ? error.message : error.toString();
    // Bei einem Stream-/Lade-Fehler den Ladezustand zuruecksetzen — sonst
    // zeigt der Bereich Fehlermeldung UND Dauer-Spinner (probleme #10).
    _loading = false;
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
    _orderCarts = await DatabaseService.loadLocalOrderCarts(scope: scope);
    _weeklyLists =
        await DatabaseService.loadLocalWeeklyOrderLists(scope: scope);
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
  Future<void> _persistOrderCarts() =>
      DatabaseService.saveLocalOrderCarts(_orderCarts, scope: _localScope);
  Future<void> _persistWeeklyLists() =>
      DatabaseService.saveLocalWeeklyOrderLists(_weeklyLists,
          scope: _localScope);

  Future<void> _persistAllLocal() async {
    await _persistSuppliers();
    await _persistProducts();
    await _persistOrders();
    await _persistMovements();
    await _persistPriceHistory();
    await _persistCustomerOrders();
    await _persistOrderCarts();
    await _persistWeeklyLists();
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
    _orderCarts = [];
    _weeklyLists = [];
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

    _orderCartsSubscription =
        _inventory.watchOrderCarts(orgId).listen((items) {
      _orderCarts = items;
      _safeNotify();
    }, onError: _setError);

    _weeklyListsSubscription =
        _inventory.watchWeeklyOrderLists(orgId).listen((items) {
      _weeklyLists = items;
      _safeNotify();
    }, onError: _setError);
  }

  Future<void> _cancelSubscriptions() async {
    await _suppliersSubscription?.cancel();
    await _productsSubscription?.cancel();
    await _ordersSubscription?.cancel();
    await _movementsSubscription?.cancel();
    await _customerOrdersSubscription?.cancel();
    await _orderCartsSubscription?.cancel();
    await _weeklyListsSubscription?.cancel();
    _suppliersSubscription = null;
    _productsSubscription = null;
    _ordersSubscription = null;
    _movementsSubscription = null;
    _customerOrdersSubscription = null;
    _orderCartsSubscription = null;
    _weeklyListsSubscription = null;
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
    // created vs. updated VOR einer evtl. neuen lokalen id bestimmen.
    final isNew = prepared.id == null || prepared.id!.isEmpty;
    if (_usesFirestore &&
        await _tryFirestore(
          'saveSupplier',
          () => _inventory.saveSupplier(prepared),
        )) {
      _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Lieferant',
        entityId: prepared.id,
        summary:
            'Lieferant „${prepared.name}" ${isNew ? 'angelegt' : 'aktualisiert'}',
      );
      return;
    }
    final stored = prepared.id == null
        ? prepared.copyWith(id: _nextLocalId('supplier'))
        : prepared;
    _upsertLocal(
      _suppliers,
      stored,
      (item) => item.id,
    );
    _suppliers.sort((a, b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _persistSuppliers();
    _safeNotify();
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Lieferant',
      entityId: stored.id,
      summary:
          'Lieferant „${stored.name}" ${isNew ? 'angelegt' : 'aktualisiert'}',
    );
  }

  Future<void> deleteSupplier(String supplierId) async {
    final orgId = _orgId;
    if (orgId == null) {
      return;
    }
    // Name VOR der Loeschung fuer eine lesbare Zusammenfassung nachschlagen.
    final name = supplierById(supplierId)?.name;
    final summary =
        name == null ? 'Lieferant gelöscht' : 'Lieferant „$name" gelöscht';
    if (_usesFirestore &&
        await _tryFirestore(
          'deleteSupplier',
          () => _inventory.deleteSupplier(
            orgId: orgId,
            supplierId: supplierId,
          ),
        )) {
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Lieferant',
        entityId: supplierId,
        summary: summary,
      );
      return;
    }
    _suppliers = _suppliers
        .where((supplier) => supplier.id != supplierId)
        .toList(growable: false);
    await _persistSuppliers();
    _safeNotify();
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Lieferant',
      entityId: supplierId,
      summary: summary,
    );
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
    // created vs. updated VOR einer evtl. neuen lokalen id bestimmen.
    final isNew = prepared.id == null || prepared.id!.isEmpty;
    if (_usesFirestore &&
        await _tryFirestore(
          'saveProduct',
          () => _inventory.saveProduct(prepared),
        )) {
      _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Produkt',
        entityId: prepared.id,
        summary:
            'Produkt „${prepared.name}" ${isNew ? 'angelegt' : 'aktualisiert'}',
      );
      return;
    }
    final stored = prepared.id == null
        ? prepared.copyWith(id: _nextLocalId('product'))
        : prepared;
    _upsertLocal(
      _products,
      stored,
      (item) => item.id,
    );
    _products
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _persistProducts();
    _safeNotify();
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Produkt',
      entityId: stored.id,
      summary:
          'Produkt „${stored.name}" ${isNew ? 'angelegt' : 'aktualisiert'}',
    );
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
    // Name VOR der Loeschung fuer eine lesbare Zusammenfassung nachschlagen.
    final name = productById(productId)?.name;
    final summary =
        name == null ? 'Produkt gelöscht' : 'Produkt „$name" gelöscht';
    if (_usesFirestore &&
        await _tryFirestore(
          'deleteProduct',
          () => _inventory.deleteProduct(
            orgId: orgId,
            productId: productId,
          ),
        )) {
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Produkt',
        entityId: productId,
        summary: summary,
      );
      return;
    }
    _products = _products
        .where((product) => product.id != productId)
        .toList(growable: false);
    await _persistProducts();
    _safeNotify();
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Produkt',
      entityId: productId,
      summary: summary,
    );
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
    // Lesbare Zusammenfassung: Artikelname (falls bekannt) + vorzeichenbehaftetes
    // Delta.
    final productName = productById(productId)?.name ?? productId;
    final signedDelta = delta > 0 ? '+$delta' : '$delta';
    final summary = 'Bestand „$productName" angepasst ($signedDelta)';
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
      _audit?.call(
        action: AuditAction.updated,
        entityType: 'Bestand',
        entityId: productId,
        summary: summary,
      );
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
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Bestand',
      entityId: productId,
      summary: summary,
    );
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
    // created vs. updated VOR einer evtl. neuen lokalen id bestimmen.
    final isNew = prepared.id == null || prepared.id!.isEmpty;
    final supplierName =
        supplierById(prepared.supplierId)?.name ?? prepared.supplierName;
    final summary = supplierName == null || supplierName.isEmpty
        ? 'Bestellung gespeichert'
        : 'Bestellung gespeichert (Lieferant „$supplierName")';
    if (_usesFirestore) {
      try {
        final newId = await _inventory.savePurchaseOrder(prepared);
        _audit?.call(
          action: isNew ? AuditAction.created : AuditAction.updated,
          entityType: 'Bestellung',
          entityId: newId,
          summary: summary,
        );
        return newId;
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
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Bestellung',
      entityId: withId.id,
      summary: summary,
    );
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
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Bestellung',
        entityId: orderId,
        summary: 'Bestellung gelöscht',
      );
      return;
    }
    _orders =
        _orders.where((order) => order.id != orderId).toList(growable: false);
    await _persistOrders();
    _safeNotify();
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Bestellung',
      entityId: orderId,
      summary: 'Bestellung gelöscht',
    );
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
    final receivedTotal =
        receivedByItemIndex.values.fold<int>(0, (sum, qty) => sum + qty);
    final auditSummary = 'Wareneingang gebucht ($receivedTotal Einheiten)';
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
      _audit?.call(
        action: AuditAction.updated,
        entityType: 'Wareneingang',
        entityId: orderId,
        summary: auditSummary,
      );
      return;
    }
    _applyLocalReceipt(orderId, receivedByItemIndex);
    await _persistOrders();
    await _persistProducts();
    await _persistMovements();
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Wareneingang',
      entityId: orderId,
      summary: auditSummary,
    );
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
    // created vs. updated VOR einer evtl. neuen lokalen id bestimmen.
    final isNew = prepared.id == null || prepared.id!.isEmpty;
    final customer = prepared.customerName.trim();
    final summary = customer.isEmpty
        ? 'Kundenbestellung gespeichert'
        : 'Kundenbestellung gespeichert (Kunde „$customer")';
    if (_usesFirestore) {
      try {
        final newId = await _inventory.saveCustomerOrder(prepared);
        _audit?.call(
          action: isNew ? AuditAction.created : AuditAction.updated,
          entityType: 'Kundenbestellung',
          entityId: newId,
          summary: summary,
        );
        return newId;
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
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Kundenbestellung',
      entityId: withId.id,
      summary: summary,
    );
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
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Kundenbestellung',
        entityId: orderId,
        summary: 'Kundenbestellung gelöscht',
      );
      return;
    }
    _customerOrders = _customerOrders
        .where((order) => order.id != orderId)
        .toList(growable: false);
    await _persistCustomerOrders();
    _safeNotify();
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Kundenbestellung',
      entityId: orderId,
      summary: 'Kundenbestellung gelöscht',
    );
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
          // Kontaktverknuepfung zur Kundenkartei mit uebernehmen, sonst geht
          // sie bei jeder Wiederholung verloren (probleme #41).
          contactId: order.contactId,
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

  // --- Bestelllisten: Mutationen -----------------------------------------

  /// Legt [product] mit [quantity] in den Bestellkorb des zugehörigen Ladens.
  /// Existiert die Position schon, wird die Menge **erhöht** (kollaboratives
  /// Sammeln über die Woche). Denormalisiert Name/Einheit/Kategorie/Lieferant
  /// aus dem Artikel. Offen für **jeden aktiven Mitarbeiter** (nicht nur
  /// Manager) – der entsprechende Firestore-Schreibpfad ist dafür freigegeben.
  Future<void> addToCart({
    required Product product,
    int quantity = 1,
    String? note,
  }) async {
    if (quantity <= 0 || product.id == null) {
      return;
    }
    final cart = orderCartForSite(product.siteId) ??
        SiteOrderList(
          orgId: _orgId ?? product.orgId,
          siteId: product.siteId,
          siteName: product.siteName,
          kind: OrderListKind.cart,
        );
    final items = [...cart.items];
    final index =
        items.indexWhere((item) => item.productId == product.id);
    if (index >= 0) {
      final existing = items[index];
      items[index] = existing.copyWith(
        name: product.name,
        unit: product.unit,
        category: product.category,
        clearCategory: product.category == null,
        supplierId: product.supplierId,
        supplierName: product.supplierName,
        clearSupplier: product.supplierId == null,
        quantity: existing.quantity + quantity,
        addedByUid: _currentUser?.uid,
        note: note,
      );
    } else {
      items.add(
        OrderListItem(
          productId: product.id,
          name: product.name,
          sku: product.sku,
          category: product.category,
          unit: product.unit,
          quantity: quantity,
          supplierId: product.supplierId,
          supplierName: product.supplierName,
          addedByUid: _currentUser?.uid,
          note: note,
        ),
      );
    }
    await _persistOrderList(
      cart.copyWith(
        siteName: product.siteName ?? cart.siteName,
        items: items,
        kind: OrderListKind.cart,
        updatedByUid: _currentUser?.uid,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Setzt die Menge einer Korb-Position. [quantity] <= 0 entfernt sie.
  Future<void> setCartItemQuantity({
    required String siteId,
    required String productId,
    required int quantity,
  }) async {
    final cart = orderCartForSite(siteId);
    if (cart == null) {
      return;
    }
    final items = <OrderListItem>[];
    for (final item in cart.items) {
      if (item.productId == productId) {
        if (quantity > 0) {
          items.add(item.copyWith(quantity: quantity));
        }
        // quantity <= 0 -> Position weglassen (entfernen)
      } else {
        items.add(item);
      }
    }
    await _persistOrderList(
      cart.copyWith(
        items: items,
        updatedByUid: _currentUser?.uid,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> removeCartItem({
    required String siteId,
    required String productId,
  }) =>
      setCartItemQuantity(siteId: siteId, productId: productId, quantity: 0);

  /// Leert den Bestellkorb eines Ladens (z.B. nach dem Checkout). Speichert eine
  /// leere Liste (Update-Pfad – funktioniert auch für Mitarbeiter ohne
  /// Lösch-Recht).
  Future<void> clearCart(String siteId) async {
    final cart = orderCartForSite(siteId);
    if (cart == null || cart.items.isEmpty) {
      return;
    }
    await _persistOrderList(
      cart.copyWith(
        items: const [],
        updatedByUid: _currentUser?.uid,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Füllt den Korb mit den Positionen der Standard-Wochenliste vor. Vorhandene
  /// Korb-Positionen (auch abweichende Mengen) bleiben **unangetastet**; nur
  /// fehlende Artikel werden ergänzt. Gibt die Zahl der ergänzten Positionen
  /// zurück (0, wenn keine Wochenliste existiert oder alles schon im Korb ist).
  Future<int> prefillCartFromWeeklyList(String siteId) async {
    final weekly = weeklyListForSite(siteId);
    if (weekly == null || weekly.items.isEmpty) {
      return 0;
    }
    final cart = orderCartForSite(siteId);
    final items = [...(cart?.items ?? const <OrderListItem>[])];
    var added = 0;
    for (final templateItem in weekly.items) {
      final alreadyInCart = templateItem.productId != null &&
          items.any((item) => item.productId == templateItem.productId);
      if (alreadyInCart) {
        continue;
      }
      items.add(templateItem.copyWith(addedByUid: _currentUser?.uid));
      added++;
    }
    if (added == 0) {
      return 0;
    }
    final base = cart ??
        SiteOrderList(
          orgId: _orgId ?? weekly.orgId,
          siteId: siteId,
          siteName: weekly.siteName,
          kind: OrderListKind.cart,
        );
    await _persistOrderList(
      base.copyWith(
        items: items,
        kind: OrderListKind.cart,
        updatedByUid: _currentUser?.uid,
        updatedAt: DateTime.now(),
      ),
    );
    return added;
  }

  /// Speichert die Standard-Wochenliste eines Ladens (Manager-Pfad).
  Future<void> saveWeeklyList(SiteOrderList list) async {
    // Explizite „Liste speichern"-Aktion (eigener Speichern-Button im Editor),
    // KEIN inkrementelles Autosave -> protokollieren. Der Log sitzt hier statt im
    // gemeinsamen _persistOrderList, weil Letzteres auch jede Korb-Mutation
    // (Rauschen) persistiert. _persistOrderList wirft bei cloud-only-Fehlern ->
    // der Log wird nur nach erfolgreichem await erreicht.
    await _persistOrderList(
      list.copyWith(
        kind: OrderListKind.weeklyTemplate,
        updatedByUid: _currentUser?.uid,
        updatedAt: DateTime.now(),
      ),
    );
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Bestellliste',
      entityId: list.siteId,
      summary: 'Wochen-Bestellliste gespeichert',
    );
  }

  /// Löst den Bestellkorb eines Ladens als echte Bestellung(en) aus: gruppiert
  /// nach Lieferant und legt je Gruppe eine `PurchaseOrder` (Status „Bestellt")
  /// an – Preis/Einheit/Lieferant **live** aus dem aktuellen Artikel, sonst aus
  /// den denormalisierten Korb-Werten. Artikel ohne Lieferant landen in einer
  /// Sammelbestellung „Ohne Lieferant". Leert den Korb danach. Gibt die IDs der
  /// erzeugten Bestellungen zurück. Manager-Pfad.
  Future<List<String>> checkoutCart(String siteId) async {
    final cart = orderCartForSite(siteId);
    if (cart == null || cart.items.isEmpty) {
      return const [];
    }
    // Gruppierung nach dem LIVE-Lieferanten des Artikels (ein zwischenzeitlicher
    // Lieferantenwechsel greift), Fallback auf den denormalisierten Korb-Wert.
    final groups = <String, List<OrderListItem>>{};
    for (final item in cart.items) {
      final liveSupplierId = productById(item.productId)?.supplierId;
      final supplierKey = ((liveSupplierId ?? item.supplierId) ?? '').trim();
      groups.putIfAbsent(supplierKey, () => []).add(item);
    }
    final createdIds = <String>[];
    try {
      for (final entry in groups.entries) {
        final supplierId = entry.key;
        final supplier = supplierById(supplierId);
        final orderItems = entry.value.map((cartItem) {
          final product = productById(cartItem.productId);
          return PurchaseOrderItem(
            productId: cartItem.productId,
            name: product?.name ?? cartItem.name,
            sku: product?.sku ?? cartItem.sku,
            unit: product?.unit ?? cartItem.unit,
            quantityOrdered: cartItem.quantity,
            unitPriceCents: product?.purchasePriceCents,
          );
        }).toList(growable: false);
        final order = PurchaseOrder(
          orgId: _orgId ?? cart.orgId,
          siteId: siteId,
          siteName: cart.siteName,
          supplierId: supplierId,
          supplierName: supplier?.name ??
              (supplierId.isEmpty
                  ? 'Ohne Lieferant'
                  : entry.value.first.supplierName),
          status: PurchaseOrderStatus.ordered,
          items: orderItems,
          orderedAt: DateTime.now(),
        );
        createdIds.add(await savePurchaseOrder(order));
      }
    } catch (error) {
      // Teilfehler (z.B. cloud-only Firestore-Fehler mitten in der Schleife):
      // die bereits erzeugten Bestellungen best-effort zurücknehmen, damit ein
      // Retry nichts doppelt anlegt (savePurchaseOrder ist nicht idempotent).
      // Der Korb bleibt unverändert -> der Nutzer kann sauber neu auslösen.
      for (final id in createdIds) {
        try {
          await deletePurchaseOrder(id);
        } catch (_) {
          // Kompensation best-effort.
        }
      }
      rethrow;
    }
    // Nur die tatsächlich ausgelösten Positionen entfernen – gleichzeitige
    // Mitarbeiter-Adds während des Checkouts bleiben so erhalten.
    await _removeCartItems(siteId, cart.items);
    return createdIds;
  }

  /// Stabiler Schlüssel einer Korb-Position für gezieltes Entfernen (per
  /// productId; ohne id über Name+Einheit).
  static String _cartItemKey(OrderListItem item) =>
      (item.productId != null && item.productId!.isNotEmpty)
          ? 'p:${item.productId}'
          : 'n:${item.name}|${item.unit}';

  /// Entfernt gezielt die [removed]-Positionen aus dem aktuellen Korb (statt ihn
  /// komplett zu leeren), damit parallel hinzugefügte Positionen erhalten
  /// bleiben.
  Future<void> _removeCartItems(
    String siteId,
    List<OrderListItem> removed,
  ) async {
    final current = orderCartForSite(siteId);
    if (current == null || current.items.isEmpty) {
      return;
    }
    final removedKeys = removed.map(_cartItemKey).toSet();
    final remaining = current.items
        .where((item) => !removedKeys.contains(_cartItemKey(item)))
        .toList();
    if (remaining.length == current.items.length) {
      return;
    }
    await _persistOrderList(
      current.copyWith(
        items: remaining,
        updatedByUid: _currentUser?.uid,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Persistiert eine Bestellliste (Korb oder Wochenliste) nach dem
  /// Drei-Speichermodi-Muster. Doc-ID = `siteId` (Singleton je Laden); die
  /// Ziel-Collection ergibt sich aus [SiteOrderList.kind].
  ///
  /// Hinweis: Im cloud/hybrid-Modus lesen die Korb-Mutatoren den aktuellen Stand
  /// aus dem gestreamten `_orderCarts`, ändern ihn und schreiben die **ganze**
  /// Liste zurück. Zwei fast gleichzeitige Änderungen (vor der nächsten
  /// Stream-Emission) sind damit „last writer wins". Für zwei Läden mit wenigen
  /// Mitarbeitern ist das bewusst akzeptiert (keine Transaktion/kein Merge je
  /// Position); bei echtem Mehrnutzer-Andrang müsste eine Array-Union-Transaktion
  /// im Repository ergänzt werden.
  Future<void> _persistOrderList(SiteOrderList list) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    final prepared = list.copyWith(orgId: orgId, id: list.siteId);
    if (_usesFirestore &&
        await _tryFirestore(
          'saveOrderList',
          () => _inventory.saveOrderList(prepared),
        )) {
      return;
    }
    if (prepared.kind == OrderListKind.weeklyTemplate) {
      _upsertLocal(_weeklyLists, prepared, (item) => item.siteId);
      _weeklyLists = [..._weeklyLists];
      await _persistWeeklyLists();
    } else {
      _upsertLocal(_orderCarts, prepared, (item) => item.siteId);
      _orderCarts = [..._orderCarts];
      await _persistOrderCarts();
    }
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
