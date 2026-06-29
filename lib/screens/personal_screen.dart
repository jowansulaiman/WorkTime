import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/de_number_input.dart';
import '../core/lohn_herleitung.dart';
import '../core/money.dart';
import '../core/payroll_calculator.dart';
import '../core/personnel_cost.dart';
import '../core/sfn_zuschlag.dart';
import '../core/zeitkonto_calculator.dart';
import '../models/app_user.dart';
import '../models/customer_order.dart';
import '../models/employee_profile.dart';
import '../models/employee_ausbildung.dart';
import '../models/employee_child.dart';
import '../models/employee_qualification.dart';
import '../models/employment_contract.dart';
import '../models/org_payroll_settings.dart';
import '../models/pay_line_type.dart';
import '../models/urlaubsanpassung.dart';
import '../models/urlaubskonto_jahr.dart';
import '../models/payroll_record.dart';
import '../models/payroll_settings.dart';
import '../models/work_entry.dart';
import '../models/work_task.dart';
import '../providers/inventory_provider.dart';
import '../providers/personal_provider.dart';
import '../services/export_service.dart';
import '../ui/ui.dart';
import 'abwesenheit_screen.dart';

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

/// Urlaubstage ohne überflüssige Nachkommastelle, mit deutschem Komma
/// (30.0 → „30", 12.5 → „12,5").
String _formatTage(double tage) => tage % 1 == 0
    ? tage.toInt().toString()
    : tage.toStringAsFixed(1).replaceAll('.', ',');

String _formatDate(DateTime date) =>
    DateFormat('dd.MM.yyyy', 'de_DE').format(date);

/// Formatiert einen Prozentwert mit deutschem Dezimalkomma (z. B. „1,7 %").
/// Ganzzahlige Werte werden ohne Nachkommastelle dargestellt („15 %").
String _formatPercent(double value) {
  final text = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString().replaceAll('.', ',');
  return '$text %';
}

/// Farbton für den Lohn-Freigabestatus.
AppStatusTone _payrollStatusTone(PayrollStatus status) => switch (status) {
      PayrollStatus.entwurf => AppStatusTone.neutral,
      PayrollStatus.freigegeben => AppStatusTone.info,
      PayrollStatus.bezahlt => AppStatusTone.success,
      PayrollStatus.storniert => AppStatusTone.error,
    };

int? _parseEuroToCents(String raw) => Money.parseCents(raw);

// Prozent <-> Bruchteil-Umrechnung: geteilte, getestete Util (de_number_input).
String _rateToPercentInput(double fraction) => rateToPercentInput(fraction);

double? _percentInputToRate(String raw) => percentInputToRate(raw);

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
        const _UrlaubMigrationCard(),
        AppCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AbwesenheitScreen(),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.beach_access_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: context.iconSizes.md),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Abwesenheits-Übersicht',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    Text('Urlaubskonten & §9-Hinweise je Mitarbeiter',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
        SizedBox(height: spacing.sm),
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

/// Selbst-versteckende M0-Hinweiskarte: bietet (admin) das einmalige Übernehmen
/// der Bestands-Urlaubstage aus den deprecaten Altfeldern ins Sollzeit-Modell
/// an. Sichtbar nur, solange es offene Übernahmen gibt.
class _UrlaubMigrationCard extends StatefulWidget {
  const _UrlaubMigrationCard();

  @override
  State<_UrlaubMigrationCard> createState() => _UrlaubMigrationCardState();
}

class _UrlaubMigrationCardState extends State<_UrlaubMigrationCard> {
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final offen = personal.mitarbeiterMitOffenerUrlaubsMigration;
    if (offen.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(bottom: context.spacing.lg),
      child: AppSectionCard(
        title: 'Urlaubsdaten ins Sollzeit-Modell übernehmen',
        icon: Icons.event_available_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${offen.length} Mitarbeiter haben ihren Jahresurlaub noch im '
              'alten Feld. Übernimm die Bestandswerte unverändert ins '
              'Sollzeit-Modell (Urlaubstage/Jahr) – das wird die künftige Quelle.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SizedBox(height: context.spacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _running ? null : _run,
                icon: _running
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.move_down, size: 18),
                label: const Text('Übernehmen'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final personal = context.read<PersonalProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final anzahl = await personal.migriereUrlaubstageInSollzeit();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(anzahl == 0
            ? 'Keine Übernahme nötig.'
            : '$anzahl Urlaubswert(e) ins Sollzeit-Modell übernommen.'),
      ));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Übernahme fehlgeschlagen: $error')),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
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
            IconButton(
              tooltip: 'Lohnarten-Katalog',
              icon: const Icon(Icons.list_alt_outlined),
              onPressed: () => showAppBottomSheet(
                context: context,
                builder: (_) => const _PayLineTypeKatalogSheet(),
              ),
            ),
            IconButton(
              tooltip: 'Lohn-Einstellungen ${month.year}',
              icon: const Icon(Icons.tune),
              onPressed: () => showAppBottomSheet(
                context: context,
                builder: (_) => _OrgPayrollSettingsSheet(jahr: month.year),
              ),
            ),
            SizedBox(width: spacing.xs),
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
        else ...[
          _PayrollRunSummary(month: month, records: records),
          SizedBox(height: spacing.lg),
          for (final record in records) ...[
            _PayrollTile(record: record, month: month, monthEntries: monthEntries),
            SizedBox(height: spacing.sm),
          ],
        ],
      ],
    );
  }
}

/// Lohnlauf-Übersicht eines Monats: Summen-KPIs über alle Abrechnungen +
/// Statusverteilung + Batch-Freigabe aller Entwürfe.
class _PayrollRunSummary extends StatelessWidget {
  const _PayrollRunSummary({required this.month, required this.records});

  final DateTime month;
  final List<PayrollRecord> records;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final appColors = Theme.of(context).appColors;

    var grossSum = 0, deductionsSum = 0, netSum = 0, employerSum = 0;
    var drafts = 0, released = 0, paid = 0, cancelled = 0;
    for (final r in records) {
      // Stornierte Abrechnungen zählen nicht in die Monatssummen.
      if (r.status == PayrollStatus.storniert) {
        cancelled++;
        continue;
      }
      grossSum += r.grossCents;
      deductionsSum += r.totalDeductionsCents;
      netSum += r.netCents;
      employerSum += r.employerTotalCents;
      switch (r.status) {
        case PayrollStatus.entwurf:
          drafts++;
        case PayrollStatus.freigegeben:
          released++;
        case PayrollStatus.bezahlt:
          paid++;
        case PayrollStatus.storniert:
          break;
      }
    }

