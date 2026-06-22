import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/customer_order.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  // Nicht-Demo-Nutzer -> kein Demo-Seeding, leerer Start.
  const user = AppUserProfile(
    uid: 'owner-1',
    orgId: 'org-1',
    email: 'owner@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Inhaber'),
  );

  late FirestoreService firestoreService;

  InventoryProvider newLocalProvider() => InventoryProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    firestoreService = FirestoreService(firestore: FakeFirebaseFirestore());
  });

  CustomerOrder order({
    required String customer,
    DateTime? pickupDate,
    CustomerOrderStatus status = CustomerOrderStatus.open,
    CustomerOrderRecurrence recurrence = CustomerOrderRecurrence.none,
    DateTime? preparedAt,
  }) =>
      CustomerOrder(
        orgId: 'org-1',
        siteId: 'site-1',
        customerName: customer,
        status: status,
        recurrence: recurrence,
        pickupDate: pickupDate,
        preparedAt: preparedAt,
        items: const [
          CustomerOrderItem(name: 'Pueblo Tabak 30g', quantity: 4),
        ],
      );

  group('InventoryProvider – Kundenbestellungen (lokal)', () {
    test('saveCustomerOrder weist lokale Id + Nummer zu und persistiert',
        () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);

      await provider.saveCustomerOrder(order(customer: 'Herr Schmidt'));

      expect(provider.customerOrders, hasLength(1));
      final saved = provider.customerOrders.single;
      expect(saved.id, isNotNull);
      expect(saved.orderNumber, startsWith('KB-'));

      // Neustart (gleiche SharedPreferences) stellt wieder her.
      final restarted = newLocalProvider();
      await restarted.updateSession(user);
      expect(restarted.customerOrders, hasLength(1));
      expect(restarted.customerOrders.single.customerName, 'Herr Schmidt');
    });

    test('ordersDueSoonNotPrepared: nur offen, unvorbereitet, bald faellig',
        () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      final now = DateTime.now();

      await provider.saveCustomerOrder(
        order(customer: 'Ueberfaellig', pickupDate: now.subtract(const Duration(days: 1))),
      );
      await provider.saveCustomerOrder(
        order(customer: 'Morgen', pickupDate: now.add(const Duration(days: 1))),
      );
      await provider.saveCustomerOrder(
        order(customer: 'Spaeter', pickupDate: now.add(const Duration(days: 5))),
      );
      await provider.saveCustomerOrder(
        order(
          customer: 'Vorbereitet',
          pickupDate: now.add(const Duration(hours: 6)),
          status: CustomerOrderStatus.prepared,
          preparedAt: now,
        ),
      );
      await provider.saveCustomerOrder(
        order(
          customer: 'Abgeholt',
          pickupDate: now.subtract(const Duration(days: 2)),
          status: CustomerOrderStatus.pickedUp,
        ),
      );
      await provider.saveCustomerOrder(
        order(customer: 'OhneTermin'),
      );

      final due = provider.ordersDueSoonNotPrepared();
      final names = due.map((o) => o.customerName).toList();
      expect(names, containsAll(['Ueberfaellig', 'Morgen']));
      expect(names, isNot(contains('Spaeter')));
      expect(names, isNot(contains('Vorbereitet')));
      expect(names, isNot(contains('Abgeholt')));
      expect(names, isNot(contains('OhneTermin')));
      // Dringendste zuerst (ueberfaellig vor morgen).
      expect(due.first.customerName, 'Ueberfaellig');
      expect(provider.ordersDueSoonNotPrepared().length, 2);
    });

    test('markCustomerOrderPrepared setzt und entfernt preparedAt', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveCustomerOrder(
        order(customer: 'A', pickupDate: DateTime.now()),
      );

      await provider.markCustomerOrderPrepared(provider.customerOrders.single);
      var saved = provider.customerOrders.single;
      expect(saved.status, CustomerOrderStatus.prepared);
      expect(saved.isPrepared, isTrue);

      await provider.markCustomerOrderPrepared(saved, prepared: false);
      saved = provider.customerOrders.single;
      expect(saved.status, CustomerOrderStatus.open);
      expect(saved.isPrepared, isFalse);
    });

    test('markCustomerOrderPickedUp legt bei Wiederholung Folgetermin an',
        () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      final pickup = DateTime(2026, 6, 19, 12);
      await provider.saveCustomerOrder(
        order(
          customer: 'Stammkunde',
          pickupDate: pickup,
          recurrence: CustomerOrderRecurrence.weekly,
        ),
      );

      await provider.markCustomerOrderPickedUp(provider.customerOrders.single);

      expect(provider.customerOrders, hasLength(2));
      final pickedUp = provider.customerOrders
          .firstWhere((o) => o.status == CustomerOrderStatus.pickedUp);
      final followUp = provider.customerOrders
          .firstWhere((o) => o.status == CustomerOrderStatus.open);
      expect(pickedUp.customerName, 'Stammkunde');
      expect(followUp.customerName, 'Stammkunde');
      expect(followUp.pickupDate, DateTime(2026, 6, 26, 12)); // +7 Tage
      expect(followUp.isPrepared, isFalse);
      expect(followUp.recurrence, CustomerOrderRecurrence.weekly);
      expect(followUp.id, isNot(pickedUp.id));
    });

    test('markCustomerOrderPickedUp ohne Wiederholung legt nichts Neues an',
        () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveCustomerOrder(
        order(customer: 'Einmalig', pickupDate: DateTime(2026, 6, 19, 12)),
      );

      await provider.markCustomerOrderPickedUp(provider.customerOrders.single);

      expect(provider.customerOrders, hasLength(1));
      expect(provider.customerOrders.single.status,
          CustomerOrderStatus.pickedUp);
    });

    test('customerOrderCategories sammelt distinkte Warengruppen', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveCustomerOrder(
        const CustomerOrder(
          orgId: 'org-1',
          siteId: 'site-1',
          customerName: 'A',
          items: [
            CustomerOrderItem(name: 'Tabak', category: 'Drehtabak', quantity: 1),
            CustomerOrderItem(name: 'Zeitung', category: 'Presse', quantity: 1),
          ],
        ),
      );
      await provider.saveCustomerOrder(
        const CustomerOrder(
          orgId: 'org-1',
          siteId: 'site-1',
          customerName: 'B',
          items: [
            CustomerOrderItem(name: 'Tabak 2', category: 'Drehtabak', quantity: 1),
          ],
        ),
      );

      expect(provider.customerOrderCategories, {'Drehtabak', 'Presse'});
    });

    test('customerOrdersForSite filtert nach Standort', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveCustomerOrder(
        const CustomerOrder(
          orgId: 'org-1',
          siteId: 'site-1',
          customerName: 'Laden 1',
          items: [CustomerOrderItem(name: 'X', quantity: 1)],
        ),
      );
      await provider.saveCustomerOrder(
        const CustomerOrder(
          orgId: 'org-1',
          siteId: 'site-2',
          customerName: 'Laden 2',
          items: [CustomerOrderItem(name: 'Y', quantity: 1)],
        ),
      );

      expect(provider.customerOrdersForSite('site-1'), hasLength(1));
      expect(provider.customerOrdersForSite('site-1').single.customerName,
          'Laden 1');
      expect(provider.customerOrdersForSite(null), hasLength(2));
    });
  });
}
