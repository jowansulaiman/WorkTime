import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/assortment_analysis.dart';
import '../core/hybrid_write_fallback.dart';
import '../core/assortment_gap.dart';
import '../core/basket_analysis.dart';
import '../core/cash_state.dart';
import '../core/cashier_anomaly.dart';
import '../core/daily_closing.dart';
import '../core/kasse_report.dart';
import '../core/dead_stock.dart';
import '../core/ean.dart';
import '../core/expiry_warning.dart';
import '../core/fridge_refill_shortfall.dart';
import '../core/local_demo_data.dart';
import '../core/local_demo_inventory_data.dart';
import '../core/price_deviation.dart';
import '../core/reorder_suggestion.dart';
import '../core/sales_velocity.dart';
import '../core/seasonal_factor.dart';
import '../core/shrinkage_report.dart';
import '../core/staffing_profile.dart';
import '../core/store_health.dart';
import '../models/app_user.dart';
import '../models/audit_log_entry.dart';
import '../models/cash_closing.dart';
import '../models/cash_count.dart';
import '../models/customer_order.dart';
import '../models/fridge_refill.dart';
import '../models/order_cart.dart';
import '../models/pos_daily_stat.dart';
import '../models/pos_receipt.dart';
import '../models/price_history_entry.dart';
import '../models/product.dart';
import '../models/product_batch.dart';
import '../models/purchase_order.dart';
import '../models/scan_event.dart';
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
class InventoryProvider extends ChangeNotifier with HybridWriteFallback {
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
  StreamSubscription<List<ProductBatch>>? _batchesSubscription;
  StreamSubscription<List<PurchaseOrder>>? _ordersSubscription;
  StreamSubscription<List<StockMovement>>? _movementsSubscription;
  StreamSubscription<List<CustomerOrder>>? _customerOrdersSubscription;
  StreamSubscription<List<SiteOrderList>>? _orderCartsSubscription;
  StreamSubscription<List<SiteOrderList>>? _weeklyListsSubscription;
  StreamSubscription<List<FridgeRefillList>>? _fridgeListsSubscription;

  AppUserProfile? _currentUser;
  List<Supplier> _suppliers = [];
  List<Product> _products = [];
  List<ProductBatch> _batches = [];
  List<PurchaseOrder> _orders = [];
  List<StockMovement> _movements = [];
  List<PriceHistoryEntry> _priceHistory = [];
  List<CustomerOrder> _customerOrders = [];
  List<SiteOrderList> _orderCarts = [];
  List<SiteOrderList> _weeklyLists = [];
  // #48: eigener Fehlerzustand der Bestelllisten-Streams (Korb/Wochenliste),
  // damit ein Teil-Ausfall nicht die globale _errorMessage einfaerbt und die
  // UI "leer" nicht mit "konnte nicht geladen werden" verwechselt.
  bool _orderListsLoadFailed = false;
  List<FridgeRefillList> _fridgeLists = [];
  List<ScanEvent> _scanEvents = [];

  // Cloud-only Kassenfakten fuer die lokale Demo-Session. Sie werden bewusst
  // weder ueber [DatabaseService] geladen noch in SharedPreferences
  // geschrieben. Ein Sessionwechsel verwirft auch lokale Demo-Mutationen.
  List<PosReceipt> _localDemoPosReceipts = [];
  List<PosDailyStat> _localDemoPosDailyStats = [];
  List<CashCount> _localDemoCashCounts = [];
  List<CashClosing> _localDemoCashClosings = [];

  /// Ob der lokale Telemetrie-Spiegel bereits geladen wurde. Anders als die
  /// uebrigen Collections gibt es fuer scanEvents KEINEN Stream, der die
  /// In-Memory-Liste fuellt — im hybrid-Modus muss der Spiegel vor dem ersten
  /// Append/Fallback-Read explizit geladen werden, sonst ueberschreibt der
  /// erste Scan der Session den kompletten Alt-Spiegel.
  bool _scanEventsLoaded = false;
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

  // --- Auto-Buchung Umsatz/Wareneinsatz → Finanzen (H-A2) ------------------
  // Best-effort, fire-and-forget; deterministische Journal-IDs (co-/po-<id>)
  // sichern Idempotenz (keine Doppelbuchung im hybrid-Fallback). Aus der
  // lebenden FinanceProvider-Instanz in main.dart gesetzt (Finance steht NACH
  // Inventory in der Kette → Injektion per Sink, keine Kettenumsortierung).
  Future<String?> Function(CustomerOrder order)? _revenuePoster;
  Future<String?> Function(PurchaseOrder order)? _goodsCostPoster;

  void setRevenueJournalPoster(Future<String?> Function(CustomerOrder)? poster) {
    _revenuePoster = poster;
  }

  void setGoodsCostJournalPoster(Future<String?> Function(PurchaseOrder)? poster) {
    _goodsCostPoster = poster;
  }

  Future<void> _bookCustomerOrderRevenueIfNeeded(
    CustomerOrder order,
    CustomerOrderStatus? oldStatus,
  ) async {
    final poster = _revenuePoster;
    if (poster == null) return;
    if (order.status != CustomerOrderStatus.pickedUp) return;
    if (oldStatus == CustomerOrderStatus.pickedUp) return;
    try {
      await poster(order);
    } catch (error) {
      AppLogger.warning('Umsatz-Buchung fehlgeschlagen', error: error);
    }
  }

  Future<void> _bookPurchaseOrderCostIfNeeded(
    PurchaseOrder order,
    PurchaseOrderStatus? oldStatus,
  ) async {
    final poster = _goodsCostPoster;
    if (poster == null) return;
    if (order.status != PurchaseOrderStatus.received) return;
    if (oldStatus == PurchaseOrderStatus.received) return;
    try {
      await poster(order);
    } catch (error) {
      AppLogger.warning('Wareneinsatz-Buchung fehlgeschlagen', error: error);
    }
  }

  CustomerOrderStatus? _customerOrderStatus(String? id) {
    if (id == null) return null;
    for (final o in _customerOrders) {
      if (o.id == id) return o.status;
    }
    return null;
  }

  PurchaseOrderStatus? _purchaseOrderStatus(String? id) =>
      _purchaseOrderForId(id)?.status;

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
  List<FridgeRefillList> get fridgeRefillLists => _fridgeLists;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;

  /// #48: true, wenn der Bestellkorb-/Wochenlisten-Stream fehlgeschlagen ist.
  /// Die Korb-UI zeigt dann einen Ladefehler statt eines leeren Korbs.
  bool get orderListsLoadFailed => _orderListsLoadFailed;

  bool get usesLocalStorage => _forceLocalStorage || _localStorageOnly;
  bool get _usesFirestore => !usesLocalStorage;
  @override
  bool get usesHybridStorage =>
      !_forceLocalStorage && !_localStorageOnly && _hybridStorageEnabled;
  String? get _orgId => _currentUser?.orgId;

  /// Strikte Ausnahme fuer die Demo: Ein Demo-Konto im Cloud-Modus benutzt
  /// weiterhin ausschliesslich das Repository. Nur die lokale Demo-Session
  /// darf auf die ephemeren Kassenfakten zugreifen.
  bool get _usesLocalDemoFacts =>
      usesLocalStorage && LocalDemoData.isDemoUser(_currentUser);

  /// Versucht eine Firestore-Mutation. Erfolg -> true (Aufrufer ist fertig).
  /// Im Hybrid-Modus bei Fehler -> false (Aufrufer faellt lokal zurueck, damit
  /// offline nichts verloren geht). Im Cloud-only-Modus wird der Fehler
  /// durchgereicht.
  // Q1: zentrale Offline-Positivliste (HybridWriteFallback).
  @override
  String get hybridFallbackLabel => 'Inventory';

