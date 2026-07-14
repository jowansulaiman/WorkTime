import '../models/cash_closing.dart';
import '../models/cash_count.dart';
import '../models/customer_order.dart';
import '../models/delivery_advice.dart';
import '../models/fridge_refill.dart';
import '../models/inventory_count_session.dart';
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

/// Abstraktion ueber den Datenzugriff der Warenwirtschaft (Lieferanten,
/// Artikel, Bestellungen, Bestandsbewegungen).
///
/// Die High-Level-Schicht ([InventoryProvider]) haengt von dieser Abstraktion
/// statt von der konkreten `FirestoreService`-Klasse ab (DIP,
/// no-domain-repository-interfaces-dip). Implementierungen kapseln den
/// konkreten Datenzugriff (Firestore) bzw. lassen sich in Tests durch einen
/// handgeschriebenen Fake ersetzen.
abstract interface class InventoryRepository {
  Stream<List<Supplier>> watchSuppliers(String orgId);

  Stream<List<Product>> watchProducts(String orgId);

  Stream<List<PurchaseOrder>> watchPurchaseOrders(String orgId);

  /// Letzte Bestandsbewegungen, optional auf einen Artikel ([productId]) oder
  /// – fuer den standortgescopten Verlauf – auf einen Standort ([siteId])
  /// gefiltert. Ist [productId] gesetzt, hat es Vorrang vor [siteId].
  Stream<List<StockMovement>> watchStockMovements(
    String orgId, {
    String? productId,
    String? siteId,
    int limit = 100,
  });

  /// Bestandsbewegungen im Zeitraum [from]..[to] (inklusive, nach `createdAt`),
  /// optional auf einen Standort ([siteId]) gefiltert. Anders als
  /// [watchStockMovements] OHNE hartes Limit — Auswertungen ueber Wochen
  /// (Verkaufsgeschwindigkeit/Reichweite/Schwund) brauchen mehr als die
  /// juengsten 100 Bewegungen. Einmaliger Read statt Stream.
  Future<List<StockMovement>> getStockMovementsInRange(
    String orgId,
    DateTime from,
    DateTime to, {
    String? siteId,
  });

  /// Verkaufsfakten (`posReceipts`, P0) im Zeitraum [from]..[to] nach
  /// `transactionDate` (inklusive), optional standortgefiltert. **Cloud-only**
  /// (read) — Basis der Finanz-/Marge-/Schwund-Auswertungen (P2). Serverseitig
  /// geschrieben; es gibt keinen lokalen Fallback.
  Future<List<PosReceipt>> getPosReceiptsInRange(
    String orgId,
    DateTime from,
    DateTime to, {
    String? siteId,
  });

  // --- Kassen-Modul: Zählungen / Abschlüsse / Tagesaggregate --------------
  // Alle cloud-only (wie posReceipts): kein lokaler Fallback, keine Spiegelung.

  /// Zählprotokolle (Kassenstürze) im Zeitraum [from]..[to] nach `countedAt`
  /// (inklusive), optional standortgefiltert, jüngste zuerst.
  Future<List<CashCount>> getCashCountsInRange(
    String orgId,
    DateTime from,
    DateTime to, {
    String? siteId,
  });

  /// Legt ein Zählprotokoll an (create-only — Zählungen sind unveränderlich,
  /// Korrektur = neue Zählung).
  Future<void> addCashCount(CashCount count);

  /// Festgeschriebene Kassenabschlüsse mit Geschäftstag in [fromDay]..[toDay]
  /// (`YYYY-MM-DD`, inklusive), optional standortgefiltert, jüngste zuerst.
  Future<List<CashClosing>> getCashClosingsInRange(
    String orgId,
    String fromDay,
    String toDay, {
    String? siteId,
  });

  /// Schreibt einen Kassenabschluss fest (create-only, deterministische
  /// Doc-ID `{businessDay}-{siteId}`). Existiert der Tag bereits, wirft die
  /// Implementierung einen deutschen [StateError].
  Future<void> createCashClosing(CashClosing closing);

  /// Markiert einen festgeschriebenen Abschluss als ins Finanzjournal gebucht
  /// — die einzige erlaubte Mutation (`bookedToFinance false→true`, Plan §3.2).
  Future<void> markCashClosingBooked({
    required String orgId,
    required String closingId,
  });

  /// Serverseitige Tagesaggregate (`posDailyStats`, Plan §3.3) mit
  /// Geschäftstag in [fromDay]..[toDay] (`YYYY-MM-DD`, inklusive), optional
  /// standortgefiltert, jüngste zuerst.
  Future<List<PosDailyStat>> getPosDailyStatsInRange(
    String orgId,
    String fromDay,
    String toDay, {
    String? siteId,
  });

  Future<void> saveSupplier(Supplier supplier);

  Future<void> deleteSupplier({
    required String orgId,
    required String supplierId,
  });

