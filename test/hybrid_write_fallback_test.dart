import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/hybrid_write_fallback.dart';

class _Harness with HybridWriteFallback {
  _Harness({required this.usesHybridStorage});
  @override
  final bool usesHybridStorage;
  @override
  String get hybridFallbackLabel => 'Test';
}

FirebaseException _fb(String code) =>
    FirebaseException(plugin: 'firestore', code: code);

void main() {
  group('HybridWriteFallback (Q1-Positivliste)', () {
    test('Erfolg → true', () async {
      final h = _Harness(usesHybridStorage: true);
      final ok = await h.tryFirestoreWrite('x', () async {});
      expect(ok, isTrue);
    });

    test('Hybrid + echter Offline-Fehler → lokaler Fallback (false)', () async {
      final h = _Harness(usesHybridStorage: true);
      expect(
        await h.tryFirestoreWrite('x', () async => throw _fb('unavailable')),
        isFalse,
      );
      expect(
        await h.tryFirestoreWrite(
            'x', () async => throw _fb('deadline-exceeded')),
        isFalse,
      );
      expect(
        await h.tryFirestoreWrite(
            'x', () async => throw TimeoutException('t')),
        isFalse,
      );
    });

    test('Hybrid + permission-denied → rethrow (KEIN stiller Fallback)',
        () async {
      final h = _Harness(usesHybridStorage: true);
      await expectLater(
        h.tryFirestoreWrite('x', () async => throw _fb('permission-denied')),
        throwsA(isA<FirebaseException>()),
      );
    });

    test('Hybrid + failed-precondition (fehlender Index) → rethrow', () async {
      final h = _Harness(usesHybridStorage: true);
      await expectLater(
        h.tryFirestoreWrite('x', () async => throw _fb('failed-precondition')),
        throwsA(isA<FirebaseException>()),
      );
    });

    test('cloud-only (kein Hybrid) → jeder Fehler rethrowt', () async {
      final h = _Harness(usesHybridStorage: false);
      await expectLater(
        h.tryFirestoreWrite('x', () async => throw _fb('unavailable')),
        throwsA(isA<FirebaseException>()),
      );
    });
  });
}
