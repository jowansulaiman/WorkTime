import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/money.dart';
import '../core/site_name_resolver.dart';
import '../models/contact.dart';
import '../models/product.dart';
import '../models/purchase_order.dart';
import '../models/site_definition.dart';
import '../models/supplier.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/team_provider.dart';
import '../routing/shell_tab.dart';
import '../services/export_service.dart';
import '../widgets/action_fab.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/contact_picker_field.dart';
import '../widgets/empty_state.dart';
import 'fridge_refill_screen.dart';
import 'order_cart_screen.dart';
import 'purchase_order_screens.dart';

final NumberFormat _euroFormat =
    NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

/// Formatiert einen Centbetrag als "1,99 €". Gibt '–' bei null zurueck.
String formatCents(int? cents) {
  if (cents == null) {
    return '–';
  }
  return _euroFormat.format(cents / 100);
}

/// Wandelt eine Euro-Eingabe ("1,99" oder "1.99") in Cent. Null bei leer.
///
/// Delegiert an [Money.parseCents] (gemeinsamer, robuster Parser), damit
/// Punkt-vs-Komma-Dezimaltrenner überall identisch behandelt werden.
int? parseEuroToCents(String value) => Money.parseCents(value);

String _centsToEuroInput(int? cents) {
  if (cents == null) {
    return '';
  }
  return (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
}

Future<bool> _confirmDelete(BuildContext context, String itemName) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('$itemName loeschen?'),
      content: Text('$itemName wird unwiderruflich geloescht.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Loeschen'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Hauptansicht der Warenwirtschaft: Bestand, Lieferanten und Bestellungen.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    this.parentLabel = 'Profil',
    this.initialTabIndex = 0,
  });

  final String parentLabel;

  /// Tab, der beim Öffnen aktiv ist (0 = Bestand). Erlaubt Deep-Links wie den
  /// Warenkorb-Knopf in der App-Bar, der direkt auf [cartTabIndex] springt.
  final int initialTabIndex;

  /// Index des „Bestellkorb"-Tabs — öffentlich, damit Deep-Links (Router/App-Bar)
  /// nicht die private Tab-Reihenfolge kennen müssen.
  static const int cartTabIndex = 3;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  // Tab-Reihenfolge (benannte Indizes statt Literale, damit FAB/Badge/Navigation
  // bei künftigem Umsortieren nicht auseinanderlaufen).
  static const int _stockTabIndex = 0;
  static const int _fridgeTabIndex = 1;
  static const int _suppliersTabIndex = 2;
  static const int _cartTabIndex = 3;
  static const int _ordersTabIndex = 4;
  static const int _tabCount = 5;

  late final TabController _tabController;
  String? _selectedSiteId;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabCount,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, _tabCount - 1),
    );
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final inventory = context.watch<InventoryProvider>();
    final team = context.watch<TeamProvider>();
    final profile = auth.profile;

    if (profile == null || !profile.canViewInventory) {
      return Scaffold(
        appBar: BreadcrumbAppBar(
          breadcrumbs: [
            BreadcrumbItem(
              label: widget.parentLabel,
              onTap: () => Navigator.of(context).pop(),
            ),
            const BreadcrumbItem(label: 'Warenwirtschaft'),
          ],
        ),
        body: const Center(
          child: Text('Keine Berechtigung fuer die Warenwirtschaft.'),
        ),
      );
    }

    final canManage = profile.canManageInventory;
    final sites = team.sites;
    final lowStockCount = inventory.lowStockProducts(siteId: _selectedSiteId).length;
    // Bestellkorb/Wochenliste sind je Laden. Bei genau einem Laden ist der
    // effektive Laden eindeutig, auch wenn kein Filter aktiv ist.
    final effectiveSiteId =
        _selectedSiteId ?? (sites.length == 1 ? sites.first.id : null);

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: widget.parentLabel,
            onTap: () => Navigator.of(context).pop(),
          ),
          const BreadcrumbItem(label: 'Warenwirtschaft'),
        ],
        actions: [
          IconButton(
            tooltip: 'Bestell-Auswertung',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => context.push(AppRoutes.orderAnalytics),
          ),
          IconButton(
            tooltip: 'Kundenwünsche',
            icon: const Icon(Icons.inbox_outlined),
            onPressed: () => context.push(AppRoutes.customerWishes),
          ),
          _buildExportMenu(context, inventory, sites),
        ],
      ),
      floatingActionButton:
          _buildFab(context, inventory, sites, canManage, effectiveSiteId),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              children: [
                if (sites.length > 1)
                  _SiteFilterBar(
                    sites: sites,
                    selectedSiteId: _selectedSiteId,
                    onChanged: (value) =>
                        setState(() => _selectedSiteId = value),
                  ),
                TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(
                      child: _TabLabel(
                        icon: Icons.inventory_2_outlined,
                        label: 'Bestand',
                        badgeCount: lowStockCount,
                      ),
                    ),
                    Tab(
                      child: _TabLabel(
                        icon: Icons.kitchen_outlined,
                        label: 'Kühlschrank',
                        // Wie der Bestellkorb: ohne eindeutigen Laden kein
                        // Summen-Badge (der Tab zeigt dann „Laden wählen").
                        badgeCount: effectiveSiteId == null
                            ? 0
                            : inventory.fridgeRefillOpenCount(effectiveSiteId),
                      ),
                    ),
                    const Tab(
                      child: _TabLabel(
                        icon: Icons.local_shipping_outlined,
                        label: 'Lieferanten',
                      ),
                    ),
                    Tab(
                      child: _TabLabel(
                        icon: Icons.shopping_cart_outlined,
                        label: 'Bestellkorb',
                        // Badge konsistent zum Tab-Inhalt: ohne eindeutigen Laden
                        // (Mehr-Laden, kein Filter) zeigt der Tab einen
                        // "Laden wählen"-Hinweis -> dann auch kein Summen-Badge.
                        badgeCount: effectiveSiteId == null
                            ? 0
                            : inventory.cartItemCount(effectiveSiteId),
                      ),
                    ),
                    Tab(
                      child: _TabLabel(
                        icon: Icons.receipt_long_outlined,
                        label: 'Bestellungen',
                        badgeCount: inventory.openOrders
                            .where((order) =>
                                _selectedSiteId == null ||
                                order.siteId == _selectedSiteId)
                            .length,
                      ),
                    ),
                  ],
                ),
                if (inventory.errorMessage != null)
                  _ErrorBanner(
                    message: inventory.errorMessage!,
                    onDismiss: inventory.clearError,
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _StockTab(
                        siteId: _selectedSiteId,
                        search: _search,
                        canManage: canManage,
                        onSearchChanged: (value) =>
                            setState(() => _search = value),
                        sites: sites,
                      ),
                      FridgeRefillTab(
                        siteId: effectiveSiteId,
                        canManage: canManage,
                        sites: sites,
                      ),
                      _SuppliersTab(canManage: canManage),
                      OrderCartTab(
                        siteId: effectiveSiteId,
                        canManage: canManage,
                        sites: sites,
                        onCheckoutDone: () => _tabController.animateTo(
                          _ordersTabIndex,
                        ),
                      ),
                      _OrdersTab(
                        siteId: _selectedSiteId,
                        canManage: canManage,
                        sites: sites,
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

  Widget _buildExportMenu(
    BuildContext context,
    InventoryProvider inventory,
    List<SiteDefinition> sites,
  ) {
    String? siteLabel;
    if (_selectedSiteId != null) {
      for (final site in sites) {
        if (site.id == _selectedSiteId) {
          siteLabel = site.name;
          break;
        }
      }
    }
    return PopupMenuButton<int>(
      icon: const Icon(Icons.ios_share_outlined),
      tooltip: 'Exportieren',
      onSelected: (value) async {
        final products = inventory.productsForSite(_selectedSiteId);
        final reorder = inventory.lowStockProducts(siteId: _selectedSiteId);
        try {
          switch (value) {
            case 0:
              await ExportService.exportStockListPdf(
                  products: products, siteLabel: siteLabel);
            case 1:
              await ExportService.exportStockListCsv(
                  products: products, siteLabel: siteLabel);
            case 2:
              await ExportService.exportReorderListPdf(
                  products: reorder, siteLabel: siteLabel);
            case 3:
              await ExportService.exportReorderListCsv(
                  products: reorder, siteLabel: siteLabel);
          }
        } catch (_) {
          if (context.mounted) {
            _showSnack(context, 'Export fehlgeschlagen.');
          }
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 0, child: Text('Bestandsliste (PDF)')),
        PopupMenuItem(value: 1, child: Text('Bestandsliste (CSV)')),
        PopupMenuItem(value: 2, child: Text('Nachbestellliste (PDF)')),
        PopupMenuItem(value: 3, child: Text('Nachbestellliste (CSV)')),
      ],
    );
  }

  Widget? _buildFab(
    BuildContext context,
    InventoryProvider inventory,
    List<SiteDefinition> sites,
    bool canManage,
    String? effectiveSiteId,
  ) {
    // Schnell-„In den Warenkorb"-Aktion: für JEDEN aktiven Mitarbeiter. Öffnet
    // den gefilterten Schnell-Sheet (Laden + Kategorie) und legt Artikel live in
    // den Korb.
    final cartAction = FabAction(
      icon: Icons.add_shopping_cart,
      label: 'In den Warenkorb',
      emphasized: true,
      onPressed: () => showQuickAddCartSheet(
        context,
        sites: sites,
        initialSiteId: effectiveSiteId,
        onGoToCart: () => _tabController.animateTo(_cartTabIndex),
      ),
    );

    // Schnell etwas auf die Kühlschrank-Nachfüllliste setzen — für JEDEN
    // aktiven Mitarbeiter (gleiches Muster wie der Warenkorb).
    final fridgeAction = FabAction(
      icon: Icons.kitchen_outlined,
      label: 'Kühlschrank nachfüllen',
      onPressed: () => showFridgeRefillAddSheet(
        context,
        sites: sites,
        initialSiteId: effectiveSiteId,
      ),
    );

    switch (_tabController.index) {
      case _stockTabIndex:
        // Verwaltung fächert Scanner + Artikel über die prominente Korb-Aktion
        // auf; Mitarbeiter sehen nur den einzelnen Korb-FAB.
        return ExpandableFab(
          heroTag: 'inv-fab-stock',
          actions: [
            // Scanner plattformunabhängig (Off-Mobile: manuelle Eingabe im
            // ScannerScreen) — konsistent zum festen Scanner-Tab der Bottomnav.
            if (canManage)
              FabAction(
                icon: Icons.qr_code_scanner_outlined,
                label: 'Scanner',
                onPressed: () => context.push(AppRoutes.scanner),
              ),
            if (canManage)
              FabAction(
                icon: Icons.add,
                label: 'Artikel',
                onPressed: () => _addProduct(context, inventory, sites),
              ),
            fridgeAction,
            cartAction,
          ],
        );
      case _fridgeTabIndex:
        return ExpandableFab(
          heroTag: 'inv-fab-fridge',
          actions: [fridgeAction],
        );
      case _suppliersTabIndex:
        return canManage
            ? ExpandableFab(
                heroTag: 'inv-fab-suppliers',
                actions: [
                  FabAction(
                    icon: Icons.add,
                    label: 'Lieferant',
                    onPressed: () => _addSupplier(context, inventory),
                  ),
                ],
              )
            : null;
      case _cartTabIndex:
        return ExpandableFab(
          heroTag: 'inv-fab-cart',
          actions: [cartAction],
        );
      case _ordersTabIndex:
        return canManage
            ? ExpandableFab(
                heroTag: 'inv-fab-orders',
                actions: [
                  FabAction(
                    icon: Icons.add,
                    label: 'Bestellung',
                    onPressed: () => _addOrder(context, sites),
                  ),
                ],
              )
            : null;
      default:
        return null;
    }
  }

  Future<void> _addProduct(
    BuildContext context,
    InventoryProvider inventory,
    List<SiteDefinition> sites,
  ) async {
    if (sites.isEmpty) {
      _showSnack(context,
          'Bitte zuerst in der Teamverwaltung einen Standort anlegen.');
      return;
    }
    final result = await showProductDialog(
      context,
      sites: sites,
      suppliers: inventory.activeSuppliers,
      defaultSiteId: _selectedSiteId ?? sites.first.id,
    );
    if (result != null) {
      try {
        await inventory.saveProduct(result);
        if (context.mounted) {
          _showSnack(context, 'Artikel gespeichert.');
        }
      } catch (error) {
        if (context.mounted) {
          _showSnack(context, 'Fehler: $error');
        }
      }
    }
  }

  Future<void> _addSupplier(
    BuildContext context,
    InventoryProvider inventory,
  ) async {
    final result = await showSupplierDialog(context);
    if (result != null) {
      try {
        await inventory.saveSupplier(result);
        if (context.mounted) {
          _showSnack(context, 'Lieferant gespeichert.');
        }
      } catch (error) {
        if (context.mounted) {
          _showSnack(context, 'Fehler: $error');
        }
      }
    }
  }

  Future<void> _addOrder(BuildContext context, List<SiteDefinition> sites) async {
    if (sites.isEmpty) {
      _showSnack(context,
          'Bitte zuerst in der Teamverwaltung einen Standort anlegen.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PurchaseOrderEditorScreen(
          sites: sites,
          initialSiteId: _selectedSiteId ?? sites.first.id,
        ),
      ),
    );
  }
}

