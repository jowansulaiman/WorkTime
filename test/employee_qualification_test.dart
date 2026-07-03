import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/employee_qualification.dart';

void main() {
  EmployeeQualification quali({DateTime? gueltigBis}) => EmployeeQualification(
        orgId: 'org-1',
        userId: 'emp-1',
        qualificationName: 'Kassenschulung',
        gueltigBis: gueltigBis,
      );

  group('EmployeeQualification.gueltigkeitStatus (PA-1.3)', () {
    final now = DateTime(2026, 7, 3, 10);

    test('ohne gueltigBis: unbefristet gültig', () {
      expect(quali().gueltigkeitStatus(now), QualiGueltigkeit.gueltig);
    });

    test('gueltigBis weit in der Zukunft: gültig', () {
      expect(
        quali(gueltigBis: DateTime(2026, 12, 31)).gueltigkeitStatus(now),
        QualiGueltigkeit.gueltig,
      );
    });

    test('gueltigBis gestern: abgelaufen', () {
      expect(
        quali(gueltigBis: DateTime(2026, 7, 2)).gueltigkeitStatus(now),
        QualiGueltigkeit.abgelaufen,
      );
    });

    test('gueltigBis in 10 Tagen (< Warnfrist 30): läuft ab', () {
      expect(
        quali(gueltigBis: DateTime(2026, 7, 13)).gueltigkeitStatus(now),
        QualiGueltigkeit.laeuftAb,
      );
    });

    test('gueltigBis heute: läuft ab (bis Tagesende gültig)', () {
      expect(
        quali(gueltigBis: DateTime(2026, 7, 3)).gueltigkeitStatus(now),
        QualiGueltigkeit.laeuftAb,
      );
    });

    test('gueltigBis in 31 Tagen (außerhalb Warnfrist): gültig', () {
      expect(
        quali(gueltigBis: DateTime(2026, 8, 3)).gueltigkeitStatus(now),
        QualiGueltigkeit.gueltig,
      );
    });

    test('warnTage konfigurierbar: 7-Tage-Fenster', () {
      final q = quali(gueltigBis: DateTime(2026, 7, 20));
      expect(q.gueltigkeitStatus(now, warnTage: 7), QualiGueltigkeit.gueltig);
      expect(
        q.gueltigkeitStatus(DateTime(2026, 7, 15), warnTage: 7),
        QualiGueltigkeit.laeuftAb,
      );
    });
  });
}
