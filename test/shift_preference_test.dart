import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/shift_preference.dart';

void main() {
  EmployeeShiftPreference sample() => const EmployeeShiftPreference(
        orgId: 'org-1',
        userId: 'u1',
        rules: [
          ShiftPreferenceRule(
            kind: PreferenceKind.prefer,
            weekdays: {1, 3},
            startMinute: 360,
            endMinute: 720,
            daypart: ShiftDaypart.morning,
          ),
          ShiftPreferenceRule(
            kind: PreferenceKind.block,
            weekdays: {6, 7},
            startMinute: 0,
            endMinute: 24 * 60,
          ),
          ShiftPreferenceRule(
            kind: PreferenceKind.avoid,
            startMinute: 1080,
            endMinute: 1440,
            daypart: ShiftDaypart.evening,
          ),
        ],
      );

  test('Firestore round-trip (camelCase) erhält alle Regeln', () {
    final original = sample();
    final restored = EmployeeShiftPreference.fromFirestore(
      'u1',
      original.toFirestoreMap(),
    );
    expect(restored.userId, 'u1');
    expect(restored.orgId, 'org-1');
    expect(restored.rules, hasLength(3));
    expect(restored.rules[0].kind, PreferenceKind.prefer);
    expect(restored.rules[0].weekdays, {1, 3});
    expect(restored.rules[0].startMinute, 360);
    expect(restored.rules[0].daypart, ShiftDaypart.morning);
    expect(restored.rules[1].kind, PreferenceKind.block);
    expect(restored.rules[1].weekdays, {6, 7});
    expect(restored.rules[2].kind, PreferenceKind.avoid);
    expect(restored.rules[2].daypart, ShiftDaypart.evening);
  });

  test('Lokaler round-trip (snake_case) erhält alle Regeln', () {
    final original = sample();
    final restored = EmployeeShiftPreference.fromMap(original.toMap());
    expect(restored.rules, hasLength(3));
    expect(restored.rules[0].weekdays, {1, 3});
    expect(restored.rules[1].kind, PreferenceKind.block);
    expect(restored.rules[2].kind, PreferenceKind.avoid);
    expect(restored.rules[2].startMinute, 1080);
  });

  test('Enum fromValue mit Default-Zweig (unbekannt → prefer / null)', () {
    expect(PreferenceKindX.fromValue('quatsch'), PreferenceKind.prefer);
    expect(PreferenceKindX.fromValue('block'), PreferenceKind.block);
    expect(ShiftDaypartX.fromValue('quatsch'), isNull);
    expect(ShiftDaypartX.fromValue('evening'), ShiftDaypart.evening);
  });

  test('isBlocked: Wochentag + Zeitfenster-Überlappung', () {
    final p = EmployeeShiftPreference(
      orgId: 'org-1',
      userId: 'u1',
      rules: [
        ShiftPreferenceRule(
          kind: PreferenceKind.block,
          weekdays: const {1},
          startMinute: ShiftDaypart.morning.startMinute,
          endMinute: ShiftDaypart.morning.endMinute,
        ),
      ],
    );
    // Montag (1) 08:00–14:00 überlappt Vormittag → gesperrt.
    expect(p.isBlocked(1, 8 * 60, 14 * 60), isTrue);
    // Dienstag (2) gleiche Zeit → nicht gesperrt (Wochentag passt nicht).
    expect(p.isBlocked(2, 8 * 60, 14 * 60), isFalse);
    // Montag 14:00–18:00 (Nachmittag) → keine Überlappung mit Vormittag.
    expect(p.isBlocked(1, 14 * 60, 18 * 60), isFalse);
  });

  test('softScore: prefer positiv, avoid negativ, neutral 0', () {
    final prefer = EmployeeShiftPreference(orgId: 'o', userId: 'u', rules: [
      ShiftPreferenceRule(
        kind: PreferenceKind.prefer,
        startMinute: ShiftDaypart.morning.startMinute,
        endMinute: ShiftDaypart.morning.endMinute,
      ),
    ]);
    final avoid = EmployeeShiftPreference(orgId: 'o', userId: 'u', rules: [
      ShiftPreferenceRule(
        kind: PreferenceKind.avoid,
        startMinute: ShiftDaypart.morning.startMinute,
        endMinute: ShiftDaypart.morning.endMinute,
      ),
    ]);
    expect(prefer.softScore(1, 6 * 60, 12 * 60), greaterThan(0));
    expect(avoid.softScore(1, 6 * 60, 12 * 60), lessThan(0));
    // Abendschicht ohne Überlappung mit Vormittag → neutral.
    expect(prefer.softScore(1, 18 * 60, 22 * 60), 0);
  });

  test('leere Vorgaben sind neutral', () {
    final empty = EmployeeShiftPreference.empty('o', 'u');
    expect(empty.isEmpty, isTrue);
    expect(empty.isBlocked(1, 8 * 60, 14 * 60), isFalse);
    expect(empty.softScore(1, 8 * 60, 14 * 60), 0);
  });
}
