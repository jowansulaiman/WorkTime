# Plan-Ordner — Index & Stand

_Re-verifiziert am 2026-07-04 gegen den aktuellen Code (Multi-Agent-Assessment, jeder
Plan am echten Code stichprobenartig geprüft: existieren die Kern-Symbole/Dateien/Collections
wirklich?). Fertige Pläne (Kern geliefert, nur noch Deploy/Commit oder bewusst user-gated)
liegen in [archiv/](archiv/)._

## Aktive Pläne (echte, ungebaute Implementierungsarbeit offen)

| Plan | Stand | Offene Bauarbeit (Kern) |
|---|---|---|
| [konsolidierung-duplikate-kopplung.md](konsolidierung-duplikate-kopplung.md) | **in Arbeit** | Fundament (F1/F2), L1–L4, Z1/Z3–Z5, M4 gebaut+getestet. OFFEN: **M1** Urlaub-Konsolidierung (settings.vacationDays → effektiveUrlaubstage, Migrations-Konsumenten), **M2** Quali-Gültigkeit (gueltigBis in Auto-Assigner/Compliance), **M5** Ownership/read-only-Felder, **Q1** CostTypeRole-Enum, **Q2** dedizierter AbsenceProvider, **Q3** geteilte SummaryStat, **Z2** Stempel-Migration (`_clockInKey` → ZeitwirtschaftProvider). L5 optional. |
| [ida-hr-zeit-uebernahme.md](ida-hr-zeit-uebernahme.md) | mostly done | Phase A + M-B0/M-L-a + Stundenkonto/Stempeln/Monatsabschluss code-verifiziert (als `ClockEntry` via AllTec, Direct-Write). OFFEN echt: **M-L-b** Überstunden-Auszahlung (`lohnstunden.dart` fehlt), **M-D** DATEV-Lohn-Export (`datev_lohn_mapping.dart`/`buildDatevLohnCsv` fehlt), validierter `clockIn/clockOut`-Callable-Pfad (M7b, user-gated). |
| [personal-bereich-ausbau.md](personal-bereich-ausbau.md) | ~halb | PA-0 (Security), PA-2 (Akte-Self-Read), PA-3 (Dokumente/Storage), PA-6.1, PA-7, PA-8.3 gebaut+getestet. OFFEN: **PA-4** Stempel-Härtung (`clockIn/clockOut`-Callables + `{userId}`-open + `kioskPresence` fehlen), **PA-5** Monats-Festschreibung, **PA-6.2** Lines-Verrechnung, PA-1/2.1–2.2/7.3/8.1–8.2. |
| [arbeitsmodus-laden-tablet.md](arbeitsmodus-laden-tablet.md) | mostly done | I0–I2 code-fertig+getestet (StoreTask/Provider, `/arbeitsmodus`-Gate, KioskScreen mit PIN/Auto-Logout, 5 Kiosk-Callables + Rules/Index), I3 teilw. OFFEN echt: **kioskSubmitOrder** (server-geprüftes Bestellen, E7), **Increment 4** Geräte-Provisioning (`kioskActivateDevice`/`kioskDevices`/Admin-UI), `kioskRoster`-onWrite-Trigger. |
| [arbeitsmodus-kachel-ausbau.md](arbeitsmodus-kachel-ausbau.md) | Entwurf | Nur **A0** gebaut (`isKiosk()`-Rules-Härtung, 13 Deny-Pfade — über die Plan-Minimalempfehlung hinaus). OFFEN fast alles: A1b/A2/A3 — Callables (`kioskSubmitAbsence`/`-UpdateWishStatus`/`-MarkOrderPrepared`), Projektionen (`kioskShifts`/`-Presence`/`-Absences`), `StoreAnnouncement`+Provider, `oktoposSyncStatus`, `_HintsTile`-siteId-Bugfix, `preparedByUid`. |
| [redesign-gesamt.md](redesign-gesamt.md) | Masterplan | **Phase 0 (Fundament)** code-fertig+getestet (AppErrorState/AppSearchField/AppOfflineBanner, ConnectivityStatusProvider, GlobalSearch, 5 Pakete, 6 Tests — verifiziert). OFFEN: gesamter **Teil C** (Bereichs-Rollouts alle 7 Tabs), DS5 Golden, NAV/R/A11Y-Querschnitt-Deltas, S5 Biometrie-Gate + S6 2FA — substanzielle UI-Arbeit über 46+ Screens. |
| [ux-redesign-produktdesign.md](ux-redesign-produktdesign.md) | Produkt-Design | **Phase 0** gebaut (app-weiter Strichmännchen-Flip `resolveLight/Dark`, §4.11 G1–G5/G7 verdrahtet). OFFEN Phasen 1–3: interaktives Reorder-Banner (V1), entry-form-Defaults (B10), Bulk-Freigabe (B11); Komponenten `AppMonthPicker`/`AppAdaptiveTable`/`AppFilterBar`/`KioskStatusPanel`; Rollen-Dashboards (`_TeamleadDashboardTabV2`), `AppShiftColorMapper`, Hub-Umbau. Komplementär zu redesign-gesamt.md. |
| [ui-aufraeumen-und-verteilen.md](ui-aufraeumen-und-verteilen.md) | AKTIV | Nur **AP0.1** (Spacing-Tokens s6/s12) geliefert. OFFEN: alle 7 **God-File-Splits** AP2.1–2.7 (shift_planner 6155 Z, personal 5685, team 4813 …), 5 neue V2-Komponenten (AP0.2), DS-Adoption/Klon-Ersatz (AP1.x), Navigations-/Hub-Restrukturierung (AP4.x), A11y (AP5.x). |

