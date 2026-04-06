import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/compliance_rule_set_utils.dart';
import '../models/app_user.dart';
import '../models/compliance_rule_set.dart';
import '../models/compliance_violation.dart';
import '../models/employee_site_assignment.dart';
import '../models/employment_contract.dart';
import '../models/site_definition.dart';
import '../models/shift.dart';
import '../models/travel_time_rule.dart';
import '../models/user_settings.dart';
import '../models/work_entry.dart';
import '../models/work_template.dart';
import '../services/compliance_service.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';

const _clockInKey = 'clock_in_time';
const _clockInSiteIdKey = 'clock_in_site_id';
const _clockInSiteNameKey = 'clock_in_site_name';

class OvertimeApprovalRequired implements Exception {
  const OvertimeApprovalRequired({
    required this.shift,
    required this.entryStart,
    required this.entryEnd,
    this.entryId,
    this.beforeShiftStart,
    this.beforeShiftEnd,
    this.afterShiftStart,
    this.afterShiftEnd,
  });

  final Shift shift;
  final DateTime entryStart;
  final DateTime entryEnd;
  final String? entryId;
  final DateTime? beforeShiftStart;
  final DateTime? beforeShiftEnd;
  final DateTime? afterShiftStart;
  final DateTime? afterShiftEnd;

  bool get hasBeforeShiftOvertime =>
      beforeShiftStart != null &&
      beforeShiftEnd != null &&
      beforeShiftEnd!.isAfter(beforeShiftStart!);

  bool get hasAfterShiftOvertime =>
      afterShiftStart != null &&
      afterShiftEnd != null &&
      afterShiftEnd!.isAfter(afterShiftStart!);

  bool get hasOvertime => hasBeforeShiftOvertime || hasAfterShiftOvertime;

  Duration get overtimeDuration {
    var total = Duration.zero;
    if (hasBeforeShiftOvertime) {
      total += beforeShiftEnd!.difference(beforeShiftStart!);
    }
    if (hasAfterShiftOvertime) {
      total += afterShiftEnd!.difference(afterShiftStart!);
    }
    return total;
  }

  @override
  String toString() {
    return 'Der Eintrag liegt teilweise ausserhalb der geplanten Schicht '
        'und benoetigt eine Ueberstunden-Freigabe.';
  }
}

/// Callback der aufgerufen wird, wenn ein Arbeitszeiteintrag fuer eine
/// Schicht gespeichert wurde (sourceShiftId).
typedef OnShiftWorked = void Function(String sourceShiftId);

class WorkProvider extends ChangeNotifier {
  WorkProvider({
    required FirestoreService firestoreService,
    ComplianceService? complianceService,
    this.onShiftWorked,
    bool? disableAuthentication,
  })  : _firestoreService = firestoreService,
        _complianceService = complianceService ?? const ComplianceService(),
        _forceLocalStorage =
            disableAuthentication ?? AppConfig.disableAuthentication;

  /// Wird gesetzt, sobald die Provider in main.dart verkabelt sind.
  OnShiftWorked? onShiftWorked;

  final FirestoreService _firestoreService;
  final ComplianceService _complianceService;
  final bool _forceLocalStorage;
  bool _localStorageOnly = false;
  bool _hybridStorageEnabled = false;

  StreamSubscription<List<WorkEntry>>? _entriesSubscription;
  StreamSubscription<List<WorkTemplate>>? _templatesSubscription;
  StreamSubscription<List<WorkEntry>>? _reportEntriesSubscription;

  AppUserProfile? _currentUser;
  AppUserProfile? _reportUser;
  DateTime _selectedMonth = DateTime.now();
  List<WorkEntry> _entries = [];
  List<WorkTemplate> _templates = [];
  List<WorkEntry> _reportEntries = [];
  List<WorkEntry> _localEntries = [];
  List<WorkTemplate> _localTemplates = [];
  List<SiteDefinition> _sites = [];
  List<AppUserProfile> _members = [];
  List<EmploymentContract> _contracts = [];
  List<EmployeeSiteAssignment> _siteAssignments = [];
  List<ComplianceRuleSet> _ruleSets = [];
  List<TravelTimeRule> _travelTimeRules = [];
  bool _loading = false;
  String? _errorMessage;
  bool _disposed = false;

  DateTime? _clockInTime;
  String? _clockInSiteId;
  String? _clockInSiteName;
  Timer? _clockTickTimer;
  Timer? _clockAvailabilityTimer;
  Shift? _activeShiftNow;
  WorkEntry? _activeEntrySnapshot;
  bool _checkingClockAvailability = false;
  int _clockAvailabilityRequestId = 0;
  bool _isClockBusy = false;

  AppUserProfile? get currentUser => _currentUser;
  AppUserProfile? get reportUser => _reportUser ?? _currentUser;
  DateTime get selectedMonth => _selectedMonth;
  List<WorkEntry> get entries => _entries;
  List<WorkEntry> get reportEntries =>
      _isReportingCurrentUser ? _entries : _reportEntries;
  List<WorkTemplate> get templates => _templates;
  List<SiteDefinition> get sites => _sites;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;

  bool get _isReportingCurrentUser =>
      reportUser == null || reportUser!.uid == _currentUser?.uid;

  bool get isClockedIn => _clockInTime != null;
  DateTime? get clockInTime => _clockInTime;
  Shift? get activeShiftNow => _activeShiftNow;
  bool get checkingClockAvailability => _checkingClockAvailability;
  WorkEntry? get activeEntryNow =>
      _activeEntrySnapshot ?? _activeEntryAt(DateTime.now());
  bool get isClockBackedByEntry =>
      _clockInTime == null && activeEntryNow != null;
  bool get hasActiveClockSession =>
      _clockInTime != null || activeEntryNow != null;
  DateTime? get effectiveClockStartTime =>
      _clockInTime ?? activeEntryNow?.startTime;

  Duration get clockedDuration {
    if (_clockInTime == null) return Duration.zero;
    return DateTime.now().difference(_clockInTime!);
  }

  Duration get effectiveClockedDuration {
    final start = effectiveClockStartTime;
    if (start == null) {
      return Duration.zero;
    }
    return DateTime.now().difference(start);
  }

  UserSettings get settings => _currentUser?.settings ?? const UserSettings();
  UserSettings get reportSettings =>
      reportUser?.settings ?? const UserSettings();
  bool get usesLocalStorage => _forceLocalStorage || _localStorageOnly;
  bool get usesHybridStorage =>
      !_forceLocalStorage && !_localStorageOnly && _hybridStorageEnabled;

  double get totalHoursThisMonth =>
      _entries.fold(0, (sum, entry) => sum + entry.workedHours);

  double get totalWageThisMonth => totalHoursThisMonth * settings.hourlyRate;

  double get overtimeThisMonth => _entries.fold(0, (sum, entry) {
        final diff = entry.workedHours - settings.dailyHours;
        return sum + (diff > 0 ? diff : 0);
      });

  double get totalReportHoursThisMonth =>
      reportEntries.fold(0, (sum, entry) => sum + entry.workedHours);

  double get totalReportWageThisMonth =>
      totalReportHoursThisMonth * reportSettings.hourlyRate;

  double get reportOvertimeThisMonth => reportEntries.fold(0, (sum, entry) {
        final diff = entry.workedHours - reportSettings.dailyHours;
        return sum + (diff > 0 ? diff : 0);
      });

  String? _lastSessionKey;

