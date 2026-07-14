import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/inventory_count_session.dart';

void main() {
  group('InventoryCountStatus', () {
    test('value/fromValue round-trip + Default', () {
      for (final s in InventoryCountStatus.values) {
        expect(InventoryCountStatus.fromValue(s.value), s);
      }
      expect(InventoryCountStatus.fromValue('unbekannt'),
          InventoryCountStatus.open);
      expect(InventoryCountStatus.fromValue(null), InventoryCountStatus.open);
    });
  });

  group('InventoryCountEvent Serialisierung', () {
    final event = InventoryCountEvent(
      id: 'line-1',
      productId: 'p-1',
      productName: 'Cola',
      countedQuantity: 14,
      stockAtCount: 12,
      countedAt: DateTime(2026, 7, 14, 10, 30),
      countedByUid: 'u-1',
      countedByLabel: 'Peter',
      bookedAt: DateTime(2026, 7, 14, 18),
    );

    test('toMap/fromMap (snake_case, lokal) round-trip', () {
      final restored = InventoryCountEvent.fromMap(event.toMap());
      expect(restored.id, 'line-1');
      expect(restored.productId, 'p-1');
      expect(restored.countedQuantity, 14);
      expect(restored.stockAtCount, 12);
      expect(restored.countedByUid, 'u-1');
      expect(restored.countedByLabel, 'Peter');
      expect(restored.countedAt, event.countedAt);
      expect(restored.bookedAt, event.bookedAt);
      expect(restored.isBooked, isTrue);
    });

    test('toFirestoreMap/fromFirestore (camelCase, Timestamp) round-trip', () {
      final map = event.toFirestoreMap();
      expect(map['countedAt'], isA<Timestamp>());
      final restored = InventoryCountEvent.fromFirestore('line-9', map);
      expect(restored.id, 'line-9'); // ID kommt als separates Argument
      expect(restored.countedQuantity, 14);
      expect(restored.countedAt, event.countedAt);
      expect(restored.bookedAt, event.bookedAt);
    });

    test('clearBookedAt leert das Feld', () {
      expect(event.copyWith(clearBookedAt: true).bookedAt, isNull);
    });
  });

  group('InventoryCountSession Serialisierung', () {
    final session = InventoryCountSession(
      id: 's-1',
      orgId: 'org-1',
      siteId: 'site-1',
      title: 'Sommerinventur',
      status: InventoryCountStatus.completed,
      categoryFilter: 'Getränke',
      startedAt: DateTime(2026, 7, 14, 8),
      startedByUid: 'u-1',
      startedByLabel: 'Chef',
      completedAt: DateTime(2026, 7, 14, 20),
      completedByUid: 'u-1',
      totalProducts: 100,
      countedProducts: 98,
      resolvedCounts: const {'p-3': 'line-7'},
      diffSummary: const [
        InventoryCountDiff(
          productId: 'p-3',
          productName: 'Bier',
          countedQuantity: 20,
          previousStock: 24,
          unitCostCents: 80,
          decision: 'verrechnet',
        ),
      ],
    );

    test('toMap/fromMap round-trip inkl. resolvedCounts + diffSummary', () {
      final restored = InventoryCountSession.fromMap(session.toMap());
      expect(restored.title, 'Sommerinventur');
      expect(restored.status, InventoryCountStatus.completed);
      expect(restored.categoryFilter, 'Getränke');
      expect(restored.resolvedCounts, {'p-3': 'line-7'});
      expect(restored.diffSummary.single.delta, -4);
      expect(restored.diffSummary.single.valuationDeltaCents, -320);
      expect(restored.diffSummary.single.decision, 'verrechnet');
    });

    test('toFirestoreMap/fromFirestore round-trip', () {
      final map = session.toFirestoreMap();
      expect(map['startedAt'], isA<Timestamp>());
      final restored = InventoryCountSession.fromFirestore('s-9', map);
      expect(restored.id, 's-9');
      expect(restored.totalProducts, 100);
      expect(restored.countedProducts, 98);
      expect(restored.resolvedCounts, {'p-3': 'line-7'});
      expect(restored.diffSummary.single.previousStock, 24);
    });

    test('progress: 98/100', () {
      expect(session.progress, closeTo(0.98, 0.001));
    });
  });
}
