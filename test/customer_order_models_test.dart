import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/customer_order.dart';

void main() {
  CustomerOrder sample() => CustomerOrder(
        id: 'co-1',
        orgId: 'org-1',
        siteId: 'site-1',
        siteName: 'Tabak Boerse',
        customerName: 'Herr Schmidt',
        customerContact: '0151 2345678',
        orderNumber: 'KB-2026-0007',
        status: CustomerOrderStatus.prepared,
        recurrence: CustomerOrderRecurrence.weekly,
        notes: 'Holt jeden Freitag ab.',
        pickupDate: DateTime(2026, 6, 19, 12),
        preparedAt: DateTime(2026, 6, 18, 9, 30),
        createdByUid: 'owner-1',
        items: const [
          CustomerOrderItem(
            productId: 'p-1',
            name: 'Pueblo Tabak 30g',
            sku: 'PUE30',
            category: 'Drehtabak',
            unit: 'Beutel',
            quantity: 5,
            unitPriceCents: 650,
          ),
          CustomerOrderItem(
            name: 'OCB Blaettchen',
            category: 'Raucherbedarf',
            quantity: 3,
          ),
        ],
      );

  group('CustomerOrderItem', () {
    test('lineTotalCents multipliziert Menge mit Einzelpreis', () {
      const item = CustomerOrderItem(
          name: 'X', quantity: 4, unitPriceCents: 250);
      expect(item.lineTotalCents, 1000);
    });

    test('lineTotalCents ist 0 ohne Preis', () {
      const item = CustomerOrderItem(name: 'X', quantity: 4);
      expect(item.lineTotalCents, 0);
    });

    test('snake_case round-trip (toMap/fromMap)', () {
      const item = CustomerOrderItem(
        productId: 'p-9',
        name: 'Marlboro',
        sku: 'MARL',
        category: 'Zigaretten',
        unit: 'Stange',
        quantity: 2,
        unitPriceCents: 8500,
      );
      final restored = CustomerOrderItem.fromMap(item.toMap());
      expect(restored.productId, 'p-9');
      expect(restored.name, 'Marlboro');
      expect(restored.sku, 'MARL');
      expect(restored.category, 'Zigaretten');
      expect(restored.unit, 'Stange');
      expect(restored.quantity, 2);
      expect(restored.unitPriceCents, 8500);
    });

    test('fromMap akzeptiert camelCase (Firestore) wie snake_case', () {
      final restored = CustomerOrderItem.fromMap(const {
        'productId': 'p-1',
        'name': 'Cola',
        'unitPriceCents': 199,
        'quantity': 6,
      });
      expect(restored.productId, 'p-1');
      expect(restored.unitPriceCents, 199);
      expect(restored.quantity, 6);
    });

    test('copyWith clearX leert Felder', () {
      const item = CustomerOrderItem(
        name: 'X',
        sku: 'S',
        category: 'C',
        quantity: 1,
        unitPriceCents: 100,
      );
      final cleared = item.copyWith(
        clearUnitPrice: true,
        clearCategory: true,
        clearSku: true,
      );
      expect(cleared.unitPriceCents, isNull);
      expect(cleared.category, isNull);
      expect(cleared.sku, isNull);
      expect(cleared.name, 'X');
    });
  });

  group('CustomerOrder enums', () {
    test('Status fromValue faellt unbekannt auf open zurueck', () {
      expect(CustomerOrderStatusX.fromValue('muell'), CustomerOrderStatus.open);
      expect(CustomerOrderStatusX.fromValue('picked_up'),
          CustomerOrderStatus.pickedUp);
    });

    test('Status .value / .label / isClosed', () {
      expect(CustomerOrderStatus.pickedUp.value, 'picked_up');
      expect(CustomerOrderStatus.open.label, 'Offen');
      expect(CustomerOrderStatus.pickedUp.isClosed, isTrue);
      expect(CustomerOrderStatus.cancelled.isClosed, isTrue);
      expect(CustomerOrderStatus.open.isClosed, isFalse);
      expect(CustomerOrderStatus.prepared.isOpen, isTrue);
    });

    test('Recurrence fromValue faellt unbekannt auf none zurueck', () {
      expect(CustomerOrderRecurrenceX.fromValue('muell'),
          CustomerOrderRecurrence.none);
      expect(CustomerOrderRecurrenceX.fromValue('monthly'),
          CustomerOrderRecurrence.monthly);
    });

    test('Recurrence.advance schiebt um Woche/Monat', () {
      final base = DateTime(2026, 1, 30, 12);
      expect(CustomerOrderRecurrence.none.advance(base), base);
      expect(CustomerOrderRecurrence.weekly.advance(base),
          DateTime(2026, 2, 6, 12));
      expect(CustomerOrderRecurrence.monthly.advance(base),
          DateTime(2026, 3, 2, 12)); // 30. Jan + 1 Monat -> normalisiert
    });
  });

  group('CustomerOrder', () {
    test('Berechnungen: total, hasPrices, isPrepared, itemCount', () {
      final order = sample();
      expect(order.itemCount, 2);
      expect(order.totalQuantity, 8);
      expect(order.totalCents, 5 * 650); // nur Position 1 hat Preis
      expect(order.hasPrices, isTrue);
      expect(order.isPrepared, isTrue);
    });

    test('nextPickupDate nur bei wiederkehrend + Termin', () {
      final order = sample();
      expect(order.nextPickupDate, DateTime(2026, 6, 26, 12));
      final once = order.copyWith(recurrence: CustomerOrderRecurrence.none);
      expect(once.nextPickupDate, isNull);
      final noDate = order.copyWith(clearPickupDate: true);
      expect(noDate.nextPickupDate, isNull);
    });

    test('snake_case round-trip erhaelt alle Felder inkl. Datum & Items', () {
      final order = sample();
      final restored = CustomerOrder.fromMap(order.toMap());
      expect(restored.id, 'co-1');
      expect(restored.customerName, 'Herr Schmidt');
      expect(restored.customerContact, '0151 2345678');
      expect(restored.orderNumber, 'KB-2026-0007');
      expect(restored.status, CustomerOrderStatus.prepared);
      expect(restored.recurrence, CustomerOrderRecurrence.weekly);
      expect(restored.pickupDate, DateTime(2026, 6, 19, 12));
      expect(restored.preparedAt, DateTime(2026, 6, 18, 9, 30));
      expect(restored.notes, 'Holt jeden Freitag ab.');
      expect(restored.items, hasLength(2));
      expect(restored.items.first.name, 'Pueblo Tabak 30g');
      expect(restored.items.first.category, 'Drehtabak');
    });

    test('camelCase round-trip (toFirestoreMap/fromFirestore)', () {
      final order = sample();
      final map = order.toFirestoreMap();
      // totalCents wird denormalisiert mitgeschrieben.
      expect(map['totalCents'], 5 * 650);
      final restored = CustomerOrder.fromFirestore('co-1', map);
      expect(restored.customerName, 'Herr Schmidt');
      expect(restored.status, CustomerOrderStatus.prepared);
      expect(restored.recurrence, CustomerOrderRecurrence.weekly);
      expect(restored.pickupDate, DateTime(2026, 6, 19, 12));
      expect(restored.items, hasLength(2));
      expect(restored.items.first.unitPriceCents, 650);
    });

    test('copyWith clearX leert nullable Felder', () {
      final order = sample();
      final cleared = order.copyWith(
        clearPickupDate: true,
        clearPreparedAt: true,
        clearCustomerContact: true,
        clearOrderNumber: true,
        clearNotes: true,
        clearSiteName: true,
      );
      expect(cleared.pickupDate, isNull);
      expect(cleared.preparedAt, isNull);
      expect(cleared.isPrepared, isFalse);
      expect(cleared.customerContact, isNull);
      expect(cleared.orderNumber, isNull);
      expect(cleared.notes, isNull);
      expect(cleared.siteName, isNull);
      // Unberuehrte Felder bleiben.
      expect(cleared.customerName, 'Herr Schmidt');
    });
  });
}
