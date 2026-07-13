import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/parcel_shipment.dart';
import '../models/shelf_compartment.dart';
import '../providers/parcel_provider.dart';
import '../services/barcode_scanner.dart';
import '../services/scan_feedback.dart';
import '../widgets/barcode_scan_field.dart';

/// Einlagern-Flow (Plan §5a): Paket-Barcode scannen → Fach-Barcode scannen
/// (mit Freifach-Vorschlag + Belegungs-Warnung) → Empfänger zuordnen (Typeahead
/// aus dem Register + „Neu anlegen") → speichern. Carrier-agnostisch (Paketdienst
/// optional). Scanner/Feedback sind für Tests injizierbar.
class PaketEinlagernScreen extends StatefulWidget {
  const PaketEinlagernScreen({
    super.key,
    required this.siteId,
    this.siteName,
    this.scanner,
    this.feedback,
  });

  final String siteId;
  final String? siteName;
  final BarcodeScanner? scanner;
  final ScanFeedback? feedback;

  @override
  State<PaketEinlagernScreen> createState() => _PaketEinlagernScreenState();
}

class _PaketEinlagernScreenState extends State<PaketEinlagernScreen> {
  String? _trackingCode;
  bool _ohneBarcode = false;
  ShelfCompartment? _compartment;

  String? _recipientFirst;
  String? _recipientLast;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _senderController = TextEditingController();
  final TextEditingController _carrierController = TextEditingController();
  String _query = '';
  bool _newRecipientMode = false;
  final TextEditingController _firstController = TextEditingController();
  final TextEditingController _lastController = TextEditingController();

  bool _saving = false;

  ParcelProvider get _parcel => context.read<ParcelProvider>();

  bool get _hasRecipient =>
      (_recipientFirst != null && _recipientFirst!.trim().isNotEmpty) ||
      (_recipientLast != null && _recipientLast!.trim().isNotEmpty);

  bool get _canSave => _compartment != null && _hasRecipient && !_saving;

  @override
  void dispose() {
    _searchController.dispose();
    _senderController.dispose();
    _carrierController.dispose();
    _firstController.dispose();
    _lastController.dispose();
    super.dispose();
  }

  Future<String?> _scan(String title, String hint) => showBarcodeScanSheet(
        context,
        title: title,
        hint: hint,
        scanner: widget.scanner,
        feedback: widget.feedback,
      );

  Future<void> _scanPackage() async {
    final code = await _scan('Paket scannen', 'Sendungsnummer des Pakets');
    if (code == null || !mounted) return;
    final open = _parcel.findParcelByCode(code).where((p) => p.isOpen).toList();
    if (open.isNotEmpty) {
      final label = open.first.compartmentLabel;
      final proceed = await _confirm(
        'Bereits eingelagert',
        'Dieses Paket liegt schon im Bestand'
            '${label == null ? '' : ' (Fach $label)'}. Trotzdem neu erfassen?',
      );
      if (!proceed || !mounted) return;
    }
    setState(() {
      _trackingCode = code;
      _ohneBarcode = false;
    });
  }

  Future<void> _scanCompartment() async {
    final code = await _scan('Fach scannen', 'Barcode des Fachs/Regalplatzes');
    if (code == null || !mounted) return;
    var fach = _parcel.compartmentByBarcode(code);
    if (fach == null) {
      final created = await _createCompartment(code);
      if (created == null || !mounted) return;
      fach = created;
    }
    // Belegungs-Warnung: Fach enthält bereits (fremde) offene Pakete.
    final occupants = _parcel.parcelsInCompartment(fach.id!);
    if (occupants.isNotEmpty) {
      final names = occupants.map((p) => p.recipientDisplayName).toSet();
      final proceed = await _confirm(
        'Fach belegt',
        'Fach ${fach.label} enthält bereits Paket(e) von '
            '${names.join(', ')}. Trotzdem hinzufügen?',
      );
      if (!proceed || !mounted) return;
    }
    setState(() => _compartment = fach);
  }

