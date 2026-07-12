import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/money.dart';
import '../core/site_name_resolver.dart';
import '../models/contact.dart';
import '../models/product.dart';
import '../models/purchase_order.dart';
import '../models/site_definition.dart';
import '../models/stock_movement.dart';
import '../models/supplier.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/team_provider.dart';
import '../routing/shell_tab.dart';
import '../services/export_service.dart';
import '../theme/theme_extensions.dart';
import '../ui/app_status.dart';
import '../widgets/action_fab.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/contact_picker_field.dart';
import '../widgets/empty_state.dart';
import '../widgets/price_history_sheet.dart';
import '../widgets/responsive_layout.dart';
import 'fridge_refill_screen.dart';
import 'order_cart_screen.dart';
import 'price_deviation_screen.dart';
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
      title: Text('$itemName löschen?'),
      content: Text('$itemName wird unwiderruflich geloescht.'),
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

  /// Öffnet direkt den Kühlschrank-Tab (Deeplink `?tab=kuehl`, z.B. aus der
  /// Home-Aktionskarte „Kühlschrank nachfüllen").
  static const int fridgeTabIndex = 1;

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
  final TextEditingController _searchController = TextEditingController();
  String? _selectedSiteId;
  String _search = '';
  // Suchfeld ist standardmäßig eingeklappt (spart eine Zeile) und wird erst
  // über den Lupen-Button in der AppBar (nur im Bestand-Tab) eingeblendet.
  bool _searchVisible = false;

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) {
        _search = '';
        _searchController.clear();
      }
    });
  }

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
    _searchController.dispose();
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
    // Kühlschrank-Badge: manuell offene Positionen ODER automatische Soll-Ist-
    // Lücken (das Maximum), nur bei eindeutigem Laden (sonst kein Summen-Badge).
    final fridgeBadgeCount = effectiveSiteId == null
        ? 0
        : [
            inventory.fridgeRefillOpenCount(effectiveSiteId),
            inventory.fridgeShortfallCount(effectiveSiteId),
          ].reduce((a, b) => a > b ? a : b);

    // Auf Handybreite (< mediumWindow) rendern ALLE Tabs nur ihr Icon (+ Badge);
    // das Label lebt in Tooltip/Semantics (siehe _TabLabel). So bleibt der
    // Tab-Streifen schmal, passt ohne horizontales Scrollen UND springt beim
    // Tabwechsel nicht um (kein Reflow durch ein wachsendes Aktiv-Label). Ab
    // Tablet-/Desktopbreite (Rail-Layout, zentrierter Inhalt) ist Platz für alle
    // Labels. Tab-Reihenfolge/Indizes bleiben UNVERÄNDERT (Deeplink-Kopplung).
    final compactTabs =
        MediaQuery.sizeOf(context).width < MobileBreakpoints.mediumWindow;
    final selectedTab = _tabController.index;
    final showTabLabels = !compactTabs;

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
          // Lupe nur im Bestand-Tab — blendet das (sonst eingeklappte) Suchfeld
          // ein/aus, damit die Liste keine Dauer-Suchzeile trägt.
          if (selectedTab == _stockTabIndex)
            IconButton(
              tooltip: _searchVisible ? 'Suche schließen' : 'Artikel suchen',
              isSelected: _searchVisible,
              icon: const Icon(Icons.search),
              selectedIcon: const Icon(Icons.search_off),
              onPressed: _toggleSearch,
            ),
          // Geführte Bestandszählung (eigener Bereich /inventur) — nur wer
          // buchen darf, sieht den Einstieg.
          if (canManage && selectedTab == _stockTabIndex)
            IconButton(
              tooltip: 'Inventur (Bestand zählen)',
              icon: const Icon(Icons.fact_check_outlined),
              onPressed: () => context.push(AppRoutes.inventur),
            ),
          if (AppConfig.oktoposEnabled && profile.isAdmin)
            PopupMenuButton<String>(
              icon: const Icon(Icons.point_of_sale_outlined),
              tooltip: 'Kasse (OktoPOS)',
              onSelected: (value) {
                switch (value) {
                  case 'sync':
                    _syncFromOktopos(
                        context, inventory, sites, effectiveSiteId);
                  case 'push':
                    _pushToOktopos(
                        context, inventory, sites, effectiveSiteId);
                  case 'pushCustomers':
                    _pushCustomersToOktopos(
                        context, inventory, sites, effectiveSiteId);
                  case 'priceCheck':
                    _openPriceDeviation(context, sites, effectiveSiteId);
                  case 'settings':
                    _openOktoposSettings(context, inventory, sites);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'sync',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.sync),
                    title: Text('Verkäufe aus Kasse übernehmen'),
                  ),
                ),
                PopupMenuItem(
                  value: 'push',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.upload_outlined),
                    title: Text('Artikel an Kasse senden'),
                  ),
                ),
                PopupMenuItem(
                  value: 'pushCustomers',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.people_alt_outlined),
                    title: Text('Kunden an Kasse senden'),
                  ),
                ),
                PopupMenuItem(
                  value: 'priceCheck',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.price_check_outlined),
                    title: Text('Preisabgleich Kasse'),
                  ),
                ),
                PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.settings_outlined),
                    title: Text('Einstellungen'),
                  ),
                ),
              ],
            ),
          // Analyse-/Auswertungs-Ziele gebündelt in EIN Menü, damit die AppBar
          // auf Handybreite nicht mit 5-7 Icons überläuft.
          PopupMenuButton<String>(
            icon: const Icon(Icons.insights_outlined),
            tooltip: 'Auswertungen',
            onSelected: (value) {
              switch (value) {
                case 'orderAnalytics':
                  context.push(AppRoutes.orderAnalytics);
                case 'bestandInsights':
                  context.push(AppRoutes.bestandInsights);
                case 'sortiment':
                  context.push(AppRoutes.sortiment);
                case 'storeHealth':
                  context.push(AppRoutes.storeHealth);
                case 'dailyClosing':
                  context.push(AppRoutes.dailyClosing);
                case 'kassenbericht':
                  context.push(AppRoutes.kassenbericht);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'orderAnalytics',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.insights_outlined),
                  title: Text('Bestell-Auswertung'),
                ),
              ),
              if (profile.isAdmin)
                const PopupMenuItem(
                  value: 'bestandInsights',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.query_stats_outlined),
                    title: Text('Bestand-Insights'),
                  ),
                ),
              if (profile.isAdmin)
                const PopupMenuItem(
                  value: 'sortiment',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.pie_chart_outline),
                    title: Text('Sortimentsanalyse'),
                  ),
                ),
              if (profile.isAdmin)
                const PopupMenuItem(
                  value: 'kassenbericht',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.receipt_long_outlined),
                    title: Text('Kassenbericht'),
                  ),
                ),
              if (profile.isAdmin)
                const PopupMenuItem(
                  value: 'storeHealth',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.compare_arrows),
                    title: Text('Laden-Benchmark'),
                  ),
                ),
              // Tagesabschluss/Kasse: einsehen + zählen auch für Teamleitung
              // (Abschließen/Buchen bleibt im Screen admin-gated).
              if (profile.isAdmin || profile.isTeamLead)
                const PopupMenuItem(
                  value: 'dailyClosing',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.point_of_sale_outlined),
                    title: Text('Tagesabschluss (Kasse)'),
                  ),
                ),
            ],
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
                  // 5 Text-Tabs passen fix verteilt nicht auf Handybreite
                  // (Labels/Badges abgeschnitten) → scrollbar + linksbündig.
                  // Im Kompaktmodus (nur Icons) engeres Label-Padding, damit
                  // alle 5 Icon-Tabs bequem ohne Scrollen nebeneinander liegen.
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelPadding: showTabLabels
                      ? null
                      : const EdgeInsets.symmetric(horizontal: 12),
                  tabs: [
                    Tab(
                      child: _TabLabel(
                        icon: Icons.inventory_2_outlined,
                        label: 'Bestand',
                        badgeCount: lowStockCount,
                        badgeTone: _BadgeTone.warning,
                        showLabel: showTabLabels,
                      ),
                    ),
                    Tab(
                      child: _TabLabel(
                        icon: Icons.kitchen_outlined,
                        label: 'Kühlschrank',
                        // Wie der Bestellkorb: ohne eindeutigen Laden kein
                        // Summen-Badge (der Tab zeigt dann „Laden wählen").
                        badgeCount: fridgeBadgeCount,
                        badgeTone: _BadgeTone.warning,
                        showLabel: showTabLabels,
                      ),
                    ),
                    Tab(
                      child: _TabLabel(
                        icon: Icons.local_shipping_outlined,
                        label: 'Lieferanten',
                        showLabel: showTabLabels,
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
                        showLabel: showTabLabels,
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
                        showLabel: showTabLabels,
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
                        searchController: _searchController,
                        searchVisible: _searchVisible,
                        canManage: canManage,
                        onSearchChanged: (value) =>
                            setState(() => _search = value),
                        onCloseSearch: _toggleSearch,
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

  /// Admin-Aktion „Verkäufe aus Kasse übernehmen" (OktoPOS). Wählt den Laden
  /// (eindeutig oder per Auswahl), löst den serverseitigen Abgleich aus und
  /// meldet das Ergebnis. Der API-Key bleibt serverseitig — hier wird nur die
  /// Cloud Function getriggert.
  /// Liefert den Ziel-Laden für eine Kassen-Aktion: den eindeutigen Laden bzw.
  /// per Auswahl-Sheet. `null` = abgebrochen / kein Laden.
  Future<String?> _pickOktoposSite(
    BuildContext context,
    List<SiteDefinition> sites,
    String? effectiveSiteId,
  ) async {
    if (effectiveSiteId != null) {
      return effectiveSiteId;
    }
    if (sites.isEmpty) {
      _showSnack(context, 'Kein Laden vorhanden.');
      return null;
    }
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Welcher Laden?',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            for (final site in sites)
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: Text(site.name),
                onTap: () => Navigator.of(sheetContext).pop(site.id),
              ),
          ],
        ),
      ),
    );
  }

  /// Öffnet den automatischen Preisabgleich App-VK vs. Kasse für einen Laden.
  Future<void> _openPriceDeviation(
    BuildContext context,
    List<SiteDefinition> sites,
    String? effectiveSiteId,
  ) async {
    final siteId = await _pickOktoposSite(context, sites, effectiveSiteId);
    if (siteId == null || !context.mounted) return;
    final site = sites
        .where((s) => s.id == siteId)
        .cast<SiteDefinition?>()
        .firstWhere((_) => true, orElse: () => null);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PriceDeviationScreen(
          siteId: siteId,
          siteName: site?.name ?? 'Laden',
        ),
      ),
    );
  }

  Future<void> _syncFromOktopos(
    BuildContext context,
    InventoryProvider inventory,
    List<SiteDefinition> sites,
    String? effectiveSiteId,
  ) async {
    final siteId = await _pickOktoposSite(context, sites, effectiveSiteId);
    if (siteId == null || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Kasse wird abgeglichen …')),
    );
    try {
      final result = await inventory.triggerOktoposSync(siteId: siteId);
      final applied = (result['appliedMovements'] as num?)?.toInt() ?? 0;
      final reversed = (result['reversedMovements'] as num?)?.toInt() ?? 0;
      final unmatched = (result['unmatchedLineItems'] as num?)?.toInt() ?? 0;
      final parts = <String>[
        '$applied Verkäufe übernommen',
        if (reversed > 0) '$reversed Erstattungen',
        if (unmatched > 0) '$unmatched Positionen ohne Artikel',
      ];
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Kassenabgleich: ${parts.join(' · ')}.')),
      );
    } catch (error) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Kassenabgleich fehlgeschlagen: '
            '${_friendlyError(error)}')),
      );
    }
  }

  /// Schreibt die Artikel eines Ladens in die Kasse (OktoPOS). Bestätigung
  /// nötig, da hier IN die Kasse geschrieben wird (Stammdaten/Preise/Barcodes).
  Future<void> _pushToOktopos(
    BuildContext context,
    InventoryProvider inventory,
    List<SiteDefinition> sites,
    String? effectiveSiteId,
  ) async {
    final siteId = await _pickOktoposSite(context, sites, effectiveSiteId);
    if (siteId == null || !context.mounted) {
      return;
    }
    final siteName = sites
        .firstWhere((s) => s.id == siteId, orElse: () => sites.first)
        .name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Artikel an Kasse senden?'),
        content: Text(
          'Alle aktiven Artikel von „$siteName" werden in die OktoPOS-Kasse '
          'geschrieben (Stammdaten, Preise, Barcodes). Vorhandene Artikel '
          'werden anhand der Artikelnummer aktualisiert.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Senden'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Artikel werden an die Kasse gesendet …')),
    );
    try {
      final result = await inventory.pushOktoposArticles(siteId: siteId);
      final created = (result['created'] as num?)?.toInt() ?? 0;
      final updated = (result['updated'] as num?)?.toInt() ?? 0;
      final failed = (result['failed'] as num?)?.toInt() ?? 0;
      final skipped = (result['skipped'] as num?)?.toInt() ?? 0;
      final parts = <String>[
        '$created neu',
        '$updated aktualisiert',
        if (failed > 0) '$failed fehlgeschlagen',
        if (skipped > 0) '$skipped übersprungen',
      ];
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Artikelversand: ${parts.join(' · ')}.')),
      );
    } catch (error) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Artikelversand fehlgeschlagen: '
            '${_friendlyError(error)}')),
      );
    }
  }

  /// Schreibt die Kunden-Kontakte in die Kasse (OktoPOS). Bestätigung nötig
  /// (schreibend). Vorhandene Kunden werden serverseitig übersprungen.
  Future<void> _pushCustomersToOktopos(
    BuildContext context,
    InventoryProvider inventory,
    List<SiteDefinition> sites,
    String? effectiveSiteId,
  ) async {
    final siteId = await _pickOktoposSite(context, sites, effectiveSiteId);
    if (siteId == null || !context.mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kunden an Kasse senden?'),
        content: const Text(
          'Alle aktiven Kunden-Kontakte werden als Kunden in die OktoPOS-Kasse '
          'geschrieben. Bereits vorhandene Kunden werden übersprungen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Senden'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Kunden werden an die Kasse gesendet …')),
    );
    try {
      final result = await inventory.pushOktoposCustomers(siteId: siteId);
      final created = (result['created'] as num?)?.toInt() ?? 0;
      final skipped = (result['skipped'] as num?)?.toInt() ?? 0;
      final failed = (result['failed'] as num?)?.toInt() ?? 0;
      final parts = <String>[
        '$created neu angelegt',
        if (skipped > 0) '$skipped bereits vorhanden',
        if (failed > 0) '$failed fehlgeschlagen',
      ];
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Kundenversand: ${parts.join(' · ')}.')),
      );
    } catch (error) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Kundenversand fehlgeschlagen: '
            '${_friendlyError(error)}')),
      );
    }
  }

  /// Öffnet die OktoPOS-Einstellungen (Basis-URL, Auto-Abgleich, Kassen-Nr. je
  /// Laden). Der API-Key bleibt serverseitig und wird hier nie eingegeben.
  Future<void> _openOktoposSettings(
    BuildContext context,
    InventoryProvider inventory,
    List<SiteDefinition> sites,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _OktoposSettingsSheet(inventory: inventory, sites: sites),
    );
    if (saved == true && context.mounted) {
      _showSnack(context, 'Kassen-Einstellungen gespeichert.');
    }
  }

  /// Extrahiert eine lesbare Meldung aus Callable-/Sonstigen Fehlern, ohne den
  /// Screen an cloud_functions zu koppeln (FirebaseFunctionsException trägt eine
  /// `.message`).
  String _friendlyError(Object error) {
    try {
      final dynamic e = error;
      final message = e.message;
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
    } catch (_) {
      // kein .message-Feld – Fallback unten
    }
    return error.toString();
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
          'Bitte zuerst unter Personal → Organisation einen Standort anlegen.');
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
          'Bitte zuerst unter Personal → Organisation einen Standort anlegen.');
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
              label: const Text('Alle Läden'),
              selected: selectedSiteId == null,
              onSelected: (_) => onChanged(null),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
            const SizedBox(width: 12),
            for (final site in sites) ...[
              ChoiceChip(
                label: Text(site.name),
                selected: selectedSiteId == site.id,
                onSelected: (_) => onChanged(site.id),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
              const SizedBox(width: 12),
            ],
          ],
        ),
      ),
    );
  }
}

