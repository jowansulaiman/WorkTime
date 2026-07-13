import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/kasse_report.dart';
import 'package:worktime_app/core/site_comparison.dart';
import 'package:worktime_app/models/payroll_record.dart';
import 'package:worktime_app/models/work_entry.dart';

/// REPORTING-5 — reine Engine `computeSiteVergleich` (kein State/IO/`now()`).

KassenPeriode _kassen({
  required int umsatzBrutto,
  int umsatzNetto = 0,
  int belege = 0,
  int? rohertragNetto,
  bool hatDaten = true,
}) =>
    KassenPeriode(
      start: DateTime(2026, 6, 1),
      hatDaten: hatDaten,
      belege: belege,
      erstattungen: 0,
      positiveErstattungen: 0,
      umsatzBruttoCents: umsatzBrutto,
      umsatzNettoCents: umsatzNetto,
      nettoUnsicherCents: 0,
      kaeufeNettoCents: 0,
      kaeufeBruttoCents: 0,
      wareneinsatzCents:
          rohertragNetto == null ? null : (umsatzNetto - rohertragNetto),
      wareneinsatzAbdeckungPct: null,
      rohertragNettoCents: rohertragNetto,
      rohertragBruttoCents: null,
      deltaVorperiodePct: null,
      deltaVorjahrPct: null,
    );

/// Zeiteintrag mit exakt [minutes] Brutto-Zeit (abzüglich [breakMin] Pause).
WorkEntry _entry({
  String? siteId,
  required int minutes,
  int breakMin = 0,
  WorkEntryStatus status = WorkEntryStatus.approved,
}) {
  final start = DateTime(2026, 6, 10, 8);
  return WorkEntry(
    orgId: 'org-1',
    userId: 'u1',
    date: DateTime(2026, 6, 10),
    startTime: start,
    endTime: start.add(Duration(minutes: minutes)),
    breakMinutes: breakMin.toDouble(),
    siteId: siteId,
    status: status,
  );
}

PayrollRecord _pay({
  required int employerTotal,
  PayrollStatus status = PayrollStatus.freigegeben,
}) =>
    PayrollRecord(
      orgId: 'org-1',
      userId: 'u1',
      periodYear: 2026,
      periodMonth: 6,
      employerTotalCents: employerTotal,
      status: status,
    );

SiteVergleichInput _input(
  String id, {
  String? name,
  KassenPeriode? kassen,
  int? ek,
  int? vk,
}) =>
    SiteVergleichInput(
      siteId: id,
      siteName: name ?? id,
      kassen: kassen,
      bestandswertEkCents: ek,
      bestandswertVkCents: vk,
    );

SiteKennzahlen _row(SiteVergleich v, String? siteId) =>
    v.sites.firstWhere((s) => s.siteId == siteId);

