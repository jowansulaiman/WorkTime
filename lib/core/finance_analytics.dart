import '../models/finance_models.dart';

/// Plan-vs-Ist-Auswertung einer Kostenstelle für ein Jahr.
class CostCenterReport {
  const CostCenterReport({
    required this.center,
    required this.plannedCents,
    required this.actualCents,
    required this.entryCount,
  });

  final CostCenter center;
  final int plannedCents;

  /// Signierte Ist-Summe (Kosten − Gutschriften).
  final int actualCents;
  final int entryCount;

  /// Auslastung (Ist/Plan); 0, wenn kein Plan hinterlegt ist.
  double get utilization =>
      plannedCents <= 0 ? 0 : actualCents / plannedCents;

  int get remainingCents => plannedCents - actualCents;

  bool get isOverBudget => plannedCents > 0 && actualCents > plannedCents;
}

/// Ein Monatsbalken des Jahresverlaufs.
class MonthBucket {
  const MonthBucket({
    required this.month,
    required this.expenseCents,
    required this.creditCents,
  });

  final int month; // 1..12
  final int expenseCents; // Summe positiver Buchungen
  final int creditCents; // Summe der Beträge negativer Buchungen (positiv)

  int get netCents => expenseCents - creditCents;
}

/// Reine, dependency-freie Finanz-Auswertungen über dem Kosten-Journal.
///
/// **Vorzeichen-Konvention** (wie [JournalEntry]): `amountCents > 0` = Kosten,
/// `< 0` = Gutschrift. Alle Auswertungen leiten sich allein daraus ab.
class FinanceAnalytics {
  const FinanceAnalytics._();

  /// Signierte Ist-Summe einer Kostenstelle (+ optional Kostenart) im Jahr.
  static int actualForCostCenter(
    List<JournalEntry> entries,
    String costCenterId,
    int year, {
    String? costTypeId,
  }) {
    var sum = 0;
    for (final e in entries) {
      if (e.costCenterId != costCenterId) continue;
      if (e.date.year != year) continue;
      if (costTypeId != null && e.costTypeId != costTypeId) continue;
      sum += e.amountCents;
    }
    return sum;
  }

  /// Plan einer Kostenstelle: Summe der **Gesamtbudgets** (ohne Kostenart) der
  /// Kostenstelle im Jahr; ist diese 0, Fallback auf [CostCenter.annualBudgetCents].
  static int plannedForCostCenter(
    List<Budget> budgets,
    CostCenter center,
    int year,
  ) {
    var sum = 0;
    var hasTotalBudget = false;
    for (final b in budgets) {
      if (b.costCenterId != center.id) continue;
      if (b.year != year) continue;
      if (!b.isTotalBudget) continue; // kostenart-spezifische zählen hier nicht
      sum += b.plannedAmountCents;
      hasTotalBudget = true;
    }
    // Existenz, NICHT Summe entscheidet: ein explizit auf 0 gesetztes
    // Gesamtbudget muss den annualBudget-Fallback verdrängen können.
    return hasTotalBudget ? sum : center.annualBudgetCents;
  }

  /// Plan/Ist-Report je Kostenstelle (nach Auslastung absteigend sortiert).
  static List<CostCenterReport> costCenterReports(
    List<CostCenter> centers,
    List<Budget> budgets,
    List<JournalEntry> entries,
    int year,
  ) {
    final reports = <CostCenterReport>[];
    for (final center in centers) {
      final id = center.id;
      if (id == null) continue;
      final actual = actualForCostCenter(entries, id, year);
      final planned = plannedForCostCenter(budgets, center, year);
      final count = entries
          .where((e) => e.costCenterId == id && e.date.year == year)
          .length;
      reports.add(CostCenterReport(
        center: center,
        plannedCents: planned,
        actualCents: actual,
        entryCount: count,
      ));
    }
    reports.sort((a, b) => b.actualCents.compareTo(a.actualCents));
    return reports;
  }

  /// 12-Monats-Verlauf (Kosten/Gutschriften je Monat) eines Jahres.
  static List<MonthBucket> monthlyBreakdown(
    List<JournalEntry> entries,
    int year,
  ) {
    final expense = List<int>.filled(12, 0);
    final credit = List<int>.filled(12, 0);
    for (final e in entries) {
      if (e.date.year != year) continue;
      final i = e.date.month - 1;
      if (i < 0 || i > 11) continue;
      if (e.amountCents >= 0) {
        expense[i] += e.amountCents;
      } else {
        credit[i] += -e.amountCents;
      }
    }
    return [
      for (var m = 0; m < 12; m++)
        MonthBucket(
          month: m + 1,
          expenseCents: expense[m],
          creditCents: credit[m],
        ),
    ];
  }

  /// Summe der Kosten (nur positive Buchungen) im Jahr.
  static int totalExpenses(List<JournalEntry> entries, int year) {
    var sum = 0;
    for (final e in entries) {
      if (e.date.year == year && e.amountCents > 0) sum += e.amountCents;
    }
    return sum;
  }

  /// Summe der Gutschriften (Beträge negativer Buchungen, positiv) im Jahr.
  static int totalCredits(List<JournalEntry> entries, int year) {
    var sum = 0;
    for (final e in entries) {
      if (e.date.year == year && e.amountCents < 0) sum += -e.amountCents;
    }
    return sum;
  }

  /// Signiertes Gesamt-Ist (Kosten − Gutschriften) im Jahr.
  static int totalActual(List<JournalEntry> entries, int year) {
    var sum = 0;
    for (final e in entries) {
      if (e.date.year == year) sum += e.amountCents;
    }
    return sum;
  }

  /// Summe aller Kostenstellen-Pläne im Jahr.
  static int totalPlanned(
    List<CostCenter> centers,
    List<Budget> budgets,
    int year,
  ) {
    var sum = 0;
    for (final center in centers) {
      sum += plannedForCostCenter(budgets, center, year);
    }
    return sum;
  }
}
