import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/core/datev_export.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/cash_closing.dart';
import 'package:worktime_app/models/finance_models.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/finance_provider.dart';
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

  group('FinanceProvider (local)', () {
    test('CRUD über alle 4 Collections + Persistenz + Analytik', () async {
      final provider =
          FinanceProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);

      await provider.saveCostCenter(const CostCenter(
        orgId: 'org-1',
        number: '1001',
        name: 'Strichmännchen',
      ));
      await provider.saveCostType(const CostType(
        orgId: 'org-1',
        number: '4100',
        name: 'Miete',
      ));
      expect(provider.costCenters.length, 1);
      expect(provider.costTypes.length, 1);
      final ccId = provider.costCenters.single.id!;
      final ctId = provider.costTypes.single.id!;

      await provider.saveJournalEntry(JournalEntry(
        orgId: 'org-1',
        date: DateTime(2026, 3, 1),
        costCenterId: ccId,
        costTypeId: ctId,
        description: 'Märzmiete',
        amountCents: 250000,
      ));
      await provider.saveJournalEntry(JournalEntry(
        orgId: 'org-1',
        date: DateTime(2026, 4, 1),
        costCenterId: ccId,
        costTypeId: ctId,
        description: 'Gutschrift',
        amountCents: -50000,
      ));
      await provider.saveBudget(Budget(
        orgId: 'org-1',
        costCenterId: ccId,
        year: 2026,
        plannedAmountCents: 300000,
      ));

      // Analytik: Ist = 250000 - 50000 = 200000, Plan = 300000.
      final reports = provider.costCenterReports(2026);
      expect(reports.single.actualCents, 200000);
      expect(reports.single.plannedCents, 300000);
      expect(reports.single.isOverBudget, isFalse);
      expect(provider.totalExpenses(2026), 250000);
      expect(provider.totalCredits(2026), 50000);
      expect(provider.totalActual(2026), 200000);
      expect(provider.yearsWithEntries, [2026]);

      // Budget-Upsert (deterministische ID) überschreibt statt zu duplizieren.
      await provider.saveBudget(Budget(
        orgId: 'org-1',
        costCenterId: ccId,
        year: 2026,
        plannedAmountCents: 400000,
      ));
      expect(provider.budgets.length, 1);
      expect(provider.costCenterReports(2026).single.plannedCents, 400000);

      // Persistenz über Neustart.
      final reopened =
          FinanceProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(reopened.dispose);
      await reopened.updateSession(_admin, localStorageOnly: true);
      expect(reopened.journalEntries.length, 2);
      expect(reopened.costCenterReports(2026).single.actualCents, 200000);

      // Löschen einer Buchung.
      final entryId = reopened.journalEntries
          .firstWhere((e) => e.amountCents == 250000)
          .id!;
      await reopened.deleteJournalEntry(entryId);
      expect(reopened.journalEntries.length, 1);
      expect(reopened.totalActual(2026), -50000);
    });

    test('costCenterForSite liefert deterministisch die kleinste Nummer (H-C1)',
        () async {
      final provider =
          FinanceProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);

      await provider.saveCostCenter(const CostCenter(
        orgId: 'org-1',
        number: '1002',
        name: 'Tabak Börse B',
        siteId: 'site-2',
      ));
      await provider.saveCostCenter(const CostCenter(
        orgId: 'org-1',
        number: '1001',
        name: 'Tabak Börse A',
        siteId: 'site-2',
      ));
      await provider.saveCostCenter(const CostCenter(
        orgId: 'org-1',
        number: '1003',
        name: 'Inaktiv',
        siteId: 'site-2',
        isActive: false,
      ));
      await provider.saveCostCenter(const CostCenter(
        orgId: 'org-1',
        number: '2000',
        name: 'Strichmännchen',
        siteId: 'site-1',
      ));

      // Mehrere aktive Treffer → kleinste Nummer gewinnt; inaktive ignoriert.
      expect(provider.costCenterForSite('site-2')?.number, '1001');
      expect(provider.costCenterForSite('site-1')?.number, '2000');
      expect(provider.costCenterForSite('unbekannt'), isNull);
      expect(provider.costCenterForSite(null), isNull);
    });

    test('Nicht-Admin darf nicht schreiben', () async {
      final provider =
          FinanceProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_employee, localStorageOnly: true);

      await expectLater(
        provider.saveCostCenter(
          const CostCenter(orgId: 'org-1', number: '1', name: 'x'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('DATEV-Config persistiert über Neustart + ist admin-gated', () async {
      final provider =
          FinanceProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);
      expect(provider.datevConfig.defaultContraAccount, '9000'); // Default

      await provider.saveDatevConfig(const DatevExportConfig(
        consultantNumber: '4242',
        clientNumber: '99',
        accountLength: 5,
        defaultContraAccount: '8400',
      ));
      expect(provider.datevConfig.consultantNumber, '4242');

      final reopened =
          FinanceProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(reopened.dispose);
      await reopened.updateSession(_admin, localStorageOnly: true);
      expect(reopened.datevConfig.consultantNumber, '4242');
      expect(reopened.datevConfig.accountLength, 5);
      expect(reopened.datevConfig.defaultContraAccount, '8400');

      await reopened.updateSession(_employee, localStorageOnly: true);
      await expectLater(
        reopened.saveDatevConfig(const DatevExportConfig()),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('FinanceProvider (cloud)', () {
    test('streamt Kostenstellen + Buchungen aus Firestore', () async {
      await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('costCenters')
          .doc('cc1')
          .set(const CostCenter(
            id: 'cc1',
            orgId: 'org-1',
            number: '1002',
            name: 'Tabak Börse',
          ).toFirestoreMap());

      await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('journalEntries')
          .doc('j1')
          .set(JournalEntry(
            id: 'j1',
            orgId: 'org-1',
            date: DateTime(2026, 1, 5),
            costCenterId: 'cc1',
            costTypeId: 't1',
            description: 'Wareneinkauf',
            amountCents: 120000,
          ).toFirestoreMap());

      final provider = FinanceProvider(firestoreService: service);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.costCenters.map((c) => c.id), contains('cc1'));
      expect(provider.costCenterById('cc1')!.name, 'Tabak Börse');
      expect(provider.totalExpenses(2026), 120000);
    });
  });

  group('FinanceProvider Speichermodus-Migration (H-H1)', () {
    test('cacheCloudStateLocally schreibt Cloud-Stand in den lokalen Speicher',
        () async {
      await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('costCenters')
          .doc('cc1')
          .set(const CostCenter(
                  id: 'cc1', orgId: 'org-1', number: '1001', name: 'Laden')
              .toFirestoreMap());
      await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('journalEntries')
          .doc('j1')
          .set(JournalEntry(
            id: 'j1',
            orgId: 'org-1',
            date: DateTime(2026, 2, 1),
            costCenterId: 'cc1',
            costTypeId: 't1',
            description: 'Miete',
            amountCents: 90000,
          ).toFirestoreMap());

      final cloud = FinanceProvider(firestoreService: service);
      addTearDown(cloud.dispose);
      await cloud.updateSession(_admin);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(cloud.journalEntries, hasLength(1));

      await cloud.cacheCloudStateLocally();

      // Neuer Provider im local-Modus liest den gecachten Stand.
      final local =
          FinanceProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(local.dispose);
      await local.updateSession(_admin, localStorageOnly: true);
      expect(local.costCenterById('cc1')?.name, 'Laden');
      expect(local.journalEntries.map((e) => e.id), contains('j1'));
    });

    test('syncLocalStateToCloud lädt das Journal idempotent hoch (append-only)',
        () async {
      final local =
          FinanceProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(local.dispose);
      await local.updateSession(_admin, localStorageOnly: true);
      await local.saveCostCenter(
          const CostCenter(id: 'cc1', orgId: 'org-1', number: '1', name: 'L'));
      await local.saveCostType(
          const CostType(id: 't1', orgId: 'org-1', number: '4', name: 'M'));
      await local.saveJournalEntry(JournalEntry(
        id: 'pay-emp-2026-06',
        orgId: 'org-1',
        date: DateTime(2026, 6, 30),
        costCenterId: 'cc1',
        costTypeId: 't1',
        description: 'Personalkosten',
        amountCents: 360000,
      ));

      Future<int> cloudJournalCount() async {
        final snap = await firestore
            .collection('organizations')
            .doc('org-1')
            .collection('journalEntries')
            .get();
        return snap.docs.length;
      }

      await local.syncLocalStateToCloud();
      expect(await cloudJournalCount(), 1);

      // Zweiter Sync → kein Duplikat (Upsert über deterministische Doc-ID).
      await local.syncLocalStateToCloud();
      expect(await cloudJournalCount(), 1);
    });
  });

  group('postCashDifference (M6, §8a)', () {
    Future<FinanceProvider> seeded({bool withCashDiffType = true}) async {
      final provider =
          FinanceProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_admin, localStorageOnly: true);
      await provider.saveCostCenter(const CostCenter(
          orgId: 'org-1', number: '1001', name: 'Laden', siteId: 'site-1'));
      if (withCashDiffType) {
        await provider.saveCostType(const CostType(
            orgId: 'org-1', number: '6900', name: 'Kassendifferenz'));
      }
      return provider;
    }

    CashClosing closing(int? diff) => CashClosing(
          orgId: 'org-1',
          siteId: 'site-1',
          businessDay: '2026-06-30',
          cashDifferenceCents: diff,
          closedByUid: 'admin-1',
        );

    test('Fehlbetrag wird als Kosten gebucht, idempotent', () async {
      final provider = await seeded();
      final ok = await provider.postCashDifference(closing(-250));
      expect(ok, isTrue);
      final booked = provider.journalEntries
          .where((e) => e.id == 'pos-diff-2026-06-30-site-1');
      expect(booked, hasLength(1));
      expect(booked.single.amountCents, 250);

      // Zweite Buchung → kein Duplikat (deterministische ID).
      await provider.postCashDifference(closing(-250));
      expect(
        provider.journalEntries
            .where((e) => e.id == 'pos-diff-2026-06-30-site-1'),
        hasLength(1),
      );
    });

    test('ohne Kassendifferenz-Kostenart wird still übersprungen', () async {
      final provider = await seeded(withCashDiffType: false);
      final ok = await provider.postCashDifference(closing(-250));
      expect(ok, isFalse);
      expect(provider.journalEntries, isEmpty);
    });

    test('keine Differenz → keine Buchung', () async {
      final provider = await seeded();
      expect(await provider.postCashDifference(closing(null)), isFalse);
      expect(await provider.postCashDifference(closing(0)), isFalse);
      expect(provider.journalEntries, isEmpty);
    });

    test('Nicht-Admin darf nicht buchen', () async {
      final provider =
          FinanceProvider(firestoreService: service, disableAuthentication: true);
      addTearDown(provider.dispose);
      await provider.updateSession(_employee, localStorageOnly: true);
      expect(await provider.postCashDifference(closing(-250)), isFalse);
    });
  });
}
