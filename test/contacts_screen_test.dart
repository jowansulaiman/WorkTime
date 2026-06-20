import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/contact.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/contact_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/screens/contacts_screen.dart';
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

// Bewusst KEINE Demo-Identitäten (sonst seedet _maybeSeedLocalDemo zusätzliche
// Demo-Kontakte und die Zählungen werden nicht-deterministisch).
const _admin = AppUserProfile(
  uid: 'owner-1',
  orgId: 'org-1',
  email: 'owner@laden.test',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Inhaber'),
);

const _employee = AppUserProfile(
  uid: 'ma-1',
  orgId: 'org-1',
  email: 'ma@laden.test',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Mitarbeiter'),
);

Future<void> _pump(
  WidgetTester tester, {
  AppUserProfile profile = _admin,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1600);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final firestore = FakeFirebaseFirestore();
  final firestoreService = FirestoreService(firestore: firestore);

  final auth =
      _FakeAuthProvider(firestoreService: firestoreService, profile: profile);
  final team = TeamProvider(firestoreService: firestoreService);
  final contacts = ContactProvider(
    firestoreService: firestoreService,
    disableAuthentication: true,
  );

  await team.updateSession(profile);
  await contacts.updateSession(profile);
  await contacts.saveContact(
    const Contact(
      orgId: 'org-1',
      name: 'Nord-Tabak GmbH',
      type: ContactType.wholesaler,
    ),
  );
  await contacts.saveContact(
    const Contact(
      orgId: 'org-1',
      name: 'Stammkunde Hansen',
      type: ContactType.customer,
    ),
  );

  addTearDown(() {
    contacts.dispose();
    team.dispose();
    auth.dispose();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<TeamProvider>.value(value: team),
        ChangeNotifierProvider<ContactProvider>.value(value: contacts),
      ],
      child: MaterialApp(
        theme: AppTheme.resolveLight(useV2: true),
        home: const ContactsScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('de_DE'));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  testWidgets('zeigt die Kontaktliste und einen FAB für Manager',
      (tester) async {
    await _pump(tester);

    expect(find.text('Nord-Tabak GmbH'), findsOneWidget);
    expect(find.text('Stammkunde Hansen'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('Mitarbeiter sehen die Liste, aber keinen FAB', (tester) async {
    await _pump(tester, profile: _employee);

    expect(find.text('Nord-Tabak GmbH'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('Kategorie-Filter beschränkt die Liste', (tester) async {
    await _pump(tester);

    final customerChip = find.text('Kunde (1)');
    expect(customerChip, findsOneWidget);
    await tester.ensureVisible(customerChip);
    await tester.tap(customerChip);
    await tester.pumpAndSettle();

    expect(find.text('Stammkunde Hansen'), findsOneWidget);
    expect(find.text('Nord-Tabak GmbH'), findsNothing);
  });

  testWidgets('Suche filtert nach Name', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField).first, 'Hansen');
    await tester.pumpAndSettle();

    expect(find.text('Stammkunde Hansen'), findsOneWidget);
    expect(find.text('Nord-Tabak GmbH'), findsNothing);
  });
}
