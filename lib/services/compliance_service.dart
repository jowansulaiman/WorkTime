import 'package:collection/collection.dart';
import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/compliance_rule_set.dart';
import '../models/compliance_violation.dart';
import '../models/employee_site_assignment.dart';
import '../models/employment_contract.dart';
import '../models/shift.dart';
import '../models/travel_time_rule.dart';
import '../models/work_entry.dart';

class ComplianceService {
  const ComplianceService();

  List<ComplianceViolation> validateShift({
    required Shift shift,
    required List<Shift> existingShifts,
    required List<Shift> draftShifts,
    required List<AbsenceRequest> absences,
    required List<EmploymentContract> contracts,
    required List<EmployeeSiteAssignment> siteAssignments,
    required List<ComplianceRuleSet> ruleSets,
    required List<TravelTimeRule> travelTimeRules,
    required List<AppUserProfile> members,
  }) {
    final violations = <ComplianceViolation>[];
    final contract = _activeContract(
      contracts: contracts,
      userId: shift.userId,
      at: shift.startTime,
    );
    final member =
        members.firstWhereOrNull((entry) => entry.uid == shift.userId);
    final workRuleSettings = _workRuleSettingsFor(member);
    final assignment = _assignmentForShift(
      assignments: siteAssignments,
      shift: shift,
      userId: shift.userId,
    );
    final ruleSet = _resolveRuleSet(
      ruleSets: ruleSets,
      siteId: shift.siteId,
      contract: contract,
    );
    final durationMinutes =
        shift.endTime.difference(shift.startTime).inMinutes -
            shift.breakMinutes.round();
    final sameUserExisting = existingShifts
        .where((candidate) =>
            candidate.userId == shift.userId && candidate.id != shift.id)
        .toList(growable: false);
    final sameUserDraft = draftShifts
        .where((candidate) =>
            candidate.userId == shift.userId && !identical(candidate, shift))
        .toList(growable: false);

    if (!shift.isUnassigned && (shift.siteId?.trim().isEmpty ?? true)) {
      violations.add(
        const ComplianceViolation(
          code: 'site_required',
          severity: ComplianceSeverity.blocking,
          message: 'Fuer geplante Schichten ist ein Standort Pflicht.',
        ),
      );
    }

    if (!shift.isUnassigned && assignment == null) {
      violations.add(
        ComplianceViolation(
          code: 'site_assignment_missing',
          severity: ComplianceSeverity.blocking,
          message:
              '${shift.employeeName} ist dem gewaehlten Standort nicht zugeordnet.',
          relatedEntityIds: [
            shift.userId,
            if (shift.siteId != null) shift.siteId!
          ],
        ),
      );
    }

    if (!shift.isUnassigned &&
        shift.requiredQualificationIds.isNotEmpty &&
        assignment != null) {
      final missing = shift.requiredQualificationIds
          .where((id) => !assignment.qualificationIds.contains(id))
          .toList(growable: false);
      if (missing.isNotEmpty) {
        violations.add(
          ComplianceViolation(
            code: 'missing_qualification',
            severity: ComplianceSeverity.blocking,
            message:
                '${shift.employeeName} erfuellt nicht alle erforderlichen Qualifikationen.',
            relatedEntityIds: missing,
          ),
        );
      }
    }

    final conflictingExisting = sameUserExisting
        .where((candidate) => candidate.overlaps(shift))
        .toList(growable: false);
    if (conflictingExisting.isNotEmpty) {
      violations.add(
        ComplianceViolation(
          code: 'overlap_existing',
          severity: ComplianceSeverity.blocking,
          message:
              'Ueberschneidung mit bestehender Schicht am ${_formatDateTime(conflictingExisting.first.startTime)}.',
          relatedEntityIds: conflictingExisting
              .map((entry) => entry.id)
              .whereType<String>()
              .toList(growable: false),
        ),
      );
    }

    final conflictingDraft = sameUserDraft
        .where((candidate) => candidate.overlaps(shift))
        .toList(growable: false);
    if (conflictingDraft.isNotEmpty) {
      violations.add(
        ComplianceViolation(
          code: 'overlap_draft',
          severity: ComplianceSeverity.blocking,
          message: 'Ueberschneidung mit weiterer neuer Schicht im Paket.',
          relatedEntityIds: conflictingDraft
              .map((entry) => entry.id)
              .whereType<String>()
              .toList(growable: false),
        ),
      );
    }

    final approvedAbsences = absences
        .where((absence) =>
            absence.userId == shift.userId &&
            absence.status == AbsenceStatus.approved &&
            absence.overlaps(shift.startTime, shift.endTime))
        .toList(growable: false);
    if (approvedAbsences.isNotEmpty) {
      violations.add(
        ComplianceViolation(
          code: 'absence_conflict',
          severity: ComplianceSeverity.blocking,
          message:
              'Genehmigte Abwesenheit (${approvedAbsences.first.type.label}) ueberschneidet diese Schicht.',
          relatedEntityIds: approvedAbsences
              .map((entry) => entry.id)
              .whereType<String>()
              .toList(growable: false),
        ),
      );
    }

    final requiredBreakMinutes = _requiredBreakMinutes(
      workedMinutes: durationMinutes,
      ruleSet: ruleSet,
      workRuleSettings: workRuleSettings,
    );
    if (requiredBreakMinutes > shift.breakMinutes.round()) {
      violations.add(
        ComplianceViolation(
          code: 'break_required',
          severity: ComplianceSeverity.blocking,
          message:
              'Fuer ${_formatHours(durationMinutes)} Arbeitszeit sind mindestens $requiredBreakMinutes Minuten Pause erforderlich.',
        ),
      );
    }

    final shiftsSameDay = [
      ...sameUserExisting,
      ...sameUserDraft,
    ]
        .where((candidate) => _isSameDay(candidate.startTime, shift.startTime))
        .toList();
    final plannedDayMinutes = shiftsSameDay.fold<int>(
      durationMinutes,
      (sum, candidate) => sum + candidate.workedHours.round() * 60,
    );
    final maxDailyMinutes = _maxDailyMinutes(contract, ruleSet);
    if (workRuleSettings.enforceMaxDailyMinutes &&
        plannedDayMinutes > maxDailyMinutes) {
      violations.add(
        ComplianceViolation(
          code: 'daily_limit',
          severity: ComplianceSeverity.blocking,
          message:
              'Mit dieser Schicht wuerde ${shift.employeeName} ${_formatHours(plannedDayMinutes)} an einem Tag erreichen. Erlaubt sind ${_formatHours(maxDailyMinutes)}.',
        ),
      );
    } else if (workRuleSettings.warnDailyAverageExceeded &&
        plannedDayMinutes > 8 * 60) {
      violations.add(
        const ComplianceViolation(
          code: 'daily_average_warning',
          severity: ComplianceSeverity.warning,
          message:
              'Die Tagesarbeitszeit liegt ueber 8 Stunden und sollte im Ausgleichszeitraum beobachtet werden.',
        ),
      );
    }

    final restViolations = _restViolations(
      shift: shift,
      candidateShifts: [...sameUserExisting, ...sameUserDraft],
      ruleSet: ruleSet,
      travelTimeRules: travelTimeRules,
      siteAssignments: siteAssignments,
      contract: contract,
      workRuleSettings: workRuleSettings,
    );
    violations.addAll(restViolations);

    if (contract != null &&
        workRuleSettings.enforceMinijobLimit &&
        contract.type == EmploymentType.miniJob &&
        contract.hourlyRate > 0) {
      final monthlyMinutes = [
        ...sameUserExisting,
        ...sameUserDraft,
      ]
          .where((candidate) =>
              candidate.startTime.year == shift.startTime.year &&
              candidate.startTime.month == shift.startTime.month)
          .fold<int>(durationMinutes,
              (sum, candidate) => sum + candidate.workedHours.round() * 60);
      final projectedCents = ((monthlyMinutes / 60) * contract.hourlyRate * 100).round();
      final monthlyLimit =
          contract.monthlyIncomeLimitCents ?? ruleSet.minijobMonthlyLimitCents;
      if (projectedCents > monthlyLimit) {
        violations.add(
          ComplianceViolation(
            code: 'minijob_limit',
            severity: ComplianceSeverity.blocking,
            message:
                'Die geplanten Stunden wuerden die Minijob-Grenze von ${(monthlyLimit / 100).toStringAsFixed(0)} EUR ueberschreiten.',
          ),
        );
      }
    }

    if (contract?.isMinor == true) {
      if (_overlapsRestrictedMinorNightWindow(shift)) {
        violations.add(
          const ComplianceViolation(
            code: 'minor_night_work',
            severity: ComplianceSeverity.blocking,
            message:
                'Jugendliche duerfen in diesem Zeitfenster nicht eingeplant werden.',
          ),
        );
      }
      if (plannedDayMinutes > 8 * 60) {
        violations.add(
          const ComplianceViolation(
            code: 'minor_daily_limit',
            severity: ComplianceSeverity.blocking,
            message: 'Jugendliche duerfen maximal 8 Stunden pro Tag arbeiten.',
          ),
        );
      }
    }

    if (contract?.isPregnant == true) {
      if (_overlapsPregnancyNightWindow(shift)) {
        violations.add(
          const ComplianceViolation(
            code: 'pregnancy_night_work',
            severity: ComplianceSeverity.blocking,
            message: 'Nachtschichten sind fuer diesen Vertrag nicht zulaessig.',
          ),
        );
      }
      if (plannedDayMinutes > 510) {
        violations.add(
          const ComplianceViolation(
            code: 'pregnancy_daily_limit',
            severity: ComplianceSeverity.blocking,
            message:
                'Fuer diesen Vertrag gilt eine Tagesgrenze von 8,5 Stunden.',
          ),
        );
      }
    }

    final previousShift = [...sameUserExisting, ...sameUserDraft]
        .where((candidate) => candidate.endTime.isBefore(shift.startTime))
        .sorted((a, b) => b.endTime.compareTo(a.endTime))
        .firstOrNull;
    if (previousShift != null &&
        ruleSet.warnForwardRotation &&
        workRuleSettings.warnForwardRotation) {
      final previousBucket = _shiftBucket(previousShift.startTime);
      final currentBucket = _shiftBucket(shift.startTime);
      if (currentBucket < previousBucket) {
        violations.add(
          const ComplianceViolation(
            code: 'forward_rotation_warning',
            severity: ComplianceSeverity.warning,
            message:
                'Die Abfolge der Schichtarten ist rueckwaerts rotiert. Vorwaertsrotation ist ergonomischer.',
          ),
        );
      }
    }

    if (workRuleSettings.warnOvertime &&
        contract != null &&
        contract.dailyHours > 0) {
      final targetMinutes = (contract.dailyHours * 60).round();
      if (plannedDayMinutes > targetMinutes) {
        violations.add(
          ComplianceViolation(
            code: 'overtime_warning',
            severity: ComplianceSeverity.warning,
            message:
                'Die Schicht fuehrt voraussichtlich zu Ueberstunden gegenueber ${contract.dailyHours.toStringAsFixed(1)} Sollstunden.',
          ),
        );
      }
    }

    if (workRuleSettings.warnSundayWork &&
        shift.startTime.weekday == DateTime.sunday) {
      violations.add(
        const ComplianceViolation(
          code: 'sunday_work_warning',
          severity: ComplianceSeverity.warning,
          message:
              'Sonntagsarbeit erfordert Ersatzruhetage und gesonderte Pruefung.',
        ),
      );
    }

    if (member == null && !shift.isUnassigned) {
      violations.add(
        const ComplianceViolation(
          code: 'member_missing',
          severity: ComplianceSeverity.warning,
          message:
              'Das Mitarbeiterprofil konnte fuer die Regelpruefung nicht vollstaendig geladen werden.',
        ),
      );
    }

    return violations;
  }

