import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/employee_profile.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/personal_provider.dart';
import 'package:worktime_app/screens/personal/tabs/employee_stammdaten_tab.dart';
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

Future<PersonalProvider> _pump(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1100, 2600);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final service = FirestoreService(firestore: FakeFirebaseFirestore());
  final personal =
      PersonalProvider(firestoreService: service, disableAuthentication: true);
  addTearDown(personal.dispose);
  await personal.updateSession(_admin, localStorageOnly: true);

  await tester.pumpWidget(
    ChangeNotifierProvider<PersonalProvider>.value(
      value: personal,
      child: MaterialApp(
        theme: AppTheme.resolveLight(useV2: true),
        home: const Scaffold(body: EmployeeStammdatenTab(userId: 'admin-1')),
      ),
    ),
  );
  await tester.pump();
  return personal;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    await initializeDateFormatting('de_DE');
  });

  testWidgets('rendert die vier AllTec-Karten', (tester) async {
    await _pump(tester);
    expect(find.text('Stammdaten'), findsOneWidget);
    expect(find.text('Status & Vereinbarungen'), findsOneWidget);
    expect(find.text('Klassifizierungen'), findsOneWidget);
    expect(find.text('Arbeitszeit'), findsOneWidget);
  });

  testWidgets('zeigt gespeicherte Parität-Felder an', (tester) async {
    final personal = await _pump(tester);
    await personal.saveEmployeeProfile(const EmployeeProfile(
      orgId: '',
      userId: 'admin-1',
      abteilung: 'Verkauf',
      kostenstelle: 'KST-100',
      kuerzel: 'LMU',
      erwerbsart: Erwerbsart.midijob,
    ));
    await tester.pump();

    expect(find.text('Verkauf'), findsOneWidget);
    expect(find.text('KST-100'), findsOneWidget);
    expect(find.text('LMU'), findsOneWidget);
    expect(find.text('Midijob'), findsOneWidget);
  });
}
