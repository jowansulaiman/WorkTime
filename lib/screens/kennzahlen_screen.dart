import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/money.dart';
import '../providers/management_dashboard_provider.dart';
import '../ui/ui.dart';

/// **REPORTING-4 — Management-Dashboard `/kennzahlen`.** Zeigt die für den
/// Nutzer sichtbaren Kennzahlen (Katalog-gesteuert über
/// [ManagementDashboardProvider.visibleKpis]) für einen Monat. Route-Gate
/// `isAdmin || canManageShifts` (siehe RoutePermissions).
class KennzahlenScreen extends StatefulWidget {
  const KennzahlenScreen({super.key, this.parentLabel = 'Übersicht'});

  final String parentLabel;

  @override
  State<KennzahlenScreen> createState() => _KennzahlenScreenState();
}

class _KennzahlenScreenState extends State<KennzahlenScreen> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    // Default: abgeschlossener Vormonat (wie der Lohnlauf).
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 1);
    _year = start.year;
    _month = start.month;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  void _reload() {
    context.read<ManagementDashboardProvider>().load(
          year: _year,
          month: _month,
        );
  }

  void _changeMonth(int delta) {
    final next = DateTime(_year, _month + delta);
    setState(() {
      _year = next.year;
      _month = next.month;
    });
    _reload();
  }

  static const _monthNames = [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
  ];

  String _hhmm(int minutes) {
    final neg = minutes < 0;
    final m = minutes.abs();
    final h = m ~/ 60;
    final rest = m % 60;
    return '${neg ? '−' : ''}$h:${rest.toString().padLeft(2, '0')} h';
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<ManagementDashboardProvider>();
    final spacing = context.spacing;
    final orgZeit = dashboard.orgZeit;

    final tiles = <Widget>[];
    if (orgZeit != null) {
      tiles.add(_KpiTile(
        label: 'Sollzeit (Org)',
        value: _hhmm(orgZeit.sollMinutes),
        icon: Icons.schedule_outlined,
      ));
      tiles.add(_KpiTile(
        label: 'Istzeit (approved)',
        value: _hhmm(orgZeit.istMinutes),
        icon: Icons.timer_outlined,
      ));
      tiles.add(_KpiTile(
        label: 'Saldo',
        value: _hhmm(orgZeit.saldoMinutes),
        icon: Icons.account_balance_outlined,
        tone: orgZeit.saldoMinutes < 0
            ? AppStatusTone.warning
            : AppStatusTone.success,
      ));
      tiles.add(_KpiTile(
        label: 'Offene Freigaben',
        value: '${orgZeit.offeneFreigaben}',
        icon: Icons.fact_check_outlined,
        tone: orgZeit.offeneFreigaben > 0
            ? AppStatusTone.warning
            : AppStatusTone.neutral,
      ));
    }
    if (dashboard.offeneAbwesenheiten != null) {
      tiles.add(_KpiTile(
        label: 'Offene Abwesenheiten',
        value: '${dashboard.offeneAbwesenheiten}',
        icon: Icons.event_busy_outlined,
        tone: (dashboard.offeneAbwesenheiten ?? 0) > 0
            ? AppStatusTone.warning
            : AppStatusTone.neutral,
      ));
    }
    if (dashboard.bestandswertEkCents != null) {
      tiles.add(_KpiTile(
        label: 'Bestandswert (EK)',
        value: Money.formatCents(dashboard.bestandswertEkCents),
        icon: Icons.inventory_2_outlined,
      ));
    }
    if (dashboard.bestandswertVkCents != null) {
      tiles.add(_KpiTile(
        label: 'Bestandswert (VK)',
        value: Money.formatCents(dashboard.bestandswertVkCents),
        icon: Icons.sell_outlined,
      ));
    }

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: widget.parentLabel,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const BreadcrumbItem(label: 'Kennzahlen'),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: EdgeInsets.all(spacing.md),
              children: [
                _MonthRow(
                  label: '${_monthNames[_month - 1]} $_year',
                  onPrevious: () => _changeMonth(-1),
                  onNext: () => _changeMonth(1),
                ),
                SizedBox(height: spacing.md),
                if (dashboard.isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (dashboard.error != null)
                  AppStatusBanner(
                    icon: Icons.error_outline,
                    tone: AppStatusTone.error,
                    message: dashboard.error!,
                  )
                else if (tiles.isEmpty)
                  const AppEmptyState(
                    icon: Icons.insights_outlined,
                    message: 'Für deine Berechtigung sind derzeit keine '
                        'Kennzahlen sichtbar.',
                  )
                else
                  Wrap(
                    spacing: spacing.md,
                    runSpacing: spacing.md,
                    children: [
                      for (final t in tiles)
                        SizedBox(width: 220, child: t),
                    ],
                  ),
                SizedBox(height: spacing.md),
                Text(
                  'Bindende Istzeit zählt nur freigegebene Zeiteinträge; '
                  'Kennzahlen richten sich nach deiner Berechtigung.',
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

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.icon,
    this.tone = AppStatusTone.neutral,
  });

  final String label;
  final String value;
  final IconData icon;
  final AppStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final accent = switch (tone) {
      AppStatusTone.warning => appColors.warning,
      AppStatusTone.success => appColors.success,
      AppStatusTone.error => theme.colorScheme.error,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: accent),
            const SizedBox(height: 8),
            Text(value,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _MonthRow extends StatelessWidget {
  const _MonthRow({
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Vormonat',
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Folgemonat',
        ),
      ],
    );
  }
}
