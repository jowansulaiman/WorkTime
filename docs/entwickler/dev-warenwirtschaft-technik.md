# Warenwirtschaft (technisch)

Die Warenwirtschaft liegt in `InventoryProvider` (`lib/providers/inventory_provider.dart`) mit einer **Repository-Abstraktion** darunter.

## Repository-Abstraktion

- `lib/repositories/inventory_repository.dart` (Interface)
- `lib/repositories/firestore_inventory_repository.dart` (Firestore-Implementierung)

Der Provider löst das Cloud-Repository **lazy** auf (nie im Konstruktor) – sonst Crash im `APP_DISABLE_AUTH`/Web-Modus (siehe [Provider-Kette](article:dev-provider-kette)).

## Zentrale Modelle

- `Product` (`lib/models/product.dart`) – Artikelstamm, Barcode, Preis.
- `StockMovement` (`lib/models/stock_movement.dart`) – Bestandsbewegungen (Zu-/Abgang). Cloud-Pull aus OktoPOS schreibt mit `source:'oktopos'` (Client darf das laut Rules nicht).
- `PurchaseOrder` (`lib/models/purchase_order.dart`) + `Supplier` – Einkauf/Wareneingang. `PurchaseOrderItem.taxRatePercent` trägt die USt am Einkauf.
- `ProductBatch` (`lib/models/product_batch.dart`) – MHD-Chargen; pure `expiry_warning.dart` berechnet Warnungen.
- `CustomerOrder`/`OrderCart` – Kundenbestellungen.
- `FridgeRefill` – Kühlschrank; `fridge_refill_shortfall.dart` leitet aus Soll-Ist ab, was fehlt. Der Kühlschrank ist eine **Teilmenge** des Bestands (`fridgeStock ⊆ currentStock`).

## Auswertungen

`SalesInsightsProvider` + Core-Engines (`sales_velocity.dart`, `dead_stock.dart`, `reorder_suggestion.dart`, `assortment_analysis.dart`, `basket_analysis.dart`, `seasonal_factor.dart`) speisen die admin-only Screens (`bestand_insights_screen.dart`, `sortiment_screen.dart`). Diese sind enger gegated als die übrige Warenwirtschaft (EK-Preise/Marge).

## Speichermodus-Verhalten

Alle Mutatoren folgen dem Drei-Modi-Muster (siehe [Speichermodi](article:dev-storage-modi)) und loggen auf dem Erfolgs-Pfad in den [Audit-Sink](article:dev-audit-trail) (Rauschen wie Warenkorb/Favoriten bewusst nicht).

## Weiter

- [Kasse/POS (technisch)](article:dev-kasse-pos-technik)
- [OktoPOS-Kassenanbindung](article:dev-oktopos)