  List<ComplianceViolation> validateWorkEntry({
    required WorkEntry entry,
    required List<WorkEntry> existingEntries,
    required List<EmploymentContract> contracts,
    required List<EmployeeSiteAssignment> siteAssignments,
    required List<ComplianceRuleSet> ruleSets,
    required List<TravelTimeRule> travelTimeRules,
    AppUserProfile? member,
  }) {
    final violations = <ComplianceViolation>[];
    final contract = _activeContract(
      contracts: contracts,
      userId: entry.userId,
      at: entry.startTime,
    );
    final workRuleSettings = _workRuleSettingsFor(member);
    final ruleSet = _resolveRuleSet(
      ruleSets: ruleSets,
      siteId: entry.siteId,
      contract: contract,
    );
    final assignment = siteAssignments.firstWhereOrNull(
      (item) => item.userId == entry.userId && item.siteId == entry.siteId,
    );
    final sameUserEntries = existingEntries
        .where((candidate) => candidate.id != entry.id)
        .toList(growable: false);

    if (!entry.endTime.isAfter(entry.startTime)) {
      violations.add(
        const ComplianceViolation(
          code: 'invalid_range',
          severity: ComplianceSeverity.blocking,
          message: 'Das Ende muss nach dem Start liegen.',
        ),
      );
    }

    if (entry.siteId?.trim().isEmpty ?? true) {
      violations.add(
        const ComplianceViolation(
          code: 'site_required',
          severity: ComplianceSeverity.blocking,
          message: 'Zeiteintraege muessen einem Standort zugeordnet sein.',
        ),
      );
    }

    if (assignment == null && (entry.siteId?.trim().isNotEmpty ?? false)) {
      violations.add(
        const ComplianceViolation(
          code: 'site_assignment_missing',
          severity: ComplianceSeverity.blocking,
          message:
              'Der Mitarbeiter ist dem gewaehlten Standort nicht zugeordnet.',
        ),
      );
    }

    final overlappingEntries = sameUserEntries
        .where((candidate) => _entriesOverlap(candidate, entry))
        .toList(growable: false);
    if (overlappingEntries.isNotEmpty) {
      violations.add(
        ComplianceViolation(
          code: 'overlap_existing',
          severity: ComplianceSeverity.blocking,
          message:
              'Dieser Eintrag ueberschneidet sich mit einem bestehenden Zeiteintrag am ${_formatDateTime(overlappingEntries.first.startTime)}.',
          relatedEntityIds: overlappingEntries
              .map((item) => item.id)
              .whereType<String>()
              .toList(growable: false),
        ),
      );
    }

    final workedMinutes = entry.endTime.difference(entry.startTime).inMinutes -
        entry.breakMinutes.round();
    final requiredBreakMinutes = _requiredBreakMinutes(
      workedMinutes: workedMinutes,
      ruleSet: ruleSet,
      workRuleSettings: workRuleSettings,
    );
    if (requiredBreakMinutes > entry.breakMinutes.round()) {
      violations.add(
        ComplianceViolation(
          code: 'break_required',
          severity: ComplianceSeverity.blocking,
          message:
              'Fuer ${_formatHours(workedMinutes)} Arbeitszeit sind mindestens $requiredBreakMinutes Minuten Pause erforderlich.',
        ),
      );
    }

    final sameDayMinutes = sameUserEntries
        .where((candidate) => _isSameDay(candidate.startTime, entry.startTime))
        .fold<int>(workedMinutes,
            (sum, candidate) => sum + candidate.workedHours.round() * 60);
    final maxDailyMinutes = _maxDailyMinutes(contract, ruleSet);
    if (workRuleSettings.enforceMaxDailyMinutes &&
        sameDayMinutes > maxDailyMinutes) {
      violations.add(
        ComplianceViolation(
          code: 'daily_limit',
          severity: ComplianceSeverity.blocking,
          message:
              'Mit diesem Eintrag wird die Tagesgrenze von ${_formatHours(maxDailyMinutes)} ueberschritten.',
        ),
      );
    } else if (workRuleSettings.warnDailyAverageExceeded &&
        sameDayMinutes > 8 * 60) {
      violations.add(
        const ComplianceViolation(
          code: 'daily_average_warning',
          severity: ComplianceSeverity.warning,
          message:
              'Die Tagesarbeitszeit liegt ueber 8 Stunden und sollte im Ausgleichszeitraum beobachtet werden.',
        ),
      );
    }

    final previousEntry = sameUserEntries
        .where((candidate) => candidate.endTime.isBefore(entry.startTime))
        .sorted((a, b) => b.endTime.compareTo(a.endTime))
        .firstOrNull;
    if (previousEntry != null) {
      violations.addAll(
        _singleWorkEntryRestGapViolations(
          earlier: previousEntry,
          later: entry,
          ruleSet: ruleSet,
          travelTimeRules: travelTimeRules,
          siteAssignments: siteAssignments,
          contract: contract,
          workRuleSettings: workRuleSettings,
        ),
      );
    }
    final nextEntry = sameUserEntries
        .where((candidate) => candidate.startTime.isAfter(entry.endTime))
        .sorted((a, b) => a.startTime.compareTo(b.startTime))
        .firstOrNull;
    if (nextEntry != null) {
      violations.addAll(
        _singleWorkEntryRestGapViolations(
          earlier: entry,
          later: nextEntry,
          ruleSet: ruleSet,
          travelTimeRules: travelTimeRules,
          siteAssignments: siteAssignments,
          contract: contract,
          workRuleSettings: workRuleSettings,
        ),
      );
    }

    if (contract != null &&
        workRuleSettings.enforceMinijobLimit &&
        contract.type == EmploymentType.miniJob &&
        contract.hourlyRate > 0) {
      final monthlyMinutes = sameUserEntries
          .where((candidate) =>
              candidate.startTime.year == entry.startTime.year &&
              candidate.startTime.month == entry.startTime.month)
          .fold<int>(
            workedMinutes,
            (sum, candidate) => sum + candidate.workedHours.round() * 60,
          );
      final projectedCents = ((monthlyMinutes / 60) * contract.hourlyRate * 100).round();
      final monthlyLimit =
          contract.monthlyIncomeLimitCents ?? ruleSet.minijobMonthlyLimitCents;
      if (projectedCents > monthlyLimit) {
        violations.add(
          ComplianceViolation(
            code: 'minijob_limit',
            severity: ComplianceSeverity.blocking,
            message:
                'Die erfassten Stunden wuerden die Minijob-Grenze von ${(monthlyLimit / 100).toStringAsFixed(0)} EUR ueberschreiten.',
          ),
        );
      }
    }

    if (contract?.isMinor == true) {
      if (_entryOverlapsRestrictedMinorNightWindow(entry)) {
        violations.add(
          const ComplianceViolation(
            code: 'minor_night_work',
            severity: ComplianceSeverity.blocking,
            message:
                'Jugendliche duerfen in diesem Zeitfenster nicht arbeiten.',
          ),
        );
      }
      if (sameDayMinutes > 8 * 60) {
        violations.add(
          const ComplianceViolation(
            code: 'minor_daily_limit',
            severity: ComplianceSeverity.blocking,
            message: 'Jugendliche duerfen maximal 8 Stunden pro Tag arbeiten.',
          ),
        );
      }
    }

    if (contract?.isPregnant == true) {
      if (_entryOverlapsPregnancyNightWindow(entry)) {
        violations.add(
          const ComplianceViolation(
            code: 'pregnancy_night_work',
            severity: ComplianceSeverity.blocking,
            message: 'Nachtschichten sind fuer diesen Vertrag nicht zulaessig.',
          ),
        );
      }
      if (sameDayMinutes > 510) {
        violations.add(
          const ComplianceViolation(
            code: 'pregnancy_daily_limit',
            severity: ComplianceSeverity.blocking,
            message:
                'Fuer diesen Vertrag gilt eine Tagesgrenze von 8,5 Stunden.',
          ),
        );
      }
    }

    if (workRuleSettings.warnOvertime &&
        contract != null &&
        contract.dailyHours > 0) {
      final targetMinutes = (contract.dailyHours * 60).round();
      if (sameDayMinutes > targetMinutes) {
        violations.add(
          ComplianceViolation(
            code: 'overtime_warning',
            severity: ComplianceSeverity.warning,
            message:
                'Der Eintrag fuehrt voraussichtlich zu Ueberstunden gegenueber ${contract.dailyHours.toStringAsFixed(1)} Sollstunden.',
          ),
        );
      }
    }

    return violations;
  }

