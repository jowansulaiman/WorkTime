# OktoPOS-Kassenanbindung

Verknüpfung von WorkTime mit dem Kassensystem **OktoPOS Manager** (Hersteller-API).
Ziel: Abverkäufe der Kasse automatisch in den WorkTime-Bestand übernehmen
(Standorte Strichmännchen + Tabak Börse).

## Status

| Phase | Inhalt | Stand |
|---|---|---|
| **M1** | Model-Felder (`Product.externalPosId`, `StockMovement.source`/`externalRef`) + Tests | ✅ umgesetzt |
| **M2** | Cloud Function `syncOktoposTransactions` (read-only Pull → Bestandsabbuchung, idempotent) | ✅ umgesetzt |
| **M3** | Provider `InventoryProvider.triggerOktoposSync` + Admin-Menü „Kasse" (Abgleich auslösen **+ Einstellungs-Sheet**: baseUrl/Auto-Abgleich/cashRegisterId je Laden, merge-sicher) | ✅ umgesetzt |
| **M4** | Nächtlicher autonomer Pull `oktoposNightlySync` (opt-in `config.enabled`) | ✅ umgesetzt (inaktiv bis konfiguriert) |
| **M5** | Artikel-**Push** in die Kasse (Stammdaten/Preise/Barcodes) + Token-Lookups + USt-Feld am Artikel | ✅ umgesetzt |
| **M6a** | Kunden-**Import** (Contacts → OktoPOS, idempotent create-if-absent) | ✅ umgesetzt |
| **M6b** | Bestell-**Import** (OrderApi) | ⛔ bewusst **nicht** gebaut (keine valide Kiosk-Quelle, siehe unten) |

Freischaltung der Schnittstelle, API-Key/Token und das Setup übernimmt der Betreiber
(siehe **Inbetriebnahme**). Bis dahin ist die UI per `APP_OKTOPOS_ENABLED` (Default aus)
unsichtbar und die Functions sind inert.

## Recherche-Ergebnis (Hersteller-Schnittstellen)

Alle 8 dokumentierten OktoPOS-Schnittstellen waren erreichbar. Kernpunkte:

- **Auth einheitlich:** statischer API-Key im **HTTP-Header `X-API-KEY`** (kein OAuth,
  kein Token-Endpunkt). Im OktoPOS Manager unter „OktoPOS → System" abrufbar; pro
  Division/Standort vergebbar. `403` = keine Berechtigung.
- **Base-URL** ist instanzspezifisch (`https://<deine-instanz>/v1`) — **nicht** in den
  Specs ausgeschrieben, muss vom Betreiber beschafft werden.
- **Transaktions-Export Zeitraum** (Schnittstelle 6, der wertvolle read-only Pull):
  `GET /v1/transactions/from/{from}/until/{until}/page/{page}/size/{size}/cash-register/{cash-register}`
  — **Path-Parameter** (keine Query-Parameter); nicht genutztes `cash-register`-Segment
  ganz weglassen. Antwort: `TransactionResponse` (Paging-Hülle `actualPage`/`lastPage`/
  `transactionCount` + `transactions[]`), ggf. als Array (ein Wrapper je Kasse).
  - `Transaction`: `referenceNumber`, `type` (`sales`/`refund`/`cash`), `training` (bool),
    `businessDay` (ISO-Date), `transactionDate.timestamp`+`timezone`, `items[]`, `taxes[]`
    (`ReceiptTax{rate,net,tax,gross}` — Steuersatz nur auf Belegebene!), `gross` (Money).
  - `LineItem`: `id`, `quantity`, `price` (Money), `product{id,name,externalReference,scannedBarcode}`.
  - `Money` = `{currency.code, decimal, string}` — **nicht** in Cent → beim Import ×100.
- **Artikel-Import** (Schnittstelle 1, für M5/Push): `POST /v1/articles` mit
  `externalReferenceNumber` (stabiler Fremdschlüssel), `description`, `price[]`
  (je `distributionChannel` inkl. `taxRate`), `unit` (Token); Barcodes **getrennt** über
  `POST /v1/articles/add-barcodes`/`delete-barcodes`. Gültige Einheiten/Kanäle vorher per
  `GET /articles/units` bzw. `/distribution-channels` ziehen.

## Architektur & Sicherheit

**Entscheidung: Cloud Function als Proxy (Server-zu-Server), kein direkter HTTP-Call aus Flutter.**

Gründe:
1. **Secret-Schutz:** `X-API-KEY` ist ein Geheimnis → **Firebase Secret Manager**
   (`OKTOPOS_API_KEYS`), nie im Client-Bundle / in Firestore / per dart-define.
2. **CORS:** Ein Web-Direktaufruf gegen OktoPOS scheitert an CORS; die Function umgeht das.
3. **Kein HTTP-Paket im Client:** `pubspec.yaml` hat bewusst kein `http`/`dio` — der Client
   spricht nur Firebase Callables. Muster bleibt erhalten.
