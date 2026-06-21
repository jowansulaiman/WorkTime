import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/ical_export.dart';
import 'package:worktime_app/models/shift.dart';

void main() {
  group('IcalExport', () {
    test('baut gültiges VCALENDAR/VEVENT mit lokaler Zeit', () {
      final shifts = [
        Shift(
          id: 's1',
          orgId: 'o',
          userId: 'u1',
          employeeName: 'Peter',
          title: 'Frühschicht',
          startTime: DateTime(2026, 6, 22, 8, 0),
          endTime: DateTime(2026, 6, 22, 16, 30),
          siteName: 'Tabak Börse',
        ),
      ];
      final ics = IcalExport.buildShifts(shifts);

      expect(ics, startsWith('BEGIN:VCALENDAR'));
      expect(ics.trimRight(), endsWith('END:VCALENDAR'));
      expect(ics, contains('BEGIN:VEVENT'));
      expect(ics, contains('UID:s1@worktime'));
      expect(ics, contains('DTSTART:20260622T080000'));
      expect(ics, contains('DTEND:20260622T163000'));
      expect(ics, contains('SUMMARY:Frühschicht – Peter'));
      expect(ics, contains('LOCATION:Tabak Börse'));
    });

    test('escaped Sonderzeichen in Feldern', () {
      final shifts = [
        Shift(
          orgId: 'o',
          userId: 'u1',
          employeeName: 'A;B',
          title: 'Schicht, früh',
          startTime: DateTime(2026, 1, 1, 9),
          endTime: DateTime(2026, 1, 1, 12),
        ),
      ];
      final ics = IcalExport.buildShifts(shifts);
      expect(ics, contains(r'SUMMARY:Schicht\, früh – A\;B'));
    });
  });
}
