// Pure Erkennung von Preisabweichungen App-VK vs. Kasse.
//
// Es gibt keinen Kassen-Endpunkt, der Artikelpreise LIEST (die OktoPOS-
// Anbindung kann Artikel nur schreiben). Die tatsaechlich kassierten Preise
// liegen aber bereits in den gesyncten Belegen (`posReceipts.lines[]`,
// `unitPriceCents` = Listen-Stueckpreis der Kasse zum Verkaufszeitpunkt,
// Rabatte separat). Der Abgleich vergleicht deshalb je Artikel den JUENGSTEN
// an der Kasse beobachteten Stueckpreis mit dem App-VK — automatisch, aus
// vorhandenen Daten, ohne neue Cloud Function.

import '../models/pos_receipt.dart';
import '../models/product.dart';

/// Eine erkannte Abweichung zwischen App-VK und Kassen-Preis eines Artikels.
class PriceDeviation {
  const PriceDeviation({
    required this.product,
    required this.posUnitPriceCents,
    required this.lastSoldAt,
    required this.observations,
  });

  final Product product;

  /// Juengster an der Kasse beobachteter Listen-Stueckpreis (Cent).
  final int posUnitPriceCents;

  /// Zeitpunkt des juengsten Verkaufs, der den Kassen-Preis belegt.
  final DateTime? lastSoldAt;

  /// Wie viele Verkaufszeilen im Fenster GENAU diesen Preis zeigten
  /// (Vertrauensindikator).
  final int observations;

  int? get appPriceCents => product.sellingPriceCents;

  /// Kasse minus App: positiv = Kasse kassiert MEHR als die App fuehrt.
  int get diffCents => posUnitPriceCents - (appPriceCents ?? 0);
}

/// Vergleicht die [products] gegen die Verkaufszeilen der [receipts] und
/// liefert alle Artikel, deren juengster Kassen-Preis vom App-VK abweicht —
/// inklusive Artikel ganz ohne App-VK (dort ist jeder Kassen-Preis eine
/// meldenswerte Abweichung). Sortiert nach absoluter Abweichung, groesste
/// zuerst.
///
/// Beruecksichtigt nur echte Verkaufsbelege (`isRevenue`, Typ `sales`, kein
/// Training) und Zeilen mit zugeordnetem Produkt + Stueckpreis. Rabatte
/// (`discountCents`) aendern den Listenpreis nicht und bleiben aussen vor.
List<PriceDeviation> computePriceDeviations({
  required List<Product> products,
  required List<PosReceipt> receipts,
  String? siteId,
}) {
  // Juengste Preisbeobachtung je Produkt sammeln.
  final latestByProduct = <String, ({int priceCents, DateTime? at})>{};
  final countByProductPrice = <String, int>{};

  for (final receipt in receipts) {
    if (!receipt.isRevenue || receipt.training) continue;
    if (receipt.type != 'sales') continue; // Refunds spiegeln Alt-Preise.
    if (siteId != null && siteId.isNotEmpty && receipt.siteId != siteId) {
      continue;
    }
    for (final line in receipt.lines) {
      final productId = line.productId;
      final unitPrice = line.unitPriceCents;
      if (productId == null || unitPrice == null || line.quantity <= 0) {
        continue;
      }
      final at = receipt.transactionDate;
      final existing = latestByProduct[productId];
      final isNewer = existing == null ||
          existing.at == null ||
          (at != null && at.isAfter(existing.at!));
      if (isNewer) {
        latestByProduct[productId] = (priceCents: unitPrice, at: at);
      }
      final countKey = '$productId:$unitPrice';
      countByProductPrice[countKey] = (countByProductPrice[countKey] ?? 0) + 1;
    }
  }

  final deviations = <PriceDeviation>[];
  for (final product in products) {
    final id = product.id;
    if (id == null) continue;
    if (siteId != null && siteId.isNotEmpty && product.siteId != siteId) {
      continue;
    }
    final observed = latestByProduct[id];
    if (observed == null) continue;
    if (product.sellingPriceCents == observed.priceCents) continue;
    deviations.add(
      PriceDeviation(
        product: product,
        posUnitPriceCents: observed.priceCents,
        lastSoldAt: observed.at,
        observations: countByProductPrice['$id:${observed.priceCents}'] ?? 0,
      ),
    );
  }
  deviations.sort((a, b) {
    final byDiff = b.diffCents.abs().compareTo(a.diffCents.abs());
    if (byDiff != 0) return byDiff;
    return a.product.name.toLowerCase().compareTo(b.product.name.toLowerCase());
  });
  return deviations;
}
