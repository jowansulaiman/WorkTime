import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/price_deviation.dart';
import 'package:worktime_app/models/pos_receipt.dart';
import 'package:worktime_app/models/product.dart';

void main() {
  Product product(String id, String name, int? sellingCents,
      {String siteId = 'site-1'}) {
    return Product(
      id: id,
      orgId: 'org-1',
      siteId: siteId,
      name: name,
      sellingPriceCents: sellingCents,
    );
  }

  PosReceipt receipt({
    required List<PosReceiptLine> lines,
    String type = 'sales',
    bool isRevenue = true,
    bool training = false,
    String siteId = 'site-1',
    DateTime? at,
  }) {
    return PosReceipt(
      orgId: 'org-1',
      siteId: siteId,
      referenceNumber: 'r-${at?.millisecondsSinceEpoch ?? 0}',
      type: type,
      isRevenue: isRevenue,
      training: training,
      transactionDate: at,
      lines: lines,
    );
  }

  PosReceiptLine line(String productId, int unitPriceCents,
      {int quantity = 1}) {
    return PosReceiptLine(
      productId: productId,
      quantity: quantity,
      unitPriceCents: unitPriceCents,
    );
  }

  test('meldet Abweichung mit dem JUENGSTEN Kassen-Preis', () {
    final deviations = computePriceDeviations(
      products: [product('p1', 'Cola', 179)],
      receipts: [
        receipt(lines: [line('p1', 199)], at: DateTime(2026, 7, 10)),
        receipt(lines: [line('p1', 189)], at: DateTime(2026, 7, 1)),
      ],
    );
    expect(deviations, hasLength(1));
    expect(deviations.single.posUnitPriceCents, 199);
    expect(deviations.single.diffCents, 20);
    expect(deviations.single.lastSoldAt, DateTime(2026, 7, 10));
    expect(deviations.single.observations, 1);
  });

  test('gleicher Preis = keine Abweichung', () {
    final deviations = computePriceDeviations(
      products: [product('p1', 'Cola', 199)],
      receipts: [
        receipt(lines: [line('p1', 199)], at: DateTime(2026, 7, 10)),
      ],
    );
    expect(deviations, isEmpty);
  });

  test('Artikel ohne App-VK: jeder Kassen-Preis ist meldenswert', () {
    final deviations = computePriceDeviations(
      products: [product('p1', 'Neuware', null)],
      receipts: [
        receipt(lines: [line('p1', 250)], at: DateTime(2026, 7, 10)),
      ],
    );
    expect(deviations, hasLength(1));
    expect(deviations.single.appPriceCents, isNull);
  });

  test('Refunds, Training und Fremd-Belege zaehlen nicht', () {
    final deviations = computePriceDeviations(
      products: [product('p1', 'Cola', 179)],
      receipts: [
        receipt(
          lines: [line('p1', 999)],
          type: 'refund',
          at: DateTime(2026, 7, 10),
        ),
        receipt(
          lines: [line('p1', 999)],
          training: true,
          isRevenue: false,
          at: DateTime(2026, 7, 10),
        ),
        // Zeile ohne Produkt-Zuordnung.
        receipt(
          lines: [const PosReceiptLine(quantity: 1, unitPriceCents: 999)],
          at: DateTime(2026, 7, 10),
        ),
      ],
    );
    expect(deviations, isEmpty);
  });

  test('siteId filtert Belege UND Artikel; sortiert nach groesster Abweichung',
      () {
    final deviations = computePriceDeviations(
      products: [
        product('p1', 'Cola', 179),
        product('p2', 'Fanta', 179),
        product('p3', 'Anderer Laden', 100, siteId: 'site-2'),
      ],
      receipts: [
        receipt(lines: [line('p1', 189)], at: DateTime(2026, 7, 10)),
        receipt(lines: [line('p2', 299)], at: DateTime(2026, 7, 10)),
        receipt(
          lines: [line('p3', 999)],
          siteId: 'site-2',
          at: DateTime(2026, 7, 10),
        ),
      ],
      siteId: 'site-1',
    );
    expect(deviations.map((d) => d.product.id), ['p2', 'p1']);
  });

  test('observations zaehlt Zeilen mit exakt dem juengsten Preis', () {
    final deviations = computePriceDeviations(
      products: [product('p1', 'Cola', 179)],
      receipts: [
        receipt(lines: [line('p1', 199)], at: DateTime(2026, 7, 10)),
        receipt(lines: [line('p1', 199)], at: DateTime(2026, 7, 9)),
        receipt(lines: [line('p1', 189)], at: DateTime(2026, 7, 8)),
      ],
    );
    expect(deviations.single.observations, 2);
  });
}
