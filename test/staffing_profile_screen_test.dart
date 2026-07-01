import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/pos_receipt.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/screens/staffing_profile_screen.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

import 'support/router_harness.dart';

class _FakeTeamProvider extends TeamProvider {
  _FakeTeamProvider(this._fakeSites, FirestoreService service)
      : super(firestoreService: service);
  final List<SiteDefinition> _fakeSites;
  SiteDefinition? savedSite;
  @override
  List<SiteDefinition> get sites => _fakeSites;
  @override
  Future<void> saveSite(SiteDefinition site) async {
    savedSite = site;
  }
}

/// Widget-Test des Besetzungs-Profil-Screens (P3.1).
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

  testWidgets('zeigt Stoßzeiten-Vorschlag und Heatmap', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fs = FakeFirebaseFirestore();
    final now = DateTime.now();
    // 40 Belege um 16:00 an einem Tag innerhalb des 28-Tage-Fensters.
    final busy = DateTime(now.year, now.month, now.day, 16)
        .subtract(const Duration(days: 2));
    for (var i = 0; i < 40; i++) {
      final receipt = PosReceipt(
        orgId: 'org-1',
        siteId: 'site-1',
        referenceNumber: 'B$i',
        type: 'sales',
        isRevenue: true,
        transactionDate: busy.add(Duration(minutes: i)),
      );
      await fs
          .collection('organizations')
          .doc('org-1')
          .collection('posReceipts')
          .doc('B$i')
          .set(receipt.toFirestoreMap());
    }

    final service = FirestoreService(firestore: fs);
    final inventory = InventoryProvider(firestoreService: service);
    await tester.runAsync(() async {
      await inventory.updateSession(admin, localStorageOnly: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    final team = _FakeTeamProvider(
      const [SiteDefinition(orgId: 'org-1', id: 'site-1', name: 'Strichmännchen')],
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
        child: const MaterialApp(home: StaffingProfileScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Besetzungs-Profil'), findsOneWidget);
    expect(find.textContaining('Stoßzeiten'), findsOneWidget);
    expect(find.textContaining('Belege/Std'), findsWidgets);
    expect(find.textContaining('Kräfte'), findsWidgets); // 40/Std -> 2 Kräfte
    expect(find.textContaining('Heatmap'), findsOneWidget);

    // „übernehmen" schreibt den Bedarf in den StaffingDemand des Standorts.
    final applyBtn = find.widgetWithText(TextButton, 'übernehmen').first;
    await tester.runAsync(() async {
      await tester.tap(applyBtn);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(team.savedSite, isNotNull);
    expect(team.savedSite!.staffingDemands, isNotEmpty);
    expect(team.savedSite!.staffingDemands.first.requiredCount, 2);
  });
}
