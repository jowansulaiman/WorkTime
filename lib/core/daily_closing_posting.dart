import '../models/finance_models.dart';
import 'daily_closing.dart';

/// **P2.0 — Tagesabschluss → DATEV-Buchung.** Bildet aus einem [DailyClosing]
/// die buchungsfähigen [JournalEntry]s: **je USt-Satz EINE Zeile** auf das
/// dedizierte Erlöskonto.
///
/// **Pure / offline-testbar.** Wichtige Designentscheidungen (aus dem Plan):
/// - **Konto-Zuordnung EXPLIZIT** über [revenueCostTypeIdByRate] (Satz →
///   CostType-/Erlöskonto-ID), NICHT über die Namens-Heuristik
///   (`_resolveCostTypeByNeedles` kann „Umsatz 19" und „Umsatz 7" nicht trennen).
/// - Betrag = **netto** je Satz (Erlöse sind netto; das dedizierte Konto je
///   19/7 trägt den Satz), **negativ** (Gutschrift-/Erlös-Konvention von
///   [JournalEntry.amountCents]).
/// - Deterministische ID `pos-<businessDay>-<siteId>-<ratePercent>` → idempotent
///   (Re-Buchung überschreibt via set(merge), keine Doppelbuchung).
/// - Sätze **ohne** zugeordnetes Konto (oder mit netto 0 / unbekanntem Satz)
///   werden **übersprungen** (keine Falschbuchung); der Aufrufer kann warnen.
///
/// **Richtwert** — der DATEV-Export trägt bewusst keine Steuerschlüssel; der
/// Steuerberater prüft vor der Verbuchung. Geld-/Steuerfelder der Kasse sind
/// zudem noch Swagger-unverifiziert (P0).
List<JournalEntry> buildDailyClosingEntries(
  DailyClosing closing, {
  required String orgId,
  required String costCenterId,
  required Map<int, String> revenueCostTypeIdByRate,
  String? createdByUid,
}) {
  final date = DateTime.tryParse('${closing.businessDay}T12:00:00') ??
      DateTime.tryParse(closing.businessDay) ??
      DateTime(1970);
  final entries = <JournalEntry>[];
  for (final bucket in closing.taxBuckets) {
    final rate = bucket.ratePercent;
    if (rate == null) continue; // unbekannter Satz -> nicht buchen
    final costTypeId = revenueCostTypeIdByRate[rate];
    if (costTypeId == null || costTypeId.isEmpty) continue; // kein Konto -> skip
    if (bucket.netCents == 0) continue;
    entries.add(JournalEntry(
      id: 'pos-${closing.businessDay}-${closing.siteId}-$rate',
      orgId: orgId,
      date: date,
      costCenterId: costCenterId,
      costTypeId: costTypeId,
      amountCents: -bucket.netCents, // Erlös = Gutschrift (negativ)
      description:
          'Tagesumsatz ${closing.businessDay} · $rate% USt (Kasse, Richtwert)',
      reference: closing.businessDay,
      createdByUid: createdByUid,
    ));
  }
  return entries;
}
