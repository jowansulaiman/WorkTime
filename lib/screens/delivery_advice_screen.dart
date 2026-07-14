import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/delivery_advice.dart';
import '../models/product_batch.dart';
import '../models/purchase_order.dart';
import '../models/stock_movement.dart';
import '../providers/inventory_provider.dart';
import '../theme/theme_extensions.dart';
import '../widgets/delivery_advice_sheet.dart';
import '../widgets/goods_receipt_sheet.dart';
import '../widgets/purchase_receipt_sheet.dart';

/// **WW-4 — Lieferavis-Verwaltung (imperativ via `Navigator.push`, KEINE
/// go_router-Route — Kopplung #7 entfällt bewusst).** Listet angekündigte
/// Lieferungen, erlaubt Anlage/Bearbeitung und startet den Wareneingang gegen
/// ein Avis (WW-7).
class DeliveryAdviceScreen extends StatefulWidget {
  const DeliveryAdviceScreen({
    super.key,
    required this.siteId,
    this.siteName,
  });

  /// Laden-Scope für Neuanlage. Die Liste zeigt alle Avise dieses Ladens.
  final String siteId;
  final String? siteName;

  @override
  State<DeliveryAdviceScreen> createState() => _DeliveryAdviceScreenState();
}

class _DeliveryAdviceScreenState extends State<DeliveryAdviceScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final advices = inventory.advicesForSite(widget.siteId);
    final announced = advices
        .where((a) => a.status == DeliveryAdviceStatus.announced)
        .toList();
    final received =
        advices.where((a) => a.status == DeliveryAdviceStatus.received).toList();
    final cancelled = advices
        .where((a) => a.status == DeliveryAdviceStatus.cancelled)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Lieferavis')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _create(inventory),
        icon: const Icon(Icons.add),
        label: const Text('Avis erfassen'),
      ),
      body: advices.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Noch keine Lieferavise erfasst.\n\nEin Avis kündigt eine '
                  'Lieferung an — auch ohne oder über mehrere Bestellungen.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: [
                if (announced.isNotEmpty) ...[
                  _sectionHeader(context, 'Angekündigt', announced.length),
                  for (final a in announced) _adviceCard(inventory, a),
                ],
                if (received.isNotEmpty) ...[
                  _sectionHeader(context, 'Eingegangen', received.length),
                  for (final a in received) _adviceCard(inventory, a),
                ],
                if (cancelled.isNotEmpty) ...[
                  _sectionHeader(context, 'Storniert', cancelled.length),
                  for (final a in cancelled) _adviceCard(inventory, a),
                ],
              ],
            ),
    );
  }

  Widget _sectionHeader(BuildContext context, String label, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Text(
          '$label ($count)',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      );

  Widget _adviceCard(InventoryProvider inventory, DeliveryAdvice advice) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final dateLabel =
        DateFormat('EEE, d. MMM y', 'de_DE').format(advice.expectedDate);
    final (chipColor, chipBg, chipText) = switch (advice.status) {
      DeliveryAdviceStatus.announced => (
          appColors.info,
          appColors.infoContainer,
          'Angekündigt'
        ),
      DeliveryAdviceStatus.received => (
          appColors.success,
          appColors.successContainer,
          'Eingegangen'
        ),
      DeliveryAdviceStatus.cancelled => (
          theme.colorScheme.onSurfaceVariant,
          theme.colorScheme.surfaceContainerHighest,
          'Storniert'
        ),
    };
    final title = advice.supplierName ?? advice.reference ?? 'Lieferavis';
    final isOpen = advice.status == DeliveryAdviceStatus.announced;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Erwartet: $dateLabel'),
            Text('${advice.itemCount} Position(en) · '
                '${advice.totalAnnouncedQuantity} Stk avisiert'),
            if (advice.reference != null && advice.supplierName != null)
              Text('Ref.: ${advice.reference}',
                  style: theme.textTheme.bodySmall),
          ],
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Chip(
              label: Text(chipText,
                  style: TextStyle(color: chipColor, fontSize: 11)),
              backgroundColor: chipBg,
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
            ),
            PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (v) => _onAction(inventory, advice, v),
              itemBuilder: (_) => [
                if (isOpen)
                  const PopupMenuItem(
                    value: 'receive',
                    child: ListTile(
                      leading: Icon(Icons.inventory_2_outlined),
                      title: Text('Wareneingang starten'),
                    ),
                  ),
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Bearbeiten'),
                  ),
                ),
                if (isOpen)
                  const PopupMenuItem(
                    value: 'cancel',
                    child: ListTile(
                      leading: Icon(Icons.block_outlined),
                      title: Text('Stornieren'),
                    ),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Löschen'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onAction(
    InventoryProvider inventory,
    DeliveryAdvice advice,
    String value,
  ) async {
    switch (value) {
      case 'receive':
        await _startReceipt(inventory, advice);
        break;
      case 'edit':
        await _edit(inventory, advice);
        break;
      case 'cancel':
        await _guard(() => inventory.cancelAdvice(advice.id!), 'Avis storniert.');
        break;
      case 'delete':
        final ok = await _confirmDelete();
        if (ok) {
          await _guard(
              () => inventory.deleteDeliveryAdvice(advice.id!), 'Avis gelöscht.');
        }
        break;
    }
  }

  Future<void> _create(InventoryProvider inventory) async {
    final advice = await showDeliveryAdviceSheet(
      context,
      siteId: widget.siteId,
      siteName: widget.siteName,
      suppliers: inventory.suppliers,
    );
    if (advice == null) return;
    await _guard(() => inventory.saveDeliveryAdvice(advice), 'Avis gespeichert.');
  }

  Future<void> _edit(InventoryProvider inventory, DeliveryAdvice advice) async {
    final edited = await showDeliveryAdviceSheet(
      context,
      siteId: advice.siteId,
      siteName: advice.siteName,
      existing: advice,
      suppliers: inventory.suppliers,
    );
    if (edited == null) return;
    await _guard(
        () => inventory.saveDeliveryAdvice(edited), 'Avis aktualisiert.');
  }

  /// **WW-7 — Wareneingang gegen Avis.**
  /// - Mit `purchaseOrderId` und offener Bestellung → voller
  ///   `purchase_receipt_sheet`, dann Avis auf `received`.
  /// - Ohne Bezug → geführter `showGoodsReceiptSheet` je auflösbarer
  ///   Artikelposition (bucht Bestand + optional MHD/Charge), dann `received`.
  Future<void> _startReceipt(
    InventoryProvider inventory,
    DeliveryAdvice advice,
  ) async {
    final poId = advice.purchaseOrderId;
    if (poId != null && poId.isNotEmpty) {
      PurchaseOrder? order;
      for (final o in inventory.purchaseOrders) {
        if (o.id == poId) {
          order = o;
          break;
        }
      }
      if (order == null || order.closedAt != null) {
        _toast('Verknüpfte Bestellung nicht offen — bitte manuell buchen.');
        return;
      }
      final result = await showPurchaseReceiptSheet(context, order: order);
      if (result == null || result.lines.isEmpty) return;
      await _guard(() async {
        await inventory.receiveOrder(
          orderId: order!.id!,
          receivedByItemIndex: result.lines,
          deliveryNoteNumber: result.deliveryNoteNumber,
          updatePurchasePrice: result.updatePurchasePrice,
        );
        await inventory.markAdviceReceived(advice.id!);
      }, 'Wareneingang gebucht, Avis erledigt.');
      return;
    }

    // Freier Eingang: je Position mit auflösbarem Artikel ein geführtes Sheet.
    var booked = 0;
    var skipped = 0;
    for (final item in advice.items) {
      final product = item.productId == null ? null : inventory.productById(item.productId!);
      if (product == null || product.id == null) {
        skipped++;
        continue;
      }
      if (!mounted) return;
      final input = await showGoodsReceiptSheet(
        context,
        product: product,
        initialQuantity: item.announcedQuantity,
      );
      if (input == null || input.quantity <= 0) continue;
      try {
        await inventory.adjustStock(
          productId: product.id!,
          delta: input.quantity,
          type: StockMovementType.receipt,
          reason: 'Avis-Wareneingang',
        );
        if (input.hasBatch) {
          await inventory.saveBatch(ProductBatch(
            orgId: product.orgId,
            siteId: product.siteId,
            productId: product.id!,
            productName: product.name,
            expiryDate: ProductBatch.normalizeDay(input.expiryDate!),
            quantity: input.quantity,
            note: input.lot,
          ));
        }
        booked++;
      } catch (error) {
        if (mounted) _toast('Fehler beim Buchen: $error');
      }
    }
    if (booked > 0) {
      await inventory.markAdviceReceived(advice.id!);
    }
    if (!mounted) return;
    _toast(skipped == 0
        ? '$booked Position(en) gebucht, Avis erledigt.'
        : '$booked gebucht, $skipped ohne Artikelbezug übersprungen.');
  }

  Future<bool> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Avis löschen?'),
        content: const Text('Das Lieferavis wird dauerhaft entfernt.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Löschen')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _guard(Future<void> Function() action, String successMsg) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _toast(successMsg);
    } catch (error) {
      if (mounted) _toast('Fehler: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
