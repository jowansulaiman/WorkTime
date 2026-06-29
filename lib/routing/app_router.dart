import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/analytics_service.dart';
import '../core/redesign_flags.dart';
import '../providers/auth_provider.dart';
import '../providers/feature_flag_provider.dart';
import '../providers/theme_provider.dart';
import '../screens/audit_log_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/auth_screen_v2.dart';
import '../screens/customer_feedback_screen.dart';
import '../screens/customer_order_screen.dart';
import '../screens/customer_wishes_screen.dart';
import '../screens/finance_screen.dart';
import '../screens/force_update_screen.dart';
import '../screens/home_screen.dart';
import '../screens/inventory_screen.dart';
import '../screens/month_report_screen.dart';
import '../screens/order_analytics_screen.dart';
import '../screens/personal_screen.dart';
import '../screens/scanner_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/statistics_screen.dart';
import '../screens/team_management_screen.dart';
import '../screens/zeitwirtschaft/lohnlauf_screen.dart';
import '../screens/zeitwirtschaft/mitarbeiterabschluss_screen.dart';
import '../screens/zeitwirtschaft/monatsabschluss_screen.dart';
import '../screens/zeitwirtschaft/stempel_screen.dart';
import '../screens/zeitwirtschaft/stundenkonto_screen.dart';
import '../screens/zeitwirtschaft/zeit_section_placeholder.dart';
import '../screens/zeitwirtschaft/zeiterfassung_screen.dart';
import '../widgets/bootstrap_frame.dart';
import 'route_permissions.dart';
import 'shell_tab.dart';

/// Root-Navigator der App. Section-Routen pushen über diesen Key, decken also
/// die Bottom-Nav/Rail der Shell ab (wie früher `Navigator.push` über den Hub).
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

const Set<String> _gatePaths = {
  AppRoutes.start,
  AppRoutes.login,
  AppRoutes.setup,
  AppRoutes.blocked,
  AppRoutes.update,
};

/// Baut den App-Router. Wird in `main.dart` EINMAL erzeugt (memoisiert), damit
/// die Navigations-Historie über Theme-/Flag-Rebuilds erhalten bleibt.
///
/// [auth]/[featureFlags]/[theme] sind ChangeNotifier und bilden zusammen das
/// `refreshListenable`: jeder Auth-Übergang, Force-Update-Wechsel oder
/// V1/V2-Flag-Wechsel triggert eine Neubewertung von [_gateRedirect].
GoRouter buildAppRouter({
  required AuthProvider auth,
  required FeatureFlagProvider featureFlags,
  required ThemeProvider theme,
  String initialLocation = '/',
}) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    refreshListenable: Listenable.merge([auth, featureFlags, theme]),
    observers: [AnalyticsService.observer],
    redirect: _gateRedirect,
    routes: <RouteBase>[
      // ---- Gate-Routen ----
      GoRoute(
        path: AppRoutes.start,
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.setup,
        builder: (context, state) => RedesignFlags.isOnRead(context)
            ? const FirebaseSetupScreenV2()
            : const FirebaseSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => RedesignFlags.isOnRead(context)
            ? const AuthScreenV2()
            : const AuthScreen(),
      ),
      GoRoute(
        path: AppRoutes.blocked,
        builder: (context, state) => RedesignFlags.isOnRead(context)
            ? const AccessBlockedScreenV2()
            : const AccessBlockedScreen(),
      ),
      GoRoute(
        path: AppRoutes.update,
        builder: (context, state) {
          final flags = context.read<FeatureFlagProvider>();
          return ForceUpdateScreen(
            message: flags.updateMessage,
            minimumBuildNumber: flags.minimumBuildNumber,
            currentBuildNumber: flags.currentBuildNumber,
          );
        },
      ),

      // ---- Shell: 7 statische Branches (lazy IndexedStack, State je Branch) ----
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeScreen(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          for (final tab in ShellTab.values)
            StatefulShellBranch(
              navigatorKey: GlobalKey<NavigatorState>(debugLabel: tab.name),
              routes: <RouteBase>[
                GoRoute(
                  path: shellTabPaths[tab]!,
                  builder: (context, state) => buildHomeTab(context, tab),
                ),
              ],
            ),
        ],
      ),

      // ---- Hauptbereich-Routen (single canonical route je Screen) ----
      _sectionRoute(
        AppRoutes.inventory,
        // `?tab=korb` springt direkt in den Bestellkorb (Warenkorb-Knopf in der
        // V2-App-Bar). Der Query-Param berührt das Permission-Gating nicht — der
        // Redirect prüft state.matchedLocation (ohne Query).
        (c, s) => InventoryScreen(
          parentLabel: 'Laden',
          initialTabIndex: s.uri.queryParameters['tab'] == 'korb'
              ? InventoryScreen.cartTabIndex
              : 0,
        ),
      ),
      _sectionRoute(AppRoutes.customerOrders,
          (c, s) => const CustomerOrderScreen(parentLabel: 'Laden')),
      _sectionRoute(AppRoutes.personal,
          (c, s) => const PersonalScreen(parentLabel: 'Laden')),
      _sectionRoute(AppRoutes.finance,
          (c, s) => const FinanceScreen(parentLabel: 'Laden')),
      _sectionRoute(AppRoutes.feedbackInbox,
          (c, s) => const CustomerFeedbackScreen(parentLabel: 'Laden')),
      _sectionRoute(AppRoutes.auditLog,
          (c, s) => const AuditLogScreen(parentLabel: 'Laden')),
      _sectionRoute(AppRoutes.team,
          (c, s) => const TeamManagementScreen(parentLabel: 'Profil')),
      _sectionRoute(AppRoutes.settings,
          (c, s) => const SettingsScreen(parentLabel: 'Profil')),
      _sectionRoute(AppRoutes.monthReport,
          (c, s) => const MonthReportScreen(parentLabel: 'Profil')),
      _sectionRoute(AppRoutes.statistics,
          (c, s) => const StatisticsScreen(parentLabel: 'Profil')),
      _sectionRoute(AppRoutes.customerWishes,
          (c, s) => const CustomerWishesScreen()),
      _sectionRoute(AppRoutes.scanner,
          (c, s) => const ScannerScreen(parentLabel: 'Warenwirtschaft')),
      _sectionRoute(AppRoutes.orderAnalytics,
          (c, s) => const OrderAnalyticsScreen(parentLabel: 'Laden')),

      // ---- Zeitwirtschaft-Bereich (Sub-Routen unter dem `/zeit`-Tab-Hub) ----
      _sectionRoute(AppRoutes.zeitErfassung, (c, s) => const ZeiterfassungScreen()),
      _sectionRoute(AppRoutes.zeitStempeln, (c, s) => const StempelScreen()),
      _sectionRoute(
          AppRoutes.zeitStundenkonto, (c, s) => const StundenkontoScreen()),
      _sectionRoute(
          AppRoutes.zeitAbwesenheiten,
          (c, s) => const ZeitSectionPlaceholder(
              title: 'Abwesenheiten', meilenstein: 'M4')),
      _sectionRoute(
          AppRoutes.zeitAbwesenheitenKalender,
          (c, s) => const ZeitSectionPlaceholder(
              title: 'Abwesenheitskalender', meilenstein: 'M4')),
      _sectionRoute(AppRoutes.zeitMonatsabschluss,
          (c, s) => const MonatsabschlussScreen()),
      _sectionRoute(AppRoutes.zeitMitarbeiterabschluss,
          (c, s) => const MitarbeiterabschlussScreen()),
      _sectionRoute(AppRoutes.zeitLohnlauf, (c, s) => const LohnlaufScreen()),
    ],
  );
}