class _SiteFilterBar extends StatelessWidget {
  const _SiteFilterBar({
    required this.sites,
    required this.selectedSiteId,
    required this.onChanged,
  });

  final List<SiteDefinition> sites;
  final String? selectedSiteId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('Alle Laeden'),
              selected: selectedSiteId == null,
              onSelected: (_) => onChanged(null),
            ),
            const SizedBox(width: 8),
            for (final site in sites) ...[
              ChoiceChip(
                label: Text(site.name),
                selected: selectedSiteId == site.id,
                onSelected: (_) => onChanged(site.id),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.icon,
    required this.label,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (badgeCount > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.error,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$badgeCount',
              style: TextStyle(
                color: colorScheme.onError,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: colorScheme.onErrorContainer),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Bestand-Tab
// ===========================================================================

class _StockTab extends StatelessWidget {
  const _StockTab({
    required this.siteId,
    required this.search,
    required this.canManage,
    required this.onSearchChanged,
    required this.sites,
  });

  final String? siteId;
  final String search;
  final bool canManage;
  final ValueChanged<String> onSearchChanged;
  final List<SiteDefinition> sites;

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final query = search.trim().toLowerCase();
    // Bewusste Entscheidung (barcode-no-index-clientside-scan): Die Produktsuche
    // ist ein Volltext-Substring-Filter (contains) ueber die bereits gestreamte
    // Produktliste. Firestore kann Substring-Suche serverseitig ohnehin nicht.
    // Eine indizierte where('barcode', isEqualTo:)-Query lohnt sich erst, wenn ein
    // echter POS-Barcode-Scan kommt (Exact-Match) -> dann findProductByBarcode im
    // Repository + (siteId, barcode)-Index ergaenzen. Fuer die heutige Datenmenge
    // (2 Laeden) ist die clientseitige Filterung ausreichend.
    final products = inventory.productsForSite(siteId).where((product) {
      if (query.isEmpty) {
        return true;
      }
      return product.name.toLowerCase().contains(query) ||
          (product.sku?.toLowerCase().contains(query) ?? false) ||
          (product.barcode?.toLowerCase().contains(query) ?? false) ||
          (product.category?.toLowerCase().contains(query) ?? false);
    }).toList();

    final lowStock = inventory.lowStockProducts(siteId: siteId);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Artikel, Artikelnr. oder Barcode suchen',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: onSearchChanged,
          ),
        ),
        Builder(builder: (context) {
          final valueCents =
              inventory.totalStockValuePurchaseCents(siteId: siteId);
          if (valueCents <= 0) {
            return const SizedBox.shrink();
          }
          final sellingCents =
              inventory.totalStockValueSellingCents(siteId: siteId);
          final marginCents = inventory.totalStockMarginCents(siteId: siteId);
          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Warenwert (EK): ${formatCents(valueCents)}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (sellingCents > 0)
                        Text(
                          'VK: ${formatCents(sellingCents)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (marginCents > 0)
                        Text(
                          'Spanne: ${formatCents(marginCents)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
        if (lowStock.isNotEmpty && canManage)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _ReorderBanner(
              count: lowStock.length,
              onTap: () => _startReorder(context, inventory, lowStock),
            ),
          ),
        Expanded(
          child: products.isEmpty
              ? const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  message:
                      'Noch keine Artikel. Lege ueber das Plus den ersten Artikel an.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, kFabSafeBottomInset),
                  itemCount: products.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _ProductTile(
                    product: products[index],
                    canManage: canManage,
                    sites: sites,
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _startReorder(
    BuildContext context,
    InventoryProvider inventory,
    List<Product> lowStock,
  ) async {
    // Nachzubestellende Artikel nach Lieferant gruppieren und den groessten
    // Vorschlag zuerst anbieten.
    final bySupplier = <String?, List<Product>>{};
    for (final product in lowStock) {
      bySupplier.putIfAbsent(product.supplierId, () => []).add(product);
    }
    final targetSiteId = siteId ?? (lowStock.isNotEmpty ? lowStock.first.siteId : null);
    if (targetSiteId == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PurchaseOrderEditorScreen(
          sites: sites,
          initialSiteId: targetSiteId,
          prefillReorder: true,
        ),
      ),
    );
  }
}

class _ReorderBanner extends StatelessWidget {
  const _ReorderBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: colorScheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$count Artikel unter Mindestbestand – jetzt nachbestellen',
                  style: TextStyle(
                    color: colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onTertiaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.canManage,
    required this.sites,
  });

  final Product product;
  final bool canManage;
  final List<SiteDefinition> sites;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final inventory = context.read<InventoryProvider>();
    final stockColor = product.isOutOfStock
        ? colorScheme.error
        : (product.needsReorder ? colorScheme.tertiary : colorScheme.primary);

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: canManage ? () => _edit(context, inventory) : null,
        leading: CircleAvatar(
          backgroundColor: stockColor.withValues(alpha: 0.15),
          child: Text(
            '${product.currentStock}',
            style: TextStyle(color: stockColor, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          product.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              [
                if (product.category?.isNotEmpty ?? false) product.category!,
                'Bestand: ${product.currentStock} ${product.unit}',
                if (product.minStock > 0) 'Min: ${product.minStock}',
                if (product.sellingPriceCents != null)
                  'VK ${formatCents(product.sellingPriceCents)}',
              ].join('  ·  '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            if (sites.length > 1 &&
                (resolveSiteName(sites, product.siteId,
                            fallback: product.siteName)
                        ?.isNotEmpty ??
                    false))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  resolveSiteName(sites, product.siteId,
                      fallback: product.siteName)!,
                  style: TextStyle(
                    color: colorScheme.outline,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Schnellaktion für JEDEN aktiven Mitarbeiter: Artikel in den
            // gemeinsamen Bestellkorb legen ("Sorte ist leer").
            IconButton(
              tooltip: 'In den Bestellkorb',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_shopping_cart_outlined),
              onPressed: () => _addToCart(context, inventory),
            ),
            if (canManage)
              PopupMenuButton<String>(
                onSelected: (value) => _onMenu(context, inventory, value),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
                  PopupMenuItem(
                      value: 'issue', child: Text('Abgang buchen')),
                  PopupMenuItem(
                      value: 'adjust', child: Text('Bestand korrigieren')),
                  PopupMenuItem(value: 'stocktake', child: Text('Inventur')),
                  PopupMenuItem(value: 'transfer', child: Text('Umlagern')),
                  PopupMenuItem(value: 'delete', child: Text('Loeschen')),
                ],
              )
            else if (product.needsReorder)
              Icon(Icons.warning_amber_rounded, color: colorScheme.tertiary),
          ],
        ),
      ),
    );
  }

  Future<void> _addToCart(
      BuildContext context, InventoryProvider inventory) async {
    if (product.id == null) {
      return;
    }
    final quantity = await showOrderQuantityDialog(context, product);
    if (quantity == null) {
      return;
    }
    await inventory.addToCart(product: product, quantity: quantity);
    if (context.mounted) {
      _showSnack(context, '${product.name} in den Bestellkorb gelegt.');
    }
  }

  Future<void> _onMenu(
    BuildContext context,
    InventoryProvider inventory,
    String value,
  ) async {
    switch (value) {
      case 'edit':
        await _edit(context, inventory);
        break;
      case 'issue':
        await _issue(context, inventory);
        break;
      case 'adjust':
        await _adjust(context, inventory);
        break;
      case 'stocktake':
        await _stocktake(context, inventory);
        break;
      case 'transfer':
        await _transfer(context, inventory);
        break;
      case 'delete':
        if (await _confirmDelete(context, product.name) &&
            product.id != null) {
          await inventory.deleteProduct(product.id!);
          if (context.mounted) {
            _showSnack(context, 'Artikel geloescht.');
          }
        }
        break;
    }
  }

  Future<void> _edit(
      BuildContext context, InventoryProvider inventory) async {
    final result = await showProductDialog(
      context,
      sites: sites,
      suppliers: inventory.activeSuppliers,
      product: product,
    );
    if (result != null) {
      await inventory.saveProduct(result);
      if (context.mounted) {
        _showSnack(context, 'Artikel gespeichert.');
      }
    }
  }

  Future<void> _adjust(
      BuildContext context, InventoryProvider inventory) async {
    final delta = await _showStockDeltaDialog(context, product);
    if (delta != null && delta != 0 && product.id != null) {
      await inventory.adjustStock(
        productId: product.id!,
        delta: delta,
        reason: 'Manuelle Korrektur',
      );
      if (context.mounted) {
        _showSnack(context, 'Bestand korrigiert.');
      }
    }
  }

  Future<void> _issue(
      BuildContext context, InventoryProvider inventory) async {
    final result = await _showStockIssueDialog(context, product);
    if (result == null) {
      return;
    }
    final error = await inventory.issueStock(
      product: product,
      quantity: result.quantity,
      reason: result.reason,
    );
    if (context.mounted) {
      _showSnack(context, error ?? 'Abgang gebucht.');
    }
  }

  Future<void> _stocktake(
      BuildContext context, InventoryProvider inventory) async {
    final counted = await _showStocktakeDialog(context, product);
    if (counted != null) {
      await inventory.recordStocktake(product: product, countedStock: counted);
      if (context.mounted) {
        _showSnack(context, 'Inventur gebucht.');
      }
    }
  }

  Future<void> _transfer(
      BuildContext context, InventoryProvider inventory) async {
    final candidates = inventory.products
        .where((p) =>
            p.id != null && p.id != product.id && p.siteId != product.siteId)
        .toList();
    if (candidates.isEmpty) {
      _showSnack(context,
          'Kein Zielartikel an einem anderen Standort vorhanden. Lege ihn dort zuerst an.');
      return;
    }
    final result = await _showTransferDialog(context, product, candidates);
    if (result == null) {
      return;
    }
    final error = await inventory.transferStock(
      from: product,
      to: result.target,
      quantity: result.quantity,
    );
    if (context.mounted) {
      _showSnack(context, error ?? 'Umlagerung gebucht.');
    }
  }
}

// ===========================================================================
// Lieferanten-Tab
// ===========================================================================

class _SuppliersTab extends StatelessWidget {
  const _SuppliersTab({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final suppliers = inventory.suppliers;

    if (suppliers.isEmpty) {
      return const EmptyState(
        icon: Icons.local_shipping_outlined,
        message:
            'Noch keine Lieferanten. Lege ueber das Plus den ersten Lieferanten an.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, kFabSafeBottomInset),
      itemCount: suppliers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final supplier = suppliers[index];
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            onTap: canManage
                ? () => _edit(context, inventory, supplier)
                : null,
            leading: CircleAvatar(
              child: Text(
                supplier.name.isNotEmpty ? supplier.name[0].toUpperCase() : '?',
              ),
            ),
            title: Text(
              supplier.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              [
                if (supplier.contactPerson?.isNotEmpty ?? false)
                  supplier.contactPerson!,
                if (supplier.phone?.isNotEmpty ?? false) supplier.phone!,
                if (supplier.effectiveOrderEmail != null)
                  supplier.effectiveOrderEmail!,
                if (supplier.leadTimeDays != null)
                  'Lieferzeit ${supplier.leadTimeDays} Tage',
              ].join('  ·  '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: canManage
                ? PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        await _edit(context, inventory, supplier);
                      } else if (value == 'delete') {
                        if (await _confirmDelete(context, supplier.name) &&
                            supplier.id != null) {
                          await inventory.deleteSupplier(supplier.id!);
                          if (context.mounted) {
                            _showSnack(context, 'Lieferant geloescht.');
                          }
                        }
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
                      PopupMenuItem(value: 'delete', child: Text('Loeschen')),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }

  Future<void> _edit(
    BuildContext context,
    InventoryProvider inventory,
    Supplier supplier,
  ) async {
    final result = await showSupplierDialog(context, supplier: supplier);
    if (result != null) {
      await inventory.saveSupplier(result);
      if (context.mounted) {
        _showSnack(context, 'Lieferant gespeichert.');
      }
    }
  }
}

// ===========================================================================
// Bestellungen-Tab
// ===========================================================================

class _OrdersTab extends StatelessWidget {
  const _OrdersTab({
    required this.siteId,
    required this.canManage,
    required this.sites,
  });

  final String? siteId;
  final bool canManage;
  final List<SiteDefinition> sites;

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final orders = inventory.ordersForSite(siteId);

    if (orders.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        message:
            'Noch keine Bestellungen. Erstelle ueber das Plus eine Bestellung.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, kFabSafeBottomInset),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final order = orders[index];
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PurchaseOrderDetailScreen(
                  orderId: order.id!,
                  sites: sites,
                  canManage: canManage,
                ),
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    order.orderNumber ?? 'Bestellung',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                _StatusChip(status: order.status),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [
                  if (order.supplierName?.isNotEmpty ?? false)
                    order.supplierName!,
                  '${order.itemCount} Positionen',
                  if (order.hasPrices) formatCents(order.totalCents),
                ].join('  ·  '),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final PurchaseOrderStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      PurchaseOrderStatus.draft => colorScheme.outline,
      PurchaseOrderStatus.ordered => colorScheme.primary,
      PurchaseOrderStatus.partiallyReceived => colorScheme.tertiary,
      PurchaseOrderStatus.received => colorScheme.secondary,
      PurchaseOrderStatus.cancelled => colorScheme.error,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ===========================================================================
// Dialoge: Artikel, Lieferant, Bestandskorrektur, Inventur
// ===========================================================================

Future<Product?> showProductDialog(
  BuildContext context, {
  required List<SiteDefinition> sites,
  required List<Supplier> suppliers,
  Product? product,
  String? defaultSiteId,
  String? initialBarcode,
}) {
  return showDialog<Product>(
    context: context,
    builder: (_) => _ProductDialog(
      sites: sites,
      suppliers: suppliers,
      product: product,
      defaultSiteId: defaultSiteId,
      initialBarcode: initialBarcode,
    ),
  );
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({
    required this.sites,
    required this.suppliers,
    this.product,
    this.defaultSiteId,
    this.initialBarcode,
  });

  final List<SiteDefinition> sites;
  final List<Supplier> suppliers;
  final Product? product;
  final String? defaultSiteId;

  /// Vorbefuellter Barcode fuer die Neuanlage aus dem Scanner (kein Treffer).
  final String? initialBarcode;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _unit;
  late final TextEditingController _sku;
  late final TextEditingController _barcode;
  late final TextEditingController _purchasePrice;
  late final TextEditingController _sellingPrice;
  late final TextEditingController _stock;
  late final TextEditingController _minStock;
  late final TextEditingController _targetStock;
  late final TextEditingController _reorderQty;
  String? _siteId;
  String? _supplierId;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _category = TextEditingController(text: product?.category ?? '');
    _unit = TextEditingController(text: product?.unit ?? Product.defaultUnit);
    _sku = TextEditingController(text: product?.sku ?? '');
    _barcode = TextEditingController(
        text: product?.barcode ?? widget.initialBarcode ?? '');
    _purchasePrice = TextEditingController(
        text: _centsToEuroInput(product?.purchasePriceCents));
    _sellingPrice = TextEditingController(
        text: _centsToEuroInput(product?.sellingPriceCents));
    _stock =
        TextEditingController(text: (product?.currentStock ?? 0).toString());
    _minStock =
        TextEditingController(text: (product?.minStock ?? 0).toString());
    _targetStock = TextEditingController(
        text: (product?.targetStock ?? 0) > 0
            ? product!.targetStock.toString()
            : '');
    _reorderQty = TextEditingController(
        text: product?.reorderQuantity?.toString() ?? '');
    _siteId = product?.siteId ??
        widget.defaultSiteId ??
        (widget.sites.isNotEmpty ? widget.sites.first.id : null);
    _supplierId = product?.supplierId;
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _unit.dispose();
    _sku.dispose();
    _barcode.dispose();
    _purchasePrice.dispose();
    _sellingPrice.dispose();
    _stock.dispose();
    _minStock.dispose();
    _targetStock.dispose();
    _reorderQty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.product != null;
    return AlertDialog(
      title: Text(isEdit ? 'Artikel bearbeiten' : 'Neuer Artikel'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name *'),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? 'Bitte einen Namen angeben'
                          : null,
                ),
                if (widget.sites.length > 1)
                  DropdownButtonFormField<String>(
                    initialValue: _siteId,
                    decoration: const InputDecoration(labelText: 'Laden *'),
                    items: [
                      for (final site in widget.sites)
                        DropdownMenuItem(
                          value: site.id,
                          child: Text(site.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _siteId = value),
                    validator: (value) =>
                        value == null ? 'Bitte einen Laden waehlen' : null,
                  ),
                DropdownButtonFormField<String?>(
                  initialValue: _supplierId,
                  decoration: const InputDecoration(labelText: 'Lieferant'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('– kein Lieferant –'),
                    ),
                    for (final supplier in widget.suppliers)
                      DropdownMenuItem<String?>(
                        value: supplier.id,
                        child: Text(supplier.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _supplierId = value),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _category,
                        decoration:
                            const InputDecoration(labelText: 'Warengruppe'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _unit,
                        decoration:
                            const InputDecoration(labelText: 'Einheit'),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _sku,
                        decoration:
                            const InputDecoration(labelText: 'Artikelnr.'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _barcode,
                        decoration:
                            const InputDecoration(labelText: 'Barcode/EAN'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _purchasePrice,
                        decoration: const InputDecoration(
                          labelText: 'EK-Preis €',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _sellingPrice,
                        decoration: const InputDecoration(
                          labelText: 'VK-Preis €',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stock,
                        decoration:
                            const InputDecoration(labelText: 'Bestand'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _minStock,
                        decoration: const InputDecoration(
                          labelText: 'Mindestbestand',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _reorderQty,
                        decoration: const InputDecoration(
                          labelText: 'Bestellmenge',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _targetStock,
                  decoration: const InputDecoration(
                    labelText: 'Zielbestand (optional)',
                    helperText: 'Auffüllen bis zu dieser Menge beim Nachbestellen',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Speichern'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final siteId = _siteId;
    if (siteId == null) {
      return;
    }
    final site = widget.sites.firstWhere(
      (s) => s.id == siteId,
      orElse: () => widget.sites.first,
    );
    final supplier = _supplierId == null
        ? null
        : widget.suppliers
            .where((s) => s.id == _supplierId)
            .cast<Supplier?>()
            .firstWhere((s) => true, orElse: () => null);

    final base = widget.product ??
        Product(orgId: '', siteId: siteId, name: _name.text.trim());

    final result = base.copyWith(
      siteId: siteId,
      siteName: site.name,
      name: _name.text.trim(),
      category: _category.text.trim().isEmpty ? null : _category.text.trim(),
      clearCategory: _category.text.trim().isEmpty,
      unit: _unit.text.trim().isEmpty ? Product.defaultUnit : _unit.text.trim(),
      sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
      clearSku: _sku.text.trim().isEmpty,
      barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
      clearBarcode: _barcode.text.trim().isEmpty,
      supplierId: supplier?.id,
      supplierName: supplier?.name,
      clearSupplier: _supplierId == null,
      purchasePriceCents: parseEuroToCents(_purchasePrice.text),
      clearPurchasePrice: parseEuroToCents(_purchasePrice.text) == null,
      sellingPriceCents: parseEuroToCents(_sellingPrice.text),
      clearSellingPrice: parseEuroToCents(_sellingPrice.text) == null,
      currentStock: int.tryParse(_stock.text.trim()) ?? 0,
      minStock: int.tryParse(_minStock.text.trim()) ?? 0,
      targetStock: int.tryParse(_targetStock.text.trim()) ?? 0,
      reorderQuantity: int.tryParse(_reorderQty.text.trim()),
      clearReorderQuantity: _reorderQty.text.trim().isEmpty,
    );
    Navigator.of(context).pop(result);
  }
}

Future<Supplier?> showSupplierDialog(
  BuildContext context, {
  Supplier? supplier,
}) {
  return showDialog<Supplier>(
    context: context,
    builder: (_) => _SupplierDialog(supplier: supplier),
  );
}

class _SupplierDialog extends StatefulWidget {
  const _SupplierDialog({this.supplier});

  final Supplier? supplier;

  @override
  State<_SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<_SupplierDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _contact;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _orderEmail;
  late final TextEditingController _customerNumber;
  late final TextEditingController _leadTime;
  late final TextEditingController _minOrder;
  late final TextEditingController _packaging;
  late final TextEditingController _notes;
  String? _contactId;

  @override
  void initState() {
    super.initState();
    final supplier = widget.supplier;
    _contactId = supplier?.contactId;
    _name = TextEditingController(text: supplier?.name ?? '');
    _contact = TextEditingController(text: supplier?.contactPerson ?? '');
    _email = TextEditingController(text: supplier?.email ?? '');
    _phone = TextEditingController(text: supplier?.phone ?? '');
    _orderEmail = TextEditingController(text: supplier?.orderEmail ?? '');
    _customerNumber =
        TextEditingController(text: supplier?.customerNumber ?? '');
    _leadTime = TextEditingController(
        text: supplier?.leadTimeDays?.toString() ?? '');
    _minOrder = TextEditingController(
        text: supplier?.minOrderQuantity?.toString() ?? '');
    _packaging = TextEditingController(text: supplier?.packagingUnit ?? '');
    _notes = TextEditingController(text: supplier?.notes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _email.dispose();
    _phone.dispose();
    _orderEmail.dispose();
    _customerNumber.dispose();
    _leadTime.dispose();
    _minOrder.dispose();
    _packaging.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.supplier != null;
    return AlertDialog(
      title: Text(isEdit ? 'Lieferant bearbeiten' : 'Neuer Lieferant'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ContactPickerField(
                  contactId: _contactId,
                  label: 'Verknüpfter Kontakt',
                  emptyLabel: 'Kein Kontakt verknüpft',
                  allowedTypes: const [
                    ContactType.supplier,
                    ContactType.wholesaler,
                  ],
                  onSelected: (contact) => setState(() {
                    _contactId = contact?.id;
                    if (contact != null) {
                      if (_name.text.trim().isEmpty) {
                        _name.text = contact.name;
                      }
                      if (_contact.text.trim().isEmpty &&
                          (contact.contactPerson?.trim().isNotEmpty ?? false)) {
                        _contact.text = contact.contactPerson!.trim();
                      }
                      if (_email.text.trim().isEmpty &&
                          (contact.email?.trim().isNotEmpty ?? false)) {
                        _email.text = contact.email!.trim();
                      }
                      final reach = contact.primaryPhone;
                      if (_phone.text.trim().isEmpty &&
                          (reach?.trim().isNotEmpty ?? false)) {
                        _phone.text = reach!.trim();
                      }
                    }
                  }),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name *'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? 'Bitte einen Namen angeben'
                          : null,
                ),
                TextFormField(
                  controller: _contact,
                  decoration:
                      const InputDecoration(labelText: 'Ansprechpartner'),
                ),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'E-Mail'),
                  keyboardType: TextInputType.emailAddress,
                ),
                TextFormField(
                  controller: _orderEmail,
                  decoration: const InputDecoration(
                    labelText: 'Bestell-E-Mail (falls abweichend)',
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Telefon'),
                  keyboardType: TextInputType.phone,
                ),
                TextFormField(
                  controller: _customerNumber,
                  decoration:
                      const InputDecoration(labelText: 'Eigene Kundennr.'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _leadTime,
                        decoration: const InputDecoration(
                            labelText: 'Lieferzeit (Tage)'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _minOrder,
                        decoration: const InputDecoration(
                            labelText: 'Mindestbestellmenge'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                      ),
                    ),
                  ],
                ),
                TextFormField(
                  controller: _packaging,
                  decoration: const InputDecoration(
                      labelText: 'Gebinde / Verpackungseinheit'),
                ),
                TextFormField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Notiz'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Speichern'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    String? trimOrNull(String value) =>
        value.trim().isEmpty ? null : value.trim();
    final base = widget.supplier ?? Supplier(orgId: '', name: _name.text.trim());
    final result = base.copyWith(
      name: _name.text.trim(),
      contactPerson: trimOrNull(_contact.text),
      clearContactPerson: _contact.text.trim().isEmpty,
      email: trimOrNull(_email.text),
      clearEmail: _email.text.trim().isEmpty,
      orderEmail: trimOrNull(_orderEmail.text),
      clearOrderEmail: _orderEmail.text.trim().isEmpty,
      phone: trimOrNull(_phone.text),
      clearPhone: _phone.text.trim().isEmpty,
      customerNumber: trimOrNull(_customerNumber.text),
      clearCustomerNumber: _customerNumber.text.trim().isEmpty,
      leadTimeDays: int.tryParse(_leadTime.text.trim()),
      clearLeadTimeDays: _leadTime.text.trim().isEmpty,
      minOrderQuantity: int.tryParse(_minOrder.text.trim()),
      clearMinOrderQuantity: _minOrder.text.trim().isEmpty,
      packagingUnit: trimOrNull(_packaging.text),
      clearPackagingUnit: _packaging.text.trim().isEmpty,
      notes: trimOrNull(_notes.text),
      clearNotes: _notes.text.trim().isEmpty,
      contactId: _contactId,
      clearContactId: _contactId == null,
    );
    Navigator.of(context).pop(result);
  }
}

Future<({Product target, int quantity})?> _showTransferDialog(
  BuildContext context,
  Product product,
  List<Product> candidates,
) {
  Product target = candidates.first;
  final quantityController = TextEditingController();
  return showDialog<({Product target, int quantity})>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Umlagern: ${product.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Bestand ${product.siteName ?? 'Quelle'}: '
                '${product.currentStock} ${product.unit}'),
            const SizedBox(height: 12),
            DropdownButtonFormField<Product>(
              initialValue: target,
              decoration: const InputDecoration(
                labelText: 'Ziel-Standort',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final candidate in candidates)
                  DropdownMenuItem(
                    value: candidate,
                    child: Text(
                      '${candidate.siteName ?? 'Standort'} · ${candidate.name}'
                      ' (${candidate.currentStock})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => target = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: quantityController,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Menge',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final qty = int.tryParse(quantityController.text.trim());
              if (qty == null || qty <= 0) {
                Navigator.of(context).pop();
                return;
              }
              Navigator.of(context).pop((target: target, quantity: qty));
            },
            child: const Text('Umlagern'),
          ),
        ],
      ),
    ),
  );
}

Future<({int quantity, String reason})?> _showStockIssueDialog(
    BuildContext context, Product product) {
  final quantityController = TextEditingController();
  final reasonController = TextEditingController(text: 'Verkauf');
  // Live-Validierung gegen den aktuellen Bestand (gleiche Regel wie issueStock):
  // der Nutzer sieht eine Übermenge sofort, statt erst nach dem Buchen.
  final inventory = context.read<InventoryProvider>();
  return showDialog<({int quantity, String reason})>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final qty = int.tryParse(quantityController.text.trim());
        final issueError = (qty == null || qty <= 0)
            ? null
            : inventory.validateStockIssue(product: product, quantity: qty);
        final canBook = qty != null && qty > 0 && issueError == null;
        return AlertDialog(
          title: Text('Abgang buchen: ${product.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  'Aktueller Bestand: ${product.currentStock} ${product.unit}'),
              const SizedBox(height: 12),
              TextField(
                controller: quantityController,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Menge (Abgang)',
                  border: const OutlineInputBorder(),
                  errorText: issueError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Grund (z.B. Verkauf, Schwund, Eigenbedarf)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: canBook
                  ? () {
                      final reason = reasonController.text.trim();
                      Navigator.of(dialogContext).pop((
                        quantity: qty,
                        reason: reason.isEmpty ? 'Verkauf' : reason,
                      ));
                    }
                  : null,
              child: const Text('Buchen'),
            ),
          ],
        );
      },
    ),
  );
}

Future<int?> _showStockDeltaDialog(BuildContext context, Product product) {
  final controller = TextEditingController();
  return showDialog<int>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Bestand korrigieren: ${product.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Aktueller Bestand: ${product.currentStock} ${product.unit}'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Aenderung (z.B. -3 oder 12)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(int.tryParse(controller.text.trim())),
          child: const Text('Buchen'),
        ),
      ],
    ),
  );
}

Future<int?> _showStocktakeDialog(BuildContext context, Product product) {
  final controller =
      TextEditingController(text: product.currentStock.toString());
  return showDialog<int>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Inventur: ${product.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Bisheriger Bestand: ${product.currentStock} ${product.unit}'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Gezaehlter Bestand',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(int.tryParse(controller.text.trim())),
          child: const Text('Speichern'),
        ),
      ],
    ),
  );
}
