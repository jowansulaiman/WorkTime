import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../core/app_logger.dart';
import '../core/error_reporter.dart';
import '../core/retry.dart';
import '../models/cash_closing.dart';
import '../models/cash_count.dart';
import '../models/customer_order.dart';
import '../models/delivery_advice.dart';
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
import 'inventory_repository.dart';

/// Firestore-Implementierung der [InventoryRepository] — die einzige Stelle mit
/// Warenwirtschafts-Datenzugriffslogik (zuvor im FirestoreService-God-Object,
/// firestore-service-god-object). Reiner Cloud-Datenzugriff; die
/// Speicherstrategie (cloud/hybrid/local) liegt weiterhin im Provider.
class FirestoreInventoryRepository implements InventoryRepository {
  FirestoreInventoryRepository({
    required FirebaseFirestore firestore,
    Uuid? uuid,
  })  : _firestore = firestore,
        _uuid = uuid ?? const Uuid();

  final FirebaseFirestore _firestore;
  final Uuid _uuid;

  DocumentReference<Map<String, dynamic>> _organizationDoc(String orgId) =>
      _firestore.collection('organizations').doc(orgId);

  CollectionReference<Map<String, dynamic>> _supplierCollection(String orgId) =>
      _organizationDoc(orgId).collection('suppliers');

  CollectionReference<Map<String, dynamic>> _productCollection(String orgId) =>
      _organizationDoc(orgId).collection('products');

  CollectionReference<Map<String, dynamic>> _productBatchCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('productBatches');

  CollectionReference<Map<String, dynamic>> _purchaseOrderCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('purchaseOrders');

  CollectionReference<Map<String, dynamic>> _stockMovementCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('stockMovements');

  CollectionReference<Map<String, dynamic>> _posReceiptCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('posReceipts');

  CollectionReference<Map<String, dynamic>> _scanEventCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('scanEvents');

  CollectionReference<Map<String, dynamic>> _deliveryAdviceCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('deliveryAdvices');

  CollectionReference<Map<String, dynamic>> _customerOrderCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('customerOrders');

  CollectionReference<Map<String, dynamic>> _orderCartCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('orderCarts');

  CollectionReference<Map<String, dynamic>> _weeklyOrderListCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('weeklyOrderLists');

  CollectionReference<Map<String, dynamic>> _fridgeRefillListCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('fridgeRefillLists');

  /// Ziel-Collection einer Bestellliste je [kind] (Korb vs. Standard-Liste).
  CollectionReference<Map<String, dynamic>> _orderListCollection(
    String orgId,
    OrderListKind kind,
  ) =>
      kind == OrderListKind.weeklyTemplate
          ? _weeklyOrderListCollection(orgId)
          : _orderCartCollection(orgId);

