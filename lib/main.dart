import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/accessibility.dart';
import 'core/app_config.dart';
import 'core/app_logger.dart';
import 'core/error_reporter.dart';
import 'core/quick_actions_service.dart';
import 'core/redesign_flags.dart';
import 'firebase_options.dart';
import 'providers/audit_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/connectivity_status_provider.dart';
import 'providers/contact_provider.dart';
import 'providers/feature_flag_provider.dart';
import 'providers/finance_provider.dart';
import 'providers/inventory_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/password_provider.dart';
import 'providers/personal_provider.dart';
import 'providers/sales_insights_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/storage_mode_provider.dart';
import 'providers/store_task_provider.dart';
import 'providers/team_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/work_provider.dart';
import 'providers/zeitwirtschaft_provider.dart';
import 'routing/app_router.dart';
import 'screens/public/public_feedback_app.dart';
import 'screens/public/public_legal_app.dart';
import 'screens/public/public_legal_screen.dart';
import 'screens/public/public_wish_app.dart';
import 'services/auth_service.dart';
import 'services/document_storage.dart';
import 'services/firestore_service.dart';
import 'services/push_messaging_service.dart';
import 'theme/app_theme.dart';
import 'widgets/bootstrap_frame.dart';

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
  // Öffentliche Modi (Web-Routen /wunsch bzw. /feedback): die App läuft dann als
  // isolierte, login-freie Hülle OHNE Provider-Kette/_AuthGate. Einmal beim
  // Bootstrap ausgewertet.
  final bool _publicWishMode = isPublicWishRoute();
  final bool _publicFeedbackMode = isPublicFeedbackRoute();
  // Rechtliche Pflichtseiten (reine Statik, kein Firebase): /impressum,
  // /datenschutz. Wie die anderen öffentlichen Modi login-frei und ohne
  // Provider-Kette.
  final bool _publicImpressumMode = isPublicImpressumRoute();
  final bool _publicDatenschutzMode = isPublicDatenschutzRoute();
  bool get _publicMode =>
      _publicWishMode ||
      _publicFeedbackMode ||
      _publicImpressumMode ||
      _publicDatenschutzMode;
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

      // App Check aktivieren, BEVOR der erste Firestore-Zugriff passiert —
      // schützt v.a. den öffentlichen Schreibpfad (/wunsch) vor Bot-/Abuse.
      // No-op ohne reCAPTCHA-Key (Dev/Test). Aktiv in beiden Modi
      // (öffentlich + intern). Enforcement zusätzlich in der Firebase-Console.
      if (AppConfig.appCheckEnabled) {
        try {
          await FirebaseAppCheck.instance.activate(
            webProvider:
                ReCaptchaV3Provider(AppConfig.appCheckRecaptchaKey),
            androidProvider: AndroidProvider.playIntegrity,
            appleProvider: AppleProvider.appAttest,
          );
        } catch (error, stackTrace) {
          // App Check darf den Start nicht verhindern (fail-open im Client;
          // der eigentliche Schutz ist das Console-Enforcement).
          ErrorReporter.report(error, stackTrace,
              context: 'FirebaseAppCheck.activate');
        }
      }

      // Firestore Offline-Persistence aktivieren: Daten werden lokal gecacht,
      // sodass Reads auch offline bedient werden und beim Reconnect automatisch
      // synchronisiert werden. Reduziert Cloud-Reads erheblich.
      FirebaseFirestore.instance.settings = _buildFirestoreSettings();

      // Push-Benachrichtigungen (FCM): nur mit aktivem Flag und außerhalb der
      // öffentlichen Hüllen. No-op auf nicht unterstützten Plattformen; die
      // eigentliche Token-Registrierung passiert erst nach Login über den
      // NotificationProvider. Fail-open (Push darf den Start nie blockieren —
      // analog App Check; sonst meldet runZonedGuarded einen fatalen Zonenfehler).
      if (AppConfig.pushEnabled && !_publicMode) {
        try {
          await PushMessagingService.instance.initialize();
        } catch (error, stackTrace) {
          ErrorReporter.report(error, stackTrace,
              context: 'PushMessagingService.initialize');
        }
      }
    }

    // Im öffentlichen Wunsch-Modus KEIN authProvider.init(): keine
    // Profil-Auflösung, kein Mitarbeiter-Login. Anonyme Auth übernimmt die
    // öffentliche Seite selbst (lazy beim Absenden).
    if (!_publicMode) {
      await _authProvider.init();
    }
  }

  Settings _buildFirestoreSettings() {
    // PA-4.4e (Kiosk-Datensparsamkeit, Plan arbeitsmodus-laden-tablet §4):
    // Auf dem GETEILTEN Laden-Tablet keine Offline-Persistenz — gelesene
    // Org-Daten sollen nicht dauerhaft auf der Platte des Geraets liegen.
    // Das Board degradiert offline sichtbar (Kacheln melden Verbindung)
    // statt still aus einem alten Plattencache zu lesen.
    if (AppConfig.kioskModeEnabled) {
      return const Settings(persistenceEnabled: false);
    }
    if (kIsWeb) {
      // ZV-1.3 (Web-Persistenz-Entscheid): bewusst **Single-Tab**-Persistenz.
      // Der cloud_firestore-Flutter-Plugin exponiert KEINEN Multi-Tab-Manager
      // (das ist JS-SDK-spezifisch). Ein zweiter Tab desselben Origins kann die
      // Persistenz nicht erwerben — der Plugin fängt das ab und läuft dort
      // online weiter (graceful degradation, kein Absturz). Für die zwei Läden
      // ausreichend; Multi-Tab-Offline wäre nur mit JS-Interop nachrüstbar.
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
            child: StartupStatusCard(
              title: 'Arbeitsbereich wird geladen',
              message:
                  'Zeiterfassung, Schichtplanung und Auswertungen werden vorbereitet. Bitte einen Moment warten.',
              showLoader: true,
            ),
          );
        }

        if (snapshot.hasError) {
          return _BootstrapShell(
            child: StartupStatusCard(
              title: 'Start fehlgeschlagen',
              message:
                  'Die Anwendung konnte nicht vollstaendig geladen werden. Bitte versuche es erneut.',
              actionLabel: 'Erneut versuchen',
              onActionPressed: _retryInitialization,
            ),
          );
        }

        if (_publicImpressumMode) {
          return const PublicLegalApp(page: PublicLegalPage.impressum);
        }

        if (_publicDatenschutzMode) {
          return const PublicLegalApp(page: PublicLegalPage.datenschutz);
        }

        if (_publicFeedbackMode) {
          return PublicFeedbackApp(firestoreService: _firestoreService);
        }

        if (_publicWishMode) {
          return PublicWishApp(firestoreService: _firestoreService);
        }

        return WorkTimeApp(
          firestoreService: _firestoreService,
          authProvider: _authProvider,
        );
      },
    );
  }
}

