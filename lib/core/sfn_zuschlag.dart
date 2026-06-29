/// §3b-EStG-Aufteilung der **S**onntags-, **F**eiertags- und **N**achtarbeits-
/// zuschläge (SFN) in einen steuerfreien, einen SV-freien und einen jeweils
/// pflichtigen Anteil.
///
/// Reiner, **quellen-entkoppelter** Rechenkern (Plan §5.8b / Leitentscheidung
/// E9 „§3b voll umsetzen", Meilenstein **M-L-a** — laut Audit-Korrektur H4 früh
/// baubar, da nur M-B0/`SalaryKind` nötig). Die **Lage** (welche Stunden unter
/// welche Zuschlagsart fallen — Nacht-Fenster aus `OrgPayrollSettings`, Sonn-/
/// Feiertag aus dem Feiertagskalender) wird hier **als Eingabe** entgegen-
/// genommen, NICHT ermittelt: deren Quelle ist die noch ausstehende
/// „Mantelzeit-Lage" (Leitentscheidung #2/M-Z2). Dadurch ist diese Aufteilung
/// von der Mantelzeit-Entscheidung unabhängig und schon jetzt nutzbar — sowohl
/// für `WorkEntry`-Zeiten als auch später für Mantelzeit-Events.
///
/// Bleibt — wie der ganze HR-Lohnteil — ein **Richtwert**, keine zertifizierte
/// Lohnbuchhaltung. Rechnet ausschließlich in ganzen Cent (keine Euro-`double`-
/// Zwischenwerte → kein Float-Drift, analog [Money]).
library;

import 'dart:math' as math;

/// Steuerfreier Höchst-Grundlohn der §3b-Bemessung: **50 €/h** (5000 Cent).
/// Darüber ist der Zuschlag steuerpflichtig.
const int sfnSteuerfreiGrundlohnCapCents = 5000;

/// SV-freier Höchst-Grundlohn der §3b-Bemessung: **25 €/h** (2500 Cent).
/// Darüber ist der Zuschlag SV-pflichtig (aber ggf. weiter steuerfrei).
const int sfnSvFreiGrundlohnCapCents = 2500;

/// Art eines §3b-Zuschlags mit ihrem gesetzlichen steuerfreien Höchstsatz.
///
/// Die Prozentsätze sind die §3b-EStG-Höchstgrenzen (Plan §5.8b). Welche
/// konkreten Stunden welcher Art zugeordnet werden (inkl. der Sonderregel
/// „00–04 Uhr nur bei Arbeitsbeginn vor 00 Uhr" → [nachtTief]), entscheidet die
/// aufrufende Lage-Ermittlung, nicht dieser Kern.
enum SfnZuschlagsart {
  /// Nachtarbeit 20–06 Uhr: **+25 %**.
  nacht,

  /// Nachtarbeit 00–04 Uhr bei Arbeitsbeginn vor 00 Uhr: **+40 %**.
  nachtTief,

  /// Sonntagsarbeit: **+50 %**.
  sonntag,

  /// Feiertagsarbeit: **+125 %**.
  feiertag,

  /// 24.12. ab 14 Uhr, 25.12., 26.12., 1.5.: **+150 %**.
  feiertagHoch,
}

extension SfnZuschlagsartX on SfnZuschlagsart {
  /// Gesetzlicher steuerfreier Höchstsatz (§3b EStG) in **Basispunkten** des
  /// Grundlohns (2500 = 25 %). Ganzzahlig gehalten, um Float-Drift zu vermeiden.
  int get basispunkte => switch (this) {
        SfnZuschlagsart.nacht => 2500,
        SfnZuschlagsart.nachtTief => 4000,
        SfnZuschlagsart.sonntag => 5000,
        SfnZuschlagsart.feiertag => 12500,
        SfnZuschlagsart.feiertagHoch => 15000,
      };

  /// Höchstsatz als Faktor (0,25 …) — nur für Anzeige; gerechnet wird über
  /// [basispunkte].
  double get prozent => basispunkte / 10000;

  String get label => switch (this) {
        SfnZuschlagsart.nacht => 'Nachtarbeit (20–06 Uhr)',
        SfnZuschlagsart.nachtTief => 'Nachtarbeit (00–04 Uhr)',
        SfnZuschlagsart.sonntag => 'Sonntagsarbeit',
        SfnZuschlagsart.feiertag => 'Feiertagsarbeit',
        SfnZuschlagsart.feiertagHoch => 'Feiertagsarbeit (hoch)',
      };
}

/// Aufteilung eines §3b-Zuschlags (alle Beträge in **ganzen Cent**).
///
/// Es gilt stets `0 ≤ svFreiCents ≤ steuerfreiCents ≤ gesamtCents`, weil die
/// SV-Grundlohngrenze (25 €) strenger ist als die Steuergrenze (50 €) und beide
/// ≤ dem echten Grundlohn liegen.
class Sfn3bAnteil {
  const Sfn3bAnteil({
    required this.gesamtCents,
    required this.steuerfreiCents,
    required this.svFreiCents,
  });

