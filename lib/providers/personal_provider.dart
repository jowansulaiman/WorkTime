import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/employment_contract.dart';
import '../models/payroll_profile.dart';
import '../models/payroll_record.dart';
import '../models/payroll_settings.dart';
import '../models/site_definition.dart';
import '../models/work_entry.dart';
import '../models/work_task.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';

/// Aggregierte Abwesenheits-Kennzahlen eines Mitarbeiters (Statistik).
class AbsenceStats {
  const AbsenceStats({
    this.sicknessCount = 0,
    this.sicknessDays = 0,
    this.unavailableCount = 0,
    this.unavailableDays = 0,
    this.vacationCount = 0,
    this.vacationDays = 0,
  });

  final int sicknessCount;
  final int sicknessDays;
  final int unavailableCount;
  final int unavailableDays;
  final int vacationCount;
  final int vacationDays;

  int get totalCount => sicknessCount + unavailableCount + vacationCount;
}

/// Zustand des Personal-Bereichs (nur Admin): Arbeitsaufträge und
/// Lohnabrechnungen als eigene org-skopierte Collections, plus aggregierende
/// Sichten über Stammdaten (Mitarbeiter, Verträge, Standorte) und Abwesenheiten.
///
/// Kundenaufträge werden NICHT hier verwaltet – dafür existiert die
/// Warenwirtschaft ([InventoryProvider]); der Personal-Screen liest sie dort.
///
/// Speicher-Verhalten analog [InventoryProvider]: Cloud/Hybrid über
/// Firestore-Streams (Offline-Cache), local über SharedPreferences. Schreibende
/// Operationen fallen im Hybrid-Modus offline lokal zurück.
class PersonalProvider extends ChangeNotifier {
  PersonalProvider({
    required FirestoreService firestoreService,
    bool? disableAuthentication,
  })  : _firestore = firestoreService,
        _forceLocalStorage =
            disableAuthentication ?? AppConfig.disableAuthentication;

  final FirestoreService _firestore;
  final bool _forceLocalStorage;
  bool _localStorageOnly = false;
  bool _hybridStorageEnabled = false;

  StreamSubscription<List<WorkTask>>? _tasksSubscription;
  StreamSubscription<List<PayrollRecord>>? _payrollSubscription;
  StreamSubscription<List<PayrollProfile>>? _profilesSubscription;
  StreamSubscription<List<AbsenceRequest>>? _absencesSubscription;

  AppUserProfile? _currentUser;
  List<WorkTask> _tasks = [];
  List<PayrollRecord> _payrollRecords = [];
  List<PayrollProfile> _payrollProfiles = [];
  List<AbsenceRequest> _absences = [];

  // Stammdaten aus dem TeamProvider (org-weit, via updateReferenceData).
  List<AppUserProfile> _members = [];
  List<EmploymentContract> _contracts = [];
  List<SiteDefinition> _sites = [];

  final PayrollSettings _payrollSettings = PayrollSettings.defaults2026();

  bool _loading = false;
  String? _errorMessage;
  bool _disposed = false;
  int _localSeq = 0;
  String? _lastSessionKey;

  // --- Getter --------------------------------------------------------------

  List<WorkTask> get tasks => _tasks;
  List<PayrollRecord> get payrollRecords => _payrollRecords;
  List<PayrollProfile> get payrollProfiles => _payrollProfiles;
  List<AbsenceRequest> get absences => _absences;
  List<AppUserProfile> get members => _members;
  List<EmploymentContract> get contracts => _contracts;
  List<SiteDefinition> get sites => _sites;
  PayrollSettings get payrollSettings => _payrollSettings;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;

  bool get usesLocalStorage => _forceLocalStorage || _localStorageOnly;
  bool get _usesFirestore => !usesLocalStorage;
  bool get usesHybridStorage =>
      !_forceLocalStorage && !_localStorageOnly && _hybridStorageEnabled;
  bool get isAdmin => _currentUser?.isAdmin ?? false;

