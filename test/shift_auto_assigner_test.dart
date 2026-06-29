import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/shift_auto_assigner.dart';
import 'package:worktime_app/models/absence_request.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/compliance_rule_set.dart';
import 'package:worktime_app/models/employee_site_assignment.dart';
import 'package:worktime_app/models/employment_contract.dart';
import 'package:worktime_app/models/org_settings.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/shift_preference.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/services/compliance_service.dart';

void main() {
  const service = ComplianceService();
  final ruleSets = [ComplianceRuleSet.defaultRetail('org-1')];

  // Woche 1 Montag, Woche 2 Montag (deterministisch).
  final monday = DateTime(2026, 6, 1).subtract(
    Duration(days: DateTime(2026, 6, 1).weekday - 1),
  );
  final tuesday = monday.add(const Duration(days: 1));
  final wednesday = monday.add(const Duration(days: 2));
  final nextMonday = monday.add(const Duration(days: 7));

  final hardSettings = OrgSettings.defaults('org-1'); // enforceHourCapHard=true
  const softSettings = OrgSettings(orgId: 'org-1', enforceHourCapHard: false);

  AppUserProfile member(String uid,
          {bool active = true, bool enforceMinijob = true}) =>
      AppUserProfile(
        uid: uid,
        orgId: 'org-1',
        email: '$uid@example.com',
        role: UserRole.employee,
        isActive: active,
        settings: UserSettings(name: uid),
        workRuleSettings: WorkRuleSettings(enforceMinijobLimit: enforceMinijob),
      );

  EmploymentContract contract(
    String uid, {
    EmploymentType type = EmploymentType.fullTime,
    double hourlyRate = 0,
    double? monthlyMaxHours,
    double? weeklyMaxHours,
    int? monthlyIncomeLimitCents,
    double weeklyHours = 40,
  }) =>
      EmploymentContract(
        id: 'c-$uid',
        orgId: 'org-1',
        userId: uid,
        type: type,
        validFrom: DateTime(2020, 1, 1),
        dailyHours: 8,
        weeklyHours: weeklyHours,
        hourlyRate: hourlyRate,
        monthlyMaxHours: monthlyMaxHours,
        weeklyMaxHours: weeklyMaxHours,
        monthlyIncomeLimitCents: monthlyIncomeLimitCents,
      );

  EmployeeSiteAssignment assignment(
    String uid, {
    String siteId = 'site-1',
    List<String> qualis = const [],
    bool primary = false,
  }) =>
      EmployeeSiteAssignment(
        id: 'a-$uid-$siteId',
        orgId: 'org-1',
        userId: uid,
        siteId: siteId,
        siteName: 'Laden',
        qualificationIds: qualis,
        isPrimary: primary,
      );

  Shift openShift(
    String id, {
    DateTime? start,
    int hours = 6,
    String siteId = 'site-1',
    List<String> qualis = const [],
  }) {
    final s = start ?? monday.add(const Duration(hours: 8));
    return Shift(
      id: id,
      orgId: 'org-1',
      userId: '',
      employeeName: '',
      title: 'Laden',
      startTime: s,
      endTime: s.add(Duration(hours: hours)),
      siteId: siteId,
      siteName: 'Laden',
      requiredQualificationIds: qualis,
    );
  }

  Shift assignedShift(
    String id,
    String uid, {
    DateTime? start,
    int hours = 6,
  }) {
    final s = start ?? monday.add(const Duration(hours: 8));
    return Shift(
      id: id,
      orgId: 'org-1',
      userId: uid,
      employeeName: uid,
      title: 'Laden',
      startTime: s,
      endTime: s.add(Duration(hours: hours)),
      siteId: 'site-1',
      siteName: 'Laden',
    );
  }

  AbsenceRequest absence(
    String uid, {
    required AbsenceType type,
    required AbsenceStatus status,
    DateTime? day,
  }) {
    final d = day ?? monday;
    return AbsenceRequest(
      orgId: 'org-1',
      userId: uid,
      employeeName: uid,
      startDate: d,
      endDate: d,
      type: type,
      status: status,
    );
  }

  ShiftPreferenceRule rule(
    PreferenceKind kind, {
    ShiftDaypart? daypart,
    Set<int> weekdays = const {},
  }) =>
      ShiftPreferenceRule(
        kind: kind,
        weekdays: weekdays,
        startMinute: daypart?.startMinute ?? 0,
        endMinute: daypart?.endMinute ?? 24 * 60,
        daypart: daypart,
      );

  EmployeeShiftPreference pref(String uid, List<ShiftPreferenceRule> rules) =>
      EmployeeShiftPreference(orgId: 'org-1', userId: uid, rules: rules);

  AutoAssignmentResult run({
    required List<Shift> open,
    required List<AppUserProfile> members,
    List<EmploymentContract> contracts = const [],
    List<EmployeeSiteAssignment> assignments = const [],
    List<AbsenceRequest> absences = const [],
    List<Shift> existing = const [],
    OrgSettings? settings,
    Map<String, EmployeeShiftPreference> preferences = const {},
    double preferenceWeight = 0,
  }) =>
      ShiftAutoAssigner(
        openShifts: open,
        members: members,
        contracts: contracts,
        siteAssignments: assignments,
        approvedAbsences: absences,
        existingAssignedShifts: existing,
        ruleSets: ruleSets,
        travelTimeRules: const [],
        complianceService: service,
        settings: settings ?? hardSettings,
        preferencesByUserId: preferences,
        preferenceWeight: preferenceWeight,
      ).assign();

  test('1. Happy Path: 2 Schichten, 2 Kandidaten → beide besetzt', () {
    final result = run(
      open: [openShift('s1'), openShift('s2')],
      members: [member('u1'), member('u2')],
      contracts: [contract('u1'), contract('u2')],
      assignments: [assignment('u1'), assignment('u2')],
    );
    expect(result.assignments, hasLength(2));
    expect(result.unassigned, isEmpty);
    expect(
      result.assignments.map((a) => a.userId).toSet(),
      {'u1', 'u2'},
    );
  });

  test('2. Monats-Cap hart: ausgelasteter Kandidat raus, anderer übernimmt', () {
    final result = run(
      open: [openShift('s1', start: monday.add(const Duration(hours: 8)))],
      members: [member('u1'), member('u2')],
      contracts: [contract('u1', monthlyMaxHours: 6), contract('u2')],
      assignments: [assignment('u1'), assignment('u2')],
      existing: [assignedShift('e1', 'u1', start: tuesday.add(const Duration(hours: 8)))],
    );
    expect(result.assignments, hasLength(1));
    expect(result.assignments.single.userId, 'u2');
  });

  test('2b. Monats-Cap hart: kein Kandidat übrig → unassigned mit Cap-Grund', () {
    final result = run(
      open: [openShift('s1')],
      members: [member('u1')],
      contracts: [contract('u1', monthlyMaxHours: 6)],
      assignments: [assignment('u1')],
      existing: [assignedShift('e1', 'u1', start: tuesday.add(const Duration(hours: 8)))],
    );
    expect(result.assignments, isEmpty);
    expect(result.unassigned.single.reason, UnassignableReason.monthlyCap);
  });

  test('3. Monats-Cap weich: Zuweisung + Warnung, keine offene Schicht', () {
    final result = run(
      open: [openShift('s1')],
      members: [member('u1')],
      contracts: [contract('u1', monthlyMaxHours: 6)],
      assignments: [assignment('u1')],
      existing: [assignedShift('e1', 'u1', start: tuesday.add(const Duration(hours: 8)))],
      settings: softSettings,
    );
    expect(result.assignments, hasLength(1));
    expect(result.unassigned, isEmpty);
    expect(result.warnings, isNotEmpty);
  });

  test('4. Wochen-Cap hart: gleiche Woche raus, andere Woche zuweisbar', () {
    final result = run(
      open: [
        openShift('sA', start: wednesday.add(const Duration(hours: 8))),
        openShift('sB', start: nextMonday.add(const Duration(hours: 8))),
      ],
      members: [member('u1')],
      contracts: [contract('u1', weeklyMaxHours: 6)],
      assignments: [assignment('u1')],
      existing: [assignedShift('e1', 'u1', start: monday.add(const Duration(hours: 8)))],
    );
    final unassignedA = result.unassigned.singleWhere((u) => u.shiftId == 'sA');
    expect(unassignedA.reason, UnassignableReason.weeklyCap);
    expect(result.assignments.single.shiftId, 'sB');
    expect(result.assignments.single.userId, 'u1');
  });

  test('5. Wochen-Cap weich: überlasteter Kandidat zuletzt gewählt', () {
    final result = run(
      open: [openShift('s1', start: wednesday.add(const Duration(hours: 8)))],
      members: [member('u1'), member('u2')],
      contracts: [
        contract('u1', weeklyMaxHours: 6),
        contract('u2', weeklyMaxHours: 40),
      ],
      assignments: [assignment('u1'), assignment('u2')],
      existing: [assignedShift('e1', 'u1', start: monday.add(const Duration(hours: 8)))],
      settings: softSettings,
    );
    expect(result.assignments.single.userId, 'u2');
  });

  test('6. Toggle-Parität: hart → unassigned, weich → assignment+warning', () {
    List<Shift> open() => [openShift('s1')];
    final shared = {
      'members': [member('u1')],
      'contracts': [contract('u1', monthlyMaxHours: 6)],
      'assignments': [assignment('u1')],
      'existing': [assignedShift('e1', 'u1', start: tuesday.add(const Duration(hours: 8)))],
    };
    final hard = run(
      open: open(),
      members: shared['members'] as List<AppUserProfile>,
      contracts: shared['contracts'] as List<EmploymentContract>,
      assignments: shared['assignments'] as List<EmployeeSiteAssignment>,
      existing: shared['existing'] as List<Shift>,
      settings: hardSettings,
    );
    final soft = run(
      open: open(),
      members: shared['members'] as List<AppUserProfile>,
      contracts: shared['contracts'] as List<EmploymentContract>,
      assignments: shared['assignments'] as List<EmployeeSiteAssignment>,
      existing: shared['existing'] as List<Shift>,
      settings: softSettings,
    );
    expect(hard.assignments, isEmpty);
    expect(hard.unassigned.single.reason, UnassignableReason.monthlyCap);
    expect(soft.assignments, hasLength(1));
    expect(soft.warnings, isNotEmpty);
  });

  test('7. Urlaub blockiert', () {
    final result = run(
      open: [openShift('s1')],
      members: [member('u1')],
      contracts: [contract('u1')],
      assignments: [assignment('u1')],
      absences: [
        absence('u1', type: AbsenceType.vacation, status: AbsenceStatus.approved),
      ],
    );
    expect(result.unassigned.single.reason, UnassignableReason.absence);
  });

  test('8. Krankheit blockiert', () {
    final result = run(
      open: [openShift('s1')],
      members: [member('u1')],
      contracts: [contract('u1')],
      assignments: [assignment('u1')],
      absences: [
        absence('u1', type: AbsenceType.sickness, status: AbsenceStatus.approved),
      ],
    );
    expect(result.unassigned.single.reason, UnassignableReason.absence);
  });

  test('9. Pending blockiert NICHT', () {
    final result = run(
      open: [openShift('s1')],
      members: [member('u1')],
      contracts: [contract('u1')],
      assignments: [assignment('u1')],
      absences: [
        absence('u1', type: AbsenceType.vacation, status: AbsenceStatus.pending),
      ],
    );
    expect(result.assignments, hasLength(1));
    expect(result.unassigned, isEmpty);
  });

  test('10. Quali fehlt → raus', () {
    final result = run(
      open: [openShift('s1', qualis: const ['kasse'])],
      members: [member('u1')],
      contracts: [contract('u1')],
      assignments: [assignment('u1', qualis: const [])],
    );
    expect(result.unassigned.single.reason, UnassignableReason.qualification);
  });

  test('11. Standort-Berechtigung fehlt → raus', () {
    final result = run(
      open: [openShift('s1')],
      members: [member('u1')],
      contracts: [contract('u1')],
      assignments: const [],
    );
    expect(result.unassigned.single.reason, UnassignableReason.site);
  });

  test('12. Minijob-Verdienstgrenze bleibt hart (auch im weichen Modus)', () {
    final result = run(
      open: [openShift('s1', start: monday.add(const Duration(hours: 8)))],
      members: [member('u1', enforceMinijob: false)],
      contracts: [
        contract('u1',
            type: EmploymentType.miniJob,
            hourlyRate: 60,
            monthlyIncomeLimitCents: 60300),
      ],
      assignments: [assignment('u1')],
      existing: [assignedShift('e1', 'u1', start: tuesday.add(const Duration(hours: 8)))],
      settings: softSettings,
    );
    expect(result.assignments, isEmpty);
    expect(result.unassigned.single.reason, UnassignableReason.minijob);
  });

  test('13. Compliance minRest 660 → raus', () {
    final result = run(
      open: [openShift('s1', start: tuesday.add(const Duration(hours: 6)), hours: 6)],
      members: [member('u1')],
      contracts: [contract('u1')],
      assignments: [assignment('u1')],
      existing: [
        assignedShift('e1', 'u1',
            start: monday.add(const Duration(hours: 20)), hours: 3),
      ],
    );
    expect(result.unassigned.single.reason, UnassignableReason.compliance);
  });

  test('14. Doppelbelegung → raus', () {
    final result = run(
      open: [openShift('s1', start: monday.add(const Duration(hours: 10)))],
      members: [member('u1')],
      contracts: [contract('u1')],
      assignments: [assignment('u1')],
      existing: [assignedShift('e1', 'u1', start: monday.add(const Duration(hours: 8)))],
    );
    expect(result.unassigned.single.reason, UnassignableReason.doubleBooking);
  });

  test('15a. Fairness: unterausgelasteter Kandidat gewinnt', () {
    final existing = [
      for (var i = 0; i < 5; i++)
        assignedShift('e$i', 'u1',
            start: monday.add(Duration(days: i, hours: 8))),
    ];
    final result = run(
      open: [openShift('s1', start: nextMonday.add(const Duration(hours: 8)))],
      members: [member('u1'), member('u2')],
      contracts: [
        contract('u1', monthlyMaxHours: 40),
        contract('u2', monthlyMaxHours: 40),
      ],
      assignments: [assignment('u1'), assignment('u2')],
      existing: existing,
    );
    expect(result.assignments.single.userId, 'u2');
  });

  test('15b. Tie-Break nach userId (lexikografisch)', () {
    final result = run(
      open: [openShift('s1')],
      members: [member('u2'), member('u1')],
      contracts: [contract('u1'), contract('u2')],
      assignments: [assignment('u1'), assignment('u2')],
    );
    expect(result.assignments.single.userId, 'u1');
  });

  test('16. Determinismus: gleicher Input → identisches Ergebnis', () {
    AutoAssignmentResult once() => run(
          open: [openShift('s1'), openShift('s2')],
          members: [member('u1'), member('u2')],
          contracts: [contract('u1'), contract('u2')],
          assignments: [assignment('u1'), assignment('u2')],
        );
    final a = once();
    final b = once();
    expect(a.assignments.length, b.assignments.length);
    for (var i = 0; i < a.assignments.length; i++) {
      expect(a.assignments[i].shiftId, b.assignments[i].shiftId);
      expect(a.assignments[i].userId, b.assignments[i].userId);
    }
  });

  // --- Optimierer-Mehrwert gegenüber dem früheren Start-Zeit-Greedy ----------

  test('17. MRV: schwer besetzbarer Slot zuerst (Greedy würde stranden)', () {
    // u1 darf site-1 + site-2, u2 nur site-1. u1 hat Wochengrenze 6h (genau eine
    // 6h-Schicht/Woche). s1 (Mo, site-1) kann u1 ODER u2; s2 (Di, site-2) NUR u1.
    // Ein start-zeit-sortierter Greedy nähme u1 (gleichwertiger Score, kleinere
    // uid) für s1 → s2 bliebe unbesetzbar. MRV besetzt s2 (1 Kandidat) zuerst.
    final result = run(
      open: [
        openShift('s1', start: monday.add(const Duration(hours: 8))),
        openShift('s2',
            start: tuesday.add(const Duration(hours: 8)), siteId: 'site-2'),
      ],
      members: [member('u1'), member('u2')],
      contracts: [
        contract('u1', weeklyMaxHours: 6),
        contract('u2', weeklyMaxHours: 40),
      ],
      assignments: [
        assignment('u1', siteId: 'site-1'),
        assignment('u1', siteId: 'site-2'),
        assignment('u2', siteId: 'site-1'),
      ],
    );
    expect(result.unassigned, isEmpty);
    expect(result.assignments, hasLength(2));
    expect(result.assignments.firstWhere((a) => a.shiftId == 's2').userId, 'u1');
    expect(result.assignments.firstWhere((a) => a.shiftId == 's1').userId, 'u2');
  });

  test('18. Fairness-Lokalsuche: gleichmäßige Verteilung statt Klumpung', () {
    final days = [
      monday,
      tuesday,
      wednesday,
      monday.add(const Duration(days: 3)),
    ];
    final result = run(
      open: [
        for (var i = 0; i < days.length; i++)
          openShift('s$i', start: days[i].add(const Duration(hours: 8))),
      ],
      members: [member('u1'), member('u2')],
      contracts: [contract('u1'), contract('u2')],
      assignments: [assignment('u1'), assignment('u2')],
    );
    expect(result.assignments, hasLength(4));
    final perUser = <String, int>{};
    for (final a in result.assignments) {
      perUser[a.userId] = (perUser[a.userId] ?? 0) + 1;
    }
    expect(perUser['u1'], 2);
    expect(perUser['u2'], 2);
  });

  test('19. Überkapazität: Ejection scheitert sauber → Contention-Grund', () {
    // Drei zeitgleiche Schichten, nur zwei Mitarbeiter: eine bleibt zwingend
    // offen. Da grundsätzlich geeignete (aber verplante) Kandidaten existieren,
    // ist der Grund Contention — nicht ein harter Constraint.
    final result = run(
      open: [openShift('s1'), openShift('s2'), openShift('s3')],
      members: [member('u1'), member('u2')],
      contracts: [contract('u1'), contract('u2')],
      assignments: [assignment('u1'), assignment('u2')],
    );
    expect(result.assignments, hasLength(2));
    expect(result.unassigned, hasLength(1));
    expect(result.unassigned.single.reason, UnassignableReason.contention);
  });

  test('20. Engpass bei Stundengrenzen: volle Abdeckung trotz Cap-Mix', () {
    // u1 (Woche 12h = 2 Schichten), u2 (Woche 6h = 1 Schicht). s3 nur u1.
    // Optimum besetzt alle drei; der Optimierer findet es (u2 für einen der
    // freien Slots, u1 für s3 + den anderen).
    final result = run(
      open: [
        openShift('s1', start: monday.add(const Duration(hours: 8))),
        openShift('s2', start: tuesday.add(const Duration(hours: 8))),
        openShift('s3',
            start: wednesday.add(const Duration(hours: 8)), siteId: 'site-2'),
      ],
      members: [member('u1'), member('u2')],
      contracts: [
        contract('u1', weeklyMaxHours: 12),
        contract('u2', weeklyMaxHours: 6),
      ],
      assignments: [
        assignment('u1', siteId: 'site-1'),
        assignment('u1', siteId: 'site-2'),
        assignment('u2', siteId: 'site-1'),
      ],
    );
    expect(result.unassigned, isEmpty);
    expect(result.assignments, hasLength(3));
    expect(result.assignments.firstWhere((a) => a.shiftId == 's3').userId, 'u1');
  });

  test('21. Determinismus + volle Abdeckung auf größerer Instanz', () {
    AutoAssignmentResult once() => run(
          open: [
            openShift('a', start: monday.add(const Duration(hours: 8))),
            openShift('b', start: tuesday.add(const Duration(hours: 8))),
            openShift('c', start: wednesday.add(const Duration(hours: 8))),
            openShift('d', start: monday.add(const Duration(days: 3, hours: 8))),
            openShift('e', start: monday.add(const Duration(days: 4, hours: 8))),
          ],
          members: [member('u1'), member('u2'), member('u3')],
          contracts: [contract('u1'), contract('u2'), contract('u3')],
          assignments: [assignment('u1'), assignment('u2'), assignment('u3')],
        );
    final a = once();
    final b = once();
    expect(a.unassigned, isEmpty);
    expect(a.assignments, hasLength(5));
    expect(
      a.assignments.map((x) => '${x.shiftId}:${x.userId}').toList(),
      b.assignments.map((x) => '${x.shiftId}:${x.userId}').toList(),
    );
  });

  // --- Mitarbeiter-Vorlieben (weiche Wünsche + harte Sperren) ----------------

  test('22. Sperre ist hart: gesperrte Tageszeit → preferenceBlock', () {
    final result = run(
      open: [openShift('s1', start: monday.add(const Duration(hours: 8)))],
      members: [member('u1')],
      contracts: [contract('u1')],
      assignments: [assignment('u1')],
      preferences: {
        'u1': pref('u1', [rule(PreferenceKind.block, daypart: ShiftDaypart.morning)]),
      },
    );
    expect(result.assignments, isEmpty);
    expect(result.unassigned.single.reason, UnassignableReason.preferenceBlock);
  });

  test('23. Bevorzugung (weich): präferierter Mitarbeiter gewinnt den Slot', () {
    // Ohne Vorliebe gewänne u1 (uid-Tie-Break). u2 bevorzugt Vormittag → u2.
    final result = run(
      open: [openShift('s1', start: monday.add(const Duration(hours: 8)))],
      members: [member('u1'), member('u2')],
      contracts: [contract('u1'), contract('u2')],
      assignments: [assignment('u1'), assignment('u2')],
      preferences: {
        'u2': pref('u2', [rule(PreferenceKind.prefer, daypart: ShiftDaypart.morning)]),
      },
      preferenceWeight: 1.0,
    );
    expect(result.assignments.single.userId, 'u2');
  });

  test('24. Meidung (weich): gemiedener Mitarbeiter unterliegt', () {
    // u1 würde per Tie-Break gewinnen, meidet aber Vormittag → u2 gewinnt.
    final result = run(
      open: [openShift('s1', start: monday.add(const Duration(hours: 8)))],
      members: [member('u1'), member('u2')],
      contracts: [contract('u1'), contract('u2')],
      assignments: [assignment('u1'), assignment('u2')],
      preferences: {
        'u1': pref('u1', [rule(PreferenceKind.avoid, daypart: ShiftDaypart.morning)]),
      },
      preferenceWeight: 1.0,
    );
    expect(result.assignments.single.userId, 'u2');
  });

  test('25. Sperre nur an bestimmten Wochentagen', () {
    // u1 sperrt NUR Montag-Vormittag. Mo bleibt offen, Di wird besetzt.
    final result = run(
      open: [
        openShift('mon', start: monday.add(const Duration(hours: 8))),
        openShift('tue', start: tuesday.add(const Duration(hours: 8))),
      ],
      members: [member('u1')],
      contracts: [contract('u1')],
      assignments: [assignment('u1')],
      preferences: {
        'u1': pref('u1', [
          rule(PreferenceKind.block,
              daypart: ShiftDaypart.morning, weekdays: const {1}),
        ]),
      },
    );
    expect(result.assignments.single.shiftId, 'tue');
    expect(result.assignments.single.userId, 'u1');
    expect(result.unassigned.single.shiftId, 'mon');
    expect(result.unassigned.single.reason, UnassignableReason.preferenceBlock);
  });

  test('26. Sperre bleibt hart auch bei preferenceWeight 0', () {
    final result = run(
      open: [openShift('s1', start: monday.add(const Duration(hours: 8)))],
      members: [member('u1')],
      contracts: [contract('u1')],
      assignments: [assignment('u1')],
      preferences: {
        'u1': pref('u1', [rule(PreferenceKind.block, daypart: ShiftDaypart.morning)]),
      },
      preferenceWeight: 0,
    );
    expect(result.unassigned.single.reason, UnassignableReason.preferenceBlock);
  });
}
