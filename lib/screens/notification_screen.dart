import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/absence_request.dart';
import '../models/shift.dart';
import '../providers/auth_provider.dart';
import '../providers/schedule_provider.dart';
import '../widgets/breadcrumb_app_bar.dart';

Future<bool?> showAbsenceRequestSheet(
  BuildContext context, {
  required AbsenceType defaultType,
  DateTime? initialStart,
  DateTime? initialEnd,
  AbsenceRequest? initialRequest,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _AbsenceRequestSheet(
      defaultType: defaultType,
      initialStart: initialStart,
      initialEnd: initialEnd,
      initialRequest: initialRequest,
    ),
  );
}

enum _InboxFilter { all, urgent, requests, swaps, shifts, updates }

enum _InboxItemKind { request, swap, shift, update }

class _InboxAction {
  const _InboxAction({
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.successMessage,
  });

  final String label;
  final Future<bool> Function(BuildContext context) onPressed;
  final bool primary;
  final String? successMessage;
}

class _InboxItem {
  const _InboxItem({
    required this.kind,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.color,
    this.badge,
    this.actions = const [],
  });

  final _InboxItemKind kind;
  final IconData icon;
  final String title;
  final String subtitle;
  final DateTime time;
  final Color color;
  final String? badge;
  final List<_InboxAction> actions;
}

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({
    super.key,
    this.parentLabel,
    this.canNavigateBack = false,
    this.onNavigateBack,
  });

  final String? parentLabel;
  final bool canNavigateBack;
  final VoidCallback? onNavigateBack;

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  _InboxFilter _filter = _InboxFilter.all;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final schedule = context.watch<ScheduleProvider>();
    final currentUser = auth.profile;
    final canManageShifts = currentUser?.canManageShifts ?? false;
    final isTeamLead = currentUser?.isTeamLead ?? false;
    final canCreateOwnRequests =
        currentUser != null && (!canManageShifts || isTeamLead);
    final canViewSchedule = currentUser?.canViewSchedule ?? false;
    final now = DateTime.now();
    final colorScheme = Theme.of(context).colorScheme;
    final ownUserId = currentUser?.uid ?? '';
    final pendingAbsences = schedule.allAbsenceRequests
        .where((request) => request.status == AbsenceStatus.pending)
        .where((request) => canManageShifts || request.userId == ownUserId)
        .toList(growable: false)
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final reviewedAbsences = schedule.allAbsenceRequests
        .where((request) => request.status != AbsenceStatus.pending)
        .where((request) => request.userId == ownUserId)
        .toList(growable: false)
      ..sort((a, b) => (b.updatedAt ?? b.startDate).compareTo(
            a.updatedAt ?? a.startDate,
          ));
    final pendingSwaps = schedule.shifts
        .where((shift) => shift.swapStatus == 'pending')
        .where((shift) => canManageShifts || shift.userId == ownUserId)
        .toList(growable: false)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final upcomingOwnShifts = schedule.shifts
        .where((shift) => canViewSchedule)
        .where((shift) => shift.userId == ownUserId)
        .where((shift) => shift.endTime.isAfter(now))
        .where((shift) => shift.status != ShiftStatus.cancelled)
        .toList(growable: false)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final items = _buildItems(
      context,
      canManageShifts: canManageShifts,
      isTeamLead: isTeamLead,
      ownUserId: ownUserId,
      pendingAbsences: pendingAbsences,
      reviewedAbsences: reviewedAbsences,
      pendingSwaps: pendingSwaps,
      upcomingOwnShifts: upcomingOwnShifts,
    );
    final filteredItems = items.where((item) => _matchesFilter(item)).toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    final urgentCount = pendingAbsences.length + pendingSwaps.length;
    final isEmbeddedInShell = Scaffold.maybeOf(context) != null;

    final content = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: CustomScrollView(
            slivers: [
              if (isEmbeddedInShell)
                SliverToBoxAdapter(
                  child: ShellBreadcrumb(
                    breadcrumbs: const [BreadcrumbItem(label: 'Anfragen')],
                    onBack:
                        widget.canNavigateBack ? widget.onNavigateBack : null,
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    isEmbeddedInShell ? 10 : 16,
                    20,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Anfragen',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isTeamLead
                            ? 'Team-Anfragen priorisieren und eigene Antraege direkt an den Admin senden.'
                            : canManageShifts
                                ? 'Krankmeldungen, Tausch und Freigaben mit Prioritaet abarbeiten.'
                                : 'Eigene Antraege, Schichtaenderungen und Tausch-Rueckmeldungen im Blick.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 18),
                      _InboxHeroCard(
                        canManageShifts: canManageShifts,
                        isTeamLead: isTeamLead,
                        urgentCount: urgentCount,
                        pendingAbsences: pendingAbsences.length,
                        pendingSwaps: pendingSwaps.length,
                        reviewedAbsences: reviewedAbsences.length,
                      ),
                      const SizedBox(height: 12),
                      if (canCreateOwnRequests)
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _InboxQuickButton(
                              icon: Icons.local_hospital_outlined,
                              label: 'Krank',
                              onTap: () => showAbsenceRequestSheet(
                                context,
                                defaultType: AbsenceType.sickness,
                                initialStart: DateTime.now(),
                                initialEnd: DateTime.now(),
                              ),
                            ),
                            _InboxQuickButton(
                              icon: Icons.beach_access_outlined,
                              label: 'Urlaub',
                              onTap: () => showAbsenceRequestSheet(
                                context,
                                defaultType: AbsenceType.vacation,
                                initialStart: DateTime.now(),
                                initialEnd: DateTime.now(),
                              ),
                            ),
                            _InboxQuickButton(
                              icon: Icons.block_outlined,
                              label: 'Nicht verfuegbar',
                              onTap: () => showAbsenceRequestSheet(
                                context,
                                defaultType: AbsenceType.unavailable,
                                initialStart: DateTime.now(),
                                initialEnd: DateTime.now(),
                              ),
                            ),
                          ],
                        ),
                      if (isTeamLead)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'Deine eigenen Antraege landen zur Freigabe beim Admin.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      if (canCreateOwnRequests) const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final entry in _filterEntries(
                              canManageShifts: canManageShifts,
                            )) ...[
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  selected: _filter == entry.filter,
                                  label: Text(entry.label),
                                  onSelected: (_) =>
                                      setState(() => _filter = entry.filter),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (filteredItems.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 48,
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          canCreateOwnRequests
                              ? 'Keine passenden Eintraege. Neue Antraege kannst du direkt hier stellen.'
                              : canManageShifts
                                  ? 'Im aktuellen Filter gibt es keine offenen Vorgänge.'
                                  : 'Keine passenden Eintraege. Neue Antraege kannst du direkt hier stellen.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = filteredItems[index];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: _InboxItemCard(item: item),
                      );
                    },
                    childCount: filteredItems.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ),
        ),
      ),
    );

    final materialContent = Material(
      color: Colors.transparent,
      child: content,
    );

    if (isEmbeddedInShell) {
      return materialContent;
    }

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: widget.parentLabel ?? 'Heute',
            onTap: () => Navigator.of(context).pop(),
          ),
          const BreadcrumbItem(label: 'Anfragen'),
        ],
      ),
      body: materialContent,
    );
  }

  List<({String label, _InboxFilter filter})> _filterEntries({
    required bool canManageShifts,
  }) {
    return [
      (label: 'Alle', filter: _InboxFilter.all),
      (
        label: canManageShifts ? 'Kritisch' : 'Offen',
        filter: _InboxFilter.urgent,
      ),
      (label: 'Antraege', filter: _InboxFilter.requests),
      (label: 'Tausch', filter: _InboxFilter.swaps),
      (
        label: canManageShifts ? 'Updates' : 'Schichten',
        filter: canManageShifts ? _InboxFilter.updates : _InboxFilter.shifts,
      ),
    ];
  }

  bool _matchesFilter(_InboxItem item) {
    return switch (_filter) {
      _InboxFilter.all => true,
      _InboxFilter.urgent =>
        item.kind == _InboxItemKind.request || item.kind == _InboxItemKind.swap,
      _InboxFilter.requests => item.kind == _InboxItemKind.request,
      _InboxFilter.swaps => item.kind == _InboxItemKind.swap,
      _InboxFilter.shifts => item.kind == _InboxItemKind.shift,
      _InboxFilter.updates => item.kind == _InboxItemKind.update,
    };
  }

  List<_InboxItem> _buildItems(
    BuildContext context, {
    required bool canManageShifts,
    required bool isTeamLead,
    required String ownUserId,
    required List<AbsenceRequest> pendingAbsences,
    required List<AbsenceRequest> reviewedAbsences,
    required List<Shift> pendingSwaps,
    required List<Shift> upcomingOwnShifts,
  }) {
    final schedule = context.read<ScheduleProvider>();
    final dateFmt = DateFormat('dd.MM.yyyy', 'de_DE');
    final shiftFmt = DateFormat('EEE, dd.MM. HH:mm', 'de_DE');
    final colorScheme = Theme.of(context).colorScheme;
    final items = <_InboxItem>[
      ...pendingAbsences.map(
        (absence) {
          final canEditOwnPendingRequest = absence.userId == ownUserId &&
              absence.status == AbsenceStatus.pending;
          final canReviewAbsence = !canEditOwnPendingRequest &&
              canManageShifts &&
              (!isTeamLead || absence.userId != ownUserId);
          return _InboxItem(
            kind: _InboxItemKind.request,
            icon: Icons.event_note_outlined,
            title: canManageShifts
                ? '${absence.employeeName} · ${absence.type.label}'
                : '${absence.type.label} eingereicht',
            subtitle:
                '${dateFmt.format(absence.startDate)} - ${dateFmt.format(absence.endDate)}'
                '${absence.note?.trim().isEmpty == false ? '\n${absence.note!.trim()}' : ''}',
            time: absence.createdAt ?? absence.startDate,
            color: colorScheme.tertiary,
            badge: absence.status.label,
            actions: canReviewAbsence && absence.id != null
                ? [
                    _InboxAction(
                      label: 'Ablehnen',
                      successMessage: 'Antrag abgelehnt',
                      onPressed: (context) async {
                        await schedule.reviewAbsenceRequest(
                          requestId: absence.id!,
                          status: AbsenceStatus.rejected,
                        );
                        return true;
                      },
                    ),
                    _InboxAction(
                      label: 'Genehmigen',
                      primary: true,
                      successMessage: 'Antrag genehmigt',
                      onPressed: (context) async {
                        await schedule.reviewAbsenceRequest(
                          requestId: absence.id!,
                          status: AbsenceStatus.approved,
                        );
                        return true;
                      },
                    ),
                  ]
                : canEditOwnPendingRequest && absence.id != null
                    ? [
                        _InboxAction(
                          label: 'Bearbeiten',
                          onPressed: (context) async {
                            await showAbsenceRequestSheet(
                              context,
                              defaultType: absence.type,
                              initialRequest: absence,
                            );
                            return false;
                          },
                        ),
                        _InboxAction(
                          label: 'Loeschen',
                          onPressed: (context) async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('Antrag loeschen'),
                                content: const Text(
                                  'Moechtest du diesen offenen Antrag wirklich loeschen?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(false),
                                    child: const Text('Abbrechen'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(true),
                                    child: const Text('Loeschen'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) {
                              return false;
                            }
                            await schedule.deleteAbsenceRequest(absence.id!);
                            return true;
                          },
                          successMessage: 'Antrag geloescht',
                        ),
                      ]
                    : const [],
          );
        },
      ),
      ...pendingSwaps.map(
        (shift) => _InboxItem(
          kind: _InboxItemKind.swap,
          icon: Icons.swap_horiz,
          title: canManageShifts
              ? 'Tausch-Anfrage · ${shift.employeeName}'
              : 'Tausch in Bearbeitung',
          subtitle:
              '${shift.title} · ${shiftFmt.format(shift.startTime)} - ${DateFormat('HH:mm').format(shift.endTime)}',
          time: shift.updatedAt ?? shift.startTime,
          color: colorScheme.primary,
          badge: 'Offen',
          actions: canManageShifts && shift.id != null
              ? [
                  _InboxAction(
                    label: 'Ablehnen',
                    successMessage: 'Tausch-Anfrage abgelehnt',
                    onPressed: (context) async {
                      await schedule.reviewShiftSwap(
                        shiftId: shift.id!,
                        approved: false,
                      );
                      return true;
                    },
                  ),
                  _InboxAction(
                    label: 'Freigeben',
                    primary: true,
                    successMessage: 'Tausch-Anfrage freigegeben',
                    onPressed: (context) async {
                      await schedule.reviewShiftSwap(
                        shiftId: shift.id!,
                        approved: true,
                      );
                      return true;
                    },
                  ),
                ]
              : const [],
        ),
      ),
      if (!canManageShifts)
        ...upcomingOwnShifts.take(6).map(
              (shift) => _InboxItem(
                kind: _InboxItemKind.shift,
                icon: Icons.schedule_outlined,
                title: 'Kommende Schicht · ${shift.title}',
                subtitle:
                    '${shiftFmt.format(shift.startTime)} - ${DateFormat('HH:mm').format(shift.endTime)}'
                    '${shift.effectiveSiteLabel == null ? '' : '\n${shift.effectiveSiteLabel}'}',
                time: shift.startTime,
                color: colorScheme.secondary,
                badge: shift.status.label,
                actions: shift.id == null || shift.swapStatus == 'pending'
                    ? const []
                    : [
                        _InboxAction(
                          label: 'Tausch',
                          successMessage: 'Tausch-Anfrage gesendet',
                          onPressed: (context) async {
                            await schedule.requestShiftSwap(shift.id!);
                            return true;
                          },
                        ),
                        _InboxAction(
                          label: 'Krank melden',
                          primary: true,
                          onPressed: (context) async =>
                              await showAbsenceRequestSheet(
                                context,
                                defaultType: AbsenceType.sickness,
                                initialStart: shift.startTime,
                                initialEnd: shift.endTime,
                              ) ??
                              false,
                        ),
                      ],
              ),
            ),
      ...reviewedAbsences.map(
        (absence) {
          final canManageApprovedVacation = canManageShifts &&
              absence.type == AbsenceType.vacation &&
              absence.status == AbsenceStatus.approved &&
              absence.id != null;
          return _InboxItem(
            kind: _InboxItemKind.update,
            icon: absence.status == AbsenceStatus.approved
                ? Icons.check_circle_outline
                : Icons.cancel_outlined,
            title:
                '${absence.type.label} ${absence.status == AbsenceStatus.approved ? 'genehmigt' : 'abgelehnt'}',
            subtitle:
                '${dateFmt.format(absence.startDate)} - ${dateFmt.format(absence.endDate)}',
            time: absence.updatedAt ?? absence.startDate,
            color: absence.status == AbsenceStatus.approved
                ? colorScheme.primary
                : colorScheme.error,
            badge: absence.status.label,
            actions: canManageApprovedVacation
                ? [
                    _InboxAction(
                      label: 'Bearbeiten',
                      onPressed: (context) async {
                        await showAbsenceRequestSheet(
                          context,
                          defaultType: absence.type,
                          initialRequest: absence,
                        );
                        return false;
                      },
                    ),
                    _InboxAction(
                      label: 'Loeschen',
                      onPressed: (context) async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Urlaub loeschen'),
                            content: const Text(
                              'Moechtest du diesen genehmigten Urlaub wirklich loeschen?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                                child: const Text('Abbrechen'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(true),
                                child: const Text('Loeschen'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) {
                          return false;
                        }
                        await schedule.deleteAbsenceRequest(absence.id!);
                        return true;
                      },
                      successMessage: 'Urlaub geloescht',
                    ),
                  ]
                : const [],
          );
        },
      ),
    ];

    return items;
  }
}

