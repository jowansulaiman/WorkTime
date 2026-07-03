import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Was der Scanner gerade erkennen soll — steuert die aktive Formatliste.
///
/// Jedes zusaetzliche Format kostet Erkennungszeit pro Frame, deshalb bleibt
/// der schnelle Produktscan bewusst auf 1D-Handelscodes beschraenkt; QR wird
/// nur im [qr]-Modus mitgescannt (umschaltbar im [ScannerScreen]).
enum ScannerTarget {
  /// Handels-Barcodes: EAN-13/EAN-8/UPC-A (Standard, schnell).
  retail,

  /// Zusaetzlich QR-Codes (etwas langsamer, nur bei Bedarf).
  qr,
}

/// Seam fuer die Kamera-/Barcode-Quelle.
///
/// Der [ScannerScreen] kennt nur dieses Interface; im Test wird statt der echten
/// Kamera ein Fake injiziert (keine Platform-Channels in Widget-Tests). Die
/// Vorschau wird ueber [buildPreview] geliefert, damit der Screen testbar bleibt.
abstract interface class BarcodeScanner {
  /// Strom erkannter, getrimmter, nicht-leerer Codes. Entprellung/Dedup macht
  /// der Aufrufer (siehe ScannerScreen) — hier kommt jede Erkennung roh an.
  ///
  /// Der Strom bleibt ueber einen Formatwechsel ([setTarget]) hinweg stabil,
  /// auch wenn intern der Kamera-Controller neu aufgebaut wird.
  Stream<String> get codes;

  /// Ob Kamera-Scannen auf dieser Plattform grundsaetzlich moeglich ist
  /// (false auf Windows/Linux). Steuert den manuellen Eingabe-Fallback.
  bool get isAvailable;

  /// Ob eine Taschenlampe ein-/ausgeschaltet werden kann (nur echte Handys).
  bool get supportsTorch;

  /// Aktuell aktives Scan-Ziel (Formatliste).
  ScannerTarget get target;

  /// Wechselt die erkannten Formate zur Laufzeit (z.B. QR ein/aus). Baut den
  /// Kamera-Controller neu auf (Formate sind ein final-Konstruktor-Parameter)
  /// und startet ihn wieder, falls er lief — [codes] bleibt dabei stabil.
  Future<void> setTarget(ScannerTarget target);

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

  /// Weiterleitung der Erkennungen des jeweils aktuellen Controllers. Der
  /// Aufrufer abonniert EINMAL diesen stabilen Broadcast-Strom; ein
  /// Controller-Neuaufbau (siehe [setTarget]) verdrahtet nur die Quelle neu, das
  /// Abo des Screens bleibt gueltig (sonst waere es nach dem Wechsel tot).
  final StreamController<String> _out = StreamController<String>.broadcast();
  StreamSubscription<BarcodeCapture>? _controllerSub;

  ScannerTarget _target = ScannerTarget.retail;

  /// Ob der Scanner aktuell laeuft — damit [setTarget] nach dem Neuaufbau nur
  /// dann wieder startet, wenn er vorher lief.
  bool _started = false;

  // Ziel-Fenster (Reticle): EAN-13 ist quer/breit -> flaches, breites Rechteck,
  // mittig. Dieselben Werte speisen scanWindow (Analysezone) UND das sichtbare
  // Overlay, damit beide deckungsgleich sind.
  static const double _reticleWidthFraction = 0.82;
  static const double _reticleHeightFraction = 0.32;

