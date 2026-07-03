import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/clock_service.dart';

void main() {
  group('ClockService.requiredBreakMinutes (ArbZG §4)', () {
    test('keine Pause bis 6 h (360 min)', () {
      expect(ClockService.requiredBreakMinutes(0), 0);
      expect(ClockService.requiredBreakMinutes(360), 0);
    });
    test('30 min über 6 h bis 9 h', () {
      expect(ClockService.requiredBreakMinutes(361), 30);
      expect(ClockService.requiredBreakMinutes(540), 30);
    });
    test('45 min über 9 h', () {
      expect(ClockService.requiredBreakMinutes(541), 45);
      expect(ClockService.requiredBreakMinutes(720), 45);
    });
  });

  group('ClockService.netMinutes', () {
    test('brutto minus Pause', () {
      final net = ClockService.netMinutes(
        kommen: DateTime(2026, 6, 10, 9),
        gehen: DateTime(2026, 6, 10, 13),
        pauseMinuten: 30,
      );
      expect(net, 240 - 30);
    });
    test('clamp auf 0 bei übergroßer Pause', () {
      final net = ClockService.netMinutes(
        kommen: DateTime(2026, 6, 10, 9),
        gehen: DateTime(2026, 6, 10, 9, 20),
        pauseMinuten: 60,
      );
      expect(net, 0);
    });
  });

  group('ClockService.effectivePauseMinutes', () {
    test('explizite Pause hat Vorrang', () {
      final pause = ClockService.effectivePauseMinutes(
        kommen: DateTime(2026, 6, 10, 8),
        gehen: DateTime(2026, 6, 10, 18),
        pauseMinuten: 15,
      );
      expect(pause, 15);
    });
    test('Auto-Pflichtpause ohne Angabe: 8 h → 30 min', () {
      final pause = ClockService.effectivePauseMinutes(
        kommen: DateTime(2026, 6, 10, 8),
        gehen: DateTime(2026, 6, 10, 16),
      );
      expect(pause, 30);
    });
    test('Auto-Pflichtpause ohne Angabe: 10 h → 45 min', () {
      final pause = ClockService.effectivePauseMinutes(
        kommen: DateTime(2026, 6, 10, 8),
        gehen: DateTime(2026, 6, 10, 18),
      );
      expect(pause, 45);
    });
    test('negative explizite Pause → 0', () {
      final pause = ClockService.effectivePauseMinutes(
        kommen: DateTime(2026, 6, 10, 8),
        gehen: DateTime(2026, 6, 10, 12),
        pauseMinuten: -5,
      );
      expect(pause, 0);
    });
  });

  group('ClockService.runningMinutes / needsForceClose', () {
    test('Laufzeit ≥ 0 (auch bei negativer Differenz)', () {
      final kommen = DateTime(2026, 6, 10, 9);
      expect(
        ClockService.runningMinutes(
            kommen: kommen, now: DateTime(2026, 6, 10, 11)),
        120,
      );
      expect(
        ClockService.runningMinutes(
            kommen: kommen, now: DateTime(2026, 6, 10, 8)),
        0,
      );
    });
    test('Force-Close erst über 10 h', () {
      final kommen = DateTime(2026, 6, 10, 8);
      expect(
        ClockService.needsForceClose(
            kommen: kommen, now: DateTime(2026, 6, 10, 18)), // genau 10 h
        isFalse,
      );
      expect(
        ClockService.needsForceClose(
            kommen: kommen, now: DateTime(2026, 6, 10, 18, 1)),
        isTrue,
      );
    });
  });

  group('ClockService.needsClarification', () {
    test('Kommen von gestern → Klärung', () {
      expect(
        ClockService.needsClarification(
          kommen: DateTime(2026, 6, 9, 22),
          now: DateTime(2026, 6, 10, 7),
        ),
        isTrue,
      );
    });
    test('selber Tag → keine Klärung', () {
      expect(
        ClockService.needsClarification(
          kommen: DateTime(2026, 6, 10, 8),
          now: DateTime(2026, 6, 10, 17),
        ),
        isFalse,
      );
    });
  });

  group('looksForgotten (ZV-2.3a)', () {
    test('unter 12 h → nicht vergessen', () {
      expect(
        ClockService.looksForgotten(
          kommen: DateTime(2026, 6, 10, 8),
          now: DateTime(2026, 6, 10, 18), // 10 h
        ),
        isFalse,
      );
    });
    test('über 12 h → wahrscheinlich vergessen', () {
      expect(
        ClockService.looksForgotten(
          kommen: DateTime(2026, 6, 10, 8),
          now: DateTime(2026, 6, 10, 21), // 13 h
        ),
        isTrue,
      );
    });
  });
}