  /// Speichert einen Artikel und gibt dessen Doc-ID zurueck (bei Anlage die
  /// neu vergebene) — Aufrufer wie die Umlagerung mit Zielartikel-Anlage
  /// brauchen die ID fuer die direkt folgende Bestandsbuchung.
  Future<String> saveProduct(Product product);

  Future<void> deleteProduct({
    required String orgId,
    required String productId,
  });

  // --- MHD-/Ablauf-Chargen (productBatches) ------------------------------
  // Warenchargen mit Mindesthaltbarkeitsdatum. Ein Artikel kann mehrere Chargen
  // mit unterschiedlichem MHD haben. Reiner `orderBy(expiryDay)`-Stream
  // (Single-Field, auto-indiziert) — die Warnung wird clientseitig via
  // `computeExpiryWarnings` abgeleitet (kein Composite-Index in M1).

  /// Warenchargen mit MHD (Collection `productBatches`), aufsteigend nach MHD.
  Stream<List<ProductBatch>> watchProductBatches(String orgId);

  /// Speichert eine Charge (Anlage oder Update; Doc-ID bei Anlage vergeben).
  Future<void> saveProductBatch(ProductBatch batch);

  /// Loescht eine Charge.
  Future<void> deleteProductBatch({
    required String orgId,
    required String batchId,
  });

  /// Schreibt einen unveraenderlichen Preis-Historie-Eintrag in die
  /// Subcollection des Artikels (`products/{productId}/priceHistory`).
  Future<void> addPriceHistory(PriceHistoryEntry entry);

  /// Liest die Preis-Historie eines Artikels (neueste zuerst).
  Future<List<PriceHistoryEntry>> fetchPriceHistory({
    required String orgId,
    required String productId,
  });

  // --- Scan-Telemetrie (scanEvents) ---------------------------------------
  // Append-only wie stockMovements; Auswertung clientseitig via
  // `computeScanStats`. Nur `orderBy(createdAt)` -> Single-Field-Index,
  // KEIN Composite noetig.

  /// Schreibt ein Scan-Ereignis. Aufrufer loggen fire-and-forget — Fehler
  /// hier duerfen das Scannen nie stoeren oder verlangsamen.
  Future<void> addScanEvent(ScanEvent event);

  /// Liest die juengsten Scan-Ereignisse (neueste zuerst, einmaliger Read —
  /// die Statistik ist eine Auswertungs-Ansicht, kein Live-Board).
  Future<List<ScanEvent>> fetchScanEvents(String orgId, {int limit = 500});

  /// Bucht eine Bestandsaenderung atomar und gibt den neuen Bestand zurueck.
  Future<int> adjustProductStock({
    required String orgId,
    required String productId,
    required int delta,
    required StockMovementType type,
    String? reason,
    String? relatedOrderId,
    String? createdByUid,
    String? clientMutationId,
  });

  /// H9 (Inventur): setzt den Bestand ABSOLUT auf [newStock] und bucht die
  /// Differenz zum frischen Serverstand als Bewegung — das Delta entsteht in
  /// der Transaktion, nie aus einem potenziell veralteten UI-Stand.
  Future<int> setProductStock({
    required String orgId,
    required String productId,
    required int newStock,
    StockMovementType type = StockMovementType.stocktake,
    String? reason,
    String? createdByUid,
    String? clientMutationId,
  });

  /// H10 (Umlagerung): bucht Abgang an der Quelle und Zugang am Ziel in EINER
  /// Transaktion (inkl. beider Bewegungs-Docs) — Bestand kann nicht mehr durch
  /// eine fehlgeschlagene Ziel-Buchung "verschwinden".
  Future<void> transferProductStock({
    required String orgId,
    required String fromProductId,
    required String toProductId,
    required int quantity,
    String? fromReason,
    String? toReason,
    String? createdByUid,
    String? clientMutationId,
  });

  /// Setzt den Kühlschrank-Ist-Stand [fridgeStock] eines Artikels (absolut) und
  /// protokolliert eine `fridgeRefill`-Bewegung über [refilledQty]. Ändert den
  /// Gesamtbestand (`currentStock`) NICHT — reine Umlagerung Lager→Kühlschrank.
  Future<void> setFridgeStock({
    required String orgId,
    required String productId,
    required int fridgeStock,
    required int refilledQty,
    String? createdByUid,
    String? clientMutationId,
  });

  Future<String> savePurchaseOrder(PurchaseOrder order);

  Future<void> deletePurchaseOrder({
    required String orgId,
    required String orderId,
  });

  /// Schließt die offene Restmenge einer teilweise gelieferten Bestellung.
  Future<PurchaseOrder> closePurchaseOrderRemainder({
    required String orgId,
    required String orderId,
    required String reason,
  });

