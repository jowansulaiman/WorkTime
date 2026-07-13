import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/core/datev_export.dart';
import 'package:worktime_app/core/local_demo_data.dart';
import 'package:worktime_app/core/local_demo_schedule_data.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/org_settings.dart';
import 'package:worktime_app/models/supplier.dart';
import 'package:worktime_app/models/team_definition.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/demo_data_seeder.dart';

void main() {
  const orgId = 'demo-org-seeder-test';
  final july = DateTime(2026, 7, 13, 12);
  final august = DateTime(2026, 8, 14, 12);

  late AppUserProfile demoUser;
  late LocalStorageScope scope;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    demoUser = LocalDemoData.adminAccount.toProfile(orgId: orgId);
    scope = LocalStorageScope.fromUser(demoUser);
  });

  test('Nicht-Demo-Nutzer veraendern SharedPreferences nicht', () async {
    SharedPreferences.setMockInitialValues({'sentinel': 'bleibt'});
    DatabaseService.resetCachedPrefs();
    const regularUser = AppUserProfile(
      uid: 'real-user',
      orgId: 'real-org',
      email: 'real@example.com',
      role: UserRole.employee,
      isActive: true,
      settings: UserSettings(name: 'Echter Nutzer'),
    );

    await DemoDataSeeder.seedForUser(regularUser, now: july);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'sentinel'});
    expect(prefs.getString('sentinel'), 'bleibt');
  });

  test(
    'vollstaendiger Seed befuellt alle Planungs- und operativen Bereiche',
    () async {
      await DemoDataSeeder.seedForUser(demoUser, now: july);

      final counts = await _collectionCounts(scope);
      expect(counts, hasLength(54));
      expect(counts.values.every((count) => count > 0), isTrue);
      expect(counts['members'], LocalDemoData.profilesForOrg(orgId).length);
      expect(
        counts['shifts'],
        LocalDemoScheduleData.shiftsForOrg(
          orgId: orgId,
          createdByUid: LocalDemoData.adminAccount.uid,
          now: july,
        ).length,
      );

      final orgSettings = await DatabaseService.loadLocalOrgSettings(
        scope: scope,
      );
      expect(orgSettings, isNotNull);
      expect(orgSettings!.id, OrgSettings.documentId);
      expect(orgSettings.orgId, orgId);
      expect(orgSettings.purchasePricesIncludeVat, isTrue);

      final userSettings = await DatabaseService.loadLocalUserSettings(
        scope: scope,
      );
      expect(userSettings.name, LocalDemoData.adminAccount.name);

      final datevConfig = await DatabaseService.loadLocalDatevConfig(
        scope: scope,
      );
      expect(datevConfig, isNotNull);
      expect(datevConfig!.isConfigured, isTrue);
      expect(datevConfig.designation, 'WorkTime Demo $orgId');

      final prefs = await SharedPreferences.getInstance();
      const forbiddenCloudOnlyKeys = [
        'customer_wishes',
        'customer_feedback',
        'pos_receipts',
        'pos_daily_stats',
        'cash_counts',
        'cash_closings',
        'employee_documents',
      ];
      for (final fragment in forbiddenCloudOnlyKeys) {
        expect(
          prefs.getKeys().where((key) => key.contains(fragment)),
          isEmpty,
          reason: '$fragment darf nicht lokal persistiert werden',
        );
      }
    },
  );

  test(
    'wiederholter Seed ist idempotent und erzeugt keine Duplikate',
    () async {
      await DemoDataSeeder.seedForUser(demoUser, now: july);
      final firstCounts = await _collectionCounts(scope);

      await DemoDataSeeder.seedForUser(demoUser, now: july);
      final secondCounts = await _collectionCounts(scope);
      final shifts = await DatabaseService.loadLocalShifts(scope: scope);
      final entries = await DatabaseService.loadLocalEntries(scope: scope);
      final snapshots = await DatabaseService.loadLocalZeitkontoSnapshots(
        scope: scope,
      );

      expect(secondCounts, firstCounts);
      expect(shifts.map((item) => item.id).toSet(), hasLength(shifts.length));
      expect(entries.map((item) => item.id).toSet(), hasLength(entries.length));
      expect(
        snapshots.map((item) => item.id).toSet(),
        hasLength(snapshots.length),
      );
    },
  );

  test(
    'erneuter Seed aktualisiert stabile IDs auf den aktuellen Monat',
    () async {
      final stableShiftId = LocalDemoScheduleData.shiftId(orgId, 'completed');
      final stableWorkId =
          'demo-work-$orgId-${LocalDemoData.employeeAccount.uid}-approved';

      await DemoDataSeeder.seedForUser(demoUser, now: july);
      final julyShift = (await DatabaseService.loadLocalShifts(
        scope: scope,
      )).singleWhere((item) => item.id == stableShiftId);
      final julyWork = (await DatabaseService.loadLocalEntries(
        scope: scope,
      )).singleWhere((item) => item.id == stableWorkId);
      final julySnapshotCount =
          (await DatabaseService.loadLocalZeitkontoSnapshots(
            scope: scope,
          )).length;
      final julyCounts = await _collectionCounts(scope);

      await DemoDataSeeder.seedForUser(demoUser, now: august);
      final augustShifts = await DatabaseService.loadLocalShifts(scope: scope);
      final augustShift = augustShifts.singleWhere(
        (item) => item.id == stableShiftId,
      );
      final augustWork = (await DatabaseService.loadLocalEntries(
        scope: scope,
      )).singleWhere((item) => item.id == stableWorkId);
      final augustSnapshots = await DatabaseService.loadLocalZeitkontoSnapshots(
        scope: scope,
      );

      expect(julyShift.startTime.month, 7);
      expect(julyWork.date.month, 7);
      expect(augustShift.startTime.month, 8);
      expect(augustWork.date.month, 8);
      expect(
        augustShifts.where((item) => item.id == stableShiftId),
        hasLength(1),
      );
      expect(augustSnapshots, hasLength(julySnapshotCount));
      expect(await _collectionCounts(scope), julyCounts);
    },
  );

  test(
    'eigene Datensaetze und vorhandene Einstellungen bleiben erhalten',
    () async {
      await DemoDataSeeder.seedForUser(demoUser, now: july);
      final teams = await DatabaseService.loadLocalTeams(scope: scope);
      teams.add(
        TeamDefinition(
          id: 'custom-team',
          orgId: orgId,
          name: 'Mein eigenes Team',
          memberIds: const ['custom-user'],
        ),
      );
      await DatabaseService.saveLocalTeams(teams, scope: scope);
      final suppliers = await DatabaseService.loadLocalSuppliers(scope: scope);
      suppliers.add(
        const Supplier(
          id: 'custom-supplier',
          orgId: orgId,
          name: 'Eigener Lieferant',
        ),
      );
      await DatabaseService.saveLocalSuppliers(suppliers, scope: scope);
      await DatabaseService.saveLocalUserSettings(
        const UserSettings(
          name: 'Eigener Anzeigename',
          hourlyRate: 99,
          dailyHours: 5,
        ),
        scope: scope,
      );
      await DatabaseService.saveLocalOrgSettings(
        const OrgSettings(
          id: OrgSettings.documentId,
          orgId: orgId,
          enforceHourCapHard: true,
          defaultShiftMinutes: 360,
          purchasePricesIncludeVat: false,
        ),
        scope: scope,
      );
      await DatabaseService.saveLocalDatevConfig(
        const DatevExportConfig(
          consultantNumber: '7654321',
          clientNumber: '9999',
          designation: 'Eigene DATEV-Konfiguration',
        ),
        scope: scope,
      );

      await DemoDataSeeder.seedForUser(demoUser, now: august);

      final refreshedTeams = await DatabaseService.loadLocalTeams(scope: scope);
      final userSettings = await DatabaseService.loadLocalUserSettings(
        scope: scope,
      );
      final orgSettings = await DatabaseService.loadLocalOrgSettings(
        scope: scope,
      );
      final refreshedSuppliers = await DatabaseService.loadLocalSuppliers(
        scope: scope,
      );
      final datevConfig = await DatabaseService.loadLocalDatevConfig(
        scope: scope,
      );
      expect(
        refreshedTeams.singleWhere((team) => team.id == 'custom-team').name,
        'Mein eigenes Team',
      );
      expect(userSettings.name, 'Eigener Anzeigename');
      expect(userSettings.hourlyRate, 99);
      expect(
        refreshedSuppliers
            .singleWhere((supplier) => supplier.id == 'custom-supplier')
            .name,
        'Eigener Lieferant',
      );
      expect(orgSettings!.enforceHourCapHard, isTrue);
      expect(orgSettings.defaultShiftMinutes, 360);
      expect(orgSettings.purchasePricesIncludeVat, isFalse);
      expect(datevConfig!.designation, 'Eigene DATEV-Konfiguration');
      expect(datevConfig.consultantNumber, '7654321');
    },
  );
}