4. **App-Check + Auth + Org-Gating** erbt die Function automatisch (`onCall`,
   `loadCallerProfile`/`assertAdmin`/`assertSameOrg`).
5. **Bestandsbewegungen via Admin SDK** (umgeht die Client-Rules) → die Rules erlauben
   Clients **kein** `source=='oktopos'`; Kassen-Provenienz ist nicht fälschbar.
6. **TLS-Pflicht:** Die Function verweigert eine `baseUrl`, die nicht `https` ist
   (Key nie im Klartext).
7. **Idempotenz + Performance (gebündelt):** Deterministische Doc-ID je
   `(Kasse, Beleg, Position)` → `oktopos-<cr>-<ref>-<lineId>`. Gebucht wird
   **seitenweise im Batch** (`applyOktoposMovementsBatch`): ein `getAll`
   filtert bereits gebuchte Bewegungen heraus, dann pro Chunk (≤500 Writes) ein
   `WriteBatch` mit `batch.create` je neuer Bewegung (Race ⇒ atomarer Rollback,
   keine Doppelbuchung) und **einem** `FieldValue.increment` je Produkt. Statt
   einer `runTransaction` pro Position → wenige Round-Trips pro Seite (skaliert
   auch an Tagen mit vielen Verkäufen). Trade-off: `balanceAfter` bleibt bei
   Kassen-Bewegungen `null` (Bestand per increment fortgeschrieben).
8. **Nur LESEN aus OktoPOS** in M1–M4 — null Schreibrisiko in der Kasse.

## Datenfluss M1–M4 (read-only Pull)

```
OktoPOS  ──GET /v1/transactions/...──►  Cloud Function syncOktoposTransactions
  (X-API-KEY, Secret)                     │  Money.decimal ×100 → Cent
                                          │  training herausfiltern
                                          │  sales = Abgang(-) · refund = Zugang(+) · cash = ignorieren
                                          │  Join: scannedBarcode → externalPosId → sku
                                          ▼
              organizations/{orgId}/stockMovements  (source='oktopos', externalRef=Beleg)
              + products/{id}.currentStock (Transaktion, idempotent)
              + config/oktoposSync.sites[siteId].lastBusinessDay (Cursor)
                                          │  (Firestore-Streams)
                                          ▼
              InventoryProvider → Bestand sinkt, Bewegung „Kasse" sichtbar,
              speist Bestellhäufigkeit/Nachbestellung
```

### Feld-Mapping Transaktion → WorkTime

| OktoPOS | WorkTime | Hinweis |
|---|---|---|
| `LineItem.product.scannedBarcode` | `Product.barcode` | **primärer** Join |
| `LineItem.product.externalReference` | `Product.externalPosId` → `Product.sku` | Fallback-Joins |
| `LineItem.quantity` | `StockMovement.quantityDelta` | `sales` → negativ (`issue`), `refund` → positiv (`receipt`) |
| `Transaction.referenceNumber` | `StockMovement.externalRef` + Doc-ID | Idempotenz |
| `cash-register` / Division | `siteId` | Achse Standort ↔ Token (1 Token je Laden) |
| `training==true`, `type∈{cash}` | herausgefiltert | kein Bestandseffekt |
| `transactionDate.timestamp` | `StockMovement.createdAt` | sonst Geschäftstag |

**Bekannte Grenzen / Schutzmechanismen v1:**
- Gebinde/Kisten-Barcodes (`crate`) werden 1:1 als 1 Stück verbucht (kein Multiplikator
  aus der Transaktion ableitbar).
- Nicht zuordenbare Positionen werden **gezählt und gemeldet**
  (`unmatchedLineItems`/`unmatchedSamples`), nicht still verworfen.
- Verkäufe **ohne Belegnummer** werden gemeldet (`skippedNoReference`), aber **nicht
  gebucht** — ohne Belegnummer gibt es keinen stabilen Idempotenz-Schlüssel (bei echten
  fiskalischen Verkäufen kommt das nicht vor).
- **Mehrere Läden:** je Laden ist eine **Kassen-Nr.** Pflicht. Fehlt sie bei >1 Laden,
  bricht der Lauf mit Fehler ab — sonst würde ein Verkauf in beiden Läden gebucht
  (gleicher Barcode in beiden Sortimenten).
- Das Zeitfenster nutzt UTC-Grenzen mit Überlappung (Cursor + Idempotenz fangen
  Doppelläufe ab; sehr aktuelle Verkäufe erscheinen ggf. erst beim nächsten Lauf).
- Callable-Timeouts: Server 300s (manuell) / 540s (nächtlich), Client 120s — ein längerer
  Pull wird dadurch nicht fälschlich als Fehler angezeigt.

