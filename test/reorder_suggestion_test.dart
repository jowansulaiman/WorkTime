import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/reorder_suggestion.dart';
import 'package:worktime_app/core/sales_velocity.dart';
import 'package:worktime_app/models/product.dart';

/// Reine Tests für P1.3 (datengetriebener Meldebestand/Zielbestand).
void main() {
  const windowDays = 28;

  Product product(
    String id, {
    String siteId = 'site-1',
    String? supplierId,
    int minStock = 0,
    int targetStock = 0,
  }) =>
      Product(
        id: id,
        orgId: 'org-1',
        siteId: siteId,
        name: id,
        supplierId: supplierId,
        minStock: minStock,
        targetStock: targetStock,
      );

  ProductVelocity velocity(
    String id, {
    required int soldUnits,
    int currentStock = 0,
    int windowDaysOverride = windowDays,
    String siteId = 'site-1',
    bool isNewProduct = false,
  }) =>
      ProductVelocity(
        productId: id,
        siteId: siteId,
        soldUnits: soldUnits,
        windowDays: windowDaysOverride,
        currentStock: currentStock,
        purchasePriceCents: null,
        isNewProduct: isNewProduct,
      );

  test('Renner: höhere Schwellen aus Tagesabsatz × (Lieferzeit + Sicherheit)', () {
    // 56/28 = 2/Tag; Lieferant lead=4, safety=3 -> min = ceil(2*7)=14.
    // coverage=14 -> target = 14 + ceil(2*14)=14+28 = 42.
    final result = computeReorderSuggestions(
      velocities: [velocity('p1', soldUnits: 56)],
      products: [product('p1', supplierId: 'sup-1', minStock: 5, targetStock: 8)],
      leadTimeDaysBySupplierId: const {'sup-1': 4},
      safetyDays: 3,
      coverageDays: 14,
    );
    final s = result.single;
    expect(s.leadTimeDays, 4);
    expect(s.suggestedMinStock, 14);
    expect(s.suggestedTargetStock, 42);
    expect(s.minStockChanged, isTrue);
    expect(s.isReliable, isTrue);
  });

  test('Langsamdreher: niedrige Schwellen', () {
    // 7/28 = 0.25/Tag; lead 3 (default), safety 3 -> min=ceil(0.25*6)=2.
    // coverage 14 -> +ceil(0.25*14)=4 -> target 6.
    final result = computeReorderSuggestions(
      velocities: [velocity('p1', soldUnits: 7)],
      products: [product('p1')],
      defaultLeadTimeDays: 3,
      safetyDays: 3,
      coverageDays: 14,
    );
    final s = result.single;
    expect(s.leadTimeDays, 3);
    expect(s.suggestedMinStock, 2);
    expect(s.suggestedTargetStock, 6);
  });

  test('Ladenhüter (kein Absatz): Schwellen 0 (nicht nachbestellen)', () {
    final result = computeReorderSuggestions(
      velocities: [velocity('p1', soldUnits: 0)],
      products: [product('p1', minStock: 10, targetStock: 20)],
    );
    final s = result.single;
    expect(s.suggestedMinStock, 0);
    expect(s.suggestedTargetStock, 0);
    expect(s.minStockChanged, isTrue); // von 10 auf 0
    expect(s.targetStockChanged, isTrue);
  });

  test('Neu-Artikel ohne Absatz: KEIN Schwellen-0-Vorschlag (zu neu für Aussage)',
      () {
    final result = computeReorderSuggestions(
      velocities: [velocity('p1', soldUnits: 0, isNewProduct: true)],
      products: [product('p1', minStock: 10, targetStock: 20)],
    );
    // Frisch angelegter Artikel darf nicht sofort auf „nicht nachbestellen"
    // gestellt werden — gar kein Vorschlag.
    expect(result, isEmpty);
  });

  test('Neu-Artikel MIT Absatz bekommt weiterhin einen Vorschlag', () {
    // 28/28 = 1/Tag, default lead 3 + safety 3 -> min=6; coverage 14 -> target 20.
    final result = computeReorderSuggestions(
      velocities: [velocity('p1', soldUnits: 28, isNewProduct: true)],
      products: [product('p1')],
    );
    expect(result.single.suggestedMinStock, 6);
    expect(result.single.suggestedTargetStock, 20);
  });

  test('Lieferzeit kommt vom Lieferanten, sonst Default', () {
    final result = computeReorderSuggestions(
      velocities: [
        velocity('p1', soldUnits: 28), // 1/Tag
        velocity('p2', soldUnits: 28),
      ],
      products: [
        product('p1', supplierId: 'slow'),
        product('p2'), // kein Lieferant -> Default
      ],
      leadTimeDaysBySupplierId: const {'slow': 10},
      defaultLeadTimeDays: 2,
      safetyDays: 0,
      coverageDays: 0,
    );
    final p1 = result.firstWhere((r) => r.productId == 'p1');
    final p2 = result.firstWhere((r) => r.productId == 'p2');
    expect(p1.suggestedMinStock, 10); // 1/Tag * 10
    expect(p2.suggestedMinStock, 2); // Default 2
  });

  test('kurzes Fenster ⇒ Vorschlag, aber als unzuverlässig markiert', () {
    final result = computeReorderSuggestions(
      velocities: [velocity('p1', soldUnits: 7, windowDaysOverride: 7)],
      products: [product('p1')],
    );
    expect(result.single.isReliable, isFalse);
  });

  test('keine Änderung, wenn Vorschlag == aktuelle Schwellen', () {
    // 28/28=1/Tag, default lead 3, safety 3 -> min=6; coverage 14 -> target 6+14=20.
    final result = computeReorderSuggestions(
      velocities: [velocity('p1', soldUnits: 28)],
      products: [product('p1', minStock: 6, targetStock: 20)],
    );
    expect(result.single.hasChange, isFalse);
  });

  test('unterwegs-Menge senkt nur die konkrete Nachbestellmenge', () {
    final result = computeReorderSuggestions(
      velocities: [velocity('p1', soldUnits: 28, currentStock: 5)],
      products: [product('p1', minStock: 6, targetStock: 20)],
      incomingByProductId: const {'p1': 7},
    );

    final suggestion = result.single;
    expect(suggestion.currentStock, 5);
    expect(suggestion.incomingQuantity, 7);
    expect(suggestion.suggestedMinStock, 6);
    expect(suggestion.suggestedTargetStock, 20);
    expect(suggestion.suggestedOrderQuantity, 8);
  });

  test(
    'konkrete Nachbestellmenge wird bei ausreichendem Zulauf auf 0 gekappt',
    () {
      final result = computeReorderSuggestions(
        velocities: [velocity('p1', soldUnits: 28, currentStock: 5)],
        products: [product('p1')],
        incomingByProductId: const {'p1': 99},
      );

      expect(result.single.incomingQuantity, 99);
      expect(result.single.suggestedOrderQuantity, 0);
    },
  );

  test('negative injizierte unterwegs-Mengen werden als 0 behandelt', () {
    final result = computeReorderSuggestions(
      velocities: [velocity('p1', soldUnits: 28, currentStock: 5)],
      products: [product('p1')],
      incomingByProductId: const {'p1': -7},
    );

    expect(result.single.incomingQuantity, 0);
    expect(result.single.suggestedOrderQuantity, 15);
  });
}
