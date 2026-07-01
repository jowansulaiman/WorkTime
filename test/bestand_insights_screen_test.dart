import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/providers/sales_insights_provider.dart';
import 'package:worktime_app/screens/bestand_insights_screen.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

import 'support/router_harness.dart';

/// Widget-Test des Bestand-Insights-Screens (P1.1–P1.3 sichtbar gemacht).
void main() {
  const admin = AppUserProfile(
    uid: 'owner-1',
    orgId: 'org-1',
    email: 'owner@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Inhaber'),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    await initializeDateFormatting('de_DE');
  });

  Future<void> seedProduct(
    FakeFirebaseFirestore fs, {
    required String id,
    required int currentStock,
    int? purchasePriceCents,
  }) =>
      fs
          .collection('organizations')
          .doc('org-1')
          .collection('products')
          .doc(id)
          .set({
        'orgId': 'org-1',
        'siteId': 'site-1',
        'siteName': 'Strichmännchen',
        'name': id,
        'nameLower': id.toLowerCase(),
        'currentStock': currentStock,
        'purchasePriceCents': purchasePriceCents,
        'isActive': true,
      });

  Future<void> seedIssue(
    FakeFirebaseFirestore fs, {
    required String id,
    required String productId,
    required int qty,
    required DateTime at,
    String type = 'issue',
  }) =>
      fs
          .collection('organizations')
          .doc('org-1')
          .collection('stockMovements')
          .doc(id)
          .set({
        'orgId': 'org-1',
        'siteId': 'site-1',
        'productId': productId,
        'type': type,
        'quantityDelta': -qty,
        'createdAt': Timestamp.fromDate(at),
      });

  testWidgets('zeigt Ladenhüter, totes Kapital und Bestellschwellen-Tipps',
      (tester) async {
    // Hohe Test-Fläche, damit alle (lazy gebauten) ListView-Abschnitte rendern.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fs = FakeFirebaseFirestore();
    final now = DateTime.now();
    await seedProduct(fs,
        id: 'Ladenhueter', currentStock: 50, purchasePriceCents: 300);
    await seedProduct(fs, id: 'Renner', currentStock: 10, purchasePriceCents: 80);
    await seedIssue(fs,
        id: 'm1',
        productId: 'Renner',
        qty: 28,
        at: now.subtract(const Duration(days: 2)));
    await seedIssue(fs,
        id: 'm2',
        productId: 'Renner',
        qty: 28,
        at: now.subtract(const Duration(days: 6)));
    // Inventur-Fehlbestand für den Ladenhüter: -2 × 3,00 € EK = 6,00 € Schwund.
    await seedIssue(fs,
        id: 'stk',
        productId: 'Ladenhueter',
        qty: 2,
        type: 'stocktake',
        at: now.subtract(const Duration(days: 3)));

    final service = FirestoreService(firestore: fs);
    final inventory = InventoryProvider(firestoreService: service);
    final insights = SalesInsightsProvider();

    // Echte DB-/Stream-Async außerhalb der Fake-Async-Uhr des Widget-Tests
    // ausführen (sonst hängen die FakeFirebaseFirestore-Futures).
    await tester.runAsync(() async {
      await inventory.updateSession(admin, localStorageOnly: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      insights.bind(inventory, admin);
      await insights.load(siteId: 'site-1');
    });

    final auth = FakeAuthProvider(firestoreService: service, profile: admin);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
          ChangeNotifierProvider<SalesInsightsProvider>.value(value: insights),
        ],
        child: const MaterialApp(home: BestandInsightsScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Bestand-Insights'), findsOneWidget);
    expect(find.textContaining('Ladenhüter (1)'), findsOneWidget);
    expect(find.text('Ladenhueter'),
        findsWidgets); // Dead-Stock- + Schwund-Tile
    expect(find.text('Totes Kapital'), findsOneWidget);
    // 50 × 3,00 € EK = 150,00 € (KPI + Dead-Stock-Tile). NumberFormat nutzt ein
    // geschütztes Leerzeichen vor dem €, daher auf die Zahl matchen.
    expect(find.textContaining('150,00'), findsWidgets);
    // Renner: 56 Stück/28 Tage = 2/Tag -> Bestellschwellen-Vorschlag (≠ 0).
    expect(find.textContaining('Bestellschwellen-Vorschläge'), findsOneWidget);
    // P2.2 Schwund: Inventur-Fehlbestand -2 × 3,00 € = 6,00 €.
    expect(find.textContaining('Schwund / Inventurdifferenz (1)'), findsOneWidget);
    expect(find.textContaining('6,00'), findsWidgets);
  });

  testWidgets('„Übernehmen" schreibt die vorgeschlagenen Schwellen in den Artikel',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fs = FakeFirebaseFirestore();
    final now = DateTime.now();
    // Renner ohne Lieferant -> Default-Lieferzeit 3 + Sicherheit 3; 2/Tag ->
    // Meldebestand ceil(2×6)=12, Zielbestand 12+ceil(2×14)=40.
    await seedProduct(fs, id: 'Renner', currentStock: 10, purchasePriceCents: 80);
    await seedIssue(fs,
        id: 'm1',
        productId: 'Renner',
        qty: 28,
        at: now.subtract(const Duration(days: 2)));
    await seedIssue(fs,
        id: 'm2',
        productId: 'Renner',
        qty: 28,
        at: now.subtract(const Duration(days: 6)));

    final service = FirestoreService(firestore: fs);
    final inventory = InventoryProvider(firestoreService: service);
    final insights = SalesInsightsProvider();
    await tester.runAsync(() async {
      await inventory.updateSession(admin, localStorageOnly: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      insights.bind(inventory, admin);
      await insights.load(siteId: 'site-1');
    });

    final auth = FakeAuthProvider(firestoreService: service, profile: admin);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
          ChangeNotifierProvider<SalesInsightsProvider>.value(value: insights),
        ],
        child: const MaterialApp(home: BestandInsightsScreen()),
      ),
    );
    await tester.pump();

    final applyButton = find.widgetWithText(TextButton, 'Übernehmen');
    expect(applyButton, findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(applyButton);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    late Map<String, dynamic> data;
    await tester.runAsync(() async {
      final doc = await fs
          .collection('organizations')
          .doc('org-1')
          .collection('products')
          .doc('Renner')
          .get();
      data = doc.data()!;
    });
    expect((data['minStock'] as num).toInt(), 12);
    expect((data['targetStock'] as num).toInt(), 40);
  });
}
