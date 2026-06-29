# Bestellhäufigkeit — „häufig bestellte Artikel zuerst" + Auswertung

Status: **umgesetzt** (Juni 2026). Branch: main (uncommitted).

## Ziel (Nutzer-Wunsch)

1. Bei Bestellung/Nachbestellung sollen die **häufig bestellten Artikel** immer
   Vorrang haben — auf dem **Scanner** und in den **Bestellungen**.
2. Ein **Bereich** zum Ansehen der Artikel-Bestellhäufigkeit **pro Woche / pro
   Monat**, modern als Diagramm.

## Entscheidungen (mit Nutzer abgestimmt)

- **„Häufig" = Anzahl Lieferantenbestellungen**, in denen der Artikel vorkam,
  rollierend **~12 Wochen** (`InventoryProvider.orderFrequencyWindow = 84 Tage`).
  Eine Bestellung zählt je Artikel **1×** (nicht Stückzahl). **Stornierte**
  Bestellungen zählen nicht. Datum = `orderedAt ?? createdAt`.
- **Quelle = `PurchaseOrder`-Historie** (liegt im Cloud/Hybrid voll im Speicher
  als `_orders`, lokal aus dem Cache). **Kein** neues Model-Feld, **kein**
  Firestore-Index, **keine** Rules-Änderung — rein abgeleitet (retroaktiv).
- **Auswertung = eigener Screen** (kein neuer Tab), `AppRoutes.orderAnalytics`
  = `/bestell-auswertung`, Berechtigung wie Warenwirtschaft (`canViewInventory`).

## Umsetzung

### Kern (pur, getestet)
- `lib/core/order_frequency.dart`: `isoWeekNumber`, `startOfIsoWeek`,
  `startOfMonth`, `FrequencyGranularity{week,month}`, `OrderFrequencyBucket`,
  `buildOrderFrequencyBuckets(...)` (letzte N Fenster, älteste zuerst, storniert
  raus, optional siteId/productId). Tests: `test/order_frequency_test.dart`.

### Provider (`lib/providers/inventory_provider.dart`)
- `orderFrequencyByProduct({siteId, now})` → `Map<productId,Anzahl>`, memoisiert
  je `(siteId, Tag)`, invalidiert in `_safeNotify` (Cache `_orderFreqCache`).
  Tag im Key, damit eine über Mitternacht offene Sitzung nicht driftet.
- `orderFrequencyFor`, `sortByOrderFrequency(list, {siteId})` (Seam für alle
  Bestell-Listen), `frequentlyOrderedProducts({siteId, limit})` (nur bestellte,
  absteigend). Tests: `test/inventory_order_frequency_test.dart`.

### Priorisierung „häufig zuerst" (Seam `sortByOrderFrequency`)
- Scanner Bestell-Modus: neue Schnellwahl-Zeile „Häufig bestellt" (Chips →
  `_addScannedToCart`) in `_buildOrderSession` (`scanner_screen.dart`).
- „In den Warenkorb"-Sheet + Artikel-Picker (`order_cart_screen.dart`).
- Bestell-Editor `_candidates` (`purchase_order_screens.dart`): `needsReorder`
  → Häufigkeit → Name.

### Auswertungs-Screen (`lib/screens/order_analytics_screen.dart`)
- Woche/Monat-Umschalter (SegmentedButton), Laden-Dropdown, Balkendiagramm
  (`_FrequencyBarChart`, angelehnt an `personal_screen`/`statistics_screen`),
  Top-Artikel-Rangliste (Antippen filtert das Diagramm auf einen Artikel).
- Routing-Kopplung #7 vollständig: `AppRoutes.orderAnalytics` (shell_tab.dart),
  `_sectionRoute` + Import (app_router.dart), `RoutePermissions.isLocationAllowed`
  (route_permissions.dart). Erreichbar: Laden-Hub-Karte + Warenwirtschaft-AppBar
  (`insights_outlined`) + V2-Slide-in-Menü (`app_nav_menu.dart`,
  `onOpenOrderAnalytics`).

## Adversariales Review (sauber)
Keine echten Bugs. ISO-Woche gegen Referenz 2000–2040 geprüft (inkl. 53-Wochen-
Jahre, DST). Cache-Invalidierung über alle `_orders`-Mutationspfade ok. Keine
In-place-Sortierung von `_products`. Behoben: Cache-Tag im Key, Rangliste-Label
„rollierend ~12 Wochen" (statt exakt „12 Wochen", da Chart-Fenster leicht abweicht).
Offen als Tech-Debt (nicht hier gebündelt): `_FrequencyBarChart`/`_SectionCard`
sind die 3. Kopie der fl_chart-Konfig → ggf. nach `lib/widgets/` heben.
