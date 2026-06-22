import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/order_cart.dart';
import '../models/product.dart';
import '../models/site_definition.dart';
import '../providers/inventory_provider.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/empty_state.dart';

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

int _defaultQuantity(Product product) {
  final reorder = product.reorderQuantity;
  if (reorder != null && reorder > 0) {
    return reorder;
  }
  return 1;
}

/// Fragt eine Menge für [product] ab (vorbelegt mit der vorgeschlagenen
/// Bestellmenge). Gibt die Menge (> 0) oder `null` bei Abbruch zurück.
Future<int?> showOrderQuantityDialog(
  BuildContext context,
  Product product, {
  int? initialQuantity,
  String title = 'In den Bestellkorb',
}) {
  final controller = TextEditingController(
    text: '${initialQuantity ?? _defaultQuantity(product)}',
  );
  return showDialog<int>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              product.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Menge (${product.unit})',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => Navigator.of(dialogContext)
                  .pop(int.tryParse(controller.text.trim())),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(int.tryParse(controller.text.trim())),
            child: const Text('Hinzufügen'),
          ),
        ],
      );
    },
  ).then((value) {
    controller.dispose();
    if (value == null || value <= 0) {
      return null;
    }
    return value;
  });
}

/// Picker über die Artikel eines Ladens (Suche + Kategorie-Filter). Liefert den
/// gewählten Artikel samt Menge zurück (oder `null`). Wiederverwendet für den
/// Korb und den Wochenlisten-Editor.
Future<({Product product, int quantity})?> showOrderProductPicker(
  BuildContext context, {
  required List<Product> products,
}) {
  return showModalBottomSheet<({Product product, int quantity})>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _ProductPickerSheet(products: products),
  );
}

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({required this.products});

  final List<Product> products;

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  String _search = '';
  String? _category;

  @override
  Widget build(BuildContext context) {
    final categories = <String>{
      for (final product in widget.products)
        if (product.category?.trim().isNotEmpty ?? false) product.category!.trim(),
    }.toList()
      ..sort();
    final query = _search.trim().toLowerCase();
    final filtered = widget.products.where((product) {
      if (!product.isActive) {
        return false;
      }
      if (_category != null && product.category?.trim() != _category) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return product.name.toLowerCase().contains(query) ||
          (product.sku?.toLowerCase().contains(query) ?? false) ||
          (product.barcode?.toLowerCase().contains(query) ?? false);
    }).toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Artikel auswählen',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Artikel suchen',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _search = value),
              ),
            ),
            if (categories.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: const Text('Alle'),
                        selected: _category == null,
                        onSelected: (_) => setState(() => _category = null),
                      ),
                    ),
                    for (final category in categories)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(category),
                          selected: _category == category,
                          onSelected: (_) =>
                              setState(() => _category = category),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: filtered.isEmpty
                  ? const EmptyState(
                      icon: Icons.inventory_2_outlined,
                      message: 'Keine passenden Artikel.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final product = filtered[index];
                        return ListTile(
                          title: Text(product.name),
                          subtitle: Text(
                            [
                              if (product.category?.isNotEmpty ?? false)
                                product.category!,
                              if (product.supplierName?.isNotEmpty ?? false)
                                product.supplierName!,
                            ].join('  ·  '),
                          ),
                          trailing: const Icon(Icons.add_circle_outline),
                          onTap: () => _pick(context, product),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, Product product) async {
    final quantity = await showOrderQuantityDialog(context, product);
    if (quantity != null && context.mounted) {
      Navigator.of(context).pop((product: product, quantity: quantity));
    }
  }
}

// ===========================================================================
// Schnell-Hinzufügen (FAB) – Laden- + Kategorie-Filter, Live in den Korb
// ===========================================================================

/// Öffnet den Schnell-Sheet: zeigt alle Artikel, filterbar nach Laden und
/// Kategorie, und legt sie per Tippen direkt in den Bestellkorb (Live-Menge je
/// Artikel sichtbar). Für JEDEN aktiven Mitarbeiter.
Future<void> showQuickAddCartSheet(
  BuildContext context, {
  required List<SiteDefinition> sites,
  String? initialSiteId,
  VoidCallback? onGoToCart,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _QuickAddCartSheet(
      sites: sites,
      initialSiteId: initialSiteId,
      onGoToCart: onGoToCart,
    ),
  );
}

