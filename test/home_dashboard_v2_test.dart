import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/ui/app_hero_card.dart';

import 'support/router_harness.dart';

/// Integrationstest fuer Schritt 4 (Home-Dashboards V2): pumpt die echte App
/// (go_router-Shell) und prueft, dass bei aktivem `redesign_v2`-Flag die
/// V2-Dashboards gewaehlt werden — erkannt an [AppHeroCard] (V2-only). Ohne Flag
/// bleibt es bei V1 (keine AppHeroCard).

const _admin = AppUserProfile(
  uid: 'admin-1',
  orgId: 'org-1',
  email: 'admin@example.com',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Admin'),
);
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

  testWidgets('Employee + Flag an -> V2-Dashboard (AppHeroCard)',
      (tester) async {
    final h = await pumpApp(tester, profile: _employee, flagOn: true);
    expect(find.byType(AppHeroCard), findsOneWidget);
    expect(find.text('Krank melden'), findsOneWidget);
    await h.cleanup();
  });

  testWidgets('Admin + Flag an -> V2-Dashboard (AppHeroCard + Plan oeffnen)',
      (tester) async {
    final h = await pumpApp(tester, profile: _admin, flagOn: true);
    expect(find.byType(AppHeroCard), findsOneWidget);
    expect(find.text('Plan oeffnen'), findsOneWidget);
    await h.cleanup();
  });

  testWidgets('Employee + Flag aus -> V1 (keine AppHeroCard)', (tester) async {
    final h = await pumpApp(tester, profile: _employee, flagOn: false);
    expect(find.byType(AppHeroCard), findsNothing);
    await h.cleanup();
  });

  testWidgets('Laufzeit-Override schaltet das Home-Layout live V1 -> V2',
      (tester) async {
    final h = await pumpApp(tester, profile: _employee, flagOn: false);
    // Start ohne Flag/Override -> V1-Layout (keine AppHeroCard).
    expect(find.byType(AppHeroCard), findsNothing);

    // Schalter umlegen (wie der Einstellungs-Toggle) -> Home muss live auf das
    // V2-Layout wechseln (refreshListenable enthaelt den ThemeProvider).
    await h.theme.setRedesignV2Override(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AppHeroCard), findsOneWidget);

    await h.cleanup();
  });
}