  String? get _orgId => _currentUser?.orgId;

  String get _storageModeKey => usesLocalStorage
      ? 'local'
      : (_hybridStorageEnabled ? 'hybrid' : 'cloud');

  LocalStorageScope? get _localScope {
    final user = _currentUser;
    if (user == null) return null;
    return LocalStorageScope.fromUser(user);
  }

  // --- Abgeleitete Sichten -------------------------------------------------

  List<WorkTask> tasksForUser(String userId) =>
      _tasks.where((task) => task.assignedUserId == userId).toList();

  int openTaskCountForUser(String userId) =>
      _tasks.where((task) => task.assignedUserId == userId && !task.isDone).length;

  int get openTaskCount => _tasks.where((task) => !task.isDone).length;

  List<PayrollRecord> payrollForUser(String userId) =>
      _payrollRecords.where((record) => record.userId == userId).toList();

  /// Lohn-Stammdaten eines Mitarbeiters (für die Vorbefüllung der Abrechnung).
  PayrollProfile? profileForUser(String userId) {
    for (final profile in _payrollProfiles) {
      if (profile.userId == userId) return profile;
    }
    return null;
  }

  /// Jüngste Abrechnung eines Mitarbeiters (nach Periode).
  PayrollRecord? latestPayrollForUser(String userId) {
    final records = payrollForUser(userId);
    if (records.isEmpty) return null;
    records.sort((a, b) {
      final y = b.periodYear.compareTo(a.periodYear);
      if (y != 0) return y;
      return b.periodMonth.compareTo(a.periodMonth);
    });
    return records.first;
  }

  PayrollRecord? payrollForUserPeriod(String userId, int year, int month) {
    for (final record in _payrollRecords) {
      if (record.userId == userId &&
          record.periodYear == year &&
          record.periodMonth == month) {
        return record;
      }
    }
    return null;
  }

  List<AbsenceRequest> absencesForUser(String userId) =>
      _absences.where((absence) => absence.userId == userId).toList();

  /// Aktiver (oder jüngster) Arbeitsvertrag eines Mitarbeiters.
  EmploymentContract? contractForUser(String userId) {
    final now = DateTime.now();
    EmploymentContract? active;
    EmploymentContract? latest;
    for (final contract in _contracts) {
      if (contract.userId != userId) continue;
      if (latest == null || contract.validFrom.isAfter(latest.validFrom)) {
        latest = contract;
      }
      if (contract.isActiveOn(now)) {
        if (active == null || contract.validFrom.isAfter(active.validFrom)) {
          active = contract;
        }
      }
    }
    return active ?? latest;
  }

  AppUserProfile? memberById(String userId) {
    for (final member in _members) {
      if (member.uid == userId) return member;
    }
    return null;
  }

  /// Zählt Abwesenheiten (Anzahl + Tage) je Typ; ignoriert abgelehnte Anträge.
  /// Optional auf ein Kalenderjahr eingeschränkt.
  AbsenceStats absenceStatsForUser(String userId, {int? year}) {
    var sicknessCount = 0, sicknessDays = 0;
    var unavailableCount = 0, unavailableDays = 0;
    var vacationCount = 0, vacationDays = 0;
    for (final absence in _absences) {
      if (absence.userId != userId) continue;
      if (absence.status == AbsenceStatus.rejected) continue;
      if (year != null && absence.startDate.year != year) continue;
      final days = absence.endDate.difference(absence.startDate).inDays + 1;
      final span = days < 1 ? 1 : days;
      switch (absence.type) {
        case AbsenceType.sickness:
          sicknessCount++;
          sicknessDays += span;
        case AbsenceType.unavailable:
          unavailableCount++;
          unavailableDays += span;
        case AbsenceType.vacation:
          vacationCount++;
          vacationDays += span;
      }
    }
    return AbsenceStats(
      sicknessCount: sicknessCount,
      sicknessDays: sicknessDays,
      unavailableCount: unavailableCount,
      unavailableDays: unavailableDays,
      vacationCount: vacationCount,
      vacationDays: vacationDays,
    );
  }

