import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/screens/inventory_screen.dart';
import 'package:worktime_app/screens/paketshop_screen.dart';
import 'package:worktime_app/services/database_service.dart';

import 'support/router_harness.dart';

/// Charakterisiert den neu gruppierten Laden-Hub über die echte Router-Shell.
/// Neben der sichtbaren Hierarchie wird geprüft, dass die bisherigen Push-Ziele
/// und damit das Zurück-zum-Hub-Verhalten erhalten bleiben.
const _employee = AppUserProfile(
  uid: 'employee-1',
  orgId: 'org-1',
  email: 'employee@example.com',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Peter'),
);

const _admin = AppUserProfile(
  uid: 'admin-1',
  orgId: 'org-1',
  email: 'admin@example.com',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Sandra'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => initializeDateFormatting('de_DE'));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  testWidgets('Mitarbeiter sieht klar gruppiertes Tagesgeschäft', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      profile: _employee,
      flagOn: true,
      initialLocation: '/laden',
      size: const Size(390, 1000),
    );

    expect(find.text('Warenwirtschaft öffnen'), findsOneWidget);
    expect(find.text('Tagesgeschäft'), findsOneWidget);
    expect(find.text('Auswertungen & Kasse'), findsOneWidget);
    expect(find.text('Verwaltung'), findsNothing);
    expect(find.text('Kundenbestellungen'), findsOneWidget);
    expect(find.text('Paketshop'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Paketshop'));
    await tester.tap(find.text('Paketshop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(PaketshopHubScreen), findsOneWidget);

    await h.cleanup();
  });

  testWidgets('Admin sieht Auswertungen und Verwaltung; Hero öffnet Inventar', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      profile: _admin,
      flagOn: true,
      initialLocation: '/laden',
      size: const Size(1400, 1600),
    );

    expect(find.text('Tagesgeschäft'), findsOneWidget);
    expect(find.text('Auswertungen & Kasse'), findsOneWidget);
    expect(find.text('Verwaltung'), findsOneWidget);
    expect(find.text('Kassenbericht'), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Änderungsprotokoll'), findsOneWidget);

    await tester.tap(find.text('Warenwirtschaft öffnen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(InventoryScreen), findsOneWidget);

    await h.cleanup();
  });
}
