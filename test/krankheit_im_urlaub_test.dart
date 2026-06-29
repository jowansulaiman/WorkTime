import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/urlaub_calculator.dart';
import 'package:worktime_app/models/absence_request.dart';
import 'package:worktime_app/models/sollzeit_profile.dart';

// 27.04.2026 ist ein Montag; 01.05.2026 (Fr) ist Feiertag in SH.
SollzeitProfile _vollzeit() => SollzeitProfile(
      orgId: 'o',
      userId: 'u',
      gueltigAb: DateTime(2020, 1, 1),
      montagMinutes: 480,
      dienstagMinutes: 480,
      mittwochMinutes: 480,
      donnerstagMinutes: 480,
      freitagMinutes: 480,
    );

AbsenceRequest _abs(
  DateTime von,
  DateTime bis,
  AbsenceType type, {
  AbsenceStatus status = AbsenceStatus.approved,
  bool halfDay = false,
}) =>
    AbsenceRequest(
      orgId: 'o',
      userId: 'u',
      employeeName: 'Test',
      startDate: von,
      endDate: bis,
      type: type,
      status: status,
      halfDay: halfDay,
    );

void main() {
  group('findeKrankheitImUrlaub (§9 BUrlG)', () {
    test('Krankheit im genehmigten Urlaub → werktagsgenaue Überlappung', () {
      final res = findeKrankheitImUrlaub(
        [
          _abs(DateTime(2026, 4, 27), DateTime(2026, 4, 30),
              AbsenceType.vacation),
          _abs(DateTime(2026, 4, 28), DateTime(2026, 4, 29),
              AbsenceType.sickness),
        ],
        jahr: 2026,
        sollzeit: _vollzeit(),
      );
      expect(res, hasLength(1));
      expect(res.single.tage, 2);
      expect(res.single.urlaub.type, AbsenceType.vacation);
      expect(res.single.krankheit.type, AbsenceType.sickness);
    });

    test('keine zeitliche Überlappung → leer', () {
      final res = findeKrankheitImUrlaub(
        [
          _abs(DateTime(2026, 4, 27), DateTime(2026, 4, 30),
              AbsenceType.vacation),
          _abs(DateTime(2026, 5, 11), DateTime(2026, 5, 12),
              AbsenceType.sickness),
        ],
        jahr: 2026,
        sollzeit: _vollzeit(),
      );
      expect(res, isEmpty);
    });

    test('nur GENEHMIGTER Urlaub zählt (offener wird ignoriert)', () {
      final res = findeKrankheitImUrlaub(
        [
          _abs(DateTime(2026, 4, 27), DateTime(2026, 4, 30),
              AbsenceType.vacation,
              status: AbsenceStatus.pending),
          _abs(DateTime(2026, 4, 28), DateTime(2026, 4, 29),
              AbsenceType.sickness),
        ],
        jahr: 2026,
        sollzeit: _vollzeit(),
      );
      expect(res, isEmpty);
    });

    test('abgelehnte Krankheit zählt nicht', () {
      final res = findeKrankheitImUrlaub(
        [
          _abs(DateTime(2026, 4, 27), DateTime(2026, 4, 30),
              AbsenceType.vacation),
          _abs(DateTime(2026, 4, 28), DateTime(2026, 4, 29),
              AbsenceType.sickness,
              status: AbsenceStatus.rejected),
        ],
        jahr: 2026,
        sollzeit: _vollzeit(),
      );
      expect(res, isEmpty);
    });

    test('Feiertag in der Überlappung wird nicht gutgeschrieben (1.5.)', () {
      // Mo 27.4 – Fr 1.5: 5 Tage, 1.5. ist Feiertag → 4 anrechenbare Werktage.
      final res = findeKrankheitImUrlaub(
        [
          _abs(DateTime(2026, 4, 27), DateTime(2026, 5, 1),
              AbsenceType.vacation),
          _abs(DateTime(2026, 4, 27), DateTime(2026, 5, 1),
              AbsenceType.sickness),
        ],
        jahr: 2026,
        sollzeit: _vollzeit(),
      );
      expect(res.single.tage, 4);
    });
  });

  group('werktageImBereich', () {
    test('zählt Mo–Fr, ignoriert Wochenende (feiertage leer)', () {
      final t = werktageImBereich(
        DateTime(2026, 4, 27), // Mo
        DateTime(2026, 5, 3), // So
        jahr: 2026,
        feiertage: const {},
        sollzeit: _vollzeit(),
      );
      expect(t, 5);
    });

    test('halbtags zählt 0,5 je Werktag', () {
      final t = werktageImBereich(
        DateTime(2026, 4, 27),
        DateTime(2026, 4, 28),
        jahr: 2026,
        feiertage: const {},
        sollzeit: _vollzeit(),
        halbtags: true,
      );
      expect(t, 1.0); // 2 Werktage × 0,5
    });
  });

  group('AbsenceRequest.durationHours', () {
    test('ohne hours → 0', () {
      expect(
        _abs(DateTime(2026, 4, 27), DateTime(2026, 4, 27), AbsenceType.timeOff)
            .durationHours,
        0,
      );
    });

    test('mit hours → der Wert', () {
      final r = AbsenceRequest(
        orgId: 'o',
        userId: 'u',
        employeeName: 'T',
        startDate: DateTime(2026, 4, 27),
        endDate: DateTime(2026, 4, 27),
        type: AbsenceType.timeOff,
        hours: 3.5,
      );
      expect(r.durationHours, 3.5);
    });
  });
}
