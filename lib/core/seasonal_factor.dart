import '../models/pos_receipt.dart';

/// **P4.3 — Saison-/Wetter-Faktor (opt-in, Feinschliff).** Liefert
/// Nachfrage-Multiplikatoren zur Feinjustierung von Bestell-/Besetzungs-
/// Vorschlägen:
/// - **Wochentag-/Saison-Faktor** aus der eigenen Beleg-Historie (Fr läuft
///   stärker als Di) — pure, ohne externe Quelle.
/// - **Wetter-Faktor** aus einem [WeatherSnapshot] (warm/trocken hebt Impuls-
///   käufe, Starkregen senkt die Frequenz) — **graceful degradation: ohne
///   Wetterdaten = Faktor 1.0** (der Open-Meteo-Abruf ist ein optionaler Adapter
///   und keine harte Abhängigkeit).
///
/// **Pure / offline-testbar.** Die Wetter-Heuristik ist bewusst einfach und als
/// Richtwert dokumentiert.
class WeatherSnapshot {
  const WeatherSnapshot({this.temperatureC, this.precipitationMm});

  final double? temperatureC;
  final double? precipitationMm;
}

double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

int? _weekdayOf(String day) {
  final parsed = DateTime.tryParse('${day}T00:00:00Z');
  return parsed?.weekday;
}

String? _dayOf(PosReceipt r) {
  final bd = r.businessDay;
  if (bd != null && bd.trim().isNotEmpty) return bd.trim();
  final tx = r.transactionDate;
  if (tx == null) return null;
  return '${tx.year}-${tx.month.toString().padLeft(2, '0')}-'
      '${tx.day.toString().padLeft(2, '0')}';
}

/// Wochentag (1..7) → Nachfrage-Faktor relativ zum Durchschnittstag
/// (`> 1` = überdurchschnittlich). Mittelt Belege je Wochentag über die
/// beobachteten Tage und normiert auf den Mittelwert aller Wochentage. Nur
/// Umsatzbelege. Leeres Ergebnis, wenn keine Basis.
Map<int, double> computeWeekdayDemandFactors(List<PosReceipt> receipts) {
  final countByWeekday = <int, int>{};
  final daysByWeekday = <int, Set<String>>{};
  for (final r in receipts) {
    if (!r.isRevenue || r.training) continue;
    final day = _dayOf(r);
    if (day == null) continue;
    final wd = _weekdayOf(day);
    if (wd == null) continue;
    countByWeekday[wd] = (countByWeekday[wd] ?? 0) + 1;
    (daysByWeekday[wd] ??= <String>{}).add(day);
  }
  if (countByWeekday.isEmpty) return const {};

  final avgByWeekday = <int, double>{};
  for (final wd in countByWeekday.keys) {
    final days = daysByWeekday[wd]!.length;
    if (days > 0) avgByWeekday[wd] = countByWeekday[wd]! / days;
  }
  if (avgByWeekday.isEmpty) return const {};
  final overall =
      avgByWeekday.values.reduce((a, b) => a + b) / avgByWeekday.length;
  if (overall <= 0) return const {};

  return {
    for (final e in avgByWeekday.entries) e.key: e.value / overall,
  };
}

/// Wetter → Nachfrage-Faktor. `null`/ohne Werte ⇒ **1.0** (graceful). Heuristik:
/// warm hebt (bis +20 %), Starkregen senkt (bis −20 %). Richtwert.
double weatherDemandFactor(WeatherSnapshot? weather) {
  if (weather == null) return 1.0;
  final temp = weather.temperatureC;
  final precip = weather.precipitationMm;
  final tempFactor =
      temp == null ? 1.0 : 1.0 + _clamp((temp - 20) / 100, -0.1, 0.2);
  final precipFactor =
      precip == null ? 1.0 : 1.0 - _clamp(precip / 100, 0.0, 0.2);
  return tempFactor * precipFactor;
}

/// Kombinierter Nachfrage-Faktor für einen [weekday]: Wochentag-Faktor ×
/// Wetter-Faktor. Fehlt der Wochentag in [weekdayFactors], gilt 1.0.
double combinedDemandFactor({
  required int weekday,
  required Map<int, double> weekdayFactors,
  WeatherSnapshot? weather,
}) {
  final wf = weekdayFactors[weekday] ?? 1.0;
  return wf * weatherDemandFactor(weather);
}
