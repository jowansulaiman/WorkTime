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
import '../widgets/responsive_layout.dart';

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
  final Set<String> _selectedSiteIds = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final work = context.watch<WorkProvider>();
    final team = context.watch<TeamProvider>();
    final isAdmin = auth.isAdmin;
    final currentUser = auth.profile;
    final reportUser = work.reportUser ?? auth.profile;
    final rawEntries = work.reportEntries;
    final settings = work.reportSettings;
    final colorScheme = theme.colorScheme;
    final pagePadding = MobileBreakpoints.screenPadding(context);
    final isCompactScreen = MobileBreakpoints.isCompact(context);
    final sectionSpacing = isCompactScreen ? 16.0 : 20.0;

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

    final availableSites = <String, String>{};
    for (final entry in rawEntries) {
      if (entry.siteId != null && entry.siteName != null) {
        availableSites[entry.siteId!] = entry.siteName!;
      }
    }
    for (final site in team.sites) {
      if (site.id != null) {
        availableSites[site.id!] = site.name;
      }
    }

    final entries = _selectedSiteIds.isEmpty
        ? rawEntries
        : rawEntries
            .where(
                (e) => e.siteId != null && _selectedSiteIds.contains(e.siteId))
            .toList();

    final totalHours =
        entries.fold(0.0, (sum, entry) => sum + entry.workedHours);
    final overtimeHours = entries.fold(0.0, (sum, entry) {
      final diff = entry.workedHours - settings.dailyHours;
      return sum + (diff > 0 ? diff : 0);
    });
    final totalWage = totalHours * settings.hourlyRate;

    final content = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    pagePadding.left,
                    16,
                    pagePadding.right,
                    16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monatsbericht',
                        style: (isCompactScreen
                                ? theme.textTheme.headlineSmall
                                : theme.textTheme.headlineMedium)
                            ?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Monatssummen, Eintragsdetails und PDF-Export fuer Mitarbeiter und Admins.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      SizedBox(height: sectionSpacing),
                      _MonthSelector(provider: work),
                      const SizedBox(height: 16),
                      if (isAdmin)
                        _EmployeeSelector(
                          members: team.members,
                          selectedUser: reportUser,
                          onChanged: (value) {
                            work.selectReportUser(value);
                            setState(() {
                              _selectedSiteIds.clear();
                            });
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
                      SizedBox(height: sectionSpacing),
                      if (availableSites.isNotEmpty) ...[
                        _buildSiteFilter(availableSites),
                        SizedBox(height: sectionSpacing),
                      ],
                      Text(
                        'Zusammenfassung',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _StatsGrid(
                        totalHours: totalHours,
                        overtimeHours: overtimeHours,
                        totalWage: totalWage,
                        entryCount: entries.length,
                        settings: settings,
                      ),
                      SizedBox(height: sectionSpacing),
                      FilledButton.icon(
                        onPressed: entries.isEmpty || _exporting
                            ? null
                            : () => _exportPdf(work, entries),
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
                      SizedBox(height: isCompactScreen ? 20 : 24),
                      Text(
                        'Eintraege (${entries.length})',
                        style: theme.textTheme.titleLarge?.copyWith(
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

  Widget _buildSiteFilter(Map<String, String> sites) {
    final sortedSites = sites.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Standort-Filter',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final site in sortedSites)
              FilterChip(
                label: Text(site.value),
                selected: _selectedSiteIds.contains(site.key),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedSiteIds.add(site.key);
                    } else {
                      _selectedSiteIds.remove(site.key);
                    }
                  });
                },
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _exportPdf(
      WorkProvider work, List<WorkEntry> entriesToExport) async {
    setState(() => _exporting = true);
    try {
      await ExportService.exportMonthlyReport(
        entries: entriesToExport,
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
        final columns = constraints.maxWidth >= 980
            ? items.length.clamp(1, 4)
            : constraints.maxWidth >= 680
                ? 2
                : constraints.maxWidth >= 360 && items.length > 1
                    ? 2
                    : 1;
        const spacing = 12.0;
        final itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _StatGridCard(item: item),
              ),
          ],
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 190;

        return Card(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact ? 96 : 104),
            child: Padding(
              padding: EdgeInsets.all(compact ? 14 : 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(compact ? 8 : 10),
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.icon, color: item.color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.label,
                          maxLines: compact ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              item.value,
                              style: (compact
                                      ? Theme.of(context).textTheme.titleMedium
                                      : Theme.of(context).textTheme.titleLarge)
                                  ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: item.color,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
    final pagePadding = MobileBreakpoints.screenPadding(context);
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

    final detailText =
        '${timeFmt.format(entry.startTime)} - ${timeFmt.format(entry.endTime)}'
        '${entry.note != null ? ' · ${entry.note}' : ''}';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        pagePadding.left,
        4,
        pagePadding.right,
        4,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 430;

          if (!compact) {
            return Card(
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
                  detailText,
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
            );
          }

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          dateFmt.format(entry.date),
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                      if (isOvertime)
                        Icon(
                          Icons.trending_up,
                          size: 16,
                          color: colorScheme.tertiary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detailText,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${entry.workedHours.toStringAsFixed(1)} h',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                      if (settings.hourlyRate > 0) ...[
                        const Spacer(),
                        Text(
                          currencyFmt.format(wage),
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
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
