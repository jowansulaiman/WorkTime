import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/theme/app_theme.dart';
import 'package:worktime_app/widgets/app_nav_menu.dart';

/// Isolierter Widget-Test fuer das Slide-in-Menue [AppNavMenu]: prueft die nach
/// Berechtigung gruppierten Eintraege, den authDisabled-Footer und die Callbacks
/// — ohne Provider-Stack, da das Widget bewusst rein praesentational ist.
const _admin = AppUserProfile(
  uid: 'admin-1',
  orgId: 'org-1',
  email: 'admin@example.com',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Sandra'),
);

// Mitarbeiter explizit OHNE Berichts-Recht (die Rollen-Defaults erlauben
// Reports) — so wird die Auswertungen-Gruppe ausgeblendet.
const _employeeNoReports = AppUserProfile(
  uid: 'emp-1',
  orgId: 'org-1',
  email: 'peter@example.com',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Peter'),
  permissions: UserPermissions(
    canViewSchedule: true,
    canEditSchedule: false,
    canViewTimeTracking: true,
    canEditTimeEntries: true,
    canViewReports: false,
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  required AppUserProfile user,
  bool authDisabled = false,
  bool showScanner = false,
  bool showAreas = false,
  VoidCallback? onSignOut,
  VoidCallback? onOpenSettings,
  VoidCallback? onOpenPersonal,
  VoidCallback? onOpenScanner,
  VoidCallback? onOpenTime,
  VoidCallback? onOpenContacts,
  VoidCallback? onOpenShop,
  String? selectedArea,
  VoidCallback? onClose,
}) async {
  // Hoher Viewport, damit die (lazy) ListView alle Menue-Eintraege baut.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(304, 5000);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolveLight(useV2: true),
      home: Scaffold(
        body: AppNavMenu(
          user: user,
          authDisabled: authDisabled,
          showScanner: showScanner,
          showAreas: showAreas,
          siteName: 'Strichmaennchen',
          dailyHours: 8,
          vacationDays: 30,
          selectedArea: selectedArea,
          onClose: onClose,
          onSignOut: onSignOut ?? () {},
          onOpenTime: onOpenTime ?? () {},
          onOpenContacts: onOpenContacts ?? () {},
          onOpenShop: onOpenShop ?? () {},
          onOpenMonthReport: () {},
          onOpenStatistics: () {},
          onOpenPersonal: onOpenPersonal ?? () {},
          onOpenFinance: () {},
          onOpenInventory: () {},
          onOpenCustomerOrders: () {},
          onOpenOrderAnalytics: () {},
          onOpenScanner: onOpenScanner ?? () {},
          onOpenSettings: onOpenSettings ?? () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async => initializeDateFormatting('de_DE'));

  testWidgets('Admin sieht alle Gruppen + Eintraege', (tester) async {
    await _pump(tester, user: _admin);

    expect(find.text('Sandra'), findsOneWidget); // Name im Header
    expect(find.textContaining('Admin ·'), findsOneWidget); // Rolle + Standort
    expect(find.text('Laden & Bestand'), findsOneWidget);
    expect(find.text('Auswertungen'), findsOneWidget);
    expect(find.text('Monatsbericht'), findsOneWidget);
    expect(find.text('Statistiken'), findsOneWidget);
    expect(find.text('Verwaltung'), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
    // Teamverwaltung ist aufgelöst — Organisation lebt im Personalbereich.
    expect(find.text('Teamverwaltung'), findsNothing);
    expect(find.text('Warenwirtschaft'), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
    expect(find.text('Abmelden'), findsOneWidget);
  });

  testWidgets('Mitarbeiter ohne Reports: keine Auswertungen/Personal', (
    tester,
  ) async {
    await _pump(tester, user: _employeeNoReports);

    expect(find.text('Peter'), findsOneWidget);
    expect(find.textContaining('Mitarbeiter ·'), findsOneWidget);
    expect(find.text('Auswertungen'), findsNothing);
    expect(find.text('Monatsbericht'), findsNothing);
    expect(find.text('Statistiken'), findsNothing);
    expect(find.text('Teamverwaltung'), findsNothing);
    // Personal ist Admin-only -> fuer Mitarbeiter ausgeblendet.
    expect(find.text('Personal'), findsNothing);
    // Fachmodule sind jetzt klar von der Admin-Verwaltung getrennt.
    expect(find.text('Warenwirtschaft'), findsOneWidget);
    expect(find.text('Laden & Bestand'), findsOneWidget);
    expect(find.text('Verwaltung'), findsNothing);
    expect(find.text('Einstellungen'), findsOneWidget);
    expect(find.text('Abmelden'), findsOneWidget);
  });

  testWidgets('Scanner-Eintrag: nur bei showScanner UND Verwalter-Recht', (
    tester,
  ) async {
    // showScanner=false (z.B. Desktop/Web/Tablet) -> kein Scanner.
    await _pump(tester, user: _admin);
    expect(find.text('Scanner'), findsNothing);

    // showScanner=true + Admin (canManageInventory) -> Scanner sichtbar.
    await _pump(tester, user: _admin, showScanner: true);
    expect(find.text('Scanner'), findsOneWidget);

    // showScanner=true, aber Mitarbeiter ohne Verwalterrecht -> kein Scanner.
    await _pump(tester, user: _employeeNoReports, showScanner: true);
    expect(find.text('Scanner'), findsNothing);
  });

  testWidgets('Tap Scanner ruft onOpenScanner', (tester) async {
    var opened = false;
    await _pump(
      tester,
      user: _admin,
      showScanner: true,
      onOpenScanner: () => opened = true,
    );
    await tester.ensureVisible(find.text('Scanner'));
    await tester.tap(find.text('Scanner'));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('authDisabled -> Footer "Profil wechseln"', (tester) async {
    await _pump(tester, user: _admin, authDisabled: true);
    expect(find.text('Profil wechseln'), findsOneWidget);
    expect(find.text('Abmelden'), findsNothing);
  });

  testWidgets('Abmelden ruft onSignOut', (tester) async {
    var signedOut = false;
    await _pump(tester, user: _admin, onSignOut: () => signedOut = true);

    await tester.ensureVisible(find.text('Abmelden'));
    await tester.tap(find.text('Abmelden'));
    await tester.pump();
    expect(signedOut, isTrue);
  });

  testWidgets('Tap Einstellungen ruft onOpenSettings', (tester) async {
    var opened = false;
    await _pump(tester, user: _admin, onOpenSettings: () => opened = true);

    await tester.ensureVisible(find.text('Einstellungen'));
    await tester.tap(find.text('Einstellungen'));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('Tap Personal ruft onOpenPersonal', (tester) async {
    var opened = false;
    await _pump(tester, user: _admin, onOpenPersonal: () => opened = true);

    await tester.ensureVisible(find.text('Personal'));
    await tester.tap(find.text('Personal'));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('Arbeitsbereiche: nur bei showAreas (mobiler Drawer)', (
    tester,
  ) async {
    // Default (Rail/endDrawer): keine Arbeitsbereiche-Gruppe.
    await _pump(tester, user: _admin);
    expect(find.text('Arbeitsbereiche'), findsNothing);

    // Mobiler Drawer: Zeit/Kontakte/Laden sind die aus der Bottomnav
    // ausgelagerten Tabs und tauchen hier auf.
    await _pump(tester, user: _admin, showAreas: true);
    expect(find.text('Arbeitsbereiche'), findsOneWidget);
    expect(find.text('Zeit'), findsOneWidget);
    expect(find.text('Kontakte'), findsOneWidget);
    expect(find.text('Laden'), findsOneWidget);
  });

  testWidgets('Tap Zeit (Bereiche) ruft onOpenTime', (tester) async {
    var opened = false;
    await _pump(
      tester,
      user: _admin,
      showAreas: true,
      onOpenTime: () => opened = true,
    );

    await tester.ensureVisible(find.text('Zeit'));
    await tester.tap(find.text('Zeit'));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('aktiver Arbeitsbereich wird markiert und Menü ist schließbar', (
    tester,
  ) async {
    var closed = false;
    await _pump(
      tester,
      user: _admin,
      showAreas: true,
      selectedArea: 'Laden',
      onClose: () => closed = true,
    );

    final ladenTile = find.ancestor(
      of: find.text('Laden'),
      matching: find.byType(ListTile),
    );
    expect(ladenTile, findsOneWidget);
    expect(tester.widget<ListTile>(ladenTile).selected, isTrue);

    await tester.tap(find.byTooltip('Menü schließen'));
    await tester.pump();
    expect(closed, isTrue);
  });
}
