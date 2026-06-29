import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/order_frequency.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/team_provider.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/empty_state.dart';

/// Auswertung der Bestellhäufigkeit: wie oft welcher Artikel bestellt wird,
/// als Balkendiagramm pro Woche / pro Monat plus eine Rangliste der
/// meistbestellten Artikel (rollierend, [InventoryProvider.orderFrequencyWindow]).
///
/// Eigener Hauptbereich-Screen (über die Shell gepusht, `AppRoutes.orderAnalytics`),
/// Berechtigung wie die Warenwirtschaft (`canViewInventory`). Liest rein aus der
/// bereits gestreamten Bestellhistorie — kein Repo-Zugriff, kein Index.
class OrderAnalyticsScreen extends StatefulWidget {
  const OrderAnalyticsScreen({super.key, this.parentLabel = 'Laden'});

  final String parentLabel;

  @override
  State<OrderAnalyticsScreen> createState() => _OrderAnalyticsScreenState();
}

class _OrderAnalyticsScreenState extends State<OrderAnalyticsScreen> {
  FrequencyGranularity _granularity = FrequencyGranularity.week;
  String? _siteId; // null = alle Läden
  String? _selectedProductId; // null = alle Artikel (Gesamtzahl der Bestellungen)

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final team = context.watch<TeamProvider>();
    final profile = context.watch<AuthProvider>().profile;
    final sites = team.sites;

    final appBar = BreadcrumbAppBar(
      breadcrumbs: [
        BreadcrumbItem(
          label: widget.parentLabel,
          onTap: () => Navigator.of(context).pop(),
        ),
        const BreadcrumbItem(label: 'Bestell-Auswertung'),
      ],
    );

    if (!(profile?.canViewInventory ?? false)) {
      return Scaffold(
        appBar: appBar,
        body: const SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Die Bestell-Auswertung ist für dieses Profil deaktiviert.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    // Bei genau einem Laden ist der Laden eindeutig, auch ohne aktiven Filter.
    final effectiveSiteId =
        _siteId ?? (sites.length == 1 ? sites.first.id : null);

    final now = DateTime.now();
    final bucketCount = _granularity == FrequencyGranularity.week ? 12 : 6;
    final buckets = buildOrderFrequencyBuckets(
      orders: inventory.purchaseOrders,
      granularity: _granularity,
      now: now,
      bucketCount: bucketCount,
      siteId: effectiveSiteId,
      productId: _selectedProductId,
    );

    final freq = inventory.orderFrequencyByProduct(siteId: effectiveSiteId);
    final ranking = freq.entries
        .map((entry) =>
            (product: inventory.productById(entry.key), count: entry.value))
        .where((row) => row.product != null)
        .toList()
      ..sort((a, b) {
        if (a.count != b.count) {
          return b.count.compareTo(a.count);
        }
        return a.product!.name
            .toLowerCase()
            .compareTo(b.product!.name.toLowerCase());
      });
    final topRanking = ranking.length > 15 ? ranking.sublist(0, 15) : ranking;
    final maxCount = topRanking.isEmpty ? 0 : topRanking.first.count;

    final selectedProduct =
        _selectedProductId == null ? null : inventory.productById(_selectedProductId);
    // Falls der gewählte Artikel den Laden nicht (mehr) führt, Filter lösen.
    if (_selectedProductId != null && selectedProduct == null) {
      // Stiller Reset im nächsten Frame – build bleibt rein.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedProductId = null);
      });
    }

    final totalOrders = buckets.fold<int>(0, (sum, b) => sum + b.orderCount);
    final monthFormat = DateFormat('MMM', 'de_DE');
    final labels = [
      for (final bucket in buckets)
        _granularity == FrequencyGranularity.week
            ? 'KW${isoWeekNumber(bucket.start)}'
            : monthFormat.format(bucket.start),
    ];
    final values = [for (final bucket in buckets) bucket.orderCount.toDouble()];