  /// Tatsächlich gezahlter Zuschlag (auf dem **echten** Grundlohn, ungedeckelt).
  final int gesamtCents;

  /// Nach §3b **steuerfreier** Anteil (Grundlohn-Bemessung bis 50 €/h gedeckelt).
  final int steuerfreiCents;

  /// **SV-freier** Anteil (Grundlohn-Bemessung bis 25 €/h gedeckelt).
  final int svFreiCents;

  /// Steuerpflichtiger Rest (Anteil über der 50-€-Grundlohngrenze).
  int get steuerpflichtigCents => gesamtCents - steuerfreiCents;

  /// SV-pflichtiger Rest (Anteil über der 25-€-Grundlohngrenze).
  int get svPflichtigCents => gesamtCents - svFreiCents;

  bool get isZero =>
      gesamtCents == 0 && steuerfreiCents == 0 && svFreiCents == 0;

  static const Sfn3bAnteil zero =
      Sfn3bAnteil(gesamtCents: 0, steuerfreiCents: 0, svFreiCents: 0);

  Sfn3bAnteil operator +(Sfn3bAnteil other) => Sfn3bAnteil(
        gesamtCents: gesamtCents + other.gesamtCents,
        steuerfreiCents: steuerfreiCents + other.steuerfreiCents,
        svFreiCents: svFreiCents + other.svFreiCents,
      );

  @override
  String toString() => 'Sfn3bAnteil(gesamt: $gesamtCents, steuerfrei: '
      '$steuerfreiCents, svFrei: $svFreiCents)';
}

/// Kaufmännische Ganzzahl-Division (round-half-up) ohne Float-Zwischenwert.
///
/// Vorbedingung: **nicht-negativer** Zähler und positiver Nenner (für negative
/// Zähler ist das Ergebnis Richtung Null gerundet, nicht symmetrisch). In §3b
/// sind Basispunkte, Grundlohn und Minuten stets positiv — der Aufrufer
/// [computeSfn3bAnteil] gibt davor bei `<= 0` bereits [Sfn3bAnteil.zero] zurück.
int _roundDiv(int numerator, int denominator) {
  assert(numerator >= 0 && denominator > 0,
      '_roundDiv erwartet nicht-negativen Zähler und positiven Nenner');
  return (numerator + denominator ~/ 2) ~/ denominator;
}

/// Berechnet die §3b-Aufteilung **einer** Zuschlagsart für [dauer] bei einem
/// Stundengrundlohn von [grundlohnCentsProStunde].
///
/// Formel (Plan §5.8b): `Anteil = satz × min(grundlohn, Cap) × stunden`, wobei
/// die Steuer-/SV-Grenze ([sfnSteuerfreiGrundlohnCapCents]/
/// [sfnSvFreiGrundlohnCapCents]) den bemessungsfähigen Grundlohn deckelt.
/// Negative/Null-Eingaben ergeben [Sfn3bAnteil.zero].
Sfn3bAnteil computeSfn3bAnteil({
  required SfnZuschlagsart art,
  required int grundlohnCentsProStunde,
  required Duration dauer,
}) {
  final minutes = dauer.inMinutes;
  if (minutes <= 0 || grundlohnCentsProStunde <= 0) {
    return Sfn3bAnteil.zero;
  }
  final bp = art.basispunkte;
  // Nenner: Basispunkte (×10000) und Stunde (×60 min).
  const denom = 10000 * 60;
  int anteil(int grundlohnCents) =>
      _roundDiv(bp * grundlohnCents * minutes, denom);

  return Sfn3bAnteil(
    gesamtCents: anteil(grundlohnCentsProStunde),
    steuerfreiCents: anteil(
        math.min(grundlohnCentsProStunde, sfnSteuerfreiGrundlohnCapCents)),
    svFreiCents:
        anteil(math.min(grundlohnCentsProStunde, sfnSvFreiGrundlohnCapCents)),
  );
}

/// Summiert die §3b-Aufteilung über eine ganze **Lage** (Zuschlagsart → Dauer)
/// bei gleichem Stundengrundlohn. Die Anteile addieren sich linear, d. h. Nacht-
/// und Sonn-/Feiertagsanteile werden — wie nach §3b zulässig — kumuliert.
Sfn3bAnteil computeSfn3bGesamt({
  required Map<SfnZuschlagsart, Duration> lage,
  required int grundlohnCentsProStunde,
}) {
  var total = Sfn3bAnteil.zero;
  for (final entry in lage.entries) {
    total += computeSfn3bAnteil(
      art: entry.key,
      grundlohnCentsProStunde: grundlohnCentsProStunde,
      dauer: entry.value,
    );
  }
  return total;
}
