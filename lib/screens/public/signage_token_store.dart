import 'package:shared_preferences/shared_preferences.dart';

/// Persistiert den zuletzt genutzten Display-Token des öffentlichen Werbe-
/// Players. Auf Web landet SharedPreferences im `localStorage` → der Fernseher
/// „merkt sich" sein Display über Neustarts hinweg. So genügt es, das Gerät
/// beim Booten auf die feste Adresse `…/anzeige` zu schicken: der Player nimmt
/// den gemerkten Token und startet die Werbung automatisch (ohne erneute
/// Code-Eingabe), solange der Browser den localStorage behält.
///
/// Bewusst eigener, ungescopeter Key (nicht über [DatabaseService]) — der Player
/// läuft ohne Login/Provider-Kette und ist an kein Nutzerprofil gebunden.
class SignageTokenStore {
  SignageTokenStore._();

  static const String _key = 'signage_last_token';

  static Future<void> save(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, trimmed);
  }

  static Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
