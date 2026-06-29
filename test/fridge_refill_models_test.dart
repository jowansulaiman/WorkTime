import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/fridge_refill.dart';

void main() {
  FridgeRefillList sample() {
    return FridgeRefillList(
      id: 'site-1',
      orgId: 'org-1',
      siteId: 'site-1',
      siteName: 'Tabak Börse',
      items: [
        FridgeRefillItem(
          id: 'i-1',
          productId: 'p-1',
          name: 'Coca-Cola 0,5l',
          category: 'Getränke',
          unit: 'Flasche',
          quantity: 6,
          note: 'untere Reihe leer',
          done: false,
          addedByUid: 'peter',
          addedByName: 'Peter',
          addedAt: DateTime(2026, 6, 28, 9, 15),
        ),
        const FridgeRefillItem(
          id: 'i-2',
          // Freitext-Position (kein Artikel).
          name: 'Mezzo Mix',
          quantity: 2,
          done: true,
        ),
      ],
      updatedByUid: 'peter',
      updatedAt: DateTime(2026, 6, 28, 9, 16),
    );
  }

  group('FridgeRefillItem', () {
    test('isFreeText erkennt Positionen ohne Artikel', () {
      const withProduct = FridgeRefillItem(id: 'a', productId: 'p-1', name: 'X');
      const freeText = FridgeRefillItem(id: 'b', name: 'Wasser');
      expect(withProduct.isFreeText, isFalse);
      expect(freeText.isFreeText, isTrue);
    });

    test('clear-Flags leeren nullable Felder', () {
      const item = FridgeRefillItem(
        id: 'i-1',
        productId: 'p-1',
        name: 'Cola',
        category: 'Getränke',
        note: 'leer',
      );
      final cleared = item.copyWith(
        clearProduct: true,
        clearCategory: true,
        clearNote: true,
      );
      expect(cleared.productId, isNull);
      expect(cleared.category, isNull);
      expect(cleared.note, isNull);
      expect(cleared.name, 'Cola');
    });
  });

  group('FridgeRefillList Helfer', () {
    test('openCount/doneCount/itemById/openItemForProduct', () {
      final list = sample();
      expect(list.itemCount, 2);
      expect(list.openCount, 1);
      expect(list.doneCount, 1);
      expect(list.isEmpty, isFalse);
      expect(list.itemById('i-2')?.name, 'Mezzo Mix');
      expect(list.openItemForProduct('p-1')?.id, 'i-1');
      // Abgehakte/fehlende Positionen liefern null.
      expect(list.openItemForProduct('fehlt'), isNull);
      expect(list.openItemForProduct(null), isNull);
    });

    test('openItemForProduct ignoriert abgehakte Positionen', () {
      const list = FridgeRefillList(
        orgId: 'org-1',
        siteId: 'site-1',
        items: [
          FridgeRefillItem(id: 'i-1', productId: 'p-1', name: 'Cola', done: true),
        ],
      );
      expect(list.openItemForProduct('p-1'), isNull);
    });
  });

  group('Dual-Serialisierung', () {
    test('snake_case Round-Trip (toMap/fromMap)', () {
      final list = sample();
      final restored = FridgeRefillList.fromMap(list.toMap());

      expect(restored.id, 'site-1');
      expect(restored.orgId, 'org-1');
      expect(restored.siteId, 'site-1');
      expect(restored.siteName, 'Tabak Börse');
      expect(restored.updatedByUid, 'peter');
      expect(restored.updatedAt, DateTime(2026, 6, 28, 9, 16));
      expect(restored.items, hasLength(2));

      final first = restored.items.first;
      expect(first.id, 'i-1');
      expect(first.productId, 'p-1');
      expect(first.name, 'Coca-Cola 0,5l');
      expect(first.category, 'Getränke');
      expect(first.unit, 'Flasche');
      expect(first.quantity, 6);
      expect(first.note, 'untere Reihe leer');
      expect(first.done, isFalse);
      expect(first.addedByUid, 'peter');
      expect(first.addedByName, 'Peter');
      expect(first.addedAt, DateTime(2026, 6, 28, 9, 15));

      final second = restored.items.last;
      expect(second.productId, isNull);
      expect(second.isFreeText, isTrue);
      expect(second.done, isTrue);
    });

    test('camelCase Round-Trip (toFirestoreMap/fromFirestore)', () {
      final list = sample();
      final map = list.toFirestoreMap();
      // Eingebettetes addedAt ist ein konkreter Timestamp (kein serverTimestamp).
      final items = map['items'] as List;
      expect((items.first as Map)['addedAt'], isA<Timestamp>());

      final restored = FridgeRefillList.fromFirestore('site-1', map);
      expect(restored.id, 'site-1');
      expect(restored.orgId, 'org-1');
      expect(restored.siteId, 'site-1');
      expect(restored.items, hasLength(2));
      expect(restored.items.first.quantity, 6);
      expect(restored.items.first.addedAt, DateTime(2026, 6, 28, 9, 15));
      expect(restored.items.last.isFreeText, isTrue);
      expect(restored.items.last.done, isTrue);
    });

    test('siteId faellt in fromFirestore auf die Doc-ID zurueck', () {
      final restored = FridgeRefillList.fromFirestore('site-9', {
        'orgId': 'org-1',
        'items': const [],
      });
      expect(restored.siteId, 'site-9');
    });
  });
}
