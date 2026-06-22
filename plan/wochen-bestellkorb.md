# Wochen-Bestellkorb + Standard-Wochenliste

**Status: implementiert (2026-06-21).** Bestand-unabhängiges Nachbestellen für die
zwei Läden in Kiel.

## Problem / Ziel

Bisher hing das Nachbestellen am Warenbestand (`Product.needsReorder`,
`InventoryProvider.buildReorderItems`) — das hieß manuelles Bestandspflegen.
Gewünscht: **jede Woche aus der Artikelliste bestellen**, wobei **jeder
Mitarbeiter** einen leeren Artikel mit Menge in einen geteilten **Bestellkorb**
legt und der **Admin** den Korb als echte Bestellung(en) auslöst.

## Entscheidungen (vom Nutzer bestätigt)

1. **Bestand bleibt optional** (Scanner/Inventur/Wareneingang unverändert); das
   Bestellen ist davon entkoppelt — die ganze Artikelliste ist bestellbar.
2. **Checkout erzeugt echte `PurchaseOrder` je Lieferant** (Status „Bestellt")
   und nutzt den bestehenden Wareneingang weiter.
3. Pro Laden eine **Standard-Wochenliste**, die den Korb vorbefüllt.

## Architektur

- **Kein neuer Provider** — alles in `InventoryProvider` (wie Kundenbestellungen),
  `main.dart`-Kette unangetastet. Lazy-Cloud-Repo-Muster gewahrt.
- **Keine Cloud Function** — direkte Firestore-Writes. **Kein Composite-Index**
  (Singletons je Laden).
- Zwei org-skopierte Collections, **Doc-ID = `siteId`**:
  `organizations/{orgId}/orderCarts/{siteId}` und `.../weeklyOrderLists/{siteId}`.

## Umgesetzte Dateien

- **Modell** `lib/models/order_cart.dart`: `OrderListKind{cart,weeklyTemplate}`,
  `OrderListItem`, `SiteOrderList` (dual serialisiert, copyWith mit clear-Flags).
- **Repository** `lib/repositories/inventory_repository.dart` +
  `firestore_inventory_repository.dart`: `watchOrderCarts`,
  `watchWeeklyOrderLists`, `saveOrderList`, `deleteOrderList`.
- **Lokale Persistenz** `lib/services/database_service.dart`: Keys `order_carts`,
  `weekly_order_lists` (org-skopiert) + load/save-Paare.
- **Provider** `lib/providers/inventory_provider.dart`: Streams + Getter
  (`orderCartForSite`, `weeklyListForSite`, `cartItemCount`, `productById`) +
  Mutatoren `addToCart` (merge/erhöhen), `setCartItemQuantity`, `removeCartItem`,
  `clearCart`, `prefillCartFromWeeklyList`, `saveWeeklyList`, `checkoutCart`
  (gruppiert je Lieferant → `PurchaseOrder` ordered → leert Korb).
- **Rules** `firestore.rules`: `orderCarts` (create/update für **jedes aktive
  Org-Mitglied** — Kern des Features; delete nur Manager), `weeklyOrderLists`
  (nur `canManageInventory`).
- **UI** `lib/screens/order_cart_screen.dart` (`OrderCartTab`,
  `WeeklyOrderListEditorScreen`, Produkt-Picker, Mengen-Dialog, **Schnell-Sheet
  `showQuickAddCartSheet`** mit Laden- + Kategorie-Filter und Live-Hinzufügen) +
  `inventory_screen.dart`: 4. Tab „Bestellkorb" (Badge = Korb-Positionen),
  Schnellaktion „In den Bestellkorb" je Produkt (für **alle** Mitarbeiter),
  **„In den Warenkorb"-FAB** (FloatingActionButton, öffnet den Schnell-Sheet;
  für alle aktiven Mitarbeiter; Tab-Indizes als benannte Konstanten).

## Härtung aus dem adversarialen Review (2026-06-21)

- **checkoutCart**: gruppiert nach **live**-Lieferant; bei Teilfehler werden
  bereits erzeugte Bestellungen kompensierend gelöscht (kein Doppel beim Retry);
  Bestell-Button hat in-flight-Sperre (`_CheckoutButton`); leert nach Erfolg nur
  die **ausgelösten** Positionen (parallele Adds bleiben erhalten).
- **Rules**: `orderCarts`/`weeklyOrderLists` binden `siteId`-Feld an die Doc-ID
  (`request.resource.data.siteId == siteId`).
- **Badge**: zeigt im Mehr-Laden-Modus ohne Laden-Auswahl 0 (konsistent zum
  „Laden wählen"-Leerzustand des Tabs).

## Rechte

- Korb füllen/ändern/vorbefüllen: **alle aktiven Mitarbeiter** (`canViewInventory`).
- Checkout (Bestellung auslösen) + Standard-Wochenliste pflegen: **Manager**
  (`canManageInventory`).

## Bekannte Grenze

Cloud/hybrid-Korb-Mutationen sind „last writer wins" (Read-modify-write über den
gestreamten Stand, ganze Liste zurückgeschrieben). Für die Datenmenge bewusst
akzeptiert; bei echtem Andrang Array-Union-Transaktion im Repository ergänzen.

## Tests

- `test/order_cart_models_test.dart` (Dual-Round-Trip, copyWith, enum-Default).
- `test/order_cart_provider_test.dart` (addToCart-merge, prefill, setQuantity/
  remove, checkout-Gruppierung + Korb-Leerung, Persistenz, Cloud-Round-Trip).
- `test/inventory_provider_test.dart`: Test-Fake `_OfflineInventoryRepository` um
  die neuen Interface-Methoden ergänzt.

## Verifikation (manuell)

`flutter run --dart-define=APP_DISABLE_AUTH=true` — als `peter@example.com`:
Bestand → Produkt → „In den Bestellkorb"; Bestellkorb-Tab → Mengen anpassen. Als
`admin@demo.local`: „Standard-Wochenliste bearbeiten" anlegen, „Standard-
Wochenliste laden", „Bestellen" → je Lieferant erscheint eine Bestellung im
Bestellungen-Tab, Korb ist leer; Wareneingang wie bisher.

## Deployment

`firebase deploy --only firestore:rules` (neue `orderCarts`/`weeklyOrderLists`-
Pfade) nötig, bevor Mitarbeiter im Cloud-Modus in den Korb schreiben können.
