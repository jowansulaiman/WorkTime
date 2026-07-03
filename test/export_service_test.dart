import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:worktime_app/models/audit_log_entry.dart';
import 'package:worktime_app/models/payroll_record.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/services/export_service.dart';

/// Minimaler quotenbewusster CSV-Parser (Delimiter `;`, Quote `"`,
/// verdoppelte Quotes, Zeilenumbrueche innerhalb gequoteter Felder).
/// Nur fuer den Test, um zu verifizieren, dass das Escaping die
/// Datensatzstruktur (11 Spalten pro Zeile) verlustfrei erhaelt.
List<List<String>> _parseCsv(String input) {
  final records = <List<String>>[];
  var fields = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var i = 0;
  while (i < input.length) {
    final ch = input[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      field.write(ch);
      i++;
      continue;
    }
    if (ch == '"') {
      inQuotes = true;
      i++;
      continue;
    }
    if (ch == ';') {
      fields.add(field.toString());
      field.clear();
      i++;
      continue;
    }
    if (ch == '\n') {
      fields.add(field.toString());
      field.clear();
      records.add(fields);
      fields = <String>[];
      i++;
      continue;
    }
    field.write(ch);
    i++;
  }
  if (field.isNotEmpty || fields.isNotEmpty) {
    fields.add(field.toString());
    records.add(fields);
  }
  return records;
}

