# Plan-Ordner — Index & Stand

_Re-verifiziert am 2026-06-29 gegen den aktuellen Code (Multi-Agent-Assessment, jeder
Punkt am echten Code geprüft). Fertige Pläne liegen in [archiv/](archiv/)._

## Aktive Pläne (offene Punkte vorhanden)

| Plan | Stand | Offene Punkte (Kern) |
|---|---|---|
| [konsolidierung-duplikate-kopplung.md](konsolidierung-duplikate-kopplung.md) | **in Arbeit** | Entdopplung & Kopplung Lohn↔Personal↔Zeit. F1/F2-Resolver + Welle L/M/Z/Q. **Wird im Zuge des 29.06-Aufräumens abgearbeitet** (außer user-gated L5/Z2). |
| [zeitwirtschaft-alltec-1zu1.md](zeitwirtschaft-alltec-1zu1.md) | mostly done | M1–M6+M7a fertig. Offen nur **user-gated**: M7b (Callable-Härtung Stempeln), M3c-a (Home-Clock-Migration), gebündeltes Deploy. |
| [ida-hr-zeit-uebernahme.md](ida-hr-zeit-uebernahme.md) | mostly done | Offen: **M-D DATEV-Lohn-Export** (E5), M-L-b Überstunden-Auszahlung→PayrollLine (partial). Rest user-gated (Kiosk/Recruiting/Härtung). |
| [ida-hr-zeit-uebernahme-VERIFIKATION.md](ida-hr-zeit-uebernahme-VERIFIKATION.md) | Analyse-Artefakt | Reines Verifikations-Dokument zum IDA-Plan; nur §5-Empfehlungen aktionierbar. |
| [alltec-uebernahme.md](alltec-uebernahme.md) | mostly done | Offen: M2 Lieferantenbestellung-PDF+mailto, M5b WorkTimePdfTheme/Berichte-Hub, M7d Serien-Schicht-Edit (partial). Rest user-gated (Governance/Notifications). |
| [personal-finanz-ausbau.md](personal-finanz-ausbau.md) | mostly done | Offen: C-Import (CSV/DATEV-Import Finanzen), journalEntries-Jahresfilter+Index. B4/B6 bereits umgesetzt (Plan veraltet). |
| [redesign-signal-teal.md](redesign-signal-teal.md) | partial | Inkrementeller Signal-Teal-Rollout hinter `redesign_v2`. Viele Screens noch V1/Legacy. Strangler-Fig, fortlaufend. |
| [skills-alignment.md](skills-alignment.md) | mostly done | Verbleib v.a. **user-gated** Architektur-/Perf-Schulden (God-File-Split shift_planner/home_screen, Secure-Storage, Outbox/Delta-Sync, Golden-Tests, Flavors). |

## Archiviert (Kern vollständig geliefert) — [archiv/](archiv/)

| Plan | Status | Rest |
|---|---|---|
| auto-schichtverteilung.md | ✅ fully done | — |
| scanner-modul.md | ✅ fully done | — |
| bestellhaeufigkeit.md | ✅ fully done | nur gated: fl_chart-Config-Dedup (kosmetisch) |
| schichttausch.md | ✅ fully done | nur gated: rules-Deploy |
| wochen-bestellkorb.md | ✅ fully done | nur gated: Cloud-Korb-Array-Union-Transaktion (LWW akzeptiert) |

> **Konvention** ([[plan-ablageort]]): Pläne liegen versioniert hier im Projekt.
> „user-gated" = bewusst zurückgestellt, braucht eine Nutzer-Entscheidung (z.B.
> App-Check-Go-Live, Callable-Härtung, größere Architektur-Umbauten) — nicht
> automatisch ausführen.
