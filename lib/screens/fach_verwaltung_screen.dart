import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/shelf_compartment.dart';
import '../providers/parcel_provider.dart';
import '../services/barcode_scanner.dart';
import '../services/scan_feedback.dart';
import '../widgets/barcode_scan_field.dart';

/// Fach-Verwaltung (Plan §5c): Fächer mit Bin-Barcode anlegen (Barcode je
/// Standort eindeutig), Reverse-Lookup „was liegt in Fach X?", leeres Fach
/// löschen (belegtes ist geschützt). Umbenennen ist v1 bewusst nicht dabei
/// (Label-Cache-Nachzug, spätere Ausbaustufe). Scanner injizierbar für Tests.
class FachVerwaltungScreen extends StatelessWidget {
  const FachVerwaltungScreen({super.key, this.siteId, this.siteName, this.scanner, this.feedback});

  final String? siteId;
  final String? siteName;
  final BarcodeScanner? scanner;
  final ScanFeedback? feedback;

  @override
  Widget build(BuildContext context) {
    final parcel = context.watch<ParcelProvider>();
    final faecher = parcel.compartments;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fächer'),
        actions: [
          IconButton(
            tooltip: 'Fach scannen (Reverse-Lookup)',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => _reverseLookup(context),
          ),
        ],
      ),
      body: faecher.isEmpty
          ? const Center(child: Text('Noch keine Fächer angelegt.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final f in faecher)
                  _FachTile(
                    fach: f,
                    occupants: parcel.parcelsInCompartment(f.id ?? ''),
                    onDelete: () => _delete(context, f),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createFach(context),
        icon: const Icon(Icons.add),
        label: const Text('Fach'),
      ),
    );
  }

  Future<void> _createFach(BuildContext context) async {
    final provider = context.read<ParcelProvider>();
    final result = await showDialog<({String label, String barcode})>(
      context: context,
      builder: (_) => _CreateFachDialog(scanner: scanner, feedback: feedback),
    );
    if (result == null ||
        result.label.isEmpty ||
        result.barcode.isEmpty ||
        !context.mounted) {
      return;
    }
    try {
      await provider.saveCompartment(
        ShelfCompartment(
          orgId: '', // Provider setzt orgId
          siteId: siteId ?? provider.settings.paketshopSiteId ?? '',
          siteName: siteName,
          label: result.label,
          barcode: result.barcode,
        ),
      );
    } on StateError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _delete(BuildContext context, ShelfCompartment f) async {
    final provider = context.read<ParcelProvider>();
    try {
      await provider.deleteCompartment(f.id!);
    } on StateError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _reverseLookup(BuildContext context) async {
    final provider = context.read<ParcelProvider>();
    final code = await showBarcodeScanSheet(
      context,
      title: 'Fach scannen',
      hint: 'Was liegt in diesem Fach?',
      scanner: scanner,
      feedback: feedback,
    );
    if (code == null || !context.mounted) return;
    final fach = provider.compartmentByBarcode(code);
    final occupants = fach == null
        ? const []
        : provider.parcelsInCompartment(fach.id ?? '');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(fach == null ? 'Unbekanntes Fach' : 'Fach ${fach.label}'),
        content: Text(
          fach == null
              ? 'Kein Fach mit diesem Barcode.'
              : occupants.isEmpty
                  ? 'Leer.'
                  : occupants
                      .map((p) => p.recipientDisplayName)
                      .join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _FachTile extends StatelessWidget {
  const _FachTile({
    required this.fach,
    required this.occupants,
    required this.onDelete,
  });

  final ShelfCompartment fach;
  final List occupants;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final belegt = occupants.isNotEmpty;
    return Card(
      child: ListTile(
        leading: Icon(belegt ? Icons.inventory_2 : Icons.inbox_outlined),
        title: Text('Fach ${fach.label}'),
        subtitle: Text(belegt ? '${occupants.length} Paket(e)' : 'frei'),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: belegt ? 'Belegt — nicht löschbar' : 'Löschen',
          onPressed: onDelete,
        ),
      ),
    );
  }
}

/// Dialog zum Anlegen eines Fachs (eigene Controller, sauber disposed nach
/// vollständigem Schließen — verhindert „controller used after dispose").
class _CreateFachDialog extends StatefulWidget {
  const _CreateFachDialog({this.scanner, this.feedback});

  final BarcodeScanner? scanner;
  final ScanFeedback? feedback;

  @override
  State<_CreateFachDialog> createState() => _CreateFachDialogState();
}

class _CreateFachDialogState extends State<_CreateFachDialog> {
  final TextEditingController _label = TextEditingController();
  final TextEditingController _barcode = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    _barcode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Neues Fach'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _label,
              decoration: const InputDecoration(labelText: 'Label (z. B. A2)'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _barcode,
                    decoration:
                        const InputDecoration(labelText: 'Fach-Barcode'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final code = await showBarcodeScanSheet(
                      context,
                      title: 'Fach-Barcode scannen',
                      scanner: widget.scanner,
                      feedback: widget.feedback,
                    );
                    if (code != null) _barcode.text = code;
                  },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scannen'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            (label: _label.text.trim(), barcode: _barcode.text.trim()),
          ),
          child: const Text('Anlegen'),
        ),
      ],
    );
  }
}
