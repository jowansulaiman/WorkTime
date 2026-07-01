# WorkTime — Code-Review: Bugs & Probleme

> **Re-Verifikation 2026-06-29.** Alle 76 Befunde des Reviews vom 21.06. wurden gegen den
> **aktuellen** Code neu geprüft (Multi-Agent, jeder Befund am echten Code, Zeilennummern
> der Ursprungsbefunde sind veraltet). Ergebnis unten. Baseline weiterhin grün:
> `flutter analyze` sauber (2 triviale Alt-Hinweise), **1067 Tests grün**.

## Kernergebnis der Re-Verifikation

- **Alle kritischen & hohen Befunde sind behoben.** Server-Compliance-Spiegel (validateSingleWorkEntry),
  Minuten-Aggregations-Drift, Duplikat-Docs (stabile Client-UUID), `parseEuroToCents` (→ `Money.parseCents`),
  Übernacht-Schichten — alle in den letzten 8 Tagen gefixt (am Code belegt).
- **Verbleibend: 41 offene/teilweise Befunde, ausschließlich niedrig/mittel** (Test-Lücken,
  kleine Provider-Edge-Cases, Doku-Drift, toter Code, Härtungs-Restpunkte).
- **CSV-Formel-Injection, CSV-CR-Quoting, PDF/`DateFormat`-`de_DE`** ebenfalls bereits behoben.

| Schweregrad | 21.06. | offen/teilw. (29.06.) |
|---|---|---|
| 🔴 Kritisch | 1 | **0** |
| 🟠 Hoch | 4 | **0** |
| 🟡 Mittel | 17 | 4 |
| ⚪ Niedrig | 54 | 37 |

> Hinweis: Ein Teil dieser offenen Befunde wird im **Konsolidierungs-Lauf vom 29.06.**
> miterledigt (z.B. core-lohn toter Steuersatz-Code → L4; Lohn-Prefill falscher Monat
> #53 → L2). Stand der Umsetzung: siehe [plan/konsolidierung-duplikate-kopplung.md](../plan/konsolidierung-duplikate-kopplung.md).

## Offene / teilweise Befunde (mittel zuerst)

| Schwere | Status | Bereich | Befund |
|---|---|---|---|
| mittel | offen | provider-state | #22 Hybrid-LWW vergleicht client-lokales `updatedAt` (`DateTime.now`) mit `serverTimestamp` |
| mittel | teilw. | services-firestore | Callable-Idempotenz ohne `clientMutationId` (Daten-Integrität via stabile UUID gelöst, Trace-ID instabil) |
| mittel | teilw. | sicherheit | `customerWishes`: jeder Auth-Nutzer (auch fremde Org) kann unbegrenzt in main-org schreiben (App-Check/Rate-Limit) |
| mittel | offen | test-lücken | #19 Hybrid-Offline-Fallback der Bestellkorb-Mutationen ungetestet |
| niedrig | offen | compliance | Pausen-Rundungs-Drift (JS Gesamt vs. Dart break-vorab); Jugend-/Mutterschutz-Nachtfenster hartkodiert 06/20 |
| niedrig | teilw. | core-lohn | toter Steuersatz-Code (`soliRate`/`incomeTaxRateByClass`/`taxTariff`-Jahr) — **wird via L4 angegangen** |
| niedrig | offen | core-lohn | `_midijobBase` unter Minijob-Grenze ohne Übergangsminderung (Doku/Klassifikation) |
| niedrig | offen | provider-state | #63 TeamProvider `loading` bleibt true (Nicht-Manager, cloud-only); #64 Local-Dedup verwirft Rollenwechsel; #65 setMemberActive ohne Org-Check |
| niedrig | offen | provider-state | #74 fire-and-forget `_restartSubscriptions`; #75 `_notifyShiftWorked` ohne `_errorArea`; #76 Hybrid-Dedup spiegelt Settings nicht |
| niedrig | offen | provider-state | #42/#43 Audit-Mirror (cloud-only Lesen vs. lokal; Hybrid-Doppel-Eintrag); #44 FeatureFlag kein Offline-Cache (teilw.) |
| niedrig | offen | navigation | #56 Force-Update fail-open; #57 Strg+1..9 immer Rail; #58 PopScope erster Zurück; #59 CLAUDE.md-Breakpoint-Doku (1120 vs. 600) |
| niedrig | offen | services-firestore | Abwesenheits-Reads ohne untere Datumsgrenze; Batch-Direktschreiber ohne orgId-Konsistenzcheck; Bestelllisten-Streams `onError` global |
| niedrig | teilw. | sicherheit | `publicWishOrg()` hart 'main-org' vs. `APP_DEFAULT_ORG_ID` (Drift-Risiko) |
| niedrig | offen | screens-ui | #54 Abwesenheiten je Board-Zelle neu sortiert (Perf); #51 Wunsch-`storeName`-Länge ungeprüft; #53 Lohn-Prefill falscher Monat (**→ via L2 behoben**) |
| niedrig | offen | services-persistenz | Schema-Versionierung No-op; Legacy-Migration kopiert leere orgId breit; Scanner-Ton global; iOS-Share ohne `sharePositionOrigin` |
| niedrig | offen | test-lücken | #66–#73 Widget-/Cloud-Tests für Wunsch/Bestellkorb/Standort-Isolation fehlen; `publicStoreNameList`-Parsing ungetestet |

## Detail-Dateien (Volltext der Ursprungsbefunde, 21.06.)

[01-kritisch-hoch.md](01-kritisch-hoch.md) (✅ alle behoben) ·
[compliance.md](compliance.md) · [services-firestore.md](services-firestore.md) ·
[services-persistenz.md](services-persistenz.md) · [provider-state.md](provider-state.md) ·
[bestellkorb-kundenwuensche.md](bestellkorb-kundenwuensche.md) · [sicherheit.md](sicherheit.md) ·
[modelle-serialisierung.md](modelle-serialisierung.md) (✅ behoben) · [core-lohn.md](core-lohn.md) ·
[navigation-bootstrap.md](navigation-bootstrap.md) · [screens-ui.md](screens-ui.md) ·
[test-luecken.md](test-luecken.md)
