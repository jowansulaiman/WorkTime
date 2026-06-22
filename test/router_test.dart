import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/screens/auth_screen.dart';
import 'package:worktime_app/screens/force_update_screen.dart';
import 'package:worktime_app/screens/inventory_screen.dart';
import 'package:worktime_app/screens/team_management_screen.dart';
import 'package:worktime_app/services/database_service.dart';

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
    expect(find.byType(AuthScreen), findsOneWidget);
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

  testWidgets('/scanner ausserhalb echter Mobil-Plattform wird umgeleitet',
      (tester) async {
    // Desktop-Plattform erzwingen -> MobileBreakpoints.isNativeMobile == false,
    // der Scanner-Deep-Link ist dann nicht erlaubt und landet wieder auf '/'.
    // (Unter `flutter test` meldet die Umgebung sonst Android.) Der Override muss
    // im Test-Body zurückgesetzt werden (vor dem Invarianten-Check, nicht erst im
    // tearDown).
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final h = await pumpApp(
        tester,
        profile: _admin,
        initialLocation: '/scanner',
      );
      expect(_loc(h.router), '/');
      await h.cleanup();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
