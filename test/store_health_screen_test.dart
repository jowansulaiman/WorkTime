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
import 'package:worktime_app/screens/store_health_screen.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

import 'support/router_harness.dart';

/// Widget-Test des Laden-Benchmark-Screens (P2.3).
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

  String day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  testWidgets('zeigt Tagesvergleich je Laden mit Delta', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fs = FakeFirebaseFirestore();
    final now = DateTime.now();
    var seq = 0;

    Future<void> seed(String siteId, DateTime at, int count) async {
      for (var i = 0; i < count; i++) {
        final r = PosReceipt(
          orgId: 'org-1',
          siteId: siteId,
          referenceNumber: 'r${seq++}',
          type: 'sales',
          isRevenue: true,
          businessDay: day(at),
          // Rückwärts von [at]: nie in der Zukunft der transactionDate-Range-
          // Query (to = now); der Geschäftstag bleibt über businessDay gepinnt.
          transactionDate: at.subtract(Duration(minutes: i)),
        );
        await fs
            .collection('organizations')
            .doc('org-1')
            .collection('posReceipts')
            .doc('rec$seq')
            .set(r.toFirestoreMap());
      }
    }

    Future<void> seedProduct(String id, String siteId, String siteName) => fs
        .collection('organizations')
        .doc('org-1')
        .collection('products')
        .doc(id)
        .set({
      'orgId': 'org-1',
      'siteId': siteId,
      'siteName': siteName,
      'name': id,
      'nameLower': id,
      'isActive': true,
    });

    await seedProduct('p1', 'site-1', 'Strichmännchen');
    await seedProduct('p2', 'site-2', 'Tabak Börse');
    // site-1: heute 6, gleiche Wochentage davor je 10 -> Schnitt 10 -> −40 %.
    // Wall-Clock-sicher zu JEDER Uhrzeit: Anker = exakt jetzt (keine feste
    // Uhrzeit wie 10:00, kein Rückversatz über Mitternacht) — der ausgewertete
    // Geschäftstag ist day(now), die Beleg-Zeitstempel laufen rückwärts.
    await seed('site-1', now, 6);
    await seed('site-1', now.subtract(const Duration(days: 7)), 10);
    await seed('site-1', now.subtract(const Duration(days: 14)), 10);
    // site-2: nur heute 12 (keine Vergleichsbasis).
    await seed('site-2', now, 12);

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
        child: const MaterialApp(home: StoreHealthScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Laden-Benchmark'), findsOneWidget);
    expect(find.text('Strichmännchen'), findsOneWidget);
    expect(find.text('Tabak Börse'), findsOneWidget);
    expect(find.textContaining('Belege heute'), findsWidgets);
    expect(find.textContaining('-40'), findsWidgets); // site-1 Einbruch
    expect(find.textContaining('keine Basis'), findsWidgets); // site-2
  });
}
