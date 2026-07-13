import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/purchase_order.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/screens/purchase_order_screens.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const admin = AppUserProfile(
    uid: 'owner-1',
    orgId: 'org-1',
    email: 'owner@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Inhaber'),
  );

  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  Future<({InventoryProvider inventory, String orderId})> seedOrder(
    PurchaseOrder order,
  ) async {
    final service = FirestoreService(firestore: FakeFirebaseFirestore());
    final inventory = InventoryProvider(
      firestoreService: service,
      disableAuthentication: true,
    );
    addTearDown(inventory.dispose);
    await inventory.updateSession(admin);
    final orderId = await inventory.savePurchaseOrder(order);
    return (inventory: inventory, orderId: orderId);
  }

  Future<void> pumpDetail(
    WidgetTester tester, {
    required InventoryProvider inventory,
    required String orderId,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<InventoryProvider>.value(
        value: inventory,
        child: MaterialApp(
          home: PurchaseOrderDetailScreen(
            orderId: orderId,
            sites: const [],
            canManage: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Rest schließen verlangt einen Grund und aktualisiert das Bestelldetail',
    (tester) async {
      final (:inventory, :orderId) = await seedOrder(
        const PurchaseOrder(
          orgId: 'org-1',
          siteId: 'site-1',
          supplierId: 'sup-1',
          supplierName: 'Großhandel',
          status: PurchaseOrderStatus.partiallyReceived,
          items: [
            PurchaseOrderItem(
              name: 'Feuerzeuge',
              quantityOrdered: 10,
              quantityReceived: 4,
              unitPriceCents: 25,
            ),
          ],
        ),
      );
      await pumpDetail(
        tester,
        inventory: inventory,
        orderId: orderId,
      );

      expect(find.text('Wareneingang'), findsOneWidget);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Rest schließen'), findsOneWidget);

      await tester.tap(find.text('Rest schließen'));
      await tester.pumpAndSettle();

      expect(find.text('Restmenge schließen?'), findsOneWidget);
      expect(find.text('6 Stück offen'), findsOneWidget);
      final submit = find.byKey(const Key('close_purchase_order_submit'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      final reason = find.byKey(const Key('close_purchase_order_reason'));
      await tester.enterText(reason, '   ');
      await tester.pump();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      await tester.enterText(reason, '  Rest nicht mehr lieferbar  ');
      await tester.pump();
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

      await tester.tap(submit);
      await tester.pumpAndSettle();

      final closed = inventory.purchaseOrders.single;
      expect(closed.status, PurchaseOrderStatus.received);
      expect(closed.closedAt, isNotNull);
      expect(closed.closedReason, 'Rest nicht mehr lieferbar');
      expect(find.textContaining('Rest geschlossen am'), findsOneWidget);
      expect(
        find.text('Begründung: Rest nicht mehr lieferbar'),
        findsOneWidget,
      );
      expect(find.text('Geliefert (EK)'), findsOneWidget);
      expect(find.text('1,00 €'), findsOneWidget);
      expect(find.text('Wareneingang'), findsNothing);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Wareneingang buchen'), findsNothing);
      expect(find.text('Rest schließen'), findsNothing);
    },
  );

  testWidgets(
    'closedAt blendet Wareneingang auch bei inkonsistentem Teilstatus aus',
    (tester) async {
      final (:inventory, :orderId) = await seedOrder(
        PurchaseOrder(
          orgId: 'org-1',
          siteId: 'site-1',
          supplierId: 'sup-1',
          status: PurchaseOrderStatus.partiallyReceived,
          closedAt: DateTime(2026, 7, 13, 14, 30),
          closedReason: 'Altbestand geschlossen',
          items: const [
            PurchaseOrderItem(
              name: 'Papier',
              quantityOrdered: 10,
              quantityReceived: 2,
              unitPriceCents: 50,
            ),
          ],
        ),
      );
      await pumpDetail(
        tester,
        inventory: inventory,
        orderId: orderId,
      );

      expect(find.text('Wareneingang'), findsNothing);
      expect(find.text('Rest geschlossen am 13.07.2026'), findsOneWidget);
      expect(find.text('Begründung: Altbestand geschlossen'), findsOneWidget);
      expect(find.text('Geliefert (EK)'), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Wareneingang buchen'), findsNothing);
      expect(find.text('Rest schließen'), findsNothing);
    },
  );
}
