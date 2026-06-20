import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/accessibility.dart';
import 'core/analytics_service.dart';
import 'core/app_config.dart';
import 'core/app_logger.dart';
import 'core/error_reporter.dart';
import 'core/redesign_flags.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/feature_flag_provider.dart';
import 'providers/inventory_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/storage_mode_provider.dart';
import 'providers/team_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/work_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/auth_screen_v2.dart';
import 'screens/force_update_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_logo.dart';

Future<void> main() async {
  // Alles in einer einzigen bewachten Zone starten, damit auch Fehler aus
  // fire-and-forget-Futures (z. B. _dispatchProviderUpdate) erfasst werden.
  // ensureInitialized() und runApp() MÜSSEN in derselben Zone laufen.
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      AppConfig.validateEnvironment();

      // Saubere Web-URLs ohne #-Fragment (web-url-strategy-missing). Auf nicht-
      // Web-Plattformen ist usePathUrlStrategy ein No-op, wir gaten dennoch
      // explizit per kIsWeb.
      if (kIsWeb) {
        usePathUrlStrategy();
      }

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        ErrorReporter.report(
          details.exception,
          details.stack,
          context: 'FlutterError (${details.library ?? 'flutter'})',
        );
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        ErrorReporter.report(error, stack,
            context: 'PlatformDispatcher', fatal: true);
        return true;
      };

      // Im Release-Build statt des roten Default-ErrorWidget einen ruhigen,
      // deutschen Fehlerschirm zeigen; im Debug bleibt das informative Default.
      if (!kDebugMode) {
        ErrorWidget.builder = (details) => const _FriendlyErrorWidget();
      }

      runApp(const AppBootstrap());
    },
    (error, stack) {
      ErrorReporter.report(error, stack,
          context: 'Zone (unbehandelter async-Fehler)', fatal: true);
    },
  );
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late Future<void> _initialization = _initializeApp();
  late final FirestoreService _firestoreService = FirestoreService();
  late final AuthService _authService = AuthService();
  late final AuthProvider _authProvider = AuthProvider(
    authService: _authService,
    firestoreService: _firestoreService,
  );

  Future<void> _initializeApp() async {
    await initializeDateFormatting('de_DE', null);

    final canUseNativeAndroidFirebaseConfig =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    if (DefaultFirebaseOptions.isConfigured ||
        canUseNativeAndroidFirebaseConfig) {
      try {
        if (DefaultFirebaseOptions.isConfigured) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        } else {
          await Firebase.initializeApp();
        }
      } on FirebaseException catch (error, stackTrace) {
        if (error.code != 'duplicate-app') {
          AppLogger.error('Firebase-Initialisierung fehlgeschlagen',
              error: error, stackTrace: stackTrace);
          Error.throwWithStackTrace(error, stackTrace);
        }
      } catch (error, stackTrace) {
        AppLogger.error('Firebase-Initialisierung fehlgeschlagen',
            error: error, stackTrace: stackTrace);
        Error.throwWithStackTrace(error, stackTrace);
      }

      // Firestore Offline-Persistence aktivieren: Daten werden lokal gecacht,
      // sodass Reads auch offline bedient werden und beim Reconnect automatisch
      // synchronisiert werden. Reduziert Cloud-Reads erheblich.
      FirebaseFirestore.instance.settings = _buildFirestoreSettings();
    }

    await _authProvider.init();
  }

  Settings _buildFirestoreSettings() {
    if (kIsWeb) {
      return const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        webExperimentalAutoDetectLongPolling: true,
        webExperimentalLongPollingOptions: WebExperimentalLongPollingOptions(
          timeoutDuration: Duration(seconds: 30),
        ),
      );
    }

    return const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  void _retryInitialization() {
    setState(() {
      _initialization = _initializeApp();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _BootstrapShell(
            child: _StartupStatusCard(
              title: 'Arbeitsbereich wird geladen',
              message:
                  'Zeiterfassung, Schichtplanung und Auswertungen werden vorbereitet. Bitte einen Moment warten.',
              showLoader: true,
            ),
          );
        }

        if (snapshot.hasError) {
          return _BootstrapShell(
            child: _StartupStatusCard(
              title: 'Start fehlgeschlagen',
              message:
                  'Die Anwendung konnte nicht vollstaendig geladen werden. Bitte versuche es erneut.',
              actionLabel: 'Erneut versuchen',
              onActionPressed: _retryInitialization,
            ),
          );
        }

        return WorkTimeApp(
          firestoreService: _firestoreService,
          authProvider: _authProvider,
        );
      },
    );
  }
}

class WorkTimeApp extends StatelessWidget {
  const WorkTimeApp({
    super.key,
    required this.firestoreService,
    required this.authProvider,
  });

