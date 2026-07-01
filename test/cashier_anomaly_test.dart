import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/cashier_anomaly.dart';
import 'package:worktime_app/models/pos_receipt.dart';

/// Reine Tests für P3.2 (Storno-/Refund-Anomalie je Kassierer).
void main() {
  // [total] Umsatz-Belege für [cashierId], davon [refunds] Erstattungen.
  List<PosReceipt> cashier(String cashierId, int total, int refunds) {
    return List.generate(total, (i) {
      final isRefund = i < refunds;
      return PosReceipt(
        orgId: 'org-1',
        siteId: 'site-1',
        referenceNumber: '$cashierId-$i',
        type: isRefund ? 'refund' : 'sales',
        isRevenue: true,
        cashierId: cashierId,
      );
    });
  }

  test('markiert auffällige Erstattungsquote (z >= Schwelle)', () {
    final receipts = <PosReceipt>[
      for (var k = 0; k < 9; k++) ...cashier('normal$k', 50, 1), // Quote 0.02
      ...cashier('verdacht', 50, 20), // Quote 0.40
    ];
    final report = computeCashierAnomalies(
      receipts: receipts,
      minTransactions: 30,
      zThreshold: 2.0,
    );
    expect(report.flagged.map((s) => s.cashierId), ['verdacht']);
    final v = report.stats.firstWhere((s) => s.cashierId == 'verdacht');
    expect(v.zScore, greaterThan(2.0));
    expect(v.refundRate, closeTo(0.4, 1e-9));
    // ein „normaler" Kassierer ist NICHT markiert.
    expect(report.stats.firstWhere((s) => s.cashierId == 'normal0').isFlagged,
        isFalse);
  });

  test('Mindest-Fallzahl: zu wenige Vorgänge ⇒ nicht bewertet', () {
    final report = computeCashierAnomalies(
      receipts: [
        ...cashier('aktiv', 50, 5),
        ...cashier('selten', 5, 4), // hohe Quote, aber nur 5 Vorgänge
      ],
      minTransactions: 30,
    );
    expect(report.stats.map((s) => s.cashierId), ['aktiv']);
    expect(report.stats.any((s) => s.cashierId == 'selten'), isFalse);
  });

  test('weniger als 2 qualifizierte Kassierer ⇒ kein z-Wert', () {
    final report = computeCashierAnomalies(
      receipts: cashier('einzig', 50, 25),
      minTransactions: 30,
    );
    expect(report.stats.single.zScore, isNull);
    expect(report.stats.single.isFlagged, isFalse);
  });

  test('keine Streuung (gleiche Quote) ⇒ kein z-Wert, kein Alarm', () {
    final report = computeCashierAnomalies(
      receipts: [
        ...cashier('a', 50, 5),
        ...cashier('b', 50, 5),
      ],
      minTransactions: 30,
    );
    expect(report.stats.every((s) => s.zScore == null), isTrue);
    expect(report.flagged, isEmpty);
  });

  test('training/cash und Belege ohne Kassierer-ID zählen nicht', () {
    final report = computeCashierAnomalies(
      receipts: [
        ...cashier('a', 40, 2),
        ...cashier('b', 40, 2),
        // Rauschen, das ignoriert werden muss:
        const PosReceipt(
            orgId: 'org-1',
            siteId: 'site-1',
            referenceNumber: 'noid',
            type: 'refund',
            isRevenue: true), // kein cashierId
        const PosReceipt(
            orgId: 'org-1',
            siteId: 'site-1',
            referenceNumber: 'train',
            type: 'sales',
            isRevenue: false,
            training: true,
            cashierId: 'a'),
      ],
      minTransactions: 30,
    );
    expect(report.stats.firstWhere((s) => s.cashierId == 'a').totalTransactions, 40);
  });
}
