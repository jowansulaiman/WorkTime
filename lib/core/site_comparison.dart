import '../models/payroll_record.dart';
import '../models/work_entry.dart';
import 'kasse_report.dart';
import 'work_entry_rules.dart';

/// **REPORTING-5 — Standortvergleich-Engine (pure).** Stellt die Läden einer Org
/// für einen Zeitraum (i. d. R. ein Monat) nebeneinander: je Standort Umsatz,
/// Rohertrag, Belege, Personalstunden (nur `approved`-Ist) und Bestandswert,
/// plus Ranking und Delta zum führenden Standort.
///
/// **Abgrenzung zu `StoreHealth` (`store_health.dart`):** `StoreHealth` ist ein
/// **Warn-Benchmark** — es vergleicht die heutige Beleg-Anzahl eines Ladens mit
/// seinem Wochentag-Schnitt und schlägt bei einem Einbruch (`isDip`) Alarm.
/// Diese Engine ist dagegen eine **Zeitraum-Analyse** über mehrere Kennzahlen
/// (Umsatz/Rohertrag/Personal/Bestand) ohne Schwellwert/Alarm. Eine langfristige
/// Zusammenführung (ein Standort-Modul mit Benchmark- UND Analyse-Sicht) bleibt
/// als Option offen; heute bewusst getrennt, weil Datenbasis (Belege vs.
/// Perioden-Aggregate) und Zweck (Frühwarnung vs. Führungs-Report) verschieden
/// sind.
///
/// **Pure / offline-testbar:** kein State, kein IO, kein `now()`. Der Aufrufer
/// löst die Kassen-Perioden (`loadKassenbericht`), Bestandswerte und
/// Monats-Zeiteinträge auf und reicht sie fertig herein; die Engine filtert die
/// SSoT-Regeln (`countsAsIst` für das Ist, `PayrollStatus.isFinalized` für die
/// Lohnkosten) selbst und verwirft nichts still.
class SiteKennzahlen {
  const SiteKennzahlen({
    required this.siteId,
    required this.siteName,
    required this.hatKassenDaten,
    required this.umsatzBruttoCents,
    required this.umsatzNettoCents,
    required this.belege,
    required this.rohertragNettoCents,
    required this.personalMinuten,
    required this.bestandswertEkCents,
    required this.bestandswertVkCents,
    required this.lohnkostenRichtwertCents,
    required this.rang,
    required this.umsatzAnteilPct,
    required this.umsatzDeltaZuFuehrendemPct,
  });

  /// Standort-ID; `null` = die Sammelzeile **„ohne Standort"** (Zeiteinträge
  /// ohne `siteId` werden nicht verworfen, sondern hier gebündelt).
  final String? siteId;

  /// Anzeigename des Standorts (`null` bei „ohne Standort" oder unbekannter,
  /// nicht konfigurierter `siteId`).
  final String? siteName;

  /// `false` = für diesen Standort lag keine einzige Kassen-Periode/kein
  /// Kassen-Tag im Zeitraum vor (Umsatz/Belege stehen dann auf 0, aber als
  /// „keine Daten" markiert, nie als stille 0 fehlinterpretiert).
  final bool hatKassenDaten;

  final int umsatzBruttoCents;
  final int umsatzNettoCents;
  final int belege;

  /// Rohertrag netto (Umsatz netto − Wareneinsatz); `null` wenn unbewertet ODER
  /// der Rohertrag für das gebundene Profil nicht sichtbar ist.
  final int? rohertragNettoCents;

  /// Geleistete Personal-Minuten (nur `approved`-Ist via [countsAsIst]).
  final double personalMinuten;

  /// Warenbestandswert zu EK in Cent; `null` = nicht sichtbar oder keine
  /// echte Standort-Zeile.
  final int? bestandswertEkCents;

  /// Warenbestandswert zu VK in Cent; `null` = nicht sichtbar oder keine
  /// echte Standort-Zeile.
  final int? bestandswertVkCents;

  /// **Klar gelabelter Richtwert** — anteilige Lohnkosten: die org-weiten
  /// finalisierten AG-Gesamtkosten proportional zu den `approved`-Minuten dieses
  /// Standorts. `null`, wenn keine Allokationsbasis existiert (kein Standort mit
  /// `approved`-Minuten bzw. keine finalisierte Abrechnung) — es gibt bewusst
  /// KEINEN stillen 50/50-Split und KEINE `siteId` am `PayrollRecord`.
  final int? lohnkostenRichtwertCents;

