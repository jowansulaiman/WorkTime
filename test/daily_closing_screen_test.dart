import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/finance_models.dart';
import 'package:worktime_app/models/pos_receipt.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/finance_provider.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/screens/daily_closing_screen.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

import 'support/router_harness.dart';

class _FakeTeamProvider extends TeamProvider {
  _FakeTeamProvider(this._fakeSites, FirestoreService service)
      : super(firestoreService: service);
  final List<SiteDefinition> _fakeSites;
  @override
  List<SiteDefinition> get sites => _fakeSites;
}

/// Widget-Test des Tagesabschluss-Screens (P2.0) inkl. Buchung.
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

  testWidgets('zeigt Tagesabschluss und bucht je USt-Satz', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fs = FakeFirebaseFirestore();
    final now = DateTime.now();
    final receipt = PosReceipt(
      orgId: 'org-1',
      siteId: 'site-1',
      referenceNumber: 'B1',
      type: 'sales',
      isRevenue: true,
      businessDay: '2026-06-29',
      transactionDate: now.subtract(const Duration(days: 1)),
      grossCents: 1190,
      taxes: const [
        ReceiptTax(ratePercent: 19, netCents: 1000, taxCents: 190, grossCents: 1190),
      ],
    );
    await fs
        .collection('organizations')
        .doc('org-1')
        .collection('posReceipts')
        .doc('B1')
        .set(receipt.toFirestoreMap());

    final service = FirestoreService(firestore: fs);
    final inventory = InventoryProvider(firestoreService: service);
    final finance = FinanceProvider(firestoreService: service);

    await tester.runAsync(() async {
      await inventory.updateSession(admin, localStorageOnly: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await finance.updateSession(admin, localStorageOnly: true);
      await finance.saveCostCenter(const CostCenter(
          orgId: 'org-1', number: '1001', name: 'Strichmännchen', siteId: 'site-1'));
      await finance.saveCostType(
          const CostType(orgId: 'org-1', number: '8400', name: 'Erlöse 19%'));
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
          ChangeNotifierProvider<FinanceProvider>.value(value: finance),
          ChangeNotifierProvider<TeamProvider>.value(value: team),
        ],
        child: const MaterialApp(home: DailyClosingScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Tagesabschluss (Kasse)'), findsOneWidget);
    expect(find.text('Erlöskonten je USt-Satz'), findsOneWidget);
    expect(find.textContaining('2026-06-29'), findsWidgets);
    final bookBtn = find.widgetWithText(FilledButton, 'Buchen');
    expect(bookBtn, findsOneWidget);

    // Rate 19% ist per Namens-Match vorbelegt -> Buchung läuft direkt.
    await tester.runAsync(() async {
      await tester.tap(bookBtn);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    final posted =
        finance.journalEntries.where((e) => e.id == 'pos-2026-06-29-site-1-19');
    expect(posted, hasLength(1));
    expect(posted.single.amountCents, -1000); // netto, Erlös = negativ
  });
}
