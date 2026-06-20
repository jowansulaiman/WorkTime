import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/price_history_entry.dart';
import '../models/product.dart';
import '../providers/inventory_provider.dart';

final NumberFormat _euroFormat =
    NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
final DateFormat _dateFormat = DateFormat('dd.MM.yyyy HH:mm', 'de_DE');

String _cents(int? cents) =>
    cents == null ? '–' : _euroFormat.format(cents / 100);

/// Zeigt die Preis-Historie (EK/VK) eines Artikels als Bottom-Sheet.
///
/// Liest ueber [InventoryProvider.priceHistoryFor] — in cloud/hybrid aus der
/// Firestore-Subcollection, in local-Modus aus dem lokalen Spiegel. Wird vom
/// Scanner (Treffer-Karte) genutzt; ist bewusst wiederverwendbar gehalten.
Future<void> showPriceHistorySheet(
  BuildContext context, {
  required Product product,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _PriceHistorySheet(product: product),
  );
}

class _PriceHistorySheet extends StatelessWidget {
  const _PriceHistorySheet({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inventory = context.read<InventoryProvider>();
    final productId = product.id;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Preisverlauf', style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(product.name, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          FutureBuilder<List<PriceHistoryEntry>>(
            future: productId == null
                ? Future<List<PriceHistoryEntry>>.value(
                    const <PriceHistoryEntry>[])
                : inventory.priceHistoryFor(productId),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final entries = snapshot.data ?? const <PriceHistoryEntry>[];
              if (entries.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Noch keine Preisaenderungen erfasst.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final entry = entries[index];
                    return ListTile(
                      leading: Icon(
                        entry.field == PriceField.selling
                            ? Icons.sell_outlined
                            : Icons.shopping_cart_outlined,
                      ),
                      title: Text(
                        '${entry.field.label}: '
                        '${_cents(entry.oldCents)} → ${_cents(entry.newCents)}',
                      ),
                      subtitle: entry.changedAt == null
                          ? null
                          : Text(_dateFormat.format(entry.changedAt!)),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
