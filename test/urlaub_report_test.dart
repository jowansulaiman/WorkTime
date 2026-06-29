import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/urlaub_calculator.dart';
import 'package:worktime_app/models/absence_request.dart';
import 'package:worktime_app/models/sollzeit_profile.dart';
import 'package:worktime_app/models/urlaubsanpassung.dart';
import 'package:worktime_app/models/urlaubskonto_jahr.dart';

SollzeitProfile _soll({
  required int montag,
  required int dienstag,
  required int mittwoch,
  required int donnerstag,
  required int freitag,
  double urlaub = 30,
}) =>
    SollzeitProfile(
      orgId: 'o',
      userId: 'u',
      gueltigAb: DateTime(2020, 1, 1),
      montagMinutes: montag,
      dienstagMinutes: dienstag,
      mittwochMinutes: mittwoch,
      donnerstagMinutes: donnerstag,
      freitagMinutes: freitag,
      urlaubstageJahr: urlaub,
    );

AbsenceRequest _urlaub(DateTime von, DateTime bis,
        {AbsenceStatus status = AbsenceStatus.approved, bool halfDay = false}) =>
    AbsenceRequest(
      orgId: 'o',
      userId: 'u',
      employeeName: 'Test',
      startDate: von,
      endDate: bis,
      type: AbsenceType.vacation,
      status: status,
      halfDay: halfDay,
    );

void main() {
  final vollzeit =
      _soll(montag: 480, dienstag: 480, mittwoch: 480, donnerstag: 480, freitag: 480);

  group('berechneUrlaubsReport – Anspruch', () {
    test('5-Tage-Vollzeit 30 Tage volles Jahr → 30 (B1: nicht 25)', () {
      final r = berechneUrlaubsReport(jahr: 2026, sollzeit: vollzeit);
      expect(r.anspruchJahr, 30);
    });

    test('3-Tage-Teilzeit, Basis 30 → 18 (30×3/5)', () {
      final teilzeit =
          _soll(montag: 480, dienstag: 480, mittwoch: 480, donnerstag: 0, freitag: 0);
      final r = berechneUrlaubsReport(jahr: 2026, sollzeit: teilzeit);
      expect(r.anspruchJahr, 18);
    });

    test('Zwölftelung bei Eintritt zur Jahresmitte (Juli) → 15', () {
      final r = berechneUrlaubsReport(
          jahr: 2026, sollzeit: vollzeit, hireDate: DateTime(2026, 7, 1));
      expect(r.anspruchJahr, 15); // 30 × 6/12
    });

    test('§5(2): gesetzlicher Mindesturlaub wird aufgerundet (2,67 → 3)', () {
      // 2-Tage-Woche (Basis 20), 4 Monate (Sept-Eintritt): 20×0,4×4/12 = 2,667.
      final zweiTage = _soll(
          montag: 480, dienstag: 480, mittwoch: 0, donnerstag: 0, freitag: 0,
          urlaub: 20);
      final r = berechneUrlaubsReport(
          jahr: 2026, sollzeit: zweiTage, hireDate: DateTime(2026, 9, 1));
      expect(r.anspruchJahr, 3);
    });

    test('manuelle Anpassung fließt in den Anspruch ein', () {
      final r = berechneUrlaubsReport(jahr: 2026, sollzeit: vollzeit, anpassungen: [
        const Urlaubsanpassung(
            orgId: 'o', userId: 'u', jahr: 2026, tage: 2,
            art: UrlaubsAnpassungArt.sonderurlaub),
        const Urlaubsanpassung(
            orgId: 'o', userId: 'u', jahr: 2025, tage: 5), // anderes Jahr
      ]);
      expect(r.anspruchJahr, 32); // 30 + 2 (2025 ignoriert)
    });
  });

  group('genommen / geplant (Werktage + Feiertag)', () {
    test('Feiertag im Zeitraum zählt nicht (1. Mai 2026, Fr)', () {
      // Mo 27.4. – Fr 1.5.2026: 1. Mai ist Feiertag (SH) → 4 statt 5 Werktage.
      final r = berechneUrlaubsReport(
        jahr: 2026,
        sollzeit: vollzeit,
        vacationAbsences: [_urlaub(DateTime(2026, 4, 27), DateTime(2026, 5, 1))],
      );
      expect(r.genommen, 4);
    });

    test('halbtägig zählt 0,5', () {
      final r = berechneUrlaubsReport(
        jahr: 2026,
        sollzeit: vollzeit,
        vacationAbsences: [
          _urlaub(DateTime(2026, 6, 1), DateTime(2026, 6, 1), halfDay: true)
        ],
      );
      expect(r.genommen, 0.5);
    });

    test('offene Anträge zählen als geplant, nicht genommen', () {
      final r = berechneUrlaubsReport(
        jahr: 2026,
        sollzeit: vollzeit,
        vacationAbsences: [
          _urlaub(DateTime(2026, 6, 1), DateTime(2026, 6, 2),
              status: AbsenceStatus.pending),
        ],
      );
      expect(r.genommen, 0);
      expect(r.geplant, 2);
      expect(r.resturlaub, 28); // 30 - 2 geplant
      expect(r.resturlaubOhneGeplant, 30);
    });
  });

  group('Vortrag + 31.3.-Verfall (Hinweisobliegenheit)', () {
    UrlaubskontoJahr konto({DateTime? hinweis}) => UrlaubskontoJahr(
          orgId: 'o',
          userId: 'u',
          jahr: 2026,
          vortragVorjahrTage: 8,
          vortragVerfaelltAm: DateTime(2026, 3, 31),
          hinweisErteiltAm: hinweis,
        );

    test('ohne Hinweis: KEIN Verfall (EuGH/BAG)', () {
      final r = berechneUrlaubsReport(
        jahr: 2026,
        sollzeit: vollzeit,
        konto: konto(),
        stichtag: DateTime(2026, 6, 1), // nach dem 31.3.
      );
      expect(r.vortragVerfallen, 0);
      expect(r.vortragVorjahr, 8);
      expect(r.anspruchGesamt, 38); // 30 + 8
    });

    test('mit Hinweis + nach 31.3.: ungenutzter Vortrag verfällt', () {
      final r = berechneUrlaubsReport(
        jahr: 2026,
        sollzeit: vollzeit,
        konto: konto(hinweis: DateTime(2026, 1, 15)),
        stichtag: DateTime(2026, 6, 1),
      );
      expect(r.vortragVerfallen, 8); // nichts vor dem 31.3. genommen
      expect(r.anspruchGesamt, 30); // Vortrag verfallen
    });

    test('mit Hinweis: vor 31.3. genommener Vortrag verfällt nicht', () {
      final r = berechneUrlaubsReport(
        jahr: 2026,
        sollzeit: vollzeit,
        konto: konto(hinweis: DateTime(2026, 1, 15)),
        // 5 Werktage im Februar genommen (vor Verfall).
        vacationAbsences: [_urlaub(DateTime(2026, 2, 2), DateTime(2026, 2, 6))],
        stichtag: DateTime(2026, 6, 1),
      );
      expect(r.genommen, 5);
      expect(r.vortragVerfallen, 3); // 8 Vortrag − 5 genutzt = 3 verfallen
    });
  });
}
