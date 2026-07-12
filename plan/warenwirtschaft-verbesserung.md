# Warenwirtschaft: Analyse + Verbesserung (11.07.2026)

Tiefenanalyse des Warenwirtschaftsbereichs (8 parallele Teilanalysen: UI, Provider,
Modelle, Auswertungen, Bestell-Flow, Rules/Backend, Tests, Plan-Doku — >90 Befunde)
mit direkt umgesetzter erster Ausbaustufe. Dieses Dokument hält fest, was gefixt/
gebaut wurde und welche bestätigten Befunde als Backlog offen bleiben.

## Umgesetzt (code-fertig, getestet)

### Bugfixes

| # | Befund | Fix |
|---|---|---|
| B1 | **Kühlschrank-Nachfüllen konnte in cloud/hybrid NIE nach Firestore schreiben**: `setFridgeStock` schreibt einen Batch (products.fridgeStock + `fridge_refill`-Bewegung), aber die `stockMovements`-Rules kannten den Typ `fridge_refill` nicht und verlangten `canManageInventory()` → Batch scheiterte für alle, hybrid divergierte still lokal. | `firestore.rules`: zweiter Create-Pfad — `fridge_refill` für jedes aktive Org-Mitglied (Feld-Allowlist/Typprüfungen unverändert), übrige Typen weiter Leitung-only. **Deploy nötig** (`firebase deploy --only firestore:rules`). |
| B2 | **Preis-Tippfehler löschte still den gespeicherten Preis**: `parseEuroToCents('1,9o') == null` ⇒ `clearPurchasePrice/clearSellingPrice` beim Speichern. | Validatoren auf EK/VK-Feldern im Artikel-Editor: leer = löschen erlaubt, nicht parsebar = Speichern blockiert. |
| B3 | **Lokale Bestellnummern kollidierten nach Löschung** (`_orders.length + 1`). | `_nextLocalOrderNumber()`: höchstes Jahres-Suffix + 1. |
| B4 | **Lösch-dann-Speichern-Crash im local-Modus**: deleteProduct/-Supplier/-PurchaseOrder/-CustomerOrder hinterließen `toList(growable: false)`, `_upsertLocal` ruft `.add()` → `Unsupported operation`. Vom neuen Test aufgedeckt. | Alle vier Delete-Pfade growable. |
| B5 | **Ladenhüter-Fenster log**: Liste rechnete mit dem 28-Tage-Fenster, UI behauptete 60 Tage. | `SalesInsightsProvider` lädt ein separates 60-Tage-Read-Model für Ladenhüter. |
| B6 | **`isReliable` war praktisch immer true** (maß die angefragte Fensterlänge statt der echten Datenhistorie). | `ProductVelocity.dataDays`/`effectiveDataDays` + optionales `dataSince`; Datenbasis wird aus Bewegungen/`createdAt` abgeleitet. |
| B7 | **Neu-Artikel galten sofort als Ladenhüter** und bekamen „Schwellen auf 0"-Vorschläge. | `isNewProduct`-Guard in `sales_velocity`/`reorder_suggestion`. |
| B8 | Inventur-Dialog füllte den Buchbestand vor (Schein-Inventur bei hastigem Speichern). | Leeres Pflichtfeld, Speichern erst bei Eingabe. |

### Neue Bereiche / Funktionen

1. **Geführter Inventur-Modus `/inventur`** (`lib/screens/inventur_screen.dart`):
   Zähl-Session je Laden (Standort-Chips, Warengruppen-Filter, Suche), leere
   Zähl-Felder, Fortschritt, Differenz-Vorschau (nur Abweichungen, EK-Summe nur
   für Leitung), sequenzielles Buchen über `recordStocktake`, PopScope-Schutz.
   Routing-Kopplung #7 vollständig (AppRoutes/_sectionRoute/RoutePermissions/
   global_search). Einstieg: AppBar-Button im Bestand-Tab (nur `canManageInventory`).
2. **Bestellung erreicht den Lieferanten**: Bestell-PDF
   (`PdfService.generatePurchaseOrderDocument`, bewusst ohne EK-Preise) + „PDF
   teilen" (downloadFileBytes-Muster, Web+Mobile) + „Per E-Mail senden" (mailto
   mit Klartext-Body aus `ExportService.buildPurchaseOrderText`) im Bestell-Detail.
