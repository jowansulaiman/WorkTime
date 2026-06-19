import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/performance_service.dart';

void main() {
  group('PerformanceService.traceCriticalFlow', () {
    tearDown(() {
      PerformanceService.externalSink = null;
      PerformanceService.enabled = true;
    });

    test('meldet Name, Dauer und Metadaten an die Senke', () async {
      String? capturedName;
      Duration? capturedElapsed;
      Map<String, Object?>? capturedMeta;
      PerformanceService.externalSink = (name, elapsed, meta) {
        capturedName = name;
        capturedElapsed = elapsed;
        capturedMeta = meta;
      };

      final result = await PerformanceService.traceCriticalFlow(
        'work_add_entry',
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return 42;
        },
        metadata: const {'storage': 'hybrid'},
      );

      expect(result, 42);
      expect(capturedName, 'work_add_entry');
      expect(capturedElapsed, isNotNull);
      expect(capturedElapsed! >= Duration.zero, isTrue);
      expect(capturedMeta, const {'storage': 'hybrid'});
    });

    test('misst auch bei geworfener Exception und reicht sie durch', () async {
      var reported = false;
      PerformanceService.externalSink = (_, __, ___) => reported = true;

      await expectLater(
        PerformanceService.traceCriticalFlow<void>(
          'work_clock_in',
          () async => throw StateError('boom'),
        ),
        throwsStateError,
      );
      expect(reported, isTrue);
    });

    test('ohne Senke wirft nichts (Null-Safety)', () async {
      PerformanceService.externalSink = null;
      final result =
          await PerformanceService.traceCriticalFlow('x', () async => 'ok');
      expect(result, 'ok');
    });

    test('deaktiviert: führt Aktion aus, meldet aber nicht', () async {
      var reported = false;
      PerformanceService.externalSink = (_, __, ___) => reported = true;
      PerformanceService.enabled = false;

      final result =
          await PerformanceService.traceCriticalFlow('x', () async => 7);

      expect(result, 7);
      expect(reported, isFalse);
    });
  });
}
