import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/providers/theme_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/widgets/theme_mode_button.dart';

/// Widget-Test für den schnellen Hell/Dunkel-Umschalter [ThemeModeButton]:
/// Tippen wechselt sofort, langes Drücken öffnet die explizite Auswahl.
Future<void> _pump(WidgetTester tester, ThemeProvider provider) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>.value(
      value: provider,
      child: const MaterialApp(
        home: Scaffold(
          appBar: null,
          body: Center(child: ThemeModeButton()),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  testWidgets('zeigt das Auto-Icon im System-Modus', (tester) async {
    final provider = ThemeProvider();
    await _pump(tester, provider);
    expect(find.byIcon(Icons.brightness_auto_outlined), findsOneWidget);
    expect(provider.themeMode, ThemeMode.system);
  });

  testWidgets('Tippen wechselt weg von System (hell/dunkel)', (tester) async {
    final provider = ThemeProvider();
    await _pump(tester, provider);
    await tester.tap(find.byType(ThemeModeButton));
    await tester.pump();
    // Plattform-Helligkeit im Test ist hell → Tap schaltet auf Dunkel.
    expect(provider.themeMode, ThemeMode.dark);
  });

  testWidgets('Tippen schaltet zwischen hell und dunkel hin und her',
      (tester) async {
    final provider = ThemeProvider();
    await provider.setThemeMode(ThemeMode.dark);
    await _pump(tester, provider);
    await tester.tap(find.byType(ThemeModeButton));
    await tester.pump();
    expect(provider.themeMode, ThemeMode.light);
  });

  testWidgets('Langdruck öffnet die explizite Auswahl und setzt den Modus',
      (tester) async {
    final provider = ThemeProvider();
    await _pump(tester, provider);
    await tester.longPress(find.byType(ThemeModeButton));
    await tester.pumpAndSettle();

    expect(find.text('System'), findsOneWidget);
    expect(find.text('Hell'), findsOneWidget);
    expect(find.text('Dunkel'), findsOneWidget);

    await tester.tap(find.text('Dunkel'));
    await tester.pumpAndSettle();
    expect(provider.themeMode, ThemeMode.dark);
  });
}
