# Scanner-Modul (Barcode/EAN) — Plan

Plan für einen **Kamera-Barcode-Scanner** in der Warenwirtschaft der WorkTime-App.
Der Scanner ist **nur auf Handys sichtbar**, findet Artikel über ihren Barcode
(EAN), bucht Bestand, erkennt Preisabweichungen, gibt **akustisches + haptisches
Feedback** (Ton für „geklappt" / „nicht geklappt") und erlaubt es, einen
**unbekannten Artikel direkt neu anzulegen**.

> Stand: Juni 2026. Dieses Dokument ist ein **Umsetzungsplan**, noch keine
> Implementierung. Es folgt den bestehenden App-Mustern (Dual-Serialisierung,
> org-/standort-skopierte Collections, drei Speichermodi, Seam-basierte Tests,
> Material 3 + `AppThemeColors`) und baut bewusst auf der **vorhandenen**
> Warenwirtschaft auf (`Product`, `InventoryProvider`, `StockMovement`).
>
> Alle Zeilennummern sind Stand der Recherche und dienen der Orientierung — vor
> dem Anfassen kurz gegenprüfen.

---

## 1. Zweck & fachlicher Kontext

Die App wird für **zwei Geschäfte in Kiel** betrieben — **Strichmännchen** (Kiosk)
und **Tabak Börse** (Tabakladen) — abgebildet als zwei **Standorte (`sites`)**
innerhalb **einer Organisation**. Bestand und Preise werden **pro Laden** geführt:
ein Artikel, der in beiden Läden existiert, ist **zwei Datensätze** (`Product` mit
unterschiedlicher `siteId`). Diese Geschäftsstruktur bestimmt jede
Design-Entscheidung des Scanners — insbesondere: **jeder Scan muss eindeutig einem
Laden zugeordnet sein.**

Typischer Ablauf an der Theke/im Lager mit dem Handy:

1. Mitarbeiter öffnet den Scanner, der **aktive Laden** ist sichtbar.
2. Kamera erfasst den EAN → Artikel wird gesucht.
3. **Treffer:** kurzer Erfolgs-Ton + Haptik, Artikel-Karte erscheint, Bestand kann
   gebucht werden (Wareneingang `+`, Abgang `−`, Inventur).
4. **Kein Treffer:** Fehler-Ton + Haptik, Hinweis „Artikel nicht vorhanden", Button
   **„Neu anlegen"** öffnet das Anlage-Formular mit **vorbefülltem Barcode** und
   gewähltem Laden.
5. Bei abweichendem Preis: Bestätigungs-Dialog „VK X € → Y € übernehmen?".

---

## 2. Sichtbarkeit: „nur für Handys"

### 2.1 Ausgangslage (wichtig — CLAUDE.md ist hier veraltet)

Die Shell unterscheidet aktuell **ausschließlich nach Fenstergröße**, nicht nach
Plattform. Der in CLAUDE.md genannte harte Breakpoint `>= 1120` existiert in dieser
Branch **nicht mehr**; die Schwellen liegen zentral in
`lib/widgets/responsive_layout.dart`:

- `MobileBreakpoints.mediumWindow = 600`, `expandedWindow = 840`
- `useNavigationRail(width) => width >= 600`, `useExpandedRailLabels(width) => width >= 840`
- `home_screen.dart:133` → `useRail = useNavigationRail(maxWidth) && maxHeight >= 600`

In `home_screen.dart`, `responsive_layout.dart`, `app_nav_menu.dart`,
`app_nav_rail.dart` gibt es **keinerlei** `kIsWeb` / `Platform` / `defaultTargetPlatform`.
Breite allein ist **kein** „Handy" — ab 600 px gilt schon ein iPad-Portrait,
Split-View oder kleines Desktop-Fenster als „Rail".

### 2.2 Robuste „nur Handy"-Definition

„Nur Handy" muss **echte Mobil-Plattform UND kleine Breite** kombinieren. Das
Plattform-Idiom existiert bereits im Repo (`main.dart:104`, `auth_provider.dart:62`):

```dart
// in lib/widgets/responsive_layout.dart (MobileBreakpoints), neu:
import 'package:flutter/foundation.dart';

static bool get isNativeMobile =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
     defaultTargetPlatform == TargetPlatform.iOS);

// im Screen/Build:
final showScanner = MobileBreakpoints.isNativeMobile &&
    MediaQuery.sizeOf(context).width < MobileBreakpoints.mediumWindow; // < 600
```

- Schließt **Web-Desktop** (`kIsWeb`), **Desktop-OS** und **große Tablets** (≥ 600)
  aus. Wenn iPads/große Android-Tablets den Scanner auch nutzen sollen → nur
  `isNativeMobile` prüfen, ohne den `< 600`-Teil.
- Sichtbarkeit **im `build()`/`LayoutBuilder` auswerten** (Rotation/Resize live),
  nicht in `initState` cachen.

### 2.3 Einbindung in die Navigation

