import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../core/accessibility.dart';
import '../core/analytics_service.dart';
import '../core/app_config.dart';
import '../core/redesign_flags.dart';
import '../core/work_entry_rules.dart';
import '../routing/route_permissions.dart';
import '../routing/shell_tab.dart';
import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/employee_site_assignment.dart';
import '../models/site_definition.dart';
import '../models/shift.dart';
import '../models/work_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/connectivity_status_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/parcel_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/storage_mode_provider.dart';
import '../providers/team_provider.dart';
import '../providers/work_provider.dart';
import '../providers/zeitwirtschaft_provider.dart';
import '../theme/app_theme.dart';
import 'search/global_search.dart';
import '../ui/app_card.dart';
import '../ui/app_hero_card.dart';
import '../ui/app_offline_banner.dart';
import '../ui/app_quick_action.dart';
import '../ui/app_section_card.dart';
import '../ui/app_stat_cards.dart';
import '../ui/app_status.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_nav_menu.dart';
import '../widgets/app_nav_rail.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/info_chip.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/section_card.dart';
import '../widgets/section_header.dart';
import '../widgets/theme_mode_button.dart';
import '../widgets/dashboard_action_items_card.dart';
import 'entry_form_screen.dart';
import 'contacts_screen.dart';
import 'fridge_refill_screen.dart';
import 'order_cart_screen.dart';
import 'notification_screen.dart';
import 'shift_planner_screen.dart';
import 'zeitwirtschaft/zeitwirtschaft_hub_screen.dart';

