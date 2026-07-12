// Pure Duplikat-Erkennung fuer Barcodes je Laden. Grundlage des
// Duplikat-Reports in der Scan-Statistik und Ergaenzung zur harten
// Eindeutigkeits-Pruefung in InventoryProvider.saveProduct.

import '../models/product.dart';
import 'ean.dart';

/// Ein Barcode, der im selben Laden an mehreren Artikeln haengt.
class BarcodeDuplicate {
  const BarcodeDuplicate({
    required this.siteId,
    required this.canonicalCode,
    required this.products,
  });

  final String siteId;

  /// Kanonische Vergleichsform (siehe [canonicalGtin]) — die angezeigten
  /// Artikel koennen abweichende Schreibweisen tragen (UPC-A vs. EAN-13).
  final String canonicalCode;

  /// Mindestens zwei Artikel, inkl. deaktivierter (auch die blockieren die
  /// Eindeutigkeit, weil eine Reaktivierung sonst kollidiert).
  final List<Product> products;
}

/// Findet alle Barcodes, die innerhalb EINES Ladens an mehr als einem Artikel
/// haengen. Schreibweisen-tolerant ueber [canonicalGtin]; Artikel ohne Barcode
/// werden ignoriert. Ergebnis stabil sortiert (siteId, Code).
List<BarcodeDuplicate> findDuplicateBarcodes(List<Product> products) {
  // siteId -> kanonischer Code -> Artikel (kein zusammengesetzter String-Key:
  // Hauscodes duerfen beliebige Zeichen enthalten).
  final grouped = <String, Map<String, List<Product>>>{};
  for (final product in products) {
    final code = product.barcode?.trim() ?? '';
    if (code.isEmpty) continue;
    grouped
        .putIfAbsent(product.siteId, () => {})
        .putIfAbsent(canonicalGtin(code), () => [])
        .add(product);
  }
  final duplicates = <BarcodeDuplicate>[];
  grouped.forEach((siteId, byCode) {
    byCode.forEach((canonical, members) {
      if (members.length < 2) return;
      members
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      duplicates.add(
        BarcodeDuplicate(
          siteId: siteId,
          canonicalCode: canonical,
          products: List.unmodifiable(members),
        ),
      );
    });
  });
  duplicates.sort((a, b) {
    final bySite = a.siteId.compareTo(b.siteId);
    if (bySite != 0) return bySite;
    return a.canonicalCode.compareTo(b.canonicalCode);
  });
  return duplicates;
}
