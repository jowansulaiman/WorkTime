// lib/core/datev_lohn_export.dart

import '../core/firestore_num_parser.dart' as parse;
import '../models/employee_profile.dart';
import '../models/pay_line_type.dart';
import '../models/payroll_record.dart';

/// **DATEV-Lohn (PERSONAL-1/-2).** Personalnummer-Validierung (PERSONAL-1) +
/// purer LODAS-/Lohn&Gehalt-Bewegungsdaten-Builder (PERSONAL-2).
///
/// Alles hier ist **pure** (kein State/IO/`now()`), damit die Regeln offline
/// deterministisch testbar sind.

/// Prüft eine DATEV-Personalnummer nach den Formatregeln: **nur Ziffern,
/// 1–5 Stellen, numerisch ungleich 0**.
///
/// Führende Nullen sind zulässig (`'007'`), solange der Zahlwert > 0 ist;
/// `'0'`/`'00000'` sind ungültig (DATEV vergibt keine Personalnummer 0).
/// Leerzeichen werden vorher getrimmt.
bool isValidDatevPersonalnummer(String? nummer) {
  final trimmed = nummer?.trim() ?? '';
  if (trimmed.isEmpty || trimmed.length > 5) return false;
  if (!RegExp(r'^\d+$').hasMatch(trimmed)) return false;
  return int.parse(trimmed) > 0;
}

/// Art eines Personalnummer-Problems (typisiert statt Roh-Strings, damit die
/// UI die Fälle unterscheiden und die Tests auf die Art asserten können).
enum PersonalnummerProblemArt {
  /// Keine Personalnummer hinterlegt.
  fehlt,

  /// Personalnummer vorhanden, aber formal ungültig (Format/Länge/Nullwert).
  ungueltig,

  /// Personalnummer wird von mehreren Mitarbeitern getragen (kollidiert).
  doppelt,
}

extension PersonalnummerProblemArtLabel on PersonalnummerProblemArt {
  /// Deutsches Kurzlabel für die Inline-Warnung.
  String get label => switch (this) {
        PersonalnummerProblemArt.fehlt => 'Personalnummer fehlt',
        PersonalnummerProblemArt.ungueltig => 'Personalnummer ungültig',
        PersonalnummerProblemArt.doppelt => 'Personalnummer doppelt',
      };
}

/// Ein einzelnes Personalnummer-Problem eines Mitarbeiters (transient, keine
/// Collection — Muster `DatevExportFinding`/`ComplianceViolation`).
class PersonalnummerProblem {
  const PersonalnummerProblem({
    required this.userId,
    required this.art,
    this.personnelNumber,
  });

  /// Betroffener Mitarbeiter.
  final String userId;

  /// Art des Problems.
  final PersonalnummerProblemArt art;

  /// Die (ggf. ungültige/kollidierende) Nummer — `null` bei [fehlt].
  final String? personnelNumber;

  @override
  bool operator ==(Object other) =>
      other is PersonalnummerProblem &&
      other.userId == userId &&
      other.art == art &&
      other.personnelNumber == personnelNumber;

  @override
  int get hashCode => Object.hash(userId, art, personnelNumber);

  @override
  String toString() =>
      'PersonalnummerProblem($userId, ${art.name}, $personnelNumber)';
}

/// Eingabe-Datensatz für [findePersonalnummerProbleme] — je Mitarbeiter die
/// Kennung und die (rohe) Personalnummer aus der Stammakte.
typedef PersonalnummerEintrag = ({String userId, String? personnelNumber});

