# Archivierte Problem-/Bug-Befunde

Detaildateien aus dem Code-Review vom 21.06.2026, deren Befunde am aktuellen Code
**vollständig behoben** (oder als geringfügiges Restrisiko **bewusst akzeptiert**) sind
(re-verifiziert 2026-07-04 und 2026-07-12, Multi-Agent). Nur zur Historie;
Zeilennummern der Ursprungsbefunde sind veraltet. Live-Roll-up der noch offenen
Bereiche im [Problem-Index](../README.md).

## Abschluss-Welle 2026-07-12 (alle Restbefunde des 21.06.-Reviews)

- **compliance.md** — Restbefunde erledigt: **#24** behoben — einheitliche Formel
  `max(0, round(Brutto) − round(Pause))` in beiden Spiegeln
  (`_shift/_entryWorkedMinutes` ↔ `workedMinutesFromShift/Entry`) + Grenzfall-Tests
  (631,5-min-Brutto mit 30,5-min-Pause an der daily_limit-Grenze, Clamp-Fall).
  **#26** als bewusste Entscheidung dokumentiert: Jugend-/Mutterschutz-Nachtfenster
  ist das GESETZLICHE Fenster 20:00–06:00 (JArbSchG § 14 / MuSchG § 5), per
  Org-Konfiguration nicht lockerbar — Doku-Kommentar an beiden Spiegel-Funktionen +
  Hinweis in der RuleSet-Karte (team_management_screen).
- **provider-state.md** — **#22** (mittel) behoben: persistiertes Pending-Sync-Set
  (`_pendingEntryIds`, `DatabaseService.load/savePendingSyncIds`) — im
  Hybrid-Fallback lokal geschriebene Einträge werden beim Merge
  (`_storeHybridWorkEntriesSnapshot`/`cacheCloudStateLocally`) nie mehr von
  Cloud-Snapshots per Wall-Clock-Vergleich überschrieben; Auflösung nach
  erfolgreichem Cloud-Write bzw. `syncLocalStateToCloud`; Clock-Skew-Regressionstest.
  **#44** bewusst akzeptiert (dokumentierte Fail-open-Designentscheidung der
  Force-Update-Config).
- **screens-ui.md** — **#51** behoben (`AppConfig.parseStoreNames` kappt auf die
  Rules-Grenze 120 Zeichen); **#53** war bereits behoben (`computeZeitkonto`
  filtert Einträge hart auf Jahr+Monat der Record-Periode — Falscher-Monat-Prefill
  unmöglich); **#54** behoben (per-Build-Cache `_dayAbsenceCache` analog zum
  Schicht-Bucketing, Filter+Sort einmal je Tag statt je Board-Zelle).
- **services-firestore.md** — **#39** bewusst akzeptiert (dokumentierter Tradeoff:
  keine untere Datumsgrenze wegen mehrjähriger Anträge); **#48** behoben
  (per-Stream-Flag `orderListsLoadFailed` statt globalem `_setError`, Korb-UI
  unterscheidet „leer" von „konnte nicht geladen werden", + Test).
- **services-persistenz.md** — **#33** behoben (Legacy-Daten ohne orgId matchen
  nur noch die Default-Org statt jeden Scope); **#34** behoben
  (Org-Isolations-/Sharing-Tests für `order_carts`/`weekly_order_lists`);
  **#37** behoben (`sharePositionOrigin`-Parameter über alle drei
  Download-Fassaden + Bildschirmmitte-Fallback für iPad/macOS-Popover).
- **navigation-bootstrap.md** — **#56** bewusst akzeptiert (Force-Update fail-open
  by design); **#57** behoben (Strg+1..9 bindet layoutabhängig: Rail →
  railDestinations, V1-Bottomnav → volle destinations inkl. Profil, V2 → die
  sichtbare 5er-Leiste); **#58** behoben (leere/ungültige Historie → `SystemNavigator.pop()`
  statt verschlucktem erstem Zurück-Druck); #59 war bereits erledigt.
- **test-luecken.md** — alle Lücken geschlossen: **#19** Hybrid-Fallback +
  cloud-only-rethrow der Bestelllisten (`_OrderListOfflineRepository`);
  **#66** `public_wish_screen_test.dart` (Validierung, ehrlicher
  Ohne-Firebase-Fehler, Mengen-Stepper); **#67** Cloud-Checkout/Prefill/
  Rollback-Round-Trips; **#68** `customer_wishes_screen_test.dart`
  (Berechtigungs-Gate, Filter, Status→Firestore) + `order_cart_screen_test.dart`
  (Checkout-Doppel-Tap-Sperre, Wochenlisten-Editor-Save); **#69** voller
  camelCase-Round-Trip inkl. notes/handledByUid/handledAt; **#70**
  Zwei-Läden-Isolation + Einzel-Laden-Fallback; **#71** Merge-Clear von
  Kategorie/Lieferant; **#72** Name+Einheit-Fallback beim Checkout; **#73**
  `parseStoreNames`-Parsing-Tests.

- **01-kritisch-hoch.md** — Alle 5 kritischen/hohen Befunde behoben: #1 Server-Compliance-Spiegel `validateSingleWorkEntry` vollständig an Dart angeglichen (rest/minijob/minor/pregnancy/overtime + `travelTimeRules`), #2 minutengenaue Aggregation (`_shift/_entryWorkedMinutes`), #3 stabile Client-UUIDs vor Callable, #4 `Money.parseCents` (1.99 → 199 Cent), #5 Übernacht-Schichten via Folgetag-Rollover.
- **core-lohn.md** — Alle 6 Befunde (#27–#32, niedrig) behoben: `Money.parseCents`-Punkt-Heuristik + Test, `taxTariff` via `_tariffForYear(year)` abgeleitet, `validateEnvironment` auf `!kDebugMode` (blockt Release + Profile), tote Felder (`soliRate`/`incomeTaxRateByClass`) als veraltet dokumentiert, `_midijobBase`-Edge-Case bewusst dokumentiert.
- **modelle-serialisierung.md** — Einziger Befund #45 (niedrig) behoben: `PurchaseOrderItem.copyWith` hat jetzt `clearSku`-Flag (identisch zum Schwester-Model `CustomerOrderItem`, mit Verweis auf #45).
- **sicherheit.md** — Alle Befunde behoben/akzeptiert: #60/#61 (orderCarts Feld-Allowlist + `updatedByUid`-Bindung, beide hoch) in `firestore.rules`; #17 (customerWishes Spam/Cross-Tenant) via `firebase_app_check` in `main.dart` + streng allowlisteter create-Regel adressiert, Rest-Risiko (kein In-Rules-Rate-Limit) bewusst als App-Check-Betriebsannahme dokumentiert; #62 (`publicWishOrg()` hart 'main-org', niedrig) als Konfig-Footgun in Regel-Kommentaren festgehalten.
- **bestellkorb-kundenwuensche.md** — Einziger Befund #46 (niedrig): checkoutCart-Mengen-Race technisch unverändert, aber in `_persistOrderList` explizit als „last writer wins / für zwei Läden bewusst akzeptiert" dokumentiert → als Restrisiko akzeptiert.
