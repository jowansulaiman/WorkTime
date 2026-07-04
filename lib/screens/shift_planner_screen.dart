import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:collection/collection.dart';

import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/compliance_violation.dart';
import '../core/hex_color.dart';
import '../core/shift_auto_assigner.dart';
import '../models/shift.dart';
import '../models/shift_swap_request.dart';
import '../models/shift_template.dart';
import '../models/qualification_definition.dart';
import '../models/site_definition.dart';
import '../models/team_definition.dart';
import '../providers/auth_provider.dart';
import '../providers/feature_flag_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/team_provider.dart';
import '../routing/shell_tab.dart';
import '../services/compliance_rejected_exception.dart';
import '../services/export_service.dart';
import '../theme/app_theme.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/responsive_layout.dart';
import 'notification_screen.dart';
import 'shift_planner/planner_logic.dart';

part 'shift_planner/planner_cells.dart';
part 'shift_planner/shift_editor_sheet.dart';

enum ShiftPlanExportFormat { pdf, csv, ical }

enum _PlannerLayoutMode { employee, location }

enum _PlannerAbsenceFilter { all, vacation, sickness, unavailable }

typedef _ShiftEditorLauncher = Future<void> Function({
  Shift? shift,
  DateTime? initialDate,
  Set<String>? initialUserIds,
  bool initialUnassigned,
  String? initialLocation,
  String? initialTeamId,
  String? initialTeamName,
  String? initialTitle,
});

typedef ShiftPlanExportCallback = Future<void> Function(
  ShiftPlanExportFormat format,
  List<Shift> shifts,
);

int _plannerAbsenceStatusPriority(AbsenceStatus status) => switch (status) {
      AbsenceStatus.pending => 0,
      AbsenceStatus.approved => 1,
      AbsenceStatus.rejected => 2,
    };

int _plannerAbsenceRequestSort(AbsenceRequest a, AbsenceRequest b) {
  final byStatus = _plannerAbsenceStatusPriority(
    a.status,
  ).compareTo(_plannerAbsenceStatusPriority(b.status));
  if (byStatus != 0) {
    return byStatus;
  }
  final byStart = a.startDate.compareTo(b.startDate);
  if (byStart != 0) {
    return byStart;
  }
  final byEnd = a.endDate.compareTo(b.endDate);
  if (byEnd != 0) {
    return byEnd;
  }
  final byEmployee = a.employeeName.compareTo(b.employeeName);
  if (byEmployee != 0) {
    return byEmployee;
  }
  return a.type.label.compareTo(b.type.label);
}

bool _canManageApprovedVacationRequest({
  required AppUserProfile? currentUser,
  required AbsenceRequest request,
  required Iterable<AppUserProfile> members,
}) {
  if (currentUser == null ||
      !currentUser.canManageShifts ||
      request.id == null ||
      request.type != AbsenceType.vacation ||
      request.status != AbsenceStatus.approved) {
    return false;
  }
  final requester =
      members.firstWhereOrNull((member) => member.uid == request.userId) ??
          (currentUser.uid == request.userId ? currentUser : null);
  if (requester == null) {
    return currentUser.isAdmin;
  }
  return currentUser.canManageApprovedVacationFor(requester);
}

class ShiftPlannerScreen extends StatelessWidget {
  const ShiftPlannerScreen({
    super.key,
    this.canNavigateBack = false,
    this.onNavigateBack,
    this.onShiftPlanExport,
  });

