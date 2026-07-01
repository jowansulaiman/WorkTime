import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/assortment_gap.dart';
import '../core/dead_stock.dart';
import '../core/money.dart';
import '../core/reorder_suggestion.dart';
import '../core/sales_velocity.dart';
import '../core/shrinkage_report.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/sales_insights_provider.dart';
import '../theme/theme_extensions.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_card.dart';

/// **Bestand-Insights (P1.1–P1.3).** Admin-Auswertung je Standort: Ladenhüter +
/// gebundenes totes Kapital, Umlagerungsvorschläge in den anderen Laden und
/// datengetriebene Bestellschwellen — jeweils mit empfohlener Aktion statt
/// Datenwand. Liest den [SalesInsightsProvider] (Read-State); die Berechnung
/// liegt in den puren Cores. Enthält EK-Preise -> admin-only (Route + Guard).
class BestandInsightsScreen extends StatefulWidget {
  const BestandInsightsScreen({super.key, this.parentLabel = 'Warenwirtschaft'});

  final String parentLabel;

  @override
  State<BestandInsightsScreen> createState() => _BestandInsightsScreenState();
}

class _BestandInsightsScreenState extends State<BestandInsightsScreen> {
  String? _siteId;
  bool _applying = false;

  void _load(String siteId) {
    context.read<SalesInsightsProvider>().load(
          siteId: siteId,
          windowDays: SalesVelocity.defaultReliableDays,
          deadStockWindowDays: 60,
        );
  }

