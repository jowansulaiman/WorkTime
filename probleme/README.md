# WorkTime — Code-Review: Bugs & Probleme

> **Abschluss-Welle 2026-07-12.** Alle noch offenen Befunde des Reviews vom
> 21.06. wurden erneut gegen den aktuellen Code verifiziert (Multi-Agent-Triage
> + adversariale Gegenprüfung) und **behoben, als bewusste Design-Entscheidung
> dokumentiert oder als bereits behoben bestätigt**. Alle sieben Detaildateien
> sind nach [archiv/](archiv/) gewandert. Zusätzlich wurde die neue GB-Liste
> ([gb_prob_2026-07-12.md](gb_prob_2026-07-12.md)) in zwei Wellen abgearbeitet
> (Fix-Tabelle unten). Quality Gates: **flutter analyze 0 Issues**,
> **1836 Flutter-Tests**, **109 Node-Tests** — alles grün.

## Stand 21.06.-Review: KOMPLETT abgeschlossen

| Schweregrad | 21.06. | offen (04.07.) | offen (12.07.) |
|---|---|---|---|
| 🔴 Kritisch | 1 | 0 | **0** |
| 🟠 Hoch | 4 | 0 | **0** |
| 🟡 Mittel | 17 | 2 | **0** |
| ⚪ Niedrig | 54 | ~22 | **0** |

Am 12.07. erledigt (Details in [archiv/README.md](archiv/README.md)):
- **Behoben:** #24 (Pausen-Rundungs-Spiegel), #22 (Hybrid-LWW Clock-Skew →
  Pending-Sync-Set), #33 (Legacy-Migration nur Default-Org), #48
  (Bestelllisten-Stream-Fehler entkoppelt), #51 (120-Zeichen-Cap Ladenname),
  #54 (Abwesenheiten-Bucketing), #37 (iPad-Share-Anker), #57/#58
  (Nav-Shortcuts/PopScope) sowie alle Test-Lücken #19/#34/#66–#73.
- **Bewusst akzeptiert (dokumentiert):** #26 (gesetzliches
  Jugend-/Mutterschutz-Nachtfenster fest 20:00–06:00), #39
  (Abwesenheits-Reads ohne untere Grenze), #44/#56 (Force-Update fail-open).
- **Bereits behoben bestätigt:** #53 (Lohn-Prefill; `computeZeitkonto` filtert
  hart auf die Record-Periode).

## GB-Liste 2026-07-12 (Sicherheits-/Integritäts-Analyse): ABGEARBEITET

[gb_prob_2026-07-12.md](gb_prob_2026-07-12.md) deckt sich weitgehend mit
`plan/sicherheits-audit-2026-07.md`. Stand nach den zwei Fix-Wellen vom 12.07.:

**Behoben (Code fertig — Rules-/Storage-/Functions-Deploy noch offen!):**

