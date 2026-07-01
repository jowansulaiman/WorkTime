import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../models/app_user.dart';
import '../models/audit_log_entry.dart';
import '../models/store_task.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import 'audit_sink.dart';

/// Zustand der Laden-To-Dos ([StoreTask]) für den Arbeitsmodus/Kiosk.
///
/// Broadcast-Aufgaben je Laden (`siteId`) bzw. org-weit. Der **Leiter/Admin**
/// legt sie an, ändert und löscht sie ([canManage]); **jeder aktive Mitarbeiter**
/// darf sie am Kiosk **je Standort** abhaken ([markDoneForSite] / [reopenForSite]).
///
/// Speicher-Verhalten analog [PersonalProvider]/[InventoryProvider]: Cloud/Hybrid
/// über Firestore-Stream (Offline-Cache), local über SharedPreferences;
/// schreibende Operationen fallen im Hybrid-Modus offline lokal zurück.
class StoreTaskProvider extends ChangeNotifier {
  StoreTaskProvider({
    required FirestoreService firestoreService,
    bool? disableAuthentication,
  })  : _firestore = firestoreService,
        _forceLocalStorage =
            disableAuthentication ?? AppConfig.disableAuthentication;

  final FirestoreService _firestore;
  final bool _forceLocalStorage;
  bool _localStorageOnly = false;
  bool _hybridStorageEnabled = false;

  StreamSubscription<List<StoreTask>>? _tasksSubscription;

  AppUserProfile? _currentUser;
  List<StoreTask> _tasks = [];

  bool _loading = false;
  String? _errorMessage;
  bool _disposed = false;
  int _localSeq = 0;
  String? _lastSessionKey;
  AuditSink? _audit;

  // --- Getter --------------------------------------------------------------

  List<StoreTask> get tasks => _tasks;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;

  /// Darf der aktuelle Nutzer Laden-To-Dos anlegen/ändern/löschen?
  /// Leiter/Admin (gleiche Schwelle wie Schichtverwaltung).
  bool get canManage {
    final user = _currentUser;
    return user != null && (user.isAdmin || user.canManageShifts);
  }

  bool get usesLocalStorage => _forceLocalStorage || _localStorageOnly;
  bool get _usesFirestore => !usesLocalStorage;
  bool get usesHybridStorage =>
      !_forceLocalStorage && !_localStorageOnly && _hybridStorageEnabled;

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

  /// Aufgaben für einen Laden ([siteId]); `null` zeigt alle. Broadcast-Aufgaben
  /// (`task.siteId == null`) erscheinen in jedem Laden.
  List<StoreTask> storeTasksForSite(String? siteId) =>
      _tasks.where((t) => t.appliesToSite(siteId)).toList(growable: false);

  /// Offene (für **diesen Laden** noch nicht erledigte) Aufgaben. Eine
  /// Broadcast-Aufgabe bleibt so lange offen, bis genau dieser Laden sie abhakt.
  List<StoreTask> openStoreTasksForSite(String? siteId) => storeTasksForSite(siteId)
      .where((t) => !t.isDoneForSite(siteId))
      .toList(growable: false);

  /// Anzahl offener Aufgaben für einen Laden (für Badge/Kachel).
  int openStoreTaskCount([String? siteId]) =>
      openStoreTasksForSite(siteId).length;

  // --- Session/Verdrahtung -------------------------------------------------

  void setAuditSink(AuditSink sink) {
    _audit = sink;
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
      _tasks = [];
      _loading = false;
      _safeNotify();
      return;
    }

