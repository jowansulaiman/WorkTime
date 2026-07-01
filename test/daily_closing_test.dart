import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/daily_closing.dart';
import 'package:worktime_app/models/pos_receipt.dart';

/// Reine Tests für P2.0 (Tagesabschluss / Tagesumsatz mit USt-Split).
void main() {
  PosReceipt receipt({
    required String day,
    required String type,
    String siteId = 'site-1',
    int? grossCents,
    List<ReceiptTax> taxes = const [],
    List<PaymentLine> payments = const [],
    bool training = false,
  }) {
    final isRevenue = !training && (type == 'sales' || type == 'refund');
    return PosReceipt(
      orgId: 'org-1',
      siteId: siteId,
      referenceNumber: '$day-$type-${grossCents ?? 0}',
      type: type,
      isRevenue: isRevenue,
      training: training,
      businessDay: day,
      grossCents: grossCents,
      taxes: taxes,
      payments: payments,
    );
  }

  test('aggregiert Tagesumsatz mit USt-Split 19/7', () {
    final closings = computeDailyClosings([
      receipt(day: '2026-06-30', type: 'sales', grossCents: 1190, taxes: const [
        ReceiptTax(ratePercent: 19, netCents: 1000, taxCents: 190, grossCents: 1190),
      ]),
      receipt(day: '2026-06-30', type: 'sales', grossCents: 107, taxes: const [
        ReceiptTax(ratePercent: 7, netCents: 100, taxCents: 7, grossCents: 107),
      ]),
      receipt(day: '2026-06-30', type: 'sales', grossCents: 119, taxes: const [
        ReceiptTax(ratePercent: 19, netCents: 100, taxCents: 19, grossCents: 119),
      ]),
    ]);

    expect(closings, hasLength(1));
    final c = closings.single;
    expect(c.businessDay, '2026-06-30');
    expect(c.salesCount, 3);
    expect(c.revenueGrossCents, 1190 + 107 + 119);
    // Eimer absteigend nach Satz: 19 zuerst.
    expect(c.taxBuckets.first.ratePercent, 19);
    expect(c.taxBuckets.first.netCents, 1100);
    expect(c.taxBuckets.first.taxCents, 209);
    final t7 = c.taxBuckets.firstWhere((b) => b.ratePercent == 7);
    expect(t7.taxCents, 7);
  });

  test('refund zählt zum Umsatz, cash nur in Bargeld-Bewegung', () {
    final closings = computeDailyClosings([
      receipt(day: '2026-06-30', type: 'sales', grossCents: 500),
      receipt(day: '2026-06-30', type: 'refund', grossCents: -100),
      receipt(day: '2026-06-30', type: 'cash', grossCents: 20000), // Kassensturz
    ]);
    final c = closings.single;
    expect(c.salesCount, 1);
    expect(c.refundCount, 1);
    expect(c.revenueGrossCents, 400); // 500 - 100
    expect(c.cashMovementCents, 20000);
  });

  test('training-Belege bleiben außen vor', () {
    final closings = computeDailyClosings([
      receipt(day: '2026-06-30', type: 'sales', grossCents: 999, training: true),
      receipt(day: '2026-06-30', type: 'sales', grossCents: 100),
    ]);
    expect(closings.single.revenueGrossCents, 100);
    expect(closings.single.salesCount, 1);
  });

  test('trennt je Geschäftstag und Standort, sortiert Tag absteigend', () {
    final closings = computeDailyClosings([
      receipt(day: '2026-06-29', type: 'sales', grossCents: 100),
      receipt(day: '2026-06-30', type: 'sales', grossCents: 200),
      receipt(day: '2026-06-30', type: 'sales', grossCents: 50, siteId: 'site-2'),
    ]);
    expect(closings.first.businessDay, '2026-06-30'); // neuester Tag zuerst
    expect(closings.map((c) => '${c.businessDay}/${c.siteId}'),
        ['2026-06-30/site-1', '2026-06-30/site-2', '2026-06-29/site-1']);
  });

  test('aggregiert Zahlart-Split (bar/Karte) je Tag', () {
    final closings = computeDailyClosings([
      receipt(day: '2026-06-30', type: 'sales', grossCents: 500, payments: const [
        PaymentLine(method: 'bar', amountCents: 500),
      ]),
      receipt(day: '2026-06-30', type: 'sales', grossCents: 300, payments: const [
        PaymentLine(method: 'karte', amountCents: 300),
      ]),
      receipt(day: '2026-06-30', type: 'sales', grossCents: 200, payments: const [
        PaymentLine(method: 'bar', amountCents: 200),
      ]),
    ]);
    final c = closings.single;
    expect(c.paymentsByMethod['bar'], 700);
    expect(c.paymentsByMethod['karte'], 300);
  });

  test('unbekannter USt-Satz landet in eigenem Eimer', () {
    final closings = computeDailyClosings([
      receipt(day: '2026-06-30', type: 'sales', grossCents: 100, taxes: const [
        ReceiptTax(netCents: 100, taxCents: 0, grossCents: 100), // kein ratePercent
      ]),
    ]);
    expect(closings.single.taxBuckets.single.ratePercent, isNull);
  });
}