Inventory/Kundenbestellungen sind heute **keine Tabs**, sondern Einträge im
Slide-in-Menü (`app_nav_menu.dart`), die per `_pushFromMenu(...)` als
`Navigator.push(MaterialPageRoute(...))` geöffnet werden (`home_screen.dart:854, 827`).

**Empfehlung (minimal-invasiv):** Scanner ebenso als
- **Menü-Eintrag** „Scanner" in `app_nav_menu.dart` (Gruppe „Verwaltung", neben
  „Waren"), gegated per `canManageInventory` **und** per durchgereichtem
  `bool showScanner` (Plattform/Größe, von der Shell berechnet — `AppNavMenu`
  bleibt rein präsentational), **plus**
- ein **Scan-FAB / Aktion** direkt im Bestand-Tab des `inventory_screen.dart`,
  ebenfalls nur wenn `showScanner`.

Geöffnet wird ein **eigener Voll-Screen** `ScannerScreen` via `Navigator.push`
(analog `PurchaseOrderEditorScreen`).

**Alternative (invasiver):** echter BottomNav-Tab über `_ShellDestinationId.scanner`
+ `_buildDestinations`. Erfordert, die Plattform-/Größenflags als Parameter in
`_buildDestinations` zu reichen (die Methode hat keinen `BuildContext`), Adressierung
**immer** per `destinations.indexWhere(... == _ShellDestinationId.scanner)`, nie per
Literal-Index (CLAUDE.md-Kopplung 7). Da `useRail` bei `< 600` ohnehin `false` ist,
erschiene der Tab automatisch nur in der BottomNav — die Build-Bedingung trotzdem so
wählen, dass der Tab im Rail-Modus gar nicht erst entsteht.

> **Empfehlung:** Menü-Eintrag + FAB. Kein neuer Tab im MVP.

### 2.4 Berechtigung

Neuer abgeleiteter Getter in `lib/models/app_user.dart` (bei den anderen, ~Z. 328):

```dart
bool get canUseScanner => isActive && canManageInventory;
```

Plattform-/Größenprüfung gehört **nicht** ins Profil-Model — die ist UI-Sache.
**Doppelgate-Regel (CLAUDE.md):** `canUseScanner`/`canManageInventory` gated **UI
UND Provider-Mutator** — wer scannt und Bestand/Preis schreibt, braucht
`canManageInventory`. Reine Betrachter (`canViewInventory => isActive`) dürfen
höchstens nachschlagen.

---

## 3. Architektur-Überblick & Seams

Der Scanner führt **zwei neue, testbare Abstraktionen (Seams)** ein, damit der Screen
ohne echte Kamera/Hardware widget-testbar bleibt (das Repo nutzt handgeschriebene
Fakes, **kein Mockito**):

```dart
// Kamera/Barcode-Quelle
abstract interface class BarcodeScanner {
  Stream<String> get codes;          // erkannte EANs
  Future<void> start();
  Future<void> stop();
  bool get isAvailable;              // false auf Windows/Linux/Web-ohne-Kamera
}
// Implementierung: MobileScannerAdapter (mobile_scanner) + FakeBarcodeScanner (Test)

// Akustisches/haptisches Feedback
abstract interface class ScanFeedback {
  Future<void> success();            // OK-Ton + leichte Haptik
  Future<void> failure();            // Fehler-Ton + kräftige Haptik
}
// Implementierung: AudioHapticFeedback + NoopScanFeedback (Test)
```

Beide werden dem `ScannerScreen` **per Konstruktor** übergeben (Muster wie
`InventoryProvider(inventoryRepository:, cloudFunctionInvoker:)`). Die
Geschäftslogik (Lookup, Buchung, Preis-Update) bleibt im **bestehenden**
`InventoryProvider` — der Scanner ist nur ein neuer UI-Einstieg, **kein neuer
Provider** (keine Änderung an der `main.dart`-Provider-Kette nötig).

```
ScannerScreen (mobile-only)
  ├── BarcodeScanner (Seam) ──► EAN-String
  ├── InventoryProvider.productByBarcode(code, siteId)   (NEU, clientseitig)
  │      ├── Treffer  ──► Artikel-Karte ──► adjustStock / Preis-Update
  │      └── kein Treffer ──► showProductDialog(initialBarcode:, defaultSiteId:)
  └── ScanFeedback (Seam) ──► success() / failure()
```

---

## 4. Wie die Waren gespeichert werden (Datenmodell)

Die Datenschicht ist **weitgehend bereit** — `Product` trägt bereits ein
`barcode`-Feld, vollständig **dual serialisiert**:

| Stelle | Datei:Zeile | Format |
|---|---|---|
| `barcode`-Feld | `lib/models/product.dart:49` | `String?` (EAN), nullable |
| `toFirestoreMap` | `product.dart:162` | camelCase `barcode`, `_trimmedOrNull` (leer→null) |
| `toMap` | `product.dart:187` | snake_case `barcode` (roh, **kein** trim) |
| `fromFirestore` / `fromMap` | `product.dart:108 / 135` | lesen beide `barcode` |
| `copyWith` | `product.dart:223, 240` | `clearBarcode`-Flag vorhanden |

