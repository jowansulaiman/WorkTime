# Kassen-Modul — Kassenzustand, Kassenabschluss, Käufe/Verkäufe & Gewinn-Auswertung (OktoPOS)

_Stand: 2026-07-03 · Status: **V1+M1–M6 code-fertig+getestet+review-gehärtet (§10); offen nur noch extern: Blaze-Deploy, OktoPOS-Swagger-Verifikation, Commit** · Datenbasis: OktoPOS-Kassenanbindung (posReceipts-Layer, code-fertig) · Zielumgebung: **Blaze** ([[blaze-zielumgebung]]) · Plattformen: **Web · iOS · Android · Kiosk-Tablet (Arbeitsmodus)**_

_Modell-Eignung je Aufgabenpaket markiert: `Geeignet für: Fable 5` (schwierige Analyse, Architektur, komplexe Businesslogik, riskante Mehrdatei-Änderungen, Datenmodellierung, Entscheidungsfindung) · `Geeignet für: Opus` (klar spezifizierte Implementierung, Tests, UI-Nacharbeiten, Refactors, Doku, Review) · `Geeignet für: Beide`._

Baut **P2.0 (Tagesabschluss/Kassendifferenz)** aus [oktopos-datenwert-plan.md](oktopos-datenwert-plan.md)
zu einem Fachmodul „Kasse" innerhalb der Warenwirtschaft aus und nutzt die P2.1-Rohertrag-Daten;
P2.2 (Schwund) und P2.3 (Benchmark) bleiben eigenständig im Datenwert-Plan. Neu geliefert wird:

1. **Kassenzustand** — wie viel Bargeld rechnerisch gerade in der Kasse liegt (je Standort).
2. **Kassenabschluss** — Tagesabschluss mit Zählung (Kassensturz), Soll/Ist-Differenz und Festschreibung. Zählen dürfen **alle Mitarbeitenden** (Laden-Tablet, blinde Zählung ohne Soll-Anzeige, §7.3) oder Chef/Teamleitung im Tagesabschluss; perspektivisch direkt aus OktoPOS (E3).
3. **Käufe & Verkäufe** — Einkaufsvolumen und Umsatz je Zeitraum. Verkäufe ab v1 echt brutto **und** netto (`taxes[]`); Einkaufspreise werden über einen **org-weiten Schalter** als netto ODER brutto interpretiert (E1, §3.4).
4. **Vergleich pro Woche / Monat / Jahr** — Vorperioden- und Vorjahresvergleich.
5. **Gewinn pro Woche (netto/brutto)** — Rohertrag = Umsatz − Wareneinsatz, klar definiert und ehrlich gelabelt.

---

## 1. Ziel & Scope

**In Scope**

- Neuer Auswertungs-Screen **„Kassenbericht"** (`/kassenbericht`): Umsatz, Käufe, Rohertrag je ISO-Woche / Monat / Jahr, mit Δ zur Vorperiode und zur Vorjahresperiode, Diagramm (fl_chart) + Tabelle + CSV-Export.
- Ausbau des bestehenden **Tagesabschluss-Screens** (`/tagesabschluss`): Zählung erfassen (Kassensturz), Soll-Bargeld vs. gezählt, Differenz, Tag **festschreiben** (persistierter Abschluss), Kassenzustand-Karte.
- **Kiosk-Kachel „Kasse zählen"** auf dem Laden-Tablet (Arbeitsmodus): blinde Zählung durch alle Mitarbeitenden, Attribution über die Kiosk-Session (§7.3, E2).
- **Org-Schalter „Einkaufspreise enthalten MwSt"** (netto/brutto, gilt für alle Artikel) in den `OrgSettings` (§3.4, E1).
- Zwei neue Collections: `cashCounts` (Zählprotokolle) und `cashClosings` (festgeschriebene Tagesabschlüsse), plus serverseitige Tagesaggregate `posDailyStats` für die Monats-/Jahres-Sicht.
- Pure, offline-testbare Engines für alle Berechnungen (Muster `computeDailyClosings`).

**Out of Scope (bewusst)**

- Keine doppelte Buchführung / kein Steuerbescheid-Anspruch — alle Geldwerte sind **Richtwerte**, bis die OktoPOS-Felder gegen die Swagger/Echt-Daten validiert sind (P0 in [oktopos-naechste-schritte.md](oktopos-naechste-schritte.md)). Der Steuerberater bleibt die Autorität.
- Kein Kassenbuch im GoBD-Sinn (Einzelaufzeichnung von Barein-/-ausgängen mit Belegpflicht) — v1 liefert Zählprotokoll + Abschluss-Historie.
- Kein OktoPOS-Z-Bon-Import **in v1**: Die Kassen-API bietet nach heutigem Kenntnisstand **keinen** bekannten Endpunkt für Tagesabschluss/Kassenlade (nur `/transactions`, Artikel- und Kunden-Endpunkte, siehe [oktopos-kassenanbindung.md](oktopos-kassenanbindung.md)). Zeigt die Swagger-Verifikation einen solchen Endpunkt, wird er per E3 in M6 zur Quelle des Kassenzustands.
- Callable-Härtung der Kiosk-Zählung (server-geprüfte Session statt Direkt-Write) → user-gated M6, Muster wie `kioskClockPunch` in [arbeitsmodus-laden-tablet.md](arbeitsmodus-laden-tablet.md).

---

## 2. Ist-Stand (verifiziert am Code, 2026-07-02)

| Baustein | Existiert | Fundstelle |
|---|---|---|
| Belegdaten der Kasse (brutto, USt je Satz, Zahlarten, Zeilen) | ✅ `posReceipts`, cloud-only, read-only | [lib/models/pos_receipt.dart](../lib/models/pos_receipt.dart) (ReceiptTax 8–34, PaymentLine 38–56, Zeilen 60–109), Sync in [functions/index.js](../functions/index.js) 3573–3593 |
| Tagesabschluss-Berechnung (USt-Split, Zahlart-Split, `cashMovementCents`) | ✅ pure | [lib/core/daily_closing.dart](../lib/core/daily_closing.dart) `computeDailyClosings` |
| Tagesabschluss-UI + Buchung ins Finanzjournal (idempotent `pos-{businessDay}-{siteId}-{rate}`) | ✅ admin-only | [lib/screens/daily_closing_screen.dart](../lib/screens/daily_closing_screen.dart), [lib/core/daily_closing_posting.dart](../lib/core/daily_closing_posting.dart), `FinanceProvider.postDailyClosing` |
| Beleg-Range-Query + Index | ✅ | `getPosReceiptsInRange` in [lib/repositories/firestore_inventory_repository.dart](../lib/repositories/firestore_inventory_repository.dart) 176–198, Index `(siteId, transactionDate)` |
| Rohertrag je Artikel (ABC) | ✅ pure | [lib/core/assortment_analysis.dart](../lib/core/assortment_analysis.dart) — `Menge × (realisierter VK − EK)` |
| ISO-Wochen-/Monats-Bucketing | ✅ pure, wiederverwendbar | [lib/core/order_frequency.dart](../lib/core/order_frequency.dart) `startOfIsoWeek`/`startOfMonth`/`isoWeekNumber` |
| Käufe (Bestellungen mit `totalCents`, Status, `orderedAt`/`receivedAt`) | ✅ | [lib/models/purchase_order.dart](../lib/models/purchase_order.dart); Wareneinsatz-Buchung H-A2 bei Wareneingang |
| Kassenzustand / Zählung / Differenz / persistierter Abschluss | ❌ fehlt | — |
| Wochen-/Monats-/Jahres-Vergleich, Gewinn-Sicht | ❌ fehlt | Bestellhäufigkeit hat nur Woche/Monat-Buckets ohne Geldwerte |
| Rules/Read-Scope Belege | ✅ `sameOrg && (admin ∥ teamlead)`, write = false | firestore.rules 1414–1418 |

**Speichermodi:** Der gesamte Kassen-Bereich ist wie `posReceipts` **Cloud-/Hybrid-only**
(Präzedenz: `InventoryProvider.loadDailyClosings` liefert im Local-Modus leer). Im Local-Modus
zeigen die Screens einen freundlichen Leerzustand mit Hinweis. Das ist eine bewusste,
dokumentierte Ausnahme von den drei Speichermodi.

---

## 2a. Verifikation der bereits gebauten OktoPOS-Schnittstellen (Code-Review 02.07.2026)

Die gebaute Anbindung ([functions/index.js](../functions/index.js) 2955–4390) wurde gegen die
Plan-Dokumente und die Rules geprüft — **Ergebnis: im Kern korrekt**:

