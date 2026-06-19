// Teil von home_screen.dart (split-home-screen-god-file, Strangler Schritt 2).
//
// Reine, BuildContext-freie Datums-/Stunden-/Format-Helfer des Home-Screens.
// Als 'part' gehalten: file-private Sichtbarkeit bleibt erhalten, keine
// Aufrufstellen muessen geaendert werden, und die Library-Imports der
// Hauptdatei (Shift/WorkEntry/DateFormat/isSameDay) gelten weiter.
part of 'home_screen.dart';


bool _isPlannedShift(Shift shift) {
  return !shift.isUnassigned && shift.status != ShiftStatus.cancelled;
}

int _calendarDayKey(DateTime value) {
  return value.year * 10000 + value.month * 100 + value.day;
}

double _sumShiftHours(Iterable<Shift> shifts) {
  return shifts.fold<double>(0, (sum, shift) => sum + shift.workedHours);
}

double _sumEntryHours(Iterable<WorkEntry> entries) {
  return entries.fold<double>(0, (sum, entry) => sum + entry.workedHours);
}

String _formatSignedHours(double value) {
  final prefix = value > 0.05 ? '+' : '';
  return '$prefix${value.toStringAsFixed(1)} h';
}

List<Shift> _shiftsForDay(Iterable<Shift> shifts, DateTime day) {
  return shifts
      .where(
          (shift) => _isPlannedShift(shift) && isSameDay(shift.startTime, day))
      .toList(growable: false)
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
}

Map<String, List<WorkEntry>> _entriesBySourceShiftId(
    Iterable<WorkEntry> entries) {
  final map = <String, List<WorkEntry>>{};
  for (final entry in entries) {
    final shiftId = entry.sourceShiftId?.trim();
    if (shiftId == null || shiftId.isEmpty) {
      continue;
    }
    (map[shiftId] ??= <WorkEntry>[]).add(entry);
  }
  for (final linkedEntries in map.values) {
    linkedEntries.sort((a, b) => a.startTime.compareTo(b.startTime));
  }
  return map;
}

String _formatUserError(Object error) {
  final raw = error.toString().trim();
  if (raw.startsWith('Bad state: ')) {
    return raw.substring('Bad state: '.length).trim();
  }
  if (raw.startsWith('Exception: ')) {
    return raw.substring('Exception: '.length).trim();
  }
  return raw;
}

String _formatClockDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '${hours}h:${minutes}min';
}

String _formatShiftWindow(Shift shift) {
  return '${DateFormat('HH:mm', 'de_DE').format(shift.startTime)} - '
      '${DateFormat('HH:mm', 'de_DE').format(shift.endTime)}';
}

String _formatClockBreakLabel(
  WorkProvider provider,
  WorkEntry? lastClockEntry,
) {
  if (lastClockEntry != null) {
    return 'Pause: ${lastClockEntry.breakMinutes.toStringAsFixed(0)} min';
  }
  return 'Auto-Pause ab ${provider.settings.autoBreakAfterMinutes} min';
}
