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
import 'package:worktime_app/screens/inventory_screen.dart';
import 'package:worktime_app/services/auth_service.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  setUp(() {
    // Ohne diesen Mock haengt SharedPreferences.getInstance() im Widget-Test
    // (kein Platform-Channel) -> _loadLocalData() in updateSession blockiert.
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  const admin = AppUserProfile(
    uid: 'owner-1',
    orgId: 'org-1',
    email: 'owner@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Inhaber'),
  );

  testWidgets('zeigt Tabs und einen Niedrigbestand-Artikel', (tester) async {
    final firestoreService = FirestoreService(firestore: FakeFirebaseFirestore());

    final inventory = InventoryProvider(
      firestoreService: firestoreService,
      disableAuthentication: true,
    );
    await inventory.updateSession(admin);
    await inventory.saveProduct(
      const Product(
        orgId: 'org-1',
        siteId: 'site-1',
        name: 'Feuerzeug Clipper',
        currentStock: 1,
        minStock: 10,
      ),
    );

    final auth = _TestAuthProvider(
      firestoreService: firestoreService,
      profile: admin,
    );
    final team = TeamProvider(firestoreService: firestoreService);
    await team.updateSession(admin);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
          ChangeNotifierProvider<TeamProvider>.value(value: team),
        ],
        child: const MaterialApp(home: InventoryScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Die drei Reiter sind vorhanden.
    expect(find.text('Bestand'), findsWidgets);
    expect(find.text('Lieferanten'), findsWidgets);
    expect(find.text('Bestellungen'), findsWidgets);

    // Der niedrige Bestand wird im Bestand-Tab gelistet.
    expect(find.text('Feuerzeug Clipper'), findsWidgets);
  });

  testWidgets('zeigt den Leerzustand ohne Artikel', (tester) async {
    final firestoreService = FirestoreService(firestore: FakeFirebaseFirestore());
    final inventory = InventoryProvider(
      firestoreService: firestoreService,
      disableAuthentication: true,
    );
    await inventory.updateSession(admin);

    final auth = _TestAuthProvider(
      firestoreService: firestoreService,
      profile: admin,
    );
    final team = TeamProvider(firestoreService: firestoreService);
    await team.updateSession(admin);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
          ChangeNotifierProvider<TeamProvider>.value(value: team),
        ],
        child: const MaterialApp(home: InventoryScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Der gemeinsame EmptyState (Plan-Gap duplicate-emptystate-widget) rendert.
    expect(find.byType(InventoryScreen), findsOneWidget);
    expect(find.textContaining('Artikel'), findsWidgets);
  });
}

class _TestAuthProvider extends AuthProvider {
  _TestAuthProvider({
    required super.firestoreService,
    AppUserProfile? profile,
  })  : _profile = profile,
        super(authService: AuthService());

  final AppUserProfile? _profile;

  @override
  AppUserProfile? get profile => _profile;
}
