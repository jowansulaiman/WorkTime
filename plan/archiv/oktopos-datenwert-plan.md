# OktoPOS-Datenwert-Plan — maximaler Nutzen aus den Kassendaten

> Für **Strichmännchen & Tabak Börse** (zwei Standorte einer Org). Baut auf der bestehenden
> OktoPOS-Anbindung auf ([oktopos-kassenanbindung.md](oktopos-kassenanbindung.md)).
>
> **Stand: code-verifiziert (Tiefen-Review 30.06.2026).** Die erste Fassung verkaufte mehrere
> Bausteine als „wiederverwenden", die real **neu gebaut** werden müssen. Korrigiert sind v.a.:
> (1) Velocity läuft **nicht** auf `watchStockMovements` (hartes `limit=100`); (2) der **USt-Split
> 19/7** hat im bestehenden DATEV-Export **kein** Daten-Gegenstück; (3) das `posReceipts`-Schema ist
> nur teils durch die OktoPOS-Rohdaten gedeckt; (4) `posReceipts` braucht **eigene Rules + Indizes**.
> Der **Kernnutzen jedes Strangs bleibt baubar** — die Korrekturen betreffen versteckten Aufwand.

## 1. Leitidee

Der größte und für WorkTime **einzigartige** Hebel ist die **Verschmelzung von Kassendaten mit
Bestell-, Finanz- und Personalplanung in EINER App** — das kann kein reines POS-System. Derselbe
`transactionDate`-Strom, der den **Bestellbedarf** treibt, treibt auch den **Personalbedarf**
(Auto-Schichtplaner); derselbe Beleg, der den **Rohertrag** liefert, deckt per Soll-Ist den
**Schwund** auf und füllt den **Tagesabschluss**. Wir ziehen die Belege schon — heute wird alles
außer der Menge verworfen.

## 2. Fundament (P0) — Verkaufsfakten-Layer

Pflicht-Vorarbeit für ~80 % der Auswertungen. Neue org-skopierte Collection, idempotent,
kostenbewusst (**+1 Write/Beleg** zusätzlich zur bestehenden Mengen-Buchung).

### Schema — mit Feldverfügbarkeit (gegen OktoPOS-Swagger zu verifizieren!)

`organizations/{orgId}/posReceipts/{posId}` — **Doc-ID kassen-/standort-qualifiziert**
(`<cr|siteId>-<referenceNumber>`; `referenceNumber` ist **nur je Kasse** eindeutig → sonst
Cross-Store-Kollision). Re-Sync = `set(merge:true)` (überschreibt; anders als movements, die per
`batch.create`+`getAll`-Filter nie überschreiben).

```
// gesichert (heute schon im Pull verfügbar):
referenceNumber, type (sales|refund|cash), training,
businessDay ("YYYY-MM-DD"), transactionDate (Timestamp),
siteId, cashRegisterId,
grossCents (Money.decimal ×100, mit Math.round — NICHT truncaten),
taxes: [{ratePercent, netCents, taxCents, grossCents}],   // USt nur BELEGWEIT (kein Satz je Position!)
lines: [{productId, externalReference, scannedBarcode, quantity, unitPriceCents, discountCents, category}]

// "sofern OktoPOS-Swagger sie liefert" — VOR Bau verifizieren:
cashierId?, cashierName?, customerId?, payments?: [{method, amountCents, subType}]
```

- **Korrektur Steuer:** OktoPOS liefert den Satz **nur belegweit** (`taxes[]`/`ReceiptTax`),
  `LineItem` hat **kein** Steuerfeld → **kein `taxRateBp` je Zeile**. Einheit = **ganze Prozent**
  (`ratePercent`, konsistent zu `Product.taxRatePercent`), **nicht** Basispunkte — sonst zwei
  Steuer-Einheiten in derselben App (Footgun). Geld in **Cents**.
- **`type=cash`** (Bargeld-Ein/Auszahlung, Kassensturz) wird heute als `skippedNonSales`
  **verworfen** (`functions/index.js`) → für **Kassendifferenz** (P2.0) nötig: **Function-Änderung**,
  um cash-Belege zu speichern (aber aus Umsatz/Marge ausschließen). `training=true` ebenso speichern,
  aus allen Umsatz-Aggregaten ausschließen.
- **Granularität:** `lines[]` **eingebettet** (1 Write/Beleg statt 1+N) — Kiosk-Bons < ~20 Positionen.
- **Andockpunkt:** gleicher `db.batch()` wie die Bestandsbuchung in `syncOktoposTransactions`.

### NEU nötig (im ersten Entwurf gefehlt)

- **firestore.rules-Block** (Default ist DENY → ohne Block liest niemand):
  ```
  match /posReceipts/{posId} {
    // PII (cashierName/customerId) -> eng an Admin/echte teamlead-Rolle, NICHT canManageInventory
    // (= isAdmin()||canManageShifts(), zu breit). Schreiben nur serverseitig (Admin SDK).
    allow read: if sameOrg(orgId)
        && (isAdmin() || roleIsTeamLeadValue(currentUser().data.role));
    allow write: if false;
  }
  ```
- **Composite-Indizes** (`firestore.indexes.json`) je geplanter Query: `siteId + transactionDate`
  (Zeitreihe/Benchmark — **einziger tatsächlich genutzter Index**: auch der Tagesabschluss lädt
  über die `transactionDate`-Range und gruppiert clientseitig nach `businessDay`, weil Belege
  ohne `businessDay` sonst herausfielen; siehe [kassen-modul.md](kassen-modul.md) §2a/V1).
  ~~`siteId ASC + businessDay DESC`~~ erst ergänzen, wenn wirklich direkt per `businessDay`
  gequert wird; optional `siteId + cashierId` (Kassierer-Anomalie). Reiner `businessDay`-Range
  ohne zweites Feld braucht keinen Composite-Index.
- **Hybrid:** `posReceipts` bewusst **KEIN** `DatabaseService`-Key (nicht in `_orgScopedCollectionKeys`)
  → read-only Cloud-Stream, **kein** local fallback, keine Spiegelung von PII.
- **Betrieb:** läuft auf **Blaze** (die Anbindung braucht ohnehin Outbound + Secret Manager +
  Scheduler) — Free-Tier-Write-Budget gilt, aber nicht „Spark".

**Aufwand:** M · **KPI:** % der `sales+refund`-Belege mit persistierten Fakten = 100 %.

## 3. Phasen (nach Wert/Aufwand)

### Gemeinsame Voraussetzung für P1.1/P1.2/P2.2 — Bewegungs-Historie abfragbar machen

**Korrektur (HIGH):** `watchStockMovements` hat ein hartes `limit = 100`
(`firestore_inventory_repository.dart`), `recentMovements` gibt genau diese 100 — bei Kiosk-Volumen
nach wenigen Tagen erschöpft. `dailyVelocity`/`coverageDays` **existieren nicht**. Die im Plan
geforderte ≥4-Wochen-Aggregation ist damit **nicht** „kostenlos parallel". Nötig:
- **neue Range-Query** `getStockMovementsInRange(orgId, from, to, {siteId})` (die Indizes
  `(siteId,createdAt)`/`(productId,createdAt)` existieren bereits, `firestore.indexes.json`), **oder**
