import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/compliance_rule_set.dart';
import 'package:worktime_app/models/employee_site_assignment.dart';
import 'package:worktime_app/models/employment_contract.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/travel_time_rule.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/services/compliance_service.dart';

void main() {
  group('ComplianceService', () {
    const service = ComplianceService();
    final defaultRuleSet = ComplianceRuleSet.defaultRetail('org-1');

    AppUserProfile employee(String uid, String name) {
      return AppUserProfile(
        uid: uid,
        orgId: 'org-1',
        email: '$uid@example.com',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: name),
      );
    }

    EmploymentContract contractFor(
      String userId, {
      EmploymentType type = EmploymentType.fullTime,
      double hourlyRate = 0,
      int? monthlyIncomeLimitCents,
      bool isMinor = false,
      bool isPregnant = false,
    }) {
      return EmploymentContract(
        id: 'contract-$userId',
        orgId: 'org-1',
        userId: userId,
        type: type,
        validFrom: DateTime(2020, 1, 1),
        dailyHours: 8,
        weeklyHours: 40,
        hourlyRate: hourlyRate,
        monthlyIncomeLimitCents: monthlyIncomeLimitCents,
        isMinor: isMinor,
        isPregnant: isPregnant,
      );
    }

    EmployeeSiteAssignment assignmentFor(
      String userId,
      String siteId,
      String siteName, {
      List<String> qualificationIds = const [],
    }) {
      return EmployeeSiteAssignment(
        id: 'assignment-$userId-$siteId',
        orgId: 'org-1',
        userId: userId,
        siteId: siteId,
        siteName: siteName,
        isPrimary: true,
        qualificationIds: qualificationIds,
      );
    }

    test('blocks missing breaks for shifts over six hours', () {
      final shift = Shift(
        orgId: 'org-1',
        userId: 'employee-1',
        employeeName: 'Anna',
        title: 'Fruehdienst',
        startTime: DateTime(2026, 4, 6, 8),
        endTime: DateTime(2026, 4, 6, 16),
        siteId: 'site-1',
        siteName: 'Berlin',
        location: 'Berlin',
      );

      final violations = service.validateShift(
        shift: shift,
        existingShifts: const [],
        draftShifts: [shift],
        absences: const [],
        contracts: [contractFor('employee-1')],
        siteAssignments: [assignmentFor('employee-1', 'site-1', 'Berlin')],
        ruleSets: [defaultRuleSet],
        travelTimeRules: const [],
        members: [employee('employee-1', 'Anna')],
      );

      expect(
        violations.map((item) => item.code),
        contains('break_required'),
      );
    });

    test('can disable the >6h break rule for a specific employee', () {
      final shift = Shift(
        orgId: 'org-1',
        userId: 'employee-1',
        employeeName: 'Anna',
        title: 'Tagdienst',
        startTime: DateTime(2026, 4, 6, 8),
        endTime: DateTime(2026, 4, 6, 15),
        siteId: 'site-1',
        siteName: 'Berlin',
        location: 'Berlin',
      );

      final violations = service.validateShift(
        shift: shift,
        existingShifts: const [],
        draftShifts: [shift],
        absences: const [],
        contracts: [contractFor('employee-1')],
        siteAssignments: [assignmentFor('employee-1', 'site-1', 'Berlin')],
        ruleSets: [defaultRuleSet],
        travelTimeRules: const [],
        members: [
          employee('employee-1', 'Anna').copyWith(
            workRuleSettings: const WorkRuleSettings(
              enforceBreakAfterSixHours: false,
            ),
          ),
        ],
      );

      expect(
        violations.map((item) => item.code),
        isNot(contains('break_required')),
      );
    });

    test('keeps the >9h break rule active when only >6h is disabled', () {
      final shift = Shift(
        orgId: 'org-1',
        userId: 'employee-1',
        employeeName: 'Anna',
        title: 'Langdienst',
        startTime: DateTime(2026, 4, 6, 8),
        endTime: DateTime(2026, 4, 6, 18),
        siteId: 'site-1',
        siteName: 'Berlin',
        location: 'Berlin',
      );

      final violations = service.validateShift(
        shift: shift,
        existingShifts: const [],
        draftShifts: [shift],
        absences: const [],
        contracts: [contractFor('employee-1')],
        siteAssignments: [assignmentFor('employee-1', 'site-1', 'Berlin')],
        ruleSets: [defaultRuleSet],
        travelTimeRules: const [],
        members: [
          employee('employee-1', 'Anna').copyWith(
            workRuleSettings: const WorkRuleSettings(
              enforceBreakAfterSixHours: false,
              enforceBreakAfterNineHours: true,
            ),
          ),
        ],
      );

      expect(
        violations.map((item) => item.code),
        contains('break_required'),
      );
    });

    test('blocks rest time across sites when travel counts as work time', () {
      final previousShift = Shift(
        id: 'existing-1',
        orgId: 'org-1',
        userId: 'employee-1',
        employeeName: 'Anna',
        title: 'Spaetdienst',
        startTime: DateTime(2026, 4, 6, 14),
        endTime: DateTime(2026, 4, 6, 22),
        breakMinutes: 30,
        siteId: 'site-1',
        siteName: 'Berlin',
        location: 'Berlin',
      );
      final nextShift = Shift(
        orgId: 'org-1',
        userId: 'employee-1',
        employeeName: 'Anna',
        title: 'Fruehdienst',
        startTime: DateTime(2026, 4, 7, 8),
        endTime: DateTime(2026, 4, 7, 14),
        siteId: 'site-2',
        siteName: 'Hamburg',
        location: 'Hamburg',
      );

      final violations = service.validateShift(
        shift: nextShift,
        existingShifts: [previousShift],
        draftShifts: [nextShift],
        absences: const [],
        contracts: [contractFor('employee-1')],
        siteAssignments: [
          assignmentFor('employee-1', 'site-1', 'Berlin'),
          assignmentFor('employee-1', 'site-2', 'Hamburg'),
        ],
        ruleSets: [defaultRuleSet],
        travelTimeRules: const [
          TravelTimeRule(
            id: 'travel-1',
            orgId: 'org-1',
            fromSiteId: 'site-1',
            toSiteId: 'site-2',
            travelMinutes: 45,
            countsAsWorkTime: true,
          ),
        ],
        members: [employee('employee-1', 'Anna')],
      );

      expect(
        violations.map((item) => item.code),
        contains('rest_time'),
      );
    });

    test('warns when travel time rule between sites is missing', () {
      final previousShift = Shift(
        id: 'existing-1',
        orgId: 'org-1',
        userId: 'employee-1',
        employeeName: 'Anna',
        title: 'Spaetdienst',
        startTime: DateTime(2026, 4, 6, 12),
        endTime: DateTime(2026, 4, 6, 20),
        breakMinutes: 30,
        siteId: 'site-1',
        siteName: 'Berlin',
        location: 'Berlin',
      );
      final nextShift = Shift(
        orgId: 'org-1',
        userId: 'employee-1',
        employeeName: 'Anna',
        title: 'Fruehdienst',
        startTime: DateTime(2026, 4, 7, 8),
        endTime: DateTime(2026, 4, 7, 14),
        siteId: 'site-2',
        siteName: 'Hamburg',
        location: 'Hamburg',
      );

      final violations = service.validateShift(
        shift: nextShift,
        existingShifts: [previousShift],
        draftShifts: [nextShift],
        absences: const [],
        contracts: [contractFor('employee-1')],
        siteAssignments: [
          assignmentFor('employee-1', 'site-1', 'Berlin'),
          assignmentFor('employee-1', 'site-2', 'Hamburg'),
        ],
        ruleSets: [defaultRuleSet],
        travelTimeRules: const [],
        members: [employee('employee-1', 'Anna')],
      );

      expect(
        violations.map((item) => item.code),
        contains('travel_time_missing'),
      );
    });

    test('resolves travel time rules for legacy shifts without site id', () {
      final previousShift = Shift(
        id: 'existing-1',
        orgId: 'org-1',
        userId: 'employee-1',
        employeeName: 'Anna',
        title: 'Spaetdienst',
        startTime: DateTime(2026, 4, 6, 14),
        endTime: DateTime(2026, 4, 6, 22),
        breakMinutes: 30,
        siteName: 'Berlin',
        location: 'Berlin',
      );
      final nextShift = Shift(
        orgId: 'org-1',
        userId: 'employee-1',
        employeeName: 'Anna',
        title: 'Fruehdienst',
        startTime: DateTime(2026, 4, 7, 8),
        endTime: DateTime(2026, 4, 7, 14),
        siteId: 'site-2',
        siteName: 'Hamburg',
        location: 'Hamburg',
      );

      final violations = service.validateShift(
        shift: nextShift,
        existingShifts: [previousShift],
        draftShifts: [nextShift],
        absences: const [],
        contracts: [contractFor('employee-1')],
        siteAssignments: [
          assignmentFor('employee-1', 'site-1', 'Berlin'),
          assignmentFor('employee-1', 'site-2', 'Hamburg'),
        ],
        ruleSets: [defaultRuleSet],
        travelTimeRules: const [
          TravelTimeRule(
            id: 'travel-1',
            orgId: 'org-1',
            fromSiteId: 'site-1',
            toSiteId: 'site-2',
            travelMinutes: 45,
            countsAsWorkTime: true,
          ),
        ],
        members: [employee('employee-1', 'Anna')],
      );

      expect(
        violations.map((item) => item.code),
        contains('rest_time'),
      );
      expect(
        violations.map((item) => item.code),
        isNot(contains('travel_time_missing')),
      );
    });

    test('blocks projected minijob income above configured monthly limit', () {
      final existingShifts = [
        Shift(
          id: 'existing-1',
          orgId: 'org-1',
          userId: 'employee-1',
          employeeName: 'Ben',
          title: 'Dienst 1',
          startTime: DateTime(2026, 4, 1, 9),
          endTime: DateTime(2026, 4, 1, 15),
          siteId: 'site-1',
          siteName: 'Berlin',
          location: 'Berlin',
        ),
        Shift(
          id: 'existing-2',
          orgId: 'org-1',
          userId: 'employee-1',
          employeeName: 'Ben',
          title: 'Dienst 2',
          startTime: DateTime(2026, 4, 8, 9),
          endTime: DateTime(2026, 4, 8, 15),
          siteId: 'site-1',
          siteName: 'Berlin',
          location: 'Berlin',
        ),
        Shift(
          id: 'existing-3',
          orgId: 'org-1',
          userId: 'employee-1',
          employeeName: 'Ben',
          title: 'Dienst 3',
          startTime: DateTime(2026, 4, 15, 9),
          endTime: DateTime(2026, 4, 15, 15),
          siteId: 'site-1',
          siteName: 'Berlin',
          location: 'Berlin',
        ),
      ];
      final newShift = Shift(
        orgId: 'org-1',
        userId: 'employee-1',
        employeeName: 'Ben',
        title: 'Extra',
        startTime: DateTime(2026, 4, 22, 9),
        endTime: DateTime(2026, 4, 22, 12),
        siteId: 'site-1',
        siteName: 'Berlin',
        location: 'Berlin',
      );

      final violations = service.validateShift(
        shift: newShift,
        existingShifts: existingShifts,
        draftShifts: [newShift],
        absences: const [],
        contracts: [
          contractFor(
            'employee-1',
            type: EmploymentType.miniJob,
            hourlyRate: 30,
            monthlyIncomeLimitCents: 60300,
          ),
        ],
        siteAssignments: [assignmentFor('employee-1', 'site-1', 'Berlin')],
        ruleSets: [defaultRuleSet],
        travelTimeRules: const [],
        members: [employee('employee-1', 'Ben')],
      );

      expect(
        violations.map((item) => item.code),
        contains('minijob_limit'),
      );
    });

    test('blocks overlapping work entries and invalid time ranges', () {
      final entry = WorkEntry(
        id: 'entry-2',
        orgId: 'org-1',
        userId: 'employee-1',
        date: DateTime(2026, 4, 6),
        startTime: DateTime(2026, 4, 6, 11),
        endTime: DateTime(2026, 4, 6, 10),
        siteId: 'site-1',
        siteName: 'Berlin',
      );

      final violations = service.validateWorkEntry(
        entry: entry,
        existingEntries: [
          WorkEntry(
            id: 'entry-1',
            orgId: 'org-1',
            userId: 'employee-1',
            date: DateTime(2026, 4, 6),
            startTime: DateTime(2026, 4, 6, 9),
            endTime: DateTime(2026, 4, 6, 12),
            siteId: 'site-1',
            siteName: 'Berlin',
          ),
        ],
        contracts: [contractFor('employee-1')],
        siteAssignments: [assignmentFor('employee-1', 'site-1', 'Berlin')],
        ruleSets: [defaultRuleSet],
        travelTimeRules: const [],
      );

      expect(violations.map((item) => item.code), contains('invalid_range'));
      expect(
        violations.map((item) => item.code),
        contains('overlap_existing'),
      );
    });

    test('blocks rest time between work entries across sites with travel', () {
      final entry = WorkEntry(
        id: 'entry-2',
        orgId: 'org-1',
        userId: 'employee-1',
        date: DateTime(2026, 4, 7),
        startTime: DateTime(2026, 4, 7, 8),
        endTime: DateTime(2026, 4, 7, 14),
        breakMinutes: 30,
        siteId: 'site-2',
        siteName: 'Hamburg',
      );

      final violations = service.validateWorkEntry(
        entry: entry,
        existingEntries: [
          WorkEntry(
            id: 'entry-1',
            orgId: 'org-1',
            userId: 'employee-1',
            date: DateTime(2026, 4, 6),
            startTime: DateTime(2026, 4, 6, 14),
            endTime: DateTime(2026, 4, 6, 22),
            breakMinutes: 30,
            siteId: 'site-1',
            siteName: 'Berlin',
          ),
        ],
        contracts: [contractFor('employee-1')],
        siteAssignments: [
          assignmentFor('employee-1', 'site-1', 'Berlin'),
          assignmentFor('employee-1', 'site-2', 'Hamburg'),
        ],
        ruleSets: [defaultRuleSet],
        travelTimeRules: const [
          TravelTimeRule(
            id: 'travel-1',
            orgId: 'org-1',
            fromSiteId: 'site-1',
            toSiteId: 'site-2',
            travelMinutes: 45,
            countsAsWorkTime: true,
          ),
        ],
      );

      expect(violations.map((item) => item.code), contains('rest_time'));
    });

    test('does not enforce daily rest between work entries on the same day',
        () {
      final entry = WorkEntry(
        id: 'entry-2',
        orgId: 'org-1',
        userId: 'employee-1',
        date: DateTime(2026, 4, 7),
        startTime: DateTime(2026, 4, 7, 12, 5),
        endTime: DateTime(2026, 4, 7, 16),
        siteId: 'site-1',
        siteName: 'Berlin',
      );

      final violations = service.validateWorkEntry(
        entry: entry,
        existingEntries: [
          WorkEntry(
            id: 'entry-1',
            orgId: 'org-1',
            userId: 'employee-1',
            date: DateTime(2026, 4, 7),
            startTime: DateTime(2026, 4, 7, 8),
            endTime: DateTime(2026, 4, 7, 12),
            siteId: 'site-1',
            siteName: 'Berlin',
          ),
        ],
        contracts: [contractFor('employee-1')],
        siteAssignments: [assignmentFor('employee-1', 'site-1', 'Berlin')],
        ruleSets: [defaultRuleSet],
        travelTimeRules: const [],
      );

      expect(violations.map((item) => item.code), isNot(contains('rest_time')));
    });

    test('still enforces daily rest after an overnight work entry', () {
      final entry = WorkEntry(
        id: 'entry-2',
        orgId: 'org-1',
        userId: 'employee-1',
        date: DateTime(2026, 4, 7),
        startTime: DateTime(2026, 4, 7, 10),
        endTime: DateTime(2026, 4, 7, 14),
        siteId: 'site-1',
        siteName: 'Berlin',
      );

      final violations = service.validateWorkEntry(
        entry: entry,
        existingEntries: [
          WorkEntry(
            id: 'entry-1',
            orgId: 'org-1',
            userId: 'employee-1',
            date: DateTime(2026, 4, 6),
            startTime: DateTime(2026, 4, 6, 20),
            endTime: DateTime(2026, 4, 7, 2),
            siteId: 'site-1',
            siteName: 'Berlin',
          ),
        ],
        contracts: [contractFor('employee-1')],
        siteAssignments: [assignmentFor('employee-1', 'site-1', 'Berlin')],
        ruleSets: [defaultRuleSet],
        travelTimeRules: const [],
      );

      expect(violations.map((item) => item.code), contains('rest_time'));
    });
  });
}