  Future<ShelfCompartment?> _createCompartment(String barcode) async {
    final labelController = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fach nicht registriert'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Fach jetzt anlegen? Vergib ein Label (z. B. „A2").'),
            const SizedBox(height: 12),
            TextField(
              controller: labelController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Fach-Label'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, labelController.text.trim()),
            child: const Text('Anlegen'),
          ),
        ],
      ),
    );
    labelController.dispose();
    if (label == null || label.isEmpty || !mounted) return null;
    final id = await _parcel.saveCompartment(
      ShelfCompartment(
        orgId: '', // Provider setzt orgId
        siteId: widget.siteId,
        siteName: widget.siteName,
        label: label,
        barcode: barcode,
      ),
    );
    return ShelfCompartment(
      id: id,
      orgId: '',
      siteId: widget.siteId,
      siteName: widget.siteName,
      label: label,
      barcode: barcode,
    );
  }

  Future<bool> _confirm(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Trotzdem'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _selectRecipientFromText(String first, String last) {
    setState(() {
      _recipientFirst = first;
      _recipientLast = last;
      _newRecipientMode = false;
      _query = '';
      _searchController.clear();
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      final customer = await _parcel.upsertCustomer(
        firstName: _recipientFirst ?? '',
        lastName: _recipientLast ?? '',
        siteId: widget.siteId,
      );
      final fach = _compartment!;
      await _parcel.saveParcel(
        ParcelShipment(
          orgId: '', // Provider setzt orgId
          siteId: widget.siteId,
          siteName: widget.siteName,
          trackingCode: _trackingCode,
          recipientFirstName: _recipientFirst ?? '',
          recipientLastName: _recipientLast ?? '',
          senderName: _senderController.text.trim().isEmpty
              ? null
              : _senderController.text.trim(),
          carrier: _carrierController.text.trim().isEmpty
              ? null
              : _carrierController.text.trim(),
          parcelCustomerId: customer.id,
          compartmentId: fach.id,
          compartmentLabel: fach.label,
          arrivedAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      final name = '${_recipientFirst ?? ''} ${_recipientLast ?? ''}'.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Paket für $name in Fach ${fach.label} eingelagert')),
      );
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches =
        _query.trim().isEmpty ? const [] : _parcel.parcelCustomersMatching(_query);

    return Scaffold(
      appBar: AppBar(title: const Text('Paket annehmen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('1 · Paket'),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _scanPackage,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Paket scannen'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => setState(() {
                  _trackingCode = null;
                  _ohneBarcode = true;
                }),
                child: const Text('Ohne Barcode'),
              ),
            ],
          ),
          if (_trackingCode != null)
            _ValueChip(icon: Icons.qr_code, label: _trackingCode!),
          if (_ohneBarcode)
            const _ValueChip(icon: Icons.block, label: 'Ohne Barcode'),

          const SizedBox(height: 20),
          const _SectionTitle('2 · Fach'),
          if (_freeHint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Vorschlag: freies Fach $_freeHint',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          FilledButton.icon(
            onPressed: _scanCompartment,
            icon: const Icon(Icons.shelves),
            label: const Text('Fach scannen'),
          ),
          if (_compartment != null)
            _ValueChip(icon: Icons.inventory_2, label: 'Fach ${_compartment!.label}'),

          const SizedBox(height: 20),
          const _SectionTitle('3 · Empfänger'),
          if (_hasRecipient)
            _ValueChip(
              icon: Icons.person,
              label: '${_recipientFirst ?? ''} ${_recipientLast ?? ''}'.trim(),
              onClear: () => setState(() {
                _recipientFirst = null;
                _recipientLast = null;
              }),
            )
          else ...[
            if (!_newRecipientMode) ...[
              TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  labelText: 'Name suchen',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              for (final c in matches.take(6))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.person_outline),
                  title: Text(c.displayName),
                  onTap: () => _selectRecipientFromText(c.firstName, c.lastName),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _newRecipientMode = true),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Neu anlegen'),
                ),
              ),
            ] else ...[
              TextField(
                controller: _firstController,
                decoration: const InputDecoration(labelText: 'Vorname'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _lastController,
                decoration: const InputDecoration(labelText: 'Nachname'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() => _newRecipientMode = false),
                    child: const Text('Zurück'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => _selectRecipientFromText(
                      _firstController.text.trim(),
                      _lastController.text.trim(),
                    ),
                    child: const Text('Übernehmen'),
                  ),
                ],
              ),
            ],
          ],

          const SizedBox(height: 20),
          const _SectionTitle('Optional'),
          TextField(
            controller: _senderController,
            decoration: const InputDecoration(
              labelText: 'Absender / Shop (z. B. Amazon)',
              prefixIcon: Icon(Icons.storefront_outlined),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _carrierController,
            decoration: const InputDecoration(
              labelText: 'Paketdienst (z. B. DHL, Hermes, DPD)',
              prefixIcon: Icon(Icons.local_shipping_outlined),
            ),
          ),

          const SizedBox(height: 28),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _canSave ? _save : null,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: const Text('Einlagern'),
        ),
      ),
    );
  }

  String? get _freeHint {
    if (_compartment != null) return null;
    final free = _parcel.freeCompartments;
    return free.isEmpty ? null : free.first.label;
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _ValueChip extends StatelessWidget {
  const _ValueChip({required this.icon, required this.label, this.onClear});
  final IconData icon;
  final String label;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Chip(
          avatar: Icon(icon, size: 18),
          label: Text(label),
          onDeleted: onClear,
        ),
      );
}
