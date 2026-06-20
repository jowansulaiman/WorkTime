import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/providers/personal_provider.dart';
import 'package:worktime_app/screens/personal_screen.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/theme/app_theme.dart';

const _admin = AppUserProfile(
  uid: 'admin-1',
  orgId: 'org-1',
  email: 'admin@example.com',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Sandra'),
);

const _employee = AppUserProfile(
  uid: 'emp-1',
  orgId: 'org-1',
  email: 'peter@example.com',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Peter'),
);

Future<void> _pump(WidgetTester tester, AppUserProfile user) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 2200);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final firestore = FakeFirebaseFirestore();
  final service = FirestoreService(firestore: firestore);
  final personal =
      PersonalProvider(firestoreService: service, disableAuthentication: true);
  final inventory =
      InventoryProvider(firestoreService: service, disableAuthentication: true);
  addTearDown(personal.dispose);
  addTearDown(inventory.dispose);

  await personal.updateSession(user, localStorageOnly: true);
  await inventory.updateSession(user, localStorageOnly: true);
  personal.updateReferenceData(members: [user]);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PersonalProvider>.value(value: personal),
        ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
      ],
      child: MaterialApp(
        theme: AppTheme.resolveLight(useV2: true),
        home: const PersonalScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('de_DE'));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  testWidgets('Admin sieht alle Tabs', (tester) async {
    await _pump(tester, _admin);

    expect(find.text('Übersicht'), findsOneWidget);
    expect(find.text('Aufträge'), findsOneWidget);
    expect(find.text('Lohn'), findsOneWidget);
    expect(find.text('Finanzen'), findsOneWidget);
    expect(find.text('Statistik'), findsOneWidget);
    expect(find.text('Kein Zugriff'), findsNothing);
  });

  testWidgets('Lohn-Tab zeigt Richtwert-Hinweis', (tester) async {
    await _pump(tester, _admin);

    await tester.tap(find.text('Lohn'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Richtwert'), findsWidgets);
  });

  testWidgets('Nicht-Admin: Kein Zugriff', (tester) async {
    await _pump(tester, _employee);
    expect(find.text('Kein Zugriff'), findsOneWidget);
  });
}
