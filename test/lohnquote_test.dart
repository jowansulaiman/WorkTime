import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/kasse_report.dart';
import 'package:worktime_app/core/lohnquote.dart';
import 'package:worktime_app/models/payroll_record.dart';

/// Reine Tests der Lohnquote/Betriebsergebnis-Berechnung (Kassen-Modul M6-D).
void main() {
  KassenPeriode periode(DateTime start,
      {int umsatzBrutto = 0, int? rohNetto}) {
    return KassenPeriode(
      start: start,
      hatDaten: true,
      belege: 1,
      erstattungen: 0,
      positiveErstattungen: 0,
      umsatzBruttoCents: umsatzBrutto,
      umsatzNettoCents: 0,
      nettoUnsicherCents: 0,
      kaeufeNettoCents: 0,
      kaeufeBruttoCents: 0,
      wareneinsatzCents: null,
      wareneinsatzAbdeckungPct: null,
      rohertragNettoCents: rohNetto,
      rohertragBruttoCents: null,
      deltaVorperiodePct: null,
      deltaVorjahrPct: null,
    );
  }

  PayrollRecord payroll({
    required int year,
    required int month,
    required int employerTotal,
    PayrollStatus status = PayrollStatus.freigegeben,
  }) {
    return PayrollRecord(
      orgId: 'org-1',
      userId: 'u1',
      periodYear: year,
      periodMonth: month,
      employerTotalCents: employerTotal,
      status: status,
    );
  }

  test('Monat: Lohnquote + Betriebsergebnis je Periode', () {
    final result = computeLohnkennzahlen(
      granularity: ReportGranularity.month,
      perioden: [
        periode(DateTime(2026, 6, 1), umsatzBrutto: 100000, rohNetto: 40000),
      ],
      payrolls: [
        payroll(year: 2026, month: 6, employerTotal: 20000),
        payroll(year: 2026, month: 6, employerTotal: 5000), // zweiter MA
      ],
    );
    final k = result.single;
    expect(k.personalkostenCents, 25000);
    expect(k.lohnquotePct, closeTo(25, 0.001)); // 25000/100000
    expect(k.betriebsergebnisCents, 40000 - 25000);
    expect(k.hatPersonalkosten, isTrue);
  });

  test('nur finalisierte Abrechnungen zählen', () {
    final result = computeLohnkennzahlen(
      granularity: ReportGranularity.month,
      perioden: [periode(DateTime(2026, 6, 1), umsatzBrutto: 100000)],
      payrolls: [
        payroll(year: 2026, month: 6, employerTotal: 9999,
            status: PayrollStatus.entwurf),
        payroll(year: 2026, month: 6, employerTotal: 1111,
            status: PayrollStatus.storniert),
      ],
    );
    expect(result.single.personalkostenCents, 0);
    expect(result.single.hatPersonalkosten, isFalse);
    expect(result.single.lohnquotePct, isNull);
  });

  test('Jahr: summiert die Monate des Jahres', () {
    final result = computeLohnkennzahlen(
      granularity: ReportGranularity.year,
      perioden: [periode(DateTime(2026, 1, 1), umsatzBrutto: 1200000)],
      payrolls: [
        payroll(year: 2026, month: 1, employerTotal: 10000),
        payroll(year: 2026, month: 2, employerTotal: 10000),
        payroll(year: 2025, month: 12, employerTotal: 99999), // anderes Jahr
      ],
    );
    expect(result.single.personalkostenCents, 20000);
  });

  test('Woche: keine Kennzahlen (Monatswerte nicht auf Wochen aufteilbar)', () {
    final result = computeLohnkennzahlen(
      granularity: ReportGranularity.week,
      perioden: [periode(DateTime(2026, 6, 29), umsatzBrutto: 50000)],
      payrolls: [payroll(year: 2026, month: 6, employerTotal: 20000)],
    );
    expect(result.single.hatPersonalkosten, isFalse);
    expect(result.single.lohnquotePct, isNull);
    expect(result.single.betriebsergebnisCents, isNull);
  });

  test('ohne Umsatz: Lohnquote null; Betriebsergebnis nur mit Rohertrag', () {
    final result = computeLohnkennzahlen(
      granularity: ReportGranularity.month,
      perioden: [periode(DateTime(2026, 6, 1), umsatzBrutto: 0, rohNetto: null)],
      payrolls: [payroll(year: 2026, month: 6, employerTotal: 20000)],
    );
    expect(result.single.lohnquotePct, isNull);
    expect(result.single.betriebsergebnisCents, isNull); // Rohertrag null
  });
}
