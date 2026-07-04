import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../models/purchase_order.dart';
import '../models/site_definition.dart';
import '../models/supplier.dart';
import '../providers/inventory_provider.dart';
import '../widgets/action_fab.dart';
import '../widgets/breadcrumb_app_bar.dart';
import 'inventory_screen.dart';

final DateFormat _dateFormat = DateFormat('dd.MM.yyyy', 'de_DE');

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Color _statusColor(PurchaseOrderStatus status, ColorScheme colorScheme) {
  return switch (status) {
    PurchaseOrderStatus.draft => colorScheme.outline,
    PurchaseOrderStatus.ordered => colorScheme.primary,
    PurchaseOrderStatus.partiallyReceived => colorScheme.tertiary,
    PurchaseOrderStatus.received => colorScheme.secondary,
    PurchaseOrderStatus.cancelled => colorScheme.error,
  };
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final PurchaseOrderStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _statusColor(status, colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ===========================================================================
// Bestellung erstellen
// ===========================================================================

class PurchaseOrderEditorScreen extends StatefulWidget {
  const PurchaseOrderEditorScreen({
    super.key,
    required this.sites,
    required this.initialSiteId,
    this.prefillReorder = false,
  });

  final List<SiteDefinition> sites;
  final String? initialSiteId;
  final bool prefillReorder;

  @override
  State<PurchaseOrderEditorScreen> createState() =>
      _PurchaseOrderEditorScreenState();
}

class _PurchaseOrderEditorScreenState extends State<PurchaseOrderEditorScreen> {
  String? _siteId;
  String? _supplierId;
  final Map<String, int> _quantities = {};
  final TextEditingController _notes = TextEditingController();
  bool _prefilledForSupplier = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _siteId = widget.initialSiteId;
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final suppliers = inventory.activeSuppliers;
    final candidates = _candidates(inventory);
    final selectedCount =
        candidates.where((p) => (_quantities[p.id] ?? 0) > 0).length;

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: 'Warenwirtschaft',
            onTap: () => Navigator.of(context).pop(),
          ),
          const BreadcrumbItem(label: 'Neue Bestellung'),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    children: [
                      if (widget.sites.length > 1)
                        DropdownButtonFormField<String>(
                          initialValue: _siteId,
                          decoration: const InputDecoration(
                            labelText: 'Laden',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final site in widget.sites)
                              DropdownMenuItem(
                                value: site.id,
                                child: Text(site.name),
                              ),
                          ],
                          onChanged: (value) => setState(() {
                            _siteId = value;
                          }),
                        ),
                      if (widget.sites.length > 1) const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _supplierId,
                        decoration: const InputDecoration(
                          labelText: 'Lieferant *',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final supplier in suppliers)
                            DropdownMenuItem(
                              value: supplier.id,
                              child: Text(supplier.name),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _supplierId = value;
                          _prefilledForSupplier = false;
                        }),
                      ),
                    ],
                  ),
                ),
                if (_supplierId == null)
                  const Expanded(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Bitte zuerst einen Lieferanten waehlen.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: candidates.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Fuer diesen Lieferanten und Laden gibt es keine '
                                'Artikel. Lege Artikel an oder weise sie dem '
                                'Lieferanten zu.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: candidates.length + 1,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              if (index == candidates.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: TextField(
                                    controller: _notes,
                                    decoration: const InputDecoration(
                                      labelText: 'Notiz zur Bestellung',
                                      border: OutlineInputBorder(),
                                    ),
                                    maxLines: 2,
                                  ),
                                );
                              }
                              final product = candidates[index];
                              return _OrderLineEditor(
                                product: product,
                                quantity: _quantities[product.id] ?? 0,
                                onChanged: (value) => setState(() {
                                  _quantities[product.id!] = value;
                                }),
                              );
                            },
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _supplierId == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving || selectedCount == 0
                            ? null
                            : () => _save(inventory, asOrdered: false),
                        child: const Text('Als Entwurf'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving || selectedCount == 0
                            ? null
                            : () => _save(inventory, asOrdered: true),
                        icon: const Icon(Icons.send),
                        label: Text('Bestellen ($selectedCount)'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  List<Product> _candidates(InventoryProvider inventory) {
    if (_supplierId == null) {
      return const [];
    }
    final freq = inventory.orderFrequencyByProduct(siteId: _siteId);
    final products = inventory
        .productsForSite(_siteId)
        .where((product) =>
            product.isActive && product.supplierId == _supplierId)
        .toList()
      ..sort((a, b) {
        // Nachzubestellende zuerst.
        if (a.needsReorder != b.needsReorder) {
          return a.needsReorder ? -1 : 1;
        }
        // Dann häufig bestellte Artikel.
        final fa = freq[a.id] ?? 0;
        final fb = freq[b.id] ?? 0;
        if (fa != fb) {
          return fb.compareTo(fa);
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    if (widget.prefillReorder && !_prefilledForSupplier) {
      _prefilledForSupplier = true;
      for (final product in products) {
        if (product.needsReorder && product.id != null) {
          _quantities[product.id!] = product.suggestedReorderQuantity;
        }
      }
    }
    return products;
  }

  Future<void> _save(
    InventoryProvider inventory, {
    required bool asOrdered,
  }) async {
    final supplier = inventory.supplierById(_supplierId);
    final candidates = inventory
        .productsForSite(_siteId)
        .where((product) => (_quantities[product.id] ?? 0) > 0)
        .toList();
    if (supplier == null || candidates.isEmpty) {
      return;
    }
    final site = widget.sites
        .where((s) => s.id == _siteId)
        .cast<SiteDefinition?>()
        .firstWhere((s) => true, orElse: () => null);

    final items = candidates
        .map(
          (product) => PurchaseOrderItem(
            productId: product.id,
            name: product.name,
            sku: product.sku,
            unit: product.unit,
            quantityOrdered: _quantities[product.id]!,
            unitPriceCents: product.purchasePriceCents,
            // USt-Satz aus dem Artikel übernehmen → Käufe echt netto/brutto
            // (M6-B). Der EK gilt als netto (B2B).
            taxRatePercent: product.taxRatePercent,
          ),
        )
        .toList();

    final order = PurchaseOrder(
      orgId: '',
      siteId: _siteId ?? '',
      siteName: site?.name,
      supplierId: supplier.id!,
      supplierName: supplier.name,
      status: asOrdered
          ? PurchaseOrderStatus.ordered
          : PurchaseOrderStatus.draft,
      items: items,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      orderedAt: asOrdered ? DateTime.now() : null,
    );

    setState(() => _saving = true);
    try {
      await inventory.savePurchaseOrder(order);
      if (mounted) {
        Navigator.of(context).pop();
        _toast(
          context,
          asOrdered ? 'Bestellung abgeschickt.' : 'Entwurf gespeichert.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _toast(context, 'Fehler: $error');
      }
    }
  }
}

class _OrderLineEditor extends StatelessWidget {
  const _OrderLineEditor({
    required this.product,
    required this.quantity,
    required this.onChanged,
  });

  final Product product;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      'Bestand ${product.currentStock}',
                      if (product.minStock > 0) 'Min ${product.minStock}',
                      if (product.purchasePriceCents != null)
                        'EK ${formatCents(product.purchasePriceCents)}',
                    ].join('  ·  '),
                    style: TextStyle(
                      color: product.needsReorder
                          ? colorScheme.tertiary
                          : colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            _Stepper(
              value: quantity,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(value + 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

// ===========================================================================
// Bestellung Detail + Wareneingang
// ===========================================================================

class PurchaseOrderDetailScreen extends StatelessWidget {
  const PurchaseOrderDetailScreen({
    super.key,
    required this.orderId,
    required this.sites,
    required this.canManage,
  });

  final String orderId;
  final List<SiteDefinition> sites;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final order = inventory.purchaseOrders
        .where((o) => o.id == orderId)
        .cast<PurchaseOrder?>()
        .firstWhere((o) => true, orElse: () => null);

    if (order == null) {
      return Scaffold(
        appBar: BreadcrumbAppBar(
          breadcrumbs: [
            BreadcrumbItem(
              label: 'Warenwirtschaft',
              onTap: () => Navigator.of(context).pop(),
            ),
            const BreadcrumbItem(label: 'Bestellung'),
          ],
        ),
        body: const Center(child: Text('Bestellung nicht gefunden.')),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final supplier = inventory.supplierById(order.supplierId);

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: 'Warenwirtschaft',
            onTap: () => Navigator.of(context).pop(),
          ),
          BreadcrumbItem(label: order.orderNumber ?? 'Bestellung'),
        ],
        actions: [
          IconButton(
            tooltip: 'Bestelltext kopieren',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () => _copyOrderText(context, order, supplier),
          ),
          if (canManage)
            PopupMenuButton<String>(
              onSelected: (value) => _onMenu(context, inventory, order, value),
              itemBuilder: (_) => [
                if (order.status.acceptsReceipt)
                  const PopupMenuItem(
                    value: 'receive',
                    child: Text('Wareneingang buchen'),
                  ),
                if (order.status == PurchaseOrderStatus.draft)
                  const PopupMenuItem(
                    value: 'order',
                    child: Text('Als bestellt markieren'),
                  ),
                if (!order.status.isClosed)
                  const PopupMenuItem(
                    value: 'cancel',
                    child: Text('Stornieren'),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Löschen'),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: canManage && order.status.acceptsReceipt
          ? ExpandableFab(
              heroTag: 'purchase_order_receive_fab',
              actions: [
                FabAction(
                  icon: Icons.move_to_inbox_outlined,
                  label: 'Wareneingang',
                  onPressed: () => _receive(context, inventory, order),
                ),
              ],
            )
          : null,
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                order.supplierName ?? 'Lieferant',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            _StatusBadge(status: order.status),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (order.siteName?.isNotEmpty ?? false)
                          _InfoRow(
                              icon: Icons.storefront_outlined,
                              text: order.siteName!),
                        if (order.orderedAt != null)
                          _InfoRow(
                            icon: Icons.send_outlined,
                            text:
                                'Bestellt am ${_dateFormat.format(order.orderedAt!)}',
                          ),
                        if (order.receivedAt != null)
                          _InfoRow(
                            icon: Icons.check_circle_outline,
                            text:
                                'Geliefert am ${_dateFormat.format(order.receivedAt!)}',
                          ),
                        if (order.notes?.isNotEmpty ?? false)
                          _InfoRow(
                              icon: Icons.notes_outlined, text: order.notes!),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Positionen',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                for (final item in order.items)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(item.name),
                      subtitle: Text(
                        'Bestellt: ${item.quantityOrdered} ${item.unit}'
                        '  ·  Geliefert: ${item.quantityReceived}'
                        '${item.unitPriceCents != null ? '  ·  ${formatCents(item.lineTotalCents)}' : ''}',
                      ),
                      trailing: item.isFullyReceived
                          ? Icon(Icons.check_circle,
                              color: colorScheme.secondary)
                          : (item.quantityReceived > 0
                              ? Icon(Icons.timelapse,
                                  color: colorScheme.tertiary)
                              : null),
                    ),
                  ),
                if (order.hasPrices)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Gesamt (EK)',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          formatCents(order.totalCents),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    InventoryProvider inventory,
    PurchaseOrder order,
    String value,
  ) async {
    switch (value) {
      case 'receive':
        await _receive(context, inventory, order);
        break;
      case 'order':
        await inventory.markOrderAsOrdered(order);
        if (context.mounted) {
          _toast(context, 'Als bestellt markiert.');
        }
        break;
      case 'cancel':
        await inventory.cancelOrder(order);
        if (context.mounted) {
          _toast(context, 'Bestellung storniert.');
        }
        break;
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Bestellung löschen?'),
            content: const Text('Die Bestellung wird unwiderruflich geloescht.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Löschen'),
              ),
            ],
          ),
        );
        if (confirmed == true && order.id != null) {
          await inventory.deletePurchaseOrder(order.id!);
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        }
        break;
    }
  }

  Future<void> _receive(
    BuildContext context,
    InventoryProvider inventory,
    PurchaseOrder order,
  ) async {
    final result = await showDialog<Map<int, int>>(
      context: context,
      builder: (_) => _ReceiveDialog(order: order),
    );
    if (result != null && result.isNotEmpty && order.id != null) {
      try {
        await inventory.receiveOrder(
          orderId: order.id!,
          receivedByItemIndex: result,
        );
        if (context.mounted) {
          _toast(context, 'Wareneingang gebucht – Bestaende aktualisiert.');
        }
      } catch (error) {
        if (context.mounted) {
          _toast(context, 'Fehler: $error');
        }
      }
    }
  }

  void _copyOrderText(
    BuildContext context,
    PurchaseOrder order,
    Supplier? supplier,
  ) {
    final buffer = StringBuffer()
      ..writeln('Bestellung ${order.orderNumber ?? ''}'.trim())
      ..writeln('Lieferant: ${order.supplierName ?? ''}');
    if (supplier?.customerNumber?.isNotEmpty ?? false) {
      buffer.writeln('Kundennr.: ${supplier!.customerNumber}');
    }
    if (order.siteName?.isNotEmpty ?? false) {
      buffer.writeln('Laden: ${order.siteName}');
    }
    buffer.writeln('');
    for (final item in order.items) {
      buffer.writeln('- ${item.quantityOrdered} ${item.unit}  ${item.name}'
          '${item.sku != null ? ' (${item.sku})' : ''}');
    }
    if (order.notes?.isNotEmpty ?? false) {
      buffer
        ..writeln('')
        ..writeln('Notiz: ${order.notes}');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    _toast(context, 'Bestelltext in die Zwischenablage kopiert.');
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ReceiveDialog extends StatefulWidget {
  const _ReceiveDialog({required this.order});

  final PurchaseOrder order;

  @override
  State<_ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends State<_ReceiveDialog> {
  late final Map<int, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {};
    for (var i = 0; i < widget.order.items.length; i++) {
      final outstanding = widget.order.items[i].outstandingQuantity;
      _controllers[i] = TextEditingController(
        text: outstanding > 0 ? outstanding.toString() : '0',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.order.items;
    return AlertDialog(
      title: const Text('Wareneingang buchen'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < items.length; i++)
                if (items[i].outstandingQuantity > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(items[i].name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              Text(
                                'offen: ${items[i].outstandingQuantity} ${items[i].unit}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: _controllers[i],
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              if (items.every((item) => item.outstandingQuantity <= 0))
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Alle Positionen sind bereits vollstaendig geliefert.'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            final result = <int, int>{};
            for (final entry in _controllers.entries) {
              final qty = int.tryParse(entry.value.text.trim()) ?? 0;
              if (qty > 0) {
                result[entry.key] = qty;
              }
            }
            Navigator.of(context).pop(result);
          },
          child: const Text('Buchen'),
        ),
      ],
    );
  }
}
