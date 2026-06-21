# Scanner-Modul (Barcode/EAN)

Ausführliche Beschreibung des **Kamera-Barcode-Scanners** der Warenwirtschaft:
Artikel werden über ihren **EAN/Barcode** gefunden, **Bestand** wird gebucht,
**Preisabweichungen** werden erkannt und protokolliert, und unbekannte Artikel
lassen sich **direkt neu anlegen**. Jeder Scan gibt **akustisches, haptisches und
visuelles** Feedback. Zusätzlich gibt es einen **Inventur-Sammelmodus** mit
Differenzbericht und eine **Preis-Historie-Ansicht**.

> Stand: Juni 2026 (umgesetzt). Das Modul folgt durchgängig den bestehenden
> App-Mustern (Dual-Serialisierung, org-/standort-skopierte Collections, drei
> Speichermodi, Seam-basierte Tests, Material 3 + `AppThemeColors`) und baut auf
> der vorhandenen Warenwirtschaft auf (`Product`, `InventoryProvider`,
> `StockMovement`). Es ist **kein neuer Provider** — der Scanner ist nur ein neuer
> UI-Einstieg in den bestehenden `InventoryProvider`.

---

## 1. Zweck & fachlicher Kontext

Die App wird für zwei Geschäfte in Kiel betrieben — **Strichmännchen** (Kiosk) und
**Tabak Börse** (Tabakladen) — abgebildet als zwei **Standorte (`sites`)** innerhalb
**einer Organisation**. Bestand und Preise werden **pro Laden** geführt: ein Artikel,
der in beiden Läden existiert, ist **zwei Datensätze** (`Product` mit
unterschiedlicher `siteId`). Diese Struktur bestimmt jede Design-Entscheidung des
Scanners — insbesondere: **jeder Scan muss eindeutig einem Laden zugeordnet sein.**

Typischer Ablauf an Theke/Lager mit dem Handy:

1. Mitarbeiter öffnet den Scanner; der **aktive Laden** ist sichtbar (bei nur einem
   Laden automatisch gewählt, sonst Pflicht-Auswahl).
2. Kamera erfasst den EAN → Artikel wird gesucht.
3. **Treffer:** kurzer Erfolgs-Ton + Haptik + grüner Rahmen-Blitz, Artikel-Karte
   erscheint, Bestand kann gebucht werden (Wareneingang `+`, Abgang `−`, Inventur,
   Preis ändern, Preisverlauf).
4. **Kein Treffer:** Fehler-Ton + Haptik, Hinweis „Artikel nicht vorhanden", Button
   **„Neu anlegen"** öffnet das Anlage-Formular mit **vorbefülltem Barcode** und
   gewähltem Laden. Ist ein **deaktivierter** Artikel zu dem Code vorhanden, wird
   stattdessen **„Reaktivieren"** angeboten.
5. Bei abweichendem Preis: Bestätigungs-Sheet „VK X € → Y € übernehmen?", die
   Änderung wird in der **Preis-Historie** protokolliert.

---

## 2. Zugriff & Sichtbarkeit („nur Mobilgeräte")

### 2.1 Plattform-/Größen-Gate

Der Scanner ist **nur auf echten Mobil-Plattformen** sichtbar (Android/iOS nativ),
**nicht** auf Web oder Desktop-OS. Tablets sind **eingeschlossen** (Entscheidung des
Betreibers). Das Idiom liegt zentral in `lib/widgets/responsive_layout.dart`:

```dart
// MobileBreakpoints
static bool get isNativeMobile =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
     defaultTargetPlatform == TargetPlatform.iOS);
```

- **Bewusst ohne Breitengrenze:** Es zählt allein die Plattform, nicht die
  Fensterbreite — so erscheint der Scanner auch auf Tablets/iPads, aber nie im
  Web-Browser oder auf Desktop.
- Web/Windows/Linux/macOS haben keine sinnvolle Scan-UX; dort entfällt der Einstieg.
  Der `ScannerScreen` selbst bleibt trotzdem **defensiv** (manuelle Eingabe als
  vollwertiger Pfad, siehe §10).

