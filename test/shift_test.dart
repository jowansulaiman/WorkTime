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
