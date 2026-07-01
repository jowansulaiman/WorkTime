import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/app_config.dart';
import '../core/compliance_rule_set_utils.dart';
import '../core/shift_auto_assigner.dart';
import '../core/shift_slot_generator.dart';
import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/audit_log_entry.dart';
import '../models/compliance_rule_set.dart';
import '../models/compliance_violation.dart';
import '../models/employee_site_assignment.dart';
import '../models/employment_contract.dart';
import '../models/shift_preference.dart';
import '../models/org_settings.dart';
import '../models/shift.dart';
import '../models/shift_swap_request.dart';
import '../models/swap_credit.dart';
import '../models/shift_template.dart';
import '../models/site_definition.dart';
import '../models/travel_time_rule.dart';
import '../services/database_service.dart';
import '../services/compliance_service.dart';
import '../services/compliance_rejected_exception.dart';
import '../services/firestore_service.dart';
import '../core/app_logger.dart';
import 'audit_sink.dart';

enum ScheduleViewMode { day, week, month }

class ShiftConflictIssue {
  const ShiftConflictIssue({
    required this.shift,
    this.conflictingShifts = const [],
    this.blockingAbsences = const [],
    this.conflictingDraftShifts = const [],
    this.violations = const [],
  });

  final Shift shift;
  final List<Shift> conflictingShifts;
  final List<AbsenceRequest> blockingAbsences;
  final List<Shift> conflictingDraftShifts;
  final List<ComplianceViolation> violations;

  List<ComplianceViolation> get blockingViolations => violations
      .where((violation) => violation.severity == ComplianceSeverity.blocking)
      .toList(growable: false);

  List<ComplianceViolation> get warningViolations => violations
      .where((violation) => violation.severity == ComplianceSeverity.warning)
      .toList(growable: false);

  bool get hasConflicts =>
      conflictingShifts.isNotEmpty ||
      blockingAbsences.isNotEmpty ||
      conflictingDraftShifts.isNotEmpty ||
      blockingViolations.isNotEmpty;
}

class ShiftConflictException implements Exception {
  const ShiftConflictException(this.issues);

  final List<ShiftConflictIssue> issues;

  @override
  String toString() {
    final count = issues.length;
    return count == 1
        ? 'Es wurde 1 Schichtkonflikt gefunden.'
        : 'Es wurden $count Schichtkonflikte gefunden.';
  }
}

class ShiftAssigneeAvailability {
  const ShiftAssigneeAvailability({
    required this.member,
    this.conflictingShifts = const [],
    this.blockingAbsences = const [],
    this.violations = const [],
  });

  final AppUserProfile member;
  final List<Shift> conflictingShifts;
  final List<AbsenceRequest> blockingAbsences;
  final List<ComplianceViolation> violations;

  List<ComplianceViolation> get blockingViolations => violations
      .where((violation) => violation.severity == ComplianceSeverity.blocking)
      .toList(growable: false);

  List<ComplianceViolation> get warningViolations => violations
      .where((violation) => violation.severity == ComplianceSeverity.warning)
      .toList(growable: false);

  bool get isAvailable =>
      conflictingShifts.isEmpty &&
      blockingAbsences.isEmpty &&
      blockingViolations.isEmpty;

  bool get hasWarnings => warningViolations.isNotEmpty;
}

class ScheduleProvider extends ChangeNotifier {
  ScheduleProvider({
    required FirestoreService firestoreService,
    ComplianceService? complianceService,
    bool? disableAuthentication,
    Uuid? uuid,
  })  : _firestoreService = firestoreService,
        _complianceService = complianceService ?? const ComplianceService(),
        _uuid = uuid ?? const Uuid(),
        _forceLocalStorage =
            disableAuthentication ?? AppConfig.disableAuthentication;

  final FirestoreService _firestoreService;
  final ComplianceService _complianceService;
  final Uuid _uuid;
  final bool _forceLocalStorage;

  /// Zuletzt im Schicht-Editor gewählter Standort (nur UI-Komfort, keine
  /// persistierte Daten): dient als Default-Vorbelegung des Pflicht-Standorts
  /// bei der nächsten Neuanlage. Bewusst statisch, damit es ein Editor-Leben
  /// überdauert.
  static String? lastUsedSiteId;
  bool _localStorageOnly = false;
  bool _hybridStorageEnabled = false;

  StreamSubscription<List<Shift>>? _shiftsSubscription;
  StreamSubscription<List<AbsenceRequest>>? _absenceSubscription;
  StreamSubscription<List<AbsenceRequest>>? _allAbsenceSubscription;
  StreamSubscription<List<ShiftTemplate>>? _templatesSubscription;
  // Schichttausch: Manager abonniert alle (`_allSwapSubscription`); Mitarbeiter
  // abonnieren eingehend (Ziel) + ausgehend (Antragsteller) getrennt, da
  // Firestore kein OR über zwei Felder kann.
  StreamSubscription<List<ShiftSwapRequest>>? _allSwapSubscription;
  StreamSubscription<List<ShiftSwapRequest>>? _swapIncomingSubscription;
  StreamSubscription<List<ShiftSwapRequest>>? _swapOutgoingSubscription;
  StreamSubscription<List<SwapCredit>>? _allSwapCreditSubscription;
  StreamSubscription<List<SwapCredit>>? _swapCreditAsCreditorSubscription;
  StreamSubscription<List<SwapCredit>>? _swapCreditAsDebtorSubscription;

  AppUserProfile? _currentUser;
  DateTime _visibleDate = DateTime.now();
  ScheduleViewMode _viewMode = ScheduleViewMode.week;
  String? _selectedUserId;
  String? _selectedTeamId;
  String? _selectedTeamName;
  List<Shift> _shifts = [];
  List<ShiftTemplate> _shiftTemplates = [];
  List<AbsenceRequest> _absenceRequests = [];
  List<AbsenceRequest> _allAbsenceRequests = [];
  // Schichttausch: `_swapRequests`/`_swapCredits` sind die zusammengeführte,
  // an die UI ausgegebene Sicht. `_swapInbox`/`_swapOutbox` (bzw.
  // `_creditsAsCreditor`/`_creditsAsDebtor`) sind die getrennten Stream-Quellen,
  // aus denen die Union gebildet wird.
  List<ShiftSwapRequest> _swapRequests = [];
  List<ShiftSwapRequest> _swapInbox = [];
  List<ShiftSwapRequest> _swapOutbox = [];
  List<SwapCredit> _swapCredits = [];
  List<SwapCredit> _creditsAsCreditor = [];
  List<SwapCredit> _creditsAsDebtor = [];
  List<Shift> _localShifts = [];
  List<ShiftTemplate> _localShiftTemplates = [];
  List<AbsenceRequest> _localAbsenceRequests = [];
  List<ShiftSwapRequest> _localSwapRequests = [];
  List<SwapCredit> _localSwapCredits = [];
  // Lokal geloeschte IDs (Tombstones), die ein Wieder-Einspielen aus der Cloud
  // unterdruecken, bis die Loeschung propagiert wurde.
  Set<String> _deletedShiftIds = <String>{};
  Set<String> _deletedAbsenceIds = <String>{};
  List<AppUserProfile> _orgMembers = [];
  List<EmploymentContract> _contracts = [];
  List<EmployeeSiteAssignment> _siteAssignments = [];
  List<EmployeeShiftPreference> _shiftPreferences = [];
  List<SiteDefinition> _sites = [];
  List<ComplianceRuleSet> _ruleSets = [];
  List<TravelTimeRule> _travelTimeRules = [];
  bool _loading = false;
  String? _errorMessage;
  bool _disposed = false;
  ShiftStatus? _statusFilter;

  // Memoisierung des shifts-Getters: die gefilterte Liste wird gegen die
  // Eingaben (Identitaet von _shifts + Status-/Team-Filter) gecacht, damit
  // nicht bei jedem Rebuild/Getter-Zugriff neu allokiert/gefiltert wird
  // (schedule-shifts-getter-refilters). _shifts wird stets neu zugewiesen
  // (nie in-place mutiert), daher ist der Identitaetsvergleich korrekt.
  List<Shift>? _filteredShiftsCache;
  List<Shift>? _filteredShiftsCacheSource;
  ShiftStatus? _filteredShiftsCacheStatus;
  String? _filteredShiftsCacheTeamId;
  String? _filteredShiftsCacheTeamName;

  DateTime get visibleDate => _visibleDate;
  ScheduleViewMode get viewMode => _viewMode;
  String? get selectedUserId => _selectedUserId;
  String? get selectedTeamId => _selectedTeamId;
  String? get selectedTeamName => _selectedTeamName;
  List<Shift> get shifts {
    final cached = _filteredShiftsCache;
    if (cached != null &&
        identical(_filteredShiftsCacheSource, _shifts) &&
        _filteredShiftsCacheStatus == _statusFilter &&
        _filteredShiftsCacheTeamId == _selectedTeamId &&
        _filteredShiftsCacheTeamName == _selectedTeamName) {
      return cached;
    }
    // Unveraenderlich, da die Referenz gecacht und geteilt wird (ein
    // versehentliches In-Place-sort() wuerde sonst den Cache korrumpieren).
    final result = List<Shift>.unmodifiable(_filterShifts(_shifts));
    _filteredShiftsCache = result;
    _filteredShiftsCacheSource = _shifts;
    _filteredShiftsCacheStatus = _statusFilter;
    _filteredShiftsCacheTeamId = _selectedTeamId;
    _filteredShiftsCacheTeamName = _selectedTeamName;
    return result;
  }
  List<ShiftTemplate> get shiftTemplates => _shiftTemplates;
  List<AbsenceRequest> get absenceRequests => _absenceRequests;
  List<AbsenceRequest> get allAbsenceRequests => _allAbsenceRequests;

  /// Für den aktuellen Nutzer sichtbare Tauschanfragen (Manager: alle der Org;
  /// Mitarbeiter: eigene ein- und ausgehende).
  List<ShiftSwapRequest> get swapRequests => List.unmodifiable(_swapRequests);

  /// Für den aktuellen Nutzer sichtbare Schicht-Gutschriften (Manager: alle;
  /// Mitarbeiter: eigene als Gläubiger/Schuldner).
  List<SwapCredit> get swapCredits => List.unmodifiable(_swapCredits);

  /// Anzahl der Tauschanfragen, die der aktuelle Nutzer aktiv bearbeiten muss
  /// (Badge am Anfragen-Tab): als Ziel eine offene Anfrage annehmen/ablehnen,
  /// als Chef eine vom Kollegen angenommene Anfrage bestätigen/ablehnen.
  int get pendingSwapActionCount {
    final user = _currentUser;
    if (user == null) {
      return 0;
    }
    return _swapRequests.where((request) {
      if (request.targetUid == user.uid &&
          request.status == SwapStatus.pending) {
        return true;
      }
      if (user.canManageShifts &&
          request.status == SwapStatus.acceptedByColleague) {
        return true;
      }
      return false;
    }).length;
  }

  /// Offene Gutschriften des aktuellen Nutzers (für die Anzeige „du schuldest"
  /// / „dir wird geschuldet").
  List<SwapCredit> get openSwapCredits =>
      _swapCredits.where((credit) => credit.isOpen).toList(growable: false);

  /// Gesamtzahl offener Punkte im Anfragen-Tab (für das Badge am Tab): offene
  /// Abwesenheitsanträge (für Manager alle, für Mitarbeiter die eigenen) plus
  /// die aktiv zu bearbeitenden Tauschanfragen ([pendingSwapActionCount]).
  int get pendingInboxActionCount {
    final user = _currentUser;
    if (user == null) {
      return 0;
    }
    final pendingAbsences = _allAbsenceRequests
        .where((request) =>
            request.status == AbsenceStatus.pending &&
            (user.canManageShifts || request.userId == user.uid))
        .length;
    return pendingAbsences + pendingSwapActionCount;
  }

  /// Sichtbare Org-Mitglieder (für die Vertreter-Auswahl im Antrag); leer, bis
  /// der Planer-Datenstrom die Referenzdaten geliefert hat.
  List<AppUserProfile> get orgMembers => List.unmodifiable(_orgMembers);
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;
  ShiftStatus? get statusFilter => _statusFilter;

  /// Macht einen Fehler beim fire-and-forget Sitzungsaufbau in der UI sichtbar
  /// (fire-and-forget-updatesession).
  void surfaceSessionError(Object error) {
    _errorMessage =
        'Daten konnten nicht geladen werden. Bitte später erneut versuchen.';
    _safeNotify();
  }
  bool get usesLocalStorage => _forceLocalStorage || _localStorageOnly;
  bool get usesHybridStorage =>
      !_forceLocalStorage && !_localStorageOnly && _hybridStorageEnabled;

  /// Anzahl lokal vorgemerkter, noch nicht in die Cloud übertragener Löschungen
  /// (Schicht- und Abwesenheits-Tombstones) – ehrliches „ausstehender
  /// Abgleich"-Signal für die Sync-Status-UX (no-connectivity-no-sync-status-ux).
  int get pendingDeletionCount =>
      _deletedShiftIds.length + _deletedAbsenceIds.length;

  AuditSink? _audit;

  /// Senke fürs Änderungsprotokoll (best-effort). Wird in main.dart verdrahtet.
  void setAuditSink(AuditSink sink) {
    _audit = sink;
  }

  void updateReferenceData({
    required List<AppUserProfile> members,
    required List<EmploymentContract> contracts,
    required List<EmployeeSiteAssignment> siteAssignments,
    required List<ComplianceRuleSet> ruleSets,
    required List<TravelTimeRule> travelTimeRules,
    List<SiteDefinition> sites = const [],
    List<EmployeeShiftPreference> shiftPreferences = const [],
  }) {
    _orgMembers = members;
    _contracts = contracts;
    _siteAssignments = siteAssignments;
    _sites = sites;
    _ruleSets = ruleSets;
    _travelTimeRules = travelTimeRules;
    _shiftPreferences = shiftPreferences;
  }

  /// Standorte mit Öffnungszeiten/Bedarf (für die Auto-Schichtverteilung).
  List<SiteDefinition> get sites => List.unmodifiable(_sites);

  String? _lastSessionKey;

