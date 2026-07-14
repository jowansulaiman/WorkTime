import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/receipt_deviation.dart';
import 'package:worktime_app/models/purchase_order.dart';

void main() {
  group('effectiveReceiptQuantity (WW-7 geteilter Clamp)', () {
    const item = PurchaseOrderItem(name: 'Cola', quantityOrdered: 10, quantityReceived: 4);
    // offen = 6

    test('klemmt auf den offenen Rest, wenn mehr geliefert als offen', () {
      expect(effectiveReceiptQuantity(const PurchaseReceiptLine(quantity: 9), item), 6);
    });

    test('untere Schranke 0 (negative/leere Menge)', () {
      expect(effectiveReceiptQuantity(const PurchaseReceiptLine(quantity: 0), item), 0);
      expect(effectiveReceiptQuantity(const PurchaseReceiptLine(quantity: -3), item), 0);
    });

    test('Teilmenge bleibt unangetastet', () {
      expect(effectiveReceiptQuantity(const PurchaseReceiptLine(quantity: 3), item), 3);
    });

    test('allowOverdelivery hebt die obere Schranke auf (nur 0 bleibt)', () {
      expect(
        effectiveReceiptQuantity(
            const PurchaseReceiptLine(quantity: 9, allowOverdelivery: true), item),
        9,
      );
      expect(
        effectiveReceiptQuantity(
            const PurchaseReceiptLine(quantity: -1, allowOverdelivery: true), item),
        0,
      );
    });

    test('voll gelieferte Position: ohne Override 0, mit Override durchgelassen', () {
      const full = PurchaseOrderItem(name: 'X', quantityOrdered: 5, quantityReceived: 5);
      expect(effectiveReceiptQuantity(const PurchaseReceiptLine(quantity: 2), full), 0);
      expect(
        effectiveReceiptQuantity(
            const PurchaseReceiptLine(quantity: 2, allowOverdelivery: true), full),
        2,
      );
    });
  });

  group('computeReceiptDeviations', () {
    PurchaseOrder order(List<PurchaseOrderItem> items) => PurchaseOrder(
          orgId: 'org-1',
          siteId: 'site-1',
          supplierId: 'sup-1',
          items: items,
        );

    test('keine Abweichung bei exakter Lieferung ohne Preisänderung', () {
      final report = computeReceiptDeviations(order([
        const PurchaseOrderItem(
            name: 'A', quantityOrdered: 5, quantityReceived: 5, unitPriceCents: 100),
      ]));
      expect(report.hasDeviations, isFalse);
      expect(report.summary, isEmpty);
      expect(report.all, hasLength(1));
    });

    test('Minderlieferung wird erkannt und gezählt', () {
      final report = computeReceiptDeviations(order([
        const PurchaseOrderItem(name: 'A', quantityOrdered: 10, quantityReceived: 7),
      ]));
      expect(report.hasDeviations, isTrue);
      expect(report.shortCount, 1);
      expect(report.overCount, 0);
      expect(report.deviations.single.quantityDelta, -3);
      expect(report.summary, '1 Minderlieferung');
    });

    test('Mehrlieferung + Preisabweichung kombiniert', () {
      final report = computeReceiptDeviations(order([
        const PurchaseOrderItem(
          name: 'B',
          quantityOrdered: 4,
          quantityReceived: 6,
          unitPriceCents: 100,
          receivedUnitPriceCents: 115,
        ),
      ]));
      final dev = report.deviations.single;
      expect(dev.isOver, isTrue);
      expect(dev.quantityDelta, 2);
      expect(dev.priceDeltaCents, 15);
      expect(dev.hasPriceDeviation, isTrue);
      expect(report.summary, contains('1 Mehrlieferung'));
      expect(report.summary, contains('1 Preisabweichung'));
    });

    test('fehlender Ist-EK ⇒ keine Preisabweichung (null-tolerant)', () {
      final report = computeReceiptDeviations(order([
        const PurchaseOrderItem(
            name: 'C', quantityOrdered: 3, quantityReceived: 3, unitPriceCents: 100),
      ]));
      expect(report.priceDeviationCount, 0);
      expect(report.hasDeviations, isFalse);
    });

    test('Summary zählt mehrere Positionen zusammen', () {
      final report = computeReceiptDeviations(order([
        const PurchaseOrderItem(name: 'A', quantityOrdered: 10, quantityReceived: 7),
        const PurchaseOrderItem(name: 'B', quantityOrdered: 5, quantityReceived: 2),
        const PurchaseOrderItem(
          name: 'C',
          quantityOrdered: 4,
          quantityReceived: 8,
          unitPriceCents: 100,
          receivedUnitPriceCents: 90,
        ),
      ]));
      expect(report.shortCount, 2);
      expect(report.overCount, 1);
      expect(report.priceDeviationCount, 1);
      expect(report.summary, '2 Minderlieferungen, 1 Mehrlieferung, 1 Preisabweichung');
    });
  });
}
