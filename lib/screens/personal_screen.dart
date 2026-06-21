import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/payroll_calculator.dart';
import '../core/personnel_cost.dart';
import '../models/app_user.dart';
import '../models/audit_log_entry.dart';
import '../models/customer_order.dart';
import '../models/employment_contract.dart';
import '../models/payroll_record.dart';
import '../models/payroll_settings.dart';
import '../models/work_entry.dart';
import '../models/work_task.dart';
import '../providers/audit_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/personal_provider.dart';
import '../services/export_service.dart';
import '../ui/ui.dart';

/// Personal-Bereich (nur Admin): Übersicht, Aufträge, Lohn (Richtwert),
/// Finanzen (Personalkosten) und Statistiken – mit Monats-/Statusfilter und
/// PDF-/CSV-Export. Wird per `Navigator.push` aus dem Verwaltungsmenü geöffnet
/// (Muster von Team-/Warenwirtschafts-Screen). Reines V2-Design.
class PersonalScreen extends StatefulWidget {
  const PersonalScreen({super.key, this.parentLabel = 'Profil'});

  final String parentLabel;

  @override
  State<PersonalScreen> createState() => _PersonalScreenState();
}

class _PersonalScreenState extends State<PersonalScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<WorkEntry> _monthEntries = const [];
  bool _entriesLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEntries());
  }

  Future<void> _loadEntries() async {
    setState(() => _entriesLoading = true);
    final entries =
        await context.read<PersonalProvider>().loadOrgWorkEntriesForMonth(_month);
    if (!mounted) return;
    setState(() {
      _monthEntries = entries;
      _entriesLoading = false;
    });
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
    _loadEntries();
  }

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    // Admin-Gate: der Bereich ist nur über das Admin-Menü erreichbar; zur
    // Sicherheit auch hier prüfen.
    final isAdmin = personal.isAdmin;

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: BreadcrumbAppBar(
          breadcrumbs: [
            BreadcrumbItem(
              label: widget.parentLabel,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const BreadcrumbItem(label: 'Personal'),
          ],
        ),
        body: !isAdmin
            ? const EmptyState(
                icon: Icons.lock_outline,
                title: 'Kein Zugriff',
                message: 'Der Personal-Bereich ist Administratoren vorbehalten.',
              )
            : Column(
                children: [
                  const Material(
                    elevation: 0,
                    child: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [
                        Tab(text: 'Übersicht'),
                        Tab(text: 'Aufträge'),
                        Tab(text: 'Lohn'),
                        Tab(text: 'Finanzen'),
                        Tab(text: 'Statistik'),
                      ],
                    ),
                  ),
                  _MonthBar(
                    month: _month,
                    onPrev: () => _shiftMonth(-1),
                    onNext: () => _shiftMonth(1),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _OverviewTab(
                          month: _month,
                          monthEntries: _monthEntries,
                          entriesLoading: _entriesLoading,
                        ),
                        const _OrdersTab(),
                        _PayrollTab(month: _month, monthEntries: _monthEntries),
                        _FinanceTab(
                          month: _month,
                          monthEntries: _monthEntries,
                          entriesLoading: _entriesLoading,
                        ),
                        _StatsTab(year: _month.year),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ───────────────────────────── Gemeinsame Helfer ──────────────────────────

final NumberFormat _eurFormat =
    NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

String _euro(int cents) => _eurFormat.format(cents / 100);

String _monthLabel(DateTime month) =>
    DateFormat('MMMM yyyy', 'de_DE').format(month);

int? _parseEuroToCents(String raw) {
  final cleaned = raw
      .trim()
      .replaceAll('€', '')
      .replaceAll(' ', '')
      .replaceAll('.', '')
      .replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null) return null;
  return (value * 100).round();
}

String _centsToInput(int cents) =>
    (cents / 100).toStringAsFixed(2).replaceAll('.', ',');

double _hoursForUser(List<WorkEntry> entries, String userId) => entries
    .where((e) => e.userId == userId)
    .fold<double>(0, (sum, e) => sum + e.workedHours);

/// Personalkosten je Mitarbeiter (Stunden × Stundenlohn + AG-Kosten aus Lohn).
List<PersonnelCostRow> _costByEmployee(
  List<AppUserProfile> members,
  List<WorkEntry> entries,
  PersonalProvider provider,
  int year,
  int month,
) {
  final rows = <PersonnelCostRow>[];
  for (final member in members) {
    final hours = _hoursForUser(entries, member.uid);
    final rate = provider.contractForUser(member.uid)?.hourlyRate ?? 0;
    final payroll = provider.payrollForUserPeriod(member.uid, year, month);
    if (hours <= 0 && payroll == null) continue;
    rows.add(PersonnelCostRow(
      label: member.displayName,
      workedHours: hours,
      laborCostCents: (hours * rate * 100).round(),
      employerTotalCents: payroll?.employerTotalCents ?? 0,
    ));
  }
  rows.sort((a, b) => b.laborCostCents.compareTo(a.laborCostCents));
  return rows;
}

/// Personalkosten je Standort (aus den Zeiteinträgen, Lohn des jeweiligen MA).
List<PersonnelCostRow> _costBySite(
  List<WorkEntry> entries,
  PersonalProvider provider,
) {
  final hoursBySite = <String, double>{};
  final costBySite = <String, double>{};
  for (final entry in entries) {
    final site = (entry.siteName == null || entry.siteName!.trim().isEmpty)
        ? 'Ohne Standort'
        : entry.siteName!.trim();
    final rate = provider.contractForUser(entry.userId)?.hourlyRate ?? 0;
    hoursBySite.update(site, (v) => v + entry.workedHours,
        ifAbsent: () => entry.workedHours);
    costBySite.update(site, (v) => v + entry.workedHours * rate,
        ifAbsent: () => entry.workedHours * rate);
  }
  final rows = hoursBySite.entries
      .map((e) => PersonnelCostRow(
            label: e.key,
            workedHours: e.value,
            laborCostCents: ((costBySite[e.key] ?? 0) * 100).round(),
          ))
      .toList();
  rows.sort((a, b) => b.laborCostCents.compareTo(a.laborCostCents));
  return rows;
}

// ───────────────────────────── Monatsleiste ───────────────────────────────

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.spacing.md,
        context.spacing.sm,
        context.spacing.md,
        0,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Vorheriger Monat',
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              _monthLabel(month),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: 'Nächster Monat',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

EdgeInsets _tabPadding(BuildContext context) => EdgeInsets.fromLTRB(
      context.spacing.md,
      context.spacing.md,
      context.spacing.md,
      context.spacing.xl,
    );

// ───────────────────────────── Übersicht ──────────────────────────────────

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.month,
    required this.monthEntries,
    required this.entriesLoading,
  });

  final DateTime month;
  final List<WorkEntry> monthEntries;
  final bool entriesLoading;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final members = personal.members;
    final spacing = context.spacing;

    if (members.isEmpty) {
      return const EmptyState(
        icon: Icons.group_outlined,
        title: 'Keine Mitarbeiter',
        message: 'Lege im Teambereich Mitarbeiter an, um sie hier zu sehen.',
      );
    }

    final totalHours =
        monthEntries.fold<double>(0, (sum, e) => sum + e.workedHours);
    final totalCost = _costByEmployee(
      members,
      monthEntries,
      personal,
      month.year,
      month.month,
    ).fold<int>(0, (sum, r) => sum + r.laborCostCents);

    return ListView(
      padding: _tabPadding(context),
      children: [
        Row(
          children: [
            Expanded(
              child: AppMetricCard(
                label: 'Mitarbeiter',
                value: '${members.length}',
                icon: Icons.groups_outlined,
              ),
            ),
            SizedBox(width: spacing.md),
            Expanded(
              child: AppMetricCard(
                label: 'Stunden ($_monthShort)',
                value: entriesLoading
                    ? '…'
                    : '${totalHours.toStringAsFixed(1)} h',
                icon: Icons.schedule_outlined,
              ),
            ),
            SizedBox(width: spacing.md),
            Expanded(
              child: AppMetricCard(
                label: 'Personalkosten',
                value: entriesLoading ? '…' : _euro(totalCost),
                icon: Icons.payments_outlined,
              ),
            ),
          ],
        ),
        SizedBox(height: spacing.lg),
        Text(
          'Mitarbeiter',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        SizedBox(height: spacing.sm),
        for (final member in members) ...[
          _EmployeeCard(
            member: member,
            hours: _hoursForUser(monthEntries, member.uid),
            month: month,
            monthEntries: monthEntries,
          ),
          SizedBox(height: spacing.sm),
        ],
      ],
    );
  }

  String get _monthShort => DateFormat('MMM', 'de_DE').format(month);
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.member,
    required this.hours,
    required this.month,
    required this.monthEntries,
  });

  final AppUserProfile member;
  final double hours;
  final DateTime month;
  final List<WorkEntry> monthEntries;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final openTasks = personal.openTaskCountForUser(member.uid);
    final latest = personal.latestPayrollForUser(member.uid);
    final stats = personal.absenceStatsForUser(member.uid, year: month.year);

    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _EmployeeDetailScreen(
            member: member,
            month: month,
            monthEntries: monthEntries,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    colorScheme.primaryContainer.withValues(alpha: 0.7),
                foregroundColor: colorScheme.onPrimaryContainer,
                child: Text(member.displayName.isEmpty
                    ? '?'
                    : member.displayName.characters.first.toUpperCase()),
              ),
              SizedBox(width: context.spacing.sm + context.spacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      member.role.label,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
          SizedBox(height: context.spacing.sm + context.spacing.xs),
          Wrap(
            spacing: context.spacing.sm,
            runSpacing: context.spacing.xs,
            children: [
              _MiniChip(
                icon: Icons.schedule_outlined,
                label: '${hours.toStringAsFixed(1)} h',
              ),
              _MiniChip(
                icon: Icons.assignment_outlined,
                label: '$openTasks offen',
                tone: openTasks > 0 ? AppStatusTone.warning : null,
              ),
              if (latest != null)
                _MiniChip(
                  icon: Icons.payments_outlined,
                  label: 'Netto ${_euro(latest.netCents)}',
                  tone: AppStatusTone.success,
                ),
              if (stats.sicknessDays > 0)
                _MiniChip(
                  icon: Icons.sick_outlined,
                  label: '${stats.sicknessDays} Krank-Tg.',
                  tone: AppStatusTone.error,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.label, this.tone});

  final IconData icon;
  final String label;
  final AppStatusTone? tone;

  @override
  Widget build(BuildContext context) {
    return AppStatusBadge(
      label: label,
      tone: tone ?? AppStatusTone.neutral,
      icon: icon,
      filled: tone == null,
    );
  }
}

// ───────────────────────────── Aufträge ───────────────────────────────────

class _OrdersTab extends StatefulWidget {
  const _OrdersTab();

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  TaskStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final inventory = context.watch<InventoryProvider>();
    final spacing = context.spacing;

    final tasks = [...personal.tasks];
    tasks.sort((a, b) {
      final ad = a.dueDate, bd = b.dueDate;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });
    final filteredTasks = _statusFilter == null
        ? tasks
        : tasks.where((t) => t.status == _statusFilter).toList();

    final customerOrders = [...inventory.customerOrders]
      ..sort((a, b) {
        final ad = a.pickupDate, bd = b.pickupDate;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });

    return ListView(
      padding: _tabPadding(context),
      children: [
        AppSectionCard(
          title: 'Arbeitsaufträge',
          icon: Icons.checklist_rtl_outlined,
          trailing: FilledButton.tonalIcon(
            onPressed: () => _openTaskEditor(context, null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Neu'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: spacing.sm,
                children: [
                  AppFilterChip(
                    label: 'Alle',
                    selected: _statusFilter == null,
                    onSelected: (_) => setState(() => _statusFilter = null),
                  ),
                  for (final status in TaskStatus.values)
                    AppFilterChip(
                      label: status.label,
                      selected: _statusFilter == status,
                      onSelected: (_) =>
                          setState(() => _statusFilter = status),
                    ),
                ],
              ),
              SizedBox(height: spacing.md),
              if (filteredTasks.isEmpty)
                const _InlineEmpty(
                  icon: Icons.checklist_outlined,
                  message: 'Keine Arbeitsaufträge.',
                )
              else
                for (final task in filteredTasks) ...[
                  _TaskTile(task: task),
                  SizedBox(height: spacing.sm),
                ],
            ],
          ),
        ),
        SizedBox(height: spacing.lg),
        AppSectionCard(
          title: 'Kundenaufträge',
          icon: Icons.shopping_bag_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Übersicht aus der Warenwirtschaft – Verwaltung dort.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              SizedBox(height: spacing.sm),
              if (customerOrders.isEmpty)
                const _InlineEmpty(
                  icon: Icons.shopping_bag_outlined,
                  message: 'Keine Kundenaufträge erfasst.',
                )
              else
                for (final order in customerOrders.take(20)) ...[
                  _CustomerOrderTile(order: order),
                  SizedBox(height: spacing.sm),
                ],
            ],
          ),
        ),
      ],
    );
  }

  void _openTaskEditor(BuildContext context, WorkTask? task) {
    showAppBottomSheet(
      context: context,
      builder: (_) => _TaskEditorSheet(task: task),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});

  final WorkTask task;

  AppStatusTone get _tone => switch (task.status) {
        TaskStatus.open => AppStatusTone.warning,
        TaskStatus.inProgress => AppStatusTone.info,
        TaskStatus.done => AppStatusTone.success,
      };

  @override
  Widget build(BuildContext context) {
    final personal = context.read<PersonalProvider>();
    final member = personal.memberById(task.assignedUserId);
    final theme = Theme.of(context);
    return AppCard(
      color: theme.colorScheme.surfaceContainerLowest,
      onTap: () => showAppBottomSheet(
        context: context,
        builder: (_) => _TaskEditorSheet(task: task),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration:
                        task.isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              AppStatusBadge(label: task.status.label, tone: _tone),
            ],
          ),
          SizedBox(height: context.spacing.xs),
          Wrap(
            spacing: context.spacing.sm,
            runSpacing: context.spacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MiniChip(
                icon: Icons.person_outline,
                label: member?.displayName ?? 'Unbekannt',
              ),
              _MiniChip(
                icon: Icons.flag_outlined,
                label: task.priority.label,
              ),
              if (task.dueDate != null)
                _MiniChip(
                  icon: Icons.event_outlined,
                  label: DateFormat('dd.MM.yyyy', 'de_DE')
                      .format(task.dueDate!),
                  tone: task.isOverdue ? AppStatusTone.error : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomerOrderTile extends StatelessWidget {
  const _CustomerOrderTile({required this.order});

  final CustomerOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.customerName,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: context.spacing.xxs),
                Text(
                  [
                    if (order.orderNumber != null) order.orderNumber!,
                    if (order.pickupDate != null)
                      'Abholung ${DateFormat('dd.MM.', 'de_DE').format(order.pickupDate!)}',
                    if (order.hasPrices) _euro(order.totalCents),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          AppStatusBadge(
            label: order.status.label,
            tone: order.status.isOpen
                ? AppStatusTone.warning
                : AppStatusTone.success,
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Lohn ───────────────────────────────────────

class _PayrollTab extends StatelessWidget {
  const _PayrollTab({required this.month, required this.monthEntries});

  final DateTime month;
  final List<WorkEntry> monthEntries;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final spacing = context.spacing;
    final records = personal.payrollRecords
        .where((r) => r.periodYear == month.year && r.periodMonth == month.month)
        .toList()
      ..sort((a, b) => b.grossCents.compareTo(a.grossCents));

    return ListView(
      padding: _tabPadding(context),
      children: [
        const AppStatusBanner(
          icon: Icons.info_outline,
          tone: AppStatusTone.warning,
          message: PayrollResult.disclaimer,
        ),
        SizedBox(height: spacing.md),
        Row(
          children: [
            Expanded(
              child: Text(
                'Abrechnungen ${_monthLabel(month)}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            FilledButton.icon(
              onPressed: () => showAppBottomSheet(
                context: context,
                builder: (_) => _PayrollEditorSheet(
                  month: month,
                  monthEntries: monthEntries,
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Abrechnung'),
            ),
          ],
        ),
        SizedBox(height: spacing.md),
        if (records.isEmpty)
          const _InlineEmpty(
            icon: Icons.receipt_long_outlined,
            message: 'Noch keine Abrechnungen für diesen Monat.',
          )
        else
          for (final record in records) ...[
            _PayrollTile(record: record, month: month, monthEntries: monthEntries),
            SizedBox(height: spacing.sm),
          ],
      ],
    );
  }
}

class _PayrollTile extends StatelessWidget {
  const _PayrollTile({
    required this.record,
    required this.month,
    required this.monthEntries,
  });

  final PayrollRecord record;
  final DateTime month;
  final List<WorkEntry> monthEntries;

  @override
  Widget build(BuildContext context) {
    final personal = context.read<PersonalProvider>();
    final theme = Theme.of(context);
    final member = personal.memberById(record.userId);
    final name = member?.displayName ?? 'Unbekannt';

    return AppCard(
      onTap: () => showAppBottomSheet(
        context: context,
        builder: (_) => _PayrollEditorSheet(
          month: month,
          monthEntries: monthEntries,
          existing: record,
          presetUserId: record.userId,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              AppStatusBadge(
                label: record.kind == PayrollEmploymentKind.minijob
                    ? 'Minijob'
                    : record.taxClass.shortLabel,
                tone: AppStatusTone.neutral,
                filled: true,
              ),
            ],
          ),
          SizedBox(height: context.spacing.sm),
          Row(
            children: [
              Expanded(
                child: _AmountColumn(
                    label: 'Brutto', value: _euro(record.grossCents)),
              ),
              Expanded(
                child: _AmountColumn(
                  label: 'Netto',
                  value: _euro(record.netCents),
                  tone: AppStatusTone.success,
                ),
              ),
              Expanded(
                child: _AmountColumn(
                  label: 'AG-Kosten',
                  value: _euro(record.employerTotalCents),
                ),
              ),
            ],
          ),
          SizedBox(height: context.spacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => ExportService.exportPayrollPdf(
                record: record,
                employeeName: name,
              ),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('PDF'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountColumn extends StatelessWidget {
  const _AmountColumn({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final AppStatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tone == AppStatusTone.success
        ? theme.appColors.success
        : theme.colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        Text(
          value,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w800, color: color),
        ),
      ],
    );
  }
}

// ───────────────────────────── Finanzen ───────────────────────────────────

class _FinanceTab extends StatelessWidget {
  const _FinanceTab({
    required this.month,
    required this.monthEntries,
    required this.entriesLoading,
  });

  final DateTime month;
  final List<WorkEntry> monthEntries;
  final bool entriesLoading;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final spacing = context.spacing;

    if (entriesLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final byEmployee = _costByEmployee(
      personal.members,
      monthEntries,
      personal,
      month.year,
      month.month,
    );
    final bySite = _costBySite(monthEntries, personal);
    final totalCost = byEmployee.fold<int>(0, (s, r) => s + r.laborCostCents);
    final totalHours = byEmployee.fold<double>(0, (s, r) => s + r.workedHours);
    final totalEmployer =
        byEmployee.fold<int>(0, (s, r) => s + r.employerTotalCents);

    if (byEmployee.isEmpty) {
      return const EmptyState(
        icon: Icons.payments_outlined,
        title: 'Keine Kosten',
        message: 'Für diesen Monat liegen keine Zeiteinträge vor.',
      );
    }

    final rangeLabel = _monthLabel(month);

    return ListView(
      padding: _tabPadding(context),
      children: [
        Row(
          children: [
            Expanded(
              child: AppMetricCard(
                label: 'Personalkosten',
                value: _euro(totalCost),
                icon: Icons.payments_outlined,
              ),
            ),
            SizedBox(width: spacing.md),
            Expanded(
              child: AppMetricCard(
                label: 'Stunden',
                value: '${totalHours.toStringAsFixed(1)} h',
                icon: Icons.schedule_outlined,
              ),
            ),
          ],
        ),
        if (totalEmployer > 0) ...[
          SizedBox(height: spacing.md),
          AppStatCard(
            label: 'Arbeitgeber-Gesamtkosten (inkl. Lohnabrechnungen)',
            value: _euro(totalEmployer),
            subtitle: 'Brutto + AG-Sozialabgaben (Richtwert)',
            icon: Icons.account_balance_outlined,
            color: Theme.of(context).colorScheme.tertiary,
          ),
        ],
        SizedBox(height: spacing.lg),
        AppSectionCard(
          title: 'Kosten pro Mitarbeiter',
          icon: Icons.bar_chart_outlined,
          trailing: _ExportMenu(
            onPdf: () => ExportService.exportPersonnelCostPdf(
              rows: byEmployee,
              rangeLabel: rangeLabel,
              title: 'Personalkosten pro Mitarbeiter',
            ),
            onCsv: () => ExportService.exportPersonnelCostCsv(
              rows: byEmployee,
              rangeLabel: rangeLabel,
              title: 'Personalkosten pro Mitarbeiter',
            ),
          ),
          child: Column(
            children: [
              _CostBarChart(rows: byEmployee),
              SizedBox(height: spacing.sm),
              for (final row in byEmployee) _CostRowTile(row: row),
            ],
          ),
        ),
        SizedBox(height: spacing.lg),
        AppSectionCard(
          title: 'Kosten pro Standort',
          icon: Icons.storefront_outlined,
          child: Column(
            children: [
              _CostBarChart(rows: bySite),
              SizedBox(height: spacing.sm),
              for (final row in bySite) _CostRowTile(row: row),
            ],
          ),
        ),
      ],
    );
  }
}

class _CostRowTile extends StatelessWidget {
  const _CostRowTile({required this.row});

  final PersonnelCostRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(row.label)),
          Text(
            '${row.workedHours.toStringAsFixed(1)} h',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          SizedBox(width: context.spacing.md),
          Text(
            _euro(row.laborCostCents),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Statistik ──────────────────────────────────

class _StatsTab extends StatelessWidget {
  const _StatsTab({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final spacing = context.spacing;
    final members = personal.members;

    if (members.isEmpty) {
      return const EmptyState(
        icon: Icons.insights_outlined,
        title: 'Keine Daten',
        message: 'Es sind keine Mitarbeiter vorhanden.',
      );
    }

    var sickTotal = 0, vacationTotal = 0, unavailableTotal = 0;
    final perMember = <_StatsRow>[];
    for (final member in members) {
      final stats = personal.absenceStatsForUser(member.uid, year: year);
      sickTotal += stats.sicknessDays;
      vacationTotal += stats.vacationDays;
      unavailableTotal += stats.unavailableDays;
      perMember.add(_StatsRow(name: member.displayName, sickDays: stats.sicknessDays, vacationDays: stats.vacationDays, unavailableDays: stats.unavailableDays));
    }
    perMember.sort((a, b) => b.sickDays.compareTo(a.sickDays));

    final appColors = Theme.of(context).appColors;

    return ListView(
      padding: _tabPadding(context),
      children: [
        Text(
          'Abwesenheiten $year',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        SizedBox(height: spacing.sm),
        Row(
          children: [
            Expanded(
              child: AppStatCard(
                label: 'Krank',
                value: '$sickTotal Tage',
                subtitle: 'Gesamt im Team',
                icon: Icons.sick_outlined,
                color: appColors.warning,
              ),
            ),
            SizedBox(width: spacing.md),
            Expanded(
              child: AppStatCard(
                label: 'Nicht verfügbar',
                value: '$unavailableTotal Tage',
                subtitle: 'Gesamt im Team',
                icon: Icons.event_busy_outlined,
                color: appColors.info,
              ),
            ),
          ],
        ),
        SizedBox(height: spacing.md),
        AppStatCard(
          label: 'Urlaub',
          value: '$vacationTotal Tage',
          subtitle: 'Genommen/geplant im Team',
          icon: Icons.beach_access_outlined,
          color: appColors.success,
        ),
        SizedBox(height: spacing.lg),
        AppSectionCard(
          title: 'Krank-Tage pro Mitarbeiter',
          icon: Icons.bar_chart_outlined,
          child: _StatsBarChart(
            labels: perMember.map((r) => r.name).toList(),
            values: perMember.map((r) => r.sickDays.toDouble()).toList(),
            unit: 'Tage',
            color: appColors.warning,
          ),
        ),
        SizedBox(height: spacing.lg),
        AppSectionCard(
          title: 'Details pro Mitarbeiter',
          icon: Icons.table_chart_outlined,
          child: Column(
            children: [
              for (final row in perMember)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: context.spacing.xs),
                  child: Row(
                    children: [
                      Expanded(child: Text(row.name)),
                      _MiniChip(
                        icon: Icons.sick_outlined,
                        label: '${row.sickDays}',
                        tone: AppStatusTone.warning,
                      ),
                      SizedBox(width: context.spacing.xs),
                      _MiniChip(
                        icon: Icons.event_busy_outlined,
                        label: '${row.unavailableDays}',
                        tone: AppStatusTone.info,
                      ),
                      SizedBox(width: context.spacing.xs),
                      _MiniChip(
                        icon: Icons.beach_access_outlined,
                        label: '${row.vacationDays}',
                        tone: AppStatusTone.success,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsRow {
  const _StatsRow({
    required this.name,
    required this.sickDays,
    required this.vacationDays,
    required this.unavailableDays,
  });
  final String name;
  final int sickDays;
  final int vacationDays;
  final int unavailableDays;
}

// ───────────────────────────── Charts ─────────────────────────────────────

class _CostBarChart extends StatelessWidget {
  const _CostBarChart({required this.rows});

  final List<PersonnelCostRow> rows;

  @override
  Widget build(BuildContext context) {
    return _StatsBarChart(
      labels: rows.map((r) => r.label).toList(),
      values: rows.map((r) => r.laborCostCents / 100).toList(),
      unit: '€',
      color: Theme.of(context).colorScheme.primary,
    );
  }
}

/// Generischer Balkenchart (fl_chart) für die Personal-Auswertungen.
/// Konfiguration angelehnt an `statistics_screen` (gleiche fl_chart-Version).
class _StatsBarChart extends StatelessWidget {
  const _StatsBarChart({
    required this.labels,
    required this.values,
    required this.unit,
    required this.color,
  });

  final List<String> labels;
  final List<double> values;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (values.isEmpty || values.every((v) => v <= 0)) {
      return const _InlineEmpty(
        icon: Icons.bar_chart_outlined,
        message: 'Keine Werte vorhanden.',
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
                '${labels[group.x]}\n${rod.toY.toStringAsFixed(unit == '€' ? 0 : 1)} $unit',
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
                reservedSize: 36,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  final short = labels[i].split(' ').first;
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      short.length > 8 ? '${short.substring(0, 7)}…' : short,
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
                  color: color,
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

// ───────────────────────────── Mitarbeiter-Detail ─────────────────────────

class _EmployeeDetailScreen extends StatelessWidget {
  const _EmployeeDetailScreen({
    required this.member,
    required this.month,
    required this.monthEntries,
  });

  final AppUserProfile member;
  final DateTime month;
  final List<WorkEntry> monthEntries;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final spacing = context.spacing;
    final contract = personal.contractForUser(member.uid);
    final hours = _hoursForUser(monthEntries, member.uid);
    final rate = contract?.hourlyRate ?? 0;
    final costCents = (hours * rate * 100).round();
    final stats = personal.absenceStatsForUser(member.uid, year: month.year);
    final tasks = personal.tasksForUser(member.uid);
    final payroll = personal.payrollForUser(member.uid);
    final appColors = Theme.of(context).appColors;

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: 'Personal',
            onTap: () => Navigator.of(context).maybePop(),
          ),
          BreadcrumbItem(label: member.displayName),
        ],
      ),
      body: ListView(
        padding: _tabPadding(context),
        children: [
          AppHeroCard(
            tone: AppHeroTone.accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.displayName,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                SizedBox(height: spacing.xxs),
                Text(
                  '${member.role.label} · ${contract?.type.label ?? 'Kein Vertrag'}'
                  '${rate > 0 ? ' · ${_euro((rate * 100).round())}/h' : ''}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          if (rate > 0 &&
              personal.payrollSettings
                  .isBelowMinimumWage((rate * 100).round())) ...[
            SizedBox(height: spacing.md),
            AppStatusBanner(
              tone: AppStatusTone.warning,
              icon: Icons.warning_amber_rounded,
              message: 'Stundenlohn ${_euro((rate * 100).round())} liegt unter '
                  'dem gesetzlichen Mindestlohn von '
                  '${_euro(personal.payrollSettings.minimumHourlyWageCents)}.',
            ),
          ],
          SizedBox(height: spacing.lg),
          Row(
            children: [
              Expanded(
                child: AppMetricCard(
                  label: 'Stunden ${DateFormat('MMM', 'de_DE').format(month)}',
                  value: '${hours.toStringAsFixed(1)} h',
                  icon: Icons.schedule_outlined,
                ),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: AppMetricCard(
                  label: 'Kosten',
                  value: _euro(costCents),
                  icon: Icons.payments_outlined,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.lg),
          AppSectionCard(
            title: 'Abwesenheiten ${month.year}',
            icon: Icons.event_busy_outlined,
            child: Row(
              children: [
                Expanded(
                  child: AppStatCard(
                    label: 'Krank',
                    value: '${stats.sicknessDays}',
                    subtitle: '${stats.sicknessCount}×',
                    icon: Icons.sick_outlined,
                    color: appColors.warning,
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: AppStatCard(
                    label: 'N. verfügbar',
                    value: '${stats.unavailableDays}',
                    subtitle: '${stats.unavailableCount}×',
                    icon: Icons.event_busy_outlined,
                    color: appColors.info,
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: AppStatCard(
                    label: 'Urlaub',
                    value: '${stats.vacationDays}',
                    subtitle: '${stats.vacationCount}×',
                    icon: Icons.beach_access_outlined,
                    color: appColors.success,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.lg),
          AppSectionCard(
            title: 'Aufträge',
            icon: Icons.checklist_rtl_outlined,
            trailing: FilledButton.tonalIcon(
              onPressed: () => showAppBottomSheet(
                context: context,
                builder: (_) =>
                    _TaskEditorSheet(task: null, presetUserId: member.uid),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Neu'),
            ),
            child: tasks.isEmpty
                ? const _InlineEmpty(
                    icon: Icons.checklist_outlined,
                    message: 'Keine Aufträge zugewiesen.',
                  )
                : Column(
                    children: [
                      for (final task in tasks) ...[
                        _TaskTile(task: task),
                        SizedBox(height: spacing.sm),
                      ],
                    ],
                  ),
          ),
          SizedBox(height: spacing.lg),
          AppSectionCard(
            title: 'Lohnabrechnungen',
            icon: Icons.receipt_long_outlined,
            trailing: FilledButton.tonalIcon(
              onPressed: () => showAppBottomSheet(
                context: context,
                builder: (_) => _PayrollEditorSheet(
                  month: month,
                  monthEntries: monthEntries,
                  presetUserId: member.uid,
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Neu'),
            ),
            child: payroll.isEmpty
                ? const _InlineEmpty(
                    icon: Icons.receipt_long_outlined,
                    message: 'Noch keine Abrechnungen.',
                  )
                : Column(
                    children: [
                      for (final record in payroll) ...[
                        _PayrollTile(
                          record: record,
                          month: DateTime(record.periodYear, record.periodMonth),
                          monthEntries: monthEntries,
                        ),
                        SizedBox(height: spacing.sm),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Editor-Sheets ──────────────────────────────

class _TaskEditorSheet extends StatefulWidget {
  const _TaskEditorSheet({required this.task, this.presetUserId});

  final WorkTask? task;
  final String? presetUserId;

  @override
  State<_TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<_TaskEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  String? _userId;
  DateTime? _dueDate;
  TaskPriority _priority = TaskPriority.medium;
  TaskStatus _status = TaskStatus.open;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _title = TextEditingController(text: task?.title ?? '');
    _description = TextEditingController(text: task?.description ?? '');
    _userId = task?.assignedUserId ?? widget.presetUserId;
    _dueDate = task?.dueDate;
    _priority = task?.priority ?? TaskPriority.medium;
    _status = task?.status ?? TaskStatus.open;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final personal = context.read<PersonalProvider>();
    final members = personal.members;
    final spacing = context.spacing;

    return AppBottomSheetScaffold(
      title: widget.task == null ? 'Neuer Auftrag' : 'Auftrag bearbeiten',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _userId,
              decoration: const InputDecoration(labelText: 'Mitarbeiter'),
              items: [
                for (final member in members)
                  DropdownMenuItem(
                    value: member.uid,
                    child: Text(member.displayName),
                  ),
              ],
              validator: (value) =>
                  value == null ? 'Bitte Mitarbeiter wählen' : null,
              onChanged: (value) => setState(() => _userId = value),
            ),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _title,
              label: 'Titel',
              textCapitalization: TextCapitalization.sentences,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Pflichtfeld' : null,
            ),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _description,
              label: 'Beschreibung (optional)',
              maxLines: 3,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
            SizedBox(height: spacing.md),
            Text('Priorität', style: Theme.of(context).textTheme.labelLarge),
            SizedBox(height: spacing.xs),
            AppSegmented<TaskPriority>(
              segments: [
                for (final p in TaskPriority.values)
                  AppSegment(value: p, label: p.label),
              ],
              selected: _priority,
              onChanged: (value) => setState(() => _priority = value),
            ),
            SizedBox(height: spacing.md),
            Text('Status', style: Theme.of(context).textTheme.labelLarge),
            SizedBox(height: spacing.xs),
            AppSegmented<TaskStatus>(
              segments: [
                for (final s in TaskStatus.values)
                  AppSegment(value: s, label: s.label),
              ],
              selected: _status,
              onChanged: (value) => setState(() => _status = value),
            ),
            SizedBox(height: spacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(
                _dueDate == null
                    ? 'Fälligkeit (optional)'
                    : DateFormat('dd.MM.yyyy', 'de_DE').format(_dueDate!),
              ),
              trailing: _dueDate == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _dueDate = null),
                    ),
              onTap: _pickDueDate,
            ),
            SizedBox(height: spacing.md),
            Row(
              children: [
                if (widget.task != null)
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Speichern'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      locale: const Locale('de', 'DE'),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final personal = context.read<PersonalProvider>();
    final base = widget.task ??
        WorkTask(orgId: '', assignedUserId: _userId!, title: _title.text.trim());
    final task = base.copyWith(
      assignedUserId: _userId,
      title: _title.text.trim(),
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      clearDescription: _description.text.trim().isEmpty,
      dueDate: _dueDate,
      clearDueDate: _dueDate == null,
      priority: _priority,
      status: _status,
    );
    try {
      await personal.saveWorkTask(task);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context, error);
      }
    }
  }

  Future<void> _delete() async {
    final id = widget.task?.id;
    if (id == null) return;
    setState(() => _saving = true);
    try {
      await context.read<PersonalProvider>().deleteWorkTask(id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context, error);
      }
    }
  }
}

class _PayrollEditorSheet extends StatefulWidget {
  const _PayrollEditorSheet({
    required this.month,
    required this.monthEntries,
    this.existing,
    this.presetUserId,
  });

  final DateTime month;
  final List<WorkEntry> monthEntries;
  final PayrollRecord? existing;
  final String? presetUserId;

  @override
  State<_PayrollEditorSheet> createState() => _PayrollEditorSheetState();
}

class _PayrollEditorSheetState extends State<_PayrollEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _gross;
  String? _userId;
  TaxClass _taxClass = TaxClass.i;
  PayrollEmploymentKind _kind = PayrollEmploymentKind.standard;
  bool _churchTax = false;
  String? _federalState;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _userId = existing?.userId ?? widget.presetUserId;
    _gross = TextEditingController(
      text: existing != null ? _centsToInput(existing.grossCents) : '',
    );
    if (existing != null) {
      _taxClass = existing.taxClass;
      _kind = existing.kind;
      _churchTax = existing.churchTax;
      _federalState = existing.federalState;
    } else if (_userId != null) {
      // Neue Abrechnung: aus den Lohn-Stammdaten des Mitarbeiters vorbefuellen.
      _applyProfile(_userId!);
    }
  }

  /// Uebernimmt die gespeicherten Lohn-Stammdaten eines Mitarbeiters in die
  /// Formularfelder (nur fuer eine neue Abrechnung aufgerufen).
  void _applyProfile(String userId) {
    final profile = context.read<PersonalProvider>().profileForUser(userId);
    if (profile == null) return;
    _taxClass = profile.taxClass;
    _kind = profile.kind;
    _churchTax = profile.churchTax;
    _federalState = profile.federalState;
    final gross = profile.monthlyGrossCents;
    if (gross != null && gross > 0 && _gross.text.trim().isEmpty) {
      _gross.text = _centsToInput(gross);
    }
  }

  /// Wert fuer das Bundesland-Dropdown – nur BY/BW sind kirchensteuer-relevant
  /// (8 % statt 9 %); alles andere wird als „Andere" (null) angezeigt.
  String? get _stateDropdownValue {
    final state = (_federalState ?? '').toLowerCase();
    if (state.startsWith('bay') || state == 'by') return 'Bayern';
    if (state.startsWith('baden') || state == 'bw') return 'Baden-Württemberg';
    return null;
  }

  @override
  void dispose() {
    _gross.dispose();
    super.dispose();
  }

  PayrollSettings get _settings => context.read<PersonalProvider>().payrollSettings;

  PayrollResult? get _result {
    final cents = _parseEuroToCents(_gross.text);
    if (cents == null) return null;
    return PayrollCalculator.calculate(
      grossCents: cents,
      taxClass: _taxClass,
      churchTax: _churchTax,
      federalState: _federalState,
      kind: _kind,
      settings: _settings,
    );
  }

  @override
  Widget build(BuildContext context) {
    final personal = context.read<PersonalProvider>();
    final members = personal.members;
    final spacing = context.spacing;
    final result = _result;

    return AppBottomSheetScaffold(
      title: widget.existing == null
          ? 'Neue Lohnabrechnung'
          : 'Lohnabrechnung bearbeiten',
      subtitle: '${_monthLabel(widget.month)} · Richtwert',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppStatusBanner(
              icon: Icons.info_outline,
              tone: AppStatusTone.warning,
              message: PayrollResult.disclaimer,
            ),
            SizedBox(height: spacing.md),
            DropdownButtonFormField<String>(
              initialValue: _userId,
              decoration: const InputDecoration(labelText: 'Mitarbeiter'),
              items: [
                for (final member in members)
                  DropdownMenuItem(
                    value: member.uid,
                    child: Text(member.displayName),
                  ),
              ],
              validator: (value) =>
                  value == null ? 'Bitte Mitarbeiter wählen' : null,
              onChanged: (value) => setState(() {
                _userId = value;
                // Neue Abrechnung: Stammdaten des gewählten Mitarbeiters laden.
                if (value != null && widget.existing == null) {
                  _applyProfile(value);
                }
              }),
            ),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _gross,
              label: 'Bruttolohn (€)',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onChanged: (_) => setState(() {}),
              validator: (value) =>
                  _parseEuroToCents(value ?? '') == null ? 'Ungültig' : null,
              suffixIcon: IconButton(
                tooltip: 'Aus Stunden/Vertrag',
                icon: const Icon(Icons.auto_fix_high_outlined),
                onPressed: _userId == null ? null : _prefillGross,
              ),
            ),
            SizedBox(height: spacing.md),
            Text('Steuerklasse', style: Theme.of(context).textTheme.labelLarge),
            SizedBox(height: spacing.xs),
            AppSegmented<TaxClass>(
              segments: [
                for (final t in TaxClass.values)
                  AppSegment(value: t, label: t.shortLabel),
              ],
              selected: _taxClass,
              onChanged: (value) => setState(() => _taxClass = value),
            ),
            SizedBox(height: spacing.md),
            Text('Beschäftigung', style: Theme.of(context).textTheme.labelLarge),
            SizedBox(height: spacing.xs),
            AppSegmented<PayrollEmploymentKind>(
              segments: const [
                AppSegment(
                    value: PayrollEmploymentKind.standard, label: 'SV-pflichtig'),
                AppSegment(
                    value: PayrollEmploymentKind.minijob, label: 'Minijob'),
                AppSegment(
                    value: PayrollEmploymentKind.midijob, label: 'Midijob'),
              ],
              selected: _kind,
              onChanged: (value) => setState(() => _kind = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Kirchensteuer'),
              value: _churchTax,
              onChanged: (value) => setState(() => _churchTax = value),
            ),
            if (_churchTax) ...[
              SizedBox(height: spacing.xs),
              DropdownButtonFormField<String?>(
                initialValue: _stateDropdownValue,
                decoration: const InputDecoration(
                  labelText: 'Bundesland (Kirchensteuersatz)',
                ),
                items: const [
                  DropdownMenuItem(
                    value: null,
                    child: Text('Andere Bundesländer (9 %)'),
                  ),
                  DropdownMenuItem(
                    value: 'Bayern',
                    child: Text('Bayern (8 %)'),
                  ),
                  DropdownMenuItem(
                    value: 'Baden-Württemberg',
                    child: Text('Baden-Württemberg (8 %)'),
                  ),
                ],
                onChanged: (value) => setState(() => _federalState = value),
              ),
            ],
            if (result != null) ...[
              SizedBox(height: spacing.sm),
              _PayrollBreakdown(result: result),
            ],
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
                  onPressed: _saving || result == null ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Speichern'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _prefillGross() {
    final personal = context.read<PersonalProvider>();
    final userId = _userId;
    if (userId == null) return;
    final contract = personal.contractForUser(userId);
    final rate = contract?.hourlyRate ?? 0;
    final hours = _hoursForUser(widget.monthEntries, userId);
    double gross;
    if (hours > 0 && rate > 0) {
      gross = hours * rate;
    } else if (rate > 0 && contract != null) {
      gross = rate * contract.weeklyHours * 4.33;
    } else {
      gross = 0;
    }
    setState(() => _gross.text = gross.toStringAsFixed(2).replaceAll('.', ','));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final result = _result;
    if (result == null || _userId == null) return;
    setState(() => _saving = true);
    final personal = context.read<PersonalProvider>();
    final audit = context.read<AuditProvider>();
    final memberName =
        personal.memberById(_userId!)?.displayName ?? 'Mitarbeiter';
    final isNew = widget.existing == null;
    final record = result.buildRecord(
      id: widget.existing?.id,
      orgId: '',
      userId: _userId!,
      periodYear: widget.month.year,
      periodMonth: widget.month.month,
      taxClass: _taxClass,
      churchTax: _churchTax,
      federalState: _federalState,
    );
    try {
      await personal.savePayrollRecord(record);
      // Stammdaten merken -> naechste Abrechnung wird vorbefuellt.
      await personal.rememberPayrollProfile(
        userId: _userId!,
        taxClass: _taxClass,
        kind: _kind,
        churchTax: _churchTax,
        federalState: _federalState,
        monthlyGrossCents: record.grossCents,
      );
      // Audit-Trail: Lohn-Snapshots werden per deterministischer Doc-ID still
      // ueberschrieben -> Aenderung protokollieren.
      await audit.log(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Lohnabrechnung',
        entityId: record.documentId,
        summary: '$memberName ${_monthLabel(widget.month)}: '
            'Brutto ${_euro(record.grossCents)}, Netto ${_euro(record.netCents)}',
      );
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
      await context.read<PersonalProvider>().deletePayrollRecord(id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context, error);
      }
    }
  }
}

class _PayrollBreakdown extends StatelessWidget {
  const _PayrollBreakdown({required this.result});

  final PayrollResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;

    Widget row(String label, int cents, {bool bold = false, Color? color}) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: context.spacing.xxs),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: bold
                    ? theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)
                    : theme.textTheme.bodyMedium,
              ),
            ),
            Text(
              _euro(cents),
              style: (bold
                      ? theme.textTheme.titleSmall
                      : theme.textTheme.bodyMedium)
                  ?.copyWith(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    return AppCard(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        children: [
          row('Bruttolohn', result.grossCents, bold: true),
          const Divider(),
          row('Lohnsteuer', -result.incomeTaxCents),
          if (result.soliCents > 0) row('Soli', -result.soliCents),
          if (result.churchTaxCents > 0)
            row('Kirchensteuer', -result.churchTaxCents),
          if (result.employeeSocialTotalCents > 0)
            row('Sozialabgaben (AN)', -result.employeeSocialTotalCents),
          const Divider(),
          row('Nettolohn', result.netCents,
              bold: true, color: appColors.success),
          SizedBox(height: context.spacing.xs),
          row('Arbeitgeber-Gesamtkosten', result.employerTotalCents,
              color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

// ───────────────────────────── Kleinteile ─────────────────────────────────

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: theme.colorScheme.outline, size: 20),
          SizedBox(width: context.spacing.sm),
          Flexible(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportMenu extends StatelessWidget {
  const _ExportMenu({required this.onPdf, required this.onCsv});

  final VoidCallback onPdf;
  final VoidCallback onCsv;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      icon: const Icon(Icons.ios_share_outlined),
      tooltip: 'Exportieren',
      onSelected: (value) => value == 0 ? onPdf() : onCsv(),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 0, child: Text('Als PDF')),
        PopupMenuItem(value: 1, child: Text('Als CSV')),
      ],
    );
  }
}

void _showError(BuildContext context, Object error) {
  final message = error is StateError ? error.message : 'Aktion fehlgeschlagen.';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
