import 'package:flutter/widgets.dart';

import 'app_logger.dart';

/// Senke für Produkt-Telemetrie.
typedef AnalyticsSink = void Function(String event, Map<String, Object?> params);

/// Produkt-Telemetrie / Screen-Tracking (no-analytics-screen-tracking).
///
/// Bewusst datensparsam (DSGVO, EU/Deutsch): es werden **niemals** Namen,
/// E-Mails, uids oder vollständige Payloads gesendet — nur Screen-Namen, Rollen
/// und Anzahlen. Wie [ErrorReporter] ist die konkrete Implementierung
/// (z. B. firebase_analytics) über [externalSink] einhängbar, ohne die Aufrufer
/// zu ändern; ohne Senke werden Events im Debug nur geloggt. [enabled] erlaubt
/// ein Opt-out.
abstract final class AnalyticsService {
  static AnalyticsSink? externalSink;
  static bool enabled = true;

  /// Geteilter NavigatorObserver für Detail-Screens (Routenwechsel). Tab-Wechsel
  /// der Shell laufen index-basiert und werden separat per [logScreenView]
  /// gemeldet.
  static final NavigatorObserver observer = _AnalyticsNavigatorObserver();

  static void logEvent(String name, {Map<String, Object?> params = const {}}) {
    if (!enabled) {
      return;
    }
    AppLogger.debug('analytics: $name $params');
    externalSink?.call(name, params);
  }

  static void logScreenView(String screen, {String? role}) {
    logEvent('screen_view', params: {
      'screen': screen,
      if (role != null && role.isNotEmpty) 'role': role,
    });
  }
}

class _AnalyticsNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _log(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) {
      _log(newRoute);
    }
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  void _log(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || name.isEmpty) {
      return;
    }
    AnalyticsService.logScreenView(name);
  }
}