3. **Bewegungshistorie je Artikel sichtbar**: Menüpunkt „Bewegungen anzeigen" →
   Bottom-Sheet (`InventoryProvider.movementsForProduct`, nutzt vorhandenen
   `(productId, createdAt)`-Index); „Preisverlauf" (vorhandenes Sheet) jetzt auch
   aus der Warenwirtschaft erreichbar (vorher nur Scanner).
4. **Filter + Sortierung im Bestand-Tab**: Chips Nachbestellen/Leer/Kühlschrank +
   Warengruppen-Menü + Sortierung (Name / Bestand niedrig zuerst / Warenwert).
5. **Umlagern ohne Vorarbeit**: Ziel ist jetzt ein Standort; fehlt der Artikel
   dort, legt `transferStockToSite` ihn automatisch an (Stammdaten übernommen,
   Bestand 0) und bucht dann. Match vorhandener Zielartikel via Barcode→Name.
   (`InventoryRepository.saveProduct` gibt dafür jetzt die Doc-ID zurück.)
6. **Zugang buchen** als eigener Menüpunkt (Typ `receipt`, mit Grund) + Grund-Feld
   in der Bestandskorrektur (Schwund-Report bleibt aussagekräftig).
7. **Bestellungen-Tab Status-Filter** (Alle/Offen/Geliefert/Storniert).
8. **Lieferanten: Telefon/E-Mail antippbar** (tel:/mailto:-ActionChips).
9. **Warenwert/Spanne-Metrikblock nur noch für `canManageInventory`** (EK-Wissen,
   konsistent zur admin-only Sortimentsanalyse).

### Tests

Neu/erweitert: `test/inventur_screen_test.dart` (4), `test/inventory_provider_test.dart`
(+5: Bestellnummern, movementsForProduct, transferStockToSite ×3),
`test/pdf_service_test.dart` (+3), `test/sales_velocity_test.dart` (+3),
`test/reorder_suggestion_test.dart` (+2), `test/dead_stock_test.dart` (+1),
`test/sales_insights_provider_test.dart` (+1), `test/route_permissions_test.dart` (+`/inventur`).

## Review-Runde (adversarial, 12.07.)

Multi-Agent-Review (Korrektheit/Kopplungen/Sicherheit) über das Session-Diff,
jeder Befund adversarial verifiziert. Alle bestätigten Befunde wurden gefixt:

