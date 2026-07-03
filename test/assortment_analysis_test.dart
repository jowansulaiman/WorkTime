import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/assortment_analysis.dart';
import 'package:worktime_app/models/pos_receipt.dart';
import 'package:worktime_app/models/product.dart';

/// Reine Tests für P2.1 (Rohertrag & ABC nach Deckungsbeitrag).
void main() {
  Product product(String id, {int? ek, String? category}) => Product(
        id: id,
        orgId: 'org-1',
        siteId: 'site-1',
        name: id,
        purchasePriceCents: ek,
        category: category,
      );

  PosReceiptLine line(String pid,
          {required int qty, required int unit, int? discount, String? cat}) =>
      PosReceiptLine(
        productId: pid,
        name: pid,
        category: cat,
        quantity: qty,
        unitPriceCents: unit,
        discountCents: discount,
      );

  PosReceipt receipt(
    List<PosReceiptLine> lines, {
    bool isRevenue = true,
    bool training = false,
    String type = 'sales',
  }) =>
      PosReceipt(
        orgId: 'org-1',
        siteId: 'site-1',
        referenceNumber: 'r',
        type: type,
        isRevenue: isRevenue,
        training: training,
        lines: lines,
      );

  test('ABC nach Deckungsbeitrag (Anteil bis 80/95 %)', () {
    // Deckungsbeiträge: 800 / 100 / 50 / 30 / 20 = 1000 gesamt.
    // kumuliert davor: 0 / 80 / 90 / 95 / 98 % -> A / B / B / C / C.
    AssortmentItem byId(AssortmentAnalysis a, String id) =>
        a.items.firstWhere((i) => i.productId == id);
    final analysis = computeAssortmentAnalysis(
      receipts: [
        receipt([
          line('a1', qty: 1, unit: 900), // DB 800
          line('b1', qty: 1, unit: 200), // DB 100
          line('b2', qty: 1, unit: 150), // DB 50
          line('c1', qty: 1, unit: 130), // DB 30
          line('c2', qty: 1, unit: 120), // DB 20
        ]),
      ],
      products: [
        product('a1', ek: 100),
        product('b1', ek: 100),
        product('b2', ek: 100),
        product('c1', ek: 100),
        product('c2', ek: 100),
      ],
    );

    expect(analysis.items.first.productId, 'a1'); // höchster DB zuerst
    expect(byId(analysis, 'a1').abcClass, 'A');
    expect(byId(analysis, 'b1').abcClass, 'B');
    expect(byId(analysis, 'b2').abcClass, 'B');
    expect(byId(analysis, 'c1').abcClass, 'C');
    expect(byId(analysis, 'c2').abcClass, 'C');
    expect(analysis.totalContributionCents, 1000);
  });

  test('Umsatzriese mit Mini-Marge bleibt Deckungsbeitrags-C', () {
    // Zigaretten: Riesenumsatz, winzige Spanne. Viele margenstarke Kleinartikel
    // tragen den Deckungsbeitrag -> Zigaretten landen in C.
    final analysis = computeAssortmentAnalysis(
      receipts: [
        receipt([
          line('zig', qty: 100, unit: 720, cat: 'Tabak'), // DB 100×20 = 2000
          for (var i = 0; i < 10; i++)
            line('snack$i', qty: 50, unit: 150, cat: 'Süßware'), // je DB 5000
        ]),
      ],
      products: [
        product('zig', ek: 700),
        for (var i = 0; i < 10; i++) product('snack$i', ek: 50),
      ],
    );
    final zig = analysis.items.firstWhere((i) => i.productId == 'zig');
    expect(zig.contributionCents, 2000);
    expect(zig.abcClass, 'C'); // 2000 von 52000 -> ganz hinten
    expect(analysis.contributionByCategory['Tabak'], 2000);
    expect(analysis.contributionByCategory['Süßware'], 50000);
  });

  test('Rabatt senkt den realisierten Preis und damit den Rohertrag', () {
    final analysis = computeAssortmentAnalysis(
      receipts: [
        receipt([line('p', qty: 5, unit: 200, discount: 50)]), // real 150
      ],
      products: [product('p', ek: 100)],
    );
    final p = analysis.items.single;
    expect(p.revenueCents, 5 * 150);
    expect(p.contributionCents, 5 * (150 - 100));
  });

  test('fehlender EK ⇒ unbewertet (nicht 0), nicht in ABC/Total', () {
    final analysis = computeAssortmentAnalysis(
      receipts: [
        receipt([
          line('valued', qty: 1, unit: 100),
          line('noek', qty: 1, unit: 100),
        ]),
      ],
      products: [
        product('valued', ek: 40),
        product('noek'), // kein EK
      ],
    );
    final noek = analysis.items.firstWhere((i) => i.productId == 'noek');
    expect(noek.isValuated, isFalse);
    expect(noek.contributionCents, isNull);
    expect(noek.abcClass, '-');
    expect(noek.revenueCents, 100); // Umsatz trotzdem bekannt
    expect(analysis.unvaluatedCount, 1);
    expect(analysis.totalContributionCents, 60); // nur 'valued'
  });

  test('training/cash-Belege und Zeilen ohne Produkt zählen nicht', () {
    final analysis = computeAssortmentAnalysis(
      receipts: [
        receipt([line('p', qty: 100, unit: 999)], training: true),
        receipt([line('p', qty: 100, unit: 999)],
            isRevenue: false, type: 'cash'),
        receipt([
          const PosReceiptLine(productId: null, quantity: 5, unitPriceCents: 999),
          line('p', qty: 2, unit: 200),
        ]),
      ],
      products: [product('p', ek: 100)],
    );
    final p = analysis.items.single;
    expect(p.quantitySold, 2); // nur die echte sales-Zeile mit Produkt
    expect(p.contributionCents, 2 * 100);
  });

  test('negativer realisierter Preis (Rabatt > VK) ⇒ unbewertet, kein Schrott', () {
    final analysis = computeAssortmentAnalysis(
      receipts: [
        receipt([line('p', qty: 1, unit: 100, discount: 200)]), // realisiert -100
      ],
      products: [product('p', ek: 50)],
    );
    final p = analysis.items.single;
    expect(p.isValuated, isFalse); // negativer Preis zählt als unbekannt
    expect(p.revenueCents, 0); // kein negativer Umsatz im Aggregat
    expect(analysis.totalContributionCents, 0);
  });

  test('fehlender Verkaufspreis einer Zeile ⇒ Artikel unbewertet', () {
    final analysis = computeAssortmentAnalysis(
      receipts: [
        receipt([
          line('p', qty: 1, unit: 200),
          const PosReceiptLine(productId: 'p', quantity: 1), // kein unitPrice
        ]),
      ],
      products: [product('p', ek: 50)],
    );
    expect(analysis.items.single.isValuated, isFalse);
  });

  test('§3.4-Schalter (M6-C): Brutto-EK wird über taxRatePercent normalisiert',
      () {
    Product taxed(String id, {int? ek, int? rate}) => Product(
          id: id,
          orgId: 'org-1',
          siteId: 'site-1',
          name: id,
          purchasePriceCents: ek,
          taxRatePercent: rate,
        );
    final receipts = [
      receipt([line('a', qty: 10, unit: 200)]), // Umsatz 2000
    ];

    // Default (EK netto): DB = 2000 − 119×10 = 810.
    final netto = computeAssortmentAnalysis(
      receipts: receipts,
      products: [taxed('a', ek: 119, rate: 19)],
    );
    expect(netto.items.single.contributionCents, 2000 - 119 * 10);

    // Brutto-Schalter: EK 119 brutto → 100 netto → DB = 2000 − 100×10 = 1000.
    final brutto = computeAssortmentAnalysis(
      receipts: receipts,
      products: [taxed('a', ek: 119, rate: 19)],
      purchasePricesIncludeVat: true,
    );
    expect(brutto.items.single.contributionCents, 2000 - 100 * 10);

    // Brutto-Schalter, aber kein Steuersatz → unbewertet (kein stilles Raten).
    final ohneSatz = computeAssortmentAnalysis(
      receipts: receipts,
      products: [taxed('a', ek: 119)],
      purchasePricesIncludeVat: true,
    );
    expect(ohneSatz.items.single.isValuated, isFalse);
  });
}
