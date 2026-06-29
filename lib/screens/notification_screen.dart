import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/abwesenheit_matrix.dart';
import '../core/urlaub_calculator.dart';
import '../models/absence_request.dart';
import '../models/customer_order.dart';
import '../models/product.dart';
import '../models/shift.dart';
import '../models/shift_swap_request.dart';
import '../models/swap_credit.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/personal_provider.dart';
import '../providers/schedule_provider.dart';
import '../theme/theme_extensions.dart';
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

/// In welchen der drei Anfragen-Bereiche ein Eintrag gehört. Wird an JEDER
/// Erzeugungsstelle explizit gesetzt (Pflichtparameter, kein Default), damit
/// kein Eintrag versehentlich falsch einsortiert wird:
/// - [todo]: braucht eine Entscheidung/Freigabe von mir (immer offen, oben).
/// - [inProgress]: offen, aber wartet auf andere / nur Komfort (eingeklappt).
/// - [history]: reine Info ohne Handlungsdruck (eingeklappt).
enum _InboxSection { todo, inProgress, history }

/// Sortierung im Bereich „Läuft & wartet": kommende Schichten zuerst (nach
/// Startzeit), danach übrige Vorgänge nach zuletzt angefasst (neueste oben).
int _byShiftThenRecency(_InboxItem a, _InboxItem b) {
  final aShift = a.kind == _InboxItemKind.shift;
  final bShift = b.kind == _InboxItemKind.shift;
  if (aShift && bShift) return a.time.compareTo(b.time);
  if (aShift) return -1;
  if (bShift) return 1;
  return b.time.compareTo(a.time);
}

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
    required this.section,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.color,
    this.badge,
    this.actions = const [],
  });

  final _InboxItemKind kind;
  final _InboxSection section;
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
  bool _inProgressExpanded = false;
  bool _historyExpanded = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final schedule = context.watch<ScheduleProvider>();
    final inventory = context.watch<InventoryProvider>();
    final currentUser = auth.profile;
    final canViewInventory = currentUser?.canViewInventory ?? false;
    final canManageInventory = currentUser?.canManageInventory ?? false;
    final dueCustomerOrders =
        canViewInventory ? inventory.ordersDueSoonNotPrepared() : <CustomerOrder>[];
    final lowStock =
        canViewInventory ? inventory.lowStockProducts() : <Product>[];
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
      dueCustomerOrders: dueCustomerOrders,
      lowStockProducts: lowStock,
      canManageInventory: canManageInventory,
    );
    final filteredItems =
        items.where((item) => _matchesFilter(item)).toList();
    // Drei Bereiche statt einer flachen, rein nach Datum sortierten Liste
    // (das war der „durcheinander"-Grund): „Zu erledigen" braucht eine
    // Entscheidung von mir (immer offen, oben), „Läuft & wartet" und
    // „Verlauf & Hinweise" sind sekundär (eingeklappt). todoItems bleibt in
    // Quell-Reihenfolge: pendingAbsences sind bereits nach startDate, Swaps
    // nach Startzeit vorsortiert → grob nach Fälligkeit, Dringendstes zuerst.
    final todoItems = filteredItems
        .where((item) => item.section == _InboxSection.todo)
        .toList();
    final inProgressItems = filteredItems
        .where((item) => item.section == _InboxSection.inProgress)
        .toList()
      ..sort(_byShiftThenRecency);
    final historyItems = filteredItems
        .where((item) => item.section == _InboxSection.history)
        .toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    // Hero/„Kritisch" zeigt die echte Zahl offener Entscheidungen
    // (ungefiltert), nicht die der aktuellen Filteransicht.
    final urgentCount =
        items.where((item) => item.section == _InboxSection.todo).length;
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
              ..._buildSectionSlivers(
                context: context,
                todoItems: todoItems,
                inProgressItems: inProgressItems,
                historyItems: historyItems,
                canCreateOwnRequests: canCreateOwnRequests,
                canManageShifts: canManageShifts,
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
      _InboxFilter.urgent => item.section == _InboxSection.todo,
      _InboxFilter.requests => item.kind == _InboxItemKind.request,
      _InboxFilter.swaps => item.kind == _InboxItemKind.swap,
      _InboxFilter.shifts => item.kind == _InboxItemKind.shift,
      _InboxFilter.updates => item.section != _InboxSection.todo,
    };
  }

  /// Baut die drei Bereiche („Zu erledigen" offen, „Läuft & wartet" und
  /// „Verlauf & Hinweise" eingeklappt) als Sliver-Liste. Leere Bereiche werden
  /// weggelassen; ist alles leer, erscheint die bisherige Inbox-Leermeldung.
  List<Widget> _buildSectionSlivers({
    required BuildContext context,
    required List<_InboxItem> todoItems,
    required List<_InboxItem> inProgressItems,
    required List<_InboxItem> historyItems,
    required bool canCreateOwnRequests,
    required bool canManageShifts,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final allEmpty = todoItems.isEmpty &&
        inProgressItems.isEmpty &&
        historyItems.isEmpty;
    if (allEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 48,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  canCreateOwnRequests
                      ? 'Keine passenden Eintraege. Neue Antraege kannst du direkt hier stellen.'
                      : canManageShifts
                          ? 'Im aktuellen Filter gibt es keine offenen Vorgänge.'
                          : 'Keine passenden Eintraege. Neue Antraege kannst du direkt hier stellen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    SliverList cardSliver(List<_InboxItem> list, {required bool dense}) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _InboxItemCard(item: list[index], dense: dense),
          ),
          childCount: list.length,
        ),
      );
    }

    final slivers = <Widget>[];
    // „Zu erledigen" wird auch leer gezeigt (mit ruhiger Erfolgsmeldung),
    // solange es der primäre Blick ist – sonst nur, wenn etwas drin ist.
    final showTodo = todoItems.isNotEmpty ||
        _filter == _InboxFilter.all ||
        _filter == _InboxFilter.urgent;
    if (showTodo) {
      slivers.add(
        SliverToBoxAdapter(
          child: _SectionHeader(
            title: 'Zu erledigen',
            count: todoItems.length,
            emphasize: true,
          ),
        ),
      );
      if (todoItems.isEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.appColors.successContainer
                      .withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: theme.appColors.onSuccessContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Alles erledigt – nichts wartet auf deine Entscheidung.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.appColors.onSuccessContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      } else {
        slivers.add(cardSliver(todoItems, dense: false));
      }
    }
    if (inProgressItems.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _CollapsibleSection(
            title: 'Läuft & wartet',
            count: inProgressItems.length,
            expanded: _inProgressExpanded,
            onToggle: (v) => setState(() => _inProgressExpanded = v),
            items: inProgressItems,
          ),
        ),
      );
    }
    if (historyItems.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _CollapsibleSection(
            title: 'Verlauf & Hinweise',
            count: historyItems.length,
            expanded: _historyExpanded,
            onToggle: (v) => setState(() => _historyExpanded = v),
            items: historyItems,
          ),
        ),
      );
    }
    return slivers;
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
    required List<CustomerOrder> dueCustomerOrders,
    required List<Product> lowStockProducts,
    required bool canManageInventory,
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
            section: canReviewAbsence
                ? _InboxSection.todo
                : _InboxSection.inProgress,
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
          section:
              canManageShifts ? _InboxSection.todo : _InboxSection.inProgress,
          icon: Icons.swap_horiz,
          title: canManageShifts
              ? 'Tausch-Anfrage · ${shift.employeeName}'
              : 'Tausch in Bearbeitung',
          subtitle:
              '${shift.title} · ${shiftFmt.format(shift.startTime)} - ${DateFormat('HH:mm', 'de_DE').format(shift.endTime)}',
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
                section: _InboxSection.inProgress,
                icon: Icons.schedule_outlined,
                title: 'Kommende Schicht · ${shift.title}',
                subtitle:
                    '${shiftFmt.format(shift.startTime)} - ${DateFormat('HH:mm', 'de_DE').format(shift.endTime)}'
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
            section: _InboxSection.history,
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

    // Schichttausch: neue Tauschanfragen (eigene Collection). Pro Anfrage je
    // nach Rolle/Status ein Inbox-Eintrag (Kollege annehmen/ablehnen, Chef
    // bestätigen/ablehnen, Antragsteller zurückziehen, Ergebnis als Info).
    for (final request in schedule.swapRequests) {
      final item = _swapRequestInboxItem(
        context,
        request,
        schedule: schedule,
        ownUserId: ownUserId,
        canManageShifts: canManageShifts,
        colorScheme: colorScheme,
      );
      if (item != null) {
        items.add(item);
      }
    }
    // Offene Schicht-Gutschriften (einseitiger Tausch).
    for (final credit in schedule.swapCredits.where((c) => c.isOpen)) {
      items.add(
        _swapCreditInboxItem(
          context,
          credit,
          schedule: schedule,
          ownUserId: ownUserId,
          canManageShifts: canManageShifts,
          colorScheme: colorScheme,
        ),
      );
    }

    // Kundenbestellungen, die bald abgeholt werden, aber noch nicht vorbereitet
    // sind: als Warnung (Warnfarbe) ins Benachrichtigungs-Center.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final warningColor = Theme.of(context).appColors.warning;
    for (final order in dueCustomerOrders) {
      final pickup = order.pickupDate;
      final overdue = pickup != null && pickup.isBefore(today);
      final positions = order.items.map((item) => item.name).join(', ');
      items.add(
        _InboxItem(
          kind: _InboxItemKind.update,
          section: (canManageInventory && order.id != null)
              ? _InboxSection.todo
              : _InboxSection.inProgress,
          icon: Icons.shopping_bag_outlined,
          title: 'Kundenbestellung nicht vorbereitet',
          subtitle: '${order.customerName}'
              '${pickup != null ? ' · Abholung ${dateFmt.format(pickup)}' : ''}'
              '${positions.isNotEmpty ? '\n$positions' : ''}',
          time: pickup ?? now,
          color: warningColor,
          badge: overdue ? 'Ueberfaellig' : 'Bald faellig',
          actions: [
            if (canManageInventory && order.id != null)
              _InboxAction(
                label: 'Als vorbereitet markieren',
                primary: true,
                successMessage: 'Bestellung als vorbereitet markiert',
                onPressed: (context) async {
                  await context
                      .read<InventoryProvider>()
                      .markCustomerOrderPrepared(order);
                  return true;
                },
              ),
          ],
        ),
      );
    }

    // Artikel unter Meldebestand: als eine gebuendelte Nachbestell-Warnung.
    if (lowStockProducts.isNotEmpty) {
      final names = lowStockProducts.take(4).map((p) => p.name).join(', ');
      final more = lowStockProducts.length > 4 ? ' …' : '';
      items.add(
        _InboxItem(
          kind: _InboxItemKind.update,
          section: _InboxSection.history,
          icon: Icons.inventory_2_outlined,
          title: '${lowStockProducts.length} Artikel nachbestellen',
          subtitle: '$names$more',
          time: now,
          color: warningColor,
          badge: 'Nachbestellen',
        ),
      );
    }

    return items;
  }

  /// Baut den Inbox-Eintrag für eine Tauschanfrage – rollen- und
  /// statusabhängig. `null`, wenn der aktuelle Nutzer diese Anfrage nicht
  /// (mehr) sehen soll (z.B. abgeschlossene Fremd-Anfragen für einen Manager).
  _InboxItem? _swapRequestInboxItem(
    BuildContext context,
    ShiftSwapRequest request, {
    required ScheduleProvider schedule,
    required String ownUserId,
    required bool canManageShifts,
    required ColorScheme colorScheme,
  }) {
    final id = request.id;
    if (id == null) {
      return null;
    }
    final swapFmt = DateFormat('EEE, dd.MM. HH:mm', 'de_DE');
    final isTarget = request.targetUid == ownUserId;
    final isRequester = request.requesterUid == ownUserId;
    final time = request.updatedAt ?? request.createdAt ?? request.requesterShiftStart;

    final lines = <String>[
      'Abgegeben: ${request.requesterShiftLabel ?? swapFmt.format(request.requesterShiftStart)}',
      if (request.isGiveAway)
        'Gegenleistung: keine (Gutschrift nächsten Monat)'
      else
        'Gewünscht: ${request.targetShiftLabel ?? (request.targetShiftStart != null ? swapFmt.format(request.targetShiftStart!) : '—')}',
      if (request.note != null && request.note!.trim().isNotEmpty)
        'Notiz: ${request.note!.trim()}',
    ];
    final subtitle = lines.join('\n');

    // 1) Kollege: an mich gerichtet und offen -> annehmen/ablehnen.
    if (isTarget && request.status == SwapStatus.pending) {
      return _InboxItem(
        kind: _InboxItemKind.swap,
        section: _InboxSection.todo,
        icon: Icons.swap_horiz,
        title: 'Tauschanfrage von ${request.requesterName}',
        subtitle: subtitle,
        time: time,
        color: colorScheme.primary,
        badge: request.kind.label,
        actions: [
          _InboxAction(
            label: 'Ablehnen',
            successMessage: 'Tauschanfrage abgelehnt',
            onPressed: (context) async {
              await schedule.respondToShiftSwapRequest(
                requestId: id,
                accept: false,
              );
              return true;
            },
          ),
          _InboxAction(
            label: 'Annehmen',
            primary: true,
            successMessage: 'Tauschanfrage angenommen – wartet auf Freigabe',
            onPressed: (context) async {
              await schedule.respondToShiftSwapRequest(
                requestId: id,
                accept: true,
              );
              return true;
            },
          ),
        ],
      );
    }

    // 2) Antragsteller: noch nicht entschieden -> Status + zurückziehen.
    if (isRequester &&
        (request.status == SwapStatus.pending ||
            request.status == SwapStatus.acceptedByColleague)) {
      return _InboxItem(
        kind: _InboxItemKind.swap,
        section: _InboxSection.inProgress,
        icon: Icons.swap_horiz,
        title: 'Deine Tauschanfrage an ${request.targetName}',
        subtitle: subtitle,
        time: time,
        color: colorScheme.primary,
        badge: request.status.label,
        actions: [
          _InboxAction(
            label: 'Zurückziehen',
            successMessage: 'Tauschanfrage zurückgezogen',
            onPressed: (context) async {
              await schedule.cancelShiftSwapRequest(id);
              return true;
            },
          ),
        ],
      );
    }

    // 3) Chef: vom Kollegen angenommen -> bestätigen/ablehnen.
    if (canManageShifts && request.status == SwapStatus.acceptedByColleague) {
      final arrow = request.isGiveAway ? '→' : '↔';
      return _InboxItem(
        kind: _InboxItemKind.swap,
        section: _InboxSection.todo,
        icon: Icons.swap_horiz,
        title:
            'Tausch bestätigen · ${request.requesterName} $arrow ${request.targetName}',
        subtitle: subtitle,
        time: time,
        color: colorScheme.primary,
        badge: 'Zu bestätigen',
        actions: [
          _InboxAction(
            label: 'Ablehnen',
            successMessage: 'Schichttausch abgelehnt',
            onPressed: (context) async {
              await schedule.rejectShiftSwapRequest(id);
              return true;
            },
          ),
          _InboxAction(
            label: 'Übernehmen',
            primary: true,
            successMessage: 'Schichttausch durchgeführt',
            onPressed: (context) async {
              Future<void> doConfirm(bool override) =>
                  schedule.confirmShiftSwapRequest(
                    requestId: id,
                    overrideCompliance: override,
                  );
              final issues = await schedule.previewSwapCompliance(id);
              if (issues.isNotEmpty) {
                if (!context.mounted) {
                  return false;
                }
                final proceed = await _showSwapComplianceDialog(context, issues);
                if (proceed != true) {
                  return false;
                }
                await doConfirm(true);
                return true;
              }
              try {
                await doConfirm(false);
              } on ShiftConflictException catch (conflict) {
                if (!context.mounted) {
                  return false;
                }
                final proceed = await _showSwapComplianceDialog(
                  context,
                  conflict.issues,
                );
                if (proceed != true) {
                  return false;
                }
                await doConfirm(true);
              }
              return true;
            },
          ),
        ],
      );
    }

    // 4) Chef: offen (wartet auf Kollegen) -> nur Information (Chef ist im Bilde).
    if (canManageShifts &&
        !isTarget &&
        !isRequester &&
        request.status == SwapStatus.pending) {
      return _InboxItem(
        kind: _InboxItemKind.swap,
        section: _InboxSection.inProgress,
        icon: Icons.swap_horiz,
        title:
            'Tauschanfrage offen · ${request.requesterName} → ${request.targetName}',
        subtitle: subtitle,
        time: time,
        color: colorScheme.secondary,
        badge: 'Wartet auf Kollegen',
      );
    }

    // 5) Abgeschlossen: Ergebnis nur für Beteiligte als Info anzeigen.
    if (request.status.isClosed && (isRequester || isTarget)) {
      final isPositive = request.status == SwapStatus.confirmed;
      return _InboxItem(
        kind: _InboxItemKind.swap,
        section: _InboxSection.history,
        icon: isPositive ? Icons.check_circle_outline : Icons.swap_horiz,
        title: 'Schichttausch ${request.status.label.toLowerCase()}',
        subtitle: subtitle,
        time: time,
        color: isPositive ? colorScheme.primary : colorScheme.outline,
        badge: request.status.label,
      );
    }

    return null;
  }

  _InboxItem _swapCreditInboxItem(
    BuildContext context,
    SwapCredit credit, {
    required ScheduleProvider schedule,
    required String ownUserId,
    required bool canManageShifts,
    required ColorScheme colorScheme,
  }) {
    final id = credit.id;
    final owedToMe = credit.creditorUid == ownUserId;
    final iOwe = credit.debtorUid == ownUserId;
    final dateFmt = DateFormat('EEE, dd.MM.', 'de_DE');
    final title = owedToMe
        ? '${credit.debtorName} schuldet dir eine Schicht'
        : iOwe
            ? 'Du schuldest ${credit.creditorName} eine Schicht'
            : 'Gutschrift: ${credit.debtorName} → ${credit.creditorName}';
    final canSettle = (canManageShifts || owedToMe || iOwe) && id != null;
    return _InboxItem(
      kind: _InboxItemKind.swap,
      // Gutschrift hat zwar einen primären Button („Eingelöst"), aber keine
      // Frist → bewusst inProgress statt todo (dokumentierter Sonderfall).
      section: _InboxSection.inProgress,
      icon: Icons.account_balance_wallet_outlined,
      title: title,
      subtitle:
          'Aus Übernahme: ${credit.originShiftLabel ?? dateFmt.format(credit.originShiftStart)}',
      time: credit.createdAt ?? credit.originShiftStart,
      color: colorScheme.tertiary,
      badge: 'Gutschrift offen',
      actions: canSettle
          ? [
              if (canManageShifts)
                _InboxAction(
                  label: 'Stornieren',
                  successMessage: 'Gutschrift storniert',
                  onPressed: (context) async {
                    await schedule.cancelSwapCredit(id);
                    return true;
                  },
                ),
              _InboxAction(
                label: 'Eingelöst',
                primary: true,
                successMessage: 'Gutschrift eingelöst',
                onPressed: (context) async {
                  await schedule.settleSwapCredit(id);
                  return true;
                },
              ),
            ]
          : const [],
    );
  }

  Future<bool?> _showSwapComplianceDialog(
    BuildContext context,
    List<ShiftConflictIssue> issues,
  ) {
    final fmt = DateFormat('dd.MM. HH:mm', 'de_DE');
    final messages = <String>[];
    for (final issue in issues) {
      for (final violation in issue.violations) {
        messages.add('• ${violation.message}');
      }
      for (final conflict in issue.conflictingShifts) {
        messages.add('• Überschneidung mit ${conflict.title} '
            '(${fmt.format(conflict.startTime)})');
      }
      for (final absence in issue.blockingAbsences) {
        messages.add('• Abwesenheit: ${absence.type.label}');
      }
    }
    if (messages.isEmpty) {
      messages.add('• Es wurden mögliche Regelverstöße erkannt.');
    }
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Regelverstoß beim Übernehmen'),
        content: SingleChildScrollView(
          child: Text(
            'Der Tausch verletzt beim Empfänger folgende Regeln:\n\n'
            '${messages.join('\n')}\n\n'
            'Trotzdem übernehmen?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Trotzdem übernehmen'),
          ),
        ],
      ),
    );
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

