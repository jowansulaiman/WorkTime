import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/assortment_gap.dart';
import 'package:worktime_app/core/sales_velocity.dart';
import 'package:worktime_app/models/product.dart';

/// Reine Tests für P4.1 (Listungslücken / Laden-Vergleich).
void main() {
  ({Product product, ProductVelocity velocity}) item(
    String id, {
    required String siteId,
    required int soldUnits,
    String? barcode,
    String? externalPosId,
    String name = 'Artikel',
  }) {
    final product = Product(
      id: id,
      orgId: 'org-1',
      siteId: siteId,
      name: name,
      barcode: barcode,
      externalPosId: externalPosId,
    );
    final velocity = ProductVelocity(
      productId: id,
      siteId: siteId,
      soldUnits: soldUnits,
      windowDays: 28,
      currentStock: 0,
      purchasePriceCents: null,
    );
    return (product: product, velocity: velocity);
  }

  List<ListingGap> run(
    List<({Product product, ProductVelocity velocity})> items,
    List<String> siteIds, {
    int minSoldUnits = 1,
  }) =>
      findListingGaps(
        velocities: items.map((e) => e.velocity).toList(),
        products: items.map((e) => e.product).toList(),
        siteIds: siteIds,
        minSoldUnits: minSoldUnits,
      );

  test('Renner in A, in B nicht geführt ⇒ Listungslücke für B', () {
    final a = item('a', siteId: 'site-1', soldUnits: 40, barcode: '111');
    // site-2 führt den Artikel (barcode 111) NICHT.
    final other = item('b', siteId: 'site-2', soldUnits: 5, barcode: '999');
    final gaps = run([a, other], ['site-2']);
    expect(gaps, hasLength(1));
    expect(gaps.single.sellingProduct.id, 'a');
    expect(gaps.single.missingSiteId, 'site-2');
    expect(gaps.single.soldUnits, 40);
    expect(gaps.single.matchedBy, 'barcode');
  });

  test('führt B den Artikel bereits ⇒ keine Lücke', () {
    final a = item('a', siteId: 'site-1', soldUnits: 40, barcode: '111');
    final bCarries = item('b', siteId: 'site-2', soldUnits: 0, barcode: '111');
    expect(run([a, bCarries], ['site-2']), isEmpty);
  });

  test('kein Absatz unter minSoldUnits ⇒ keine Lücke', () {
    final a = item('a', siteId: 'site-1', soldUnits: 0, barcode: '111');
    final b = item('b', siteId: 'site-2', soldUnits: 0, barcode: '999');
    expect(run([a, b], ['site-2'], minSoldUnits: 1), isEmpty);
  });

  test('bester Quell-Artikel gewinnt bei gleicher Identität', () {
    // Zwei Läden führen denselben Renner (Name-Match), site-3 nicht.
    final a = item('a', siteId: 'site-1', soldUnits: 10, name: 'Cola');
    final b = item('b', siteId: 'site-2', soldUnits: 50, name: 'Cola');
    final gaps = run([a, b], ['site-3']);
    expect(gaps, hasLength(1));
    expect(gaps.single.sellingProduct.id, 'b'); // 50 > 10
    expect(gaps.single.matchedBy, 'name');
  });

  test('sortiert nach Tagesabsatz absteigend', () {
    final fast = item('fast', siteId: 'site-1', soldUnits: 56, barcode: '1');
    final slow = item('slow', siteId: 'site-1', soldUnits: 14, barcode: '2');
    final gaps = run([fast, slow], ['site-2']);
    expect(gaps.map((g) => g.sellingProduct.id), ['fast', 'slow']);
  });
}