    return AppSectionCard(
      title: 'Lohnlauf ${_monthLabel(month)}',
      icon: Icons.account_balance_wallet_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AppStatCard(
                  label: 'Brutto gesamt',
                  value: _euro(grossSum),
                  subtitle: '${records.length} Abrechnungen',
                  icon: Icons.arrow_upward,
                  color: appColors.info,
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: AppStatCard(
                  label: 'Abzüge gesamt',
                  value: _euro(deductionsSum),
                  subtitle: 'Steuer + SV (AN)',
                  icon: Icons.arrow_downward,
                  color: appColors.warning,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Row(
            children: [
              Expanded(
                child: AppStatCard(
                  label: 'Netto gesamt',
                  value: _euro(netSum),
                  subtitle: 'Auszahlung',
                  icon: Icons.payments_outlined,
                  color: appColors.success,
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: AppStatCard(
                  label: 'AG-Kosten gesamt',
                  value: _euro(employerSum),
                  subtitle: 'inkl. AG-SV',
                  icon: Icons.business_outlined,
                  color: appColors.info,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Text(
            '${records.length} Abrechnungen · $drafts Entwurf · '
            '$released freigegeben · $paid bezahlt'
            '${cancelled > 0 ? ' · $cancelled storniert' : ''}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          if (drafts > 0) ...[
            SizedBox(height: spacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => _finalizeAll(context),
                icon: const Icon(Icons.verified_outlined, size: 18),
                label: Text('Alle Entwürfe freigeben ($drafts)'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _finalizeAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Alle Entwürfe freigeben'),
        content: Text(
          'Sollen alle noch nicht freigegebenen Lohnabrechnungen für '
          '${_monthLabel(month)} freigegeben werden?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Freigeben'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context
          .read<PersonalProvider>()
          .finalizeAllDrafts(month.year, month.month);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
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
                label: record.status.label,
                tone: _payrollStatusTone(record.status),
                filled: true,
              ),
              SizedBox(width: context.spacing.xs),
              AppStatusBadge(
                label: record.kind == PayrollEmploymentKind.minijob
                    ? 'Minijob'
                    : record.taxClass.shortLabel,
                tone: AppStatusTone.neutral,
                filled: true,
              ),
              if (record.journalEntryId != null) ...[
                SizedBox(width: context.spacing.xs),
                const AppStatusBadge(
                  label: 'Gebucht',
                  tone: AppStatusTone.success,
                  filled: true,
                ),
              ],
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
          Row(
            children: [
              PopupMenuButton<PayrollStatus>(
                tooltip: 'Status ändern',
                onSelected: (status) async {
                  try {
                    await personal.setPayrollStatus(record, status);
                  } catch (error) {
                    if (context.mounted) _showError(context, error);
                  }
                },
                itemBuilder: (_) => [
                  for (final status in PayrollStatus.values)
                    PopupMenuItem(
                      value: status,
                      enabled: status != record.status,
                      child: Row(
                        children: [
                          Icon(
                            status == record.status
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 18,
                          ),
                          SizedBox(width: context.spacing.sm),
                          Text(status.label),
                        ],
                      ),
                    ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flag_outlined, size: 18),
                    SizedBox(width: context.spacing.xs),
                    Text('Status', style: theme.textTheme.labelLarge),
                    const Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => ExportService.exportPayrollPdf(
                  record: record,
                  employeeName: name,
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF'),
              ),
            ],
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

/// Read-only Soll/Ist-Zeitkonto des gewählten Mitarbeiters im Abrechnungsmonat
/// (H-B2). Soll aus dem SollzeitProfile, Ist aus den WorkEntries (einzige
/// Ist-Quelle — keine Mantelzeit).
class _ZeitkontoCard extends StatelessWidget {
  const _ZeitkontoCard({required this.result});

  final ZeitkontoResult result;

  String _h(double hours) => '${hours.toStringAsFixed(1)} h';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saldo = result.saldoHours;
    final saldoColor = saldo > 0
        ? theme.appColors.success
        : (saldo < 0 ? theme.appColors.warning : theme.colorScheme.onSurface);
    final saldoText = '${saldo >= 0 ? '+' : ''}${_h(saldo)}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_outlined,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('Zeitkonto (Monat)',
                  style: theme.textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 8),
          if (!result.hasSollProfile)
            Text(
              'Kein Sollzeit-Profil hinterlegt – nur Ist (${_h(result.istHours)}).',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else
            Row(
              children: [
                Expanded(
                    child: _AmountColumn(label: 'Soll', value: _h(result.sollHours))),
                Expanded(
                    child: _AmountColumn(label: 'Ist', value: _h(result.istHours))),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Saldo',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      Text(saldoText,
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800, color: saldoColor)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
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
          _EmployeeStammdatenCard(member: member),
          SizedBox(height: spacing.lg),
          _EmployeeHrCard(member: member),
          SizedBox(height: spacing.lg),
          _UrlaubskontoCard(member: member, jahr: month.year),
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

  /// Itemisierte Zusatz-Lohnzeilen (M-L): Zulagen/§3b/VwL/Einmalzahlungen.
  /// Additiv/informativ — Brutto/Netto bleiben die Einzelfelder.
  late List<PayrollLine> _lines;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _lines = [...?existing?.lines];
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
    final personal = context.read<PersonalProvider>();
    final profile = personal.profileForUser(userId);
    if (profile == null) return;
    _taxClass = profile.taxClass;
    _kind = profile.kind;
    _churchTax = profile.churchTax;
    // Bundesland: Lohn-Stammdaten zuerst, sonst aus dem Primärstandort
    // vorbefüllen (H-C3, nur Vorschlag — der gespeicherte PayrollRecord friert
    // den bestätigten Wert als Snapshot ein). Stabile siteId, kein siteName.
    final profileState = profile.federalState?.trim();
    _federalState = (profileState != null && profileState.isNotEmpty)
        ? profile.federalState
        : personal.federalStateForUserPrimarySite(userId);
    if (_gross.text.trim().isNotEmpty) return;
    // Stundenlöhner (Vertrag salaryKind == hourly): Brutto aus
    // Stunden × Stundenlohn vorschlagen statt aus dem Festgehalt-Stammwert
    // (H-B3). Festgehalt-Verträge nutzen weiter monthlyGrossCents.
    final contract = personal.contractForUser(userId);
    if (contract?.salaryKind == SalaryKind.hourly) {
      final suggestion = _grossFromHours(userId);
      if (suggestion != null && suggestion > 0) {
        _gross.text = _eurosToInput(suggestion);
        return;
      }
    }
    final gross = profile.monthlyGrossCents;
    if (gross != null && gross > 0) {
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

  // Sätze des **Abrechnungs-Periodenjahres** (nicht der Wall-Clock!), damit eine
  // rück-/vordatierte Abrechnung die org-Override + defaults<jahr> des richtigen
  // Jahres trifft (z. B. Dezember-2025-Lauf im Januar 2026).
  PayrollSettings get _settings =>
      context.read<PersonalProvider>().effectivePayrollSettings(widget.month.year);

  /// Stammakte des aktuell gewählten Mitarbeiters (für genauere Lohnparameter:
  /// Kinder, PV-Kinderlosenzuschlag, kassenindividueller KV-Zusatzbeitrag).
  EmployeeProfile? get _employeeProfile {
    final userId = _userId;
    if (userId == null) return null;
    return context.read<PersonalProvider>().employeeProfileForUser(userId);
  }

  PayrollResult? get _result {
    final cents = _parseEuroToCents(_gross.text);
    if (cents == null) return null;
    final profile = _employeeProfile;
    final userId = _userId;
    final personal = context.read<PersonalProvider>();
    // Kinderzähler-Einzelquelle (§4.4): gepflegte Kinder schlagen childrenCount.
    final kinderzahl = userId == null
        ? (profile?.childrenCount ?? 0)
        : personal.effektiveKinderzahl(userId);
    return PayrollCalculator.calculate(
      grossCents: cents,
      taxClass: _taxClass,
      churchTax: _churchTax,
      federalState: _federalState,
      kind: _kind,
      settings: _settings,
      childCount: kinderzahl,
      pvChildless: _pvChildless(profile, _hatKinderEigenschaft(userId, profile)),
      healthAdditionalRateOverride: _kvSurchargeOverride(profile),
    );
  }

  /// Elterneigenschaft (für den PV-Kinderlosenzuschlag, § 55 Abs. 3 SGB XI):
  /// entfällt der Zuschlag bei **nachgewiesener** Elternschaft – unabhängig vom
  /// Kinderfreibetrag-Zähler (auch erwachsene Kinder ohne `zaehltFuerFreibetrag`
  /// begründen Elternschaft). Daher NICHT an [effektiveKinderzahl] koppeln.
  bool _hatKinderEigenschaft(String? userId, EmployeeProfile? profile) {
    if (userId != null &&
        context.read<PersonalProvider>().hatGepflegteKinder(userId)) {
      return true;
    }
    return (profile?.childrenCount ?? 0) > 0;
  }

  /// PV-Kinderlosenzuschlag: nur kinderlos UND nachweislich ab 23 Jahren.
  /// Ohne Stammakte oder ohne hinterlegtes Geburtsdatum konservativ kein
  /// Zuschlag – wir berechnen keinen Abzug, dessen Altersvoraussetzung wir nicht
  /// belegen können (mit Geburtsdatum greift er automatisch).
  bool _pvChildless(EmployeeProfile? profile, bool hatKinderEigenschaft) {
    if (profile == null || hatKinderEigenschaft) return false;
    final birth = profile.birthDate;
    if (birth == null) return false;
    final now = DateTime.now();
    var age = now.year - birth.year;
    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) {
      age--;
    }
    return age >= 23;
  }

  /// Brutto-Herleitungs-Hinweis (§5.6/§6.5): nur für Stundenlöhner, zeigt die
  /// Rechnung „Stunden × Stundenlohn".
  String? get _bruttoHerleitungHinweis {
    final userId = _userId;
    if (userId == null) return null;
    final contract = context.read<PersonalProvider>().contractForUser(userId);
    if (contract == null || contract.salaryKind != SalaryKind.hourly) {
      return null;
    }
    final rate = contract.hourlyRate;
    if (rate <= 0) return null;
    final rateStr = '${_eurosToInput(rate)} €';
    final hours = _hoursForUser(widget.monthEntries, userId);
    if (hours <= 0) {
      return 'Stundenlohn $rateStr/h — noch keine erfassten Stunden in diesem Monat.';
    }
    final cents = (hours * rate * 100).round();
    return 'Brutto-Herleitung (§5.6): ${hours.toStringAsFixed(2)} h × '
        '$rateStr/h = ${_euro(cents)}';
  }

  /// Kassenindividueller KV-Zusatzbeitrag aus der Stammakte als Bruchteil.
  double? _kvSurchargeOverride(EmployeeProfile? profile) {
    final percent = profile?.healthInsuranceSurchargePercent;
    if (percent == null) return null;
    return percent / 100.0;
  }

  /// Kurzer Transparenz-Hinweis, welche Lohnparameter aus der Stammakte
  /// stammen (oder null, wenn nichts Relevantes hinterlegt ist).
  String? get _stammaktenHinweis {
    final profile = _employeeProfile;
    if (profile == null) return null;
    final userId = _userId;
    final kinderzahl = userId == null
        ? profile.childrenCount
        : context.read<PersonalProvider>().effektiveKinderzahl(userId);
    final parts = <String>[];
    if (kinderzahl > 0) {
      parts.add('$kinderzahl ${kinderzahl == 1 ? 'Kind' : 'Kinder'}');
    } else if (_pvChildless(profile, _hatKinderEigenschaft(userId, profile))) {
      parts.add('PV-Kinderlosenzuschlag');
    }
    final kv = profile.healthInsuranceSurchargePercent;
    if (kv != null) parts.add('KV-Zusatz ${_formatPercent(kv)}');
    if (parts.isEmpty) return null;
    return 'Aus Stammakte berücksichtigt: ${parts.join(' · ')}';
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
            if (_userId != null) ...[
              SizedBox(height: spacing.md),
              _ZeitkontoCard(
                result: context.read<PersonalProvider>().zeitkontoFor(
                      _userId!,
                      widget.month.year,
                      widget.month.month,
                      widget.monthEntries,
                    ),
              ),
            ],
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
            if (_bruttoHerleitungHinweis != null) ...[
              SizedBox(height: spacing.sm),
              AppStatusBanner(
                icon: Icons.functions,
                tone: AppStatusTone.info,
                message: _bruttoHerleitungHinweis!,
              ),
            ],
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
            if (_stammaktenHinweis != null) ...[
              SizedBox(height: spacing.sm),
              AppStatusBanner(
                icon: Icons.badge_outlined,
                tone: AppStatusTone.info,
                message: _stammaktenHinweis!,
              ),
            ],
            SizedBox(height: spacing.md),
            _LohnzeilenEditor(
              lines: _lines,
              onAdd: _addLine,
              onRemove: (index) => setState(() => _lines.removeAt(index)),
            ),
            if (result != null) ...[
              SizedBox(height: spacing.sm),
              _PayrollBreakdown(result: result, lines: _lines),
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
    final userId = _userId;
    if (userId == null) return;
    final gross = _grossFromHours(userId) ?? 0;
    setState(() => _gross.text = _eurosToInput(gross));
  }

  /// Brutto-Vorschlag (Euro) aus `Stunden × Stundenlohn` des aktiven Vertrags;
  /// ohne erfasste Stunden Fallback auf `Stundenlohn × Wochenstunden × 4,33`.
  /// `null`, wenn kein Stundensatz hinterlegt ist (H-B3-Baustein).
  double? _grossFromHours(String userId) {
    final contract = context.read<PersonalProvider>().contractForUser(userId);
    final rate = contract?.hourlyRate ?? 0;
    if (rate <= 0) return null;
    final hours = _hoursForUser(widget.monthEntries, userId);
    if (hours > 0) return hours * rate;
    if (contract != null) return rate * contract.weeklyHours * 4.33;
    return null;
  }

  String _eurosToInput(double euros) =>
      euros.toStringAsFixed(2).replaceAll('.', ',');

  /// Öffnet den Lohnzeilen-Editor und fügt die erzeugte Zeile hinzu.
  Future<void> _addLine() async {
    final personal = context.read<PersonalProvider>();
    final userId = _userId;
    final contract = userId == null ? null : personal.contractForUser(userId);
    final line = await showAppBottomSheet<PayrollLine>(
      context: context,
      builder: (_) => _PayLineEditorSheet(
        katalog: personal.activePayLineTypes,
        defaultStundenlohnCents: ((contract?.hourlyRate ?? 0) * 100).round(),
        // §39b-Vorschau für Einmalzahlungen braucht das laufende Brutto +
        // Steuerparameter (Richtwert).
        regularMonthlyGrossCents: _parseEuroToCents(_gross.text) ?? 0,
        settings: _settings,
        taxClass: _taxClass,
        churchTax: _churchTax,
        federalState: _federalState,
        childCount:
            userId == null ? 0 : personal.effektiveKinderzahl(userId),
        kvSurchargeOverride: _kvSurchargeOverride(_employeeProfile),
      ),
    );
    if (line != null && mounted) {
      setState(() => _lines.add(line));
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final result = _result;
    if (result == null || _userId == null) return;
    setState(() => _saving = true);
    final personal = context.read<PersonalProvider>();
    final record = result
        .buildRecord(
          id: widget.existing?.id,
          orgId: '',
          userId: _userId!,
          periodYear: widget.month.year,
          periodMonth: widget.month.month,
          taxClass: _taxClass,
          churchTax: _churchTax,
          federalState: _federalState,
        )
        .copyWith(lines: _lines);
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
      // Audit-Logging erfolgt zentral in PersonalProvider.savePayrollRecord.
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
  const _PayrollBreakdown({required this.result, this.lines = const []});

  final PayrollResult result;
  final List<PayrollLine> lines;

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
          if (lines.isNotEmpty) ...[
            const Divider(),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Lohnzeilen (zusätzlich, Richtwert)',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            SizedBox(height: context.spacing.xxs),
            for (final line in lines) _PayLineRow(line: line),
          ],
          SizedBox(height: context.spacing.xs),
          if (result.employerLeviesTotalCents > 0)
            row('AG-Umlagen (U1/U2/InsO/UV)', result.employerLeviesTotalCents,
                color: theme.colorScheme.onSurfaceVariant),
          row('Arbeitgeber-Gesamtkosten', result.employerTotalCents,
              color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// Eine Zeile der Lohnzeilen-Anzeige (Name + Art-Chip + steuerfrei/SV-frei-
/// Marker + signierter Betrag).
class _PayLineRow extends StatelessWidget {
  const _PayLineRow({required this.line});

  final PayrollLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final marker = <String>[
      if (line.effektivSteuerfreiCents > 0)
        'st.frei ${_euro(line.effektivSteuerfreiCents)}',
      if (line.effektivSvFreiCents > 0)
        'SV-frei ${_euro(line.effektivSvFreiCents)}',
    ].join(' · ');
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${line.kind.label}: ${line.name}',
                    style: theme.textTheme.bodyMedium),
                if (marker.isNotEmpty)
                  Text(marker,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: appColors.success)),
              ],
            ),
          ),
          Text(
            _euro(line.amountCents),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: line.amountCents < 0 ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Lohn-Einstellungen ───────────────────────────

/// Admin-Editor für die org-/jahr-spezifische Lohn-Konfiguration
/// (`payrollConfig/{jahr}`): SV-/AG-Sätze **inkl. Arbeitgeber-Umlagen**
/// (U1/U2/InsO/UV) und Grenzwerte. Ohne hinterlegtes Dokument greifen die
/// gesetzlichen Richtwert-Defaults; Speichern legt die org-Überschreibung an.
class _OrgPayrollSettingsSheet extends StatefulWidget {
  const _OrgPayrollSettingsSheet({required this.jahr});

  final int jahr;

  @override
  State<_OrgPayrollSettingsSheet> createState() =>
      _OrgPayrollSettingsSheetState();
}

class _OrgPayrollSettingsSheetState extends State<_OrgPayrollSettingsSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _minWage;
  late final TextEditingController _bbgKvPv;
  late final TextEditingController _bbgRvAlv;
  late final TextEditingController _minijob;
  late final TextEditingController _health;
  late final TextEditingController _healthAdd;
  late final TextEditingController _care;
  late final TextEditingController _pension;
  late final TextEditingController _unemployment;
  late final TextEditingController _u1;
  late final TextEditingController _u2;
  late final TextEditingController _inso;
  late final TextEditingController _uv;
  late bool _u1Applies;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final personal = context.read<PersonalProvider>();
    final s = personal.effectivePayrollSettings(widget.jahr);
    _minWage = TextEditingController(text: _centsToInput(s.minimumHourlyWageCents));
    _bbgKvPv = TextEditingController(text: _centsToInput(s.bbgKvPvMonthlyCents));
    _bbgRvAlv = TextEditingController(text: _centsToInput(s.bbgRvAlvMonthlyCents));
    _minijob = TextEditingController(text: _centsToInput(s.minijobCeilingCents));
    _health = TextEditingController(text: _rateToPercentInput(s.healthRate));
    _healthAdd =
        TextEditingController(text: _rateToPercentInput(s.healthAdditionalRate));
    _care = TextEditingController(text: _rateToPercentInput(s.careRate));
    _pension = TextEditingController(text: _rateToPercentInput(s.pensionRate));
    _unemployment =
        TextEditingController(text: _rateToPercentInput(s.unemploymentRate));
    _u1 = TextEditingController(text: _rateToPercentInput(s.umlageU1Rate));
    _u2 = TextEditingController(text: _rateToPercentInput(s.umlageU2Rate));
    _inso =
        TextEditingController(text: _rateToPercentInput(s.insolvenzgeldumlageRate));
    _uv = TextEditingController(text: _rateToPercentInput(s.uvRate));
    _u1Applies = s.u1Applies;
  }

  @override
  void dispose() {
    for (final c in [
      _minWage, _bbgKvPv, _bbgRvAlv, _minijob, _health, _healthAdd,
      _care, _pension, _unemployment, _u1, _u2, _inso, _uv,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final personal = context.watch<PersonalProvider>();
    final hasOverride = personal.orgPayrollSettingsForYear(widget.jahr) != null;

    return AppBottomSheetScaffold(
      title: 'Lohn-Einstellungen ${widget.jahr}',
      subtitle: hasOverride
          ? 'Org-Überschreibung · Richtwert'
          : 'Gesetzliche Defaults · Richtwert',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppStatusBanner(
              icon: Icons.info_outline,
              tone: AppStatusTone.warning,
              message: 'Unverbindliche Richtwerte – Sätze vor dem Lohnlauf '
                  'prüfen/aktualisieren. Einzelne SV-Sätze für 2026 sind noch '
                  'Platzhalter (2025er-Werte); die Umlagen U1/U2/InsO/UV sind '
                  'kassen-/BG-individuell.',
            ),
            SizedBox(height: spacing.md),
            _sectionLabel('Arbeitgeber-Umlagen'),
            SizedBox(height: spacing.xs),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('U1-Umlage (Lohnfortzahlung)'),
              subtitle: const Text('i. d. R. nur Betriebe bis ~30 Mitarbeiter'),
              value: _u1Applies,
              onChanged: (value) => setState(() => _u1Applies = value),
            ),
            if (_u1Applies) _percentField('U1-Satz (%)', _u1),
            if (_u1Applies) SizedBox(height: spacing.sm),
            _percentField('U2-Satz – Mutterschutz (%)', _u2),
            SizedBox(height: spacing.sm),
            _percentField('Insolvenzgeldumlage (%)', _inso),
            SizedBox(height: spacing.sm),
            _percentField('UV-Beitrag – Unfallversicherung (%)', _uv),
            SizedBox(height: spacing.lg),
            _sectionLabel('Sozialversicherungssätze'),
            SizedBox(height: spacing.sm),
            _percentField('Krankenversicherung gesamt (%)', _health),
            SizedBox(height: spacing.sm),
            _percentField('KV-Zusatzbeitrag Ø (%)', _healthAdd),
            SizedBox(height: spacing.sm),
            _percentField('Pflegeversicherung gesamt (%)', _care),
            SizedBox(height: spacing.sm),
            _percentField('Rentenversicherung gesamt (%)', _pension),
            SizedBox(height: spacing.sm),
            _percentField('Arbeitslosenversicherung gesamt (%)', _unemployment),
            SizedBox(height: spacing.lg),
            _sectionLabel('Grenzwerte'),
            SizedBox(height: spacing.sm),
            _euroField('Mindestlohn (€/h)', _minWage),
            SizedBox(height: spacing.sm),
            _euroField('Minijob-Grenze (€/Monat)', _minijob),
            SizedBox(height: spacing.sm),
            _euroField('BBG KV/PV (€/Monat)', _bbgKvPv),
            SizedBox(height: spacing.sm),
            _euroField('BBG RV/ALV (€/Monat)', _bbgRvAlv),
            SizedBox(height: spacing.lg),
            Row(
              children: [
                if (hasOverride)
                  TextButton.icon(
                    onPressed: _saving ? null : _reset,
                    icon: const Icon(Icons.restore),
                    label: const Text('Defaults'),
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

  Widget _sectionLabel(String text) =>
      Text(text, style: Theme.of(context).textTheme.titleSmall);

  Widget _percentField(String label, TextEditingController controller) {
    return AppFormField(
      controller: controller,
      label: label,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      validator: (value) =>
          _percentInputToRate(value ?? '') == null ? 'Ungültig' : null,
    );
  }

  Widget _euroField(String label, TextEditingController controller) {
    return AppFormField(
      controller: controller,
      label: label,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      validator: (value) =>
          _parseEuroToCents(value ?? '') == null ? 'Ungültig' : null,
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final personal = context.read<PersonalProvider>();
    final existing = personal.orgPayrollSettingsForYear(widget.jahr);
    final base = personal.effectivePayrollSettings(widget.jahr);
    final updated = base.copyWith(
      year: widget.jahr,
      minimumHourlyWageCents: _parseEuroToCents(_minWage.text),
      bbgKvPvMonthlyCents: _parseEuroToCents(_bbgKvPv.text),
      bbgRvAlvMonthlyCents: _parseEuroToCents(_bbgRvAlv.text),
      minijobCeilingCents: _parseEuroToCents(_minijob.text),
      healthRate: _percentInputToRate(_health.text),
      healthAdditionalRate: _percentInputToRate(_healthAdd.text),
      careRate: _percentInputToRate(_care.text),
      pensionRate: _percentInputToRate(_pension.text),
      unemploymentRate: _percentInputToRate(_unemployment.text),
      umlageU1Rate: _percentInputToRate(_u1.text),
      umlageU2Rate: _percentInputToRate(_u2.text),
      insolvenzgeldumlageRate: _percentInputToRate(_inso.text),
      uvRate: _percentInputToRate(_uv.text),
      u1Applies: _u1Applies,
    );
    final config = OrgPayrollSettings(
      id: existing?.id,
      orgId: existing?.orgId ?? '',
      jahr: widget.jahr,
      settings: updated,
      createdByUid: existing?.createdByUid,
      createdAt: existing?.createdAt,
      updatedAt: existing?.updatedAt,
    );
    try {
      await personal.saveOrgPayrollSettings(config);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $error')),
      );
    }
  }

  Future<void> _reset() async {
    setState(() => _saving = true);
    final personal = context.read<PersonalProvider>();
    try {
      await personal.deleteOrgPayrollSettings(widget.jahr);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Zurücksetzen fehlgeschlagen: $error')),
      );
    }
  }
}

// ─────────────────────────── Stammakte (HR) ───────────────────────────────

/// Read-only Stammdaten-Karte im Mitarbeiter-Detail mit „Erfassen/Bearbeiten".
/// Wiederverwendbares Datums-Auswahlfeld (de_DE) mit Löschen.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final fd = firstDate ?? DateTime(1940);
        final ld = lastDate ?? DateTime(now.year + 10);
        final init = value ?? DateTime(now.year, now.month);
        // Gespeicherten Wert ins Fenster klemmen, sonst wirft showDatePicker
        // (z. B. Geburtstag vor firstDate bei Bestands-/Importdaten).
        final clamped = init.isBefore(fd) ? fd : (init.isAfter(ld) ? ld : init);
        final picked = await showDatePicker(
          context: context,
          initialDate: clamped,
          firstDate: fd,
          lastDate: ld,
          locale: const Locale('de', 'DE'),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today_outlined, size: 18)
              : IconButton(
                  tooltip: 'Löschen',
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => onChanged(null),
                ),
        ),
        child: Text(
          value == null ? 'Nicht gesetzt' : _formatDate(value!),
          style: value == null
              ? theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)
              : theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// Sub-Sektionen der Mitarbeiter-Stammakte (M-H): Kinder (lohnsteuerlich),
/// Qualifikationen (Gültigkeit) und Ausbildung. Alle admin-only.
class _EmployeeHrCard extends StatelessWidget {
  const _EmployeeHrCard({required this.member});

  final AppUserProfile member;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final spacing = context.spacing;
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final uid = member.uid;
    final kinder = personal.childrenForUser(uid);
    final quals = personal.qualificationsForUser(uid);
    final ausbildungen = personal.ausbildungenForUser(uid);
    final now = DateTime.now();

    Widget addButton(VoidCallback onTap) => FilledButton.tonalIcon(
          onPressed: onTap,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Neu'),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionCard(
          title: 'Kinder',
          icon: Icons.child_care_outlined,
          trailing: addButton(() => showAppBottomSheet(
                context: context,
                builder: (_) => _ChildEditorSheet(member: member),
              )),
          child: kinder.isEmpty
              ? const _InlineEmpty(
                  icon: Icons.child_care_outlined,
                  message: 'Keine Kinder erfasst. Lohnsteuerlicher Kinderzähler '
                      'kommt aus „Kinder erfasst", sobald welche angelegt sind.',
                )
              : Column(
                  children: [
                    for (final kind in kinder)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.face_outlined),
                        title: Text(kind.anzeigeName),
                        subtitle: Text([
                          if (kind.geburtstag != null)
                            '* ${_formatDate(kind.geburtstag!)}',
                          kind.zaehltFuerFreibetrag
                              ? 'zählt für Freibetrag'
                              : 'ohne Freibetrag',
                        ].join(' · ')),
                        onTap: () => showAppBottomSheet(
                          context: context,
                          builder: (_) =>
                              _ChildEditorSheet(member: member, existing: kind),
                        ),
                      ),
                  ],
                ),
        ),
        SizedBox(height: spacing.lg),
        AppSectionCard(
          title: 'Qualifikationen',
          icon: Icons.workspace_premium_outlined,
          trailing: addButton(() => showAppBottomSheet(
                context: context,
                builder: (_) => _QualificationEditorSheet(member: member),
              )),
          child: quals.isEmpty
              ? const _InlineEmpty(
                  icon: Icons.workspace_premium_outlined,
                  message: 'Keine Qualifikationen erfasst.',
                )
              : Column(
                  children: [
                    for (final quali in quals)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.verified_outlined),
                        title: Text(quali.qualificationName.isEmpty
                            ? 'Qualifikation'
                            : quali.qualificationName),
                        subtitle: Text([
                          quali.erwerb.label,
                          if (quali.gueltigBis != null)
                            'gültig bis ${_formatDate(quali.gueltigBis!)}',
                        ].join(' · ')),
                        trailing: quali.istGueltig(now)
                            ? null
                            : Icon(Icons.error_outline,
                                size: 18, color: appColors.warning),
                        onTap: () => showAppBottomSheet(
                          context: context,
                          builder: (_) => _QualificationEditorSheet(
                              member: member, existing: quali),
                        ),
                      ),
                  ],
                ),
        ),
        SizedBox(height: spacing.lg),
        AppSectionCard(
          title: 'Ausbildung',
          icon: Icons.school_outlined,
          trailing: addButton(() => showAppBottomSheet(
                context: context,
                builder: (_) => _AusbildungEditorSheet(member: member),
              )),
          child: ausbildungen.isEmpty
              ? const _InlineEmpty(
                  icon: Icons.school_outlined,
                  message: 'Keine Ausbildung erfasst.',
                )
              : Column(
                  children: [
                    for (final a in ausbildungen)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.school_outlined),
                        title: Text(
                            a.bezeichnung.isEmpty ? 'Ausbildung' : a.bezeichnung),
                        subtitle: Text([
                          if (a.beginn != null) _formatDate(a.beginn!),
                          if (a.ende != null) '– ${_formatDate(a.ende!)}',
                        ].join(' ')),
                        onTap: () => showAppBottomSheet(
                          context: context,
                          builder: (_) => _AusbildungEditorSheet(
                              member: member, existing: a),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Editor für ein [EmployeeChild] (anlegen/bearbeiten/löschen).
class _ChildEditorSheet extends StatefulWidget {
  const _ChildEditorSheet({required this.member, this.existing});

  final AppUserProfile member;
  final EmployeeChild? existing;

  @override
  State<_ChildEditorSheet> createState() => _ChildEditorSheetState();
}

class _ChildEditorSheetState extends State<_ChildEditorSheet> {
  late final TextEditingController _vorname;
  late final TextEditingController _name;
  late final TextEditingController _steuerId;
  DateTime? _geburtstag;
  bool _zaehlt = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _vorname = TextEditingController(text: e?.vorname ?? '');
    _name = TextEditingController(text: e?.name ?? '');
    _steuerId = TextEditingController(text: e?.steuerIdKind ?? '');
    _geburtstag = e?.geburtstag;
    _zaehlt = e?.zaehltFuerFreibetrag ?? true;
  }

  @override
  void dispose() {
    _vorname.dispose();
    _name.dispose();
    _steuerId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final now = DateTime.now();
    return AppBottomSheetScaffold(
      title: widget.existing == null ? 'Kind hinzufügen' : 'Kind bearbeiten',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppFormField(controller: _vorname, label: 'Vorname'),
          SizedBox(height: spacing.md),
          AppFormField(controller: _name, label: 'Nachname'),
          SizedBox(height: spacing.md),
          _DateField(
            label: 'Geburtstag',
            value: _geburtstag,
            firstDate: DateTime(1990),
            lastDate: now,
            onChanged: (d) => setState(() => _geburtstag = d),
          ),
          SizedBox(height: spacing.md),
          AppFormField(
            controller: _steuerId,
            label: 'Steuer-ID des Kindes (optional)',
            keyboardType: TextInputType.number,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Zählt für Kinderfreibetrag'),
            value: _zaehlt,
            onChanged: (v) => setState(() => _zaehlt = v),
          ),
          SizedBox(height: spacing.md),
          _EditorActions(
            saving: _saving,
            onDelete: widget.existing == null ? null : _delete,
            onSave: _save,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final personal = context.read<PersonalProvider>();
    final e = widget.existing;
    final child = EmployeeChild(
      id: e?.id,
      orgId: e?.orgId ?? '',
      userId: widget.member.uid,
      vorname: _vorname.text.trim(),
      name: _name.text.trim(),
      steuerIdKind:
          _steuerId.text.trim().isEmpty ? null : _steuerId.text.trim(),
      geburtstag: _geburtstag,
      zaehltFuerFreibetrag: _zaehlt,
      createdByUid: e?.createdByUid,
      createdAt: e?.createdAt,
      updatedAt: e?.updatedAt,
    );
    await _run(() => personal.saveEmployeeChild(child));
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    final personal = context.read<PersonalProvider>();
    await _run(() => personal.deleteEmployeeChild(widget.existing!.id!));
  }

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger
          .showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $error')));
    }
  }
}

/// Editor für eine [EmployeeQualification].
class _QualificationEditorSheet extends StatefulWidget {
  const _QualificationEditorSheet({required this.member, this.existing});

  final AppUserProfile member;
  final EmployeeQualification? existing;

  @override
  State<_QualificationEditorSheet> createState() =>
      _QualificationEditorSheetState();
}

class _QualificationEditorSheetState extends State<_QualificationEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _bemerkung;
  QualiErwerb _erwerb = QualiErwerb.vorab;
  DateTime? _erworbenAm;
  DateTime? _gueltigBis;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.qualificationName ?? '');
    _bemerkung = TextEditingController(text: e?.bemerkung ?? '');
    _erwerb = e?.erwerb ?? QualiErwerb.vorab;
    _erworbenAm = e?.erworbenAm;
    _gueltigBis = e?.gueltigBis;
  }

  @override
  void dispose() {
    _name.dispose();
    _bemerkung.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return AppBottomSheetScaffold(
      title: widget.existing == null
          ? 'Qualifikation hinzufügen'
          : 'Qualifikation bearbeiten',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppFormField(
              controller: _name,
              label: 'Bezeichnung',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null,
            ),
            SizedBox(height: spacing.md),
            Text('Erwerb', style: Theme.of(context).textTheme.labelLarge),
            SizedBox(height: spacing.xs),
            AppSegmented<QualiErwerb>(
              segments: [
                for (final e in QualiErwerb.values)
                  AppSegment(value: e, label: e.label),
              ],
              selected: _erwerb,
              onChanged: (v) => setState(() => _erwerb = v),
            ),
            SizedBox(height: spacing.md),
            _DateField(
              label: 'Erworben am',
              value: _erworbenAm,
              onChanged: (d) => setState(() => _erworbenAm = d),
            ),
            SizedBox(height: spacing.md),
            _DateField(
              label: 'Gültig bis (optional)',
              value: _gueltigBis,
              onChanged: (d) => setState(() => _gueltigBis = d),
            ),
            SizedBox(height: spacing.md),
            AppFormField(controller: _bemerkung, label: 'Bemerkung (optional)'),
            SizedBox(height: spacing.md),
            _EditorActions(
              saving: _saving,
              onDelete: widget.existing == null ? null : _delete,
              onSave: _save,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final personal = context.read<PersonalProvider>();
    final e = widget.existing;
    final quali = EmployeeQualification(
      id: e?.id,
      orgId: e?.orgId ?? '',
      userId: widget.member.uid,
      qualificationId: e?.qualificationId,
      qualificationName: _name.text.trim(),
      erwerb: _erwerb,
      erworbenAm: _erworbenAm,
      gueltigBis: _gueltigBis,
      bemerkung:
          _bemerkung.text.trim().isEmpty ? null : _bemerkung.text.trim(),
      createdByUid: e?.createdByUid,
      createdAt: e?.createdAt,
      updatedAt: e?.updatedAt,
    );
    await _run(() => personal.saveEmployeeQualification(quali));
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    final personal = context.read<PersonalProvider>();
    await _run(() => personal.deleteEmployeeQualification(widget.existing!.id!));
  }

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger
          .showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $error')));
    }
  }
}

/// Editor für eine [EmployeeAusbildung].
class _AusbildungEditorSheet extends StatefulWidget {
  const _AusbildungEditorSheet({required this.member, this.existing});

  final AppUserProfile member;
  final EmployeeAusbildung? existing;

  @override
  State<_AusbildungEditorSheet> createState() => _AusbildungEditorSheetState();
}

class _AusbildungEditorSheetState extends State<_AusbildungEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _bezeichnung;
  late final TextEditingController _noteZwischen;
  late final TextEditingController _noteAbschluss;
  late final TextEditingController _bemerkung;
  DateTime? _beginn;
  DateTime? _ende;
  String? _ausbilderUserId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _bezeichnung = TextEditingController(text: e?.bezeichnung ?? '');
    _noteZwischen = TextEditingController(text: e?.noteZwischen ?? '');
    _noteAbschluss = TextEditingController(text: e?.noteAbschluss ?? '');
    _bemerkung = TextEditingController(text: e?.bemerkung ?? '');
    _beginn = e?.beginn;
    _ende = e?.ende;
    _ausbilderUserId = e?.ausbilderUserId;
  }

  @override
  void dispose() {
    _bezeichnung.dispose();
    _noteZwischen.dispose();
    _noteAbschluss.dispose();
    _bemerkung.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final personal = context.read<PersonalProvider>();
    final others =
        personal.members.where((m) => m.uid != widget.member.uid).toList();
    return AppBottomSheetScaffold(
      title: widget.existing == null
          ? 'Ausbildung hinzufügen'
          : 'Ausbildung bearbeiten',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppFormField(
              controller: _bezeichnung,
              label: 'Bezeichnung',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null,
            ),
            SizedBox(height: spacing.md),
            _DateField(
              label: 'Beginn',
              value: _beginn,
              onChanged: (d) => setState(() => _beginn = d),
            ),
            SizedBox(height: spacing.md),
            _DateField(
              label: 'Ende (optional)',
              value: _ende,
              onChanged: (d) => setState(() => _ende = d),
            ),
            SizedBox(height: spacing.md),
            DropdownButtonFormField<String?>(
              initialValue: _ausbilderUserId,
              decoration:
                  const InputDecoration(labelText: 'Ausbilder:in (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('—')),
                for (final m in others)
                  DropdownMenuItem(value: m.uid, child: Text(m.displayName)),
              ],
              onChanged: (v) => setState(() => _ausbilderUserId = v),
            ),
            SizedBox(height: spacing.md),
            AppFormField(
                controller: _noteZwischen, label: 'Zwischennote (optional)'),
            SizedBox(height: spacing.md),
            AppFormField(
                controller: _noteAbschluss, label: 'Abschlussnote (optional)'),
            SizedBox(height: spacing.md),
            AppFormField(controller: _bemerkung, label: 'Bemerkung (optional)'),
            SizedBox(height: spacing.md),
            _EditorActions(
              saving: _saving,
              onDelete: widget.existing == null ? null : _delete,
              onSave: _save,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final personal = context.read<PersonalProvider>();
    final e = widget.existing;
    String? trimmed(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final ausbildung = EmployeeAusbildung(
      id: e?.id,
      orgId: e?.orgId ?? '',
      userId: widget.member.uid,
      bezeichnung: _bezeichnung.text.trim(),
      beginn: _beginn,
      ende: _ende,
      ausbilderUserId: _ausbilderUserId,
      noteZwischen: trimmed(_noteZwischen),
      noteAbschluss: trimmed(_noteAbschluss),
      bemerkung: trimmed(_bemerkung),
      createdByUid: e?.createdByUid,
      createdAt: e?.createdAt,
      updatedAt: e?.updatedAt,
    );
    await _run(() => personal.saveEmployeeAusbildung(ausbildung));
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    final personal = context.read<PersonalProvider>();
    await _run(() => personal.deleteEmployeeAusbildung(widget.existing!.id!));
  }

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger
          .showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $error')));
    }
  }
}

/// Speichern/Löschen-Aktionszeile für die HR-Sub-Editoren.
class _EditorActions extends StatelessWidget {
  const _EditorActions({
    required this.saving,
    required this.onSave,
    this.onDelete,
  });

  final bool saving;
  final VoidCallback onSave;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onDelete != null)
          TextButton.icon(
            onPressed: saving ? null : onDelete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Löschen'),
          ),
        const Spacer(),
        FilledButton(
          onPressed: saving ? null : onSave,
          child: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Speichern'),
        ),
      ],
    );
  }
}

/// Urlaubskonto-Aufstellung (M-U) im Mitarbeiter-Detail: Anspruch/Vortrag/
/// Verfall/genommen/geplant/Resturlaub mit +/−/=-Logik, admin-Bearbeitung von
/// Vortrag (UrlaubskontoJahr) und manuellen Anpassungen.
class _UrlaubskontoCard extends StatelessWidget {
  const _UrlaubskontoCard({required this.member, required this.jahr});

  final AppUserProfile member;
  final int jahr;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final spacing = context.spacing;
    final report = personal.urlaubsReportFor(member.uid, jahr);
    final konto = personal.urlaubskontoFor(member.uid, jahr);
    final anpassungen = personal.urlaubsanpassungenForUser(member.uid, jahr: jahr);
    final krankheitImUrlaub = personal.krankheitImUrlaubFor(member.uid, jahr);
    final krankheitTage =
        krankheitImUrlaub.fold<double>(0, (s, k) => s + k.tage);

    Widget zeile(String label, double tage,
        {bool bold = false, Color? color, bool divider = false}) {
      final style = (bold
              ? theme.textTheme.titleSmall
              : theme.textTheme.bodyMedium)
          ?.copyWith(color: color);
      return Padding(
        padding: EdgeInsets.symmetric(vertical: divider ? 0 : spacing.xs / 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: style),
            Text('${_formatTage(tage)} Tage', style: style),
          ],
        ),
      );
    }

    final hinweisFehlt = report.vortragVorjahr > 0 &&
        (konto == null || konto.hinweisErteiltAm == null);

    return AppSectionCard(
      title: 'Urlaubskonto $jahr',
      icon: Icons.beach_access_outlined,
      trailing: Wrap(
        spacing: spacing.xs,
        children: [
          IconButton(
            tooltip: 'Vortrag/Verfall bearbeiten',
            icon: const Icon(Icons.tune),
            onPressed: () => showAppBottomSheet(
              context: context,
              builder: (_) => _UrlaubskontoEditorSheet(
                  member: member, jahr: jahr, existing: konto),
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: () => showAppBottomSheet(
              context: context,
              builder: (_) =>
                  _UrlaubsanpassungEditorSheet(member: member, jahr: jahr),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Anpassung'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          zeile('Jahresanspruch', report.anspruchJahr),
          if (report.vortragVorjahr != 0)
            zeile('+ Vortrag Vorjahr', report.vortragVorjahr),
          if (report.vortragVerfallen != 0)
            zeile('− verfallen', -report.vortragVerfallen,
                color: appColors.warning),
          const Divider(),
          zeile('= Gesamtanspruch', report.anspruchGesamt, bold: true),
          zeile('− genommen', -report.genommen),
          if (report.geplant != 0)
            zeile('− geplant (offen)', -report.geplant,
                color: theme.colorScheme.onSurfaceVariant),
          const Divider(),
          zeile('= Resturlaub', report.resturlaub,
              bold: true,
              color: report.resturlaub < 0
                  ? appColors.warning
                  : appColors.success),
          if (hinweisFehlt) ...[
            SizedBox(height: spacing.sm),
            const AppStatusBanner(
              icon: Icons.info_outline,
              tone: AppStatusTone.info,
              message: 'Hinweis auf Resturlaub-Verfall nicht dokumentiert → '
                  'kein 31.3.-Verfall (EuGH/BAG). Über „Vortrag bearbeiten" '
                  'das Hinweis-Datum hinterlegen.',
            ),
          ],
          if (krankheitImUrlaub.isNotEmpty) ...[
            SizedBox(height: spacing.sm),
            AppStatusBanner(
              icon: Icons.healing_outlined,
              tone: AppStatusTone.warning,
              message: 'Krankheit im genehmigten Urlaub (§9 BUrlG): '
                  '${_formatTage(krankheitTage)} Tage sind nicht auf den '
                  'Urlaub anzurechnen – über „Anpassung" gutschreiben.',
            ),
          ],
          if (anpassungen.isNotEmpty) ...[
            SizedBox(height: spacing.sm),
            Text('Manuelle Anpassungen',
                style: theme.textTheme.labelLarge),
            for (final a in anpassungen)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                    '${a.tage >= 0 ? '+' : ''}${_formatTage(a.tage)} Tage · ${a.art.label}'),
                subtitle: a.anmerkung == null ? null : Text(a.anmerkung!),
                trailing: IconButton(
                  tooltip: 'Löschen',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => personal.deleteUrlaubsanpassung(a.id!),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Editor für das Jahres-Vortragsdoc (UrlaubskontoJahr).
class _UrlaubskontoEditorSheet extends StatefulWidget {
  const _UrlaubskontoEditorSheet({
    required this.member,
    required this.jahr,
    this.existing,
  });

  final AppUserProfile member;
  final int jahr;
  final UrlaubskontoJahr? existing;

  @override
  State<_UrlaubskontoEditorSheet> createState() =>
      _UrlaubskontoEditorSheetState();
}

class _UrlaubskontoEditorSheetState extends State<_UrlaubskontoEditorSheet> {
  late final TextEditingController _vortrag;
  late final TextEditingController _mehrurlaub;
  DateTime? _verfall;
  DateTime? _hinweis;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _vortrag = TextEditingController(
        text: e == null ? '' : _formatTage(e.vortragVorjahrTage));
    _mehrurlaub = TextEditingController(
        text: e == null ? '' : _formatTage(e.gewaehrterMehrurlaubTage));
    _verfall = e?.vortragVerfaelltAm ?? UrlaubskontoJahr.defaultVerfall(widget.jahr);
    _hinweis = e?.hinweisErteiltAm;
  }

  @override
  void dispose() {
    _vortrag.dispose();
    _mehrurlaub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return AppBottomSheetScaffold(
      title: 'Urlaubskonto ${widget.jahr}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppFormField(
            controller: _vortrag,
            label: 'Vortrag aus Vorjahr (Tage)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
          ),
          SizedBox(height: spacing.md),
          _DateField(
            label: 'Vortrag verfällt am',
            value: _verfall,
            onChanged: (d) => setState(() => _verfall = d),
          ),
          SizedBox(height: spacing.md),
          _DateField(
            label: 'Verfall-Hinweis erteilt am',
            value: _hinweis,
            onChanged: (d) => setState(() => _hinweis = d),
          ),
          Padding(
            padding: EdgeInsets.only(top: spacing.xs),
            child: Text(
              'Ohne dokumentierten Hinweis verfällt der Vortrag NICHT (EuGH/BAG).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          SizedBox(height: spacing.md),
          AppFormField(
            controller: _mehrurlaub,
            label: 'Gewährter Mehrurlaub (Tage)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
          ),
          SizedBox(height: spacing.md),
          _EditorActions(saving: _saving, onSave: _save),
        ],
      ),
    );
  }

  double _parse(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  Future<void> _save() async {
    setState(() => _saving = true);
    final personal = context.read<PersonalProvider>();
    final e = widget.existing;
    final konto = UrlaubskontoJahr(
      id: e?.id,
      orgId: e?.orgId ?? '',
      userId: widget.member.uid,
      jahr: widget.jahr,
      vortragVorjahrTage: _parse(_vortrag),
      vortragVerfaelltAm: _verfall,
      hinweisErteiltAm: _hinweis,
      gewaehrterMehrurlaubTage: _parse(_mehrurlaub),
      createdByUid: e?.createdByUid,
      createdAt: e?.createdAt,
      updatedAt: e?.updatedAt,
    );
    final messenger = ScaffoldMessenger.of(context);
    try {
      await personal.saveUrlaubskontoJahr(konto);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $error')));
    }
  }
}

/// Editor für eine manuelle Urlaubs-Anpassung (Korrektur-Ledger).
class _UrlaubsanpassungEditorSheet extends StatefulWidget {
  const _UrlaubsanpassungEditorSheet(
      {required this.member, required this.jahr});

  final AppUserProfile member;
  final int jahr;

  @override
  State<_UrlaubsanpassungEditorSheet> createState() =>
      _UrlaubsanpassungEditorSheetState();
}

class _UrlaubsanpassungEditorSheetState
    extends State<_UrlaubsanpassungEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _tage = TextEditingController();
  final _anmerkung = TextEditingController();
  UrlaubsAnpassungArt _art = UrlaubsAnpassungArt.allgemein;
  bool _saving = false;

  @override
  void dispose() {
    _tage.dispose();
    _anmerkung.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return AppBottomSheetScaffold(
      title: 'Urlaubs-Anpassung ${widget.jahr}',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppFormField(
              controller: _tage,
              label: 'Tage (− für Abzug)',
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
              ],
              validator: (v) =>
                  double.tryParse((v ?? '').trim().replaceAll(',', '.')) == null
                      ? 'Ungültig'
                      : null,
            ),
            SizedBox(height: spacing.md),
            Text('Art', style: Theme.of(context).textTheme.labelLarge),
            SizedBox(height: spacing.xs),
            AppSegmented<UrlaubsAnpassungArt>(
              segments: [
                for (final a in UrlaubsAnpassungArt.values)
                  AppSegment(value: a, label: a.label),
              ],
              selected: _art,
              onChanged: (v) => setState(() => _art = v),
            ),
            SizedBox(height: spacing.md),
            AppFormField(controller: _anmerkung, label: 'Anmerkung (optional)'),
            SizedBox(height: spacing.md),
            _EditorActions(saving: _saving, onSave: _save),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final personal = context.read<PersonalProvider>();
    final anpassung = Urlaubsanpassung(
      orgId: '',
      userId: widget.member.uid,
      jahr: widget.jahr,
      tage: double.tryParse(_tage.text.trim().replaceAll(',', '.')) ?? 0,
      art: _art,
      anmerkung: _anmerkung.text.trim().isEmpty ? null : _anmerkung.text.trim(),
    );
    final messenger = ScaffoldMessenger.of(context);
    try {
      await personal.saveUrlaubsanpassung(anpassung);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $error')));
    }
  }
}

class _EmployeeStammdatenCard extends StatelessWidget {
  const _EmployeeStammdatenCard({required this.member});

  final AppUserProfile member;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final profile = personal.employeeProfileForUser(member.uid);
    final hasData = profile != null && !profile.isEmpty;

    return AppSectionCard(
      title: 'Stammdaten',
      icon: Icons.badge_outlined,
      trailing: FilledButton.tonalIcon(
        onPressed: () => showAppBottomSheet(
          context: context,
          builder: (_) =>
              _EmployeeProfileEditorSheet(member: member, existing: profile),
        ),
        icon: Icon(hasData ? Icons.edit_outlined : Icons.add, size: 18),
        label: Text(hasData ? 'Bearbeiten' : 'Erfassen'),
      ),
      child: hasData
          ? _StammdatenBody(profile: profile)
          : const _InlineEmpty(
              icon: Icons.badge_outlined,
              message: 'Noch keine Stammdaten hinterlegt.',
            ),
    );
  }
}

class _StammdatenBody extends StatelessWidget {
  const _StammdatenBody({required this.profile});

  final EmployeeProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final spacing = context.spacing;
    final theme = Theme.of(context);
    final personal = context.watch<PersonalProvider>();
    // Sobald ein Sollzeit-Profil existiert, ist dessen `urlaubstageJahr`
    // kanonisch – das alte Feld wäre stille Divergenz (Review-Fund). Dann den
    // aufgelösten Wert (Vorrangregel §5.1) statt `annualVacationDays` zeigen.
    final hatSollzeit = personal.sollzeitProfilesForUser(p.userId).isNotEmpty;
    final String? urlaubAnzeige = hatSollzeit
        ? '${_formatTage(personal.effektiveUrlaubstage(p.userId).tage)} '
            'Tage/Jahr (Sollzeit)'
        : (p.annualVacationDays == null
            ? null
            : '${p.annualVacationDays} Tage/Jahr');

    // Gruppen aus (Überschrift, [(Label, Wert?)…]); leere Zeilen/Gruppen
    // werden ausgeblendet, damit keine „—"-Wüsten entstehen.
    final groups = <(String, List<(String, String?)>)>[
      (
        'Persönlich',
        [
          ('Geburtstag', p.birthDate == null ? null : _formatDate(p.birthDate!)),
          ('Nationalität', p.nationality),
        ],
      ),
      (
        'Anschrift',
        [
          ('Adresse', p.formattedAddress),
          ('Adresszusatz', p.addressExtra),
        ],
      ),
      (
        'Privater Kontakt',
        [
          ('Telefon', p.privatePhone),
          ('Mobil', p.privateMobile),
          ('E-Mail', p.privateEmail),
        ],
      ),
      (
        'Beschäftigung',
        [
          ('Status', p.status.label),
          ('Personalnummer', p.personnelNumber),
          ('Personengruppe', p.personnelGroup?.label),
          ('Eintritt', p.hireDate == null ? null : _formatDate(p.hireDate!)),
          (
            'Probezeit bis',
            p.probationEnd == null ? null : _formatDate(p.probationEnd!)
          ),
          (
            'Befristet bis',
            p.limitedUntil == null ? null : _formatDate(p.limitedUntil!)
          ),
          ('Austritt', p.exitDate == null ? null : _formatDate(p.exitDate!)),
        ],
      ),
      (
        'Lohn & Sozialversicherung',
        [
          ('Familienstand', p.maritalStatus?.label),
          ('Konfession', p.confession?.label),
          (
            'Kinder',
            personal.effektiveKinderzahl(p.userId) > 0
                ? '${personal.effektiveKinderzahl(p.userId)}'
                : null
          ),
          ('Steuer-ID', p.taxId),
          ('SV-Nummer', p.socialSecurityNumber),
          ('Krankenkasse', p.healthInsurance),
          ('Versicherungsart', p.healthInsuranceType?.label),
          (
            'KV-Zusatzbeitrag',
            p.healthInsuranceSurchargePercent == null
                ? null
                : _formatPercent(p.healthInsuranceSurchargePercent!)
          ),
        ],
      ),
      (
        'Bankverbindung',
        [
          ('IBAN', p.iban),
          ('BIC', p.bic),
          ('Kontoinhaber', p.accountHolder),
        ],
      ),
      (
        'Urlaub & Notfall',
        [
          ('Urlaubsanspruch', urlaubAnzeige),
          ('Notfallkontakt', p.emergencyContactName),
          ('Notfall-Telefon', p.emergencyContactPhone),
        ],
      ),
    ];

    bool hasValue(String? v) => v != null && v.trim().isNotEmpty;
    final visibleGroups = [
      for (final g in groups)
        if (g.$2.any((row) => hasValue(row.$2))) g,
    ];

    Widget heading(String text) => Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < visibleGroups.length; i++) ...[
          if (i > 0) SizedBox(height: spacing.md),
          heading(visibleGroups[i].$1),
          SizedBox(height: spacing.xs),
          for (final row in visibleGroups[i].$2)
            if (hasValue(row.$2)) _InfoRow(label: row.$1, value: row.$2!),
        ],
        if (hasValue(p.note)) ...[
          SizedBox(height: spacing.md),
          heading('Notiz'),
          SizedBox(height: spacing.xs),
          Text(p.note!, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Voll-Editor der Personal-Stammakte (admin-only). Baut bei jedem Speichern
/// eine vollständige [EmployeeProfile] frisch aus dem Formular auf (Felder, die
/// leer sind, werden zu null), und überschreibt die Akte (deterministische ID).
class _EmployeeProfileEditorSheet extends StatefulWidget {
  const _EmployeeProfileEditorSheet({required this.member, this.existing});

  final AppUserProfile member;
  final EmployeeProfile? existing;

  @override
  State<_EmployeeProfileEditorSheet> createState() =>
      _EmployeeProfileEditorSheetState();
}

class _EmployeeProfileEditorSheetState
    extends State<_EmployeeProfileEditorSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _salutation;
  late final TextEditingController _title;
  late final TextEditingController _nationality;
  late final TextEditingController _street;
  late final TextEditingController _houseNumber;
  late final TextEditingController _postalCode;
  late final TextEditingController _city;
  late final TextEditingController _addressExtra;
  late final TextEditingController _privatePhone;
  late final TextEditingController _privateMobile;
  late final TextEditingController _privateEmail;
  late final TextEditingController _personnelNumber;
  late final TextEditingController _childrenCount;
  late final TextEditingController _taxId;
  late final TextEditingController _svNumber;
  late final TextEditingController _healthInsurance;
  late final TextEditingController _kvSurcharge;
  late final TextEditingController _iban;
  late final TextEditingController _bic;
  late final TextEditingController _accountHolder;
  late final TextEditingController _vacationDays;
  late final TextEditingController _emergencyName;
  late final TextEditingController _emergencyPhone;
  late final TextEditingController _note;

  List<TextEditingController> get _controllers => [
        _salutation,
        _title,
        _nationality,
        _street,
        _houseNumber,
        _postalCode,
        _city,
        _addressExtra,
        _privatePhone,
        _privateMobile,
        _privateEmail,
        _personnelNumber,
        _childrenCount,
        _taxId,
        _svNumber,
        _healthInsurance,
        _kvSurcharge,
        _iban,
        _bic,
        _accountHolder,
        _vacationDays,
        _emergencyName,
        _emergencyPhone,
        _note,
      ];

  late EmployeeStatus _status;
  PersonnelGroup? _personnelGroup;
  MaritalStatus? _maritalStatus;
  Confession? _confession;
  HealthInsuranceType? _healthInsuranceType;

  DateTime? _birthDate;
  DateTime? _hireDate;
  DateTime? _exitDate;
  DateTime? _probationEnd;
  DateTime? _limitedUntil;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _salutation = TextEditingController(text: e?.salutation ?? '');
    _title = TextEditingController(text: e?.titleAcademic ?? '');
    _nationality = TextEditingController(text: e?.nationality ?? '');
    _street = TextEditingController(text: e?.street ?? '');
    _houseNumber = TextEditingController(text: e?.houseNumber ?? '');
    _postalCode = TextEditingController(text: e?.postalCode ?? '');
    _city = TextEditingController(text: e?.city ?? '');
    _addressExtra = TextEditingController(text: e?.addressExtra ?? '');
    _privatePhone = TextEditingController(text: e?.privatePhone ?? '');
    _privateMobile = TextEditingController(text: e?.privateMobile ?? '');
    _privateEmail = TextEditingController(text: e?.privateEmail ?? '');
    _personnelNumber = TextEditingController(text: e?.personnelNumber ?? '');
    _childrenCount = TextEditingController(
      text: (e?.childrenCount ?? 0) > 0 ? '${e!.childrenCount}' : '',
    );
    _taxId = TextEditingController(text: e?.taxId ?? '');
    _svNumber = TextEditingController(text: e?.socialSecurityNumber ?? '');
    _healthInsurance = TextEditingController(text: e?.healthInsurance ?? '');
    _kvSurcharge = TextEditingController(
      text: e?.healthInsuranceSurchargePercent == null
          ? ''
          : e!.healthInsuranceSurchargePercent!.toString().replaceAll('.', ','),
    );
    _iban = TextEditingController(text: e?.iban ?? '');
    _bic = TextEditingController(text: e?.bic ?? '');
    _accountHolder = TextEditingController(text: e?.accountHolder ?? '');
    _vacationDays = TextEditingController(
      text: e?.annualVacationDays == null ? '' : '${e!.annualVacationDays}',
    );
    _emergencyName = TextEditingController(text: e?.emergencyContactName ?? '');
    _emergencyPhone =
        TextEditingController(text: e?.emergencyContactPhone ?? '');
    _note = TextEditingController(text: e?.note ?? '');

    _status = e?.status ?? EmployeeStatus.aktiv;
    _personnelGroup = e?.personnelGroup;
    _maritalStatus = e?.maritalStatus;
    _confession = e?.confession;
    _healthInsuranceType = e?.healthInsuranceType;
    _birthDate = e?.birthDate;
    _hireDate = e?.hireDate;
    _exitDate = e?.exitDate;
    _probationEnd = e?.probationEnd;
    _limitedUntil = e?.limitedUntil;
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final theme = Theme.of(context);
    final hasExisting = widget.existing != null && !widget.existing!.isEmpty;
    // Migrierter Mitarbeiter (Sollzeit-Profil vorhanden) → Urlaub ist dort
    // kanonisch; das Altfeld read-only zeigen statt editierbar driften zu lassen.
    final personal = context.watch<PersonalProvider>();
    final hatSollzeit =
        personal.sollzeitProfilesForUser(widget.member.uid).isNotEmpty;
    final urlaubKanonisch =
        hatSollzeit ? personal.effektiveUrlaubstage(widget.member.uid) : null;
    // Sobald Kinder als Sub-Entitäten gepflegt sind, ist der Kinderzähler dort
    // kanonisch (§4.4) → Altfeld read-only zeigen (sonst „doppelt editierbar").
    final kinderGepflegt = personal.hatGepflegteKinder(widget.member.uid);
    final kinderzahl = personal.effektiveKinderzahl(widget.member.uid);

    Widget gap() => SizedBox(height: spacing.sm);

    Widget heading(String text) => Padding(
          padding: EdgeInsets.only(top: spacing.md, bottom: spacing.xs),
          child: Text(
            text,
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        );

    Widget field(
      TextEditingController controller,
      String label, {
      TextInputType? keyboardType,
      int maxLines = 1,
      String? hint,
      List<TextInputFormatter>? inputFormatters,
      String? Function(String?)? validator,
    }) =>
        Padding(
          padding: EdgeInsets.only(bottom: spacing.sm),
          child: AppFormField(
            controller: controller,
            label: label,
            hint: hint,
            keyboardType: keyboardType,
            maxLines: maxLines,
            inputFormatters: inputFormatters,
            validator: validator,
          ),
        );

    Widget dateField(
      String label,
      DateTime? value,
      ValueChanged<DateTime?> onChanged, {
      DateTime? firstDate,
      DateTime? lastDate,
    }) {
      final now = DateTime.now();
      return Padding(
        padding: EdgeInsets.only(bottom: spacing.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime(now.year, now.month),
              firstDate: firstDate ?? DateTime(1940),
              lastDate: lastDate ?? DateTime(now.year + 5),
              locale: const Locale('de', 'DE'),
            );
            if (picked != null) onChanged(picked);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              suffixIcon: value == null
                  ? const Icon(Icons.calendar_today_outlined, size: 18)
                  : IconButton(
                      tooltip: 'Löschen',
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => onChanged(null),
                    ),
            ),
            child: Text(
              value == null ? 'Nicht gesetzt' : _formatDate(value),
              style: value == null
                  ? theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)
                  : theme.textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }

    Widget enumDropdown<T>(
      String label,
      T? selected,
      List<T> values,
      String Function(T) labelOf,
      ValueChanged<T?> onChanged,
    ) =>
        Padding(
          padding: EdgeInsets.only(bottom: spacing.sm),
          child: DropdownButtonFormField<T?>(
            initialValue: selected,
            decoration: InputDecoration(labelText: label),
            items: [
              DropdownMenuItem<T?>(value: null, child: const Text('—')),
              for (final v in values)
                DropdownMenuItem<T?>(value: v, child: Text(labelOf(v))),
            ],
            onChanged: onChanged,
          ),
        );

    return AppBottomSheetScaffold(
      title: hasExisting ? 'Stammdaten bearbeiten' : 'Stammdaten erfassen',
      subtitle: widget.member.displayName,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading('Persönlich'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: field(_salutation, 'Anrede')),
                SizedBox(width: spacing.sm),
                Expanded(child: field(_title, 'Titel')),
              ],
            ),
            dateField(
              'Geburtstag',
              _birthDate,
              (d) => setState(() => _birthDate = d),
              firstDate: DateTime(1930),
              lastDate: DateTime.now(),
            ),
            field(_nationality, 'Nationalität'),

            heading('Anschrift'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: field(_street, 'Straße')),
                SizedBox(width: spacing.sm),
                Expanded(child: field(_houseNumber, 'Nr.')),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: field(
                    _postalCode,
                    'PLZ',
                    keyboardType: TextInputType.number,
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(flex: 3, child: field(_city, 'Ort')),
              ],
            ),
            field(_addressExtra, 'Adresszusatz'),

            heading('Privater Kontakt'),
            field(_privatePhone, 'Telefon',
                keyboardType: TextInputType.phone),
            field(_privateMobile, 'Mobil', keyboardType: TextInputType.phone),
            field(_privateEmail, 'E-Mail',
                keyboardType: TextInputType.emailAddress),

            heading('Beschäftigung'),
            Padding(
              padding: EdgeInsets.only(bottom: spacing.sm),
              child: DropdownButtonFormField<EmployeeStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  for (final s in EmployeeStatus.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) =>
                    setState(() => _status = v ?? EmployeeStatus.aktiv),
              ),
            ),
            field(_personnelNumber, 'Personalnummer'),
            enumDropdown<PersonnelGroup>(
              'Personengruppe',
              _personnelGroup,
              PersonnelGroup.values,
              (v) => v.label,
              (v) => setState(() => _personnelGroup = v),
            ),
            dateField(
              'Eintrittsdatum',
              _hireDate,
              (d) => setState(() => _hireDate = d),
              lastDate: DateTime(DateTime.now().year + 2),
            ),
            dateField(
              'Probezeit bis',
              _probationEnd,
              (d) => setState(() => _probationEnd = d),
              lastDate: DateTime(DateTime.now().year + 2),
            ),
            dateField(
              'Befristet bis',
              _limitedUntil,
              (d) => setState(() => _limitedUntil = d),
              lastDate: DateTime(DateTime.now().year + 10),
            ),
            dateField(
              'Austrittsdatum',
              _exitDate,
              (d) => setState(() => _exitDate = d),
              lastDate: DateTime(DateTime.now().year + 5),
            ),

            heading('Lohn & Sozialversicherung'),
            enumDropdown<MaritalStatus>(
              'Familienstand',
              _maritalStatus,
              MaritalStatus.values,
              (v) => v.label,
              (v) => setState(() => _maritalStatus = v),
            ),
            enumDropdown<Confession>(
              'Konfession',
              _confession,
              Confession.values,
              (v) => v.label,
              (v) => setState(() => _confession = v),
            ),
            if (kinderGepflegt)
              Padding(
                padding: EdgeInsets.symmetric(vertical: spacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Anzahl Kinder (Freibetrag)',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    Text('$kinderzahl', style: theme.textTheme.bodyLarge),
                    Padding(
                      padding: EdgeInsets.only(top: spacing.xs),
                      child: Text(
                        'Aus gepflegten Kindern abgeleitet – dort bearbeiten.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              )
            else
              field(
                _childrenCount,
                'Anzahl Kinder',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            field(_taxId, 'Steuer-ID'),
            field(_svNumber, 'Sozialversicherungsnummer'),
            field(_healthInsurance, 'Krankenkasse'),
            enumDropdown<HealthInsuranceType>(
              'Versicherungsart',
              _healthInsuranceType,
              HealthInsuranceType.values,
              (v) => v.label,
              (v) => setState(() => _healthInsuranceType = v),
            ),
            field(
              _kvSurcharge,
              'KV-Zusatzbeitrag (%)',
              hint: 'z. B. 1,7',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return null;
                return _parsePercent(text) == null
                    ? 'Ungültiger Prozentwert (z. B. 1,7)'
                    : null;
              },
            ),

            heading('Bankverbindung'),
            field(_iban, 'IBAN'),
            field(_bic, 'BIC'),
            field(_accountHolder, 'Kontoinhaber'),

            heading('Urlaub & Notfall'),
            if (hatSollzeit)
              Padding(
                padding: EdgeInsets.symmetric(vertical: spacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Urlaubsanspruch',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    Text(
                      '${_formatTage(urlaubKanonisch!.tage)} Tage/Jahr',
                      style: theme.textTheme.bodyLarge,
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: spacing.xs),
                      child: Text(
                        'Im Sollzeit-Modell hinterlegt – dort bearbeiten.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              field(
                _vacationDays,
                'Urlaubsanspruch (Tage/Jahr)',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              Padding(
                padding: EdgeInsets.only(top: context.spacing.xs),
                child: Text(
                  'Wird künftig im Sollzeit-Modell geführt (Urlaubstage/Jahr). '
                  'Bestandswerte lassen sich in der Übersicht dorthin übernehmen.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
            field(_emergencyName, 'Notfallkontakt (Name)'),
            field(_emergencyPhone, 'Notfall-Telefon',
                keyboardType: TextInputType.phone),

            heading('Notiz'),
            field(_note, 'Interne Notiz', maxLines: 4),

            SizedBox(height: spacing.md),
            Row(
              children: [
                if (hasExisting)
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
            gap(),
          ],
        ),
      ),
    );
  }

  String? _trimmed(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  double? _parsePercent(String raw) {
    final cleaned =
        raw.trim().replaceAll('%', '').replaceAll(',', '.').trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final personal = context.read<PersonalProvider>();
    final existing = widget.existing;
    // Bei migriertem Mitarbeiter (Sollzeit-Profil) das deprecate Altfeld
    // unverändert lassen – nicht aus dem read-only Feld zurückschreiben.
    final hatSollzeit =
        personal.sollzeitProfilesForUser(widget.member.uid).isNotEmpty;
    // Bei gepflegten Kindern (§4.4) den abgeleiteten Zähler nicht aus dem
    // read-only Feld zurückschreiben – Altwert erhalten.
    final kinderGepflegt = personal.hatGepflegteKinder(widget.member.uid);
    final profile = EmployeeProfile(
      id: existing?.id,
      orgId: existing?.orgId ?? '',
      userId: widget.member.uid,
      salutation: _trimmed(_salutation),
      titleAcademic: _trimmed(_title),
      birthDate: _birthDate,
      nationality: _trimmed(_nationality),
      street: _trimmed(_street),
      houseNumber: _trimmed(_houseNumber),
      postalCode: _trimmed(_postalCode),
      city: _trimmed(_city),
      addressExtra: _trimmed(_addressExtra),
      privatePhone: _trimmed(_privatePhone),
      privateMobile: _trimmed(_privateMobile),
      privateEmail: _trimmed(_privateEmail),
      personnelNumber: _trimmed(_personnelNumber),
      status: _status,
      personnelGroup: _personnelGroup,
      hireDate: _hireDate,
      exitDate: _exitDate,
      probationEnd: _probationEnd,
      limitedUntil: _limitedUntil,
      maritalStatus: _maritalStatus,
      confession: _confession,
      childrenCount: kinderGepflegt
          ? (existing?.childrenCount ?? 0)
          : (int.tryParse(_childrenCount.text.trim()) ?? 0),
      taxId: _trimmed(_taxId),
      socialSecurityNumber: _trimmed(_svNumber),
      healthInsurance: _trimmed(_healthInsurance),
      healthInsuranceType: _healthInsuranceType,
      healthInsuranceSurchargePercent: _parsePercent(_kvSurcharge.text),
      iban: _trimmed(_iban),
      bic: _trimmed(_bic),
      accountHolder: _trimmed(_accountHolder),
      annualVacationDays: hatSollzeit
          ? existing?.annualVacationDays
          : int.tryParse(_vacationDays.text.trim()),
      emergencyContactName: _trimmed(_emergencyName),
      emergencyContactPhone: _trimmed(_emergencyPhone),
      note: _trimmed(_note),
      createdByUid: existing?.createdByUid,
      createdAt: existing?.createdAt,
    );
    try {
      await personal.saveEmployeeProfile(profile);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context, error);
      }
    }
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    try {
      await context
          .read<PersonalProvider>()
          .deleteEmployeeProfile(widget.member.uid);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context, error);
      }
    }
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

// ─────────────────────────── Lohnzeilen (M-L) ─────────────────────────────

/// Hours aus „1,5"-Eingabe (deutsches Dezimalkomma) tolerant parsen.
double _parseStunden(String raw) =>
    double.tryParse(raw.replaceAll(',', '.').trim()) ?? 0;

String? _trimOrNull(String value) {
  final t = value.trim();
  return t.isEmpty ? null : t;
}

/// Editierbare Liste der itemisierten Lohnzeilen einer Abrechnung (additiv).
class _LohnzeilenEditor extends StatelessWidget {
  const _LohnzeilenEditor({
    required this.lines,
    required this.onAdd,
    required this.onRemove,
  });

  final List<PayrollLine> lines;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Lohnzeilen (optional)',
                  style: theme.textTheme.labelLarge),
            ),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Zeile'),
            ),
          ],
        ),
        if (lines.isEmpty)
          Text(
            'Zusätzliche Bezüge/Abzüge (Zulage, §3b-Zuschlag, VwL, '
            'Einmalzahlung) — Brutto/Netto bleiben die Hauptfelder.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          )
        else
          for (var i = 0; i < lines.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('${lines[i].kind.label}: ${lines[i].name}'),
              subtitle: lines[i].datevLohnartNr == null
                  ? null
                  : Text('DATEV-Lohnart ${lines[i].datevLohnartNr}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_euro(lines[i].amountCents),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  IconButton(
                    tooltip: 'Entfernen',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => onRemove(i),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// Sheet zum Anlegen einer Lohnzeile (frei oder aus dem Katalog). Für
/// §3b-Zuschläge wird die Aufteilung live aus [computeSfn3bAnteil] gerechnet.
class _PayLineEditorSheet extends StatefulWidget {
  const _PayLineEditorSheet({
    required this.katalog,
    this.defaultStundenlohnCents = 0,
    this.regularMonthlyGrossCents = 0,
    this.settings,
    this.taxClass = TaxClass.i,
    this.churchTax = false,
    this.federalState,
    this.childCount = 0,
    this.kvSurchargeOverride,
  });

  final List<PayLineType> katalog;
  final int defaultStundenlohnCents;

  /// Laufendes Monatsbrutto + Steuerparameter — nur für die §39b-Vorschau einer
  /// Einmalzahlung (Richtwert). [settings] null ⇒ keine Vorschau.
  final int regularMonthlyGrossCents;
  final PayrollSettings? settings;
  final TaxClass taxClass;
  final bool churchTax;
  final String? federalState;
  final int childCount;
  final double? kvSurchargeOverride;

  @override
  State<_PayLineEditorSheet> createState() => _PayLineEditorSheetState();
}

class _PayLineEditorSheetState extends State<_PayLineEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  PayLineType? _type;
  PayLineKind _kind = PayLineKind.zulage;
  bool _isAbzug = false;
  SfnZuschlagsart _sfnArt = SfnZuschlagsart.nacht;
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _datev = TextEditingController();
  final _stunden = TextEditingController();
  late final TextEditingController _grundlohn;

  @override
  void initState() {
    super.initState();
    _grundlohn = TextEditingController(
      text: widget.defaultStundenlohnCents > 0
          ? _centsToInput(widget.defaultStundenlohnCents)
          : '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _datev.dispose();
    _stunden.dispose();
    _grundlohn.dispose();
    super.dispose();
  }

  void _applyType(PayLineType? t) {
    setState(() {
      _type = t;
      if (t != null) {
        _kind = t.kind;
        _isAbzug = t.kind.isAbzug;
        if (_name.text.trim().isEmpty) _name.text = t.name;
        if (t.datevLohnartNr != null && _datev.text.trim().isEmpty) {
          _datev.text = t.datevLohnartNr!;
        }
      }
    });
  }

  Sfn3bAnteil get _preview => computeSfn3bAnteil(
        art: _sfnArt,
        grundlohnCentsProStunde: _parseEuroToCents(_grundlohn.text) ?? 0,
        dauer: Duration(minutes: (_parseStunden(_stunden.text) * 60).round()),
      );

  /// §39b-Steuer-Vorschau (Richtwert) für eine Einmalzahlung — nur sichtbar,
  /// wenn die nötigen Steuerparameter übergeben wurden.
  String? get _einmalzahlungVorschau {
    final settings = widget.settings;
    final bonus = _parseEuroToCents(_amount.text) ?? 0;
    if (_kind != PayLineKind.einmalzahlung ||
        _isAbzug ||
        settings == null ||
        bonus <= 0) {
      return null;
    }
    final t = LohnHerleitung.einmalzahlungSteuer(
      regularMonthlyGrossCents: widget.regularMonthlyGrossCents,
      einmalzahlungCents: bonus,
      settings: settings,
      taxClass: widget.taxClass,
      churchTax: widget.churchTax,
      federalState: widget.federalState,
      childCount: widget.childCount,
      healthAdditionalRateOverride: widget.kvSurchargeOverride,
    );
    final teile = <String>[
      'LSt ${_euro(t.incomeTaxCents)}',
      if (t.soliCents > 0) 'Soli ${_euro(t.soliCents)}',
      if (t.churchTaxCents > 0) 'KiSt ${_euro(t.churchTaxCents)}',
    ];
    return '§39b-Steuer (Richtwert): ${teile.join(' · ')}';
  }

  PayrollLine? _build() {
    final name = _name.text.trim();
    if (_kind == PayLineKind.zuschlag3b) {
      final grundlohn = _parseEuroToCents(_grundlohn.text) ?? 0;
      final minutes = (_parseStunden(_stunden.text) * 60).round();
      if (grundlohn <= 0 || minutes <= 0) return null;
      return LohnHerleitung.sfn3bLine(
        art: _sfnArt,
        grundlohnCentsProStunde: grundlohn,
        dauer: Duration(minutes: minutes),
        name: name.isEmpty ? _sfnArt.label : name,
        datevLohnartNr: _trimOrNull(_datev.text),
        lineTypeId: _type?.id,
      );
    }
    final magnitude = _parseEuroToCents(_amount.text);
    if (name.isEmpty || magnitude == null || magnitude == 0) return null;
    final signed = _isAbzug ? -magnitude.abs() : magnitude.abs();
    return PayrollLine(
      lineTypeId: _type?.id,
      name: name,
      datevLohnartNr: _trimOrNull(_datev.text),
      amountCents: signed,
      kind: _kind,
      steuerfrei: _type?.steuerfrei ?? false,
      svFrei: _type?.svFrei ?? false,
    );
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final line = _build();
    if (line == null) {
      _showError(context, StateError('Bitte Betrag/Stunden vollständig angeben.'));
      return;
    }
    Navigator.of(context).pop(line);
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final isSfn = _kind == PayLineKind.zuschlag3b;
    return AppBottomSheetScaffold(
      title: 'Lohnzeile hinzufügen',
      subtitle: 'Bezug oder Abzug · Richtwert',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.katalog.isNotEmpty) ...[
              DropdownButtonFormField<PayLineType?>(
                initialValue: _type,
                decoration:
                    const InputDecoration(labelText: 'Aus Katalog (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Freie Zeile')),
                  for (final t in widget.katalog)
                    DropdownMenuItem(value: t, child: Text(t.name)),
                ],
                onChanged: _applyType,
              ),
              SizedBox(height: spacing.md),
            ],
            DropdownButtonFormField<PayLineKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Art'),
              items: [
                for (final k in PayLineKind.values)
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: (value) => setState(() {
                _kind = value ?? _kind;
                _isAbzug = _kind.isAbzug;
              }),
            ),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _name,
              label: 'Bezeichnung',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null,
            ),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _datev,
              label: 'DATEV-Lohnartnummer (optional)',
              keyboardType: TextInputType.number,
              validator: (v) => PayLineType.isValidDatevLohnartNr(v)
                  ? null
                  : 'Max. 4-stellig numerisch',
            ),
            SizedBox(height: spacing.md),
            if (isSfn) ...[
              DropdownButtonFormField<SfnZuschlagsart>(
                initialValue: _sfnArt,
                decoration: const InputDecoration(labelText: 'Zuschlagsart'),
                items: [
                  for (final a in SfnZuschlagsart.values)
                    DropdownMenuItem(value: a, child: Text(a.label)),
                ],
                onChanged: (value) => setState(() => _sfnArt = value ?? _sfnArt),
              ),
              SizedBox(height: spacing.md),
              Row(
                children: [
                  Expanded(
                    child: AppFormField(
                      controller: _stunden,
                      label: 'Stunden',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  SizedBox(width: spacing.md),
                  Expanded(
                    child: AppFormField(
                      controller: _grundlohn,
                      label: 'Grundlohn €/h',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              SizedBox(height: spacing.sm),
              AppStatusBanner(
                icon: Icons.calculate_outlined,
                tone: AppStatusTone.info,
                message: 'Zuschlag ${_euro(_preview.gesamtCents)} · steuerfrei '
                    '${_euro(_preview.steuerfreiCents)} · SV-frei '
                    '${_euro(_preview.svFreiCents)}',
              ),
            ] else ...[
              AppSegmented<bool>(
                segments: const [
                  AppSegment(value: false, label: 'Bezug (+)'),
                  AppSegment(value: true, label: 'Abzug (−)'),
                ],
                selected: _isAbzug,
                onChanged: (value) => setState(() => _isAbzug = value),
              ),
              SizedBox(height: spacing.md),
              AppFormField(
                controller: _amount,
                label: 'Betrag (€)',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: (_) => setState(() {}),
                validator: (v) =>
                    _parseEuroToCents(v ?? '') == null ? 'Ungültig' : null,
              ),
              if (_einmalzahlungVorschau != null) ...[
                SizedBox(height: spacing.sm),
                AppStatusBanner(
                  icon: Icons.calculate_outlined,
                  tone: AppStatusTone.info,
                  message: _einmalzahlungVorschau!,
                ),
              ],
            ],
            SizedBox(height: spacing.lg),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _save,
                child: const Text('Hinzufügen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Lohnarten-Katalog (M-L) ──────────────────────

/// Admin-Verwaltung des org-weiten Lohnart-Katalogs ([PayLineType]).
class _PayLineTypeKatalogSheet extends StatelessWidget {
  const _PayLineTypeKatalogSheet();

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final spacing = context.spacing;
    final types = [...personal.payLineTypes]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final theme = Theme.of(context);

    return AppBottomSheetScaffold(
      title: 'Lohnarten-Katalog',
      subtitle: 'Wiederverwendbare Lohnart-Vorlagen',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => showAppBottomSheet(
                context: context,
                builder: (_) => const _PayLineTypeEditorSheet(),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Neue Lohnart'),
            ),
          ),
          SizedBox(height: spacing.md),
          if (types.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: spacing.lg),
              child: Text(
                'Noch keine Lohnarten angelegt.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            for (final t in types)
              Card(
                margin: EdgeInsets.only(bottom: spacing.sm),
                child: ListTile(
                  title: Text(t.name,
                      style: t.deaktiviert
                          ? TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: theme.colorScheme.onSurfaceVariant)
                          : null),
                  subtitle: Text(
                    '${t.kind.label} · ${t.wertTyp.label}'
                    '${t.datevLohnartNr != null ? ' · DATEV ${t.datevLohnartNr}' : ''}'
                    '${t.steuerfrei ? ' · steuerfrei' : ''}'
                    '${t.svFrei ? ' · SV-frei' : ''}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Bearbeiten',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => showAppBottomSheet(
                          context: context,
                          builder: (_) => _PayLineTypeEditorSheet(existing: t),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Löschen',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(context, t),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, PayLineType type) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lohnart löschen?'),
        content: Text('„${type.name}" wird entfernt. Bereits abgerechnete '
            'Zeilen bleiben unverändert.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true && type.id != null && context.mounted) {
      try {
        await context.read<PersonalProvider>().deletePayLineType(type.id!);
      } catch (error) {
        if (context.mounted) _showError(context, error);
      }
    }
  }
}

/// Editor für eine einzelne Lohnart ([PayLineType]).
class _PayLineTypeEditorSheet extends StatefulWidget {
  const _PayLineTypeEditorSheet({this.existing});

  final PayLineType? existing;

  @override
  State<_PayLineTypeEditorSheet> createState() =>
      _PayLineTypeEditorSheetState();
}

class _PayLineTypeEditorSheetState extends State<_PayLineTypeEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _datev;
  late PayLineKind _kind;
  late PayWertTyp _wertTyp;
  late PayInterval _intervall;
  late bool _steuerfrei;
  late bool _svFrei;
  late bool _deaktiviert;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _datev = TextEditingController(text: e?.datevLohnartNr ?? '');
    _kind = e?.kind ?? PayLineKind.zulage;
    _wertTyp = e?.wertTyp ?? PayWertTyp.nominal;
    _intervall = e?.intervall ?? PayInterval.monatlich;
    _steuerfrei = e?.steuerfrei ?? false;
    _svFrei = e?.svFrei ?? false;
    _deaktiviert = e?.deaktiviert ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _datev.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final prepared = (widget.existing ??
            const PayLineType(orgId: '', name: ''))
        .copyWith(
      name: _name.text.trim(),
      datevLohnartNr: _trimOrNull(_datev.text),
      clearDatevLohnartNr: _trimOrNull(_datev.text) == null,
      kind: _kind,
      wertTyp: _wertTyp,
      intervall: _intervall,
      steuerfrei: _steuerfrei,
      svFrei: _svFrei,
      deaktiviert: _deaktiviert,
    );
    try {
      await context.read<PersonalProvider>().savePayLineType(prepared);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return AppBottomSheetScaffold(
      title: widget.existing == null ? 'Neue Lohnart' : 'Lohnart bearbeiten',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppFormField(
              controller: _name,
              label: 'Bezeichnung',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null,
            ),
            SizedBox(height: spacing.md),
            DropdownButtonFormField<PayLineKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Art'),
              items: [
                for (final k in PayLineKind.values)
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: (value) => setState(() => _kind = value ?? _kind),
            ),
            SizedBox(height: spacing.md),
            DropdownButtonFormField<PayWertTyp>(
              initialValue: _wertTyp,
              decoration: const InputDecoration(labelText: 'Werttyp'),
              items: [
                for (final w in PayWertTyp.values)
                  DropdownMenuItem(value: w, child: Text(w.label)),
              ],
              onChanged: (value) => setState(() => _wertTyp = value ?? _wertTyp),
            ),
            SizedBox(height: spacing.md),
            DropdownButtonFormField<PayInterval>(
              initialValue: _intervall,
              decoration: const InputDecoration(labelText: 'Intervall'),
              items: [
                for (final i in PayInterval.values)
                  DropdownMenuItem(value: i, child: Text(i.label)),
              ],
              onChanged: (value) =>
                  setState(() => _intervall = value ?? _intervall),
            ),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _datev,
              label: 'DATEV-Lohnartnummer (optional)',
              keyboardType: TextInputType.number,
              validator: (v) => PayLineType.isValidDatevLohnartNr(v)
                  ? null
                  : 'Max. 4-stellig numerisch',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Steuerfrei'),
              value: _steuerfrei,
              onChanged: (v) => setState(() => _steuerfrei = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('SV-frei'),
              value: _svFrei,
              onChanged: (v) => setState(() => _svFrei = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Deaktiviert'),
              subtitle: const Text('Für neue Zeilen ausblenden'),
              value: _deaktiviert,
              onChanged: (v) => setState(() => _deaktiviert = v),
            ),
            SizedBox(height: spacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Speichern'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
