import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/compliance_rule_set.dart';
import 'package:worktime_app/models/employee_site_assignment.dart';
import 'package:worktime_app/models/employment_contract.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/travel_time_rule.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/models/work_template.dart';
import 'package:worktime_app/providers/work_provider.dart';
import 'package:worktime_app/services/compliance_rejected_exception.dart';
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

/// Liefert fuer den Vorlagen-Stream einen Fehler, um das Sichtbarmachen
/// von Stream-Fehlern zu testen (work-template-report-stream-silent).
class _ErroringTemplatesFirestoreService extends FirestoreService {
  _ErroringTemplatesFirestoreService({required super.firestore});

  @override
  Stream<List<WorkTemplate>> watchWorkTemplates({
    required String orgId,
    required String userId,
  }) =>
      Stream<List<WorkTemplate>>.error(StateError('permission-denied'));
}

/// Wirft beim Loeschen, um den hybrid-Fallback (CLAUDE.md-Mutator-Muster)
/// zu testen (hybrid-delete-rethrows).
class _DeleteFailingFirestoreService extends FirestoreService {
  _DeleteFailingFirestoreService({required super.firestore});

  @override
  Future<void> deleteWorkEntry({
    required String orgId,
    required String entryId,
  }) async =>
      throw Exception('offline');
}

/// Wirft beim Speichern von Zeiteintraegen (Callable UND Direkt-Write
/// gescheitert), um den hybriden Pending-Sync-Schutz (#22) zu testen.
class _SaveEntryFailingFirestoreService extends FirestoreService {
  _SaveEntryFailingFirestoreService({required super.firestore});