/// Kompakte, dezent in der Akzentfarbe getönte Status-Pille in der Titelzeile.
class _BadgePill extends StatelessWidget {
  const _BadgePill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

/// Überschrift eines Bereichs mit Anzahl-Pille. [emphasize] hebt „Zu erledigen"
/// in der Warnfarbe hervor (Dringlichkeit), sonst neutral.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    this.emphasize = false,
  });

  final String title;
  final int count;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final pillBg = emphasize
        ? appColors.warningContainer
        : theme.colorScheme.surfaceContainerHighest;
    final pillFg = emphasize
        ? appColors.onWarningContainer
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: pillBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: pillFg, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

/// Einklappbarer Sekundär-Bereich. Der Aufklapp-Zustand lebt im Screen-State
/// (sonst klappte er bei jedem Provider-Notify zu); der Header zeigt immer die
/// Live-Anzahl, damit nichts „verschwunden" wirkt.
class _CollapsibleSection extends StatelessWidget {
  const _CollapsibleSection({
    required this.title,
    required this.count,
    required this.expanded,
    required this.onToggle,
    required this.items,
  });

  final String title;
  final int count;
  final bool expanded;
  final ValueChanged<bool> onToggle;
  final List<_InboxItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Theme(
        // Flaches Design: keine Trennlinien der ExpansionTile.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('inbox-section-$title'),
          initiallyExpanded: expanded,
          onExpansionChanged: onToggle,
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _InboxItemCard(item: item, dense: true),
              ),
          ],
        ),
      ),
    );
  }
}

