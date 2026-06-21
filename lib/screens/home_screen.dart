import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../core/accessibility.dart';
import '../core/analytics_service.dart';
import '../core/redesign_flags.dart';
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
import '../ui/app_hero_card.dart';
import '../ui/app_quick_action.dart';
import '../ui/app_section_card.dart';
import '../ui/app_stat_cards.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_nav_menu.dart';
import '../widgets/app_nav_rail.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/info_chip.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/section_card.dart';
import '../widgets/section_header.dart';
import '../widgets/dashboard_action_items_card.dart';
import 'audit_log_screen.dart';
import 'entry_form_screen.dart';
import 'contacts_screen.dart';
import 'customer_order_screen.dart';
import 'inventory_screen.dart';
import 'month_report_screen.dart';
import 'personal_screen.dart';
import 'notification_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';
import 'shift_planner_screen.dart';
import 'statistics_screen.dart';
import 'team_management_screen.dart';

part 'home_screen_helpers.dart';
part 'home_screen_tabs.dart';
part 'home_dashboards_v2.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;
  // Strg/Ctrl + 1..9 -> n-te Rail-Destination (no-desktop-keyboard-shortcuts).
  static const List<LogicalKeyboardKey> _navDigitKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  final Set<_ShellDestinationId> _loadedDestinations = {
    _ShellDestinationId.today,
  };
  final List<_ShellDestinationId> _navHistory = [];

  /// Steuert das V2-Slide-in-Menü (drawer/endDrawer) von ausserhalb des
  /// Scaffold-Subtrees (mobiler ☰-Trigger, Rail-Profil-Header).
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    // Eng gescopte Watches: die Shell rebuildt nur noch bei Profil-/
    // Storage-Aenderungen. Die haeufig wechselnden Work-/Schedule-Daten werden
    // im Banner bzw. FAB-Teilbaum selbst abonniert (home-shell-watches-all-providers).
    final currentUser =
        context.select<AuthProvider, AppUserProfile?>((auth) => auth.profile);
    final authDisabled = context.read<AuthProvider>().authDisabled;
    final storageLocation = authDisabled
        ? DataStorageLocation.local
        : context.select<StorageModeProvider, DataStorageLocation>(
            (storage) => storage.location,
          );
    final canManageShifts = currentUser?.canManageShifts ?? false;
    final useV2 = RedesignFlags.isOn(context);
    final destinations = _buildDestinations(currentUser, useV2: useV2);
    final selectedIndex = _navIndex.clamp(0, destinations.length - 1);
    final currentDestination = destinations[selectedIndex];
    final railDestinations = destinations
        .where((destination) => destination.id != _ShellDestinationId.profile)
        .toList(growable: false);
    final railSelectedIndex = railDestinations.indexWhere(
      (destination) => destination.id == currentDestination.id,
    );

    // Desktop-/Web-Tastatur-Shortcuts (no-desktop-keyboard-shortcuts):
    // Strg/Ctrl + 1..9 springt direkt auf die n-te Rail-Destination.
    final shortcutBindings = <ShortcutActivator, VoidCallback>{
      for (var i = 0;
          i < railDestinations.length && i < _navDigitKeys.length;
          i++)
        SingleActivator(_navDigitKeys[i], control: true): () =>
            _handleDestinationTap(i, destinations: railDestinations),
    };

    return CallbackShortcuts(
      bindings: shortcutBindings,
      child: FocusTraversalGroup(
        child: PopScope<void>(
          canPop: _navHistory.isEmpty,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) {
              return;
            }
            _navigateBackInShell(destinations: destinations);
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Material-3 Window-Size-Classes: BottomNav (<600) -> Rail mit nur
              // ausgewaehltem Label (600–839) -> Rail mit allen Labels (>=840)
              // (no-medium-window-class). Hoehen-Guard, damit die (nicht scrollbare)
              // NavigationRail auf kurzen Landscape-Phones nicht vertikal ueberlaeuft.
              final useRail =
                  MobileBreakpoints.useNavigationRail(constraints.maxWidth) &&
                      constraints.maxHeight >= MobileBreakpoints.mediumWindow;
              final expandedRailLabels =
                  MobileBreakpoints.useExpandedRailLabels(constraints.maxWidth);
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
                      storageLocation: storageLocation,
                    ),
                  ),
                  Expanded(child: body),
                ],
              );

              return Scaffold(
                key: _scaffoldKey,
                // V2-Slide-in-Menü: mobil von links (drawer, ☰ in der schlanken
                // V2-AppBar), auf Rail/Desktop von rechts (endDrawer, geöffnet vom
                // Rail-Profil-Header). Pro Layout nur eine Seite, damit es kein
                // verwirrendes Wischen von der „falschen" Kante gibt. V1 bleibt ohne.
                drawer: (useV2 && !useRail)
                    ? _buildAppMenuDrawer(currentUser, authDisabled)
                    : null,
                endDrawer: (useV2 && useRail)
                    ? _buildAppMenuDrawer(currentUser, authDisabled)
                    : null,
                // Schmaler Rand: lässt dem horizontalen TableCalendar-/Wochen-Swipe
                // im ShiftPlanner Platz, statt ihn am linken Rand abzufangen.
                drawerEdgeDragWidth: useV2 ? 24 : null,
                appBar: (useV2 && !useRail)
                    ? _V2MenuTopBar(
                        user: currentUser,
                        onOpenMenu: () =>
                            _scaffoldKey.currentState?.openDrawer(),
                      )
                    : null,
                body: useRail
                    ? SafeArea(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (useV2)
                              AppNavRail(
                                items: [
                                  for (final destination in railDestinations)
                                    AppNavRailItem(
                                      icon: destination.icon,
                                      selectedIcon: destination.selectedIcon,
                                      label: destination.label,
                                    ),
                                ],
                                selectedIndex: railSelectedIndex,
                                onSelected: (index) => _handleDestinationTap(
                                  index,
                                  destinations: railDestinations,
                                ),
                                onOpenMenu: () =>
                                    _scaffoldKey.currentState?.openEndDrawer(),
                                user: currentUser,
                                expandedLabels: expandedRailLabels,
                              )
                            else ...[
                              NavigationRail(
                                selectedIndex: railSelectedIndex == -1
                                    ? null
                                    : railSelectedIndex,
                                onDestinationSelected: (index) =>
                                    _handleDestinationTap(
                                  index,
                                  destinations: railDestinations,
                                ),
                                labelType: expandedRailLabels
                                    ? NavigationRailLabelType.all
                                    : NavigationRailLabelType.selected,
                                leading: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 12, 12, 8),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const AppLogo(height: 38),
                                      const SizedBox(height: 12),
                                      _RailProfileHeader(
                                        user: currentUser,
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
                                    tooltip: authDisabled
                                        ? 'Profil wechseln'
                                        : 'Abmelden',
                                    onPressed: () =>
                                        context.read<AuthProvider>().signOut(),
                                    icon: const Icon(Icons.logout),
                                  ),
                                ),
                                destinations: [
                                  for (final destination in railDestinations)
                                    NavigationRailDestination(
                                      icon: Icon(destination.icon),
                                      selectedIcon:
                                          Icon(destination.selectedIcon),
                                      label: Text(destination.label),
                                    ),
                                ],
                              ),
                              const VerticalDivider(width: 1),
                            ],
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
                floatingActionButton: currentDestination.showFab
                    ? Consumer<WorkProvider>(
                        builder: (context, work, _) =>
                            _buildFab(
                              context,
                              destination: currentDestination,
                              canManageShifts: canManageShifts,
                              destinations: destinations,
                              work: work,
                            ) ??
                            const SizedBox.shrink(),
                      )
                    : null,
              );
            },
          ),
        ),
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

    // Screen-Tracking (no-analytics-screen-tracking), datensparsam: nur
    // Tab-Name + Rolle, keine personenbezogenen Daten.
    AnalyticsService.logScreenView(
      destinations[index].id.name,
      role: context.read<AuthProvider>().profile?.role.name,
    );
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
        ? _ExpressiveActionsFab(
            label: 'Aktionen',
            icon: Icons.bolt_rounded,
            onPressed: () => _showPlannerQuickActions(
              destinations,
              currentDestinationLabel: destination.label,
            ),
          )
        : _ExpressiveActionsFab(
            label: 'Schnell',
            icon: Icons.bolt_rounded,
            onPressed: () => _showEmployeeQuickActions(
              currentDestinationLabel: destination.label,
            ),
          );

    final punchClockFab = FloatingActionButton(
      heroTag: 'shell_punch_clock_fab',
      tooltip: work.hasActiveClockSession
          ? 'Stempeluhr oeffnen und ausstempeln'
          : 'Stempeluhr oeffnen',
      onPressed: work.currentUser == null ? null : () => _showPunchClockSheet(),
      backgroundColor:
          work.hasActiveClockSession ? colorScheme.error : appColors.success,
      foregroundColor: work.hasActiveClockSession
          ? colorScheme.onError
          : appColors.onSuccess,
      child: Icon(
        work.hasActiveClockSession ? Icons.logout_rounded : Icons.login_rounded,
      ),
    );

    return _ShellFabCluster(
      actions: [
        if (canEditTimeEntries) punchClockFab,
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

  /// Baut den Inhalt des V2-Slide-in-Menüs. Wird sowohl als `drawer` (links)
  /// als auch als `endDrawer` (rechts) verwendet. Der `Consumer2`-Teilbaum wird
  /// erst beim Öffnen des Drawers gebaut (geschlossen ist er nicht im Tree),
  /// abonniert Team/Work also nur dann und weitet die Shell-Rebuilds nicht aus.
  Widget _buildAppMenuDrawer(AppUserProfile? user, bool authDisabled) {
    return Drawer(
      child: Consumer2<TeamProvider, WorkProvider>(
        builder: (context, team, work, _) {
          final assignments = team.siteAssignments
              .where((assignment) => assignment.userId == user?.uid)
              .toList(growable: false);
          EmployeeSiteAssignment? primaryAssignment;
          for (final assignment in assignments) {
            if (assignment.isPrimary) {
              primaryAssignment = assignment;
              break;
            }
          }
          primaryAssignment ??= assignments.isEmpty ? null : assignments.first;
          final availableSites =
              team.sites.isNotEmpty ? team.sites : work.sites;
          String? siteName;
          for (final site in availableSites) {
            if (site.id == primaryAssignment?.siteId) {
              siteName = site.name;
              break;
            }
          }

          // Scanner-Einstieg auf echten Mobil-Plattformen (Handy UND Tablet:
          // Android/iOS nativ). Web und Desktop-OS haben keine sinnvolle
          // Kamera-/Scan-UX und fallen raus.
          final showScanner = MobileBreakpoints.isNativeMobile;

          return AppNavMenu(
            user: user,
            authDisabled: authDisabled,
            showScanner: showScanner,
            siteName: siteName,
            dailyHours: work.settings.dailyHours,
            vacationDays: work.settings.vacationDays,
            onSignOut: () {
              _closeAppMenu();
              context.read<AuthProvider>().signOut();
            },
            onOpenMonthReport: () =>
                _pushFromMenu(const MonthReportScreen(parentLabel: 'Profil')),
            onOpenStatistics: () =>
                _pushFromMenu(const StatisticsScreen(parentLabel: 'Profil')),
            onOpenPersonal: () =>
                _pushFromMenu(const PersonalScreen(parentLabel: 'Profil')),
            onOpenTeam: () => _pushFromMenu(
                const TeamManagementScreen(parentLabel: 'Profil')),
            onOpenInventory: () =>
                _pushFromMenu(const InventoryScreen(parentLabel: 'Profil')),
            onOpenCustomerOrders: () => _pushFromMenu(
                const CustomerOrderScreen(parentLabel: 'Profil')),
            onOpenScanner: () =>
                _pushFromMenu(const ScannerScreen(parentLabel: 'Profil')),
            onOpenSettings: () =>
                _pushFromMenu(const SettingsScreen(parentLabel: 'Profil')),
          );
        },
      ),
    );
  }

  void _closeAppMenu() {
    final state = _scaffoldKey.currentState;
    if (state == null) {
      return;
    }
    if (state.isDrawerOpen) {
      state.closeDrawer();
    }
    if (state.isEndDrawerOpen) {
      state.closeEndDrawer();
    }
  }

  /// Schliesst das Menü und pusht den Detail-Screen — damit ein anschliessendes
  /// Zurück den Detail-Screen poppt und nicht in einen offenen Drawer führt.
  void _pushFromMenu(Widget screen) {
    _closeAppMenu();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  List<_ShellDestination> _buildDestinations(
    AppUserProfile? user, {
    bool useV2 = false,
  }) {
    final canNavigateBack = _navHistory.isNotEmpty;
    final canManageShifts = user?.canManageShifts ?? false;
    final canViewSchedule = user?.canViewSchedule ?? false;
    final canViewTimeTracking = user?.canViewTimeTracking ?? false;
    final canViewContacts = user?.canViewContacts ?? false;
    final canViewInventory = user?.canViewInventory ?? false;
    final isAdmin = user?.isAdmin ?? false;
    final items = <_ShellDestination>[
      _ShellDestination(
        id: _ShellDestinationId.today,
        label: 'Heute',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        child: canManageShifts
            ? (useV2
                ? _AdminDashboardTabV2(
                    onOpenPlan: _openPlanDestination,
                    onOpenPlanForDate: _openPlanDestinationForDate,
                    canNavigateBack: canNavigateBack,
                    onNavigateBack: _handleShellBackPressed,
                  )
                : _AdminDashboardTab(
                    onOpenPlan: _openPlanDestination,
                    onOpenPlanForDate: _openPlanDestinationForDate,
                    canNavigateBack: canNavigateBack,
                    onNavigateBack: _handleShellBackPressed,
                  ))
            : useV2
                ? _EmployeeDashboardTabV2(
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
      if (canViewContacts)
        _ShellDestination(
          id: _ShellDestinationId.contacts,
          label: 'Kontakte',
          icon: Icons.contacts_outlined,
          selectedIcon: Icons.contacts,
          child: ContactsScreen(
            canNavigateBack: canNavigateBack,
            onNavigateBack: _handleShellBackPressed,
          ),
          // Kontakte bringen ihren eigenen FAB ("Neuer Kontakt") mit; der
          // schicht-/zeitbezogene Shell-FAB ist hier bewusst aus.
          showFab: false,
        ),
      // "Laden" buendelt die Geschaefts-Module (Warenwirtschaft,
      // Kundenbestellungen, Personal) als ein einziger Tab -> kein Bottom-Nav-
      // Ueberlauf durch drei getrennte Tabs.
      if (canViewInventory || isAdmin)
        _ShellDestination(
          id: _ShellDestinationId.shop,
          label: 'Laden',
          icon: Icons.storefront_outlined,
          selectedIcon: Icons.storefront,
          child: _ShopHubTab(
            canNavigateBack: canNavigateBack,
            onNavigateBack: _handleShellBackPressed,
          ),
          showFab: false,
        ),
      // In V2 ersetzt das Slide-in-Menü (Scaffold.drawer/endDrawer) den
      // Profil-Tab; die Bottom-Nav zeigt nur die 4 Kern-Tabs.
      if (!useV2)
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

enum _ShellDestinationId { today, plan, time, inbox, contacts, shop, profile }

/// Schlanke V2-Top-Bar im Bottom-Nav-Modus: ein Avatar-Button links öffnet das
/// Slide-in-Menü. Bewusst ohne Titel — den Abschnittstitel liefert weiterhin der
/// `SectionHeader` jedes Tabs (kein Doppel-Header).
class _V2MenuTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _V2MenuTopBar({required this.user, required this.onOpenMenu});

  final AppUserProfile? user;
  final VoidCallback onOpenMenu;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final initial = user?.displayName.characters.first.toUpperCase() ?? '?';
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      leadingWidth: 64,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: IconButton(
          tooltip: 'Menü',
          onPressed: onOpenMenu,
          icon: CircleAvatar(
            radius: 16,
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            child: Text(
              initial,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
                InfoChip(
                  icon: Icons.storefront_outlined,
                  label: shift.effectiveSiteLabel ?? 'Standort offen',
                ),
                InfoChip(
                  icon: Icons.person_outline,
                  label: shift.employeeName,
                ),
                InfoChip(
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
  });

  final DataStorageLocation storageLocation;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Work/Schedule werden hier (im kleinen Banner-Teilbaum) abonniert, damit
    // ihre haeufigen Aenderungen nur dieses Widget rebuilden, nicht die ganze
    // Shell (home-shell-watches-all-providers).
    final work = context.watch<WorkProvider>();
    final schedule = context.watch<ScheduleProvider>();
    final String? text;
    final IconData icon;
    final Color color;
    var showSyncAction = false;

    // Ehrliches „ausstehender Abgleich"-Signal: nur lokal vorgemerkte, noch
    // nicht propagierte Löschungen (Tombstones), kein gespiegelter Cache
    // (no-connectivity-no-sync-status-ux).
    final pendingDeletions =
        work.pendingDeletionCount + schedule.pendingDeletionCount;

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
    } else if (pendingDeletions > 0) {
      text = '$pendingDeletions ausstehende '
          '${pendingDeletions == 1 ? 'Löschung wird' : 'Löschungen werden'} '
          'beim nächsten Abgleich übertragen.';
      icon = Icons.cloud_upload_outlined;
      color = colorScheme.tertiary;
      showSyncAction = true;
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
            if (showSyncAction)
              TextButton(
                onPressed: () => _syncNow(context),
                child: const Text('Jetzt synchronisieren'),
              ),
          ],
        ),
      ),
    );
  }

  /// Manueller, nutzer-initiierter Abgleich der lokal gepufferten Änderungen
  /// (inkl. Tombstones) in die Cloud – bewusst nur on-demand, um den
  /// Spark-Free-Tier-Designzielen (keine automatischen Voll-Pushes) zu folgen.
  Future<void> _syncNow(BuildContext context) async {
    final work = context.read<WorkProvider>();
    final schedule = context.read<ScheduleProvider>();
    final messenger = ScaffoldMessenger.of(context);
    await work.syncLocalStateToCloud();
    await schedule.syncLocalStateToCloud();
    messenger.showSnackBar(
      const SnackBar(content: Text('Abgleich abgeschlossen.')),
    );
  }
}

/// Wochentags-/Datums-Kopfzelle der mobilen Wochenansicht
/// (extrahiert aus build-helper-methods-to-widget-classes).
class _DayHeaderCell extends StatelessWidget {
  const _DayHeaderCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
  });

  final DateTime day;
  final bool isToday;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
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
}

/// Sammelt die Shell-FABs hinter einem dauerhaft sichtbaren Toggle unten rechts
/// (modernes vertikales Speed-Dial). Eingeklappt zeigt nur der Chevron-Toggle,
/// dass dort Aktionen liegen; Tippen klappt die Buttons gestaffelt nach oben aus
/// und dreht den Chevron. Standard: eingeklappt.
class _ShellFabCluster extends StatefulWidget {
  const _ShellFabCluster({required this.actions});

  /// Buttons in Anzeigereihenfolge von oben nach unten. Der letzte Eintrag sitzt
  /// am naechsten zum Toggle und erscheint beim Ausklappen zuerst.
  final List<Widget> actions;

  @override
  State<_ShellFabCluster> createState() => _ShellFabClusterState();
}

class _ShellFabClusterState extends State<_ShellFabCluster>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respektiert die "Bewegung reduzieren"-Systemeinstellung.
    _controller.duration =
        context.motionDuration(const Duration(milliseconds: 300));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.actions.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < count; i++)
          _RevealSlot(
            controller: _controller,
            expanded: _expanded,
            position: count - 1 - i,
            child: widget.actions[i],
          ),
        _buildToggle(context),
      ],
    );
  }

  Widget _buildToggle(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Tooltip(
      message: _expanded ? 'Aktionen ausblenden' : 'Aktionen anzeigen',
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.32),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: const CircleBorder(),
          child: Ink(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [colorScheme.primary, colorScheme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: InkWell(
              onTap: _toggle,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 52,
                height: 52,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => Transform.rotate(
                    angle: _controller.value * 3.1415926,
                    child: Icon(
                      Icons.chevron_left,
                      color: colorScheme.onPrimary,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ein gestaffelt ein-/ausblendender Platz im [_ShellFabCluster]. Eingeklappt
/// nimmt er keinen Platz ein und schluckt keine Taps.
class _RevealSlot extends StatelessWidget {
  const _RevealSlot({
    required this.controller,
    required this.expanded,
    required this.position,
    required this.child,
  });

  final AnimationController controller;
  final bool expanded;

  /// 0 = naechster am Toggle (erscheint zuerst), groesser = weiter oben/spaeter.
  final int position;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (position * 0.14).clamp(0.0, 0.4);
    final end = (start + 0.6).clamp(0.0, 1.0);
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final t = ((controller.value - start) / (end - start)).clamp(0.0, 1.0);
        final eased = Curves.easeOutCubic.transform(t);
        if (eased <= 0.001 && !expanded) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Opacity(
            opacity: eased,
            child: Transform.translate(
              offset: Offset(0, (1 - eased) * 18),
              child: Transform.scale(
                scale: 0.85 + 0.15 * eased,
                alignment: Alignment.bottomRight,
                child: IgnorePointer(
                  ignoring: !expanded,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Markanter, gebrandeter Aktions-FAB (Signal-Teal-Verlauf) der Shell. Bewusst
/// als eigenes Widget statt `FloatingActionButton.extended`, damit der Verlauf
/// und der weiche Marken-Schatten moeglich sind und sich der Button klar vom
/// gruen/roten Stempeluhr-FAB darueber absetzt. Verhalten bleibt: oeffnet das
/// Schnellaktionen-Sheet.
class _ExpressiveActionsFab extends StatelessWidget {
  const _ExpressiveActionsFab({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Tooltip(
      message: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.32),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: const StadiumBorder(),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colorScheme.primary, colorScheme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: InkWell(
              onTap: onPressed,
              customBorder: const StadiumBorder(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: colorScheme.onPrimary, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
                  InfoChip(
                    icon: Icons.storefront_outlined,
                    label: nextShift.effectiveSiteLabel ?? 'Standort offen',
                  ),
                  InfoChip(
                    icon: Icons.badge_outlined,
                    label: nextShift.title,
                  ),
                  InfoChip(
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

    return SectionCard(
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
                InfoChip(
                  icon: Icons.people_alt_outlined,
                  label: '$activeMembers aktiv',
                ),
                InfoChip(
                  icon: Icons.event_note_outlined,
                  label: '$pendingAbsenceCount offen',
                ),
                InfoChip(
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

/// "Laden"-Tab: ein gebuendelter Einstieg in die Geschaefts-Module
/// (Warenwirtschaft, Kundenbestellungen, Personal). Bewusst als Hub mit
/// Schnellzugriff-Karten – die Module sind selbst Tab-Screens, echte Unter-Tabs
/// waeren Tabs-in-Tabs. Oeffnet die Vollbild-Screens per Navigator.push.
class _ShopHubTab extends StatelessWidget {
  const _ShopHubTab({
    required this.canNavigateBack,
    this.onNavigateBack,
  });

  final bool canNavigateBack;
  final VoidCallback? onNavigateBack;

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().profile;
    final canViewInventory = currentUser?.canViewInventory ?? false;
    final isAdmin = currentUser?.isAdmin ?? false;
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
              SectionHeader(
                title: 'Laden',
                subtitle:
                    'Warenwirtschaft, Kundenbestellungen und Personal an einem Ort.',
                breadcrumbs: const [BreadcrumbItem(label: 'Laden')],
                onBack: canNavigateBack ? onNavigateBack : null,
              ),
              const SizedBox(height: 20),
              AdaptiveCardGrid(
                minItemWidth: 180,
                children: [
                  if (canViewInventory)
                    _QuickActionCard(
                      icon: Icons.inventory_2_outlined,
                      title: 'Warenwirtschaft',
                      subtitle:
                          'Bestand, Lieferanten und Bestellungen verwalten',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const InventoryScreen(parentLabel: 'Laden'),
                        ),
                      ),
                    ),
                  if (canViewInventory)
                    _QuickActionCard(
                      icon: Icons.shopping_bag_outlined,
                      title: 'Kundenbestellungen',
                      subtitle: 'Sonderbestellungen von Kunden verwalten',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const CustomerOrderScreen(parentLabel: 'Laden'),
                        ),
                      ),
                    ),
                  if (isAdmin)
                    _QuickActionCard(
                      icon: Icons.badge_outlined,
                      title: 'Personal',
                      subtitle:
                          'Auftraege, Lohn-Richtwerte, Finanzen und Statistik',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const PersonalScreen(parentLabel: 'Laden'),
                        ),
                      ),
                    ),
                  if (isAdmin)
                    _QuickActionCard(
                      icon: Icons.history_outlined,
                      title: 'Änderungsprotokoll',
                      subtitle:
                          'Wer hat wann was geaendert (Lohn, Kontakte, Preise)',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const AuditLogScreen(parentLabel: 'Laden'),
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
              SectionHeader(
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
                              InfoChip(
                                icon: Icons.storefront_outlined,
                                label: primarySite?.name.trim().isEmpty ?? true
                                    ? 'Kein Stammstandort'
                                    : primarySite!.name,
                              ),
                              InfoChip(
                                icon: Icons.schedule_outlined,
                                label:
                                    '${work.settings.dailyHours.toStringAsFixed(1)} h Soll/Tag',
                              ),
                              InfoChip(
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
                  if (currentUser?.isAdmin ?? false)
                    _QuickActionCard(
                      icon: Icons.badge_outlined,
                      title: 'Personal',
                      subtitle:
                          'Auftraege, Lohn-Richtwerte, Finanzen und Statistik',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PersonalScreen(
                            parentLabel: 'Profil',
                          ),
                        ),
                      ),
                    ),
                  if (currentUser?.canViewInventory ?? false)
                    _QuickActionCard(
                      icon: Icons.inventory_2_outlined,
                      title: 'Warenwirtschaft',
                      subtitle:
                          'Bestand, Lieferanten und Bestellungen verwalten',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const InventoryScreen(
                            parentLabel: 'Profil',
                          ),
                        ),
                      ),
                    ),
                  if (currentUser?.canViewInventory ?? false)
                    _QuickActionCard(
                      icon: Icons.shopping_bag_outlined,
                      title: 'Kundenbestellungen',
                      subtitle:
                          'Sonderbestellungen von Kunden verwalten',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CustomerOrderScreen(
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
              SectionCard(
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
                InfoChip(
                  icon: Icons.schedule_outlined,
                  label: 'Soll ${plannedHours.toStringAsFixed(1)} h',
                ),
              InfoChip(
                icon: Icons.task_alt_outlined,
                label: 'Ist ${actualHours.toStringAsFixed(1)} h',
              ),
              if (plannedHours > 0)
                InfoChip(
                  icon: actualHours >= plannedHours
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  label: _formatSignedHours(actualHours - plannedHours),
                ),
              if (linkedEntries.isNotEmpty)
                InfoChip(
                  icon: Icons.link_rounded,
                  label:
                      '${linkedEntries.length} ${linkedEntries.length == 1 ? 'Link' : 'Links'}',
                ),
              if (unlinkedCount > 0)
                InfoChip(
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
                          InfoChip(
                            icon: Icons.schedule_outlined,
                            label:
                                'Soll ${shift.workedHours.toStringAsFixed(1)} h',
                          ),
                          InfoChip(
                            icon: Icons.task_alt_outlined,
                            label: linkedEntries.isEmpty
                                ? 'Noch kein Ist'
                                : 'Ist ${linkedHours.toStringAsFixed(1)} h',
                          ),
                          InfoChip(
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
                    child: CircularProgressIndicator.adaptive(),
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
