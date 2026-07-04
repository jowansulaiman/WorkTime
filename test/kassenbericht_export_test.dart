import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:worktime_app/core/kasse_report.dart';
import 'package:worktime_app/core/third_party_report.dart';
import 'package:worktime_app/services/export_service.dart';

/// Test des Kassenbericht-CSV-Exports (Kassen-Modul M4): BOM, ;-Delimiter,
/// de_DE-Beträge, leere Buckets bleiben leer.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  KassenPeriode periode({
    required DateTime start,
    bool hatDaten = true,
    int brutto = 0,
    int netto = 0,
    int kaeufe = 0,
    int? cogs,
    int? rohNetto,
    int? rohBrutto,
    double? deltaVor,
  }) {
    return KassenPeriode(
      start: start,
      hatDaten: hatDaten,
      belege: hatDaten ? 5 : 0,
      erstattungen: 0,
      positiveErstattungen: 0,
      umsatzBruttoCents: brutto,
      umsatzNettoCents: netto,
      nettoUnsicherCents: 0,
      kaeufeNettoCents: kaeufe,
      kaeufeBruttoCents: kaeufe,
      wareneinsatzCents: cogs,
      wareneinsatzAbdeckungPct: cogs == null ? null : 100,
      rohertragNettoCents: rohNetto,
      rohertragBruttoCents: rohBrutto,
      deltaVorperiodePct: deltaVor,
      deltaVorjahrPct: null,
    );
  }

  test('CSV hat BOM, ;-Delimiter und deutsche Beträge', () {
    final csv = ExportService.buildKassenberichtCsv(
      granularity: ReportGranularity.week,
      siteLabel: 'Strichmännchen',
      perioden: [
        periode(
          start: DateTime(2026, 6, 29),
          brutto: 119000,
          netto: 100000,
          kaeufe: 50000,
          cogs: 60000,
          rohNetto: 40000,
          rohBrutto: 59000,
          deltaVor: 12.5,
        ),
      ],
    );

    expect(csv.codeUnitAt(0), 0xFEFF); // BOM
    expect(csv, contains('Kassenbericht Export'));
    expect(csv, contains('Laden;Strichmännchen'));
    expect(csv, contains('Richtwert'));
    // Kopfzeile mit ;-Delimiter.
    expect(csv, contains('Zeitraum;Umsatz brutto;Umsatz netto;Käufe netto'));
    // Beträge in Euro mit Komma.
    expect(csv, contains('1190,00'));
    expect(csv, contains('1000,00'));
    expect(csv, contains('400,00')); // Rohertrag netto
    expect(csv, contains('12,5')); // Δ
    expect(csv, contains('KW27 2026'));
  });

  test('leere Buckets: Umsatz-Spalten bleiben leer statt 0', () {
    final csv = ExportService.buildKassenberichtCsv(
      granularity: ReportGranularity.month,
      perioden: [
        periode(start: DateTime(2026, 5, 1), hatDaten: false),
        periode(start: DateTime(2026, 6, 1), brutto: 20000, netto: 16000),
      ],
    );
    final lines = csv.split('\n');
    // Zeile des leeren Mai-Buckets: Umsatz-Felder leer (zwei aufeinander
    // folgende ; nach dem Zeitraum-Label).
    final maiLine = lines.firstWhere((l) => l.startsWith('Mai'));
    expect(maiLine.startsWith('Mai 2026;;;'), isTrue);
  });

  test('Fremdgeld-Block wird separat hinten angehängt (§5)', () {
    final csv = ExportService.buildKassenberichtCsv(
      granularity: ReportGranularity.week,
      perioden: [periode(start: DateTime(2026, 7, 6), brutto: 20000)],
      thirdParty: const ThirdPartySummary(
        totalCents: 5700,
        byType: [
          ThirdPartyTypeSummary(
              typeId: 'lotto', typeName: 'Lotto', totalCents: 4500, count: 2),
          ThirdPartyTypeSummary(
              typeId: 'post', typeName: 'Post', totalCents: 1200, count: 1),
        ],
      ),
    );
    // Bestehende Umsatz-Kopfzeile unverändert vorne.
    expect(csv, contains('Zeitraum;Umsatz brutto'));
    // Separater Block hinten.
    expect(csv, contains('Dritte Hand / Fremdgelder (Treuhand, kein Umsatz)'));
    expect(csv, contains('Dienst;Betrag;Positionen'));
    expect(csv, contains('Lotto;45,00;2'));
    expect(csv, contains('Fremdgeld gesamt;57,00;'));
    // Reihenfolge: Fremdgeld-Block kommt NACH der Umsatztabelle.
    expect(csv.indexOf('Umsatz brutto') < csv.indexOf('Fremdgelder'), isTrue);
  });

  test('ohne Fremdgeld: kein Block (Default empty)', () {
    final csv = ExportService.buildKassenberichtCsv(
      granularity: ReportGranularity.week,
      perioden: [periode(start: DateTime(2026, 7, 6), brutto: 20000)],
    );
    expect(csv.contains('Fremdgelder'), isFalse);
  });
}
