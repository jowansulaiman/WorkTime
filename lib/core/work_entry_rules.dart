// lib/core/work_entry_rules.dart

import '../models/shift.dart';
import '../models/work_entry.dart';

/// Pure Freigabe-/Zähl-Regeln für [WorkEntry] — Single Source of Truth für den
/// Zeitwirtschafts-Freigabe-Workflow (Plan `plan/zeit-schichtbindung-freigabe.md`).
///
/// Bewusst ohne State/IO/`now()` → deterministisch + offline testbar
/// (`test/work_entry_rules_test.dart`). Client (WorkProvider/Screens), die
/// Aggregationen (Zeitkonto) und — spiegelbildlich — Rules/Callable müssen
/// GEGEN diese Definitionen arbeiten; Änderungen hier an allen Spiegeln
/// nachziehen (siehe Plan „Material-Feld-Set (3-Punkt-Sync)").

/// Zählt ein Eintrag ins **bindende Ist** (Saldo/Zeitkonto/Lohn)?
///
/// **Streng (E3):** nur `approved`. `draft`/`submitted` sind „vorläufig, in
/// Freigabe" und zählen NICHT ins bindende Ist; `rejected` zählt nie.
///
/// Abwärtskompatibel: Alt-Einträge ohne `status`-Feld parsen als `approved`
/// ([WorkEntryStatus.fromValue]-Default) und zählen daher voll.
bool countsAsIst(WorkEntry entry) => entry.status == WorkEntryStatus.approved;

/// Gilt der Eintrag als „vorläufig" (erfasst, aber noch nicht bindend gezählt)?
/// Für getrennte UI-Ausweisung „… h in Freigabe".
bool isVorlaeufig(WorkEntry entry) =>
    entry.status == WorkEntryStatus.submitted ||
    entry.status == WorkEntryStatus.draft;

/// Ändert sich zwischen [oldEntry] und [newEntry] ein Feld aus dem
/// **Material-Feld-Set** `{startTime, endTime, breakMinutes, siteId}`?
///
/// Dieses Set ist der EINZIGE Re-Approval-/Korrektur-Trigger — exakt wie die
/// bestehende Server-Funktion `correctionReasonRequired` in
/// `functions/index.js` (bewusster Spiegel). **Nicht** im Set: `date` (aus
/// `startTime` abgeleitet/normalisiert), `note`/`category` (nicht
/// abrechnungsrelevant), `sourceShiftId` (Zuordnungs-Metadatum). `breakMinutes`
/// wird — wie serverseitig — auf ganze Minuten gerundet verglichen; `siteId`
/// wird leer==null normalisiert.
bool isMaterialWorkEntryChange(WorkEntry oldEntry, WorkEntry newEntry) {
  return !oldEntry.startTime.isAtSameMomentAs(newEntry.startTime) ||
      !oldEntry.endTime.isAtSameMomentAs(newEntry.endTime) ||
      oldEntry.breakMinutes.round() != newEntry.breakMinutes.round() ||
      _normalizeSiteId(oldEntry.siteId) != _normalizeSiteId(newEntry.siteId);
}

String? _normalizeSiteId(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// Z2/Z4: Erzwingt den Freigabe-Status für eine **Eigen-Erfassung/-Korrektur**
/// (der Speicherpfad pinnt `userId == author.uid`, daher immer Eigen-Bezug).
///
/// Admins ([isAdmin]) sind laut Freigabe-Konzept ausgenommen und dürfen
/// `approved` erfassen/behalten. Für alle anderen wird der Eintrag auf
/// `submitted` gesetzt und verliert die Freigabe (`approvedByUid`/`approvedAt`
/// geleert) → er geht (erneut) in die Manager-Warteschlange. Deckt Z2 (Neuanlage)
/// und Z4 (Korrektur eines bereits genehmigten Eintrags) einheitlich ab.
/// Idempotent. Server-seitig erzwingen Rules/Callable dasselbe; dies ist der
/// Client-Vorlauf.
WorkEntry applyOwnEntrySubmissionPolicy(
  WorkEntry entry, {
  required bool isAdmin,
}) {
  if (isAdmin) {
    return entry;
  }
  if (entry.status == WorkEntryStatus.submitted &&
      entry.approvedByUid == null &&
      entry.approvedAt == null) {
    return entry;
  }
  return entry.copyWith(
    status: WorkEntryStatus.submitted,
    clearApprovedByUid: true,
    clearApprovedAt: true,
  );
}

/// E4/Z7: Darf [entry] per **Sammel-Freigabe** genehmigt werden? Nur
/// schicht-konforme, aus echtem Stempel stammende, unkorrigierte Zeiten — so
/// rutscht **nie** ein manueller/nachgearbeiteter/ungeplanter Eintrag in die
/// Sammel-Freigabe (der geht einzeln). Bedingungen (alle):
/// - `status == submitted`
/// - `sourceShiftId` gesetzt (schicht-gebunden)
/// - `sourceClockEntryId` gesetzt (aus echtem Stempel, keine Hand-Erfassung)
/// - `correctionReason == null` (keine Nacharbeitung)
/// - falls [shift] übergeben: Stempel liegt **innerhalb [tolerance]** um die
///   geplanten Zeiten (pünktlich; kein verspätet/früher).
bool isEligibleForBulkApproval(
  WorkEntry entry, {
  Shift? shift,
  Duration tolerance = const Duration(minutes: 15),
}) {
  if (entry.status != WorkEntryStatus.submitted) return false;
  final shiftId = entry.sourceShiftId?.trim();
  if (shiftId == null || shiftId.isEmpty) return false;
  final clockId = entry.sourceClockEntryId?.trim();
  if (clockId == null || clockId.isEmpty) return false;
  if (entry.correctionReason != null) return false;
  if (shift != null) {
    if (shift.id != shiftId) return false;
    final startDelta =
        entry.startTime.difference(shift.startTime).inMinutes.abs();
    final endDelta = entry.endTime.difference(shift.endTime).inMinutes.abs();
    if (startDelta > tolerance.inMinutes || endDelta > tolerance.inMinutes) {
      return false;
    }
  }
  return true;
}
