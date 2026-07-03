import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/payroll_record.dart';
import 'package:worktime_app/models/pos_receipt.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/personal_provider.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/feature_flag_provider.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/screens/kassenbericht_screen.dart';
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

class _FakePersonalProvider extends PersonalProvider {
  _FakePersonalProvider(this._fakePayrolls, FirestoreService service)
      : super(firestoreService: service, disableAuthentication: true);
  final List<PayrollRecord> _fakePayrolls;
  @override
  List<PayrollRecord> get payrollRecords => _fakePayrolls;
}

/// Widget-Test des Kassenbericht-Screens (Kassen-Modul M4).
void main() {
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    await initializeDateFormatting('de_DE');
  });

  String day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> pump(WidgetTester tester, AppUserProfile profile,
      {bool withData = true, List<PayrollRecord> payrolls = const []}) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fs = FakeFirebaseFirestore();
    if (withData) {
      final now = DateTime.now().subtract(const Duration(minutes: 5));
      final receipt = PosReceipt(
        orgId: 'org-1',
        siteId: 'site-1',
        referenceNumber: 'B1',
        type: 'sales',
        isRevenue: true,
        businessDay: day(now),
        transactionDate: now,
        grossCents: 11900,
        taxes: const [
          ReceiptTax(
              ratePercent: 19, netCents: 10000, taxCents: 1900,
              grossCents: 11900),
        ],
      );
      await fs
          .collection('organizations')
          .doc('org-1')
          .collection('posReceipts')
          .doc('B1')
          .set(receipt.toFirestoreMap());
    }

    final service = FirestoreService(firestore: fs);
    final inventory = InventoryProvider(firestoreService: service);
    final flags = FeatureFlagProvider(firestoreService: service);
    await tester.runAsync(() async {
      await inventory.updateSession(profile, localStorageOnly: false);
      await flags.updateSession(profile, localStorageOnly: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    final team = _FakeTeamProvider(
      const [SiteDefinition(orgId: 'org-1', id: 'site-1', name: 'Strichmännchen')],
      service,
    );
    final auth = FakeAuthProvider(firestoreService: service, profile: profile);
    final personal = _FakePersonalProvider(payrolls, service);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
          ChangeNotifierProvider<FeatureFlagProvider>.value(value: flags),
          ChangeNotifierProvider<TeamProvider>.value(value: team),
          ChangeNotifierProvider<PersonalProvider>.value(value: personal),
        ],
        child: const MaterialApp(home: KassenberichtScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('Admin: zeigt KPIs, Diagramm und Richtwert-Banner', (tester) async {
    await pump(tester, admin);

    expect(find.text('Kassenbericht'), findsOneWidget);
    expect(find.textContaining('Richtwert'), findsOneWidget);
    expect(find.text('Umsatz brutto'), findsOneWidget);
    expect(find.text('Rohertrag netto'), findsOneWidget);
    // Umsatz brutto 119,00 € erscheint (KPI-Karte).
    expect(find.textContaining('119,00'), findsWidgets);
  });

  testWidgets('Segmentwechsel auf Jahr: leere Altperioden zeigen neutralen '
      'Hinweis (kein „Server-Update"-Versprechen)', (tester) async {
    await pump(tester, admin);

    await tester.tap(find.text('Jahr'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Nur eine Beleg-heute → Vorjahres-Buckets leer → neutraler Hinweis.
    expect(find.textContaining('Für ältere Zeiträume'), findsOneWidget);
    expect(find.textContaining('Server-Update'), findsNothing);
  });

  testWidgets('leerer Zeitraum: Handlungsaufforderung statt stiller 0',
      (tester) async {
    await pump(tester, admin, withData: false);
    expect(find.textContaining('Noch keine Kassendaten'), findsOneWidget);
  });

  testWidgets('Mitarbeiter: kein Zugriff', (tester) async {
    await pump(tester, employee);
    expect(find.textContaining('Nur für Administratoren'), findsOneWidget);
    expect(find.text('Umsatz brutto'), findsNothing);
  });

  testWidgets('Lohnquote-Karte erscheint auf Monat mit Personalkosten (M6-D)',
      (tester) async {
    final now = DateTime.now();
    await pump(tester, admin, payrolls: [
      PayrollRecord(
        orgId: 'org-1',
        userId: 'u1',
        periodYear: now.year,
        periodMonth: now.month,
        employerTotalCents: 30000,
        status: PayrollStatus.freigegeben,
      ),
    ]);

    // Auf Woche (Default) ist die Karte nicht sichtbar.
    expect(find.textContaining('Lohnquote'), findsNothing);

    await tester.tap(find.text('Monat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Lohnquote & Betriebsergebnis'), findsOneWidget);
    expect(find.text('Personalkosten (AG-gesamt)'), findsOneWidget);
    // 30000/… Umsatz-brutto → Quote in %, Betriebsergebnis-Zeile vorhanden.
    expect(find.text('Betriebsergebnis'), findsOneWidget);
  });
}