part 'home_screen_helpers.dart';
part 'home_screen_tabs.dart';
part 'home_dashboards_v2.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.navigationShell});

  /// Von der `StatefulShellRoute.indexedStack` injiziert. Ist zugleich der
  /// lazy, state-erhaltende IndexedStack der sieben Branches (ersetzt den
  /// früheren manuellen `_LazyDestinationStack`).
  final StatefulNavigationShell navigationShell;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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

  /// Cross-Tab-Zurück-Verlauf: zuletzt verlassene Tabs. Speist `PopScope.canPop`
  /// und das Zurück-Chevron im Tab-Header (via [_ShellScope]). Das ist die
  /// In-App-Tab-Historie — getrennt von der Browser-/System-Historie.
  final List<ShellTab> _navHistory = [];

  StatefulNavigationShell get _shell => widget.navigationShell;

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
    // Eng gescoptes Select: rebuildt die Shell nur, wenn sich die Badge-Zahl
    // (offene Anfragen + Tausch-Aktionen) ändert – nicht bei jeder Schicht.
    final inboxBadge =
        context.select<ScheduleProvider, int>((s) => s.pendingInboxActionCount);
    final useV2 = RedesignFlags.isOn(context);
    final destinations = _visibleDestinations(currentUser, useV2: useV2);
    final currentBranchIndex = _shell.currentIndex;
    // Metadaten des aktuellen Branch (auch wenn der Tab in der Nav versteckt
    // ist, z.B. /profil unter V2) -> liefert Label + FAB-Sichtbarkeit.
    final currentDestination =
        _destinationMeta(ShellTab.values[currentBranchIndex]);
    // Position des aktuellen Branch in der sichtbaren Liste; -1 (versteckter
    // Branch) -> 0 clampen, damit NavigationBar/Rail einen gültigen Index hat.
    final rawSelectedIndex = destinations.indexWhere(
      (destination) => shellBranchIndex(destination.id) == currentBranchIndex,
    );
    final selectedIndex = rawSelectedIndex == -1 ? 0 : rawSelectedIndex;
    final railDestinations = destinations
        .where((destination) => destination.id != ShellTab.profile)
        .toList(growable: false);
    final railSelectedIndex = railDestinations.indexWhere(
      (destination) => shellBranchIndex(destination.id) == currentBranchIndex,
    );

    // Desktop-/Web-Tastatur-Shortcuts (no-desktop-keyboard-shortcuts):
    // Strg/Ctrl + 1..9 springt auf das n-te Ziel der SICHTBAREN Navigation.
    // #57: layoutabhaengig — Rail nutzt railDestinations (ohne Profil),
    // die Bottom-Nav ihre tatsaechlich sichtbaren Ziele (V1 inkl. Profil,
    // V2 die feste 5er-Leiste). Die Breakpoint-Logik entspricht der im
    // LayoutBuilder unten (dessen Constraints sind hier die Bildschirmgroesse).
    final screenSize = MediaQuery.sizeOf(context);
    final useRailForShortcuts =
        MobileBreakpoints.useNavigationRail(screenSize.width) &&
            screenSize.height >= MobileBreakpoints.mediumWindow;
    final Map<ShortcutActivator, VoidCallback> shortcutBindings;
    if (useRailForShortcuts) {
      shortcutBindings = <ShortcutActivator, VoidCallback>{
        for (var i = 0;
            i < railDestinations.length && i < _navDigitKeys.length;
            i++)
          SingleActivator(_navDigitKeys[i], control: true): () =>
              _handleDestinationTap(i, destinations: railDestinations),
      };
    } else if (useV2) {
      final navEntries = _v2BottomNavEntries(currentUser);
      shortcutBindings = <ShortcutActivator, VoidCallback>{
        for (var i = 0;
            i < navEntries.length && i < _navDigitKeys.length;
            i++)
          SingleActivator(_navDigitKeys[i], control: true): () =>
              _handleBottomNavTap(navEntries[i]),
      };
    } else {
      shortcutBindings = <ShortcutActivator, VoidCallback>{
        for (var i = 0;
            i < destinations.length && i < _navDigitKeys.length;
            i++)
          SingleActivator(_navDigitKeys[i], control: true): () =>
              _handleDestinationTap(i, destinations: destinations),
      };
    }

    return CallbackShortcuts(
      bindings: shortcutBindings,
      child: FocusTraversalGroup(
        child: PopScope<void>(
          canPop: _navHistory.isEmpty,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) {
              return;
            }
            // #58: Enthaelt die Historie keine gueltige Rueck-Destination mehr
            // (z.B. nach Permission-Reduktion), den bereits konsumierten
            // System-Pop nachholen, statt den ersten Zurueck-Druck zu
            // verschlucken. Auf dem Web uebernimmt die Browser-Historie.
            if (!_navigateBackInShell()) {
              SystemNavigator.pop();
            }
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
              final body = _ShellScope(
                canGoBack: _navHistory.isNotEmpty,
                onGoBack: _handleShellBackPressed,
                child: _shell,
              );
              final shellContent = Column(
                children: [
                  SafeArea(
                    bottom: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ShellStatusBanner(
                          storageLocation: storageLocation,
                        ),
                        // Offline-Banner (Anf. 13): blendet sich nur bei
                        // fehlender Verbindung ein, rebuildet nur bei Wechsel.
                        // Im lokalen Modus NICHT zeigen: dort sagt bereits das
                        // Speichermodus-Banner ("Lokaler Modus aktiv"), dass
                        // nichts synchronisiert wird — ein zweites Offline-Band
                        // wäre redundant und sogar falsch ("später
                        // synchronisiert" gilt im local-Modus nie). Kurzschluss
                        // vor context.select: die Konnektivitäts-Abhängigkeit
                        // wird nur außerhalb des local-Modus registriert (ein
                        // Storage-Wechsel rebuildet die Shell und verdrahtet sie
                        // dann).
                        AppOfflineBanner(
                          offline: storageLocation !=
                                  DataStorageLocation.local &&
                              context.select<ConnectivityStatusProvider, bool>(
                                (c) => c.isOffline,
                              ),
                        ),
                      ],
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
                    ? _buildAppMenuDrawer(
                        currentUser,
                        authDisabled,
                        showAreas: true,
                      )
                    : null,
                endDrawer: (useV2 && useRail)
                    ? _buildAppMenuDrawer(
                        currentUser,
                        authDisabled,
                        showAreas: false,
                      )
                    : null,
                // Schmaler Rand: lässt dem horizontalen TableCalendar-/Wochen-Swipe
                // im ShiftPlanner Platz, statt ihn am linken Rand abzufangen.
                drawerEdgeDragWidth: useV2 ? 24 : null,
                appBar: (useV2 && !useRail)
                    ? _V2MenuTopBar(
                        onOpenMenu: () =>
                            _scaffoldKey.currentState?.openDrawer(),
                        showCart: currentUser?.canViewInventory ?? false,
                        onOpenCart: () => context.push(
                          '${AppRoutes.inventory}?tab=korb',
                        ),
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
                                      badgeCount:
                                          destination.id == ShellTab.inbox
                                              ? inboxBadge
                                              : 0,
                                    ),
                                ],
                                selectedIndex: railSelectedIndex,
                                onSelected: (index) => _handleDestinationTap(
                                  index,
                                  destinations: railDestinations,
                                ),
                                onOpenMenu: () =>
                                    _scaffoldKey.currentState?.openEndDrawer(),
                                onSearch: () => showGlobalSearch(context),
                                // Hell/Dunkel liegt bewusst nur unter „Profil",
                                // nicht mehr in der Navigations-Rail.
                                user: currentUser,
                                expandedLabels: expandedRailLabels,
                              )
                            else ...[
                              NavigationRail(
                                // Breit genug für den 96px-Profil-Header im
                                // Leading (sonst RenderFlex-Overflow in der Rail).
                                minWidth: 124,
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
                                            ShellTab.profile,
                                        onTap: () => _activateDestination(
                                          ShellTab.profile,
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
                                      icon: _badgedNavIcon(
                                        destination.icon,
                                        destination.id,
                                        inboxBadge,
                                      ),
                                      selectedIcon: _badgedNavIcon(
                                        destination.selectedIcon,
                                        destination.id,
                                        inboxBadge,
                                      ),
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
                    : _buildBottomNavBar(
                        useV2: useV2,
                        user: currentUser,
                        currentBranchIndex: currentBranchIndex,
                        inboxBadge: inboxBadge,
                        destinations: destinations,
                        selectedIndex: selectedIndex,
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

  /// Wechselt auf den Branch von [id] (über `goBranch`). Re-Tap des aktiven
  /// Tabs setzt dessen Branch auf die Wurzel zurück. Cross-Tab-Wechsel werden
  /// für die In-App-Zurück-Geste in [_navHistory] protokolliert.
  void _activateDestination(ShellTab id, {bool recordHistory = true}) {
    if (!mounted) {
      return;
    }
    final branchIndex = shellBranchIndex(id);
    final currentIndex = _shell.currentIndex;
    if (branchIndex == currentIndex) {
      _shell.goBranch(branchIndex, initialLocation: true);
      return;
    }
    if (recordHistory) {
      _navHistory.add(ShellTab.values[currentIndex]);
    }
    _shell.goBranch(branchIndex);
    // goBranch rebuildet die Shell ohnehin; setState aktualisiert zusätzlich die
    // von _navHistory abhängige Nav-Chrome (PopScope.canPop / Zurück-Chevron).
    setState(() {});

    // Screen-Tracking (no-analytics-screen-tracking), datensparsam: nur
    // Tab-Name + Rolle, keine personenbezogenen Daten.
    AnalyticsService.logScreenView(
      id.name,
      role: context.read<AuthProvider>().profile?.role.name,
    );
  }

  bool _navigateBackInShell() {
    var switched = false;
    while (_navHistory.isNotEmpty) {
      final previous = _navHistory.removeLast();
      final branchIndex = shellBranchIndex(previous);
      if (branchIndex == _shell.currentIndex) {
        continue;
      }
      if (mounted) {
        _shell.goBranch(branchIndex, initialLocation: false);
      }
      switched = true;
      break;
    }
    if (mounted) {
      setState(() {});
    }
    return switched;
  }

  void _handleShellBackPressed() {
    _navigateBackInShell();
  }

  void _handleDestinationTap(
    int index, {
    required List<_ShellDestination> destinations,
  }) {
    _activateDestination(destinations[index].id);
  }

  /// Untere Navigationsleiste. Das Framework rendert die Labels als nacktes
  /// `Text` (kein maxLines) UND skaliert sie mit der System-Schrift bis 1,3×
  /// hoch -> lange Labels brechen sonst auf zwei Zeilen um. Wir deckeln die
  /// Label-Skalierung hier auf 1,0 (Icons/Indikator skalieren ohnehin nicht),
  /// damit die Leiste bei jeder Geräte-Schriftgröße einzeilig bleibt.
  Widget _buildBottomNavBar({
    required bool useV2,
    required AppUserProfile? user,
    required int currentBranchIndex,
    required int inboxBadge,
    required List<_ShellDestination> destinations,
    required int selectedIndex,
  }) {
    if (!useV2) {
      // V1: unveränderte, permission-gefilterte Branch-Leiste.
      return MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.0,
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) =>
              _handleDestinationTap(index, destinations: destinations),
          destinations: [
            for (final destination in destinations)
              NavigationDestination(
                icon: _badgedNavIcon(
                  destination.icon,
                  destination.id,
                  inboxBadge,
                ),
                selectedIcon: _badgedNavIcon(
                  destination.selectedIcon,
                  destination.id,
                  inboxBadge,
                ),
                label: destination.label,
              ),
          ],
        ),
      );
    }

    // V2: feste 5er-Leiste (Heute · Plan · Scanner · Anfragen · Mehr). Scanner
    // pusht eine Route, »Mehr« öffnet das Slide-in-Menü — beides sind KEINE
    // Shell-Branches. Liegt der aktive Branch nicht in der Leiste (Zeit/
    // Kontakte/Laden, über »Mehr« geöffnet), wird »Mehr« markiert.
    final entries = _v2BottomNavEntries(user);
    final currentBranch = ShellTab.values[currentBranchIndex];
    var selected = entries.indexWhere((e) => e.branch == currentBranch);
    if (selected == -1) {
      final moreIndex = entries.indexWhere((e) => e.kind == _BottomNavKind.more);
      selected = moreIndex == -1 ? 0 : moreIndex;
    }
    return MediaQuery.withClampedTextScaling(
      // Text-Scaling nicht hart auf 1.0 klemmen (Accessibility), aber moderat
      // deckeln, damit die Nav-Labels nicht die Leiste sprengen.
      maxScaleFactor: 1.3,
      child: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (index) => _handleBottomNavTap(entries[index]),
        destinations: [
          for (final entry in entries)
            NavigationDestination(
              icon: entry.showInboxBadge
                  ? _badgedNavIcon(entry.icon, ShellTab.inbox, inboxBadge)
                  : Icon(entry.icon),
              selectedIcon: entry.showInboxBadge
                  ? _badgedNavIcon(entry.selectedIcon, ShellTab.inbox, inboxBadge)
                  : Icon(entry.selectedIcon),
              label: entry.label,
            ),
        ],
      ),
    );
  }

  /// Die festen V2-Bottomnav-Einträge in Reihenfolge: Heute · Plan · Scanner ·
  /// Anfragen · Mehr. Plan und Scanner sind berechtigungsabhängig (fehlt das
  /// Recht, schrumpft die Leiste); Heute/Anfragen/Mehr sind immer da.
  List<_BottomNavEntry> _v2BottomNavEntries(AppUserProfile? user) {
    return [
      const _BottomNavEntry.branch(
        branch: ShellTab.today,
        label: 'Heute',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
      ),
      if (RoutePermissions.isShellTabAllowed(ShellTab.plan, user))
        const _BottomNavEntry.branch(
          branch: ShellTab.plan,
          label: 'Plan',
          icon: Icons.view_timeline_outlined,
          selectedIcon: Icons.view_timeline,
        ),
      if (RoutePermissions.isLocationAllowed(AppRoutes.scanner, user))
        const _BottomNavEntry.scanner(),
      const _BottomNavEntry.branch(
        branch: ShellTab.inbox,
        label: 'Anfragen',
        icon: Icons.inbox_outlined,
        selectedIcon: Icons.inbox,
        showInboxBadge: true,
      ),
      const _BottomNavEntry.more(),
    ];
  }

  void _handleBottomNavTap(_BottomNavEntry entry) {
    switch (entry.kind) {
      case _BottomNavKind.branch:
        _activateDestination(entry.branch!);
      case _BottomNavKind.scanner:
        // Scanner ist eine über die Shell gepushte Route, kein Branch.
        context.push(AppRoutes.scanner);
      case _BottomNavKind.more:
        // »Mehr« öffnet dasselbe Slide-in-Menü wie der Avatar in der V2-AppBar.
        _scaffoldKey.currentState?.openDrawer();
    }
  }

  /// Schließt das »Mehr«-Menü und wechselt auf einen Shell-Branch (Zeit/
  /// Kontakte/Laden), der nicht mehr in der Bottomnav liegt.
  void _openBranchFromMenu(ShellTab tab) {
    _closeAppMenu();
    _activateDestination(tab);
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

    // Sekundär: Schnellaktionen (öffnet ein Sheet). Schlichter runder FAB im
    // App-FAB-Stil – kein eigener Verlauf mehr, damit alle FABs einheitlich sind.
    final actionsFab = FloatingActionButton(
      heroTag: 'shell_actions_fab',
      tooltip: canManageShifts ? 'Aktionen' : 'Schnellaktionen',
      onPressed: canManageShifts
          ? () => _showPlannerQuickActions(destinations)
          : () => _showEmployeeQuickActions(
                currentDestinationLabel: destination.label,
              ),
      child: const Icon(Icons.bolt_rounded),
    );

    if (!canEditTimeEntries) {
      return actionsFab;
    }

    // Primär & dauerhaft sichtbar: die Stempeluhr als prominenter Status-Button.
    // Grün „Einstempeln" / rot „Ausstempeln" – Farbe und Symbol spiegeln den
    // Zustand der EINEN persistenten Stempeluhr ([ZeitwirtschaftProvider]).
    // Tippen öffnet den Stempel-Bildschirm (Laden-Auswahl + Kommen/Gehen).
    final active = context.watch<ZeitwirtschaftProvider>().isClockedIn;
    final punchClockFab = FloatingActionButton.extended(
      heroTag: 'shell_punch_clock_fab',
      tooltip: active
          ? 'Stempeluhr oeffnen und ausstempeln'
          : 'Stempeluhr oeffnen',
      onPressed: work.currentUser == null
          ? null
          : () => context.push(AppRoutes.zeitStempeln),
      backgroundColor: active ? colorScheme.error : appColors.success,
      foregroundColor: active ? colorScheme.onError : appColors.onSuccess,
      icon: Icon(active ? Icons.logout_rounded : Icons.login_rounded),
      label: Text(active ? 'Ausstempeln' : 'Einstempeln'),
    );

    // Nebeneinander statt gestapelt: Die Höhe bleibt die eines einzelnen FAB,
    // damit nicht plötzlich mehr Listeninhalt verdeckt wird. Stempeluhr ganz
    // rechts (Primärposition), Aktionen links daneben als Sekundärbutton.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        actionsFab,
        const SizedBox(width: 14),
        punchClockFab,
      ],
    );
  }


  // Hauptbereich-Routen über die Shell pushen (Back kehrt zum Hub zurück).
  Future<void> _pushMonthReport() => context.push(AppRoutes.monthReport);

  /// Schließt das Slide-in-Menü und navigiert zur Section-Route — Back führt
  /// dann zum Tab zurück, nicht in einen offenen Drawer.
  void _openSection(String location) {
    _closeAppMenu();
    context.push(location);
  }

  // EntryForm bleibt imperativ (Editor-Screen ohne eigene Route).
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

  /// Öffnet den Schnell-„In den Warenkorb"-Sheet aus einer Schnellaktion heraus
  /// (schließt zuerst das Schnellaktionen-Sheet). Standorte aus dem TeamProvider,
  /// Fallback auf den WorkProvider (gleiche Quelle wie an anderen Stellen).
  Future<void> _openQuickAddCartFromSheet(BuildContext sheetContext) async {
    final team = context.read<TeamProvider>();
    final work = context.read<WorkProvider>();
    final sites = team.sites.isNotEmpty ? team.sites : work.sites;
    Navigator.of(sheetContext).pop();
    await showQuickAddCartSheet(context, sites: sites);
  }

  /// Öffnet den „Kühlschrank nachfüllen"-Sheet aus einer Schnellaktion heraus
  /// (schließt zuerst das Schnellaktionen-Sheet). Gleiche Standort-Quelle wie
  /// der Warenkorb-Schnellzugriff.
  Future<void> _openFridgeRefillFromSheet(BuildContext sheetContext) async {
    final team = context.read<TeamProvider>();
    final work = context.read<WorkProvider>();
    final sites = team.sites.isNotEmpty ? team.sites : work.sites;
    Navigator.of(sheetContext).pop();
    await showFridgeRefillAddSheet(context, sites: sites);
  }

  Future<void> _showPlannerQuickActions(
    List<_ShellDestination> destinations,
  ) async {
    if (!mounted) {
      return;
    }
    final currentUser = context.read<AuthProvider>().profile;
    final hasTimeDestination = destinations.any(
      (destination) => destination.id == ShellTab.time,
    );
    final hasInboxDestination = destinations.any(
      (destination) => destination.id == ShellTab.inbox,
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
                      onTap: () => _jumpToDestination(ShellTab.time),
                    ),
                  if (hasInboxDestination)
                    _QuickActionListTile(
                      icon: Icons.inbox_outlined,
                      title: 'Offene Anfragen pruefen',
                      subtitle:
                          'Krankmeldungen, Urlaub und Tausch sofort sehen',
                      onTap: () => _jumpToDestination(ShellTab.inbox),
                    ),
                  if (currentUser?.canViewInventory ?? false)
                    _QuickActionListTile(
                      icon: Icons.add_shopping_cart_outlined,
                      title: 'In den Warenkorb',
                      subtitle: 'Ware schnell zum Bestellen in den Korb legen',
                      onTap: () => _openQuickAddCartFromSheet(sheetContext),
                    ),
                  if (currentUser?.canViewInventory ?? false)
                    _QuickActionListTile(
                      icon: Icons.kitchen_outlined,
                      title: 'Kühlschrank nachfüllen',
                      subtitle: 'Markieren, was aus dem Lager nachgefüllt wird',
                      onTap: () => _openFridgeRefillFromSheet(sheetContext),
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
                    icon: Icons.badge_outlined,
                    title: 'Personal',
                    subtitle:
                        'Mitarbeiter, Rollen, Standorte und Organisation',
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await context.push(AppRoutes.personal);
                    },
                  ),
                  // REPORTING-4: Management-Kennzahlen (Admin + Schichtleitung).
                  if ((currentUser?.isAdmin ?? false) ||
                      (currentUser?.canManageShifts ?? false))
                    _QuickActionListTile(
                      icon: Icons.insights_outlined,
                      title: 'Kennzahlen',
                      subtitle:
                          'Org-weite Zeit-, Bestands- und Umsatz-Kennzahlen',
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await context.push(AppRoutes.kennzahlen);
                      },
                    ),
                  // REPORTING-6: Standortvergleich (admin-only).
                  if (currentUser?.isAdmin ?? false)
                    _QuickActionListTile(
                      icon: Icons.compare_arrows_outlined,
                      title: 'Standortvergleich',
                      subtitle: 'Läden nebeneinander: Umsatz, Rohertrag, Lohn',
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await context.push(AppRoutes.standortvergleich);
                      },
                    ),
                  // PERSONAL-9/Q4: Mitteilungs-Inbox (jeder Nutzer).
                  _QuickActionListTile(
                    icon: Icons.notifications_none_outlined,
                    title: context.read<NotificationProvider>().unreadCount > 0
                        ? 'Mitteilungen (${context.read<NotificationProvider>().unreadCount})'
                        : 'Mitteilungen',
                    subtitle: 'Erinnerungen und Systemnachrichten',
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await context.push(AppRoutes.mitteilungen);
                    },
                  ),
                  if (currentUser?.canViewReports ?? false)
                    _QuickActionListTile(
                      icon: Icons.description_outlined,
                      title: 'Monatsbericht',
                      subtitle: 'PDF und Monatsauswertung direkt aufrufen',
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await _pushMonthReport();
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
                  if (currentUser?.canViewInventory ?? false)
                    _QuickActionListTile(
                      icon: Icons.add_shopping_cart_outlined,
                      title: 'In den Warenkorb',
                      subtitle: 'Ware schnell zum Bestellen in den Korb legen',
                      onTap: () => _openQuickAddCartFromSheet(sheetContext),
                    ),
                  if (currentUser?.canViewInventory ?? false)
                    _QuickActionListTile(
                      icon: Icons.kitchen_outlined,
                      title: 'Kühlschrank nachfüllen',
                      subtitle: 'Markieren, was aus dem Lager nachgefüllt wird',
                      onTap: () => _openFridgeRefillFromSheet(sheetContext),
                    ),
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
                  // PERSONAL-9/Q4: Mitteilungs-Inbox (jeder Nutzer).
                  _QuickActionListTile(
                    icon: Icons.notifications_none_outlined,
                    title: context.read<NotificationProvider>().unreadCount > 0
                        ? 'Mitteilungen (${context.read<NotificationProvider>().unreadCount})'
                        : 'Mitteilungen',
                    subtitle: 'Erinnerungen und Systemnachrichten',
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await context.push(AppRoutes.mitteilungen);
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

  void _jumpToDestination(ShellTab id) {
    Navigator.of(context).pop();
    _activateDestination(id);
  }

  /// Baut den Inhalt des V2-Slide-in-Menüs. Wird sowohl als `drawer` (links)
  /// als auch als `endDrawer` (rechts) verwendet. Der `Consumer2`-Teilbaum wird
  /// erst beim Öffnen des Drawers gebaut (geschlossen ist er nicht im Tree),
  /// abonniert Team/Work also nur dann und weitet die Shell-Rebuilds nicht aus.
  Widget _buildAppMenuDrawer(
    AppUserProfile? user,
    bool authDisabled, {
    required bool showAreas,
  }) {
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

          // Scanner-Einstieg im Menü für alle, die Inventar verwalten dürfen —
          // plattformunabhängig (passend zum festen Scanner-Tab in der Mitte der
          // Bottomnav). Off-Mobile bietet der ScannerScreen die manuelle Eingabe.
          final showScanner = user?.canUseScanner ?? false;

          return AppNavMenu(
            user: user,
            authDisabled: authDisabled,
            showScanner: showScanner,
            // Die aus der Bottomnav ausgelagerten Bereiche nur im mobilen
            // Drawer zeigen — in der Rail (endDrawer) stehen sie schon links.
            showAreas: showAreas,
            siteName: siteName,
            dailyHours: work.settings.dailyHours,
            vacationDays: work.settings.vacationDays,
            selectedArea: _destinationMeta(
              ShellTab.values[_shell.currentIndex],
            ).label,
            onClose: _closeAppMenu,
            onSignOut: () {
              _closeAppMenu();
              context.read<AuthProvider>().signOut();
            },
            onOpenTime: () => _openBranchFromMenu(ShellTab.time),
            onOpenContacts: () => _openBranchFromMenu(ShellTab.contacts),
            onOpenShop: () => _openBranchFromMenu(ShellTab.shop),
            onOpenMonthReport: () => _openSection(AppRoutes.monthReport),
            onOpenStatistics: () => _openSection(AppRoutes.statistics),
            onOpenPersonal: () => _openSection(AppRoutes.personal),
            onOpenFinance: () => _openSection(AppRoutes.finance),
            onOpenInventory: () => _openSection(AppRoutes.inventory),
            onOpenCustomerOrders: () => _openSection(AppRoutes.customerOrders),
            onOpenOrderAnalytics: () => _openSection(AppRoutes.orderAnalytics),
            onOpenScanner: () => _openSection(AppRoutes.scanner),
            onOpenSettings: () => _openSection(AppRoutes.settings),
            onOpenMeineAkte: () => _openSection(AppRoutes.meineAkte),
            onOpenKnowledge: () => _openSection(AppRoutes.knowledge),
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

  /// Metadaten (Label/Icons/FAB) einer [ShellTab] — permission-unabhängig, damit
  /// auch der aktuell aktive (ggf. in der Nav versteckte) Branch ein Label und
  /// die richtige FAB-Sichtbarkeit hat.
  /// Icon einer Nav-Destination, am Anfragen-Tab mit Zähler-Badge versehen.
  Widget _badgedNavIcon(IconData icon, ShellTab tab, int inboxBadge) {
    if (tab == ShellTab.inbox && inboxBadge > 0) {
      return Badge(label: Text('$inboxBadge'), child: Icon(icon));
    }
    return Icon(icon);
  }

  _ShellDestination _destinationMeta(ShellTab tab) {
    switch (tab) {
      case ShellTab.today:
        return const _ShellDestination(
          id: ShellTab.today,
          label: 'Heute',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          showFab: true,
        );
      case ShellTab.plan:
        return const _ShellDestination(
          id: ShellTab.plan,
          label: 'Plan',
          icon: Icons.view_timeline_outlined,
          selectedIcon: Icons.view_timeline,
          showFab: true,
        );
      case ShellTab.time:
        return const _ShellDestination(
          id: ShellTab.time,
          label: 'Zeit',
          icon: Icons.schedule_outlined,
          selectedIcon: Icons.schedule,
          showFab: true,
        );
      case ShellTab.inbox:
        return const _ShellDestination(
          id: ShellTab.inbox,
          label: 'Anfragen',
          icon: Icons.inbox_outlined,
          selectedIcon: Icons.inbox,
          showFab: true,
        );
      case ShellTab.contacts:
        // Kontakte bringen ihren eigenen FAB ("Neuer Kontakt") mit; der
        // schicht-/zeitbezogene Shell-FAB ist hier bewusst aus.
        return const _ShellDestination(
          id: ShellTab.contacts,
          label: 'Kontakte',
          icon: Icons.contacts_outlined,
          selectedIcon: Icons.contacts,
        );
      case ShellTab.shop:
        // "Laden" buendelt die Geschaefts-Module (Warenwirtschaft,
        // Kundenbestellungen, Personal) als ein einziger Tab.
        return const _ShellDestination(
          id: ShellTab.shop,
          label: 'Laden',
          icon: Icons.storefront_outlined,
          selectedIcon: Icons.storefront,
        );
      case ShellTab.profile:
        return const _ShellDestination(
          id: ShellTab.profile,
          label: 'Profil',
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
        );
    }
  }

  /// Permission-Sichtbarkeit eines Tabs in der Nav-Bar. Der Branch existiert in
  /// der Route IMMER (statisch) — hier wird nur entschieden, ob ein Nav-Item
  /// gezeigt wird. In V2 ersetzt das Slide-in-Menü den Profil-Tab.
  bool _isTabVisible(ShellTab tab, AppUserProfile? user, {required bool useV2}) {
    // Reiner Darstellungs-Sonderfall: im V2-Design ersetzt das Slide-in-Menü
    // den Profil-Tab. Das ist KEINE Berechtigung und bleibt daher hier.
    if (tab == ShellTab.profile && useV2) {
      return false;
    }
    // Berechtigungs-Matrix zentral (geteilt mit dem Router-Redirect, H-H2):
    // löst u. a. die frühere Shop-Tab-Divergenz auf (canViewInventory statt
    // `canViewInventory || isAdmin`).
    return RoutePermissions.isShellTabAllowed(tab, user);
  }

  /// Sichtbare Nav-Items (nach Permissions gefiltert), in kanonischer
  /// [ShellTab]-Reihenfolge. Jedes Item trägt seine [ShellTab] → Branch-Index
  /// immer via [shellBranchIndex], nie über die Listenposition.
  List<_ShellDestination> _visibleDestinations(
    AppUserProfile? user, {
    bool useV2 = false,
  }) {
    return [
      for (final tab in ShellTab.values)
        if (_isTabVisible(tab, user, useV2: useV2)) _destinationMeta(tab),
    ];
  }
}

class _ShellDestination {
  const _ShellDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.showFab = false,
  });

  final ShellTab id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool showFab;
}

/// Art eines V2-Bottomnav-Eintrags: ein Shell-Branch (Tab-Wechsel), der Scanner
/// (gepushte Route) oder »Mehr« (öffnet das Slide-in-Menü).
enum _BottomNavKind { branch, scanner, more }

/// Ein Eintrag der festen V2-Bottomnav. Anders als [_ShellDestination] kann ein
/// Eintrag auch eine Aktion ohne eigenen Branch sein (Scanner/Mehr).
class _BottomNavEntry {
  const _BottomNavEntry({
    required this.kind,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.branch,
    this.showInboxBadge = false,
  });

  const _BottomNavEntry.branch({
    required ShellTab branch,
    required String label,
    required IconData icon,
    required IconData selectedIcon,
    bool showInboxBadge = false,
  }) : this(
          kind: _BottomNavKind.branch,
          label: label,
          icon: icon,
          selectedIcon: selectedIcon,
          branch: branch,
          showInboxBadge: showInboxBadge,
        );

  const _BottomNavEntry.scanner()
      : this(
          kind: _BottomNavKind.scanner,
          label: 'Scanner',
          icon: Icons.qr_code_scanner_outlined,
          selectedIcon: Icons.qr_code_scanner,
        );

  const _BottomNavEntry.more()
      : this(
          kind: _BottomNavKind.more,
          label: 'Mehr',
          icon: Icons.menu,
          selectedIcon: Icons.menu,
        );

  final _BottomNavKind kind;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Zugehöriger Shell-Branch — nur bei [_BottomNavKind.branch] gesetzt.
  final ShellTab? branch;

  /// Ob das Icon das Anfragen-Badge (offene Inbox-Aktionen) trägt.
  final bool showInboxBadge;
}

/// Reicht die Cross-Tab-Zurück-Geste der Shell an die Tab-Inhalte. Die Inhalte
/// werden in den `StatefulShellRoute`-Branches gebaut und liegen damit im
/// Widget-Baum UNTERHALB dieser InheritedWidget; [buildHomeTab] liest sie hier.
class _ShellScope extends InheritedWidget {
  const _ShellScope({
    required this.canGoBack,
    required this.onGoBack,
    required super.child,
  });

  final bool canGoBack;
  final VoidCallback onGoBack;

  static _ShellScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShellScope>();

  @override
  bool updateShouldNotify(_ShellScope oldWidget) =>
      canGoBack != oldWidget.canGoBack;
}

/// Schlanke V2-Top-Bar im Bottom-Nav-Modus: ein eindeutiger Menü-Button links
/// öffnet das Slide-in-Menü. Bewusst ohne Titel — den Abschnittstitel liefert
/// weiterhin der `SectionHeader` jedes Tabs (kein Doppel-Header).
class _V2MenuTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _V2MenuTopBar({
    required this.onOpenMenu,
    required this.showCart,
    required this.onOpenCart,
  });

  final VoidCallback onOpenMenu;

  /// Ob der Warenkorb-Knopf oben rechts gezeigt wird (nur mit Waren-Recht).
  final bool showCart;
  final VoidCallback onOpenCart;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      leadingWidth: 64,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Semantics(
          button: true,
          label: 'Menü öffnen',
          child: IconButton(
            tooltip: 'Menü',
            onPressed: onOpenMenu,
            icon: const Icon(Icons.menu_rounded),
          ),
        ),
      ),
      actions: [
        // Der Hell/Dunkel-Umschalter ist bewusst nicht mehr in der App-Leiste,
        // sondern nur noch unter „Profil" versteckt (und im Einstellungs-Hub).
        // Globale Suche (Anf. 24/25): 1-Tap-Sprung zu Bereich/Datensatz.
        IconButton(
          tooltip: 'Suchen',
          icon: const Icon(Icons.search_rounded),
          onPressed: () => showGlobalSearch(context),
        ),
        if (showCart)
          // Warenkorb oben rechts, mit Stück-Badge (Summe über alle Läden).
          // Eigenes Selector -> nur dieses Icon rebuildet bei Korb-Änderungen,
          // nicht die ganze Shell.
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Selector<InventoryProvider, int>(
              selector: (_, inventory) => inventory.cartItemCount(),
              builder: (context, count, _) {
                const cartIcon = Icon(Icons.shopping_cart_outlined);
                return IconButton(
                  tooltip: 'Warenkorb',
                  onPressed: onOpenCart,
                  icon: count > 0
                      ? Badge(label: Text('$count'), child: cartIcon)
                      : cartIcon,
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Initial (Großbuchstabe) für Avatare — sicher bei leerem/null Namen.
/// `''.characters.first` würde sonst einen StateError werfen.
String _initialFor(String? name) {
  final trimmed = (name ?? '').trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.characters.first.toUpperCase();
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
                child: Text(_initialFor(user?.displayName)),
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

/// Baut den Inhalt einer Shell-Branch. Wird von den
/// `StatefulShellRoute`-Branches in `app_router.dart` aufgerufen; der `context`
/// liegt damit unterhalb der HomeScreen-Shell und sieht [_ShellScope] (für die
/// Cross-Tab-Zurück-Geste). V1/V2-Wahl der Dashboards via [RedesignFlags.isOn].
Widget buildHomeTab(BuildContext context, ShellTab tab) {
  final useV2 = RedesignFlags.isOn(context);
  final user = context.watch<AuthProvider>().profile;
  final scope = _ShellScope.of(context);
  final canBack = scope?.canGoBack ?? false;
  final onBack = scope?.onGoBack;

  switch (tab) {
    case ShellTab.today:
      final canManageShifts = user?.canManageShifts ?? false;
      if (canManageShifts) {
        return useV2
            ? _AdminDashboardTabV2(
                onOpenPlan: () => _openPlanFromTab(context),
                onOpenPlanForDate: (date) =>
                    _openPlanForDateFromTab(context, date),
                canNavigateBack: canBack,
                onNavigateBack: onBack,
              )
            : _AdminDashboardTab(
                onOpenPlan: () => _openPlanFromTab(context),
                onOpenPlanForDate: (date) =>
                    _openPlanForDateFromTab(context, date),
                canNavigateBack: canBack,
                onNavigateBack: onBack,
              );
      }
      return useV2
          ? _EmployeeDashboardTabV2(
              canNavigateBack: canBack,
              onNavigateBack: onBack,
            )
          : _EmployeeDashboardTab(
              canNavigateBack: canBack,
              onNavigateBack: onBack,
            );
    case ShellTab.plan:
      // Dichtes Wochen-/Monats-Raster: lokal auf 1,5 klemmen (gestufte
      // Dynamic-Type-Leiter E1), waehrend die App global bis 2,0 skaliert.
      return DenseContentTextScale(
        child: ShiftPlannerScreen(
          canNavigateBack: canBack,
          onNavigateBack: onBack,
        ),
      );
    case ShellTab.time:
      return ZeitwirtschaftHubScreen(
        canNavigateBack: canBack,
        onNavigateBack: onBack,
      );
    case ShellTab.inbox:
      return NotificationScreen(
        canNavigateBack: canBack,
        onNavigateBack: onBack,
      );
    case ShellTab.contacts:
      return ContactsScreen(
        canNavigateBack: canBack,
        onNavigateBack: onBack,
      );
    case ShellTab.shop:
      return _ShopHubTab(
        canNavigateBack: canBack,
        onNavigateBack: onBack,
      );
    case ShellTab.profile:
      return _ProfileHubTab(
        canNavigateBack: canBack,
        onNavigateBack: onBack,
      );
  }
}

/// Wechselt auf den Plan-Tab (aus einem Dashboard heraus). Nur mit Berechtigung.
Future<void> _openPlanFromTab(BuildContext context) async {
  final user = context.read<AuthProvider>().profile;
  if (!(user?.canViewSchedule ?? false)) {
    return;
  }
  context.go(shellTabPaths[ShellTab.plan]!);
}

/// Wechselt auf den Plan-Tab und stellt das Tagesdatum ein (gleiche Reihenfolge
/// der ScheduleProvider-Mutationen wie zuvor in der Shell).
Future<void> _openPlanForDateFromTab(
  BuildContext context,
  DateTime focusDate,
) async {
  final user = context.read<AuthProvider>().profile;
  if (!(user?.canViewSchedule ?? false)) {
    return;
  }
  final schedule = context.read<ScheduleProvider>();
  final normalized = DateUtils.dateOnly(focusDate);
  if (schedule.viewMode != ScheduleViewMode.day) {
    schedule.setViewMode(ScheduleViewMode.day);
  }
  if (!DateUtils.isSameDay(schedule.visibleDate, normalized)) {
    schedule.setVisibleDate(normalized);
  }
  if (context.mounted) {
    context.go(shellTabPaths[ShellTab.plan]!);
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
              '${DateFormat('HH:mm', 'de_DE').format(shift.startTime)} - ${DateFormat('HH:mm', 'de_DE').format(shift.endTime)}',
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textWidget = Text(
              text!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            );
            final syncButton = TextButton(
              onPressed: () => _syncNow(context),
              child: const Text('Jetzt synchronisieren'),
            );
            // Auf schmalen Geräten Text und Sync-Aktion untereinander, sonst
            // sprengt der Button bei langem Text/großem Text-Scaling die Row.
            if (showSyncAction && constraints.maxWidth < 360) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: color, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: textWidget),
                    ],
                  ),
                  Align(alignment: Alignment.centerLeft, child: syncButton),
                ],
              );
            }
            return Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 10),
                Expanded(child: textWidget),
                if (showSyncAction) syncButton,
              ],
            );
          },
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;

    // [AppCard] liefert die einheitliche Karten-Optik (surfaceContainerLow,
    // Hairline-Rand aus dem CardTheme, weicher Schatten, geclippte Ripple) —
    // damit traegt der Laden-Hub denselben Look wie die uebrigen V2-Screens.
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon-Chip links, Chevron rechts oben. Der Chevron liegt bewusst
          // hier (nicht in der Titel-Zeile), damit der Titel die volle Breite
          // hat und nicht mitten im Wort umbricht.
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(spacing.sm + spacing.xxs),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(context.radii.md),
                ),
                child: Icon(
                  icon,
                  color: colorScheme.onPrimaryContainer,
                  size: context.iconSizes.md,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
                size: context.iconSizes.sm,
              ),
            ],
          ),
          SizedBox(height: spacing.md),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          SizedBox(height: spacing.xs + spacing.xxs),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
        ],
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
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Row(
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
        if (onTap != null)
          Icon(
            Icons.chevron_right,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
      ],
    );
    if (onTap == null) {
      return row;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: row,
      ),
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
    // Eine persistente Stempeluhr ([ZeitwirtschaftProvider]) — frei stempelbar.
    final isClockActive = context.watch<ZeitwirtschaftProvider>().isClockedIn;
    final primaryAssignment =
        _resolvePrimaryAssignment(team, provider.currentUser?.uid);
    final primarySite = _resolvePrimarySite(
      team.sites.isNotEmpty ? team.sites : provider.sites,
      primaryAssignment,
    );
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
                '${DateFormat('HH:mm', 'de_DE').format(nextShift.startTime)} - ${DateFormat('HH:mm', 'de_DE').format(nextShift.endTime)}',
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
                  onPressed: () => context.push(AppRoutes.zeitStempeln),
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
            if (nextShift == null) ...[
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
                    ? DateFormat('HH:mm', 'de_DE').format(dayShifts.first.startTime)
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
                    DateFormat('dd.MM.', 'de_DE').format(day),
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
    this.onOpenDecision,
  });

  final List<AbsenceRequest> pendingAbsences;
  final List<Shift> pendingSwapRequests;

  /// Öffnet die Entscheidung (Anfragen-Tab). Ist er gesetzt, werden die
  /// Einträge antippbar.
  final VoidCallback? onOpenDecision;

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
          if (onOpenDecision != null)
            InkWell(
              onTap: onOpenDecision,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: items[i],
              ),
            )
          else
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

