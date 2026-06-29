import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/abwesenheit_matrix.dart';
import 'package:worktime_app/models/absence_request.dart';

void main() {
  group('Anrechnungsmatrix §5.4a', () {
    test('jede AbsenceType hat eine Regel (regelFor nie null)', () {
      for (final t in AbsenceType.values) {
        expect(regelFor(t), isNotNull);
      }
    });

    test('Urlaub: bezahlt, als Soll, urlaubswirksam, DATEV U', () {
      final r = regelFor(AbsenceType.vacation);
      expect(r.bezahlt, isTrue);
      expect(r.alsSollAngerechnet, isTrue);
      expect(r.urlaubswirksam, isTrue);
      expect(r.datevAusfallschluessel, 'U');
    });

    test('Krank: EFZG-begrenzt, nicht urlaubswirksam, DATEV K', () {
      final r = regelFor(AbsenceType.sickness);
      expect(r.efzgBegrenzt, isTrue);
      expect(r.urlaubswirksam, isFalse);
      expect(r.datevAusfallschluessel, 'K');
      expect(efzgMaxKalendertage, 42);
    });

    test('Kind-krank: DATEV „K" (Audit-Korrektur M3, nicht „KK")', () {
      expect(regelFor(AbsenceType.childSick).datevAusfallschluessel, 'K');
    });

    test('unbezahlt + Kurzarbeit: NICHT als Soll angerechnet', () {
      // Sonst entstünde falsches Plus im Stundenkonto.
      expect(regelFor(AbsenceType.unpaidLeave).alsSollAngerechnet, isFalse);
      expect(regelFor(AbsenceType.shortTimeWork).alsSollAngerechnet, isFalse);
      expect(regelFor(AbsenceType.unpaidLeave).bezahlt, isFalse);
    });

    test('nur Urlaub ist urlaubswirksam', () {
      final urlaubswirksam = AbsenceType.values
          .where((t) => regelFor(t).urlaubswirksam)
          .toList();
      expect(urlaubswirksam, [AbsenceType.vacation]);
    });
  });
}
