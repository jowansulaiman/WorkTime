import '../models/purchase_order.dart';

/// **WW-7 — Abweichung einer einzelnen Bestellposition** zwischen bestellt und
/// tatsächlich geliefert (Menge + Einkaufspreis). Rein datenhaltend.
class ReceiptDeviation {
  const ReceiptDeviation({
    required this.itemName,
    this.sku,
    required this.unit,
    required this.quantityOrdered,
    required this.quantityReceived,
    this.orderedUnitPriceCents,
    this.receivedUnitPriceCents,
  });

  final String itemName;
  final String? sku;
  final String unit;
  final int quantityOrdered;
  final int quantityReceived;

  /// Bestellter Netto-Einkaufspreis (Cent), falls hinterlegt.
  final int? orderedUnitPriceCents;

  /// Tatsächlich gelieferter Ist-EK (Cent, WW-6), falls beim Eingang erfasst.
  final int? receivedUnitPriceCents;

  /// Mengendifferenz: `+` Mehrlieferung, `-` Minderlieferung, `0` exakt.
  int get quantityDelta => quantityReceived - quantityOrdered;

  bool get isShort => quantityDelta < 0;
  bool get isOver => quantityDelta > 0;
  bool get hasQuantityDeviation => quantityDelta != 0;

  /// Preisdifferenz je Einheit (Ist-EK − bestellt) in Cent, `null` wenn einer
  /// der beiden Preise fehlt (dann keine belastbare Aussage möglich).
  int? get priceDeltaCents {
    final ordered = orderedUnitPriceCents;
    final received = receivedUnitPriceCents;
    if (ordered == null || received == null) return null;
    return received - ordered;
  }

  bool get hasPriceDeviation => (priceDeltaCents ?? 0) != 0;

  bool get hasAnyDeviation => hasQuantityDeviation || hasPriceDeviation;
}

/// **WW-7 — Abweichungsprotokoll einer Bestellung.** Aggregiert die
/// Positions-Abweichungen und liefert eine kurze Klassifikation für Anzeige und
/// Bestell-PDF. Rein, offline-testbar (keine Seiteneffekte, keine `now()`).
class ReceiptDeviationReport {
  const ReceiptDeviationReport({
    required this.all,
    required this.deviations,
  });

  /// Alle Positionen (auch abweichungsfreie) — für vollständige PDF-Tabellen.
  final List<ReceiptDeviation> all;

  /// Nur Positionen MIT Abweichung (Menge oder Preis).
  final List<ReceiptDeviation> deviations;

  bool get hasDeviations => deviations.isNotEmpty;

  int get shortCount => deviations.where((d) => d.isShort).length;
  int get overCount => deviations.where((d) => d.isOver).length;
  int get priceDeviationCount =>
      deviations.where((d) => d.hasPriceDeviation).length;

  /// Kompakte deutsche Zusammenfassung, z. B. „2 Minderlieferungen, 1
  /// Preisabweichung". Leer, wenn keine Abweichung.
  String get summary {
    final parts = <String>[];
    if (shortCount > 0) {
      parts.add(shortCount == 1
          ? '1 Minderlieferung'
          : '$shortCount Minderlieferungen');
    }
    if (overCount > 0) {
      parts.add(
          overCount == 1 ? '1 Mehrlieferung' : '$overCount Mehrlieferungen');
    }
    if (priceDeviationCount > 0) {
      parts.add(priceDeviationCount == 1
          ? '1 Preisabweichung'
          : '$priceDeviationCount Preisabweichungen');
    }
    return parts.join(', ');
  }
}

/// Bildet das [ReceiptDeviationReport] einer [PurchaseOrder] aus dem aktuellen
/// Positions-Ist (`quantityReceived`, `receivedUnitPriceCents`).
///
/// Sinnvoll erst nach mindestens einem Wareneingang — für eine noch nicht
/// gelieferte Bestellung ist jede Position „minderliefert" (received 0), was
/// [ReceiptDeviationReport.hasDeviations] korrekt widerspiegelt; der Aufrufer
/// zeigt das Protokoll darum nur bei teilweisem/vollem Eingang an.
ReceiptDeviationReport computeReceiptDeviations(PurchaseOrder order) {
  final all = <ReceiptDeviation>[];
  for (final item in order.items) {
    all.add(ReceiptDeviation(
      itemName: item.name,
      sku: item.sku,
      unit: item.unit,
      quantityOrdered: item.quantityOrdered,
      quantityReceived: item.quantityReceived,
      orderedUnitPriceCents: item.unitPriceCents,
      receivedUnitPriceCents: item.receivedUnitPriceCents,
    ));
  }
  return ReceiptDeviationReport(
    all: all,
    deviations: all.where((d) => d.hasAnyDeviation).toList(growable: false),
  );
}