  /// Lädt org-weit alle Zeiteinträge eines Monats (für Personalkosten/Finanz).
  /// Cloud/Hybrid über Firestore, local aus SharedPreferences.
  Future<List<WorkEntry>> loadOrgWorkEntriesForMonth(DateTime month) async {
    final orgId = _orgId;
    if (orgId == null) return const [];
    if (_usesFirestore) {
      try {
        return await _firestore.getOrgWorkEntriesForMonth(
          orgId: orgId,
          month: month,
        );
      } catch (error) {
        if (!usesHybridStorage) rethrow;
        AppLogger.warning(
          'Personal: loadOrgWorkEntriesForMonth offline – lokaler Fallback',
          error: error,
        );
      }
    }
    final all = await DatabaseService.loadLocalEntries(scope: _localScope);
    return all
        .where((entry) =>
            entry.date.year == month.year && entry.date.month == month.month)
        .toList(growable: false);
  }

  // --- Session / Reference Data -------------------------------------------

  void updateReferenceData({
    List<AppUserProfile> members = const [],
    List<EmploymentContract> contracts = const [],
    List<SiteDefinition> sites = const [],
  }) {
    _members = members;
    _contracts = contracts;
    _sites = sites;
    // Bewusst kein notifyListeners (Setter wird im Rebuild aufgerufen ->
    // sonst Rebuild-Loop, vgl. TeamProvider-Konvention).
  }

  Future<void> updateSession(
    AppUserProfile? user, {
    bool localStorageOnly = false,
    bool hybridStorageEnabled = false,
  }) async {
    _localStorageOnly = localStorageOnly;
    _hybridStorageEnabled = hybridStorageEnabled;
    final sessionKey =
        user == null ? null : '${user.uid}:${user.orgId}:$_storageModeKey';
    if (sessionKey == _lastSessionKey) {
      _currentUser = user;
      return;
    }
    _lastSessionKey = sessionKey;
    _currentUser = user;

    await _cancelSubscriptions();

    if (user == null) {
      _resetData();
      _safeNotify();
      return;
    }

    if (_usesFirestore) {
      _startFirestoreSubscriptions(user.orgId);
    } else {
      await _loadLocalData();
      _safeNotify();
    }
  }

  void _startFirestoreSubscriptions(String orgId) {
    _loading = true;
    _safeNotify();

    _tasksSubscription = _firestore.watchWorkTasks(orgId).listen((items) {
      _tasks = items;
      _loading = false;
      _safeNotify();
    }, onError: _setError);

    _payrollSubscription =
        _firestore.watchPayrollRecords(orgId).listen((items) {
      _payrollRecords = items;
      _safeNotify();
    }, onError: _setError);

    _profilesSubscription =
        _firestore.watchPayrollProfiles(orgId).listen((items) {
      _payrollProfiles = items;
      _safeNotify();
    }, onError: _setError);

    _absencesSubscription =
        _firestore.watchAllAbsenceRequests(orgId: orgId).listen((items) {
      _absences = items;
      _safeNotify();
    }, onError: _setError);
  }

  Future<void> _loadLocalData() async {
    final scope = _localScope;
    _tasks = await DatabaseService.loadLocalWorkTasks(scope: scope);
    _payrollRecords =
        await DatabaseService.loadLocalPayrollRecords(scope: scope);
    _payrollProfiles =
        await DatabaseService.loadLocalPayrollProfiles(scope: scope);
    _absences = await DatabaseService.loadLocalAbsenceRequests(scope: scope);
  }

  Future<void> _cancelSubscriptions() async {
    await _tasksSubscription?.cancel();
    await _payrollSubscription?.cancel();
    await _profilesSubscription?.cancel();
    await _absencesSubscription?.cancel();
    _tasksSubscription = null;
    _payrollSubscription = null;
    _profilesSubscription = null;
    _absencesSubscription = null;
  }

