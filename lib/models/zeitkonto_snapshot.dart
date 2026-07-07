// lib/models/zeitkonto_snapshot.dart

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_num_parser.dart' as parse;

/// Monats-Stundenkonto eines Mitarbeiters (AllTec `HourAccount`, M4).
///
/// Wird beim **Monatsabschluss** (M5) fortgeschrieben (Upsert) — der laufende
/// Saldo wird sonst on-demand aus `zeitkonto_snapshot_builder` berechnet
/// (Spark-frugal, IDA-/E7-Muster). Urlaub bleibt kalenderjahr-bezogen (Quelle
/// `urlaub_calculator`); hier nur als Anzeige in den Monats-Snapshot gespiegelt.
class ZeitkontoSnapshot {
  final String? id;
  final String orgId;
  final String userId;
  final int jahr;
  final int monat;

  /// Monatssoll (Minuten).
  final int sollMinutes;

  /// Ist inkl. angerechneter bezahlter Abwesenheiten (Minuten).
  final int istMinutes;

  /// Über-/Minusstunden des Monats (= Ist − Soll).
  final int ueberstundenMinutes;

  /// Ausgezahlte Überstunden (Minuten).
  final int ausgezahltMinutes;

  /// Saldo-Übertrag aus dem Vormonat (Minuten).
  final int uebertragMinutes;

  /// Kumulierter Saldo zum Monatsende (= Übertrag + Überstunden − Ausgezahlt).
  final int saldoMinutes;

  /// Planzeit des Monats (Minuten): Summe der dem Mitarbeiter zugewiesenen
  /// Schicht-Netto-Zeiten (`Shift.workedHours`, ohne cancelled/unassigned) —
  /// Z9/E6. Rein anzeigende Schichtplan-Sicht **neben** Soll (Vertrag) und Ist
  /// (genehmigt); fließt NICHT in Saldo/Überstunden. Alt-Snapshots ohne Feld = 0.
  final int geplantMinutes;

  final double urlaubstageGesamt;
  final double urlaubstageGenommen;
  final double urlaubstageRest;
  final int kranktage;

