// lib/core/clock_service.dart

/// Reine Stempel-Rechenlogik (AllTec-1:1, M3) — kein State/IO/`now()`-Zugriff,
/// alle Eingaben injiziert → deterministisch + offline testbar.
///
/// Die Pausen-Schwellen sind identisch zu `compliance_service.dart` /
/// `functions/index.js` (ArbZG §4: 30 min ab 6 h, 45 min ab 9 h) — bei einer
/// Änderung dort hier mitziehen (CLAUDE.md Compliance-Spiegel).
abstract final class ClockService {
  static const int breakThreshold6hMinutes = 360;
  static const int breakThreshold9hMinutes = 540;

  /// Force-Close-Warnung ab dieser Laufzeit (10 h).
  static const int defaultMaxOngoingMinutes = 600;

  /// ArbZG §4: Pflichtpause in Minuten für eine **Brutto**-Arbeitszeit.
  static int requiredBreakMinutes(int grossMinutes) {
    if (grossMinutes > breakThreshold9hMinutes) {
      return 45;
    }
    if (grossMinutes > breakThreshold6hMinutes) {
      return 30;
    }
    return 0;
  }

  /// Netto-Minuten einer abgeschlossenen Buchung (≥ 0).
  static int netMinutes({
    required DateTime kommen,
    required DateTime gehen,
    required int pauseMinuten,
  }) {
    final gross = gehen.difference(kommen).inMinutes;
    final pause = pauseMinuten < 0 ? 0 : pauseMinuten;
    final net = gross - pause;
    return net < 0 ? 0 : net;
  }

  /// Pause, die beim Ausstempeln gilt: explizit angegeben (≥ 0), sonst die
  /// automatische Pflichtpause für die Brutto-Dauer (Fehlbetrag-Auto-Pause).
  static int effectivePauseMinutes({
    required DateTime kommen,
    required DateTime gehen,
    int? pauseMinuten,
  }) {
    if (pauseMinuten != null) {
      return pauseMinuten < 0 ? 0 : pauseMinuten;
    }
    final gross = gehen.difference(kommen).inMinutes;
    return requiredBreakMinutes(gross);
  }

  /// Laufzeit einer offenen Buchung relativ zu [now] (≥ 0).
  static int runningMinutes({
    required DateTime kommen,
    required DateTime now,
  }) {
    final minutes = now.difference(kommen).inMinutes;
    return minutes < 0 ? 0 : minutes;
  }

  /// Läuft die Buchung ungewöhnlich lange (> [maxMinutes], Default 10 h)?
  /// Das Ausstempeln wird dann als bestätigte Ausnahme gespeichert.
  static bool needsForceClose({
    required DateTime kommen,
    required DateTime now,
    int maxMinutes = defaultMaxOngoingMinutes,
  }) {
    return runningMinutes(kommen: kommen, now: now) > maxMinutes;
  }

  /// Stammt das Kommen von einem früheren Kalendertag (vergessenes Ausstempeln)?
  /// → Buchung braucht Klärung.
  static bool needsClarification({
    required DateTime kommen,
    required DateTime now,
  }) {
    final kommenDay = DateTime(kommen.year, kommen.month, kommen.day);
    final nowDay = DateTime(now.year, now.month, now.day);
    return nowDay.isAfter(kommenDay);
  }
}