class WorkTimeApp extends StatefulWidget {
  const WorkTimeApp({
    super.key,
    required this.firestoreService,
    required this.authProvider,
  });

  final FirestoreService firestoreService;
  final AuthProvider authProvider;

  @override
  State<WorkTimeApp> createState() => _WorkTimeAppState();
}

class _WorkTimeAppState extends State<WorkTimeApp> {
  // Einmalig erzeugter Router (memoisiert via ??=): die Navigations-Historie
  // überlebt die Theme-/Flag-Rebuilds des Consumer2. Erzeugung erst im ersten
  // Consumer2-Build, weil FeatureFlag-/ThemeProvider von MultiProvider lazy
  // (create:) entstehen und vorher nicht als Instanz vorliegen.
  GoRouter? _router;

  // Storage-Seam für Personalakte-Dokumente (PA-3). Nur konstruieren, wenn
  // Firebase initialisiert ist (sonst wirft FirebaseStorage.instance) — im
  // Demo-/APP_DISABLE_AUTH-Modus bleibt er null und Upload/Download sind aus.
  DocumentStorage? _documentStorage;

  DocumentStorage? _resolveDocumentStorage() {
    final firebaseReady = DefaultFirebaseOptions.isConfigured ||
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
    if (!firebaseReady) return null;
    return _documentStorage ??= FirebaseDocumentStorage();
  }

