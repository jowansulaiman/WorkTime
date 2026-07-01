import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/absence_request.dart';
import '../../providers/auth_provider.dart';
import '../../providers/schedule_provider.dart';
import '../../routing/shell_tab.dart';
import '../../ui/ui.dart';
import '../notification_screen.dart';

/// Abwesenheiten (AllTec-1:1) — rollen-adaptive Liste der Abwesenheitsanträge im
/// Zeitwirtschafts-Hub.
///
/// * **Mitarbeiter** sehen ihre **eigenen** Anträge (`allAbsenceRequests` ist für
///   Nicht-Manager bereits self-gescoped) und können sie bearbeiten/löschen,
///   solange sie offen sind.
/// * **Manager** sehen die **org-weite** Liste, genehmigen/lehnen offene Anträge
///   ab und springen in den [AbwesenheitskalenderScreen].
///
/// Reine Reuse-Ansicht: Anträge laufen über [showAbsenceRequestSheet], die
/// Mutationen über [ScheduleProvider] (`submitAbsenceRequest`,
/// `reviewAbsenceRequest`, `deleteAbsenceRequest`). Kein neues Modell, keine
/// eigene Persistenz.
class AbwesenheitenScreen extends StatefulWidget {
  const AbwesenheitenScreen({super.key, this.parentLabel = 'Zeitwirtschaft'});

  final String parentLabel;

  @override
  State<AbwesenheitenScreen> createState() => _AbwesenheitenScreenState();
}

class _AbwesenheitenScreenState extends State<AbwesenheitenScreen> {
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de_DE');

  /// `null` = alle Status anzeigen.
  AbsenceStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final schedule = context.watch<ScheduleProvider>();
    final user = context.watch<AuthProvider>().profile;
    final spacing = context.spacing;
    final canManage = user?.canManageShifts ?? false;

    final all = schedule.allAbsenceRequests;
    final filtered = all
        .where((r) => _statusFilter == null || r.status == _statusFilter)
        .toList()
      ..sort(_byPendingThenDateDesc);

    final pendingCount =
        all.where((r) => r.status == AbsenceStatus.pending).length;

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: widget.parentLabel,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const BreadcrumbItem(label: 'Abwesenheiten'),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  spacing.md, spacing.md, spacing.md, spacing.xl),
              children: [
                _RequestButtons(canManage: canManage),
                SizedBox(height: spacing.md),
                _StatusFilterBar(
                  selected: _statusFilter,
                  pendingCount: pendingCount,
                  onChanged: (value) => setState(() => _statusFilter = value),
                ),
                SizedBox(height: spacing.md),
                if (filtered.isEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: spacing.xl),
                    child: const EmptyState(
                      icon: Icons.beach_access_outlined,
                      message: 'Keine Abwesenheiten im gewählten Filter.',
                    ),
                  )
                else
                  for (final request in filtered) ...[
                    _AbsenceCard(
                      request: request,
                      showEmployee: canManage,
                      canManage: canManage,
                      isOwn: request.userId == user?.uid,
                      dateFmt: _dateFmt,
                    ),
                    SizedBox(height: spacing.sm),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static int _byPendingThenDateDesc(AbsenceRequest a, AbsenceRequest b) {
    final aPending = a.status == AbsenceStatus.pending;
    final bPending = b.status == AbsenceStatus.pending;
    if (aPending != bPending) return aPending ? -1 : 1;
    return b.startDate.compareTo(a.startDate);
  }
}

