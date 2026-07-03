import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/cash_state.dart';
import 'package:worktime_app/models/cash_count.dart';
import 'package:worktime_app/models/pos_receipt.dart';

/// Reine Tests für den rechnerischen Kassenzustand (Kassen-Modul M1, §4.2).
void main() {
  PosReceipt receipt({
    required String day,
    String type = 'sales',
    String siteId = 'site-1',
    int? grossCents,
    bool training = false,
    DateTime? transactionDate,
    List<PaymentLine> payments = const [],
  }) {
    final isRevenue = !training && (type == 'sales' || type == 'refund');
    return PosReceipt(
      orgId: 'org-1',
      siteId: siteId,
      referenceNumber: '$day-$type-${grossCents ?? 0}-${payments.length}',
      type: type,
      training: training,
      isRevenue: isRevenue,
      businessDay: day,
      transactionDate: transactionDate,
      grossCents: grossCents,
      payments: payments,
    );
  }

  CashCount count({
    required DateTime countedAt,
    int countedCents = 20000,
    String siteId = 'site-1',
  }) {
    return CashCount(
      orgId: 'org-1',
      siteId: siteId,
      businessDay: '${countedAt.year}-'
          '${countedAt.month.toString().padLeft(2, '0')}-'
          '${countedAt.day.toString().padLeft(2, '0')}',
      countedAt: countedAt,
      countedCents: countedCents,
      createdByUid: 'user-1',
    );
  }

  test('ohne Zählung: nicht verankert, kein Soll, Tageswerte trotzdem', () {
    final state = computeCashState(
      receipts: [
        receipt(day: '2026-07-01', grossCents: 500, payments: const [
          PaymentLine(method: 'bar', amountCents: 500),
        ]),
        receipt(day: '2026-07-01', type: 'cash', grossCents: -2000),
      ],
      counts: const [],
      siteId: 'site-1',
    );
    expect(state.verankert, isFalse);
    expect(state.sollCents, isNull);
    expect(state.letzteZaehlung, isNull);
    expect(state.tagesBareinnahmenCents, 500);
    expect(state.tagesCashBewegungCents, -2000);
  });

  test('Soll = Zählung + Bar-Zahlungen + cash-Belege seit Anker', () {
    final state = computeCashState(
      receipts: [
        // VOR der Zählung — zählt nicht ins Soll.
        receipt(
          day: '2026-07-01',
          grossCents: 999,
          transactionDate: DateTime(2026, 7, 1, 9, 0),
          payments: const [PaymentLine(method: 'bar', amountCents: 999)],
        ),
        // NACH der Zählung: Barverkauf, Kartenverkauf, Bar-Erstattung, Entnahme.
        receipt(
          day: '2026-07-01',
          grossCents: 700,
          transactionDate: DateTime(2026, 7, 1, 12, 0),
          payments: const [PaymentLine(method: 'bar', amountCents: 700)],
        ),
        receipt(
          day: '2026-07-01',
          grossCents: 300,
          transactionDate: DateTime(2026, 7, 1, 13, 0),
          payments: const [PaymentLine(method: 'karte', amountCents: 300)],
        ),
        receipt(
          day: '2026-07-01',
          type: 'refund',
          grossCents: -100,
          transactionDate: DateTime(2026, 7, 1, 14, 0),
          payments: const [PaymentLine(method: 'BAR ', amountCents: -100)],
        ),
        receipt(
          day: '2026-07-01',
          type: 'cash',
          grossCents: -5000,
          transactionDate: DateTime(2026, 7, 1, 15, 0),
        ),
      ],
      counts: [count(countedAt: DateTime(2026, 7, 1, 10, 0))],
      siteId: 'site-1',
    );

    expect(state.verankert, isTrue);
    // 20000 + 700 − 100 (Bar, Karte zählt nicht) − 5000 Entnahme.
    expect(state.sollCents, 20000 + 700 - 100 - 5000);
    expect(state.letzteZaehlung!.countedCents, 20000);
  });

  test('die JÜNGSTE Zählung ist der Anker', () {
    final state = computeCashState(
      receipts: [
        receipt(
          day: '2026-07-01',
          grossCents: 100,
          transactionDate: DateTime(2026, 7, 1, 18, 0),
          payments: const [PaymentLine(method: 'bar', amountCents: 100)],
        ),
      ],
      counts: [
        count(countedAt: DateTime(2026, 6, 30, 19, 0), countedCents: 11111),
        count(countedAt: DateTime(2026, 7, 1, 10, 0), countedCents: 22222),
      ],
      siteId: 'site-1',
    );
    expect(state.sollCents, 22222 + 100);
  });

  test('training-Belege zählen in KEINEM Summanden', () {
    final state = computeCashState(
      receipts: [
        receipt(
          day: '2026-07-01',
          grossCents: 500,
          training: true,
          transactionDate: DateTime(2026, 7, 1, 12, 0),
          payments: const [PaymentLine(method: 'bar', amountCents: 500)],
        ),
        receipt(
          day: '2026-07-01',
          type: 'cash',
          grossCents: 9999,
          training: true,
          transactionDate: DateTime(2026, 7, 1, 12, 30),
        ),
      ],
      counts: [count(countedAt: DateTime(2026, 7, 1, 10, 0))],
      siteId: 'site-1',
    );
    expect(state.sollCents, 20000);
    expect(state.tagesBareinnahmenCents, 0);
    expect(state.tagesCashBewegungCents, 0);
  });

  test('Beleg ohne transactionDate: nur spätere Geschäftstage zählen', () {
    final state = computeCashState(
      receipts: [
        // Gleicher Tag, keine Uhrzeit -> nicht zuordenbar, ausgelassen.
        receipt(day: '2026-07-01', grossCents: 100, payments: const [
          PaymentLine(method: 'bar', amountCents: 100),
        ]),
        // Späterer Tag -> zählt.
        receipt(day: '2026-07-02', grossCents: 200, payments: const [
          PaymentLine(method: 'cash', amountCents: 200),
        ]),
      ],
      counts: [count(countedAt: DateTime(2026, 7, 1, 10, 0))],
      siteId: 'site-1',
    );
    expect(state.sollCents, 20000 + 200);
  });

  test('siteId filtert Belege und Zählungen', () {
    final state = computeCashState(
      receipts: [
        receipt(day: '2026-07-01', grossCents: 100, siteId: 'site-2',
            payments: const [PaymentLine(method: 'bar', amountCents: 100)]),
      ],
      counts: [count(countedAt: DateTime(2026, 7, 1), siteId: 'site-2')],
      siteId: 'site-1',
    );
    expect(state.verankert, isFalse);
    expect(state.tagesBareinnahmenCents, 0);
  });

  test('businessDay-Parameter fixiert die Tageswerte', () {
    final state = computeCashState(
      receipts: [
        receipt(day: '2026-06-30', grossCents: 300, payments: const [
          PaymentLine(method: 'bar', amountCents: 300),
        ]),
        receipt(day: '2026-07-01', grossCents: 700, payments: const [
          PaymentLine(method: 'bar', amountCents: 700),
        ]),
      ],
      counts: const [],
      siteId: 'site-1',
      businessDay: '2026-06-30',
    );
    expect(state.tagesBareinnahmenCents, 300);
  });
}