  void _resetData() {
    _tasks = [];
    _payrollRecords = [];
    _payrollProfiles = [];
    _absences = [];
    _loading = false;
  }

  // --- Arbeitsaufträge -----------------------------------------------------

  Future<void> saveWorkTask(WorkTask task) async {
    _assertAdmin();
    final orgId = _requireOrg();
    final prepared = task.copyWith(
      orgId: orgId,
      createdByUid: task.createdByUid ?? _currentUser?.uid,
    );
    if (_usesFirestore &&
        await _tryFirestore(
          'saveWorkTask',
          () => _firestore.saveWorkTask(prepared),
        )) {
      return;
    }
    final withId = prepared.id == null
        ? prepared.copyWith(id: _nextLocalId('task'))
        : prepared;
    _upsertLocal(_tasks, withId, (item) => item.id);
    _tasks = [..._tasks];
    await _persistTasks();
    _safeNotify();
  }

  Future<void> setTaskStatus(WorkTask task, TaskStatus status) =>
      saveWorkTask(task.copyWith(status: status));

  Future<void> deleteWorkTask(String taskId) async {
    _assertAdmin();
    final orgId = _orgId;
    if (orgId == null) return;
    if (_usesFirestore &&
        await _tryFirestore(
          'deleteWorkTask',
          () => _firestore.deleteWorkTask(orgId: orgId, taskId: taskId),
        )) {
      return;
    }
    _tasks = _tasks.where((task) => task.id != taskId).toList(growable: false);
    await _persistTasks();
    _safeNotify();
  }

  Future<void> _persistTasks() =>
      DatabaseService.saveLocalWorkTasks(_tasks, scope: _localScope);

  // --- Lohnabrechnungen ----------------------------------------------------

  Future<void> savePayrollRecord(PayrollRecord record) async {
    _assertAdmin();
    final orgId = _requireOrg();
    // Deterministische ID (pro Mitarbeiter/Monat) für stabilen Upsert.
    final withMeta = record.copyWith(
      orgId: orgId,
      createdByUid: record.createdByUid ?? _currentUser?.uid,
    );
    final prepared = withMeta.id == null
        ? withMeta.copyWith(id: withMeta.documentId)
        : withMeta;
    if (_usesFirestore &&
        await _tryFirestore(
          'savePayrollRecord',
          () => _firestore.savePayrollRecord(prepared),
        )) {
      return;
    }
    _upsertLocal(_payrollRecords, prepared, (item) => item.id);
    _payrollRecords = [..._payrollRecords];
    await _persistPayroll();
    _safeNotify();
  }

  Future<void> deletePayrollRecord(String recordId) async {
    _assertAdmin();
    final orgId = _orgId;
    if (orgId == null) return;
    if (_usesFirestore &&
        await _tryFirestore(
          'deletePayrollRecord',
          () =>
              _firestore.deletePayrollRecord(orgId: orgId, recordId: recordId),
        )) {
      return;
    }
    _payrollRecords = _payrollRecords
        .where((record) => record.id != recordId)
        .toList(growable: false);
    await _persistPayroll();
    _safeNotify();
  }

  Future<void> _persistPayroll() =>
      DatabaseService.saveLocalPayrollRecords(_payrollRecords,
          scope: _localScope);

  // --- Lohn-Stammdaten (PayrollProfile) ------------------------------------

  Future<void> savePayrollProfile(PayrollProfile profile) async {
    _assertAdmin();
    final orgId = _requireOrg();
    final withMeta = profile.copyWith(
      orgId: orgId,
      createdByUid: profile.createdByUid ?? _currentUser?.uid,
    );
    final prepared = withMeta.id == null
        ? withMeta.copyWith(id: withMeta.documentId)
        : withMeta;
    if (_usesFirestore &&
        await _tryFirestore(
          'savePayrollProfile',
          () => _firestore.savePayrollProfile(prepared),
        )) {
      return;
    }
    _upsertLocal(_payrollProfiles, prepared, (item) => item.id);
    _payrollProfiles = [..._payrollProfiles];
    await _persistProfiles();
    _safeNotify();
  }