## Inbetriebnahme (Betreiber-Schritte)

> Voraussetzung: **Blaze-Plan** (ausgehende Netzwerk-Calls aus Functions + Secret Manager
> + Cloud Scheduler erfordern Blaze; Spark genügt nicht).

1. **Schnittstelle freischalten** beim OktoPOS-Support (Transaktions-Export Zeitraum;
   für M5 zusätzlich Artikel-Import). API-Key(s) + Base-URL + Kassen-IDs (`cash-register`)
   je Laden beschaffen.
2. **Secret setzen** (ein Key für alle Läden ODER JSON je Standort):
   ```bash
   # einzelner Key:
   firebase functions:secrets:set OKTOPOS_API_KEYS      # Wert: <der-key>
   # ODER Key je Standort (siteId → key):
   firebase functions:secrets:set OKTOPOS_API_KEYS      # Wert: {"site-1":"k1","site-2":"k2"}
   ```
3. **Config-Dokument** `organizations/{orgId}/config/oktoposSync` pflegen.
   **Am einfachsten in der App:** Warenwirtschaft → Menü „Kasse" → *Einstellungen*
   (Basis-URL, Auto-Abgleich, Kassen-Nr. je Laden; merge-sicher, lässt den Cursor
   unberührt). Alternativ direkt in Firestore (Admin-schreibbar, **kein** Secret darin):
   ```json
   {
     "baseUrl": "https://<deine-instanz>/v1",
     "enabled": true,
     "defaultSize": 50,
     "sites": {
       "site-1": { "cashRegisterId": 1 },
       "site-2": { "cashRegisterId": 2 }
     }
   }
   ```
   (`enabled` steuert nur den nächtlichen Auto-Pull; `cashRegisterId` weglassen = alle
   erlaubten Kassen.)
4. **Deployen:**
   ```bash
   firebase deploy --only firestore:rules,functions
   ```
5. **UI freischalten** (Sichtbarkeit, kein Secret):
   `flutter run/build --dart-define=APP_OKTOPOS_ENABLED=true`
6. **Auslösen:** Warenwirtschaft → App-Bar-Icon „Verkäufe aus Kasse übernehmen" (Admin) →
   Laden wählen → Ergebnis als Snackbar. Der nächtliche Lauf (03:30 Europe/Berlin) folgt
   automatisch, sobald `enabled=true`.

## M5 — Artikel-Push (umgesetzt, schreibt WorkTime → Kasse)

**Richtung:** WorkTime ist die Stammdatenquelle, Push nach OktoPOS (ArticleApi). Zwei
Admin-Callables (`functions/index.js`):
- **`pushOktoposArticles`** `{orgId, siteId, productIds?, dryRun?}` — ohne `productIds` alle
  **aktiven** Artikel des Standorts. Pro Artikel: `POST /v1/articles` (anlegen); bei **HTTP 409**
  (existiert) → `POST /v1/articles/change-prices` (nur Preise); Barcodes best-effort über
  `POST /v1/articles/add-barcodes` (`forceReuse:true`). Idempotenz über
  `externalReferenceNumber = WorkTime-Produkt-ID`. 403 bricht den ganzen Push ab; sonstige
  Fehler werden pro Artikel gemeldet (`results[]` + Zähler created/updated/failed/skipped).
- **`getOktoposLookups`** `{orgId, siteId}` — liefert `units` + `distributionChannels` (Tokens)
  für die Einstellungs-UI (`GET /v1/articles/units` + `/distribution-channels`).

**Mapping (Artikel-Body):** `Product.id`→`externalReferenceNumber`, `name`→`description`
(muss eindeutig sein!), `sku`→`materialNumber`, `category`→`group.token`,
`sellingPriceCents/100`→`ArticlePrice.price`, `taxRatePercent`→`ArticlePrice.taxRate`
(`"19.00"`), `unit`→`Unit.token` (per Map/Default), `barcode`→separat `add-barcodes`.

**Neue Config (`config/oktoposSync.push`):** `distributionChannel` (Token, z.B. `INHOUSE`),
`defaultUnitToken` (z.B. `Stück`), `defaultTaxRate` (z.B. `19`), `cashierCanChangePrice`,
optional `unitTokenMap` (WorkTime-Einheit → OktoPOS-Token). Beide ersten sind **Pflicht** für
den Push (sonst `failed-precondition`).

**Neues Model-Feld:** `Product.taxRatePercent` (int?, ganze Prozent) — im Artikel-Formular
editierbar; leer ⇒ `defaultTaxRate` aus der Config.

**Pull-Verbesserung:** `matchProduct` matcht jetzt zusätzlich `externalReference` gegen die
**Produkt-ID** — so findet der Pull die zuvor gepushten Artikel wieder, auch ohne Barcode.

