import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Art einer Urlaubs-Korrekturbuchung (IDA `hr_urlaubsanpassungen`:
/// 1=ABZUG_ALLG, 2=ABZUG_FRIST, 3=SONDERURLAUB, 4=ALLG).
enum UrlaubsAnpassungArt { abzugAllgemein, abzugFrist, sonderurlaub, allgemein }

extension UrlaubsAnpassungArtX on UrlaubsAnpassungArt {
  String get value => switch (this) {
        UrlaubsAnpassungArt.abzugAllgemein => 'abzug_allgemein',
        UrlaubsAnpassungArt.abzugFrist => 'abzug_frist',
        UrlaubsAnpassungArt.sonderurlaub => 'sonderurlaub',
        UrlaubsAnpassungArt.allgemein => 'allgemein',
      };

  String get label => switch (this) {
        UrlaubsAnpassungArt.abzugAllgemein => 'Abzug (allgemein)',
        UrlaubsAnpassungArt.abzugFrist => 'Abzug (Frist/Verfall)',
        UrlaubsAnpassungArt.sonderurlaub => 'Sonderurlaub',
        UrlaubsAnpassungArt.allgemein => 'Allgemein',
      };

  static UrlaubsAnpassungArt fromValue(String? value) => switch (value) {
        'abzug_allgemein' => UrlaubsAnpassungArt.abzugAllgemein,
        'abzug_frist' => UrlaubsAnpassungArt.abzugFrist,
        'sonderurlaub' => UrlaubsAnpassungArt.sonderurlaub,
        _ => UrlaubsAnpassungArt.allgemein,
      };
}

/// Manuelle ±-Korrektur des Urlaubsanspruchs eines Mitarbeiters für ein Jahr
/// (Korrektur-Ledger, M-U). Org-skopiert, admin-only.
class Urlaubsanpassung {
  const Urlaubsanpassung({
    this.id,
    required this.orgId,
    required this.userId,
    required this.jahr,
    this.tage = 0,
    this.art = UrlaubsAnpassungArt.allgemein,
    this.anmerkung,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String userId;
  final int jahr;

  /// Signierter Tageswert (+ gutgeschrieben, − abgezogen).
  final double tage;
  final UrlaubsAnpassungArt art;
  final String? anmerkung;

  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Urlaubsanpassung.fromFirestore(String id, Map<String, dynamic> map) {
    return Urlaubsanpassung(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      jahr: parse.toInt(map['jahr']) ?? DateTime.now().year,
      tage: parse.toDouble(map['tage']) ?? 0,
      art: UrlaubsAnpassungArtX.fromValue(map['art']?.toString()),
      anmerkung: map['anmerkung'] as String?,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory Urlaubsanpassung.fromMap(Map<String, dynamic> map) {
    return Urlaubsanpassung(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      jahr: parse.toInt(map['jahr']) ?? DateTime.now().year,
      tage: parse.toDouble(map['tage']) ?? 0,
      art: UrlaubsAnpassungArtX.fromValue(map['art']?.toString()),
      anmerkung: map['anmerkung'] as String?,
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
      'tage': tage,
      'art': art.value,
      'anmerkung': anmerkung,
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
      'tage': tage,
      'art': art.value,
      'anmerkung': anmerkung,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Urlaubsanpassung copyWith({
    String? id,
    String? orgId,
    String? userId,
    int? jahr,
    double? tage,
    UrlaubsAnpassungArt? art,
    String? anmerkung,
    bool clearAnmerkung = false,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Urlaubsanpassung(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      jahr: jahr ?? this.jahr,
      tage: tage ?? this.tage,
      art: art ?? this.art,
      anmerkung: clearAnmerkung ? null : (anmerkung ?? this.anmerkung),
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
