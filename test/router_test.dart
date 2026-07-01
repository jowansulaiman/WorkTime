import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/screens/auth_screen.dart';
import 'package:worktime_app/screens/auth_screen_v2.dart';
import 'package:worktime_app/screens/force_update_screen.dart';
import 'package:worktime_app/screens/inventory_screen.dart';
import 'package:worktime_app/screens/team_management_screen.dart';
import 'package:worktime_app/screens/zeitwirtschaft/abwesenheiten_screen.dart';
import 'package:worktime_app/screens/zeitwirtschaft/abwesenheitskalender_screen.dart';
import 'package:worktime_app/screens/zeitwirtschaft/lohnlauf_screen.dart';
import 'package:worktime_app/screens/zeitwirtschaft/mitarbeiterabschluss_screen.dart';
import 'package:worktime_app/screens/zeitwirtschaft/monatsabschluss_screen.dart';
import 'package:worktime_app/screens/zeitwirtschaft/stempel_screen.dart';
import 'package:worktime_app/screens/zeitwirtschaft/stundenkonto_screen.dart';
import 'package:worktime_app/screens/zeitwirtschaft/zeit_section_placeholder.dart';
import 'package:worktime_app/screens/zeitwirtschaft/zeiterfassung_screen.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/routing/shell_tab.dart';

import 'support/router_harness.dart';

/// Router-Tests: Deep-Links rendern den richtigen Screen, der Gate-Redirect
/// reproduziert die alte _AuthGate-Logik (Auth, Force-Update, gesperrt) und
/// das URL-Permission-Gating leitet unberechtigte Deep-Links auf '/' um.

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
const _blocked = AppUserProfile(
  uid: 'blk-1',
  orgId: 'org-1',
  email: 'blk@example.com',
  role: UserRole.employee,
  isActive: false,
  settings: UserSettings(name: 'Blocked'),
);

