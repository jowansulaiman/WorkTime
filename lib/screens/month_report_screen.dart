import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../models/work_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/team_provider.dart';
import '../providers/work_provider.dart';
import '../services/export_service.dart';
import '../widgets/breadcrumb_app_bar.dart';

class MonthReportScreen extends StatefulWidget {
  const MonthReportScreen({
    super.key,
    this.parentLabel = 'Zeit',
  });

  final String parentLabel;

  @override
  State<MonthReportScreen> createState() => _MonthReportScreenState();
}

class _MonthReportScreenState extends State<MonthReportScreen> {
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final work = context.watch<WorkProvider>();
    final team = context.watch<TeamProvider>();
    final isAdmin = auth.isAdmin;
    final currentUser = auth.profile;
    final reportUser = work.reportUser ?? auth.profile;
    final entries = work.reportEntries;
    final settings = work.reportSettings;
    final colorScheme = Theme.of(context).colorScheme;

    if (!(currentUser?.canViewReports ?? false)) {
      return Scaffold(
        appBar: BreadcrumbAppBar(
          breadcrumbs: [
            BreadcrumbItem(
              label: widget.parentLabel,
              onTap: () => Navigator.of(context).pop(),
            ),
            const BreadcrumbItem(label: 'Monatsbericht'),
          ],
        ),
        body: const SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Der Monatsbericht ist fuer dieses Profil deaktiviert.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    final content = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monatsbericht',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Monatssummen, Eintragsdetails und PDF-Export fuer Mitarbeiter und Admins.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 20),
                      _MonthSelector(provider: work),
                      const SizedBox(height: 16),
                      if (isAdmin)
                        _EmployeeSelector(
                          members: team.members,
                          selectedUser: reportUser,
                          onChanged: (value) {
                            work.selectReportUser(value);
                          },
                        ),
                      if (isAdmin) const SizedBox(height: 16),
                      if (reportUser != null)
                        Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                reportUser.displayName.isEmpty
                                    ? '?'
                                    : reportUser.displayName
                                        .substring(0, 1)
                                        .toUpperCase(),
                              ),
                            ),
                            title: Text(reportUser.displayName),
                            subtitle: Text(reportUser.email),
                            trailing: Text(reportUser.role.label),
                          ),
                        ),
                      const SizedBox(height: 20),
                      Text(
                        'Zusammenfassung',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 12),
                      _StatsGrid(
                        totalHours: work.totalReportHoursThisMonth,
                        overtimeHours: work.reportOvertimeThisMonth,
                        totalWage: work.totalReportWageThisMonth,
                        entryCount: entries.length,
                        settings: settings,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: entries.isEmpty || _exporting
                            ? null
                            : () => _exportPdf(work),
                        icon: _exporting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onTertiary,
                                ),
                              )
                            : const Icon(Icons.picture_as_pdf),
                        label: Text(
                          _exporting ? 'Wird exportiert...' : 'PDF exportieren',
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: colorScheme.tertiary,
                          foregroundColor: colorScheme.onTertiary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Eintraege (${entries.length})',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              if (entries.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: _EmptyReportState(),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _ReportEntryTile(
                      entry: entries[index],
                      settings: settings,
                    ),
                    childCount: entries.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: widget.parentLabel,
            onTap: () => Navigator.of(context).pop(),
          ),
          const BreadcrumbItem(label: 'Monatsbericht'),
        ],
      ),
      body: content,
    );
  }

  Future<void> _exportPdf(WorkProvider work) async {
    setState(() => _exporting = true);
    try {
      await ExportService.exportMonthlyReport(
        entries: work.reportEntries,
        settings: work.reportSettings,
        year: work.selectedMonth.year,
        month: work.selectedMonth.month,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler beim PDF-Export: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }
}

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({required this.provider});

  final WorkProvider provider;

  @override
  Widget build(BuildContext context) {
    final monthFmt = DateFormat('MMMM yyyy', 'de_DE');
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: provider.previousMonth,
          ),
          Expanded(
            child: Center(
              child: Text(
                monthFmt.format(provider.selectedMonth),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: provider.nextMonth,
          ),
        ],
      ),
    );
  }
}

class _EmployeeSelector extends StatelessWidget {
  const _EmployeeSelector({
    required this.members,
    required this.selectedUser,
    required this.onChanged,
  });

  final List<AppUserProfile> members;
  final AppUserProfile? selectedUser;
  final ValueChanged<AppUserProfile?> onChanged;

