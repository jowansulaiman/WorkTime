// lib/providers/theme_provider.dart

import 'package:flutter/material.dart';
import '../services/database_service.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  static const Locale _defaultLocale = Locale('de', 'DE');
  bool? _redesignV2Override;

  ThemeMode get themeMode => _themeMode;
  Locale get locale => _defaultLocale;

  /// Laufzeit-Override fuer das Signal-Teal-Redesign (`redesign_v2`): `true`/
  /// `false` erzwingen V2/V1 live, `null` = normale Aufloesung (Dev-Define bzw.
  /// org-Flag). Persistiert; wird in [RedesignFlags] und der Theme-Wahl in
  /// `main.dart` vorrangig beruecksichtigt.
  bool? get redesignV2Override => _redesignV2Override;

  Future<void> init() async {
    final saved = await DatabaseService.getLocalSetting('theme_mode');
    _themeMode = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    final redesign = await DatabaseService.getLocalSetting('redesign_v2_override');
    _redesignV2Override = switch (redesign) {
      'on' => true,
      'off' => false,
      _ => null,
    };

    await DatabaseService.removeLocalSetting('locale');

    notifyListeners();
  }

  /// Setzt den Laufzeit-Override (`null` loescht ihn = normale Aufloesung).
  Future<void> setRedesignV2Override(bool? value) async {
    _redesignV2Override = value;
    if (value == null) {
      await DatabaseService.removeLocalSetting('redesign_v2_override');
    } else {
      await DatabaseService.saveLocalSetting(
        'redesign_v2_override',
        value ? 'on' : 'off',
      );
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    await DatabaseService.saveLocalSetting('theme_mode', value);
    notifyListeners();
  }
}
