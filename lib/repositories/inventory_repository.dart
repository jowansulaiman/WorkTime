import '../models/customer_order.dart';
import '../models/price_history_entry.dart';
import '../models/product.dart';
import '../models/purchase_order.dart';
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

  Future<void> saveSupplier(Supplier supplier);

  Future<void> deleteSupplier({
    required String orgId,
    required String supplierId,
  });

  Future<void> saveProduct(Product product);

  Future<void> deleteProduct({
    required String orgId,
    required String productId,
  });

  /// Schreibt einen unveraenderlichen Preis-Historie-Eintrag in die
  /// Subcollection des Artikels (`products/{productId}/priceHistory`).
  Future<void> addPriceHistory(PriceHistoryEntry entry);

  /// Liest die Preis-Historie eines Artikels (neueste zuerst).
  Future<List<PriceHistoryEntry>> fetchPriceHistory({
    required String orgId,
    required String productId,
  });

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

  Future<String> savePurchaseOrder(PurchaseOrder order);

  Future<void> deletePurchaseOrder({
    required String orgId,
    required String orderId,
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
  Future<void> receivePurchaseOrder({
    required String orgId,
    required String orderId,
    required Map<int, int> receivedByItemIndex,
    String? createdByUid,
    String? clientMutationId,
  });
}