  /// Monat abgeschlossen (gesperrt). = AllTec `isLocked`.
  final bool abgeschlossen;
  final String? abgeschlossenVon;
  final DateTime? abgeschlossenAm;

  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ZeitkontoSnapshot({
    this.id,
    this.orgId = '',
    this.userId = '',
    required this.jahr,
    required this.monat,
    this.sollMinutes = 0,
    this.istMinutes = 0,
    this.ueberstundenMinutes = 0,
    this.ausgezahltMinutes = 0,
    this.uebertragMinutes = 0,
    this.saldoMinutes = 0,
    this.geplantMinutes = 0,
    this.urlaubstageGesamt = 0,
    this.urlaubstageGenommen = 0,
    this.urlaubstageRest = 0,
    this.kranktage = 0,
    this.abgeschlossen = false,
    this.abgeschlossenVon,
    this.abgeschlossenAm,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  /// Deterministische Doc-ID `{userId}-{jahr}-{mm}` (Upsert beim Abschluss).
  static String buildId(String userId, int jahr, int monat) =>
      '$userId-$jahr-${monat.toString().padLeft(2, '0')}';

  double get sollHours => sollMinutes / 60.0;
  double get istHours => istMinutes / 60.0;
  double get ueberstundenHours => ueberstundenMinutes / 60.0;
  double get saldoHours => saldoMinutes / 60.0;
  double get ausgezahltHours => ausgezahltMinutes / 60.0;
  double get uebertragHours => uebertragMinutes / 60.0;
  double get geplantHours => geplantMinutes / 60.0;

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String && raw.trim().isNotEmpty) return DateTime.parse(raw);
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'jahr': jahr,
      'monat': monat,
      'soll_minutes': sollMinutes,
      'ist_minutes': istMinutes,
      'ueberstunden_minutes': ueberstundenMinutes,
      'ausgezahlt_minutes': ausgezahltMinutes,
      'uebertrag_minutes': uebertragMinutes,
      'saldo_minutes': saldoMinutes,
      'geplant_minutes': geplantMinutes,
      'urlaubstage_gesamt': urlaubstageGesamt,
      'urlaubstage_genommen': urlaubstageGenommen,
      'urlaubstage_rest': urlaubstageRest,
      'kranktage': kranktage,
      'abgeschlossen': abgeschlossen,
      'abgeschlossen_von': abgeschlossenVon,
      'abgeschlossen_am': abgeschlossenAm?.toIso8601String(),
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory ZeitkontoSnapshot.fromMap(Map<String, dynamic> map) {
    return ZeitkontoSnapshot(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      jahr: parse.toInt(map['jahr']) ?? 0,
      monat: parse.toInt(map['monat']) ?? 0,
      sollMinutes: parse.toInt(map['soll_minutes']) ?? 0,
      istMinutes: parse.toInt(map['ist_minutes']) ?? 0,
      ueberstundenMinutes: parse.toInt(map['ueberstunden_minutes']) ?? 0,
      ausgezahltMinutes: parse.toInt(map['ausgezahlt_minutes']) ?? 0,
      uebertragMinutes: parse.toInt(map['uebertrag_minutes']) ?? 0,
      saldoMinutes: parse.toInt(map['saldo_minutes']) ?? 0,
      geplantMinutes: parse.toInt(map['geplant_minutes']) ?? 0,
      urlaubstageGesamt: parse.toDouble(map['urlaubstage_gesamt']) ?? 0,
      urlaubstageGenommen: parse.toDouble(map['urlaubstage_genommen']) ?? 0,
      urlaubstageRest: parse.toDouble(map['urlaubstage_rest']) ?? 0,
      kranktage: parse.toInt(map['kranktage']) ?? 0,
      abgeschlossen: parse.toBool(map['abgeschlossen']) ?? false,
      abgeschlossenVon: map['abgeschlossen_von'] as String?,
      abgeschlossenAm: _parseDate(map['abgeschlossen_am']),
      createdByUid: map['created_by_uid'] as String?,
      createdAt: _parseDate(map['created_at']),
      updatedAt: _parseDate(map['updated_at']),
    );
  }

  factory ZeitkontoSnapshot.fromFirestore(String id, Map<String, dynamic> map) {
    return ZeitkontoSnapshot(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      jahr: parse.toInt(map['jahr']) ?? 0,
      monat: parse.toInt(map['monat']) ?? 0,
      sollMinutes: parse.toInt(map['sollMinutes']) ?? 0,
      istMinutes: parse.toInt(map['istMinutes']) ?? 0,
      ueberstundenMinutes: parse.toInt(map['ueberstundenMinutes']) ?? 0,
      ausgezahltMinutes: parse.toInt(map['ausgezahltMinutes']) ?? 0,
      uebertragMinutes: parse.toInt(map['uebertragMinutes']) ?? 0,
      saldoMinutes: parse.toInt(map['saldoMinutes']) ?? 0,
      geplantMinutes: parse.toInt(map['geplantMinutes']) ?? 0,
      urlaubstageGesamt: parse.toDouble(map['urlaubstageGesamt']) ?? 0,
      urlaubstageGenommen: parse.toDouble(map['urlaubstageGenommen']) ?? 0,
      urlaubstageRest: parse.toDouble(map['urlaubstageRest']) ?? 0,
      kranktage: parse.toInt(map['kranktage']) ?? 0,
      abgeschlossen: parse.toBool(map['abgeschlossen']) ?? false,
      abgeschlossenVon: map['abgeschlossenVon'] as String?,
      abgeschlossenAm: _parseDate(map['abgeschlossenAm']),
      createdByUid: map['createdByUid'] as String?,
      createdAt: _parseDate(map['createdAt']),
      updatedAt: _parseDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'jahr': jahr,
      'monat': monat,
      'sollMinutes': sollMinutes,
      'istMinutes': istMinutes,
      'ueberstundenMinutes': ueberstundenMinutes,
      'ausgezahltMinutes': ausgezahltMinutes,
      'uebertragMinutes': uebertragMinutes,
      'saldoMinutes': saldoMinutes,
      'geplantMinutes': geplantMinutes,
      'urlaubstageGesamt': urlaubstageGesamt,
      'urlaubstageGenommen': urlaubstageGenommen,
      'urlaubstageRest': urlaubstageRest,
      'kranktage': kranktage,
      'abgeschlossen': abgeschlossen,
      'abgeschlossenVon': abgeschlossenVon,
      'abgeschlossenAm':
          abgeschlossenAm == null ? null : Timestamp.fromDate(abgeschlossenAm!),
      'createdByUid': createdByUid,
      if (createdAt == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  ZeitkontoSnapshot copyWith({
    String? id,
    String? orgId,
    String? userId,
    int? jahr,
    int? monat,
    int? sollMinutes,
    int? istMinutes,
    int? ueberstundenMinutes,
    int? ausgezahltMinutes,
    int? uebertragMinutes,
    int? saldoMinutes,
    int? geplantMinutes,
    double? urlaubstageGesamt,
    double? urlaubstageGenommen,
    double? urlaubstageRest,
    int? kranktage,
    bool? abgeschlossen,
    String? abgeschlossenVon,
    DateTime? abgeschlossenAm,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearAbgeschlossenVon = false,
    bool clearAbgeschlossenAm = false,
  }) {
    return ZeitkontoSnapshot(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      jahr: jahr ?? this.jahr,
      monat: monat ?? this.monat,
      sollMinutes: sollMinutes ?? this.sollMinutes,
      istMinutes: istMinutes ?? this.istMinutes,
      ueberstundenMinutes: ueberstundenMinutes ?? this.ueberstundenMinutes,
      ausgezahltMinutes: ausgezahltMinutes ?? this.ausgezahltMinutes,
      uebertragMinutes: uebertragMinutes ?? this.uebertragMinutes,
      saldoMinutes: saldoMinutes ?? this.saldoMinutes,
      geplantMinutes: geplantMinutes ?? this.geplantMinutes,
      urlaubstageGesamt: urlaubstageGesamt ?? this.urlaubstageGesamt,
      urlaubstageGenommen: urlaubstageGenommen ?? this.urlaubstageGenommen,
      urlaubstageRest: urlaubstageRest ?? this.urlaubstageRest,
      kranktage: kranktage ?? this.kranktage,
      abgeschlossen: abgeschlossen ?? this.abgeschlossen,
      abgeschlossenVon: clearAbgeschlossenVon
          ? null
          : (abgeschlossenVon ?? this.abgeschlossenVon),
      abgeschlossenAm: clearAbgeschlossenAm
          ? null
          : (abgeschlossenAm ?? this.abgeschlossenAm),
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
