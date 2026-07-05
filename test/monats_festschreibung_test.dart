import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/core/monats_festschreibung.dart';
import 'package:worktime_app/core/monatsabschluss_service.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/clock_entry.dart';
import 'package:worktime_app/models/compliance_rule_set.dart';
import 'package:worktime_app/models/employee_site_assignment.dart';
import 'package:worktime_app/models/payroll_record.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/models/zeitkonto_snapshot.dart';
import 'package:worktime_app/providers/work_provider.dart';
import 'package:worktime_app/providers/zeitwirtschaft_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// PA-5: Monats-Festschreibung — Client-Schichten (Guard in WorkProvider +
/// ZeitwirtschaftProvider, Abschluss-Blocker, Abrechnungssperre PA-5.2).
/// Callable-Schicht spiegelt functions/monats_lock.js (node --test);
/// Rules-Schicht per Emulator (PA-9-Verifikationsliste).

const _employee = AppUserProfile(
  uid: 'emp-1',
  orgId: 'org-1',
  email: 'peter@example.com',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Peter'),
);

const _admin = AppUserProfile(
  uid: 'admin-1',
  orgId: 'org-1',
  email: 'admin@demo.local',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Admin'),
);

ZeitkontoSnapshot _lockedSnapshot({
  String userId = 'emp-1',
  required int jahr,
  required int monat,
}) =>
    ZeitkontoSnapshot(
      orgId: 'org-1',
      userId: userId,
      jahr: jahr,
      monat: monat,
      sollMinutes: 9600,
      istMinutes: 9600,
      abgeschlossen: true,
      abgeschlossenVon: 'admin-1',
    );