GoRoute _sectionRoute(
  String path,
  Widget Function(BuildContext context, GoRouterState state) builder,
) =>
    GoRoute(
      path: path,
      parentNavigatorKey: rootNavigatorKey,
      builder: builder,
    );

/// Reproduziert die frühere `_AuthGate`-Entscheidung als go_router-Redirect.
/// Schleifensicher: jeder Zweig gibt `null` zurück, wenn die Ziel-Location schon
/// stimmt; „Gate verlassen → /" läuft erst NACH allen Blockern.
String? _gateRedirect(BuildContext context, GoRouterState state) {
  final auth = context.read<AuthProvider>();
  final flags = context.read<FeatureFlagProvider>();
  final loc = state.matchedLocation;

  if (!auth.firebaseConfigured) {
    return loc == AppRoutes.setup ? null : AppRoutes.setup;
  }
  if (!auth.initialized || auth.isResolvingProfile) {
    return loc == AppRoutes.start ? null : AppRoutes.start;
  }
  if (!auth.isAuthenticated) {
    return loc == AppRoutes.login ? null : AppRoutes.login;
  }
  final profile = auth.profile;
  if (profile != null && !profile.isActive) {
    return loc == AppRoutes.blocked ? null : AppRoutes.blocked;
  }
  if (flags.requiresUpdate) {
    return loc == AppRoutes.update ? null : AppRoutes.update;
  }

  // Voll aufgelöst & erlaubt: auf einer Gate-Route sitzend -> raus auf Home.
  if (_gatePaths.contains(loc)) {
    return '/';
  }

  // Permission-Gating für Deep-Links (URL-Ebene). '/' und '/anfragen' sind
  // immer erlaubt -> der Fallback '/' kann keine Schleife auslösen. Matrix:
  // zentral in RoutePermissions (geteilt mit dem Home-Screen, H-H2).
  if (!RoutePermissions.isLocationAllowed(loc, profile)) {
    return '/';
  }
  return null;
}

/// Lade-Splash, gezeigt während Auth/Profil aufgelöst werden (Gate-Zustand
/// `/start`). Optik identisch zum Bootstrap-Loader.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const BootstrapFrame(
      child: StartupStatusCard(
        title: 'Arbeitsbereich wird geladen',
        message:
            'Zeiterfassung, Schichtplanung und Auswertungen werden vorbereitet. Bitte einen Moment warten.',
        showLoader: true,
      ),
    );
  }
}
