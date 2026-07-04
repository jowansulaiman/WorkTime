# OktoPOS-Kassenanbindung

Die Anbindung an das Kassensystem **OktoPOS** läuft ausschließlich über Cloud Functions – die **einzigen** Functions mit ausgehendem HTTP (`fetch`, Header `X-API-KEY`). Sie brauchen **Blaze** (Outbound + Secret + Scheduler).

## Datenflüsse

- **Pull** (Verkäufe → Bestand): `syncOktoposTransactions` (onCall) + `oktoposNightlySync` (onSchedule). Schreibt Bestandsbewegungen via **Admin SDK** (umgeht Rules) mit `source:'oktopos'` – der Client dürfte das laut `stockMovements`-Rules **nicht**.
- **Artikel-Push** (Artikel/Preise → Kasse): `pushOktoposArticles` + `getOktoposLookups` (onCall). Idempotenz über `externalReferenceNumber = Produkt-ID` (409 → change-prices).
- **Kunden-Push** (Contacts Typ Kunde → Kasse): `pushOktoposCustomers` (onCall), idempotent via `findByExternalIdentifier` create-if-absent (CustomerApi hat kein Update).

Die **OrderApi** (Bestell-Import) ist bewusst **nicht** gebaut (keine Kiosk-Quelldaten).

## Konfiguration & Secret

> [!WARNING]
> Der API-Key liegt im **Secret Manager `OKTOPOS_API_KEYS`**, NIE im Client. Betriebs-Config (baseUrl/cashRegisterId/push-Tokens) liegt in `config/oktoposSync`.

## Server-Tagesaggregate

`functions/oktopos_stats.js` schreibt beim Sync `posDailyStats` fort (Spiegel der Dart-Engine) und stellt `rebuildPosDailyStats` (Callable) zum Backfill bereit. Der Client bevorzugt Server-Stats für die volle Monats-/Jahres-Historie. Details: [Kasse/POS (technisch)](article:dev-kasse-pos-technik).

## UI-Schalter

`AppConfig.oktoposEnabled` (`APP_OKTOPOS_ENABLED`, Default aus) gated die UI. Der volle Datenwert-Ausbau (Velocity, Dead-Stock, Rohertrag/ABC) ist im Plan `plan/oktopos-datenwert-plan.md` dokumentiert.

> [!IMPORTANT]
> Nach dem Functions-Deploy muss `rebuildPosDailyStats` einmalig als **Backfill** laufen, sonst fehlt die Historie.

## Weiter

- [Cloud Functions](article:dev-cloud-functions)
- [Kasse/POS (technisch)](article:dev-kasse-pos-technik)
- [Warenwirtschaft (technisch)](article:dev-warenwirtschaft-technik)