  EmploymentContract? _activeContract({
    required List<EmploymentContract> contracts,
    required String userId,
    required DateTime at,
  }) {
    return contracts
        .where(
            (contract) => contract.userId == userId && contract.isActiveOn(at))
        .sorted((a, b) => b.validFrom.compareTo(a.validFrom))
        .firstOrNull;
  }

  EmployeeSiteAssignment? _assignmentForShift({
    required List<EmployeeSiteAssignment> assignments,
    required Shift shift,
    required String userId,
  }) {
    if (shift.siteId?.trim().isNotEmpty ?? false) {
      return assignments.firstWhereOrNull(
        (item) => item.userId == userId && item.siteId == shift.siteId,
      );
    }
    if (shift.siteName?.trim().isNotEmpty ?? false) {
      final normalized = shift.siteName!.trim().toLowerCase();
      return assignments.firstWhereOrNull(
        (item) =>
            item.userId == userId &&
            item.siteName.trim().toLowerCase() == normalized,
      );
    }
    return null;
  }

  ComplianceRuleSet _resolveRuleSet({
    required List<ComplianceRuleSet> ruleSets,
    required String? siteId,
    required EmploymentContract? contract,
  }) {
    return ruleSets.firstWhereOrNull(
          (item) =>
              item.siteId == siteId && item.employmentType == contract?.type,
        ) ??
        ruleSets.firstWhereOrNull(
          (item) => item.siteId == siteId && item.employmentType == null,
        ) ??
        ruleSets.firstWhereOrNull(
          (item) =>
              item.siteId == null && item.employmentType == contract?.type,
        ) ??
        ruleSets.firstWhereOrNull((item) => item.siteId == null) ??
        ComplianceRuleSet.defaultRetail(contract?.orgId ?? '');
  }

