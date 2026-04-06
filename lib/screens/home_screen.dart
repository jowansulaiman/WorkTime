import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/employee_site_assignment.dart';
import '../models/site_definition.dart';
import '../models/shift.dart';
import '../models/work_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/storage_mode_provider.dart';
import '../providers/team_provider.dart';
import '../providers/work_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/responsive_layout.dart';
import 'entry_form_screen.dart';
import 'month_report_screen.dart';
import 'notification_screen.dart';
import 'settings_screen.dart';
import 'shift_planner_screen.dart';
import 'statistics_screen.dart';
import 'team_management_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;
  final Set<_ShellDestinationId> _loadedDestinations = {
    _ShellDestinationId.today,
  };
  final List<_ShellDestinationId> _navHistory = [];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final work = context.watch<WorkProvider>();
    final schedule = context.watch<ScheduleProvider>();
    final storage = context.watch<StorageModeProvider>();
    final currentUser = auth.profile;
    final canManageShifts = currentUser?.canManageShifts ?? false;
    final authDisabled = auth.authDisabled;
    final destinations = _buildDestinations(currentUser);
    final selectedIndex = _navIndex.clamp(0, destinations.length - 1);
    final currentDestination = destinations[selectedIndex];
    final railDestinations = destinations
        .where((destination) => destination.id != _ShellDestinationId.profile)
        .toList(growable: false);
    final railSelectedIndex = railDestinations.indexWhere(
      (destination) => destination.id == currentDestination.id,
    );

    return PopScope<void>(
      canPop: _navHistory.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        _navigateBackInShell(destinations: destinations);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useRail = constraints.maxWidth >= 1120;
          final body = _LazyDestinationStack(
            selectedId: currentDestination.id,
            loadedDestinations: _loadedDestinations,
            destinations: destinations,
          );
          final shellContent = Column(
            children: [
              SafeArea(
                bottom: false,
                child: _ShellStatusBanner(
                  storageLocation: authDisabled
                      ? DataStorageLocation.local
                      : storage.location,
                  work: work,
                  schedule: schedule,
                ),
              ),
              Expanded(child: body),
            ],
          );

          return Scaffold(
            body: useRail
                ? SafeArea(
                    child: Row(
                      children: [
                        NavigationRail(
                          selectedIndex: railSelectedIndex == -1
                              ? null
                              : railSelectedIndex,
                          onDestinationSelected: (index) =>
                              _handleDestinationTap(
                            index,
                            destinations: railDestinations,
                          ),
                          labelType: NavigationRailLabelType.all,
                          leading: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AppLogo(height: 38),
                                const SizedBox(height: 12),
                                _RailProfileHeader(
                                  user: auth.profile,
                                  isSelected: currentDestination.id ==
                                      _ShellDestinationId.profile,
                                  onTap: () => _activateDestination(
                                    _ShellDestinationId.profile,
                                    destinations: destinations,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: IconButton(
                              tooltip:
                                  authDisabled ? 'Profil wechseln' : 'Abmelden',
                              onPressed: () =>
                                  context.read<AuthProvider>().signOut(),
                              icon: const Icon(Icons.logout),
                            ),
                          ),
                          destinations: [
                            for (final destination in railDestinations)
                              NavigationRailDestination(
                                icon: Icon(destination.icon),
                                selectedIcon: Icon(destination.selectedIcon),
                                label: Text(destination.label),
                              ),
                          ],
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: shellContent),
                      ],
                    ),
                  )
                : shellContent,
            bottomNavigationBar: useRail
                ? null
                : NavigationBar(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: (index) => _handleDestinationTap(
                      index,
                      destinations: destinations,
                    ),
                    destinations: [
                      for (final destination in destinations)
                        NavigationDestination(
                          icon: Icon(destination.icon),
                          selectedIcon: Icon(destination.selectedIcon),
                          label: destination.label,
                        ),
                    ],
                  ),
            floatingActionButton: _buildFab(
              context,
              destination: currentDestination,
              canManageShifts: canManageShifts,
              destinations: destinations,
              work: work,
            ),
          );
        },
      ),
    );
  }

  _ShellDestinationId _currentDestinationId(
      List<_ShellDestination> destinations) {
    final selectedIndex = _navIndex.clamp(0, destinations.length - 1);
    return destinations[selectedIndex].id;
  }

  void _activateDestination(
    _ShellDestinationId id, {
    required List<_ShellDestination> destinations,
    bool recordHistory = true,
  }) {
    if (!mounted) {
      return;
    }

    final index =
        destinations.indexWhere((destination) => destination.id == id);
    if (index == -1) {
      return;
    }

    final currentId = _currentDestinationId(destinations);
    if (recordHistory && currentId != id) {
      _navHistory.add(currentId);
    }

    if (_navIndex == index) {
      return;
    }

    setState(() {
      _navIndex = index;
      _loadedDestinations.add(destinations[index].id);
    });
  }

  bool _navigateBackInShell({List<_ShellDestination>? destinations}) {
    final resolvedDestinations = destinations ??
        _buildDestinations(
          context.read<AuthProvider>().profile,
        );
    final currentId = _currentDestinationId(resolvedDestinations);

    while (_navHistory.isNotEmpty) {
      final previousId = _navHistory.removeLast();
      final index = resolvedDestinations
          .indexWhere((destination) => destination.id == previousId);
      if (index == -1 || previousId == currentId) {
        continue;
      }
      if (!mounted) {
        return false;
      }
      setState(() {
        _navIndex = index;
        _loadedDestinations.add(previousId);
      });
      return true;
    }

    return false;
  }

  void _handleShellBackPressed() {
    _navigateBackInShell();
  }

  void _handleDestinationTap(
    int index, {
    required List<_ShellDestination> destinations,
  }) {
    _activateDestination(
      destinations[index].id,
      destinations: destinations,
    );
  }

  Future<void> _openPlanDestination() async {
    await _activatePlanDestination();
  }

  Future<void> _openPlanDestinationForDate(DateTime focusDate) async {
    await _activatePlanDestination(focusDate: focusDate);
  }

  Future<void> _activatePlanDestination({DateTime? focusDate}) async {
    if (!mounted) {
      return;
    }
    final currentUser = context.read<AuthProvider>().profile;
    if (!(currentUser?.canViewSchedule ?? false)) {
      return;
    }

    final destinations = _buildDestinations(currentUser);
    final index = destinations.indexWhere(
        (destination) => destination.id == _ShellDestinationId.plan);
    if (index == -1) {
      return;
    }

    final schedule = context.read<ScheduleProvider>();
    final normalizedFocusDate =
        focusDate == null ? null : DateUtils.dateOnly(focusDate);
    if (normalizedFocusDate != null &&
        schedule.viewMode != ScheduleViewMode.day) {
      schedule.setViewMode(ScheduleViewMode.day);
    }
    if (normalizedFocusDate != null &&
        !DateUtils.isSameDay(schedule.visibleDate, normalizedFocusDate)) {
      schedule.setVisibleDate(normalizedFocusDate);
    }

    if (!mounted) {
      return;
    }

    _activateDestination(
      _ShellDestinationId.plan,
      destinations: destinations,
    );
  }

  Widget? _buildFab(
    BuildContext context, {
    required _ShellDestination destination,
    required bool canManageShifts,
    required List<_ShellDestination> destinations,
    required WorkProvider work,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;

    if (!destination.showFab) {
      return null;
    }

    final canEditTimeEntries = work.currentUser?.canEditTimeEntries ?? false;
    final actionsFab = canManageShifts
        ? FloatingActionButton.extended(
            heroTag: 'shell_actions_fab',
            onPressed: () => _showPlannerQuickActions(
              destinations,
              currentDestinationLabel: destination.label,
            ),
            icon: const Icon(Icons.bolt),
            label: const Text('Aktionen'),
          )
        : FloatingActionButton.extended(
            heroTag: 'shell_actions_fab',
            onPressed: () => _showEmployeeQuickActions(
              currentDestinationLabel: destination.label,
            ),
            icon: const Icon(Icons.bolt),
            label: const Text('Schnell'),
          );

    if (!canEditTimeEntries) {
      return actionsFab;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton(
          heroTag: 'shell_punch_clock_fab',
          tooltip: work.hasActiveClockSession
              ? 'Stempeluhr oeffnen und ausstempeln'
              : 'Stempeluhr oeffnen',
          onPressed:
              work.currentUser == null ? null : () => _showPunchClockSheet(),
          backgroundColor: work.hasActiveClockSession
              ? colorScheme.error
              : appColors.success,
          foregroundColor: work.hasActiveClockSession
              ? colorScheme.onError
              : appColors.onSuccess,
          child: Icon(
            work.hasActiveClockSession
                ? Icons.logout_rounded
                : Icons.login_rounded,
          ),
        ),
        const SizedBox(height: 12),
        actionsFab,
      ],
    );
  }

  Future<void> _showPunchClockSheet() async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _PunchClockSheet(),
    );
  }

  Future<void> _pushTeamManagement({required String parentLabel}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamManagementScreen(parentLabel: parentLabel),
      ),
    );
  }

  Future<void> _pushMonthReport({required String parentLabel}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MonthReportScreen(parentLabel: parentLabel),
      ),
    );
  }

  Future<void> _pushEntryForm({
    required String parentLabel,
    WorkEntry? entry,
    DateTime? initialDate,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EntryFormScreen(
          entry: entry,
          initialDate: initialDate,
          parentLabel: parentLabel,
        ),
      ),
    );
  }

  Future<void> _showPlannerQuickActions(
    List<_ShellDestination> destinations, {
    required String currentDestinationLabel,
  }) async {
    if (!mounted) {
      return;
    }
    final currentUser = context.read<AuthProvider>().profile;
    final hasTimeDestination = destinations.any(
      (destination) => destination.id == _ShellDestinationId.time,
    );
    final hasInboxDestination = destinations.any(
      (destination) => destination.id == _ShellDestinationId.inbox,
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Schnellaktionen',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Wechsle direkt in die aktuelle Arbeitsansicht.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 18),
                  if (hasTimeDestination)
                    _QuickActionListTile(
                      icon: Icons.schedule_outlined,
                      title: 'Zeiterfassung und Stunden',
                      subtitle:
                          'Eigene Zeiten, Monat und Korrekturen direkt oeffnen',
                      onTap: () => _jumpToDestination(
                        _ShellDestinationId.time,
                        destinations: destinations,
                      ),
                    ),
                  if (hasInboxDestination)
                    _QuickActionListTile(
                      icon: Icons.inbox_outlined,
                      title: 'Offene Anfragen pruefen',
                      subtitle:
                          'Krankmeldungen, Urlaub und Tausch sofort sehen',
                      onTap: () => _jumpToDestination(
                        _ShellDestinationId.inbox,
                        destinations: destinations,
                      ),
                    ),
                  if (currentUser?.isTeamLead ?? false)
                    _QuickActionListTile(
                      icon: Icons.local_hospital_outlined,
                      title: 'Krankmeldung an Admin',
                      subtitle: 'Eigene Krankmeldung direkt absenden',
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await showAbsenceRequestSheet(
                          context,
                          defaultType: AbsenceType.sickness,
                          initialStart: DateTime.now(),
                          initialEnd: DateTime.now(),
                        );
                      },
                    ),
                  if (currentUser?.isTeamLead ?? false)
                    _QuickActionListTile(
                      icon: Icons.beach_access_outlined,
                      title: 'Urlaub anfragen',
                      subtitle: 'Eigene Urlaubsanfrage direkt an den Admin',
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await showAbsenceRequestSheet(
                          context,
                          defaultType: AbsenceType.vacation,
                          initialStart: DateTime.now(),
                          initialEnd: DateTime.now(),
                        );
                      },
                    ),
                  if (currentUser?.isTeamLead ?? false)
                    _QuickActionListTile(
                      icon: Icons.block_outlined,
                      title: 'Nicht verfuegbar',
                      subtitle: 'Weitere Abwesenheit an den Admin senden',
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await showAbsenceRequestSheet(
                          context,
                          defaultType: AbsenceType.unavailable,
                          initialStart: DateTime.now(),
                          initialEnd: DateTime.now(),
                        );
                      },
                    ),
                  _QuickActionListTile(
                    icon: Icons.groups_outlined,
                    title: 'Teamverwaltung',
                    subtitle: 'Standorte, Qualifikationen und Rollen pflegen',
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await _pushTeamManagement(
                        parentLabel: currentDestinationLabel,
                      );
                    },
                  ),
                  if (currentUser?.canViewReports ?? false)
                    _QuickActionListTile(
                      icon: Icons.description_outlined,
                      title: 'Monatsbericht',
                      subtitle: 'PDF und Monatsauswertung direkt aufrufen',
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await _pushMonthReport(
                          parentLabel: currentDestinationLabel,
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showEmployeeQuickActions({
    required String currentDestinationLabel,
  }) async {
    if (!mounted) {
      return;
    }
    final currentUser = context.read<AuthProvider>().profile;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Schnellaktionen',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Die haeufigsten Aufgaben direkt mit einer Hand ausloesen.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 18),
                  if (currentUser?.canEditTimeEntries ?? false)
                    _QuickActionListTile(
                      icon: Icons.edit_calendar_outlined,
                      title: 'Arbeitszeit erfassen',
                      subtitle: 'Manuellen Eintrag anlegen oder korrigieren',
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await _pushEntryForm(
                          parentLabel: currentDestinationLabel,
                        );
                      },
                    ),
                  _QuickActionListTile(
                    icon: Icons.local_hospital_outlined,
                    title: 'Krank melden',
                    subtitle: 'Heute oder morgen in 2 Schritten absenden',
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await showAbsenceRequestSheet(
                        context,
                        defaultType: AbsenceType.sickness,
                        initialStart: DateTime.now(),
                        initialEnd: DateTime.now(),
                      );
                    },
                  ),
                  _QuickActionListTile(
                    icon: Icons.beach_access_outlined,
                    title: 'Urlaub anfragen',
                    subtitle:
                        'Antrag direkt aus der mobilen Schnellaktion stellen',
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await showAbsenceRequestSheet(
                        context,
                        defaultType: AbsenceType.vacation,
                        initialStart: DateTime.now(),
                        initialEnd: DateTime.now(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _jumpToDestination(
    _ShellDestinationId id, {
    required List<_ShellDestination> destinations,
  }) {
    final index =
        destinations.indexWhere((destination) => destination.id == id);
    if (index == -1) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop();
    _activateDestination(
      id,
      destinations: destinations,
    );
  }

  List<_ShellDestination> _buildDestinations(AppUserProfile? user) {
    final canNavigateBack = _navHistory.isNotEmpty;
    final canManageShifts = user?.canManageShifts ?? false;
    final canViewSchedule = user?.canViewSchedule ?? false;
    final canViewTimeTracking = user?.canViewTimeTracking ?? false;
    final items = <_ShellDestination>[
      _ShellDestination(
        id: _ShellDestinationId.today,
        label: 'Heute',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        child: canManageShifts
            ? _AdminDashboardTab(
                onOpenPlan: _openPlanDestination,
                onOpenPlanForDate: _openPlanDestinationForDate,
                canNavigateBack: canNavigateBack,
                onNavigateBack: _handleShellBackPressed,
              )
            : _EmployeeDashboardTab(
                canNavigateBack: canNavigateBack,
                onNavigateBack: _handleShellBackPressed,
              ),
        showFab: true,
      ),
      if (canViewSchedule)
        _ShellDestination(
          id: _ShellDestinationId.plan,
          label: 'Plan',
          icon: Icons.view_timeline_outlined,
          selectedIcon: Icons.view_timeline,
          child: ShiftPlannerScreen(
            canNavigateBack: canNavigateBack,
            onNavigateBack: _handleShellBackPressed,
          ),
          showFab: true,
        ),
      if (canViewTimeTracking)
        _ShellDestination(
          id: _ShellDestinationId.time,
          label: 'Zeit',
          icon: Icons.schedule_outlined,
          selectedIcon: Icons.schedule,
          child: _TimeTrackingTab(
            canNavigateBack: canNavigateBack,
            onNavigateBack: _handleShellBackPressed,
          ),
          showFab: true,
        ),
      _ShellDestination(
        id: _ShellDestinationId.inbox,
        label: 'Anfragen',
        icon: Icons.inbox_outlined,
        selectedIcon: Icons.inbox,
        child: NotificationScreen(
          canNavigateBack: canNavigateBack,
          onNavigateBack: _handleShellBackPressed,
        ),
        showFab: true,
      ),
      _ShellDestination(
        id: _ShellDestinationId.profile,
        label: 'Profil',
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        child: _ProfileHubTab(
          canNavigateBack: canNavigateBack,
          onNavigateBack: _handleShellBackPressed,
        ),
      ),
    ];

    return items;
  }
}

bool _isPlannedShift(Shift shift) {
  return !shift.isUnassigned && shift.status != ShiftStatus.cancelled;
}

int _calendarDayKey(DateTime value) {
  return value.year * 10000 + value.month * 100 + value.day;
}

double _sumShiftHours(Iterable<Shift> shifts) {
  return shifts.fold<double>(0, (sum, shift) => sum + shift.workedHours);
}

double _sumEntryHours(Iterable<WorkEntry> entries) {
  return entries.fold<double>(0, (sum, entry) => sum + entry.workedHours);
}

String _formatSignedHours(double value) {
  final prefix = value > 0.05 ? '+' : '';
  return '$prefix${value.toStringAsFixed(1)} h';
}

List<Shift> _shiftsForDay(Iterable<Shift> shifts, DateTime day) {
  return shifts
      .where(
          (shift) => _isPlannedShift(shift) && isSameDay(shift.startTime, day))
      .toList(growable: false)
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
}

Map<String, List<WorkEntry>> _entriesBySourceShiftId(
    Iterable<WorkEntry> entries) {
  final map = <String, List<WorkEntry>>{};
  for (final entry in entries) {
    final shiftId = entry.sourceShiftId?.trim();
    if (shiftId == null || shiftId.isEmpty) {
      continue;
    }
    (map[shiftId] ??= <WorkEntry>[]).add(entry);
  }
  for (final linkedEntries in map.values) {
    linkedEntries.sort((a, b) => a.startTime.compareTo(b.startTime));
  }
  return map;
}

class _ShellDestination {
  const _ShellDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.child,
    this.showFab = false,
  });

  final _ShellDestinationId id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget child;
  final bool showFab;
}

enum _ShellDestinationId { today, plan, time, inbox, profile }

class _RailProfileHeader extends StatelessWidget {
  const _RailProfileHeader({
    required this.user,
    required this.isSelected,
    required this.onTap,
  });

  final AppUserProfile? user;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 96,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.secondaryContainer
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? colorScheme.secondary
                  : colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 24,
                child: Text(
                  user?.displayName.characters.first.toUpperCase() ?? '?',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                user?.role.label ?? '',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isSelected ? Icons.person : Icons.person_outline,
                    size: 18,
                    color: isSelected
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Profil',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? colorScheme.onSecondaryContainer
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LazyDestinationStack extends StatelessWidget {
  const _LazyDestinationStack({
    required this.selectedId,
    required this.loadedDestinations,
    required this.destinations,
  });

  final _ShellDestinationId selectedId;
  final Set<_ShellDestinationId> loadedDestinations;
  final List<_ShellDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final destination in destinations)
          Offstage(
            offstage: destination.id != selectedId,
            child: TickerMode(
              enabled: destination.id == selectedId,
              child: loadedDestinations.contains(destination.id)
                  ? destination.child
                  : const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }
}

Future<void> _showShiftDetailsSheet(
  BuildContext context, {
  required Shift shift,
  required bool isPlanner,
  Future<void> Function(DateTime focusDate)? onOpenPlanForDate,
}) async {
  final colorScheme = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    shift.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                _ShiftStatusBadge(status: shift.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${DateFormat('EEEE, dd.MM.yyyy', 'de_DE').format(shift.startTime)} · '
              '${DateFormat('HH:mm').format(shift.startTime)} - ${DateFormat('HH:mm').format(shift.endTime)}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.storefront_outlined,
                  label: shift.effectiveSiteLabel ?? 'Standort offen',
                ),
                _InfoChip(
                  icon: Icons.person_outline,
                  label: shift.employeeName,
                ),
                _InfoChip(
                  icon: Icons.hourglass_bottom_outlined,
                  label:
                      '${shift.workedHours.toStringAsFixed(1)} h inkl. ${shift.breakMinutes.toStringAsFixed(0)} min Pause',
                ),
              ],
            ),
            if (shift.notes?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(shift.notes!.trim()),
              ),
            ],
            const SizedBox(height: 18),
            if (isPlanner)
              FilledButton.icon(
                onPressed: onOpenPlanForDate == null
                    ? null
                    : () async {
                        Navigator.of(sheetContext).pop();
                        await Future<void>.delayed(Duration.zero);
                        await onOpenPlanForDate(shift.startTime);
                      },
                icon: const Icon(Icons.view_timeline),
                label: const Text('Im Schichtplan bearbeiten'),
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (shift.id != null && shift.swapStatus == null)
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await context
                            .read<ScheduleProvider>()
                            .requestShiftSwap(shift.id!);
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Tausch-Anfrage gesendet'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Tausch anfragen'),
                    ),
                  FilledButton.icon(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await showAbsenceRequestSheet(
                        context,
                        defaultType: AbsenceType.sickness,
                        initialStart: shift.startTime,
                        initialEnd: shift.endTime,
                      );
                    },
                    icon: const Icon(Icons.local_hospital_outlined),
                    label: const Text('Krank melden'),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}

