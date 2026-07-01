import '../models/pos_receipt.dart';

/// **P2.0 — Tagesabschluss (Tagesumsatz mit USt-Split).** Verdichtet die
/// Kassenbelege je **Geschäftstag** und Standort zu einem buchungsfähigen
/// Tagesumsatz: Brutto, **USt-Aufschlüsselung je Satz (19/7)** aus den
/// belegweiten `taxes[]`, sowie die Bargeld-Bewegung (`type=cash`) als Basis für
/// die spätere Kassendifferenz.
///
/// **Pure / offline-testbar.** **Daten-Vorbehalt:** Geld-/Steuerfelder der
/// Belege sind noch nicht gegen die OktoPOS-Swagger verifiziert (P0) — das
/// Ergebnis ist ein **Richtwert** (der Steuerberater prüft vor der Verbuchung),
/// nie eine fertige Festschreibung. training-Belege bleiben außen vor.
class TaxBucket {
  const TaxBucket({
    required this.ratePercent,
    required this.netCents,
    required this.taxCents,
    required this.grossCents,
  });

  /// USt-Satz in ganzen Prozent; `null` = unbekannter Satz (eigener Eimer).
  final int? ratePercent;
  final int netCents;
  final int taxCents;
  final int grossCents;
}

/// Tagesabschluss eines Standorts für einen Geschäftstag.
class DailyClosing {
  const DailyClosing({
    required this.businessDay,
    required this.siteId,
    required this.salesCount,
    required this.refundCount,
    required this.revenueGrossCents,
    required this.taxBuckets,
    required this.paymentsByMethod,
    required this.cashMovementCents,
  });

  final String businessDay;
  final String siteId;
  final int salesCount;
  final int refundCount;

  /// Brutto-Umsatz (sales + refund) des Tages in Cent.
  final int revenueGrossCents;

  /// USt-Aufschlüsselung je Satz (für die spätere n-JournalEntry-Buchung mit
  /// dediziertem Erlöskonto je 19/7).
  final List<TaxBucket> taxBuckets;

  /// Zahlart-Aufschlüsselung des Tages: Methode (bar/Karte/...) → Betrag in Cent.
  final Map<String, int> paymentsByMethod;

  /// Summe der Bargeld-Bewegungen (`type=cash`, Kassensturz/Ein-/Auszahlung) in
  /// Cent — Basis der Kassendifferenz (Soll-Bargeld vs. gezählt).
  final int cashMovementCents;
}

class _Agg {
  int salesCount = 0;
  int refundCount = 0;
  int revenueGrossCents = 0;
  int cashMovementCents = 0;
  // ratePercent (oder -1 für unbekannt) -> [net, tax, gross]
  final Map<int, List<int>> taxByRate = {};
  // Zahlart-Token -> Betrag in Cent
  final Map<String, int> paymentsByMethod = {};
}

/// Berechnet [DailyClosing]s je (Standort, Geschäftstag) aus den Belegen,
/// absteigend nach Geschäftstag sortiert.
List<DailyClosing> computeDailyClosings(List<PosReceipt> receipts) {
  // key: "siteId|businessDay"
  final agg = <String, _Agg>{};

  for (final r in receipts) {
    if (r.training) continue;
    final day = (r.businessDay != null && r.businessDay!.trim().isNotEmpty)
        ? r.businessDay!.trim()
        : _dayOf(r.transactionDate);
    if (day == null) continue;
    final a = agg.putIfAbsent('${r.siteId}|$day', () => _Agg());

    final type = (r.type ?? '').toLowerCase();
    if (type == 'cash') {
      a.cashMovementCents += r.grossCents ?? 0;
      continue;
    }
    if (!r.isRevenue) continue;

    if (type == 'refund') {
      a.refundCount += 1;
    } else {
      a.salesCount += 1;
    }
    a.revenueGrossCents += r.grossCents ?? 0;
    for (final t in r.taxes) {
      final rate = t.ratePercent ?? -1;
      final bucket = a.taxByRate.putIfAbsent(rate, () => [0, 0, 0]);
      bucket[0] += t.netCents ?? 0;
      bucket[1] += t.taxCents ?? 0;
      bucket[2] += t.grossCents ?? 0;
    }
    for (final p in r.payments) {
      final method = (p.method == null || p.method!.trim().isEmpty)
          ? 'unbekannt'
          : p.method!.trim();
      a.paymentsByMethod[method] =
          (a.paymentsByMethod[method] ?? 0) + (p.amountCents ?? 0);
    }
  }

  final result = <DailyClosing>[];
  for (final entry in agg.entries) {
    final parts = entry.key.split('|');
    final siteId = parts[0];
    final day = parts.sublist(1).join('|');
    final a = entry.value;
    final buckets = a.taxByRate.entries.map((e) {
      return TaxBucket(
        ratePercent: e.key < 0 ? null : e.key,
        netCents: e.value[0],
        taxCents: e.value[1],
        grossCents: e.value[2],
      );
    }).toList()
      ..sort((x, y) => (y.ratePercent ?? -1).compareTo(x.ratePercent ?? -1));
    result.add(DailyClosing(
      businessDay: day,
      siteId: siteId,
      salesCount: a.salesCount,
      refundCount: a.refundCount,
      revenueGrossCents: a.revenueGrossCents,
      taxBuckets: buckets,
      paymentsByMethod: Map<String, int>.unmodifiable(a.paymentsByMethod),
      cashMovementCents: a.cashMovementCents,
    ));
  }
  result.sort((x, y) {
    final c = y.businessDay.compareTo(x.businessDay);
    return c != 0 ? c : x.siteId.compareTo(y.siteId);
  });
  return result;
}

String? _dayOf(DateTime? tx) {
  if (tx == null) return null;
  return '${tx.year}-${tx.month.toString().padLeft(2, '0')}-'
      '${tx.day.toString().padLeft(2, '0')}';
}