  final FirestoreService firestoreService;
  final AuthProvider authProvider;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => ThemeProvider()..init()),
        ChangeNotifierProvider(create: (_) => StorageModeProvider()..init()),
        ChangeNotifierProxyProvider2<AuthProvider, StorageModeProvider,
            FeatureFlagProvider>(
          create: (_) =>
              FeatureFlagProvider(firestoreService: firestoreService),
          update: (_, auth, storage, provider) {
            provider ??=
                FeatureFlagProvider(firestoreService: firestoreService);
            _dispatchProviderUpdate(
              provider.updateSession(
                auth.profile,
                localStorageOnly: storage.isLocalOnly,
                hybridStorageEnabled: storage.isHybrid,
              ),
              'FeatureFlagProvider.updateSession',
            );
            return provider;
          },
        ),
        ChangeNotifierProxyProvider2<AuthProvider, StorageModeProvider,
            TeamProvider>(
          create: (_) => TeamProvider(
            firestoreService: firestoreService,
          ),
          update: (_, auth, storage, provider) {
            provider ??= TeamProvider(firestoreService: firestoreService);
            _dispatchProviderUpdate(
              provider.updateSession(
                auth.profile,
                localStorageOnly: storage.isLocalOnly,
                hybridStorageEnabled: storage.isHybrid,
              ),
              'TeamProvider.updateSession',
              onError: provider.surfaceSessionError,
            );
            return provider;
          },
        ),
        ChangeNotifierProxyProvider3<AuthProvider, TeamProvider,
            StorageModeProvider, ScheduleProvider>(
          create: (_) => ScheduleProvider(
            firestoreService: firestoreService,
          ),
          update: (_, auth, team, storage, provider) {
            provider ??= ScheduleProvider(firestoreService: firestoreService);
            _dispatchProviderUpdate(
              provider.updateSession(
                auth.profile,
                localStorageOnly: storage.isLocalOnly,
                hybridStorageEnabled: storage.isHybrid,
              ),
              'ScheduleProvider.updateSession',
              onError: provider.surfaceSessionError,
            );
            provider.updateReferenceData(
              members: team.members,
              contracts: team.contracts,
              siteAssignments: team.siteAssignments,
              ruleSets: team.ruleSets,
              travelTimeRules: team.travelTimeRules,
            );
            return provider;
          },
        ),
        ChangeNotifierProxyProvider2<AuthProvider, StorageModeProvider,
            InventoryProvider>(
          create: (_) => InventoryProvider(
            firestoreService: firestoreService,
          ),
          update: (_, auth, storage, provider) {
            provider ??= InventoryProvider(firestoreService: firestoreService);
            _dispatchProviderUpdate(
              provider.updateSession(
                auth.profile,
                localStorageOnly: storage.isLocalOnly,
                hybridStorageEnabled: storage.isHybrid,
              ),
              'InventoryProvider.updateSession',
              onError: provider.surfaceSessionError,
            );
            return provider;
          },
        ),
        ChangeNotifierProxyProvider4<AuthProvider, TeamProvider,
            StorageModeProvider, ScheduleProvider, WorkProvider>(
          create: (_) => WorkProvider(
            firestoreService: firestoreService,
          ),
          update: (_, auth, team, storage, schedule, provider) {
            provider ??= WorkProvider(firestoreService: firestoreService);
            provider.updateScheduleProvider(schedule);
            _dispatchProviderUpdate(
              provider.updateSession(
                auth.profile,
                localStorageOnly: storage.isLocalOnly,
                hybridStorageEnabled: storage.isHybrid,
              ),
              'WorkProvider.updateSession',
              onError: provider.surfaceSessionError,
            );
            provider.updateReferenceData(
              members: team.members,
              sites: team.sites,
              contracts: team.contracts,
              siteAssignments: team.siteAssignments,
              ruleSets: team.ruleSets,
              travelTimeRules: team.travelTimeRules,
            );
            return provider;
          },
        ),
      ],
      child: Consumer2<ThemeProvider, FeatureFlagProvider>(
        builder: (context, themeProvider, featureFlags, _) => MaterialApp(
          title: 'timework',
          debugShowCheckedModeBanner: false,
          // Theme-Flip (redesign_v2): Dev-Override > org-Flag waehlt V1/V2-Optik.
          // Die Bootstrap-Shell bleibt auf V1 gepinnt (Anti-Flash) — kein
          // Umschalten vor Aufloesung der Remote-Config.
          theme: AppTheme.resolveLight(
            useV2: _resolveUseV2(featureFlags, themeProvider.redesignV2Override),
          ),
          darkTheme: AppTheme.resolveDark(
            useV2: _resolveUseV2(featureFlags, themeProvider.redesignV2Override),
          ),
          themeMode: themeProvider.themeMode,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('de', 'DE'),
            Locale('en', 'US'),
          ],
          locale: themeProvider.locale,
          navigatorObservers: [AnalyticsService.observer],
          builder: (context, child) {
            // Sehr große System-Textskalierung clampen, damit Komponenten mit
            // fixen Höhen nicht überlaufen (no-textscaler-reduce-motion).
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: clampTextScaler(mediaQuery.textScaler),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const _AuthGate(),
        ),
      ),
    );
  }
}