  /// 1-basierter Rang nach Umsatz brutto (1 = umsatzstärkster Standort).
  final int rang;

  /// Anteil dieses Standorts am Gesamt-Umsatz brutto in %; `null` ohne Umsatz.
  final double? umsatzAnteilPct;

  /// Δ Umsatz brutto zum führenden Standort (Rang 1) in %; `null` für den
  /// Spitzenreiter selbst und wenn der Spitzenreiter keinen Umsatz > 0 hat
  /// (kein irreführendes Δ gegen eine 0-/refund-lastige Basis — Muster
  /// `store_health.dart`). Negativ = schwächer als der Spitzenreiter.
  final double? umsatzDeltaZuFuehrendemPct;

  /// `true`, wenn es sich um eine echte Standort-Zeile handelt (nicht die
  /// „ohne Standort"-Sammelzeile).
  bool get hatStandort => siteId != null;

  /// Personalstunden (abgeleitet aus [personalMinuten]).
  double get personalStunden => personalMinuten / 60.0;
}

/// Ergebnis des Standortvergleichs für einen Zeitraum.
class SiteVergleich {
  const SiteVergleich({
    required this.sites,
    required this.gesamtUmsatzBruttoCents,
    required this.gesamtUmsatzNettoCents,
    required this.gesamtBelege,
    required this.gesamtPersonalMinuten,
    required this.gesamtRohertragNettoCents,
    required this.gesamtBestandswertEkCents,
    required this.gesamtBestandswertVkCents,
    required this.gesamtLohnkostenRichtwertCents,
    required this.hatLohnAllokation,
  });

  /// Standort-Kennzahlen, absteigend nach Umsatz brutto sortiert (Ranking;
  /// die „ohne Standort"-Sammelzeile fällt mit Umsatz 0 ans Ende).
  final List<SiteKennzahlen> sites;

  final int gesamtUmsatzBruttoCents;
  final int gesamtUmsatzNettoCents;
  final int gesamtBelege;
  final double gesamtPersonalMinuten;

  /// Σ Rohertrag netto der bewerteten Standorte; `null` wenn kein Standort
  /// einen bewerteten Rohertrag hat oder der Rohertrag nicht sichtbar ist.
  final int? gesamtRohertragNettoCents;

  /// Σ Bestandswert EK/VK; `null` wenn für keinen Standort sichtbar.
  final int? gesamtBestandswertEkCents;
  final int? gesamtBestandswertVkCents;

  /// Σ verteilter Lohnkosten-Richtwert (= die finalisierten AG-Gesamtkosten,
  /// wenn eine Allokationsbasis existiert); `null` sonst.
  final int? gesamtLohnkostenRichtwertCents;

  /// `true` = es gab eine belastbare Allokationsbasis (finalisierte
  /// Abrechnungen UND `approved`-Minuten). Steuert die ehrliche UI-Kennzeichnung
  /// „Richtwert (Verteilung nach Stunden)".
  final bool hatLohnAllokation;

  double get gesamtPersonalStunden => gesamtPersonalMinuten / 60.0;
}

/// Ein Standort-Eingang für [computeSiteVergleich]: die vom Aufrufer bereits
/// aufgelösten Kassen-/Bestand-Kennzahlen eines Standorts. Die Zeiteinträge und
/// Lohnabrechnungen kommen separat (org-weit) herein, weil sie NICHT sauber
/// standort-attribuiert sind (Zeiten tragen ihre eigene `siteId`, Löhne gar
/// keine).
class SiteVergleichInput {
  const SiteVergleichInput({
    required this.siteId,
    this.siteName,
    this.kassen,
    this.bestandswertEkCents,
    this.bestandswertVkCents,
  });

  final String siteId;
  final String? siteName;

  /// Die Kassen-Periode des Zeitraums für diesen Standort (aus
  /// `loadKassenbericht(siteId:)`); `null` = keine Kassendaten.
  final KassenPeriode? kassen;

  /// Bestandswert EK/VK in Cent; `null` = für das gebundene Profil nicht
  /// sichtbar (dann bleibt die Kennzahl auch im Ergebnis `null`).
  final int? bestandswertEkCents;
  final int? bestandswertVkCents;
}

