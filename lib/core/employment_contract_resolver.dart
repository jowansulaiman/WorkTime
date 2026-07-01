import '../models/employment_contract.dart';

/// Zentraler, **purer** Resolver für den „am Stichtag gültigen Vertrag" eines
/// Mitarbeiters (Konsolidierungs-Fundament **F1**).
///
/// Vorher gab es zwei divergierende Implementierungen:
/// - `PersonalProvider.contractForUser` (Stichtag = `now()`, Fallback = jüngster
///   Vertrag) und
/// - `WorkProvider._activeContractForCurrentUser` (Stichtag-Parameter, **kein**
///   Fallback) — was bei abgelaufenem Vertrag zu unterschiedlichen Sätzen/
///   Sollzeiten zwischen den Modulen führte.
///
/// Beide Module bedienen sich jetzt aus dieser einen Funktion. Bewusste,
/// dokumentierte Entscheidung (Plan §3 F1): **bei fehlendem aktiven Vertrag wird
/// auf den jüngsten bekannten Vertrag zurückgefallen** (`fallbackToLatest`).
/// Ein bekannter Vertragssatz ist die belastbarere Quelle als der
/// selbstgemeldete `UserSettings`-Wert (SSoT-Leitregel: `settings.hourlyRate`
/// ist nur Anzeige-/Fallback-Wert, nie Berechnungseingang, solange ein Vertrag
/// existiert). So liefern Personal- und Zeit-/Lohn-Modul für denselben
/// Mitarbeiter/Stichtag denselben Vertrag.
class EmploymentContractResolver {
  const EmploymentContractResolver._();

  /// Der am [date] für [userId] gültige Vertrag. Bei Überlappung gewinnt der
  /// neueste `validFrom`. Ist kein Vertrag aktiv und [fallbackToLatest] gesetzt,
  /// wird der jüngste (egal ob aktiv) zurückgegeben, sonst `null`.
  static EmploymentContract? activeOn(
    Iterable<EmploymentContract> contracts,
    String userId,
    DateTime date, {
    bool fallbackToLatest = true,
  }) {
    EmploymentContract? active;
    EmploymentContract? latest;
    for (final contract in contracts) {
      if (contract.userId != userId) continue;
      if (latest == null || contract.validFrom.isAfter(latest.validFrom)) {
        latest = contract;
      }
      if (contract.isActiveOn(date)) {
        if (active == null || contract.validFrom.isAfter(active.validFrom)) {
          active = contract;
        }
      }
    }
    if (active != null) return active;
    return fallbackToLatest ? latest : null;
  }
}
