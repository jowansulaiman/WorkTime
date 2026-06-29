import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:worktime_app/core/finance_analytics.dart';
import 'package:worktime_app/models/finance_models.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/services/export_service.dart';
import 'package:worktime_app/services/pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('de_DE'));

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

    test('generates a finance report without external font downloads',
        () async {
      const center =
          CostCenter(id: 'c1', orgId: 'o', number: '1001', name: 'Strichmännchen');
      final bytes = await PdfService.generateFinanceReport(
        year: 2026,
        orgName: 'Kostenrechnung',
        reports: const [
          CostCenterReport(
            center: center,
            plannedCents: 1200000,
            actualCents: 900000,
            entryCount: 12,
          ),
        ],
        months: FinanceAnalytics.monthlyBreakdown(
          [
            JournalEntry(
              orgId: 'o',
              date: DateTime(2026, 3, 1),
              costCenterId: 'c1',
              costTypeId: 't1',
              description: 'Miete',
              amountCents: 250000,
            ),
          ],
          2026,
        ),
        totalPlanned: 1200000,
        totalActual: 900000,
        totalExpenses: 950000,
        totalCredits: 50000,
      );
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
    });

    test('builds a shift plan csv split per site (matrix)', () {
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
            siteId: 'site-1',
            siteName: 'Tabak B\u00F6rse',
          ),
          Shift(
            orgId: 'org-1',
            userId: 'employee-2',
            employeeName: 'Ben',
            title: 'Spaetdienst',
            startTime: DateTime(2026, 4, 2, 13),
            endTime: DateTime(2026, 4, 2, 19),
            breakMinutes: 0,
            siteId: 'site-2',
            siteName: 'Strichm\u00E4nnchen GmbH',
          ),
        ],
        rangeStart: DateTime(2026, 4, 1),
        rangeEnd: DateTime(2026, 4, 8),
        rangeLabel: '01.04.2026 - 07.04.2026',
        employeeLabel: 'Alle',
        teamLabel: 'Service',
      );

      expect(csv, startsWith('\uFEFFSchichtplan Export'));
      expect(csv, contains('Zeitraum;01.04.2026 - 07.04.2026'));
      // Pro Standort eine Sektion + Datums-Spaltenkopf.
      expect(csv, contains('Tabak B\u00F6rse'));
      expect(csv, contains('Strichm\u00E4nnchen GmbH'));
      expect(csv, contains('Mitarbeiter;'));
      expect(csv, contains('01.04.'));
      // Matrix-Zellen mit Uhrzeit-Spanne.
      expect(csv, contains('Anna'));
      expect(csv, contains('06:00\u201314:00'));
      expect(csv, contains('Ben'));
      expect(csv, contains('13:00\u201319:00'));
    });
  });
}
