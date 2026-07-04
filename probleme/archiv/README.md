# Archivierte Problem-/Bug-Befunde

Detaildateien aus dem Code-Review vom 21.06.2026, deren Befunde am aktuellen Code
**vollständig behoben** (oder als geringfügiges Restrisiko **bewusst akzeptiert**) sind
(re-verifiziert 2026-07-04, Multi-Agent). Nur zur Historie; Zeilennummern der
Ursprungsbefunde sind veraltet. Live-Roll-up der noch offenen Bereiche im
[Problem-Index](../README.md).

- **01-kritisch-hoch.md** — Alle 5 kritischen/hohen Befunde behoben: #1 Server-Compliance-Spiegel `validateSingleWorkEntry` vollständig an Dart angeglichen (rest/minijob/minor/pregnancy/overtime + `travelTimeRules`), #2 minutengenaue Aggregation (`_shift/_entryWorkedMinutes`), #3 stabile Client-UUIDs vor Callable, #4 `Money.parseCents` (1.99 → 199 Cent), #5 Übernacht-Schichten via Folgetag-Rollover.
- **core-lohn.md** — Alle 6 Befunde (#27–#32, niedrig) behoben: `Money.parseCents`-Punkt-Heuristik + Test, `taxTariff` via `_tariffForYear(year)` abgeleitet, `validateEnvironment` auf `!kDebugMode` (blockt Release + Profile), tote Felder (`soliRate`/`incomeTaxRateByClass`) als veraltet dokumentiert, `_midijobBase`-Edge-Case bewusst dokumentiert.
- **modelle-serialisierung.md** — Einziger Befund #45 (niedrig) behoben: `PurchaseOrderItem.copyWith` hat jetzt `clearSku`-Flag (identisch zum Schwester-Model `CustomerOrderItem`, mit Verweis auf #45).
- **sicherheit.md** — Alle Befunde behoben/akzeptiert: #60/#61 (orderCarts Feld-Allowlist + `updatedByUid`-Bindung, beide hoch) in `firestore.rules`; #17 (customerWishes Spam/Cross-Tenant) via `firebase_app_check` in `main.dart` + streng allowlisteter create-Regel adressiert, Rest-Risiko (kein In-Rules-Rate-Limit) bewusst als App-Check-Betriebsannahme dokumentiert; #62 (`publicWishOrg()` hart 'main-org', niedrig) als Konfig-Footgun in Regel-Kommentaren festgehalten.
- **bestellkorb-kundenwuensche.md** — Einziger Befund #46 (niedrig): checkoutCart-Mengen-Race technisch unverändert, aber in `_persistOrderList` explizit als „last writer wins / für zwei Läden bewusst akzeptiert" dokumentiert → als Restrisiko akzeptiert.