/// "Laden"-Tab: ein gebündelter Einstieg in die Geschäftsmodule. Der wichtigste
/// Arbeitsbereich steht prominent oben; alle weiteren Ziele sind nach Aufgabe
/// gruppiert. Die Module bleiben eigenständige, gepushte Screens (Back → Hub).
class _ShopHubTab extends StatelessWidget {
  const _ShopHubTab({required this.canNavigateBack, this.onNavigateBack});

  final bool canNavigateBack;
  final VoidCallback? onNavigateBack;

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().profile;
    final canViewInventory = currentUser?.canViewInventory ?? false;
    final isAdmin = currentUser?.isAdmin ?? false;
    final canManageFeedback = currentUser?.canManageFeedback ?? false;
    final canViewParcels = currentUser?.canViewParcels ?? false;
    final screenPad = MobileBreakpoints.screenPadding(context);

    // Live-Status fuer die Warenwirtschafts-Kacheln: knappe Bestaende +
    // offene Kundenbestellungen. Beides liest nur In-Memory-Listen (leer ⇒ 0,
    // also kein Pill) — sicher auch im Offline-/Demo-Modus.
    var lowStockCount = 0;
    var openCustomerOrderCount = 0;
    if (canViewInventory) {
      final inventory = context.watch<InventoryProvider>();
      lowStockCount = inventory.lowStockProducts().length;
      openCustomerOrderCount = inventory.openCustomerOrders.length;
    }

