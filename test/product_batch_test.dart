import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/product_batch.dart';

void main() {
  group('ProductBatch duale Serialisierung', () {
    final batch = ProductBatch(
      id: 'b-1',
      orgId: 'org-1',
      siteId: 'site-1',
      productId: 'p-9',
      productName: 'Cola 0,33l',
      expiryDate: DateTime(2026, 7, 5),
      quantity: 12,
      note: 'Palette hinten links',
      createdByUid: 'admin-1',
      createdAt: DateTime(2026, 7, 1, 8),
    );

    test('toMap/fromMap (snake_case) rundläuft', () {
      final restored = ProductBatch.fromMap(batch.toMap());
      expect(restored.id, 'b-1');
      expect(restored.orgId, 'org-1');
      expect(restored.siteId, 'site-1');
      expect(restored.productId, 'p-9');
      expect(restored.productName, 'Cola 0,33l');
      // Datum auf lokale Mittagszeit normalisiert.
      expect(restored.expiryDate, DateTime(2026, 7, 5, 12));
      expect(restored.quantity, 12);
      expect(restored.note, 'Palette hinten links');
      expect(restored.status, BatchStatus.active);
      expect(restored.createdByUid, 'admin-1');
    });

    test('toFirestoreMap/fromFirestore (camelCase, Timestamp) rundläuft', () {
      final map = batch.toFirestoreMap();
      expect(map['status'], 'active');
      expect(map['expiryDay'], '2026-07-05');
      expect(map['expiryDate'], isA<Timestamp>());
      final restored = ProductBatch.fromFirestore('b-1', map);
      expect(restored.id, 'b-1');
      expect(restored.productId, 'p-9');
      expect(restored.productName, 'Cola 0,33l');
      expect(restored.expiryDate, DateTime(2026, 7, 5, 12));
      expect(restored.quantity, 12);
      expect(restored.note, 'Palette hinten links');
      expect(restored.status, BatchStatus.active);
    });

    test('fehlendes/kaputtes MHD wirft FormatException statt 2000-01-01 (M6)',
        () {
      // Frueher fiel ein unlesbares expiryDate still auf 2000-01-01 zurueck —
      // die Charge erschien dauerhaft als extrem ueberfaellig und verdeckte
      // echte MHD-Warnungen. Jetzt ist das Feld load-bearing; die Lesepfade
      // ueberspringen solche Datensaetze protokolliert.
      final broken = batch.toMap()..remove('expiry_date');
      expect(() => ProductBatch.fromMap(broken), throwsFormatException);

      final brokenFs = batch.toFirestoreMap()..['expiryDate'] = 'quatsch';
      expect(
        () => ProductBatch.fromFirestore('b-1', brokenFs),
        throwsFormatException,
      );
    });

    test('BatchStatus.value / fromValue mit Default-Branch', () {
      expect(BatchStatus.active.value, 'active');
      expect(BatchStatus.soldOut.value, 'sold_out');
      expect(BatchStatus.discarded.value, 'discarded');
      expect(BatchStatus.fromValue('sold_out'), BatchStatus.soldOut);
      expect(BatchStatus.fromValue('discarded'), BatchStatus.discarded);
      expect(BatchStatus.fromValue('unbekannt'), BatchStatus.active);
      expect(BatchStatus.fromValue(null), BatchStatus.active);
    });

    test('copyWith clearNote/clearResolvedAt leert nur die markierten Felder',
        () {
      final resolved = batch.copyWith(
        status: BatchStatus.discarded,
        resolvedByUid: 'emp-3',
        resolvedAt: DateTime(2026, 7, 4, 10),
      );
      expect(resolved.status, BatchStatus.discarded);
      expect(resolved.resolvedByUid, 'emp-3');
      expect(resolved.resolvedAt, DateTime(2026, 7, 4, 10));

      final cleared = resolved.copyWith(clearNote: true, clearResolvedAt: true);
      expect(cleared.note, isNull);
      expect(cleared.resolvedAt, isNull);
      // nicht markierte Felder bleiben erhalten.
      expect(cleared.resolvedByUid, 'emp-3');
      expect(cleared.status, BatchStatus.discarded);
    });

    test('expiryDay = YYYY-MM-DD; Datum wird auf Mittagszeit normalisiert', () {
      final raw = ProductBatch(
        orgId: 'o',
        siteId: 's',
        productId: 'p',
        expiryDate: DateTime(2026, 12, 3, 23, 59),
      );
      expect(raw.expiryDay, '2026-12-03');
      expect(ProductBatch.normalizeDay(raw.expiryDate),
          DateTime(2026, 12, 3, 12));
    });
  });
}
