import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/absence_request.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/audit_log_entry.dart';
import 'package:worktime_app/models/employee_ausbildung.dart';
import 'package:worktime_app/models/employee_child.dart';
import 'package:worktime_app/models/employee_profile.dart';
import 'package:worktime_app/models/employee_qualification.dart';
import 'package:worktime_app/models/employee_site_assignment.dart';
import 'package:worktime_app/models/employment_contract.dart';
import 'package:worktime_app/models/finance_models.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/core/urlaub_calculator.dart';
import 'package:worktime_app/models/org_payroll_settings.dart';
import 'package:worktime_app/models/pay_line_type.dart';
import 'package:worktime_app/models/payroll_record.dart';
import 'package:worktime_app/models/payroll_settings.dart';
import 'package:worktime_app/models/sollzeit_profile.dart';
import 'package:worktime_app/models/urlaubsanpassung.dart';
import 'package:worktime_app/models/urlaubskonto_jahr.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/models/work_task.dart';
import 'package:worktime_app/providers/finance_provider.dart';
import 'package:worktime_app/providers/personal_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// Lässt jeden Cloud-Write der Lohn-Konfiguration scheitern (Hybrid-Fallback).
class _FailingPayrollConfigService extends FirestoreService {
  _FailingPayrollConfigService({required super.firestore});

  @override
  Future<void> saveOrgPayrollSettings(OrgPayrollSettings config) async =>
      throw StateError('offline');

  @override
  Future<void> savePayLineType(PayLineType type) async =>
      throw StateError('offline');

