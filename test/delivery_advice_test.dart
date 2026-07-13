import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/delivery_advice.dart';

void main() {
  final advice = DeliveryAdvice(
    id: 'da-1',
    orgId: 'org-1',
    siteId: 'site-1',
    siteName: 'Strichmännchen',
    supplierId: 'sup-1',
    supplierName: 'Großhandel',
    purchaseOrderId: 'po-9',
    reference: 'AVIS-42',
    status: DeliveryAdviceStatus.announced,
    expectedDate: DateTime(2026, 7, 15, 8), // wird auf 12:00 normalisiert
    items: const [
      DeliveryAdviceItem(
        productId: 'p-1',
        name: 'Cola 0,33l',
        sku: 'C33',
        unit: 'Stk.',
        announcedQuantity: 24,
        note: 'Palette',
      ),
    ],
    notes: 'kommt morgens',
    createdByUid: 'admin-1',
  );

  group('DeliveryAdvice Serialisierung', () {
    test('normalizeDay → 12:00; expectedDay unabhängig von der Uhrzeit', () {
      // Der Provider normalisiert vor dem Konstruieren (Muster ProductBatch);
      // das Model speichert roh, expectedDay kappt die Uhrzeit ohnehin.
      expect(DeliveryAdvice.normalizeDay(DateTime(2026, 7, 15, 8)),
          DateTime(2026, 7, 15, 12));
      expect(advice.expectedDay, '2026-07-15');
    });

    test('camelCase round-trippt (toFirestoreMap/fromFirestore)', () {
      final map = advice.toFirestoreMap();
      expect(map['status'], 'announced');
      final restored = DeliveryAdvice.fromFirestore('da-1', map);
      expect(restored.id, 'da-1');
      expect(restored.siteId, 'site-1');
      expect(restored.supplierName, 'Großhandel');
      expect(restored.purchaseOrderId, 'po-9');
      expect(restored.status, DeliveryAdviceStatus.announced);
      expect(restored.expectedDay, '2026-07-15');
      expect(restored.items.single.announcedQuantity, 24);
      expect(restored.items.single.name, 'Cola 0,33l');
    });

    test('snake_case round-trippt (toMap/fromMap)', () {
      final restored = DeliveryAdvice.fromMap(advice.toMap());
      expect(restored.siteId, 'site-1');
      expect(restored.reference, 'AVIS-42');
      expect(restored.status, DeliveryAdviceStatus.announced);
      expect(restored.items.single.sku, 'C33');
      expect(restored.notes, 'kommt morgens');
    });

    test('Status-Enum: value/fromValue/Default + isOpen', () {
      expect(DeliveryAdviceStatus.received.value, 'received');
      expect(DeliveryAdviceStatus.cancelled.value, 'cancelled');
      expect(DeliveryAdviceStatus.fromValue('received'),
          DeliveryAdviceStatus.received);
      expect(DeliveryAdviceStatus.fromValue('zzz'),
          DeliveryAdviceStatus.announced);
      expect(DeliveryAdviceStatus.fromValue(null),
          DeliveryAdviceStatus.announced);
      expect(DeliveryAdviceStatus.announced.isOpen, isTrue);
      expect(DeliveryAdviceStatus.received.isOpen, isFalse);
    });

    test('copyWith clearX-Flags', () {
      final withReceipt = advice.copyWith(
        status: DeliveryAdviceStatus.received,
        receivedAt: DateTime(2026, 7, 15, 9),
      );
      expect(withReceipt.status, DeliveryAdviceStatus.received);
      expect(withReceipt.receivedAt, isNotNull);
      final cleared = withReceipt.copyWith(clearReceivedAt: true);
      expect(cleared.receivedAt, isNull);
    });
  });
}
