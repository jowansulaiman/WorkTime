import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Art eines Export-Laufs (Q2): Finanz-Buchungsstapel oder Lohn-Bewegungsdaten.
/// `.value` = snake_case-String; `fromValue` hat einen Default-Branch (wirft
/// nie) — ein unbekannter String fällt still auf [finanz].
enum DatevExportArt { finanz, lohn }

extension DatevExportArtX on DatevExportArt {
  String get value => switch (this) {
        DatevExportArt.finanz => 'finanz',
        DatevExportArt.lohn => 'lohn',
      };

  String get label => switch (this) {
        DatevExportArt.finanz => 'Finanz-Buchungsstapel',
        DatevExportArt.lohn => 'Lohn-Bewegungsdaten',
      };

  static DatevExportArt fromValue(String? value) => switch (value) {
        'lohn' => DatevExportArt.lohn,
        _ => DatevExportArt.finanz,
      };
}

/// **Q2 — EIN gemeinsamer DATEV-Export-Lauf** (Finanz- UND Lohn-Historie) unter
/// `organizations/{orgId}/datevExportRuns/{runId}`.
///
/// **Cloud-only + immutabel** wie `CashClosing`: nur [fromFirestore]/
/// [toFirestoreMap], KEIN `toMap`, KEIN `copyWith` (dokumentierte Ausnahme von
/// der Dual-Serialisierungs-Regel). Die ROHDATEI wird NICHT persistiert
/// (1-MiB-Risiko bei Jahres-Journalen) — nur Metadaten + kanonische Snapshots.
///
/// **Reproduzierbarkeit:** **Lohn** trägt einen kanonischen [rowsSnapshot]
/// (byte-identischer Re-Download, nie aus Live-Daten). **Finanz** trägt bis zur
/// Grenze einen [entriesSnapshot] (dann byte-identisch) + [configSnapshot] +
/// [generatedAtMillis] für „Neu aufbauen & vergleichen". [snapshotTruncated]
/// zeigt an, ob die Snapshot-Grenze griff.
///
/// Die Rules-Allowlist wird EXAKT aus [toFirestoreMap] gebaut — neue Felder hier
/// UND im Rules-`hasOnly` ergänzen.
class DatevExportRun {
  const DatevExportRun({
    this.id,
    required this.orgId,
    this.schemaVersion = 1,
    required this.exportArt,
    required this.kind,
    required this.periodYear,
    this.periodMonth,
    required this.createdByUid,
    this.createdAt,
    this.entryCount = 0,
    this.sollCents,
    this.habenCents,
    this.summeCents,
    required this.fileName,
    required this.fileSha256,
    this.generatedAtMillis,
    this.configSnapshot,
    this.rowsSnapshot,
    this.entriesSnapshot,
    this.snapshotTruncated = false,
    this.snapshotRowCount = 0,
    this.subjectUserIds = const [],
    this.acceptedWarningCodes = const [],
    this.problemeAnzahl = 0,
    this.monatFestgeschrieben = false,
    this.overrideBestaetigt = false,
    this.note,
  });

  final String? id;

  /// Pflicht — die create-Rule prüft `orgId == {orgId}` (Pin gegen Fremd-Org).
  final String orgId;

  /// Schema-Version (int, ab 1; Leitplanke) — hält Format-/Lohnarten-Änderungen
  /// migrierbar.
  final int schemaVersion;

  final DatevExportArt exportArt;

  /// Konkretes Format, z. B. `extf_buchungsstapel`, `lodas_bewegungsdaten`,
  /// `lohn_und_gehalt_bewegungsdaten`.
  final String kind;

  final int periodYear;
  final int? periodMonth;

  final String createdByUid;
  final DateTime? createdAt;

  final int entryCount;

  /// Finanz: Summe Soll/Haben in Cent (Transparenz statt Beleg-Balance).
  final int? sollCents;
  final int? habenCents;

  /// Lohn: Gesamtsumme in Cent.
  final int? summeCents;

  final String fileName;

  /// SHA-256 der erzeugten Datei (Hex, 64 Zeichen) — Rules erzwingen das Format.
  final String fileSha256;

  /// Zeitstempel (ms since epoch), zu dem die Datei erzeugt wurde — für den
  /// Finanz-Rebuild („Neu aufbauen & vergleichen") reproduzierbar.
  final int? generatedAtMillis;

  /// Finanz: Snapshot der Export-Config zur Reproduktion (camelCase-Map).
  final Map<String, dynamic>? configSnapshot;

  /// Lohn: kanonischer Zeilen-Snapshot (`{personalnummer, lohnartNr,
  /// mengeStunden?, betragCents?}`) — byte-identischer Re-Download.
  final List<Map<String, dynamic>>? rowsSnapshot;

  /// Finanz: kompakter kanonischer Exportzeilen-Snapshot (bis zur Grenze).
  final List<Map<String, dynamic>>? entriesSnapshot;

