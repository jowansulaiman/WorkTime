import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/clock_entry.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/models/sollzeit_profile.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/models/zeitkonto_snapshot.dart';
import 'package:worktime_app/providers/zeitwirtschaft_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// M3b-1: ZeitwirtschaftProvider clockIn/clockOut (persistente ClockEntry).
class _CapturingFirestoreService extends FirestoreService {
  _CapturingFirestoreService({required super.firestore});

  ClockEntry? saved;

  @override
  Future<void> saveClockEntry(ClockEntry entry) async {
    saved = entry;
  }

  // PA-4.1: clockIn läuft im Cloud-Modus über die {userId}-open-Transaktion.
  @override
  Future<void> clockInOpen(ClockEntry entry) async {
    saved = entry;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const employee = AppUserProfile(
    uid: 'emp-1',
    orgId: 'org-1',
    email: 'emp@example.com',
    role: UserRole.employee,
    isActive: true,
    settings: UserSettings(name: 'Peter'),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  Future<List<ClockEntry>> storedFor(AppUserProfile user) =>
      DatabaseService.loadLocalClockEntries(
        scope: LocalStorageScope.fromUser(user),
      );

  group('lokaler Modus', () {
    Future<ZeitwirtschaftProvider> localProvider() async {
      final provider = ZeitwirtschaftProvider(
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      );
      await provider.updateSession(employee, localStorageOnly: true);
      return provider;
    }

    test('clockIn legt eine laufende Buchung an', () async {
      final provider = await localProvider();
      await provider.clockIn(
        siteId: 'site-1',
        siteName: 'Strichmännchen',
        at: DateTime(2026, 6, 10, 8),
      );

      expect(provider.isClockedIn, isTrue);
      expect(provider.openEntry!.status, ClockStatus.ongoing);
      expect(provider.openEntry!.siteName, 'Strichmännchen');

      final stored = await storedFor(employee);
      expect(stored.where((e) => e.isOngoing), hasLength(1));
    });

    test('zweites clockIn ist No-Op (genau eine offene Buchung)', () async {
      final provider = await localProvider();
      await provider.clockIn(at: DateTime(2026, 6, 10, 8));
      await provider.clockIn(at: DateTime(2026, 6, 10, 9));

      final stored = await storedFor(employee);
      expect(stored.where((e) => e.isOngoing), hasLength(1));
    });

    test('clockOut schließt ab, Auto-Pause 30 min → Netto 450', () async {
      final provider = await localProvider();
      await provider.clockIn(at: DateTime(2026, 6, 10, 8));
      await provider.clockOut(at: DateTime(2026, 6, 10, 16)); // 8 h brutto

      expect(provider.isClockedIn, isFalse);

      final done =
          (await storedFor(employee)).firstWhere((e) => !e.isOngoing);
      expect(done.status, ClockStatus.completed);
      expect(done.gehen, isNotNull);
      expect(done.pauseMinuten, 30);
      expect(done.nettoMinutes, 450);
    });

    test('clockOut mit expliziter Pause + Anmerkung', () async {
      final provider = await localProvider();
      await provider.clockIn(at: DateTime(2026, 6, 10, 8));
      await provider.clockOut(
        at: DateTime(2026, 6, 10, 16),
        pauseMinuten: 60,
        anmerkung: 'Inventur',
      );

      final done =
          (await storedFor(employee)).firstWhere((e) => !e.isOngoing);
      expect(done.pauseMinuten, 60);
      expect(done.nettoMinutes, 420);
      expect(done.anmerkung, 'Inventur');
    });

    test('monthEntries enthält die abgeschlossene Buchung (nach selectMonth)',
        () async {
      final provider = await localProvider();
      await provider.clockIn(at: DateTime(2026, 6, 10, 8));
      await provider.clockOut(at: DateTime(2026, 6, 10, 16));
      await provider.selectMonth(DateTime(2026, 6, 1));

      expect(provider.monthEntries, hasLength(1));
      expect(provider.monthEntries.single.status, ClockStatus.completed);

      // Anderer Monat → leer.
      await provider.selectMonth(DateTime(2026, 7, 1));
      expect(provider.monthEntries, isEmpty);
    });

    test('clockOut am Folgetag → Status klaerung', () async {
      final provider = await localProvider();
      await provider.clockIn(at: DateTime(2026, 6, 9, 22));
      await provider.clockOut(at: DateTime(2026, 6, 10, 6));

      final done = (await storedFor(employee)).single;
      expect(done.status, ClockStatus.klaerung);
      expect(done.klaerung, isTrue);
    });
  });

  group('WorkEntry-Erzeugung (Poster-Seam, M3c)', () {
    Future<ZeitwirtschaftProvider> localProvider() async {
      final provider = ZeitwirtschaftProvider(
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      );
      await provider.updateSession(employee, localStorageOnly: true);
      return provider;
    }

    test('clockOut erzeugt WorkEntry(submitted) mit sourceClockEntryId',
        () async {
      WorkEntry? posted;
      final provider = await localProvider();
      provider.setWorkEntryPoster((e) async => posted = e);

      await provider.clockIn(
          siteId: 'site-1', siteName: 'Strichmännchen', at: DateTime(2026, 6, 10, 8));
      await provider.clockOut(at: DateTime(2026, 6, 10, 16));

      expect(posted, isNotNull);
      expect(posted!.status, WorkEntryStatus.submitted);
      expect(posted!.sourceClockEntryId, isNotNull);
      expect(posted!.breakMinutes, 30);
      expect(posted!.siteId, 'site-1');
    });

    test('Klärungsfall (Vortag) erzeugt KEINEN WorkEntry', () async {
      WorkEntry? posted;
      final provider = await localProvider();
      provider.setWorkEntryPoster((e) async => posted = e);

      await provider.clockIn(at: DateTime(2026, 6, 9, 22));
      await provider.clockOut(at: DateTime(2026, 6, 10, 6));

      expect(posted, isNull);
    });

    test('Poster-Fehler bricht das Ausstempeln nicht ab', () async {
      final provider = await localProvider();
      provider.setWorkEntryPoster((e) async => throw StateError('compliance'));

      await provider.clockIn(at: DateTime(2026, 6, 10, 8));
      await provider.clockOut(at: DateTime(2026, 6, 10, 16));

      expect(provider.isClockedIn, isFalse);
      final done = (await DatabaseService.loadLocalClockEntries(
        scope: LocalStorageScope.fromUser(employee),
      ))
          .single;
      expect(done.status, ClockStatus.completed);
    });
  });

  group('Klärung & Korrektur (ZV-3)', () {
    const manager = AppUserProfile(
      uid: 'mgr-1',
      orgId: 'org-1',
      email: 'mgr@example.com',
      role: UserRole.admin,
      isActive: true,
      settings: UserSettings(name: 'Chef'),
    );

    Future<ZeitwirtschaftProvider> mgrProvider() async {
      final provider = ZeitwirtschaftProvider(
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      );
      await provider.updateSession(manager, localStorageOnly: true);
      return provider;
    }

    test('clockIn schreibt shiftId + source app', () async {
      final provider = await mgrProvider();
      await provider.clockIn(
        siteId: 'site-1',
        siteName: 'Strichmännchen',
        shiftId: 'shift-42',
        at: DateTime(2026, 6, 10, 8),
      );
      final open = provider.openEntry!;
      expect(open.shiftId, 'shift-42');
      expect(open.source, 'app');
    });

    test('Schicht-Kette: clockIn(shiftId) → clockOut → WorkEntry.sourceShiftId',
        () async {
      WorkEntry? posted;
      final provider = await mgrProvider();
      provider.setWorkEntryPoster((e) async => posted = e);

      await provider.clockIn(
        siteId: 'site-1',
        siteName: 'Strichmännchen',
        shiftId: 'shift-42',
        at: DateTime(2026, 6, 10, 8),
      );
      await provider.clockOut(at: DateTime(2026, 6, 10, 16));

      expect(posted, isNotNull);
      expect(posted!.sourceShiftId, 'shift-42');
      expect(posted!.status, WorkEntryStatus.submitted);
      expect(posted!.category, 'stempel');
    });

    test('resolveKlaerung schließt ab + erzeugt genau einen WorkEntry', () async {
      WorkEntry? posted;
      final provider = await mgrProvider();
      provider.setWorkEntryPoster((e) async => posted = e);

      // Klärungsfall erzeugen (Vortag-Buchung).
      await provider.clockIn(at: DateTime(2026, 6, 9, 22));
      await provider.clockOut(at: DateTime(2026, 6, 10, 6));
      expect(posted, isNull); // Klärung erzeugt zunächst keinen WorkEntry

      final open = (await storedFor(manager))
          .firstWhere((e) => e.status == ClockStatus.klaerung);
      await provider.resolveKlaerung(
        open,
        kommen: DateTime(2026, 6, 9, 22),
        gehen: DateTime(2026, 6, 10, 2),
        grund: 'Ausstempeln vergessen',
      );

      expect(posted, isNotNull);
      expect(posted!.status, WorkEntryStatus.submitted);
      final resolved = (await storedFor(manager))
          .firstWhere((e) => e.id == open.id);
      expect(resolved.status, ClockStatus.completed);
      expect(resolved.korrigiertVonUid, 'mgr-1');
      expect(resolved.korrekturGrund, 'Ausstempeln vergessen');
      expect(resolved.manuellErfasst, isTrue);
    });

    test('dismissKlaerung setzt deaktiviert, kein WorkEntry', () async {
      WorkEntry? posted;
      final provider = await mgrProvider();
      provider.setWorkEntryPoster((e) async => posted = e);

      await provider.clockIn(at: DateTime(2026, 6, 9, 22));
      await provider.clockOut(at: DateTime(2026, 6, 10, 6));
      final open = (await storedFor(manager))
          .firstWhere((e) => e.status == ClockStatus.klaerung);

      await provider.dismissKlaerung(open, grund: 'Doppelbuchung');
      final dismissed =
          (await storedFor(manager)).firstWhere((e) => e.id == open.id);
      expect(dismissed.status, ClockStatus.deaktiviert);
      expect(posted, isNull);
    });

    test('addManualClockEntry erzeugt fertige Buchung + WorkEntry', () async {
      WorkEntry? posted;
      final provider = await mgrProvider();
      provider.setWorkEntryPoster((e) async => posted = e);

      await provider.addManualClockEntry(
        userId: 'emp-1',
        userName: 'Peter',
        kommen: DateTime(2026, 6, 10, 8),
        gehen: DateTime(2026, 6, 10, 16),
        siteId: 'site-1',
        siteName: 'Strichmännchen',
        grund: 'Handy vergessen',
      );

      expect(posted, isNotNull);
      expect(posted!.userId, 'emp-1');
      expect(posted!.sourceShiftId, isNull);
      final stored = (await storedFor(manager))
          .firstWhere((e) => e.userId == 'emp-1');
      expect(stored.status, ClockStatus.completed);
      expect(stored.manuellErfasst, isTrue);
      expect(stored.korrekturGrund, 'Handy vergessen');
    });

    test('Mitarbeiter ohne Manager-Recht darf nicht korrigieren', () async {
      final provider = ZeitwirtschaftProvider(
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      );
      await provider.updateSession(employee, localStorageOnly: true);
      await provider.clockIn(at: DateTime(2026, 6, 9, 22));
      await provider.clockOut(at: DateTime(2026, 6, 10, 6));
      final open = (await storedFor(employee))
          .firstWhere((e) => e.status == ClockStatus.klaerung);

      await provider.dismissKlaerung(open, grund: 'x');
      final after =
          (await storedFor(employee)).firstWhere((e) => e.id == open.id);
      // employee (kein canManageShifts) → No-Op, bleibt Klärung.
      expect(after.status, ClockStatus.klaerung);
    });
  });

  group('Stundenkonto-Snapshots (M4b)', () {
    test('saveSnapshot + loadSnapshots round-trip (lokal)', () async {
      final provider = ZeitwirtschaftProvider(
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      );
      await provider.updateSession(employee, localStorageOnly: true);

      await provider.saveSnapshot(ZeitkontoSnapshot(
        orgId: 'org-1',
        userId: 'emp-1',
        jahr: 2026,
        monat: 6,
        sollMinutes: 9000,
        istMinutes: 9120,
        ueberstundenMinutes: 120,
        saldoMinutes: 720,
      ));
      await provider.loadSnapshots(2026);

      expect(provider.yearSnapshots, hasLength(1));
      expect(provider.snapshotFor(2026, 6)!.saldoMinutes, 720);
      expect(provider.snapshotFor(2026, 5), isNull);
    });
  });

  group('Cloud-Modus (mitgeschnitten)', () {
    test('clockIn schreibt eine ongoing-ClockEntry', () async {
      final capture =
          _CapturingFirestoreService(firestore: FakeFirebaseFirestore());
      final provider = ZeitwirtschaftProvider(firestoreService: capture);
      await provider.updateSession(employee); // cloud-only

      await provider.clockIn(siteId: 'site-1', at: DateTime(2026, 6, 10, 8));

      expect(capture.saved, isNotNull);
      expect(capture.saved!.status, ClockStatus.ongoing);
      expect(capture.saved!.userId, 'emp-1');
      expect(capture.saved!.siteId, 'site-1');
    });
  });

  group('loadOrgZeitKpis (REPORTING-2)', () {
    const manager = AppUserProfile(
      uid: 'mgr-1',
      orgId: 'org-1',
      email: 'mgr@example.com',
      role: UserRole.admin,
      isActive: true,
      settings: UserSettings(name: 'Chef'),
    );

    SollzeitProfile profile(String userId) => SollzeitProfile(
          orgId: 'org-1',
          userId: userId,
          gueltigAb: DateTime(2025, 1, 1),
          montagMinutes: 480,
          dienstagMinutes: 480,
          mittwochMinutes: 480,
          donnerstagMinutes: 480,
          freitagMinutes: 480,
          isMonatsarbeitszeit: true,
          monatsarbeitszeitMinutes: 9000,
        );

    Future<ZeitwirtschaftProvider> providerFor(AppUserProfile user) async {
      final provider = ZeitwirtschaftProvider(
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      );
      await provider.updateSession(user, localStorageOnly: true);
      return provider;
    }

    test('Gate: Mitarbeiter ohne canManageShifts erhält null', () async {
      final provider = await providerFor(employee);
      final kpis = await provider.loadOrgZeitKpis(
        jahr: 2026,
        monat: 6,
        memberIds: const ['emp-1'],
        profilesByUser: const {},
      );
      expect(kpis, isNull);
    });

    test('Manager: komponiert Org-Zeit-Kennzahlen aus lokalen Daten', () async {
      final provider = await providerFor(manager);
      await DatabaseService.saveLocalEntries(
        [
          WorkEntry(
            orgId: 'org-1',
            userId: 'a',
            date: DateTime(2026, 6, 2),
            startTime: DateTime(2026, 6, 2, 8),
            endTime: DateTime(2026, 6, 2, 16), // 480 approved
          ),
          WorkEntry(
            orgId: 'org-1',
            userId: 'a',
            date: DateTime(2026, 6, 3),
            startTime: DateTime(2026, 6, 3, 8),
            endTime: DateTime(2026, 6, 3, 12),
            status: WorkEntryStatus.submitted,
          ),
        ],
        scope: LocalStorageScope.fromUser(manager),
      );

      final kpis = await provider.loadOrgZeitKpis(
        jahr: 2026,
        monat: 6,
        memberIds: const ['a'],
        profilesByUser: {
          'a': [profile('a')],
        },
      );
      expect(kpis, isNotNull);
      expect(kpis!.sollMinutes, 9000);
      expect(kpis.istMinutes, 480); // nur approved
      expect(kpis.offeneFreigaben, 1); // submitted
      expect(kpis.mitarbeiterMitSoll, 1);
    });
  });
}
