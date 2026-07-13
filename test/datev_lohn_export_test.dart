import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/datev_lohn_export.dart';
import 'package:worktime_app/models/employee_profile.dart';
import 'package:worktime_app/models/pay_line_type.dart';
import 'package:worktime_app/models/payroll_record.dart';

void main() {
  group('isValidDatevPersonalnummer', () {
    test('akzeptiert 1–5-stellige Ziffernfolgen > 0', () {
      expect(isValidDatevPersonalnummer('1'), isTrue);
      expect(isValidDatevPersonalnummer('42'), isTrue);
      expect(isValidDatevPersonalnummer('99999'), isTrue);
      // führende Nullen erlaubt, solange der Zahlwert > 0 ist
      expect(isValidDatevPersonalnummer('007'), isTrue);
      // getrimmt
      expect(isValidDatevPersonalnummer('  12 '), isTrue);
    });

    test('verwirft leer, zu lang, Nicht-Ziffern und Nullwert', () {
      expect(isValidDatevPersonalnummer(null), isFalse);
      expect(isValidDatevPersonalnummer(''), isFalse);
      expect(isValidDatevPersonalnummer('   '), isFalse);
      expect(isValidDatevPersonalnummer('123456'), isFalse); // 6-stellig
      expect(isValidDatevPersonalnummer('12a'), isFalse);
      expect(isValidDatevPersonalnummer('A1'), isFalse);
      expect(isValidDatevPersonalnummer('0'), isFalse);
      expect(isValidDatevPersonalnummer('00000'), isFalse);
      expect(isValidDatevPersonalnummer('-1'), isFalse);
    });
  });

  group('findePersonalnummerProbleme', () {
    test('meldet fehlende Personalnummer', () {
      final probleme = findePersonalnummerProbleme([
        (userId: 'u1', personnelNumber: null),
        (userId: 'u2', personnelNumber: '   '),
      ]);
      expect(probleme.length, 2);
      expect(probleme.every((p) => p.art == PersonalnummerProblemArt.fehlt),
          isTrue);
      expect(probleme.map((p) => p.userId), ['u1', 'u2']);
    });

    test('meldet ungültige Personalnummer', () {
      final probleme = findePersonalnummerProbleme([
        (userId: 'u1', personnelNumber: '12a'),
        (userId: 'u2', personnelNumber: '0'),
      ]);
      expect(probleme.length, 2);
      expect(
        probleme.every((p) => p.art == PersonalnummerProblemArt.ungueltig),
        isTrue,
      );
    });

    test('meldet Dopplung an ALLEN beteiligten Mitarbeitern', () {
      final probleme = findePersonalnummerProbleme([
        (userId: 'u1', personnelNumber: '42'),
        (userId: 'u2', personnelNumber: '42'),
        (userId: 'u3', personnelNumber: '7'),
      ]);
      final doppelt = probleme
          .where((p) => p.art == PersonalnummerProblemArt.doppelt)
          .toList();
      expect(doppelt.map((p) => p.userId), ['u1', 'u2']);
      // u3 ist eindeutig → kein Problem
      expect(probleme.any((p) => p.userId == 'u3'), isFalse);
    });

    test('Leading-Zero-Äquivalenz: 007 und 7 sind eine Kollision', () {
      final probleme = findePersonalnummerProbleme([
        (userId: 'u1', personnelNumber: '007'),
        (userId: 'u2', personnelNumber: '7'),
      ]);
      final doppelt = probleme
          .where((p) => p.art == PersonalnummerProblemArt.doppelt)
          .map((p) => p.userId)
          .toList();
      expect(doppelt, ['u1', 'u2']);
    });

    test('gültige eindeutige Nummern ergeben keine Probleme', () {
      final probleme = findePersonalnummerProbleme([
        (userId: 'u1', personnelNumber: '1'),
        (userId: 'u2', personnelNumber: '2'),
      ]);
      expect(probleme, isEmpty);
    });

    test('ungültige zählen NICHT als Dopplung (leere Felder)', () {
      final probleme = findePersonalnummerProbleme([
        (userId: 'u1', personnelNumber: '0'),
        (userId: 'u2', personnelNumber: '0'),
      ]);
      expect(
        probleme.every((p) => p.art == PersonalnummerProblemArt.ungueltig),
        isTrue,
      );
      expect(probleme.any((p) => p.art == PersonalnummerProblemArt.doppelt),
          isFalse);
    });

    test('wirft nie, auch bei leerer Eingabe', () {
      expect(findePersonalnummerProbleme(const []), isEmpty);
    });
  });

  group('DatevLohnConfig Serialisierung (PERSONAL-2)', () {
    const config = DatevLohnConfig(
      format: DatevLohnFormat.lohnUndGehalt,
      beraterNr: '1234567',
      mandantenNr: '54321',
      festeLohnartGrundlohn: '100',
    );

    test('snake_case round-trippt + schemaVersion', () {
      final map = config.toMap();
      expect(map['schema_version'], 1);
      expect(map['format'], 'lohn_und_gehalt');
      final r = DatevLohnConfig.fromMap(map);
      expect(r.beraterNr, '1234567');
      expect(r.festeLohnartGrundlohn, '100');
      expect(r.format, DatevLohnFormat.lohnUndGehalt);
    });

    test('camelCase round-trippt', () {
      final fs = config.toFirestoreMap();
      expect(fs['format'], 'lohn_und_gehalt');
      final r = DatevLohnConfig.fromFirestore('datevLohn', fs);
      expect(r.mandantenNr, '54321');
      expect(r.format, DatevLohnFormat.lohnUndGehalt);
    });

    test('isConfigured / Format-Enum-Default', () {
      expect(const DatevLohnConfig().isConfigured, isFalse);
      expect(config.isConfigured, isTrue);
      expect(DatevLohnFormatX.fromValue('zzz'), DatevLohnFormat.lodas);
    });
  });

  group('buildBewegungsdaten (PERSONAL-2)', () {
    EmployeeProfile profile(String userId, String? nummer) =>
        EmployeeProfile(orgId: 'o', userId: userId, personnelNumber: nummer);

    PayrollRecord record(
      String userId, {
      required PayrollStatus status,
      int grossCents = 300000,
      int? istMinutes = 9600, // 160 h
      List<PayrollLine> lines = const [],
    }) =>
        PayrollRecord(
          orgId: 'o',
          userId: userId,
          periodYear: 2026,
          periodMonth: 6,
          grossCents: grossCents,
          istMinutes: istMinutes,
          status: status,
          lines: lines,
        );

    const config = DatevLohnConfig(
      format: DatevLohnFormat.lodas,
      beraterNr: '1234567',
      mandantenNr: '54321',
      festeLohnartGrundlohn: '100',
    );

    test('2 MA × Grundlohn + Zuschlagszeilen → deterministische Datei', () {
      final ergebnis = buildBewegungsdaten(
        config: config,
        records: [
          record('u1', status: PayrollStatus.freigegeben, lines: const [
            PayrollLine(
              name: 'Nachtzuschlag',
              datevLohnartNr: '200',
              amountCents: 5000,
              kind: PayLineKind.zuschlag3b,
              mengeStunden: 8.0,
            ),
          ]),
          record('u2', status: PayrollStatus.bezahlt, grossCents: 200000,
              istMinutes: 6000, lines: const [
            PayrollLine(name: 'VwL', datevLohnartNr: '300', amountCents: -4000),
          ]),
        ],
        profilesByUserId: {
          'u1': profile('u1', '7'),
          'u2': profile('u2', '12'),
        },
        payLineTypes: const [],
        jahr: 2026,
        monat: 6,
      );
      final lines = ergebnis.content.split('\r\n');
      expect(lines[0], 'DATEV-LOHN;lodas;1234567;54321;062026');
      expect(lines[1], 'Personalnummer;Lohnart;Menge;Betrag');
      // u1: Grundlohn (160h/3000€) + Nachtzuschlag (8h/50€)
      expect(lines[2], '7;100;160,00;3000,00');
      expect(lines[3], '7;200;8,00;50,00');
      // u2: Grundlohn (100h/2000€) + VwL (-40€, keine Menge)
      expect(lines[4], '12;100;100,00;2000,00');
      expect(lines[5], '12;300;;-40,00');
      expect(ergebnis.zeilenAnzahl, 4);
      expect(ergebnis.probleme, isEmpty);
      expect(ergebnis.subjectUserIds..sort(), ['u1', 'u2']);
    });

    test('Format-Token unterscheidet Lohn&Gehalt', () {
      final ergebnis = buildBewegungsdaten(
        config: config.copyWith(format: DatevLohnFormat.lohnUndGehalt),
        records: [record('u1', status: PayrollStatus.freigegeben)],
        profilesByUserId: {'u1': profile('u1', '7')},
        payLineTypes: const [],
        jahr: 2026,
        monat: 6,
      );
      expect(ergebnis.content.split('\r\n').first,
          'DATEV-LOHN;lohn_und_gehalt;1234567;54321;062026');
    });

    test('nur freigegeben/bezahlt; Entwurf wird ignoriert', () {
      final ergebnis = buildBewegungsdaten(
        config: config,
        records: [record('u1', status: PayrollStatus.entwurf)],
        profilesByUserId: {'u1': profile('u1', '7')},
        payLineTypes: const [],
        jahr: 2026,
        monat: 6,
      );
      expect(ergebnis.zeilenAnzahl, 0);
    });

    test('Probleme: fehlende Personalnummer, fehlende Lohnart, Grundlohn ohne '
        'Menge', () {
      final ergebnis = buildBewegungsdaten(
        config: config,
        records: [
          // keine Personalnummer → ganzer Record als Problem, keine Zeilen
          record('u1', status: PayrollStatus.freigegeben),
          // Grundlohn ohne istMinutes + Zeile ohne Lohnart
          record('u2', status: PayrollStatus.freigegeben, istMinutes: null,
              lines: const [
            PayrollLine(name: 'Ad-hoc-Zulage', amountCents: 1000),
          ]),
        ],
        profilesByUserId: {
          'u1': profile('u1', null),
          'u2': profile('u2', '12'),
        },
        payLineTypes: const [],
        jahr: 2026,
        monat: 6,
      );
      final msgs = ergebnis.probleme.map((p) => p.message).join(' | ');
      expect(msgs, contains('Keine Personalnummer'));
      expect(msgs, contains('Grundlohn ohne Stundenmenge'));
      expect(msgs, contains('ohne Lohnartnummer'));
      // u1 hat keine gültige Nummer → nicht in subjectUserIds
      expect(ergebnis.subjectUserIds, ['u2']);
      // Grundlohn-Zeile von u2 wird trotz fehlender Menge geschrieben (leer)
      expect(ergebnis.content, contains('12;100;;3000,00'));
    });

    test('Q2 Re-Download: serializeLohnBewegungsdaten aus rowsSnapshot ist '
        'byte-identisch', () {
      final ergebnis = buildBewegungsdaten(
        config: config,
        records: [
          record('u1', status: PayrollStatus.freigegeben, lines: const [
            PayrollLine(
                name: 'Nacht',
                datevLohnartNr: '200',
                amountCents: 5000,
                mengeStunden: 8.0),
          ]),
        ],
        profilesByUserId: {'u1': profile('u1', '7')},
        payLineTypes: const [],
        jahr: 2026,
        monat: 6,
      );
      // Re-Download baut die Datei NUR aus dem Snapshot (nie aus Live-Daten).
      final wieder = serializeLohnBewegungsdaten(
        config: config,
        rows: ergebnis.rows,
        jahr: 2026,
        monat: 6,
      );
      expect(wieder, ergebnis.content);
    });

    test('Lohnart aus PayLineType-Katalog aufgelöst, wenn Zeile keine trägt',
        () {
      final ergebnis = buildBewegungsdaten(
        config: config,
        records: [
          record('u1', status: PayrollStatus.freigegeben, lines: const [
            PayrollLine(
                name: 'Prämie', lineTypeId: 'lt1', amountCents: 10000),
          ]),
        ],
        profilesByUserId: {'u1': profile('u1', '7')},
        payLineTypes: const [
          PayLineType(id: 'lt1', orgId: 'o', name: 'Prämie', datevLohnartNr: '400'),
        ],
        jahr: 2026,
        monat: 6,
      );
      expect(ergebnis.content, contains('7;400;;100,00'));
      expect(ergebnis.probleme, isEmpty);
    });
  });
}
