import '../models/cash_closing.dart';

/// **Dritte-Hand-/Fremdgeld-Auswertung (§5).** Reine, getrennte Aggregation der
/// Fremdgeld-Beträge aus festgeschriebenen [CashClosing]s — **berührt keine
/// Umsatz-/Rohertrags-Aggregate** (`KassenPeriode` bleibt unverändert). Dient
/// der Darstellung „eigene Kasse vs. externe Dienste".

/// Aggregat einer einzelnen Fremdgeld-Art über den Zeitraum.
class ThirdPartyTypeSummary {
  const ThirdPartyTypeSummary({
    required this.typeId,
    required this.typeName,
    required this.totalCents,
    required this.count,
  });

  final String typeId;
  final String typeName;
  final int totalCents;

  /// Anzahl erfasster Positionen dieser Art (über alle Abschlüsse).
  final int count;
}

/// Gesamt-Aggregat der Fremdgelder eines Zeitraums.
class ThirdPartySummary {
  const ThirdPartySummary({required this.totalCents, required this.byType});

  final int totalCents;

  /// Je Art, absteigend nach Betrag.
  final List<ThirdPartyTypeSummary> byType;

  bool get isEmpty => byType.isEmpty;

  static const empty = ThirdPartySummary(totalCents: 0, byType: []);
}

/// Aggregiert die Fremdgeld-Beträge aller [closings] je Art. Pure & offline
/// testbar. Der Name wird als Snapshot der jüngsten Erfassung übernommen
/// (Abschlüsse kommen jüngste-zuerst, daher gewinnt der erste gesehene Name).
ThirdPartySummary computeThirdPartySummary(List<CashClosing> closings) {
  final byId = <String, ThirdPartyTypeSummary>{};
  var total = 0;
  for (final closing in closings) {
    for (final amount in closing.thirdParty) {
      total += amount.amountCents;
      final existing = byId[amount.typeId];
      byId[amount.typeId] = ThirdPartyTypeSummary(
        typeId: amount.typeId,
        // Ersten (jüngsten) nicht-leeren Namen behalten.
        typeName: existing?.typeName.isNotEmpty == true
            ? existing!.typeName
            : (amount.typeName.isNotEmpty ? amount.typeName : amount.typeId),
        totalCents: (existing?.totalCents ?? 0) + amount.amountCents,
        count: (existing?.count ?? 0) + 1,
      );
    }
  }
  final list = byId.values.toList(growable: false)
    ..sort((a, b) => b.totalCents.compareTo(a.totalCents));
  return ThirdPartySummary(totalCents: total, byType: list);
}
