# WorkTime — Code-Review: Bugs & Probleme

> **Re-Verifikation 2026-07-04.** Alle Befunde wurden erneut gegen den **aktuellen** Code
> geprüft (Multi-Agent, jeder Befund am echten Code; Zeilennummern der Ursprungsbefunde
> vom 21.06. sind veraltet). Detaildateien mit **vollständig behobenen** Befundgruppen sind
> nach [archiv/](archiv/) gewandert. Baseline weiterhin grün.

## Kernergebnis

- **Alle kritischen & hohen Befunde bleiben behoben** (Server-Compliance-Spiegel inkl. `travelTimeRules`,
  minutengenaue Aggregation, stabile Client-UUIDs, `Money.parseCents`, Übernacht-Schichten,
  orderCarts-Feld-Allowlist + `updatedByUid`-Bindung, App-Check im öffentlichen Wunschpfad — alle am Code belegt).
- **5 Detaildateien vollständig abgearbeitet** → archiviert (siehe unten).
- **Verbleibend: ausschließlich niedrig/mittel** über 7 Bereiche — Test-Lücken, kleine
  Provider-/Service-Edge-Cases, bewusst akzeptierte Restrisiken, Doku-Nuancen.

| Schweregrad | 21.06. | offen (29.06.) | offen (04.07.) |
|---|---|---|---|
| 🔴 Kritisch | 1 | 0 | **0** |
| 🟠 Hoch | 4 | 0 | **0** |
| 🟡 Mittel | 17 | 4 | **2** |
| ⚪ Niedrig | 54 | 37 | **~22** |

## Offene / teilweise Befunde (mittel zuerst)

| Schwere | Status | Bereich | Befund |
|---|---|---|---|
| mittel | offen | provider-state | #22 Hybrid-LWW vergleicht client-lokales `updatedAt` (`DateTime.now`) mit `serverTimestamp` (`work_provider.dart:2105/2181`) → Clock-Skew kann lokale Edits verlieren |
| mittel | offen | test-lücken | #19 Hybrid-Offline-Fallback der Bestellkorb-Mutationen ungetestet (`saveOrderList` wirft im Fake nie) |
| niedrig | offen | compliance | #24 Pausen-Rundungs-Drift (JS rundet Gesamtdifferenz, Dart pre-rundet Pause; ≤1 Min bei fraktionalen `breakMinutes`); #26 Jugend-/Mutterschutz-Nachtfenster hart 06:00/20:00 (RuleSet-`nightWindowStart/End` ignoriert; beide Spiegel konsistent) |
| niedrig | teilw. | provider-state | #44 App-Config/`minimumBuildNumber`-Pfad uncached — bewusste Fail-open-Designentscheidung (dokumentiert). `orgSettings` jetzt hybrid-gecacht |
| niedrig | offen | screens-ui | #51 Wunsch-`storeName`-Länge ungeprüft (vs. Rules-Cap 120); #53 Lohn-Prefill falscher Monat im Detail-Screen (nur Vorschlagswert); #54 Abwesenheiten je Board-Zelle neu sortiert (Perf, kein Bucketing) |
| niedrig | offen | services-firestore | #39 Abwesenheits-Reads ohne untere Datumsgrenze (bewusster Tradeoff, wächst mit Datenalter); #48 Bestelllisten-Streams teilen globalen `_setError` (Resilienz/UX) |
| niedrig | offen | services-persistenz | #33 Legacy-Migration mit leerem `orgId` trifft jeden Org-Scope (low-conf Edge-Case, für Ein-Org-Betrieb irrelevant); #34 Test-Lücke Org-Isolation `order_carts`/`weekly_order_lists`; #37 iOS/macOS-Share ohne `sharePositionOrigin` |
| niedrig | offen | navigation | #56 Force-Update fail-open (dokumentiert/akzeptiert); #57 Strg+1..9 in Bottom-Nav aus `railDestinations` (Profil per Shortcut unerreichbar); #58 PopScope verschluckt ersten Zurück-Druck im Randfall |
| niedrig | offen/teilw. | test-lücken | #66–#73 Widget-/Cloud-Tests für Wunsch/Bestellkorb/Zwei-Läden-Isolation fehlen; #69 nur teilw. (camelCase-Round-Trip prüft nur `contactId`) |

## Detail-Dateien

**Offene Bereiche** (Volltext der Ursprungsbefunde, 21.06.; Restpunkte niedrig/mittel):
[compliance.md](compliance.md) · [provider-state.md](provider-state.md) ·
[screens-ui.md](screens-ui.md) · [services-firestore.md](services-firestore.md) ·
[services-persistenz.md](services-persistenz.md) · [navigation-bootstrap.md](navigation-bootstrap.md) ·
[test-luecken.md](test-luecken.md)

**Archiviert (Befundgruppe vollständig behoben/akzeptiert)** — [archiv/](archiv/):
[01-kritisch-hoch.md](archiv/01-kritisch-hoch.md) (✅ alle kritisch/hoch behoben) ·
[core-lohn.md](archiv/core-lohn.md) (✅ #27–#32) ·
[modelle-serialisierung.md](archiv/modelle-serialisierung.md) (✅ #45 `clearSku`) ·
[sicherheit.md](archiv/sicherheit.md) (✅ #60/#61 orderCarts-BOPLA, #17 App-Check) ·
[bestellkorb-kundenwuensche.md](archiv/bestellkorb-kundenwuensche.md) (✅ #46 als „last writer wins" bewusst akzeptiert)
