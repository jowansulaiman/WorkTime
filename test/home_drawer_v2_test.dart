import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/widgets/app_nav_menu.dart';

import 'support/router_harness.dart';

/// Shell-Integrationstest fuer das V2-Slide-in-Menue: in V2 verschwindet der
/// Profil-Tab aus der Bottom-Nav (4 Kern-Tabs), der ☰-Avatar oeffnet das
/// [AppNavMenu], auf Desktop oeffnet der Rail-Profil-Header den endDrawer. In V1
/// bleibt alles wie bisher (Profil als 5. Tab, kein Drawer).

const _employee = AppUserProfile(
  uid: 'emp-1',
  orgId: 'org-1',
  email: 'peter@example.com',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Peter'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => initializeDateFormatting('de_DE'));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  testWidgets('V2 mobil: kein Profil-Tab, ☰ oeffnet das Menue',
      (tester) async {
    // Breite < 600 => Bottom-Nav; bewusst roomy, um den (orthogonalen, schmal-
    // breiten) Dashboard-Überlauf nicht mitzutesten. Höhe lässt die Drawer-
    // ListView alle Einträge bauen.
    final h = await pumpApp(
      tester,
      profile: _employee,
      flagOn: true,
      size: const Size(580, 1200),
    );

    // Profil ist nicht mehr in der Bottom-Nav; das Menue ist noch geschlossen.
    expect(find.text('Profil'), findsNothing);
    expect(find.byType(AppNavMenu), findsNothing);

    // ☰-Avatar oeffnet das Slide-in-Menue.
    expect(find.byTooltip('Menü'), findsOneWidget);
    await tester.tap(find.byTooltip('Menü'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AppNavMenu), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);

    await h.cleanup();
  });

  testWidgets('V2 Desktop: Rail-Profil-Header oeffnet endDrawer',
      (tester) async {
    final h = await pumpApp(
      tester,
      profile: _employee,
      flagOn: true,
      size: const Size(1400, 1600),
    );

    expect(find.byType(AppNavMenu), findsNothing);

    // Der Account-Knopf unten in der V2-Rail oeffnet das Slide-in-Menue.
    await tester.tap(find.byTooltip('Menü öffnen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AppNavMenu), findsOneWidget);

    await h.cleanup();
  });

  testWidgets('V1 bleibt unveraendert: Profil-Tab, kein Drawer/Menue',
      (tester) async {
    final h = await pumpApp(
      tester,
      profile: _employee,
      flagOn: false,
      size: const Size(400, 900),
    );

    expect(find.text('Profil'), findsWidgets); // Bottom-Nav-Tab
    expect(find.byType(AppNavMenu), findsNothing);
    expect(find.byTooltip('Menü'), findsNothing);

    await h.cleanup();
  });
}