  @override
  Widget build(BuildContext context) {
    final employeeMembers = members.where((member) => member.isActive).toList();
    final availableMembers = <AppUserProfile>[
      ...employeeMembers,
      if (selectedUser != null &&
          employeeMembers.every((member) => member.uid != selectedUser!.uid))
        selectedUser!,
    ];

    if (availableMembers.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Keine Mitarbeiter verfuegbar'),
          subtitle: Text(
            'Sobald Teammitglieder geladen sind, kann hier der Bericht umgeschaltet werden.',
          ),
        ),
      );
    }

    final selectedValue = availableMembers.any(
      (member) => member.uid == selectedUser?.uid,
    )
        ? selectedUser?.uid
        : availableMembers.first.uid;

    return DropdownButtonFormField<String>(
      initialValue: selectedValue,
      decoration: const InputDecoration(
        labelText: 'Mitarbeiter fuer Bericht',
        prefixIcon: Icon(Icons.groups_outlined),
      ),
      items: [
        for (final member in availableMembers)
          DropdownMenuItem(
            value: member.uid,
            child: Text(member.displayName),
          ),
      ],
      onChanged: (value) {
        if (value == null) {
          return;
        }
        final member = availableMembers.firstWhere(
          (candidate) => candidate.uid == value,
        );
        onChanged(member);
      },
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.totalHours,
    required this.overtimeHours,
    required this.totalWage,
    required this.entryCount,
    required this.settings,
  });

  final double totalHours;
  final double overtimeHours;
  final double totalWage;
  final int entryCount;
  final dynamic settings;

  @override
  Widget build(BuildContext context) {
    final currencyFmt = NumberFormat.currency(
      locale: 'de_DE',
      symbol: settings.currency,
      decimalDigits: 2,
    );
    final colorScheme = Theme.of(context).colorScheme;

    final items = [
      _StatItem(
        'Gesamtstunden',
        '${totalHours.toStringAsFixed(2)} h',
        Icons.timer,
        colorScheme.secondary,
      ),
      _StatItem(
        'Arbeitstage',
        '$entryCount',
        Icons.calendar_month,
        colorScheme.primary,
      ),
      _StatItem(
        'Ueberstunden',
        '${overtimeHours.toStringAsFixed(2)} h',
        Icons.trending_up,
        colorScheme.tertiary,
      ),
      if (settings.hourlyRate > 0)
        _StatItem(
          'Bruttolohn',
          currencyFmt.format(totalWage),
          Icons.payments,
          colorScheme.primary,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final singleColumn = constraints.maxWidth < 720;
        return GridView.count(
          crossAxisCount: singleColumn ? 1 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: singleColumn ? 3.8 : 2.2,
          children: items.map((item) => _StatGridCard(item: item)).toList(),
        );
      },
    );
  }
}

class _StatItem {
  const _StatItem(this.label, this.value, this.icon, this.color);

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _StatGridCard extends StatelessWidget {
  const _StatGridCard({required this.item});

  final _StatItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, color: item.color, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              item.value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: item.color,
                  ),
            ),
            Text(
              item.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportEntryTile extends StatelessWidget {
  const _ReportEntryTile({
    required this.entry,
    required this.settings,
  });

  final WorkEntry entry;
  final dynamic settings;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateFmt = DateFormat('EE, dd.MM.', 'de_DE');
    final timeFmt = DateFormat('HH:mm');
    final wage = entry.workedHours * settings.hourlyRate;
    final currencyFmt = NumberFormat.currency(
      locale: 'de_DE',
      symbol: settings.currency,
      decimalDigits: 2,
    );
    final isOvertime =
        entry.workedHours > settings.dailyHours && settings.dailyHours > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          title: Row(
            children: [
              Expanded(child: Text(dateFmt.format(entry.date))),
              if (isOvertime)
                Icon(
                  Icons.trending_up,
                  size: 16,
                  color: colorScheme.tertiary,
                ),
            ],
          ),
          subtitle: Text(
            '${timeFmt.format(entry.startTime)} - ${timeFmt.format(entry.endTime)}'
            '${entry.note != null ? ' · ${entry.note}' : ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          leading: CircleAvatar(
            child: Text(entry.workedHours.toStringAsFixed(1)),
          ),
          trailing: settings.hourlyRate > 0
              ? Text(
                  currencyFmt.format(wage),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _EmptyReportState extends StatelessWidget {
  const _EmptyReportState();

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.75);
    return Column(
      children: [
        Icon(Icons.assignment_outlined, size: 64, color: muted),
        const SizedBox(height: 12),
        Text(
          'Keine Eintraege fuer diesen Monat',
          style: TextStyle(color: muted),
        ),
      ],
    );
  }
}
