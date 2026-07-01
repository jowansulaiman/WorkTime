import 'dart:math' as math;

import '../models/product.dart';
import '../models/stock_movement.dart';

/// **P1.1 — Sell-Through & Reichweite.** Reine, deterministische Ableitung der
/// Verkaufsgeschwindigkeit (Einheiten/Tag) und Lagerreichweite (Tage) je Artikel
/// aus den Bestandsbewegungen eines Zeitfensters.
///
/// **Pure / offline-testbar** (wie `shift_slot_generator`/`compliance_service`):
/// kein Provider-State, kein `BuildContext`, keine Firestore-/Async-IO, **kein**
/// `DateTime.now()`. Fenster (`windowStart`) und Stichtag (`asOf`) werden
/// injiziert — schwere Aggregation soll der Aufrufer (Provider, perspektivisch
/// serverseitig vorverdichtet) liefern; diese Schicht rechnet nur.
///
/// **Demand-Proxy:** „verkauft" = Summe der **Abgänge** (`StockMovementType.issue`,
/// negativer `quantityDelta`) im Fenster. Das umfasst Kassenverkäufe
/// (`source == 'oktopos'`) **und** manuelle Abgänge/Schwund — bewusst, weil ein
/// Abgang aus Sicht der Reichweite Nachfrage ist. Erstattungen/Wareneingänge
/// (`receipt`) zählen **nicht** als Verkauf (würden die Velocity verfälschen).
class SalesVelocity {
  const SalesVelocity._();

  /// Fenster, ab dem die Velocity als belastbar gilt (Plan: „erst ab ~4 Wochen").
  /// Darunter ist sie ein grober Richtwert — die UI weist „Datenbasis: X Tage"
  /// aus, statt eine Scheingenauigkeit zu suggerieren.
  static const int defaultReliableDays = 28;
}

/// Abgeleitetes, **immutable** Read-Model je Artikel für einen Auswertungslauf.
class ProductVelocity {
  const ProductVelocity({
    required this.productId,
    required this.siteId,
    required this.soldUnits,
    required this.windowDays,
    required this.currentStock,
    required this.purchasePriceCents,
    this.minReliableDays = SalesVelocity.defaultReliableDays,
  });

  final String productId;
  final String siteId;

  /// Σ verkaufte/abgegangene Einheiten im Fenster (>= 0).
  final int soldUnits;

  /// Länge des Auswertungsfensters in Tagen (>= 1) = Datenbasis.
  final int windowDays;

  /// Bestand zum Stichtag (kann negativ sein, wird für Reichweite auf 0 geklemmt).
  final int currentStock;

  /// Einkaufspreis in Cent zum Stichtag; `null` ⇒ Artikel „unbewertet"
  /// (gebundenes Kapital nicht berechenbar, **nicht** als 0 ausweisen).
  final int? purchasePriceCents;

  /// Ab wie vielen Fenstertagen die Velocity als belastbar gilt.
  final int minReliableDays;

  /// Verkaufsgeschwindigkeit in Einheiten pro Tag (>= 0).
  double get dailyVelocity => soldUnits / windowDays;

  /// Lagerreichweite in Tagen: Bestand ÷ Tagesabsatz. `null`, wenn kein Absatz
  /// im Fenster (Reichweite „unendlich"/unbestimmt — als „kein Absatz" anzeigen,
  /// nicht als 0). Bestand <= 0 ⇒ 0 Tage Reichweite.
  double? get coverageDays {
    if (currentStock <= 0) return 0;
    final daily = dailyVelocity;
    if (daily <= 0) return null;
    return currentStock / daily;
  }

  /// Kein Absatz im Fenster trotz vorhandenem Bestand ⇒ Ladenhüter-Kandidat
  /// (Basis für P1.2 Dead-Stock). Saisonware nie automatisch auslisten.
  bool get isDeadStock => soldUnits == 0 && currentStock > 0;

  /// `true`, wenn der Einkaufspreis gesetzt ist (gebundenes Kapital berechenbar).
  bool get isValuated => purchasePriceCents != null;

  /// Gebundenes Kapital zum Einkaufspreis (Bestand × EK) in Cent; 0 bei
  /// fehlendem Preis oder Negativbestand.
  int get tiedUpCapitalCents =>
      (purchasePriceCents ?? 0) * (currentStock > 0 ? currentStock : 0);

  /// Datenbasis lang genug für eine belastbare Aussage.
  bool get isReliable => windowDays >= minReliableDays;
}

/// Berechnet [ProductVelocity] je übergebenem Artikel aus den
/// Bestandsbewegungen im Fenster `[windowStart, asOf]` (inklusive).
///
/// - Join über `productId` (eindeutig je Org); Bewegungen ohne passenden Artikel
///   in [products] werden ignoriert (z.B. gelöschte Artikel).
/// - Bewegungen ohne `createdAt` oder außerhalb des Fensters werden ignoriert —
///   der Aufrufer sollte bereits gefiltert liefern (Range-Query), das ist die
///   defensive Zweitprüfung.
/// - [minReliableDays] steuert die `isReliable`-Schwelle der Ergebnisse.
List<ProductVelocity> computeProductVelocities({
  required List<Product> products,
  required List<StockMovement> movements,
  required DateTime windowStart,
  required DateTime asOf,
  int minReliableDays = SalesVelocity.defaultReliableDays,
}) {
  final windowDays = math.max(1, asOf.difference(windowStart).inDays);

  final soldByProduct = <String, int>{};
  for (final m in movements) {
    if (m.type != StockMovementType.issue) continue;
    if (m.quantityDelta >= 0) continue;
    final at = m.createdAt;
    if (at == null) continue;
    if (at.isBefore(windowStart) || at.isAfter(asOf)) continue;
    soldByProduct[m.productId] =
        (soldByProduct[m.productId] ?? 0) + (-m.quantityDelta);
  }

  final result = <ProductVelocity>[];
  for (final p in products) {
    final id = p.id;
    if (id == null) continue;
    result.add(
      ProductVelocity(
        productId: id,
        siteId: p.siteId,
        soldUnits: soldByProduct[id] ?? 0,
        windowDays: windowDays,
        currentStock: p.currentStock,
        purchasePriceCents: p.purchasePriceCents,
        minReliableDays: minReliableDays,
      ),
    );
  }
  return result;
}
