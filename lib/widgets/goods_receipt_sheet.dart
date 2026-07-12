import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/product.dart';
import '../theme/theme_extensions.dart';

/// Ergebnis des gefuehrten Wareneingangs: Menge + optionales MHD + optionale
/// Chargen-Angabe. Die Buchung selbst (adjustStock + ggf. saveBatch) macht der
/// Aufrufer — das Sheet sammelt nur die Eingaben in EINEM Ablauf.
class GoodsReceiptInput {
  const GoodsReceiptInput({
    required this.quantity,
    this.expiryDate,
    this.lot,
  });

  final int quantity;

  /// Mindesthaltbarkeitsdatum der Lieferung (optional — nur fuer Ware mit MHD).
  final DateTime? expiryDate;

  /// Chargen-/Losnummer (optional, landet in `ProductBatch.note`).
  final String? lot;

  bool get hasBatch => expiryDate != null;
}

/// Gefuehrter Wareneingang: Menge, MHD und Charge in EINEM Ablauf statt
/// getrennter Buttons („Wareneingang" vs. „MHD erfassen"). GS1-Scans
/// (DataMatrix/QR mit AI 17/10) befuellen MHD/Charge vor.
///
/// Liefert `null` bei Abbruch.
Future<GoodsReceiptInput?> showGoodsReceiptSheet(
  BuildContext context, {
  required Product product,
  int initialQuantity = 1,
  DateTime? initialExpiry,
  String? initialLot,
}) {
  return showModalBottomSheet<GoodsReceiptInput>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _GoodsReceiptSheet(
      product: product,
      initialQuantity: initialQuantity,
      initialExpiry: initialExpiry,
      initialLot: initialLot,
    ),
  );
}

class _GoodsReceiptSheet extends StatefulWidget {
  const _GoodsReceiptSheet({
    required this.product,
    required this.initialQuantity,
    this.initialExpiry,
    this.initialLot,
  });

  final Product product;
  final int initialQuantity;
  final DateTime? initialExpiry;
  final String? initialLot;

  @override
  State<_GoodsReceiptSheet> createState() => _GoodsReceiptSheetState();
}

class _GoodsReceiptSheetState extends State<_GoodsReceiptSheet> {
  late int _quantity = widget.initialQuantity < 1 ? 1 : widget.initialQuantity;
  late DateTime? _expiry = widget.initialExpiry;
  late final TextEditingController _lotController =
      TextEditingController(text: widget.initialLot ?? '');

  @override
  void dispose() {
    _lotController.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ??
          DateTime(today.year, today.month, today.day)
              .add(const Duration(days: 7)),
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 5),
      helpText: 'Mindesthaltbarkeitsdatum (MHD)',
      locale: const Locale('de', 'DE'),
    );
    if (picked == null || !mounted) return;
    setState(() => _expiry = picked);
  }

  void _submit() {
    final lot = _lotController.text.trim();
    Navigator.of(context).pop(
      GoodsReceiptInput(
        quantity: _quantity,
        expiryDate: _expiry,
        lot: lot.isEmpty ? null : lot,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd.MM.yyyy', 'de_DE');
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Wareneingang: ${widget.product.name}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Aktueller Bestand: ${widget.product.currentStock} '
            '${widget.product.unit}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Text('Menge (Zugang)')),
              IconButton.outlined(
                onPressed: _quantity > 1
                    ? () => setState(() => _quantity -= 1)
                    : null,
                icon: const Icon(Icons.remove),
                tooltip: 'Weniger',
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '$_quantity',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton.outlined(
                onPressed: () => setState(() => _quantity += 1),
                icon: const Icon(Icons.add),
                tooltip: 'Mehr',
              ),
            ],
          ),
          const SizedBox(height: 12),
          // MHD optional: gesetzt -> Chip mit Datum + Entfernen; sonst Button.
          if (_expiry == null)
            OutlinedButton.icon(
              onPressed: _pickExpiry,
              icon: const Icon(Icons.event_available_outlined),
              label: const Text('MHD erfassen (optional)'),
            )
          else
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'MHD',
                prefixIcon: Icon(Icons.event_available_outlined),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(dateFormat.format(_expiry!))),
                  IconButton(
                    tooltip: 'MHD aendern',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: _pickExpiry,
                  ),
                  IconButton(
                    tooltip: 'MHD entfernen',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _expiry = null),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _lotController,
            // Rebuild, damit der Hinweis unten auf eine eingegebene Charge
            // ohne MHD reagieren kann (Warnfarbe).
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Charge/Los (optional)',
              prefixIcon: Icon(Icons.tag_outlined),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _expiry != null
                ? 'Mit MHD wird zusaetzlich zur Bestandsbuchung eine Charge '
                    'angelegt — sie erscheint rechtzeitig in der '
                    'Ablauf-Warnung.'
                : 'Eine Charge wird nur zusammen mit einem MHD gespeichert — '
                    'ohne MHD wird nur der Bestand gebucht.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: _lotController.text.trim().isNotEmpty && _expiry == null
                  ? theme.appColors.warning
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.add),
            label: Text('Wareneingang buchen (+$_quantity)'),
          ),
        ],
      ),
    );
  }
}
