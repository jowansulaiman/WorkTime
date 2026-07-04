import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Kind eines Mitarbeiters (HR-Sub-Entität, M-H).
///
/// **Einzelquelle Kinderzähler (§4.4):** Sobald für einen Mitarbeiter ≥ 1
/// [EmployeeChild] gepflegt ist, leitet sich der lohnsteuerliche Kinderzähler
/// aus `count(zaehltFuerFreibetrag)` ab (statt aus dem int-Feld
/// `EmployeeProfile.childrenCount`). Solange keine Kinder gepflegt sind, bleibt
/// `childrenCount` die Quelle (rückwärtskompatibel) – nie beide parallel.
class EmployeeChild {
  const EmployeeChild({
    this.id,
    required this.orgId,
    required this.userId,
    this.vorname = '',
    this.name = '',
    this.geschlecht,
    this.steuerIdKind,
    this.geburtstag,
    this.anmerkungen,
    this.zaehltFuerFreibetrag = true,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String userId;
  final String vorname;
  final String name;
  final String? geschlecht;

  /// Steuer-Identifikationsnummer des Kindes (11-stellig), optional.
  final String? steuerIdKind;
  final DateTime? geburtstag;

  /// Freitext-Anmerkung zum Kind (optional; AllTec-Feld-Parität).
  final String? anmerkungen;

  /// Ob das Kind für den lohnsteuerlichen Kinderfreibetrag zählt (Default true).
  final bool zaehltFuerFreibetrag;

  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get anzeigeName {
    final parts = [vorname.trim(), name.trim()].where((p) => p.isNotEmpty);
    final joined = parts.join(' ');
    return joined.isEmpty ? 'Kind' : joined;
  }

  // Tages-Datum auf lokale Mittagszeit normalisieren (Konvention WorkEntry/
  // SollzeitProfile: 12:00 vermeidet Zeitzonen-Drift).
  static DateTime? _dateOnly(DateTime? d) =>
      d == null ? null : DateTime(d.year, d.month, d.day, 12);

  factory EmployeeChild.fromFirestore(String id, Map<String, dynamic> map) {
    return EmployeeChild(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      vorname: (map['vorname'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      geschlecht: map['geschlecht'] as String?,
      steuerIdKind: map['steuerIdKind'] as String?,
      geburtstag: FirestoreDateParser.readDate(map['geburtstag']),
      anmerkungen: map['anmerkungen'] as String?,
      zaehltFuerFreibetrag:
          parse.toBool(map['zaehltFuerFreibetrag']) ?? true,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory EmployeeChild.fromMap(Map<String, dynamic> map) {
    return EmployeeChild(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      vorname: (map['vorname'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      geschlecht: map['geschlecht'] as String?,
      steuerIdKind: map['steuer_id_kind'] as String?,
      geburtstag: FirestoreDateParser.readLocalDate(map['geburtstag']),
      anmerkungen: map['anmerkungen'] as String?,
      zaehltFuerFreibetrag:
          parse.toBool(map['zaehlt_fuer_freibetrag']) ?? true,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'vorname': vorname,
      'name': name,
      'geschlecht': geschlecht,
      'steuerIdKind': steuerIdKind,
      'geburtstag': _dateOnly(geburtstag) == null
          ? null
          : Timestamp.fromDate(_dateOnly(geburtstag)!),
      'anmerkungen': anmerkungen,
      'zaehltFuerFreibetrag': zaehltFuerFreibetrag,
      'createdByUid': createdByUid,
      // Doc-ID wird vor dem Schreiben gesetzt → an createdAt festmachen, nicht
      // an id==null (sonst nie geschrieben). Mit merge:true nur beim Anlegen.
      if (createdAt == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'vorname': vorname,
      'name': name,
      'geschlecht': geschlecht,
      'steuer_id_kind': steuerIdKind,
      'geburtstag': _dateOnly(geburtstag)?.toIso8601String(),
      'anmerkungen': anmerkungen,
      'zaehlt_fuer_freibetrag': zaehltFuerFreibetrag,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  EmployeeChild copyWith({
    String? id,
    String? orgId,
    String? userId,
    String? vorname,
    String? name,
    String? geschlecht,
    bool clearGeschlecht = false,
    String? steuerIdKind,
    bool clearSteuerIdKind = false,
    DateTime? geburtstag,
    bool clearGeburtstag = false,
    String? anmerkungen,
    bool clearAnmerkungen = false,
    bool? zaehltFuerFreibetrag,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmployeeChild(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      vorname: vorname ?? this.vorname,
      name: name ?? this.name,
      geschlecht: clearGeschlecht ? null : (geschlecht ?? this.geschlecht),
      steuerIdKind:
          clearSteuerIdKind ? null : (steuerIdKind ?? this.steuerIdKind),
      geburtstag: clearGeburtstag ? null : (geburtstag ?? this.geburtstag),
      anmerkungen:
          clearAnmerkungen ? null : (anmerkungen ?? this.anmerkungen),
      zaehltFuerFreibetrag:
          zaehltFuerFreibetrag ?? this.zaehltFuerFreibetrag,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