  // --- Lieferavise (deliveryAdvices) -------------------------------------
  // Angekündigte Lieferungen (WW-4). Komplette Org-Collection als Stream
  // (kleines Org-Volumen; Filter/Sortierung clientseitig) — reiner Read ohne
  // where/orderBy, KEIN Composite-Index. Direkte Firestore-Writes wie
  // productBatches (kein Callable-Pfad).

  /// Lieferavise einer Organisation (Collection `deliveryAdvices`).
  Stream<List<DeliveryAdvice>> watchDeliveryAdvices(String orgId);

  /// Speichert ein Lieferavis (Anlage oder Update; Doc-ID bei Anlage vergeben).
  Future<void> saveDeliveryAdvice(DeliveryAdvice advice);

  /// Löscht ein Lieferavis.
  Future<void> deleteDeliveryAdvice({
    required String orgId,
    required String adviceId,
  });

  // --- Inventur-Sessions (inventoryCountSessions + lines-Subcollection, WW-8) --
  // Komplette Session-Collection streamen (Org-Volumen klein), Filter/Sortierung
  // clientseitig → KEIN Composite-Index. Zähl-EVENTS liegen als append-only
  // Docs in der lines-Subcollection je Session.

  /// Alle Inventur-Sessions einer Organisation (nur Metadaten, ohne lines).
  Stream<List<InventoryCountSession>> watchInventoryCountSessions(String orgId);

  /// Speichert/aktualisiert eine Session (Anlage vergibt Doc-ID) und gibt die
  /// Doc-ID zurück.
  Future<String> saveInventoryCountSession(InventoryCountSession session);

  /// Zähl-Events einer Session (append-only Subcollection `lines`).
  Stream<List<InventoryCountEvent>> watchInventoryCountLines(
    String orgId,
    String sessionId,
  );

  /// Speichert/aktualisiert ein Zähl-Event einer Session; gibt die Line-ID
  /// zurück (Anlage vergibt sie).
  Future<String> saveInventoryCountEvent({
    required String orgId,
    required String sessionId,
    required InventoryCountEvent event,
  });

  Stream<List<CustomerOrder>> watchCustomerOrders(String orgId);

  /// Speichert eine Kundenbestellung (Anlage oder Update) und gibt deren Id
  /// zurueck. Vergibt bei neuen Bestellungen eine Bestellnummer.
  Future<String> saveCustomerOrder(CustomerOrder order);

  Future<void> deleteCustomerOrder({
    required String orgId,
    required String orderId,
  });

  /// Bucht den Wareneingang fuer eine Bestellung atomar.
  ///
  /// **WW-6:** [receivedByItemIndex] trägt je Positionsindex eine
  /// [PurchaseReceiptLine] (Menge + optional Ist-EK/MHD/Charge); die Menge wird
  /// auf den offenen Rest geklemmt. Der Ist-EK landet an der Position, die
  /// [deliveryNoteNumber] an der Bestellung. Chargen legt der Provider im
  /// Nachlauf an (nicht Teil der atomaren Bestandstransaktion).
  Future<void> receivePurchaseOrder({
    required String orgId,
    required String orderId,
    required Map<int, PurchaseReceiptLine> receivedByItemIndex,
    String? deliveryNoteNumber,
    String? createdByUid,
    String? clientMutationId,
  });

  // --- Bestelllisten (Wochen-Bestellkorb + Standard-Wochenliste) ---------
  // Singleton je Laden (Doc-ID = siteId), eingebettete Positionen. Bewusst kein
  // orderBy/Index – die Collections sind klein (eine Liste je Laden).

  /// Geteilte Bestellkörbe je Laden (Collection `orderCarts`).
  Stream<List<SiteOrderList>> watchOrderCarts(String orgId);

  /// Standard-Wochenlisten je Laden (Collection `weeklyOrderLists`).
  Stream<List<SiteOrderList>> watchWeeklyOrderLists(String orgId);

  /// Speichert eine Bestellliste (Doc-ID = `list.siteId`); [list.kind] bestimmt
  /// die Ziel-Collection.
  Future<void> saveOrderList(SiteOrderList list);

  /// Löscht eine Bestellliste eines Ladens (z.B. Korb nach Checkout leeren).
  Future<void> deleteOrderList({
    required String orgId,
    required String siteId,
    required OrderListKind kind,
  });

  // --- Kühlschrank-Nachfüllliste -----------------------------------------
  // Singleton je Laden (Doc-ID = siteId), eingebettete Positionen. Collection
  // `fridgeRefillLists`, analog zu den Bestelllisten (klein, kein Index).

  /// Kühlschrank-Nachfülllisten je Laden (Collection `fridgeRefillLists`).
  Stream<List<FridgeRefillList>> watchFridgeRefillLists(String orgId);

  /// Speichert die Nachfüllliste eines Ladens (Doc-ID = `list.siteId`).
  Future<void> saveFridgeRefillList(FridgeRefillList list);

  /// Löscht die Nachfüllliste eines Ladens.
  Future<void> deleteFridgeRefillList({
    required String orgId,
    required String siteId,
  });
}