  ComplianceRuleSet resolveRuleSet({
    required List<ComplianceRuleSet> ruleSets,
    required String? siteId,
    required EmploymentContract? contract,
  }) {
    return _resolveRuleSet(
      ruleSets: ruleSets,
      siteId: siteId,
      contract: contract,
    );
  }

  List<ComplianceViolation> _restViolations({
    required Shift shift,
    required List<Shift> candidateShifts,
    required ComplianceRuleSet ruleSet,
    required List<TravelTimeRule> travelTimeRules,
    required List<EmployeeSiteAssignment> siteAssignments,
    required EmploymentContract? contract,
    required WorkRuleSettings workRuleSettings,
  }) {
    if (!workRuleSettings.enforceMinRestTime) {
      return const [];
    }
    final violations = <ComplianceViolation>[];
    final sortedCandidates = [...candidateShifts]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final previous = sortedCandidates
        .where((candidate) => candidate.endTime.isBefore(shift.startTime))
        .sorted((a, b) => b.endTime.compareTo(a.endTime))
        .firstOrNull;
    final next = sortedCandidates
        .where((candidate) => candidate.startTime.isAfter(shift.endTime))
        .sorted((a, b) => a.startTime.compareTo(b.startTime))
        .firstOrNull;

    if (previous != null) {
      violations.addAll(
        _singleRestGapViolations(
          earlier: previous,
          later: shift,
          ruleSet: ruleSet,
          travelTimeRules: travelTimeRules,
          siteAssignments: siteAssignments,
          contract: contract,
        ),
      );
    }
    if (next != null) {
      violations.addAll(
        _singleRestGapViolations(
          earlier: shift,
          later: next,
          ruleSet: ruleSet,
          travelTimeRules: travelTimeRules,
          siteAssignments: siteAssignments,
          contract: contract,
        ),
      );
    }
    return violations;
  }

