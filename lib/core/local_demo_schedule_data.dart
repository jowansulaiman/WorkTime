import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/compliance_rule_set.dart';
import '../models/employment_contract.dart';
import '../models/qualification_definition.dart';
import '../models/shift.dart';
import '../models/shift_preference.dart';
import '../models/shift_swap_request.dart';
import '../models/shift_template.dart';
import '../models/swap_credit.dart';
import '../models/team_definition.dart';
import '../models/travel_time_rule.dart';
import '../models/user_invite.dart';
import '../models/user_settings.dart';
import 'local_demo_data.dart';

/// Vollstaendiger, reproduzierbarer Demo-Datensatz fuer Personalplanung.
///
/// Alle IDs sind stabil. Zeitbezogene Datensaetze werden relativ zu [now] im
/// sichtbaren Monat erzeugt, sodass Kalender- und Statusfilter sofort
/// aussagekraeftige Ergebnisse liefern.
class LocalDemoScheduleData {
  LocalDemoScheduleData._();

  static String teamId(String orgId, String slug) => 'demo-team-$orgId-$slug';

  static String qualificationId(String orgId, String slug) =>
      'demo-qualification-$orgId-$slug';

  static String shiftId(String orgId, String slug) => 'demo-shift-$orgId-$slug';

  static String swapRequestId(String orgId, String slug) =>
      'demo-swap-$orgId-$slug';

