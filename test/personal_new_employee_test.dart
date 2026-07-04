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
import 'package:worktime_app/providers/team_provider.dart';
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

Future<TeamProvider> _pump(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 2200);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final service = FirestoreService(firestore: FakeFirebaseFirestore());
  final personal =
      PersonalProvider(firestoreService: service, disableAuthentication: true);
  final inventory =
      InventoryProvider(firestoreService: service, disableAuthentication: true);
  final team =
      TeamProvider(firestoreService: service, disableAuthentication: true);
  addTearDown(personal.dispose);
  addTearDown(inventory.dispose);
  addTearDown(team.dispose);
  await personal.updateSession(_admin, localStorageOnly: true);
  await inventory.updateSession(_admin, localStorageOnly: true);
  await team.updateSession(_admin, localStorageOnly: true);
  personal.updateReferenceData(members: [_admin]);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PersonalProvider>.value(value: personal),
        ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
        ChangeNotifierProvider<TeamProvider>.value(value: team),
      ],
      child: MaterialApp(
        theme: AppTheme.resolveLight(useV2: true),
        home: const PersonalScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return team;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('de_DE'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  testWidgets('„Neuer Mitarbeiter" öffnet Einladungsdialog', (tester) async {
    await _pump(tester);
    expect(find.byIcon(Icons.person_add_alt_1), findsOneWidget);

    await tester.tap(find.byIcon(Icons.person_add_alt_1));
    await tester.pumpAndSettle();
    expect(find.text('Neuer Mitarbeiter'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Name *'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'E-Mail *'), findsOneWidget);
    expect(find.text('Einladen'), findsOneWidget);
  });

  testWidgets('Einladen erzeugt eine userInvite via TeamProvider',
      (tester) async {
    final team = await _pump(tester);

    await tester.tap(find.byIcon(Icons.person_add_alt_1));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Name *'), 'Neue Kraft');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'E-Mail *'), 'neu@example.com');
    await tester.tap(find.text('Einladen'));
    await tester.pumpAndSettle();

    expect(team.invites.any((i) => i.email == 'neu@example.com'), isTrue);
    expect(find.text('Neuer Mitarbeiter'), findsNothing); // Dialog geschlossen
  });
}
