# Kundenbestellungen (Sonderbestellungen)

Ausführliche Beschreibung des Moduls **Kundenbestellungen**, das die Warenwirtschaft
der WorkTime-App um kundenseitige Sonderbestellungen erweitert.

> Stand: Juni 2026. Dieses Modul baut auf dem bestehenden Warenwirtschaft-Modul
> (Lieferanten, Artikel, Lieferantenbestellungen, Bestandsbewegungen) auf und
> hält dessen Muster (Dual-Serialisierung, Standort-Scoping, Cent-Preise) ein.

---

## 1. Zweck & fachlicher Kontext

Die App wird für zwei Geschäfte in Kiel betrieben (**Strichmännchen** – Kiosk,
**Tabak Börse** – Tabakladen), abgebildet als zwei **Standorte (`sites`)** innerhalb
**einer Organisation**. Neben dem internen Nachschub (Lieferantenbestellungen) gibt
es **Sonderbestellungen von Kunden**: Ein Kunde bestellt bestimmte Ware (z. B. eine
spezielle Tabaksorte, Zeitschriften, Zigarettenstangen) und holt sie zu einem
**Abholtermin** ab.

Charakteristisch:

- Manche Kunden kommen **regelmäßig** (jede Woche / jeden Monat) und holen wiederkehrend
  ihre Ware ab → **wiederkehrende Bestellungen** mit automatischem Folgetermin.
- Eine Bestellung kann **Tabak oder beliebige andere Ware** enthalten (Positionen mit
  freier Warengruppe/Kategorie).
- Mitarbeiter müssen **gewarnt** werden, wenn eine Bestellung kurz vor der Abholung
  **noch nicht vorbereitet** ist.

Das Modul deckt den kompletten Lebenszyklus ab: anlegen → vorbereiten → abholen
(oder stornieren), inkl. Filtern, Kategorien, Suche und PDF-/CSV-Export.

---

## 2. Funktionsumfang im Überblick

- Kundenbestellungen je Standort anlegen, bearbeiten, löschen.
- Positionen (Artikel, Menge, Einheit, Warengruppe, Einzelpreis) pflegen.
- Status-Workflow: **Offen → Vorbereitet → Abgeholt** (oder **Storniert**).
- **Wiederkehrende Bestellungen** (wöchentlich/monatlich) mit **Auto-Folgetermin**
  beim Abhaken „abgeholt".
- **Warnung „nicht vorbereitet"** an drei Stellen: Liste, Home-Dashboard,
  Benachrichtigungs-Center.
- Filter nach **Standort**, **Status** und **Warengruppe** + Volltext-Suche.
- **PDF-** und **CSV-Export** der (gefilterten) Bestellliste.
- Voll offline-fähig (lokaler Demo-/Dev-Modus ohne Firebase) inkl. Demodaten.

---

## 3. Datenmodell

Datei: `lib/models/customer_order.dart`. Folgt der **Zwei-Serialisierungs-Regel**
des Projekts:

| Methoden | Keys | Datum/Zahlen | Verwendung |
|---|---|---|---|
| `toFirestoreMap()` / `fromFirestore(id, map)` | camelCase | `Timestamp` / `serverTimestamp` | Firestore-Writes & Test-Seeding |
| `toMap()` / `fromMap(map)` | snake_case | ISO-8601-Strings | SharedPreferences (lokal) |

### 3.1 `CustomerOrder`

