import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/shift_punch_matcher.dart';
import 'package:worktime_app/models/shift.dart';

Shift _shift({
  required String id,
  String userId = 'emp-1',
  required DateTime start,
  required DateTime end,
  ShiftStatus status = ShiftStatus.confirmed,
}) {
  return Shift(
    id: id,
    orgId: 'org-1',
    userId: userId,
    employeeName: 'Anna',
    title: 'Dienst',
    startTime: start,
    endTime: end,
    status: status,
  );
}

void main() {
  final base = DateTime(2026, 6, 10);
  DateTime at(int h, int m) => DateTime(base.year, base.month, base.day, h, m);

  group('matchShiftForPunch', () {
    test('kommen innerhalb der Schicht → Treffer', () {
      final s = _shift(id: 's1', start: at(9, 0), end: at(17, 0));
      expect(
        matchShiftForPunch([s], at(9, 5), userId: 'emp-1')?.id,
        's1',
      );
    });

    test('früher Antritt innerhalb Karenz (±15 min) → Treffer', () {
      final s = _shift(id: 's1', start: at(9, 0), end: at(17, 0));
      expect(
        matchShiftForPunch([s], at(8, 50), userId: 'emp-1')?.id,
        's1',
      );
    });

    test('zu früh (vor Karenz) → kein Treffer', () {
      final s = _shift(id: 's1', start: at(9, 0), end: at(17, 0));
      expect(matchShiftForPunch([s], at(8, 40), userId: 'emp-1'), isNull);
    });

    test('nach Schichtende → kein Treffer', () {
      final s = _shift(id: 's1', start: at(9, 0), end: at(17, 0));
      expect(matchShiftForPunch([s], at(17, 1), userId: 'emp-1'), isNull);
    });

    test('cancelled/unassigned/fremde userId sind keine Kandidaten', () {
      final cancelled = _shift(
          id: 'c', start: at(9, 0), end: at(17, 0), status: ShiftStatus.cancelled);
      final foreign =
          _shift(id: 'f', userId: 'other', start: at(9, 0), end: at(17, 0));
      final unassigned =
          _shift(id: 'u', userId: '', start: at(9, 0), end: at(17, 0));
      expect(
        matchShiftForPunch([cancelled, foreign, unassigned], at(9, 5),
            userId: 'emp-1'),
        isNull,
      );
    });

    test('mehrere Treffer: kleinste |kommen−start| gewinnt', () {
      final early = _shift(id: 'a', start: at(8, 0), end: at(12, 0));
      final late = _shift(id: 'b', start: at(9, 0), end: at(13, 0));
      // kommen 09:10 → |09:10−09:00|=10 < |09:10−08:00|=70 → b.
      expect(
        matchShiftForPunch([early, late], at(9, 10), userId: 'emp-1')?.id,
        'b',
      );
    });

    test('Tie-Breaker deterministisch (gleiche Distanz → frühere start, dann id)',
        () {
      // Beide Kandidaten mit gleichem |kommen−start| = 15 min, kommen 09:00:
      // A start 08:45 (dist 15), B start 09:15 (dist 15, an der Karenz-Grenze).
      // Frühere start (08:45, id 'z') gewinnt.
      final a = _shift(id: 'z', start: at(8, 45), end: at(12, 0));
      final b = _shift(id: 'a', start: at(9, 15), end: at(13, 0));
      expect(
        matchShiftForPunch([b, a], at(9, 0), userId: 'emp-1')?.id,
        'z',
      );
    });

    test('leere Liste → null', () {
      expect(matchShiftForPunch([], at(9, 0), userId: 'emp-1'), isNull);
    });
  });
}
