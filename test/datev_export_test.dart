import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/datev_export.dart';
import 'package:worktime_app/models/finance_models.dart';
import 'package:worktime_app/services/export_service.dart';

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

    test('DatevExportConfig round-trip + accountLength-Clamp', () {
      const c = DatevExportConfig(
        consultantNumber: '1234567',
        clientNumber: '54321',
        accountLength: 6,
        defaultContraAccount: '8400',
        designation: 'Stapel',
        revenueAccountByRate: {19: 'ct19', 7: 'ct7'},
      );
      final r = DatevExportConfig.fromMap(c.toMap());
      expect(r.consultantNumber, '1234567');
      expect(r.clientNumber, '54321');
      expect(r.accountLength, 6);
      expect(r.defaultContraAccount, '8400');
      expect(r.designation, 'Stapel');
      // P2.0: Satz→Erlöskonto-Mapping überlebt den Round-trip (String-JSON-Keys).
      expect(r.revenueAccountByRate, {19: 'ct19', 7: 'ct7'});
      // Sachkontenlänge wird auf 4..8 geklemmt.
      expect(DatevExportConfig.fromMap({'account_length': 99}).accountLength, 8);
      expect(DatevExportConfig.fromMap({'account_length': 2}).accountLength, 4);
      expect(DatevExportConfig.fromMap(const {}).defaultContraAccount, '9000');
    });

    test('Konfiguration fließt in die Kopfzeile ein', () {
      final out = DatevExport.buildBuchungsstapel(
        entries: entries,
        centersById: const {'c1': center},
        typesById: const {'t1': type},
        year: 2026,
        config: const DatevExportConfig(
          consultantNumber: '7777',
          clientNumber: '8888',
          accountLength: 5,
        ),
        generatedAt: DateTime(2026, 6, 22),
      );
      expect(out.split('\r\n').first, contains(';7777;8888;20260101;5;'));
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

  group('DatevExportConfig Serialisierung (DATEV-1)', () {
    const config = DatevExportConfig(
      consultantNumber: '1234567',
      clientNumber: '54321',
      accountLength: 5,
      defaultContraAccount: '9000',
      designation: 'Stapel',
      revenueAccountByRate: {19: '8400', 7: '8300'},
    );

    test('snake_case round-trippt (toMap/fromMap) inkl. schemaVersion', () {
      final map = config.toMap();
      expect(map['schema_version'], 1);
      final restored = DatevExportConfig.fromMap(map);
      expect(restored.consultantNumber, '1234567');
      expect(restored.clientNumber, '54321');
      expect(restored.accountLength, 5);
      expect(restored.defaultContraAccount, '9000');
      expect(restored.revenueAccountByRate, {19: '8400', 7: '8300'});
      expect(restored.schemaVersion, 1);
    });

    test('camelCase round-trippt (toFirestoreMap/fromFirestore); '
        'Map-Keys als Strings', () {
      final fs = config.toFirestoreMap();
      expect(fs['schemaVersion'], 1);
      // int-Keys der Rate-Map MÜSSEN als String serialisiert sein.
      expect((fs['revenueAccountByRate'] as Map).keys, containsAll(['19', '7']));
      final cloud = DatevExportConfig.fromFirestore('datev', fs);
      expect(cloud.consultantNumber, '1234567');
      expect(cloud.accountLength, 5);
      expect(cloud.revenueAccountByRate, {19: '8400', 7: '8300'});
    });

    test('fehlende schema_version defaultet tolerant auf 1', () {
      final restored = DatevExportConfig.fromMap(const {
        'consultant_number': '1',
        'client_number': '2',
      });
      expect(restored.schemaVersion, 1);
    });

    test('firestoreDocId ist die feste Singleton-ID', () {
      expect(DatevExportConfig.firestoreDocId, 'datev');
    });
  });

  group('DATEV-3: Deterministik + buildDatevExport', () {
    const center = CostCenter(id: 'c1', orgId: 'o', number: '1001', name: 'L');
    const type = CostType(id: 't1', orgId: 'o', number: '4100', name: 'M');

    // Drei Buchungen am GLEICHEN Tag mit unterschiedlichen IDs.
    JournalEntry e(String id, int amount) => JournalEntry(
          id: id,
          orgId: 'o',
          date: DateTime(2026, 3, 15),
          costCenterId: 'c1',
          costTypeId: 't1',
          description: 'B$id',
          amountCents: amount,
        );

    String buildFrom(List<JournalEntry> entries) =>
        DatevExport.buildBuchungsstapel(
          entries: entries,
          centersById: const {'c1': center},
          typesById: const {'t1': type},
          year: 2026,
          config: const DatevExportConfig(defaultContraAccount: '9000'),
          generatedAt: DateTime(2026, 6, 22),
        );

    test('gleiches Datum: Reihenfolge der Eingabe ändert den Output NICHT', () {
      final a = buildFrom([e('a', 100), e('b', 200), e('c', 300)]);
      final b = buildFrom([e('c', 300), e('a', 100), e('b', 200)]);
      expect(a, b, reason: 'totale (date,id)-Ordnung → stabiler Stapel');
    });

    test('buildDatevExport: sha256/entryCount/soll/haben + Reproduzierbarkeit',
        () {
      final r1 = ExportService.buildDatevExport(
        entries: [e('a', 1000), e('b', -400)],
        centersById: const {'c1': center},
        typesById: const {'t1': type},
        year: 2026,
        generatedAt: DateTime(2026, 6, 22, 9),
        config: const DatevExportConfig(defaultContraAccount: '9000'),
      );
      expect(r1.entryCount, 2);
      expect(r1.sollCents, 1000); // amount >= 0
      expect(r1.habenCents, 400); // |amount < 0|
      expect(r1.sha256, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(r1.fileName, 'EXTF_Buchungsstapel_2026.csv');

      // Gleiche Eingaben + gleicher generatedAt → identischer Hash.
      final r2 = ExportService.buildDatevExport(
        entries: [e('b', -400), e('a', 1000)],
        centersById: const {'c1': center},
        typesById: const {'t1': type},
        year: 2026,
        generatedAt: DateTime(2026, 6, 22, 9),
        config: const DatevExportConfig(defaultContraAccount: '9000'),
      );
      expect(r2.sha256, r1.sha256);
    });
  });
}
