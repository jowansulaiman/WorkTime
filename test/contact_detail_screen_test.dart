import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/contact.dart';
import 'package:worktime_app/models/contact_activity.dart';
import 'package:worktime_app/models/contact_details.dart';
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

const _admin = AppUserProfile(
  uid: 'admin-1',
  orgId: 'org-1',
  email: 'chef@laden.test',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Chef'),
);

Future<String> _pump(
  WidgetTester tester, {
  AppUserProfile profile = _employee,
  Contact? contact,
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
    contact ??
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

  final id = contacts.contacts.first.id!;

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

  testWidgets('M4: VCard-Chips + Person-Stammdaten (voll ausgebautes Modell)',
      (tester) async {
    await _pump(
      tester,
      contact: const Contact(
        orgId: 'org-1',
        name: 'Dr. Anna Meier',
        kind: ContactKind.person,
        status: ContactStatus.gesperrt,
        firstName: 'Anna',
        lastName: 'Meier',
        title: 'Dr.',
        gender: Gender.weiblich,
        position: 'Inhaberin',
        debitorNumber: 'D-100',
      ),
    );

    // displayName (Person → Vor-/Nachname) im Kopf (VCard + Breadcrumb).
    expect(find.text('Anna Meier'), findsWidgets);
    // Person-Chip + Status-Chip (gesperrt).
    expect(find.text('Person'), findsOneWidget);
    expect(find.text('Gesperrt'), findsOneWidget);
    // Übersicht-Stammdaten zeigen Person-Felder + Geschäftsdaten.
    expect(find.text('Vorname'), findsOneWidget);
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('Debitoren-Nr.'), findsOneWidget);
  });

  testWidgets('M4: Bank-Tab + strukturierte Adresse rendern', (tester) async {
    await _pump(
      tester,
      contact: const Contact(
        orgId: 'org-1',
        name: 'Nord-Tabak GmbH',
        addresses: [
          ContactAddress(
            id: 'a-1',
            type: AddressType.lieferung,
            street: 'Lagerweg',
            houseNumber: '5',
            zip: '24106',
            city: 'Kiel',
          ),
        ],
        bankAccounts: [
          BankAccount(
            id: 'b-1',
            iban: 'DE89370400440532013000',
            bankName: 'Commerzbank',
          ),
        ],
      ),
    );

    // Bank-Tab öffnen und IBAN prüfen (Tab kann in der scrollbaren TabBar
    // außerhalb des sichtbaren Bereichs liegen → erst sichtbar machen).
    await tester.ensureVisible(find.text('Bank'));
    await tester.tap(find.text('Bank'));
    await tester.pumpAndSettle();
    expect(find.text('DE89370400440532013000'), findsOneWidget);
    expect(find.text('Commerzbank'), findsOneWidget);

    // Adressen-Tab: strukturierte Lieferadresse.
    await tester.ensureVisible(find.text('Adressen'));
    await tester.tap(find.text('Adressen'));
    await tester.pumpAndSettle();
    expect(find.text('Lieferadresse'), findsOneWidget);
  });

  testWidgets('M5b: Manager sieht Bearbeiten + kann eine Adresse hinzufügen',
      (tester) async {
    await _pump(
      tester,
      profile: _admin,
      contact: const Contact(orgId: 'org-1', name: 'Nord-Tabak GmbH'),
    );

    // „Bearbeiten"-Aktion in der AppBar (nur Manager).
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

    // In den Adressen-Tab und eine Rechnungsadresse hinzufügen.
    await tester.ensureVisible(find.text('Adressen'));
    await tester.tap(find.text('Adressen'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Adresse'));
    await tester.pumpAndSettle();

    // Dialog: Straße eintragen (Typ-Default = Rechnungsadresse) und speichern.
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Straße'), 'Lagerweg 5');
    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.pumpAndSettle();

    // Persistiert → neue Rechnungsadresse-Sektion im Tab.
    expect(find.text('Rechnungsadresse'), findsOneWidget);
    expect(find.text('Lagerweg 5'), findsOneWidget);
  });
}