  LocalStorageScope? get _localScope {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return null;
    }
    return LocalStorageScope.fromUser(currentUser);
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
      }
      return;
    }
    _lastSessionKey = sessionKey;

    final changed =
        user?.uid != _currentUser?.uid || user?.orgId != _currentUser?.orgId;
    _currentUser = user;
    if (user == null) {
      _selectedUserId = null;
      _selectedTeamId = null;
      _selectedTeamName = null;
      _shifts = [];
      _shiftTemplates = [];
      _absenceRequests = [];
      _allAbsenceRequests = [];
      _swapRequests = [];
      _swapInbox = [];
      _swapOutbox = [];
      _swapCredits = [];
      _creditsAsCreditor = [];
      _creditsAsDebtor = [];
      _localShifts = [];
      _localShiftTemplates = [];
      _localAbsenceRequests = [];
      _localSwapRequests = [];
      _localSwapCredits = [];
      _orgMembers = [];
      _contracts = [];
      _siteAssignments = [];
      _shiftPreferences = [];
      _ruleSets = [];
      _travelTimeRules = [];
      await _shiftsSubscription?.cancel();
      await _absenceSubscription?.cancel();
      await _allAbsenceSubscription?.cancel();
      await _templatesSubscription?.cancel();
      await _cancelSwapSubscriptions();
      _safeNotify();
      return;
    }

    if (usesHybridStorage && changed) {
      await _shiftsSubscription?.cancel();
      await _absenceSubscription?.cancel();
      await _allAbsenceSubscription?.cancel();
      await _templatesSubscription?.cancel();
      await _cancelSwapSubscriptions();
      _shiftsSubscription = null;
      _absenceSubscription = null;
      _allAbsenceSubscription = null;
      _templatesSubscription = null;
    }

    _selectedUserId = user.canManageShifts ? _selectedUserId : user.uid;

    if (usesLocalStorage) {
      await _shiftsSubscription?.cancel();
      await _absenceSubscription?.cancel();
      await _allAbsenceSubscription?.cancel();
      await _templatesSubscription?.cancel();
      await _cancelSwapSubscriptions();
      if (changed ||
          (_localShifts.isEmpty &&
              _localShiftTemplates.isEmpty &&
              _localAbsenceRequests.isEmpty)) {
        await _loadLocalState();
      } else {
        _applyLocalState();
        _safeNotify();
      }
      return;
    }

    if (usesHybridStorage) {
      if (changed ||
          storageModeChanged ||
          (_localShifts.isEmpty &&
              _localShiftTemplates.isEmpty &&
              _localAbsenceRequests.isEmpty)) {
        await _loadLocalState();
      }
      if (changed || storageModeChanged) {
        await _restartSubscriptions();
      }
      _safeNotify();
      return;
    }

    if (changed || storageModeChanged) {
      await _restartSubscriptions();
    }
  }

  /// #74: `_restartSubscriptions` ist async — als fire-and-forget aus den
  /// View-Settern aufgerufen, aber mit Fehlerbehandlung (sonst verschluckte
  /// Exceptions + hängender Ladespinner).
  void _restartSubscriptionsSafely() {
    unawaited(_restartSubscriptions().catchError((Object error) {
      _errorMessage = 'Fehler beim Laden der Schichten: $error';
      _loading = false;
      _safeNotify();
    }));
  }

  void setViewMode(ScheduleViewMode mode) {
    _viewMode = mode;
    if (usesHybridStorage) {
      _applyLocalState();
      _safeNotify();
    }
    _restartSubscriptionsSafely();
  }

  void setVisibleDate(DateTime date) {
    _visibleDate = date;
    if (usesHybridStorage) {
      _applyLocalState();
      _safeNotify();
    }
    _restartSubscriptionsSafely();
  }

  void setSelectedUserId(String? userId) {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return;
    }
    _selectedUserId = currentUser.canManageShifts ? userId : currentUser.uid;
    if (usesHybridStorage) {
      _applyLocalState();
      _safeNotify();
    }
    _restartSubscriptionsSafely();
  }

  void setTeamFilter(String? teamId, {String? teamName}) {
    _selectedTeamId = teamId;
    _selectedTeamName = teamId == null ? null : teamName?.trim();
    _safeNotify();
  }

  void setStatusFilter(ShiftStatus? status) {
    _statusFilter = status;
    _safeNotify();
  }

  Future<void> saveShifts(
    List<Shift> shifts, {
    RecurrencePattern recurrencePattern = RecurrencePattern.none,
    DateTime? recurrenceEndDate,
    String? seriesId,
    bool skipCompliance = false,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts || shifts.isEmpty) {
      return;
    }

    // Optionale gemeinsame Serien-ID (z.B. Mehrtage-Anlage / Kopier-Aktionen):
    // gruppiert ansonsten unabhängige Schichten zu einer Serie, ohne ein
    // vorhandenes seriesId zu überschreiben. ACHTUNG Teil-Write-Risiko: ein
    // Batch > 50 läuft als mehrere atomare Server-Calls; schlägt ein späterer
    // Chunk per Compliance fehl, bleiben frühere Chunks geschrieben (kein
    // Cross-Chunk-Rollback). Aufrufer (Editor) begrenzt/prüft den Fan-out vorab.
    final preparedShifts = seriesId == null
        ? shifts
        : shifts
            .map(
              (shift) => (shift.seriesId == null || shift.seriesId!.isEmpty)
                  ? shift.copyWith(seriesId: seriesId)
                  : shift,
            )
            .toList(growable: false);

    // skipCompliance = bewusster Chef-Override (Schichttausch): weder die
    // clientseitige Vorprüfung werfen noch (unten) die validierende Callable
    // nutzen — der Direkt-Write umgeht die serverseitige Compliance.
    if (!skipCompliance) {
      final conflictIssues = await validateShifts(
        preparedShifts,
        recurrencePattern: recurrencePattern,
        recurrenceEndDate: recurrenceEndDate,
      );
      if (conflictIssues.isNotEmpty) {
        throw ShiftConflictException(conflictIssues);
      }
    }

    // created vs updated VOR dem Vergeben neuer ids ableiten: sind alle
    // Eingabe-Schichten neu (keine id), ist es eine Neuanlage – sonst (auch bei
    // gemischtem Batch) als Änderung protokollieren.
    final allNew =
        preparedShifts.every((shift) => shift.id == null || shift.id!.isEmpty);
    final auditAction = allNew ? AuditAction.created : AuditAction.updated;

    if (usesLocalStorage) {
      var occurrenceCount = 0;
      String? lastShiftId;
      for (final shift in preparedShifts) {
        final occurrences = _firestoreService.buildShiftOccurrences(
          shift.copyWith(createdByUid: currentUser.uid),
          recurrencePattern: recurrencePattern,
          recurrenceEndDate: recurrenceEndDate,
        );

        for (final occurrence in occurrences) {
          final stored = occurrence.copyWith(
            id: occurrence.id ?? _nextLocalId('shift'),
          );
          _upsertLocalShift(stored);
          occurrenceCount++;
          lastShiftId = stored.id;
        }
      }

      await _persistLocalShifts();
      _applyLocalState();
      notifyListeners();
      _audit?.call(
        action: auditAction,
        entityType: 'Schicht',
        entityId: occurrenceCount == 1 ? lastShiftId : null,
        summary: occurrenceCount == 1
            ? '1 Schicht gespeichert'
            : '$occurrenceCount Schichten gespeichert',
      );
      return;
    }

    final occurrences = preparedShifts
        .expand(
          (shift) => _firestoreService.buildShiftOccurrences(
            shift.copyWith(createdByUid: currentUser.uid),
            recurrencePattern: recurrencePattern,
            recurrenceEndDate: recurrenceEndDate,
          ),
        )
        // Jede Occurrence bekommt schon hier eine stabile Doc-ID, damit der
        // Callable-Pfad idempotent ist (no-idempotency-key); bei id == null
        // wuerde der Server sonst inhaltsbasiert hashen.
        .map((occurrence) =>
            occurrence.copyWith(id: occurrence.id ?? _nextLocalId('shift')))
        .toList(growable: false);
    try {
      if (skipCompliance) {
        await _firestoreService.saveShiftBatchDirect(occurrences);
      } else {
        await _firestoreService.saveShiftBatch(occurrences);
      }
    } on ComplianceRejectedException {
      // Bewusste serverseitige Compliance-Ablehnung – nie lokal überschreiben,
      // auch nicht im Hybrid-Modus.
      rethrow;
    } catch (error) {
      if (!usesHybridStorage) {
        rethrow;
      }
      for (final occurrence in occurrences) {
        _upsertLocalShift(
          occurrence.copyWith(
            id: occurrence.id ?? _nextLocalId('shift'),
          ),
        );
      }
      await _persistLocalShifts();
      _applyLocalState();
      _safeNotify();
      _audit?.call(
        action: auditAction,
        entityType: 'Schicht',
        entityId: occurrences.length == 1 ? occurrences.first.id : null,
        summary: occurrences.length == 1
            ? '1 Schicht gespeichert'
            : '${occurrences.length} Schichten gespeichert',
      );
      return;
    }
    _audit?.call(
      action: auditAction,
      entityType: 'Schicht',
      entityId: occurrences.length == 1 ? occurrences.first.id : null,
      summary: occurrences.length == 1
          ? '1 Schicht gespeichert'
          : '${occurrences.length} Schichten gespeichert',
    );
  }

  // --- Automatische Schichtverteilung (Phase A Generierung + Phase B Besetzung) ---

  /// **Phase A:** Generiert unbesetzte Schicht-Slots aus den Standort-
  /// Öffnungszeiten + Personalbedarf für `[rangeStart, rangeEnd)`. Reiner
  /// Wrapper um [ShiftSlotGenerator] — keine Mutation/notify/Audit.
  List<Shift> generatePlannedShifts({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required OrgSettings settings,
  }) {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) {
      return const [];
    }
    final existingInRange = _shifts
        .where((shift) =>
            !shift.startTime.isBefore(rangeStart) &&
            shift.startTime.isBefore(rangeEnd))
        .toList(growable: false);
    return ShiftSlotGenerator(
      sites: _sites,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      settings: settings,
      existingShifts: existingInRange,
      orgId: currentUser.orgId,
      seriesId: newSeriesId(),
      shiftIdFactory: () => _nextLocalId('shift'),
    ).generate();
  }

  /// **Phase B:** Verteilt unbesetzte Schichten ([openShifts] = Phase-A-Ergebnis
  /// + bereits vorhandene offene Schichten) auf Mitarbeiter unter harten
  /// Constraints + weichen Zielen. Reiner Wrapper um [ShiftAutoAssigner] — keine
  /// Mutation.
  ///
  /// **Wichtig:** Für korrekte Monats-/Wochen-Stundensummen (Caps + Minijob)
  /// werden die bereits besetzten Schichten + genehmigten Abwesenheiten für den
  /// **vollen Monat** UND die **ISO-Wochen der offenen Schichten** gesammelt —
  /// NICHT nur den sichtbaren Bereich (`_shifts` deckt nur die aktuelle Woche
  /// ab). In Cloud/Hybrid per `getShiftsInRange`/`getApprovedAbsencesInRange`
  /// (org-weit), im Local-Modus aus dem vollständigen lokalen Cache.
  Future<AutoAssignmentResult> proposeAutoAssignment({
    required List<Shift> openShifts,
    required DateTime month,
    required OrgSettings settings,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) {
      return const AutoAssignmentResult();
    }
    final orgId = currentUser.orgId;

    // Sammelbereich = voller Monat, erweitert um die ISO-Wochen der offenen
    // Schichten (decken Wochen ab, die über die Monatsgrenze ragen).
    var gatherStart = DateTime(month.year, month.month, 1);
    var gatherEnd = DateTime(month.year, month.month + 1, 1);
    for (final shift in openShifts) {
      final day = DateTime(
        shift.startTime.year,
        shift.startTime.month,
        shift.startTime.day,
      );
      final weekStart = day.subtract(Duration(days: shift.startTime.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 7));
      if (weekStart.isBefore(gatherStart)) gatherStart = weekStart;
      if (weekEnd.isAfter(gatherEnd)) gatherEnd = weekEnd;
    }

    final existingAssigned =
        await _assignedShiftsInRange(orgId, gatherStart, gatherEnd);
    final approvedAbsences =
        await _approvedAbsencesInRange(orgId, gatherStart, gatherEnd);

    final preferencesByUserId = <String, EmployeeShiftPreference>{
      for (final pref in _shiftPreferences)
        if (pref.userId.trim().isNotEmpty) pref.userId: pref,
    };

    return ShiftAutoAssigner(
      openShifts: openShifts,
      members: _orgMembers,
      contracts: _contracts,
      siteAssignments: _siteAssignments,
      approvedAbsences: approvedAbsences,
      existingAssignedShifts: existingAssigned,
      ruleSets: _effectiveRuleSets,
      travelTimeRules: _travelTimeRules,
      complianceService: _complianceService,
      settings: settings,
      preferencesByUserId: preferencesByUserId,
      preferenceWeight: _autoPlanPreferenceWeight,
    ).assign();
  }

  /// Gewicht der weichen Schicht-Vorlieben (prefer/avoid) im Verteiler-Score.
  /// Größenordnung wie die Monats-Fairness, damit Vorlieben spürbar nudgen,
  /// ohne Abdeckung/harte Regeln zu übersteuern (harte `block`-Sperren wirken
  /// unabhängig davon).
  static const double _autoPlanPreferenceWeight = 0.75;

  /// Bereits besetzte Schichten im Bereich `[start, end)` — org-weit. Local:
  /// aus dem vollständigen lokalen Cache; Cloud/Hybrid: per Firestore-Query
  /// (Hybrid zusätzlich mit lokaler Spiegelung gemerged, dedupliziert nach id).
  Future<List<Shift>> _assignedShiftsInRange(
    String orgId,
    DateTime start,
    DateTime end,
  ) async {
    bool inRange(Shift s) =>
        !s.isUnassigned &&
        s.orgId == orgId &&
        !s.startTime.isBefore(start) &&
        s.startTime.isBefore(end);

    if (usesLocalStorage) {
      return _localShifts.where(inRange).toList(growable: false);
    }
    try {
      final fetched = await _firestoreService.getShiftsInRange(
        orgId: orgId,
        start: start,
        end: end,
      );
      final assigned = fetched.where((s) => !s.isUnassigned);
      if (!usesHybridStorage) {
        return assigned.toList(growable: false);
      }
      // Hybrid: lokale (gespiegelte) Schichten dazunehmen, dedup nach id.
      final byId = <String, Shift>{};
      final anonymous = <Shift>[];
      for (final shift in [...assigned, ..._localShifts.where(inRange)]) {
        final id = shift.id;
        if (id == null || id.isEmpty) {
          anonymous.add(shift);
        } else {
          byId[id] = shift;
        }
      }
      return [...byId.values, ...anonymous];
    } catch (_) {
      // Fail-safe: in-memory (vollständiger lokaler Cache + sichtbarer Bereich).
      final byId = <String, Shift>{};
      final anonymous = <Shift>[];
      for (final shift in [..._localShifts.where(inRange), ..._shifts.where(inRange)]) {
        final id = shift.id;
        if (id == null || id.isEmpty) {
          anonymous.add(shift);
        } else {
          byId[id] = shift;
        }
      }
      return [...byId.values, ...anonymous];
    }
  }

  /// Genehmigte Abwesenheiten im Bereich `[start, end)` — org-weit. Local: aus
  /// dem Snapshot; Cloud/Hybrid: per Firestore-Query.
  Future<List<AbsenceRequest>> _approvedAbsencesInRange(
    String orgId,
    DateTime start,
    DateTime end,
  ) async {
    if (usesLocalStorage) {
      return _approvedAbsencesSnapshot()
          .where((a) => a.overlaps(start, end))
          .toList(growable: false);
    }
    try {
      final fetched = await _firestoreService.getApprovedAbsencesInRange(
        orgId: orgId,
        start: start,
        end: end,
      );
      return fetched
          .where((a) => a.status == AbsenceStatus.approved)
          .toList(growable: false);
    } catch (_) {
      return _approvedAbsencesSnapshot()
          .where((a) => a.overlaps(start, end))
          .toList(growable: false);
    }
  }

  /// Genehmigte Abwesenheiten aus allen geladenen Quellen (cloud/admin/local),
  /// dedupliziert nach id.
  List<AbsenceRequest> _approvedAbsencesSnapshot() {
    final byId = <String, AbsenceRequest>{};
    final anonymous = <AbsenceRequest>[];
    for (final list in [
      _allAbsenceRequests,
      _absenceRequests,
      _localAbsenceRequests,
    ]) {
      for (final absence in list) {
        if (absence.status != AbsenceStatus.approved) continue;
        final id = absence.id;
        if (id == null || id.isEmpty) {
          anonymous.add(absence);
        } else {
          byId[id] = absence;
        }
      }
    }
    return [...byId.values, ...anonymous];
  }

  /// Speichert das kombinierte Ergebnis: neu generierte Schichten (zugewiesen
  /// oder unbesetzt) plus bereits vorhandene offene Schichten, die im [result]
  /// eine Zuweisung bekommen haben. Delegiert an [saveShifts] (Batch ≤50,
  /// Storage-Modi, Compliance-Re-Validierung, Exceptions). Erbt das
  /// Mutator-Muster (hybrid-Fallback/cloud-rethrow).
  Future<void> applyAutoPlan({
    required List<Shift> generatedShifts,
    required List<Shift> existingOpenShifts,
    required AutoAssignmentResult result,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) {
      return;
    }
    final proposalByShiftId = <String, ShiftAssignmentProposal>{
      for (final proposal in result.assignments) proposal.shiftId: proposal,
    };

    final finalShifts = <Shift>[];
    // Neu generierte Schichten: zuweisen wenn möglich, sonst unbesetzt anlegen
    // (sichtbarer Bedarf bleibt erhalten — Plan §13.4).
    for (final shift in generatedShifts) {
      final proposal =
          shift.id == null ? null : proposalByShiftId[shift.id!];
      finalShifts.add(proposal == null
          ? shift
          : shift.copyWith(
              userId: proposal.userId,
              employeeName: proposal.userName,
            ));
    }
    // Bereits vorhandene offene Schichten: NUR (erneut) speichern, wenn jetzt
    // zugewiesen — sonst unangetastet lassen.
    for (final shift in existingOpenShifts) {
      final proposal =
          shift.id == null ? null : proposalByShiftId[shift.id!];
      if (proposal == null) continue;
      finalShifts.add(shift.copyWith(
        userId: proposal.userId,
        employeeName: proposal.userName,
      ));
    }

    if (finalShifts.isEmpty) {
      return;
    }

    // seriesId/recurrence bewusst NICHT neu setzen — Phase-A-Schichten tragen
    // den generierten seriesId bereits und sind schon expandiert.
    await saveShifts(finalShifts);

    // Genau EINE zusätzliche Auto-Plan-Summary, nur auf dem Erfolgs-Pfad
    // (saveShifts hat oben ggf. geworfen → diese Zeile wird dann übersprungen).
    final assignedCount =
        finalShifts.where((shift) => !shift.isUnassigned).length;
    _audit?.call(
      action: AuditAction.created,
      entityType: 'Schicht',
      entityId: null,
      summary:
          '${generatedShifts.length} Schichten generiert, $assignedCount automatisch besetzt',
    );
  }

  Future<void> saveShiftTemplate(ShiftTemplate template) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) {
      return;
    }

    if (usesLocalStorage) {
      final localTemplate = template.copyWith(
        id: template.id ?? _nextLocalId('shift-template'),
        orgId: currentUser.orgId,
        userId: currentUser.uid,
      );
      _upsertLocalShiftTemplate(localTemplate);
      await _persistLocalShiftTemplates();
      _applyLocalState();
      notifyListeners();
      return;
    }

    final preparedTemplate = template.copyWith(
      orgId: currentUser.orgId,
      userId: currentUser.uid,
    );
    try {
      await _firestoreService.saveShiftTemplate(preparedTemplate);
    } catch (error) {
      if (!usesHybridStorage) {
        rethrow;
      }
      _upsertLocalShiftTemplate(
        preparedTemplate.copyWith(
          id: preparedTemplate.id ?? _nextLocalId('shift-template'),
        ),
      );
      await _persistLocalShiftTemplates();
      _applyLocalState();
      _safeNotify();
    }
  }

  Future<void> deleteShiftTemplate(String id) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) {
      return;
    }

    if (usesLocalStorage) {
      _localShiftTemplates.removeWhere((template) => template.id == id);
      await DatabaseService.saveLocalShiftTemplates(
        _localShiftTemplates,
        scope: _localScope,
      );
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.deleteShiftTemplate(
      orgId: currentUser.orgId,
      templateId: id,
    );
  }

  Future<List<ShiftConflictIssue>> validateShifts(
    List<Shift> shifts, {
    RecurrencePattern recurrencePattern = RecurrencePattern.none,
    DateTime? recurrenceEndDate,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts || shifts.isEmpty) {
      return const [];
    }

    final expandedShifts = shifts
        .expand(
          (shift) => _firestoreService.buildShiftOccurrences(
            shift,
            recurrencePattern: recurrencePattern,
            recurrenceEndDate: recurrenceEndDate,
          ),
        )
        .toList(growable: false);
    final issues = <ShiftConflictIssue>[];
    for (var i = 0; i < expandedShifts.length; i++) {
      final shift = expandedShifts[i];
      final hasAssignee = !shift.isUnassigned;
      final queryWindow = _buildShiftAvailabilityWindow(
        shift.startTime,
        shift.endTime,
      );
      final contextualShifts = !hasAssignee
          ? const <Shift>[]
          : usesLocalStorage
              ? _localShifts.where((candidate) {
                  return candidate.orgId == shift.orgId &&
                      candidate.userId == shift.userId &&
                      !candidate.startTime.isBefore(queryWindow.start) &&
                      candidate.startTime.isBefore(queryWindow.end);
                }).toList(growable: false)
              : await _firestoreService.getShiftsInRange(
                  orgId: shift.orgId,
                  start: queryWindow.start,
                  end: queryWindow.end,
                  userId: shift.userId,
                );
      final approvedAbsences = !hasAssignee
          ? const <AbsenceRequest>[]
          : usesLocalStorage
              ? _localAbsenceRequests.where((request) {
                  return request.orgId == shift.orgId &&
                      request.userId == shift.userId &&
                      request.status == AbsenceStatus.approved &&
                      request.overlaps(queryWindow.start, queryWindow.end);
                }).toList(growable: false)
              : await _firestoreService.getApprovedAbsencesInRange(
                  orgId: shift.orgId,
                  start: queryWindow.start,
                  end: queryWindow.end,
                  userId: shift.userId,
                );
      final conflictingShifts = contextualShifts
          .where((candidate) =>
              candidate.id != shift.id && candidate.overlaps(shift))
          .toList(growable: false);
      final blockingAbsences = approvedAbsences
          .where((request) => request.overlaps(shift.startTime, shift.endTime))
          .toList(growable: false);
      final conflictingDraftShifts = <Shift>[];

      for (var j = 0; j < expandedShifts.length; j++) {
        if (i == j) {
          continue;
        }
        final candidate = expandedShifts[j];
        if (candidate.id == shift.id &&
            candidate.id != null &&
            candidate.userId == shift.userId) {
          continue;
        }
        if (candidate.overlaps(shift)) {
          conflictingDraftShifts.add(candidate);
        }
      }

      final violations = _complianceService.validateShift(
        shift: shift,
        existingShifts: contextualShifts,
        draftShifts: conflictingDraftShifts,
        absences: approvedAbsences,
        contracts: _contracts,
        siteAssignments: _siteAssignments,
        ruleSets: _effectiveRuleSets,
        travelTimeRules: _travelTimeRules,
        members: _orgMembers,
      );

      final issue = ShiftConflictIssue(
        shift: shift,
        conflictingShifts: conflictingShifts,
        blockingAbsences: blockingAbsences,
        conflictingDraftShifts: conflictingDraftShifts,
        violations: violations,
      );
      if (issue.hasConflicts) {
        issues.add(issue);
      }
    }

    return issues;
  }

  Future<List<ShiftAssigneeAvailability>> loadAssigneeAvailability({
    required List<AppUserProfile> members,
    required DateTime startTime,
    required DateTime endTime,
    double breakMinutes = 0,
    String? siteId,
    String? siteName,
    List<String> requiredQualificationIds = const [],
    String? shiftTitle,
    String? excludeShiftId,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null || members.isEmpty || !endTime.isAfter(startTime)) {
      return members
          .map((member) => ShiftAssigneeAvailability(member: member))
          .toList(growable: false);
    }

    final queryWindow = _buildShiftAvailabilityWindow(startTime, endTime);
    final candidateShifts = usesLocalStorage
        ? _localShifts.where((shift) {
            return shift.orgId == currentUser.orgId &&
                !shift.startTime.isBefore(queryWindow.start) &&
                shift.startTime.isBefore(queryWindow.end);
          }).toList(growable: false)
        : await _firestoreService.getShiftsInRange(
            orgId: currentUser.orgId,
            start: queryWindow.start,
            end: queryWindow.end,
          );
    final blockingAbsences = usesLocalStorage
        ? _localAbsenceRequests.where((request) {
            return request.orgId == currentUser.orgId &&
                request.status == AbsenceStatus.approved &&
                request.overlaps(startTime, endTime);
          }).toList(growable: false)
        : await _firestoreService.getApprovedAbsencesInRange(
            orgId: currentUser.orgId,
            start: startTime,
            end: endTime,
          );

    final suggestions = members.map((member) {
      final conflicts = candidateShifts
          .where((shift) =>
              shift.userId == member.uid &&
              shift.id != excludeShiftId &&
              shift.startTime.isBefore(endTime) &&
              shift.endTime.isAfter(startTime))
          .toList(growable: false);
      final absences = blockingAbsences
          .where((request) => request.userId == member.uid)
          .toList(growable: false);
      final draftShift = Shift(
        id: excludeShiftId,
        orgId: currentUser.orgId,
        userId: member.uid,
        employeeName: member.displayName,
        title: shiftTitle ?? 'Vorschau',
        startTime: startTime,
        endTime: endTime,
        breakMinutes: breakMinutes,
        siteId: siteId,
        siteName: siteName,
        location: siteName,
        requiredQualificationIds: requiredQualificationIds,
      );
      final violations = _complianceService.validateShift(
        shift: draftShift,
        existingShifts: candidateShifts
            .where((shift) => shift.userId == member.uid)
            .toList(growable: false),
        draftShifts: const [],
        absences: blockingAbsences
            .where((request) => request.userId == member.uid)
            .toList(growable: false),
        contracts: _contracts,
        siteAssignments: _siteAssignments,
        ruleSets: _effectiveRuleSets,
        travelTimeRules: _travelTimeRules,
        members: _orgMembers.isEmpty ? members : _orgMembers,
      );
      return ShiftAssigneeAvailability(
        member: member,
        conflictingShifts: conflicts,
        blockingAbsences: absences,
        violations: violations,
      );
    }).toList(growable: false)
      ..sort((a, b) {
        if (a.isAvailable != b.isAvailable) {
          return a.isAvailable ? -1 : 1;
        }
        if (a.hasWarnings != b.hasWarnings) {
          return a.hasWarnings ? 1 : -1;
        }
        return a.member.displayName.compareTo(b.member.displayName);
      });

    return suggestions;
  }

  Future<void> deleteShift(String shiftId) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) {
      return;
    }

    // Beschreibung der Schicht (Mitarbeiter/Datum) für ein aussagekräftiges
    // Protokoll vor dem Entfernen ermitteln.
    final auditSummary = 'Schicht gelöscht${_describeShift(shiftId)}';

    if (usesLocalStorage) {
      _localShifts.removeWhere((shift) => shift.id == shiftId);
      await DatabaseService.saveLocalShifts(
        _localShifts,
        scope: _localScope,
      );
      await _recordShiftTombstone(shiftId);
      _applyLocalState();
      notifyListeners();
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Schicht',
        entityId: shiftId,
        summary: auditSummary,
      );
      return;
    }

    try {
      await _firestoreService.deleteShift(
        orgId: currentUser.orgId,
        shiftId: shiftId,
      );
    } catch (error) {
      if (!usesHybridStorage) {
        rethrow;
      }
      // Hybrid offline: nicht hart werfen (CLAUDE.md-Mutator-Muster), sondern
      // lokal entfernen + Tombstone setzen; propagiert via syncLocalStateToCloud.
      _localShifts.removeWhere((shift) => shift.id == shiftId);
      await DatabaseService.saveLocalShifts(_localShifts, scope: _localScope);
      await _recordShiftTombstone(shiftId);
      _applyLocalState();
      _safeNotify();
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Schicht',
        entityId: shiftId,
        summary: auditSummary,
      );
      return;
    }
    if (_deletedShiftIds.remove(shiftId)) {
      await DatabaseService.saveTombstones(
        DatabaseService.shiftsCollection,
        _deletedShiftIds,
        scope: _localScope,
      );
    }
    _localShifts.removeWhere((shift) => shift.id == shiftId);
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Schicht',
      entityId: shiftId,
      summary: auditSummary,
    );
  }

  /// Liefert einen kurzen Zusatz „ (Mitarbeiter, TT.MM.JJJJ)" für eine bekannte
  /// Schicht – sonst einen leeren String. Nur aus in-memory-Listen, kein I/O.
  String _describeShift(String shiftId) {
    Shift? found;
    for (final shift in _shifts) {
      if (shift.id == shiftId) {
        found = shift;
        break;
      }
    }
    found ??= () {
      for (final shift in _localShifts) {
        if (shift.id == shiftId) {
          return shift;
        }
      }
      return null;
    }();
    if (found == null) {
      return '';
    }
    final start = found.startTime;
    final datum =
        '${start.day.toString().padLeft(2, '0')}.${start.month.toString().padLeft(2, '0')}.${start.year}';
    final name = found.employeeName.trim();
    return name.isEmpty ? ' ($datum)' : ' ($name, $datum)';
  }

  Future<void> publishShifts(
    Iterable<Shift> shifts, {
    ShiftStatus status = ShiftStatus.confirmed,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) {
      return;
    }

    final publishable =
        shifts.where((shift) => shift.status != status).toList(growable: false);
    if (publishable.isEmpty) {
      return;
    }

    if (usesLocalStorage) {
      var publishedCount = 0;
      for (final shift in publishable) {
        final index = _localShifts.indexWhere((item) => item.id == shift.id);
        if (index == -1) {
          continue;
        }
        _localShifts[index] = _localShifts[index].copyWith(status: status);
        publishedCount++;
      }
      if (publishedCount == 0) {
        return;
      }
      await DatabaseService.saveLocalShifts(
        _localShifts,
        scope: _localScope,
      );
      _applyLocalState();
      notifyListeners();
      _audit?.call(
        action: AuditAction.updated,
        entityType: 'Schicht',
        entityId: null,
        summary: publishedCount == 1
            ? '1 Schicht veröffentlicht'
            : '$publishedCount Schichten veröffentlicht',
      );
      return;
    }

    await _firestoreService.publishShiftBatch(
      orgId: currentUser.orgId,
      shifts: publishable
          .map((shift) => shift.copyWith(createdByUid: currentUser.uid))
          .toList(growable: false),
      status: status,
    );
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Schicht',
      entityId: null,
      summary: publishable.length == 1
          ? '1 Schicht veröffentlicht'
          : '${publishable.length} Schichten veröffentlicht',
    );
  }

  Future<void> deleteShiftSeries(String seriesId) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) {
      return;
    }

    if (usesLocalStorage) {
      final removedIds = _localShifts
          .where((shift) => shift.seriesId == seriesId)
          .map((shift) => shift.id)
          .whereType<String>()
          .toList(growable: false);
      _localShifts.removeWhere((shift) => shift.seriesId == seriesId);
      await DatabaseService.saveLocalShifts(
        _localShifts,
        scope: _localScope,
      );
      for (final id in removedIds) {
        await _recordShiftTombstone(id);
      }
      _applyLocalState();
      notifyListeners();
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Schicht',
        entityId: seriesId,
        summary: 'Schichtserie gelöscht',
      );
      return;
    }

    try {
      await _firestoreService.deleteShiftSeries(
        orgId: currentUser.orgId,
        seriesId: seriesId,
      );
    } catch (error) {
      if (!usesHybridStorage) {
        rethrow;
      }
      // Hybrid offline: ganze Serie lokal entfernen + je Schicht Tombstone.
      final removedIds = _localShifts
          .where((shift) => shift.seriesId == seriesId)
          .map((shift) => shift.id)
          .whereType<String>()
          .toList(growable: false);
      _localShifts.removeWhere((shift) => shift.seriesId == seriesId);
      await DatabaseService.saveLocalShifts(_localShifts, scope: _localScope);
      for (final id in removedIds) {
        await _recordShiftTombstone(id);
      }
      _applyLocalState();
      _safeNotify();
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Schicht',
        entityId: seriesId,
        summary: 'Schichtserie gelöscht',
      );
      return;
    }
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Schicht',
      entityId: seriesId,
      summary: 'Schichtserie gelöscht',
    );
  }

  Future<void> submitAbsenceRequest(AbsenceRequest request) async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return;
    }

    final existingRequest =
        request.id == null ? null : _findAbsenceRequestById(request.id!);
    var canManageApprovedVacation = false;
    if (request.id != null) {
      if (existingRequest == null) {
        throw StateError('Der Antrag konnte nicht mehr gefunden werden.');
      }
      canManageApprovedVacation =
          await _canCurrentUserManageApprovedVacation(existingRequest);
      if (!_canCurrentUserEditOwnAbsence(existingRequest) &&
          !canManageApprovedVacation) {
        throw StateError(
          'Nur eigene offene Antraege oder genehmigte Urlaube koennen bearbeitet werden.',
        );
      }
    }

    final requestWithContext = AbsenceRequest(
      id: existingRequest?.id ?? request.id,
      orgId: existingRequest?.orgId ?? currentUser.orgId,
      userId: existingRequest?.userId ?? currentUser.uid,
      employeeName: existingRequest?.employeeName ?? currentUser.displayName,
      startDate: request.startDate,
      endDate: request.endDate,
      type: canManageApprovedVacation ? existingRequest!.type : request.type,
      note: request.note?.trim().isEmpty ?? true ? null : request.note!.trim(),
      status: existingRequest?.status ?? AbsenceStatus.pending,
      reviewedByUid: existingRequest?.reviewedByUid,
      // M-U-Felder durchreichen (sonst gingen Halbtag/Stunden/Vertreter still
      // verloren); bei genehmigtem Urlaub bleibt die Antrags-„Form" gesperrt
      // wie der Typ, Metadaten (Vertreter/EAU) dürfen aktualisiert werden.
      halfDay: canManageApprovedVacation ? existingRequest!.halfDay : request.halfDay,
      halfDayPeriod: canManageApprovedVacation
          ? existingRequest!.halfDayPeriod
          : request.halfDayPeriod,
      hours: canManageApprovedVacation ? existingRequest!.hours : request.hours,
      vertreterUserIds: request.vertreterUserIds,
      eauAttached: request.eauAttached,
      createdAt: existingRequest?.createdAt,
      updatedAt: existingRequest?.updatedAt,
    );

    final auditSummary =
        'Abwesenheitsantrag ${requestWithContext.type.label} '
        '${_describeAbsenceRange(requestWithContext.startDate, requestWithContext.endDate)}';
    // Neuer Antrag (created) vs. Bearbeitung eines bestehenden (updated).
    final auditAction =
        existingRequest == null ? AuditAction.created : AuditAction.updated;

    if (usesLocalStorage) {
      final localRequest = requestWithContext.copyWith(
        id: requestWithContext.id ?? _nextLocalId('absence'),
      );
      _upsertLocalAbsenceRequest(localRequest);
      await _persistLocalAbsenceRequests();
      _applyLocalState();
      notifyListeners();
      _audit?.call(
        action: auditAction,
        entityType: 'Abwesenheit',
        entityId: localRequest.id,
        summary: auditSummary,
      );
      await _releaseShiftsForSickAbsence(localRequest);
      return;
    }

    try {
      await _firestoreService.saveAbsenceRequest(
        requestWithContext,
      );
    } catch (error) {
      if (!usesHybridStorage) {
        rethrow;
      }
      final localRequest = requestWithContext.copyWith(
        id: requestWithContext.id ?? _nextLocalId('absence'),
      );
      _upsertLocalAbsenceRequest(localRequest);
      await _persistLocalAbsenceRequests();
      _applyLocalState();
      _safeNotify();
      _audit?.call(
        action: auditAction,
        entityType: 'Abwesenheit',
        entityId: localRequest.id,
        summary: auditSummary,
      );
      await _releaseShiftsForSickAbsence(localRequest);
      return;
    }
    _audit?.call(
      action: auditAction,
      entityType: 'Abwesenheit',
      entityId: requestWithContext.id,
      summary: auditSummary,
    );
    await _releaseShiftsForSickAbsence(requestWithContext);
  }

  /// Trägt bei einer Krankmeldung (sickness/childSick) den betroffenen
  /// Mitarbeiter aus seinen überlappenden Schichten aus → Schicht wird „frei"
  /// (unbesetzt, Status `planned`), damit der Chef sie neu besetzen kann.
  /// Best-effort: ein Fehler hier darf die Abwesenheits-Speicherung nicht
  /// scheitern lassen. Greift für selbst gemeldete Krankheit (Mitarbeiter trägt
  /// sich via Self-Austragen-Regel selbst aus) ebenso wie für Chef-Meldungen.
  Future<void> _releaseShiftsForSickAbsence(AbsenceRequest absence) async {
    if (absence.type != AbsenceType.sickness &&
        absence.type != AbsenceType.childSick) {
      return;
    }
    if (absence.status == AbsenceStatus.rejected) {
      return;
    }
    final currentUser = _currentUser;
    if (currentUser == null) {
      return;
    }
    // Schichten schreiben darf nur die Schichtleitung. Freigeben erfolgt daher
    // durch eine Manager-Aktion: Chef meldet sich selbst krank ODER der Chef
    // genehmigt die Krankmeldung eines Mitarbeiters. Eine Selbst-Krankmeldung
    // eines Mitarbeiters gibt hier (noch) nichts frei.
    if (!currentUser.canManageShifts) {
      return;
    }

    bool affectsShift(Shift shift) =>
        shift.userId == absence.userId &&
        !shift.isUnassigned &&
        shift.status != ShiftStatus.completed &&
        shift.status != ShiftStatus.cancelled &&
        absence.overlaps(shift.startTime, shift.endTime);

    Shift freed(Shift shift) => shift.copyWith(
          userId: '',
          employeeName: '',
          status: ShiftStatus.planned,
          clearSwap: true,
        );

    if (usesLocalStorage) {
      var changed = 0;
      for (var i = 0; i < _localShifts.length; i++) {
        if (affectsShift(_localShifts[i])) {
          _localShifts[i] = freed(_localShifts[i]);
          changed++;
        }
      }
      if (changed > 0) {
        await _persistLocalShifts();
        _applyLocalState();
        _safeNotify();
        _audit?.call(
          action: AuditAction.updated,
          entityType: 'Schicht',
          summary: '$changed Schicht(en) wegen Krankmeldung freigegeben',
        );
      }
      return;
    }

    try {
      final rangeStart = DateTime(
        absence.startDate.year,
        absence.startDate.month,
        absence.startDate.day,
      );
      final rangeEnd = DateTime(
        absence.endDate.year,
        absence.endDate.month,
        absence.endDate.day + 1,
      );
      final affected = await _firestoreService.getShiftsInRange(
        orgId: currentUser.orgId,
        start: rangeStart,
        end: rangeEnd,
        userId: absence.userId,
      );
      var changed = 0;
      for (final shift in affected) {
        if (shift.id == null || !affectsShift(shift)) {
          continue;
        }
        await _firestoreService.releaseShiftAssignment(
          orgId: currentUser.orgId,
          shiftId: shift.id!,
        );
        changed++;
        if (usesHybridStorage) {
          final index = _localShifts.indexWhere((item) => item.id == shift.id);
          if (index == -1) {
            _localShifts.add(freed(shift));
          } else {
            _localShifts[index] = freed(shift);
          }
        }
      }
      if (changed > 0) {
        if (usesHybridStorage) {
          await _persistLocalShifts();
          _applyLocalState();
        }
        _safeNotify();
        _audit?.call(
          action: AuditAction.updated,
          entityType: 'Schicht',
          summary: '$changed Schicht(en) wegen Krankmeldung freigegeben',
        );
      }
    } catch (error) {
      AppLogger.warning(
        'ScheduleProvider: Schichten bei Krankmeldung freigeben fehlgeschlagen: $error',
      );
    }
  }

  /// Formatiert einen Abwesenheits-Zeitraum als „TT.MM.JJJJ–TT.MM.JJJJ" (bzw.
  /// nur ein Datum, wenn Start = Ende) für lesbare Protokolleinträge.
  String _describeAbsenceRange(DateTime start, DateTime end) {
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    final from = fmt(start);
    final to = fmt(end);
    return from == to ? from : '$from–$to';
  }

  Future<void> deleteAbsenceRequest(String requestId) async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return;
    }

    final request = _findAbsenceRequestById(requestId);
    if (request == null) {
      return;
    }
    final canManageApprovedVacation =
        await _canCurrentUserManageApprovedVacation(request);
    if (!_canCurrentUserEditOwnAbsence(request) && !canManageApprovedVacation) {
      throw StateError(
        'Nur eigene offene Antraege oder genehmigte Urlaube koennen geloescht werden.',
      );
    }

    if (usesLocalStorage) {
      _localAbsenceRequests.removeWhere((item) => item.id == requestId);
      await DatabaseService.saveLocalAbsenceRequests(
        _localAbsenceRequests,
        scope: _localScope,
      );
      await _recordAbsenceTombstone(requestId);
      _applyLocalState();
      notifyListeners();
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Abwesenheit',
        entityId: requestId,
        summary: 'Abwesenheitsantrag gelöscht',
      );
      return;
    }

    try {
      await _firestoreService.deleteAbsenceRequest(
        orgId: currentUser.orgId,
        requestId: requestId,
      );
    } catch (error) {
      if (!usesHybridStorage) {
        rethrow;
      }
      // Hybrid offline: lokal entfernen + Tombstone statt hart zu werfen.
      _localAbsenceRequests.removeWhere((item) => item.id == requestId);
      await DatabaseService.saveLocalAbsenceRequests(
        _localAbsenceRequests,
        scope: _localScope,
      );
      await _recordAbsenceTombstone(requestId);
      _applyLocalState();
      _safeNotify();
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Abwesenheit',
        entityId: requestId,
        summary: 'Abwesenheitsantrag gelöscht',
      );
      return;
    }
    if (_deletedAbsenceIds.remove(requestId)) {
      await DatabaseService.saveTombstones(
        DatabaseService.absenceRequestsCollection,
        _deletedAbsenceIds,
        scope: _localScope,
      );
    }
    _localAbsenceRequests.removeWhere((item) => item.id == requestId);
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Abwesenheit',
      entityId: requestId,
      summary: 'Abwesenheitsantrag gelöscht',
    );
  }

  Future<void> reviewAbsenceRequest({
    required String requestId,
    required AbsenceStatus status,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) {
      return;
    }

    final request = _findAbsenceRequestById(requestId);
    if (request == null) {
      return;
    }
    final canReview = await _canCurrentUserReviewAbsence(request);
    if (!canReview) {
      throw StateError(
        'Teamleiter koennen nur Mitarbeiter-Antraege freigeben. Eigene Antraege gehen an den Admin.',
      );
    }

    if (usesLocalStorage) {
      final index = _localAbsenceRequests
          .indexWhere((request) => request.id == requestId);
      if (index == -1) {
        return;
      }
      _localAbsenceRequests[index] = _localAbsenceRequests[index].copyWith(
        status: status,
        reviewedByUid: currentUser.uid,
      );
      await _persistLocalAbsenceRequests();
      _applyLocalState();
      notifyListeners();
      if (status == AbsenceStatus.approved) {
        await _releaseShiftsForSickAbsence(
          request.copyWith(status: AbsenceStatus.approved),
        );
      }
      return;
    }

    try {
      await _firestoreService.reviewAbsenceRequest(
        orgId: currentUser.orgId,
        requestId: requestId,
        status: status,
        reviewerUid: currentUser.uid,
      );
    } catch (error) {
      if (!usesHybridStorage) {
        rethrow;
      }
      final index =
          _localAbsenceRequests.indexWhere((item) => item.id == requestId);
      if (index == -1) {
        _upsertLocalAbsenceRequest(
          request.copyWith(
            status: status,
            reviewedByUid: currentUser.uid,
          ),
        );
      } else {
        _localAbsenceRequests[index] = _localAbsenceRequests[index].copyWith(
          status: status,
          reviewedByUid: currentUser.uid,
        );
      }
      await _persistLocalAbsenceRequests();
      _applyLocalState();
      _safeNotify();
    }
    if (status == AbsenceStatus.approved) {
      await _releaseShiftsForSickAbsence(
        request.copyWith(status: AbsenceStatus.approved),
      );
    }
  }

  AbsenceRequest? _findAbsenceRequestById(String requestId) {
    for (final request in _absenceRequests) {
      if (request.id == requestId) {
        return request;
      }
    }
    for (final request in _allAbsenceRequests) {
      if (request.id == requestId) {
        return request;
      }
    }
    for (final request in _localAbsenceRequests) {
      if (request.id == requestId) {
        return request;
      }
    }
    return null;
  }

  bool _canCurrentUserEditOwnAbsence(AbsenceRequest request) {
    final currentUser = _currentUser;
    return currentUser != null &&
        request.userId == currentUser.uid &&
        request.status == AbsenceStatus.pending;
  }

  Future<bool> _canCurrentUserManageApprovedVacation(
    AbsenceRequest request,
  ) async {
    final currentUser = _currentUser;
    if (currentUser == null ||
        !currentUser.canManageShifts ||
        request.type != AbsenceType.vacation ||
        request.status != AbsenceStatus.approved) {
      return false;
    }
    final requester = await _resolveRequesterProfile(request.userId);
    if (requester == null) {
      return currentUser.isAdmin && request.userId == currentUser.uid;
    }
    return currentUser.canManageApprovedVacationFor(requester);
  }

  Future<bool> _canCurrentUserReviewAbsence(AbsenceRequest request) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) {
      return false;
    }
    if (currentUser.isAdmin) {
      return true;
    }
    final requester = await _resolveRequesterProfile(request.userId);
    if (requester == null) {
      return false;
    }
    return currentUser.canReviewAbsenceRequestFor(requester);
  }

  Future<AppUserProfile?> _resolveRequesterProfile(String uid) async {
    final currentUser = _currentUser;
    if (currentUser?.uid == uid) {
      return currentUser;
    }
    for (final member in _orgMembers) {
      if (member.uid == uid) {
        return member;
      }
    }
    if (usesLocalStorage) {
      return null;
    }
    return _firestoreService.getUserProfile(uid);
  }

  /// Berechnet die verbrauchten Urlaubstage (genehmigte Urlaubsantraege) im
  /// aktuellen sichtbaren Jahr anhand der lokal vorhandenen Abwesenheitsliste.
  int get usedVacationDaysThisYear {
    final year = DateTime.now().year;
    final currentUser = _currentUser;
    if (currentUser == null) {
      return 0;
    }
    final relevantRequests =
        (usesLocalStorage ? _localAbsenceRequests : _allAbsenceRequests)
            .where((request) => request.userId == currentUser.uid)
            .toList(growable: false);
    return _countVacationDays(
      relevantRequests,
      year,
    );
  }

  static int _countVacationDays(List<AbsenceRequest> requests, int year) {
    int total = 0;
    for (final request in requests) {
      if (request.type != AbsenceType.vacation ||
          request.status != AbsenceStatus.approved) {
        continue;
      }
      final start = request.startDate.isBefore(DateTime(year))
          ? DateTime(year)
          : request.startDate;
      final end = request.endDate.isAfter(DateTime(year, 12, 31))
          ? DateTime(year, 12, 31)
          : request.endDate;
      if (end.isBefore(start)) continue;
      for (var day = DateTime(start.year, start.month, start.day);
          !day.isAfter(end);
          day = day.add(const Duration(days: 1))) {
        if (day.weekday <= DateTime.friday) {
          total += 1;
        }
      }
    }
    return total;
  }

  List<Shift> upcomingShiftsForCurrentUser() {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return const [];
    }
    final now = DateTime.now();
    return _shifts
        .where((shift) =>
            shift.userId == currentUser.uid && shift.endTime.isAfter(now))
        .toList(growable: false);
  }

  /// Klont eine Schicht für Kopier-Operationen auf ein neues Zeitfenster und
  /// behält fachlich relevante Felder – inkl. [siteId]/[siteName] und
  /// [requiredQualificationIds], die für neue Schichten Pflicht bzw. wichtig
  /// sind. Bewusst eine frische [Shift] statt copyWith, damit kein altes
  /// id/seriesId mitgeschleppt wird; Status wird auf geplant zurückgesetzt.
  Shift _cloneShiftForCopy(
    Shift source, {
    required DateTime startTime,
    required DateTime endTime,
    required String createdByUid,
  }) {
    return Shift(
      orgId: source.orgId,
      userId: source.userId,
      employeeName: source.employeeName,
      title: source.title,
      startTime: startTime,
      endTime: endTime,
      breakMinutes: source.breakMinutes,
      teamId: source.teamId,
      team: source.team,
      siteId: source.siteId,
      siteName: source.siteName,
      location: source.location,
      requiredQualificationIds: source.requiredQualificationIds,
      notes: source.notes,
      color: source.color,
      status: ShiftStatus.planned,
      createdByUid: createdByUid,
    );
  }

  /// Kopiert eine oder mehrere Schichten auf beliebige Zieltage
  /// (wochentagsunabhängig). Jede (Quell-Schicht × Zieltag)-Kombination wird
  /// auf den jeweiligen Tag rebased – Uhrzeit und Dauer bleiben erhalten, auch
  /// über Mitternacht. Der Tag, an dem eine Quelle bereits liegt, wird
  /// übersprungen (kein triviales Duplikat). Alle Kopien teilen eine
  /// gemeinsame seriesId und werden in EINEM [saveShifts]-Aufruf geschrieben
  /// (Validierung/Chunking/Audit inklusive).
  Future<void> copyShiftsToDays(
    List<Shift> sourceShifts,
    List<DateTime> targetDays,
  ) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) return;
    if (sourceShifts.isEmpty || targetDays.isEmpty) return;

    final normalizedDays = <DateTime>{
      for (final day in targetDays) DateTime(day.year, day.month, day.day),
    };

    final copies = <Shift>[];
    for (final source in sourceShifts) {
      final sourceDay = DateTime(
        source.startTime.year,
        source.startTime.month,
        source.startTime.day,
      );
      final duration = source.endTime.difference(source.startTime);
      for (final day in normalizedDays) {
        if (day == sourceDay) {
          continue;
        }
        final newStart = DateTime(
          day.year,
          day.month,
          day.day,
          source.startTime.hour,
          source.startTime.minute,
        );
        copies.add(
          _cloneShiftForCopy(
            source,
            startTime: newStart,
            endTime: newStart.add(duration),
            createdByUid: currentUser.uid,
          ),
        );
      }
    }

    if (copies.isEmpty) return;

    await saveShifts(copies, seriesId: newSeriesId());
  }

  /// Kopiert EINE Schicht auf genau einen Zieltag (Drag & Drop), optional an
  /// einen anderen Mitarbeiter zugewiesen. Anders als [copyShiftsToDays] wird
  /// der Quelltag NICHT übersprungen – ein Drop auf denselben Tag, aber eine
  /// andere Mitarbeiter-Zeile, ist eine gültige Kopie. Baut eine frische
  /// Schicht (id == null) → es wird kopiert, nicht die Quelle überschrieben.
  Future<void> copyShiftToDay(
    Shift source,
    DateTime targetDay, {
    String? reassignUserId,
    String? reassignEmployeeName,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) return;

    final duration = source.endTime.difference(source.startTime);
    final newStart = DateTime(
      targetDay.year,
      targetDay.month,
      targetDay.day,
      source.startTime.hour,
      source.startTime.minute,
    );
    var clone = _cloneShiftForCopy(
      source,
      startTime: newStart,
      endTime: newStart.add(duration),
      createdByUid: currentUser.uid,
    );
    if (reassignUserId != null && reassignUserId.isNotEmpty) {
      clone = clone.copyWith(
        userId: reassignUserId,
        employeeName: reassignEmployeeName ?? clone.employeeName,
      );
    }
    await saveShifts([clone]);
  }

  /// Kopiert eine Schicht auf beliebige Zieltage UND beliebige Ziel-Mitarbeiter
  /// (Kreuzprodukt Mitarbeiter × Tage). Uhrzeit/Dauer bleiben erhalten. Die
  /// exakte Ursprungskombination (gleicher Tag + gleicher Mitarbeiter) wird
  /// übersprungen, sonst entstünde ein 1:1-Duplikat. Alle Kopien teilen eine
  /// gemeinsame seriesId und gehen in EINEM [saveShifts]-Aufruf raus.
  Future<void> copyShiftToAssignees(
    Shift source,
    List<DateTime> targetDays,
    List<AppUserProfile> assignees,
  ) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) return;
    if (targetDays.isEmpty || assignees.isEmpty) return;

    final normalizedDays = <DateTime>{
      for (final day in targetDays) DateTime(day.year, day.month, day.day),
    };
    final sourceDay = DateTime(
      source.startTime.year,
      source.startTime.month,
      source.startTime.day,
    );
    final duration = source.endTime.difference(source.startTime);

    final copies = <Shift>[];
    for (final assignee in assignees) {
      for (final day in normalizedDays) {
        if (day == sourceDay && assignee.uid == source.userId) {
          continue;
        }
        final newStart = DateTime(
          day.year,
          day.month,
          day.day,
          source.startTime.hour,
          source.startTime.minute,
        );
        final clone = _cloneShiftForCopy(
          source,
          startTime: newStart,
          endTime: newStart.add(duration),
          createdByUid: currentUser.uid,
        ).copyWith(
          userId: assignee.uid,
          employeeName: assignee.displayName,
        );
        copies.add(clone);
      }
    }

    if (copies.isEmpty) return;
    await saveShifts(copies, seriesId: newSeriesId());
  }

  Future<void> copyWeekShifts({
    required DateTime sourceWeekStart,
    required DateTime targetWeekStart,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) return;

    final dayOffset = targetWeekStart.difference(sourceWeekStart);
    final sourceShifts = usesLocalStorage
        ? _localShifts.where((s) {
            final start = sourceWeekStart;
            final end = sourceWeekStart.add(const Duration(days: 7));
            return !s.startTime.isBefore(start) && s.startTime.isBefore(end);
          }).toList()
        : _shifts.where((s) {
            final start = sourceWeekStart;
            final end = sourceWeekStart.add(const Duration(days: 7));
            return !s.startTime.isBefore(start) && s.startTime.isBefore(end);
          }).toList();

    if (sourceShifts.isEmpty) {
      throw StateError('Keine Schichten in der Quellwoche gefunden.');
    }

    final filteredSourceShifts = _filterShifts(
      sourceShifts,
      includeStatusFilter: false,
    );
    if (filteredSourceShifts.isEmpty) {
      throw StateError('Keine Schichten fuer den aktuellen Filter gefunden.');
    }

    final copiedShifts = filteredSourceShifts
        .map((s) => _cloneShiftForCopy(
              s,
              startTime: s.startTime.add(dayOffset),
              endTime: s.endTime.add(dayOffset),
              createdByUid: currentUser.uid,
            ))
        .toList(growable: false);

    await saveShifts(copiedShifts);
  }

  Future<void> requestShiftSwap(String shiftId) async {
    final currentUser = _currentUser;
    if (currentUser == null) return;

    if (usesLocalStorage) {
      final index = _localShifts.indexWhere((s) => s.id == shiftId);
      if (index == -1) return;
      _localShifts[index] = _localShifts[index].copyWith(
        swapRequestedByUid: currentUser.uid,
        swapStatus: 'pending',
      );
      await DatabaseService.saveLocalShifts(
        _localShifts,
        scope: _localScope,
      );
      _applyLocalState();
      notifyListeners();
      _audit?.call(
        action: AuditAction.updated,
        entityType: 'Schicht',
        entityId: shiftId,
        summary: 'Schichttausch angefragt',
      );
      return;
    }

    await _firestoreService.updateShiftSwapRequest(
      orgId: currentUser.orgId,
      shiftId: shiftId,
      requestedByUid: currentUser.uid,
    );
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Schicht',
      entityId: shiftId,
      summary: 'Schichttausch angefragt',
    );
  }

  /// Markiert eine Schicht als erledigt, wenn ein Arbeitszeiteintrag mit
  /// [sourceShiftId] gespeichert wurde. Wird vom WorkProvider aufgerufen.
  Future<void> completeShiftForEntry(String sourceShiftId) async {
    final currentUser = _currentUser;
    if (currentUser == null) return;

    if (usesLocalStorage) {
      final index =
          _localShifts.indexWhere((shift) => shift.id == sourceShiftId);
      if (index == -1) return;
      final shift = _localShifts[index];
      if (shift.status == ShiftStatus.completed ||
          shift.status == ShiftStatus.cancelled) {
        return;
      }
      _localShifts[index] = shift.copyWith(status: ShiftStatus.completed);
      await DatabaseService.saveLocalShifts(
        _localShifts,
        scope: _localScope,
      );
      _applyLocalState();
      _safeNotify();
      return;
    }

    await _firestoreService.updateShiftStatus(
      orgId: currentUser.orgId,
      shiftId: sourceShiftId,
      status: ShiftStatus.completed,
    );
  }

  Future<void> reviewShiftSwap({
    required String shiftId,
    required bool approved,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) return;

    if (usesLocalStorage) {
      final index = _localShifts.indexWhere((s) => s.id == shiftId);
      if (index == -1) return;
      _localShifts[index] = _localShifts[index].copyWith(
        swapStatus: approved ? 'approved' : 'rejected',
      );
      await DatabaseService.saveLocalShifts(
        _localShifts,
        scope: _localScope,
      );
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.reviewShiftSwap(
      orgId: currentUser.orgId,
      shiftId: shiftId,
      approved: approved,
    );
  }

  // ===========================================================================
  // Schichttausch (neue Tauschanfragen, eigene Collection `shiftSwapRequests`)
  // ===========================================================================

  String? _memberName(String uid) {
    for (final member in _orgMembers) {
      if (member.uid == uid) {
        return member.displayName;
      }
    }
    return null;
  }

  Future<Shift?> _resolveShiftById(String shiftId) async {
    if (shiftId.isEmpty) {
      return null;
    }
    for (final shift in _shifts) {
      if (shift.id == shiftId) {
        return shift;
      }
    }
    for (final shift in _localShifts) {
      if (shift.id == shiftId) {
        return shift;
      }
    }
    final currentUser = _currentUser;
    if (usesLocalStorage || currentUser == null) {
      return null;
    }
    return _firestoreService.getShiftById(
      orgId: currentUser.orgId,
      shiftId: shiftId,
    );
  }

  /// Org-weite, besetzte Schichten anderer Mitarbeiter im Zeitraum – Kandidaten
  /// für die Tausch-Auswahl. Setzt die geöffnete `shifts`-Lese-Regel voraus
  /// (jeder mit `canViewSchedule` darf org-weit lesen).
  Future<List<Shift>> getSwappableShiftsInRange(
    DateTime start,
    DateTime end,
  ) async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return const [];
    }
    final List<Shift> all;
    if (usesLocalStorage) {
      all = _localShifts
          .where((shift) =>
              shift.orgId == currentUser.orgId &&
              !shift.startTime.isBefore(start) &&
              shift.startTime.isBefore(end))
          .toList();
    } else {
      all = await _firestoreService.getShiftsInRange(
        orgId: currentUser.orgId,
        start: start,
        end: end,
      );
    }
    return all
        .where((shift) =>
            !shift.isUnassigned &&
            shift.userId != currentUser.uid &&
            shift.status != ShiftStatus.cancelled &&
            shift.status != ShiftStatus.completed)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  /// **Antragsteller** stellt eine Tauschanfrage. `request` trägt die Auswahl
  /// (eigene Schicht, Kollegenschicht bzw. Übernahme, Notiz); Identität,
  /// Status und die Snapshot-Felder werden hier vertrauenswürdig (re)gesetzt.
  Future<void> submitShiftSwapRequest(ShiftSwapRequest request) async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return;
    }

    final requesterShift = await _resolveShiftById(request.requesterShiftId);
    if (requesterShift == null) {
      throw StateError('Die eigene Schicht wurde nicht gefunden.');
    }
    if (requesterShift.userId != currentUser.uid) {
      throw StateError(
        'Es können nur eigene Schichten zum Tausch angeboten werden.',
      );
    }

    Shift? targetShift;
    if (request.kind == SwapKind.exchange) {
      final targetShiftId = request.targetShiftId;
      if (targetShiftId == null || targetShiftId.isEmpty) {
        throw StateError(
          'Für einen Tausch muss eine Schicht des Kollegen gewählt werden.',
        );
      }
      targetShift = await _resolveShiftById(targetShiftId);
      if (targetShift == null) {
        throw StateError('Die Schicht des Kollegen wurde nicht gefunden.');
      }
    }

    final targetUid = request.kind == SwapKind.exchange
        ? targetShift!.userId
        : request.targetUid;
    if (targetUid.isEmpty || targetUid == currentUser.uid) {
      throw StateError(
        'Bitte einen anderen Mitarbeiter als Tauschpartner wählen.',
      );
    }
    final targetName = _memberName(targetUid) ??
        (targetShift?.employeeName.trim().isNotEmpty == true
            ? targetShift!.employeeName
            : request.targetName);

    final prepared = ShiftSwapRequest(
      orgId: currentUser.orgId,
      requesterUid: currentUser.uid,
      requesterName: currentUser.displayName,
      requesterShiftId: requesterShift.id!,
      targetUid: targetUid,
      targetName: targetName,
      targetShiftId: request.kind == SwapKind.exchange ? targetShift!.id : null,
      kind: request.kind,
      status: SwapStatus.pending,
      note: (request.note?.trim().isEmpty ?? true) ? null : request.note!.trim(),
      requesterShiftStart: requesterShift.startTime,
      targetShiftStart: targetShift?.startTime,
      requesterShiftLabel: _swapShiftLabel(requesterShift),
      targetShiftLabel:
          targetShift == null ? null : _swapShiftLabel(targetShift),
    );

    await _writeSwapRequest(
      prepared,
      action: AuditAction.created,
      summary: 'Tauschanfrage an $targetName gesendet',
    );
  }

  /// **Kollege** nimmt eine an ihn gerichtete, offene Anfrage an oder ab.
  /// Hier wird KEINE Schicht umgebucht – das macht erst der Chef beim Bestätigen.
  Future<void> respondToShiftSwapRequest({
    required String requestId,
    required bool accept,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return;
    }
    final request = _findSwapRequestById(requestId);
    if (request == null) {
      throw StateError('Die Tauschanfrage wurde nicht gefunden.');
    }
    if (request.targetUid != currentUser.uid) {
      throw StateError(
        'Nur der angefragte Kollege kann annehmen oder ablehnen.',
      );
    }
    if (request.status != SwapStatus.pending) {
      throw StateError('Diese Anfrage ist nicht mehr offen.');
    }
    await _updateSwapRequestState(
      request.copyWith(
        status: accept
            ? SwapStatus.acceptedByColleague
            : SwapStatus.declinedByColleague,
      ),
      summary: accept
          ? 'Tauschanfrage von ${request.requesterName} angenommen'
          : 'Tauschanfrage von ${request.requesterName} abgelehnt',
    );
  }

  /// **Antragsteller** zieht seine Anfrage zurück (solange noch nicht bestätigt).
  Future<void> cancelShiftSwapRequest(String requestId) async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return;
    }
    final request = _findSwapRequestById(requestId);
    if (request == null) {
      return;
    }
    if (request.requesterUid != currentUser.uid) {
      throw StateError('Nur der Antragsteller kann die Anfrage zurückziehen.');
    }
    if (request.status != SwapStatus.pending &&
        request.status != SwapStatus.acceptedByColleague) {
      throw StateError('Diese Anfrage kann nicht mehr zurückgezogen werden.');
    }
    await _updateSwapRequestState(
      request.copyWith(status: SwapStatus.cancelled),
      summary: 'Tauschanfrage zurückgezogen',
    );
  }

  /// **Chef** lehnt eine vom Kollegen angenommene Anfrage ab.
  Future<void> rejectShiftSwapRequest(String requestId) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) {
      return;
    }
    final request = _findSwapRequestById(requestId);
    if (request == null) {
      return;
    }
    if (request.status != SwapStatus.acceptedByColleague) {
      throw StateError(
        'Nur vom Kollegen angenommene Anfragen können hier abgelehnt werden.',
      );
    }
    await _updateSwapRequestState(
      request.copyWith(
        status: SwapStatus.rejectedByManager,
        reviewedByUid: currentUser.uid,
      ),
      summary:
          'Schichttausch abgelehnt: ${request.requesterName} ↔ ${request.targetName}',
      reviewerUid: currentUser.uid,
    );
  }

  /// Vorschau der Compliance-Verstöße, die die Umbuchung beim Empfänger
  /// auslösen würde (für die Chef-Bestätigung). Leere Liste = unkritisch.
  Future<List<ShiftConflictIssue>> previewSwapCompliance(
    String requestId,
  ) async {
    final request = _findSwapRequestById(requestId);
    if (request == null) {
      return const [];
    }
    final swapped = await _buildSwappedShifts(request);
    if (swapped.isEmpty) {
      return const [];
    }
    return validateShifts(swapped);
  }

  /// **Chef** bestätigt und vollzieht den Tausch: beide Schichten werden
  /// umgebucht (`userId`/`employeeName`), bei Übernahme entsteht eine
  /// Gutschrift, und der Status wird NACH erfolgreicher Umbuchung auf
  /// `confirmed` gesetzt. Ohne [overrideCompliance] wirft die Umbuchung bei
  /// Regelverstößen (ShiftConflict/ComplianceRejected) – der Chef kann dann mit
  /// `overrideCompliance: true` erneut bestätigen (Direkt-Write, Bypass).
  Future<void> confirmShiftSwapRequest({
    required String requestId,
    bool overrideCompliance = false,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) {
      throw StateError('Nur die Schichtleitung kann einen Tausch bestätigen.');
    }
    final request = _findSwapRequestById(requestId);
    if (request == null) {
      throw StateError('Die Tauschanfrage wurde nicht gefunden.');
    }
    if (request.status != SwapStatus.acceptedByColleague) {
      throw StateError(
        'Der Tausch kann erst nach Annahme durch den Kollegen bestätigt werden.',
      );
    }

    final swapped = await _buildSwappedShifts(request);
    if (swapped.isEmpty) {
      throw StateError('Die betroffenen Schichten wurden nicht gefunden.');
    }

    // Umbuchung – wirft bei Regelverstoß, sofern nicht übersteuert.
    await saveShifts(swapped, skipCompliance: overrideCompliance);

    if (request.isGiveAway) {
      await _createSwapCredit(request);
    }

    await _updateSwapRequestState(
      request.copyWith(
        status: SwapStatus.confirmed,
        reviewedByUid: currentUser.uid,
        overriddenCompliance: overrideCompliance,
      ),
      summary: 'Schichttausch durchgeführt: ${request.requesterName} ↔ '
          '${request.targetName}'
          '${overrideCompliance ? ' (Regelverstoß übersteuert)' : ''}',
      reviewerUid: currentUser.uid,
      overriddenCompliance: overrideCompliance,
    );
  }

  /// Baut die umgebuchten Schicht-Kopien (`userId`/`employeeName` getauscht).
  /// Bei Übernahme wandert nur die Antragsteller-Schicht.
  Future<List<Shift>> _buildSwappedShifts(ShiftSwapRequest request) async {
    final requesterShift = await _resolveShiftById(request.requesterShiftId);
    if (requesterShift == null) {
      return const [];
    }
    final targetName = _memberName(request.targetUid) ?? request.targetName;
    final requesterName =
        _memberName(request.requesterUid) ?? request.requesterName;

    final newRequesterShift = requesterShift.copyWith(
      userId: request.targetUid,
      employeeName: targetName,
    );

    if (request.isGiveAway || request.targetShiftId == null) {
      return [newRequesterShift];
    }

    final targetShift = await _resolveShiftById(request.targetShiftId!);
    if (targetShift == null) {
      return const [];
    }
    final newTargetShift = targetShift.copyWith(
      userId: request.requesterUid,
      employeeName: requesterName,
    );
    return [newRequesterShift, newTargetShift];
  }

  Future<void> _createSwapCredit(ShiftSwapRequest request) async {
    final credit = SwapCredit(
      // Deterministische Doc-ID aus der Anfrage -> Retries (Umbuchung erfolgte,
      // Gutschrift-Write schlug fehl) erzeugen kein Duplikat.
      id: request.id == null ? null : 'credit-${request.id}',
      orgId: request.orgId,
      // Der Kollege (target) hat die Schicht zusätzlich übernommen -> ihm wird
      // eine Schicht geschuldet. Der Antragsteller (requester) ist Schuldner.
      creditorUid: request.targetUid,
      creditorName: _memberName(request.targetUid) ?? request.targetName,
      debtorUid: request.requesterUid,
      debtorName: _memberName(request.requesterUid) ?? request.requesterName,
      originSwapRequestId: request.id ?? '',
      originShiftStart: request.requesterShiftStart,
      originShiftLabel: request.requesterShiftLabel,
      status: SwapCreditStatus.open,
    );
    await _writeSwapCredit(
      credit,
      action: AuditAction.created,
      summary: 'Gutschrift angelegt: ${credit.debtorName} → ${credit.creditorName}',
    );
  }

  /// Markiert eine offene Gutschrift als eingelöst. Erlaubt für die
  /// Schichtleitung **und** die beteiligten Mitarbeiter (Gläubiger/Schuldner).
  Future<void> settleSwapCredit(
    String creditId, {
    String? settledBySwapRequestId,
    String? note,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return;
    }
    final credit = _findSwapCreditById(creditId);
    if (credit == null) {
      throw StateError('Die Gutschrift wurde nicht gefunden.');
    }
    final involved = credit.creditorUid == currentUser.uid ||
        credit.debtorUid == currentUser.uid;
    if (!currentUser.canManageShifts && !involved) {
      throw StateError(
        'Nur Beteiligte oder die Schichtleitung können Gutschriften einlösen.',
      );
    }
    if (!credit.isOpen) {
      return;
    }
    await _writeSwapCredit(
      credit.copyWith(
        status: SwapCreditStatus.settled,
        settledAt: DateTime.now(),
        settledBySwapRequestId: settledBySwapRequestId,
        note: (note?.trim().isEmpty ?? true) ? null : note!.trim(),
      ),
      action: AuditAction.updated,
      summary:
          'Gutschrift eingelöst: ${credit.debtorName} → ${credit.creditorName}',
    );
  }

  /// **Chef** storniert eine offene Gutschrift (z.B. doppelt erfasst).
  Future<void> cancelSwapCredit(String creditId) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) {
      return;
    }
    final credit = _findSwapCreditById(creditId);
    if (credit == null || !credit.isOpen) {
      return;
    }
    await _writeSwapCredit(
      credit.copyWith(status: SwapCreditStatus.cancelled),
      action: AuditAction.updated,
      summary: 'Gutschrift storniert',
    );
  }

  Future<void> _writeSwapRequest(
    ShiftSwapRequest request, {
    required AuditAction action,
    required String summary,
  }) async {
    if (usesLocalStorage) {
      final local = request.copyWith(id: request.id ?? _nextLocalId('swap'));
      _upsertLocalSwapRequest(local);
      await _persistLocalSwapRequests();
      _applyLocalState();
      notifyListeners();
      _audit?.call(
        action: action,
        entityType: 'Schichttausch',
        entityId: local.id,
        summary: summary,
      );
      return;
    }
    try {
      await _firestoreService.saveSwapRequest(request);
    } catch (error) {
      if (!usesHybridStorage) {
        rethrow;
      }
      final local = request.copyWith(id: request.id ?? _nextLocalId('swap'));
      _upsertLocalSwapRequest(local);
      await _persistLocalSwapRequests();
      _applyLocalState();
      _safeNotify();
      _audit?.call(
        action: action,
        entityType: 'Schichttausch',
        entityId: local.id,
        summary: summary,
      );
      return;
    }
    _audit?.call(
      action: action,
      entityType: 'Schichttausch',
      entityId: request.id,
      summary: summary,
    );
  }

  Future<void> _updateSwapRequestState(
    ShiftSwapRequest updated, {
    required String summary,
    String? reviewerUid,
    bool? overriddenCompliance,
  }) async {
    final requestId = updated.id;
    if (requestId == null) {
      return;
    }
    if (usesLocalStorage) {
      _upsertLocalSwapRequest(updated);
      await _persistLocalSwapRequests();
      _applyLocalState();
      notifyListeners();
      _audit?.call(
        action: AuditAction.updated,
        entityType: 'Schichttausch',
        entityId: requestId,
        summary: summary,
      );
      return;
    }
    try {
      await _firestoreService.updateSwapRequestStatus(
        orgId: updated.orgId,
        requestId: requestId,
        status: updated.status,
        reviewerUid: reviewerUid,
        overriddenCompliance: overriddenCompliance,
      );
    } catch (error) {
      if (!usesHybridStorage) {
        rethrow;
      }
      _upsertLocalSwapRequest(updated);
      await _persistLocalSwapRequests();
      _applyLocalState();
      _safeNotify();
      _audit?.call(
        action: AuditAction.updated,
        entityType: 'Schichttausch',
        entityId: requestId,
        summary: summary,
      );
      return;
    }
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Schichttausch',
      entityId: requestId,
      summary: summary,
    );
  }

  Future<void> _writeSwapCredit(
    SwapCredit credit, {
    required AuditAction action,
    required String summary,
  }) async {
    if (usesLocalStorage) {
      final local = credit.copyWith(id: credit.id ?? _nextLocalId('credit'));
      _upsertLocalSwapCredit(local);
      await _persistLocalSwapCredits();
      _applyLocalState();
      notifyListeners();
      _audit?.call(
        action: action,
        entityType: 'Gutschrift',
        entityId: local.id,
        summary: summary,
      );
      return;
    }
    try {
      await _firestoreService.saveSwapCredit(credit);
    } catch (error) {
      if (!usesHybridStorage) {
        rethrow;
      }
      final local = credit.copyWith(id: credit.id ?? _nextLocalId('credit'));
      _upsertLocalSwapCredit(local);
      await _persistLocalSwapCredits();
      _applyLocalState();
      _safeNotify();
      _audit?.call(
        action: action,
        entityType: 'Gutschrift',
        entityId: local.id,
        summary: summary,
      );
      return;
    }
    _audit?.call(
      action: action,
      entityType: 'Gutschrift',
      entityId: credit.id,
      summary: summary,
    );
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> cacheCloudStateLocally() async {
    final currentUser = _currentUser;
    if (currentUser == null || usesLocalStorage) {
      return;
    }

    final filterUserId = currentUser.canManageShifts ? null : currentUser.uid;
    _localShifts = [
      ..._withoutTombstoned(
        await _firestoreService.getAllShifts(
          orgId: currentUser.orgId,
          userId: filterUserId,
        ),
        (shift) => shift.id,
        _deletedShiftIds,
      ),
    ];
    _localShiftTemplates = currentUser.canManageShifts
        ? [
            ...await _firestoreService.getShiftTemplates(
              orgId: currentUser.orgId,
              userId: currentUser.uid,
            ),
          ]
        : <ShiftTemplate>[];
    _localAbsenceRequests = [
      ..._withoutTombstoned(
        await _firestoreService.getAllAbsenceRequests(
          orgId: currentUser.orgId,
          userId: filterUserId,
        ),
        (request) => request.id,
        _deletedAbsenceIds,
      ),
    ];
    await DatabaseService.saveLocalShifts(
      _localShifts,
      scope: _localScope,
    );
    await DatabaseService.saveLocalShiftTemplates(
      _localShiftTemplates,
      scope: _localScope,
    );
    await DatabaseService.saveLocalAbsenceRequests(
      _localAbsenceRequests,
      scope: _localScope,
    );
  }

  Future<void> syncLocalStateToCloud() async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return;
    }

    if (currentUser.canManageShifts) {
      final shifts = _localShifts
          .where((shift) => shift.orgId == currentUser.orgId)
          .toList(growable: false);
      if (shifts.isNotEmpty) {
        try {
          await _firestoreService.saveShiftBatch(shifts);
        } catch (error) {
          AppLogger.warning('syncLocalStateToCloud(schedule): Schichten konnten '
              'nicht geschrieben werden: $error');
        }
      }

      // Lokal geloeschte Schichten in die Cloud propagieren, Tombstones aufloesen.
      if (_deletedShiftIds.isNotEmpty) {
        final propagated = <String>{};
        for (final id in _deletedShiftIds) {
          try {
            await _firestoreService.deleteShift(
              orgId: currentUser.orgId,
              shiftId: id,
            );
            propagated.add(id);
          } catch (error) {
            AppLogger.warning('syncLocalStateToCloud(schedule): Loeschung von '
                'Schicht $id konnte nicht propagiert werden: $error');
          }
        }
        if (propagated.isNotEmpty) {
          _deletedShiftIds.removeAll(propagated);
          await DatabaseService.saveTombstones(
            DatabaseService.shiftsCollection,
            _deletedShiftIds,
            scope: _localScope,
          );
        }
      }

      for (final template in _localShiftTemplates.where(
        (item) => item.orgId == currentUser.orgId,
      )) {
        try {
          await _firestoreService.saveShiftTemplate(template);
        } catch (error) {
          AppLogger.warning('syncLocalStateToCloud(schedule): Schichtvorlage '
              'konnte nicht geschrieben werden: $error');
        }
      }
    }

    for (final request in _localAbsenceRequests.where(
      (item) =>
          item.orgId == currentUser.orgId && item.userId == currentUser.uid,
    )) {
      try {
        await _firestoreService.saveAbsenceRequest(request);
      } catch (error) {
        AppLogger.warning('syncLocalStateToCloud(schedule): Abwesenheitsantrag '
            'konnte nicht geschrieben werden: $error');
      }
    }

    // Lokal geloeschte Abwesenheiten in die Cloud propagieren, Tombstones loesen.
    if (_deletedAbsenceIds.isNotEmpty) {
      final propagated = <String>{};
      for (final id in _deletedAbsenceIds) {
        try {
          await _firestoreService.deleteAbsenceRequest(
            orgId: currentUser.orgId,
            requestId: id,
          );
          propagated.add(id);
        } catch (error) {
          AppLogger.warning('syncLocalStateToCloud(schedule): Loeschung von '
              'Abwesenheit $id konnte nicht propagiert werden: $error');
        }
      }
      if (propagated.isNotEmpty) {
        _deletedAbsenceIds.removeAll(propagated);
        await DatabaseService.saveTombstones(
          DatabaseService.absenceRequestsCollection,
          _deletedAbsenceIds,
          scope: _localScope,
        );
      }
    }
  }

  Future<void> _restartSubscriptions() async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      _loading = false;
      _safeNotify();
      return;
    }

    if (usesLocalStorage) {
      if (_localShifts.isEmpty && _localAbsenceRequests.isEmpty) {
        await _loadLocalState();
      } else {
        _applyLocalState();
        _safeNotify();
      }
      return;
    }

    _loading = true;
    _safeNotify();

    final oldShiftsSub = _shiftsSubscription;
    final oldAbsenceSub = _absenceSubscription;
    final oldAllAbsenceSub = _allAbsenceSubscription;
    final oldTemplatesSub = _templatesSubscription;
    final oldAllSwapSub = _allSwapSubscription;
    final oldSwapIncomingSub = _swapIncomingSubscription;
    final oldSwapOutgoingSub = _swapOutgoingSubscription;
    final oldAllSwapCreditSub = _allSwapCreditSubscription;
    final oldSwapCreditCreditorSub = _swapCreditAsCreditorSubscription;
    final oldSwapCreditDebtorSub = _swapCreditAsDebtorSubscription;

    final range = _currentRange();
    final filterUserId =
        currentUser.canManageShifts ? _selectedUserId : currentUser.uid;
    final canLoadShifts =
        currentUser.canViewSchedule || currentUser.canManageShifts;
    if (canLoadShifts) {
      _shiftsSubscription = _firestoreService
          .watchShifts(
        orgId: currentUser.orgId,
        start: range.start,
        end: range.end,
        userId: filterUserId,
      )
          .listen((items) {
        final visible = _withoutTombstoned(
          items,
          (shift) => shift.id,
          _deletedShiftIds,
        ).toList(growable: false);
        _shifts = visible;
        _loading = false;
        _errorMessage = null;
        if (usesHybridStorage) {
          unawaited(
            _storeHybridShiftSnapshot(
              visible,
              start: range.start,
              end: range.end,
              filterUserId: filterUserId,
            ),
          );
        }
        _safeNotify();
      }, onError: (Object error) {
        _errorMessage = 'Fehler beim Laden der Schichten: $error';
        _shifts = [];
        _loading = false;
        _safeNotify();
      });
    } else {
      _shiftsSubscription = null;
      _loading = false;
      _errorMessage = null;
    }

    if (currentUser.canManageShifts) {
      _templatesSubscription = _firestoreService
          .watchShiftTemplates(
        orgId: currentUser.orgId,
        userId: currentUser.uid,
      )
          .listen((items) {
        _shiftTemplates = items;
        if (usesHybridStorage) {
          unawaited(_storeHybridShiftTemplatesSnapshot(items));
        }
        _safeNotify();
      }, onError: (Object error) {
        AppLogger.warning(
          'ScheduleProvider: Fehler beim Laden der Schichtvorlagen: $error',
        );
      });
    } else {
      _templatesSubscription = null;
    }

    _allAbsenceSubscription = _firestoreService
        .watchAllAbsenceRequests(
      orgId: currentUser.orgId,
      userId: currentUser.canManageShifts ? null : currentUser.uid,
    )
        .listen((items) {
      final visible = _withoutTombstoned(
        items,
        (request) => request.id,
        _deletedAbsenceIds,
      ).toList(growable: false);
      _allAbsenceRequests = visible;
      if (usesHybridStorage) {
        unawaited(_storeHybridAbsenceRequestsSnapshot(visible));
      }
      _safeNotify();
    }, onError: (Object error) {
      AppLogger.warning(
          'ScheduleProvider: Fehler beim Laden der kompletten Abwesenheiten: $error');
    });

    _absenceSubscription = _firestoreService
        .watchAbsenceRequests(
      orgId: currentUser.orgId,
      start: range.start,
      end: range.end,
      userId: filterUserId,
    )
        .listen((items) {
      _absenceRequests = _withoutTombstoned(
        items,
        (request) => request.id,
        _deletedAbsenceIds,
      ).toList(growable: false);
      _safeNotify();
    }, onError: (Object error) {
      AppLogger.warning(
          'ScheduleProvider: Fehler beim Laden der Abwesenheiten: $error');
      _absenceRequests = [];
      _safeNotify();
    });

    // --- Schichttausch: Manager abonniert alle, Mitarbeiter ein-/ausgehend ---
    if (currentUser.canManageShifts) {
      _swapIncomingSubscription = null;
      _swapOutgoingSubscription = null;
      _allSwapSubscription = _firestoreService
          .watchAllSwapRequests(orgId: currentUser.orgId)
          .listen((items) {
        _swapInbox = items;
        _swapOutbox = const [];
        _rebuildSwapRequests();
        if (usesHybridStorage) {
          unawaited(_storeHybridSwapRequestsSnapshot(items));
        }
        _safeNotify();
      }, onError: (Object error) {
        AppLogger.warning(
            'ScheduleProvider: Fehler beim Laden der Tauschanfragen: $error');
      });
    } else {
      _allSwapSubscription = null;
      _swapIncomingSubscription = _firestoreService
          .watchIncomingSwapRequests(
        orgId: currentUser.orgId,
        targetUid: currentUser.uid,
      )
          .listen((items) {
        _swapInbox = items;
        _rebuildSwapRequests();
        if (usesHybridStorage) {
          unawaited(_storeHybridSwapRequestsSnapshot(_swapRequests));
        }
        _safeNotify();
      }, onError: (Object error) {
        AppLogger.warning(
            'ScheduleProvider: Fehler beim Laden eingehender Tauschanfragen: $error');
      });
      _swapOutgoingSubscription = _firestoreService
          .watchOutgoingSwapRequests(
        orgId: currentUser.orgId,
        requesterUid: currentUser.uid,
      )
          .listen((items) {
        _swapOutbox = items;
        _rebuildSwapRequests();
        if (usesHybridStorage) {
          unawaited(_storeHybridSwapRequestsSnapshot(_swapRequests));
        }
        _safeNotify();
      }, onError: (Object error) {
        AppLogger.warning(
            'ScheduleProvider: Fehler beim Laden ausgehender Tauschanfragen: $error');
      });
    }

    // --- Gutschriften ---
    if (currentUser.canManageShifts) {
      _swapCreditAsCreditorSubscription = null;
      _swapCreditAsDebtorSubscription = null;
      _allSwapCreditSubscription = _firestoreService
          .watchAllSwapCredits(orgId: currentUser.orgId)
          .listen((items) {
        _creditsAsCreditor = items;
        _creditsAsDebtor = const [];
        _rebuildSwapCredits();
        if (usesHybridStorage) {
          unawaited(_storeHybridSwapCreditsSnapshot(items));
        }
        _safeNotify();
      }, onError: (Object error) {
        AppLogger.warning(
            'ScheduleProvider: Fehler beim Laden der Gutschriften: $error');
      });
    } else {
      _allSwapCreditSubscription = null;
      _swapCreditAsCreditorSubscription = _firestoreService
          .watchSwapCredits(
        orgId: currentUser.orgId,
        uid: currentUser.uid,
        asCreditor: true,
      )
          .listen((items) {
        _creditsAsCreditor = items;
        _rebuildSwapCredits();
        if (usesHybridStorage) {
          unawaited(_storeHybridSwapCreditsSnapshot(_swapCredits));
        }
        _safeNotify();
      }, onError: (Object error) {
        AppLogger.warning(
            'ScheduleProvider: Fehler beim Laden der Gutschriften (Gläubiger): $error');
      });
      _swapCreditAsDebtorSubscription = _firestoreService
          .watchSwapCredits(
        orgId: currentUser.orgId,
        uid: currentUser.uid,
        asCreditor: false,
      )
          .listen((items) {
        _creditsAsDebtor = items;
        _rebuildSwapCredits();
        if (usesHybridStorage) {
          unawaited(_storeHybridSwapCreditsSnapshot(_swapCredits));
        }
        _safeNotify();
      }, onError: (Object error) {
        AppLogger.warning(
            'ScheduleProvider: Fehler beim Laden der Gutschriften (Schuldner): $error');
      });
    }

    // Alte Subscriptions GENAU EINMAL nach dem Aufbau der neuen canceln (nicht
    // im wiederholt feuernden onData-Callback) — garantiert genau einen aktiven
    // Listener und vermeidet die Race, dass der alte Stream weiter veraltete
    // Daten schreibt (probleme #21, Muster aus WorkProvider).
    await oldShiftsSub?.cancel();
    await oldTemplatesSub?.cancel();
    await oldAllAbsenceSub?.cancel();
    await oldAbsenceSub?.cancel();
    await oldAllSwapSub?.cancel();
    await oldSwapIncomingSub?.cancel();
    await oldSwapOutgoingSub?.cancel();
    await oldAllSwapCreditSub?.cancel();
    await oldSwapCreditCreditorSub?.cancel();
    await oldSwapCreditDebtorSub?.cancel();
  }

  Future<void> _loadLocalState() async {
    _loading = true;
    notifyListeners();
    _localShifts = await DatabaseService.loadLocalShifts(scope: _localScope);
    _localShiftTemplates =
        await DatabaseService.loadLocalShiftTemplates(scope: _localScope);
    _localAbsenceRequests =
        await DatabaseService.loadLocalAbsenceRequests(scope: _localScope);
    _localSwapRequests =
        await DatabaseService.loadLocalSwapRequests(scope: _localScope);
    _localSwapCredits =
        await DatabaseService.loadLocalSwapCredits(scope: _localScope);
    _deletedShiftIds = await DatabaseService.loadTombstones(
      DatabaseService.shiftsCollection,
      scope: _localScope,
    );
    _deletedAbsenceIds = await DatabaseService.loadTombstones(
      DatabaseService.absenceRequestsCollection,
      scope: _localScope,
    );
    _applyLocalState();
    notifyListeners();
  }

  void _applyLocalState() {
    final currentUser = _currentUser;
    if (currentUser == null) {
      _shifts = [];
      _shiftTemplates = [];
      _absenceRequests = [];
      _allAbsenceRequests = [];
      _swapRequests = [];
      _swapCredits = [];
      _loading = false;
      return;
    }

    final range = _currentRange();
    final filterUserId =
        currentUser.canManageShifts ? _selectedUserId : currentUser.uid;
    final canLoadShifts =
        currentUser.canViewSchedule || currentUser.canManageShifts;

    _shifts = !canLoadShifts
        ? const <Shift>[]
        : _localShifts.where((shift) {
            final sameOrg = shift.orgId == currentUser.orgId;
            final sameUser =
                filterUserId == null || shift.userId == filterUserId;
            final inRange = !shift.startTime.isBefore(range.start) &&
                shift.startTime.isBefore(range.end);
            return sameOrg && sameUser && inRange;
          }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    _shiftTemplates = !currentUser.canManageShifts
        ? <ShiftTemplate>[]
        : (_localShiftTemplates.where((template) {
            return template.orgId == currentUser.orgId &&
                (template.userId.isEmpty || template.userId == currentUser.uid);
          }).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          ));

    _absenceRequests = _localAbsenceRequests.where((request) {
      final sameOrg = request.orgId == currentUser.orgId;
      final sameUser = filterUserId == null || request.userId == filterUserId;
      return sameOrg && sameUser && request.overlaps(range.start, range.end);
    }).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));

    _allAbsenceRequests = _localAbsenceRequests.where((request) {
      final sameOrg = request.orgId == currentUser.orgId;
      final canSeeRequest =
          currentUser.canManageShifts || request.userId == currentUser.uid;
      return sameOrg && canSeeRequest;
    }).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));

    _swapRequests = _localSwapRequests.where((request) {
      final sameOrg = request.orgId == currentUser.orgId;
      final canSee = currentUser.canManageShifts ||
          request.requesterUid == currentUser.uid ||
          request.targetUid == currentUser.uid;
      return sameOrg && canSee;
    }).toList()
      ..sort((a, b) {
        final aw = a.updatedAt ?? a.createdAt ?? a.requesterShiftStart;
        final bw = b.updatedAt ?? b.createdAt ?? b.requesterShiftStart;
        return bw.compareTo(aw);
      });

    _swapCredits = _localSwapCredits.where((credit) {
      final sameOrg = credit.orgId == currentUser.orgId;
      final canSee = currentUser.canManageShifts ||
          credit.creditorUid == currentUser.uid ||
          credit.debtorUid == currentUser.uid;
      return sameOrg && canSee;
    }).toList()
      ..sort((a, b) => b.originShiftStart.compareTo(a.originShiftStart));

    _loading = false;
  }

  String get _storageModeKey {
    if (usesLocalStorage) {
      return 'local';
    }
    return usesHybridStorage ? 'hybrid' : 'cloud';
  }

  Future<void> _storeHybridShiftSnapshot(
    List<Shift> items, {
    required DateTime start,
    required DateTime end,
    required String? filterUserId,
  }) async {
    final scope = _localScope;
    if (!usesHybridStorage || scope == null) {
      return;
    }

    final scopedLocalShifts = _localShifts.where((shift) {
      final inRange =
          !shift.startTime.isBefore(start) && shift.startTime.isBefore(end);
      if (!inRange) {
        return false;
      }
      if (filterUserId == null) {
        return true;
      }
      return shift.userId == filterUserId;
    }).toList(growable: false);
    final unaffectedShifts = _localShifts.where((shift) {
      final inRange =
          !shift.startTime.isBefore(start) && shift.startTime.isBefore(end);
      if (!inRange) {
        return true;
      }
      if (filterUserId == null) {
        return false;
      }
      return shift.userId != filterUserId;
    }).toList(growable: false);

    _localShifts = [
      ...unaffectedShifts,
      ..._mergeByKey(
        scopedLocalShifts,
        _withoutTombstoned(items, (shift) => shift.id, _deletedShiftIds),
        (shift) => shift.id?.trim().isNotEmpty == true
            ? 'id:${shift.id}'
            : 'shift:${shift.userId}:${shift.startTime.toIso8601String()}:${shift.endTime.toIso8601String()}',
        updatedAtOf: (shift) => shift.updatedAt,
      ),
    ]..sort((a, b) => a.startTime.compareTo(b.startTime));

    await _persistLocalShifts();
    _applyLocalState();
    _safeNotify();
  }

  Future<void> _storeHybridShiftTemplatesSnapshot(
    List<ShiftTemplate> items,
  ) async {
    final scope = _localScope;
    if (!usesHybridStorage || scope == null) {
      return;
    }
    _localShiftTemplates = _mergeByKey(
      _localShiftTemplates,
      items,
      (template) => template.id?.trim().isNotEmpty == true
          ? 'id:${template.id}'
          : 'template:${template.userId}:${template.name}:${template.startMinutes}:${template.endMinutes}',
    );
    await _persistLocalShiftTemplates();
    _applyLocalState();
    _safeNotify();
  }

  Future<void> _storeHybridAbsenceRequestsSnapshot(
    List<AbsenceRequest> items,
  ) async {
    final scope = _localScope;
    if (!usesHybridStorage || scope == null) {
      return;
    }
    _localAbsenceRequests = _mergeByKey(
      _localAbsenceRequests,
      _withoutTombstoned(items, (request) => request.id, _deletedAbsenceIds),
      (request) => request.id?.trim().isNotEmpty == true
          ? 'id:${request.id}'
          : 'absence:${request.userId}:${request.startDate.toIso8601String()}:${request.endDate.toIso8601String()}:${request.type.value}',
    );
    await _persistLocalAbsenceRequests();
    _applyLocalState();
    _safeNotify();
  }

  // Stabile Client-ID (UUID v4), bereits beim Erzeugen vergeben -> auch der
  // Cloud-Pfad nutzt sie als Doc-ID und Callable-Retries bleiben idempotent
  // (timestamp-ids-not-uuid, no-idempotency-key).
  String _nextLocalId(String prefix) {
    return '$prefix-${_uuid.v4()}';
  }

  /// Neue Serien-ID (UUID v4) zum Gruppieren mehrerer zusammengehöriger
  /// Schichten (Mehrtage-Anlage im Editor, Kopier-Aktionen), damit sie als
  /// Serie behandel- und über [deleteShiftSeries] gemeinsam löschbar werden.
  /// Bewusst im Provider erzeugt – die UI generiert keine IDs.
  String newSeriesId() => _uuid.v4();

  void _upsertLocalShift(Shift shift) {
    final index = _localShifts.indexWhere((item) => item.id == shift.id);
    if (index == -1) {
      _localShifts.add(shift);
      return;
    }
    _localShifts[index] = shift;
  }

  void _upsertLocalShiftTemplate(ShiftTemplate template) {
    final index =
        _localShiftTemplates.indexWhere((item) => item.id == template.id);
    if (index == -1) {
      _localShiftTemplates.add(template);
      return;
    }
    _localShiftTemplates[index] = template;
  }

  void _upsertLocalAbsenceRequest(AbsenceRequest request) {
    final index =
        _localAbsenceRequests.indexWhere((item) => item.id == request.id);
    if (index == -1) {
      _localAbsenceRequests.add(request);
      return;
    }
    _localAbsenceRequests[index] = request;
  }

  Future<void> _persistLocalShifts() {
    return DatabaseService.saveLocalShifts(
      _localShifts,
      scope: _localScope,
    );
  }

  Future<void> _persistLocalShiftTemplates() {
    return DatabaseService.saveLocalShiftTemplates(
      _localShiftTemplates,
      scope: _localScope,
    );
  }

  Future<void> _persistLocalAbsenceRequests() {
    return DatabaseService.saveLocalAbsenceRequests(
      _localAbsenceRequests,
      scope: _localScope,
    );
  }

  // --- Schichttausch-Hilfsfunktionen ---

  Future<void> _cancelSwapSubscriptions() async {
    await _allSwapSubscription?.cancel();
    await _swapIncomingSubscription?.cancel();
    await _swapOutgoingSubscription?.cancel();
    await _allSwapCreditSubscription?.cancel();
    await _swapCreditAsCreditorSubscription?.cancel();
    await _swapCreditAsDebtorSubscription?.cancel();
    _allSwapSubscription = null;
    _swapIncomingSubscription = null;
    _swapOutgoingSubscription = null;
    _allSwapCreditSubscription = null;
    _swapCreditAsCreditorSubscription = null;
    _swapCreditAsDebtorSubscription = null;
  }

  void _rebuildSwapRequests() {
    final byId = <String, ShiftSwapRequest>{};
    for (final request in _swapInbox) {
      if (request.id != null && request.id!.isNotEmpty) {
        byId[request.id!] = request;
      }
    }
    for (final request in _swapOutbox) {
      if (request.id != null && request.id!.isNotEmpty) {
        byId[request.id!] = request;
      }
    }
    _swapRequests = byId.values.toList()
      ..sort((a, b) {
        final aw = a.updatedAt ?? a.createdAt ?? a.requesterShiftStart;
        final bw = b.updatedAt ?? b.createdAt ?? b.requesterShiftStart;
        return bw.compareTo(aw);
      });
  }

  void _rebuildSwapCredits() {
    final byId = <String, SwapCredit>{};
    for (final credit in _creditsAsCreditor) {
      if (credit.id != null && credit.id!.isNotEmpty) {
        byId[credit.id!] = credit;
      }
    }
    for (final credit in _creditsAsDebtor) {
      if (credit.id != null && credit.id!.isNotEmpty) {
        byId[credit.id!] = credit;
      }
    }
    _swapCredits = byId.values.toList()
      ..sort((a, b) => b.originShiftStart.compareTo(a.originShiftStart));
  }

  ShiftSwapRequest? _findSwapRequestById(String requestId) {
    for (final request in _swapRequests) {
      if (request.id == requestId) {
        return request;
      }
    }
    for (final request in _localSwapRequests) {
      if (request.id == requestId) {
        return request;
      }
    }
    return null;
  }

  SwapCredit? _findSwapCreditById(String creditId) {
    for (final credit in _swapCredits) {
      if (credit.id == creditId) {
        return credit;
      }
    }
    for (final credit in _localSwapCredits) {
      if (credit.id == creditId) {
        return credit;
      }
    }
    return null;
  }

  void _upsertLocalSwapRequest(ShiftSwapRequest request) {
    final index =
        _localSwapRequests.indexWhere((item) => item.id == request.id);
    if (index == -1) {
      _localSwapRequests.add(request);
      return;
    }
    _localSwapRequests[index] = request;
  }

  void _upsertLocalSwapCredit(SwapCredit credit) {
    final index = _localSwapCredits.indexWhere((item) => item.id == credit.id);
    if (index == -1) {
      _localSwapCredits.add(credit);
      return;
    }
    _localSwapCredits[index] = credit;
  }

  Future<void> _persistLocalSwapRequests() {
    return DatabaseService.saveLocalSwapRequests(
      _localSwapRequests,
      scope: _localScope,
    );
  }

  Future<void> _persistLocalSwapCredits() {
    return DatabaseService.saveLocalSwapCredits(
      _localSwapCredits,
      scope: _localScope,
    );
  }

  Future<void> _storeHybridSwapRequestsSnapshot(
    List<ShiftSwapRequest> items,
  ) async {
    final scope = _localScope;
    if (!usesHybridStorage || scope == null) {
      return;
    }
    _localSwapRequests = _mergeByKey(
      _localSwapRequests,
      items,
      (request) => request.id?.trim().isNotEmpty == true
          ? 'id:${request.id}'
          : 'swap:${request.requesterShiftId}:${request.targetUid}',
      updatedAtOf: (request) => request.updatedAt,
    );
    await _persistLocalSwapRequests();
    _applyLocalState();
    _safeNotify();
  }

  Future<void> _storeHybridSwapCreditsSnapshot(List<SwapCredit> items) async {
    final scope = _localScope;
    if (!usesHybridStorage || scope == null) {
      return;
    }
    _localSwapCredits = _mergeByKey(
      _localSwapCredits,
      items,
      (credit) => credit.id?.trim().isNotEmpty == true
          ? 'id:${credit.id}'
          : 'credit:${credit.originSwapRequestId}',
      updatedAtOf: (credit) => credit.updatedAt,
    );
    await _persistLocalSwapCredits();
    _applyLocalState();
    _safeNotify();
  }

  /// Kurzlabel einer Schicht für die Inbox-Darstellung („Mo 24.06., 09:00–17:00
  /// · Standort"). Bewusst ohne `intl`, damit es überall (auch ohne geladenes
  /// Locale) funktioniert; Wochentage/Format sind deutsch fixiert.
  String _swapShiftLabel(Shift shift) {
    const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    String two(int v) => v.toString().padLeft(2, '0');
    final wd = weekdays[(shift.startTime.weekday - 1) % 7];
    final date = '${two(shift.startTime.day)}.${two(shift.startTime.month)}.';
    final time =
        '${two(shift.startTime.hour)}:${two(shift.startTime.minute)}–${two(shift.endTime.hour)}:${two(shift.endTime.minute)}';
    final site = shift.effectiveSiteLabel;
    final base = '$wd $date, $time';
    return site == null || site.trim().isEmpty ? base : '$base · $site';
  }

  /// Filtert aus der Cloud kommende Elemente heraus, die lokal als geloescht
  /// markiert sind (Tombstone) – verhindert Wiederauferstehen beim Mode-Switch.
  Iterable<T> _withoutTombstoned<T>(
    Iterable<T> items,
    String? Function(T item) idOf,
    Set<String> tombstones,
  ) {
    if (tombstones.isEmpty) {
      return items;
    }
    return items.where((item) {
      final id = idOf(item)?.trim();
      return id == null || id.isEmpty || !tombstones.contains(id);
    });
  }

  Future<void> _recordShiftTombstone(String id) async {
    _deletedShiftIds.add(id);
    await DatabaseService.saveTombstones(
      DatabaseService.shiftsCollection,
      _deletedShiftIds,
      scope: _localScope,
    );
  }

  Future<void> _recordAbsenceTombstone(String id) async {
    _deletedAbsenceIds.add(id);
    await DatabaseService.saveTombstones(
      DatabaseService.absenceRequestsCollection,
      _deletedAbsenceIds,
      scope: _localScope,
    );
  }

  List<T> _mergeByKey<T>(
    Iterable<T> localItems,
    Iterable<T> remoteItems,
    String Function(T item) keyOf, {
    DateTime? Function(T item)? updatedAtOf,
  }) {
    final merged = <String, T>{};
    var index = 0;
    for (final item in localItems) {
      final key = keyOf(item).trim();
      merged[key.isEmpty ? 'local:$index' : key] = item;
      index++;
    }
    for (final item in remoteItems) {
      final key = keyOf(item).trim();
      final resolvedKey = key.isEmpty ? 'remote:$index' : key;
      index++;
      final existing = merged[resolvedKey];
      if (existing != null && updatedAtOf != null) {
        final localTs = updatedAtOf(existing);
        final remoteTs = updatedAtOf(item);
        // Last-Write-Wins: eine lokal neuere (noch nicht synchronisierte)
        // Version nicht durch einen aelteren Server-Snapshot ueberschreiben.
        if (localTs != null && remoteTs != null && localTs.isAfter(remoteTs)) {
          continue;
        }
      }
      merged[resolvedKey] = item;
    }
    return merged.values.toList(growable: true);
  }

  List<Shift> _filterShifts(
    Iterable<Shift> source, {
    bool includeStatusFilter = true,
  }) {
    final selectedTeamId = _selectedTeamId;
    final selectedTeamName = _selectedTeamName;
    return source.where((shift) {
      if (includeStatusFilter &&
          _statusFilter != null &&
          shift.status != _statusFilter) {
        return false;
      }
      if (selectedTeamId == null || selectedTeamId.isEmpty) {
        return true;
      }
      if (shift.teamId == selectedTeamId) {
        return true;
      }
      if (selectedTeamName == null || selectedTeamName.isEmpty) {
        return false;
      }
      return shift.team == selectedTeamName;
    }).toList(growable: false);
  }

  ({DateTime start, DateTime end}) _currentRange() {
    switch (_viewMode) {
      case ScheduleViewMode.day:
        final start = DateTime(
          _visibleDate.year,
          _visibleDate.month,
          _visibleDate.day,
        );
        return (start: start, end: start.add(const Duration(days: 1)));
      case ScheduleViewMode.week:
        final day = _visibleDate.weekday;
        final start = DateTime(
          _visibleDate.year,
          _visibleDate.month,
          _visibleDate.day,
        ).subtract(Duration(days: day - 1));
        return (start: start, end: start.add(const Duration(days: 7)));
      case ScheduleViewMode.month:
        final start = DateTime(_visibleDate.year, _visibleDate.month, 1);
        final end = DateTime(_visibleDate.year, _visibleDate.month + 1, 1);
        return (start: start, end: end);
    }
  }

  ({DateTime start, DateTime end}) _buildShiftAvailabilityWindow(
    DateTime startTime,
    DateTime endTime,
  ) {
    final start = DateTime(
      startTime.year,
      startTime.month,
      startTime.day,
    ).subtract(const Duration(days: 1));
    final end = DateTime(
      endTime.year,
      endTime.month,
      endTime.day + 1,
    );
    return (start: start, end: end);
  }

  List<ComplianceRuleSet> get _effectiveRuleSets {
    return ComplianceRuleSetUtils.effectiveRuleSets(
      ruleSets: _ruleSets,
      currentUser: _currentUser,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _shiftsSubscription?.cancel();
    _absenceSubscription?.cancel();
    _allAbsenceSubscription?.cancel();
    _templatesSubscription?.cancel();
    _allSwapSubscription?.cancel();
    _swapIncomingSubscription?.cancel();
    _swapOutgoingSubscription?.cancel();
    _allSwapCreditSubscription?.cancel();
    _swapCreditAsCreditorSubscription?.cancel();
    _swapCreditAsDebtorSubscription?.cancel();
    super.dispose();
  }
}
