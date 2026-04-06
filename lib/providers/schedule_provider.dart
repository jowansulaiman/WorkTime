import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/compliance_rule_set_utils.dart';
import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/compliance_rule_set.dart';
import '../models/compliance_violation.dart';
import '../models/employee_site_assignment.dart';
import '../models/employment_contract.dart';
import '../models/shift.dart';
import '../models/shift_template.dart';
import '../models/travel_time_rule.dart';
import '../services/database_service.dart';
import '../services/compliance_service.dart';
import '../services/firestore_service.dart';

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
  })  : _firestoreService = firestoreService,
        _complianceService = complianceService ?? const ComplianceService(),
        _forceLocalStorage =
            disableAuthentication ?? AppConfig.disableAuthentication;

  final FirestoreService _firestoreService;
  final ComplianceService _complianceService;
  final bool _forceLocalStorage;
  bool _localStorageOnly = false;
  bool _hybridStorageEnabled = false;

  StreamSubscription<List<Shift>>? _shiftsSubscription;
  StreamSubscription<List<AbsenceRequest>>? _absenceSubscription;
  StreamSubscription<List<AbsenceRequest>>? _allAbsenceSubscription;
  StreamSubscription<List<ShiftTemplate>>? _templatesSubscription;

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
  List<Shift> _localShifts = [];
  List<ShiftTemplate> _localShiftTemplates = [];
  List<AbsenceRequest> _localAbsenceRequests = [];
  List<AppUserProfile> _orgMembers = [];
  List<EmploymentContract> _contracts = [];
  List<EmployeeSiteAssignment> _siteAssignments = [];
  List<ComplianceRuleSet> _ruleSets = [];
  List<TravelTimeRule> _travelTimeRules = [];
  bool _loading = false;
  String? _errorMessage;
  bool _disposed = false;
  ShiftStatus? _statusFilter;

  DateTime get visibleDate => _visibleDate;
  ScheduleViewMode get viewMode => _viewMode;
  String? get selectedUserId => _selectedUserId;
  String? get selectedTeamId => _selectedTeamId;
  String? get selectedTeamName => _selectedTeamName;
  List<Shift> get shifts => _filterShifts(_shifts);
  List<ShiftTemplate> get shiftTemplates => _shiftTemplates;
  List<AbsenceRequest> get absenceRequests => _absenceRequests;
  List<AbsenceRequest> get allAbsenceRequests => _allAbsenceRequests;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;
  ShiftStatus? get statusFilter => _statusFilter;
  bool get usesLocalStorage => _forceLocalStorage || _localStorageOnly;
  bool get usesHybridStorage =>
      !_forceLocalStorage && !_localStorageOnly && _hybridStorageEnabled;

  void updateReferenceData({
    required List<AppUserProfile> members,
    required List<EmploymentContract> contracts,
    required List<EmployeeSiteAssignment> siteAssignments,
    required List<ComplianceRuleSet> ruleSets,
    required List<TravelTimeRule> travelTimeRules,
  }) {
    _orgMembers = members;
    _contracts = contracts;
    _siteAssignments = siteAssignments;
    _ruleSets = ruleSets;
    _travelTimeRules = travelTimeRules;
  }

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
      _localShifts = [];
      _localShiftTemplates = [];
      _localAbsenceRequests = [];
      _orgMembers = [];
      _contracts = [];
      _siteAssignments = [];
      _ruleSets = [];
      _travelTimeRules = [];
      await _shiftsSubscription?.cancel();
      await _absenceSubscription?.cancel();
      await _allAbsenceSubscription?.cancel();
      await _templatesSubscription?.cancel();
      _safeNotify();
      return;
    }

    if (usesHybridStorage && changed) {
      await _shiftsSubscription?.cancel();
      await _absenceSubscription?.cancel();
      await _allAbsenceSubscription?.cancel();
      await _templatesSubscription?.cancel();
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

  void setViewMode(ScheduleViewMode mode) {
    _viewMode = mode;
    if (usesHybridStorage) {
      _applyLocalState();
      _safeNotify();
    }
    _restartSubscriptions();
  }

  void setVisibleDate(DateTime date) {
    _visibleDate = date;
    if (usesHybridStorage) {
      _applyLocalState();
      _safeNotify();
    }
    _restartSubscriptions();
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
    _restartSubscriptions();
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

  Future<void> saveShift(
    Shift shift, {
    RecurrencePattern recurrencePattern = RecurrencePattern.none,
    DateTime? recurrenceEndDate,
  }) async {
    await saveShifts(
      [shift],
      recurrencePattern: recurrencePattern,
      recurrenceEndDate: recurrenceEndDate,
    );
  }

  Future<void> saveShifts(
    List<Shift> shifts, {
    RecurrencePattern recurrencePattern = RecurrencePattern.none,
    DateTime? recurrenceEndDate,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts || shifts.isEmpty) {
      return;
    }

    final conflictIssues = await validateShifts(
      shifts,
      recurrencePattern: recurrencePattern,
      recurrenceEndDate: recurrenceEndDate,
    );
    if (conflictIssues.isNotEmpty) {
      throw ShiftConflictException(conflictIssues);
    }

    if (usesLocalStorage) {
      for (final shift in shifts) {
        final occurrences = _firestoreService.buildShiftOccurrences(
          shift.copyWith(createdByUid: currentUser.uid),
          recurrencePattern: recurrencePattern,
          recurrenceEndDate: recurrenceEndDate,
        );

        for (final occurrence in occurrences) {
          final localShift = occurrence.copyWith(
            id: occurrence.id ?? _nextLocalId('shift'),
          );
          final index =
              _localShifts.indexWhere((item) => item.id == localShift.id);
          if (index == -1) {
            _localShifts.add(localShift);
          } else {
            _localShifts[index] = localShift;
          }
        }
      }

      await DatabaseService.saveLocalShifts(
        _localShifts,
        scope: _localScope,
      );
      _applyLocalState();
      notifyListeners();
      return;
    }

    final occurrences = shifts
        .expand(
          (shift) => _firestoreService.buildShiftOccurrences(
            shift.copyWith(createdByUid: currentUser.uid),
            recurrencePattern: recurrencePattern,
            recurrenceEndDate: recurrenceEndDate,
          ),
        )
        .toList(growable: false);
    await _firestoreService.saveShiftBatch(occurrences);
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
      final index = _localShiftTemplates.indexWhere(
        (item) => item.id == localTemplate.id,
      );
      if (index == -1) {
        _localShiftTemplates.add(localTemplate);
      } else {
        _localShiftTemplates[index] = localTemplate;
      }
      await DatabaseService.saveLocalShiftTemplates(
        _localShiftTemplates,
        scope: _localScope,
      );
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.saveShiftTemplate(
      template.copyWith(
        orgId: currentUser.orgId,
        userId: currentUser.uid,
      ),
    );
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

    if (usesLocalStorage) {
      _localShifts.removeWhere((shift) => shift.id == shiftId);
      await DatabaseService.saveLocalShifts(
        _localShifts,
        scope: _localScope,
      );
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.deleteShift(
      orgId: currentUser.orgId,
      shiftId: shiftId,
    );
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
      var changed = false;
      for (final shift in publishable) {
        final index = _localShifts.indexWhere((item) => item.id == shift.id);
        if (index == -1) {
          continue;
        }
        _localShifts[index] = _localShifts[index].copyWith(status: status);
        changed = true;
      }
      if (!changed) {
        return;
      }
      await DatabaseService.saveLocalShifts(
        _localShifts,
        scope: _localScope,
      );
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.publishShiftBatch(
      orgId: currentUser.orgId,
      shifts: publishable
          .map((shift) => shift.copyWith(createdByUid: currentUser.uid))
          .toList(growable: false),
      status: status,
    );
  }

  Future<void> deleteShiftSeries(String seriesId) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.canManageShifts) {
      return;
    }

    if (usesLocalStorage) {
      _localShifts.removeWhere((shift) => shift.seriesId == seriesId);
      await DatabaseService.saveLocalShifts(
        _localShifts,
        scope: _localScope,
      );
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.deleteShiftSeries(
      orgId: currentUser.orgId,
      seriesId: seriesId,
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
      createdAt: existingRequest?.createdAt,
      updatedAt: existingRequest?.updatedAt,
    );

    if (usesLocalStorage) {
      final localRequest = requestWithContext.copyWith(
        id: requestWithContext.id ?? _nextLocalId('absence'),
      );
      final index = _localAbsenceRequests.indexWhere(
        (item) => item.id == localRequest.id,
      );
      if (index == -1) {
        _localAbsenceRequests.add(localRequest);
      } else {
        _localAbsenceRequests[index] = localRequest;
      }
      await DatabaseService.saveLocalAbsenceRequests(
        _localAbsenceRequests,
        scope: _localScope,
      );
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.saveAbsenceRequest(
      requestWithContext,
    );
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
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.deleteAbsenceRequest(
      orgId: currentUser.orgId,
      requestId: requestId,
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
      await DatabaseService.saveLocalAbsenceRequests(
        _localAbsenceRequests,
        scope: _localScope,
      );
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.reviewAbsenceRequest(
      orgId: currentUser.orgId,
      requestId: requestId,
      status: status,
      reviewerUid: currentUser.uid,
    );
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

  /// Laedt die genehmigten Urlaubstage fuer ein bestimmtes Jahr aus Firestore.
  Future<int> getUsedVacationDaysForYear(int year) async {
    final user = _currentUser;
    if (user == null) return 0;

    if (usesLocalStorage) {
      return _countVacationDays(_localAbsenceRequests, year);
    }

    final vacations = await _firestoreService.getApprovedVacationsForYear(
      orgId: user.orgId,
      userId: user.uid,
      year: year,
    );
    return _countVacationDays(vacations, year);
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
        .map((s) => Shift(
              orgId: s.orgId,
              userId: s.userId,
              employeeName: s.employeeName,
              title: s.title,
              startTime: s.startTime.add(dayOffset),
              endTime: s.endTime.add(dayOffset),
              breakMinutes: s.breakMinutes,
              teamId: s.teamId,
              team: s.team,
              location: s.location,
              notes: s.notes,
              color: s.color,
              status: ShiftStatus.planned,
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
      return;
    }

    await _firestoreService.updateShiftSwapRequest(
      orgId: currentUser.orgId,
      shiftId: shiftId,
      requestedByUid: currentUser.uid,
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

  /// Gibt die Schichten fuer einen bestimmten Tag und Benutzer zurueck, die
  /// noch offen (nicht erledigt/abgesagt) sind.
  Future<List<Shift>> openShiftsForDay({
    required DateTime day,
    String? userId,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null) return const [];

    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final effectiveUserId = userId ?? currentUser.uid;

    if (usesLocalStorage) {
      return _localShifts
          .where((shift) =>
              shift.orgId == currentUser.orgId &&
              shift.userId == effectiveUserId &&
              shift.startTime.isBefore(dayEnd) &&
              shift.endTime.isAfter(dayStart) &&
              shift.status != ShiftStatus.completed &&
              shift.status != ShiftStatus.cancelled)
          .toList(growable: false);
    }

    final shifts = await _firestoreService.getShiftsInRange(
      orgId: currentUser.orgId,
      start: dayStart,
      end: dayEnd,
      userId: effectiveUserId,
    );
    return shifts
        .where((shift) =>
            shift.status != ShiftStatus.completed &&
            shift.status != ShiftStatus.cancelled)
        .toList(growable: false);
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
      ...await _firestoreService.getAllShifts(
        orgId: currentUser.orgId,
        userId: filterUserId,
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
      ...await _firestoreService.getAllAbsenceRequests(
        orgId: currentUser.orgId,
        userId: filterUserId,
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

    final shifts = _localShifts
        .where((shift) => shift.orgId == currentUser.orgId)
        .toList(growable: false);
    if (shifts.isNotEmpty) {
      await _firestoreService.saveShiftBatch(shifts);
    }

    for (final template in _localShiftTemplates.where(
      (item) => item.orgId == currentUser.orgId,
    )) {
      await _firestoreService.saveShiftTemplate(template);
    }

    for (final request in _localAbsenceRequests.where(
      (item) => item.orgId == currentUser.orgId,
    )) {
      await _firestoreService.saveAbsenceRequest(request);
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

    await _shiftsSubscription?.cancel();
    await _absenceSubscription?.cancel();
    await _allAbsenceSubscription?.cancel();
    await _templatesSubscription?.cancel();
    if (!usesHybridStorage) {
      _shifts = [];
      _shiftTemplates = [];
      _absenceRequests = [];
      _allAbsenceRequests = [];
    }

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
        _shifts = items;
        _loading = false;
        _errorMessage = null;
        if (usesHybridStorage) {
          unawaited(
            _storeHybridShiftSnapshot(
              items,
              start: range.start,
              end: range.end,
              filterUserId: filterUserId,
            ),
          );
        }
        _safeNotify();
      }, onError: (Object error) {
        _errorMessage = 'Fehler beim Laden der Schichten: $error';
        _loading = false;
        _safeNotify();
      });
    } else {
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
        debugPrint(
          'ScheduleProvider: Fehler beim Laden der Schichtvorlagen: $error',
        );
      });
    }

    _allAbsenceSubscription = _firestoreService
        .watchAllAbsenceRequests(
      orgId: currentUser.orgId,
      userId: currentUser.canManageShifts ? null : currentUser.uid,
    )
        .listen((items) {
      _allAbsenceRequests = items;
      if (usesHybridStorage) {
        unawaited(_storeHybridAbsenceRequestsSnapshot(items));
      }
      _safeNotify();
    }, onError: (Object error) {
      debugPrint(
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
      _absenceRequests = items;
      _safeNotify();
    }, onError: (Object error) {
      debugPrint(
          'ScheduleProvider: Fehler beim Laden der Abwesenheiten: $error');
    });
  }

  Future<void> _loadLocalState() async {
    _loading = true;
    notifyListeners();
    _localShifts = await DatabaseService.loadLocalShifts(scope: _localScope);
    _localShiftTemplates =
        await DatabaseService.loadLocalShiftTemplates(scope: _localScope);
    _localAbsenceRequests =
        await DatabaseService.loadLocalAbsenceRequests(scope: _localScope);
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

    _localShifts = _localShifts.where((shift) {
      final inRange =
          !shift.startTime.isBefore(start) && shift.startTime.isBefore(end);
      if (!inRange) {
        return true;
      }
      if (filterUserId == null) {
        return false;
      }
      return shift.userId != filterUserId;
    }).toList(growable: true)
      ..addAll(items)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    await DatabaseService.saveLocalShifts(
      _localShifts,
      scope: scope,
    );
  }

  Future<void> _storeHybridShiftTemplatesSnapshot(
    List<ShiftTemplate> items,
  ) async {
    final scope = _localScope;
    if (!usesHybridStorage || scope == null) {
      return;
    }
    _localShiftTemplates = [...items];
    await DatabaseService.saveLocalShiftTemplates(
      _localShiftTemplates,
      scope: scope,
    );
  }

  Future<void> _storeHybridAbsenceRequestsSnapshot(
    List<AbsenceRequest> items,
  ) async {
    final scope = _localScope;
    if (!usesHybridStorage || scope == null) {
      return;
    }
    _localAbsenceRequests = [...items];
    await DatabaseService.saveLocalAbsenceRequests(
      _localAbsenceRequests,
      scope: scope,
    );
  }

  String _nextLocalId(String prefix) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
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
    _templatesSubscription?.cancel();
    super.dispose();
  }
}
