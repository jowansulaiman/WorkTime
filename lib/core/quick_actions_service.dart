import 'package:flutter/foundation.dart';
import 'package:quick_actions/quick_actions.dart';

import '../routing/shell_tab.dart';

/// Verbindet das System-Schnellaktionen-Menü (Long-Press auf das App-Icon,
/// iOS „Home Screen Quick Actions" / Android „App Shortcuts") mit dem
/// go_router. Auswahl einer Aktion setzt eine „pending route", die der
/// Gate-Redirect (`_gateRedirect` in `routing/app_router.dart`) erst zustellt,
/// sobald Auth/Profil aufgelöst & aktiv sind — so überlebt ein Cold-Start
/// (App per Schnellaktion gestartet) korrekt den Login.
///
/// Bewusst KEIN Provider: die Aktion feuert plattformseitig außerhalb des
/// Widget-Baums und muss auch vor dem ersten Frame ein Ziel merken können.
class QuickActionsService {
  QuickActionsService._();

  static final QuickActionsService instance = QuickActionsService._();

  // Stabile Aktions-Typen (Bezeichner im OS-Menü, dürfen sich nicht ändern).
  static const String typeStempeln = 'action_stempeln';
  static const String typeSchichtplan = 'action_schichtplan';
  static const String typeScanner = 'action_scanner';

  final QuickActions _quickActions = const QuickActions();
  bool _initialized = false;
  String? _pendingRoute;

  /// Vom App-Widget injiziert: führt die eigentliche Navigation aus
  /// (`context.go`). Bei Warmstart sofort aufgerufen; bei Cold-Start evtl. noch
  /// `null` → dann zählt allein die `pending route`.
  void Function(String route)? navigate;

  /// Nur Mobile hat ein Long-Press-Schnellaktionen-Menü. Web/Desktop = No-op.
  bool get _isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Vom Gate-Redirect konsumiert: liefert die offene Schnellaktions-Route
  /// (falls vorhanden) und löscht sie. Idempotent → kein Redirect-Loop.
  String? takePendingRoute() {
    final route = _pendingRoute;
    _pendingRoute = null;
    return route;
  }

  /// Registriert den Handler und legt die Einträge des Long-Press-Menüs an.
  /// Mehrfachaufruf ist sicher (einmalige Initialisierung).
  Future<void> init() async {
    if (_initialized || !_isSupported) return;
    _initialized = true;

    _quickActions.initialize((String type) {
      final route = _routeForType(type);
      if (route == null) return;
      _pendingRoute = route;
      // Warmstart (Router montiert & Auth fertig): `navigate` springt direkt
      // ans Ziel; der Redirect räumt die pending route dabei als No-op ab.
      // Sonst (Router noch nicht montiert → `navigate` no-op, ODER Auth noch
      // nicht aufgelöst → Redirect hält am Gate): die Route bleibt pending und
      // wird im Gate-Redirect zugestellt, sobald Auth/Profil bereitstehen.
      navigate?.call(route);
    });

    await _quickActions.setShortcutItems(const <ShortcutItem>[
      ShortcutItem(type: typeStempeln, localizedTitle: 'Stempeln'),
      ShortcutItem(type: typeSchichtplan, localizedTitle: 'Schichtplan'),
      ShortcutItem(type: typeScanner, localizedTitle: 'Scanner'),
    ]);
  }

  String? _routeForType(String type) {
    switch (type) {
      case typeStempeln:
        return AppRoutes.zeitStempeln;
      case typeSchichtplan:
        return shellTabPaths[ShellTab.plan];
      case typeScanner:
        return AppRoutes.scanner;
    }
    return null;
  }
}