  @override
  void initState() {
    super.initState();
    // Schnellaktionen-Menü (Long-Press auf das App-Icon) an den go_router
    // koppeln. Navigation läuft über den Root-Navigator-Context; ist der noch
    // nicht montiert (Cold-Start), greift die pending-route-Zustellung im
    // Gate-Redirect. Nur Mobile, sonst No-op.
    QuickActionsService.instance.navigate = (route) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) ctx.go(route);
    };
    // Push-Tap → Deep-Link (gleiche gate-konforme Zustellung wie Schnellaktionen:
    // Warmstart navigiert direkt, Cold-Start/Hintergrund über die Pending-Route
    // im Gate-Redirect, sobald Auth/Profil aufgelöst sind).
    PushMessagingService.instance.navigate = (route) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) ctx.go(route);
    };
    // fire-and-forget; Fehler beim Schnellaktionen-Setup dürfen den Start NICHT
    // fatal machen (sonst meldet runZonedGuarded sie als fatalen Zonenfehler).
    unawaited(
      QuickActionsService.instance.init().catchError(
        (Object error, StackTrace stack) => ErrorReporter.report(
          error,
          stack,
          context: 'QuickActionsService.init',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = widget.firestoreService;
    final authProvider = widget.authProvider;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => ThemeProvider()..init()),
        // Konnektivitaets-/Offline-Status (Anf. 13). Von Auth/Storage
        // unabhaengig -> frueh registriert, damit Shell + Bereiche ihn lesen.
        // ZV-1.1: dreiwertiges Enum (online/offline/backendUnreachable) +
        // Debounce + Resume-Recheck sind eingebaut; eine Reachability-Probe kann
        // hier via `reachabilityProbe:` injiziert werden (Default null =
        // Interface-Status, keine Regression). Eine Produktiv-Probe braucht
        // einen HTTP-Client gegen den eigenen Endpunkt — bewusst nicht per
        // Default verdrahtet (keine neue Dependency, kein Falsch-Offline-Risiko).
        ChangeNotifierProvider(create: (_) => ConnectivityStatusProvider()),
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
        // Audit-Senke FRÜH registrieren (vor allen Daten-Providern), damit jeder
        // nachfolgende Provider sie via setAuditSink beziehen kann. Reihenfolge in
        // der Kette ist tragend: ein ProxyProvider darf nur auf zuvor registrierte
        // Provider zugreifen. Erfasst zentral jede Änderung aller Mitarbeiter.
        ChangeNotifierProxyProvider2<AuthProvider, StorageModeProvider,
            AuditProvider>(
          create: (_) => AuditProvider(
            firestoreService: firestoreService,
          ),
          update: (_, auth, storage, provider) {
            provider ??= AuditProvider(firestoreService: firestoreService);
            _dispatchProviderUpdate(
              provider.updateSession(
                auth.profile,
                localStorageOnly: storage.isLocalOnly,
                hybridStorageEnabled: storage.isHybrid,
              ),
              'AuditProvider.updateSession',
            );
            return provider;
          },
        ),
        ChangeNotifierProxyProvider3<AuthProvider, StorageModeProvider,
            AuditProvider, TeamProvider>(
          create: (_) => TeamProvider(
            firestoreService: firestoreService,
          ),
          update: (_, auth, storage, audit, provider) {
            provider ??= TeamProvider(firestoreService: firestoreService);
            provider.setAuditSink(audit.log);
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
        ChangeNotifierProxyProvider4<AuthProvider, TeamProvider,
            StorageModeProvider, AuditProvider, ScheduleProvider>(
          create: (_) => ScheduleProvider(
            firestoreService: firestoreService,
          ),
          update: (_, auth, team, storage, audit, provider) {
            provider ??= ScheduleProvider(firestoreService: firestoreService);
            provider.setAuditSink(audit.log);
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
              sites: team.sites,
              shiftPreferences: team.shiftPreferences,
            );
            return provider;
          },
        ),
        ChangeNotifierProxyProvider3<AuthProvider, StorageModeProvider,
            AuditProvider, InventoryProvider>(
          create: (_) => InventoryProvider(
            firestoreService: firestoreService,
          ),
          update: (_, auth, storage, audit, provider) {
            provider ??= InventoryProvider(firestoreService: firestoreService);
            provider.setAuditSink(audit.log);
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
        // Auswertungs-Read-State (P1.1–P1.3): delegiert an die lebende
        // InventoryProvider-Instanz (zustandslose Rechen-Methoden), hält nur das
        // Ergebnis — daher NACH Inventory in der Kette, kein eigenes Cloud-Repo.
        ChangeNotifierProxyProvider2<AuthProvider, InventoryProvider,
            SalesInsightsProvider>(
          create: (_) => SalesInsightsProvider(),
          update: (_, auth, inventory, provider) {
            provider ??= SalesInsightsProvider();
            provider.bind(inventory, auth.profile);
            return provider;
          },
        ),
        ChangeNotifierProxyProvider3<AuthProvider, StorageModeProvider,
            AuditProvider, ContactProvider>(
          create: (_) => ContactProvider(
            firestoreService: firestoreService,
          ),
          update: (_, auth, storage, audit, provider) {
            provider ??= ContactProvider(firestoreService: firestoreService);
            provider.setAuditSink(audit.log);
            _dispatchProviderUpdate(
              provider.updateSession(
                auth.profile,
                localStorageOnly: storage.isLocalOnly,
                hybridStorageEnabled: storage.isHybrid,
              ),
              'ContactProvider.updateSession',
              onError: provider.surfaceSessionError,
            );
            return provider;
          },
        ),
        // Passwortmanager (§5.1): rein server-verschlüsselt (Cloud KMS +
        // Callables), im Offline-/Demo-/Local-Modus deaktiviert. Auth/Storage/
        // Audit wie ContactProvider.
        ChangeNotifierProxyProvider3<AuthProvider, StorageModeProvider,
            AuditProvider, PasswordProvider>(
          create: (_) => PasswordProvider(
            firestoreService: firestoreService,
          ),
          update: (_, auth, storage, audit, provider) {
            provider ??= PasswordProvider(firestoreService: firestoreService);
            provider.setAuditSink(audit.log);
            _dispatchProviderUpdate(
              provider.updateSession(
                auth.profile,
                localStorageOnly: storage.isLocalOnly,
                hybridStorageEnabled: storage.isHybrid,
              ),
              'PasswordProvider.updateSession',
              onError: provider.surfaceSessionError,
            );
            return provider;
          },
        ),
        // Laden-To-Dos (Arbeitsmodus/Kiosk): Broadcast-Aufgaben je Laden. Leiter
        // legt an; jeder Mitarbeiter darf am Kiosk abhaken. Auth/Storage/Audit
        // wie ContactProvider.
        ChangeNotifierProxyProvider3<AuthProvider, StorageModeProvider,
            AuditProvider, StoreTaskProvider>(
          create: (_) => StoreTaskProvider(
            firestoreService: firestoreService,
          ),
          update: (_, auth, storage, audit, provider) {
            provider ??= StoreTaskProvider(firestoreService: firestoreService);
            provider.setAuditSink(audit.log);
            _dispatchProviderUpdate(
              provider.updateSession(
                auth.profile,
                localStorageOnly: storage.isLocalOnly,
                hybridStorageEnabled: storage.isHybrid,
              ),
              'StoreTaskProvider.updateSession',
            );
            return provider;
          },
        ),
        ChangeNotifierProxyProvider4<AuthProvider, TeamProvider,
            StorageModeProvider, AuditProvider, PersonalProvider>(
          create: (_) => PersonalProvider(
            firestoreService: firestoreService,
          ),
          update: (context, auth, team, storage, audit, provider) {
            provider ??= PersonalProvider(firestoreService: firestoreService);
            provider.setAuditSink(audit.log);
            // Personal→Plan-Kopplung (E5): Sollzeit-Profile + Austrittsdaten
            // der Stammakte in den lebenden (zuvor in der Kette gebauten)
            // ScheduleProvider spiegeln — Setter ohne notifyListeners
            // (Vorbild: WorkProvider.updateScheduleProvider-Verdrahtung).
            provider.setPlanningDataSink(
                context.read<ScheduleProvider>().updatePersonalReferenceData);
            final documentStorage = _resolveDocumentStorage();
            if (documentStorage != null) {
              provider.setDocumentStorage(documentStorage);
            }
            _dispatchProviderUpdate(
              provider.updateSession(
                auth.profile,
                localStorageOnly: storage.isLocalOnly,
                hybridStorageEnabled: storage.isHybrid,
              ),
              'PersonalProvider.updateSession',
              onError: provider.surfaceSessionError,
            );
            provider.updateReferenceData(
              members: team.members,
              contracts: team.contracts,
              sites: team.sites,
              siteAssignments: team.siteAssignments,
            );
            return provider;
          },
        ),
        // Zeitwirtschaft (M3): persistente Stempel-Sessions (ClockEntry). Nach
        // Personal eingehängt; additiv zum WorkProvider-Clock.
        ChangeNotifierProxyProvider3<AuthProvider, StorageModeProvider,
            AuditProvider, ZeitwirtschaftProvider>(
          create: (_) =>
              ZeitwirtschaftProvider(firestoreService: firestoreService),
          update: (context, auth, storage, audit, provider) {
            provider ??=
                ZeitwirtschaftProvider(firestoreService: firestoreService);
            provider.setAuditSink(audit.log);
            // Monatsabschluss-Entwurfslohn (M5): der lebende PersonalProvider
            // (zuvor in der Kette gebaut) nimmt den Draft-PayrollRecord auf.
            provider.setPayrollDraftPoster(
                context.read<PersonalProvider>().savePayrollRecord);
            // Abrechnungssperre (PA-5.2): Reopen eines Monatsabschlusses prüft
            // den Lohn-Status des Monats gegen den lebenden PersonalProvider.
            provider.setPayrollStatusLookup((userId, jahr, monat) => context
                .read<PersonalProvider>()
                .payrollForUserPeriod(userId, jahr, monat)
                ?.status);
            _dispatchProviderUpdate(
              provider.updateSession(
                auth.profile,
                localStorageOnly: storage.isLocalOnly,
                hybridStorageEnabled: storage.isHybrid,
              ),
              'ZeitwirtschaftProvider.updateSession',
              onError: provider.surfaceSessionError,
            );
            return provider;
          },
        ),
        ChangeNotifierProxyProvider3<AuthProvider, StorageModeProvider,
            AuditProvider, FinanceProvider>(
          create: (_) => FinanceProvider(firestoreService: firestoreService),
          update: (context, auth, storage, audit, provider) {
            provider ??= FinanceProvider(firestoreService: firestoreService);
            provider.setAuditSink(audit.log);
            // Personalkosten-Auto-Buchung (H-A1): die lebende Finance-Instanz
            // als Buchungs-Sink in den (zuvor in der Kette gebauten)
            // PersonalProvider injizieren. Finance hängt NICHT als Proxy an
            // Personal — daher per context.read statt Kettenumsortierung.
            context
                .read<PersonalProvider>()
                .setPayrollJournalPoster(provider.postPersonnelCostJournal);
            // Umsatz/Wareneinsatz-Auto-Buchung (H-A2): dieselbe Finance-Instanz
            // als Buchungs-Sink in den (zuvor gebauten) InventoryProvider.
            final inventory = context.read<InventoryProvider>();
            inventory
                .setRevenueJournalPoster(provider.postCustomerOrderRevenue);
            inventory.setGoodsCostJournalPoster(provider.postPurchaseOrderCost);
            _dispatchProviderUpdate(
              provider.updateSession(
                auth.profile,
                localStorageOnly: storage.isLocalOnly,
                hybridStorageEnabled: storage.isHybrid,
              ),
              'FinanceProvider.updateSession',
              onError: provider.surfaceSessionError,
            );
            return provider;
          },
        ),
        ChangeNotifierProxyProvider5<AuthProvider, TeamProvider,
            StorageModeProvider, ScheduleProvider, AuditProvider, WorkProvider>(
          create: (_) => WorkProvider(
            firestoreService: firestoreService,
          ),
          update: (context, auth, team, storage, schedule, audit, provider) {
            provider ??= WorkProvider(firestoreService: firestoreService);
            provider.updateScheduleProvider(schedule);
            provider.setAuditSink(audit.log);
            // Stempel-Ausgang (ZeitwirtschaftProvider, zuvor in der Kette gebaut)
            // erzeugt seinen WorkEntry über den lebenden WorkProvider (H-A1-Muster).
            context
                .read<ZeitwirtschaftProvider>()
                .setWorkEntryPoster(provider.addEntry);
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
        // Push-Token-Lebenszyklus (M1): hängt nur von Auth + Storage ab → ans
        // Kettenende. Registriert beim Login den FCM-Token, meldet ihn beim
        // Logout ab; In-App-Inbox folgt in M2/M3. Service ist plattform-/flag-
        // gegated → im Demo-/local-Modus No-op.
        ChangeNotifierProxyProvider2<AuthProvider, StorageModeProvider,
            NotificationProvider>(
          create: (_) => NotificationProvider(),
          update: (_, auth, storage, provider) {
            provider ??= NotificationProvider();
            _dispatchProviderUpdate(
              provider.updateSession(
                auth.profile,
                localStorageOnly: storage.isLocalOnly,
                hybridStorageEnabled: storage.isHybrid,
              ),
              'NotificationProvider.updateSession',
            );
            return provider;
          },
        ),
      ],
      child: Consumer2<ThemeProvider, FeatureFlagProvider>(
        builder: (context, themeProvider, featureFlags, _) {
          // Router einmalig erzeugen; refreshListenable (Auth/Flags/Theme)
          // übernimmt danach Auth-Redirects & V1/V2-Flips.
          final router = _router ??= buildAppRouter(
            auth: authProvider,
            featureFlags: featureFlags,
            theme: themeProvider,
          );
          return MaterialApp.router(
            title: 'timework',
            debugShowCheckedModeBanner: false,
            // Theme-Flip (redesign_v2): Dev-Override > org-Flag waehlt V1/V2-Optik.
            // Die Bootstrap-Shell bleibt auf V1 gepinnt (Anti-Flash) — kein
            // Umschalten vor Aufloesung der Remote-Config.
            theme: AppTheme.resolveLight(
              useV2:
                  _resolveUseV2(featureFlags, themeProvider.redesignV2Override),
            ),
            darkTheme: AppTheme.resolveDark(
              useV2:
                  _resolveUseV2(featureFlags, themeProvider.redesignV2Override),
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
            // Analytics-Observer liegt jetzt am GoRouter (observers:),
            // navigatorObservers wird von MaterialApp.router ignoriert.
            routerConfig: router,
          );
        },
      ),
    );
  }
}

/// Loest die V2-Optik-Wahl fuer den Theme-Flip auf: der Dev-Override
/// (APP_REDESIGN_V2) gewinnt, sonst zaehlt das org-seitige `redesign_v2`-Flag.
bool _resolveUseV2(FeatureFlagProvider featureFlags, bool? runtimeOverride) =>
    RedesignFlags.resolve(
      serverFlag: featureFlags.isEnabled(
        RedesignFlags.flagKey,
        fallback: RedesignFlags.defaultEnabled,
      ),
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
      home: BootstrapFrame(child: child),
    );
  }
}

// Die frühere _AuthGate-Logik lebt jetzt im go_router-Redirect (_gateRedirect
// in lib/routing/app_router.dart) plus den Gate-Routen (/start, /anmelden,
// /einrichtung, /gesperrt, /aktualisierung).
