import '../models/product.dart';
import 'product_identity.dart';
import 'sales_velocity.dart';

/// **P4.1 — Laden-Vergleich / Listungslücken.** Findet Artikel, die in **einem**
/// Laden laufen (Absatz im Fenster), in einem **anderen** Laden der Org aber gar
/// nicht geführt werden — eine Listungschance („läuft in A, fehlt in B").
///
/// **Pure / offline-testbar.** Artikel-Identität über den geteilten
/// [productIdentityOf] (barcode → externalPosId → Name).
class ListingGap {
  const ListingGap({
    required this.sellingProduct,
    required this.missingSiteId,
    required this.soldUnits,
    required this.dailyVelocity,
    required this.matchedBy,
  });

  /// Der laufende Artikel-Datensatz im Quell-Laden.
  final Product sellingProduct;

  /// Standort, der diesen Artikel NICHT führt (Listungschance).
  final String missingSiteId;

  /// Verkaufte Einheiten im Quell-Laden im Fenster.
  final int soldUnits;
  final double dailyVelocity;

  /// Match-Qualität (`barcode` sicher … `name` schwach).
  final String matchedBy;
}

/// Listungslücken über die [siteIds] der Org.
///
/// - [velocities]/[products] sind org-weit (alle Standorte).
/// - Ein Artikel mit `soldUnits >= [minSoldUnits]` in Laden A erzeugt für jeden
///   Laden B aus [siteIds], der die Identität NICHT führt, eine [ListingGap].
/// - Pro (Identität, fehlender-Standort) gewinnt der bestverkaufende Quell-Artikel.
/// - Absteigend nach Tagesabsatz sortiert.
List<ListingGap> findListingGaps({
  required List<ProductVelocity> velocities,
  required List<Product> products,
  required List<String> siteIds,
  int minSoldUnits = 1,
}) {
  final velById = {for (final v in velocities) v.productId: v};

  // Identität -> Menge der Standorte, die sie führen.
  final carriedSites = <String, Set<String>>{};
  // Identität -> Match-Qualität.
  final matchByKey = <String, String>{};
  for (final p in products) {
    if (p.id == null) continue;
    final identity = productIdentityOf(p);
    final key = identity.key;
    if (key == null) continue;
    (carriedSites[key] ??= <String>{}).add(p.siteId);
    matchByKey.putIfAbsent(key, () => identity.matchedBy);
  }

  // Bester Quell-Artikel je (Identität, fehlender Standort).
  final best = <String, ListingGap>{};
  for (final p in products) {
    final id = p.id;
    if (id == null) continue;
    final vel = velById[id];
    if (vel == null || vel.soldUnits < minSoldUnits) continue;
    final identity = productIdentityOf(p);
    final key = identity.key;
    if (key == null) continue;
    final carried = carriedSites[key] ?? const <String>{};
    for (final siteId in siteIds) {
      if (carried.contains(siteId)) continue; // führt den Artikel bereits
      final gapKey = '$key|$siteId';
      final existing = best[gapKey];
      if (existing == null || vel.soldUnits > existing.soldUnits) {
        best[gapKey] = ListingGap(
          sellingProduct: p,
          missingSiteId: siteId,
          soldUnits: vel.soldUnits,
          dailyVelocity: vel.dailyVelocity,
          matchedBy: matchByKey[key] ?? identity.matchedBy,
        );
      }
    }
  }

  final result = best.values.toList()
    ..sort((a, b) {
      final c = b.dailyVelocity.compareTo(a.dailyVelocity);
      return c != 0 ? c : (a.sellingProduct.id ?? '').compareTo(b.sellingProduct.id ?? '');
    });
  return result;
}