  List<ComplianceViolation> _singleRestGapViolations({
    required Shift earlier,
    required Shift later,
    required ComplianceRuleSet ruleSet,
    required List<TravelTimeRule> travelTimeRules,
    required List<EmployeeSiteAssignment> siteAssignments,
    required EmploymentContract? contract,
  }) {
    final violations = <ComplianceViolation>[];
    if (!_shouldEnforceRestGap(
      earlierStart: earlier.startTime,
      earlierEnd: earlier.endTime,
      laterStart: later.startTime,
    )) {
      return violations;
    }
    final gapMinutes = later.startTime.difference(earlier.endTime).inMinutes;
    final earlierSiteId = _effectiveSiteId(
      shift: earlier,
      assignments: siteAssignments,
    );
    final laterSiteId = _effectiveSiteId(
      shift: later,
      assignments: siteAssignments,
    );
    final ruleTravel = _findTravelRule(
      travelTimeRules: travelTimeRules,
      fromSiteId: earlierSiteId,
      toSiteId: laterSiteId,
    );
    final minRestMinutes =
        contract?.isMinor == true ? 12 * 60 : ruleSet.minRestMinutes;
    if ((earlierSiteId?.isNotEmpty ?? false) &&
        (laterSiteId?.isNotEmpty ?? false) &&
        earlierSiteId != laterSiteId &&
        ruleTravel == null) {
      violations.add(
        const ComplianceViolation(
          code: 'travel_time_missing',
          severity: ComplianceSeverity.warning,
          message:
              'Zwischen diesen Standorten fehlt eine gepflegte Fahrtzeitregel.',
        ),
      );
    }
    final effectiveGap = gapMinutes -
        (ruleTravel?.countsAsWorkTime == true ? ruleTravel!.travelMinutes : 0);
    if (effectiveGap < minRestMinutes) {
      violations.add(
        ComplianceViolation(
          code: 'rest_time',
          severity: ComplianceSeverity.blocking,
          message:
              'Zwischen ${_formatDateTime(earlier.endTime)} und ${_formatDateTime(later.startTime)} liegen nur ${_formatHours(effectiveGap)} Ruhezeit.',
        ),
      );
    }
    return violations;
  }

