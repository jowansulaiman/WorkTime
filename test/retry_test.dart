import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/retry.dart';

void main() {
  group('retryTransient', () {
    // Sofortige Wiederholungen ohne echte Wartezeit.
    Future<void> noSleep(Duration _) async {}

    test('wiederholt transiente Fehler bis zum Erfolg', () async {
      var attempts = 0;
      final result = await retryTransient<String>(
        () async {
          attempts++;
          if (attempts < 3) {
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'temporaer',
            );
          }
          return 'ok';
        },
        baseDelay: Duration.zero,
        sleep: noSleep,
      );

      expect(result, 'ok');
      expect(attempts, 3);
    });

    test('wirft nach Erschoepfen von maxAttempts', () async {
      var attempts = 0;
      await expectLater(
        retryTransient<void>(
          () async {
            attempts++;
            throw TimeoutException('zu langsam');
          },
          maxAttempts: 4,
          baseDelay: Duration.zero,
          sleep: noSleep,
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(attempts, 4);
    });

    test('wiederholt NICHT-transiente Fehler nicht', () async {
      var attempts = 0;
      await expectLater(
        retryTransient<void>(
          () async {
            attempts++;
            throw StateError('fachlicher Fehler');
          },
          baseDelay: Duration.zero,
          sleep: noSleep,
        ),
        throwsA(isA<StateError>()),
      );
      expect(attempts, 1, reason: 'StateError ist nicht transient');
    });

    test('failed-precondition (Compliance) wird nicht wiederholt', () async {
      var attempts = 0;
      await expectLater(
        retryTransient<void>(
          () async {
            attempts++;
            throw FirebaseFunctionsException(
              code: 'failed-precondition',
              message: 'Compliance',
            );
          },
          baseDelay: Duration.zero,
          sleep: noSleep,
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      expect(attempts, 1);
    });

    test('isTransientError klassifiziert korrekt', () {
      expect(
        isTransientError(
          FirebaseFunctionsException(code: 'unavailable', message: ''),
        ),
        isTrue,
      );
      expect(
        isTransientError(
          FirebaseFunctionsException(code: 'deadline-exceeded', message: ''),
        ),
        isTrue,
      );
      expect(isTransientError(TimeoutException('x')), isTrue);
      expect(isTransientError(StateError('x')), isFalse);
      expect(
        isTransientError(
          FirebaseFunctionsException(code: 'permission-denied', message: ''),
        ),
        isFalse,
      );
    });
  });
}
