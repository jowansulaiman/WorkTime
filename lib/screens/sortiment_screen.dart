import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/assortment_analysis.dart';
import '../core/basket_analysis.dart';
import '../core/money.dart';
import '../core/sales_velocity.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../theme/theme_extensions.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_card.dart';

/// **Sortimentsanalyse (P2.1).** Admin-Auswertung je Standort: Rohertrag &
/// ABC-Klassen nach **Deckungsbeitrag** (nicht Umsatz). Lädt die Kassenbelege
/// (`posReceipts`) über `InventoryProvider.loadAssortmentAnalysis`. Lokaler
/// Lade-State (ephemer, eigener Screen). Enthält EK/Marge -> admin-only.
class SortimentScreen extends StatefulWidget {
  const SortimentScreen({super.key, this.parentLabel = 'Warenwirtschaft'});

  final String parentLabel;

  @override
  State<SortimentScreen> createState() => _SortimentScreenState();
}

class _SortimentScreenState extends State<SortimentScreen> {
  String? _siteId;
  bool _loading = false;
  String? _error;
  AssortmentAnalysis? _analysis;
  BasketAnalysis? _basket;
  bool _started = false;
  static const int _windowDays = SalesVelocity.defaultReliableDays;

  Future<void> _load(String siteId) async {
    setState(() {
      _siteId = siteId;
      _loading = true;
      _error = null;
    });
    try {
      final inventory = context.read<InventoryProvider>();
      final analysis =
          await inventory.loadAssortmentAnalysis(siteId: siteId, windowDays: _windowDays);
      final basket =
          await inventory.loadBasketAnalysis(siteId: siteId, windowDays: _windowDays);
      if (!mounted || siteId != _siteId) return;
      setState(() {
        _analysis = analysis;
        _basket = basket;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || siteId != _siteId) return;
      setState(() {
        _error = 'Sortimentsanalyse konnte nicht geladen werden.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final breadcrumbs = [
      BreadcrumbItem(
        label: widget.parentLabel,
        onTap: () => Navigator.of(context).maybePop(),
      ),
      const BreadcrumbItem(label: 'Sortimentsanalyse'),
    ];

    if (profile == null || !profile.isAdmin) {
      return Scaffold(
        appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
        body: const Center(child: Text('Nur für Administratoren.')),
      );
    }

    final inventory = context.watch<InventoryProvider>();
    final sites = _sitesFrom(inventory.products);
    if (_siteId == null && sites.isNotEmpty) {
      _siteId = sites.first.id;
    }
    if (!_started && _siteId != null) {
      _started = true;
      final siteId = _siteId!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(siteId);
      });
    }

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
            if (sites.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DropdownButton<String>(
                    value: _siteId,
                    onChanged: (value) {
                      if (value != null) _load(value);
                    },
                    items: [
                      for (final s in sites)
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                  ),
                ),
              ),
            Expanded(child: _buildBody(context, sites)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<_SiteRef> sites) {
    if (sites.isEmpty) {
      return const EmptyState(
        icon: Icons.warehouse_outlined,
        title: 'Keine Artikel',
        message: 'Sobald Kassenbelege vorliegen, erscheint hier die '
            'Sortimentsanalyse nach Rohertrag.',
      );
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Analyse fehlgeschlagen',
        message: _error!,
        action: FilledButton.tonal(
          onPressed: _siteId == null ? null : () => _load(_siteId!),
          child: const Text('Erneut versuchen'),
        ),
      );
    }
    final analysis = _analysis;
    if (_loading && analysis == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (analysis == null || analysis.items.isEmpty) {
      return const EmptyState(
        icon: Icons.point_of_sale_outlined,
        title: 'Noch kein Kassenabgleich',
        message: 'Für diesen Zeitraum liegen keine Verkaufsfakten vor.',
      );
    }

    final theme = Theme.of(context);
    final categories = analysis.contributionByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return RefreshIndicator(
      onRefresh: () async {
        if (_siteId != null) await _load(_siteId!);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Datenbasis: letzte $_windowDays Tage · Ranking nach Rohertrag '
            '(Deckungsbeitrag), nicht Umsatz.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatCard(
                icon: Icons.savings_outlined,
                label: 'Rohertrag',
                value: Money.formatCents(analysis.totalContributionCents),
                color: theme.appColors.success,
              ),
              _StatCard(
                icon: Icons.receipt_long_outlined,
                label: 'Umsatz',
                value: Money.formatCents(analysis.totalRevenueCents),
                color: theme.appColors.info,
              ),
              if (analysis.unvaluatedCount > 0)
                _StatCard(
                  icon: Icons.help_outline,
                  label: 'Unbewertet',
                  value: '${analysis.unvaluatedCount}',
                  color: theme.appColors.warning,
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (categories.isNotEmpty)
            SectionCard(
              title: 'Rohertrag je Warengruppe',
              child: Column(
                children: [
                  for (final e in categories)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(e.key)),
                          Text(
                            Money.formatCents(e.value),
                            style: const TextStyle(
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Artikel nach Rohertrag (${analysis.items.length})',
            child: Column(
              children: [
                for (final item in analysis.items.take(100))
                  _AssortmentTile(item),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Häufig zusammen gekauft '
                '(${_basket?.pairs.length ?? 0})',
            child: (_basket == null || _basket!.pairs.isEmpty)
                ? const Text('Noch keine wiederkehrenden Kombinationen.')
                : Column(
                    children: [
                      for (final pair in _basket!.pairs.take(20))
                        _BasketTile(pair),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  List<_SiteRef> _sitesFrom(List<Product> products) {
    final byId = <String, String>{};
    for (final p in products) {
      byId.putIfAbsent(p.siteId, () => p.siteName ?? p.siteId);
    }
    return byId.entries.map((e) => _SiteRef(e.key, e.value)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}

class _SiteRef {
  const _SiteRef(this.id, this.name);
  final String id;
  final String name;
}

class _AssortmentTile extends StatelessWidget {
  const _AssortmentTile(this.item);

  final AssortmentItem item;

  @override
  Widget build(BuildContext context) {
    final contribution = item.isValuated
        ? Money.formatCents(item.contributionCents)
        : 'unbewertet';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _AbcBadge(item.abcClass),
      title: Text(item.name ?? item.productId),
      subtitle: Text(
        '${item.quantitySold}× · Umsatz ${Money.formatCents(item.revenueCents)} '
        '· Rohertrag $contribution',
      ),
    );
  }
}

class _BasketTile extends StatelessWidget {
  const _BasketTile(this.pair);

  final ProductPair pair;

  @override
  Widget build(BuildContext context) {
    final a = pair.nameA ?? pair.productIdA;
    final b = pair.nameB ?? pair.productIdB;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.link, color: Theme.of(context).appColors.info),
      title: Text('$a + $b'),
      subtitle: Text('${pair.together}× zusammen · Lift '
          '${pair.lift.toStringAsFixed(1)}'),
    );
  }
}

class _AbcBadge extends StatelessWidget {
  const _AbcBadge(this.abcClass);

  final String abcClass;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (abcClass) {
      'A' => (colors.successContainer, colors.onSuccessContainer),
      'B' => (colors.infoContainer, colors.onInfoContainer),
      'C' => (colors.warningContainer, colors.onWarningContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        abcClass,
        style: TextStyle(color: fg, fontWeight: FontWeight.bold),
      ),
    );
  }
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
