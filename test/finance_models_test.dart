import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/finance_analytics.dart';
import 'package:worktime_app/models/finance_models.dart';

void main() {
  group('Finanz-Modelle Serialisierung', () {
    test('CostCenter round-trip (beide Formate)', () {
      const center = CostCenter(
        orgId: 'org-1',
        number: '1001',
        name: 'Strichmännchen',
        description: 'Laden Kiel-Mitte',
        costBearerRef: 'KT-01',
        annualBudgetCents: 12000000,
        isBillable: true,
        isActive: true,
      );
      final local = CostCenter.fromMap(center.toMap());
      expect(local.number, '1001');
      expect(local.name, 'Strichmännchen');
      expect(local.description, 'Laden Kiel-Mitte');
      expect(local.costBearerRef, 'KT-01');
      expect(local.annualBudgetCents, 12000000);
      expect(local.isBillable, isTrue);

      final fs = center.toFirestoreMap();
      expect(fs['number'], '1001');
      expect(fs['annualBudgetCents'], 12000000);
      final cloud = CostCenter.fromFirestore('c1', fs);
      expect(cloud.id, 'c1');
      expect(cloud.name, 'Strichmännchen');
      expect(cloud.isBillable, isTrue);
    });

    test('CostCenter.siteId round-trips + clear-Flag (H-C1)', () {
      const center = CostCenter(
        id: 'c2',
        orgId: 'org-1',
        number: '1002',
        name: 'Tabak Börse',
        siteId: 'site-77',
      );
      expect(CostCenter.fromMap(center.toMap()).siteId, 'site-77');
      expect(
        CostCenter.fromFirestore('c2', center.toFirestoreMap()).siteId,
        'site-77',
      );
      expect(center.copyWith(clearSiteId: true).siteId, isNull);
      expect(center.copyWith().siteId, 'site-77');
    });

    test('CostType round-trip + Group-Enum-Default', () {
      const type = CostType(
        orgId: 'org-1',
        number: '4100',
        name: 'Miete',
        group: CostTypeGroup.direct,
      );
      final local = CostType.fromMap(type.toMap());
      expect(local.number, '4100');
      expect(local.group, CostTypeGroup.direct);
      final cloud = CostType.fromFirestore('t1', type.toFirestoreMap());
      expect(cloud.group, CostTypeGroup.direct);

      expect(CostTypeGroupX.fromValue('activity'), CostTypeGroup.activity);
      expect(CostTypeGroupX.fromValue('quatsch'), CostTypeGroup.overhead);
    });

    test('JournalEntry round-trip + Vorzeichen-Getter', () {
      final entry = JournalEntry(
        orgId: 'org-1',
        date: DateTime(2026, 3, 15),
        costCenterId: 'c1',
        costTypeId: 't1',
        description: 'Märzmiete',
        amountCents: 250000,
        reference: 'RE-2026-042',
      );
      expect(entry.isExpense, isTrue);
      expect(entry.isCredit, isFalse);

      final local = JournalEntry.fromMap(entry.toMap());
      expect(local.amountCents, 250000);
      expect(local.date, DateTime(2026, 3, 15));
      expect(local.reference, 'RE-2026-042');

      final cloud = JournalEntry.fromFirestore('j1', entry.toFirestoreMap());
      expect(cloud.amountCents, 250000);
      expect(cloud.date, DateTime(2026, 3, 15, 12));
      expect(cloud.costCenterId, 'c1');

      final credit = entry.copyWith(amountCents: -5000);
      expect(credit.isCredit, isTrue);
      expect(credit.isExpense, isFalse);
    });

    test('Budget deterministische Doc-ID + costTypeId clear-Flag', () {
      const total = Budget(
        orgId: 'org-1',
        costCenterId: 'c1',
        year: 2026,
        plannedAmountCents: 10000000,
      );
      expect(total.documentId, 'c1-all-2026');
      expect(total.isTotalBudget, isTrue);

      const specific = Budget(
        orgId: 'org-1',
        costCenterId: 'c1',
        costTypeId: 't1',
        year: 2026,
        plannedAmountCents: 3000000,
      );
      expect(specific.documentId, 'c1-t1-2026');
      expect(specific.isTotalBudget, isFalse);

      final cleared = specific.copyWith(clearCostTypeId: true);
      expect(cleared.costTypeId, isNull);
      expect(cleared.documentId, 'c1-all-2026');

      final local = Budget.fromMap(specific.toMap());
      expect(local.costTypeId, 't1');
      expect(local.plannedAmountCents, 3000000);
      final cloud = Budget.fromFirestore('b1', specific.toFirestoreMap());
      expect(cloud.costTypeId, 't1');
      expect(cloud.year, 2026);
    });
  });

  group('FinanceAnalytics', () {
    const c1 = CostCenter(
        id: 'c1', orgId: 'o', number: '1001', name: 'Strichmännchen');
    const c2 = CostCenter(
        id: 'c2',
        orgId: 'o',
        number: '1002',
        name: 'Tabak Börse',
        annualBudgetCents: 5000000);

    JournalEntry je(String cc, int month, int amount) => JournalEntry(
          orgId: 'o',
          date: DateTime(2026, month, 10),
          costCenterId: cc,
          costTypeId: 't1',
          description: 'x',
          amountCents: amount,
        );

    final entries = [
      je('c1', 1, 300000), // Kosten
      je('c1', 2, 200000), // Kosten
      je('c1', 3, -50000), // Gutschrift
      je('c2', 1, 100000),
      je('c1', 1, 999), // anderes Jahr testen wir separat
    ];

    test('actualForCostCenter summiert signiert + jahres-/kostenstellengenau',
        () {
      // c1 2026: 300000 + 200000 - 50000 + 999 = 450999
      expect(FinanceAnalytics.actualForCostCenter(entries, 'c1', 2026), 450999);
      expect(FinanceAnalytics.actualForCostCenter(entries, 'c2', 2026), 100000);
      expect(FinanceAnalytics.actualForCostCenter(entries, 'c1', 2025), 0);
    });

    test('plannedForCostCenter: Budget-Summe, sonst annualBudget-Fallback', () {
      const budgets = [
        Budget(
            orgId: 'o',
            costCenterId: 'c1',
            year: 2026,
            plannedAmountCents: 600000),
        Budget(
            orgId: 'o',
            costCenterId: 'c1',
            costTypeId: 't1', // kostenart-spezifisch -> zählt NICHT in Plan
            year: 2026,
            plannedAmountCents: 999999),
      ];
      expect(FinanceAnalytics.plannedForCostCenter(budgets, c1, 2026), 600000);
      // c2 ohne Budget-Doc -> Fallback annualBudgetCents.
      expect(FinanceAnalytics.plannedForCostCenter(budgets, c2, 2026), 5000000);
    });

    test('explizites 0-Gesamtbudget verdrängt den annualBudget-Fallback', () {
      // c2 hat annualBudgetCents=5000000, aber ein explizites 0-Gesamtbudget.
      const budgets = [
        Budget(
            orgId: 'o',
            costCenterId: 'c2',
            year: 2026,
            plannedAmountCents: 0),
      ];
      expect(FinanceAnalytics.plannedForCostCenter(budgets, c2, 2026), 0);
      // Anderes Jahr ohne Budget -> weiterhin Fallback.
      expect(FinanceAnalytics.plannedForCostCenter(budgets, c2, 2025), 5000000);
    });

    test('costCenterReports: Auslastung, Über-Budget, Sortierung', () {
      const budgets = [
        Budget(
            orgId: 'o',
            costCenterId: 'c1',
            year: 2026,
            plannedAmountCents: 400000),
      ];
      final reports =
          FinanceAnalytics.costCenterReports([c1, c2], budgets, entries, 2026);
      // Nach Ist absteigend: c1 (450999) vor c2 (100000).
      expect(reports.first.center.id, 'c1');
      final r1 = reports.firstWhere((r) => r.center.id == 'c1');
      expect(r1.actualCents, 450999);
      expect(r1.plannedCents, 400000);
      expect(r1.isOverBudget, isTrue); // 450999 > 400000
      expect(r1.utilization, greaterThan(1.0));
      expect(r1.remainingCents, 400000 - 450999);
      expect(r1.entryCount, 4); // 4 c1-Buchungen in 2026
    });

    test('monthlyBreakdown trennt Kosten/Gutschriften je Monat', () {
      final months = FinanceAnalytics.monthlyBreakdown(entries, 2026);
      expect(months.length, 12);
      // Januar: c1 300000 + 999 + c2 100000 Kosten, keine Gutschrift.
      expect(months[0].expenseCents, 400999);
      expect(months[0].creditCents, 0);
      // März: nur Gutschrift -50000.
      expect(months[2].expenseCents, 0);
      expect(months[2].creditCents, 50000);
      expect(months[2].netCents, -50000);
    });

    test('Gesamt-KPIs (Kosten/Gutschriften/signiert/Plan)', () {
      const budgets = [
        Budget(
            orgId: 'o',
            costCenterId: 'c1',
            year: 2026,
            plannedAmountCents: 400000),
      ];
      // Kosten 2026: 300000+200000+100000+999 = 600999; Gutschrift 50000.
      expect(FinanceAnalytics.totalExpenses(entries, 2026), 600999);
      expect(FinanceAnalytics.totalCredits(entries, 2026), 50000);
      expect(FinanceAnalytics.totalActual(entries, 2026), 550999);
      // Plan: c1 600000-Budget? nein 400000; c2 Fallback 5000000.
      expect(FinanceAnalytics.totalPlanned([c1, c2], budgets, 2026),
          400000 + 5000000);
    });
  });
}