  /// Übernimmt die vorgeschlagenen Melde-/Zielbestand-Schwellen in den Artikel
  /// (schreibt über den vorhandenen Produkt-Save) und lädt die Auswertung neu.
  Future<void> _applyReorder(ReorderSuggestion suggestion, Product? product) async {
    if (product == null || _applying) return;
    final messenger = ScaffoldMessenger.of(context);
    final inventory = context.read<InventoryProvider>();
    setState(() => _applying = true);
    try {
      await inventory.saveProduct(product.copyWith(
        minStock: suggestion.suggestedMinStock,
        targetStock: suggestion.suggestedTargetStock,
      ));
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text('Schwellen für „${product.name}" übernommen.')));
      if (_siteId != null) _load(_siteId!);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
          const SnackBar(content: Text('Übernehmen fehlgeschlagen.')));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  /// Bucht die vorgeschlagene Umlagerung paarweise (Abgang Quelle + Eingang Ziel)
  /// über die vorhandene `transferStock`-Mutation.
  Future<void> _applyTransfer(TransferSuggestion suggestion) async {
    if (_applying) return;
    final messenger = ScaffoldMessenger.of(context);
    final inventory = context.read<InventoryProvider>();
    setState(() => _applying = true);
    final error = await inventory.transferStock(
      from: suggestion.fromProduct,
      to: suggestion.toProduct,
      quantity: suggestion.quantity,
    );
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(error ??
          '${suggestion.quantity}× „${suggestion.fromProduct.name}" umgelagert.'),
    ));
    if (error == null && _siteId != null) _load(_siteId!);
    setState(() => _applying = false);
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final breadcrumbs = [
      BreadcrumbItem(
        label: widget.parentLabel,
        onTap: () => Navigator.of(context).maybePop(),
      ),
      const BreadcrumbItem(label: 'Bestand-Insights'),
    ];

    if (profile == null || !profile.isAdmin) {
      return Scaffold(
        appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
        body: const Center(child: Text('Nur für Administratoren.')),
      );
    }

    final inventory = context.watch<InventoryProvider>();
    final insights = context.watch<SalesInsightsProvider>();
    final sites = _sitesFrom(inventory.products);

    // Default-Standort wählen und Erst-Laden anstoßen — aber nur, wenn der
    // Provider noch keine (frischen) Daten für diesen Standort hält (überlebt
    // Navigation zurück; vermeidet Reload bei jedem Aufbau). Außerhalb des
    // Builds via postFrame, damit kein notify während des Builds passiert.
    if (_siteId == null && sites.isNotEmpty) {
      _siteId = sites.first.id;
    }
    final siteId = _siteId;
    if (siteId != null && insights.siteId != siteId && !insights.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final p = context.read<SalesInsightsProvider>();
        if (p.siteId != siteId && !p.isLoading) _load(siteId);
      });
    }

    final productsById = <String, Product>{
      for (final p in inventory.products)
        if (p.id != null) p.id!: p,
    };

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: breadcrumbs,
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            icon: const Icon(Icons.refresh),
            onPressed: _siteId == null ? null : () => _load(_siteId!),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (sites.length > 1) _buildSiteSelector(sites),
            Expanded(
              child: _buildBody(context, insights, productsById, sites),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSiteSelector(List<_SiteRef> sites) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DropdownButton<String>(
          value: _siteId,
          onChanged: (value) {
            if (value == null) return;
            setState(() => _siteId = value);
            _load(value);
          },
          items: [
            for (final s in sites)
              DropdownMenuItem(value: s.id, child: Text(s.name)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SalesInsightsProvider insights,
    Map<String, Product> productsById,
    List<_SiteRef> sites,
  ) {
    if (sites.isEmpty) {
      return const EmptyState(
        icon: Icons.warehouse_outlined,
        title: 'Keine Artikel',
        message: 'Sobald Artikel und Verkäufe vorliegen, erscheinen hier '
            'Reichweite, Ladenhüter und Bestellvorschläge.',
      );
    }
    if (insights.error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Auswertung fehlgeschlagen',
        message: insights.error!,
        action: FilledButton.tonal(
          onPressed: _siteId == null ? null : () => _load(_siteId!),
          child: const Text('Erneut versuchen'),
        ),
      );
    }
    if (insights.isLoading && insights.velocities.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final deadStock = insights.deadStock;
    final transfers = insights.transfers;
    final reorders = insights.reorderChanges;
    final shrinkageLosses = insights.shrinkageLosses;
    final listingGaps = insights.listingGaps;

    return RefreshIndicator(
      onRefresh: () async {
        final siteId = _siteId;
        if (siteId == null) return;
        await context.read<SalesInsightsProvider>().load(siteId: siteId);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Datenbasis: letzte ${insights.windowDays} Tage '
            '(Ladenhüter: ${insights.deadStockWindowDays} Tage).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          _buildKpis(context, insights),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Ladenhüter (${deadStock.length})',
            child: deadStock.isEmpty
                ? const _SectionEmpty('Keine Ladenhüter im Zeitraum.')
                : Column(
                    children: [
                      for (final v in deadStock.take(50))
                        _DeadStockTile(velocity: v, products: productsById),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Umlagerung in den anderen Laden (${transfers.length})',
            child: transfers.isEmpty
                ? const _SectionEmpty(
                    'Keine sinnvolle Umlagerung gefunden.')
                : Column(
                    children: [
                      for (final t in transfers.take(50))
                        _TransferTile(
                          t,
                          onApply: _applying ? null : () => _applyTransfer(t),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Bestellschwellen-Vorschläge (${reorders.length})',
            child: reorders.isEmpty
                ? const _SectionEmpty(
                    'Aktuelle Melde-/Zielbestände passen zur Nachfrage.')
                : Column(
                    children: [
                      for (final r in reorders.take(50))
                        _ReorderTile(
                          suggestion: r,
                          products: productsById,
                          onApply: _applying
                              ? null
                              : () => _applyReorder(r, productsById[r.productId]),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Schwund / Inventurdifferenz (${shrinkageLosses.length})',
            child: shrinkageLosses.isEmpty
                ? const _SectionEmpty(
                    'Keine Inventurdifferenz im Zeitraum erfasst.')
                : Column(
                    children: [
                      for (final s in shrinkageLosses.take(50))
                        _ShrinkageTile(s),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Listungslücken — läuft im anderen Laden (${listingGaps.length})',
            child: listingGaps.isEmpty
                ? const _SectionEmpty(
                    'Kein Renner aus dem anderen Laden fehlt hier.')
                : Column(
                    children: [
                      for (final g in listingGaps.take(50)) _ListingGapTile(g),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpis(BuildContext context, SalesInsightsProvider insights) {
    final colors = Theme.of(context).appColors;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _StatCard(
          icon: Icons.hourglass_empty,
          label: 'Ladenhüter',
          value: '${insights.deadStock.length}',
          color: colors.warning,
        ),
        _StatCard(
          icon: Icons.savings_outlined,
          label: 'Totes Kapital',
          value: Money.formatCents(insights.tiedUpDeadCapitalCents),
          color: colors.warning,
        ),
        _StatCard(
          icon: Icons.swap_horiz,
          label: 'Umlagerungen',
          value: '${insights.transfers.length}',
          color: colors.info,
        ),
        _StatCard(
          icon: Icons.tune,
          label: 'Schwellen-Tipps',
          value: '${insights.reorderChanges.length}',
          color: colors.info,
        ),
        if ((insights.shrinkage?.shrinkageValueCents ?? 0) > 0)
          _StatCard(
            icon: Icons.report_gmailerrorred_outlined,
            label: 'Schwund (${insights.shrinkageWindowDays} T)',
            value: Money.formatCents(insights.shrinkage!.shrinkageValueCents),
            color: colors.warning,
          ),
      ],
    );
  }

  List<_SiteRef> _sitesFrom(List<Product> products) {
    final byId = <String, String>{};
    for (final p in products) {
      byId.putIfAbsent(p.siteId, () => p.siteName ?? p.siteId);
    }
    final list = byId.entries.map((e) => _SiteRef(e.key, e.value)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }
}

class _SiteRef {
  const _SiteRef(this.id, this.name);
  final String id;
  final String name;
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline,
              size: 18, color: Theme.of(context).appColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeadStockTile extends StatelessWidget {
  const _DeadStockTile({required this.velocity, required this.products});

  final ProductVelocity velocity;
  final Map<String, Product> products;

  @override
  Widget build(BuildContext context) {
    final name = products[velocity.productId]?.name ?? velocity.productId;
    final capital = velocity.isValuated
        ? Money.formatCents(velocity.tiedUpCapitalCents)
        : 'unbewertet';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.hourglass_empty,
          color: Theme.of(context).appColors.warning),
      title: Text(name),
      subtitle: Text('Bestand ${velocity.currentStock} · gebundenes Kapital '
          '$capital · 0 Verkäufe'),
    );
  }
}

class _ListingGapTile extends StatelessWidget {
  const _ListingGapTile(this.gap);

  final ListingGap gap;

  @override
  Widget build(BuildContext context) {
    final fromSite =
        gap.sellingProduct.siteName ?? gap.sellingProduct.siteId;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.add_business_outlined,
          color: Theme.of(context).appColors.success),
      title: Text(gap.sellingProduct.name),
      subtitle: Text('läuft in $fromSite (${gap.soldUnits} verkauft) · '
          'hier nicht geführt'),
    );
  }
}

class _ShrinkageTile extends StatelessWidget {
  const _ShrinkageTile(this.item);

  final ShrinkageItem item;

  @override
  Widget build(BuildContext context) {
    // netValueCents ist hier negativ (nur Verluste werden gelistet).
    final loss = Money.formatCents(-(item.netValueCents ?? 0));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.report_gmailerrorred_outlined,
          color: Theme.of(context).appColors.warning),
      title: Text(item.name ?? item.productId),
      subtitle: Text('${item.netUnits} Stück · Verlust $loss'),
    );
  }
}

class _TransferTile extends StatelessWidget {
  const _TransferTile(this.suggestion, {this.onApply});

  final TransferSuggestion suggestion;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final toSite = suggestion.toProduct.siteName ?? suggestion.toProduct.siteId;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.swap_horiz, color: Theme.of(context).appColors.info),
      title: Text(suggestion.fromProduct.name),
      subtitle: Text('${suggestion.quantity} Stück → $toSite · '
          'Zuordnung: ${_matchLabel(suggestion.matchedBy)}'),
      trailing: TextButton(
        onPressed: onApply,
        child: const Text('Umlagern'),
      ),
    );
  }

  String _matchLabel(String matchedBy) => switch (matchedBy) {
        'barcode' => 'Barcode (sicher)',
        'externalPosId' => 'Kassen-Nr.',
        _ => 'Name (prüfen)',
      };
}

class _ReorderTile extends StatelessWidget {
  const _ReorderTile({
    required this.suggestion,
    required this.products,
    this.onApply,
  });

  final ReorderSuggestion suggestion;
  final Map<String, Product> products;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final name = products[suggestion.productId]?.name ?? suggestion.productId;
    final parts = <String>[];
    if (suggestion.minStockChanged) {
      parts.add('Melde ${suggestion.currentMinStock}→'
          '${suggestion.suggestedMinStock}');
    }
    if (suggestion.targetStockChanged) {
      parts.add('Ziel ${suggestion.currentTargetStock}→'
          '${suggestion.suggestedTargetStock}');
    }
    if (!suggestion.isReliable) {
      parts.add('Richtwert (<4 Wo.)');
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.tune, color: Theme.of(context).appColors.info),
      title: Text(name),
      subtitle: Text(parts.join(' · ')),
      trailing: TextButton(
        onPressed: onApply,
        child: const Text('Übernehmen'),
      ),
    );
  }
}