  LocalStorageScope? get _localScope {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return null;
    }
    return LocalStorageScope.fromUser(currentUser);
  }

  void updateReferenceData({
    List<AppUserProfile> members = const [],
    required List<SiteDefinition> sites,
    required List<EmploymentContract> contracts,
    required List<EmployeeSiteAssignment> siteAssignments,
    required List<ComplianceRuleSet> ruleSets,
    required List<TravelTimeRule> travelTimeRules,
  }) {
    _members = members;
    _sites = sites;
    _contracts = contracts;
    _siteAssignments = siteAssignments;
    _ruleSets = ruleSets;
    _travelTimeRules = travelTimeRules;
  }

  Future<void> updateSession(
    AppUserProfile? user, {
    bool localStorageOnly = false,
    bool hybridStorageEnabled = false,
  }) async {
    final previousStorageModeKey = _storageModeKey;
    _localStorageOnly = localStorageOnly;
    _hybridStorageEnabled = hybridStorageEnabled;
    final storageModeChanged = previousStorageModeKey != _storageModeKey;
    final sessionKey =
        user == null ? null : '${user.uid}:${user.orgId}:$_storageModeKey';
    if (sessionKey == _lastSessionKey && user != null) {
      if (!usesLocalStorage || _currentUser?.uid != user.uid) {
        _currentUser = user;
        if (_reportUser?.uid == user.uid) {
          _reportUser = user;
        }
      }
      _ensureClockAvailabilityWatcher();
      return;
    }
    _lastSessionKey = sessionKey;

    final changed =
        user?.uid != _currentUser?.uid || user?.orgId != _currentUser?.orgId;
    _currentUser = user;
    if (user == null) {
      _reportUser = null;
      _entries = [];
      _reportEntries = [];
      _templates = [];
      _sites = [];
      _members = [];
      _contracts = [];
      _siteAssignments = [];
      _ruleSets = [];
      _travelTimeRules = [];
      _clockInTime = null;
      _clockInSiteId = null;
      _clockInSiteName = null;
      _activeShiftNow = null;
      _activeEntrySnapshot = null;
      _checkingClockAvailability = false;
      _stopClockTick();
      _stopClockAvailabilityWatcher();
      await _entriesSubscription?.cancel();
      await _templatesSubscription?.cancel();
      await _reportEntriesSubscription?.cancel();
      _safeNotify();
      return;
    }

    if (usesHybridStorage && changed) {
      await _entriesSubscription?.cancel();
      await _templatesSubscription?.cancel();
      await _reportEntriesSubscription?.cancel();
      _entriesSubscription = null;
      _templatesSubscription = null;
      _reportEntriesSubscription = null;
    }

    if (_reportUser == null || changed) {
      _reportUser = user;
    }

    if (usesLocalStorage) {
      await _entriesSubscription?.cancel();
      await _templatesSubscription?.cancel();
      await _reportEntriesSubscription?.cancel();
      if (changed || (_localEntries.isEmpty && _localTemplates.isEmpty)) {
        await _loadLocalState(user);
        await restoreClockState();
      } else {
        _applyLocalState();
      }
      _ensureClockAvailabilityWatcher();
      await refreshCurrentShiftStatus();
      _safeNotify();
      return;
    }

    if (usesHybridStorage) {
      if (changed ||
          storageModeChanged ||
          (_localEntries.isEmpty && _localTemplates.isEmpty)) {
        await _loadLocalState(
          user,
          overrideUserSettings: false,
        );
        await DatabaseService.saveLocalUserSettings(
          user.settings,
          scope: _localScope,
        );
        await restoreClockState();
      }
      if (changed || storageModeChanged) {
        await _restartSubscriptions();
      }
      _ensureClockAvailabilityWatcher();
      await refreshCurrentShiftStatus();
      _safeNotify();
      return;
    }

    if (changed || storageModeChanged) {
      await _restartSubscriptions();
      await restoreClockState();
    }
    _ensureClockAvailabilityWatcher();
    await refreshCurrentShiftStatus();
  }

  Future<void> selectMonth(DateTime month) async {
    _selectedMonth = DateTime(month.year, month.month);
    if (usesLocalStorage) {
      _applyLocalState();
      notifyListeners();
      return;
    }
    if (usesHybridStorage) {
      _applyLocalState();
      _safeNotify();
    }
    await _restartSubscriptions();
  }

  Future<void> nextMonth() async {
    await selectMonth(DateTime(_selectedMonth.year, _selectedMonth.month + 1));
  }

  Future<void> previousMonth() async {
    await selectMonth(DateTime(_selectedMonth.year, _selectedMonth.month - 1));
  }

  Future<void> selectReportUser(AppUserProfile? user) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canViewReports) {
      return;
    }
    _reportUser = currentUser.isAdmin ? (user ?? currentUser) : currentUser;
    if (usesLocalStorage) {
      _applyLocalState();
      notifyListeners();
      return;
    }
    if (usesHybridStorage) {
      _applyLocalState();
      _safeNotify();
    }
    await _restartReportSubscription();
  }

  Future<void> addEntry(WorkEntry entry) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canEditTimeEntries) {
      return;
    }
    final preparedEntry = entry.copyWith(
      orgId: currentUser.orgId,
      userId: currentUser.uid,
    );
    final violations = await validateEntry(preparedEntry);
    final blocking = violations.where((item) => item.isBlocking).toList();
    if (blocking.isNotEmpty) {
      throw StateError(blocking.map((item) => item.message).join('\n'));
    }
    if (usesLocalStorage) {
      final localEntry = preparedEntry.copyWith(
        id: preparedEntry.id ?? _nextLocalId('entry'),
      );
      final index =
          _localEntries.indexWhere((item) => item.id == localEntry.id);
      if (index == -1) {
        _localEntries.add(localEntry);
      } else {
        _localEntries[index] = localEntry;
      }
      await DatabaseService.saveLocalEntries(
        _localEntries,
        scope: _localScope,
      );
      _applyLocalState();
      _notifyShiftWorked(preparedEntry.sourceShiftId);
      notifyListeners();
      return;
    }
    await _firestoreService.saveWorkEntry(
      preparedEntry,
    );
    _notifyShiftWorked(preparedEntry.sourceShiftId);
  }

  Future<void> addEntries(List<WorkEntry> entries) async {
    if (entries.isEmpty) {
      return;
    }
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canEditTimeEntries) {
      return;
    }

    final preparedEntries = <WorkEntry>[];
    for (final entry in entries) {
      final preparedEntry = entry.copyWith(
        orgId: entry.orgId.isNotEmpty ? entry.orgId : currentUser.orgId,
        userId: entry.userId.isNotEmpty ? entry.userId : currentUser.uid,
      );
      final violations = await validateEntry(preparedEntry);
      final blocking = violations.where((item) => item.isBlocking).toList();
      if (blocking.isNotEmpty) {
        throw StateError(blocking.map((item) => item.message).join('\n'));
      }
      preparedEntries.add(preparedEntry);
    }

    if (usesLocalStorage) {
      for (final entry in preparedEntries) {
        final localEntry = entry.copyWith(
          id: entry.id ?? _nextLocalId('entry'),
        );
        final index =
            _localEntries.indexWhere((item) => item.id == localEntry.id);
        if (index == -1) {
          _localEntries.add(localEntry);
        } else {
          _localEntries[index] = localEntry;
        }
      }
      await DatabaseService.saveLocalEntries(
        _localEntries,
        scope: _localScope,
      );
      _applyLocalState();
      for (final entry in preparedEntries) {
        _notifyShiftWorked(entry.sourceShiftId);
      }
      notifyListeners();
      return;
    }

    await _firestoreService.saveWorkEntryBatch(preparedEntries);
    for (final entry in preparedEntries) {
      _notifyShiftWorked(entry.sourceShiftId);
    }
  }

  Future<void> saveEntryWithOvertimeHandling(
    WorkEntry entry, {
    bool allowOvertime = false,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return;
    }

    final preparedEntry = entry.copyWith(
      orgId: entry.orgId.isNotEmpty ? entry.orgId : currentUser.orgId,
      userId: entry.userId.isNotEmpty ? entry.userId : currentUser.uid,
    );

    final referenceShift = await _resolveReferenceShiftForEntry(preparedEntry);
    if (referenceShift == null) {
      await addEntry(preparedEntry);
      return;
    }

    final segments = _splitEntryAgainstShift(
      preparedEntry,
      referenceShift,
    );
    final requiresOvertimeApproval = segments.length > 1 ||
        (segments.isNotEmpty &&
            (segments.first.category?.toLowerCase() == 'overtime'));
    if (requiresOvertimeApproval && !allowOvertime) {
      throw _buildOvertimeApprovalRequired(
        entry: preparedEntry,
        shift: referenceShift,
      );
    }

    await addEntries(segments);
    await refreshCurrentShiftStatus();
  }

  Future<void> updateEntry(WorkEntry entry) async {
    await addEntry(entry);
  }

  Future<void> deleteEntry(String id) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canEditTimeEntries) {
      return;
    }
    if (usesLocalStorage) {
      _localEntries.removeWhere((entry) => entry.id == id);
      await DatabaseService.saveLocalEntries(
        _localEntries,
        scope: _localScope,
      );
      _applyLocalState();
      await refreshCurrentShiftStatus();
      notifyListeners();
      return;
    }
    await _firestoreService.deleteWorkEntry(
      orgId: currentUser.orgId,
      entryId: id,
    );
    await refreshCurrentShiftStatus();
  }

  Future<void> addTemplate(WorkTemplate template) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canEditTimeEntries) {
      return;
    }
    if (usesLocalStorage) {
      final localTemplate = template.copyWith(
        id: template.id ?? _nextLocalId('template'),
        orgId: currentUser.orgId,
        userId: currentUser.uid,
      );
      final index =
          _localTemplates.indexWhere((item) => item.id == localTemplate.id);
      if (index == -1) {
        _localTemplates.add(localTemplate);
      } else {
        _localTemplates[index] = localTemplate;
      }
      await DatabaseService.saveLocalTemplates(
        _localTemplates,
        scope: _localScope,
      );
      _applyLocalState();
      notifyListeners();
      return;
    }
    await _firestoreService.saveWorkTemplate(
      template.copyWith(
        orgId: currentUser.orgId,
        userId: currentUser.uid,
      ),
    );
  }

  Future<void> updateTemplate(WorkTemplate template) async {
    await addTemplate(template);
  }

  Future<void> deleteTemplate(String id) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canEditTimeEntries) {
      return;
    }
    if (usesLocalStorage) {
      _localTemplates.removeWhere((template) => template.id == id);
      await DatabaseService.saveLocalTemplates(
        _localTemplates,
        scope: _localScope,
      );
      _applyLocalState();
      notifyListeners();
      return;
    }
    await _firestoreService.deleteWorkTemplate(
      orgId: currentUser.orgId,
      templateId: id,
    );
  }

  Future<void> updateSettings(UserSettings settings) async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return;
    }
    if (usesLocalStorage) {
      _currentUser = currentUser.copyWith(settings: settings);
      if (_reportUser?.uid == currentUser.uid) {
        _reportUser = _currentUser;
      }
      await DatabaseService.saveLocalUserSettings(
        settings,
        scope: _localScope,
      );
      notifyListeners();
      return;
    }
    await _firestoreService.upsertUserProfile(
      currentUser.copyWith(settings: settings),
    );
    if (usesHybridStorage) {
      await DatabaseService.saveLocalUserSettings(
        settings,
        scope: _localScope,
      );
    }
  }

  Future<void> cacheCloudStateLocally() async {
    final currentUser = _currentUser;
    if (currentUser == null || usesLocalStorage) {
      return;
    }

    _localEntries = [
      ...await _firestoreService.getAllWorkEntries(
        orgId: currentUser.orgId,
        userId: currentUser.uid,
      ),
    ];
    _localTemplates = [
      ...await _firestoreService.getWorkTemplates(
        orgId: currentUser.orgId,
        userId: currentUser.uid,
      ),
    ];
    await DatabaseService.saveLocalEntries(
      _localEntries,
      scope: _localScope,
    );
    await DatabaseService.saveLocalTemplates(
      _localTemplates,
      scope: _localScope,
    );
    await DatabaseService.saveLocalUserSettings(
      currentUser.settings,
      scope: _localScope,
    );
  }

  Future<void> syncLocalStateToCloud() async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return;
    }

    await _firestoreService.upsertUserProfile(currentUser);

    final entries = _localEntries
        .where((entry) =>
            entry.orgId == currentUser.orgId &&
            (entry.userId.isEmpty || entry.userId == currentUser.uid))
        .map((entry) => entry.copyWith(
              orgId: currentUser.orgId,
              userId: entry.userId.isEmpty ? currentUser.uid : entry.userId,
            ))
        .toList(growable: false);
    if (entries.isNotEmpty) {
      await _firestoreService.saveWorkEntryBatch(entries);
    }

    for (final template in _localTemplates.where(
      (item) =>
          item.orgId == currentUser.orgId &&
          (item.userId.isEmpty || item.userId == currentUser.uid),
    )) {
      await _firestoreService.saveWorkTemplate(
        template.copyWith(
          orgId: currentUser.orgId,
          userId: template.userId.isEmpty ? currentUser.uid : template.userId,
        ),
      );
    }
  }

  Future<void> clockIn() async {
    if (_isClockBusy) return;
    _isClockBusy = true;
    try {
      final user = _currentUser;
      if (_clockInTime != null || user == null || !user.canEditTimeEntries) {
        return;
      }
      final overlappingEntry = await findOverlappingEntryForRange(
        start: DateTime.now(),
        end: DateTime.now().add(const Duration(seconds: 1)),
      );
      if (overlappingEntry != null) {
        throw StateError(
          'Fuer den aktuellen Zeitraum existiert bereits ein Zeiteintrag. '
          'Die Stempeluhr wurde nicht erneut gestartet.',
        );
      }
      final activeShift = await _findCoveringShift(
        orgId: user.orgId,
        userId: user.uid,
        start: DateTime.now(),
        end: DateTime.now(),
      );
      if (activeShift == null) {
        throw StateError(
          'Einstempeln ist nur waehrend einer geplanten Schicht moeglich.',
        );
      }
      final clockSite = _clockSiteForUser(user.uid);
      if (clockSite == null) {
        throw StateError(
          'Fuer die Stempeluhr ist kein Standort zugeordnet. Bitte zuerst in der Teamverwaltung einen Primaerstandort hinterlegen.',
        );
      }
      _clockInTime = DateTime.now();
      _clockInSiteId = clockSite.siteId;
      _clockInSiteName = clockSite.siteName;
      await DatabaseService.saveLocalSetting(
        _clockInKey,
        _clockInTime!.toIso8601String(),
        scope: _localScope,
      );
      await DatabaseService.saveLocalSetting(
        _clockInSiteIdKey,
        clockSite.siteId,
        scope: _localScope,
      );
      await DatabaseService.saveLocalSetting(
        _clockInSiteNameKey,
        clockSite.siteName,
        scope: _localScope,
      );
      _startClockTick();
      await refreshCurrentShiftStatus(referenceTime: _clockInTime);
      _safeNotify();
    } finally {
      _isClockBusy = false;
    }
  }

  Future<void> clockOut({
    bool allowOvertime = false,
  }) async {
    if (_isClockBusy) return;
    _isClockBusy = true;
    try {
      final user = _currentUser;
      if ((!hasActiveClockSession && _clockInTime == null) || user == null) {
        return;
      }
      if (!user.canEditTimeEntries) {
        return;
      }

      final activeEntry = _clockInTime == null
          ? (activeEntryNow ??
              await _loadActiveEntryAt(
                orgId: user.orgId,
                userId: user.uid,
                pointInTime: DateTime.now(),
              ))
          : null;
      final start = _clockInTime ?? activeEntry?.startTime;
      if (start == null) {
        return;
      }
      final end = DateTime.now();
      final referenceShift = await _resolveReferenceShiftForClockOut(
        orgId: user.orgId,
        userId: user.uid,
        sessionStart: start,
        existingEntry: activeEntry,
      );
      if (referenceShift == null) {
        throw StateError(
          'Ausstempeln ist nur fuer Zeitraeume mit zugeordneter Schicht moeglich.',
        );
      }
      final clockSite = _clockSiteForUser(user.uid);
      if (clockSite == null) {
        throw StateError(
          'Fuer die laufende Stempeluhr konnte kein Standort ermittelt werden.',
        );
      }

      final workedMinutes = end.difference(start).inMinutes;
      final breakMinutes = _autoBreakMinutesFor(
        workedMinutes: workedMinutes,
        siteId: _clockInSiteId ?? activeEntry?.siteId,
      );
      final clockEntry = WorkEntry(
        id: activeEntry?.id,
        orgId: user.orgId,
        userId: user.uid,
        date: start,
        startTime: start,
        endTime: end,
        breakMinutes: activeEntry?.breakMinutes ?? breakMinutes,
        siteId: activeEntry?.siteId ?? clockSite.siteId,
        siteName: activeEntry?.siteName ?? clockSite.siteName,
        sourceShiftId: activeEntry?.sourceShiftId ?? referenceShift.id,
        note: activeEntry?.note ?? 'Stempeluhr',
        category: activeEntry?.category,
        correctionReason: activeEntry?.correctionReason,
        correctedByUid: activeEntry?.correctedByUid,
        correctedAt: activeEntry?.correctedAt,
      );

      final segments = _splitEntryAgainstShift(
        clockEntry,
        referenceShift,
        overtimeNote: _mergeEntryNote(
          activeEntry?.note ?? 'Stempeluhr',
          'Ueberstunden',
        ),
      );
      final needsOvertimeApproval = segments.length > 1 ||
          (segments.isNotEmpty &&
              (segments.first.category?.toLowerCase() == 'overtime'));
      if (needsOvertimeApproval && !allowOvertime) {
        throw _buildOvertimeApprovalRequired(
          entry: clockEntry,
          shift: referenceShift,
        );
      }

      // Save entry BEFORE clearing clock state so we can recover on failure.
      if (segments.length == 1) {
        await addEntry(segments.first);
      } else {
        await addEntries(segments);
      }

      _stopClockTick();
      _clockInTime = null;
      _clockInSiteId = null;
      _clockInSiteName = null;
      await DatabaseService.removeLocalSetting(
        _clockInKey,
        scope: _localScope,
      );
      await DatabaseService.removeLocalSetting(
        _clockInSiteIdKey,
        scope: _localScope,
      );
      await DatabaseService.removeLocalSetting(
        _clockInSiteNameKey,
        scope: _localScope,
      );
      await refreshCurrentShiftStatus();
      _safeNotify();
    } finally {
      _isClockBusy = false;
    }
  }

  /// Korrigiert einen bestehenden Stempeluhr-Eintrag mit neuen Zeiten und
  /// einer Begruendung.
  Future<void> correctClockEntry({
    required String entryId,
    required DateTime correctedStart,
    required DateTime correctedEnd,
    required String reason,
  }) async {
    final user = _currentUser;
    if (user == null || !user.canEditTimeEntries) return;
    final existingEntry = [
      ..._entries,
      ..._reportEntries,
      ..._localEntries,
    ].firstWhere(
      (entry) => entry.id == entryId,
      orElse: () => WorkEntry(
        id: entryId,
        orgId: user.orgId,
        userId: user.uid,
        date: correctedStart,
        startTime: correctedStart,
        endTime: correctedEnd,
      ),
    );

    final workedMinutes = correctedEnd.difference(correctedStart).inMinutes;
    final breakMinutes = _autoBreakMinutesFor(
      workedMinutes: workedMinutes,
      siteId: existingEntry.siteId,
    );
    final clockSite = _clockSiteForUser(user.uid);

    await updateEntry(WorkEntry(
      id: entryId,
      orgId: user.orgId,
      userId: user.uid,
      date: correctedStart,
      startTime: correctedStart,
      endTime: correctedEnd,
      breakMinutes: breakMinutes,
      siteId: existingEntry.siteId ?? clockSite?.siteId,
      siteName: existingEntry.siteName ?? clockSite?.siteName,
      sourceShiftId: existingEntry.sourceShiftId,
      correctionReason: reason,
      correctedByUid: user.uid,
      correctedAt: DateTime.now(),
      note: existingEntry.note ?? 'Stempeluhr',
      category: existingEntry.category,
    ));
  }

  Future<List<ComplianceViolation>> validateEntry(WorkEntry entry) async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return const [];
    }
    final effectiveOrgId =
        entry.orgId.isNotEmpty ? entry.orgId : currentUser.orgId;
    final effectiveUserId =
        entry.userId.isNotEmpty ? entry.userId : currentUser.uid;
    final member = _members.firstWhereOrNull(
          (candidate) => candidate.uid == effectiveUserId,
        ) ??
        (currentUser.uid == effectiveUserId ? currentUser : null);
    final referenceShift = await _resolveReferenceShiftForEntry(
      entry.copyWith(
        orgId: effectiveOrgId,
        userId: effectiveUserId,
      ),
    );
    final isOvertimeEntry = _isOvertimeEntry(entry);
    final isCoveredByShift = referenceShift != null &&
        !referenceShift.startTime.isAfter(entry.startTime) &&
        !referenceShift.endTime.isBefore(entry.endTime);
    final isAllowedOvertime = referenceShift != null &&
        isOvertimeEntry &&
        _isAllowedOvertimeEntry(entry, referenceShift);
    if (!isCoveredByShift && !isAllowedOvertime) {
      return const [
        ComplianceViolation(
          code: 'shift_required',
          severity: ComplianceSeverity.blocking,
          message:
              'Zeiteintraege sind nur innerhalb einer geplanten Schicht moeglich.',
        ),
      ];
    }
    final dayStart = DateTime(
      entry.startTime.year,
      entry.startTime.month,
      1,
    );
    final queryStart = dayStart.subtract(const Duration(days: 1));
    final queryEnd = DateTime(
      entry.startTime.year,
      entry.startTime.month + 1,
      2,
    );
    final existingEntries = usesLocalStorage
        ? _localEntries.where((candidate) {
            final effectiveUserId =
                entry.userId.isNotEmpty ? entry.userId : currentUser.uid;
            return candidate.userId == effectiveUserId &&
                !candidate.startTime.isBefore(queryStart) &&
                candidate.startTime.isBefore(queryEnd);
          }).toList(growable: false)
        : await _firestoreService.getWorkEntriesInRange(
            orgId: entry.orgId.isNotEmpty ? entry.orgId : currentUser.orgId,
            userId: entry.userId.isNotEmpty ? entry.userId : currentUser.uid,
            start: queryStart,
            end: queryEnd,
          );
    return _complianceService.validateWorkEntry(
      entry: entry,
      existingEntries: existingEntries,
      contracts: _contracts,
      siteAssignments: _siteAssignments,
      ruleSets: _effectiveRuleSets,
      travelTimeRules: _travelTimeRules,
      member: member,
    );
  }

  Future<WorkEntry?> findOverlappingEntryForRange({
    required DateTime start,
    required DateTime end,
    String? orgId,
    String? userId,
    String? excludeEntryId,
  }) async {
    final currentUser = _currentUser;
    final effectiveOrgId =
        orgId?.trim().isNotEmpty == true ? orgId!.trim() : currentUser?.orgId;
    final effectiveUserId =
        userId?.trim().isNotEmpty == true ? userId!.trim() : currentUser?.uid;
    if (effectiveOrgId == null ||
        effectiveOrgId.isEmpty ||
        effectiveUserId == null ||
        effectiveUserId.isEmpty) {
      return null;
    }

    final entries = await _loadUserEntriesForRange(
      orgId: effectiveOrgId,
      userId: effectiveUserId,
      start: start,
      end: end,
    );
    final overlappingEntries = entries
        .where((entry) => entry.id != excludeEntryId)
        .where((entry) =>
            _entriesOverlap(entry.startTime, entry.endTime, start, end))
        .toList(growable: false)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return overlappingEntries.firstOrNull;
  }

  Future<void> restoreClockState() async {
    final stored = await DatabaseService.getLocalSetting(
      _clockInKey,
      scope: _localScope,
    );
    if (stored != null) {
      final parsed = DateTime.tryParse(stored);
      // Validate: discard clock state if the time is in the future or older
      // than 24 hours (stale from a previous day).
      if (parsed == null ||
          parsed.isAfter(DateTime.now()) ||
          DateTime.now().difference(parsed).inHours > 24) {
        await DatabaseService.removeLocalSetting(
          _clockInKey,
          scope: _localScope,
        );
        await DatabaseService.removeLocalSetting(
          _clockInSiteIdKey,
          scope: _localScope,
        );
        await DatabaseService.removeLocalSetting(
          _clockInSiteNameKey,
          scope: _localScope,
        );
        return;
      }
      _clockInTime = parsed;
      _clockInSiteId = await DatabaseService.getLocalSetting(
        _clockInSiteIdKey,
        scope: _localScope,
      );
      _clockInSiteName = await DatabaseService.getLocalSetting(
        _clockInSiteNameKey,
        scope: _localScope,
      );
      if (_clockInTime != null) {
        _startClockTick();
        _safeNotify();
      }
    }
  }

  Future<Shift?> findCoveringShiftForRange({
    required DateTime start,
    required DateTime end,
    String? orgId,
    String? userId,
  }) async {
    final currentUser = _currentUser;
    final effectiveOrgId =
        orgId?.trim().isNotEmpty == true ? orgId!.trim() : currentUser?.orgId;
    final effectiveUserId =
        userId?.trim().isNotEmpty == true ? userId!.trim() : currentUser?.uid;
    if (effectiveOrgId == null ||
        effectiveOrgId.isEmpty ||
        effectiveUserId == null ||
        effectiveUserId.isEmpty) {
      return null;
    }
    return _findCoveringShift(
      orgId: effectiveOrgId,
      userId: effectiveUserId,
      start: start,
      end: end,
    );
  }

  Future<List<Shift>> loadConfirmedShiftsForDay(
    DateTime day, {
    String? orgId,
    String? userId,
  }) async {
    final currentUser = _currentUser;
    final effectiveOrgId =
        orgId?.trim().isNotEmpty == true ? orgId!.trim() : currentUser?.orgId;
    final effectiveUserId =
        userId?.trim().isNotEmpty == true ? userId!.trim() : currentUser?.uid;
    if (effectiveOrgId == null ||
        effectiveOrgId.isEmpty ||
        effectiveUserId == null ||
        effectiveUserId.isEmpty) {
      return const [];
    }

    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final shifts = await _loadUserShiftsForRange(
      orgId: effectiveOrgId,
      userId: effectiveUserId,
      start: dayStart,
      end: dayEnd,
    );

    final dayShifts = shifts
        .where((shift) =>
            _isBookableShift(shift) &&
            shift.startTime.isBefore(dayEnd) &&
            shift.endTime.isAfter(dayStart))
        .toList(growable: false)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return dayShifts;
  }

  Future<List<Shift>> loadShiftsForRange({
    required DateTime start,
    required DateTime end,
    String? orgId,
    String? userId,
    bool onlyBookable = false,
    bool includeCancelled = false,
  }) async {
    final currentUser = _currentUser;
    final effectiveOrgId =
        orgId?.trim().isNotEmpty == true ? orgId!.trim() : currentUser?.orgId;
    final effectiveUserId =
        userId?.trim().isNotEmpty == true ? userId!.trim() : currentUser?.uid;
    if (effectiveOrgId == null ||
        effectiveOrgId.isEmpty ||
        effectiveUserId == null ||
        effectiveUserId.isEmpty ||
        !end.isAfter(start)) {
      return const [];
    }

    final shifts = await _loadUserShiftsForRange(
      orgId: effectiveOrgId,
      userId: effectiveUserId,
      start: start,
      end: end,
    );

    final filtered = shifts.where((shift) {
      if (shift.isUnassigned) {
        return false;
      }
      if (!includeCancelled && shift.status == ShiftStatus.cancelled) {
        return false;
      }
      if (onlyBookable && !_isBookableShift(shift)) {
        return false;
      }
      return true;
    }).toList(growable: false)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return filtered;
  }

  Future<List<Shift>> loadShiftsForMonth(
    DateTime month, {
    String? orgId,
    String? userId,
    bool onlyBookable = false,
    bool includeCancelled = false,
  }) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return loadShiftsForRange(
      start: start,
      end: end,
      orgId: orgId,
      userId: userId,
      onlyBookable: onlyBookable,
      includeCancelled: includeCancelled,
    );
  }

  Future<List<WorkEntry>> loadEntriesForRange({
    required DateTime start,
    required DateTime end,
    String? orgId,
    String? userId,
  }) async {
    final currentUser = _currentUser;
    final effectiveOrgId =
        orgId?.trim().isNotEmpty == true ? orgId!.trim() : currentUser?.orgId;
    final effectiveUserId =
        userId?.trim().isNotEmpty == true ? userId!.trim() : currentUser?.uid;
    if (effectiveOrgId == null ||
        effectiveOrgId.isEmpty ||
        effectiveUserId == null ||
        effectiveUserId.isEmpty ||
        !end.isAfter(start)) {
      return const [];
    }

    final entries = await _loadUserEntriesForRange(
      orgId: effectiveOrgId,
      userId: effectiveUserId,
      start: start,
      end: end,
    );
    return entries..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  Future<void> refreshCurrentShiftStatus({
    DateTime? referenceTime,
  }) async {
    final currentUser = _currentUser;
    final requestId = ++_clockAvailabilityRequestId;
    if (currentUser == null) {
      _activeShiftNow = null;
      _checkingClockAvailability = false;
      _safeNotify();
      return;
    }

    _checkingClockAvailability = true;
    _safeNotify();

    try {
      final pointInTime = referenceTime ?? DateTime.now();
      final results = await Future.wait<Object?>([
        _findCoveringShift(
          orgId: currentUser.orgId,
          userId: currentUser.uid,
          start: pointInTime,
          end: pointInTime,
        ),
        _loadActiveEntryAt(
          orgId: currentUser.orgId,
          userId: currentUser.uid,
          pointInTime: pointInTime,
        ),
      ]);
      if (requestId != _clockAvailabilityRequestId) {
        return;
      }
      _activeShiftNow = results[0] as Shift?;
      _activeEntrySnapshot = results[1] as WorkEntry?;
    } catch (error) {
      if (requestId != _clockAvailabilityRequestId) {
        return;
      }
      _activeShiftNow = null;
      _activeEntrySnapshot = null;
      debugPrint(
          'WorkProvider: Fehler beim Pruefen der aktiven Schicht: $error');
    } finally {
      if (requestId == _clockAvailabilityRequestId) {
        _checkingClockAvailability = false;
        _safeNotify();
      }
    }
  }

  void _startClockTick() {
    _clockTickTimer?.cancel();
    _clockTickTimer = Timer.periodic(
      const Duration(seconds: 30),
      (timer) {
        try {
          _safeNotify();
        } catch (_) {
          timer.cancel();
          _clockTickTimer = null;
        }
      },
    );
  }

  void _stopClockTick() {
    _clockTickTimer?.cancel();
    _clockTickTimer = null;
  }

  void _ensureClockAvailabilityWatcher() {
    _clockAvailabilityTimer?.cancel();
    if (_currentUser == null) {
      return;
    }
    _clockAvailabilityTimer = Timer.periodic(
      const Duration(minutes: 1),
      (timer) {
        try {
          unawaited(refreshCurrentShiftStatus());
        } catch (_) {
          timer.cancel();
          _clockAvailabilityTimer = null;
        }
      },
    );
  }

  void _stopClockAvailabilityWatcher() {
    _clockAvailabilityTimer?.cancel();
    _clockAvailabilityTimer = null;
  }

  List<WorkEntry> getEntriesForDay(DateTime day) {
    return _entries.where((entry) {
      return entry.date.year == day.year &&
          entry.date.month == day.month &&
          entry.date.day == day.day;
    }).toList(growable: false);
  }

  bool hasEntryOnDay(DateTime day) {
    return _entries.any((entry) {
      return entry.date.year == day.year &&
          entry.date.month == day.month &&
          entry.date.day == day.day;
    });
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _restartSubscriptions() async {
    final currentUser = _currentUser;
    if (currentUser == null || usesLocalStorage) {
      _loading = false;
      _safeNotify();
      return;
    }

    _loading = true;
    _safeNotify();

    // Build new subscriptions before cancelling old ones to avoid a window
    // where _entries is empty and listeners see stale/no data.
    final oldEntriesSub = _entriesSubscription;
    final oldTemplatesSub = _templatesSubscription;

    final shouldLoadEntries =
        currentUser.canViewTimeTracking || currentUser.canViewReports;
    final month = DateTime(_selectedMonth.year, _selectedMonth.month);
    if (shouldLoadEntries) {
      _entriesSubscription = _firestoreService
          .watchWorkEntries(
        orgId: currentUser.orgId,
        userId: currentUser.uid,
        month: _selectedMonth,
      )
          .listen((items) {
        _entries = items;
        _loading = false;
        _errorMessage = null;
        if (usesHybridStorage) {
          unawaited(
            _storeHybridWorkEntriesSnapshot(
              items,
              userId: currentUser.uid,
              month: month,
            ),
          );
        }
        _safeNotify();
      }, onError: (Object error) {
        _errorMessage = 'Fehler beim Laden der Eintraege: $error';
        _loading = false;
        _safeNotify();
      });
    } else {
      _entriesSubscription = null;
      _entries = [];
      _loading = false;
      _errorMessage = null;
    }

    if (currentUser.canEditTimeEntries) {
      _templatesSubscription = _firestoreService
          .watchWorkTemplates(
        orgId: currentUser.orgId,
        userId: currentUser.uid,
      )
          .listen((items) {
        _templates = items;
        if (usesHybridStorage) {
          unawaited(_storeHybridTemplatesSnapshot(items));
        }
        _safeNotify();
      }, onError: (Object error) {
        debugPrint('WorkProvider: Fehler beim Laden der Vorlagen: $error');
      });
    } else {
      _templatesSubscription = null;
      _templates = [];
    }

    await oldEntriesSub?.cancel();
    await oldTemplatesSub?.cancel();

    await _restartReportSubscription();
  }

  Future<void> _restartReportSubscription() async {
    final currentUser = _currentUser;
    final reportUser = _reportUser;
    await _reportEntriesSubscription?.cancel();
    _reportEntries = [];

    if (currentUser == null ||
        reportUser == null ||
        !currentUser.canViewReports ||
        _isReportingCurrentUser ||
        usesLocalStorage) {
      _safeNotify();
      return;
    }

    final reportMonth = DateTime(_selectedMonth.year, _selectedMonth.month);
    _reportEntriesSubscription = _firestoreService
        .watchWorkEntries(
      orgId: reportUser.orgId,
      userId: reportUser.uid,
      month: _selectedMonth,
    )
        .listen((items) {
      _reportEntries = items;
      if (usesHybridStorage) {
        unawaited(
          _storeHybridWorkEntriesSnapshot(
            items,
            userId: reportUser.uid,
            month: reportMonth,
          ),
        );
      }
      _safeNotify();
    }, onError: (Object error) {
      debugPrint('WorkProvider: Fehler beim Laden der Berichtsdaten: $error');
    });
  }

  Future<void> _loadLocalState(
    AppUserProfile user, {
    bool overrideUserSettings = true,
  }) async {
    _loading = true;
    notifyListeners();
    final scope = LocalStorageScope.fromUser(user);
    _localEntries = await DatabaseService.loadLocalEntries(scope: scope);
    _localTemplates = await DatabaseService.loadLocalTemplates(scope: scope);
    if (overrideUserSettings) {
      final localSettings =
          await DatabaseService.loadLocalUserSettings(scope: scope);
      _currentUser = user.copyWith(settings: localSettings);
    } else {
      _currentUser = user;
    }
    if (_reportUser?.uid == user.uid || _reportUser == null) {
      _reportUser = _currentUser;
    }
    _applyLocalState();
  }

  void _applyLocalState() {
    final currentUser = _currentUser;
    if (currentUser == null) {
      _entries = [];
      _templates = [];
      _reportEntries = [];
      _loading = false;
      return;
    }

    final reportUser = _reportUser ?? currentUser;
    final canUseEntries =
        currentUser.canViewTimeTracking || currentUser.canViewReports;

    final monthEntries = !canUseEntries
        ? <WorkEntry>[]
        : _localEntries.where((entry) {
            final sameUser =
                entry.userId.isEmpty || entry.userId == currentUser.uid;
            final sameMonth = entry.date.year == _selectedMonth.year &&
                entry.date.month == _selectedMonth.month;
            return sameUser && sameMonth;
          }).toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));

    final templates = !currentUser.canEditTimeEntries
        ? <WorkTemplate>[]
        : _localTemplates.where((template) {
            return template.userId.isEmpty ||
                template.userId == currentUser.uid;
          }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final monthReportEntries = !currentUser.canViewReports
        ? const <WorkEntry>[]
        : reportUser.uid == currentUser.uid
            ? monthEntries
            : _localEntries.where((entry) {
                final sameUser = entry.userId == reportUser.uid;
                final sameMonth = entry.date.year == _selectedMonth.year &&
                    entry.date.month == _selectedMonth.month;
                return sameUser && sameMonth;
              }).toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));

    _entries = monthEntries;
    _templates = templates;
    _reportEntries =
        reportUser.uid == currentUser.uid ? [] : monthReportEntries;
    _loading = false;
  }

  String get _storageModeKey {
    if (usesLocalStorage) {
      return 'local';
    }
    return usesHybridStorage ? 'hybrid' : 'cloud';
  }

  Future<void> _storeHybridTemplatesSnapshot(
    List<WorkTemplate> items,
  ) async {
    final scope = _localScope;
    if (!usesHybridStorage || scope == null) {
      return;
    }
    _localTemplates = [...items];
    await DatabaseService.saveLocalTemplates(
      _localTemplates,
      scope: scope,
    );
  }

  Future<void> _storeHybridWorkEntriesSnapshot(
    List<WorkEntry> items, {
    required String userId,
    required DateTime month,
  }) async {
    final scope = _localScope;
    if (!usesHybridStorage || scope == null) {
      return;
    }

    _localEntries = _localEntries.where((entry) {
      final sameUser = entry.userId == userId;
      final sameMonth =
          entry.date.year == month.year && entry.date.month == month.month;
      return !(sameUser && sameMonth);
    }).toList(growable: true)
      ..addAll(items)
      ..sort((a, b) => a.date.compareTo(b.date));

    await DatabaseService.saveLocalEntries(
      _localEntries,
      scope: scope,
    );
  }

  void _notifyShiftWorked(String? sourceShiftId) {
    final shiftId = sourceShiftId?.trim();
    if (shiftId == null || shiftId.isEmpty) return;
    onShiftWorked?.call(shiftId);
  }

  String _nextLocalId(String prefix) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
  }

  Future<Shift?> _findCoveringShift({
    required String orgId,
    required String userId,
    required DateTime start,
    required DateTime end,
  }) async {
    final shifts = await _loadUserShiftsForRange(
      orgId: orgId,
      userId: userId,
      start: start,
      end: end,
    );
    for (final shift in shifts) {
      if (!_isBookableShift(shift)) {
        continue;
      }
      if (!shift.startTime.isAfter(start) && !shift.endTime.isBefore(end)) {
        return shift;
      }
    }
    return null;
  }

  Future<List<Shift>> _loadUserShiftsForRange({
    required String orgId,
    required String userId,
    required DateTime start,
    required DateTime end,
  }) async {
    final queryStart = DateTime(
      start.year,
      start.month,
      start.day,
    ).subtract(const Duration(days: 1));
    final queryEnd = DateTime(
      end.year,
      end.month,
      end.day + 2,
    );

    final shifts = usesLocalStorage
        ? await DatabaseService.loadLocalShifts(scope: _localScope)
        : await _firestoreService.getShiftsInRange(
            orgId: orgId,
            userId: userId,
            start: queryStart,
            end: queryEnd,
          );

    return shifts
        .where((shift) =>
            shift.orgId == orgId &&
            shift.userId == userId &&
            shift.startTime.isBefore(end.add(const Duration(minutes: 1))) &&
            shift.endTime.isAfter(start.subtract(const Duration(minutes: 1))))
        .toList(growable: false);
  }

  Future<List<WorkEntry>> _loadUserEntriesForRange({
    required String orgId,
    required String userId,
    required DateTime start,
    required DateTime end,
  }) async {
    final queryStart = DateTime(
      start.year,
      start.month,
      start.day,
    ).subtract(const Duration(days: 1));
    final queryEnd = DateTime(
      end.year,
      end.month,
      end.day + 2,
    );

    final entries = usesLocalStorage
        ? await DatabaseService.loadLocalEntries(scope: _localScope)
        : await _firestoreService.getWorkEntriesInRange(
            orgId: orgId,
            userId: userId,
            start: queryStart,
            end: queryEnd,
          );

    return entries
        .where((entry) =>
            entry.orgId == orgId &&
            (entry.userId.isEmpty || entry.userId == userId) &&
            _entriesOverlap(entry.startTime, entry.endTime, start, end))
        .toList(growable: false);
  }

  Future<WorkEntry?> _loadActiveEntryAt({
    required String orgId,
    required String userId,
    required DateTime pointInTime,
  }) async {
    final entries = await _loadUserEntriesForRange(
      orgId: orgId,
      userId: userId,
      start: pointInTime.subtract(const Duration(seconds: 1)),
      end: pointInTime.add(const Duration(seconds: 1)),
    );
    final activeEntries = entries
        .where((entry) =>
            !entry.startTime.isAfter(pointInTime) &&
            entry.endTime.isAfter(pointInTime))
        .toList(growable: false)
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    return activeEntries.firstOrNull;
  }

  bool _isBookableShift(Shift shift) {
    if (shift.isUnassigned) {
      return false;
    }
    return shift.status == ShiftStatus.confirmed ||
        shift.status == ShiftStatus.completed;
  }

  WorkEntry? _activeEntryAt(DateTime pointInTime) {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return null;
    }
    final entries = _entries
        .where((entry) =>
            entry.userId == currentUser.uid &&
            !entry.startTime.isAfter(pointInTime) &&
            entry.endTime.isAfter(pointInTime))
        .toList(growable: false)
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    return entries.firstOrNull;
  }

  bool _entriesOverlap(
    DateTime firstStart,
    DateTime firstEnd,
    DateTime secondStart,
    DateTime secondEnd,
  ) {
    return firstStart.isBefore(secondEnd) && firstEnd.isAfter(secondStart);
  }

  bool _isOvertimeEntry(WorkEntry entry) {
    return entry.category?.trim().toLowerCase() == 'overtime';
  }

  bool _isAllowedOvertimeEntry(WorkEntry entry, Shift shift) {
    if (!_isOvertimeEntry(entry)) {
      return false;
    }
    final beforeShift = entry.endTime == shift.startTime &&
        entry.startTime.isBefore(entry.endTime);
    final afterShift = entry.startTime == shift.endTime &&
        entry.endTime.isAfter(entry.startTime);
    return beforeShift || afterShift;
  }

  Future<Shift?> _resolveReferenceShiftForEntry(WorkEntry entry) async {
    final sourceShiftId = entry.sourceShiftId?.trim();
    if (sourceShiftId != null && sourceShiftId.isNotEmpty) {
      final shifts = await _loadUserShiftsForRange(
        orgId: entry.orgId,
        userId: entry.userId,
        start: entry.startTime,
        end: entry.endTime,
      );
      final sourceShift = shifts
          .where((shift) => shift.id == sourceShiftId)
          .where(_isBookableShift)
          .firstOrNull;
      if (sourceShift != null) {
        return sourceShift;
      }
    }

    final coveringShift = await _findCoveringShift(
      orgId: entry.orgId,
      userId: entry.userId,
      start: entry.startTime,
      end: entry.endTime,
    );
    if (coveringShift != null) {
      return coveringShift;
    }

    final startShift = await _findCoveringShift(
      orgId: entry.orgId,
      userId: entry.userId,
      start: entry.startTime,
      end: entry.startTime,
    );
    if (startShift != null) {
      return startShift;
    }

    return _findCoveringShift(
      orgId: entry.orgId,
      userId: entry.userId,
      start: entry.endTime,
      end: entry.endTime,
    );
  }

  Future<Shift?> _resolveReferenceShiftForClockOut({
    required String orgId,
    required String userId,
    required DateTime sessionStart,
    WorkEntry? existingEntry,
  }) async {
    final sourceShiftId = existingEntry?.sourceShiftId?.trim();
    if (sourceShiftId != null && sourceShiftId.isNotEmpty) {
      final shifts = await _loadUserShiftsForRange(
        orgId: orgId,
        userId: userId,
        start: sessionStart,
        end: DateTime.now(),
      );
      final sourceShift = shifts
          .where((shift) => shift.id == sourceShiftId)
          .where(_isBookableShift)
          .firstOrNull;
      if (sourceShift != null) {
        return sourceShift;
      }
    }
    return _findCoveringShift(
      orgId: orgId,
      userId: userId,
      start: sessionStart,
      end: sessionStart,
    );
  }

  List<WorkEntry> _splitEntryAgainstShift(
    WorkEntry entry,
    Shift shift, {
    String? overtimeNote,
  }) {
    final segments = <WorkEntry>[];
    final insideStart = entry.startTime.isAfter(shift.startTime)
        ? entry.startTime
        : shift.startTime;
    final insideEnd =
        entry.endTime.isBefore(shift.endTime) ? entry.endTime : shift.endTime;
    final hasInsideSegment = insideEnd.isAfter(insideStart);

    if (entry.startTime.isBefore(shift.startTime)) {
      final overtimeEnd = hasInsideSegment ? shift.startTime : entry.endTime;
      if (overtimeEnd.isAfter(entry.startTime)) {
        segments.add(
          entry.copyWith(
            clearSourceShiftId: false,
            sourceShiftId: shift.id,
            startTime: entry.startTime,
            endTime: overtimeEnd,
            breakMinutes: hasInsideSegment ? 0 : entry.breakMinutes,
            category: 'overtime',
            note: overtimeNote ?? _mergeEntryNote(entry.note, 'Ueberstunden'),
            id: hasInsideSegment ? null : entry.id,
          ),
        );
      }
    }

    if (hasInsideSegment) {
      segments.add(
        entry.copyWith(
          sourceShiftId: shift.id,
          startTime: insideStart,
          endTime: insideEnd,
          category: _isOvertimeEntry(entry) ? null : entry.category,
          note: entry.note,
          id: entry.id,
        ),
      );
    }

    if (entry.endTime.isAfter(shift.endTime)) {
      final overtimeStart = hasInsideSegment ? shift.endTime : entry.startTime;
      if (entry.endTime.isAfter(overtimeStart)) {
        segments.add(
          entry.copyWith(
            clearSourceShiftId: false,
            sourceShiftId: shift.id,
            startTime: overtimeStart,
            endTime: entry.endTime,
            breakMinutes: 0,
            category: 'overtime',
            note: overtimeNote ?? _mergeEntryNote(entry.note, 'Ueberstunden'),
            id: hasInsideSegment ? null : entry.id,
          ),
        );
      }
    }

    return segments.isEmpty ? [entry] : segments;
  }

  OvertimeApprovalRequired _buildOvertimeApprovalRequired({
    required WorkEntry entry,
    required Shift shift,
  }) {
    final beforeShiftStart =
        entry.startTime.isBefore(shift.startTime) ? entry.startTime : null;
    final beforeShiftEnd =
        entry.startTime.isBefore(shift.startTime) ? shift.startTime : null;
    final afterShiftStart =
        entry.endTime.isAfter(shift.endTime) ? shift.endTime : null;
    final afterShiftEnd =
        entry.endTime.isAfter(shift.endTime) ? entry.endTime : null;
    return OvertimeApprovalRequired(
      shift: shift,
      entryStart: entry.startTime,
      entryEnd: entry.endTime,
      entryId: entry.id,
      beforeShiftStart: beforeShiftStart,
      beforeShiftEnd: beforeShiftEnd,
      afterShiftStart: afterShiftStart,
      afterShiftEnd: afterShiftEnd,
    );
  }

  String _mergeEntryNote(String? original, String addition) {
    final cleanedOriginal = original?.trim() ?? '';
    if (cleanedOriginal.isEmpty) {
      return addition;
    }
    if (cleanedOriginal.contains(addition)) {
      return cleanedOriginal;
    }
    return '$cleanedOriginal · $addition';
  }

  EmployeeSiteAssignment? _primaryAssignmentForUser(String userId) {
    final assignment = _siteAssignments.firstWhereOrNull(
          (item) => item.userId == userId && item.isPrimary,
        ) ??
        _siteAssignments.firstWhereOrNull((item) => item.userId == userId);
    if (assignment == null || assignment.siteId.isEmpty) {
      return null;
    }
    return assignment;
  }

  ({String siteId, String siteName})? _clockSiteForUser(String userId) {
    final storedId = _clockInSiteId?.trim();
    final storedName = _clockInSiteName?.trim();
    if (storedId != null &&
        storedId.isNotEmpty &&
        storedName != null &&
        storedName.isNotEmpty) {
      return (siteId: storedId, siteName: storedName);
    }
    final assignment = _primaryAssignmentForUser(userId);
    if (assignment == null) {
      return null;
    }
    return (siteId: assignment.siteId, siteName: assignment.siteName);
  }

  List<ComplianceRuleSet> get _effectiveRuleSets {
    return ComplianceRuleSetUtils.effectiveRuleSets(
      ruleSets: _ruleSets,
      currentUser: _currentUser,
    );
  }

  double _autoBreakMinutesFor({
    required int workedMinutes,
    required String? siteId,
  }) {
    final threshold = settings.autoBreakAfterMinutes;
    if (threshold <= 0 || workedMinutes < threshold) {
      return 0;
    }
    final ruleSet = _effectiveRuleSetFor(siteId);
    var requiredBreak = 0;
    for (final rule in ruleSet.breakRules.sorted(
      (a, b) => a.afterMinutes.compareTo(b.afterMinutes),
    )) {
      if (workedMinutes > rule.afterMinutes) {
        requiredBreak = rule.requiredBreakMinutes;
      }
    }
    return requiredBreak.toDouble();
  }

  ComplianceRuleSet _effectiveRuleSetFor(String? siteId) {
    final currentUser = _currentUser;
    final contract = _contracts
        .where((item) =>
            item.userId == currentUser?.uid &&
            currentUser != null &&
            item.isActiveOn(DateTime.now()))
        .toList(growable: false)
      ..sort((a, b) => b.validFrom.compareTo(a.validFrom));
    final activeContract = contract.isEmpty ? null : contract.first;
    return _complianceService.resolveRuleSet(
      ruleSets: _effectiveRuleSets,
      siteId: siteId,
      contract: activeContract,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _stopClockTick();
    _stopClockAvailabilityWatcher();
    _entriesSubscription?.cancel();
    _templatesSubscription?.cancel();
    _reportEntriesSubscription?.cancel();
    super.dispose();
  }
}
