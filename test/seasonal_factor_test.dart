import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/seasonal_factor.dart';
import 'package:worktime_app/models/pos_receipt.dart';

/// Reine Tests für P4.3 (Saison-/Wetter-Faktor).
void main() {
  // [count] Umsatzbelege an einem Geschäftstag.
  List<PosReceipt> receiptsFor(String day, int count,
          {bool revenue = true, bool training = false}) =>
      List.generate(
        count,
        (i) => PosReceipt(
          orgId: 'org-1',
          siteId: 'site-1',
          referenceNumber: '$day-$i',
          type: revenue ? 'sales' : 'cash',
          isRevenue: revenue,
          training: training,
          businessDay: day,
        ),
      );

  group('computeWeekdayDemandFactors', () {
    test('normiert Wochentag-Durchschnitt auf den Gesamtschnitt', () {
      // 2026-06-29 = Montag (3 Belege), 2026-06-30 = Dienstag (1 Beleg).
      // avg Mo=3, Di=1 -> Gesamtschnitt 2 -> Faktoren Mo 1.5, Di 0.5.
      final factors = computeWeekdayDemandFactors([
        ...receiptsFor('2026-06-29', 3),
        ...receiptsFor('2026-06-30', 1),
      ]);
      expect(factors[DateTime.monday], 1.5);
      expect(factors[DateTime.tuesday], 0.5);
    });

    test('mittelt je Wochentag über beobachtete Tage', () {
      // Zwei Montage (8 + 4 Belege) -> avg 6; ein Dienstag 6 -> avg 6.
      // Gesamtschnitt 6 -> beide Faktoren 1.0.
      final factors = computeWeekdayDemandFactors([
        ...receiptsFor('2026-06-22', 8), // Montag
        ...receiptsFor('2026-06-29', 4), // Montag
        ...receiptsFor('2026-06-30', 6), // Dienstag
      ]);
      expect(factors[DateTime.monday], 1.0);
      expect(factors[DateTime.tuesday], 1.0);
    });

    test('keine Basis ⇒ leer', () {
      expect(computeWeekdayDemandFactors(const []), isEmpty);
      expect(
          computeWeekdayDemandFactors(receiptsFor('2026-06-30', 5, revenue: false)),
          isEmpty);
    });
  });

  group('weatherDemandFactor', () {
    test('ohne Wetter ⇒ 1.0 (graceful degradation)', () {
      expect(weatherDemandFactor(null), 1.0);
      expect(weatherDemandFactor(const WeatherSnapshot()), 1.0);
    });

    test('warm hebt, Starkregen senkt', () {
      // 30 °C, 0 mm -> 1 + (10/100) = 1.1
      expect(weatherDemandFactor(const WeatherSnapshot(temperatureC: 30, precipitationMm: 0)),
          closeTo(1.1, 1e-9));
      // 20 °C, 20 mm -> 1.0 * (1 - 0.2) = 0.8
      expect(weatherDemandFactor(const WeatherSnapshot(temperatureC: 20, precipitationMm: 20)),
          closeTo(0.8, 1e-9));
    });

    test('Extreme werden gedeckelt (±)', () {
      // sehr heiß -> Temp-Faktor max 1.2; sehr nass -> Regen-Faktor min 0.8.
      expect(weatherDemandFactor(const WeatherSnapshot(temperatureC: 99, precipitationMm: 0)),
          closeTo(1.2, 1e-9));
      expect(weatherDemandFactor(const WeatherSnapshot(temperatureC: 20, precipitationMm: 999)),
          closeTo(0.8, 1e-9));
    });
  });

  test('combinedDemandFactor multipliziert Wochentag × Wetter', () {
    final factor = combinedDemandFactor(
      weekday: DateTime.monday,
      weekdayFactors: const {DateTime.monday: 1.5},
      weather: const WeatherSnapshot(temperatureC: 30, precipitationMm: 0),
    );
    expect(factor, closeTo(1.65, 1e-9)); // 1.5 × 1.1
    // unbekannter Wochentag -> 1.0 × Wetter
    expect(
      combinedDemandFactor(
          weekday: DateTime.sunday, weekdayFactors: const {}, weather: null),
      1.0,
    );
  });
}
