import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/purchase_order.dart';
import 'package:worktime_app/models/stock_movement.dart';
import 'package:worktime_app/models/supplier.dart';

void main() {
  group('Supplier', () {
    test('round-trips through the local map', () {
      const supplier = Supplier(
        id: 'sup-1',
        orgId: 'org-1',
        name: 'Tabak Grosshandel Nord',
        contactPerson: 'Frau Meier',
        email: 'kontakt@thnord.de',
        orderEmail: 'bestellung@thnord.de',
        phone: '0431 12345',
        customerNumber: 'KD-9981',
        leadTimeDays: 2,
        notes: 'Liefert dienstags',
      );

      final restored = Supplier.fromMap(supplier.toMap());

      expect(restored.name, 'Tabak Grosshandel Nord');
      expect(restored.orderEmail, 'bestellung@thnord.de');
      expect(restored.customerNumber, 'KD-9981');
      expect(restored.leadTimeDays, 2);
    });

    test('effectiveOrderEmail falls back to the contact email', () {
      const withOrder = Supplier(
        orgId: 'o',
        name: 'A',
        email: 'a@x.de',
        orderEmail: 'order@x.de',
      );
      const withoutOrder = Supplier(orgId: 'o', name: 'A', email: 'a@x.de');
      const neither = Supplier(orgId: 'o', name: 'A');

      expect(withOrder.effectiveOrderEmail, 'order@x.de');
      expect(withoutOrder.effectiveOrderEmail, 'a@x.de');
      expect(neither.effectiveOrderEmail, isNull);
    });
  });

  group('Product', () {
    test('round-trips through the local map', () {
      const product = Product(
        id: 'prod-1',
        orgId: 'org-1',
        siteId: 'site-1',
        siteName: 'Strichmaennchen',
        name: 'Feuerzeug',
        sku: 'FZ-01',
        barcode: '4001234567890',
        category: 'Raucherbedarf',
        unit: 'Stück',
        supplierId: 'sup-1',
        supplierName: 'Nord',
        purchasePriceCents: 45,
        sellingPriceCents: 99,
        currentStock: 12,
        minStock: 10,
        targetStock: 40,
        reorderQuantity: 50,
      );

      final restored = Product.fromMap(product.toMap());

      expect(restored.name, 'Feuerzeug');
      expect(restored.barcode, '4001234567890');
      expect(restored.purchasePriceCents, 45);
      expect(restored.currentStock, 12);
      expect(restored.minStock, 10);
      expect(restored.targetStock, 40);
      expect(restored.reorderQuantity, 50);
    });

    test('needsReorder triggers at or below the minimum stock', () {
      const above =
          Product(orgId: 'o', siteId: 's', name: 'x', currentStock: 11, minStock: 10);
      const equal =
          Product(orgId: 'o', siteId: 's', name: 'x', currentStock: 10, minStock: 10);
      const below =
          Product(orgId: 'o', siteId: 's', name: 'x', currentStock: 3, minStock: 10);
      const noMin =
          Product(orgId: 'o', siteId: 's', name: 'x', currentStock: 0, minStock: 0);

      expect(above.needsReorder, isFalse);
      expect(equal.needsReorder, isTrue);
      expect(below.needsReorder, isTrue);
      expect(noMin.needsReorder, isFalse);
    });

    test('suggestedReorderQuantity prefers the explicit value', () {
      const explicit = Product(
        orgId: 'o',
        siteId: 's',
        name: 'x',
        currentStock: 2,
        minStock: 10,
        reorderQuantity: 30,
      );
      const derived = Product(
        orgId: 'o',
        siteId: 's',
        name: 'x',
        currentStock: 4,
        minStock: 10,
      );

      expect(explicit.suggestedReorderQuantity, 30);
      // target = 2 * minStock (20), delta = 20 - 4 = 16
      expect(derived.suggestedReorderQuantity, 16);
    });

    test('suggestedReorderQuantity nutzt den Zielbestand vor minStock*2', () {
      const withTarget = Product(
        orgId: 'o',
        siteId: 's',
        name: 'x',
        currentStock: 5,
        minStock: 5,
        targetStock: 20,
      );
      // Zielbestand 20 - Bestand 5 = 15 (statt minStock*2 - 5 = 5).
      expect(withTarget.suggestedReorderQuantity, 15);

      // Explizite Bestellmenge schlaegt den Zielbestand.
      expect(
        withTarget.copyWith(reorderQuantity: 8).suggestedReorderQuantity,
        8,
      );
      // Bereits ueber Zielbestand -> Mindestmenge 1.
      expect(
        withTarget.copyWith(currentStock: 25).suggestedReorderQuantity,
        1,
      );
    });

    test('Marge und Warenwert je Artikel', () {
      const p = Product(
        orgId: 'o',
        siteId: 's',
        name: 'x',
        purchasePriceCents: 100,
        sellingPriceCents: 150,
        currentStock: 4,
      );
      expect(p.marginCents, 50);
      expect(p.marginPercent, closeTo(50, 0.001));
      expect(p.stockValuePurchaseCents, 400); // 4 * 100
      expect(p.stockValueSellingCents, 600); // 4 * 150

      // Ohne Preis -> kein Wert, keine Marge.
      const noPrice = Product(orgId: 'o', siteId: 's', name: 'y', currentStock: 3);
      expect(noPrice.marginCents, isNull);
      expect(noPrice.stockValuePurchaseCents, 0);
    });
  });

  group('PurchaseOrderItem', () {
    test('computes outstanding quantity and line total', () {
      const item = PurchaseOrderItem(
        name: 'Feuerzeug',
        quantityOrdered: 50,
        quantityReceived: 20,
        unitPriceCents: 45,
      );

      expect(item.outstandingQuantity, 30);
      expect(item.isFullyReceived, isFalse);
      expect(item.lineTotalCents, 50 * 45);
    });

    test('outstanding never goes negative on over-delivery', () {
      const item = PurchaseOrderItem(
        name: 'x',
        quantityOrdered: 10,
        quantityReceived: 12,
      );
      expect(item.outstandingQuantity, 0);
      expect(item.isFullyReceived, isTrue);
    });
  });

  group('PurchaseOrder', () {
    PurchaseOrder buildOrder(PurchaseOrderStatus status) => PurchaseOrder(
          id: 'po-1',
          orgId: 'org-1',
          siteId: 'site-1',
          siteName: 'Strichmaennchen',
          supplierId: 'sup-1',
          supplierName: 'Nord',
          orderNumber: 'BST-2026-0001',
          status: status,
          items: const [
            PurchaseOrderItem(
              productId: 'p1',
              name: 'Feuerzeug',
              quantityOrdered: 50,
              quantityReceived: 0,
              unitPriceCents: 45,
            ),
            PurchaseOrderItem(
              productId: 'p2',
              name: 'Zeitschrift',
              quantityOrdered: 10,
              quantityReceived: 0,
              unitPriceCents: 200,
            ),
          ],
        );

    test('round-trips through the local map keeping items', () {
      final restored = PurchaseOrder.fromMap(
        buildOrder(PurchaseOrderStatus.ordered).toMap(),
      );

      expect(restored.orderNumber, 'BST-2026-0001');
      expect(restored.status, PurchaseOrderStatus.ordered);
      expect(restored.items.length, 2);
      expect(restored.items.first.name, 'Feuerzeug');
      expect(restored.totalCents, 50 * 45 + 10 * 200);
    });

    test('deriveReceiptStatus reflects delivered quantities', () {
      final ordered = buildOrder(PurchaseOrderStatus.ordered);
      expect(ordered.deriveReceiptStatus(), PurchaseOrderStatus.ordered);

      final partial = ordered.copyWith(
        items: [
          ordered.items[0].copyWith(quantityReceived: 20),
          ordered.items[1],
        ],
      );
      expect(
        partial.deriveReceiptStatus(),
        PurchaseOrderStatus.partiallyReceived,
      );

      final full = ordered.copyWith(
        items: [
          ordered.items[0].copyWith(quantityReceived: 50),
          ordered.items[1].copyWith(quantityReceived: 10),
        ],
      );
      expect(full.deriveReceiptStatus(), PurchaseOrderStatus.received);
    });

    test('deriveReceiptStatus leaves cancelled and draft untouched', () {
      expect(
        buildOrder(PurchaseOrderStatus.cancelled).deriveReceiptStatus(),
        PurchaseOrderStatus.cancelled,
      );
      expect(
        buildOrder(PurchaseOrderStatus.draft).deriveReceiptStatus(),
        PurchaseOrderStatus.draft,
      );
    });
  });

  group('StockMovement', () {
    test('round-trips type and delta through the local map', () {
      const movement = StockMovement(
        id: 'm1',
        orgId: 'org-1',
        siteId: 'site-1',
        productId: 'p1',
        productName: 'Feuerzeug',
        type: StockMovementType.receipt,
        quantityDelta: 50,
        balanceAfter: 62,
        reason: 'Wareneingang',
      );

      final restored = StockMovement.fromMap(movement.toMap());

      expect(restored.type, StockMovementType.receipt);
      expect(restored.quantityDelta, 50);
      expect(restored.balanceAfter, 62);
    });

    test('unknown type falls back to adjustment', () {
      expect(
        StockMovementTypeX.fromValue('nonsense'),
        StockMovementType.adjustment,
      );
    });
  });
}