/// Farbrolle eines Tab-Zählers: [warning] für Handlungsbedarf (Bestand unter
/// Minimum, Kühlschrank-Lücken), [neutral] für reine Mengen (Korb, Bestellungen).
enum _BadgeTone { warning, neutral }

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.icon,
    required this.label,
    this.badgeCount = 0,
    this.badgeTone = _BadgeTone.neutral,
    this.showLabel = true,
  });

  final IconData icon;
  final String label;
  final int badgeCount;
  final _BadgeTone badgeTone;

  /// `false` (nur auf Handybreite, inaktiver Tab): rendert Icon (+ Badge) ohne
  /// Textlabel — das Label bleibt via Tooltip/Semantics erhalten.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        if (showLabel) ...[
          const SizedBox(width: 6),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
        if (badgeCount > 0) ...[
          SizedBox(width: showLabel ? 6 : 4),
          _TabBadge(count: badgeCount, tone: badgeTone),
        ],
      ],
    );
    if (showLabel) {
      return row;
    }
    // Icon-only: Label für Sehende (Tooltip) und Screenreader (Semantics) retten.
    return Tooltip(
      message: badgeCount > 0 ? '$label ($badgeCount)' : label,
      child: Semantics(
        label: badgeCount > 0 ? '$label, $badgeCount' : label,
        child: row,
      ),
    );
  }
}

