import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/absence_request.dart';
import '../../models/work_entry.dart';
import '../../providers/schedule_provider.dart';
import '../../providers/work_provider.dart';
import '../../ui/ui.dart';
import '../entry_form_screen.dart';
import '../notification_screen.dart';

/// Zeiterfassung (AllTec-1:1, M2b) — drei Tabs **Arbeitszeiten / Urlaub /
/// Krankmeldungen** für den angemeldeten Mitarbeiter (Self-Service). Ersetzt die
/// frühere Kalender-Monatsansicht als Inhalt von [AppRoutes.zeitErfassung].
///
/// Arbeitszeiten zeigt die eigenen [WorkEntry]s des gewählten Monats mit
/// Freigabe-Status ([WorkEntryStatus]) und erlaubt Einreichen/Bearbeiten/Anlegen.
/// Genehmigen/Ablehnen durch Manager läuft über den Mitarbeiterabschluss-Hub
/// (M5), wo Vorgesetzte fremde Einträge sehen. Urlaub/Krankmeldungen lesen die
/// eigenen [AbsenceRequest]s und stoßen Anträge über `showAbsenceRequestSheet` an.
class ZeiterfassungScreen extends StatefulWidget {
  const ZeiterfassungScreen({super.key, this.parentLabel = 'Zeitwirtschaft'});

  final String parentLabel;

  @override
  State<ZeiterfassungScreen> createState() => _ZeiterfassungScreenState();
}

class _ZeiterfassungScreenState extends State<ZeiterfassungScreen> {
  bool _filterKlaerung = false;

  static final _monthFormat = DateFormat('MMMM yyyy', 'de_DE');

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkProvider>();
    final schedule = context.watch<ScheduleProvider>();
    final user = work.currentUser;
    final month = work.selectedMonth;
    final spacing = context.spacing;