  final bool canNavigateBack;
  final VoidCallback? onNavigateBack;
  final ShiftPlanExportCallback? onShiftPlanExport;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final schedule = context.watch<ScheduleProvider>();
    final team = context.watch<TeamProvider>();
    final currentUser = auth.profile;
    final members = team.members.where((member) => member.isActive).toList();
    final teams = team.teams;
    final isAdmin = currentUser?.canManageShifts ?? false;
    final isTeamLead = currentUser?.isTeamLead ?? false;
    if (!(currentUser?.canViewSchedule ?? false)) {
      return const SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Der Schichtplan ist fuer dieses Profil deaktiviert.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final rangeLabel = _rangeLabel(schedule.visibleDate, schedule.viewMode);
    final selectedTeam =
        teams.where((entry) => entry.id == schedule.selectedTeamId).firstOrNull;
    final visibleShifts = schedule.shifts;
    final visibleAbsenceRequests = selectedTeam == null
        ? schedule.absenceRequests
        : schedule.absenceRequests.where((request) {
            return selectedTeam.memberIds.contains(request.userId);
          }).toList(growable: false);
    final plannerAbsenceRequests = visibleAbsenceRequests
        .where((request) => request.status != AbsenceStatus.rejected)
        .toList(growable: false)
      ..sort(_plannerAbsenceRequestSort);
    final selectedMemberLabel = schedule.selectedUserId == null
        ? null
        : members
            .where((member) => member.uid == schedule.selectedUserId)
            .map((member) => member.displayName)
            .firstOrNull;
    final employeeExportLabel =
        isAdmin ? selectedMemberLabel : currentUser?.displayName;

    if (isAdmin) {
      return _AdminShiftPlannerBoard(
        members: members,
        teams: teams,
        visibleShifts: visibleShifts,
        visibleAbsenceRequests: plannerAbsenceRequests,
        rangeLabel: rangeLabel,
        employeeExportLabel: employeeExportLabel,
        selectedTeamName: selectedTeam?.name,
        canNavigateBack: canNavigateBack,
        onNavigateBack: onNavigateBack,
        onCopyWeek: () => _copyWeek(context),
        onAutoPlan: () => _autoPlan(context),
        onCopyShiftToDays: (shift) => _copyShiftToDays(context, shift, members),
        onDropCopyShift: (shift, targetDay, reassignUserId, reassignName) =>
            _dropCopyShift(
          context,
          shift,
          targetDay,
          reassignUserId,
          reassignName,
        ),
        onExport: (format, shifts) => _handleShiftPlanExport(
          context,
          format: format,
          shifts: shifts,
          visibleDate: schedule.visibleDate,
          viewMode: schedule.viewMode,
          rangeLabel: rangeLabel,
          employeeLabel: employeeExportLabel,
          teamLabel: selectedTeam?.name,
        ),
        onOpenShiftEditor: ({
          Shift? shift,
          DateTime? initialDate,
          Set<String>? initialUserIds,
          bool initialUnassigned = false,
          String? initialLocation,
          String? initialTeamId,
          String? initialTeamName,
          String? initialTitle,
        }) =>
            _openShiftEditor(
          context,
          members: members,
          teams: teams,
          shift: shift,
          initialDate: initialDate,
          initialUserIds: initialUserIds,
          initialUnassigned: initialUnassigned,
          initialLocation: initialLocation,
          initialTeamId: initialTeamId,
          initialTeamName: initialTeamName,
          initialTitle: initialTitle,
        ),
      );
    }

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ShellBreadcrumb(
                breadcrumbs: const [
                  BreadcrumbItem(label: 'Plan'),
                  BreadcrumbItem(label: 'Meine Schichten'),
                ],
                onBack: canNavigateBack ? onNavigateBack : null,
              ),
              const SizedBox(height: 10),
              Text(
                isAdmin ? 'Schichtplaner' : 'Meine Schichten',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                isTeamLead
                    ? 'Schichten koordinieren, Konflikte pruefen und eigene Abwesenheiten an den Admin senden.'
                    : isAdmin
                        ? 'Schichten anlegen, filtern, Konflikte pruefen und Abwesenheiten freigeben.'
                        : 'Eigene Schichten einsehen und Abwesenheiten melden.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SegmentedButton<ScheduleViewMode>(
                              segments: const [
                                ButtonSegment(
                                  value: ScheduleViewMode.day,
                                  label: Text('Tag'),
                                ),
                                ButtonSegment(
                                  value: ScheduleViewMode.week,
                                  label: Text('Woche'),
                                ),
                                ButtonSegment(
                                  value: ScheduleViewMode.month,
                                  label: Text('Monat'),
                                ),
                              ],
                              selected: {schedule.viewMode},
                              onSelectionChanged: (selection) {
                                schedule.setViewMode(selection.first);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => schedule.setVisibleDate(
                              _shiftVisibleDate(
                                schedule.visibleDate,
                                schedule.viewMode,
                                -1,
                              ),
                            ),
                            icon: const Icon(Icons.chevron_left),
                            label: const Text('Zurueck'),
                          ),
                          Text(
                            rangeLabel,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => schedule.setVisibleDate(
                              _shiftVisibleDate(
                                schedule.visibleDate,
                                schedule.viewMode,
                                1,
                              ),
                            ),
                            icon: const Icon(Icons.chevron_right),
                            label: const Text('Weiter'),
                          ),
                          if (isAdmin)
                            SizedBox(
                              width: 280,
                              child: DropdownButtonFormField<String>(
                                initialValue: schedule.selectedUserId,
                                decoration: const InputDecoration(
                                  labelText: 'Mitarbeiter-Filter',
                                  prefixIcon: Icon(Icons.groups_outlined),
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('Alle Mitarbeiter'),
                                  ),
                                  for (final member in members)
                                    DropdownMenuItem(
                                      value: member.uid,
                                      child: Text(member.displayName),
                                    ),
                                ],
                                onChanged: schedule.setSelectedUserId,
                              ),
                            ),
                          if (isAdmin)
                            SizedBox(
                              width: 220,
                              child: DropdownButtonFormField<String?>(
                                initialValue: schedule.selectedTeamId,
                                decoration: const InputDecoration(
                                  labelText: 'Team-Filter',
                                  prefixIcon: Icon(Icons.groups_2_outlined),
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Alle Teams'),
                                  ),
                                  for (final team in teams)
                                    DropdownMenuItem<String?>(
                                      value: team.id,
                                      child: Text(team.name),
                                    ),
                                ],
                                onChanged: (value) {
                                  final team = teams
                                      .where((entry) => entry.id == value)
                                      .firstOrNull;
                                  schedule.setTeamFilter(
                                    value,
                                    teamName: team?.name,
                                  );
                                },
                              ),
                            ),
                          if (isAdmin)
                            SizedBox(
                              width: 200,
                              child: DropdownButtonFormField<ShiftStatus?>(
                                initialValue: schedule.statusFilter,
                                decoration: const InputDecoration(
                                  labelText: 'Status-Filter',
                                  prefixIcon: Icon(Icons.filter_list),
                                ),
                                items: [
                                  const DropdownMenuItem<ShiftStatus?>(
                                    value: null,
                                    child: Text('Alle Status'),
                                  ),
                                  for (final status in ShiftStatus.values)
                                    DropdownMenuItem<ShiftStatus?>(
                                      value: status,
                                      child: Text(status.label),
                                    ),
                                ],
                                onChanged: (value) =>
                                    schedule.setStatusFilter(value),
                              ),
                            ),
                          FilledButton.icon(
                            onPressed: isAdmin
                                ? () => _openShiftEditor(
                                      context,
                                      members: members,
                                      teams: teams,
                                    )
                                : () => _openAbsenceEditor(context),
                            icon: Icon(
                              isAdmin
                                  ? Icons.add_task
                                  : Icons.event_busy_outlined,
                            ),
                            label: Text(
                              isAdmin
                                  ? 'Schicht anlegen'
                                  : 'Abwesenheit melden',
                            ),
                          ),
                          if (isTeamLead)
                            OutlinedButton.icon(
                              onPressed: () => _openAbsenceEditor(context),
                              icon: const Icon(Icons.event_busy_outlined),
                              label: const Text('Abwesenheit melden'),
                            ),
                          PopupMenuButton<ShiftPlanExportFormat>(
                            enabled: visibleShifts.isNotEmpty,
                            tooltip: 'Schichtplan exportieren',
                            onSelected: (format) => _handleShiftPlanExport(
                              context,
                              format: format,
                              shifts: visibleShifts,
                              visibleDate: schedule.visibleDate,
                              viewMode: schedule.viewMode,
                              rangeLabel: rangeLabel,
                              employeeLabel: employeeExportLabel,
                              teamLabel: selectedTeam?.name,
                            ),
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: ShiftPlanExportFormat.pdf,
                                child: Text('Als PDF exportieren'),
                              ),
                              PopupMenuItem(
                                value: ShiftPlanExportFormat.csv,
                                child: Text('Als CSV exportieren'),
                              ),
                              PopupMenuItem(
                                value: ShiftPlanExportFormat.ical,
                                child: Text('Als Kalender (.ics)'),
                              ),
                            ],
                            icon: const Icon(Icons.download_outlined),
                          ),
                          if (isAdmin)
                            OutlinedButton.icon(
                              onPressed: () => _copyWeek(context),
                              icon: const Icon(Icons.content_copy),
                              label: const Text('Woche kopieren'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (schedule.viewMode == ScheduleViewMode.month) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: TableCalendar(
                      locale: 'de_DE',
                      firstDay: DateTime(2020),
                      lastDay: DateTime(2035),
                      focusedDay: schedule.visibleDate,
                      calendarFormat: CalendarFormat.month,
                      headerStyle: const HeaderStyle(
                        titleCentered: true,
                        formatButtonVisible: false,
                      ),
                      selectedDayPredicate: (day) =>
                          isSameDay(day, schedule.visibleDate),
                      onDaySelected: (selectedDay, focusedDay) {
                        schedule.setVisibleDate(selectedDay);
                      },
                      calendarBuilders: CalendarBuilders(
                        markerBuilder: (context, day, events) {
                          final shiftCount = visibleShifts.where((shift) {
                            return shift.startTime.year == day.year &&
                                shift.startTime.month == day.month &&
                                shift.startTime.day == day.day;
                          }).length;
                          final absenceCount =
                              visibleAbsenceRequests.where((request) {
                            return request.overlaps(
                              DateTime(day.year, day.month, day.day),
                              DateTime(
                                  day.year, day.month, day.day, 23, 59, 59),
                            );
                          }).length;
                          if (shiftCount == 0 && absenceCount == 0) {
                            return null;
                          }
                          return Positioned(
                            bottom: 2,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (shiftCount > 0)
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                if (shiftCount > 0 && absenceCount > 0)
                                  const SizedBox(width: 3),
                                if (absenceCount > 0)
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .tertiary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Schichten',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 12),
                      if (visibleShifts.isEmpty)
                        const _PlannerEmptyState(
                          icon: Icons.view_timeline_outlined,
                          text: 'Keine Schichten im aktuellen Zeitfenster.',
                        )
                      else
                        Column(
                          children: [
                            for (final shift in visibleShifts)
                              _ShiftCard(
                                shift: shift,
                                isAdmin: isAdmin,
                                onEdit: () => _openShiftEditor(
                                  context,
                                  members: members,
                                  teams: teams,
                                  shift: shift,
                                ),
                                onDelete: () async {
                                  if (shift.id != null) {
                                    try {
                                      await context
                                          .read<ScheduleProvider>()
                                          .deleteShift(shift.id!);
                                    } catch (error) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text('Fehler: $error'),
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                      );
                                    }
                                  }
                                },
                                onDeleteSeries: shift.seriesId == null
                                    ? null
                                    : () async {
                                        try {
                                          await context
                                              .read<ScheduleProvider>()
                                              .deleteShiftSeries(
                                                  shift.seriesId!);
                                        } catch (error) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text('Fehler: $error'),
                                              backgroundColor: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                            ),
                                          );
                                        }
                                      },
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Abwesenheiten',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 12),
                      if (visibleAbsenceRequests.isEmpty)
                        const _PlannerEmptyState(
                          icon: Icons.event_busy_outlined,
                          text: 'Keine Abwesenheiten im aktuellen Zeitfenster.',
                        )
                      else
                        Column(
                          children: [
                            for (final request in visibleAbsenceRequests)
                              _AbsenceCard(
                                request: request,
                                canReviewRequest: isAdmin &&
                                    (!isTeamLead ||
                                        request.userId != currentUser?.uid),
                                canManageApprovedVacation:
                                    _canManageApprovedVacationRequest(
                                  currentUser: currentUser,
                                  request: request,
                                  members: members,
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyWeek(BuildContext context) async {
    final schedule = context.read<ScheduleProvider>();
    final sourceStart = schedule.visibleDate.subtract(
      Duration(days: schedule.visibleDate.weekday - 1),
    );
    final targetDate = await showDatePicker(
      context: context,
      initialDate: sourceStart.add(const Duration(days: 7)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('de', 'DE'),
    );
    if (targetDate == null || !context.mounted) return;
    final targetStart = targetDate.subtract(
      Duration(days: targetDate.weekday - 1),
    );
    try {
      await schedule.copyWeekShifts(
        sourceWeekStart: sourceStart,
        targetWeekStart: targetStart,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Woche erfolgreich kopiert')),
      );
    } on ShiftConflictException catch (error) {
      if (!context.mounted) return;
      await _showShiftConflictDialog(context, error.issues);
    } on ComplianceRejectedException catch (error) {
      if (!context.mounted) return;
      await _showComplianceRejectionDialog(context, error);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: ${_cleanErrorText(error)}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Automatische Schichtverteilung: generiert Schichten aus Öffnungszeiten +
  /// Bedarf (Phase A), besetzt sie (Phase B), zeigt eine Vorschau und speichert
  /// auf Bestätigung.
  Future<void> _autoPlan(BuildContext context) async {
    final schedule = context.read<ScheduleProvider>();
    final settings = context.read<FeatureFlagProvider>().orgSettings;
    final range =
        _currentScheduleRange(schedule.visibleDate, schedule.viewMode);

    final generated = schedule.generatePlannedShifts(
      rangeStart: range.start,
      rangeEnd: range.end,
      settings: settings,
    );
    final existingOpen = schedule.shifts
        .where((shift) =>
            shift.isUnassigned &&
            !shift.startTime.isBefore(range.start) &&
            shift.startTime.isBefore(range.end))
        .toList(growable: false);
    final openShifts = [...generated, ...existingOpen];

    if (openShifts.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nichts zu planen — keine Öffnungszeiten/Bedarf im Zeitraum oder '
            'bereits alles besetzt.',
          ),
        ),
      );
      return;
    }

    // Auto-Verteilung sammelt org-weit belegte Schichten + genehmigte
    // Abwesenheiten für den vollen Monat — kann spürbar dauern. Blockierenden
    // Spinner zeigen, damit der Nutzer den Fortschritt sieht.
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final result = await schedule
        .proposeAutoAssignment(
          openShifts: openShifts,
          month: range.start,
          settings: settings,
        )
        .whenComplete(navigator.pop);

    if (!context.mounted) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _AutoPlanPreviewSheet(
        generated: generated,
        existingOpen: existingOpen,
        result: result,
        enforceHourCapHard: settings.enforceHourCapHard,
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      await schedule.applyAutoPlan(
        generatedShifts: generated,
        existingOpenShifts: existingOpen,
        result: result,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${generated.length} Schichten geplant, '
            '${result.assignments.length} besetzt',
          ),
        ),
      );
    } on ShiftConflictException catch (error) {
      if (!context.mounted) return;
      await _showShiftConflictDialog(context, error.issues);
    } on ComplianceRejectedException catch (error) {
      if (!context.mounted) return;
      await _showComplianceRejectionDialog(context, error);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: ${_cleanErrorText(error)}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Kopiert eine bestehende Schicht auf andere Mitarbeiter und/oder Tage.
  /// Öffnet das [_CopyShiftSheet] (Mitarbeiter-Chips + Mehrtage-Picker) und
  /// nutzt [ScheduleProvider.copyShiftToAssignees].
  Future<void> _copyShiftToDays(
    BuildContext context,
    Shift shift,
    List<AppUserProfile> members,
  ) async {
    final schedule = context.read<ScheduleProvider>();
    final selection = await showModalBottomSheet<_CopyShiftSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => _CopyShiftSheet(
        source: shift,
        members: members,
      ),
    );
    if (selection == null ||
        selection.days.isEmpty ||
        selection.assigneeUids.isEmpty ||
        !context.mounted) {
      return;
    }
    final assignees = members
        .where((member) => selection.assigneeUids.contains(member.uid))
        .toList(growable: false);
    if (assignees.isEmpty) {
      return;
    }
    try {
      await schedule.copyShiftToAssignees(
        shift,
        selection.days.toList(),
        assignees,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Schicht kopiert')),
      );
    } on ShiftConflictException catch (error) {
      if (!context.mounted) return;
      await _showShiftConflictDialog(context, error.issues);
    } on ComplianceRejectedException catch (error) {
      if (!context.mounted) return;
      await _showComplianceRejectionDialog(context, error);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: ${_cleanErrorText(error)}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Drag & Drop: kopiert die gezogene Schicht direkt auf den Zieltag (ohne
  /// Picker), optional an die Ziel-Mitarbeiterzeile zugewiesen. Fehler werden
  /// über dieselben Dialoge wie beim Editor gemeldet.
  Future<void> _dropCopyShift(
    BuildContext context,
    Shift shift,
    DateTime targetDay,
    String? reassignUserId,
    String? reassignName,
  ) async {
    final schedule = context.read<ScheduleProvider>();
    try {
      await schedule.copyShiftToDay(
        shift,
        targetDay,
        reassignUserId: reassignUserId,
        reassignEmployeeName: reassignName,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Schicht kopiert')),
      );
    } on ShiftConflictException catch (error) {
      if (!context.mounted) return;
      await _showShiftConflictDialog(context, error.issues);
    } on ComplianceRejectedException catch (error) {
      if (!context.mounted) return;
      await _showComplianceRejectionDialog(context, error);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: ${_cleanErrorText(error)}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _handleShiftPlanExport(
    BuildContext context, {
    required ShiftPlanExportFormat format,
    required List<Shift> shifts,
    required DateTime visibleDate,
    required ScheduleViewMode viewMode,
    required String rangeLabel,
    String? employeeLabel,
    String? teamLabel,
  }) async {
    if (onShiftPlanExport != null) {
      await onShiftPlanExport!(format, shifts);
      return;
    }

    await _exportShiftPlan(
      context,
      format: format,
      shifts: shifts,
      visibleDate: visibleDate,
      viewMode: viewMode,
      rangeLabel: rangeLabel,
      employeeLabel: employeeLabel,
      teamLabel: teamLabel,
    );
  }

  Future<void> _exportShiftPlan(
    BuildContext context, {
    required ShiftPlanExportFormat format,
    required List<Shift> shifts,
    required DateTime visibleDate,
    required ScheduleViewMode viewMode,
    required String rangeLabel,
    String? employeeLabel,
    String? teamLabel,
  }) async {
    final range = _currentScheduleRange(visibleDate, viewMode);
    try {
      switch (format) {
        case ShiftPlanExportFormat.pdf:
          await ExportService.exportShiftPlanPdf(
            shifts: shifts,
            rangeStart: range.start,
            rangeEnd: range.end,
            rangeLabel: rangeLabel,
            employeeLabel: employeeLabel,
            teamLabel: teamLabel,
          );
        case ShiftPlanExportFormat.csv:
          await ExportService.exportShiftPlanCsv(
            shifts: shifts,
            rangeStart: range.start,
            rangeEnd: range.end,
            rangeLabel: rangeLabel,
            employeeLabel: employeeLabel,
            teamLabel: teamLabel,
          );
        case ShiftPlanExportFormat.ical:
          await ExportService.exportShiftPlanIcal(
            shifts: shifts,
            rangeStart: range.start,
            rangeEnd: range.end,
          );
      }

      if (!context.mounted) {
        return;
      }
      final label = switch (format) {
        ShiftPlanExportFormat.pdf => 'PDF',
        ShiftPlanExportFormat.csv => 'CSV',
        ShiftPlanExportFormat.ical => 'Kalender',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Schichtplan als $label exportiert')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export fehlgeschlagen: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _openShiftEditor(
    BuildContext context, {
    required List<AppUserProfile> members,
    required List<TeamDefinition> teams,
    Shift? shift,
    DateTime? initialDate,
    Set<String>? initialUserIds,
    bool initialUnassigned = false,
    String? initialLocation,
    String? initialTeamId,
    String? initialTeamName,
    String? initialTitle,
  }) async {
    final currentUser = context.read<AuthProvider>().profile;
    final scheduleProvider = context.read<ScheduleProvider>();
    if (currentUser == null) {
      return;
    }

    final result = await showModalBottomSheet<_ShiftEditorResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _ShiftEditorSheet(
          members: members,
          teams: teams,
          currentUser: currentUser,
          shift: shift,
          initialDate: initialDate,
          initialUserIds: initialUserIds,
          initialUnassigned: initialUnassigned,
          initialLocation: initialLocation,
          initialTeamId: initialTeamId,
          initialTeamName: initialTeamName,
          initialTitle: initialTitle,
        ),
      ),
    );

    if (result == null) {
      return;
    }

    try {
      await scheduleProvider.saveShifts(
        result.shifts,
        recurrencePattern: result.recurrencePattern,
        recurrenceEndDate: result.recurrenceEndDate,
        seriesId:
            result.groupAsSeries ? scheduleProvider.newSeriesId() : null,
      );
    } on ShiftConflictException catch (error) {
      if (!context.mounted) {
        return;
      }
      await _showShiftConflictDialog(context, error.issues);
    } on ComplianceRejectedException catch (error) {
      // Serverseitige Compliance-Ablehnung: strukturierte Verstoesse anzeigen
      // statt der nackten 'Bad state:'-Meldung (probleme #16).
      if (!context.mounted) {
        return;
      }
      await _showComplianceRejectionDialog(context, error);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_cleanErrorText(error)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Entfernt das englische 'Bad state: '-Praefix, das `StateError.toString()`
  /// voranstellt (probleme #16).
  String _cleanErrorText(Object error) =>
      error.toString().replaceFirst('Bad state: ', '');

  Future<void> _showComplianceRejectionDialog(
    BuildContext context,
    ComplianceRejectedException error,
  ) {
    final violations = error.violations;
    final colorScheme = Theme.of(context).colorScheme;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Regelverstoss'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: violations.isEmpty
                ? Text(_cleanErrorText(error))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final violation in violations)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                violation.severity ==
                                        ComplianceSeverity.blocking
                                    ? Icons.block_rounded
                                    : Icons.warning_amber_rounded,
                                size: 18,
                                color: violation.severity ==
                                        ComplianceSeverity.blocking
                                    ? colorScheme.error
                                    : Theme.of(context).appColors.warning,
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(violation.message)),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Schliessen'),
          ),
        ],
      ),
    );
  }

  Future<void> _showShiftConflictDialog(
    BuildContext context,
    List<ShiftConflictIssue> issues,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Schichtkonflikte'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: _ShiftConflictList(issues: issues),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Schliessen'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAbsenceEditor(BuildContext context) async {
    final currentUser = context.read<AuthProvider>().profile;
    final scheduleProvider = context.read<ScheduleProvider>();
    if (currentUser == null) {
      return;
    }

    final result = await showModalBottomSheet<AbsenceRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _AbsenceEditorSheet(currentUser: currentUser),
      ),
    );

    if (result == null) {
      return;
    }

    try {
      await scheduleProvider.submitAbsenceRequest(result);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Abwesenheit gemeldet.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $error')),
      );
    }
  }
}

class _AdminShiftPlannerBoard extends StatefulWidget {
  const _AdminShiftPlannerBoard({
    required this.members,
    required this.teams,
    required this.visibleShifts,
    required this.visibleAbsenceRequests,
    required this.rangeLabel,
    required this.employeeExportLabel,
    required this.selectedTeamName,
    required this.canNavigateBack,
    this.onNavigateBack,
    required this.onCopyWeek,
    required this.onAutoPlan,
    required this.onCopyShiftToDays,
    required this.onDropCopyShift,
    required this.onExport,
    required this.onOpenShiftEditor,
  });

  final List<AppUserProfile> members;
  final List<TeamDefinition> teams;
  final List<Shift> visibleShifts;
  final List<AbsenceRequest> visibleAbsenceRequests;
  final String rangeLabel;
  final String? employeeExportLabel;
  final String? selectedTeamName;
  final bool canNavigateBack;
  final VoidCallback? onNavigateBack;
  final Future<void> Function() onCopyWeek;
  final Future<void> Function() onAutoPlan;
  final Future<void> Function(Shift shift) onCopyShiftToDays;
  final Future<void> Function(
    Shift shift,
    DateTime targetDay,
    String? reassignUserId,
    String? reassignName,
  ) onDropCopyShift;
  final Future<void> Function(ShiftPlanExportFormat format, List<Shift> shifts)
      onExport;
  final _ShiftEditorLauncher onOpenShiftEditor;

  @override
  State<_AdminShiftPlannerBoard> createState() =>
      _AdminShiftPlannerBoardState();
}

class _AdminShiftPlannerBoardState extends State<_AdminShiftPlannerBoard> {
  static const _sideWidth = 154.0;
  static const _dayWidth = 176.0;
  static const _compactToolbarBreakpoint = 1040.0;
  static const _compactMonthBreakpoint = 860.0;

  _PlannerLayoutMode _layoutMode = _PlannerLayoutMode.employee;
  String? _selectedLocation;
  String? _selectedFunction;
  _PlannerAbsenceFilter _selectedAbsenceFilter = _PlannerAbsenceFilter.all;

  // Month sidebar state
  Set<String> _selectedMonthEmployeeIds = {};
  Set<String> _selectedMonthLocations = {};
  bool _sidebarEmployeesExpanded = true;
  bool _sidebarLocationsExpanded = true;

  List<Shift> _currentBoardShifts() {
    return _applyBoardFilters(widget.visibleShifts);
  }

  // --- Board-Vorgruppierung (planner-build-on-on-quadratic-filtering) -------
  // Statt in jeder Zeile/Tageszelle die gesamte Schichtliste neu zu filtern
  // (O(rows x days x shifts) pro Frame), werden die Schichten einmal pro Build
  // in Buckets pro Zeile bzw. pro Tag gruppiert; Zeile/Tag lesen dann nur per
  // Lookup.
  String _shiftBucketKey(Shift shift) {
    if (_layoutMode == _PlannerLayoutMode.employee) {
      return 'u:${shift.userId}';
    }
    final location = shift.effectiveSiteLabel?.trim();
    return 'l:${location == null || location.isEmpty ? '' : location}';
  }

  String _rowBucketKey(_PlannerBoardRowData row) {
    if (row.memberId != null) {
      return 'u:${row.memberId}';
    }
    final location = row.location?.trim();
    return 'l:${location == null || location.isEmpty ? '' : location}';
  }

  String _dayBucketKey(DateTime day) => '${day.year}-${day.month}-${day.day}';

  Map<String, List<Shift>> _groupShiftsByRow(List<Shift> shifts) {
    final buckets = <String, List<Shift>>{};
    for (final shift in shifts) {
      (buckets[_shiftBucketKey(shift)] ??= <Shift>[]).add(shift);
    }
    return buckets;
  }

  Map<String, List<Shift>> _groupShiftsByDay(List<Shift> shifts) {
    final buckets = <String, List<Shift>>{};
    for (final shift in shifts) {
      (buckets[_dayBucketKey(shift.startTime)] ??= <Shift>[]).add(shift);
    }
    return buckets;
  }

  @override
  Widget build(BuildContext context) {
    final schedule = context.watch<ScheduleProvider>();
    final theme = Theme.of(context);
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final useCompactToolbar = viewportWidth < _compactToolbarBreakpoint;
    final useCompactMonthLayout = viewportWidth < _compactMonthBreakpoint;
    final screenPadding = useCompactToolbar
        ? MobileBreakpoints.screenPadding(context)
        : const EdgeInsets.symmetric(horizontal: 18);
    final range =
        _currentScheduleRange(schedule.visibleDate, schedule.viewMode);
    final days = rangeDays(range.start, range.end);
    final filteredShifts = _currentBoardShifts();
    final filteredAbsenceRequests = _filteredAbsenceRequests(schedule);
    final freeShifts = filteredShifts
        .where((shift) => shift.isUnassigned)
        .toList(growable: false)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final plannedShifts = filteredShifts
        .where((shift) => !shift.isUnassigned)
        .toList(growable: false)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final rows = _layoutMode == _PlannerLayoutMode.employee
        ? _buildEmployeeRows(plannedShifts, schedule, days)
        : _buildLocationRows(plannedShifts);
    // Einmalige Vorgruppierung pro Zeile (plannedShifts ist bereits nach
    // Startzeit sortiert -> Buckets bleiben sortiert).
    final plannedByRow = _groupShiftsByRow(plannedShifts);
    final freeByDay = _groupShiftsByDay(freeShifts);

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
              children: [
                _buildToolbar(
                  context,
                  schedule: schedule,
                  isCompact: useCompactToolbar,
                ),
                if (schedule.loading)
                  const LinearProgressIndicator(minHeight: 2),
                _buildFilters(
                  context,
                  schedule: schedule,
                  isCompact: useCompactToolbar,
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    screenPadding.left,
                    12,
                    screenPadding.right,
                    0,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(22),
                      border:
                          Border.all(color: theme.colorScheme.outlineVariant),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.shadow.withValues(
                            alpha: theme.brightness == Brightness.dark
                                ? 0.24
                                : 0.08,
                          ),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Schichtplan',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${filteredShifts.length} Schichten',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color:
                                        theme.colorScheme.onSecondaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (schedule.viewMode == ScheduleViewMode.month)
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              useCompactMonthLayout ? 10 : 14,
                              0,
                              useCompactMonthLayout ? 10 : 14,
                              18,
                            ),
                            child: _buildMonthLayout(
                              context,
                              schedule: schedule,
                              filteredShifts: filteredShifts,
                              isCompact: useCompactMonthLayout,
                            ),
                          )
                        else
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.fromLTRB(
                              useCompactToolbar ? 10 : 14,
                              0,
                              useCompactToolbar ? 10 : 14,
                              18,
                            ),
                            child: SizedBox(
                              width: _sideWidth + (days.length * _dayWidth),
                              child: Column(
                                children: [
                                  _buildHeaderRow(
                                    context,
                                    days: days,
                                  ),
                                  const _PlannerSectionLabel('FREIE SCHICHTEN'),
                                  _buildFreeShiftRow(
                                    context,
                                    days: days,
                                    shiftsByDay: freeByDay,
                                    freeCount: freeShifts.length,
                                  ),
                                  const _PlannerSectionLabel('PLANMÄSSIGE SCHICHTEN'),
                                  if (rows.isEmpty)
                                    const _PlannerEmptyBoardState()
                                  else
                                    for (final row in rows)
                                      _buildPlannedRow(
                                        context,
                                        row: row,
                                        days: days,
                                        rowShifts: plannedByRow[
                                                _rowBucketKey(row)] ??
                                            const <Shift>[],
                                      ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (filteredAbsenceRequests.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      screenPadding.left,
                      12,
                      screenPadding.right,
                      0,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          Text(
                            'Abwesenheiten im Zeitraum',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          for (final absence in filteredAbsenceRequests)
                            _PlannerAbsencePill(
                              absence: absence,
                              showEmployeeName: true,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(
    BuildContext context, {
    required ScheduleProvider schedule,
    required bool isCompact,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    final compactPadding = MobileBreakpoints.screenPadding(context);

    if (isCompact) {
      return Container(
        color: colorScheme.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShellBreadcrumb(
              breadcrumbs: const [
                BreadcrumbItem(label: 'Plan'),
                BreadcrumbItem(label: 'Schichtplaner'),
              ],
              onBack: widget.canNavigateBack ? widget.onNavigateBack : null,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compactPadding.left,
                12,
                compactPadding.right,
                14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (schedule.viewMode == ScheduleViewMode.month) ...[
                        IconButton.filledTonal(
                          onPressed: () => _showMonthSidebarSheet(context),
                          icon: const Icon(Icons.menu_rounded),
                          tooltip: 'Mitarbeiter und Standorte',
                          style: IconButton.styleFrom(
                            backgroundColor: colorScheme.surfaceContainerHigh,
                            foregroundColor: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      _navIconButton(
                        context,
                        icon: Icons.chevron_left_rounded,
                        onTap: () => schedule.setVisibleDate(
                          _shiftVisibleDate(
                            schedule.visibleDate,
                            schedule.viewMode,
                            -1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _toolbarRangeLabel(
                            schedule.visibleDate,
                            schedule.viewMode,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _navIconButton(
                        context,
                        icon: Icons.chevron_right_rounded,
                        onTap: () => schedule.setVisibleDate(
                          _shiftVisibleDate(
                            schedule.visibleDate,
                            schedule.viewMode,
                            1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        onPressed: () => widget.onOpenShiftEditor(),
                        icon: const Icon(Icons.add_rounded),
                        tooltip: 'Neue Schicht',
                      ),
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        onPressed: () => widget.onAutoPlan(),
                        icon: const Icon(Icons.auto_fix_high_rounded),
                        tooltip: 'Automatisch planen',
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Aktionen',
                        onSelected: (value) =>
                            _handleToolbarActionSelection(context, value),
                        itemBuilder: (context) => _buildPlannerActionMenuItems(
                          includeLayoutOptions:
                              schedule.viewMode != ScheduleViewMode.month,
                          includePublishOptions: true,
                        ),
                        icon: const Icon(Icons.more_vert_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => schedule.setVisibleDate(
                            DateTime.now(),
                          ),
                          child: const Text('HEUTE'),
                        ),
                        const SizedBox(width: 10),
                        PopupMenuButton<ScheduleViewMode>(
                          onSelected: schedule.setViewMode,
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: ScheduleViewMode.day,
                              child: Text('Tag'),
                            ),
                            PopupMenuItem(
                              value: ScheduleViewMode.week,
                              child: Text('Woche'),
                            ),
                            PopupMenuItem(
                              value: ScheduleViewMode.month,
                              child: Text('Monat'),
                            ),
                          ],
                          child: _controlPill(
                            context,
                            label: 'Ansicht',
                            value: switch (schedule.viewMode) {
                              ScheduleViewMode.day => 'Tag',
                              ScheduleViewMode.week => 'Woche',
                              ScheduleViewMode.month => 'Monat',
                            },
                          ),
                        ),
                        if (schedule.viewMode != ScheduleViewMode.month) ...[
                          const SizedBox(width: 10),
                          PopupMenuButton<_PlannerLayoutMode>(
                            onSelected: (value) =>
                                setState(() => _layoutMode = value),
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: _PlannerLayoutMode.employee,
                                child: Text('Mitarbeiter'),
                              ),
                              PopupMenuItem(
                                value: _PlannerLayoutMode.location,
                                child: Text('Standort'),
                              ),
                            ],
                            child: _controlPill(
                              context,
                              label: 'Layout',
                              value: _layoutMode == _PlannerLayoutMode.employee
                                  ? 'Mitarbeiter'
                                  : 'Standort',
                            ),
                          ),
                        ],
                        const SizedBox(width: 10),
                        IconButton.filledTonal(
                          onPressed: _clearAllFilters,
                          icon: const Icon(Icons.filter_alt_off_outlined),
                          tooltip: 'Filter zuruecksetzen',
                          style: IconButton.styleFrom(
                            backgroundColor: colorScheme.surfaceContainerHigh,
                            foregroundColor: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShellBreadcrumb(
            breadcrumbs: const [
              BreadcrumbItem(label: 'Plan'),
              BreadcrumbItem(label: 'Schichtplaner'),
            ],
            onBack: widget.canNavigateBack ? widget.onNavigateBack : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            child: Row(
              children: [
                _navIconButton(
                  context,
                  icon: Icons.chevron_left_rounded,
                  onTap: () => schedule.setVisibleDate(
                    _shiftVisibleDate(
                      schedule.visibleDate,
                      schedule.viewMode,
                      -1,
                    ),
                  ),
                ),
                Flexible(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      _toolbarRangeLabel(
                        schedule.visibleDate,
                        schedule.viewMode,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                _navIconButton(
                  context,
                  icon: Icons.chevron_right_rounded,
                  onTap: () => schedule.setVisibleDate(
                    _shiftVisibleDate(
                      schedule.visibleDate,
                      schedule.viewMode,
                      1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => schedule.setVisibleDate(DateTime.now()),
                  child: const Text('HEUTE'),
                ),
                const SizedBox(width: 8),
                // Steuer-/Aktions-Cluster: rechtsbündig, scrollt horizontal,
                // wenn die Breite knapp wird (kein RenderFlex-Overflow mehr,
                // auch bei großer Schriftskalierung).
                Flexible(
                  flex: 3,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (schedule.viewMode != ScheduleViewMode.month) ...[
                          PopupMenuButton<_PlannerLayoutMode>(
                            onSelected: (value) =>
                                setState(() => _layoutMode = value),
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: _PlannerLayoutMode.employee,
                                child: Text('Mitarbeiter'),
                              ),
                              PopupMenuItem(
                                value: _PlannerLayoutMode.location,
                                child: Text('Standort'),
                              ),
                            ],
                            child: _controlPill(
                              context,
                              label: 'Layout',
                              value: _layoutMode == _PlannerLayoutMode.employee
                                  ? 'Mitarbeiter'
                                  : 'Standort',
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        PopupMenuButton<ScheduleViewMode>(
                          onSelected: schedule.setViewMode,
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: ScheduleViewMode.day,
                              child: Text('Tag'),
                            ),
                            PopupMenuItem(
                              value: ScheduleViewMode.week,
                              child: Text('Woche'),
                            ),
                            PopupMenuItem(
                              value: ScheduleViewMode.month,
                              child: Text('Monat'),
                            ),
                          ],
                          child: _controlPill(
                            context,
                            label: 'Ansicht',
                            value: switch (schedule.viewMode) {
                              ScheduleViewMode.day => 'Tag',
                              ScheduleViewMode.week => 'Woche',
                              ScheduleViewMode.month => 'Monat',
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filledTonal(
                          onPressed: _clearAllFilters,
                          icon: const Icon(Icons.filter_alt_off_outlined),
                          tooltip: 'Filter zuruecksetzen',
                          style: IconButton.styleFrom(
                            backgroundColor: colorScheme.surfaceContainerHigh,
                            foregroundColor: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.tonalIcon(
                          onPressed: () => widget.onOpenShiftEditor(),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Neue Schicht'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        PopupMenuButton<String>(
                          onSelected: (value) =>
                              _handleToolbarActionSelection(context, value),
                          itemBuilder: (context) =>
                              _buildPlannerActionMenuItems(),
                          child: _outlineActionButton(context, 'AKTIONEN'),
                        ),
                        const SizedBox(width: 10),
                        InkWell(
                          onTap: () =>
                              _handleToolbarActionSelection(context, 'publish'),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: appColors.success,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      appColors.success.withValues(alpha: 0.24),
                                  blurRadius: 14,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Text(
                              'VERÖFFENTLICHEN',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: appColors.onSuccess,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildPlannerActionMenuItems({
    bool includeLayoutOptions = false,
    bool includePublishOptions = false,
  }) {
    return [
      const PopupMenuItem(value: 'new', child: Text('Schicht anlegen')),
      const PopupMenuItem(
        value: 'free',
        child: Text('Freie Schicht anlegen'),
      ),
      const PopupMenuItem(value: 'copy', child: Text('Woche kopieren')),
      const PopupMenuItem(
        value: 'auto',
        child: Text('Automatisch planen'),
      ),
      const PopupMenuItem(
        value: 'staffing_profile',
        child: Text('Besetzungs-Profil (Kassendaten)'),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: 'pdf',
        child: Text('Als PDF exportieren'),
      ),
      const PopupMenuItem(
        value: 'csv',
        child: Text('Als CSV exportieren'),
      ),
      if (includeLayoutOptions) ...[
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'layout_employee',
          child: Text('Layout: Mitarbeiter'),
        ),
        const PopupMenuItem(
          value: 'layout_location',
          child: Text('Layout: Standort'),
        ),
      ],
      if (includePublishOptions) ...[
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'publish',
          child: Text('Veroeffentlichen'),
        ),
      ],
    ];
  }

  Future<void> _handleToolbarActionSelection(
    BuildContext context,
    String value,
  ) async {
    final shifts = _currentBoardShifts();
    switch (value) {
      case 'new':
        await widget.onOpenShiftEditor();
      case 'free':
        await widget.onOpenShiftEditor(
          initialUnassigned: true,
        );
      case 'copy':
        await widget.onCopyWeek();
      case 'auto':
        await widget.onAutoPlan();
      case 'staffing_profile':
        context.push(AppRoutes.staffingProfile);
      case 'pdf':
        await widget.onExport(
          ShiftPlanExportFormat.pdf,
          shifts,
        );
      case 'csv':
        await widget.onExport(
          ShiftPlanExportFormat.csv,
          shifts,
        );
      case 'layout_employee':
        setState(() => _layoutMode = _PlannerLayoutMode.employee);
      case 'layout_location':
        setState(() => _layoutMode = _PlannerLayoutMode.location);
      case 'publish':
        await _publishVisibleShifts(context, shifts);
    }
  }

  Future<void> _showMonthSidebarSheet(BuildContext context) async {
    final theme = Theme.of(context);
    final locations = widget.visibleShifts
        .map((shift) => shift.effectiveSiteLabel?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, modalSetState) {
          void syncState(VoidCallback update) {
            setState(update);
            modalSetState(() {});
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.88,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Kalender-Menue',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_selectedMonthEmployeeIds.isNotEmpty ||
                            _selectedMonthLocations.isNotEmpty)
                          TextButton(
                            onPressed: () => syncState(() {
                              _selectedMonthEmployeeIds = {};
                              _selectedMonthLocations = {};
                            }),
                            child: const Text('Zuruecksetzen'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Mitarbeiter und Standorte fuer die Monatsansicht auswaehlen.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'MITARBEITER',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final member in widget.members)
                      _PlannerSidebarCheckbox(
                        label: member.displayName,
                        selected: _selectedMonthEmployeeIds.contains(
                          member.uid,
                        ),
                        onChanged: (selected) => syncState(() {
                          if (selected) {
                            _selectedMonthEmployeeIds.add(member.uid);
                          } else {
                            _selectedMonthEmployeeIds.remove(member.uid);
                          }
                        }),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      'STANDORTE',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (locations.isEmpty)
                      Text(
                        'Im aktuellen Zeitraum sind keine Standorte vorhanden.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      for (final location in locations)
                        _PlannerSidebarCheckbox(
                          label: location,
                          selected: _selectedMonthLocations.contains(location),
                          onChanged: (selected) => syncState(() {
                            if (selected) {
                              _selectedMonthLocations.add(location);
                            } else {
                              _selectedMonthLocations.remove(location);
                            }
                          }),
                        ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMonthLayout(
    BuildContext context, {
    required ScheduleProvider schedule,
    required List<Shift> filteredShifts,
    required bool isCompact,
  }) {
    if (isCompact) {
      return _buildMonthBoard(
        context,
        visibleDate: schedule.visibleDate,
        shifts: filteredShifts,
        isCompact: true,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 240,
          child: _buildMonthSidebar(
            context,
            schedule: schedule,
            shifts: filteredShifts,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMonthBoard(
            context,
            visibleDate: schedule.visibleDate,
            shifts: filteredShifts,
            isCompact: false,
          ),
        ),
      ],
    );
  }

  Widget _buildMonthSidebar(
    BuildContext context, {
    required ScheduleProvider schedule,
    required List<Shift> shifts,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visibleDate = schedule.visibleDate;
    final firstOfMonth = DateTime(visibleDate.year, visibleDate.month, 1);
    final miniDays = calendarMonthGridDays(visibleDate);
    final miniWeeks = chunkDays(miniDays, 7);

    final locations = widget.visibleShifts
        .map((shift) => shift.effectiveSiteLabel?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Mini-Kalender ──
            Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    final prev = DateTime(
                      visibleDate.year,
                      visibleDate.month - 1,
                    );
                    schedule.setVisibleDate(prev);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.chevron_left_rounded,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      DateFormat('MMMM yyyy', 'de_DE').format(firstOfMonth),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    final next = DateTime(
                      visibleDate.year,
                      visibleDate.month + 1,
                    );
                    schedule.setVisibleDate(next);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Weekday header
            Row(
              children: [
                for (final label in ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'])
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // Day grid
            for (final week in miniWeeks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    for (final day in week)
                      Expanded(
                        child: _PlannerMiniCalendarDay(
                          day: day,
                          visibleDate: visibleDate,
                          onTap: () {
                            schedule.setVisibleDate(day);
                            schedule.setViewMode(ScheduleViewMode.day);
                          },
                        ),
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 16),
            Divider(color: colorScheme.outlineVariant, height: 1),
            const SizedBox(height: 12),

            // ── Mitarbeiter ──
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(
                () => _sidebarEmployeesExpanded = !_sidebarEmployeesExpanded,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      _sidebarEmployeesExpanded
                          ? Icons.expand_more
                          : Icons.chevron_right,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'MITARBEITER',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurfaceVariant,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const Spacer(),
                    if (_selectedMonthEmployeeIds.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_selectedMonthEmployeeIds.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_sidebarEmployeesExpanded) ...[
              const SizedBox(height: 4),
              for (final member in widget.members)
                _PlannerSidebarCheckbox(
                  label: member.displayName,
                  selected: _selectedMonthEmployeeIds.contains(member.uid),
                  onChanged: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedMonthEmployeeIds.add(member.uid);
                      } else {
                        _selectedMonthEmployeeIds.remove(member.uid);
                      }
                    });
                  },
                ),
            ],

            const SizedBox(height: 12),
            Divider(color: colorScheme.outlineVariant, height: 1),
            const SizedBox(height: 12),

            // ── Standorte ──
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(
                () => _sidebarLocationsExpanded = !_sidebarLocationsExpanded,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      _sidebarLocationsExpanded
                          ? Icons.expand_more
                          : Icons.chevron_right,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'STANDORTE',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurfaceVariant,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const Spacer(),
                    if (_selectedMonthLocations.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_selectedMonthLocations.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_sidebarLocationsExpanded) ...[
              const SizedBox(height: 4),
              for (final location in locations)
                _PlannerSidebarCheckbox(
                  label: location,
                  selected: _selectedMonthLocations.contains(location),
                  onChanged: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedMonthLocations.add(location);
                      } else {
                        _selectedMonthLocations.remove(location);
                      }
                    });
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMonthBoard(
    BuildContext context, {
    required DateTime visibleDate,
    required List<Shift> shifts,
    required bool isCompact,
  }) {
    final theme = Theme.of(context);
    final monthDays = calendarMonthGridDays(visibleDate);
    final weekChunks = chunkDays(monthDays, 7);
    final daysByKey = {
      for (final day in monthDays) dayKey(day): day,
    };
    final shiftsByDay = <int, List<Shift>>{};
    for (final shift in shifts) {
      final day = DateTime(
        shift.startTime.year,
        shift.startTime.month,
        shift.startTime.day,
      );
      final key = dayKey(day);
      if (!daysByKey.containsKey(key)) {
        continue;
      }
      shiftsByDay.putIfAbsent(key, () => <Shift>[]).add(shift);
    }
    for (final entries in shiftsByDay.values) {
      entries.sort((a, b) {
        final byStart = a.startTime.compareTo(b.startTime);
        if (byStart != 0) {
          return byStart;
        }
        if (a.isUnassigned != b.isUnassigned) {
          return a.isUnassigned ? -1 : 1;
        }
        return a.employeeName.compareTo(b.employeeName);
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactBoard =
            isCompact || constraints.maxWidth < _compactMonthBreakpoint;
        const weekNumberWidth = 52.0;
        const weekdayHeaderHeight = 44.0;
        final dayCellHeight =
            compactBoard && constraints.maxWidth < MobileBreakpoints.standard
                ? 92.0
                : compactBoard
                    ? 108.0
                    : 180.0;

        if (compactBoard) {
          return _buildCompactMonthBoard(
            context,
            visibleDate: visibleDate,
            weekChunks: weekChunks,
            shiftsByDay: shiftsByDay,
            dayCellHeight: dayCellHeight,
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const _PlannerMonthWeekHeaderCell(
                      width: weekNumberWidth,
                      height: weekdayHeaderHeight,
                    ),
                    for (final day in weekChunks.first)
                      Expanded(
                        child: _PlannerMonthWeekdayHeaderCell(
                          height: weekdayHeaderHeight,
                          day: day,
                        ),
                      ),
                  ],
                ),
                for (var weekIndex = 0;
                    weekIndex < weekChunks.length;
                    weekIndex++)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PlannerMonthWeekNumberCell(
                        width: weekNumberWidth,
                        height: dayCellHeight,
                        weekNumber: isoWeekNumber(weekChunks[weekIndex].first),
                      ),
                      for (final day in weekChunks[weekIndex])
                        Expanded(
                          child: _PlannerMonthDayCell(
                            height: dayCellHeight,
                            day: day,
                            visibleMonth: visibleDate.month,
                            visibleYear: visibleDate.year,
                            shifts: shiftsByDay[dayKey(day)] ?? const [],
                            absenceCount: _dayAbsenceCount(day),
                            onAddShift: () => widget.onOpenShiftEditor(
                              initialDate: day,
                              initialLocation: _selectedLocation,
                            ),
                            onShowAbsences: () => _showDayNotes(context, day),
                            onOpenShift: (shift) =>
                                widget.onOpenShiftEditor(shift: shift),
                            onDeleteShift: (shift) =>
                                _deleteShift(context, shift),
                            onDeleteSeries: (seriesId) =>
                                _deleteShiftSeries(context, seriesId),
                            onShowMore: () => _showMonthDayDetails(
                              context,
                              day,
                              shiftsByDay[dayKey(day)] ?? const [],
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactMonthBoard(
    BuildContext context, {
    required DateTime visibleDate,
    required List<List<DateTime>> weekChunks,
    required Map<int, List<Shift>> shiftsByDay,
    required double dayCellHeight,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            Row(
              children: [
                for (final label in const [
                  'Mo',
                  'Di',
                  'Mi',
                  'Do',
                  'Fr',
                  'Sa',
                  'So'
                ])
                  Expanded(
                    child: _PlannerCompactMonthWeekdayHeaderCell(
                      label: label,
                    ),
                  ),
              ],
            ),
            for (final week in weekChunks)
              SizedBox(
                height: dayCellHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final day in week)
                      Expanded(
                        child: _PlannerCompactMonthDayCell(
                          height: dayCellHeight,
                          day: day,
                          visibleMonth: visibleDate.month,
                          visibleYear: visibleDate.year,
                          shifts: shiftsByDay[dayKey(day)] ?? const [],
                          absenceCount: _dayAbsenceCount(day),
                          onTapDay: () => _showMonthDayDetails(
                            context,
                            day,
                            shiftsByDay[dayKey(day)] ?? const [],
                          ),
                          onOpenShift: (shift) =>
                              widget.onOpenShiftEditor(shift: shift),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(
    BuildContext context, {
    required ScheduleProvider schedule,
    required bool isCompact,
  }) {
    final theme = Theme.of(context);
    final horizontalPadding = isCompact
        ? MobileBreakpoints.screenPadding(context)
        : const EdgeInsets.symmetric(horizontal: 18);
    final activeFilterChips = _buildActiveFilterChips(schedule);
    final locations = widget.visibleShifts
        .map((shift) => shift.effectiveSiteLabel?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
    final functions = widget.visibleShifts
        .map((shift) => shift.title.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
    final filterControls = <Widget>[
      PopupMenuButton<String?>(
        initialValue: _selectedLocation,
        onSelected: (value) => setState(() => _selectedLocation = value),
        itemBuilder: (context) => [
          const PopupMenuItem<String?>(
            value: null,
            child: Text('Alle Standorte'),
          ),
          for (final location in locations)
            PopupMenuItem<String?>(
              value: location,
              child: Text(location),
            ),
        ],
        child: _filterPill(
          context,
          label: 'Standort',
          activeCount: _selectedLocation == null ? 0 : 1,
        ),
      ),
      PopupMenuButton<String?>(
        initialValue: schedule.selectedTeamId,
        onSelected: (value) {
          final team =
              widget.teams.where((entry) => entry.id == value).firstOrNull;
          schedule.setTeamFilter(value, teamName: team?.name);
        },
        itemBuilder: (context) => [
          const PopupMenuItem<String?>(
            value: null,
            child: Text('Alle Arbeitsbereiche'),
          ),
          for (final team in widget.teams)
            PopupMenuItem<String?>(
              value: team.id,
              child: Text(team.name),
            ),
        ],
        child: _filterPill(
          context,
          label: 'Arbeitsbereiche',
          activeCount: schedule.selectedTeamId == null ? 0 : 1,
        ),
      ),
      PopupMenuButton<String?>(
        initialValue: schedule.selectedUserId,
        onSelected: schedule.setSelectedUserId,
        itemBuilder: (context) => [
          const PopupMenuItem<String?>(
            value: null,
            child: Text('Alle Mitarbeiter'),
          ),
          for (final member in widget.members)
            PopupMenuItem<String?>(
              value: member.uid,
              child: Text(member.displayName),
            ),
        ],
        child: _filterPill(
          context,
          label: 'Mitarbeiter',
          activeCount: schedule.selectedUserId == null ? 0 : 1,
        ),
      ),
      PopupMenuButton<String?>(
        initialValue: _selectedFunction,
        onSelected: (value) => setState(() => _selectedFunction = value),
        itemBuilder: (context) => [
          const PopupMenuItem<String?>(
            value: null,
            child: Text('Alle Funktionen'),
          ),
          for (final function in functions)
            PopupMenuItem<String?>(
              value: function,
              child: Text(function),
            ),
        ],
        child: _filterPill(
          context,
          label: 'Funktion',
          activeCount: _selectedFunction == null ? 0 : 1,
        ),
      ),
      PopupMenuButton<_PlannerAbsenceFilter>(
        initialValue: _selectedAbsenceFilter,
        onSelected: (value) => setState(() => _selectedAbsenceFilter = value),
        itemBuilder: (context) => const [
          PopupMenuItem<_PlannerAbsenceFilter>(
            value: _PlannerAbsenceFilter.all,
            child: Text('Alle Abwesenheiten'),
          ),
          PopupMenuItem<_PlannerAbsenceFilter>(
            value: _PlannerAbsenceFilter.vacation,
            child: Text('Urlaub anzeigen'),
          ),
          PopupMenuItem<_PlannerAbsenceFilter>(
            value: _PlannerAbsenceFilter.sickness,
            child: Text('Krank anzeigen'),
          ),
          PopupMenuItem<_PlannerAbsenceFilter>(
            value: _PlannerAbsenceFilter.unavailable,
            child: Text('Nicht verfuegbar anzeigen'),
          ),
        ],
        child: _filterPill(
          context,
          label: 'Abwesenheiten',
          activeCount:
              _selectedAbsenceFilter == _PlannerAbsenceFilter.all ? 0 : 1,
        ),
      ),
      PopupMenuButton<ShiftStatus?>(
        initialValue: schedule.statusFilter,
        onSelected: schedule.setStatusFilter,
        itemBuilder: (context) => [
          const PopupMenuItem<ShiftStatus?>(
            value: null,
            child: Text('Alle Tags'),
          ),
          for (final status in ShiftStatus.values)
            PopupMenuItem<ShiftStatus?>(
              value: status,
              child: Text(status.label),
            ),
        ],
        child: _filterPill(
          context,
          label: 'Tags',
          activeCount: schedule.statusFilter == null ? 0 : 1,
        ),
      ),
    ];

    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding.left,
        0,
        horizontalPadding.right,
        12,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: isCompact
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var index = 0;
                            index < filterControls.length;
                            index++) ...[
                          filterControls[index],
                          if (index < filterControls.length - 1)
                            const SizedBox(width: 10),
                        ],
                      ],
                    ),
                  )
                : Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: filterControls,
                  ),
          ),
          if (activeFilterChips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: isCompact
                    ? SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var index = 0;
                                index < activeFilterChips.length;
                                index++) ...[
                              activeFilterChips[index],
                              if (index < activeFilterChips.length - 1)
                                const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: activeFilterChips,
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(
    BuildContext context, {
    required List<DateTime> days,
  }) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant;
    final accentColor = theme.appColors.info;
    return Row(
      children: [
        Container(
          width: _sideWidth,
          height: 78,
          padding: const EdgeInsets.only(left: 10, right: 14),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: borderColor),
              bottom: BorderSide(color: borderColor),
            ),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => widget.onOpenShiftEditor(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_circle,
                      size: 22,
                      color: accentColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'SCHICHT',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        for (final day in days)
          _PlannerDayHeaderCell(
            day: day,
            width: _dayWidth,
            noteCount: _dayAbsenceCount(day),
            onTapNote: () => _showDayNotes(context, day),
          ),
      ],
    );
  }


  Widget _buildFreeShiftRow(
    BuildContext context, {
    required List<DateTime> days,
    required Map<String, List<Shift>> shiftsByDay,
    required int freeCount,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rowLabelCell(
          context,
          title: 'Offene Slots',
          subtitle: freeCount == 0
              ? 'Noch keine freie Schicht'
              : '$freeCount offen',
        ),
        for (final day in days)
          _buildDayCell(
            context,
            day: day,
            shifts: shiftsByDay[_dayBucketKey(day)] ?? const <Shift>[],
            onAdd: () => widget.onOpenShiftEditor(
              initialDate: day,
              initialUnassigned: true,
              initialLocation: _selectedLocation,
            ),
          ),
      ],
    );
  }

  Widget _buildPlannedRow(
    BuildContext context, {
    required _PlannerBoardRowData row,
    required List<DateTime> days,
    required List<Shift> rowShifts,
    List<DateTime>? summaryDays,
  }) {
    // rowShifts ist bereits fuer diese Zeile vorgefiltert und nach Startzeit
    // sortiert; Tages-Buckets einmal bilden statt pro Tag neu zu filtern.
    final shiftsByDay = _groupShiftsByDay(rowShifts);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRowIdentity(
          context,
          row,
          rowShifts,
          summaryDays ?? days,
        ),
        for (final day in days)
          _buildDayCell(
            context,
            day: day,
            absences: _rowAbsencesForDay(row, day),
            shifts: shiftsByDay[_dayBucketKey(day)] ?? const <Shift>[],
            onAdd: () => widget.onOpenShiftEditor(
              initialDate: day,
              initialUserIds: row.memberId == null ? null : {row.memberId!},
              initialLocation: row.location,
            ),
            onDropShift: (dragged) =>
                _handleShiftDrop(dragged, targetDay: day, row: row),
          ),
      ],
    );
  }

  Widget _buildRowIdentity(
    BuildContext context,
    _PlannerBoardRowData row,
    List<Shift> rowShifts,
    List<DateTime> days,
  ) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final avatarColor = _plannerAvatarColor(theme, row);
    final actualHours =
        rowShifts.fold<double>(0, (sum, shift) => sum + shift.workedHours);
    final targetHours = row.targetHoursFor(days);
    final avatarForeground = ThemeData.estimateBrightnessForColor(
              avatarColor,
            ) ==
            Brightness.dark
        ? Colors.white
        : theme.colorScheme.onSurface;
    return Container(
      width: _sideWidth,
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: avatarColor,
            foregroundColor: avatarForeground,
            child: Text(
              row.avatarLabel,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (row.subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    row.subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: actualHours > targetHours
                        ? theme.colorScheme.errorContainer
                        : appColors.successContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${actualHours.toStringAsFixed(0)}h/${targetHours.toStringAsFixed(0)}h',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: actualHours > targetHours
                          ? theme.colorScheme.onErrorContainer
                          : appColors.onSuccessContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell(
    BuildContext context, {
    required DateTime day,
    required List<Shift> shifts,
    List<AbsenceRequest> absences = const [],
    required Future<void> Function() onAdd,
    Future<void> Function(Shift dragged)? onDropShift,
  }) {
    final theme = Theme.of(context);
    final footerLabels = <String>[
      if (shifts.isNotEmpty)
        '${shifts.fold<double>(0, (sum, shift) => sum + shift.workedHours).toStringAsFixed(0)}h',
      if (absences.isNotEmpty)
        absences.length == 1 ? '1 Abw.' : '${absences.length} Abw.',
    ];

    Widget buildContent({bool highlighted = false}) {
      return Container(
        width: _dayWidth,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: highlighted
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
              : null,
          border: Border(
            right: BorderSide(color: theme.colorScheme.outlineVariant),
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (shifts.isEmpty && absences.isEmpty)
              SizedBox(
                height: 72,
                child: Center(
                  child: _PlannerQuickAddButton(onTap: onAdd),
                ),
              )
            else ...[
              for (final absence in absences)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PlannerAbsencePill(
                    absence: absence,
                    compact: true,
                  ),
                ),
              for (final shift in shifts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildDraggableShiftCard(context, shift, shifts),
                ),
              Align(
                alignment: Alignment.center,
                child: _PlannerQuickAddButton(onTap: onAdd),
              ),
            ],
            if (footerLabels.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                footerLabels.join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (onDropShift == null) {
      return buildContent();
    }
    // Drop-Ziel: gezogene Schicht wird auf diesen Tag (und ggf. diese
    // Mitarbeiter-Zeile) KOPIERT. Highlight, solange eine Schicht über der
    // Zelle schwebt.
    return DragTarget<Shift>(
      onAcceptWithDetails: (details) => onDropShift(details.data),
      builder: (context, candidate, rejected) =>
          buildContent(highlighted: candidate.isNotEmpty),
    );
  }

  /// Schichtkarte als [LongPressDraggable] – LongPress (nicht Draggable),
  /// damit das horizontale Scrollen des Boards erhalten bleibt.
  Widget _buildDraggableShiftCard(
    BuildContext context,
    Shift shift,
    List<Shift> dayShifts,
  ) {
    final card = _PlannerBoardShiftCard(
      shift: shift,
      sameBucketCount:
          dayShifts.where((entry) => entry.title == shift.title).length,
      onTap: () => widget.onOpenShiftEditor(shift: shift),
      onDelete: () => _deleteShift(context, shift),
      onDeleteSeries: shift.seriesId == null
          ? null
          : () => _deleteShiftSeries(context, shift.seriesId!),
      onCopyToDays: () => widget.onCopyShiftToDays(shift),
    );
    final feedback = _shiftDragFeedback(context, shift);
    final whileDragging = Opacity(opacity: 0.4, child: card);

    // Auf Desktop/Web (Maus) sofortiges Ziehen per Klick – dort scrollt das
    // Board ohnehin per Rad/Trackpad, kein Gesten-Konflikt. Auf Touch
    // LongPress-Draggable, damit das Board weiter mit dem Finger horizontal
    // gescrollt werden kann.
    final usePointerDrag = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;

    if (usePointerDrag) {
      return Draggable<Shift>(
        data: shift,
        feedback: feedback,
        childWhenDragging: whileDragging,
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: card,
        ),
      );
    }
    return LongPressDraggable<Shift>(
      data: shift,
      feedback: feedback,
      childWhenDragging: whileDragging,
      child: card,
    );
  }

  Widget _shiftDragFeedback(BuildContext context, Shift shift) {
    final theme = Theme.of(context);
    final timeFmt = DateFormat('HH:mm', 'de_DE');
    return Material(
      color: Colors.transparent,
      child: Container(
        width: _dayWidth - 20,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              shift.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              '${timeFmt.format(shift.startTime)} - ${timeFmt.format(shift.endTime)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  /// Verarbeitet einen Drop auf eine Tageszelle: kopiert die gezogene Schicht
  /// auf den Zieltag; liegt das Ziel in einer anderen Mitarbeiter-Zeile, wird
  /// die Kopie diesem Mitarbeiter zugewiesen. Drop auf dieselbe Zelle = No-Op.
  Future<void> _handleShiftDrop(
    Shift dragged, {
    required DateTime targetDay,
    required _PlannerBoardRowData row,
  }) {
    final sourceDay = DateTime(
      dragged.startTime.year,
      dragged.startTime.month,
      dragged.startTime.day,
    );
    final target = DateTime(targetDay.year, targetDay.month, targetDay.day);
    String? reassignUserId;
    String? reassignName;
    if (row.memberId != null && row.memberId != dragged.userId) {
      final member =
          widget.members.firstWhereOrNull((m) => m.uid == row.memberId);
      reassignUserId = row.memberId;
      reassignName = member?.displayName ?? row.title;
    }
    if (target == sourceDay && reassignUserId == null) {
      return Future<void>.value();
    }
    return widget.onDropCopyShift(dragged, target, reassignUserId, reassignName);
  }

  Widget _rowLabelCell(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: _sideWidth,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActiveFilterChips(ScheduleProvider schedule) {
    final activeMember = widget.members
        .where((member) => member.uid == schedule.selectedUserId)
        .firstOrNull;
    final chips = <Widget>[
      if (_selectedLocation != null)
        _activeFilterChip(
          label: 'Standort: $_selectedLocation',
          onDeleted: () => setState(() => _selectedLocation = null),
        ),
      if (schedule.selectedTeamName != null)
        _activeFilterChip(
          label: 'Arbeitsbereich: ${schedule.selectedTeamName}',
          onDeleted: () => schedule.setTeamFilter(null),
        ),
      if (activeMember != null)
        _activeFilterChip(
          label: 'Mitarbeiter: ${activeMember.displayName}',
          onDeleted: () => schedule.setSelectedUserId(null),
        ),
      if (_selectedFunction != null)
        _activeFilterChip(
          label: 'Funktion: $_selectedFunction',
          onDeleted: () => setState(() => _selectedFunction = null),
        ),
      if (_selectedAbsenceFilter != _PlannerAbsenceFilter.all)
        _activeFilterChip(
          label:
              'Abwesenheiten: ${_absenceFilterLabel(_selectedAbsenceFilter)}',
          onDeleted: () => setState(
            () => _selectedAbsenceFilter = _PlannerAbsenceFilter.all,
          ),
        ),
      if (schedule.statusFilter != null)
        _activeFilterChip(
          label: 'Tag: ${schedule.statusFilter!.label}',
          onDeleted: () => schedule.setStatusFilter(null),
        ),
      if (_selectedMonthEmployeeIds.isNotEmpty)
        _activeFilterChip(
          label:
              'Monat Mitarbeiter: ${_selectionSummary(_selectedMonthEmployeeNames())}',
          onDeleted: () => setState(() => _selectedMonthEmployeeIds = {}),
        ),
      if (_selectedMonthLocations.isNotEmpty)
        _activeFilterChip(
          label:
              'Monat Standorte: ${_selectionSummary(_selectedMonthLocations.toList()..sort())}',
          onDeleted: () => setState(() => _selectedMonthLocations = {}),
        ),
    ];
    return chips;
  }

  List<String> _selectedMonthEmployeeNames() {
    return widget.members
        .where((member) => _selectedMonthEmployeeIds.contains(member.uid))
        .map((member) => member.displayName)
        .toList(growable: false)
      ..sort();
  }

  String _selectionSummary(List<String> values) {
    if (values.isEmpty) {
      return 'Alle';
    }
    if (values.length == 1) {
      return values.first;
    }
    return '${values.first} +${values.length - 1}';
  }

  Widget _activeFilterChip({
    required String label,
    required VoidCallback onDeleted,
  }) {
    final theme = Theme.of(context);
    return InputChip(
      label: Text(label),
      onDeleted: onDeleted,
      deleteIcon: const Icon(Icons.close, size: 18),
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      side: BorderSide(color: theme.colorScheme.outlineVariant),
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Future<void> _showMonthDayDetails(
    BuildContext context,
    DateTime day,
    List<Shift> dayShifts,
  ) async {
    final theme = Theme.of(context);
    final dayAbsences = _dayAbsences(day);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(DateFormat('EEEE, dd. MMMM yyyy', 'de_DE').format(day)),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dayAbsences.isNotEmpty) ...[
                  Text(
                    'Abwesenheiten',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final absence in dayAbsences)
                        _PlannerAbsencePill(
                          absence: absence,
                          showEmployeeName: true,
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
                Text(
                  dayShifts.isEmpty ? 'Keine Schichten' : 'Schichten',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                if (dayShifts.isEmpty)
                  Text(
                    'Fuer diesen Tag sind aktuell keine Schichten hinterlegt.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Column(
                    children: [
                      for (final shift in dayShifts)
                        _ShiftCard(
                          shift: shift,
                          isAdmin: true,
                          onEdit: () {
                            Navigator.of(dialogContext).pop();
                            widget.onOpenShiftEditor(shift: shift);
                          },
                          onDelete: () {
                            Navigator.of(dialogContext).pop();
                            _deleteShift(context, shift);
                          },
                          onDeleteSeries: shift.seriesId == null
                              ? null
                              : () {
                                  Navigator.of(dialogContext).pop();
                                  _deleteShiftSeries(context, shift.seriesId!);
                                },
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Schliessen'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              widget.onOpenShiftEditor(
                initialDate: day,
                initialLocation: _selectedLocation,
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Schicht anlegen'),
          ),
        ],
      ),
    );
  }

  List<Shift> _applyBoardFilters(List<Shift> shifts) {
    final schedule = context.read<ScheduleProvider>();
    return shifts.where((shift) {
      if (_selectedLocation != null &&
          shift.effectiveSiteLabel != _selectedLocation) {
        return false;
      }
      if (_selectedFunction != null && shift.title != _selectedFunction) {
        return false;
      }
      if (schedule.viewMode == ScheduleViewMode.month) {
        if (_selectedMonthEmployeeIds.isNotEmpty &&
            !shift.isUnassigned &&
            !_selectedMonthEmployeeIds.contains(shift.userId)) {
          return false;
        }
        if (_selectedMonthLocations.isNotEmpty) {
          final label = shift.effectiveSiteLabel?.trim() ?? '';
          if (!_selectedMonthLocations.contains(label)) {
            return false;
          }
        }
      }
      return true;
    }).toList(growable: false);
  }

  List<_PlannerBoardRowData> _buildEmployeeRows(
    List<Shift> shifts,
    ScheduleProvider schedule,
    List<DateTime> days,
  ) {
    final selectedTeam = widget.teams
        .where((team) => team.id == schedule.selectedTeamId)
        .firstOrNull;
    Iterable<AppUserProfile> members = widget.members;
    if (selectedTeam != null) {
      members = members
          .where((member) => selectedTeam.memberIds.contains(member.uid));
    }
    if (schedule.selectedUserId != null) {
      members =
          members.where((member) => member.uid == schedule.selectedUserId);
    }

    final rows = <String, _PlannerBoardRowData>{
      for (final member in members)
        member.uid: _PlannerBoardRowData.employee(member),
    };

    for (final shift in shifts) {
      rows.putIfAbsent(
        shift.userId,
        () => _PlannerBoardRowData.fallbackEmployee(
          userId: shift.userId,
          employeeName: shift.employeeName,
        ),
      );
    }

    return rows.values.toList(growable: false)
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  List<_PlannerBoardRowData> _buildLocationRows(List<Shift> shifts) {
    final locations = shifts
        .map((shift) => shift.effectiveSiteLabel?.trim().isNotEmpty == true
            ? shift.effectiveSiteLabel!.trim()
            : 'Ohne Standort')
        .toSet()
        .toList(growable: false)
      ..sort();
    return locations
        .map((location) => _PlannerBoardRowData.location(location))
        .toList(growable: false);
  }

  Future<void> _publishVisibleShifts(
    BuildContext context,
    List<Shift> shifts,
  ) async {
    final publishable = shifts
        .where((shift) =>
            shift.status != ShiftStatus.completed &&
            shift.status != ShiftStatus.cancelled)
        .toList(growable: false);
    if (publishable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Keine veroefentlichbaren Schichten im Filter.')),
      );
      return;
    }
    try {
      await context.read<ScheduleProvider>().publishShifts(publishable);
      if (!context.mounted) {
        return;
      }
      // Server-seitig (onShiftWritten-Trigger) wird jede neu bestaetigte,
      // zugewiesene Schicht dem Mitarbeiter gemeldet (In-App + Push, pro Woche
      // gebuendelt) — daher die Benachrichtigung hier ehrlich ansagen.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Schichtplan fuer ${publishable.length} Schichten veroeffentlicht. '
            'Zugewiesene Mitarbeiter werden benachrichtigt.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  static Future<bool> _confirmShiftDeletion(
    BuildContext context, {
    required bool series,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(series ? 'Ganze Serie löschen?' : 'Schicht löschen?'),
        content: Text(
          series
              ? 'Alle Schichten dieser Serie werden entfernt. Das kann nicht rückgängig gemacht werden.'
              : 'Diese Schicht wird entfernt. Das kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _deleteShift(BuildContext context, Shift shift) async {
    if (shift.id == null) {
      return;
    }
    if (!await _confirmShiftDeletion(context, series: false)) {
      return;
    }
    if (!context.mounted) return;
    try {
      await context.read<ScheduleProvider>().deleteShift(shift.id!);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _deleteShiftSeries(BuildContext context, String seriesId) async {
    if (!await _confirmShiftDeletion(context, series: true)) {
      return;
    }
    if (!context.mounted) return;
    try {
      await context.read<ScheduleProvider>().deleteShiftSeries(seriesId);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _showDayNotes(BuildContext context, DateTime day) async {
    final dayAbsences = _dayAbsences(day);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(DateFormat('EEEE, dd.MM.yyyy', 'de_DE').format(day)),
        content: dayAbsences.isEmpty
            ? const Text(
                'Keine Anmerkungen oder Abwesenheiten fuer diesen Tag.')
            : SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final absence in dayAbsences)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PlannerAbsencePill(
                          absence: absence,
                          showEmployeeName: true,
                        ),
                      ),
                  ],
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Schliessen'),
          ),
        ],
      ),
    );
  }

  void _clearAllFilters() {
    final schedule = context.read<ScheduleProvider>();
    schedule.setTeamFilter(null);
    schedule.setSelectedUserId(null);
    schedule.setStatusFilter(null);
    setState(() {
      _selectedLocation = null;
      _selectedFunction = null;
      _selectedAbsenceFilter = _PlannerAbsenceFilter.all;
      _layoutMode = _PlannerLayoutMode.employee;
      _selectedMonthEmployeeIds = {};
      _selectedMonthLocations = {};
    });
  }

  Widget _controlPill(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 18),
        ],
      ),
    );
  }

  Widget _filterPill(
    BuildContext context, {
    required String label,
    required int activeCount,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (activeCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$activeCount',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 18),
        ],
      ),
    );
  }

  Widget _outlineActionButton(BuildContext context, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _navIconButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: ConstrainedBox(
        // Mind. 48dp Tap-Ziel (vorher ~36dp).
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }


  int _dayAbsenceCount(DateTime day) {
    return _dayAbsences(day).length;
  }

  String _absenceFilterLabel(_PlannerAbsenceFilter filter) {
    return switch (filter) {
      _PlannerAbsenceFilter.all => 'Alle',
      _PlannerAbsenceFilter.vacation => 'Urlaub',
      _PlannerAbsenceFilter.sickness => 'Krank',
      _PlannerAbsenceFilter.unavailable => 'Nicht verfuegbar',
    };
  }

  AbsenceType? _absenceFilterType(_PlannerAbsenceFilter filter) {
    return switch (filter) {
      _PlannerAbsenceFilter.all => null,
      _PlannerAbsenceFilter.vacation => AbsenceType.vacation,
      _PlannerAbsenceFilter.sickness => AbsenceType.sickness,
      _PlannerAbsenceFilter.unavailable => AbsenceType.unavailable,
    };
  }

  bool _matchesAbsenceFilters(
    AbsenceRequest request,
    ScheduleProvider schedule,
  ) {
    final filterType = _absenceFilterType(_selectedAbsenceFilter);
    if (filterType != null && request.type != filterType) {
      return false;
    }
    if (schedule.viewMode == ScheduleViewMode.month &&
        _selectedMonthEmployeeIds.isNotEmpty &&
        !_selectedMonthEmployeeIds.contains(request.userId)) {
      return false;
    }
    return true;
  }

  List<AbsenceRequest> _filteredAbsenceRequests(ScheduleProvider schedule) {
    return widget.visibleAbsenceRequests
        .where((request) => _matchesAbsenceFilters(request, schedule))
        .toList(growable: false)
      ..sort(_plannerAbsenceRequestSort);
  }

  List<AbsenceRequest> _dayAbsences(DateTime day) {
    final schedule = context.read<ScheduleProvider>();
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return widget.visibleAbsenceRequests
        .where(
          (request) =>
              _matchesAbsenceFilters(request, schedule) &&
              request.overlaps(dayStart, dayEnd),
        )
        .toList(growable: false)
      ..sort(_plannerAbsenceRequestSort);
  }

  List<AbsenceRequest> _rowAbsencesForDay(
    _PlannerBoardRowData row,
    DateTime day,
  ) {
    final memberId = row.memberId;
    if (memberId == null) {
      return const <AbsenceRequest>[];
    }
    return _dayAbsences(day)
        .where((request) => request.userId == memberId)
        .toList(growable: false);
  }


  String _toolbarRangeLabel(DateTime date, ScheduleViewMode mode) {
    switch (mode) {
      case ScheduleViewMode.day:
        return DateFormat('dd. MMM yyyy', 'de_DE').format(date);
      case ScheduleViewMode.week:
        final start = date.subtract(Duration(days: date.weekday - 1));
        final end = start.add(const Duration(days: 6));
        return '${DateFormat('dd. MMM', 'de_DE').format(start)} - ${DateFormat('dd. MMM yyyy', 'de_DE').format(end)}';
      case ScheduleViewMode.month:
        return DateFormat('MMMM yyyy', 'de_DE').format(date);
    }
  }
}


class _PlannerMonthWeekHeaderCell extends StatelessWidget {
  const _PlannerMonthWeekHeaderCell({
    required this.width,
    required this.height,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant),
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Text(
        'KW',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _PlannerMonthWeekdayHeaderCell extends StatelessWidget {
  const _PlannerMonthWeekdayHeaderCell({
    required this.height,
    required this.day,
  });

  final double height;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isWeekend = day.weekday >= DateTime.saturday;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: isWeekend
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerLowest,
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant),
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Text(
        DateFormat('EEE', 'de_DE').format(day).toUpperCase(),
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurfaceVariant,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _PlannerMonthWeekNumberCell extends StatelessWidget {
  const _PlannerMonthWeekNumberCell({
    required this.width,
    required this.height,
    required this.weekNumber,
  });

  final double width;
  final double height;
  final int weekNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: width,
      height: height,
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant),
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Text(
        '$weekNumber',
        style: theme.textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PlannerCompactMonthWeekdayHeaderCell extends StatelessWidget {
  const _PlannerCompactMonthWeekdayHeaderCell({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant),
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PlannerCompactMonthDayCell extends StatelessWidget {
  const _PlannerCompactMonthDayCell({
    required this.height,
    required this.day,
    required this.visibleMonth,
    required this.visibleYear,
    required this.shifts,
    required this.absenceCount,
    required this.onTapDay,
    required this.onOpenShift,
  });

  final double height;
  final DateTime day;
  final int visibleMonth;
  final int visibleYear;
  final List<Shift> shifts;
  final int absenceCount;
  final VoidCallback onTapDay;
  final ValueChanged<Shift> onOpenShift;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isInVisibleMonth =
        day.month == visibleMonth && day.year == visibleYear;
    final isToday = isSameDay(day, DateTime.now());
    final isWeekend = day.weekday >= DateTime.saturday;
    final backgroundColor = !isInVisibleMonth
        ? colorScheme.surfaceContainerLow
        : (isWeekend
            ? colorScheme.surfaceContainerLowest
            : colorScheme.surface);

    return Material(
      color: backgroundColor,
      child: InkWell(
        onTap: onTapDay,
        child: Container(
          height: height,
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: colorScheme.outlineVariant),
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: isToday
                        ? const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          )
                        : EdgeInsets.zero,
                    decoration: isToday
                        ? BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(999),
                          )
                        : null,
                    child: Text(
                      '${day.day}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: isToday
                            ? colorScheme.onPrimary
                            : (isInVisibleMonth
                                ? colorScheme.onSurface
                                : colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.62)),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (absenceCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$absenceCount',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: shifts.isEmpty
                    ? const SizedBox.shrink()
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          // Höhenbudget der kompakten Zelle respektieren, sonst
                          // läuft die innere Column über (RenderFlex-Overflow).
                          const tileExtent = 20.0;
                          const tileSpacing = 4.0;
                          const moreHintExtent = 18.0;
                          final shownCount = monthCellVisibleShiftCount(
                            available: constraints.maxHeight,
                            total: shifts.length,
                            tileExtent: tileExtent,
                            tileSpacing: tileSpacing,
                            moreHintExtent: moreHintExtent,
                          );
                          final shown =
                              shifts.take(shownCount).toList(growable: false);
                          final hidden = shifts.length - shown.length;
                          return ClipRect(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var index = 0;
                                    index < shown.length;
                                    index++) ...[
                                  SizedBox(
                                    height: tileExtent,
                                    child: _PlannerCompactMonthShiftTile(
                                      shift: shown[index],
                                      onTap: () => onOpenShift(shown[index]),
                                    ),
                                  ),
                                  if (index < shown.length - 1)
                                    const SizedBox(height: tileSpacing),
                                ],
                                if (hidden > 0) ...[
                                  if (shown.isNotEmpty)
                                    const SizedBox(height: tileSpacing),
                                  Text(
                                    '+$hidden mehr',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlannerMonthDayCell extends StatelessWidget {
  const _PlannerMonthDayCell({
    required this.height,
    required this.day,
    required this.visibleMonth,
    required this.visibleYear,
    required this.shifts,
    required this.absenceCount,
    required this.onAddShift,
    required this.onShowAbsences,
    required this.onOpenShift,
    required this.onDeleteShift,
    required this.onDeleteSeries,
    required this.onShowMore,
  });

  final double height;
  final DateTime day;
  final int visibleMonth;
  final int visibleYear;
  final List<Shift> shifts;
  final int absenceCount;
  final VoidCallback onAddShift;
  final VoidCallback onShowAbsences;
  final ValueChanged<Shift> onOpenShift;
  final ValueChanged<Shift> onDeleteShift;
  final ValueChanged<String> onDeleteSeries;
  final VoidCallback onShowMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isInVisibleMonth =
        day.month == visibleMonth && day.year == visibleYear;
    final isToday = isSameDay(day, DateTime.now());
    final isWeekend = day.weekday >= DateTime.saturday;
    final totalHours =
        shifts.fold<double>(0, (sum, shift) => sum + shift.workedHours);
    final dayLabel = day.day == 1 || !isInVisibleMonth
        ? DateFormat('d. MMM', 'de_DE').format(day)
        : '${day.day}';

    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 8),
      decoration: BoxDecoration(
        color: !isInVisibleMonth
            ? colorScheme.surfaceContainerLow
            : (isWeekend
                ? colorScheme.surfaceContainerLowest
                : colorScheme.surface),
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant),
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: isToday
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      dayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: isToday
                            ? colorScheme.onPrimary
                            : (isInVisibleMonth
                                ? colorScheme.onSurface
                                : colorScheme.onSurfaceVariant),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              if (absenceCount > 0)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6, right: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: onShowAbsences,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$absenceCount Abw.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (absenceCount == 0) const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onAddShift,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Icon(
                    Icons.add,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: shifts.isEmpty
                ? const SizedBox.shrink()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // Nur so viele Schicht-Kacheln rendern, wie in die feste
                      // Zellenhöhe passen — sonst läuft die innere Column über
                      // (RenderFlex-Overflow). Der Rest erscheint als
                      // „+N weitere"-Hinweis. ClipRect ist die Sicherung gegen
                      // verbleibende Sub-Pixel-Rundung.
                      const tileExtent = 30.0;
                      const tileSpacing = 5.0;
                      const moreHintExtent = 26.0;
                      final shownCount = monthCellVisibleShiftCount(
                        available: constraints.maxHeight,
                        total: shifts.length,
                        tileExtent: tileExtent,
                        tileSpacing: tileSpacing,
                        moreHintExtent: moreHintExtent,
                      );
                      final shown =
                          shifts.take(shownCount).toList(growable: false);
                      final hidden = shifts.length - shown.length;
                      return ClipRect(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var index = 0;
                                index < shown.length;
                                index++) ...[
                              SizedBox(
                                height: tileExtent,
                                child: _PlannerMonthShiftTile(
                                  shift: shown[index],
                                  onTap: () => onOpenShift(shown[index]),
                                  onDelete: () => onDeleteShift(shown[index]),
                                  onDeleteSeries: shown[index].seriesId == null
                                      ? null
                                      : () => onDeleteSeries(
                                            shown[index].seriesId!,
                                          ),
                                ),
                              ),
                              if (index < shown.length - 1)
                                const SizedBox(height: tileSpacing),
                            ],
                            if (hidden > 0) ...[
                              if (shown.isNotEmpty)
                                const SizedBox(height: tileSpacing),
                              InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: onShowMore,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  child: Text(
                                    '+$hidden weitere',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Row(
            children: [
              if (shifts.isNotEmpty)
                Text(
                  '${totalHours.toStringAsFixed(0)}h',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (shifts.isNotEmpty && absenceCount > 0)
                const SizedBox(width: 8),
              if (shifts.isEmpty && absenceCount > 0)
                Flexible(
                  child: Text(
                    'Abwesenheiten vorhanden',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlannerCompactMonthShiftTile extends StatelessWidget {
  const _PlannerCompactMonthShiftTile({
    required this.shift,
    required this.onTap,
  });

  final Shift shift;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final baseColor = _resolveShiftColor(shift, theme);
    final background = _softenColor(
      baseColor,
      colorScheme.surfaceContainerLowest,
      0.9,
    );
    final label = shift.isUnassigned ? 'Frei · ${shift.title}' : shift.title;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: baseColor.withValues(alpha: 0.14),
            ),
          ),
          child: Text(
            '${DateFormat('HH:mm', 'de_DE').format(shift.startTime)} $label',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: baseColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlannerMonthShiftTile extends StatelessWidget {
  const _PlannerMonthShiftTile({
    required this.shift,
    required this.onTap,
    required this.onDelete,
    this.onDeleteSeries,
  });

  final Shift shift;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onDeleteSeries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final baseColor = _resolveShiftColor(shift, theme);
    final background = _softenColor(
      baseColor,
      colorScheme.surfaceContainerLowest,
      0.86,
    );
    final label = shift.isUnassigned
        ? 'Frei · ${shift.title}'
        : '${shift.employeeName} · ${shift.title}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 3, 2, 3),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: baseColor.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${DateFormat('HH:mm', 'de_DE').format(shift.startTime)} $label',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: baseColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      onTap();
                    case 'delete':
                      onDelete();
                    case 'delete_series':
                      onDeleteSeries?.call();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Bearbeiten'),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Einzeln löschen'),
                  ),
                  if (onDeleteSeries != null)
                    const PopupMenuItem(
                      value: 'delete_series',
                      child: Text('Serie löschen'),
                    ),
                ],
                child: Icon(
                  Icons.more_horiz,
                  size: 16,
                  color: baseColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _ShiftCard extends StatelessWidget {
  const _ShiftCard({
    required this.shift,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
    this.onDeleteSeries,
  });

  final Shift shift;
  final bool isAdmin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onDeleteSeries;

  @override
  Widget build(BuildContext context) {
    final startFmt = DateFormat('EEE, dd.MM. HH:mm', 'de_DE');
    final endFmt = DateFormat('HH:mm', 'de_DE');
    final borderColor = tryParseHexColor(shift.color);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: borderColor != null
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: borderColor, width: 0.5),
            )
          : null,
      child: Container(
        decoration: borderColor != null
            ? BoxDecoration(
                border: Border(
                  left: BorderSide(color: borderColor, width: 5),
                ),
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          title: Text(shift.title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${shift.employeeName} · ${startFmt.format(shift.startTime)} - ${endFmt.format(shift.endTime)}'
                '${shift.team == null || shift.team!.isEmpty ? '' : '\nTeam: ${shift.team}'}'
                '${shift.effectiveSiteLabel == null || shift.effectiveSiteLabel!.isEmpty ? '' : '\nStandort: ${shift.effectiveSiteLabel}'}'
                '${shift.notes == null || shift.notes!.isEmpty ? '' : '\n${shift.notes}'}',
              ),
              if (!isAdmin && shift.id != null)
                Builder(
                  builder: (context) {
                    // Läuft für diese Schicht bereits eine (neue) Tauschanfrage?
                    final openRequest = context
                        .watch<ScheduleProvider>()
                        .swapRequests
                        .firstWhereOrNull(
                          (request) =>
                              request.requesterShiftId == shift.id &&
                              !request.status.isClosed,
                        );
                    if (openRequest != null) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Tauschanfrage: ${openRequest.status.label}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.tertiary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TextButton.icon(
                        onPressed: () => showSwapRequestSheet(context, shift),
                        icon: const Icon(Icons.swap_horiz, size: 18),
                        label: const Text('Tausch anfragen'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    );
                  },
                ),
              if (isAdmin && shift.swapStatus == 'pending')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Tauschanfrage: '),
                      IconButton(
                        tooltip: 'Tausch genehmigen',
                        icon: Icon(Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20),
                        onPressed: () async {
                          if (shift.id == null) return;
                          try {
                            await context
                                .read<ScheduleProvider>()
                                .reviewShiftSwap(
                                  shiftId: shift.id!,
                                  approved: true,
                                );
                          } catch (error) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Fehler: $error'),
                                backgroundColor:
                                    Theme.of(context).colorScheme.error,
                              ),
                            );
                          }
                        },
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Tausch ablehnen',
                        icon: Icon(Icons.cancel,
                            color: Theme.of(context).colorScheme.error,
                            size: 20),
                        onPressed: () async {
                          if (shift.id == null) return;
                          try {
                            await context
                                .read<ScheduleProvider>()
                                .reviewShiftSwap(
                                  shiftId: shift.id!,
                                  approved: false,
                                );
                          } catch (error) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Fehler: $error'),
                                backgroundColor:
                                    Theme.of(context).colorScheme.error,
                              ),
                            );
                          }
                        },
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          isThreeLine: true,
          leading: CircleAvatar(
            child: Text(
              shift.employeeName.trim().isEmpty
                  ? '?'
                  : shift.employeeName.trim().characters.first.toUpperCase(),
            ),
          ),
          trailing: isAdmin
              ? PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        onEdit();
                      case 'delete':
                        onDelete();
                      case 'delete_series':
                        onDeleteSeries?.call();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Bearbeiten'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Einzeln löschen'),
                    ),
                    if (onDeleteSeries != null)
                      const PopupMenuItem(
                        value: 'delete_series',
                        child: Text('Serie löschen'),
                      ),
                  ],
                )
              : Text(shift.status.label),
        ),
      ),
    );
  }
}

class _AbsenceCard extends StatelessWidget {
  const _AbsenceCard({
    required this.request,
    required this.canReviewRequest,
    required this.canManageApprovedVacation,
  });

  final AbsenceRequest request;
  final bool canReviewRequest;
  final bool canManageApprovedVacation;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd.MM.yyyy', 'de_DE');
    final colorScheme = Theme.of(context).colorScheme;
    final provider = context.read<ScheduleProvider>();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: colorScheme.tertiaryContainer,
          child: Icon(
            Icons.event_busy_outlined,
            color: colorScheme.onTertiaryContainer,
          ),
        ),
        title: Text('${request.employeeName} · ${request.type.label}'),
        subtitle: Text(
          '${dateFmt.format(request.startDate)} - ${dateFmt.format(request.endDate)}'
          '${request.note == null || request.note!.isEmpty ? '' : '\n${request.note}'}',
        ),
        trailing: canReviewRequest && request.status == AbsenceStatus.pending
            ? Wrap(
                spacing: 8,
                children: [
                  IconButton(
                    tooltip: 'Genehmigen',
                    onPressed: () async {
                      try {
                        await provider.reviewAbsenceRequest(
                          requestId: request.id!,
                          status: AbsenceStatus.approved,
                        );
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Fehler: $error'),
                            backgroundColor:
                                Theme.of(context).colorScheme.error,
                          ),
                        );
                      }
                    },
                    icon: Icon(Icons.check_circle, color: colorScheme.primary),
                  ),
                  IconButton(
                    tooltip: 'Ablehnen',
                    onPressed: () async {
                      try {
                        await provider.reviewAbsenceRequest(
                          requestId: request.id!,
                          status: AbsenceStatus.rejected,
                        );
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Fehler: $error'),
                            backgroundColor:
                                Theme.of(context).colorScheme.error,
                          ),
                        );
                      }
                    },
                    icon: Icon(Icons.cancel, color: colorScheme.error),
                  ),
                ],
              )
            : canManageApprovedVacation
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(request.status.label),
                      PopupMenuButton<String>(
                        tooltip: 'Urlaub bearbeiten',
                        onSelected: (value) async {
                          if (value == 'edit') {
                            await showAbsenceRequestSheet(
                              context,
                              defaultType: request.type,
                              initialRequest: request,
                            );
                            return;
                          }
                          if (value != 'delete') {
                            return;
                          }
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Urlaub löschen'),
                              content: const Text(
                                'Möchtest du diesen genehmigten Urlaub wirklich löschen?',
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
                                  child: const Text('Löschen'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true) {
                            return;
                          }
                          try {
                            await provider.deleteAbsenceRequest(request.id!);
                          } catch (error) {
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Fehler: $error'),
                                backgroundColor:
                                    Theme.of(context).colorScheme.error,
                              ),
                            );
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Bearbeiten'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Löschen'),
                          ),
                        ],
                        child: const Icon(Icons.more_horiz),
                      ),
                    ],
                  )
                : Text(request.status.label),
      ),
    );
  }
}

/// Abschnitts-Trenner im Schichtplan-Board (extrahiert aus _buildSectionLabel,
/// build-helper-methods-to-widget-classes).
class _PlannerSectionLabel extends StatelessWidget {
  const _PlannerSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.outlineVariant;
    final accentColor = Theme.of(context).appColors.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: borderColor),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accentColor,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

/// Leerzustand der planmaessigen Board-Zeilen (extrahiert aus
/// _buildEmptyPlannedState; eigenes Layout, daher kein Reuse von
/// _PlannerEmptyState).
class _PlannerEmptyBoardState extends StatelessWidget {
  const _PlannerEmptyBoardState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Row(
        children: [
          Icon(
            Icons.event_busy_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Text(
            'Keine Schichten fuer die aktuelle Auswahl.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Runder Plus-Button in einer Board-Tageszelle (extrahiert aus
/// _quickAddButton).
class _PlannerQuickAddButton extends StatelessWidget {
  const _PlannerQuickAddButton({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 48x48-Trefferfläche (Material-Mindestmaß) mit gut sichtbarem 40px-Kreis.
    return Tooltip(
      message: 'Schicht hinzufuegen',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.28),
                ),
              ),
              child: Icon(
                Icons.add_rounded,
                size: 24,
                color: colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Einzelner Tag im Mini-Monatskalender der Planer-Sidebar
/// (extrahiert aus build-helper-methods-to-widget-classes).
class _PlannerMiniCalendarDay extends StatelessWidget {
  const _PlannerMiniCalendarDay({
    required this.day,
    required this.visibleDate,
    required this.onTap,
  });

  final DateTime day;
  final DateTime visibleDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isInMonth =
        day.month == visibleDate.month && day.year == visibleDate.year;
    final isToday = isSameDay(day, DateTime.now());

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isToday ? colorScheme.primary : null,
          shape: BoxShape.circle,
        ),
        child: Text(
          '${day.day}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: isToday
                ? colorScheme.onPrimary
                : (isInMonth
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Kompakte Checkbox-Zeile der Planer-Sidebar (Mitarbeiter-/Standortfilter)
/// (extrahiert aus build-helper-methods-to-widget-classes).
class _PlannerSidebarCheckbox extends StatelessWidget {
  const _PlannerSidebarCheckbox({
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: selected,
                onChanged: (value) => onChanged(value ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: selected
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlannerEmptyState extends StatelessWidget {
  const _PlannerEmptyState({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.75);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(icon, size: 40, color: muted),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: muted)),
        ],
      ),
    );
  }
}


String _formatBreakMinutes(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(1).replaceFirst('.', ',');
}

String _formatShiftTemplateSummary(
  BuildContext context,
  ShiftTemplate template,
) {
  final timeRange =
      '${_formatTimeOfDay(context, _timeOfDayFromMinutes(template.startMinutes))} - '
      '${_formatTimeOfDay(context, _timeOfDayFromMinutes(template.endMinutes))}';
  final parts = <String>[
    template.title,
    timeRange,
    'Pause: ${_formatBreakMinutes(template.breakMinutes)} min',
    if (template.siteName?.trim().isNotEmpty == true) template.siteName!.trim(),
    if (template.teamName?.trim().isNotEmpty == true) template.teamName!.trim(),
  ];
  final qualifications = template.requiredQualificationIds.isEmpty
      ? ''
      : '\n${template.requiredQualificationIds.length} Qualifikation${template.requiredQualificationIds.length == 1 ? '' : 'en'} erforderlich';
  final noteText = template.notes?.trim().isNotEmpty == true
      ? '\n${template.notes!.trim()}'
      : '';
  return '${parts.join(' · ')}$qualifications$noteText';
}

TimeOfDay _timeOfDayFromMinutes(int minutes) {
  final normalized = minutes.clamp(0, 1439);
  return TimeOfDay(
    hour: normalized ~/ 60,
    minute: normalized % 60,
  );
}

int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

String _formatTimeOfDay(BuildContext context, TimeOfDay time) {
  return MaterialLocalizations.of(context).formatTimeOfDay(
    time,
    alwaysUse24HourFormat: true,
  );
}

class _ShiftConflictList extends StatelessWidget {
  const _ShiftConflictList({
    required this.issues,
    this.textColor,
  });

  final List<ShiftConflictIssue> issues;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = textColor ?? Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < issues.length; i++) ...[
          Text(
            _formatShiftConflictTitle(issues[i]),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: effectiveColor,
                ),
          ),
          const SizedBox(height: 6),
          for (final line in _buildConflictDetails(issues[i]))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '- $line',
                style: TextStyle(color: effectiveColor),
              ),
            ),
          if (i < issues.length - 1) ...[
            const SizedBox(height: 8),
            Divider(
              height: 1,
              color: effectiveColor.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

enum _EditorNoticeTone { info, warning }

enum _EditorBadgeTone { neutral, success, warning, error }

enum _AvailabilityReasonTone { blocking, warning }

class _EditorNoticeCard extends StatelessWidget {
  const _EditorNoticeCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String message;
  final _EditorNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final isInfo = tone == _EditorNoticeTone.info;
    final background =
        isInfo ? appColors.infoContainer : appColors.warningContainer;
    final foreground =
        isInfo ? appColors.onInfoContainer : appColors.onWarningContainer;
    final accent = isInfo ? appColors.info : appColors.warning;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foreground.withValues(alpha: 0.9),
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

class _EditorCountBadge extends StatelessWidget {
  const _EditorCountBadge({
    required this.label,
    this.tone = _EditorBadgeTone.neutral,
  });

  final String label;
  final _EditorBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;

    late final Color background;
    late final Color foreground;
    late final Color border;

    switch (tone) {
      case _EditorBadgeTone.neutral:
        background = colorScheme.surfaceContainerHighest.withValues(alpha: 0.8);
        foreground = colorScheme.onSurfaceVariant;
        border = colorScheme.outlineVariant.withValues(alpha: 0.85);
      case _EditorBadgeTone.success:
        background = appColors.successContainer.withValues(alpha: 0.88);
        foreground = appColors.onSuccessContainer;
        border = appColors.success.withValues(alpha: 0.2);
      case _EditorBadgeTone.warning:
        background = appColors.warningContainer.withValues(alpha: 0.88);
        foreground = appColors.onWarningContainer;
        border = appColors.warning.withValues(alpha: 0.2);
      case _EditorBadgeTone.error:
        background = colorScheme.errorContainer.withValues(alpha: 0.9);
        foreground = colorScheme.onErrorContainer;
        border = colorScheme.error.withValues(alpha: 0.24);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AvailabilityReason {
  const _AvailabilityReason({
    required this.message,
    required this.icon,
    required this.tone,
  });

  final String message;
  final IconData icon;
  final _AvailabilityReasonTone tone;
}

class _AbsenceEditorSheet extends StatefulWidget {
  const _AbsenceEditorSheet({required this.currentUser});

  final AppUserProfile currentUser;

  @override
  State<_AbsenceEditorSheet> createState() => _AbsenceEditorSheetState();
}

class _AbsenceEditorSheetState extends State<_AbsenceEditorSheet> {
  late DateTime _startDate;
  late DateTime _endDate;
  late final TextEditingController _noteCtrl;
  AbsenceType _type = AbsenceType.vacation;

  @override
  void initState() {
    super.initState();
    _startDate = DateTime.now();
    _endDate = DateTime.now();
    _noteCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Abwesenheit melden',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          _DateTile(
            label: 'Von',
            value: DateFormat('dd.MM.yyyy', 'de_DE').format(_startDate),
            icon: Icons.event_available_outlined,
            onTap: () => _pickDate(true),
          ),
          const SizedBox(height: 12),
          _DateTile(
            label: 'Bis',
            value: DateFormat('dd.MM.yyyy', 'de_DE').format(_endDate),
            icon: Icons.event_busy_outlined,
            onTap: () => _pickDate(false),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AbsenceType>(
            initialValue: _type,
            decoration: const InputDecoration(
              labelText: 'Art',
              prefixIcon: Icon(Icons.flag_outlined),
            ),
            items: [
              for (final type in AbsenceType.values)
                DropdownMenuItem(
                  value: type,
                  child: Text(type.label),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _type = value);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notiz',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.send),
            label: const Text('Abwesenheit senden'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('de', 'DE'),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  void _save() {
    if (_endDate.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Das Enddatum muss nach dem Startdatum liegen.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      AbsenceRequest(
        orgId: widget.currentUser.orgId,
        userId: widget.currentUser.uid,
        employeeName: widget.currentUser.displayName,
        startDate: _startDate,
        endDate: _endDate,
        type: _type,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(value),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

String _formatShiftConflictTitle(ShiftConflictIssue issue) {
  final startFmt = DateFormat('dd.MM.yyyy HH:mm', 'de_DE');
  final endFmt = DateFormat('HH:mm', 'de_DE');
  final locationLabel =
      issue.shift.effectiveSiteLabel?.trim().isNotEmpty == true
          ? ' · ${issue.shift.effectiveSiteLabel}'
          : '';
  return '${issue.shift.employeeName} · ${issue.shift.title}$locationLabel · '
      '${startFmt.format(issue.shift.startTime)} - ${endFmt.format(issue.shift.endTime)}';
}

List<String> _buildConflictDetails(ShiftConflictIssue issue) {
  final lines = <String>[];
  final dayFmt = DateFormat('dd.MM.yyyy', 'de_DE');
  final timeFmt = DateFormat('HH:mm', 'de_DE');

  for (final shift in issue.conflictingDraftShifts) {
    lines.add(
      'Ueberschneidung mit weiterer neuer Schicht "${shift.title}" '
      '(${shift.employeeName}, ${dayFmt.format(shift.startTime)} '
      '${timeFmt.format(shift.startTime)} - ${timeFmt.format(shift.endTime)}'
      '${_formatLocationSuffix(shift.effectiveSiteLabel)}).',
    );
  }

  for (final shift in issue.conflictingShifts) {
    lines.add(
      'Ueberschneidung mit bestehender Schicht "${shift.title}" '
      '(${shift.employeeName}, ${dayFmt.format(shift.startTime)} '
      '${timeFmt.format(shift.startTime)} - ${timeFmt.format(shift.endTime)}'
      '${_formatLocationSuffix(shift.effectiveSiteLabel)}).',
    );
  }

  for (final absence in issue.blockingAbsences) {
    lines.add(
      'Konflikt mit ${absence.type.label.toLowerCase()} '
      '(${dayFmt.format(absence.startDate)} - ${dayFmt.format(absence.endDate)}).',
    );
  }

  for (final violation in issue.violations) {
    final prefix = violation.severity == ComplianceSeverity.blocking
        ? 'Blockiert'
        : 'Warnung';
    lines.add('$prefix: ${violation.message}');
  }

  return lines;
}

List<_AvailabilityReason> _buildAssigneeAvailabilityReasons(
  ShiftAssigneeAvailability availability,
) {
  final reasons = <_AvailabilityReason>[];
  final dayFmt = DateFormat('dd.MM.yyyy', 'de_DE');
  final timeFmt = DateFormat('HH:mm', 'de_DE');

  for (final shift in availability.conflictingShifts) {
    reasons.add(
      _AvailabilityReason(
        icon: Icons.schedule_outlined,
        tone: _AvailabilityReasonTone.blocking,
        message: 'Bereits in Schicht "${shift.title}" eingeplant am '
            '${dayFmt.format(shift.startTime)} von '
            '${timeFmt.format(shift.startTime)} bis ${timeFmt.format(shift.endTime)}'
            '${_formatLocationSuffix(shift.effectiveSiteLabel)}.',
      ),
    );
  }

  for (final absence in availability.blockingAbsences) {
    reasons.add(
      _AvailabilityReason(
        icon: Icons.event_busy_outlined,
        tone: _AvailabilityReasonTone.blocking,
        message: '${absence.type.label} genehmigt: '
            '${dayFmt.format(absence.startDate)} - ${dayFmt.format(absence.endDate)}.',
      ),
    );
  }

  for (final violation in availability.violations) {
    reasons.add(
      _AvailabilityReason(
        icon: violation.severity == ComplianceSeverity.blocking
            ? Icons.gpp_bad_outlined
            : Icons.warning_amber_rounded,
        tone: violation.severity == ComplianceSeverity.blocking
            ? _AvailabilityReasonTone.blocking
            : _AvailabilityReasonTone.warning,
        message:
            '${violation.severity == ComplianceSeverity.blocking ? 'Blockiert' : 'Warnung'}: ${violation.message}',
      ),
    );
  }

  return reasons;
}

String _formatLocationSuffix(String? location) {
  final trimmed = location?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return '';
  }
  return ', Standort $trimmed';
}

String _initialsForName(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .toList(growable: false);
  if (parts.isEmpty) {
    return '?';
  }
  return parts.map((part) => part[0].toUpperCase()).join();
}

String _rangeLabel(DateTime date, ScheduleViewMode mode) {
  switch (mode) {
    case ScheduleViewMode.day:
      return DateFormat('EEEE, dd.MM.yyyy', 'de_DE').format(date);
    case ScheduleViewMode.week:
      final start = date.subtract(Duration(days: date.weekday - 1));
      final end = start.add(const Duration(days: 6));
      return '${DateFormat('dd.MM.', 'de_DE').format(start)} - ${DateFormat('dd.MM.yyyy', 'de_DE').format(end)}';
    case ScheduleViewMode.month:
      return DateFormat('MMMM yyyy', 'de_DE').format(date);
  }
}

DateTime _shiftVisibleDate(
  DateTime date,
  ScheduleViewMode mode,
  int direction,
) {
  switch (mode) {
    case ScheduleViewMode.day:
      return date.add(Duration(days: direction));
    case ScheduleViewMode.week:
      return date.add(Duration(days: 7 * direction));
    case ScheduleViewMode.month:
      final targetMonth = DateTime(date.year, date.month + direction, 1);
      final maxDay = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
      final clampedDay = date.day.clamp(1, maxDay);
      return DateTime(targetMonth.year, targetMonth.month, clampedDay);
  }
}

({DateTime start, DateTime end}) _currentScheduleRange(
  DateTime date,
  ScheduleViewMode mode,
) {
  switch (mode) {
    case ScheduleViewMode.day:
      final start = DateTime(date.year, date.month, date.day);
      return (start: start, end: start.add(const Duration(days: 1)));
    case ScheduleViewMode.week:
      final start = DateTime(
        date.year,
        date.month,
        date.day,
      ).subtract(Duration(days: date.weekday - 1));
      return (start: start, end: start.add(const Duration(days: 7)));
    case ScheduleViewMode.month:
      final start = DateTime(date.year, date.month, 1);
      return (start: start, end: DateTime(date.year, date.month + 1, 1));
  }
}

/// Vorschau-Sheet der automatischen Schichtverteilung: zeigt zu erstellende
/// Schichten, Zuweisungen, Warnungen und nicht zuweisbare Slots. Gibt `true`
/// zurück, wenn der Nutzer „Übernehmen & speichern" wählt.
class _AutoPlanPreviewSheet extends StatelessWidget {
  const _AutoPlanPreviewSheet({
    required this.generated,
    required this.existingOpen,
    required this.result,
    required this.enforceHourCapHard,
  });

  final List<Shift> generated;
  final List<Shift> existingOpen;
  final AutoAssignmentResult result;
  final bool enforceHourCapHard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final dateFmt = DateFormat('EEE dd.MM.', 'de_DE');
    final timeFmt = DateFormat('HH:mm', 'de_DE');

    final lookup = <String, Shift>{
      for (final shift in [...generated, ...existingOpen])
        if (shift.id != null) shift.id!: shift,
    };

    String slotLabel(String shiftId) {
      final shift = lookup[shiftId];
      if (shift == null) {
        return shiftId;
      }
      final site = shift.siteName?.trim().isNotEmpty == true
          ? shift.siteName!.trim()
          : 'Standort';
      return '${dateFmt.format(shift.startTime)} '
          '${timeFmt.format(shift.startTime)}–${timeFmt.format(shift.endTime)} · $site';
    }

    final generatedBySite = <String, int>{};
    for (final shift in generated) {
      final key = shift.siteName?.trim().isNotEmpty == true
          ? shift.siteName!.trim()
          : '—';
      generatedBySite[key] = (generatedBySite[key] ?? 0) + 1;
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Automatische Planung — Vorschau',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _AutoPlanStat(
                  label: '${generated.length} neu',
                  color: appColors.info,
                  icon: Icons.add_circle_outline,
                ),
                _AutoPlanStat(
                  label: '${result.assignments.length} besetzt',
                  color: appColors.success,
                  icon: Icons.person_add_alt,
                ),
                _AutoPlanStat(
                  label: '${result.unassigned.length} offen',
                  color: appColors.warning,
                  icon: Icons.help_outline,
                ),
                if (result.warnings.isNotEmpty)
                  _AutoPlanStat(
                    label: '${result.warnings.length} Warnungen',
                    color: appColors.warning,
                    icon: Icons.warning_amber_rounded,
                  ),
              ],
            ),
            if (!enforceHourCapHard) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: appColors.warningContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: appColors.onWarningContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Stundengrenzen sind weich — Überschreitungen sind erlaubt.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: appColors.onWarningContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (generatedBySite.isNotEmpty) ...[
              const SizedBox(height: 16),
              _AutoPlanSectionHeader(
                title: 'Neu zu erstellen',
                count: generated.length,
              ),
              for (final entry in generatedBySite.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('${entry.key}: ${entry.value} Schichten'),
                ),
            ],
            if (result.assignments.isNotEmpty) ...[
              const SizedBox(height: 16),
              _AutoPlanSectionHeader(
                title: 'Zuweisungen',
                count: result.assignments.length,
              ),
              for (final assignment in result.assignments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: slotLabel(assignment.shiftId)),
                          const TextSpan(text: '  →  '),
                          TextSpan(
                            text: assignment.userName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ]),
                      ),
                      Text(
                        assignment.reason,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (result.warnings.isNotEmpty) ...[
              const SizedBox(height: 16),
              _AutoPlanSectionHeader(
                title: 'Warnungen',
                count: result.warnings.length,
                color: appColors.warning,
              ),
              for (final warning in result.warnings)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 18, color: appColors.warning),
                      const SizedBox(width: 8),
                      Expanded(child: Text(warning.message)),
                    ],
                  ),
                ),
            ],
            if (result.unassigned.isNotEmpty) ...[
              const SizedBox(height: 16),
              _AutoPlanSectionHeader(
                title: 'Nicht zuweisbar',
                count: result.unassigned.length,
                color: appColors.warning,
              ),
              for (final item in result.unassigned)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(slotLabel(item.shiftId)),
                      Text(
                        item.message,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: appColors.warning),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Abbrechen'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.save),
                    label: const Text('Übernehmen & speichern'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoPlanStat extends StatelessWidget {
  const _AutoPlanStat({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AutoPlanSectionHeader extends StatelessWidget {
  const _AutoPlanSectionHeader({
    required this.title,
    required this.count,
    this.color,
  });

  final String title;
  final int count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        '$title ($count)',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
