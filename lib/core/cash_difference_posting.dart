import '../models/cash_closing.dart';
import '../models/finance_models.dart';

/// **Kassen-Modul M6 — Kassendifferenz → Finanzjournal.** Bildet aus einem
/// festgeschriebenen [CashClosing] die buchungsfähige [JournalEntry] für die
/// Kassendifferenz (gezählt − Soll), damit Schwund/Überschuss an der Lade im
/// Finanzergebnis auftaucht (Plan §8a).
///
/// **Pure / offline-testbar.** Konventionen:
/// - Vorzeichen: `amountCents = -cashDifferenceCents`. Ein **Fehlbetrag**
///   (`cashDifferenceCents < 0`, gezählt < Soll) wird so zu **positiven Kosten**;
///   ein **Überschuss** (`> 0`) zu einer **negativen Gutschrift** — deckungsgleich
///   mit der [JournalEntry.amountCents]-Konvention (>0 Kosten, <0 Gutschrift).
/// - Deterministische ID `pos-diff-<businessDay>-<siteId>` → idempotent
///   (Re-Buchung überschreibt via set(merge), keine Doppelbuchung).
/// - `null`, wenn keine Differenz vorliegt (ohne Zählung oder Differenz 0) oder
///   kein Kostenkonto/keine Kostenstelle zugeordnet ist (keine Falschbuchung).
///
/// **Richtwert** — Kassendaten Swagger-unverifiziert; der Steuerberater prüft.
JournalEntry? buildCashDifferenceEntry(
  CashClosing closing, {
  required String orgId,
  required String costCenterId,
  required String costTypeId,
  String? createdByUid,
}) {
  final diff = closing.cashDifferenceCents;
  if (diff == null || diff == 0) return null;
  if (costCenterId.isEmpty || costTypeId.isEmpty) return null;
  final date = DateTime.tryParse('${closing.businessDay}T12:00:00') ??
      DateTime.tryParse(closing.businessDay) ??
      DateTime(1970);
  final art = diff < 0 ? 'Fehlbetrag' : 'Überschuss';
  return JournalEntry(
    id: 'pos-diff-${closing.businessDay}-${closing.siteId}',
    orgId: orgId,
    date: date,
    costCenterId: costCenterId,
    costTypeId: costTypeId,
    amountCents: -diff,
    description:
        'Kassendifferenz ${closing.businessDay} · $art (Kasse, Richtwert)',
    reference: closing.businessDay,
    createdByUid: createdByUid,
  );
}
