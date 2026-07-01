import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/cashier_anomaly.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/team_provider.dart';
import '../theme/theme_extensions.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_card.dart';

/// **Kassierer-Prüfung — Storno-/Refund-Anomalie (P3.2).** Statistischer
/// Verdachtshinweis: auffällige Erstattungs-/Storno-Quoten je Kassierer ggü.
/// dem Standort-Schnitt (z-Wert), mit Mindest-Fallzahl.
///
/// **Sehr sensibel (Leistungskontrolle).** Der Screen führt mit einem
/// nicht-ausblendbaren Hinweis: **Verdacht aus Statistik, keine Schuld­
/// feststellung, keine automatische Sanktion; Einsatz erfordert Mitbestimmung
/// (BetrVG) & DSGVO-Klärung; Zweckbindung Verlustprävention.** Strikt admin-only.
class CashierAnomalyScreen extends StatefulWidget {
  const CashierAnomalyScreen({super.key, this.parentLabel = 'Personal'});

  final String parentLabel;

  @override
  State<CashierAnomalyScreen> createState() => _CashierAnomalyScreenState();
}

class _CashierAnomalyScreenState extends State<CashierAnomalyScreen> {
  String? _siteId;
  bool _loading = false;
  String? _error;
  CashierAnomalyReport? _report;
  bool _started = false;

  Future<void> _load(String siteId) async {
    setState(() {
      _siteId = siteId;
      _loading = true;
      _error = null;
    });
    try {
      final report = await context
          .read<InventoryProvider>()
          .loadCashierAnomalies(siteId: siteId, windowDays: 28);
      if (!mounted || siteId != _siteId) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || siteId != _siteId) return;
      setState(() {
        _error = 'Auswertung konnte nicht geladen werden.';
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
      const BreadcrumbItem(label: 'Kassierer-Prüfung'),
    ];
    if (profile == null || !profile.isAdmin) {
      return Scaffold(
        appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
        body: const Center(child: Text('Nur für Administratoren.')),
      );
    }

    final inventory = context.watch<InventoryProvider>();
    final sites = <String, String>{
      for (final p in inventory.products) p.siteId: p.siteName ?? p.siteId,
    };
    final siteList = sites.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    if (_siteId == null && siteList.isNotEmpty) _siteId = siteList.first.key;
    if (!_started && _siteId != null) {
      _started = true;
      final siteId = _siteId!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(siteId);
      });
    }

    final names = <String, String>{
      for (final m in context.watch<TeamProvider>().members) m.uid: m.displayName,
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
            const _Disclaimer(),
            if (siteList.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DropdownButton<String>(
                    value: _siteId,
                    onChanged: (v) {
                      if (v != null) _load(v);
                    },
                    items: [
                      for (final s in siteList)
                        DropdownMenuItem(value: s.key, child: Text(s.value)),
                    ],
                  ),
                ),
              ),
            Expanded(child: _buildBody(context, names, siteList.isEmpty)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, Map<String, String> names, bool noSites) {
    if (noSites) {
      return const EmptyState(
          icon: Icons.store_outlined,
          title: 'Keine Standorte',
          message: 'Lege zuerst Standorte/Artikel an.');
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Fehlgeschlagen',
        message: _error!,
        action: FilledButton.tonal(
            onPressed: _siteId == null ? null : () => _load(_siteId!),
            child: const Text('Erneut versuchen')),
      );
    }
    final report = _report;
    if (_loading && report == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (report == null || report.stats.isEmpty) {
      return const EmptyState(
        icon: Icons.fact_check_outlined,
        title: 'Keine belastbare Datenbasis',
        message: 'Es gibt noch zu wenige Kassen-Vorgänge je Kassierer '
            '(Mindest-Fallzahl) für einen Vergleich.',
      );
    }

    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Standort-Schnitt Erstattungsquote: '
          '${(report.siteRefundRateMean * 100).toStringAsFixed(1)} % · '
          'Mindest-Fallzahl ${report.minTransactions} Vorgänge · '
          'Schwelle z ≥ ${report.zThreshold.toStringAsFixed(1)}.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Kassierer (${report.stats.length} bewertet · '
              '${report.flagged.length} auffällig)',
          child: Column(
            children: [
              for (final s in report.stats)
                _CashierTile(stat: s, name: names[s.cashierId]),
            ],
          ),
        ),
      ],
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.appColors.warningContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.gavel_outlined,
              size: 18, color: theme.appColors.onWarningContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Statistischer Verdachtshinweis — keine Schuldfeststellung und '
              'keine automatische Sanktion. Zweckbindung: Verlustprävention. '
              'Einsatz erfordert Mitbestimmung (BetrVG) und DSGVO-Klärung; '
              'Auffälligkeiten immer persönlich prüfen.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.appColors.onWarningContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _CashierTile extends StatelessWidget {
  const _CashierTile({required this.stat, required this.name});

  final CashierStat stat;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = name ?? 'Kassier-ID ${stat.cashierId}';
    final z = stat.zScore;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        stat.isFlagged ? Icons.warning_amber_rounded : Icons.person_outline,
        color: stat.isFlagged
            ? theme.appColors.warning
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(label),
      subtitle: Text(
        '${(stat.refundRate * 100).toStringAsFixed(1)} % Erstattungen '
        '(${stat.refundTransactions}/${stat.totalTransactions})'
        '${z == null ? '' : ' · z ${z.toStringAsFixed(1)}'}',
      ),
      trailing: stat.isFlagged
          ? Text('prüfen',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.appColors.warning))
          : null,
    );
  }
}