| Feld | Typ | Bedeutung |
|---|---|---|
| `id` | `String?` | Dokument-ID (separat in `fromFirestore`, in `fromMap` aus `map['id']`) |
| `orgId` | `String` | Organisation |
| `siteId` / `siteName` | `String` / `String?` | Standort (Pflicht) + denormalisierter Name |
| `customerName` | `String` | Kunde (Pflicht, keine eigene Kundenkartei) |
| `customerContact` | `String?` | Freitext-Kontakt (Telefon/E-Mail) |
| `orderNumber` | `String?` | Menschlich lesbare Nummer (`KB-2026-0007`) |
| `status` | `CustomerOrderStatus` | Offen/Vorbereitet/Abgeholt/Storniert |
| `recurrence` | `CustomerOrderRecurrence` | Einmalig/Wöchentlich/Monatlich |
| `items` | `List<CustomerOrderItem>` | Positionen (eingebettet) |
| `notes` | `String?` | Notiz |
| `pickupDate` | `DateTime?` | Abholtermin – steuert die Warnung |
| `preparedAt` | `DateTime?` | Zeitpunkt der Vorbereitung (`isPrepared = preparedAt != null`) |
| `createdByUid`, `createdAt`, `updatedAt` | – | Audit-Felder |

Abgeleitete Getter: `isPrepared`, `itemCount`, `totalQuantity`, `totalCents`,
`hasPrices`, `nextPickupDate` (nächster Termin bei wiederkehrenden Bestellungen).

`copyWith` besitzt für jedes nullable Feld ein `clearX`-Flag
(`clearSiteName`, `clearCustomerContact`, `clearOrderNumber`, `clearNotes`,
`clearPickupDate`, `clearPreparedAt`) — ein Feld lässt sich sonst nicht auf `null`
setzen.

### 3.2 `CustomerOrderItem`

Eingebettete Position (kein eigenes Dokument): `productId?`, `name`, `sku?`,
`category?` (Warengruppe, z. B. „Drehtabak", „Presse"), `unit` (Default `Stück`),
`quantity`, `unitPriceCents?`. Getter `lineTotalCents = unitPriceCents * quantity`.
Preise werden – wie im ganzen Modul – in **Cent (int)** gehalten.

### 3.3 Enums

```text
CustomerOrderStatus     .value          .label
  open                  'open'          Offen
  prepared              'prepared'      Vorbereitet
  pickedUp              'picked_up'     Abgeholt
  cancelled             'cancelled'     Storniert

CustomerOrderRecurrence .value          .label
  none                  'none'          Einmalig
  weekly                'weekly'        Wöchentlich
  monthly               'monthly'       Monatlich
```

`fromValue` hat immer einen Default-Branch (`open` bzw. `none`) und wirft nie.
`CustomerOrderRecurrence.advance(base)` schiebt ein Datum um den Rhythmus nach vorne
(`+7 Tage` bzw. `+1 Monat`, **Uhrzeit bleibt erhalten**).

---

## 4. Architektur & Speicherung

### 4.1 Bewusste Integration in die Warenwirtschaft

Kundenbestellungen wurden **nicht** als eigener Provider gebaut, sondern in den
bestehenden **`InventoryProvider`** und das **`InventoryRepository`** integriert.

**Begründung:** Sie teilen Speicher-Modi, Sitzungs-Lebenszyklus, Demo-Seeding und
den Offline-Fallback der Warenwirtschaft. Ein eigener Provider hätte ~200 Zeilen
Boilerplate dupliziert und einen weiteren Proxy in die tragende Provider-Kette in
`main.dart` eingefügt. → **`main.dart` bleibt unverändert.**

### 4.2 Datenzugriffs-Schicht

- Interface: `lib/repositories/inventory_repository.dart`
  → `watchCustomerOrders`, `saveCustomerOrder`, `deleteCustomerOrder`.
- Firestore-Implementierung: `lib/repositories/firestore_inventory_repository.dart`
  - Collection `organizations/{orgId}/customerOrders`.
  - `watchCustomerOrders` liest sortiert nach **`createdAt`** (immer via
    `serverTimestamp` gesetzt). Ein `orderBy('pickupDate')` würde Bestellungen ohne
    Abholtermin verlieren – die Sortierung nach Termin und das „bald-fällig"-Filtern
    laufen daher **clientseitig** im Provider.
  - Bestellnummern via gemeinsamem Zähler-Helfer `_allocateOrderNumber(counterId:
    'customerOrders', prefix: 'KB')` (atomare Transaktion, garantiert eindeutig).