    if (_usesFirestore) {
      _loading = true;
      _safeNotify();
      _tasksSubscription = _firestore.watchStoreTasks(user.orgId).listen((items) {
        _tasks = items;
        _loading = false;
        _safeNotify();
      }, onError: _setError);
    } else {
      _tasks = await DatabaseService.loadLocalStoreTasks(scope: _localScope);
      _loading = false;
      _safeNotify();
    }
  }

  Future<void> _cancelSubscriptions() async {
    await _tasksSubscription?.cancel();
    _tasksSubscription = null;
  }

  // --- Mutatoren -----------------------------------------------------------

  /// Anlegen/Bearbeiten durch den Leiter (Admin/Teamlead).
  Future<void> saveStoreTask(StoreTask task) async {
    _assertCanManage();
    final orgId = _requireOrg();
    final isNew = task.id == null || task.id!.isEmpty;
    final prepared = task.copyWith(
      orgId: orgId,
      createdByUid: task.createdByUid ?? _currentUser?.uid,
    );
    await _writeStoreTask(
      prepared,
      isNew: isNew,
      summary: 'Laden-Aufgabe „${task.title}" '
          '${isNew ? 'angelegt' : 'aktualisiert'}',
      action: isNew ? AuditAction.created : AuditAction.updated,
    );
  }

  /// Abhaken **für genau einen Laden** — auch durch einen regulären Mitarbeiter
  /// am Kiosk. Setzt (nur) den Erledigt-Vermerk dieses Ladens; andere Läden
  /// bleiben unberührt (jeder Laden erledigt dieselbe Broadcast-Aufgabe selbst).
  Future<void> markDoneForSite(
    StoreTask task,
    String? siteId, {
    String? employeeId,
    String? employeeName,
  }) async {
    final orgId = _requireOrg();
    final key = StoreTask.siteKey(siteId);
    final completions =
        Map<String, StoreTaskCompletion>.from(task.completedBySite);
    completions[key] = StoreTaskCompletion(
      employeeId: employeeId,
      name: employeeName,
      at: DateTime.now(),
    );
    final who = (employeeName != null && employeeName.trim().isNotEmpty)
        ? ' (${employeeName.trim()})'
        : '';
    await _writeStoreTask(
      task.copyWith(orgId: orgId, completedBySite: completions),
      isNew: false,
      summary: 'Laden-Aufgabe „${task.title}" erledigt$who',
      action: AuditAction.updated,
    );
  }

  /// Erledigt-Vermerk **dieses Ladens** wieder entfernen (Aufgabe hier erneut
  /// offen).
  Future<void> reopenForSite(StoreTask task, String? siteId) async {
    final orgId = _requireOrg();
    final key = StoreTask.siteKey(siteId);
    if (!task.completedBySite.containsKey(key)) return;
    final completions =
        Map<String, StoreTaskCompletion>.from(task.completedBySite)..remove(key);
    await _writeStoreTask(
      task.copyWith(orgId: orgId, completedBySite: completions),
      isNew: false,
      summary: 'Laden-Aufgabe „${task.title}" wieder geöffnet',
      action: AuditAction.updated,
    );
  }

  Future<void> deleteStoreTask(String taskId) async {
    _assertCanManage();
    final orgId = _orgId;
    if (orgId == null) return;
    final title = _taskTitleById(taskId);
    final summary =
        title == null ? 'Laden-Aufgabe gelöscht' : 'Laden-Aufgabe „$title" gelöscht';
    if (_usesFirestore &&
        await _tryFirestore(
          'deleteStoreTask',
          () => _firestore.deleteStoreTask(orgId: orgId, taskId: taskId),
        )) {
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Laden-Aufgabe',
        entityId: taskId,
        summary: summary,
      );
      return;
    }
    _tasks = _tasks.where((task) => task.id != taskId).toList(growable: false);
    await _persistTasks();
    _safeNotify();
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Laden-Aufgabe',
      entityId: taskId,
      summary: summary,
    );
  }

  /// Gemeinsamer Schreibpfad (Cloud-Versuch → Hybrid-Local-Fallback → Audit nur
  /// auf dem Erfolgs-Pfad, in JEDEM Storage-Zweig).
  Future<void> _writeStoreTask(
    StoreTask prepared, {
    required bool isNew,
    required String summary,
    required AuditAction action,
  }) async {
    if (_usesFirestore &&
        await _tryFirestore(
          'saveStoreTask',
          () => _firestore.saveStoreTask(prepared),
        )) {
      _audit?.call(
        action: action,
        entityType: 'Laden-Aufgabe',
        entityId: prepared.id,
        summary: summary,
      );
      return;
    }
    final withId = prepared.id == null || prepared.id!.isEmpty
        ? prepared.copyWith(id: _nextLocalId('storetask'))
        : prepared;
    _upsertLocal(_tasks, withId, (item) => item.id);
    _tasks = [..._tasks];
    await _persistTasks();
    _safeNotify();
    _audit?.call(
      action: action,
      entityType: 'Laden-Aufgabe',
      entityId: withId.id,
      summary: summary,
    );
  }

  String? _taskTitleById(String taskId) {
    for (final task in _tasks) {
      if (task.id == taskId) return task.title;
    }
    return null;
  }

  Future<void> _persistTasks() =>
      DatabaseService.saveLocalStoreTasks(_tasks, scope: _localScope);

  // --- Speichermodus-Migration (analog PersonalProvider) -------------------

  /// Snapshot des aktuellen (Cloud-)Stands in den lokalen Speicher (für den
  /// Wechsel cloud/hybrid → local).
  Future<void> cacheCloudStateLocally() async {
    if (usesLocalStorage) return;
    await _persistTasks();
  }

  /// Lädt die lokalen Aufgaben beim Wechsel local → Cloud/Hybrid hoch
  /// (Upsert über deterministische Doc-IDs → idempotent).
  Future<void> syncLocalStateToCloud() async {
    if (_orgId == null) return;
    for (final t in List<StoreTask>.from(_tasks)) {
      try {
        await _firestore.saveStoreTask(t);
      } catch (error) {
        AppLogger.warning('syncLocalStateToCloud(storeTask): $error');
      }
    }
  }

  // --- Helfer --------------------------------------------------------------

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
        'StoreTask: $label offline – lokaler Fallback aktiv',
        error: error,
      );
      return false;
    }
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

  String _nextLocalId(String prefix) {
    _localSeq += 1;
    return 'local-$prefix-${DateTime.now().microsecondsSinceEpoch}-$_localSeq';
  }

  String _requireOrg() {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    return orgId;
  }

  void _assertCanManage() {
    if (!canManage) {
      throw StateError('Nur Leitung/Admin darf Laden-Aufgaben verwalten.');
    }
  }

  void _setError(Object error) {
    _loading = false;
    _errorMessage = error is StateError ? error.message : error.toString();
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSubscriptions();
    super.dispose();
  }
}