### 2.2 Berechtigung

Neuer abgeleiteter Getter in `lib/models/app_user.dart`:

```dart
bool get canUseScanner => canManageInventory;
```

`canManageInventory` (= `isActive && (isAdmin || canManageShifts)`) enthält bereits
`isActive`. **Doppelgate-Regel:** `canManageInventory` gated **UI UND
Provider-Mutator** — wer scannt und Bestand/Preis schreibt, braucht dieses Recht.
Die Plattform-/Größenprüfung gehört **nicht** ins Profil-Model (reine UI-Sache).

### 2.3 Einbindung in die Navigation

Zwei Einstiege, beide mobil-only über `MobileBreakpoints.isNativeMobile`:

- **Menü-Eintrag „Scanner"** in `lib/widgets/app_nav_menu.dart` (Gruppe
  „Verwaltung", neben „Warenwirtschaft"), gegated per `showScanner &&
  canManageInventory`. Das Menü bleibt **rein präsentational**: die Shell
  (`home_screen.dart`) berechnet `showScanner` und reicht es als Flag herein.
- **Scan-FAB** im Bestand-Tab von `lib/screens/inventory_screen.dart`
  (FloatingActionButton-Cluster: Scan-FAB über dem „Artikel"-FAB, eigene
  `heroTag`s).

Beide öffnen einen **Voll-Screen** `ScannerScreen` via `Navigator.push`
(`MaterialPageRoute`), analog zu `InventoryScreen`/`CustomerOrderScreen`. **Kein**
neuer BottomNav-Tab.

---

## 3. Architektur & Seams

Der Scanner führt **zwei testbare Abstraktionen (Seams)** ein, damit der Screen
ohne echte Kamera/Hardware widget-testbar bleibt (das Repo nutzt handgeschriebene
Fakes, **kein Mockito**). Beide werden dem `ScannerScreen` **per Konstruktor**
übergeben.

```
ScannerScreen (mobil-only)
  ├── BarcodeScanner (Seam) ──► EAN-String
  ├── InventoryProvider.productByBarcode(code, siteId)   (clientseitig)
  │      ├── Treffer  ──► Artikel-Karte ──► adjustStock / Preis-Update
  │      └── kein Treffer ──► showProductDialog(initialBarcode:, defaultSiteId:)
  └── ScanFeedback (Seam) ──► success() / failure()
```

### 3.1 `BarcodeScanner` (`lib/services/barcode_scanner.dart`)

```dart
abstract interface class BarcodeScanner {
  Stream<String> get codes;        // erkannte, getrimmte EANs
  bool get isAvailable;            // false auf Windows/Linux
  bool get supportsTorch;          // nur echte Handys
  Future<void> start();
  Future<void> stop();
  Future<void> toggleTorch();
  Future<void> switchCamera();
  Widget buildPreview(BuildContext context);  // Live-Kamera (Fake: Platzhalter)
  Future<void> dispose();
}
```

- **`MobileScannerAdapter`** — echte Implementierung auf Basis von `mobile_scanner`
  (v7, Apple Vision/CameraX/ZXing). Der Controller wird **lazy** erzeugt und nur auf
  unterstützten Plattformen; auf den Formaten **EAN-13/EAN-8/UPC-A** beschränkt
  (schnellere, präzisere Scans); `autoStart: false` (Lebenszyklus steuert der
  Screen). `buildPreview` liefert die Vorschau über `MobileScanner(controller:)`.
- **`FakeBarcodeScanner`** (im Test) — schiebt EANs über einen `StreamController` in
  `codes`, `buildPreview` ist ein Platzhalter. Kein Platform-Channel im Test.

### 3.2 `ScanFeedback` (`lib/services/scan_feedback.dart`)

```dart
abstract interface class ScanFeedback {
  Future<void> success();   // OK-Ton + leichte Haptik
  Future<void> failure();   // Fehler-Ton + kräftige Haptik
  Future<void> dispose();
}
```

