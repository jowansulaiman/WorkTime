import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/customer_wish.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/audit_provider.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/contact_provider.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/screens/customer_wishes_screen.dart';
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

const _manager = AppUserProfile(
  uid: 'owner-1',
  orgId: 'org-1',
  email: 'owner@laden.test',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Inhaber'),
);

const _employee = AppUserProfile(
  uid: 'emp-1',
  orgId: 'org-1',
  email: 'peter@laden.test',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Peter'),
);

/// #68: Widget-Tests für den internen Kundenwunsch-Eingang — Berechtigungs-
/// Gate (nur canManageInventory sieht das Aktionen-Menü), Offen/Erledigt-
/// Filter und der Manager-Status-Übergang bis in den Firestore-Doc.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late FirestoreService service;

  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    firestore = FakeFirebaseFirestore();
    service = FirestoreService(firestore: firestore);
  });

  Future<String> seedWish({
    required String text,
    CustomerWishStatus status = CustomerWishStatus.pending,
  }) async {
    final id = await service.submitCustomerWish(
      CustomerWish(
        orgId: 'org-1',
        referenceCode: 'ABC-123',
        storeName: 'Tabak Börse',
        category: CustomerWishCategory.magazine,
        wishText: text,
      ),
    );
    if (status != CustomerWishStatus.pending) {
      await service.updateCustomerWishStatus(
        orgId: 'org-1',
        wishId: id,
        status: status,
        handledByUid: 'owner-1',
      );
    }
    return id;
  }

  Future<void> pumpScreen(WidgetTester tester, AppUserProfile profile) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final auth = _FakeAuthProvider(firestoreService: service, profile: profile);
    final team = TeamProvider(firestoreService: service);
    final inventory = InventoryProvider(
        firestoreService: service, disableAuthentication: true);
    final contacts =
        ContactProvider(firestoreService: service, disableAuthentication: true);
    final audit =
        AuditProvider(firestoreService: service, disableAuthentication: true);
    await team.updateSession(profile);
    await inventory.updateSession(profile);
    await contacts.updateSession(profile);
    addTearDown(() {
      inventory.dispose();
      contacts.dispose();
      team.dispose();
      audit.dispose();
      auth.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<TeamProvider>.value(value: team),
          ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
          ChangeNotifierProvider<ContactProvider>.value(value: contacts),
          ChangeNotifierProvider<AuditProvider>.value(value: audit),
        ],
        child: MaterialApp(
          theme: AppTheme.resolveLight(useV2: true),
          home: CustomerWishesScreen(firestoreService: service),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets(
      'Filter: offene Wünsche sichtbar, erledigte erst über den '
      '"Erledigte"-Chip', (tester) async {
    await seedWish(text: 'Spiegel Ausgabe 26');
    await seedWish(text: 'Stange Marlboro', status: CustomerWishStatus.done);

    await pumpScreen(tester, _manager);

    expect(find.text('Spiegel Ausgabe 26'), findsOneWidget);
    expect(find.text('Stange Marlboro'), findsNothing,
        reason: 'erledigte Wünsche sind standardmaessig ausgeblendet');
    expect(find.text('1 offener Wunsch'), findsOneWidget);

    await tester.tap(find.text('Erledigte'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Stange Marlboro'), findsOneWidget);
  });

  testWidgets('Mitarbeiter ohne canManageInventory sieht kein Aktionen-Menü',
      (tester) async {
    await seedWish(text: 'Spiegel Ausgabe 26');

    await pumpScreen(tester, _employee);

    expect(find.text('Spiegel Ausgabe 26'), findsOneWidget,
        reason: 'aktive Mitglieder sehen den Eingang');
    expect(find.byType(PopupMenuButton<dynamic>), findsNothing);
    expect(
      find.byWidgetPredicate((widget) => widget is PopupMenuButton),
      findsNothing,
      reason: 'Status/Löschen ist Manager-only',
    );
  });

  testWidgets(
      'Manager markiert einen Wunsch als erledigt -> Status landet im '
      'Firestore-Doc', (tester) async {
    final id = await seedWish(text: 'Spiegel Ausgabe 26');

    await pumpScreen(tester, _manager);

    await tester.tap(find.byWidgetPredicate((w) => w is PopupMenuButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Als erledigt markieren'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final doc = await firestore
        .collection('organizations')
        .doc('org-1')
        .collection('customerWishes')
        .doc(id)
        .get();
    expect(doc.data()!['status'], 'erledigt');
    expect(doc.data()!['handledByUid'], 'owner-1');
  });
}