➡️ **Kein neues Product-Feld nötig.** Der Scanner kann gefundene/neue Barcodes
direkt über das vorhandene `saveProduct` (set/merge, idempotent über Doc-ID)
schreiben.

**Wichtige Eigenschaften:**

- `Product.siteId` ist **Pflicht** → Scan ist immer laden-gebunden.
- Preise sind `int?` in **Cent** (`purchasePriceCents`, `sellingPriceCents`).
- `barcode` hat **keine Eindeutigkeits-Constraint** (weder Model, Provider, Rules
  noch Index). Ein Barcode kann theoretisch mehrfach / je Laden vorkommen → Lookup
  **muss** site-scoped sein und „mehrere Treffer" behandeln (siehe §5.4).
- Kleiner Footgun der Zwei-Serialisierungs-Regel: `toFirestoreMap` trimmt `barcode`
  zu `null`, `toMap` nicht. Liefert der Scanner führende/abschließende Leerzeichen,
  vor dem Speichern **selbst `.trim()`** und leere/0-Strings verwerfen.

---

## 5. Datenbank: Artikel finden, Bestand buchen

### 5.1 Barcode-Lookup — clientseitig (empfohlen für MVP)

Es gibt **heute keine** `findProductByBarcode`-Methode. Die Produktsuche ist ein
clientseitiges `contains()` über die bereits gestreamte Liste; ein Code-Kommentar
(`inventory_screen.dart:465–471`) dokumentiert bewusst, dass eine indizierte Query
erst bei echtem Hochfrequenz-POS-Scan lohnt.

`watchProducts` streamt die **gesamte** `products`-Collection einer Org
(`firestore_inventory_repository.dart:68`, `orderBy('nameLower')`, **kein** `where`);
der Provider hält alles in `_products`. Für **2 Läden** ist clientseitiges Filtern
ideal: kein Index, keine Latenz, deckt **local/cloud/hybrid einheitlich** ab und
umgeht den Lazy-Cloud-Repo-Footgun (das Cloud-Repo darf im `disableAuth`/local-Modus
nicht angefasst werden — `inventory_provider.dart:46`).

```dart
// NEU in InventoryProvider — rein clientseitig, kein Repo, kein Index:
Product? productByBarcode(String barcode, {String? siteId}) {
  final code = barcode.trim();
  if (code.isEmpty) return null;
  return _products.firstWhereOrNull((p) =>
      p.barcode?.trim() == code &&
      (siteId == null || p.siteId == siteId) &&
      p.isActive);
}
List<Product> productsByBarcode(String barcode, {String? siteId}) { ... } // für „mehrere Treffer"
```

### 5.2 Eskalation auf Server-Query (nur falls je nötig)

Erst bei sehr großem Bestand / echtem POS:
`findProductByBarcode` in `InventoryRepository` **und** `FirestoreInventoryRepository`
ergänzen: `where('barcode', isEqualTo: code).where('siteId', isEqualTo: siteId).limit(1)`.

- **Zwei Gleichheitsfilter ohne `orderBy` brauchen KEINEN Composite-Index** (Firestore
  Single-Field-Merge-Join). Index in `firestore.indexes.json` erst nötig, sobald ein
  `orderBy`/Range dazukommt → dann `(siteId ASC, barcode ASC)`.
- ⚠️ Fehlender Index wirft **erst zur Laufzeit** (`failed-precondition` mit Index-Link),
  nicht im Build — und `FakeFirebaseFirestore` ignoriert Indizes (in Tests unsichtbar).
- ⚠️ Eine neue Repo-Methode braucht **zusätzlich einen lokalen Pfad im Provider**
  (es gibt **kein** Local-Repository), sonst funktioniert sie offline nicht.

### 5.3 Bestand buchen beim Scannen

Über die **vorhandene** `adjustStock`-Methode (`inventory_provider.dart:559`) — keine
neue Buchungslogik:

| Aktion | Aufruf | `StockMovementType` |
|---|---|---|
| Wareneingang | `adjustStock(productId:, delta: +n, type: receipt)` | `receipt` |
| Verkauf/Abgang | `adjustStock(productId:, delta: -n, type: issue)` | `issue` |
| Korrektur | `adjustStock(... type: adjustment)` | `adjustment` |
| Inventur (Stückzahl setzen) | `recordStocktake(product:, countedStock:)` | `stocktake` |

`adjustProductStock` im Repo ist eine **atomare Firestore-Transaktion**
(`firestore_inventory_repository.dart:151`): Produkt lesen → optional Movement-Doc
zur Idempotenz lesen → `currentStock += delta` → unveränderliches `StockMovement` mit
`balanceAfter`-Snapshot schreiben. `StockMovement` ist ein **Audit-Log** (Rules:
`update/delete=false`, strikte Feld-Allowlist) → die Scan-Historie ist damit
automatisch nachvollziehbar.

### 5.4 ⚠️ Doppel-Scan-Schutz (das zentrale Korrektheitsproblem)