| Befund | Fix |
|---|---|
| **Poison-Doc-DoS (hoch)**: der neue Jedermann-`fridge_refill`-Create-Pfad prüfte productName/reason/relatedOrderId nicht auf Typ; `StockMovement.fromFirestore` hart-castete → EIN bösartiges Doc hätte alle Bewegungs-Reads der Org gecrasht (und wäre client-seitig unlöschbar). | Rules: `is string`-Checks (Muster cashCounts) + `siteId`/`productId is string`; Parser toleriert jetzt alle String-Felder via `?.toString()` (Repo-Regel „Parser nie hart casten"). |
| **Kiosk-Refill lief ins Leere (hoch)**: `setFridgeStock` macht vor dem Batch einen Idempotenz-`get()` auf die Movement-Doc — `read` verlangte `!isKiosk()` → permission-denied → stiller Hybrid-Fallback nur in die Tablet-SharedPreferences. | Rules: `read` gesplittet in `get` (sameOrg, auch Kiosk — Punkt-Get einer zufälligen UUID leakt nichts) und `list` (weiterhin `!isKiosk()`). |
| **Audit-Fälschung (mittel)**: Jedermann-Pfad erlaubte `createdByUid: null` (anonyme Protokoll-Einträge). | `createdByUid == request.auth.uid` ist im Jedermann-Pfad Pflicht. |
| **Hybrid-Fallback-Crash-Klasse (hoch)**: `_upsertLocal` mutierte per `.add()` in-place — in cloud/hybrid sind die Felder `growable: false`-Streamlisten → `UnsupportedError` in JEDEM Offline-Fallback nach erstem Stream-Emit (traf neu `transferStockToSite`, vorbestehend auch saveProduct/saveBatch/Karten). | `_upsertLocal` liefert eine neue growable Liste, alle 10 Aufrufer weisen zu. |
| **Stille Bestandsvernichtung (niedrig)**: Cloud-Anlage des Umlagerungs-Ziels ok, Folgebuchung fällt lokal zurück → Zielartikel noch nicht im Stream → Buchung lief still ins Leere (Quelle belastet, Ziel leer, „Erfolg" gemeldet). | Nach Cloud-Anlage wird der Zielartikel sofort in `_products` übernommen. |
| **Inventur-Verwerfen-Dialog doppelt (mittel)**: `maybePop()` direkt nach `setState` sah den noch nicht aktualisierten `PopScope`-Notifier → Dialog erschien erneut. | Nach bestätigtem Verwerfen bedingungsloses `pop()`. |
| **isReliable-Regression (mittel)**: abgeleitetes `dataSince` aus fenster-gefilterten Bewegungen → sobald irgendeine Bewegung im Fenster lag, galten ALLE Artikel als „nicht belastbar". | Inferenz nimmt das früheste Signal aus Bewegungen UND Artikel-`createdAt` gemeinsam. |
| **Warenwert-Sortierung für Nicht-Leitung (niedrig)**: EK-Rangfolge war trotz Metrik-Gating über die Sortierung ablesbar. | Sortieroption `Warenwert` nur noch für `canManageInventory` + defensiver Reset. |
| **_MovementsSheet-Refetch (niedrig)**: Future wurde in `build()` erzeugt (Spinner-Flackern + Doppel-Query bei Rotation/Theme). | StatefulWidget, Future einmalig in `initState`. |

Bewusst offen gelassen (Backlog, siehe unten): `_tryFirestore` wertet auch
nicht-transiente Fehler (permission-denied) als „offline" und fällt still
lokal zurück; getAfter()-Kopplung der fridge_refill-Bewegung an das
products-Update (kostet ein Rules-Read, gegen Protokoll-Fluten durch Insider).

## Deploy-Hinweise

- `firebase deploy --only firestore:rules` — ohne den fridge_refill-Fix bleibt
  das Kühlschrank-Nachfüllen in cloud/hybrid wirkungslos (B1). Reiht sich in den
  bestehenden Deploy-Stau ein (plan/deploy-checkliste.md).
- Keine neuen Indexe nötig (movementsForProduct nutzt den vorhandenen
  `(productId, createdAt)`-Composite-Index).

## Backlog (bestätigte Befunde, bewusst NICHT in dieser Stufe)

Priorisiert nach Alltagsnutzen:

1. **Wareneingang-Dialog ausbauen**: MHD-Abfrage (legt ProductBatch an), Ist-EK
   je Position (aktualisiert Preis + priceHistory), Lieferschein-Nr. am Beleg.
2. **„Unterwegs"-Menge**: offene Bestellmengen je Artikel berechnen und in
   Nachbestell-Banner/Vorschlägen berücksichtigen (Doppelbestell-Schutz);
   „Rest schließen" für ewige Teillieferungen (sonst wird der Wareneinsatz
   nie gebucht — finance-Kopplung prüfen).
3. **Hybrid-Offline-Outbox**: offline gebuchte Bestandsänderungen werden bisher
   nie in die Cloud nachgespielt (nur userContent-Spiegel, kein Replay).
   Größerer Umbau, eigener Plan empfohlen.
4. **transferStock im Hybrid-Modus**: Quelle kann in der Cloud, Ziel nur lokal
   landen (Split-Brain); Kompensationslogik greift im Fallback nicht.
5. **Deaktivieren statt Löschen** („führen wir nicht mehr") + Aufräumen
   abhängiger Daten (priceHistory/Chargen/Bewegungen bleiben als Waisen).
6. **MHD/Chargen in der Warenwirtschaft** sichtbar machen (bisher nur Scanner/
   Inbox): Chargenliste je Artikel, Ablauf-Chip in der Bestandszeile.
7. **Marge ist brutto/netto-gemischt** (VK brutto vs. EK netto) — echte
   Rohertrags-Marge braucht USt-Bereinigung; mit Kassen-Modul-Schaltern
   (`grossPurchasePrices`) konsistent lösen.
8. **Kundenbestellung „abgeholt"** bucht keinen Bestandsabgang.
9. **Kühlschrank-Welten koppeln**: manuelle Nachfüllliste vs. Soll-Ist-Automatik
   laufen aneinander vorbei.
10. **Stream-Fehler je Collection isolieren** (ein Fehler reißt heute das ganze
    Modul in den Fehlerzustand); `watchProductBatches` auf aktive Chargen begrenzen.
11. Etiketten-/Preisschilddruck (A4-Bogen) — nice-to-have, ESL-Plan beachten.

## Bewusst verworfen

- OrderApi-/Bestell-Import aus OktoPOS (keine Kiosk-Quelldaten, laut Plan verworfen).
- Kein neues State-Management/Repo-Split in dieser Stufe (God-File-Split
  inventory_provider/inventory_screen = eigenes Refactoring-Vorhaben).