**UI:** „Kasse"-Menü → *Artikel an Kasse senden* (mit Bestätigung, da schreibend) +
Einstellungs-Sheet-Abschnitt *Artikel-Versand (Push)* inkl. *Tokens laden* (zeigt die
Kassen-Tokens zum Übernehmen).

## M6a — Kunden-Import (umgesetzt, Contacts → Kasse)

Callable **`pushOktoposCustomers`** `{orgId, siteId, contactIds?, dryRun?}` (admin): schreibt
Kunden-Kontakte (`ContactType.customer`, aktiv) als OktoPOS-`Customer`. **Idempotent ohne
Update-Endpunkt:** zuerst `GET /v1/customers/findByExternalIdentifier/{contact.id}` — bei
404/409 (unbekannt) → `POST /v1/customers` (anlegen), sonst **übersprungen** (vorhandene
Kunden werden nicht verändert; die CustomerApi hat kein Update). `403` bricht ab.

**Mapping Contact → Customer (camelCase):** `id`→`externalIdentifier` (Idempotenz-Schlüssel);
`name`→`person.name.{givenName,familyName}` (Split: letztes Wort = Nachname, Rest = Vorname,
Einzelwort in beide); `email`→`person.email`; `phone`/`mobile`→`person.phone[]`
(`home`/`mobile`, max 2); `taxId`→`person.vatRegNo` (nur ≤15 Zeichen); `street`/`postalCode`/
`city`→`person.address.{streetAddress,postalCode,addressLocality}` (+`addressCountry:"DE"`);
`customerNumber`/`notes`→`comments[]` (`INTERNAL`). **Pflichtfeld `groups`** wird aus
`config.customerGroupName` (Default „Stammkunde") gefüllt. `gender`/`birthDate`/`houseNumber`
werden weggelassen (in WorkTime nicht vorhanden).

**UI:** „Kasse"-Menü → *Kunden an Kasse senden* (mit Bestätigung); Einstellungs-Feld
*Kundengruppe*.

## M6b — Bestell-Import: bewusst NICHT umgesetzt

Die **OrderApi** ist eine **Inbound**-Schnittstelle, über die ein vorgelagertes
Online-Shop-/Self-Order-/Küchensystem fertige Bestellungen in OktoPOS einspeist. Pflichtfelder
(`pickupToken`, `pickupTime` — Vergangenheit ⇒ HTTP 503 —, je Position `distributionChannel`
+ `taxRateId` als serverseitig vorprovisionierte Werte, kein Barcode/`externalReference` für
Artikel) **hat ein stationärer Tabak-/Kiosk-Laden ohne Online-Vorbestellkanal nicht**. Sie
ließen sich nur mit Dummy-Werten füllen, was **fehlerhafte/fiktive Bestellungen in die
fiskalische Verbuchung** schreiben würde — daher nicht gebaut. (Zusätzlich: Versionskonflikt
`swagger.yaml` 1.0.1 vs. Redoc 1.3.0 beim Anbieter offen.) Erst sinnvoll, wenn WorkTime einen
echten Click-and-Collect-/Vorbestell-Kanal bekommt.

## Berührte Dateien (M1–M6a)

- `lib/models/product.dart` — `externalPosId` + `taxRatePercent` (6-Stellen-Kopplung)
- `lib/models/stock_movement.dart` — `source` + `externalRef` (+ `isFromPos`)
- `firestore.rules` — `stockMovements`-Allowlist erweitert, Client darf `source` nur
  `null`/`'manual'` setzen
- `functions/index.js` — Secret `OKTOPOS_API_KEYS`; **Pull:** `syncOktoposTransactions`
  (onCall) + `oktoposNightlySync` (onSchedule); **Artikel-Push:** `pushOktoposArticles` +
  `getOktoposLookups`; **Kunden-Push:** `pushOktoposCustomers` (onCall); Sync-/Push-Kern + Helfer
- `lib/services/firestore_service.dart` — `syncOktoposTransactions`/`pushOktoposArticles`/
  `getOktoposLookups` (Callable-Wrapper) + `fetch/saveOktoposConfig(...)` (merge-sicher,
  inkl. `push`-Einstellungen)
- `lib/providers/inventory_provider.dart` — `triggerOktoposSync` / `pushOktoposArticles` /
  `loadOktoposLookups` / `load/saveOktoposConfig` + Audit
- `lib/core/app_config.dart` — `oktoposEnabled` (UI-Schalter)
- `lib/screens/inventory_screen.dart` — Admin-Menü „Kasse" (Abgleich/Artikel-Versand) +
  `_OktoposSettingsSheet` (inkl. Push-Felder + Tokens laden) + USt-Feld im Artikel-Formular
- `test/oktopos_integration_test.dart` — Model-Roundtrips, Provider-Trigger, Push, Config-Merge
