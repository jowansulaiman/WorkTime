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

    test('roundtrips updatedAt through the local map (LWW-Tie-Breaker)', () {
      final entry = WorkEntry(
        id: 'e1',
        date: DateTime(2026, 3, 29),
        startTime: DateTime(2026, 3, 29, 8),
        endTime: DateTime(2026, 3, 29, 17),
        updatedAt: DateTime(2026, 3, 29, 18, 30),
      );

      final restored = WorkEntry.fromMap(entry.toMap());

      expect(restored.updatedAt, isNotNull);
      expect(restored.updatedAt!.toIso8601String(),
          entry.updatedAt!.toIso8601String());
    });
  });

  group('WorkEntry status workflow (M2)', () {
    WorkEntry sample({
      WorkEntryStatus status = WorkEntryStatus.approved,
      String? approvedByUid,
      DateTime? approvedAt,
      String? sourceClockEntryId,
    }) =>
        WorkEntry(
          id: 'e1',
          date: DateTime(2026, 6, 1),
          startTime: DateTime(2026, 6, 1, 8),
          endTime: DateTime(2026, 6, 1, 16),
          status: status,
          approvedByUid: approvedByUid,
          approvedAt: approvedAt,
          sourceClockEntryId: sourceClockEntryId,
        );

    test('defaults to approved (abwärtskompatibel)', () {
      expect(sample().status, WorkEntryStatus.approved);
    });

    test('fromValue fällt für unbekannt/leer auf approved', () {
      expect(WorkEntryStatus.fromValue('bogus'), WorkEntryStatus.approved);
      expect(WorkEntryStatus.fromValue(null), WorkEntryStatus.approved);
      expect(WorkEntryStatus.fromValue(''), WorkEntryStatus.approved);
      expect(WorkEntryStatus.fromValue('rejected'), WorkEntryStatus.rejected);
    });

    test('lokale Map round-trippt Status + Freigabe + sourceClockEntryId', () {
      final entry = sample(
        status: WorkEntryStatus.submitted,
        approvedByUid: 'mgr-1',
        approvedAt: DateTime(2026, 6, 2, 9, 30),
        sourceClockEntryId: 'clk-1',
      );
      final map = entry.toMap();
      expect(map['status'], 'submitted');
      expect(map['source_clock_entry_id'], 'clk-1');

      final restored = WorkEntry.fromMap(map);
      expect(restored.status, WorkEntryStatus.submitted);
      expect(restored.approvedByUid, 'mgr-1');
      expect(restored.approvedAt!.toIso8601String(),
          entry.approvedAt!.toIso8601String());
      expect(restored.sourceClockEntryId, 'clk-1');
    });

    test('fromMap ohne status-Feld bleibt approved (Altdaten)', () {
      final restored = WorkEntry.fromMap({
        'date': '2026-06-01',
        'start_time': '2026-06-01T08:00:00.000',
        'end_time': '2026-06-01T16:00:00.000',
      });
      expect(restored.status, WorkEntryStatus.approved);
    });

    test('toFirestoreMap serialisiert Status + Freigabefelder', () {
      final map = sample(
        status: WorkEntryStatus.rejected,
        approvedByUid: 'mgr-2',
        approvedAt: DateTime(2026, 6, 2, 10),
        sourceClockEntryId: 'clk-2',
      ).toFirestoreMap();
      expect(map['status'], 'rejected');
      expect(map['approvedByUid'], 'mgr-2');
      expect(map['approvedAt'], isNotNull);
      expect(map['sourceClockEntryId'], 'clk-2');
    });

    test('fromFirestore parst Status + Freigabefelder', () {
      final restored = WorkEntry.fromFirestore('e9', {
        'orgId': 'org-1',
        'userId': 'u1',
        'date': DateTime(2026, 6, 1, 12),
        'startTime': DateTime(2026, 6, 1, 8),
        'endTime': DateTime(2026, 6, 1, 16),
        'status': 'submitted',
        'approvedByUid': 'mgr-3',
        'approvedAt': DateTime(2026, 6, 2, 11),
        'sourceClockEntryId': 'clk-3',
      });
      expect(restored.status, WorkEntryStatus.submitted);
      expect(restored.approvedByUid, 'mgr-3');
      expect(restored.approvedAt, isNotNull);
      expect(restored.sourceClockEntryId, 'clk-3');
    });

    test('copyWith setzt Status und leert die Freigabe (Wiedereröffnen)', () {
      final reopened = sample(
        status: WorkEntryStatus.approved,
        approvedByUid: 'mgr-1',
        approvedAt: DateTime(2026, 6, 2),
      ).copyWith(
        status: WorkEntryStatus.submitted,
        clearApprovedByUid: true,
        clearApprovedAt: true,
      );
      expect(reopened.status, WorkEntryStatus.submitted);
      expect(reopened.approvedByUid, isNull);
      expect(reopened.approvedAt, isNull);
    });
  });
}
