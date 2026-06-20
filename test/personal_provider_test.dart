import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/absence_request.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/payroll_record.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/models/work_task.dart';
import 'package:worktime_app/providers/personal_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

const _admin = AppUserProfile(
  uid: 'admin-1',
  orgId: 'org-1',
  email: 'admin@example.com',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Sandra'),
);

const _employee = AppUserProfile(
  uid: 'emp-1',
  orgId: 'org-1',
  email: 'peter@example.com',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Peter'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late FirestoreService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    firestore = FakeFirebaseFirestore();
    service = FirestoreService(firestore: firestore);
  });

  group('PersonalProvider (local)', () {
    test('saveWorkTask + savePayrollRecord persist across instances', () async {
      final provider =
          PersonalProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);

      await provider.saveWorkTask(
        const WorkTask(orgId: 'org-1', assignedUserId: 'emp-1', title: 'Lager'),
      );
      await provider.savePayrollRecord(
        const PayrollRecord(
          orgId: 'org-1',
          userId: 'emp-1',
          periodYear: 2026,
          periodMonth: 6,
          grossCents: 300000,
          netCents: 200000,
        ),
      );

      expect(provider.tasks.length, 1);
      expect(provider.tasks.first.title, 'Lager');
      expect(provider.payrollRecords.length, 1);
      expect(provider.latestPayrollForUser('emp-1')!.grossCents, 300000);

      // Neue Instanz lädt dieselben lokalen Daten.
      final reopened =
          PersonalProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(reopened.dispose);
      await reopened.updateSession(_admin, localStorageOnly: true);
      expect(reopened.tasks.length, 1);
      expect(reopened.payrollRecords.length, 1);
    });

    test('Lohn-Upsert pro Monat überschreibt (deterministische ID)', () async {
      final provider =
          PersonalProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);

      for (final gross in [250000, 280000]) {
        await provider.savePayrollRecord(
          PayrollRecord(
            orgId: 'org-1',
            userId: 'emp-1',
            periodYear: 2026,
            periodMonth: 6,
            grossCents: gross,
          ),
        );
      }
      expect(provider.payrollRecords.length, 1);
      expect(provider.payrollForUserPeriod('emp-1', 2026, 6)!.grossCents, 280000);
    });

    test('rememberPayrollProfile speichert Stammdaten und ist write-frugal',
        () async {
      final provider =
          PersonalProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);

      await provider.rememberPayrollProfile(
        userId: 'emp-1',
        taxClass: TaxClass.iii,
        kind: PayrollEmploymentKind.minijob,
        churchTax: true,
        federalState: 'Bayern',
        monthlyGrossCents: 55600,
      );
      expect(provider.payrollProfiles.length, 1);
      final saved = provider.profileForUser('emp-1')!;
      expect(saved.taxClass, TaxClass.iii);
      expect(saved.federalState, 'Bayern');
      expect(saved.monthlyGrossCents, 55600);

      // Unveränderte Stammdaten -> kein neuer Eintrag, keine Duplikate.
      await provider.rememberPayrollProfile(
        userId: 'emp-1',
        taxClass: TaxClass.iii,
        kind: PayrollEmploymentKind.minijob,
        churchTax: true,
        federalState: 'Bayern',
        monthlyGrossCents: 55600,
      );
      expect(provider.payrollProfiles.length, 1);

      // Geänderte Stammdaten -> Upsert auf denselben userId-Datensatz.
      await provider.rememberPayrollProfile(
        userId: 'emp-1',
        taxClass: TaxClass.i,
        kind: PayrollEmploymentKind.standard,
        churchTax: false,
      );
      expect(provider.payrollProfiles.length, 1);
      expect(provider.profileForUser('emp-1')!.taxClass, TaxClass.i);

      // Persistenz über Neustart.
      final reopened =
          PersonalProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(reopened.dispose);
      await reopened.updateSession(_admin, localStorageOnly: true);
      expect(reopened.profileForUser('emp-1')!.taxClass, TaxClass.i);
    });

    test('Nicht-Admin darf nicht schreiben', () async {
      final provider =
          PersonalProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_employee, localStorageOnly: true);

      await expectLater(
        provider.saveWorkTask(
          const WorkTask(orgId: 'org-1', assignedUserId: 'emp-1', title: 'x'),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('PersonalProvider (cloud)', () {
    test('streamt Aufgaben und aggregiert Abwesenheiten', () async {
      await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('workTasks')
          .doc('t1')
          .set(const WorkTask(
            id: 't1',
            orgId: 'org-1',
            assignedUserId: 'emp-1',
            title: 'Inventur',
          ).toFirestoreMap());

      await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('absenceRequests')
          .doc('a1')
          .set(AbsenceRequest(
            orgId: 'org-1',
            userId: 'emp-1',
            employeeName: 'Peter',
            startDate: DateTime(2026, 6, 1),
            endDate: DateTime(2026, 6, 3),
            type: AbsenceType.sickness,
            status: AbsenceStatus.approved,
          ).toFirestoreMap());

      final provider = PersonalProvider(firestoreService: service);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.tasks.map((t) => t.id), contains('t1'));
      final stats = provider.absenceStatsForUser('emp-1', year: 2026);
      expect(stats.sicknessCount, 1);
      expect(stats.sicknessDays, 3);
      expect(stats.vacationDays, 0);
    });
  });
}
