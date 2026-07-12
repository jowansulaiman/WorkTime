import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/sales_velocity.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/stock_movement.dart';

/// Reine, deterministische Tests für den P1.1-Velocity-Core. Feste Daten
/// erlaubt (keine Wall-Clock-Abhängigkeit — `asOf`/`windowStart` injiziert).
void main() {
  Product product(
    String id, {
    int currentStock = 0,
    int? purchasePriceCents,
    String siteId = 'site-1',
    DateTime? createdAt,
  }) =>
      Product(
        id: id,
        orgId: 'org-1',
        siteId: siteId,
        name: id,
        currentStock: currentStock,
        purchasePriceCents: purchasePriceCents,
        createdAt: createdAt,
      );

  StockMovement movement({
    required String productId,
    required int quantityDelta,
    required DateTime createdAt,
    StockMovementType type = StockMovementType.issue,
    String siteId = 'site-1',
  }) =>
      StockMovement(
        orgId: 'org-1',
        siteId: siteId,
        productId: productId,
        type: type,
        quantityDelta: quantityDelta,
        createdAt: createdAt,
      );

  final asOf = DateTime(2026, 6, 30, 12);
  final windowStart = asOf.subtract(const Duration(days: 28));

  group('computeProductVelocities', () {
    test('summiert Abgänge (issue) zu Tagesabsatz und Reichweite', () {
      final result = computeProductVelocities(
        products: [product('p1', currentStock: 56, purchasePriceCents: 100)],
        movements: [
          movement(
              productId: 'p1',
              quantityDelta: -28,
              createdAt: asOf.subtract(const Duration(days: 1))),
          // Genau am Fensterstart: zählt noch UND belegt eine Datenhistorie
          // über das volle Fenster (isReliable misst echte Datentage).
          movement(
              productId: 'p1',
              quantityDelta: -28,
              createdAt: windowStart),
        ],
        windowStart: windowStart,
        asOf: asOf,
      );

      expect(result, hasLength(1));
      final v = result.single;
      expect(v.soldUnits, 56);
      expect(v.windowDays, 28);
      // 56 Einheiten / 28 Tage = 2.0/Tag; 56 Bestand / 2.0 = 28 Tage Reichweite.
      expect(v.dailyVelocity, 2.0);
      expect(v.coverageDays, 28.0);
      expect(v.isReliable, isTrue);
      expect(v.isValuated, isTrue);
      expect(v.tiedUpCapitalCents, 5600);
    });

    test('Wareneingang/Erstattung (receipt) zählt NICHT als Verkauf', () {
      final result = computeProductVelocities(
        products: [product('p1', currentStock: 10)],
        movements: [
          movement(
              productId: 'p1',
              quantityDelta: 100,
              type: StockMovementType.receipt,
              createdAt: asOf.subtract(const Duration(days: 2))),
          movement(
              productId: 'p1',
              quantityDelta: -14,
              createdAt: asOf.subtract(const Duration(days: 2))),
        ],
        windowStart: windowStart,
        asOf: asOf,
      );
      expect(result.single.soldUnits, 14);
    });

    test('kein Absatz bei Bestand ⇒ Dead-Stock, Reichweite null', () {
      final result = computeProductVelocities(
        products: [product('p1', currentStock: 40, purchasePriceCents: 250)],
        movements: const [],
        windowStart: windowStart,
        asOf: asOf,
      );
      final v = result.single;
      expect(v.soldUnits, 0);
      expect(v.dailyVelocity, 0);
      expect(v.coverageDays, isNull);
      expect(v.isDeadStock, isTrue);
      expect(v.tiedUpCapitalCents, 40 * 250);
    });

    test('Bestand <= 0 ⇒ Reichweite 0, kein Dead-Stock', () {
      final result = computeProductVelocities(
        products: [product('p1', currentStock: 0)],
        movements: [
          movement(
              productId: 'p1',
              quantityDelta: -5,
              createdAt: asOf.subtract(const Duration(days: 1))),
        ],
        windowStart: windowStart,
        asOf: asOf,
      );
      final v = result.single;
      expect(v.coverageDays, 0);
      expect(v.isDeadStock, isFalse);
    });

    test('fehlender EK ⇒ unbewertet (nicht 0)', () {
      final result = computeProductVelocities(
        products: [product('p1', currentStock: 10)],
        movements: const [],
        windowStart: windowStart,
        asOf: asOf,
      );
      final v = result.single;
      expect(v.isValuated, isFalse);
      expect(v.purchasePriceCents, isNull);
      expect(v.tiedUpCapitalCents, 0);
    });

    test('Bewegungen außerhalb des Fensters/ohne Datum werden ignoriert', () {
      final result = computeProductVelocities(
        products: [product('p1', currentStock: 100)],
        movements: [
          movement(
              productId: 'p1',
              quantityDelta: -50,
              createdAt: windowStart.subtract(const Duration(days: 1))),
          movement(productId: 'p1', quantityDelta: -7, createdAt: asOf),
        ],
        windowStart: windowStart,
        asOf: asOf,
      );
      expect(result.single.soldUnits, 7);
    });

    test('kurzes Fenster ⇒ nicht belastbar (isReliable false)', () {
      final shortStart = asOf.subtract(const Duration(days: 7));
      final result = computeProductVelocities(
        products: [product('p1', currentStock: 14)],
        movements: [
          movement(
              productId: 'p1',
              quantityDelta: -7,
              createdAt: asOf.subtract(const Duration(days: 1))),
        ],
        windowStart: shortStart,
        asOf: asOf,
      );
      final v = result.single;
      expect(v.windowDays, 7);
      expect(v.dailyVelocity, 1.0);
      expect(v.isReliable, isFalse);
    });

    test('Bewegung ohne passenden Artikel wird ignoriert', () {
      final result = computeProductVelocities(
        products: [product('p1', currentStock: 10)],
        movements: [
          movement(
              productId: 'geloescht',
              quantityDelta: -99,
              createdAt: asOf.subtract(const Duration(days: 1))),
        ],
        windowStart: windowStart,
        asOf: asOf,
      );
      expect(result.single.soldUnits, 0);
    });

    test('isReliable misst die tatsächliche Datenhistorie, '
        'nicht die angefragte Fensterlänge', () {
      // 28-Tage-Fenster, aber die früheste Bewegung ist erst 3 Tage alt —
      // wer erst seit 3 Tagen erfasst, bekommt KEIN „belastbar".
      final result = computeProductVelocities(
        products: [product('p1', currentStock: 10)],
        movements: [
          movement(
              productId: 'p1',
              quantityDelta: -6,
              createdAt: asOf.subtract(const Duration(days: 3))),
        ],
        windowStart: windowStart,
        asOf: asOf,
      );
      final v = result.single;
      expect(v.windowDays, 28);
      expect(v.effectiveDataDays, 3);
      expect(v.isReliable, isFalse);
    });

    test('injiziertes dataSince übersteuert die Ableitung aus den Bewegungen',
        () {
      // Der Aufrufer weiß es besser (Erfassung läuft seit Fensterstart, es gab
      // nur lange keinen Abgang) ⇒ volle Datenbasis, belastbar.
      final result = computeProductVelocities(
        products: [product('p1', currentStock: 10)],
        movements: [
          movement(
              productId: 'p1',
              quantityDelta: -6,
              createdAt: asOf.subtract(const Duration(days: 3))),
        ],
        windowStart: windowStart,
        asOf: asOf,
        dataSince: windowStart,
      );
      final v = result.single;
      expect(v.effectiveDataDays, 28);
      expect(v.isReliable, isTrue);
    });

    test('neuer Artikel (createdAt im Fenster) ist kein Ladenhüter '
        'und nicht belastbar', () {
      final result = computeProductVelocities(
        products: [
          // Erst vor 5 Tagen angelegt, noch kein Verkauf — zu neu für Aussage.
          product('neu',
              currentStock: 40,
              purchasePriceCents: 250,
              createdAt: asOf.subtract(const Duration(days: 5))),
          // Alt-Artikel als Kontrolle: bleibt Ladenhüter.
          product('alt',
              currentStock: 40,
              purchasePriceCents: 250,
              createdAt: asOf.subtract(const Duration(days: 90))),
        ],
        movements: const [],
        windowStart: windowStart,
        asOf: asOf,
      );

      final neu = result.firstWhere((v) => v.productId == 'neu');
      expect(neu.isNewProduct, isTrue);
      expect(neu.isDeadStock, isFalse);
      expect(neu.effectiveDataDays, 5); // eigene Lebensdauer, nicht Org-Basis
      expect(neu.isReliable, isFalse);

      final alt = result.firstWhere((v) => v.productId == 'alt');
      expect(alt.isNewProduct, isFalse);
      expect(alt.isDeadStock, isTrue);
      expect(alt.isReliable, isTrue);
    });
  });
}
