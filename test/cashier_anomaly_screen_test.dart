import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/pos_receipt.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/screens/cashier_anomaly_screen.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

import 'support/router_harness.dart';

class _FakeTeamProvider extends TeamProvider {
  _FakeTeamProvider(this._members, FirestoreService service)
      : super(firestoreService: service);
  final List<AppUserProfile> _members;
  @override
  List<AppUserProfile> get members => _members;
}

/// Widget-Test der Kassierer-Prüfung (P3.2) — Disclaimer + Verdachtshinweis.
void main() {
  const admin = AppUserProfile(
    uid: 'owner-1',
    orgId: 'org-1',
    email: 'owner@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Inhaber'),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  testWidgets('zeigt Disclaimer und markiert auffälligen Kassierer',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fs = FakeFirebaseFirestore();
    final now = DateTime.now();
    var seq = 0;

    Future<void> seedReceipt(String cashierId, bool refund) async {
      final r = PosReceipt(
        orgId: 'org-1',
        siteId: 'site-1',
        referenceNumber: 'r${seq++}',
        type: refund ? 'refund' : 'sales',
        isRevenue: true,
        transactionDate: now.subtract(const Duration(days: 1)),
        cashierId: cashierId,
      );
      await fs
          .collection('organizations')
          .doc('org-1')
          .collection('posReceipts')
          .doc('r$seq')
          .set(r.toFirestoreMap());
    }

    await fs
        .collection('organizations')
        .doc('org-1')
        .collection('products')
        .doc('p1')
        .set({
      'orgId': 'org-1',
      'siteId': 'site-1',
      'siteName': 'Strichmännchen',
      'name': 'p1',
      'nameLower': 'p1',
      'isActive': true,
    });

    await tester.runAsync(() async {
      // 5 unauffällige Kassierer (je 30 Verkäufe, 0 Erstattungen) + 1 Verdacht
      // (30 Vorgänge, 12 Erstattungen = 40 %). z des Verdachts ≈ 2,24 -> markiert.
      for (var k = 0; k < 5; k++) {
        for (var i = 0; i < 30; i++) {
          await seedReceipt('clean$k', false);
        }
      }
      for (var i = 0; i < 30; i++) {
        await seedReceipt('verdacht', i < 12);
      }
    });

    final service = FirestoreService(firestore: fs);
    final inventory = InventoryProvider(firestoreService: service);
    await tester.runAsync(() async {
      await inventory.updateSession(admin, localStorageOnly: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    final team = _FakeTeamProvider(
      const [
        AppUserProfile(
          uid: 'verdacht',
          orgId: 'org-1',
          email: 'max@laden.test',
          role: UserRole.employee,
          isActive: true,
          settings: UserSettings(name: 'Max Kassierer'),
        ),
      ],
      service,
    );
    final auth = FakeAuthProvider(firestoreService: service, profile: admin);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
          ChangeNotifierProvider<TeamProvider>.value(value: team),
        ],
        child: const MaterialApp(home: CashierAnomalyScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Kassierer-Prüfung'), findsOneWidget);
    expect(find.textContaining('Mitbestimmung'), findsOneWidget); // Disclaimer
    expect(find.textContaining('1 auffällig'), findsOneWidget);
    expect(find.text('Max Kassierer'), findsOneWidget); // Name aufgelöst
    expect(find.text('prüfen'), findsOneWidget);
  });
}
