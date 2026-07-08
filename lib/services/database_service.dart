import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_logger.dart';
import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/compliance_rule_set.dart';
import '../models/contact.dart';
import '../models/contact_organization.dart';
import '../models/customer_order.dart';
import '../models/fridge_refill.dart';
import '../models/order_cart.dart';
import '../models/employee_site_assignment.dart';
import '../models/employment_contract.dart';
import '../models/shift_preference.dart';
import '../models/audit_log_entry.dart';
import '../models/clock_entry.dart';
import '../models/zeitkonto_snapshot.dart';
import '../core/datev_export.dart';
import '../models/employee_ausbildung.dart';
import '../models/employee_child.dart';
import '../models/employee_note.dart';
import '../models/employee_profile.dart';
import '../models/employee_qualification.dart';
import '../models/org_payroll_settings.dart';
import '../models/org_settings.dart';
import '../models/pay_line_type.dart';
import '../models/sollzeit_profile.dart';
import '../models/urlaubsanpassung.dart';
import '../models/urlaubskonto_jahr.dart';
import '../models/finance_models.dart';
import '../models/payroll_profile.dart';
import '../models/payroll_record.dart';
import '../models/price_history_entry.dart';
import '../models/product.dart';
import '../models/product_batch.dart';
import '../models/purchase_order.dart';
import '../models/qualification_definition.dart';
import '../models/shift.dart';
import '../models/shift_swap_request.dart';
import '../models/swap_credit.dart';
import '../models/shift_template.dart';
import '../models/site_definition.dart';
import '../models/stock_movement.dart';
import '../models/supplier.dart';
import '../models/team_definition.dart';
import '../models/travel_time_rule.dart';
import '../models/user_settings.dart';
import '../models/store_task.dart';
import '../models/user_invite.dart';
import '../models/work_entry.dart';
import '../models/work_task.dart';
import '../models/work_template.dart';

class LocalStorageScope {
  const LocalStorageScope({
    required this.orgId,
    required this.userId,
  });

  factory LocalStorageScope.fromUser(AppUserProfile user) {
    return LocalStorageScope(
      orgId: user.orgId,
      userId: user.uid,
    );
  }

  final String orgId;
  final String userId;

  String get normalizedOrgId => orgId.trim();
  String get normalizedUserId => userId.trim();

  bool get isValid => normalizedOrgId.isNotEmpty && normalizedUserId.isNotEmpty;

  String get encodedKey =>
      '${Uri.encodeComponent(normalizedOrgId)}|${Uri.encodeComponent(normalizedUserId)}';
}

class DatabaseService {
  static const _entriesKey = 'work_entries';
  static const _clockEntriesKey = 'clock_entries';
  static const _zeitkontoSnapshotsKey = 'zeitkonto_snapshots';
  static const _templatesKey = 'work_templates';
  static const _shiftsKey = 'schedule_shifts';
  static const _shiftTemplatesKey = 'shift_templates';
  static const _absenceRequestsKey = 'absence_requests';
  // Schichttausch (Tauschanfragen + Gutschriften): org-skopiert, neue
  // Collections ohne Altbestand.
  static const _swapRequestsKey = 'shift_swap_requests';
  static const _swapCreditsKey = 'swap_credits';
  static const _membersKey = 'team_members';
  static const _invitesKey = 'team_invites';
  static const _teamsKey = 'teams';
  static const _sitesKey = 'sites';
  static const _qualificationsKey = 'qualifications';
  static const _contractsKey = 'employment_contracts';
  static const _siteAssignmentsKey = 'employee_site_assignments';
  static const _shiftPreferencesKey = 'shift_preferences';
  static const _ruleSetsKey = 'compliance_rule_sets';
  static const _travelTimeRulesKey = 'travel_time_rules';
  static const _suppliersKey = 'suppliers';
  static const _productsKey = 'products';
  static const _productBatchesKey = 'product_batches';
  static const _purchaseOrdersKey = 'purchase_orders';
  static const _stockMovementsKey = 'stock_movements';
  static const _priceHistoryKey = 'price_history';
  static const _customerOrdersKey = 'customer_orders';
  static const _orderCartsKey = 'order_carts';
  static const _weeklyOrderListsKey = 'weekly_order_lists';
  // Kühlschrank-Nachfüllliste je Laden: org-skopiert, neue Collection.
  static const _fridgeRefillListsKey = 'fridge_refill_lists';
  // Kontakte (Kunden/Lieferanten/Partner): org-skopiert, ohne Legacy-Migration.
  static const _contactsKey = 'contacts';
  // Kontakt-Organisationen (eigenständiges Adressbuch, M9): org-skopiert.
  static const _contactOrganizationsKey = 'contact_organizations';
  // Laden-To-Dos (Arbeitsmodus/Kiosk): org-skopiert, je Laden (Broadcast).
  static const _storeTasksKey = 'store_tasks';
  // Personal-Bereich (nur Admin): org-skopiert, ohne Legacy-Migration.
  static const _workTasksKey = 'work_tasks';
  static const _payrollRecordsKey = 'payroll_records';
  static const _payrollProfilesKey = 'payroll_profiles';
  static const _employeeProfilesKey = 'employee_profiles';
  static const _sollzeitProfilesKey = 'sollzeit_profiles';
  static const _payrollConfigKey = 'payroll_config';
  static const _employeeChildrenKey = 'employee_children';
  static const _employeeNotesKey = 'employee_notes';
  static const _employeeQualificationsKey = 'employee_qualifications';
  static const _employeeAusbildungenKey = 'employee_ausbildungen';
  static const _urlaubskontoJahreKey = 'urlaubskonto_jahre';
  static const _urlaubsanpassungenKey = 'urlaubsanpassungen';
  static const _payLineTypesKey = 'pay_line_types';
  // Finanzen (Kostenrechnung): org-skopiert, ohne Legacy-Migration.
  static const _costCentersKey = 'cost_centers';
  static const _costTypesKey = 'cost_types';
  static const _journalEntriesKey = 'journal_entries';
  static const _budgetsKey = 'budgets';
  static const _datevConfigKey = 'datev_config';
  static const _auditLogKey = 'audit_log';
  // Org-weite operative Einstellungen (Auto-Schichtverteilung): org-skopiert,
  // ein Objekt je Org.
  static const _orgSettingsKey = 'org_settings';
  static const _localAuthUserIdKey = 'local_auth_user_id';
  static const _settingsPrefix = 'setting_';
  static const _dataStorageLocationKey = 'data_storage_location';
  static const _scopedPrefix = 'local_v2';
  static const _orgScopeInitializedKey = '__org_initialized';
  static const _userScopeInitializedKey = '__user_initialized';
  static const _schemaVersionKey = '__schema_version';