- **serverseitige Velocity-Vor-Aggregation** (täglicher Job schreibt `salesVelocity/{siteId}-{productId}`).

Empfehlung: Range-Query zuerst (kleiner), Vor-Aggregation erst bei Kostendruck.

### P1 — Bestand & Kapital (braucht die Bewegungs-Range-Query oben)

| # | Feature | Nutzen | Andockpunkt | Aufw. | KPI |
|---|---|---|---|---|---|
| 1.1 | **Sell-Through & Reichweite** je Artikel/Standort | Basis aller Bestand-Features; „Marlboro reicht 3 Tage, Feuerzeug-Display 90"; spart 1–2 h/Woche „gefühltes" Nachschätzen | **neu** `InventoryProvider.dailyVelocity/coverageDays` aus Range-Query; Chip/Spalte im Bestand-Tab | M | Out-of-Stock-Tage Top-50 ↓; Lagerwert (Reichweite >90 T) ↓ |
| 1.2 | **Dead-Stock-Report + Cross-Site-Umlagerung A↔B** | Regalplatz ist die knappste Ressource; mehrere 100 € totes Kapital/Laden freisetzbar; Umlagerung = barer Gewinn | Filter „Ladenhüter" im Bestand-Tab; Vorschlag via `StockMovementType.transfer` (existiert) | S* | Totes Kapital (EK, 0 Verkauf >60 T) ↓ |
| 1.3 | **Datengetriebener Meldebestand/Zielbestand** → Bestellkorb | Renner höhere, Langsamdreher niedrigere Schwellen; 5–15 % weniger gebundenes Kapital | `minStock/targetStock` als **Vorschlag** im Artikel-Editor; `suggestedReorderQuantity`-Pfad; Lieferzeit aus `PurchaseOrder.orderedAt→receivedAt` **oder `Supplier.leadTimeDays` (existiert bereits)** | M | Gebundenes Kapital ↓; Fehlmengen-Tage ↓ |

*1.2 ist S **nur**, sobald die Range-Query (oben) steht — auf der reicht es nicht.

