import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/delivery_advice.dart';
import '../models/supplier.dart';

/// **WW-4 — Lieferavis-Editor (imperatives Sheet, bewusst KEINE go_router-Route,
/// Kopplung #7 entfällt).** Legt ein Avis an oder bearbeitet ein bestehendes.
///
/// Prefill-Wege:
/// - aus einer Bestellung: [prefillItems] (offene Mengen) + [supplierId]/
///   [supplierName]/[purchaseOrderId] übergeben.
/// - Neuanlage vom Avis-Screen: nur [siteId]/[siteName] + [suppliers].
///
/// Gibt bei „Speichern" das (id-lose bei Neuanlage) [DeliveryAdvice] zurück —
/// der Aufrufer reicht es an `InventoryProvider.saveDeliveryAdvice`.
Future<DeliveryAdvice?> showDeliveryAdviceSheet(
  BuildContext context, {
  required String siteId,
  String? siteName,
  DeliveryAdvice? existing,
  List<DeliveryAdviceItem>? prefillItems,
  String? supplierId,
  String? supplierName,
  String? purchaseOrderId,
  List<Supplier> suppliers = const [],
}) {
  return showModalBottomSheet<DeliveryAdvice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _DeliveryAdviceSheet(
      siteId: siteId,
      siteName: siteName,
      existing: existing,
      prefillItems: prefillItems,
      supplierId: supplierId,
      supplierName: supplierName,
      purchaseOrderId: purchaseOrderId,
      suppliers: suppliers,
    ),
  );
}

class _DeliveryAdviceSheet extends StatefulWidget {
  const _DeliveryAdviceSheet({
    required this.siteId,
    this.siteName,
    this.existing,
    this.prefillItems,
    this.supplierId,
    this.supplierName,
    this.purchaseOrderId,
    this.suppliers = const [],
  });

  final String siteId;
  final String? siteName;
  final DeliveryAdvice? existing;
  final List<DeliveryAdviceItem>? prefillItems;
  final String? supplierId;
  final String? supplierName;
  final String? purchaseOrderId;
  final List<Supplier> suppliers;

  @override
  State<_DeliveryAdviceSheet> createState() => _DeliveryAdviceSheetState();
}

class _DeliveryAdviceSheetState extends State<_DeliveryAdviceSheet> {
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();
  late DateTime _expectedDate;
  String? _supplierId;
  final List<_ItemDraft> _items = [];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _expectedDate = existing?.expectedDate ??
        DeliveryAdvice.normalizeDay(
            DateTime.now().add(const Duration(days: 1)));
    _referenceController.text = existing?.reference ?? '';
    _notesController.text = existing?.notes ?? '';
    _supplierId = existing?.supplierId ?? widget.supplierId;
    final sourceItems = existing?.items ?? widget.prefillItems ?? const [];
    for (final item in sourceItems) {
      _items.add(_ItemDraft.fromItem(item));
    }
    if (_items.isEmpty) {
      _items.add(_ItemDraft.empty());
    }
  }

  @override
  void dispose() {
    _referenceController.dispose();
    _notesController.dispose();
    for (final draft in _items) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      helpText: 'Erwarteter Liefertermin',
      locale: const Locale('de', 'DE'),
    );
    if (picked == null || !mounted) return;
    setState(() => _expectedDate = DeliveryAdvice.normalizeDay(picked));
  }

  void _submit() {
    final items = <DeliveryAdviceItem>[];
    for (final draft in _items) {
      final name = draft.name.text.trim();
      final qty = int.tryParse(draft.qty.text.trim()) ?? 0;
      if (name.isEmpty || qty <= 0) continue;
      items.add(DeliveryAdviceItem(
        productId: draft.productId,
        name: name,
        sku: draft.sku,
        unit: draft.unit,
        announcedQuantity: qty,
      ));
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mindestens eine Position mit Menge > 0 erfassen.'),
        ),
      );
      return;
    }
    final supplierName = _supplierId == null
        ? widget.supplierName
        : widget.suppliers
            .where((s) => s.id == _supplierId)
            .map((s) => s.name)
            .cast<String?>()
            .firstWhere((_) => true, orElse: () => widget.supplierName);
    final reference = _referenceController.text.trim();
    final notes = _notesController.text.trim();
    final base = widget.existing;
    final advice = (base ??
            DeliveryAdvice(
              orgId: '', // vom Provider gesetzt
              siteId: widget.siteId,
              expectedDate: _expectedDate,
            ))
        .copyWith(
      siteId: widget.siteId,
      siteName: widget.siteName ?? base?.siteName,
      supplierId: _supplierId,
      clearSupplierId: _supplierId == null,
      supplierName: supplierName,
      clearSupplierName: supplierName == null,
      purchaseOrderId: widget.purchaseOrderId ?? base?.purchaseOrderId,
      reference: reference.isEmpty ? null : reference,
      clearReference: reference.isEmpty,
      expectedDate: _expectedDate,
      items: items,
      notes: notes.isEmpty ? null : notes,
      clearNotes: notes.isEmpty,
    );
    Navigator.of(context).pop(advice);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = DateFormat('EEEE, d. MMMM y', 'de_DE').format(_expectedDate);
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
              widget.existing == null ? 'Lieferavis erfassen' : 'Avis bearbeiten',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Erwartet am'),
              subtitle: Text(dateLabel),
              trailing: TextButton(
                onPressed: _pickDate,
                child: const Text('Ändern'),
              ),
            ),
            if (widget.suppliers.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: _supplierId,
                decoration: const InputDecoration(
                  labelText: 'Lieferant (optional)',
                  prefixIcon: Icon(Icons.local_shipping_outlined),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('— kein Lieferant —'),
                  ),
                  for (final s in widget.suppliers)
                    DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _supplierId = v),
              )
            else if (widget.supplierName != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('Lieferant: ${widget.supplierName}',
                    style: theme.textTheme.bodyMedium),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _referenceController,
              decoration: const InputDecoration(
                labelText: 'Avis-/Lieferschein-Referenz (optional)',
                prefixIcon: Icon(Icons.tag_outlined),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Positionen', style: theme.textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _items.add(_ItemDraft.empty())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Position'),
                ),
              ],
            ),
            for (var i = 0; i < _items.length; i++)
              _ItemRow(
                draft: _items[i],
                onRemove: _items.length == 1
                    ? null
                    : () => setState(() {
                          _items.removeAt(i).dispose();
                        }),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notiz (optional)',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check),
              label: const Text('Avis speichern'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.draft, this.onRemove});

  final _ItemDraft draft;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: draft.name,
              decoration: const InputDecoration(labelText: 'Artikel'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: TextField(
              controller: draft.qty,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Menge'),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close),
            tooltip: 'Position entfernen',
          ),
        ],
      ),
    );
  }
}

class _ItemDraft {
  _ItemDraft({
    required this.name,
    required this.qty,
    this.productId,
    this.sku,
    this.unit = 'Stück',
  });

  factory _ItemDraft.empty() =>
      _ItemDraft(name: TextEditingController(), qty: TextEditingController());

  factory _ItemDraft.fromItem(DeliveryAdviceItem item) => _ItemDraft(
        name: TextEditingController(text: item.name),
        qty: TextEditingController(text: item.announcedQuantity.toString()),
        productId: item.productId,
        sku: item.sku,
        unit: item.unit,
      );

  final TextEditingController name;
  final TextEditingController qty;
  final String? productId;
  final String? sku;
  final String unit;

  void dispose() {
    name.dispose();
    qty.dispose();
  }
}