| GB | Audit | Fix |
|---|---|---|
| K1 | K1 | `config/{configId}`-Write jetzt `isAdmin() && sameOrg(orgId)` |
| K2 | M1 | `organizations/{orgId}` create/update an `sameOrg` gebunden |
| K3 | K3 | `enforceShiftOrg` erzwingt Caller-Org je Schicht; `writeShiftBatch` nimmt explizite orgId (+ Node-Tests) |
| K4 | K2 | `assertOktoposHostAllowed`: exakte Host-Allowlist (`OKTOPOS_ALLOWED_HOSTS`, fail-closed) + Block privater/lokaler IPs; zentral in `resolveOktoposBaseUrl` (+ Node-Tests) |
| K5 | H1 | users-create: permissions IMMER gegen Invite geprüft (Rollen-Default-Fallback) |
| K6 | H2 | users-create: Lohn-/Urlaubsfelder via `settingsPayrollMatchesInvite` ans Invite gepinnt |
| H1 | M2 | `userInvites` get/list org-skopiert (Client-Query war bereits org-gepinnt) |
| H2 | H3 | `assertOktoposSiteConfigured` vor jeder Key-Auflösung; `*`/`default`-Key-Fallback entfernt (+ Node-Test) |
| H3 | H4 | `oktoposLineDiscriminator`: Positions-Index-Fallback statt movementId-Kollaps bei fehlender `item.id` (+ Node-Test) |
| H4 | H5 | Pagination blättert bei fehlendem `lastPage` weiter, solange volle Seiten kommen (+ Warn-Log) |
| H5 | M3 | Cap-Abbruch: `result.truncated`, Error-Log, Cursor wird NICHT fortgeschrieben (keine dauerhafte Lücke) |
| H6 | M4 | Receipt-/Movement-IDs am STABILEN siteId-Scope statt an der änderbaren `cashRegisterId` (+ Node-Test) |
| H7 | L2 | `oktoposNightlySync` paginiert über alle Orgs (kein hartes limit(50)) |
| H8 | H6 | `saveProduct` schreibt `currentStock` bei EXISTIERENDEM Doc nicht mehr mit (Doc-Existenz-Kriterium schont syncLocalStateToCloud; + Provider-Re-Injektion, Test) |
| H9 | N4 | Inventur setzt absolut in der Transaktion (`setProductStock`), Delta aus dem frischen Serverstand (Test) |
| H10 | — | Umlagerung atomar: `transferProductStock` bucht Quelle+Ziel+beide Bewegungen in EINER Transaktion (+ Test mit stale-UI-Guard) |
| H11 | — | `postDailyClosing` meldet `cloudComplete`; der Tagesabschluss markiert `bookedToFinance` nur noch nach echtem Cloud-Journal (+ Test) |
| M2 | N11 | storage.rules prüfen `isActive` in allen drei Blöcken (employee-documents, Kontakt-Avatar, Signage) |
| M3 | N2 | Login: transiente Firestore-/Netzfehler → Retry mit Backoff statt sofortigem signOut |
| M4 | N9 | Bootstrap-Admin-Selbstprovisionierung code-seitig auf `!kReleaseMode` gegated (Defense-in-Depth) |
| M5 | N10 | Rules-`inviteIdForCurrentUser()` an Client-Normalisierung angeglichen (`'/'→'_'`) |
| M6 | N5 | ProductBatch-MHD ist load-bearing: FormatException statt 2000-01-01-Fallback; Lesepfade überspringen protokolliert (+ Test) |
| M7 | N1 | Monatsreport-PDF filtert auf `countsAsIst` (E3 — keine submitted/draft/rejected-Zeiten in Lohnsummen) |
| M8 | M5 | Refund senkt COGS in BEIDEN Spiegeln (`oktopos_stats.js` + `kasse_report.dart`, + Tests) |
| M9 | N6 | Kiosk-WorkEntry.date auf Berliner Mittagszeit normalisiert (`berlinNoonDate`, DST-korrekt, + Node-Test) |
| M10 | N7 | `kioskSaveCashCount` validiert `siteId` gegen die Org-Standorte |
| N2 | — | Content-Security-Policy zusätzlich als HTTP-Header in `firebase.json` (Meta-Tag bleibt als Fallback) |
| N3 | — | Analyzer auf 0 Issues: tote Lint-Regel entfernt, `onNavigateBack`-Leiche bereinigt, `announce`→`sendAnnouncement` |

**Bewusst offen gelassen (mit Begründung):**
- **M1** (Kiosk/einfache Nutzer lesen EK-Preise/Lieferanten/Bestellungen):
  kollidiert mit dem geplanten A0 „Read-Scope zu weit" aus
  `plan/arbeitsmodus-kachel-ausbau.md` (Projektionen statt Roh-Reads) — ein
  Rules-only-Schnellfix bräche die Kiosk-Board-Streams (products für
  Kühlschrank/MHD). Dort umsetzen.
- **N1** (App-Check-Enforcement): Betriebs-/Console-Thema, bereits als
  Betriebsannahme dokumentiert (archiv/sicherheit.md #17).
- **N4** (Dependency-Upgrades): eigenes, risikobehaftetes Upgrade-Projekt mit
  separatem Testlauf — nicht als Beifang.

**Deploy-Hinweis:** Wirksam erst nach `firebase deploy --only
firestore:rules,storage` bzw. `--only functions` (+ beim OktoPOS-Cutover
`OKTOPOS_ALLOWED_HOSTS` setzen, sonst bleibt OktoPOS fail-closed gesperrt) und
einem neuen Web-/App-Build — Runbook `plan/deploy-checkliste.md`.

## Detail-Dateien

**Offen:** [gb_prob_2026-07-12.md](gb_prob_2026-07-12.md) (Rest siehe Tabelle oben) ·
Umsetzungsreihenfolge und verifizierte Fix-Rezepte in
`plan/sicherheits-audit-2026-07.md`.

**Archiviert (Befundgruppe vollständig behoben/akzeptiert)** — [archiv/](archiv/):
[01-kritisch-hoch.md](archiv/01-kritisch-hoch.md) ·
[compliance.md](archiv/compliance.md) ·
[core-lohn.md](archiv/core-lohn.md) ·
[modelle-serialisierung.md](archiv/modelle-serialisierung.md) ·
[navigation-bootstrap.md](archiv/navigation-bootstrap.md) ·
[provider-state.md](archiv/provider-state.md) ·
[screens-ui.md](archiv/screens-ui.md) ·
[services-firestore.md](archiv/services-firestore.md) ·
[services-persistenz.md](archiv/services-persistenz.md) ·
[sicherheit.md](archiv/sicherheit.md) ·
[bestellkorb-kundenwuensche.md](archiv/bestellkorb-kundenwuensche.md) ·
[test-luecken.md](archiv/test-luecken.md)
