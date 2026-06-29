import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/shift_plan_grid.dart';
import 'package:worktime_app/models/shift.dart';

void main() {
  Shift shift({
    required String employee,
    required String siteName,
    required DateTime start,
    required DateTime end,
    String userId = 'u',
  }) =>
      Shift(
        orgId: 'org-1',
        userId: employee.isEmpty ? '' : userId,
        employeeName: employee,
        title: siteName,
        startTime: start,
        endTime: end,
        siteId: 'site-$siteName',
        siteName: siteName,
      );

  test('gruppiert nach Standort, Matrix Mitarbeiter × Tage', () {
    final result = ShiftPlanGrid.build(
      shifts: [
        shift(
          employee: 'Anna',
          siteName: 'Tabak Börse',
          start: DateTime(2026, 7, 6, 6, 45),
          end: DateTime(2026, 7, 6, 10, 15),
          userId: 'u1',
        ),
        shift(
          employee: 'Anna',
          siteName: 'Tabak Börse',
          start: DateTime(2026, 7, 7, 6, 45),
          end: DateTime(2026, 7, 7, 10, 15),
          userId: 'u1',
        ),
        shift(
          employee: 'Ben',
          siteName: 'Strichmännchen GmbH',
          start: DateTime(2026, 7, 6, 15, 15),
          end: DateTime(2026, 7, 6, 19, 15),
          userId: 'u2',
        ),
      ],
      rangeStart: DateTime(2026, 7, 6),
      rangeEnd: DateTime(2026, 7, 13),
    );

    expect(result.days, hasLength(7));
    expect(result.sites.map((s) => s.siteName),
        ['Strichmännchen GmbH', 'Tabak Börse']); // alphabetisch sortiert

    final tabak = result.sites.firstWhere((s) => s.siteName == 'Tabak Börse');
    expect(tabak.rows, hasLength(1));
    final anna = tabak.rows.single;
    expect(anna.label, 'Anna');
    // Mo 06.07. + Di 07.07. belegt, Rest leer.
    expect(anna.cells[0], '06:45–10:15');
    expect(anna.cells[1], '06:45–10:15');
    expect(anna.cells[2], '');
    expect(anna.totalHours, closeTo(7.0, 0.001)); // 2× 3,5 h
  });

  test('unbesetzte Schichten landen in eigener Zeile', () {
    final result = ShiftPlanGrid.build(
      shifts: [
        shift(
          employee: '',
          siteName: 'Paketshop',
          start: DateTime(2026, 7, 6, 9),
          end: DateTime(2026, 7, 6, 17),
        ),
      ],
      rangeStart: DateTime(2026, 7, 6),
      rangeEnd: DateTime(2026, 7, 7),
    );
    final paket = result.sites.single;
    expect(paket.rows.single.label, ShiftPlanGrid.unassignedLabel);
    expect(paket.rows.single.cells.single, '09:00–17:00');
  });

  test('mehrere Schichten am selben Tag werden zusammengefasst', () {
    final result = ShiftPlanGrid.build(
      shifts: [
        shift(
          employee: 'Cara',
          siteName: 'Laden',
          start: DateTime(2026, 7, 6, 8),
          end: DateTime(2026, 7, 6, 12),
        ),
        shift(
          employee: 'Cara',
          siteName: 'Laden',
          start: DateTime(2026, 7, 6, 14),
          end: DateTime(2026, 7, 6, 18),
        ),
      ],
      rangeStart: DateTime(2026, 7, 6),
      rangeEnd: DateTime(2026, 7, 7),
    );
    expect(result.sites.single.rows.single.cells.single,
        '08:00–12:00 / 14:00–18:00');
  });

  test('leerer Bereich → leitet Tage aus den Schichten ab', () {
    final result = ShiftPlanGrid.build(
      shifts: [
        shift(
          employee: 'Dана',
          siteName: 'Laden',
          start: DateTime(2026, 7, 6, 8),
          end: DateTime(2026, 7, 6, 12),
        ),
      ],
      rangeStart: DateTime(2026, 7, 6),
      rangeEnd: DateTime(2026, 7, 6), // leer
    );
    expect(result.days, hasLength(1));
    expect(result.sites.single.rows.single.cells.single, '08:00–12:00');
  });
}
