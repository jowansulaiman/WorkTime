import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/services/export_service.dart';
import 'package:worktime_app/services/pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PdfService', () {
    test('generates a monthly report without external font downloads',
        () async {
      final bytes = await PdfService.generateMonthlyReport(
        entries: [
          WorkEntry(
            date: DateTime(2026, 3, 1),
            startTime: DateTime(2026, 3, 1, 8),
            endTime: DateTime(2026, 3, 1, 16, 30),
            breakMinutes: 30,
            note: 'Frühschicht',
          ),
          WorkEntry(
            date: DateTime(2026, 3, 2),
            startTime: DateTime(2026, 3, 2, 9),
            endTime: DateTime(2026, 3, 2, 17),
            breakMinutes: 45,
            note: 'Übergabe',
          ),
        ],
        settings: const UserSettings(
          name: 'Jörg Müller',
          hourlyRate: 18.5,
          dailyHours: 8,
          currency: 'EUR',
        ),
        year: 2026,
        month: 3,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
    });

    test('generates a shift plan report without external font downloads',
        () async {
      final bytes = await PdfService.generateShiftPlanReport(
        shifts: [
          Shift(
            orgId: 'org-1',
            userId: 'employee-1',
            employeeName: 'Anna',
            title: 'Fruehdienst',
            startTime: DateTime(2026, 4, 1, 6),
            endTime: DateTime(2026, 4, 1, 14),
            breakMinutes: 30,
            teamId: 'team-1',
            team: 'Service',
            notes: 'Kasse',
          ),
          Shift(
            orgId: 'org-1',
            userId: 'employee-2',
            employeeName: 'Ben',
            title: 'Spaetdienst',
            startTime: DateTime(2026, 4, 1, 13),
            endTime: DateTime(2026, 4, 1, 21),
            breakMinutes: 45,
            teamId: 'team-1',
            team: 'Service',
            status: ShiftStatus.confirmed,
          ),
        ],
        rangeLabel: '01.04.2026 - 07.04.2026',
        employeeLabel: 'Alle Mitarbeiter',
        teamLabel: 'Service',
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
    });

    test('builds a shift plan csv with metadata and rows', () {
      final csv = ExportService.buildShiftPlanCsv(
        shifts: [
          Shift(
            orgId: 'org-1',
            userId: 'employee-1',
            employeeName: 'Anna',
            title: 'Fruehdienst',
            startTime: DateTime(2026, 4, 1, 6),
            endTime: DateTime(2026, 4, 1, 14),
            breakMinutes: 30,
            teamId: 'team-1',
            team: 'Service',
            notes: 'Kasse',
          ),
        ],
        rangeLabel: '01.04.2026 - 07.04.2026',
        employeeLabel: 'Anna',
        teamLabel: 'Service',
      );

      expect(csv, startsWith('\uFEFFSchichtplan Export'));
      expect(csv, contains('Zeitraum;01.04.2026 - 07.04.2026'));
      expect(csv, contains('Mitarbeiter;Anna'));
      expect(csv, contains('Team;Service'));
      expect(csv, contains('Fruehdienst'));
      expect(csv, contains('Kasse'));
    });
  });
}
