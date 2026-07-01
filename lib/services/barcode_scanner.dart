import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Seam fuer die Kamera-/Barcode-Quelle.
///
/// Der [ScannerScreen] kennt nur dieses Interface; im Test wird statt der echten
/// Kamera ein Fake injiziert (keine Platform-Channels in Widget-Tests). Die
/// Vorschau wird ueber [buildPreview] geliefert, damit der Screen testbar bleibt.
abstract interface class BarcodeScanner {
  /// Strom erkannter, getrimmter, nicht-leerer Codes. Entprellung/Dedup macht
  /// der Aufrufer (siehe ScannerScreen) — hier kommt jede Erkennung roh an.
  Stream<String> get codes;

  /// Ob Kamera-Scannen auf dieser Plattform grundsaetzlich moeglich ist
  /// (false auf Windows/Linux). Steuert den manuellen Eingabe-Fallback.
  bool get isAvailable;

  /// Ob eine Taschenlampe ein-/ausgeschaltet werden kann (nur echte Handys).
  bool get supportsTorch;

  Future<void> start();
  Future<void> stop();
  Future<void> toggleTorch();
  Future<void> switchCamera();

  /// Live-Kameravorschau. Liefert bei fehlender Unterstuetzung einen leeren
  /// Platzhalter.
  Widget buildPreview(BuildContext context);

  Future<void> dispose();
}

/// Echte Implementierung auf Basis von `mobile_scanner` (v7, Apple Vision/CameraX).
///
/// Der Controller wird erst bei Bedarf erzeugt und nur auf unterstuetzten
/// Plattformen — so wird auf Windows/Linux/Web-ohne-Kamera nichts angefasst.
class MobileScannerAdapter implements BarcodeScanner {
  MobileScannerAdapter() {
    _ensureWebLibraryScriptUrl();
  }

  MobileScannerController? _controller;

  /// Auf Web laedt `mobile_scanner` die ZXing-Bibliothek sonst zur Laufzeit von
  /// `https://unpkg.com/@zxing/library@0.21.3` nach. Das blockiert unsere
  /// strenge CSP (`script-src` in `web/index.html` erlaubt kein unpkg) — der
  /// Scanner meldet dann nur „Could not load the BarcodeReader script due to a
  /// network error". Wir hosten die Bibliothek stattdessen selbst unter
  /// `web/vendor/zxing.min.js` (von `script-src 'self'` gedeckt, keine
  /// CDN-Abhaengigkeit) und zeigen den Loader dorthin. Pfad bewusst relativ
  /// (loest gegen `<base href>` auf → funktioniert auch unter Sub-Pfaden).
  /// Idempotent (Plattform merkt sich die erste URL via `??=`), No-op
  /// ausserhalb des Webs.
  ///
  /// HINWEIS Offline: Flutter 3.41 liefert einen sich selbst abmeldenden
  /// Service-Worker (kein Precache); zusammen mit `no-store`-Hosting-Headern
  /// hat die Web-App aktuell KEINE Offline-Faehigkeit. Der Scanner ist damit
  /// nur online nutzbar — echtes Offline braucht einen eigenen PWA-SW (separat).
  static bool _webScriptUrlConfigured = false;
  static void _ensureWebLibraryScriptUrl() {
    if (!kIsWeb || _webScriptUrlConfigured) return;
    _webScriptUrlConfigured = true;
    MobileScannerPlatform.instance.setBarcodeLibraryScriptUrl(
      'vendor/zxing.min.js',
    );
  }

  static bool get _platformSupported {
    if (kIsWeb) return true; // ZXing, braucht Secure Context (HTTPS/localhost)
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return true;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  MobileScannerController _ensureController() {
    return _controller ??= MobileScannerController(
      autoStart: false, // Lebenszyklus steuert der Screen selbst.
      detectionSpeed: DetectionSpeed.normal,
      formats: const <BarcodeFormat>[
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
      ],
    );
  }

  @override
  bool get isAvailable => _platformSupported;

  @override
  bool get supportsTorch =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Stream<String> get codes {
    if (!_platformSupported) return const Stream<String>.empty();
    return _ensureController()
        .barcodes
        .expand((capture) => capture.barcodes)
        .map((barcode) => barcode.rawValue?.trim() ?? '')
        .where((value) => value.isNotEmpty);
  }

  @override
  Future<void> start() async {
    if (!_platformSupported) return;
    await _ensureController().start();
  }

  @override
  Future<void> stop() async {
    await _controller?.stop();
  }

  @override
  Future<void> toggleTorch() async {
    await _controller?.toggleTorch();
  }

  @override
  Future<void> switchCamera() async {
    await _controller?.switchCamera();
  }

  @override
  Widget buildPreview(BuildContext context) {
    if (!_platformSupported) return const SizedBox.shrink();
    return MobileScanner(controller: _ensureController(), fit: BoxFit.cover);
  }

  @override
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}