class _QuickAddCartSheet extends StatefulWidget {
  const _QuickAddCartSheet({
    required this.sites,
    this.initialSiteId,
    this.onGoToCart,
  });

  final List<SiteDefinition> sites;
  final String? initialSiteId;
  final VoidCallback? onGoToCart;

  @override
  State<_QuickAddCartSheet> createState() => _QuickAddCartSheetState();
}

class _QuickAddCartSheetState extends State<_QuickAddCartSheet> {
  String _search = '';
  String? _category;
  late String? _siteId;

  @override
  void initState() {
    super.initState();
    _siteId = widget.initialSiteId;
  }

  @override
  Widget build(BuildContext context) {
    // context.watch -> der Sheet baut sich neu, sobald sich der Korb ändert
    // (Live-Mengen je Artikel).
    final inventory = context.watch<InventoryProvider>();
    final theme = Theme.of(context);

    final siteProducts = inventory.productsForSite(_siteId);
    final categories = <String>{
      for (final product in siteProducts)
        if (product.category?.trim().isNotEmpty ?? false)
          product.category!.trim(),
    }.toList()
      ..sort();

    final query = _search.trim().toLowerCase();
    final filtered = siteProducts.where((product) {
      if (!product.isActive) {
        return false;
      }
      if (_category != null && product.category?.trim() != _category) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return product.name.toLowerCase().contains(query) ||
          (product.sku?.toLowerCase().contains(query) ?? false) ||
          (product.barcode?.toLowerCase().contains(query) ?? false);
    }).toList();

    final totalInCart = inventory.cartItemCount(_siteId);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.add_shopping_cart_outlined),
                  const SizedBox(width: 8),
                  Text('In den Warenkorb',
                      style: theme.textTheme.titleMedium),
                ],
              ),
            ),
            if (widget.sites.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: DropdownButtonFormField<String?>(
                  initialValue: _siteId,
                  decoration: const InputDecoration(
                    labelText: 'Laden',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Alle Läden'),
                    ),
                    for (final site in widget.sites)
                      DropdownMenuItem<String?>(
                        value: site.id,
                        child: Text(site.name),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _siteId = value;
                    _category = null; // Kategorie kann je Laden abweichen
                  }),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Artikel suchen',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _search = value),
              ),
            ),
            if (categories.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: const Text('Alle'),
                        selected: _category == null,
                        onSelected: (_) => setState(() => _category = null),
                      ),
                    ),
                    for (final category in categories)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(category),
                          selected: _category == category,
                          onSelected: (_) =>
                              setState(() => _category = category),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: filtered.isEmpty
                  ? const EmptyState(
                      icon: Icons.inventory_2_outlined,
                      message: 'Keine passenden Artikel.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final product = filtered[index];
                        final inCart = inventory
                                .orderCartForSite(product.siteId)
                                ?.itemForProduct(product.id)
                                ?.quantity ??
                            0;
                        return _QuickAddRow(
                          product: product,
                          quantityInCart: inCart,
                          showSite: widget.sites.length > 1,
                          onAdd: () => inventory.addToCart(
                            product: product,
                            quantity: 1,
                          ),
                          onRemoveOne: inCart <= 0 || product.id == null
                              ? null
                              : () => inventory.setCartItemQuantity(
                                    siteId: product.siteId,
                                    productId: product.id!,
                                    quantity: inCart - 1,
                                  ),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Fertig'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onGoToCart?.call();
                        },
                        icon: const Icon(Icons.shopping_cart_outlined),
                        label: Text('Warenkorb ($totalInCart)'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAddRow extends StatelessWidget {
  const _QuickAddRow({
    required this.product,
    required this.quantityInCart,
    required this.showSite,
    required this.onAdd,
    required this.onRemoveOne,
  });

  final Product product;
  final int quantityInCart;
  final bool showSite;
  final VoidCallback onAdd;
  final VoidCallback? onRemoveOne;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final inCart = quantityInCart > 0;
    return ListTile(
      title: Text(product.name),
      subtitle: Text(
        [
          if (product.category?.isNotEmpty ?? false) product.category!,
          if (product.supplierName?.isNotEmpty ?? false) product.supplierName!,
          if (showSite && (product.siteName?.isNotEmpty ?? false))
            product.siteName!,
        ].join('  ·  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (inCart) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onRemoveOne,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text(
              '$quantityInCart',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ],
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'In den Warenkorb',
            onPressed: product.id == null ? null : onAdd,
            icon: Icon(
              inCart ? Icons.add_circle_outline : Icons.add_shopping_cart,
              color: colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Bestellkorb-Tab
// ===========================================================================

/// Der geteilte Wochen-Bestellkorb eines Ladens. Sichtbar für ALLE aktiven
/// Mitarbeiter; sie dürfen Artikel hineinlegen und Mengen anpassen. Nur die
/// Verwaltung (canManage) löst den Korb als echte Bestellung(en) aus oder
/// pflegt die Standard-Wochenliste.
class OrderCartTab extends StatelessWidget {
  const OrderCartTab({
    super.key,
    required this.siteId,
    required this.canManage,
    required this.sites,
    required this.onCheckoutDone,
  });

  /// Effektiver Laden (bei Mehr-Laden-Org ggf. `null`, wenn „Alle" gewählt ist).
  final String? siteId;
  final bool canManage;
  final List<SiteDefinition> sites;

  /// Wird nach erfolgreichem Checkout aufgerufen (z.B. um in den
  /// Bestellungen-Tab zu wechseln).
  final VoidCallback onCheckoutDone;

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();

    if (siteId == null) {
      return const EmptyState(
        icon: Icons.shopping_cart_outlined,
        message:
            'Bitte oben einen Laden wählen, um dessen Bestellkorb zu sehen.',
      );
    }

    final cart = inventory.orderCartForSite(siteId);
    final weekly = inventory.weeklyListForSite(siteId);
    final items = cart?.items ?? const <OrderListItem>[];
    final groups = _groupBySupplier(items);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: (weekly == null || weekly.items.isEmpty)
                    ? null
                    : () => _prefill(context, inventory),
                icon: const Icon(Icons.playlist_add_outlined),
                label: const Text('Standard-Wochenliste laden'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _addItem(context),
                icon: const Icon(Icons.add),
                label: const Text('Artikel'),
              ),
              if (canManage)
                TextButton.icon(
                  onPressed: () => _editWeekly(context),
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text('Wochenliste bearbeiten'),
                ),
              if (canManage && items.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _clearCart(context, inventory),
                  icon: const Icon(Icons.remove_shopping_cart_outlined),
                  label: const Text('Korb leeren'),
                ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const EmptyState(
                  icon: Icons.shopping_cart_outlined,
                  message:
                      'Der Bestellkorb ist leer. Lege Artikel über „Artikel" '
                      'hinein oder lade die Standard-Wochenliste.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                  children: [
                    for (final group in groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                        child: Text(
                          group.supplierName,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      for (final item in group.items)
                        _CartItemTile(
                          siteId: siteId!,
                          item: item,
                        ),
                    ],
                  ],
                ),
        ),
        if (canManage && items.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _CheckoutButton(
                itemCount: items.length,
                onCheckout: () => _checkout(context, inventory, groups),
              ),
            ),
          ),
      ],
    );
  }

  List<_SupplierGroup> _groupBySupplier(List<OrderListItem> items) {
    final byName = <String, List<OrderListItem>>{};
    for (final item in items) {
      final name = (item.supplierName?.trim().isNotEmpty ?? false)
          ? item.supplierName!.trim()
          : 'Ohne Lieferant';
      byName.putIfAbsent(name, () => []).add(item);
    }
    final groups = byName.entries
        .map((entry) => _SupplierGroup(entry.key, entry.value))
        .toList()
      ..sort((a, b) => a.supplierName.toLowerCase().compareTo(
            b.supplierName.toLowerCase(),
          ));
    return groups;
  }

  Future<void> _prefill(
    BuildContext context,
    InventoryProvider inventory,
  ) async {
    final added = await inventory.prefillCartFromWeeklyList(siteId!);
    if (!context.mounted) {
      return;
    }
    _toast(
      context,
      added > 0
          ? '$added Artikel aus der Standard-Wochenliste ergänzt.'
          : 'Alle Artikel der Standardliste sind bereits im Korb.',
    );
  }

  Future<void> _addItem(BuildContext context) {
    // Gleicher Schnell-Sheet wie der FAB (Laden- + Kategorie-Filter, Live-Add).
    return showQuickAddCartSheet(
      context,
      sites: sites,
      initialSiteId: siteId,
    );
  }

  Future<void> _clearCart(
    BuildContext context,
    InventoryProvider inventory,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bestellkorb leeren?'),
        content: const Text(
          'Alle Positionen im Bestellkorb dieses Ladens werden entfernt. '
          'Das kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leeren'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await inventory.clearCart(siteId!);
    if (context.mounted) {
      _toast(context, 'Bestellkorb geleert.');
    }
  }

  void _editWeekly(BuildContext context) {
    final site = sites
        .where((s) => s.id == siteId)
        .cast<SiteDefinition?>()
        .firstWhere((s) => true, orElse: () => null);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WeeklyOrderListEditorScreen(
          siteId: siteId!,
          siteName: site?.name,
        ),
      ),
    );
  }

  Future<void> _checkout(
    BuildContext context,
    InventoryProvider inventory,
    List<_SupplierGroup> groups,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bestellung auslösen?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Es ${groups.length == 1 ? 'wird' : 'werden'} ${groups.length} '
              'Bestellung${groups.length == 1 ? '' : 'en'} angelegt:',
            ),
            const SizedBox(height: 8),
            for (final group in groups)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• ${group.supplierName}: ${group.items.length} Position'
                  '${group.items.length == 1 ? '' : 'en'}',
                ),
              ),
            const SizedBox(height: 8),
            const Text('Der Bestellkorb wird danach geleert.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Bestellen'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      final ids = await inventory.checkoutCart(siteId!);
      if (!context.mounted) {
        return;
      }
      _toast(
        context,
        '${ids.length} Bestellung${ids.length == 1 ? '' : 'en'} erstellt – '
        'im Tab „Bestellungen".',
      );
      onCheckoutDone();
    } catch (error) {
      if (context.mounted) {
        _toast(context, 'Fehler beim Bestellen: $error');
      }
    }
  }
}

