import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/dead_stock.dart';
import 'package:worktime_app/core/sales_velocity.dart';
import 'package:worktime_app/models/product.dart';

/// Reine Tests für P1.2 (standortübergreifende Umlagerungsvorschläge).
void main() {
  const windowDays = 28;

  // Baut einen Artikel + die dazu konsistente ProductVelocity (soldUnits/Fenster
  // bestimmen dailyVelocity, currentStock die Reichweite).
  ({Product product, ProductVelocity velocity}) item(
    String id, {
    required String siteId,
    required int currentStock,
    required int soldUnits,
    String? barcode,
    String? externalPosId,
    String name = 'Artikel',
    int? purchasePriceCents,
    bool isNewProduct = false,
  }) {
    final product = Product(
      id: id,
      orgId: 'org-1',
      siteId: siteId,
      name: name,
      barcode: barcode,
      externalPosId: externalPosId,
      currentStock: currentStock,
      purchasePriceCents: purchasePriceCents,
    );
    final velocity = ProductVelocity(
      productId: id,
      siteId: siteId,
      soldUnits: soldUnits,
      windowDays: windowDays,
      currentStock: currentStock,
      purchasePriceCents: purchasePriceCents,
      isNewProduct: isNewProduct,
    );
    return (product: product, velocity: velocity);
  }

  List<TransferSuggestion> run(List<({Product product, ProductVelocity velocity})> items,
      {double destinationMaxCoverageDays = 14, double targetCoverageDays = 21}) {
    return suggestCrossSiteTransfers(
      velocities: items.map((e) => e.velocity).toList(),
      products: items.map((e) => e.product).toList(),
      destinationMaxCoverageDays: destinationMaxCoverageDays,
      targetCoverageDays: targetCoverageDays,
    );
  }

  test('Ladenhüter in A → laufender, knapper Artikel in B (per Barcode)', () {
    final a = item('a', siteId: 'site-1', currentStock: 50, soldUnits: 0,
        barcode: '111', purchasePriceCents: 300);
    final b = item('b', siteId: 'site-2', currentStock: 10, soldUnits: 56,
        barcode: '111');

    final result = run([a, b]);

    expect(result, hasLength(1));
    final s = result.single;
    expect(s.fromProduct.id, 'a');
    expect(s.toProduct.id, 'b');
    // Ziel: ceil(2.0/Tag * 21) - 10 Bestand = 32; Quellbestand 50 -> 32.
    expect(s.quantity, 32);
    expect(s.matchedBy, 'barcode');
    expect(s.fromTiedUpCapitalCents, 50 * 300);
    expect(s.destinationCoverageDaysBefore, 5.0);
  });

  test('kein Match über Standorte (verschiedene Barcodes) ⇒ kein Vorschlag', () {
    final a = item('a', siteId: 'site-1', currentStock: 50, soldUnits: 0,
        barcode: '111');
    final b = item('b', siteId: 'site-2', currentStock: 1, soldUnits: 56,
        barcode: '222');
    expect(run([a, b]), isEmpty);
  });

  test('neuer Artikel (zu neu für Aussage) ⇒ keine Umlagerungs-Quelle', () {
    // Frisch angelegt, noch kein Verkauf — darf NICHT als Ladenhüter
    // weggelagert werden.
    final a = item('a', siteId: 'site-1', currentStock: 50, soldUnits: 0,
        barcode: '111', isNewProduct: true);
    final b = item('b', siteId: 'site-2', currentStock: 1, soldUnits: 56,
        barcode: '111');
    expect(run([a, b]), isEmpty);
  });

  test('Quelle hat Absatz (kein Ladenhüter) ⇒ kein Vorschlag', () {
    final a = item('a', siteId: 'site-1', currentStock: 50, soldUnits: 5,
        barcode: '111');
    final b = item('b', siteId: 'site-2', currentStock: 1, soldUnits: 56,
        barcode: '111');
    expect(run([a, b]), isEmpty);
  });

  test('Ziel ist nicht knapp (hohe Reichweite) ⇒ kein Vorschlag', () {
    final a = item('a', siteId: 'site-1', currentStock: 50, soldUnits: 0,
        barcode: '111');
    // 56/28 = 2/Tag, Bestand 200 -> Reichweite 100 Tage (>14).
    final b = item('b', siteId: 'site-2', currentStock: 200, soldUnits: 56,
        barcode: '111');
    expect(run([a, b]), isEmpty);
  });

  test('nur ein Standort führt den Artikel ⇒ kein Vorschlag', () {
    final a = item('a', siteId: 'site-1', currentStock: 50, soldUnits: 0,
        barcode: '111');
    final b = item('b', siteId: 'site-1', currentStock: 1, soldUnits: 56,
        barcode: '111');
    expect(run([a, b]), isEmpty);
  });

  test('greedy: Quellbestand geht zuerst an das dringendste Ziel', () {
    final src = item('src', siteId: 'site-1', currentStock: 20, soldUnits: 0,
        barcode: '111');
    // Ziel A: 84/28 = 3/Tag, Bestand 3 -> Reichweite 1 Tag (dringender).
    final destA = item('da', siteId: 'site-2', currentStock: 3, soldUnits: 84,
        barcode: '111');
    // Ziel B: 28/28 = 1/Tag, Bestand 2 -> Reichweite 2 Tage.
    final destB = item('db', siteId: 'site-3', currentStock: 2, soldUnits: 28,
        barcode: '111');

    final result = run([src, destA, destB]);

    // Quelle (20) fließt ganz an A (Bedarf 60) -> nichts bleibt für B.
    expect(result, hasLength(1));
    expect(result.single.toProduct.id, 'da');
    expect(result.single.quantity, 20);
  });

  test('Match-Qualität: externalPosId ohne Barcode, sonst Name', () {
    final a = item('a', siteId: 'site-1', currentStock: 50, soldUnits: 0,
        externalPosId: 'EXT-9', name: 'Feuerzeug');
    final b = item('b', siteId: 'site-2', currentStock: 5, soldUnits: 56,
        externalPosId: 'EXT-9', name: 'Feuerzeug');
    expect(run([a, b]).single.matchedBy, 'externalPosId');

    final c = item('c', siteId: 'site-1', currentStock: 50, soldUnits: 0,
        name: 'Kaugummi');
    final d = item('d', siteId: 'site-2', currentStock: 5, soldUnits: 56,
        name: 'Kaugummi');
    expect(run([c, d]).single.matchedBy, 'name');
  });

  test('Sortierung nach freigesetztem Kapital (desc)', () {
    final cheapSrc = item('cheap', siteId: 'site-1', currentStock: 10,
        soldUnits: 0, barcode: '111', purchasePriceCents: 100);
    final cheapDest = item('cheapd', siteId: 'site-2', currentStock: 1,
        soldUnits: 56, barcode: '111');
    final richSrc = item('rich', siteId: 'site-1', currentStock: 10,
        soldUnits: 0, barcode: '222', purchasePriceCents: 900);
    final richDest = item('richd', siteId: 'site-2', currentStock: 1,
        soldUnits: 56, barcode: '222');

    final result = run([cheapSrc, cheapDest, richSrc, richDest]);
    expect(result, hasLength(2));
    expect(result.first.fromProduct.id, 'rich'); // höheres Kapital zuerst
    expect(result.last.fromProduct.id, 'cheap');
  });
}
