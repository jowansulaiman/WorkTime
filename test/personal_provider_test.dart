import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/absence_request.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/employee_profile.dart';
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

      await expectLater(
        provider.saveEmployeeProfile(
          const EmployeeProfile(orgId: 'org-1', userId: 'emp-1', city: 'Kiel'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('EmployeeProfile: Upsert je userId + Persistenz + Löschen', () async {
      final provider =
          PersonalProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);

      await provider.saveEmployeeProfile(
        const EmployeeProfile(
          orgId: 'org-1',
          userId: 'emp-1',
          city: 'Kiel',
          iban: 'DE02120300000000202051',
          confession: Confession.katholisch,
          status: EmployeeStatus.probezeit,
        ),
      );
      expect(provider.employeeProfiles.length, 1);
      expect(provider.employeeProfileForUser('emp-1')!.iban,
          'DE02120300000000202051');

      // Erneutes Speichern überschreibt (deterministische Doc-ID = userId).
      await provider.saveEmployeeProfile(
        const EmployeeProfile(orgId: 'org-1', userId: 'emp-1', city: 'Hamburg'),
      );
      expect(provider.employeeProfiles.length, 1);
      expect(provider.employeeProfileForUser('emp-1')!.city, 'Hamburg');

      // Persistenz über Neustart.
      final reopened =
          PersonalProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(reopened.dispose);
      await reopened.updateSession(_admin, localStorageOnly: true);
      expect(reopened.employeeProfileForUser('emp-1')!.city, 'Hamburg');

      // Löschen.
      await reopened.deleteEmployeeProfile('emp-1');
      expect(reopened.employeeProfiles, isEmpty);
    });

    test('setPayrollStatus stempelt Freigeber/Zeit und leert beim Zurücksetzen',
        () async {
      final provider =
          PersonalProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);

      await provider.savePayrollRecord(
        const PayrollRecord(
          orgId: 'org-1',
          userId: 'emp-1',
          periodYear: 2026,
          periodMonth: 6,
          grossCents: 300000,
        ),
      );
      final record = provider.payrollForUserPeriod('emp-1', 2026, 6)!;
      expect(record.status, PayrollStatus.entwurf);

      await provider.setPayrollStatus(record, PayrollStatus.freigegeben);
      final freigegeben = provider.payrollForUserPeriod('emp-1', 2026, 6)!;
      expect(freigegeben.status, PayrollStatus.freigegeben);
      expect(freigegeben.finalizedByUid, 'admin-1');
      expect(freigegeben.finalizedAt, isNotNull);
      // Kein zusätzlicher Datensatz (Upsert auf dieselbe Doc-ID).
      expect(provider.payrollRecords.length, 1);

      await provider.setPayrollStatus(freigegeben, PayrollStatus.entwurf);
      final zurueck = provider.payrollForUserPeriod('emp-1', 2026, 6)!;
      expect(zurueck.status, PayrollStatus.entwurf);
      expect(zurueck.finalizedByUid, isNull);
      expect(zurueck.finalizedAt, isNull);
    });

    test('finalizeAllDrafts gibt nur Entwürfe des Monats frei (Lohnlauf)',
        () async {
      final provider =
          PersonalProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);

      for (final uid in ['emp-1', 'emp-2', 'emp-3']) {
        await provider.savePayrollRecord(
          PayrollRecord(
            orgId: 'org-1',
            userId: uid,
            periodYear: 2026,
            periodMonth: 6,
            grossCents: 300000,
          ),
        );
      }
      // emp-3 ist bereits bezahlt -> bleibt unberührt.
      await provider.setPayrollStatus(
        provider.payrollForUserPeriod('emp-3', 2026, 6)!,
        PayrollStatus.bezahlt,
      );
      // Eine Abrechnung in einem anderen Monat -> nicht betroffen.
      await provider.savePayrollRecord(
        const PayrollRecord(
          orgId: 'org-1',
          userId: 'emp-1',
          periodYear: 2026,
          periodMonth: 5,
          grossCents: 300000,
        ),
      );

      await provider.finalizeAllDrafts(2026, 6);

      final juni = provider.payrollForPeriod(2026, 6);
      expect(
        juni.where((r) => r.userId == 'emp-1').single.status,
        PayrollStatus.freigegeben,
      );
      expect(
        juni.where((r) => r.userId == 'emp-2').single.status,
        PayrollStatus.freigegeben,
      );
      expect(
        juni.where((r) => r.userId == 'emp-3').single.status,
        PayrollStatus.bezahlt, // unverändert
      );
      // Mai-Entwurf bleibt Entwurf.
      expect(
        provider.payrollForUserPeriod('emp-1', 2026, 5)!.status,
        PayrollStatus.entwurf,
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

    test('streamt Personal-Stammakten aus Firestore', () async {
      await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('employeeProfiles')
          .doc('emp-1')
          .set(const EmployeeProfile(
            id: 'emp-1',
            orgId: 'org-1',
            userId: 'emp-1',
            city: 'Kiel',
            personnelNumber: 'P-1',
          ).toFirestoreMap());

      final provider = PersonalProvider(firestoreService: service);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final profile = provider.employeeProfileForUser('emp-1');
      expect(profile, isNotNull);
      expect(profile!.city, 'Kiel');
      expect(profile.personnelNumber, 'P-1');
    });
  });
}
