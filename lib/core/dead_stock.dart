import 'dart:math' as math;

import '../models/product.dart';
import 'product_identity.dart';
import 'sales_velocity.dart';

/// **P1.2 — Ladenhüter & standortübergreifende Umlagerung A↔B.** Reine,
/// deterministische Heuristik (kein State/IO/`now()`/Zufall) — baut auf den
/// [ProductVelocity]-Read-Models aus [computeProductVelocities] auf.
///
/// Regalplatz ist die knappste Ressource: ein Artikel, der in Laden A liegt
/// (Bestand > 0, **kein** Absatz im Fenster) und in Laden B **läuft und knapp
/// wird**, ist in A totes Kapital und in B verlorener Umsatz. Eine Umlagerung
/// löst beides ohne Einkauf.

/// Ein konkreter Umlagerungsvorschlag: [quantity] Einheiten von [fromProduct]
/// (Ladenhüter-Quelle) zu [toProduct] (laufender, knapper Zielartikel im anderen
/// Laden). Anwenden später paarweise über `StockMovementType.transfer`.
class TransferSuggestion {
  const TransferSuggestion({
    required this.fromProduct,
    required this.toProduct,
    required this.quantity,
    required this.matchedBy,
    required this.fromTiedUpCapitalCents,
    required this.destinationCoverageDaysBefore,
  });

  /// Quelle (Ladenhüter, Bestand > 0, kein Absatz im Fenster).
  final Product fromProduct;

  /// Ziel (anderer Standort, Absatz > 0, knappe Reichweite).
  final Product toProduct;

  /// Vorgeschlagene Umlagerungsmenge (>= 1, <= Quellbestand).
  final int quantity;

  /// Wie die beiden Artikel verknüpft wurden: `barcode` (sicher) >
  /// `externalPosId` > `name` (schwächste, in der UI als Qualität ausweisen).
  final String matchedBy;

  /// Totes Kapital der Quelle zum EK (Anzeige/Priorisierung); 0 = unbewertet.
  final int fromTiedUpCapitalCents;

  /// Reichweite des Ziels VOR der Umlagerung in Tagen (`null` = nicht bestimmbar).
  final double? destinationCoverageDaysBefore;
}

/// Schlägt Umlagerungen zwischen Standorten vor.
///
/// Quelle = [ProductVelocity.isDeadStock] (Bestand > 0, kein Absatz). Ziel =
/// anderer Standort, derselbe Artikel (Match über barcode → externalPosId →
/// Name), `dailyVelocity > 0` und Reichweite < [destinationMaxCoverageDays].
/// Menge = bis das Ziel [targetCoverageDays] Reichweite hätte, gedeckelt auf den
/// Quellbestand; je Quelle wird der Bestand greedy auf die dringendsten Ziele
/// (höchster Tagesabsatz zuerst) verteilt. Deterministisch sortiert nach
/// freigesetztem Kapital (desc), dann Quell-Produkt-ID.
List<TransferSuggestion> suggestCrossSiteTransfers({
  required List<ProductVelocity> velocities,
  required List<Product> products,
  double destinationMaxCoverageDays = 14,
  double targetCoverageDays = 21,
  int minTransferQuantity = 1,
}) {
  final velById = {for (final v in velocities) v.productId: v};
  final productById = <String, Product>{
    for (final p in products)
      if (p.id != null) p.id!: p,
  };

  // Identitätsgruppen aufbauen (Reihenfolge stabil = Erst-Auftreten).
  final groups = <String, List<String>>{};
  final matchByKey = <String, String>{};
  for (final p in products) {
    final id = p.id;
    if (id == null || !velById.containsKey(id)) continue;
    final identity = productIdentityOf(p);
    final key = identity.key;
    if (key == null) continue;
    groups.putIfAbsent(key, () => <String>[]).add(id);
    matchByKey.putIfAbsent(key, () => identity.matchedBy);
  }

  final suggestions = <TransferSuggestion>[];
  for (final entry in groups.entries) {
    final memberIds = entry.value;
    // Nur sinnvoll, wenn mindestens zwei verschiedene Standorte beteiligt sind.
    final siteIds = <String>{
      for (final id in memberIds) productById[id]!.siteId,
    };
    if (siteIds.length < 2) continue;

    final matchedBy = matchByKey[entry.key]!;
    final sources = memberIds
        .where((id) => velById[id]!.isDeadStock)
        .toList(growable: false);
    if (sources.isEmpty) continue;

    var destinations = memberIds.where((id) {
      final v = velById[id]!;
      final cov = v.coverageDays;
      return v.dailyVelocity > 0 &&
          cov != null &&
          cov < destinationMaxCoverageDays;
    }).toList();
    if (destinations.isEmpty) continue;
    // Dringendste Ziele zuerst (höchster Tagesabsatz), stabil per ID.
    destinations.sort((a, b) {
      final cmp = velById[b]!.dailyVelocity.compareTo(velById[a]!.dailyVelocity);
      return cmp != 0 ? cmp : a.compareTo(b);
    });

    for (final sourceId in sources) {
      final source = productById[sourceId]!;
      final sourceVel = velById[sourceId]!;
      var remaining = source.currentStock;
      if (remaining < minTransferQuantity) continue;

      for (final destId in destinations) {
        if (remaining < minTransferQuantity) break;
        final dest = productById[destId]!;
        if (dest.siteId == source.siteId) continue; // nur über Standorte
        final destVel = velById[destId]!;
        final targetUnits =
            (destVel.dailyVelocity * targetCoverageDays).ceil();
        final shortfall = targetUnits - dest.currentStock;
        if (shortfall < minTransferQuantity) continue;
        final qty = math.min(remaining, shortfall);
        if (qty < minTransferQuantity) continue;
        remaining -= qty;
        suggestions.add(
          TransferSuggestion(
            fromProduct: source,
            toProduct: dest,
            quantity: qty,
            matchedBy: matchedBy,
            fromTiedUpCapitalCents: sourceVel.tiedUpCapitalCents,
            destinationCoverageDaysBefore: destVel.coverageDays,
          ),
        );
      }
    }
  }

  suggestions.sort((a, b) {
    final cmp =
        b.fromTiedUpCapitalCents.compareTo(a.fromTiedUpCapitalCents);
    if (cmp != 0) return cmp;
    return (a.fromProduct.id ?? '').compareTo(b.fromProduct.id ?? '');
  });
  return suggestions;
}
