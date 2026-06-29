import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/providers/audit_provider.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/contact_provider.dart';
import 'package:worktime_app/providers/feature_flag_provider.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/providers/personal_provider.dart';
import 'package:worktime_app/providers/schedule_provider.dart';
import 'package:worktime_app/providers/storage_mode_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/providers/theme_provider.dart';
import 'package:worktime_app/providers/work_provider.dart';
import 'package:worktime_app/providers/zeitwirtschaft_provider.dart';
import 'package:worktime_app/routing/app_router.dart';
import 'package:worktime_app/services/auth_service.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/theme/app_theme.dart';

/// Auth-Provider-Fake für Router-Tests: liefert ein festes Profil und meldet die
/// Gate-Getter so, dass der `_gateRedirect` die App als „voll gebootet" ansieht.
/// (Der echte AuthProvider würde ohne `init()` `firebaseConfigured == false` und
/// `isAuthenticated == false` liefern und alles auf /einrichtung bzw. /anmelden
/// umleiten.) Profil `null` => unauthentifiziert (Redirect nach /anmelden).
class FakeAuthProvider extends AuthProvider {
  FakeAuthProvider({required super.firestoreService, AppUserProfile? profile})
      : _profile = profile,
        super(authService: AuthService());

  final AppUserProfile? _profile;

  @override
  AppUserProfile? get profile => _profile;

  @override
  bool get firebaseConfigured => true;

  @override
  bool get initialized => true;

  @override
  bool get isResolvingProfile => false;

  @override
  bool get isAuthenticated => _profile != null;
}

/// Feature-Flag-Fake: erzwingt optional das Force-Update-Gate. `redesignV2` wird
/// für die V1/V2-Tests weiterhin über das echte Firestore-Seeding gesteuert
/// (siehe [pumpApp] `flagOn`), daher hier nur das Update-Gate.
class FakeFeatureFlagProvider extends FeatureFlagProvider {
  FakeFeatureFlagProvider({
    required super.firestoreService,
    this.forceUpdate = false,
  });

  final bool forceUpdate;

  @override
  bool get requiresUpdate => forceUpdate;

  @override
  int get minimumBuildNumber => forceUpdate ? 999 : 0;

  @override
  int get currentBuildNumber => 1;

  @override
  String? get updateMessage =>
      forceUpdate ? 'Bitte aktualisiere die App.' : null;
}

/// Ergebnis eines [pumpApp]-Aufrufs: der lebende Router (für `go`/`push` in
/// Tests), der [ThemeProvider] (für Laufzeit-V2-Override) und ein `cleanup`, das
/// Tree + Provider + Router in sicherer Reihenfolge abbaut (sonst pending Timer
/// der WorkProvider / Notify an disposed Router).
typedef AppHarness = ({
  GoRouter router,
  ThemeProvider theme,
  Future<void> Function() cleanup,
});

/// Pumpt die echte App über `MaterialApp.router` + den echten [buildAppRouter].
Future<AppHarness> pumpApp(
  WidgetTester tester, {
  required AppUserProfile? profile,
  bool flagOn = false,
  bool forceUpdate = false,
  String initialLocation = '/',
  Size size = const Size(1400, 1600),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final firestore = FakeFirebaseFirestore();
  final firestoreService = FirestoreService(firestore: firestore);
  if (profile != null) {
    await firestore
        .collection('users')
        .doc(profile.uid)
        .set(profile.toFirestoreMap());
  }
  if (flagOn) {
    await firestore
        .collection('organizations')
        .doc('org-1')
        .collection('config')
        .doc('appFlags')
        .set({
      'featureFlags': {'redesign_v2': true},
    });
  }

  final auth = FakeAuthProvider(
    firestoreService: firestoreService,
    profile: profile,
  );
  final storage = StorageModeProvider();
  final theme = ThemeProvider();
  final flags = forceUpdate
      ? FakeFeatureFlagProvider(
          firestoreService: firestoreService, forceUpdate: true)
      : FeatureFlagProvider(firestoreService: firestoreService);
  final team = TeamProvider(firestoreService: firestoreService);
  final schedule = ScheduleProvider(firestoreService: firestoreService);
  final inventory = InventoryProvider(firestoreService: firestoreService);
  final contact = ContactProvider(firestoreService: firestoreService);
  final audit = AuditProvider(firestoreService: firestoreService);
  final personal = PersonalProvider(firestoreService: firestoreService);
  final work = WorkProvider(firestoreService: firestoreService);
  work.updateScheduleProvider(schedule);
  final zeitwirtschaft =
      ZeitwirtschaftProvider(firestoreService: firestoreService);

  if (profile != null) {
    await flags.updateSession(profile, localStorageOnly: false);
    await team.updateSession(profile);
    await schedule.updateSession(profile);
    await inventory.updateSession(profile);
    await contact.updateSession(profile);
    await audit.updateSession(profile);
    await personal.updateSession(profile);
    await work.updateSession(profile);
    await zeitwirtschaft.updateSession(profile);
  }

  final router = buildAppRouter(
    auth: auth,
    featureFlags: flags,
    theme: theme,
    initialLocation: initialLocation,
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<StorageModeProvider>.value(value: storage),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<FeatureFlagProvider>.value(value: flags),
        ChangeNotifierProvider<TeamProvider>.value(value: team),
        ChangeNotifierProvider<ScheduleProvider>.value(value: schedule),
        ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
        ChangeNotifierProvider<ContactProvider>.value(value: contact),
        ChangeNotifierProvider<AuditProvider>.value(value: audit),
        ChangeNotifierProvider<PersonalProvider>.value(value: personal),
        ChangeNotifierProvider<WorkProvider>.value(value: work),
        ChangeNotifierProvider<ZeitwirtschaftProvider>.value(
            value: zeitwirtschaft),
      ],
      child: MaterialApp.router(
        theme: AppTheme.resolveLight(useV2: flagOn),
        // Textskalierung klemmen wie die echte App (main.dart-Builder), den der
        // Test umgeht — sonst RenderFlex-Overflow in dichten Widgets.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(0.8)),
          child: child!,
        ),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));

  return (
    router: router,
    theme: theme,
    cleanup: () async {
      // Reihenfolge: Tree unmounten -> Router disposen -> Provider disposen,
      // damit Listenable.merge nicht an einen disposed Router notified und keine
      // pending Timer der WorkProvider übrig bleiben.
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      zeitwirtschaft.dispose();
      work.dispose();
      personal.dispose();
      audit.dispose();
      contact.dispose();
      inventory.dispose();
      schedule.dispose();
      team.dispose();
      flags.dispose();
      theme.dispose();
      storage.dispose();
      auth.dispose();
    },
  );
}
