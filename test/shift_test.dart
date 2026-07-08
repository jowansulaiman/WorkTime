import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/absence_request.dart';
import 'package:worktime_app/models/shift.dart';

void main() {
  group('Shift', () {
    test('detects overlaps for the same employee', () {
      final base = Shift(
        orgId: 'org-1',
        userId: 'user-1',
        employeeName: 'Anna',
        title: 'Fruehdienst',
        startTime: DateTime(2026, 4, 1, 8),
        endTime: DateTime(2026, 4, 1, 16),
        location: 'Berlin',
      );

      final overlapping = Shift(
        orgId: 'org-1',
        userId: 'user-1',
        employeeName: 'Anna',
        title: 'Meeting',
        startTime: DateTime(2026, 4, 1, 12),
        endTime: DateTime(2026, 4, 1, 18),
        location: 'Hamburg',
      );

      final otherEmployee = Shift(
        orgId: 'org-1',
        userId: 'user-2',
        employeeName: 'Ben',
        title: 'Spaetdienst',
        startTime: DateTime(2026, 4, 1, 12),
        endTime: DateTime(2026, 4, 1, 18),
        location: 'Berlin',
      );

      expect(base.overlaps(overlapping), isTrue);
      expect(base.overlaps(otherEmployee), isFalse);
    });

    test('keeps location when converting to and from local map', () {
      final shift = Shift(
        id: 'shift-1',
        orgId: 'org-1',
        userId: 'user-1',
        employeeName: 'Anna',
        title: 'Fruehdienst',
        startTime: DateTime(2026, 4, 1, 8),
        endTime: DateTime(2026, 4, 1, 16),
        siteId: 'site-1',
        siteName: 'Koeln Filiale',
        location: 'Koeln',
        requiredQualificationIds: ['cashier'],
      );

      final restored = Shift.fromMap(shift.toMap());

      expect(restored.siteId, 'site-1');
      expect(restored.siteName, 'Koeln Filiale');
      expect(restored.location, 'Koeln');
      expect(restored.requiredQualificationIds, ['cashier']);
    });

    test('round-trips overtimeMinutes through local map (toMap/fromMap)', () {
      final shift = Shift(
        id: 'shift-ot',
        orgId: 'org-1',
        userId: 'user-1',
        employeeName: 'Anna',
        title: 'Spätdienst',
        startTime: DateTime(2026, 4, 1, 14),
        endTime: DateTime(2026, 4, 1, 22),
        overtimeMinutes: 90,
      );

      final map = shift.toMap();
      expect(map['overtime_minutes'], 90);

      final restored = Shift.fromMap(map);
      expect(restored.overtimeMinutes, 90);
      expect(restored.hasPlannedOvertime, isTrue);
    });

    test('round-trips overtimeMinutes through Firestore map', () {
      final shift = Shift(
        id: 'shift-ot-fs',
        orgId: 'org-1',
        userId: 'user-1',
        employeeName: 'Anna',
        title: 'Spätdienst',
        startTime: DateTime(2026, 4, 1, 14),
        endTime: DateTime(2026, 4, 1, 22),
        overtimeMinutes: 45,
      );

      final map = shift.toFirestoreMap();
      expect(map['overtimeMinutes'], 45);

      final restored = Shift.fromFirestore('shift-ot-fs', map);
      expect(restored.overtimeMinutes, 45);
      expect(restored.hasPlannedOvertime, isTrue);
    });

    test('defaults overtimeMinutes to 0 when key is missing (both formats)',
        () {
      final localMap = <String, dynamic>{
        'id': 'shift-legacy',
        'org_id': 'org-1',
        'user_id': 'user-1',
        'employee_name': 'Anna',
        'title': 'Frühdienst',
        'start_time': DateTime(2026, 4, 1, 8).toIso8601String(),
        'end_time': DateTime(2026, 4, 1, 16).toIso8601String(),
      };
      final fromLocal = Shift.fromMap(localMap);
      expect(fromLocal.overtimeMinutes, 0);
      expect(fromLocal.hasPlannedOvertime, isFalse);

      final firestoreMap = <String, dynamic>{
        'orgId': 'org-1',
        'userId': 'user-1',
        'employeeName': 'Anna',
        'title': 'Frühdienst',
        'startTime': DateTime(2026, 4, 1, 8).toIso8601String(),
        'endTime': DateTime(2026, 4, 1, 16).toIso8601String(),
      };
      final fromCloud = Shift.fromFirestore('shift-legacy', firestoreMap);
      expect(fromCloud.overtimeMinutes, 0);
      expect(fromCloud.hasPlannedOvertime, isFalse);
    });

    test('parses tolerant overtimeMinutes values (num/String)', () {
      final asDouble = Shift.fromFirestore('s1', <String, dynamic>{
        'orgId': 'org-1',
        'userId': 'user-1',
        'employeeName': 'Anna',
        'title': 'Dienst',
        'startTime': DateTime(2026, 4, 1, 8).toIso8601String(),
        'endTime': DateTime(2026, 4, 1, 16).toIso8601String(),
        'overtimeMinutes': 30.0,
      });
      expect(asDouble.overtimeMinutes, 30);

      final asString = Shift.fromMap(<String, dynamic>{
        'id': 's2',
        'org_id': 'org-1',
        'user_id': 'user-1',
        'employee_name': 'Anna',
        'title': 'Dienst',
        'start_time': DateTime(2026, 4, 1, 8).toIso8601String(),
        'end_time': DateTime(2026, 4, 1, 16).toIso8601String(),
        'overtime_minutes': '25',
      });
      expect(asString.overtimeMinutes, 25);
    });

    test('copyWith keeps and overrides overtimeMinutes', () {
      final shift = Shift(
        orgId: 'org-1',
        userId: 'user-1',
        employeeName: 'Anna',
        title: 'Dienst',
        startTime: DateTime(2026, 4, 1, 8),
        endTime: DateTime(2026, 4, 1, 16),
        overtimeMinutes: 60,
      );

      expect(shift.copyWith(title: 'Neu').overtimeMinutes, 60);
      expect(shift.copyWith(overtimeMinutes: 0).overtimeMinutes, 0);
      expect(shift.copyWith(overtimeMinutes: 120).overtimeMinutes, 120);
    });
  });

  group('AbsenceRequest', () {
    test('detects date range overlap', () {
      final request = AbsenceRequest(
        orgId: 'org-1',
        userId: 'user-1',
        employeeName: 'Anna',
        startDate: DateTime(2026, 4, 2),
        endDate: DateTime(2026, 4, 4),
        type: AbsenceType.vacation,
      );

      expect(
        request.overlaps(
          DateTime(2026, 4, 1),
          DateTime(2026, 4, 3, 23, 59),
        ),
        isTrue,
      );
      expect(
        request.overlaps(
          DateTime(2026, 4, 5),
          DateTime(2026, 4, 5, 23, 59),
        ),
        isFalse,
      );
    });
  });
}