*Risiko P1:* Velocity erst ab ~4 Wochen belastbar („Datenbasis: X Tage"). Out-of-Stock verzerrt
Velocity (verkauft=0 ≠ keine Nachfrage). Saisonartikel nie automatisch auslisten.

### P2 — Finanzen, Marge & Schwund (braucht P0-Fakten)

| # | Feature | Nutzen | Andockpunkt | Aufw. | KPI |
|---|---|---|---|---|---|
| 2.0 | **Tagesabschluss → Buchhaltung/DATEV** + Kassendifferenz | DATEV-fertige Tagesumsätze, USt-Split 19/7, Zahlart bar/Karte, Bargeld-Soll vs. gezählt | siehe **Korrektur unten** — NICHT einfach „wiederverwenden" | **L** | Tage mit Auto-Abschluss; Kassendifferenz/Monat |
| 2.1 | **Rohertrag & ABC nach DECKUNGSBEITRAG** (nicht Umsatz!) | Tabak-Kern: Zigaretten = Riesenumsatz, ~6–8 % gebundene Spanne, kaum DB; Gewinn aus Getränken/Snacks/Süßware/Zubehör/Lotto → margenstarke Impulsartikel verdienen Kassenplatz | P0 `lines[].quantity × (sellingPriceCents − purchasePriceCents)`, realisiert via `unitPriceCents − discountCents`; neuer Screen „Sortimentsanalyse" (admin-only) | M | Gesamt-Rohertrag/Monat ↑; C-Artikel-Anteil ↓ |
| 2.2 | **Schwund-/Inventurdifferenz-Report** | Schwund erstmals **messbar in €**; an der margenarmen Zigarettenwand = direkter Gewinn | Bewegungs-Range-Query (oben) `issue`+`refund` vs. `receipt`/PO + `stocktake`; Differenz als `adjustment` (Audit) | M | Schwundquote (€-Diff/Umsatz) je Laden/Gruppe ↓ |
| 2.3 | **Tages-Gesundheits-Check / Multi-Store-Benchmark** | Chef sieht früh, wenn ein Laden schwächelt; Nightly Ist vs. Wochentag-Schnitt + vs. anderem Laden → Push „−34 %" | erweitert `oktoposNightlySync`; Home-Dashboard-Kachel + Benachrichtigung | M | Reaktionszeit auf Einbrüche ↓ |

**Korrektur P2.0 (HIGH) — USt-Split ist NICHT durch DATEV gedeckt:** `datev_export.dart` dokumentiert
explizit **„keine Steuerschlüssel"**, die BU-Schlüssel-Spalte (`cols[8]`) wird nie gesetzt; `JournalEntry`
hat **kein** Steuer-/Netto-Feld und kennt **genau einen** `costType` + **ein** `amountCents` pro Buchung.
Ein Tagesabschluss mit USt-Split 19/7 braucht daher **n JournalEntries** (je Satz eine Zeile, **dediziertes
Erlöskonto je 19/7**, deterministische Teil-IDs z.B. `pos-<businessDay>-<siteId>-<ratePercent>`) **oder**
`JournalEntry`/`DatevExport` um BU-Schlüssel + Netto/Steuer zu erweitern (6-Stellen-Kopplung + DATEV-Spalte 8).
**Konto-Zuordnung explizit**, nicht über die Namens-Heuristik `_resolveCostTypeByNeedles` (kann „Umsatz 19"
und „Umsatz 7" nicht trennen, überspringt zudem still bei fehlendem Konto). **Zahlart-Split & Kassendifferenz**
haben **kein** Journal-Feld → reine **`posReceipts`-Auswertung**, nicht DATEV. Das **Poster-Muster selbst**
(`setRevenueJournalPoster`/deterministische `co-`/`po-`-IDs/`set(merge)`) und `costCenterForSite` sind tragfähig
und wiederverwendbar.

*Risiko P2:* fehlende `purchasePriceCents` → Artikel als **„unbewertet"** ausweisen, nicht als 0. Schwund
**nur** auf Artikel-/Warengruppenebene, NIE je Mitarbeiter. 2.3 mit Mindestumsatz-Floor.

### P3 — POS × Personalplanung (der einzigartige Hebel)

| # | Feature | Nutzen | Andockpunkt | Aufw. | KPI |
|---|---|---|---|---|---|
| 3.1 | **Umsatzbasierte Besetzung: `StaffingDemand.requiredCount`-Vorschlag** | Belege-pro-Stunde je Wochentag/Standort → „Fr 16–19 = 38 % der Bons → 2. Kraft". **Anonymer Beleg-Zähler** | `StaffingDemand.requiredCount` je weekday/`TimeWindow` (`lib/models/site_schedule.dart`; `staffingDemands` in `lib/models/site_definition.dart`) als editierbarer Vorschlag; `ShiftSlotGenerator` (`lib/core/shift_slot_generator.dart`) liest die Demands → bessere Auto-Plan-Slots | L | **Umsatz/Personalstunde** ↑; Personalkostenquote ↓ |
| 3.2 | **Storno-/Refund-Anomalie je Kassierer** | Kiosk-Schwundmuster (kassieren→stornieren→Bargeld behalten); z-Wert vs. Standort-Schnitt | P0 `type`/`cashierId`; admin-only Block; Alert via `notification_screen` | M | Inventurdifferenz ↓ |

**Korrektur P3.1 (MED):** Der **Kern** (editierbarer `requiredCount`-Vorschlag) ist **ohne Modelländerung**
baubar — gut. Aber: (1) die **Heatmap ist eine neue, eigene Darstellungsschicht** aus dem Belege-Profil,
**kein** Nebenprodukt von `ShiftSlotGenerator` (der splittet Demand-Fenster wieder in Schicht-Blöcke). (2)
`StaffingDemand` trägt **kein** Quell-/Begründungsfeld → die Begründung „38 % der Bons" lässt sich nicht
persistieren (nur die Zahl). Will man sie speichern → neues optionales Feld auf `StaffingDemand`
(Zwei-Serialisierungs-Regel) **oder** separate Profil-Collection.

*Risiko P3:* **3.2 ist mitbestimmungs-/datenschutzrechtlich SEHR sensibel** (Leistungskontrolle) → strikt
admin-only, Zweckbindung, z-Wert **+ Mindest-Fallzahl**, **Verdachtshinweis, NIE Automatik-Sanktion**; vor
Einführung Mitbestimmung klären.

### P4 — Feinschliff & Prognose (opt-in, zuletzt)

- **4.1 Laden-Vergleich** (M): Listungslücken + Umlagerung A↔B (braucht Bewegungs-Range-Query).
- **4.2 Cross-Sell/Warenkorb** (L): aus P0 `lines[]` aggregierte Co-Occurrence (keine Roh-Belege horten).
- **4.3 Wetter-/Saison-Faktor** (L): Open-Meteo (nicht OktoPOS), graceful degradation Faktor=1 bei Ausfall.

## 4. KPIs & ROI-Logik

- **Bestand/Kapital (P1):** Out-of-Stock-Tage Top-50, Ø Lagerreichweite, gebundenes Kapital (`Σ stockValuePurchaseCents`), totes Kapital. *ROI:* freigesetztes Kapital + vermiedene Leerverkäufe.
- **Finanzen (P2.0):** Tage mit Auto-Abschluss, Kassendifferenz/Monat, Buchhaltungs-Zeitersparnis.
- **Marge (P2.1):** Gesamt-Rohertrag/Monat, DB je Warengruppe, C-Artikel-Anteil.
- **Schwund (P2.2):** Schwundquote (€-Diff/Umsatz) je Laden/Gruppe.
- **Personal (P3):** **Umsatz pro Personalstunde**, Personalkostenquote, Überstunden in Leerlauffenstern.

## 5. Querschnitt

- **DSGVO/Mitbestimmung:** **Anonym/unkritisch** = Velocity, Marge, Schwund (Artikelebene), Staffing-Profil (Beleg-Zähler). **Personenbezogen** = `cashierName`/`customerId` in `posReceipts`, **3.2 Kassierer-Anomalie** (admin-only, Zweckbindung, ggf. Mitbestimmung). `posReceipts`-Rules eng an Admin/echte teamlead-Rolle, `write:false`, kein local-Cache (siehe P0). Schwund **nie** je Mitarbeiter.
- **Sicherheit (API-Security-Review, `claude-skills/sicherheit/01_api-sicherheit.md`):**
  - **Secret (✓ schon richtig):** `X-API-KEY` nur im **Secret Manager**, Aufruf server-zu-server (Backend-Proxy-Muster) — nie im Client/Bundle/Firestore/dart-define; nie in Logs/Fehlermeldungen/Rückgaben. `AppConfig.oktoposEnabled` ist **nur UX**, keine Sicherheitsgrenze → Durchsetzung über `assertAdmin`/`assertSameOrg` + `posReceipts`-Rules.
  - 🟠 **API10 — fremde Daten bounden/validieren:** OktoPOS-Antworten sind Fremddaten. Vor dem Schreiben in `posReceipts` **Größen/Anzahl kappen** (max. Positionen/Beleg gegen Firestore-1-MiB-Limit, max. Belege/Lauf) und Typen tolerant parsen (`asInteger`/`stringOrNull`, kein Hart-Cast). Bestehende `OKTOPOS_MAX_PAGES`-Kappe beibehalten.
  - 🟠 **CSV/DATEV-Formel-Injektion:** OktoPOS-Strings (Artikel-/Kassierer-/Kundenname) in DATEV-/CSV-Export (P2.0) **maskieren** — führendes `= + - @` neutralisieren (`'`-Präfix), sonst Code-Ausführung in Excel. Bestehende `ExportService`-CSV mitprüfen.
  - 🟠 **PII-Minimierung:** in `posReceipts` möglichst nur `cashierId`/`customerId` speichern, Namen erst im UI aus dem Team-/Kontakt-Bestand auflösen (kleinere PII-Fläche); `cashierName` nie loggen. **Retention/Zweckbindung** definieren (Belege nach X Monaten anonymisieren/löschen).
  - 🟡 **API07 SSRF:** `config.baseUrl` ist admin-gesetzt → Host **allowlisten** (z.B. erwarteter `*.oktopos.net`-Host) zusätzlich zur https-Pflicht; schützt bei kompromittiertem Admin-Konto gegen Calls auf interne Endpunkte.
  - 🟡 **BOLA-Defense-in-Depth (API01):** `orgId` immer aus der Auth ableiten (✓), zusätzlich `siteId` gegen die Standorte der Org prüfen (kein Schreiben in fremde Site-Partition). Teamlead-Lesezugriff auf `posReceipts` ggf. auf zugewiesene Standorte begrenzen, falls Cross-Store-PII unerwünscht.
  - 🔵 **Throttle:** Mindest-Intervall je Org für den manuellen Sync-Trigger (gegen Hammering der Hersteller-API/Kosten); App Check bleibt aktiv (ersetzt keine Server-Authz).
- **API-Architektur (`claude-skills/architektur/06_api-architektur.md`):**
  - **Paradigma (✓):** Callables (RPC) für Befehle (sync/push/lookups) + Firestore-Streams für Reads (Realtime+Offline) — bewusst, konsistent, **kein neues Paradigma**. OktoPOS bleibt REST hinter der Function.
  - **Anti-Corruption Layer:** Die Cloud Function ist die Übersetzungsgrenze OktoPOS-Modell ↔ WorkTime-Modell und schirmt gegen OktoPOS-**Version-Drift** (swagger 1.0.1 vs. Redoc 1.3.0) ab — konsumierte Vertragsversion **pinnen**, angenommene Felder (`payments`/`cashier`/`customer`) vor Nutzung gegen Swagger verifizieren.
  - 🔴 **Aggregate-first (BFF) statt Roh-Reads:** Dashboards lesen **vorverdichtete** Aggregat-Docs (`salesDaily/{siteId}-{businessDay}`, `salesVelocity/{siteId}-{productId}`), **nicht** Roh-`posReceipts`/-Bewegungen — ein Round-Trip, kleine Payload (mobil!), weniger Read-Kosten; löst zugleich das `limit=100`-Problem. Drill-down-Listen via **Cursor-Pagination** (`startAfter`), nie Fixed-Limit-Truncation.
  - **Idempotency-Keys (✓):** deterministische Doc-IDs = Idempotenz der POST-artigen Sync/Push-Operationen (retry-sicher auf instabilem Netz).
  - **Versionierung (✓ Mechanismus da):** `apiVersion`/`clientApiVersion` + `assertSupportedVersion` + Force-Update; neue Callable-Ergebnisfelder **nur additiv** (alte Clients ignorieren sie via tolerantem `_callableResultData`), Keys nie umbenennen.
  - 🟠 **Typisierte Ergebnis-Verträge:** Callable-Resultate als **Dart-Modelle** (`OktoposSyncResult`/`…PushResult`, Zwei-Serialisierungs-Regel) statt roher `Map<String,dynamic>` an die UI — gegen handgepflegten DTO-Drift.
  - 🟡 **Realtime > Polling:** der OktoPOS-Push-Dienst (Webhook, P2b in [oktopos-naechste-schritte.md](oktopos-naechste-schritte.md)) ist die vom Standard bevorzugte Change-Feed-Form ggü. dem nächtlichen Polling; `lastBusinessDay` ist bereits ein `since`-Cursor (grob → bekannter Re-Pull-Trade-off).
  - 🔵 **DX/Test:** Node-Functions-Testharness (gemocktes `fetch` + Firestore-Emulator) als Contract-Test; Trace-ID `_request_id` client→server existiert bereits (✓); Latenz/Fehler je Callable + apiVersion monitoren.
- **Error-Handling & Resilienz (`claude-skills/entwicklung/12_error-handling-resilience.md`):**
  - 🟠 **Typisierte Ergebnisse statt Exceptions (#1/#2):** Callable-Ausgänge als `sealed`/`Result<Summary, OktoposFailure>` (`NotConfigured`/`PermissionDenied`/`Unreachable`/`PartialFailure(results)`/`Unknown`) — Service mappt `FirebaseFunctionsException.code` → Failure, UI `switch`t (z.B. `NotConfigured` → Einstellungen öffnen, `PartialFailure` → Detailliste). Heute kollabiert alles in eine Snackbar; `StateError` für „lokaler Modus" ist ein **erwartbarer** Fall → Exception/Result, kein Error-als-Kontrollfluss.
  - 🟠 **Sync-Fehler beobachtbar machen (#8) — Kern-Risiko:** ein **still fehlschlagender Nightly-Sync = unsichtbar veralteter Bestand**. `config/oktoposSync.sites[siteId]` um `lastSyncStatus`/`lastError`/`lastSyncAt` ergänzen, im Admin-UI anzeigen, an **2.3 Tages-Gesundheits-Check** koppeln (kein Beleg seit >24 h → Alert). Client-Fehler an Crashlytics/Sentry, transient vs. dauerhaft klassifiziert.
  - 🟠 **Netzwerk-Resilienz der OktoPOS-Calls (#5):** Timeouts ✓, aber **Retry mit Backoff+Jitter** (max. 3) auf transiente OktoPOS-Antworten (5xx/Netz/Timeout) ergänzen — **sicher, weil idempotent** (deterministische IDs / find-before-create). Optional Circuit-Breaker bei längerem OktoPOS-Ausfall.
  - 🟡 **In-flight-Sperre (#7):** Sync-/Push-Buttons während des Laufs deaktivieren (Race/Doppel-Tap; analog Scanner-`adjustStock`).
  - 🟡 **Dashboard-Zustände (#4) + Offline (#6):** Auswertungen mit Loading/Empty/**Error**/Success + Retry, **Error-Boundary je Widget** (ein fehlender Aggregat-Read bricht nicht den Screen). Fehlende Kassendaten = **Empty** („noch kein Abgleich"), nicht Error. Offline = Banner + letzte bekannte Daten (stale-while-error); operative Nachbestellung degradiert graceful (Cache + „Stand: …").
  - ✅ **schon gut:** Idempotenz (retry-sichere Basis), Timeouts überall, `mounted`/`dispose`-Hygiene in Sync-/Settings-UI, Trace-ID, strukturierte Logs ohne PII/Key, per-Artikel/-Kunde graceful Degradation in den Push-Loops, Cursor-nicht-vorschieben-bei-Fehler → volle Wiederherstellbarkeit ohne Datenverlust.
- **UI/UX (`claude-skills/architektur/03_ux-ui-design.md`):**
  - **Leitprinzip — Insight + Aktion, nicht Daten-Wand:** der Ladeninhaber ist kein Analyst. Jede Auswertung führt mit **1–3 KPIs + empfohlener Aktion** („Marlboro reicht 3 Tage → nachbestellen"), Details per progressive disclosure; **pro Screen genau eine** primäre CTA.
  - **Design-System-first:** neue Screens aus den vorhandenen Tokens ableiten (`AppTheme`, `appColors` für success/warning/info, `surfaceContainerLow`, NotoSans, lib/ui-V2) — **keine** pro-Screen-Chart-Styles; **eine** wiederverwendbare KPI-Karte + ein Chart-Stil (file-private `_SectionCard` ggf. nach `lib/widgets/` heben statt kopieren).
  - 🔴 **Barrierefreiheit (KRITISCH):** Farbe **nie** alleiniger Indikator — ABC (A/B/C-Badge), Reichweite/Low-Stock, Benchmark −34 %, Schwund: Icon/Text/Muster **zusätzlich** zur Farbe (rot/grün-Blindheit). Kontrast ≥ 4.5:1 in **beiden** Themes; Charts mit `Semantics`-Text-Summary; Dynamic Type 200 % ohne Tabellen-Bruch.
  - 🔴 **Touch (KRITISCH):** Ziele ≥ 48 dp (Chips/Filter/„übernehmen"); Chart-Tooltips per **Tap** (≥ 44 pt Datenpunkt), **Hover nie alleinige** Interaktion (Web-Backoffice); async Aktionen Button disable+Spinner.
  - 🟠 **Responsive (HOCH):** Phone (Inhaber) **und** Web/Desktop (Backoffice) — Window Size Classes (kompakt < 600 / medium / expanded > 840), KPI-Grid reflowt, **Tabellen → Karten** auf schmal (kein Horizontal-Scroll); „Laden-Vergleich" auf Phone gestapelt. Skeletons/Shimmer ab ~300 ms; lange Listen `ListView.builder` (ab ~50).
  - 🟠 **Datenvisualisierung (#8):** Chart-Typ zur Datenart — Trend/Velocity → **Linie/Sparkline**, ABC/Ranking/Rohertrag → **Balken** (kein Pie bei >5 Kategorien), Staffing → **Heatmap-Grid** mit Werten; oft ist eine **KPI-Zahl** besser als ein Chart. `fl_chart` (vorhanden), **Tabular Figures** (`FontFeature.tabularFigures()`) für Zahlenkolonnen, de_DE-Zahlen/€, Loading/Empty/Error-States.
  - 🟠 **Navigation:** Fragmentierung vermeiden — **ein Auswertungs-Hub** (vorhandenes `/bestell-auswertung`/`OrderAnalyticsScreen`) als Heimat, Bestand-Tab-Chips als Inline-Glances + Deep-Links; Muster nicht mischen, Back mit Zustand (`PageStorageKey`), admin-only via `AppRoutes`+Permission.
  - 🔴 **Anti-Patterns (Pre-Delivery):** keine Emojis als Icons (Vektor-Icons + Größen-Tokens 16/20/24); keine hartkodierten Farben; Light **und** Dark testen; Press-States verschieben kein Layout.
- **State-Management & Frontend-Architektur (`claude-skills/entwicklung/13_frontend-architektur.md`):**
  - **Kein SM-Wechsel:** in `provider`/ChangeNotifier bleiben (Kette ist tragend; „nicht mehrere Frameworks mischen") — Riverpod/Bloc **nicht** einführen, deren Prinzipien (unidirektional, immutable, granulare Rebuilds) innerhalb provider anwenden.
  - 🟠 **Eigener `SalesInsightsProvider` statt InventoryProvider aufblähen:** InventoryProvider ist schon groß; Analytik-**Read-State** (Aggregate/Velocity/KPIs) in einen NEUEN Provider, **nach** Inventory in die Kette (Kopplung #4), Cloud-Repo **lazy**, `_safeNotify`. So rebuilden Inventarliste und Auswertungen unabhängig. (Die Command-Methoden `pushOktopos*`/Config in InventoryProvider sind ok — kein persistenter State.)
  - 🟠 **Abgeleitete Werte als PURE Funktionen in `lib/core/` + Memoization:** Velocity/Reichweite/ABC/Schwund/Bestellvorschlag deterministisch & offline-testbar (wie `shift_slot_generator`/`compliance_service`); schwere Aggregation **serverseitig** (aggregate-first) bzw. via `compute()`, **nicht in `build()`**. Read-Models **immutable** (`ProductVelocity`/`DailySalesSummary`, equatable/copyWith); unidirektional (Daten runter, „übernehmen"-Events rauf an die Inventory-Command).
  - 🟠 **Granulare Rebuilds (#5/#8):** Dashboard-KPIs via **`Selector`/`context.select`** + `const` + kleine Consumer-Widgets — kein großer Consumer, der das ganze Dashboard neu baut.
  - 🟡 **Keys bei umsortierten Listen:** `ValueKey(product.id)` an Artikel-Items, wenn nach Velocity/ABC sortiert wird (sonst falsche Element-Wiederverwendung).
  - 🟡 **Ephemerer UI-State via `setState`:** Filter/Zeitraum/aktiver Tab im Auswertungs-Screen lokal, **nicht** in einen globalen Provider.
  - **Navigation (#6):** Auswertungs-Screens via go_router (`AppRoutes` + `context.push`, Permission-Gating, Kopplung #7), **kein** neuer Tab (schwere ShellTab-Kopplung) ohne Not; Deep-Links + Zustand-Erhalt (IndexedStack/`PageStorageKey`).
- **Datensynchronisierung (`claude-skills/daten/19_datensynchronisierung.md`):**
  - ✅ **Stock ist conflict-free (CRDT, #6) — bewusst so lassen:** Bestandsfortschreibung via `FieldValue.increment` = **PN-Counter**; Bewegungen = **append-only Event-Log** (deterministische IDs). Gleichzeitige Quellen (POS-Sync, manuelle Korrektur, Wareneingang, Erstattung) **kommutieren** → kein LWW, kein Datenverlust. **Nicht** in ein read-modify-write zurückbauen.
  - ✅ **Delta-Sync (#3):** `lastBusinessDay`-Cursor (`since`-Stil), idempotent; nur die OktoPOS-Brücke ist (berechtigter) Eigenbau — Device↔Backend nutzt die Engine (Firestore-Offline). Tag-Granularität → bekannter Overlap-Re-Pull-Trade-off.
  - 🟠 **Konfliktstrategie EXPLIZIT machen (#5):** Artikel/Kunden/Preise = **WorkTime-autoritativ (LWW, WorkTime gewinnt)** → OktoPOS-seitige Edits werden beim nächsten Push **überschrieben**. Festlegen: **eine** Quelle je Entität. **Footgun:** `cashierCanChangePrice=true` + Preis-Push = die Kassen-Preisänderung wird überschrieben. Bidirektional (P2a MenuApi-Pull) nur mit **HLC/`updated_at`** + Konflikterkennung, nicht blind überschreiben.
  - 🟠 **Outbox für den Push (#4):** der Artikel-/Kunden-Push ist heute **manuell/synchron** → Preis-/Stammdatenänderungen **driften**, bis der Admin neu pusht. Für Near-Realtime: `oktoposOutbox`-Queue (on-save enqueue → getriggerte/geplante Function drained idempotent mit Backoff+Jitter, überlebt Neustart). v1 manueller Push ist ok — **Drift dokumentieren**, idempotentes Re-Push = Recovery.
  - 🟡 **Append-only / keine Tombstones (#3):** Annahme **fiskalische Unveränderlichkeit** (TSE) — Korrekturen kommen als neue `refund`-Buchungen, nicht als Edits/Deletes. Ein in OktoPOS storniertes Beleg-Doc propagiert **nicht** in die Bewegung (`posReceipts` wird beim Re-Pull per `set(merge)` überschrieben, die Bewegung via `create` **nicht**). **Dokumentieren.**
  - 🟡 **Eventual Consistency sichtbar machen (#7):** OktoPOS/TSE = fiskalische Source-of-Truth; WorkTime = abgeleitetes, eventually-consistentes Read-Model (Bestand hinkt bis zum Sync-Intervall nach). „Stand: … / zuletzt abgeglichen" + Sync-Status im UI (deckt sich mit der Beobachtbarkeit aus dem Error-Handling-Review); keine Echtzeit versprechen.
  - ✅ **Hintergrund-Sync (#8):** server `onSchedule` (nicht Device-`workmanager`) — korrekt, weil Sync server↔OktoPOS; Web-Background-Limit irrelevant.
- **Lokale Persistenz / On-Device-DB (`claude-skills/daten/16_datenbank.md`):**
  - ✅ **Bestätigt cloud-/aggregate-first:** der lokale Store ist **SharedPreferences** (K/V-JSON, kein Query/Index, „alles im Speicher") — Analytik über Wochen (posReceipts/Velocity) **kann dort nicht** laufen → muss serverseitig aggregiert werden (deckt sich mit OLTP/OLAP + aggregate-first). stockMovements/Stammdaten werden im Hybrid ohnehin **nicht** lokal gespiegelt.
  - 🟠 **Encryption at Rest (#3/#7):** SharedPreferences ist **Klartext**. PII der Belege (Kassierer/Kunde) **niemals** lokal cachen (auf gerootet/Browser angreifbar) → posReceipts/Aggregate **kein** `DatabaseService`-Key, **nicht** in `_orgScopedCollectionKeys`.
  - 🟡 **Migration der neuen Felder (#5):** `externalPosId`/`taxRatePercent`/`source`/`externalRef` — K/V-JSON hat kein Schema; die tolerante `fromMap` (Default null bei fehlendem Key) **ist** die additive Vorwärts-Migration ✓ (kein „DB löschen", bereits verifiziert).
  - 🟡 **Optional Offline-Nachbestellung (#6):** Velocity/Bestellvorschlag ist cloud-aggregiert → offline nicht verfügbar; falls nötig, **kleinen, PII-freien** Snapshot (K/V) cachen, nicht die Rohbelege. **Keine** zweite DB-Engine (Drift/Isar) einführen (Engines nicht mischen; Analytik gehört serverseitig).
- **Backend-Datenschicht (`claude-skills/daten/18_backend-daten.md`):**
  - 🟠 **OLTP/OLAP trennen (#5):** Firestore ist **OLTP** — keine schweren Analysen roh dagegen. Materialisierte Aggregate (`salesDaily`/`salesVelocity`) = pragmatischer OLAP-Layer **in** Firestore für die App-Dashboards; für schwere/ad-hoc Analytik (Mehrmonats-Trend, ABC, Warenkorb, Forecast, DATEV-Auswertung) den **Firestore→BigQuery-Export** (Firebase-Extension, CDC-artig) als echten OLAP-Pfad — SQL, billig. 2 Kioske: Firestore-Aggregate ggf. v1, BigQuery als Skalierungspfad.
  - 🟠 **Aggregations-Job = ETL-Pipeline (#6):** inkrementell (nur neue `businessDay`s), **idempotent** (deterministische Aggregat-Doc-IDs), beobachtbar (Lauf-Status); kein Vollabzug/Recompute. ELT, wenn nach BigQuery geladen wird.
  - 🟡 **Validierung am Rand + Datenqualität (#8):** ingestete Werte sanity-prüfen (keine negativen Mengen/absurden Beträge), Dedup ✓ (Idempotenz), „unbewertet"/`training`/`cash`-Ausschluss ✓, konsistente Fehlerformate ✓.
  - ✅ **APIs/Change-Feeds/BaaS (#1/#2/#4):** Callables = Command-API, Firestore-Streams = Read-Change-Feed, Cursor-Pull = Delta-Consumer, idempotente Writes ✓; Firebase-BaaS app-bedarfsgerecht (kein Over-Engineering), die OktoPOS-Brücke eine dünne, berechtigte Function; Aggregate als Cache, Invalidierung an den Sync/Change-Feed gekoppelt.
- **Backend-DB-Architektur (`claude-skills/daten/17_datenbankarchitektur.md`):**
  - 🟠 **Composite-Indizes je Query (#4) — vorab definieren, nicht raten:** posReceipts `(siteId↑, businessDay↓)` (Tagesabschluss/Zeitreihe), `(siteId, transactionDate)` (Stundenprofil Staffing), optional `(siteId, cashierId, transactionDate)` (Kassierer-Anomalie); Bewegungs-Range `(siteId,createdAt)`/`(productId,createdAt)` **existieren**. Index-Schreib-Overhead gegen die +1-Write/Beleg gegenrechnen — nur was Queries brauchen.
  - 🟠 **Aggregate = denormalisierte, RE-COMPUTABLE Read-Models (#1/#7):** raw posReceipts/movements = **Source of Truth**; Aggregate idempotent **aus raw neu berechenbar** (ganzer Tag), nicht nur inkrementell gepatcht → keine dauerhafte Divergenz. `lines[]` mit `name`/`category`/`unitPriceCents` **zum Verkaufszeitpunkt** denormalisieren (Firestore hat keine FK/Joins) → kein Orphan bei Produkt-Löschung, historisch korrekt.
  - ✅ **Multi-Tenancy = Datenebene (#5):** **alle** Analytik-Collections unter `organizations/{orgId}/` (Tenancy-Grenze + Rules-RLS), **keine** Top-Level-Collection; posReceipts read admin/teamlead, write:false; Queries strikt org-gescoped.
  - 🟡 **Hotspotting (#6):** Einzel-Aggregat-Doc + sequenzielle Belegnr-Doc-IDs sind bei 2 Kiosken unkritisch; beim **Webhook-Pfad (P2b)** aufs heutige Aggregat → `FieldValue.increment`/Distributed-Counter-Sharding; **kein** Premature-Sharding/-Partitionierung.
  - ✅ **Idempotenz = Unique-Constraint (#7):** deterministische Doc-IDs (`batch.create`/`set(merge)`) sind der Firestore-Ersatz für Unique-/Idempotency-Keys → Client-/Sync-Retries erzeugen keine Duplikate.
  - 🟡 **Dokumentgröße/Subcollection (#8):** `lines[]` eingebettet < 1 MiB halten (lines/Beleg kappen); bei häufiger Einzelpositions-Analytik (Warenkorb/Item-Velocity) → Subcollection bzw. BigQuery.
- **Observability (`claude-skills/entwicklung/14_observability.md`):**
  - 🟠 **Sync-Health als SLI/SLO + Alerting (#6/#8) — wichtigster Punkt:** `lastSyncStatus`/`lastSyncAt`/`lastError` je Standort + Kennzahlen (Sync-Erfolgsquote, unmatched-Rate, push-failure-Rate, Sync-Dauer) als **Health-Signale**; **SLO** definieren („Bestand max. X h alt", „Sync-Erfolg > 99 %") + **Cloud-Monitoring-Alert** auf Funktions-Fehler/**Nicht-Ausführung** des Nightly-Jobs (Symptom-Alarm „Bestand veraltet", keine Alert-Fatigue). Silent-Failure = veralteter Bestand → im Admin-UI sichtbar.
  - 🟠 **Client-Crash/Fehler-Reporting (#1):** Callable-Fehler an **Crashlytics/`sentry_flutter`** (transient vs. dauerhaft klassifiziert), **Breadcrumbs** (welche Aktion: sync/push/dashboard) + Custom Keys (Screen, `oktoposEnabled`); die globale Kette `FlutterError.onError`/`PlatformDispatcher.onError`/`runZonedGuarded` (vorhanden) ans Reporting hängen. **Crash-free Users ≥ 99,5 %** als Leitmetrik. **Niemals** PII/Key in Reports.
  - ✅ **Distributed Tracing (#5):** `_request_id` client→Function (W3C-traceparent-Geist) vorhanden → auf die neuen Analytik-Callables ausweiten und in Crashlytics-Breadcrumbs + Server-Logs spiegeln („App-Fehler ↔ Server-Fehler" in Sekunden).
  - 🟡 **Strukturierte Server-Logs (#2/#8):** `firebase-functions/logger` (Severity, strukturierte Felder, requestId) statt `console.log`; produktiv kein verboser Output; **kein** PII/Key (✓ bereits kein Key — vgl. flutter-logging-Skill, Redaction).
  - 🟡 **RUM/Perf (#4):** Dashboard-Ladezeiten + Sync-Dauer via Firebase Performance Monitoring (Custom Traces), segmentiert nach Plattform (Web-CanvasKit-Start, Low-End-Android); aggregate-first hält die Dashboards schnell.
  - 🟡 **Produkt-Telemetrie + Datensparsamkeit (#3):** Feature-Adoption (Sync/Push ausgelöst, Dashboard geöffnet) via Analytics-Observer; **Geschäfts-Analytik (Verkaufsdaten) ≠ Produkt-Telemetrie** nicht vermischen; DSGVO-Consent/Opt-out respektieren, nur erheben was eine Frage beantwortet.
- **Cross-Platform (`claude-skills/entwicklung/15_mobile-entwicklung.md`):**
  - ✅ **Von Natur aus plattformteilbar:** OktoPOS-HTTP liegt **serverseitig** (Functions); der Client macht nur Firestore-Reads + Callable-Triggers + Flutter-UI + `fl_chart` (pure Dart, alle Targets) → **kein nativer Code/Platform-Channel/FFI**, keine Client-Secrets (Web-Secure-Storage-Problem entfällt). Maximale Code-Teilung.
  - 🟡 **Export (DATEV/CSV/PDF, P2.0/P2.1) plattformgerecht (#7/#8):** über die **vorhandene** Download/Share-Abstraktion (`ExportService`/`printing`/`share_plus`/`path_provider`) — Web = Browser-Download, Mobile = Share-Sheet, Desktop = Datei-Speichern; **niemals `dart:io File` im Web** (wirft). `kIsWeb` zuerst, falls verzweigt.
  - 🟡 **Adaptive Dashboards (#5):** Phone (Inhaber, Touch/BottomNav) vs. Web/Desktop (Backoffice, Maus/Tastatur/Rail, dichter) — `LayoutBuilder`/Breakpoints (600/840, App-`>=1120`), eine UI-Struktur, mehrere Präsentationen (deckt sich mit UX-/State-Review). Auswertungs-Deep-Links = echte URLs (PathUrlStrategy) → im Web teil-/bookmarkbar.
  - 🟡 **Alerts plattformgerecht (#6/#8):** falls der Sync-Health-/Benchmark-Alert per **Push** geht — FCM mobil (`flutter_local_notifications`, iOS-Permission/Android-Channels), Web via Service-Worker, **kein FCM auf Desktop** → dort In-App-Signal. Capability hinter Abstraktion kapseln, nicht `Platform.isX` streuen.
  - ✅ **Plattform-Erkennung (#2):** `kIsWeb` zuerst / `defaultTargetPlatform` fürs Layout (dart:io wirft im Web); die Anbindung führt **keine** neuen ungeschützten `Platform.isX`-Aufrufe ein.
- **CI/CD & DevOps (`claude-skills/entwicklung/09_cicd-devops.md`):**
  - 🟠 **CI einführen — größte Lücke (#1/#8):** Repo hat **keine CI**, und die OktoPOS-Function-Logik ist **untestet**. Minimal-Pipeline (GitHub Actions): PR → `flutter analyze` + `flutter test` + **Functions-Job** (`node --check` / npm-test mit gemocktem `fetch` + Firestore-Emulator) + `firebase deploy --dry-run`-Validierung von rules/indexes. Symbol-Upload (`--split-debug-info`) zu Crashlytics/Sentry für lesbare Crashes.
  - 🟠 **Backend-Deploy koordiniert, Indizes VOR Queries (#6/#8):** `firebase deploy --only firestore:rules,functions,firestore:indexes`; die neuen **posReceipts-Composite-Indizes müssen VOR** den Analytik-Queries deployt sein (sonst Laufzeit-`FAILED_PRECONDITION`); Secret `OKTOPOS_API_KEYS` out-of-band (`functions:secrets:set`, nie im Repo). **Reihenfolge:** neue Callables VOR der App, die sie ruft (`apiVersion`/MIN_SUPPORTED_API_VERSION deckt alt-Client/neu-Function); braucht **Blaze**.
  - 🟠 **Remote-Feature-Flag statt nur Build-Flag (#7):** `APP_OKTOPOS_ENABLED` ist **build-time** → Umschalten erfordert Rebuild + Store-Review (Tage). Zusätzlich ein **Remote-Config-Flag** (FeatureFlagProvider/`config/appFlags`): dunkel ausliefern, je Org/% aktivieren, **Kill-Switch ohne Store-Release**. `config/oktoposSync.enabled` = server-seitiger Sync-Kill-Switch (✓). Rollout mit Crash-Raten-Gate.
  - 🟡 **Umgebungen/Config (#5):** `demode`- vs. Produktiv-OktoPOS = Umgebungen; `--dart-define-from-file` (12-Factor); idealerweise dev/staging-Firebase-Projekt, um den Sync **vor prod** gegen `demode` zu testen.
  - 🟡 **Reproduzierbarkeit (#8):** Versionen/Lockfiles pinnen (pubspec.lock ✓; für Functions ein `package-lock.json` ergänzen), Build-Nummern monoton (`APP_BUILD_NUMBER` aus CI-Run).
  - ✅ **schon gut:** keine Secrets im Repo (dart-define + Secret Manager), `--obfuscate --split-debug-info` für Mobile-Release, Force-Update/Min-Version-Mechanismus, per-Org-`enabled`-Kill-Switch.
- **Performance (`claude-skills/entwicklung/10_performance.md`):**
  - 🟠 **Backend-Roundtrips = #1-Hebel (#8):** Dashboards lesen **vorverdichtete Aggregat-Docs** (ein kleiner Read/Screen), **nicht** tausende Roh-posReceipts/-Bewegungen — sonst Latenz + Read-Kosten + Jank beim Parsen. Aggregate-first/BFF, Cursor-Pagination, kein N+1.
  - 🟠 **Schwere Ableitungen NICHT im Main-Isolate/`build()` (#5):** Velocity/ABC/Schwund **serverseitig** aggregieren; jede verbleibende Client-Berechnung über große Listen via **`compute()`/Isolate** (Web: Web-Worker-Grenze → schwere Sync-Arbeit dort besonders meiden). Teure Werte memoizen, nie pro Build.
  - 🟡 **Rebuilds minimieren (#2):** `const`-Widgets, **`context.select`/`Selector`** je KPI, separater `SalesInsightsProvider` (kleiner Rebuild-Scope) — kein großer Consumer, der das ganze Dashboard neu baut.
  - 🟡 **Listen lazy (#3):** Artikel-/Renner-Listen mit `ListView.builder`/Slivers (Pflicht ab ~50), `itemExtent` bei bekannter Höhe, Pagination bei sehr langen Listen — **nie** `ListView(children:[...])`.
  - 🟡 **Render-Kosten der Charts (#4):** `RepaintBoundary` um animierte Charts/Heatmap (isoliert Repaints), `Opacity`/`ClipPath`/Blur sparsam; viele Charts/Screen = Paint-Last → progressive disclosure.
  - 🟡 **Startzeit/Bundle (#6/#7):** Analytik-Screens **deferred** laden (Route-Level/`deferred import` im Web), nicht in den Cold-Start; `--analyze-size` im Blick; Web-CanvasKit-Startlast bedenken; auf **realen Low-End-Geräten + Browser** im Profile-Mode profilen (16 ms/8 ms-Budget).
  - 🟡 **Wahrgenommene Geschwindigkeit (#8):** Skeleton/Shimmer ab ~300 ms, Layout-Platz reservieren (kein CLS), Tap-Feedback < 100 ms (deckt sich mit UX-Review).
- **Offline-Modus / Plattform-Mechanik (`claude-skills/daten/21_offline-modus.md`):**
  - 🟠 **Offline-Scope explizit (#1):** **Analytik (posReceipts/Aggregate) und Sync/Push-Trigger sind server-gesperrt** — Cloud-Function-RPC + Echtzeit-Autorität (Kassen-Fremdbestand/Umsatz) dürfen offline **nicht optimistisch gefälscht** werden → Button **deaktiviert + Erklärung** („offline nicht verfügbar"), kein klickbar-dann-Fehler. Operativer Bestand/Bestellkorb bleibt **offline-fähig** (Firestore-Queue), Velocity/Vorschlag offline = letzter Stand + „Stand: …".
  - ✅ **Server-Sync umgeht die schwerste Offline-Grenze (#7):** der Nightly-Pull ist `onSchedule` (server) → **keine** Abhängigkeit von Device-Background (Doze/App-Standby/iOS-BGTask-Opportunismus/**kein** Web-Background). „Datenkorrektheit nie von Background-Sync abhängig" ist hier strukturell erfüllt; Resume/Foreground refresht die Firestore-Streams automatisch.
  - 🟡 **Zentrales entprelltes Online-Enum (#2):** `connectivity_plus` **+ echte Reachability-Probe** (verbunden ≠ Internet), 1–3 s entprellt, Re-Check bei `resumed`; Trigger/Dashboards lesen das Enum → offline „später"/disabled statt kryptischem `FirebaseFunctionsException`.
  - 🟡 **Web-Persistenz-Caveats (#3/#5):** Firestore-Cache im **`kIsWeb`-Zweig** (`persistentLocalCache`; `Settings.persistenceEnabled` ist Web-No-op) **vor dem ersten Read** (✓ Bootstrap prüfen), Single-Tab/Inkognito graceful; Web-IndexedDB/SharedPreferences sind **evictbar/Safari-ITP-7-Tage** → nichts Kritisches drauf verlassen (posReceipts cloud-only ist hier ein Vorteil). Die **eingebaute Firestore-Queue** reicht für Firestore-Daten — **keine** redundante Device-Outbox (die Push-Outbox aus dem Sync-Review betrifft die Nicht-Firestore-Strecke server→OktoPOS).
  - 🟡 **Offline-UX & Testen (#8):** persistenter Offline-Banner + „zuletzt abgeglichen"-Marker; serverpflichtige Aktionen ausgegraut mit Tooltip; **kein** Endlos-Spinner/kein kryptischer Fehler für erwartbares Offline. Testen: Web-DevTools-offline/Flugmodus + `integration_test` mit injiziertem Konnektivitäts-Seam.
- **Logging (`claude-skills/entwicklung/20_logging.md`):**
  - 🟠 **Server: `firebase-functions/logger` statt `console.log/error/warn` (#1/#2/#5):** die OktoPOS-Functions loggen via `console.log(JSON.stringify(...))` (traceCallable, oktoposNightlySync, addBarcodesBestEffort) → auf den **`firebase-functions/logger`** heben (setzt `severity` + `jsonPayload` fürs Cloud Logging). Severity nach Bedeutung: **403/Netzwerk = error, 404/409 (Idempotenz) = info, sonstige !ok = warn** — damit Alerting auf echte Probleme zielt.
  - 🟠 **PII-/Secret-Redaction (#4) — nicht verhandelbar:** Key wird nie geloggt ✓. Für die geplanten posReceipts/Kassierer-Anomalie/Analytik-Functions: **niemals** `cashierName`/`customerName`/Bodies/Header/ganze Fehlerobjekte loggen — nur **IDs + Aggregate** (Anzahl created/updated/failed/unmatched), `truncateError` (~200 Z., nur `error.message`). E-Mail/Telefon im Client via `AppLogger._redact` maskieren; HTTP-Pfade nur als Operation/`:param`, keine Query-/Body-Werte.
  - 🟡 **Aggregat-Logs am Ende langer Läufe (#5/#7):** Sync-Batch-/ETL-Loop **nicht per Beleg/Position** loggen — ein zusammengefasstes Log am Ende (✓ Nightly loggt Counts). Im Hot-Path/`notifyListeners`-nah nicht pro Frame loggen.
  - ✅ **Korrelations-ID (#3):** `_request_id` client→Function vorhanden → auf neue Analytik-Callables ausweiten; strukturierte Felder (`event`/`fn`/`status`/`durationMs`), deutsche Message + englische Feld-Keys.
  - ✅ **Logging ≠ Audit-Trail (#8) sauber getrennt:** Sync/Push schreiben **fachliche** Events ins `AuditProvider` (Kassenabgleich/-Artikel/-Kunden, nur Counts/siteName — keine PII), **technische** Diagnostik in Cloud-Logs; kein Doppelschreiben, Audit nur auf Erfolgspfad (`_audit?.call`). Bereits korrekt.
  - 🟡 **Client (#1/#6):** `AppLogger`/`ErrorReporter` statt `debugPrint`; kein `print` im Release (Web-Konsole = öffentlich); OktoPOS-Client-Fehler an `ErrorReporter.externalSink`; UI-Fehlertexte (de_DE) ≠ Logs.
- **Datenqualität:** Velocity erst ab ~4 Wochen; `training`/`type=cash` aus Umsatz raus; fehlende EK = „unbewertet" ≠ 0; Belege ohne Belegnummer überspringen; `Money.decimal ×100` mit `Math.round`.
- **Multi-Store:** alles `siteId`-skopiert; Zwei-Läden-Benchmark ist ein Feature (2.3/4.1). Artikel-Match A↔B über `barcode`/`externalPosId` mit Qualitätsanzeige.
- **Kosten (Blaze, Free-Tier-Write-Budget):** P0 = +1 Write/Beleg (eingebettete `lines[]`); Tages-KPIs/Co-Occurrence **vorab verdichten** statt Roh-Belege wiederholt lesen.
- **Bekannter Trade-off (gebauter Pull):** Belege mit ausschließlich unmatched Items schieben den `businessDay`-Cursor mit → werden nach späterem Mapping-Fix **nicht** automatisch nachgebucht. **Recovery:** manueller Re-Pull eines Datumsbereichs (Function-`from`/`until`, idempotent). Im UI als „neu zuordnen + nachsyncen" anbieten.

## 6. Empfohlene Reihenfolge

1. **P0 Verkaufsfakten-Layer** (M) + **Rules-Block & Indizes** — Fundament, schaltet P2–P4 frei.
2. **Bewegungs-Range-Query** `getStockMovementsInRange` (S–M) — geteilte Voraussetzung für P1.1/P1.2/P2.2.
3. **1.1 Sell-Through & Reichweite** (M).
4. **1.2 Dead-Stock + Umlagerung** (S, nach Range-Query) — bester Quick-Win.
5. **1.3 Datengetriebener Meldebestand** (M).
6. **2.0 Tagesabschluss → Buchhaltung/DATEV** (**L**, inkl. USt-Konten/n-Entries + cash-Beleg-Erfassung).
7. **2.1 Rohertrag & ABC nach DB** (M).
8. **2.2 Schwund-Report** (M).
9. **2.3 Tages-Gesundheits-Check** (M).
10. **3.1 Umsatzbasierte Besetzung** (L) — der einzigartige POS×Personal-Hebel.
11. **3.2 Kassierer-Anomalie** (M) — **erst nach Mitbestimmungs-/DSGVO-Klärung**.
12. **4.1/4.2/4.3** — Feinschliff, opt-in.

> **Voraussetzung für alles:** Anbindung erst **scharfschalten** (Token/Blaze/Deploy,
> [oktopos-naechste-schritte.md](oktopos-naechste-schritte.md)) und ein paar Wochen Daten sammeln.
