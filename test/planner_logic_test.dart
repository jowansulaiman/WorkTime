import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/screens/shift_planner/planner_logic.dart';

void main() {
  group('rangeDays', () {
    test('liefert das halboffene Intervall [start, end)', () {
      final days = rangeDays(DateTime(2026, 3, 1), DateTime(2026, 3, 4));
      expect(days, [
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 2),
        DateTime(2026, 3, 3),
      ]);
    });

    test('leer, wenn start == end', () {
      expect(rangeDays(DateTime(2026, 3, 1), DateTime(2026, 3, 1)), isEmpty);
    });

    test('ueberbrueckt Monatsgrenzen', () {
      final days = rangeDays(DateTime(2026, 2, 27), DateTime(2026, 3, 2));
      expect(days, [
        DateTime(2026, 2, 27),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 1),
      ]);
    });
  });

  group('chunkDays', () {
    test('teilt in volle Bloecke', () {
      final chunks = chunkDays(
        List.generate(6, (i) => DateTime(2026, 3, 1 + i)),
        3,
      );
      expect(chunks, hasLength(2));
      expect(chunks.every((c) => c.length == 3), isTrue);
    });

    test('letzter Block kann kuerzer sein', () {
      final chunks = chunkDays(
        List.generate(7, (i) => DateTime(2026, 3, 1 + i)),
        3,
      );
      expect(chunks.map((c) => c.length), [3, 3, 1]);
    });
  });

  group('calendarMonthGridDays', () {
    test('beginnt an einem Montag und umfasst volle Wochen', () {
      final grid = calendarMonthGridDays(DateTime(2026, 3, 15));
      expect(grid.first.weekday, DateTime.monday);
      expect(grid.length % 7, 0);
      // Der 1. und der letzte Tag des Monats sind enthalten (Vergleich per
      // Datumskomponenten, da die lokale Tagesschrittung über eine
      // Sommerzeit-Umstellung hinweg die Uhrzeit verschieben kann).
      bool hasDay(int year, int month, int day) => grid.any((d) =>
          d.year == year && d.month == month && d.day == day);
      expect(hasDay(2026, 3, 1), isTrue);
      expect(hasDay(2026, 3, 31), isTrue);
    });

    test('letzter Tag ist ein Sonntag', () {
      final grid = calendarMonthGridDays(DateTime(2026, 3, 1));
      expect(grid.last.weekday, DateTime.sunday);
    });
  });

  group('dayKey', () {
    test('kodiert YYYYMMDD und ist monoton', () {
      expect(dayKey(DateTime(2026, 3, 7)), 20260307);
      expect(
        dayKey(DateTime(2026, 3, 7)) < dayKey(DateTime(2026, 3, 8)),
        isTrue,
      );
    });

    test('ignoriert die Uhrzeit', () {
      expect(
        dayKey(DateTime(2026, 3, 7, 23, 59)),
        dayKey(DateTime(2026, 3, 7, 0, 0)),
      );
    });
  });

  group('monthCellVisibleShiftCount', () {
    // Maße der nicht-kompakten Monatszelle (siehe _PlannerMonthDayCell).
    int wide(double available, int total) => monthCellVisibleShiftCount(
          available: available,
          total: total,
          tileExtent: 30,
          tileSpacing: 5,
          moreHintExtent: 26,
        );
    // Maße der kompakten Monatszelle (siehe _PlannerCompactMonthDayCell).
    int compact(double available, int total) => monthCellVisibleShiftCount(
          available: available,
          total: total,
          tileExtent: 20,
          tileSpacing: 4,
          moreHintExtent: 18,
        );

    test('nichts anzuzeigen ergibt 0', () {
      expect(wide(120, 0), 0);
      expect(wide(0, 5), 0);
      expect(wide(-10, 5), 0);
    });

    test('zeigt alle, wenn alles passt', () {
      // 3 Kacheln = 3*30 + 2*5 = 100 <= 105.
      expect(wide(105, 3), 3);
    });

    test('reserviert eine Zeile fuer den Hinweis, wenn nicht alles passt', () {
      // Kapazitaet bei 105 = 3, aber 5 Schichten -> Hinweiszeile kostet Platz.
      final shown = wide(105, 5);
      expect(shown, lessThan(5));
      expect(shown, greaterThan(0));
    });

    test('die gezeigten Kacheln passen immer in die Hoehe', () {
      // Eigenschaftstest: fuer viele Hoehen darf das Layout nie ueberlaufen.
      for (var available = 24.0; available <= 240.0; available += 1) {
        for (final total in [1, 2, 3, 4, 8, 20]) {
          final shown = wide(available, total);
          expect(shown, inInclusiveRange(0, total));
          final hasMore = shown < total;
          final used = shown == 0
              ? 0.0
              : shown * 30 + (shown - 1) * 5 + (hasMore ? 5 + 26 : 0);
          expect(
            used,
            lessThanOrEqualTo(available + 0.001),
            reason: 'available=$available total=$total shown=$shown',
          );
        }
      }
    });

    test('kompakte Zelle: zwei Kacheln passen, drei nicht', () {
      // 2 Kacheln = 2*20 + 4 = 44 <= 50.
      expect(compact(50, 2), 2);
      // Mit 3 Schichten kostet die Hinweiszeile Platz -> weniger sichtbar.
      expect(compact(50, 3), lessThan(3));
    });
  });

  group('isoWeekNumber', () {
    test('erster Januar 2026 liegt in KW 1', () {
      expect(isoWeekNumber(DateTime(2026, 1, 1)), 1);
    });

    test('29.12.2025 liegt in KW 1 von 2026 (ISO-8601)', () {
      expect(isoWeekNumber(DateTime(2025, 12, 29)), 1);
    });

    test('Mitte des Jahres', () {
      expect(isoWeekNumber(DateTime(2026, 7, 1)), 27);
    });
  });
}