  Future<bool> _tryFirestore(
    String label,
    Future<void> Function() action,
  ) =>
      tryFirestoreWrite(label, action);

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
    // Toleriert die UPC-A(12) <-> EAN-13(0+12)-Leading-Zero-Variante (iOS liefert
    // UPC-A teils als EAN-13 mit fuehrender Null) — sonst Fehl-Miss beim Lookup.
    final variants = gtinLookupVariants(code);
    return _products
        .where(
          (product) =>
              (includeInactive || product.isActive) &&
              variants.contains(product.barcode?.trim() ?? '') &&
              (siteId == null || siteId.isEmpty || product.siteId == siteId),
        )
        .toList(growable: false);
  }

  /// Offene, noch nicht gelieferte Bestellmenge je Artikel.
  ///
  /// Nur tatsächlich abgeschickte Bestellungen und Teillieferungen zählen als
  /// „unterwegs". Entwürfe, gelieferte und stornierte Bestellungen bleiben
  /// außen vor. Positionen ohne stabile Artikel-ID können nicht zugeordnet
  /// werden und werden deshalb ignoriert.
  Map<String, int> incomingQuantityByProductId({String? siteId}) {
    final result = <String, int>{};
    for (final order in _orders) {
      if (order.status != PurchaseOrderStatus.ordered &&
          order.status != PurchaseOrderStatus.partiallyReceived) {
        continue;
      }
      if (siteId != null && siteId.isNotEmpty && order.siteId != siteId) {
        continue;
      }
      for (final item in order.items) {
        final productId = item.productId?.trim();
        if (productId == null || productId.isEmpty) {
          continue;
        }
        final outstanding = item.outstandingQuantity;
        if (outstanding <= 0) {
          continue;
        }
        result[productId] = (result[productId] ?? 0) + outstanding;
      }
    }
    return result;
  }

  /// **WW-3:** Offene Bestellungen mit erwartetem Liefertermin (rein
  /// clientseitig aus den gestreamten Orders — kein Query, kein Index).
  ///
  /// [day] filtert auf einen Kalendertag (Standard: alle offenen Termine),
  /// [siteId] auf einen Laden. Nur [PurchaseOrder.isDeliveryPending]-Bestellungen
  /// (offen, nicht geschlossen, mit `expectedAt`); sortiert nach Termin.
  List<PurchaseOrder> expectedDeliveries({DateTime? day, String? siteId}) {
    final result = <PurchaseOrder>[];
    for (final order in _orders) {
      if (!order.isDeliveryPending) continue;
      if (siteId != null && siteId.isNotEmpty && order.siteId != siteId) {
        continue;
      }
      if (day != null) {
        final due = order.expectedAt!;
        if (due.year != day.year ||
            due.month != day.month ||
            due.day != day.day) {
          continue;
        }
      }
      result.add(order);
    }
    result.sort((a, b) => a.expectedAt!.compareTo(b.expectedAt!));
    return result;
  }

  /// Ob der Artikel auch unter Einrechnung bereits bestellter Ware den
  /// Meldebestand erreicht oder unterschreitet.
  bool needsReorderAfterIncoming(Product product) {
    final incoming =
        product.id == null
            ? 0
            : incomingQuantityByProductId(siteId: product.siteId)[product
                    .id!] ??
                0;
    return _needsReorderAfterIncoming(product, incoming);
  }

  /// Konkrete Nachbestellmenge abzüglich bereits unterwegs befindlicher Ware.
  ///
  /// Die zugrunde liegende Produktlogik (explizite Bestellmenge bzw. Auffüllen
  /// bis Zielbestand) bleibt erhalten; die offene Menge wird danach abgezogen.
  /// Das Ergebnis ist 0, wenn der Meldebestand durch den Zulauf bereits gedeckt
  /// ist. Bleibt der projizierte Bestand trotz einer vollständig angerechneten
  /// festen Losgröße am Meldebestand, wird ein weiteres Los vorgeschlagen.
  int suggestedReorderQuantityAfterIncoming(
    Product product, {
    int? incomingQuantity,
  }) {
    final resolvedIncoming =
        incomingQuantity ??
        (product.id == null
            ? 0
            : incomingQuantityByProductId(siteId: product.siteId)[product
                    .id!] ??
                0);
    final incoming = resolvedIncoming > 0 ? resolvedIncoming : 0;
    if (!_needsReorderAfterIncoming(product, incoming)) {
      return 0;
    }
    final reduced = product.suggestedReorderQuantity - incoming;
    if (reduced > 0) {
      return reduced;
    }
    final configuredLotSize = product.reorderQuantity;
    return configuredLotSize != null && configuredLotSize > 0
        ? configuredLotSize
        : 1;
  }

  bool _needsReorderAfterIncoming(Product product, int incoming) =>
      product.isActive &&
      product.minStock > 0 &&
      product.currentStock + incoming <= product.minStock;

  /// Artikel, die nach Einrechnung bestellter Ware weiterhin nachbestellt
  /// werden sollten (`Bestand + unterwegs <= Meldebestand`).
  List<Product> lowStockProducts({String? siteId}) {
    final incoming = incomingQuantityByProductId(siteId: siteId);
    return productsForSite(siteId)
        .where((product) {
          final incomingQuantity =
              product.id == null ? 0 : incoming[product.id!] ?? 0;
          return _needsReorderAfterIncoming(product, incomingQuantity);
        })
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

  // --- Kühlschrank-Nachfüllliste -----------------------------------------

  /// Die Kühlschrank-Nachfüllliste eines Ladens (oder `null`, wenn leer/
  /// ungesetzt). Bei Einzel-Laden-Org ist die einzige Liste der Fallback.
  FridgeRefillList? fridgeRefillListForSite(String? siteId) {
    if (siteId == null || siteId.isEmpty) {
      return _fridgeLists.length == 1 ? _fridgeLists.first : null;
    }
    for (final list in _fridgeLists) {
      if (list.siteId == siteId) {
        return list;
      }
    }
    return null;
  }

  /// Positionen der Nachfüllliste eines Ladens (leer, wenn keine existiert).
  List<FridgeRefillItem> fridgeRefillItems(String? siteId) =>
      fridgeRefillListForSite(siteId)?.items ?? const <FridgeRefillItem>[];

  /// Anzahl noch nachzufüllender (nicht abgehakter) Positionen — für Badges.
  /// Über alle Läden, wenn [siteId] null/leer.
  int fridgeRefillOpenCount([String? siteId]) {
    if (siteId == null || siteId.isEmpty) {
      return _fridgeLists.fold(0, (sum, list) => sum + list.openCount);
    }
    return fridgeRefillListForSite(siteId)?.openCount ?? 0;
  }

  /// **Kühlschrank-Soll-Ist-Automatik.** Artikel, deren Kühlschrank-Ist unter dem
  /// Soll liegt und für die im Lager noch Ware vorhanden ist ("fehlt im
  /// Kühlschrank"), absteigend nach Defizit. Rein berechnet aus dem laufenden
  /// Produkt-Stand (kein neuer Stream), optional je Standort.
  List<FridgeShortfall> fridgeShortfalls({String? siteId}) =>
      computeFridgeShortfalls(_products, siteId: siteId);

  /// Anzahl der Kühlschrank-Lücken (für Badge/Benachrichtigung), optional je Laden.
  int fridgeShortfallCount([String? siteId]) =>
      computeFridgeShortfalls(_products, siteId: siteId).length;

  // --- MHD-/Ablauf-Chargen ------------------------------------------------

  /// Alle erfassten Warenchargen (inkl. abverkaufter/entsorgter — die Warnung
  /// filtert auf `active`).
  List<ProductBatch> get productBatches => _batches;

  /// MHD-/Ablauf-Warnungen (dringendste zuerst), optional je Standort. [now]
  /// ist injizierbar (Tests); sonst die Wall-Clock. [leadDays] = Vorwarnzeit.
  List<ExpiryWarning> expiryWarnings({
    String? siteId,
    int leadDays = 3,
    DateTime? now,
  }) =>
      computeExpiryWarnings(
        _batches,
        now ?? DateTime.now(),
        leadDays: leadDays,
        siteId: siteId,
      );

  /// Anzahl der offenen Ablauf-Warnungen (für Badge/Kachel-Zähler).
  int expiryWarningCount({String? siteId, int leadDays = 3, DateTime? now}) =>
      expiryWarnings(siteId: siteId, leadDays: leadDays, now: now).length;

  ProductBatch? _batchById(String id) {
    for (final batch in _batches) {
      if (batch.id == id) return batch;
    }
    return null;
  }

  String _formatDay(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.'
      '${date.month.toString().padLeft(2, '0')}.${date.year}';

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

  // --- Bestellhäufigkeit ("häufig bestellte Artikel") --------------------
  //
  // Rein aus der bereits im Speicher liegenden Bestellhistorie (`_orders`)
  // abgeleitet — kein Firestore-Index, kein Repo-Zugriff, deckt local/cloud/
  // hybrid einheitlich ab (analog zum Barcode-Lookup). Eine Bestellung zählt je
  // Artikel genau 1× (Häufigkeit der Bestellvorgänge, nicht der Stückzahl);
  // stornierte Bestellungen werden ignoriert. Memoisiert je Laden, invalidiert
  // bei jedem `notifyListeners` (siehe [_safeNotify]).

  /// Rollierendes Fenster, in dem ein Artikel als „häufig bestellt" zählt.
  static const Duration orderFrequencyWindow = Duration(days: 84); // ~12 Wochen

  final Map<String, Map<String, int>> _orderFreqCache = {};

  /// Wie oft jeder Artikel ([productId] → Anzahl) innerhalb
  /// [orderFrequencyWindow] in nicht stornierten Lieferantenbestellungen
  /// vorkam, optional auf einen [siteId]-Laden beschränkt. Datum einer
  /// Bestellung = `orderedAt ?? createdAt`. [now] nur für Tests; im Normalfall
  /// (null) wird `DateTime.now()` benutzt und das Ergebnis memoisiert.
  Map<String, int> orderFrequencyByProduct({String? siteId, DateTime? now}) {
    final useCache = now == null;
    final reference = now ?? DateTime.now();
    // Tag in den Cache-Key aufnehmen: Eine über Mitternacht offene Sitzung ohne
    // Datenänderung (z.B. Kassen-Tablet) bekäme sonst das Fenster von gestern.
    final key = useCache
        ? '${siteId ?? ''}|${reference.year}-${reference.month}-${reference.day}'
        : '';
    if (useCache) {
      final cached = _orderFreqCache[key];
      if (cached != null) {
        return cached;
      }
    }
    final cutoff = reference.subtract(orderFrequencyWindow);
    final counts = <String, int>{};
    for (final order in _orders) {
      if (order.status == PurchaseOrderStatus.cancelled) {
        continue;
      }
      if (siteId != null && siteId.isNotEmpty && order.siteId != siteId) {
        continue;
      }
      final when = order.orderedAt ?? order.createdAt;
      if (when == null || when.isBefore(cutoff)) {
        continue;
      }
      final counted = <String>{};
      for (final item in order.items) {
        final pid = item.productId;
        if (pid == null || pid.isEmpty) {
          continue;
        }
        if (!counted.add(pid)) {
          continue; // pro Bestellung nur einmal zählen
        }
        counts[pid] = (counts[pid] ?? 0) + 1;
      }
    }
    if (useCache) {
      _orderFreqCache[key] = counts;
    }
    return counts;
  }

  /// Bestellhäufigkeit eines einzelnen Artikels (0, wenn nie/außerhalb Fenster).
  int orderFrequencyFor(String productId, {String? siteId}) =>
      orderFrequencyByProduct(siteId: siteId)[productId] ?? 0;

  /// Kopiert [products] und sortiert: häufiger bestellt zuerst, dann nach Name.
  /// Seam für alle Bestell-Listen (Schnell-Hinzufügen, Picker, Bestelleditor).
  List<Product> sortByOrderFrequency(List<Product> products, {String? siteId}) {
    final freq = orderFrequencyByProduct(siteId: siteId);
    final list = [...products];
    list.sort((a, b) => _compareByOrderFrequency(a, b, freq));
    return list;
  }

  /// Aktive Artikel eines Ladens, die im Fenster mindestens einmal bestellt
  /// wurden — absteigend nach Häufigkeit, gekappt auf [limit] (≤0 = alle).
  /// Für die Scanner-Schnellwahl „Häufig bestellt".
  List<Product> frequentlyOrderedProducts({String? siteId, int limit = 8}) {
    final freq = orderFrequencyByProduct(siteId: siteId);
    final list = productsForSite(siteId)
        .where((product) => product.isActive && (freq[product.id] ?? 0) > 0)
        .toList()
      ..sort((a, b) => _compareByOrderFrequency(a, b, freq));
    if (limit > 0 && list.length > limit) {
      return list.sublist(0, limit);
    }
    return list;
  }

  int _compareByOrderFrequency(Product a, Product b, Map<String, int> freq) {
    final fa = freq[a.id] ?? 0;
    final fb = freq[b.id] ?? 0;
    if (fa != fb) {
      return fb.compareTo(fa); // höhere Häufigkeit zuerst
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  void _safeNotify() {
    if (!_disposed) {
      // Daten haben sich geändert -> Häufigkeits-Memo verwerfen.
      _orderFreqCache.clear();
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
    _seededLocalDemo = false;
    _clearLocalDemoFacts();
    // Scan-Telemetrie ist nicht stream-gespeist -> beim Sessionwechsel
    // explizit zuruecksetzen, sonst koennten Events der alten Session in den
    // Spiegel der neuen geschrieben werden.
    _scanEvents = [];
    _scanEventsLoaded = false;

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
    _batches = await DatabaseService.loadLocalProductBatches(scope: scope);
    _orders = await DatabaseService.loadLocalPurchaseOrders(scope: scope);
    _movements = await DatabaseService.loadLocalStockMovements(scope: scope);
    _priceHistory = await DatabaseService.loadLocalPriceHistory(scope: scope);
    _customerOrders =
        await DatabaseService.loadLocalCustomerOrders(scope: scope);
    _orderCarts = await DatabaseService.loadLocalOrderCarts(scope: scope);
    _weeklyLists =
        await DatabaseService.loadLocalWeeklyOrderLists(scope: scope);
    _fridgeLists =
        await DatabaseService.loadLocalFridgeRefillLists(scope: scope);
    _scanEvents = await DatabaseService.loadLocalScanEvents(scope: scope);
    _scanEventsLoaded = true;
  }

  Future<void> _persistSuppliers() =>
      DatabaseService.saveLocalSuppliers(_suppliers, scope: _localScope);
  Future<void> _persistProducts() =>
      DatabaseService.saveLocalProducts(_products, scope: _localScope);
  Future<void> _persistBatches() =>
      DatabaseService.saveLocalProductBatches(_batches, scope: _localScope);
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
  Future<void> _persistFridgeLists() =>
      DatabaseService.saveLocalFridgeRefillLists(_fridgeLists,
          scope: _localScope);
  Future<void> _persistScanEvents() =>
      DatabaseService.saveLocalScanEvents(_scanEvents, scope: _localScope);

  Future<void> _persistAllLocal() async {
    await _persistSuppliers();
    await _persistProducts();
    await _persistBatches();
    await _persistOrders();
    await _persistMovements();
    await _persistPriceHistory();
    await _persistCustomerOrders();
    await _persistOrderCarts();
    await _persistWeeklyLists();
    await _persistFridgeLists();
    await _persistScanEvents();
  }

  // --- Speichermodus-Migration (H-H1) -------------------------------------

  /// Snapshot des aktuellen (Cloud-)Warenwirtschafts-Stands in den lokalen
  /// Speicher (für den Wechsel cloud/hybrid → local).
  Future<void> cacheCloudStateLocally() async {
    if (usesLocalStorage) return;
    await _persistAllLocal();
  }

  /// Lädt Stamm-/Bestelldaten beim Wechsel local→Cloud/Hybrid hoch (Upsert über
  /// die Doc-ID → idempotent). Bewusst NICHT die append-only Ledger
  /// (StockMovement/PriceHistory) — die würden bei Re-Sync duplizieren; sie
  /// entstehen ohnehin aus künftigen Buchungen neu.
  Future<void> syncLocalStateToCloud() async {
    final orgId = _orgId;
    if (orgId == null) return;
    Future<void> push(String label, Future<void> Function() write) async {
      try {
        await write();
      } catch (error) {
        AppLogger.warning('syncLocalStateToCloud(inventory:$label): $error');
      }
    }

    for (final s in List<Supplier>.from(_suppliers)) {
      await push('supplier', () => _inventory.saveSupplier(s.copyWith(orgId: orgId)));
    }
    for (final p in List<Product>.from(_products)) {
      await push('product', () => _inventory.saveProduct(p.copyWith(orgId: orgId)));
    }
    for (final o in List<PurchaseOrder>.from(_orders)) {
      await push('order', () => _inventory.savePurchaseOrder(o.copyWith(orgId: orgId)));
    }
    for (final co in List<CustomerOrder>.from(_customerOrders)) {
      await push('customerOrder',
          () => _inventory.saveCustomerOrder(co.copyWith(orgId: orgId)));
    }
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
    final demo = LocalDemoInventoryData.allForOrg(
      orgId: user.orgId,
      actorUid: user.uid,
      now: DateTime.now(),
    );

    // Diese vier Collections bleiben absichtlich rein ephemer. Insbesondere
    // duerfen sie nicht in [_persistAllLocal] aufgenommen werden.
    _localDemoPosReceipts = List<PosReceipt>.of(demo.cloudPosReceipts);
    _localDemoPosDailyStats = List<PosDailyStat>.of(demo.cloudPosDailyStats);
    _localDemoCashCounts = List<CashCount>.of(demo.cloudCashCounts);
    _localDemoCashClosings = List<CashClosing>.of(demo.cloudCashClosings);

    var seeded = false;

    List<T> withMissingDemoItems<T>(
      List<T> current,
      List<T> fixtures,
      String? Function(T) idOf,
    ) {
      final knownIds = current.map(idOf).whereType<String>().toSet();
      final missing = fixtures
          .where((item) {
            final id = idOf(item);
            return id != null && !knownIds.contains(id);
          })
          .toList(growable: false);
      if (missing.isEmpty) return current;
      seeded = true;
      return [...current, ...missing];
    }

    // Auch bereits verwendete Demo-Profile erhalten neue Fixture-Bereiche.
    // Der Merge ueber stabile IDs erhaelt bestehende/veraenderte Datensaetze
    // und fuegt bei spaeteren Releases nur noch fehlende Beispiele hinzu.
    _suppliers = withMissingDemoItems(
      _suppliers,
      demo.suppliers,
      (item) => item.id,
    );
    _products = withMissingDemoItems(
      _products,
      demo.products,
      (item) => item.id,
    );
    _batches = withMissingDemoItems(
      _batches,
      demo.productBatches,
      (item) => item.id,
    );
    _orders = withMissingDemoItems(
      _orders,
      demo.purchaseOrders,
      (item) => item.id,
    );
    _movements = withMissingDemoItems(
      _movements,
      demo.stockMovements,
      (item) => item.id,
    );
    _priceHistory = withMissingDemoItems(
      _priceHistory,
      demo.priceHistory,
      (item) => item.id,
    );
    _customerOrders = withMissingDemoItems(
      _customerOrders,
      demo.customerOrders,
      (item) => item.id,
    );
    _orderCarts = withMissingDemoItems(
      _orderCarts,
      demo.orderCarts,
      (item) => item.id,
    );
    _weeklyLists = withMissingDemoItems(
      _weeklyLists,
      demo.weeklyOrderLists,
      (item) => item.id,
    );
    _fridgeLists = withMissingDemoItems(
      _fridgeLists,
      demo.fridgeRefillLists,
      (item) => item.id,
    );
    _scanEvents = withMissingDemoItems(
      _scanEvents,
      demo.scanEvents,
      (item) => item.id,
    );
    return seeded;
  }

  void _clearLocalDemoFacts() {
    _localDemoPosReceipts = [];
    _localDemoPosDailyStats = [];
    _localDemoCashCounts = [];
    _localDemoCashClosings = [];
  }

  void _resetData() {
    _suppliers = [];
    _products = [];
    _batches = [];
    _orders = [];
    _movements = [];
    _priceHistory = [];
    _customerOrders = [];
    _orderCarts = [];
    _weeklyLists = [];
    _orderListsLoadFailed = false;
    _fridgeLists = [];
    _scanEvents = [];
    _scanEventsLoaded = false;
    _clearLocalDemoFacts();
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

    _batchesSubscription =
        _inventory.watchProductBatches(orgId).listen((items) {
      _batches = items;
      _safeNotify();
    }, onError: _setError);

    _ordersSubscription =
        _inventory.watchPurchaseOrders(orgId).listen((items) {
      _orders = items;
      _safeNotify();
    }, onError: _setError);

    // PA-4.4g: Im Kiosk-Build NICHT abonnieren — die stockMovements-Rules
    // verweigern dem role:kiosk-Geraetekonto den Read (PA-0.1); ein
    // permission-denied hier wuerde via _setError den GESAMTEN Provider (und
    // damit das Board: Produkte/Kuehlschrank/Ablauf) in den Fehlerzustand
    // reissen. Bestandsbewegungen braucht das Board nicht.
    if (!AppConfig.kioskModeEnabled) {
      _movementsSubscription =
          _inventory.watchStockMovements(orgId).listen((items) {
        _movements = items;
        _safeNotify();
      }, onError: _setError);
    }

    _customerOrdersSubscription =
        _inventory.watchCustomerOrders(orgId).listen((items) {
      _customerOrders = items;
      _safeNotify();
    }, onError: _setError);

    // #48: Bestelllisten-Stream-Fehler NICHT auf die globale _errorMessage
    // legen — ein Teil-Ausfall des Korbs wuerde sonst die gesamte
    // Warenwirtschaft als fehlerhaft einfaerben. Stattdessen per-Stream-Flag,
    // damit die Korb-UI "konnte nicht geladen werden" statt "Korb leer" zeigt.
    _orderCartsSubscription =
        _inventory.watchOrderCarts(orgId).listen((items) {
      _orderCarts = items;
      _orderListsLoadFailed = false;
      _safeNotify();
    }, onError: (Object error) {
      AppLogger.warning('orderCarts-Stream fehlgeschlagen', error: error);
      _orderListsLoadFailed = true;
      _safeNotify();
    });

    _weeklyListsSubscription =
        _inventory.watchWeeklyOrderLists(orgId).listen((items) {
      _weeklyLists = items;
      _safeNotify();
    }, onError: (Object error) {
      AppLogger.warning('weeklyOrderLists-Stream fehlgeschlagen', error: error);
      _orderListsLoadFailed = true;
      _safeNotify();
    });

    _fridgeListsSubscription =
        _inventory.watchFridgeRefillLists(orgId).listen((items) {
      _fridgeLists = items;
      _safeNotify();
    }, onError: _setError);
  }

  Future<void> _cancelSubscriptions() async {
    await _suppliersSubscription?.cancel();
    await _productsSubscription?.cancel();
    await _batchesSubscription?.cancel();
    await _ordersSubscription?.cancel();
    await _movementsSubscription?.cancel();
    await _customerOrdersSubscription?.cancel();
    await _orderCartsSubscription?.cancel();
    await _weeklyListsSubscription?.cancel();
    await _fridgeListsSubscription?.cancel();
    _suppliersSubscription = null;
    _productsSubscription = null;
    _batchesSubscription = null;
    _ordersSubscription = null;
    _movementsSubscription = null;
    _customerOrdersSubscription = null;
    _orderCartsSubscription = null;
    _weeklyListsSubscription = null;
    _fridgeListsSubscription = null;
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
    _suppliers = _upsertLocal(
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
    // Growable lassen: _upsertLocal ruft .add() auf derselben Liste — eine
    // fixed-length-Liste liesse das naechste lokale Speichern crashen.
    _suppliers =
        _suppliers.where((supplier) => supplier.id != supplierId).toList();
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
    var prepared = product.copyWith(
      orgId: orgId,
      createdByUid: product.createdByUid ?? _currentUser?.uid,
    );
    // Clobber-Schutz: saveProduct (Manager-Edit/Anlage) darf fridgeStock NIE
    // ändern — allein setFridgeStock (Refill) + POS sind autoritativ. Bestehenden
    // Wert erhalten, neue Artikel starten bei 0. Cloud-seitig zusätzlich im Repo
    // aus dem Merge entfernt (Plan §7).
    prepared = prepared.copyWith(
      fridgeStock: productById(prepared.id)?.fridgeStock ?? 0,
    );
    // H8 (Sicherheits-Audit 2026-07): dasselbe gilt fuer currentStock — der
    // Editor friert den Wert beim Oeffnen ein, waehrend Verkaeufe/Inventuren
    // parallel buchen. Fuer BESTEHENDE Artikel den frischen Stand re-injizieren
    // (lokaler Modus/Spiegel); cloud-seitig entfernt das Repo das Feld beim
    // Update zusaetzlich aus dem Merge. Anfangsbestand neuer Artikel bleibt.
    final storedProduct = productById(prepared.id);
    if (storedProduct != null) {
      prepared = prepared.copyWith(currentStock: storedProduct.currentStock);
    }
    // Harte Barcode-Eindeutigkeit je Laden: ein Barcode darf im selben Laden
    // nur an EINEM Artikel haengen (inkl. deaktivierter — die blockieren sonst
    // die Reaktivierung). Geprueft wird nur bei Neuanlage oder geaendertem
    // Barcode: Altbestands-Duplikate bleiben editierbar (sonst waere z.B. eine
    // Preisaenderung an einem Alt-Duplikat blockiert) und werden stattdessen
    // im Duplikat-Report der Scan-Statistik sichtbar. Schreibweisen-tolerant
    // ueber gtinLookupVariants (UPC-A vs. EAN-13 mit fuehrender Null etc.).
    // Grenze: ein Race zweier Geraete kann die Pruefung umgehen (direkter
    // Firestore-Write per Design; Rules koennen Cross-Doc-Eindeutigkeit nicht
    // erzwingen) — auch das faengt der Report auf.
    final barcode = prepared.barcode?.trim() ?? '';
    if (barcode.isNotEmpty) {
      final stored = productById(prepared.id);
      final barcodeUnchanged =
          stored != null && (stored.barcode?.trim() ?? '') == barcode;
      if (!barcodeUnchanged) {
        final clash = productsByBarcode(
          barcode,
          siteId: prepared.siteId,
          includeInactive: true,
        ).where((other) => other.id != prepared.id).toList();
        if (clash.isNotEmpty) {
          final first = clash.first;
          throw StateError(
            'Barcode bereits vergeben: „${first.name}"'
            '${first.isActive ? '' : ' (deaktiviert)'} traegt den Code '
            '$barcode in diesem Laden. Jeder Barcode darf je Laden nur an '
            'einem Artikel haengen.',
          );
        }
      }
    }
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
    _products = _upsertLocal(
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

  // --- Scan-Telemetrie (Scan-Statistik/Fehleranalyse) ----------------------

  /// Lokale Scan-Telemetrie hart auf die juengsten Eintraege cappen —
  /// SharedPreferences ist kein Ort fuer unbegrenzte Logs.
  static const int _scanEventCap = 500;

  void _appendLocalScanEvent(ScanEvent event) {
    _scanEvents.insert(0, event); // Liste ist "neueste zuerst" sortiert
    if (_scanEvents.length > _scanEventCap) {
      _scanEvents.removeRange(_scanEventCap, _scanEvents.length);
    }
  }

  /// Laedt den lokalen Telemetrie-Spiegel einmalig nach (hybrid-Modus: dort
  /// laeuft kein _loadLocalData) — sonst wuerde der erste Scan der Session den
  /// persistierten Spiegel mit einer 1-Element-Liste ueberschreiben.
  Future<void> _ensureScanEventsLoaded() async {
    if (_scanEventsLoaded) return;
    _scanEventsLoaded = true;
    _scanEvents = await DatabaseService.loadLocalScanEvents(scope: _localScope);
  }

  /// Protokolliert einen Scan-Versuch fuer die Scan-Statistik — best-effort
  /// und fire-and-forget: wirft NIE und blockiert das Scannen nicht (Muster
  /// AuditSink). Kein notifyListeners (keine Live-Anzeige; die Statistik laedt
  /// on demand via [fetchScanEvents]). Bewusst KEIN Audit-Log (Rauschen).
  ///
  /// cloud/hybrid: append-only nach Firestore (`scanEvents`), bei hybrid
  /// zusaetzlich lokal gespiegelt (Offline-Statistik); local: nur gecappte
  /// lokale Liste.
  Future<void> logScanEvent({
    required String code,
    required ScanOutcome outcome,
    String? siteId,
    String? mode,
    String? source,
    int? timeToHitMs,
    String? productId,
    String? platform,
  }) async {
    try {
      final orgId = _orgId;
      if (orgId == null) return;
      // Datenschutz by Design: (a) Codes hart auf 128 Zeichen cappen — lange
      // QR-Inhalte (URLs mit Tokens etc.) gehoeren nicht in ein append-only
      // Log; (b) bewusst KEIN createdByUid — die Statistik wertet Geraete/
      // Quellen aus, keine Personen (keine Leistungskontrolle).
      final trimmedCode =
          code.length > 128 ? '${code.substring(0, 125)}…' : code;
      final event = ScanEvent(
        orgId: orgId,
        siteId: siteId,
        code: trimmedCode,
        outcome: outcome,
        mode: mode,
        source: source,
        timeToHitMs: timeToHitMs,
        productId: productId,
        platform: platform,
        createdAt: DateTime.now(),
      );
      if (_usesFirestore) {
        try {
          await _inventory.addScanEvent(event);
        } catch (error) {
          AppLogger.warning(
            'Scan-Telemetrie: Cloud-Write fehlgeschlagen',
            error: error,
          );
          // Telemetrie ist verzichtbar — im Cloud-only-Modus still verwerfen.
          if (!usesHybridStorage) return;
        }
        if (!usesHybridStorage) return;
      }
      await _ensureScanEventsLoaded();
      _appendLocalScanEvent(event);
      await _persistScanEvents();
    } catch (error) {
      // Telemetrie darf den Scanner unter keinen Umstaenden stoeren.
      AppLogger.warning('Scan-Telemetrie fehlgeschlagen', error: error);
    }
  }

  /// Juengste Scan-Ereignisse fuer die Scan-Statistik (neueste zuerst).
  /// cloud/hybrid: einmaliger Read aus Firestore (Hybrid-Offline-Fallback auf
  /// den lokalen Spiegel); local: aus der gecappten lokalen Liste.
  Future<List<ScanEvent>> fetchScanEvents({int limit = 500}) async {
    final orgId = _orgId;
    if (orgId == null) return const <ScanEvent>[];
    if (_usesFirestore) {
      try {
        return await _inventory.fetchScanEvents(orgId, limit: limit);
      } catch (error) {
        if (!usesHybridStorage) rethrow;
        AppLogger.warning(
          'Scan-Statistik offline – zeige lokalen Spiegel',
          error: error,
        );
      }
    }
    await _ensureScanEventsLoaded();
    return List<ScanEvent>.unmodifiable(_scanEvents.take(limit));
  }

  // --- Preisabgleich Kasse (posReceipts) -----------------------------------

  /// Automatischer Preisabgleich App-VK vs. Kasse: vergleicht die Artikel des
  /// Ladens gegen die juengsten TATSAECHLICH kassierten Stueckpreise aus den
  /// gesyncten Belegen (`posReceipts`, cloud-only — es gibt keinen Kassen-
  /// Endpunkt, der Artikelpreise liest). Wirft im local-Modus einen deutschen
  /// [StateError] (die UI blendet den Einstieg dann gar nicht erst ein).
  Future<List<PriceDeviation>> loadPriceDeviations({
    required String siteId,
    int days = 30,
  }) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    if (!_usesFirestore && !_usesLocalDemoFacts) {
      throw StateError(
        'Der Preisabgleich benoetigt die Cloud-Anbindung (Kassen-Belege).',
      );
    }
    final now = DateTime.now();
    final receipts = await _readPosReceiptsInRange(
      orgId,
      now.subtract(Duration(days: days)),
      now,
      siteId: siteId,
    );
    return computePriceDeviations(
      products: _products,
      receipts: receipts,
      siteId: siteId,
    );
  }

  /// Bestandsbewegungen eines Artikels (neueste zuerst, max. [limit]). In
  /// cloud/hybrid aus der produktgefilterten Query (bedient den vorhandenen
  /// (productId, createdAt)-Composite-Index — deckt anders als [recentMovements]
  /// auch Bewegungen jenseits der letzten 100 org-weiten ab); im local-Modus
  /// bzw. als Hybrid-Offline-Fallback aus dem lokalen Spiegel.
  Future<List<StockMovement>> movementsForProduct(
    String productId, {
    int limit = 50,
  }) async {
    if (_usesFirestore) {
      final orgId = _orgId;
      if (orgId == null) {
        return const <StockMovement>[];
      }
      try {
        return await _inventory
            .watchStockMovements(orgId, productId: productId, limit: limit)
            .first;
      } catch (_) {
        // Hybrid-Offline-Fallback: lokalen Spiegel zeigen (ggf. leer).
      }
    }
    return _movements
        .where((movement) => movement.productId == productId)
        .take(limit)
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
    // Growable lassen: _upsertLocal ruft .add() auf derselben Liste — eine
    // fixed-length-Liste liesse das naechste lokale Speichern crashen.
    _products =
        _products.where((product) => product.id != productId).toList();
    await _persistProducts();
    _safeNotify();
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Produkt',
      entityId: productId,
      summary: summary,
    );
  }

  /// **P1.1 — Sell-Through & Reichweite je Artikel eines Standorts.** Liefert
  /// für jeden Artikel von [siteId] die Verkaufsgeschwindigkeit (Einheiten/Tag)
  /// und Lagerreichweite (Tage) über die letzten [windowDays] Tage.
  ///
  /// Read-only/zustandslos (hält keinen Velocity-State im Provider — die
  /// Auswertungs-UI verwendet das Ergebnis ephemer). Die Bewegungen kommen in
  /// cloud/hybrid aus der nicht-limitierten Range-Query (`getStockMovementsInRange`,
  /// deckt das `limit=100` von `recentMovements` nicht ab), im lokalen Modus aus
  /// dem vollständigen lokalen Cache. Die Berechnung selbst ist die pure Funktion
  /// [computeProductVelocities].
  Future<List<ProductVelocity>> computeSiteVelocities({
    required String siteId,
    int windowDays = SalesVelocity.defaultReliableDays,
    int minReliableDays = SalesVelocity.defaultReliableDays,
    DateTime? asOf,
  }) =>
      _loadVelocities(
        siteId: siteId,
        windowDays: windowDays,
        minReliableDays: minReliableDays,
        asOf: asOf,
      );

  /// Wie [computeSiteVelocities], aber **org-weit über alle Standorte** — Basis
  /// für die standortübergreifende Umlagerung A↔B (P1.2), die denselben Artikel
  /// in beiden Läden vergleicht.
  Future<List<ProductVelocity>> computeOrgVelocities({
    int windowDays = SalesVelocity.defaultReliableDays,
    int minReliableDays = SalesVelocity.defaultReliableDays,
    DateTime? asOf,
  }) =>
      _loadVelocities(
        siteId: null,
        windowDays: windowDays,
        minReliableDays: minReliableDays,
        asOf: asOf,
      );

  /// **P1.2 — Umlagerungsvorschläge A↔B.** Schlägt vor, Ladenhüter eines Ladens
  /// in den anderen umzulagern, wo derselbe Artikel läuft und knapp wird —
  /// freigesetztes totes Kapital = barer Gewinn. Reine, deterministische
  /// Heuristik [suggestCrossSiteTransfers]; der Aufrufer wendet einen Vorschlag
  /// später über [transferStock] (`StockMovementType.transfer`) an. Sinnvolles
  /// Fenster: ≥ 60 Tage (Ladenhüter = 0 Verkauf über lange Zeit).
  Future<List<TransferSuggestion>> suggestStockTransfers({
    int windowDays = 60,
    double destinationMaxCoverageDays = 14,
    double targetCoverageDays = 21,
    int minTransferQuantity = 1,
    DateTime? asOf,
  }) async {
    final velocities = await computeOrgVelocities(
      windowDays: windowDays,
      asOf: asOf,
    );
    return suggestCrossSiteTransfers(
      velocities: velocities,
      products: _products,
      destinationMaxCoverageDays: destinationMaxCoverageDays,
      targetCoverageDays: targetCoverageDays,
      minTransferQuantity: minTransferQuantity,
    );
  }

  /// **P1.3 — Datengetriebene Meldebestand-/Zielbestand-Vorschläge** je Artikel
  /// von [siteId] aus Velocity + Lieferzeit (`Supplier.leadTimeDays`, sonst
  /// [defaultLeadTimeDays]). Liefert nur Vorschläge fürs Artikel-Editor/Bestell-
  /// korb — es wird **nichts** automatisch gespeichert (der Inhaber übernimmt).
  Future<List<ReorderSuggestion>> suggestReorderLevels({
    required String siteId,
    int windowDays = SalesVelocity.defaultReliableDays,
    int safetyDays = 3,
    int coverageDays = 14,
    int defaultLeadTimeDays = 3,
    DateTime? asOf,
  }) async {
    final velocities = await computeSiteVelocities(
      siteId: siteId,
      windowDays: windowDays,
      asOf: asOf,
    );
    final siteProducts = _products
        .where((p) => p.siteId == siteId)
        .toList(growable: false);
    final leadBySupplier = <String, int>{
      for (final s in _suppliers)
        if (s.id != null && s.leadTimeDays != null) s.id!: s.leadTimeDays!,
    };
    return computeReorderSuggestions(
      velocities: velocities,
      products: siteProducts,
      leadTimeDaysBySupplierId: leadBySupplier,
      incomingByProductId: incomingQuantityByProductId(siteId: siteId),
      defaultLeadTimeDays: defaultLeadTimeDays,
      safetyDays: safetyDays,
      coverageDays: coverageDays,
    );
  }

  /// **Kühlschrank-Soll-Vorschlag** je `inFridge`-Artikel von [siteId] aus der
  /// Velocity (Tagesabsatz × [coverageDays] Eindeckung). Reiner Vorschlag fürs
  /// Artikel-Editor (§12.4) — speichert **nichts**. Liefert `productId →
  /// vorgeschlagenes fridgeTargetStock`. Belastbar erst ab ~[windowDays] Daten.
  Future<Map<String, int>> suggestFridgeTargets({
    required String siteId,
    int coverageDays = 2,
    int windowDays = SalesVelocity.defaultReliableDays,
    DateTime? asOf,
  }) async {
    final velocities = await computeSiteVelocities(
      siteId: siteId,
      windowDays: windowDays,
      asOf: asOf,
    );
    final result = <String, int>{};
    for (final v in velocities) {
      final product = productById(v.productId);
      if (product == null || !product.inFridge) continue;
      result[v.productId] =
          suggestFridgeTarget(v.dailyVelocity, coverageDays: coverageDays);
    }
    return result;
  }

  /// Kühlschrank-Soll-Vorschlag für **einen** Artikel (fürs Artikel-Editor,
  /// §12.4) — unabhängig vom `inFridge`-Flag, damit der Vorschlag schon beim
  /// Aktivieren verfügbar ist. `null`, wenn der Artikel keine ID hat oder keine
  /// Verkaufsdaten vorliegen.
  Future<int?> suggestFridgeTargetForProduct(
    Product product, {
    int coverageDays = 2,
    int windowDays = SalesVelocity.defaultReliableDays,
    DateTime? asOf,
  }) async {
    if (product.id == null) return null;
    final velocities = await computeSiteVelocities(
      siteId: product.siteId,
      windowDays: windowDays,
      asOf: asOf,
    );
    for (final v in velocities) {
      if (v.productId == product.id) {
        return suggestFridgeTarget(v.dailyVelocity, coverageDays: coverageDays);
      }
    }
    return null;
  }

  /// **P3.2 — Storno-/Refund-Anomalie je Kassierer** für [siteId] über
  /// [windowDays] Tage (z-Wert der Erstattungsquote ggü. Standort-Schnitt).
  /// **Verdachtshinweis, kein Urteil; Einsatz erfordert Mitbestimmung/DSGVO.**
  /// Cloud-only (`cashierId` aus den Belegen); lokal/ohne Firebase leer.
  Future<CashierAnomalyReport> loadCashierAnomalies({
    required String siteId,
    int windowDays = SalesVelocity.defaultReliableDays,
    int minTransactions = 30,
    double zThreshold = 2.0,
    DateTime? asOf,
  }) async {
    final orgId = _orgId;
    if ((!_usesFirestore && !_usesLocalDemoFacts) || orgId == null) {
      return CashierAnomalyReport(
        stats: const [],
        siteRefundRateMean: 0,
        minTransactions: minTransactions,
        zThreshold: zThreshold,
      );
    }
    final now = asOf ?? DateTime.now();
    final from = now.subtract(Duration(days: windowDays));
    final receipts = await _readPosReceiptsInRange(
      orgId,
      from,
      now,
      siteId: siteId,
    );
    return computeCashierAnomalies(
      receipts: receipts,
      minTransactions: minTransactions,
      zThreshold: zThreshold,
    );
  }

  /// **P2.0 — Tagesabschluss** (Tagesumsatz mit USt-Split) für [siteId] über
  /// [windowDays] Tage. Liest die Kassenbelege (`posReceipts`, cloud-only) und
  /// gruppiert in-memory je Geschäftstag (nutzt den `(siteId,transactionDate)`-
  /// Index, kein eigener businessDay-Index nötig). Lokal leer.
  Future<List<DailyClosing>> loadDailyClosings({
    required String siteId,
    int windowDays = 31,
    DateTime? asOf,
  }) async {
    final orgId = _orgId;
    if ((!_usesFirestore && !_usesLocalDemoFacts) || orgId == null) {
      return const [];
    }
    final now = asOf ?? DateTime.now();
    final from = now.subtract(Duration(days: windowDays));
    final receipts = await _readPosReceiptsInRange(
      orgId,
      from,
      now,
      siteId: siteId,
    );
    return computeDailyClosings(receipts);
  }

  // --- Kassen-Modul: Zählung / Kassenzustand / Abschluss / Bericht ---------
  // Der gesamte Bereich ist wie posReceipts cloud-only (Plan §2): Reads
  // liefern lokal leer, Mutatoren werfen statt lokal fallzubacken (bewusste,
  // dokumentierte Ausnahme vom hybrid-Fallback-Muster).

  static const _kasseLocalError =
      'Die Kasse braucht die Cloud-Anbindung — im lokalen Modus nicht verfügbar.';

  String _dayString(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  bool _isInDemoDayRange(DateTime value, DateTime from, DateTime to) {
    final day = _dayString(value);
    return day.compareTo(_dayString(from)) >= 0 &&
        day.compareTo(_dayString(to)) <= 0;
  }

  Future<List<PosReceipt>> _readPosReceiptsInRange(
    String orgId,
    DateTime from,
    DateTime to, {
    String? siteId,
  }) async {
    if (!_usesLocalDemoFacts) {
      return _inventory.getPosReceiptsInRange(orgId, from, to, siteId: siteId);
    }
    final result =
        _localDemoPosReceipts.where((receipt) {
          if (siteId != null && siteId.isNotEmpty && receipt.siteId != siteId) {
            return false;
          }
          final at = receipt.transactionDate;
          return at != null && _isInDemoDayRange(at, from, to);
        }).toList();
    result.sort((a, b) {
      final left = a.transactionDate ?? DateTime(1970);
      final right = b.transactionDate ?? DateTime(1970);
      return right.compareTo(left);
    });
    return result;
  }

  Future<List<PosDailyStat>> _readPosDailyStatsInRange(
    String orgId,
    String fromDay,
    String toDay, {
    String? siteId,
  }) async {
    if (!_usesLocalDemoFacts) {
      return _inventory.getPosDailyStatsInRange(
        orgId,
        fromDay,
        toDay,
        siteId: siteId,
      );
    }
    final result =
        _localDemoPosDailyStats.where((stat) {
          return (siteId == null || siteId.isEmpty || stat.siteId == siteId) &&
              stat.businessDay.compareTo(fromDay) >= 0 &&
              stat.businessDay.compareTo(toDay) <= 0;
        }).toList();
    result.sort((a, b) => b.businessDay.compareTo(a.businessDay));
    return result;
  }

  Future<List<CashCount>> _readCashCountsInRange(
    String orgId,
    DateTime from,
    DateTime to, {
    String? siteId,
  }) async {
    if (!_usesLocalDemoFacts) {
      return _inventory.getCashCountsInRange(orgId, from, to, siteId: siteId);
    }
    final result =
        _localDemoCashCounts.where((count) {
          return (siteId == null || siteId.isEmpty || count.siteId == siteId) &&
              _isInDemoDayRange(count.countedAt, from, to);
        }).toList();
    result.sort((a, b) => b.countedAt.compareTo(a.countedAt));
    return result;
  }

  Future<List<CashClosing>> _readCashClosingsInRange(
    String orgId,
    String fromDay,
    String toDay, {
    String? siteId,
  }) async {
    if (!_usesLocalDemoFacts) {
      return _inventory.getCashClosingsInRange(
        orgId,
        fromDay,
        toDay,
        siteId: siteId,
      );
    }
    final result =
        _localDemoCashClosings.where((closing) {
          return (siteId == null ||
                  siteId.isEmpty ||
                  closing.siteId == siteId) &&
              closing.businessDay.compareTo(fromDay) >= 0 &&
              closing.businessDay.compareTo(toDay) <= 0;
        }).toList();
    result.sort((a, b) => b.businessDay.compareTo(a.businessDay));
    return result;
  }

  String _euro(int cents) {
    final sign = cents < 0 ? '-' : '';
    final abs = cents.abs();
    return '$sign${abs ~/ 100},${(abs % 100).toString().padLeft(2, '0')} €';
  }

  /// Zählprotokolle des Standorts im Fenster, jüngste zuerst (lokal leer).
  Future<List<CashCount>> loadCashCounts({
    required String siteId,
    int windowDays = 62,
    DateTime? asOf,
  }) async {
    final orgId = _orgId;
    if ((!_usesFirestore && !_usesLocalDemoFacts) || orgId == null) {
      return const [];
    }
    final now = asOf ?? DateTime.now();
    final from = now.subtract(Duration(days: windowDays));
    return _readCashCountsInRange(orgId, from, now, siteId: siteId);
  }

  /// **§4.2 — rechnerischer Kassenzustand** (Soll-Bargeld ab letzter Zählung).
  /// Bewusst gefenstert (kein „ab Datenbeginn", Plan §4.2): liegt im Fenster
  /// keine Zählung, ist das Ergebnis unverankert und die UI fordert zum
  /// Zählen auf. Lokal: leerer, unverankerter Zustand.
  Future<CashState> loadCashState({
    required String siteId,
    int windowDays = 62,
    DateTime? asOf,
    String? businessDay,
  }) async {
    final orgId = _orgId;
    if ((!_usesFirestore && !_usesLocalDemoFacts) || orgId == null) {
      return const CashState(
        sollCents: null,
        verankert: false,
        letzteZaehlung: null,
        tagesBareinnahmenCents: 0,
        tagesCashBewegungCents: 0,
      );
    }
    final now = asOf ?? DateTime.now();
    final from = now.subtract(Duration(days: windowDays));
    final receipts = await _readPosReceiptsInRange(
      orgId,
      from,
      now,
      siteId: siteId,
    );
    final counts = await _readCashCountsInRange(
      orgId,
      from,
      now,
      siteId: siteId,
    );
    return computeCashState(
      receipts: receipts,
      counts: counts,
      siteId: siteId,
      businessDay: businessDay,
    );
  }

  /// Erfasst eine Kassenzählung (E2: offen für ALLE aktiven Nutzer, kein
  /// `canManageInventory`-Gate — blind zählende Clients lassen
  /// `expectedCents`/`differenceCents` null, die Rules erzwingen das).
  /// **Cloud-only Mutator**: im lokalen Modus deutscher [StateError] statt
  /// hybrid-Fallback (Plan §6).
  Future<void> saveCashCount(CashCount count) async {
    final orgId = _orgId;
    if ((!_usesFirestore && !_usesLocalDemoFacts) || orgId == null) {
      throw StateError(_kasseLocalError);
    }
    final actorUid =
        count.createdByUid.isEmpty ? _currentUser?.uid : count.createdByUid;
    var prepared = count.copyWith(
      orgId: orgId,
      createdByUid: actorUid,
      // App-Pfad: die zählende Person IST der angemeldete Nutzer (ZV-4.1).
      // Kiosk-Zählungen laufen nicht hierüber, sondern über die Callable, die
      // countedByUserId server-seitig aus der Session setzt.
      countedByUserId: count.countedByUserId ?? actorUid,
    );
    if (_usesLocalDemoFacts) {
      final now = DateTime.now();
      prepared = prepared.copyWith(
        id: prepared.id ?? 'demo-cash-count-$orgId-session-${_localSeq++}',
        createdAt: prepared.createdAt ?? now,
      );
      _localDemoCashCounts = [prepared, ..._localDemoCashCounts];
      _safeNotify();
    } else {
    await _inventory.addCashCount(prepared);
    }
    _audit?.call(
      action: AuditAction.created,
      entityType: 'Kassenzählung',
      entityId: prepared.siteId,
      summary:
          'Kassenzählung ${prepared.siteId} ${prepared.businessDay} '
          'erfasst (${_euro(prepared.countedCents)}'
          '${prepared.countedByLabel == null ? '' : ', ${prepared.countedByLabel}'})',
    );
  }

  /// Festgeschriebene Kassenabschlüsse im Fenster, jüngste zuerst (lokal leer).
  /// [siteId] `null` = org-weit (alle Filialen) — u. a. für die Fremdgeld-
  /// Auswertung im Kassenbericht ohne Filialfilter.
  Future<List<CashClosing>> loadCashClosings({
    String? siteId,
    int windowDays = 62,
    DateTime? asOf,
  }) async {
    final orgId = _orgId;
    if ((!_usesFirestore && !_usesLocalDemoFacts) || orgId == null) {
      return const [];
    }
    final now = asOf ?? DateTime.now();
    final from = now.subtract(Duration(days: windowDays));
    return _readCashClosingsInRange(
      orgId,
      _dayString(from),
      _dayString(now),
      siteId: siteId,
    );
  }

  /// **§3.2 — Tag festschreiben** (create-only; „bereits abgeschlossen" wirft
  /// einen deutschen [StateError] aus dem Repository). Admin-Gate liegt in der
  /// UI + den Rules. Cloud-only Mutator wie [saveCashCount].
  Future<void> closeBusinessDay(CashClosing closing) async {
    final orgId = _orgId;
    if ((!_usesFirestore && !_usesLocalDemoFacts) || orgId == null) {
      throw StateError(_kasseLocalError);
    }
    var prepared = closing.copyWith(
      orgId: orgId,
      closedByUid:
          closing.closedByUid.isEmpty ? _currentUser?.uid : closing.closedByUid,
    );
    if (_usesLocalDemoFacts) {
      final duplicate = _localDemoCashClosings.any(
        (item) =>
            item.siteId == prepared.siteId &&
            item.businessDay == prepared.businessDay,
      );
      if (duplicate) {
        throw StateError('Dieser Tag ist bereits abgeschlossen.');
      }
      prepared = prepared.copyWith(
        id:
            prepared.id ??
            'demo-cash-closing-$orgId-session-'
                '${CashClosing.docId(prepared.businessDay, prepared.siteId)}',
        closedAt: prepared.closedAt ?? DateTime.now(),
      );
      _localDemoCashClosings = [prepared, ..._localDemoCashClosings];
      _safeNotify();
    } else {
    await _inventory.createCashClosing(prepared);
    }
    final diff = prepared.cashDifferenceCents;
    _audit?.call(
      action: AuditAction.created,
      entityType: 'Kassenabschluss',
      entityId: CashClosing.docId(prepared.businessDay, prepared.siteId),
      summary:
          'Kassenabschluss ${prepared.siteId} ${prepared.businessDay} '
          'festgeschrieben '
          '(${diff == null ? 'ohne Zählung' : 'Differenz ${_euro(diff)}'})',
    );
  }

  /// Markiert einen festgeschriebenen Abschluss als ins Finanzjournal gebucht
  /// (nach erfolgreichem `FinanceProvider.postDailyClosing`) — die einzige
  /// erlaubte Mutation (`bookedToFinance false→true`, §3.2).
  Future<void> markClosingBooked({required String closingId}) async {
    final orgId = _orgId;
    if ((!_usesFirestore && !_usesLocalDemoFacts) || orgId == null) {
      throw StateError(_kasseLocalError);
    }
    if (_usesLocalDemoFacts) {
      final index = _localDemoCashClosings.indexWhere(
        (item) =>
            item.id == closingId ||
            CashClosing.docId(item.businessDay, item.siteId) == closingId,
      );
      if (index < 0) {
        throw StateError('Kassenabschluss wurde nicht gefunden.');
      }
      final next = [..._localDemoCashClosings];
      next[index] = next[index].copyWith(bookedToFinance: true);
      _localDemoCashClosings = next;
      _safeNotify();
    } else {
      await _inventory.markCashClosingBooked(
        orgId: orgId,
        closingId: closingId,
      );
    }
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Kassenabschluss',
      entityId: closingId,
      summary: 'Kassenabschluss $closingId ins Finanzjournal gebucht',
    );
  }

  /// **§4.1 — Kassenbericht.** Bevorzugt die serverseitigen Tagesaggregate
  /// (`posDailyStats`, M5) — damit sind Monats-/Jahres-Langzeit voll verfügbar.
  /// **Fallback** (bis der Server-Sync deployt ist / noch keine Stats
  /// geschrieben hat): clientseitige Aggregation aus einem Belege-Fenster von
  /// max. 92 Tagen — dann ist nur die Wochen-Sicht voll, ältere Buckets bleiben
  /// „keine Daten". [purchasePricesIncludeVat] = Org-Schalter §3.4 (E1).
  Future<List<KassenPeriode>> loadKassenbericht({
    required ReportGranularity granularity,
    required bool purchasePricesIncludeVat,
    String? siteId,
    int? bucketCount,
    DateTime? asOf,
    int windowDays = 92,
  }) async {
    final orgId = _orgId;
    if ((!_usesFirestore && !_usesLocalDemoFacts) || orgId == null) {
      return const [];
    }
    final now = asOf ?? DateTime.now();

    // (1) Server-Aggregate über einen großzügigen Zeitraum laden — weit genug
    // zurück, um auch das Vorjahr des ältesten Buckets abzudecken (Δ Vorjahr).
    final statsFrom = now.subtract(
      Duration(
        days: switch (granularity) {
      ReportGranularity.week => 500,
      ReportGranularity.month => 800,
      ReportGranularity.year => 1600,
        },
      ),
    );
    final serverStats = await _readPosDailyStatsInRange(
      orgId,
      _dayString(statsFrom),
      _dayString(now),
      siteId: siteId,
    );
    if (serverStats.isNotEmpty) {
      return computeKassenbericht(
        stats: serverStats,
        orders: _orders,
        granularity: granularity,
        now: now,
        bucketCount: bucketCount,
        siteId: siteId,
        coverageFrom: statsFrom,
        purchasePricesIncludeVat: purchasePricesIncludeVat,
      );
    }

    // (2) Fallback: Belege-Fenster ≤ 92 Tage clientseitig aggregieren.
    final cappedWindow = windowDays > 92 ? 92 : windowDays;
    final from = now.subtract(Duration(days: cappedWindow));
    final receipts = await _readPosReceiptsInRange(
      orgId,
      from,
      now,
      siteId: siteId,
    );
    final stats = dailyStatsFromReceipts(
      receipts,
      _products,
      purchasePricesIncludeVat: purchasePricesIncludeVat,
    );
    return computeKassenbericht(
      stats: stats,
      orders: _orders,
      granularity: granularity,
      now: now,
      bucketCount: bucketCount,
      siteId: siteId,
      // Fensterbeginn durchreichen: Vergleichsperioden, die vor dem geladenen
      // Fenster beginnen, bekommen null-Δ statt Randstummel-Vergleiche.
      coverageFrom: from,
      purchasePricesIncludeVat: purchasePricesIncludeVat,
    );
  }

  /// **P4.2 — Warenkorb-/Cross-Sell-Analyse** für [siteId] über [windowDays]
  /// Tage: welche Artikel häufig zusammen über denselben Beleg gehen. Liest die
  /// Kassenbelege (`posReceipts`, cloud-only); lokal leer.
  Future<BasketAnalysis> loadBasketAnalysis({
    required String siteId,
    int windowDays = SalesVelocity.defaultReliableDays,
    int minTogether = 2,
    int topN = 25,
    DateTime? asOf,
  }) async {
    final orgId = _orgId;
    if ((!_usesFirestore && !_usesLocalDemoFacts) || orgId == null) {
      return const BasketAnalysis(pairs: [], receiptsConsidered: 0);
    }
    final now = asOf ?? DateTime.now();
    final from = now.subtract(Duration(days: windowDays));
    final receipts = await _readPosReceiptsInRange(
      orgId,
      from,
      now,
      siteId: siteId,
    );
    return computeBasketAnalysis(
      receipts: receipts,
      minTogether: minTogether,
      topN: topN,
    );
  }

  /// **P2.1 — Sortimentsanalyse (Rohertrag & ABC nach Deckungsbeitrag)** für
  /// [siteId] über [windowDays] Tage. Liest die Kassenbelege (`posReceipts`,
  /// cloud-only) und verrechnet sie mit den aktuellen EK-Preisen. Im lokalen
  /// Modus leer (ohne Firebase keine Kassenfakten). Zustandslos.
  Future<AssortmentAnalysis> loadAssortmentAnalysis({
    required String siteId,
    int windowDays = SalesVelocity.defaultReliableDays,
    DateTime? asOf,
    bool purchasePricesIncludeVat = false,
  }) async {
    final orgId = _orgId;
    if ((!_usesFirestore && !_usesLocalDemoFacts) || orgId == null) {
      return const AssortmentAnalysis(
        items: [],
        totalRevenueCents: 0,
        totalContributionCents: 0,
        contributionByCategory: {},
        unvaluatedCount: 0,
      );
    }
    final now = asOf ?? DateTime.now();
    final from = now.subtract(Duration(days: windowDays));
    final receipts = await _readPosReceiptsInRange(
      orgId,
      from,
      now,
      siteId: siteId,
    );
    final siteProducts = _products
        .where((p) => p.siteId == siteId)
        .toList(growable: false);
    return computeAssortmentAnalysis(
      receipts: receipts,
      products: siteProducts,
      purchasePricesIncludeVat: purchasePricesIncludeVat,
    );
  }

  /// **P4.1 — Listungslücken** für [siteId]: Artikel, die in einem ANDEREN Laden
  /// laufen, von [siteId] aber nicht geführt werden (Listungschance). Org-weite
  /// Velocity + alle Artikel; cloud/hybrid/lokal über `computeOrgVelocities`.
  Future<List<ListingGap>> loadListingGaps({
    required String siteId,
    int windowDays = SalesVelocity.defaultReliableDays,
    int minSoldUnits = 1,
    DateTime? asOf,
  }) async {
    final velocities = await computeOrgVelocities(
      windowDays: windowDays,
      asOf: asOf,
    );
    return findListingGaps(
      velocities: velocities,
      products: _products,
      siteIds: [siteId],
      minSoldUnits: minSoldUnits,
    );
  }

  /// **P4.3 — Wochentag-/Saison-Nachfragefaktoren** für [siteId] aus der eigenen
  /// Beleg-Historie (Wochentag → Faktor relativ zum Durchschnittstag). Reines
  /// Feintuning für Bestell-/Besetzungs-Vorschläge; der Wetter-Faktor kommt
  /// separat (`weatherDemandFactor`, graceful = 1.0 ohne Daten). Cloud-only.
  Future<Map<int, double>> loadWeekdayDemandFactors({
    required String siteId,
    int windowDays = 56,
    DateTime? asOf,
  }) async {
    final orgId = _orgId;
    if ((!_usesFirestore && !_usesLocalDemoFacts) || orgId == null) {
      return const {};
    }
    final now = asOf ?? DateTime.now();
    final from = now.subtract(Duration(days: windowDays));
    final receipts = await _readPosReceiptsInRange(
      orgId,
      from,
      now,
      siteId: siteId,
    );
    return computeWeekdayDemandFactors(receipts);
  }

  /// **P3.1 — Umsatzbasiertes Besetzungs-Profil** für [siteId] über [windowDays]
  /// Tage: anonymes Beleg-pro-Stunde-Profil (Wochentag×Stunde) als Grundlage für
  /// `StaffingDemand.requiredCount`-Vorschläge. Liest die Kassenbelege
  /// (`posReceipts`, cloud-only); lokal leer.
  Future<StaffingProfile> loadStaffingProfile({
    required String siteId,
    int windowDays = 28,
    int receiptsPerStaffPerHour = 30,
    DateTime? asOf,
  }) async {
    final orgId = _orgId;
    if ((!_usesFirestore && !_usesLocalDemoFacts) || orgId == null) {
      return StaffingProfile(
        siteId: siteId,
        cells: const [],
        receiptsPerStaffPerHour: receiptsPerStaffPerHour,
      );
    }
    final now = asOf ?? DateTime.now();
    final from = now.subtract(Duration(days: windowDays));
    final receipts = await _readPosReceiptsInRange(
      orgId,
      from,
      now,
      siteId: siteId,
    );
    return computeStaffingProfile(
      siteId: siteId,
      receipts: receipts,
      receiptsPerStaffPerHour: receiptsPerStaffPerHour,
    );
  }

  /// **P2.3 — Tages-Gesundheits-Check / Multi-Store-Benchmark.** Vergleicht die
  /// Beleg-Anzahl von [evaluatedDay] (Default: heute) je Laden mit dem
  /// Wochentag-Schnitt der letzten [windowDays] Tage. Liest org-weit die
  /// Kassenbelege (`posReceipts`, cloud-only); lokal leer.
  Future<StoreBenchmark> loadStoreBenchmark({
    String? evaluatedDay,
    int windowDays = SalesVelocity.defaultReliableDays,
    DateTime? asOf,
  }) async {
    final now = asOf ?? DateTime.now();
    final day =
        evaluatedDay ??
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}';
    final orgId = _orgId;
    if ((!_usesFirestore && !_usesLocalDemoFacts) || orgId == null) {
      return StoreBenchmark(evaluatedDay: day, perSite: const []);
    }
    final from = now.subtract(Duration(days: windowDays));
    final receipts = await _readPosReceiptsInRange(
      orgId,
      from,
      now,
      siteId: null,
    );
    return computeStoreBenchmark(receipts: receipts, evaluatedDay: day);
  }

  /// **P2.2 — Schwund-/Inventurdifferenz-Report** für [siteId] über [windowDays]
  /// Tage. Bewertet Inventur-/Korrektur-Bewegungen mit dem EK. Zustandslos; nur
  /// Artikel-/Warengruppenebene (nie je Mitarbeiter).
  Future<ShrinkageReport> loadShrinkageReport({
    required String siteId,
    int windowDays = 30,
    DateTime? asOf,
  }) async {
    final now = asOf ?? DateTime.now();
    final from = now.subtract(Duration(days: windowDays));
    final movements = await _fetchMovementsInRange(siteId, from, now);
    final siteProducts =
        _products.where((p) => p.siteId == siteId).toList(growable: false);
    return computeShrinkageReport(
      movements: movements,
      products: siteProducts,
    );
  }

  /// Bestandsbewegungen im Zeitraum: cloud/hybrid via nicht-limitierter
  /// Range-Query, lokal aus dem vollständigen Cache. [siteId] `null` = org-weit.
  Future<List<StockMovement>> _fetchMovementsInRange(
    String? siteId,
    DateTime from,
    DateTime to,
  ) async {
    final orgId = _orgId;
    if (_usesFirestore && orgId != null) {
      return _inventory.getStockMovementsInRange(orgId, from, to, siteId: siteId);
    }
    return _movements
        .where((m) =>
            (siteId == null || m.siteId == siteId) &&
            m.createdAt != null &&
            !m.createdAt!.isBefore(from) &&
            !m.createdAt!.isAfter(to))
        .toList(growable: false);
  }

  Future<List<ProductVelocity>> _loadVelocities({
    required String? siteId,
    required int windowDays,
    required int minReliableDays,
    required DateTime? asOf,
  }) async {
    final now = asOf ?? DateTime.now();
    final from = now.subtract(Duration(days: windowDays));
    var movements = await _fetchMovementsInRange(siteId, from, now);
    if (_usesLocalDemoFacts) {
      final receipts = await _readPosReceiptsInRange(
        _orgId!,
        from,
        now,
        siteId: siteId,
      );
      movements = [
        ...movements,
        ..._demoReceiptIssueMovements(
          receipts: receipts,
          existingMovements: movements,
          asOf: now,
        ),
      ];
    }

    final products =
        siteId == null
        ? _products
            : _products
                .where((p) => p.siteId == siteId)
                .toList(growable: false);
    return computeProductVelocities(
      products: products,
      movements: movements,
      windowStart: from,
      asOf: now,
      minReliableDays: minReliableDays,
    );
  }

  /// Der echte Sync materialisiert Verkaufszeilen als `issue`-Bewegungen. In
  /// der lokalen Demo gibt es keinen Sync-Prozess; dieser Adapter bildet daher
  /// dieselben Signale ephemer aus den Belegen. Bereits als OktoPOS-Bewegung
  /// vorhandene (Beleg, Artikel)-Paare werden nicht doppelt gezaehlt.
  List<StockMovement> _demoReceiptIssueMovements({
    required List<PosReceipt> receipts,
    required List<StockMovement> existingMovements,
    required DateTime asOf,
  }) {
    final represented = <String>{
      for (final movement in existingMovements)
        if (movement.isFromPos &&
            movement.externalRef != null &&
            movement.externalRef!.isNotEmpty)
          '${movement.externalRef}|${movement.productId}',
    };
    final productNames = <String, String>{
      for (final product in _products)
        if (product.id != null) product.id!: product.name,
    };
    final result = <StockMovement>[];
    for (final receipt in receipts) {
      if (!receipt.isRevenue || receipt.training) continue;
      if ((receipt.type ?? '').toLowerCase() != 'sales') continue;
      final quantityByProduct = <String, int>{};
      for (final line in receipt.lines) {
        final productId = line.productId;
        if (productId == null || productId.isEmpty || line.quantity <= 0) {
          continue;
        }
        quantityByProduct[productId] =
            (quantityByProduct[productId] ?? 0) + line.quantity;
      }
      for (final entry in quantityByProduct.entries) {
        final pair = '${receipt.referenceNumber}|${entry.key}';
        if (represented.contains(pair)) continue;
        var createdAt = receipt.transactionDate ?? asOf;
        // Demo-Fakten eines Kalendertags sollen auch vor ihrer Beispiel-Uhrzeit
        // sichtbar sein; die Pure-Funktion verwirft sonst ein Future-Signal.
        if (createdAt.isAfter(asOf)) createdAt = asOf;
        result.add(
          StockMovement(
            id:
                'demo-derived-velocity-${receipt.id ?? receipt.referenceNumber}'
                '-${entry.key}',
            orgId: receipt.orgId,
            siteId: receipt.siteId,
            productId: entry.key,
            productName: productNames[entry.key],
            type: StockMovementType.issue,
            quantityDelta: -entry.value,
            reason: 'Verkauf ueber Demo-Kassenbeleg',
            source: 'oktopos',
            externalRef: receipt.referenceNumber,
            createdAt: createdAt,
          ),
        );
      }
    }
    return result;
  }

  /// Stösst den OktoPOS-Kassenabgleich für [siteId] an: die Cloud Function zieht
  /// die Verkaufsbuchungen der Kasse und schreibt die Bestandsabgänge
  /// serverseitig (Admin SDK). Der API-Key bleibt serverseitig — der Client löst
  /// nur aus. Nur in cloud/hybrid verfügbar (Firebase nötig); im lokalen
  /// Demo-Modus nicht. Bestand/Bewegungen aktualisieren sich anschließend über
  /// die laufenden Firestore-Streams. Gibt die Ergebnis-Zusammenfassung zurück.
  Future<Map<String, dynamic>> triggerOktoposSync({
    required String siteId,
    String? from,
    String? until,
    bool dryRun = false,
  }) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    if (!_usesFirestore) {
      throw StateError(
        'Der Kassenabgleich ist nur mit Firebase-Anbindung verfügbar '
        '(nicht im lokalen Demo-Modus).',
      );
    }
    final result = await _firestoreService.syncOktoposTransactions(
      orgId: orgId,
      siteId: siteId,
      from: from,
      until: until,
      dryRun: dryRun,
    );
    if (!dryRun) {
      final applied = (result['appliedMovements'] as num?)?.toInt() ?? 0;
      final reversed = (result['reversedMovements'] as num?)?.toInt() ?? 0;
      final unmatched = (result['unmatchedLineItems'] as num?)?.toInt() ?? 0;
      final siteName = _siteNameFor(siteId) ?? siteId;
      _audit?.call(
        action: AuditAction.updated,
        entityType: 'Kassenabgleich',
        entityId: siteId,
        summary: 'OktoPOS-Abgleich $siteName: $applied Verkäufe, '
            '$reversed Erstattungen übernommen'
            '${unmatched > 0 ? ', $unmatched Positionen ohne Artikel' : ''}.',
      );
    }
    return result;
  }

  /// Lädt das OktoPOS-Sync-Config-Doc (Admin-Einstellungen + Cursor) für die
  /// Einstellungs-UI. Nur in cloud/hybrid; `null`, wenn nicht eingerichtet oder
  /// ohne Firebase-Anbindung.
  Future<Map<String, dynamic>?> loadOktoposConfig() async {
    final orgId = _orgId;
    if (orgId == null || !_usesFirestore) {
      return null;
    }
    return _firestoreService.fetchOktoposConfig(orgId);
  }

  /// Speichert die OktoPOS-Admin-Einstellungen (baseUrl / Auto-Abgleich /
  /// cashRegisterId je Standort) merge-sicher. Der API-Key bleibt serverseitig
  /// und wird hier nie berührt.
  Future<void> saveOktoposConfig({
    required String baseUrl,
    required bool enabled,
    required int defaultSize,
    required Map<String, int?> cashRegisterBySiteId,
    String? distributionChannel,
    String? defaultUnitToken,
    int? defaultTaxRate,
    bool? cashierCanChangePrice,
    String? customerGroupName,
  }) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    if (!_usesFirestore) {
      throw StateError(
        'OktoPOS-Einstellungen sind nur mit Firebase-Anbindung verfügbar.',
      );
    }
    await _firestoreService.saveOktoposConfig(
      orgId: orgId,
      baseUrl: baseUrl,
      enabled: enabled,
      defaultSize: defaultSize,
      cashRegisterBySiteId: cashRegisterBySiteId,
      distributionChannel: distributionChannel,
      defaultUnitToken: defaultUnitToken,
      defaultTaxRate: defaultTaxRate,
      cashierCanChangePrice: cashierCanChangePrice,
      customerGroupName: customerGroupName,
    );
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Kassen-Einstellungen',
      entityId: 'oktopos',
      summary: 'OktoPOS-Einstellungen gespeichert'
          '${enabled ? ' (Auto-Abgleich an)' : ''}.',
    );
  }

  /// Schreibt Artikel/Preise eines Standorts in die OktoPOS-Kasse (M5). Ohne
  /// [productIds] werden alle aktiven Artikel des Standorts gesendet. Nur in
  /// cloud/hybrid; der API-Key bleibt serverseitig. Gibt die Zusammenfassung
  /// (created/updated/failed/skipped) zurück.
  Future<Map<String, dynamic>> pushOktoposArticles({
    required String siteId,
    List<String>? productIds,
    bool dryRun = false,
  }) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    if (!_usesFirestore) {
      throw StateError(
        'Der Artikel-Versand an die Kasse ist nur mit Firebase-Anbindung '
        'verfügbar (nicht im lokalen Demo-Modus).',
      );
    }
    final result = await _firestoreService.pushOktoposArticles(
      orgId: orgId,
      siteId: siteId,
      productIds: productIds,
      dryRun: dryRun,
    );
    if (!dryRun) {
      final created = (result['created'] as num?)?.toInt() ?? 0;
      final updated = (result['updated'] as num?)?.toInt() ?? 0;
      final failed = (result['failed'] as num?)?.toInt() ?? 0;
      final siteName = _siteNameFor(siteId) ?? siteId;
      _audit?.call(
        action: AuditAction.updated,
        entityType: 'Kassen-Artikel',
        entityId: siteId,
        summary: 'OktoPOS-Artikelversand $siteName: $created neu, '
            '$updated aktualisiert'
            '${failed > 0 ? ', $failed fehlgeschlagen' : ''}.',
      );
    }
    return result;
  }

  /// Schreibt Kunden-Kontakte (Typ Kunde) in die OktoPOS-Kasse (M6a). Ohne
  /// [contactIds] alle aktiven Kunden-Kontakte der Org. Vorhandene Kunden
  /// werden serverseitig übersprungen (CustomerApi hat kein Update). Gibt die
  /// Zusammenfassung (created/skipped/failed) zurück.
  Future<Map<String, dynamic>> pushOktoposCustomers({
    required String siteId,
    List<String>? contactIds,
    bool dryRun = false,
  }) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    if (!_usesFirestore) {
      throw StateError(
        'Der Kunden-Versand an die Kasse ist nur mit Firebase-Anbindung '
        'verfügbar (nicht im lokalen Demo-Modus).',
      );
    }
    final result = await _firestoreService.pushOktoposCustomers(
      orgId: orgId,
      siteId: siteId,
      contactIds: contactIds,
      dryRun: dryRun,
    );
    if (!dryRun) {
      final created = (result['created'] as num?)?.toInt() ?? 0;
      final skipped = (result['skipped'] as num?)?.toInt() ?? 0;
      final failed = (result['failed'] as num?)?.toInt() ?? 0;
      _audit?.call(
        action: AuditAction.updated,
        entityType: 'Kassen-Kunden',
        entityId: siteId,
        summary: 'OktoPOS-Kundenversand: $created neu, $skipped vorhanden'
            '${failed > 0 ? ', $failed fehlgeschlagen' : ''}.',
      );
    }
    return result;
  }

  /// Holt die Referenz-Tokens (Einheiten + Vertriebskanäle) aus der Kasse für
  /// die Einstellungs-UI. Nur in cloud/hybrid; `null` ohne Firebase.
  Future<Map<String, dynamic>?> loadOktoposLookups({
    required String siteId,
  }) async {
    final orgId = _orgId;
    if (orgId == null || !_usesFirestore) {
      return null;
    }
    return _firestoreService.getOktoposLookups(orgId: orgId, siteId: siteId);
  }

  /// Lesbarer Standortname (aus den gestreamten Artikeln abgeleitet), für
  /// Audit-/UI-Texte. `null`, wenn kein Artikel des Standorts einen Namen trägt.
  String? _siteNameFor(String siteId) {
    for (final product in _products) {
      final name = product.siteName;
      if (product.siteId == siteId && name != null && name.isNotEmpty) {
        return name;
      }
    }
    return null;
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
  // --- MHD-/Ablauf-Chargen (Mutatoren) ------------------------------------

  /// Legt eine Warencharge mit MHD an oder aktualisiert sie (drei Speichermodi).
  Future<void> saveBatch(ProductBatch batch) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    final prepared = batch.copyWith(
      orgId: orgId,
      createdByUid: batch.createdByUid ?? _currentUser?.uid,
    );
    final isNew = prepared.id == null || prepared.id!.isEmpty;
    final name = prepared.productName ?? 'Artikel';
    final summary = 'Charge „$name" ${isNew ? 'angelegt' : 'aktualisiert'} '
        '(MHD ${_formatDay(prepared.expiryDate)})';
    if (_usesFirestore &&
        await _tryFirestore(
          'saveBatch',
          () => _inventory.saveProductBatch(prepared),
        )) {
      _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Charge',
        entityId: prepared.id,
        summary: summary,
      );
      return;
    }
    final stored = prepared.id == null
        ? prepared.copyWith(id: _nextLocalId('batch'))
        : prepared;
    _batches = _upsertLocal(_batches, stored, (item) => item.id);
    _batches.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    await _persistBatches();
    _safeNotify();
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Charge',
      entityId: stored.id,
      summary: summary,
    );
  }

  /// Markiert eine Charge als abverkauft/entsorgt (verschwindet aus der Warnung,
  /// bleibt zur Historie erhalten). Setzt Bearbeiter + Zeitstempel.
  Future<void> resolveBatch(
    String batchId, {
    required BatchStatus status,
  }) async {
    final orgId = _orgId;
    if (orgId == null) return;
    final existing = _batchById(batchId);
    if (existing == null) return;
    final resolved = existing.copyWith(
      status: status,
      resolvedByUid: _currentUser?.uid,
      resolvedAt: DateTime.now(),
    );
    final name = existing.productName ?? 'Artikel';
    final verb = status == BatchStatus.discarded
        ? 'entsorgt'
        : status == BatchStatus.soldOut
            ? 'abverkauft'
            : 'wieder aktiv gesetzt';
    final summary = 'Charge „$name" $verb';
    if (_usesFirestore &&
        await _tryFirestore(
          'resolveBatch',
          () => _inventory.saveProductBatch(resolved),
        )) {
      _audit?.call(
        action: AuditAction.updated,
        entityType: 'Charge',
        entityId: batchId,
        summary: summary,
      );
      return;
    }
    _batches = _upsertLocal(_batches, resolved, (item) => item.id);
    await _persistBatches();
    _safeNotify();
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Charge',
      entityId: batchId,
      summary: summary,
    );
  }

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
  ///
  /// H9 (Sicherheits-Audit 2026-07): Das Delta wird NIE aus dem uebergebenen
  /// (potenziell veralteten) UI-Objekt berechnet. Cloud-Pfad: absolut setzende
  /// Transaktion ([InventoryRepository.setProductStock], Delta aus dem frischen
  /// Serverstand). Lokal/Hybrid-Fallback: Delta gegen den frischen
  /// In-Memory-Stand.
  Future<void> recordStocktake({
    required Product product,
    required int countedStock,
  }) async {
    final orgId = _orgId;
    final productId = product.id;
    if (orgId == null || productId == null) {
      return;
    }
    final productName = productById(productId)?.name ?? product.name;
    final summary =
        'Inventur „$productName": Bestand auf $countedStock gesetzt';
    final mutationId = _uuid.v4();
    if (_usesFirestore &&
        await _tryFirestore(
          'recordStocktake',
          () => _inventory.setProductStock(
            orgId: orgId,
            productId: productId,
            newStock: countedStock,
            reason: 'Inventur',
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
    final fresh = productById(productId) ?? product;
    final delta = countedStock - fresh.currentStock;
    if (delta == 0) {
      return;
    }
    _applyLocalStockChange(
      productId: productId,
      delta: delta,
      type: StockMovementType.stocktake,
      reason: 'Inventur',
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

  /// **Kühlschrank nachfüllen** (§12.5/§12.6). Setzt den Kühlschrank-Ist von
  /// [product] — ohne [quantity] auf das Soll `fridgeTargetStock`, mit [quantity]
  /// additiv (auf >= 0 geklemmt) — und protokolliert eine `fridgeRefill`-Bewegung.
  /// `currentStock` bleibt unberührt (reine Umlagerung Lager→Kühlschrank). Für
  /// ALLE aktiven Mitarbeiter (§12.2); kein Audit (die Bewegung ist das Protokoll).
  Future<void> refillFridge(Product product, {int? quantity}) async {
    final orgId = _orgId;
    final productId = product.id;
    if (orgId == null || productId == null) {
      return;
    }
    // Frischen Stand bevorzugen (der gestreamte/cache-Wert ist aktueller als ein
    // evtl. älteres übergebenes Objekt).
    final current = productById(productId) ?? product;
    final oldFridge = current.fridgeStockClamped;
    final int newFridge;
    if (quantity == null) {
      newFridge = current.fridgeTargetStock;
    } else {
      final raw = oldFridge + quantity;
      newFridge = raw < 0 ? 0 : raw;
    }
    final refilled = newFridge - oldFridge;
    if (refilled == 0) {
      return;
    }
    final mutationId = _uuid.v4();
    if (_usesFirestore &&
        await _tryFirestore(
          'refillFridge',
          () => _inventory.setFridgeStock(
            orgId: orgId,
            productId: productId,
            fridgeStock: newFridge,
            refilledQty: refilled,
            createdByUid: _currentUser?.uid,
            clientMutationId: mutationId,
          ),
        )) {
      return;
    }
    _applyLocalFridgeRefill(
      product: current,
      newFridgeStock: newFridge,
      refilledQty: refilled,
    );
    await _persistProducts();
    await _persistMovements();
    _safeNotify();
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
    // H10 (Sicherheits-Audit 2026-07/GB): Cloud-Pfad bucht Quelle+Ziel+beide
    // Bewegungen in EINER Transaktion (transferProductStock) — Bestand kann
    // nicht mehr verschwinden, wenn die Ziel-Buchung scheitert. Lokal (und im
    // Hybrid-Fallback) bleibt die sequenzielle In-Memory-Buchung.
    final orgId = _orgId;
    if (_usesFirestore && orgId != null) {
      try {
        await _inventory.transferProductStock(
          orgId: orgId,
          fromProductId: from.id!,
          toProductId: to.id!,
          quantity: quantity,
          fromReason: 'Umlagerung nach $toLabel',
          toReason: 'Umlagerung von $fromLabel',
          createdByUid: _currentUser?.uid,
          clientMutationId: _uuid.v4(),
        );
        _audit?.call(
          action: AuditAction.updated,
          entityType: 'Bestand',
          entityId: from.id,
          summary:
              'Umlagerung „${from.name}": $quantity ${from.unit} von $fromLabel nach $toLabel',
        );
        return null;
      } catch (error) {
        if (!usesHybridStorage) {
          return error is StateError
              ? error.message
              : 'Umlagerung fehlgeschlagen (nichts gebucht).';
        }
        AppLogger.warning(
          'Inventory: transferStock offline – lokaler Fallback aktiv',
          error: error,
        );
        // Hybrid: unten sequenziell lokal buchen (adjustStock faellt selbst
        // lokal zurueck).
      }
    }
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

  /// Sucht den passenden Zielartikel fuer eine Umlagerung von [from] an den
  /// Standort [toSiteId]: erst exakter Barcode-Match, dann Name (case-
  /// insensitiv). `null`, wenn der Artikel dort noch nicht gefuehrt wird.
  Product? findTransferTarget(Product from, String toSiteId) {
    final barcode = from.barcode?.trim();
    if (barcode != null && barcode.isNotEmpty) {
      // Schreibweisen-tolerant (UPC-A vs. EAN-13 mit fuehrender Null etc.),
      // sonst legt die Umlagerung am Ziel ein Duplikat in anderer Schreibweise
      // an — vorbei an der harten Eindeutigkeit (die Ziel-Anlage schreibt
      // direkt uebers Repo).
      final variants = gtinLookupVariants(barcode);
      for (final candidate in _products) {
        if (candidate.siteId == toSiteId &&
            candidate.id != null &&
            candidate.id != from.id &&
            variants.contains(candidate.barcode?.trim() ?? '')) {
          return candidate;
        }
      }
    }
    final nameLower = from.name.trim().toLowerCase();
    for (final candidate in _products) {
      if (candidate.siteId == toSiteId &&
          candidate.id != null &&
          candidate.id != from.id &&
          candidate.name.trim().toLowerCase() == nameLower) {
        return candidate;
      }
    }
    return null;
  }

  /// Umlagerung nach Ziel-STANDORT statt Ziel-Artikel: existiert der Artikel
  /// dort schon ([findTransferTarget]), wird direkt umgebucht; sonst wird er
  /// am Ziel mit denselben Stammdaten (Bestand 0, ohne Kuehlschrank-Ist)
  /// angelegt und anschliessend beliefert. Nimmt dem Alltag der zwei Laeden
  /// die Huerde, den Artikel vor jeder ersten Umlagerung von Hand zu
  /// duplizieren. Gibt `null` bei Erfolg oder eine deutsche Fehlermeldung.
  Future<String?> transferStockToSite({
    required Product from,
    required String toSiteId,
    String? toSiteName,
    required int quantity,
  }) async {
    if (toSiteId == from.siteId) {
      return 'Quelle und Ziel müssen unterschiedliche Standorte sein.';
    }
    final existing = findTransferTarget(from, toSiteId);
    if (existing != null) {
      return transferStock(from: from, to: existing, quantity: quantity);
    }
    final orgId = _orgId;
    if (orgId == null) {
      return 'Keine Organisation aktiv.';
    }
    if (quantity <= 0) {
      return 'Bitte eine Menge größer als 0 eingeben.';
    }
    if (from.id == null) {
      return 'Artikel ist noch nicht gespeichert.';
    }
    if (from.currentStock - quantity < 0) {
      return 'Menge ($quantity) übersteigt den Bestand der Quelle '
          '(${from.currentStock} ${from.unit}).';
    }
    final template = Product(
      orgId: orgId,
      siteId: toSiteId,
      siteName: toSiteName,
      name: from.name,
      sku: from.sku,
      barcode: from.barcode,
      category: from.category,
      unit: from.unit,
      supplierId: from.supplierId,
      supplierName: from.supplierName,
      purchasePriceCents: from.purchasePriceCents,
      sellingPriceCents: from.sellingPriceCents,
      taxRatePercent: from.taxRatePercent,
      minStock: from.minStock,
      targetStock: from.targetStock,
      reorderQuantity: from.reorderQuantity,
      createdByUid: _currentUser?.uid,
    );
    // Anlage analog zum saveProduct-Speichermuster, aber mit der neuen Doc-ID
    // als Rueckgabe (die braucht die direkt folgende Umlagerungs-Buchung).
    Product? target;
    if (_usesFirestore) {
      try {
        final newId = await _inventory.saveProduct(template);
        target = template.copyWith(id: newId);
        // Sofort in den In-Memory-Bestand uebernehmen: die direkt folgende
        // Umlagerungs-Buchung kann im Hybrid-Fallback lokal landen und braucht
        // den Zielartikel in _products (der Stream liefert ihn erst spaeter —
        // sonst liefe _applyLocalStockChange ins Leere und die Quelle waere
        // belastet, ohne dass das Ziel etwas bekommt). Der naechste
        // Stream-Snapshot ersetzt die Liste ohnehin mit der Server-Wahrheit.
        _products = _upsertLocal(_products, target, (item) => item.id);
        _safeNotify();
      } catch (error) {
        if (!usesHybridStorage) {
          AppLogger.warning(
            'Inventory: transferStockToSite Zielartikel-Anlage fehlgeschlagen',
            error: error,
          );
          return 'Zielartikel konnte nicht angelegt werden – bitte erneut '
              'versuchen.';
        }
      }
    }
    if (target == null) {
      final stored = template.copyWith(id: _nextLocalId('product'));
      _products = _upsertLocal(_products, stored, (item) => item.id);
      _products
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      await _persistProducts();
      _safeNotify();
      target = stored;
    }
    _audit?.call(
      action: AuditAction.created,
      entityType: 'Produkt',
      entityId: target.id,
      summary:
          'Produkt „${target.name}" für Umlagerung am Zielstandort angelegt',
    );
    return transferStock(from: from, to: target, quantity: quantity);
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
    // Alten Status VOR dem Upsert merken (Übergang → geliefert löst die
    // Wareneinsatz-Buchung aus, H-A2).
    final oldStatus = _purchaseOrderStatus(prepared.id);
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
        await _bookPurchaseOrderCostIfNeeded(
            prepared.copyWith(id: newId), oldStatus);
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
            orderNumber: prepared.orderNumber ?? _nextLocalOrderNumber(),
          )
        : prepared;
    _orders = _upsertLocal(_orders, withId, (item) => item.id);
    _orders.sort((a, b) => (b.orderNumber ?? '').compareTo(a.orderNumber ?? ''));
    await _persistOrders();
    _safeNotify();
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Bestellung',
      entityId: withId.id,
      summary: summary,
    );
    await _bookPurchaseOrderCostIfNeeded(withId, oldStatus);
    return withId.id!;
  }

  /// Naechste lokale Bestellnummer `BST-<Jahr>-NNNN`: hoechstes bereits
  /// vergebenes Suffix des Jahres + 1 — NICHT die Listenlaenge, die nach einer
  /// Loeschung mit bestehenden Nummern kollidieren wuerde.
  String _nextLocalOrderNumber() {
    final prefix = 'BST-${DateTime.now().year}-';
    var maxSeq = 0;
    for (final order in _orders) {
      final number = order.orderNumber;
      if (number == null || !number.startsWith(prefix)) {
        continue;
      }
      final seq = int.tryParse(number.substring(prefix.length));
      if (seq != null && seq > maxSeq) {
        maxSeq = seq;
      }
    }
    return '$prefix${(maxSeq + 1).toString().padLeft(4, '0')}';
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

  /// Schließt die nach einer Teillieferung verbleibende Restmenge.
  ///
  /// Der Bestellstatus wird explizit auf `received` gesetzt, ohne die offenen
  /// Positionsmengen als geliefert auszugeben. Dadurch kann der Wareneinsatz
  /// auf Basis der tatsächlich gelieferten Mengen gebucht werden.
  Future<void> closePurchaseOrderRemainder({
    required String orderId,
    required String reason,
  }) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    final current = _purchaseOrderForId(orderId);
    if (current == null) {
      throw StateError('Bestellung wurde nicht gefunden.');
    }
    final trimmedReason = reason.trim();
    _validateRemainderClosure(current, trimmedReason);

    PurchaseOrder? closedByRepository;
    if (_usesFirestore &&
        await _tryFirestore('closePurchaseOrderRemainder', () async {
          closedByRepository = await _inventory.closePurchaseOrderRemainder(
            orgId: orgId,
            orderId: orderId,
            reason: trimmedReason,
          );
        })) {
      final closed = closedByRepository!;
      _audit?.call(
        action: AuditAction.updated,
        entityType: 'Bestellung',
        entityId: orderId,
        summary: 'Restmenge geschlossen: $trimmedReason',
      );
      await _bookPurchaseOrderCostIfNeeded(closed, current.status);
      return;
    }

    final closed = _closedRemainderOrder(
      current,
      reason: trimmedReason,
      closedAt: DateTime.now(),
    );
    final orderIndex = _orders.indexWhere((order) => order.id == orderId);
    if (orderIndex < 0) {
      throw StateError('Bestellung wurde nicht gefunden.');
    }
    _orders[orderIndex] = closed;
    _orders = [..._orders];
    await _persistOrders();
    _safeNotify();
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Bestellung',
      entityId: orderId,
      summary: 'Restmenge geschlossen: $trimmedReason',
    );
    await _bookPurchaseOrderCostIfNeeded(closed, current.status);
  }

  PurchaseOrder _closedRemainderOrder(
    PurchaseOrder order, {
    required String reason,
    required DateTime closedAt,
  }) {
    _validateRemainderClosure(order, reason);
    return order.copyWith(
      status: PurchaseOrderStatus.received,
      closedAt: closedAt,
      closedReason: reason,
    );
  }

  void _validateRemainderClosure(PurchaseOrder order, String reason) {
    if (reason.trim().isEmpty) {
      throw StateError(
        'Bitte eine Begründung für das Schließen der Restmenge angeben.',
      );
    }
    if (order.closedAt != null) {
      throw StateError('Die Restmenge wurde bereits geschlossen.');
    }
    if (order.status != PurchaseOrderStatus.ordered &&
        order.status != PurchaseOrderStatus.partiallyReceived) {
      throw StateError('Nur offene Bestellungen können geschlossen werden.');
    }
    if (!order.hasAnyReceipt) {
      throw StateError(
        'Der Rest kann erst nach mindestens einer Teillieferung geschlossen '
        'werden.',
      );
    }
    if (order.isFullyReceived) {
      throw StateError('Die Bestellung ist bereits vollständig geliefert.');
    }
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
    // Growable lassen: _upsertLocal ruft .add() auf derselben Liste — eine
    // fixed-length-Liste liesse das naechste lokale Speichern crashen.
    _orders = _orders.where((order) => order.id != orderId).toList();
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
    // Wareneinsatz-Buchung (H-A2): vorab prüfen, ob dieser Wareneingang die
    // Bestellung vollständig macht (Übergang → geliefert). Aus dem Vor-Zustand
    // projiziert → mode-unabhängig, idempotent über die deterministische
    // Journal-ID po-<id> (auch wenn der Cloud-Stream noch nicht aktualisiert ist).
    final before = _purchaseOrderForId(orderId);
    final bookCost = before != null &&
        before.status != PurchaseOrderStatus.received &&
        before.totalQuantityOrdered > 0 &&
        (before.totalQuantityReceived + receivedTotal) >=
            before.totalQuantityOrdered;
    Future<void> maybeBook() async {
      if (!bookCost) return;
      await _bookPurchaseOrderCostIfNeeded(
        before.copyWith(
          status: PurchaseOrderStatus.received,
          receivedAt: before.receivedAt ?? DateTime.now(),
        ),
        before.status,
      );
    }

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
      await maybeBook();
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
    await maybeBook();
  }

  PurchaseOrder? _purchaseOrderForId(String? id) {
    if (id == null) return null;
    for (final o in _orders) {
      if (o.id == id) return o;
    }
    return null;
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
    // Alten Status VOR dem Upsert merken (Übergang → abgeholt löst die
    // Umsatz-Buchung aus, H-A2).
    final oldStatus = _customerOrderStatus(prepared.id);
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
        await _bookCustomerOrderRevenueIfNeeded(
            prepared.copyWith(id: newId), oldStatus);
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
    _customerOrders = _upsertLocal(_customerOrders, withId, (item) => item.id);
    await _persistCustomerOrders();
    _safeNotify();
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Kundenbestellung',
      entityId: withId.id,
      summary: summary,
    );
    await _bookCustomerOrderRevenueIfNeeded(withId, oldStatus);
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
    // Growable lassen: _upsertLocal ruft .add() auf derselben Liste — eine
    // fixed-length-Liste liesse das naechste lokale Speichern crashen.
    _customerOrders =
        _customerOrders.where((order) => order.id != orderId).toList();
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
    var next = order.nextPickupDate;
    if (order.recurrence.isRecurring && next != null) {
      // Folgetermin so weit vorschieben, bis er in der Zukunft liegt. Sonst
      // legt eine spät abgeholte Wiederholung sofort wieder eine überfällige
      // Folgebestellung an (probleme #57).
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      var guard = 0;
      while (!next!.isAfter(today) && guard < 520) {
        next = order.recurrence.advance(next);
        guard++;
      }
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
            // USt-Satz aus dem Artikel (M6-B) → Käufe echt netto/brutto.
            taxRatePercent: product?.taxRatePercent,
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
      _weeklyLists = _upsertLocal(_weeklyLists, prepared, (item) => item.siteId);
      _weeklyLists = [..._weeklyLists];
      await _persistWeeklyLists();
    } else {
      _orderCarts = _upsertLocal(_orderCarts, prepared, (item) => item.siteId);
      _orderCarts = [..._orderCarts];
      await _persistOrderCarts();
    }
    _safeNotify();
  }

  // --- Kühlschrank-Nachfüllliste: Mutationen -----------------------------

  /// Setzt [name] (oder einen Artikel) mit [quantity] auf die Nachfüllliste des
  /// Ladens. Ist [productId] gesetzt und steht der Artikel bereits **offen** auf
  /// der Liste, wird die Menge **erhöht** (kollaboratives Sammeln). Freitext-
  /// Positionen (productId == null) werden immer als neuer Eintrag angelegt.
  /// Offen für **jeden aktiven Mitarbeiter** (nicht nur Manager).
  Future<void> addFridgeRefillItem({
    required String siteId,
    String? productId,
    required String name,
    String? category,
    String? unit,
    int quantity = 1,
    String? note,
    String? siteName,
  }) async {
    final trimmedName = name.trim();
    if (siteId.isEmpty || quantity <= 0 || trimmedName.isEmpty) {
      return;
    }
    final list = fridgeRefillListForSite(siteId) ??
        FridgeRefillList(
          orgId: _orgId ?? '',
          siteId: siteId,
          siteName: siteName,
        );
    final items = [...list.items];
    final hasProduct = productId != null && productId.isNotEmpty;
    final index = hasProduct
        ? items.indexWhere(
            (item) => !item.done && item.productId == productId,
          )
        : -1;
    if (index >= 0) {
      final existing = items[index];
      items[index] = existing.copyWith(
        name: trimmedName,
        unit: unit ?? existing.unit,
        category: category,
        clearCategory: category == null,
        quantity: existing.quantity + quantity,
        note: note,
        clearNote: note == null,
        addedByUid: _currentUser?.uid,
        addedByName: _currentUser?.displayName,
        addedAt: DateTime.now(),
      );
    } else {
      items.add(
        FridgeRefillItem(
          id: _uuid.v4(),
          productId: hasProduct ? productId : null,
          name: trimmedName,
          category: category,
          unit: (unit == null || unit.trim().isEmpty) ? 'Stück' : unit.trim(),
          quantity: quantity,
          note: note,
          addedByUid: _currentUser?.uid,
          addedByName: _currentUser?.displayName,
          addedAt: DateTime.now(),
        ),
      );
    }
    await _persistFridgeList(
      list.copyWith(
        siteName: siteName ?? list.siteName,
        items: items,
        updatedByUid: _currentUser?.uid,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Setzt die Menge einer Nachfüll-Position. [quantity] <= 0 entfernt sie.
  Future<void> setFridgeRefillItemQuantity({
    required String siteId,
    required String itemId,
    required int quantity,
  }) async {
    final list = fridgeRefillListForSite(siteId);
    if (list == null) {
      return;
    }
    final items = <FridgeRefillItem>[];
    for (final item in list.items) {
      if (item.id == itemId) {
        if (quantity > 0) {
          items.add(item.copyWith(quantity: quantity));
        }
        // quantity <= 0 -> Position weglassen (entfernen)
      } else {
        items.add(item);
      }
    }
    await _persistFridgeList(
      list.copyWith(
        items: items,
        updatedByUid: _currentUser?.uid,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> removeFridgeRefillItem({
    required String siteId,
    required String itemId,
  }) =>
      setFridgeRefillItemQuantity(siteId: siteId, itemId: itemId, quantity: 0);

  /// Hakt eine Position ab ([done] true = aus dem Lager geholt und nachgefüllt)
  /// bzw. nimmt das Häkchen zurück.
  Future<void> setFridgeRefillItemDone({
    required String siteId,
    required String itemId,
    required bool done,
  }) async {
    final list = fridgeRefillListForSite(siteId);
    if (list == null) {
      return;
    }
    final items = list.items
        .map((item) => item.id == itemId ? item.copyWith(done: done) : item)
        .toList();
    await _persistFridgeList(
      list.copyWith(
        items: items,
        updatedByUid: _currentUser?.uid,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Entfernt alle bereits abgehakten Positionen (Aufräumen nach dem
  /// Nachfüllen). Speichert eine reduzierte Liste (Update-Pfad – funktioniert
  /// auch für Mitarbeiter ohne Lösch-Recht).
  Future<void> clearFridgeRefillDone(String siteId) async {
    final list = fridgeRefillListForSite(siteId);
    if (list == null) {
      return;
    }
    final remaining = list.items.where((item) => !item.done).toList();
    if (remaining.length == list.items.length) {
      return;
    }
    await _persistFridgeList(
      list.copyWith(
        items: remaining,
        updatedByUid: _currentUser?.uid,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Leert die gesamte Nachfüllliste eines Ladens.
  Future<void> clearFridgeRefillList(String siteId) async {
    final list = fridgeRefillListForSite(siteId);
    if (list == null || list.items.isEmpty) {
      return;
    }
    await _persistFridgeList(
      list.copyWith(
        items: const [],
        updatedByUid: _currentUser?.uid,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Persistiert die Nachfüllliste nach dem Drei-Speichermodi-Muster. Doc-ID =
  /// `siteId` (Singleton je Laden). Wie beim Bestellkorb ist die cloud/hybrid-
  /// Schreibstrategie „last writer wins" (read-modify-write über den gestreamten
  /// Stand) — für zwei Läden mit wenigen Mitarbeitern bewusst akzeptiert.
  Future<void> _persistFridgeList(FridgeRefillList list) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    final prepared = list.copyWith(orgId: orgId, id: list.siteId);
    if (_usesFirestore &&
        await _tryFirestore(
          'saveFridgeRefillList',
          () => _inventory.saveFridgeRefillList(prepared),
        )) {
      return;
    }
    _fridgeLists = _upsertLocal(_fridgeLists, prepared, (item) => item.siteId);
    _fridgeLists = [..._fridgeLists];
    await _persistFridgeLists();
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

  /// Lokales Pendant zu [FirestoreInventoryRepository.setFridgeStock]: setzt
  /// `fridgeStock` (currentStock unberührt) und hängt eine `fridgeRefill`-
  /// Bewegung an.
  void _applyLocalFridgeRefill({
    required Product product,
    required int newFridgeStock,
    required int refilledQty,
  }) {
    final index = _products.indexWhere((p) => p.id == product.id);
    if (index < 0) {
      return;
    }
    _products[index] = _products[index].copyWith(fridgeStock: newFridgeStock);
    _products = [..._products];
    _movements = [
      StockMovement(
        id: _nextLocalId('movement'),
        orgId: product.orgId,
        siteId: product.siteId,
        productId: product.id!,
        productName: product.name,
        type: StockMovementType.fridgeRefill,
        quantityDelta: refilledQty,
        balanceAfter: newFridgeStock,
        reason: 'Kühlschrank nachgefüllt',
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
    if (order.closedAt != null) {
      throw StateError(
        'Für eine geschlossene Bestellung kann kein weiterer Wareneingang '
        'gebucht werden.',
      );
    }
    final updatedItems = <PurchaseOrderItem>[];
    for (var i = 0; i < order.items.length; i++) {
      final item = order.items[i];
      final qty = (receivedByItemIndex[i] ?? 0).clamp(
        0,
        item.outstandingQuantity,
      );
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
      receivedAt:
          newStatus == PurchaseOrderStatus.received
          ? (order.receivedAt ?? DateTime.now())
          : order.receivedAt,
    );
    _orders = [..._orders];
  }

  /// Ersetzt das Element mit gleicher ID bzw. haengt es an — auf einer NEUEN
  /// growable Liste, die der Aufrufer dem Feld zuweist. Wichtig: in
  /// cloud/hybrid stammen die Felder direkt aus dem Firestore-Stream
  /// (`.toList(growable: false)`) — ein in-place `.add()` wuerde dort mit
  /// `UnsupportedError` crashen (Hybrid-Offline-Fallback nach Stream-Emit).
  List<T> _upsertLocal<T>(
    List<T> list,
    T item,
    String? Function(T) idOf,
  ) {
    final id = idOf(item);
    final index = list.indexWhere((existing) => idOf(existing) == id);
    final next = [...list];
    if (index >= 0) {
      next[index] = item;
    } else {
      next.add(item);
    }
    return next;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSubscriptions();
    super.dispose();
  }
}
