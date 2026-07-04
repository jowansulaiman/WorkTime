# Automatische Schichtverteilung

Die automatische Schichtplanung besteht aus **zwei puren Core-Klassen** – ohne State, IO, `now()` oder Zufall, daher **deterministisch und offline testbar**.

## Phase A: Slot-Generierung

`ShiftSlotGenerator` (`lib/core/shift_slot_generator.dart`) erzeugt **unbesetzte `Shift`-Slots** aus:

- `SiteDefinition.weekdayHours` (Öffnungszeiten; `TimeWindow`/`WeekdayHours` in `site_schedule.dart`)
- `SiteDefinition.staffingDemands` (Bedarf > 1 = **mehrere** `Shift`-Objekte, **kein** headcount-Feld)

`seriesId`/`shiftIdFactory` werden **injiziert** (deterministisch).

## Phase B: Zuweisung

`ShiftAutoAssigner` (`lib/core/shift_auto_assigner.dart`) verteilt die Slots unter:

- **harten Constraints**: Standort, Qualifikation, Abwesenheit, Doppelbelegung, **Compliance via `ComplianceService.validateShift`**, Cap/Minijob
- **weichen Zielen**: Fairness Richtung Sollzeit
- Verfahren: Greedy + stabile Sortierung.

## Stundengrenzen ≠ Compliance

> [!WARNING]
> `EmploymentContract.monthlyMaxHours`/`weeklyMaxHours` (beide `double?`, nullable) sind **Planungsschranken im Verteiler, KEINE Compliance-Violation**. Hart/weich via `OrgSettings.enforceHourCapHard` (Default hart); weich → `AssignmentWarning` + Score-Penalty. **Minijob-Verdienstgrenze + Compliance bleiben in beiden Modi hart.**

## Provider-Anbindung

In `ScheduleProvider`:

- `generatePlannedShifts` (Phase A, sync)
- `proposeAutoAssignment` (Phase B, **`Future`**) – sammelt besetzte Schichten + genehmigte Abwesenheiten für den **vollen Monat + ISO-Wochen der offenen Schichten** (nicht nur die sichtbare Woche, sonst zählen Caps/Minijob zu niedrig). Cloud/Hybrid via `getShiftsInRange`/`getApprovedAbsencesInRange` org-weit; Local aus dem vollständigen Cache.
- `applyAutoPlan` delegiert an `saveShifts` (erbt Batch ≤50 / Storage-Modi / Compliance-Re-Validierung).

## UI-Footgun

> [!NOTE]
> `ShiftPlannerScreen.build` gibt für `canManageShifts` **früh** das `_AdminShiftPlannerBoard` zurück; der Fallback-Pfad rendert nur für Nicht-Admins. Admin-Aktionen (`onAutoPlan`/`onCopyWeek`) müssen ins Board durchgereicht werden, NICHT in den Fallback-Pfad.

## Tests

`test/shift_slot_generator_test.dart`, `test/shift_auto_assigner_test.dart` – rein, deterministisch, offline.

## Weiter

- [Compliance-Engine](article:dev-compliance-engine)
- [Zeitwirtschaft (technisch)](article:dev-zeitwirtschaft-technik)
