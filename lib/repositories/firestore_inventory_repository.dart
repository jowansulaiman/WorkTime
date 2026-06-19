import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/product.dart';
import '../models/purchase_order.dart';
import '../models/stock_movement.dart';
import '../models/supplier.dart';
import 'inventory_repository.dart';

/// Firestore-Implementierung der [InventoryRepository] — die einzige Stelle mit
/// Warenwirtschafts-Datenzugriffslogik (zuvor im FirestoreService-God-Object,
/// firestore-service-god-object). Reiner Cloud-Datenzugriff; die
/// Speicherstrategie (cloud/hybrid/local) liegt weiterhin im Provider.
class FirestoreInventoryRepository implements InventoryRepository {
  FirestoreInventoryRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _organizationDoc(String orgId) =>
      _firestore.collection('organizations').doc(orgId);

  CollectionReference<Map<String, dynamic>> _supplierCollection(String orgId) =>
      _organizationDoc(orgId).collection('suppliers');

  CollectionReference<Map<String, dynamic>> _productCollection(String orgId) =>
      _organizationDoc(orgId).collection('products');

  CollectionReference<Map<String, dynamic>> _purchaseOrderCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('purchaseOrders');

  CollectionReference<Map<String, dynamic>> _stockMovementCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('stockMovements');