`adjustStock` erzeugt **pro Aufruf eine frische `_uuid.v4()`** als `clientMutationId`
(`inventory_provider.dart:571`). Die Idempotenz schützt damit nur den **In-Flight-Retry
einer Operation**, **nicht** das versehentliche Doppel-Scannen desselben Codes —
genau der Fall, der beim Scannen typisch ist.

**Zwei Strategien (beide umsetzen empfohlen):**

1. **UI-Entprellung** im `ScannerScreen`: nach erkanntem Code für ~1,5 s gesperrt
   bzw. „gleicher Code in Folge" ignorieren; Buchungs-Button während des Schreibens
   disablen. Bei Dauer-Scan-Modus: gleicher EAN erst nach Cooldown erneut zählen.
2. **Stabile `clientMutationId`**: `adjustStock` um einen optionalen Parameter
   `String? clientMutationId` erweitern (Signatur-Erweiterung), den der Scanner aus
   `scanSessionId + productId + Sequenz` ableitet → echter Schutz auf Datenebene.

> Diese Entprellung **vor** dem Bau des Scan-Flows einplanen, sonst bucht jeder
> Doppel-Tap/Doppel-Scan doppelt.

---

## 6. Falls sich der Preis ändert

### 6.1 Ausgangslage: keine Preis-Historie

`Product` speichert nur die **Momentanwerte** `purchasePriceCents`/`sellingPriceCents`
plus `updatedAt`. `saveProduct` macht ein **merge-set ohne Diff/Audit**
(`firestore_inventory_repository.dart:132`) und schreibt **kein** Movement →
Preisänderungen sind heute **spurlos**.

### 6.2 Preisabweichung beim Scannen erkennen & übernehmen

1. Beim Scannen optional einen Preis erfassen (manuell, oder vom Etikett/POS).
2. `parseEuroToCents(eingabe)` (`inventory_screen.dart:29`) → `int` Cent, **exakt**
   gegen `product.sellingPriceCents` vergleichen (int-Vergleich, nie double).
3. Bei Abweichung **Bestätigungs-Sheet**: „VK 1,99 € → 2,19 € übernehmen?".
4. Bestätigt → `saveProduct(product.copyWith(sellingPriceCents: neu))`
   (Cent-Helfer und `clearX`-Flags sind vorhanden, `product.dart:245`).

### 6.3 Preis-Historie protokollieren (empfohlen)

**Empfehlung: eigene `priceHistory`-Subcollection** unter
`organizations/{orgId}/products/{productId}/priceHistory`:

```
{ productId, field: 'selling'|'purchase', oldCents, newCents,
  changedByUid, changedAt: serverTimestamp() }
```

**Warum so:**
- Spiegelt das bestehende **unveränderliche Audit-Log-Muster** der `stockMovements`.
- Hält `StockMovement` **semantisch sauber** (Bewegung = Menge, nicht Preis).
- Verlangt **keine** Änderung der strikten `stockMovements`-Feld-Allowlist in den Rules.

**Bewusst abgelehnt:**
- ❌ Neuer `StockMovementType` `price_change` — `quantityDelta=0`/`balanceAfter`
  wären semantisch falsch; `fromValue`-Default mappt Unbekanntes still auf
  `adjustment`; zwänge Änderungen an `.value`/`label`/`fromValue` **und** Rules.
- ❌ Nur `updatedAt` + Freitext-`reason` — keine maschinenlesbare Alt/Neu-Spur, und
  bei reiner Preisänderung entsteht ohnehin kein Movement.

**Umsetzungs-Hinweise:**
- Diff braucht den **alten** Wert → idealerweise **in derselben Transaktion** wie das
  Produkt-Update lesen+schreiben (analog `adjustProductStock`), damit Atomizität
  gewahrt bleibt. `saveProduct` kennt den alten Preis heute nicht (merge ohne Read).
- **Hybrid/local-Pfad mitziehen** (`_applyLocalStockChange`-Analogon), sonst entstehen
  offline/`disableAuth` keine History-Einträge.
- Neue **Firestore-Rules-Regel** für die Subcollection: `canManageInventory` +
  `sameOrg` + `orgId`-Match + Feld-Allowlist + `update/delete=false`
  (Vorlage: `stockMovements`-Block `firestore.rules:746–766`).
- Volle **Dual-Serialisierung** + `toMap`/`fromMap`-Round-Trip + lokaler Storage-Key.

> Offen: Historie für **beide** Preise (EK + VK) oder nur VK für den Scan-Use-Case?
> Empfehlung: beide (gleiche Struktur, vernachlässigbarer Mehraufwand).

---

## 7. Akustisches & haptisches Feedback („geklappt" / „nicht geklappt")

Anforderung: **zwei klar unterscheidbare Töne** (Erfolg vs. Fehler). Es gibt heute
**keinerlei** Sound-/Haptik-Code im Repo.

### 7.1 Lösung

`SystemSound` (Bordmittel) liefert **nur einen** plattformübergreifenden Ton
(`click`) und ist auf **Web stumm** → reicht **nicht** für zwei Töne. Daher:

