import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/expiry_warning.dart';
import 'package:worktime_app/models/product_batch.dart';

void main() {
  ProductBatch batch({
    required String id,
    required DateTime expiry,
    String siteId = 'site-1',
    BatchStatus status = BatchStatus.active,
  }) =>
      ProductBatch(
        id: id,
        orgId: 'org-1',
        siteId: siteId,
        productId: 'p-$id',
        productName: 'Artikel $id',
        expiryDate: expiry,
        status: status,
      );

  final now = DateTime(2026, 7, 1, 9, 30);

  group('computeExpiryWarnings', () {
    test('meldet nur Chargen innerhalb leadDays (inkl. abgelaufene), sortiert',
        () {
      final warnings = computeExpiryWarnings(
        [
          batch(id: 'a', expiry: DateTime(2026, 7, 1)), // heute (0)
          batch(id: 'b', expiry: DateTime(2026, 7, 3)), // in 2 Tagen
          batch(id: 'c', expiry: DateTime(2026, 7, 4)), // in 3 Tagen (Grenze)
          batch(id: 'd', expiry: DateTime(2026, 7, 5)), // in 4 Tagen (raus)
          batch(id: 'e', expiry: DateTime(2026, 6, 29)), // -2 (abgelaufen)
        ],
        now,
        leadDays: 3,
      );
      // Aufsteigend nach Restlaufzeit: dringendste (abgelaufen) zuerst.
      expect(warnings.map((w) => w.batch.id).toList(), ['e', 'a', 'b', 'c']);
    });

    test('Severity-Schwellen (expired/critical/soon)', () {
      final w = computeExpiryWarnings(
        [
          batch(id: 'exp', expiry: DateTime(2026, 6, 30)), // -1
          batch(id: 'today', expiry: DateTime(2026, 7, 1)), // 0
          batch(id: 'tmrw', expiry: DateTime(2026, 7, 2)), // 1
          batch(id: 'soon', expiry: DateTime(2026, 7, 4)), // 3
        ],
        now,
        leadDays: 3,
      );
      final bySeverity = {for (final x in w) x.batch.id: x.severity};
      expect(bySeverity['exp'], ExpirySeverity.expired);
      expect(bySeverity['today'], ExpirySeverity.critical);
      expect(bySeverity['tmrw'], ExpirySeverity.critical);
      expect(bySeverity['soon'], ExpirySeverity.soon);
    });

    test('filtert auf status==active und optional siteId', () {
      final w = computeExpiryWarnings(
        [
          batch(id: 'active', expiry: DateTime(2026, 7, 2)),
          batch(
              id: 'sold',
              expiry: DateTime(2026, 7, 2),
              status: BatchStatus.soldOut),
          batch(
              id: 'discarded',
              expiry: DateTime(2026, 7, 2),
              status: BatchStatus.discarded),
          batch(
              id: 'otherSite',
              expiry: DateTime(2026, 7, 2),
              siteId: 'site-2'),
        ],
        now,
        siteId: 'site-1',
      );
      expect(w.map((x) => x.batch.id).toList(), ['active']);
    });

    test('leadDays ist konfigurierbar', () {
      final batches = [
        batch(id: 'a', expiry: DateTime(2026, 7, 2)), // 1
        batch(id: 'b', expiry: DateTime(2026, 7, 6)), // 5
      ];
      expect(computeExpiryWarnings(batches, now, leadDays: 3).length, 1);
      expect(computeExpiryWarnings(batches, now, leadDays: 7).length, 2);
    });

    test('DST-robust: zählt Kalendertage, nicht Stunden', () {
      // now spät am Tag, Ablauf früh am Folgetag → 1 Kalendertag.
      final w = computeExpiryWarnings(
        [batch(id: 'x', expiry: DateTime(2026, 7, 2, 1))],
        DateTime(2026, 7, 1, 23),
        leadDays: 3,
      );
      expect(w.single.daysUntilExpiry, 1);
    });

    test('leere Eingabe → keine Warnungen', () {
      expect(computeExpiryWarnings(const [], now), isEmpty);
    });
  });
}
