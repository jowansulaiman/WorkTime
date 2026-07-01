import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/employment_contract_resolver.dart';
import 'package:worktime_app/models/employment_contract.dart';

EmploymentContract _c({
  required String id,
  required String userId,
  required DateTime validFrom,
  DateTime? validUntil,
  double hourlyRate = 0,
}) {
  return EmploymentContract(
    id: id,
    orgId: 'org-1',
    userId: userId,
    validFrom: validFrom,
    validUntil: validUntil,
    hourlyRate: hourlyRate,
  );
}

void main() {
  group('EmploymentContractResolver.activeOn (F1)', () {
    final c2024 = _c(
      id: 'a',
      userId: 'u1',
      validFrom: DateTime(2024, 1, 1),
      validUntil: DateTime(2024, 12, 31),
      hourlyRate: 14,
    );
    final c2025 = _c(
      id: 'b',
      userId: 'u1',
      validFrom: DateTime(2025, 1, 1),
      hourlyRate: 16,
    );
    final other = _c(id: 'x', userId: 'u2', validFrom: DateTime(2025, 1, 1));

    test('liefert den am Stichtag gültigen Vertrag', () {
      final r = EmploymentContractResolver.activeOn(
          [c2024, c2025, other], 'u1', DateTime(2024, 6, 1));
      expect(r?.id, 'a');
    });

    test('neuester validFrom gewinnt bei Überlappung', () {
      final overlapping = _c(
        id: 'c',
        userId: 'u1',
        validFrom: DateTime(2025, 6, 1),
        hourlyRate: 18,
      );
      final r = EmploymentContractResolver.activeOn(
          [c2025, overlapping], 'u1', DateTime(2025, 7, 1));
      expect(r?.id, 'c');
    });

    test('ignoriert Verträge anderer Nutzer', () {
      final r = EmploymentContractResolver.activeOn(
          [other], 'u1', DateTime(2025, 6, 1));
      expect(r, isNull);
    });

    test('Fallback auf jüngsten Vertrag, wenn keiner aktiv (Default)', () {
      // Stichtag nach Ablauf von c2024 und vor c2025 gibt es nicht – aber ein
      // Stichtag, an dem nur ein abgelaufener Vertrag existiert:
      final r = EmploymentContractResolver.activeOn(
          [c2024], 'u1', DateTime(2025, 6, 1));
      expect(r?.id, 'a', reason: 'fallbackToLatest=true ist Default');
    });

    test('kein Fallback, wenn fallbackToLatest:false', () {
      final r = EmploymentContractResolver.activeOn(
          [c2024], 'u1', DateTime(2025, 6, 1),
          fallbackToLatest: false);
      expect(r, isNull);
    });

    test('jüngster Vertrag als Fallback bei mehreren abgelaufenen', () {
      final r = EmploymentContractResolver.activeOn(
          [c2024, c2025], 'u1', DateTime(2030, 1, 1),
          fallbackToLatest: true);
      // beide aktiv? c2025 hat kein validUntil → an 2030 noch aktiv → gewinnt.
      expect(r?.id, 'b');
    });

    test('leere Liste → null', () {
      expect(
        EmploymentContractResolver.activeOn([], 'u1', DateTime(2025, 1, 1)),
        isNull,
      );
    });
  });
}