| Geprüft | Befund |
|---|---|
| Alle 5 Functions: `assertAdmin` + `assertSameOrg` + Region `europe-west3` + Secret-Binding `OKTOPOS_API_KEYS` | ✅ (index.js:2991/2996/2998, 3030, 3857/3861/3863, 3886/3891/3893, 4184/4189/4191) |
| HTTPS-Pflicht der Basis-URL | ✅ (index.js:3137–3141) |
| Cursor inklusiv mit dokumentierter Überlappung + Idempotenz-Filter (Re-Sync erzeugt keine Duplikate) | ✅ (index.js:3172–3176) |
| Geldbeträge `oktoposMoneyToCents` mit `Math.round`, tolerantes Feld-Parsing | ✅ (index.js:3778–3798) |
| Artikel-Push 409 → `change-prices`-Fallback, Barcode-Push | ✅ (index.js:4069–4086) |
| Rules: `posReceipts` read admin ∥ teamlead / write false; `stockMovements` source-Constraint | ✅ (firestore.rules:1375–1418) |
| Composite-Index `posReceipts (siteId, transactionDate)` | ✅ (firestore.indexes.json:245–258) |

**Zwei Befunde → Arbeitspakete:**

- **V1 — Index-Diskrepanz `businessDay`:** [oktopos-datenwert-plan.md](oktopos-datenwert-plan.md) fordert zusätzlich einen `posReceipts (siteId, businessDay)`-Index, der Code quert aber überall über `transactionDate` (Index vorhanden) — auch dieses Modul tut das bewusst (§3.3, wegen null-`businessDay`-Belegen). Auflösung: Datenwert-Plan korrigieren; Index NUR ergänzen, falls künftig direkt per `businessDay` gequert wird. `Geeignet für: Opus` — **✅ erledigt 03.07.2026** (Datenwert-Plan korrigiert)
- **V2 — Sync-Konkurrenz:** Zwischen `getAll`-Duplikat-Check und `batch.commit` in `applyOktoposMovementsBatch` (index.js:3466–3542) liegt ein Zeitfenster — laufen manueller Sync und Nightly (03:30) gleichzeitig für denselben Standort, sind doppelte Movements theoretisch möglich. Auflösung: Konkurrenz-Regel dokumentieren (kein manueller Sync zur Nightly-Zeit) + optional Lock-Flag in `config/oktoposSync` (Entscheidung nötig). `Geeignet für: Fable 5`

## 2b. OktoPOS-Doku-Lage: So verbindet sich Drittsoftware mit der Kasse (Web-Recherche 02.07.2026)

