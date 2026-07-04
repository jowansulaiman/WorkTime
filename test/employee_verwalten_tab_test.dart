import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/personal_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/screens/personal/tabs/employee_verwalten_tab.dart';
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

Future<void> _pump(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 2200);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final service = FirestoreService(firestore: FakeFirebaseFirestore());
  final personal =
      PersonalProvider(firestoreService: service, disableAuthentication: true);
  final team =
      TeamProvider(firestoreService: service, disableAuthentication: true);
  addTearDown(personal.dispose);
  addTearDown(team.dispose);
  await personal.updateSession(_admin, localStorageOnly: true);
  await team.updateSession(_admin, localStorageOnly: true);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PersonalProvider>.value(value: personal),
        ChangeNotifierProvider<TeamProvider>.value(value: team),
      ],
      child: MaterialApp(
        theme: AppTheme.resolveLight(useV2: true),
        home: const Scaffold(body: EmployeeVerwaltenTab(userId: 'admin-1')),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    await initializeDateFormatting('de_DE');
  });

  testWidgets('rendert Status/Gefahrenzone/Meta + Deaktivieren-Button',
      (tester) async {
    await _pump(tester);
    expect(find.text('Status & Zugang'), findsOneWidget);
    expect(find.text('Gefahrenzone'), findsOneWidget);
    expect(find.text('Technische Infos'), findsOneWidget);
    // „Löschen" = Deaktivieren-Alias.
    expect(find.text('Mitarbeiter deaktivieren'), findsOneWidget);
    // Meta zeigt die uid.
    expect(find.text('admin-1'), findsOneWidget);
  });
}
