import 'package:collection/collection.dart';

import '../models/employment_contract.dart';
import '../models/shift.dart';

/// **Pure** Projektion geplanter Überstunden (Plan
/// `plan/schichtplaner-verbesserung.md`, E1/W2).
///
/// „Geplante Überstunden" einer Schicht = der Anteil ihrer **Netto-Minuten**
/// (Dauer − Pause), der die Vertrags-Maximalstunden (`weeklyMaxHours` /
/// `monthlyMaxHours`) überschreitet, wenn man alle Schichten des Nutzers
/// **chronologisch** kumuliert (Sortierung: `startTime`, Tie-Break `id`).
///
/// Die chronologische Zurechnung ist **stabil und reihenfolgeunabhängig**:
/// egal in welcher Reihenfolge Schichten angelegt oder übergeben werden, die
/// Überstunden „gehören" immer den zeitlich **letzten** Schichten der Woche
/// bzw. des Monats — genau denen, die das Fass zum Überlaufen bringen.
///
/// - **Woche** = Montag-basiertes Bucket (gleiche Semantik wie
///   `ShiftAutoAssigner._weekLabel`, ohne ISO-Wochennummern-Sonderfälle).
/// - **Monat** = Kalendermonat.
/// - Überschreitung = `max(Wochen-Überschuss, Monats-Überschuss)` der
///   kumulierten Nettominuten **nach** dieser Schicht minus Cap, geklemmt auf
///   `[0, Schicht-Netto]`.
/// - Vertrag `null` oder ohne Caps → immer `0`.
///
/// Kein IO, kein `DateTime.now()`, kein Zufall → deterministisch und offline
/// testbar.

/// Geplante Überstunden-Minuten von [shift] gegen [contract].
///
/// [userShifts] sind die **übrigen** Schichten desselben Nutzers, die zum
/// Stundenkonto zählen. **Der Aufrufer filtert**: nur zugewiesene
/// (`!isUnassigned`), nicht stornierte (`status != ShiftStatus.cancelled`)
/// Schichten desselben Nutzers übergeben. [shift] selbst darf enthalten sein
/// (wird über Identität bzw. gleiche `id` dedupliziert), muss aber nicht.
///
/// Ergebnis geklemmt auf `[0, Netto-Minuten von shift]`.
int plannedOvertimeMinutes({
  required Shift shift,
  required Iterable<Shift> userShifts,
  required EmploymentContract? contract,
}) {
  if (contract == null ||
      (contract.monthlyMaxHours == null && contract.weeklyMaxHours == null)) {
    return 0;
  }

  final all = <Shift>[
    for (final s in userShifts)
      if (!identical(s, shift) &&
          (shift.id == null ||
              shift.id!.trim().isEmpty ||
              s.id != shift.id))
        s,
    shift,
  ];
  // Stabile chronologische Sortierung (mergeSort erhält bei exakt gleichem
  // Start + gleicher id die Eingabereihenfolge → deterministisch).
  mergeSort<Shift>(all, compare: _chronoOrder);

  final monthCum = <String, int>{};
  final weekCum = <String, int>{};
  for (final s in all) {
    final net = _netMinutes(s);
    final mKey = _monthLabel(s.startTime);
    final wKey = _weekLabel(s.startTime);
    final monthAfter = monthCum[mKey] = (monthCum[mKey] ?? 0) + net;
    final weekAfter = weekCum[wKey] = (weekCum[wKey] ?? 0) + net;
    if (identical(s, shift)) {
      return _overshootMinutes(
        monthAfter: monthAfter,
        weekAfter: weekAfter,
        monthlyMaxHours: contract.monthlyMaxHours,
        weeklyMaxHours: contract.weeklyMaxHours,
        netMinutes: net,
      );
    }
  }
  return 0; // unerreichbar (shift ist immer Teil von all)
}

