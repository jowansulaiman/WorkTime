import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/contact_provider.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/screens/customer_order_screen.dart';
import 'package:worktime_app/services/auth_service.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/theme/app_theme.dart';

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider({required super.firestoreService, AppUserProfile? profile})
      : _profile = profile,
        super(authService: AuthService());

  final AppUserProfile? _profile;

  @override
  AppUserProfile? get profile => _profile;
}

const _admin = AppUserProfile(
  uid: 'owner-1',
  orgId: 'org-1',
  email: 'owner@laden.test',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Inhaber'),
);

const _blocked = AppUserProfile(
  uid: 'x-1',
  orgId: 'org-1',
  email: 'x@laden.test',
  role: UserRole.employee,
  isActive: false,
  settings: UserSettings(name: 'Gesperrt'),
);

Future<void> _pump(WidgetTester tester, AppUserProfile profile) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1600);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final firestore = FakeFirebaseFirestore();
  final service = FirestoreService(firestore: firestore);
  final auth = _FakeAuthProvider(firestoreService: service, profile: profile);
  final team = TeamProvider(firestoreService: service);
  final inventory =
      InventoryProvider(firestoreService: service, disableAuthentication: true);
  final contacts =
      ContactProvider(firestoreService: service, disableAuthentication: true);
  await team.updateSession(profile);
  await inventory.updateSession(profile);
  await contacts.updateSession(profile);
  addTearDown(() {
    inventory.dispose();
    contacts.dispose();
    team.dispose();
    auth.dispose();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<TeamProvider>.value(value: team),
        ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
        ChangeNotifierProvider<ContactProvider>.value(value: contacts),
      ],
      child: MaterialApp(
        theme: AppTheme.resolveLight(useV2: true),
        home: const CustomerOrderScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('de_DE'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  testWidgets('ohne Berechtigung -> Hinweis statt Inhalt', (tester) async {
    await _pump(tester, _blocked);
    expect(find.textContaining('Keine Berechtigung'), findsOneWidget);
  });

  testWidgets('mit Berechtigung -> Bestellung-FAB sichtbar', (tester) async {
    await _pump(tester, _admin);
    expect(find.text('Bestellung'), findsOneWidget); // FAB-Label
    expect(find.textContaining('Keine Berechtigung'), findsNothing);
  });
}
