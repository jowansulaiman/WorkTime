import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/purchase_order.dart';
import 'package:worktime_app/models/stock_movement.dart';
import 'package:worktime_app/repositories/firestore_inventory_repository.dart';

/// Firestore-Fake, dessen Zaehler-Transaktion dauerhaft scheitert
/// (z.B. eingeschraenkte Rechte). Triggert den Fallback in
/// _allocateOrderNumber.
class _CounterDownFirestore extends FakeFirebaseFirestore {
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Zaehler gesperrt',
    );
  }
}

void main() {
  const orgId = 'org-1';

  test(
    'Bestellnummer-Fallback ist kollisionsfest, wenn der Zaehler scheitert',
    () async {
      final firestore = _CounterDownFirestore();
      final repo = FirestoreInventoryRepository(
        firestore: firestore,
        uuid: const Uuid(),
      );

      Future<void> create(String item) => repo.savePurchaseOrder(
            PurchaseOrder(
              orgId: orgId,
              siteId: 'site-1',
              supplierId: 'sup-1',
              items: [PurchaseOrderItem(name: item, quantityOrdered: 1)],
            ),
          );

      await create('A');
      await create('B');

      final orders = await repo.watchPurchaseOrders(orgId).first;
      final numbers =
          orders.map((o) => o.orderNumber).whereType<String>().toList();

      expect(numbers.length, 2);
      final pattern = RegExp(r'^BST-\d{8}-\d{4}-[0-9A-F]{4}$');
      for (final number in numbers) {
        expect(pattern.hasMatch(number), isTrue,
            reason: 'Fallback-Format mit UUID-Suffix: $number');
      }
      expect(numbers[0], isNot(numbers[1]),
          reason: 'UUID-Suffix verhindert Kollision in derselben Minute');
    },
  );

  test(
    'saveProduct lässt fridgeStock unangetastet (Clobber-Schutz)',
    () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreInventoryRepository(
        firestore: firestore,
        uuid: const Uuid(),
      );
      final products = firestore
          .collection('organizations')
          .doc(orgId)
          .collection('products');

      // Server-Stand: der Kühlschrank wurde befüllt (fridgeStock=10).
      await products.doc('prod-1').set({
        'orgId': orgId,
        'siteId': 'site-1',
        'name': 'Cola',
        'currentStock': 30,
        'inFridge': true,
        'fridgeTargetStock': 24,
        'fridgeStock': 10,
      });

      // Manager editiert den Artikel mit einem STALE fridgeStock (0).
      await repo.saveProduct(const Product(
        id: 'prod-1',
        orgId: orgId,
        siteId: 'site-1',
        name: 'Cola neu',
        currentStock: 30,
        inFridge: true,
        fridgeTargetStock: 24,
        fridgeStock: 0,
      ));

      final snap = await products.doc('prod-1').get();
      final restored = Product.fromFirestore(snap.id, snap.data()!);
      expect(restored.name, 'Cola neu'); // andere Felder werden geschrieben
      expect(restored.fridgeStock, 10); // fridgeStock NICHT überschrieben
    },
  );

  test(
    'setFridgeStock setzt fridgeStock, lässt currentStock + bucht fridgeRefill',
    () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreInventoryRepository(
        firestore: firestore,
        uuid: const Uuid(),
      );
      final org =
          firestore.collection('organizations').doc(orgId);
      await org.collection('products').doc('cola').set({
        'orgId': orgId,
        'siteId': 'site-1',
        'name': 'Cola',
        'currentStock': 30,
        'inFridge': true,
        'fridgeTargetStock': 24,
        'fridgeStock': 8,
      });

      await repo.setFridgeStock(
        orgId: orgId,
        productId: 'cola',
        fridgeStock: 24,
        refilledQty: 16,
      );

      final snap = await org.collection('products').doc('cola').get();
      final p = Product.fromFirestore(snap.id, snap.data()!);
      expect(p.fridgeStock, 24);
      expect(p.currentStock, 30); // UNVERÄNDERT (reine Umlagerung)

      final moves = await org.collection('stockMovements').get();
      expect(moves.docs, hasLength(1));
      final m = StockMovement.fromFirestore(
        moves.docs.first.id,
        moves.docs.first.data(),
      );
      expect(m.type, StockMovementType.fridgeRefill);
      expect(m.quantityDelta, 16);
      expect(m.balanceAfter, 24);
    },
  );
}
