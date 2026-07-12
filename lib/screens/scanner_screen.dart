import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/ean.dart';
import '../core/gs1.dart';
import '../models/app_user.dart';
import '../models/order_cart.dart';
import '../models/product.dart';
import '../models/product_batch.dart';
import '../models/scan_event.dart';
import '../models/site_definition.dart';
import '../models/stock_movement.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/team_provider.dart';
import '../services/barcode_scanner.dart';
import '../services/database_service.dart';
import '../services/scan_feedback.dart';
import '../theme/theme_extensions.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/goods_receipt_sheet.dart';
import '../widgets/price_history_sheet.dart';
import 'inventory_screen.dart' show formatCents, parseEuroToCents, showProductDialog;
import 'scan_statistik_screen.dart';

/// Betriebsart des Scanners.
enum _ScanMode {
  /// „Scan & Go": jeder Scan landet sofort im Bestellkorb (Standard) — schnelles
  /// Durchscannen wie an einer Selbstscan-Kasse, mit laufendem Warenkorb.
  order,

  /// Bestand buchen (Wareneingang/Abgang/Inventur/Preis je Artikel).
  book,

  /// Inventur-Sammelzaehlung.
  stocktake,
}

/// Barcode/EAN-Scanner der Warenwirtschaft. Sucht Artikel ueber ihren Barcode,
/// bucht Bestand, erkennt Preisabweichungen und legt unbekannte Artikel neu an.
///
/// Kamera- und Feedback-Zugriff laufen ueber Seams ([BarcodeScanner],
/// [ScanFeedback]), damit der Screen ohne echte Hardware widget-testbar bleibt.
/// Die Geschaeftslogik (Lookup/Buchung/Preis) liegt im [InventoryProvider].
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({
    super.key,
    this.parentLabel = 'Profil',
    this.scanner,
    this.feedback,
  });

  final String parentLabel;

  /// Im Test injizierbar (Fake). Standard: echte Kamera ([MobileScannerAdapter]).
  final BarcodeScanner? scanner;

  /// Im Test injizierbar (Noop). Standard: Ton + Haptik ([AudioHapticFeedback]).
  final ScanFeedback? feedback;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  late final BarcodeScanner _scanner;
  late final ScanFeedback _feedback;
  late final String _scanSessionId;
  final TextEditingController _manualController = TextEditingController();

  StreamSubscription<String>? _codesSub;

  String? _selectedSiteId;
  bool _scanning = false;
  String? _cameraError;

  // Letztes Ergebnis.
  Product? _match;
  List<Product> _multiMatches = const [];
  Product? _inactiveMatch;
  String? _notFoundCode;

  // Fachlich ausgewerteter GS1-Inhalt des letzten Scans (QR/DataMatrix mit
  // GTIN + MHD/Charge) — befuellt den gefuehrten Wareneingang vor.
  Gs1ScanData? _gs1Data;

  // Nicht-GS1-QR-Inhalt (URL/Freitext) des letzten Scans.
  String? _qrContent;

  // Foto-Fallback (Standbild-Analyse) laeuft gerade.
  bool _analyzingPhoto = false;

  // Nutzer-Zoom (0..1) fuer kleine/entfernte Codes.
  double _zoom = 0;

  // Startpunkt der Zeitmessung "wie lange bis zum Treffer" (Scan-Statistik):
  // gesetzt beim Kamera-Start und nach jedem verarbeiteten Ergebnis.
  DateTime? _scanTimingStart;

  // Die Kamera laeuft hinter modalen Sheets/Dialogen weiter — waehrend einer
  // offenen Interaktion (Wareneingang-Sheet, Auswahl, Preis-Dialog, ...)
  // duerfen neue Kamera-Codes NICHT verarbeitet werden, sonst stapeln sich
  // Sheets bzw. wechselt der Zustand unter dem offenen Dialog.
  bool _dialogOpen = false;

  /// Fuehrt eine modale Interaktion aus und blockiert solange die
  /// Verarbeitung neuer Kamera-Codes.
  Future<T> _withDialogGuard<T>(Future<T> Function() action) async {
    _dialogOpen = true;
    try {
      return await action();
    } finally {
      _dialogOpen = false;
    }
  }

  // Doppel-Scan-Entprellung + Buchungssperre.
  String _lastCode = '';
  DateTime? _lastCodeAt;
  bool _booking = false;
  int _bookingSeq = 0;
  int _quantity = 1;

  // Scan-Modus: Bestellen (Scan & Go, Standard) / Buchen / Inventur.
  _ScanMode _mode = _ScanMode.order;

  // Inventurmodus: Dauer-Scan in eine Zaehl-Session (productId -> Menge).
  final Map<String, int> _countByProduct = {};
  final Map<String, Product> _countedProducts = {};

  // Scan & Go: kurze Bestaetigung des zuletzt in den Korb gelegten Artikels.
  String? _lastAddedName;

  // Visueller Blitz (Erfolg/Fehler), weil Ton/Haptik auf Web/Desktop stumm sind.
  Color? _flashColor;
  Timer? _flashTimer;

  // Ton-Einstellung (im Laden lautlos betreibbar), geraeteweit persistiert.
  static const String _soundSettingKey = 'scanner_sound_enabled';
  bool _soundEnabled = true;

  // Dunkelheits-Hinweis: erscheint, wenn nach dem Start eine Weile lang gar
  // nichts erkannt wurde (Heuristik fuer schlechtes Licht) — nur wo es eine
  // Taschenlampe gibt (Handy). mobile_scanner liefert kein Umgebungslicht-Signal.
  bool _showDarkHint = false;
  Timer? _darkHintTimer;

  @override
  void initState() {
    super.initState();
    _scanner = widget.scanner ?? MobileScannerAdapter();
    _feedback = widget.feedback ?? AudioHapticFeedback();
    _scanSessionId = DateTime.now().microsecondsSinceEpoch.toString();
    WidgetsBinding.instance.addObserver(this);
    _codesSub = _scanner.codes.listen(_onCodeDetected, onError: (_) {});
    _loadSoundSetting();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initSiteAndMaybeStart();
    });
  }

  Future<void> _loadSoundSetting() async {
    final raw = await DatabaseService.getLocalSetting(_soundSettingKey);
    final enabled = raw != '0';
    if (!mounted) return;
    setState(() => _soundEnabled = enabled);
    _applySoundSetting();
  }

  void _applySoundSetting() {
    final feedback = _feedback;
    if (feedback is AudioHapticFeedback) {
      feedback.soundEnabled = _soundEnabled;
      feedback.hapticsEnabled = _soundEnabled;
    }
  }

  Future<void> _toggleSound() async {
    setState(() => _soundEnabled = !_soundEnabled);
    _applySoundSetting();
    await DatabaseService.saveLocalSetting(
      _soundSettingKey,
      _soundEnabled ? '1' : '0',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flashTimer?.cancel();
    _darkHintTimer?.cancel();
    _codesSub?.cancel();
    _manualController.dispose();
    unawaited(_scanner.dispose());
    unawaited(_feedback.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Kamera nicht dauerhaft laufen lassen (Akku/Datenschutz).
    if (state == AppLifecycleState.resumed) {
      if (_selectedSiteId != null) _startScanner();
    } else {
      _stopScanner();
    }
  }

  void _initSiteAndMaybeStart() {
    final sites = context.read<TeamProvider>().sites;
    if (sites.length == 1) {
      _selectedSiteId = sites.first.id;
    }
    if (_selectedSiteId != null) _startScanner();
    if (mounted) setState(() {});
  }

  void _startScanner() {
    if (_scanning || !_scanner.isAvailable) return;
    _scanning = true;
    _scanner.start().then((_) {
      // Erfolgreicher (Neu-)Start raeumt eine alte Fehleranzeige weg — sonst
      // bleibt die "Kamera nicht verfuegbar"-Box ueber dem laufenden Kamerabild
      // stehen, obwohl die Kamera laeuft (probleme #12).
      if (mounted && _cameraError != null) {
        setState(() => _cameraError = null);
      }
      _scanTimingStart = DateTime.now();
      _armDarkHint();
    }).catchError((Object error) {
      _scanning = false;
      if (mounted) {
        setState(() {
          _cameraError =
              'Kamera nicht verfuegbar. Bitte Kamera-Berechtigung pruefen oder '
              'den Barcode manuell eingeben.';
        });
      }
    });
  }

  void _stopScanner() {
    if (!_scanning) return;
    _scanning = false;
    _cancelDarkHint();
    unawaited(_scanner.stop());
  }

  /// Startet die Dunkelheits-Heuristik: kommt in ~4s keine einzige Erkennung,
  /// bieten wir das Einschalten der Taschenlampe an (nur wo verfuegbar).
  void _armDarkHint() {
    _darkHintTimer?.cancel();
    if (!_scanner.supportsTorch) return;
    _darkHintTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _scanning) setState(() => _showDarkHint = true);
    });
  }

  void _cancelDarkHint() {
    _darkHintTimer?.cancel();
    _darkHintTimer = null;
    if (_showDarkHint && mounted) setState(() => _showDarkHint = false);
  }

  /// Schaltet zwischen reinem Handels-Barcode-Scan (schnell) und dem
  /// erweiterten Modus (QR/DataMatrix/Umkarton-Codes) um.
  Future<void> _toggleScanTarget() async {
    final next = _scanner.target == ScannerTarget.extended
        ? ScannerTarget.retail
        : ScannerTarget.extended;
    await _scanner.setTarget(next);
    if (!mounted) return;
    setState(() {});
    _showSnack(
      next == ScannerTarget.extended
          ? 'Erweiterter Modus an — QR, DataMatrix und Karton-Codes werden '
              'mitgelesen (GS1-Codes befuellen MHD/Charge automatisch).'
          : 'Erweiterter Modus aus — nur Handels-Barcodes (schneller).',
    );
  }

  // --- Scan-Verarbeitung --------------------------------------------------

  void _onCodeDetected(String code) {
    // Offene Interaktion (Sheet/Dialog) -> Kamera-Codes verwerfen.
    if (_dialogOpen) return;
    final now = DateTime.now();
    // Erkennung angekommen -> Kamera sieht etwas: Dunkel-Hinweis zuruecknehmen.
    _cancelDarkHint();
    // Gleichen Code ~1s ignorieren -> kein Dauer-Wiederbeepen / Doppelscan, aber
    // kurz genug fuer fluessiges Mehrfach-Zaehlen desselben Artikels (Inventur).
    if (code == _lastCode &&
        _lastCodeAt != null &&
        now.difference(_lastCodeAt!) < const Duration(milliseconds: 1000)) {
      return;
    }
    _lastCode = code;
    _lastCodeAt = now;
    _handleCode(code, source: 'camera');
  }

  void _onManualSearch() {
    final code = _manualController.text.trim();
    if (code.isEmpty) return;
    _lastCode = code;
    _lastCodeAt = DateTime.now();
    _handleCode(code, source: 'manual');
  }

  // --- Scan-Statistik-Hilfen ------------------------------------------------

  String get _platformName => kIsWeb ? 'web' : defaultTargetPlatform.name;

  String get _modeValue {
    switch (_mode) {
      case _ScanMode.order:
        return 'order';
      case _ScanMode.book:
        return 'book';
      case _ScanMode.stocktake:
        return 'stocktake';
    }
  }

  /// Protokolliert den Scan-Ausgang fire-and-forget (Statistik/Fehleranalyse).
  /// Zeit-bis-Treffer nur fuer Kamera-Scans (Tippdauer ist keine Zielzeit).
  void _logScan({
    required String code,
    required ScanOutcome outcome,
    required String source,
    String? productId,
  }) {
    int? timeToHitMs;
    final startedAt = _scanTimingStart;
    if (source == 'camera' && startedAt != null) {
      timeToHitMs = DateTime.now().difference(startedAt).inMilliseconds;
    }
    // Naechste Messung beginnt jetzt (Zeit bis zum naechsten Ergebnis).
    _scanTimingStart = DateTime.now();
    unawaited(
      context.read<InventoryProvider>().logScanEvent(
            code: code,
            outcome: outcome,
            siteId: _selectedSiteId,
            mode: _modeValue,
            source: source,
            timeToHitMs: timeToHitMs,
            productId: productId,
            platform: _platformName,
          ),
    );
  }

  Future<void> _handleCode(String rawCode, {required String source}) async {
    final code = rawCode.trim();
    if (code.isEmpty) return;

    // Pruefziffer fuer Standard-Laengen erzwingen (EAN-13/8, UPC-A/UPC-E,
    // GTIN-14); proprietaere Hauscodes anderer Laenge passieren.
    if (!isPlausibleRetailCode(code)) {
      _flash(false);
      unawaited(_feedback.failure());
      _showSnack('Ungueltiger Barcode (Pruefziffer stimmt nicht).');
      _logScan(code: code, outcome: ScanOutcome.invalidChecksum, source: source);
      return;
    }

    final siteId = _selectedSiteId;
    if (siteId == null) {
      _flash(false);
      unawaited(_feedback.failure());
      _showSnack('Bitte zuerst einen Laden waehlen.');
      return;
    }

    final inventory = context.read<InventoryProvider>();

    // Fachliche QR-/GS1-Auswertung: Nicht-Standard-Codes (QR-Inhalte,
    // GS1-Element-Strings, Digital Links) werden interpretiert statt blind
    // nachgeschlagen. Reihenfolge: exakter Treffer (Hauscodes!) gewinnt vor
    // der GS1-Deutung; nur wenn beides nichts ergibt, zaehlt der Inhalt als
    // QR-Text.
    var lookupCode = code;
    Gs1ScanData? gs1;
    if (!looksLikeEan(code) &&
        inventory
            .productsByBarcode(code, siteId: siteId, includeInactive: true)
            .isEmpty) {
      gs1 = parseGs1(code);
      if (gs1 != null && gs1.hasGtin) {
        lookupCode = gs1.gtin!;
      } else if (code.length > 20 || !RegExp(r'^\d+$').hasMatch(code)) {
        // Kein Produktcode und kein GS1 mit GTIN -> als QR-Inhalt anzeigen
        // (URL/Freitext), nicht als "Artikel nicht gefunden" verwirren.
        // Bewusst KEINE Telemetrie: fremde QR-Inhalte (URLs, Kontakte, ...)
        // sind keine Produkt-Fehlversuche und gehoeren nicht in ein
        // append-only Log (Datenschutz).
        _flash(false);
        unawaited(_feedback.failure());
        setState(() {
          _match = null;
          _multiMatches = const [];
          _inactiveMatch = null;
          _notFoundCode = null;
          _gs1Data = null;
          _qrContent = code;
        });
        return;
      }
    }

    final matches = inventory.productsByBarcode(lookupCode, siteId: siteId);

    // Ausgang zentral protokollieren (fuer alle Modi identisch).
    _logScan(
      code: code,
      outcome: matches.length == 1
          ? ScanOutcome.matched
          : (matches.length > 1 ? ScanOutcome.multiMatch : ScanOutcome.notFound),
      source: source,
      productId: matches.length == 1 ? matches.first.id : null,
    );

    // GS1-Zusatzdaten (MHD/Charge) fuer den gefuehrten Wareneingang merken.
    _gs1Data = gs1;
    _qrContent = null;

    switch (_mode) {
      case _ScanMode.stocktake:
        _handleStocktakeScan(matches);
        return;
      case _ScanMode.order:
        await _handleOrderScan(inventory, lookupCode, siteId, matches);
        return;
      case _ScanMode.book:
        break; // Buchen-Modus weiter unten
    }

    // --- Buchen-Modus: Artikel-Karte mit Buchungs-Buttons zeigen ---
    if (matches.isNotEmpty) {
      _flash(true);
      unawaited(_feedback.success());
      setState(() {
        _multiMatches = matches.length > 1 ? matches : const [];
        _match = matches.length == 1 ? matches.first : null;
        _inactiveMatch = null;
        _notFoundCode = null;
        _quantity = 1;
      });
      return;
    }

    // Kein aktiver Treffer -> deaktivierten Artikel suchen (Reaktivierung statt
    // Neuanlage anbieten).
    final inactive = inventory.productsByBarcode(
      lookupCode,
      siteId: siteId,
      includeInactive: true,
    );
    _flash(false);
    unawaited(_feedback.failure());
    setState(() {
      _match = null;
      _multiMatches = const [];
      _inactiveMatch = inactive.isNotEmpty ? inactive.first : null;
      _notFoundCode = lookupCode;
    });
  }

  /// Foto-Fallback fuer beschaedigte/winzige Codes: Standbild in voller
  /// Aufloesung aufnehmen und mit allen Formaten analysieren — deutlich
  /// robuster als der Live-Stream.
  Future<void> _scanPhoto() async {
    if (_analyzingPhoto) return;
    setState(() => _analyzingPhoto = true);
    try {
      final photo = await ImagePicker().pickImage(source: ImageSource.camera);
      if (photo == null || !mounted) return;
      final codes = await _scanner.analyzePhoto(photo.path);
      if (!mounted) return;
      if (codes.isEmpty) {
        _flash(false);
        unawaited(_feedback.failure());
        _showSnack(
          'Kein Code im Foto erkannt. Naeher herangehen, fuer Licht sorgen '
          'oder den Code manuell eingeben.',
        );
        return;
      }
      // Bei mehreren erkannten Codes den plausibelsten (Pruefziffer ok) nehmen.
      final best =
          codes.firstWhereOrNull(isPlausibleRetailCode) ?? codes.first;
      await _handleCode(best, source: 'photo');
    } catch (error) {
      if (mounted) _showSnack('Foto-Scan fehlgeschlagen: $error');
    } finally {
      if (mounted) setState(() => _analyzingPhoto = false);
    }
  }

  // --- Scan & Go (Bestellen) ----------------------------------------------

  /// Inventur: jeder Scan zaehlt +1 in die Sammelliste.
  void _handleStocktakeScan(List<Product> matches) {
    if (matches.length == 1) {
      final product = matches.first;
      _flash(true);
      unawaited(_feedback.success());
      setState(() {
        _countedProducts[product.id!] = product;
        _countByProduct[product.id!] = (_countByProduct[product.id!] ?? 0) + 1;
      });
    } else if (matches.length > 1) {
      _flash(false);
      unawaited(_feedback.failure());
      _showSnack('Mehrere Artikel mit diesem Barcode — im Buchen-Modus zaehlen.');
    } else {
      _flash(false);
      unawaited(_feedback.failure());
      _showSnack('Artikel nicht vorhanden — Inventur nur fuer bekannte Artikel.');
    }
  }

  /// Scan & Go: legt den gescannten Artikel direkt in den Bestellkorb. Bei
  /// mehreren Treffern wird zur Auswahl gefragt, bei unbekanntem Code die
  /// Neuanlage angeboten.
  Future<void> _handleOrderScan(
    InventoryProvider inventory,
    String code,
    String siteId,
    List<Product> matches,
  ) async {
    if (matches.length == 1) {
      await _addScannedToCart(inventory, matches.first);
      return;
    }
    if (matches.length > 1) {
      _flash(true);
      unawaited(_feedback.success());
      await _chooseAndAddToCart(inventory, matches);
      return;
    }
    final inactive = inventory.productsByBarcode(
      code,
      siteId: siteId,
      includeInactive: true,
    );
    _flash(false);
    unawaited(_feedback.failure());
    if (!mounted) return;
    setState(() {
      _inactiveMatch = inactive.isNotEmpty ? inactive.first : null;
      _notFoundCode = code;
    });
  }

  Future<void> _addScannedToCart(
    InventoryProvider inventory,
    Product product,
  ) async {
    try {
      await inventory.addToCart(product: product, quantity: 1);
    } catch (error) {
      // Erst bei Fehler Misserfolgs-Feedback geben — vorher wurde Erfolgston/
      // -blitz schon VOR dem await ausgeloest, obwohl das Hinzufuegen scheitern
      // konnte (widerspruechliches Signal an der Kasse, probleme #49).
      if (mounted) {
        unawaited(_feedback.failure());
        _showSnack('Fehler beim Hinzufuegen: $error');
      }
      return;
    }
    // Erfolgs-Feedback (wie an einer Selbstscan-Kasse) erst nach erfolgreichem
    // Hinzufuegen.
    _flash(true);
    unawaited(_feedback.success());
    if (!mounted) return;
    setState(() {
      _lastAddedName = product.name;
      _notFoundCode = null;
      _inactiveMatch = null;
    });
  }

  Future<void> _chooseAndAddToCart(
    InventoryProvider inventory,
    List<Product> matches,
  ) async {
    final chosen = await _withDialogGuard(
      () => showModalBottomSheet<Product>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child:
                    Text('Mehrere Artikel mit diesem Barcode — bitte waehlen:'),
              ),
              for (final product in matches)
                ListTile(
                  title: Text(product.name),
                  subtitle: Text(
                    'Bestand: ${product.currentStock} ${product.unit} · '
                    'VK ${formatCents(product.sellingPriceCents)}',
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(product),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    try {
      await inventory.addToCart(product: chosen, quantity: 1);
    } catch (error) {
      if (mounted) _showSnack('Fehler beim Hinzufuegen: $error');
      return;
    }
    if (mounted) setState(() => _lastAddedName = chosen.name);
  }

  void _flash(bool success) {
    // Wird auch nach Buchungs-awaits aufgerufen -> Screen koennte schon weg sein
    // (Theme.of/setState wuerden auf disposed State werfen).
    if (!mounted) return;
    final colors = Theme.of(context).appColors;
    _flashTimer?.cancel();
    setState(() => _flashColor = success ? colors.success : colors.warning);
    _flashTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _flashColor = null);
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Buchungen ----------------------------------------------------------

  Product _liveProduct(InventoryProvider inventory, Product product) {
    if (product.id == null) return product;
    return inventory.products.firstWhereOrNull((p) => p.id == product.id) ??
        product;
  }

  String _nextMutationId(Product product, String suffix) {
    _bookingSeq += 1;
    return '$_scanSessionId::${product.id}::$_bookingSeq::$suffix';
  }

  /// Gefuehrter Wareneingang: EIN Ablauf fuer Menge + optionales MHD +
  /// optionale Charge. GS1-Scans (DataMatrix/QR mit AI 17/10/30) befuellen die
  /// Felder vor — ein Karton-Scan wird so zum Zwei-Tap-Wareneingang.
  Future<void> _receiveGuided(Product product) async {
    if (_booking || product.id == null) return;
    final gs1 = _gs1Data;
    final input = await _withDialogGuard(
      () => showGoodsReceiptSheet(
        context,
        product: product,
        initialQuantity: (gs1?.quantity != null && gs1!.quantity! > 0)
            ? gs1.quantity!
            : _quantity,
        initialExpiry: gs1?.expiryDate,
        initialLot: gs1?.lot,
      ),
    );
    if (input == null || !mounted) return;
    await _receive(product, input);
  }

  Future<void> _receive(Product product, GoodsReceiptInput input) async {
    final quantity = input.quantity;
    if (_booking || product.id == null || quantity <= 0) return;
    setState(() => _booking = true);
    try {
      await context.read<InventoryProvider>().adjustStock(
            productId: product.id!,
            delta: quantity,
            type: StockMovementType.receipt,
            reason: 'Scan-Wareneingang',
            clientMutationId: _nextMutationId(product, 'receipt:$quantity'),
          );
      // Bestand ist gebucht — MHD/Charge (falls erfasst) direkt hinterher.
      // Ein Teil-Fehler wird explizit gemeldet, damit der Nutzer weiss, was
      // gebucht wurde und was nicht.
      if (input.hasBatch) {
        if (!mounted) return;
        try {
          await context.read<InventoryProvider>().saveBatch(
                ProductBatch(
                  orgId: product.orgId,
                  siteId: product.siteId,
                  productId: product.id!,
                  productName: product.name,
                  expiryDate: ProductBatch.normalizeDay(input.expiryDate!),
                  quantity: quantity,
                  note: input.lot,
                ),
              );
        } catch (error) {
          _flash(false);
          unawaited(_feedback.failure());
          _showSnack(
            'Bestand gebucht (+$quantity), aber MHD-Charge fehlgeschlagen: '
            '$error',
          );
          return;
        }
      }
      _flash(true);
      unawaited(_feedback.success());
      final expiry = input.expiryDate;
      final expiryText = expiry == null
          ? ''
          : ' — MHD ${expiry.day.toString().padLeft(2, '0')}.'
              '${expiry.month.toString().padLeft(2, '0')}.${expiry.year} erfasst';
      _showSnack('Wareneingang: +$quantity ${product.unit} gebucht$expiryText.');
      _resetQuantity();
      if (mounted && _gs1Data != null) setState(() => _gs1Data = null);
    } catch (error) {
      _flash(false);
      unawaited(_feedback.failure());
      _showSnack('Fehler beim Buchen: $error');
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  Future<void> _issue(Product product, int quantity) async {
    if (_booking || product.id == null || quantity <= 0) return;
    setState(() => _booking = true);
    try {
      final error = await context.read<InventoryProvider>().issueStock(
            product: product,
            quantity: quantity,
            reason: 'Scan-Abgang',
            clientMutationId: _nextMutationId(product, 'issue:$quantity'),
          );
      if (error != null) {
        _flash(false);
        unawaited(_feedback.failure());
        _showSnack(error);
      } else {
        _flash(true);
        unawaited(_feedback.success());
        _showSnack('Abgang: -$quantity ${product.unit} gebucht.');
        _resetQuantity();
      }
    } catch (error) {
      _flash(false);
      unawaited(_feedback.failure());
      _showSnack('Fehler beim Buchen: $error');
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  void _resetQuantity() {
    if (mounted) setState(() => _quantity = 1);
  }

  Future<void> _stocktake(Product product) async {
    final controller =
        TextEditingController(text: product.currentStock.toString());
    final counted = await _withDialogGuard(
      () => showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Inventur'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Gezaehlter Bestand (${product.unit})',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(int.tryParse(controller.text.trim())),
            child: const Text('Setzen'),
          ),
        ],
      ),
      ),
    );
    controller.dispose();
    if (counted == null || product.id == null || !mounted) return;
    if (_booking) return;
    setState(() => _booking = true);
    try {
      await context
          .read<InventoryProvider>()
          .recordStocktake(product: product, countedStock: counted);
      _flash(true);
      unawaited(_feedback.success());
      _showSnack('Inventur gebucht: $counted ${product.unit}.');
    } catch (error) {
      _flash(false);
      _showSnack('Fehler bei der Inventur: $error');
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  // --- Preisabweichung ----------------------------------------------------

  Future<void> _changePrice(Product product) =>
      _withDialogGuard(() => _changePriceFlow(product));

  Future<void> _changePriceFlow(Product product) async {
    final controller = TextEditingController(
      text: product.sellingPriceCents == null
          ? ''
          : (product.sellingPriceCents! / 100).toStringAsFixed(2).replaceAll('.', ','),
    );
    final entered = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: 20 + MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Verkaufspreis ${product.name}',
                style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Aktuell: ${formatCents(product.sellingPriceCents)}',
                style: Theme.of(sheetContext).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Neuer VK',
                suffixText: '€',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  Navigator.of(sheetContext).pop(controller.text),
              child: const Text('Weiter'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (entered == null || !mounted) return;

    final newCents = parseEuroToCents(entered);
    if (newCents == null) {
      _showSnack('Ungueltiger Preis.');
      return;
    }
    if (newCents == product.sellingPriceCents) {
      _showSnack('Preis unveraendert.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Preis uebernehmen?'),
        content: Text(
          'VK ${formatCents(product.sellingPriceCents)} → '
          '${formatCents(newCents)} fuer ${product.name} uebernehmen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Uebernehmen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await context
          .read<InventoryProvider>()
          .updateProductPrices(product, newSellingCents: newCents);
      _flash(true);
      unawaited(_feedback.success());
      _showSnack('Preis aktualisiert: ${formatCents(newCents)}.');
    } catch (error) {
      _showSnack('Fehler beim Preis-Update: $error');
    }
  }

  // --- Neuanlage / Reaktivierung ------------------------------------------

  /// Erfasst beim Wareneingang ein Mindesthaltbarkeitsdatum (MHD) als Charge
  /// ([ProductBatch]) mit der aktuell eingestellten Menge. Optional — nur fuer
  /// Ware mit MHD (Getraenke/Suesswaren) relevant.
  Future<void> _captureExpiry(Product product) async {
    if (_booking || product.id == null) return;
    final today = DateTime.now();
    final picked = await _withDialogGuard(
      () => showDatePicker(
        context: context,
        initialDate: DateTime(today.year, today.month, today.day)
            .add(const Duration(days: 7)),
        firstDate: DateTime(today.year - 1),
        lastDate: DateTime(today.year + 5),
        helpText: 'Mindesthaltbarkeitsdatum (MHD)',
        locale: const Locale('de', 'DE'),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _booking = true);
    try {
      await context.read<InventoryProvider>().saveBatch(
            ProductBatch(
              orgId: product.orgId,
              siteId: product.siteId,
              productId: product.id!,
              productName: product.name,
              expiryDate: ProductBatch.normalizeDay(picked),
              quantity: _quantity,
            ),
          );
      _flash(true);
      unawaited(_feedback.success());
      final d = '${picked.day.toString().padLeft(2, '0')}.'
          '${picked.month.toString().padLeft(2, '0')}.${picked.year}';
      _showSnack('MHD erfasst: ${product.name} — haltbar bis $d.');
    } catch (error) {
      _flash(false);
      unawaited(_feedback.failure());
      _showSnack('Fehler beim Speichern des MHD: $error');
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  Future<void> _createNew(String barcode) =>
      _withDialogGuard(() => _createNewFlow(barcode));

  Future<void> _createNewFlow(String barcode) async {
    final inventory = context.read<InventoryProvider>();
    final sites = context.read<TeamProvider>().sites;
    final siteId = _selectedSiteId ?? (sites.isNotEmpty ? sites.first.id : null);
    if (sites.isEmpty) {
      _showSnack('Bitte zuerst unter Personal → Organisation einen Standort anlegen.');
      return;
    }
    final result = await showProductDialog(
      context,
      sites: sites,
      suppliers: inventory.activeSuppliers,
      defaultSiteId: siteId,
      initialBarcode: barcode,
    );
    if (result == null || !mounted) return;

    // Harte Barcode-Eindeutigkeit je Laden: Duplikat wird nicht mehr per
    // Dialog durchgewunken („Trotzdem anlegen" entfaellt) — saveProduct lehnt
    // es ohnehin ab. Hier nur die freundlichere Frueh-Meldung.
    final code = result.barcode?.trim() ?? '';
    if (code.isNotEmpty) {
      final existing = inventory.productsByBarcode(
        code,
        siteId: result.siteId,
        includeInactive: true,
      );
      if (existing.isNotEmpty) {
        _showSnack(
          'Barcode bereits vergeben: „${existing.first.name}" traegt diesen '
          'Code im gewaehlten Laden. Jeder Barcode darf je Laden nur an einem '
          'Artikel haengen.',
        );
        return;
      }
    }

    try {
      await inventory.saveProduct(result);
      if (!mounted) return;
      _showSnack('Artikel angelegt.');
      // Frisch angelegten Artikel direkt anzeigen (per Barcode nachladen).
      setState(() {
        _notFoundCode = null;
        _inactiveMatch = null;
        _match = code.isEmpty
            ? null
            : inventory.productByBarcode(code, siteId: result.siteId);
      });
    } catch (error) {
      if (mounted) _showSnack('Fehler beim Anlegen: $error');
    }
  }

  Future<void> _reactivate(Product product) async {
    try {
      await context
          .read<InventoryProvider>()
          .saveProduct(product.copyWith(isActive: true));
      if (!mounted) return;
      _showSnack('Artikel reaktiviert.');
      setState(() {
        _inactiveMatch = null;
        _notFoundCode = null;
        _match = product.copyWith(isActive: true);
      });
    } catch (error) {
      if (mounted) _showSnack('Fehler beim Reaktivieren: $error');
    }
  }

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final inventory = context.watch<InventoryProvider>();
    final sites = context.watch<TeamProvider>().sites;

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: widget.parentLabel,
            onTap: () => Navigator.of(context).pop(),
          ),
          const BreadcrumbItem(label: 'Scanner'),
        ],
        actions: [
          IconButton(
            tooltip: _scanner.target == ScannerTarget.extended
                ? 'Erweiterten Modus aus (nur Handels-Barcodes)'
                : 'Erweiterter Modus: QR, DataMatrix & Karton-Codes',
            icon: Icon(
              _scanner.target == ScannerTarget.extended
                  ? Icons.qr_code_2
                  : Icons.qr_code_scanner_outlined,
            ),
            onPressed: _toggleScanTarget,
          ),
          IconButton(
            tooltip: 'Scan-Statistik',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ScanStatistikScreen(initialSiteId: _selectedSiteId),
                ),
              );
            },
          ),
          IconButton(
            tooltip: _soundEnabled
                ? 'Ton & Vibration aus'
                : 'Ton & Vibration an',
            icon: Icon(
              _soundEnabled ? Icons.volume_up_outlined : Icons.volume_off_outlined,
            ),
            onPressed: _toggleSound,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _buildBody(context, profile, inventory, sites),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppUserProfile? profile,
    InventoryProvider inventory,
    List<SiteDefinition> sites,
  ) {
    if (profile == null || !profile.canUseScanner) {
      return const _CenteredHint('Keine Berechtigung fuer den Scanner.');
    }
    if (sites.isEmpty) {
      return const _CenteredHint(
        'Bitte zuerst unter Personal → Organisation einen Standort anlegen.',
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _buildSiteHeader(context, sites),
            const SizedBox(height: 12),
            _buildModeSelector(context),
            const SizedBox(height: 12),
            if (_selectedSiteId == null)
              const _CenteredHint(
                'Bitte oben den Laden waehlen, um zu scannen.',
              )
            else ...[
              _buildScanArea(context),
              const SizedBox(height: 12),
              _buildManualEntry(context),
              const SizedBox(height: 16),
              _buildResult(context, inventory),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSiteHeader(BuildContext context, List<SiteDefinition> sites) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.storefront_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: sites.length == 1
                  ? Text(
                      'Laden: ${sites.first.name}',
                      style: theme.textTheme.titleMedium,
                    )
                  : DropdownButtonFormField<String>(
                      initialValue: _selectedSiteId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Laden',
                        border: InputBorder.none,
                      ),
                      hint: const Text('Laden waehlen'),
                      items: [
                        for (final site in sites)
                          DropdownMenuItem(
                            value: site.id,
                            child: Text(site.name),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedSiteId = value;
                          _match = null;
                          _multiMatches = const [];
                          _inactiveMatch = null;
                          _notFoundCode = null;
                          _gs1Data = null;
                          _qrContent = null;
                        });
                        if (value != null) _startScanner();
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanArea(BuildContext context) {
    if (!_scanner.isAvailable) {
      return _CenteredHint(
        _cameraError ??
            'Kamera auf diesem Geraet nicht verfuegbar — bitte den Barcode '
                'manuell eingeben.',
      );
    }
    return Column(
      children: [
        _buildCameraPreview(context),
        if (_scanner.supportsZoom) _buildZoomRow(context),
      ],
    );
  }

  /// Zoom fuer kleine/weit entfernte Barcodes (zusaetzlich zum Android-
  /// autoZoom, das nur automatisch heranfaehrt).
  Widget _buildZoomRow(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.zoom_out, size: 20),
        Expanded(
          child: Slider(
            value: _zoom,
            onChanged: (value) {
              setState(() => _zoom = value);
              unawaited(_scanner.setZoom(value));
            },
          ),
        ),
        const Icon(Icons.zoom_in, size: 20),
      ],
    );
  }

  Widget _buildCameraPreview(BuildContext context) {
    final flash = _flashColor;
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _scanner.buildPreview(context),
            // Blitz-Rahmen bei Erfolg/Fehler.
            if (flash != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: flash, width: 6),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            if (_cameraError != null)
              Container(
                color: Colors.black54,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(16),
                child: Text(
                  _cameraError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            if (_showDarkHint && _cameraError == null)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      unawaited(_scanner.toggleTorch());
                      _cancelDarkHint();
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.flashlight_on_outlined, color: Colors.white),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Nichts erkannt — zu dunkel? Tippen für Licht.',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                children: [
                  if (_scanner.supportsTorch)
                    _CameraButton(
                      icon: Icons.flashlight_on_outlined,
                      tooltip: 'Taschenlampe',
                      onPressed: () => unawaited(_scanner.toggleTorch()),
                    ),
                  if (_scanner.supportsTorch) const SizedBox(width: 8),
                  if (_scanner.supportsTorch)
                    _CameraButton(
                      icon: Icons.cameraswitch_outlined,
                      tooltip: 'Kamera wechseln',
                      onPressed: () => unawaited(_scanner.switchCamera()),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualEntry(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _manualController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _onManualSearch(),
                decoration: const InputDecoration(
                  labelText: 'Barcode manuell eingeben',
                  prefixIcon: Icon(Icons.keyboard_outlined),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _onManualSearch,
              child: const Text('Suchen'),
            ),
          ],
        ),
        if (_scanner.supportsPhotoAnalysis) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _analyzingPhoto ? null : _scanPhoto,
            icon: _analyzingPhoto
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_camera_outlined),
            label: Text(
              _analyzingPhoto
                  ? 'Foto wird ausgewertet …'
                  : 'Foto scannen (kleiner/beschaedigter Code)',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildModeSelector(BuildContext context) {
    return SegmentedButton<_ScanMode>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: _ScanMode.order, label: Text('Bestellen')),
        ButtonSegment(value: _ScanMode.book, label: Text('Buchen')),
        ButtonSegment(value: _ScanMode.stocktake, label: Text('Inventur')),
      ],
      selected: {_mode},
      onSelectionChanged: (selection) => _setMode(selection.first),
    );
  }

  Future<void> _setMode(_ScanMode mode) async {
    if (mode == _mode) return;
    // Beim Verlassen des Inventurmodus mit offener Zaehlung nachfragen.
    if (_mode == _ScanMode.stocktake && _countByProduct.isNotEmpty) {
      final discard = await _withDialogGuard(
        () => showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Inventur verwerfen?'),
            content: Text(
              '${_countByProduct.length} gezaehlte Artikel gehen verloren.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Weiter zaehlen'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Verwerfen'),
              ),
            ],
          ),
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() {
      _mode = mode;
      _countByProduct.clear();
      _countedProducts.clear();
      _match = null;
      _multiMatches = const [];
      _inactiveMatch = null;
      _notFoundCode = null;
      _lastAddedName = null;
      _gs1Data = null;
      _qrContent = null;
      // Entprell-Zustand zuruecksetzen, damit derselbe Artikel direkt nach
      // einem Moduswechsel erneut gescannt werden kann (sonst 2s verschluckt,
      // probleme #50).
      _lastCode = '';
      _lastCodeAt = null;
    });
    _scanTimingStart = DateTime.now();
  }

  Widget _buildInventorySession(
    BuildContext context,
    InventoryProvider inventory,
  ) {
    if (_countByProduct.isEmpty) {
      return const _CenteredHint(
        'Inventurmodus: Scanne Artikel, um Stueckzahlen zu zaehlen. '
        'Jeder Scan zaehlt +1.',
      );
    }
    final ids = _countByProduct.keys.toList();
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Gezaehlt: ${_countByProduct.length} Artikel',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final id in ids)
            _buildCountRow(context, inventory, id),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: _booking ? null : () => _finishInventory(inventory),
              icon: const Icon(Icons.fact_check_outlined),
              label: Text('Inventur abschliessen (${_countByProduct.length})'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountRow(
    BuildContext context,
    InventoryProvider inventory,
    String productId,
  ) {
    final product = _countedProducts[productId]!;
    final counted = _countByProduct[productId] ?? 0;
    final live = _liveProduct(inventory, product);
    final delta = counted - live.currentStock;
    final theme = Theme.of(context);
    final deltaColor = delta == 0
        ? theme.colorScheme.onSurfaceVariant
        : (delta > 0 ? theme.appColors.success : theme.appColors.warning);
    return ListTile(
      title: Text(product.name),
      subtitle: Text(
        'System: ${live.currentStock} ${product.unit} · '
        'Diff: ${delta >= 0 ? '+' : ''}$delta',
        style: theme.textTheme.bodySmall?.copyWith(color: deltaColor),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove),
            tooltip: 'Weniger',
            onPressed: () => _changeCount(productId, -1),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$counted',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Mehr',
            onPressed: () => _changeCount(productId, 1),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Entfernen',
            onPressed: () => setState(() {
              _countByProduct.remove(productId);
              _countedProducts.remove(productId);
            }),
          ),
        ],
      ),
    );
  }

  void _changeCount(String productId, int delta) {
    final next = (_countByProduct[productId] ?? 0) + delta;
    setState(() {
      if (next <= 0) {
        _countByProduct.remove(productId);
        _countedProducts.remove(productId);
      } else {
        _countByProduct[productId] = next;
      }
    });
  }

  Future<void> _finishInventory(InventoryProvider inventory) async {
    if (_booking || _countByProduct.isEmpty) return;
    setState(() => _booking = true);

    // Differenzen VOR dem Buchen erfassen (recordStocktake aendert den Bestand).
    final lines = <({String name, int counted, int oldStock})>[];
    for (final entry in _countByProduct.entries) {
      final product = _liveProduct(inventory, _countedProducts[entry.key]!);
      lines.add((
        name: product.name,
        counted: entry.value,
        oldStock: product.currentStock,
      ));
    }

    var failed = 0;
    for (final entry in _countByProduct.entries) {
      final product = _liveProduct(inventory, _countedProducts[entry.key]!);
      try {
        await inventory.recordStocktake(
          product: product,
          countedStock: entry.value,
        );
      } catch (_) {
        failed++;
      }
    }

    if (!mounted) return;
    final adjusted = lines.where((l) => l.counted != l.oldStock).length;
    final totalDelta =
        lines.fold<int>(0, (sum, l) => sum + (l.counted - l.oldStock));

    setState(() {
      _booking = false;
      _countByProduct.clear();
      _countedProducts.clear();
    });
    _flash(failed == 0);
    unawaited(failed == 0 ? _feedback.success() : _feedback.failure());

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Inventur abgeschlossen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${lines.length} Artikel inventarisiert.'),
            Text('$adjusted mit Abweichung.'),
            Text(
              'Gesamtdifferenz: ${totalDelta >= 0 ? '+' : ''}$totalDelta Stueck.',
            ),
            if (failed > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '$failed Artikel konnten nicht gebucht werden.',
                  style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
                ),
              ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context, InventoryProvider inventory) {
    switch (_mode) {
      case _ScanMode.stocktake:
        return _buildInventorySession(context, inventory);
      case _ScanMode.order:
        return _buildOrderSession(context, inventory);
      case _ScanMode.book:
        break;
    }
    if (_multiMatches.isNotEmpty) {
      return _buildMultiMatches(context);
    }
    if (_match != null) {
      final live = _liveProduct(inventory, _match!);
      return _buildMatchCard(context, live);
    }
    if (_inactiveMatch != null) {
      return _buildInactiveCard(context, _inactiveMatch!);
    }
    if (_qrContent != null) {
      return _buildQrContentCard(context, _qrContent!);
    }
    if (_notFoundCode != null) {
      return _buildNotFoundCard(context, _notFoundCode!);
    }
    return const _CenteredHint(
      'Richte die Kamera auf einen Barcode oder gib ihn manuell ein.',
    );
  }

  /// Nicht-GS1-QR-Inhalt (URL/Freitext): Inhalt zeigen + kopieren statt
  /// verwirrendem „Artikel nicht gefunden".
  Widget _buildQrContentCard(BuildContext context, String content) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('QR-Inhalt erkannt', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(
              content,
              maxLines: 6,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: content));
                _showSnack('Inhalt kopiert.');
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Inhalt kopieren'),
            ),
          ],
        ),
      ),
    );
  }

  // --- Scan & Go: laufender Warenkorb -------------------------------------

  Widget _buildOrderSession(BuildContext context, InventoryProvider inventory) {
    final cart = inventory.orderCartForSite(_selectedSiteId);
    final items = cart?.items ?? const <OrderListItem>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_lastAddedName != null) ...[
          _LastAddedBanner(name: _lastAddedName!),
          const SizedBox(height: 8),
        ],
        if (_qrContent != null) ...[
          _buildQrContentCard(context, _qrContent!),
          const SizedBox(height: 8),
        ] else if (_notFoundCode != null) ...[
          _buildNotFoundCard(context, _notFoundCode!),
          const SizedBox(height: 8),
        ] else if (_inactiveMatch != null) ...[
          _buildInactiveCard(context, _inactiveMatch!),
          const SizedBox(height: 8),
        ],
        _buildFrequentPicks(context, inventory),
        _buildCartCard(context, inventory, items),
      ],
    );
  }

  /// Schnellwahl „Häufig bestellt": die meistbestellten Artikel des Ladens als
  /// antippbare Chips — ein Tipp legt sie wie ein Scan in den Warenkorb. Spart
  /// das Suchen des Barcodes für die immergleichen Sorten.
  Widget _buildFrequentPicks(
    BuildContext context,
    InventoryProvider inventory,
  ) {
    final picks =
        inventory.frequentlyOrderedProducts(siteId: _selectedSiteId, limit: 8);
    if (picks.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Häufig bestellt', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final product in picks)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text(product.name),
                    onPressed: () => _addScannedToCart(inventory, product),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartCard(
    BuildContext context,
    InventoryProvider inventory,
    List<OrderListItem> items,
  ) {
    final theme = Theme.of(context);
    final totalQty = items.fold<int>(0, (sum, item) => sum + item.quantity);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Icon(Icons.shopping_cart_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    items.isEmpty
                        ? 'Warenkorb'
                        : 'Warenkorb: ${items.length} Artikel · $totalQty Stueck',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Text(
                'Scanne Artikel — sie landen direkt im Warenkorb. Den gleichen '
                'Artikel erneut scannen erhoeht die Menge.',
              ),
            )
          else ...[
            for (final item in items) _buildCartRow(context, inventory, item),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check),
                label: Text('Fertig — Warenkorb ($totalQty)'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCartRow(
    BuildContext context,
    InventoryProvider inventory,
    OrderListItem item,
  ) {
    final theme = Theme.of(context);
    final productId = item.productId;
    final siteId = _selectedSiteId;
    final canEdit = productId != null && siteId != null;
    return ListTile(
      title: Text(item.name),
      subtitle: Text(
        [
          if (item.category?.isNotEmpty ?? false) item.category!,
          item.unit,
        ].join(' · '),
        style: theme.textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove),
            tooltip: 'Weniger',
            onPressed: canEdit
                ? () => inventory.setCartItemQuantity(
                      siteId: siteId,
                      productId: productId,
                      quantity: item.quantity - 1,
                    )
                : null,
          ),
          SizedBox(
            width: 28,
            child: Text(
              '${item.quantity}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Mehr',
            onPressed: canEdit
                ? () => inventory.setCartItemQuantity(
                      siteId: siteId,
                      productId: productId,
                      quantity: item.quantity + 1,
                    )
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Entfernen',
            onPressed: canEdit
                ? () => inventory.removeCartItem(
                      siteId: siteId,
                      productId: productId,
                    )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildMultiMatches(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Mehrere Artikel mit diesem Barcode — bitte waehlen:'),
          ),
          for (final product in _multiMatches)
            ListTile(
              title: Text(product.name),
              subtitle: Text(
                'Bestand: ${product.currentStock} ${product.unit} · '
                'VK ${formatCents(product.sellingPriceCents)}',
              ),
              onTap: () => setState(() {
                _match = product;
                _multiMatches = const [];
                _quantity = 1;
              }),
            ),
        ],
      ),
    );
  }

  Widget _buildMatchCard(BuildContext context, Product product) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.name, style: theme.textTheme.titleLarge),
            if ((product.category ?? '').isNotEmpty)
              Text(product.category!, style: theme.textTheme.bodySmall),
            if (_gs1Data != null &&
                (_gs1Data!.expiryDate != null || _gs1Data!.lot != null)) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.appColors.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'GS1-Code: '
                  '${_gs1Data!.expiryDate != null ? 'MHD ${_gs1Data!.expiryDate!.day.toString().padLeft(2, '0')}.${_gs1Data!.expiryDate!.month.toString().padLeft(2, '0')}.${_gs1Data!.expiryDate!.year}' : ''}'
                  '${_gs1Data!.expiryDate != null && _gs1Data!.lot != null ? ' · ' : ''}'
                  '${_gs1Data!.lot != null ? 'Charge ${_gs1Data!.lot}' : ''}'
                  ' — „Wareneingang" uebernimmt das automatisch.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _InfoChip(
                  label: 'Bestand',
                  value: '${product.currentStock} ${product.unit}',
                ),
                _InfoChip(label: 'VK', value: formatCents(product.sellingPriceCents)),
                _InfoChip(label: 'EK', value: formatCents(product.purchasePriceCents)),
              ],
            ),
            const Divider(height: 24),
            _buildQuantityRow(context),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        _booking ? null : () => _receiveGuided(product),
                    icon: const Icon(Icons.add),
                    label: const Text('Wareneingang'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed:
                        _booking ? null : () => _issue(product, _quantity),
                    icon: const Icon(Icons.remove),
                    label: const Text('Abgang'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _booking ? null : () => _stocktake(product),
                    icon: const Icon(Icons.checklist_outlined),
                    label: const Text('Inventur'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _booking ? null : () => _changePrice(product),
                    icon: const Icon(Icons.sell_outlined),
                    label: const Text('Preis'),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () =>
                        showPriceHistorySheet(context, product: product),
                    icon: const Icon(Icons.history),
                    label: const Text('Preisverlauf'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _booking ? null : () => _captureExpiry(product),
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text('MHD erfassen'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantityRow(BuildContext context) {
    return Row(
      children: [
        const Text('Menge:'),
        const SizedBox(width: 12),
        IconButton.outlined(
          onPressed: _quantity > 1
              ? () => setState(() => _quantity -= 1)
              : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 48,
          child: Text(
            '$_quantity',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        IconButton.outlined(
          onPressed: () => setState(() => _quantity += 1),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  Widget _buildInactiveCard(BuildContext context, Product product) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${product.name}" ist deaktiviert.',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Reaktivieren statt neu anlegen?'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _reactivate(product),
              icon: const Icon(Icons.restore_outlined),
              label: const Text('Reaktivieren'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotFoundCard(BuildContext context, String code) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Artikel nicht vorhanden',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Barcode: $code'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _createNew(code),
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Neu anlegen'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredHint extends StatelessWidget {
  const _CenteredHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _LastAddedBanner extends StatelessWidget {
  const _LastAddedBanner({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.success.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: colors.success),
          const SizedBox(width: 8),
          Expanded(child: Text('„$name" in den Warenkorb gelegt')),
        ],
      ),
    );
  }
}

class _CameraButton extends StatelessWidget {
  const _CameraButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
