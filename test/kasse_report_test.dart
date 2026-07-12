import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/kasse_report.dart';
import 'package:worktime_app/models/pos_daily_stat.dart';
import 'package:worktime_app/models/pos_receipt.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/purchase_order.dart';

/// Reine Tests für die Kassenbericht-Engine (Kassen-Modul M1, Plan §4.1/§8).
/// Feste Daten sind erlaubt — alle Referenzdaten explizit.
void main() {
  PosDailyStat stat({
    required String day,
    String siteId = 'site-1',
    int sales = 1,
    int refunds = 0,
    int gross = 0,
    int net = 0,
    int netUncovered = 0,
    int? cogs,
    int cogsCoveredGross = 0,
  }) {
    return PosDailyStat(
      orgId: 'org-1',
      siteId: siteId,
      businessDay: day,
      salesCount: sales,
      refundCount: refunds,
      revenueGrossCents: gross,
      revenueNetCents: net,
      netUncoveredGrossCents: netUncovered,
      cogsCents: cogs,
      cogsCoveredGrossCents: cogsCoveredGross,
    );
  }

  PurchaseOrder order({
    required DateTime? orderedAt,
    DateTime? createdAt,
    String siteId = 'site-1',
    PurchaseOrderStatus status = PurchaseOrderStatus.ordered,
    int unitPriceCents = 100,
    int quantity = 3,
    int? taxRatePercent,
  }) {
    return PurchaseOrder(
      orgId: 'org-1',
      siteId: siteId,
      supplierId: 'sup-1',
      status: status,
      orderedAt: orderedAt,
      createdAt: createdAt,
      items: [
        PurchaseOrderItem(
          name: 'Testartikel',
          quantityOrdered: quantity,
          unitPriceCents: unitPriceCents,
          taxRatePercent: taxRatePercent,
        ),
      ],
    );
  }

  // Mittwoch, 2026-07-01 liegt in der ISO-Woche mit Montag 2026-06-29.
  final now = DateTime(2026, 7, 1, 14, 30);

  group('computeKassenbericht', () {
    test('bucketet Wochen (ISO, Montag) und summiert Umsatz', () {
      final result = computeKassenbericht(
        stats: [
          stat(day: '2026-06-29', gross: 1000, net: 840), // diese Woche
          stat(day: '2026-07-01', gross: 500, net: 420), // diese Woche
          stat(day: '2026-06-28', gross: 300, net: 252), // Vorwoche (Sonntag)
        ],
        orders: const [],
        granularity: ReportGranularity.week,
        now: now,
        bucketCount: 2,
      );

      expect(result, hasLength(2));
      expect(result.first.start, DateTime(2026, 6, 22)); // älteste zuerst
      expect(result.first.umsatzBruttoCents, 300);
      expect(result.last.start, DateTime(2026, 6, 29));
      expect(result.last.umsatzBruttoCents, 1500);
      expect(result.last.umsatzNettoCents, 1260);
      expect(result.last.belege, 2);
      expect(result.last.hatDaten, isTrue);
    });

    test('Periode ohne Kassen-Tage: hatDaten=false statt stiller 0', () {
      final result = computeKassenbericht(
        stats: [stat(day: '2026-07-01', gross: 100, net: 84)],
        orders: const [],
        granularity: ReportGranularity.week,
        now: now,
        bucketCount: 2,
      );
      expect(result.first.hatDaten, isFalse);
      expect(result.last.hatDaten, isTrue);
    });

    test('Käufe: orderedAt ?? createdAt, ohne Entwurf/Storno', () {
      final result = computeKassenbericht(
        stats: [stat(day: '2026-07-01', gross: 1)],
        orders: [
          order(orderedAt: DateTime(2026, 6, 30)), // 3×100 = 300
          order(
            orderedAt: null,
            createdAt: DateTime(2026, 7, 1),
            unitPriceCents: 50,
          ), // Fallback createdAt, 150
          order(
            orderedAt: DateTime(2026, 6, 30),
            status: PurchaseOrderStatus.draft,
          ),
          order(
            orderedAt: DateTime(2026, 6, 30),
            status: PurchaseOrderStatus.cancelled,
          ),
        ],
        granularity: ReportGranularity.week,
        now: now,
        bucketCount: 1,
      );
      expect(result.single.kaeufeNettoCents, 300 + 150);
    });

    test('Käufe netto/brutto (M6-B): USt-Satz je Bestellung', () {
      final result = computeKassenbericht(
        stats: [stat(day: '2026-07-01', gross: 1)],
        orders: [
          // 3×100 netto = 300, mit 19% → 357 brutto.
          order(orderedAt: DateTime(2026, 6, 30), taxRatePercent: 19),
          // 3×100 netto = 300, ohne Satz → brutto = netto.
          order(orderedAt: DateTime(2026, 6, 30)),
        ],
        granularity: ReportGranularity.week,
        now: now,
        bucketCount: 1,
      );
      expect(result.single.kaeufeNettoCents, 600);
      expect(result.single.kaeufeBruttoCents, 357 + 300);
    });

    test('Käufe: Brutto-Schalter rechnet netto aus dem Preis heraus (§3.4)', () {
      final orders = [
        order(orderedAt: DateTime(2026, 6, 30), taxRatePercent: 19),
      ];
      // Preis 3×100=300 gilt als BRUTTO → netto = 300/1,19 = 252, brutto = 300.
      final result = computeKassenbericht(
        stats: [stat(day: '2026-07-01', gross: 1)],
        orders: orders,
        granularity: ReportGranularity.week,
        now: now,
        bucketCount: 1,
        purchasePricesIncludeVat: true,
      );
      expect(result.single.kaeufeBruttoCents, 300);
      expect(result.single.kaeufeNettoCents, 252); // 300/1,19 gerundet
    });

    test('Rohertrag netto/brutto aus Wareneinsatz; null ohne Bewertung', () {
      final result = computeKassenbericht(
        stats: [
          stat(day: '2026-06-29', gross: 1190, net: 1000, cogs: 600,
              cogsCoveredGross: 1190),
          stat(day: '2026-06-30', gross: 500, net: 420, cogs: null),
        ],
        orders: const [],
        granularity: ReportGranularity.week,
        now: now,
        bucketCount: 1,
      );
      final p = result.single;
      expect(p.wareneinsatzCents, 600);
      expect(p.rohertragNettoCents, 1420 - 600);
      expect(p.rohertragBruttoCents, 1690 - 600);
      expect(p.wareneinsatzAbdeckungPct, closeTo(1190 / 1690 * 100, 0.01));
      expect(p.nettoUnsicherCents, 0);
    });

    test('Wareneinsatz null, wenn KEIN Tag bewertbar war', () {
      final result = computeKassenbericht(
        stats: [stat(day: '2026-07-01', gross: 500, net: 420)],
        orders: const [],
        granularity: ReportGranularity.week,
        now: now,
        bucketCount: 1,
      );
      expect(result.single.wareneinsatzCents, isNull);
      expect(result.single.rohertragNettoCents, isNull);
    });

    test('Δ Vorperiode auf Umsatz brutto; erste Periode ohne Basis = null', () {
      final result = computeKassenbericht(
        stats: [
          stat(day: '2026-06-24', gross: 1000), // Woche 22.06.
          stat(day: '2026-07-01', gross: 1500), // Woche 29.06.
        ],
        orders: const [],
        granularity: ReportGranularity.week,
        now: now,
        bucketCount: 2,
      );
      expect(result.first.deltaVorperiodePct, isNull); // 15.06. nicht geladen
      expect(result.last.deltaVorperiodePct, closeTo(50, 0.001));
    });

    test('Δ Vorjahr (Woche): 364 Tage zurück, sonst null', () {
      final result = computeKassenbericht(
        stats: [
          stat(day: '2026-07-01', gross: 1200),
          // 364 Tage vor Montag 2026-06-29 ist Montag 2025-06-30.
          stat(day: '2025-07-02', gross: 1000),
        ],
        orders: const [],
        granularity: ReportGranularity.week,
        now: now,
        bucketCount: 1,
      );
      expect(result.single.deltaVorjahrPct, closeTo(20, 0.001));

      final ohneVorjahr = computeKassenbericht(
        stats: [stat(day: '2026-07-01', gross: 1200)],
        orders: const [],
        granularity: ReportGranularity.week,
        now: now,
        bucketCount: 1,
      );
      expect(ohneVorjahr.single.deltaVorjahrPct, isNull);
    });

    test('Monats- und Jahres-Granularität ordnen kalendarisch zu', () {
      final monate = computeKassenbericht(
        stats: [
          stat(day: '2026-06-15', gross: 700),
          stat(day: '2026-07-01', gross: 300),
          stat(day: '2025-07-10', gross: 100), // Vorjahres-Monat
        ],
        orders: const [],
        granularity: ReportGranularity.month,
        now: now,
        bucketCount: 2,
      );
      expect(monate.first.start, DateTime(2026, 6, 1));
      expect(monate.first.umsatzBruttoCents, 700);
      expect(monate.last.umsatzBruttoCents, 300);
      expect(monate.last.deltaVorjahrPct, closeTo(200, 0.001));

      final jahre = computeKassenbericht(
        stats: [
          stat(day: '2025-03-01', gross: 400),
          stat(day: '2026-07-01', gross: 600),
        ],
        orders: const [],
        granularity: ReportGranularity.year,
        now: now,
        bucketCount: 3,
      );
      expect(jahre, hasLength(3));
      expect(jahre[0].start, DateTime(2024, 1, 1));
      expect(jahre[0].hatDaten, isFalse);
      expect(jahre[1].umsatzBruttoCents, 400);
      expect(jahre[2].umsatzBruttoCents, 600);
      expect(jahre[2].deltaVorjahrPct, closeTo(50, 0.001));
    });

    test('coverageFrom: abgeschnittene Vergleichsperioden liefern null-Δ', () {
      final result = computeKassenbericht(
        stats: [
          stat(day: '2026-06-24', gross: 1000), // Woche 22.06.
          stat(day: '2026-07-01', gross: 1500), // Woche 29.06.
        ],
        orders: const [],
        granularity: ReportGranularity.week,
        now: now,
        bucketCount: 2,
        // Fenster beginnt MITTEN in der Vorwoche -> deren Wert wäre ein
        // Randstummel, kein Vergleich.
        coverageFrom: DateTime(2026, 6, 24),
      );
      expect(result.last.deltaVorperiodePct, isNull);
    });

    test('negative Vergleichsbasis (refund-lastig) liefert null-Δ', () {
      final result = computeKassenbericht(
        stats: [
          stat(day: '2026-06-24', gross: -500),
          stat(day: '2026-07-01', gross: 1500),
        ],
        orders: const [],
        granularity: ReportGranularity.week,
        now: now,
        bucketCount: 2,
      );
      expect(result.last.deltaVorperiodePct, isNull);
    });

    test('siteId filtert Stats und Bestellungen', () {
      final result = computeKassenbericht(
        stats: [
          stat(day: '2026-07-01', gross: 100, siteId: 'site-1'),
          stat(day: '2026-07-01', gross: 900, siteId: 'site-2'),
        ],
        orders: [
          order(orderedAt: DateTime(2026, 7, 1), siteId: 'site-2'),
        ],
        granularity: ReportGranularity.week,
        now: now,
        bucketCount: 1,
        siteId: 'site-1',
      );
      expect(result.single.umsatzBruttoCents, 100);
      expect(result.single.kaeufeNettoCents, 0);
    });
  });

  group('dailyStatsFromReceipts (Übergangs-Adapter)', () {
    PosReceipt receipt({
      required String day,
      String type = 'sales',
      String siteId = 'site-1',
      int? grossCents,
      bool training = false,
      List<ReceiptTax> taxes = const [],
      List<PaymentLine> payments = const [],
      List<PosReceiptLine> lines = const [],
    }) {
      final isRevenue = !training && (type == 'sales' || type == 'refund');
      return PosReceipt(
        orgId: 'org-1',
        siteId: siteId,
        referenceNumber: '$day-$type-${grossCents ?? 0}',
        type: type,
        training: training,
        isRevenue: isRevenue,
        businessDay: day,
        grossCents: grossCents,
        taxes: taxes,
        payments: payments,
        lines: lines,
      );
    }

    Product product({required String id, int? ek, int? taxRatePercent}) {
      return Product(
        id: id,
        orgId: 'org-1',
        siteId: 'site-1',
        name: 'P-$id',
        purchasePriceCents: ek,
        taxRatePercent: taxRatePercent,
      );
    }

    test('aggregiert Tag: brutto, netto, unsicher, Zahlarten, cash', () {
      final stats = dailyStatsFromReceipts(
        [
          receipt(day: '2026-06-30', grossCents: 1190, taxes: const [
            ReceiptTax(
                ratePercent: 19, netCents: 1000, taxCents: 190, grossCents: 1190),
          ], payments: const [
            PaymentLine(method: 'bar', amountCents: 1190),
          ]),
          receipt(day: '2026-06-30', grossCents: 500), // keine Steuerzeilen
          receipt(day: '2026-06-30', type: 'cash', grossCents: -2000),
          receipt(day: '2026-06-30', grossCents: 999, training: true),
        ],
        const [],
        purchasePricesIncludeVat: false,
      );

      final s = stats.single;
      expect(s.businessDay, '2026-06-30');
      expect(s.salesCount, 2);
      expect(s.revenueGrossCents, 1690);
      expect(s.revenueNetCents, 1000);
      expect(s.netUncoveredGrossCents, 500);
      expect(s.paymentsByMethod['bar'], 1190);
      expect(s.cashMovementCents, -2000);
      expect(s.taxes.single.ratePercent, 19);
    });

    test('COGS mit Netto-EK; Zeile ohne EK drückt nur die Abdeckung', () {
      final stats = dailyStatsFromReceipts(
        [
          receipt(day: '2026-06-30', grossCents: 900, lines: const [
            PosReceiptLine(productId: 'a', quantity: 2, unitPriceCents: 300),
            PosReceiptLine(productId: 'b', quantity: 1, unitPriceCents: 300),
          ]),
        ],
        [product(id: 'a', ek: 100)], // b hat keinen EK
        purchasePricesIncludeVat: false,
      );
      final s = stats.single;
      expect(s.cogsCents, 200); // nur Artikel a: 2×100
      expect(s.cogsCoveredGrossCents, 600); // 2×300
    });

    test('Refund senkt COGS auch bei positiver Rohmenge (M8, JS-Spiegel)', () {
      final stats = dailyStatsFromReceipts(
        [
          receipt(day: '2026-06-30', grossCents: 900, lines: const [
            PosReceiptLine(productId: 'a', quantity: 3, unitPriceCents: 300),
          ]),
          // OktoPOS liefert die Erstattungsmenge i.d.R. POSITIV.
          receipt(day: '2026-06-30', type: 'refund', grossCents: -300,
              lines: const [
                PosReceiptLine(productId: 'a', quantity: 1, unitPriceCents: 300),
              ]),
        ],
        [product(id: 'a', ek: 100)],
        purchasePricesIncludeVat: false,
      );
      final s = stats.single;
      expect(s.cogsCents, 200,
          reason: '3x Verkauf (300) minus 1x Erstattung (100) — frueher stieg '
              'der Wareneinsatz bei Refunds faelschlich auf 400');
      expect(s.cogsCoveredGrossCents, 600); // 900 - 300
    });

    test('Brutto-Schalter normalisiert EK über taxRatePercent', () {
      final stats = dailyStatsFromReceipts(
        [
          receipt(day: '2026-06-30', grossCents: 500, lines: const [
            PosReceiptLine(productId: 'a', quantity: 1, unitPriceCents: 500),
            PosReceiptLine(productId: 'c', quantity: 1, unitPriceCents: 100),
          ]),
        ],
        [
          product(id: 'a', ek: 119, taxRatePercent: 19), // netto 100
          product(id: 'c', ek: 50), // kein Satz -> unbewertet bei brutto
        ],
        purchasePricesIncludeVat: true,
      );
      final s = stats.single;
      expect(s.cogsCents, 100);
      expect(s.cogsCoveredGrossCents, 500); // nur Zeile a bewertet
    });

    test('kein einziger bewertbarer Posten -> cogsCents null', () {
      final stats = dailyStatsFromReceipts(
        [
          receipt(day: '2026-06-30', grossCents: 100, lines: const [
            PosReceiptLine(productId: 'x', quantity: 1, unitPriceCents: 100),
          ]),
        ],
        const [],
        purchasePricesIncludeVat: false,
      );
      expect(stats.single.cogsCents, isNull);
    });

    test('positive Erstattungen werden als Vorzeichen-Verdacht gezählt (A8)',
        () {
      final stats = dailyStatsFromReceipts(
        [
          receipt(day: '2026-06-30', type: 'refund', grossCents: 300),
          receipt(day: '2026-06-30', type: 'refund', grossCents: -100),
          receipt(day: '2026-06-30', grossCents: 1000),
        ],
        const [],
        purchasePricesIncludeVat: false,
      );
      expect(stats.single.refundCount, 2);
      expect(stats.single.positiveRefundCount, 1);

      final bericht = computeKassenbericht(
        stats: stats,
        orders: const [],
        granularity: ReportGranularity.week,
        now: DateTime(2026, 7, 1, 12),
        bucketCount: 1,
      );
      expect(bericht.single.positiveErstattungen, 1);
    });

    test('Tages-Fallback aus transactionDate, wie computeDailyClosings', () {
      final r = PosReceipt(
        orgId: 'org-1',
        siteId: 'site-1',
        referenceNumber: 'r1',
        type: 'sales',
        isRevenue: true,
        transactionDate: DateTime(2026, 6, 30, 18, 45),
        grossCents: 100,
      );
      final stats =
          dailyStatsFromReceipts([r], const [], purchasePricesIncludeVat: false);
      expect(stats.single.businessDay, '2026-06-30');
    });
  });
}