- **`AudioHapticFeedback`** — kurze WAV-Töne über `audioplayers`
  (`PlayerMode.lowLatency`) plus `HapticFeedback`. Sound und Haptik sind über
  `soundEnabled`/`hapticsEnabled` schaltbar; alle Audio-/Haptik-Aufrufe sind in
  `try/catch` gekapselt — Feedback darf den Scan-Flow **nie** blockieren oder werfen.
- **`NoopScanFeedback`** — tut nichts (Test **und** lautloser Betrieb).

---

## 4. Bedienung & Modi

Der `ScannerScreen` (`lib/screens/scanner_screen.dart`) zeigt von oben nach unten:

1. **Standort-Kopf** — aktiver Laden (Chip bei einem Laden, Dropdown bei mehreren).
2. **Modus-Umschalter** — `SegmentedButton`: **„Buchen"** ↔ **„Inventur"**.
3. **Kamera-Vorschau** (mit Torch-/Kamera-Wechsel-Buttons) **oder** Hinweis, falls
   keine Kamera verfügbar.
4. **Manuelle Eingabe** — EAN-Textfeld + „Suchen" (immer sichtbar, gleicher
   Lookup-Pfad).
5. **Ergebnisbereich** — je nach Modus und Treffer (Karte / Mehrfachauswahl /
   Reaktivieren / Neuanlage / Inventur-Sammelliste).

In der **AppBar** sitzt ein **Ton-/Vibrations-Schalter** (Lautsprecher-Icon).

---

## 5. Datenbank: Artikel finden & Bestand buchen

### 5.1 Barcode-Lookup — clientseitig

Es gibt **kein** neues `Product`-Feld: `barcode` (String?, EAN) ist bereits
vollständig **dual serialisiert** (`toFirestoreMap`/`toMap`/`fromFirestore`/
`fromMap`/`copyWith`+`clearBarcode`). Der Lookup läuft **rein clientseitig** über die
bereits gestreamte Artikelliste (`InventoryProvider`):

```dart
Product? productByBarcode(String barcode, {String? siteId, bool includeInactive = false});
List<Product> productsByBarcode(String barcode, {String? siteId, bool includeInactive = false});
```

- **Kein Firestore-Index, kein Repo-Zugriff** → deckt local/cloud/hybrid einheitlich
  ab und umgeht den **Lazy-Cloud-Repo-Footgun** (das Cloud-Repo darf im
  `disableAuth`/local-Modus nie angefasst werden). Für 2 Läden ideal.
- **Site-Scoping** ist Pflicht (Artikel sind standortgebunden).
- **Mehrfachtreffer:** Da `barcode` keine Eindeutigkeits-Constraint hat, liefert
  `productsByBarcode` alle Treffer; bei > 1 zeigt der Screen eine **Auswahlliste**.
- **Inaktive Artikel:** standardmäßig kein Treffer; mit `includeInactive: true`
  findbar (für die Reaktivierung statt Neuanlage).

### 5.2 Bestand buchen

Über die **vorhandene** `adjustStock`/`issueStock`-Logik — keine neue Buchungslogik:

| Aktion | Aufruf | `StockMovementType` |
|---|---|---|
| Wareneingang | `adjustStock(delta: +n, type: receipt)` | `receipt` |
| Abgang/Verkauf | `issueStock(quantity: n)` (validiert Negativbestand) | `issue` |
| Inventur (Stückzahl setzen) | `recordStocktake(countedStock:)` | `stocktake` |

`adjustProductStock` im Repo ist eine **atomare Firestore-Transaktion**: Produkt
lesen → optional Movement-Doc zur Idempotenz lesen → `currentStock += delta` →
unveränderliches `StockMovement` mit `balanceAfter`-Snapshot schreiben. Damit ist die
**Scan-Historie automatisch nachvollziehbar** (`StockMovement.createdByUid` +
`createdAt`).

### 5.3 Doppel-Scan-Schutz (zentrales Korrektheitsthema)

