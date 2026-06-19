import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/purchase_order.dart';
import 'package:worktime_app/models/stock_movement.dart';
import 'package:worktime_app/models/supplier.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  group('FirestoreService – Warenwirtschaft', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreService service;
    const orgId = 'org-1';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = FirestoreService(firestore: firestore);
    });

    Future<String> seedProduct({
      required String name,
      int currentStock = 0,
      int minStock = 0,
      String? supplierId,
      int? purchasePriceCents,
    }) async {
      final collection = firestore
          .collection('organizations')
          .doc(orgId)
          .collection('products');
      final ref = collection.doc();
      await ref.set(
        Product(
          orgId: orgId,
          siteId: 'site-1',
          name: name,
          currentStock: currentStock,
          minStock: minStock,
          supplierId: supplierId,
          purchasePriceCents: purchasePriceCents,
        ).copyWith(id: ref.id).toFirestoreMap(),
      );
      return ref.id;
    }

    test('saveSupplier persists and watchSuppliers emits it', () async {
      await service.saveSupplier(
        const Supplier(orgId: orgId, name: 'Nord Grosshandel'),
      );

      final suppliers = await service.watchSuppliers(orgId).first;
      expect(suppliers, hasLength(1));
      expect(suppliers.first.name, 'Nord Grosshandel');
      expect(suppliers.first.id, isNotNull);
    });

    test('adjustProductStock updates stock and writes a movement', () async {
      final productId = await seedProduct(name: 'Feuerzeug', currentStock: 10);

      final newStock = await service.adjustProductStock(
        orgId: orgId,
        productId: productId,
        delta: -3,
        type: StockMovementType.adjustment,
        reason: 'Schwund',
      );

      expect(newStock, 7);

      final product = await firestore
          .collection('organizations')
          .doc(orgId)
          .collection('products')
          .doc(productId)
          .get();
      expect(product.data()!['currentStock'], 7);

      final movements = await service.watchStockMovements(orgId).first;
      expect(movements, hasLength(1));
      expect(movements.first.quantityDelta, -3);
      expect(movements.first.balanceAfter, 7);
      expect(movements.first.type, StockMovementType.adjustment);
    });

    test('savePurchaseOrder allocates a sequential order number', () async {
      final first = await service.savePurchaseOrder(
        const PurchaseOrder(
          orgId: orgId,
          siteId: 'site-1',
          supplierId: 'sup-1',
          items: [
            PurchaseOrderItem(name: 'Feuerzeug', quantityOrdered: 10),
          ],
        ),
      );
      final second = await service.savePurchaseOrder(
        const PurchaseOrder(
          orgId: orgId,
          siteId: 'site-1',
          supplierId: 'sup-1',
          items: [
            PurchaseOrderItem(name: 'Zeitschrift', quantityOrdered: 5),
          ],
        ),
      );

      final orders = await service.watchPurchaseOrders(orgId).first;
      final numbers = orders.map((o) => o.orderNumber).toList();
      expect(first, isNot(second));
      expect(numbers.any((n) => n?.endsWith('0001') ?? false), isTrue);
      expect(numbers.any((n) => n?.endsWith('0002') ?? false), isTrue);
    });

    test('savePurchaseOrder vergibt monoton steigende, eindeutige Nummern',
        () async {
      for (var i = 0; i < 3; i++) {
        await service.savePurchaseOrder(
          PurchaseOrder(
            orgId: orgId,
            siteId: 'site-1',
            supplierId: 'sup-1',
            items: [
              PurchaseOrderItem(name: 'Artikel $i', quantityOrdered: 1),
            ],
          ),
        );
      }

      final orders = await service.watchPurchaseOrders(orgId).first;
      final suffixes = orders
          .map((o) => o.orderNumber)
          .whereType<String>()
          .map((n) => n.split('-').last)
          .toList()
        ..sort();
      expect(suffixes.toSet().length, suffixes.length,
          reason: 'Nummern sind paarweise verschieden');
      expect(suffixes, ['0001', '0002', '0003'],
          reason: 'Sequenz ist monoton ab 0001');
    });

    test('receivePurchaseOrder books a partial then full delivery', () async {
      final productId =
          await seedProduct(name: 'Feuerzeug', currentStock: 5, minStock: 10);

      final orderId = await service.savePurchaseOrder(
        PurchaseOrder(
          orgId: orgId,
          siteId: 'site-1',
          supplierId: 'sup-1',
          status: PurchaseOrderStatus.ordered,
          items: [
            PurchaseOrderItem(
              productId: productId,
              name: 'Feuerzeug',
              quantityOrdered: 50,
            ),
          ],
        ),
      );

      // Erste Teillieferung: 20 Stueck.
      await service.receivePurchaseOrder(
        orgId: orgId,
        orderId: orderId,
        receivedByItemIndex: {0: 20},
      );

      var product = await firestore
          .collection('organizations')
          .doc(orgId)
          .collection('products')
          .doc(productId)
          .get();
      expect(product.data()!['currentStock'], 25);

      var order = (await service.watchPurchaseOrders(orgId).first).first;
      expect(order.status, PurchaseOrderStatus.partiallyReceived);
      expect(order.items.first.quantityReceived, 20);

      // Restlieferung: 30 Stueck -> komplett.
      await service.receivePurchaseOrder(
        orgId: orgId,
        orderId: orderId,
        receivedByItemIndex: {0: 30},
      );

      product = await firestore
          .collection('organizations')
          .doc(orgId)
          .collection('products')
          .doc(productId)
          .get();
      expect(product.data()!['currentStock'], 55);

      order = (await service.watchPurchaseOrders(orgId).first).first;
      expect(order.status, PurchaseOrderStatus.received);
      expect(order.items.first.quantityReceived, 50);

      final movements = await service.watchStockMovements(orgId).first;
      expect(movements, hasLength(2));
      expect(
        movements.every((m) => m.type == StockMovementType.receipt),
        isTrue,
      );
    });

    test('receivePurchaseOrder caps received quantity at the outstanding amount',
        () async {
      final productId = await seedProduct(name: 'Feuerzeug', currentStock: 0);
      final orderId = await service.savePurchaseOrder(
        PurchaseOrder(
          orgId: orgId,
          siteId: 'site-1',
          supplierId: 'sup-1',
          status: PurchaseOrderStatus.ordered,
          items: [
            PurchaseOrderItem(
              productId: productId,
              name: 'Feuerzeug',
              quantityOrdered: 10,
            ),
          ],
        ),
      );

      // Versuch, mehr zu buchen als bestellt.
      await service.receivePurchaseOrder(
        orgId: orgId,
        orderId: orderId,
        receivedByItemIndex: {0: 999},
      );

      final product = await firestore
          .collection('organizations')
          .doc(orgId)
          .collection('products')
          .doc(productId)
          .get();
      expect(product.data()!['currentStock'], 10);

      final order = (await service.watchPurchaseOrders(orgId).first).first;
      expect(order.status, PurchaseOrderStatus.received);
      expect(order.items.first.quantityReceived, 10);
    });
  });
}
