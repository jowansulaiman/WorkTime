import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/money.dart';
import '../core/store_health.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../theme/theme_extensions.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_card.dart';

/// **Tages-Gesundheits-Check / Multi-Store-Benchmark (P2.3).** Admin-Auswertung:
/// vergleicht je Laden die heutige **Beleg-Anzahl** mit dem Wochentag-Schnitt
/// (und die Läden untereinander) — der Chef sieht früh, wenn ein Laden
/// schwächelt. Basis = anonyme Beleg-Zählung. (Push-Alarm separat, Infra.)
class StoreHealthScreen extends StatefulWidget {
  const StoreHealthScreen({super.key, this.parentLabel = 'Warenwirtschaft'});

  final String parentLabel;

  @override
  State<StoreHealthScreen> createState() => _StoreHealthScreenState();
}

class _StoreHealthScreenState extends State<StoreHealthScreen> {
  bool _loading = false;
  String? _error;
  StoreBenchmark? _benchmark;
  bool _started = false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final benchmark =
          await context.read<InventoryProvider>().loadStoreBenchmark();
      if (!mounted) return;
      setState(() {
        _benchmark = benchmark;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Benchmark konnte nicht geladen werden.';
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
      const BreadcrumbItem(label: 'Laden-Benchmark'),
    ];
    if (profile == null || !profile.isAdmin) {
      return Scaffold(
        appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
        body: const Center(child: Text('Nur für Administratoren.')),
      );
    }

    final inventory = context.watch<InventoryProvider>();
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    final siteNames = <String, String>{
      for (final p in inventory.products) p.siteId: p.siteName ?? p.siteId,
    };

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: breadcrumbs,
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(top: false, child: _buildBody(context, siteNames)),
    );
  }

  Widget _buildBody(BuildContext context, Map<String, String> siteNames) {
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Fehlgeschlagen',
        message: _error!,
        action: FilledButton.tonal(
            onPressed: _load, child: const Text('Erneut versuchen')),
      );
    }
    final benchmark = _benchmark;
    if (_loading && benchmark == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (benchmark == null || benchmark.perSite.isEmpty) {
      return const EmptyState(
        icon: Icons.insights_outlined,
        title: 'Noch kein Kassenabgleich',
        message: 'Sobald Belege vorliegen, erscheint hier der Tagesvergleich.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Stichtag ${benchmark.evaluatedDay} · heutige Belege vs. '
            'Wochentag-Schnitt (anonym).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          for (final h in benchmark.perSite) ...[
            _StoreCard(health: h, name: siteNames[h.siteId] ?? h.siteId),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.health, required this.name});

  final StoreHealth health;
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delta = health.deltaPercent;
    final isDip = health.isDip();
    final (icon, color, label) = switch (delta) {
      null => (Icons.remove, theme.colorScheme.onSurfaceVariant, 'keine Basis'),
      _ when delta <= -25 => (
          Icons.south_east,
          theme.appColors.warning,
          '${delta.toStringAsFixed(0)} %'
        ),
      _ when delta >= 10 => (
          Icons.north_east,
          theme.appColors.success,
          '+${delta.toStringAsFixed(0)} %'
        ),
      _ => (
          Icons.trending_flat,
          theme.colorScheme.onSurfaceVariant,
          '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(0)} %'
        ),
    };

    return SectionCard(
      title: name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${health.receiptsToday}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              const SizedBox(width: 8),
              Text('Belege heute', style: theme.textTheme.bodyMedium),
              const Spacer(),
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            health.weekdayAverage == null
                ? 'Wochentag-Schnitt: noch zu wenige Vergleichstage'
                : 'Wochentag-Schnitt: ${health.weekdayAverage!.toStringAsFixed(1)} '
                    'Belege (${health.weekdaySampleCount} Tage)'
                    '${health.revenueTodayCents > 0 ? ' · Umsatz heute ${Money.formatCents(health.revenueTodayCents)}' : ''}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (isDip)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: theme.appColors.warning),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('Deutlich unter dem Schnitt — prüfen.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.appColors.warning)),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}