- Fassade: `lib/services/firestore_service.dart` delegiert nur (`watch/save/delete`).

### 4.3 Provider-Logik (`lib/providers/inventory_provider.dart`)

- State `_customerOrders` + Stream-Subscription (mit `_safeNotify()`).
- Getter: `customerOrders`, `customerOrdersForSite(siteId)`, `openCustomerOrders`,
  `customerOrderCategories`, sowie das Warn-Herzstück `ordersDueSoonNotPrepared`
  (siehe §6).
- Mutatoren (Muster „Firestore zuerst, im Hybrid-Modus lokaler Fallback"):
  `saveCustomerOrder`, `deleteCustomerOrder`, `markCustomerOrderPrepared`,
  `markCustomerOrderPickedUp` (mit Auto-Folgetermin, §5), `cancelCustomerOrder`.

### 4.4 Drei Speichermodi

Wie der Rest der Warenwirtschaft:

- **cloud**: nur Firestore-Streams.
- **hybrid (Default)**: Cloud-Reads + lokaler Cache; Kundenbestellungen werden als
  *userContent* zusätzlich in SharedPreferences gespiegelt (Key `customer_orders`,
  **org-skopiert**, registriert in `lib/services/database_service.dart`).
- **local**: nur SharedPreferences (Demo-/Dev-Modus `APP_DISABLE_AUTH=true`).

---

## 5. Auto-Folgetermin (wiederkehrende Bestellungen)

Beim Abhaken **„Als abgeholt markieren"** (`markCustomerOrderPickedUp`):

1. Die aktuelle Bestellung wird auf **Abgeholt** gesetzt.
2. Ist `recurrence != none` **und** ein `pickupDate` gesetzt, wird automatisch eine
   **neue, offene** Bestellung angelegt:
   - gleicher Kunde, Standort, Kontakt, Positionen, Rhythmus, Notiz,
   - `pickupDate = recurrence.advance(altesPickupDate)` (+7 Tage / +1 Monat,
     Uhrzeit bleibt erhalten),
   - `status = Offen`, **`preparedAt = null`** (Vorbereitung startet wieder bei null),
   - neue Bestellnummer.

So muss ein Stammkunde nur einmal angelegt werden; der nächste Termin entsteht beim
Abholen von selbst.

---

## 6. Warnsystem „nicht vorbereitet"

### 6.1 Eine Quelle der Wahrheit

```dart
List<CustomerOrder> ordersDueSoonNotPrepared({int withinDays = 2, String? siteId})
```

Liefert alle Bestellungen, die **offen** und **nicht vorbereitet** sind und deren
Abholtermin **innerhalb von `withinDays` Tagen liegt oder bereits überfällig ist**
(sortiert nach Termin, dringendste zuerst). Abgeschlossene (abgeholt/storniert) und
vorbereitete Bestellungen sind ausgeschlossen, ebenso Bestellungen ohne Termin.
`dueSoonNotPreparedCount(...)` gibt die Anzahl. Standard-Vorlaufzeit: **2 Tage**.

### 6.2 Drei Anzeigeorte (alle aus diesem Getter gespeist)

1. **Bestell-Liste** (`lib/screens/customer_order_screen.dart`): farbiges Badge
   „Nicht vorbereitet" (Warnfarbe) an der betroffenen Zeile **und** ein Warn-Banner
   oben in der Liste.
2. **Home-Dashboard**: `CustomerOrderWarningBanner` – ein tippbares Warn-Banner,
   eingebettet in die Mitarbeiter- und Admin-Dashboards (sowohl V1 als auch V2). Es
   beobachtet den Provider selbst und blendet sich aus, wenn nichts ansteht oder die
   Berechtigung fehlt.
3. **Benachrichtigungs-Center** (`lib/screens/notification_screen.dart`): je Bestellung
   ein Eintrag mit Warnfarbe und Badge „Überfällig"/„Bald fällig"; für Berechtigte mit
   Aktion **„Als vorbereitet markieren"**.

Alle nutzen die semantische Warnfarbe (`appColors.warning` / `AppStatusTone.warning`),
nie hartkodierte Farben.

---

## 7. Berechtigungen

Bewusst **wiederverwendete** Getter aus `lib/models/app_user.dart` (keine neuen
Permission-Felder, kein Eingriff in Invite-Flow/Permission-Editor):

- `canViewInventory` (= aktives Mitglied) → Kundenbestellungen sehen.
- `canManageInventory` (= Admin oder Schichtverwalter) → anlegen/bearbeiten/
  vorbereiten/abholen/stornieren/löschen.

Die Gates greifen sowohl in der UI als auch in den `firestore.rules`.

---

## 8. Bedienoberfläche

- **Eigener Menüpunkt** „Kundenbestellungen" (neben „Warenwirtschaft") im
  Slide-in-Menü (`lib/widgets/app_nav_menu.dart`) sowie als Quick-Action auf dem
  Profil-Hub; verdrahtet in `lib/screens/home_screen.dart`.
