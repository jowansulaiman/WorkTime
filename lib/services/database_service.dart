import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/compliance_rule_set.dart';
import '../models/employee_site_assignment.dart';
import '../models/employment_contract.dart';
import '../models/qualification_definition.dart';
import '../models/shift.dart';
import '../models/shift_template.dart';
import '../models/site_definition.dart';
import '../models/team_definition.dart';
import '../models/travel_time_rule.dart';
import '../models/user_settings.dart';
import '../models/user_invite.dart';
import '../models/work_entry.dart';
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
  static const _templatesKey = 'work_templates';
  static const _shiftsKey = 'schedule_shifts';
  static const _shiftTemplatesKey = 'shift_templates';
  static const _absenceRequestsKey = 'absence_requests';
  static const _membersKey = 'team_members';
  static const _invitesKey = 'team_invites';
  static const _teamsKey = 'teams';
  static const _sitesKey = 'sites';
  static const _qualificationsKey = 'qualifications';
  static const _contractsKey = 'employment_contracts';
  static const _siteAssignmentsKey = 'employee_site_assignments';
  static const _ruleSetsKey = 'compliance_rule_sets';
  static const _travelTimeRulesKey = 'travel_time_rules';
  static const _localAuthUserIdKey = 'local_auth_user_id';
  static const _settingsPrefix = 'setting_';
  static const _dataStorageLocationKey = 'data_storage_location';
  static const _scopedPrefix = 'local_v2';
  static const _orgScopeInitializedKey = '__org_initialized';
  static const _userScopeInitializedKey = '__user_initialized';
  static const _orgScopedCollectionKeys = <String>{
    _entriesKey,
    _shiftsKey,
    _shiftTemplatesKey,
    _absenceRequestsKey,
    _membersKey,
    _invitesKey,
    _teamsKey,
    _sitesKey,
    _qualificationsKey,
    _contractsKey,
    _siteAssignmentsKey,
    _ruleSetsKey,
    _travelTimeRulesKey,
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
      } on FormatException {
        // Korrupte JSON-Eintraege ueberspringen statt die App zu crashen.
        continue;
      } on TypeError {
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
}
