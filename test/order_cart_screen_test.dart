import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/order_cart.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/screens/order_cart_screen.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/theme/app_theme.dart';

/// Seam-Provider (Subklasse statt Mockito, wie im Projekt üblich): macht
/// checkoutCart aufhaltbar (Completer) und zählt saveWeeklyList-Aufrufe.
class _SeamInventoryProvider extends InventoryProvider {
  _SeamInventoryProvider({
    required super.firestoreService,
    super.disableAuthentication,
  });

  int checkoutCalls = 0;
  Completer<List<String>>? checkoutGate;
  int saveWeeklyCalls = 0;
  SiteOrderList? lastSavedWeekly;

  @override
  Future<List<String>> checkoutCart(String siteId) {
    checkoutCalls++;
    final gate = checkoutGate;
    if (gate != null) {
      return gate.future;
    }
    return super.checkoutCart(siteId);
  }

  @override
  Future<void> saveWeeklyList(SiteOrderList list) async {
    saveWeeklyCalls++;
    lastSavedWeekly = list;
    await super.saveWeeklyList(list);
  }
}

const _user = AppUserProfile(
  uid: 'owner-1',
  orgId: 'org-1',
  email: 'owner@laden.test',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Inhaber'),
);

/// #68: Widget-Tests für die Geld-/Bestell-relevanten Korb-Aktionen: die
/// in-flight-Sperre des Bestellen-Buttons (checkoutCart ist nicht idempotent —
/// ein Doppel-Tap darf keine zweite Bestellung auslösen) und der
/// Speichern-Pfad des Wochenlisten-Editors.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SeamInventoryProvider provider;

  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    provider = _SeamInventoryProvider(
      firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      disableAuthentication: true,
    );
    addTearDown(provider.dispose);
    await provider.updateSession(_user);
  });

  Future<void> pumpCartTab(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<InventoryProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.resolveLight(useV2: true),
          home: Scaffold(
            body: OrderCartTab(
              siteId: 'site-1',
              canManage: true,
              sites: const [],
              onCheckoutDone: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
      'Bestellen-Button sperrt sich waehrend des Checkouts — Doppel-Tap '
      'loest checkoutCart nur einmal aus', (tester) async {
    await provider.addToCart(
      product: const Product(
        id: 'p-1',
        orgId: 'org-1',
        siteId: 'site-1',
        siteName: 'Tabak Börse',
        name: 'Pueblo',
        unit: 'Stück',
      ),
      quantity: 2,
    );
    provider.checkoutGate = Completer<List<String>>();

    await pumpCartTab(tester);
    expect(find.text('Bestellen (1 Position)'), findsOneWidget);

    // Erster Tap: oeffnet den Bestaetigungs-Dialog, Button wird busy.
    // (kein pumpAndSettle: der Busy-Spinner animiert endlos)
    await tester.tap(find.text('Bestellen (1 Position)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Bestellen')); // Dialog bestaetigen
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(provider.checkoutCalls, 1);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.byType(CircularProgressIndicator),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull,
        reason: 'waehrend des laufenden Checkouts muss der Button gesperrt '
            'sein (checkoutCart ist nicht idempotent)');

    // Zweiter Tap waehrend in-flight: darf nichts ausloesen.
    await tester.tap(
      find.byType(CircularProgressIndicator),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(provider.checkoutCalls, 1);

    // Checkout abschliessen -> Button wieder frei.
    provider.checkoutGate!.complete(const ['order-1']);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5)); // SnackBar-Dauer abwarten
    expect(provider.checkoutCalls, 1);
  });

  testWidgets(
      'WeeklyOrderListEditorScreen: Speichern ruft saveWeeklyList mit den '
      'aktuellen Positionen', (tester) async {
    await provider.saveWeeklyList(
      const SiteOrderList(
        orgId: 'org-1',
        siteId: 'site-1',
        kind: OrderListKind.weeklyTemplate,
        items: [
          OrderListItem(productId: 'p-1', name: 'Pueblo', quantity: 10),
        ],
      ),
    );
    provider.saveWeeklyCalls = 0;

    await tester.pumpWidget(
      ChangeNotifierProvider<InventoryProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.resolveLight(useV2: true),
          home: const WeeklyOrderListEditorScreen(
            siteId: 'site-1',
            siteName: 'Tabak Börse',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Pueblo'), findsOneWidget);

    await tester.tap(find.text('Speichern'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(provider.saveWeeklyCalls, 1);
    expect(provider.lastSavedWeekly!.kind, OrderListKind.weeklyTemplate);
    expect(provider.lastSavedWeekly!.items.single.productId, 'p-1');
    expect(provider.lastSavedWeekly!.items.single.quantity, 10);
  });
}
