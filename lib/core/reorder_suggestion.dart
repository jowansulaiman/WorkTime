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
    this.currentStock = 0,
    this.incomingQuantity = 0,
  });

  final String productId;
  final String siteId;
  final double dailyVelocity;

  /// Aktueller Bestand des Artikels zum Berechnungszeitpunkt.
  final int currentStock;

  /// **WW-1 — unterwegs-Menge:** bereits bestellte, noch nicht gelieferte
  /// Menge (Summe `outstandingQuantity` offener Bestellungen). Senkt die
  /// konkrete Nachbestellmenge [suggestedOrderQuantity] — NICHT die
  /// Schwellen-Vorschläge (s. dort).
  final int incomingQuantity;

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

  /// **WW-1 — konkrete Nachbestellmenge, unterwegs-verrechnet:** Auffüllen bis
  /// zum vorgeschlagenen Zielbestand, wobei die bereits offene Bestellmenge
  /// ([incomingQuantity]) den Vorschlag senkt — was schon unterwegs ist, muss
  /// nicht erneut bestellt werden. Nie negativ.
  ///
  /// Bewusst wird NUR diese Bestellmenge verrechnet, nicht
  /// [suggestedMinStock]/[suggestedTargetStock]: die Schwellen sind
  /// nachfragegetriebene Dauerwerte, die der Inhaber am Artikel PERSISTIERT —
  /// eine transiente unterwegs-Menge darf sie nicht dauerhaft verfälschen.
  int get suggestedOrderQuantity {
    final delta = suggestedTargetStock - currentStock - incomingQuantity;
    return delta > 0 ? delta : 0;
  }
}

/// Berechnet [ReorderSuggestion] je Artikel aus den Velocity-Read-Models.
///
/// - [safetyDays]: Puffer oben auf die Lieferzeit (Schutz gegen Nachfragespitzen
///   und Lieferverzug).
/// - [coverageDays]: gewünschte Eindeckung zwischen zwei Bestellungen (bestimmt
///   den Abstand Zielbestand↔Meldebestand).
/// - [incomingByProductId] (WW-1, optional): offene Bestellmengen („unterwegs",
///   `productId → Summe outstandingQuantity`) — senken die konkrete
///   Nachbestellmenge [ReorderSuggestion.suggestedOrderQuantity], bewusst NICHT
///   die Schwellen-Vorschläge. Bleibt injiziert (pure, kein Provider-Zugriff).
/// - Artikel ohne Absatz (`dailyVelocity == 0`, Ladenhüter) bekommen Schwellen 0
///   (nicht nachbestellen) — das setzt totes Kapital frei. **Ausnahme:** neue
///   Artikel ([ProductVelocity.isNewProduct], erst im Fenster angelegt) sind zu
///   neu für eine Aussage und bekommen KEINEN Schwellen-0-Vorschlag (sonst
///   würde jeder frisch angelegte Artikel sofort auf „nicht nachbestellen"
///   gestellt).
List<ReorderSuggestion> computeReorderSuggestions({
  required List<ProductVelocity> velocities,
  required List<Product> products,
  Map<String, int> leadTimeDaysBySupplierId = const {},
  Map<String, int> incomingByProductId = const {},
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
    // Neu-Artikel-Guard: ohne Absatz UND jünger als das Fenster ⇒ zu neu für
    // eine „Schwellen auf 0"-Empfehlung — Artikel überspringen.
    if (daily <= 0 && v.isNewProduct) continue;
    final suggestedMin =
        daily <= 0 ? 0 : (daily * (leadTimeDays + safetyDays)).ceil();
    final coverage = daily <= 0 ? 0 : (daily * coverageDays).ceil();
    final suggestedTarget = suggestedMin + coverage;

    result.add(
      ReorderSuggestion(
        productId: v.productId,
        siteId: v.siteId,
        dailyVelocity: daily,
        currentStock: v.currentStock,
        incomingQuantity: math.max(0, incomingByProductId[v.productId] ?? 0),
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
