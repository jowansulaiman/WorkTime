import '../models/product.dart';

/// Geteilte Artikel-Identität für den **standortübergreifenden Match** (derselbe
/// Artikel als zwei Datensätze, je Laden einer). Reihenfolge der Qualität:
/// `barcode` (sicher) → `externalPosId` (Kassen-Fremdschlüssel) → Name
/// (lowercase, schwächste). Genutzt von Umlagerung (P1.2) und Laden-Vergleich
/// (P4.1), damit beide dieselbe Match-Logik teilen.
class ProductIdentity {
  const ProductIdentity(this.key, this.matchedBy);

  /// Identitätsschlüssel; `null`, wenn keiner ableitbar ist.
  final String? key;

  /// `'barcode'` | `'externalPosId'` | `'name'` — Match-Qualität für die UI.
  final String matchedBy;
}

ProductIdentity productIdentityOf(Product p) {
  final barcode = p.barcode?.trim();
  if (barcode != null && barcode.isNotEmpty) {
    return ProductIdentity('barcode:$barcode', 'barcode');
  }
  final external = p.externalPosId?.trim();
  if (external != null && external.isNotEmpty) {
    return ProductIdentity('external:$external', 'externalPosId');
  }
  final name = p.name.trim().toLowerCase();
  if (name.isNotEmpty) {
    return ProductIdentity('name:$name', 'name');
  }
  return const ProductIdentity(null, 'name');
}