  /// Aktuelle Schema-Version der lokalen Persistenz (no-local-schema-version).
  /// Version 1 == Ist-Zustand (kein Migrationsschritt). Bei breaking Model-
  /// Aenderungen (Rename/Typwechsel) hochzaehlen und in
  /// [_ensureScopedSchemaVersion] einen geordneten Migrationsschritt ergaenzen,
  /// statt sich auf das stille Verwerfen inkompatibler Eintraege zu verlassen.
  static const int currentLocalSchemaVersion = 1;
  static const _orgScopedCollectionKeys = <String>{
    _entriesKey,
    _shiftsKey,
    _shiftTemplatesKey,
    _absenceRequestsKey,
    _swapRequestsKey,
    _swapCreditsKey,
    _membersKey,
    _invitesKey,
    _teamsKey,
    _sitesKey,
    _qualificationsKey,
    _contractsKey,
    _siteAssignmentsKey,
    _shiftPreferencesKey,
    _ruleSetsKey,
    _travelTimeRulesKey,
    // Warenwirtschaft: org-skopiert, bewusst NICHT in der Legacy-Migration
    // (neue Collections ohne Altbestand).
    _suppliersKey,
    _productsKey,
    // MHD-/Ablauf-Chargen: org-skopiert (bewegliche Nutzdaten, im Hybrid-Modus
    // lokal gespiegelt).
    _productBatchesKey,
    _purchaseOrdersKey,
    _stockMovementsKey,
    _priceHistoryKey,
    _customerOrdersKey,
    // Wochen-Bestellkorb + Standard-Wochenliste: org-skopiert (je Laden ein
    // Eintrag), neue Collections ohne Altbestand.
    _orderCartsKey,
    _weeklyOrderListsKey,
    // Kühlschrank-Nachfüllliste: org-skopiert (je Laden ein Eintrag).
    _fridgeRefillListsKey,
    // Kontakte: org-skopiert, neue Collection ohne Altbestand.
    _contactsKey,
    // Kontakt-Organisationen: org-skopiert, neue Collection ohne Altbestand.
    _contactOrganizationsKey,
    // Laden-To-Dos (Arbeitsmodus/Kiosk): org-skopiert (je Laden / org-weit).
    _storeTasksKey,
    // Personal-Bereich: org-skopiert, neue Collections ohne Altbestand.
    _workTasksKey,
    _payrollRecordsKey,
    _payrollProfilesKey,
    _employeeProfilesKey,
    _sollzeitProfilesKey,
    _payrollConfigKey,
    _employeeChildrenKey,
    _employeeNotesKey,
    _employeeQualificationsKey,
    _employeeAusbildungenKey,
    _urlaubskontoJahreKey,
    _urlaubsanpassungenKey,
    _payLineTypesKey,
    // Finanzen: org-skopiert, neue Collections ohne Altbestand.
    _costCentersKey,
    _costTypesKey,
    _journalEntriesKey,
    _budgetsKey,
    _datevConfigKey,
    _auditLogKey,
    _orgSettingsKey,
    // Zeitwirtschaft: Stempel-Sessions, org-skopiert (M3).
    _clockEntriesKey,
    // Zeitwirtschaft: Stundenkonto-Snapshots, org-skopiert (M4).
    _zeitkontoSnapshotsKey,
  };
  static const _legacyWorkSettingKeys = <String>[
    'name',
    'hourly_rate',
    'daily_hours',
    'currency',
    'vacation_days',
    'auto_break_after_minutes',
    'clock_in_time',
    'clock_in_site_id',
    'clock_in_site_name',
  ];

  /// Öffentliche Collection-Namen für die Tombstone-API (Soft-Delete).
  static const workEntriesCollection = _entriesKey;
  static const shiftsCollection = _shiftsKey;
  static const absenceRequestsCollection = _absenceRequestsKey;

  static SharedPreferences? _cachedPrefs;

  static Future<SharedPreferences> get _prefs async {
    return _cachedPrefs ??= await SharedPreferences.getInstance();
  }

  /// Setzt den gecachten SharedPreferences-Zustand zurueck.
  /// Wird in Tests benoetigt, wenn SharedPreferences.setMockInitialValues()
  /// aufgerufen wird.
  @visibleForTesting
  static void resetCachedPrefs() {
    _cachedPrefs = null;
  }

  static Future<List<WorkEntry>> loadLegacyEntries() {
    return _loadCollection(
      key: _entriesKey,
      fromMap: WorkEntry.fromMap,
      compare: (a, b) => a.date.compareTo(b.date),
    );
  }

  static Future<List<WorkEntry>> loadLocalEntries({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _entriesKey,
      scope: scope,
      fromMap: WorkEntry.fromMap,
      compare: (a, b) => a.date.compareTo(b.date),
    );
  }

