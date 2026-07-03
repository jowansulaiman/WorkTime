import '../models/payroll_record.dart';
import 'kasse_report.dart';
import 'order_frequency.dart' show startOfMonth;

/// **Kassen-Modul M6-D — Lohnquote & Betriebsergebnis (Richtwert).**
///
/// Verbindet die Personalkosten (AG-Gesamtkosten aus **freigegebenen/bezahlten**
/// Lohnabrechnungen, `PayrollRecord.employerTotalCents`) mit dem Umsatz und
/// Rohertrag je Berichtsperiode (§8a). **Pure / offline-testbar.**
///
/// Bewusste Abgrenzung (Ehrlichkeit vor Vollständigkeit):
/// - **Org-weit**: Personalkosten sind nicht sauber standort-attribuierbar
///   (Mitarbeitende arbeiten ggf. in mehreren Läden) — die Kennzahlen gelten
///   für alle Läden zusammen; der Aufrufer zeigt sie nur ohne Standort-Filter.
/// - Nur **Monat/Jahr**: Lohnabrechnungen sind Monatswerte und lassen sich nicht
///   sinnvoll auf einzelne Wochen aufteilen → Wochen-Granularität liefert leere
///   Kennzahlen.
/// - **Betriebsergebnis = Rohertrag netto − Personalkosten** (also „Rohertrag
///   nach Personal"): bewusst OHNE sonstige Fixkosten (Miete etc. lägen im
///   Finanzjournal und würden den bereits im Rohertrag steckenden Wareneinsatz
///   doppelt zählen). Klar als Zwischengröße gelabelt.
class Lohnkennzahl {
  const Lohnkennzahl({
    required this.start,
    required this.personalkostenCents,
    required this.hatPersonalkosten,
    required this.umsatzBruttoCents,
    required this.lohnquotePct,
    required this.rohertragNettoCents,
    required this.betriebsergebnisCents,
  });

  final DateTime start;

  /// AG-Gesamtkosten der Periode (Σ `employerTotalCents`, nur finalisiert).
  final int personalkostenCents;

  /// `false` = keine finalisierte Lohnabrechnung in der Periode → Kennzahlen
  /// sind nicht belastbar (UI zeigt „—").
  final bool hatPersonalkosten;

  final int umsatzBruttoCents;

  /// Personalkosten ÷ Umsatz brutto in %; `null` ohne Umsatz.
  final double? lohnquotePct;

  /// `null`, wenn der Rohertrag der Periode unbewertet ist.
  final int? rohertragNettoCents;

  /// Rohertrag netto − Personalkosten; `null` wenn Rohertrag unbewertet.
  final int? betriebsergebnisCents;
}

/// Bucketet die Lohnabrechnungen in dieselben Perioden wie [perioden] und
/// verbindet sie mit Umsatz/Rohertrag. Reihenfolge = [perioden] (älteste zuerst).
/// Für [ReportGranularity.week] leere Kennzahlen (Monatswerte, s. o.).
List<Lohnkennzahl> computeLohnkennzahlen({
  required List<KassenPeriode> perioden,
  required List<PayrollRecord> payrolls,
  required ReportGranularity granularity,
}) {
  if (granularity == ReportGranularity.week) {
    return [
      for (final p in perioden)
        Lohnkennzahl(
          start: p.start,
          personalkostenCents: 0,
          hatPersonalkosten: false,
          umsatzBruttoCents: p.umsatzBruttoCents,
          lohnquotePct: null,
          rohertragNettoCents: p.rohertragNettoCents,
          betriebsergebnisCents: null,
        ),
    ];
  }

  // Personalkosten je Perioden-Start aggregieren.
  final kostenByStart = <DateTime, int>{};
  for (final rec in payrolls) {
    if (!rec.status.isFinalized) continue;
    final monthDate = DateTime(rec.periodYear, rec.periodMonth, 1);
    final start = granularity == ReportGranularity.month
        ? startOfMonth(monthDate)
        : DateTime(monthDate.year, 1, 1);
    kostenByStart[start] = (kostenByStart[start] ?? 0) + rec.employerTotalCents;
  }

  return [
    for (final p in perioden)
      _build(p, kostenByStart[p.start] ?? 0, kostenByStart.containsKey(p.start)),
  ];
}

Lohnkennzahl _build(KassenPeriode p, int personalkosten, bool hatKosten) {
  final roh = p.rohertragNettoCents;
  return Lohnkennzahl(
    start: p.start,
    personalkostenCents: personalkosten,
    hatPersonalkosten: hatKosten,
    umsatzBruttoCents: p.umsatzBruttoCents,
    lohnquotePct: (hatKosten && p.umsatzBruttoCents > 0)
        ? personalkosten / p.umsatzBruttoCents * 100
        : null,
    rohertragNettoCents: roh,
    betriebsergebnisCents:
        (hatKosten && roh != null) ? roh - personalkosten : null,
  );
}