## Archiviert (Kern vollständig geliefert) — [archiv/](archiv/)

24 Pläne, deren fachlicher Kern im Code gebaut+getestet ist; offen ist nur noch **Externes**
(Blaze-Deploy, Commit, On-Device-/Emulator-Abnahme, OktoPOS-Swagger-Verifikation) oder bewusst
**user-gated** Restpunkte. Voll annotierte Liste in [archiv/README.md](archiv/README.md). Kurz nach Thema:

- **Warenwirtschaft/Kasse/POS:** kassen-modul · oktopos-kassenanbindung · oktopos-datenwert-plan · oktopos-datenwert-deploy · oktopos-naechste-schritte · mhd-ablauf-warnung · kuehlschrank-nachfuell-automatik · dritte-hand-fremdgeld-kassenzaehlen · scanner-verbesserung
- **HR/Zeit/Finanzen:** zeitwirtschaft-alltec-1zu1 · zeitwirtschaft-verbesserung · personal-finanz-ausbau · alltec-uebernahme · ida-hr-zeit-uebernahme-VERIFIKATION (Analyse-Artefakt)
- **Passwörter:** passwortmanager-und-dritthand-kasse
- **Benachrichtigungen:** push-benachrichtigungen-plan
- **UI/Redesign:** redesign-signal-teal (Fundament, abgelöst durch redesign-gesamt.md)
- **Querschnitt/Audit:** skills-alignment · analyse-5-tabs-behebung
- **Früher archiviert:** auto-schichtverteilung · scanner-modul · bestellhaeufigkeit · schichttausch · wochen-bestellkorb

> **Konvention** ([[plan-ablageort]]): Pläne liegen versioniert hier im Projekt.
> „user-gated" = bewusst zurückgestellt, braucht eine Nutzer-Entscheidung (z.B.
> App-Check-Go-Live, Callable-Härtung, größere Architektur-Umbauten) — nicht
> automatisch ausführen. Ein Plan wandert nach [archiv/](archiv/), sobald sein Kern
> gebaut+getestet ist und nur noch Deploy/Commit oder user-gated Reste offen sind.