/// Sammelt alle Personalnummer-Probleme über eine Mitarbeitermenge — **wirft
/// nie**, gibt eine typisierte Liste zurück (in Eingabereihenfolge; Duplikate
/// werden für jeden beteiligten Mitarbeiter gemeldet).
///
/// - **fehlt:** keine (leere) Personalnummer.
/// - **ungueltig:** vorhanden, aber [isValidDatevPersonalnummer] == false.
/// - **doppelt:** dieselbe (getrimmte) gültige Nummer bei ≥2 Mitarbeitern.
///
/// Ungültige Nummern werden NICHT zusätzlich auf Dopplung geprüft (die
/// Ungültigkeit ist das dominante Problem), sonst würden z. B. mehrere leere
/// Felder als „doppelt 0" gemeldet.
List<PersonalnummerProblem> findePersonalnummerProbleme(
  Iterable<PersonalnummerEintrag> mitarbeiter,
) {
  final eintraege = mitarbeiter.toList(growable: false);

  // Erst zählen, welche gültigen Nummern mehrfach vorkommen. Dedup über den
  // NUMERISCHEN Wert (nicht den Roh-String): DATEV-Personalnummern sind
  // numerisch, führende Nullen sind nicht signifikant — '007' und '7' laufen
  // im Export unter derselben Nummer und sind daher eine echte Kollision.
  final anzahlProNummer = <int, int>{};
  for (final e in eintraege) {
    final trimmed = e.personnelNumber?.trim() ?? '';
    if (isValidDatevPersonalnummer(trimmed)) {
      final value = int.parse(trimmed);
      anzahlProNummer[value] = (anzahlProNummer[value] ?? 0) + 1;
    }
  }

  final probleme = <PersonalnummerProblem>[];
  for (final e in eintraege) {
    final raw = e.personnelNumber?.trim() ?? '';
    if (raw.isEmpty) {
      probleme.add(PersonalnummerProblem(
        userId: e.userId,
        art: PersonalnummerProblemArt.fehlt,
      ));
      continue;
    }
    if (!isValidDatevPersonalnummer(raw)) {
      probleme.add(PersonalnummerProblem(
        userId: e.userId,
        art: PersonalnummerProblemArt.ungueltig,
        personnelNumber: raw,
      ));
      continue;
    }
    if ((anzahlProNummer[int.parse(raw)] ?? 0) > 1) {
      probleme.add(PersonalnummerProblem(
        userId: e.userId,
        art: PersonalnummerProblemArt.doppelt,
        personnelNumber: raw,
      ));
    }
  }
  return probleme;
}

// ─── PERSONAL-2: DATEV-Lohn-Bewegungsdaten-Builder ──────────────────────────

/// Zielformat des DATEV-Lohn-Exports. `.value` = snake_case; `fromValue` hat
/// einen Default-Branch (wirft nie).
enum DatevLohnFormat { lodas, lohnUndGehalt }

extension DatevLohnFormatX on DatevLohnFormat {
  String get value => switch (this) {
        DatevLohnFormat.lodas => 'lodas',
        DatevLohnFormat.lohnUndGehalt => 'lohn_und_gehalt',
      };

  String get label => switch (this) {
        DatevLohnFormat.lodas => 'LODAS',
        DatevLohnFormat.lohnUndGehalt => 'Lohn & Gehalt',
      };

  static DatevLohnFormat fromValue(String? value) => switch (value) {
        'lohn_und_gehalt' => DatevLohnFormat.lohnUndGehalt,
        _ => DatevLohnFormat.lodas,
      };
}

/// Konfiguration des DATEV-Lohn-Exports (vom Steuerberater vorgegeben).
///
/// **Dual serialisiert** (Kopplung #1): [toFirestoreMap]/[fromFirestore]
/// camelCase (Singleton `financeConfig/datevLohn`, admin-only Rules-Block wie
/// DATEV-1), [toMap]/[fromMap] snake_case (lokaler Fallback-Key
/// `local_v2/datev_lohn_config`). Trägt `schemaVersion` (Leitplanke).
class DatevLohnConfig {
  const DatevLohnConfig({
    this.schemaVersion = 1,
    this.format = DatevLohnFormat.lodas,
    this.beraterNr = '',
    this.mandantenNr = '',
    this.festeLohnartGrundlohn = '',
  });

  /// Feste Doc-ID des Firestore-Singletons `financeConfig/datevLohn`.
  static const String firestoreDocId = 'datevLohn';

  final int schemaVersion;
  final DatevLohnFormat format;
  final String beraterNr;
  final String mandantenNr;

  /// Lohnart-Nummer, unter der der synthetisierte Grundlohn läuft.
  final String festeLohnartGrundlohn;

  /// Ob überhaupt fachliche Werte gepflegt sind (≠ reiner Default) — steuert
  /// wie bei [DatevExportConfig] die Lokal→Cloud-Migration.
  bool get isConfigured =>
      beraterNr.trim().isNotEmpty ||
      mandantenNr.trim().isNotEmpty ||
      festeLohnartGrundlohn.trim().isNotEmpty;

  DatevLohnConfig copyWith({
    int? schemaVersion,
    DatevLohnFormat? format,
    String? beraterNr,
    String? mandantenNr,
    String? festeLohnartGrundlohn,
  }) =>
      DatevLohnConfig(
        schemaVersion: schemaVersion ?? this.schemaVersion,
        format: format ?? this.format,
        beraterNr: beraterNr ?? this.beraterNr,
        mandantenNr: mandantenNr ?? this.mandantenNr,
        festeLohnartGrundlohn:
            festeLohnartGrundlohn ?? this.festeLohnartGrundlohn,
      );

  Map<String, dynamic> toMap() => {
        'schema_version': schemaVersion,
        'format': format.value,
        'berater_nr': beraterNr,
        'mandanten_nr': mandantenNr,
        'feste_lohnart_grundlohn': festeLohnartGrundlohn,
      };