    // Paketshop-Status: offene + überfällige Pakete (nur In-Memory,
    // leer ⇒ 0, also offline/Demo-sicher).
    var openParcelCount = 0;
    var overdueParcelCount = 0;
    if (canViewParcels) {
      final parcel = context.watch<ParcelProvider>();
      openParcelCount = parcel.openParcels.length;
      overdueParcelCount = parcel.overdueParcels(DateTime.now()).length;
    }

    final dailyDestinations = <_ShopDestination>[
      if (canViewInventory)
        _ShopDestination(
          icon: Icons.shopping_bag_outlined,
          title: 'Kundenbestellungen',
          subtitle: 'Sonderbestellungen von Kunden verwalten',
          badge:
              openCustomerOrderCount > 0
                  ? '$openCustomerOrderCount offen'
                  : null,
          badgeTone: AppStatusTone.info,
          onTap: () => context.push(AppRoutes.customerOrders),
        ),
      if (canViewParcels)
        _ShopDestination(
          icon: Icons.local_shipping_outlined,
          title: 'Paketshop',
          subtitle: 'Pakete sortieren, wiederfinden und ausgeben',
          badge:
              overdueParcelCount > 0
                  ? '$overdueParcelCount überfällig'
                  : (openParcelCount > 0 ? '$openParcelCount offen' : null),
          badgeTone:
              overdueParcelCount > 0
                  ? AppStatusTone.warning
                  : AppStatusTone.info,
          onTap: () => context.push(AppRoutes.paketshop),
        ),
    ];

