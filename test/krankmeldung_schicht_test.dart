import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/absence_request.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/compliance_rule_set.dart';
import 'package:worktime_app/models/employee_site_assignment.dart';
import 'package:worktime_app/models/employment_contract.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/schedule_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

extension _SaveSingleShift on ScheduleProvider {
  Future<void> saveShift(Shift shift) => saveShifts([shift]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Modell: Chef gibt frei. Selbst-Krankmeldung eines Mitarbeiters gibt die
  // Schicht erst frei, wenn der Chef sie genehmigt; meldet der Chef selbst
  // krank, sofort.
  group('Krankmeldung gibt Schichten frei (Chef gibt frei)', () {
    late FirestoreService firestoreService;
    late AppUserProfile admin;
    late AppUserProfile empA;
    late SiteDefinition site;
    late ComplianceRuleSet ruleSet;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
      firestoreService = FirestoreService(firestore: FakeFirebaseFirestore());
      admin = const AppUserProfile(
        uid: 'admin-1',
        orgId: 'org-1',
        email: 'admin@example.com',
        role: UserRole.admin,
        isActive: true,
        settings: UserSettings(name: 'Chef'),
      );
      empA = const AppUserProfile(
        uid: 'emp-a',
        orgId: 'org-1',
        email: 'anna@example.com',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: 'Anna'),
      );
      site = const SiteDefinition(id: 'site-1', orgId: 'org-1', name: 'Kiel');
      ruleSet = ComplianceRuleSet.defaultRetail('org-1');
    });

    void seedReferenceData(ScheduleProvider provider) {
      provider.updateReferenceData(
        members: [admin, empA],
        contracts: [
          EmploymentContract(
            id: 'contract-admin',
            orgId: 'org-1',
            userId: 'admin-1',
            validFrom: DateTime(2020, 1, 1),
            dailyHours: 8,
            weeklyHours: 40,
          ),
          EmploymentContract(
            id: 'contract-a',
            orgId: 'org-1',
            userId: 'emp-a',
            validFrom: DateTime(2020, 1, 1),
            dailyHours: 8,
            weeklyHours: 40,
          ),
        ],
        siteAssignments: [
          EmployeeSiteAssignment(
            id: 'assignment-admin',
            orgId: 'org-1',
            userId: 'admin-1',
            siteId: site.id!,
            siteName: site.name,
            isPrimary: true,
          ),
          EmployeeSiteAssignment(
            id: 'assignment-a',
            orgId: 'org-1',
            userId: 'emp-a',
            siteId: site.id!,
            siteName: site.name,
            isPrimary: true,
          ),
        ],
        sites: [site],
        ruleSets: [ruleSet],
        travelTimeRules: const [],
      );
    }

    DateTime dayThisWeek(int offsetFromMonday, int hour) {
      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      return monday.add(Duration(days: offsetFromMonday, hours: hour));
    }

    Shift shiftFor(
      String userId,
      String name,
      DateTime start, {
      ShiftStatus status = ShiftStatus.planned,
    }) =>
        Shift(
          orgId: 'org-1',
          userId: userId,
          employeeName: name,
          title: 'Dienst',
          startTime: start,
          endTime: start.add(const Duration(hours: 8)),
          breakMinutes: 30,
          siteId: site.id,
          siteName: site.name,
          location: site.name,
          status: status,
        );

    AbsenceRequest absenceFor(
      String userId,
      String name,
      DateTime day,
      AbsenceType type,
    ) =>
        AbsenceRequest(
          orgId: 'org-1',
          userId: userId,
          employeeName: name,
          startDate: day,
          endDate: day,
          type: type,
        );