/// Loest die V2-Optik-Wahl fuer den Theme-Flip auf: der Dev-Override
/// (APP_REDESIGN_V2) gewinnt, sonst zaehlt das org-seitige `redesign_v2`-Flag.
bool _resolveUseV2(FeatureFlagProvider featureFlags, bool? runtimeOverride) =>
    RedesignFlags.resolve(
      serverFlag:
          featureFlags.isEnabled(RedesignFlags.flagKey, fallback: false),
      runtimeOverride: runtimeOverride,
    );

void _dispatchProviderUpdate(
  Future<void> future,
  String label, {
  void Function(Object error)? onError,
}) {
  unawaited(
    future.catchError((Object error, StackTrace stackTrace) {
      ErrorReporter.report(error, stackTrace, context: label);
      // Fehler zusaetzlich in der UI sichtbar machen, statt ihn still im Log zu
      // belassen (fire-and-forget-updatesession).
      onError?.call(error);
    }),
  );
}

/// Ruhiger Ersatz für das rote Default-[ErrorWidget] im Release-Build.
class _FriendlyErrorWidget extends StatelessWidget {
  const _FriendlyErrorWidget();

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: Color(0xFFF7F7F7),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Es ist ein unerwarteter Fehler aufgetreten.\n'
            'Bitte den Bereich erneut öffnen oder die App neu starten.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF444444)),
          ),
        ),
      ),
    );
  }
}

class _BootstrapShell extends StatelessWidget {
  const _BootstrapShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: _BootstrapFrame(child: child),
    );
  }
}

class _BootstrapFrame extends StatelessWidget {
  const _BootstrapFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupStatusCard extends StatelessWidget {
  const _StartupStatusCard({
    required this.title,
    required this.message,
    this.showLoader = false,
    this.actionLabel,
    this.onActionPressed,
  });

  final String title;
  final String message;
  final bool showLoader;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppLogo(height: 78),
            const SizedBox(height: 20),
            if (showLoader) ...[
              const CircularProgressIndicator.adaptive(),
              const SizedBox(height: 20),
            ],
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (actionLabel != null && onActionPressed != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onActionPressed,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // Flag-gegateter Chooser fuer die Auth-Flow-Screens (redesign_v2). Ein
    // Flag-Wechsel rebuildet die _AuthGate und waehlt V1/V2 neu.
    final useV2 = RedesignFlags.isOn(context);

    if (!auth.firebaseConfigured) {
      return useV2 ? const FirebaseSetupScreenV2() : const FirebaseSetupScreen();
    }

    if (!auth.initialized) {
      return const _BootstrapFrame(
        child: _StartupStatusCard(
          title: 'Arbeitsbereich wird geladen',
          message:
              'Zeiterfassung, Schichtplanung und Auswertungen werden vorbereitet. Bitte einen Moment warten.',
          showLoader: true,
        ),
      );
    }

    if (auth.isResolvingProfile) {
      return const _BootstrapFrame(
        child: _StartupStatusCard(
          title: 'Arbeitsbereich wird geladen',
          message:
              'Zeiterfassung, Schichtplanung und Auswertungen werden vorbereitet. Bitte einen Moment warten.',
          showLoader: true,
        ),
      );
    }

    if (!auth.isAuthenticated) {
      return useV2 ? const AuthScreenV2() : const AuthScreen();
    }

    final profile = auth.profile;
    if (profile != null && !profile.isActive) {
      return useV2 ? const AccessBlockedScreenV2() : const AccessBlockedScreen();
    }

    // Force-Update-Gate: nur echte Release-Builds (buildNumber > 0), die der
    // Server explizit unterhalb der Mindest-Build-Nummer einstuft, werden
    // blockiert (no-feature-flags-force-update, fail-open).
    final featureFlags = context.watch<FeatureFlagProvider>();
    if (featureFlags.requiresUpdate) {
      return ForceUpdateScreen(
        message: featureFlags.updateMessage,
        minimumBuildNumber: featureFlags.minimumBuildNumber,
        currentBuildNumber: featureFlags.currentBuildNumber,
      );
    }

    return const HomeScreen();
  }
}