Future<Map<String, int>> _collectionCounts(LocalStorageScope scope) async => {
  'members': (await DatabaseService.loadLocalTeamMembers(scope: scope)).length,
  'invites': (await DatabaseService.loadLocalInvites(scope: scope)).length,
  'teams': (await DatabaseService.loadLocalTeams(scope: scope)).length,
  'sites': (await DatabaseService.loadLocalSites(scope: scope)).length,
  'qualifications':
      (await DatabaseService.loadLocalQualifications(scope: scope)).length,
  'contracts':
      (await DatabaseService.loadLocalEmploymentContracts(scope: scope)).length,
  'assignments':
      (await DatabaseService.loadLocalSiteAssignments(scope: scope)).length,
  'preferences':
      (await DatabaseService.loadLocalShiftPreferences(scope: scope)).length,
  'rules': (await DatabaseService.loadLocalRuleSets(scope: scope)).length,
  'travel':
      (await DatabaseService.loadLocalTravelTimeRules(scope: scope)).length,
  'shifts': (await DatabaseService.loadLocalShifts(scope: scope)).length,
  'shiftTemplates':
      (await DatabaseService.loadLocalShiftTemplates(scope: scope)).length,
  'absences':
      (await DatabaseService.loadLocalAbsenceRequests(scope: scope)).length,
  'swaps': (await DatabaseService.loadLocalSwapRequests(scope: scope)).length,
  'credits': (await DatabaseService.loadLocalSwapCredits(scope: scope)).length,
  'workEntries': (await DatabaseService.loadLocalEntries(scope: scope)).length,
  'workTemplates':
      (await DatabaseService.loadLocalTemplates(scope: scope)).length,
  'clockEntries':
      (await DatabaseService.loadLocalClockEntries(scope: scope)).length,
  'snapshots':
      (await DatabaseService.loadLocalZeitkontoSnapshots(scope: scope)).length,
  'storeTasks':
      (await DatabaseService.loadLocalStoreTasks(scope: scope)).length,
  'adMedia': (await DatabaseService.loadLocalAdMedia(scope: scope)).length,
  'displays':
      (await DatabaseService.loadLocalSignageDisplays(scope: scope)).length,
  'audit': (await DatabaseService.loadLocalAuditLog(scope: scope)).length,
  'suppliers': (await DatabaseService.loadLocalSuppliers(scope: scope)).length,
  'products': (await DatabaseService.loadLocalProducts(scope: scope)).length,
  'productBatches':
      (await DatabaseService.loadLocalProductBatches(scope: scope)).length,
  'purchaseOrders':
      (await DatabaseService.loadLocalPurchaseOrders(scope: scope)).length,
  'stockMovements':
      (await DatabaseService.loadLocalStockMovements(scope: scope)).length,
  'priceHistory':
      (await DatabaseService.loadLocalPriceHistory(scope: scope)).length,
  'scanEvents':
      (await DatabaseService.loadLocalScanEvents(scope: scope)).length,
  'orderCarts':
      (await DatabaseService.loadLocalOrderCarts(scope: scope)).length,
  'weeklyOrderLists':
      (await DatabaseService.loadLocalWeeklyOrderLists(scope: scope)).length,
  'fridgeRefillLists':
      (await DatabaseService.loadLocalFridgeRefillLists(scope: scope)).length,
  'customerOrders':
      (await DatabaseService.loadLocalCustomerOrders(scope: scope)).length,
  'contacts': (await DatabaseService.loadLocalContacts(scope: scope)).length,
  'contactOrganizations':
      (await DatabaseService.loadLocalContactOrganizations(
        scope: scope,
      )).length,
  'workTasks': (await DatabaseService.loadLocalWorkTasks(scope: scope)).length,
  'payrollProfiles':
      (await DatabaseService.loadLocalPayrollProfiles(scope: scope)).length,
  'payrollRecords':
      (await DatabaseService.loadLocalPayrollRecords(scope: scope)).length,
  'employeeProfiles':
      (await DatabaseService.loadLocalEmployeeProfiles(scope: scope)).length,
  'sollzeitProfiles':
      (await DatabaseService.loadLocalSollzeitProfiles(scope: scope)).length,
  'orgPayrollSettings':
      (await DatabaseService.loadLocalOrgPayrollSettings(scope: scope)).length,
  'employeeChildren':
      (await DatabaseService.loadLocalEmployeeChildren(scope: scope)).length,
  'employeeNotes':
      (await DatabaseService.loadLocalEmployeeNotes(scope: scope)).length,
  'employeeQualifications':
      (await DatabaseService.loadLocalEmployeeQualifications(
        scope: scope,
      )).length,
  'employeeAusbildungen':
      (await DatabaseService.loadLocalEmployeeAusbildungen(
        scope: scope,
      )).length,
  'urlaubskontoJahre':
      (await DatabaseService.loadLocalUrlaubskontoJahre(scope: scope)).length,
  'urlaubsanpassungen':
      (await DatabaseService.loadLocalUrlaubsanpassungen(scope: scope)).length,
  'payLineTypes':
      (await DatabaseService.loadLocalPayLineTypes(scope: scope)).length,
  'costCenters':
      (await DatabaseService.loadLocalCostCenters(scope: scope)).length,
  'costTypes': (await DatabaseService.loadLocalCostTypes(scope: scope)).length,
  'journalEntries':
      (await DatabaseService.loadLocalJournalEntries(scope: scope)).length,
  'budgets': (await DatabaseService.loadLocalBudgets(scope: scope)).length,
  'datevConfig':
      (await DatabaseService.loadLocalDatevConfig(scope: scope)) == null
          ? 0
          : 1,
};
