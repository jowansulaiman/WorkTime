import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/purchase_order.dart';
import '../theme/theme_extensions.dart';

/// **WW-6:** Ergebnis des geführten Wareneingangs gegen eine Bestellung.
class PurchaseReceiptResult {
  const PurchaseReceiptResult({
    required this.lines,
    this.deliveryNoteNumber,
    this.updatePurchasePrice = false,
  });

  /// Positionsindex → gebuchte Menge (+ optional Ist-EK/MHD/Charge).
  final Map<int, PurchaseReceiptLine> lines;

  /// Lieferschein-Nummer der Lieferung (optional).
  final String? deliveryNoteNumber;

  /// Ob abweichende Ist-EK als Artikel-Einkaufspreis übernommen werden sollen.
  final bool updatePurchasePrice;
}

/// **WW-6:** Geführter Wareneingang gegen eine Bestellung — generalisiert das
/// Scanner-MHD/Charge-Muster (`showGoodsReceiptSheet`) auf mehrere Positionen:
/// Kopf mit Lieferschein-Nr., je offene Position die Menge (Default =
/// offener Rest) und aufklappbar MHD, Charge und Ist-Einkaufspreis.
///
/// Liefert `null` bei Abbruch.
Future<PurchaseReceiptResult?> showPurchaseReceiptSheet(
  BuildContext context, {
  required PurchaseOrder order,
}) {
  return showModalBottomSheet<PurchaseReceiptResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PurchaseReceiptSheet(order: order),
  );
}

class _PurchaseReceiptSheet extends StatefulWidget {
  const _PurchaseReceiptSheet({required this.order});

  final PurchaseOrder order;

  @override
  State<_PurchaseReceiptSheet> createState() => _PurchaseReceiptSheetState();
}

class _PurchaseReceiptSheetState extends State<_PurchaseReceiptSheet> {
  final TextEditingController _deliveryNoteController = TextEditingController();
  final Map<int, TextEditingController> _qty = {};
  final Map<int, TextEditingController> _ek = {};
  final Map<int, TextEditingController> _lot = {};
  final Map<int, DateTime?> _expiry = {};
  late final List<int> _openIndices;
  bool _updatePurchasePrice = false;

  @override
  void initState() {
    super.initState();
    _openIndices = [
      for (var i = 0; i < widget.order.items.length; i++)
        if (widget.order.items[i].outstandingQuantity > 0) i,
    ];
    for (final i in _openIndices) {
      final item = widget.order.items[i];
      _qty[i] =
          TextEditingController(text: item.outstandingQuantity.toString());
      final price = item.unitPriceCents;
      _ek[i] = TextEditingController(
        text: price != null ? _centsToInput(price) : '',
      );
      _lot[i] = TextEditingController();
      _expiry[i] = null;
    }
  }

