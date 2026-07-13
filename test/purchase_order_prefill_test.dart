import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/purchase_order.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/supplier.dart';
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  testWidgets('Bestell-Prefill zieht bereits unterwegs befindliche Mengen ab', (
    tester,
  ) async {
    final service = FirestoreService(firestore: FakeFirebaseFirestore());
    final inventory = InventoryProvider(
      firestoreService: service,
      disableAuthentication: true,
    );
    await inventory.updateSession(admin);
    await inventory.saveSupplier(
      const Supplier(orgId: 'org-1', name: 'Großhandel'),
    );
    final supplierId = inventory.suppliers.single.id!;

    for (final product in [
      Product(
        orgId: 'org-1',
        siteId: 'site-1',
        name: 'Teilgedeckt',
        supplierId: supplierId,
        currentStock: 1,
        minStock: 5,
        targetStock: 10,
      ),
      Product(
        orgId: 'org-1',
        siteId: 'site-1',
        name: 'Voll gedeckt',
        supplierId: supplierId,
        currentStock: 1,
        minStock: 5,
        targetStock: 10,
      ),
    ]) {
      await inventory.saveProduct(product);
    }
    final partialId =
        inventory.products
            .firstWhere((product) => product.name == 'Teilgedeckt')
            .id!;
    final coveredId =
        inventory.products
            .firstWhere((product) => product.name == 'Voll gedeckt')
            .id!;
    await inventory.savePurchaseOrder(
      PurchaseOrder(
        orgId: 'org-1',
        siteId: 'site-1',
        supplierId: supplierId,
        status: PurchaseOrderStatus.ordered,
        items: [
          PurchaseOrderItem(
            productId: partialId,
            name: 'Teilgedeckt',
            quantityOrdered: 3,
          ),
          PurchaseOrderItem(
            productId: coveredId,
            name: 'Voll gedeckt',
            quantityOrdered: 5,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<InventoryProvider>.value(
        value: inventory,
        child: const MaterialApp(
          home: PurchaseOrderEditorScreen(
            sites: [
              SiteDefinition(id: 'site-1', orgId: 'org-1', name: 'Laden 1'),
            ],
            initialSiteId: 'site-1',
            prefillReorder: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Großhandel').last);
    await tester.pumpAndSettle();

    final partialCard = find.ancestor(
      of: find.text('Teilgedeckt'),
      matching: find.byType(Card),
    );
    final coveredCard = find.ancestor(
      of: find.text('Voll gedeckt'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: partialCard, matching: find.text('6')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: coveredCard, matching: find.text('0')),
      findsOneWidget,
    );
    expect(find.text('Bestellen (1)'), findsOneWidget);
  });
}
