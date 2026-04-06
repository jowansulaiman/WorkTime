// lib/providers/theme_provider.dart

import 'package:flutter/material.dart';
import '../services/database_service.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  static const Locale _defaultLocale = Locale('de', 'DE');

  ThemeMode get themeMode => _themeMode;
  Locale get locale => _defaultLocale;

  Future<void> init() async {
    final saved = await DatabaseService.getLocalSetting('theme_mode');
    _themeMode = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    await DatabaseService.removeLocalSetting('locale');

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
