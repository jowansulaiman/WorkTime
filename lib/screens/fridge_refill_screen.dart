import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/fridge_refill.dart';
import '../models/product.dart';
import '../models/site_definition.dart';
import '../providers/inventory_provider.dart';
import '../widgets/empty_state.dart';

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

// ===========================================================================
// Kühlschrank-Tab: was muss aus dem Lager nachgefüllt werden?
// ===========================================================================

/// Die geteilte Kühlschrank-Nachfüllliste eines Ladens. Sichtbar für ALLE
/// aktiven Mitarbeiter; jeder darf markieren, was nachgefüllt werden muss, und
/// erledigte Positionen abhaken. „Aus dem Lager holen" listet alle offenen
/// Positionen.
class FridgeRefillTab extends StatelessWidget {
  const FridgeRefillTab({
    super.key,
    required this.siteId,
    required this.canManage,
    required this.sites,
  });

  /// Effektiver Laden (bei Mehr-Laden-Org ggf. `null`, wenn „Alle" gewählt ist).
  final String? siteId;
  final bool canManage;
  final List<SiteDefinition> sites;

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();

    if (siteId == null) {
      return const EmptyState(
        icon: Icons.kitchen_outlined,
        message:
            'Bitte oben einen Laden wählen, um dessen Kühlschrank-Liste zu '
            'sehen.',
      );
    }

