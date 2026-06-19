import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:worktime_app/models/purchase_order.dart';
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
}
