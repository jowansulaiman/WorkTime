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
  MobileScannerAdapter();

  MobileScannerController? _controller;

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
