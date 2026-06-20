import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/customer_order.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  group('FirestoreService – Kundenbestellungen', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreService service;
    const orgId = 'org-1';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = FirestoreService(firestore: firestore);
    });

    CustomerOrder newOrder({
      String customer = 'Herr Schmidt',
      CustomerOrderStatus status = CustomerOrderStatus.open,
    }) =>
        CustomerOrder(
          orgId: orgId,
          siteId: 'site-1',
          customerName: customer,
          status: status,
          pickupDate: DateTime(2026, 6, 20, 12),
          items: const [
            CustomerOrderItem(
              name: 'Pueblo Tabak 30g',
              category: 'Drehtabak',
              quantity: 4,
              unitPriceCents: 650,
            ),
          ],
        );

    test('saveCustomerOrder vergibt Nummer und Stream emittiert', () async {
      final id = await service.saveCustomerOrder(newOrder());
      expect(id, isNotEmpty);

      final orders = await service.watchCustomerOrders(orgId).first;
      expect(orders, hasLength(1));
      expect(orders.first.customerName, 'Herr Schmidt');
      expect(orders.first.id, id);
      expect(orders.first.orderNumber, startsWith('KB-'));
      expect(orders.first.totalCents, 4 * 650);
    });

    test('saveCustomerOrder mit id aktualisiert statt anzulegen', () async {
      final id = await service.saveCustomerOrder(newOrder());
      final loaded = (await service.watchCustomerOrders(orgId).first).first;

      await service.saveCustomerOrder(
        loaded.copyWith(status: CustomerOrderStatus.prepared,
            preparedAt: DateTime(2026, 6, 19)),
      );

      final orders = await service.watchCustomerOrders(orgId).first;
      expect(orders, hasLength(1));
      expect(orders.first.id, id);
      expect(orders.first.status, CustomerOrderStatus.prepared);
      expect(orders.first.isPrepared, isTrue);
    });

    test('deleteCustomerOrder entfernt das Dokument', () async {
      final id = await service.saveCustomerOrder(newOrder());
      await service.deleteCustomerOrder(orgId: orgId, orderId: id);

      final orders = await service.watchCustomerOrders(orgId).first;
      expect(orders, isEmpty);
    });

    test('mehrere Bestellungen erhalten fortlaufende Nummern', () async {
      await service.saveCustomerOrder(newOrder(customer: 'A'));
      await service.saveCustomerOrder(newOrder(customer: 'B'));

      final orders = await service.watchCustomerOrders(orgId).first;
      final numbers =
          orders.map((order) => order.orderNumber).whereType<String>().toSet();
      expect(numbers, hasLength(2)); // eindeutig
    });
  });
}