- **Screen** `lib/screens/customer_order_screen.dart`:
  - Kopf mit Breadcrumb + Export-Menü (PDF/CSV).
  - Filterleiste: **Standort** (bei >1 Laden), **Status**, **Warengruppe**
    (Chips), plus Volltext-Suche über Kunde/Kontakt/Bestellnummer/Artikel.
  - Liste sortiert „offen zuerst, dann nach Abholtermin"; je Karte Kunde,
    Status-Badge, Bestellnummer, Termin, Rhythmus, Positionszahl, Summe und ggf.
    Warn-Badge. Aktionsmenü (Bearbeiten / Vorbereiten / Abholen / Stornieren /
    Löschen) je nach Berechtigung und Status.
  - Anlegen/Bearbeiten als Dialog mit Positions-Editor (eigener Dialog je Position,
    Warengruppe mit Autovervollständigung aus bekannten Kategorien).
- Die Oberfläche ist **theme-fähig**: ein Render-Pfad, der unter dem aktuellen Theme
  (V1 wie V2 / Signal-Teal-Redesign) korrekt aussieht; Status-/Warn-Elemente nutzen
  die token-basierten `AppStatusBadge`/`AppStatusBanner`.

---

## 9. Export (PDF & CSV)

- **PDF**: `PdfService.generateCustomerOrderReport(orders, siteLabel)` in
  `lib/services/pdf_service.dart` – Kopf, Kennzahlen (Gesamt/Offen/Vorbereitet/
  Nicht vorbereitet) und Tabelle (Bestellnr., Kunde, Abholung, Status, Positionen,
  Summe). Fonts: NotoSans; Datum/Beträge im Format `de_DE`.
- **CSV**: `ExportService.buildCustomerOrderCsv(...)` – **UTF-8-BOM**, `;`-Trenner
  (deutsches Excel), Feld-Escaping. Spalten: Bestellnr.; Kunde; Kontakt; Laden;
  Abholtermin; Rhythmus; Status; Vorbereitet; Positionen; Summe; Notiz.
- Auslöser: `ExportService.exportCustomerOrdersPdf/Csv(...)` (Dateiname
  `kundenbestellungen-JJJJ-MM-TT.pdf|csv`), angebunden im Export-Menü des Screens.

---

## 10. Firestore – Regeln, Indizes, Sicherheit

- **Regeln** (`firestore.rules`): Block `match /customerOrders/{orderId}` – Lesen für
  dieselbe Org, Schreiben/Löschen gated über den bestehenden Helfer
  `canManageInventory()`; `request.resource.data.orgId == orgId` erzwingt die
  Org-Zugehörigkeit. (Direkte Client-Writes, analog zu Templates – **kein** Callable.)
- **Indizes**: **keine neuen** Composite-Indizes nötig. `watchCustomerOrders`
  verwendet nur `orderBy('createdAt')` (Single-Field), das „bald fällig"-Filtern
  passiert clientseitig.