class _SupplierGroup {
  _SupplierGroup(this.supplierName, this.items);

  final String supplierName;
  final List<OrderListItem> items;
}

/// Bestellen-Button mit in-flight-Sperre gegen Doppel-Tap (Checkout ist nicht
/// idempotent; ein zweiter Tap während des Auslösens würde doppelte
/// Bestellungen riskieren).
class _CheckoutButton extends StatefulWidget {
  const _CheckoutButton({required this.itemCount, required this.onCheckout});

  final int itemCount;
  final Future<void> Function() onCheckout;

  @override
  State<_CheckoutButton> createState() => _CheckoutButtonState();
}

class _CheckoutButtonState extends State<_CheckoutButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await widget.onCheckout();
              } finally {
                if (mounted) {
                  setState(() => _busy = false);
                }
              }
            },
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.send_outlined),
      label: Text(
        'Bestellen (${widget.itemCount} Position'
        '${widget.itemCount == 1 ? '' : 'en'})',
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({required this.siteId, required this.item});

  final String siteId;
  final OrderListItem item;

  @override
  Widget build(BuildContext context) {
    final inventory = context.read<InventoryProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final productId = item.productId;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (item.category?.isNotEmpty ?? false) item.category!,
                      item.unit,
                      if (item.note?.isNotEmpty ?? false) item.note!,
                    ].join('  ·  '),
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            _QuantityStepper(
              value: item.quantity,
              onChanged: productId == null
                  ? null
                  : (value) => inventory.setCartItemQuantity(
                        siteId: siteId,
                        productId: productId,
                        quantity: value,
                      ),
            ),
            IconButton(
              tooltip: 'Entfernen',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_outline, color: colorScheme.error),
              onPressed: productId == null
                  ? null
                  : () => inventory.removeCartItem(
                        siteId: siteId,
                        productId: productId,
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kleiner +/- Stepper (min 1). [onChanged] null = deaktiviert.
class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: (onChanged == null || value <= 1)
              ? null
              : () => onChanged!(value - 1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: onChanged == null ? null : () => onChanged!(value + 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

// ===========================================================================
// Standard-Wochenliste bearbeiten (Manager)
// ===========================================================================

/// Editor für die Standard-Wochenliste eines Ladens (die feste Grundbestellung,
/// die den Korb vorbefüllt). Lokaler Entwurf, der erst beim Speichern via
/// [InventoryProvider.saveWeeklyList] geschrieben wird.
class WeeklyOrderListEditorScreen extends StatefulWidget {
  const WeeklyOrderListEditorScreen({
    super.key,
    required this.siteId,
    this.siteName,
  });

  final String siteId;
  final String? siteName;

  @override
  State<WeeklyOrderListEditorScreen> createState() =>
      _WeeklyOrderListEditorScreenState();
}

class _WeeklyOrderListEditorScreenState
    extends State<WeeklyOrderListEditorScreen> {
  late List<OrderListItem> _items;
  bool _saving = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) {
      return;
    }
    _loaded = true;
    final inventory = context.read<InventoryProvider>();
    _items = [
      ...?inventory.weeklyListForSite(widget.siteId)?.items,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: 'Warenwirtschaft',
            onTap: () => Navigator.of(context).pop(),
          ),
          const BreadcrumbItem(label: 'Standard-Wochenliste'),
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
                if (widget.siteName?.isNotEmpty ?? false)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        const Icon(Icons.storefront_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(widget.siteName!),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _addItem(context, inventory),
                      icon: const Icon(Icons.add),
                      label: const Text('Artikel'),
                    ),
                  ),
                ),
                Expanded(
                  child: _items.isEmpty
                      ? const EmptyState(
                          icon: Icons.playlist_add_outlined,
                          message:
                              'Noch keine Artikel in der Standard-Wochenliste. '
                              'Füge die Sachen hinzu, die ihr jede Woche '
                              'bestellt.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return Card(
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 6, 4, 6),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600),
                                          ),
                                          Text(
                                            [
                                              if (item.category?.isNotEmpty ??
                                                  false)
                                                item.category!,
                                              item.unit,
                                            ].join('  ·  '),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    _QuantityStepper(
                                      value: item.quantity,
                                      onChanged: (value) => setState(() {
                                        _items[index] =
                                            item.copyWith(quantity: value);
                                      }),
                                    ),
                                    IconButton(
                                      tooltip: 'Entfernen',
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => setState(
                                          () => _items.removeAt(index)),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _saving ? null : () => _save(context, inventory),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Speichern'),
          ),
        ),
      ),
    );
  }

  Future<void> _addItem(
    BuildContext context,
    InventoryProvider inventory,
  ) async {
    final products = inventory.productsForSite(widget.siteId);
    if (products.isEmpty) {
      _toast(context, 'Für diesen Laden gibt es noch keine Artikel.');
      return;
    }
    final picked = await showOrderProductPicker(context, products: products);
    if (picked == null) {
      return;
    }
    setState(() {
      final index =
          _items.indexWhere((item) => item.productId == picked.product.id);
      final next = OrderListItem(
        productId: picked.product.id,
        name: picked.product.name,
        sku: picked.product.sku,
        category: picked.product.category,
        unit: picked.product.unit,
        quantity: picked.quantity,
        supplierId: picked.product.supplierId,
        supplierName: picked.product.supplierName,
      );
      if (index >= 0) {
        _items[index] = next;
      } else {
        _items.add(next);
      }
    });
  }

  Future<void> _save(
    BuildContext context,
    InventoryProvider inventory,
  ) async {
    setState(() => _saving = true);
    final list = SiteOrderList(
      orgId: '',
      siteId: widget.siteId,
      siteName: widget.siteName,
      kind: OrderListKind.weeklyTemplate,
      items: List<OrderListItem>.unmodifiable(_items),
    );
    try {
      await inventory.saveWeeklyList(list);
      if (context.mounted) {
        Navigator.of(context).pop();
        _toast(context, 'Standard-Wochenliste gespeichert.');
      }
    } catch (error) {
      if (context.mounted) {
        setState(() => _saving = false);
        _toast(context, 'Fehler: $error');
      }
    }
  }
}
