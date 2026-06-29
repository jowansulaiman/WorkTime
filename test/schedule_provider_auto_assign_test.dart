import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/compliance_rule_set.dart';
import 'package:worktime_app/models/employee_site_assignment.dart';
import 'package:worktime_app/models/employment_contract.dart';
import 'package:worktime_app/models/org_settings.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/site_schedule.dart';
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
  });
}