- **Töne:** zwei kurze WAV-Assets über **`audioplayers ^6.7.1`** im
  `PlayerMode.lowLatency`:
  - `assets/audio/scan_ok.wav` (kurzer heller Bestätigungston)
  - `assets/audio/scan_error.wav` (tieferer/doppelter Fehlerton)
  - ⚠️ `AssetSource('audio/scan_ok.wav')` — Pfad **ohne** `assets/`-Präfix
    (`AudioCache` präfixt selbst), Dateien trotzdem unter `flutter.assets` deklarieren.
- **Haptik (zusätzlich, Bordmittel `flutter/services`, ohne Dependency):**
  - Erfolg: `HapticFeedback.mediumImpact()` / `heavyImpact()`
  - Fehler: `HapticFeedback.vibrate()` (länger/deutlicher)
- **Visuell (Pflicht-Ergänzung):** grüner/gelber Rahmen-Blitz + SnackBar, weil
  Haptik/Sound auf Web/Desktop No-op/stumm sind. Farben **immer** aus
  `Theme.of(context).appColors` (`appColors.success` / `appColors.warning`), nie
  hartkodiert (`theme_extensions.dart:140`).

`just_audio` ist Overkill (Playlists/Streaming, schwerere Deps) — **nicht** verwenden.

### 7.2 Hinter Seam + Einstellung

`ScanFeedback`-Seam (siehe §3) mit `NoopScanFeedback` im Test (sonst echte
Platform-Channel-Calls/Hänger in Widget-Tests). Sinnvoll: eine **Einstellung**
„Scan-Ton an/aus" + „Vibration an/aus" (z. B. via `SharedPreferences`/ThemeProvider-
Settings-Muster), damit es im Laden lautlos betrieben werden kann.

---

## 8. Pakete & Plattform-Setup

### 8.1 Barcode-Scanner: `mobile_scanner ^7.2.0`

Klare Empfehlung — reines Plattform-Backend (CameraX/Android, **Apple Vision**/iOS+macOS,
ZXing/Web), keine separate `camera`-Abhängigkeit, unterstützt **EAN-13/EAN-8/UPC-A**
direkt. Controller auf `ean13`, `ean8` (+ ggf. `upcA`) beschränken → schnellere,
präzisere Scans.

- ✅ **Firebase-konfliktfrei:** v7 nutzt Apple Vision statt Google MLKit → **kein**
  `GTMSessionFetcher`-Pod-Konflikt mit `firebase_core ^3` / `cloud_functions ^5` /
  `cloud_firestore ^5`. **Versionen ≤ 6.x NICHT verwenden** (MLKit-Konflikt auf iOS).
- ⚠️ **SDK-Bump zwingend:** `mobile_scanner 7.x` verlangt **Dart ≥ 3.7 / Flutter ≥ 3.29**.
  In `pubspec.yaml` `environment.sdk` von `>=3.0.0 <4.0.0` auf **`>=3.7.0 <4.0.0`**
  anheben (installierte Toolchain erfüllt das). Ohne Bump scheitert `flutter pub get`.
- ⚠️ v7 hat Breaking Changes ggü. v6 (Controller jetzt `required`, `errorBuilder`/
  `placeholderBuilder` entfernt) → bei Tutorials auf v7-konformen Code achten.

### 8.2 Plattform-Konfiguration

| Plattform | Erforderlich |
|---|---|
| **Android** | `android.permission.CAMERA` in `AndroidManifest.xml`; `minSdkVersion ≥ 21`; ggf. AGP/Java 17 prüfen (CameraX) |
| **iOS** | `NSCameraUsageDescription` (deutscher Text!) in `ios/Runner/Info.plist` — **sonst harter Crash** beim ersten Kamera-Zugriff; Deployment Target ≥ 12.0 |
| **Web** | ZXing wird seit v5 automatisch geladen (kein `index.html`-Eintrag); braucht **secure context** (HTTPS/localhost) für `getUserMedia` |
| **Desktop** | macOS ok; **Windows/Linux NICHT unterstützt** → Fallback Pflicht |

Beispiel iOS-Text: *„WorkTime nutzt die Kamera zum Scannen von Artikel-Barcodes (EAN)."*

### 8.3 Laufzeit-Realität & Degradation

Im Dev-Modus (`APP_DISABLE_AUTH=true`) wird oft auf Desktop/Web entwickelt. Da der
Scanner ohnehin **mobile-only sichtbar** ist (§2), greift das Kamera-UI dort nicht —
aber der `ScannerScreen` muss **defensiv** sein:

- `BarcodeScanner.isAvailable == false` (Windows/Linux, keine Kamera, Web ohne
  Permission) → **manuelles EAN-`TextField`** als Fallback anbieten (gleicher
  Lookup-Pfad). Manuelle Eingabe ohnehin **immer** als Alternative zeigen
  (kaputter Barcode, Akku, schlechtes Licht).
- Kamera-Permission verweigert → klare deutsche Meldung + „Einstellungen öffnen" +
  manuelle Eingabe.

