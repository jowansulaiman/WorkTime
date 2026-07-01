import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/store_health.dart';
import 'package:worktime_app/models/pos_receipt.dart';

/// Reine Tests für P2.3 (Tages-Gesundheits-Check / Multi-Store-Benchmark).
void main() {
  // Erzeugt [count] Umsatzbelege eines Standorts an einem Geschäftstag.
  List<PosReceipt> receiptsFor(String siteId, String day, int count,
      {int grossEach = 0, bool revenue = true, bool training = false}) {
    return List.generate(
      count,
      (i) => PosReceipt(
        orgId: 'org-1',
        siteId: siteId,
        referenceNumber: '$siteId-$day-$i',
        type: revenue ? 'sales' : 'cash',
        isRevenue: revenue,
        training: training,
        businessDay: day,
        grossCents: grossEach,
      ),
    );
  }

  test('Wochentag-Schnitt und Delta je Standort', () {
    // 2026-06-30 ist ein Dienstag; Vergleichsdienstage 06-16/06-23 mit je 10
    // Belegen -> Schnitt 10. Heute 6 Belege -> −40 %.
    final receipts = [
      ...receiptsFor('site-1', '2026-06-16', 10),
      ...receiptsFor('site-1', '2026-06-23', 10),
      ...receiptsFor('site-1', '2026-06-17', 99), // Mittwoch, zählt nicht
      ...receiptsFor('site-1', '2026-06-30', 6),
    ];
    final benchmark = computeStoreBenchmark(
      receipts: receipts,
      evaluatedDay: '2026-06-30',
    );
    final s1 = benchmark.perSite.single;
    expect(s1.receiptsToday, 6);
    expect(s1.weekdayAverage, 10);
    expect(s1.weekdaySampleCount, 2);
    expect(s1.deltaPercent, -40);
    expect(s1.isDip(), isTrue);
  });

  test('zu kleine Stichprobe ⇒ kein Delta', () {
    final receipts = [
      ...receiptsFor('site-1', '2026-06-23', 10), // nur EIN Vergleichsdienstag
      ...receiptsFor('site-1', '2026-06-30', 3),
    ];
    final benchmark = computeStoreBenchmark(
      receipts: receipts,
      evaluatedDay: '2026-06-30',
      minWeekdaySamples: 2,
    );
    final s1 = benchmark.perSite.single;
    expect(s1.receiptsToday, 3);
    expect(s1.weekdayAverage, isNull);
    expect(s1.deltaPercent, isNull);
    expect(s1.isDip(), isFalse);
  });

  test('Floor unterdrückt Prozent-Rauschen bei Kleinmengen', () {
    final receipts = [
      ...receiptsFor('site-1', '2026-06-16', 2),
      ...receiptsFor('site-1', '2026-06-23', 2),
      ...receiptsFor('site-1', '2026-06-30', 1),
    ];
    final benchmark = computeStoreBenchmark(
      receipts: receipts,
      evaluatedDay: '2026-06-30',
      minAverageFloor: 5,
    );
    // Schnitt 2 < Floor 5 -> kein Delta, aber Schnitt wird gemeldet.
    expect(benchmark.perSite.single.weekdayAverage, 2);
    expect(benchmark.perSite.single.deltaPercent, isNull);
  });

  test('training/cash zählen nicht, Umsatz wird best-effort summiert', () {
    final receipts = [
      ...receiptsFor('site-1', '2026-06-30', 4, grossEach: 250),
      ...receiptsFor('site-1', '2026-06-30', 9, revenue: false), // cash
      ...receiptsFor('site-1', '2026-06-30', 9, training: true),
    ];
    final s1 = computeStoreBenchmark(
      receipts: receipts,
      evaluatedDay: '2026-06-30',
    ).perSite.single;
    expect(s1.receiptsToday, 4);
    expect(s1.revenueTodayCents, 1000); // 4 × 250
  });

  test('zwei Läden werden nach heutiger Beleg-Anzahl gerankt', () {
    final receipts = [
      ...receiptsFor('site-1', '2026-06-30', 5),
      ...receiptsFor('site-2', '2026-06-30', 12),
    ];
    final benchmark = computeStoreBenchmark(
      receipts: receipts,
      evaluatedDay: '2026-06-30',
    );
    expect(benchmark.perSite.map((s) => s.siteId), ['site-2', 'site-1']);
  });
}
