import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
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
}
