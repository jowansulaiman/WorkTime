import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/customer_order.dart';
import 'package:worktime_app/models/finance_models.dart';
import 'package:worktime_app/models/purchase_order.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/finance_provider.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// H-A2: Wareneinsatz/Umsatz aus der Warenwirtschaft werden beim Abschluss
/// automatisch (idempotent) als JournalEntry in die Buchhaltung gebucht.
void main() {
  const admin = AppUserProfile(
    uid: 'owner-1',
    orgId: 'org-1',
    email: 'owner@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Inhaber'),
  );

  late FirestoreService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    service = FirestoreService(firestore: FakeFirebaseFirestore());
  });

  Future<({InventoryProvider inventory, FinanceProvider finance})> wire() async {
    final finance =
        FinanceProvider(firestoreService: service, disableAuthentication: true);
    addTearDown(finance.dispose);
    await finance.updateSession(admin, localStorageOnly: true);
    await finance.saveCostCenter(const CostCenter(
      orgId: 'org-1',
      number: '1001',
      name: 'Strichmännchen',
      siteId: 'site-1',
    ));
    await finance.saveCostType(
        const CostType(orgId: 'org-1', number: '8400', name: 'Umsatzerlöse'));
    await finance.saveCostType(
        const CostType(orgId: 'org-1', number: '3400', name: 'Wareneinsatz'));

    final inventory =
        InventoryProvider(firestoreService: service, disableAuthentication: true);
    addTearDown(inventory.dispose);
    await inventory.updateSession(admin);
    inventory.setRevenueJournalPoster(finance.postCustomerOrderRevenue);
    inventory.setGoodsCostJournalPoster(finance.postPurchaseOrderCost);
    return (inventory: inventory, finance: finance);
  }

  test('Kundenbestellung abgeholt → Umsatz-Buchung (negativ, idempotent)',
      () async {
    final (:inventory, :finance) = await wire();
    final id = await inventory.saveCustomerOrder(const CustomerOrder(
      orgId: 'org-1',
      siteId: 'site-1',
      customerName: 'Frau Schmidt',
      items: [
        CustomerOrderItem(name: 'Zigarren', quantity: 2, unitPriceCents: 1500),
      ],
    ));
    // Noch offen → keine Buchung.
    expect(finance.journalEntries, isEmpty);

    final order =
        inventory.customerOrders.firstWhere((o) => o.id == id);
    await inventory
        .saveCustomerOrder(order.copyWith(status: CustomerOrderStatus.pickedUp));

    expect(finance.journalEntries, hasLength(1));
    final entry = finance.journalEntries.single;
    expect(entry.id, 'co-$id');
    expect(entry.amountCents, -3000); // Erlös = Gutschrift (negativ)
    expect(entry.isCredit, isTrue);

    // Erneut speichern (schon abgeholt) → keine Doppelbuchung.
    final picked = inventory.customerOrders.firstWhere((o) => o.id == id);
    await inventory.saveCustomerOrder(picked.copyWith(notes: 'bezahlt'));
    expect(finance.journalEntries, hasLength(1));
  });

  test('Bestellung geliefert → Wareneinsatz-Buchung (positiv)', () async {
    final (:inventory, :finance) = await wire();
    final id = await inventory.savePurchaseOrder(const PurchaseOrder(
      orgId: 'org-1',
      siteId: 'site-1',
      supplierId: 'sup-1',
      items: [
        PurchaseOrderItem(
            name: 'Feuerzeuge', quantityOrdered: 100, unitPriceCents: 50),
      ],
    ));
    expect(finance.journalEntries, isEmpty);

    final order = inventory.purchaseOrders.firstWhere((o) => o.id == id);
    await inventory.savePurchaseOrder(
        order.copyWith(status: PurchaseOrderStatus.received));

    expect(finance.journalEntries, hasLength(1));
    final entry = finance.journalEntries.single;
    expect(entry.id, 'po-$id');
    expect(entry.amountCents, 5000); // Kosten = positiv
    expect(entry.isExpense, isTrue);
  });

  test('Restschluss bucht nur den Wert der tatsächlich gelieferten Menge',
      () async {
    final (:inventory, :finance) = await wire();
    final id = await inventory.savePurchaseOrder(
      const PurchaseOrder(
        orgId: 'org-1',
        siteId: 'site-1',
        supplierId: 'sup-1',
        status: PurchaseOrderStatus.ordered,
        items: [
          PurchaseOrderItem(
            name: 'Feuerzeuge',
            quantityOrdered: 100,
            unitPriceCents: 50,
          ),
        ],
      ),
    );

    await inventory.receiveOrder(
      orderId: id,
      receivedByItemIndex: const {0: 40},
    );
    expect(finance.journalEntries, isEmpty);

    await inventory.closePurchaseOrderRemainder(
      orderId: id,
      reason: 'Rest nicht lieferbar',
    );

    expect(finance.journalEntries, hasLength(1));
    final entry = finance.journalEntries.single;
    expect(entry.id, 'po-$id');
    expect(entry.amountCents, 2000);
    expect(entry.date, inventory.purchaseOrders.single.closedAt);
  });

  test('Restschluss ohne Lieferwert erzeugt keine Journalbuchung', () async {
    final (:inventory, :finance) = await wire();
    final id = await inventory.savePurchaseOrder(
      const PurchaseOrder(
        orgId: 'org-1',
        siteId: 'site-1',
        supplierId: 'sup-1',
        status: PurchaseOrderStatus.ordered,
        items: [PurchaseOrderItem(name: 'Gratisware', quantityOrdered: 10)],
      ),
    );

    await inventory.receiveOrder(
      orderId: id,
      receivedByItemIndex: const {0: 4},
    );
    await inventory.closePurchaseOrderRemainder(
      orderId: id,
      reason: 'Rest nicht lieferbar',
    );

    expect(finance.journalEntries, isEmpty);
  });

  test('ohne passende Kostenart wird nicht gebucht (keine Falschbuchung)',
      () async {
    final finance =
        FinanceProvider(firestoreService: service, disableAuthentication: true);
    addTearDown(finance.dispose);
    await finance.updateSession(admin, localStorageOnly: true);
    await finance.saveCostCenter(const CostCenter(
        orgId: 'org-1', number: '1001', name: 'Laden', siteId: 'site-1'));
    // KEINE Umsatz-/Wareneinsatz-Kostenart angelegt.

    final inventory =
        InventoryProvider(firestoreService: service, disableAuthentication: true);
    addTearDown(inventory.dispose);
    await inventory.updateSession(admin);
    inventory.setRevenueJournalPoster(finance.postCustomerOrderRevenue);

    final id = await inventory.saveCustomerOrder(const CustomerOrder(
      orgId: 'org-1',
      siteId: 'site-1',
      customerName: 'Kunde',
      status: CustomerOrderStatus.pickedUp,
      items: [CustomerOrderItem(name: 'X', quantity: 1, unitPriceCents: 999)],
    ));
    expect(id, isNotEmpty);
    expect(finance.journalEntries, isEmpty);
  });
}
