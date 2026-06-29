/// Reine Datums-/Listen-Berechnungen des Schichtplaner-Boards
/// (split-shift-planner-god-file, Strangler-Fig Schritt 1). Bewusst
/// BuildContext-frei und ohne Provider-/Widget-Bezug, damit sie isoliert
/// unit-getestet werden koennen (test/planner_logic_test.dart) – statt tief im
/// 8000-Zeilen-God-File begraben zu liegen.
library;

/// Alle Tage im halboffenen Intervall [start, end) (jeweils 1-Tages-Schritte).
List<DateTime> rangeDays(DateTime start, DateTime end) {
  final days = <DateTime>[];
  var cursor = start;
  while (cursor.isBefore(end)) {
    days.add(cursor);
    cursor = cursor.add(const Duration(days: 1));
  }
  return days;
}

/// Teilt [days] in Bloecke der Groesse [size] (der letzte Block kann kuerzer
/// sein). Wird fuer das Wochen-Raster der Monatsansicht genutzt.
List<List<DateTime>> chunkDays(List<DateTime> days, int size) {
  final chunks = <List<DateTime>>[];
  for (var index = 0; index < days.length; index += size) {
    final end = (index + size < days.length) ? index + size : days.length;
    chunks.add(days.sublist(index, end));
  }
  return chunks;
}

/// Das vollstaendige Kalenderraster (montagsbeginnend) fuer den Monat von
/// [visibleDate] inkl. fuehrender/abschliessender Tage der Nachbarmonate, sodass
/// das Raster volle Wochen umfasst.
List<DateTime> calendarMonthGridDays(DateTime visibleDate) {
  final firstOfMonth = DateTime(visibleDate.year, visibleDate.month, 1);
  final leadingDays = firstOfMonth.weekday - DateTime.monday;
  final gridStart = firstOfMonth.subtract(Duration(days: leadingDays));
  final lastOfMonth = DateTime(visibleDate.year, visibleDate.month + 1, 0);
  final trailingDays = DateTime.daysPerWeek - lastOfMonth.weekday;
  final gridEndExclusive = DateTime(
    lastOfMonth.year,
    lastOfMonth.month,
    lastOfMonth.day + 1,
  ).add(Duration(days: trailingDays));
  return rangeDays(gridStart, gridEndExclusive);
}

/// Stabiler, sortierbarer Tagesschluessel (YYYYMMDD als int) zum Bucketing von
/// Schichten pro Tag.
int dayKey(DateTime day) => day.year * 10000 + day.month * 100 + day.day;

/// Wie viele Schicht-Kacheln in eine Monats-Tageszelle der nutzbaren Höhe
/// [available] passen, ohne dass die innere Column überläuft.
///
/// Reine Geometrie (kein BuildContext), damit der Overflow-Schutz der
/// Monatszellen isoliert testbar bleibt: passt nicht alles, wird eine Zeile für
/// den „+N weitere/mehr"-Hinweis reserviert und entsprechend weniger Kacheln
/// gezeigt. [tileExtent]/[tileSpacing]/[moreHintExtent] sind die festen
/// Layout-Maße der jeweiligen Zelle (Kachelhöhe, Abstand, Hinweiszeile).
int monthCellVisibleShiftCount({
  required double available,
  required int total,
  required double tileExtent,
  required double tileSpacing,
  required double moreHintExtent,
}) {
  if (total <= 0 || available <= 0) {
    return 0;
  }
  int fit(double space) => space <= 0
      ? 0
      : ((space + tileSpacing) / (tileExtent + tileSpacing)).floor();
  final capacity = fit(available);
  if (total <= capacity) {
    return total;
  }
  // Nicht alles passt -> eine Zeile für den „+N"-Hinweis (inkl. Abstand davor)
  // abziehen und neu berechnen.
  final withMore = fit(available - moreHintExtent - tileSpacing);
  return withMore.clamp(0, total);
}

/// ISO-8601-Kalenderwoche (1..53) von [date].
///
/// Rechnet bewusst in UTC: die Tagesdifferenz über `Duration`/`inDays` würde
/// sonst eine Sommerzeit-Umstellung mitzählen und die Woche an manchen Daten um
/// 1 verfehlen (z. B. ergab die lokale Variante für 2026-07-01 fälschlich KW 26
/// statt KW 27). Da der Rückgabewert ein int ist, ändert sich downstream nichts.
int isoWeekNumber(DateTime date) {
  final normalized = DateTime.utc(date.year, date.month, date.day);
  final thursday =
      normalized.add(Duration(days: DateTime.thursday - normalized.weekday));
  final firstThursday = DateTime.utc(thursday.year, 1, 4);
  final firstWeekThursday = firstThursday
      .add(Duration(days: DateTime.thursday - firstThursday.weekday));
  return 1 + (thursday.difference(firstWeekThursday).inDays ~/ 7);
}
