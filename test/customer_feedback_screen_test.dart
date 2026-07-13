import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/core/local_demo_data.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/providers/audit_provider.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/contact_provider.dart';
import 'package:worktime_app/screens/customer_feedback_screen.dart';
import 'package:worktime_app/services/auth_service.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  testWidgets('lokaler Demo-Modus zeigt und bearbeitet Kundenfeedback', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final service = FirestoreService(firestore: FakeFirebaseFirestore());
    final profile = LocalDemoData.adminAccount.toProfile(
      orgId: 'demo-feedback-org',
    );
    final auth = _LocalAuthProvider(
      firestoreService: service,
      profileValue: profile,
    );
    final contacts = ContactProvider(
      firestoreService: service,
      disableAuthentication: true,
    );
    final audit = AuditProvider(
      firestoreService: service,
      disableAuthentication: true,
    );
    await contacts.updateSession(profile);
    await audit.updateSession(profile);
    addTearDown(() {
      auth.dispose();
      contacts.dispose();
      audit.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ContactProvider>.value(value: contacts),
          ChangeNotifierProvider<AuditProvider>.value(value: audit),
        ],
        child: MaterialApp(
          theme: AppTheme.resolveLight(useV2: true),
          home: CustomerFeedbackScreen(firestoreService: service),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('6 offene Rückmeldungen'), findsOneWidget);
    expect(find.text('Im Demo-Modus nicht verfügbar'), findsNothing);

    final menu = find.byWidgetPredicate((widget) => widget is PopupMenuButton);
    expect(menu, findsWidgets);
    await tester.tap(menu.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Als erledigt markieren'));
    await tester.pumpAndSettle();

    expect(find.text('5 offene Rückmeldungen'), findsOneWidget);
  });
}

class _LocalAuthProvider extends AuthProvider {
  _LocalAuthProvider({
    required super.firestoreService,
    required this.profileValue,
  }) : super(authService: AuthService());

  final AppUserProfile profileValue;

  @override
  AppUserProfile get profile => profileValue;

  @override
  bool get authDisabled => true;
}