  factory DatevLohnConfig.fromMap(Map<String, dynamic> map) => DatevLohnConfig(
        schemaVersion: parse.toInt(map['schema_version']) ?? 1,
        format: DatevLohnFormatX.fromValue(map['format']?.toString()),
        beraterNr: (map['berater_nr'] ?? '').toString(),
        mandantenNr: (map['mandanten_nr'] ?? '').toString(),
        festeLohnartGrundlohn:
            (map['feste_lohnart_grundlohn'] ?? '').toString(),
      );

  Map<String, dynamic> toFirestoreMap() => {
        'schemaVersion': schemaVersion,
        'format': format.value,
        'beraterNr': beraterNr,
        'mandantenNr': mandantenNr,
        'festeLohnartGrundlohn': festeLohnartGrundlohn,
      };

  factory DatevLohnConfig.fromFirestore(String id, Map<String, dynamic> map) =>
      DatevLohnConfig(
        schemaVersion: parse.toInt(map['schemaVersion']) ?? 1,
        format: DatevLohnFormatX.fromValue(map['format']?.toString()),
        beraterNr: (map['beraterNr'] ?? '').toString(),
        mandantenNr: (map['mandantenNr'] ?? '').toString(),
        festeLohnartGrundlohn:
            (map['festeLohnartGrundlohn'] ?? '').toString(),
      );
}

/// Ein Problem der Lohn-Vorprüfung (transient; deutsche Message, betroffener
/// Mitarbeiter). Sammelt fehlende Personalnummern/Lohnarten je Zeile.
class DatevLohnProblem {
  const DatevLohnProblem({
    required this.userId,
    required this.message,
    this.personalnummer,
  });

  final String userId;
  final String message;
  final String? personalnummer;

  @override
  String toString() => 'DatevLohnProblem($userId, $message)';
}

/// Ergebnis von [buildBewegungsdaten]: die fertige Datei + die gesammelten
/// Probleme (nie werfen — der Aufrufer zeigt sie als Vorprüfung).
class DatevLohnExportErgebnis {
  const DatevLohnExportErgebnis({
    required this.content,
    required this.probleme,
    required this.zeilenAnzahl,
    required this.summeCents,
    required this.subjectUserIds,
    required this.rows,
  });

  final String content;
  final List<DatevLohnProblem> probleme;
  final int zeilenAnzahl;
  final int summeCents;

  /// Betroffene Mitarbeiter (DSGVO-Auffindbarkeit, Q2 `subjectUserIds`).
  final List<String> subjectUserIds;

  /// **Q2 `rowsSnapshot`:** kanonische Zeilen `{personalnummer, lohnartNr,
  /// mengeStunden?, betragCents}` — der revisionssichere Re-Download baut die
  /// Datei ausschließlich hieraus (nie aus Live-Daten), via
  /// [serializeLohnBewegungsdaten].
  final List<Map<String, dynamic>> rows;
}