class _InboxHeroCard extends StatelessWidget {
  const _InboxHeroCard({
    required this.canManageShifts,
    required this.isTeamLead,
    required this.urgentCount,
    required this.pendingAbsences,
    required this.pendingSwaps,
    required this.reviewedAbsences,
  });

  final bool canManageShifts;
  final bool isTeamLead;
  final int urgentCount;
  final int pendingAbsences;
  final int pendingSwaps;
  final int reviewedAbsences;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              canManageShifts
                  ? 'Arbeitsdruck jetzt'
                  : 'Deine offenen Rueckmeldungen',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              isTeamLead
                  ? '$urgentCount Team-Vorgaenge offen. Eigene Antraege gehen direkt an den Admin.'
                  : canManageShifts
                      ? '$urgentCount Vorgaenge brauchen eine Entscheidung. Krankmeldungen und Tauschanfragen stehen oben.'
                      : '$pendingAbsences offene Antraege, $pendingSwaps laufende Tausche und $reviewedAbsences letzte Antworten.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HeroPill(
                  icon: Icons.event_note_outlined,
                  label: '$pendingAbsences Antraege',
                ),
                _HeroPill(
                  icon: Icons.swap_horiz,
                  label: '$pendingSwaps Tausch',
                ),
                _HeroPill(
                  icon: Icons.notifications_active_outlined,
                  label: canManageShifts
                      ? '$urgentCount kritisch'
                      : '$reviewedAbsences Updates',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}

