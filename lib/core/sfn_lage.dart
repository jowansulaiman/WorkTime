// lib/core/sfn_lage.dart

import '../models/work_entry.dart';
import 'feiertage.dart';

/// Zuschlags-**Lage** eines Zeitraums (ZV-5.3): wie viele Minuten fallen in die
/// §3b-Fenster Nacht / Sonntag / Feiertag. Rein informativ (Transparenz für den
/// Mitarbeiter, „deine Zuschlagszeiten sind erfasst") — die eigentliche
/// Verrechnung macht `PayrollCalculator` (die Kategorien überlappen sich, ein
/// Minutenwert kann in mehreren zählen, z. B. Nacht am Sonntag).
class SfnLage {
  const SfnLage({
    this.nachtMinuten = 0,
    this.sonntagMinuten = 0,
    this.feiertagMinuten = 0,
  });

  /// Minuten im Nachtfenster (20:00–06:00, §3b Nachtarbeit).
  final int nachtMinuten;

  /// Minuten an Sonntagen.
  final int sonntagMinuten;

  /// Minuten an gesetzlichen Feiertagen (des gewählten Bundeslands).
  final int feiertagMinuten;

  bool get isZero =>
      nachtMinuten == 0 && sonntagMinuten == 0 && feiertagMinuten == 0;

  double get nachtStunden => nachtMinuten / 60;
  double get sonntagStunden => sonntagMinuten / 60;
  double get feiertagStunden => feiertagMinuten / 60;

  SfnLage operator +(SfnLage o) => SfnLage(
        nachtMinuten: nachtMinuten + o.nachtMinuten,
        sonntagMinuten: sonntagMinuten + o.sonntagMinuten,
        feiertagMinuten: feiertagMinuten + o.feiertagMinuten,
      );

  static const SfnLage zero = SfnLage();
}

/// **Pure** Lage-Ermittlung über eine Liste von Zeiteinträgen (ZV-5.3). Kein
/// State/IO/`now()`. Klassifiziert minutenweise über `[startTime, endTime)` —
/// eine Schicht ist kurz (≤ ~10 h), die Auflösung ist damit unkritisch und
/// robust gegen Mitternachts-/Sonntags-/Feiertagsgrenzen. Über Kalendertage
/// hinweg (Nachtschicht) wird korrekt pro Minute neu bewertet.
///
/// **Näherung:** gerechnet wird über die **Brutto**-Zeit (Pausen nicht
/// abgezogen) — bewusst, weil dies nur eine Transparenz-Anzeige ist, keine
/// Abrechnungsgröße.
SfnLage computeSfnLage(
  Iterable<WorkEntry> entries, {
  required String bundesland,
}) {
  var total = SfnLage.zero;
  for (final e in entries) {
    total += _lageForEntry(e, bundesland);
  }
  return total;
}

SfnLage _lageForEntry(WorkEntry entry, String bundesland) {
  final start = entry.startTime;
  final end = entry.endTime;
  if (!end.isAfter(start)) return SfnLage.zero;

  var nacht = 0;
  var sonntag = 0;
  var feiertag = 0;

  // Auf volle Minute normalisieren und minutenweise klassifizieren.
  var t = DateTime(start.year, start.month, start.day, start.hour, start.minute);
  final feiertagCache = <int, bool>{}; // Tag (yyyymmdd) → Feiertag?
  while (t.isBefore(end)) {
    final hour = t.hour;
    if (hour >= 20 || hour < 6) nacht++;
    if (t.weekday == DateTime.sunday) sonntag++;
    final key = t.year * 10000 + t.month * 100 + t.day;
    final isFeiertag = feiertagCache.putIfAbsent(
        key, () => istFeiertag(t, bundesland: bundesland));
    if (isFeiertag) feiertag++;
    t = t.add(const Duration(minutes: 1));
  }

  return SfnLage(
    nachtMinuten: nacht,
    sonntagMinuten: sonntag,
    feiertagMinuten: feiertag,
  );
}
