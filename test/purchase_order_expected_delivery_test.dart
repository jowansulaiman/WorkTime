import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/purchase_order.dart';

void main() {
  PurchaseOrder order({
    required PurchaseOrderStatus status,
    DateTime? expectedAt,
    DateTime? closedAt,
  }) =>
      PurchaseOrder(
        orgId: 'org-1',
        siteId: 'site-1',
        supplierId: 'sup-1',
        status: status,
        expectedAt: expectedAt,
        closedAt: closedAt,
        items: const [
          PurchaseOrderItem(name: 'X', quantityOrdered: 1),
        ],
      );

  final today = DateTime(2026, 7, 13, 9); // Referenztag mit Uhrzeit

  group('PurchaseOrder.isDeliveryPending (WW-3)', () {
    test('offen (ordered/partiallyReceived) mit Termin → true', () {
      expect(
        order(
                status: PurchaseOrderStatus.ordered,
                expectedAt: DateTime(2026, 7, 15))
            .isDeliveryPending,
        isTrue,
      );
      expect(
        order(
                status: PurchaseOrderStatus.partiallyReceived,
                expectedAt: DateTime(2026, 7, 15))
            .isDeliveryPending,
        isTrue,
      );
    });

    test('ohne Termin, Entwurf, geliefert, storniert, geschlossen → false', () {
      expect(order(status: PurchaseOrderStatus.ordered).isDeliveryPending,
          isFalse); // kein expectedAt
      expect(
        order(status: PurchaseOrderStatus.draft, expectedAt: DateTime(2026, 7, 15))
            .isDeliveryPending,
        isFalse,
      );
      expect(
        order(
                status: PurchaseOrderStatus.received,
                expectedAt: DateTime(2026, 7, 15))
            .isDeliveryPending,
        isFalse,
      );
      expect(
        order(
                status: PurchaseOrderStatus.cancelled,
                expectedAt: DateTime(2026, 7, 15))
            .isDeliveryPending,
        isFalse,
      );
      // geschlossen (closedAt gesetzt) trotz offenem Status → nicht mehr pending
      expect(
        order(
                status: PurchaseOrderStatus.ordered,
                expectedAt: DateTime(2026, 7, 15),
                closedAt: DateTime(2026, 7, 12))
            .isDeliveryPending,
        isFalse,
      );
    });
  });

  group('PurchaseOrder.expectedDeliveryState (WW-3)', () {
    test('heute = today, gestern = overdue, morgen = upcoming', () {
      expect(
        order(
                status: PurchaseOrderStatus.ordered,
                expectedAt: DateTime(2026, 7, 13))
            .expectedDeliveryState(today),
        ExpectedDeliveryDayState.today,
      );
      expect(
        order(
                status: PurchaseOrderStatus.ordered,
                expectedAt: DateTime(2026, 7, 12))
            .expectedDeliveryState(today),
        ExpectedDeliveryDayState.overdue,
      );
      expect(
        order(
                status: PurchaseOrderStatus.ordered,
                expectedAt: DateTime(2026, 7, 14))
            .expectedDeliveryState(today),
        ExpectedDeliveryDayState.upcoming,
      );
    });

    test('vergleicht nur Kalendertage, ignoriert Uhrzeit', () {
      // Termin heute um 06:00, Referenz heute 09:00 → immer noch „today".
      expect(
        order(
                status: PurchaseOrderStatus.ordered,
                expectedAt: DateTime(2026, 7, 13, 6))
            .expectedDeliveryState(today),
        ExpectedDeliveryDayState.today,
      );
    });

    test('nicht-pending → none', () {
      expect(
        order(status: PurchaseOrderStatus.received, expectedAt: DateTime(2026, 7, 12))
            .expectedDeliveryState(today),
        ExpectedDeliveryDayState.none,
      );
    });
  });
}