    Future<ScheduleProvider> bootProvider() async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      addTearDown(provider.dispose);
      await provider.updateSession(admin);
      seedReferenceData(provider);
      await Future<void>.delayed(Duration.zero);
      return provider;
    }

    Future<void> asAdmin(ScheduleProvider provider) async {
      await provider.updateSession(admin);
      provider.setSelectedUserId(null);
      await Future<void>.delayed(Duration.zero);
    }

    Future<String> submitAsEmployee(
      ScheduleProvider provider,
      AbsenceType type,
      DateTime day,
    ) async {
      await provider.updateSession(empA);
      await Future<void>.delayed(Duration.zero);
      await provider
          .submitAbsenceRequest(absenceFor('emp-a', 'Anna', day, type));
      return provider.allAbsenceRequests
          .firstWhere((absence) => absence.type == type)
          .id!;
    }

    Shift shiftById(ScheduleProvider provider, String? id) =>
        provider.shifts.firstWhere((shift) => shift.id == id);

    test('Mitarbeiter-Krankmeldung: erst nach Chef-Genehmigung frei', () async {
      final provider = await bootProvider();
      await provider.saveShift(shiftFor('emp-a', 'Anna', dayThisWeek(0, 8)));
      final shiftId = provider.shifts.single.id;

      final requestId =
          await submitAsEmployee(provider, AbsenceType.sickness, dayThisWeek(0, 0));

      // Vor der Genehmigung: Schicht bleibt zugewiesen.
      await asAdmin(provider);
      expect(shiftById(provider, shiftId).userId, 'emp-a');

      // Chef genehmigt -> Schicht wird frei.
      await provider.reviewAbsenceRequest(
        requestId: requestId,
        status: AbsenceStatus.approved,
      );
      await Future<void>.delayed(Duration.zero);

      final freed = shiftById(provider, shiftId);
      expect(freed.isUnassigned, true);
      expect(freed.userId, '');
      expect(freed.status, ShiftStatus.planned);
    });

    test('Chef-Selbst-Krankmeldung: Schicht sofort frei', () async {
      final provider = await bootProvider();
      await provider.saveShift(shiftFor('admin-1', 'Chef', dayThisWeek(0, 8)));
      final shiftId = provider.shifts.single.id;

      await provider.submitAbsenceRequest(
        absenceFor('admin-1', 'Chef', dayThisWeek(0, 0), AbsenceType.sickness),
      );
      await Future<void>.delayed(Duration.zero);

      expect(shiftById(provider, shiftId).isUnassigned, true);
    });

    test('Kind krank: nach Chef-Genehmigung frei', () async {
      final provider = await bootProvider();
      await provider.saveShift(shiftFor('emp-a', 'Anna', dayThisWeek(0, 8)));
      final shiftId = provider.shifts.single.id;

      final requestId = await submitAsEmployee(
        provider,
        AbsenceType.childSick,
        dayThisWeek(0, 0),
      );
      await asAdmin(provider);
      await provider.reviewAbsenceRequest(
        requestId: requestId,
        status: AbsenceStatus.approved,
      );
      await Future<void>.delayed(Duration.zero);

      expect(shiftById(provider, shiftId).isUnassigned, true);
    });

    test('Urlaub-Genehmigung gibt die Schicht NICHT frei', () async {
      final provider = await bootProvider();
      await provider.saveShift(shiftFor('emp-a', 'Anna', dayThisWeek(0, 8)));
      final shiftId = provider.shifts.single.id;

      final requestId = await submitAsEmployee(
        provider,
        AbsenceType.vacation,
        dayThisWeek(0, 0),
      );
      await asAdmin(provider);
      await provider.reviewAbsenceRequest(
        requestId: requestId,
        status: AbsenceStatus.approved,
      );
      await Future<void>.delayed(Duration.zero);

      expect(shiftById(provider, shiftId).userId, 'emp-a');
    });

    test('Abgesagte Schicht bleibt auch bei genehmigter Krankmeldung', () async {
      final provider = await bootProvider();
      await provider.saveShift(
        shiftFor('emp-a', 'Anna', dayThisWeek(0, 8),
            status: ShiftStatus.cancelled),
      );
      final shiftId = provider.shifts.single.id;

      final requestId = await submitAsEmployee(
        provider,
        AbsenceType.sickness,
        dayThisWeek(0, 0),
      );
      await asAdmin(provider);
      await provider.reviewAbsenceRequest(
        requestId: requestId,
        status: AbsenceStatus.approved,
      );
      await Future<void>.delayed(Duration.zero);

      final shift = shiftById(provider, shiftId);
      expect(shift.userId, 'emp-a');
      expect(shift.status, ShiftStatus.cancelled);
    });

    test('Schicht außerhalb des Krank-Zeitraums bleibt zugewiesen', () async {
      final provider = await bootProvider();
      // Krank am Montag, Schicht am Mittwoch.
      await provider.saveShift(shiftFor('emp-a', 'Anna', dayThisWeek(2, 8)));
      final shiftId = provider.shifts.single.id;

      final requestId = await submitAsEmployee(
        provider,
        AbsenceType.sickness,
        dayThisWeek(0, 0),
      );
      await asAdmin(provider);
      await provider.reviewAbsenceRequest(
        requestId: requestId,
        status: AbsenceStatus.approved,
      );
      await Future<void>.delayed(Duration.zero);

      expect(shiftById(provider, shiftId).userId, 'emp-a');
    });
  });
}