class _InboxItemCard extends StatefulWidget {
  const _InboxItemCard({required this.item, this.dense = false});

  final _InboxItem item;

  /// Kompakte Variante für die eingeklappten Sekundär-Bereiche
  /// („Läuft & wartet" / „Verlauf & Hinweise"): ohne Akzentbalken,
  /// kleinerer Avatar, kürzerer Untertitel.
  final bool dense;

  @override
  State<_InboxItemCard> createState() => _InboxItemCardState();
}

class _InboxItemCardState extends State<_InboxItemCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final dense = widget.dense;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(dense ? 14 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Akzentbalken nur in der vollen Variante (Bereich „Zu erledigen").
            if (!dense) ...[
              Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: dense ? 16 : 20,
                  backgroundColor: item.color.withValues(alpha: 0.14),
                  child: Icon(item.icon,
                      color: item.color, size: dense ? 17 : 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Titelzeile mit Status-Badge rechts – statt einer
                      // zweiten Pillen-Spalte; ein klarer Lesefluss.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (item.badge != null) ...[
                            const SizedBox(width: 8),
                            _BadgePill(text: item.badge!, color: item.color),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTime(item.time),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.subtitle,
                        maxLines: dense ? 2 : 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (item.actions.isNotEmpty) ...[
              SizedBox(height: dense ? 10 : 14),
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
      return DateFormat('dd.MM.', 'de_DE').format(time);
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
    return DateFormat('dd.MM.', 'de_DE').format(time);
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
  late bool _halfDay;
  HalfDayPeriod? _halfDayPeriod;
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _hoursController = TextEditingController();
  late Set<String> _vertreterIds;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = widget.initialRequest?.type ?? widget.defaultType;
    _halfDay = widget.initialRequest?.halfDay ?? false;
    _halfDayPeriod =
        widget.initialRequest?.halfDayPeriod ?? HalfDayPeriod.vormittags;
    final initialHours = widget.initialRequest?.hours;
    _hoursController.text =
        initialHours == null ? '' : _formatHours(initialHours);
    _vertreterIds = {...?widget.initialRequest?.vertreterUserIds};
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
    _hoursController.dispose();
    super.dispose();
  }

  /// Formatiert Stunden mit deutschem Dezimalkomma (4,0 → „4"; 4,5 → „4,5").
  static String _formatHours(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    final s = value
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
    return s.replaceAll('.', ',');
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
            DropdownButtonFormField<AbsenceType>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Art',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: [
                for (final t in AbsenceType.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: isApprovedVacationEdit
                  ? null
                  : (value) => setState(() {
                        _type = value ?? _type;
                        if (!regelFor(_type).halbtagFaehig) _halfDay = false;
                      }),
            ),
            if (regelFor(_type).halbtagFaehig) ...[
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Halbtägig'),
                value: _halfDay,
                onChanged: isApprovedVacationEdit
                    ? null
                    : (v) => setState(() => _halfDay = v),
              ),
              if (_halfDay)
                SegmentedButton<HalfDayPeriod>(
                  segments: const [
                    ButtonSegment(
                      value: HalfDayPeriod.vormittags,
                      label: Text('Vormittags'),
                    ),
                    ButtonSegment(
                      value: HalfDayPeriod.nachmittags,
                      label: Text('Nachmittags'),
                    ),
                  ],
                  selected: {_halfDayPeriod ?? HalfDayPeriod.vormittags},
                  onSelectionChanged: (s) =>
                      setState(() => _halfDayPeriod = s.first),
                ),
            ],
            if (_type == AbsenceType.sickness) ...[
              const SizedBox(height: 8),
              Text(
                'Lohnfortzahlung 6 Wochen (EFZG); danach Krankengeld der Kasse.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
            if (_type == AbsenceType.timeOff) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _hoursController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Stunden (Zeitausgleich)',
                  hintText: 'z. B. 4 oder 4,5',
                  prefixIcon: Icon(Icons.timelapse_outlined),
                  suffixText: 'h',
                ),
              ),
            ],
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
            _buildResturlaubVorschau(context),
            _buildVertreterSelector(context),
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
                        child: CircularProgressIndicator.adaptive(strokeWidth: 2),
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

  static String _tage(double d) {
    final s = (d == d.roundToDouble())
        ? d.toStringAsFixed(0)
        : d.toStringAsFixed(1).replaceAll('.', ',');
    return '$s Tage';
  }

  /// Liest einen Provider tolerant – die Live-Vorschau/Vertreter sind optionale
  /// Verfeinerungen; fehlt der Provider (z. B. isolierter Widget-Test), wird die
  /// jeweilige Sektion einfach ausgeblendet statt zu crashen.
  static T? _maybeRead<T>(BuildContext context) {
    try {
      return Provider.of<T>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// Live-Resturlaub-Vorschau (§6.6). Nur bei Urlaub und nur, wenn die
  /// (admin-only) Urlaubsdaten geladen sind – also für Admins bzgl. des eigenen
  /// Kontos. Die Mitarbeiter-Selbstansicht folgt mit der getMySelfService-
  /// Projektion (M-Z2/§4.0); ohne sie keine irreführenden Scheinzahlen.
  Widget _buildResturlaubVorschau(BuildContext context) {
    if (_type != AbsenceType.vacation) return const SizedBox.shrink();
    final profile = _maybeRead<AuthProvider>(context)?.profile;
    if (profile == null || !profile.isAdmin) return const SizedBox.shrink();
    final personal = _maybeRead<PersonalProvider>(context);
    if (personal == null) return const SizedBox.shrink();
    final uid = widget.initialRequest?.userId ?? profile.uid;
    final jahr = _startDate.year;
    final report = personal.urlaubsReportFor(uid, jahr);
    final sollzeit = personal.activeSollzeitFor(uid, _startDate);
    final bundesland =
        personal.federalStateForUserPrimarySite(uid) ?? 'Schleswig-Holstein';
    final tage = genommeneUrlaubstage(
      AbsenceRequest(
        orgId: '',
        userId: uid,
        employeeName: '',
        startDate: _startDate,
        endDate: _endDate,
        type: AbsenceType.vacation,
        halfDay: _halfDay,
      ),
      jahr: jahr,
      sollzeit: sollzeit,
      bundesland: bundesland,
    );
    // Beim Bearbeiten eines bereits gezählten Antrags (offen/genehmigt) ist
    // dessen Dauer schon im Report enthalten → nicht doppelt abziehen.
    final bereitsGezaehlt = widget.initialRequest != null &&
        widget.initialRequest!.type == AbsenceType.vacation &&
        widget.initialRequest!.status != AbsenceStatus.rejected;
    final neu = bereitsGezaehlt ? report.resturlaub : report.resturlaub - tage;
    final theme = Theme.of(context);
    final tone =
        neu < 0 ? theme.appColors.warning : theme.appColors.info;
    final text = bereitsGezaehlt
        ? 'Resturlaub $jahr: ${_tage(report.resturlaub)} (dieser Antrag bereits berücksichtigt).'
        : 'Resturlaub $jahr: ${_tage(report.resturlaub)} → nach Antrag '
            '${_tage(neu)} (${_tage(tage)} angefragt).';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.beach_access_outlined, size: 18, color: tone),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: tone, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Vertreter-Auswahl (§6.6): genehmigende Vertretung aus den Org-Mitgliedern,
  /// Self-Exclusion. Versteckt, solange keine Mitglieder geladen sind.
  Widget _buildVertreterSelector(BuildContext context) {
    final selfUid = _maybeRead<AuthProvider>(context)?.profile?.uid;
    final schedule = _maybeRead<ScheduleProvider>(context);
    if (schedule == null) return const SizedBox.shrink();
    final members =
        schedule.orgMembers.where((m) => m.uid != selfUid).toList();
    if (members.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vertretung (optional)', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final m in members)
                FilterChip(
                  label: Text(
                      m.displayName.isEmpty ? m.email : m.displayName),
                  selected: _vertreterIds.contains(m.uid),
                  onSelected: _saving
                      ? null
                      : (sel) => setState(() {
                            if (sel) {
                              _vertreterIds.add(m.uid);
                            } else {
                              _vertreterIds.remove(m.uid);
                            }
                          }),
                ),
            ],
          ),
        ],
      ),
    );
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
    final parsedHours = _type == AbsenceType.timeOff
        ? double.tryParse(_hoursController.text.trim().replaceAll(',', '.'))
        : null;
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
              halfDay: _halfDay,
              halfDayPeriod: _halfDay ? _halfDayPeriod : null,
              hours: parsedHours,
              vertreterUserIds: _vertreterIds.toList(),
              eauAttached: widget.initialRequest?.eauAttached ?? false,
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