    final reportDestinations = <_ShopDestination>[
      if (canViewInventory)
        _ShopDestination(
          icon: Icons.insights_outlined,
          title: 'Bestell-Auswertung',
          subtitle: 'Bestellhäufigkeit nach Woche und Monat auswerten',
          onTap: () => context.push(AppRoutes.orderAnalytics),
        ),
      if (isAdmin)
        _ShopDestination(
          icon: Icons.receipt_long_outlined,
          title: 'Kassenbericht',
          subtitle: 'Umsatz, Käufe und Gewinn nach Zeitraum prüfen',
          onTap: () => context.push(AppRoutes.kassenbericht),
        ),
    ];

    final managementDestinations = <_ShopDestination>[
      if (isAdmin)
        _ShopDestination(
          icon: Icons.badge_outlined,
          title: 'Personal',
          subtitle: 'Aufträge, Lohn-Richtwerte, Finanzen und Statistik',
          onTap: () => context.push(AppRoutes.personal),
        ),
      if (canManageFeedback)
        _ShopDestination(
          icon: Icons.feedback_outlined,
          title: 'Kundenfeedback',
          subtitle: 'Beschwerden, Vorschläge und Lob bearbeiten',
          onTap: () => context.push(AppRoutes.feedbackInbox),
        ),
      if (isAdmin && AppConfig.signageEnabled)
        _ShopDestination(
          icon: Icons.slideshow_outlined,
          title: 'Displays & Werbung',
          subtitle: 'Inhalte auf den Laden-Fernsehern verwalten',
          onTap: () => context.push(AppRoutes.signage),
        ),
      if (isAdmin)
        _ShopDestination(
          icon: Icons.history_outlined,
          title: 'Änderungsprotokoll',
          subtitle: 'Änderungen an Lohn, Kontakten und Preisen prüfen',
          onTap: () => context.push(AppRoutes.auditLog),
        ),
    ];

