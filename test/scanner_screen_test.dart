import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/screens/scanner_screen.dart';
import 'package:worktime_app/services/auth_service.dart';
import 'package:worktime_app/services/barcode_scanner.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/services/scan_feedback.dart';
import 'package:worktime_app/theme/app_theme.dart';

/// Steuerbarer Kamera-Fake: der Test schiebt EANs in den Stream, ohne echte
/// Platform-Channels. Vorschau = Platzhalter.
class _FakeBarcodeScanner implements BarcodeScanner {
  _FakeBarcodeScanner();

  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  @override
  bool get isAvailable => true;

  @override
  bool get supportsTorch => false;

  @override
  Stream<String> get codes => _controller.stream;

  void emit(String code) => _controller.add(code);

  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> toggleTorch() async {}
  @override
  Future<void> switchCamera() async {}
  @override
  Widget buildPreview(BuildContext context) =>
      const SizedBox(key: Key('fake-preview'));
  @override
  Future<void> dispose() async {
    await _controller.close();
  }
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => initializeDateFormatting('de_DE'));

  setUp(() {
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

  // Gueltige Pruefziffer, sonst weist der Screen den Code als ungueltig ab.
  const validEan = '4011200296908';

  Future<(_FakeBarcodeScanner, InventoryProvider)> pumpScanner(
    WidgetTester tester, {
    List<Product> products = const [],
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final firestoreService =
        FirestoreService(firestore: FakeFirebaseFirestore());

    // Genau ein Standort -> Scanner waehlt ihn automatisch.
    await DatabaseService.saveLocalSites(
      const [SiteDefinition(id: 'site-1', orgId: 'org-1', name: 'Strichmaennchen')],
      scope: LocalStorageScope.fromUser(admin),
    );

    final team = TeamProvider(
      firestoreService: firestoreService,
      disableAuthentication: true,
    );
    await team.updateSession(admin);

    final inventory = InventoryProvider(
      firestoreService: firestoreService,
      disableAuthentication: true,
    );
    await inventory.updateSession(admin);
    for (final product in products) {
      await inventory.saveProduct(product);
    }

    final auth = _TestAuthProvider(
      firestoreService: firestoreService,
      profile: admin,
    );
    final scanner = _FakeBarcodeScanner();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
          ChangeNotifierProvider<TeamProvider>.value(value: team),
        ],
        child: MaterialApp(
          theme: AppTheme.resolveLight(useV2: true),
          home: ScannerScreen(
            scanner: scanner,
            feedback: const NoopScanFeedback(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return (scanner, inventory);
  }

  testWidgets('bekannter EAN zeigt die Artikel-Karte mit Buchungs-Buttons',
      (tester) async {
    final (scanner, _) = await pumpScanner(
      tester,
      products: const [
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Feuerzeug Clipper',
          barcode: validEan,
          currentStock: 5,
        ),
      ],
    );

    // In den Buchen-Modus wechseln (Standard ist jetzt Scan & Go / Bestellen).
    await tester.tap(find.text('Buchen'));
    await tester.pump();

    scanner.emit(validEan);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Feuerzeug Clipper'), findsOneWidget);
    expect(find.text('Wareneingang'), findsOneWidget);
    expect(find.text('Abgang'), findsOneWidget);
  });

  testWidgets('Scan & Go: Scan legt den Artikel direkt in den Warenkorb',
      (tester) async {
    final (scanner, inventory) = await pumpScanner(
      tester,
      products: const [
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Feuerzeug Clipper',
          barcode: validEan,
          currentStock: 5,
        ),
      ],
    );

    // Standardmodus ist Bestellen (Scan & Go) — kein Moduswechsel noetig.
    scanner.emit(validEan);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final cart = inventory.orderCartForSite('site-1');
    expect(cart?.items, hasLength(1));
    expect(cart?.items.single.name, 'Feuerzeug Clipper');
    expect(cart?.items.single.quantity, 1);
    expect(find.textContaining('in den Warenkorb gelegt'), findsOneWidget);
    expect(find.textContaining('Warenkorb: 1 Artikel'), findsOneWidget);
  });

  testWidgets('unbekannter EAN bietet „Neu anlegen" an', (tester) async {
    final (scanner, _) = await pumpScanner(tester);

    scanner.emit(validEan);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Artikel nicht vorhanden'), findsOneWidget);
    expect(find.text('Neu anlegen'), findsOneWidget);
  });

  testWidgets('manuelle Eingabe findet den Artikel', (tester) async {
    await pumpScanner(
      tester,
      products: const [
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Tabak Drum',
          barcode: validEan,
          currentStock: 2,
        ),
      ],
    );

    await tester.tap(find.text('Buchen'));
    await tester.pump();

    await tester.enterText(
        find.byType(TextField).first, validEan);
    await tester.tap(find.text('Suchen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Tabak Drum'), findsOneWidget);
  });

  testWidgets('Wareneingang bucht den Bestand (+Menge)', (tester) async {
    final (scanner, inventory) = await pumpScanner(
      tester,
      products: const [
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Feuerzeug Clipper',
          barcode: validEan,
          currentStock: 5,
        ),
      ],
    );

    await tester.tap(find.text('Buchen'));
    await tester.pump();

    scanner.emit(validEan);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Wareneingang'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(inventory.products.single.currentStock, 6);
  });

  testWidgets('Ton-Schalter schaltet stumm und persistiert', (tester) async {
    await pumpScanner(tester);

    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await tester.pump();

    expect(find.byIcon(Icons.volume_off_outlined), findsOneWidget);
    expect(
      await DatabaseService.getLocalSetting('scanner_sound_enabled'),
      '0',
    );
  });

  testWidgets('gespeicherte Stumm-Einstellung wird beim Start uebernommen',
      (tester) async {
    await DatabaseService.saveLocalSetting('scanner_sound_enabled', '0');
    await pumpScanner(tester);

    expect(find.byIcon(Icons.volume_off_outlined), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
  });

  testWidgets('Inventurmodus: Scan zaehlt und Abschluss setzt den Bestand',
      (tester) async {
    final (scanner, inventory) = await pumpScanner(
      tester,
      products: const [
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Feuerzeug Clipper',
          barcode: validEan,
          currentStock: 5,
        ),
      ],
    );

    // In den Inventurmodus wechseln.
    await tester.tap(find.text('Inventur'));
    await tester.pump();

    // Scannen zaehlt +1.
    scanner.emit(validEan);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Feuerzeug Clipper'), findsOneWidget);
    expect(find.textContaining('Gezaehlt: 1'), findsOneWidget);

    // Abschliessen -> recordStocktake setzt den Bestand auf die gezaehlte Menge.
    await tester.tap(find.textContaining('Inventur abschliessen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Inventur abgeschlossen'), findsOneWidget);
    expect(inventory.products.single.currentStock, 1);

    await tester.tap(find.text('OK'));
    await tester.pump();
  });

  testWidgets('Treffer-Karte oeffnet den Preisverlauf (Leerzustand)',
      (tester) async {
    final (scanner, _) = await pumpScanner(
      tester,
      products: const [
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Feuerzeug Clipper',
          barcode: validEan,
          currentStock: 5,
          sellingPriceCents: 199,
        ),
      ],
    );

    await tester.tap(find.text('Buchen'));
    await tester.pump();

    scanner.emit(validEan);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Preisverlauf'), findsOneWidget); // Button
    await tester.tap(find.text('Preisverlauf'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Sheet-Titel zusaetzlich -> jetzt zwei Vorkommen, plus Leerzustand.
    expect(find.text('Preisverlauf'), findsWidgets);
    expect(find.textContaining('Noch keine Preisaenderungen'), findsOneWidget);
  });

  testWidgets('ungueltige Pruefziffer wird abgewiesen (keine Karte)',
      (tester) async {
    final (scanner, _) = await pumpScanner(
      tester,
      products: const [
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Feuerzeug Clipper',
          barcode: validEan,
          currentStock: 5,
        ),
      ],
    );

    scanner.emit('4011200296900'); // falsche Pruefziffer
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Feuerzeug Clipper'), findsNothing);
    expect(find.textContaining('Ungueltiger Barcode'), findsOneWidget);
  });
}