  @override
  Future<void> deleteOrgPayrollSettings({
    required String orgId,
    required int jahr,
  }) async =>
      throw StateError('offline');
}

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

    test('SollzeitProfile: Auto-ID, mehrere je MA, Vorrang, Persistenz, Löschen',
        () async {
      final provider =
          PersonalProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);

      await provider.saveSollzeitProfile(
        SollzeitProfile(
          orgId: 'org-1',
          userId: 'emp-1',
          gueltigAb: DateTime(2025, 1, 1),
          urlaubstageJahr: 28,
        ),
      );
      await provider.saveSollzeitProfile(
        SollzeitProfile(
          orgId: 'org-1',
          userId: 'emp-1',
          gueltigAb: DateTime(2026, 1, 1),
          urlaubstageJahr: 30,
        ),
      );

      // Mehrere Profile je MA (Auto-ID, kein Überschreiben).
      expect(provider.sollzeitProfiles.length, 2);
      // Absteigend nach gueltigAb sortiert (neuestes zuerst).
      final list = provider.sollzeitProfilesForUser('emp-1');
      expect(list.first.gueltigAb.year, 2026);
      // Das zum Stichtag gültige Modell.
      expect(provider.activeSollzeitFor('emp-1', DateTime(2025, 6, 1))!
          .urlaubstageJahr, 28);
      expect(provider.activeSollzeitFor('emp-1', DateTime(2026, 6, 1))!
          .urlaubstageJahr, 30);
      expect(provider.activeSollzeitFor('emp-1', DateTime(2024, 1, 1)), isNull);

      // Persistenz über Neustart.
      final reopened =
          PersonalProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(reopened.dispose);
      await reopened.updateSession(_admin, localStorageOnly: true);
      expect(reopened.sollzeitProfilesForUser('emp-1').length, 2);

      // Löschen eines Profils per ID.
      final toDelete = reopened.sollzeitProfilesForUser('emp-1').first.id!;
      await reopened.deleteSollzeitProfile(toDelete);
      expect(reopened.sollzeitProfiles.length, 1);
    });

    test('OrgPayrollSettings: Override greift, Fallback auf Defaults, Reset',
        () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);

      // Ohne Override: effektive Sätze = gesetzliche Defaults.
      expect(provider.orgPayrollSettingsForYear(2026), isNull);
      expect(provider.effectivePayrollSettings(2026).umlageU1Rate,
          OrgPayrollSettings.defaultSettingsForYear(2026).umlageU1Rate);

      // Override anlegen (deterministische Doc-ID = Jahr).
      await provider.saveOrgPayrollSettings(
        OrgPayrollSettings(
          orgId: 'org-1',
          jahr: 2026,
          settings: PayrollSettings.defaults2026().copyWith(
            umlageU1Rate: 0.02,
            uvRate: 0.02,
            u1Applies: false,
          ),
        ),
      );
      expect(provider.orgPayrollSettings.length, 1);
      expect(provider.orgPayrollSettingsForYear(2026)!.id, '2026');
      expect(provider.effectivePayrollSettings(2026).umlageU1Rate, 0.02);
      expect(provider.effectivePayrollSettings(2026).u1Applies, isFalse);

      // Erneutes Speichern überschreibt (kein zweiter Datensatz).
      await provider.saveOrgPayrollSettings(
        OrgPayrollSettings(
          orgId: 'org-1',
          jahr: 2026,
          settings: PayrollSettings.defaults2026().copyWith(uvRate: 0.011),
        ),
      );
      expect(provider.orgPayrollSettings.length, 1);
      expect(provider.effectivePayrollSettings(2026).uvRate, 0.011);

      // Persistenz über Neustart.
      final reopened = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(reopened.dispose);
      await reopened.updateSession(_admin, localStorageOnly: true);
      expect(reopened.orgPayrollSettingsForYear(2026)!.settings.uvRate, 0.011);

      // Reset -> wieder Defaults.
      await reopened.deleteOrgPayrollSettings(2026);
      expect(reopened.orgPayrollSettingsForYear(2026), isNull);
      expect(reopened.effectivePayrollSettings(2026).uvRate,
          OrgPayrollSettings.defaultSettingsForYear(2026).uvRate);
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

    test('streamt Sollzeit-Profile aus Firestore', () async {
      await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('sollzeitProfiles')
          .doc('sz-1')
          .set(SollzeitProfile(
            id: 'sz-1',
            orgId: 'org-1',
            userId: 'emp-1',
            gueltigAb: DateTime(2026, 1, 1),
            montagMinutes: 480,
            urlaubstageJahr: 30,
          ).toFirestoreMap());

      final provider = PersonalProvider(firestoreService: service);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final sz = provider.activeSollzeitFor('emp-1', DateTime(2026, 6, 1));
      expect(sz, isNotNull);
      expect(sz!.urlaubstageJahr, 30);
      expect(sz.montagMinutes, 480);
    });

    test('streamt Lohn-Konfiguration aus Firestore', () async {
      await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('payrollConfig')
          .doc('2026')
          .set(OrgPayrollSettings(
            id: '2026',
            orgId: 'org-1',
            jahr: 2026,
            settings: PayrollSettings.defaults2026().copyWith(uvRate: 0.018),
          ).toFirestoreMap());

      final provider = PersonalProvider(firestoreService: service);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.orgPayrollSettingsForYear(2026), isNotNull);
      expect(provider.effectivePayrollSettings(2026).uvRate, 0.018);
    });
  });

  group('PersonalProvider Urlaub-Vorrang & M0-Migration', () {
    const m2 = AppUserProfile(
      uid: 'emp-2',
      orgId: 'org-1',
      email: 'maria@example.com',
      role: UserRole.employee,
      isActive: true,
      settings: UserSettings(name: 'Maria'),
    );

    EmploymentContract contract(String uid, int urlaub) => EmploymentContract(
          orgId: 'org-1',
          userId: uid,
          validFrom: DateTime(2020, 1, 1),
          vacationDays: urlaub,
        );

    test('effektiveUrlaubstage löst die Vorrangregel §5.1 auf', () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);
      provider.updateReferenceData(
        members: const [_employee],
        contracts: [contract('emp-1', 28)],
      );

      // Nur Vertrag -> Vertrag.
      var r = provider.effektiveUrlaubstage('emp-1');
      expect(r.tage, 28);
      expect(r.quelle, UrlaubstageQuelle.vertrag);

      // + Mitarbeiterfeld -> schlägt Vertrag.
      await provider.saveEmployeeProfile(const EmployeeProfile(
          orgId: 'org-1', userId: 'emp-1', annualVacationDays: 32));
      r = provider.effektiveUrlaubstage('emp-1');
      expect(r.tage, 32);
      expect(r.quelle, UrlaubstageQuelle.mitarbeiterprofil);

      // + SollzeitProfile -> kanonisch, schlägt alles.
      await provider.saveSollzeitProfile(SollzeitProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        gueltigAb: DateTime(2024, 1, 1),
        urlaubstageJahr: 26,
      ));
      r = provider.effektiveUrlaubstage('emp-1');
      expect(r.tage, 26);
      expect(r.quelle, UrlaubstageQuelle.sollzeitProfile);
    });

    test('migriert Altfelder verbatim, ist idempotent und überspringt Profile',
        () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);
      provider.updateReferenceData(
        members: const [_employee, m2],
        contracts: [contract('emp-1', 30), contract('emp-2', 28)],
      );
      // emp-1: Mitarbeiterfeld (Vorrang); emp-2: nur Vertrag.
      await provider.saveEmployeeProfile(const EmployeeProfile(
          orgId: 'org-1', userId: 'emp-1', annualVacationDays: 30));

      expect(provider.mitarbeiterMitOffenerUrlaubsMigration.length, 2);

      final migriert = await provider.migriereUrlaubstageInSollzeit();
      expect(migriert, 2);
      expect(provider.mitarbeiterMitOffenerUrlaubsMigration, isEmpty);

      // Verbatim, 5-Tage-Voll bleibt 30 (B1, keine Skalierung).
      expect(provider.effektiveUrlaubstage('emp-1').tage, 30);
      expect(provider.effektiveUrlaubstage('emp-1').quelle,
          UrlaubstageQuelle.sollzeitProfile);
      expect(provider.effektiveUrlaubstage('emp-2').tage, 28);

      // Idempotent: zweiter Lauf legt nichts mehr an.
      final nochmal = await provider.migriereUrlaubstageInSollzeit();
      expect(nochmal, 0);
      expect(provider.sollzeitProfiles.length, 2);
    });

    test('migriert nicht für Mitarbeiter ohne Altdaten', () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);
      // Mitglied ohne Vertrag und ohne Profil -> nichts zu migrieren.
      provider.updateReferenceData(members: const [_employee]);

      expect(provider.mitarbeiterMitOffenerUrlaubsMigration, isEmpty);
      expect(await provider.migriereUrlaubstageInSollzeit(), 0);
    });

    test('reiner Default-30-Vertrag zählt nicht als offene Migration',
        () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);
      provider.updateReferenceData(
        members: const [_employee],
        contracts: [contract('emp-1', 30)], // = Default
      );

      expect(provider.mitarbeiterMitOffenerUrlaubsMigration, isEmpty);
      expect(await provider.migriereUrlaubstageInSollzeit(), 0);
      // Resolver liefert den Vertrags-Default dennoch.
      final r = provider.effektiveUrlaubstage('emp-1');
      expect(r.tage, 30);
      expect(r.quelle, UrlaubstageQuelle.vertrag);
    });

    test('effektiveUrlaubstage(at:) wechselt die Quelle über gueltigAb',
        () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);
      provider.updateReferenceData(
        members: const [_employee],
        contracts: [contract('emp-1', 28)],
      );
      await provider.saveEmployeeProfile(const EmployeeProfile(
          orgId: 'org-1', userId: 'emp-1', annualVacationDays: 32));
      await provider.saveSollzeitProfile(SollzeitProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        gueltigAb: DateTime(2026, 1, 1),
        urlaubstageJahr: 26,
      ));

      // Vor gueltigAb: Profil noch nicht aktiv -> Altfeld.
      final vorher = provider.effektiveUrlaubstage('emp-1', at: DateTime(2023, 6, 1));
      expect(vorher.tage, 32);
      expect(vorher.quelle, UrlaubstageQuelle.mitarbeiterprofil);
      // Nach gueltigAb: kanonisch.
      final nachher =
          provider.effektiveUrlaubstage('emp-1', at: DateTime(2026, 6, 1));
      expect(nachher.tage, 26);
      expect(nachher.quelle, UrlaubstageQuelle.sollzeitProfile);
    });

    test('zukünftiges Eintrittsdatum: Migrationsprofil gilt trotzdem heute',
        () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);
      provider.updateReferenceData(members: const [_employee]);
      await provider.saveEmployeeProfile(EmployeeProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        annualVacationDays: 25,
        hireDate: DateTime(2099, 1, 1), // Zukunft
      ));

      expect(await provider.migriereUrlaubstageInSollzeit(), 1);
      // gueltigAb wurde NICHT auf das Zukunftsdatum gesetzt -> heute aktiv.
      expect(provider.activeSollzeitFor('emp-1', DateTime.now()), isNotNull);
      final r = provider.effektiveUrlaubstage('emp-1');
      expect(r.quelle, UrlaubstageQuelle.sollzeitProfile);
      expect(r.tage, 25);
      expect(r.ausAltfeld, isFalse);
    });

    test('Nicht-Admin darf die Urlaubs-Migration nicht ausführen', () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_employee, localStorageOnly: true);
      await expectLater(
        provider.migriereUrlaubstageInSollzeit(),
        throwsA(isA<StateError>()),
      );
    });

    test('Cloud-Pfad: Migration schreibt Profile und bleibt idempotent',
        () async {
      // Echter Cloud-Modus über FakeFirebaseFirestore (kein localStorageOnly).
      final provider = PersonalProvider(firestoreService: service);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin);
      provider.updateReferenceData(members: const [_employee]);
      await provider.saveEmployeeProfile(const EmployeeProfile(
          orgId: 'org-1', userId: 'emp-1', annualVacationDays: 27));
      await Future<void>.delayed(Duration.zero);

      final migriert = await provider.migriereUrlaubstageInSollzeit();
      expect(migriert, 1);

      // Profil liegt unter der deterministischen Doc-ID in Firestore.
      final docs = await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('sollzeitProfiles')
          .get();
      expect(docs.docs.length, 1);
      expect(docs.docs.single.id, 'urlaub-migration-emp-1');
      expect(docs.docs.single.data()['urlaubstageJahr'], 27);

      // Stream zustellen lassen, dann zweiter Lauf -> idempotent (0, kein Dup).
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(await provider.migriereUrlaubstageInSollzeit(), 0);
      final docs2 = await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('sollzeitProfiles')
          .get();
      expect(docs2.docs.length, 1);
    });
  });

  group('PersonalProvider HR-Sub-Entitäten (M-H)', () {
    test('Kinder/Quali/Ausbildung: CRUD + Persistenz', () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);

      await provider.saveEmployeeChild(const EmployeeChild(
          orgId: 'org-1', userId: 'emp-1', vorname: 'Mia', name: 'M'));
      await provider.saveEmployeeQualification(const EmployeeQualification(
          orgId: 'org-1', userId: 'emp-1', qualificationName: 'Kasse'));
      await provider.saveEmployeeAusbildung(const EmployeeAusbildung(
          orgId: 'org-1', userId: 'emp-1', bezeichnung: 'Azubi'));

      expect(provider.childrenForUser('emp-1').length, 1);
      expect(provider.qualificationsForUser('emp-1').single.qualificationName,
          'Kasse');
      expect(provider.ausbildungenForUser('emp-1').single.bezeichnung, 'Azubi');

      // Persistenz über Neustart.
      final reopened = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(reopened.dispose);
      await reopened.updateSession(_admin, localStorageOnly: true);
      expect(reopened.childrenForUser('emp-1').length, 1);

      // Löschen.
      final childId = reopened.childrenForUser('emp-1').single.id!;
      await reopened.deleteEmployeeChild(childId);
      expect(reopened.childrenForUser('emp-1'), isEmpty);
    });

    test('Kinderzähler-Einzelquelle §4.4', () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);

      // Ohne gepflegte Kinder: Altfeld childrenCount ist die Quelle.
      await provider.saveEmployeeProfile(const EmployeeProfile(
          orgId: 'org-1', userId: 'emp-1', childrenCount: 2));
      expect(provider.hatGepflegteKinder('emp-1'), isFalse);
      expect(provider.effektiveKinderzahl('emp-1'), 2);

      // Sobald ein Kind gepflegt ist, zählt count(zaehltFuerFreibetrag).
      await provider.saveEmployeeChild(const EmployeeChild(
          orgId: 'org-1', userId: 'emp-1', vorname: 'A'));
      expect(provider.hatGepflegteKinder('emp-1'), isTrue);
      expect(provider.effektiveKinderzahl('emp-1'), 1); // schlägt childrenCount=2

      // Kind ohne Freibetrag zählt nicht mit.
      await provider.saveEmployeeChild(const EmployeeChild(
          orgId: 'org-1',
          userId: 'emp-1',
          vorname: 'B',
          zaehltFuerFreibetrag: false));
      expect(provider.childrenForUser('emp-1').length, 2);
      expect(provider.effektiveKinderzahl('emp-1'), 1);
    });

    test('Kinderzähler §4.4: alle Kinder ohne Freibetrag → 0 (kein Fallback)',
        () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);
      // Altfeld gesetzt – dürfte NICHT greifen, sobald Kinder gepflegt sind.
      await provider.saveEmployeeProfile(const EmployeeProfile(
          orgId: 'org-1', userId: 'emp-1', childrenCount: 2));
      await provider.saveEmployeeChild(const EmployeeChild(
          orgId: 'org-1',
          userId: 'emp-1',
          vorname: 'Erwachsen',
          zaehltFuerFreibetrag: false));

      // Freibetrag-Zähler 0 (kein Fallback auf childrenCount=2)…
      expect(provider.effektiveKinderzahl('emp-1'), 0);
      // …aber Elterneigenschaft bleibt wahr (steuert PV-Kinderlosenzuschlag,
      // entkoppelt vom Freibetrag-Zähler).
      expect(provider.hatGepflegteKinder('emp-1'), isTrue);
    });

    test('Speichermodus-Migration deckt die HR-Sub-Entitäten ab', () async {
      // Cloud → local: cacheCloudStateLocally spiegelt Kinder in den lokalen Cache.
      final cloud = PersonalProvider(firestoreService: service);
      addTearDown(cloud.dispose);
      await cloud.updateSession(_admin);
      await cloud.saveEmployeeChild(const EmployeeChild(
          orgId: 'org-1', userId: 'emp-1', vorname: 'Cloud'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await cloud.cacheCloudStateLocally();
      final local = await DatabaseService.loadLocalEmployeeChildren(
          scope: LocalStorageScope.fromUser(_admin));
      expect(local.any((c) => c.vorname == 'Cloud'), isTrue);

      // local → cloud: syncLocalStateToCloud lädt lokal angelegte Kinder hoch.
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
      final fs2 = FakeFirebaseFirestore();
      final svc2 = FirestoreService(firestore: fs2);
      final localProv = PersonalProvider(
          firestoreService: svc2, disableAuthentication: true);
      addTearDown(localProv.dispose);
      await localProv.updateSession(_admin, localStorageOnly: true);
      await localProv.saveEmployeeChild(const EmployeeChild(
          orgId: 'org-1', userId: 'emp-1', vorname: 'Lokal'));
      await localProv.syncLocalStateToCloud();
      final docs = await fs2
          .collection('organizations')
          .doc('org-1')
          .collection('employeeChildren')
          .get();
      expect(docs.docs.any((d) => d.data()['vorname'] == 'Lokal'), isTrue);
    });

    test('Nicht-Admin darf HR-Sub-Entitäten nicht schreiben', () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_employee, localStorageOnly: true);
      await expectLater(
        provider.saveEmployeeChild(
            const EmployeeChild(orgId: 'org-1', userId: 'emp-1', vorname: 'X')),
        throwsA(isA<StateError>()),
      );
    });

    test('streamt Kinder aus Firestore (Cloud)', () async {
      await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('employeeChildren')
          .doc('c-1')
          .set(const EmployeeChild(
                  id: 'c-1', orgId: 'org-1', userId: 'emp-1', vorname: 'Mia')
              .toFirestoreMap());

      final provider = PersonalProvider(firestoreService: service);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.childrenForUser('emp-1').length, 1);
      expect(provider.effektiveKinderzahl('emp-1'), 1);
    });
  });

  group('PersonalProvider Urlaubskonto (M-U)', () {
    test('urlaubsReportFor komponiert Sollzeit, Vortrag und Anträge', () async {
      // Genehmigten Urlaub (2 Werktage) lokal vorbelegen.
      DatabaseService.resetCachedPrefs();
      await DatabaseService.saveLocalAbsenceRequests([
        AbsenceRequest(
          orgId: 'org-1',
          userId: 'emp-1',
          employeeName: 'Peter',
          startDate: DateTime(2026, 6, 1), // Mo
          endDate: DateTime(2026, 6, 2), // Di
          type: AbsenceType.vacation,
          status: AbsenceStatus.approved,
        ),
      ], scope: LocalStorageScope.fromUser(_admin));

      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);

      await provider.saveSollzeitProfile(SollzeitProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        gueltigAb: DateTime(2020, 1, 1),
        montagMinutes: 480,
        dienstagMinutes: 480,
        mittwochMinutes: 480,
        donnerstagMinutes: 480,
        freitagMinutes: 480,
        urlaubstageJahr: 30,
      ));
      await provider.saveUrlaubskontoJahr(const UrlaubskontoJahr(
          orgId: 'org-1', userId: 'emp-1', jahr: 2026, vortragVorjahrTage: 5));

      final report = provider.urlaubsReportFor('emp-1', 2026);
      expect(report.anspruchJahr, 30);
      expect(report.vortragVorjahr, 5);
      expect(report.genommen, 2);
      expect(report.resturlaub, 33); // 30 + 5 - 2
    });

    test('Urlaubskonto/-Anpassung CRUD + deterministische ID + Persistenz',
        () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);

      await provider.saveUrlaubskontoJahr(const UrlaubskontoJahr(
          orgId: 'org-1', userId: 'emp-1', jahr: 2026, vortragVorjahrTage: 3));
      // Erneut speichern überschreibt (Doc-ID = userId-jahr).
      await provider.saveUrlaubskontoJahr(const UrlaubskontoJahr(
          orgId: 'org-1', userId: 'emp-1', jahr: 2026, vortragVorjahrTage: 4));
      expect(provider.urlaubskontoJahre.length, 1);
      expect(provider.urlaubskontoFor('emp-1', 2026)!.vortragVorjahrTage, 4);

      await provider.saveUrlaubsanpassung(const Urlaubsanpassung(
          orgId: 'org-1', userId: 'emp-1', jahr: 2026, tage: 2));
      expect(provider.urlaubsanpassungenForUser('emp-1', jahr: 2026).length, 1);

      // Persistenz über Neustart.
      final reopened = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(reopened.dispose);
      await reopened.updateSession(_admin, localStorageOnly: true);
      expect(reopened.urlaubskontoFor('emp-1', 2026)!.vortragVorjahrTage, 4);

      final id = reopened.urlaubsanpassungenForUser('emp-1').single.id!;
      await reopened.deleteUrlaubsanpassung(id);
      expect(reopened.urlaubsanpassungen, isEmpty);
    });

    test('Speichermodus-Migration deckt Urlaubskonto + Anpassung ab', () async {
      final cloud = PersonalProvider(firestoreService: service);
      addTearDown(cloud.dispose);
      await cloud.updateSession(_admin);
      await cloud.saveUrlaubskontoJahr(const UrlaubskontoJahr(
          orgId: 'org-1', userId: 'emp-1', jahr: 2026, vortragVorjahrTage: 6));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await cloud.cacheCloudStateLocally();
      final local = await DatabaseService.loadLocalUrlaubskontoJahre(
          scope: LocalStorageScope.fromUser(_admin));
      expect(local.any((k) => k.vortragVorjahrTage == 6), isTrue);
    });

    test('Nicht-Admin darf Urlaubskonto nicht schreiben', () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_employee, localStorageOnly: true);
      await expectLater(
        provider.saveUrlaubskontoJahr(const UrlaubskontoJahr(
            orgId: 'org-1', userId: 'emp-1', jahr: 2026)),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('PersonalProvider Lohn-Konfiguration – Hybrid & Audit', () {
    test('hybrid-Offline: fehlgeschlagener Cloud-Write fällt lokal zurück',
        () async {
      final provider = PersonalProvider(
        firestoreService: _FailingPayrollConfigService(firestore: firestore),
      );
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, hybridStorageEnabled: true);

      // Wirft NICHT, obwohl der Cloud-Write scheitert.
      await provider.saveOrgPayrollSettings(
        OrgPayrollSettings(
          orgId: 'org-1',
          jahr: 2026,
          settings: PayrollSettings.defaults2026().copyWith(uvRate: 0.019),
        ),
      );

      // Lokal persistiert (Stream-Read kann die In-Memory-Liste leeren, daher
      // gegen den lokalen Speicher prüfen – wie im ContactProvider-Hybridtest).
      final persisted = await DatabaseService.loadLocalOrgPayrollSettings(
        scope: LocalStorageScope.fromUser(_admin),
      );
      expect(persisted.any((c) => c.jahr == 2026 && c.settings.uvRate == 0.019),
          isTrue);
    });

    test('Audit: created/updated/deleted mit entityType + Jahr-entityId',
        () async {
      final logged = <({
        AuditAction action,
        String entityType,
        String? entityId,
        String summary
      })>[];
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      provider.setAuditSink((
          {required AuditAction action,
          required String entityType,
          String? entityId,
          required String summary}) {
        logged.add((
          action: action,
          entityType: entityType,
          entityId: entityId,
          summary: summary,
        ));
      });
      await provider.updateSession(_admin, localStorageOnly: true);

      OrgPayrollSettings cfg(double uv) => OrgPayrollSettings(
            orgId: 'org-1',
            jahr: 2026,
            settings: PayrollSettings.defaults2026().copyWith(uvRate: uv),
          );

      await provider.saveOrgPayrollSettings(cfg(0.012)); // created
      await provider.saveOrgPayrollSettings(cfg(0.013)); // updated (gleiches Jahr)
      await provider.deleteOrgPayrollSettings(2026); // deleted

      expect(logged.map((e) => e.action), [
        AuditAction.created,
        AuditAction.updated,
        AuditAction.deleted,
      ]);
      expect(logged.every((e) => e.entityType == 'Lohn-Einstellungen'), isTrue);
      expect(logged.every((e) => e.entityId == '2026'), isTrue);
    });
  });

  group('PersonalProvider Personalkosten → JournalEntry (H-A1)', () {
    Future<({PersonalProvider personal, FinanceProvider finance})> wire({
      bool withCostType = true,
    }) async {
      final finance = FinanceProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(finance.dispose);
      await finance.updateSession(_admin, localStorageOnly: true);
      await finance.saveCostCenter(const CostCenter(
        orgId: 'org-1',
        number: '1001',
        name: 'Strichmännchen',
        siteId: 'site-1',
      ));
      if (withCostType) {
        await finance.saveCostType(const CostType(
          orgId: 'org-1',
          number: '4120',
          name: 'Personalkosten',
        ));
      }

      final personal = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(personal.dispose);
      await personal.updateSession(_admin, localStorageOnly: true);
      personal.updateReferenceData(
        members: const [_employee],
        siteAssignments: const [
          EmployeeSiteAssignment(
            orgId: 'org-1',
            userId: 'emp-1',
            siteId: 'site-1',
            siteName: 'Strichmännchen',
            isPrimary: true,
          ),
        ],
      );
      personal.setPayrollJournalPoster(finance.postPersonnelCostJournal);
      return (personal: personal, finance: finance);
    }

    const draft = PayrollRecord(
      orgId: 'org-1',
      userId: 'emp-1',
      periodYear: 2026,
      periodMonth: 6,
      grossCents: 300000,
      employerTotalCents: 360000,
    );

    test('Freigabe bucht Personalkosten genau einmal + Rückverweis', () async {
      final (:personal, :finance) = await wire();
      await personal.savePayrollRecord(draft);
      final saved = personal.payrollForUserPeriod('emp-1', 2026, 6)!;

      await personal.setPayrollStatus(saved, PayrollStatus.freigegeben);

      // Genau eine Buchung mit deterministischer ID + AG-Gesamtbetrag.
      expect(finance.journalEntries, hasLength(1));
      final entry = finance.journalEntries.single;
      expect(entry.id, 'pay-emp-1-2026-06');
      expect(entry.amountCents, 360000);
      expect(entry.costCenterId, isNotEmpty);
      expect(entry.reference, 'emp-1-2026-06');

      // Rückverweis am PayrollRecord.
      final booked = personal.payrollForUserPeriod('emp-1', 2026, 6)!;
      expect(booked.journalEntryId, 'pay-emp-1-2026-06');

      // freigegeben → bezahlt darf NICHT erneut buchen.
      await personal.setPayrollStatus(booked, PayrollStatus.bezahlt);
      expect(finance.journalEntries, hasLength(1));
    });

    test('deterministische ID verhindert Doppelbuchung bei Re-Trigger',
        () async {
      final (:personal, :finance) = await wire();
      await personal.savePayrollRecord(draft);
      final saved = personal.payrollForUserPeriod('emp-1', 2026, 6)!;

      // Zweimal mit DEMSELBEN Entwurf (journalEntryId noch null) freigeben —
      // simuliert einen verlorenen Ack / doppelten Trigger.
      await personal.setPayrollStatus(saved, PayrollStatus.freigegeben);
      await personal.setPayrollStatus(saved, PayrollStatus.freigegeben);

      expect(finance.journalEntries, hasLength(1));
    });

    test('keine Buchung ohne auflösbare Kostenart (keine Falschbuchung)',
        () async {
      final (:personal, :finance) = await wire(withCostType: false);
      await personal.savePayrollRecord(draft);
      final saved = personal.payrollForUserPeriod('emp-1', 2026, 6)!;

      await personal.setPayrollStatus(saved, PayrollStatus.freigegeben);

      expect(finance.journalEntries, isEmpty);
      expect(personal.payrollForUserPeriod('emp-1', 2026, 6)!.journalEntryId,
          isNull);
    });
  });

  group('PersonalProvider federalStateForUserPrimarySite (H-C3)', () {
    test('leitet aus dem Primärstandort über die siteId ab', () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);
      provider.updateReferenceData(
        members: const [_employee],
        sites: const [
          SiteDefinition(
              id: 'site-1', orgId: 'org-1', name: 'Kiel', federalState: 'Schleswig-Holstein'),
          SiteDefinition(
              id: 'site-2',
              orgId: 'org-1',
              name: 'München',
              federalState: 'Bayern'),
        ],
        siteAssignments: const [
          EmployeeSiteAssignment(
            orgId: 'org-1',
            userId: 'emp-1',
            siteId: 'site-1',
            siteName: 'Kiel',
            isPrimary: false,
          ),
          EmployeeSiteAssignment(
            orgId: 'org-1',
            userId: 'emp-1',
            siteId: 'site-2',
            siteName: 'München',
            isPrimary: true,
          ),
        ],
      );

      // Primärstandort = site-2 (Bayern), nicht der erst gelistete Kiel.
      expect(provider.federalStateForUserPrimarySite('emp-1'), 'Bayern');
      expect(provider.federalStateForUserPrimarySite('unbekannt'), isNull);
    });

    test('null ohne Zuordnung oder ohne Bundesland am Standort', () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);
      provider.updateReferenceData(
        sites: const [
          SiteDefinition(id: 'site-1', orgId: 'org-1', name: 'Ohne Land'),
        ],
        siteAssignments: const [
          EmployeeSiteAssignment(
            orgId: 'org-1',
            userId: 'emp-1',
            siteId: 'site-1',
            siteName: 'Ohne Land',
            isPrimary: true,
          ),
        ],
      );
      expect(provider.federalStateForUserPrimarySite('emp-1'), isNull);
    });
  });

  group('PersonalProvider Lohnarten-Katalog (M-L)', () {
    test('CRUD + Auto-ID + activePayLineTypes-Filter + Persistenz', () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);

      await provider.savePayLineType(const PayLineType(
        orgId: 'org-1',
        name: 'Nachtzuschlag',
        kind: PayLineKind.zuschlag3b,
        datevLohnartNr: '300',
      ));
      await provider.savePayLineType(const PayLineType(
        orgId: 'org-1',
        name: 'Altlast',
        deaktiviert: true,
      ));
      expect(provider.payLineTypes.length, 2);
      expect(provider.activePayLineTypes.length, 1);
      expect(provider.activePayLineTypes.single.name, 'Nachtzuschlag');

      // Update über dieselbe ID (kein Duplikat).
      final id = provider.payLineTypes.firstWhere((t) => t.name == 'Altlast').id!;
      await provider.savePayLineType(provider.payLineTypes
          .firstWhere((t) => t.id == id)
          .copyWith(deaktiviert: false, name: 'Reaktiviert'));
      expect(provider.payLineTypes.length, 2);
      expect(provider.activePayLineTypes.length, 2);

      // Persistenz über Neustart.
      final reopened = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(reopened.dispose);
      await reopened.updateSession(_admin, localStorageOnly: true);
      expect(reopened.payLineTypes.length, 2);

      await reopened.deletePayLineType(id);
      expect(reopened.payLineTypes.length, 1);
    });

    test('Speichermodus-Migration deckt payLineTypes ab', () async {
      final cloud = PersonalProvider(firestoreService: service);
      addTearDown(cloud.dispose);
      await cloud.updateSession(_admin);
      await cloud.savePayLineType(const PayLineType(
          orgId: 'org-1', name: 'VwL-Zuschuss', kind: PayLineKind.vwl));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await cloud.cacheCloudStateLocally();
      final local = await DatabaseService.loadLocalPayLineTypes(
          scope: LocalStorageScope.fromUser(_admin));
      expect(local.any((t) => t.name == 'VwL-Zuschuss'), isTrue);
    });

    test('Nicht-Admin darf Lohnarten nicht schreiben', () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_employee, localStorageOnly: true);
      await expectLater(
        provider.savePayLineType(
            const PayLineType(orgId: 'org-1', name: 'X')),
        throwsA(isA<StateError>()),
      );
    });

    test('hybrid-Offline: fehlgeschlagener Cloud-Write fällt lokal zurück',
        () async {
      final provider = PersonalProvider(
        firestoreService: _FailingPayrollConfigService(firestore: firestore),
      );
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, hybridStorageEnabled: true);

      await provider.savePayLineType(
          const PayLineType(orgId: 'org-1', name: 'Offline-Zulage'));

      final persisted = await DatabaseService.loadLocalPayLineTypes(
        scope: LocalStorageScope.fromUser(_admin),
      );
      expect(persisted.any((t) => t.name == 'Offline-Zulage'), isTrue);
    });

    test('deletePayLineType ist idempotent (zweiter Delete wirft nicht)',
        () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);
      await provider.savePayLineType(
          const PayLineType(orgId: 'org-1', name: 'Temp'));
      final id = provider.payLineTypes.single.id!;
      await provider.deletePayLineType(id);
      expect(provider.payLineTypes, isEmpty);
      // Zweiter Delete auf bereits entfernte ID wirft nicht.
      await provider.deletePayLineType(id);
      expect(provider.payLineTypes, isEmpty);
    });

    test('streamt payLineTypes aus Firestore (Cloud)', () async {
      await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('payLineTypes')
          .doc('plt-1')
          .set(const PayLineType(
                  id: 'plt-1', orgId: 'org-1', name: 'Sonntagszuschlag')
              .toFirestoreMap());

      final provider = PersonalProvider(firestoreService: service);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.payLineTypes.length, 1);
      expect(provider.payLineTypes.single.name, 'Sonntagszuschlag');
    });
  });

  group('PersonalProvider M7 Self-Read (Sollzeit)', () {
    test('Nicht-Admin lädt NUR das eigene Sollzeit-Profil (self-scoped)',
        () async {
      // Zwei Profile in der Cloud: eigenes (emp-1) + fremdes (emp-2).
      await service.saveSollzeitProfile(SollzeitProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        gueltigAb: DateTime(2024, 1, 1),
        urlaubstageJahr: 28,
      ));
      await service.saveSollzeitProfile(SollzeitProfile(
        orgId: 'org-1',
        userId: 'emp-2',
        gueltigAb: DateTime(2024, 1, 1),
        urlaubstageJahr: 30,
      ));

      final provider = PersonalProvider(firestoreService: service);
      addTearDown(provider.dispose);
      await provider.updateSession(_employee); // Cloud, Nicht-Admin
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final eigene = provider.sollzeitProfilesForUser('emp-1');
      expect(eigene, hasLength(1));
      // Fremdes Profil ist NICHT geladen (self-scoped Query).
      expect(provider.sollzeitProfilesForUser('emp-2'), isEmpty);
    });
  });

  group('PersonalProvider buildDraftPayrollForMonth (M5)', () {
    test('Stundenlöhner: Brutto aus istMinutes × Stundenlohn', () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);
      provider.updateReferenceData(
        members: const [_employee],
        contracts: [
          EmploymentContract(
            orgId: 'org-1',
            userId: 'emp-1',
            validFrom: DateTime(2020, 1, 1),
            salaryKind: SalaryKind.hourly,
            hourlyRate: 15,
          ),
        ],
      );

      // 9600 min = 160 h × 15 €/h = 2400 € = 240000 ct.
      final draft = provider.buildDraftPayrollForMonth(
        userId: 'emp-1',
        year: 2026,
        month: 6,
        istMinutes: 9600,
      );
      expect(draft, isNotNull);
      expect(draft!.grossCents, 240000);
      expect(draft.status, PayrollStatus.entwurf);
      expect(draft.periodYear, 2026);
      expect(draft.periodMonth, 6);
      expect(draft.userId, 'emp-1');
      expect(draft.netCents, greaterThan(0));
      expect(draft.netCents, lessThan(draft.grossCents));
    });

    test('Festgehalt: Brutto = monthlyGrossCents (unabhängig von Stunden)',
        () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);
      provider.updateReferenceData(
        members: const [_employee],
        contracts: [
          EmploymentContract(
            orgId: 'org-1',
            userId: 'emp-1',
            validFrom: DateTime(2020, 1, 1),
            monthlyGrossCents: 300000,
          ),
        ],
      );

      final draft = provider.buildDraftPayrollForMonth(
        userId: 'emp-1',
        year: 2026,
        month: 6,
        istMinutes: 0,
      );
      expect(draft, isNotNull);
      expect(draft!.grossCents, 300000);
    });

    test('null ohne ermittelbares Brutto (kein Festgehalt, keine Stunden)',
        () async {
      final provider = PersonalProvider(
          firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);
      provider.updateReferenceData(
        members: const [_employee],
        contracts: [
          EmploymentContract(
            orgId: 'org-1',
            userId: 'emp-1',
            validFrom: DateTime(2020, 1, 1),
            salaryKind: SalaryKind.hourly,
            hourlyRate: 15,
          ),
        ],
      );

      final draft = provider.buildDraftPayrollForMonth(
        userId: 'emp-1',
        year: 2026,
        month: 6,
        istMinutes: 0,
      );
      expect(draft, isNull);
    });
  });
}
