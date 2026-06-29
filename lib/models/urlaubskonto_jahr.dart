import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Jahres-Vortragsquelle des Urlaubskontos (M-U). Trennt sauber gesetzlich vs.
/// vertraglich und trägt die **Hinweisobliegenheit** für den 31.3.-Verfall
/// (EuGH C-684/16 / BAG – Verfall NUR wenn dokumentiert, Plan §5.2).
///
/// Org-skopiert, admin-only. **Doc-ID = `{userId}-{jahr}`** (ein Datensatz je
/// Mitarbeiter und Jahr).
class UrlaubskontoJahr {
  const UrlaubskontoJahr({
    this.id,
    required this.orgId,
    required this.userId,
    required this.jahr,
    this.vortragVorjahrTage = 0,
    this.vortragVerfaelltAm,
    this.hinweisErteiltAm,
    this.gewaehrterMehrurlaubTage = 0,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String userId;
  final int jahr;

  /// Übertragener Resturlaub aus dem Vorjahr.
  final double vortragVorjahrTage;

  /// Verfallsdatum des Vortrags (Default 31.3. des Jahres). null → kein Verfall.
  final DateTime? vortragVerfaelltAm;

  /// Wann der AG seiner Hinweisobliegenheit nachgekommen ist. **Ohne** dieses
  /// Datum verfällt der Vortrag NICHT (EuGH/BAG).
  final DateTime? hinweisErteiltAm;

  /// Zusätzlich gewährter (vertraglicher) Mehrurlaub für dieses Jahr.
  final double gewaehrterMehrurlaubTage;

  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get documentId => '$userId-$jahr';

  /// Standard-Verfallsdatum 31.3. des [jahr].
  static DateTime defaultVerfall(int jahr) => DateTime(jahr, 3, 31, 12);

  static DateTime? _dateOnly(DateTime? d) =>
      d == null ? null : DateTime(d.year, d.month, d.day, 12);

  factory UrlaubskontoJahr.fromFirestore(String id, Map<String, dynamic> map) {
    return UrlaubskontoJahr(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      jahr: parse.toInt(map['jahr']) ?? DateTime.now().year,
      vortragVorjahrTage: parse.toDouble(map['vortragVorjahrTage']) ?? 0,
      vortragVerfaelltAm: FirestoreDateParser.readDate(map['vortragVerfaelltAm']),
      hinweisErteiltAm: FirestoreDateParser.readDate(map['hinweisErteiltAm']),
      gewaehrterMehrurlaubTage:
          parse.toDouble(map['gewaehrterMehrurlaubTage']) ?? 0,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory UrlaubskontoJahr.fromMap(Map<String, dynamic> map) {
    return UrlaubskontoJahr(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      jahr: parse.toInt(map['jahr']) ?? DateTime.now().year,
      vortragVorjahrTage: parse.toDouble(map['vortrag_vorjahr_tage']) ?? 0,
      vortragVerfaelltAm:
          FirestoreDateParser.readLocalDate(map['vortrag_verfaellt_am']),
      hinweisErteiltAm:
          FirestoreDateParser.readLocalDate(map['hinweis_erteilt_am']),
      gewaehrterMehrurlaubTage:
          parse.toDouble(map['gewaehrter_mehrurlaub_tage']) ?? 0,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'jahr': jahr,
      'vortragVorjahrTage': vortragVorjahrTage,
      'vortragVerfaelltAm': _dateOnly(vortragVerfaelltAm) == null
          ? null
          : Timestamp.fromDate(_dateOnly(vortragVerfaelltAm)!),
      'hinweisErteiltAm': _dateOnly(hinweisErteiltAm) == null
          ? null
          : Timestamp.fromDate(_dateOnly(hinweisErteiltAm)!),
      'gewaehrterMehrurlaubTage': gewaehrterMehrurlaubTage,
      'createdByUid': createdByUid,
      if (createdAt == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'jahr': jahr,
      'vortrag_vorjahr_tage': vortragVorjahrTage,
      'vortrag_verfaellt_am': _dateOnly(vortragVerfaelltAm)?.toIso8601String(),
      'hinweis_erteilt_am': _dateOnly(hinweisErteiltAm)?.toIso8601String(),
      'gewaehrter_mehrurlaub_tage': gewaehrterMehrurlaubTage,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  UrlaubskontoJahr copyWith({
    String? id,
    String? orgId,
    String? userId,
    int? jahr,
    double? vortragVorjahrTage,
    DateTime? vortragVerfaelltAm,
    bool clearVortragVerfaelltAm = false,
    DateTime? hinweisErteiltAm,
    bool clearHinweisErteiltAm = false,
    double? gewaehrterMehrurlaubTage,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UrlaubskontoJahr(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      jahr: jahr ?? this.jahr,
      vortragVorjahrTage: vortragVorjahrTage ?? this.vortragVorjahrTage,
      vortragVerfaelltAm: clearVortragVerfaelltAm
          ? null
          : (vortragVerfaelltAm ?? this.vortragVerfaelltAm),
      hinweisErteiltAm: clearHinweisErteiltAm
          ? null
          : (hinweisErteiltAm ?? this.hinweisErteiltAm),
      gewaehrterMehrurlaubTage:
          gewaehrterMehrurlaubTage ?? this.gewaehrterMehrurlaubTage,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