  /// Merkt sich die Lohn-Stammdaten eines Mitarbeiters aus einer Abrechnung,
  /// damit die nächste Abrechnung vorbefüllt wird. Schreibt nur, wenn sich die
  /// relevanten Felder geändert haben (spart Firestore-Writes im Spark-Free-Tier).
  Future<void> rememberPayrollProfile({
    required String userId,
    required TaxClass taxClass,
    required PayrollEmploymentKind kind,
    required bool churchTax,
    String? federalState,
    int? monthlyGrossCents,
  }) async {
    if (!isAdmin) return;
    final orgId = _orgId;
    if (orgId == null) return;
    final existing = profileForUser(userId);
    final candidate = PayrollProfile(
      id: existing?.id,
      orgId: orgId,
      userId: userId,
      taxClass: taxClass,
      kind: kind,
      churchTax: churchTax,
      federalState: federalState,
      monthlyGrossCents: monthlyGrossCents,
      createdByUid: existing?.createdByUid,
      createdAt: existing?.createdAt,
    );
    if (existing != null && existing.sameMasterData(candidate)) {
      return; // unverändert -> kein Write
    }
    await savePayrollProfile(candidate);
  }

  Future<void> deletePayrollProfile(String userId) async {
    _assertAdmin();
    final orgId = _orgId;
    if (orgId == null) return;
    if (_usesFirestore &&
        await _tryFirestore(
          'deletePayrollProfile',
          () => _firestore.deletePayrollProfile(orgId: orgId, userId: userId),
        )) {
      return;
    }
    _payrollProfiles = _payrollProfiles
        .where((profile) => profile.userId != userId)
        .toList(growable: false);
    await _persistProfiles();
    _safeNotify();
  }

  Future<void> _persistProfiles() =>
      DatabaseService.saveLocalPayrollProfiles(_payrollProfiles,
          scope: _localScope);

  // --- Infrastruktur -------------------------------------------------------

  /// Versucht eine Firestore-Mutation. Erfolg -> true. Im Hybrid-Modus bei
  /// Fehler -> false (lokaler Fallback), sonst rethrow.
  Future<bool> _tryFirestore(
    String label,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      return true;
    } catch (error) {
      if (!usesHybridStorage) rethrow;
      AppLogger.warning(
        'Personal: $label offline – lokaler Fallback aktiv',
        error: error,
      );
      return false;
    }
  }

  void _assertAdmin() {
    if (!isAdmin) {
      throw StateError('Nur Admins dürfen den Personal-Bereich bearbeiten.');
    }
  }

  String _requireOrg() {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    return orgId;
  }

  String _nextLocalId(String prefix) {
    _localSeq += 1;
    return 'local-$prefix-${DateTime.now().microsecondsSinceEpoch}-$_localSeq';
  }

  void _upsertLocal<T>(List<T> list, T item, String? Function(T) idOf) {
    final id = idOf(item);
    final index = list.indexWhere((existing) => idOf(existing) == id);
    if (index >= 0) {
      list[index] = item;
    } else {
      list.add(item);
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void _setError(Object error) {
    _loading = false;
    _errorMessage = error is StateError ? error.message : error.toString();
    _safeNotify();
  }

  /// Macht Fehler beim fire-and-forget Sitzungsaufbau in der UI sichtbar.
  void surfaceSessionError(Object error) {
    _errorMessage =
        'Personaldaten konnten nicht geladen werden. Bitte später erneut versuchen.';
    _safeNotify();
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      _safeNotify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSubscriptions();
    super.dispose();
  }
}
