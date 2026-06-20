import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/feature_flag_provider.dart';
import 'package:worktime_app/providers/schedule_provider.dart';
import 'package:worktime_app/providers/storage_mode_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/providers/theme_provider.dart';
import 'package:worktime_app/providers/work_provider.dart';
import 'package:worktime_app/screens/home_screen.dart';
import 'package:worktime_app/services/auth_service.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/theme/app_theme.dart';
import 'package:worktime_app/ui/app_hero_card.dart';

/// Integrationstest fuer Schritt 4 (Home-Dashboards V2): pumpt die echte
/// HomeScreen-Shell und prueft, dass bei aktivem `redesign_v2`-Flag die
/// V2-Dashboards gewaehlt werden — erkannt an [AppHeroCard] (V2-only). Ohne Flag
/// bleibt es bei V1 (keine AppHeroCard).
class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider({required super.firestoreService, AppUserProfile? profile})
      : _profile = profile,
        super(authService: AuthService());

  final AppUserProfile? _profile;

  @override
  AppUserProfile? get profile => _profile;
}

const _admin = AppUserProfile(
  uid: 'admin-1',
  orgId: 'org-1',
  email: 'admin@example.com',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Admin'),
);
const _employee = AppUserProfile(
  uid: 'emp-1',
  orgId: 'org-1',
  email: 'peter@example.com',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Peter'),
);

Future<({Future<void> Function() cleanup, ThemeProvider theme})> _pumpHome(
  WidgetTester tester, {
  required AppUserProfile profile,
  required bool flagOn,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 1600);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final firestore = FakeFirebaseFirestore();
  final firestoreService = FirestoreService(firestore: firestore);
  await firestore
      .collection('users')
      .doc(profile.uid)
      .set(profile.toFirestoreMap());
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

  final auth = _FakeAuthProvider(
      firestoreService: firestoreService, profile: profile);
  final team = TeamProvider(firestoreService: firestoreService);
  final schedule = ScheduleProvider(firestoreService: firestoreService);
  final work = WorkProvider(firestoreService: firestoreService);
  final storage = StorageModeProvider();
  final flags = FeatureFlagProvider(firestoreService: firestoreService);
  final theme = ThemeProvider();

  await team.updateSession(profile);
  await schedule.updateSession(profile);
  await work.updateSession(profile);
  await flags.updateSession(profile, localStorageOnly: false);


  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<StorageModeProvider>.value(value: storage),
        ChangeNotifierProvider<TeamProvider>.value(value: team),
        ChangeNotifierProvider<ScheduleProvider>.value(value: schedule),
        ChangeNotifierProvider<WorkProvider>.value(value: work),
        ChangeNotifierProvider<FeatureFlagProvider>.value(value: flags),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ],
      child: MaterialApp(
        theme: AppTheme.resolveLight(useV2: flagOn),
        // Textskalierung klemmen wie die echte App (main.dart-Builder), den der
        // direkte Pump umgeht — sonst RenderFlex-Overflow in dichten Widgets.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(0.8)),
          child: child!,
        ),
        home: const HomeScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));

  // WorkProvider haelt periodische Clock-Timer. Im Test-Body (vor der
  // pending-Timer-Pruefung) aufraeumen: Tree unmounten, dann Provider disposen.
  return (
    theme: theme,
    cleanup: () async {
      await tester.pumpWidget(const SizedBox());
      work.dispose();
      schedule.dispose();
      team.dispose();
      flags.dispose();
      storage.dispose();
      auth.dispose();
      theme.dispose();
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => initializeDateFormatting('de_DE'));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  testWidgets('Employee + Flag an -> V2-Dashboard (AppHeroCard)', (tester) async {
    final h = await _pumpHome(tester, profile: _employee, flagOn: true);
    expect(find.byType(AppHeroCard), findsOneWidget);
    expect(find.text('Krank melden'), findsOneWidget);
    await h.cleanup();
  });

  testWidgets('Admin + Flag an -> V2-Dashboard (AppHeroCard + Plan oeffnen)',
      (tester) async {
    final h = await _pumpHome(tester, profile: _admin, flagOn: true);
    expect(find.byType(AppHeroCard), findsOneWidget);
    expect(find.text('Plan oeffnen'), findsOneWidget);
    await h.cleanup();
  });

  testWidgets('Employee + Flag aus -> V1 (keine AppHeroCard)', (tester) async {
    final h = await _pumpHome(tester, profile: _employee, flagOn: false);
    expect(find.byType(AppHeroCard), findsNothing);
    await h.cleanup();
  });

  testWidgets('Laufzeit-Override schaltet das Home-Layout live V1 -> V2',
      (tester) async {
    final h = await _pumpHome(tester, profile: _employee, flagOn: false);
    // Start ohne Flag/Override -> V1-Layout (keine AppHeroCard).
    expect(find.byType(AppHeroCard), findsNothing);

    // Schalter umlegen (wie der Einstellungs-Toggle) -> Home muss live auf das
    // V2-Layout wechseln, nicht nur umfaerben.
    await h.theme.setRedesignV2Override(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AppHeroCard), findsOneWidget);

    await h.cleanup();
  });
}