  @override
  Stream<List<Supplier>> watchSuppliers(String orgId) {
    return _supplierCollection(orgId).orderBy('nameLower').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => Supplier.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Stream<List<Product>> watchProducts(String orgId) {
    return _productCollection(orgId).orderBy('nameLower').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => Product.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Stream<List<PurchaseOrder>> watchPurchaseOrders(String orgId) {
    return _purchaseOrderCollection(orgId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => PurchaseOrder.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Stream<List<StockMovement>> watchStockMovements(
    String orgId, {
    String? productId,
    int limit = 100,
  }) {
    Query<Map<String, dynamic>> query = _stockMovementCollection(orgId);
    if (productId != null && productId.isNotEmpty) {
      query = query.where('productId', isEqualTo: productId);
    }
    query = query.orderBy('createdAt', descending: true).limit(limit);
    return query.snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => StockMovement.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Future<void> saveSupplier(Supplier supplier) async {
    final collection = _supplierCollection(supplier.orgId);
    final docRef =
        supplier.id == null ? collection.doc() : collection.doc(supplier.id);
    await docRef.set({
      ...supplier.copyWith(id: docRef.id).toFirestoreMap(),
      if (supplier.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteSupplier({
    required String orgId,
    required String supplierId,
  }) {
    return _supplierCollection(orgId).doc(supplierId).delete();
  }

  @override
  Future<void> saveProduct(Product product) async {
    final collection = _productCollection(product.orgId);
    final docRef =
        product.id == null ? collection.doc() : collection.doc(product.id);
    await docRef.set({
      ...product.copyWith(id: docRef.id).toFirestoreMap(),
      if (product.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteProduct({
    required String orgId,
    required String productId,
  }) {
    return _productCollection(orgId).doc(productId).delete();
  }

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
  }) async {
    final productRef = _productCollection(orgId).doc(productId);
    // Bei vorhandener clientMutationId wird die Bewegung deterministisch
    // adressiert, damit ein App-Level-Retry nach Timeout den Bestand nicht
    // doppelt bucht (no-idempotency-on-stock-mutations).
    final movementRef = clientMutationId == null
        ? _stockMovementCollection(orgId).doc()
        : _stockMovementCollection(orgId).doc(clientMutationId);

    return _firestore.runTransaction<int>((transaction) async {
      final snapshot = await transaction.get(productRef);
      if (!snapshot.exists) {
        throw StateError('Artikel wurde nicht gefunden.');
      }
      final product = Product.fromFirestore(snapshot.id, snapshot.data()!);

      // Idempotenz: existiert die Bewegung mit dieser ID bereits, wurde die
      // Buchung schon angewendet -> kein erneutes Inkrement (no-op). Alle Reads
      // muessen vor allen Writes der Transaktion liegen.
      if (clientMutationId != null) {
        final existing = await transaction.get(movementRef);
        if (existing.exists) {
          return product.currentStock;
        }
      }

      final newStock = product.currentStock + delta;

      transaction.set(productRef, {
        'currentStock': newStock,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      transaction.set(movementRef, {
        ...StockMovement(
          orgId: orgId,
          siteId: product.siteId,
          productId: productId,
          productName: product.name,
          type: type,
          quantityDelta: delta,
          balanceAfter: newStock,
          reason: reason,
          relatedOrderId: relatedOrderId,
          createdByUid: createdByUid,
        ).toFirestoreMap(),
      });

      return newStock;
    });
  }

  @override
  Future<String> savePurchaseOrder(PurchaseOrder order) async {
    final collection = _purchaseOrderCollection(order.orgId);
    final docRef =
        order.id == null ? collection.doc() : collection.doc(order.id);
    var prepared = order.copyWith(id: docRef.id);
    if (order.id == null && (order.orderNumber == null)) {
      prepared = prepared.copyWith(
        orderNumber: await _allocateOrderNumber(order.orgId),
      );
    }
    await docRef.set({
      ...prepared.toFirestoreMap(),
      if (order.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return docRef.id;
  }

  @override
  Future<void> deletePurchaseOrder({
    required String orgId,
    required String orderId,
  }) {
    return _purchaseOrderCollection(orgId).doc(orderId).delete();
  }

  @override
  Future<void> receivePurchaseOrder({
    required String orgId,
    required String orderId,
    required Map<int, int> receivedByItemIndex,
    String? createdByUid,
    String? clientMutationId,
  }) async {
    final orderRef = _purchaseOrderCollection(orgId).doc(orderId);

    await _firestore.runTransaction((transaction) async {
      final orderSnap = await transaction.get(orderRef);
      if (!orderSnap.exists) {
        throw StateError('Bestellung wurde nicht gefunden.');
      }
      final order = PurchaseOrder.fromFirestore(orderSnap.id, orderSnap.data()!);

      // Effektive Mengen (nicht negativ, nicht ueber die offene Menge hinaus)
      // ermitteln und betroffene Artikel laden – alle Reads vor allen Writes.
      final effective = <int, int>{};
      final productSnapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in receivedByItemIndex.entries) {
        final index = entry.key;
        if (index < 0 || index >= order.items.length) {
          continue;
        }
        final item = order.items[index];
        final qty = entry.value.clamp(0, item.outstandingQuantity);
        if (qty <= 0) {
          continue;
        }
        effective[index] = qty;
        final productId = item.productId;
        if (productId != null &&
            productId.isNotEmpty &&
            !productSnapshots.containsKey(productId)) {
          productSnapshots[productId] = await transaction.get(
            _productCollection(orgId).doc(productId),
          );
        }
      }

      if (effective.isEmpty) {
        return;
      }

      // Idempotenz: deterministische Movement-IDs je Position aus der
      // clientMutationId ableiten. Existiert eine davon bereits, wurde dieser
      // Wareneingang schon gebucht -> komplette Transaktion als no-op abbrechen
      // (no-idempotency-on-stock-mutations). Reads vor Writes.
      final movementRefs = <int, DocumentReference<Map<String, dynamic>>>{};
      if (clientMutationId != null) {
        for (final index in effective.keys) {
          movementRefs[index] =
              _stockMovementCollection(orgId).doc('$clientMutationId-$index');
        }
        for (final ref in movementRefs.values) {
          final existing = await transaction.get(ref);
          if (existing.exists) {
            return;
          }
        }
      }

      // Bestaende erhoehen und Bewegungen schreiben.
      final newStockByProduct = <String, int>{};
      for (final entry in effective.entries) {
        final item = order.items[entry.key];
        final productId = item.productId;
        if (productId == null || productId.isEmpty) {
          continue;
        }
        final snapshot = productSnapshots[productId];
        if (snapshot == null || !snapshot.exists) {
          continue;
        }
        final product = Product.fromFirestore(snapshot.id, snapshot.data()!);
        final base = newStockByProduct[productId] ?? product.currentStock;
        final newStock = base + entry.value;
        newStockByProduct[productId] = newStock;

        transaction.set(
          _productCollection(orgId).doc(productId),
          {
            'currentStock': newStock,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        transaction.set(
          movementRefs[entry.key] ?? _stockMovementCollection(orgId).doc(),
          StockMovement(
            orgId: orgId,
            siteId: product.siteId,
            productId: productId,
            productName: product.name,
            type: StockMovementType.receipt,
            quantityDelta: entry.value,
            balanceAfter: newStock,
            reason: 'Wareneingang ${order.orderNumber ?? ''}'.trim(),
            relatedOrderId: orderId,
            createdByUid: createdByUid,
          ).toFirestoreMap(),
        );
      }

      // Gelieferte Mengen in den Positionen fortschreiben.
      final updatedItems = <PurchaseOrderItem>[];
      for (var i = 0; i < order.items.length; i++) {
        final item = order.items[i];
        final add = effective[i] ?? 0;
        updatedItems.add(
          add > 0
              ? item.copyWith(quantityReceived: item.quantityReceived + add)
              : item,
        );
      }

      final updatedOrder = order.copyWith(items: updatedItems);
      final newStatus = updatedOrder.deriveReceiptStatus();

      transaction.set(orderRef, {
        'items': updatedItems.map((item) => item.toFirestoreMap()).toList(),
        'status': newStatus.value,
        if (newStatus == PurchaseOrderStatus.received)
          'receivedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// Reserviert die naechste fortlaufende Bestellnummer ueber einen
  /// Zaehler in einer Transaktion (garantiert eindeutig pro Organisation).
  Future<String> _allocateOrderNumber(String orgId) async {
    final counterRef =
        _organizationDoc(orgId).collection('counters').doc('purchaseOrders');
    final now = DateTime.now();
    try {
      final seq = await _firestore.runTransaction<int>((transaction) async {
        final snapshot = await transaction.get(counterRef);
        final current = (snapshot.data()?['seq'] as num?)?.toInt() ?? 0;
        final next = current + 1;
        transaction.set(counterRef, {
          'seq': next,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return next;
      });
      return 'BST-${now.year}-${seq.toString().padLeft(4, '0')}';
    } catch (_) {
      // Fallback ohne Zaehler (z.B. eingeschraenkte Rechte): zeitbasiert.
      final stamp =
          '${now.year}${_two(now.month)}${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}';
      return 'BST-$stamp';
    }
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