  @override
  void dispose() {
    _deliveryNoteController.dispose();
    for (final c in _qty.values) {
      c.dispose();
    }
    for (final c in _ek.values) {
      c.dispose();
    }
    for (final c in _lot.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Cent → Eingabe-Text „1,25" (deutsche Dezimalstelle).
  static String _centsToInput(int cents) =>
      (cents / 100.0).toStringAsFixed(2).replaceAll('.', ',');

  /// Eingabe-Text (Euro, Komma oder Punkt) → Cent. Leer/ungültig → `null`.
  static int? _inputToCents(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final normalized = trimmed.replaceAll(' ', '').replaceAll(',', '.');
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }

  Future<void> _pickExpiry(int index) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry[index] ??
          DateTime(today.year, today.month, today.day)
              .add(const Duration(days: 7)),
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 5),
      helpText: 'Mindesthaltbarkeitsdatum (MHD)',
      locale: const Locale('de', 'DE'),
    );
    if (picked == null || !mounted) return;
    setState(() => _expiry[index] = picked);
  }

  void _submit() {
    final lines = <int, PurchaseReceiptLine>{};
    for (final i in _openIndices) {
      final qty = int.tryParse(_qty[i]!.text.trim()) ?? 0;
      if (qty <= 0) continue;
      final lot = _lot[i]!.text.trim();
      lines[i] = PurchaseReceiptLine(
        quantity: qty,
        receivedUnitPriceCents: _inputToCents(_ek[i]!.text),
        expiryDate: _expiry[i],
        batchNote: lot.isEmpty ? null : lot,
      );
    }
    final note = _deliveryNoteController.text.trim();
    Navigator.of(context).pop(
      PurchaseReceiptResult(
        lines: lines,
        deliveryNoteNumber: note.isEmpty ? null : note,
        updatePurchasePrice: _updatePurchasePrice,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Wareneingang buchen',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _deliveryNoteController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Lieferschein-Nr. (optional)',
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
            ),
            const SizedBox(height: 8),
            if (_openIndices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Alle Positionen sind bereits vollständig geliefert.',
                ),
              )
            else
              for (final i in _openIndices)
                _PositionTile(
                  item: widget.order.items[i],
                  quantityController: _qty[i]!,
                  ekController: _ek[i]!,
                  lotController: _lot[i]!,
                  expiry: _expiry[i],
                  onPickExpiry: () => _pickExpiry(i),
                  onClearExpiry: () => setState(() => _expiry[i] = null),
                ),
            if (_openIndices.isNotEmpty) ...[
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _updatePurchasePrice,
                onChanged: (v) => setState(() => _updatePurchasePrice = v),
                title: const Text('Einkaufspreis am Artikel aktualisieren?'),
                subtitle: const Text(
                  'Übernimmt einen abweichenden Ist-EK als neuen Artikel-'
                  'Einkaufspreis (mit Preis-Historie).',
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _openIndices.isEmpty ? null : _submit,
              icon: const Icon(Icons.move_to_inbox_outlined),
              label: const Text('Wareneingang buchen'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Eine offene Position: Menge immer sichtbar, MHD/Charge/Ist-EK aufklappbar.
class _PositionTile extends StatelessWidget {
  const _PositionTile({
    required this.item,
    required this.quantityController,
    required this.ekController,
    required this.lotController,
    required this.expiry,
    required this.onPickExpiry,
    required this.onClearExpiry,
  });

  final PurchaseOrderItem item;
  final TextEditingController quantityController;
  final TextEditingController ekController;
  final TextEditingController lotController;
  final DateTime? expiry;
  final VoidCallback onPickExpiry;
  final VoidCallback onClearExpiry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd.MM.yyyy', 'de_DE');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        'offen: ${item.outstandingQuantity} ${item.unit}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 88,
                  child: TextField(
                    controller: quantityController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Menge',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            Theme(
              // ExpansionTile ohne Trenner-Linien.
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(
                  'MHD / Charge / Ist-EK (optional)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                children: [
                  if (expiry == null)
                    OutlinedButton.icon(
                      onPressed: onPickExpiry,
                      icon: const Icon(Icons.event_available_outlined),
                      label: const Text('MHD erfassen'),
                    )
                  else
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'MHD',
                        prefixIcon: Icon(Icons.event_available_outlined),
                        isDense: true,
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(dateFormat.format(expiry!))),
                          IconButton(
                            tooltip: 'MHD ändern',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: onPickExpiry,
                          ),
                          IconButton(
                            tooltip: 'MHD entfernen',
                            icon: const Icon(Icons.close),
                            onPressed: onClearExpiry,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: lotController,
                    decoration: const InputDecoration(
                      labelText: 'Charge/Los',
                      prefixIcon: Icon(Icons.tag_outlined),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: ekController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Ist-EK je Einheit (€)',
                      prefixIcon: Icon(Icons.euro_outlined),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Eine Charge wird nur zusammen mit einem MHD gespeichert — '
                    'ohne MHD wird nur der Bestand gebucht.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: lotController.text.trim().isNotEmpty &&
                              expiry == null
                          ? theme.appColors.warning
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
