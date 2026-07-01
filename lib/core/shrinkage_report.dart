import '../models/product.dart';
import '../models/stock_movement.dart';

/// **P2.2 — Schwund-/Inventurdifferenz-Report.** Macht Schwund erstmals **in €**
/// messbar: Inventurkorrekturen (`stocktake`) und manuelle Korrekturen
/// (`adjustment`) werden mit dem Einkaufspreis bewertet. Ein negativer
/// Netto-Saldo = Fehlbestand (Schwund), positiv = Überbestand. An der
/// margenarmen Zigarettenwand ist eingesparter Schwund direkter Gewinn.
///
/// **Pure / offline-testbar.** Bewusst NUR Artikel-/Warengruppenebene, **nie je
/// Mitarbeiter** (Datenschutz/Mitbestimmung). Schwund wird aus realen
/// Bestandsbewegungen + aktuellem EK abgeleitet (solide Datenbasis, unabhängig
/// von den noch unverifizierten Kassen-Geldfeldern).
class ShrinkageItem {
  const ShrinkageItem({
    required this.productId,
    required this.name,
    required this.category,
    required this.netUnits,
    required this.netValueCents,
    required this.isValuated,
  });

  final String productId;
  final String? name;
  final String? category;

  /// Netto-Mengenkorrektur im Zeitraum (Σ `quantityDelta`); negativ = fehlend.
  final int netUnits;

  /// Netto-Wert (Menge × EK) in Cent; negativ = Verlust. `null`, wenn EK fehlt
  /// (**unbewertet**, nicht 0).
  final int? netValueCents;

  final bool isValuated;
}

/// Aggregiertes Schwund-Ergebnis für Zeitraum/Standort.
class ShrinkageReport {
  const ShrinkageReport({
    required this.items,
    required this.shrinkageValueCents,
    required this.surplusValueCents,
    required this.netValueCents,
    required this.netValueByCategory,
    required this.unvaluatedCount,
  });

  /// Artikel, größter Verlust zuerst (negativster Netto-Wert).
  final List<ShrinkageItem> items;

  /// Summe der Verluste (Fehlbestände) als **positive** Cent-Zahl.
  final int shrinkageValueCents;

  /// Summe der Überbestände in Cent.
  final int surplusValueCents;

  /// Netto (Überbestand − Schwund), signed.
  final int netValueCents;

  /// Netto-Wert je Warengruppe in Cent (negativ = Schwund).
  final Map<String, int> netValueByCategory;

  final int unvaluatedCount;
}

class _Acc {
  _Acc({this.name, this.category});
  String? name;
  String? category;
  int netUnits = 0;
}

/// Standard-Bewegungstypen, die als Inventurdifferenz/Schwund zählen.
const Set<StockMovementType> kDefaultShrinkageTypes = {
  StockMovementType.stocktake,
  StockMovementType.adjustment,
};

/// Berechnet den [ShrinkageReport] aus Bestandsbewegungen + Artikeln (für EK +
/// Warengruppe). Nur [countedTypes] werden gewertet (Default: Inventur + manuelle
/// Korrektur). Verkäufe/Wareneingänge/Umlagerungen sind **keine** Differenz.
ShrinkageReport computeShrinkageReport({
  required List<StockMovement> movements,
  required List<Product> products,
  Set<StockMovementType> countedTypes = kDefaultShrinkageTypes,
}) {
  final productById = <String, Product>{
    for (final p in products)
      if (p.id != null) p.id!: p,
  };

  final acc = <String, _Acc>{};
  for (final m in movements) {
    if (!countedTypes.contains(m.type)) continue;
    final p = productById[m.productId];
    final a = acc.putIfAbsent(
      m.productId,
      () => _Acc(name: p?.name ?? m.productName, category: p?.category),
    );
    a.netUnits += m.quantityDelta;
  }

  var shrinkage = 0;
  var surplus = 0;
  var net = 0;
  var unvaluated = 0;
  final byCategory = <String, int>{};
  final items = <ShrinkageItem>[];

  for (final entry in acc.entries) {
    final pid = entry.key;
    final a = entry.value;
    final ek = productById[pid]?.purchasePriceCents;
    final isValuated = ek != null;
    final value = isValuated ? a.netUnits * ek : null;
    if (value != null) {
      net += value;
      if (value < 0) {
        shrinkage += -value;
      } else {
        surplus += value;
      }
      final cat = (a.category == null || a.category!.trim().isEmpty)
          ? 'Ohne Warengruppe'
          : a.category!;
      byCategory[cat] = (byCategory[cat] ?? 0) + value;
    } else {
      unvaluated++;
    }
    items.add(ShrinkageItem(
      productId: pid,
      name: a.name,
      category: a.category,
      netUnits: a.netUnits,
      netValueCents: value,
      isValuated: isValuated,
    ));
  }

  items.sort((x, y) {
    // Größter Verlust (negativster Wert) zuerst; unbewertete ans Ende.
    if (x.isValuated != y.isValuated) return x.isValuated ? -1 : 1;
    if (x.isValuated) {
      final c = x.netValueCents!.compareTo(y.netValueCents!);
      return c != 0 ? c : x.productId.compareTo(y.productId);
    }
    return x.productId.compareTo(y.productId);
  });

  return ShrinkageReport(
    items: items,
    shrinkageValueCents: shrinkage,
    surplusValueCents: surplus,
    netValueCents: net,
    netValueByCategory: byCategory,
    unvaluatedCount: unvaluated,
  );
}