  // Bewusste Entscheidung (missing-orderby-updatedat-index-delta / full-read-no-
  // delta-sync): Lieferanten/Artikel werden als vollstaendiger, nach nameLower
  // sortierter Stream gelesen – kein where('updatedAt', isGreaterThan: cursor).
  // Firestore-snapshots() ziehen nach dem ersten Snapshot ohnehin nur DocChanges
  // (Deltas) aus dem lokalen Cache; ein echter updatedAt-Cursor + Index lohnt erst
  // bei deutlich groesseren Bestaenden als den zwei Laeden. Bis dahin nicht
  // ueberdimensionieren.
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
    String? siteId,
    int limit = 100,
  }) {
    Query<Map<String, dynamic>> query = _stockMovementCollection(orgId);
    // productId hat Vorrang (eigener (productId, createdAt)-Index); sonst optional
    // standortgescopt ueber den (siteId, createdAt)-Composite-Index. Beide bedienen
    // orderBy('createdAt') serverseitig statt clientseitig zu filtern.
    if (productId != null && productId.isNotEmpty) {
      query = query.where('productId', isEqualTo: productId);
    } else if (siteId != null && siteId.isNotEmpty) {
      query = query.where('siteId', isEqualTo: siteId);
    }
    query = query.orderBy('createdAt', descending: true).limit(limit);
    return query.snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => StockMovement.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Future<List<StockMovement>> getStockMovementsInRange(
    String orgId,
    DateTime from,
    DateTime to, {
    String? siteId,
  }) async {
    Query<Map<String, dynamic>> query = _stockMovementCollection(orgId);
    // siteId-Gleichheit + createdAt-Range bedient der vorhandene
    // (siteId, createdAt)-Composite-Index; ohne siteId genuegt der
    // automatische Single-Field-Index auf createdAt.
    if (siteId != null && siteId.isNotEmpty) {
      query = query.where('siteId', isEqualTo: siteId);
    }
    final snapshot = await query
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(to))
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => StockMovement.fromFirestore(doc.id, doc.data()))
        .toList(growable: false);
  }

  @override
  Future<List<PosReceipt>> getPosReceiptsInRange(
    String orgId,
    DateTime from,
    DateTime to, {
    String? siteId,
  }) async {
    Query<Map<String, dynamic>> query = _posReceiptCollection(orgId);
    // siteId-Gleichheit + transactionDate-Range bedient den
    // (siteId, transactionDate)-Composite-Index; ohne siteId genügt der
    // automatische Single-Field-Index auf transactionDate.
    if (siteId != null && siteId.isNotEmpty) {
      query = query.where('siteId', isEqualTo: siteId);
    }
    final snapshot = await query
        .where('transactionDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('transactionDate', isLessThanOrEqualTo: Timestamp.fromDate(to))
        .orderBy('transactionDate', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => PosReceipt.fromFirestore(doc.id, doc.data()))
        .toList(growable: false);
  }

  // --- Kassen-Modul: Zählungen / Abschlüsse / Tagesaggregate --------------

  CollectionReference<Map<String, dynamic>> _cashCountCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('cashCounts');

  CollectionReference<Map<String, dynamic>> _cashClosingCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('cashClosings');

  CollectionReference<Map<String, dynamic>> _posDailyStatCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('posDailyStats');

  @override
  Future<List<CashCount>> getCashCountsInRange(
    String orgId,
    DateTime from,
    DateTime to, {
    String? siteId,
  }) async {
    Query<Map<String, dynamic>> query = _cashCountCollection(orgId);
    // siteId-Gleichheit + countedAt-Range bedient der (siteId, countedAt)-
    // Composite-Index; ohne siteId genügt der Single-Field-Index.
    if (siteId != null && siteId.isNotEmpty) {
      query = query.where('siteId', isEqualTo: siteId);
    }
    final snapshot = await query
        .where('countedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('countedAt', isLessThanOrEqualTo: Timestamp.fromDate(to))
        .orderBy('countedAt', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => CashCount.fromFirestore(doc.id, doc.data()))
        .toList(growable: false);
  }

  @override
  Future<void> addCashCount(CashCount count) async {
    // create-only mit Auto-ID: Zählungen sind unveränderlich (Audit-Charakter).
    await _cashCountCollection(count.orgId).doc().set(count.toFirestoreMap());
  }

  @override
  Future<List<CashClosing>> getCashClosingsInRange(
    String orgId,
    String fromDay,
    String toDay, {
    String? siteId,
  }) async {
    Query<Map<String, dynamic>> query = _cashClosingCollection(orgId);
    // siteId-Gleichheit + businessDay-Range bedient der (siteId, businessDay)-
    // Composite-Index; ISO-Datumsstrings ordnen lexikographisch korrekt.
    if (siteId != null && siteId.isNotEmpty) {
      query = query.where('siteId', isEqualTo: siteId);
    }
    final snapshot = await query
        .where('businessDay', isGreaterThanOrEqualTo: fromDay)
        .where('businessDay', isLessThanOrEqualTo: toDay)
        .orderBy('businessDay', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => CashClosing.fromFirestore(doc.id, doc.data()))
        .toList(growable: false);
  }

  @override
  Future<void> createCashClosing(CashClosing closing) async {
    final docRef = _cashClosingCollection(closing.orgId)
        .doc(CashClosing.docId(closing.businessDay, closing.siteId));
    // create-only über Transaktion (der Client-SDK-Weg für „nur wenn es das
    // Doc noch nicht gibt") — Festschreibung darf nie still überschreiben.
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(docRef);
      if (existing.exists) {
        throw StateError('Dieser Tag ist bereits abgeschlossen.');
      }
      transaction.set(docRef, closing.toFirestoreMap());
    });
  }

  @override
  Future<void> markCashClosingBooked({
    required String orgId,
    required String closingId,
  }) {
    // Einzige erlaubte Mutation eines festgeschriebenen Abschlusses (§3.2);
    // die Rules erzwingen den Feld-Diff auf genau `bookedToFinance`.
    return _cashClosingCollection(orgId)
        .doc(closingId)
        .update({'bookedToFinance': true});
  }

  @override
  Future<List<PosDailyStat>> getPosDailyStatsInRange(
    String orgId,
    String fromDay,
    String toDay, {
    String? siteId,
  }) async {
    Query<Map<String, dynamic>> query = _posDailyStatCollection(orgId);
    // siteId-Gleichheit + businessDay-Range bedient der (siteId, businessDay)-
    // Composite-Index; ohne siteId genügt der Single-Field-Index.
    if (siteId != null && siteId.isNotEmpty) {
      query = query.where('siteId', isEqualTo: siteId);
    }
    final snapshot = await query
        .where('businessDay', isGreaterThanOrEqualTo: fromDay)
        .where('businessDay', isLessThanOrEqualTo: toDay)
        .orderBy('businessDay', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => PosDailyStat.fromFirestore(doc.id, doc.data()))
        .toList(growable: false);
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
  Future<String> saveProduct(Product product) async {
    final collection = _productCollection(product.orgId);
    final docRef =
        product.id == null ? collection.doc() : collection.doc(product.id);
    // Clobber-Schutz: fridgeStock wird NIE über saveProduct geschrieben (allein
    // setFridgeStock/Refill + POS-Increment sind autoritativ) — sonst überschriebe
    // ein Manager-Edit den serverseitig dekrementierten Wert (Plan §7).
    final data = {
      ...product.copyWith(id: docRef.id).toFirestoreMap(),
      if (product.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }..remove('fridgeStock');
    // H8 (Sicherheits-Audit 2026-07): currentStock unterliegt denselben
    // nebenlaeufigen Buchungen (adjustProductStock/receive/POS-Pull) — ein
    // Manager-Edit mit eingefrorenem UI-Stand darf den Serverwert nicht
    // zuruecksetzen. Kriterium ist die DOC-Existenz (nicht die id), damit
    // syncLocalStateToCloud (lokale Artikel MIT id, noch ohne Cloud-Doc) den
    // Anfangsbestand weiterhin mitbringt.
    if (product.id != null && (await docRef.get()).exists) {
      data.remove('currentStock');
    }
    await docRef.set(data, SetOptions(merge: true));
    return docRef.id;
  }

  @override
  Future<void> deleteProduct({
    required String orgId,
    required String productId,
  }) {
    return _productCollection(orgId).doc(productId).delete();
  }

  // --- MHD-/Ablauf-Chargen ------------------------------------------------
  // Voller `orderBy(expiryDay)`-Stream (Single-Field, auto-indiziert). Auch
  // aufgeloeste (abverkauft/entsorgt) Chargen werden mitgestreamt und bleiben
  // zur Historie erhalten; die Warnung filtert clientseitig auf `active`.

  @override
  Stream<List<ProductBatch>> watchProductBatches(String orgId) {
    return _productBatchCollection(orgId).orderBy('expiryDay').snapshots().map(
      (snapshot) {
        final batches = <ProductBatch>[];
        for (final doc in snapshot.docs) {
          try {
            batches.add(ProductBatch.fromFirestore(doc.id, doc.data()));
          } on FormatException catch (error) {
            // M6: Charge ohne lesbares MHD ueberspringen statt (frueher) als
            // 2000-01-01 zu fuehren — das erzeugte Dauer-Falschwarnungen.
            AppLogger.warning(
              'ProductBatch uebersprungen (kein lesbares MHD)',
              error: error,
              fields: {'doc': doc.id},
            );
          }
        }
        return List<ProductBatch>.unmodifiable(batches);
      },
    );
  }

  @override
  Future<void> saveProductBatch(ProductBatch batch) async {
    final collection = _productBatchCollection(batch.orgId);
    final docRef =
        batch.id == null ? collection.doc() : collection.doc(batch.id);
    await docRef.set({
      ...batch.copyWith(id: docRef.id).toFirestoreMap(),
      if (batch.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteProductBatch({
    required String orgId,
    required String batchId,
  }) {
    return _productBatchCollection(orgId).doc(batchId).delete();
  }

  CollectionReference<Map<String, dynamic>> _priceHistoryCollection(
    String orgId,
    String productId,
  ) =>
      _productCollection(orgId).doc(productId).collection('priceHistory');

  @override
  Future<void> addPriceHistory(PriceHistoryEntry entry) {
    return _priceHistoryCollection(entry.orgId, entry.productId)
        .add(entry.toFirestoreMap());
  }

  @override
  Future<List<PriceHistoryEntry>> fetchPriceHistory({
    required String orgId,
    required String productId,
  }) async {
    final snapshot = await _priceHistoryCollection(orgId, productId)
        .orderBy('changedAt', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => PriceHistoryEntry.fromFirestore(doc.id, doc.data()))
        .toList(growable: false);
  }

  @override
  Future<void> addScanEvent(ScanEvent event) {
    return _scanEventCollection(event.orgId).add(event.toFirestoreMap());
  }

  @override
  Future<List<ScanEvent>> fetchScanEvents(String orgId, {int limit = 500}) async {
    final snapshot = await _scanEventCollection(orgId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((doc) => ScanEvent.fromFirestore(doc.id, doc.data()))
        .toList(growable: false);
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
  Future<int> setProductStock({
    required String orgId,
    required String productId,
    required int newStock,
    StockMovementType type = StockMovementType.stocktake,
    String? reason,
    String? createdByUid,
    String? clientMutationId,
  }) async {
    final productRef = _productCollection(orgId).doc(productId);
    final movementRef = clientMutationId == null
        ? _stockMovementCollection(orgId).doc()
        : _stockMovementCollection(orgId).doc(clientMutationId);

    // H9 (Sicherheits-Audit 2026-07, Inventur): ABSOLUT setzen statt ein im
    // Provider aus potenziell veraltetem UI-Stand berechnetes Delta zu
    // addieren — das Delta wird IN der Transaktion aus dem frischen
    // Serverstand abgeleitet, damit die Inventur immer auf dem gezaehlten
    // Wert landet (UI 10 / Server 9 / gezaehlt 7 -> 7, nicht 6).
    return _firestore.runTransaction<int>((transaction) async {
      final snapshot = await transaction.get(productRef);
      if (!snapshot.exists) {
        throw StateError('Artikel wurde nicht gefunden.');
      }
      final product = Product.fromFirestore(snapshot.id, snapshot.data()!);

      if (clientMutationId != null) {
        final existing = await transaction.get(movementRef);
        if (existing.exists) {
          return product.currentStock;
        }
      }

      final delta = newStock - product.currentStock;
      if (delta == 0) {
        return product.currentStock;
      }

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
          createdByUid: createdByUid,
        ).toFirestoreMap(),
      });

      return newStock;
    });
  }

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
  }) async {
    if (quantity <= 0) {
      throw StateError('Menge muss groesser als 0 sein.');
    }
    final fromRef = _productCollection(orgId).doc(fromProductId);
    final toRef = _productCollection(orgId).doc(toProductId);
    final movements = _stockMovementCollection(orgId);
    final outRef = clientMutationId == null
        ? movements.doc()
        : movements.doc('$clientMutationId-out');
    final inRef = clientMutationId == null
        ? movements.doc()
        : movements.doc('$clientMutationId-in');

    // H10 (Sicherheits-Audit 2026-07/GB): Abgang, Zugang und beide
    // Bewegungs-Docs in EINER Transaktion — vorher waren es zwei getrennte
    // Buchungen mit best-effort-Kompensation, bei der Bestand verschwinden
    // konnte, wenn die Ziel-Buchung scheiterte.
    await _firestore.runTransaction<void>((transaction) async {
      final fromSnap = await transaction.get(fromRef);
      final toSnap = await transaction.get(toRef);
      if (!fromSnap.exists || !toSnap.exists) {
        throw StateError('Artikel wurde nicht gefunden.');
      }
      if (clientMutationId != null) {
        final existing = await transaction.get(outRef);
        if (existing.exists) {
          return;
        }
      }
      final fromProduct = Product.fromFirestore(fromSnap.id, fromSnap.data()!);
      final toProduct = Product.fromFirestore(toSnap.id, toSnap.data()!);
      if (fromProduct.currentStock < quantity) {
        throw StateError(
          'Menge ($quantity) uebersteigt den Bestand der Quelle '
          '(${fromProduct.currentStock}).',
        );
      }
      final fromStock = fromProduct.currentStock - quantity;
      final toStock = toProduct.currentStock + quantity;

      transaction.set(fromRef, {
        'currentStock': fromStock,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      transaction.set(toRef, {
        'currentStock': toStock,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      transaction.set(outRef, {
        ...StockMovement(
          orgId: orgId,
          siteId: fromProduct.siteId,
          productId: fromProductId,
          productName: fromProduct.name,
          type: StockMovementType.transfer,
          quantityDelta: -quantity,
          balanceAfter: fromStock,
          reason: fromReason,
          createdByUid: createdByUid,
        ).toFirestoreMap(),
      });
      transaction.set(inRef, {
        ...StockMovement(
          orgId: orgId,
          siteId: toProduct.siteId,
          productId: toProductId,
          productName: toProduct.name,
          type: StockMovementType.transfer,
          quantityDelta: quantity,
          balanceAfter: toStock,
          reason: toReason,
          createdByUid: createdByUid,
        ).toFirestoreMap(),
      });
    });
  }

  @override
  Future<void> setFridgeStock({
    required String orgId,
    required String productId,
    required int fridgeStock,
    required int refilledQty,
    String? createdByUid,
    String? clientMutationId,
  }) async {
    final productRef = _productCollection(orgId).doc(productId);
    final movementRef = clientMutationId == null
        ? _stockMovementCollection(orgId).doc()
        : _stockMovementCollection(orgId).doc(clientMutationId);

    // Kein Read-Modify-Write nötig (fridgeStock ist ein ABSOLUTwert, vom Aufrufer
    // berechnet) → ein atomarer Batch statt einer Transaktion. Wir lesen das
    // Produkt nur für Standort/Name der Bewegung und die Idempotenz-Prüfung.
    final snapshot = await productRef.get();
    if (!snapshot.exists) {
      throw StateError('Artikel wurde nicht gefunden.');
    }
    final product = Product.fromFirestore(snapshot.id, snapshot.data()!);

    if (clientMutationId != null) {
      final existing = await movementRef.get();
      if (existing.exists) {
        return; // Buchung wurde bereits angewendet (Retry) — no-op.
      }
    }

    final batch = _firestore.batch();
    // NUR fridgeStock + updatedAt — currentStock bleibt unberührt (das Nachfüllen
    // verschiebt Ware nur Lager→Kühlschrank, kein Gesamt-Abgang).
    batch.set(productRef, {
      'fridgeStock': fridgeStock,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(movementRef, {
      ...StockMovement(
        orgId: orgId,
        siteId: product.siteId,
        productId: productId,
        productName: product.name,
        type: StockMovementType.fridgeRefill,
        quantityDelta: refilledQty,
        balanceAfter: fridgeStock,
        reason: 'Kühlschrank nachgefüllt',
        createdByUid: createdByUid,
      ).toFirestoreMap(),
    });
    await batch.commit();
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
  Future<PurchaseOrder> closePurchaseOrderRemainder({
    required String orgId,
    required String orderId,
    required String reason,
  }) async {
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw StateError('Bitte geben Sie eine Begründung für den Abschluss an.');
    }

    final orderRef = _purchaseOrderCollection(orgId).doc(orderId);
    return _firestore.runTransaction<PurchaseOrder>((transaction) async {
      final orderSnap = await transaction.get(orderRef);
      if (!orderSnap.exists) {
        throw StateError('Bestellung wurde nicht gefunden.');
      }
      final order = PurchaseOrder.fromFirestore(orderSnap.id, orderSnap.data()!);
      if (order.closedAt != null) {
        throw StateError('Diese Bestellung wurde bereits geschlossen.');
      }
      if (order.status != PurchaseOrderStatus.ordered &&
          order.status != PurchaseOrderStatus.partiallyReceived) {
        throw StateError('Nur offene Bestellungen können geschlossen werden.');
      }
      if (!order.hasAnyReceipt) {
        throw StateError(
          'Die Bestellung kann erst nach einem Wareneingang geschlossen werden.',
        );
      }

      transaction.update(orderRef, {
        'status': PurchaseOrderStatus.received.value,
        'closedAt': FieldValue.serverTimestamp(),
        'closedReason': normalizedReason,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return order.copyWith(
        status: PurchaseOrderStatus.received,
        closedAt: DateTime.now(),
        closedReason: normalizedReason,
      );
    });
  }

  // --- Lieferavise (deliveryAdvices, WW-4) --------------------------------
  // Komplette Org-Collection als Stream, nach erwartetem Tag sortiert
  // (Single-Field `expectedDay`, auto-indiziert). Filter (Status/Standort/Tag)
  // laufen clientseitig im Provider — KEIN Composite-Index. `expectedDate` ist
  // load-bearing (wie `ProductBatch.expiryDate`): Datensaetze ohne lesbares
  // Datum werden protokolliert uebersprungen statt still verfaelscht.
  @override
  Stream<List<DeliveryAdvice>> watchDeliveryAdvices(String orgId) {
    return _deliveryAdviceCollection(orgId).orderBy('expectedDay').snapshots().map(
      (snapshot) {
        final advices = <DeliveryAdvice>[];
        for (final doc in snapshot.docs) {
          try {
            advices.add(DeliveryAdvice.fromFirestore(doc.id, doc.data()));
          } on FormatException catch (error) {
            AppLogger.warning(
              'DeliveryAdvice uebersprungen (kein lesbarer Liefertermin)',
              error: error,
              fields: {'doc': doc.id},
            );
          }
        }
        return List<DeliveryAdvice>.unmodifiable(advices);
      },
    );
  }

  @override
  Future<void> saveDeliveryAdvice(DeliveryAdvice advice) async {
    final collection = _deliveryAdviceCollection(advice.orgId);
    final docRef =
        advice.id == null ? collection.doc() : collection.doc(advice.id);
    await docRef.set({
      ...advice.copyWith(id: docRef.id).toFirestoreMap(),
      if (advice.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteDeliveryAdvice({
    required String orgId,
    required String adviceId,
  }) {
    return _deliveryAdviceCollection(orgId).doc(adviceId).delete();
  }

  // Kundenbestellungen werden – wie Lieferantenbestellungen – nach createdAt
  // gelesen (immer gesetzt via serverTimestamp). Ein orderBy('pickupDate')
  // wuerde Bestellungen ohne Abholtermin verlieren; die Sortierung nach Termin
  // und das "bald faellig"-Filtern laufen clientseitig im Provider.
  @override
  Stream<List<CustomerOrder>> watchCustomerOrders(String orgId) {
    return _customerOrderCollection(orgId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => CustomerOrder.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Future<String> saveCustomerOrder(CustomerOrder order) async {
    final collection = _customerOrderCollection(order.orgId);
    final docRef =
        order.id == null ? collection.doc() : collection.doc(order.id);
    var prepared = order.copyWith(id: docRef.id);
    if (order.id == null && order.orderNumber == null) {
      prepared = prepared.copyWith(
        orderNumber: await _allocateOrderNumber(
          order.orgId,
          counterId: 'customerOrders',
          prefix: 'KB',
        ),
      );
    }
    await docRef.set({
      ...prepared.toFirestoreMap(),
      if (order.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return docRef.id;
  }

  @override
  Future<void> deleteCustomerOrder({
    required String orgId,
    required String orderId,
  }) {
    return _customerOrderCollection(orgId).doc(orderId).delete();
  }

  // --- Bestelllisten (Wochen-Bestellkorb + Standard-Wochenliste) ---------
  // Singleton je Laden: Doc-ID = siteId, kein orderBy nötig (Collection klein).
  // updatedByUid/updatedAt sind die einzigen Metadaten; gelesen wird der ganze
  // (Mini-)Stream wie bei den anderen Warenwirtschafts-Listen.

  @override
  Stream<List<SiteOrderList>> watchOrderCarts(String orgId) {
    return _orderCartCollection(orgId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => SiteOrderList.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Stream<List<SiteOrderList>> watchWeeklyOrderLists(String orgId) {
    return _weeklyOrderListCollection(orgId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => SiteOrderList.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Future<void> saveOrderList(SiteOrderList list) {
    // Leeres siteId wuerde .doc('') aufrufen -> Firestore-ArgumentError. Frueh
    // mit klarer deutscher Meldung abbrechen (probleme #47).
    if (list.siteId.trim().isEmpty) {
      throw StateError(
        'Bestellliste kann nicht gespeichert werden: Dem Artikel fehlt eine '
        'Standortzuordnung.',
      );
    }
    // Doc-ID = siteId -> idempotenter Upsert je Laden (keine Duplikate möglich).
    return _orderListCollection(list.orgId, list.kind)
        .doc(list.siteId)
        .set(list.toFirestoreMap(), SetOptions(merge: true));
  }

  @override
  Future<void> deleteOrderList({
    required String orgId,
    required String siteId,
    required OrderListKind kind,
  }) {
    if (siteId.trim().isEmpty) {
      throw StateError(
        'Bestellliste kann nicht geloescht werden: Standort fehlt.',
      );
    }
    return _orderListCollection(orgId, kind).doc(siteId).delete();
  }

  // --- Kühlschrank-Nachfüllliste -----------------------------------------
  // Singleton je Laden (Doc-ID = siteId), kein orderBy/Index – wie die
  // Bestelllisten (eine Liste je Laden).

  @override
  Stream<List<FridgeRefillList>> watchFridgeRefillLists(String orgId) {
    return _fridgeRefillListCollection(orgId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => FridgeRefillList.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Future<void> saveFridgeRefillList(FridgeRefillList list) {
    // Leeres siteId wuerde .doc('') aufrufen -> Firestore-ArgumentError.
    if (list.siteId.trim().isEmpty) {
      throw StateError(
        'Nachfüllliste kann nicht gespeichert werden: Dem Artikel fehlt eine '
        'Standortzuordnung.',
      );
    }
    // Doc-ID = siteId -> idempotenter Upsert je Laden (keine Duplikate möglich).
    return _fridgeRefillListCollection(list.orgId)
        .doc(list.siteId)
        .set(list.toFirestoreMap(), SetOptions(merge: true));
  }

  @override
  Future<void> deleteFridgeRefillList({
    required String orgId,
    required String siteId,
  }) {
    if (siteId.trim().isEmpty) {
      throw StateError(
        'Nachfüllliste kann nicht gelöscht werden: Standort fehlt.',
      );
    }
    return _fridgeRefillListCollection(orgId).doc(siteId).delete();
  }

  @override
  Future<void> receivePurchaseOrder({
    required String orgId,
    required String orderId,
    required Map<int, PurchaseReceiptLine> receivedByItemIndex,
    String? deliveryNoteNumber,
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
      if (order.closedAt != null) {
        throw StateError(
          'Diese Bestellung ist geschlossen. Weitere Wareneingänge sind nicht möglich.',
        );
      }

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
        final qty = entry.value.quantity.clamp(0, item.outstandingQuantity);
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

      // Gelieferte Mengen + Ist-EK (WW-6) in den Positionen fortschreiben.
      final updatedItems = <PurchaseOrderItem>[];
      for (var i = 0; i < order.items.length; i++) {
        final item = order.items[i];
        final add = effective[i] ?? 0;
        if (add > 0) {
          // Ist-EK nur setzen, wenn erfasst — sonst bleibt der bestellte Preis.
          updatedItems.add(item.copyWith(
            quantityReceived: item.quantityReceived + add,
            receivedUnitPriceCents: receivedByItemIndex[i]?.receivedUnitPriceCents,
          ));
        } else {
          updatedItems.add(item);
        }
      }

      final updatedOrder = order.copyWith(items: updatedItems);
      final newStatus = updatedOrder.deriveReceiptStatus();
      final trimmedNote = deliveryNoteNumber?.trim();

      transaction.set(orderRef, {
        'items': updatedItems.map((item) => item.toFirestoreMap()).toList(),
        'status': newStatus.value,
        if (trimmedNote != null && trimmedNote.isNotEmpty)
          'deliveryNoteNumber': trimmedNote,
        if (newStatus == PurchaseOrderStatus.received)
          'receivedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// Reserviert die naechste fortlaufende Bestellnummer ueber einen
  /// Zaehler in einer Transaktion (garantiert eindeutig pro Organisation).
  /// [counterId] waehlt den Zaehler-Dokument-Schluessel, [prefix] das Praefix
  /// der Nummer (Lieferantenbestellung: BST, Kundenbestellung: KB).
  Future<String> _allocateOrderNumber(
    String orgId, {
    String counterId = 'purchaseOrders',
    String prefix = 'BST',
  }) async {
    final counterRef =
        _organizationDoc(orgId).collection('counters').doc(counterId);
    final now = DateTime.now();
    try {
      // Die Zaehler-Transaktion ist atomar und idempotent (committet
      // entweder ganz oder gar nicht) -> transiente Fehler duerfen mit
      // Backoff wiederholt werden, ohne den Zaehler doppelt zu erhoehen.
      final seq = await retryTransient(
        () => _firestore.runTransaction<int>((transaction) async {
          final snapshot = await transaction.get(counterRef);
          final current = (snapshot.data()?['seq'] as num?)?.toInt() ?? 0;
          final next = current + 1;
          transaction.set(counterRef, {
            'seq': next,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          return next;
        }),
      );
      return '$prefix-${now.year}-${seq.toString().padLeft(4, '0')}';
    } catch (error, stack) {
      // Zaehler dauerhaft nicht verfuegbar (z.B. eingeschraenkte Rechte oder
      // anhaltend transienter Fehler). Statt den Fehler still zu schlucken
      // melden wir ihn und vergeben eine zeitbasierte Nummer MIT UUID-Suffix,
      // damit parallele Bestellungen in derselben Minute nicht kollidieren.
      ErrorReporter.report(
        error,
        stack,
        context: 'Bestellnummern-Zaehler nicht verfuegbar, Fallback aktiv',
      );
      final stamp =
          '${now.year}${_two(now.month)}${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}';
      final suffix = _uuid.v4().substring(0, 4).toUpperCase();
      return '$prefix-$stamp-$suffix';
    }
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