  static LocalDemoScheduleDataset datasetForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final creator = createdByUid ?? LocalDemoData.adminAccount.uid;
    return LocalDemoScheduleDataset(
      invites: invitesForOrg(orgId: orgId, createdByUid: creator, now: anchor),
      teams: teamsForOrg(orgId: orgId, createdByUid: creator, now: anchor),
      qualifications: qualificationsForOrg(
        orgId: orgId,
        createdByUid: creator,
        now: anchor,
      ),
      employmentContracts: employmentContractsForOrg(
        orgId: orgId,
        createdByUid: creator,
        now: anchor,
      ),
      shiftPreferences: shiftPreferencesForOrg(orgId: orgId, now: anchor),
      travelTimeRules: travelTimeRulesForOrg(
        orgId: orgId,
        createdByUid: creator,
        now: anchor,
      ),
      complianceRuleSets: complianceRuleSetsForOrg(
        orgId: orgId,
        createdByUid: creator,
        now: anchor,
      ),
      shifts: shiftsForOrg(orgId: orgId, createdByUid: creator, now: anchor),
      shiftTemplates: shiftTemplatesForOrg(orgId: orgId),
      absenceRequests: absenceRequestsForOrg(orgId: orgId, now: anchor),
      shiftSwapRequests: shiftSwapRequestsForOrg(orgId: orgId, now: anchor),
      swapCredits: swapCreditsForOrg(orgId: orgId, now: anchor),
    );
  }

  static List<UserInvite> invitesForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    return [
      UserInvite(
        id: 'demo-invite-$orgId-admin-pending',
        orgId: orgId,
        email: 'neue.admin@example.com',
        role: UserRole.admin,
        settings: const UserSettings(
          name: 'Alex Admin',
          dailyHours: 8,
          vacationDays: 30,
        ),
        createdByUid: createdByUid,
        createdAt: anchor.subtract(const Duration(days: 2)),
      ),
      UserInvite(
        id: 'demo-invite-$orgId-teamlead-inactive',
        orgId: orgId,
        email: 'teamleitung.archiv@example.com',
        role: UserRole.teamlead,
        settings: const UserSettings(
          name: 'Robin Teamleitung',
          dailyHours: 7.5,
          vacationDays: 28,
        ),
        createdByUid: createdByUid,
        permissions: const UserPermissions(
          canViewSchedule: true,
          canEditSchedule: true,
          canViewTimeTracking: true,
          canEditTimeEntries: false,
          canViewReports: false,
        ),
        createdAt: anchor.subtract(const Duration(days: 14)),
        isActive: false,
      ),
      UserInvite(
        id: 'demo-invite-$orgId-employee-accepted',
        orgId: orgId,
        email: 'angenommen@example.com',
        role: UserRole.employee,
        settings: const UserSettings(
          name: 'Sam Angenommen',
          hourlyRate: 15.5,
          dailyHours: 6,
          vacationDays: 24,
        ),
        createdByUid: createdByUid,
        createdAt: anchor.subtract(const Duration(days: 21)),
        acceptedByUid: LocalDemoData.employeeSecondAccount.uid,
        acceptedAt: anchor.subtract(const Duration(days: 20)),
        isActive: false,
      ),
    ];
  }

  static List<TeamDefinition> teamsForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final createdAt = anchor.subtract(const Duration(days: 120));
    return [
      TeamDefinition(
        id: teamId(orgId, 'tabak'),
        orgId: orgId,
        name: 'Team Tabak Börse',
        description: 'Früh-, Tages- und Samstagsdienst im Tabakladen.',
        memberIds: [
          LocalDemoData.jowanAccount.uid,
          LocalDemoData.raffaelAccount.uid,
          LocalDemoData.majdAccount.uid,
          LocalDemoData.jarlaAccount.uid,
          LocalDemoData.johannaAccount.uid,
          LocalDemoData.jeanAccount.uid,
          LocalDemoData.employeeAccount.uid,
        ],
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: anchor.subtract(const Duration(days: 4)),
      ),
      TeamDefinition(
        id: teamId(orgId, 'strichmaennchen'),
        orgId: orgId,
        name: 'Team Strichmännchen',
        description: 'Verkauf, Kasse und Ladenschluss.',
        memberIds: [
          LocalDemoData.teamLeadAccount.uid,
          LocalDemoData.majdAccount.uid,
          LocalDemoData.tomAccount.uid,
          LocalDemoData.jarlaAccount.uid,
          LocalDemoData.employeeSecondAccount.uid,
        ],
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: anchor.subtract(const Duration(days: 3)),
      ),
      TeamDefinition(
        id: teamId(orgId, 'paketshop'),
        orgId: orgId,
        name: 'Team Paketshop',
        description: 'Paketannahme, Ausgabe und REWE-Servicepunkt.',
        memberIds: [
          LocalDemoData.jowanAccount.uid,
          LocalDemoData.maikeAccount.uid,
          LocalDemoData.edithAccount.uid,
          LocalDemoData.raffaelAccount.uid,
        ],
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: anchor.subtract(const Duration(days: 2)),
      ),
    ];
  }

  static List<QualificationDefinition> qualificationsForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final createdAt = anchor.subtract(const Duration(days: 100));
    return [
      QualificationDefinition(
        id: qualificationId(orgId, 'lotto'),
        orgId: orgId,
        name: 'Lotto-Annahme',
        description: 'Geschult für Annahme, Auszahlung und Jugendschutz.',
        color: '#1565C0',
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: anchor.subtract(const Duration(days: 5)),
      ),
      QualificationDefinition(
        id: qualificationId(orgId, 'hygiene'),
        orgId: orgId,
        name: 'Hygienebelehrung',
        description: 'Aktuelle Belehrung für Lebensmittel und Verkauf.',
        color: '#2E7D32',
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: anchor.subtract(const Duration(days: 4)),
      ),
      QualificationDefinition(
        id: qualificationId(orgId, 'first-aid'),
        orgId: orgId,
        name: 'Ersthelfer',
        description: 'Betriebliche Erste-Hilfe-Qualifikation.',
        color: '#C62828',
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: anchor.subtract(const Duration(days: 3)),
      ),
    ];
  }

  static List<EmploymentContract> employmentContractsForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final yearStart = DateTime(anchor.year, 1, 1);
    final createdAt = anchor.subtract(const Duration(days: 180));
    return [
      EmploymentContract(
        id: 'demo-contract-$orgId-full-time-monthly',
        orgId: orgId,
        userId: LocalDemoData.jowanAccount.uid,
        label: 'Unbefristete Vollzeit',
        type: EmploymentType.fullTime,
        validFrom: yearStart,
        weeklyHours: 40,
        dailyHours: 8,
        salaryKind: SalaryKind.monthly,
        monthlyGrossCents: 420000,
        vacationDays: 30,
        maxDailyMinutes: 600,
        monthlyMaxHours: 174,
        weeklyMaxHours: 48,
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: anchor.subtract(const Duration(days: 5)),
      ),
      EmploymentContract(
        id: 'demo-contract-$orgId-part-time-hourly',
        orgId: orgId,
        userId: LocalDemoData.employeeAccount.uid,
        label: 'Teilzeit auf Stundenbasis',
        type: EmploymentType.partTime,
        validFrom: yearStart,
        weeklyHours: 24,
        dailyHours: 6,
        hourlyRate: 17.25,
        salaryKind: SalaryKind.hourly,
        vacationDays: 26,
        maxDailyMinutes: 540,
        monthlyMaxHours: 104,
        weeklyMaxHours: 30,
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: anchor.subtract(const Duration(days: 4)),
      ),
      EmploymentContract(
        id: 'demo-contract-$orgId-mini-job-hourly',
        orgId: orgId,
        userId: LocalDemoData.employeeSecondAccount.uid,
        label: 'Minijob mit Monatsgrenze',
        type: EmploymentType.miniJob,
        validFrom: yearStart,
        weeklyHours: 9,
        dailyHours: 4.5,
        hourlyRate: 14,
        salaryKind: SalaryKind.hourly,
        vacationDays: 20,
        maxDailyMinutes: 360,
        monthlyIncomeLimitCents: 60300,
        monthlyMaxHours: 43,
        weeklyMaxHours: 12,
        isPregnant: true,
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: anchor.subtract(const Duration(days: 3)),
      ),
      EmploymentContract(
        id: 'demo-contract-$orgId-trainee-monthly',
        orgId: orgId,
        userId: LocalDemoData.maikeAccount.uid,
        label: 'Ausbildung im Einzelhandel',
        type: EmploymentType.trainee,
        validFrom: DateTime(anchor.year - 1, 8, 1),
        validUntil: DateTime(anchor.year + 1, 7, 31),
        weeklyHours: 38.5,
        dailyHours: 7.7,
        salaryKind: SalaryKind.monthly,
        monthlyGrossCents: 118000,
        vacationDays: 27,
        maxDailyMinutes: 480,
        monthlyMaxHours: 167,
        weeklyMaxHours: 40,
        isMinor: true,
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: anchor.subtract(const Duration(days: 2)),
      ),
      EmploymentContract(
        id: 'demo-contract-$orgId-expired',
        orgId: orgId,
        userId: LocalDemoData.edithAccount.uid,
        label: 'Abgelaufene Befristung',
        type: EmploymentType.partTime,
        validFrom: DateTime(anchor.year - 1, 1, 1),
        validUntil: DateTime(anchor.year - 1, 12, 31),
        weeklyHours: 20,
        dailyHours: 5,
        hourlyRate: 15,
        salaryKind: SalaryKind.hourly,
        vacationDays: 24,
        createdByUid: createdByUid,
        createdAt: anchor.subtract(const Duration(days: 500)),
        updatedAt: anchor.subtract(const Duration(days: 190)),
      ),
    ];
  }

  static List<EmployeeShiftPreference> shiftPreferencesForOrg({
    required String orgId,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    return [
      EmployeeShiftPreference(
        id: 'demo-preference-$orgId-${LocalDemoData.employeeAccount.uid}',
        orgId: orgId,
        userId: LocalDemoData.employeeAccount.uid,
        rules: const [
          ShiftPreferenceRule(
            kind: PreferenceKind.prefer,
            weekdays: {1, 2, 3, 4, 5},
            startMinute: 6 * 60,
            endMinute: 12 * 60,
            daypart: ShiftDaypart.morning,
          ),
        ],
        updatedAt: anchor.subtract(const Duration(days: 2)),
      ),
      EmployeeShiftPreference(
        id: 'demo-preference-$orgId-${LocalDemoData.employeeSecondAccount.uid}',
        orgId: orgId,
        userId: LocalDemoData.employeeSecondAccount.uid,
        rules: const [
          ShiftPreferenceRule(
            kind: PreferenceKind.avoid,
            weekdays: {1, 3, 5},
            startMinute: 12 * 60,
            endMinute: 18 * 60,
            daypart: ShiftDaypart.afternoon,
          ),
        ],
        updatedAt: anchor.subtract(const Duration(days: 1)),
      ),
      EmployeeShiftPreference(
        id: 'demo-preference-$orgId-${LocalDemoData.teamLeadAccount.uid}',
        orgId: orgId,
        userId: LocalDemoData.teamLeadAccount.uid,
        rules: const [
          ShiftPreferenceRule(
            kind: PreferenceKind.block,
            weekdays: {6, 7},
            startMinute: 18 * 60,
            endMinute: 24 * 60,
            daypart: ShiftDaypart.evening,
          ),
        ],
        updatedAt: anchor,
      ),
      EmployeeShiftPreference(
        id: 'demo-preference-$orgId-${LocalDemoData.jowanAccount.uid}',
        orgId: orgId,
        userId: LocalDemoData.jowanAccount.uid,
        rules: const [
          ShiftPreferenceRule(
            kind: PreferenceKind.prefer,
            weekdays: {2, 4},
            startMinute: 10 * 60,
            endMinute: 14 * 60,
          ),
        ],
        updatedAt: anchor,
      ),
    ];
  }

  static List<TravelTimeRule> travelTimeRulesForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final tabak = LocalDemoData.tabakSiteId(orgId);
    final strich = LocalDemoData.strichmaennchenSiteId(orgId);
    final paket = LocalDemoData.paketshopSiteId(orgId);
    TravelTimeRule rule(
      String slug,
      String from,
      String to,
      int minutes, {
      bool countsAsWorkTime = true,
    }) => TravelTimeRule(
      id: 'demo-travel-$orgId-$slug',
      orgId: orgId,
      fromSiteId: from,
      toSiteId: to,
      travelMinutes: minutes,
      countsAsWorkTime: countsAsWorkTime,
      createdByUid: createdByUid,
      createdAt: anchor.subtract(const Duration(days: 60)),
      updatedAt: anchor.subtract(const Duration(days: 1)),
    );

    return [
      rule('tabak-strich', tabak, strich, 12),
      rule('strich-tabak', strich, tabak, 12),
      rule('tabak-paket', tabak, paket, 18),
      rule('paket-tabak', paket, tabak, 18),
      rule('strich-paket', strich, paket, 22, countsAsWorkTime: false),
      rule('paket-strich', paket, strich, 22, countsAsWorkTime: false),
    ];
  }

  static List<ComplianceRuleSet> complianceRuleSetsForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final createdAt = anchor.subtract(const Duration(days: 90));
    return [
      ComplianceRuleSet(
        id: 'demo-compliance-$orgId-retail-default',
        orgId: orgId,
        name: 'DE Einzelhandel Standard',
        minRestMinutes: 11 * 60,
        breakRules: const [
          BreakRule(afterMinutes: 6 * 60, requiredBreakMinutes: 30),
          BreakRule(afterMinutes: 9 * 60, requiredBreakMinutes: 45),
        ],
        maxPlannedMinutesPerDay: 10 * 60,
        minijobMonthlyLimitCents: 60300,
        nightWindowStartMinutes: 23 * 60,
        nightWindowEndMinutes: 6 * 60,
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: anchor.subtract(const Duration(days: 4)),
      ),
      ComplianceRuleSet(
        id: 'demo-compliance-$orgId-tabak-minijob',
        orgId: orgId,
        name: 'Tabak Börse – Minijob',
        siteId: LocalDemoData.tabakSiteId(orgId),
        employmentType: EmploymentType.miniJob,
        minRestMinutes: 12 * 60,
        breakRules: const [
          BreakRule(afterMinutes: 4 * 60, requiredBreakMinutes: 15),
          BreakRule(afterMinutes: 6 * 60, requiredBreakMinutes: 30),
        ],
        maxPlannedMinutesPerDay: 8 * 60,
        minijobMonthlyLimitCents: 60300,
        nightWindowStartMinutes: 22 * 60,
        nightWindowEndMinutes: 6 * 60,
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: anchor.subtract(const Duration(days: 3)),
      ),
      ComplianceRuleSet(
        id: 'demo-compliance-$orgId-paketshop-trainee',
        orgId: orgId,
        name: 'Paketshop – Ausbildung/Jugendschutz',
        siteId: LocalDemoData.paketshopSiteId(orgId),
        employmentType: EmploymentType.trainee,
        minRestMinutes: 12 * 60,
        breakRules: const [
          BreakRule(afterMinutes: 4 * 60 + 30, requiredBreakMinutes: 30),
          BreakRule(afterMinutes: 6 * 60, requiredBreakMinutes: 60),
        ],
        maxPlannedMinutesPerDay: 8 * 60,
        nightWindowStartMinutes: 20 * 60,
        nightWindowEndMinutes: 6 * 60,
        warnForwardRotation: false,
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: anchor.subtract(const Duration(days: 2)),
      ),
    ];
  }

  static List<Shift> shiftsForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final tabak = LocalDemoData.tabakSiteId(orgId);
    final strich = LocalDemoData.strichmaennchenSiteId(orgId);
    final paket = LocalDemoData.paketshopSiteId(orgId);
    final completedStart = _monthMoment(anchor, -6, 7);
    final cancelledStart = _monthMoment(anchor, -4, 12);
    final peterSwapStart = _monthMoment(anchor, 3, 7);
    final mariaSwapStart = _monthMoment(anchor, 4, 12);
    final openStart = _monthMoment(anchor, 5, 10);
    final nightStart = _monthMoment(anchor, 6, 22);
    final monthlyStart = _monthMoment(anchor, 7, 8);
    final createdAt = anchor.subtract(const Duration(days: 30));

    return [
      Shift(
        id: shiftId(orgId, 'completed'),
        orgId: orgId,
        userId: LocalDemoData.employeeAccount.uid,
        employeeName: LocalDemoData.employeeAccount.name,
        title: 'Frühdienst abgeschlossen',
        startTime: completedStart,
        endTime: completedStart.add(const Duration(hours: 8)),
        breakMinutes: 30,
        teamId: teamId(orgId, 'tabak'),
        team: 'Team Tabak Börse',
        siteId: tabak,
        siteName: 'Tabak Börse',
        location: 'Kiel',
        requiredQualificationIds: [qualificationId(orgId, 'lotto')],
        notes: 'Regulär gearbeitet und abgeschlossen.',
        color: '#1565C0',
        status: ShiftStatus.completed,
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: completedStart.add(const Duration(hours: 9)),
      ),
      Shift(
        id: shiftId(orgId, 'cancelled'),
        orgId: orgId,
        userId: LocalDemoData.employeeSecondAccount.uid,
        employeeName: LocalDemoData.employeeSecondAccount.name,
        title: 'Spätdienst abgesagt',
        startTime: cancelledStart,
        endTime: cancelledStart.add(const Duration(hours: 6)),
        breakMinutes: 15,
        teamId: teamId(orgId, 'strichmaennchen'),
        team: 'Team Strichmännchen',
        siteId: strich,
        siteName: 'Strichmännchen GmbH',
        notes: 'Testfall für eine abgesagte Schicht.',
        color: '#757575',
        status: ShiftStatus.cancelled,
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: cancelledStart.subtract(const Duration(days: 1)),
      ),
      Shift(
        id: shiftId(orgId, 'peter-swap'),
        orgId: orgId,
        userId: LocalDemoData.employeeAccount.uid,
        employeeName: LocalDemoData.employeeAccount.name,
        title: 'Frühdienst mit Tauschanfrage',
        startTime: peterSwapStart,
        endTime: peterSwapStart.add(const Duration(hours: 8)),
        breakMinutes: 30,
        teamId: teamId(orgId, 'tabak'),
        team: 'Team Tabak Börse',
        siteId: tabak,
        siteName: 'Tabak Börse',
        requiredQualificationIds: [
          qualificationId(orgId, 'lotto'),
          qualificationId(orgId, 'first-aid'),
        ],
        seriesId: 'demo-shift-series-$orgId-weekly',
        recurrencePattern: RecurrencePattern.weekly,
        color: '#1976D2',
        swapRequestedByUid: LocalDemoData.employeeAccount.uid,
        swapStatus: SwapStatus.pending.value,
        status: ShiftStatus.confirmed,
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: anchor.subtract(const Duration(hours: 4)),
      ),
      Shift(
        id: shiftId(orgId, 'maria-swap'),
        orgId: orgId,
        userId: LocalDemoData.employeeSecondAccount.uid,
        employeeName: LocalDemoData.employeeSecondAccount.name,
        title: 'Spätdienst als Tauschziel',
        startTime: mariaSwapStart,
        endTime: mariaSwapStart.add(const Duration(hours: 6)),
        breakMinutes: 15,
        teamId: teamId(orgId, 'strichmaennchen'),
        team: 'Team Strichmännchen',
        siteId: strich,
        siteName: 'Strichmännchen GmbH',
        requiredQualificationIds: [qualificationId(orgId, 'hygiene')],
        seriesId: 'demo-shift-series-$orgId-monthly',
        recurrencePattern: RecurrencePattern.monthly,
        color: '#8E24AA',
        status: ShiftStatus.confirmed,
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: anchor.subtract(const Duration(hours: 3)),
      ),
      Shift(
        id: shiftId(orgId, 'open'),
        orgId: orgId,
        userId: '',
        employeeName: 'Offene Schicht',
        title: 'Paketshop – offene Besetzung',
        startTime: openStart,
        endTime: openStart.add(const Duration(hours: 7)),
        breakMinutes: 30,
        teamId: teamId(orgId, 'paketshop'),
        team: 'Team Paketshop',
        siteId: paket,
        siteName: 'Paketshop REWE Dietrichsdorf',
        requiredQualificationIds: [qualificationId(orgId, 'hygiene')],
        notes: 'Noch keiner Person zugewiesen.',
        color: '#FB8C00',
        status: ShiftStatus.planned,
        overtimeMinutes: 30,
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: anchor,
      ),
      Shift(
        id: shiftId(orgId, 'night'),
        orgId: orgId,
        userId: LocalDemoData.teamLeadAccount.uid,
        employeeName: LocalDemoData.teamLeadAccount.name,
        title: 'Nachtinventur',
        startTime: nightStart,
        endTime: nightStart.add(const Duration(hours: 8)),
        breakMinutes: 45,
        teamId: teamId(orgId, 'strichmaennchen'),
        team: 'Team Strichmännchen',
        siteId: strich,
        siteName: 'Strichmännchen GmbH',
        requiredQualificationIds: [qualificationId(orgId, 'first-aid')],
        notes: 'Monatsinventur über Mitternacht.',
        seriesId: 'demo-shift-series-$orgId-biweekly',
        recurrencePattern: RecurrencePattern.biWeekly,
        color: '#37474F',
        status: ShiftStatus.planned,
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: anchor,
      ),
      Shift(
        id: shiftId(orgId, 'monthly-extra'),
        orgId: orgId,
        userId: LocalDemoData.maikeAccount.uid,
        employeeName: LocalDemoData.maikeAccount.name,
        title: 'Monatlicher Paketshop-Termin',
        startTime: monthlyStart,
        endTime: monthlyStart.add(const Duration(hours: 5)),
        teamId: teamId(orgId, 'paketshop'),
        team: 'Team Paketshop',
        siteId: paket,
        siteName: 'Paketshop REWE Dietrichsdorf',
        seriesId: 'demo-shift-series-$orgId-monthly-extra',
        recurrencePattern: RecurrencePattern.monthly,
        color: '#00897B',
        status: ShiftStatus.planned,
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: anchor,
      ),
    ];
  }

  static List<ShiftTemplate> shiftTemplatesForOrg({required String orgId}) => [
    ShiftTemplate(
      id: 'demo-shift-template-$orgId-tabak-early',
      orgId: orgId,
      userId: LocalDemoData.johannaAccount.uid,
      name: 'Tabak Frühdienst',
      title: 'Frühdienst',
      startMinutes: 6 * 60 + 45,
      endMinutes: 14 * 60 + 45,
      breakMinutes: 30,
      teamId: teamId(orgId, 'tabak'),
      teamName: 'Team Tabak Börse',
      siteId: LocalDemoData.tabakSiteId(orgId),
      siteName: 'Tabak Börse',
      requiredQualificationIds: [qualificationId(orgId, 'lotto')],
      notes: 'Öffnung inklusive Kassenvorbereitung.',
      color: '#1565C0',
    ),
    ShiftTemplate(
      id: 'demo-shift-template-$orgId-strich-late',
      orgId: orgId,
      name: 'Strichmännchen Spätdienst',
      title: 'Spätdienst',
      startMinutes: 12 * 60,
      endMinutes: 20 * 60,
      breakMinutes: 30,
      teamId: teamId(orgId, 'strichmaennchen'),
      teamName: 'Team Strichmännchen',
      siteId: LocalDemoData.strichmaennchenSiteId(orgId),
      siteName: 'Strichmännchen GmbH',
      requiredQualificationIds: [qualificationId(orgId, 'hygiene')],
      color: '#8E24AA',
    ),
    ShiftTemplate(
      id: 'demo-shift-template-$orgId-paket-day',
      orgId: orgId,
      userId: LocalDemoData.maikeAccount.uid,
      name: 'Paketshop Tagesdienst',
      title: 'Paketannahme und Ausgabe',
      startMinutes: 9 * 60,
      endMinutes: 16 * 60,
      breakMinutes: 30,
      teamId: teamId(orgId, 'paketshop'),
      teamName: 'Team Paketshop',
      siteId: LocalDemoData.paketshopSiteId(orgId),
      siteName: 'Paketshop REWE Dietrichsdorf',
      requiredQualificationIds: [qualificationId(orgId, 'hygiene')],
      color: '#00897B',
    ),
    ShiftTemplate(
      id: 'demo-shift-template-$orgId-night',
      orgId: orgId,
      userId: LocalDemoData.teamLeadAccount.uid,
      name: 'Nachtinventur',
      title: 'Inventur',
      startMinutes: 22 * 60,
      endMinutes: 6 * 60,
      breakMinutes: 45,
      teamId: teamId(orgId, 'strichmaennchen'),
      teamName: 'Team Strichmännchen',
      siteId: LocalDemoData.strichmaennchenSiteId(orgId),
      siteName: 'Strichmännchen GmbH',
      requiredQualificationIds: [qualificationId(orgId, 'first-aid')],
      notes: 'Vorlage über Mitternacht.',
      color: '#37474F',
    ),
  ];

  static List<AbsenceRequest> absenceRequestsForOrg({
    required String orgId,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final accounts = [
      LocalDemoData.employeeAccount,
      LocalDemoData.employeeSecondAccount,
      LocalDemoData.teamLeadAccount,
      LocalDemoData.maikeAccount,
      LocalDemoData.edithAccount,
      LocalDemoData.raffaelAccount,
    ];
    final requests = <AbsenceRequest>[];

    for (var index = 0; index < AbsenceType.values.length; index++) {
      final type = AbsenceType.values[index];
      final account = accounts[index % accounts.length];
      final status = AbsenceStatus.values[index % AbsenceStatus.values.length];
      final start = _monthMoment(anchor, index - 5, 0);
      final end = switch (type) {
        AbsenceType.vacation => start.add(const Duration(days: 4)),
        AbsenceType.sickness => start.add(const Duration(days: 2)),
        AbsenceType.parentalLeave => start.add(const Duration(days: 21)),
        AbsenceType.maternity => start.add(const Duration(days: 14)),
        _ => start,
      };
      final halfDay =
          type == AbsenceType.unavailable || type == AbsenceType.specialLeave;
      final halfDayPeriod = switch (type) {
        AbsenceType.unavailable => HalfDayPeriod.vormittags,
        AbsenceType.specialLeave => HalfDayPeriod.nachmittags,
        _ => null,
      };

      requests.add(
        AbsenceRequest(
          id: 'demo-absence-$orgId-${type.value}',
          orgId: orgId,
          userId: account.uid,
          employeeName: account.name,
          startDate: start,
          endDate: end,
          type: type,
          note: _absenceNote(type),
          status: status,
          reviewedByUid:
              status == AbsenceStatus.pending
                  ? null
                  : LocalDemoData.adminAccount.uid,
          halfDay: halfDay,
          halfDayPeriod: halfDayPeriod,
          hours: switch (type) {
            AbsenceType.timeOff => 4.5,
            AbsenceType.shortTimeWork => 3,
            _ => null,
          },
          vertreterUserIds: [
            account.uid == LocalDemoData.employeeAccount.uid
                ? LocalDemoData.employeeSecondAccount.uid
                : LocalDemoData.employeeAccount.uid,
          ],
          eauAttached: type == AbsenceType.sickness,
          createdAt: anchor.subtract(Duration(days: index + 1)),
          updatedAt: anchor.subtract(Duration(hours: index + 1)),
        ),
      );
    }

    final sicknessWithoutEauStart = _monthMoment(anchor, -1, 0);
    requests.add(
      AbsenceRequest(
        id: 'demo-absence-$orgId-sickness-without-eau',
        orgId: orgId,
        userId: LocalDemoData.johannaAccount.uid,
        employeeName: LocalDemoData.johannaAccount.name,
        startDate: sicknessWithoutEauStart,
        endDate: sicknessWithoutEauStart,
        type: AbsenceType.sickness,
        note: 'Kurze Krankmeldung ohne eAU-Anhang.',
        status: AbsenceStatus.pending,
        eauAttached: false,
        createdAt: anchor.subtract(const Duration(hours: 8)),
        updatedAt: anchor.subtract(const Duration(hours: 7)),
      ),
    );
    return requests;
  }

  static List<ShiftSwapRequest> shiftSwapRequestsForOrg({
    required String orgId,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final requesterStart = _monthMoment(anchor, 3, 7);
    final targetStart = _monthMoment(anchor, 4, 12);
    final requests = <ShiftSwapRequest>[];

    for (var index = 0; index < SwapStatus.values.length; index++) {
      final status = SwapStatus.values[index];
      final kind = index.isEven ? SwapKind.exchange : SwapKind.giveAway;
      requests.add(
        ShiftSwapRequest(
          id: swapRequestId(orgId, status.value),
          orgId: orgId,
          requesterUid: LocalDemoData.employeeAccount.uid,
          requesterName: LocalDemoData.employeeAccount.name,
          requesterShiftId: shiftId(orgId, 'peter-swap'),
          targetUid: LocalDemoData.employeeSecondAccount.uid,
          targetName: LocalDemoData.employeeSecondAccount.name,
          targetShiftId:
              kind == SwapKind.exchange ? shiftId(orgId, 'maria-swap') : null,
          kind: kind,
          status: status,
          reviewedByUid:
              status == SwapStatus.confirmed ||
                      status == SwapStatus.rejectedByManager
                  ? LocalDemoData.adminAccount.uid
                  : null,
          overriddenCompliance: status == SwapStatus.confirmed,
          note: 'Demo-Tauschanfrage: ${status.label}.',
          requesterShiftStart: requesterStart,
          targetShiftStart: kind == SwapKind.exchange ? targetStart : null,
          requesterShiftLabel: 'Frühdienst mit Tauschanfrage',
          targetShiftLabel:
              kind == SwapKind.exchange ? 'Spätdienst als Tauschziel' : null,
          createdAt: anchor.subtract(Duration(days: index + 1)),
          updatedAt: anchor.subtract(Duration(hours: index + 1)),
        ),
      );
    }

    requests.add(
      ShiftSwapRequest(
        id: swapRequestId(orgId, 'confirmed-exchange'),
        orgId: orgId,
        requesterUid: LocalDemoData.employeeAccount.uid,
        requesterName: LocalDemoData.employeeAccount.name,
        requesterShiftId: shiftId(orgId, 'peter-swap'),
        targetUid: LocalDemoData.employeeSecondAccount.uid,
        targetName: LocalDemoData.employeeSecondAccount.name,
        targetShiftId: shiftId(orgId, 'maria-swap'),
        kind: SwapKind.exchange,
        status: SwapStatus.confirmed,
        reviewedByUid: LocalDemoData.adminAccount.uid,
        note: 'Bestätigter direkter Schichttausch.',
        requesterShiftStart: requesterStart,
        targetShiftStart: targetStart,
        requesterShiftLabel: 'Frühdienst mit Tauschanfrage',
        targetShiftLabel: 'Spätdienst als Tauschziel',
        createdAt: anchor.subtract(const Duration(days: 8)),
        updatedAt: anchor.subtract(const Duration(days: 1)),
      ),
    );
    return requests;
  }

  static List<SwapCredit> swapCreditsForOrg({
    required String orgId,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final originRequestId = swapRequestId(orgId, SwapStatus.confirmed.value);
    final settlementRequestId = swapRequestId(orgId, 'confirmed-exchange');
    final originStart = _monthMoment(anchor, 3, 7);

    return [
      SwapCredit(
        id: 'demo-swap-credit-$orgId-open',
        orgId: orgId,
        creditorUid: LocalDemoData.employeeSecondAccount.uid,
        creditorName: LocalDemoData.employeeSecondAccount.name,
        debtorUid: LocalDemoData.employeeAccount.uid,
        debtorName: LocalDemoData.employeeAccount.name,
        originSwapRequestId: originRequestId,
        originShiftStart: originStart,
        originShiftLabel: 'Frühdienst mit Tauschanfrage',
        status: SwapCreditStatus.open,
        note: 'Offene Schichtgutschrift für den Folgemonat.',
        createdAt: anchor.subtract(const Duration(days: 5)),
        updatedAt: anchor.subtract(const Duration(days: 1)),
      ),
      SwapCredit(
        id: 'demo-swap-credit-$orgId-settled',
        orgId: orgId,
        creditorUid: LocalDemoData.employeeSecondAccount.uid,
        creditorName: LocalDemoData.employeeSecondAccount.name,
        debtorUid: LocalDemoData.employeeAccount.uid,
        debtorName: LocalDemoData.employeeAccount.name,
        originSwapRequestId: originRequestId,
        originShiftStart: originStart,
        originShiftLabel: 'Frühdienst mit Tauschanfrage',
        status: SwapCreditStatus.settled,
        settledBySwapRequestId: settlementRequestId,
        settledAt: anchor.subtract(const Duration(days: 1)),
        note: 'Gutschrift durch Gegentausch eingelöst.',
        createdAt: anchor.subtract(const Duration(days: 20)),
        updatedAt: anchor.subtract(const Duration(days: 1)),
      ),
      SwapCredit(
        id: 'demo-swap-credit-$orgId-cancelled',
        orgId: orgId,
        creditorUid: LocalDemoData.employeeSecondAccount.uid,
        creditorName: LocalDemoData.employeeSecondAccount.name,
        debtorUid: LocalDemoData.employeeAccount.uid,
        debtorName: LocalDemoData.employeeAccount.name,
        originSwapRequestId: originRequestId,
        originShiftStart: originStart,
        originShiftLabel: 'Frühdienst mit Tauschanfrage',
        status: SwapCreditStatus.cancelled,
        note: 'Storniert, weil die Ursprungsschicht entfallen ist.',
        createdAt: anchor.subtract(const Duration(days: 30)),
        updatedAt: anchor.subtract(const Duration(days: 10)),
      ),
    ];
  }

  static DateTime _anchor(DateTime? now) {
    final value = now ?? DateTime.now();
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
    );
  }

  static DateTime _monthMoment(
    DateTime anchor,
    int dayOffset,
    int hour, [
    int minute = 0,
  ]) {
    final lastDay = DateTime(anchor.year, anchor.month + 1, 0).day;
    final day = (anchor.day + dayOffset).clamp(1, lastDay);
    return DateTime(anchor.year, anchor.month, day, hour, minute);
  }

  static String _absenceNote(AbsenceType type) => switch (type) {
    AbsenceType.vacation => 'Geplanter Sommerurlaub mit Vertretung.',
    AbsenceType.sickness => 'Krankmeldung mit eAU-Anhang.',
    AbsenceType.unavailable => 'Vormittags privater Termin.',
    AbsenceType.specialLeave => 'Sonderurlaub am Nachmittag.',
    AbsenceType.unpaidLeave => 'Beantragte unbezahlte Freistellung.',
    AbsenceType.timeOff => '4,5 Stunden Abbau vom Zeitkonto.',
    AbsenceType.parentalLeave => 'Testfall für einen längeren Zeitraum.',
    AbsenceType.maternity => 'Testfall Mutterschutz.',
    AbsenceType.vocationalSchool => 'Blocktag in der Berufsschule.',
    AbsenceType.volunteering => 'Freistellung für ehrenamtlichen Einsatz.',
    AbsenceType.shortTimeWork => 'Drei Stunden Kurzarbeit.',
    AbsenceType.childSick => 'Betreuung eines kranken Kindes.',
  };
}

class LocalDemoScheduleDataset {
  const LocalDemoScheduleDataset({
    required this.invites,
    required this.teams,
    required this.qualifications,
    required this.employmentContracts,
    required this.shiftPreferences,
    required this.travelTimeRules,
    required this.complianceRuleSets,
    required this.shifts,
    required this.shiftTemplates,
    required this.absenceRequests,
    required this.shiftSwapRequests,
    required this.swapCredits,
  });

  final List<UserInvite> invites;
  final List<TeamDefinition> teams;
  final List<QualificationDefinition> qualifications;
  final List<EmploymentContract> employmentContracts;
  final List<EmployeeShiftPreference> shiftPreferences;
  final List<TravelTimeRule> travelTimeRules;
  final List<ComplianceRuleSet> complianceRuleSets;
  final List<Shift> shifts;
  final List<ShiftTemplate> shiftTemplates;
  final List<AbsenceRequest> absenceRequests;
  final List<ShiftSwapRequest> shiftSwapRequests;
  final List<SwapCredit> swapCredits;
}
