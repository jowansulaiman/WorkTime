# Plan: Scanner verbessern — schnellere & zuverlässigere Barcode-Erkennung

> **Stand:** 2026-07-01 · **Status:** ✅ **M1–M6 umgesetzt** (`flutter analyze` sauber, `flutter test` = **1271 grün**) · offen nur die manuelle On-Device-Abnahme (§5.2, Kamera nicht automatisierbar) · Branch `fix/web-scanner-csp-selfhost-zxing`
>
> ## Umsetzungsstand (2026-07-01)
> Alle Meilensteine implementiert, alle Änderungen hinter dem `BarcodeScanner`-Seam (Screen kennt weiter keine `mobile_scanner`-Typen):
> - **M1** [`barcode_scanner.dart`](../lib/services/barcode_scanner.dart) `_ensureController`: `detectionTimeoutMs: 100`, `autoZoom: true`, `formats` je `ScannerTarget`; `cameraResolution` bewusst NICHT gesetzt (Kommentar).
> - **M2** `buildPreview`: `LayoutBuilder` → `scanWindow` (mobil) + `scanWindowUpdateThreshold: 0.05` + `tapToFocus: true` + `overlayBuilder` mit neuem `_ScanReticle`/`_ReticlePainter` (Web: nur kosmetisch, `scanWindow: null`).
> - **M3/M3a** `ScannerTarget{retail,qr}` + `target`/`setTarget` im Seam; Adapter auf stabilen Broadcast-`_out`-Strom umgebaut (überlebt Controller-Neuaufbau); QR-Toggle in der AppBar ([`scanner_screen.dart`](../lib/screens/scanner_screen.dart)).
> - **M4** Gleichcode-Debounce `2s → 1000ms`.
> - **M5** pure `gtinLookupVariants` in [`ean.dart`](../lib/core/ean.dart) + Nutzung in `productsByBarcode` ([`inventory_provider.dart`](../lib/providers/inventory_provider.dart)) — UPC-A↔EAN-13-Leading-Zero (#1653).
> - **M6** Dunkelheits-Hinweis (Torch-Angebot nach ~4s ohne Erkennung, nur wo `supportsTorch`).
> - **M7 (Bugfix Ton/Haptik, 01.07.):** Auf dem Handy kam beim Scannen kein Ton/keine Vibration. Ursachen behoben in [`scan_feedback.dart`](../lib/services/scan_feedback.dart): (a) Audio von `PlayerMode.lowLatency` (SoundPool spielte Asset-Toene auf Android oft nicht ab) auf Default-`mediaPlayer` + **einmal vorgeladene Quelle** (`setSource`) + `seek(0)+resume` umgestellt; (b) Haptik auf `HapticFeedback.heavyImpact` (Erfolg) bzw. Doppel-Buzz (Fehler) verstärkt und **parallel** zum Ton (`Future.wait`) ausgelöst; (c) fehlende `android.permission.VIBRATE` in [`AndroidManifest.xml`](../android/app/src/main/AndroidManifest.xml) ergänzt. **Hinweis:** `HapticFeedback` respektiert die System-Einstellung „Haptisches Feedback / Vibration bei Berührung" — ist die am Gerät aus, vibriert es trotzdem nicht (dann bräuchte es ein dediziertes `vibration`-Plugin). Nur On-Device verifizierbar.
> - **Tests** +9: `gtinLookupVariants` (foundation), UPC-A/EAN-13-Lookup (barcode-lookup), QR-Toggle + Debounce (scanner_screen; Debounce nutzt echte `runAsync`-Wartezeit, da `DateTime.now()`).
>
> **Original-Plan unten unverändert** (Begründungen/Belege gelten weiter).
>
> ---
>
> **Stand:** 2026-07-01 · **Status:** Entwurf (research- & code-verifiziert) · Branch `fix/web-scanner-csp-selfhost-zxing`
> **Betrifft:** [`lib/services/barcode_scanner.dart`](../lib/services/barcode_scanner.dart), [`lib/screens/scanner_screen.dart`](../lib/screens/scanner_screen.dart), [`lib/core/ean.dart`](../lib/core/ean.dart), [`lib/providers/inventory_provider.dart`](../lib/providers/inventory_provider.dart)
> **Verwandt:** [scanner-modul](../.claude/…) (Memory) · [`plan/arbeitsmodus-kachel-ausbau.md`](arbeitsmodus-kachel-ausbau.md) (Kiosk-Scanner-Kachel) · [`plan/mhd-ablauf-warnung.md`](mhd-ablauf-warnung.md) (MHD-Erfassung im Scanner)
> **Entscheidungen des Inhabers (01.07.):** QR = **separater umschaltbarer Modus** (Produktscan bleibt 1D-schnell) · Hauptgeräte = **Android-Handy + iPhone/iPad** (Web ist Nebenpfad).
>
> Quelle der API-Fakten: Multi-Agent-Recherche gegen die offizielle `mobile_scanner`-Quelle
> (juliansteenbakker/mobile_scanner **v7.2.0**, pub.dev, README, CHANGELOG, GitHub-Issues) +
> ML-Kit-Doku + ZXing-js-Quelle, **adversarial gegengeprüft** (9 bestätigt, 1 widerlegt, 2 präzisiert).
> Version ist bereits `^7.2.0` → **kein Paket-Upgrade nötig**, alle genutzten APIs sind darin vorhanden.

---

## 0. Kurzfassung (was wirklich das Problem ist)

Der Nutzer meldet: „erkennt Barcodes nicht gut, manchmal dauert es lang, obwohl der Barcode/QR-Code gut lesbar ist."

Die verifizierte Ursachenanalyse widerlegt die naheliegende Vermutung („Kamera-Auflösung zu niedrig") und zeigt drei echte Hebel — **alle auf Mobile (ML Kit / Apple Vision) wirksam**, wo auch tatsächlich gescannt wird:

| # | Befund (verifiziert) | Wirkung | Stelle |
|---|---|---|---|
| **A** | **QR wird NIE erkannt** — `formats` enthält nur `ean13/ean8/upcA`, `qrCode` fehlt. Das ist kein Tempo-, sondern ein Konfig-Thema. | „QR gut lesbar, wird aber nicht erkannt" = erklärt | [barcode_scanner.dart:89-93](../lib/services/barcode_scanner.dart#L89-L93) |
| **B** | **Kein `scanWindow` / kein Ziel-Reticle.** Der ganze Frame wird analysiert; der Nutzer hat kein Zielfeld. `scanWindow` verkleinert den Suchraum (schneller/stabiler) **und** gibt ein klares Ziel. **Größter Erkennungs-Hebel.** | schnellere Trefferzeit + weniger „wohin halten?" | [barcode_scanner.dart:140](../lib/services/barcode_scanner.dart#L140) |
| **C** | **Kein Autofokus-Erzwingen (`tapToFocus`), kein `autoZoom`, `detectionTimeoutMs` läuft auf Default 250 ms.** Bei nahen kleinen Regal-Codes „pumpt" der Autofokus (dokumentierte iPhone-Pro-Nahfokus-Regression). | Unschärfe → viele Frames bis Treffer = „dauert lang" | [barcode_scanner.dart:86-94](../lib/services/barcode_scanner.dart#L86-L94) |

**Wichtige Korrektur aus der Gegenprüfung (sonst baut man das Falsche):**
`cameraResolution` ist **NICHT** der Hebel. Der Dart-Doc-Kommentar behauptet „null → 640×480 auf Android", aber der native v7.2.0-Code fordert bei `null` bereits **1920×1080** an (`MobileScanner.kt:427: cameraResolutionWanted ?: Size(1920,1080)`). Auf iOS/Web hat der Parameter **keine** Wirkung. → **`cameraResolution` bewusst NICHT setzen**; ein `Size(1280,720)` würde die Analyse-Auflösung sogar *unter* den Default drücken.

**Web ehrlich einordnen:** Auf Web läuft ZXing-js (kein nativer BarcodeDetector-Pfad im Plugin, ~350 ms/Frame, Main-Thread). `scanWindow`, `autoZoom`, `tapToFocus`, `cameraResolution`, Torch wirken dort **nicht**. Da Hauptnutzung mobil ist, wird Web nur „mitgenommen" (kosmetisches Reticle + Erwartungsmanagement), nicht optimiert.

---

## 1. Zielbild & Scope

**Ziel:** Auf Android/iOS spürbar schnellere und zuverlässigere Erkennung von Handels-Barcodes; QR bei Bedarf per Umschalten; korrektes Auffinden auch bei UPC-A/EAN-13-Leading-Zero-Varianten.

**In Scope**
- Controller-Feintuning (`detectionTimeoutMs`, `autoZoom`, `tapToFocus`).
- `scanWindow` + sichtbares Ziel-Reticle (Mobile: echte Analysezone; Web: nur kosmetisch).
- Umschaltbarer **QR-Modus** (Button), der die Formatliste zur Laufzeit wechselt — ohne den 1D-Produktscan dauerhaft zu verlangsamen.
- **Robuste Erkennungs-Stream-Architektur** im Adapter (überlebt Controller-Neuaufbau beim Modus-Wechsel).
- Lookup-Korrektheit: UPC-A (12) ↔ EAN-13 (0+12) beim Nachschlagen tolerieren (Issue #1653).
- Debounce-Feinjustierung (2 s → 1 s) für flüssigeres Batch-/Inventur-Scannen.

**Nicht-Ziele (bewusst, siehe §7)**
- `cameraResolution` ändern (Default ist auf Android schon 1080p; sonst wirkungslos/kontraproduktiv).
- Web-ZXing beschleunigen (technisch begrenzt; Plugin exponiert weder `tryHarder`, Web-Worker, Crop noch nativen BarcodeDetector).
- Paket-Upgrade (7.2.0 hat bereits alle APIs + die 7.1.3/7.2.0-Android-Analyse-Fixes).
- `DetectionSpeed.noDuplicates` (Android-Totalausfälle #1252/#750).
- `invertImage`/`returnImage` aktivieren (kosten Performance, kein Nutzen für schwarz-auf-weiß-Handelscodes).

---

## 2. Meilensteine (klein, offline-testbar, in dieser Reihenfolge)

Alle Änderungen bleiben hinter dem bestehenden Seam [`BarcodeScanner`](../lib/services/barcode_scanner.dart#L12) — der `ScannerScreen` importiert weiterhin **keine** `mobile_scanner`-Typen, Widget-Tests laufen über den `_FakeBarcodeScanner` weiter.

### M1 — Controller-Tuning (größter Sofort-Effekt, geringstes Risiko)

In [`_ensureController()`](../lib/services/barcode_scanner.dart#L85-L95):

```dart
_controller ??= MobileScannerController(
  autoStart: false,
  detectionSpeed: DetectionSpeed.normal,   // beibehalten (unrestricted = optionaler A/B-Test, s.u.)
  detectionTimeoutMs: 100,                  // NEU: Default 250 → 100 (reaktiver; App entprellt selbst)
  autoZoom: true,                           // NEU: Android holt entfernte Codes heran (No-op iOS/macOS/Web)
  formats: _formatsFor(_target),            // NEU: je nach Scan-Ziel (M3)
);
```

- **`detectionTimeoutMs: 100`** — der Timeout drosselt bei `DetectionSpeed.normal` die Frame-Auswertung; 250 ms ist der stille Default (aktuell gar nicht gesetzt). Die App entprellt Doppel-Scans **selbst** (M4 / [scanner_screen.dart:207-217](../lib/screens/scanner_screen.dart#L207-L217)), die Controller-Ebene darf also aggressiv sein.
- **`autoZoom: true`** — nur Android-wirksam, schadet iOS/Web nicht (No-op).
- **`DetectionSpeed.unrestricted`** ist die Alternative (jeder Frame, keine Drosselung), aber laut Doku „memory issues on older devices" → erst als A/B-Test auf echten Geräten, nicht blind setzen. `noDuplicates` **nicht** verwenden.
- **`cameraResolution` NICHT setzen** (siehe §0-Korrektur) — als Kommentar im Code festhalten, damit es niemand „nachbessert".

### M2 — `scanWindow` + Ziel-Reticle (Haupt-Erkennungs-Hebel)

`scanWindow` ist ein Parameter des **`MobileScanner`-Widgets** (nicht des Controllers), Typ `Rect?`, Koordinaten **relativ zur Layout-Größe des Preview-Widgets**. In [`buildPreview()`](../lib/services/barcode_scanner.dart#L137-L141):

```dart
static const double _reticleWFraction = 0.82; // EAN-13 ist breit → flaches, breites Fenster
static const double _reticleHFraction = 0.32;

Rect _reticleRect(Size size) => Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * _reticleWFraction,
      height: size.height * _reticleHFraction,
    );

@override
Widget buildPreview(BuildContext context) {
  if (!_platformSupported) return const SizedBox.shrink();
  return LayoutBuilder(
    builder: (context, constraints) {
      final rect = _reticleRect(constraints.biggest);
      return MobileScanner(
        controller: _ensureController(),
        fit: BoxFit.cover,
        // Web: scanWindow ist ein No-op → null; das Reticle bleibt rein kosmetisch.
        scanWindow: kIsWeb ? null : rect,
        scanWindowUpdateThreshold: 0.05,   // gegen Rebuild-Flackern
        tapToFocus: true,                  // NEU: Nutzer kann Fokus erzwingen (iOS/Android)
        overlayBuilder: (context, _) => _ScanReticle(rect: rect),
      );
    },
  );
}
```

- **`tapToFocus: true`** adressiert direkt „bleibt unscharf bei nahen kleinen Codes" (u. a. iPhone-Pro-Nahfokus-Regression).
- **`_ScanReticle`** = schlichtes Overlay (abgedunkelte Ränder + heller Rahmen um `rect`), themekonform via `Theme.of(context).appColors`. Funktioniert auf allen Plattformen (reines Flutter-Painting) → auf Web sieht der Nutzer trotzdem ein Zielfeld.
- **Footgun (verifiziert, #1009/#633/#1199):** `scanWindow` + `BoxFit.cover` kann visuell/analytisch verrutschen, weil `cover` den Frame beschneidet. v7.2.0 hat die Fenster-Erkennung verbessert (Migration `boundingBox`→`cornerPoints`), aber **auf echten Geräten (Android + iOS) verifizieren**. Fallback, falls das Reticle nicht deckungsgleich sitzt: `scanWindow` weglassen und **nur** das Overlay behalten (Ziel-Hilfe ohne harte Analysezone) — geringerer, aber risikofreier Gewinn.

### M3 — Umschaltbarer QR-Modus (Inhaber-Entscheidung: „QR separat dazu")

Produktscan bleibt **1D-schnell**; ein Button schaltet in einen QR-Modus, der `qrCode` ergänzt.

**Seam erweitern** ([`BarcodeScanner`](../lib/services/barcode_scanner.dart#L12)):

```dart
/// Was gescannt werden soll. Steuert die aktive Formatliste (Tempo-Trade-off:
/// jedes Format kostet Erkennungszeit pro Frame → 1D bleibt Default).
enum ScannerTarget { retail, qr }

abstract interface class BarcodeScanner {
  // … bestehend …
  ScannerTarget get target;
  Future<void> setTarget(ScannerTarget target); // wechselt Formate zur Laufzeit
}
```

**Adapter:**
```dart
ScannerTarget _target = ScannerTarget.retail;

List<BarcodeFormat> _formatsFor(ScannerTarget t) => switch (t) {
  ScannerTarget.retail => const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA],
  // QR-Modus: 1D bleibt an, damit man im QR-Modus auch Produkte scannen kann.
  ScannerTarget.qr => const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.qrCode],
};

@override
Future<void> setTarget(ScannerTarget target) async { … recreate + restart … }
```

- **`formats` ist ein `final`-Konstruktor-Parameter** → Moduswechsel erfordert **Controller-Neuaufbau** (dispose → neu mit neuer Formatliste → `start()`). Das passiert nur bei bewusstem Umschalten, nicht pro Frame → unkritisch.
- **Voraussetzung → M3a (stabiler Ausgabe-Stream, in M3 gebündelt):** Der `codes`-Getter liefert aktuell `_ensureController().barcodes…` — an **eine** Controller-Instanz gebunden. Nach Neuaufbau wäre die bestehende Screen-Subscription tot. Deshalb der Adapter auf einen **eigenen Broadcast-`StreamController<String> _out`** umstellen: bei jedem (Neu-)Aufbau die `controller.barcodes`-Erkennungen in `_out` umleiten; `codes` gibt `_out.stream` zurück. So überlebt die Screen-Subscription den Moduswechsel und der Screen bleibt unverändert.
- **UI:** AppBar-Action-Toggle (`Icons.qr_code_scanner` ↔ `Icons.barcode_reader`) neben dem Ton-Button ([scanner_screen.dart:789-799](../lib/screens/scanner_screen.dart#L789-L799)), ruft `_scanner.setTarget(...)` und zeigt den aktiven Modus. Kein Web-Sonderfall nötig (ZXing wertet die Formatliste über `POSSIBLE_FORMATS` ebenfalls aus).

### M4 — Debounce feinjustieren

[scanner_screen.dart:210-212](../lib/screens/scanner_screen.dart#L210-L212): Gleichcode-Sperre von `Duration(seconds: 2)` auf **`Duration(milliseconds: 1000)`** senken. 2 s bremsen absichtliches Mehrfach-Zählen desselben Artikels (Inventur/Bestellen) spürbar; 1 s verhindert weiterhin das Dauer-Wiederbeepen eines Frame-Bursts. Bleibt die **alleinige Dedup-Autorität** (deshalb darf der Controller in M1 schnell laufen).

### M5 — Lookup-Korrektheit: UPC-A ↔ EAN-13 Leading-Zero (Issue #1653)

`mobile_scanner` 7.1.x liefert auf iOS UPC-A teils als **EAN-13 mit führender Null** (`012345678905` → `0012345678905`). Der Lookup ist aktuell **exakter String-Vergleich** ([inventory_provider.dart:272](../lib/providers/inventory_provider.dart#L272)) → Fehl-Miss, wenn der Artikel mit 12-stelligem UPC-A gespeichert ist.

- **Pure Helper in [`lib/core/ean.dart`](../lib/core/ean.dart)** (testbar, ohne Abhängigkeiten):
  ```dart
  /// Kandidaten für den Barcode-Lookup: der Code selbst plus die
  /// UPC-A↔EAN-13-Leading-Zero-Variante. Verlustfrei/tolerant, ändert nie
  /// gespeicherte Werte — nur die Suche wird großzügiger.
  Set<String> gtinLookupVariants(String raw) { … 13-stellig mit '0' vorne → auch 12-stellig; 12-stellig → auch '0'+code … }
  ```
- **In `productsByBarcode`** ([inventory_provider.dart:259-276](../lib/providers/inventory_provider.dart#L259-L276)) den `== code`-Vergleich gegen `gtinLookupVariants(code).contains(storedBarcode)` (bzw. Schnittmenge der Varianten) tauschen. Betrifft alle Aufrufer (Scanner-Lookup + Dubletten-Check bei Neuanlage) — nur *breiterer* Match, keine Verhaltensregression.

### M6 — (optional, niedrig) Torch-Hinweis bei Dunkelheit

`mobile_scanner` liefert kein Umgebungslicht-Signal. Heuristik: wenn nach ~3–4 s aktivem Scannen **kein** Treffer kam, dezenter Hinweis „Zu dunkel? Licht einschalten" mit direktem Torch-Button (nur wenn `supportsTorch`). Rein additiv; kann später kommen.

---

## 3. Warum genau diese Werte (Belege)

- **`detectionTimeoutMs` nur bei `normal` wirksam, Default 250:** Konstruktor `detectionTimeoutMs = detectionSpeed == DetectionSpeed.normal ? detectionTimeoutMs : 0`; Doc „By default 250 ms … ignored if detectionSpeed is not normal". → Senken auf 100 = reaktiver, ohne `unrestricted`-Speicherrisiko.
- **`noDuplicates` meiden:** analysiert zwar jeden Frame (ist *kein* „langsam"-Modus), hat aber reale Android-Ausfälle (#1252 „no barcodes detected", #750 „dead after pop/push").
- **`autoZoom`/`tapToFocus`/`initialZoom`** existieren in v7 (seit 7.0.0-beta.5 / 7.1.0); `setZoomScale`/`resetZoomScale`/`setFocusPoint` am Controller.
- **`scanWindow` Web-No-op** (Plugin: „scanner does not expose size information"); Formatliste wirkt dagegen **auch** auf Web (ZXing `POSSIBLE_FORMATS`-Hint) — enge Liste bleiben, nie `BarcodeFormat.all`.
- **`cameraResolution` Web:** `getUserMedia`-Constraints setzen nur `facingMode`, nie `width/height` → auf Web ohne Wirkung; auf Android bei `null` bereits 1080p.

---

## 4. Tests (offline, Fakes — keine echte Kamera/Firebase)

- **[`test/scanner_foundation_test.dart`](../test/scanner_foundation_test.dart)** (pure):
  - `gtinLookupVariants`: `012345678905` (UPC-A) ↔ `0012345678905` (EAN-13+0) gegenseitig, Nicht-GTIN-Längen unverändert, Nicht-Numerisches unberührt.
  - Bestehende EAN-Prüfziffer-Tests bleiben grün.
- **[`test/inventory_barcode_lookup_test.dart`](../test/inventory_barcode_lookup_test.dart):** Artikel mit 12-stelligem UPC-A wird von einem 13-stelligen `0…`-Scan gefunden (und umgekehrt); Standort-Skopierung bleibt.
- **[`test/scanner_screen_test.dart`](../test/scanner_screen_test.dart):** `_FakeBarcodeScanner` um `target`/`setTarget` erweitern (nur mitschreiben). Tests: QR-Toggle ruft `setTarget(ScannerTarget.qr)`; Debounce verschluckt Gleichcode < 1 s, lässt ihn nach ≥ 1 s wieder durch.
- Die Stream-Stabilität (M3a) betrifft nur den echten Adapter; der Fake hält seinen `broadcast`-Stream ohnehin stabil.

---

## 5. Definition of Done

1. `flutter analyze` ohne neue Issues; `flutter test` komplett grün (Basis ~1246).
2. **Manuelle On-Device-Abnahme (Pflicht, da Kamera nicht test-automatisierbar) auf Android UND iOS:**
   - Zeit-bis-Treffer für dieselben 5 realen Handels-Barcodes **vorher/nachher** grob messen (spürbar schneller?).
   - Reticle sitzt deckungsgleich über der tatsächlichen Analysezone (sonst M2-Fallback: nur Overlay).
   - `tapToFocus`: Tippen schärft nahe kleine Codes; `autoZoom` (Android) holt entfernte Codes heran.
   - QR-Toggle: QR wird im QR-Modus erkannt, im Produktmodus nicht (und Produktscan bleibt schnell).
   - Torch, Kamera-Wechsel, App-Resume-Neustart funktionieren weiterhin.
3. Web (Chrome): Scanner lädt (Self-Host-ZXing), Reticle sichtbar, Produkt-/QR-Scan funktioniert — **langsamer akzeptiert**.
4. `flutter build appbundle --release --obfuscate --split-debug-info=build/symbols` baut fehlerfrei (Release-Guard).

---

## 6. Kopplungen / Risiken

- **`scanWindow` + `BoxFit.cover`** kann verrutschen (#1009/#633/#1199) → On-Device verifizieren, sonst Overlay-only-Fallback.
- **Controller-Neuaufbau bei QR-Toggle** darf die Screen-Subscription nicht töten → **M3a (stabiler `_out`-Stream) ist Voraussetzung**, nicht optional.
- **`productsByBarcode`-Verbreiterung** wirkt überall (Scanner + Dubletten-Check) — bewusst nur zusätzlicher Match, kein Ausschluss.
- **Web-Erwartung:** Alle Kamera-/Fokus-/Zoom-/`scanWindow`-Hebel sind auf Web No-ops; Verbesserung dort nur via Overlay + Beleuchtung/Abstand. Vieltscanner auf die Mobile-App lenken.
- **Keine** Änderung an Compliance/Serialisierung/Provider-Kette → keine der „Wenn du X änderst, ändere auch Y"-Kopplungen aus `CLAUDE.md` betroffen (reines UI-/Service-Feintuning; `ScannerTarget` ist ein neuer, aber lokaler Enum ohne Persistenz/Callable/Firestore-Bezug).

---

## 7. Bewusst offen / später

- **Web-ZXing-Speedup** (WASM-ZXing #1231/#1664 bzw. nativer BarcodeDetector) — nicht vom Plugin exponiert; erst wenn `mobile_scanner` es anbietet oder Web strategisch wichtig wird (dann eigenes JS-Interop; Achtung: BarcodeDetector fehlt auf iOS-Safari).
- **`DetectionSpeed.unrestricted`** als A/B-Option auf modernen Geräten (Memory-Trade-off) — nach M1-Messung entscheiden.
- **`initialZoom`** (fester Start-Zoom) — optionaler Feinschliff nach Gerätetest.
- **UPC-E** ergänzen, falls US-komprimierte Codes real auftauchen (aktuell nicht in der Formatliste; bewusst).

---

## Quellen (verifiziert, v7.2.0)

- `mobile_scanner` Quelle/Doku: `MobileScannerController`, `MobileScanner`, `DetectionSpeed`, `MobileScanner.kt:427` (Android-Default 1920×1080), Web-Impl (`mobile_scanner_web.dart`, `zxing_barcode_reader.dart`), README-Feature-Matrix, CHANGELOG.
- GitHub-Issues: #1105 (autoStart/„slow"), #1252 & #750 (noDuplicates-Ausfälle), #633/#1009/#1199 (scanWindow+cover), #1653 (UPC-A→EAN-13 Leading-Zero), #1231/#1664 (WASM-ZXing).
- Google ML Kit Barcode Scanning (Android): Formate einschränken + Auflösung + Fokus.
- ZXing-js: `POSSIBLE_FORMATS`-Hint, Main-Thread-Decode, kein `tryHarder`/Worker über das Plugin.
