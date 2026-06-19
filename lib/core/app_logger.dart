import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Log-Schweregrade in aufsteigender Wichtigkeit.
enum LogLevel { debug, info, warning, error }

/// Dünne, zentrale Logging-Abstraktion statt der ~40 verstreuten
/// `debugPrint`-Aufrufe in der App.
///
/// Verhalten:
/// - `debug`/`info`: nur im Debug-Build (`kDebugMode`), sonst No-op.
/// - `warning`/`error`: immer aktiv – auch im Release –, da `dart:developer`s
///   `log` (anders als `debugPrint`) im Release nicht verschluckt wird.
/// - PII-Schutz: [_redact] maskiert E-Mail-Adressen in Nachrichten/Feldern,
///   damit keine personenbezogenen Daten in Logs/Crash-Reports landen
///   (Plan-Gap `pii-in-logs`). UIDs daher nur über `fields` und bewusst loggen.
///
/// `error` reicht zusätzlich an [`ErrorReporter`](error_reporter.dart) weiter,
/// sobald dieser eingebunden ist – siehe dortige Doku.
class AppLogger {
  AppLogger._();

  static const String _name = 'worktime';

  static void debug(String message, {Map<String, Object?>? fields}) {
    if (!kDebugMode) return;
    _log(LogLevel.debug, message, fields: fields);
  }

  static void info(String message, {Map<String, Object?>? fields}) {
    if (!kDebugMode) return;
    _log(LogLevel.info, message, fields: fields);
  }

  static void warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) {
    _log(
      LogLevel.warning,
      message,
      error: error,
      stackTrace: stackTrace,
      fields: fields,
    );
  }

  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) {
    _log(
      LogLevel.error,
      message,
      error: error,
      stackTrace: stackTrace,
      fields: fields,
    );
  }

  static void _log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) {
    final buffer = StringBuffer(_redact(message));
    if (fields != null && fields.isNotEmpty) {
      buffer.write(' | ');
      buffer.write(
        fields.entries
            .map((entry) => '${entry.key}=${_redact('${entry.value}')}')
            .join(' '),
      );
    }
    developer.log(
      buffer.toString(),
      name: _name,
      level: _levelValue(level),
      error: error,
      stackTrace: stackTrace,
    );
  }

  static int _levelValue(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500;
      case LogLevel.info:
        return 800;
      case LogLevel.warning:
        return 900;
      case LogLevel.error:
        return 1000;
    }
  }

  static final RegExp _emailPattern =
      RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');

  /// Maskiert E-Mail-Adressen, z. B. `peter@example.com` -> `p***@example.com`.
  static String _redact(String input) {
    return input.replaceAllMapped(_emailPattern, (match) {
      final value = match.group(0)!;
      final at = value.indexOf('@');
      final domain = value.substring(at + 1);
      if (at <= 1) return '***@$domain';
      return '${value[0]}***@$domain';
    });
  }
}