/// Antrags-Buttons (oben). Für Manager zusätzlich der Sprung in den Kalender.
class _RequestButtons extends StatelessWidget {
  const _RequestButtons({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final now = DateTime.now();

    void request(AbsenceType type) {
      showAbsenceRequestSheet(
        context,
        defaultType: type,
        initialStart: now,
        initialEnd: now,
      );
    }

    return Wrap(
      spacing: spacing.sm,
      runSpacing: spacing.sm,
      children: [
        FilledButton.icon(
          onPressed: () => request(AbsenceType.vacation),
          icon: const Icon(Icons.beach_access_outlined, size: 18),
          label: const Text('Urlaubsantrag'),
        ),
        FilledButton.tonalIcon(
          onPressed: () => request(AbsenceType.sickness),
          icon: const Icon(Icons.local_hospital_outlined, size: 18),
          label: const Text('Krankmeldung'),
        ),
        OutlinedButton.icon(
          onPressed: () => request(AbsenceType.timeOff),
          icon: const Icon(Icons.schedule_outlined, size: 18),
          label: const Text('Zeitausgleich'),
        ),
        if (canManage)
          OutlinedButton.icon(
            onPressed: () =>
                context.push(AppRoutes.zeitAbwesenheitenKalender),
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: const Text('Kalender'),
          ),
      ],
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({
    required this.selected,
    required this.pendingCount,
    required this.onChanged,
  });

  final AbsenceStatus? selected;
  final int pendingCount;
  final ValueChanged<AbsenceStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return Wrap(
      spacing: spacing.sm,
      children: [
        ChoiceChip(
          label: const Text('Alle'),
          selected: selected == null,
          onSelected: (_) => onChanged(null),
        ),
        ChoiceChip(
          label: Text(
            pendingCount > 0 ? 'Offen ($pendingCount)' : 'Offen',
          ),
          selected: selected == AbsenceStatus.pending,
          onSelected: (_) => onChanged(AbsenceStatus.pending),
        ),
        ChoiceChip(
          label: const Text('Genehmigt'),
          selected: selected == AbsenceStatus.approved,
          onSelected: (_) => onChanged(AbsenceStatus.approved),
        ),
        ChoiceChip(
          label: const Text('Abgelehnt'),
          selected: selected == AbsenceStatus.rejected,
          onSelected: (_) => onChanged(AbsenceStatus.rejected),
        ),
      ],
    );
  }
}

class _AbsenceCard extends StatelessWidget {
  const _AbsenceCard({
    required this.request,
    required this.showEmployee,
    required this.canManage,
    required this.isOwn,
    required this.dateFmt,
  });

  final AbsenceRequest request;
  final bool showEmployee;
  final bool canManage;
  final bool isOwn;
  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    final spacing = context.spacing;

    final title = showEmployee
        ? '${request.employeeName} · ${request.type.label}'
        : request.type.label;

    final pending = request.status == AbsenceStatus.pending;
    // Manager dürfen offene fremde/eigene Anträge entscheiden.
    final canReview = canManage && pending;
    // Eigene offene Anträge darf der Mitarbeiter selbst bearbeiten/löschen.
    final canEditOwn = isOwn && pending;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${dateFmt.format(request.startDate)} – '
                      '${dateFmt.format(request.endDate)} · '
                      '${_tageLabel(request)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if ((request.note ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        request.note!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: spacing.sm),
              _StatusChip(status: request.status, appColors: appColors),
            ],
          ),
          if (_needsAuShield(request)) ...[
            SizedBox(height: spacing.sm),
            _AuShield(attached: request.eauAttached),
          ],
          if (canReview) ...[
            SizedBox(height: spacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _review(context, AbsenceStatus.rejected),
                  icon: Icon(Icons.close, size: 18, color: colorScheme.error),
                  label: Text('Ablehnen',
                      style: TextStyle(color: colorScheme.error)),
                ),
                SizedBox(width: spacing.sm),
                FilledButton.icon(
                  onPressed: () => _review(context, AbsenceStatus.approved),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Genehmigen'),
                ),
              ],
            ),
          ] else if (canEditOwn) ...[
            SizedBox(height: spacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => showAbsenceRequestSheet(
                    context,
                    defaultType: request.type,
                    initialRequest: request,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Bearbeiten'),
                ),
                SizedBox(width: spacing.sm),
                TextButton.icon(
                  onPressed: () => _confirmDelete(context),
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: colorScheme.error),
                  label: Text('Löschen',
                      style: TextStyle(color: colorScheme.error)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _review(BuildContext context, AbsenceStatus status) async {
    final id = request.id;
    if (id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final schedule = context.read<ScheduleProvider>();
    try {
      await schedule.reviewAbsenceRequest(requestId: id, status: status);
      messenger.showSnackBar(
        SnackBar(
          content: Text(status == AbsenceStatus.approved
              ? 'Antrag genehmigt.'
              : 'Antrag abgelehnt.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Aktion fehlgeschlagen.')),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final id = request.id;
    if (id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final schedule = context.read<ScheduleProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Antrag löschen?'),
        content: Text(
          'Soll der Antrag „${request.type.label}" wirklich gelöscht werden?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await schedule.deleteAbsenceRequest(id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Antrag gelöscht.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Löschen fehlgeschlagen.')),
      );
    }
  }

  static String _tageLabel(AbsenceRequest r) {
    if (r.halfDay) {
      final period = r.halfDayPeriod;
      return period == null ? 'halber Tag' : 'halber Tag (${period.label})';
    }
    return '${r.kalenderTage} Tag(e)';
  }

  /// AU-Nachweis-Pflicht: Krankmeldung ab 3 Kalendertagen (§5 EFZG).
  static bool _needsAuShield(AbsenceRequest r) =>
      r.type == AbsenceType.sickness && r.kalenderTage >= 3;
}

/// Status-Chip im 3-Farben-Schema (success/warning/error) — gespiegelt aus der
/// Zeiterfassung, hier wiederverwendbar in diesem Screen.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.appColors});

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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// AU-Nachweis-Schild: rot, solange die Bescheinigung fehlt; grün, sobald sie
/// (per `eauAttached`-Flag) hinterlegt ist.
class _AuShield extends StatelessWidget {
  const _AuShield({required this.attached});

  final bool attached;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        attached ? theme.appColors.success : theme.colorScheme.error;
    return Row(
      children: [
        Icon(attached ? Icons.verified_user_outlined : Icons.gpp_maybe_outlined,
            size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          attached ? 'AU-Nachweis vorhanden' : 'AU-Nachweis fehlt (ab 3 Tagen)',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