Shift _shift({
  String employeeName = 'Anna',
  String title = 'Fruehdienst',
  String? team = 'Service',
  String? notes,
}) {
  return Shift(
    orgId: 'org-1',
    userId: 'employee-1',
    employeeName: employeeName,
    title: title,
    startTime: DateTime(2026, 4, 1, 6),
    endTime: DateTime(2026, 4, 1, 14),
    breakMinutes: 30,
    teamId: 'team-1',
    team: team,
    notes: notes,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('de_DE'));

  group('ExportService.buildLohnjournalCsv (PA-6.3)', () {
    test('BOM, Kopf, alphabetische Sortierung + Umlagen-Spalten', () {
      final records = [
        const PayrollRecord(
          orgId: 'org-1', userId: 'u-b', periodYear: 2026, periodMonth: 6,
          grossCents: 300000, netCents: 210000, employerTotalCents: 360000,
          employerU1Cents: 1200, employerU2Cents: 800,
          status: PayrollStatus.freigegeben,
        ),
        const PayrollRecord(
          orgId: 'org-1', userId: 'u-a', periodYear: 2026, periodMonth: 6,
          grossCents: 50000, netCents: 50000, status: PayrollStatus.freigegeben,
        ),
      ];
      final csv = ExportService.buildLohnjournalCsv(
        records: records,
        employeeName: (uid) => uid == 'u-a' ? 'Anna' : 'Bernd',
        monthLabel: '06/2026',
      );
      expect(csv.codeUnitAt(0), 0xFEFF); // BOM
      expect(csv, contains('Lohnjournal'));
      expect(csv, contains('06/2026'));
      final rows = _parseCsv(csv);
      // Header-Zeile hat 18 Spalten.
      final header = rows.firstWhere((r) => r.contains('Mitarbeiter'));
      expect(header.length, 18);
      // Datenzeilen: Anna VOR Bernd (alphabetisch).
      final dataRows = rows.where((r) => r.isNotEmpty &&
          (r.first == 'Anna' || r.first == 'Bernd')).toList();
      expect(dataRows.map((r) => r.first), ['Anna', 'Bernd']);
    });
  });

  group('ExportService.buildAuditLogCsv', () {
    test('BOM, Kopfzeile und neueste-zuerst-Sortierung', () {
      final csv = ExportService.buildAuditLogCsv(entries: [
        AuditLogEntry(
          orgId: 'org-1',
          action: AuditAction.created,
          entityType: 'Lieferant',
          entityId: 's-1',
          summary: 'Lieferant „Nord" angelegt',
          actorName: 'Inhaber',
          createdAt: DateTime(2026, 6, 20, 9, 0),
        ),
        AuditLogEntry(
          orgId: 'org-1',
          action: AuditAction.corrected,
          entityType: 'Zeiteintrag',
          summary: 'Stempelzeit korrigiert',
          actorName: 'Inhaber',
          createdAt: DateTime(2026, 6, 22, 14, 30),
        ),
      ]);

      expect(csv, startsWith('﻿'));
      expect(
        csv,
        contains('Zeitpunkt;Aktion;Objekttyp;Objekt-ID;'
            'Zusammenfassung;Benutzer'),
      );
      // „Korrigiert" (22.06.) muss vor „Angelegt" (20.06.) stehen.
      expect(
        csv.indexOf('Korrigiert'),
        lessThan(csv.indexOf('Angelegt')),
      );
      expect(csv, contains('Lieferant'));
    });
  });

  group('ExportService.buildShiftPlanCsv – Escaping/Struktur (Matrix)', () {
    // Standardbereich für die 06:00–14:00-Schicht (1 Tag → 1 Datumsspalte).
    String csvFor(List<Shift> shifts, {String rangeLabel = 'Test'}) {
      return ExportService.buildShiftPlanCsv(
        shifts: shifts,
        rangeStart: DateTime(2026, 4, 1),
        rangeEnd: DateTime(2026, 4, 2),
        rangeLabel: rangeLabel,
      );
    }

    test('beginnt mit UTF-8-BOM und Export-Kopf', () {
      final csv = csvFor(const [], rangeLabel: '01.04.2026 - 07.04.2026');
      expect(csv, startsWith('﻿'));
      expect(csv, contains('Schichtplan Export'));
      expect(csv, contains('Zeitraum;01.04.2026 - 07.04.2026'));
    });

    test('Mitarbeiter-Zeile (Matrix-Kopf) ist vorhanden', () {
      final csv = csvFor([_shift(employeeName: 'Anna')]);
      expect(csv, contains('Mitarbeiter;'));
    });

    test('quotet Mitarbeiternamen mit Semikolon', () {
      final csv = csvFor([_shift(employeeName: 'Anna; Berta')]);
      expect(csv, contains('"Anna; Berta"'));
    });

    test('verdoppelt Anfuehrungszeichen und quotet das Feld (RFC 4180)', () {
      final csv = csvFor([_shift(employeeName: 'Anna "A"')]);
      expect(csv, contains('"Anna ""A"""'));
    });

    test('quotet Felder mit Zeilenumbruch', () {
      final csv = csvFor([_shift(employeeName: 'Zeile 1\nZeile 2')]);
      expect(csv, contains('"Zeile 1\nZeile 2"'));
    });

    test('neutralisiert Formel-Praefixe gegen CSV-Injection (probleme #7)', () {
      // Standortname als Vektor — landet in der Sektions-Kopfzeile.
      final csv = csvFor([
        Shift(
          orgId: 'org-1',
          userId: 'employee-1',
          employeeName: 'Anna',
          title: 'x',
          startTime: DateTime(2026, 4, 1, 6),
          endTime: DateTime(2026, 4, 1, 14),
          breakMinutes: 30,
          siteId: 'site-1',
          siteName: '=HYPERLINK("http://evil","x")',
        ),
      ]);
      expect(csv, contains("'=HYPERLINK"));
      expect(csv, isNot(contains('\n=HYPERLINK')));
    });

    test('quotet Felder mit alleinstehendem Carriage-Return (probleme #38)', () {
      final csv = csvFor([_shift(employeeName: 'Zeile\rUmbruch')]);
      expect(csv, contains('"Zeile\rUmbruch"'));
    });

    test('quotet kombinierte Sonderzeichen in der Zeitraum-Metazeile', () {
      final csv = csvFor(const [], rangeLabel: 'KW; "April" 2026');
      expect(csv, contains('Zeitraum;"KW; ""April"" 2026"'));
    });

    test('laesst einfache Felder ohne Sonderzeichen unquotiert', () {
      final csv = csvFor([_shift(employeeName: 'Anna')]);
      expect(csv, contains('Anna'));
      expect(csv, isNot(contains('"Anna"')));
    });

    test(
      'Sonderzeichen zerstoeren die Spaltenstruktur nicht '
      '(verlustfreier Round-Trip)',
      () {
        final csv = csvFor([_shift(employeeName: 'Mueller; Anna')]);

        final records = _parseCsv(csv);
        final headerIndex = records
            .indexWhere((r) => r.isNotEmpty && r.first == 'Mitarbeiter');
        expect(headerIndex, isNonNegative, reason: 'Matrix-Kopfzeile gefunden');
        // Mitarbeiter + 1 Datumsspalte + Summe (h) = 3 Spalten.
        expect(records[headerIndex].length, 3);

        final dataRow = records[headerIndex + 1];
        expect(dataRow.length, 3,
            reason: 'Datenzeile behaelt trotz Sonderzeichen die Spaltenzahl');
        expect(dataRow[0], 'Mueller; Anna'); // Mitarbeiter
        expect(dataRow[1], '06:00–14:00'); // Zelle (Uhrzeit-Spanne)
      },
    );
  });
}