class _Bucket {
  _Bucket({this.siteName, this.kassen, this.bestandEk, this.bestandVk});

  String? siteName;
  KassenPeriode? kassen;
  int? bestandEk;
  int? bestandVk;
  double minuten = 0;
}

/// Berechnet den [SiteVergleich] aus den Standort-Eingängen [sites] sowie den
/// (org-weit, auf den Zeitraum vorgefilterten) [periodEntries] und [payroll].
///
/// - **Personalstunden:** nur `approved`-Ist ([countsAsIst]); Zeiteinträge ohne
///   `siteId` bilden die Sammelzeile „ohne Standort" (nicht still verworfen).
///   Ein Zeiteintrag mit einer `siteId`, die in [sites] nicht vorkommt, bekommt
///   eine eigene Zeile (Datenehrlichkeit statt stiller Verwurf).
/// - **Lohnkosten (Richtwert):** Σ [PayrollRecord.employerTotalCents] der
///   finalisierten Abrechnungen, proportional zu den `approved`-Minuten je
///   Standort verteilt. Ohne Allokationsbasis (0 Minuten org-weit oder keine
///   finalisierte Abrechnung) bleiben alle Lohn-Zeilen `null`.
/// - **[includeRohertrag]:** `false` blendet den Rohertrag aus (nicht sichtbar
///   für das gebundene Profil) — er wird gar nicht erst durchgereicht.
SiteVergleich computeSiteVergleich({
  required List<SiteVergleichInput> sites,
  required List<WorkEntry> periodEntries,
  required List<PayrollRecord> payroll,
  bool includeRohertrag = true,
}) {
  // Sammelzeilen-Schlüssel: echte siteId oder das Sentinel `null`
  // („ohne Standort"). LinkedHashMap-Ordnung ist für die spätere Sortierung
  // irrelevant, wir sortieren am Ende deterministisch.
  final buckets = <String?, _Bucket>{};

  // (1) Konfigurierte Standorte seeden — sie erscheinen auch mit 0 Minuten.
  for (final input in sites) {
    buckets[input.siteId] = _Bucket(
      siteName: input.siteName,
      kassen: input.kassen,
      bestandEk: input.bestandswertEkCents,
      bestandVk: input.bestandswertVkCents,
    );
  }

  // (2) Personal-Minuten (nur approved) je Standort — ohne siteId → „ohne
  // Standort", unbekannte siteId → eigene Zeile.
  for (final entry in periodEntries) {
    if (!countsAsIst(entry)) continue;
    final raw = entry.siteId;
    final key = (raw == null || raw.trim().isEmpty) ? null : raw;
    final bucket = buckets.putIfAbsent(key, () => _Bucket());
    bucket.minuten += _approvedMinuten(entry);
  }

  final totalMinuten =
      buckets.values.fold<double>(0, (sum, b) => sum + b.minuten);

  // (3) Lohnkosten-Basis: nur finalisierte Abrechnungen.
  var lohnBasisCents = 0;
  var hatFinalisierteAbrechnung = false;
  for (final record in payroll) {
    if (!record.status.isFinalized) continue;
    hatFinalisierteAbrechnung = true;
    lohnBasisCents += record.employerTotalCents;
  }
  final hatLohnAllokation = hatFinalisierteAbrechnung && totalMinuten > 0;

  // (4) Kennzahlen je Bucket bauen (noch ohne Rang/Delta).
  final rows = <SiteKennzahlen>[];
  for (final entry in buckets.entries) {
    final siteId = entry.key;
    final b = entry.value;
    final kassen = b.kassen;
    final hatKassen = kassen != null && kassen.hatDaten;
    // Lohn nur verteilen, wenn eine Basis existiert UND der Standort selbst
    // approved-Minuten hat (Stunden==0 ⇒ null, kein stiller 50/50-Split).
    final lohn = (hatLohnAllokation && b.minuten > 0)
        ? (lohnBasisCents * b.minuten / totalMinuten).round()
        : null;
    rows.add(SiteKennzahlen(
      siteId: siteId,
      siteName: b.siteName,
      hatKassenDaten: hatKassen,
      umsatzBruttoCents: kassen?.umsatzBruttoCents ?? 0,
      umsatzNettoCents: kassen?.umsatzNettoCents ?? 0,
      belege: kassen?.belege ?? 0,
      rohertragNettoCents:
          includeRohertrag ? kassen?.rohertragNettoCents : null,
      personalMinuten: b.minuten,
      bestandswertEkCents: b.bestandEk,
      bestandswertVkCents: b.bestandVk,
      lohnkostenRichtwertCents: lohn,
      // Rang/Anteil/Delta werden nach der Sortierung gesetzt.
      rang: 0,
      umsatzAnteilPct: null,
      umsatzDeltaZuFuehrendemPct: null,
    ));
  }

  // (5) Sortierung = Ranking nach Umsatz brutto (Ties: echte siteId vor null,
  // dann alphabetisch — deterministisch).
  rows.sort((a, b) {
    final byUmsatz = b.umsatzBruttoCents.compareTo(a.umsatzBruttoCents);
    if (byUmsatz != 0) return byUmsatz;
    if (a.siteId == null && b.siteId == null) return 0;
    if (a.siteId == null) return 1; // null („ohne Standort") ans Ende
    if (b.siteId == null) return -1;
    return a.siteId!.compareTo(b.siteId!);
  });

  final gesamtUmsatzBrutto =
      rows.fold<int>(0, (sum, r) => sum + r.umsatzBruttoCents);
  final leaderUmsatz = rows.isEmpty ? 0 : rows.first.umsatzBruttoCents;

  final ranked = <SiteKennzahlen>[];
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final anteil = gesamtUmsatzBrutto > 0
        ? r.umsatzBruttoCents / gesamtUmsatzBrutto * 100
        : null;
    // Δ zum Spitzenreiter: für Rang 1 selbst null; Basis <= 0 → kein Δ.
    final delta = (i == 0 || leaderUmsatz <= 0)
        ? null
        : (r.umsatzBruttoCents - leaderUmsatz) / leaderUmsatz * 100;
    ranked.add(SiteKennzahlen(
      siteId: r.siteId,
      siteName: r.siteName,
      hatKassenDaten: r.hatKassenDaten,
      umsatzBruttoCents: r.umsatzBruttoCents,
      umsatzNettoCents: r.umsatzNettoCents,
      belege: r.belege,
      rohertragNettoCents: r.rohertragNettoCents,
      personalMinuten: r.personalMinuten,
      bestandswertEkCents: r.bestandswertEkCents,
      bestandswertVkCents: r.bestandswertVkCents,
      lohnkostenRichtwertCents: r.lohnkostenRichtwertCents,
      rang: i + 1,
      umsatzAnteilPct: anteil,
      umsatzDeltaZuFuehrendemPct: delta,
    ));
  }

  // (6) Aggregate — nullable-Summen nur über sichtbare/bewertete Werte.
  int? sumNullable(int? Function(SiteKennzahlen) pick) {
    var any = false;
    var total = 0;
    for (final r in ranked) {
      final v = pick(r);
      if (v == null) continue;
      any = true;
      total += v;
    }
    return any ? total : null;
  }

  return SiteVergleich(
    sites: List<SiteKennzahlen>.unmodifiable(ranked),
    gesamtUmsatzBruttoCents: gesamtUmsatzBrutto,
    gesamtUmsatzNettoCents:
        ranked.fold<int>(0, (sum, r) => sum + r.umsatzNettoCents),
    gesamtBelege: ranked.fold<int>(0, (sum, r) => sum + r.belege),
    gesamtPersonalMinuten: totalMinuten,
    gesamtRohertragNettoCents: sumNullable((r) => r.rohertragNettoCents),
    gesamtBestandswertEkCents: sumNullable((r) => r.bestandswertEkCents),
    gesamtBestandswertVkCents: sumNullable((r) => r.bestandswertVkCents),
    gesamtLohnkostenRichtwertCents:
        hatLohnAllokation ? sumNullable((r) => r.lohnkostenRichtwertCents) : null,
    hatLohnAllokation: hatLohnAllokation,
  );
}

/// Geleistete Minuten eines Zeiteintrags (Ende − Start − Pause, nie negativ).
/// Spiegelt [WorkEntry.workedHours] (× 60), ohne die Division/Multiplikation.
double _approvedMinuten(WorkEntry entry) {
  final raw =
      entry.endTime.difference(entry.startTime).inMinutes - entry.breakMinutes;
  return raw < 0 ? 0 : raw;
}
