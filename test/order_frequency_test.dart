import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/order_frequency.dart';
import 'package:worktime_app/models/purchase_order.dart';

PurchaseOrder _order({
  required DateTime when,
  required List<String> productIds,
  PurchaseOrderStatus status = PurchaseOrderStatus.ordered,
  String siteId = 'site-1',
  List<int>? quantities,
}) {
  return PurchaseOrder(
    orgId: 'org-1',
    siteId: siteId,
    supplierId: 'sup-1',
    status: status,
    orderedAt: when,
    items: [
      for (var i = 0; i < productIds.length; i++)
        PurchaseOrderItem(
          productId: productIds[i],
          name: productIds[i],
          quantityOrdered: quantities?[i] ?? 1,
        ),
    ],
  );
}

void main() {
  group('isoWeekNumber', () {
    test('ISO-Grenzfälle rund um den Jahreswechsel', () {
      // 2026-01-01 ist ein Donnerstag -> KW1.
      expect(isoWeekNumber(DateTime(2026, 1, 1)), 1);
      // Montag der KW1/2026 liegt noch im Dezember 2025.
      expect(isoWeekNumber(DateTime(2025, 12, 29)), 1);
      // 2024-12-30 (Montag) gehört zur KW1/2025.
      expect(isoWeekNumber(DateTime(2024, 12, 30)), 1);
      expect(isoWeekNumber(DateTime(2026, 1, 5)), 2);
      // 2026-06-01 ist ein Montag in KW23.
      expect(isoWeekNumber(DateTime(2026, 6, 1)), 23);
    });
  });

  group('startOfIsoWeek / startOfMonth', () {
    test('liefert den Montag (date-only) und den Monatsersten', () {
      final monday = startOfIsoWeek(DateTime(2026, 6, 24, 15, 30));
      expect(monday.weekday, DateTime.monday);
      expect(monday.hour, 0);
      expect(monday.isAfter(DateTime(2026, 6, 24)), isFalse);
      expect(DateTime(2026, 6, 24).difference(monday).inDays, lessThan(7));

      expect(startOfMonth(DateTime(2026, 6, 24, 15)), DateTime(2026, 6, 1));
    });
  });

  group('buildOrderFrequencyBuckets', () {
    // 2026-06-24 ist ein Mittwoch (KW-Montag = 2026-06-22).
    final now = DateTime(2026, 6, 24, 12);

    test('bucketet pro Woche, älteste zuerst, aktuelle Woche zuletzt', () {
      final orders = [
        _order(when: DateTime(2026, 6, 23), productIds: ['a']),
        _order(when: DateTime(2026, 6, 22), productIds: ['a', 'b']),
        _order(when: DateTime(2026, 6, 16), productIds: ['a']),
      ];
      final buckets = buildOrderFrequencyBuckets(
        orders: orders,
        granularity: FrequencyGranularity.week,
        now: now,
        bucketCount: 4,
      );
      expect(buckets.length, 4);
      // Letztes Fenster = laufende Woche -> 2 Bestellungen, 3 Stück.
      expect(buckets.last.orderCount, 2);
      expect(buckets.last.quantity, 3);
      // Vorwoche -> 1 Bestellung.
      expect(buckets[buckets.length - 2].orderCount, 1);
    });

    test('ignoriert stornierte Bestellungen und filtert nach Artikel', () {
      final orders = [
        _order(when: DateTime(2026, 6, 23), productIds: ['a', 'b']),
        _order(
          when: DateTime(2026, 6, 23),
          productIds: ['a'],
          status: PurchaseOrderStatus.cancelled,
        ),
        _order(when: DateTime(2026, 6, 23), productIds: ['b']),
      ];
      final all = buildOrderFrequencyBuckets(
        orders: orders,
        granularity: FrequencyGranularity.week,
        now: now,
        bucketCount: 1,
      );
      expect(all.single.orderCount, 2); // storniert zählt nicht

      final onlyA = buildOrderFrequencyBuckets(
        orders: orders,
        granularity: FrequencyGranularity.week,
        now: now,
        bucketCount: 1,
        productId: 'a',
      );
      expect(onlyA.single.orderCount, 1); // nur die nicht stornierte mit 'a'
    });

    test('ignoriert Bestellungen außerhalb des Fensters und in der Zukunft', () {
      final orders = [
        _order(when: DateTime(2026, 1, 1), productIds: ['a']), // zu alt
        _order(when: DateTime(2026, 12, 1), productIds: ['a']), // Zukunft
      ];
      final buckets = buildOrderFrequencyBuckets(
        orders: orders,
        granularity: FrequencyGranularity.week,
        now: now,
        bucketCount: 4,
      );
      expect(buckets.fold<int>(0, (s, b) => s + b.orderCount), 0);
    });

    test('bucketet pro Monat', () {
      final orders = [
        _order(when: DateTime(2026, 6, 10), productIds: ['a']),
        _order(when: DateTime(2026, 5, 10), productIds: ['a']),
        _order(when: DateTime(2026, 5, 20), productIds: ['b']),
      ];
      final buckets = buildOrderFrequencyBuckets(
        orders: orders,
        granularity: FrequencyGranularity.month,
        now: now,
        bucketCount: 3,
      );
      expect(buckets.length, 3);
      expect(buckets.last.start, DateTime(2026, 6, 1));
      expect(buckets.last.orderCount, 1); // Juni
      expect(buckets[buckets.length - 2].orderCount, 2); // Mai
    });

    test('respektiert den Laden-Filter', () {
      final orders = [
        _order(when: DateTime(2026, 6, 23), productIds: ['a'], siteId: 'site-1'),
        _order(when: DateTime(2026, 6, 23), productIds: ['a'], siteId: 'site-2'),
      ];
      final site1 = buildOrderFrequencyBuckets(
        orders: orders,
        granularity: FrequencyGranularity.week,
        now: now,
        bucketCount: 1,
        siteId: 'site-1',
      );
      expect(site1.single.orderCount, 1);
    });
  });
}
