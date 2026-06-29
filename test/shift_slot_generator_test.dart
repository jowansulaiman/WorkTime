import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/shift_slot_generator.dart';
import 'package:worktime_app/models/org_settings.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/site_schedule.dart';

void main() {
  // Montag (deterministisch, unabhängig vom Wall-Clock).
  final monday = DateTime(2026, 6, 1).subtract(
    Duration(days: DateTime(2026, 6, 1).weekday - 1),
  );

  SiteDefinition site({
    required List<WeekdayHours> hours,
    List<StaffingDemand> demands = const [],
    String id = 'site-1',
    String name = 'Laden',
  }) =>
      SiteDefinition(
        id: id,
        orgId: 'org-1',
        name: name,
        weekdayHours: hours,
        staffingDemands: demands,
      );

  WeekdayHours mondayHours(List<TimeWindow> windows) =>
      WeekdayHours(weekday: DateTime.monday, windows: windows);

  TimeWindow win(int startHour, int endHour) =>
      TimeWindow(startMinute: startHour * 60, endMinute: endHour * 60);

  List<Shift> generate(
    SiteDefinition site, {
    OrgSettings? settings,
    List<Shift> existing = const [],
    DateTime? start,
    DateTime? end,
  }) {
    var counter = 0;
    return ShiftSlotGenerator(
      sites: [site],
      rangeStart: start ?? monday,
      rangeEnd: end ?? monday.add(const Duration(days: 1)),
      settings: settings ?? OrgSettings.defaults('org-1'),
      existingShifts: existing,
      orgId: 'org-1',
      seriesId: 'series-1',
      shiftIdFactory: () => 'shift-${counter++}',
    ).generate();
  }

  test('1. Slot aus Öffnungszeit (kein Bedarf) → eine 8h-Brutto-Schicht', () {
    final shifts = generate(site(hours: [mondayHours([win(9, 17)])]));
    expect(shifts, hasLength(1));
    final shift = shifts.single;
    expect(shift.isUnassigned, isTrue);
    expect(shift.siteId, 'site-1');
    expect(shift.startTime.hour, 9);
    expect(shift.endTime.hour, 17);
    expect(shift.breakMinutes, 30);
    expect(shift.seriesId, 'series-1');
    expect(shift.status, ShiftStatus.planned);
  });

  test('2. Mehrere Zeitfenster/Tag → zwei Slots, Mittagslücke frei', () {
    final shifts = generate(site(hours: [
      mondayHours([win(9, 13), win(15, 19)]),
    ]));
    expect(shifts, hasLength(2));
    expect(shifts[0].startTime.hour, 9);
    expect(shifts[0].endTime.hour, 13);
    expect(shifts[1].startTime.hour, 15);
    expect(shifts[1].endTime.hour, 19);
  });

  test('3. Bedarf > 1 → drei unbesetzte Schichten im Fenster', () {
    final shifts = generate(site(
      hours: [mondayHours([win(9, 17)])],
      demands: [
        StaffingDemand(
          weekday: DateTime.monday,
          window: win(9, 17),
          requiredCount: 3,
        ),
      ],
    ));
    expect(shifts, hasLength(3));
    expect(shifts.every((s) => s.isUnassigned), isTrue);
    expect(shifts.every((s) => s.startTime.hour == 9), isTrue);
  });

  test('4. Lange Öffnung 08–22 → zwei Schichten, kein Mini-Rest-Slot', () {
    final shifts = generate(site(hours: [mondayHours([win(8, 22)])]));
    expect(shifts, hasLength(2));
    expect(shifts[0].startTime.hour, 8);
    expect(shifts[0].endTime.hour, 16); // 8h Brutto
    expect(shifts[1].startTime.hour, 16);
    expect(shifts[1].endTime.hour, 22); // 6h Rest (>50% → eigener Slot)
  });

  test('5. Quali aus Bedarf landet auf der Schicht', () {
    final shifts = generate(site(
      hours: [mondayHours([win(9, 17)])],
      demands: [
        StaffingDemand(
          weekday: DateTime.monday,
          window: win(9, 17),
          requiredCount: 1,
          requiredQualificationIds: const ['kasse'],
        ),
      ],
    ));
    expect(shifts.single.requiredQualificationIds, ['kasse']);
  });

  test('6. Stabile IDs aus dem injizierten Factory', () {
    final shifts = generate(site(
      hours: [mondayHours([win(9, 17)])],
      demands: [
        StaffingDemand(
          weekday: DateTime.monday,
          window: win(9, 17),
          requiredCount: 2,
        ),
      ],
    ));
    expect(shifts.map((s) => s.id), ['shift-0', 'shift-1']);
    expect(shifts.every((s) => (s.id ?? '').isNotEmpty), isTrue);
  });

  test('7. Idempotenz count-aware: vorhandene Schicht reduziert Anzahl', () {
    final existing = Shift(
      id: 'existing-1',
      orgId: 'org-1',
      userId: 'u1',
      employeeName: 'Anna',
      title: 'Laden',
      startTime: monday.add(const Duration(hours: 9)),
      endTime: monday.add(const Duration(hours: 17)),
      siteId: 'site-1',
      siteName: 'Laden',
    );
    final shifts = generate(
      site(
        hours: [mondayHours([win(9, 17)])],
        demands: [
          StaffingDemand(
            weekday: DateTime.monday,
            window: win(9, 17),
            requiredCount: 3,
          ),
        ],
      ),
      existing: [existing],
    );
    expect(shifts, hasLength(2)); // 3 benötigt − 1 vorhanden
  });

  test('8. Determinismus: gleicher Input → identische Ausgabe', () {
    final s = site(hours: [mondayHours([win(8, 22)])]);
    final a = generate(s);
    final b = generate(s);
    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(a[i].startTime, b[i].startTime);
      expect(a[i].endTime, b[i].endTime);
      expect(a[i].siteId, b[i].siteId);
      expect(a[i].breakMinutes, b[i].breakMinutes);
      expect(a[i].id, b[i].id);
    }
  });

  test('9. Kein weekdayHours → leere Ausgabe', () {
    final shifts = generate(site(hours: const []));
    expect(shifts, isEmpty);
  });

  test('10. Langes Einzelfenster wird unter die Tages-Nettogrenze gesplittet',
      () {
    // 08:00–19:30 (690 min) würde ohne Deckel als EIN Slot (netto 645 > 600)
    // erzeugt und wäre dann nie compliance-fähig. Erwartung: gesplittet, jeder
    // Slot netto <= 600.
    final shifts = generate(site(hours: [
      mondayHours([
        const TimeWindow(startMinute: 8 * 60, endMinute: 19 * 60 + 30),
      ]),
    ]));
    expect(shifts.length, greaterThanOrEqualTo(2));
    for (final shift in shifts) {
      final net = shift.endTime.difference(shift.startTime).inMinutes -
          shift.breakMinutes.round();
      expect(net, lessThanOrEqualTo(600));
    }
  });
}