/// Deutsches Dezimalformat mit Komma (kein Float-Drift-Schutz nötig — reine
/// Anzeige-/Exportformatierung).
String _dez2(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

/// **Q2 Re-Download:** serialisiert kanonische [rows] (`{personalnummer,
/// lohnartNr, mengeStunden?, betragCents}`) + [config] zur Bewegungsdaten-Datei
/// — die EINZIGE Serialisierungsstelle (Builder UND revisionssicherer
/// Re-Download nutzen sie, damit die Datei byte-identisch reproduzierbar ist).
String serializeLohnBewegungsdaten({
  required DatevLohnConfig config,
  required List<Map<String, dynamic>> rows,
  required int jahr,
  required int monat,
}) {
  final periode =
      '${monat.toString().padLeft(2, '0')}${jahr.toString().padLeft(4, '0')}';
  final buf = StringBuffer();
  // Header (deterministisch; Format-Token unterscheidet LODAS/Lohn&Gehalt —
  // das genaue Zielformat bestätigt der Steuerberater, offene Frage 1).
  buf.write([
    'DATEV-LOHN',
    config.format.value,
    config.beraterNr,
    config.mandantenNr,
    periode,
  ].join(';'));
  buf.write('\r\n');
  buf.write(['Personalnummer', 'Lohnart', 'Menge', 'Betrag'].join(';'));
  buf.write('\r\n');
  for (final row in rows) {
    final menge = row['mengeStunden'];
    buf.write([
      (row['personalnummer'] ?? '').toString(),
      (row['lohnartNr'] ?? '').toString(),
      menge == null ? '' : _dez2((menge as num).toDouble()),
      _dez2((parse.toInt(row['betragCents']) ?? 0) / 100.0),
    ].join(';'));
    buf.write('\r\n');
  }
  return buf.toString();
}

/// **PERSONAL-2 — purer DATEV-Lohn-Bewegungsdaten-Builder.**
///
/// Baut aus den **freigegebenen/bezahlten** [records] (die `countsAsIst`-Kette
/// bleibt gewahrt — KEIN eigener WorkEntry-Aggregat-Code) eine Bewegungsdaten-
/// Datei (CRLF + Semikolon). Je Record: ein synthetisierter **Grundlohn-Satz**
/// (aus [PayrollRecord.istMinutes] + `grossCents` + `config.festeLohnartGrundlohn`,
/// PERSONAL-1) + je [PayrollLine] `Personalnummer;Lohnart;Menge;Betrag`.
///
/// Zeilen ohne Personalnummer/Lohnart werden NICHT geschrieben, sondern als
/// [DatevLohnProblem] gesammelt (nie werfen).
DatevLohnExportErgebnis buildBewegungsdaten({
  required DatevLohnConfig config,
  required List<PayrollRecord> records,
  required Map<String, EmployeeProfile> profilesByUserId,
  required List<PayLineType> payLineTypes,
  required int jahr,
  required int monat,
}) {
  final lohnartByTypeId = <String, String>{
    for (final t in payLineTypes)
      if (t.id != null && (t.datevLohnartNr?.trim().isNotEmpty ?? false))
        t.id!: t.datevLohnartNr!.trim(),
  };

  final probleme = <DatevLohnProblem>[];
  final subjectUserIds = <String>{};
  final rows = <Map<String, dynamic>>[];
  var summeCents = 0;

  // Nur finalisierte Records (freigegeben/bezahlt) — strenge Ist-Kette.
  final relevante = records
      .where((r) =>
          r.periodYear == jahr &&
          r.periodMonth == monat &&
          (r.status == PayrollStatus.freigegeben ||
              r.status == PayrollStatus.bezahlt))
      .toList(growable: false);

  for (final r in relevante) {
    final nummer = profilesByUserId[r.userId]?.personnelNumber?.trim() ?? '';
    if (!isValidDatevPersonalnummer(nummer)) {
      probleme.add(DatevLohnProblem(
        userId: r.userId,
        message: nummer.isEmpty
            ? 'Keine Personalnummer — Lohnzeilen nicht exportiert.'
            : 'Ungültige Personalnummer „$nummer" — nicht exportiert.',
        personalnummer: nummer.isEmpty ? null : nummer,
      ));
      continue;
    }
    subjectUserIds.add(r.userId);

    // Grundlohn-Satz (synthetisiert).
    if (config.festeLohnartGrundlohn.trim().isEmpty) {
      probleme.add(DatevLohnProblem(
        userId: r.userId,
        message: 'Keine Grundlohn-Lohnart konfiguriert — Grundlohn fehlt.',
        personalnummer: nummer,
      ));
    } else if (r.grossCents != 0) {
      if (r.istMinutes == null) {
        probleme.add(DatevLohnProblem(
          userId: r.userId,
          message: 'Grundlohn ohne Stundenmenge (Altdatensatz).',
          personalnummer: nummer,
        ));
      }
      rows.add({
        'personalnummer': nummer,
        'lohnartNr': config.festeLohnartGrundlohn.trim(),
        'mengeStunden': r.istMinutes == null ? null : r.istMinutes! / 60.0,
        'betragCents': r.grossCents,
      });
      summeCents += r.grossCents;
    }

    // Zusatz-/Zuschlagszeilen.
    for (final line in r.lines) {
      final lohnart = (line.datevLohnartNr?.trim().isNotEmpty ?? false)
          ? line.datevLohnartNr!.trim()
          : (line.lineTypeId != null ? lohnartByTypeId[line.lineTypeId] : null);
      if (lohnart == null || lohnart.isEmpty) {
        probleme.add(DatevLohnProblem(
          userId: r.userId,
          message: 'Lohnzeile „${line.name}" ohne Lohnartnummer — nicht '
              'exportiert.',
          personalnummer: nummer,
        ));
        continue;
      }
      rows.add({
        'personalnummer': nummer,
        'lohnartNr': lohnart,
        'mengeStunden': line.mengeStunden,
        'betragCents': line.amountCents,
      });
      summeCents += line.amountCents;
    }
  }

  return DatevLohnExportErgebnis(
    content: serializeLohnBewegungsdaten(
        config: config, rows: rows, jahr: jahr, monat: monat),
    probleme: probleme,
    zeilenAnzahl: rows.length,
    summeCents: summeCents,
    subjectUserIds: subjectUserIds.toList(),
    rows: rows,
  );
}
