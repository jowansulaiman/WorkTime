import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/compliance_rule_set.dart';
import 'package:worktime_app/models/employee_site_assignment.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/travel_time_rule.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/providers/work_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

class _TestWorkProvider extends WorkProvider {
  _TestWorkProvider({
    required super.firestoreService,
    this.onAddEntry,
    this.onAddEntries,
  });

  final Future<void> Function(WorkEntry entry)? onAddEntry;
  final Future<void> Function(List<WorkEntry> entries)? onAddEntries;

  @override
  Future<void> addEntry(WorkEntry entry) async {
    if (onAddEntry != null) {
      await onAddEntry!(entry);
      return;
    }
    await super.addEntry(entry);
  }

  @override
  Future<void> addEntries(List<WorkEntry> entries) async {
    if (onAddEntries != null) {
      await onAddEntries!(entries);
      return;
    }
    await super.addEntries(entries);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkProvider clocking', () {
    late FirestoreService firestoreService;
    late FakeFirebaseFirestore firestore;
    late AppUserProfile user;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
      firestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(
        firestore: firestore,
      );
      user = const AppUserProfile(
        uid: 'employee-1',
        orgId: 'org-1',
        email: 'anna@example.com',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: 'Anna'),
      );
    });

    Future<void> seedCurrentShift({
      String id = 'shift-1',
      DateTime? start,
      DateTime? end,
      ShiftStatus status = ShiftStatus.confirmed,
    }) async {
      final now = DateTime.now();
      final shift = Shift(
        id: id,
        orgId: user.orgId,
        userId: user.uid,
        employeeName: user.displayName,
        title: 'Tagdienst',
        startTime: start ?? now.subtract(const Duration(hours: 1)),
        endTime: end ?? now.add(const Duration(hours: 6)),
        breakMinutes: 30,
        siteId: 'site-1',
        siteName: 'Berlin',
        location: 'Berlin',
        status: status,
      );
      await firestore
          .collection('organizations')
          .doc(user.orgId)
          .collection('shifts')
          .doc(id)
          .set(shift.toFirestoreMap());
    }

    test('keeps clock running when saving after clock out fails', () async {
      final provider = _TestWorkProvider(
        firestoreService: firestoreService,
        onAddEntry: (_) async {
          throw StateError('save failed');
        },
      );
      await provider.updateSession(user);
      provider.updateReferenceData(
        sites: const [],
        contracts: const [],
        siteAssignments: const [
          EmployeeSiteAssignment(
            id: 'assign-1',
            orgId: 'org-1',
            userId: 'employee-1',
            siteId: 'site-1',
            siteName: 'Berlin',
            isPrimary: true,
          ),
        ],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const <TravelTimeRule>[],
      );
      await seedCurrentShift();

      await provider.clockIn();
      final clockInTime = provider.clockInTime;

      await expectLater(
        provider.clockOut(),
        throwsA(isA<StateError>()),
      );

      expect(provider.isClockedIn, isTrue);
      expect(provider.clockInTime, clockInTime);
    });

    test('uses the site captured at clock in when clocking out', () async {
      WorkEntry? savedEntry;
      final provider = _TestWorkProvider(
        firestoreService: firestoreService,
        onAddEntry: (entry) async {
          savedEntry = entry;
        },
      );
      await provider.updateSession(user);
      provider.updateReferenceData(
        sites: const [],
        contracts: const [],
        siteAssignments: const [
          EmployeeSiteAssignment(
            id: 'assign-1',
            orgId: 'org-1',
            userId: 'employee-1',
            siteId: 'site-1',
            siteName: 'Berlin',
            isPrimary: true,
          ),
        ],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const <TravelTimeRule>[],
      );
      await seedCurrentShift();

      await provider.clockIn();
      provider.updateReferenceData(
        sites: const [],
        contracts: const [],
        siteAssignments: const [
          EmployeeSiteAssignment(
            id: 'assign-2',
            orgId: 'org-1',
            userId: 'employee-1',
            siteId: 'site-2',
            siteName: 'Hamburg',
            isPrimary: true,
          ),
        ],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const <TravelTimeRule>[],
      );

      await provider.clockOut();

      expect(savedEntry, isNotNull);
      expect(savedEntry!.siteId, 'site-1');
      expect(savedEntry!.siteName, 'Berlin');
      expect(provider.isClockedIn, isFalse);
    });

    test('clears active clock state when session ends', () async {
      final provider = _TestWorkProvider(
        firestoreService: firestoreService,
      );
      await provider.updateSession(user);
      provider.updateReferenceData(
        sites: const [],
        contracts: const [],
        siteAssignments: const [
          EmployeeSiteAssignment(
            id: 'assign-1',
            orgId: 'org-1',
            userId: 'employee-1',
            siteId: 'site-1',
            siteName: 'Berlin',
            isPrimary: true,
          ),
        ],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const <TravelTimeRule>[],
      );
      await seedCurrentShift();

      await provider.clockIn();
      await provider.updateSession(null);

      expect(provider.isClockedIn, isFalse);
      expect(provider.clockInTime, isNull);
    });

    test('exposes the current active shift for clock gating', () async {
      final provider = WorkProvider(
        firestoreService: firestoreService,
      );
      await provider.updateSession(user);
      provider.updateReferenceData(
        sites: const [],
        contracts: const [],
        siteAssignments: const [
          EmployeeSiteAssignment(
            id: 'assign-1',
            orgId: 'org-1',
            userId: 'employee-1',
            siteId: 'site-1',
            siteName: 'Berlin',
            isPrimary: true,
          ),
        ],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const <TravelTimeRule>[],
      );
      final now = DateTime.now();
      await seedCurrentShift(
        start: now.subtract(const Duration(hours: 1)),
        end: now.add(const Duration(hours: 2)),
      );

      await provider.refreshCurrentShiftStatus(referenceTime: now);

      expect(provider.activeShiftNow, isNotNull);
      expect(provider.activeShiftNow!.id, 'shift-1');
    });

    test('finds a covering shift for manual entry windows', () async {
      final provider = WorkProvider(
        firestoreService: firestoreService,
      );
      await provider.updateSession(user);
      provider.updateReferenceData(
        sites: const [],
        contracts: const [],
        siteAssignments: const [
          EmployeeSiteAssignment(
            id: 'assign-1',
            orgId: 'org-1',
            userId: 'employee-1',
            siteId: 'site-1',
            siteName: 'Berlin',
            isPrimary: true,
          ),
        ],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const <TravelTimeRule>[],
      );
      final shiftStart = DateTime(2026, 3, 31, 8, 0);
      final shiftEnd = DateTime(2026, 3, 31, 16, 0);
      await seedCurrentShift(
        start: shiftStart,
        end: shiftEnd,
      );

      final coveringShift = await provider.findCoveringShiftForRange(
        start: DateTime(2026, 3, 31, 9, 0),
        end: DateTime(2026, 3, 31, 12, 0),
      );

      expect(coveringShift, isNotNull);
      expect(coveringShift!.id, 'shift-1');
    });

    test('loads only confirmed shifts for the selected day', () async {
      final provider = WorkProvider(
        firestoreService: firestoreService,
      );
      await provider.updateSession(user);
      provider.updateReferenceData(
        sites: const [],
        contracts: const [],
        siteAssignments: const [
          EmployeeSiteAssignment(
            id: 'assign-1',
            orgId: 'org-1',
            userId: 'employee-1',
            siteId: 'site-1',
            siteName: 'Berlin',
            isPrimary: true,
          ),
        ],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const <TravelTimeRule>[],
      );
      await seedCurrentShift(
        id: 'confirmed-shift',
        start: DateTime(2026, 3, 31, 8, 0),
        end: DateTime(2026, 3, 31, 16, 0),
        status: ShiftStatus.confirmed,
      );
      await seedCurrentShift(
        id: 'planned-shift',
        start: DateTime(2026, 3, 31, 17, 0),
        end: DateTime(2026, 3, 31, 20, 0),
        status: ShiftStatus.planned,
      );

      final shifts = await provider.loadConfirmedShiftsForDay(
        DateTime(2026, 3, 31),
      );

      expect(shifts, hasLength(1));
      expect(shifts.first.id, 'confirmed-shift');
    });

    test('blocks clock in outside of planned shifts', () async {
      final provider = WorkProvider(
        firestoreService: firestoreService,
      );
      await provider.updateSession(user);
      provider.updateReferenceData(
        sites: const [],
        contracts: const [],
        siteAssignments: const [
          EmployeeSiteAssignment(
            id: 'assign-1',
            orgId: 'org-1',
            userId: 'employee-1',
            siteId: 'site-1',
            siteName: 'Berlin',
            isPrimary: true,
          ),
        ],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const <TravelTimeRule>[],
      );

      await expectLater(
        provider.clockIn(),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('geplanten Schicht'),
          ),
        ),
      );
    });

    test('blocks manual entries outside of planned shifts', () async {
      final provider = WorkProvider(
        firestoreService: firestoreService,
      );
      await provider.updateSession(user);
      provider.updateReferenceData(
        sites: const [],
        contracts: const [],
        siteAssignments: const [
          EmployeeSiteAssignment(
            id: 'assign-1',
            orgId: 'org-1',
            userId: 'employee-1',
            siteId: 'site-1',
            siteName: 'Berlin',
            isPrimary: true,
          ),
        ],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const <TravelTimeRule>[],
      );

      final now = DateTime.now();
      final entry = WorkEntry(
        orgId: user.orgId,
        userId: user.uid,
        date: now,
        startTime: now.subtract(const Duration(hours: 2)),
        endTime: now.subtract(const Duration(hours: 1)),
        breakMinutes: 0,
        siteId: 'site-1',
        siteName: 'Berlin',
      );

      await expectLater(
        provider.addEntry(entry),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('geplanten Schicht'),
          ),
        ),
      );
    });

    test('stores local entries after caching cloud data locally', () async {
      final provider = WorkProvider(
        firestoreService: firestoreService,
      );
      await provider.updateSession(user);
      provider.updateReferenceData(
        sites: const [],
        contracts: const [],
        siteAssignments: const [
          EmployeeSiteAssignment(
            id: 'assign-1',
            orgId: 'org-1',
            userId: 'employee-1',
            siteId: 'site-1',
            siteName: 'Berlin',
            isPrimary: true,
          ),
        ],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const <TravelTimeRule>[],
      );

      await firestore
          .collection('organizations')
          .doc(user.orgId)
          .collection('workEntries')
          .doc('remote-entry')
          .set(
            WorkEntry(
              id: 'remote-entry',
              orgId: user.orgId,
              userId: user.uid,
              date: DateTime(2026, 3, 31),
              startTime: DateTime(2026, 3, 31, 8, 0),
              endTime: DateTime(2026, 3, 31, 10, 0),
              breakMinutes: 0,
              siteId: 'site-1',
              siteName: 'Berlin',
              sourceShiftId: 'shift-1',
            ).toFirestoreMap(),
          );

      await DatabaseService.saveLocalShifts([
        Shift(
          id: 'shift-1',
          orgId: user.orgId,
          userId: user.uid,
          employeeName: user.displayName,
          title: 'Tagdienst',
          startTime: DateTime(2026, 3, 31, 8, 0),
          endTime: DateTime(2026, 3, 31, 16, 0),
          breakMinutes: 30,
          siteId: 'site-1',
          siteName: 'Berlin',
          location: 'Berlin',
          status: ShiftStatus.confirmed,
        ),
      ], scope: LocalStorageScope.fromUser(user));
      await provider.cacheCloudStateLocally();
      await provider.updateSession(user, localStorageOnly: true);
      await provider.selectMonth(DateTime(2026, 3, 1));
      provider.updateReferenceData(
        sites: const [],
        contracts: const [],
        siteAssignments: const [
          EmployeeSiteAssignment(
            id: 'assign-1',
            orgId: 'org-1',
            userId: 'employee-1',
            siteId: 'site-1',
            siteName: 'Berlin',
            isPrimary: true,
          ),
        ],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const <TravelTimeRule>[],
      );

      await provider.addEntry(
        WorkEntry(
          orgId: user.orgId,
          userId: user.uid,
          date: DateTime(2026, 3, 31),
          startTime: DateTime(2026, 3, 31, 10, 0),
          endTime: DateTime(2026, 3, 31, 12, 0),
          breakMinutes: 0,
          siteId: 'site-1',
          siteName: 'Berlin',
          sourceShiftId: 'shift-1',
        ),
      );

      expect(provider.entries, hasLength(2));
    });

    test('blocks clock in when an overlapping work entry already exists',
        () async {
      final provider = WorkProvider(
        firestoreService: firestoreService,
      );
      await provider.updateSession(user);
      provider.updateReferenceData(
        sites: const [],
        contracts: const [],
        siteAssignments: const [
          EmployeeSiteAssignment(
            id: 'assign-1',
            orgId: 'org-1',
            userId: 'employee-1',
            siteId: 'site-1',
            siteName: 'Berlin',
            isPrimary: true,
          ),
        ],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const <TravelTimeRule>[],
      );
      await seedCurrentShift();

      final now = DateTime.now();
      final existingEntry = WorkEntry(
        id: 'entry-1',
        orgId: user.orgId,
        userId: user.uid,
        date: now,
        startTime: now.subtract(const Duration(minutes: 20)),
        endTime: now.add(const Duration(minutes: 20)),
        breakMinutes: 0,
        siteId: 'site-1',
        siteName: 'Berlin',
        sourceShiftId: 'shift-1',
      );
      await firestore
          .collection('organizations')
          .doc(user.orgId)
          .collection('workEntries')
          .doc(existingEntry.id)
          .set(existingEntry.toFirestoreMap());

      await expectLater(
        provider.clockIn(),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('bereits ein Zeiteintrag'),
          ),
        ),
      );
    });

    test('prompts for overtime when manual entry extends beyond a shift',
        () async {
      final provider = WorkProvider(
        firestoreService: firestoreService,
      );
      await provider.updateSession(user);
      provider.updateReferenceData(
        sites: const [],
        contracts: const [],
        siteAssignments: const [
          EmployeeSiteAssignment(
            id: 'assign-1',
            orgId: 'org-1',
            userId: 'employee-1',
            siteId: 'site-1',
            siteName: 'Berlin',
            isPrimary: true,
          ),
        ],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const <TravelTimeRule>[],
      );
      await seedCurrentShift(
        start: DateTime(2026, 3, 31, 8, 0),
        end: DateTime(2026, 3, 31, 16, 0),
      );

      final entry = WorkEntry(
        orgId: user.orgId,
        userId: user.uid,
        date: DateTime(2026, 3, 31),
        startTime: DateTime(2026, 3, 31, 12, 0),
        endTime: DateTime(2026, 3, 31, 18, 0),
        breakMinutes: 30,
        siteId: 'site-1',
        siteName: 'Berlin',
        sourceShiftId: 'shift-1',
      );

      await expectLater(
        provider.saveEntryWithOvertimeHandling(entry),
        throwsA(
          isA<OvertimeApprovalRequired>().having(
            (error) => error.hasAfterShiftOvertime,
            'hasAfterShiftOvertime',
            isTrue,
          ),
        ),
      );
    });

    test('splits manual entries into shift time and overtime when approved',
        () async {
      final savedEntries = <WorkEntry>[];
      final provider = _TestWorkProvider(
        firestoreService: firestoreService,
        onAddEntries: (entries) async {
          savedEntries.addAll(entries);
        },
      );
      await provider.updateSession(user);
      provider.updateReferenceData(
        sites: const [],
        contracts: const [],
        siteAssignments: const [
          EmployeeSiteAssignment(
            id: 'assign-1',
            orgId: 'org-1',
            userId: 'employee-1',
            siteId: 'site-1',
            siteName: 'Berlin',
            isPrimary: true,
          ),
        ],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const <TravelTimeRule>[],
      );
      await seedCurrentShift(
        start: DateTime(2026, 3, 31, 8, 0),
        end: DateTime(2026, 3, 31, 16, 0),
      );

      final entry = WorkEntry(
        orgId: user.orgId,
        userId: user.uid,
        date: DateTime(2026, 3, 31),
        startTime: DateTime(2026, 3, 31, 12, 0),
        endTime: DateTime(2026, 3, 31, 18, 0),
        breakMinutes: 30,
        siteId: 'site-1',
        siteName: 'Berlin',
        sourceShiftId: 'shift-1',
        note: 'Projekt A',
      );

      await provider.saveEntryWithOvertimeHandling(
        entry,
        allowOvertime: true,
      );

      expect(savedEntries, hasLength(2));
      expect(savedEntries.first.startTime, DateTime(2026, 3, 31, 12, 0));
      expect(savedEntries.first.endTime, DateTime(2026, 3, 31, 16, 0));
      expect(savedEntries.first.category, isNull);
      expect(savedEntries.last.startTime, DateTime(2026, 3, 31, 16, 0));
      expect(savedEntries.last.endTime, DateTime(2026, 3, 31, 18, 0));
      expect(savedEntries.last.category, 'overtime');
      expect(savedEntries.last.note, contains('Ueberstunden'));
    });

    test('stores split overtime entries locally when overtime is approved',
        () async {
      final provider = WorkProvider(
        firestoreService: firestoreService,
      );
      await DatabaseService.saveLocalShifts([
        Shift(
          id: 'shift-1',
          orgId: user.orgId,
          userId: user.uid,
          employeeName: user.displayName,
          title: 'Tagdienst',
          startTime: DateTime(2026, 3, 31, 8, 0),
          endTime: DateTime(2026, 3, 31, 16, 0),
          breakMinutes: 30,
          siteId: 'site-1',
          siteName: 'Berlin',
          location: 'Berlin',
          status: ShiftStatus.confirmed,
        ),
      ], scope: LocalStorageScope.fromUser(user));
      await provider.updateSession(user, localStorageOnly: true);
      await provider.selectMonth(DateTime(2026, 3, 1));
      provider.updateReferenceData(
        sites: const [],
        contracts: const [],
        siteAssignments: const [
          EmployeeSiteAssignment(
            id: 'assign-1',
            orgId: 'org-1',
            userId: 'employee-1',
            siteId: 'site-1',
            siteName: 'Berlin',
            isPrimary: true,
          ),
        ],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const <TravelTimeRule>[],
      );

      await provider.saveEntryWithOvertimeHandling(
        WorkEntry(
          orgId: user.orgId,
          userId: user.uid,
          date: DateTime(2026, 3, 31),
          startTime: DateTime(2026, 3, 31, 12, 0),
          endTime: DateTime(2026, 3, 31, 18, 0),
          breakMinutes: 30,
          siteId: 'site-1',
          siteName: 'Berlin',
          sourceShiftId: 'shift-1',
        ),
        allowOvertime: true,
      );

      expect(provider.entries, hasLength(2));
      expect(
        provider.entries.map((entry) => entry.category),
        contains('overtime'),
      );
    });

    test(
        'splits an active manual entry into shift time and overtime on clock out',
        () async {
      final savedEntries = <WorkEntry>[];
      final provider = _TestWorkProvider(
        firestoreService: firestoreService,
        onAddEntries: (entries) async {
          savedEntries.addAll(entries);
        },
      );
      await provider.updateSession(user);
      provider.updateReferenceData(
        sites: const [],
        contracts: const [],
        siteAssignments: const [
          EmployeeSiteAssignment(
            id: 'assign-1',
            orgId: 'org-1',
            userId: 'employee-1',
            siteId: 'site-1',
            siteName: 'Berlin',
            isPrimary: true,
          ),
        ],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const <TravelTimeRule>[],
      );

      final now = DateTime.now();
      final shiftEnd = now.subtract(const Duration(minutes: 5));
      await seedCurrentShift(
        id: 'shift-1',
        start: now.subtract(const Duration(hours: 2)),
        end: shiftEnd,
      );

      final activeEntry = WorkEntry(
        id: 'entry-active',
        orgId: user.orgId,
        userId: user.uid,
        date: now,
        startTime: now.subtract(const Duration(hours: 1)),
        endTime: now.add(const Duration(minutes: 30)),
        breakMinutes: 30,
        siteId: 'site-1',
        siteName: 'Berlin',
        sourceShiftId: 'shift-1',
        note: 'Projekt A',
      );
      await firestore
          .collection('organizations')
          .doc(user.orgId)
          .collection('workEntries')
          .doc(activeEntry.id)
          .set(activeEntry.toFirestoreMap());
      await provider.refreshCurrentShiftStatus(referenceTime: now);

      expect(provider.activeEntryNow, isNotNull);

      await provider.clockOut(allowOvertime: true);

      expect(savedEntries, hasLength(2));
      expect(savedEntries.first.id, 'entry-active');
      expect(savedEntries.first.endTime, shiftEnd);
      expect(savedEntries.last.category, 'overtime');
      expect(savedEntries.last.startTime, shiftEnd);
      expect(savedEntries.last.endTime.isAfter(shiftEnd), isTrue);
    });
  });
}
