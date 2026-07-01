import '../models/pos_receipt.dart';

/// **P2.3 — Tages-Gesundheits-Check & Multi-Store-Benchmark.** Vergleicht die
/// Beleg-Anzahl eines Geschäftstags je Laden mit dem **Wochentag-Schnitt** des
/// Fensters und mit dem **anderen Laden** — der Chef sieht früh, wenn ein Laden
/// schwächelt („Fr 16–19 = −34 %"). Basis ist die **Beleg-Anzahl** (anonym,
/// robust), nicht die noch unverifizierten Kassen-Geldfelder.
///
/// **Pure / offline-testbar:** der ausgewertete Tag wird injiziert (kein
/// `now()`); Wochentage werden aus dem `businessDay` (`YYYY-MM-DD`) abgeleitet.
class StoreHealth {
  const StoreHealth({
    required this.siteId,
    required this.evaluatedDay,
    required this.receiptsToday,
    required this.weekdayAverage,
    required this.weekdaySampleCount,
    required this.deltaPercent,
    required this.revenueTodayCents,
  });

  final String siteId;
  final String evaluatedDay;
  final int receiptsToday;

  /// Durchschnittliche Beleg-Anzahl an gleichen Wochentagen im Fenster (ohne den
  /// ausgewerteten Tag); `null`, wenn die Stichprobe zu klein/Floor unterschritten.
  final double? weekdayAverage;
  final int weekdaySampleCount;

  /// Abweichung heute gegenüber dem Wochentag-Schnitt in Prozent; `null` ohne
  /// belastbare Basis. Negativ = Einbruch.
  final double? deltaPercent;

  /// Best-effort-Tagesumsatz (brutto) in Cent — Anzeige, nicht Alarm-Basis.
  final int revenueTodayCents;

  /// Spürbarer Einbruch (für Alarm/Hervorhebung): mind. [threshold] % unter
  /// dem Wochentag-Schnitt.
  bool isDip({double threshold = 25}) =>
      deltaPercent != null && deltaPercent! <= -threshold;
}

class StoreBenchmark {
  const StoreBenchmark({required this.evaluatedDay, required this.perSite});

  final String evaluatedDay;

  /// Gesundheits-Signal je Standort, nach heutiger Beleg-Anzahl absteigend.
  final List<StoreHealth> perSite;
}

String? _dayOf(PosReceipt r) {
  final bd = r.businessDay;
  if (bd != null && bd.trim().isNotEmpty) return bd.trim();
  final tx = r.transactionDate;
  if (tx == null) return null;
  final m = tx.month.toString().padLeft(2, '0');
  final d = tx.day.toString().padLeft(2, '0');
  return '${tx.year}-$m-$d';
}

int? _weekday(String day) {
  // Explizit UTC parsen (Suffix Z), damit der Wochentag eines Kalendertags
  // unabhängig von der Host-/Server-Zeitzone deterministisch ist.
  final parsed = DateTime.tryParse('${day}T00:00:00Z');
  return parsed?.weekday;
}

/// Berechnet den [StoreBenchmark] für [evaluatedDay] (`YYYY-MM-DD`) aus den
/// Belegen des Fensters. Es zählen nur Umsatzbelege (`isRevenue`, kein training).
///
/// - [minWeekdaySamples]: Mindestanzahl gleicher Wochentage für eine belastbare
///   Basis (sonst `weekdayAverage`/`deltaPercent` = null).
/// - [minAverageFloor]: Mindest-Schnitt (gegen Prozent-Rauschen bei Kleinmengen).
StoreBenchmark computeStoreBenchmark({
  required List<PosReceipt> receipts,
  required String evaluatedDay,
  int minWeekdaySamples = 2,
  double minAverageFloor = 5,
}) {
  final targetWeekday = _weekday(evaluatedDay);

  // siteId -> day -> {count, revenue}
  final perSite = <String, Map<String, _DayAgg>>{};
  for (final r in receipts) {
    if (!r.isRevenue || r.training) continue;
    final day = _dayOf(r);
    if (day == null) continue;
    final byDay = perSite.putIfAbsent(r.siteId, () => <String, _DayAgg>{});
    final agg = byDay.putIfAbsent(day, () => _DayAgg());
    agg.count += 1;
    agg.revenueCents += r.grossCents ?? 0;
  }

  final result = <StoreHealth>[];
  for (final entry in perSite.entries) {
    final siteId = entry.key;
    final byDay = entry.value;
    final today = byDay[evaluatedDay];

    final sameWeekday = <int>[];
    for (final dayEntry in byDay.entries) {
      if (dayEntry.key == evaluatedDay) continue;
      if (targetWeekday != null && _weekday(dayEntry.key) != targetWeekday) {
        continue;
      }
      sameWeekday.add(dayEntry.value.count);
    }

    double? average;
    double? delta;
    if (sameWeekday.length >= minWeekdaySamples) {
      final avg = sameWeekday.reduce((a, b) => a + b) / sameWeekday.length;
      average = avg;
      if (avg >= minAverageFloor) {
        delta = ((today?.count ?? 0) - avg) / avg * 100;
      }
    }

    result.add(StoreHealth(
      siteId: siteId,
      evaluatedDay: evaluatedDay,
      receiptsToday: today?.count ?? 0,
      weekdayAverage: average,
      weekdaySampleCount: sameWeekday.length,
      deltaPercent: delta,
      revenueTodayCents: today?.revenueCents ?? 0,
    ));
  }

  result.sort((a, b) {
    final c = b.receiptsToday.compareTo(a.receiptsToday);
    return c != 0 ? c : a.siteId.compareTo(b.siteId);
  });
  return StoreBenchmark(evaluatedDay: evaluatedDay, perSite: result);
}

class _DayAgg {
  int count = 0;
  int revenueCents = 0;
}