  static Rect _reticleRect(Size size) => Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: size.width * _reticleWidthFraction,
        height: size.height * _reticleHeightFraction,
      );

  static List<BarcodeFormat> _formatsFor(ScannerTarget target) {
    switch (target) {
      case ScannerTarget.retail:
        return const <BarcodeFormat>[
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
        ];
      case ScannerTarget.qr:
        // 1D bleibt aktiv, damit man im QR-Modus auch Produkte scannen kann.
        return const <BarcodeFormat>[
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.qrCode,
        ];
    }
  }

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
    final existing = _controller;
    if (existing != null) return existing;
    final controller = MobileScannerController(
      autoStart: false, // Lebenszyklus steuert der Screen selbst.
      detectionSpeed: DetectionSpeed.normal,
      // Default ist 250 ms Drossel zwischen Auswertungen; 100 ms macht die
      // Erkennung reaktiver. Doppel-Scans entprellt der Aufrufer selbst
      // (ScannerScreen), die Controller-Ebene darf also schnell laufen.
      detectionTimeoutMs: 100,
      // Holt zu weit entfernte Codes automatisch heran (nur Android wirksam,
      // No-op auf iOS/Web).
      autoZoom: true,
      formats: _formatsFor(_target),
      // Bewusst NICHT gesetzt: cameraResolution. Der native v7-Default fordert
      // auf Android bereits 1920x1080 an; ein kleinerer Wert wuerde die
      // Analyse-Aufloesung senken (kontraproduktiv), auf iOS/Web ist der
      // Parameter wirkungslos.
    );
    _controller = controller;
    // Erkennungen des aktuellen Controllers in den stabilen Ausgabestrom leiten.
    _controllerSub = controller.barcodes.listen(
      (capture) {
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue?.trim() ?? '';
          if (value.isNotEmpty && !_out.isClosed) _out.add(value);
        }
      },
      onError: (_) {},
    );
    return controller;
  }

  @override
  bool get isAvailable => _platformSupported;

  @override
  bool get supportsTorch =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  ScannerTarget get target => _target;

  @override
  Future<void> setTarget(ScannerTarget target) async {
    if (target == _target) return;
    _target = target;
    if (!_platformSupported) return;
    // Formate sind ein final-Konstruktor-Parameter -> Controller neu aufbauen.
    // Der stabile _out-Strom bleibt bestehen; nur die Quelle wird neu verdrahtet.
    final wasStarted = _started;
    await _controllerSub?.cancel();
    _controllerSub = null;
    await _controller?.dispose();
    _controller = null;
    _started = false;
    if (wasStarted) {
      // NICHT blockierend awaiten: start() wartet intern darauf, dass der neue
      // Controller vom MobileScanner attached wird (sonst controllerNotAttached-
      // Timeout). Dieses Attach passiert aber erst, wenn der Aufrufer NACH
      // setTarget() setState() ruft und der (per Controller-Key) neu gemountete
      // MobileScanner den neuen Controller attached. Ein await hier haelt den
      // Rebuild auf -> start() laeuft in den 500ms-Timeout und wirft. Darum
      // fire-and-forget; ein echter Kamerafehler spiegelt sich ohnehin im
      // Fehlerzustand des sichtbaren MobileScanner.
      unawaited(start().catchError((Object _) {}));
    }
  }

  @override
  Stream<String> get codes => _out.stream;

  @override
  Future<void> start() async {
    if (!_platformSupported) return;
    await _ensureController().start();
    _started = true;
  }

  @override
  Future<void> stop() async {
    _started = false;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final rect = _reticleRect(constraints.biggest);
        final controller = _ensureController();
        return MobileScanner(
          // Der MobileScanner-State bindet seinen Controller EINMALIG in
          // initState (late final, kein didUpdateWidget). Wird der Controller
          // nach einem Formatwechsel (setTarget) neu erzeugt, bleibt der State
          // sonst am alten, disposedten Controller haengen -> weisses Bild bzw.
          // controllerNotAttached. Ein an die Controller-Identitaet gekoppelter
          // Key erzwingt einen frischen State, der den neuen Controller
          // attached (und damit start() entsperrt).
          key: ObjectKey(controller),
          controller: controller,
          fit: BoxFit.cover,
          // scanWindow begrenzt die Analysezone (schneller/stabiler) — auf Web
          // ein No-op, dort bleibt das Reticle rein visuell.
          scanWindow: kIsWeb ? null : rect,
          scanWindowUpdateThreshold: 0.05, // gegen Rebuild-Flackern
          tapToFocus: true, // Nutzer kann Fokus erzwingen (iOS/Android)
          overlayBuilder: (context, _) => _ScanReticle(rect: rect),
        );
      },
    );
  }

  @override
  Future<void> dispose() async {
    await _controllerSub?.cancel();
    _controllerSub = null;
    await _controller?.dispose();
    _controller = null;
    await _out.close();
  }
}

/// Sichtbares Ziel-Fenster ueber der Kameravorschau: dunkelt den Bereich
/// ausserhalb ab und rahmt das mittige Scan-Rechteck. Rein visuell (blockiert
/// keine Gesten) und deckungsgleich mit dem [scanWindow] auf Mobile.
class _ScanReticle extends StatelessWidget {
  const _ScanReticle({required this.rect});

  final Rect rect;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ReticlePainter(
          rect: rect,
          borderColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  _ReticlePainter({required this.rect, required this.borderColor});

  final Rect rect;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = const Color(0x66000000);
    // Vier Streifen rund um das Zielfenster abdunkeln (ohne Path-Operationen).
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, rect.top), dim);
    canvas.drawRect(Rect.fromLTRB(0, rect.bottom, size.width, size.height), dim);
    canvas.drawRect(Rect.fromLTRB(0, rect.top, rect.left, rect.bottom), dim);
    canvas.drawRect(Rect.fromLTRB(rect.right, rect.top, size.width, rect.bottom), dim);

    final border = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      border,
    );
  }

  @override
  bool shouldRepaint(_ReticlePainter oldDelegate) =>
      oldDelegate.rect != rect || oldDelegate.borderColor != borderColor;
}
