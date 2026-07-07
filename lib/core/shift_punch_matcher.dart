// lib/core/shift_punch_matcher.dart

import '../models/shift.dart';

/// Z1 (plan/zeit-schichtbindung-freigabe.md): pures, deterministisches
/// Schicht-Matching fürs **Einstempeln**. Zeit wird injiziert (kein `now()`),
/// daher offline testbar (`test/shift_punch_matcher_test.dart`).
///
/// [kommen] matcht eine Schicht des Nutzers, wenn `kommen ∈ [start − karenz, end]`
/// (früher Antritt bis [karenz] erlaubt; nach Schichtende kein Match). Beim
/// Einstempeln ist nur `kommen` bekannt → **Overlap-Regel** (nicht Coverage;
/// Coverage gilt nur für die manuelle Erfassung mit bekanntem Ende).
///
/// Kandidaten: `shift.userId == userId`, nicht `cancelled`, nicht unassigned.
/// Tie-Breaker (stabil, reihenfolgeunabhängig): (1) kleinste |kommen − start|,
/// (2) frühere `startTime`, (3) lexikografisch kleinste `id`.
///
/// Vergleiche in **lokaler** Zeit (Modelle normalisieren via `toLocal`);
/// Über-Mitternacht-Schichten werden über die absoluten `DateTime`-Grenzen
/// verglichen, nicht über die Tageskomponente.
Shift? matchShiftForPunch(
  List<Shift> shifts,
  DateTime kommen, {
  required String userId,
  Duration karenz = const Duration(minutes: 15),
}) {
  final candidates = shifts
      .where((shift) =>
          shift.userId == userId &&
          shift.status != ShiftStatus.cancelled &&
          !shift.isUnassigned &&
          !kommen.isBefore(shift.startTime.subtract(karenz)) &&
          !kommen.isAfter(shift.endTime))
      .toList();
  if (candidates.isEmpty) {
    return null;
  }
  candidates.sort((a, b) {
    final da = kommen.difference(a.startTime).inMinutes.abs();
    final db = kommen.difference(b.startTime).inMinutes.abs();
    if (da != db) return da.compareTo(db);
    final byStart = a.startTime.compareTo(b.startTime);
    if (byStart != 0) return byStart;
    return (a.id ?? '').compareTo(b.id ?? '');
  });
  return candidates.first;
}
