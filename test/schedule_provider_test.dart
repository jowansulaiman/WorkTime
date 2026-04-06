import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/absence_request.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/compliance_rule_set.dart';
import 'package:worktime_app/models/employee_site_assignment.dart';
import 'package:worktime_app/models/employment_contract.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/shift_template.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/schedule_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScheduleProvider local mode', () {
    late FirestoreService firestoreService;
    late AppUserProfile adminUser;
    late SiteDefinition defaultSite;
    late ComplianceRuleSet defaultRuleSet;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
      firestoreService = FirestoreService(
        firestore: FakeFirebaseFirestore(),
      );
      adminUser = const AppUserProfile(
        uid: 'admin-1',
        orgId: 'org-1',
        email: 'admin@example.com',
        role: UserRole.admin,
        isActive: true,
        settings: UserSettings(name: 'Admin'),
      );
      defaultSite = const SiteDefinition(
        id: 'site-1',
        orgId: 'org-1',
        name: 'Berlin',
      );
      defaultRuleSet = ComplianceRuleSet.defaultRetail('org-1');
    });

    void seedCompliance(
      ScheduleProvider provider, {
      List<AppUserProfile> members = const [],
      List<EmploymentContract> contracts = const [],
      List<EmployeeSiteAssignment> assignments = const [],
    }) {
      final seededMembers = [adminUser, ...members];
      provider.updateReferenceData(
        members: seededMembers,
        contracts: [
          EmploymentContract(
            id: 'contract-admin',
            orgId: adminUser.orgId,
            userId: adminUser.uid,
            validFrom: DateTime(2020, 1, 1),
            dailyHours: 8,
            weeklyHours: 40,
          ),
          ...contracts,
        ],
        siteAssignments: [
          EmployeeSiteAssignment(
            id: 'assignment-admin',
            orgId: adminUser.orgId,
            userId: adminUser.uid,
            siteId: defaultSite.id!,
            siteName: defaultSite.name,
            isPrimary: true,
          ),
          ...assignments,
        ],
        ruleSets: [defaultRuleSet],
        travelTimeRules: const [],
      );
    }

    EmploymentContract contractFor(String userId) {
      return EmploymentContract(
        id: 'contract-$userId',
        orgId: adminUser.orgId,
        userId: userId,
        validFrom: DateTime(2020, 1, 1),
        dailyHours: 8,
        weeklyHours: 40,
      );
    }

    EmployeeSiteAssignment assignmentFor({
      required String userId,
      required String siteId,
      required String siteName,
      bool isPrimary = true,
    }) {
      return EmployeeSiteAssignment(
        id: 'assignment-$userId-$siteId',
        orgId: adminUser.orgId,
        userId: userId,
        siteId: siteId,
        siteName: siteName,
        isPrimary: isPrimary,
      );
    }

    DateTime dayInCurrentWeek(int offsetFromMonday) {
      final today = DateTime.now();
      final weekStart = DateTime(
        today.year,
        today.month,
        today.day,
      ).subtract(Duration(days: today.weekday - 1));
      return weekStart.add(Duration(days: offsetFromMonday));
    }

    test('saves and reloads shifts locally when auth is disabled', () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(adminUser);
      seedCompliance(provider);

      final start = DateTime.now();
      final shiftStart = DateTime(
        start.year,
        start.month,
        start.day,
        8,
      );

      await provider.saveShift(
        Shift(
          orgId: adminUser.orgId,
          userId: adminUser.uid,
          employeeName: adminUser.displayName,
          title: 'Tagdienst',
          startTime: shiftStart,
          endTime: shiftStart.add(const Duration(hours: 8)),
          breakMinutes: 30,
          siteId: defaultSite.id,
          siteName: defaultSite.name,
          location: defaultSite.name,
        ),
      );

      expect(provider.shifts, hasLength(1));
      expect(provider.shifts.single.title, 'Tagdienst');

      final reloaded = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await reloaded.updateSession(adminUser);

      expect(reloaded.shifts, hasLength(1));
      expect(reloaded.shifts.single.title, 'Tagdienst');
    });

    test('reloads cloud shifts when switching back from local-only mode',
        () async {
      final remoteFirestore = FakeFirebaseFirestore();
      final remoteService = FirestoreService(firestore: remoteFirestore);
      final provider = ScheduleProvider(firestoreService: remoteService);
      final shiftDay = dayInCurrentWeek(1);
      final shiftStart = DateTime(
        shiftDay.year,
        shiftDay.month,
        shiftDay.day,
        8,
      );

      await remoteFirestore
          .collection('organizations')
          .doc(adminUser.orgId)
          .collection('shifts')
          .doc('cloud-shift')
          .set(
            Shift(
              orgId: adminUser.orgId,
              userId: adminUser.uid,
              employeeName: adminUser.displayName,
              title: 'Cloud-Schicht',
              startTime: shiftStart,
              endTime: shiftStart.add(const Duration(hours: 8)),
              breakMinutes: 30,
              siteId: defaultSite.id,
              siteName: defaultSite.name,
              location: defaultSite.name,
            ).toFirestoreMap(),
          );

      await provider.updateSession(adminUser, localStorageOnly: true);
      expect(provider.shifts, isEmpty);

      await provider.updateSession(adminUser, localStorageOnly: false);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.shifts, hasLength(1));
      expect(provider.shifts.single.title, 'Cloud-Schicht');
    });

    test('allows creating local shifts after caching cloud data locally',
        () async {
      final remoteFirestore = FakeFirebaseFirestore();
      final remoteService = FirestoreService(firestore: remoteFirestore);
      final provider = ScheduleProvider(firestoreService: remoteService);
      final firstDay = dayInCurrentWeek(1);
      final firstStart = DateTime(
        firstDay.year,
        firstDay.month,
        firstDay.day,
        8,
      );

      await remoteFirestore
          .collection('organizations')
          .doc(adminUser.orgId)
          .collection('shifts')
          .doc('cloud-shift')
          .set(
            Shift(
              orgId: adminUser.orgId,
              userId: adminUser.uid,
              employeeName: adminUser.displayName,
              title: 'Cloud-Schicht',
              startTime: firstStart,
              endTime: firstStart.add(const Duration(hours: 8)),
              breakMinutes: 30,
              siteId: defaultSite.id,
              siteName: defaultSite.name,
              location: defaultSite.name,
            ).toFirestoreMap(),
          );

      await provider.updateSession(adminUser);
      seedCompliance(provider);
      await provider.cacheCloudStateLocally();
      await provider.updateSession(adminUser, localStorageOnly: true);
      seedCompliance(provider);

      final secondDay = dayInCurrentWeek(2);
      final secondStart = DateTime(
        secondDay.year,
        secondDay.month,
        secondDay.day,
        10,
      );
      await provider.saveShift(
        Shift(
          orgId: adminUser.orgId,
          userId: adminUser.uid,
          employeeName: adminUser.displayName,
          title: 'Lokale Schicht',
          startTime: secondStart,
          endTime: secondStart.add(const Duration(hours: 8)),
          breakMinutes: 30,
          siteId: defaultSite.id,
          siteName: defaultSite.name,
          location: defaultSite.name,
        ),
      );

      expect(provider.shifts, hasLength(2));
      expect(
        provider.shifts.map((shift) => shift.title),
        containsAll(['Cloud-Schicht', 'Lokale Schicht']),
      );
    });

    test(
        'keeps local shifts when switching from local-only to hybrid with empty cloud',
        () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
      );
      final shiftDay = dayInCurrentWeek(1);
      final shiftStart = DateTime(
        shiftDay.year,
        shiftDay.month,
        shiftDay.day,
        8,
      );
      await DatabaseService.saveLocalShifts(
        [
          Shift(
            id: 'local-shift',
            orgId: adminUser.orgId,
            userId: adminUser.uid,
            employeeName: adminUser.displayName,
            title: 'Lokale Hybrid-Schicht',
            startTime: shiftStart,
            endTime: shiftStart.add(const Duration(hours: 8)),
            breakMinutes: 30,
            siteId: defaultSite.id,
            siteName: defaultSite.name,
            location: defaultSite.name,
          ),
        ],
        scope: LocalStorageScope.fromUser(adminUser),
      );

      await provider.updateSession(adminUser, localStorageOnly: true);

      expect(provider.shifts, hasLength(1));
      expect(provider.shifts.single.id, 'local-shift');

      await provider.updateSession(adminUser, hybridStorageEnabled: true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.shifts, hasLength(1));
      expect(provider.shifts.single.id, 'local-shift');
      expect(provider.shifts.single.location, 'Berlin');
    });

    test('stores hybrid shifts locally when cloud transfer fails', () async {
      final failingService = FirestoreService(
        firestore: FakeFirebaseFirestore(),
        cloudFunctionInvoker: (_, __) async {
          throw FirebaseFunctionsException(
            code: 'internal',
            message: 'save failed',
          );
        },
      );
      final provider = ScheduleProvider(firestoreService: failingService);
      final shiftDay = dayInCurrentWeek(2);
      final shiftStart = DateTime(
        shiftDay.year,
        shiftDay.month,
        shiftDay.day,
        9,
      );

      await provider.updateSession(adminUser, hybridStorageEnabled: true);
      seedCompliance(provider);

      await provider.saveShift(
        Shift(
          orgId: adminUser.orgId,
          userId: adminUser.uid,
          employeeName: adminUser.displayName,
          title: 'Hybrid-Fallback',
          startTime: shiftStart,
          endTime: shiftStart.add(const Duration(hours: 8)),
          breakMinutes: 30,
          siteId: defaultSite.id,
          siteName: defaultSite.name,
          location: defaultSite.name,
        ),
      );

      expect(provider.shifts, hasLength(1));
      expect(provider.shifts.single.title, 'Hybrid-Fallback');

      final persistedShifts = await DatabaseService.loadLocalShifts(
        scope: LocalStorageScope.fromUser(adminUser),
      );
      expect(persistedShifts, hasLength(1));
      expect(persistedShifts.single.location, 'Berlin');
    });

    test('stores and reloads shift templates locally', () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(adminUser);
      seedCompliance(provider);

      await provider.saveShiftTemplate(
        ShiftTemplate(
          name: 'Fruehdienst',
          title: 'Fruehdienst',
          startMinutes: 8 * 60,
          endMinutes: 16 * 60,
          breakMinutes: 30,
          siteId: defaultSite.id,
          siteName: defaultSite.name,
          teamId: 'team-1',
          teamName: 'Service',
          requiredQualificationIds: const ['q-1'],
          notes: 'Kasse zuerst besetzen',
          color: '#2196F3',
        ),
      );

      expect(provider.shiftTemplates, hasLength(1));
      expect(provider.shiftTemplates.single.name, 'Fruehdienst');
      expect(provider.shiftTemplates.single.siteName, 'Berlin');
      expect(provider.shiftTemplates.single.requiredQualificationIds, ['q-1']);

      final reloaded = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await reloaded.updateSession(adminUser);

      expect(reloaded.shiftTemplates, hasLength(1));
      expect(reloaded.shiftTemplates.single.name, 'Fruehdienst');
      expect(reloaded.shiftTemplates.single.teamName, 'Service');
    });

    test('stores and reviews absence requests locally', () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(adminUser);
      seedCompliance(provider);

      final today = DateTime.now();
      await provider.submitAbsenceRequest(
        AbsenceRequest(
          orgId: adminUser.orgId,
          userId: adminUser.uid,
          employeeName: adminUser.displayName,
          startDate: today,
          endDate: today.add(const Duration(days: 1)),
          type: AbsenceType.vacation,
        ),
      );

      expect(provider.absenceRequests, hasLength(1));
      final requestId = provider.absenceRequests.single.id;
      expect(provider.absenceRequests.single.status, AbsenceStatus.pending);

      await provider.reviewAbsenceRequest(
        requestId: requestId!,
        status: AbsenceStatus.approved,
      );

      expect(provider.absenceRequests.single.status, AbsenceStatus.approved);
    });

    test('updates own pending absence requests locally', () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      const employee = AppUserProfile(
        uid: 'employee-1',
        orgId: 'org-1',
        email: 'employee@example.com',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: 'Mira'),
      );

      await provider.updateSession(employee);
      seedCompliance(provider, members: const [employee]);

      final today = dayInCurrentWeek(1);
      final updatedStart = dayInCurrentWeek(2);
      final updatedEnd = dayInCurrentWeek(3);
      await provider.submitAbsenceRequest(
        AbsenceRequest(
          orgId: employee.orgId,
          userId: employee.uid,
          employeeName: employee.displayName,
          startDate: today,
          endDate: today,
          type: AbsenceType.vacation,
          note: 'Alt',
        ),
      );

      final existing = provider.absenceRequests.single;
      await provider.submitAbsenceRequest(
        existing.copyWith(
          startDate: updatedStart,
          endDate: updatedEnd,
          type: AbsenceType.unavailable,
          note: 'Neu',
        ),
      );

      expect(provider.absenceRequests, hasLength(1));
      expect(provider.absenceRequests.single.id, existing.id);
      expect(
        provider.absenceRequests.single.startDate.day,
        updatedStart.day,
      );
      expect(provider.absenceRequests.single.type, AbsenceType.unavailable);
      expect(provider.absenceRequests.single.note, 'Neu');
      expect(provider.absenceRequests.single.status, AbsenceStatus.pending);
    });

    test('keeps future own absence requests visible in the full request list',
        () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      const employee = AppUserProfile(
        uid: 'employee-1',
        orgId: 'org-1',
        email: 'employee@example.com',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: 'Mira'),
      );

      await provider.updateSession(employee);
      seedCompliance(provider, members: const [employee]);

      final futureStart = DateTime.now().add(const Duration(days: 45));
      await provider.submitAbsenceRequest(
        AbsenceRequest(
          orgId: employee.orgId,
          userId: employee.uid,
          employeeName: employee.displayName,
          startDate: futureStart,
          endDate: futureStart.add(const Duration(days: 2)),
          type: AbsenceType.vacation,
        ),
      );

      expect(provider.absenceRequests, isEmpty);
      expect(provider.allAbsenceRequests, hasLength(1));
      expect(provider.allAbsenceRequests.single.userId, employee.uid);
      expect(provider.allAbsenceRequests.single.status, AbsenceStatus.pending);
    });

    test('deletes own pending absence requests locally', () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      const employee = AppUserProfile(
        uid: 'employee-1',
        orgId: 'org-1',
        email: 'employee@example.com',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: 'Mira'),
      );

      await provider.updateSession(employee);
      seedCompliance(provider, members: const [employee]);

      final today = dayInCurrentWeek(1);
      final updatedStart = dayInCurrentWeek(3);
      final updatedEnd = dayInCurrentWeek(4);
      await provider.submitAbsenceRequest(
        AbsenceRequest(
          orgId: employee.orgId,
          userId: employee.uid,
          employeeName: employee.displayName,
          startDate: today,
          endDate: today,
          type: AbsenceType.vacation,
        ),
      );

      await provider.deleteAbsenceRequest(provider.absenceRequests.single.id!);

      expect(provider.absenceRequests, isEmpty);
    });

    test('does not update approved own absence requests locally', () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      const employee = AppUserProfile(
        uid: 'employee-1',
        orgId: 'org-1',
        email: 'employee@example.com',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: 'Mira'),
      );
      await provider.updateSession(employee);
      seedCompliance(provider, members: const [employee]);

      final today = dayInCurrentWeek(1);
      final updatedStart = dayInCurrentWeek(3);
      final updatedEnd = dayInCurrentWeek(4);
      await provider.submitAbsenceRequest(
        AbsenceRequest(
          orgId: employee.orgId,
          userId: employee.uid,
          employeeName: employee.displayName,
          startDate: today,
          endDate: today,
          type: AbsenceType.vacation,
        ),
      );

      final requestId = provider.absenceRequests.single.id!;
      await provider.updateSession(adminUser);
      seedCompliance(provider, members: const [employee]);
      await provider.reviewAbsenceRequest(
        requestId: requestId,
        status: AbsenceStatus.approved,
      );

      await provider.updateSession(employee);
      seedCompliance(provider, members: const [employee]);

      await expectLater(
        () => provider.submitAbsenceRequest(
          provider.absenceRequests.single.copyWith(note: 'Spaeter'),
        ),
        throwsStateError,
      );
      await expectLater(
        () => provider.deleteAbsenceRequest(requestId),
        throwsStateError,
      );
    });

    test('admin can update and delete approved employee vacations locally',
        () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      const employee = AppUserProfile(
        uid: 'employee-1',
        orgId: 'org-1',
        email: 'employee@example.com',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: 'Mira'),
      );

      await provider.updateSession(employee);
      seedCompliance(provider, members: const [employee]);

      final today = dayInCurrentWeek(1);
      final updatedStart = dayInCurrentWeek(3);
      final updatedEnd = dayInCurrentWeek(4);
      await provider.submitAbsenceRequest(
        AbsenceRequest(
          orgId: employee.orgId,
          userId: employee.uid,
          employeeName: employee.displayName,
          startDate: today,
          endDate: today,
          type: AbsenceType.vacation,
          note: 'Alt',
        ),
      );

      final requestId = provider.absenceRequests.single.id!;
      await provider.updateSession(adminUser);
      seedCompliance(provider, members: const [employee]);
      await provider.reviewAbsenceRequest(
        requestId: requestId,
        status: AbsenceStatus.approved,
      );

      await provider.submitAbsenceRequest(
        provider.absenceRequests.single.copyWith(
          startDate: updatedStart,
          endDate: updatedEnd,
          type: AbsenceType.sickness,
          note: 'Neu',
        ),
      );

      expect(provider.absenceRequests, hasLength(1));
      expect(provider.absenceRequests.single.userId, employee.uid);
      expect(provider.absenceRequests.single.type, AbsenceType.vacation);
      expect(provider.absenceRequests.single.note, 'Neu');
      expect(
        provider.absenceRequests.single.startDate.day,
        updatedStart.day,
      );

      await provider.deleteAbsenceRequest(requestId);

      expect(provider.absenceRequests, isEmpty);
      expect(provider.allAbsenceRequests, isEmpty);
    });

    test('teamlead can update and delete own approved vacations locally',
        () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      const teamLead = AppUserProfile(
        uid: 'lead-1',
        orgId: 'org-1',
        email: 'lead@example.com',
        role: UserRole.teamlead,
        isActive: true,
        settings: UserSettings(name: 'Lead'),
      );

      await provider.updateSession(teamLead);
      seedCompliance(provider, members: const [teamLead]);

      final today = dayInCurrentWeek(1);
      final updatedStart = dayInCurrentWeek(3);
      final updatedEnd = dayInCurrentWeek(4);
      await provider.submitAbsenceRequest(
        AbsenceRequest(
          orgId: teamLead.orgId,
          userId: teamLead.uid,
          employeeName: teamLead.displayName,
          startDate: today,
          endDate: today,
          type: AbsenceType.vacation,
          note: 'Alt',
        ),
      );

      final requestId = provider.absenceRequests.single.id!;
      await provider.updateSession(adminUser);
      seedCompliance(provider, members: const [teamLead]);
      await provider.reviewAbsenceRequest(
        requestId: requestId,
        status: AbsenceStatus.approved,
      );

      await provider.updateSession(teamLead);
      seedCompliance(provider, members: const [teamLead]);

      await provider.submitAbsenceRequest(
        provider.absenceRequests.single.copyWith(
          startDate: updatedStart,
          endDate: updatedEnd,
          note: 'Verschoben',
        ),
      );

      expect(provider.absenceRequests.single.userId, teamLead.uid);
      expect(provider.absenceRequests.single.type, AbsenceType.vacation);
      expect(provider.absenceRequests.single.note, 'Verschoben');

      await provider.deleteAbsenceRequest(requestId);

      expect(provider.absenceRequests, isEmpty);
    });

    test('teamlead can update approved employee vacations locally', () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      const teamLead = AppUserProfile(
        uid: 'lead-1',
        orgId: 'org-1',
        email: 'lead@example.com',
        role: UserRole.teamlead,
        isActive: true,
        settings: UserSettings(name: 'Lead'),
      );
      const employee = AppUserProfile(
        uid: 'employee-1',
        orgId: 'org-1',
        email: 'employee@example.com',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: 'Employee'),
      );

      await provider.updateSession(employee);
      seedCompliance(provider, members: const [teamLead, employee]);

      final today = DateTime.now();
      await provider.submitAbsenceRequest(
        AbsenceRequest(
          orgId: employee.orgId,
          userId: employee.uid,
          employeeName: employee.displayName,
          startDate: today,
          endDate: today,
          type: AbsenceType.vacation,
        ),
      );

      final requestId = provider.absenceRequests.single.id!;
      await provider.updateSession(teamLead);
      seedCompliance(provider, members: const [teamLead, employee]);
      await provider.reviewAbsenceRequest(
        requestId: requestId,
        status: AbsenceStatus.approved,
      );

      await provider.submitAbsenceRequest(
        provider.absenceRequests.single.copyWith(
          endDate: today.add(const Duration(days: 2)),
          note: 'Erweitert',
        ),
      );

      expect(provider.absenceRequests.single.userId, employee.uid);
      expect(
        provider.absenceRequests.single.endDate.day,
        today.add(const Duration(days: 2)).day,
      );
      expect(provider.absenceRequests.single.note, 'Erweitert');
    });

    test('teamlead cannot update approved admin vacations locally', () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      const teamLead = AppUserProfile(
        uid: 'lead-1',
        orgId: 'org-1',
        email: 'lead@example.com',
        role: UserRole.teamlead,
        isActive: true,
        settings: UserSettings(name: 'Lead'),
      );

      await provider.updateSession(adminUser);
      seedCompliance(provider, members: const [teamLead]);

      final today = DateTime.now();
      await provider.submitAbsenceRequest(
        AbsenceRequest(
          orgId: adminUser.orgId,
          userId: adminUser.uid,
          employeeName: adminUser.displayName,
          startDate: today,
          endDate: today,
          type: AbsenceType.vacation,
        ),
      );

      final requestId = provider.absenceRequests.single.id!;
      await provider.reviewAbsenceRequest(
        requestId: requestId,
        status: AbsenceStatus.approved,
      );

      await provider.updateSession(teamLead);
      seedCompliance(provider, members: const [teamLead]);

      await expectLater(
        () => provider.submitAbsenceRequest(
          provider.absenceRequests.single.copyWith(note: 'Nicht erlaubt'),
        ),
        throwsStateError,
      );
      await expectLater(
        () => provider.deleteAbsenceRequest(requestId),
        throwsStateError,
      );
    });

    test('teamlead sends own requests but cannot review them locally',
        () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      const teamLead = AppUserProfile(
        uid: 'lead-1',
        orgId: 'org-1',
        email: 'lead@example.com',
        role: UserRole.teamlead,
        isActive: true,
        settings: UserSettings(name: 'Lead'),
      );

      await provider.updateSession(teamLead);
      seedCompliance(provider, members: const [teamLead]);

      final today = DateTime.now();
      await provider.submitAbsenceRequest(
        AbsenceRequest(
          orgId: teamLead.orgId,
          userId: teamLead.uid,
          employeeName: teamLead.displayName,
          startDate: today,
          endDate: today,
          type: AbsenceType.vacation,
        ),
      );

      await expectLater(
        () => provider.reviewAbsenceRequest(
          requestId: provider.absenceRequests.single.id!,
          status: AbsenceStatus.approved,
        ),
        throwsStateError,
      );
      expect(provider.absenceRequests.single.status, AbsenceStatus.pending);
    });

    test('teamlead can review employee requests locally', () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      const teamLead = AppUserProfile(
        uid: 'lead-1',
        orgId: 'org-1',
        email: 'lead@example.com',
        role: UserRole.teamlead,
        isActive: true,
        settings: UserSettings(name: 'Lead'),
      );
      const employee = AppUserProfile(
        uid: 'employee-1',
        orgId: 'org-1',
        email: 'employee@example.com',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: 'Employee'),
      );

      await provider.updateSession(employee);
      seedCompliance(provider, members: const [teamLead, employee]);

      final today = DateTime.now();
      await provider.submitAbsenceRequest(
        AbsenceRequest(
          orgId: employee.orgId,
          userId: employee.uid,
          employeeName: employee.displayName,
          startDate: today,
          endDate: today,
          type: AbsenceType.unavailable,
        ),
      );

      await provider.updateSession(teamLead);
      seedCompliance(provider, members: const [teamLead, employee]);

      await provider.reviewAbsenceRequest(
        requestId: provider.absenceRequests.single.id!,
        status: AbsenceStatus.approved,
      );

      expect(provider.absenceRequests.single.status, AbsenceStatus.approved);
    });

    test('saves the same shift for multiple employees locally', () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(adminUser);
      const members = [
        AppUserProfile(
          uid: 'employee-1',
          orgId: 'org-1',
          email: 'anna@example.com',
          role: UserRole.employee,
          isActive: true,
          settings: UserSettings(name: 'Anna'),
        ),
        AppUserProfile(
          uid: 'employee-2',
          orgId: 'org-1',
          email: 'ben@example.com',
          role: UserRole.employee,
          isActive: true,
          settings: UserSettings(name: 'Ben'),
        ),
      ];
      seedCompliance(
        provider,
        members: members,
        contracts: members.map((member) => contractFor(member.uid)).toList(),
        assignments: members
            .map(
              (member) => assignmentFor(
                userId: member.uid,
                siteId: defaultSite.id!,
                siteName: defaultSite.name,
              ),
            )
            .toList(),
      );

      final shiftStart = DateTime(2026, 4, 1, 8);
      await provider.saveShifts([
        Shift(
          orgId: adminUser.orgId,
          userId: 'employee-1',
          employeeName: 'Anna',
          title: 'Fruehdienst',
          startTime: shiftStart,
          endTime: shiftStart.add(const Duration(hours: 8)),
          breakMinutes: 30,
          siteId: defaultSite.id,
          siteName: defaultSite.name,
          location: defaultSite.name,
          teamId: 'team-1',
          team: 'Service',
        ),
        Shift(
          orgId: adminUser.orgId,
          userId: 'employee-2',
          employeeName: 'Ben',
          title: 'Fruehdienst',
          startTime: shiftStart,
          endTime: shiftStart.add(const Duration(hours: 8)),
          breakMinutes: 30,
          siteId: defaultSite.id,
          siteName: defaultSite.name,
          location: defaultSite.name,
          teamId: 'team-1',
          team: 'Service',
        ),
      ]);

      provider.setVisibleDate(DateTime(2026, 4, 1));
      expect(provider.shifts, hasLength(2));
      expect(provider.shifts.map((shift) => shift.employeeName), [
        'Anna',
        'Ben',
      ]);
      expect(provider.shifts.every((shift) => shift.team == 'Service'), isTrue);
    });

    test('filters shifts by saved team id and fallback team name', () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(adminUser);
      const members = [
        AppUserProfile(
          uid: 'employee-1',
          orgId: 'org-1',
          email: 'anna@example.com',
          role: UserRole.employee,
          isActive: true,
          settings: UserSettings(name: 'Anna'),
        ),
        AppUserProfile(
          uid: 'employee-2',
          orgId: 'org-1',
          email: 'ben@example.com',
          role: UserRole.employee,
          isActive: true,
          settings: UserSettings(name: 'Ben'),
        ),
        AppUserProfile(
          uid: 'employee-3',
          orgId: 'org-1',
          email: 'chris@example.com',
          role: UserRole.employee,
          isActive: true,
          settings: UserSettings(name: 'Chris'),
        ),
      ];
      seedCompliance(
        provider,
        members: members,
        contracts: members.map((member) => contractFor(member.uid)).toList(),
        assignments: members
            .map(
              (member) => assignmentFor(
                userId: member.uid,
                siteId: defaultSite.id!,
                siteName: defaultSite.name,
              ),
            )
            .toList(),
      );

      final now = DateTime.now();
      final shiftStart = DateTime(now.year, now.month, now.day, 8);
      await provider.saveShifts([
        Shift(
          orgId: adminUser.orgId,
          userId: 'employee-1',
          employeeName: 'Anna',
          title: 'Fruehdienst',
          startTime: shiftStart,
          endTime: shiftStart.add(const Duration(hours: 8)),
          breakMinutes: 30,
          siteId: defaultSite.id,
          siteName: defaultSite.name,
          location: defaultSite.name,
          teamId: 'team-1',
          team: 'Service',
        ),
        Shift(
          orgId: adminUser.orgId,
          userId: 'employee-2',
          employeeName: 'Ben',
          title: 'Spaetdienst',
          startTime: shiftStart.add(const Duration(hours: 1)),
          endTime: shiftStart.add(const Duration(hours: 9)),
          breakMinutes: 30,
          siteId: defaultSite.id,
          siteName: defaultSite.name,
          location: defaultSite.name,
          team: 'Service',
        ),
        Shift(
          orgId: adminUser.orgId,
          userId: 'employee-3',
          employeeName: 'Chris',
          title: 'Office',
          startTime: shiftStart,
          endTime: shiftStart.add(const Duration(hours: 6)),
          siteId: defaultSite.id,
          siteName: defaultSite.name,
          location: defaultSite.name,
          teamId: 'team-2',
          team: 'Verwaltung',
        ),
      ]);

      provider.setTeamFilter('team-1', teamName: 'Service');

      expect(provider.shifts, hasLength(2));
      expect(
        provider.shifts.map((shift) => shift.employeeName).toList(),
        ['Anna', 'Ben'],
      );
    });

    test('collects all conflicts for multi shift planning', () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(adminUser);
      seedCompliance(provider);

      final day = DateTime.now();
      final baseStart = DateTime(day.year, day.month, day.day, 8);

      await provider.saveShift(
        Shift(
          orgId: adminUser.orgId,
          userId: adminUser.uid,
          employeeName: adminUser.displayName,
          title: 'Bestehende Schicht',
          startTime: baseStart,
          endTime: baseStart.add(const Duration(hours: 4)),
          siteId: defaultSite.id,
          siteName: defaultSite.name,
          location: defaultSite.name,
        ),
      );

      await provider.submitAbsenceRequest(
        AbsenceRequest(
          orgId: adminUser.orgId,
          userId: adminUser.uid,
          employeeName: adminUser.displayName,
          startDate: baseStart,
          endDate: baseStart,
          type: AbsenceType.vacation,
        ),
      );
      await provider.reviewAbsenceRequest(
        requestId: provider.absenceRequests.single.id!,
        status: AbsenceStatus.approved,
      );

      final issues = await provider.validateShifts([
        Shift(
          orgId: adminUser.orgId,
          userId: adminUser.uid,
          employeeName: adminUser.displayName,
          title: 'Neue Schicht A',
          startTime: baseStart.add(const Duration(hours: 1)),
          endTime: baseStart.add(const Duration(hours: 5)),
          siteId: defaultSite.id,
          siteName: defaultSite.name,
          location: defaultSite.name,
        ),
        Shift(
          orgId: adminUser.orgId,
          userId: adminUser.uid,
          employeeName: adminUser.displayName,
          title: 'Neue Schicht B',
          startTime: baseStart.add(const Duration(hours: 3)),
          endTime: baseStart.add(const Duration(hours: 7)),
          siteId: defaultSite.id,
          siteName: defaultSite.name,
          location: defaultSite.name,
        ),
      ]);

      expect(issues, hasLength(2));
      expect(
        issues.every((issue) => issue.conflictingShifts.isNotEmpty),
        isTrue,
      );
      expect(
        issues.every((issue) => issue.blockingAbsences.isNotEmpty),
        isTrue,
      );
      expect(
        issues.every((issue) => issue.conflictingDraftShifts.isNotEmpty),
        isTrue,
      );
    });

    test(
        'ignores approved absences from other employees for unassigned shifts in firestore mode',
        () async {
      final remoteFirestore = FakeFirebaseFirestore();
      final remoteService = FirestoreService(firestore: remoteFirestore);
      final provider = ScheduleProvider(firestoreService: remoteService);
      await provider.updateSession(adminUser);
      seedCompliance(provider);

      await remoteService.saveAbsenceRequest(
        AbsenceRequest(
          orgId: adminUser.orgId,
          userId: 'employee-1',
          employeeName: 'Anna',
          startDate: DateTime(2026, 4, 6),
          endDate: DateTime(2026, 4, 6),
          type: AbsenceType.vacation,
          status: AbsenceStatus.approved,
        ),
      );

      final issues = await provider.validateShifts([
        Shift(
          orgId: adminUser.orgId,
          userId: '',
          employeeName: 'Freie Schicht',
          title: 'Offene Schicht',
          startTime: DateTime(2026, 4, 6, 9),
          endTime: DateTime(2026, 4, 6, 17),
          breakMinutes: 30,
          siteId: defaultSite.id,
          siteName: defaultSite.name,
          location: defaultSite.name,
        ),
      ]);

      expect(issues, isEmpty);
    });

    test(
        'marks employees as unavailable across locations and suggests free ones',
        () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(adminUser);

      const members = [
        AppUserProfile(
          uid: 'employee-1',
          orgId: 'org-1',
          email: 'anna@example.com',
          role: UserRole.employee,
          isActive: true,
          settings: UserSettings(name: 'Anna'),
        ),
        AppUserProfile(
          uid: 'employee-2',
          orgId: 'org-1',
          email: 'ben@example.com',
          role: UserRole.employee,
          isActive: true,
          settings: UserSettings(name: 'Ben'),
        ),
        AppUserProfile(
          uid: 'employee-3',
          orgId: 'org-1',
          email: 'chris@example.com',
          role: UserRole.employee,
          isActive: true,
          settings: UserSettings(name: 'Chris'),
        ),
      ];
      seedCompliance(
        provider,
        members: members,
        contracts: [
          EmploymentContract(
            id: 'contract-1',
            orgId: 'org-1',
            userId: 'employee-1',
            validFrom: DateTime(2020, 1, 1),
            dailyHours: 8,
            weeklyHours: 40,
          ),
          EmploymentContract(
            id: 'contract-2',
            orgId: 'org-1',
            userId: 'employee-2',
            validFrom: DateTime(2020, 1, 1),
            dailyHours: 8,
            weeklyHours: 40,
          ),
          EmploymentContract(
            id: 'contract-3',
            orgId: 'org-1',
            userId: 'employee-3',
            validFrom: DateTime(2020, 1, 1),
            dailyHours: 8,
            weeklyHours: 40,
          ),
        ],
        assignments: [
          const EmployeeSiteAssignment(
            id: 'assign-1',
            orgId: 'org-1',
            userId: 'employee-1',
            siteId: 'site-1',
            siteName: 'Berlin',
            isPrimary: true,
          ),
          const EmployeeSiteAssignment(
            id: 'assign-2',
            orgId: 'org-1',
            userId: 'employee-2',
            siteId: 'site-1',
            siteName: 'Berlin',
            isPrimary: true,
          ),
          const EmployeeSiteAssignment(
            id: 'assign-3',
            orgId: 'org-1',
            userId: 'employee-3',
            siteId: 'site-2',
            siteName: 'Hamburg',
            isPrimary: true,
          ),
        ],
      );

      final start = DateTime(2026, 4, 2, 8);
      final end = start.add(const Duration(hours: 8));

      await provider.saveShift(
        Shift(
          orgId: adminUser.orgId,
          userId: 'employee-1',
          employeeName: 'Anna',
          title: 'Fruehdienst',
          startTime: start,
          endTime: end,
          breakMinutes: 30,
          siteId: 'site-1',
          siteName: 'Berlin',
          location: 'Berlin',
        ),
      );

      await provider.saveShift(
        Shift(
          orgId: adminUser.orgId,
          userId: 'employee-3',
          employeeName: 'Chris',
          title: 'Schulung',
          startTime: start.add(const Duration(hours: 2)),
          endTime: end.add(const Duration(hours: 1)),
          breakMinutes: 30,
          siteId: 'site-2',
          siteName: 'Hamburg',
          location: 'Hamburg',
        ),
      );

      final availability = await provider.loadAssigneeAvailability(
        members: members,
        startTime: start.add(const Duration(hours: 1)),
        endTime: start.add(const Duration(hours: 5)),
        siteId: 'site-1',
        siteName: 'Berlin',
        shiftTitle: 'Vorschau',
      );

      final anna =
          availability.firstWhere((entry) => entry.member.uid == 'employee-1');
      final ben =
          availability.firstWhere((entry) => entry.member.uid == 'employee-2');
      final chris =
          availability.firstWhere((entry) => entry.member.uid == 'employee-3');

      expect(anna.isAvailable, isFalse);
      expect(anna.conflictingShifts, hasLength(1));
      expect(anna.conflictingShifts.single.location, 'Berlin');

      expect(ben.isAvailable, isTrue);
      expect(ben.conflictingShifts, isEmpty);
      expect(ben.blockingAbsences, isEmpty);

      expect(chris.isAvailable, isFalse);
      expect(chris.conflictingShifts, hasLength(1));
      expect(chris.conflictingShifts.single.location, 'Hamburg');
    });

    test('uses break minutes for availability compliance checks', () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(adminUser);

      const member = AppUserProfile(
        uid: 'employee-1',
        orgId: 'org-1',
        email: 'anna@example.com',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: 'Anna'),
      );

      seedCompliance(
        provider,
        members: const [member],
        contracts: [contractFor(member.uid)],
        assignments: [
          assignmentFor(
            userId: member.uid,
            siteId: defaultSite.id!,
            siteName: defaultSite.name,
          ),
        ],
      );

      final start = DateTime(2026, 3, 30, 13);
      final end = DateTime(2026, 3, 30, 19, 15);

      final withoutBreak = await provider.loadAssigneeAvailability(
        members: const [member],
        startTime: start,
        endTime: end,
        breakMinutes: 0,
        siteId: defaultSite.id,
        siteName: defaultSite.name,
        shiftTitle: 'Spaetdienst',
      );
      final withBreak = await provider.loadAssigneeAvailability(
        members: const [member],
        startTime: start,
        endTime: end,
        breakMinutes: 30,
        siteId: defaultSite.id,
        siteName: defaultSite.name,
        shiftTitle: 'Spaetdienst',
      );

      expect(withoutBreak.single.isAvailable, isFalse);
      expect(
        withoutBreak.single.blockingViolations.map((item) => item.code),
        contains('break_required'),
      );

      expect(withBreak.single.isAvailable, isTrue);
      expect(
        withBreak.single.blockingViolations.map((item) => item.code),
        isNot(contains('break_required')),
      );
    });

    test('blocks planning when site assignment is missing', () async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(adminUser);

      const employee = AppUserProfile(
        uid: 'employee-1',
        orgId: 'org-1',
        email: 'anna@example.com',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: 'Anna'),
      );

      seedCompliance(
        provider,
        members: const [employee],
        contracts: [
          EmploymentContract(
            id: 'contract-1',
            orgId: 'org-1',
            userId: 'employee-1',
            validFrom: DateTime(2020, 1, 1),
            dailyHours: 8,
            weeklyHours: 40,
          ),
        ],
      );

      final issues = await provider.validateShifts([
        Shift(
          orgId: adminUser.orgId,
          userId: employee.uid,
          employeeName: employee.displayName,
          title: 'Spaetdienst',
          startTime: DateTime(2026, 4, 3, 12),
          endTime: DateTime(2026, 4, 3, 20),
          siteId: 'site-2',
          siteName: 'Hamburg',
          location: 'Hamburg',
        ),
      ]);

      expect(issues, hasLength(1));
      expect(
        issues.single.blockingViolations
            .map((item) => item.code)
            .contains('site_assignment_missing'),
        isTrue,
      );
    });
  });
}