String _loc(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => initializeDateFormatting('de_DE'));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  testWidgets('Deep-Link /warenwirtschaft (Admin) rendert InventoryScreen',
      (tester) async {
    final h = await pumpApp(
      tester,
      profile: _admin,
      initialLocation: '/warenwirtschaft',
    );
    expect(find.byType(InventoryScreen), findsOneWidget);
    expect(_loc(h.router), '/warenwirtschaft');
    await h.cleanup();
  });

  testWidgets('Deep-Link /team (Admin) rendert TeamManagementScreen',
      (tester) async {
    final h = await pumpApp(
      tester,
      profile: _admin,
      initialLocation: '/team',
    );
    expect(find.byType(TeamManagementScreen), findsOneWidget);
    expect(_loc(h.router), '/team');
    await h.cleanup();
  });

  testWidgets('Unauth Deep-Link wird auf /anmelden umgeleitet', (tester) async {
    final h = await pumpApp(
      tester,
      profile: null,
      initialLocation: '/warenwirtschaft',
    );
    // Unauth = keine org-Config → produktiver Default V2 → AuthScreenV2.
    expect(find.byType(AuthScreenV2), findsOneWidget);
    expect(_loc(h.router), '/anmelden');
    await h.cleanup();
  });

  testWidgets('Deep-Link /team ohne Admin-Recht wird auf / umgeleitet',
      (tester) async {
    final h = await pumpApp(
      tester,
      profile: _employee,
      initialLocation: '/team',
    );
    expect(find.byType(TeamManagementScreen), findsNothing);
    expect(_loc(h.router), '/');
    await h.cleanup();
  });

  testWidgets('Force-Update-Gate zeigt ForceUpdateScreen', (tester) async {
    final h = await pumpApp(
      tester,
      profile: _admin,
      forceUpdate: true,
      initialLocation: '/',
    );
    expect(find.byType(ForceUpdateScreen), findsOneWidget);
    expect(_loc(h.router), '/aktualisierung');
    await h.cleanup();
  });

  testWidgets('Deaktiviertes Konto wird auf /gesperrt umgeleitet',
      (tester) async {
    final h = await pumpApp(
      tester,
      profile: _blocked,
      initialLocation: '/warenwirtschaft',
    );
    expect(find.byType(AccessBlockedScreen), findsOneWidget);
    expect(_loc(h.router), '/gesperrt');
    await h.cleanup();
  });

  testWidgets('Tab-Wechsel via go() aktualisiert die URL (IndexedStack-Shell)',
      (tester) async {
    final h = await pumpApp(tester, profile: _admin, initialLocation: '/');
    expect(_loc(h.router), '/');

    h.router.go('/zeit');
    await tester.pumpAndSettle();
    expect(_loc(h.router), '/zeit');

    h.router.go('/plan');
    await tester.pumpAndSettle();
    expect(_loc(h.router), '/plan');

    // Zurück auf /zeit: kein Neuaufbau-Crash, Branch-State-Erhalt (IndexedStack).
    h.router.go('/zeit');
    await tester.pumpAndSettle();
    expect(_loc(h.router), '/zeit');

    await h.cleanup();
  });

  testWidgets(
      'Deep-Link /zeit/erfassung (Sub-Route) rendert die Zeiterfassung',
      (tester) async {
    // Verifiziert, dass die `/zeit/*`-Section-Routen NICHT vom `/zeit`-Tab-
    // Branch verschluckt werden (geteiltes Pfad-Präfix).
    final h = await pumpApp(
      tester,
      profile: _admin,
      initialLocation: AppRoutes.zeitErfassung,
    );
    expect(find.byType(ZeiterfassungScreen), findsOneWidget);
    expect(_loc(h.router), '/zeit/erfassung');
    await h.cleanup();
  });

  testWidgets('Deep-Link /zeit/stempeln rendert den Stempel-Screen',
      (tester) async {
    final h = await pumpApp(
      tester,
      profile: _employee,
      initialLocation: AppRoutes.zeitStempeln,
    );
    expect(find.byType(StempelScreen), findsOneWidget);
    expect(_loc(h.router), '/zeit/stempeln');
    await h.cleanup();
  });

  testWidgets('Deep-Link /zeit/stundenkonto rendert das Stundenkonto',
      (tester) async {
    final h = await pumpApp(
      tester,
      profile: _employee,
      initialLocation: AppRoutes.zeitStundenkonto,
    );
    expect(find.byType(StundenkontoScreen), findsOneWidget);
    expect(_loc(h.router), '/zeit/stundenkonto');
    await h.cleanup();
  });

  testWidgets('Deep-Link /zeit/abwesenheiten rendert die Abwesenheiten-Liste',
      (tester) async {
    final h = await pumpApp(
      tester,
      profile: _employee,
      initialLocation: AppRoutes.zeitAbwesenheiten,
    );
    expect(find.byType(AbwesenheitenScreen), findsOneWidget);
    expect(find.byType(ZeitSectionPlaceholder), findsNothing);
    expect(_loc(h.router), '/zeit/abwesenheiten');
    await h.cleanup();
  });

  testWidgets(
      'Deep-Link /zeit/abwesenheiten/kalender rendert den Abwesenheitskalender',
      (tester) async {
    final h = await pumpApp(
      tester,
      profile: _admin,
      initialLocation: AppRoutes.zeitAbwesenheitenKalender,
    );
    expect(find.byType(AbwesenheitskalenderScreen), findsOneWidget);
    expect(find.byType(ZeitSectionPlaceholder), findsNothing);
    expect(_loc(h.router), '/zeit/abwesenheiten/kalender');
    await h.cleanup();
  });

  testWidgets(
      'Deep-Link /zeit/abwesenheiten/kalender (Mitarbeiter) rendert die '
      'eigene Zeile', (tester) async {
    final h = await pumpApp(
      tester,
      profile: _employee,
      initialLocation: AppRoutes.zeitAbwesenheitenKalender,
    );
    expect(find.byType(AbwesenheitskalenderScreen), findsOneWidget);
    expect(_loc(h.router), '/zeit/abwesenheiten/kalender');
    await h.cleanup();
  });

  testWidgets(
      'Deep-Link /zeit/lohnlauf ohne Admin-Recht wird auf / umgeleitet',
      (tester) async {
    final h = await pumpApp(
      tester,
      profile: _employee,
      initialLocation: AppRoutes.zeitLohnlauf,
    );
    expect(find.byType(ZeitSectionPlaceholder), findsNothing);
    expect(_loc(h.router), '/');
    await h.cleanup();
  });

  testWidgets('Deep-Link /zeit/lohnlauf (Admin) rendert den Lohnlauf',
      (tester) async {
    final h = await pumpApp(
      tester,
      profile: _admin,
      initialLocation: AppRoutes.zeitLohnlauf,
    );
    expect(find.byType(LohnlaufScreen), findsOneWidget);
    expect(find.byType(ZeitSectionPlaceholder), findsNothing);
    expect(_loc(h.router), '/zeit/lohnlauf');
    await h.cleanup();
  });

  testWidgets('Deep-Link /zeit/monatsabschluss rendert „Mein Monatsabschluss"',
      (tester) async {
    final h = await pumpApp(
      tester,
      profile: _employee,
      initialLocation: AppRoutes.zeitMonatsabschluss,
    );
    expect(find.byType(MonatsabschlussScreen), findsOneWidget);
    expect(find.byType(ZeitSectionPlaceholder), findsNothing);
    expect(_loc(h.router), '/zeit/monatsabschluss');
    await h.cleanup();
  });

  testWidgets(
      'Deep-Link /zeit/mitarbeiterabschluss (Admin) rendert den Hub',
      (tester) async {
    final h = await pumpApp(
      tester,
      profile: _admin,
      initialLocation: AppRoutes.zeitMitarbeiterabschluss,
    );
    expect(find.byType(MitarbeiterabschlussScreen), findsOneWidget);
    expect(_loc(h.router), '/zeit/mitarbeiterabschluss');
    await h.cleanup();
  });

  testWidgets(
      'Deep-Link /zeit/mitarbeiterabschluss ohne Admin wird auf / umgeleitet',
      (tester) async {
    final h = await pumpApp(
      tester,
      profile: _employee,
      initialLocation: AppRoutes.zeitMitarbeiterabschluss,
    );
    expect(find.byType(MitarbeiterabschlussScreen), findsNothing);
    expect(_loc(h.router), '/');
    await h.cleanup();
  });

  testWidgets('/scanner ohne Inventar-Recht wird auf / umgeleitet',
      (tester) async {
    // Der Scanner ist plattformunabhaengig erreichbar (fester Bottomnav-Tab),
    // aber an canUseScanner gebunden: ein Mitarbeiter ohne Inventar-Verwaltung
    // (canManageShifts == false) wird vom Deep-Link auf '/' zurueckgeleitet.
    final h = await pumpApp(
      tester,
      profile: _employee,
      initialLocation: '/scanner',
    );
    expect(_loc(h.router), '/');
    await h.cleanup();
  });
}