- **Öffentlich dokumentiert** sind nur 4 „Offene Schnittstellen" (Artikelanlage, Kundenanlage, Bestellung importieren, Transaktionen abfragen), Abfrage „über den OktoPOS Manager (Cloud)", ohne technische Details — <https://www.oktopos.com/de/pos-system/system/interfaces>. Direkte DB-Zugriffe sind laut Hersteller-FAQ ausgeschlossen; „individuelle Schnittstellenerweiterung auf Wunsch (optional)".
- **Die technische API-Doku (swagger.yaml/Redoc) ist login-gated**: <https://support.manager.oktopos.net/api-doc> antwortet `login_needed`. → Mit den eigenen OktoPOS-Manager-Zugangsdaten der Läden einloggen und die Swagger herunterladen (deckt die offenen Punkte A2/A8 + Range-Endpunkt-Re-Verifikation ab), sonst Doku beim Support anfordern (<https://support.oktopos.net/>).
- **Auth-Modell** (aus der gated Doku, im Code bereits so gebaut): statischer API-Key im Header `X-API-KEY`, abrufbar im OktoPOS Manager unter „OktoPOS → System", **je Division/Standort** vergebbar; Basis-URL instanzspezifisch `https://<instanz>/v1`. Genau so umgesetzt (Key je `siteId` im Secret `OKTOPOS_API_KEYS`, §2a).
- **Kein API-Endpunkt für Tagesabschluss / Z-Bon / Kassenlade / Bargeldbestand / Kassenbuch dokumentiert.** Kassenbericht, Z-Berichte, Kassenbuch („OktoJournal"), DSFinV-K/GoBD/TSE-Exporte existieren nur als **manuelle Exporte im OktoPOS Manager** (PDF/Excel/CSV) bzw. als optionale, kostenpflichtige **tägliche Datei-Ablage auf dem eigenen Server** — <https://www.oktopos.com/de/management/finance-controlling/accounting-export>, <https://www.oktopos.com/en/pos-system/cash-book>. **Konsequenz für E3:** Der Kassenzustand ist nach aktueller Doku-Lage NICHT per API abholbar — die manuelle Zählung (Tablet/Screen) bleibt die Quelle; der abgeleitete Soll-Bestand aus der Transactions-API (§4.2) ist der rechnerische Gegenwert. Optionen für später: gated Doku auf einen nicht beworbenen Endpunkt prüfen, Hersteller-Anfrage „individuelle Schnittstellenerweiterung", oder täglicher Datei-Export (Format/Kosten klären).
- **Fiskal-Verankerung:** Die Kasse führt TSE (Cryptovision/Swissbit) + DSFinV-K/GoBD-Exporte — der fiskalisch verbindliche Tagesabschluss lebt in der Kasse; unser `CashClosing` ist die **betriebliche** Festschreibung (Zählung/Differenz/Journal-Brücke), kein Fiskal-Ersatz. Das stützt die bestehende Out-of-Scope-Abgrenzung (§1, GoBD).

---

## 3. Datenmodell (neu)

### 3.1 `CashCount` — Zählprotokoll (Kassensturz)

`organizations/{orgId}/cashCounts/{autoId}` — Client-Write, **nur Firestore-Serialisierung**
(camelCase `toFirestoreMap`/`fromFirestore`; kein `toMap`/snake_case, da nie lokal persistiert —
gleiches bewusstes Muster wie `PosReceipt`, im Model-Doc-Kommentar festhalten).

| Feld | Typ | Bedeutung |
|---|---|---|
| `orgId`, `siteId` | String | Mandant/Standort (Pflicht) |
| `cashRegisterId` | int? | Kasse — **int wie in `PosReceipt`** (pos_receipt.dart:139, `parse.toInt`); v1 informativ, Zählung gilt je Standort |
| `businessDay` | String | `YYYY-MM-DD` = **lokales Gerätedatum von `countedAt`** (bewusste Näherung: gezählt wird physisch im Laden; posReceipts-`businessDay` kommt dagegen 1:1 von der Kasse) |
| `countedAt` | Timestamp | Zeitpunkt der Zählung |
| `countedCents` | int | gezählter Bargeldbestand |
| `expectedCents` | int? | Soll-Bestand zum Zählzeitpunkt (Snapshot aus §4.2); **null bei blinder Zählung** durch Mitarbeitende ohne Beleg-Leserecht sowie wenn nicht verankert |
| `differenceCents` | int? | `counted − expected` (Snapshot; null bei blinder Zählung — Differenz berechnet dann der Abschluss §3.2) |
| `denominations` | Map<String,int>? | optionale Stückelung (`"200.00" → Anzahl`) |
| `note` | String? | Freitext (z. B. „Wechselgeld eingelegt") |
| `source` | String | `manual` (Tagesabschluss-Screen) ∥ `kiosk` (Laden-Tablet); `oktopos` ist dem Server vorbehalten (E3) — Rules erzwingen das wie bei `stockMovements` |
| `countedByLabel` | String? | Anzeigename der zählenden Person aus der Kiosk-Session (am Tablet ist das Geräte-Konto der Auth-User, §7.3) |
| `kioskSessionId` | String? | Referenz auf die Kiosk-Session (Nachvollziehbarkeit) |
| `createdByUid` | String | Auth-User — von den Rules an `request.auth.uid` gepinnt (§9); am Kiosk = Geräte-Konto, Person via `countedByLabel` |
| `createdAt` | Timestamp | serverTimestamp |

Unveränderlich (update/delete = false, Audit-Charakter wie `stockMovements`). Korrektur = neue Zählung.

### 3.2 `CashClosing` — festgeschriebener Kassenabschluss

`organizations/{orgId}/cashClosings/{businessDay}-{siteId}` — **deterministische Doc-ID** ⇒ idempotent,
genau ein Abschluss je Tag+Standort. Persistierter Snapshot des berechneten `DailyClosing` **plus** Zählung:

`orgId`, `siteId`, `businessDay`, `salesCount`, `refundCount`, `revenueGrossCents`,
`taxes[]` (ReceiptTax-Form wie am Beleg), `paymentsByMethod` (Map), `cashMovementCents`,
`cashExpectedCents` (Soll-Bargeld des Tages), `cashCountedCents`/`cashCountId` (übernommene Zählung, nullable),
`cashDifferenceCents` (nullable), `bookedToFinance` (bool, s. u.), `closedByUid`, `closedAt`, `note`.

**Festschreibung mit genau einer Ausnahme:** Alle fachlichen Felder sind unveränderlich
(delete = false). Einzig `bookedToFinance` darf per Update `false→true` kippen (admin-only,
Rules erzwingen per Feld-Diff-Allowlist, dass NUR dieses Feld geändert wird, §9) — denn der
bestehende Buchungsfluss `FinanceProvider.postDailyClosing` (admin-Guard, finance_provider.dart:525/529)
ist ein separater Schritt nach dem Abschließen. Das Flag ist zugleich die teamlead-lesbare
Gebucht-Anzeige (§7.2), da `journalEntries` laut Rules admin-only sind.

Der Snapshot macht den Abschluss unabhängig von späteren Re-Syncs der Belege. **Anzeige-Konvention
bei Divergenz:** Der Abschluss-Snapshot ist die festgeschriebene Zahl; der Kassenbericht (§7.1,
aus posDailyStats/Belegen) ist der lebende Richtwert — weichen beide für einen Tag ab, zeigt der
Tagesabschluss ein Hinweis-Icon. Nur Firestore-Serialisierung (wie 3.1).

### 3.3 `posDailyStats` — serverseitige Tagesaggregate (für Monats-/Jahres-Sicht)

**Warum:** Ein Jahresvergleich über rohe `posReceipts` würde bei zwei Läden schnell zehntausende
Dokument-Reads pro Screen-Aufruf kosten. Stattdessen schreibt der bestehende Sync je betroffenem
`(siteId, businessDay)` **ein** Aggregat-Dokument; 365 Docs decken ein Jahr ab.

`organizations/{orgId}/posDailyStats/{businessDay}-{siteId}` (Admin SDK only, wie posReceipts):
`orgId`, `siteId`, `businessDay`, `salesCount`, `refundCount`,
`positiveRefundCount` (A8-Vorzeichen-Verdacht), `revenueGrossCents`,
`revenueNetCents` (Σ `taxes[].netCents`; fehlende Steuerzeilen → `netUncoveredGrossCents` ausweisen),
`taxes[]` (Array in ReceiptTax-Form wie am Beleg — **so implementiert, M5 schreibt exakt dieses
Format**, keine Map), `paymentsByMethod` (Map), `cashMovementCents`,
`cogsCents` (Wareneinsatz der verkauften Zeilen, §8; Netto-EK gemäß §3.4-Schalter), `cogsCoveredGrossCents` (Datenqualität:
Umsatzanteil mit EK-Bewertung), `updatedAt`.

Fortschreibung in `runOktoposSync` ([functions/index.js](../functions/index.js)):

- Betroffene `(siteId, businessDay)`-Paare über **alle Seiten** der Paging-Schleife in einem Set
  sammeln; die Neuaggregation läuft genau **einmal nach** der Schleife, ausschließlich bei
  `!dryRun` (analog zur Cursor-Fortschreibung index.js:3358–3359 — `applyOktoposReceiptsBatch`
  selbst läuft je Seite und ein Tag kann Seiten überspannen).
- **Tageszuordnung wie im Client:** `businessDay ?? Kalendertag aus transactionDate` — derselbe
  Fallback wie `computeDailyClosings` (daily_closing.dart:78–82), denn der Sync persistiert
  `businessDay: businessDay || null` (index.js:3275). Die Ganztags-Neuaggregation liest den Tag
  deshalb über eine `transactionDate`-**Range** (bestehender `(siteId, transactionDate)`-Index),
  nicht über businessDay-Gleichheit; sonst fielen null-businessDay-Belege still heraus.
- Ergebnis per `set` schreiben (kein `increment`). **Idempotenz gilt für alle belege-abgeleiteten
  Felder** (Umsatz/Steuern/Zahlarten/Counts). `cogsCents` wird dagegen bei jeder Neuaggregation
  mit dem **dann aktuellen** `Product.purchasePriceCents` bewertet (normalisiert nach dem
  §3.4-Schalter, den der Server per Admin SDK aus `config/orgSettings` liest) — der Nightly-Sync re-pullt den
  Cursor-Tag bei jedem Lauf (index.js:3169–3173), ein „Einfrieren" gibt es mangels EK-Historie
  nicht (A3): COGS ist ein Richtwert.

Dazu Backfill-Callable `rebuildPosDailyStats({from, until, siteId?})` (admin-only, `assertSameOrg`,
Batch-Chunks wie Sync).

### 3.4 `OrgSettings` — Schalter „Einkaufspreise enthalten MwSt" (E1)

Neues Feld `purchasePricesIncludeVat` (bool, Default `false` = netto) im bestehenden
Config-Singleton `config/orgSettings` (wird von `FeatureFlagProvider` geladen/geschrieben,
lokaler Fallback `local_v2/org_settings`, admin-write über den generischen
`config/{configId}`-Rules-Block — alles vorhandene Infrastruktur). **Gilt org-weit für alle
Artikel.** Steht der Schalter auf brutto, rechnen Client-Engines UND Server-COGS den Netto-EK als
`purchasePriceCents / (1 + Product.taxRatePercent/100)`; Artikel ohne `taxRatePercent` gelten
dann als **unbewertet** (drücken die ausgewiesene EK-Abdeckung — kein stilles Raten).
UI: Schalter im bestehenden Org-Einstellungs-Bereich, Beschriftung „Einkaufspreise enthalten
MwSt (brutto)" mit Erklärtext, dass die Umstellung für alle Artikel und Auswertungen gilt
(auch Sortimentsanalyse-Rohertrag, sobald diese den Schalter mitbenutzt — M6-Prüfpunkt).

---

## 4. Pure Logik / Engines (offline-testbar, kein IO/`now()`)

### 4.1 `lib/core/kasse_report.dart` — Zeitraum-Vergleich & Gewinn

- `enum ReportGranularity { week, month, year }` — **bewusst eigenes Enum** statt Erweiterung von
  `FrequencyGranularity`: dessen erschöpfende `label`-Extension (order_frequency.dart:7–10) bräche
  beim Compile, und die `==`-Vergleiche im `order_analytics_screen` würden einen `year`-Wert
  **still wie Monat** bucketen — beides spricht für Trennung. Helfer
  `startOfIsoWeek`/`startOfMonth`/`isoWeekNumber` aus [order_frequency.dart](../lib/core/order_frequency.dart) wiederverwenden.
- `class KassenPeriode { start, label, umsatzBruttoCents, umsatzNettoCents, nettoUnsicherCents, kaeufeCents, wareneinsatzCents, wareneinsatzAbdeckungPct, rohertragNettoCents, rohertragBruttoCents, belege, erstattungen, deltaVorperiodePct, deltaVorjahrPct, hatDaten }`
  — `hatDaten=false` markiert Buckets ohne Datendeckung (UI zeigt „keine Daten", nie eine stille 0).
  Label deutsch via `DateFormat(…, 'de_DE')` erst in der UI (Engine liefert nur Daten).
- `computeKassenbericht({required List<PosDailyStat> stats, required List<PurchaseOrder> orders, required ReportGranularity granularity, required DateTime now, int bucketCount, String? siteId})`
  → Liste `KassenPeriode`, älteste zuerst. Defaults: 12 Wochen / 12 Monate / 3 Jahre.
  Vorjahres-Δ: gleiche ISO-KW bzw. gleicher Monat des Vorjahres (nur wenn Daten vorhanden, sonst null).
- Übergangsvariante bis M5 deployt ist: Adapter `dailyStatsFromReceipts(List<PosReceipt>, List<Product>, {required bool purchasePricesIncludeVat})`
  berechnet dieselben Tagesaggregate clientseitig aus einem Belege-Fenster von **≤ 92 Tagen**.
  Damit ist vor M5 nur die **Wochen-Sicht voll** nutzbar (12 KW = 84 Tage); die **Monats-Sicht ist
  auf 3 Buckets begrenzt** und zeigt — wie das Jahres-Segment — den Hinweis „Langzeit-Daten nach
  Server-Update" (§7.1, §10 M4, §12 A7). Die Engine hat so genau EINE Eingangsform.
- Datenqualitäts-Signale der Engine: EK-Abdeckung, Netto-Abdeckung, **„positive Erstattungs-Belege
  erkannt"** (Vorzeichen-Verdacht, A8).

### 4.2 `lib/core/cash_state.dart` — rechnerischer Kassenzustand

`computeCashState({required List<PosReceipt> receipts, required List<CashCount> counts, required String siteId})`
— training-Belege sind in **beiden** Summanden ausgeschlossen (wie `computeDailyClosings`, das
training VOR dem cash-Zweig überspringt, daily_closing.dart:78–88):

```
Anker   = letzte Zählung (countedCents, countedAt) im Lade-Fenster; keine Zählung ⇒ verankert=false
Soll    = Anker
        + Σ Bar-Zahlungen aus isRevenue-Belegen seit Anker   (payments[] mit Bar-Methode, Refunds negativ, A8)
        + Σ cash-Belege seit Anker, ohne training             (type='cash', Ein-/Auszahlungen, wie cashMovementCents)
```

**Begrenzter Read-Pfad (kein „ab Datenbeginn"):** `loadCashState({siteId, windowDays = 62})` lädt
Zählungen + Belege nur im Fenster. Liegt darin keine Zählung, gibt es **kein gerechnetes Soll** —
`verankert=false`, die UI zeigt eine „Bitte Kasse zählen"-Aufforderung statt eines ab Datenbeginn
gerechneten (und read-teuren) Fantasiewerts. Nach M5 optional: Vortage aus `posDailyStats`
(paymentsByMethod + cashMovementCents liegen dort vor) + nur der laufende Tag aus Belegen.

Bar-Methode = tolerantes Token-Set `{bar, cash, bargeld}` (zentral als Konstante; echte
OktoPOS-Tokens erst nach Echt-Validierung bekannt → A2). Ergebnis `CashState { sollCents, verankert, letzteZaehlung, tagesBareinnahmenCents, tagesCashBewegungCents }`.

### 4.3 Erweiterung Tagesabschluss

`DailyClosing` bleibt unverändert; neu daneben: `buildCashClosingSnapshot(DailyClosing, CashState, CashCount?)`
→ Feldwerte für §3.2 inkl. `cashDifferenceCents = counted − expected`.

---

## 5. Server (Cloud Functions, Blaze)

- `runOktoposSync`: posDailyStats-Fortschreibung (§3.3: Set über alle Seiten, einmal nach der
  Schleife, nur `!dryRun`). Kein neuer HTTP-Endpunkt, kein neues Secret.
- Neue Callable `rebuildPosDailyStats` (v2 `onCall`, Region `europe-west3` = `REGION`, admin-only, `assertSameOrg`).
- Payload snake_case (`toMap`-Regel gilt für Callable-Payloads; hier nur primitive from/until-Strings).
- Tests: `node --test` mit Fixture-Belegen **und konstanten Produktdaten** → deterministische Stats;
  Re-Run ⇒ identisches Ergebnis für belege-abgeleitete Felder (COGS-Neubewertung bei EK-Änderung ist
  per §3.3 erwartetes Verhalten und wird als eigener Testfall dokumentiert, nicht als Idempotenz-Bruch).

**Kein** Functions-Zwang für M1–M4: Zählung/Abschluss/Wochenbericht laufen komplett über
direkten Firestore-Zugriff + Client-Engines. Monats-Langzeit- und Jahres-Sicht brauchen M5.

---

## 6. Provider-Anbindung

Alles in **`InventoryProvider`** (dort liegen bereits `loadDailyClosings`, das Inventory-Repository
und der posReceipts-Zugriff; kein neuer Provider, Kette in `main.dart` unverändert):

- `loadKassenbericht({siteId, granularity, bucketCount})` — lädt Stats (M5) bzw. Belege-Fenster ≤ 92 Tage (M4-Übergang) + nutzt bereits geladene `purchaseOrders`; hält Read-Model analog `SalesInsightsProvider`-Muster (Teilerfolg statt alles-oder-nichts).
- `loadCashState({siteId, windowDays = 62})`, `loadCashCounts({siteId, windowDays})` — immer gefenstert (§4.2).
- `saveCashCount(CashCount)` — **Mutator**, offen für **alle aktiven Nutzer** (kein `canManageInventory`-Gate — Zählen ist Mitarbeiter-Aufgabe, E2): nur cloud/hybrid; im catch bei hybrid NICHT lokal fallbacken (Ausnahme §2: Kasse ist cloud-only ⇒ rethrow mit deutscher Meldung); Audit auf Erfolgs-Pfad: `_audit?.call(action: 'kasse.zaehlung', entityType: 'cashCount', …, summary: 'Kassenzählung <Standort> <Betrag> erfasst')`.
- `closeBusinessDay(...)` — schreibt `CashClosing` (create-only, deterministische ID; existiert schon ⇒ deutscher `StateError` „Tag ist bereits abgeschlossen"); Audit `kasse.abschluss`. Danach bietet die UI die bestehende Journal-Buchung an (`FinanceProvider.postDailyClosing`); nach Erfolg `markClosingBooked(...)` = feldbeschränktes Update `bookedToFinance: true` (einzige erlaubte Mutation, §3.2/§9; Audit `kasse.abschluss_gebucht`).
- Repository ([firestore_inventory_repository.dart](../lib/repositories/firestore_inventory_repository.dart)): `getCashCountsInRange`, `addCashCount`, `getCashClosingsInRange`, `createCashClosing`, `markCashClosingBooked`, `getPosDailyStatsInRange`.

---

## 7. UI

### 7.0 Plattform-Matrix (Web · iOS · Android · Kiosk-Tablet) — verifiziert am Code

| Baustein | Web | iOS/Android | Kiosk-Tablet | Beleg |
|---|---|---|---|---|
| Kassenbericht + Tagesabschluss (Firestore-Reads) | ✅ | ✅ | — (bewusst nicht: Umsatz-/EK-Daten gehören nicht aufs geteilte Board) | posReceipts cloud-only, kein kIsWeb-Sonderweg nötig |
| CSV-/PDF-Export | ✅ Blob-Download | ✅ share_plus mit Dateipfad | — | `download_service_web.dart` / `download_service_io.dart` (conditional export) |
| Diagramme | ✅ | ✅ | — | fl_chart bereits aktiv in order_analytics/statistics/personal |
| Zählung erfassen | ✅ (Screen §7.2) | ✅ (Screen §7.2) | ✅ Kachel §7.3 | Kachel-Muster `_ExpiryTile` (kiosk_screen.dart:799); Geräte-Konto `role:kiosk` ist `isActiveUser` ⇒ cashCounts-create-Rule greift |
| Betragseingabe de_DE (Komma) | ✅ | ✅ | ✅ | `Money.parseCents` (lib/core/money.dart) existiert — im Zähl-Sheet/Kachel verwenden, kein eigener Parser |
| Responsive | Rail ab 600 dp, `ConstrainedBox(maxWidth)` wie statistics_screen | BottomSheets | Wrap-Grid 1/2/3-spaltig (kiosk_screen.dart:445–468) | bestehende Muster übernehmen |

**Vorbedingung Kiosk (Kopplung §11.12):** Die Zähl-Kachel erbt die A0-Auflage aus
[arbeitsmodus-kachel-ausbau.md](arbeitsmodus-kachel-ausbau.md) §0 — das Geräte-Konto braucht
explizite false-Permission-Overrides (`canViewSchedule` etc.), sonst öffnet `role:kiosk` über die
`permissionOrDefault`-Fallbacks mehr Reads als nötig. Die Kachel selbst braucht davon nichts
(create-only), aber sie darf nicht VOR dieser Härtung als Anlass dienen, das Konto breiter zu
berechtigen.

### 7.1 Neuer Screen „Kassenbericht" (`/kassenbericht`)

- `AppRoutes.kassenbericht` + `_sectionRoute` in [app_router.dart](../lib/routing/app_router.dart) + **admin-only** in [route_permissions.dart](../lib/routing/route_permissions.dart) (zeigt EK/Marge — gleiche Begründung wie `bestandInsights`/`sortiment`) + in die Dense-Section-Liste (Dynamic-Type 1,5×).
- Aufbau: Standort-Filter · Segmente **Woche | Monat | Jahr** · KPI-Karten (Umsatz brutto, Umsatz netto, Käufe, **Rohertrag netto** groß + Rohertrag brutto klein, Δ Vorperiode, Δ Vorjahr) · fl_chart-Balken (12 KW / 12 Monate / 3 Jahre) · Bucket-Tabelle · Datenqualitäts-Hinweis (EK-Abdeckung %, Netto-Abdeckung %, Vorzeichen-Verdacht A8, „Richtwert"-Banner) · CSV-Export (UTF-8-BOM + `;`, ExportService-Muster).
- Vor dem M5-Deploy zeigen **Monats-Segment (nur 3 Buckets) und Jahres-Segment** den Hinweis „Langzeit-Daten werden nach Server-Update verfügbar"; Buckets ohne Datendeckung erscheinen als „keine Daten" (`hatDaten`, §4.1), nie als stille 0.
- Einstiege: Insights-Menü der [inventory_screen.dart](../lib/screens/inventory_screen.dart) + QuickActionCard „Kassenbericht" im ShopHubTab ([home_screen.dart](../lib/screens/home_screen.dart), isAdmin-gated).

### 7.2 Tagesabschluss-Ausbau (`/tagesabschluss`)

- **Kassenzustand-Karte** oben: rechnerischer Ist-Bestand je Standort (§4.2), „zuletzt gezählt am …", nicht verankert ⇒ „Bitte Kasse zählen"-Aufforderung.
- Je Tag: bestehende USt-/Zahlart-Aufschlüsselung + neu **„Zählung erfassen"** (BottomSheet, `showDragHandle`, `isScrollControlled`, `useSafeArea`: Betrag, optionale Stückelung, Notiz) → zeigt sofort Soll/Ist/Differenz (Farben via `Theme.of(context).appColors` success/warning/error, nie hardcoded).
- **„Tag abschließen"** (nur admin): schreibt `CashClosing`, bietet danach die bestehende Journal-Buchung an (Erfolg ⇒ `bookedToFinance=true`); abgeschlossene Tage bekommen Badge „festgeschrieben" und sind read-only; divergiert der lebende Richtwert vom Snapshot ⇒ Hinweis-Icon (§3.2).
- Screen-Gate von admin auf **admin ∥ teamlead** erweitern (Teamleitung darf einsehen + zählen; Abschließen/Buchen bleibt per Button-Gate admin) — deckungsgleich mit den posReceipts-Rules. Route-Guard in `route_permissions.dart` anpassen. **Achtung Datenpfad:** Der Screen leitet den Gebucht-Status heute aus `finance.journalEntries` ab (`_bookedRatesFor`, daily_closing_screen.dart:284/314), deren read laut Rules admin-only ist — für teamlead wird der Gebucht-Badge stattdessen aus `cashClosings.bookedToFinance` gelesen (teamlead-lesbar, §9) und alle journal-abhängigen Teile (Erlöskonten-Auswahl, Buchen) sind explizit isAdmin-gated, damit der Screen ohne Journal-Stream funktioniert.

### 7.3 Kiosk-Kachel „Kasse zählen" (Laden-Tablet, E2)

Neue Kachel im Arbeitsmodus (Muster der MHD-Kachel): großes Betragsfeld (+ optionale Stückelung,
Notiz), **blinde Zählung** — die Kachel zeigt bewusst KEIN Soll und keine Differenz. Das ist
zugleich technisch erzwungen (Mitarbeitende/Geräte-Konto haben kein posReceipts-Leserecht) und
fachlich gewollt (verhindert „Hinzählen" auf einen bekannten Sollwert). Schreibt `CashCount` mit
`source='kiosk'`, `createdByUid` = Geräte-Konto, `countedByLabel`/`kioskSessionId` aus der
aktiven Kiosk-Session ([arbeitsmodus-laden-tablet.md](arbeitsmodus-laden-tablet.md)); ohne aktive
Session verlangt die Kachel die Namenswahl+PIN. Erfolgsmeldung „Zählung gespeichert — danke!".
Soll/Differenz sieht die Leitung anschließend im Tagesabschluss (§7.2). Callable-Härtung
(server-geprüfte Session statt Direkt-Write) = user-gated M6.

### 7.4 UI/UX-Leitplanken — „nicht minimal, aber nicht überladen"

- **Kassenbericht:** genau EINE KPI-Reihe (max. 6 Karten: Umsatz brutto · Umsatz netto · Käufe · Rohertrag netto · Δ Vorperiode · Δ Vorjahr), EIN Diagramm pro Segment, darunter die Bucket-Tabelle. Alles Weitere (Zahlart-Split, Steuer-Split, Tages-Drilldown) per **progressive disclosure**: Tap auf Bucket → BottomSheet mit Details. Rohertrag brutto nur als Nebenwert mit Tooltip — keine zweite große Zahl.
- **Ein** „Richtwert"-Banner oben (solange A2/A8 unverifiziert), NICHT je Karte wiederholen.
- **Tagesabschluss:** Karte pro Tag = Kopf (Datum, Umsatz, Status-Badge offen/festgeschrieben/gebucht) → aufklappbar USt/Zahlart/Bargeld → Aktionen. Zähl-Sheet = EIN Betragsfeld; Stückelung + Notiz hinter „Mehr angeben" (optional, nie Pflicht).
- **Kiosk-Kachel:** ein Schritt, ein Feld, große Touch-Ziele (Tablet), Erfolgs-Feedback, KEINE Zahlen des Tages sichtbar (blind, §7.3). Keine hängende Kachel: ohne Netz klare Meldung „Zählung braucht Internet" (Kasse ist cloud-only, §2).
- **Keine Kassierer-PII** im Kassenbericht (nur `/kassierer-pruefung` zeigt das, mit DSGVO-Hinweis); keine EK-/Margen-Werte außerhalb admin-gated Screens.
- Leerzustände immer mit Handlungsaufforderung („Noch keine Kassendaten — Sync unter Kasse-Einstellungen starten" / „Bitte Kasse zählen"), nie leere Flächen. Status-Farben via `appColors`, Beträge via `Money.format()` (de_DE).

Alle Texte deutsch, jedes `DateFormat` mit `'de_DE'`.

---

## 8. Berechnungs-Definitionen (verbindlich, im Code dokumentieren)

| Kennzahl | Definition | Quelle |
|---|---|---|
| **Umsatz brutto** | Σ `grossCents` aller `isRevenue`-Belege (ohne `training`); Erstattungen gehen vorzeichenbehaftet ein (**Annahme A8:** die Kasse liefert Refund-Beträge negativ) | posReceipts / posDailyStats |
| **Umsatz netto** | Σ `taxes[].netCents`; Belege ohne Steuerzeilen laufen in `nettoUnsicherCents` und werden ausgewiesen (kein stilles Raten) | posReceipts |
| **Käufe** | Σ `PurchaseOrder.totalCents`, Periodenzuordnung nach `orderedAt ?? createdAt` (Datumsregel wie Bestell-Auswertung). Status-Filter ≠ `draft`/`cancelled` — der draft-Ausschluss ist eine **bewusste Abweichung** von der Bestell-Auswertung (die zählt Entwürfe mit, order_frequency.dart:94–97); Entwürfe sind keine Käufe. KPI-Label folgt dem §3.4-Schalter („Käufe (netto)" bzw. „Käufe (brutto, wie erfasst)" — Bestellpositionen tragen keine eigene USt, echte Netto-Normalisierung der Käufe = M6) | purchaseOrders |
| **Wareneinsatz (COGS)** | Σ über verkaufte Belegzeilen: `quantity × Netto-EK` (Netto-EK aus `purchasePriceCents`, normalisiert per §3.4-Schalter; jeweils aktueller EK, kein Verlauf — A3); Zeilen ohne Produkt-Match/EK — und bei brutto-Einstellung ohne `taxRatePercent` — fehlen und drücken die ausgewiesene **EK-Abdeckung** | posReceipts × products (M5: im Stats-Doc, bei Re-Aggregation neu bewertet) |
| **Gewinn = Rohertrag netto** | `Umsatz netto − Wareneinsatz` — die ehrliche Zahl (USt ist durchlaufender Posten) | Engine §4.1 |
| **Rohertrag brutto** | `Umsatz brutto − Wareneinsatz` — nur Vergleichswert, im UI klein + mit Tooltip „enthält USt" | Engine §4.1 |
| **Soll-Bargeld** | letzte Zählung + Bar-Zahlungen + cash-Bewegungen seit Zählung, ohne training (§4.2) | posReceipts + cashCounts |
| **Kassendifferenz** | `gezählt − Soll` zum Zählzeitpunkt | CashCount/CashClosing |

**Bewusst NICHT „Gewinn" genannt wird das Betriebsergebnis** (Rohertrag − Personal/Gemeinkosten):
Personal- und Gemeinkosten liegen bereits als JournalEntries im Finanzmodul (H-A1/H-A2) — eine
optionale Karte „Betriebsergebnis (Richtwert)" ist M6. Im UI heißt die Kennzahl **„Rohertrag"**
mit Untertitel „Gewinn vor Personal- & Fixkosten", damit niemand Rohertrag für Reingewinn hält.

---

## 8a. Beitrag zu Lohnabrechnung & Monatsabschluss (Datenvollständigkeits-Check 02.07.2026)

Der Lohnlauf (WorkEntry × PayrollProfile, `PayrollCalculator`) und der Zeitwirtschafts-Monatsabschluss
(`monatsabschluss_service.dart`) funktionieren heute ohne Kassendaten — geprüft wurde, was das
Kassen-Modul für einen **vollständigen Finanz-Monatszyklus** beitragen muss:

- **Lohnquote-Karte** (Personalkosten ÷ Umsatz je Monat): beide Quellen existieren nach M5
  (`PayrollRecord.employerTotalCents` via H-A1-Journal + `posDailyStats.revenueGrossCents`),
  nirgends aggregiert → als Karte in die M6-Betriebsergebnis-Gruppe (admin-only). Klärungsfrage:
  AG-Gesamtkosten oder nur Brutto-Lohn als Zähler. `Geeignet für: Beide (Definition: Fable 5, Karte: Opus)`
- **Kassendifferenzen als Kosten buchen:** `CashClosing.cashDifferenceCents` wird bisher nur
  angezeigt. Neu (M6): idempotente Journal-Buchung `pos-diff-{businessDay}-{siteId}` auf eine
  Kostenart „Kassendifferenz" — erst dann taucht Schwund an der Lade im Finanz-Ergebnis auf.
  `Geeignet für: Opus (Muster postDailyClosing existiert)`
- **Monats-Vollständigkeits-Check:** Vor dem DATEV-/Finanz-Export eines Monats prüft eine
  Checkliste im FinanceScreen „alle Geschäftstage mit Umsatz haben ein `CashClosing`?" (weicher
  Hinweis, kein harter Block — der Zeitwirtschafts-Abschluss bleibt unabhängig, keine atomare
  Kopplung der drei Abschlüsse; bewusste Entscheidung gegen einen Monster-Abschluss).
  `Geeignet für: Opus`
- **Trinkgeld (A9):** `PosReceipt` hat kein Tips-Feld; ob OktoPOS Trinkgeld liefert, klärt erst
  die gated Swagger (§2b). Falls ja → Feld im Sync + Payroll-Behandlung (steuerfrei §3 Nr. 51
  EStG bei freiwilligem Trinkgeld) als eigener Folgeplan. Bis dahin: nicht erfasst, ehrlich
  dokumentiert.
- **Privatentnahmen/Bar-Entnahmen:** stecken heute undifferenziert in `type='cash'`. v1 reicht
  die Notiz an Zählung/Abschluss; eine eigene Kategorisierung (Entnahme-Art) ist M6-Option.
- **Abgrenzung:** Schichtzuschläge (Nacht/Sonn-/Feiertag §3b), Provisionen und
  Abwesenheits-Vergütungssätze sind **Lohn-Themen ohne Kassen-Bezug** → gehören in
  [personal-bereich-ausbau.md](personal-bereich-ausbau.md) / [ida-hr-zeit-uebernahme.md](ida-hr-zeit-uebernahme.md),
  nicht hierher (dort als Querverweis vermerken).

---

## 9. Sicherheit / Rules / Indexe

### 9.1 Rollen- & Sichtbarkeitsmatrix

Legende: L = lesen, S = schreiben, – = kein Zugriff. „self" = eigener Datensatz.

| Datenart / Screen | admin | teamlead | employee | Kiosk-Gerätekonto |
|---|---|---|---|---|
| `posReceipts` (Belege, Umsatz, Kassierer-ID) | L | L | – | – |
| `posDailyStats` (Tagesaggregate) | L | L | – | – |
| `cashCounts` (Zählprotokolle) | L+S | L+S | S (nur blind: ohne `expectedCents`)¹ | S (blind, `source='kiosk'`)¹ |
| `cashClosings` (festgeschriebene Abschlüsse) | L+S (create; update nur `bookedToFinance`) | L | – | – |
| `config/orgSettings` (§3.4-Schalter) | L+S | L | L² | L² |
| `config/oktoposSync` (Kassen-Konfig, Sync-Cursor) | L+S | – | – | – |
| `journalEntries` (Finanzjournal, Buchungen) | L+S | – | – | – |
| Kassenbericht `/kassenbericht` (EK/Marge/Gewinn!) | ✓ | – | – | – |
| Tagesabschluss `/tagesabschluss` | ✓ (inkl. Abschließen/Buchen) | ✓ (einsehen + zählen) | – | – |
| Kiosk-Kachel „Kasse zählen" | – | – | ✓ (via Tablet-Session) | ✓ |

¹ create-only, unveränderlich; Rules erzwingen `createdByUid == auth.uid` und für Nicht-Leitung `expectedCents == null`.
² `config/{configId}` ist heute sameOrg-read/admin-write (bestehender Rules-Block) — der Schalter ist unkritisch (bool, kein Geldwert).

Grundsatz: **Umsatz-, EK-, Margen- und Differenz-Zahlen sieht nur die Leitung** (admin; teamlead
ohne EK/Marge, d. h. ohne `/kassenbericht`). Mitarbeitende liefern Zählungen, sehen aber keine
Soll-Werte. Das deckt sich mit den bestehenden posReceipts-Rules und `route_permissions.dart`.

### 9.2 Rules & Indexe

- `firestore.rules` (Muster posReceipts/stockMovements, `sameOrg` gepinnt):
  - `cashCounts`: read `sameOrg && (isAdmin ∥ teamlead)` — Zählungen enthalten via `expectedCents` Umsatz-Wissen. create **`sameOrg && isActiveUser`** (alle Mitarbeitenden + Kiosk-Geräte-Konto, E2) + Feld-Allowlist + `orgId`-Pin + `countedCents is number` + **`createdByUid == request.auth.uid`** (Akteur-Pin gegen Audit-Spoofing, wie stockMovements firestore.rules:1402–1404) + `source in ['manual','kiosk']` (nie `oktopos` vom Client) + Zeitstempel-Plausibilität; **Nicht-admin/teamlead dürfen nur blind zählen**: für sie erzwingen die Rules `expectedCents == null && differenceCents == null`; update/delete `false`.
  - `cashClosings`: read `sameOrg && (isAdmin ∥ teamlead)`; create **nur isAdmin** + Allowlist + Pin; **update nur isAdmin und nur, wenn der Feld-Diff exakt `bookedToFinance: false→true` ist** (`affectedKeys().hasOnly(['bookedToFinance'])`, §3.2); delete `false`.
  - `posDailyStats`: read wie posReceipts; write `false` (nur Admin SDK).
- `firestore.indexes.json` (+ Deploy): `cashCounts (siteId ASC, countedAt DESC)`, `cashClosings (siteId ASC, businessDay DESC)`, `posDailyStats (siteId ASC, businessDay DESC)`.
- Kein neues Secret, kein neuer Outbound-HTTP. Client sieht weiterhin nie den OktoPOS-Key.
- Kassierer-/PII-Bezug: Der Kassenbericht aggregiert nur — keine `cashierId`-Anzeige (dafür gibt es `/kassierer-pruefung` mit DSGVO-Hinweis).

---

## 10. Meilensteine

> **Stand 03.07.2026: V1 ✅ · M1 ✅ · M2 ✅ · M3 ✅ — code-fertig + getestet** (Gesamt-Suite
> 1338 grün, `flutter analyze` clean). M1/M2-Review eingearbeitet: Rules-Typ-Checks gegen
> Poison-Docs + `countedAt`-Zeitstempel-Plausibilität (Anker-Kapern), Doc-ID-Pin +
> `bookedToFinance == false` beim cashClosings-create, tolerante String-Parser, A8-Signal
> `positiveErstattungen`, `coverageFrom`-Schutz gegen Randstummel-Δ, null-Δ bei negativer
> Vergleichsbasis, Audit-Summaries mit Standort.
> **M3** (03.07.): Tagesabschluss-Screen neu (Kassenzustand-Karte, Zähl-Sheet mit
> Soll/Ist/Differenz, „Tag abschließen" + Buchen, festgeschrieben-/gebucht-Badges),
> geteiltes [cash_count_sheet.dart](../lib/widgets/cash_count_sheet.dart), Kiosk-Zählkachel
> (blind, §7.3), teamlead-Öffnung + Insights-Menü-Einstieg, Gebucht-Badge aus
> `cashClosings.bookedToFinance` (nicht dem admin-only Journal). M3-Review eingearbeitet:
> Tageszählung in den Abschluss-Snapshot eingebettet (tagesrichtiges Soll/Differenz statt
> globalem Kassenzustand), separater Fehlerpfad für die Gebucht-Markierung, negative
> Zählbeträge gesperrt, neutraler Breadcrumb „Kasse".
> **M4** (03.07.): Kassenbericht-Screen `/kassenbericht` (admin-only) —
> [kassenbericht_screen.dart](../lib/screens/kassenbericht_screen.dart): Segmente Woche/Monat/Jahr,
> 6 KPI-Karten (Umsatz brutto/netto, Käufe, Rohertrag netto groß + brutto klein „enthält USt",
> Δ Vorperiode/Vorjahr) mit „Aktuelle Periode"-Label, fl_chart-Balken (minY für negative
> A8-Umsätze), Perioden-Tabelle, Richtwert-Banner + Datenqualitäts-Hinweis (Netto-/EK-Abdeckung,
> positive-Erstattungen-Warnung), Langzeit-Hinweis für Monat/Jahr, CSV-Export
> (`ExportService.buildKassenberichtCsv`, BOM+`;`+de_DE); Route/Permission/dense-Liste,
> Einstiege Insights-Menü + ShopHub-Kachel (beide admin). M4-Review eingearbeitet: Sequence-Token
> gegen Load-Races, „enthält USt"-Hinweis, KPI-Perioden-Label, negative Balken sichtbar, Δ 0 %
> neutral. Widget-/CSV-Tests + route_permission-Test.
> **M5** (03.07.): Server-Tagesaggregate. Pures Modul
> [functions/oktopos_stats.js](../functions/oktopos_stats.js) (`computeDailyStats`/`ekNettoByProduct`,
> Spiegel von `dailyStatsFromReceipts`, §11.11) + 13 `node --test`; `posDailyStats`-Fortschreibung in
> `runOktoposSync` (genau 1× nach der Paging-Schleife, nur `!dryRun`, best-effort, Ganztags-Re-Aggregation
> über transactionDate-Range mit ±1-Tag-Puffer); `loadProductLookups` um EK/USt erweitert;
> `rebuildPosDailyStats`-Callable (admin, `assertSameOrg`, kein Secret, 512 MiB, 400-Tage-Cap);
> Client-Umschaltung: `loadKassenbericht` bevorzugt Server-Stats (getPosDailyStatsInRange über
> 500/800/1600 Tage je Granularität, coverageFrom=Fensterstart), Fallback = 92-Tage-Belegfenster;
> Screen: Monat 12 Buckets, Langzeit-Hinweis neutral formuliert + nur wenn älteste Periode leer.
> M5-Review: Langzeit-Hinweis kein falsches „Server-Update"-Versprechen mehr, rebuild-Memory 512 MiB.
> **M6-A** (03.07., Kassendifferenz-Autobuchung, §8a): pure
> [cash_difference_posting.dart](../lib/core/cash_difference_posting.dart) (`buildCashDifferenceEntry`,
> `amountCents = -cashDifferenceCents` → Fehlbetrag=Kosten, Überschuss=Gutschrift, idempotent
> `pos-diff-{day}-{site}`) + `FinanceProvider.postCashDifference` (admin, Namens-Heuristik
> `kassendifferenz`/`kassenmanko` — bewusst spezifisch gegen Fehltreffer wie „Inventurdifferenz")
> + Einbindung in den Buchen-Flow des Tagesabschlusses (eigen gekapselt, still übersprungen ohne
> Konto/Differenz). Review-Fixes: eigenes try/catch für die Differenz-Buchung, Needles verengt.
> Tests: pure + Provider + Widget.
> **M6-B** (03.07., USt am Einkauf — löst „Käufe netto/brutto" ein): `PurchaseOrderItem.taxRatePercent`
> (Zwei-Serialisierung, aus `Product.taxRatePercent` bei Anlage übernommen) + schalter-bewusste
> `lineNetCents/lineGrossCents(priceIncludesVat)` / `PurchaseOrder.totalNetCents/totalGrossCents`;
> Engine: `KassenPeriode.kaeufeNettoCents`+`kaeufeBruttoCents`, `computeKassenbericht` mit
> `purchasePricesIncludeVat` (an beide Pfade durchgereicht); KPI „Käufe netto" + brutto-Untertitel,
> CSV-Spalten netto/brutto. **Selbst gefundener Fix:** der erfasste EK-Preis ist netto ODER brutto je
> §3.4-Schalter (sonst USt-Doppelzählung) — Aufteilung schalter-bewusst, beide Fälle getestet.
> **M6-C/D/E** (03.07.): **C** — §3.4-Schalter in `computeAssortmentAnalysis` (EK-Netto via `_ekNetto`,
> identisch zum Kassenbericht), Provider/Screen reichen ihn durch. **D** —
> [lohnquote.dart](../lib/core/lohnquote.dart) (`computeLohnkennzahlen`: Personalkosten aus finalisierten
> `PayrollRecord.employerTotalCents` je Perioden-Bucket ÷ Umsatz + Betriebsergebnis = Rohertrag netto −
> Personal, org-weit, nur Monat/Jahr) + `_LohnquoteCard` im Kassenbericht (nur ohne Standort-Filter).
> **E** — `kioskSaveCashCount`-Callable (session-validiert via `requireKioskSession`, blind, Betrag/
> businessDay-Validierung, server-authoritativer `countedByLabel` aus users/{employeeId}) +
> `FirestoreService.kioskSaveCashCount` + Kiosk-Tile nutzt es im Echtbetrieb (Direkt-Write nur Dev-Fallback).
> M6-C/D/E-Review: alle „low" — Lohnquote-Karte watch statt read (Rebuild bei Payroll-Stream),
> Betriebsergebnis-Farbe null-sicher, Server-Anzeigename mit E-Mail-Präfix-Fallback.
> Offen: nur noch extern (Deploy/Swagger/Commit) + V2-Entscheidung (Sync-Lock).
>
> **⚠ Deploy-Reihenfolge (M5):** `rebuildPosDailyStats`-Backfill MUSS direkt nach
> `firebase deploy --only functions` laufen (VOR der ersten Nightly-Sync-Nacht) — sobald EIN
> `posDailyStats`-Doc existiert, bevorzugt der Client strikt die Server-Stats; ohne Backfill wirken
> bereits vorhandene Wochen-Daten sonst kurzzeitig „weg". Bekannter Tradeoff: der Client memoisiert das
> Stats-Fenster nicht (Segmentwechsel liest neu) — bei 2 Läden × ~365 Docs/Jahr akzeptiert (§3.3).

| M | Inhalt | Server | Offline testbar | Modell-Eignung |
|---|---|---|---|---|
| **M1** | Pure Engines: `kasse_report.dart` (Granularität, Buckets, netto/brutto, Δ Vorperiode/Vorjahr, `hatDaten`, Datenqualität inkl. A8-Signal) + `cash_state.dart` + `dailyStatsFromReceipts`-Adapter + Unit-Tests (feste Daten erlaubt, alle Referenzdaten explizit) | — | ✅ | `Geeignet für: Fable 5` (Geld-/Kennzahlen-Logik mit Edge-Cases — Fehler verfälschen still Beträge) |
| **M2** | Modelle `CashCount`/`CashClosing`/`PosDailyStat` (nur Firestore-Serialisierung, dokumentierte Ausnahme) + **OrgSettings-Feld `purchasePricesIncludeVat` + Einstellungs-Schalter (E1)** + Repository-Methoden + `InventoryProvider`-Mutatoren mit AuditSink + rules/indexes **im Repo** (Deploy separat) + Provider-Tests (FakeFirebaseFirestore; Zahlen kommen als `double` zurück!) | Dateien, kein Deploy | ✅ | `Geeignet für: Beide` (Datenmodell + Rules-Feindiff §9: Fable 5 · Repository/Provider-Boilerplate + Tests: Opus) |
| **M3** ✅ | Tagesabschluss-Ausbau: Kassenzustand-Karte, Zähl-Sheet, Differenz, „Tag abschließen" + Buchen-Flow (`bookedToFinance`), teamlead-Öffnung inkl. Badge-Datenpfad §7.2 + **Kiosk-Kachel „Kasse zählen" (blind, §7.3, E2)**; Widget-Tests (Screen/Sheet/Routen) | — | ✅ | `Geeignet für: Opus` (UI nach fixer Spec §7.2–§7.4; Rechte-Pfade sind im Plan entschieden) — **erledigt 03.07.** |
| **M4** ✅ | Kassenbericht-Screen `/kassenbericht`: **Woche voll (12 KW), Monat 3 Buckets + Langzeit-Hinweis, Jahr nur Hinweis** (Belege-Fenster ≤ 92 Tage) + Route/Permission/Dense + Hub-Karte + CSV-Export + Widget-Tests | — | ✅ | `Geeignet für: Opus` — **erledigt 03.07.** |
| **M5** ✅ | `posDailyStats`-Fortschreibung in `runOktoposSync` (§3.3) + `rebuildPosDailyStats`-Callable + `node --test` (13) + Client-Umschaltung: Monats-Sicht auf 12 Buckets, Jahres-Sicht aktiv (nach Backfill) | ✅ Functions + rules/index-Deploy (Blaze) — **Code fertig, Deploy offen** | Functions-Tests offline | `Geeignet für: Fable 5` — **erledigt 03.07.** |
| **M6** _(teilweise)_ | **✅ M6-A Kassendifferenz-Autobuchung** `pos-diff-{businessDay}-{siteId}` (§8a) · **✅ M6-B USt am Einkauf** (`taxRatePercent` je `PurchaseOrderItem` aus `Product.taxRatePercent`, Käufe echt netto/brutto, schalter-bewusst §3.4) · **✅ M6-C §3.4-Schalter in der Sortimentsanalyse** (EK-Netto identisch zum Kassenbericht) · **✅ M6-D Lohnquote-/Betriebsergebnis-Karte** (org-weit, Monat/Jahr, `PayrollRecord.employerTotalCents` ÷ Umsatz + Rohertrag − Personal) · **✅ M6-E Kiosk-Zählung-Härtung** (`kioskSaveCashCount`-Callable, session-validiert, server-authoritativer Anzeigename, blind) — alle 03.07. · **offen (extern/blockiert):** **Kassenzustand aus OktoPOS (E3)** braucht die gated Swagger / Hersteller-Anfrage (§2b); Swagger-Verifikation A2/A8/A9; Functions-Emulator-Test für `kioskSaveCashCount` (emulator-pending wie `kioskClockPunch`) | teils ✅ | teils ✅ | erledigt 03.07. |

Dazu die Verifikations-Pakete aus §2a: **V1** (Index-Diskrepanz auflösen, `Geeignet für: Opus`) und
**V2** (Sync-Konkurrenz-Regel/Lock, `Geeignet für: Fable 5`) — beide unabhängig von M1–M6 einplanbar.

Empfohlene Reihenfolge: V1/V2 (klein, jederzeit) · M1 → M2 → M3 → M4 (App liefert ab hier Zählung/Abschluss/Kassenzustand + Wochen-Vergleich komplett) → M5 (volle Monats-/Jahres-Sicht) → M6.

---

## 11. Kritische Kopplungen (beim Umsetzen abhaken)

1. **Neues Model** → hier bewusst NUR `toFirestoreMap`/`fromFirestore` (Ausnahme wie `PosReceipt` im Kommentar begründen); geht nichts durch Callables → kein snake_case in `functions/index.js` nötig (Ausnahme: `rebuildPosDailyStats`-Payload = primitive Strings).
2. **Neuer `where`+`orderBy`** → drei Composite-Indexe (§9) in `firestore.indexes.json` VOR dem ersten Cloud-Test deployen, sonst Laufzeitfehler.
3. **Neuer Screen mit URL** → `AppRoutes`-Konstante + `_sectionRoute` + `route_permissions` + Dense-Liste; Aufruf via `context.push(AppRoutes.kassenbericht)`; Zähl-Sheet bleibt imperativ.
4. **Rules ↔ Client synchron**: teamlead-Öffnung des Tagesabschluss-Screens NUR zusammen mit den cashCounts-/cashClosings-Rules ausliefern — und der Gebucht-Badge für teamlead MUSS auf `cashClosings.bookedToFinance` umgestellt sein, weil `journalEntries`-read admin-only ist (sonst leerer Status/Fehlerzustand, §7.2).
5. **`FrequencyGranularity` nicht anfassen** (label-Extension bricht Compile, `==`-Vergleiche würden `year` still falsch bucketen) — eigenes `ReportGranularity`.
6. **AuditSink** nur auf Erfolgs-Pfaden (`kasse.zaehlung`, `kasse.abschluss`, `kasse.abschluss_gebucht`), nie auf rethrow.
7. **Status-Farben** nur via `appColors`; alle Strings deutsch; `DateFormat(…, 'de_DE')`.
8. `REGION`-Konstante der neuen Callable = `FIREBASE_FUNCTIONS_REGION` (`europe-west3`).
9. `computeDailyClosings`/`daily_closing_posting` NICHT umbauen — der bestehende Buchungsfluss (idempotente Journal-IDs `pos-{businessDay}-{siteId}-{rate}`) bleibt die einzige Brücke ins Finanzmodul.
10. **Server-Tageszuordnung = Client-Tageszuordnung** (businessDay-Fallback auf transactionDate, §3.3) — sonst divergieren M4-Adapter und M5-Stats für dieselben Tage.
11. **§3.4-Schalter wirkt doppelt** — die EK-Normalisierung steckt in den Client-Engines UND im Server-COGS (§3.3). Logik-Änderung immer an beiden Stellen mitziehen (gleiche Disziplin wie beim Compliance-Spiegel `compliance_service.dart` ↔ `functions/index.js`).
12. **Kiosk-Zähl-Kachel ⇄ Geräte-Konto-Härtung (A0):** Die Kachel darf nicht als Anlass dienen, `role:kiosk` breiter zu berechtigen; die false-Permission-Overrides aus [arbeitsmodus-kachel-ausbau.md](arbeitsmodus-kachel-ausbau.md) §0 gehören VOR bzw. spätestens MIT M3 gesetzt (§7.0).
13. **Sync-Konkurrenz (V2):** posDailyStats-Fortschreibung (M5) erbt das getAll/commit-Zeitfenster des Movements-Batches — bis zur V2-Entscheidung gilt: kein manueller Sync zur Nightly-Zeit (03:30 Europe/Berlin).

---

## 12. Entscheidungen, offene Punkte & Annahmen

**Entschieden (Nutzer, 02.07.2026):**

- **E1 (ersetzt A1):** Die EK-Interpretation ist **einstellbar** — org-weiter Schalter `purchasePricesIncludeVat` (netto/brutto, gilt für alle Artikel, §3.4). Default netto.
- **E2 (ersetzt A4):** Zählen dürfen **alle Mitarbeitenden** — primär über die Kiosk-Kachel am Laden-Tablet (**blinde Zählung**, §7.3); Soll/Differenz sieht nur admin/teamlead. Rules erzwingen das (§9).
- **E3 (präzisiert A6):** Der Kassenzustand soll aus der **OktoPOS-Kasse geholt** werden, sobald das technisch geht. **Doku-Lage 02.07. (§2b): Es gibt derzeit KEINEN dokumentierten API-Endpunkt dafür** — Kassenbericht/Z-Bon existieren nur als manuelle Manager-Exporte. Weg dahin: gated Swagger prüfen (Login), sonst Hersteller-Anfrage „individuelle Schnittstellenerweiterung" oder täglicher Datei-Export (M6). Bis dahin ist die manuelle Zählung (Tablet/Screen) die Quelle; der rechnerische Soll-Bestand (§4.2) der Gegenwert.

**Annahmen / offen:**

- **A2 — Bar-Token:** Welche `payments[].method`-Strings OktoPOS wirklich liefert (bar/cash/…), ist erst nach der Echt-Validierung (P0) sicher. Bis dahin tolerantes Token-Set + „unbekannt"-Ausweis.
- **A3 — Kein EK-Verlauf:** Wareneinsatz nutzt den jeweils aktuellen EK — bei EK-Änderungen ist historischer Rohertrag ein Richtwert, und posDailyStats-Re-Aggregationen bewerten neu (§3.3). (`priceHistory` existiert nur für VK-Preise.)
- **A5 — Eine Kasse je Standort** angenommen (`cashRegisterId` wird als int mitgeführt, aber nicht separat bilanziert).
- **A6 — OktoPOS-EoD:** Öffentlich ist KEIN Z-Bon-/Kassenlade-Endpunkt dokumentiert (§2b); ob die gated Doku (8 Schnittstellen intern vs. 4 öffentlich) einen nicht beworbenen enthält, klärt der Login in <https://support.manager.oktopos.net/api-doc>. Wenn ja → E3: er wird Quelle des Kassenzustands (M6); die manuelle Zählung bleibt als Fallback und Kontrolle (Vier-Augen: gezählt vs. Kassen-Soll).
- **A7 — Zeitraum-Tiefe vor M5:** Das Belege-Fenster (≤ 92 Tage) trägt ~13 Wochen und nur 3 Monats-Buckets; Jahres-Sicht und Vorjahres-Δ (Woche UND Monat) werden erst nach M5 + `rebuildPosDailyStats`-Backfill befüllt.
- **A8 — Vorzeichen aus der Kasse:** Der Sync übernimmt Beträge unverändert (functions/index.js:3277–3284, keine Vorzeichenbehandlung). Umsatz, Soll-Bargeld und Kassendifferenz setzen voraus, dass Refund-`grossCents`/`payments[].amountCents` und die Ein-/Auszahlungs-Beträge der `type='cash'`-Belege **vorzeichenbehaftet** ankommen. Verifikation gegen Echt-Daten/gated Swagger (§2b) = Teil von P0; bis dahin Richtwert-Banner + Engine-Signal „positive Erstattungs-Belege erkannt" (§4.1).
- **A9 — Trinkgeld:** `PosReceipt` hat kein Tips-Feld, und ob die Transactions-API Trinkgeld ausweist, ist unbekannt (gated Swagger, §2b/§8a). Bis zur Klärung wird Trinkgeld NICHT erfasst — ehrlich dokumentiert, kein stilles Mitzählen im Umsatz.
- **A10 — Sync-Konkurrenz (V2):** Kein Lock zwischen manuellem Sync und Nightly; bis zur V2-Entscheidung gilt die Betriebsregel „kein manueller Sync um 03:30" (§2a, §11.13).
- **A11 — Wareneinsatz-Buchung netto (Folgepunkt aus M6-B-Review, vorbestehend):** Die H-A2-Auto-Buchung `FinanceProvider.postPurchaseOrderCost` bucht `order.totalCents` (den erfassten Preis). Unter dem **Default**-Schalter (`purchasePricesIncludeVat=false`) ist das netto und konsistent mit `kaeufeNettoCents`. Unter aktiviertem **Brutto**-Schalter bucht sie den Brutto-Betrag, während der Kassenbericht das herausgerechnete Netto zeigt → USt-Anteil im Finanzjournal zu hoch. Nicht durch M6-B verschlechtert (vorbestehend), aber sauber wäre `order.totalNetCents(priceIncludesVat:)` — braucht den Org-Schalter im FinanceProvider. Folge-Ticket, kein Blocker.

---

## 13. Definition of Done

- `flutter analyze` clean, `flutter test` komplett grün (bestehende Suite + neue Unit-/Widget-Tests), `node --test` für M5.
- Engines pur und deterministisch (kein `now()`/IO; `now` wird injiziert wie in `buildOrderFrequencyBuckets`).
- Offline-Demo-Lauf `flutter run --dart-define=APP_DISABLE_AUTH=true`: Kassen-Screens zeigen saubere Leerzustände (kein Crash, kein rotes Widget) — Lazy-Cloud-Repo-Regel beachtet.
- Rules + Indexe im Repo geändert; Deploy-Kommandos dokumentiert (`firebase deploy --only firestore:rules,firestore:indexes` bzw. `--only functions` für M5) — Deploy selbst bleibt user-gated.
- Rollenmatrix §9.1 in Tests gespiegelt: teamlead erreicht `/kassenbericht` nicht, employee-/Kiosk-Zählung kann `expectedCents` nicht setzen, Kiosk liest keine posReceipts.
- Kennzahlen-Definitionen aus §8 als Doc-Kommentare an den Engines; „Richtwert"-Banner sichtbar, solange die Swagger-Verifikation (inkl. A2/A8/A9) aussteht.
- [plan/README.md](README.md) und Memory-Index aktualisiert.