  String? _effectiveSiteId({
    required Shift shift,
    required List<EmployeeSiteAssignment> assignments,
  }) {
    if (shift.siteId?.trim().isNotEmpty ?? false) {
      return shift.siteId!.trim();
    }
    return _assignmentForShift(
      assignments: assignments,
      shift: shift,
      userId: shift.userId,
    )?.siteId;
  }

  TravelTimeRule? _findTravelRule({
    required List<TravelTimeRule> travelTimeRules,
    required String? fromSiteId,
    required String? toSiteId,
  }) {
    if (fromSiteId == null || toSiteId == null) {
      return null;
    }
    return travelTimeRules.firstWhereOrNull(
      (item) =>
          item.matches(fromSiteId, toSiteId) ||
          item.matches(toSiteId, fromSiteId),
    );
  }

  int _requiredBreakMinutes({
    required int workedMinutes,
    required ComplianceRuleSet ruleSet,
    required WorkRuleSettings workRuleSettings,
  }) {
    var requiredBreak = 0;
    for (final rule in ruleSet.breakRules
        .sorted((a, b) => a.afterMinutes.compareTo(b.afterMinutes))) {
      if (!_isBreakRuleEnabled(rule, workRuleSettings)) {
        continue;
      }
      if (workedMinutes > rule.afterMinutes) {
        requiredBreak = rule.requiredBreakMinutes;
      }
    }
    return requiredBreak;
  }