    final spacing = context.spacing;

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
                    'Tagesgeschäft, Auswertungen und Verwaltung – klar nach Aufgaben sortiert.',
                breadcrumbs: const [BreadcrumbItem(label: 'Laden')],
                onBack: canNavigateBack ? onNavigateBack : null,
              ),
              SizedBox(height: spacing.lg),
              if (canViewInventory)
                _ShopInventoryHero(
                  lowStockCount: lowStockCount,
                  openCustomerOrderCount: openCustomerOrderCount,
                  openParcelCount: canViewParcels ? openParcelCount : null,
                  overdueParcelCount:
                      canViewParcels ? overdueParcelCount : null,
                  onTap: () => context.push(AppRoutes.inventory),
                ),
              if (dailyDestinations.isNotEmpty) ...[
                SizedBox(height: spacing.xl),
                _ShopSection(
                  icon: Icons.storefront_outlined,
                  title: 'Tagesgeschäft',
                  subtitle: 'Aufträge und Services für den laufenden Betrieb',
                  destinations: dailyDestinations,
                ),
              ],
              if (reportDestinations.isNotEmpty) ...[
                SizedBox(height: spacing.xl),
                _ShopSection(
                  icon: Icons.query_stats_outlined,
                  title: 'Auswertungen & Kasse',
                  subtitle: 'Bestellungen, Umsatz und Entwicklung im Blick',
                  destinations: reportDestinations,
                ),
              ],
              if (managementDestinations.isNotEmpty) ...[
                SizedBox(height: spacing.xl),
                _ShopSection(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Verwaltung',
                  subtitle: 'Team, Kommunikation und Systeme organisieren',
                  destinations: managementDestinations,
                ),
              ],
              SizedBox(height: spacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShopDestination {
  const _ShopDestination({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.badgeTone = AppStatusTone.neutral,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;
  final AppStatusTone badgeTone;
}

class _ShopInventoryHero extends StatelessWidget {
  const _ShopInventoryHero({
    required this.lowStockCount,
    required this.openCustomerOrderCount,
    required this.openParcelCount,
    required this.overdueParcelCount,
    required this.onTap,
  });

  final int lowStockCount;
  final int openCustomerOrderCount;
  final int? openParcelCount;
  final int? overdueParcelCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;

    Widget content({required bool compact}) {
      final copy = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Warenwirtschaft',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: spacing.xs),
          Text(
            'Bestände, Lieferanten und Bestellungen zentral bearbeiten.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: spacing.md),
          Wrap(
            spacing: spacing.sm,
            runSpacing: spacing.sm,
            children: [
              AppStatusBadge(
                icon:
                    lowStockCount > 0
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline_rounded,
                label:
                    lowStockCount > 0
                        ? '$lowStockCount Artikel knapp'
                        : 'Bestand ohne Warnung',
                tone:
                    lowStockCount > 0
                        ? AppStatusTone.warning
                        : AppStatusTone.success,
                filled: true,
              ),
              AppStatusBadge(
                icon: Icons.shopping_bag_outlined,
                label: '$openCustomerOrderCount Bestellungen offen',
                tone:
                    openCustomerOrderCount > 0
                        ? AppStatusTone.info
                        : AppStatusTone.neutral,
                filled: true,
              ),
              if ((overdueParcelCount ?? 0) > 0)
                AppStatusBadge(
                  icon: Icons.schedule_rounded,
                  label: '$overdueParcelCount Pakete überfällig',
                  tone: AppStatusTone.warning,
                  filled: true,
                )
              else if ((openParcelCount ?? 0) > 0)
                AppStatusBadge(
                  icon: Icons.local_shipping_outlined,
                  label: '$openParcelCount Pakete offen',
                  tone: AppStatusTone.info,
                  filled: true,
                ),
            ],
          ),
        ],
      );

      final action = FilledButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.arrow_forward_rounded),
        label: const Text('Warenwirtschaft öffnen'),
      );

      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [copy, SizedBox(height: spacing.lg), action],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [Expanded(child: copy), SizedBox(width: spacing.xl), action],
      );
    }

    return AppHeroCard(
      tone: AppHeroTone.accent,
      padding: EdgeInsets.all(spacing.lg),
      child: LayoutBuilder(
        builder:
            (context, constraints) =>
                content(compact: constraints.maxWidth < 640),
      ),
    );
  }
}