Zwei Strategien, beide umgesetzt:

1. **UI-Entprellung** im `ScannerScreen`: derselbe Code wird ~2 s lang ignoriert
   (kein Dauer-Wiederbeepen), und der Buchungs-Button ist während des Schreibens
   gesperrt (`_booking`-Guard).
2. **Stabile `clientMutationId`:** `adjustStock`/`issueStock` nehmen einen optionalen
   `String? clientMutationId`. Der Scanner leitet eine stabile Id aus
   `scanSessionId :: productId :: Sequenz :: Typ` ab. Auf dem **Firestore-Pfad** wird
   die Bewegung unter dieser Id adressiert → ein In-Flight-Retry bucht **nicht**
   doppelt. Eine legitime Wiederholung (z. B. „+1" zweimal) erhält eine **neue**
   Sequenz und bucht korrekt erneut.

> Hinweis: Die Daten-Idempotenz greift auf dem Firestore-Pfad. Der lokale Pfad
> (local-Modus + Hybrid-Offline-Fallback) bucht synchron/einmalig und kennt keine
> Replays; dort schützt der UI-Guard.

---

## 6. Artikel neu anlegen / reaktivieren

Der Anlage-Einstieg ist die **vorhandene** `showProductDialog(...)`, erweitert um
einen optionalen `String? initialBarcode`:

```dart
_barcode = TextEditingController(
    text: product?.barcode ?? widget.initialBarcode ?? '');
```

**Flow „kein Treffer":**

1. Fehler-Feedback, Hinweis „Artikel nicht vorhanden".
2. Button **„Neu anlegen"** → `showProductDialog(initialBarcode: scannedCode,
   defaultSiteId: aktiverLaden, ...)`. Preise laufen über das vorhandene
   `parseEuroToCents` — der Scanner braucht keine eigene Preislogik.
3. **Dublettenwarnung:** existiert der EAN im selben Laden schon, wird vor dem
   Speichern rückgefragt.
4. Ergebnis → `inventory.saveProduct(...)`; der frisch angelegte Artikel wird direkt
   per Barcode nachgeladen und angezeigt.

**Flow „deaktivierter Artikel":** statt Neuanlage wird **„Reaktivieren"**
angeboten (`saveProduct(product.copyWith(isActive: true))`).

---

## 7. Preisabweichung & Preis-Historie

### 7.1 Erkennen & Übernehmen

In der Trefferkarte öffnet der Button **„Preis"** ein Bottom-Sheet zur Eingabe des
neuen VK. `parseEuroToCents(eingabe)` → `int` Cent, **exakt** gegen
`product.sellingPriceCents` vergleichen (int-Vergleich, nie double):

- **Gleich** → Hinweis „Preis unverändert".
- **Abweichend** → Bestätigungs-Dialog „VK 1,99 € → 2,19 € übernehmen?". Bestätigt →
  `updateProductPrices(product, newSellingCents: ...)`.

### 7.2 Audit-Log `priceHistory`

`updateProductPrices(product, {newPurchaseCents, newSellingCents})` aktualisiert den
Preis **und** protokolliert jede tatsächliche Änderung als **unveränderlichen
Audit-Eintrag** — bewusst als **eigene Subcollection**, nicht als `StockMovement`
(Bewegung = Menge, nicht Preis):

```
organizations/{orgId}/products/{productId}/priceHistory/{entryId}
{ orgId, productId, field: 'selling'|'purchase', oldCents, newCents,
  changedByUid, changedAt: serverTimestamp() }
