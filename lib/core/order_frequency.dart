import '../models/purchase_order.dart';

/// Zeitliche Auflösung der Bestellhäufigkeits-Auswertung.
enum FrequencyGranularity { week, month }

extension FrequencyGranularityX on FrequencyGranularity {
  String get label => switch (this) {
        FrequencyGranularity.week => 'Woche',
        FrequencyGranularity.month => 'Monat',
      };
}

/// Ein Zeitfenster (ISO-Woche oder Kalendermonat) mit aggregierten
/// Bestellzahlen. [start] ist der date-only Beginn des Fensters (Montag der
/// Woche bzw. Monatserster), [orderCount] die Anzahl distinkter, nicht
/// stornierter Bestellungen im Fenster, [quantity] die Summe der bestellten
/// Stückzahlen.
class OrderFrequencyBucket {
  const OrderFrequencyBucket({
    required this.start,
    required this.orderCount,
    required this.quantity,
  });

  final DateTime start;
  final int orderCount;
  final int quantity;
}

/// Montag (date-only) der ISO-Woche, in der [date] liegt.
DateTime startOfIsoWeek(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  final monday = d.subtract(Duration(days: d.weekday - 1));
  return DateTime(monday.year, monday.month, monday.day);
}

/// Erster Tag (date-only) des Monats, in dem [date] liegt.
DateTime startOfMonth(DateTime date) => DateTime(date.year, date.month, 1);

/// ISO-8601-Kalenderwochennummer (1–53). Die Woche 1 ist die Woche mit dem
/// ersten Donnerstag des Jahres. Rechnet in UTC, damit DST-Übergänge die
/// Tagesdifferenz nicht verfälschen.
int isoWeekNumber(DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  // Donnerstag der laufenden ISO-Woche bestimmt das ISO-Jahr.
  final thursday = d.add(Duration(days: 4 - d.weekday));
  final firstDayOfIsoYear = DateTime.utc(thursday.year, 1, 1);
  final dayOfYear = thursday.difference(firstDayOfIsoYear).inDays;
  return 1 + (dayOfYear ~/ 7);
}

DateTime _shiftWeeks(DateTime monday, int weeks) {
  final shifted = monday.add(Duration(days: 7 * weeks));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

/// Bucketet [orders] in die letzten [bucketCount] Fenster (ISO-Woche bzw.
/// Monat), endend mit dem Fenster, in dem [now] liegt. Älteste zuerst.
///
/// Gezählt werden nur Bestellungen, die **nicht** storniert sind; optional auf
/// einen [siteId]-Laden und auf einen [productId]-Artikel beschränkt. Ist
/// [productId] gesetzt, zählt eine Bestellung nur, wenn sie diesen Artikel
/// enthält, und [OrderFrequencyBucket.quantity] summiert nur dessen Positionen.
/// Datum einer Bestellung = `orderedAt ?? createdAt` (rein, kein `now()`).
List<OrderFrequencyBucket> buildOrderFrequencyBuckets({
  required List<PurchaseOrder> orders,
  required FrequencyGranularity granularity,
  required DateTime now,
  int bucketCount = 12,
  String? siteId,
  String? productId,
}) {
  final count = bucketCount < 1 ? 1 : bucketCount;
  final starts = <DateTime>[];
  if (granularity == FrequencyGranularity.week) {
    final thisMonday = startOfIsoWeek(now);
    for (var i = count - 1; i >= 0; i--) {
      starts.add(_shiftWeeks(thisMonday, -i));
    }
  } else {
    final thisMonth = startOfMonth(now);
    for (var i = count - 1; i >= 0; i--) {
      starts.add(DateTime(thisMonth.year, thisMonth.month - i, 1));
    }
  }

  final indexByStart = <DateTime, int>{
    for (var i = 0; i < starts.length; i++) starts[i]: i,
  };
  final earliest = starts.first;
  final orderCounts = List<int>.filled(starts.length, 0);
  final quantities = List<int>.filled(starts.length, 0);

  for (final order in orders) {
    if (order.status == PurchaseOrderStatus.cancelled) {
      continue;
    }
    if (siteId != null && siteId.isNotEmpty && order.siteId != siteId) {
      continue;
    }
    final when = order.orderedAt ?? order.createdAt;
    if (when == null || when.isBefore(earliest)) {
      continue;
    }
    final start = granularity == FrequencyGranularity.week
        ? startOfIsoWeek(when)
        : startOfMonth(when);
    final idx = indexByStart[start];
    if (idx == null) {
      continue; // außerhalb des Fensters (z.B. zukünftig datiert)
    }
    var qty = 0;
    var contains = false;
    for (final item in order.items) {
      if (productId == null || productId.isEmpty) {
        contains = true;
        qty += item.quantityOrdered;
      } else if (item.productId == productId) {
        contains = true;
        qty += item.quantityOrdered;
      }
    }
    if (!contains) {
      continue;
    }
    orderCounts[idx] += 1;
    quantities[idx] += qty;
  }

  return [
    for (var i = 0; i < starts.length; i++)
      OrderFrequencyBucket(
        start: starts[i],
        orderCount: orderCounts[i],
        quantity: quantities[i],
      ),
  ];
}
