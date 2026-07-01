import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/shrinkage_report.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/stock_movement.dart';

/// Reine Tests für P2.2 (Schwund-/Inventurdifferenz-Report).
void main() {
  Product product(String id, {int? ek, String? category}) => Product(
        id: id,
        orgId: 'org-1',
        siteId: 'site-1',
        name: id,
        purchasePriceCents: ek,
        category: category,
      );

  StockMovement move(
    String productId,
    int delta,
    StockMovementType type,
  ) =>
      StockMovement(
        orgId: 'org-1',
        siteId: 'site-1',
        productId: productId,
        type: type,
        quantityDelta: delta,
      );

  test('Inventur-Fehlbestand wird zu €-Schwund (EK-bewertet)', () {
    final report = computeShrinkageReport(
      movements: [
        move('zig', -5, StockMovementType.stocktake), // 5 fehlen
      ],
      products: [product('zig', ek: 600, category: 'Tabak')],
    );
    final item = report.items.single;
    expect(item.netUnits, -5);
    expect(item.netValueCents, -3000); // -5 × 600
    expect(report.shrinkageValueCents, 3000);
    expect(report.surplusValueCents, 0);
    expect(report.netValueCents, -3000);
    expect(report.netValueByCategory['Tabak'], -3000);
  });

  test('Verkäufe/Wareneingänge/Umlagerungen zählen NICHT als Differenz', () {
    final report = computeShrinkageReport(
      movements: [
        move('p', -100, StockMovementType.issue), // Verkauf
        move('p', 100, StockMovementType.receipt), // Wareneingang
        move('p', -10, StockMovementType.transfer), // Umlagerung
        move('p', -2, StockMovementType.adjustment), // zählt
      ],
      products: [product('p', ek: 50)],
    );
    expect(report.items.single.netUnits, -2);
    expect(report.shrinkageValueCents, 100); // nur die adjustment-Buchung
  });

  test('Überbestand erhöht surplus, nicht shrinkage', () {
    final report = computeShrinkageReport(
      movements: [move('p', 3, StockMovementType.stocktake)],
      products: [product('p', ek: 100)],
    );
    expect(report.surplusValueCents, 300);
    expect(report.shrinkageValueCents, 0);
    expect(report.netValueCents, 300);
  });

  test('fehlender EK ⇒ unbewertet, nicht in €-Summen', () {
    final report = computeShrinkageReport(
      movements: [
        move('noek', -9, StockMovementType.stocktake),
        move('valued', -1, StockMovementType.stocktake),
      ],
      products: [product('noek'), product('valued', ek: 100)],
    );
    final noek = report.items.firstWhere((i) => i.productId == 'noek');
    expect(noek.isValuated, isFalse);
    expect(noek.netValueCents, isNull);
    expect(noek.netUnits, -9); // Menge trotzdem bekannt
    expect(report.unvaluatedCount, 1);
    expect(report.shrinkageValueCents, 100); // nur 'valued'
  });

  test('größter Verlust steht zuerst, unbewertete am Ende', () {
    final report = computeShrinkageReport(
      movements: [
        move('small', -1, StockMovementType.stocktake), // -100
        move('big', -10, StockMovementType.stocktake), // -1000
        move('noek', -50, StockMovementType.stocktake),
      ],
      products: [
        product('small', ek: 100),
        product('big', ek: 100),
        product('noek'),
      ],
    );
    expect(report.items.first.productId, 'big');
    expect(report.items.last.productId, 'noek'); // unbewertet ganz hinten
  });
}
