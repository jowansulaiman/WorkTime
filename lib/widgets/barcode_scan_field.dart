import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/barcode_scanner.dart';
import '../services/scan_feedback.dart';

/// Öffnet ein modales Scan-Sheet und liefert den **rohen** erkannten Code
/// zurück (oder `null`, wenn abgebrochen). Wiederverwendbar für beliebige
/// Barcodes — Paket-Sendungsnummern, Fach-Bin-Barcodes, Kundenhandy-Codes.
///
/// Bewusst **ohne** Retail-Prüfziffer-Validierung (opake Paket-/Fach-Codes) und
/// **ohne** `scanWindow` (voller Frame, Reticle rein visuell — mobile_scanner
/// #1009/#633). Nutzt die vorhandenen Scanner-Seams ([BarcodeScanner],
/// [ScanFeedback]); für Tests injizierbar. Standard-Ziel: [ScannerTarget.extended]
/// (deckt EAN/UPC + QR + DataMatrix + ITF-14 + Code-128 ab).
Future<String?> showBarcodeScanSheet(
  BuildContext context, {
  ScannerTarget target = ScannerTarget.extended,
  String title = 'Barcode scannen',
  String? hint,
  BarcodeScanner? scanner,
  ScanFeedback? feedback,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _BarcodeScanSheet(
      target: target,
      title: title,
      hint: hint,
      scanner: scanner,
      feedback: feedback,
    ),
  );
}

class _BarcodeScanSheet extends StatefulWidget {
  const _BarcodeScanSheet({
    required this.target,
    required this.title,
    this.hint,
    this.scanner,
    this.feedback,
  });

  final ScannerTarget target;
  final String title;
  final String? hint;
  final BarcodeScanner? scanner;
  final ScanFeedback? feedback;

  @override
  State<_BarcodeScanSheet> createState() => _BarcodeScanSheetState();
}

class _BarcodeScanSheetState extends State<_BarcodeScanSheet> {
  late final BarcodeScanner _scanner;
  late final ScanFeedback _feedback;
  late final bool _ownsScanner;
  StreamSubscription<String>? _sub;
  final TextEditingController _manualController = TextEditingController();

  bool _handling = false;
  bool _analyzingPhoto = false;
  double _zoom = 0;

  // Doppel-Scan-Entprellung (der Aufrufer bekommt exakt einen Code zurück).
  String _lastCode = '';
  DateTime? _lastCodeAt;

  @override
  void initState() {
    super.initState();
    _ownsScanner = widget.scanner == null;
    _scanner = widget.scanner ?? MobileScannerAdapter();
    _feedback = widget.feedback ?? AudioHapticFeedback();
    _sub = _scanner.codes.listen(_onCode, onError: (_) {});
    if (_scanner.isAvailable) {
      // setTarget vor start(): Controller ist noch nicht gebaut → nur das Ziel
      // wird gesetzt, kein Neuaufbau. scanWindow wird NIE gesetzt.
      unawaited(
        _scanner
            .setTarget(widget.target)
            .then((_) => _scanner.start())
            .catchError((Object _) {}),
      );
    }
  }

  void _onCode(String code) {
    if (_handling) return;
    final c = code.trim();
    if (c.isEmpty) return;
    final now = DateTime.now();
    if (c == _lastCode &&
        _lastCodeAt != null &&
        now.difference(_lastCodeAt!) < const Duration(milliseconds: 1000)) {
      return;
    }
    _lastCode = c;
    _lastCodeAt = now;
    _accept(c);
  }

  void _accept(String code) {
    if (_handling || !mounted) return;
    _handling = true;
    unawaited(_feedback.success());
    unawaited(_scanner.stop());
    Navigator.of(context).pop(code);
  }

  void _submitManual() {
    final value = _manualController.text.trim();
    if (value.isEmpty) return;
    _accept(value);
  }

  Future<void> _scanPhoto() async {
    if (_analyzingPhoto) return;
    setState(() => _analyzingPhoto = true);
    try {
      final photo = await ImagePicker().pickImage(source: ImageSource.camera);
      if (photo == null || !mounted) return;
      final codes = await _scanner.analyzePhoto(photo.path);
      if (!mounted) return;
      if (codes.isEmpty) {
        unawaited(_feedback.failure());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Kein Code im Foto erkannt. Näher herangehen, für Licht sorgen '
              'oder den Code manuell eingeben.',
            ),
          ),
        );
        return;
      }
      _accept(codes.first); // roher Code, keine Retail-Prüfung
    } finally {
      if (mounted) setState(() => _analyzingPhoto = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _manualController.dispose();
    unawaited(_scanner.stop());
    if (_ownsScanner) {
      unawaited(_scanner.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cameraAvailable = _scanner.isAvailable;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: theme.textTheme.titleLarge),
          if (widget.hint != null) ...[
            const SizedBox(height: 4),
            Text(widget.hint!, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 12),
          if (cameraAvailable) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 280,
                child: _scanner.buildPreview(context),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_scanner.supportsTorch)
                  IconButton.filledTonal(
                    onPressed: () => unawaited(_scanner.toggleTorch()),
                    icon: const Icon(Icons.flash_on_outlined),
                    tooltip: 'Taschenlampe',
                  ),
                if (_scanner.supportsPhotoAnalysis) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _analyzingPhoto ? null : () => _scanPhoto(),
                    icon: _analyzingPhoto
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera_outlined),
                    tooltip: 'Foto scannen (schwierige Codes)',
                  ),
                ],
                if (_scanner.supportsZoom)
                  Expanded(
                    child: Slider(
                      value: _zoom,
                      onChanged: (v) {
                        setState(() => _zoom = v);
                        unawaited(_scanner.setZoom(v));
                      },
                    ),
                  ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Kamera hier nicht verfügbar — bitte den Code manuell eingeben.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualController,
                  textInputAction: TextInputAction.done,
                  autofocus: !cameraAvailable,
                  onSubmitted: (_) => _submitManual(),
                  decoration: const InputDecoration(
                    labelText: 'Code manuell eingeben',
                    prefixIcon: Icon(Icons.keyboard_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _submitManual,
                child: const Text('Übernehmen'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
