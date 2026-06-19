import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';

/// Prueft, ob ein Fehler transient (voruebergehend) ist und ein Retry sinnvoll
/// erscheint. NUR Infrastruktur-/Netzfehler sind transient — fachliche oder
/// Berechtigungsfehler werden NIE wiederholt.
bool isTransientError(Object error) {
  if (error is TimeoutException) {
    return true;
  }
  if (error is FirebaseException) {
    final code = error.code;
    return code == 'unavailable' || code == 'deadline-exceeded';
  }
  return false;
}

/// Fuehrt eine **idempotente** Operation mit exponentiellem Backoff + Jitter
/// aus und wiederholt sie ausschliesslich bei transienten Fehlern
/// ([isTransientError]). Alles andere (StateError, `permission-denied`,
/// `failed-precondition`/ComplianceRejected, …) wird sofort rethrown.
///
/// Wichtig: Nur fuer Operationen verwenden, deren Mehrfachausfuehrung
/// folgenlos ist (stabile Doc-IDs / set(merge:true)).
///
/// [baseDelay] = Basiswartezeit; effektive Wartezeit waechst exponentiell
/// (`base * 2^(versuch-1)`), gedeckelt durch [maxDelay], mit vollem Jitter
/// (zufaellig zwischen 0 und dem gedeckelten Wert). [baseDelay] == [Duration.zero]
/// ergibt sofortige Wiederholungen (fuer Tests).
Future<T> retryTransient<T>(
  Future<T> Function() action, {
  int maxAttempts = 3,
  Duration baseDelay = const Duration(milliseconds: 200),
  Duration maxDelay = const Duration(seconds: 5),
  math.Random? random,
  Future<void> Function(Duration delay)? sleep,
  void Function(Object error, int attempt)? onRetry,
}) async {
  assert(maxAttempts >= 1, 'maxAttempts muss >= 1 sein');
  final rng = random ?? math.Random();
  final sleepFn = sleep ?? Future<void>.delayed;
  var attempt = 0;
  while (true) {
    attempt++;
    try {
      return await action();
    } catch (error) {
      if (attempt >= maxAttempts || !isTransientError(error)) {
        rethrow;
      }
      onRetry?.call(error, attempt);
      final expMs = baseDelay.inMilliseconds * (1 << (attempt - 1));
      final cappedMs = math.min(expMs, maxDelay.inMilliseconds);
      final delayMs = cappedMs <= 0 ? 0 : rng.nextInt(cappedMs + 1);
      await sleepFn(Duration(milliseconds: delayMs));
    }
  }
}