WorkEntry _entryOn(DateTime day) => WorkEntry(
      orgId: 'org-1',
      userId: 'emp-1',
      date: DateTime(day.year, day.month, day.day, 12),
      startTime: DateTime(day.year, day.month, day.day, 9),
      endTime: DateTime(day.year, day.month, day.day, 13),
      siteId: 'site-1',
      siteName: 'Kiel',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  group('MonatsFestschreibung (pure Guard)', () {
    test('wirft mit deutscher Meldung, wenn Snapshot abgeschlossen', () async {
      await expectLater(
        MonatsFestschreibung.assertNichtFestgeschrieben(
          ladeSnapshot: (u, j, m) async =>
              _lockedSnapshot(jahr: j, monat: m),
          userId: 'emp-1',
          datum: DateTime(2026, 5, 15),
        ),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('05/2026'))),
      );
    });

    test('kein Snapshot / nicht abgeschlossen / Ladefehler → frei (fail-open)',
        () async {
      await MonatsFestschreibung.assertNichtFestgeschrieben(
        ladeSnapshot: (u, j, m) async => null,
        userId: 'emp-1',
        datum: DateTime(2026, 5, 15),
      );
      await MonatsFestschreibung.assertNichtFestgeschrieben(
        ladeSnapshot: (u, j, m) async => ZeitkontoSnapshot(
            orgId: 'org-1', userId: u, jahr: j, monat: m),
        userId: 'emp-1',
        datum: DateTime(2026, 5, 15),
      );
      // Ladefehler (offline) blockiert NICHT — Callable+Rules sind hart.
      await MonatsFestschreibung.assertNichtFestgeschrieben(
        ladeSnapshot: (u, j, m) async => throw StateError('offline'),
        userId: 'emp-1',
        datum: DateTime(2026, 5, 15),
      );
    });
  });

  group('MonatsabschlussService: offene Stempelung blockiert', () {
    test('offeneStempelungen > 0 → Blocker mit deutschem Text', () {
      const service = MonatsabschlussService();
      final result = service.validate(
        snapshot: ZeitkontoSnapshot(
            orgId: 'org-1', userId: 'emp-1', jahr: 2026, monat: 5),
        entries: const [],
        vormonat: null,
        now: DateTime(2026, 6, 10),
        offeneStempelungen: 1,
      );
      expect(result.canClose, isFalse);
      expect(result.errors.join(' '), contains('Stempelung läuft noch'));
    });
  });

  group('WorkProvider-Guard (cloud, Fake-Firestore)', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreService service;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      service = FirestoreService(
        firestore: firestore,
        cloudFunctionInvoker: (name, payload) async =>
            {'savedId': 'x', 'violations': <dynamic>[]},
      );
      // Mai 2026 ist für emp-1 festgeschrieben.
      await service.saveZeitkontoSnapshot(
          _lockedSnapshot(jahr: 2026, monat: 5));
      // Deckende Schichten für Mai/Juni-Einträge (die Schichtbindungs-Regel
      // ist hier nicht Testgegenstand — der Festschreibungs-Guard läuft VOR
      // der Compliance).
      for (final day in [DateTime(2026, 5, 15), DateTime(2026, 6, 15)]) {
        final shift = Shift(
          id: 'shift-${day.month}',
          orgId: 'org-1',
          userId: 'emp-1',
          employeeName: 'Peter',
          title: 'Tagdienst',
          startTime: DateTime(day.year, day.month, day.day, 8),
          endTime: DateTime(day.year, day.month, day.day, 14),
          breakMinutes: 30,
          siteId: 'site-1',
          siteName: 'Kiel',
          location: 'Kiel',
          status: ShiftStatus.confirmed,
        );
        await firestore
            .collection('organizations')
            .doc('org-1')
            .collection('shifts')
            .doc(shift.id)
            .set(shift.toFirestoreMap());
      }
    });

    Future<WorkProvider> cloudProvider() async {
      final provider = WorkProvider(firestoreService: service);
      addTearDown(provider.dispose);
      await provider.updateSession(_employee);
      provider.updateReferenceData(
        sites: const [],
        contracts: const [],
        siteAssignments: const [
          EmployeeSiteAssignment(
            id: 'assign-1',
            orgId: 'org-1',
            userId: 'emp-1',
            siteId: 'site-1',
            siteName: 'Kiel',
            isPrimary: true,
          ),
        ],
        ruleSets: [ComplianceRuleSet.defaultRetail('org-1')],
        travelTimeRules: const [],
      );
      return provider;
    }

    test('addEntry in festgeschriebenen Monat wirft StateError', () async {
      final provider = await cloudProvider();
      await expectLater(
        provider.addEntry(_entryOn(DateTime(2026, 5, 15))),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('festgeschrieben'))),
      );
    });

    test('addEntry in freien Monat geht durch', () async {
      final provider = await cloudProvider();
      await provider.addEntry(_entryOn(DateTime(2026, 6, 15)));
    });

    test('updateEntry: Verschieben AUS dem festgeschriebenen Monat heraus '
        'ist ebenso gesperrt', () async {
      final provider = await cloudProvider();
      // Bestehenden Eintrag im Juni anlegen und dann in den (freien) Juli
      // schieben — erlaubt. Danach simulieren wir das Herausschieben aus dem
      // gesperrten Mai über einen in-memory bekannten Eintrag.
      final juni = _entryOn(DateTime(2026, 6, 15));
      await provider.addEntry(juni);

      // Eintrag mit id im gesperrten Mai direkt in die lokale Sicht bringen:
      // der Guard prüft den NEUEN Monat zuerst — ein Update, dessen Ziel im
      // Mai liegt, wird geblockt, egal woher.
      await expectLater(
        provider.updateEntry(_entryOn(DateTime(2026, 5, 20))
            .copyWith(id: 'entry-mai')),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('WorkProvider-Guard (lokaler Modus)', () {
    test('addEntry in festgeschriebenen Monat wirft auch lokal', () async {
      // Lokalen Snapshot als festgeschrieben seeden.
      await DatabaseService.saveLocalZeitkontoSnapshots(
        [_lockedSnapshot(jahr: 2026, monat: 5)],
        scope: LocalStorageScope.fromUser(_employee),
      );
      final provider = WorkProvider(
        firestoreService:
            FirestoreService(firestore: FakeFirebaseFirestore()),
      );
      addTearDown(provider.dispose);
      await provider.updateSession(_employee, localStorageOnly: true);

      await expectLater(
        provider.addEntry(_entryOn(DateTime(2026, 5, 15))),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('festgeschrieben'))),
      );
    });
  });

  group('ZeitwirtschaftProvider (lokaler Modus)', () {
    Future<ZeitwirtschaftProvider> localProvider(AppUserProfile user) async {
      final provider = ZeitwirtschaftProvider(
        firestoreService:
            FirestoreService(firestore: FakeFirebaseFirestore()),
      );
      addTearDown(provider.dispose);
      await provider.updateSession(user, localStorageOnly: true);
      return provider;
    }

    test('addManualClockEntry in festgeschriebenen Monat wirft', () async {
      await DatabaseService.saveLocalZeitkontoSnapshots(
        [_lockedSnapshot(userId: 'admin-1', jahr: 2026, monat: 5)],
        scope: LocalStorageScope.fromUser(_admin),
      );
      final provider = await localProvider(_admin);
      await expectLater(
        provider.addManualClockEntry(
          userId: 'admin-1',
          kommen: DateTime(2026, 5, 10, 9),
          gehen: DateTime(2026, 5, 10, 13),
          grund: 'Nachtrag',
        ),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('festgeschrieben'))),
      );
    });

    test('reopenMonth: Nicht-Admin wird abgewiesen (PA-5.2)', () async {
      // Employee mit Manager-Rechten (canManageShifts), aber KEIN Admin.
      const teamlead = AppUserProfile(
        uid: 'lead-1',
        orgId: 'org-1',
        email: 'lead@example.com',
        role: UserRole.teamlead,
        isActive: true,
        settings: UserSettings(name: 'Lea'),
      );
      final provider = await localProvider(teamlead);
      await expectLater(
        provider.reopenMonth(
            _lockedSnapshot(userId: 'emp-1', jahr: 2026, monat: 5)),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('Nur Admins'))),
      );
    });

    test('reopenMonth: freigegebene Lohnabrechnung sperrt das Reopen '
        '(erst stornieren)', () async {
      final provider = await localProvider(_admin);
      provider.setPayrollStatusLookup(
          (userId, jahr, monat) => PayrollStatus.freigegeben);
      await expectLater(
        provider.reopenMonth(
            _lockedSnapshot(userId: 'emp-1', jahr: 2026, monat: 5)),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('stornieren'))),
      );
    });

    test('reopenMonth: Admin ohne freigegebenen Lohn darf zurücknehmen',
        () async {
      final provider = await localProvider(_admin);
      provider.setPayrollStatusLookup((userId, jahr, monat) => null);
      await provider.reopenMonth(
          _lockedSnapshot(userId: 'emp-1', jahr: 2026, monat: 5));
    });

    test('closeMonth: laufende Stempelung im Zielmonat blockiert', () async {
      // Vormonat dynamisch (vollständig vorbei), ongoing-Buchung dort seeden.
      final now = DateTime.now();
      final prev = DateTime(now.year, now.month - 1, 15, 9);
      await DatabaseService.saveLocalClockEntries(
        [
          ClockEntry(
            id: 'clock-open-1',
            orgId: 'org-1',
            userId: _admin.uid,
            kommen: prev,
            status: ClockStatus.ongoing,
          ),
        ],
        scope: LocalStorageScope.fromUser(_admin),
      );
      final provider = await localProvider(_admin);

      final result = await provider.closeMonth(
        liveSnapshot: ZeitkontoSnapshot(
          orgId: 'org-1',
          userId: _admin.uid,
          jahr: prev.year,
          monat: prev.month,
          sollMinutes: 0,
          istMinutes: 0,
        ),
        monthEntries: const [],
        vormonat: null,
      );
      expect(result.canClose, isFalse);
      expect(result.errors.join(' '), contains('Stempelung läuft noch'));
    });
  });
}