```

- **Modell** `lib/models/price_history_entry.dart` (`PriceHistoryEntry` +
  `PriceField`-Enum), voll **dual serialisiert** (camelCase/Timestamp für Firestore,
  snake_case/ISO für lokal).
- **Speichermodus-Muster** wie `adjustStock`: cloud/hybrid über das Repo
  (`addPriceHistory`), bei Hybrid-Fehler lokaler Fallback; local-Modus direkt lokal
  (Key `price_history` in `DatabaseService`, org-skopiert).
- **Lesepfad:** `InventoryProvider.priceHistoryFor(productId)` — cloud/hybrid aus der
  Firestore-Subcollection (`fetchPriceHistory`, `orderBy('changedAt')` absteigend;
  **kein Composite-Index nötig**, Single-Field wird automatisch indexiert), local aus
  dem lokalen Spiegel.

### 7.3 Preis-Historie-Ansicht

`lib/widgets/price_history_sheet.dart` → `showPriceHistorySheet(context, product:)`:
ein wiederverwendbares Bottom-Sheet, das je Eintrag „**EK/VK: alt → neu**" und das
Datum (`dd.MM.yyyy HH:mm`, `de_DE`) zeigt; Leerzustand „Noch keine Preisänderungen
erfasst.". Eingebunden als **„Preisverlauf"-Button** in der Scanner-Trefferkarte.

---

## 8. Inventur-Sammelmodus

Über den Modus-Umschalter „Inventur" wird aus dem Scanner ein **Zähl-Werkzeug**:

- **Jeder Scan zählt +1** in eine Session (`productId → Menge`); Mehrfachscan
  summiert. Pro Zeile gibt es `+`/`−`/Löschen für manuelle Korrektur.
- Jede Zeile zeigt die **Live-Differenz** zum Systembestand (gezählt − Bestand),
  farbcodiert über `AppThemeColors` (grün = mehr, gelb = weniger).
- Unbekannte oder mehrdeutige Artikel → Fehler-Feedback + Hinweis (Inventur nur für
  bekannte, eindeutige Artikel).
- **„Inventur abschliessen"** bucht alle Zählungen gebündelt via `recordStocktake`
  und zeigt einen **Differenzbericht** (Anzahl inventarisiert, davon mit Abweichung,
  Gesamtdifferenz ±Stück; nicht buchbare Artikel separat).
- Beim Verlassen des Inventurmodus mit offener Zählung erscheint ein
  **Verwerfen-Dialog**.

---

## 9. Akustisches, haptisches & visuelles Feedback

Anforderung: **zwei klar unterscheidbare Töne** (Erfolg vs. Fehler).

- **Töne:** zwei kurze WAV-Assets über `audioplayers` im Low-Latency-Modus
  (`assets/audio/scan_ok.wav` = heller Bestätigungston, `assets/audio/scan_error.wav`
  = tieferer Doppelton). `AssetSource('audio/...')` **ohne** `assets/`-Präfix
  (`AudioCache` präfixt selbst), Dateien unter `flutter.assets` deklariert.
- **Haptik:** `HapticFeedback.mediumImpact()` (Erfolg) / `HapticFeedback.vibrate()`
  (Fehler).
- **Visuell (Pflicht-Ergänzung):** grüner/gelber **Rahmen-Blitz** + SnackBar, weil
  Haptik/Sound auf manchen Geräten stumm/No-op sind. Farben **immer** aus
  `Theme.of(context).appColors` (`success`/`warning`), nie hartkodiert.
- **Einstellung:** AppBar-Toggle schaltet Ton **und** Vibration; geräteweit
  persistiert über `DatabaseService.saveLocalSetting('scanner_sound_enabled')` —
  „im Laden lautlos betreibbar".

`SystemSound` reicht bewusst **nicht** (nur ein plattformübergreifender Ton, auf Web
stumm); `just_audio` wäre Overkill.

---

## 10. Robustheit & Degradation

- **EAN-Prüfziffer** (`lib/core/ean.dart`, `isValidEanChecksum`): Codes mit
  Standardlänge (EAN-13/8, UPC-A) werden vor dem Lookup auf die Prüfziffer geprüft;
  Fehl-/Teilscans fallen früh mit eigenem Fehlerton durch. Proprietäre Hauscodes
  anderer Länge werden durchgelassen.
- **Kamera nicht verfügbar** (Windows/Linux, keine Kamera): `isAvailable == false` →
  manuelles EAN-Feld als gleichwertiger Fallback. Manuelle Eingabe ist ohnehin
  **immer** verfügbar (kaputtes Etikett, Akku, schlechtes Licht).
- **Permission verweigert / Kamera-Fehler:** klare deutsche Meldung + manuelle
  Eingabe.
- **Lifecycle/Akku/Datenschutz:** Die Kamera wird bei `AppLifecycleState.paused`
  (und beim Verlassen des Screens) **gestoppt** und bei `resumed` neu gestartet —
  sie läuft nicht dauerhaft. `dispose` gibt Seams, Subscription und Timer frei.
- **Standort-Zwang:** Bei mehreren Läden muss vor dem Scannen ein Laden gewählt
  werden; bei genau einem wird er automatisch gewählt; ohne Laden Hinweis auf die
  Teamverwaltung.

---

## 11. Pakete & Plattform-Setup

`pubspec.yaml`:

```yaml
environment:
  sdk: '>=3.7.0 <4.0.0'        # angehoben für mobile_scanner ^7 (Dart >= 3.7)
