import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/ui/app_hero_card.dart';
import 'package:worktime_app/ui/app_quick_action.dart';
import 'package:worktime_app/ui/app_section_card.dart';
import 'package:worktime_app/ui/app_stat_cards.dart';
import 'package:worktime_app/widgets/dashboard_action_items_card.dart';

import 'support/router_harness.dart';

// ---------------------------------------------------------------------------
// CHARAKTERISIERUNGS-TESTS: Heute-Dashboard (V2) — IST-Zustand pinnen.
//
// Zweck: Diese Tests nageln das JETZIGE Verhalten des Heute-Tabs (ShellTab.today)
// pro Rolle fest, BEVOR die geplante Umsortierung (Plan §6.1 „Heute
// priorisieren/entrümpeln") die Reihenfolge/Gruppierung der Blöcke ändert.
// Bewusst verhaltens-erhaltend (Characterization Tests im Fowler-Sinn):
//   - Sie LESEN nur, ändern keine Screens/Provider.
//   - Sie prüfen die PRÄSENZ der Kern-Blöcke/Widgets pro Rolle, NICHT die exakte
//     Reihenfolge — die ändert sich beim Umbau absichtlich.
//   - Nach §6.1 muss dieselbe Menge an Kern-Blöcken je Rolle noch da sein;
//     ein Test-Rot signalisiert dann einen ungewollten Feature-Verlust.
//
// Getestet wird die ECHTE go_router-Shell via pumpApp() (test/support/
// router_harness.dart) mit FakeFirebaseFirestore + allen Providern. Das
// redesign_v2-Flag ist überall AN (flagOn: true) → V2-Dashboards
// (_EmployeeDashboardTabV2 / _AdminDashboardTabV2 in home_dashboards_v2.dart).
//
// Rollen-Dispatch: buildHomeTab wählt per canManageShifts (app_user.dart) —
// admin/teamlead → Admin-Dashboard, employee → Employee-Dashboard.
// ---------------------------------------------------------------------------

const _employee = AppUserProfile(
  uid: 'emp-1',
  orgId: 'org-1',
  email: 'peter@example.com',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Peter'),
);

const _teamlead = AppUserProfile(
  uid: 'lead-1',
  orgId: 'org-1',
  email: 'lea.teamlead@example.com',
  role: UserRole.teamlead,
  isActive: true,
  settings: UserSettings(name: 'Lea'),
);

const _admin = AppUserProfile(
  uid: 'admin-1',
  orgId: 'org-1',
  email: 'admin@example.com',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Admin'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => initializeDateFormatting('de_DE'));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  // -------------------------------------------------------------------------
  // MITARBEITER (employee): _EmployeeDashboardTabV2
  // -------------------------------------------------------------------------
  testWidgets(
    'Heute (employee): Kern-Blöcke vorhanden — Hero, Krank/Urlaub/Zeit, '
    'Action-Items',
    (tester) async {
      final h = await pumpApp(tester, profile: _employee, flagOn: true);

      // V2-Hero (AppHeroCard-Hülle).
      expect(find.byType(AppHeroCard), findsWidgets);

      // Warnkarte Nachbestellungen (sichtbar, da isActive → canViewInventory).
      expect(find.byType(DashboardActionItemsCard), findsOneWidget);

      // Mitarbeiter-Quick-Actions.
      expect(find.text('Krank melden'), findsOneWidget);
      expect(find.text('Urlaub anfragen'), findsOneWidget);

      // Es dürfen KEINE Admin-Quick-Actions auftauchen (Rollen-Trennung).
      expect(find.text('Plan öffnen'), findsNothing);
      expect(find.text('Personal verwalten'), findsNothing);

      // Mindestens Quick-Action- und Sektionskarten rendern.
      expect(find.byType(AppQuickActionCard), findsWidgets);
      expect(find.byType(AppSectionCard), findsWidgets);

      await h.cleanup();
    },
  );

  // -------------------------------------------------------------------------
  // TEAMLEITER (teamlead): nutzt _AdminDashboardTabV2 (KEIN eigenes Dashboard)
  // -------------------------------------------------------------------------
  testWidgets(
    'Heute (teamlead): sieht das Admin-Dashboard (canManageShifts), '
    'aber KEIN „Personal verwalten" (nur isAdmin)',
    (tester) async {
      final h = await pumpApp(tester, profile: _teamlead, flagOn: true);

      expect(find.byType(AppHeroCard), findsWidgets);
      expect(find.text('Plan öffnen'), findsOneWidget);

      // „Personal verwalten" ist zusätzlich auf isAdmin gegatet → Teamlead sieht die
      // Karte NICHT. Belegter Unterschied admin↔teamlead.
      expect(find.text('Personal verwalten'), findsNothing);

      // Admin-Metrik-Grid rendert.
      expect(find.byType(AppMetricCard), findsWidgets);

      // Mitarbeiter-only Quick-Actions dürfen NICHT erscheinen.
      expect(find.text('Krank melden'), findsNothing);
      expect(find.text('Urlaub anfragen'), findsNothing);

      await h.cleanup();
    },
  );

  // -------------------------------------------------------------------------
  // ADMIN: _AdminDashboardTabV2 (voller Umfang inkl. „Personal verwalten")
  // -------------------------------------------------------------------------
  testWidgets(
    'Heute (admin): voller Admin-Block — Hero, Plan/Team, Metrik-Kacheln',
    (tester) async {
      final h = await pumpApp(tester, profile: _admin, flagOn: true);

      // V2-Hero + Warnkarte.
      expect(find.byType(AppHeroCard), findsWidgets);
      expect(find.byType(DashboardActionItemsCard), findsOneWidget);

      // Admin-Quick-Actions (Personal verwalten = isAdmin-only).
      expect(find.text('Plan öffnen'), findsOneWidget);
      expect(find.text('Personal verwalten'), findsOneWidget);

      // Metrik-Grid.
      expect(find.byType(AppMetricCard), findsWidgets);

      // Mitarbeiter-only Quick-Actions dürfen NICHT erscheinen.
      expect(find.text('Krank melden'), findsNothing);
      expect(find.text('Urlaub anfragen'), findsNothing);

      await h.cleanup();
    },
  );
}
