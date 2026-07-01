import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/absence_request.dart';
import '../../models/app_user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/schedule_provider.dart';
import '../../providers/team_provider.dart';
import '../../ui/ui.dart';

/// Abwesenheitskalender (AllTec-1:1) — Monatsraster **Mitarbeiter × Tage**,
/// farbcodiert je Abwesenheitsart.
///
/// Rollen-adaptiv: **Manager** sehen alle aktiven Mitarbeiter (optional auf einen
/// Laden gefiltert), **Mitarbeiter** nur die eigene Zeile. Liest ausschließlich
/// `ScheduleProvider.allAbsenceRequests` (org-weit für Manager, self-gescoped für
/// Mitarbeiter) und filtert per [AbsenceRequest.overlaps] auf den Monat. Reine
/// Lese-Ansicht — kein neues Modell, keine Mutationen.
class AbwesenheitskalenderScreen extends StatefulWidget {
  const AbwesenheitskalenderScreen({
    super.key,
    this.parentLabel = 'Zeitwirtschaft',
  });

  final String parentLabel;

  @override
  State<AbwesenheitskalenderScreen> createState() =>
      _AbwesenheitskalenderScreenState();
}

class _AbwesenheitskalenderScreenState
    extends State<AbwesenheitskalenderScreen> {
  static final _monthFormat = DateFormat('MMMM yyyy', 'de_DE');

  late DateTime _month;
  String? _siteFilter; // null = alle Läden

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    final schedule = context.watch<ScheduleProvider>();
    final team = context.watch<TeamProvider>();
    final user = context.watch<AuthProvider>().profile;
    final canManage = user?.canManageShifts ?? false;

    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;

    // Zeilen: Manager → aktive Mitglieder (optional nach Laden gefiltert);
    // Mitarbeiter → nur die eigene Zeile.
    final List<AppUserProfile> rows;
    if (canManage) {
      final active = team.members.where((m) => m.isActive).toList()
        ..sort((a, b) => a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase()));
      rows = _siteFilter == null
          ? active
          : active
              .where((m) => team.siteAssignments.any((a) =>
                  a.userId == m.uid && a.siteId == _siteFilter))
              .toList();
    } else {
      rows = user == null ? const [] : [user];
    }

    // Abwesenheiten des Monats (pending + approved; rejected ausgeblendet).
    final monthStart = DateTime(_month.year, _month.month, 1);
    final monthEndExclusive = DateTime(_month.year, _month.month + 1, 1);
    final coverage = <String, Map<int, AbsenceType>>{};
    for (final r in schedule.allAbsenceRequests) {
      if (r.status == AbsenceStatus.rejected) continue;
      if (!r.overlaps(monthStart, monthEndExclusive)) continue;
      final byDay = coverage.putIfAbsent(r.userId, () => <int, AbsenceType>{});
      final firstDay =
          r.startDate.month == _month.month && r.startDate.year == _month.year
              ? r.startDate.day
              : 1;
      final lastDay =
          r.endDate.month == _month.month && r.endDate.year == _month.year
              ? r.endDate.day
              : daysInMonth;
      for (var d = firstDay; d <= lastDay; d++) {
        // Erste belegende Art je Tag gewinnt (überlappende Anträge selten).
        byDay.putIfAbsent(d, () => r.type);
      }
    }

    final presentTypes = <AbsenceType>{
      for (final byDay in coverage.values) ...byDay.values,
    }.toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    final sites = team.sites;

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: widget.parentLabel,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const BreadcrumbItem(label: 'Abwesenheitskalender'),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  spacing.md, spacing.md, spacing.md, spacing.xl),
              children: [
                _MonthHeader(
                  label: _monthFormat.format(_month),
                  onPrevious: () => _changeMonth(-1),
                  onNext: () => _changeMonth(1),
                ),
                if (canManage && sites.length > 1) ...[
                  SizedBox(height: spacing.md),
                  _SiteFilterBar(
                    sites: sites
                        .where((s) => s.id != null)
                        .map((s) => (s.id!, s.name))
                        .toList(),
                    selected: _siteFilter,
                    onChanged: (value) => setState(() => _siteFilter = value),
                  ),
                ],
                SizedBox(height: spacing.md),
                if (rows.isEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: spacing.xl),
                    child: const EmptyState(
                      icon: Icons.calendar_month_outlined,
                      message: 'Keine Mitarbeiter im gewählten Filter.',
                    ),
                  )
                else
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: _CalendarGrid(
                      month: _month,
                      daysInMonth: daysInMonth,
                      rows: rows,
                      coverage: coverage,
                    ),
                  ),
                if (presentTypes.isNotEmpty) ...[
                  SizedBox(height: spacing.md),
                  _Legend(types: presentTypes),
                ] else if (rows.isNotEmpty) ...[
                  SizedBox(height: spacing.md),
                  Text(
                    'Keine Abwesenheiten in diesem Monat.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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

/// Farbe je Abwesenheitsart — ausschließlich benannte Theme-Rollen (keine
/// hartkodierten Farben).
Color absenceTypeColor(
    AbsenceType type, ColorScheme cs, AppThemeColors ac) {
  return switch (type) {
    AbsenceType.vacation => ac.info,
    AbsenceType.sickness => cs.error,
    AbsenceType.childSick => cs.error,
    AbsenceType.timeOff => ac.warning,
    AbsenceType.shortTimeWork => ac.warning,
    AbsenceType.specialLeave => cs.tertiary,
    AbsenceType.volunteering => cs.tertiary,
    AbsenceType.parentalLeave => cs.secondary,
    AbsenceType.maternity => cs.secondary,
    AbsenceType.vocationalSchool => cs.primary,
    AbsenceType.unpaidLeave => cs.outline,
    AbsenceType.unavailable => cs.onSurfaceVariant,
  };
}

const double _kNameColWidth = 132;
const double _kDayCellWidth = 26;
const double _kRowHeight = 34;
const double _kHeaderHeight = 28;

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.month,
    required this.daysInMonth,
    required this.rows,
    required this.coverage,
  });

  final DateTime month;
  final int daysInMonth;
  final List<AppUserProfile> rows;
  final Map<String, Map<int, AbsenceType>> coverage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dividerColor = theme.dividerColor.withValues(alpha: 0.5);

    // Eingefrorene Namensspalte links, horizontal scrollbares Tagesraster rechts
    // — damit die Namen beim Scrollen sichtbar bleiben.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _kNameColWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeaderCell(
                height: _kHeaderHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text('Mitarbeiter',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              for (final member in rows)
                Container(
                  height: _kRowHeight,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 12, right: 6),
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(color: dividerColor, width: 0.5)),
                  ),
                  child: Text(
                    member.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tagesnummern-Kopf
                Row(
                  children: [
                    for (var d = 1; d <= daysInMonth; d++)
                      _HeaderCell(
                        width: _kDayCellWidth,
                        height: _kHeaderHeight,
                        child: Text(
                          '$d',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _isWeekend(month, d)
                                ? cs.onSurfaceVariant
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
                for (final member in rows)
                  Row(
                    children: [
                      for (var d = 1; d <= daysInMonth; d++)
                        _DayCell(
                          month: month,
                          day: d,
                          type: coverage[member.uid]?[d],
                          dividerColor: dividerColor,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static bool _isWeekend(DateTime month, int day) {
    final wd = DateTime(month.year, month.month, day).weekday;
    return wd == DateTime.saturday || wd == DateTime.sunday;
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.height, required this.child, this.width});

  final double height;
  final double? width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.month,
    required this.day,
    required this.type,
    required this.dividerColor,
  });

  final DateTime month;
  final int day;
  final AbsenceType? type;
  final Color dividerColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final weekend = _isWeekend(month, day);
    final type = this.type;

    Widget cell = Container(
      width: _kDayCellWidth,
      height: _kRowHeight,
      decoration: BoxDecoration(
        color: type != null
            ? absenceTypeColor(type, cs, theme.appColors)
                .withValues(alpha: 0.55)
            : (weekend
                ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
                : null),
        border: Border(
          top: BorderSide(color: dividerColor, width: 0.5),
          left: BorderSide(color: dividerColor, width: 0.5),
        ),
      ),
    );

    if (type != null) {
      cell = Tooltip(
        message:
            '${DateFormat('dd.MM.', 'de_DE').format(DateTime(month.year, month.month, day))} · ${type.label}',
        child: cell,
      );
    }
    return cell;
  }

  static bool _isWeekend(DateTime month, int day) {
    final wd = DateTime(month.year, month.month, day).weekday;
    return wd == DateTime.saturday || wd == DateTime.sunday;
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.types});

  final List<AbsenceType> types;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Wrap(
      spacing: context.spacing.md,
      runSpacing: context.spacing.sm,
      children: [
        for (final type in types)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: absenceTypeColor(type, cs, theme.appColors)
                      .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text(type.label, style: theme.textTheme.bodySmall),
            ],
          ),
      ],
    );
  }
}

class _SiteFilterBar extends StatelessWidget {
  const _SiteFilterBar({
    required this.sites,
    required this.selected,
    required this.onChanged,
  });

  final List<(String, String)> sites; // (id, name)
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: context.spacing.sm,
      children: [
        ChoiceChip(
          label: const Text('Alle Läden'),
          selected: selected == null,
          onSelected: (_) => onChanged(null),
        ),
        for (final (id, name) in sites)
          ChoiceChip(
            label: Text(name),
            selected: selected == id,
            onSelected: (_) => onChanged(id),
          ),
      ],
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader(
      {required this.label, required this.onPrevious, required this.onNext});

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Vorheriger Monat',
          onPressed: onPrevious,
        ),
        Expanded(
          child: Center(
            child: Text(label,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Nächster Monat',
          onPressed: onNext,
        ),
      ],
    );
  }
}