dependencies:
  mobile_scanner: ^7.2.0       # v7 = Apple Vision -> kein GTMSessionFetcher-Konflikt
  audioplayers: ^6.7.1
flutter:
  assets:
    - assets/audio/            # scan_ok.wav, scan_error.wav
```

| Plattform | Erforderlich | Status |
|---|---|---|
| **Android** | `android.permission.CAMERA` + `uses-feature camera (required=false)`; `minSdk = flutter.minSdkVersion` (≥ 21) | gesetzt |
| **iOS** | `NSCameraUsageDescription` (deutscher Text) in `Info.plist` — sonst harter Crash; Deployment-Target ≥ 12.0 (Flutter-Default) | gesetzt |
| **Web** | ZXing automatisch; braucht Secure Context (HTTPS/localhost) | Build OK, Scanner-Einstieg ausgeblendet |
| **Windows/Linux** | nicht unterstützt → manueller Fallback | abgedeckt |

> **Warum mobile_scanner v7:** v7 nutzt Apple Vision statt Google MLKit → **kein**
> `GTMSessionFetcher`-Pod-Konflikt mit `firebase_core ^3` / `cloud_functions ^5` /
> `cloud_firestore ^5`. Versionen ≤ 6.x **nicht** verwenden.

---

## 12. Sicherheit (Firestore-Rules)

Schreibpfade gehen **direkt** in Firestore (keine Cloud Function), abgesichert über
`firestore.rules`:

- `products` create/update bei `canManageInventory()` + `sameOrg` + `orgId`-Match.
- `stockMovements` create mit Feld-Allowlist + `type`-Enum-Whitelist,
  `update/delete = false` (Audit-Log).
- **Neu:** `priceHistory`-Subcollection unter `products/{productId}` — modelliert
  nach `stockMovements`: `read` (sameOrg) · `create` (sameOrg + `canManageInventory()`
  + `orgId`-Match + Feld-Allowlist `[orgId, productId, field, oldCents, newCents,
  changedByUid, changedAt]` + `field in ['purchase','selling']` + nullable
  Cent-Typprüfung + `changedByUid == request.auth.uid`) · `update, delete: if false`.
  Die Allowlist deckt sich exakt mit `PriceHistoryEntry.toFirestoreMap()`.

> Der Scanner-Schreibpfad braucht `canManageInventory` — **UI und
> Provider-Mutator** sind gegated.

---

## 13. Tests

Alles **offline**, Fakes statt echtem Firebase (kein Mockito):

- `test/scanner_foundation_test.dart` — EAN-Prüfziffer (EAN-13/8/UPC-A, gültig/
  ungültig/Müll), `MobileBreakpoints.isNativeMobile` (Plattform-Override),
  `canUseScanner`.
- `test/inventory_barcode_lookup_test.dart` — `productByBarcode`/`productsByBarcode`
  (Treffer/Miss, Site-Scoping, inaktiv, Mehrfachtreffer), `adjustStock`-Idempotenz
  mit stabiler `clientMutationId` (Cloud-Modus), `updateProductPrices` +
  `priceHistory`, `priceHistoryFor`.
- `test/scanner_screen_test.dart` — Widget-Test mit `FakeBarcodeScanner` +
  `NoopScanFeedback`: bekannter EAN → Karte; unbekannter → „Neu anlegen"; manuelle
  Eingabe; Wareneingang bucht; ungültige Prüfziffer abgewiesen; Ton-Schalter
  stummschalten + persistieren; Inventurmodus zählt + Abschluss setzt Bestand;
  Preisverlauf öffnet.
- `test/app_nav_menu_test.dart` — Scanner-Eintrag nur bei `showScanner &&
  canManageInventory`.

**Definition of Done:** `flutter analyze` sauber · `flutter test` grün (406 Cases) ·
Web-Build erfolgreich · alle UI-Texte Deutsch · `DateFormat`/`NumberFormat` mit
`'de_DE'`.

---

## 14. Betroffene / neue Dateien

**Neu:**

- `lib/screens/scanner_screen.dart` — der Scanner-Screen
- `lib/services/barcode_scanner.dart` — Seam + `MobileScannerAdapter`
- `lib/services/scan_feedback.dart` — Seam + `AudioHapticFeedback`/`NoopScanFeedback`
- `lib/core/ean.dart` — EAN-Prüfziffer
- `lib/models/price_history_entry.dart` — `PriceHistoryEntry` + `PriceField`
- `lib/widgets/price_history_sheet.dart` — Preisverlauf-Sheet
- `assets/audio/scan_ok.wav`, `assets/audio/scan_error.wav`
- Tests: `scanner_screen_test.dart`, `scanner_foundation_test.dart`,
  `inventory_barcode_lookup_test.dart`

**Geändert:**

- `pubspec.yaml` (SDK-Bump, `mobile_scanner`, `audioplayers`, Assets)
- `lib/widgets/responsive_layout.dart` (`isNativeMobile`)
- `lib/models/app_user.dart` (`canUseScanner`)
- `lib/providers/inventory_provider.dart` (`productByBarcode`/`productsByBarcode`,
  `adjustStock`/`issueStock` + `clientMutationId`, `updateProductPrices`,
  `_recordPriceChange`, `priceHistoryFor`, `priceHistory`-Feld/Laden/Persistenz)
- `lib/repositories/inventory_repository.dart` +
  `firestore_inventory_repository.dart` (`addPriceHistory`, `fetchPriceHistory`)
- `lib/services/database_service.dart` (`price_history`-Collection)
- `lib/widgets/app_nav_menu.dart` + `lib/screens/home_screen.dart` (Menü-Eintrag,
  `showScanner`)
- `lib/screens/inventory_screen.dart` (`showProductDialog(initialBarcode:)`,
  Scan-FAB)
- `firestore.rules` (priceHistory-Subcollection)
- `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`

---

## 15. Deployment & offene Punkte

**Vor dem Produktiveinsatz:**

```bash
firebase deploy --only firestore:rules    # aktiviert die priceHistory-Regel
```

Ohne Deploy werden `priceHistory`-Writes in Produktion abgelehnt. Ein
**Composite-Index ist nicht nötig** (`orderBy('changedAt')` läuft über ein
automatisches Single-Field-Index).

**Auf echter Hardware verifizieren** (geht nicht im offline/web-Dev-Modus):

```bash
flutter build apk --release --obfuscate --split-debug-info=build/symbols   # Android
flutter build ipa --release --obfuscate --split-debug-info=build/symbols   # iOS
```

Dabei prüfen: realer Kamera-Scan, die beiden Töne, Kamera-Permission-Dialog.

**Bewusst aufgeschoben (optional):** Live-`watchPriceHistory`-Stream (heute
On-Demand-Read pro Artikel), getrennte Schalter für Ton vs. Vibration (heute ein
gemeinsamer).
