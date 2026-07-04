import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// **Screenshot-/Recents-Schutz (Passwortmanager PM-S10).** Setzt auf Android
/// `FLAG_SECURE` (blockiert Screenshots + verbirgt den Inhalt in der App-
/// Übersicht) über einen MethodChannel zur `MainActivity`.
///
/// **No-op** auf Web/iOS/Desktop (dort gibt es kein direktes FLAG_SECURE-
/// Äquivalent) und wenn der native Handler fehlt — dann bleibt der Schutz
/// bewusst aus (dokumentierte Grenze), ohne die App zu stören.
class ScreenSecurity {
  const ScreenSecurity._();

  static const MethodChannel _channel =
      MethodChannel('worktime/screen_security');

  /// Aktiviert den Screenshot-Schutz (vor dem Anzeigen sensibler Inhalte).
  static Future<void> enable() => _set('enable');

  /// Deaktiviert ihn wieder (nach dem Ausblenden).
  static Future<void> disable() => _set('disable');

  static Future<void> _set(String method) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod(method);
    } on PlatformException {
      // Native Aufruf fehlgeschlagen → still ignorieren.
    } on MissingPluginException {
      // Plattform ohne Handler (iOS/Desktop/Test) → no-op.
    }
  }
}
