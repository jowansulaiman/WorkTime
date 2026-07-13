import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/local_demo_data.dart';
import 'package:worktime_app/core/local_demo_schedule_data.dart';
import 'package:worktime_app/models/absence_request.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/employment_contract.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/shift_preference.dart';
import 'package:worktime_app/models/shift_swap_request.dart';
import 'package:worktime_app/models/swap_credit.dart';

void main() {
  const orgId = 'demo-org-schedule-test';
  final now = DateTime(2026, 7, 13, 12);

  LocalDemoScheduleDataset build() =>
      LocalDemoScheduleData.datasetForOrg(orgId: orgId, now: now);

  test('Stammdaten decken Rollen, Vertrags- und Vorgabevarianten ab', () {
    final data = build();

    expect(
      data.invites.map((invite) => invite.role).toSet(),
      UserRole.values.toSet(),
    );
    expect(data.invites.any((invite) => invite.isActive), isTrue);
    expect(data.invites.any((invite) => !invite.isActive), isTrue);
    expect(data.invites.any((invite) => invite.isAccepted), isTrue);
    expect(data.invites.any((invite) => !invite.isAccepted), isTrue);

    expect(
      data.employmentContracts.map((contract) => contract.type).toSet(),
      EmploymentType.values.toSet(),
    );
    expect(
      data.employmentContracts.map((contract) => contract.salaryKind).toSet(),
      SalaryKind.values.toSet(),
    );
    expect(
      data.employmentContracts.any((contract) => contract.isMinor),
      isTrue,
    );
    expect(
      data.employmentContracts.any((contract) => contract.isPregnant),
      isTrue,
    );
    expect(
      data.employmentContracts.any((contract) => !contract.isActiveOn(now)),
      isTrue,
    );

    final rules = data.shiftPreferences
        .expand((preference) => preference.rules)
        .toList(growable: false);
    expect(
      rules.map((rule) => rule.kind).toSet(),
      PreferenceKind.values.toSet(),
    );
    expect(
      rules.map((rule) => rule.daypart).whereType<ShiftDaypart>().toSet(),
      ShiftDaypart.values.toSet(),
    );
    expect(rules.any((rule) => rule.daypart == null), isTrue);
    expect(data.travelTimeRules.map((rule) => rule.countsAsWorkTime).toSet(), {
      true,
      false,
    });
  });

  test(
    'Planungsdaten sind im aktuellen Monat und alle Referenzen existieren',
    () {
      final data = build();
      final teamIds = data.teams.map((team) => team.id).toSet();
      final qualificationIds =
          data.qualifications.map((qualification) => qualification.id).toSet();
      final siteIds = {
        LocalDemoData.tabakSiteId(orgId),
        LocalDemoData.strichmaennchenSiteId(orgId),
        LocalDemoData.paketshopSiteId(orgId),
      };

      expect(qualificationIds, {
        'demo-qualification-$orgId-lotto',
        'demo-qualification-$orgId-hygiene',
        'demo-qualification-$orgId-first-aid',
      });
      expect(
        data.shifts.map((shift) => shift.status).toSet(),
        ShiftStatus.values.toSet(),
      );
      expect(
        data.shifts.map((shift) => shift.recurrencePattern).toSet(),
        RecurrencePattern.values.toSet(),
      );
      expect(data.shifts.any((shift) => shift.isUnassigned), isTrue);
      expect(
        data.shifts.any(
          (shift) =>
              shift.startTime.day != shift.endTime.day &&
              shift.endTime.isAfter(shift.startTime),
        ),
        isTrue,
      );
      expect(
        data.shifts.every(
          (shift) =>
              shift.startTime.year == now.year &&
              shift.startTime.month == now.month,
        ),
        isTrue,
      );

      for (final shift in data.shifts) {
        if (shift.teamId != null) expect(teamIds, contains(shift.teamId));
        if (shift.siteId != null) expect(siteIds, contains(shift.siteId));
        for (final qualificationId in shift.requiredQualificationIds) {
          expect(qualificationIds, contains(qualificationId));
        }
      }
      for (final template in data.shiftTemplates) {
        if (template.teamId != null) expect(teamIds, contains(template.teamId));
        if (template.siteId != null) expect(siteIds, contains(template.siteId));
        for (final qualificationId in template.requiredQualificationIds) {
          expect(qualificationIds, contains(qualificationId));
        }
      }
    },
  );

  test('Abwesenheiten decken Typen, Status, Halbtage, Stunden und eAU ab', () {
    final requests = build().absenceRequests;

    expect(
      requests.map((request) => request.type).toSet(),
      AbsenceType.values.toSet(),
    );
    expect(
      requests.map((request) => request.status).toSet(),
      AbsenceStatus.values.toSet(),
    );
    expect(
      requests
          .where((request) => request.halfDay)
          .map((request) => request.halfDayPeriod)
          .whereType<HalfDayPeriod>()
          .toSet(),
      HalfDayPeriod.values.toSet(),
    );
    expect(
      requests
          .where((request) => request.type == AbsenceType.sickness)
          .map((request) => request.eauAttached)
          .toSet(),
      {true, false},
    );
    expect(
      requests
          .singleWhere((request) => request.type == AbsenceType.timeOff)
          .durationHours,
      4.5,
    );
    expect(
      requests.every(
        (request) =>
            request.startDate.year == now.year &&
            request.startDate.month == now.month,
      ),
      isTrue,
    );
  });

  test(
    'Tauschanfragen und Gutschriften bilden alle Status mit gueltigen FKs ab',
    () {
      final data = build();
      final shiftIds = data.shifts.map((shift) => shift.id).toSet();
      final requestIds =
          data.shiftSwapRequests.map((request) => request.id).toSet();

      expect(
        data.shiftSwapRequests.map((request) => request.status).toSet(),
        SwapStatus.values.toSet(),
      );
      expect(
        data.shiftSwapRequests.map((request) => request.kind).toSet(),
        SwapKind.values.toSet(),
      );
      for (final request in data.shiftSwapRequests) {
        expect(shiftIds, contains(request.requesterShiftId));
        if (request.kind == SwapKind.exchange) {
          expect(request.targetShiftId, isNotNull);
          expect(shiftIds, contains(request.targetShiftId));
          expect(request.targetShiftStart, isNotNull);
        } else {
          expect(request.targetShiftId, isNull);
          expect(request.targetShiftStart, isNull);
        }
      }

      expect(
        data.swapCredits.map((credit) => credit.status).toSet(),
        SwapCreditStatus.values.toSet(),
      );
      for (final credit in data.swapCredits) {
        expect(requestIds, contains(credit.originSwapRequestId));
        if (credit.settledBySwapRequestId != null) {
          expect(requestIds, contains(credit.settledBySwapRequestId));
        }
      }
      final origin = data.shiftSwapRequests.singleWhere(
        (request) => request.id == data.swapCredits.first.originSwapRequestId,
      );
      expect(origin.status, SwapStatus.confirmed);
      expect(origin.kind, SwapKind.giveAway);
    },
  );

  test('gleicher Anker erzeugt dieselben stabilen IDs', () {
    final first = build();
    final second = build();

    expect(
      first.shifts.map((shift) => shift.id),
      second.shifts.map((shift) => shift.id),
    );
    expect(
      first.absenceRequests.map((request) => request.id),
      second.absenceRequests.map((request) => request.id),
    );
    expect(
      first.shiftSwapRequests.map((request) => request.id),
      second.shiftSwapRequests.map((request) => request.id),
    );
  });
}