class _TabBadge extends StatelessWidget {
  const _TabBadge({required this.count, required this.tone});

  final int count;
  final _BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.appColors;
    final (Color bg, Color fg) = switch (tone) {
      _BadgeTone.warning => (status.warning, status.onWarning),
      _BadgeTone.neutral => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
    };
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.bold,
          height: 1.1,
        ),
      ),
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

class _StockTab extends StatefulWidget {
  const _StockTab({
    required this.siteId,
    required this.search,
    required this.searchController,
    required this.searchVisible,
    required this.canManage,
    required this.onSearchChanged,
    required this.onCloseSearch,
    required this.sites,
  });

  final String? siteId;
  final String search;
  final TextEditingController searchController;

  /// Suchfeld ist nur sichtbar, wenn über den AppBar-Lupen-Button eingeblendet.
  final bool searchVisible;
  final bool canManage;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onCloseSearch;
  final List<SiteDefinition> sites;

  @override
  State<_StockTab> createState() => _StockTabState();
}

/// Status-Schnellfilter der Bestandsliste.
enum _StockFilter { alle, nachbestellen, leer, kuehlschrank }

/// Sortierung der Bestandsliste.
enum _StockSort { name, bestand, wert }

class _StockTabState extends State<_StockTab> {
  _StockFilter _filter = _StockFilter.alle;
  String? _categoryFilter;
  _StockSort _sort = _StockSort.name;

  bool _matchesFilter(Product product) => switch (_filter) {
        _StockFilter.alle => true,
        _StockFilter.nachbestellen => product.needsReorder,
        _StockFilter.leer => product.isOutOfStock,
        _StockFilter.kuehlschrank => product.inFridge,
      };

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final query = widget.search.trim().toLowerCase();
    final allForSite = inventory.productsForSite(widget.siteId);
    // Warengruppen aus dem ungefilterten Standort-Sortiment (Filter-Menü).
    final categories = <String>{
      for (final product in allForSite)
        if (product.category?.trim().isNotEmpty ?? false)
          product.category!.trim(),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    // Gewählte Warengruppe kann durch Standortwechsel verschwinden — dann
    // still zurücksetzen (kein setState: wir sind bereits im Build).
    if (_categoryFilter != null && !categories.contains(_categoryFilter)) {
      _categoryFilter = null;
    }
    final reorderCount = allForSite.where((p) => p.needsReorder).length;
    final emptyCount = allForSite.where((p) => p.isOutOfStock).length;
    // Bewusste Entscheidung (barcode-no-index-clientside-scan): Die Produktsuche
    // ist ein Volltext-Substring-Filter (contains) ueber die bereits gestreamte
    // Produktliste. Firestore kann Substring-Suche serverseitig ohnehin nicht.
    // Eine indizierte where('barcode', isEqualTo:)-Query lohnt sich erst, wenn ein
    // echter POS-Barcode-Scan kommt (Exact-Match) -> dann findProductByBarcode im
    // Repository + (siteId, barcode)-Index ergaenzen. Fuer die heutige Datenmenge
    // (2 Laeden) ist die clientseitige Filterung ausreichend.
    final products = allForSite.where((product) {
      if (!_matchesFilter(product)) {
        return false;
      }
      if (_categoryFilter != null &&
          product.category?.trim() != _categoryFilter) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return product.name.toLowerCase().contains(query) ||
          (product.sku?.toLowerCase().contains(query) ?? false) ||
          (product.barcode?.toLowerCase().contains(query) ?? false) ||
          (product.category?.toLowerCase().contains(query) ?? false);
    }).toList();
    // Warenwert-Sortierung ist eine EK-Groesse -> wie der Metrikblock nur fuer
    // die Leitung; defensiv zuruecksetzen, falls das Recht entzogen wurde.
    if (!widget.canManage && _sort == _StockSort.wert) {
      _sort = _StockSort.name;
    }
    switch (_sort) {
      case _StockSort.name:
        break; // Liste kommt bereits alphabetisch aus dem Provider.
      case _StockSort.bestand:
        products.sort((a, b) => a.currentStock.compareTo(b.currentStock));
      case _StockSort.wert:
        products.sort((a, b) =>
            b.stockValuePurchaseCents.compareTo(a.stockValuePurchaseCents));
    }
    final filtersActive = _filter != _StockFilter.alle ||
        _categoryFilter != null ||
        query.isNotEmpty;

    final lowStock = inventory.lowStockProducts(siteId: widget.siteId);

    return Column(
      children: [
        // Eingeklappt (Default): keine Suchzeile. Erst der Lupen-Button in der
        // AppBar blendet das Feld ein (autofokussiert).
        if (widget.searchVisible)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: widget.searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: 'Artikel suchen',
                hintText: 'Name, Artikelnr. oder Barcode',
                border: const OutlineInputBorder(),
                // Ein X: erst Text leeren, bei leerem Feld das Suchfeld schließen.
                suffixIcon: IconButton(
                  tooltip: widget.search.isEmpty
                      ? 'Suche schließen'
                      : 'Suche leeren',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    if (widget.search.isEmpty) {
                      widget.onCloseSearch();
                    } else {
                      widget.searchController.clear();
                      widget.onSearchChanged('');
                    }
                  },
                ),
              ),
              onChanged: widget.onSearchChanged,
            ),
          ),
        // Warenwert/Spanne enthalten EK-Kalkulation -> nur für die Leitung
        // (canManageInventory), konsistent zur admin-only Sortimentsanalyse.
        if (widget.canManage)
          Builder(builder: (context) {
            final valueCents =
                inventory.totalStockValuePurchaseCents(siteId: widget.siteId);
            if (valueCents <= 0) {
              return const SizedBox.shrink();
            }
            final sellingCents =
                inventory.totalStockValueSellingCents(siteId: widget.siteId);
            final marginCents =
                inventory.totalStockMarginCents(siteId: widget.siteId);
            final theme = Theme.of(context);
            // Fester Metrikblock statt Wrap: EK/VK/Spanne behalten mobil ihre
            // Reihenfolge und springen nicht in eine zweite Zeile.
            return Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(context.radii.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StockValueMetric(
                      label: 'Warenwert (EK)',
                      value: formatCents(valueCents),
                      emphasize: true,
                    ),
                  ),
                  if (sellingCents > 0)
                    Expanded(
                      child: _StockValueMetric(
                        label: 'Verkaufswert',
                        value: formatCents(sellingCents),
                      ),
                    ),
                  if (marginCents > 0)
                    Expanded(
                      child: _StockValueMetric(
                        label: 'Spanne',
                        value: formatCents(marginCents),
                      ),
                    ),
                ],
              ),
            );
          }),
        if (lowStock.isNotEmpty && widget.canManage)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _ReorderBanner(
              count: lowStock.length,
              onTap: () => _startReorder(context, inventory, lowStock),
            ),
          ),
        // Schnellfilter + Sortierung: bei kiosktypisch hunderten SKUs ist
        // „nur Nachbestellen/Leer/Kühlschrank" der häufigste Blick auf die
        // Liste — ohne Scrollen und ohne Suchbegriff.
        if (allForSite.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: Text(reorderCount > 0
                              ? 'Nachbestellen ($reorderCount)'
                              : 'Nachbestellen'),
                          selected: _filter == _StockFilter.nachbestellen,
                          onSelected: (selected) => setState(() => _filter =
                              selected
                                  ? _StockFilter.nachbestellen
                                  : _StockFilter.alle),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: Text(
                              emptyCount > 0 ? 'Leer ($emptyCount)' : 'Leer'),
                          selected: _filter == _StockFilter.leer,
                          onSelected: (selected) => setState(() => _filter =
                              selected ? _StockFilter.leer : _StockFilter.alle),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Kühlschrank'),
                          selected: _filter == _StockFilter.kuehlschrank,
                          onSelected: (selected) => setState(() => _filter =
                              selected
                                  ? _StockFilter.kuehlschrank
                                  : _StockFilter.alle),
                        ),
                        if (categories.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          PopupMenuButton<String>(
                            tooltip: 'Warengruppe filtern',
                            onSelected: (value) => setState(() =>
                                _categoryFilter = value.isEmpty ? null : value),
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: '',
                                child: Text('Alle Warengruppen'),
                              ),
                              for (final category in categories)
                                PopupMenuItem(
                                  value: category,
                                  child: Text(category),
                                ),
                            ],
                            child: Chip(
                              avatar: const Icon(Icons.category_outlined,
                                  size: 16),
                              label: Text(_categoryFilter ?? 'Warengruppe'),
                              deleteIcon: _categoryFilter == null
                                  ? const Icon(Icons.arrow_drop_down)
                                  : null,
                              onDeleted: _categoryFilter == null
                                  ? null
                                  : () => setState(
                                      () => _categoryFilter = null),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<_StockSort>(
                  tooltip: 'Sortierung',
                  icon: const Icon(Icons.sort),
                  initialValue: _sort,
                  onSelected: (value) => setState(() => _sort = value),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: _StockSort.name,
                      child: Text('Name (A–Z)'),
                    ),
                    const PopupMenuItem(
                      value: _StockSort.bestand,
                      child: Text('Bestand (niedrig zuerst)'),
                    ),
                    // EK-Groesse -> nur fuer die Leitung (wie der Metrikblock).
                    if (widget.canManage)
                      const PopupMenuItem(
                        value: _StockSort.wert,
                        child: Text('Warenwert (hoch zuerst)'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child: products.isEmpty
              ? EmptyState(
                  icon: Icons.inventory_2_outlined,
                  message: filtersActive
                      ? 'Keine Artikel für die gewählten Filter.'
                      : 'Noch keine Artikel. Lege ueber das Plus den ersten Artikel an.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, kFabSafeBottomInset),
                  itemCount: products.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _ProductTile(
                    product: products[index],
                    canManage: widget.canManage,
                    sites: widget.sites,
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
    final targetSiteId =
        widget.siteId ?? (lowStock.isNotEmpty ? lowStock.first.siteId : null);
    if (targetSiteId == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PurchaseOrderEditorScreen(
          sites: widget.sites,
          initialSiteId: targetSiteId,
          prefillReorder: true,
        ),
      ),
    );
  }
}

/// Label-über-Wert-Metrik für den Warenwert-Block (feste Spaltenbreite via
/// Expanded des Aufrufers). Tabellenziffern verhindern springende Beträge.
class _StockValueMetric extends StatelessWidget {
  const _StockValueMetric({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (emphasize
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.bodyMedium)
              ?.copyWith(fontWeight: FontWeight.w700)
              .tabular,
        ),
      ],
    );
  }
}

