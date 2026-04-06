import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/work_entry.dart';

void main() {
  group('WorkEntry date handling', () {
    test('stores calendar dates as plain YYYY-MM-DD values', () {
      final entry = WorkEntry(
        date: DateTime(2026, 3, 29),
        startTime: DateTime(2026, 3, 29, 8),
        endTime: DateTime(2026, 3, 29, 17),
        breakMinutes: 30,
        siteId: 'site-1',
        siteName: 'Berlin',
        correctionReason: 'Nachtrag',
        correctedByUid: 'user-1',
        correctedAt: DateTime(2026, 3, 29, 18),
      );

      final map = entry.toMap();
      final restored = WorkEntry.fromMap(map);

      expect(map['date'], '2026-03-29');
      expect(restored.date.year, 2026);
      expect(restored.date.month, 3);
      expect(restored.date.day, 29);
      expect(restored.date.hour, 12);
      expect(restored.siteId, 'site-1');
      expect(restored.siteName, 'Berlin');
      expect(restored.correctionReason, 'Nachtrag');
    });

    test('normalizes legacy UTC timestamps back to the local calendar day', () {
      final legacyDate = DateTime.parse('2026-03-28T23:00:00.000Z').toLocal();

      final restored = WorkEntry.fromMap({
        'id': 1,
        'date': '2026-03-28T23:00:00.000Z',
        'start_time': '2026-03-29T08:00:00.000',
        'end_time': '2026-03-29T17:00:00.000',
        'break_minutes': 30,
        'note': null,
        'category': null,
      });

      expect(restored.date.year, legacyDate.year);
      expect(restored.date.month, legacyDate.month);
      expect(restored.date.day, legacyDate.day);
      expect(restored.date.hour, 12);
    });
  });
}
