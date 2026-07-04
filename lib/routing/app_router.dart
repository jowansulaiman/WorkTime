import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/accessibility.dart';
import '../core/analytics_service.dart';
import '../core/app_config.dart';
import '../core/quick_actions_service.dart';
import '../core/redesign_flags.dart';
import '../providers/auth_provider.dart';
import '../providers/feature_flag_provider.dart';
import '../providers/theme_provider.dart';
import '../screens/audit_log_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/auth_screen_v2.dart';
import '../screens/bestand_insights_screen.dart';
import '../screens/customer_feedback_screen.dart';
import '../screens/customer_order_screen.dart';
import '../screens/cashier_anomaly_screen.dart';
import '../screens/customer_wishes_screen.dart';
import '../screens/daily_closing_screen.dart';
import '../screens/finance_screen.dart';
import '../screens/force_update_screen.dart';
import '../screens/home_screen.dart';
import '../screens/inventory_screen.dart';
import '../screens/kassenbericht_screen.dart';
import '../screens/passwords_screen.dart';
import '../screens/kiosk/kiosk_screen.dart';
import '../screens/meine_akte_screen.dart';
import '../screens/month_report_screen.dart';
import '../screens/order_analytics_screen.dart';
import '../screens/personal_screen.dart';
import '../screens/scanner_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/sortiment_screen.dart';
import '../screens/staffing_profile_screen.dart';
import '../screens/store_health_screen.dart';
import '../screens/statistics_screen.dart';
import '../screens/team_management_screen.dart';
import '../screens/zeitwirtschaft/abwesenheiten_screen.dart';
import '../screens/zeitwirtschaft/abwesenheitskalender_screen.dart';
import '../screens/zeitwirtschaft/lohnlauf_screen.dart';
import '../screens/zeitwirtschaft/mitarbeiterabschluss_screen.dart';
import '../screens/zeitwirtschaft/monatsabschluss_screen.dart';
import '../screens/zeitwirtschaft/stempel_screen.dart';
import '../screens/zeitwirtschaft/stundenkonto_screen.dart';
import '../screens/zeitwirtschaft/zeiterfassung_screen.dart';
import '../services/push_messaging_service.dart';
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

      // Arbeitsmodus / Laden-Tablet (Kiosk): Vollbild über dem Root-Navigator
      // (ersetzt die Shell). Nur im Kiosk-Build erreichbar (Gate erzwingt es).
      GoRoute(
        path: AppRoutes.kiosk,
        parentNavigatorKey: rootNavigatorKey,
        // Dichtes Tablet-Board: lokal auf 1,5 klemmen (gestufte Dynamic-Type-
        // Leiter E1).
        builder: (context, state) =>
            const DenseContentTextScale(child: KioskScreen()),
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
          initialTabIndex: switch (s.uri.queryParameters['tab']) {
            'korb' => InventoryScreen.cartTabIndex,
            'kuehl' => InventoryScreen.fridgeTabIndex,
            _ => 0,
          },
        ),
      ),
      _sectionRoute(AppRoutes.customerOrders,
          (c, s) => const CustomerOrderScreen(parentLabel: 'Laden')),
      _sectionRoute(AppRoutes.personal,
          (c, s) => const PersonalScreen(parentLabel: 'Laden')),
      _sectionRoute(AppRoutes.meineAkte,
          (c, s) => const MeineAkteScreen(parentLabel: 'Profil')),
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
      _sectionRoute(AppRoutes.bestandInsights,
          (c, s) => const BestandInsightsScreen(parentLabel: 'Warenwirtschaft')),
      _sectionRoute(AppRoutes.sortiment,
          (c, s) => const SortimentScreen(parentLabel: 'Warenwirtschaft')),
      _sectionRoute(AppRoutes.staffingProfile,
          (c, s) => const StaffingProfileScreen(parentLabel: 'Schichtplan')),
      // Erreichbar aus Buchhaltung (Admin) UND dem Laden-Insights-Menü
      // (Teamleitung) — neutraler Breadcrumb, da teamlead keine Buchhaltung hat.
      _sectionRoute(AppRoutes.dailyClosing,
          (c, s) => const DailyClosingScreen(parentLabel: 'Kasse')),
      _sectionRoute(AppRoutes.kassenbericht,
          (c, s) => const KassenberichtScreen(parentLabel: 'Warenwirtschaft')),
      _sectionRoute(AppRoutes.passwords,
          (c, s) => const PasswordsScreen(parentLabel: 'Profil')),
      _sectionRoute(AppRoutes.storeHealth,
          (c, s) => const StoreHealthScreen(parentLabel: 'Warenwirtschaft')),
      _sectionRoute(AppRoutes.cashierAnomaly,
          (c, s) => const CashierAnomalyScreen(parentLabel: 'Personal')),

      // ---- Zeitwirtschaft-Bereich (Sub-Routen unter dem `/zeit`-Tab-Hub) ----
      _sectionRoute(AppRoutes.zeitErfassung, (c, s) => const ZeiterfassungScreen()),
      _sectionRoute(AppRoutes.zeitStempeln, (c, s) => const StempelScreen()),
      _sectionRoute(
          AppRoutes.zeitStundenkonto, (c, s) => const StundenkontoScreen()),
      _sectionRoute(
          AppRoutes.zeitAbwesenheiten, (c, s) => const AbwesenheitenScreen()),
      _sectionRoute(AppRoutes.zeitAbwesenheitenKalender,
          (c, s) => const AbwesenheitskalenderScreen()),
      _sectionRoute(AppRoutes.zeitMonatsabschluss,
          (c, s) => const MonatsabschlussScreen()),
      _sectionRoute(AppRoutes.zeitMitarbeiterabschluss,
          (c, s) => const MitarbeiterabschlussScreen()),
      _sectionRoute(AppRoutes.zeitLohnlauf, (c, s) => const LohnlaufScreen()),
    ],
  );
}

