import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/payroll_record.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/personal_provider.dart';
import 'package:worktime_app/screens/zeitwirtschaft/lohnlauf_screen.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/theme/app_theme.dart';

/// M6: LohnlaufScreen zeigt die Entwürfe des (Vor-)Monats + Sammel-Freigabe.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('de_DE'));

  const admin = AppUserProfile(
    uid: 'admin-1',
    orgId: 'org-1',
    email: 'admin@example.com',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Chef'),
  );
  const employee = AppUserProfile(
    uid: 'emp-1',
    orgId: 'org-1',
    email: 'peter@example.com',
    role: UserRole.employee,
    isActive: true,
    settings: UserSettings(name: 'Peter Müller'),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  // Der Lohnlauf zeigt standardmäßig den Vormonat.
  final prev = DateTime(DateTime.now().year, DateTime.now().month - 1);

  Future<PersonalProvider> seededProvider() async {
    final personal = PersonalProvider(
      firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      disableAuthentication: true,
    );
    addTearDown(personal.dispose);
    await personal.updateSession(admin, localStorageOnly: true);
    personal.updateReferenceData(members: const [admin, employee]);
    await personal.savePayrollRecord(PayrollRecord(
      orgId: 'org-1',
      userId: 'emp-1',
      periodYear: prev.year,
      periodMonth: prev.month,
      grossCents: 200000,
      netCents: 150000,
      employerTotalCents: 40000,
      incomeTaxCents: 30000,
    ));
    return personal;
  }

  Future<void> pump(WidgetTester tester, PersonalProvider personal) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 2200);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<PersonalProvider>.value(
        value: personal,
        child: MaterialApp(
          theme: AppTheme.resolveLight(useV2: true),
          home: const LohnlaufScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('zeigt Entwurf + Summen, Freigabe-Button für Entwürfe',
      (tester) async {
    final personal = await seededProvider();
    await pump(tester, personal);

    expect(find.text('Peter Müller'), findsOneWidget);
    expect(find.textContaining('Alle Entwürfe freigeben'), findsOneWidget);
    expect(find.text('Brutto gesamt'), findsOneWidget);
  });

  testWidgets('„Alle Entwürfe freigeben" setzt den Datensatz auf freigegeben',
      (tester) async {
    final personal = await seededProvider();
    await pump(tester, personal);

    await tester.tap(find.textContaining('Alle Entwürfe freigeben'));
    await tester.pumpAndSettle();
    // Bestätigungsdialog → „Freigeben".
    await tester.tap(find.widgetWithText(FilledButton, 'Freigeben'));
    await tester.pumpAndSettle();

    final record =
        personal.payrollForUserPeriod('emp-1', prev.year, prev.month);
    expect(record, isNotNull);
    expect(record!.status, PayrollStatus.freigegeben);
  });
}
