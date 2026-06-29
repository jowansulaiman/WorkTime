import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/purchase_order.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  const user = AppUserProfile(
    uid: 'owner-1',
    orgId: 'org-1',
    email: 'owner@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Inhaber'),
  );

  late FakeFirebaseFirestore firestore;
  late FirestoreService firestoreService;

  InventoryProvider newLocalProvider() => InventoryProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    firestore = FakeFirebaseFirestore();
    firestoreService = FirestoreService(firestore: firestore);
  });

  Future<Map<String, String>> seedProducts(
    InventoryProvider provider,
    List<String> names,
  ) async {
    for (final name in names) {
      await provider.saveProduct(
        Product(orgId: 'org-1', siteId: 'site-1', name: name),
      );
    }
    return {for (final p in provider.products) p.name: p.id!};
  }

  Future<void> saveOrder(
    InventoryProvider provider,
    Map<String, String> ids,
    List<String> names, {
    PurchaseOrderStatus status = PurchaseOrderStatus.ordered,
    DateTime? when,
  }) {
    return provider.savePurchaseOrder(
      PurchaseOrder(
        orgId: 'org-1',
        siteId: 'site-1',
        supplierId: 'sup-1',
        status: status,
        orderedAt: when ?? DateTime.now(),
        items: [
          for (final name in names)
            PurchaseOrderItem(
              productId: ids[name],
              name: name,
              quantityOrdered: 1,
            ),
        ],
      ),
    );
  }

  test('orderFrequencyByProduct zählt nicht stornierte Bestellungen je Artikel',
      () async {
    final provider = newLocalProvider();
    await provider.updateSession(user);
    final ids = await seedProducts(provider, ['Cola', 'Wasser', 'Chips']);
    final now = DateTime.now();

    await saveOrder(provider, ids, ['Cola', 'Wasser'], when: now);
    await saveOrder(provider, ids, ['Cola'], when: now);
    await saveOrder(provider, ids, ['Cola', 'Chips'], when: now);
    await saveOrder(provider, ids, ['Wasser'],
        status: PurchaseOrderStatus.cancelled, when: now);

    final freq = provider.orderFrequencyByProduct(now: now);
    expect(freq[ids['Cola']], 3);
    expect(freq[ids['Wasser']], 1); // storniert zählt nicht
    expect(freq[ids['Chips']], 1);
    expect(provider.orderFrequencyFor(ids['Cola']!), 3);
  });

  test('orderFrequencyByProduct ignoriert Bestellungen außerhalb des Fensters',
      () async {
    final provider = newLocalProvider();
    await provider.updateSession(user);
    final ids = await seedProducts(provider, ['Cola']);
    final now = DateTime(2026, 6, 24);

    await saveOrder(provider, ids, ['Cola'],
        when: now.subtract(const Duration(days: 10)));
    await saveOrder(provider, ids, ['Cola'],
        when: now.subtract(const Duration(days: 200)));

    final freq = provider.orderFrequencyByProduct(now: now);
    expect(freq[ids['Cola']], 1); // 200 Tage liegen außerhalb der ~12 Wochen
  });

  test('sortByOrderFrequency sortiert häufige zuerst, dann nach Name', () async {
    final provider = newLocalProvider();
    await provider.updateSession(user);
    final ids = await seedProducts(provider, ['Cola', 'Wasser', 'Apfel']);

    await saveOrder(provider, ids, ['Wasser']);
    await saveOrder(provider, ids, ['Wasser']);
    await saveOrder(provider, ids, ['Cola']);
    // 'Apfel' wurde nie bestellt -> ans Ende, nach Name.

    final sorted = provider.sortByOrderFrequency(provider.products);
    expect(sorted.map((p) => p.name).toList(), ['Wasser', 'Cola', 'Apfel']);
  });

  test('frequentlyOrderedProducts liefert nur Bestelltes, gekappt auf limit',
      () async {
    final provider = newLocalProvider();
    await provider.updateSession(user);
    final ids = await seedProducts(provider, ['Cola', 'Wasser', 'Apfel']);

    await saveOrder(provider, ids, ['Wasser']);
    await saveOrder(provider, ids, ['Wasser']);
    await saveOrder(provider, ids, ['Cola']);

    expect(
      provider.frequentlyOrderedProducts(limit: 1).map((p) => p.name).toList(),
      ['Wasser'],
    );
    // limit 0 = alle bestellten; 'Apfel' (0×) bleibt draußen.
    expect(
      provider.frequentlyOrderedProducts(limit: 0).map((p) => p.name).toList(),
      ['Wasser', 'Cola'],
    );
  });
}
