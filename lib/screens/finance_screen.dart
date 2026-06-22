import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/finance_analytics.dart';
import '../core/money.dart';
import '../models/finance_models.dart';
import '../providers/finance_provider.dart';
import '../services/export_service.dart';
import '../ui/ui.dart';

/// Finanzbereich / Buchhaltung (nur Admin): Kosten-Allokationsmodell mit
/// Kostenstellen, Kostenarten, Buchungsjournal und Plan-Budgets — plus
/// DATEV-/CSV-/PDF-Export. Reines V2-Design. Wird per Router-Sektion geöffnet.
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key, this.parentLabel = 'Laden'});

  final String parentLabel;

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = DateTime.now().year;
  }

  void _shiftYear(int delta) => setState(() => _year += delta);

  Future<void> _export(
    BuildContext context,
    FinanceProvider finance,
    String kind,
  ) async {
    final centersById = {
      for (final c in finance.costCenters)
        if (c.id != null) c.id!: c,
    };
    final typesById = {
      for (final t in finance.costTypes)
        if (t.id != null) t.id!: t,
    };
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (kind == 'datev') {
        await ExportService.exportDatevBuchungsstapel(
          entries: finance.journalEntries,
          centersById: centersById,
          typesById: typesById,
          year: _year,
        );
        messenger.showSnackBar(
          const SnackBar(
            content: Text('DATEV-Stapel erstellt — vor der Übergabe an den '
                'Steuerberater fachlich prüfen.'),
          ),
        );
      } else {
        await ExportService.exportFinanceJournalCsv(
          entries: finance.journalEntries,
          centersById: centersById,
          typesById: typesById,
          year: _year,
        );
      }
    } catch (error) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Export fehlgeschlagen.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final finance = context.watch<FinanceProvider>();
    if (!finance.isAdmin) {
      return Scaffold(
        appBar: BreadcrumbAppBar(
          breadcrumbs: [
            BreadcrumbItem(
              label: widget.parentLabel,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const BreadcrumbItem(label: 'Buchhaltung'),
          ],
        ),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Kein Zugriff',
          message: 'Der Finanzbereich ist nur für Administratoren verfügbar.',
        ),
      );
    }

    final theme = Theme.of(context);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: BreadcrumbAppBar(
          breadcrumbs: [
            BreadcrumbItem(
              label: widget.parentLabel,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const BreadcrumbItem(label: 'Buchhaltung'),
          ],
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Exportieren',
              icon: const Icon(Icons.ios_share_outlined),
              onSelected: (value) => _export(context, finance, value),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'journal_csv',
                  child: Text('Buchungsjournal (CSV)'),
                ),
                PopupMenuItem(
                  value: 'datev',
                  child: Text('DATEV-Buchungsstapel (EXTF)'),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Material(
              color: theme.colorScheme.surface,
              child: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Übersicht'),
                  Tab(text: 'Journal'),
                  Tab(text: 'Stammdaten'),
                  Tab(text: 'Budgets'),
                ],
              ),
            ),
            _YearBar(year: _year, onShift: _shiftYear),
            Expanded(
              child: TabBarView(
                children: [
                  _OverviewTab(year: _year),
                  _JournalTab(year: _year),
                  const _MasterDataTab(),
                  _BudgetTab(year: _year),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YearBar extends StatelessWidget {
  const _YearBar({required this.year, required this.onShift});

  final int year;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.md,
          vertical: context.spacing.xs,
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Vorjahr',
              onPressed: () => onShift(-1),
            ),
            Expanded(
              child: Text(
                'Geschäftsjahr $year',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Folgejahr',
              onPressed: () => onShift(1),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Übersicht ──────────────────────────────────

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    final finance = context.watch<FinanceProvider>();
    final spacing = context.spacing;
    final appColors = Theme.of(context).appColors;

    final planned = finance.totalPlanned(year);
    final actual = finance.totalActual(year);
    final expenses = finance.totalExpenses(year);
    final credits = finance.totalCredits(year);
    final reports = finance.costCenterReports(year);
    final overBudget = reports.where((r) => r.isOverBudget).toList();

    if (finance.costCenters.isEmpty && finance.journalEntries.isEmpty) {
      return const EmptyState(
        icon: Icons.account_balance_outlined,
        title: 'Noch keine Finanzdaten',
        message: 'Legen Sie zuerst Kostenstellen und Kostenarten an, '
            'dann erfassen Sie Buchungen im Journal.',
      );
    }

    return ListView(
      padding: _pad(context),
      children: [
        Row(
          children: [
            Expanded(
              child: AppStatCard(
                label: 'Jahresbudget',
                value: _euro(planned),
                subtitle: 'Plan gesamt',
                icon: Icons.savings_outlined,
                color: appColors.info,
              ),
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: AppStatCard(
                label: 'Ist gebucht',
                value: _euro(actual),
                subtitle: actual < 0
                    ? 'Netto-Gutschrift'
                    : (planned > 0
                        ? '${(actual / planned * 100).round()} % vom Plan'
                        : 'Kosten − Gutschriften'),
                icon: Icons.receipt_long_outlined,
                color: actual < 0
                    ? appColors.info
                    : (planned > 0 && actual > planned
                        ? Theme.of(context).colorScheme.error
                        : appColors.success),
              ),
            ),
          ],
        ),
        SizedBox(height: spacing.sm),
        Row(
          children: [
            Expanded(
              child: AppStatCard(
                label: 'Kosten',
                value: _euro(expenses),
                subtitle: 'Ausgaben gesamt',
                icon: Icons.arrow_upward,
                color: appColors.warning,
              ),
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: AppStatCard(
                label: 'Gutschriften',
                value: _euro(credits),
                subtitle: 'Erstattungen',
                icon: Icons.arrow_downward,
                color: appColors.success,
              ),
            ),
          ],
        ),
        SizedBox(height: spacing.lg),
        if (overBudget.isNotEmpty) ...[
          AppStatusBanner(
            tone: AppStatusTone.error,
            icon: Icons.warning_amber_rounded,
            message: '${overBudget.length} '
                '${overBudget.length == 1 ? 'Kostenstelle überschreitet' : 'Kostenstellen überschreiten'}'
                ' das Budget.',
          ),
          SizedBox(height: spacing.lg),
        ],
        AppSectionCard(
          title: 'Plan / Ist je Kostenstelle',
          icon: Icons.donut_large_outlined,
          child: reports.isEmpty
              ? const _InlineEmpty(
                  icon: Icons.donut_large_outlined,
                  message: 'Keine Kostenstellen vorhanden.',
                )
              : Column(
                  children: [
                    for (final r in reports) ...[
                      _CostCenterReportRow(report: r),
                      SizedBox(height: spacing.sm),
                    ],
                  ],
                ),
        ),
        SizedBox(height: spacing.lg),
        _MonthlyBreakdownCard(buckets: finance.monthlyBreakdown(year)),
      ],
    );
  }
}

class _CostCenterReportRow extends StatelessWidget {
  const _CostCenterReportRow({required this.report});

  final CostCenterReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final utilization = report.utilization;
    final pct = (utilization * 100).clamp(0, 999).round();

    final Color tone;
    if (report.plannedCents <= 0) {
      tone = theme.colorScheme.onSurfaceVariant;
    } else if (utilization >= 1.0) {
      tone = theme.colorScheme.error;
    } else if (utilization >= 0.85) {
      tone = appColors.warning;
    } else {
      tone = appColors.success;
    }

    return AppCard(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${report.center.number} · ${report.center.name}',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (report.center.isBillable)
                Padding(
                  padding: EdgeInsets.only(right: context.spacing.xs),
                  child: Icon(Icons.euro, size: 16, color: appColors.info),
                ),
              if (report.plannedCents > 0)
                Text('$pct %',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: tone, fontWeight: FontWeight.w800)),
            ],
          ),
          SizedBox(height: context.spacing.xs),
          if (report.plannedCents > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: utilization.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: tone,
              ),
            ),
          SizedBox(height: context.spacing.xs),
          Text(
            'Ist ${_euro(report.actualCents)} € · '
            'Plan ${_euro(report.plannedCents)} € · '
            'Rest ${_euro(report.remainingCents)} € · '
            '${report.entryCount} Buchungen',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _MonthlyBreakdownCard extends StatelessWidget {
  const _MonthlyBreakdownCard({required this.buckets});

  final List<MonthBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final maxValue = buckets.fold<int>(
        1, (m, b) => b.expenseCents > m ? b.expenseCents : m);

    return AppSectionCard(
      title: 'Monatsverlauf',
      icon: Icons.bar_chart_outlined,
      child: Column(
        children: [
          for (final b in buckets)
            Padding(
              padding: EdgeInsets.symmetric(vertical: context.spacing.xxs),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      DateFormat('MMM', 'de_DE')
                          .format(DateTime(2000, b.month)),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (b.expenseCents / maxValue).clamp(0.0, 1.0),
                        minHeight: 10,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        color: appColors.warning,
                      ),
                    ),
                  ),
                  SizedBox(width: context.spacing.sm),
                  SizedBox(
                    width: 84,
                    child: Text(
                      '${_euro(b.netCents)} €',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Journal ────────────────────────────────────

class _JournalTab extends StatelessWidget {
  const _JournalTab({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    final finance = context.watch<FinanceProvider>();
    final spacing = context.spacing;
    final entries = finance.journalForYear(year);
    final canBook = finance.costCenters.isNotEmpty && finance.costTypes.isNotEmpty;

    return ListView(
      padding: _pad(context),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Buchungen $year',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            FilledButton.icon(
              onPressed: canBook
                  ? () => showAppBottomSheet(
                        context: context,
                        builder: (_) => _JournalEntryEditorSheet(year: year),
                      )
                  : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Buchung'),
            ),
          ],
        ),
        SizedBox(height: spacing.md),
        if (!canBook)
          const AppStatusBanner(
            tone: AppStatusTone.info,
            icon: Icons.info_outline,
            message: 'Legen Sie zuerst mindestens eine Kostenstelle und eine '
                'Kostenart unter „Stammdaten" an.',
          )
        else if (entries.isEmpty)
          const _InlineEmpty(
            icon: Icons.receipt_long_outlined,
            message: 'Noch keine Buchungen in diesem Jahr.',
          )
        else
          for (final entry in entries) ...[
            _JournalEntryTile(entry: entry, year: year),
            SizedBox(height: spacing.sm),
          ],
      ],
    );
  }
}

class _JournalEntryTile extends StatelessWidget {
  const _JournalEntryTile({required this.entry, required this.year});

  final JournalEntry entry;
  final int year;

  @override
  Widget build(BuildContext context) {
    final finance = context.read<FinanceProvider>();
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final center = finance.costCenterById(entry.costCenterId);
    final type = finance.costTypeById(entry.costTypeId);
    final color = entry.isCredit ? appColors.success : theme.colorScheme.onSurface;

    return AppCard(
      onTap: () => showAppBottomSheet(
        context: context,
        builder: (_) => _JournalEntryEditorSheet(year: year, existing: entry),
      ),
      child: Row(
        children: [
          Icon(
            entry.isCredit ? Icons.south_west : Icons.north_east,
            size: 18,
            color: entry.isCredit ? appColors.success : appColors.warning,
          ),
          SizedBox(width: context.spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.description,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: context.spacing.xxs),
                Text(
                  '${_formatDate(entry.date)} · ${center?.name ?? '—'}'
                  ' · ${type?.name ?? '—'}'
                  '${entry.reference != null ? ' · ${entry.reference}' : ''}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SizedBox(width: context.spacing.sm),
          Text(
            '${_euro(entry.amountCents)} €',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Stammdaten ─────────────────────────────────

class _MasterDataTab extends StatelessWidget {
  const _MasterDataTab();

  @override
  Widget build(BuildContext context) {
    final finance = context.watch<FinanceProvider>();
    final spacing = context.spacing;
    final centers = [...finance.costCenters]
      ..sort((a, b) => a.number.compareTo(b.number));
    final types = [...finance.costTypes]
      ..sort((a, b) => a.number.compareTo(b.number));

    return ListView(
      padding: _pad(context),
      children: [
        AppSectionCard(
          title: 'Kostenstellen',
          icon: Icons.store_outlined,
          trailing: FilledButton.tonalIcon(
            onPressed: () => showAppBottomSheet(
              context: context,
              builder: (_) => const _CostCenterEditorSheet(),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Neu'),
          ),
          child: centers.isEmpty
              ? const _InlineEmpty(
                  icon: Icons.store_outlined,
                  message: 'Noch keine Kostenstellen (z. B. je Laden).',
                )
              : Column(
                  children: [
                    for (final c in centers) ...[
                      _CostCenterTile(center: c),
                      SizedBox(height: spacing.sm),
                    ],
                  ],
                ),
        ),
        SizedBox(height: spacing.lg),
        AppSectionCard(
          title: 'Kostenarten',
          icon: Icons.category_outlined,
          trailing: FilledButton.tonalIcon(
            onPressed: () => showAppBottomSheet(
              context: context,
              builder: (_) => const _CostTypeEditorSheet(),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Neu'),
          ),
          child: types.isEmpty
              ? const _InlineEmpty(
                  icon: Icons.category_outlined,
                  message: 'Noch keine Kostenarten (z. B. Miete, Wareneinsatz).',
                )
              : Column(
                  children: [
                    for (final t in types) ...[
                      _CostTypeTile(type: t),
                      SizedBox(height: spacing.sm),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _CostCenterTile extends StatelessWidget {
  const _CostCenterTile({required this.center});

  final CostCenter center;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      color: theme.colorScheme.surfaceContainerLowest,
      onTap: () => showAppBottomSheet(
        context: context,
        builder: (_) => _CostCenterEditorSheet(existing: center),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${center.number} · ${center.name}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                if (center.annualBudgetCents > 0)
                  Text('Jahresbudget ${_euro(center.annualBudgetCents)} €',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (!center.isActive)
            const AppStatusBadge(
                label: 'inaktiv', tone: AppStatusTone.neutral, filled: true),
        ],
      ),
    );
  }
}

class _CostTypeTile extends StatelessWidget {
  const _CostTypeTile({required this.type});

  final CostType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      color: theme.colorScheme.surfaceContainerLowest,
      onTap: () => showAppBottomSheet(
        context: context,
        builder: (_) => _CostTypeEditorSheet(existing: type),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('${type.number} · ${type.name}',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          AppStatusBadge(
              label: type.group.label,
              tone: AppStatusTone.neutral,
              filled: true),
        ],
      ),
    );
  }
}

// ───────────────────────────── Budgets ────────────────────────────────────

class _BudgetTab extends StatelessWidget {
  const _BudgetTab({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    final finance = context.watch<FinanceProvider>();
    final spacing = context.spacing;
    final budgets = finance.budgets.where((b) => b.year == year).toList()
      ..sort((a, b) => a.costCenterId.compareTo(b.costCenterId));
    final canPlan = finance.costCenters.isNotEmpty;

    return ListView(
      padding: _pad(context),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Budgets $year',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            FilledButton.icon(
              onPressed: canPlan
                  ? () => showAppBottomSheet(
                        context: context,
                        builder: (_) => _BudgetEditorSheet(year: year),
                      )
                  : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Budget'),
            ),
          ],
        ),
        SizedBox(height: spacing.md),
        if (!canPlan)
          const AppStatusBanner(
            tone: AppStatusTone.info,
            icon: Icons.info_outline,
            message: 'Legen Sie zuerst Kostenstellen an.',
          )
        else if (budgets.isEmpty)
          const _InlineEmpty(
            icon: Icons.savings_outlined,
            message: 'Noch keine Budgets für dieses Jahr.',
          )
        else
          for (final b in budgets) ...[
            _BudgetTile(budget: b, year: year),
            SizedBox(height: spacing.sm),
          ],
      ],
    );
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({required this.budget, required this.year});

  final Budget budget;
  final int year;

  @override
  Widget build(BuildContext context) {
    final finance = context.read<FinanceProvider>();
    final theme = Theme.of(context);
    final center = finance.costCenterById(budget.costCenterId);
    final type =
        budget.costTypeId == null ? null : finance.costTypeById(budget.costTypeId!);

    return AppCard(
      color: theme.colorScheme.surfaceContainerLowest,
      onTap: () => showAppBottomSheet(
        context: context,
        builder: (_) => _BudgetEditorSheet(year: year, existing: budget),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${center?.name ?? '—'}'
              '${type != null ? ' · ${type.name}' : ' · Gesamt'}',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Text('${_euro(budget.plannedAmountCents)} €',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// ───────────────────────────── Helpers ────────────────────────────────────

EdgeInsets _pad(BuildContext context) {
  final p = MobileBreakpoints.screenPadding(context);
  return EdgeInsets.fromLTRB(p.left, context.spacing.md, p.right,
      context.spacing.xxl + context.spacing.lg);
}

final NumberFormat _numberFormat = NumberFormat('#,##0.00', 'de_DE');

/// Reiner de_DE-Betrag ohne Symbol (das UI hängt „ €" an).
String _euro(int cents) => _numberFormat.format(cents / 100);

String _formatDate(DateTime date) =>
    DateFormat('dd.MM.yyyy', 'de_DE').format(date);

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.md),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          SizedBox(width: context.spacing.sm),
          Expanded(
            child: Text(message,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

void _showError(BuildContext context, Object error) {
  final message = error is StateError ? error.message : 'Aktion fehlgeschlagen.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _centsToInput(int cents) =>
    (cents.abs() / 100).toStringAsFixed(2).replaceAll('.', ',');

final _amountFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
];

// ─────────────────────────── Editor-Sheets ────────────────────────────────

class _JournalEntryEditorSheet extends StatefulWidget {
  const _JournalEntryEditorSheet({required this.year, this.existing});

  final int year;
  final JournalEntry? existing;

  @override
  State<_JournalEntryEditorSheet> createState() =>
      _JournalEntryEditorSheetState();
}

class _JournalEntryEditorSheetState extends State<_JournalEntryEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late final TextEditingController _reference;
  String? _costCenterId;
  String? _costTypeId;
  late DateTime _date;
  bool _isCredit = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _description = TextEditingController(text: e?.description ?? '');
    _amount =
        TextEditingController(text: e == null ? '' : _centsToInput(e.amountCents));
    _reference = TextEditingController(text: e?.reference ?? '');
    _costCenterId = e?.costCenterId;
    _costTypeId = e?.costTypeId;
    _isCredit = e?.isCredit ?? false;
    final now = DateTime.now();
    _date = e?.date ??
        (now.year == widget.year ? now : DateTime(widget.year, 1, 1));
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final finance = context.read<FinanceProvider>();
    final spacing = context.spacing;
    final centers = [...finance.costCenters]
      ..sort((a, b) => a.number.compareTo(b.number));
    final types = [...finance.costTypes]
      ..sort((a, b) => a.number.compareTo(b.number));

    return AppBottomSheetScaffold(
      title: widget.existing == null ? 'Neue Buchung' : 'Buchung bearbeiten',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DateField(
              label: 'Buchungsdatum',
              value: _date,
              firstDate: DateTime(widget.year - 1),
              lastDate: DateTime(widget.year + 1, 12, 31),
              onChanged: (d) => setState(() => _date = d),
            ),
            SizedBox(height: spacing.md),
            DropdownButtonFormField<String>(
              initialValue: _costCenterId,
              decoration: const InputDecoration(labelText: 'Kostenstelle'),
              items: [
                for (final c in centers)
                  DropdownMenuItem(
                      value: c.id, child: Text('${c.number} · ${c.name}')),
              ],
              validator: (v) => v == null ? 'Bitte wählen' : null,
              onChanged: (v) => setState(() => _costCenterId = v),
            ),
            SizedBox(height: spacing.md),
            DropdownButtonFormField<String>(
              initialValue: _costTypeId,
              decoration: const InputDecoration(labelText: 'Kostenart'),
              items: [
                for (final t in types)
                  DropdownMenuItem(
                      value: t.id, child: Text('${t.number} · ${t.name}')),
              ],
              validator: (v) => v == null ? 'Bitte wählen' : null,
              onChanged: (v) => setState(() => _costTypeId = v),
            ),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _description,
              label: 'Bezeichnung',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null,
            ),
            SizedBox(height: spacing.md),
            Text('Art', style: Theme.of(context).textTheme.labelLarge),
            SizedBox(height: spacing.xs),
            AppSegmented<bool>(
              segments: const [
                AppSegment(value: false, label: 'Kosten'),
                AppSegment(value: true, label: 'Gutschrift'),
              ],
              selected: _isCredit,
              onChanged: (v) => setState(() => _isCredit = v),
            ),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _amount,
              label: 'Betrag (€)',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _amountFormatters,
              validator: (v) {
                final cents = Money.parseCents(v ?? '');
                if (cents == null) return 'Ungültig';
                if (cents == 0) return 'Betrag darf nicht 0 sein';
                return null;
              },
            ),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _reference,
              label: 'Beleg / Referenz (optional)',
            ),
            SizedBox(height: spacing.md),
            Row(
              children: [
                if (widget.existing != null)
                  TextButton.icon(
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Löschen'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Speichern'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final magnitude = Money.parseCents(_amount.text);
    if (magnitude == null || _costCenterId == null || _costTypeId == null) {
      return;
    }
    setState(() => _saving = true);
    final signed = _isCredit ? -magnitude.abs() : magnitude.abs();
    final ref = _reference.text.trim();
    final entry = JournalEntry(
      id: widget.existing?.id,
      orgId: widget.existing?.orgId ?? '',
      date: _date,
      costCenterId: _costCenterId!,
      costTypeId: _costTypeId!,
      description: _description.text.trim(),
      amountCents: signed,
      reference: ref.isEmpty ? null : ref,
      createdByUid: widget.existing?.createdByUid,
      createdAt: widget.existing?.createdAt,
    );
    try {
      await context.read<FinanceProvider>().saveJournalEntry(entry);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context, error);
      }
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    setState(() => _saving = true);
    try {
      await context.read<FinanceProvider>().deleteJournalEntry(id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context, error);
      }
    }
  }
}

class _CostCenterEditorSheet extends StatefulWidget {
  const _CostCenterEditorSheet({this.existing});

  final CostCenter? existing;

  @override
  State<_CostCenterEditorSheet> createState() => _CostCenterEditorSheetState();
}

class _CostCenterEditorSheetState extends State<_CostCenterEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _number;
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _costBearer;
  late final TextEditingController _annualBudget;
  late bool _isBillable;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _number = TextEditingController(text: e?.number ?? '');
    _name = TextEditingController(text: e?.name ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _costBearer = TextEditingController(text: e?.costBearerRef ?? '');
    _annualBudget = TextEditingController(
        text: (e?.annualBudgetCents ?? 0) > 0
            ? _centsToInput(e!.annualBudgetCents)
            : '');
    _isBillable = e?.isBillable ?? false;
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    _description.dispose();
    _costBearer.dispose();
    _annualBudget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return AppBottomSheetScaffold(
      title:
          widget.existing == null ? 'Neue Kostenstelle' : 'Kostenstelle bearbeiten',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppFormField(
                    controller: _number,
                    label: 'Nummer (KOST1)',
                    hint: 'z. B. 1001',
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Pflicht' : null,
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  flex: 2,
                  child: AppFormField(
                    controller: _name,
                    label: 'Name',
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Pflicht' : null,
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.md),
            AppFormField(
                controller: _description, label: 'Beschreibung (optional)'),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _annualBudget,
              label: 'Jahresbudget € (optional)',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _amountFormatters,
            ),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _costBearer,
              label: 'Kostenträger (DATEV KOST2, optional)',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Abrechenbar (Kostenträger)'),
              value: _isBillable,
              onChanged: (v) => setState(() => _isBillable = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aktiv'),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
            SizedBox(height: spacing.sm),
            Row(
              children: [
                if (widget.existing != null)
                  TextButton.icon(
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Löschen'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Speichern'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final e = widget.existing;
    final bearer = _costBearer.text.trim();
    final desc = _description.text.trim();
    final center = CostCenter(
      id: e?.id,
      orgId: e?.orgId ?? '',
      number: _number.text.trim(),
      name: _name.text.trim(),
      description: desc.isEmpty ? null : desc,
      costBearerRef: bearer.isEmpty ? null : bearer,
      annualBudgetCents: Money.parseCents(_annualBudget.text) ?? 0,
      isBillable: _isBillable,
      isActive: _isActive,
      createdByUid: e?.createdByUid,
      createdAt: e?.createdAt,
    );
    try {
      await context.read<FinanceProvider>().saveCostCenter(center);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context, error);
      }
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    setState(() => _saving = true);
    try {
      await context.read<FinanceProvider>().deleteCostCenter(id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context, error);
      }
    }
  }
}

class _CostTypeEditorSheet extends StatefulWidget {
  const _CostTypeEditorSheet({this.existing});

  final CostType? existing;

  @override
  State<_CostTypeEditorSheet> createState() => _CostTypeEditorSheetState();
}

class _CostTypeEditorSheetState extends State<_CostTypeEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _number;
  late final TextEditingController _name;
  late CostTypeGroup _group;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _number = TextEditingController(text: e?.number ?? '');
    _name = TextEditingController(text: e?.name ?? '');
    _group = e?.group ?? CostTypeGroup.overhead;
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return AppBottomSheetScaffold(
      title: widget.existing == null ? 'Neue Kostenart' : 'Kostenart bearbeiten',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppFormField(
                    controller: _number,
                    label: 'Sachkonto-Nr',
                    hint: 'z. B. 4100',
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Pflicht' : null,
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  flex: 2,
                  child: AppFormField(
                    controller: _name,
                    label: 'Name',
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Pflicht' : null,
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.md),
            Text('Gruppe', style: Theme.of(context).textTheme.labelLarge),
            SizedBox(height: spacing.xs),
            AppSegmented<CostTypeGroup>(
              segments: [
                for (final g in CostTypeGroup.values)
                  AppSegment(value: g, label: g.label),
              ],
              selected: _group,
              onChanged: (v) => setState(() => _group = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aktiv'),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
            SizedBox(height: spacing.sm),
            Row(
              children: [
                if (widget.existing != null)
                  TextButton.icon(
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Löschen'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Speichern'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final e = widget.existing;
    final type = CostType(
      id: e?.id,
      orgId: e?.orgId ?? '',
      number: _number.text.trim(),
      name: _name.text.trim(),
      group: _group,
      isActive: _isActive,
      createdByUid: e?.createdByUid,
      createdAt: e?.createdAt,
    );
    try {
      await context.read<FinanceProvider>().saveCostType(type);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context, error);
      }
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    setState(() => _saving = true);
    try {
      await context.read<FinanceProvider>().deleteCostType(id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context, error);
      }
    }
  }
}

class _BudgetEditorSheet extends StatefulWidget {
  const _BudgetEditorSheet({required this.year, this.existing});

  final int year;
  final Budget? existing;

  @override
  State<_BudgetEditorSheet> createState() => _BudgetEditorSheetState();
}

class _BudgetEditorSheetState extends State<_BudgetEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  String? _costCenterId;
  String? _costTypeId; // null = Gesamtbudget
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _amount = TextEditingController(
        text: e == null ? '' : _centsToInput(e.plannedAmountCents));
    _costCenterId = e?.costCenterId;
    _costTypeId = e?.costTypeId;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final finance = context.read<FinanceProvider>();
    final spacing = context.spacing;
    final centers = [...finance.costCenters]
      ..sort((a, b) => a.number.compareTo(b.number));
    final types = [...finance.costTypes]
      ..sort((a, b) => a.number.compareTo(b.number));

    return AppBottomSheetScaffold(
      title: widget.existing == null ? 'Neues Budget' : 'Budget bearbeiten',
      subtitle: 'Geschäftsjahr ${widget.year}',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _costCenterId,
              decoration: const InputDecoration(labelText: 'Kostenstelle'),
              items: [
                for (final c in centers)
                  DropdownMenuItem(
                      value: c.id, child: Text('${c.number} · ${c.name}')),
              ],
              validator: (v) => v == null ? 'Bitte wählen' : null,
              onChanged: (v) => setState(() => _costCenterId = v),
            ),
            SizedBox(height: spacing.md),
            DropdownButtonFormField<String?>(
              initialValue: _costTypeId,
              decoration:
                  const InputDecoration(labelText: 'Kostenart (optional)'),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('Gesamtbudget')),
                for (final t in types)
                  DropdownMenuItem<String?>(
                      value: t.id, child: Text('${t.number} · ${t.name}')),
              ],
              onChanged: (v) => setState(() => _costTypeId = v),
            ),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _amount,
              label: 'Planbetrag (€)',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _amountFormatters,
              validator: (v) =>
                  Money.parseCents(v ?? '') == null ? 'Ungültig' : null,
            ),
            SizedBox(height: spacing.md),
            Row(
              children: [
                if (widget.existing != null)
                  TextButton.icon(
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Löschen'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Speichern'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final cents = Money.parseCents(_amount.text);
    if (cents == null || _costCenterId == null) return;
    setState(() => _saving = true);
    final e = widget.existing;
    final oldId = e?.id;
    // Bei geändertem Kostenstellen-/Kostenart-Schlüssel ändert sich die
    // deterministische Doc-ID -> id zurücksetzen, sonst Update am falschen Doc.
    final keyChanged = e != null &&
        (e.costCenterId != _costCenterId || e.costTypeId != _costTypeId);
    final budget = Budget(
      id: keyChanged ? null : oldId,
      orgId: e?.orgId ?? '',
      costCenterId: _costCenterId!,
      costTypeId: _costTypeId,
      year: widget.year,
      plannedAmountCents: cents,
      createdByUid: e?.createdByUid,
      createdAt: e?.createdAt,
    );
    try {
      final finance = context.read<FinanceProvider>();
      // Beim Schlüsselwechsel das alte (umbenannte) Budget entfernen.
      if (keyChanged && oldId != null) {
        await finance.deleteBudget(oldId);
      }
      await finance.saveBudget(budget);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context, error);
      }
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    setState(() => _saving = true);
    try {
      await context.read<FinanceProvider>().deleteBudget(id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context, error);
      }
    }
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: firstDate,
          lastDate: lastDate,
          locale: const Locale('de', 'DE'),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(_formatDate(value)),
      ),
    );
  }
}
