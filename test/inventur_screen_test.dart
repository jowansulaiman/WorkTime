import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/inventory_count_session.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/stock_movement.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/screens/inventur_screen.dart';
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

  const employee = AppUserProfile(
    uid: 'emp-1',
    orgId: 'org-1',
    email: 'peter@laden.test',
    role: UserRole.employee,
    isActive: true,
    settings: UserSettings(name: 'Peter'),
  );

  /// Local-Modus-Provider mit einem Standort (site-1) und vier Artikeln:
  /// zwei aktive auf site-1, ein inaktiver, einer auf site-2.
  Future<(InventoryProvider, TeamProvider)> seedProviders() async {
    final firestoreService =
        FirestoreService(firestore: FakeFirebaseFirestore());
    final inventory = InventoryProvider(
      firestoreService: firestoreService,
      disableAuthentication: true,
    );
    await inventory.updateSession(admin);
    await inventory.saveProduct(const Product(
      orgId: 'org-1',
      siteId: 'site-1',
      name: 'Cola 0,5l',
      category: 'Getränke',
      unit: 'Stück',
      currentStock: 5,
    ));
    await inventory.saveProduct(const Product(
      orgId: 'org-1',
      siteId: 'site-1',
      name: 'Bounty',
      category: 'Süßware',
      unit: 'Stück',
      currentStock: 10,
      purchasePriceCents: 60,
    ));
    await inventory.saveProduct(const Product(
      orgId: 'org-1',
      siteId: 'site-1',
      name: 'Altware',
      currentStock: 2,
      isActive: false,
    ));
    await inventory.saveProduct(const Product(
      orgId: 'org-1',
      siteId: 'site-2',
      name: 'Fremdartikel',
      currentStock: 3,
    ));

    final team = TeamProvider(
      firestoreService: firestoreService,
      disableAuthentication: true,
    );
    await team.updateSession(admin);
    await team.saveSite(const SiteDefinition(
      id: 'site-1',
      orgId: 'org-1',
      name: 'Strichmännchen',
      street: 'Musterstrasse 1',
      postalCode: '24103',
      city: 'Kiel',
      federalState: 'Schleswig-Holstein',
      latitude: 54.3233,
      longitude: 10.1394,
      createdByUid: 'owner-1',
    ));
    return (inventory, team);
  }

  Future<void> pumpInventur(
    WidgetTester tester, {
    required InventoryProvider inventory,
    required TeamProvider team,
    AppUserProfile profile = admin,
  }) async {
    final auth = _TestAuthProvider(
      firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      profile: profile,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
          ChangeNotifierProvider<TeamProvider>.value(value: team),
        ],
        child: const MaterialApp(home: InventurScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('listet nur aktive Artikel des Standorts (alphabetisch)',
      (tester) async {
    final (inventory, team) = await seedProviders();
    await pumpInventur(tester, inventory: inventory, team: team);

    // Genau ein Standort -> automatisch gewählt, aktive site-1-Artikel sichtbar.
    expect(find.text('Bounty'), findsOneWidget);
    expect(find.text('Cola 0,5l'), findsOneWidget);
    // Inaktive Artikel und Artikel anderer Standorte fehlen.
    expect(find.text('Altware'), findsNothing);
    expect(find.text('Fremdartikel'), findsNothing);
    // Fortschritt zählt über den Zähl-Umfang (2 aktive Artikel), nichts gezählt.
    expect(find.text('0 von 2 gezählt'), findsOneWidget);
    // Ohne Eingabe ist die Differenz-Prüfung gesperrt.
    final button = tester.widget<FilledButton>(find.widgetWithText(
        FilledButton, 'Differenzen prüfen'));
    expect(button.onPressed, isNull);
  });

  testWidgets('Differenz-Vorschau zeigt nur Abweichungen', (tester) async {
    final (inventory, team) = await seedProviders();
    await pumpInventur(tester, inventory: inventory, team: team);

    final products = inventory.productsForSite('site-1');
    final cola = products.firstWhere((p) => p.name == 'Cola 0,5l');
    final bounty = products.firstWhere((p) => p.name == 'Bounty');

    // Cola stimmt (5 = Buchbestand), Bounty weicht ab (7 statt 10).
    await tester.enterText(
        find.byKey(ValueKey('inventur-count-${cola.id}')), '5');
    await tester.enterText(
        find.byKey(ValueKey('inventur-count-${bounty.id}')), '7');
    await tester.pump();
    expect(find.text('2 von 2 gezählt'), findsOneWidget);

    await tester.tap(find.text('Differenzen prüfen'));
    await tester.pumpAndSettle();

    // Nur EINE Abweichung (Bounty) im Sheet; Cola erzeugt keine Buchung.
    expect(find.text('Differenz-Vorschau'), findsOneWidget);
    expect(find.text('1 Differenz buchen'), findsOneWidget);
    expect(find.text('-3'), findsOneWidget);
    expect(find.text('Buchbestand 10 · gezählt 7 Stück'), findsOneWidget);
    // EK gepflegt (Bounty) -> Bewertung der Differenzen wird angezeigt.
    expect(find.text('Differenz nach EK'), findsOneWidget);
  });

  testWidgets('Buchen setzt Bestand, schreibt stocktake-Bewegung und räumt auf',
      (tester) async {
    final (inventory, team) = await seedProviders();
    await pumpInventur(tester, inventory: inventory, team: team);

    final products = inventory.productsForSite('site-1');
    final cola = products.firstWhere((p) => p.name == 'Cola 0,5l');
    final bounty = products.firstWhere((p) => p.name == 'Bounty');

    await tester.enterText(
        find.byKey(ValueKey('inventur-count-${cola.id}')), '5');
    await tester.enterText(
        find.byKey(ValueKey('inventur-count-${bounty.id}')), '7');
    await tester.pump();

    await tester.tap(find.text('Differenzen prüfen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 Differenz buchen'));
    await tester.pumpAndSettle();

    // recordStocktake-Effekt: Bestand korrigiert + Bewegung vom Typ stocktake.
    final updated = inventory
        .productsForSite('site-1')
        .firstWhere((p) => p.name == 'Bounty');
    expect(updated.currentStock, 7);
    expect(
      inventory.recentMovements
          .any((m) => m.type == StockMovementType.stocktake),
      isTrue,
    );
    // Deutsche Zusammenfassung als SnackBar.
    expect(find.text('1 Differenz gebucht.'), findsOneWidget);
    // Gebuchte aus der Session entfernt (Feld leer), beide als erledigt
    // markiert -> Fortschritt bleibt vollständig.
    final bountyField = tester.widget<TextField>(
        find.byKey(ValueKey('inventur-count-${bounty.id}')));
    expect(bountyField.controller?.text, isEmpty);
    expect(find.text('2 von 2 gezählt'), findsOneWidget);
  });

  testWidgets('Session-Modus: starten, zählen, abschließen bucht + completed',
      (tester) async {
    final (inventory, team) = await seedProviders();
    await pumpInventur(tester, inventory: inventory, team: team);

    // Session starten (WW-8).
    await tester.tap(find.widgetWithText(FilledButton, 'Session'));
    await tester.pumpAndSettle();
    expect(inventory.resumeableSessions(), hasLength(1));
    final sessionId = inventory.resumeableSessions().single.id!;

    final bounty = inventory
        .productsForSite('site-1')
        .firstWhere((p) => p.name == 'Bounty');
    await tester.enterText(
        find.byKey(ValueKey('inventur-count-${bounty.id}')), '7');
    await tester.pump();

    // Abschließen (WW-9): bucht die Differenz absolut + Session completed.
    await tester.tap(find.widgetWithText(FilledButton, 'Abschließen'));
    await tester.pumpAndSettle();

    final updated = inventory
        .productsForSite('site-1')
        .firstWhere((p) => p.name == 'Bounty');
    expect(updated.currentStock, 7);
    expect(inventory.countSessionById(sessionId)!.status,
        InventoryCountStatus.completed);
    expect(inventory.resumeableSessions(), isEmpty);
  });

  testWidgets('ohne canManageInventory kein Zugriff', (tester) async {
    final (inventory, team) = await seedProviders();
    await pumpInventur(
      tester,
      inventory: inventory,
      team: team,
      profile: employee,
    );

    expect(find.text('Keine Berechtigung'), findsOneWidget);
    // Keine Zähl-Liste, keine Aktionen.
    expect(find.text('Differenzen prüfen'), findsNothing);
    expect(find.byType(TextField), findsNothing);
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