  /// `true`, wenn die Snapshot-Grenze griff (dann nur Metadaten + Rebuild).
  final bool snapshotTruncated;

  /// Transparenz: wie viele Zeilen der Snapshot tatsächlich enthält.
  final int snapshotRowCount;

  /// DSGVO-Auffindbarkeit (Art. 15/17): betroffene Mitarbeiter (Lohn).
  final List<String> subjectUserIds;

  /// Übernommene, bewusst akzeptierte Prüflauf-Warnungen.
  final List<String> acceptedWarningCodes;

  /// Anzahl der Vorprüfungs-Probleme zum Erstellungszeitpunkt.
  final int problemeAnzahl;

  /// GoBD: war der Zeitraum festgeschrieben / wurde trotz Warnung exportiert.
  final bool monatFestgeschrieben;
  final bool overrideBestaetigt;

  final String? note;

  /// Byte-identischer Re-Download möglich? Lohn mit [rowsSnapshot] bzw. Finanz
  /// mit [entriesSnapshot] und nicht gekappt.
  bool get canRebuildByteIdentical {
    if (snapshotTruncated) return false;
    return exportArt == DatevExportArt.lohn
        ? (rowsSnapshot != null && rowsSnapshot!.isNotEmpty)
        : (entriesSnapshot != null && entriesSnapshot!.isNotEmpty);
  }

  factory DatevExportRun.fromFirestore(String id, Map<String, dynamic> map) {
    return DatevExportRun(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      schemaVersion: parse.toInt(map['schemaVersion']) ?? 1,
      exportArt: DatevExportArtX.fromValue(map['exportArt']?.toString()),
      kind: (map['kind'] ?? '').toString(),
      periodYear: parse.toInt(map['periodYear']) ?? 0,
      periodMonth: parse.toInt(map['periodMonth']),
      createdByUid: (map['createdByUid'] ?? '').toString(),
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      entryCount: parse.toInt(map['entryCount']) ?? 0,
      sollCents: parse.toInt(map['sollCents']),
      habenCents: parse.toInt(map['habenCents']),
      summeCents: parse.toInt(map['summeCents']),
      fileName: (map['fileName'] ?? '').toString(),
      fileSha256: (map['fileSha256'] ?? '').toString(),
      generatedAtMillis: parse.toInt(map['generatedAtMillis']),
      configSnapshot: _readMap(map['configSnapshot']),
      rowsSnapshot: _readMapList(map['rowsSnapshot']),
      entriesSnapshot: _readMapList(map['entriesSnapshot']),
      snapshotTruncated: parse.toBool(map['snapshotTruncated']) ?? false,
      snapshotRowCount: parse.toInt(map['snapshotRowCount']) ?? 0,
      subjectUserIds: _readStringList(map['subjectUserIds']),
      acceptedWarningCodes: _readStringList(map['acceptedWarningCodes']),
      problemeAnzahl: parse.toInt(map['problemeAnzahl']) ?? 0,
      monatFestgeschrieben: parse.toBool(map['monatFestgeschrieben']) ?? false,
      overrideBestaetigt: parse.toBool(map['overrideBestaetigt']) ?? false,
      note: map['note']?.toString(),
    );
  }

  /// camelCase-Map für den Firestore-Write. `createdAt` wird als
  /// `serverTimestamp` gesetzt (die create-Rule erzwingt `createdAt ==
  /// request.time` → kein Backdating). Optionale Felder werden immer geschrieben
  /// (auch als `null`), damit die Rules-Allowlist deterministisch greift.
  Map<String, dynamic> toFirestoreMap() => {
        'orgId': orgId,
        'schemaVersion': schemaVersion,
        'exportArt': exportArt.value,
        'kind': kind,
        'periodYear': periodYear,
        'periodMonth': periodMonth,
        'createdByUid': createdByUid,
        'createdAt': FieldValue.serverTimestamp(),
        'entryCount': entryCount,
        'sollCents': sollCents,
        'habenCents': habenCents,
        'summeCents': summeCents,
        'fileName': fileName,
        'fileSha256': fileSha256,
        'generatedAtMillis': generatedAtMillis,
        'configSnapshot': configSnapshot,
        'rowsSnapshot': rowsSnapshot,
        'entriesSnapshot': entriesSnapshot,
        'snapshotTruncated': snapshotTruncated,
        'snapshotRowCount': snapshotRowCount,
        'subjectUserIds': subjectUserIds,
        'acceptedWarningCodes': acceptedWarningCodes,
        'problemeAnzahl': problemeAnzahl,
        'monatFestgeschrieben': monatFestgeschrieben,
        'overrideBestaetigt': overrideBestaetigt,
        'note': note,
      };

  static Map<String, dynamic>? _readMap(dynamic raw) =>
      raw is Map ? Map<String, dynamic>.from(raw) : null;

  static List<Map<String, dynamic>>? _readMapList(dynamic raw) {
    if (raw is! List) return null;
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  static List<String> _readStringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList(growable: false);
  }
}
