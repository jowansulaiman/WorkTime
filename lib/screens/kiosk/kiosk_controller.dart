import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/app_user.dart';

/// Aktive Kiosk-Anmeldung am geteilten Laden-Tablet.
///
/// Hält den aktuell am Kiosk angemeldeten Mitarbeiter und einen
/// Inaktivitäts-Timer (Auto-Logout nach [inactivityTimeout], Default 90 s — E8).
/// **Wichtig:** Es findet KEIN Firebase-Identitätswechsel statt — der Mitarbeiter
/// ist hier ein reiner UI-Session-Zustand. In Increment 2 wird die Anmeldung
/// server-geprüft (`kioskBeginSession`) und sensible Writes (Stempeln) laufen
/// über eine Callable; in Increment 0 ist es ein lokaler Dev-Pfad.
class KioskController extends ChangeNotifier {
  KioskController({this.inactivityTimeout = const Duration(seconds: 90)});

  final Duration inactivityTimeout;

  AppUserProfile? _employee;
  String? _sessionId;
  Timer? _logoutTimer;
  DateTime? _expiresAt;
  bool _disposed = false;

  /// Der aktuell angemeldete Mitarbeiter (oder `null` = Leerlauf-Board).
  AppUserProfile? get employee => _employee;
  bool get hasSession => _employee != null;

  /// Server-Session-ID (`sid`) der aktiven Anmeldung; im Dev-Pfad `'dev-local'`.
  /// Für serverseitige Aktionen (z. B. `kioskClockPunch`) nötig.
  String? get sessionId => _sessionId;

  /// Zeitpunkt des automatischen Logouts (für einen sichtbaren Countdown).
  DateTime? get expiresAt => _expiresAt;

  void login(AppUserProfile employee, {String? sid}) {
    _employee = employee;
    _sessionId = sid;
    _restartTimer();
    _safeNotify();
  }

  /// Aktivität registrieren → Auto-Logout-Timer zurücksetzen.
  void touch() {
    if (_employee != null) _restartTimer();
  }

  void logout() {
    _employee = null;
    _sessionId = null;
    _logoutTimer?.cancel();
    _logoutTimer = null;
    _expiresAt = null;
    _safeNotify();
  }

  void _restartTimer() {
    _logoutTimer?.cancel();
    _expiresAt = DateTime.now().add(inactivityTimeout);
    _logoutTimer = Timer(inactivityTimeout, logout);
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _logoutTimer?.cancel();
    super.dispose();
  }
}

/// **Dev-PIN-Speicher (Increment 0, NUR Offline-/Demo-Pfad).**
///
/// Lokaler 4-stelliger PIN je Mitarbeiter in [SharedPreferences]. Ersetzt in
/// Increment 2 vollständig die server-geprüfte PIN (`userSecrets/{uid}` +
/// `kioskBeginSession`-Callable, scrypt-Hash, Rate-Limit). Hier bewusst KEIN
/// Hashing/Rate-Limit — ausschließlich, um die Anmelde-UX offline durchspielen
/// zu können. Ohne gesetzte PIN gilt die Demo-PIN [demoPin].
class KioskPinStore {
  KioskPinStore._();

  /// Demo-Standard-PIN, falls ein Mitarbeiter noch keine eigene gesetzt hat.
  static const String demoPin = '1234';

  static const String _prefix = 'kiosk_dev_pin_';

  static Future<String?> getPin(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$uid');
  }

  static Future<void> setPin(String uid, String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$uid', pin);
  }

  /// Prüft [pin] gegen die gespeicherte PIN des Mitarbeiters; ohne gespeicherte
  /// PIN wird die [demoPin] akzeptiert.
  static Future<bool> verify(String uid, String pin) async {
    final stored = await getPin(uid);
    return pin == (stored ?? demoPin);
  }
}

/// **Geräte-Einstellung: der lokal gewählte Laden dieses Kiosk-Tablets.**
///
/// Anders als der PIN NICHT pro Nutzer, sondern **pro Gerät** — einmalig am
/// Tablet aus einer Klarnamen-Liste gewählt und in [SharedPreferences] gemerkt.
/// Ein `APP_KIOSK_SITE_ID`-dart-define hat Vorrang (vorkonfigurierte Geräte).
class KioskDeviceStore {
  KioskDeviceStore._();

  static const String _siteKey = 'kiosk_device_site_id';

  static Future<String?> getSiteId() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_siteKey);
    return (value == null || value.isEmpty) ? null : value;
  }

  static Future<void> setSiteId(String siteId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_siteKey, siteId);
  }
}
