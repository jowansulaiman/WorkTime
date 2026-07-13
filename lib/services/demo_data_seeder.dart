import '../core/local_demo_backoffice_data.dart';
import '../core/local_demo_data.dart';
import '../core/local_demo_inventory_data.dart';
import '../core/local_demo_operations_data.dart';
import '../core/local_demo_schedule_data.dart';
import '../models/app_user.dart';
import '../models/org_settings.dart';
import 'database_service.dart';

/// Schreibt den vollstaendigen lokalen Demo-Datensatz in die bestehenden
/// SharedPreferences-Scopes.
///
/// Der Seeder ist absichtlich nicht an einen Provider gekoppelt. Dadurch kann
/// der Auth-Flow ihn an einer zentralen Stelle aufrufen, waehrend Tests und
/// andere lokale Einstiege dieselbe idempotente Operation verwenden koennen.
class DemoDataSeeder {
  DemoDataSeeder._();

  /// Seedet bzw. aktualisiert die lokalen Demo-Daten fuer [user].
  ///
  /// Profile, die keinem Konto aus [LocalDemoData] entsprechen, werden nicht
  /// angefasst. [now] macht zeitbezogene Datensaetze in Tests reproduzierbar.
  static Future<void> seedForUser(AppUserProfile user, {DateTime? now}) async {
    if (!LocalDemoData.isDemoUser(user)) {
      return;
    }

    final scope = LocalStorageScope.fromUser(user);
    if (!scope.isValid) {
      return;
    }

    final anchor = now ?? DateTime.now();
    final creatorUid = LocalDemoData.adminAccount.uid;
    final orgId = scope.normalizedOrgId;
    final schedule = LocalDemoScheduleData.datasetForOrg(
      orgId: orgId,
      createdByUid: creatorUid,
      now: anchor,
    );

    // Der erste Zugriff initialisiert/migriert den Scope einmal geordnet. Die
    // folgenden Collection-Merges koennen danach ohne eigene Schluessellogik
    // die oeffentliche DatabaseService-API nutzen.
    await _seedCollection(
      load: () => DatabaseService.loadLocalTeamMembers(scope: scope),
      save:
          (items) => DatabaseService.saveLocalTeamMembers(items, scope: scope),
      demoItems: LocalDemoData.profilesForOrg(orgId),
      keyOf: (item) => item.uid,
      isManagedDemo:
          (item) =>
              item.uid.startsWith('local-demo-') ||
              item.uid.startsWith('local-test-') ||
              LocalDemoData.accountForUid(item.uid) != null ||
              LocalDemoData.accountForEmail(item.email) != null,
    );

    await _seedCollection(
      load: () => DatabaseService.loadLocalInvites(scope: scope),
      save: (items) => DatabaseService.saveLocalInvites(items, scope: scope),
      demoItems: schedule.invites,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalTeams(scope: scope),
      save: (items) => DatabaseService.saveLocalTeams(items, scope: scope),
      demoItems: schedule.teams,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalSites(scope: scope),
      save: (items) => DatabaseService.saveLocalSites(items, scope: scope),
      demoItems: LocalDemoData.sitesForOrg(
        orgId: orgId,
        createdByUid: creatorUid,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalQualifications(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalQualifications(items, scope: scope),
      demoItems: schedule.qualifications,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalEmploymentContracts(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalEmploymentContracts(items, scope: scope),
      demoItems: schedule.employmentContracts,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalSiteAssignments(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalSiteAssignments(items, scope: scope),
      demoItems: LocalDemoData.siteAssignmentsForOrg(
        orgId: orgId,
        createdByUid: creatorUid,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalShiftPreferences(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalShiftPreferences(items, scope: scope),
      demoItems: schedule.shiftPreferences,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalRuleSets(scope: scope),
      save: (items) => DatabaseService.saveLocalRuleSets(items, scope: scope),
      demoItems: schedule.complianceRuleSets,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalTravelTimeRules(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalTravelTimeRules(items, scope: scope),
      demoItems: schedule.travelTimeRules,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );

    await _seedCollection(
      load: () => DatabaseService.loadLocalShifts(scope: scope),
      save: (items) => DatabaseService.saveLocalShifts(items, scope: scope),
      demoItems: schedule.shifts,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalShiftTemplates(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalShiftTemplates(items, scope: scope),
      demoItems: schedule.shiftTemplates,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalAbsenceRequests(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalAbsenceRequests(items, scope: scope),
      demoItems: schedule.absenceRequests,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalSwapRequests(scope: scope),
      save:
          (items) => DatabaseService.saveLocalSwapRequests(items, scope: scope),
      demoItems: schedule.shiftSwapRequests,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalSwapCredits(scope: scope),
      save:
          (items) => DatabaseService.saveLocalSwapCredits(items, scope: scope),
      demoItems: schedule.swapCredits,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );

    await _seedCollection(
      load: () => DatabaseService.loadLocalEntries(scope: scope),
      save: (items) => DatabaseService.saveLocalEntries(items, scope: scope),
      demoItems: LocalDemoOperationsData.workEntriesForOrg(
        orgId: orgId,
        now: anchor,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalTemplates(scope: scope),
      save: (items) => DatabaseService.saveLocalTemplates(items, scope: scope),
      demoItems: LocalDemoOperationsData.workTemplatesForOrg(orgId),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalClockEntries(scope: scope),
      save:
          (items) => DatabaseService.saveLocalClockEntries(items, scope: scope),
      demoItems: LocalDemoOperationsData.clockEntriesForOrg(
        orgId: orgId,
        now: anchor,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalZeitkontoSnapshots(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalZeitkontoSnapshots(items, scope: scope),
      demoItems: LocalDemoOperationsData.zeitkontoSnapshotsForOrg(
        orgId: orgId,
        now: anchor,
      ),
      keyOf: (item) => item.id,
      // Snapshot-IDs folgen dem Produktformat userId-Jahr-Monat und tragen
      // daher keinen demo-Praefix. Demo-Nutzer markieren hier die Datensaetze.
      isManagedDemo: (item) => LocalDemoData.accountForUid(item.userId) != null,
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalStoreTasks(scope: scope),
      save: (items) => DatabaseService.saveLocalStoreTasks(items, scope: scope),
      demoItems: LocalDemoOperationsData.storeTasksForOrg(
        orgId: orgId,
        createdByUid: creatorUid,
        now: anchor,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );

    // Signage besteht aus Medien und Displays. Beide Seiten werden gemeinsam
    // geseedet, damit die mediaIds der Displays immer aufloesbar bleiben.
    await _seedCollection(
      load: () => DatabaseService.loadLocalAdMedia(scope: scope),
      save: (items) => DatabaseService.saveLocalAdMedia(items, scope: scope),
      demoItems: LocalDemoOperationsData.adMediaForOrg(
        orgId: orgId,
        createdByUid: creatorUid,
        now: anchor,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalSignageDisplays(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalSignageDisplays(items, scope: scope),
      demoItems: LocalDemoOperationsData.signageDisplaysForOrg(
        orgId: orgId,
        createdByUid: creatorUid,
        now: anchor,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalAuditLog(scope: scope),
      save: (items) => DatabaseService.saveLocalAuditLog(items, scope: scope),
      demoItems: LocalDemoOperationsData.auditEntriesForOrg(
        orgId: orgId,
        now: anchor,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );

    await _seedInventory(
      scope: scope,
      orgId: orgId,
      actorUid: creatorUid,
      now: anchor,
    );
    await _seedBackoffice(
      scope: scope,
      orgId: orgId,
      actorUid: creatorUid,
      now: anchor,
    );

    if (await DatabaseService.loadLocalOrgSettings(scope: scope) == null) {
      await DatabaseService.saveLocalOrgSettings(
        OrgSettings(
          id: OrgSettings.documentId,
          orgId: orgId,
          enforceHourCapHard: false,
          defaultShiftMinutes: 480,
          defaultBreakMinutes: 30,
          defaultRequiredCount: 1,
          purchasePricesIncludeVat: true,
        ),
        scope: scope,
      );
    }

    final localSettings = await DatabaseService.loadLocalUserSettings(
      scope: scope,
    );
    if (localSettings.name.trim().isEmpty) {
      await DatabaseService.saveLocalUserSettings(user.settings, scope: scope);
    }
  }

  static Future<void> _seedInventory({
    required LocalStorageScope scope,
    required String orgId,
    required String actorUid,
    required DateTime now,
  }) async {
    final inventory = LocalDemoInventoryData.allForOrg(
      orgId: orgId,
      actorUid: actorUid,
      now: now,
    );

    await _seedCollection(
      load: () => DatabaseService.loadLocalSuppliers(scope: scope),
      save: (items) => DatabaseService.saveLocalSuppliers(items, scope: scope),
      demoItems: inventory.suppliers,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalProducts(scope: scope),
      save: (items) => DatabaseService.saveLocalProducts(items, scope: scope),
      demoItems: inventory.products,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalProductBatches(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalProductBatches(items, scope: scope),
      demoItems: inventory.productBatches,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalPurchaseOrders(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalPurchaseOrders(items, scope: scope),
      demoItems: inventory.purchaseOrders,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalStockMovements(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalStockMovements(items, scope: scope),
      demoItems: inventory.stockMovements,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalPriceHistory(scope: scope),
      save:
          (items) => DatabaseService.saveLocalPriceHistory(items, scope: scope),
      demoItems: inventory.priceHistory,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalScanEvents(scope: scope),
      save: (items) => DatabaseService.saveLocalScanEvents(items, scope: scope),
      demoItems: inventory.scanEvents,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalOrderCarts(scope: scope),
      save: (items) => DatabaseService.saveLocalOrderCarts(items, scope: scope),
      demoItems: inventory.orderCarts,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalWeeklyOrderLists(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalWeeklyOrderLists(items, scope: scope),
      demoItems: inventory.weeklyOrderLists,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalFridgeRefillLists(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalFridgeRefillLists(items, scope: scope),
      demoItems: inventory.fridgeRefillLists,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalCustomerOrders(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalCustomerOrders(items, scope: scope),
      demoItems: inventory.customerOrders,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalContacts(scope: scope),
      save: (items) => DatabaseService.saveLocalContacts(items, scope: scope),
      demoItems: inventory.contacts,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalContactOrganizations(scope: scope),
      save:
          (items) => DatabaseService.saveLocalContactOrganizations(
            items,
            scope: scope,
          ),
      demoItems: inventory.contactOrganizations,
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );

    // customerWishes, customerFeedback sowie die cloud*-POS-/Kassenlisten aus
    // dem Bundle sind absichtlich nicht Teil der lokalen Persistenz.
  }

  static Future<void> _seedBackoffice({
    required LocalStorageScope scope,
    required String orgId,
    required String actorUid,
    required DateTime now,
  }) async {
    await _seedCollection(
      load: () => DatabaseService.loadLocalWorkTasks(scope: scope),
      save: (items) => DatabaseService.saveLocalWorkTasks(items, scope: scope),
      demoItems: LocalDemoBackofficeData.workTasksForOrg(
        orgId: orgId,
        createdByUid: actorUid,
        now: now,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalPayrollProfiles(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalPayrollProfiles(items, scope: scope),
      demoItems: LocalDemoBackofficeData.payrollProfilesForOrg(
        orgId: orgId,
        createdByUid: actorUid,
        now: now,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalPayrollRecords(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalPayrollRecords(items, scope: scope),
      demoItems: LocalDemoBackofficeData.payrollRecordsForOrg(
        orgId: orgId,
        createdByUid: actorUid,
        now: now,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalEmployeeProfiles(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalEmployeeProfiles(items, scope: scope),
      demoItems: LocalDemoBackofficeData.employeeProfilesForOrg(
        orgId: orgId,
        createdByUid: actorUid,
        now: now,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalSollzeitProfiles(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalSollzeitProfiles(items, scope: scope),
      demoItems: LocalDemoBackofficeData.sollzeitProfilesForOrg(
        orgId: orgId,
        createdByUid: actorUid,
        now: now,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalOrgPayrollSettings(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalOrgPayrollSettings(items, scope: scope),
      demoItems: LocalDemoBackofficeData.orgPayrollSettingsForOrg(
        orgId: orgId,
        createdByUid: actorUid,
        now: now,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalEmployeeChildren(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalEmployeeChildren(items, scope: scope),
      demoItems: LocalDemoBackofficeData.employeeChildrenForOrg(
        orgId: orgId,
        createdByUid: actorUid,
        now: now,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalEmployeeNotes(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalEmployeeNotes(items, scope: scope),
      demoItems: LocalDemoBackofficeData.employeeNotesForOrg(
        orgId: orgId,
        createdByUid: actorUid,
        now: now,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalEmployeeQualifications(scope: scope),
      save:
          (items) => DatabaseService.saveLocalEmployeeQualifications(
            items,
            scope: scope,
          ),
      demoItems: LocalDemoBackofficeData.employeeQualificationsForOrg(
        orgId: orgId,
        createdByUid: actorUid,
        now: now,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalEmployeeAusbildungen(scope: scope),
      save:
          (items) => DatabaseService.saveLocalEmployeeAusbildungen(
            items,
            scope: scope,
          ),
      demoItems: LocalDemoBackofficeData.employeeAusbildungenForOrg(
        orgId: orgId,
        createdByUid: actorUid,
        now: now,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalUrlaubskontoJahre(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalUrlaubskontoJahre(items, scope: scope),
      demoItems: LocalDemoBackofficeData.urlaubskontoJahreForOrg(
        orgId: orgId,
        createdByUid: actorUid,
        now: now,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalUrlaubsanpassungen(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalUrlaubsanpassungen(items, scope: scope),
      demoItems: LocalDemoBackofficeData.urlaubsanpassungenForOrg(
        orgId: orgId,
        createdByUid: actorUid,
        now: now,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalPayLineTypes(scope: scope),
      save:
          (items) => DatabaseService.saveLocalPayLineTypes(items, scope: scope),
      demoItems: LocalDemoBackofficeData.payLineTypesForOrg(
        orgId: orgId,
        createdByUid: actorUid,
        now: now,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalCostCenters(scope: scope),
      save:
          (items) => DatabaseService.saveLocalCostCenters(items, scope: scope),
      demoItems: LocalDemoBackofficeData.costCentersForOrg(
        orgId: orgId,
        createdByUid: actorUid,
        now: now,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalCostTypes(scope: scope),
      save: (items) => DatabaseService.saveLocalCostTypes(items, scope: scope),
      demoItems: LocalDemoBackofficeData.costTypesForOrg(
        orgId: orgId,
        createdByUid: actorUid,
        now: now,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalJournalEntries(scope: scope),
      save:
          (items) =>
              DatabaseService.saveLocalJournalEntries(items, scope: scope),
      demoItems: LocalDemoBackofficeData.journalEntriesForOrg(
        orgId: orgId,
        createdByUid: actorUid,
        now: now,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );
    await _seedCollection(
      load: () => DatabaseService.loadLocalBudgets(scope: scope),
      save: (items) => DatabaseService.saveLocalBudgets(items, scope: scope),
      demoItems: LocalDemoBackofficeData.budgetsForOrg(
        orgId: orgId,
        createdByUid: actorUid,
        now: now,
      ),
      keyOf: (item) => item.id,
      isManagedDemo: (item) => _hasDemoId(item.id),
    );

    final demoDatev = LocalDemoBackofficeData.datevConfigForOrg(orgId);
    final existingDatev = await DatabaseService.loadLocalDatevConfig(
      scope: scope,
    );
    if (existingDatev == null ||
        existingDatev.designation == demoDatev.designation) {
      await DatabaseService.saveLocalDatevConfig(demoDatev, scope: scope);
    }

    // EmployeeDocument enthaelt nur Metadaten zu Cloud-Storage-Binaries und
    // besitzt bewusst keinen SharedPreferences-Spiegel.
  }

  /// Fuehrt stabile Upserts fuer [demoItems] aus und behaelt fremde Eintraege.
  ///
  /// Gleiche Schluessel werden durch die neue Demo-Version ersetzt. Mit
  /// [isManagedDemo] koennen ausserdem veraltete Demo-Records entfernt werden,
  /// deren Schluessel in einem rollierenden Datensatz nicht mehr vorkommen.
  static List<T> mergeByKey<T, K>({
    required Iterable<T> existing,
    required Iterable<T> demoItems,
    required K Function(T item) keyOf,
    bool Function(T item)? isManagedDemo,
  }) {
    final demoByKey = <K, T>{};
    final demoKeyOrder = <K>[];
    for (final item in demoItems) {
      final key = keyOf(item);
      if (!demoByKey.containsKey(key)) {
        demoKeyOrder.add(key);
      }
      demoByKey[key] = item;
    }

    final merged = <T>[];
    for (final item in existing) {
      if (demoByKey.containsKey(keyOf(item))) {
        continue;
      }
      if (isManagedDemo?.call(item) ?? false) {
        continue;
      }
      merged.add(item);
    }
    for (final key in demoKeyOrder) {
      merged.add(demoByKey[key] as T);
    }
    return List<T>.unmodifiable(merged);
  }

  static Future<void> _seedCollection<T, K>({
    required Future<List<T>> Function() load,
    required Future<void> Function(List<T> items) save,
    required Iterable<T> demoItems,
    required K Function(T item) keyOf,
    bool Function(T item)? isManagedDemo,
  }) async {
    final existing = await load();
    final merged = mergeByKey<T, K>(
      existing: existing,
      demoItems: demoItems,
      keyOf: keyOf,
      isManagedDemo: isManagedDemo,
    );
    await save(merged);
  }

  static bool _hasDemoId(String? id) => id?.startsWith('demo-') ?? false;
}
