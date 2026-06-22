import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/order_cart.dart';

void main() {
  SiteOrderList sample({OrderListKind kind = OrderListKind.cart}) {
    return SiteOrderList(
      id: 'site-1',
      orgId: 'org-1',
      siteId: 'site-1',
      siteName: 'Tabak Börse',
      kind: kind,
      items: const [
        OrderListItem(
          productId: 'p-1',
          name: 'Pueblo Tabak 30g',
          sku: 'PUE30',
          category: 'Drehtabak',
          unit: 'Beutel',
          quantity: 5,
          supplierId: 'sup-1',
          supplierName: 'Tabak Nord',
          addedByUid: 'peter',
          note: 'fast leer',
        ),
        OrderListItem(
          productId: 'p-2',
          name: 'Feuerzeug',
          unit: 'Stück',
          quantity: 12,
        ),
      ],
      updatedByUid: 'peter',
      updatedAt: DateTime(2026, 6, 21, 10, 30),
    );
  }

  group('OrderListKind', () {
    test('value/fromValue Round-Trip und Default', () {
      expect(OrderListKind.cart.value, 'cart');
      expect(OrderListKind.weeklyTemplate.value, 'weekly_template');
      expect(OrderListKindX.fromValue('weekly_template'),
          OrderListKind.weeklyTemplate);
      expect(OrderListKindX.fromValue('cart'), OrderListKind.cart);
      // Unbekannter/null-Wert faellt still auf cart zurueck (Default-Branch).
      expect(OrderListKindX.fromValue('quatsch'), OrderListKind.cart);
      expect(OrderListKindX.fromValue(null), OrderListKind.cart);
    });
  });

  group('SiteOrderList Helfer', () {
    test('itemCount/totalQuantity/itemForProduct', () {
      final list = sample();
      expect(list.itemCount, 2);
      expect(list.totalQuantity, 17);
      expect(list.isEmpty, isFalse);
      expect(list.itemForProduct('p-2')?.name, 'Feuerzeug');
      expect(list.itemForProduct('fehlt'), isNull);
      expect(list.itemForProduct(null), isNull);
    });
  });

  group('Dual-Serialisierung', () {
    test('snake_case Round-Trip (toMap/fromMap)', () {
      final list = sample(kind: OrderListKind.weeklyTemplate);
      final restored = SiteOrderList.fromMap(list.toMap());

      expect(restored.id, 'site-1');
      expect(restored.orgId, 'org-1');
      expect(restored.siteId, 'site-1');
      expect(restored.siteName, 'Tabak Börse');
      expect(restored.kind, OrderListKind.weeklyTemplate);
      expect(restored.updatedByUid, 'peter');
      expect(restored.updatedAt, DateTime(2026, 6, 21, 10, 30));
      expect(restored.items, hasLength(2));
      final first = restored.items.first;
      expect(first.productId, 'p-1');
      expect(first.name, 'Pueblo Tabak 30g');
      expect(first.sku, 'PUE30');
      expect(first.category, 'Drehtabak');
      expect(first.unit, 'Beutel');
      expect(first.quantity, 5);
      expect(first.supplierId, 'sup-1');
      expect(first.supplierName, 'Tabak Nord');
      expect(first.addedByUid, 'peter');
      expect(first.note, 'fast leer');
    });

    test('camelCase Round-Trip (toFirestoreMap/fromFirestore)', () {
      final list = sample();
      final map = list.toFirestoreMap();
      // Doc-ID wird separat geliefert (Firestore-Maps tragen die id nie).
      final restored = SiteOrderList.fromFirestore('site-1', map);

      expect(restored.id, 'site-1');
      expect(restored.orgId, 'org-1');
      expect(restored.siteId, 'site-1');
      expect(restored.kind, OrderListKind.cart);
      expect(restored.items, hasLength(2));
      expect(restored.items.first.quantity, 5);
      expect(restored.items.first.supplierName, 'Tabak Nord');
      expect(restored.items.last.unit, 'Stück');
    });

    test('siteId faellt in fromFirestore auf die Doc-ID zurueck', () {
      // Doc-ID = siteId (Singleton je Laden); fehlt siteId im Map, gilt die id.
      final restored = SiteOrderList.fromFirestore('site-7', {
        'orgId': 'org-1',
        'kind': 'cart',
        'items': const [],
      });
      expect(restored.siteId, 'site-7');
    });
  });

  group('copyWith', () {
    test('OrderListItem clear-Flags leeren nullable Felder', () {
      const item = OrderListItem(
        productId: 'p-1',
        name: 'Pueblo',
        sku: 'PUE',
        category: 'Drehtabak',
        unit: 'Beutel',
        quantity: 3,
        supplierId: 'sup-1',
        supplierName: 'Tabak Nord',
        note: 'fast leer',
      );
      final cleared = item.copyWith(
        clearSku: true,
        clearCategory: true,
        clearSupplier: true,
        clearNote: true,
      );
      expect(cleared.sku, isNull);
      expect(cleared.category, isNull);
      expect(cleared.supplierId, isNull);
      expect(cleared.supplierName, isNull);
      expect(cleared.note, isNull);
      // Unberuehrte Felder bleiben.
      expect(cleared.name, 'Pueblo');
      expect(cleared.quantity, 3);
    });

    test('SiteOrderList copyWith ersetzt Items und kind', () {
      final list = sample();
      final updated = list.copyWith(
        items: const [],
        kind: OrderListKind.weeklyTemplate,
      );
      expect(updated.isEmpty, isTrue);
      expect(updated.kind, OrderListKind.weeklyTemplate);
      expect(updated.siteName, 'Tabak Börse');
    });
  });
}