/// Tabellen-/Chart-/Raster-lastige Hauptbereiche, deren Text lokal auf 1,5
/// geklemmt wird (gestufte Dynamic-Type-Leiter E1), während Lese-/Formular-
/// Screens die volle Skalierung bis 2,0 behalten. Wird beim Bereichs-Rollout
/// je Screen geprüft/reduziert, wenn er responsiv umgebaut ist.
const Set<String> _denseSectionPaths = <String>{
  AppRoutes.inventory,
  AppRoutes.personal,
  AppRoutes.finance,
  AppRoutes.team,
  AppRoutes.monthReport,
  AppRoutes.statistics,
  AppRoutes.orderAnalytics,
  AppRoutes.bestandInsights,
  AppRoutes.sortiment,
  AppRoutes.staffingProfile,
  AppRoutes.dailyClosing,
  AppRoutes.kassenbericht,
  AppRoutes.storeHealth,
  AppRoutes.cashierAnomaly,
  AppRoutes.auditLog,
  AppRoutes.zeitErfassung,
  AppRoutes.zeitStundenkonto,
  AppRoutes.zeitMonatsabschluss,
  AppRoutes.zeitMitarbeiterabschluss,
  AppRoutes.zeitLohnlauf,
  AppRoutes.zeitAbwesenheiten,
  AppRoutes.zeitAbwesenheitenKalender,
};

GoRoute _sectionRoute(
  String path,
  Widget Function(BuildContext context, GoRouterState state) builder,
) =>
    GoRoute(
      path: path,
      parentNavigatorKey: rootNavigatorKey,
      builder: _denseSectionPaths.contains(path)
          ? (context, state) =>
              DenseContentTextScale(child: builder(context, state))
          : builder,
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

  // Arbeitsmodus / Laden-Tablet: Im Kiosk-Build (dediziertes Gerät) ist das
  // Vollbild-Board die EINZIGE erreichbare Oberfläche — auch Unterrouten
  // `/arbeitsmodus/...` bleiben erlaubt, alles andere wird dorthin gelenkt.
  // Steht NACH den Auth-Gates (Gerät muss angemeldet & aktiv sein), aber VOR der
  // normalen Permission-/Deep-Link-Logik. Increment 0: rein flag-getrieben;
  // später zusätzlich an `profile.role == kiosk` gebunden.
  if (AppConfig.kioskModeEnabled) {
    final inKiosk =
        loc == AppRoutes.kiosk || loc.startsWith('${AppRoutes.kiosk}/');
    return inKiosk ? null : AppRoutes.kiosk;
  }

  // Schnellaktion aus dem Long-Press-Menü (App-Icon) zustellen — erst HIER, da
  // Auth/Profil jetzt sicher aufgelöst & aktiv sind. Deckt den Cold-Start ab
  // (App per Schnellaktion gestartet → Ziel wartet bis nach dem Login). Beim
  // Warmstart wurde meist schon direkt navigiert; `take` ist idempotent und
  // verhindert eine Redirect-Schleife (zweiter Lauf liefert null).
  // `profile != null` ist hier durch das isAuthenticated-Gate oben bereits
  // garantiert (isAuthenticated ⟹ profile != null); explizit als Invariante,
  // damit nie eine pending-Route bei noch nicht geladenem Profil verworfen wird.
  final pendingQuickAction = profile == null
      ? null
      : QuickActionsService.instance.takePendingRoute();
  if (pendingQuickAction != null &&
      pendingQuickAction != loc &&
      RoutePermissions.isLocationAllowed(pendingQuickAction, profile)) {
    return pendingQuickAction;
  }

  // Getippte Push-Benachrichtigung (Cold-Start/Hintergrund) gate-konform
  // zustellen — gleiche Pending-Route-Mechanik wie Schnellaktionen. Die
  // Permission-Prüfung läuft auf dem Pfad ohne Query (z. B.
  // '/warenwirtschaft?tab=korb').
  final pendingPush = profile == null
      ? null
      : PushMessagingService.instance.takePendingRoute();
  if (pendingPush != null &&
      pendingPush != loc &&
      RoutePermissions.isLocationAllowed(pendingPush.split('?').first, profile)) {
    return pendingPush;
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