  static Future<void> saveLocalEntries(
    List<WorkEntry> entries, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _entriesKey,
      scope: scope,
      items: entries,
      toMap: (entry) => entry.toMap(),
    );
  }

  static Future<List<ClockEntry>> loadLocalClockEntries({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _clockEntriesKey,
      scope: scope,
      fromMap: ClockEntry.fromMap,
      compare: (a, b) => a.kommen.compareTo(b.kommen),
    );
  }

  static Future<void> saveLocalClockEntries(
    List<ClockEntry> entries, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _clockEntriesKey,
      scope: scope,
      items: entries,
      toMap: (entry) => entry.toMap(),
    );
  }

  static Future<List<ZeitkontoSnapshot>> loadLocalZeitkontoSnapshots({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _zeitkontoSnapshotsKey,
      scope: scope,
      fromMap: ZeitkontoSnapshot.fromMap,
      compare: (a, b) => a.monat.compareTo(b.monat),
    );
  }

  static Future<void> saveLocalZeitkontoSnapshots(
    List<ZeitkontoSnapshot> snapshots, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _zeitkontoSnapshotsKey,
      scope: scope,
      items: snapshots,
      toMap: (snapshot) => snapshot.toMap(),
    );
  }

  static Future<List<WorkTemplate>> loadLegacyTemplates() {
    return _loadCollection(
      key: _templatesKey,
      fromMap: WorkTemplate.fromMap,
      compare: (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  static Future<List<WorkTemplate>> loadLocalTemplates({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _templatesKey,
      scope: scope,
      fromMap: WorkTemplate.fromMap,
      compare: (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  static Future<void> saveLocalTemplates(
    List<WorkTemplate> templates, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _templatesKey,
      scope: scope,
      items: templates,
      toMap: (template) => template.toMap(),
    );
  }

  static Future<List<Shift>> loadLocalShifts({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _shiftsKey,
      scope: scope,
      fromMap: Shift.fromMap,
      compare: (a, b) => a.startTime.compareTo(b.startTime),
    );
  }

  static Future<void> saveLocalShifts(
    List<Shift> shifts, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _shiftsKey,
      scope: scope,
      items: shifts,
      toMap: (shift) => shift.toMap(),
    );
  }

  static Future<List<ShiftTemplate>> loadLocalShiftTemplates({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _shiftTemplatesKey,
      scope: scope,
      fromMap: ShiftTemplate.fromMap,
      compare: (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  static Future<void> saveLocalShiftTemplates(
    List<ShiftTemplate> templates, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _shiftTemplatesKey,
      scope: scope,
      items: templates,
      toMap: (template) => template.toMap(),
    );
  }

  static Future<List<AbsenceRequest>> loadLocalAbsenceRequests({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _absenceRequestsKey,
      scope: scope,
      fromMap: AbsenceRequest.fromMap,
      compare: (a, b) => a.startDate.compareTo(b.startDate),
    );
  }

  static Future<void> saveLocalAbsenceRequests(
    List<AbsenceRequest> requests, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _absenceRequestsKey,
      scope: scope,
      items: requests,
      toMap: (request) => request.toMap(),
    );
  }

  static Future<List<ShiftSwapRequest>> loadLocalSwapRequests({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _swapRequestsKey,
      scope: scope,
      fromMap: ShiftSwapRequest.fromMap,
      compare: (a, b) => b.requesterShiftStart.compareTo(a.requesterShiftStart),
    );
  }

  static Future<void> saveLocalSwapRequests(
    List<ShiftSwapRequest> requests, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _swapRequestsKey,
      scope: scope,
      items: requests,
      toMap: (request) => request.toMap(),
    );
  }

  static Future<List<SwapCredit>> loadLocalSwapCredits({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _swapCreditsKey,
      scope: scope,
      fromMap: SwapCredit.fromMap,
      compare: (a, b) => b.originShiftStart.compareTo(a.originShiftStart),
    );
  }

  static Future<void> saveLocalSwapCredits(
    List<SwapCredit> credits, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _swapCreditsKey,
      scope: scope,
      items: credits,
      toMap: (credit) => credit.toMap(),
    );
  }

  static Future<List<AppUserProfile>> loadLocalTeamMembers({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _membersKey,
      scope: scope,
      fromMap: AppUserProfile.fromMap,
      compare: (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
  }

  // SICHERHEIT (no-secure-storage-for-sensitive): enthaelt PII (E-Mail, Rolle).
  // Klartext-JSON in SharedPreferences, im hybrid-Modus auch produktiv gespiegelt.
  // Siehe ausfuehrlichen Hinweis an saveLocalEmploymentContracts.
  static Future<void> saveLocalTeamMembers(
    List<AppUserProfile> members, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _membersKey,
      scope: scope,
      items: members,
      toMap: (member) => member.toMap(),
    );
  }

  static Future<List<UserInvite>> loadLocalInvites({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _invitesKey,
      scope: scope,
      fromMap: UserInvite.fromMap,
      compare: (a, b) => a.emailLower.compareTo(b.emailLower),
    );
  }

  static Future<void> saveLocalInvites(
    List<UserInvite> invites, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _invitesKey,
      scope: scope,
      items: invites,
      toMap: (invite) => invite.toMap(),
    );
  }

  static Future<List<TeamDefinition>> loadLocalTeams({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _teamsKey,
      scope: scope,
      fromMap: TeamDefinition.fromMap,
      compare: (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  static Future<void> saveLocalTeams(
    List<TeamDefinition> teams, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _teamsKey,
      scope: scope,
      items: teams,
      toMap: (team) => team.toMap(),
    );
  }

  static Future<List<SiteDefinition>> loadLocalSites({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _sitesKey,
      scope: scope,
      fromMap: SiteDefinition.fromMap,
      compare: (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  static Future<void> saveLocalSites(
    List<SiteDefinition> sites, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _sitesKey,
      scope: scope,
      items: sites,
      toMap: (site) => site.toMap(),
    );
  }

  static Future<List<QualificationDefinition>> loadLocalQualifications({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _qualificationsKey,
      scope: scope,
      fromMap: QualificationDefinition.fromMap,
      compare: (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  static Future<void> saveLocalQualifications(
    List<QualificationDefinition> qualifications, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _qualificationsKey,
      scope: scope,
      items: qualifications,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<EmploymentContract>> loadLocalEmploymentContracts({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _contractsKey,
      scope: scope,
      fromMap: EmploymentContract.fromMap,
      compare: (a, b) => b.validFrom.compareTo(a.validFrom),
    );
  }

  // SICHERHEIT (no-secure-storage-for-sensitive): Arbeitsvertraege enthalten
  // Verguetungsdaten (Cents) und werden hier als KLARTEXT-JSON in
  // SharedPreferences abgelegt. Anders als in CLAUDE.md beschrieben werden
  // Stammdaten im hybrid-Modus (Produktiv-Default) sehr wohl lokal gespiegelt
  // (_storeHybridContractsSnapshot in team_provider.dart) -> die Exposition
  // betrifft auch den Produktivbetrieb, nicht nur den local-Dev-Modus.
  // Bedrohungsmodell fuer 2 Laeden: app-sandboxed, eigenes Geraet -> mittel.
  // Remediation (zurueckgestellt, vgl. firebase_crashlytics-Vorgehen in Welle 1):
  // flutter_secure_storage (Keychain/Keystore) als Backend fuer Cents/Settings,
  // Klartext-Fallback nur auf Web. Firestores eigener Offline-Cache ist ebenfalls
  // unverschluesselt, ersetzt also keine echte At-Rest-Verschluesselung.
  static Future<void> saveLocalEmploymentContracts(
    List<EmploymentContract> contracts, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _contractsKey,
      scope: scope,
      items: contracts,
      toMap: (item) => item.toMap(),
    );
  }

  // --- Laden-To-Dos (Arbeitsmodus/Kiosk) ------------------------------------

  static Future<List<StoreTask>> loadLocalStoreTasks({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _storeTasksKey,
      scope: scope,
      fromMap: StoreTask.fromMap,
      compare: (a, b) {
        // Erledigt ist jetzt je Standort (completedBySite) — hier nur nach
        // Fälligkeit, dann Titel sortieren (die Board-Anzeige filtert je Laden).
        final ad = a.dueDate;
        final bd = b.dueDate;
        if (ad == null && bd == null) {
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        }
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      },
    );
  }

  static Future<void> saveLocalStoreTasks(
    List<StoreTask> tasks, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _storeTasksKey,
      scope: scope,
      items: tasks,
      toMap: (item) => item.toMap(),
    );
  }

  // --- Personal-Bereich: Arbeitsaufträge ------------------------------------

  static Future<List<WorkTask>> loadLocalWorkTasks({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _workTasksKey,
      scope: scope,
      fromMap: WorkTask.fromMap,
      compare: (a, b) {
        final ad = a.dueDate;
        final bd = b.dueDate;
        if (ad == null && bd == null) {
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        }
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      },
    );
  }

  static Future<void> saveLocalWorkTasks(
    List<WorkTask> tasks, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _workTasksKey,
      scope: scope,
      items: tasks,
      toMap: (item) => item.toMap(),
    );
  }

  // --- Personal-Bereich: Lohnabrechnungen -----------------------------------
  // SICHERHEIT: Lohndaten (Cents) liegen wie Arbeitsverträge als Klartext-JSON
  // in SharedPreferences (vgl. Hinweis an saveLocalEmploymentContracts).

  static Future<List<PayrollRecord>> loadLocalPayrollRecords({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _payrollRecordsKey,
      scope: scope,
      fromMap: PayrollRecord.fromMap,
      compare: (a, b) {
        final y = b.periodYear.compareTo(a.periodYear);
        if (y != 0) return y;
        return b.periodMonth.compareTo(a.periodMonth);
      },
    );
  }

  static Future<void> saveLocalPayrollRecords(
    List<PayrollRecord> records, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _payrollRecordsKey,
      scope: scope,
      items: records,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<PayrollProfile>> loadLocalPayrollProfiles({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _payrollProfilesKey,
      scope: scope,
      fromMap: PayrollProfile.fromMap,
    );
  }

  static Future<void> saveLocalPayrollProfiles(
    List<PayrollProfile> profiles, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _payrollProfilesKey,
      scope: scope,
      items: profiles,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<EmployeeProfile>> loadLocalEmployeeProfiles({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _employeeProfilesKey,
      scope: scope,
      fromMap: EmployeeProfile.fromMap,
    );
  }

  static Future<void> saveLocalEmployeeProfiles(
    List<EmployeeProfile> profiles, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _employeeProfilesKey,
      scope: scope,
      items: profiles,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<SollzeitProfile>> loadLocalSollzeitProfiles({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _sollzeitProfilesKey,
      scope: scope,
      fromMap: SollzeitProfile.fromMap,
    );
  }

  static Future<void> saveLocalSollzeitProfiles(
    List<SollzeitProfile> profiles, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _sollzeitProfilesKey,
      scope: scope,
      items: profiles,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<OrgPayrollSettings>> loadLocalOrgPayrollSettings({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _payrollConfigKey,
      scope: scope,
      fromMap: OrgPayrollSettings.fromMap,
    );
  }

  static Future<void> saveLocalOrgPayrollSettings(
    List<OrgPayrollSettings> configs, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _payrollConfigKey,
      scope: scope,
      items: configs,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<EmployeeChild>> loadLocalEmployeeChildren({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _employeeChildrenKey,
      scope: scope,
      fromMap: EmployeeChild.fromMap,
    );
  }

  static Future<void> saveLocalEmployeeChildren(
    List<EmployeeChild> children, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _employeeChildrenKey,
      scope: scope,
      items: children,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<EmployeeNote>> loadLocalEmployeeNotes({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _employeeNotesKey,
      scope: scope,
      fromMap: EmployeeNote.fromMap,
    );
  }

  static Future<void> saveLocalEmployeeNotes(
    List<EmployeeNote> notes, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _employeeNotesKey,
      scope: scope,
      items: notes,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<EmployeeQualification>> loadLocalEmployeeQualifications({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _employeeQualificationsKey,
      scope: scope,
      fromMap: EmployeeQualification.fromMap,
    );
  }

  static Future<void> saveLocalEmployeeQualifications(
    List<EmployeeQualification> quals, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _employeeQualificationsKey,
      scope: scope,
      items: quals,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<EmployeeAusbildung>> loadLocalEmployeeAusbildungen({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _employeeAusbildungenKey,
      scope: scope,
      fromMap: EmployeeAusbildung.fromMap,
    );
  }

  static Future<void> saveLocalEmployeeAusbildungen(
    List<EmployeeAusbildung> ausbildungen, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _employeeAusbildungenKey,
      scope: scope,
      items: ausbildungen,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<UrlaubskontoJahr>> loadLocalUrlaubskontoJahre({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _urlaubskontoJahreKey,
      scope: scope,
      fromMap: UrlaubskontoJahr.fromMap,
    );
  }

  static Future<void> saveLocalUrlaubskontoJahre(
    List<UrlaubskontoJahr> konten, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _urlaubskontoJahreKey,
      scope: scope,
      items: konten,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<Urlaubsanpassung>> loadLocalUrlaubsanpassungen({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _urlaubsanpassungenKey,
      scope: scope,
      fromMap: Urlaubsanpassung.fromMap,
    );
  }

  static Future<void> saveLocalUrlaubsanpassungen(
    List<Urlaubsanpassung> anpassungen, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _urlaubsanpassungenKey,
      scope: scope,
      items: anpassungen,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<PayLineType>> loadLocalPayLineTypes({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _payLineTypesKey,
      scope: scope,
      fromMap: PayLineType.fromMap,
    );
  }

  static Future<void> saveLocalPayLineTypes(
    List<PayLineType> types, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _payLineTypesKey,
      scope: scope,
      items: types,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<CostCenter>> loadLocalCostCenters({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _costCentersKey,
      scope: scope,
      fromMap: CostCenter.fromMap,
    );
  }

  static Future<void> saveLocalCostCenters(
    List<CostCenter> items, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _costCentersKey,
      scope: scope,
      items: items,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<CostType>> loadLocalCostTypes({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _costTypesKey,
      scope: scope,
      fromMap: CostType.fromMap,
    );
  }

  static Future<void> saveLocalCostTypes(
    List<CostType> items, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _costTypesKey,
      scope: scope,
      items: items,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<JournalEntry>> loadLocalJournalEntries({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _journalEntriesKey,
      scope: scope,
      fromMap: JournalEntry.fromMap,
      compare: (a, b) => b.date.compareTo(a.date),
    );
  }

  static Future<void> saveLocalJournalEntries(
    List<JournalEntry> items, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _journalEntriesKey,
      scope: scope,
      items: items,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<Budget>> loadLocalBudgets({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _budgetsKey,
      scope: scope,
      fromMap: Budget.fromMap,
    );
  }

  static Future<void> saveLocalBudgets(
    List<Budget> items, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _budgetsKey,
      scope: scope,
      items: items,
      toMap: (item) => item.toMap(),
    );
  }

  /// DATEV-Export-Konfiguration (ein Objekt je Org, lokal/gerätegebunden).
  static Future<DatevExportConfig?> loadLocalDatevConfig({
    LocalStorageScope? scope,
  }) async {
    final list = await _loadCollection(
      key: _datevConfigKey,
      scope: scope,
      fromMap: DatevExportConfig.fromMap,
    );
    return list.isEmpty ? null : list.first;
  }

  static Future<void> saveLocalDatevConfig(
    DatevExportConfig config, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _datevConfigKey,
      scope: scope,
      items: [config],
      toMap: (item) => item.toMap(),
    );
  }

  /// Org-weite operative Einstellungen (ein Objekt je Org, lokal gespiegelt für
  /// Local-/Hybrid-Modus). Gibt null zurück, wenn nichts hinterlegt ist —
  /// Aufrufer nutzt dann [OrgSettings.defaults].
  static Future<OrgSettings?> loadLocalOrgSettings({
    LocalStorageScope? scope,
  }) async {
    final list = await _loadCollection(
      key: _orgSettingsKey,
      scope: scope,
      fromMap: OrgSettings.fromMap,
    );
    return list.isEmpty ? null : list.first;
  }

  static Future<void> saveLocalOrgSettings(
    OrgSettings settings, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _orgSettingsKey,
      scope: scope,
      items: [settings],
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<AuditLogEntry>> loadLocalAuditLog({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _auditLogKey,
      scope: scope,
      fromMap: AuditLogEntry.fromMap,
      compare: (a, b) => (b.createdAt ?? DateTime(0))
          .compareTo(a.createdAt ?? DateTime(0)),
    );
  }

  static Future<void> saveLocalAuditLog(
    List<AuditLogEntry> entries, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _auditLogKey,
      scope: scope,
      items: entries,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<EmployeeSiteAssignment>> loadLocalSiteAssignments({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _siteAssignmentsKey,
      scope: scope,
      fromMap: EmployeeSiteAssignment.fromMap,
      compare: (a, b) => a.siteName.toLowerCase().compareTo(
            b.siteName.toLowerCase(),
          ),
    );
  }

  static Future<void> saveLocalSiteAssignments(
    List<EmployeeSiteAssignment> assignments, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _siteAssignmentsKey,
      scope: scope,
      items: assignments,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<EmployeeShiftPreference>> loadLocalShiftPreferences({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _shiftPreferencesKey,
      scope: scope,
      fromMap: EmployeeShiftPreference.fromMap,
      compare: (a, b) => a.userId.compareTo(b.userId),
    );
  }

  static Future<void> saveLocalShiftPreferences(
    List<EmployeeShiftPreference> preferences, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _shiftPreferencesKey,
      scope: scope,
      items: preferences,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<ComplianceRuleSet>> loadLocalRuleSets({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _ruleSetsKey,
      scope: scope,
      fromMap: ComplianceRuleSet.fromMap,
      compare: (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  static Future<void> saveLocalRuleSets(
    List<ComplianceRuleSet> ruleSets, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _ruleSetsKey,
      scope: scope,
      items: ruleSets,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<TravelTimeRule>> loadLocalTravelTimeRules({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _travelTimeRulesKey,
      scope: scope,
      fromMap: TravelTimeRule.fromMap,
      compare: (a, b) => a.fromSiteId.compareTo(b.fromSiteId),
    );
  }

  static Future<void> saveLocalTravelTimeRules(
    List<TravelTimeRule> rules, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _travelTimeRulesKey,
      scope: scope,
      items: rules,
      toMap: (item) => item.toMap(),
    );
  }

  // --- Warenwirtschaft (lokale Persistenz) -------------------------------

  static Future<List<Supplier>> loadLocalSuppliers({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _suppliersKey,
      scope: scope,
      fromMap: Supplier.fromMap,
      compare: (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  static Future<void> saveLocalSuppliers(
    List<Supplier> suppliers, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _suppliersKey,
      scope: scope,
      items: suppliers,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<Product>> loadLocalProducts({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _productsKey,
      scope: scope,
      fromMap: Product.fromMap,
      compare: (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  static Future<void> saveLocalProducts(
    List<Product> products, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _productsKey,
      scope: scope,
      items: products,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<ProductBatch>> loadLocalProductBatches({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _productBatchesKey,
      scope: scope,
      fromMap: ProductBatch.fromMap,
      compare: (a, b) => a.expiryDate.compareTo(b.expiryDate),
    );
  }

  static Future<void> saveLocalProductBatches(
    List<ProductBatch> batches, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _productBatchesKey,
      scope: scope,
      items: batches,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<PurchaseOrder>> loadLocalPurchaseOrders({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _purchaseOrdersKey,
      scope: scope,
      fromMap: PurchaseOrder.fromMap,
      compare: (a, b) => (b.orderNumber ?? '').compareTo(a.orderNumber ?? ''),
    );
  }

  static Future<void> saveLocalPurchaseOrders(
    List<PurchaseOrder> orders, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _purchaseOrdersKey,
      scope: scope,
      items: orders,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<CustomerOrder>> loadLocalCustomerOrders({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _customerOrdersKey,
      scope: scope,
      fromMap: CustomerOrder.fromMap,
      compare: (a, b) => (b.orderNumber ?? '').compareTo(a.orderNumber ?? ''),
    );
  }

  static Future<void> saveLocalCustomerOrders(
    List<CustomerOrder> orders, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _customerOrdersKey,
      scope: scope,
      items: orders,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<SiteOrderList>> loadLocalOrderCarts({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _orderCartsKey,
      scope: scope,
      fromMap: SiteOrderList.fromMap,
      compare: (a, b) => a.siteId.compareTo(b.siteId),
    );
  }

  static Future<void> saveLocalOrderCarts(
    List<SiteOrderList> carts, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _orderCartsKey,
      scope: scope,
      items: carts,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<SiteOrderList>> loadLocalWeeklyOrderLists({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _weeklyOrderListsKey,
      scope: scope,
      fromMap: SiteOrderList.fromMap,
      compare: (a, b) => a.siteId.compareTo(b.siteId),
    );
  }

  static Future<void> saveLocalWeeklyOrderLists(
    List<SiteOrderList> lists, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _weeklyOrderListsKey,
      scope: scope,
      items: lists,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<FridgeRefillList>> loadLocalFridgeRefillLists({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _fridgeRefillListsKey,
      scope: scope,
      fromMap: FridgeRefillList.fromMap,
      compare: (a, b) => a.siteId.compareTo(b.siteId),
    );
  }

  static Future<void> saveLocalFridgeRefillLists(
    List<FridgeRefillList> lists, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _fridgeRefillListsKey,
      scope: scope,
      items: lists,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<StockMovement>> loadLocalStockMovements({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _stockMovementsKey,
      scope: scope,
      fromMap: StockMovement.fromMap,
      compare: (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
    );
  }

  static Future<void> saveLocalStockMovements(
    List<StockMovement> movements, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _stockMovementsKey,
      scope: scope,
      items: movements,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<PriceHistoryEntry>> loadLocalPriceHistory({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _priceHistoryKey,
      scope: scope,
      fromMap: PriceHistoryEntry.fromMap,
      compare: (a, b) => (b.changedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.changedAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
    );
  }

  static Future<void> saveLocalPriceHistory(
    List<PriceHistoryEntry> entries, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _priceHistoryKey,
      scope: scope,
      items: entries,
      toMap: (item) => item.toMap(),
    );
  }

  // --- Kontakte (lokale Persistenz) --------------------------------------

  static Future<List<Contact>> loadLocalContacts({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _contactsKey,
      scope: scope,
      fromMap: Contact.fromMap,
      compare: (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  static Future<void> saveLocalContacts(
    List<Contact> contacts, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _contactsKey,
      scope: scope,
      items: contacts,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<List<ContactOrganization>> loadLocalContactOrganizations({
    LocalStorageScope? scope,
  }) {
    return _loadCollection(
      key: _contactOrganizationsKey,
      scope: scope,
      fromMap: ContactOrganization.fromMap,
      compare: (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  static Future<void> saveLocalContactOrganizations(
    List<ContactOrganization> organizations, {
    LocalStorageScope? scope,
  }) {
    return _saveCollection(
      key: _contactOrganizationsKey,
      scope: scope,
      items: organizations,
      toMap: (item) => item.toMap(),
    );
  }

  static Future<String?> loadLocalAuthUserId() async {
    final prefs = await _prefs;
    return prefs.getString(_localAuthUserIdKey);
  }

  static Future<void> saveLocalAuthUserId(String? userId) async {
    final prefs = await _prefs;
    final normalizedUserId = userId?.trim();
    if (normalizedUserId == null || normalizedUserId.isEmpty) {
      await prefs.remove(_localAuthUserIdKey);
      return;
    }
    await prefs.setString(_localAuthUserIdKey, normalizedUserId);
  }

  static Future<UserSettings> loadLegacyUserSettings() {
    return loadLocalUserSettings();
  }

  static Future<UserSettings> loadLocalUserSettings({
    LocalStorageScope? scope,
  }) async {
    final name = await getLocalSetting('name', scope: scope) ?? '';
    final rate = double.tryParse(
            await getLocalSetting('hourly_rate', scope: scope) ?? '0') ??
        0;
    final hours = double.tryParse(
            await getLocalSetting('daily_hours', scope: scope) ?? '8') ??
        8;
    final currency = await getLocalSetting('currency', scope: scope) ?? 'EUR';
    final vacationDays = int.tryParse(
            await getLocalSetting('vacation_days', scope: scope) ?? '30') ??
        30;
    final autoBreak = int.tryParse(
          await getLocalSetting(
                'auto_break_after_minutes',
                scope: scope,
              ) ??
              '360',
        ) ??
        360;

    return UserSettings(
      name: name,
      hourlyRate: rate,
      dailyHours: hours,
      currency: currency,
      vacationDays: vacationDays,
      autoBreakAfterMinutes: autoBreak,
    );
  }

  static Future<void> saveLocalUserSettings(
    UserSettings settings, {
    LocalStorageScope? scope,
  }) async {
    final prefs = await _prefs;
    if (scope != null) {
      await _ensureScopedStorageInitialized(prefs, scope);
    }
    final entries = <String, String>{
      'name': settings.name,
      // SICHERHEIT (no-secure-storage-for-sensitive): Stundenlohn als Klartext.
      // Geringere Sensibilitaet (eigene Daten), siehe Hinweis an
      // saveLocalEmploymentContracts fuer die Remediation.
      'hourly_rate': settings.hourlyRate.toString(),
      'daily_hours': settings.dailyHours.toString(),
      'currency': settings.currency,
      'vacation_days': settings.vacationDays.toString(),
      'auto_break_after_minutes': settings.autoBreakAfterMinutes.toString(),
    };
    await Future.wait(
      entries.entries.map(
        (entry) =>
            prefs.setString(_resolveSettingKey(entry.key, scope), entry.value),
      ),
    );
  }

  static Future<String> loadDataStorageLocation() async {
    final raw = await getLocalSetting(_dataStorageLocationKey);
    final normalized = raw?.trim().toLowerCase();
    if (normalized == 'local') {
      return 'local';
    }
    if (normalized == 'cloud') {
      return 'cloud';
    }
    return 'hybrid';
  }

  static Future<void> saveDataStorageLocation(String location) async {
    final normalized = location.trim().toLowerCase();
    await saveLocalSetting(
      _dataStorageLocationKey,
      switch (normalized) {
        'local' => 'local',
        'cloud' => 'cloud',
        _ => 'hybrid',
      },
    );
  }

  static Future<bool> hasLegacyData() async {
    final prefs = await _prefs;
    final hasEntries =
        (prefs.getStringList(_entriesKey) ?? const []).isNotEmpty;
    final hasTemplates =
        (prefs.getStringList(_templatesKey) ?? const []).isNotEmpty;
    final hasSettings = _legacyWorkSettingKeys.any(
      (key) => prefs.containsKey(_resolveGlobalSettingKey(key)),
    );
    return hasEntries || hasTemplates || hasSettings;
  }

  static Future<void> clearLegacyWorkData() async {
    final prefs = await _prefs;
    await prefs.remove(_entriesKey);
    await prefs.remove(_templatesKey);
    for (final key in _legacyWorkSettingKeys) {
      await prefs.remove(_resolveGlobalSettingKey(key));
    }
  }

  static Future<void> saveLocalSetting(
    String key,
    String value, {
    LocalStorageScope? scope,
  }) async {
    final prefs = await _prefs;
    if (scope != null) {
      await _ensureScopedStorageInitialized(prefs, scope);
    }
    await prefs.setString(_resolveSettingKey(key, scope), value);
  }

  static Future<String?> getLocalSetting(
    String key, {
    LocalStorageScope? scope,
  }) async {
    final prefs = await _prefs;
    if (scope != null) {
      await _ensureScopedStorageInitialized(prefs, scope);
    }
    return prefs.getString(_resolveSettingKey(key, scope));
  }

  static Future<void> removeLocalSetting(
    String key, {
    LocalStorageScope? scope,
  }) async {
    final prefs = await _prefs;
    if (scope != null) {
      await _ensureScopedStorageInitialized(prefs, scope);
    }
    await prefs.remove(_resolveSettingKey(key, scope));
  }

  // --- Tombstones (Soft-Delete gegen Wiederauferstehen beim Mode-Switch) ---
  //
  // Wird ein Datensatz im local-Modus geloescht, bleibt der Firestore-Doc evtl.
  // bestehen und wuerde beim Wechsel in hybrid/cloud erneut eingespielt. Eine
  // persistierte Menge geloeschter IDs unterdrueckt das Re-Adden, bis die
  // Loeschung in die Cloud propagiert wurde.

  static String _tombstoneKey(String collectionKey, LocalStorageScope? scope) {
    return '${_resolveCollectionKey(collectionKey, scope)}.__tombstones';
  }

  static Future<Set<String>> loadTombstones(
    String collectionKey, {
    LocalStorageScope? scope,
  }) async {
    final prefs = await _prefs;
    if (scope != null) {
      await _ensureScopedStorageInitialized(prefs, scope);
    }
    final raw = prefs.getStringList(_tombstoneKey(collectionKey, scope)) ??
        const <String>[];
    return raw.toSet();
  }

  static Future<void> saveTombstones(
    String collectionKey,
    Set<String> ids, {
    LocalStorageScope? scope,
  }) async {
    final prefs = await _prefs;
    if (scope != null) {
      await _ensureScopedStorageInitialized(prefs, scope);
    }
    await prefs.setStringList(
      _tombstoneKey(collectionKey, scope),
      ids.toList(growable: false),
    );
  }

  static Future<List<T>> _loadCollection<T>({
    required String key,
    required T Function(Map<String, dynamic> map) fromMap,
    int Function(T a, T b)? compare,
    LocalStorageScope? scope,
  }) async {
    final prefs = await _prefs;
    if (scope != null) {
      await _ensureScopedStorageInitialized(prefs, scope);
    }

    final rawItems = prefs.getStringList(_resolveCollectionKey(key, scope)) ??
        const <String>[];
    final items = <T>[];
    for (final raw in rawItems) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        items.add(fromMap(map));
      } on FormatException catch (error, stackTrace) {
        // Korrupte JSON-Eintraege ueberspringen statt die App zu crashen —
        // aber protokollieren, damit ein versehentlicher Daten-Drop (z.B.
        // bei vergessener Schema-Migration) nicht voellig unsichtbar bleibt
        // (probleme #6).
        AppLogger.warning(
          'Lokaler Eintrag uebersprungen (kaputtes JSON)',
          error: error,
          stackTrace: stackTrace,
          fields: {'collection': key},
        );
        continue;
      } on TypeError catch (error, stackTrace) {
        // Typ-Inkompatibilitaet (z.B. Modell-Feld hat den Typ gewechselt ohne
        // erhoehte currentLocalSchemaVersion + Migration) -> Eintrag faellt
        // sonst lautlos weg. Protokollieren (probleme #6).
        AppLogger.warning(
          'Lokaler Eintrag uebersprungen (Typ-Inkompatibilitaet — '
          'fehlende Schema-Migration?)',
          error: error,
          stackTrace: stackTrace,
          fields: {'collection': key},
        );
        continue;
      }
    }

    if (compare != null) {
      items.sort(compare);
    }
    return items;
  }

  static Future<void> _saveCollection<T>({
    required String key,
    required List<T> items,
    required Map<String, dynamic> Function(T item) toMap,
    LocalStorageScope? scope,
  }) async {
    final prefs = await _prefs;
    if (scope != null) {
      await _ensureScopedStorageInitialized(prefs, scope);
    }

    final serialized =
        items.map((item) => jsonEncode(toMap(item))).toList(growable: false);
    await prefs.setStringList(_resolveCollectionKey(key, scope), serialized);
  }

  static Future<void> _ensureScopedStorageInitialized(
    SharedPreferences prefs,
    LocalStorageScope scope,
  ) async {
    if (!scope.isValid) {
      return;
    }

    await _ensureOrgScopedStorageInitialized(prefs, scope);
    await _ensureUserScopedStorageInitialized(prefs, scope);
    await _ensureScopedSchemaVersion(prefs, _orgScopeSchemaVersionKey(scope));
    await _ensureScopedSchemaVersion(prefs, _userScopeSchemaVersionKey(scope));
  }

  /// Versioniert die lokale Persistenz pro Scope. Liest die gespeicherte
  /// Version (0 = noch keine), fuehrt geordnete, vorwaertsgerichtete
  /// Migrationsschritte aus und stempelt am Ende [currentLocalSchemaVersion].
  /// Aktuell ist Version 1 der Ist-Zustand -> ein No-op-Stempel; die toleranten
  /// Parser (FormatException/TypeError werden in _loadCollection uebersprungen)
  /// bleiben als Defense-in-Depth bestehen.
  static Future<void> _ensureScopedSchemaVersion(
    SharedPreferences prefs,
    String versionKey,
  ) async {
    final stored = prefs.getInt(versionKey) ?? 0;
    if (stored >= currentLocalSchemaVersion) {
      return;
    }
    // Künftige Migrationen hier einhaengen, z. B.:
    //   if (stored < 2) { await _migrateV1ToV2(prefs, ...); }
    await prefs.setInt(versionKey, currentLocalSchemaVersion);
  }

  static Future<void> _ensureOrgScopedStorageInitialized(
    SharedPreferences prefs,
    LocalStorageScope scope,
  ) async {
    final initializedKey = _orgScopeInitializedMarkerKey(scope);
    if (prefs.getString(initializedKey) == 'true') {
      return;
    }

    if (_hasOrgScopedData(prefs, scope)) {
      await prefs.setString(initializedKey, 'true');
      return;
    }

    await _migrateScopedCollection<WorkEntry>(
      prefs: prefs,
      key: _entriesKey,
      scope: scope,
      legacyItems: await loadLegacyEntries(),
      filter: (entry) => _matchesScopedOrgItem(entry.orgId, scope),
      toMap: (entry) => entry.toMap(),
    );
    await _migrateScopedCollection<Shift>(
      prefs: prefs,
      key: _shiftsKey,
      scope: scope,
      legacyItems: await loadLocalShifts(),
      filter: (shift) => _matchesScopedOrgItem(shift.orgId, scope),
      toMap: (shift) => shift.toMap(),
    );
    await _migrateScopedCollection<ShiftTemplate>(
      prefs: prefs,
      key: _shiftTemplatesKey,
      scope: scope,
      legacyItems: await loadLocalShiftTemplates(),
      filter: (template) =>
          _matchesScopedOrgItem(template.orgId, scope) &&
          (template.userId.isEmpty ||
              template.userId == scope.normalizedUserId),
      toMap: (template) => template.toMap(),
    );
    await _migrateScopedCollection<AbsenceRequest>(
      prefs: prefs,
      key: _absenceRequestsKey,
      scope: scope,
      legacyItems: await loadLocalAbsenceRequests(),
      filter: (request) => _matchesScopedOrgItem(request.orgId, scope),
      toMap: (request) => request.toMap(),
    );
    await _migrateScopedCollection<AppUserProfile>(
      prefs: prefs,
      key: _membersKey,
      scope: scope,
      legacyItems: await loadLocalTeamMembers(),
      filter: (member) => _matchesScopedOrgItem(member.orgId, scope),
      toMap: (member) => member.toMap(),
    );
    await _migrateScopedCollection<UserInvite>(
      prefs: prefs,
      key: _invitesKey,
      scope: scope,
      legacyItems: await loadLocalInvites(),
      filter: (invite) => _matchesScopedOrgItem(invite.orgId, scope),
      toMap: (invite) => invite.toMap(),
    );
    await _migrateScopedCollection<TeamDefinition>(
      prefs: prefs,
      key: _teamsKey,
      scope: scope,
      legacyItems: await loadLocalTeams(),
      filter: (team) => _matchesScopedOrgItem(team.orgId, scope),
      toMap: (team) => team.toMap(),
    );
    await _migrateScopedCollection<SiteDefinition>(
      prefs: prefs,
      key: _sitesKey,
      scope: scope,
      legacyItems: await loadLocalSites(),
      filter: (site) => _matchesScopedOrgItem(site.orgId, scope),
      toMap: (site) => site.toMap(),
    );
    await _migrateScopedCollection<QualificationDefinition>(
      prefs: prefs,
      key: _qualificationsKey,
      scope: scope,
      legacyItems: await loadLocalQualifications(),
      filter: (item) => _matchesScopedOrgItem(item.orgId, scope),
      toMap: (item) => item.toMap(),
    );
    await _migrateScopedCollection<EmploymentContract>(
      prefs: prefs,
      key: _contractsKey,
      scope: scope,
      legacyItems: await loadLocalEmploymentContracts(),
      filter: (contract) => _matchesScopedOrgItem(contract.orgId, scope),
      toMap: (contract) => contract.toMap(),
    );
    await _migrateScopedCollection<EmployeeSiteAssignment>(
      prefs: prefs,
      key: _siteAssignmentsKey,
      scope: scope,
      legacyItems: await loadLocalSiteAssignments(),
      filter: (assignment) => _matchesScopedOrgItem(assignment.orgId, scope),
      toMap: (assignment) => assignment.toMap(),
    );
    await _migrateScopedCollection<ComplianceRuleSet>(
      prefs: prefs,
      key: _ruleSetsKey,
      scope: scope,
      legacyItems: await loadLocalRuleSets(),
      filter: (ruleSet) => _matchesScopedOrgItem(ruleSet.orgId, scope),
      toMap: (ruleSet) => ruleSet.toMap(),
    );
    await _migrateScopedCollection<TravelTimeRule>(
      prefs: prefs,
      key: _travelTimeRulesKey,
      scope: scope,
      legacyItems: await loadLocalTravelTimeRules(),
      filter: (rule) => _matchesScopedOrgItem(rule.orgId, scope),
      toMap: (rule) => rule.toMap(),
    );

    await prefs.setString(initializedKey, 'true');
  }

  static Future<void> _ensureUserScopedStorageInitialized(
    SharedPreferences prefs,
    LocalStorageScope scope,
  ) async {
    final initializedKey = _userScopeInitializedMarkerKey(scope);
    if (prefs.getString(initializedKey) == 'true') {
      return;
    }

    if (_hasUserScopedData(prefs, scope)) {
      await prefs.setString(initializedKey, 'true');
      return;
    }

    await _migrateScopedCollection<WorkTemplate>(
      prefs: prefs,
      key: _templatesKey,
      scope: scope,
      legacyItems: await loadLegacyTemplates(),
      filter: (template) => _matchesScopedWorkTemplate(template, scope),
      toMap: (template) => template.toMap(),
    );

    for (final key in _legacyWorkSettingKeys) {
      final legacyValue = prefs.getString(_resolveGlobalSettingKey(key));
      if (legacyValue == null) {
        continue;
      }
      await prefs.setString(_resolveSettingKey(key, scope), legacyValue);
    }

    await prefs.setString(initializedKey, 'true');
  }

  static Future<void> _migrateScopedCollection<T>({
    required SharedPreferences prefs,
    required String key,
    required LocalStorageScope scope,
    required List<T> legacyItems,
    required bool Function(T item) filter,
    required Map<String, dynamic> Function(T item) toMap,
  }) async {
    final filteredItems = legacyItems.where(filter).toList(growable: false);
    if (filteredItems.isEmpty) {
      return;
    }

    await prefs.setStringList(
      _resolveCollectionKey(key, scope),
      filteredItems
          .map((item) => jsonEncode(toMap(item)))
          .toList(growable: false),
    );
  }

  static bool _matchesScopedWorkTemplate(
    WorkTemplate template,
    LocalStorageScope scope,
  ) {
    return _matchesScopedOrgItem(template.orgId, scope) &&
        (template.userId.isEmpty || template.userId == scope.normalizedUserId);
  }

  static bool _matchesScopedOrgItem(
    String orgId,
    LocalStorageScope scope,
  ) {
    final normalizedOrgId = orgId.trim();
    return normalizedOrgId.isEmpty || normalizedOrgId == scope.normalizedOrgId;
  }

  static bool _hasOrgScopedData(
    SharedPreferences prefs,
    LocalStorageScope scope,
  ) {
    final prefix = _orgScopePrefix(scope);
    return prefs.getKeys().any(
          (key) =>
              key.startsWith(prefix) &&
              key != _orgScopeInitializedMarkerKey(scope),
        );
  }

  static bool _hasUserScopedData(
    SharedPreferences prefs,
    LocalStorageScope scope,
  ) {
    final prefix = _userScopePrefix(scope);
    return prefs.getKeys().any(
          (key) =>
              key.startsWith(prefix) &&
              key != _userScopeInitializedMarkerKey(scope),
        );
  }

  static String _resolveCollectionKey(
    String key,
    LocalStorageScope? scope,
  ) {
    if (scope == null) {
      return key;
    }
    final prefix = _orgScopedCollectionKeys.contains(key)
        ? _orgScopePrefix(scope)
        : _userScopePrefix(scope);
    return '$prefix$key';
  }

  static String _resolveSettingKey(
    String key,
    LocalStorageScope? scope,
  ) {
    if (scope == null) {
      return _resolveGlobalSettingKey(key);
    }
    return '${_userScopePrefix(scope)}$_settingsPrefix$key';
  }

  static String _resolveGlobalSettingKey(String key) {
    return '$_settingsPrefix$key';
  }

  static String _orgScopePrefix(LocalStorageScope scope) {
    return '$_scopedPrefix/org/${Uri.encodeComponent(scope.normalizedOrgId)}/';
  }

  static String _userScopePrefix(LocalStorageScope scope) {
    return '${_orgScopePrefix(scope)}user/${Uri.encodeComponent(scope.normalizedUserId)}/';
  }

  static String _orgScopeInitializedMarkerKey(LocalStorageScope scope) {
    return '${_orgScopePrefix(scope)}$_orgScopeInitializedKey';
  }

  static String _userScopeInitializedMarkerKey(LocalStorageScope scope) {
    return '${_userScopePrefix(scope)}$_userScopeInitializedKey';
  }

  static String _orgScopeSchemaVersionKey(LocalStorageScope scope) {
    return '${_orgScopePrefix(scope)}$_schemaVersionKey';
  }

  static String _userScopeSchemaVersionKey(LocalStorageScope scope) {
    return '${_userScopePrefix(scope)}$_schemaVersionKey';
  }
}
