import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';

/// Art des Qualifikationserwerbs.
enum QualiErwerb { vorab, intern, extern }

extension QualiErwerbX on QualiErwerb {
  String get value => switch (this) {
        QualiErwerb.vorab => 'vorab',
        QualiErwerb.intern => 'intern',
        QualiErwerb.extern => 'extern',
      };

  String get label => switch (this) {
        QualiErwerb.vorab => 'bereits vorhanden',
        QualiErwerb.intern => 'intern erworben',
        QualiErwerb.extern => 'extern erworben',
      };

  /// Default-Branch wirft nie (Enum-Kopplungsregel).
  static QualiErwerb fromValue(String? value) => switch (value) {
        'intern' => QualiErwerb.intern,
        'extern' => QualiErwerb.extern,
        _ => QualiErwerb.vorab,
      };
}

/// Gültigkeitsstatus einer Qualifikation relativ zu einem Stichtag (PA-1.3):
/// gültig, läuft bald ab (innerhalb der Warnfrist) oder abgelaufen.
enum QualiGueltigkeit { gueltig, laeuftAb, abgelaufen }

/// Einem Mitarbeiter zugeordnete Qualifikation (HR-Sub-Entität, M-H) –
/// mit Erwerb/Gültigkeit/Doku. Bezieht sich optional auf eine
/// [QualificationDefinition] (`qualificationId`, Schicht-Anforderung), trägt
/// aber den Namen als Snapshot für die Anzeige.
class EmployeeQualification {
  const EmployeeQualification({
    this.id,
    required this.orgId,
    required this.userId,
    this.qualificationId,
    this.qualificationName = '',
    this.erwerb = QualiErwerb.vorab,
    this.erworbenAm,
    this.gueltigBis,
    this.bemerkung,
    this.documentId,
    this.qualifikationsart,
    this.beschreibung,
    this.zertifikatNr,
    this.ausstellendeStelle,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String userId;

  /// FK auf `qualifications` (optional – freie Qualifikationen ohne Stammsatz).
  final String? qualificationId;
  final String qualificationName;
  final QualiErwerb erwerb;
  final DateTime? erworbenAm;
  final DateTime? gueltigBis;
  final String? bemerkung;

  /// **PERSONAL-6:** Weiche FK auf ein [EmployeeDocument] (`employeeDocuments`),
  /// das den Qualifikationsnachweis enthält (Zertifikat/Bescheinigung o. ä.).
  /// Bewusst OHNE harte Integrität: wird das verknüpfte Dokument gelöscht,
  /// verwaist die Referenz (die UI zeigt dann „Nachweis nicht mehr vorhanden").
  final String? documentId;

  // AllTec-Feld-Parität (freitextliche Zusatzangaben zur Qualifikation).
  final String? qualifikationsart;
  final String? beschreibung;
  final String? zertifikatNr;
  final String? ausstellendeStelle;

  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Ob die Qualifikation am [date] (Default heute) gültig ist (kein
  /// `gueltigBis` = unbefristet gültig).
  bool istGueltig(DateTime date) {
    final bis = gueltigBis;
    if (bis == null) return true;
    final end = DateTime(bis.year, bis.month, bis.day, 23, 59, 59);
    return !date.isAfter(end);
  }

  /// Gültigkeitsstatus am [date] (PA-1.3, pure): `abgelaufen`, wenn `gueltigBis`
  /// vor dem Tag liegt; `laeuftAb`, wenn es innerhalb der nächsten [warnTage]
  /// Tage abläuft; sonst `gueltig` (auch unbefristet ohne `gueltigBis`).
  QualiGueltigkeit gueltigkeitStatus(DateTime date, {int warnTage = 30}) {
    final bis = gueltigBis;
    if (bis == null) return QualiGueltigkeit.gueltig;
    final end = DateTime(bis.year, bis.month, bis.day, 23, 59, 59);
    if (date.isAfter(end)) return QualiGueltigkeit.abgelaufen;
    final warnAb = end.subtract(Duration(days: warnTage));
    if (!date.isBefore(warnAb)) return QualiGueltigkeit.laeuftAb;
    return QualiGueltigkeit.gueltig;
  }

  // Tages-Datum auf lokale Mittagszeit normalisieren (Konvention: 12:00).
  static DateTime? _dateOnly(DateTime? d) =>
      d == null ? null : DateTime(d.year, d.month, d.day, 12);

  factory EmployeeQualification.fromFirestore(
      String id, Map<String, dynamic> map) {
    return EmployeeQualification(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      qualificationId: map['qualificationId'] as String?,
      qualificationName: (map['qualificationName'] ?? '').toString(),
      erwerb: QualiErwerbX.fromValue(map['erwerb']?.toString()),
      erworbenAm: FirestoreDateParser.readDate(map['erworbenAm']),
      gueltigBis: FirestoreDateParser.readDate(map['gueltigBis']),
      bemerkung: map['bemerkung'] as String?,
      documentId: map['documentId'] as String?,
      qualifikationsart: map['qualifikationsart'] as String?,
      beschreibung: map['beschreibung'] as String?,
      zertifikatNr: map['zertifikatNr'] as String?,
      ausstellendeStelle: map['ausstellendeStelle'] as String?,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory EmployeeQualification.fromMap(Map<String, dynamic> map) {
    return EmployeeQualification(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      qualificationId: map['qualification_id'] as String?,
      qualificationName: (map['qualification_name'] ?? '').toString(),
      erwerb: QualiErwerbX.fromValue(map['erwerb']?.toString()),
      erworbenAm: FirestoreDateParser.readLocalDate(map['erworben_am']),
      gueltigBis: FirestoreDateParser.readLocalDate(map['gueltig_bis']),
      bemerkung: map['bemerkung'] as String?,
      documentId: map['document_id'] as String?,
      qualifikationsart: map['qualifikationsart'] as String?,
      beschreibung: map['beschreibung'] as String?,
      zertifikatNr: map['zertifikat_nr'] as String?,
      ausstellendeStelle: map['ausstellende_stelle'] as String?,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'qualificationId': qualificationId,
      'qualificationName': qualificationName,
      'erwerb': erwerb.value,
      'erworbenAm': _dateOnly(erworbenAm) == null
          ? null
          : Timestamp.fromDate(_dateOnly(erworbenAm)!),
      'gueltigBis': _dateOnly(gueltigBis) == null
          ? null
          : Timestamp.fromDate(_dateOnly(gueltigBis)!),
      'bemerkung': bemerkung,
      'documentId': documentId,
      'qualifikationsart': qualifikationsart,
      'beschreibung': beschreibung,
      'zertifikatNr': zertifikatNr,
      'ausstellendeStelle': ausstellendeStelle,
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
      'qualification_id': qualificationId,
      'qualification_name': qualificationName,
      'erwerb': erwerb.value,
      'erworben_am': _dateOnly(erworbenAm)?.toIso8601String(),
      'gueltig_bis': _dateOnly(gueltigBis)?.toIso8601String(),
      'bemerkung': bemerkung,
      'document_id': documentId,
      'qualifikationsart': qualifikationsart,
      'beschreibung': beschreibung,
      'zertifikat_nr': zertifikatNr,
      'ausstellende_stelle': ausstellendeStelle,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  EmployeeQualification copyWith({
    String? id,
    String? orgId,
    String? userId,
    String? qualificationId,
    bool clearQualificationId = false,
    String? qualificationName,
    QualiErwerb? erwerb,
    DateTime? erworbenAm,
    bool clearErworbenAm = false,
    DateTime? gueltigBis,
    bool clearGueltigBis = false,
    String? bemerkung,
    bool clearBemerkung = false,
    String? documentId,
    bool clearDocumentId = false,
    String? qualifikationsart,
    bool clearQualifikationsart = false,
    String? beschreibung,
    bool clearBeschreibung = false,
    String? zertifikatNr,
    bool clearZertifikatNr = false,
    String? ausstellendeStelle,
    bool clearAusstellendeStelle = false,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmployeeQualification(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      qualificationId:
          clearQualificationId ? null : (qualificationId ?? this.qualificationId),
      qualificationName: qualificationName ?? this.qualificationName,
      erwerb: erwerb ?? this.erwerb,
      erworbenAm: clearErworbenAm ? null : (erworbenAm ?? this.erworbenAm),
      gueltigBis: clearGueltigBis ? null : (gueltigBis ?? this.gueltigBis),
      bemerkung: clearBemerkung ? null : (bemerkung ?? this.bemerkung),
      documentId: clearDocumentId ? null : (documentId ?? this.documentId),
      qualifikationsart: clearQualifikationsart
          ? null
          : (qualifikationsart ?? this.qualifikationsart),
      beschreibung:
          clearBeschreibung ? null : (beschreibung ?? this.beschreibung),
      zertifikatNr:
          clearZertifikatNr ? null : (zertifikatNr ?? this.zertifikatNr),
      ausstellendeStelle: clearAusstellendeStelle
          ? null
          : (ausstellendeStelle ?? this.ausstellendeStelle),
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
