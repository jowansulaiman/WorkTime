import 'dart:math' as math;

import '../models/pos_receipt.dart';

/// **P3.1 — Umsatzbasierte Besetzung (der einzigartige POS×Personal-Hebel).**
/// Baut aus den Kassenbelegen ein **anonymes** Beleg-pro-Stunde-Profil je
/// (Wochentag, Stunde) eines Standorts und leitet daraus einen Besetzungs-
/// Vorschlag ab („Fr 16–19 = Stoßzeit → 2. Kraft"). Grundlage ist die reine
/// **Beleg-Anzahl** (kein Personenbezug, keine unsicheren Geldfelder).
///
/// **Pure / offline-testbar.** Wochentag/Stunde kommen aus `transactionDate`
/// (Ladens-Wanduhr; DE-Zeitzone angenommen). Der Vorschlag ist ein **Richtwert**
/// zum Übernehmen in `StaffingDemand.requiredCount` — nie automatisch gesetzt.
class HourlyDemand {
  const HourlyDemand({
    required this.weekday,
    required this.hour,
    required this.totalReceipts,
    required this.sampleDays,
  });

  /// `DateTime.monday`..`DateTime.sunday` (1..7).
  final int weekday;

  /// Stunde 0..23 (Ladens-Wanduhr).
  final int hour;

  /// Belege insgesamt in dieser Wochentag-Stunde über das Fenster.
  final int totalReceipts;

  /// Anzahl beobachteter Kalendertage dieses Wochentags (Mittelungs-Nenner).
  final int sampleDays;

  /// Durchschnittliche Belege in dieser Stunde an einem typischen [weekday].
  double get avgReceipts => sampleDays <= 0 ? 0 : totalReceipts / sampleDays;
}

class StaffingProfile {
  const StaffingProfile({
    required this.siteId,
    required this.cells,
    required this.receiptsPerStaffPerHour,
  });

  final String siteId;

  /// Wochentag-Stunden mit Aktivität (avgReceipts > 0).
  final List<HourlyDemand> cells;

  /// Kapazitätsannahme: wie viele Belege eine Kraft je Stunde bedient.
  final int receiptsPerStaffPerHour;

  HourlyDemand? cellAt(int weekday, int hour) {
    for (final c in cells) {
      if (c.weekday == weekday && c.hour == hour) return c;
    }
    return null;
  }

  /// Spitzen-Durchschnitt über alle Zellen (zum Skalieren der Heatmap).
  double get peakAvgReceipts =>
      cells.fold<double>(0, (m, c) => math.max(m, c.avgReceipts));

  /// Vorgeschlagene gleichzeitige Besetzung für [weekday] im Zeitfenster
  /// [startMinute]..[endMinute] (Minuten ab Mitternacht): getrieben von der
  /// **Stoßzeit-Stunde** im Fenster (max. Stunden-Schnitt ÷ Kapazität), mind. 1.
  int suggestRequiredCount({
    required int weekday,
    required int startMinute,
    required int endMinute,
  }) {
    final startHour = startMinute ~/ 60;
    final endHour = ((endMinute - 1) ~/ 60).clamp(startHour, 23);
    var peak = 0.0;
    for (var h = startHour; h <= endHour; h++) {
      final cell = cellAt(weekday, h);
      if (cell != null) peak = math.max(peak, cell.avgReceipts);
    }
    if (peak <= 0) return 1;
    return math.max(1, (peak / receiptsPerStaffPerHour).ceil());
  }
}

String _dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Berechnet das [StaffingProfile] aus Umsatzbelegen (`isRevenue`, kein
/// training). [receiptsPerStaffPerHour] = Kapazitätsannahme je Kraft.
StaffingProfile computeStaffingProfile({
  required String siteId,
  required List<PosReceipt> receipts,
  int receiptsPerStaffPerHour = 30,
}) {
  // weekday -> hour -> count
  final counts = <int, Map<int, int>>{};
  // weekday -> set of distinct dates with activity (Mittelungs-Nenner)
  final daysPerWeekday = <int, Set<String>>{};

  for (final r in receipts) {
    if (!r.isRevenue || r.training) continue;
    final tx = r.transactionDate;
    if (tx == null) continue;
    final weekday = tx.weekday;
    final hour = tx.hour;
    (counts[weekday] ??= <int, int>{}).update(hour, (v) => v + 1,
        ifAbsent: () => 1);
    (daysPerWeekday[weekday] ??= <String>{}).add(_dateKey(tx));
  }

  final cells = <HourlyDemand>[];
  for (final weekdayEntry in counts.entries) {
    final weekday = weekdayEntry.key;
    final sampleDays = daysPerWeekday[weekday]?.length ?? 0;
    for (final hourEntry in weekdayEntry.value.entries) {
      cells.add(HourlyDemand(
        weekday: weekday,
        hour: hourEntry.key,
        totalReceipts: hourEntry.value,
        sampleDays: sampleDays,
      ));
    }
  }
  cells.sort((a, b) {
    final c = a.weekday.compareTo(b.weekday);
    return c != 0 ? c : a.hour.compareTo(b.hour);
  });

  return StaffingProfile(
    siteId: siteId,
    cells: cells,
    receiptsPerStaffPerHour: math.max(1, receiptsPerStaffPerHour),
  );
}
