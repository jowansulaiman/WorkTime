import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:collection/collection.dart';

import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/compliance_violation.dart';
import '../models/shift.dart';
import '../models/shift_template.dart';
import '../models/team_definition.dart';
import '../providers/auth_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/team_provider.dart';
import '../services/export_service.dart';
import '../theme/app_theme.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/responsive_layout.dart';
import 'notification_screen.dart';

enum ShiftPlanExportFormat { pdf, csv }

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
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: $error'),
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
      }

      if (!context.mounted) {
        return;
      }
      final label = switch (format) {
        ShiftPlanExportFormat.pdf => 'PDF',
        ShiftPlanExportFormat.csv => 'CSV',
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
      );
    } on ShiftConflictException catch (error) {
      if (!context.mounted) {
        return;
      }
      await _showShiftConflictDialog(context, error.issues);
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
    }
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

    await scheduleProvider.submitAbsenceRequest(result);
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
    final days = _rangeDays(range.start, range.end);
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
                                  _buildSectionLabel('FREIE SCHICHTEN'),
                                  _buildFreeShiftRow(
                                    context,
                                    days: days,
                                    shifts: freeShifts,
                                  ),
                                  _buildSectionLabel('PLANMÄSSIGE SCHICHTEN'),
                                  if (rows.isEmpty)
                                    _buildEmptyPlannedState(context)
                                  else
                                    for (final row in rows)
                                      _buildPlannedRow(
                                        context,
                                        row: row,
                                        days: days,
                                        shifts: plannedShifts,
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    _toolbarRangeLabel(
                      schedule.visibleDate,
                      schedule.viewMode,
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
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
                const Spacer(),
                if (schedule.viewMode != ScheduleViewMode.month) ...[
                  PopupMenuButton<_PlannerLayoutMode>(
                    onSelected: (value) => setState(() => _layoutMode = value),
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
                PopupMenuButton<String>(
                  onSelected: (value) =>
                      _handleToolbarActionSelection(context, value),
                  itemBuilder: (context) => _buildPlannerActionMenuItems(),
                  child: _outlineActionButton(context, 'AKTIONEN'),
                ),
                const SizedBox(width: 10),
                PopupMenuButton<String>(
                  onSelected: (value) =>
                      _handleToolbarActionSelection(context, value),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'publish_changes',
                      child: Text(
                        'Veroeffentlichen und Benachrichtigungen bei Aenderungen',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'publish_all',
                      child: Text('Veroeffentlichen und alle benachrichtigen'),
                    ),
                    PopupMenuItem(
                      value: 'publish_silent',
                      child: Text(
                        'Veroeffentlichen und niemanden benachrichtigen',
                      ),
                    ),
                  ],
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
                          color: appColors.success.withValues(alpha: 0.24),
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
          value: 'publish_changes',
          child: Text('Veroeffentlichen und Aenderungen melden'),
        ),
        const PopupMenuItem(
          value: 'publish_all',
          child: Text('Veroeffentlichen und alle benachrichtigen'),
        ),
        const PopupMenuItem(
          value: 'publish_silent',
          child: Text('Veroeffentlichen ohne Benachrichtigung'),
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
      case 'publish_changes':
        await _publishVisibleShifts(
          context,
          shifts,
          modeLabel: 'mit Aenderungsbenachrichtigung',
        );
      case 'publish_all':
        await _publishVisibleShifts(
          context,
          shifts,
          modeLabel: 'mit Benachrichtigung an alle',
        );
      case 'publish_silent':
        await _publishVisibleShifts(
          context,
          shifts,
          modeLabel: 'ohne Benachrichtigung',
        );
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
                      _buildSidebarCheckbox(
                        context,
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
                        _buildSidebarCheckbox(
                          context,
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
    final miniDays = _calendarMonthGridDays(visibleDate);
    final miniWeeks = _chunkDays(miniDays, 7);

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
                        child: _buildMiniCalendarDay(
                          context,
                          day: day,
                          visibleDate: visibleDate,
                          schedule: schedule,
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
                _buildSidebarCheckbox(
                  context,
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
                _buildSidebarCheckbox(
                  context,
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

  Widget _buildMiniCalendarDay(
    BuildContext context, {
    required DateTime day,
    required DateTime visibleDate,
    required ScheduleProvider schedule,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isInMonth =
        day.month == visibleDate.month && day.year == visibleDate.year;
    final isToday = isSameDay(day, DateTime.now());

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        schedule.setVisibleDate(day);
        schedule.setViewMode(ScheduleViewMode.day);
      },
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

  Widget _buildSidebarCheckbox(
    BuildContext context, {
    required String label,
    required bool selected,
    required ValueChanged<bool> onChanged,
  }) {
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

  Widget _buildMonthBoard(
    BuildContext context, {
    required DateTime visibleDate,
    required List<Shift> shifts,
    required bool isCompact,
  }) {
    final theme = Theme.of(context);
    final monthDays = _calendarMonthGridDays(visibleDate);
    final weekChunks = _chunkDays(monthDays, 7);
    final daysByKey = {
      for (final day in monthDays) _dayKey(day): day,
    };
    final shiftsByDay = <int, List<Shift>>{};
    for (final shift in shifts) {
      final day = DateTime(
        shift.startTime.year,
        shift.startTime.month,
        shift.startTime.day,
      );
      final key = _dayKey(day);
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
                    : 170.0;

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
                        weekNumber: _isoWeekNumber(weekChunks[weekIndex].first),
                      ),
                      for (final day in weekChunks[weekIndex])
                        Expanded(
                          child: _PlannerMonthDayCell(
                            height: dayCellHeight,
                            day: day,
                            visibleMonth: visibleDate.month,
                            visibleYear: visibleDate.year,
                            shifts: shiftsByDay[_dayKey(day)] ?? const [],
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
                              shiftsByDay[_dayKey(day)] ?? const [],
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
                          shifts: shiftsByDay[_dayKey(day)] ?? const [],
                          absenceCount: _dayAbsenceCount(day),
                          onTapDay: () => _showMonthDayDetails(
                            context,
                            day,
                            shiftsByDay[_dayKey(day)] ?? const [],
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

  Widget _buildEmptyPlannedState(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 28,
        horizontal: 16,
      ),
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

  Widget _buildSectionLabel(String label) {
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

  Widget _buildFreeShiftRow(
    BuildContext context, {
    required List<DateTime> days,
    required List<Shift> shifts,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rowLabelCell(
          context,
          title: 'Offene Slots',
          subtitle: shifts.isEmpty
              ? 'Noch keine freie Schicht'
              : '${shifts.length} offen',
        ),
        for (final day in days)
          _buildDayCell(
            context,
            day: day,
            shifts: shifts
                .where((shift) => isSameDay(shift.startTime, day))
                .toList(),
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
    required List<Shift> shifts,
    List<DateTime>? summaryDays,
  }) {
    final rowShifts = shifts
        .where((shift) => row.matches(shift))
        .toList(growable: false)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
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
            shifts: rowShifts
                .where((shift) => isSameDay(shift.startTime, day))
                .toList(),
            onAdd: () => widget.onOpenShiftEditor(
              initialDate: day,
              initialUserIds: row.memberId == null ? null : {row.memberId!},
              initialLocation: row.location,
            ),
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
  }) {
    final theme = Theme.of(context);
    final footerLabels = <String>[
      if (shifts.isNotEmpty)
        '${shifts.fold<double>(0, (sum, shift) => sum + shift.workedHours).toStringAsFixed(0)}h',
      if (absences.isNotEmpty)
        absences.length == 1 ? '1 Abw.' : '${absences.length} Abw.',
    ];
    return Container(
      width: _dayWidth,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
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
                child: _quickAddButton(context: context, onTap: onAdd),
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
                child: _PlannerBoardShiftCard(
                  shift: shift,
                  sameBucketCount: shifts
                      .where((entry) => entry.title == shift.title)
                      .length,
                  onTap: () => widget.onOpenShiftEditor(shift: shift),
                  onDelete: () => _deleteShift(context, shift),
                  onDeleteSeries: shift.seriesId == null
                      ? null
                      : () => _deleteShiftSeries(context, shift.seriesId!),
                ),
              ),
            Align(
              alignment: Alignment.center,
              child: _quickAddButton(context: context, onTap: onAdd),
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

  List<List<DateTime>> _chunkDays(List<DateTime> days, int size) {
    final chunks = <List<DateTime>>[];
    for (var index = 0; index < days.length; index += size) {
      final end = (index + size < days.length) ? index + size : days.length;
      chunks.add(days.sublist(index, end));
    }
    return chunks;
  }

  List<DateTime> _calendarMonthGridDays(DateTime visibleDate) {
    final firstOfMonth = DateTime(visibleDate.year, visibleDate.month, 1);
    final leadingDays = firstOfMonth.weekday - DateTime.monday;
    final gridStart = firstOfMonth.subtract(Duration(days: leadingDays));
    final lastOfMonth = DateTime(visibleDate.year, visibleDate.month + 1, 0);
    final trailingDays = DateTime.daysPerWeek - lastOfMonth.weekday;
    final gridEndExclusive = DateTime(
      lastOfMonth.year,
      lastOfMonth.month,
      lastOfMonth.day + 1,
    ).add(Duration(days: trailingDays));
    return _rangeDays(gridStart, gridEndExclusive);
  }

  int _dayKey(DateTime day) => day.year * 10000 + day.month * 100 + day.day;

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
    List<Shift> shifts, {
    required String modeLabel,
  }) async {
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
    await context.read<ScheduleProvider>().publishShifts(publishable);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Schichtplan fuer ${publishable.length} Schichten veroeffentlicht ($modeLabel).',
        ),
      ),
    );
  }

  Future<void> _deleteShift(BuildContext context, Shift shift) async {
    if (shift.id == null) {
      return;
    }
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
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _quickAddButton({
    required BuildContext context,
    required Future<void> Function() onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
        ),
        child: Icon(
          Icons.add,
          size: 18,
          color: colorScheme.primary,
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

  List<DateTime> _rangeDays(DateTime start, DateTime end) {
    final days = <DateTime>[];
    var cursor = start;
    while (cursor.isBefore(end)) {
      days.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
    return days;
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

class _PlannerBoardRowData {
  const _PlannerBoardRowData({
    required this.id,
    required this.title,
    required this.avatarLabel,
    this.memberId,
    this.location,
    this.subtitle,
    this.dailyHours = 8,
  });

  factory _PlannerBoardRowData.employee(AppUserProfile member) {
    final title = member.displayName;
    return _PlannerBoardRowData(
      id: member.uid,
      title: title,
      memberId: member.uid,
      avatarLabel: title.characters.take(1).toString().toUpperCase(),
      dailyHours: member.settings.dailyHours,
      subtitle: member.role.label,
    );
  }

  factory _PlannerBoardRowData.fallbackEmployee({
    required String userId,
    required String employeeName,
  }) {
    final title = employeeName.trim().isEmpty ? 'Unbekannt' : employeeName;
    return _PlannerBoardRowData(
      id: userId,
      title: title,
      memberId: userId,
      avatarLabel: title.characters.take(1).toString().toUpperCase(),
    );
  }

  factory _PlannerBoardRowData.location(String location) {
    final avatarLabel = location.characters.take(1).toString().toUpperCase();
    return _PlannerBoardRowData(
      id: 'location-$location',
      title: location,
      location: location == 'Ohne Standort' ? null : location,
      avatarLabel: avatarLabel,
      subtitle: 'Standort',
    );
  }

  final String id;
  final String title;
  final String avatarLabel;
  final String? memberId;
  final String? location;
  final String? subtitle;
  final double dailyHours;

  bool matches(Shift shift) {
    if (memberId != null) {
      return shift.userId == memberId;
    }
    final normalized = location?.trim();
    final effectiveShiftLocation = shift.effectiveSiteLabel?.trim();
    if (normalized == null || normalized.isEmpty) {
      return effectiveShiftLocation == null || effectiveShiftLocation.isEmpty;
    }
    return effectiveShiftLocation == normalized;
  }

  double targetHoursFor(List<DateTime> days) {
    if (memberId == null) {
      return 0;
    }
    final workDays = days.where((day) => day.weekday <= DateTime.friday).length;
    return workDays * dailyHours;
  }
}

class _PlannerDayHeaderCell extends StatelessWidget {
  const _PlannerDayHeaderCell({
    required this.day,
    required this.width,
    required this.noteCount,
    required this.onTapNote,
  });

  final DateTime day;
  final double width;
  final int noteCount;
  final VoidCallback onTapNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    return Container(
      width: width,
      height: 78,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant),
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('EEE, dd. MMM', 'de_DE').format(day).toUpperCase(),
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: onTapNote,
            child: Row(
              children: [
                Text(
                  noteCount > 0 ? '$noteCount Anmerkungen' : 'Anmerkungen',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: appColors.info,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.help_outline_rounded,
                  size: 14,
                  color: appColors.info,
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
    final visibleShiftCount = shifts.length > 2 ? 2 : shifts.length;
    final hiddenShiftCount = shifts.length - visibleShiftCount;
    final displayedShifts =
        shifts.take(visibleShiftCount).toList(growable: false);
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
                child: displayedShifts.isEmpty
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var index = 0;
                              index < displayedShifts.length;
                              index++) ...[
                            _PlannerCompactMonthShiftTile(
                              shift: displayedShifts[index],
                              onTap: () => onOpenShift(displayedShifts[index]),
                            ),
                            if (index < displayedShifts.length - 1)
                              const SizedBox(height: 4),
                          ],
                          if (hiddenShiftCount > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              '+$hiddenShiftCount mehr',
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
    final visibleShiftCount = shifts.length > 4 ? 4 : shifts.length;
    final hiddenShiftCount = shifts.length - visibleShiftCount;
    final displayedShifts =
        shifts.take(visibleShiftCount).toList(growable: false);
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
            child: displayedShifts.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0;
                          index < displayedShifts.length;
                          index++) ...[
                        _PlannerMonthShiftTile(
                          shift: displayedShifts[index],
                          onTap: () => onOpenShift(displayedShifts[index]),
                          onDelete: () => onDeleteShift(displayedShifts[index]),
                          onDeleteSeries:
                              displayedShifts[index].seriesId == null
                                  ? null
                                  : () => onDeleteSeries(
                                        displayedShifts[index].seriesId!,
                                      ),
                        ),
                        if (index < displayedShifts.length - 1)
                          const SizedBox(height: 6),
                      ],
                      if (hiddenShiftCount > 0) ...[
                        const SizedBox(height: 6),
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: onShowMore,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Text(
                              '+$hiddenShiftCount weitere',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
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
                Text(
                  'Abwesenheiten vorhanden',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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
          padding: const EdgeInsets.fromLTRB(8, 5, 2, 5),
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
                height: 22,
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
                    child: Text('Einzeln loeschen'),
                  ),
                  if (onDeleteSeries != null)
                    const PopupMenuItem(
                      value: 'delete_series',
                      child: Text('Serie loeschen'),
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

class _PlannerBoardShiftCard extends StatelessWidget {
  const _PlannerBoardShiftCard({
    required this.shift,
    required this.sameBucketCount,
    required this.onTap,
    required this.onDelete,
    this.onDeleteSeries,
  });

  final Shift shift;
  final int sameBucketCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onDeleteSeries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = _resolveShiftColor(shift, theme);
    final titleStyle = theme.textTheme.labelLarge?.copyWith(
      color: baseColor,
      fontWeight: FontWeight.w700,
    );
    final timeFmt = DateFormat('h a', 'en_US');
    return CustomPaint(
      painter: _DashedRoundedBorderPainter(
        color: baseColor.withValues(alpha: 0.38),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: _softenColor(
              baseColor,
              theme.colorScheme.surfaceContainerLowest,
              0.88,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border(
              left: BorderSide(color: baseColor, width: 4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      shift.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                  ),
                  if (sameBucketCount > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: baseColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$sameBucketCount',
                        style: TextStyle(
                          color: baseColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
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
                        child: Text('Einzeln loeschen'),
                      ),
                      if (onDeleteSeries != null)
                        const PopupMenuItem(
                          value: 'delete_series',
                          child: Text('Serie loeschen'),
                        ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.more_horiz, size: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${timeFmt.format(shift.startTime)} - ${timeFmt.format(shift.endTime)} · ${shift.workedHours.toStringAsFixed(0)}h',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                shift.effectiveSiteLabel?.trim().isNotEmpty == true
                    ? shift.effectiveSiteLabel!
                    : (shift.team?.trim().isNotEmpty == true
                        ? shift.team!
                        : 'Ohne Standort'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlannerAbsencePill extends StatelessWidget {
  const _PlannerAbsencePill({
    required this.absence,
    this.showEmployeeName = false,
    this.compact = false,
  });

  final AbsenceRequest absence;
  final bool showEmployeeName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dateFmt = DateFormat('dd.MM.yyyy');
    final colors = switch (absence.status) {
      AbsenceStatus.pending => (
          background: colorScheme.secondaryContainer,
          foreground: colorScheme.onSecondaryContainer,
          accent: colorScheme.secondary,
        ),
      AbsenceStatus.approved => (
          background: colorScheme.tertiaryContainer,
          foreground: colorScheme.onTertiaryContainer,
          accent: colorScheme.tertiary,
        ),
      AbsenceStatus.rejected => (
          background: colorScheme.surfaceContainerHigh,
          foreground: colorScheme.onSurfaceVariant,
          accent: colorScheme.outline,
        ),
    };
    final icon = switch (absence.type) {
      AbsenceType.vacation => Icons.beach_access_rounded,
      AbsenceType.sickness => Icons.healing_rounded,
      AbsenceType.unavailable => Icons.block_rounded,
    };
    final label = showEmployeeName
        ? '${absence.employeeName}: ${absence.type.label} · ${absence.status.label}'
        : '${absence.type.label} · ${absence.status.label}';
    final tooltip = StringBuffer()
      ..write(label)
      ..write('\n')
      ..write(dateFmt.format(absence.startDate))
      ..write(' - ')
      ..write(dateFmt.format(absence.endDate));
    if (absence.note != null && absence.note!.trim().isNotEmpty) {
      tooltip
        ..write('\n')
        ..write(absence.note!.trim());
    }

    return Tooltip(
      message: tooltip.toString(),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: compact ? double.infinity : 320,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 6 : 7,
          ),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colors.accent.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Icon(
                icon,
                size: compact ? 14 : 16,
                color: colors.accent,
              ),
              const SizedBox(width: 6),
              if (compact)
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedRoundedBorderPainter extends CustomPainter {
  _DashedRoundedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(14);
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, radius);
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (final metric in metrics) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0.0, metric.length)),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedBorderPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

Color _plannerAvatarColor(ThemeData theme, _PlannerBoardRowData row) {
  final appColors = theme.appColors;
  final palette = [
    theme.colorScheme.primary,
    theme.colorScheme.secondary,
    appColors.success,
    theme.colorScheme.tertiary,
    appColors.info,
  ];
  if (row.location != null || row.id.startsWith('location-')) {
    return appColors.info;
  }
  final index = row.id.hashCode.abs() % palette.length;
  return palette[index];
}

Color _resolveShiftColor(Shift shift, ThemeData theme) {
  if (shift.color != null && shift.color!.trim().isNotEmpty) {
    return Color(int.parse(shift.color!.replaceFirst('#', '0xFF')));
  }
  final palette = [
    theme.appColors.success,
    theme.colorScheme.primary,
    theme.colorScheme.secondary,
    theme.colorScheme.tertiary,
    theme.appColors.info,
  ];
  final index = shift.title.hashCode.abs() % palette.length;
  return palette[index];
}

Color _softenColor(Color color, Color surface, double amount) {
  return Color.lerp(color, surface, amount) ?? color;
}

int _isoWeekNumber(DateTime date) {
  final normalized = DateTime(date.year, date.month, date.day);
  final thursday =
      normalized.add(Duration(days: DateTime.thursday - normalized.weekday));
  final firstThursday = DateTime(thursday.year, 1, 4);
  final firstWeekThursday = firstThursday
      .add(Duration(days: DateTime.thursday - firstThursday.weekday));
  return 1 + (thursday.difference(firstWeekThursday).inDays ~/ 7);
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
    final endFmt = DateFormat('HH:mm');
    final borderColor = shift.color != null
        ? Color(int.parse(shift.color!.replaceFirst('#', '0xFF')))
        : null;
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
              if (!isAdmin && shift.swapStatus == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TextButton.icon(
                    onPressed: () async {
                      if (shift.id == null) return;
                      try {
                        await context
                            .read<ScheduleProvider>()
                            .requestShiftSwap(shift.id!);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Tauschanfrage gesendet')),
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
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Tausch anfragen'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              if (!isAdmin && shift.swapStatus == 'pending')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Tauschanfrage ausstehend',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.tertiary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
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
          leading:
              CircleAvatar(child: Text(shift.employeeName.substring(0, 1))),
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
                      child: Text('Einzeln loeschen'),
                    ),
                    if (onDeleteSeries != null)
                      const PopupMenuItem(
                        value: 'delete_series',
                        child: Text('Serie loeschen'),
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
    final dateFmt = DateFormat('dd.MM.yyyy');
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
                            child: Text('Loeschen'),
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

class _ShiftEditorResult {
  const _ShiftEditorResult({
    required this.shifts,
    required this.recurrencePattern,
    required this.recurrenceEndDate,
  });

  final List<Shift> shifts;
  final RecurrencePattern recurrencePattern;
  final DateTime? recurrenceEndDate;
}

class _ShiftTemplatePickerSheet extends StatelessWidget {
  const _ShiftTemplatePickerSheet({
    required this.templates,
    required this.selectedTemplateId,
  });

  final List<ShiftTemplate> templates;
  final String? selectedTemplateId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Schichtvorlage auswaehlen',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: templates.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final template = templates[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(template.name),
                    subtitle: Text(
                      _formatShiftTemplateSummary(context, template),
                      maxLines: template.notes != null ? 4 : 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: selectedTemplateId == template.id
                        ? Icon(
                            Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () => Navigator.of(context).pop(template),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftTemplateSaveSheet extends StatefulWidget {
  const _ShiftTemplateSaveSheet({
    required this.template,
  });

  final ShiftTemplate template;

  @override
  State<_ShiftTemplateSaveSheet> createState() =>
      _ShiftTemplateSaveSheetState();
}

class _ShiftTemplateSaveSheetState extends State<_ShiftTemplateSaveSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.template.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.template.id != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEdit ? 'Schichtvorlage bearbeiten' : 'Schichtvorlage speichern',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _formatShiftTemplateSummary(context, widget.template),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name der Vorlage',
                prefixIcon: Icon(Icons.bookmark_outline),
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Bitte einen Namen eingeben';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: Icon(isEdit ? Icons.edit_outlined : Icons.save),
              label: Text(
                isEdit ? 'Vorlage aktualisieren' : 'Vorlage speichern',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(
      widget.template.copyWith(
        name: _nameCtrl.text.trim(),
      ),
    );
  }
}

class _AdditionalShiftAssignmentDraft {
  const _AdditionalShiftAssignmentDraft({
    required this.id,
    this.memberId,
    required this.startTime,
    required this.endTime,
    this.breakMinutes = 0,
  });

  final int id;
  final String? memberId;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final double breakMinutes;

  _AdditionalShiftAssignmentDraft copyWith({
    String? memberId,
    bool clearMemberId = false,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    double? breakMinutes,
  }) {
    return _AdditionalShiftAssignmentDraft(
      id: id,
      memberId: clearMemberId ? null : (memberId ?? this.memberId),
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      breakMinutes: breakMinutes ?? this.breakMinutes,
    );
  }
}

class _ShiftEditorSheet extends StatefulWidget {
  const _ShiftEditorSheet({
    required this.members,
    required this.teams,
    required this.currentUser,
    this.shift,
    this.initialDate,
    this.initialUserIds,
    this.initialUnassigned = false,
    this.initialLocation,
    this.initialTeamId,
    this.initialTeamName,
    this.initialTitle,
  });

  final List<AppUserProfile> members;
  final List<TeamDefinition> teams;
  final AppUserProfile currentUser;
  final Shift? shift;
  final DateTime? initialDate;
  final Set<String>? initialUserIds;
  final bool initialUnassigned;
  final String? initialLocation;
  final String? initialTeamId;
  final String? initialTeamName;
  final String? initialTitle;

  @override
  State<_ShiftEditorSheet> createState() => _ShiftEditorSheetState();
}

class _ShiftEditorSheetState extends State<_ShiftEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _teamCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _breakCtrl;
  late final TextEditingController _notesCtrl;
  late DateTime _date;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late Set<String> _selectedUserIds;
  String? _selectedTeamId;
  late ShiftStatus _status;
  RecurrencePattern _recurrencePattern = RecurrencePattern.none;
  DateTime? _recurrenceEndDate;
  String? _shiftColor;
  List<ShiftConflictIssue> _conflictIssues = const [];
  List<ShiftAssigneeAvailability> _assigneeAvailability = const [];
  int _availabilityRequestId = 0;
  bool _loadingAvailability = false;
  late bool _saveAsUnassigned;
  String? _selectedSiteId;
  String? _selectedTemplateId;
  bool _siteInitialized = false;
  Set<String> _requiredQualificationIds = <String>{};
  List<_AdditionalShiftAssignmentDraft> _additionalAssignments = const [];
  int _nextAdditionalAssignmentDraftId = 0;
  bool _validating = false;

  @override
  void initState() {
    super.initState();
    final shift = widget.shift;
    _saveAsUnassigned =
        widget.initialUnassigned || (shift?.isUnassigned ?? false);
    final initialDate =
        widget.initialDate ?? shift?.startTime ?? DateTime.now();
    _titleCtrl =
        TextEditingController(text: shift?.title ?? widget.initialTitle ?? '');
    _teamCtrl = TextEditingController(
      text: shift?.team ?? widget.initialTeamName ?? '',
    );
    _locationCtrl = TextEditingController(
      text: shift?.location ?? widget.initialLocation ?? '',
    );
    _breakCtrl = TextEditingController(
      text: (shift?.breakMinutes ?? 30).toStringAsFixed(0),
    );
    _notesCtrl = TextEditingController(text: shift?.notes ?? '');
    _date = initialDate;
    _startTime = TimeOfDay.fromDateTime(
      shift?.startTime ?? initialDate,
    );
    _endTime = TimeOfDay.fromDateTime(
      shift?.endTime ?? initialDate.add(const Duration(hours: 8)),
    );
    final draftUserIds = widget.initialUserIds ?? const <String>{};
    if (shift != null) {
      _selectedUserIds = {
        if (!shift.isUnassigned) shift.userId,
      };
    } else if (draftUserIds.isNotEmpty) {
      _selectedUserIds = draftUserIds.toSet();
    } else if (_saveAsUnassigned) {
      _selectedUserIds = <String>{};
    } else {
      _selectedUserIds = {
        if (widget.members.isNotEmpty) widget.members.first.uid,
      };
    }
    _selectedTeamId = shift?.teamId ??
        widget.initialTeamId ??
        widget.teams
            .where((team) => team.name == shift?.team)
            .map((team) => team.id)
            .whereType<String>()
            .firstOrNull;
    _selectedSiteId = shift?.siteId;
    _requiredQualificationIds = {
      ...?shift?.requiredQualificationIds,
    };
    _status = shift?.status ?? ShiftStatus.planned;
    _recurrencePattern = shift?.recurrencePattern ?? RecurrencePattern.none;
    _shiftColor = shift?.color;
    _titleCtrl.addListener(_clearConflictPreview);
    _teamCtrl.addListener(_clearConflictPreview);
    _locationCtrl.addListener(_clearConflictPreview);
    _breakCtrl.addListener(_clearConflictPreview);
    _notesCtrl.addListener(_clearConflictPreview);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!_saveAsUnassigned) {
        _refreshAssigneeAvailability();
      }
    });
  }

  @override
  void dispose() {
    _titleCtrl.removeListener(_clearConflictPreview);
    _teamCtrl.removeListener(_clearConflictPreview);
    _locationCtrl.removeListener(_clearConflictPreview);
    _breakCtrl.removeListener(_clearConflictPreview);
    _notesCtrl.removeListener(_clearConflictPreview);
    _titleCtrl.dispose();
    _teamCtrl.dispose();
    _locationCtrl.dispose();
    _breakCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_siteInitialized) {
      return;
    }
    _siteInitialized = true;
    final sites = context.read<TeamProvider>().sites;
    final site = sites.firstWhereOrNull(
      (candidate) =>
          candidate.id == _selectedSiteId ||
          candidate.name.trim().toLowerCase() ==
              _locationCtrl.text.trim().toLowerCase(),
    );
    if (site != null) {
      _selectedSiteId = site.id;
      _locationCtrl.text = site.name;
    }
  }

  void _clearConflictPreview() {
    if (_conflictIssues.isEmpty) {
      return;
    }
    setState(() => _conflictIssues = const []);
  }

  void _setDirty(
    VoidCallback callback, {
    bool refreshAvailability = false,
  }) {
    setState(() {
      callback();
      _conflictIssues = const [];
    });
    if (refreshAvailability) {
      _refreshAssigneeAvailability();
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamProvider = context.watch<TeamProvider>();
    final scheduleProvider = context.watch<ScheduleProvider>();
    final sites = teamProvider.sites;
    final qualifications = teamProvider.qualifications;
    final shiftTemplates = scheduleProvider.shiftTemplates;
    final selectedTemplate = shiftTemplates
        .where((template) => template.id == _selectedTemplateId)
        .firstOrNull;
    final isEdit = widget.shift != null;
    final selectedTeam =
        widget.teams.where((team) => team.id == _selectedTeamId).firstOrNull;
    final availabilityItems = _visibleAssigneeAvailability;
    final availableMembers = availabilityItems
        .where((entry) => entry.isAvailable)
        .toList(growable: false);
    final unavailableMembers = availabilityItems
        .where((entry) => !entry.isAvailable)
        .toList(growable: false);
    final selectedUserId = _selectedUserIds.firstOrNull;
    final selectedAvailability = availabilityItems
        .where((entry) => entry.member.uid == selectedUserId)
        .firstOrNull;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEdit ? 'Schicht bearbeiten' : 'Neue Schicht',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Schichtvorlagen',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        _EditorCountBadge(
                          label:
                              '${shiftTemplates.length} Vorlage${shiftTemplates.length == 1 ? '' : 'n'}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      selectedTemplate == null
                          ? 'Speichere haeufige Schichten als Vorlage oder uebernimm bestehende Einstellungen mit einem Tippen.'
                          : 'Aktive Vorlage: ${selectedTemplate.name}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: shiftTemplates.isEmpty
                              ? null
                              : () => _pickTemplate(shiftTemplates),
                          icon: const Icon(Icons.bookmarks_outlined),
                          label: Text(
                            selectedTemplate?.name ?? 'Aus Vorlage uebernehmen',
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _saveCurrentAsTemplate,
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: const Text('Als Vorlage speichern'),
                        ),
                        if (selectedTemplate != null) ...[
                          FilledButton.tonalIcon(
                            onPressed: () => _updateTemplate(selectedTemplate),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Vorlage aktualisieren'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _deleteTemplate(selectedTemplate),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Vorlage loeschen'),
                          ),
                        ],
                      ],
                    ),
                    if (selectedTemplate != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _formatShiftTemplateSummary(context, selectedTemplate),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ] else if (shiftTemplates.isEmpty) ...[
                      const SizedBox(height: 12),
                      const _EditorNoticeCard(
                        icon: Icons.bookmark_border_outlined,
                        title: 'Noch keine Schichtvorlagen vorhanden',
                        message:
                            'Lege aus dem aktuellen Formular eine Vorlage an, um wiederkehrende Schichten schneller zu planen.',
                        tone: _EditorNoticeTone.info,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Planung',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    ChoiceChip(
                      label: const Text('Mitarbeiter'),
                      selected: !_saveAsUnassigned,
                      onSelected: (selected) {
                        if (!selected) {
                          return;
                        }
                        _setDirty(
                          () {
                            _saveAsUnassigned = false;
                            if (_selectedUserIds.isEmpty &&
                                widget.members.isNotEmpty) {
                              _selectedUserIds = {widget.members.first.uid};
                            }
                          },
                          refreshAvailability: true,
                        );
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Freie Schicht'),
                      selected: _saveAsUnassigned,
                      onSelected: (selected) {
                        if (!selected) {
                          return;
                        }
                        _setDirty(() {
                          _saveAsUnassigned = true;
                          _selectedUserIds = <String>{};
                          _additionalAssignments = const [];
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_saveAsUnassigned)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Diese Schicht wird ohne feste Zuordnung gespeichert und erscheint im Bereich "Freie Schichten".',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              )
            else if (isEdit)
              DropdownButtonFormField<String>(
                initialValue: selectedUserId,
                decoration: const InputDecoration(
                  labelText: 'Mitarbeiter',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                items: [
                  for (final availability in availabilityItems)
                    DropdownMenuItem(
                      value: availability.member.uid,
                      enabled: availability.isAvailable ||
                          availability.member.uid == selectedUserId,
                      child: Text(
                        availability.isAvailable ||
                                availability.member.uid == selectedUserId
                            ? availability.member.displayName
                            : '${availability.member.displayName} · nicht verfuegbar',
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _setDirty(() => _selectedUserIds = {value});
                  }
                },
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Mitarbeiter',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          _EditorCountBadge(
                            label: '${_selectedUserIds.length} ausgewaehlt',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (widget.members.isEmpty)
                        const _EditorNoticeCard(
                          icon: Icons.people_outline_rounded,
                          title: 'Keine aktiven Mitarbeiter vorhanden',
                          message:
                              'Im Team sind aktuell keine aktiven Mitarbeiter hinterlegt.',
                          tone: _EditorNoticeTone.warning,
                        )
                      else ...[
                        const _EditorNoticeCard(
                          icon: Icons.auto_awesome_outlined,
                          title: 'Automatische Vorschlaege aktiv',
                          message:
                              'Freie Mitarbeiter werden vorgeschlagen. Bereits belegte oder abwesende Mitarbeiter bleiben gesperrt, bis der Konflikt behoben ist.',
                          tone: _EditorNoticeTone.info,
                        ),
                        if (_loadingAvailability) ...[
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: const LinearProgressIndicator(minHeight: 6),
                          ),
                        ],
                        if (availableMembers.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Verfuegbar im gewaehlten Zeitraum',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              _EditorCountBadge(
                                label: '${availableMembers.length} frei',
                                tone: _EditorBadgeTone.success,
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () => _setDirty(
                                  () => _selectedUserIds = availableMembers
                                      .map((entry) => entry.member.uid)
                                      .toSet(),
                                ),
                                icon: const Icon(Icons.playlist_add_check),
                                label: const Text('Alle freien auswaehlen'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final availability in availableMembers)
                                FilterChip(
                                  label: Text(availability.member.displayName),
                                  selected: _selectedUserIds
                                      .contains(availability.member.uid),
                                  onSelected: (selected) {
                                    _setDirty(() {
                                      if (selected) {
                                        _selectedUserIds
                                            .add(availability.member.uid);
                                      } else {
                                        _selectedUserIds
                                            .remove(availability.member.uid);
                                      }
                                    });
                                  },
                                ),
                            ],
                          ),
                        ],
                        if (availableMembers.isEmpty && !_loadingAvailability)
                          const Padding(
                            padding: EdgeInsets.only(top: 16),
                            child: _EditorNoticeCard(
                              icon: Icons.person_search_outlined,
                              title: 'Aktuell kein freier Mitarbeiter',
                              message:
                                  'Passe Zeitfenster, Standort oder Arbeitsbereich an oder speichere die Schicht als freie Schicht.',
                              tone: _EditorNoticeTone.warning,
                            ),
                          ),
                        if (unavailableMembers.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Nicht verfuegbar',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              _EditorCountBadge(
                                label: '${unavailableMembers.length} gesperrt',
                                tone: _EditorBadgeTone.warning,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Diese Mitarbeiter koennen aktuell nicht eingeplant werden. Die Gruende werden pro Person aufgegliedert.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                          const SizedBox(height: 12),
                          Column(
                            children: [
                              for (final availability in unavailableMembers)
                                _AssigneeAvailabilityTile(
                                  availability: availability,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Schichttitel',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Bitte Titel eingeben';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _DateTile(
              label: 'Datum',
              value: DateFormat('dd.MM.yyyy').format(_date),
              icon: Icons.calendar_today,
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.login),
                    title: const Text('Beginn'),
                    trailing: Text(_startTime.format(context)),
                    onTap: _pickStart,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Ende'),
                    trailing: Text(_endTime.format(context)),
                    onTap: _pickEnd,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _breakCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Pause in Minuten',
                prefixIcon: Icon(Icons.coffee_outlined),
              ),
              onChanged: (_) => _setDirty(
                () {},
                refreshAvailability: true,
              ),
            ),
            if (!_saveAsUnassigned && widget.members.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Weitere Besetzungen',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          _EditorCountBadge(
                            label:
                                '${_additionalAssignments.length} Zusatzbesetzung${_additionalAssignments.length == 1 ? '' : 'en'}',
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _addAdditionalAssignment,
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('Person hinzufuegen'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Titel, Standort, Arbeitsbereich, Qualifikationen, Notiz, Status und Farbe werden vom Hauptblock uebernommen. Fuer jede Zusatzbesetzung kannst du einen eigenen Mitarbeiter und eigene Zeiten definieren. Konflikte werden beim Speichern gemeinsam geprueft.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 14),
                      if (_additionalAssignments.isEmpty)
                        const _EditorNoticeCard(
                          icon: Icons.schedule_send_outlined,
                          title: 'Keine Zusatzbesetzung angelegt',
                          message:
                              'Nutze weitere Besetzungen, wenn dieselbe Schicht von mehreren Personen in unterschiedlichen Zeitfenstern uebernommen wird, zum Beispiel 08:00 - 10:00 und 10:00 - 13:00.',
                          tone: _EditorNoticeTone.info,
                        )
                      else
                        Column(
                          children: [
                            for (var index = 0;
                                index < _additionalAssignments.length;
                                index++) ...[
                              _AdditionalShiftAssignmentCard(
                                key: ValueKey(
                                  'additional-assignment-${_additionalAssignments[index].id}',
                                ),
                                index: index,
                                draft: _additionalAssignments[index],
                                members: widget.members,
                                onMemberChanged: (memberId) =>
                                    _updateAdditionalAssignment(
                                  _additionalAssignments[index].id,
                                  (draft) => draft.copyWith(memberId: memberId),
                                ),
                                onRemove: () => _removeAdditionalAssignment(
                                  _additionalAssignments[index].id,
                                ),
                                onPickStart: () => _pickAdditionalStart(
                                  _additionalAssignments[index].id,
                                ),
                                onPickEnd: () => _pickAdditionalEnd(
                                  _additionalAssignments[index].id,
                                ),
                                onBreakChanged: (value) =>
                                    _updateAdditionalAssignment(
                                  _additionalAssignments[index].id,
                                  (draft) => draft.copyWith(
                                    breakMinutes:
                                        _parseBreakMinutesValue(value),
                                  ),
                                ),
                              ),
                              if (index < _additionalAssignments.length - 1)
                                const SizedBox(height: 12),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _selectedTeamId,
              decoration: const InputDecoration(
                labelText: 'Gespeichertes Team',
                prefixIcon: Icon(Icons.groups_2_outlined),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Kein Team'),
                ),
                for (final team in widget.teams)
                  DropdownMenuItem<String?>(
                    value: team.id,
                    child: Text(team.name),
                  ),
              ],
              onChanged: (value) {
                _setDirty(
                  () {
                    _selectedTeamId = value;
                    if (value == null) {
                      return;
                    }
                    final team = widget.teams
                        .where((candidate) => candidate.id == value)
                        .firstOrNull;
                    if (team == null) {
                      return;
                    }
                    _teamCtrl.text = team.name;
                    if (!isEdit && team.memberIds.isNotEmpty) {
                      _selectedUserIds = widget.members
                          .where(
                              (member) => team.memberIds.contains(member.uid))
                          .map((member) => member.uid)
                          .toSet();
                    }
                  },
                  refreshAvailability: true,
                );
              },
            ),
            if (selectedTeam != null &&
                selectedTeam.memberIds.isNotEmpty &&
                !isEdit) ...[
              const SizedBox(height: 8),
              Text(
                'Teammitglieder werden automatisch uebernommen. Belegte Mitarbeiter werden darunter separat mit Konfliktgrund angezeigt.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _teamCtrl,
              decoration: const InputDecoration(
                labelText: 'Team / Bereich',
                prefixIcon: Icon(Icons.group_work_outlined),
              ),
            ),
            const SizedBox(height: 12),
            if (sites.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Es sind noch keine Standorte angelegt. Bitte hinterlege zuerst Standorte in der Teamverwaltung.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _selectedSiteId,
                decoration: const InputDecoration(
                  labelText: 'Standort',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                items: [
                  for (final site in sites)
                    DropdownMenuItem(
                      value: site.id,
                      child: Text(site.name),
                    ),
                ],
                onChanged: (value) {
                  _setDirty(
                    () {
                      _selectedSiteId = value;
                      final selected =
                          sites.where((site) => site.id == value).firstOrNull;
                      _locationCtrl.text = selected?.name ?? '';
                    },
                    refreshAvailability: true,
                  );
                },
              ),
            if (qualifications.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Erforderliche Qualifikationen',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final qualification in qualifications)
                    FilterChip(
                      label: Text(qualification.name),
                      selected:
                          _requiredQualificationIds.contains(qualification.id),
                      onSelected: (selected) {
                        _setDirty(
                          () {
                            if (qualification.id == null) {
                              return;
                            }
                            if (selected) {
                              _requiredQualificationIds.add(qualification.id!);
                            } else {
                              _requiredQualificationIds
                                  .remove(qualification.id);
                            }
                          },
                          refreshAvailability: true,
                        );
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notiz',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ShiftStatus>(
              initialValue: _status,
              decoration: const InputDecoration(
                labelText: 'Status',
                prefixIcon: Icon(Icons.flag_outlined),
              ),
              items: [
                for (final status in ShiftStatus.values)
                  DropdownMenuItem(
                    value: status,
                    child: Text(status.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  _setDirty(() => _status = value);
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<RecurrencePattern>(
              initialValue: _recurrencePattern,
              decoration: const InputDecoration(
                labelText: 'Wiederholung',
                prefixIcon: Icon(Icons.repeat),
              ),
              items: [
                for (final pattern in RecurrencePattern.values)
                  DropdownMenuItem(
                    value: pattern,
                    child: Text(pattern.label),
                  ),
              ],
              onChanged: isEdit
                  ? null
                  : (value) {
                      if (value != null) {
                        _setDirty(() => _recurrencePattern = value);
                      }
                    },
            ),
            if (!isEdit && _recurrencePattern != RecurrencePattern.none) ...[
              const SizedBox(height: 12),
              _DateTile(
                label: 'Wiederholen bis',
                value: _recurrenceEndDate == null
                    ? 'Enddatum waehlen'
                    : DateFormat('dd.MM.yyyy').format(_recurrenceEndDate!),
                icon: Icons.event_repeat,
                onTap: _pickRecurrenceEndDate,
              ),
            ],
            const SizedBox(height: 12),
            Text('Farbe', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final hex in const [
                  '#4CAF50',
                  '#2196F3',
                  '#FF9800',
                  '#E91E63',
                  '#9C27B0',
                  '#00BCD4',
                  '#795548',
                  '#607D8B',
                ])
                  GestureDetector(
                    onTap: () => _setDirty(
                      () => _shiftColor = _shiftColor == hex ? null : hex,
                    ),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(int.parse(hex.replaceFirst('#', '0xFF'))),
                        shape: BoxShape.circle,
                        border: _shiftColor == hex
                            ? Border.all(
                                color: Theme.of(context).colorScheme.onSurface,
                                width: 3)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            if (isEdit && _loadingAvailability) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (isEdit &&
                selectedAvailability != null &&
                !selectedAvailability.isAvailable) ...[
              const SizedBox(height: 12),
              _AssigneeAvailabilityTile(
                availability: selectedAvailability,
                title: 'Ausgewaehlter Mitarbeiter ist nicht verfuegbar',
              ),
            ],
            const SizedBox(height: 20),
            if (_conflictIssues.isNotEmpty) ...[
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _conflictIssues.length == 1
                            ? '1 Konflikt gefunden'
                            : '${_conflictIssues.length} Konflikte gefunden',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Die betroffenen Schichten werden unten aufgelistet. Passe Zeiten, Mitarbeiter oder Abwesenheiten an und pruefe erneut.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _ShiftConflictList(
                        issues: _conflictIssues,
                        textColor:
                            Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed: _validating ? null : _save,
              icon: _validating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(
                _validating
                    ? 'Pruefe Konflikte...'
                    : (isEdit ? 'Aktualisieren' : 'Speichern'),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTemplate(List<ShiftTemplate> templates) async {
    final template = await showModalBottomSheet<ShiftTemplate>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _ShiftTemplatePickerSheet(
        templates: templates,
        selectedTemplateId: _selectedTemplateId,
      ),
    );
    if (template == null || !mounted) {
      return;
    }

    final sites = context.read<TeamProvider>().sites;
    final resolvedTeam = widget.teams.firstWhereOrNull(
      (team) =>
          team.id == template.teamId ||
          (template.teamName?.trim().isNotEmpty == true &&
              team.name.trim().toLowerCase() ==
                  template.teamName!.trim().toLowerCase()),
    );
    final resolvedSite = sites.firstWhereOrNull(
      (site) =>
          site.id == template.siteId ||
          (template.siteName?.trim().isNotEmpty == true &&
              site.name.trim().toLowerCase() ==
                  template.siteName!.trim().toLowerCase()),
    );

    _setDirty(
      () {
        _selectedTemplateId = template.id;
        _titleCtrl.text = template.title;
        _startTime = _timeOfDayFromMinutes(template.startMinutes);
        _endTime = _timeOfDayFromMinutes(template.endMinutes);
        _breakCtrl.text = _formatBreakMinutes(template.breakMinutes);
        _notesCtrl.text = template.notes ?? '';
        _selectedTeamId = resolvedTeam?.id;
        _teamCtrl.text = resolvedTeam?.name ?? (template.teamName ?? '');
        _selectedSiteId = resolvedSite?.id;
        _locationCtrl.text = resolvedSite?.name ?? (template.siteName ?? '');
        _requiredQualificationIds = template.requiredQualificationIds.toSet();
        _shiftColor = template.color;
      },
      refreshAvailability: true,
    );
  }

  Future<void> _saveCurrentAsTemplate() async {
    final draft = _buildTemplateDraft();
    if (draft == null) {
      return;
    }

    final template = await _openTemplateSaveSheet(draft);
    if (template == null || !mounted) {
      return;
    }

    try {
      await context.read<ScheduleProvider>().saveShiftTemplate(template);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Schichtvorlage gespeichert.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Vorlage konnte nicht gespeichert werden: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _updateTemplate(ShiftTemplate template) async {
    final draft = _buildTemplateDraft();
    if (draft == null) {
      return;
    }

    final updatedTemplate = await _openTemplateSaveSheet(
      draft.copyWith(
        id: template.id,
        orgId: template.orgId,
        userId: template.userId,
        name: template.name,
      ),
    );
    if (updatedTemplate == null || !mounted) {
      return;
    }

    try {
      await context.read<ScheduleProvider>().saveShiftTemplate(updatedTemplate);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Schichtvorlage aktualisiert.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Vorlage konnte nicht aktualisiert werden: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _deleteTemplate(ShiftTemplate template) async {
    final templateId = template.id;
    if (templateId == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Schichtvorlage loeschen?'),
        content: Text(
          'Die Vorlage "${template.name}" wird unwiderruflich geloescht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Loeschen'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await context.read<ScheduleProvider>().deleteShiftTemplate(templateId);
      if (!mounted) {
        return;
      }
      if (_selectedTemplateId == templateId) {
        _setDirty(() => _selectedTemplateId = null);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Schichtvorlage geloescht.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Vorlage konnte nicht geloescht werden: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<ShiftTemplate?> _openTemplateSaveSheet(ShiftTemplate template) {
    return showModalBottomSheet<ShiftTemplate>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _ShiftTemplateSaveSheet(template: template),
      ),
    );
  }

  ShiftTemplate? _buildTemplateDraft() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Bitte zuerst einen Schichttitel eingeben.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return null;
    }

    final startMinutes = _toMinutes(_startTime);
    final endMinutes = _toMinutes(_endTime);
    if (endMinutes <= startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Endzeit muss nach Startzeit liegen.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return null;
    }

    final sites = context.read<TeamProvider>().sites;
    final selectedTeam =
        widget.teams.where((team) => team.id == _selectedTeamId).firstOrNull;
    final selectedSite =
        sites.where((site) => site.id == _selectedSiteId).firstOrNull;
    final teamName = _teamCtrl.text.trim().isEmpty
        ? selectedTeam?.name
        : _teamCtrl.text.trim();
    final siteName = selectedSite?.name ??
        (_locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim());

    return ShiftTemplate(
      name: title,
      title: title,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      breakMinutes: _parseBreakMinutes(),
      teamId: selectedTeam?.id,
      teamName: teamName,
      siteId: selectedSite?.id,
      siteName: siteName,
      requiredQualificationIds:
          _requiredQualificationIds.toList(growable: false),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      color: _shiftColor,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('de', 'DE'),
    );
    if (picked != null) {
      _setDirty(
        () => _date = picked,
        refreshAvailability: true,
      );
    }
  }

  Future<void> _pickRecurrenceEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _recurrenceEndDate ?? _date.add(const Duration(days: 28)),
      firstDate: _date,
      lastDate: DateTime(2035),
      locale: const Locale('de', 'DE'),
    );
    if (picked != null) {
      _setDirty(() => _recurrenceEndDate = picked);
    }
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) {
      _setDirty(
        () => _startTime = picked,
        refreshAvailability: true,
      );
    }
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null) {
      _setDirty(
        () => _endTime = picked,
        refreshAvailability: true,
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final shifts = _buildProposedShifts();
    if (shifts == null) {
      return;
    }

    setState(() {
      _validating = true;
      _conflictIssues = const [];
    });

    try {
      final issues = await context.read<ScheduleProvider>().validateShifts(
            shifts,
            recurrencePattern: _recurrencePattern,
            recurrenceEndDate: _recurrenceEndDate,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _validating = false;
        _conflictIssues = issues;
      });
      if (issues.isNotEmpty) {
        return;
      }

      Navigator.of(context).pop(
        _ShiftEditorResult(
          shifts: shifts,
          recurrencePattern: _recurrencePattern,
          recurrenceEndDate: _recurrenceEndDate,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _validating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Konfliktpruefung fehlgeschlagen: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  List<Shift>? _buildProposedShifts() {
    final sites = context.read<TeamProvider>().sites;
    final selectedMembers = widget.members
        .where((candidate) => _selectedUserIds.contains(candidate.uid))
        .toList(growable: false);
    final startTime = _selectedStartDateTime;
    final endTime = _selectedEndDateTime;

    if (!endTime.isAfter(startTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Endzeit muss nach Startzeit liegen.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return null;
    }

    if (!_saveAsUnassigned &&
        selectedMembers.isEmpty &&
        _additionalAssignments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Bitte mindestens einen Mitarbeiter einplanen.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return null;
    }

    if (widget.shift == null &&
        _recurrencePattern != RecurrencePattern.none &&
        _recurrenceEndDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Bitte Enddatum fuer die Wiederholung waehlen.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return null;
    }

    final teamName =
        _teamCtrl.text.trim().isEmpty ? null : _teamCtrl.text.trim();
    final selectedSite = sites.firstWhereOrNull(
      (site) => site.id == _selectedSiteId,
    );
    if (selectedSite == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Bitte einen Standort auswaehlen.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return null;
    }
    final location = selectedSite.name;
    final breakMinutes = _parseBreakMinutes();
    if (_saveAsUnassigned) {
      return [
        Shift(
          id: widget.shift?.id,
          orgId: widget.currentUser.orgId,
          userId: '',
          employeeName: 'Freie Schicht',
          title: _titleCtrl.text.trim(),
          startTime: startTime,
          endTime: endTime,
          breakMinutes: breakMinutes,
          teamId: _selectedTeamId,
          team: teamName,
          siteId: selectedSite.id,
          siteName: selectedSite.name,
          location: location,
          requiredQualificationIds:
              _requiredQualificationIds.toList(growable: false),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          seriesId: widget.shift?.seriesId,
          recurrencePattern: _recurrencePattern,
          color: _shiftColor,
          status: _status,
          createdByUid: widget.currentUser.uid,
        ),
      ];
    }

    final shifts = <Shift>[
      ...selectedMembers.map(
        (member) => Shift(
          id: widget.shift?.id,
          orgId: widget.currentUser.orgId,
          userId: member.uid,
          employeeName: member.displayName,
          title: _titleCtrl.text.trim(),
          startTime: startTime,
          endTime: endTime,
          breakMinutes: breakMinutes,
          teamId: _selectedTeamId,
          team: teamName,
          siteId: selectedSite.id,
          siteName: selectedSite.name,
          location: location,
          requiredQualificationIds:
              _requiredQualificationIds.toList(growable: false),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          seriesId: widget.shift?.seriesId,
          recurrencePattern: _recurrencePattern,
          color: _shiftColor,
          status: _status,
          createdByUid: widget.currentUser.uid,
        ),
      ),
    ];

    for (var index = 0; index < _additionalAssignments.length; index++) {
      final draft = _additionalAssignments[index];
      final memberId = draft.memberId?.trim();
      if (memberId == null || memberId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Bitte fuer Zusatzbesetzung ${index + 1} einen Mitarbeiter auswaehlen.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return null;
      }
      final member = widget.members
          .where((candidate) => candidate.uid == memberId)
          .firstOrNull;
      if (member == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Mitarbeiter fuer Zusatzbesetzung ${index + 1} wurde nicht gefunden.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return null;
      }

      final additionalStart = _dateTimeFor(draft.startTime);
      final additionalEnd = _dateTimeFor(draft.endTime);
      if (!additionalEnd.isAfter(additionalStart)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Endzeit muss in Zusatzbesetzung ${index + 1} nach der Startzeit liegen.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return null;
      }

      shifts.add(
        Shift(
          orgId: widget.currentUser.orgId,
          userId: member.uid,
          employeeName: member.displayName,
          title: _titleCtrl.text.trim(),
          startTime: additionalStart,
          endTime: additionalEnd,
          breakMinutes: draft.breakMinutes,
          teamId: _selectedTeamId,
          team: teamName,
          siteId: selectedSite.id,
          siteName: selectedSite.name,
          location: location,
          requiredQualificationIds:
              _requiredQualificationIds.toList(growable: false),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          seriesId: widget.shift?.seriesId,
          recurrencePattern: _recurrencePattern,
          color: _shiftColor,
          status: _status,
          createdByUid: widget.currentUser.uid,
        ),
      );
    }

    return shifts;
  }

  List<ShiftAssigneeAvailability> get _visibleAssigneeAvailability {
    if (_assigneeAvailability.isNotEmpty) {
      return _assigneeAvailability;
    }
    final fallback = widget.members
        .map((member) => ShiftAssigneeAvailability(member: member))
        .toList(growable: false)
      ..sort(
        (a, b) => a.member.displayName.compareTo(b.member.displayName),
      );
    return fallback;
  }

  DateTime get _selectedStartDateTime => DateTime(
        _date.year,
        _date.month,
        _date.day,
        _startTime.hour,
        _startTime.minute,
      );

  DateTime get _selectedEndDateTime => DateTime(
        _date.year,
        _date.month,
        _date.day,
        _endTime.hour,
        _endTime.minute,
      );

  DateTime _dateTimeFor(TimeOfDay time) => DateTime(
        _date.year,
        _date.month,
        _date.day,
        time.hour,
        time.minute,
      );

  void _addAdditionalAssignment() {
    _setDirty(() {
      _additionalAssignments = [
        ..._additionalAssignments,
        _AdditionalShiftAssignmentDraft(
          id: _nextAdditionalAssignmentDraftId++,
          startTime: _startTime,
          endTime: _endTime,
          breakMinutes: _parseBreakMinutes(),
        ),
      ];
    });
  }

  void _removeAdditionalAssignment(int draftId) {
    _setDirty(() {
      _additionalAssignments = _additionalAssignments
          .where((draft) => draft.id != draftId)
          .toList(growable: false);
    });
  }

  void _updateAdditionalAssignment(
    int draftId,
    _AdditionalShiftAssignmentDraft Function(
      _AdditionalShiftAssignmentDraft draft,
    ) update,
  ) {
    _setDirty(() {
      _additionalAssignments = _additionalAssignments
          .map((draft) => draft.id == draftId ? update(draft) : draft)
          .toList(growable: false);
    });
  }

  Future<void> _pickAdditionalStart(int draftId) async {
    final draft = _additionalAssignments
        .where((candidate) => candidate.id == draftId)
        .firstOrNull;
    if (draft == null) {
      return;
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: draft.startTime,
    );
    if (picked == null) {
      return;
    }
    _updateAdditionalAssignment(
      draftId,
      (currentDraft) => currentDraft.copyWith(startTime: picked),
    );
  }

  Future<void> _pickAdditionalEnd(int draftId) async {
    final draft = _additionalAssignments
        .where((candidate) => candidate.id == draftId)
        .firstOrNull;
    if (draft == null) {
      return;
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: draft.endTime,
    );
    if (picked == null) {
      return;
    }
    _updateAdditionalAssignment(
      draftId,
      (currentDraft) => currentDraft.copyWith(endTime: picked),
    );
  }

  Future<void> _refreshAssigneeAvailability() async {
    if (_saveAsUnassigned) {
      setState(() {
        _loadingAvailability = false;
        _assigneeAvailability = const [];
      });
      return;
    }
    final requestId = ++_availabilityRequestId;
    final startTime = _selectedStartDateTime;
    final endTime = _selectedEndDateTime;

    if (!endTime.isAfter(startTime) || widget.members.isEmpty) {
      if (!mounted || requestId != _availabilityRequestId) {
        return;
      }
      setState(() {
        _loadingAvailability = false;
        _assigneeAvailability = widget.members
            .map((member) => ShiftAssigneeAvailability(member: member))
            .toList(growable: false);
      });
      return;
    }

    setState(() => _loadingAvailability = true);

    try {
      final availability =
          await context.read<ScheduleProvider>().loadAssigneeAvailability(
                members: widget.members,
                startTime: startTime,
                endTime: endTime,
                breakMinutes: _parseBreakMinutes(),
                siteId: _selectedSiteId,
                siteName: _locationCtrl.text.trim().isEmpty
                    ? null
                    : _locationCtrl.text.trim(),
                requiredQualificationIds:
                    _requiredQualificationIds.toList(growable: false),
                shiftTitle: _titleCtrl.text.trim(),
                excludeShiftId: widget.shift?.id,
              );
      if (!mounted || requestId != _availabilityRequestId) {
        return;
      }
      setState(() {
        _loadingAvailability = false;
        _assigneeAvailability = availability;
        _selectedUserIds.removeWhere(
          (userId) => availability.any(
            (entry) => entry.member.uid == userId && !entry.isAvailable,
          ),
        );
      });
    } catch (error) {
      if (!mounted || requestId != _availabilityRequestId) {
        return;
      }
      setState(() => _loadingAvailability = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Verfuegbarkeiten konnten nicht geladen werden: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  double _parseBreakMinutes() {
    return _parseBreakMinutesValue(_breakCtrl.text);
  }

  double _parseBreakMinutesValue(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
  }
}

class _AdditionalShiftAssignmentCard extends StatelessWidget {
  const _AdditionalShiftAssignmentCard({
    super.key,
    required this.index,
    required this.draft,
    required this.members,
    required this.onMemberChanged,
    required this.onRemove,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onBreakChanged,
  });

  final int index;
  final _AdditionalShiftAssignmentDraft draft;
  final List<AppUserProfile> members;
  final ValueChanged<String?> onMemberChanged;
  final VoidCallback onRemove;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final ValueChanged<String> onBreakChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedMember = members
        .where((candidate) => candidate.uid == draft.memberId)
        .firstOrNull;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Zusatzbesetzung ${index + 1}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (selectedMember != null)
                      _EditorCountBadge(
                        label: selectedMember.role.label,
                        tone: _EditorBadgeTone.neutral,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Zusatzbesetzung entfernen',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: draft.memberId,
            decoration: const InputDecoration(
              labelText: 'Mitarbeiter',
              prefixIcon: Icon(Icons.person_outline),
            ),
            items: [
              for (final member in members)
                DropdownMenuItem(
                  value: member.uid,
                  child: Text(member.displayName),
                ),
            ],
            onChanged: onMemberChanged,
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.login),
                  title: const Text('Beginn'),
                  trailing: Text(draft.startTime.format(context)),
                  onTap: onPickStart,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Ende'),
                  trailing: Text(draft.endTime.format(context)),
                  onTap: onPickEnd,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('additional-break-${draft.id}'),
            initialValue: _formatBreakMinutes(draft.breakMinutes),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Pause in Minuten',
              prefixIcon: Icon(Icons.coffee_outlined),
            ),
            onChanged: onBreakChanged,
          ),
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

class _AssigneeAvailabilityTile extends StatelessWidget {
  const _AssigneeAvailabilityTile({
    required this.availability,
    this.title,
  });

  final ShiftAssigneeAvailability availability;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    final reasons = _buildAssigneeAvailabilityReasons(availability);
    final hasBlocking = reasons.any(
      (reason) => reason.tone == _AvailabilityReasonTone.blocking,
    );
    final accent = hasBlocking ? colorScheme.error : appColors.warning;
    final accentContainer =
        hasBlocking ? colorScheme.errorContainer : appColors.warningContainer;
    final onAccentContainer = hasBlocking
        ? colorScheme.onErrorContainer
        : appColors.onWarningContainer;
    final blockingViolationCount = availability.blockingViolations.length;
    final warningCount = availability.warningViolations.length;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                title!,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: accent,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Padding(
            padding: EdgeInsets.fromLTRB(16, title == null ? 16 : 0, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: accentContainer.withValues(alpha: 0.9),
                  foregroundColor: onAccentContainer,
                  child: Text(
                    _initialsForName(availability.member.displayName),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: onAccentContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        availability.member.displayName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        availability.member.role.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _EditorCountBadge(
                  label: hasBlocking ? 'Blockiert' : 'Warnung',
                  tone: hasBlocking
                      ? _EditorBadgeTone.error
                      : _EditorBadgeTone.warning,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (availability.conflictingShifts.isNotEmpty)
                  _AvailabilityMetaChip(
                    icon: Icons.schedule_outlined,
                    label:
                        '${availability.conflictingShifts.length} Schicht${availability.conflictingShifts.length == 1 ? '' : 'en'}',
                  ),
                if (availability.blockingAbsences.isNotEmpty)
                  _AvailabilityMetaChip(
                    icon: Icons.event_busy_outlined,
                    label:
                        '${availability.blockingAbsences.length} Abwesenheit${availability.blockingAbsences.length == 1 ? '' : 'en'}',
                  ),
                if (blockingViolationCount > 0)
                  _AvailabilityMetaChip(
                    icon: Icons.gpp_bad_outlined,
                    label:
                        '$blockingViolationCount Regel${blockingViolationCount == 1 ? '' : 'n'} blockiert',
                  ),
                if (warningCount > 0)
                  _AvailabilityMetaChip(
                    icon: Icons.warning_amber_rounded,
                    label:
                        '$warningCount Hinweis${warningCount == 1 ? '' : 'e'}',
                  ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: accent.withValues(alpha: 0.18),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              children: [
                for (var i = 0; i < reasons.length; i++) ...[
                  _AvailabilityReasonRow(reason: reasons[i]),
                  if (i < reasons.length - 1) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
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

class _AvailabilityMetaChip extends StatelessWidget {
  const _AvailabilityMetaChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityReasonRow extends StatelessWidget {
  const _AvailabilityReasonRow({required this.reason});

  final _AvailabilityReason reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    final isBlocking = reason.tone == _AvailabilityReasonTone.blocking;
    final background = isBlocking
        ? colorScheme.errorContainer.withValues(alpha: 0.72)
        : appColors.warningContainer.withValues(alpha: 0.72);
    final foreground = isBlocking
        ? colorScheme.onErrorContainer
        : appColors.onWarningContainer;
    final accent = isBlocking ? colorScheme.error : appColors.warning;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              reason.icon,
              size: 18,
              color: accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reason.message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: foreground,
              ),
            ),
          ),
        ],
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
            value: DateFormat('dd.MM.yyyy').format(_startDate),
            icon: Icons.event_available_outlined,
            onTap: () => _pickDate(true),
          ),
          const SizedBox(height: 12),
          _DateTile(
            label: 'Bis',
            value: DateFormat('dd.MM.yyyy').format(_endDate),
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
