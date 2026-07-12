import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/barcode_duplicates.dart';
import 'package:worktime_app/core/scan_stats.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/scan_event.dart';

void main() {
  // Festes "Jetzt" — die Engine ist pure, Wall-Clock wird injiziert.
  final now = DateTime(2026, 7, 11, 12);

  ScanEvent event({
    String code = '4011200296908',
    ScanOutcome outcome = ScanOutcome.matched,
    String? siteId = 'site-1',
    String source = 'camera',
    String mode = 'book',
    int? timeToHitMs,
    int daysAgo = 0,
    String platform = 'android',
  }) {
    return ScanEvent(
      orgId: 'org-1',
      siteId: siteId,
      code: code,
      outcome: outcome,
      mode: mode,
      source: source,
      timeToHitMs: timeToHitMs,
      platform: platform,
      createdAt: now.subtract(Duration(days: daysAgo)),
    );
  }

  group('ScanEvent Serialisierung', () {
    test('toMap/fromMap round-trippt (snake_case, ISO-Datum)', () {
      final original = event(timeToHitMs: 850).copyWith(id: 'ev-1');
      final restored = ScanEvent.fromMap(original.toMap());
      expect(restored.id, 'ev-1');
      expect(restored.orgId, 'org-1');
      expect(restored.siteId, 'site-1');
      expect(restored.code, '4011200296908');
      expect(restored.outcome, ScanOutcome.matched);
      expect(restored.mode, 'book');
      expect(restored.source, 'camera');
      expect(restored.timeToHitMs, 850);
      expect(restored.platform, 'android');
      expect(restored.createdAt, original.createdAt);
    });

    test('fromFirestore liest camelCase; Enum-Default wirft nie', () {
      final restored = ScanEvent.fromFirestore('ev-2', {
        'orgId': 'org-1',
        'code': 'X',
        'outcome': 'voellig-unbekannt',
        'timeToHitMs': 1200.0, // FakeFirestore liefert double
      });
      expect(restored.id, 'ev-2');
      expect(restored.outcome, ScanOutcome.notFound); // Default-Branch
      expect(restored.timeToHitMs, 1200);
    });

    test('ScanOutcome value/fromValue sind konsistent', () {
      for (final outcome in ScanOutcome.values) {
        expect(ScanOutcome.fromValue(outcome.value), outcome);
      }
    });
  });

  group('computeScanStats', () {
    test('leere Eingabe ergibt leere Statistik', () {
      final stats = computeScanStats(const [], now: now);
      expect(stats.isEmpty, isTrue);
      expect(stats.hitRate, 0);
    });

    test('zaehlt Ausgaenge, Quellen und Plattformen im Fenster', () {
      final stats = computeScanStats(
        [
          event(timeToHitMs: 500),
          event(timeToHitMs: 1500),
          event(outcome: ScanOutcome.notFound, code: '999'),
          event(outcome: ScanOutcome.invalidChecksum, code: '999'),
          event(source: 'manual', outcome: ScanOutcome.matched),
          event(source: 'photo', platform: 'ios'),
          // Ausserhalb des 7-Tage-Fensters -> ignoriert.
          event(daysAgo: 10, outcome: ScanOutcome.notFound),
        ],
        now: now,
        windowDays: 7,
      );
      expect(stats.total, 6);
      expect(stats.matched, 4);
      expect(stats.notFound, 1);
      expect(stats.invalidChecksum, 1);
      expect(stats.manualEntries, 1);
      expect(stats.photoScans, 1);
      expect(stats.hitRate, closeTo(4 / 6, 0.001));
      expect(stats.averageTimeToHitMs, 1000);
      expect(stats.medianTimeToHitMs, 1500);
      expect(stats.byPlatform['android'], 5);
      expect(stats.byPlatform['ios'], 1);
      expect(stats.bySource['camera'], 4);
      expect(stats.byMode['book'], 6);
    });

    test('Fehlversuchs-Codes werden gebuendelt und absteigend sortiert', () {
      final stats = computeScanStats(
        [
          event(outcome: ScanOutcome.notFound, code: 'A', daysAgo: 1),
          event(outcome: ScanOutcome.notFound, code: 'A'),
          event(outcome: ScanOutcome.invalidChecksum, code: 'A'),
          event(outcome: ScanOutcome.notFound, code: 'B'),
        ],
        now: now,
      );
      expect(stats.failingCodes, hasLength(2));
      expect(stats.failingCodes.first.code, 'A');
      expect(stats.failingCodes.first.attempts, 3);
      expect(stats.failingCodes.first.notFound, 2);
      expect(stats.failingCodes.first.invalidChecksum, 1);
      expect(stats.failingCodes.first.lastTriedAt, now);
      expect(stats.failingCodes.last.code, 'B');
    });

    test('siteId-Filter greift', () {
      final stats = computeScanStats(
        [event(), event(siteId: 'site-2')],
        now: now,
        siteId: 'site-1',
      );
      expect(stats.total, 1);
    });
  });

  group('findDuplicateBarcodes', () {
    Product product(String id, String name, String? barcode,
        {String siteId = 'site-1', bool isActive = true}) {
      return Product(
        id: id,
        orgId: 'org-1',
        siteId: siteId,
        name: name,
        barcode: barcode,
        isActive: isActive,
      );
    }

    test('findet Duplikate je Laden, Schreibweisen-tolerant', () {
      final duplicates = findDuplicateBarcodes([
        product('p1', 'Cola', '036000291452'), // UPC-A
        product('p2', 'Cola alt', '0036000291452', isActive: false), // EAN-13
        product('p3', 'Fanta', '4006381333931'),
        // Gleicher Code, aber ANDERER Laden -> kein Duplikat.
        product('p4', 'Cola Kiel', '036000291452', siteId: 'site-2'),
        product('p5', 'Ohne Code', null),
      ]);
      expect(duplicates, hasLength(1));
      expect(duplicates.single.siteId, 'site-1');
      expect(duplicates.single.canonicalCode, '0036000291452');
      // Sortiert nach Name: „Cola" vor „Cola alt".
      expect(duplicates.single.products.map((p) => p.id), ['p1', 'p2']);
    });

    test('keine Duplikate -> leere Liste', () {
      expect(
        findDuplicateBarcodes([
          product('p1', 'A', '4006381333931'),
          product('p2', 'B', '4011200296908'),
        ]),
        isEmpty,
      );
    });
  });
}
