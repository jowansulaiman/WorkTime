import 'app_logger.dart';

/// Senke für RUM-/Performance-Signale (Custom Traces).
typedef PerformanceTraceSink = void Function(
  String traceName,
  Duration elapsed,
  Map<String, Object?> metadata,
);

/// Custom-Trace-Instrumentierung kritischer Abläufe (no-perf-traces-critical-flows).
///
/// Wie [ErrorReporter] und [AnalyticsService] ist die konkrete Implementierung
/// (z. B. firebase_performance) über [externalSink] einhängbar, ohne die
/// Aufrufer zu ändern; ohne Senke werden die gemessenen Dauern im Debug nur
/// geloggt. [enabled] erlaubt ein Opt-out. Bewusst dependency-frei gehalten,
/// damit kein Paket ohne lauffähigen Build verprobt werden muss (folgt dem in
/// Welle 1 etablierten Crashlytics-Präzedenzfall).
abstract final class PerformanceService {
  static PerformanceTraceSink? externalSink;
  static bool enabled = true;

  /// Misst die Dauer eines asynchronen kritischen Ablaufs ([action]) und meldet
  /// sie an die Senke. Der Rückgabewert/Fehler von [action] bleibt unverändert
  /// (die Messung läuft auch bei einer geworfenen Exception via `finally`).
  static Future<T> traceCriticalFlow<T>(
    String name,
    Future<T> Function() action, {
    Map<String, Object?> metadata = const {},
  }) async {
    if (!enabled) {
      return action();
    }
    final stopwatch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      stopwatch.stop();
      _report(name, stopwatch.elapsed, metadata);
    }
  }

  /// Synchrone Variante für rein lokale, potenziell teure Arbeit.
  static T traceSync<T>(
    String name,
    T Function() action, {
    Map<String, Object?> metadata = const {},
  }) {
    if (!enabled) {
      return action();
    }
    final stopwatch = Stopwatch()..start();
    try {
      return action();
    } finally {
      stopwatch.stop();
      _report(name, stopwatch.elapsed, metadata);
    }
  }

  static void _report(
    String name,
    Duration elapsed,
    Map<String, Object?> metadata,
  ) {
    AppLogger.debug('perf: $name ${elapsed.inMilliseconds}ms $metadata');
    externalSink?.call(name, elapsed, metadata);
  }
}