void main() {
  group('computeSiteVergleich – Ranking/Delta/Anteil', () {
    test('sortiert nach Umsatz brutto, setzt Rang/Anteil/Delta', () {
      final v = computeSiteVergleich(
        sites: [
          _input('s2', kassen: _kassen(umsatzBrutto: 6000, belege: 12)),
          _input('s1', kassen: _kassen(umsatzBrutto: 10000, belege: 25)),
        ],
        periodEntries: const [],
        payroll: const [],
      );

      expect(v.sites.map((s) => s.siteId).toList(), ['s1', 's2']);
      expect(v.sites[0].rang, 1);
      expect(v.sites[1].rang, 2);
      // Anteil am Gesamtumsatz (16000).
      expect(v.sites[0].umsatzAnteilPct, closeTo(62.5, 1e-9));
      expect(v.sites[1].umsatzAnteilPct, closeTo(37.5, 1e-9));
      // Spitzenreiter selbst hat kein Delta; s2 = −40 % zum Leader.
      expect(v.sites[0].umsatzDeltaZuFuehrendemPct, isNull);
      expect(v.sites[1].umsatzDeltaZuFuehrendemPct, closeTo(-40, 1e-9));
      expect(v.gesamtUmsatzBruttoCents, 16000);
      expect(v.gesamtBelege, 37);
    });

    test('kein Delta gegen einen führenden Standort mit Umsatz 0', () {
      final v = computeSiteVergleich(
        sites: [
          _input('s1', kassen: _kassen(umsatzBrutto: 0, hatDaten: true)),
          _input('s2', kassen: _kassen(umsatzBrutto: 0, hatDaten: true)),
        ],
        periodEntries: const [],
        payroll: const [],
      );
      expect(v.sites[1].umsatzDeltaZuFuehrendemPct, isNull);
      expect(v.sites[0].umsatzAnteilPct, isNull); // Gesamtumsatz 0
    });
  });

  group('computeSiteVergleich – Personalstunden (approved-only)', () {
    test('nur approved zählt; Pause abgezogen; nie negativ', () {
      final v = computeSiteVergleich(
        sites: [_input('s1', kassen: _kassen(umsatzBrutto: 5000))],
        periodEntries: [
          _entry(siteId: 's1', minutes: 120, breakMin: 30), // 90
          _entry(siteId: 's1', minutes: 60), // 60
          _entry(
              siteId: 's1', minutes: 200, status: WorkEntryStatus.submitted),
          _entry(siteId: 's1', minutes: 100, status: WorkEntryStatus.draft),
          _entry(siteId: 's1', minutes: 300, status: WorkEntryStatus.rejected),
        ],
        payroll: const [],
      );
      expect(_row(v, 's1').personalMinuten, 150.0);
      expect(_row(v, 's1').personalStunden, closeTo(2.5, 1e-9));
      expect(v.gesamtPersonalMinuten, 150.0);
    });

    test('Eintrag ohne siteId → Zeile „ohne Standort" (nicht verworfen)', () {
      final v = computeSiteVergleich(
        sites: [_input('s1', kassen: _kassen(umsatzBrutto: 5000))],
        periodEntries: [
          _entry(siteId: 's1', minutes: 120),
          _entry(siteId: null, minutes: 60),
          _entry(siteId: '  ', minutes: 30), // leer == ohne Standort
        ],
        payroll: const [],
      );
      final ohne = _row(v, null);
      expect(ohne.hatStandort, isFalse);
      expect(ohne.siteName, isNull);
      expect(ohne.personalMinuten, 90.0); // 60 + 30
      // „ohne Standort" (Umsatz 0) fällt ans Ende der Rangliste.
      expect(v.sites.last.siteId, isNull);
    });

    test('unbekannte siteId bekommt eine eigene Zeile (Datenehrlichkeit)', () {
      final v = computeSiteVergleich(
        sites: [_input('s1', kassen: _kassen(umsatzBrutto: 5000))],
        periodEntries: [
          _entry(siteId: 's-unbekannt', minutes: 45),
        ],
        payroll: const [],
      );
      final unbekannt = _row(v, 's-unbekannt');
      expect(unbekannt.siteName, isNull); // nicht konfiguriert
      expect(unbekannt.hatKassenDaten, isFalse);
      expect(unbekannt.personalMinuten, 45.0);
      expect(v.sites.map((s) => s.siteId), containsAll(['s1', 's-unbekannt']));
    });
  });

  group('computeSiteVergleich – Lohnkosten-Richtwert', () {
    test('finalisierte AG-Kosten proportional zu approved-Minuten verteilt', () {
      final v = computeSiteVergleich(
        sites: [
          _input('s1', kassen: _kassen(umsatzBrutto: 8000)),
          _input('s2', kassen: _kassen(umsatzBrutto: 4000)),
        ],
        periodEntries: [
          _entry(siteId: 's1', minutes: 100),
          _entry(siteId: 's2', minutes: 300),
        ],
        payroll: [
          _pay(employerTotal: 4000, status: PayrollStatus.freigegeben),
          _pay(employerTotal: 9999, status: PayrollStatus.entwurf), // ignoriert
        ],
      );
      expect(v.hatLohnAllokation, isTrue);
      expect(_row(v, 's1').lohnkostenRichtwertCents, 1000); // 4000*100/400
      expect(_row(v, 's2').lohnkostenRichtwertCents, 3000); // 4000*300/400
      expect(v.gesamtLohnkostenRichtwertCents, 4000);
    });

    test('ohne finalisierte Abrechnung: kein Richtwert, kein 50/50', () {
      final v = computeSiteVergleich(
        sites: [_input('s1', kassen: _kassen(umsatzBrutto: 5000))],
        periodEntries: [_entry(siteId: 's1', minutes: 100)],
        payroll: [_pay(employerTotal: 5000, status: PayrollStatus.entwurf)],
      );
      expect(v.hatLohnAllokation, isFalse);
      expect(_row(v, 's1').lohnkostenRichtwertCents, isNull);
      expect(v.gesamtLohnkostenRichtwertCents, isNull);
    });

    test('Standort mit 0 approved-Minuten bekommt keinen Lohn-Anteil', () {
      final v = computeSiteVergleich(
        sites: [
          _input('s1', kassen: _kassen(umsatzBrutto: 5000)),
          _input('s2', kassen: _kassen(umsatzBrutto: 3000)),
        ],
        periodEntries: [_entry(siteId: 's1', minutes: 100)], // s2 = 0 min
        payroll: [_pay(employerTotal: 2000)],
      );
      expect(_row(v, 's1').lohnkostenRichtwertCents, 2000);
      expect(_row(v, 's2').lohnkostenRichtwertCents, isNull);
      expect(v.gesamtLohnkostenRichtwertCents, 2000);
    });
  });

  group('computeSiteVergleich – Sichtbarkeit & Kassendaten-Flag', () {
    test('includeRohertrag=false blendet Rohertrag komplett aus', () {
      final sites = [
        _input('s1', kassen: _kassen(umsatzBrutto: 5000, rohertragNetto: 3000)),
      ];
      final mit = computeSiteVergleich(
        sites: sites,
        periodEntries: const [],
        payroll: const [],
      );
      final ohne = computeSiteVergleich(
        sites: sites,
        periodEntries: const [],
        payroll: const [],
        includeRohertrag: false,
      );
      expect(_row(mit, 's1').rohertragNettoCents, 3000);
      expect(mit.gesamtRohertragNettoCents, 3000);
      expect(_row(ohne, 's1').rohertragNettoCents, isNull);
      expect(ohne.gesamtRohertragNettoCents, isNull);
    });

    test('hatKassenDaten spiegelt kassen==null bzw. hatDaten==false', () {
      final v = computeSiteVergleich(
        sites: [
          _input('s1', kassen: null),
          _input('s2', kassen: _kassen(umsatzBrutto: 0, hatDaten: false)),
          _input('s3', kassen: _kassen(umsatzBrutto: 100, hatDaten: true)),
        ],
        periodEntries: const [],
        payroll: const [],
      );
      expect(_row(v, 's1').hatKassenDaten, isFalse);
      expect(_row(v, 's2').hatKassenDaten, isFalse);
      expect(_row(v, 's3').hatKassenDaten, isTrue);
    });

    test('Bestandswerte werden nullable aggregiert (nur gesetzte Werte)', () {
      final v = computeSiteVergleich(
        sites: [
          _input('s1', kassen: _kassen(umsatzBrutto: 5000), ek: 500, vk: 800),
          _input('s2', kassen: _kassen(umsatzBrutto: 3000), ek: null, vk: 200),
        ],
        periodEntries: const [],
        payroll: const [],
      );
      expect(v.gesamtBestandswertEkCents, 500); // nur s1
      expect(v.gesamtBestandswertVkCents, 1000); // 800 + 200
    });
  });

  test('leere Eingabe liefert leeren, aber konsistenten Vergleich', () {
    final v = computeSiteVergleich(
      sites: const [],
      periodEntries: const [],
      payroll: const [],
    );
    expect(v.sites, isEmpty);
    expect(v.gesamtUmsatzBruttoCents, 0);
    expect(v.gesamtPersonalMinuten, 0.0);
    expect(v.gesamtRohertragNettoCents, isNull);
    expect(v.hatLohnAllokation, isFalse);
  });
}