    final monthEntries = user == null
        ? const <WorkEntry>[]
        : (work.entries
            .where((e) =>
                e.userId == user.uid &&
                e.date.year == month.year &&
                e.date.month == month.month)
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime)));

    final myAbsences = user == null
        ? const <AbsenceRequest>[]
        : schedule.absenceRequests
            .where((a) => a.userId == user.uid)
            .toList();
    final urlaub = myAbsences
        .where((a) =>
            a.type != AbsenceType.sickness && a.type != AbsenceType.childSick)
        .toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    final krank = myAbsences
        .where((a) =>
            a.type == AbsenceType.sickness || a.type == AbsenceType.childSick)
        .toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: BreadcrumbAppBar(
          breadcrumbs: [
            BreadcrumbItem(
              label: widget.parentLabel,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const BreadcrumbItem(label: 'Zeiterfassung'),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(spacing.md, spacing.sm, spacing.md, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Vorheriger Monat',
                      onPressed: work.previousMonth,
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          _monthFormat.format(month),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Nächster Monat',
                      onPressed: work.nextMonth,
                    ),
                  ],
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(text: 'Arbeitszeiten'),
                  Tab(text: 'Urlaub'),
                  Tab(text: 'Krankmeldungen'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _ArbeitszeitenTab(
                      entries: monthEntries,
                      filterKlaerung: _filterKlaerung,
                      canEdit: user?.canEditTimeEntries ?? false,
                      onToggleFilter: (v) =>
                          setState(() => _filterKlaerung = v),
                      onAdd: () => _openEntryForm(context),
                      onEdit: (entry) => _openEntryForm(context, entry: entry),
                      onSubmit: (entry) =>
                          context.read<WorkProvider>().submitWorkEntry(entry),
                    ),
                    _AbsenceTab(
                      requests: urlaub,
                      emptyIcon: Icons.beach_access,
                      emptyMessage: 'Keine Urlaubs-/Freistellungsanträge.',
                      actionLabel: 'Urlaubsantrag',
                      onRequest: () => showAbsenceRequestSheet(
                        context,
                        defaultType: AbsenceType.vacation,
                      ),
                    ),
                    _AbsenceTab(
                      requests: krank,
                      emptyIcon: Icons.local_hospital_outlined,
                      emptyMessage: 'Keine Krankmeldungen.',
                      actionLabel: 'Krankmeldung',
                      onRequest: () => showAbsenceRequestSheet(
                        context,
                        defaultType: AbsenceType.sickness,
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
  }

  Future<void> _openEntryForm(BuildContext context, {WorkEntry? entry}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntryFormScreen(
          parentLabel: 'Zeiterfassung',
          entry: entry,
          initialDate: entry?.date,
        ),
      ),
    );
  }
}

class _ArbeitszeitenTab extends StatelessWidget {
  const _ArbeitszeitenTab({
    required this.entries,
    required this.filterKlaerung,
    required this.canEdit,
    required this.onToggleFilter,
    required this.onAdd,
    required this.onEdit,
    required this.onSubmit,
  });

  final List<WorkEntry> entries;
  final bool filterKlaerung;
  final bool canEdit;
  final ValueChanged<bool> onToggleFilter;
  final VoidCallback onAdd;
  final ValueChanged<WorkEntry> onEdit;
  final ValueChanged<WorkEntry> onSubmit;

  static final _dateFormat = DateFormat('dd.MM.yyyy', 'de_DE');
  static final _timeFormat = DateFormat('HH:mm', 'de_DE');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    final filtered = filterKlaerung
        ? entries
            .where((e) =>
                e.status == WorkEntryStatus.draft ||
                e.status == WorkEntryStatus.rejected)
            .toList()
        : entries;
    // Summe ohne abgelehnte Einträge.
    final totalHours = filtered
        .where((e) => e.status != WorkEntryStatus.rejected)
        .fold<double>(0, (sum, e) => sum + e.workedHours);

    return ListView(
      padding: EdgeInsets.fromLTRB(spacing.md, spacing.md, spacing.md, spacing.xl),
      children: [
        Row(
          children: [
            FilterChip(
              label: const Text('Nur Klärung'),
              selected: filterKlaerung,
              onSelected: onToggleFilter,
              avatar: filterKlaerung
                  ? const Icon(Icons.warning_amber, size: 16)
                  : null,
            ),
            const Spacer(),
            if (canEdit)
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Neue Arbeitszeit'),
              ),
          ],
        ),
        SizedBox(height: spacing.md),
        AppCard(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.sm + spacing.xs,
          ),
          child: Row(
            children: [
              Icon(Icons.summarize, size: 18, color: theme.colorScheme.primary),
              SizedBox(width: spacing.sm),
              Text('${filtered.length} Einträge',
                  style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(
                'Summe: ${totalHours.toStringAsFixed(1)} h',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.md),
        if (filtered.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: spacing.xl),
            child: AppEmptyState(
              icon: Icons.schedule_outlined,
              message: filterKlaerung
                  ? 'Keine Einträge mit Klärungsbedarf.'
                  : 'Keine Arbeitszeiten in diesem Monat.',
            ),
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: spacing.lg,
                columns: const [
                  DataColumn(label: Text('Tag')),
                  DataColumn(label: Text('Kommen')),
                  DataColumn(label: Text('Gehen')),
                  DataColumn(label: Text('Pause')),
                  DataColumn(label: Text('Stunden'), numeric: true),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Optionen')),
                ],
                rows: [
                  for (final e in filtered)
                    DataRow(cells: [
                      DataCell(Text(_dateFormat.format(e.date))),
                      DataCell(Text(_timeFormat.format(e.startTime))),
                      DataCell(Text(_timeFormat.format(e.endTime))),
                      DataCell(Text('${e.breakMinutes.round()} min')),
                      DataCell(Text('${e.workedHours.toStringAsFixed(1)} h')),
                      DataCell(_StatusChip(status: e.status)),
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (canEdit &&
                              (e.status == WorkEntryStatus.draft ||
                                  e.status == WorkEntryStatus.rejected))
                            IconButton(
                              icon: const Icon(Icons.send, size: 18),
                              tooltip: 'Einreichen',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => onSubmit(e),
                            ),
                          if (canEdit)
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              tooltip: 'Bearbeiten',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => onEdit(e),
                            ),
                        ],
                      )),
                    ]),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Farbiger Status-Badge für [WorkEntryStatus] (Statusfarben via [AppThemeColors]).
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final WorkEntryStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final color = switch (status) {
      WorkEntryStatus.approved => appColors.success,
      WorkEntryStatus.submitted => appColors.info,
      WorkEntryStatus.rejected => theme.colorScheme.error,
      WorkEntryStatus.draft => theme.colorScheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(context.radii.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Liste eigener Abwesenheiten (Urlaub bzw. Krankmeldungen) + Antrags-Button.
class _AbsenceTab extends StatelessWidget {
  const _AbsenceTab({
    required this.requests,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.actionLabel,
    required this.onRequest,
  });

  final List<AbsenceRequest> requests;
  final IconData emptyIcon;
  final String emptyMessage;
  final String actionLabel;
  final VoidCallback onRequest;

  static final _dateFormat = DateFormat('dd.MM.yyyy', 'de_DE');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final spacing = context.spacing;

    return ListView(
      padding: EdgeInsets.fromLTRB(spacing.md, spacing.md, spacing.md, spacing.xl),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: onRequest,
            icon: const Icon(Icons.add, size: 18),
            label: Text(actionLabel),
          ),
        ),
        SizedBox(height: spacing.md),
        if (requests.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: spacing.xl),
            child: AppEmptyState(icon: emptyIcon, message: emptyMessage),
          )
        else
          for (final r in requests) ...[
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.type.label,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: spacing.xxs),
                        Text(
                          r.halfDay
                              ? '${_dateFormat.format(r.startDate)} · halber Tag'
                              : '${_dateFormat.format(r.startDate)} – ${_dateFormat.format(r.endDate)} · ${r.kalenderTage} Tag(e)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (r.note != null && r.note!.isNotEmpty) ...[
                          SizedBox(height: spacing.xxs),
                          Text(r.note!, style: theme.textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  _AbsenceStatusChip(status: r.status, appColors: appColors),
                ],
              ),
            ),
            SizedBox(height: spacing.sm),
          ],
      ],
    );
  }
}

class _AbsenceStatusChip extends StatelessWidget {
  const _AbsenceStatusChip({required this.status, required this.appColors});

  final AbsenceStatus status;
  final AppThemeColors appColors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (status) {
      AbsenceStatus.approved => appColors.success,
      AbsenceStatus.pending => appColors.warning,
      AbsenceStatus.rejected => theme.colorScheme.error,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(context.radii.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
