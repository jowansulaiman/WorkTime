import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/sfn_lage.dart';
import 'package:worktime_app/models/work_entry.dart';

void main() {
  WorkEntry entry(DateTime start, DateTime end) => WorkEntry(
        orgId: 'org-1',
        userId: 'emp-1',
        date: start,
        startTime: start,
        endTime: end,
      );

  // Schleswig-Holstein: 1. Mai 2026 (Fr) ist Tag der Arbeit (Feiertag).
  const bl = 'SH';

  test('Tagschicht Mo 08–14 Uhr: keine Zuschläge', () {
    final l = computeSfnLage(
      [entry(DateTime(2026, 6, 8, 8), DateTime(2026, 6, 8, 14))],
      bundesland: bl,
    );
    expect(l.isZero, isTrue);
  });

  test('Nachtschicht 22–06 Uhr: 8 h Nacht (20–06)', () {
    final l = computeSfnLage(
      [entry(DateTime(2026, 6, 8, 22), DateTime(2026, 6, 9, 6))],
      bundesland: bl,
    );
    expect(l.nachtMinuten, 8 * 60);
    expect(l.sonntagMinuten, 0);
  });

  test('teilweise Nacht: 19–21 Uhr → 1 h Nacht (ab 20)', () {
    final l = computeSfnLage(
      [entry(DateTime(2026, 6, 8, 19), DateTime(2026, 6, 8, 21))],
      bundesland: bl,
    );
    expect(l.nachtMinuten, 60);
  });

  test('Sonntag 10–14 Uhr: 4 h Sonntag', () {
    // 2026-06-07 ist ein Sonntag.
    final sonntag = DateTime(2026, 6, 7);
    expect(sonntag.weekday, DateTime.sunday);
    final l = computeSfnLage(
      [entry(DateTime(2026, 6, 7, 10), DateTime(2026, 6, 7, 14))],
      bundesland: bl,
    );
    expect(l.sonntagMinuten, 4 * 60);
    expect(l.feiertagMinuten, 0);
  });

  test('Feiertag (1. Mai) 09–13 Uhr: 4 h Feiertag', () {
    final l = computeSfnLage(
      [entry(DateTime(2026, 5, 1, 9), DateTime(2026, 5, 1, 13))],
      bundesland: bl,
    );
    expect(l.feiertagMinuten, 4 * 60);
  });

  test('Nacht am Sonntag zählt in BEIDE Kategorien (Überlappung)', () {
    // So 07.06. 22:00 → Mo 08.06. 02:00: 4 h; davon Sonntag 22–24 = 2 h,
    // Nacht komplett 4 h.
    final l = computeSfnLage(
      [entry(DateTime(2026, 6, 7, 22), DateTime(2026, 6, 8, 2))],
      bundesland: bl,
    );
    expect(l.nachtMinuten, 4 * 60);
    expect(l.sonntagMinuten, 2 * 60);
  });

  test('mehrere Einträge summieren sich', () {
    final l = computeSfnLage(
      [
        entry(DateTime(2026, 6, 8, 22), DateTime(2026, 6, 9, 2)), // 4 h Nacht
        entry(DateTime(2026, 6, 10, 23), DateTime(2026, 6, 11, 1)), // 2 h Nacht
      ],
      bundesland: bl,
    );
    expect(l.nachtMinuten, 6 * 60);
  });

  test('leere/inverse Einträge ergeben zero', () {
    final l = computeSfnLage(
      [entry(DateTime(2026, 6, 8, 14), DateTime(2026, 6, 8, 14))],
      bundesland: bl,
    );
    expect(l.isZero, isTrue);
  });
}
