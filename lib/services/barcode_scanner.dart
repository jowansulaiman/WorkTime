import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Was der Scanner gerade erkennen soll — steuert die aktive Formatliste.
///
/// Jedes zusaetzliche Format kostet Erkennungszeit pro Frame, deshalb bleibt
/// der schnelle Produktscan bewusst auf 1D-Handelscodes beschraenkt; QR,
/// DataMatrix und Karton-Codes werden nur im [extended]-Modus mitgescannt
/// (umschaltbar im [ScannerScreen]).
enum ScannerTarget {
  /// Handels-Barcodes: EAN-13/EAN-8/UPC-A/UPC-E (Standard, schnell).
  retail,

  /// Zusaetzlich QR, GS1 DataMatrix, ITF-14 (Umkartons) und Code-128
  /// (etwas langsamer, nur bei Bedarf).
  extended,
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

  /// Ob die Kamera-Vergroesserung steuerbar ist (nur echte Handys). Fuer kleine
  /// oder weit entfernte Barcodes.
  bool get supportsZoom;

  /// Ob ein Foto in voller Aufloesung nachtraeglich analysiert werden kann
  /// ([analyzePhoto]) — der Rettungsanker fuer beschaedigte/winzige Codes.
  bool get supportsPhotoAnalysis;

  /// Aktuell aktives Scan-Ziel (Formatliste).
  ScannerTarget get target;

  /// Wechselt die erkannten Formate zur Laufzeit (z.B. erweiterten Modus
  /// ein/aus). Baut den Kamera-Controller neu auf (Formate sind ein
  /// final-Konstruktor-Parameter) und startet ihn wieder, falls er lief —
  /// [codes] bleibt dabei stabil.
  Future<void> setTarget(ScannerTarget target);

  Future<void> start();
  Future<void> stop();
  Future<void> toggleTorch();
  Future<void> switchCamera();

  /// Setzt die Kamera-Vergroesserung (0.0 = keine, 1.0 = maximal).
  /// No-op, wenn [supportsZoom] false ist.
  Future<void> setZoom(double scale);

  /// Analysiert ein Standbild (Dateipfad) in voller Aufloesung mit ALLEN
  /// unterstuetzten Formaten und liefert die erkannten Codes (leer = nichts
  /// erkannt). Deutlich robuster als der Live-Stream bei kleinen oder
  /// beschaedigten Codes.
  Future<List<String>> analyzePhoto(String path);

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

  /// Zaehlt stop()/setTarget()-Aufrufe. Ein noch laufendes start() darf
  /// `_started` NICHT mehr auf true setzen, wenn zwischenzeitlich gestoppt
  /// wurde (sonst startet setTarget die Kamera "aus dem Nichts" wieder).
  int _lifecycleEpoch = 0;

  /// Zuletzt gesetzter Zoom — wird nach einem Controller-Neuaufbau (setTarget)
  /// wieder angewendet, damit der Nutzer die Einstellung nicht verliert.
  double _zoom = 0;

  // Ziel-Hilfe (Reticle): EAN-13 ist quer/breit -> flaches, breites Rechteck,
  // mittig. Das Reticle ist REIN VISUELL — analysiert wird bewusst der GANZE
  // Frame. Frueher wurde hier zusaetzlich `scanWindow` gesetzt; die native
  // Widget->Textur-Umrechnung ist aber fehleranfaellig (mobile_scanner #1009/
  // #633: beim ersten Frame ist die Texturgroesse oft noch 0, das falsch
  // berechnete Fenster wird wegen des Update-Thresholds nie korrigiert) — die
  // Analysezone lag dann NEBEN dem sichtbaren Reticle und der Scanner erkannte
  // im Laden praktisch nichts. Volle Frame-Analyse ist fuer MLKit/Apple Vision
  // problemlos und erkennt Codes ueberall im Bild.
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
          // Kleine Import-Artikel tragen oft UPC-E — ohne dieses Format wurden
          // sie NIE erkannt (haeufige Ursache fuer "Scanner findet nichts").
          BarcodeFormat.upcE,
        ];
      case ScannerTarget.extended:
        // 1D bleibt aktiv, damit man im erweiterten Modus auch Produkte
        // scannen kann; dazu QR/DataMatrix (GS1-Inhalte mit MHD/Charge) und
        // ITF-14/Code-128 (Umkartons, Lieferanten-Etiketten).
        return const <BarcodeFormat>[
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
          BarcodeFormat.qrCode,
          BarcodeFormat.dataMatrix,
          BarcodeFormat.itf14,
          BarcodeFormat.code128,
        ];
    }
  }

  /// Formatliste fuer die Standbild-Analyse: immer ALLE unterstuetzten Formate
  /// — beim Foto zaehlt maximale Trefferchance, nicht Frame-Tempo.
  static const List<BarcodeFormat> _photoFormats = <BarcodeFormat>[
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
    BarcodeFormat.qrCode,
    BarcodeFormat.dataMatrix,
    BarcodeFormat.itf14,
    BarcodeFormat.code128,
  ];

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

  static bool get _isMobileDevice =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

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
  bool get supportsTorch => _isMobileDevice;

  @override
  bool get supportsZoom => _isMobileDevice;

  @override
  bool get supportsPhotoAnalysis => _isMobileDevice;

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
    _lifecycleEpoch++; // haengige start()-Futures des alten Controllers entwerten
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
    final epoch = _lifecycleEpoch;
    await _ensureController().start();
    // Kam waehrend des (langsamen) Kamera-Starts ein stop()/setTarget()
    // dazwischen, gilt dessen Zustand — nicht unserer.
    if (epoch != _lifecycleEpoch) return;
    _started = true;
    if (_zoom > 0 && supportsZoom) {
      // Nutzer-Zoom ueberlebt Formatwechsel/Neustart.
      unawaited(
        _controller?.setZoomScale(_zoom).catchError((Object _) {}),
      );
    }
  }

  @override
  Future<void> stop() async {
    _lifecycleEpoch++;
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
  Future<void> setZoom(double scale) async {
    if (!supportsZoom) return;
    _zoom = scale.clamp(0.0, 1.0);
    await _controller?.setZoomScale(_zoom);
  }

  @override
  Future<List<String>> analyzePhoto(String path) async {
    if (!supportsPhotoAnalysis) return const <String>[];
    final capture = await _ensureController().analyzeImage(
      path,
      formats: _photoFormats,
    );
    if (capture == null) return const <String>[];
    return capture.barcodes
        .map((barcode) => barcode.rawValue?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
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
          // KEIN scanWindow (siehe Kommentar am Reticle): analysiert wird der
          // ganze Frame, das Reticle ist nur eine sichtbare Ziel-Hilfe.
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
/// keine Gesten) — die Analyse laeuft auf dem ganzen Frame.
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
