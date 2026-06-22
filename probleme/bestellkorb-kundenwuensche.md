# Wochen-Bestellkorb & Kundenwünsche (neues Modul)

> Teil des WorkTime-Code-Reviews. Zurück zur [Übersicht](README.md).

### 46. checkoutCart: parallel erhöhte Mengen gehen verloren (Position wird per Schlüssel ganz entfernt)

- **Schweregrad:** Niedrig  ·  **Kategorie:** race-lifecycle  ·  **Konfidenz:** medium  ·  **Status:** selbst verifiziert
- **Fundstellen:** `lib/providers/inventory_provider.dart:1497`, `lib/providers/inventory_provider.dart:1511-1533`

**Problem.** checkoutCart() liest den Korb, legt Bestellungen an und entfernt anschließend per _removeCartItems die ausgelösten Positionen über _cartItemKey (productId bzw. name|unit). Erhöht ein Mitarbeiter während des Checkouts die Menge einer bereits im Checkout befindlichen Position, hat die geänderte Position denselben Schlüssel und wird komplett mitentfernt — die zwischenzeitlich hinzugefügte Mehrmenge ist weg. Der Kommentar verspricht, parallele Adds blieben erhalten; das gilt nur für NEUE Positionen mit anderem Schlüssel, nicht für Mengenerhöhungen bestehender Positionen.

**Auswirkung.** Selten, aber realer stiller Mengenverlust im kollaborativen Korb bei gleichzeitiger Nutzung während des Checkouts (genau das Mehrnutzer-Szenario, für das das Feature gedacht ist).

**Beleg.** _removeCartItems entfernt alle items, deren _cartItemKey in removedKeys liegt — unabhängig von der aktuellen Menge.

**Empfehlung.** Beim Entfernen die zum Checkout-Zeitpunkt erfasste Menge je Position berücksichtigen (nur diese Menge abziehen statt die ganze Position zu entfernen), oder den Checkout in einer Firestore-Transaktion gegen den Live-Stand durchführen.
