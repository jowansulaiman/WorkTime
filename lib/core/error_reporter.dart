import 'app_logger.dart';

/// Zentrale Senke für unbehandelte Fehler.
///
/// Heute: strukturiertes Logging via [AppLogger] (Release-fest, im Gegensatz
/// zu `debugPrint`). Das schließt den Plan-Gap, dass globale Fehler-Handler im
/// Release-Build spurlos verschwanden.
///
/// Einhängepunkt für echtes Crash-Reporting: ein externer Adapter (Firebase
/// Crashlytics / Sentry) kann sich über [externalSink] registrieren, ohne dass
/// `main.dart` oder die Provider den konkreten Anbieter kennen. Welle 2 des
/// Plans (`no-crash-reporting`) fügt `firebase_crashlytics` als Dependency
/// hinzu und setzt in `main()`:
///
/// ```dart
/// ErrorReporter.externalSink = (error, stack, {required fatal, context}) =>
///     FirebaseCrashlytics.instance.recordError(error, stack, fatal: fatal);
/// ```
class ErrorReporter {
  ErrorReporter._();

  /// Optionaler externer Sink (z. B. Crashlytics). `null`, bis registriert.
  static void Function(
    Object error,
    StackTrace stack, {
    required bool fatal,
    String? context,
  })? externalSink;

  /// Meldet einen Fehler an Log und (falls vorhanden) externes Reporting.
  /// `fatal` markiert nicht behebbare Abstürze (Zone-/Platform-Fehler).
  static void report(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) {
    final stackTrace = stack ?? StackTrace.current;
    AppLogger.error(
      context ?? 'Unbehandelter Fehler',
      error: error,
      stackTrace: stackTrace,
      fields: {'fatal': fatal},
    );

    final sink = externalSink;
    if (sink == null) return;
    try {
      sink(error, stackTrace, fatal: fatal, context: context);
    } catch (sinkError, sinkStack) {
      // Reporting darf die App niemals selbst zum Absturz bringen.
      AppLogger.warning(
        'Externer Error-Sink hat selbst eine Ausnahme geworfen',
        error: sinkError,
        stackTrace: sinkStack,
      );
    }
  }
}
