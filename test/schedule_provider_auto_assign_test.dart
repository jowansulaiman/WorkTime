import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/core/shift_auto_assigner.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/compliance_rule_set.dart';
import 'package:worktime_app/models/employee_site_assignment.dart';
import 'package:worktime_app/models/employment_contract.dart';
import 'package:worktime_app/models/org_settings.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/site_schedule.dart';
import 'package:worktime_app/models/sollzeit_profile.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/schedule_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScheduleProvider Auto-Schichtverteilung', () {
    late AppUserProfile admin;
    late AppUserProfile employee;
    late SiteDefinition site;

    DateTime dayInCurrentWeek(int offsetFromMonday) {
      final today = DateTime.now();
      final weekStart = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: today.weekday - 1));
      return weekStart.add(Duration(days: offsetFromMonday));
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
      admin = const AppUserProfile(
        uid: 'admin-1',
        orgId: 'org-1',
        email: 'admin@example.com',
        role: UserRole.admin,
        isActive: true,
        settings: UserSettings(name: 'Admin'),
      );
      employee = const AppUserProfile(
        uid: 'u1',
        orgId: 'org-1',
        email: 'u1@example.com',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: 'Uwe'),
      );
      site = const SiteDefinition(
        id: 'site-1',
        orgId: 'org-1',
        name: 'Laden',
        weekdayHours: [
          WeekdayHours(
            weekday: DateTime.monday,
            windows: [TimeWindow(startMinute: 540, endMinute: 1020)],
          ),
        ],
      );
    });

    EmploymentContract contractFor(String uid, {double? monthlyMaxHours}) =>
        EmploymentContract(
          id: 'c-$uid',
          orgId: 'org-1',
          userId: uid,
          validFrom: DateTime(2020, 1, 1),
          dailyHours: 8,
          weeklyHours: 40,
          monthlyMaxHours: monthlyMaxHours,
        );

    EmployeeSiteAssignment assignmentFor(String uid) => EmployeeSiteAssignment(
          id: 'a-$uid',
          orgId: 'org-1',
          userId: uid,
          siteId: 'site-1',
          siteName: 'Laden',
          isPrimary: true,
        );

    ScheduleProvider newProvider() => ScheduleProvider(
          firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
          disableAuthentication: true,
        );

    test('generatePlannedShifts liefert Slots aus Öffnungszeiten', () async {
      final provider = newProvider();
      addTearDown(provider.dispose);
      await provider.updateSession(admin);
      provider.updateReferenceData(
        members: [admin, employee],
        contracts: [contractFor('admin-1'), contractFor('u1')],
        siteAssignments: [assignmentFor('admin-1'), assignmentFor('u1')],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const [],
        sites: [site],
      );

      final monday = dayInCurrentWeek(0);
      final generated = provider.generatePlannedShifts(
        rangeStart: monday,
        rangeEnd: monday.add(const Duration(days: 1)),
        settings: OrgSettings.defaults('org-1'),
      );

      expect(generated, isNotEmpty);
      expect(generated.every((s) => s.isUnassigned), isTrue);
      expect(generated.first.siteId, 'site-1');
    });

    test('proposeAutoAssignment besetzt generierte Schichten', () async {
      final provider = newProvider();
      addTearDown(provider.dispose);
      await provider.updateSession(admin);
      provider.updateReferenceData(
        members: [admin, employee],
        contracts: [contractFor('admin-1'), contractFor('u1')],
        siteAssignments: [assignmentFor('admin-1'), assignmentFor('u1')],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const [],
        sites: [site],
      );

      final monday = dayInCurrentWeek(0);
      final generated = provider.generatePlannedShifts(
        rangeStart: monday,
        rangeEnd: monday.add(const Duration(days: 1)),
        settings: OrgSettings.defaults('org-1'),
      );
      final result = await provider.proposeAutoAssignment(
        openShifts: generated,
        month: monday,
        settings: OrgSettings.defaults('org-1'),
      );

      expect(result.assignments, hasLength(generated.length));
      expect(result.unassigned, isEmpty);
    });

    test('applyAutoPlan speichert generierte UND bereits offene Schichten',
        () async {
      final provider = newProvider();
      addTearDown(provider.dispose);
      await provider.updateSession(admin);
      provider.updateReferenceData(
        members: [admin, employee],
        contracts: [contractFor('admin-1'), contractFor('u1')],
        siteAssignments: [assignmentFor('admin-1'), assignmentFor('u1')],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const [],
        sites: [site],
      );

      // Bereits vorhandene offene Schicht (anderer Tag als die Öffnungszeit,
      // damit der Generator sie nicht dupliziert).
      final tuesday = dayInCurrentWeek(1);
      await provider.saveShifts([
        Shift(
          orgId: 'org-1',
          userId: '',
          employeeName: '',
          title: 'Offen',
          startTime: tuesday.add(const Duration(hours: 9)),
          endTime: tuesday.add(const Duration(hours: 17)),
          breakMinutes: 30,
          siteId: 'site-1',
          siteName: 'Laden',
        ),
      ]);
      expect(provider.shifts.where((s) => s.isUnassigned), hasLength(1));

      final monday = dayInCurrentWeek(0);
      final generated = provider.generatePlannedShifts(
        rangeStart: monday,
        rangeEnd: monday.add(const Duration(days: 1)),
        settings: OrgSettings.defaults('org-1'),
      );
      final existingOpen =
          provider.shifts.where((s) => s.isUnassigned).toList(growable: false);
      final result = await provider.proposeAutoAssignment(
        openShifts: [...generated, ...existingOpen],
        month: monday,
        settings: OrgSettings.defaults('org-1'),
      );

      await provider.applyAutoPlan(
        generatedShifts: generated,
        existingOpenShifts: existingOpen,
        result: result,
      );

      // Generierte (Mo) + zuvor offene (Di) Schicht, beide jetzt besetzt.
      expect(provider.shifts, hasLength(generated.length + 1));
      expect(provider.shifts.where((s) => s.isUnassigned), isEmpty);
    });

    test('Permission-Gate: ohne canManageShifts leeres Ergebnis', () async {
      final provider = newProvider();
      addTearDown(provider.dispose);
      await provider.updateSession(employee);
      provider.updateReferenceData(
        members: [employee],
        contracts: [contractFor('u1')],
        siteAssignments: [assignmentFor('u1')],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const [],
        sites: [site],
      );

      final monday = dayInCurrentWeek(0);
      final generated = provider.generatePlannedShifts(
        rangeStart: monday,
        rangeEnd: monday.add(const Duration(days: 1)),
        settings: OrgSettings.defaults('org-1'),
      );
      expect(generated, isEmpty);

      final result = await provider.proposeAutoAssignment(
        openShifts: const [],
        month: monday,
        settings: OrgSettings.defaults('org-1'),
      );
      expect(result.assignments, isEmpty);
      expect(result.unassigned, isEmpty);
    });

    test('Cap-Toggle aus OrgSettings wirkt durch (hart vs. weich)', () async {
      final provider = newProvider();
      addTearDown(provider.dispose);
      await provider.updateSession(admin);
      provider.updateReferenceData(
        members: [employee], // nur u1, damit das Cap-Verhalten isoliert ist
        contracts: [contractFor('u1', monthlyMaxHours: 10)],
        siteAssignments: [assignmentFor('u1')],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const [],
        sites: [site],
      );

      // Zwei 8h-Schichten an verschiedenen Tagen desselben Monats (fixe Daten —
      // proposeAutoAssignment range-filtert direkt übergebene openShifts nicht).
      Shift eightHour(String id, DateTime day) => Shift(
            id: id,
            orgId: 'org-1',
            userId: '',
            employeeName: '',
            title: 'Laden',
            startTime: day.add(const Duration(hours: 9)),
            endTime: day.add(const Duration(hours: 17)),
            breakMinutes: 30,
            siteId: 'site-1',
            siteName: 'Laden',
          );
      final open = [
        eightHour('mon', DateTime(2026, 6, 1)),
        eightHour('tue', DateTime(2026, 6, 2)),
      ];

      final hard = await provider.proposeAutoAssignment(
        openShifts: open,
        month: DateTime(2026, 6, 1),
        settings: const OrgSettings(orgId: 'org-1', enforceHourCapHard: true),
      );
      expect(hard.assignments, hasLength(1));
      expect(hard.unassigned.single.shiftId, 'tue');

      final soft = await provider.proposeAutoAssignment(
        openShifts: open,
        month: DateTime(2026, 6, 1),
        settings: const OrgSettings(orgId: 'org-1', enforceHourCapHard: false),
      );
      expect(soft.assignments, hasLength(2));
      expect(soft.warnings, isNotEmpty);
    });

    test('Monats-Cap zählt bereits besetzte Schichten des GANZEN Monats '
        '(nicht nur die sichtbare Woche)', () async {
      final provider = newProvider();
      addTearDown(provider.dispose);
      await provider.updateSession(admin);
      provider.updateReferenceData(
        members: [employee],
        contracts: [contractFor('u1', monthlyMaxHours: 10)],
        siteAssignments: [assignmentFor('u1')],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const [],
        sites: [site],
      );

      // Bereits besetzte 6h-Schicht früh im Monat (fixes Datum, NICHT in der
      // sichtbaren Woche → nur im vollständigen lokalen Cache, nicht in _shifts).
      await provider.saveShifts([
        Shift(
          orgId: 'org-1',
          userId: 'u1',
          employeeName: 'Uwe',
          title: 'Frueh',
          startTime: DateTime(2026, 6, 1, 8),
          endTime: DateTime(2026, 6, 1, 14),
          siteId: 'site-1',
          siteName: 'Laden',
        ),
      ]);

      // Offene 6h-Schicht später im Monat, andere Woche.
      final open = Shift(
        id: 'open-1',
        orgId: 'org-1',
        userId: '',
        employeeName: '',
        title: 'Laden',
        startTime: DateTime(2026, 6, 15, 8),
        endTime: DateTime(2026, 6, 15, 14),
        siteId: 'site-1',
        siteName: 'Laden',
      );

      // 6h vorhanden + 6h neu = 12h > Cap 10h → muss offen bleiben. Würde nur
      // die sichtbare Woche gezählt, wäre der Vor-Monat-Eintrag unsichtbar und
      // die Schicht fälschlich zugewiesen.
      final result = await provider.proposeAutoAssignment(
        openShifts: [open],
        month: DateTime(2026, 6, 15),
        settings: const OrgSettings(orgId: 'org-1', enforceHourCapHard: true),
      );
      expect(result.assignments, isEmpty);
      expect(result.unassigned.single.shiftId, 'open-1');
    });

    test(
        'W3 Duplikat-Slot-Fix: aktiver Mitarbeiter-Filter versteckt vorhandene '
        'Slots NICHT vor generatePlannedShifts', () async {
      final provider = newProvider();
      addTearDown(provider.dispose);
      await provider.updateSession(admin);
      provider.updateReferenceData(
        members: [admin, employee],
        contracts: [contractFor('admin-1'), contractFor('u1')],
        siteAssignments: [assignmentFor('admin-1'), assignmentFor('u1')],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const [],
        sites: [site],
      );

      // Vorhandener unbesetzter Slot exakt auf der Montags-Öffnungszeit
      // (2026-06-01 ist ein Montag, 9:00–17:00 = Fenster 540–1020).
      final monday = DateTime(2026, 6, 1);
      await provider.saveShifts([
        Shift(
          orgId: 'org-1',
          userId: '',
          employeeName: '',
          title: 'Laden',
          startTime: monday.add(const Duration(hours: 9)),
          endTime: monday.add(const Duration(hours: 17)),
          breakMinutes: 30,
          siteId: 'site-1',
          siteName: 'Laden',
        ),
      ]);

      // Mitarbeiter-Filter aktivieren: die sichtbare Liste (`shifts`) versteckt
      // den unbesetzten Slot jetzt — die Idempotenz-Basis darf das nicht.
      provider.setSelectedUserId('u1');
      await Future<void>.delayed(Duration.zero);
      expect(provider.shifts.where((s) => s.isUnassigned), isEmpty);

      final generated = provider.generatePlannedShifts(
        rangeStart: monday,
        rangeEnd: monday.add(const Duration(days: 1)),
        settings: OrgSettings.defaults('org-1'),
      );
      expect(generated, isEmpty,
          reason: 'Vorhandener Slot darf trotz aktivem Filter nicht '
              'erneut generiert werden');
    });

    test('W3: stornierte Schichten zählen NICHT zum Monats-Cap', () async {
      final provider = newProvider();
      addTearDown(provider.dispose);
      await provider.updateSession(admin);
      provider.updateReferenceData(
        members: [employee],
        contracts: [contractFor('u1', monthlyMaxHours: 10)],
        siteAssignments: [assignmentFor('u1')],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const [],
        sites: [site],
      );

      // Stornierte 6h-Schicht früh im Monat: dürfte das Konto NICHT belasten.
      await provider.saveShifts([
        Shift(
          orgId: 'org-1',
          userId: 'u1',
          employeeName: 'Uwe',
          title: 'Abgesagt',
          startTime: DateTime(2026, 6, 1, 8),
          endTime: DateTime(2026, 6, 1, 14),
          siteId: 'site-1',
          siteName: 'Laden',
          status: ShiftStatus.cancelled,
        ),
      ]);

      final open = Shift(
        id: 'open-1',
        orgId: 'org-1',
        userId: '',
        employeeName: '',
        title: 'Laden',
        startTime: DateTime(2026, 6, 15, 8),
        endTime: DateTime(2026, 6, 15, 14),
        siteId: 'site-1',
        siteName: 'Laden',
      );

      // 6h storniert + 6h neu: zählte die stornierte mit, wären es 12h > 10h
      // Cap und die Schicht bliebe offen.
      final result = await provider.proposeAutoAssignment(
        openShifts: [open],
        month: DateTime(2026, 6, 15),
        settings: const OrgSettings(orgId: 'org-1', enforceHourCapHard: true),
      );
      expect(result.assignments, hasLength(1));
      expect(result.assignments.single.userId, 'u1');
      expect(result.unassigned, isEmpty);
    });

    test('W3 Teilübernahme: applyAutoPlan mit onlyShiftIds speichert nur die '
        'gewählten Slots', () async {
      final provider = newProvider();
      addTearDown(provider.dispose);
      await provider.updateSession(admin);
      provider.setVisibleDate(DateTime(2026, 6, 15));
      await Future<void>.delayed(Duration.zero);
      provider.updateReferenceData(
        members: [employee],
        contracts: [contractFor('u1')],
        siteAssignments: [assignmentFor('u1')],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const [],
        sites: [site],
      );

      Shift openShift(String id, DateTime day) => Shift(
            id: id,
            orgId: 'org-1',
            userId: '',
            employeeName: '',
            title: 'Laden',
            startTime: day.add(const Duration(hours: 9)),
            endTime: day.add(const Duration(hours: 13)),
            siteId: 'site-1',
            siteName: 'Laden',
          );
      final generated = [
        openShift('slot-a', DateTime(2026, 6, 15)),
        openShift('slot-b', DateTime(2026, 6, 16)),
      ];
      final result = await provider.proposeAutoAssignment(
        openShifts: generated,
        month: DateTime(2026, 6, 15),
        settings: OrgSettings.defaults('org-1'),
      );
      expect(result.assignments, hasLength(2));

      await provider.applyAutoPlan(
        generatedShifts: generated,
        existingOpenShifts: const [],
        result: result,
        onlyShiftIds: {'slot-a'},
      );

      // Nur der gewählte Slot wurde gespeichert (und ist besetzt).
      expect(provider.shifts, hasLength(1));
      expect(provider.shifts.single.id, 'slot-a');
      expect(provider.shifts.single.userId, 'u1');
    });

    test('W3/E1: geplante Überstunden (overtimeMinutes) kommen am '
        'gespeicherten Shift an (Local-Modus, weicher Cap)', () async {
      final provider = newProvider();
      addTearDown(provider.dispose);
      await provider.updateSession(admin);
      provider.setVisibleDate(DateTime(2026, 6, 15));
      await Future<void>.delayed(Duration.zero);
      provider.updateReferenceData(
        members: [employee],
        contracts: [contractFor('u1', monthlyMaxHours: 10)],
        siteAssignments: [assignmentFor('u1')],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const [],
        sites: [site],
      );

      // Zwei 8h-Schichten (netto je 450 min) gegen Monats-Cap 10 h (600 min):
      // die chronologisch zweite trägt 300 min geplante Überstunden.
      Shift eightHour(String id, DateTime day) => Shift(
            id: id,
            orgId: 'org-1',
            userId: '',
            employeeName: '',
            title: 'Laden',
            startTime: day.add(const Duration(hours: 9)),
            endTime: day.add(const Duration(hours: 17)),
            breakMinutes: 30,
            siteId: 'site-1',
            siteName: 'Laden',
          );
      final generated = [
        eightHour('mon', DateTime(2026, 6, 15)),
        eightHour('tue', DateTime(2026, 6, 16)),
      ];
      final result = await provider.proposeAutoAssignment(
        openShifts: generated,
        month: DateTime(2026, 6, 15),
        settings: const OrgSettings(orgId: 'org-1', enforceHourCapHard: false),
      );
      expect(result.assignments, hasLength(2));
      expect(
        result.assignments.map((a) => a.overtimeMinutes).toList()..sort(),
        [0, 300],
      );

      await provider.applyAutoPlan(
        generatedShifts: generated,
        existingOpenShifts: const [],
        result: result,
      );

      final saved = provider.shifts;
      expect(saved, hasLength(2));
      final byId = {for (final s in saved) s.id: s};
      expect(byId['mon']!.overtimeMinutes, 0);
      expect(byId['tue']!.overtimeMinutes, 300);
    });

    test('W3/E3: manuelle Planung über Max persistiert overtimeMinutes '
        'ohne Blockade', () async {
      final provider = newProvider();
      addTearDown(provider.dispose);
      await provider.updateSession(admin);
      provider.setVisibleDate(DateTime(2026, 6, 15));
      await Future<void>.delayed(Duration.zero);
      provider.updateReferenceData(
        members: [employee],
        contracts: [contractFor('u1', monthlyMaxHours: 5)],
        siteAssignments: [assignmentFor('u1')],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const [],
        sites: [site],
      );

      // 8h-Schicht (netto 450 min) gegen Monats-Cap 5 h (300 min): manuelles
      // Speichern darf NICHT blockieren (Chef-Entscheidung), markiert aber
      // 150 min geplante Überstunden.
      await provider.saveShifts([
        Shift(
          orgId: 'org-1',
          userId: 'u1',
          employeeName: 'Uwe',
          title: 'Laden',
          startTime: DateTime(2026, 6, 15, 9),
          endTime: DateTime(2026, 6, 15, 17),
          breakMinutes: 30,
          siteId: 'site-1',
          siteName: 'Laden',
        ),
      ]);

      expect(provider.shifts, hasLength(1));
      expect(provider.shifts.single.overtimeMinutes, 150);
      expect(provider.shifts.single.hasPlannedOvertime, isTrue);
    });

    test('W3/E5: Sollzeit-Profile aus updatePersonalReferenceData steuern die '
        'Fairness-Ziele des Verteilers', () async {
      const employee2 = AppUserProfile(
        uid: 'u2',
        orgId: 'org-1',
        email: 'u2@example.com',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: 'Vera'),
      );
      final provider = newProvider();
      addTearDown(provider.dispose);
      await provider.updateSession(admin);
      provider.updateReferenceData(
        members: [employee, employee2],
        contracts: [contractFor('u1'), contractFor('u2')],
        siteAssignments: [assignmentFor('u1'), assignmentFor('u2')],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const [],
        sites: [site],
      );

      // Vorbelastung: u1 hat 4h, u2 hat 7,5h geplant (2026-06-01, Montag).
      await provider.saveShifts([
        Shift(
          orgId: 'org-1',
          userId: 'u1',
          employeeName: 'Uwe',
          title: 'Frueh',
          startTime: DateTime(2026, 6, 1, 9),
          endTime: DateTime(2026, 6, 1, 13),
          siteId: 'site-1',
          siteName: 'Laden',
        ),
        Shift(
          orgId: 'org-1',
          userId: 'u2',
          employeeName: 'Vera',
          title: 'Voll',
          startTime: DateTime(2026, 6, 1, 9),
          endTime: DateTime(2026, 6, 1, 17),
          breakMinutes: 30,
          siteId: 'site-1',
          siteName: 'Laden',
        ),
      ]);

      final open = Shift(
        id: 'open-1',
        orgId: 'org-1',
        userId: '',
        employeeName: '',
        title: 'Laden',
        startTime: DateTime(2026, 6, 2, 9),
        endTime: DateTime(2026, 6, 2, 13),
        siteId: 'site-1',
        siteName: 'Laden',
      );

      // OHNE Sollzeit fällt das Ziel auf die (identischen) Verträge zurück:
      // u1 ist weiter unter Ziel (240 < 450 geplante Minuten) → u1 gewinnt.
      final baseline = await provider.proposeAutoAssignment(
        openShifts: [open],
        month: DateTime(2026, 6, 1),
        settings: OrgSettings.defaults('org-1'),
      );
      expect(baseline.assignments.single.userId, 'u1');

      // MIT Sollzeit: u1 hat sein Mini-Soll (240 min/Woche) bereits erreicht,
      // u2 (2400 min/Woche) liegt weit darunter → u2 gewinnt. Beweist, dass
      // die gepushten Profile beim Assigner ankommen (E4 Sollzeit-first).
      provider.updatePersonalReferenceData(
        sollzeitProfiles: [
          SollzeitProfile(
            id: 'sz-u1',
            orgId: 'org-1',
            userId: 'u1',
            gueltigAb: DateTime(2026, 1, 1),
            montagMinutes: 240,
          ),
          SollzeitProfile(
            id: 'sz-u2',
            orgId: 'org-1',
            userId: 'u2',
            gueltigAb: DateTime(2026, 1, 1),
            montagMinutes: 480,
            dienstagMinutes: 480,
            mittwochMinutes: 480,
            donnerstagMinutes: 480,
            freitagMinutes: 480,
          ),
        ],
      );
      final withSollzeit = await provider.proposeAutoAssignment(
        openShifts: [open],
        month: DateTime(2026, 6, 1),
        settings: OrgSettings.defaults('org-1'),
      );
      expect(withSollzeit.assignments.single.userId, 'u2');
    });

    test('W3/E5: Austrittsdatum aus updatePersonalReferenceData schließt '
        'Mitarbeiter hart aus', () async {
      final provider = newProvider();
      addTearDown(provider.dispose);
      await provider.updateSession(admin);
      provider.updateReferenceData(
        members: [employee],
        contracts: [contractFor('u1')],
        siteAssignments: [assignmentFor('u1')],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const [],
        sites: [site],
      );
      provider.updatePersonalReferenceData(
        exitDateByUserId: {'u1': DateTime(2026, 6, 10)},
      );

      final open = Shift(
        id: 'open-1',
        orgId: 'org-1',
        userId: '',
        employeeName: '',
        title: 'Laden',
        startTime: DateTime(2026, 6, 15, 9),
        endTime: DateTime(2026, 6, 15, 13),
        siteId: 'site-1',
        siteName: 'Laden',
      );
      final result = await provider.proposeAutoAssignment(
        openShifts: [open],
        month: DateTime(2026, 6, 15),
        settings: OrgSettings.defaults('org-1'),
      );
      expect(result.assignments, isEmpty);
      expect(result.unassigned.single.reason, UnassignableReason.ausgeschieden);
    });

    test('W3: openShiftsInRange liefert offene Schichten trotz aktivem '
        'Mitarbeiter-Filter (ungefiltert, ohne stornierte)', () async {
      final provider = newProvider();
      addTearDown(provider.dispose);
      await provider.updateSession(admin);
      provider.updateReferenceData(
        members: [admin, employee],
        contracts: [contractFor('admin-1'), contractFor('u1')],
        siteAssignments: [assignmentFor('admin-1'), assignmentFor('u1')],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const [],
        sites: [site],
      );

      await provider.saveShifts([
        Shift(
          id: 'open-1',
          orgId: 'org-1',
          userId: '',
          employeeName: '',
          title: 'Offen',
          startTime: DateTime(2026, 6, 15, 9),
          endTime: DateTime(2026, 6, 15, 13),
          siteId: 'site-1',
          siteName: 'Laden',
        ),
        Shift(
          id: 'cancelled-1',
          orgId: 'org-1',
          userId: '',
          employeeName: '',
          title: 'Storniert',
          startTime: DateTime(2026, 6, 16, 9),
          endTime: DateTime(2026, 6, 16, 13),
          siteId: 'site-1',
          siteName: 'Laden',
          status: ShiftStatus.cancelled,
        ),
      ]);

      // Filter aktiv: `shifts` versteckt die offene Schicht.
      provider.setSelectedUserId('u1');
      await Future<void>.delayed(Duration.zero);

      final open = provider.openShiftsInRange(
        DateTimeRange(
          start: DateTime(2026, 6, 1),
          end: DateTime(2026, 7, 1),
        ),
      );
      expect(open.map((s) => s.id), ['open-1']);
    });
  });
}
