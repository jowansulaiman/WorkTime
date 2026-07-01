import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/basket_analysis.dart';
import 'package:worktime_app/models/pos_receipt.dart';

/// Reine Tests für P4.2 (Warenkorb-/Cross-Sell-Analyse).
void main() {
  PosReceipt receipt(List<String> productIds,
      {bool revenue = true, bool training = false}) {
    return PosReceipt(
      orgId: 'org-1',
      siteId: 'site-1',
      referenceNumber: productIds.join('-'),
      type: revenue ? 'sales' : 'cash',
      isRevenue: revenue,
      training: training,
      lines: [
        for (final id in productIds)
          PosReceiptLine(productId: id, name: id.toUpperCase(), quantity: 1),
      ],
    );
  }

  test('zählt häufige Paare, sortiert nach gemeinsamer Häufigkeit', () {
    final analysis = computeBasketAnalysis(
      receipts: [
        receipt(['tabak', 'feuerzeug']),
        receipt(['tabak', 'feuerzeug']),
        receipt(['tabak', 'feuerzeug']),
        receipt(['cola', 'snack']),
        receipt(['cola', 'snack']),
      ],
      minTogether: 2,
    );
    expect(analysis.receiptsConsidered, 5);
    final top = analysis.pairs.first;
    expect({top.productIdA, top.productIdB}, {'feuerzeug', 'tabak'});
    expect(top.together, 3);
    expect(analysis.pairs.length, 2); // tabak+feuerzeug, cola+snack
  });

  test('seltene Paare unter minTogether fallen raus', () {
    final analysis = computeBasketAnalysis(
      receipts: [
        receipt(['a', 'b']),
        receipt(['c', 'd']), // nur 1× zusammen
      ],
      minTogether: 2,
    );
    expect(analysis.pairs, isEmpty);
  });

  test('training/cash und Ein-Artikel-Belege erzeugen keine Paare', () {
    final analysis = computeBasketAnalysis(
      receipts: [
        receipt(['a', 'b'], training: true),
        receipt(['a', 'b'], revenue: false),
        receipt(['a']), // nur ein Artikel
        receipt(['a', 'b']),
        receipt(['a', 'b']),
      ],
      minTogether: 2,
    );
    // Nur die zwei echten sales-Belege mit 2 Artikeln zählen.
    expect(analysis.pairs.single.together, 2);
    expect(analysis.receiptsConsidered, 3); // 2× a+b, 1× nur a
  });

  test('Konfidenz und Lift werden korrekt berechnet', () {
    // a kommt in 4 Belegen, b in 2, zusammen 2 -> P(b|a)=0.5; lift=2*4/(4*2)=1.0
    final analysis = computeBasketAnalysis(
      receipts: [
        receipt(['a', 'b']),
        receipt(['a', 'b']),
        receipt(['a', 'x']),
        receipt(['a', 'y']),
      ],
      minTogether: 2,
    );
    final ab = analysis.pairs.firstWhere(
        (p) => {p.productIdA, p.productIdB}.containsAll({'a', 'b'}));
    expect(ab.together, 2);
    expect(ab.countA, 4);
    expect(ab.countB, 2);
    expect(ab.confidenceAtoB, 0.5);
    expect(ab.lift, 1.0);
  });

  test('je Beleg zählt ein Artikel nur einmal (distinct)', () {
    final analysis = computeBasketAnalysis(
      receipts: [
        receipt(['a', 'a', 'b']), // a doppelt auf dem Beleg
        receipt(['a', 'b']),
      ],
      minTogether: 1,
    );
    expect(analysis.pairs.single.together, 2);
    expect(analysis.pairs.single.countA, 2);
  });
}
