import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
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

  group('ExportService.buildShiftPlanCsv – Escaping/Struktur', () {
    test('beginnt mit UTF-8-BOM und deutscher Kopfzeile', () {
      final csv = ExportService.buildShiftPlanCsv(
        shifts: const [],
        rangeLabel: '01.04.2026 - 07.04.2026',
      );
      expect(csv, startsWith('﻿'));
      expect(
        csv,
        contains(
          'Datum;Wochentag;Beginn;Ende;Pause (min);Stunden;'
          'Mitarbeiter;Titel;Team;Status;Notiz',
        ),
      );
    });

    test('quotet Felder mit Semikolon', () {
      final csv = ExportService.buildShiftPlanCsv(
        shifts: [_shift(employeeName: 'Anna; Berta')],
        rangeLabel: 'Test',
      );
      expect(csv, contains('"Anna; Berta"'));
    });

    test('verdoppelt Anfuehrungszeichen und quotet das Feld (RFC 4180)', () {
      final csv = ExportService.buildShiftPlanCsv(
        shifts: [_shift(title: 'Schicht "A"')],
        rangeLabel: 'Test',
      );
      expect(csv, contains('"Schicht ""A"""'));
    });

    test('quotet Felder mit Zeilenumbruch', () {
      final csv = ExportService.buildShiftPlanCsv(
        shifts: [_shift(notes: 'Zeile 1\nZeile 2')],
        rangeLabel: 'Test',
      );
      expect(csv, contains('"Zeile 1\nZeile 2"'));
    });

    test('quotet kombinierte Sonderzeichen in der Zeitraum-Metazeile', () {
      final csv = ExportService.buildShiftPlanCsv(
        shifts: const [],
        rangeLabel: 'KW; "April" 2026',
      );
      expect(csv, contains('Zeitraum;"KW; ""April"" 2026"'));
    });

    test('laesst einfache Felder ohne Sonderzeichen unquotiert', () {
      final csv = ExportService.buildShiftPlanCsv(
        shifts: [_shift(employeeName: 'Anna', title: 'Fruehdienst')],
        rangeLabel: 'Test',
      );
      expect(csv, contains('Anna'));
      expect(csv, isNot(contains('"Anna"')));
      expect(csv, isNot(contains('"Fruehdienst"')));
    });

    test(
      'Sonderzeichen zerstoeren die Spaltenstruktur nicht '
      '(11 Felder, verlustfreier Round-Trip)',
      () {
        final csv = ExportService.buildShiftPlanCsv(
          shifts: [
            _shift(
              employeeName: 'Mueller; Anna',
              title: 'Schicht "A"',
              team: 'Service;Kasse',
              notes: 'Zeile1\nZeile2; mit "Anfuehrung"',
            ),
          ],
          rangeLabel: 'Test',
        );

        final records = _parseCsv(csv);
        final headerIndex =
            records.indexWhere((r) => r.isNotEmpty && r.first == 'Datum');
        expect(headerIndex, isNonNegative, reason: 'Kopfzeile gefunden');
        expect(records[headerIndex].length, 11);

        final dataRow = records[headerIndex + 1];
        expect(dataRow.length, 11,
            reason: 'Datenzeile behaelt trotz Sonderzeichen 11 Spalten');
        expect(dataRow[6], 'Mueller; Anna'); // Mitarbeiter
        expect(dataRow[7], 'Schicht "A"'); // Titel
        expect(dataRow[8], 'Service;Kasse'); // Team
        expect(dataRow[10], 'Zeile1\nZeile2; mit "Anfuehrung"'); // Notiz
      },
    );
  });
}
