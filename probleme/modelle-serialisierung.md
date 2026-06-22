# Modelle & Serialisierung

> Teil des WorkTime-Code-Reviews. Zurück zur [Übersicht](README.md).

### 45. PurchaseOrderItem.copyWith ohne clearSku-Flag für nullable sku (Inkonsistenz)

- **Schweregrad:** Niedrig  ·  **Kategorie:** maintainability  ·  **Konfidenz:** high  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/models/purchase_order.dart`, `lib/models/customer_order.dart`

**Problem.** PurchaseOrderItem.sku ist nullable (lib/models/purchase_order.dart:73), aber copyWith (Zeile 138-158) bietet kein clearSku-Flag — sku kann via copyWith nicht auf null gesetzt werden (Muster 'sku ?? this.sku' lässt nur Setzen/Behalten zu). Das parallele Model CustomerOrderItem.copyWith (lib/models/customer_order.dart:177-199) hat dagegen sehr wohl ein clearSku-Flag. Damit weicht PurchaseOrderItem vom in CLAUDE.md dokumentierten copyWith/clearX-Muster für nullable Felder ab. Aktuell wird das Leeren von sku von keinem Aufrufer benötigt (geprüft: lib/providers/inventory_provider.dart, lib/screens/purchase_order_screens.dart, order_cart_screen.dart rufen copyWith nur mit quantity/quantityReceived/addedByUid auf), daher kein aktiver Bug.

**Auswirkung.** Reine Konsistenz-/Wartungslücke: künftiger Code, der eine zuvor gesetzte Artikelnummer wieder entfernen will, kann das über copyWith nicht ausdrücken und müsste das Item neu konstruieren — leicht zu übersehen, weil das Schwester-Model das Flag bereits hat.

**Beleg.** lib/models/purchase_order.dart:138-158 (kein clearSku); lib/models/customer_order.dart:185-198 (clearSku vorhanden).

**Empfehlung.** PurchaseOrderItem.copyWith um 'bool clearSku = false' ergänzen und sku auf 'clearSku ? null : (sku ?? this.sku)' umstellen — analog zu CustomerOrderItem.copyWith.
