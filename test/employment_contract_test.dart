import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/employment_contract.dart';

void main() {
  group('EmploymentContract.salaryKind (H-B3)', () {
    test('default ist Festgehalt (monthly) — keine Verhaltensänderung', () {
      final contract = EmploymentContract(
        orgId: 'org-1',
        userId: 'u1',
        validFrom: DateTime(2026, 1, 1),
      );
      expect(contract.salaryKind, SalaryKind.monthly);
    });

    test('round-trips durch beide Serialisierungen', () {
      final contract = EmploymentContract(
        id: 'c1',
        orgId: 'org-1',
        userId: 'u1',
        validFrom: DateTime(2026, 1, 1),
        hourlyRate: 15,
        salaryKind: SalaryKind.hourly,
      );

      expect(
        EmploymentContract.fromMap(contract.toMap()).salaryKind,
        SalaryKind.hourly,
      );
      expect(
        EmploymentContract.fromFirestore('c1', contract.toFirestoreMap())
            .salaryKind,
        SalaryKind.hourly,
      );
      expect(contract.copyWith(salaryKind: SalaryKind.monthly).salaryKind,
          SalaryKind.monthly);
    });

    test('fromValue fällt unbekannt still auf monthly (Enum-Kopplungsregel)',
        () {
      expect(SalaryKindX.fromValue('hourly'), SalaryKind.hourly);
      expect(SalaryKindX.fromValue('unbekannt'), SalaryKind.monthly);
      expect(SalaryKindX.fromValue(null), SalaryKind.monthly);
      expect(SalaryKind.hourly.value, 'hourly');
      expect(SalaryKind.hourly.label, 'Stundenlohn');
    });

    test('Altdaten ohne salary_kind lesen als monthly (rückwärtskompatibel)',
        () {
      final legacy = {
        'id': 'c2',
        'org_id': 'org-1',
        'user_id': 'u1',
        'valid_from': DateTime(2026, 1, 1).toIso8601String(),
        'hourly_rate': 12.0,
      };
      expect(EmploymentContract.fromMap(legacy).salaryKind, SalaryKind.monthly);
    });
  });

  group('EmploymentContract.monthlyGrossCents (M1 kanonisches Festgehalt)', () {
    test('round-trips durch beide Serialisierungen + copyWith/clear', () {
      final contract = EmploymentContract(
        id: 'c1',
        orgId: 'org-1',
        userId: 'u1',
        validFrom: DateTime(2026, 1, 1),
        monthlyGrossCents: 250000,
      );
      expect(
        EmploymentContract.fromMap(contract.toMap()).monthlyGrossCents,
        250000,
      );
      expect(
        EmploymentContract.fromFirestore('c1', contract.toFirestoreMap())
            .monthlyGrossCents,
        250000,
      );
      expect(contract.copyWith(monthlyGrossCents: 300000).monthlyGrossCents,
          300000);
      expect(contract.copyWith(clearMonthlyGrossCents: true).monthlyGrossCents,
          isNull);
    });

    test('Altdaten ohne monthly_gross_cents lesen als null', () {
      final legacy = {
        'id': 'c2',
        'org_id': 'org-1',
        'user_id': 'u1',
        'valid_from': DateTime(2026, 1, 1).toIso8601String(),
      };
      expect(EmploymentContract.fromMap(legacy).monthlyGrossCents, isNull);
    });
  });

  group('EmploymentContract Stundengrenzen (monthly/weeklyMaxHours)', () {
    test('round-trips durch beide Serialisierungen inkl. null', () {
      final contract = EmploymentContract(
        id: 'c1',
        orgId: 'org-1',
        userId: 'u1',
        validFrom: DateTime(2026, 1, 1),
        weeklyMaxHours: 37.5,
        monthlyMaxHours: 160,
      );

      final fromLocal = EmploymentContract.fromMap(contract.toMap());
      expect(fromLocal.weeklyMaxHours, 37.5);
      expect(fromLocal.monthlyMaxHours, 160);

      final fromCloud = EmploymentContract.fromFirestore(
        'c1',
        contract.toFirestoreMap(),
      );
      expect(fromCloud.weeklyMaxHours, 37.5);
      expect(fromCloud.monthlyMaxHours, 160);
    });

    test('Defaults sind null (keine vertragliche Grenze)', () {
      final contract = EmploymentContract(
        orgId: 'org-1',
        userId: 'u1',
        validFrom: DateTime(2026, 1, 1),
      );
      expect(contract.weeklyMaxHours, isNull);
      expect(contract.monthlyMaxHours, isNull);
    });

    test('copyWith setzt und clearX leert beide Felder', () {
      final contract = EmploymentContract(
        orgId: 'org-1',
        userId: 'u1',
        validFrom: DateTime(2026, 1, 1),
        weeklyMaxHours: 40,
        monthlyMaxHours: 170,
      );
      expect(contract.copyWith(weeklyMaxHours: 30).weeklyMaxHours, 30);
      expect(contract.copyWith(monthlyMaxHours: 150).monthlyMaxHours, 150);
      expect(contract.copyWith(clearWeeklyMaxHours: true).weeklyMaxHours, isNull);
      expect(
        contract.copyWith(clearMonthlyMaxHours: true).monthlyMaxHours,
        isNull,
      );
      // Unveränderte Felder bleiben erhalten.
      expect(contract.copyWith(clearWeeklyMaxHours: true).monthlyMaxHours, 170);
    });

    test('Altdaten ohne die Felder lesen als null', () {
      final legacy = {
        'id': 'c2',
        'org_id': 'org-1',
        'user_id': 'u1',
        'valid_from': DateTime(2026, 1, 1).toIso8601String(),
      };
      final contract = EmploymentContract.fromMap(legacy);
      expect(contract.weeklyMaxHours, isNull);
      expect(contract.monthlyMaxHours, isNull);
    });
  });
}