- **Kein Cloud-Function-Callable**: Kundenbestellungen haben keine
  Compliance-Validierung und keinen Bestands-Fan-out, daher schreiben sie – wie
  Templates/Teams/Abwesenheiten – direkt nach Firestore.
- **Counter**: `organizations/{orgId}/counters/customerOrders` für fortlaufende
  Nummern; von den bestehenden Counter-Regeln abgedeckt.

---

## 11. Demodaten (Offline-Modus)

`LocalDemoData.customerOrdersForOrg(...)` in `lib/core/local_demo_data.dart` seedet im
lokalen Modus drei Beispiele, darunter bewusst eine **überfällige, nicht vorbereitete**
Bestellung, damit die Warnung ohne Firebase sofort sichtbar ist (sowie eine bald
fällige und eine vorbereitete). Aufgerufen aus
`InventoryProvider._maybeSeedLocalDemo`, sofern noch keine Kundenbestellungen
vorhanden sind.

---

## 12. Tests

- `test/customer_order_models_test.dart` – Round-Trips (snake_case & camelCase),
  Enum-`fromValue`-Defaults, `copyWith`-clear-Flags, Berechnungen,
  `recurrence.advance`, `nextPickupDate`.
- `test/customer_order_service_test.dart` – `FirestoreService` mit
  `FakeFirebaseFirestore`: Speichern (inkl. Nummernvergabe), Stream, Update, Löschen,
  eindeutige Nummern.
- `test/customer_order_provider_test.dart` – lokaler Modus: Speichern/Persistenz,
  `ordersDueSoonNotPrepared`-Logik, Vorbereiten/zurücknehmen, Auto-Folgetermin,
  Kategorien, Standort-Filter.
- `test/customer_order_export_test.dart` – CSV: BOM, Kopfzeile, Escaping, Inhalte.
- `test/app_nav_menu_test.dart` – um die neue Menü-Kachel ergänzt.

Alle Tests laufen **offline** (Fakes, `SharedPreferences.setMockInitialValues` +
`DatabaseService.resetCachedPrefs`).

---

## 13. Betroffene Dateien (Übersicht)

**Neu**

- `lib/models/customer_order.dart`
- `lib/screens/customer_order_screen.dart`
- `test/customer_order_{models,service,provider,export}_test.dart`
- `docs/kundenbestellungen.md` (dieses Dokument)

**Geändert**

- `lib/repositories/inventory_repository.dart`
- `lib/repositories/firestore_inventory_repository.dart`
- `lib/providers/inventory_provider.dart`
- `lib/services/firestore_service.dart`
- `lib/services/database_service.dart`
- `lib/services/pdf_service.dart`
- `lib/services/export_service.dart`
- `lib/core/local_demo_data.dart`
- `firestore.rules`
- `lib/widgets/app_nav_menu.dart`
- `lib/screens/home_screen.dart`
- `lib/screens/home_dashboards_v2.dart`
- `lib/screens/home_screen_tabs.dart`
- `lib/screens/notification_screen.dart`
- `test/app_nav_menu_test.dart`

**Bewusst unverändert**: `lib/main.dart`, `functions/index.js`,
`lib/models/app_user.dart`, `firestore.indexes.json`.

---

## 14. Deployment-Hinweise

- Geänderte Sicherheitsregeln deployen:
  ```bash
  firebase deploy --only firestore:rules
  ```
- Keine neuen Indizes und keine Functions-Änderung nötig.
- Lokaler Test/Entwicklung wie gewohnt:
  ```bash
  flutter run --dart-define=APP_DISABLE_AUTH=true
  ```

---

## 15. Mögliche Erweiterungen (offen)

- Eigene Kundenkartei (Stammkunden mit Kontakt/Historie) statt freiem Kundennamen.
- Konfigurierbare Vorlaufzeit der Warnung (aktuell fix 2 Tage).
- Verknüpfung von Bestellpositionen mit echten Artikeln/Beständen (Reservierung).
- Push-Benachrichtigung am Abholtag.
- Widget-Test für den `CustomerOrderScreen` (Permission-Gate, Warn-Badge, Filter).
