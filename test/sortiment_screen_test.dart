import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/pos_receipt.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/screens/sortiment_screen.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

import 'support/router_harness.dart';

/// Widget-Test der Sortimentsanalyse (P2.1) — Rohertrag/ABC sichtbar gemacht.
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

  testWidgets('zeigt Rohertrag-KPI und ABC-Liste', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fs = FakeFirebaseFirestore();
    final now = DateTime.now();
    await fs
        .collection('organizations')
        .doc('org-1')
        .collection('products')
        .doc('snack')
        .set({
      'orgId': 'org-1',
      'siteId': 'site-1',
      'siteName': 'Strichmännchen',
      'name': 'Snack',
      'nameLower': 'snack',
      'purchasePriceCents': 50,
      'isActive': true,
    });
    final receipt = PosReceipt(
      orgId: 'org-1',
      siteId: 'site-1',
      referenceNumber: 'B1',
      type: 'sales',
      isRevenue: true,
      transactionDate: now.subtract(const Duration(days: 1)),
      lines: const [
        PosReceiptLine(
            productId: 'snack',
            name: 'Snack',
            category: 'Süßware',
            quantity: 4,
            unitPriceCents: 150),
      ],
    );
    await fs
        .collection('organizations')
        .doc('org-1')
        .collection('posReceipts')
        .doc('B1')
        .set(receipt.toFirestoreMap());
    // Zwei Belege Snack+Cola zusammen -> Warenkorb-Paar (P4.2).
    for (final ref in ['B2', 'B3']) {
      final combo = PosReceipt(
        orgId: 'org-1',
        siteId: 'site-1',
        referenceNumber: ref,
        type: 'sales',
        isRevenue: true,
        transactionDate: now.subtract(const Duration(days: 1)),
        lines: const [
          PosReceiptLine(productId: 'snack', name: 'Snack', quantity: 1, unitPriceCents: 150),
          PosReceiptLine(productId: 'cola', name: 'Cola', quantity: 1, unitPriceCents: 200),
        ],
      );
      await fs
          .collection('organizations')
          .doc('org-1')
          .collection('posReceipts')
          .doc(ref)
          .set(combo.toFirestoreMap());
    }

    final service = FirestoreService(firestore: fs);
    final inventory = InventoryProvider(firestoreService: service);
    await tester.runAsync(() async {
      await inventory.updateSession(admin, localStorageOnly: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    final auth = FakeAuthProvider(firestoreService: service, profile: admin);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
        ],
        child: const MaterialApp(home: SortimentScreen()),
      ),
    );
    // postFrame stößt das Laden an; FakeFirestore-Reads lösen sich über
    // Microtasks -> mehrere bare pumps spülen sie durch.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Sortimentsanalyse'), findsOneWidget);
    expect(find.text('Rohertrag'), findsWidgets);
    expect(find.text('Snack'), findsOneWidget);
    expect(find.textContaining('Süßware'), findsWidgets);
    // P4.2 Warenkorb: Snack+Cola zweimal zusammen -> Paar sichtbar.
    expect(find.textContaining('Häufig zusammen gekauft'), findsOneWidget);
    expect(find.text('Cola + Snack'), findsOneWidget);
  });
}
