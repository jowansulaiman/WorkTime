import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';

/// Status einer Aus-/Weiterbildung (AllTec-Parität; steuert das Status-Badge).
enum AusbildungStatus { laufend, abgeschlossen, abgebrochen }

extension AusbildungStatusX on AusbildungStatus {
  String get value => switch (this) {
        AusbildungStatus.laufend => 'laufend',
        AusbildungStatus.abgeschlossen => 'abgeschlossen',
        AusbildungStatus.abgebrochen => 'abgebrochen',
      };

  String get label => switch (this) {
        AusbildungStatus.laufend => 'Laufend',
        AusbildungStatus.abgeschlossen => 'Abgeschlossen',
        AusbildungStatus.abgebrochen => 'Abgebrochen',
      };

  /// Default-Branch wirft nie (Enum-Kopplungsregel).
  static AusbildungStatus fromValue(String? value) => switch (value) {
        'abgeschlossen' => AusbildungStatus.abgeschlossen,
        'abgebrochen' => AusbildungStatus.abgebrochen,
        _ => AusbildungStatus.laufend,
      };
}

/// Ausbildung eines Mitarbeiters (HR-Sub-Entität, M-H).
class EmployeeAusbildung {
  const EmployeeAusbildung({
    this.id,
    required this.orgId,
    required this.userId,
    this.bezeichnung = '',
    this.beginn,
    this.ende,
    this.ausbilderUserId,
    this.ausbildungsart,
    this.ausbildungsstaette,
    this.fachrichtung,
    this.abschluss,
    this.status = AusbildungStatus.laufend,
    this.noteZwischen,
    this.noteAbschluss,
    this.bemerkung,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String userId;
  final String bezeichnung;
  final DateTime? beginn;
  final DateTime? ende;

  /// Verantwortliche:r Ausbilder:in (FK auf einen anderen Mitarbeiter), optional.
  final String? ausbilderUserId;

  // AllTec-Feld-Parität.
  final String? ausbildungsart;
  final String? ausbildungsstaette;
  final String? fachrichtung;
  final String? abschluss;
  final AusbildungStatus status;

  final String? noteZwischen;
  final String? noteAbschluss;
  final String? bemerkung;

  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Tages-Datum auf lokale Mittagszeit normalisieren (Konvention: 12:00).
  static DateTime? _dateOnly(DateTime? d) =>
      d == null ? null : DateTime(d.year, d.month, d.day, 12);

  factory EmployeeAusbildung.fromFirestore(
      String id, Map<String, dynamic> map) {
    return EmployeeAusbildung(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      bezeichnung: (map['bezeichnung'] ?? '').toString(),
      beginn: FirestoreDateParser.readDate(map['beginn']),
      ende: FirestoreDateParser.readDate(map['ende']),
      ausbilderUserId: map['ausbilderUserId'] as String?,
      ausbildungsart: map['ausbildungsart'] as String?,
      ausbildungsstaette: map['ausbildungsstaette'] as String?,
      fachrichtung: map['fachrichtung'] as String?,
      abschluss: map['abschluss'] as String?,
      status: AusbildungStatusX.fromValue(map['status']?.toString()),
      noteZwischen: map['noteZwischen'] as String?,
      noteAbschluss: map['noteAbschluss'] as String?,
      bemerkung: map['bemerkung'] as String?,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory EmployeeAusbildung.fromMap(Map<String, dynamic> map) {
    return EmployeeAusbildung(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      bezeichnung: (map['bezeichnung'] ?? '').toString(),
      beginn: FirestoreDateParser.readLocalDate(map['beginn']),
      ende: FirestoreDateParser.readLocalDate(map['ende']),
      ausbilderUserId: map['ausbilder_user_id'] as String?,
      ausbildungsart: map['ausbildungsart'] as String?,
      ausbildungsstaette: map['ausbildungsstaette'] as String?,
      fachrichtung: map['fachrichtung'] as String?,
      abschluss: map['abschluss'] as String?,
      status: AusbildungStatusX.fromValue(map['status']?.toString()),
      noteZwischen: map['note_zwischen'] as String?,
      noteAbschluss: map['note_abschluss'] as String?,
      bemerkung: map['bemerkung'] as String?,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'bezeichnung': bezeichnung,
      'beginn': _dateOnly(beginn) == null
          ? null
          : Timestamp.fromDate(_dateOnly(beginn)!),
      'ende':
          _dateOnly(ende) == null ? null : Timestamp.fromDate(_dateOnly(ende)!),
      'ausbilderUserId': ausbilderUserId,
      'ausbildungsart': ausbildungsart,
      'ausbildungsstaette': ausbildungsstaette,
      'fachrichtung': fachrichtung,
      'abschluss': abschluss,
      'status': status.value,
      'noteZwischen': noteZwischen,
      'noteAbschluss': noteAbschluss,
      'bemerkung': bemerkung,
      'createdByUid': createdByUid,
      // Doc-ID wird vor dem Schreiben gesetzt → an createdAt festmachen.
      if (createdAt == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'bezeichnung': bezeichnung,
      'beginn': _dateOnly(beginn)?.toIso8601String(),
      'ende': _dateOnly(ende)?.toIso8601String(),
      'ausbilder_user_id': ausbilderUserId,
      'ausbildungsart': ausbildungsart,
      'ausbildungsstaette': ausbildungsstaette,
      'fachrichtung': fachrichtung,
      'abschluss': abschluss,
      'status': status.value,
      'note_zwischen': noteZwischen,
      'note_abschluss': noteAbschluss,
      'bemerkung': bemerkung,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  EmployeeAusbildung copyWith({
    String? id,
    String? orgId,
    String? userId,
    String? bezeichnung,
    DateTime? beginn,
    bool clearBeginn = false,
    DateTime? ende,
    bool clearEnde = false,
    String? ausbilderUserId,
    bool clearAusbilderUserId = false,
    String? ausbildungsart,
    bool clearAusbildungsart = false,
    String? ausbildungsstaette,
    bool clearAusbildungsstaette = false,
    String? fachrichtung,
    bool clearFachrichtung = false,
    String? abschluss,
    bool clearAbschluss = false,
    AusbildungStatus? status,
    String? noteZwischen,
    bool clearNoteZwischen = false,
    String? noteAbschluss,
    bool clearNoteAbschluss = false,
    String? bemerkung,
    bool clearBemerkung = false,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmployeeAusbildung(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      bezeichnung: bezeichnung ?? this.bezeichnung,
      beginn: clearBeginn ? null : (beginn ?? this.beginn),
      ende: clearEnde ? null : (ende ?? this.ende),
      ausbilderUserId: clearAusbilderUserId
          ? null
          : (ausbilderUserId ?? this.ausbilderUserId),
      ausbildungsart:
          clearAusbildungsart ? null : (ausbildungsart ?? this.ausbildungsart),
      ausbildungsstaette: clearAusbildungsstaette
          ? null
          : (ausbildungsstaette ?? this.ausbildungsstaette),
      fachrichtung:
          clearFachrichtung ? null : (fachrichtung ?? this.fachrichtung),
      abschluss: clearAbschluss ? null : (abschluss ?? this.abschluss),
      status: status ?? this.status,
      noteZwischen:
          clearNoteZwischen ? null : (noteZwischen ?? this.noteZwischen),
      noteAbschluss:
          clearNoteAbschluss ? null : (noteAbschluss ?? this.noteAbschluss),
      bemerkung: clearBemerkung ? null : (bemerkung ?? this.bemerkung),
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
