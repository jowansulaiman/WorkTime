import 'dart:math' as math;

import '../models/product.dart';
import 'sales_velocity.dart';

/// **P1.3 — Datengetriebener Meldebestand & Zielbestand.** Reine,
/// deterministische Ableitung empfohlener `minStock`/`targetStock`-Schwellen aus
/// der Verkaufsgeschwindigkeit ([ProductVelocity]) und der Lieferzeit — Renner
/// bekommen höhere, Langsamdreher niedrigere Schwellen. Ziel: weniger gebundenes
/// Kapital bei gleichbleibender Lieferfähigkeit.
///
/// **Pure / offline-testbar:** Lieferzeit (`leadTimeDaysBySupplierId` +
/// [defaultLeadTimeDays]) wird injiziert, kein State/IO/`now()`.
///
/// Formeln (klassisches Meldebestands-Modell):
/// - **Meldebestand** (Reorder Point) = ⌈Tagesabsatz × (Lieferzeit + Sicherheit)⌉
/// - **Zielbestand** (Order-up-to) = Meldebestand + ⌈Tagesabsatz × Eindeckzeit⌉
class ReorderSuggestion {
  const ReorderSuggestion({
    required this.productId,
    required this.siteId,
    required this.dailyVelocity,
    required this.leadTimeDays,
    required this.suggestedMinStock,
    required this.suggestedTargetStock,
    required this.currentMinStock,
    required this.currentTargetStock,
    required this.isReliable,
  });

  final String productId;
  final String siteId;
  final double dailyVelocity;

  /// Verwendete Lieferzeit in Tagen (aus Lieferant oder Default).
  final int leadTimeDays;

  /// Empfohlener Meldebestand (Reorder Point).
  final int suggestedMinStock;

  /// Empfohlener Zielbestand (Order-up-to-Level), >= [suggestedMinStock].
  final int suggestedTargetStock;

  final int currentMinStock;
  final int currentTargetStock;

  /// Datenbasis lang genug, um der Empfehlung zu trauen (sonst nur Richtwert).
  final bool isReliable;

  /// `true`, wenn sich der vorgeschlagene Meldebestand vom aktuellen
  /// unterscheidet (lohnt Anzeige/Übernahme).
  bool get minStockChanged => suggestedMinStock != currentMinStock;

  /// `true`, wenn sich der vorgeschlagene Zielbestand unterscheidet.
  bool get targetStockChanged => suggestedTargetStock != currentTargetStock;

  /// Mindestens eine Schwelle weicht ab.
  bool get hasChange => minStockChanged || targetStockChanged;
}

/// Berechnet [ReorderSuggestion] je Artikel aus den Velocity-Read-Models.
///
/// - [safetyDays]: Puffer oben auf die Lieferzeit (Schutz gegen Nachfragespitzen
///   und Lieferverzug).
/// - [coverageDays]: gewünschte Eindeckung zwischen zwei Bestellungen (bestimmt
///   den Abstand Zielbestand↔Meldebestand).
/// - Artikel ohne Absatz (`dailyVelocity == 0`, Ladenhüter) bekommen Schwellen 0
///   (nicht nachbestellen) — das setzt totes Kapital frei.
List<ReorderSuggestion> computeReorderSuggestions({
  required List<ProductVelocity> velocities,
  required List<Product> products,
  Map<String, int> leadTimeDaysBySupplierId = const {},
  int defaultLeadTimeDays = 3,
  int safetyDays = 3,
  int coverageDays = 14,
}) {
  final productById = <String, Product>{
    for (final p in products)
      if (p.id != null) p.id!: p,
  };

  final result = <ReorderSuggestion>[];
  for (final v in velocities) {
    final product = productById[v.productId];
    if (product == null) continue;

    final supplierLead = product.supplierId == null
        ? null
        : leadTimeDaysBySupplierId[product.supplierId];
    final leadTimeDays = math.max(0, supplierLead ?? defaultLeadTimeDays);

    final daily = v.dailyVelocity;
    final suggestedMin =
        daily <= 0 ? 0 : (daily * (leadTimeDays + safetyDays)).ceil();
    final coverage = daily <= 0 ? 0 : (daily * coverageDays).ceil();
    final suggestedTarget = suggestedMin + coverage;

    result.add(
      ReorderSuggestion(
        productId: v.productId,
        siteId: v.siteId,
        dailyVelocity: daily,
        leadTimeDays: leadTimeDays,
        suggestedMinStock: suggestedMin,
        suggestedTargetStock: suggestedTarget,
        currentMinStock: product.minStock,
        currentTargetStock: product.targetStock,
        isReliable: v.isReliable,
      ),
    );
  }
  return result;
}
