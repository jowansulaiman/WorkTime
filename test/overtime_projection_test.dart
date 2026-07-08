import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/overtime_projection.dart';
import 'package:worktime_app/models/employment_contract.dart';
import 'package:worktime_app/models/shift.dart';

void main() {
  // Fixe Referenzwoche: 2026-06-01 ist ein Montag.
  final monday = DateTime(2026, 6, 1);
  final tuesday = DateTime(2026, 6, 2);
  final wednesday = DateTime(2026, 6, 3);
  final friday = DateTime(2026, 6, 5);
  final sunday = DateTime(2026, 6, 7);
  final nextMonday = DateTime(2026, 6, 8);
  final july = DateTime(2026, 7, 1);

  Shift shift(
    String id, {
    required DateTime day,
    String uid = 'u1',
    int hours = 6,
    double breakMinutes = 0,
    int startHour = 8,
  }) =>
      Shift(
        id: id,
        orgId: 'org-1',
        userId: uid,
        employeeName: uid,
        title: 'Laden',
        startTime: day.add(Duration(hours: startHour)),
        endTime: day.add(Duration(hours: startHour + hours)),
        breakMinutes: breakMinutes,
        siteId: 'site-1',
        siteName: 'Laden',
      );

  EmploymentContract contract({
    String uid = 'u1',
    double? monthlyMaxHours,
    double? weeklyMaxHours,
    DateTime? validFrom,
    DateTime? validUntil,
  }) =>
      EmploymentContract(
        id: 'c-$uid',
        orgId: 'org-1',
        userId: uid,
        type: EmploymentType.fullTime,
        validFrom: validFrom ?? DateTime(2020, 1, 1),
        validUntil: validUntil,
        dailyHours: 8,
        weeklyHours: 40,
        hourlyRate: 0,
        monthlyMaxHours: monthlyMaxHours,
        weeklyMaxHours: weeklyMaxHours,
      );

  group('plannedOvertimeMinutes', () {
    test('kein Vertrag bzw. Vertrag ohne Caps → 0', () {
      final s = shift('a', day: monday);
      expect(
        plannedOvertimeMinutes(shift: s, userShifts: const [], contract: null),
        0,
      );
      expect(
        plannedOvertimeMinutes(
          shift: s,
          userShifts: const [],
          contract: contract(), // keine Caps gesetzt
        ),
        0,
      );
    });

    test('chronologische Kumulierung: nur die SPÄTERE Schicht trägt die '
        'Überstunden — unabhängig von der Übergabe-Reihenfolge', () {
      final a = shift('a', day: monday); // 6h
      final b = shift('b', day: wednesday); // 6h
      final c = contract(weeklyMaxHours: 10); // 600 Min.

      // b (Mittwoch) kippt das Konto: 720 − 600 = 120 Min.
      expect(
        plannedOvertimeMinutes(shift: b, userShifts: [a], contract: c),
        120,
      );
      // a (Montag) liegt chronologisch vorn → 0, egal ob b bekannt ist.
      expect(
        plannedOvertimeMinutes(shift: a, userShifts: [b], contract: c),
        0,
      );
      // Reihenfolgeunabhängig: b auch dann 120, wenn b „zuerst angelegt" war.
      expect(
        plannedOvertimeMinutes(shift: b, userShifts: [b, a], contract: c),
        120,
      );
    });

    test('Klemmung auf Schicht-Netto: Konto schon vor der Schicht über Cap', () {
      final a = shift('a', day: monday);
      final b = shift('b', day: wednesday);
      final c6h = shift('c', day: friday);
      // Wochen-Cap 10h: nach a+b schon 120 über; c wäre 8h drüber (480), wird
      // aber auf das eigene Netto (360) geklemmt.
      expect(
        plannedOvertimeMinutes(
          shift: c6h,
          userShifts: [a, b],
          contract: contract(weeklyMaxHours: 10),
        ),
        360,
      );
    });

    test('max(Wochen-Überschuss, Monats-Überschuss) gewinnt', () {
      final a = shift('a', day: monday);
      final b = shift('b', day: wednesday);
      // Monat 8h (Überschuss 240) vs. Woche 10h (Überschuss 120) → 240.
      expect(
        plannedOvertimeMinutes(
          shift: b,
          userShifts: [a],
          contract: contract(monthlyMaxHours: 8, weeklyMaxHours: 10),
        ),
        240,
      );
    });

    test('Pause reduziert die Netto-Minuten', () {
      final a = shift('a', day: monday);
      final b = shift('b', day: wednesday, breakMinutes: 30); // netto 330
      // Woche 10h: 360 + 330 = 690 → 90 über.
      expect(
        plannedOvertimeMinutes(
          shift: b,
          userShifts: [a],
          contract: contract(weeklyMaxHours: 10),
        ),
        90,
      );
    });

    test('Woche ist Montag-basiert: Sonntag und Folge-Montag getrennt', () {
      final sun = shift('sun', day: sunday);
      final mon = shift('mon', day: nextMonday);
      final c = contract(weeklyMaxHours: 6);
      // Beide Schichten je exakt am Cap ihrer (verschiedenen) Wochen → 0.
      expect(
        plannedOvertimeMinutes(shift: mon, userShifts: [sun], contract: c),
        0,
      );
    });

    test('Kalendermonats-Grenze: Juli zählt nicht ins Juni-Konto', () {
      final juneA = shift('a', day: monday);
      final julyB = shift('b', day: july);
      expect(
        plannedOvertimeMinutes(
          shift: julyB,
          userShifts: [juneA],
          contract: contract(monthlyMaxHours: 6),
        ),
        0,
      );
    });

    test('Tie-Break bei gleicher Startzeit: id entscheidet stabil', () {
      final a = shift('a', day: monday); // gleiche Startzeit wie b
      final b = shift('b', day: monday, startHour: 8);
      final c = contract(weeklyMaxHours: 6);
      // Sortierung a < b (id) → b ist „später" und trägt die Überstunden.
      expect(plannedOvertimeMinutes(shift: b, userShifts: [a], contract: c), 360);
      expect(plannedOvertimeMinutes(shift: a, userShifts: [b], contract: c), 0);
    });
  });

  group('projectOvertimeByShiftId', () {
    test('projiziert je Nutzer unabhängig, chronologisch', () {
      final shifts = [
        shift('u1-b', day: wednesday, uid: 'u1'),
        shift('u1-a', day: monday, uid: 'u1'),
        shift('u2-a', day: monday, uid: 'u2'),
      ];
      final result = projectOvertimeByShiftId(
        assignedShifts: shifts,
        contractOf: (uid, at) =>
            uid == 'u1' ? contract(weeklyMaxHours: 10) : contract(),
      );
      expect(result['u1-a'], 0);
      expect(result['u1-b'], 120);
      expect(result['u2-a'], 0); // u2 ohne Caps
      expect(result, hasLength(3)); // auch 0-Werte enthalten
    });

    test('Vertragswechsel: je Schicht-Datum der passende Vertrag', () {
      final juneContract = contract(
        weeklyMaxHours: 6,
        validFrom: DateTime(2020, 1, 1),
        validUntil: DateTime(2026, 6, 30),
      );
      final julyContract = contract(
        weeklyMaxHours: 40,
        validFrom: DateTime(2026, 7, 1),
      );
      final shifts = [
        shift('june-1', day: monday),
        shift('june-2', day: tuesday), // Woche über 6h-Cap → Überstunden
        shift('july-1', day: july),
        shift('july-2', day: DateTime(2026, 7, 2)), // 40h-Cap → keine
      ];
      final result = projectOvertimeByShiftId(
        assignedShifts: shifts,
        contractOf: (uid, at) =>
            at.isBefore(DateTime(2026, 7, 1)) ? juneContract : julyContract,
      );
      expect(result['june-1'], 0);
      expect(result['june-2'], 360);
      expect(result['july-1'], 0);
      expect(result['july-2'], 0);
    });

    test('unbesetzte Schichten werden übersprungen', () {
      final open = shift('open', day: monday, uid: '');
      final result = projectOvertimeByShiftId(
        assignedShifts: [open, shift('a', day: monday)],
        contractOf: (uid, at) => contract(weeklyMaxHours: 40),
      );
      expect(result.containsKey('open'), isFalse);
      expect(result['a'], 0);
    });

    test('determinisch: gleicher Input → identisches Ergebnis', () {
      final shifts = [
        shift('b', day: wednesday),
        shift('a', day: monday),
        shift('c', day: friday),
      ];
      Map<String, int> once() => projectOvertimeByShiftId(
            assignedShifts: shifts,
            contractOf: (uid, at) => contract(weeklyMaxHours: 10),
          );
      expect(once(), once());
    });
  });
}
