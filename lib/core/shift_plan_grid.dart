import '../models/shift.dart';

/// Baut aus einer Schichtliste eine **nach Standort getrennte Matrix**
/// (Zeilen = Mitarbeiter, Spalten = Kalendertage) — das Format des echten
/// Schichtplans (eine Sektion je Laden). Wird von CSV- und PDF-Export geteilt,
/// damit beide identisch aufgebaut sind. Pure/testbar (kein intl, kein IO).
class ShiftPlanGrid {
  ShiftPlanGrid._();

  /// Zeile für unbesetzte Schichten.
  static const String unassignedLabel = 'Unbesetzt';

  static ShiftPlanGridResult build({
    required List<Shift> shifts,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    // Tage = jeder Kalendertag in [rangeStart, rangeEnd).
    final days = <DateTime>[];
    var cursor = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final end = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
    while (cursor.isBefore(end)) {
      days.add(cursor);
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
    // Fallback: leerer/ungültiger Bereich → Tage aus den Schichten ableiten.
    if (days.isEmpty) {
      final derived = shifts
          .map((s) =>
              DateTime(s.startTime.year, s.startTime.month, s.startTime.day))
          .toSet()
          .toList()
        ..sort();
      days.addAll(derived);
    }

    final dayIndexByKey = <int, int>{};
    for (var i = 0; i < days.length; i++) {
      dayIndexByKey[_dayKey(days[i])] = i;
    }
    int dayIndex(DateTime d) => dayIndexByKey[_dayKey(d)] ?? -1;

    // Gruppieren nach Standort (Name → Fallback location → „Ohne Standort").
    final bySite = <String, List<Shift>>{};
    for (final shift in shifts) {
      bySite.putIfAbsent(_siteLabel(shift), () => <Shift>[]).add(shift);
    }

    String cellFor(List<Shift> list, int di) {
      final dayShifts = list.where((s) => dayIndex(s.startTime) == di).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      if (dayShifts.isEmpty) {
        return '';
      }
      return dayShifts
          .map((s) => '${_hm(s.startTime)}–${_hm(s.endTime)}')
          .join(' / ');
    }

    final groups = <ShiftPlanSiteGroup>[];
    final siteNames = bySite.keys.toList()..sort();
    for (final siteName in siteNames) {
      final siteShifts = bySite[siteName]!;
      final byEmployee = <String, List<Shift>>{};
      final unassigned = <Shift>[];
      for (final shift in siteShifts) {
        if (shift.isUnassigned || shift.employeeName.trim().isEmpty) {
          unassigned.add(shift);
        } else {
          byEmployee
              .putIfAbsent(shift.employeeName.trim(), () => <Shift>[])
              .add(shift);
        }
      }
      final rows = <ShiftPlanRow>[];
      final employees = byEmployee.keys.toList()..sort();
      for (final employee in employees) {
        final list = byEmployee[employee]!;
        rows.add(ShiftPlanRow(
          label: employee,
          cells: [for (var i = 0; i < days.length; i++) cellFor(list, i)],
          totalHours: list.fold<double>(0, (sum, s) => sum + s.workedHours),
        ));
      }
      if (unassigned.isNotEmpty) {
        rows.add(ShiftPlanRow(
          label: unassignedLabel,
          cells: [for (var i = 0; i < days.length; i++) cellFor(unassigned, i)],
          totalHours:
              unassigned.fold<double>(0, (sum, s) => sum + s.workedHours),
        ));
      }
      groups.add(ShiftPlanSiteGroup(siteName: siteName, rows: rows));
    }

    return ShiftPlanGridResult(days: days, sites: groups);
  }

  static String _siteLabel(Shift shift) {
    final name = shift.siteName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    final location = shift.location?.trim();
    if (location != null && location.isNotEmpty) {
      return location;
    }
    return 'Ohne Standort';
  }

  static int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class ShiftPlanGridResult {
  const ShiftPlanGridResult({required this.days, required this.sites});

  final List<DateTime> days;
  final List<ShiftPlanSiteGroup> sites;

  bool get isEmpty => sites.isEmpty;
}

class ShiftPlanSiteGroup {
  const ShiftPlanSiteGroup({required this.siteName, required this.rows});

  final String siteName;
  final List<ShiftPlanRow> rows;
}

class ShiftPlanRow {
  const ShiftPlanRow({
    required this.label,
    required this.cells,
    required this.totalHours,
  });

  final String label;
  final List<String> cells;
  final double totalHours;
}