class _ShellStatusBanner extends StatelessWidget {
  const _ShellStatusBanner({
    required this.storageLocation,
    required this.work,
    required this.schedule,
  });

  final DataStorageLocation storageLocation;
  final WorkProvider work;
  final ScheduleProvider schedule;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final String? text;
    final IconData icon;
    final Color color;

    if (storageLocation == DataStorageLocation.local) {
      text =
          'Lokaler Modus aktiv. Daten werden nicht mit Firebase synchronisiert.';
      icon = Icons.cloud_off_outlined;
      color = colorScheme.secondary;
    } else if (work.errorMessage != null || schedule.errorMessage != null) {
      text = work.errorMessage ?? schedule.errorMessage;
      icon = Icons.sync_problem_outlined;
      color = colorScheme.error;
    } else if (work.loading || schedule.loading) {
      text = 'Daten werden aktualisiert.';
      icon = Icons.sync;
      color = colorScheme.primary;
    } else {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionListTile extends StatelessWidget {
  const _QuickActionListTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        minVerticalPadding: 14,
        leading: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.primaryContainer.withValues(
                    alpha: 0.7,
                  ),
          child: Icon(icon),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.surface,
              colorScheme.surfaceContainerLow,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: colorScheme.primary),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: colorScheme.onSurfaceVariant,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionStateTile extends StatelessWidget {
  const _ActionStateTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmployeeHeroCard extends StatelessWidget {
  const _EmployeeHeroCard({
    required this.nextShift,
    required this.provider,
  });

  final Shift? nextShift;
  final WorkProvider provider;

  @override
  Widget build(BuildContext context) {
    final team = context.watch<TeamProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final nextShift = this.nextShift;
    final activeShift = provider.activeShiftNow;
    final isClockActive = provider.hasActiveClockSession;
    final primaryAssignment =
        _resolvePrimaryAssignment(team, provider.currentUser?.uid);
    final primarySite = _resolvePrimarySite(
      team.sites.isNotEmpty ? team.sites : provider.sites,
      primaryAssignment,
    );
    final canStartClock = primaryAssignment != null && activeShift != null;
    final canUseClock = isClockActive || canStartClock;
    final siteLabel = primarySite?.name ??
        primaryAssignment?.siteName ??
        'Kein Standort hinterlegt';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nextShift == null
                  ? 'Heute ohne geplante Schicht'
                  : 'Naechste Schicht',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            if (nextShift == null)
              Text(
                primaryAssignment != null
                    ? 'Arbeitszeit kann nur waehrend einer geplanten Schicht erfasst werden.'
                    : 'Zum Einstempeln fehlt aktuell ein zugewiesener Standort.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              )
            else ...[
              Text(
                '${DateFormat('EEEE, dd.MM.', 'de_DE').format(nextShift.startTime)} · '
                '${DateFormat('HH:mm').format(nextShift.startTime)} - ${DateFormat('HH:mm').format(nextShift.endTime)}',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    icon: Icons.storefront_outlined,
                    label: nextShift.effectiveSiteLabel ?? 'Standort offen',
                  ),
                  _InfoChip(
                    icon: Icons.badge_outlined,
                    label: nextShift.title,
                  ),
                  _InfoChip(
                    icon: Icons.hourglass_bottom_outlined,
                    label: '${nextShift.workedHours.toStringAsFixed(1)} h',
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: !canUseClock
                      ? null
                      : () => _handlePunchClockAction(context, provider),
                  icon: Icon(
                    isClockActive ? Icons.stop_circle : Icons.play_circle,
                  ),
                  label: Text(
                    isClockActive ? 'Ausstempeln' : 'Einstempeln',
                  ),
                  style: isClockActive
                      ? FilledButton.styleFrom(
                          backgroundColor: colorScheme.error,
                          foregroundColor: colorScheme.onError,
                        )
                      : null,
                ),
                OutlinedButton.icon(
                  onPressed: nextShift == null
                      ? null
                      : () => _showShiftDetailsSheet(
                            context,
                            shift: nextShift,
                            isPlanner: false,
                          ),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Details'),
                ),
              ],
            ),
            if (!canStartClock && !isClockActive) ...[
              const SizedBox(height: 12),
              Text(
                primaryAssignment == null
                    ? 'Bitte zuerst in der Teamverwaltung einen Primaerstandort hinterlegen.'
                    : nextShift != null &&
                            nextShift.startTime.isAfter(DateTime.now())
                        ? 'Einstempeln ist erst ab ${DateFormat('HH:mm').format(nextShift.startTime)} innerhalb deiner geplanten Schicht moeglich.'
                        : 'Aktuell liegt keine laufende Schicht fuer die Stempeluhr vor.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: primaryAssignment == null
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ] else if (nextShift == null) ...[
              const SizedBox(height: 12),
              Text(
                'Stempeluhr-Standort: $siteLabel',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmployeeWeekStrip extends StatelessWidget {
  const _EmployeeWeekStrip({
    required this.upcomingShifts,
    required this.absences,
  });

  final List<Shift> upcomingShifts;
  final List<AbsenceRequest> absences;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(
      7,
      (index) => DateTime(today.year, today.month, today.day + index),
    );

    return _SectionCard(
      title: 'Deine Woche',
      child: SizedBox(
        height: 110,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, index) {
            final day = days[index];
            final dayShifts = upcomingShifts.where((shift) {
              return shift.startTime.year == day.year &&
                  shift.startTime.month == day.month &&
                  shift.startTime.day == day.day;
            }).toList(growable: false);
            final dayAbsences = absences.where((absence) {
              return absence.overlaps(day, day.add(const Duration(days: 1)));
            }).toList(growable: false);
            final hasItems = dayShifts.isNotEmpty || dayAbsences.isNotEmpty;
            final label = DateFormat('EEE', 'de_DE').format(day).toUpperCase();
            final detail = dayAbsences.isNotEmpty
                ? dayAbsences.first.type.label
                : dayShifts.isNotEmpty
                    ? DateFormat('HH:mm').format(dayShifts.first.startTime)
                    : 'Frei';
            return Container(
              width: 88,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hasItems
                    ? Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.45)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('dd.MM.').format(day),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    dayShifts.isEmpty && dayAbsences.isEmpty
                        ? 'Keine'
                        : '${dayShifts.length + dayAbsences.length} ${dayShifts.length + dayAbsences.length == 1 ? 'Eintrag' : 'Eintraege'}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemCount: days.length,
        ),
      ),
    );
  }
}

class _PlannerHeroCard extends StatelessWidget {
  const _PlannerHeroCard({
    required this.activeMembers,
    required this.todayShiftCount,
    required this.pendingAbsenceCount,
    required this.pendingSwapCount,
    required this.siteCount,
  });

  final int activeMembers;
  final int todayShiftCount;
  final int pendingAbsenceCount;
  final int pendingSwapCount;
  final int siteCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.secondaryContainer.withValues(alpha: 0.72),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filialbetrieb im Blick',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '$todayShiftCount Schichten heute in $siteCount Standorten. '
              '$pendingAbsenceCount Abwesenheiten und $pendingSwapCount Tausch-Anfragen brauchen Aufmerksamkeit.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoChip(
                  icon: Icons.people_alt_outlined,
                  label: '$activeMembers aktiv',
                ),
                _InfoChip(
                  icon: Icons.event_note_outlined,
                  label: '$pendingAbsenceCount offen',
                ),
                _InfoChip(
                  icon: Icons.swap_horiz,
                  label: '$pendingSwapCount Tausch',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagerDecisionList extends StatelessWidget {
  const _ManagerDecisionList({
    required this.pendingAbsences,
    required this.pendingSwapRequests,
  });

  final List<AbsenceRequest> pendingAbsences;
  final List<Shift> pendingSwapRequests;

  @override
  Widget build(BuildContext context) {
    if (pendingAbsences.isEmpty && pendingSwapRequests.isEmpty) {
      return const _EmptyState(
        icon: Icons.check_circle_outline,
        text: 'Keine offenen Entscheidungen. Der aktuelle Tag ist geklaert.',
      );
    }

    final items = <Widget>[
      ...pendingAbsences.take(3).map(
            (request) => _ManagerDecisionTile.absence(request: request),
          ),
      ...pendingSwapRequests.take(3).map(
            (shift) => _ManagerDecisionTile.swap(shift: shift),
          ),
    ];

    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          items[i],
          if (i < items.length - 1) const Divider(height: 20),
        ],
      ],
    );
  }
}

class _ManagerDecisionTile extends StatelessWidget {
  const _ManagerDecisionTile.absence({
    required this.request,
  })  : shift = null,
        _isAbsence = true;

  const _ManagerDecisionTile.swap({
    required this.shift,
  })  : request = null,
        _isAbsence = false;

  final AbsenceRequest? request;
  final Shift? shift;
  final bool _isAbsence;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (_isAbsence ? colorScheme.tertiary : colorScheme.primary)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            _isAbsence ? Icons.event_note_outlined : Icons.swap_horiz,
            color: _isAbsence ? colorScheme.tertiary : colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isAbsence
                    ? '${request!.employeeName} · ${request!.type.label}'
                    : '${shift!.employeeName} · Tausch-Anfrage',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                _isAbsence
                    ? '${DateFormat('dd.MM.', 'de_DE').format(request!.startDate)} - ${DateFormat('dd.MM.', 'de_DE').format(request!.endDate)}'
                    : '${shift!.title} · ${DateFormat('dd.MM. HH:mm', 'de_DE').format(shift!.startTime)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmployeeDashboardTab extends StatelessWidget {
  const _EmployeeDashboardTab({
    required this.canNavigateBack,
    this.onNavigateBack,
  });

  final bool canNavigateBack;
  final VoidCallback? onNavigateBack;

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().profile;
    final work = context.watch<WorkProvider>();
    final schedule = context.watch<ScheduleProvider>();
    final canViewSchedule = currentUser?.canViewSchedule ?? false;
    final canViewWorkEntries = (currentUser?.canViewTimeTracking ?? false) ||
        (currentUser?.canViewReports ?? false);
    final canEditTimeEntries = currentUser?.canEditTimeEntries ?? false;
    final upcomingShifts = canViewSchedule
        ? (schedule.upcomingShiftsForCurrentUser()
          ..sort((a, b) => a.startTime.compareTo(b.startTime)))
        : <Shift>[];
    final ownAbsences = schedule.allAbsenceRequests
        .where((request) =>
            currentUser == null || request.userId == currentUser.uid)
        .toList(growable: false);
    final pendingAbsences =
        ownAbsences.where((r) => r.status == AbsenceStatus.pending).toList();
    final nextShift = upcomingShifts.isEmpty ? null : upcomingShifts.first;
    final recentEntries = canViewWorkEntries
        ? (work.entries.toList()
          ..sort((a, b) => b.startTime.compareTo(a.startTime)))
        : <WorkEntry>[];
    final pendingSwapCount =
        upcomingShifts.where((shift) => shift.swapStatus == 'pending').length;

    final screenPad = MobileBreakpoints.screenPadding(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: screenPad.horizontal / 2,
              vertical: 16,
            ),
            children: [
              _HeaderSection(
                title: 'Heute',
                subtitle:
                    'Naechste Schicht, Arbeitszeit und offene Aufgaben ohne Umwege.',
                breadcrumbs: const [BreadcrumbItem(label: 'Heute')],
                onBack: canNavigateBack ? onNavigateBack : null,
              ),
              const SizedBox(height: 20),
              _EmployeeHeroCard(
                nextShift: nextShift,
                provider: work,
              ),
              const SizedBox(height: 16),
              AdaptiveCardGrid(
                minItemWidth: 180,
                children: [
                  _QuickActionCard(
                    icon: Icons.local_hospital_outlined,
                    title: 'Krank melden',
                    subtitle: 'Heute oder morgen direkt absenden',
                    onTap: () => showAbsenceRequestSheet(
                      context,
                      defaultType: AbsenceType.sickness,
                      initialStart: DateTime.now(),
                      initialEnd: DateTime.now(),
                    ),
                  ),
                  _QuickActionCard(
                    icon: Icons.beach_access_outlined,
                    title: 'Urlaub anfragen',
                    subtitle: 'Antrag ohne Umweg stellen',
                    onTap: () => showAbsenceRequestSheet(
                      context,
                      defaultType: AbsenceType.vacation,
                      initialStart: DateTime.now(),
                      initialEnd: DateTime.now(),
                    ),
                  ),
                  if (canEditTimeEntries)
                    _QuickActionCard(
                      icon: Icons.edit_calendar_outlined,
                      title: 'Zeit erfassen',
                      subtitle: 'Manuellen Eintrag anlegen oder korrigieren',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EntryFormScreen(
                            parentLabel: 'Heute',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (canViewSchedule)
                _EmployeeWeekStrip(
                  upcomingShifts: upcomingShifts,
                  absences: ownAbsences,
                ),
              const SizedBox(height: 16),
              if (pendingAbsences.isNotEmpty || pendingSwapCount > 0)
                _SectionCard(
                  title: 'Offene Aufgaben',
                  child: Column(
                    children: [
                      if (pendingAbsences.isNotEmpty)
                        _ActionStateTile(
                          icon: Icons.pending_actions,
                          title:
                              '${pendingAbsences.length} Abwesenheitsantraege offen',
                          subtitle:
                              'Deine Antraege sind eingereicht und warten auf Rueckmeldung.',
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                      if (pendingAbsences.isNotEmpty && pendingSwapCount > 0)
                        const Divider(height: 20),
                      if (pendingSwapCount > 0)
                        _ActionStateTile(
                          icon: Icons.swap_horiz,
                          title:
                              '$pendingSwapCount Tausch-Anfragen in Bearbeitung',
                          subtitle:
                              'Sobald entschieden wurde, erscheint die Rueckmeldung in Anfragen.',
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    ],
                  ),
                ),
              if (pendingAbsences.isNotEmpty || pendingSwapCount > 0)
                const SizedBox(height: 16),
              _ClockInOutWidget(provider: work),
              const SizedBox(height: 20),
              _WeeklyProgressWidget(provider: work),
              const SizedBox(height: 16),
              _MonthlyShiftSummaryCards(provider: work),
              if (pendingAbsences.isNotEmpty) ...[
                const SizedBox(height: 16),
                _PendingAbsencesWidget(absences: pendingAbsences),
              ],
              const SizedBox(height: 20),
              _SectionCard(
                title: 'Naechste Schichten',
                child: upcomingShifts.isEmpty
                    ? const _EmptyState(
                        icon: Icons.event_busy_outlined,
                        text:
                            'Keine kommenden Schichten im aktuell geladenen Zeitraum.',
                      )
                    : Column(
                        children: upcomingShifts.take(5).map((shift) {
                          return _ShiftPreviewTile(
                            shift: shift,
                            onTap: () => _showShiftDetailsSheet(
                              context,
                              shift: shift,
                              isPlanner: false,
                            ),
                          );
                        }).toList(),
                      ),
              ),
              const SizedBox(height: 20),
              _SectionCard(
                title: 'Letzte Eintraege',
                child: recentEntries.isEmpty
                    ? const _EmptyState(
                        icon: Icons.inbox_outlined,
                        text: 'Noch keine Arbeitszeiteintraege vorhanden.',
                      )
                    : Column(
                        children: recentEntries.take(5).map((entry) {
                          return _RecentEntryTile(entry: entry);
                        }).toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClockInOutWidget extends StatelessWidget {
  const _ClockInOutWidget({required this.provider});

  final WorkProvider provider;

  @override
  Widget build(BuildContext context) {
    final team = context.watch<TeamProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    final isClockedIn = provider.hasActiveClockSession;
    final durationLabel =
        _formatClockDuration(provider.effectiveClockedDuration);
    final primaryAssignment =
        _resolvePrimaryAssignment(team, provider.currentUser?.uid);
    final primarySite = _resolvePrimarySite(
      team.sites.isNotEmpty ? team.sites : provider.sites,
      primaryAssignment,
    );
    final activeShift = provider.activeShiftNow;
    final lastClockEntry = _resolveLastClockEntry(provider.entries);
    final canStartClock = primaryAssignment != null && activeShift != null;
    final canUseClock = isClockedIn || canStartClock;
    final startLabel = provider.effectiveClockStartTime != null
        ? DateFormat('HH:mm').format(provider.effectiveClockStartTime!)
        : lastClockEntry == null
            ? '--:--'
            : DateFormat('HH:mm').format(lastClockEntry.startTime);
    final endLabel = isClockedIn
        ? '--:--'
        : lastClockEntry == null
            ? '--:--'
            : DateFormat('HH:mm').format(lastClockEntry.endTime);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isClockedIn
                        ? appColors.successContainer
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    isClockedIn ? Icons.timer : Icons.timer_outlined,
                    size: 28,
                    color: isClockedIn
                        ? appColors.success
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stempeluhr',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        primarySite?.name ??
                            primaryAssignment?.siteName ??
                            'Kein Standort hinterlegt',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isClockedIn
                        ? appColors.successContainer
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isClockedIn
                        ? (provider.isClockBackedByEntry
                            ? 'Aus Eintrag aktiv'
                            : 'Im Dienst')
                        : 'Nicht aktiv',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: isClockedIn
                              ? appColors.onSuccessContainer
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ClockStatTile(
                    label: 'STARTS',
                    time: startLabel,
                    icon: Icons.login_rounded,
                    color: appColors.success,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ClockStatTile(
                    label: 'ENDS',
                    time: endLabel,
                    icon: Icons.logout_rounded,
                    color: colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isClockedIn
                    ? appColors.successContainer.withValues(alpha: 0.84)
                    : colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.75,
                      ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    durationLabel,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatClockBreakLabel(provider, lastClockEntry),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (!isClockedIn &&
                primaryAssignment != null &&
                activeShift == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  'Check-in ist nur waehrend einer laufenden Schicht moeglich.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: !canUseClock
                        ? null
                        : () => _handlePunchClockAction(context, provider),
                    icon: Icon(isClockedIn ? Icons.stop : Icons.play_arrow),
                    label: Text(isClockedIn ? 'Ausstempeln' : 'Einstempeln'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor:
                          isClockedIn ? colorScheme.error : appColors.success,
                      foregroundColor: isClockedIn
                          ? colorScheme.onError
                          : appColors.onSuccess,
                    ),
                  ),
                ),
                if (!isClockedIn && _hasRecentClockEntry(provider)) ...[
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () => _showCorrectionDialog(context, provider),
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text('Korrigieren'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                  ),
                ],
              ],
            ),
            if (!canUseClock) ...[
              const SizedBox(height: 12),
              Text(
                'Zum Einstempeln ist ein Primaerstandort erforderlich.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _hasRecentClockEntry(WorkProvider provider) {
    return provider.entries.any((e) => e.note?.contains('Stempeluhr') ?? false);
  }

  Future<void> _showCorrectionDialog(
    BuildContext context,
    WorkProvider provider,
  ) async {
    final clockEntries = provider.entries
        .where((e) => e.note?.contains('Stempeluhr') ?? false)
        .toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    if (clockEntries.isEmpty) return;
    final entry = clockEntries.first;

    final result = await showDialog<_ClockCorrectionResult>(
      context: context,
      builder: (_) => _ClockCorrectionDialog(entry: entry),
    );
    if (result == null || !context.mounted) return;

    try {
      await provider.correctClockEntry(
        entryId: entry.id!,
        correctedStart: result.start,
        correctedEnd: result.end,
        reason: result.reason,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eintrag korrigiert')),
      );
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
}

class _ClockCorrectionResult {
  const _ClockCorrectionResult({
    required this.start,
    required this.end,
    required this.reason,
  });
  final DateTime start;
  final DateTime end;
  final String reason;
}

class _ClockCorrectionDialog extends StatefulWidget {
  const _ClockCorrectionDialog({required this.entry});
  final WorkEntry entry;

  @override
  State<_ClockCorrectionDialog> createState() => _ClockCorrectionDialogState();
}

class _ClockCorrectionDialogState extends State<_ClockCorrectionDialog> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  final _reasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _startTime = TimeOfDay.fromDateTime(widget.entry.startTime);
    _endTime = TimeOfDay.fromDateTime(widget.entry.endTime);
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd.MM.yyyy', 'de_DE');
    return AlertDialog(
      title: const Text('Stempeluhr-Eintrag korrigieren'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Datum: ${dateFmt.format(widget.entry.date)}'),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.login),
              title: const Text('Start'),
              trailing: TextButton(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _startTime,
                  );
                  if (picked != null) setState(() => _startTime = picked);
                },
                child: Text(_startTime.format(context)),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout),
              title: const Text('Ende'),
              trailing: TextButton(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _endTime,
                  );
                  if (picked != null) setState(() => _endTime = picked);
                },
                child: Text(_endTime.format(context)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Begruendung (Pflicht)',
                prefixIcon: Icon(Icons.comment_outlined),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            if (_reasonCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Bitte Begruendung angeben'),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
              return;
            }
            final date = widget.entry.date;
            Navigator.of(context).pop(_ClockCorrectionResult(
              start: DateTime(
                date.year,
                date.month,
                date.day,
                _startTime.hour,
                _startTime.minute,
              ),
              end: DateTime(
                date.year,
                date.month,
                date.day,
                _endTime.hour,
                _endTime.minute,
              ),
              reason: _reasonCtrl.text.trim(),
            ));
          },
          child: const Text('Korrigieren'),
        ),
      ],
    );
  }
}

class _WeeklyProgressWidget extends StatefulWidget {
  const _WeeklyProgressWidget({required this.provider});

  final WorkProvider provider;

  @override
  State<_WeeklyProgressWidget> createState() => _WeeklyProgressWidgetState();
}

class _WeeklyProgressWidgetState extends State<_WeeklyProgressWidget> {
  Future<_WeeklyShiftProgressData>? _future;
  String? _futureKey;

  void _refreshFuture() {
    final provider = widget.provider;
    final user = provider.currentUser;
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final nextKey =
        '${user?.orgId}:${user?.uid}:${weekStart.toIso8601String()}';
    if (_futureKey == nextKey && _future != null) {
      return;
    }
    _futureKey = nextKey;
    _future = _loadWeeklyProgress(provider, weekStart);
  }

  Future<_WeeklyShiftProgressData> _loadWeeklyProgress(
    WorkProvider provider,
    DateTime weekStart,
  ) async {
    final weekEnd = weekStart.add(const Duration(days: 7));
    final results = await Future.wait<Object>([
      provider.loadShiftsForRange(
        start: weekStart,
        end: weekEnd,
      ),
      provider.loadEntriesForRange(
        start: weekStart,
        end: weekEnd,
      ),
    ]);

    final shifts = results[0] as List<Shift>;
    final entries = results[1] as List<WorkEntry>;
    final shiftIds = shifts
        .where((shift) => shift.id != null)
        .map((shift) => shift.id!)
        .toSet();
    final linkedEntries = entries.where((entry) {
      final shiftId = entry.sourceShiftId?.trim();
      return shiftId != null && shiftIds.contains(shiftId);
    }).length;

    return _WeeklyShiftProgressData(
      plannedHours: _sumShiftHours(shifts),
      actualHours: _sumEntryHours(entries),
      shiftCount: shifts.length,
      linkedEntryCount: linkedEntries,
    );
  }

  @override
  Widget build(BuildContext context) {
    _refreshFuture();
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).appColors;
    final fallbackTarget = widget.provider.settings.dailyHours * 5;

    return FutureBuilder<_WeeklyShiftProgressData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final weeklyTarget = data == null || data.plannedHours <= 0
            ? fallbackTarget
            : data.plannedHours;
        final weeklyHours = data?.actualHours ?? 0;
        final progress = weeklyTarget > 0
            ? (weeklyHours / weeklyTarget).clamp(0.0, 1.0)
            : 0.0;
        final diff = weeklyHours - weeklyTarget;
        final diffColor = diff >= 0 ? appColors.success : colorScheme.error;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.date_range,
                        color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Wochenfortschritt',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      '${weeklyHours.toStringAsFixed(1)} / ${weeklyTarget.toStringAsFixed(1)} h',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: progress >= 1.0
                        ? appColors.success
                        : colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(
                      icon: Icons.schedule_outlined,
                      label: data == null || data.shiftCount == 0
                          ? 'Kein Schichtplan'
                          : '${data.shiftCount} ${data.shiftCount == 1 ? 'Schicht' : 'Schichten'}',
                    ),
                    _InfoChip(
                      icon: Icons.link_rounded,
                      label: data == null || data.linkedEntryCount == 0
                          ? 'Noch nicht verknuepft'
                          : '${data.linkedEntryCount} verknuepft',
                    ),
                    _InfoChip(
                      icon: diff >= 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      label: _formatSignedHours(diff),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  data == null || data.plannedHours <= 0
                      ? 'Kein geplanter Wochenrahmen vorhanden. Fallback auf Sollstunden aus den Einstellungen.'
                      : 'Soll aus ${data.shiftCount} geplanten Schichten, Ist aus erfassten Arbeitszeiten.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    minHeight: 3,
                    backgroundColor: Colors.transparent,
                    color: diffColor.withValues(alpha: 0.65),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WeeklyShiftProgressData {
  const _WeeklyShiftProgressData({
    required this.plannedHours,
    required this.actualHours,
    required this.shiftCount,
    required this.linkedEntryCount,
  });

  final double plannedHours;
  final double actualHours;
  final int shiftCount;
  final int linkedEntryCount;
}

class _PendingAbsencesWidget extends StatelessWidget {
  const _PendingAbsencesWidget({required this.absences});

  final List<AbsenceRequest> absences;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateFmt = DateFormat('dd.MM.yyyy', 'de_DE');

    return Card(
      color: colorScheme.tertiaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pending_actions, color: colorScheme.tertiary),
                const SizedBox(width: 8),
                Text(
                  'Offene Abwesenheitsantraege (${absences.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...absences.take(3).map((absence) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        absence.type == AbsenceType.vacation
                            ? Icons.beach_access
                            : absence.type == AbsenceType.sickness
                                ? Icons.local_hospital
                                : Icons.block,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${absence.type.label}: '
                          '${dateFmt.format(absence.startDate)} - ${dateFmt.format(absence.endDate)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.tertiary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          absence.status.label,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colorScheme.tertiary,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _AdminDashboardTab extends StatelessWidget {
  const _AdminDashboardTab({
    required this.onOpenPlan,
    required this.onOpenPlanForDate,
    required this.canNavigateBack,
    this.onNavigateBack,
  });

  final Future<void> Function() onOpenPlan;
  final Future<void> Function(DateTime focusDate) onOpenPlanForDate;
  final bool canNavigateBack;
  final VoidCallback? onNavigateBack;

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().profile;
    final team = context.watch<TeamProvider>();
    final schedule = context.watch<ScheduleProvider>();
    final activeMembers =
        team.members.where((member) => member.isActive).length;
    final pendingAbsences = schedule.allAbsenceRequests
        .where((request) => request.status == AbsenceStatus.pending)
        .toList(growable: false);
    final pendingSwapRequests = schedule.shifts
        .where((shift) => shift.swapStatus == 'pending')
        .toList(growable: false);
    final upcomingShifts = [...schedule.shifts]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final todayStart = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final todayEnd = todayStart.add(const Duration(days: 1));
    final todayShifts = schedule.shifts.where((shift) {
      return !shift.startTime.isBefore(todayStart) &&
          shift.startTime.isBefore(todayEnd);
    }).toList(growable: false)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final unassignedToday = todayShifts.where((shift) => shift.isUnassigned);
    final completedToday = todayShifts
        .where((shift) => shift.status == ShiftStatus.completed)
        .length;
    final openToday = todayShifts
        .where((shift) =>
            shift.status != ShiftStatus.completed &&
            shift.status != ShiftStatus.cancelled &&
            !shift.isUnassigned)
        .length;
    final todaySites = todayShifts
        .map((shift) => shift.effectiveSiteLabel)
        .whereType<String>();

    final screenPad = MobileBreakpoints.screenPadding(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: screenPad.horizontal / 2,
              vertical: 16,
            ),
            children: [
              _HeaderSection(
                title: 'Heute',
                subtitle:
                    'Filialbetrieb, Ausnahmen und Entscheidungen fuer den laufenden Tag.',
                breadcrumbs: const [BreadcrumbItem(label: 'Heute')],
                onBack: canNavigateBack ? onNavigateBack : null,
              ),
              const SizedBox(height: 20),
              _PlannerHeroCard(
                activeMembers: activeMembers,
                todayShiftCount: todayShifts.length,
                pendingAbsenceCount: pendingAbsences.length,
                pendingSwapCount: pendingSwapRequests.length,
                siteCount: todaySites.toSet().length,
              ),
              const SizedBox(height: 16),
              AdaptiveCardGrid(
                minItemWidth: 180,
                children: [
                  _QuickActionCard(
                    icon: Icons.view_timeline_outlined,
                    title: 'Plan oeffnen',
                    subtitle: 'Direkt in die mobile Tagesplanung springen',
                    onTap: onOpenPlan,
                  ),
                  if (currentUser?.isAdmin ?? false)
                    _QuickActionCard(
                      icon: Icons.groups_outlined,
                      title: 'Team verwalten',
                      subtitle: 'Standorte, Rollen und Qualifikationen pflegen',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TeamManagementScreen(
                            parentLabel: 'Heute',
                          ),
                        ),
                      ),
                    ),
                  _QuickActionCard(
                    icon: Icons.inbox_outlined,
                    title: 'Anfragen pruefen',
                    subtitle:
                        'Krankmeldungen und Tausch ohne Umwege entscheiden',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotificationScreen(
                          parentLabel: 'Heute',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AdaptiveCardGrid(
                minItemWidth: 155,
                children: [
                  _DashboardMetricCard(
                    label: 'Aktive Mitarbeiter',
                    value: '$activeMembers',
                    icon: Icons.people_alt_outlined,
                  ),
                  _DashboardMetricCard(
                    label: 'Offene Einladungen',
                    value: '${team.invites.length}',
                    icon: Icons.mark_email_unread_outlined,
                  ),
                  _DashboardMetricCard(
                    label: 'Schichten heute',
                    value: '${todayShifts.length}',
                    icon: Icons.view_timeline_outlined,
                  ),
                  _DashboardMetricCard(
                    label: 'Erledigt',
                    value: '$completedToday / ${todayShifts.length}',
                    icon: Icons.check_circle_outline,
                  ),
                  _DashboardMetricCard(
                    label: 'Noch offen',
                    value: '$openToday',
                    icon: Icons.pending_actions_outlined,
                  ),
                  _DashboardMetricCard(
                    label: 'Offene Abwesenheiten',
                    value: '${pendingAbsences.length}',
                    icon: Icons.event_note_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SectionCard(
                title: 'Heute priorisieren',
                child: Column(
                  children: [
                    _ActionStateTile(
                      icon: Icons.warning_amber_rounded,
                      title:
                          '${pendingAbsences.length + pendingSwapRequests.length} Entscheidungen offen',
                      subtitle:
                          'Abwesenheiten und Tauschanfragen sollten vor der naechsten Schicht geklaert werden.',
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    const Divider(height: 20),
                    _ActionStateTile(
                      icon: Icons.person_off_outlined,
                      title:
                          '${unassignedToday.length} freie oder unbesetzte Schichten',
                      subtitle:
                          'Nicht zugewiesene Dienste fallen im Tagesbetrieb sofort auf.',
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionCard(
                title: 'Naechste Schichten',
                child: upcomingShifts.isEmpty
                    ? const _EmptyState(
                        icon: Icons.event_busy_outlined,
                        text: 'Keine Schichten im aktuellen Planungsfenster.',
                      )
                    : Column(
                        children: upcomingShifts.take(8).map((shift) {
                          return _ShiftPreviewTile(
                            shift: shift,
                            onTap: () => _showShiftDetailsSheet(
                              context,
                              shift: shift,
                              isPlanner: true,
                              onOpenPlanForDate: onOpenPlanForDate,
                            ),
                          );
                        }).toList(),
                      ),
              ),
              const SizedBox(height: 20),
              _SectionCard(
                title: 'Naechste Entscheidungen',
                child: _ManagerDecisionList(
                  pendingAbsences: pendingAbsences,
                  pendingSwapRequests: pendingSwapRequests,
                ),
              ),
              const SizedBox(height: 20),
              _TeamCalendarWidget(
                members: team.members.where((m) => m.isActive).toList(),
                shifts: schedule.shifts,
                absences: schedule.absenceRequests,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamCalendarWidget extends StatefulWidget {
  const _TeamCalendarWidget({
    required this.members,
    required this.shifts,
    required this.absences,
  });

  final List<AppUserProfile> members;
  final List<Shift> shifts;
  final List<AbsenceRequest> absences;

  @override
  State<_TeamCalendarWidget> createState() => _TeamCalendarWidgetState();
}

class _TeamCalendarWidgetState extends State<_TeamCalendarWidget> {
  late DateTime _weekStart;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final today = _startOfDay(DateTime.now());
    _weekStart = _startOfWeek(today);
    _selectedDay = today;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final today = _startOfDay(DateTime.now());
    final members = [...widget.members]
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final days =
        List.generate(7, (index) => _weekStart.add(Duration(days: index)));
    final dayKeys = days.map(_dayKey).toSet();
    final shiftsByUserDay = <String, List<Shift>>{};
    final absencesByUserDay = <String, List<AbsenceRequest>>{};

    for (final shift in widget.shifts) {
      final shiftDay = _startOfDay(shift.startTime);
      final keyPart = _dayKey(shiftDay);
      if (!dayKeys.contains(keyPart)) {
        continue;
      }
      final key = _userDayKey(shift.userId, shiftDay);
      (shiftsByUserDay[key] ??= <Shift>[]).add(shift);
    }

    for (final entries in shiftsByUserDay.values) {
      entries.sort((a, b) => a.startTime.compareTo(b.startTime));
    }

    for (final absence in widget.absences) {
      if (absence.status != AbsenceStatus.approved) {
        continue;
      }
      for (final day in days) {
        final dayStart = _startOfDay(day);
        final dayEnd = dayStart.add(const Duration(days: 1));
        if (!absence.overlaps(dayStart, dayEnd)) {
          continue;
        }
        final key = _userDayKey(absence.userId, dayStart);
        (absencesByUserDay[key] ??= <AbsenceRequest>[]).add(absence);
      }
    }

    final selectedDayStart = _startOfDay(_selectedDay);
    final selectedShifts = widget.shifts
        .where((shift) => _isSameDay(shift.startTime, selectedDayStart))
        .toList(growable: false)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final selectedAbsences = widget.absences
        .where((absence) =>
            absence.status == AbsenceStatus.approved &&
            absence.overlaps(
              selectedDayStart,
              selectedDayStart.add(const Duration(days: 1)),
            ))
        .toList(growable: false)
      ..sort((a, b) => a.employeeName.compareTo(b.employeeName));
    final onDutyMemberCount =
        selectedShifts.map((shift) => shift.userId).toSet().length;
    final absentMemberCount =
        selectedAbsences.map((absence) => absence.userId).toSet().length;
    final freeMemberCount = members.where((member) {
      final snapshot = _snapshotFor(
        member.uid,
        selectedDayStart,
        shiftsByUserDay,
        absencesByUserDay,
      );
      return snapshot.status == _TeamDayStatus.free;
    }).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Team-Kalender',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: 'Vorherige Woche',
                  onPressed: () => _moveWeek(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                TextButton(
                  onPressed: _goToCurrentWeek,
                  child: const Text('Diese Woche'),
                ),
                IconButton(
                  tooltip: 'Naechste Woche',
                  onPressed: () => _moveWeek(1),
                  icon: const Icon(Icons.chevron_right),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _formatWeekLabel(days.first, days.last),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TeamCalendarMetricPill(
                  icon: Icons.schedule_outlined,
                  label: '$onDutyMemberCount im Dienst',
                  color: colorScheme.primary,
                ),
                _TeamCalendarMetricPill(
                  icon: Icons.event_busy_outlined,
                  label: '$absentMemberCount abwesend',
                  color: colorScheme.tertiary,
                ),
                _TeamCalendarMetricPill(
                  icon: Icons.check_circle_outline,
                  label: '$freeMemberCount frei',
                  color: colorScheme.secondary,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TeamCalendarMetricPill(
                  icon: Icons.badge_outlined,
                  label: 'Schicht',
                  color: colorScheme.primary,
                  compact: true,
                ),
                _TeamCalendarMetricPill(
                  icon: Icons.beach_access,
                  label: 'Urlaub',
                  color: colorScheme.tertiary,
                  compact: true,
                ),
                _TeamCalendarMetricPill(
                  icon: Icons.local_hospital,
                  label: 'Krank',
                  color: colorScheme.error,
                  compact: true,
                ),
                _TeamCalendarMetricPill(
                  icon: Icons.block,
                  label: 'Nicht verfuegbar',
                  color: colorScheme.secondary,
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (members.isEmpty)
              const _EmptyState(
                icon: Icons.groups_outlined,
                text: 'Keine aktiven Mitarbeiter.',
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 700) {
                    return _buildMobileCalendar(
                      context,
                      members: members,
                      days: days,
                      today: today,
                      shiftsByUserDay: shiftsByUserDay,
                      absencesByUserDay: absencesByUserDay,
                    );
                  }
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Table(
                      defaultColumnWidth: const FixedColumnWidth(132),
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      columnWidths: const {
                        0: FixedColumnWidth(220),
                      },
                      border: TableBorder(
                        horizontalInside: BorderSide(
                          color:
                              colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'Mitarbeiter',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            for (final day in days)
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: _buildDayHeader(
                                  context,
                                  day,
                                  isToday: _isSameDay(day, today),
                                  isSelected: _isSameDay(day, _selectedDay),
                                ),
                              ),
                          ],
                        ),
                        for (final member in members)
                          TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: _buildMemberCell(member, days),
                              ),
                              for (final day in days)
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: _buildDayCell(
                                    context,
                                    member.uid,
                                    day,
                                    shiftsByUserDay,
                                    absencesByUserDay,
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 16),
            _buildSelectedDayDetails(
              context,
              day: selectedDayStart,
              shifts: selectedShifts,
              absences: selectedAbsences,
            ),
          ],
        ),
      ),
    );
  }

  void _moveWeek(int direction) {
    final selectedOffset =
        _selectedDay.difference(_weekStart).inDays.clamp(0, 6);
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * direction));
      _selectedDay =
          _startOfDay(_weekStart.add(Duration(days: selectedOffset)));
    });
  }

  void _goToCurrentWeek() {
    final today = _startOfDay(DateTime.now());
    setState(() {
      _weekStart = _startOfWeek(today);
      _selectedDay = today;
    });
  }

  Widget _buildMobileCalendar(
    BuildContext context, {
    required List<AppUserProfile> members,
    required List<DateTime> days,
    required DateTime today,
    required Map<String, List<Shift>> shiftsByUserDay,
    required Map<String, List<AbsenceRequest>> absencesByUserDay,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // Horizontal day selector strip
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final day in days)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _MobileDayChip(
                    day: day,
                    isToday: _isSameDay(day, today),
                    isSelected: _isSameDay(day, _selectedDay),
                    onTap: () =>
                        setState(() => _selectedDay = _startOfDay(day)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Member list for selected day
        ...members.map((member) {
          final snapshot = _snapshotFor(
            member.uid,
            _selectedDay,
            shiftsByUserDay,
            absencesByUserDay,
          );
          final palette = _paletteFor(colorScheme, snapshot.status);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    child: Text(
                      member.displayName.characters.first.toUpperCase(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.displayName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              snapshot.icon,
                              size: 14,
                              color: palette.foreground,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${snapshot.title} · ${snapshot.subtitle}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: palette.foreground,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDayHeader(
    BuildContext context,
    DateTime day, {
    required bool isToday,
    required bool isSelected,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('EEEE', 'de_DE').format(day),
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight:
                isSelected || isToday ? FontWeight.bold : FontWeight.w600,
            color: isSelected || isToday ? colorScheme.primary : null,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          DateFormat('dd.MM.', 'de_DE').format(day),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildMemberCell(AppUserProfile member, List<DateTime> days) {
    final weekEnd = days.last.add(const Duration(days: 1));
    final memberShifts = widget.shifts.where((shift) {
      return shift.userId == member.uid &&
          !shift.startTime.isBefore(days.first) &&
          shift.startTime.isBefore(weekEnd);
    }).toList(growable: false);
    final memberAbsenceDays = widget.absences.where((absence) {
      return absence.userId == member.uid &&
          absence.status == AbsenceStatus.approved &&
          absence.overlaps(days.first, weekEnd);
    }).length;
    final totalHours =
        memberShifts.fold<double>(0, (sum, shift) => sum + shift.workedHours);

    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          child: Text(member.displayName.characters.first.toUpperCase()),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                member.displayName,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                '${memberShifts.length} Schichten · ${totalHours.toStringAsFixed(1)} h'
                '${memberAbsenceDays > 0 ? ' · $memberAbsenceDays Abw.' : ''}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    String userId,
    DateTime day,
    Map<String, List<Shift>> shiftsByUserDay,
    Map<String, List<AbsenceRequest>> absencesByUserDay,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final snapshot = _snapshotFor(
      userId,
      day,
      shiftsByUserDay,
      absencesByUserDay,
    );
    final isSelected = _isSameDay(day, _selectedDay);
    final isToday = _isSameDay(day, DateTime.now());
    final palette = _paletteFor(colorScheme, snapshot.status);

    return Tooltip(
      message: snapshot.tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _selectedDay = _startOfDay(day)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 122,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : isToday
                      ? colorScheme.primary.withValues(alpha: 0.35)
                      : colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(snapshot.icon, size: 16, color: palette.foreground),
                  const SizedBox(width: 6),
                  if (isToday)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Heute',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                snapshot.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: palette.foreground,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                snapshot.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.foreground.withValues(alpha: 0.85),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _TeamDaySnapshot _snapshotFor(
    String userId,
    DateTime day,
    Map<String, List<Shift>> shiftsByUserDay,
    Map<String, List<AbsenceRequest>> absencesByUserDay,
  ) {
    final key = _userDayKey(userId, day);
    final dayAbsences = absencesByUserDay[key] ?? const [];
    final dayShifts = shiftsByUserDay[key] ?? const [];

    if (dayAbsences.isNotEmpty) {
      final type = dayAbsences.first.type;
      final status = switch (type) {
        AbsenceType.vacation => _TeamDayStatus.vacation,
        AbsenceType.sickness => _TeamDayStatus.sickness,
        AbsenceType.unavailable => _TeamDayStatus.unavailable,
      };
      return _TeamDaySnapshot(
        status: status,
        icon: switch (type) {
          AbsenceType.vacation => Icons.beach_access,
          AbsenceType.sickness => Icons.local_hospital,
          AbsenceType.unavailable => Icons.block,
        },
        title: type.label,
        subtitle: dayAbsences.length > 1
            ? '${dayAbsences.length} Eintraege'
            : 'Ganztags blockiert',
        tooltip: dayAbsences
            .map(
              (absence) => '${absence.employeeName}: ${absence.type.label} '
                  '(${DateFormat('dd.MM.yyyy').format(absence.startDate)} - '
                  '${DateFormat('dd.MM.yyyy').format(absence.endDate)})',
            )
            .join('\n'),
      );
    }

    if (dayShifts.isNotEmpty) {
      final first = dayShifts.first;
      final last = dayShifts.last;
      final totalHours =
          dayShifts.fold<double>(0, (sum, shift) => sum + shift.workedHours);
      return _TeamDaySnapshot(
        status: _TeamDayStatus.shift,
        icon: Icons.badge_outlined,
        title: dayShifts.length == 1
            ? first.title
            : '${dayShifts.length} Schichten',
        subtitle:
            '${DateFormat('HH:mm').format(first.startTime)} - ${DateFormat('HH:mm').format(last.endTime)} · ${totalHours.toStringAsFixed(1)} h',
        tooltip: dayShifts
            .map(
              (shift) => '${shift.employeeName}: ${shift.title} '
                  '${DateFormat('HH:mm').format(shift.startTime)} - '
                  '${DateFormat('HH:mm').format(shift.endTime)}',
            )
            .join('\n'),
      );
    }

    return const _TeamDaySnapshot(
      status: _TeamDayStatus.free,
      icon: Icons.check_circle_outline,
      title: 'Frei',
      subtitle: 'Keine Eintraege',
      tooltip: 'Keine Schicht oder genehmigte Abwesenheit',
    );
  }

  Widget _buildSelectedDayDetails(
    BuildContext context, {
    required DateTime day,
    required List<Shift> shifts,
    required List<AbsenceRequest> absences,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Details fuer ${DateFormat('EEEE, dd.MM.yyyy', 'de_DE').format(day)}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final useColumn = constraints.maxWidth < 860;
              final shiftPanel = _TeamDayDetailPanel(
                title: 'Schichten (${shifts.length})',
                icon: Icons.schedule_outlined,
                color: colorScheme.primary,
                child: shifts.isEmpty
                    ? const Text('Keine Schichten an diesem Tag.')
                    : Column(
                        children: shifts.map((shift) {
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 16,
                              child: Text(
                                shift.employeeName.characters.first
                                    .toUpperCase(),
                              ),
                            ),
                            title: Text(shift.employeeName),
                            subtitle: Text(
                              '${shift.title} · ${DateFormat('HH:mm').format(shift.startTime)} - ${DateFormat('HH:mm').format(shift.endTime)}',
                            ),
                            trailing: Text(
                              shift.status.label,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
              );
              final absencePanel = _TeamDayDetailPanel(
                title: 'Abwesenheiten (${absences.length})',
                icon: Icons.event_busy_outlined,
                color: colorScheme.tertiary,
                child: absences.isEmpty
                    ? const Text('Keine genehmigten Abwesenheiten.')
                    : Column(
                        children: absences.map((absence) {
                          final accent = switch (absence.type) {
                            AbsenceType.vacation => colorScheme.tertiary,
                            AbsenceType.sickness => colorScheme.error,
                            AbsenceType.unavailable => colorScheme.secondary,
                          };
                          final icon = switch (absence.type) {
                            AbsenceType.vacation => Icons.beach_access,
                            AbsenceType.sickness => Icons.local_hospital,
                            AbsenceType.unavailable => Icons.block,
                          };
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(icon, color: accent),
                            title: Text(absence.employeeName),
                            subtitle: Text(
                              '${absence.type.label} · ${DateFormat('dd.MM.').format(absence.startDate)} - ${DateFormat('dd.MM.').format(absence.endDate)}',
                            ),
                          );
                        }).toList(),
                      ),
              );

              if (useColumn) {
                return Column(
                  children: [
                    shiftPanel,
                    const SizedBox(height: 12),
                    absencePanel,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: shiftPanel),
                  const SizedBox(width: 12),
                  Expanded(child: absencePanel),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  ({Color background, Color foreground}) _paletteFor(
    ColorScheme colorScheme,
    _TeamDayStatus status,
  ) {
    return switch (status) {
      _TeamDayStatus.shift => (
          background: colorScheme.primaryContainer.withValues(alpha: 0.65),
          foreground: colorScheme.primary,
        ),
      _TeamDayStatus.vacation => (
          background: colorScheme.tertiaryContainer.withValues(alpha: 0.75),
          foreground: colorScheme.tertiary,
        ),
      _TeamDayStatus.sickness => (
          background: colorScheme.errorContainer.withValues(alpha: 0.75),
          foreground: colorScheme.error,
        ),
      _TeamDayStatus.unavailable => (
          background: colorScheme.secondaryContainer.withValues(alpha: 0.75),
          foreground: colorScheme.secondary,
        ),
      _TeamDayStatus.free => (
          background: colorScheme.surface,
          foreground: colorScheme.onSurfaceVariant,
        ),
    };
  }

  DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime _startOfWeek(DateTime value) {
    final day = _startOfDay(value);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  String _dayKey(DateTime day) =>
      DateFormat('yyyyMMdd').format(_startOfDay(day));

  String _userDayKey(String userId, DateTime day) => '$userId|${_dayKey(day)}';

  String _formatWeekLabel(DateTime start, DateTime end) {
    return '${DateFormat('dd.MM.', 'de_DE').format(start)} - '
        '${DateFormat('dd.MM.yyyy', 'de_DE').format(end)}';
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

enum _TeamDayStatus { free, shift, vacation, sickness, unavailable }

class _TeamDaySnapshot {
  const _TeamDaySnapshot({
    required this.status,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tooltip,
  });

  final _TeamDayStatus status;
  final IconData icon;
  final String title;
  final String subtitle;
  final String tooltip;
}

class _MobileDayChip extends StatelessWidget {
  const _MobileDayChip({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: isSelected
          ? colorScheme.primaryContainer
          : isToday
              ? colorScheme.surfaceContainerHigh
              : colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : isToday
                      ? colorScheme.primary.withValues(alpha: 0.35)
                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                DateFormat('E', 'de_DE').format(day).substring(0, 2),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight:
                      isSelected || isToday ? FontWeight.bold : FontWeight.w600,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${day.day}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamCalendarMetricPill extends StatelessWidget {
  const _TeamCalendarMetricPill({
    required this.icon,
    required this.label,
    required this.color,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 16 : 18, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

class _TeamDayDetailPanel extends StatelessWidget {
  const _TeamDayDetailPanel({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

String _formatUserError(Object error) {
  final raw = error.toString().trim();
  if (raw.startsWith('Bad state: ')) {
    return raw.substring('Bad state: '.length).trim();
  }
  if (raw.startsWith('Exception: ')) {
    return raw.substring('Exception: '.length).trim();
  }
  return raw;
}

Future<void> _handlePunchClockAction(
  BuildContext context,
  WorkProvider provider, {
  bool viaQr = false,
}) async {
  try {
    final wasEntryBacked = provider.isClockBackedByEntry;
    if (provider.hasActiveClockSession) {
      try {
        await provider.clockOut();
      } on OvertimeApprovalRequired catch (approval) {
        if (!context.mounted) {
          return;
        }
        final approved = await _confirmPunchClockOvertime(context, approval);
        if (approved != true) {
          return;
        }
        await provider.clockOut(allowOvertime: true);
      }
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            viaQr
                ? 'QR-Checkout gespeichert'
                : (wasEntryBacked
                    ? 'Laufender Zeiteintrag beendet'
                    : 'Ausgestempelt und gespeichert'),
          ),
        ),
      );
    } else {
      await provider.clockIn();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            viaQr ? 'QR-Check-in gestartet' : 'Stempeluhr gestartet',
          ),
        ),
      );
    }
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_formatUserError(error)),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}

Future<bool?> _confirmPunchClockOvertime(
  BuildContext context,
  OvertimeApprovalRequired approval,
) {
  final timeFmt = DateFormat('HH:mm');
  final lines = <String>[
    'Die geplante Schicht endet um '
        '${timeFmt.format(approval.shift.endTime)}.',
  ];
  if (approval.hasBeforeShiftOvertime) {
    lines.add(
      'Zusatzzeit vor der Schicht: '
      '${timeFmt.format(approval.beforeShiftStart!)} - '
      '${timeFmt.format(approval.beforeShiftEnd!)}',
    );
  }
  if (approval.hasAfterShiftOvertime) {
    lines.add(
      'Zusatzzeit nach der Schicht: '
      '${timeFmt.format(approval.afterShiftStart!)} - '
      '${timeFmt.format(approval.afterShiftEnd!)}',
    );
  }
  lines.add(
    'Die Schicht selbst bleibt unveraendert. Die Zusatzzeit wird als Ueberstunden gespeichert.',
  );

  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Arbeitszeit verlaengern?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines) ...[
              Text(line),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Als Ueberstunden speichern'),
        ),
      ],
    ),
  );
}

class _TimeTrackingTab extends StatefulWidget {
  const _TimeTrackingTab({
    required this.canNavigateBack,
    this.onNavigateBack,
  });

  final bool canNavigateBack;
  final VoidCallback? onNavigateBack;

  @override
  State<_TimeTrackingTab> createState() => _TimeTrackingTabState();
}

class _TimeTrackingTabState extends State<_TimeTrackingTab> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Future<List<Shift>>? _monthShiftsFuture;
  String? _monthShiftsKey;

  void _refreshMonthShiftsFuture(WorkProvider provider) {
    final user = provider.currentUser;
    final month = provider.selectedMonth;
    final nextKey = '${user?.orgId}:${user?.uid}:${month.year}-${month.month}';
    if (_monthShiftsKey == nextKey && _monthShiftsFuture != null) {
      return;
    }
    _monthShiftsKey = nextKey;
    _monthShiftsFuture = provider.loadShiftsForMonth(month);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    final monthFmt = DateFormat('MMMM yyyy', 'de_DE');
    final currentUser = provider.currentUser;
    _refreshMonthShiftsFuture(provider);

    return SafeArea(
      child: currentUser == null
          ? const Center(child: CircularProgressIndicator())
          : !currentUser.canViewTimeTracking
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _SectionCard(
                        title: 'Kein Zugriff',
                        child: Text(
                          'Die Zeiterfassung ist fuer dieses Profil deaktiviert. '
                          'Ein Admin kann den Bereich bei Bedarf wieder freischalten.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ),
                  ),
                )
              : FutureBuilder<List<Shift>>(
                  future: _monthShiftsFuture,
                  builder: (context, snapshot) {
                    final monthShifts = snapshot.data ?? const <Shift>[];
                    final plannedHoursThisMonth = _sumShiftHours(monthShifts);
                    final plannedHoursByDay = <int, double>{};
                    final actualHoursByDay = <int, double>{};

                    for (final shift in monthShifts) {
                      final dayKey = _calendarDayKey(shift.startTime);
                      plannedHoursByDay[dayKey] =
                          (plannedHoursByDay[dayKey] ?? 0) + shift.workedHours;
                    }
                    for (final entry in provider.entries) {
                      final dayKey = _calendarDayKey(entry.date);
                      actualHoursByDay[dayKey] =
                          (actualHoursByDay[dayKey] ?? 0) + entry.workedHours;
                    }

                    final selectedDayShifts = _selectedDay == null
                        ? const <Shift>[]
                        : _shiftsForDay(monthShifts, _selectedDay!);

                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 0),
                                child: _HeaderSection(
                                  title: 'Zeiterfassung',
                                  subtitle:
                                      'Monatsansicht, Kalendertage und Eintragsdetails fuer deine Arbeitszeiten.',
                                  breadcrumbs: const [
                                    BreadcrumbItem(label: 'Zeit'),
                                    BreadcrumbItem(label: 'Zeiterfassung'),
                                  ],
                                  onBack: widget.canNavigateBack
                                      ? widget.onNavigateBack
                                      : null,
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 0),
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    if (currentUser.canViewReports)
                                      FilledButton.icon(
                                        onPressed: () =>
                                            Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const MonthReportScreen(
                                              parentLabel: 'Zeit',
                                            ),
                                          ),
                                        ),
                                        icon: const Icon(
                                            Icons.description_outlined),
                                        label: const Text('Monatsbericht'),
                                      ),
                                    if (currentUser.canEditTimeEntries)
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => EntryFormScreen(
                                              parentLabel: 'Zeit',
                                              initialDate: _selectedDay ??
                                                  DateTime.now(),
                                            ),
                                          ),
                                        ),
                                        icon: const Icon(Icons.add),
                                        label: const Text('Eintrag'),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.chevron_left),
                                      onPressed: provider.previousMonth,
                                    ),
                                    Expanded(
                                      child: Center(
                                        child: Text(
                                          monthFmt
                                              .format(provider.selectedMonth),
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
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
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: _SummaryCards(
                                  provider: provider,
                                  plannedHours: plannedHoursThisMonth > 0
                                      ? plannedHoursThisMonth
                                      : null,
                                  loadingPlannedHours:
                                      snapshot.connectionState ==
                                              ConnectionState.waiting &&
                                          !snapshot.hasData,
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    Card(
                                      child: TableCalendar(
                                        locale: 'de_DE',
                                        firstDay: DateTime(2020),
                                        lastDay: DateTime(2035),
                                        focusedDay: _focusedDay,
                                        selectedDayPredicate: (day) =>
                                            isSameDay(_selectedDay, day),
                                        calendarFormat: CalendarFormat.month,
                                        startingDayOfWeek:
                                            StartingDayOfWeek.monday,
                                        headerStyle: HeaderStyle(
                                          formatButtonVisible: false,
                                          titleCentered: true,
                                          titleTextStyle: theme
                                              .textTheme.titleMedium!
                                              .copyWith(
                                                  fontWeight: FontWeight.bold),
                                          leftChevronIcon: Icon(
                                            Icons.chevron_left,
                                            color: colorScheme.primary,
                                          ),
                                          rightChevronIcon: Icon(
                                            Icons.chevron_right,
                                            color: colorScheme.primary,
                                          ),
                                        ),
                                        calendarStyle: CalendarStyle(
                                          cellMargin:
                                              const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 6,
                                          ),
                                          todayDecoration: BoxDecoration(
                                            color:
                                                colorScheme.secondaryContainer,
                                            shape: BoxShape.circle,
                                          ),
                                          selectedDecoration: BoxDecoration(
                                            color: colorScheme.tertiary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        onDaySelected:
                                            (selectedDay, focusedDay) {
                                          setState(() {
                                            _selectedDay = selectedDay;
                                            _focusedDay = focusedDay;
                                          });
                                        },
                                        onPageChanged: (focusedDay) {
                                          _focusedDay = focusedDay;
                                          provider.selectMonth(focusedDay);
                                        },
                                        calendarBuilders: CalendarBuilders(
                                          markerBuilder:
                                              (context, day, events) {
                                            final dayKey = _calendarDayKey(day);
                                            final plannedHours =
                                                plannedHoursByDay[dayKey] ?? 0;
                                            final actualHours =
                                                actualHoursByDay[dayKey] ?? 0;
                                            if (plannedHours <= 0 &&
                                                actualHours <= 0) {
                                              return null;
                                            }
                                            return Positioned(
                                              bottom: 3,
                                              child: _CalendarDayLoadMarker(
                                                plannedHours: plannedHours,
                                                actualHours: actualHours,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        _CalendarLegendMarker(
                                          color: colorScheme.tertiary,
                                          outlined: true,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Geplant (Soll)',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        _CalendarLegendMarker(
                                          color: appColors.success,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Erfasst (Ist)',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_selectedDay != null)
                              SliverToBoxAdapter(
                                child: _DayEntries(
                                  day: _selectedDay!,
                                  entries:
                                      provider.getEntriesForDay(_selectedDay!),
                                  shifts: selectedDayShifts,
                                ),
                              ),
                            if (_selectedDay == null)
                              _EntriesList(entries: provider.entries),
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 96)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _CalendarDayLoadMarker extends StatelessWidget {
  const _CalendarDayLoadMarker({
    required this.plannedHours,
    required this.actualHours,
  });

  final double plannedHours;
  final double actualHours;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).appColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (plannedHours > 0)
          _CalendarLegendMarker(
            color: colorScheme.tertiary,
            outlined: true,
            width: 10 +
                ((plannedHours < 2
                        ? 2
                        : plannedHours > 10
                            ? 10
                            : plannedHours) *
                    1.35),
          ),
        if (plannedHours > 0 && actualHours > 0) const SizedBox(height: 2),
        if (actualHours > 0)
          _CalendarLegendMarker(
            color: appColors.success,
            width: 10 +
                ((actualHours < 2
                        ? 2
                        : actualHours > 10
                            ? 10
                            : actualHours) *
                    1.35),
          ),
      ],
    );
  }
}

class _CalendarLegendMarker extends StatelessWidget {
  const _CalendarLegendMarker({
    required this.color,
    this.outlined = false,
    this.width = 18,
  });

  final Color color;
  final bool outlined;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 5,
      decoration: BoxDecoration(
        color: outlined ? color.withValues(alpha: 0.14) : color,
        borderRadius: BorderRadius.circular(999),
        border:
            outlined ? Border.all(color: color.withValues(alpha: 0.75)) : null,
      ),
    );
  }
}

class _PunchClockSheet extends StatelessWidget {
  const _PunchClockSheet();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkProvider>();
    final team = context.watch<TeamProvider>();
    final currentUser = provider.currentUser;

    if (currentUser == null) {
      return const SizedBox(
        height: 240,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final primaryAssignment = _resolvePrimaryAssignment(team, currentUser.uid);
    final primarySite = _resolvePrimarySite(
      team.sites.isNotEmpty ? team.sites : provider.sites,
      primaryAssignment,
    );
    final lastClockEntry = _resolveLastClockEntry(provider.entries);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HeaderSection(
            title: 'Stempeluhr',
            subtitle:
                'Ein- und ausstempeln, Standort pruefen und den aktuellen Einsatz verwalten.',
            breadcrumbs: [
              BreadcrumbItem(label: 'Zeit'),
              BreadcrumbItem(label: 'Stempeluhr')
            ],
          ),
          const SizedBox(height: 16),
          _PunchClockHero(
            provider: provider,
            siteAssignment: primaryAssignment,
            site: primarySite,
            activeShift: provider.activeShiftNow,
            lastClockEntry: lastClockEntry,
            onPrimaryAction: () => _handlePunchClockAction(
              context,
              provider,
            ),
            onQrAction: () => _handlePunchClockAction(
              context,
              provider,
              viaQr: true,
            ),
          ),
          const SizedBox(height: 16),
          _ConfirmedShiftDayPanel(
            day: DateTime.now(),
            title: 'Bestaetigte Schichten heute',
            emptyText:
                'Heute sind keine bestaetigten Schichten fuer die Stempeluhr verfuegbar.',
            highlightShiftId: provider.activeShiftNow?.id,
          ),
        ],
      ),
    );
  }
}

EmployeeSiteAssignment? _resolvePrimaryAssignment(
  TeamProvider team,
  String? userId,
) {
  if (userId == null || userId.isEmpty) {
    return null;
  }
  final assignments = team.siteAssignments
      .where((assignment) => assignment.userId == userId)
      .toList(growable: false);
  for (final assignment in assignments) {
    if (assignment.isPrimary) {
      return assignment;
    }
  }
  return assignments.isEmpty ? null : assignments.first;
}

WorkEntry? _resolveLastClockEntry(Iterable<WorkEntry> entries) {
  final clockEntries = entries
      .where((entry) => entry.note?.contains('Stempeluhr') ?? false)
      .toList(growable: false)
    ..sort((a, b) => b.startTime.compareTo(a.startTime));
  return clockEntries.isEmpty ? null : clockEntries.first;
}

SiteDefinition? _resolvePrimarySite(
  Iterable<SiteDefinition> sites,
  EmployeeSiteAssignment? assignment,
) {
  if (assignment == null) {
    return null;
  }
  for (final site in sites) {
    if (site.id == assignment.siteId) {
      return site;
    }
  }
  return null;
}

String _formatClockDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '${hours}h:${minutes}min';
}

String _formatShiftWindow(Shift shift) {
  return '${DateFormat('HH:mm').format(shift.startTime)} - '
      '${DateFormat('HH:mm').format(shift.endTime)}';
}

String _formatClockBreakLabel(
  WorkProvider provider,
  WorkEntry? lastClockEntry,
) {
  if (lastClockEntry != null) {
    return 'Pause: ${lastClockEntry.breakMinutes.toStringAsFixed(0)} min';
  }
  return 'Auto-Pause ab ${provider.settings.autoBreakAfterMinutes} min';
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({
    required this.title,
    required this.subtitle,
    this.breadcrumbs,
    this.onBack,
  });

  final String title;
  final String subtitle;
  final List<BreadcrumbItem>? breadcrumbs;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final compact = MobileBreakpoints.isCompact(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (breadcrumbs != null && breadcrumbs!.isNotEmpty) ...[
          ShellBreadcrumb(
            breadcrumbs: breadcrumbs!,
            onBack: onBack,
          ),
          const SizedBox(height: 10),
        ],
        Text(
          title,
          style: (compact
                  ? Theme.of(context).textTheme.headlineSmall
                  : Theme.of(context).textTheme.headlineMedium)
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _PunchClockHero extends StatelessWidget {
  const _PunchClockHero({
    required this.provider,
    required this.siteAssignment,
    required this.site,
    required this.activeShift,
    required this.lastClockEntry,
    required this.onPrimaryAction,
    required this.onQrAction,
  });

  final WorkProvider provider;
  final EmployeeSiteAssignment? siteAssignment;
  final SiteDefinition? site;
  final Shift? activeShift;
  final WorkEntry? lastClockEntry;
  final Future<void> Function() onPrimaryAction;
  final Future<void> Function() onQrAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    final isClockedIn = provider.hasActiveClockSession;
    final durationLabel =
        _formatClockDuration(provider.effectiveClockedDuration);
    final startLabel = provider.effectiveClockStartTime != null
        ? DateFormat('HH:mm').format(provider.effectiveClockStartTime!)
        : lastClockEntry == null
            ? '--:--'
            : DateFormat('HH:mm').format(lastClockEntry!.startTime);
    final endLabel = isClockedIn
        ? '--:--'
        : lastClockEntry == null
            ? '--:--'
            : DateFormat('HH:mm').format(lastClockEntry!.endTime);
    final breakLabel = _formatClockBreakLabel(
      provider,
      provider.activeEntryNow ?? lastClockEntry,
    );
    final statusColor = isClockedIn ? appColors.success : colorScheme.outline;
    final hasSiteAssignment = siteAssignment != null;
    final canClock = isClockedIn || (hasSiteAssignment && activeShift != null);
    final todayLabel =
        DateFormat('EEEE, d. MMMM', 'de_DE').format(DateTime.now());
    final siteLabel = site?.name.trim().isNotEmpty == true
        ? site!.name
        : siteAssignment?.siteName.trim().isNotEmpty == true
            ? siteAssignment!.siteName
            : 'Kein Standort';
    final codeLabel = [
      if (site?.displayCode.isNotEmpty == true) site!.displayCode,
      if (site?.federalState?.trim().isNotEmpty == true) site!.federalState!,
    ].join(' · ');
    final heroSurface = Color.lerp(
          colorScheme.surface,
          appColors.successContainer,
          isClockedIn ? 0.42 : 0.12,
        ) ??
        colorScheme.surface;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.surface,
            heroSurface,
            colorScheme.secondaryContainer.withValues(alpha: 0.72),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
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
                        'Heute',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              letterSpacing: 0.5,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        todayLabel,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _PunchClockChip(
                            icon: Icons.storefront_outlined,
                            label: siteLabel,
                            active: hasSiteAssignment,
                          ),
                          _PunchClockChip(
                            icon: Icons.event_available_rounded,
                            label: activeShift == null
                                ? 'Keine aktive Schicht'
                                : _formatShiftWindow(activeShift!),
                            active: activeShift != null,
                          ),
                          _PunchClockChip(
                            icon: Icons.sync_rounded,
                            label: isClockedIn
                                ? (provider.isClockBackedByEntry
                                    ? 'Eintrag aktiv'
                                    : 'Aktiv')
                                : canClock
                                    ? 'Bereit'
                                    : 'Gesperrt',
                            active: isClockedIn || canClock,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (codeLabel.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      codeLabel,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _ClockStatTile(
                          label: 'Start',
                          time: startLabel,
                          icon: Icons.login_rounded,
                          color: appColors.success,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ClockStatTile(
                          label: 'Ende',
                          time: endLabel,
                          icon: Icons.logout_rounded,
                          color: colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.coffee_outlined,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          breakLabel,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const Spacer(),
                        Text(
                          isClockedIn
                              ? (provider.isClockBackedByEntry
                                  ? 'Aus Zeit'
                                  : 'Automatisch')
                              : 'Letzter Eintrag',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      isClockedIn
                          ? (provider.isClockBackedByEntry
                              ? 'Eintrag laeuft'
                              : 'Im Dienst')
                          : 'Nicht im Dienst',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            letterSpacing: 0.4,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Column(
                children: [
                  Text(
                    durationLabel,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurface,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isClockedIn
                        ? (provider.isClockBackedByEntry
                            ? 'Zeitfenster aus Eintrag seit $startLabel aktiv'
                            : 'Laufende Zeit seit $startLabel')
                        : activeShift == null
                            ? 'Check-in nur waehrend einer aktiven Schicht moeglich'
                            : lastClockEntry == null
                                ? 'Bereit fuer den naechsten Check-in'
                                : 'Letzter Einsatz endete um $endLabel',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _SlideClockAction(
              enabled: canClock,
              label: isClockedIn
                  ? 'Zum Ausstempeln ziehen'
                  : 'Zum Einstempeln ziehen',
              color: isClockedIn
                  ? colorScheme.errorContainer
                  : appColors.successContainer,
              textColor: isClockedIn
                  ? colorScheme.onErrorContainer
                  : appColors.onSuccessContainer,
              knobColor: isClockedIn ? colorScheme.error : appColors.success,
              onCompleted: canClock ? onPrimaryAction : null,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canClock ? onQrAction : null,
                icon: const Icon(Icons.qr_code_2_rounded),
                label: Text(isClockedIn ? 'QR-Ausstempeln' : 'QR-Einstempeln'),
                style: FilledButton.styleFrom(
                  backgroundColor: appColors.successContainer,
                  foregroundColor: appColors.onSuccessContainer,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _LocationStatusCard(
              siteAssignment: siteAssignment,
              site: site,
              hasSiteAssignment: hasSiteAssignment,
            ),
          ],
        ),
      ),
    );
  }
}

class _PunchClockChip extends StatelessWidget {
  const _PunchClockChip({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    final background = active
        ? appColors.successContainer
        : colorScheme.surface.withValues(alpha: 0.9);
    final foreground =
        active ? appColors.onSuccessContainer : colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _ClockStatTile extends StatelessWidget {
  const _ClockStatTile({
    required this.label,
    required this.time,
    required this.icon,
    required this.color,
  });

  final String label;
  final String time;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final iconColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 10),
            Text(
              time,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SlideClockAction extends StatefulWidget {
  const _SlideClockAction({
    required this.label,
    required this.color,
    required this.textColor,
    required this.knobColor,
    required this.onCompleted,
    this.enabled = true,
  });

  final String label;
  final Color color;
  final Color textColor;
  final Color knobColor;
  final Future<void> Function()? onCompleted;
  final bool enabled;

  @override
  State<_SlideClockAction> createState() => _SlideClockActionState();
}

class _SlideClockActionState extends State<_SlideClockAction> {
  double _progress = 0;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant _SlideClockAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label ||
        oldWidget.enabled != widget.enabled) {
      _progress = 0;
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final knobIconColor =
        ThemeData.estimateBrightnessForColor(widget.knobColor) ==
                Brightness.dark
            ? Colors.white
            : Theme.of(context).colorScheme.onSurface;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const knobSize = 52.0;
        final maxTravel = width - knobSize - 8;
        final left = 4 + maxTravel * _progress.clamp(0.0, 1.0);
        return Opacity(
          opacity: widget.enabled ? 1 : 0.55,
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: Text(
                    _busy ? 'BITTE WARTEN...' : widget.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: widget.textColor,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                        ),
                  ),
                ),
                Positioned(
                  left: left,
                  child: GestureDetector(
                    onHorizontalDragUpdate: !widget.enabled || _busy
                        ? null
                        : (details) {
                            setState(() {
                              _progress = (_progress +
                                      details.delta.dx /
                                          (maxTravel <= 0 ? 1 : maxTravel))
                                  .clamp(0.0, 1.0);
                            });
                          },
                    onHorizontalDragEnd: !widget.enabled || _busy
                        ? null
                        : (_) async {
                            if (_progress >= 0.82 &&
                                widget.onCompleted != null) {
                              setState(() {
                                _progress = 1;
                                _busy = true;
                              });
                              try {
                                await widget.onCompleted!();
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _progress = 0;
                                    _busy = false;
                                  });
                                }
                              }
                            } else {
                              setState(() => _progress = 0);
                            }
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: knobSize,
                      height: knobSize,
                      decoration: BoxDecoration(
                        color: widget.knobColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: widget.knobColor.withValues(alpha: 0.28),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        _busy ? Icons.more_horiz : Icons.arrow_forward_rounded,
                        color: knobIconColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LocationStatusCard extends StatelessWidget {
  const _LocationStatusCard({
    required this.siteAssignment,
    required this.site,
    required this.hasSiteAssignment,
  });

  final EmployeeSiteAssignment? siteAssignment;
  final SiteDefinition? site;
  final bool hasSiteAssignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Standort',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (hasSiteAssignment
                          ? appColors.successContainer
                          : colorScheme.errorContainer)
                      .withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  hasSiteAssignment ? 'Standort aktiv' : 'Standort fehlt',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: hasSiteAssignment
                            ? appColors.onSuccessContainer
                            : colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            siteAssignment?.siteName ??
                'Kein Standort fuer die Stempeluhr zugewiesen.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (site != null &&
              (site!.displayCode.isNotEmpty ||
                  (site!.federalState?.trim().isNotEmpty ?? false) ||
                  site!.displayAddress.isNotEmpty ||
                  site!.coordinateLabel.isNotEmpty)) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (site!.displayCode.isNotEmpty) site!.displayCode,
                if (site!.federalState?.trim().isNotEmpty ?? false)
                  site!.federalState!,
                if (site!.displayAddress.isNotEmpty) site!.displayAddress,
                if (site!.coordinateLabel.isNotEmpty)
                  'GPS ${site!.coordinateLabel}',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            hasSiteAssignment
                ? 'Standortpruefung ist fuer ${siteAssignment!.siteName} vorbereitet.'
                : 'Bitte in der Teamverwaltung einen Primaerstandort hinterlegen.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          AspectRatio(
            aspectRatio: 1.55,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [
                    appColors.successContainer.withValues(alpha: 0.82),
                    colorScheme.secondaryContainer.withValues(alpha: 0.72),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _MapLikePainter(
                        lineColor: colorScheme.outlineVariant,
                        accent: appColors.info,
                      ),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0.05, 0.08),
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: appColors.info.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0.05, 0.08),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: appColors.info,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0.05, 0.08),
                    child: Icon(
                      Icons.location_on_rounded,
                      color: appColors.onInfo,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapLikePainter extends CustomPainter {
  const _MapLikePainter({
    required this.lineColor,
    required this.accent,
  });

  final Color lineColor;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = lineColor.withValues(alpha: 0.35)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final thin = Paint()
      ..color = lineColor.withValues(alpha: 0.22)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final park = Paint()
      ..color = accent.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.08, size.height * 0.55, size.width * 0.25,
            size.height * 0.2),
        const Radius.circular(18),
      ),
      park,
    );

    final path1 = Path()
      ..moveTo(size.width * 0.08, size.height * 0.18)
      ..quadraticBezierTo(
        size.width * 0.32,
        size.height * 0.24,
        size.width * 0.62,
        size.height * 0.14,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.1,
        size.width * 0.95,
        size.height * 0.18,
      );
    canvas.drawPath(path1, road);

    final path2 = Path()
      ..moveTo(size.width * 0.12, size.height * 0.92)
      ..quadraticBezierTo(
        size.width * 0.38,
        size.height * 0.62,
        size.width * 0.54,
        size.height * 0.48,
      )
      ..quadraticBezierTo(
        size.width * 0.76,
        size.height * 0.28,
        size.width * 0.9,
        size.height * 0.06,
      );
    canvas.drawPath(path2, road);

    for (final ratio in [0.16, 0.3, 0.45, 0.7, 0.84]) {
      canvas.drawLine(
        Offset(size.width * ratio, size.height * 0.12),
        Offset(size.width * (ratio - 0.08), size.height * 0.92),
        thin,
      );
    }
    for (final ratio in [0.22, 0.38, 0.58, 0.76]) {
      canvas.drawLine(
        Offset(size.width * 0.08, size.height * ratio),
        Offset(size.width * 0.94, size.height * (ratio - 0.06)),
        thin,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MapLikePainter oldDelegate) {
    return oldDelegate.lineColor != lineColor || oldDelegate.accent != accent;
  }
}

class _DashboardMetricCard extends StatelessWidget {
  const _DashboardMetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                Icon(icon, color: colorScheme.primary, size: 20),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.7,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final muted = colorScheme.onSurfaceVariant.withValues(alpha: 0.82);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: muted),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
        ],
      ),
    );
  }
}

class _MonthlyShiftSummaryCards extends StatefulWidget {
  const _MonthlyShiftSummaryCards({required this.provider});

  final WorkProvider provider;

  @override
  State<_MonthlyShiftSummaryCards> createState() =>
      _MonthlyShiftSummaryCardsState();
}

class _MonthlyShiftSummaryCardsState extends State<_MonthlyShiftSummaryCards> {
  Future<List<Shift>>? _future;
  String? _futureKey;

  void _refreshFuture() {
    final provider = widget.provider;
    final user = provider.currentUser;
    final month = provider.selectedMonth;
    final nextKey = '${user?.orgId}:${user?.uid}:${month.year}-${month.month}';
    if (_futureKey == nextKey && _future != null) {
      return;
    }
    _futureKey = nextKey;
    _future = provider.loadShiftsForMonth(month);
  }

  @override
  Widget build(BuildContext context) {
    _refreshFuture();
    return FutureBuilder<List<Shift>>(
      future: _future,
      builder: (context, snapshot) {
        final plannedHours = _sumShiftHours(snapshot.data ?? const <Shift>[]);
        return _SummaryCards(
          provider: widget.provider,
          plannedHours: plannedHours > 0 ? plannedHours : null,
          loadingPlannedHours:
              snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData,
        );
      },
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({
    required this.provider,
    this.plannedHours,
    this.loadingPlannedHours = false,
  });

  final WorkProvider provider;
  final double? plannedHours;
  final bool loadingPlannedHours;

  @override
  Widget build(BuildContext context) {
    final settings = provider.settings;
    final colorScheme = Theme.of(context).colorScheme;
    final hasPlannedHours = plannedHours != null && plannedHours! > 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final children = <Widget>[
          _StatCard(
            label: 'Stunden',
            value: '${provider.totalHoursThisMonth.toStringAsFixed(1)} h',
            subtitle: hasPlannedHours
                ? '${plannedHours!.toStringAsFixed(1)} h geplant'
                : 'Erfasste Arbeitszeit im Monat',
            icon: Icons.access_time,
            color: colorScheme.secondary,
          ),
          if (hasPlannedHours || loadingPlannedHours)
            _PlannedActualStatCard(
              plannedHours: plannedHours,
              actualHours: provider.totalHoursThisMonth,
              loading: loadingPlannedHours,
            ),
          _StatCard(
            label: 'Ueberstunden',
            value: '${provider.overtimeThisMonth.toStringAsFixed(1)} h',
            subtitle: 'Zeit oberhalb deiner Tagesvorgabe',
            icon: Icons.trending_up,
            color: colorScheme.tertiary,
          ),
          if (settings.hourlyRate > 0)
            _StatCard(
              label: 'Bruttolohn',
              value: NumberFormat.currency(
                locale: 'de_DE',
                symbol: settings.currency,
              ).format(provider.totalWageThisMonth),
              subtitle: 'Auf Basis der erfassten Stunden',
              icon: Icons.euro,
              color: colorScheme.primary,
            ),
        ];

        final wideColumns = children.length < 4 ? children.length : 4;
        final columns = constraints.maxWidth >= 1080
            ? wideColumns
            : constraints.maxWidth >= 720
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
            for (final child in children)
              SizedBox(
                width: itemWidth,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
}

class _PlannedActualStatCard extends StatelessWidget {
  const _PlannedActualStatCard({
    required this.plannedHours,
    required this.actualHours,
    required this.loading,
  });

  final double? plannedHours;
  final double actualHours;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    final safePlannedHours = plannedHours ?? 0;
    final diff = actualHours - safePlannedHours;
    final isOver = diff > 0.1;
    final isUnder = diff < -0.1;
    final accentColor = loading
        ? colorScheme.primary
        : isOver
            ? colorScheme.tertiary
            : isUnder
                ? colorScheme.error
                : appColors.success;
    final progress = safePlannedHours > 0
        ? (actualHours / safePlannedHours).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.compare_arrows, color: accentColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Soll / Ist',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  loading ? 'Laedt...' : _formatSignedHours(diff),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              loading
                  ? 'Geplante Schichten werden geladen'
                  : '${actualHours.toStringAsFixed(1)} h Ist von ${safePlannedHours.toStringAsFixed(1)} h Soll',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: loading ? null : progress,
                minHeight: 8,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHubTab extends StatelessWidget {
  const _ProfileHubTab({
    required this.canNavigateBack,
    this.onNavigateBack,
  });

  final bool canNavigateBack;
  final VoidCallback? onNavigateBack;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final work = context.watch<WorkProvider>();
    final team = context.watch<TeamProvider>();
    final currentUser = auth.profile;
    final assignments = team.siteAssignments
        .where((assignment) => assignment.userId == currentUser?.uid)
        .toList(growable: false);
    EmployeeSiteAssignment? primaryAssignment;
    for (final assignment in assignments) {
      if (assignment.isPrimary) {
        primaryAssignment = assignment;
        break;
      }
    }
    primaryAssignment ??= assignments.isEmpty ? null : assignments.first;

    final availableSites = team.sites.isNotEmpty ? team.sites : work.sites;
    SiteDefinition? primarySite;
    for (final site in availableSites) {
      if (site.id == primaryAssignment?.siteId) {
        primarySite = site;
        break;
      }
    }

    final screenPad = MobileBreakpoints.screenPadding(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: screenPad.horizontal / 2,
              vertical: 16,
            ),
            children: [
              _HeaderSection(
                title: 'Profil',
                subtitle:
                    'Persoenliche Daten, Arbeitszeit-Einstellungen und Auswertungen an einem Ort.',
                breadcrumbs: const [BreadcrumbItem(label: 'Profil')],
                onBack: canNavigateBack ? onNavigateBack : null,
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 340;
                      final avatar = CircleAvatar(
                        radius: compact ? 24 : 28,
                        child: Text(
                          currentUser?.displayName.characters.first
                                  .toUpperCase() ??
                              '?',
                        ),
                      );
                      final info = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentUser?.displayName ?? 'Profil',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currentUser?.role.label ?? '',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _InfoChip(
                                icon: Icons.storefront_outlined,
                                label: primarySite?.name.trim().isEmpty ?? true
                                    ? 'Kein Stammstandort'
                                    : primarySite!.name,
                              ),
                              _InfoChip(
                                icon: Icons.schedule_outlined,
                                label:
                                    '${work.settings.dailyHours.toStringAsFixed(1)} h Soll/Tag',
                              ),
                              _InfoChip(
                                icon: Icons.beach_access_outlined,
                                label:
                                    '${work.settings.vacationDays} Urlaubstage',
                              ),
                            ],
                          ),
                        ],
                      );
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            avatar,
                            const SizedBox(height: 14),
                            info,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          avatar,
                          const SizedBox(width: 14),
                          Expanded(child: info),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AdaptiveCardGrid(
                minItemWidth: 180,
                children: [
                  if (currentUser?.isAdmin ?? false)
                    _QuickActionCard(
                      icon: Icons.groups_outlined,
                      title: 'Teamverwaltung',
                      subtitle:
                          'Mitarbeiter, Standorte und Rollen weiter pflegen',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TeamManagementScreen(
                            parentLabel: 'Profil',
                          ),
                        ),
                      ),
                    ),
                  _QuickActionCard(
                    icon: Icons.settings_outlined,
                    title: 'Einstellungen',
                    subtitle: 'Profil, Theme und Standardwerte aendern',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(
                          parentLabel: 'Profil',
                        ),
                      ),
                    ),
                  ),
                  if (currentUser?.canViewReports ?? false)
                    _QuickActionCard(
                      icon: Icons.description_outlined,
                      title: 'Monatsbericht',
                      subtitle:
                          'Eigene Stunden oder Team-Bericht als PDF pruefen',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MonthReportScreen(
                            parentLabel: 'Profil',
                          ),
                        ),
                      ),
                    ),
                  if (currentUser?.canViewReports ?? false)
                    _QuickActionCard(
                      icon: Icons.analytics_outlined,
                      title: 'Statistiken',
                      subtitle:
                          'Monats- und Jahresauswertungen direkt mobil einsehen',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const StatisticsScreen(
                            parentLabel: 'Profil',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Sicherheit',
                child: Column(
                  children: [
                    _ActionStateTile(
                      icon: Icons.security_outlined,
                      title: 'Session aktiv',
                      subtitle: auth.authDisabled
                          ? 'Lokaler Entwicklungsmodus ohne Firebase-Anmeldung.'
                          : 'Angemeldet auf diesem Geraet. Biometrie kann spaeter ergaenzt werden.',
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const Divider(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => context.read<AuthProvider>().signOut(),
                        icon: const Icon(Icons.logout),
                        label: Text(
                          auth.authDisabled ? 'Profil wechseln' : 'Abmelden',
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
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
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
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _ShiftStatusBadge extends StatelessWidget {
  const _ShiftStatusBadge({required this.status});

  final ShiftStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      ShiftStatus.confirmed => colorScheme.primary,
      ShiftStatus.completed => colorScheme.secondary,
      ShiftStatus.cancelled => colorScheme.error,
      ShiftStatus.planned => colorScheme.tertiary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _ShiftPreviewTile extends StatelessWidget {
  const _ShiftPreviewTile({
    required this.shift,
    this.onTap,
  });

  final Shift shift;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE, dd.MM. HH:mm', 'de_DE');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          child: Text(
            shift.employeeName.characters.take(1).toString().toUpperCase(),
          ),
        ),
        title: Text(shift.title),
        subtitle: Text(
          '${shift.employeeName} · ${dateFormat.format(shift.startTime)} - ${DateFormat('HH:mm').format(shift.endTime)}'
          '${shift.effectiveSiteLabel == null ? '' : '\n${shift.effectiveSiteLabel}'}',
        ),
        trailing: _ShiftStatusBadge(status: shift.status),
      ),
    );
  }
}

class _RecentEntryTile extends StatelessWidget {
  const _RecentEntryTile({required this.entry});

  final WorkEntry entry;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('EEE, dd.MM.', 'de_DE');
    final timeFmt = DateFormat('HH:mm');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(dateFmt.format(entry.date)),
        subtitle: Text(
          '${timeFmt.format(entry.startTime)} - ${timeFmt.format(entry.endTime)}'
          '${entry.siteName == null ? '' : '\n${entry.siteName}'}',
        ),
        trailing: Text('${entry.workedHours.toStringAsFixed(2)} h'),
      ),
    );
  }
}

class _DayEntries extends StatelessWidget {
  const _DayEntries({
    required this.day,
    required this.entries,
    required this.shifts,
  });

  final DateTime day;
  final List<WorkEntry> entries;
  final List<Shift> shifts;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEEE, dd. MMMM', 'de_DE');
    final shiftById = <String, Shift>{
      for (final shift in shifts)
        if (shift.id != null) shift.id!: shift,
    };
    final linkedEntries = entries.where((entry) {
      final shiftId = entry.sourceShiftId?.trim();
      return shiftId != null && shiftById.containsKey(shiftId);
    }).toList(growable: false);
    final unlinkedCount = entries.length - linkedEntries.length;
    final plannedHours = _sumShiftHours(shifts);
    final actualHours = _sumEntryHours(entries);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fmt.format(day),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (plannedHours > 0)
                _InfoChip(
                  icon: Icons.schedule_outlined,
                  label: 'Soll ${plannedHours.toStringAsFixed(1)} h',
                ),
              _InfoChip(
                icon: Icons.task_alt_outlined,
                label: 'Ist ${actualHours.toStringAsFixed(1)} h',
              ),
              if (plannedHours > 0)
                _InfoChip(
                  icon: actualHours >= plannedHours
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  label: _formatSignedHours(actualHours - plannedHours),
                ),
              if (linkedEntries.isNotEmpty)
                _InfoChip(
                  icon: Icons.link_rounded,
                  label:
                      '${linkedEntries.length} ${linkedEntries.length == 1 ? 'Link' : 'Links'}',
                ),
              if (unlinkedCount > 0)
                _InfoChip(
                  icon: Icons.link_off_outlined,
                  label: '$unlinkedCount ohne Schichtbezug',
                ),
            ],
          ),
          const SizedBox(height: 12),
          _DayShiftPlanPanel(
            shifts: shifts,
            entries: entries,
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text('Kein Eintrag fuer diesen Tag')),
              ),
            )
          else
            ...entries.map(
              (entry) => _EntryCard(
                entry: entry,
                linkedShift: entry.sourceShiftId == null
                    ? null
                    : shiftById[entry.sourceShiftId!.trim()],
              ),
            ),
        ],
      ),
    );
  }
}

class _DayShiftPlanPanel extends StatelessWidget {
  const _DayShiftPlanPanel({
    required this.shifts,
    required this.entries,
  });

  final List<Shift> shifts;
  final List<WorkEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final linkedEntriesByShiftId = _entriesBySourceShiftId(entries);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.38),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Geplante Schichten und verknuepfte Zeiten',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          if (shifts.isEmpty)
            Text(
              'Fuer diesen Tag gibt es keine geplante Schicht.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...shifts.map((shift) {
              final linkedEntries = shift.id == null
                  ? const <WorkEntry>[]
                  : linkedEntriesByShiftId[shift.id!] ?? const <WorkEntry>[];
              final linkedHours = _sumEntryHours(linkedEntries);
              final diff = linkedHours - shift.workedHours;
              final diffColor = diff.abs() <= 0.1
                  ? colorScheme.primary
                  : diff >= 0
                      ? colorScheme.tertiary
                      : colorScheme.error;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.42),
                    ),
                  ),
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
                                  shift.title,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${DateFormat('HH:mm').format(shift.startTime)} - ${DateFormat('HH:mm').format(shift.endTime)}'
                                  '${shift.effectiveSiteLabel?.trim().isNotEmpty == true ? ' · ${shift.effectiveSiteLabel}' : ''}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _ShiftStatusBadge(status: shift.status),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _InfoChip(
                            icon: Icons.schedule_outlined,
                            label:
                                'Soll ${shift.workedHours.toStringAsFixed(1)} h',
                          ),
                          _InfoChip(
                            icon: Icons.task_alt_outlined,
                            label: linkedEntries.isEmpty
                                ? 'Noch kein Ist'
                                : 'Ist ${linkedHours.toStringAsFixed(1)} h',
                          ),
                          _InfoChip(
                            icon: Icons.compare_arrows,
                            label: linkedEntries.isEmpty
                                ? 'Offen'
                                : _formatSignedHours(diff),
                          ),
                        ],
                      ),
                      if (linkedEntries.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          linkedEntries
                              .map(
                                (entry) =>
                                    '${DateFormat('HH:mm').format(entry.startTime)} - ${DateFormat('HH:mm').format(entry.endTime)}'
                                    '${entry.breakMinutes > 0 ? ' · ${entry.breakMinutes.toInt()} min Pause' : ''}',
                              )
                              .join('\n'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: diffColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _EntriesList extends StatelessWidget {
  const _EntriesList({required this.entries});

  final List<WorkEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: _EmptyState(
            icon: Icons.inbox_outlined,
            text: 'Keine Eintraege in diesem Monat.',
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _EntryCard(entry: entries[index]),
        ),
        childCount: entries.length,
      ),
    );
  }
}

class _ConfirmedShiftDayPanel extends StatefulWidget {
  const _ConfirmedShiftDayPanel({
    required this.day,
    required this.title,
    required this.emptyText,
    this.highlightShiftId,
  });

  final DateTime day;
  final String title;
  final String emptyText;
  final String? highlightShiftId;

  @override
  State<_ConfirmedShiftDayPanel> createState() =>
      _ConfirmedShiftDayPanelState();
}

class _ConfirmedShiftDayPanelState extends State<_ConfirmedShiftDayPanel> {
  Future<List<Shift>>? _future;
  String? _futureKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshFutureIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _ConfirmedShiftDayPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!DateUtils.isSameDay(oldWidget.day, widget.day)) {
      _futureKey = null;
    }
    _refreshFutureIfNeeded();
  }

  void _refreshFutureIfNeeded() {
    final provider = context.read<WorkProvider>();
    final user = provider.currentUser;
    final dayKey = DateTime(
      widget.day.year,
      widget.day.month,
      widget.day.day,
    ).toIso8601String();
    final nextKey = '${user?.orgId}:${user?.uid}:$dayKey';
    if (_futureKey == nextKey && _future != null) {
      return;
    }
    _futureKey = nextKey;
    _future = provider.loadConfirmedShiftsForDay(widget.day);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Shift>>(
      future: _future,
      builder: (context, snapshot) {
        final colorScheme = Theme.of(context).colorScheme;
        final theme = Theme.of(context);
        final shifts = snapshot.data ?? const <Shift>[];

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.38),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (snapshot.hasError)
                Text(
                  'Schichten konnten nicht geladen werden.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (shifts.isEmpty)
                Text(
                  widget.emptyText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              else
                ...shifts.map(
                  (shift) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ConfirmedShiftInfoTile(
                      shift: shift,
                      highlighted: shift.id == widget.highlightShiftId,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ConfirmedShiftInfoTile extends StatelessWidget {
  const _ConfirmedShiftInfoTile({
    required this.shift,
    required this.highlighted,
  });

  final Shift shift;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlighted
            ? colorScheme.primaryContainer.withValues(alpha: 0.38)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlighted
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              highlighted
                  ? Icons.play_circle_fill_rounded
                  : Icons.event_rounded,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        shift.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    if (highlighted)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          'Jetzt aktiv',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ),
                    _ShiftStatusBadge(status: shift.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${DateFormat('HH:mm').format(shift.startTime)} - ${DateFormat('HH:mm').format(shift.endTime)}'
                  ' · ${shift.workedHours.toStringAsFixed(1)} h',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                if (shift.effectiveSiteLabel?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    shift.effectiveSiteLabel!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    this.linkedShift,
  });

  final WorkEntry entry;
  final Shift? linkedShift;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<WorkProvider>();
    final dateFmt = DateFormat('EE, dd.MM.', 'de_DE');
    final timeFmt = DateFormat('HH:mm');
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        titleAlignment: ListTileTitleAlignment.top,
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          child: Text(
            '${entry.workedHours.toStringAsFixed(1)}h',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(dateFmt.format(entry.date)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${timeFmt.format(entry.startTime)} - ${timeFmt.format(entry.endTime)}'
              '${entry.breakMinutes > 0 ? ' (Pause: ${entry.breakMinutes.toInt()} min)' : ''}',
            ),
            if (linkedShift != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.link_rounded,
                          size: 16,
                          color: colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Mit Schicht verknuepft',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${linkedShift!.title} · ${timeFmt.format(linkedShift!.startTime)} - ${timeFmt.format(linkedShift!.endTime)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (linkedShift!.effectiveSiteLabel?.trim().isNotEmpty ==
                        true)
                      Text(
                        linkedShift!.effectiveSiteLabel!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ] else if (entry.sourceShiftId?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                'Schichtbezug vorhanden, aber im aktuellen Zeitraum nicht geladen.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        isThreeLine: linkedShift != null,
        trailing: !(provider.currentUser?.canEditTimeEntries ?? false)
            ? null
            : PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EntryFormScreen(
                          entry: entry,
                          parentLabel: 'Zeit',
                        ),
                      ),
                    );
                  } else if (value == 'delete' && entry.id != null) {
                    _confirmDelete(context, provider, entry.id!);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
                  PopupMenuItem(value: 'delete', child: Text('Loeschen')),
                ],
              ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WorkProvider provider,
    String entryId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eintrag loeschen?'),
        content: const Text('Dieser Eintrag wird unwiderruflich geloescht.'),
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

    if (confirmed == true) {
      try {
        await provider.deleteEntry(entryId);
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Loeschen: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}