    final items = inventory.fridgeRefillItems(siteId);
    final open = items.where((item) => !item.done).toList();
    final done = items.where((item) => item.done).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => showFridgeRefillAddSheet(
                  context,
                  sites: sites,
                  initialSiteId: siteId,
                ),
                icon: const Icon(Icons.add),
                label: const Text('Zur Liste hinzufügen'),
              ),
              if (done.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _clearDone(context, inventory),
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: Text('Erledigte aufräumen (${done.length})'),
                ),
              if (canManage && items.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _clearAll(context, inventory),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Liste leeren'),
                ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const EmptyState(
                  icon: Icons.kitchen_outlined,
                  message:
                      'Die Kühlschrank-Liste ist leer. Markiere über „Zur Liste '
                      'hinzufügen", welche Getränke aus dem Lager nachgefüllt '
                      'werden müssen.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                  children: [
                    if (open.isNotEmpty) ...[
                      _SectionHeader(
                        icon: Icons.move_to_inbox_outlined,
                        label: 'Aus dem Lager holen (${open.length})',
                      ),
                      for (final item in open)
                        _FridgeItemTile(siteId: siteId!, item: item),
                    ],
                    if (done.isNotEmpty) ...[
                      _SectionHeader(
                        icon: Icons.check_circle_outline,
                        label: 'Erledigt (${done.length})',
                      ),
                      for (final item in done)
                        _FridgeItemTile(siteId: siteId!, item: item),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _clearDone(
    BuildContext context,
    InventoryProvider inventory,
  ) async {
    await inventory.clearFridgeRefillDone(siteId!);
    if (context.mounted) {
      _toast(context, 'Erledigte Positionen entfernt.');
    }
  }

  Future<void> _clearAll(
    BuildContext context,
    InventoryProvider inventory,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Liste leeren?'),
        content: const Text(
          'Alle Positionen der Kühlschrank-Liste dieses Ladens werden '
          'entfernt. Das kann nicht rückgängig gemacht werden.',
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
    await inventory.clearFridgeRefillList(siteId!);
    if (context.mounted) {
      _toast(context, 'Kühlschrank-Liste geleert.');
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _FridgeItemTile extends StatelessWidget {
  const _FridgeItemTile({required this.siteId, required this.item});

  final String siteId;
  final FridgeRefillItem item;

  @override
  Widget build(BuildContext context) {
    final inventory = context.read<InventoryProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final done = item.done;
    final subtitle = [
      if (item.category?.isNotEmpty ?? false) item.category!,
      '${item.quantity} ${item.unit}',
      if (item.note?.isNotEmpty ?? false) item.note!,
      if (item.addedByName?.isNotEmpty ?? false) 'von ${item.addedByName}',
    ].join('  ·  ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
        child: Row(
          children: [
            Checkbox(
              value: done,
              onChanged: (value) => inventory.setFridgeRefillItemDone(
                siteId: siteId,
                itemId: item.id,
                done: value ?? false,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done ? colorScheme.onSurfaceVariant : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (!done)
              _FridgeQtyStepper(
                value: item.quantity,
                onChanged: (value) => inventory.setFridgeRefillItemQuantity(
                  siteId: siteId,
                  itemId: item.id,
                  quantity: value,
                ),
              ),
            IconButton(
              tooltip: 'Entfernen',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_outline, color: colorScheme.error),
              onPressed: () => inventory.removeFridgeRefillItem(
                siteId: siteId,
                itemId: item.id,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kleiner +/- Stepper (min 1).
class _FridgeQtyStepper extends StatelessWidget {
  const _FridgeQtyStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: value <= 1 ? null : () => onChanged(value - 1),
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
          onPressed: () => onChanged(value + 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

// ===========================================================================
// Hinzufügen-Sheet: Artikel suchen ODER freien Text eintippen
// ===========================================================================

/// Öffnet den Sheet, um Sachen auf die Kühlschrank-Nachfüllliste zu setzen:
/// erfasste Artikel (such-/kategoriegefiltert) per Tippen, ODER einen freien
/// Text eintragen, wenn die Sorte (noch) nicht als Artikel existiert. Für JEDEN
/// aktiven Mitarbeiter.
Future<void> showFridgeRefillAddSheet(
  BuildContext context, {
  required List<SiteDefinition> sites,
  String? initialSiteId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FridgeAddSheet(
      sites: sites,
      initialSiteId: initialSiteId,
    ),
  );
}

class _FridgeAddSheet extends StatefulWidget {
  const _FridgeAddSheet({required this.sites, this.initialSiteId});

  final List<SiteDefinition> sites;
  final String? initialSiteId;

  @override
  State<_FridgeAddSheet> createState() => _FridgeAddSheetState();
}

class _FridgeAddSheetState extends State<_FridgeAddSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  String? _category;
  late String? _siteId;

  @override
  void initState() {
    super.initState();
    _siteId = widget.initialSiteId ??
        (widget.sites.length == 1 ? widget.sites.first.id : null);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Laden, dem ein **Freitext**-Eintrag zugeordnet würde (braucht einen
  /// eindeutigen Laden – Artikel-Einträge kennen ihren Laden selbst).
  String? get _freeTextSiteId =>
      _siteId ?? (widget.sites.length == 1 ? widget.sites.first.id : null);

  String? _siteNameFor(String? siteId) {
    if (siteId == null) {
      return null;
    }
    for (final site in widget.sites) {
      if (site.id == siteId) {
        return site.name;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // context.watch -> der Sheet baut sich neu, sobald sich die Liste ändert
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

    final query = _search.trim();
    final queryLower = query.toLowerCase();
    final filtered = siteProducts.where((product) {
      if (!product.isActive) {
        return false;
      }
      if (_category != null && product.category?.trim() != _category) {
        return false;
      }
      if (queryLower.isEmpty) {
        return true;
      }
      return product.name.toLowerCase().contains(queryLower) ||
          (product.sku?.toLowerCase().contains(queryLower) ?? false) ||
          (product.barcode?.toLowerCase().contains(queryLower) ?? false);
    }).toList();
    // Häufig bestellte Artikel zuerst (gleiche Reihung wie im Bestellkorb).
    final ordered = inventory.sortByOrderFrequency(filtered, siteId: _siteId);

    final freeTextSiteId = _freeTextSiteId;
    final showFreeText = query.isNotEmpty;
    final openTotal = inventory.fridgeRefillOpenCount(_siteId);

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
                  const Icon(Icons.kitchen_outlined),
                  const SizedBox(width: 8),
                  Text('Kühlschrank nachfüllen',
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
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Getränk suchen oder eintippen',
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                children: [
                  if (showFreeText)
                    _FreeTextAddRow(
                      label: query,
                      enabled: freeTextSiteId != null,
                      hint: freeTextSiteId == null
                          ? 'Zum freien Eintragen oben einen Laden wählen'
                          : null,
                      onAdd: () => _addFreeText(inventory, freeTextSiteId!),
                    ),
                  if (ordered.isEmpty && !showFreeText)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: EmptyState(
                        icon: Icons.inventory_2_outlined,
                        message: 'Keine passenden Artikel.',
                      ),
                    )
                  else
                    for (final product in ordered)
                      _FridgeAddRow(
                        product: product,
                        quantityOnList: inventory
                                .fridgeRefillListForSite(product.siteId)
                                ?.openItemForProduct(product.id)
                                ?.quantity ??
                            0,
                        showSite: widget.sites.length > 1,
                        onAdd: () => inventory.addFridgeRefillItem(
                          siteId: product.siteId,
                          productId: product.id,
                          name: product.name,
                          category: product.category,
                          unit: product.unit,
                          siteName: product.siteName,
                        ),
                        onRemoveOne: () => _removeOne(inventory, product),
                      ),
                ],
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
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.kitchen_outlined),
                        label: Text('Auf der Liste ($openTotal)'),
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

  Future<void> _addFreeText(
    InventoryProvider inventory,
    String siteId,
  ) async {
    final name = _search.trim();
    if (name.isEmpty) {
      return;
    }
    await inventory.addFridgeRefillItem(
      siteId: siteId,
      name: name,
      siteName: _siteNameFor(siteId),
    );
    if (!mounted) {
      return;
    }
    _searchController.clear();
    setState(() => _search = '');
    _toast(context, '„$name" zur Kühlschrank-Liste hinzugefügt.');
  }

  Future<void> _removeOne(InventoryProvider inventory, Product product) async {
    final open = inventory
        .fridgeRefillListForSite(product.siteId)
        ?.openItemForProduct(product.id);
    if (open == null) {
      return;
    }
    await inventory.setFridgeRefillItemQuantity(
      siteId: product.siteId,
      itemId: open.id,
      quantity: open.quantity - 1,
    );
  }
}

class _FreeTextAddRow extends StatelessWidget {
  const _FreeTextAddRow({
    required this.label,
    required this.enabled,
    required this.onAdd,
    this.hint,
  });

  final String label;
  final bool enabled;
  final String? hint;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: colorScheme.secondaryContainer,
      child: ListTile(
        leading: const Icon(Icons.edit_outlined),
        title: Text('„$label" eintragen'),
        subtitle: hint == null ? null : Text(hint!),
        trailing: Icon(
          Icons.add_circle,
          color: enabled ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
        enabled: enabled,
        onTap: enabled ? onAdd : null,
      ),
    );
  }
}

class _FridgeAddRow extends StatelessWidget {
  const _FridgeAddRow({
    required this.product,
    required this.quantityOnList,
    required this.showSite,
    required this.onAdd,
    required this.onRemoveOne,
  });

  final Product product;
  final int quantityOnList;
  final bool showSite;
  final VoidCallback onAdd;
  final VoidCallback onRemoveOne;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onList = quantityOnList > 0;
    return ListTile(
      title: Text(product.name),
      subtitle: Text(
        [
          if (product.category?.isNotEmpty ?? false) product.category!,
          if (showSite && (product.siteName?.isNotEmpty ?? false))
            product.siteName!,
        ].join('  ·  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onList) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onRemoveOne,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text(
              '$quantityOnList',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ],
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Auf die Kühlschrank-Liste',
            onPressed: product.id == null ? null : onAdd,
            icon: Icon(
              onList ? Icons.add_circle_outline : Icons.add,
              color: colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