/// Farbrolle einer [_MetricChip]: neutral (Kennwert) oder semantisch
/// (warning/error) für den kompakten Bestandsstatus je Zeile.
enum _ChipTone { neutral, warning, error }

/// Kleine, umbruchsichere Kennwert-Pille (Label-Wert) für Tile-Untertitel —
/// ersetzt die auf Handybreite still abschneidenden „·"-Ketten. Alle Pillen
/// (auch die Status-Variante) teilen Größe/Baseline, damit die Wrap-Zeile
/// gleichmäßig bleibt; lange Werte werden auf eine Zeile gekürzt statt umbrochen.
class _MetricChip extends StatelessWidget {
  const _MetricChip(this.label, {this.tone = _ChipTone.neutral, this.icon});

  final String label;
  final _ChipTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.appColors;
    final (Color bg, Color fg) = switch (tone) {
      _ChipTone.neutral => (
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant,
        ),
      _ChipTone.warning => (
          status.warningContainer,
          status.onWarningContainer,
        ),
      _ChipTone.error => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return ConstrainedBox(
      // Deckelt die Breite, damit ein langer Kategorie-/Standortname im
      // Wrap-Kontext (unbeschränkte Breite) nicht die Zeile sprengt.
      constraints: const BoxConstraints(maxWidth: 180),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
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
    // Semantischer Warn-Ton (appColors) statt frei überschriebenem
    // tertiaryContainer; tappbar über einen InkWell mit gleichem Radius.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(context.radii.lg),
        onTap: onTap,
        child: AppStatusBanner(
          icon: Icons.warning_amber_rounded,
          tone: AppStatusTone.warning,
          message:
              '$count Artikel unter Mindestbestand – jetzt nachbestellen',
          action: Icon(
            Icons.chevron_right,
            color: Theme.of(context).appColors.warning,
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = theme.appColors;
    final inventory = context.read<InventoryProvider>();

    // Bestandsfarbe über semantische Tokens (appColors.warning statt des frei
    // überschriebenen tertiary) — mit zusätzlichem, nicht-farblichem Signal.
    final stockColor = product.isOutOfStock
        ? colorScheme.error
        : (product.needsReorder ? status.warning : colorScheme.primary);

    // Kompakte Status-Pille in derselben Größe wie die Kennwert-Pillen, damit
    // die Wrap-Zeile gleich hoch bleibt (statt einer großen AppStatusBadge).
    final Widget? statusChip = product.isOutOfStock
        ? const _MetricChip('Leer',
            tone: _ChipTone.error, icon: Icons.error_outline)
        : (product.needsReorder
            ? const _MetricChip('Nachbestellen',
                tone: _ChipTone.warning, icon: Icons.warning_amber_rounded)
            : null);

    final siteName = sites.length > 1
        ? resolveSiteName(sites, product.siteId, fallback: product.siteName)
        : null;

    // Untertitel als umbruchsichere Kennwert-Pillen statt „·"-Kette, damit
    // Min/VK/Standort auf Handybreite nie still abgeschnitten werden. Die
    // „Bestand: X"-Angabe entfällt (dupliziert die Avatar-Zahl).
    final chips = <Widget>[
      // Status doppelt zu vermeiden: der Screenreader liest ihn schon aus dem
      // Leading-Semantics-Label → sichtbare Pille aus dem Semantics ausschließen.
      if (statusChip != null) ExcludeSemantics(child: statusChip),
      if (product.minStock > 0) _MetricChip('Min ${product.minStock}'),
      if (product.sellingPriceCents != null)
        _MetricChip('VK ${formatCents(product.sellingPriceCents)}'),
      if (product.category?.isNotEmpty ?? false) _MetricChip(product.category!),
      if (siteName?.isNotEmpty ?? false) _MetricChip(siteName!),
    ];

    final semanticStatus = product.isOutOfStock
        ? ', ausverkauft'
        : (product.needsReorder ? ', unter Mindestbestand' : '');

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        isThreeLine: chips.isNotEmpty,
        onTap: canManage ? () => _edit(context, inventory) : null,
        leading: Semantics(
          label:
              'Bestand ${product.currentStock} ${product.unit}$semanticStatus',
          child: ExcludeSemantics(
            child: SizedBox(
              width: 44,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: stockColor.withValues(alpha: 0.15),
                    child: Text(
                      '${product.currentStock}',
                      style: TextStyle(
                          color: stockColor, fontWeight: FontWeight.bold),
                    ),
                  ),
                  // Einheit als Caption unter der Zahl; FittedBox verhindert
                  // Überlauf des schmalen Leading-Slots bei großer Textskalierung.
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          product.unit,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        title: Text(
          product.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: chips.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: chips,
                ),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Schnellaktion für JEDEN aktiven Mitarbeiter: Artikel in den
            // gemeinsamen Bestellkorb legen ("Sorte ist leer"). Volles 48dp-
            // Touch-Target (kein visualDensity.compact).
            IconButton(
              tooltip: 'In den Bestellkorb',
              icon: const Icon(Icons.add_shopping_cart_outlined),
              onPressed: () => _addToCart(context, inventory),
            ),
            if (canManage) ...[
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: 'Artikel-Aktionen',
                onSelected: (value) => _onMenu(context, inventory, value),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
                  PopupMenuItem(
                      value: 'receive', child: Text('Zugang buchen')),
                  PopupMenuItem(
                      value: 'issue', child: Text('Abgang buchen')),
                  PopupMenuItem(
                      value: 'adjust', child: Text('Bestand korrigieren')),
                  PopupMenuItem(value: 'stocktake', child: Text('Inventur')),
                  PopupMenuItem(value: 'transfer', child: Text('Umlagern')),
                  PopupMenuDivider(),
                  PopupMenuItem(
                      value: 'movements', child: Text('Bewegungen anzeigen')),
                  PopupMenuItem(
                      value: 'priceHistory', child: Text('Preisverlauf')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'delete', child: Text('Löschen')),
                ],
              ),
            ],
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
    try {
      await inventory.addToCart(product: product, quantity: quantity);
      if (context.mounted) {
        _showSnack(context, '${product.name} in den Bestellkorb gelegt.');
      }
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, 'Fehler: $error');
      }
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
      case 'receive':
        await _receive(context, inventory);
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
      case 'movements':
        await _showMovementsSheet(context, product);
        break;
      case 'priceHistory':
        await showPriceHistorySheet(context, product: product);
        break;
      case 'delete':
        if (await _confirmDelete(context, product.name) &&
            product.id != null) {
          try {
            await inventory.deleteProduct(product.id!);
            if (context.mounted) {
              _showSnack(context, 'Artikel geloescht.');
            }
          } catch (error) {
            if (context.mounted) {
              _showSnack(context, 'Fehler: $error');
            }
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

  /// Wareneingang ohne Bestellung (z.B. Barkauf beim Großmarkt): positiver
  /// Zugang vom Typ `receipt` mit eigenem Grund — bewusst getrennt von der
  /// anonymen „Korrektur", damit Schwund-Auswertungen sauber bleiben.
  Future<void> _receive(
      BuildContext context, InventoryProvider inventory) async {
    final result = await _showStockReceiptDialog(context, product);
    if (result == null || product.id == null) {
      return;
    }
    try {
      await inventory.adjustStock(
        productId: product.id!,
        delta: result.quantity,
        type: StockMovementType.receipt,
        reason: result.reason,
      );
      if (context.mounted) {
        _showSnack(context, 'Zugang gebucht.');
      }
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, 'Fehler: $error');
      }
    }
  }

  Future<void> _adjust(
      BuildContext context, InventoryProvider inventory) async {
    final result = await _showStockDeltaDialog(context, product);
    if (result != null && result.delta != 0 && product.id != null) {
      try {
        await inventory.adjustStock(
          productId: product.id!,
          delta: result.delta,
          reason: result.reason,
        );
        if (context.mounted) {
          _showSnack(context, 'Bestand korrigiert.');
        }
      } catch (error) {
        if (context.mounted) {
          _showSnack(context, 'Fehler: $error');
        }
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
      try {
        await inventory.recordStocktake(
            product: product, countedStock: counted);
        if (context.mounted) {
          _showSnack(context, 'Inventur gebucht.');
        }
      } catch (error) {
        if (context.mounted) {
          _showSnack(context, 'Fehler: $error');
        }
      }
    }
  }

  Future<void> _transfer(
      BuildContext context, InventoryProvider inventory) async {
    // Ziel ist ein STANDORT, kein manuell vorangelegter Zielartikel: existiert
    // der Artikel dort noch nicht, legt der Provider ihn automatisch an
    // (transferStockToSite) — die tägliche Umlagerung zwischen den zwei Läden
    // scheitert damit nicht mehr an fehlenden Duplikaten.
    final otherSites = sites
        .where((site) => site.id != null && site.id != product.siteId)
        .toList();
    if (otherSites.isEmpty) {
      _showSnack(context, 'Es gibt keinen weiteren Standort zum Umlagern.');
      return;
    }
    final result =
        await _showTransferDialog(context, product, otherSites, inventory);
    if (result == null) {
      return;
    }
    final error = await inventory.transferStockToSite(
      from: product,
      toSiteId: result.site.id!,
      toSiteName: result.site.name,
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
        // Identität (Ansprechpartner + Lieferzeit) zuerst — überlebt die
        // Truncation; Kontaktdaten (längster Freitext) in Zeile 2.
        final identityLine = [
          if (supplier.contactPerson?.isNotEmpty ?? false)
            supplier.contactPerson!,
          if (supplier.leadTimeDays != null)
            'Lieferzeit ${supplier.leadTimeDays} Tage',
        ].join('  ·  ');
        final phone = supplier.phone?.trim();
        final email = supplier.effectiveOrderEmail;
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            isThreeLine:
                identityLine.isNotEmpty && (phone != null || email != null),
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
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (identityLine.isNotEmpty)
                    Text(
                      identityLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  // Telefon/E-Mail direkt antippbar — Nachbestellen am Telefon
                  // ist der häufigste Lieferanten-Kontakt im Ladenalltag.
                  if ((phone?.isNotEmpty ?? false) || email != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (phone?.isNotEmpty ?? false)
                            ActionChip(
                              avatar: const Icon(Icons.phone_outlined,
                                  size: 16),
                              label: Text(phone!),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _launchContact(
                                context,
                                Uri(scheme: 'tel', path: phone),
                                'Telefon-App konnte nicht geöffnet werden.',
                              ),
                            ),
                          if (email != null)
                            ActionChip(
                              avatar: const Icon(Icons.mail_outline,
                                  size: 16),
                              label: Text(
                                email,
                                overflow: TextOverflow.ellipsis,
                              ),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _launchContact(
                                context,
                                Uri(scheme: 'mailto', path: email),
                                'E-Mail-App konnte nicht geöffnet werden.',
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
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
                      PopupMenuItem(value: 'delete', child: Text('Löschen')),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }

  /// Öffnet tel:/mailto: extern; Fehlschlag (kein Handler, z.B. Desktop ohne
  /// Mail-Client) wird als deutsche SnackBar gemeldet statt still verschluckt.
  Future<void> _launchContact(
    BuildContext context,
    Uri uri,
    String errorMessage,
  ) async {
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      _showSnack(context, errorMessage);
    }
  }

  Future<void> _edit(
    BuildContext context,
    InventoryProvider inventory,
    Supplier supplier,
  ) async {
    final result = await showSupplierDialog(context, supplier: supplier);
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
}

// ===========================================================================
// Bestellungen-Tab
// ===========================================================================

/// Status-Filter des Bestellungen-Tabs.
enum _OrderFilter { alle, offen, geliefert, storniert }

class _OrdersTab extends StatefulWidget {
  const _OrdersTab({
    required this.siteId,
    required this.canManage,
    required this.sites,
  });

  final String? siteId;
  final bool canManage;
  final List<SiteDefinition> sites;

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  _OrderFilter _filter = _OrderFilter.alle;

  bool _matchesFilter(PurchaseOrder order) => switch (_filter) {
        _OrderFilter.alle => true,
        _OrderFilter.offen => order.status == PurchaseOrderStatus.draft ||
            order.status == PurchaseOrderStatus.ordered ||
            order.status == PurchaseOrderStatus.partiallyReceived,
        _OrderFilter.geliefert =>
          order.status == PurchaseOrderStatus.received,
        _OrderFilter.storniert =>
          order.status == PurchaseOrderStatus.cancelled,
      };

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final allOrders = inventory.ordersForSite(widget.siteId);

    if (allOrders.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        message:
            'Noch keine Bestellungen. Erstelle ueber das Plus eine Bestellung.',
      );
    }

    final orders = allOrders.where(_matchesFilter).toList();
    final openCount = allOrders
        .where((order) =>
            order.status == PurchaseOrderStatus.draft ||
            order.status == PurchaseOrderStatus.ordered ||
            order.status == PurchaseOrderStatus.partiallyReceived)
        .length;

    return Column(
      children: [
        // Status-Schnellfilter: die Historie wächst unbegrenzt — im Alltag
        // zählt fast immer nur „Offen".
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (filter, label) in [
                  (_OrderFilter.alle, 'Alle'),
                  (
                    _OrderFilter.offen,
                    openCount > 0 ? 'Offen ($openCount)' : 'Offen'
                  ),
                  (_OrderFilter.geliefert, 'Geliefert'),
                  (_OrderFilter.storniert, 'Storniert'),
                ]) ...[
                  FilterChip(
                    label: Text(label),
                    selected: _filter == filter,
                    onSelected: (selected) => setState(() =>
                        _filter = selected ? filter : _OrderFilter.alle),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: orders.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  message: 'Keine Bestellungen mit diesem Status.',
                )
              : _buildList(context, orders),
        ),
      ],
    );
  }

  Widget _buildList(BuildContext context, List<PurchaseOrder> orders) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, kFabSafeBottomInset),
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
                  sites: widget.sites,
                  canManage: widget.canManage,
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
    // Semantische Töne: erhalten=Erfolg, teilweise=Warnung, bestellt=Info.
    final tone = switch (status) {
      PurchaseOrderStatus.draft => AppStatusTone.neutral,
      PurchaseOrderStatus.ordered => AppStatusTone.info,
      PurchaseOrderStatus.partiallyReceived => AppStatusTone.warning,
      PurchaseOrderStatus.received => AppStatusTone.success,
      PurchaseOrderStatus.cancelled => AppStatusTone.error,
    };
    return AppStatusBadge(label: status.label, tone: tone);
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
  late final TextEditingController _taxRate;
  late final TextEditingController _stock;
  late final TextEditingController _minStock;
  late final TextEditingController _targetStock;
  late final TextEditingController _reorderQty;
  late final TextEditingController _fridgeTargetStock;
  String? _siteId;
  String? _supplierId;
  bool _inFridge = false;
  bool _suggestingFridge = false;

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
    _taxRate =
        TextEditingController(text: product?.taxRatePercent?.toString() ?? '');
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
    _inFridge = product?.inFridge ?? false;
    _fridgeTargetStock = TextEditingController(
        text: (product?.fridgeTargetStock ?? 0) > 0
            ? product!.fridgeTargetStock.toString()
            : '');
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
    _taxRate.dispose();
    _stock.dispose();
    _minStock.dispose();
    _targetStock.dispose();
    _reorderQty.dispose();
    _fridgeTargetStock.dispose();
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
                        // Harte Eindeutigkeit je Laden: freundliche Meldung
                        // schon im Formular (saveProduct lehnt das Duplikat
                        // sonst mit StateError ab).
                        validator: _validateBarcodeUnique,
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
                        // Nicht parsebare Eingabe blockiert das Speichern —
                        // sonst löscht ein Tippfehler („1,9o") still den
                        // gespeicherten Preis (clearPurchasePrice in _submit).
                        validator: _validatePriceInput,
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
                        validator: _validatePriceInput,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stock,
                        readOnly: isEdit,
                        enabled: !isEdit,
                        decoration: InputDecoration(
                          labelText: 'Bestand',
                          helperText: isEdit
                              ? 'Nur über „Bestand korrigieren“/„Inventur“'
                              : null,
                          helperMaxLines: 2,
                        ),
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
                const SizedBox(height: 12),
                TextFormField(
                  controller: _taxRate,
                  decoration: const InputDecoration(
                    labelText: 'USt-Satz % (optional)',
                    helperText: 'Für den Versand an die Kasse, z.B. 19 oder 7. '
                        'Leer ⇒ Standardsatz aus den Kassen-Einstellungen',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _inFridge,
                  onChanged: (value) => setState(() => _inFridge = value),
                  secondary: const Icon(Icons.kitchen_outlined),
                  title: const Text('Im Verkaufs-Kühlschrank führen'),
                  subtitle: const Text(
                      'Aktiviert die Kühlschrank-Soll-Ist-Nachfüllung'),
                ),
                if (_inFridge)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _fridgeTargetStock,
                          decoration: const InputDecoration(
                            labelText: 'Kühlschrank-Soll',
                            helperText: 'Voll-Füllstand des Kühlschranks',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: TextButton.icon(
                          onPressed:
                              _suggestingFridge ? null : _applyFridgeSuggestion,
                          icon: _suggestingFridge
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.auto_awesome, size: 18),
                          label: const Text('Vorschlag'),
                        ),
                      ),
                    ],
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

  /// Leer ist erlaubt (Preis wird geloescht), aber eine nicht parsebare
  /// Eingabe blockiert das Speichern — sonst ginge der gespeicherte Preis
  /// still verloren (clear*-Flags in [_submit]).
  static String? _validatePriceInput(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    return parseEuroToCents(text) == null
        ? 'Ungültiger Betrag (z.B. 1,99)'
        : null;
  }

  /// Harte Barcode-Eindeutigkeit je Laden (Spiegel der saveProduct-Prüfung):
  /// derselbe Code darf im gewählten Laden an keinem ANDEREN Artikel hängen
  /// (auch keinem deaktivierten). Unverändert belassene Alt-Barcodes bleiben
  /// gültig — Altbestands-Duplikate blockieren das Bearbeiten nicht.
  String? _validateBarcodeUnique(String? value) {
    final code = value?.trim() ?? '';
    if (code.isEmpty) {
      return null;
    }
    final unchanged = widget.product != null &&
        (widget.product!.barcode?.trim() ?? '') == code;
    if (unchanged) {
      return null;
    }
    final inventory = context.read<InventoryProvider>();
    final clash = inventory
        .productsByBarcode(code, siteId: _siteId, includeInactive: true)
        .where((other) => other.id != widget.product?.id);
    if (clash.isEmpty) {
      return null;
    }
    final first = clash.first;
    return 'Bereits vergeben an „${first.name}"'
        '${first.isActive ? '' : ' (deaktiviert)'}';
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
      taxRatePercent: int.tryParse(_taxRate.text.trim()),
      clearTaxRatePercent: _taxRate.text.trim().isEmpty,
      // Bestand nur bei Neuanlage aus dem Feld übernehmen. Beim Bearbeiten
      // bleibt der Live-Bestand unangetastet — Änderungen laufen ausschließlich
      // über adjustStock/recordStocktake (buchen StockMovement + Audit).
      currentStock: widget.product == null
          ? (int.tryParse(_stock.text.trim()) ?? 0)
          : base.currentStock,
      minStock: int.tryParse(_minStock.text.trim()) ?? 0,
      targetStock: int.tryParse(_targetStock.text.trim()) ?? 0,
      reorderQuantity: int.tryParse(_reorderQty.text.trim()),
      clearReorderQuantity: _reorderQty.text.trim().isEmpty,
      inFridge: _inFridge,
      fridgeTargetStock:
          _inFridge ? (int.tryParse(_fridgeTargetStock.text.trim()) ?? 0) : 0,
    );
    Navigator.of(context).pop(result);
  }

  /// Übernimmt den velocity-abgeleiteten Kühlschrank-Soll-Vorschlag (§12.4).
  /// Nur für bereits gespeicherte Artikel (braucht Verkaufsdaten).
  Future<void> _applyFridgeSuggestion() async {
    final product = widget.product;
    final messenger = ScaffoldMessenger.of(context);
    if (product?.id == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text(
            'Vorschlag erst nach dem ersten Speichern (braucht Verkaufsdaten).'),
      ));
      return;
    }
    final inventory = context.read<InventoryProvider>();
    setState(() => _suggestingFridge = true);
    try {
      final suggestion =
          await inventory.suggestFridgeTargetForProduct(product!);
      if (!mounted) return;
      if (suggestion == null || suggestion <= 0) {
        messenger.showSnackBar(const SnackBar(
          content:
              Text('Noch kein belastbarer Vorschlag (zu wenig Verkaufsdaten).'),
        ));
      } else {
        setState(() => _fridgeTargetStock.text = suggestion.toString());
      }
    } finally {
      if (mounted) setState(() => _suggestingFridge = false);
    }
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

Future<({SiteDefinition site, int quantity})?> _showTransferDialog(
  BuildContext context,
  Product product,
  List<SiteDefinition> otherSites,
  InventoryProvider inventory,
) {
  SiteDefinition targetSite = otherSites.first;
  final quantityController = TextEditingController();
  return showDialog<({SiteDefinition site, int quantity})>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) {
        final qty = int.tryParse(quantityController.text.trim());
        // Live-Validierung: nicht mehr umlagern, als am Quell-Standort da ist.
        final String? qtyError = (qty == null || qty <= 0)
            ? null
            : (qty > product.currentStock
                ? 'Nur ${product.currentStock} ${product.unit} verfügbar'
                : null);
        final canBook = qty != null && qty > 0 && qtyError == null;
        // Vorschau: existiert der Artikel am Ziel schon oder wird er (mit
        // denselben Stammdaten, Bestand 0) automatisch angelegt?
        final existingTarget =
            inventory.findTransferTarget(product, targetSite.id!);
        final theme = Theme.of(context);
        return AlertDialog(
          title: Text('Umlagern: ${product.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bestand ${product.siteName ?? 'Quelle'}: '
                  '${product.currentStock} ${product.unit}'),
              const SizedBox(height: 12),
              DropdownButtonFormField<SiteDefinition>(
                initialValue: targetSite,
                decoration: const InputDecoration(
                  labelText: 'Ziel-Standort',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final site in otherSites)
                    DropdownMenuItem(
                      value: site,
                      child: Text(site.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => targetSite = value);
                },
              ),
              const SizedBox(height: 8),
              Text(
                existingTarget != null
                    ? 'Zielartikel vorhanden (Bestand '
                        '${existingTarget.currentStock} ${existingTarget.unit}).'
                    : 'Artikel wird am Zielstandort automatisch angelegt '
                        '(Bestand 0, gleiche Stammdaten).',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantityController,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Menge',
                  border: const OutlineInputBorder(),
                  errorText: qtyError,
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
              onPressed: canBook
                  ? () => Navigator.of(context)
                      .pop((site: targetSite, quantity: qty))
                  : null,
              child: const Text('Umlagern'),
            ),
          ],
        );
      },
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

Future<({int delta, String reason})?> _showStockDeltaDialog(
    BuildContext context, Product product) {
  final controller = TextEditingController();
  final reasonController = TextEditingController();
  return showDialog<({int delta, String reason})>(
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
          const SizedBox(height: 12),
          // Grund macht die Korrektur in Bewegungen/Schwund-Report
          // nachvollziehbar (Bruch, Zaehlfehler, Eigenbedarf ...).
          TextField(
            controller: reasonController,
            decoration: const InputDecoration(
              labelText: 'Grund (z.B. Bruch, Zählfehler)',
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
            final delta = int.tryParse(controller.text.trim());
            if (delta == null) {
              Navigator.of(context).pop();
              return;
            }
            final reason = reasonController.text.trim();
            Navigator.of(context).pop((
              delta: delta,
              reason: reason.isEmpty ? 'Manuelle Korrektur' : reason,
            ));
          },
          child: const Text('Buchen'),
        ),
      ],
    ),
  );
}