### 8.4 `pubspec.yaml`-Diff (geplant)

```yaml
environment:
  sdk: '>=3.7.0 <4.0.0'        # war: >=3.0.0
dependencies:
  mobile_scanner: ^7.2.0
  audioplayers: ^6.7.1         # nur wenn echte Töne gewünscht (Empfehlung: ja)
flutter:
  assets:
    - assets/audio/            # scan_ok.wav, scan_error.wav
```

---

## 9. Artikel neu anlegen, wenn nicht vorhanden

Der Anlage-Einstiegspunkt ist **bereits vorhanden** und fast unverändert nutzbar:
`showProductDialog(context, {required sites, required suppliers, Product? product, String? defaultSiteId})`
(`inventory_screen.dart:959`). Er enthält schon ein **Barcode-Feld**
(`inventory_screen.dart:1132`) und kennt `defaultSiteId`.

**Minimaler Eingriff:** optionalen Parameter `String? initialBarcode` ergänzen und
an `_ProductDialog` durchreichen:

```dart
_barcode = TextEditingController(text: product?.barcode ?? initialBarcode ?? '');
```

**Flow „kein Treffer":**
1. Fehler-Feedback (§7), Hinweis „Artikel nicht vorhanden".
2. Button **„Neu anlegen"** → `showProductDialog(initialBarcode: scannedCode, defaultSiteId: aktiverLaden, suppliers: inventory.activeSuppliers, sites: ...)`.
3. Ergebnis → bestehendes `inventory.saveProduct(result)` (keine
   `createFromBarcode`-Methode nötig).

Preise im Dialog werden über `parseEuroToCents`/`_centsToEuroInput` erledigt — der
Scanner braucht **keine eigene Preislogik**.

> **Hinweis UX-Konvention:** Der Inventory-Anlage-Flow ist ein **`AlertDialog`** —
> die **Ausnahme** im Repo (App-Konvention ist `showModalBottomSheet(showDragHandle:
> true, isScrollControlled: true, useSafeArea: true)`, siehe `notification_screen.dart:21`).
> Optional bei Gelegenheit auf Bottom-Sheet umstellen; für den Scanner-MVP ist der
> Dialog ausreichend.

---

## 10. Standort-Kontext (kritisch)

Da Artikel **standortgebunden** sind, **muss** beim Scannen klar sein, welcher Laden
gemeint ist — sonst landet ein Scan im falschen Bestand.

- Laden kommt aus `TeamProvider.sites` (`team_provider.dart:72`); im Inventory-Screen
  hält `_selectedSiteId` (`inventory_screen.dart:92`) den aktiven Filter.