  int _maxDailyMinutes(
      EmploymentContract? contract, ComplianceRuleSet ruleSet) {
    final contractLimit = contract?.maxDailyMinutes;
    if (contractLimit != null && contractLimit > 0) {
      return contractLimit;
    }
    return ruleSet.maxPlannedMinutesPerDay;
  }

  bool _overlapsRestrictedMinorNightWindow(Shift shift) {
    return _overlapsNightWindow(
      start: shift.startTime,
      end: shift.endTime,
    );
  }

  bool _overlapsPregnancyNightWindow(Shift shift) {
    return _overlapsNightWindow(
      start: shift.startTime,
      end: shift.endTime,
    );
  }

  List<ComplianceViolation> _singleWorkEntryRestGapViolations({
    required WorkEntry earlier,
    required WorkEntry later,
    required ComplianceRuleSet ruleSet,
    required List<TravelTimeRule> travelTimeRules,
    required List<EmployeeSiteAssignment> siteAssignments,
    required EmploymentContract? contract,
    required WorkRuleSettings workRuleSettings,
  }) {
    if (!workRuleSettings.enforceMinRestTime) {
      return const [];
    }
    final violations = <ComplianceViolation>[];
    if (!_shouldEnforceRestGap(
      earlierStart: earlier.startTime,
      earlierEnd: earlier.endTime,
      laterStart: later.startTime,
    )) {
      return violations;
    }
    final gapMinutes = later.startTime.difference(earlier.endTime).inMinutes;
    final earlierSiteId = _effectiveEntrySiteId(
      entry: earlier,
      assignments: siteAssignments,
    );
    final laterSiteId = _effectiveEntrySiteId(
      entry: later,
      assignments: siteAssignments,
    );
    final ruleTravel = _findTravelRule(
      travelTimeRules: travelTimeRules,
      fromSiteId: earlierSiteId,
      toSiteId: laterSiteId,
    );
    final minRestMinutes =
        contract?.isMinor == true ? 12 * 60 : ruleSet.minRestMinutes;
    if ((earlierSiteId?.isNotEmpty ?? false) &&
        (laterSiteId?.isNotEmpty ?? false) &&
        earlierSiteId != laterSiteId &&
        ruleTravel == null) {
      violations.add(
        const ComplianceViolation(
          code: 'travel_time_missing',
          severity: ComplianceSeverity.warning,
          message:
              'Zwischen diesen Standorten fehlt eine gepflegte Fahrtzeitregel.',
        ),
      );
    }
    final effectiveGap = gapMinutes -
        (ruleTravel?.countsAsWorkTime == true ? ruleTravel!.travelMinutes : 0);
    if (effectiveGap < minRestMinutes) {
      violations.add(
        ComplianceViolation(
          code: 'rest_time',
          severity: ComplianceSeverity.blocking,
          message:
              'Zwischen ${_formatDateTime(earlier.endTime)} und ${_formatDateTime(later.startTime)} liegen nur ${_formatHours(effectiveGap)} Ruhezeit.',
        ),
      );
    }
    return violations;
  }