/// Zugang buchen (Wareneingang ohne Bestellung). Nur positive Mengen.
Future<({int quantity, String reason})?> _showStockReceiptDialog(
    BuildContext context, Product product) {
  final quantityController = TextEditingController();
  final reasonController = TextEditingController();
  return showDialog<({int quantity, String reason})>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) {
        final qty = int.tryParse(quantityController.text.trim());
        final canBook = qty != null && qty > 0;
        return AlertDialog(
          title: Text('Zugang buchen: ${product.name}'),
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
                decoration: const InputDecoration(
                  labelText: 'Menge (Zugang)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Grund (z.B. Barkauf Großmarkt)',
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
              onPressed: canBook
                  ? () {
                      final reason = reasonController.text.trim();
                      Navigator.of(context).pop((
                        quantity: qty,
                        reason: reason.isEmpty ? 'Wareneingang' : reason,
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

Future<int?> _showStocktakeDialog(BuildContext context, Product product) {
  // Bewusst KEINE Vorbefuellung mit dem Buchbestand: ein hastiges „Speichern"
  // wuerde sonst eine Schein-Inventur buchen, die den Buchbestand als gezaehlt
  // bestaetigt. Leeres Pflichtfeld erzwingt echtes Zaehlen.
  final controller = TextEditingController();
  return showDialog<int>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) {
        final counted = int.tryParse(controller.text.trim());
        return AlertDialog(
          title: Text('Inventur: ${product.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  'Bisheriger Bestand: ${product.currentStock} ${product.unit}'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Gezaehlter Bestand',
                  hintText: 'Tatsaechlich gezaehlte Menge',
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
              onPressed: counted == null
                  ? null
                  : () => Navigator.of(context).pop(counted),
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    ),
  );
}

/// Bewegungshistorie eines Artikels als Bottom-Sheet — macht erstmals in der
/// Warenwirtschaft sichtbar, WARUM ein Bestand ist, wie er ist (Wareneingang,
/// Abgang, Korrektur, Inventur, Umlagerung, Kühlschrank, Kasse).
Future<void> _showMovementsSheet(BuildContext context, Product product) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MovementsSheet(product: product),
  );
}

class _MovementsSheet extends StatefulWidget {
  const _MovementsSheet({required this.product});

  final Product product;

  @override
  State<_MovementsSheet> createState() => _MovementsSheetState();
}

class _MovementsSheetState extends State<_MovementsSheet> {
  static final DateFormat _dateFormat =
      DateFormat('dd.MM.yyyy HH:mm', 'de_DE');

  /// Einmalig im State gehalten — ein in build() erzeugtes Future liesse
  /// jeden Sheet-Rebuild (Rotation, Theme, Tastatur) neu laden und zurueck
  /// zum Spinner springen (klassische FutureBuilder-Falle).
  Future<List<StockMovement>>? _future;

  @override
  void initState() {
    super.initState();
    final productId = widget.product.id;
    if (productId != null) {
      _future =
          context.read<InventoryProvider>().movementsForProduct(productId);
    }
  }

  IconData _iconFor(StockMovementType type) => switch (type) {
        StockMovementType.receipt => Icons.call_received,
        StockMovementType.issue => Icons.call_made,
        StockMovementType.adjustment => Icons.tune,
        StockMovementType.stocktake => Icons.fact_check_outlined,
        StockMovementType.transfer => Icons.swap_horiz,
        StockMovementType.fridgeRefill => Icons.kitchen_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = theme.appColors;
    final product = widget.product;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Bewegungen: ${product.name}',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: _future == null
                ? const EmptyState(
                    icon: Icons.history,
                    message: 'Artikel ist noch nicht gespeichert.',
                  )
                : FutureBuilder<List<StockMovement>>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState !=
                          ConnectionState.done) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      final movements =
                          snapshot.data ?? const <StockMovement>[];
                      if (movements.isEmpty) {
                        return const EmptyState(
                          icon: Icons.history,
                          message:
                              'Noch keine Bewegungen zu diesem Artikel.',
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: movements.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final movement = movements[index];
                          final delta = movement.quantityDelta;
                          final deltaColor = delta > 0
                              ? status.success
                              : (delta < 0
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurfaceVariant);
                          final subtitleParts = <String>[
                            if (movement.createdAt != null)
                              _dateFormat.format(movement.createdAt!),
                            if (movement.reason?.isNotEmpty ?? false)
                              movement.reason!,
                            if (movement.isFromPos) 'Kasse',
                          ];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(_iconFor(movement.type),
                                color: theme.colorScheme.onSurfaceVariant),
                            title: Text(movement.type.label),
                            subtitle: subtitleParts.isEmpty
                                ? null
                                : Text(
                                    subtitleParts.join('  ·  '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  delta > 0 ? '+$delta' : '$delta',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: deltaColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (movement.balanceAfter != null)
                                  Text(
                                    'Bestand: ${movement.balanceAfter}',
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(
                                      color: theme
                                          .colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Admin-Einstellungen der OktoPOS-Kassenanbindung: Basis-URL, nächtlicher
/// Auto-Abgleich und Kassen-Nr. (`cash-register`) je Laden. Schreibt
/// merge-sicher ins Config-Doc `config/oktoposSync` — der serverseitige
/// Sync-Cursor bleibt erhalten. Der **API-Key wird hier nie eingegeben** (er
/// liegt ausschließlich serverseitig im Secret Manager).
class _OktoposSettingsSheet extends StatefulWidget {
  const _OktoposSettingsSheet({required this.inventory, required this.sites});

  final InventoryProvider inventory;
  final List<SiteDefinition> sites;

  @override
  State<_OktoposSettingsSheet> createState() => _OktoposSettingsSheetState();
}

class _OktoposSettingsSheetState extends State<_OktoposSettingsSheet> {
  final TextEditingController _baseUrlController = TextEditingController();
  final Map<String, TextEditingController> _crControllers = {};
  final Map<String, String> _lastBusinessDayBySite = {};
  // Artikel-Versand (Push, M5).
  final TextEditingController _channelController = TextEditingController();
  final TextEditingController _unitTokenController = TextEditingController();
  final TextEditingController _taxController = TextEditingController(text: '19');
  final TextEditingController _customerGroupController =
      TextEditingController(text: 'Stammkunde');
  bool _cashierCanChange = false;
  bool _loadingTokens = false;
  // Seitengröße des Kassen-Pulls. Nicht in der UI editierbar (Default 50), wird
  // aber round-getrippt, damit ein evtl. serverseitig gesetzter Wert beim
  // Speichern erhalten bleibt.
  int _defaultSize = 50;
  bool _enabled = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final site in widget.sites) {
      final id = site.id;
      if (id != null) {
        _crControllers[id] = TextEditingController();
      }
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final config = await widget.inventory.loadOktoposConfig();
      if (!mounted) {
        return;
      }
      if (config != null) {
        _baseUrlController.text = (config['baseUrl'] ?? '').toString();
        _enabled = config['enabled'] == true;
        final size = config['defaultSize'];
        if (size is num && size.toInt() > 0) {
          _defaultSize = size.toInt();
        }
        final sites = config['sites'];
        if (sites is Map) {
          sites.forEach((key, value) {
            final siteId = key.toString();
            if (value is Map) {
              final cr = value['cashRegisterId'];
              if (cr is num && _crControllers.containsKey(siteId)) {
                _crControllers[siteId]!.text = cr.toInt().toString();
              }
              final last = value['lastBusinessDay'];
              if (last != null) {
                _lastBusinessDayBySite[siteId] = last.toString();
              }
            }
          });
        }
        final push = config['push'];
        if (push is Map) {
          _channelController.text =
              (push['distributionChannel'] ?? '').toString();
          _unitTokenController.text =
              (push['defaultUnitToken'] ?? '').toString();
          final tax = push['defaultTaxRate'];
          if (tax is num && tax.toInt() > 0) {
            _taxController.text = tax.toInt().toString();
          }
          _cashierCanChange = push['cashierCanChangePrice'] == true;
        }
        final group = config['customerGroupName'];
        if (group is String && group.trim().isNotEmpty) {
          _customerGroupController.text = group;
        }
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _channelController.dispose();
    _unitTokenController.dispose();
    _taxController.dispose();
    _customerGroupController.dispose();
    for (final controller in _crControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isNotEmpty && !baseUrl.toLowerCase().startsWith('https://')) {
      setState(() => _error = 'Die Basis-URL muss mit https:// beginnen.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final cashRegisterBySiteId = <String, int?>{};
    for (final entry in _crControllers.entries) {
      final text = entry.value.text.trim();
      cashRegisterBySiteId[entry.key] = text.isEmpty ? null : int.tryParse(text);
    }
    try {
      await widget.inventory.saveOktoposConfig(
        baseUrl: baseUrl,
        enabled: _enabled,
        defaultSize: _defaultSize,
        cashRegisterBySiteId: cashRegisterBySiteId,
        distributionChannel: _channelController.text.trim(),
        defaultUnitToken: _unitTokenController.text.trim(),
        defaultTaxRate: int.tryParse(_taxController.text.trim()) ?? 19,
        cashierCanChangePrice: _cashierCanChange,
        customerGroupName: _customerGroupController.text.trim().isEmpty
            ? null
            : _customerGroupController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  /// Holt Einheiten-/Vertriebskanal-Tokens aus der Kasse und lässt den Admin
  /// einen in das jeweilige Feld übernehmen (Antippen = einsetzen).
  Future<void> _loadTokens() async {
    final siteId = widget.sites.isNotEmpty ? widget.sites.first.id : null;
    if (siteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kein Laden vorhanden.')),
      );
      return;
    }
    setState(() => _loadingTokens = true);
    try {
      final lookups = await widget.inventory.loadOktoposLookups(siteId: siteId);
      if (!mounted) {
        return;
      }
      final units = (lookups?['units'] as List?) ?? const [];
      final channels = (lookups?['distributionChannels'] as List?) ?? const [];
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Kassen-Tokens'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Vertriebskanäle',
                      style: Theme.of(dialogContext).textTheme.labelLarge),
                  if (channels.isEmpty) const Text('—'),
                  for (final c in channels)
                    if (c is Map && c['token'] != null)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.input, size: 18),
                        title: Text(c['token'].toString()),
                        onTap: () {
                          _channelController.text = c['token'].toString();
                          Navigator.of(dialogContext).pop();
                        },
                      ),
                  const Divider(),
                  Text('Einheiten',
                      style: Theme.of(dialogContext).textTheme.labelLarge),
                  if (units.isEmpty) const Text('—'),
                  for (final u in units)
                    if (u is Map && u['token'] != null)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.input, size: 18),
                        title: Text(u['token'].toString()),
                        onTap: () {
                          _unitTokenController.text = u['token'].toString();
                          Navigator.of(dialogContext).pop();
                        },
                      ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tokens laden fehlgeschlagen: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loadingTokens = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.point_of_sale_outlined),
                const SizedBox(width: 8),
                Text('Kassen-Einstellungen (OktoPOS)',
                    style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Der API-Schlüssel wird hier NICHT gespeichert – er liegt sicher '
              'serverseitig. Hier nur Basis-URL und Kassen-Nr. je Laden.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              TextField(
                controller: _baseUrlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Basis-URL',
                  hintText: 'https://<instanz>/v1',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Nächtlicher Auto-Abgleich'),
                subtitle: const Text('Täglich 03:30 automatisch übernehmen'),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              const SizedBox(height: 8),
              Text('Kassen-Nr. je Laden', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final site in widget.sites)
                if (site.id != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: _crControllers[site.id],
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: site.name,
                        hintText: 'leer = alle Kassen',
                        helperText: _lastBusinessDayBySite[site.id] != null
                            ? 'Zuletzt abgeglichen bis '
                                '${_lastBusinessDayBySite[site.id]}'
                            : null,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
              const SizedBox(height: 16),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: Text('Artikel-Versand (Push)',
                        style: theme.textTheme.labelLarge),
                  ),
                  TextButton.icon(
                    onPressed: _loadingTokens ? null : _loadTokens,
                    icon: _loadingTokens
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Tokens laden'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _channelController,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Vertriebskanal-Token',
                  hintText: 'z.B. INHOUSE',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _unitTokenController,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Standard-Einheit-Token',
                  hintText: 'z.B. Stück',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _taxController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Standard-USt-Satz %',
                  hintText: 'z.B. 19',
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Kasse darf Preis ändern'),
                value: _cashierCanChange,
                onChanged: (value) => setState(() => _cashierCanChange = value),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _customerGroupController,
                decoration: const InputDecoration(
                  labelText: 'Kundengruppe (für Kunden-Versand)',
                  hintText: 'z.B. Stammkunde',
                  helperText: 'OktoPOS verlangt je Kunde eine Gruppe',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Speichern'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