- Scanner zeigt den **aktiven Laden prominent** an (Header/Chip).
- Ist `_selectedSiteId == null` („Alle Läden") **und** `sites.length > 1` → den
  Nutzer **vor dem Scannen** einen Laden wählen lassen (Pflicht). Bei `sites.length == 1`
  automatisch dieser; bei `sites.isEmpty` dieselbe Guard wie `_addProduct`
  (`inventory_screen.dart:265`).
- Sowohl der Lookup als auch `defaultSiteId` der Neuanlage nutzen denselben Laden.

---

## 11. Zusätzliche Aspekte (ggf. vergessen)

Bewusst ergänzt, weil sie den Scanner praxistauglich/robust machen:

1. **Mengeneingabe statt nur ±1:** nach Scan ein `+`/`−`/Anzahl-Feld, damit
   Wareneingänge mit Stückzahl gebucht werden (nicht nur 1 pro Scan).
2. **Dauer-Scan-Modus** (kontinuierlich) vs. **Einzel-Scan** — mit Cooldown gegen
   Doppelzählung (§5.4). Für Inventur ggf. Liste „gescannt: N×Artikel".
3. **EAN-Prüfziffer validieren** (EAN-13/-8 Checksumme) vor Lookup → Fehlscans/
   Teilscans früh als „ungültig" abfangen (eigener Fehlerton).
4. **„Mehrere Treffer"**: weil `barcode` nicht eindeutig ist → bei >1 Treffer
   Auswahl-Liste statt stillem `firstWhere`.
5. **Inaktive Artikel** (`isActive == false`): als Treffer behandeln, aber kenntlich
   machen / Reaktivierung anbieten, statt „nicht gefunden".
6. **Inventurmodus:** Scan → Stückzahl erfassen → `recordStocktake`; am Ende
   Differenzbericht. (Nutzt vorhandenes `recordStocktake`.)
7. **Taschenlampe/Torch** + **Autofokus**-Tap, **Kamera wechseln** (front/back) —
   `mobile_scanner` bietet das; UX im schlecht beleuchteten Lager wichtig.
8. **Manuelle Eingabe** als gleichwertiger Pfad (kaputtes Etikett, Akku, kein Zugriff).
9. **Kamera-Permission-Handling**: Erstanfrage, „abgelehnt"-Zustand, Deep-Link zu
   System-Einstellungen, alles auf Deutsch.
10. **Offline-Verhalten:** im `hybrid`-Modus funktioniert Lookup über den
    in-memory-Cache; Buchungen fallen lokal zurück (`_applyLocalStockChange`) und
    syncen später — dem Nutzer Offline-Status anzeigen.
11. **Datenschutz/Akku/Lifecycle:** Kamera bei `AppLifecycleState.paused` / beim
    Verlassen des Screens **stoppen** (`BarcodeScanner.stop()`), nicht dauerhaft laufen.
12. **Audit/Wer-hat-gescannt:** ergibt sich aus `StockMovement.createdByUid` +
    `createdAt` (kein Extra-Feld nötig). Optional `reason: 'Scan'` setzen.
13. **Accessibility:** ausreichende Trefferflächen, Sprachausgabe-Labels, Feedback
    auch visuell (nicht nur Ton/Haptik).
14. **Lautstärke/Stumm-Schalter** respektieren bzw. eigene Ton-Einstellung (§7.2).
15. **Barcode-Eindeutigkeit (Datenqualität):** beim Neuanlegen prüfen, ob der EAN im
    selben Laden schon existiert (clientseitig), um Dubletten zu vermeiden — eine echte
    DB-Constraint gibt es in Firestore nur über eine separate Lookup-Doc-Collection.

---

## 12. Berechtigungen & Sicherheit (Firestore-Rules)

- Schreibpfade gehen **direkt** in Firestore (keine Cloud Function), abgesichert
  **nur** durch `firestore.rules`: `products` create/update bei `canManageInventory`
  + `sameOrg` + `orgId`-Match (`firestore.rules:707`); `stockMovements` create mit
  Feld-Allowlist + `type`-Enum-Whitelist, `update/delete=false` (`firestore.rules:746`).
- Der Scanner-Schreibpfad braucht `canManageInventory` (UI **und** Provider gaten).
- Neue `priceHistory`-Subcollection → **eigene Rules-Regel** (§6.3).
- ⚠️ Eine neue `stockMovements`-/`priceHistory`-Property scheitert sonst an der
  Allowlist — Rules sind hier load-bearing.

---

## 13. Kritische Kopplungen (CLAUDE.md „Wenn du X änderst…")

- **Neues Product-Feld** (falls je nötig, z. B. MwSt): **6 Stellen**
  (`toFirestoreMap`, `fromFirestore`, `toMap`, `fromMap`, `copyWith` + `clearX`).
- **Neue Repo-Methode** (`findProductByBarcode`): zusätzlich **lokaler Pfad im
  Provider** (kein Local-Repo) + ggf. Index in `firestore.indexes.json`.
- **Neuer Firestore-Write-Pfad** (`priceHistory`): Rules **und** Payload-Format
  (direkt = camelCase) abgleichen.
- **Cloud-Repo niemals im Provider-Konstruktor** auflösen (lazy, `inventory_provider.dart:46`)
  — sonst rote Seiten im `disableAuth`/Web-Modus.
- **Provider- vs. Repo-Name:** `InventoryProvider.adjustStock` ≠
  `Repository.adjustProductStock`; `saveProduct` gibt `Future<void>` (keine ID).
- **`adjustStock`-Signatur** ggf. um `clientMutationId` erweitern (Doppel-Scan, §5.4).

---

## 14. Implementierungs-Schritte (Strangler, inkrementell)

**Phase 0 — Fundament (klein, isoliert testbar)**
1. `pubspec.yaml`: SDK-Bump `>=3.7.0`, `mobile_scanner ^7.2.0`, `audioplayers ^6.7.1`,
   `assets/audio/`.
2. Plattform-Config: Android-Manifest (CAMERA, minSdk), iOS-Info.plist
   (`NSCameraUsageDescription`, Deployment Target), `flutter pub get` + Build je Ziel.
3. `MobileBreakpoints.isNativeMobile` + `canUseScanner`-Getter (+ Unit/Widget-Tests).
4. Seams `BarcodeScanner` (+ `MobileScannerAdapter`, `FakeBarcodeScanner`) und
   `ScanFeedback` (+ `AudioHapticFeedback`, `NoopScanFeedback`).

**Phase 1 — Lookup & Anzeige (read-only)**
5. `InventoryProvider.productByBarcode/productsByBarcode` (clientseitig) + Unit-Tests.
6. `ScannerScreen` (mobile-only): Kamera + manueller Fallback, Standort-Anzeige/-Zwang,
   Treffer-Karte, Feedback-Töne. Einbindung via Menü-Eintrag + FAB.

**Phase 2 — Schreiben**
7. Bestandsbuchung (`adjustStock`, receipt/issue/adjustment) inkl. **Doppel-Scan-Schutz**
   (UI-Debounce + optional stabile `clientMutationId`).
8. „Neu anlegen": `showProductDialog(initialBarcode:)` + Dublettenwarnung.

**Phase 3 — Preis**
9. Preisabweichungs-Erkennung + Bestätigungs-Sheet.
10. `priceHistory`-Subcollection (Model, Dual-Serialisierung, Rules, lokaler Pfad,
    Transaktion) + Tests.

**Phase 4 — Komfort (optional)**
11. Inventurmodus, Dauer-Scan, Torch/Autofokus, EAN-Prüfziffer, Ton-Einstellung,
    Lifecycle-Stop, Accessibility-Feinschliff.

---

## 15. Teststrategie

Alles **offline**, Fakes statt echtem Firebase (kein Mockito):

- **Provider-Unit** (`test/inventory_provider_test.dart`-Muster): `productByBarcode`
  Treffer/Miss, **Site-Scoping**, inaktive Artikel, mehrere Treffer. `adjustStock`
  Idempotenz mit stabiler `clientMutationId`.
- **Widget** (`test/contacts_screen_test.dart`/`test/inventory_screen_test.dart`-Muster):
  `ScannerScreen` mit `FakeBarcodeScanner` (liefert bekannten EAN → Karte; unbekannten
  → Anlage-Dialog mit **vorbefülltem Barcode** + korrektem Laden), `NoopScanFeedback`.
  Setup: `tester.view.physicalSize`, `AppTheme.resolveLight(useV2: true)`,
  `SharedPreferences.setMockInitialValues({}) + DatabaseService.resetCachedPrefs()`,
  `initializeDateFormatting('de_DE')`.
- **Sichtbarkeit**: `debugDefaultTargetPlatformOverride` (android → sichtbar; macOS/
  kIsWeb → unsichtbar) + Breiten-Variation (≥ 600 → unsichtbar). Override im
  `tearDown` zurücksetzen.
- **Hinweise:** `FakeFirebaseFirestore` liefert Zahlen als **`double`** → keine
  int-Gleichheit auf Preis-/Bestandsfeldern asserten. Compliance/Movements auf `.code`
  bzw. `.type` prüfen, nicht auf Message. Kamera/Haptik/Sound **nur** über Seams (sonst
  Platform-Channel-Hänger).

**Quality Gates (Definition of Done):** `flutter analyze` sauber · `flutter test`
grün · Build je Ziel (Android/iOS/Web) erfolgreich · alle deutschen UI-Texte ·
`DateFormat`/`NumberFormat` mit `'de_DE'`.

---

## 16. Offene Entscheidungen (bitte bestätigen)

| # | Frage | Empfehlung (Default) |
|---|---|---|
| 1 | Scanner als **Menü-Eintrag + FAB** oder eigener **BottomNav-Tab**? | Menü + FAB (minimal-invasiv) |
| 2 | Nur **Phones** (< 600 px) oder auch **Tablets**? | Nur Phones im MVP (`isNativeMobile && < 600`) |
| 3 | Wer darf scannen? | `canManageInventory` (Verwalter/Admin) |
| 4 | **Echte Töne** (audioplayers + WAV) oder nur Haptik/System-Klick? | Echte Töne — du hast „Ton für geklappt/nicht geklappt" gefordert |
| 5 | Preis-Historie für **EK+VK** oder nur **VK**? | Beide |
| 6 | Bei Treffer **direkt buchen** (POS-artig) oder nur anzeigen/bearbeiten? | Anzeigen + Buchungs-Buttons (kein Auto-Buchen) |
| 7 | **Doppel-Scan-Schutz**: UI-Debounce, stabile `clientMutationId`, oder beides? | Beides |
| 8 | Server-`findProductByBarcode` + Index, oder dauerhaft clientseitig? | Clientseitig (2 Läden) — Eskalation dokumentiert |
| 9 | **Windows/Linux**-Desktop echtes Ziel? | Nein nötig (Scanner ist mobile-only); manuelle Eingabe deckt Rest |

---

## 17. Betroffene / neue Dateien (Überblick)

**Neu:**
- `lib/screens/scanner_screen.dart`
- `lib/services/barcode_scanner.dart` (Seam + `MobileScannerAdapter`)
- `lib/services/scan_feedback.dart` (Seam + `AudioHapticFeedback`)
- `lib/models/price_history_entry.dart` (Phase 3)
- `assets/audio/scan_ok.wav`, `assets/audio/scan_error.wav`
- Tests: `test/scanner_screen_test.dart`, `test/inventory_barcode_lookup_test.dart`,
  `test/price_history_*_test.dart`

**Geändert:**
- `pubspec.yaml` (SDK-Bump, Pakete, Assets)
- `lib/widgets/responsive_layout.dart` (`isNativeMobile`)
- `lib/models/app_user.dart` (`canUseScanner`)
- `lib/widgets/app_nav_menu.dart` + `lib/screens/home_screen.dart` (Menü-Eintrag, FAB, Push)
- `lib/providers/inventory_provider.dart` (`productByBarcode`, ggf. `adjustStock`-Param, priceHistory-Pfad)
- `lib/screens/inventory_screen.dart` (`showProductDialog(initialBarcode:)`)
- `lib/repositories/inventory_repository.dart` + `firestore_inventory_repository.dart`
  (nur falls Server-Lookup/priceHistory)
- `firestore.rules` (+ `firestore.indexes.json` nur bei Server-Lookup)
- `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`
