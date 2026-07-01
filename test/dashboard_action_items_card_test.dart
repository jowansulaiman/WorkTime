import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/services/auth_service.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/theme/app_theme.dart';
import 'package:worktime_app/widgets/dashboard_action_items_card.dart';

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider({required super.firestoreService, AppUserProfile? profile})
      : _profile = profile,
        super(authService: AuthService());

  final AppUserProfile? _profile;

  @override
  AppUserProfile? get profile => _profile;
}

const _admin = AppUserProfile(
  uid: 'owner-1',
  orgId: 'org-1',
  email: 'owner@laden.test',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Inhaber'),
);

Future<InventoryProvider> _pump(
  WidgetTester tester, {
  List<Product> products = const [],
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
      _FakeAuthProvider(firestoreService: firestoreService, profile: _admin);
  final inventory = InventoryProvider(
    firestoreService: firestoreService,
    disableAuthentication: true,
  );
  await inventory.updateSession(_admin);
  for (final product in products) {
    await inventory.saveProduct(product);
  }
  // Ohne Standort-Zuordnung -> Kühlschrank-Warnung org-weit (Fallback, §12.7).
  final team = TeamProvider(firestoreService: firestoreService);

  addTearDown(() {
    inventory.dispose();
    auth.dispose();
    team.dispose();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
        ChangeNotifierProvider<TeamProvider>.value(value: team),
      ],
      child: MaterialApp(
        theme: AppTheme.resolveLight(useV2: true),
        home: const Scaffold(
          body: Center(child: DashboardActionItemsCard()),
        ),
      ),
    ),
  );
  await tester.pump();
  return inventory;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('de_DE'));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  testWidgets('zeigt Nachbestell-Hinweis bei niedrigem Bestand', (tester) async {
    await _pump(tester, products: const [
      Product(
        orgId: 'org-1',
        siteId: 'site-1',
        name: 'Feuerzeug',
        currentStock: 1,
        minStock: 5,
      ),
    ]);

    expect(find.text('Hinweise & Aktionspunkte'), findsOneWidget);
    expect(
      find.textContaining('nachbestellt werden'),
      findsOneWidget,
    );
  });

  testWidgets('blendet sich aus, wenn nichts ansteht', (tester) async {
    await _pump(tester, products: const [
      Product(
        orgId: 'org-1',
        siteId: 'site-1',
        name: 'Genug',
        currentStock: 50,
        minStock: 5,
      ),
    ]);

    expect(find.text('Hinweise & Aktionspunkte'), findsNothing);
  });
}
