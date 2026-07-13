import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/parcel_shipment.dart';
import '../providers/parcel_provider.dart';
import '../services/barcode_scanner.dart';
import '../services/scan_feedback.dart';
import '../widgets/barcode_scan_field.dart';

/// Ausgeben-Flow (Plan §5b): Paket per Barcode/Kundenhandy-Code **oder**
/// Namenssuche finden → gebündelte Kunden-Karte (alle offenen Pakete + Fächer)
/// → „Ausgegeben" (einzeln/alle) mit **Undo**. Scanner/Feedback injizierbar.
class PaketAusgebenScreen extends StatefulWidget {
  const PaketAusgebenScreen({
    super.key,
    this.scanner,
    this.feedback,
  });

  final BarcodeScanner? scanner;
  final ScanFeedback? feedback;

  @override
  State<PaketAusgebenScreen> createState() => _PaketAusgebenScreenState();
}

class _PaketAusgebenScreenState extends State<PaketAusgebenScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _selectedKey; // recipientNameLower des gewählten Empfängers
  String? _notFoundCode;

  ParcelProvider get _parcel => context.read<ParcelProvider>();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await showBarcodeScanSheet(
      context,
      title: 'Paket / Code scannen',
      hint: 'Paket-Barcode oder Code vom Kundenhandy',
      scanner: widget.scanner,
      feedback: widget.feedback,
    );
    if (code == null || !mounted) return;
    final hits = _parcel.findParcelByCode(code).where((p) => p.isOpen).toList();
    setState(() {
      if (hits.isEmpty) {
        _notFoundCode = code;
        _selectedKey = null;
      } else {
        _notFoundCode = null;
        _selectedKey = hits.first.recipientNameLower;
      }
    });
  }

  Future<void> _handOut(List<ParcelShipment> parcels) async {
    if (parcels.isEmpty) return;
    if (parcels.length > 1) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Mehrere Pakete ausgeben'),
          content: Text('${parcels.length} Pakete dieses Kunden ausgeben?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Alle ausgeben')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    final ids = parcels.map((p) => p.id).whereType<String>().toList();
    for (final p in parcels) {
      await _parcel.handOutParcel(p);
    }
    if (!mounted) return;
    setState(() {
      _selectedKey = null;
      _query = '';
      _searchController.clear();
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('${ids.length} Paket(e) ausgegeben'),
          action: SnackBarAction(
            label: 'Rückgängig',
            onPressed: () => _undo(ids),
          ),
        ),
      );
  }

  Future<void> _undo(List<String> ids) async {
    for (final id in ids) {
      final current = _parcel.parcels.where((p) => p.id == id).toList();
      if (current.isNotEmpty) {
        await _parcel.undoHandOut(current.first);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final parcel = context.watch<ParcelProvider>();
    final theme = Theme.of(context);

    // Empfänger-Gruppen der offenen Pakete, gefiltert nach Suchtext.
    final open = parcel.openParcels;
    final Map<String, List<ParcelShipment>> byRecipient = {};
    for (final p in open) {
      byRecipient.putIfAbsent(p.recipientNameLower, () => []).add(p);
    }
    final q = _query.trim().toLowerCase();
    final groups = byRecipient.entries
        .where((e) => q.isEmpty || e.key.contains(q))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final selected =
        _selectedKey == null ? null : byRecipient[_selectedKey];

    return Scaffold(
      appBar: AppBar(title: const Text('Paket ausgeben')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() {
                    _query = v;
                    _selectedKey = null;
                    _notFoundCode = null;
                  }),
                  decoration: const InputDecoration(
                    labelText: 'Name suchen',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scannen'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_notFoundCode != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.help_outline),
                title: Text('Nicht gefunden: $_notFoundCode'),
                subtitle: const Text(
                    'Kein offenes Paket zu diesem Code. Anlieferung evtl. noch '
                    'nicht einsortiert.'),
              ),
            )
          else if (selected != null && selected.isNotEmpty)
            _RecipientBundle(
              parcels: selected,
              onHandOutOne: (p) => _handOut([p]),
              onHandOutAll: () => _handOut(selected),
            )
          else ...[
            if (open.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Keine offenen Pakete.')),
              )
            else if (groups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Kein Treffer.')),
              )
            else
              ...groups.map(
                (e) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(e.value.first.recipientDisplayName),
                    subtitle: Text('${e.value.length} Paket(e)'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => _selectedKey = e.key),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _RecipientBundle extends StatelessWidget {
  const _RecipientBundle({
    required this.parcels,
    required this.onHandOutOne,
    required this.onHandOutAll,
  });

  final List<ParcelShipment> parcels;
  final void Function(ParcelShipment) onHandOutOne;
  final VoidCallback onHandOutAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(parcels.first.recipientDisplayName,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('${parcels.length} offene(s) Paket(e)',
                style: theme.textTheme.bodySmall),
            const Divider(),
            ...parcels.map(
              (p) => ListTile(
                dense: true,
                title: Text([
                  if (p.compartmentLabel != null) 'Fach ${p.compartmentLabel}',
                  if (p.senderName != null) p.senderName!,
                  if (p.trackingCode != null) '…${_suffix(p.trackingCode!)}',
                ].join(' · ')),
                trailing: OutlinedButton(
                  onPressed: () => onHandOutOne(p),
                  child: const Text('Ausgegeben'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onHandOutAll,
              icon: const Icon(Icons.check),
              label: Text(parcels.length > 1
                  ? 'Alle ${parcels.length} ausgeben'
                  : 'Ausgegeben'),
            ),
            const SizedBox(height: 8),
            Text(
              'Offizieller Ablauf des Paketdiensts (Ausweis/Unterschrift am '
              'Anbieter-Gerät) bleibt zusätzlich zwingend.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  static String _suffix(String code) =>
      code.length <= 4 ? code : code.substring(code.length - 4);
}