/// Batch-Projektion: geplante Überstunden-Minuten je Schicht-ID.
///
/// [assignedShifts] = alle zählenden Schichten (typisch: bestehende besetzte
/// + neu vorgeschlagene). **Der Aufrufer filtert** stornierte Schichten
/// heraus; Schichten ohne Nutzer (`isUnassigned`) werden übersprungen, da sie
/// keinem Stundenkonto zurechenbar sind. Schicht-IDs sollten eindeutig sein.
///
/// [contractOf] liefert den am jeweiligen Schicht-Datum aktiven Vertrag des
/// Nutzers (Vertragswechsel innerhalb des Horizonts werden so je Schicht
/// korrekt bewertet). `null` bzw. Verträge ohne Caps ergeben `0`.
///
/// Ergebnis enthält einen Eintrag für **jede** Schicht mit nicht-leerer `id`
/// (auch mit Wert `0`), damit Lookups nie zwischen „nicht projiziert" und
/// „keine Überstunden" unterscheiden müssen.
Map<String, int> projectOvertimeByShiftId({
  required List<Shift> assignedShifts,
  required EmploymentContract? Function(String userId, DateTime at) contractOf,
}) {
  final byUser = <String, List<Shift>>{};
  for (final shift in assignedShifts) {
    if (shift.isUnassigned) continue;
    (byUser[shift.userId] ??= <Shift>[]).add(shift);
  }

  final result = <String, int>{};
  for (final uid in byUser.keys.sorted((a, b) => a.compareTo(b))) {
    final shifts = byUser[uid]!;
    mergeSort<Shift>(shifts, compare: _chronoOrder);

    final monthCum = <String, int>{};
    final weekCum = <String, int>{};
    for (final shift in shifts) {
      final net = _netMinutes(shift);
      final mKey = _monthLabel(shift.startTime);
      final wKey = _weekLabel(shift.startTime);
      final monthAfter = monthCum[mKey] = (monthCum[mKey] ?? 0) + net;
      final weekAfter = weekCum[wKey] = (weekCum[wKey] ?? 0) + net;

      final id = shift.id;
      if (id == null || id.trim().isEmpty) continue;
      final contract = contractOf(uid, shift.startTime);
      result[id] = _overshootMinutes(
        monthAfter: monthAfter,
        weekAfter: weekAfter,
        monthlyMaxHours: contract?.monthlyMaxHours,
        weeklyMaxHours: contract?.weeklyMaxHours,
        netMinutes: net,
      );
    }
  }
  return result;
}

/// `max(Wochen-Überschuss, Monats-Überschuss)` nach der Schicht, geklemmt auf
/// `[0, netMinutes]`. Caps `null`/`<= 0` zählen nicht.
int _overshootMinutes({
  required int monthAfter,
  required int weekAfter,
  required double? monthlyMaxHours,
  required double? weeklyMaxHours,
  required int netMinutes,
}) {
  var over = 0.0;
  if (monthlyMaxHours != null && monthlyMaxHours > 0) {
    final capMin = monthlyMaxHours * 60;
    if (monthAfter > capMin && monthAfter - capMin > over) {
      over = monthAfter - capMin;
    }
  }
  if (weeklyMaxHours != null && weeklyMaxHours > 0) {
    final capMin = weeklyMaxHours * 60;
    if (weekAfter > capMin && weekAfter - capMin > over) {
      over = weekAfter - capMin;
    }
  }
  if (over <= 0 || netMinutes <= 0) return 0;
  final minutes = over.round();
  return minutes > netMinutes ? netMinutes : (minutes < 0 ? 0 : minutes);
}

int _netMinutes(Shift shift) =>
    shift.endTime.difference(shift.startTime).inMinutes -
    shift.breakMinutes.round();

int _chronoOrder(Shift a, Shift b) {
  final byStart = a.startTime.compareTo(b.startTime);
  if (byStart != 0) return byStart;
  return (a.id ?? '').compareTo(b.id ?? '');
}

String _monthLabel(DateTime date) => '${date.year}-${date.month}';

/// Montag-basiertes Wochen-Bucket (Spiegel von `ShiftAutoAssigner._weekLabel`).
String _weekLabel(DateTime date) {
  final monday = DateTime(date.year, date.month, date.day)
      .subtract(Duration(days: date.weekday - 1));
  return '${monday.year}-${monday.month}-${monday.day}';
}
