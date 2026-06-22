import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/datev_export.dart';
import 'package:worktime_app/models/finance_models.dart';

void main() {
  const center = CostCenter(
    id: 'c1',
    orgId: 'o',
    number: '1001',
    name: 'Strichmännchen',
    costBearerRef: 'KT-01',
  );
  const type = CostType(id: 't1', orgId: 'o', number: '4100', name: 'Miete');

  final entries = [
    JournalEntry(
      orgId: 'o',
      date: DateTime(2026, 3, 15),
      costCenterId: 'c1',
      costTypeId: 't1',
      description: 'Märzmiete',
      amountCents: 123456, // Kosten
      reference: 'RE-42',
    ),
    JournalEntry(
      orgId: 'o',
      date: DateTime(2026, 4, 1),
      costCenterId: 'c1',
      costTypeId: 't1',
      description: 'Erstattung',
      amountCents: -5000, // Gutschrift
    ),
  ];

  String build() => DatevExport.buildBuchungsstapel(
        entries: entries,
        centersById: const {'c1': center},
        typesById: const {'t1': type},
        year: 2026,
        config: const DatevExportConfig(
          consultantNumber: '1234567',
          clientNumber: '54321',
          accountLength: 4,
          defaultContraAccount: '9000',
          designation: 'Stapel 2026',
        ),
        generatedAt: DateTime(2026, 6, 22, 9, 30, 15, 7),
      );

  group('DatevExport (EXTF Buchungsstapel)', () {
    test('Kopfzeile + Spaltenkopf strukturieren den Stapel', () {
      final lines = build().split('\r\n');
      expect(lines.first,
          startsWith('"EXTF";700;21;"Buchungsstapel";9;20260622093015007;'));
      expect(lines.first, contains(';1234567;54321;20260101;4;'));
      // Spaltenkopf: KOST1 an Position 37 (Index 36).
      final header = lines[1].split(';');
      expect(header.length, DatevExport.fieldNames.length);
      expect(header[36], '"KOST1 - Kostenstelle"');
      expect(header[0], '"Umsatz (ohne Soll/Haben-Kz)"');
    });

    test('Datenzeile: Betrag/Vorzeichen/Konto/Datum/KOST korrekt', () {
      final lines = build().split('\r\n');
      // Zeile 3 (Index 2) = erste Buchung (123456 Cent Kosten, 15.03.).
      final cols = lines[2].split(';');
      expect(cols[0], '1234,56'); // Umsatz ohne Vorzeichen, Komma-Dezimal
      expect(cols[1], 'S'); // Kosten -> Soll
      expect(cols[2], '"EUR"');
      expect(cols[6], '4100'); // Konto = Kostenart-Nr (nur Ziffern, unquoted)
      expect(cols[7], '9000'); // Gegenkonto
      expect(cols[9], '1503'); // Belegdatum TTMM
      expect(cols[10], '"RE-42"'); // Belegfeld 1
      expect(cols[13], '"Märzmiete"'); // Buchungstext
      expect(cols[36], '"1001"'); // KOST1 = Kostenstellen-Nr (Textfeld, quoted)
      expect(cols[37], '"KT-01"'); // KOST2 = Kostenträger
    });

    test('Gutschrift wird zu Haben (H) mit positivem Betrag', () {
      final lines = build().split('\r\n');
      final cols = lines[3].split(';'); // zweite Buchung (-5000)
      expect(cols[0], '50,00');
      expect(cols[1], 'H');
    });

    test('nur Buchungen des Geschäftsjahres + CRLF-Zeilenenden', () {
      final out = build();
      expect(out.contains('\r\n'), isTrue);
      // 1 Kopf + 1 Spaltenkopf + 2 Daten + abschließendes CRLF -> 5 Segmente.
      final segments = out.split('\r\n');
      expect(segments.where((s) => s.isNotEmpty).length, 4);

      // Buchung aus anderem Jahr wird ausgeschlossen.
      final withOther = DatevExport.buildBuchungsstapel(
        entries: [
          ...entries,
          JournalEntry(
            orgId: 'o',
            date: DateTime(2025, 12, 31),
            costCenterId: 'c1',
            costTypeId: 't1',
            description: 'Vorjahr',
            amountCents: 999,
          ),
        ],
        centersById: const {'c1': center},
        typesById: const {'t1': type},
        year: 2026,
        config: const DatevExportConfig(),
        generatedAt: DateTime(2026, 6, 22),
      );
      expect(withOther.contains('Vorjahr'), isFalse);
    });
  });
}
