import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/payroll_record.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/models/zeitkonto_snapshot.dart';
import 'package:worktime_app/providers/zeitwirtschaft_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// M5: Monatsabschluss-Orchestrierung im ZeitwirtschaftProvider (close/reopen +
/// Entwurfs-Lohn-Seam), lokaler Modus.
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

  const admin = AppUserProfile(
    uid: 'admin-1',
    orgId: 'org-1',
    email: 'admin@example.com',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Chef'),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  Future<ZeitwirtschaftProvider> localProvider(
      {AppUserProfile user = employee}) async {
    final provider = ZeitwirtschaftProvider(
      firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
    );
    await provider.updateSession(user, localStorageOnly: true);
    return provider;
  }

  ZeitkontoSnapshot live({int ist = 9600, int soll = 9600}) => ZeitkontoSnapshot(
        orgId: 'org-1',
        userId: 'emp-1',
        jahr: 2026,
        monat: 6,
        sollMinutes: soll,
        istMinutes: ist,
        ueberstundenMinutes: ist - soll,
        saldoMinutes: ist - soll,
      );

  WorkEntry entry(WorkEntryStatus status) => WorkEntry(
        id: 'e-${status.name}',
        orgId: 'org-1',
        userId: 'emp-1',
        date: DateTime(2026, 6, 10),
        startTime: DateTime(2026, 6, 10, 8),
        endTime: DateTime(2026, 6, 10, 16),
        status: status,
      );

  // Fester „Jetzt": Juni/2026 ist damit vollständig vergangen (abschließbar).
  final now = DateTime(2026, 7, 1);

  test('closeMonth blockiert bei offenen Einträgen und schreibt nichts',
      () async {
    final provider = await localProvider();
    final validation = await provider.closeMonth(
      liveSnapshot: live(),
      monthEntries: [entry(WorkEntryStatus.submitted)],
      vormonat: null,
      now: now,
    );
    expect(validation.canClose, isFalse);
    final stored = await provider.loadOrgSnapshotsForMonth(2026, 6);
    expect(stored, isEmpty);
  });

  test('closeMonth blockiert bei offenen Klärungsfällen (ZV-5.2)', () async {
    final provider = await localProvider();
    final validation = await provider.closeMonth(
      liveSnapshot: live(),
      monthEntries: [entry(WorkEntryStatus.approved)], // Einträge sauber
      vormonat: null,
      now: now,
      offeneKlaerungen: 2,
    );
    expect(validation.canClose, isFalse);
    expect(
      validation.errors.any((e) => e.contains('Klärungsfälle')),
      isTrue,
    );
    final stored = await provider.loadOrgSnapshotsForMonth(2026, 6);
    expect(stored, isEmpty);
  });

  test('closeMonth blockiert den laufenden/zukünftigen Monat', () async {
    final provider = await localProvider();
    final validation = await provider.closeMonth(
      liveSnapshot: live(),
      monthEntries: const [],
      vormonat: null,
      now: DateTime(2026, 6, 15), // Juni läuft noch
    );
    expect(validation.canClose, isFalse);
    expect(
      validation.errors.any((e) => e.contains('noch nicht vollständig vorbei')),
      isTrue,
    );
  });

  test('closeMonth sperrt den Snapshot und postet den Entwurfs-Lohn (Admin)',
      () async {
    final provider = await localProvider(user: admin);
    PayrollRecord? posted;
    provider.setPayrollDraftPoster((record) async => posted = record);

    const draft = PayrollRecord(
      orgId: '',
      userId: 'emp-1',
      periodYear: 2026,
      periodMonth: 6,
      grossCents: 200000,
    );
    final validation = await provider.closeMonth(
      liveSnapshot: live(),
      monthEntries: [entry(WorkEntryStatus.approved)],
      vormonat: null,
      draftPayroll: draft,
      actorUid: 'admin-1',
      now: now,
    );

    expect(validation.canClose, isTrue);
    expect(posted, isNotNull);
    expect(posted!.grossCents, 200000);

    final stored = await provider.loadOrgSnapshotsForMonth(2026, 6);
    expect(stored, hasLength(1));
    expect(stored.first.abgeschlossen, isTrue);
    expect(stored.first.abgeschlossenVon, 'admin-1');
  });

  test('closeMonth postet KEINEN Entwurfs-Lohn für Nicht-Admins', () async {
    final provider = await localProvider(); // employee (kein Admin)
    var posterCalled = false;
    provider.setPayrollDraftPoster((record) async => posterCalled = true);

    const draft = PayrollRecord(
      orgId: '',
      userId: 'emp-1',
      periodYear: 2026,
      periodMonth: 6,
      grossCents: 200000,
    );
    final validation = await provider.closeMonth(
      liveSnapshot: live(),
      monthEntries: [entry(WorkEntryStatus.approved)],
      vormonat: null,
      draftPayroll: draft,
      now: now,
    );

    // Snapshot wird gesperrt (canManageShifts), aber kein Lohn-Entwurf erzeugt.
    expect(validation.canClose, isTrue);
    expect(posterCalled, isFalse);
    final stored = await provider.loadOrgSnapshotsForMonth(2026, 6);
    expect(stored.first.abgeschlossen, isTrue);
  });

  test('reopenMonth hebt die Sperre wieder auf', () async {
    final provider = await localProvider();
    await provider.closeMonth(
      liveSnapshot: live(),
      monthEntries: [entry(WorkEntryStatus.approved)],
      vormonat: null,
      now: now,
    );
    final locked = (await provider.loadOrgSnapshotsForMonth(2026, 6)).first;
    expect(locked.abgeschlossen, isTrue);

    await provider.reopenMonth(locked);
    final reopened = (await provider.loadOrgSnapshotsForMonth(2026, 6)).first;
    expect(reopened.abgeschlossen, isFalse);
    expect(reopened.abgeschlossenVon, isNull);
  });

  test('loadCarryover holt den Dezember-Vormonat über die Jahresgrenze',
      () async {
    final provider = await localProvider();
    await provider.saveSnapshot(ZeitkontoSnapshot(
      orgId: 'org-1',
      userId: 'emp-1',
      jahr: 2025,
      monat: 12,
      saldoMinutes: 600,
    ));
    await provider.loadSnapshots(2026); // _snapshotYear = 2026
    await provider.loadCarryover(DateTime(2026, 1));
    expect(provider.carryover, isNotNull);
    expect(provider.carryover!.jahr, 2025);
    expect(provider.carryover!.monat, 12);
    expect(provider.carryover!.saldoMinutes, 600);
  });

  test('loadCarryover im selben Jahr nutzt den Jahres-Cache', () async {
    final provider = await localProvider();
    await provider.saveSnapshot(ZeitkontoSnapshot(
      orgId: 'org-1',
      userId: 'emp-1',
      jahr: 2026,
      monat: 5,
      saldoMinutes: 300,
    ));
    await provider.loadSnapshots(2026);
    await provider.loadCarryover(DateTime(2026, 6));
    expect(provider.carryover?.monat, 5);
    expect(provider.carryover?.saldoMinutes, 300);
  });

  test('loadOrgWorkEntriesForMonth filtert den Monat (lokaler Cache)', () async {
    final provider = await localProvider();
    await DatabaseService.saveLocalEntries(
      [
        entry(WorkEntryStatus.approved),
        WorkEntry(
          id: 'e-other-month',
          orgId: 'org-1',
          userId: 'emp-2',
          date: DateTime(2026, 5, 3),
          startTime: DateTime(2026, 5, 3, 8),
          endTime: DateTime(2026, 5, 3, 12),
          status: WorkEntryStatus.approved,
        ),
      ],
      scope: LocalStorageScope.fromUser(employee),
    );
    final juni = await provider.loadOrgWorkEntriesForMonth(DateTime(2026, 6));
    expect(juni, hasLength(1));
    expect(juni.first.userId, 'emp-1');
  });
}
