import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/money.dart';
import '../core/site_comparison.dart';
import '../providers/feature_flag_provider.dart';
import '../providers/management_dashboard_provider.dart';
import '../ui/ui.dart';

/// **REPORTING-6 — Standortvergleich `/standortvergleich`.** Zeigt die
/// Standort-Kennzahlen eines Monats nebeneinander (Ranking, Umsatz/Rohertrag/
/// Belege/Personalstunden/Bestandswert + Lohn-Richtwert). Route-Gate im ersten
/// Schnitt **admin-only** (der teamlead-Pfad kollidiert mit REPORTING-7 — dort
/// liest `loadKassenbericht` posDailyStats direkt).
class StandortvergleichScreen extends StatefulWidget {
  const StandortvergleichScreen({super.key, this.parentLabel = 'Übersicht'});

  final String parentLabel;

  @override
  State<StandortvergleichScreen> createState() =>
      _StandortvergleichScreenState();
}

class _StandortvergleichScreenState extends State<StandortvergleichScreen> {
  late int _year;
  late int _month;

  static const _monthNames = [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 1);
    _year = start.year;
    _month = start.month;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  void _reload() {
    context.read<ManagementDashboardProvider>().loadSiteVergleich(
          year: _year,
          month: _month,
          purchasePricesIncludeVat:
              context.read<FeatureFlagProvider>().purchasePricesIncludeVat,
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

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<ManagementDashboardProvider>();
    final vergleich = dashboard.siteVergleich;
    final spacing = context.spacing;
    final wide = MobileBreakpoints.useNavigationRail(
        MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: widget.parentLabel,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const BreadcrumbItem(label: 'Standortvergleich'),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: EdgeInsets.all(spacing.md),
              children: [
                _MonthRow(
                  label: '${_monthNames[_month - 1]} $_year',
                  onPrevious: () => _changeMonth(-1),
                  onNext: () => _changeMonth(1),
                ),
                SizedBox(height: spacing.md),
                if (dashboard.isSiteVergleichLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (dashboard.siteVergleichError != null)
                  AppStatusBanner(
                    icon: Icons.error_outline,
                    tone: AppStatusTone.error,
                    message: dashboard.siteVergleichError!,
                  )
                else if (vergleich == null || vergleich.sites.isEmpty)
                  const AppEmptyState(
                    icon: Icons.compare_arrows_outlined,
                    message: 'Keine Standortdaten für diesen Monat.',
                  )
                else ...[
                  Wrap(
                    spacing: spacing.md,
                    runSpacing: spacing.md,
                    children: [
                      for (final s in vergleich.sites)
                        SizedBox(
                          width: wide ? 340 : double.infinity,
                          child: _SiteCard(kennzahl: s),
                        ),
                    ],
                  ),
                  SizedBox(height: spacing.md),
                  if (vergleich.hatLohnAllokation)
                    const AppStatusBanner(
                      icon: Icons.info_outline,
                      tone: AppStatusTone.info,
                      message: 'Lohnkosten sind ein Richtwert (Verteilung der '
                          'finalisierten Lohnkosten nach geleisteten Stunden je '
                          'Standort) — keine standortgenaue Buchung.',
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SiteCard extends StatelessWidget {
  const _SiteCard({required this.kennzahl});

  final SiteKennzahlen kennzahl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final k = kennzahl;
    final delta = k.umsatzDeltaZuFuehrendemPct;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: k.rang == 1
                      ? appColors.success.withValues(alpha: 0.18)
                      : theme.colorScheme.surfaceContainerHighest,
                  child: Text('${k.rang}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: k.rang == 1
                            ? appColors.success
                            : theme.colorScheme.onSurfaceVariant,
                      )),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    k.siteName ?? (k.hatStandort ? 'Standort' : 'Ohne Standort'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (delta != null && delta < 0)
                  Text('${delta.toStringAsFixed(0)} %',
                      style: TextStyle(
                          color: appColors.warning,
                          fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            _row(context, 'Umsatz (brutto)',
                Money.formatCents(k.umsatzBruttoCents)),
            if (k.rohertragNettoCents != null)
              _row(context, 'Rohertrag (netto)',
                  Money.formatCents(k.rohertragNettoCents)),
            _row(context, 'Belege', '${k.belege}'),
            _row(context, 'Personalstunden',
                '${k.personalStunden.toStringAsFixed(1)} h'),
            if (k.bestandswertEkCents != null)
              _row(context, 'Bestandswert (EK)',
                  Money.formatCents(k.bestandswertEkCents)),
            if (k.lohnkostenRichtwertCents != null)
              _row(context, 'Lohn (Richtwert)',
                  Money.formatCents(k.lohnkostenRichtwertCents)),
            if (k.umsatzAnteilPct != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (k.umsatzAnteilPct! / 100).clamp(0.0, 1.0),
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
              const SizedBox(height: 2),
              Text('${k.umsatzAnteilPct!.toStringAsFixed(0)} % des Org-Umsatzes',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _MonthRow extends StatelessWidget {
  const _MonthRow(
      {required this.label, required this.onPrevious, required this.onNext});

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
            tooltip: 'Vormonat'),
        Expanded(
          child: Text(label,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ),
        IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Folgemonat'),
      ],
    );
  }
}