  @override
  Future<void> saveWorkEntry(WorkEntry entry) async =>
      throw Exception('offline');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkProvider Stream-Fehler', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
    });

    test(
        'macht einen Vorlagen-Stream-Fehler sichtbar statt ihn zu schlucken',
        () async {
      final firestore = FakeFirebaseFirestore();
      const admin = AppUserProfile(
        uid: 'admin-1',
        orgId: 'org-1',
        email: 'admin@example.com',
        role: UserRole.admin,
        isActive: true,
        settings: UserSettings(name: 'Admin'),
      );
      final provider = WorkProvider(
        firestoreService:
            _ErroringTemplatesFirestoreService(firestore: firestore),
      );
      addTearDown(provider.dispose);

      await provider.updateSession(admin);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.errorMessage, isNotNull,
          reason: 'ein dauerhafter Stream-Fehler darf nicht still verschwinden');
      expect(provider.errorMessage, contains('Vorlagen'));
    });
  });

  group('WorkProvider hybrid-Delete-Fallback', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
    });

    const admin = AppUserProfile(
      uid: 'admin-1',
      orgId: 'org-1',
      email: 'admin@example.com',
      role: UserRole.admin,
      isActive: true,
      settings: UserSettings(name: 'Admin'),
    );

    test(
        'deleteEntry faellt im hybrid-Modus lokal zurueck (kein rethrow) und '
        'setzt einen Tombstone', () async {
      final provider = WorkProvider(
        firestoreService:
            _DeleteFailingFirestoreService(firestore: FakeFirebaseFirestore()),
      );
      addTearDown(provider.dispose);
      await provider.updateSession(admin, hybridStorageEnabled: true);
      await Future<void>.delayed(Duration.zero);

      await provider.deleteEntry('entry-x'); // darf NICHT werfen

      final tombstones = await DatabaseService.loadTombstones(
        DatabaseService.workEntriesCollection,
        scope: LocalStorageScope.fromUser(admin),
      );
      expect(tombstones, contains('entry-x'));
    });

    test('deleteEntry wirft im cloud-only-Modus weiter', () async {
      final provider = WorkProvider(
        firestoreService:
            _DeleteFailingFirestoreService(firestore: FakeFirebaseFirestore()),
      );
      addTearDown(provider.dispose);
      await provider.updateSession(admin); // cloud-only (hybrid=false)
      await Future<void>.delayed(Duration.zero);

      expect(() => provider.deleteEntry('entry-x'), throwsException);
    });

    test(
        'pendingDeletionCount zaehlt eine lokal vorgemerkte Loeschung '
        '(Sync-Status-UX)', () async {
      final provider = WorkProvider(
        firestoreService:
            _DeleteFailingFirestoreService(firestore: FakeFirebaseFirestore()),
      );
      addTearDown(provider.dispose);
      await provider.updateSession(admin, hybridStorageEnabled: true);
      await Future<void>.delayed(Duration.zero);

      expect(provider.pendingDeletionCount, 0);

      await provider.deleteEntry('entry-x'); // Cloud-Delete schlaegt fehl

      expect(provider.pendingDeletionCount, 1,
          reason: 'eine un-propagierte Loeschung muss als ausstehend gelten');
    });
  });

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

    test(
        'keeps local entries when switching from local-only to hybrid with empty cloud',
        () async {
      final provider = WorkProvider(
        firestoreService: firestoreService,
      );
      final now = DateTime.now();
      await DatabaseService.saveLocalEntries(
        [
          WorkEntry(
            id: 'local-entry',
            orgId: user.orgId,
            userId: user.uid,
            date: now,
            startTime: now.subtract(const Duration(hours: 2)),
            endTime: now.subtract(const Duration(hours: 1)),
            breakMinutes: 0,
            siteId: 'site-1',
            siteName: 'Berlin',
          ),
        ],
        scope: LocalStorageScope.fromUser(user),
      );

      await provider.updateSession(user, localStorageOnly: true);
      await provider.selectMonth(DateTime(now.year, now.month));

      expect(provider.entries, hasLength(1));
      expect(provider.entries.single.id, 'local-entry');

      await provider.updateSession(user, hybridStorageEnabled: true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.entries, hasLength(1));
      expect(provider.entries.single.id, 'local-entry');
      expect(provider.entries.single.siteName, 'Berlin');
    });

    test('stores hybrid entries locally when cloud transfer fails', () async {
      final failingService = FirestoreService(
        firestore: firestore,
        cloudFunctionInvoker: (_, __) async {
          throw FirebaseFunctionsException(
            code: 'internal',
            message: 'save failed',
          );
        },
      );
      final provider = WorkProvider(
        firestoreService: failingService,
      );
      await provider.updateSession(user, hybridStorageEnabled: true);
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
      await provider.addEntry(
        WorkEntry(
          orgId: user.orgId,
          userId: user.uid,
          date: now,
          startTime: now.subtract(const Duration(minutes: 30)),
          endTime: now.subtract(const Duration(minutes: 5)),
          breakMinutes: 0,
          siteId: 'site-1',
          siteName: 'Berlin',
          sourceShiftId: 'shift-1',
        ),
      );

      expect(provider.entries, hasLength(1));
      expect(provider.entries.single.siteName, 'Berlin');

      final persistedEntries = await DatabaseService.loadLocalEntries(
        scope: LocalStorageScope.fromUser(user),
      );
      expect(persistedEntries, hasLength(1));
      expect(persistedEntries.single.siteName, 'Berlin');
    });

    test(
        'hybrid: Cloud-Snapshot mit neuerem updatedAt ueberschreibt einen '
        'nicht synchronisierten lokalen Eintrag nicht (#22 Clock-Skew)', () async {
      final provider = WorkProvider(
        firestoreService: _SaveEntryFailingFirestoreService(
          firestore: firestore,
        ),
      );
      addTearDown(provider.dispose);
      await provider.updateSession(user, hybridStorageEnabled: true);
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
      final localEntry = WorkEntry(
        id: 'entry-skew',
        orgId: user.orgId,
        userId: user.uid,
        date: now,
        startTime: now.subtract(const Duration(minutes: 30)),
        endTime: now.subtract(const Duration(minutes: 5)),
        breakMinutes: 0,
        siteId: 'site-1',
        siteName: 'Berlin',
        note: 'lokal',
        sourceShiftId: 'shift-1',
      );
      // Cloud-Write schlaegt fehl -> lokaler Hybrid-Fallback (pending).
      await provider.addEntry(localEntry);
      expect(provider.entries.single.note, 'lokal');

      // Veralteten Cloud-Stand derselben ID einspielen, dessen serverseitiges
      // updatedAt (Server-Uhr) NEUER ist als der lokale Client-Stempel —
      // exakt das Clock-Skew-Szenario, das lokale Edits verlieren liess.
      final staleCloudMap = localEntry
          .copyWith(note: 'veralteter Cloud-Stand')
          .toFirestoreMap()
        ..['updatedAt'] =
            Timestamp.fromDate(DateTime.now().add(const Duration(hours: 1)));
      await firestore
          .collection('organizations')
          .doc(user.orgId)
          .collection('workEntries')
          .doc('entry-skew')
          .set(staleCloudMap);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.entries.single.note, 'lokal',
          reason: 'pending lokale Version darf nicht vom Cloud-Snapshot '
              'ueberschrieben werden (Clock-Skew)');
      final persisted = await DatabaseService.loadLocalEntries(
        scope: LocalStorageScope.fromUser(user),
      );
      expect(persisted.single.note, 'lokal');
    });

    test(
        'cloud-Pfad vergibt vor dem Callable-Aufruf eine stabile UUID-Doc-ID '
        '(no-idempotency-key)', () async {
      // Regression: id darf nie null an die Callable gehen, sonst hasht der
      // Server inhaltsbasiert und ein Retry mit geaendertem Feld dupliziert.
      Map<String, dynamic>? capturedPayload;
      final capturingService = FirestoreService(
        firestore: firestore,
        cloudFunctionInvoker: (name, payload) async {
          capturedPayload = payload;
          return {'issues': <dynamic>[]};
        },
      );
      final provider = WorkProvider(firestoreService: capturingService);
      await provider.updateSession(user); // cloud-Modus (weder local noch hybrid)
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
      await provider.addEntry(
        WorkEntry(
          orgId: user.orgId,
          userId: user.uid,
          date: now,
          startTime: now.subtract(const Duration(minutes: 30)),
          endTime: now.subtract(const Duration(minutes: 5)),
          breakMinutes: 0,
          siteId: 'site-1',
          siteName: 'Berlin',
          sourceShiftId: 'shift-1',
        ),
      );

      final entryMap = capturedPayload?['entry'] as Map<String, dynamic>?;
      expect(entryMap, isNotNull,
          reason: 'Callable upsertWorkEntry sollte aufgerufen worden sein');
      final id = entryMap!['id'] as String?;
      expect(id, isNotNull,
          reason: 'id darf nie null an die Callable gehen (Idempotenz)');
      expect(id, startsWith('entry-'));
      expect(RegExp(r'^entry-[0-9a-f-]{36}$').hasMatch(id!), isTrue,
          reason: 'id muss eine UUID v4 sein, kein reiner Timestamp');
    });

    test(
        'lokaler Pfad vergibt UUID-IDs statt reiner Timestamp-IDs '
        '(timestamp-ids-not-uuid)', () async {
      final provider = WorkProvider(firestoreService: firestoreService);
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

      final id = provider.entries.single.id;
      expect(id, isNotNull);
      expect(RegExp(r'^entry-[0-9a-f-]{36}$').hasMatch(id!), isTrue,
          reason: 'Lokale IDs muessen UUID-basiert sein (kein Timestamp)');
    });

    test(
        'does NOT persist locally when the server rejects with a blocking '
        'compliance violation (failed-precondition) in hybrid mode', () async {
      // Regression: Eine bewusste serverseitige Compliance-Ablehnung darf im
      // Hybrid-Modus NICHT lokal überschrieben werden (Plan-Gap
      // hybrid-catch-swallows-blocking-stateerror). Die strukturierten
      // Verstöße müssen erhalten bleiben (blocking-violations-discarded-client).
      final rejectingService = FirestoreService(
        firestore: firestore,
        cloudFunctionInvoker: (_, __) async {
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'Tagesarbeitszeit überschritten',
            details: const {
              'validations': [
                {
                  'violations': [
                    {
                      'code': 'max_daily_minutes',
                      'severity': 'blocking',
                      'message': 'Tagesarbeitszeit überschritten',
                    },
                  ],
                },
              ],
            },
          );
        },
      );
      final provider = WorkProvider(firestoreService: rejectingService);
      await provider.updateSession(user, hybridStorageEnabled: true);
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
      await expectLater(
        provider.addEntry(
          WorkEntry(
            orgId: user.orgId,
            userId: user.uid,
            date: now,
            startTime: now.subtract(const Duration(minutes: 30)),
            endTime: now.subtract(const Duration(minutes: 5)),
            breakMinutes: 0,
            siteId: 'site-1',
            siteName: 'Berlin',
            sourceShiftId: 'shift-1',
          ),
        ),
        throwsA(
          isA<ComplianceRejectedException>().having(
            (error) => error.violations.map((violation) => violation.code),
            'violations',
            contains('max_daily_minutes'),
          ),
        ),
      );

      // Kein lokaler Fallback: weder im Speicher noch persistiert.
      expect(provider.entries, isEmpty);
      final persistedEntries = await DatabaseService.loadLocalEntries(
        scope: LocalStorageScope.fromUser(user),
      );
      expect(persistedEntries, isEmpty);
    });

    test(
        'tombstone: ein lokal geloeschter Eintrag taucht nach Wechsel in den '
        'Cloud-Modus nicht wieder auf', () async {
      final now = DateTime.now();
      final entry = WorkEntry(
        id: 'entry-tomb',
        orgId: user.orgId,
        userId: user.uid,
        date: now,
        startTime: now.subtract(const Duration(hours: 3)),
        endTime: now.subtract(const Duration(hours: 1)),
        breakMinutes: 0,
        siteId: 'site-1',
        siteName: 'Berlin',
      );
      // Eintrag existiert in Firestore (Cloud-Wahrheit).
      await firestore
          .collection('organizations')
          .doc(user.orgId)
          .collection('workEntries')
          .doc(entry.id)
          .set(entry.toFirestoreMap());

      final provider = WorkProvider(firestoreService: firestoreService);

      // Im local-Modus loeschen -> Tombstone, Firestore-Doc bleibt bestehen.
      await provider.updateSession(user, localStorageOnly: true);
      await provider.deleteEntry('entry-tomb');

      // Wechsel in den Cloud-Modus: der Live-Stream liefert den Doc weiterhin.
      await provider.updateSession(user);
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        provider.entries.any((item) => item.id == 'entry-tomb'),
        isFalse,
        reason: 'Tombstone muss das Wiederauferstehen verhindern',
      );
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

  group('WorkProvider Lohn-Schätzung (H-B1: Vertrag statt UserSettings)', () {
    late FirestoreService firestoreService;
    late AppUserProfile user;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
      firestoreService = FirestoreService(firestore: FakeFirebaseFirestore());
      user = const AppUserProfile(
        uid: 'employee-1',
        orgId: 'org-1',
        email: 'anna@example.com',
        role: UserRole.employee,
        isActive: true,
        // Settings-Stundensatz 10 € (alte Quelle) — soll vom Vertrag (20 €)
        // überschrieben werden.
        settings: UserSettings(name: 'Anna', hourlyRate: 10, dailyHours: 6),
      );
    });

    Future<WorkProvider> seedProvider({
      required List<EmploymentContract> contracts,
    }) async {
      final provider = WorkProvider(firestoreService: firestoreService);
      addTearDown(provider.dispose);
      // Im local-Modus lädt _loadLocalState die Settings aus dem Speicher und
      // überschreibt die In-Memory-Settings — daher hier persistieren.
      await DatabaseService.saveLocalUserSettings(
        user.settings,
        scope: LocalStorageScope.fromUser(user),
      );
      await DatabaseService.saveLocalEntries(
        [
          WorkEntry(
            id: 'e1',
            orgId: user.orgId,
            userId: user.uid,
            date: DateTime(2026, 3, 10),
            startTime: DateTime(2026, 3, 10, 8, 0),
            endTime: DateTime(2026, 3, 10, 17, 0),
            breakMinutes: 0, // 9 h gearbeitet
            siteId: 'site-1',
            siteName: 'Berlin',
          ),
        ],
        scope: LocalStorageScope.fromUser(user),
      );
      await provider.updateSession(user, localStorageOnly: true);
      await provider.selectMonth(DateTime(2026, 3, 1));
      provider.updateReferenceData(
        sites: const [],
        contracts: contracts,
        siteAssignments: const <EmployeeSiteAssignment>[],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const <TravelTimeRule>[],
      );
      return provider;
    }

    test('nutzt den am Eintragsdatum gültigen Vertrag (hourlyRate/dailyHours)',
        () async {
      final provider = await seedProvider(contracts: [
        EmploymentContract(
          id: 'c1',
          orgId: 'org-1',
          userId: 'employee-1',
          validFrom: DateTime(2026, 1, 1),
          hourlyRate: 20,
          dailyHours: 8,
        ),
      ]);

      expect(provider.entries, hasLength(1));
      // 9 h × 20 € (Vertrag) = 180 €, NICHT 9 × 10 € (Settings).
      expect(provider.totalWageThisMonth, 180);
      // Überstunden gegen Vertrags-Tagessoll 8 h → 1 h (nicht 3 h gegen 6 h).
      expect(provider.overtimeThisMonth, 1);
    });

    test('fällt ohne aktiven Vertrag auf UserSettings zurück (nie still 0)',
        () async {
      final provider = await seedProvider(contracts: const []);

      // Diagnose: Eintrag geladen? Settings korrekt?
      expect(provider.entries, hasLength(1));
      expect(provider.totalHoursThisMonth, 9);
      expect(provider.settings.hourlyRate, 10);
      // Kein Vertrag → Settings: 9 h × 10 € = 90 €; Überstunden gegen 6 h = 3 h.
      expect(provider.totalWageThisMonth, 90);
      expect(provider.overtimeThisMonth, 3);
    });
  });
}
