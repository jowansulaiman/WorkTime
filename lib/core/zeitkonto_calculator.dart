import '../models/sollzeit_profile.dart';
import '../models/work_entry.dart';

/// Ergebnis eines Monats-Zeitkontos (Soll/Ist/Saldo) in Minuten.
class ZeitkontoResult {
  const ZeitkontoResult({
    required this.sollMinutes,
    required this.istMinutes,
    required this.hasSollProfile,
  });

  /// Vertragliches Monatssoll in Minuten.
  final int sollMinutes;

  /// Tatsächlich gearbeitete Zeit (Ist) in Minuten.
  final int istMinutes;

  /// Ob ein gültiges [SollzeitProfile] aufgelöst werden konnte. `false` ⇒
  /// [sollMinutes] ist 0, weil kein Soll hinterlegt ist (nicht: Soll = 0).
  final bool hasSollProfile;

  /// Saldo (Ist − Soll): positiv = Überstunden, negativ = Minusstunden.
  int get saldoMinutes => istMinutes - sollMinutes;

  double get sollHours => sollMinutes / 60.0;
  double get istHours => istMinutes / 60.0;
  double get saldoHours => saldoMinutes / 60.0;
}

/// Berechnet das Soll/Ist-Zeitkonto eines Mitarbeiters für einen Monat
/// (H-B2). Konsumiert das bisher ungenutzte [SollzeitProfile] als **Soll**-Quelle
/// und [WorkEntry] als **einzige Ist-Quelle**.
///
/// Bewusst KEINE „Mantelzeit"/zweite Ist-Quelle — die M11-Leitentscheidung
/// (siehe `plan/ida-hr-zeit-uebernahme.md`) steht aus; bis dahin bleibt
/// `WorkEntry` die alleinige Ist-Quelle, um Doppelzählung zu vermeiden.
///
/// - [profiles]: alle Sollzeit-Profile des Mitarbeiters (gültig-ab-versioniert,
///   beliebige Reihenfolge — wird intern absteigend sortiert).
/// - [entries]: Zeiteinträge des Mitarbeiters (nur die des Monats werden gezählt).
ZeitkontoResult computeZeitkonto({
  required int year,
  required int month,
  required List<SollzeitProfile> profiles,
  required List<WorkEntry> entries,
}) {
  final sorted = [...profiles]
    ..sort((a, b) => b.gueltigAb.compareTo(a.gueltigAb));

  SollzeitProfile? activeOn(DateTime day) {
    for (final p in sorted) {
      if (p.isEffectiveOn(day)) return p;
    }
    return null;
  }

  final firstDay = DateTime(year, month, 1);
  // Tag 0 des Folgemonats = letzter Tag dieses Monats.
  final lastDay = DateTime(year, month + 1, 0);
  final reference = activeOn(lastDay);

  var sollMinutes = 0;
  if (reference != null &&
      reference.isMonatsarbeitszeit &&
      reference.monatsarbeitszeitMinutes != null) {
    // Festes Monatssoll (gleichmäßig verteilt) – nicht Tag für Tag summieren.
    sollMinutes = reference.monatsarbeitszeitMinutes!;
  } else {
    for (var day = firstDay;
        !day.isAfter(lastDay);
        day = day.add(const Duration(days: 1))) {
      final profile = activeOn(day);
      if (profile == null) continue;
      sollMinutes += profile.sollMinutesForWeekday(day.weekday);
    }
  }

  var istHours = 0.0;
  for (final entry in entries) {
    // Abgelehnte Einträge zählen nicht ins Ist (konsistent zur Monatssumme in
    // zeiterfassung_screen.dart; sonst bläht ein abgelehnter Eintrag das
    // Stundenkonto/Saldo auf).
    if (entry.status == WorkEntryStatus.rejected) continue;
    if (entry.date.year == year && entry.date.month == month) {
      istHours += entry.workedHours;
    }
  }

  return ZeitkontoResult(
    sollMinutes: sollMinutes,
    istMinutes: (istHours * 60).round(),
    hasSollProfile: reference != null,
  );
}
