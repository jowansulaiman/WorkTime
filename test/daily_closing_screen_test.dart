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

/// Widget-Test des Kassenabschluss-Screens (Kassen-Modul M3): Kassenzustand,
/// Zählung, Festschreiben, Buchen und die teamlead-Öffnung.
void main() {
  String today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  const admin = AppUserProfile(
    uid: 'owner-1',
    orgId: 'org-1',
    email: 'owner@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Inhaber'),
  );
  const teamlead = AppUserProfile(
    uid: 'lead-1',
    orgId: 'org-1',
    email: 'lea@laden.test',
    role: UserRole.teamlead,
    isActive: true,
    settings: UserSettings(name: 'Lea'),
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

  Future<
      ({
        FakeFirebaseFirestore fs,
        InventoryProvider inventory,
        FinanceProvider finance,
      })> seed(
    WidgetTester tester,
    AppUserProfile profile, {
    bool withReceiptToday = false,
  }) async {
    final fs = FakeFirebaseFirestore();
    if (withReceiptToday) {
      final receipt = PosReceipt(
        orgId: 'org-1',
        siteId: 'site-1',
        referenceNumber: 'B1',
        type: 'sales',
        isRevenue: true,
        businessDay: today(),
        transactionDate: DateTime.now().subtract(const Duration(minutes: 5)),
        grossCents: 1190,
        taxes: const [
          ReceiptTax(
              ratePercent: 19, netCents: 1000, taxCents: 190, grossCents: 1190),
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
    final finance = FinanceProvider(firestoreService: service);
    await tester.runAsync(() async {
      await inventory.updateSession(profile, localStorageOnly: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await finance.updateSession(profile, localStorageOnly: true);
      // Finanz-Stammdaten nur als Admin seeden (FinanceProvider ist admin-only).
      if (profile.isAdmin) {
        await finance.saveCostCenter(const CostCenter(
            orgId: 'org-1',
            number: '1001',
            name: 'Strichmännchen',
            siteId: 'site-1'));
        await finance.saveCostType(
            const CostType(orgId: 'org-1', number: '8400', name: 'Erlöse 19%'));
        await finance.saveCostType(const CostType(
            orgId: 'org-1', number: '6900', name: 'Kassendifferenz'));
      }
    });
    return (fs: fs, inventory: inventory, finance: finance);
  }

  Future<void> pump(
    WidgetTester tester, {
    required AppUserProfile profile,
    required InventoryProvider inventory,
    required FinanceProvider finance,
    required FirestoreService service,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final team = _FakeTeamProvider(
      const [SiteDefinition(orgId: 'org-1', id: 'site-1', name: 'Strichmännchen')],
      service,
    );
    final auth = FakeAuthProvider(firestoreService: service, profile: profile);
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
  }

  testWidgets('Kassenzustand unverankert → Aufforderung zum Zählen',
      (tester) async {
    final s = await seed(tester, admin);
    await pump(tester,
        profile: admin,
        inventory: s.inventory,
        finance: s.finance,
        service: FirestoreService(firestore: s.fs));

    expect(find.text('Kassenzustand'), findsOneWidget);
    expect(find.textContaining('bitte Kasse zählen'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Kasse zählen'), findsOneWidget);
  });

  testWidgets('Zählung erfassen persistiert CashCount und verankert das Soll',
      (tester) async {
    final s = await seed(tester, admin);
    await pump(tester,
        profile: admin,
        inventory: s.inventory,
        finance: s.finance,
        service: FirestoreService(firestore: s.fs));

    await tester.tap(find.widgetWithText(FilledButton, 'Kasse zählen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '200,00');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Zählung speichern'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    final counts = await s.inventory.loadCashCounts(siteId: 'site-1');
    expect(counts, hasLength(1));
    expect(counts.single.countedCents, 20000);
    expect(counts.single.source, 'manual');
    expect(find.textContaining('Rechnerischer Bargeldbestand'), findsOneWidget);
  });

  testWidgets('Abschließen schreibt fest, dann Buchen erzeugt Journalzeile',
      (tester) async {
    final s = await seed(tester, admin, withReceiptToday: true);
    await pump(tester,
        profile: admin,
        inventory: s.inventory,
        finance: s.finance,
        service: FirestoreService(firestore: s.fs));

    // Vor dem Abschluss steht "Tag abschließen".
    final closeBtn = find.widgetWithText(FilledButton, 'Tag abschließen');
    expect(closeBtn, findsOneWidget);
    await tester.tap(closeBtn);
    await tester.pumpAndSettle();
    // Bestätigungsdialog.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Abschließen'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    final closings = await s.inventory.loadCashClosings(siteId: 'site-1');
    expect(closings, hasLength(1));
    expect(find.text('festgeschrieben'), findsOneWidget);

    // Jetzt buchen.
    final bookBtn = find.widgetWithText(FilledButton, 'Ins Journal buchen');
    expect(bookBtn, findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(bookBtn);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    final posted = s.finance.journalEntries
        .where((e) => e.id == 'pos-${today()}-site-1-19');
    expect(posted, hasLength(1));
    expect(posted.single.amountCents, -1000);
    final booked = await s.inventory.loadCashClosings(siteId: 'site-1');
    expect(booked.single.bookedToFinance, isTrue);
  });

  testWidgets('Abschluss bettet die Tageszählung + Differenz ein', (tester) async {
    final s = await seed(tester, admin, withReceiptToday: true);
    await pump(tester,
        profile: admin,
        inventory: s.inventory,
        finance: s.finance,
        service: FirestoreService(firestore: s.fs));

    Future<void> zaehle(String betrag) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Kasse zählen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, betrag);
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Zählung speichern'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
    }

    // Erste Zählung verankert das Soll (250,00 €); ohne Bar-Bewegung bleibt es
    // dort. Zweite Zählung (249,00 €) vergleicht gegen dieses Soll → −1,00 €.
    await zaehle('250,00');
    await zaehle('249,00');

    // Dann abschließen — die jüngste Tageszählung wird eingebettet.
    await tester.tap(find.widgetWithText(FilledButton, 'Tag abschließen'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Abschließen'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    final closing =
        (await s.inventory.loadCashClosings(siteId: 'site-1')).single;
    expect(closing.cashCountedCents, 24900);
    expect(closing.cashExpectedCents, 25000);
    expect(closing.cashDifferenceCents, -100);
    expect(closing.cashCountId, isNotNull);

    // Buchen bucht den Umsatz UND die Kassendifferenz (M6, §8a).
    await tester.runAsync(() async {
      await tester
          .tap(find.widgetWithText(FilledButton, 'Ins Journal buchen'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    final diffEntry = s.finance.journalEntries
        .where((e) => e.id == 'pos-diff-${today()}-site-1');
    expect(diffEntry, hasLength(1));
    expect(diffEntry.single.amountCents, 100); // Fehlbetrag 1,00 € → Kosten
  });

  testWidgets('Teamleitung: darf zählen, aber nicht abschließen/buchen',
      (tester) async {
    final s = await seed(tester, teamlead, withReceiptToday: true);
    await pump(tester,
        profile: teamlead,
        inventory: s.inventory,
        finance: s.finance,
        service: FirestoreService(firestore: s.fs));

    expect(find.text('Kassenzustand'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Kasse zählen'), findsOneWidget);
    // Admin-Aktionen fehlen.
    expect(find.widgetWithText(FilledButton, 'Tag abschließen'), findsNothing);
    expect(find.text('Erlöskonten je USt-Satz'), findsNothing);
  });

  testWidgets('Mitarbeiter: kein Zugriff', (tester) async {
    final s = await seed(tester, employee);
    await pump(tester,
        profile: employee,
        inventory: s.inventory,
        finance: s.finance,
        service: FirestoreService(firestore: s.fs));

    expect(find.textContaining('Nur für Leitung/Admin'), findsOneWidget);
    expect(find.text('Kassenzustand'), findsNothing);
  });
}
