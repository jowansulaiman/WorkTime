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
import 'package:worktime_app/providers/inventory_provider.dart';
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
import 'package:worktime_app/widgets/app_nav_menu.dart';

/// Shell-Integrationstest fuer das V2-Slide-in-Menue: in V2 verschwindet der
/// Profil-Tab aus der Bottom-Nav (4 Kern-Tabs), der ☰-Avatar oeffnet das
/// [AppNavMenu], auf Desktop oeffnet der Rail-Profil-Header den endDrawer. In V1
/// bleibt alles wie bisher (Profil als 5. Tab, kein Drawer).
class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider({required super.firestoreService, AppUserProfile? profile})
      : _profile = profile,
        super(authService: AuthService());

  final AppUserProfile? _profile;

  @override
  AppUserProfile? get profile => _profile;
}

const _employee = AppUserProfile(
  uid: 'emp-1',
  orgId: 'org-1',
  email: 'peter@example.com',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Peter'),
);

Future<({Future<void> Function() cleanup})> _pumpHome(
  WidgetTester tester, {
  required bool flagOn,
  required Size size,
  AppUserProfile profile = _employee,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
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

  final auth =
      _FakeAuthProvider(firestoreService: firestoreService, profile: profile);
  final team = TeamProvider(firestoreService: firestoreService);
  final schedule = ScheduleProvider(firestoreService: firestoreService);
  final work = WorkProvider(firestoreService: firestoreService);
  final inventory = InventoryProvider(firestoreService: firestoreService);
  final storage = StorageModeProvider();
  final flags = FeatureFlagProvider(firestoreService: firestoreService);
  final theme = ThemeProvider();

  await team.updateSession(profile);
  await schedule.updateSession(profile);
  await work.updateSession(profile);
  await inventory.updateSession(profile);
  await flags.updateSession(profile, localStorageOnly: false);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<StorageModeProvider>.value(value: storage),
        ChangeNotifierProvider<TeamProvider>.value(value: team),
        ChangeNotifierProvider<ScheduleProvider>.value(value: schedule),
        ChangeNotifierProvider<WorkProvider>.value(value: work),
        ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
        ChangeNotifierProvider<FeatureFlagProvider>.value(value: flags),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ],
      child: MaterialApp(
        theme: AppTheme.resolveLight(useV2: flagOn),
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

  return (
    cleanup: () async {
      await tester.pumpWidget(const SizedBox());
      work.dispose();
      inventory.dispose();
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

  testWidgets('V2 mobil: kein Profil-Tab, ☰ oeffnet das Menue',
      (tester) async {
    // Breite < 600 => Bottom-Nav; bewusst roomy, um den (orthogonalen, schmal-
    // breiten) Dashboard-Überlauf nicht mitzutesten. Höhe lässt die Drawer-
    // ListView alle Einträge bauen.
    final h = await _pumpHome(tester, flagOn: true, size: const Size(580, 1200));

    // Profil ist nicht mehr in der Bottom-Nav; das Menue ist noch geschlossen.
    expect(find.text('Profil'), findsNothing);
    expect(find.byType(AppNavMenu), findsNothing);

    // ☰-Avatar oeffnet das Slide-in-Menue.
    expect(find.byTooltip('Menü'), findsOneWidget);
    await tester.tap(find.byTooltip('Menü'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AppNavMenu), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);

    await h.cleanup();
  });

  testWidgets('V2 Desktop: Rail-Profil-Header oeffnet endDrawer',
      (tester) async {
    final h =
        await _pumpHome(tester, flagOn: true, size: const Size(1400, 1600));

    expect(find.byType(AppNavMenu), findsNothing);

    // Der Account-Knopf unten in der V2-Rail oeffnet das Slide-in-Menue.
    await tester.tap(find.byTooltip('Menü öffnen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AppNavMenu), findsOneWidget);

    await h.cleanup();
  });

  testWidgets('V1 bleibt unveraendert: Profil-Tab, kein Drawer/Menue',
      (tester) async {
    final h = await _pumpHome(tester, flagOn: false, size: const Size(400, 900));

    expect(find.text('Profil'), findsWidgets); // Bottom-Nav-Tab
    expect(find.byType(AppNavMenu), findsNothing);
    expect(find.byTooltip('Menü'), findsNothing);

    await h.cleanup();
  });
}