class _ShopSection extends StatelessWidget {
  const _ShopSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.destinations,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<_ShopDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(spacing.sm),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(context.radii.md),
              ),
              child: Icon(
                icon,
                color: colorScheme.onSecondaryContainer,
                size: context.iconSizes.sm,
              ),
            ),
            SizedBox(width: spacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  SizedBox(height: spacing.xxs),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: spacing.md),
        _ShopTileGrid(destinations: destinations),
      ],
    );
  }
}

class _ShopTileGrid extends StatelessWidget {
  const _ShopTileGrid({required this.destinations});

  final List<_ShopDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final gap = context.spacing.md;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 840
                ? 3
                : constraints.maxWidth >= 600
                ? 2
                : 1;
        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final destination in destinations)
              SizedBox(
                width: tileWidth,
                child: _ShopModuleTile(destination: destination),
              ),
          ],
        );
      },
    );
  }
}

class _ShopModuleTile extends StatelessWidget {
  const _ShopModuleTile({required this.destination});

  final _ShopDestination destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    final hasBadge = destination.badge?.isNotEmpty ?? false;
    return Semantics(
      button: true,
      label: [
        destination.title,
        destination.subtitle,
        if (hasBadge) destination.badge!,
      ].join(', '),
      child: AppCard(
        onTap: destination.onTap,
        padding: EdgeInsets.all(spacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(spacing.s12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(context.radii.md),
              ),
              child: Icon(
                destination.icon,
                color: colorScheme.onPrimaryContainer,
                size: context.iconSizes.md,
              ),
            ),
            SizedBox(width: spacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destination.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: spacing.xs),
                  Text(
                    destination.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (hasBadge) ...[
                    SizedBox(height: spacing.s12),
                    AppStatusBadge(
                      label: destination.badge!,
                      tone: destination.badgeTone,
                      icon:
                          destination.badgeTone == AppStatusTone.warning
                              ? Icons.warning_amber_rounded
                              : Icons.info_outline_rounded,
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: spacing.xs),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
              size: context.iconSizes.sm,
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SectionHeader(
                      title: 'Profil',
                      subtitle:
                          'Persoenliche Daten, Arbeitszeit-Einstellungen und Auswertungen an einem Ort.',
                      breadcrumbs: const [BreadcrumbItem(label: 'Profil')],
                      onBack: canNavigateBack ? onNavigateBack : null,
                    ),
                  ),
                  // Hell/Dunkel schnell umschaltbar, ohne in die Einstellungen
                  // zu wechseln. Bewusst nur hier unter „Profil" versteckt —
                  // nicht mehr in der globalen App-Leiste/Navigations-Rail.
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: ThemeModeButton(),
                  ),
                ],
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
                        child: Text(_initialFor(currentUser?.displayName)),
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
                      icon: Icons.badge_outlined,
                      title: 'Personal',
                      subtitle:
                          'Auftraege, Lohn-Richtwerte, Finanzen und Statistik',
                      onTap: () => context.push(AppRoutes.personal),
                    ),
                  if (currentUser?.canViewInventory ?? false)
                    _QuickActionCard(
                      icon: Icons.inventory_2_outlined,
                      title: 'Warenwirtschaft',
                      subtitle:
                          'Bestand, Lieferanten und Bestellungen verwalten',
                      onTap: () => context.push(AppRoutes.inventory),
                    ),
                  if (currentUser?.canViewInventory ?? false)
                    _QuickActionCard(
                      icon: Icons.shopping_bag_outlined,
                      title: 'Kundenbestellungen',
                      subtitle:
                          'Sonderbestellungen von Kunden verwalten',
                      onTap: () => context.push(AppRoutes.customerOrders),
                    ),
                  _QuickActionCard(
                    icon: Icons.menu_book_outlined,
                    title: 'Wissen & Hilfe',
                    subtitle: 'Anleitungen zu jedem Bereich der App',
                    onTap: () => context.push(AppRoutes.knowledge),
                  ),
                  _QuickActionCard(
                    icon: Icons.settings_outlined,
                    title: 'Einstellungen',
                    subtitle: 'Profil, Theme und Standardwerte aendern',
                    onTap: () => context.push(AppRoutes.settings),
                  ),
                  if (AppConfig.passwordManagerEnabled &&
                      (currentUser?.isActive ?? false))
                    _QuickActionCard(
                      icon: Icons.vpn_key_outlined,
                      title: 'Passwörter',
                      subtitle: 'Zugangsdaten sicher speichern und wiederfinden',
                      onTap: () => context.push(AppRoutes.passwords),
                    ),
                  if (currentUser?.canViewReports ?? false)
                    _QuickActionCard(
                      icon: Icons.description_outlined,
                      title: 'Monatsbericht',
                      subtitle:
                          'Eigene Stunden oder Team-Bericht als PDF pruefen',
                      onTap: () => context.push(AppRoutes.monthReport),
                    ),
                  if (currentUser?.canViewReports ?? false)
                    _QuickActionCard(
                      icon: Icons.analytics_outlined,
                      title: 'Statistiken',
                      subtitle:
                          'Monats- und Jahresauswertungen direkt mobil einsehen',
                      onTap: () => context.push(AppRoutes.statistics),
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
          '${shift.employeeName} · ${dateFormat.format(shift.startTime)} - ${DateFormat('HH:mm', 'de_DE').format(shift.endTime)}'
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
    final timeFmt = DateFormat('HH:mm', 'de_DE');
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
                                  '${DateFormat('HH:mm', 'de_DE').format(shift.startTime)} - ${DateFormat('HH:mm', 'de_DE').format(shift.endTime)}'
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
                                    '${DateFormat('HH:mm', 'de_DE').format(entry.startTime)} - ${DateFormat('HH:mm', 'de_DE').format(entry.endTime)}'
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
    final timeFmt = DateFormat('HH:mm', 'de_DE');
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
                  PopupMenuItem(value: 'delete', child: Text('Löschen')),
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
        title: const Text('Eintrag löschen?'),
        content: const Text('Dieser Eintrag wird unwiderruflich geloescht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
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
            content: Text('Fehler beim Löschen: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}
