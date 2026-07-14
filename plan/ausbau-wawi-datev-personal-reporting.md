# Ausbau-Plan: Warenwirtschaft · DATEV · Personal · Reporting

**Stand:** 13.07.2026 · **Status:** Welle 1 abgeschlossen (WW-1, WW-3, PERSONAL-1, REPORTING-1, REPORTING-2, DATEV-1, DATEV-2 umgesetzt + adversarisch reviewt, 3 Befunde gefixt; WW-2 bereits vorab gelandet) · flutter analyze 0 Issues, 1914 Tests grün · Welle 2 begonnen: Q2 + PERSONAL-2 + PERSONAL-3 + DATEV-3 + Q1 + REPORTING-3 + REPORTING-4(Kern) + PERSONAL-4 + PERSONAL-9/Q4 umgesetzt (DATEV-Strecke Finanz+Lohn end-to-end + Management-Dashboard /kennzahlen) · Deploy des `financeConfig`+`datevExportRuns`-Rules/Index steht aus (Q0) · **Erstellt aus:** Multi-Agent-Analyse (je Bereich Ist-Analyse → Design → adversarische Prüfung gegen die Codebasis; 44 Prüf-Befunde eingearbeitet) + zwei Betreiber-Review-Runden vom 12.07.2026 (Runde 1: 9 Befunde — u. a. Q1 global, Lohn-`rowsSnapshot`, Zähl-Events statt Last-Write-Wins, `systemKind`, `visibleSince`/`openedAt`; Runde 2: 8 Befunde + 2 Ergänzungen — u. a. Q1-Offline-Positivliste, Inventur-Stale-Prüfung, Finanz-„Neu aufbauen & vergleichen", Rules-Transition-Matrix, Q6 Migrations-Matrix, Q7 Job-Monitoring, Schema-Versionen; Runde 3 vom 13.07.2026: 5 Befunde — Konflikt-Vollständigkeit als dokumentierte Client-Invariante statt Rules-Illusion, vollständige Run-Feldliste als Allowlist-Quelle, Run-Create-Härtung gegen Backdating, DSGVO-`subjectUserIds`, drei präzise Verlustfreiheits-Stufen)

## Ziel & Scope

Vier Ausbau-Pakete auf bestehender, verifizierter Substanz — kein Neubau:

1. **Warenwirtschaft:** persistente Inventurprozesse, offene Bestellmengen, Lieferavis, professioneller Wareneingang.
2. **DATEV:** Prüflauf, Export-Historie, Festschreibung (GoBD), Zahlarten-/Kassen-/USt-Mapping.
3. **Personal:** echte Lohnexporte (DATEV Lohn), Vertrags-/Dokumentenfreigaben, Qualifikations- und Ablaufmanagement.
4. **Reporting:** Management-Dashboards, Standortvergleich, rollen-gesteuerte Kennzahlen.

**Nicht im Scope:** OktoPOS-Ausbau, EDI-/E-Mail-Import von Lieferavisen, E-Mail-Versand (existiert nicht als Infrastruktur), Employee-Dashboard („employee nur Eigenes" deckt /statistik + /monatsbericht bereits ab).

**Leitplanken (gelten für JEDEN Meilenstein):** Zwei-Serialisierungs-Regel (alle Stellen je Feld), Drei-Speichermodi-Mutator-Muster, Provider lazy Cloud-Repo, AuditSink nur auf Erfolgs-Pfaden (nur `AuditAction`-Enum-Werte `created/updated/deleted/corrected` — die Rules whitelisten exakt diese vier Strings; fachliche Unterscheidung über `entityType` + deutsche `summary`), Rules `sameOrg` + Feld-Allowlists, `where`+`orderBy` → Composite-Index, deutsche UI-Texte + `DateFormat('de_DE')`, `appColors`, Tests offline mit Fakes. **Neue persistierte Snapshot-/Export-Strukturen (`datevExportRuns` inkl. `rowsSnapshot`/`entriesSnapshot`, Inventur-`diffSummary`, DATEV-/Lohn-Config) tragen ein `schemaVersion`-Feld (int, ab 1); Leser parsen tolerant mit Default 1** — Format-/Lohnarten-Änderungen bleiben so später migrierbar. Definition of Done je Meilenstein: `flutter analyze` (0 Issues) + `flutter test` grün (+ Node-Tests bei functions-Änderungen).

---

## Q — Querschnitts-Bausteine (VOR bzw. quer zu den Bereichen)

### Q0: Commit-Hygiene + Sammel-Deploy (Vorbedingung für alles) — Status: TEILWEISE (Welle-1+2-Code committet 93859ee + firestore:indexes/rules auf taskmaster-ebcez deployt; offen: alter functions/hosting-Stau)
Der bekannte Deploy-Stau ist die größte Einzelabhängigkeit: neue Rules-/Index-abhängige Features laufen sonst im hybrid-Modus still in den lokalen Fallback (`_tryFirestore` wertet `permission-denied` als offline).
- Uncommittete Arbeit des Branches `probleme-abarbeitung-2026-07-12` committen, Branch mergen/pushen.
- `plan/deploy-checkliste.md` abarbeiten: `firebase deploy --only firestore:indexes` → `firestore:rules` → `storage` → `functions` → `hosting` (genau diese Reihenfolge; functions-Deploy ist wegen `overtimeMinutes`/destruktivem `toFirestoreShift` der dringendste Posten; danach `rebuildPosDailyStats`-Backfill für die Reporting-Trends).
- **Geltungsbereich (Review-Befund):** Diese Reihenfolge gilt für den AKTUELLEN Deploy-Stau. Neue Features dieses Plans definieren ihre Deploy-Reihenfolge je Meilenstein selbst — sie KANN abweichen (Beispiel REPORTING-7: functions VOR rules, sonst bricht Teamlead-Lesen kurz).
- Smoke-Tests nach Deploy (fridge_refill am Kiosk, Wareneingang gegen Bestellung, stocktake im hybrid-Modus — AppLogger-Warnungen beobachten).
- **Aufwand:** S (keine Codeänderung) · **blockiert:** WW-4/5/8/9/10, DATEV-6, PERSONAL-3/4/5/7, REPORTING-7/8.

### Q1: Globale Architekturregel — Hybrid-Fallback nur bei echten Offline-Fehlern (Positivliste) — Status: ERLEDIGT (Welle 2: zentraler Mixin lib/core/hybrid_write_fallback.dart via isTransientError; Finance/Personal/Inventory _tryFirestore delegiert; CLAUDE.md-Kopplung #8b + Test-Konvention FirebaseException(unavailable); 6 Offline-Sim-Tests von Exception(offline)→transient umgestellt)
Zwei Prüfer haben unabhängig dieselbe Fehlerklasse gefunden: Der hybrid-Fallback (`FinanceProvider._tryFirestore` u. a.) fängt JEDEN Fehler — auch einen Rules-Deny — und schreibt dann lokal weiter, inkl. Audit-Eintrag. Das unterläuft jede Rules-Härtung still und versteckt echte Bugs.
- **Regel als POSITIVLISTE (gilt projektweit; Review-Befund: Negativliste reicht nicht):** Der lokale Fallback greift NUR bei expliziten Offline-Codes — `unavailable`, `deadline-exceeded` und echten Netzwerk-/Socket-Fehlern. **ALLE anderen Codes scheitern sichtbar** (rethrow, deutsche Fehlermeldung, KEIN Audit): `permission-denied`/`unauthenticated` (Rules-Deny), `failed-precondition` (z. B. fehlender Composite-Index — sähe sonst wie „offline" aus!), `invalid-argument`, `resource-exhausted`, `unknown`. Präzedenz: Hybrid-Spiegel-Clobber-Fix aus dem Scanner-Paket. Als Kopplungs-Regel in CLAUDE.md aufnehmen: „Neuer Hybrid-Mutator → Offline-Positivlisten-Muster + Test".
- **Gilt für ALLE Schreibpfade, die dieser Plan einführt oder härtet** — nicht nur DATEV-4/WW-8: `deliveryAdvices` (WW-4), `inventoryCountSessions`+lines (WW-8/9), `financeConfig` (DATEV-1), `datevExportRuns` (Q2), `financePeriodLocks`+Journal (DATEV-4), Dokument-Workflow-Felder (PERSONAL-4), `employeeQualifications` (PERSONAL-6), `markAsRead` der Inbox (PERSONAL-9). Jeder dieser Meilensteine bekommt Tests „Rules-Deny → Fehler sichtbar, KEIN lokaler Write, KEIN Audit" UND „`failed-precondition` → Fehler sichtbar, kein stiller Fallback".
- Bestehende Fallback-Helfer (Finance, Inventory, Personal) zentral umstellen — ein gemeinsamer Helfer/Mixin statt n Kopien, damit die Unterscheidung nicht pro Provider divergiert.
- **Aufwand:** M · **gehört zeitlich VOR** DATEV-4 und WW-8/9; neue Pfade wenden das Muster von Anfang an an.

### Q2: EINE gemeinsame DATEV-Export-Historie (löst Plan-Konflikt auf) — Status: ERLEDIGT (Welle 2: Model+Service+Rules+Index+Tests; Rules/Index-Deploy offen)
Die Bereichs-Designs planten zwei konkurrierende Collections (`datevExportRuns` in DATEV-3, `datevExports` in PERSONAL-3). **Entscheidung: eine Collection `organizations/{orgId}/datevExportRuns`** für Finanz- UND Lohn-Exporte:
- **Vollständige Feldliste (Review-Befund: die Rules-Allowlist wird EXAKT hieraus gebaut — fehlende Felder würden legitime Runs blockieren):** `orgId` (Pflicht — die create-Rule prüft den Pin!), `schemaVersion` (int, ab 1), `exportArt` (Enum `finanz`/`lohn`, `.value`/`fromValue`-Default), `kind` (z. B. `extf_buchungsstapel`, `lodas_bewegungsdaten`), `periodYear`/`periodMonth?`, `createdByUid`, `createdAt` (serverTimestamp), `entryCount`, `sollCents`/`habenCents` bzw. `summeCents`, `fileName`, `fileSha256`, `generatedAtMillis?` + `configSnapshot?` (Finanz-Reproduktion), `rowsSnapshot?` (Lohn, s. u.), `entriesSnapshot?` (Finanz, s. u.), `snapshotTruncated` (bool) + `snapshotRowCount` (int — Transparenz, wenn die Snapshot-Grenze griff), `subjectUserIds` (List&lt;String&gt; — DSGVO-Auffindbarkeit, s. u.), `acceptedWarningCodes`/`problemeAnzahl` (Prüflauf-/Vorprüfungs-Übernahmen), `monatFestgeschrieben` (bool) + `overrideBestaetigt` (bool — GoBD: Override trotz Warnung wird festgehalten), `note?`.
- Cloud-only + immutabel wie `CashClosing` (nur `fromFirestore`/`toFirestoreMap`, kein `toMap`, kein `copyWith` — dokumentierte Ausnahme von der Dual-Regel). ROHDATEI wird NICHT persistiert (1-MiB-Risiko bei Jahres-Journalen).
- **Reproduzierbarkeit je Export-Art (revisionssicher):** **Lohn** darf NICHT aus Live-Daten neu gebaut werden (Mitarbeiterdaten/Personalnummern/Lohnarten/Config können sich nachträglich ändern) → der Run speichert einen **kanonischen `rowsSnapshot`** (Liste `{personalnummer, lohnartNr, mengeStunden?, betragCents?}`) + `configSnapshot`; der Re-Download baut die Datei ausschließlich aus dem Snapshot (Grenze ~1000 Zeilen dokumentieren/prüfen, sonst kein Re-Download, nur Metadaten). **Finanz (Review-Befund: Live-Rebuild ist nicht verlustfrei):** die Aktion heißt ehrlich **„Neu aufbauen & vergleichen"** — Rebuild aus Live-Journal + `configSnapshot` + `generatedAtMillis`, Hash-Vergleich, Abweichung = deutliche Warnung „Journal seit Erstellung verändert". Zusätzlich speichert der Run einen kompakten kanonischen **`entriesSnapshot`** (Exportzeilen) bis zu einer dokumentierten Grenze (~2000 Zeilen — dann ist auch Finanz byte-identisch reproduzierbar); darüber nur Metadaten + Rebuild-mit-Vergleich. Die HARTE Unveränderlichkeits-Garantie liefert die Kombination mit DATEV-4: nach Festschreibung des Zeitraums ist das Journal unveränderlich → empfohlener Flow bleibt „exportieren, dann festschreiben".
- **Semantik/UX mit präzisen Verlustfreiheits-Stufen (Review-Befund: nicht pauschal „verlustfrei" behaupten):** Ein Run dokumentiert die **Erstellung** (Historie heißt „Erstellte Exporte", nicht „Exportiert"); Runs bleiben immutabel (bewusst kein mutierbares `downloadState`-Feld an einem append-only-Doc). Drei Stufen, in der UI je Run unterscheidbar ausgewiesen: (1) **Lohn** = byte-identischer Re-Download aus `rowsSnapshot`; (2) **Finanz MIT `entriesSnapshot`** = byte-identischer Re-Download; (3) **Finanz OHNE Snapshot** (`snapshotTruncated == true`) = nur „Neu aufbauen & vergleichen" — byte-Identität dort NUR garantiert, wenn der Zeitraum festgeschrieben ist (DATEV-4). Ein fehlgeschlagener Download ist in Stufe 1+2 verlustfrei wiederholbar, in Stufe 3 nur nachvollziehbar (Hash-Vergleich).
- **Schema-Version:** Runs + Snapshots tragen `schemaVersion` (int, ab 1; s. Leitplanken) — spätere DATEV-Format-/Lohnarten-Änderungen bleiben nachvollziehbar und migrierbar.
- **DSGVO/Aufbewahrung (präzisiert — Review-Befund: Kappungs-Mechanik war unscharf):** Datenminimierung im `rowsSnapshot` — nur Personalnummer/Lohnart/Menge/Betrag, KEINE Klarnamen; Zugriff admin-only (Rules) + Audit-Eintrag je Erstellung. **Entscheidung:** Die Personalnummer BLEIBT im Snapshot (steuerliches Ordnungsmerkmal, gesetzliche Aufbewahrungspflicht — Art. 17 Abs. 3 lit. b DSGVO deckt das Behalten); Runs werden bei Account-Löschung weder gelöscht noch verändert (immutabel). Der Klarnamen-Bezug lebt allein im Profil und wird DORT durch die bestehende Anonymisierungs-Strecke gekappt (Marker `geloescht:<hash>`). Für Auskunfts-/Löschersuchen (Art. 15/17) trägt der Run zusätzlich `subjectUserIds` — `deleteUserAccount` findet betroffene Runs per `array-contains`, löscht sie NICHT, sondern vermerkt die Aufbewahrungspflicht im Löschprotokoll; endgültige Löschung erst nach Fristablauf (offene Frage 14). Löschkonzept/Aufbewahrung im Datenschutz-Text (`APP_LEGAL_*`-Seiten bzw. interne Doku) ergänzen.
- **Rules (gehärtet — Review-Befund: Historienartefakt gegen Backdating/kaputte Docs schützen):** `read`/`create` nur `isAdmin() && sameOrg(orgId)`; create zusätzlich `createdByUid == request.auth.uid` + `createdAt == request.time` (kein Backdating — Client MUSS serverTimestamp senden) + `request.resource.data.orgId == orgId` + `schemaVersion is int` + `exportArt in ['finanz','lohn']` + `fileSha256.matches('^[a-f0-9]{64}$')` + `keys().hasOnly`-Allowlist über die VOLLSTÄNDIGE Feldliste oben; `update`/`delete: false`. Emulator-Deny-Tests: Backdating, fremde Org, kaputter Hash, unbekanntes Feld.
- Index: 1 Composite `datevExportRuns(exportArt ASC, createdAt DESC)` in `firestore.indexes.json` (Historie filtert nach Art).
- Offline-Semantik: hybrid-offline → Export **blockieren** („erst wieder online exportieren"); reiner local-Modus → Export erlaubt mit deutlichem „ohne Historie"-Hinweis. Reihenfolge immer: Run-Doc schreiben, DANN Download.
- **Aufwand:** M · **Konsumenten:** DATEV-3 (Finanz), PERSONAL-3 (Lohn).

### Q3: Push-Kategorie-Kopplung (für alle neuen Nightlies) — Status: offen
WW-5, PERSONAL-5 und PERSONAL-7 legen neue Push-Kategorien an. Jede neue Kategorie braucht **immer dieses Kopplungs-Set** (vom Prüfer als Lücke belegt): `functions/push_notifications.js` (Notification-Builder + `channelIdForType`-Case) ↔ `lib/services/push_messaging_service.dart` `_channelIdForType` (deckungsgleicher Dart-Spiegel inkl. Android-Channel) ↔ `lib/models/notification_prefs.dart` (neuer Kanal-Bool, dual serialisiert) ↔ Prefs-Checkbox in den Benachrichtigungs-Einstellungen.

### Q4: Mitteilungs-Inbox (PERSONAL-9, vorgezogen als Querschnitts-Baustein) — Status: ERLEDIGT (= PERSONAL-9)
Ohne Inbox-Leser sind ALLE server-erzeugten Erinnerungen (Lieferung WW-5, Dokumente PERSONAL-5, Quali PERSONAL-7, bestehendes MHD) für Nutzer ohne aktiviertes Push unsichtbar (`APP_PUSH_ENABLED` Default aus). Details unter PERSONAL-9 — hier nur die Einordnung: **vor bzw. parallel zu den ersten Nightlies bauen.**

### Q5: Rollen-/Rechte-SSoT fürs Reporting — Status: ERLEDIGT (= REPORTING-1 KpiPermissions)
`KpiPermissions` (REPORTING-1) ist der gemeinsame Sichtbarkeits-Katalog für Dashboard, Detail-Screens und Home-Kacheln — **permission-basiert** (`canViewReports`, `canManageShifts`, `isAdmin`), nicht rollenbasiert (Prüf-Befund: die bestehenden Gates sind Flag-basiert und per User überschreibbar).

### Q6: Migrations-/Backfill-Matrix (Review-Befund: bisher nur verstreut) — Status: offen
Gesammelte Bestandsdaten-Behandlung — jeder Punkt gehört als expliziter Schritt/Test in den jeweiligen Meilenstein:

| Migration | Bestand ohne Feld/alt | Verhalten |
|---|---|---|
| `PayrollRecord.istMinutes` (PERSONAL-1) | Alt-Records ohne Stunden | KEIN automatischer Backfill (damaliges Ist nicht sicher rekonstruierbar); Export meldet „Grundlohn ohne Stundenmenge" in der Problem-Liste; optional manueller Backfill aus `zeitkontoSnapshots` je Monat |
| `EmployeeDocument.visibleSince` (PERSONAL-4/5) | Bestands-Dokumente | Fallback `createdAt` (Leser + Nightly nutzen `visibleSince ?? createdAt`), dokumentiert |
| `JournalEntry.date` → 12:00 (DATEV-4) | Mitternachts-Timestamps (Editor/Personalkosten) | VOR dem Rules-Guard entscheiden: Einmal-Migration (Admin-Aktion, normalisiert Alt-Docs) ODER dokumentierte Rules-Toleranz für Alt-Bestand — sonst schlagen Updates/Deletes an Bestandsbuchungen gegen den falschen Monat |
| Lokale DATEV-Config → Cloud (DATEV-1) | gerätelokale `datev_config` | Einmal-Migration beim ersten Cloud-Load (Initial-Doc + Audit `created`) — bereits im Meilenstein geplant |
| NotificationPrefs neue Kanäle (Q3: lieferung/dokumente/quali) | Prefs-Docs ohne neuen Bool | fehlender Bool = Kategorie-Default (Entscheidung je Kategorie, s. offene Fragen); `pushAllowed`-Leser tolerant |
| OrgSettings-Defaults (PERSONAL-7/8) | fehlende Felder | tolerantes Parsing → Defaults (Vorlauf 30, `enforceQualiAblaufHard` true) |
| Rules-/Index-Rollback | — | neue Felder immer optional (vorwärts-kompatible Rules); vor jedem Deploy-Paket letzten funktionierenden Rules-/Index-Stand per git-Tag markieren; Index-LÖSCHUNGEN erst nach bestätigtem Prod-Betrieb |

### Q7: Monitoring/Runbook für Nightlies, Backfills & Scheduled Functions — Status: offen
Mit WW-5, PERSONAL-5 und PERSONAL-7 wachsen die Scheduler auf ≥5 (plus bestehende `expiryWarningNightly`/`oktoposNightlySync`) — ohne Sichtbarkeit fällt ein toter Nightly niemandem auf.
- Gemeinsamer **Job-Status-Wrapper** für alle onSchedule-Functions: schreibt je Lauf `organizations/{orgId}/jobStatus/{jobName}` (letzter Start/Ende, Erfolg/Fehler, verarbeitete Zähler, gekürzte Fehlermeldung) via Admin SDK; Rules: read admin-only, Client-Writes verboten (kein create/update-Block). Strukturiertes Logging (ohne PII) bleibt daneben bestehen.
- Admin-Sicht: kleine „System-Jobs"-Karte im Einstellungen-Hub (admin-only): letzte Laufzeit + Status je Job; Erstausbau der manuellen Wiederholung über den dokumentierten Firebase-Console-Weg (Runbook), optional später eine admin-only Callable `runJobNow`.
- **Runbook-Abschnitt** (in `plan/deploy-checkliste.md` oder `docs/`): je Job — was er tut, wie man ihn manuell wiederholt, warum Wiederholung dank `dedupeId` idempotent ist, wie man Dedupe-Docs kontrolliert; plus Backfill-Prozeduren (`rebuildPosDailyStats`).
- **Aufwand:** S–M · **Abhängig:** erste neue Nightly (WW-5 oder PERSONAL-5/7); Rules-Block mit dem jeweiligen Paket deployen.

---

## A — Warenwirtschaft (WW-0 … WW-10)

**Ist-Basis (verifiziert):** `PurchaseOrderItem.outstandingQuantity`/`deriveReceiptStatus`/`isFullyReceived(>=)` existieren fertig; `PurchaseOrder.expectedAt` ist voll dual serialisiert, aber ohne jede UI („totes Feld"); `receivePurchaseOrder` ist eine atomare, idempotente Transaktion mit beidseitigem Mengen-Clamp (Repo + `_applyLocalReceipt`); der Inventur-Screen `/inventur` zählt rein in-memory (`_countControllers`); `recordStocktake→setProductStock` ist gehärtet (H9); `StockMovement.externalRef` ist in der Rules-Allowlist; MHD/Charge-Sheet (`goods_receipt_sheet.dart`) existiert Scanner-seitig; Nightly-Muster `expiryWarningNightly`+`fanOutPush` existiert.

### WW-0: Deploy-Stau auflösen — Status: offen
= Q0 (siehe oben). Vorbedingung für alle Rules-/Index-abhängigen WW-Meilensteine.

### WW-1: Offene Bestellmengen sichtbar + in Nachbestell-Logik verrechnet — Status: umgesetzt (13.07.2026)
Deploy-frei, kleinster Schritt des gesamten Plans.
- `InventoryProvider`: Getter `incomingQuantityByProductId({siteId})` (Summe `outstandingQuantity` über Orders in `ordered`/`partiallyReceived`).
- `lib/core/reorder_suggestion.dart`: optionaler Parameter `incomingByProductId` (pure bleiben) — offene Menge senkt den Vorschlag; Aufrufstelle im Provider durchreichen.
- `lowStockProducts`: „unterwegs"-Verrechnung; Artikel mit ausreichender unterwegs-Menge im UI als „bestellt, unterwegs" kennzeichnen statt verschwinden lassen.
- `inventory_screen.dart`: „offen X von Y Stk."-Chip je Bestellung (`appColors.warning` bei Teillieferung), „unterwegs"-Badge am Artikel.
- **Bekannte Grenze (dokumentieren):** der serverseitige Meldebestand-Push `onProductWritten` kennt offene Bestellmengen nicht und pusht ggf. weiter — Push bleibt bewusst konservativ; Folgeticket optional.
- **Dateien:** `lib/providers/inventory_provider.dart`, `lib/core/reorder_suggestion.dart`, `lib/screens/inventory_screen.dart` · **Rules/Indexe:** keine · **Tests:** `reorder_suggestion_test.dart` erweitern; Provider-Test über Fake-Orders in allen drei Status (Mengen nie als int asserten) · **Aufwand:** S

### WW-2: „Rest schließen" für Teillieferungen + Wareneinsatz auf Ist-Liefer-Basis — Status: ERLEDIGT (vorab gelandet, grün)
- Model: `PurchaseOrder` + `closedAt` (DateTime?) / `closedReason` (String?) — je 4 Serialisierungs-Stellen + `clearClosedAt`/`clearClosedReason`; Getter `deliveredTotalCents` (Summe `quantityReceived × unitPriceCents`, Steuerbehandlung wie `totalCents`).
- Semantik: Schließen setzt `status=received` + `closedAt` + Pflicht-Begründung; `deriveReceiptStatus` bleibt unverändert (expliziter Override).
- Repo: `closePurchaseOrderRemainder(orgId, orderId, reason)` als Transaktion (nur aus `ordered`/`partially_received` und `hasAnyReceipt`).
- **Guard (Prüf-Befund hoch, eingearbeitet):** `receivePurchaseOrder` UND `_applyLocalReceipt` werfen bei `closedAt != null` deutschen `StateError` — sonst flippt ein Nach-Schluss-Eingang den Override zurück auf `partially_received` und korrumpiert die Wareneinsatz-Basis. UI blendet „Wareneingang buchen" bei geschlossenen Bestellungen aus. Test: Eingang nach Schließen ist Fehler in Cloud- UND Local-Pfad.
- Finanz-Kopplung: `postPurchaseOrderCost` bucht bei `closedAt != null` `deliveredTotalCents` statt `totalCents`; **auch der Guard** (`totalCents <= 0 → return`) muss auf die jeweils wirksame Basis umgestellt werden (Testfall „Schließen ohne Liefer-Wert bucht nichts"). Journal-Idempotenz `po-<id>` unverändert.
- Provider: Drei-Modi-Muster nach Vorlage `receiveOrder`; `_audit?.call` nur auf Erfolgs-Pfaden.
- **Dateien:** `lib/models/purchase_order.dart`, beide Inventory-Repos, `lib/providers/inventory_provider.dart`, `lib/providers/finance_provider.dart`, `lib/screens/purchase_order_screens.dart` · **Rules:** keine (purchaseOrders-Block hat keine Feld-Allowlist, verifiziert) · **Aufwand:** M

### WW-3: `expectedAt` aktivieren — Liefertermin + „heute erwartet" (Minimal-Avis, deploy-frei) — Status: ERLEDIGT (Welle 1)
- Editor: Datums-Picker „Liefertermin (erwartet)" (`copyWith(expectedAt:)`/`clearExpectedAt` existieren); Anzeige in Detail + Bestellliste; Badges „heute erwartet" (`appColors.info`) / „überfällig" (`appColors.warning`).
- Provider-Getter `expectedDeliveries({day})` clientseitig aus den gestreamten Orders (kein Query, kein Index); Filter-Chip „Erwartet"; Hinweis-Karte „X Lieferungen heute erwartet" im Warenwirtschafts-Kopf.
- **Dateien:** `purchase_order_screens.dart`, `inventory_screen.dart`, `inventory_provider.dart` · **Aufwand:** S

### WW-4: Lieferavis als eigene Collection `deliveryAdvices` — Status: ERLEDIGT (13.07.: Backend Model/Provider/Repo/Rules bereits Welle-3; UI 14.07.: Editor-Sheet `delivery_advice_sheet.dart` + Verwaltungs-Screen `delivery_advice_screen.dart` imperativ via Navigator.push, „Avis erfassen"/„Lieferavise…" im Bestell-Detail-Menü mit Vorbefüllung aus offenen Mengen + purchaseOrderId-Bezug; Statuswechsel markAdviceReceived/cancelAdvice + 5 Tests. Rules-Deploy offen.)
Für Fälle, die `expectedAt` nicht abdeckt (Avis ohne/über mehrere Bestellungen, avisierte Mengen je Position).
- Neues Model `lib/models/delivery_advice.dart`: `DeliveryAdvice` + eingebettete `DeliveryAdviceItem` + Enum `DeliveryAdviceStatus{announced, received, cancelled}` (`.value` snake_case, `fromValue`-Default, deutsche Labels). `expectedDate` auf 12:00 normalisiert + `expectedDay` 'YYYY-MM-DD' (ProductBatch-Muster). Voll dual serialisiert + `clearX`-Flags; kein Callable-Pfad.
- Repo `watch/save/deleteDeliveryAdvice` (komplette Org-Collection streamen, Muster `watchPurchaseOrders`); `DatabaseService`-Key `delivery_advices` in `_orgScopedCollectionKeys` (Kopplung #5); Provider-CRUD im Drei-Modi-Muster, `_audit` auf Erfolgs-Pfaden; Getter `advicesExpectedToday` (speist die „heute erwartet"-Karte aus WW-3 mit).
- UI: „Avis erfassen" am Bestell-Detail (Positionen aus offenen Mengen vorbefüllt), Abschnitt „Angekündigt" + Editor-Sheet (imperativ, kein Route → Kopplung #7 entfällt bewusst).
- **Rules:** neuer Block `deliveryAdvices`: read `sameOrg && !isKiosk()`; create/update/delete `canManageInventory()` + orgId-Pin + `keys().hasOnly`-Allowlist + Status-Enum-Check (Muster productBatches/stockMovements). **Indexe:** keine (kein where+orderBy).
- **Aufwand:** M · **Abhängig:** WW-3 (gemeinsame Anzeige), Q0 (Rules-Deploy vor Go-Live)

### WW-5: Push-Erinnerung „heute erwartete Lieferungen" (Nightly) — Status: offen
- `functions/index.js`: `deliveryReminderNightly` (onSchedule, Region `europe-west3`): je Org Bestellungen mit offenem Status + `expectedAt` heute sowie Avise `announced` + `expectedDay==heute`. **Query-Entscheidung (Prüf-Befund eingearbeitet):** purchaseOrders nur mit `status`-Equality-Filter abfragen und das `expectedAt`-Tagesfenster **in JS in-memory filtern** (Org-Volumen klein) → bewusst KEIN neuer Composite-Index. Avis-Query (2 Equalities) braucht ohnehin keinen.
- `fanOutPush` an Nutzer mit Inventar-Verwaltungsrecht, `dedupeId 'delivery-<orgId>-<tag>-<docId>'`; deutsche Texte, keine Preise/PII.
- **Kopplungs-Set Q3 vollständig:** neue Kategorie `lieferung` in `functions/push_notifications.js` (Builder + `channelIdForType`) + Dart-Spiegel `push_messaging_service.dart` + `notification_prefs.dart` + Prefs-UI. Default: aus für Bestandsnutzer (offene Frage bestätigen).
- **Deploy:** `--only functions` · **Tests:** Node (dedupeId, Empfängerfilter, Tagesfenster Europe/Berlin) · **Aufwand:** S–M · **Abhängig:** WW-3+4, Push-Infra-Deploy (`APP_PUSH_ENABLED`, APNs), Q4 (Sichtbarkeit ohne Push)

### WW-6: Wareneingang Pro I — geführtes Sheet gegen Bestellung (MHD/Charge, Lieferschein-Nr., Ist-EK) — Status: offen
Ersetzt den schlichten `_ReceiveDialog`; generalisiert das Scanner-MHD/Charge-Muster auf den Bestell-Wareneingang (= AP1 aus `plan/gpt_vergleich_2026-07-12.md`).
- Model: `PurchaseOrder.deliveryNoteNumber` (String?), `PurchaseOrderItem.receivedUnitPriceCents` (int?) — je 4 Stellen + `clearX`. Übergabetyp `PurchaseReceiptLine {quantity, receivedUnitPriceCents?, expiryDate?, batchNote?}` (nicht persistiert).
- Repo: `receivePurchaseOrder`-Signatur `Map<int,int>` → `Map<int,PurchaseReceiptLine>`; Transaktion schreibt Ist-EK + Lieferschein-Nr.; Clamp/Idempotenz/Reads-vor-Writes unverändert. **Aufrufer-Migration inkl. `lib/services/firestore_service.dart`-Wrapper** (Prüf-Befund: delegierende Methode ~Z. 2556 mitmigrieren).
- ProductBatch-Anlage NACH erfolgreicher Transaktion via `saveProductBatch` (wie Scanner-Flow) — **Teilerfolg absichern (Review-Befund):** deterministische Batch-Doc-ID `po-<orderId>-<itemIndex>` (Wiederholung idempotent); schlägt die Batch-Anlage nach gebuchtem Bestand fehl, wird ein Pending-Merker gehalten und beim nächsten Öffnen des Bestell-Details sichtbar „MHD/Charge nachtragen" angeboten (Retry legt dank deterministischer ID genau einen Batch an). Test: Batch-Save wirft injiziert → Bestand gebucht, Retry erzeugt den Batch exakt einmal. Ist-EK-Abweichung → `priceHistory`-Eintrag + Toggle „Einkaufspreis am Artikel aktualisieren?".
- UI: neues `lib/widgets/purchase_receipt_sheet.dart` (aus `goods_receipt_sheet.dart` generalisieren, nicht kopieren): Kopf Lieferschein-Nr., je offene Position Menge (Default = outstanding) + aufklappbar MHD/Charge/Ist-EK.
- Hybrid-Parität: `_applyLocalReceipt` schreibt dieselben Felder (Cloud-lokal-Parität testen). `deliveredTotalCents` (WW-2) bevorzugt ab jetzt `receivedUnitPriceCents`, Fallback `unitPriceCents` — Wareneinsatz-Kopplung explizit testen.
- **Rules:** keine (Allowlists decken alles, verifiziert) · **Aufwand:** L · **Abhängig:** WW-2

### WW-7: Wareneingang Pro II — Übermengen, Abweichungsprotokoll, Eingang gegen Avis — Status: ERLEDIGT (14.07., f913285 + Folge-Commit)
> **Abweichung vom Plan (bewusst):** „Aufnahme ins Bestell-PDF" NICHT umgesetzt — das einzige Bestell-PDF (`generatePurchaseOrderDocument`) ist lieferantenseitig und bewusst OHNE interne EK-/Eingangsdaten; das Abweichungsprotokoll dort würde interne Eingangsdaten an den Lieferanten leaken. Stattdessen In-App-Anzeige (warnfarbene Karte im Bestell-Detail, nur bei echtem Eingang + Abweichung). Ein interner Eingangs-PDF-Export existiert (noch) nicht als Surface.
- Übermengen: `PurchaseReceiptLine.allowOverdelivery` (UI-Toggle „Mehrlieferung zulassen"); Clamp an BEIDEN Stellen über einen **gemeinsamen pure Helfer** `effectiveReceiptQuantity(...)` in `purchase_order.dart` lockern (beendet die Clamp-Divergenz-Gefahr strukturell). `isFullyReceived` nutzt bereits `>=` → Status/Wareneinsatz tragen Mehrmengen.
- Abweichungsprotokoll: pure `lib/core/receipt_deviation.dart` — `computeReceiptDeviations(PurchaseOrder)` (bestellt/geliefert/Differenz/EK-Abweichung/closedReason), Anzeige im Bestell-Detail + Aufnahme ins Bestell-PDF (`pdf_service.dart`).
- Eingang gegen Avis: Avis-Aktion „Wareneingang starten" — mit `purchaseOrderId` → `purchase_receipt_sheet` vorbefüllt; ohne Bezug → freier Eingang über `showGoodsReceiptSheet`; Erfolgspfad setzt Avis auf `received` + Audit. GS1-Vorbefüllung optional.
- **Tests:** Paritäts-Test Cloud vs. lokal für `effectiveReceiptQuantity` (ein Test, beide Pfade) · **Aufwand:** M · **Abhängig:** WW-6; Avis-Pfad braucht WW-4

### WW-8: Persistente Inventur-Sessions (anlegen, unterbrechen, fortsetzen, mehrgerätefähig) — Status: offen
= AP3 aus `plan/gpt_vergleich_2026-07-12.md`. Ersetzt die In-Memory-Zählung durch `inventoryCountSessions`; die Buchung bleibt bei `recordStocktake`.
- Model `lib/models/inventory_count_session.dart`: `InventoryCountSession` + `InventoryCountEvent` + Enum `InventoryCountStatus{open, completed, cancelled}`. Layout: `organizations/{orgId}/inventoryCountSessions/{sessionId}` + Subcollection `lines/{lineId}` — **append-only Zähl-EVENTS statt Last-Write-Wins** (Review-Befund: stilles Überschreiben fremder Zählungen ist für Inventur fachlich zu schwach). Jedes Event: productId, productName, countedQuantity, stockAtCount, countedAt/ByUid/ByLabel, bookedAt? (WW-9).
- Konflikt-Semantik: die UI aggregiert Events je productId (aktuell = neuestes Event); zählen ZWEI verschiedene Nutzer denselben Artikel mit **abweichender Menge**, ist das ein sichtbarer Konflikt (Chip „2 Zählungen: 12 / 14") — der Abschluss (WW-9) bleibt blockiert, bis je Konflikt-Artikel eine **maßgebliche Zählung explizit gewählt** wird. Eigene Korrektur = Update des eigenen Events (kein Event-Spam beim Tippen); fremde Zählung korrigieren = eigenes neues Event (Zählhistorie bleibt erhalten, GoBD-freundlich).
- Session-Felder: id, orgId, siteId, title, status, categoryFilter?, startedAt/ByUid/ByLabel, completedAt/ByUid?, totalProducts, countedProducts, resolvedCounts? (Konflikt-Auflösungen: productId → maßgebliche lineId, WW-9), diffSummary? (WW-9). Alles dual serialisiert.
- **Lokaler Spiegel mit Chunking (Review-Befund):** NICHT alle Lines in ein SharedPreferences-Monolith-Objekt — je Session ein eigener Storage-Key (`inventory_count_sessions/<sessionId>`), Events debounce-koalesziert persistiert; **Performance-Test mit 3.000 und 10.000 Zeilen** (Serialisierungs-/Ladezeit) + dokumentiertes Limit. Zähl-DATEN offline puffern, die Bestands-BUCHUNG erst beim Abschluss.
- Provider: `startCountSession`, `recordCount(productId, quantity)` (aktualisiert debounced ~800 ms das EIGENE offene Event des Artikels bzw. legt eines an), `cancelCountSession`, `resumeableSessions`, `conflictsFor(session)`; Audit nur bei Session anlegen/abbrechen (nicht je Zählzeile — Rauschen-Regel).
- Screen-Umbau `/inventur` (Route existiert): Einstieg zeigt offene Sessions („Fortsetzen") oder legt neue an; Controller aus dem Event-Aggregat initialisiert; Fortschrittsbalken; Zähler-Chip je Zeile (wer, wann); Konflikt-Chip.
- **Rules mit expliziter Transition-Matrix (Review-Befund: „update solange open" ist zu grob):** Sessions: read `sameOrg && !isKiosk`; create `canManageInventory` + orgId-Pin + Allowlist + `status=='open'` + `startedByUid==request.auth.uid`; `delete: false`. **Erlaubte Status-Übergänge NUR `open→completed` und `open→cancelled`** (Diff-Check auf `status`), abschließen darf nur `canManageInventory`. **Feld-Allowlist je Update-Typ:** Zähl-Fortschritt (`countedProducts`), Konflikt-Auflösung (`resolvedCounts`), Abschluss (`status`+`completedAt`+`completedByUid`+`diffSummary` zusammen); andere Feld-Kombinationen deny. **Lines (Events): create mit Akteur-Pin (`countedByUid==request.auth.uid`); update nur (a) eigenes Event (Zählwert-Korrektur, Pin auf `resource.data.countedByUid`) oder (b) reine `bookedAt`-Markierung durch den Abschließenden (alle übrigen Felder unverändert); `delete: false`.** Das Event-Modell löst den früheren Rules-Widerspruch (Mehrbenutzer-Abschluss über fremd-gezählte Zeilen) strukturell. **Emulator-Deny-Tests je verbotener Übergang** (completed→open, diffSummary-Nachtrag nach Abschluss, Fremd-Event-Zählwert-Änderung) → ins Deploy-Prüfprotokoll (WW-10/Q0). **Grenze der Rules (Review-Befund hoch):** die VOLLSTÄNDIGKEIT der Konflikt-Auflösung (`resolvedCounts` deckt alle Konflikt-Artikel) kann eine Rule NICHT prüfen — Rules können nicht über die lines-Subcollection aggregieren. Sie ist eine **Client-Invariante** (der WW-9-Abschluss-Flow erzwingt sie, Provider-Tests decken sie) und wird als dokumentierte Enforcement-Grenze in den Rules-Kommentar geschrieben (Muster cashCounts-thirdParty). Wer später serverseitige Härte will: optionaler Folge-Meilenstein „Abschluss als Callable `closeInventoryCountSession`" (Server-Transaktion liest lines, prüft Konflikt-Vollständigkeit + Stale, schreibt Abschluss) — bewusst NICHT im Erstausbau: Abschließende sind ohnehin `canManageInventory`-Leitung, das Restrisiko ist Fehlbedienung, kein Angriff.
- **Repo-API/Index-Entscheidung (Prüf-Befund eingearbeitet):** komplette Session-Collection streamen (Org-Volumen klein), Filter/Sortierung clientseitig → **KEIN Composite-Index** (der ursprünglich geplante `(status, startedAt)` entfällt).
- **Dokumentgrößen-Grenze (Prüf-Befund eingearbeitet):** `diffSummary` enthält NUR echte Differenzen (nicht alle Zeilen — Zählliste kommt aus den line-Docs); Test mit großem Sortiment ergänzen.
- **Tests:** Roundtrips (Session/Event, beide Formate); „App-Neustart" (Provider neu instanziieren, gleiche Mock-Prefs) → Fortsetzen liefert Zählstände; **Mehrbenutzer-Konflikt: zwei Events verschiedener Nutzer mit abweichender Menge werden erkannt und blockieren den Abschluss bis zur Auswahl**; eigene Korrektur erzeugt KEIN zweites Event; bestehende `inventur_screen_test.dart` auf Session-Backing migrieren; Chunking-Performance-Test 3k/10k.
- **Aufwand:** L (größtes Einzelstück) · **Abhängig:** Q0 (Rules-Deploy), Q1 (Deny-Härtung)

### WW-9: Inventur-Abschluss — Konflikt-Auflösung, Differenzbuchung mit Session-Bezug + Historie — Status: offen
- **Vorstufe Konflikt-Auflösung (aus dem WW-8-Event-Modell):** das Diff-Vorschau-Sheet zeigt je Artikel die maßgebliche Zählung (Default: neuestes Event; bei Konflikt — mehrere Nutzer, abweichende Mengen — Pflicht-Auswahl); die Auswahl wird als `resolvedCounts` (productId → lineId) am Session-Doc festgehalten. Ohne vollständige Auflösung kein Abschluss.
- **Stale-Prüfung vor jeder Buchung (Review-Befund hoch):** zwischen `countedAt` und Abschluss können Verkäufe/Wareneingänge liegen — `recordStocktake` bucht ABSOLUT und würde sie überschreiben. Der Abschluss prüft je Artikel, ob seit `countedAt` der maßgeblichen Zählung Bestandsbewegungen existieren (Range-Query der Movements ab `countedAt`, per productId gruppiert — dieselbe Strecke wie `loadInventurMovements`) bzw. ob `currentStock != stockAtCount`. Veraltete Zeilen werden markiert und NICHT gebucht; der Nutzer wählt je Zeile: **Neuzählung** (Default, neues Event) oder **„Bewegungen verrechnen"** (Buchungsziel = gezählte Menge + Bestandsveränderung seit Zählung; die Entscheidung wird in `diffSummary` dokumentiert). Test: Verkauf zwischen Zählung und Abschluss blockiert die Zeile; Verrechnung ergibt das korrekte Absolut-Ziel.
- Optional (offene Frage): Inventur-Betriebsmodus — während einer offenen Session Warnung/Sperre für Bestandsbuchungen des Standorts/der gezählten Kategorie (OrgSettings-Schalter), um Stale-Fälle von vornherein zu minimieren.
- Abschluss bucht je Artikel (auf Basis der maßgeblichen Zählung) über `recordStocktake` mit deterministischer `clientMutationId='inv-<sessionId>-<productId>'` (nach Teilfehler gefahrlos wiederholbar) und `externalRef='inventur:<sessionId>'` (Feld ist allowlisted + dual serialisiert → **kein** Modell-/Rules-Touch an StockMovement). `setProductStock`/`recordStocktake` um `externalRef`-Durchreichung erweitern.
- Teilfehler-Semantik: fehlgeschlagene Artikel bleiben „ungebucht" (`bookedAt?` am maßgeblichen Event), Session bleibt `open` bis alle Diffs gebucht sind; dann `completed` + eingefrorene `diffSummary` (gezählt/vorher/Delta/EK-Bewertung ZUM Abschlusszeitpunkt). Sequenziell buchen mit Fortschritts-UI (bewusst kein Batch — `setProductStock` ist je Artikel transaktional).
- Historie: Abschnitt „Abgeschlossene Inventuren" (read-only; EK-Bewertung nur `canManageInventory`). **Movement-Drilldown über eine ÖFFENTLICHE, getestete Provider-/Repo-Methode `loadInventurMovements(session)`** (Review-Befund: nicht die privaten limitierten Streams anzapfen): limitlose Range-Query um den Session-Zeitraum (Muster `watchStockMovementsInRange`), clientseitig per `externalRef`-Prefix `'inventur:<sessionId>'` gefiltert — bleibt index-frei, deckt alte Sessions ab.
- Schwund-Kopplung: `shrinkage_report.dart` unverändert; Link „Schwund-Auswertung öffnen"; Audit auf Abschluss-Erfolgspfad in jedem Storage-Zweig.
- **Tests:** Konflikt blockiert Abschluss, Auswahl löst; Abschluss bucht Deltas absolut korrekt (aus maßgeblicher Zählung); Idempotenz-Wiederholung no-op; Teilfehler lässt Session open; **`bookedAt`-Markierung auf fremd-gezählten Events** (Mehrbenutzer-Fall gegen die WW-8-Rules); `loadInventurMovements` liefert nur Session-Movements · **Aufwand:** M–L · **Abhängig:** WW-8

### WW-10: Inventur-Protokoll als PDF/CSV + GoBD-Härtung — Status: offen
- `pdf_service.dart`: `generateInventoryCountReport({session, lines, includeValuation})` — Zählliste (Artikel, gezählt, Zähler, Zeitstempel) + bewertete Differenzliste; EK-Bewertung nur bei `includeValuation` (Aufrufer gated `canManageInventory`). `export_service.dart`: `buildInventoryCountCsv` (UTF-8-BOM + `;`, deutsches Excel).
- Protokoll-Inhalt IMMER aus persistierten Daten (`diffSummary`/lines), nie live neu bewertet — Preisänderungen nach Abschluss dürfen das Archiv nicht ändern (Test).
- GoBD-Härtung: Sessions nach Abschluss unveränderlich (WW-8-Update-Regel), lines nach Abschluss nicht mehr schreibbar — Entscheidung offen: Rules-`get()` aufs Parent (1 Read/Write) vs. Client-Enforcement mit dokumentierter Grenze (Muster cashCounts „Korrektur = neue Zählung").
- **Deploy:** `--only firestore:rules` (Verschärfung) · **Aufwand:** M · **Abhängig:** WW-8+9

---

## B — DATEV / Buchhaltung (DATEV-1 … DATEV-6)

**Ist-Basis (verifiziert):** `DatevExport.buildBuchungsstapel` (EXTF) existiert und ist pure/deterministisch (einzige `now()`-Quelle injizierbar); `DatevExportConfig` ist heute **gerätelokal** (SharedPreferences `datev_config`), `saveDatevConfig` ohne Audit; USt-Sätze ohne `revenueAccountByRate`-Eintrag werden heute **still übersprungen**; BU-Schlüssel-Spalte bleibt leer; Kostenarten werden per Namens-Heuristik (`_cashDiffNeedles` u. a.) aufgelöst; es gibt KEINE Finanz-Festschreibung (Vorbild existiert: Monats-Festschreibung PA-5 + Rules-`get()`-Muster); `cashClosings` sind bereits append-only.

**Ausführungs-Reihenfolge (geändert nach Prüf-Befund):** DATEV-1 → 2 → 3 → **5 → 4** → 6. Begründung: Mapping-Felder (`taxRatePercent`/`paymentMethod` an Buchungen) müssen VOR dem Perioden-Lock existieren — sonst können Alt-Buchungen in gesperrten Monaten nie mehr einen BU-Schlüssel bekommen (nur per Storno).

### DATEV-1: DatevExportConfig org-weit heben (`financeConfig/datev`) + Audit — Status: ERLEDIGT (Welle 1; Rules-Deploy offen)
- `DatevExportConfig` bekommt zusätzlich `toFirestoreMap()`/`fromFirestore()` (camelCase-Spiegel); Firestore-Singleton `organizations/{orgId}/financeConfig/datev`; lokaler Spiegel bleibt Fallback/local-Modus.
- **Bewusst EIGENE admin-only Collection statt des generischen `config/{configId}`-Blocks:** dessen sameOrg-Read würde Berater-/Mandantennummer allen Org-Mitgliedern zeigen, und überlappende Rules-Matches sind ODER-verknüpft (eine restriktivere Spezial-Match kann den generischen Block nicht überstimmen).
- `FinanceProvider`: Config cloud-first laden — **admin-gated** (`if (isAdmin)`, Prüf-Befund: sonst garantierter permission-denied für jeden Mitarbeiter beim Login); `saveDatevConfig` aufs Drei-Modi-Muster; **Audit-Lücke schließen:** `_audit?.call(action: AuditAction.updated, entityType:'datevConfig', …)` auf jedem Erfolgs-Zweig (Migration → `created`). Einmal-Migration lokal→Cloud beim ersten Load ohne Cloud-Doc.
- **Rules:** `match /financeConfig/{configId}`: read/create/update nur `isAdmin() && sameOrg(orgId)` + orgId-Pin, `delete: false`.
- **Aufwand:** S · **Abhängig:** keine (Fundament); Rules wirksam erst nach DATEV-6/Q0

### DATEV-2: Prüflauf vor Export (pure `DatevExportCheck` + Gate-UI) — Status: ERLEDIGT (Welle 1)
- Neue pure Klasse `lib/core/datev_export_check.dart`: `DatevExportCheck.run(...)` → `List<DatevExportFinding>` (code, severity error/warning, deutsche Message, betroffene IDs) — transient wie `ComplianceViolation`, keine Collection.
- Befund-Codes v1: `cost_type_missing_number`, `unknown_cost_type`, `unknown_cost_center`, `contra_account_missing`, `revenue_rate_unmapped` (die heutige stille Skip-Klasse!), `closing_unbooked`, `entries_empty`. **Gestrichen/präzisiert (Prüf-Befunde):** `closing_missing_day` entfällt in v1 (Datenquelle fehlt in der Signatur); `journal_local_only` wird zu „aktueller Modus ist local/hybrid-offline" heruntergestuft, bis ein echtes Cloud-Vollständigkeits-Signal existiert (Flag, das bei `_persist`-Fallback gesetzt und lokal persistiert wird — als Folge-Schritt notiert).
- **Modellbedingt keine Soll/Haben-Balance-Prüfung:** das einseitige Allokationsmodell kennt keine Beleg-Balance; Ersatz: `entries_empty` + S/H-Summen werden in der Export-Historie (Q2) sichtbar. (Explizit dokumentiert, damit die Anforderung „unbalancierte Buchungen" nicht als vergessen gilt.)
- `buildDailyClosingEntries`: Rückgabe `({entries, skippedRates})` statt stillem `continue` → ehrliche SnackBar im Tagesabschluss.
- CashClosing-Beschaffung konkret: `loadCashClosings(asOf: DateTime(year,12,31), windowDays: 366)` bzw. Range-Call; „Closings nicht verfügbar" (local-Modus) als eigenes Flag an den Prüflauf (≠ „keine Abschlüsse").
- UI-Gate in `finance_screen._export`: Befundliste-Sheet; Fehler blockieren, Warnungen erfordern „Trotz Warnungen exportieren"; `DatevExport.disclaimer` bleibt.
- **Tests:** je Befund-Code ein Fixture, Assertions auf `.code` (Compliance-Muster) · **Aufwand:** M · **Abhängig:** weich DATEV-1; wird in DATEV-5 um Mapping-Codes erweitert

### DATEV-3: Export-Historie (nutzt Q2 `datevExportRuns`) — Status: ERLEDIGT (Welle 2: crypto-Dep, Deterministik-Fix (date,id), buildDatevExport+sha256, Run-Write+„Erstellte Exporte"-Sheet+„Neu aufbauen & vergleichen"; byte-identischer Re-Download aus entriesSnapshot = Folge-Verfeinerung)
- `ExportService.exportDatevBuchungsstapel` refactoren: `generatedAt` injizierbar, Rückgabe `({content, sha256, entryCount, sollCents, habenCents, fileName})`; `crypto` als direkte Dependency in `pubspec.yaml` (heute nur transitiv, verifiziert).
- **Deterministik-Fix (Prüf-Befund):** totale Ordnung `sort` nach `(date, id)` statt nur `date` — Dart-Sort ist instabil, Ties hängen sonst an der Eingangsreihenfolge → falsche „Journal verändert"-Warnungen. Test: Ties in beliebiger Reihenfolge → identischer Hash.
- Nach bestandenem Prüflauf (DATEV-2) Run in `datevExportRuns` (Q2) schreiben (`exportArt: finanz`, SHA-256, `configSnapshot`, `generatedAtMillis`, `acceptedWarningCodes`, `entriesSnapshot` bis zur Q2-Grenze); Abschnitt „Erstellte Exporte" in `finance_screen` mit **„Neu aufbauen & vergleichen"** (Q2-Semantik: Rebuild + Hash-Vergleich; Abweichung → Warnung `appColors.warning` „Journal seit Erstellung verändert", Download trotzdem möglich; bei vorhandenem `entriesSnapshot` byte-identischer Download aus dem Snapshot).
- Offline-Semantik aus Q2 (Run-Doc VOR Download; hybrid-offline blockiert).
- **Aufwand:** M · **Abhängig:** Q2, DATEV-2, DATEV-1 (configSnapshot org-weit)

### DATEV-5: Kassennahes Mapping — Zahlart→Konto, Kasse/Standort→Gegenkonto, USt→BU-Schlüssel — Status: offen (VOR DATEV-4 umsetzen)
- `DatevExportConfig` +6 Felder: `paymentAccountByMethod`, `taxKeyByRate` (Vorschläge 19→'3', 7→'2' — **vom Steuerberater bestätigen lassen**), `contraAccountBySiteId` (Fallback `defaultContraAccount`), `skrProfile` (Metadatum), `cashDifferenceCostTypeId`/`personnelCostTypeId`/`wareneinsatzCostTypeId` (ersetzen die Needle-Heuristiken als Primärquelle; Needles nur noch Fallback mit `AppLogger.warning`). Map-int-Keys immer als String serialisieren (Vorbild `revenueAccountByRate`).
- `JournalEntry` +3 Plan-Metadaten: `taxRatePercent` (int?), `paymentMethod` (String?), **`systemKind` (String?, z. B. `payment_transit` — Review-Befund: Systembuchungen eindeutig typisieren)** — volle 6 Stellen inkl. `clearX`; journalEntries-Rules haben keine Feld-Allowlist → kein Rules-Touch.
- `buildDailyClosingEntries` schreibt `taxRatePercent` an Erlöszeilen; NEU `buildPaymentTransitEntries`: je Zahlart mit Mapping eine Buchung mit idempotenter ID `pos-pay-<day>-<site>-<method>` — **Method-Key vor ID-Bildung sanitizen** (lowercase, `[^a-z0-9]→'_'`; Prüf-Befund: rohe Keys können `/` enthalten), Original-Key als `paymentMethod`-Feld, `systemKind='payment_transit'` gesetzt; ohne Mapping → `skipped`-Rückgabe (nie still).
- **Auswertungs-Schutz (Review-Befund):** ALLE Journal-Leser (Finance-Summen/Kostenstellen-Reports, Betriebsergebnis, REPORTING-Sektionen) behandeln `systemKind`-Buchungen EXPLIZIT — Default: Transit-Buchungen fließen NICHT in Umsatz-/Kosten-Analysen (reine Export-/Abstimmungszeilen), sonst drohen Doppelzählungen. Test: Tagesabschluss mit Transit-Zeilen verändert Kostenstellen-Report und Dashboard-Umsatz nicht.
- `datev_export.dart`: BU-Spalte `cols[8]` aus `taxKeyByRate[taxRatePercent]` (sonst leer wie heute — abwärtskompatibel); Gegenkonto `cols[7]` via CostCenter→Site→`contraAccountBySiteId`.
- Admin-UI: Mapping-Abschnitte im `_DatevConfigSheet` mit Vorbelegung (beobachtete Zahlarten aus CashClosings, USt-Sätze aus taxBuckets, Sites aus TeamProvider); Persistenz + Audit über DATEV-1 (**Audit-Historie IST die Mapping-Versionierung**).
- Prüflauf-Erweiterung: `payment_method_unmapped`, `tax_key_missing` (Warnung), `site_contra_unmapped`, `cost_type_ref_missing`.
- **Aufwand:** L · **Abhängig:** DATEV-1 (Pflicht), DATEV-2; extern: fachliche Freigabe Steuerberater (Kontenwahl, Transit-Semantik im einseitigen Allokationsmodell — s. offene Fragen)

### DATEV-4: GoBD-Festschreibung — Perioden-Lock + Storno statt Änderung + EXTF-Kennzeichen — Status: offen (NACH DATEV-5)
- **Vorab-Schritt (Prüf-Befund hoch, eingearbeitet):** `JournalEntry.date` zentral auf 12:00 lokal normalisieren — in `FinanceProvider.saveJournalEntry` (`copyWith(date: DateTime(y,m,d,12))`), im Editor-Default, in `postPersonnelCostJournal` (bucht heute Monatsletzter 00:00!) und beim Storno-Datum. Die ursprüngliche Plan-Prämisse „date ist bereits 12:00-normalisiert" stimmt nur für die POS-Pfade; ohne Normalisierung kippt der UTC-Monat im Rules-Guard (DE = UTC+1/+2). Für Alt-Docs mit Mitternachts-Timestamps vom Monatsersten: Migration oder dokumentierte Rules-Toleranz definieren.
- **Q1 ist Voraussetzung:** `_tryFirestore` muss `permission-denied` rethrowen — sonst verwandelt der hybrid-Fallback jeden Rules-Deny in einen scheinbar erfolgreichen Lokal-Write samt Audit (Prüf-Befund hoch).
- Lock-Model `FinancePeriodLock` @ `organizations/{orgId}/financePeriodLocks/{yyyy-MM}` (deterministische Doc-ID, monatlich): orgId, period (== Doc-ID, rules-erzwungen), lockedByUid/At, exportRunId? (Referenz auf Q2-Lauf), note?. **Abweichend vom cloud-only-Vorbild MIT `toMap`/`fromMap` + lokalem Spiegel** (Prüf-Befund: sonst ist der Client-Guard im local-Modus/hybrid-offline wirkungslos, weil `istPeriodeGesperrt` immer eine leere Liste sähe).
- Pure Client-Schicht `lib/core/finance_festschreibung.dart` (Spiegel-Muster `monats_festschreibung.dart`): `periodId` (zero-padded), `istPeriodeGesperrt`, identische deutsche Meldung wie der Rules-Deny.
- Provider: zentraler Guard in `saveJournalEntry`/`deleteJournalEntry` (deutscher `StateError`); `postDailyClosing`/`postCashDifference`/`postPersonnelCostJournal` erben ihn; Tagesabschluss-UI zeigt „Periode festgeschrieben — Korrektur nur per Storno". Storno-Flow: `stornoJournalEntry` (Betrag invertiert, `description 'Storno: …'`, `reference` = Original-ID, Datum = heute 12:00 in offener Periode, Original unangetastet); Audit: Storno → `AuditAction.corrected`, Lock → `created`.
- **Rules:** Helper `finanzPeriodeFrei(orgId, ts)` nach dem exists()-sicheren `get()`-Muster; journalEntries: create/update/delete jeweils geprüft, update **beidseitig** (resource UND request — verhindert Heraus-/Hineinschieben), tolerant gegen kaputte date-Felder. `financePeriodLocks`: create-only (`update/delete: false` — Entsperren nur via Console; offene Frage). Kosten 1–2 `get()` je Write bewusst akzeptiert (Monats-Lock-Präzedenz).
- EXTF: `buildBuchungsstapel` Parameter `festschreibung` (Default false) → Header-Festschreibekennzeichen '1' nur, wenn alle Monate mit Buchungen des Exportjahres gesperrt sind; positionsempfindliche Header-Tests nachziehen. Prüflauf-Code `period_not_locked` (Warnung).
- Festschreibe-UI: Monatsliste mit Schloss-Status + Bestätigungsdialog („nicht umkehrbar"); nach Export Angebot „Zeitraum jetzt festschreiben?" mit `exportRunId`.
- **Keine Callable-Schicht:** Finanz-Writes haben keinen Callable-Pfad — Client + Rules sind die vollständige Enforcement-Menge. Kopplungs-Regel ins Plan-Doc: entsteht je eine Finance-Callable, MUSS sie einen JS-Spiegel bekommen (analog `monats_lock.js`).
- **Aufwand:** L · **Abhängig:** Q1 (Pflicht), DATEV-3/Q2 (exportRunId), DATEV-5 (Ausführungs-Reihenfolge), DATEV-2 (`period_not_locked`)

### DATEV-6: Deploy-Paket + Doku-Nachführung — Status: offen
- Rules-Deploy (financeConfig, datevExportRuns, financePeriodLocks, verschärfter journalEntries-Block) — der Deploy schiebt zwangsläufig ALLE gestauten Rules-Änderungen mit: **gesamten Rules-Diff reviewen**, nicht nur den DATEV-Anteil. Emulator-Prüfprotokoll (deny-Fälle: Write in gesperrte Periode, Run-update/delete, financeConfig-Read als Nicht-Admin).
- Doku: `plan/gpt_vergleich_2026-07-12.md` AP6 nachführen; CLAUDE.md-Kopplung ergänzen („Finanz-Festschreibungs-Semantik ändern → `finance_festschreibung.dart` UND `finanzPeriodeFrei` synchron") + Index-Zählstand korrigieren (real 25, CLAUDE.md sagt 14).
- **Aufwand:** S · **Abhängig:** DATEV-1/3/4/5, Q0

---

## C — Personal / HR (PERSONAL-1 … PERSONAL-9)

**Ist-Basis (verifiziert):** Lohnlauf existiert (PayrollRecord mit Status-Workflow `freigegeben/bezahlt`, `PayLineType.datevLohnartNr`, `personnelNumber` am Profil, `ZeitkontoSnapshot` mit `countsAsIst`=approved); **Grundlohn ist KEINE PayrollLine**, sondern `PayrollRecord.grossCents` — `istMinutes` wird bei der Draft-Erzeugung verrechnet und verworfen; Dokument-Stack (Upload, `acknowledgedAt` mit feldgranularer Rules-Allowlist) existiert; `EmployeeQualification` mit `gueltigBis`+`gueltigkeitStatus` existiert (admin-only read); MHD-Warn-Muster (`expiry_warning.dart` + `expiryWarningNightly` + `dedupeId`) existiert; `notifications`-Collection hat Self-Read-Rules (`recipientUid`), aber **keinen Client-Leser**.

### PERSONAL-1: Lohn-Mengengerüst + Personalnummer-Validierung — Status: ERLEDIGT (Welle 1)
- **Grundlohn-Stunden (Prüf-Befund hoch, Variante a):** `PayrollRecord` bekommt ein persistiertes Stunden-Feld `istMinutes` (int?, „zum Freigabezeitpunkt abgerechnetes Ist" — friert GoBD-freundlich ein) — 6 Serialisierungs-Stellen + `clearIstMinutes`; `buildDraftPayrollForMonth` füllt es (statt es zu verwerfen), Lohn-Editor zeigt/übernimmt es. Der Export-Builder (PERSONAL-2) synthetisiert daraus + `grossCents` + `config.festeLohnartGrundlohn` den Grundlohn-Satz.
- `PayrollLine.mengeStunden` (double?) für Zuschlags-/Zusatzzeilen: Serialisierung in den Line-Map-Buildern (camelCase `mengeStunden` / snake_case `menge_stunden`, `parse.toDouble`) + `clearMengeStunden`. **§3b-Durchreichung vollständig (Prüf-Befund):** Fabrik `PayrollLine.zuschlag3b` um `mengeStunden`-Parameter erweitern (aus `dauer` in `sfn3bLine` berechnet) + Aufrufstelle im Lohn-Editor (`personal_screen.dart` ~Z. 5738) anpassen; Test: die im Editor erzeugte §3b-Zeile trägt die Menge.
- Pure Validierung in `lib/core/datev_lohn_export.dart` (Datei hier anlegen): `isValidDatevPersonalnummer` (nur Ziffern, 1–5 Stellen, nicht '0') + `findePersonalnummerProbleme` (fehlend/ungültig/doppelt, typisiert, kein Throw); weiche Inline-Warnung im Stammdaten-Tab.
- **Rules/Functions/Indexe:** keine · **Aufwand:** S–M

### PERSONAL-2: Purer DATEV-Lohn-Builder (LODAS + Lohn&Gehalt) + `DatevLohnConfig` — Status: ERLEDIGT (Welle 2: Builder+Config+Flag+Tests; Provider-/Screen-Anbindung folgt in PERSONAL-3)
- `datev_lohn_export.dart` ausbauen: `DatevLohnFormat{lodas, lohnUndGehalt}` (Enum-Konventionen), `DatevLohnConfig` (format, beraterNr, mandantenNr, `festeLohnartGrundlohn`) dual serialisiert; `buildBewegungsdaten({config, records, profilesByUserId, payLineTypes, jahr, monat})` → CRLF+Semikolon-ASCII (Vorbild EXTF-Builder). Je Record: Grundlohn-Satz synthetisiert (PERSONAL-1) + je PayrollLine Personalnummer;Lohnart;Menge/Betrag (deutsches Dezimalformat).
- Ergebnisobjekt `DatevLohnExportErgebnis {content, probleme}`: nur `freigegeben`/`bezahlt`-Records (countsAsIst-Kette bleibt gewahrt — KEIN eigener WorkEntry-Aggregat-Code); fehlende Personalnummer/Lohnart je Zeile als Problem gesammelt.
- Flag `APP_DATEV_LOHN_ENABLED` (Default false) in `AppConfig` + CLAUDE.md-Tabelle; **Config-Singleton `financeConfig/datevLohn` — ENTSCHIEDEN** (Review-Befund: nicht der generische `config/`-Block, dessen sameOrg-Read Berater-/Mandantennummer allen Mitarbeitern zeigen würde): gleicher admin-only Rules-Block wie DATEV-1, Save admin-gated + audit-pflichtig (`AuditAction.updated`, entityType `datevLohnConfig`); lokaler Fallback-Key `local_v2/datev_lohn_config`.
- **Tests:** Golden-Strings beide Formate (2 MA × 3 Lohnarten), Problem-Sammlung, Config-Roundtrips · **Aufwand:** M · **Abhängig:** PERSONAL-1; DATEV-1 (financeConfig-Rules-Block); extern: Format-Vorgabe + Lohnartnummern des Steuerberaters

### PERSONAL-3: Lohn-Export im Lohnlauf-Screen + gemeinsame Historie (Q2) — Status: ERLEDIGT (Welle 2: DATEV-Lohn-Button+Vorprüfung+Config-Sheet, Q2-Lohn-Run mit rowsSnapshot, revisionssicherer Re-Download via serializeLohnBewegungsdaten, DatevLohnConfig cloud-first in FinanceProvider; Monats-Festschreibungs-Warnung = Folge mit DATEV-4)
- `lohnlauf_screen.dart`: Button „DATEV-Lohn (Export)" (nur `AppConfig.datevLohnEnabled && isAdmin`): Config-Prüfung → `buildBewegungsdaten` → Vorprüfungs-Dialog (Probleme; **Monats-Festschreibung laut `ZeitkontoSnapshot.abgeschlossen` als Warnung mit explizitem Override** — hart/weich als offene Frage) → Run in `datevExportRuns` schreiben (Q2, `exportArt: lohn`, inkl. `rowsSnapshot` + `fileSha256` + `monatFestgeschrieben`/`overrideBestaetigt`) → Download; Re-Download baut ausschließlich aus dem `rowsSnapshot` (revisionssicher, nie aus Live-Daten — Q2).
- Retrofit: der Finanz-Export loggt in dieselbe Historie (bereits Teil von DATEV-3); Historie-Sheet filtert nach Art (Q2-Index).
- **Statt eigener `datevExports`-Collection wird Q2 genutzt** (Konflikt-Auflösung; das ursprüngliche PERSONAL-3-Modell entfällt).
- **DSGVO-Hinweis:** Export-Dateien enthalten Lohn-PII — nur Download, keine Persistenz des Inhalts; Empfängerkreis = Steuerberater; Hinweis im Dialog.
- **Aufwand:** M · **Abhängig:** PERSONAL-2, Q2, Q0 (Rules/Index-Deploy)

### PERSONAL-4: Dokumenten-Workflow — getrennte Zeitstempel + Status — Status: ERLEDIGT (Welle 2: EmployeeDocument +requiresAcknowledgement/visibleSince/openedAt/downloadedAt/declinedAt/declineComment volle Dual-Serialisierung + abgeleiteter workflowStatus; markDocumentOpened(idempotent)/declineDocument(Pflicht-Kommentar); Admin setzt visibleSince beim Sichtbarschalten; Rules MA-Allowlist erweitert + declineComment-nur-mit-declinedAt; UI Status-Chip/Ablehnen-Dialog/requiresAcknowledgement-Schalter; Audit ergänzt. Rules-Deploy offen)
- `EmployeeDocument` +Felder (Review-Befund: „zugestellt beim ersten Rendern" ist rechtlich zu schwach — Zeitstempel sauber trennen): `requiresAcknowledgement` (bool, Default false), **`visibleSince`** (DateTime? — Bereitstellung; wird admin-seitig beim Sichtbarschalten/Upload mit `visibleToEmployee` gesetzt, NICHT vom MA), **`openedAt`** (DateTime? — bewusstes Öffnen: Viewer-/Download-Aktion des MA, NICHT das bloße Rendern der Dokumentliste), optional `downloadedAt`, `declinedAt` (DateTime?), `declineComment` (String?) — je volle Serialisierungs-Stellen + `clearX`; Status ist ABGELEITET (`workflowStatus`: offen → bereitgestellt → geöffnet → bestätigt/abgelehnt; abgelehnt schlägt bestätigt) — kein persistiertes Enum, keine Drift.
- Rules (firestore.rules ~1279): MA-update-Allowlist erweitern auf `hasOnly(['acknowledgedAt','openedAt','downloadedAt','declinedAt','declineComment','updatedAt'])` — `visibleSince` gehört NICHT in die MA-Allowlist (admin-seitig); weiterhin nur eigenes Doc + `visibleToEmployee`; `declineComment` nur zusammen mit `declinedAt`.
- Provider: `markDocumentOpened` (idempotent, beim Öffnen/Download des Dokuments — nicht beim Listen-Rendern), `declineDocument` (Pflicht-Kommentar, räumt `acknowledgedAt`); Admin-Pfad setzt `visibleSince` beim Sichtbarschalten; **Audit-Lücke schließen:** `acknowledgeDocument` + die neuen Mutatoren loggen (`AuditAction.updated`, sprechende Summaries).
- UI: Status-Chips (`appColors`), Ablehnen-Dialog, `requiresAcknowledgement`-Schalter im Upload-Dialog, Admin sieht `declineComment` + wer wann geöffnet/bestätigt hat.
- **Deploy:** `--only firestore:rules` synchron mit dem Client (sonst permission-denied) — nimmt den gestauten employeeDocuments/storage-Block gleich mit · **Aufwand:** M

### PERSONAL-5: Dokument-Erinnerungen (Nightly) + Admin-Tracking — Status: offen
- `documentReminderNightly` (onSchedule, Muster `expiryWarningNightly`): unbestätigte Workflow-Dokumente, deren Bereitstellung (`visibleSince`, Fallback `createdAt`) älter als 3 Tage ist; **Query-Entscheidung (Prüf-Befund):** serverseitig nur `requiresAcknowledgement==true` (+ ggf. `visibleToEmployee==true`) filtern, `acknowledgedAt`/`declinedAt`/Alter **in JS prüfen** → kein Composite-Index (4 Equalities + Range wären sonst index-pflichtig). Caveat dokumentieren: `declinedAt==null`-Queries würden Bestands-Docs ohne Feld nicht matchen — durch JS-Filterung umgangen.
- `dedupeId 'doc-reminder:{docId}:{isoWoche}'` (wöchentlich, spamfrei); Kopplungs-Set Q3 für die neue Kategorie.
- Pure Aggregation `lib/core/document_tracking.dart` (`offeneBestaetigungen(docs, stichtag)`); Admin-Screen „Dokument-Bestätigungen" — **als Section-Route** `/dokument-bestaetigungen` (AppRoutes + `_sectionRoute` + `_isLocationAllowed` admin-only; Prüf-Befund: org-weite Admin-Übersicht ist ein Hauptbereichs-Screen, kein Detail-Sheet).
- **Deploy:** `--only functions` · **Aufwand:** M · **Abhängig:** PERSONAL-4 (+ deployte Rules), Q3, Q4

### PERSONAL-6: Quali-Nachweis-Dokument + Self-Read eigener Qualifikationen — Status: offen
- `EmployeeQualification.documentId` (String?, weiche FK auf EmployeeDocument; Löschung lässt sie verwaisen → UI „Nachweis nicht mehr vorhanden") — volle Stellen + `clearDocumentId`.
- Quali-Editor: Abschnitt „Nachweis" (Dokument wählen oder hochladen via bestehendem `uploadDocument`, Kategorien existieren); Download-Link.
- Rules: employeeQualifications-read erweitern auf `isAdmin() || (sameOrg && resource.data.userId == request.auth.uid)` (Muster urlaubskontoJahre-Self-Read); Schreibrechte bleiben admin-only. Meine-Akte: Abschnitt „Meine Qualifikationen" mit `gueltigkeitStatus`-Badges.
- **Deploy:** `--only firestore:rules` · **Aufwand:** S

### PERSONAL-7: Quali-Ablauf-Warnungen (konfigurierbarer Vorlauf + Nightly) — Status: offen
- `OrgSettings.qualiWarnVorlaufTage` (int, Default 30) — volle Stellen; Pflege im OrgSettings-Editor; Client-Badges lesen den Wert statt hart 30.
- Pure `lib/core/quali_expiry_warning.dart` (`computeQualiExpiryWarnings(..., {now, vorlaufTage})` → laeuftAb/abgelaufen).
- `qualiExpiryNightly` (onSchedule): je Org `gueltigBis <= threshold` (einzelner Range → kein Composite); `fanOutPush` an Mitarbeiter UND Admins. **dedupeId MIT Gültigkeitsdatum** (Prüf-Befund): `quali:{qualiId}:{gueltigBisTag}:{stufe}` — sonst gäbe es nach Verlängerung nie wieder eine Warnung (`.create()`-Idempotenz auf ewigem Doc). Kopplungs-Set Q3.
- **Deploy:** `--only functions` · **Aufwand:** M · **Abhängig:** PERSONAL-6 (MA sieht den Gegenstand der Warnung), Q3, Q4

### PERSONAL-8: Quali-Ablauf in der Schichtplanung (ShiftAutoAssigner + manuelle Zuweisung) — Status: offen
- Datenkanal: `setPlanningDataSink` pusht zusätzlich `qualiGueltigBisByUser` (userId → qualificationId → gueltigBis; nur Datensätze MIT FK). **Merge-Regel (Prüf-Befund):** je (userId, FK) gewinnt der günstigste Datensatz — `gueltigBis==null` (unbefristet) vor `max(gueltigBis)` (sonst blockiert ein alter abgelaufener Datensatz nach Verlängerung); Testfall aufnehmen. `updatePersonalReferenceData` erweitert (Setter weiterhin OHNE `notifyListeners`).
- `OrgSettings.enforceQualiAblaufHard` (bool, Default true; Muster `enforceHourCapHard`).
- Assigner (pure, Stichtag = Schichtdatum, kein `now()`): an beiden Prüfstellen — abgelaufen ⇒ hart `UnassignableReason.qualificationExpired` (Enum + deutsches Label + Prioritätenliste) / weich `AssignmentWarning` + Score-Penalty; bald ablaufend (Vorlauf aus PERSONAL-7) ⇒ immer nur Warnung. Kein HR-Datensatz ⇒ unbefristet gültig (rückwärtskompatibel, kein Big-Bang — Default bestätigen, offene Frage).
- Manuelle Zuweisung: nicht-blockierender Hinweis (Admin-Override bleibt, analog Compliance-Override-Philosophie).
- **Compliance-Spiegel NICHT betroffen** (Planungsschranke, keine Violation — Kopplung #2 nicht auslösen) · **Aufwand:** M · **Abhängig:** fachlich PERSONAL-6/7, technisch unabhängig

### PERSONAL-9 (= Q4): Mitteilungs-Inbox-Leseansicht — Status: ERLEDIGT (Welle 2: read-only AppNotification, NotificationProvider Inbox-Stream recipientUid+createdAt-desc-limit-50 + unreadCount + markAsRead(readAt), /mitteilungen-Screen + Routing-Dreiklang (jeder aktive Nutzer), Composite-Index notifications(recipientUid,createdAt DESC); Rules waren bereits vorhanden. Index-Deploy offen)
- `NotificationProvider` ausbauen (heute nur FCM-Token): Inbox laden — **Query `where recipientUid==uid` orderBy `createdAt` desc limit 50** (Prüf-Befund hoch: das Feld heißt `recipientUid`, NICHT `userId` — sonst Rules-Deny und nutzloser Index); ungelesen-Zähler; `markAsRead` schreibt feldgranular nur `readAt` (deckungsgleich mit der Rules-Allowlist). Read-only-Model `AppNotification.fromFirestore` mit den ECHTEN Feldern (`recipientUid`, `category`, `title`, `body`, `route`, `entityType`, `entityId`, `readAt`, `createdAt`) — Navigation über das vorhandene `route`-Feld (keine eigenen Payload-Typen). Dokumentierte Ausnahme: server-owned read-only, kein `toMap`.
- Screen `/mitteilungen` (Routing-Dreiklang: AppRoutes + `_sectionRoute` + `_isLocationAllowed` für jeden aktiven Nutzer); Glocken-Badge im Home-Header; local-Modus: leere Inbox (bewusste Degradation).
- **Index:** Composite `notifications(recipientUid ASC, createdAt DESC)` — vorher prüfen, ob vorhanden.
- **Einordnung korrigiert (Prüf-Befund):** die Inbox war im Push-Plan (`plan/archiv/push-benachrichtigungen-plan.md`) angekündigt, aber nie als Meilenstein gebaut — dieser Baustein schließt die Lücke, keine Doppelplanung.
- **Deploy:** `--only firestore:indexes` · **Aufwand:** M · **nützt:** WW-5, PERSONAL-5/7, bestehendes MHD/Klärung/Lohn

---

## D — Reporting / Kennzahlen (REPORTING-1 … REPORTING-8)

**Ist-Basis (verifiziert):** Engines `kasse_report.dart` (KassenPerioden aus posDailyStats-first via `loadKassenbericht(siteId:)`), `lohnquote.dart` (org-weit, nur Monat/Jahr, ehrlich als Richtwert dokumentiert), `zeitkonto_snapshot_builder.dart` (E3: Ist nur approved), `store_health.dart` (Laden-Benchmark) existieren; `SalesInsightsProvider` ist das Muster für Read-State-Provider ohne eigenes Cloud-Repo; `RoutePermissions` ist das SSoT-Muster; posDailyStats/posReceipts-Rules: read admin||teamlead (org-weit — die einzige echte Rules-Lücke des Bereichs); ohne functions-Deploy + Backfill laufen Trends im 92-Tage-Client-Fallback.

### REPORTING-1: Deklaratives KPI-Sichtbarkeits-Modell (`KpiPermissions`) — Status: ERLEDIGT (Welle 1)
- `lib/core/kpi_permissions.dart`: `enum KpiId` (umsatz, rohertrag, lohnquote, betriebsergebnis, bestandswertEk/Vk, zeitkontoOrg, offeneFreigaben, offeneAbwesenheiten, personalstundenSite, belegeSite, eigeneZeitStatistik, …) + `KpiPermissions.isKpiAllowed(KpiId, profile)` + `visibleKpis(profile)` — Muster `RoutePermissions`, je Zeile Kommentar auf den deckenden Rules-Block. Katalog darf Rechte nur VERENGEN; Daten-Rules bleiben maßgeblich.
- **Permission- statt rollenbasiert (Prüf-Befund):** `eigeneZeitStatistik→canViewReports`, `zeitkontoOrg/offeneFreigaben→canManageShifts`, Lohn/EK/Marge→`isAdmin` — die bestehenden Gates sind Flag-basiert und per User überschreibbar; Test-Matrix um Override-Fälle erweitern.
- Unbekannte KpiId ⇒ **false** (bewusst invertierter Routen-Default — Kennzahlen sind sensibler als Navigation).
- Bestehende Inline-Gates delegieren verhaltensgleich (Characterization: bestehende Screen-Tests bleiben grün).
- **Aufwand:** S · **Rules/Indexe:** keine

### REPORTING-2: Org-Zeit-Kennzahlen als pure Engine — Status: ERLEDIGT (Welle 1)
- `lib/core/org_zeit_kpis.dart`: `OrgZeitKpis` (sollMinutes, istMinutes, saldoMinutes, mitarbeiterMitSoll, offeneFreigaben, offeneEntwuerfe) + `computeOrgZeitKpis(...)` — intern je Mitglied `buildZeitkontoSnapshot` (E3-Invariante NICHT neu implementieren; submitted/draft nur als separate Zähler). **`urlaubOffen` gestrichen** (Prüf-Befund: Quelle ist der ScheduleProvider in REPORTING-3, nicht diese Engine).
- **Snapshot-Konsistenz (Prüf-Befund):** Signatur zusätzlich `required List<ZeitkontoSnapshot> currentMonthSnapshots` — `ausgezahltMinutes` durchreichen und Regel dokumentieren/testen: **persistierter Snapshot gewinnt für abgeschlossene Monate** (der Report darf dem festgeschriebenen Abschluss nicht widersprechen), Live-Berechnung nur für offene.
- `ZeitwirtschaftProvider.loadOrgZeitKpis(...)`: Komposition der existierenden `loadOrg*`-Methoden; Gate `canManageShifts` (schließt isAdmin ein) **+ Kiosk-Kontext ausschließen**.
- **Aufwand:** S · **Rules/Indexe:** keine

### REPORTING-3: `ManagementDashboardProvider` (Read-State, Muster SalesInsightsProvider) — Status: ERLEDIGT (Welle 2: bind + Teilerfolg + Stale-Guard + KpiPermissions-Gating; main.dart als letzter Proxy; Tests via Subklassen-Seam)
- ChangeNotifier OHNE eigenes Cloud-Repo: `bind()` an lebende Provider (Inventory, Personal, Zeitwirtschaft, Schedule, FeatureFlags); `_safeNotify`; Stale-Guard nach dem Vorbild des `_siteId`-Vergleichs in `sales_insights_provider.dart` (~Z. 182), hier als zusammengesetzter Lauf-Schlüssel (granularity, siteId) — (das ursprünglich zitierte `_dataKey` existiert nicht).
- Sektionen mit Teilerfolg (Kassen-Perioden, Lohnkennzahlen, Bestandswerte je Site, OrgZeit, offene Abwesenheiten aus ScheduleProvider-pending): eine fehlgeschlagene Sektion reißt die anderen nicht mit; Lohn-Sektion nur bei `KpiPermissions`-Erlaubnis UND granularity≠week UND siteId==null (lohnquote-Grenzen erben).
- `main.dart`-Kette: als LETZTER Proxy (Senke aller Quellen, Kopplung #4).
- **Tests:** Fake-Quell-Provider per Subklassen-Seam; Teilerfolg; Stale-Guard; employee ⇒ Lohn-Sektion null trotz Daten · **Aufwand:** M · **Abhängig:** REPORTING-1+2

### REPORTING-4: Dashboard-Screen `/kennzahlen` + Home-Integration + Reuse-Widgets — Status: TEILWEISE (Welle 2: /kennzahlen-Screen + Routing-Dreiklang Gate isAdmin||canManageShifts; OFFEN: Home-Kachel, Widget-Hoisting nach kennzahlen_widgets.dart, Trend-Chart, Drill-Down-Gating)
- Widgets aus `kassenbericht_screen.dart` nach `lib/widgets/kennzahlen_widgets.dart` heben (KpiCard, RichtwertBanner, UmsatzTrendChart); Kassenbericht verhaltensgleich umstellen (bestehende Tests als Netz).
- Screen: Zeitraumwahl (SegmentedButton), KPI-Kacheln über `visibleKpis` (keine Streu-ifs), fl_chart-Trend, Sektions-Fehler je Karte; ehrlicher Langzeit-Hinweis bei Fallback-Daten.
- Routing-Dreiklang; **Route-Gate `isAdmin || canManageShifts`** (konsistent mit den workEntries-Rules statt Rollen-Paar; Prüf-Befund).
- **Drill-Down-Gating (Prüf-Befund):** Kachel-Ziele (`kassenbericht`, `bestandInsights`, `storeHealth`, `personal`) sind admin-only geroutet — Drill-Down-Affordance zusätzlich über `RoutePermissions.isLocationAllowed` gaten (Kachel ohne Recht = kein Tap-Ziel), sonst laufen Teamlead-Taps ins Leere. Widget-Test dafür.
- Home: „Kennzahlen"-Kachel im Admin-Dashboard; `dashboard_action_items_card` + „X Zeiteinträge warten auf Freigabe" (Ziel `zeitMitarbeiterabschluss`, teamlead-erreichbar).
- **Aufwand:** L · **Abhängig:** REPORTING-3; Trends produktiv erst nach Q0-Backfill (Screen zeigt das ehrlich an)

### REPORTING-5: Standortvergleich-Engine (pure) — Status: offen
- `lib/core/site_comparison.dart`: `SiteKennzahlen`/`SiteVergleich` + `computeSiteVergleich(...)` — je Site Umsatz/Rohertrag/Belege/Personalstunden (nur approved via `countsAsIst`; Einträge ohne siteId als Zeile „ohne Standort", nicht still verwerfen)/Bestandswert; Ranking + Delta (Muster `store_health.dart`).
- Lohnkosten-Allokation als **klar gelabelter Richtwert** (org-weite finalisierte PayrollRecords proportional zu approved-Minuten je Site; Stunden==0 ⇒ null, kein stilles 50/50) — bewusst KEINE siteId am PayrollRecord (keine falsche Präzision in den Daten).
- Provider-Erweiterung `loadSiteVergleich()`: je Site `loadKassenbericht(siteId:)` + `totalStockValue*Cents(siteId:)` + Monats-Entries wiederverwendet.
- **Abgrenzung StoreHealth dokumentieren** (Prüf-Befund): StoreHealth = Warn-Benchmark mit Schwellwert, Standortvergleich = Zeitraum-Analyse; langfristige Zusammenführung als Option notieren.
- **Aufwand:** M · **Abhängig:** REPORTING-3

### REPORTING-6: Standortvergleich-Screen `/standortvergleich` — Status: offen
- Beide Läden nebeneinander (responsive über `MobileBreakpoints`), Zeitraumwahl, Ranking-/Delta-Markierung (`appColors`), Lohn-Zeile „Richtwert (Verteilung nach Stunden)", Drill-Down je Site in den Kassenbericht (`initialSiteId`-Parameter, Default-Verhalten unverändert).
- **Route-Gate: im ersten Schnitt ADMIN-ONLY** (Prüf-Befund hoch: der Teamlead-Pfad kollidiert mit REPORTING-7 — `loadKassenbericht` liest posDailyStats direkt, und ein Site-gescopeter Teamlead kann per Design nicht beide Läden vergleichen). Teamlead-Variante erst nach REPORTING-7 als bewusste Folge-Entscheidung.
- **Aufwand:** M · **Abhängig:** REPORTING-5, REPORTING-4 (Widgets)

### REPORTING-7: Teamlead-Site-Scoping serverseitig (KPI-Projektions-Callable + Rules-Verengung) — Status: offen (LETZTER Reporting-Schritt)
- `functions/kpi_projection.js` + `exports.getSiteKpiProjection` (onCall, `europe-west3`): Auth + `assertSameOrg` + Rolle admin||teamlead; Teamlead-Sites aus `employeeSiteAssignments` validieren (`isPrimary` existiert bereits — alle zugewiesenen Sites erlaubt, isPrimary nur Default-Vorauswahl); posDailyStats per Admin SDK lesen und NUR projizierte Felder liefern (`revenue_gross_cents`, `sales_count`, `refund_count`, `business_day`, `site_id` — snake_case, Callable-Konvention; KEINE cogs-/net-Felder); Range-Cap ~400 Tage; Logging ohne PII.
- Client: Invoker-Seam in `FirestoreService`; Dashboard-Kassen-Sektion für Teamleads über die Projektion; bei `not-found`/`unavailable` → Hinweis-State, **KEIN stiller Direkt-Read-Fallback** (würde das Scoping aushebeln — bewusste, begründete Abweichung vom Hybrid-Muster).
- **Rules-Verengung: erster Schnitt NUR posDailyStats** read auf `isAdmin` (Prüf-Befund hoch: die posReceipts-Verengung würde den verifiziert posReceipts-lesenden Teamlead-Tagesabschluss brechen — `loadDailyClosings` liest posReceipts direkt, `/tagesabschluss` ist admin+teamlead). posReceipts-Verengung = eigener Folge-Meilenstein mit DailyClosing-Projektion.
- **Deploy-Reihenfolge zwingend: functions VOR rules** (sonst bricht Teamlead-Lesen kurz).
- **Tests:** Node (unauthenticated, fremde Org, fremde Site, Key-Set-Assertion ohne cogs, Range-Cap); Flutter (Projektion rendert ohne Rohertrag; `unavailable` ⇒ Hinweis + kein Direkt-Read) · **Aufwand:** L · **Abhängig:** REPORTING-1/3/4, Q0

### REPORTING-8: Deploy, Backfill-Abnahme, Doku — Status: offen
- Vorgelagerter Kassen-Stack-Deploy + `rebuildPosDailyStats`-Backfill (aus Q0); Reporting-Deploy (functions → rules); Web: `flutter clean` PFLICHT vor `flutter build web`.
- Abnahme auf Prod: 3 Rollen-Durchstiche (admin/teamlead/employee): Kacheln/Drill-Downs/Redirects/Rules-Denys.
- CLAUDE.md: Routen `/kennzahlen`, `/standortvergleich`, `/mitteilungen`, `/dokument-bestaetigungen` ergänzen; Index-Zählstand korrigieren.
- **Aufwand:** S · **Abhängig:** REPORTING-4/6/7

---

## Empfohlene Gesamt-Reihenfolge (Wellen)

Jeder Bereich ist unabhängig baubar; die Wellen ordnen nur global nach Nutzen/Abhängigkeit:

| Welle | Inhalt | Charakter |
|---|---|---|
| 0 | **Q0** (Commit + Sammel-Deploy) | Vorbedingung, keine Codeänderung |
| 1 | WW-1, WW-3, DATEV-1, DATEV-2, PERSONAL-1, REPORTING-1, REPORTING-2 | deploy-freie Quick Wins, sofort baubar |
| 2 | **Q1**, **Q2**, WW-2, DATEV-3, PERSONAL-2, PERSONAL-4, REPORTING-3, **PERSONAL-9/Q4** | Fundament-Bausteine + Kern-Substanz |
| 3 | WW-6, WW-8, WW-9, DATEV-5, PERSONAL-3, PERSONAL-6, REPORTING-4, REPORTING-5 | große fachliche Brocken |
| 4 | WW-4, WW-7, WW-10, **DATEV-4**, PERSONAL-7, PERSONAL-8, REPORTING-6 | Härtungen + Ausbau (DATEV-4 erst nach DATEV-5 + Q1!) |
| 5 | WW-5, PERSONAL-5, REPORTING-7, DATEV-6, REPORTING-8 | Nightlies, Rules-Verengung, Abschluss-Deploys |

**Aufwands-Summe (grob):** WW ≈ 4×S + 5×M + 2×L · DATEV ≈ 2×S + 2×M + 2×L · PERSONAL ≈ 2×S + 7×M · REPORTING ≈ 3×S + 3×M + 2×L · Querschnitt ≈ 1×S + 2×M (Q3/Q4/Q5 sind in den Bereichen mitgezählt).

## Offene Fragen (Entscheidungen vor/parallel zum Bau)

**Extern (Steuerberater):**
1. DATEV-Lohn-Zielformat: LODAS oder Lohn&Gehalt? Mandantenspezifische Lohnartnummern; Golden-Tests gegen eine echte Import-Vorlage abnehmen.
2. BU-Schlüssel (19→'3', 7→'2'?), Geldtransit-/Kassen-Konten je SKR, Behandlung Einlagen/Entnahmen/Fremdgeld (DATEV-5); Disclaimer bleibt bis zur Bestätigung.
3. GoBD-Anspruch Inventur-Archiv (WW-10) + EXTF-Reproduktion statt Datei-Persistenz (Q2): genügt das, oder zusätzlich revisionssichere externe Ablage (Storage-Upload)?

**Fachlich (Betreiber):**
4. Festschreibung: monatlich (vorgeschlagen) vs. jährlich; Entsperren wirklich unmöglich (nur Console) oder auditierter Admin-Entsperr-Pfad?
5. Lohn-Export bei nicht festgeschriebenem Monat: Warnung mit Override (geplant) oder Hard-Block?
6. Übermengen im Wareneingang: annehmen mit Leitung-Toggle (geplant) oder nur protokollieren?
7. Mehrbenutzer-Inventur: reicht Sichtbarkeit „wer hat zuletzt gezählt" (geplant) oder Bereichs-Zuteilung je Zähler?
8. Zahlarten-Transit-Buchungen: als eigene Journal-Zeilen (Vorschlag) oder nur Export-Zeilen? (beeinflusst Kostenstellen-Reports)
9. Lohnkosten-Allokation je Site als Richtwert akzeptiert (MA arbeiten in beiden Läden)?
10. Teamlead im Standortvergleich nach REPORTING-7: nur eigene Site ohne Vergleich, oder beide erlaubt?
11. Export-Historie teamlead-lesbar oder admin-only (geplant: admin-only, trägt Umsatz-Summen)?
12. Push-Kategorie „Lieferung": Default an/aus für Bestandsnutzer?
13. Inventur-Betriebsmodus (WW-9): Soll eine offene Session Bestandsbuchungen des Standorts/der gezählten Kategorie sperren oder nur warnen — oder genügt die Stale-Prüfung beim Abschluss?
14. Aufbewahrungsfristen für `datevExportRuns` (Q2): konkrete Frist (6 vs. 10 Jahre je Unterlagen-Art) mit dem Steuerberater festlegen; automatisches Löschen nach Fristablauf gewünscht?

*(Entschieden im Review vom 12.07.2026: DATEV-Lohn-Config liegt in `financeConfig/datevLohn` admin-only, NICHT im generischen config-Block — s. PERSONAL-2.)*

## Externe Abhängigkeiten & Risiken

- **Deploy-Stau (Q0)** ist die größte Einzelabhängigkeit — ohne ihn laufen neue Rules-Features still in lokale Fallbacks. Rules-Deploys schieben immer den GESAMTEN gestauten Diff mit → jeweils komplett reviewen.
- **Blaze** ist produktiv gegeben (Scheduler/Admin SDK ok); Push-Sichtbarkeit hängt zusätzlich an `APP_PUSH_ENABLED` + APNs — deshalb Q4 (Inbox) als Fallback-Sichtbarkeit.
- **God-Files wachsen weiter:** `inventory_provider.dart` (~3900 Z.) und `inventory_screen.dart` (~4000 Z.) bekommen durch WW-4/6/8 deutlich Zuwachs — bewusste Entscheidung nötig: bisherige Linie beibehalten oder WW-8 als Anlass für einen eigenen Inventur-Provider (dann NACH Inventory in die main.dart-Kette).
- **Rules-`get()`-Kosten** (DATEV-4): 1–2 Reads je Journal-Write, bei n-zeiligem Tagesabschluss n Reads — bewusst akzeptiert (Monats-Lock-Präzedenz), dokumentieren.
- **Doku-Drift:** CLAUDE.md nennt 14 Composite-Indexe, real sind es 25 — bei der nächsten CLAUDE.md-Pflege korrigieren (in DATEV-6/REPORTING-8 enthalten).
