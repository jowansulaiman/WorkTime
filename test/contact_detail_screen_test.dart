import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/contact.dart';
import 'package:worktime_app/models/contact_activity.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/contact_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/screens/contacts/contact_detail_screen.dart';
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

const _employee = AppUserProfile(
  uid: 'ma-1',
  orgId: 'org-1',
  email: 'ma@laden.test',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Mitarbeiter'),
);

const _inactive = AppUserProfile(
  uid: 'ma-2',
  orgId: 'org-1',
  email: 'gesperrt@laden.test',
  role: UserRole.employee,
  isActive: false,
  settings: UserSettings(name: 'Gesperrt'),
);

Future<String> _pump(
  WidgetTester tester, {
  AppUserProfile profile = _employee,
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
    Contact(
      orgId: 'org-1',
      name: 'Nord-Tabak GmbH',
      type: ContactType.wholesaler,
      contactPerson: 'Frau Meier',
      email: 'info@nord-tabak.test',
      phone: '0431 12345',
      street: 'Holtenauer Str. 1',
      postalCode: '24105',
      city: 'Kiel',
      notes: 'Zuverlässiger Großhändler.',
      tags: const ['Priorität A'],
      activities: [
        ContactActivity(
          type: ContactActivityType.call,
          occurredAt: DateTime(2026, 7, 1),
          note: 'Nachbestellung besprochen',
        ),
      ],
    ),
  );

  addTearDown(() {
    contacts.dispose();
    team.dispose();
    auth.dispose();
  });

  final id = contacts.contacts
      .firstWhere((c) => c.name == 'Nord-Tabak GmbH')
      .id!;

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<TeamProvider>.value(value: team),
        ChangeNotifierProvider<ContactProvider>.value(value: contacts),
      ],
      child: MaterialApp(
        theme: AppTheme.resolveLight(useV2: true),
        home: ContactDetailScreen(contactId: id),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return id;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('de_DE'));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  testWidgets('zeigt die 7 AllTec-Tabs in der richtigen Reihenfolge',
      (tester) async {
    await _pump(tester);

    for (final label in const [
      'Übersicht',
      'Adressen',
      'Kommunikation',
      'Ansprechpartner',
      'Einwilligungen',
      'Bank',
      'Notizen',
    ]) {
      // Auf die TabBar eingegrenzt — manche Labels (z. B. „Kommunikation")
      // tauchen zusätzlich als Section-Titel im aktiven Tab auf.
      expect(
        find.descendant(
          of: find.byType(TabBar),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'Tab $label fehlt',
      );
    }
    // Kopf-VCard trägt den Kontaktnamen.
    expect(find.text('Nord-Tabak GmbH'), findsWidgets);
  });

  testWidgets('Übersicht zeigt Kommunikation und letzte Aktivitäten',
      (tester) async {
    await _pump(tester);

    expect(find.text('info@nord-tabak.test'), findsOneWidget);
    expect(find.textContaining('Nachbestellung besprochen'), findsOneWidget);
  });

  testWidgets('gesperrter Nutzer sieht keine Kontakt-Details', (tester) async {
    await _pump(tester, profile: _inactive);

    expect(find.text('Keine Berechtigung für Kontakte.'), findsOneWidget);
    // Keine TabBar für gesperrte Nutzer.
    expect(find.text('Übersicht'), findsNothing);
  });
}