    final chartTitle = selectedProduct == null
        ? 'Bestellungen pro ${_granularity.label}'
        : '${selectedProduct.name}: Bestellungen pro ${_granularity.label}';

    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const _Header(
                  title: 'Bestell-Auswertung',
                  subtitle:
                      'Wie oft welcher Artikel bestellt wird — pro Woche und pro Monat.',
                ),
                const SizedBox(height: 16),
                if (sites.length > 1) ...[
                  DropdownButtonFormField<String?>(
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
                      for (final site in sites)
                        DropdownMenuItem<String?>(
                          value: site.id,
                          child: Text(site.name),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _siteId = value;
                      _selectedProductId = null; // Artikel ist ladenabhängig
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                SegmentedButton<FrequencyGranularity>(
                  segments: const [
                    ButtonSegment(
                      value: FrequencyGranularity.week,
                      label: Text('Woche'),
                      icon: Icon(Icons.view_week_outlined),
                    ),
                    ButtonSegment(
                      value: FrequencyGranularity.month,
                      label: Text('Monat'),
                      icon: Icon(Icons.calendar_month_outlined),
                    ),
                  ],
                  selected: {_granularity},
                  onSelectionChanged: (selection) =>
                      setState(() => _granularity = selection.first),
                ),
                const SizedBox(height: 16),
                if (selectedProduct != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      avatar: const Icon(Icons.filter_alt_outlined, size: 18),
                      label: Text('Nur: ${selectedProduct.name}'),
                      onDeleted: () =>
                          setState(() => _selectedProductId = null),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _SectionCard(
                  title: chartTitle,
                  trailing: '$totalOrders Bestellungen',
                  child: _FrequencyBarChart(labels: labels, values: values),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Häufig bestellte Artikel (rollierend ~12 Wochen)',
                  child: topRanking.isEmpty
                      ? const EmptyState(
                          icon: Icons.bar_chart_outlined,
                          message: 'Noch keine Bestellungen im Zeitraum.',
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < topRanking.length; i++)
                              _RankingRow(
                                rank: i + 1,
                                product: topRanking[i].product!,
                                count: topRanking[i].count,
                                maxCount: maxCount,
                                selected: topRanking[i].product!.id ==
                                    _selectedProductId,
                                onTap: () => setState(() {
                                  final id = topRanking[i].product!.id;
                                  _selectedProductId =
                                      _selectedProductId == id ? null : id;
                                }),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tipp: Einen Artikel antippen, um nur dessen Bestellverlauf im '
                  'Diagramm zu sehen.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.rank,
    required this.product,
    required this.count,
    required this.maxCount,
    required this.selected,
    required this.onTap,
  });

  final int rank;
  final Product product;
  final int count;
  final int maxCount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = maxCount <= 0 ? 0.0 : count / maxCount;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.secondaryContainer : null,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 6,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$count×',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Balkendiagramm (fl_chart) der Bestellungen je Zeitfenster. Konfiguration
/// angelehnt an die Auswertungs-Charts in `statistics_screen`/`personal_screen`.
class _FrequencyBarChart extends StatelessWidget {
  const _FrequencyBarChart({required this.labels, required this.values});

  final List<String> labels;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (values.isEmpty || values.every((v) => v <= 0)) {
      return const EmptyState(
        icon: Icons.bar_chart_outlined,
        message: 'Keine Bestellungen im Zeitraum.',
      );
    }
    final maxV = values.fold<double>(0, (a, b) => a > b ? a : b);
    final ceiling = maxV <= 0 ? 1.0 : maxV * 1.25;
    final count = values.length;

    return SizedBox(
      height: 240,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: ceiling,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => colorScheme.inverseSurface,
              getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                '${labels[group.x]}\n${rod.toY.toStringAsFixed(0)} Bestellungen',
                TextStyle(
                  color: colorScheme.onInverseSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  // Bei vielen Balken nur jede zweite Beschriftung zeigen.
                  if (count > 8 && i.isOdd) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      labels[i],
                      style: theme.textTheme.labelSmall,
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(count, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i],
                  color: colorScheme.primary,
                  width: count > 8 ? 10 : 16,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