  String? _effectiveEntrySiteId({
    required WorkEntry entry,
    required List<EmployeeSiteAssignment> assignments,
  }) {
    if (entry.siteId?.trim().isNotEmpty ?? false) {
      return entry.siteId!.trim();
    }
    if (entry.siteName?.trim().isNotEmpty ?? false) {
      final normalized = entry.siteName!.trim().toLowerCase();
      return assignments
          .firstWhereOrNull(
            (item) =>
                item.userId == entry.userId &&
                item.siteName.trim().toLowerCase() == normalized,
          )
          ?.siteId;
    }
    return null;
  }

  bool _entriesOverlap(WorkEntry left, WorkEntry right) {
    return left.startTime.isBefore(right.endTime) &&
        left.endTime.isAfter(right.startTime);
  }

  bool _entryOverlapsRestrictedMinorNightWindow(WorkEntry entry) {
    return _overlapsNightWindow(
      start: entry.startTime,
      end: entry.endTime,
    );
  }

  bool _entryOverlapsPregnancyNightWindow(WorkEntry entry) {
    return _overlapsNightWindow(
      start: entry.startTime,
      end: entry.endTime,
    );
  }

  WorkRuleSettings _workRuleSettingsFor(AppUserProfile? member) {
    return member?.workRuleSettings ?? const WorkRuleSettings();
  }

  bool _isBreakRuleEnabled(
    BreakRule rule,
    WorkRuleSettings workRuleSettings,
  ) {
    if (rule.afterMinutes == 360) {
      return workRuleSettings.enforceBreakAfterSixHours;
    }
    if (rule.afterMinutes == 540) {
      return workRuleSettings.enforceBreakAfterNineHours;
    }
    return true;
  }

  int _shiftBucket(DateTime start) {
    final hour = start.hour;
    if (hour < 12) {
      return 0;
    }
    if (hour < 20) {
      return 1;
    }
    return 2;
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  bool _shouldEnforceRestGap({
    required DateTime earlierStart,
    required DateTime earlierEnd,
    required DateTime laterStart,
  }) {
    if (!_isSameDay(earlierEnd, laterStart)) {
      return true;
    }

    // Tagesruhe soll zwischen Arbeitstagen greifen. Zwei getrennte Eintraege
    // am selben Kalendertag werden hier nicht als neue Ruhezeit gewertet.
    return !_isSameDay(earlierStart, earlierEnd);
  }

  bool _overlapsNightWindow({
    required DateTime start,
    required DateTime end,
  }) {
    return start.hour < 6 || end.hour >= 20 || !_isSameDay(start, end);
  }

  String _formatHours(int minutes) {
    return '${(minutes / 60).toStringAsFixed(1)} h';
  }

  String _formatDateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString().padLeft(4, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }
}
