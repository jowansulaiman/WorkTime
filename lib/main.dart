import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/app_config.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/storage_mode_provider.dart';
import 'providers/team_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/work_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_logo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validateEnvironment();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}\n${details.stack}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unbehandelter Fehler: $error\n$stack');
    return true;
  };

  runApp(const AppBootstrap());
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
          debugPrint(
            'Firebase-Initialisierung fehlgeschlagen: $error\n$stackTrace',
          );
          Error.throwWithStackTrace(error, stackTrace);
        }
      } catch (error, stackTrace) {
        debugPrint(
          'Firebase-Initialisierung fehlgeschlagen: $error\n$stackTrace',
        );
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    // Firestore Offline-Persistence aktivieren: Daten werden lokal gecacht,
    // sodass Reads auch offline bedient werden und beim Reconnect automatisch
    // synchronisiert werden. Reduziert Cloud-Reads erheblich.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    await _authProvider.init();
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
            );
            return provider;
          },
        ),
        ChangeNotifierProxyProvider3<AuthProvider, TeamProvider,
            StorageModeProvider, WorkProvider>(
          create: (_) => WorkProvider(
            firestoreService: firestoreService,
          ),
          update: (_, auth, team, storage, provider) {
            provider ??= WorkProvider(firestoreService: firestoreService);
            _dispatchProviderUpdate(
              provider.updateSession(
                auth.profile,
                localStorageOnly: storage.isLocalOnly,
                hybridStorageEnabled: storage.isHybrid,
              ),
              'WorkProvider.updateSession',
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
      ],
      child: _ShiftCompletionWiring(
        child: Consumer<ThemeProvider>(
          builder: (context, themeProvider, _) => MaterialApp(
            title: 'timework',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
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
            home: const _AuthGate(),
          ),
        ),
      ),
    );
  }
}

void _dispatchProviderUpdate(Future<void> future, String label) {
  unawaited(
    future.catchError((Object error, StackTrace stackTrace) {
      debugPrint('$label failed: $error\n$stackTrace');
    }),
  );
}

/// Verbindet WorkProvider und ScheduleProvider: Wenn ein Arbeitszeiteintrag
/// fuer eine Schicht gespeichert wird, wird die Schicht automatisch als
/// erledigt markiert.
class _ShiftCompletionWiring extends StatefulWidget {
  const _ShiftCompletionWiring({required this.child});

  final Widget child;

  @override
  State<_ShiftCompletionWiring> createState() => _ShiftCompletionWiringState();
}

class _ShiftCompletionWiringState extends State<_ShiftCompletionWiring> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final work = context.read<WorkProvider>();
    final schedule = context.read<ScheduleProvider>();
    work.onShiftWorked ??= (sourceShiftId) {
      _dispatchProviderUpdate(
        schedule.completeShiftForEntry(sourceShiftId),
        'ScheduleProvider.completeShiftForEntry',
      );
    };
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
    final colorScheme = Theme.of(context).colorScheme;

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
              CircularProgressIndicator(
                color: colorScheme.primary,
              ),
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

    if (!auth.firebaseConfigured) {
      return const FirebaseSetupScreen();
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
      return const AuthScreen();
    }

    final profile = auth.profile;
    if (profile != null && !profile.isActive) {
      return const AccessBlockedScreen();
    }

    return const HomeScreen();
  }
}