class _InboxQuickButton extends StatelessWidget {
  const _InboxQuickButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _InboxItemCard extends StatefulWidget {
  const _InboxItemCard({required this.item});

  final _InboxItem item;

  @override
  State<_InboxItemCard> createState() => _InboxItemCardState();
}

class _InboxItemCardState extends State<_InboxItemCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: item.color.withValues(alpha: 0.14),
                  child: Icon(item.icon, color: item.color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.subtitle,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (item.badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: item.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          item.badge!,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: item.color,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _formatTime(item.time),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (item.actions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: item.actions.map((action) {
                  final child = action.primary
                      ? FilledButton(
                          onPressed:
                              _busy ? null : () => _runAction(context, action),
                          child: Text(_busy ? 'Bitte warten...' : action.label),
                        )
                      : OutlinedButton(
                          onPressed:
                              _busy ? null : () => _runAction(context, action),
                          child: Text(action.label),
                        );
                  return child;
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _runAction(BuildContext context, _InboxAction action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final handled = await action.onPressed(context);
      if (!context.mounted || !handled) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action.successMessage ?? '${action.label} gespeichert'),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  static String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.isNegative) {
      if (diff.inDays.abs() == 0) {
        return 'Heute';
      }
      if (diff.inDays.abs() == 1) {
        return 'Morgen';
      }
      return DateFormat('dd.MM.').format(time);
    }
    if (diff.inMinutes < 60) {
      return 'vor ${diff.inMinutes} min';
    }
    if (diff.inHours < 24) {
      return 'vor ${diff.inHours} h';
    }
    if (diff.inDays < 7) {
      return 'vor ${diff.inDays} Tagen';
    }
    return DateFormat('dd.MM.').format(time);
  }
}

class _AbsenceRequestSheet extends StatefulWidget {
  const _AbsenceRequestSheet({
    required this.defaultType,
    this.initialStart,
    this.initialEnd,
    this.initialRequest,
  });

  final AbsenceType defaultType;
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final AbsenceRequest? initialRequest;

  @override
  State<_AbsenceRequestSheet> createState() => _AbsenceRequestSheetState();
}

class _AbsenceRequestSheetState extends State<_AbsenceRequestSheet> {
  late AbsenceType _type;
  late DateTime _startDate;
  late DateTime _endDate;
  final TextEditingController _noteController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = widget.initialRequest?.type ?? widget.defaultType;
    final now = DateTime.now();
    _startDate = DateTime(
      (widget.initialRequest?.startDate ?? widget.initialStart ?? now).year,
      (widget.initialRequest?.startDate ?? widget.initialStart ?? now).month,
      (widget.initialRequest?.startDate ?? widget.initialStart ?? now).day,
    );
    _endDate = DateTime(
      (widget.initialRequest?.endDate ??
              widget.initialEnd ??
              widget.initialStart ??
              now)
          .year,
      (widget.initialRequest?.endDate ??
              widget.initialEnd ??
              widget.initialStart ??
              now)
          .month,
      (widget.initialRequest?.endDate ??
              widget.initialEnd ??
              widget.initialStart ??
              now)
          .day,
    );
    _noteController.text = widget.initialRequest?.note ?? '';
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd.MM.yyyy', 'de_DE');
    final isEditing = widget.initialRequest != null;
    final isApprovedVacationEdit =
        widget.initialRequest?.status == AbsenceStatus.approved &&
            widget.initialRequest?.type == AbsenceType.vacation;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEditing ? 'Antrag bearbeiten' : 'Antrag erstellen',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              isEditing
                  ? isApprovedVacationEdit
                      ? 'Genehmigten Urlaub im Zeitraum oder Hinweis anpassen.'
                      : 'Zeitraum, Art oder Hinweis anpassen und erneut speichern.'
                  : 'Kurz halten, sauber absenden. Blockierende Regeln prueft der Planungsflow spaeter automatisch.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 18),
            SegmentedButton<AbsenceType>(
              segments: const [
                ButtonSegment(
                  value: AbsenceType.vacation,
                  icon: Icon(Icons.beach_access_outlined),
                  label: Text('Urlaub'),
                ),
                ButtonSegment(
                  value: AbsenceType.sickness,
                  icon: Icon(Icons.local_hospital_outlined),
                  label: Text('Krank'),
                ),
                ButtonSegment(
                  value: AbsenceType.unavailable,
                  icon: Icon(Icons.block_outlined),
                  label: Text('Nicht verf.'),
                ),
              ],
              selected: {_type},
              onSelectionChanged: isApprovedVacationEdit
                  ? null
                  : (selection) => setState(() => _type = selection.first),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Von'),
                    subtitle: Text(dateFmt.format(_startDate)),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: () => _pickDate(isStart: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bis'),
                    subtitle: Text(dateFmt.format(_endDate)),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Hinweis',
                hintText: 'Optionaler Kommentar fuer den Planer',
                prefixIcon: Icon(Icons.edit_note_outlined),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        isEditing ? Icons.save_outlined : Icons.send_outlined,
                      ),
                label: Text(
                  _saving
                      ? 'Wird gespeichert...'
                      : isEditing
                          ? 'Aenderungen speichern'
                          : 'Antrag senden',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final selectedDate = isStart ? _startDate : _endDate;
    final minAllowed = DateTime.now().subtract(const Duration(days: 30));
    final maxAllowed = DateTime.now().add(const Duration(days: 365));
    final firstDate = selectedDate.isBefore(minAllowed)
        ? DateTime(selectedDate.year, selectedDate.month, selectedDate.day)
        : minAllowed;
    final lastDate = selectedDate.isAfter(maxAllowed)
        ? DateTime(selectedDate.year, selectedDate.month, selectedDate.day)
        : maxAllowed;
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: firstDate,
      lastDate: lastDate,
      locale: const Locale('de', 'DE'),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = picked.isBefore(_startDate) ? _startDate : picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_endDate.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Das Enddatum muss nach dem Startdatum liegen.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<ScheduleProvider>().submitAbsenceRequest(
            AbsenceRequest(
              id: widget.initialRequest?.id,
              orgId: '',
              userId: '',
              employeeName: '',
              startDate: _startDate,
              endDate: _endDate,
              type: _type,
              note: _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
              status: widget.initialRequest?.status ?? AbsenceStatus.pending,
              reviewedByUid: widget.initialRequest?.reviewedByUid,
              createdAt: widget.initialRequest?.createdAt,
              updatedAt: widget.initialRequest?.updatedAt,
            ),
          );
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop(true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            widget.initialRequest == null
                ? 'Antrag gespeichert'
                : 'Antrag aktualisiert',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
