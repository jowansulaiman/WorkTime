import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Kategorie eines Personalakte-Dokuments (PA-3). Steuert Anzeige-Gruppierung
/// und die Default-Aufbewahrungsfrist (PA-8). Enthält bewusst KEINE Art.-9-
/// Kategorien (keine Diagnosen o. ä.) — eine Krankmeldung ist nur der Nachweis,
/// nicht die Diagnose.
///
/// AllTec-Parität (personal-alltec-1zu1, M4-Rest): deckt alle 9 AllTec-
/// Kategorien ab (`fortbildung` heißt hier `schulung`) und behält zusätzlich
/// die WorkTime-eigenen `lohnabrechnung`/`krankmeldung` (Lohnzettel-Ablage,
/// eAU-Nachweis). Erweiterung ist rein additiv — bestehende Dokumente behalten
/// ihre Kategorie, unbekannte Werte fallen via [DocumentCategoryX.fromValue]
/// auf `sonstiges`.
enum DocumentCategory {
  arbeitsvertrag,
  lohnabrechnung,
  bescheinigung,
  krankmeldung,
  zeugnis,
  schulung,
  abmahnung,
  kuendigung,
  fuehrungszeugnis,
  gesundheitszeugnis,
  sonstiges,
}

extension DocumentCategoryX on DocumentCategory {
  String get value => switch (this) {
        DocumentCategory.arbeitsvertrag => 'arbeitsvertrag',
        DocumentCategory.lohnabrechnung => 'lohnabrechnung',
        DocumentCategory.bescheinigung => 'bescheinigung',
        DocumentCategory.krankmeldung => 'krankmeldung',
        DocumentCategory.zeugnis => 'zeugnis',
        DocumentCategory.schulung => 'schulung',
        DocumentCategory.abmahnung => 'abmahnung',
        DocumentCategory.kuendigung => 'kuendigung',
        DocumentCategory.fuehrungszeugnis => 'fuehrungszeugnis',
        DocumentCategory.gesundheitszeugnis => 'gesundheitszeugnis',
        DocumentCategory.sonstiges => 'sonstiges',
      };

  String get label => switch (this) {
        DocumentCategory.arbeitsvertrag => 'Arbeitsvertrag',
        DocumentCategory.lohnabrechnung => 'Lohnabrechnung',
        DocumentCategory.bescheinigung => 'Bescheinigung',
        DocumentCategory.krankmeldung => 'Krankmeldung',
        DocumentCategory.zeugnis => 'Zeugnis',
        DocumentCategory.schulung => 'Schulung',
        DocumentCategory.abmahnung => 'Abmahnung',
        DocumentCategory.kuendigung => 'Kündigung',
        DocumentCategory.fuehrungszeugnis => 'Führungszeugnis',
        DocumentCategory.gesundheitszeugnis => 'Gesundheitszeugnis',
        DocumentCategory.sonstiges => 'Sonstiges',
      };

  /// Gesetzliche Default-Aufbewahrung in Jahren ab Upload (PA-8, überschreibbar):
  /// Lohnunterlagen 6 J. (§41 EStG), Verträge/Zeugnisse bis Austritt + Puffer
  /// (hier 10 J. großzügig), Krankmeldung 2 J. (Arbeitszeitnachweis-nah),
  /// Sonstiges/Bescheinigung 10 J. Der konkrete Wert wird beim Upload
  /// vorbelegt und kann angepasst werden.
  int get defaultRetentionYears => switch (this) {
        DocumentCategory.lohnabrechnung => 6,
        DocumentCategory.krankmeldung => 2,
        // Abmahnungen werden nach HR-Praxis nach wenigen Jahren entfernt
        // (kein gesetzlicher Aufbewahrungszwang; Wirkung verblasst).
        DocumentCategory.abmahnung => 3,
        DocumentCategory.arbeitsvertrag => 10,
        DocumentCategory.kuendigung => 10,
        DocumentCategory.zeugnis => 10,
        DocumentCategory.bescheinigung => 10,
        // Führungszeugnis: datensparsam — kurze Frist, i. d. R. reicht die
        // dokumentierte Einsichtnahme statt Dauer-Ablage.
        DocumentCategory.fuehrungszeugnis => 3,
        // Gesundheitszeugnis/IfSG-Belehrung (§ 43): nachweisrelevant im Handel.
        DocumentCategory.gesundheitszeugnis => 10,
        DocumentCategory.schulung => 10,
        DocumentCategory.sonstiges => 10,
      };

  /// Default-Branch wirft nie (Enum-Kopplungsregel).
  static DocumentCategory fromValue(String? value) => switch (value) {
        'arbeitsvertrag' => DocumentCategory.arbeitsvertrag,
        'lohnabrechnung' => DocumentCategory.lohnabrechnung,
        'bescheinigung' => DocumentCategory.bescheinigung,
        'krankmeldung' => DocumentCategory.krankmeldung,
        'zeugnis' => DocumentCategory.zeugnis,
        'schulung' => DocumentCategory.schulung,
        // AllTec-Alias: dort heißt die Kategorie `fortbildung`.
        'fortbildung' => DocumentCategory.schulung,
        'abmahnung' => DocumentCategory.abmahnung,
        'kuendigung' => DocumentCategory.kuendigung,
        'fuehrungszeugnis' => DocumentCategory.fuehrungszeugnis,
        'gesundheitszeugnis' => DocumentCategory.gesundheitszeugnis,
        _ => DocumentCategory.sonstiges,
      };
}

/// Metadaten eines in der digitalen Personalakte abgelegten Dokuments (PA-3).
/// Die Binärdatei selbst liegt in Firebase Storage unter [storagePath]; dieses
/// Doc trägt nur Metadaten (org-skopiert). Bewusst **cloud-only** (keine
/// SharedPreferences-Spiegelung — eine Datei ohne Binärinhalt ist wertlos).
class EmployeeDocument {
  const EmployeeDocument({
    this.id,
    required this.orgId,
    required this.userId,
    this.category = DocumentCategory.sonstiges,
    required this.title,
    this.fileName = '',
    this.contentType = 'application/octet-stream',
    this.sizeBytes = 0,
    required this.storagePath,
    this.note,
    this.visibleToEmployee = true,
    this.acknowledgedAt,
    this.retentionUntil,
    this.uploadedByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String userId;
  final DocumentCategory category;
  final String title;
  final String fileName;
  final String contentType;
  final int sizeBytes;

  /// Voller Storage-Objektpfad `employee-documents/{orgId}/{userId}/{docId}`
  /// (KEINE PII im Pfad — Objektname = docId).
  final String storagePath;
  final String? note;

  /// Ob der Mitarbeiter das Dokument sehen darf. `false` = interne Ablage
  /// (z. B. Abmahnungs-Entwurf) — nur Admin. Steuert Self-Read (Rules +
  /// Storage-Rules) und die Push-Benachrichtigung.
  final bool visibleToEmployee;

  /// Zeitpunkt der Lesebestätigung durch den Mitarbeiter (optional, PA-3.4) —
  /// das EINZIGE Feld, das der Mitarbeiter selbst schreiben darf.
  final DateTime? acknowledgedAt;

  /// Ende der Aufbewahrungsfrist (PA-8) — aus [DocumentCategory.defaultRetentionYears]
  /// vorbelegt, überschreibbar. `null` = keine Frist gesetzt.
  final DateTime? retentionUntil;

  final String? uploadedByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get acknowledged => acknowledgedAt != null;

  /// Aufbewahrungsfrist am [now] abgelaufen (PA-8.1)? `false`, wenn keine Frist
  /// gesetzt ist (`retentionUntil == null` = unbefristet aufbewahren).
  bool retentionExpired(DateTime now) {
    final until = retentionUntil;
    if (until == null) return false;
    return now.isAfter(DateTime(until.year, until.month, until.day, 23, 59, 59));
  }

  static DateTime? _dateOnly(DateTime? d) =>
      d == null ? null : DateTime(d.year, d.month, d.day, 12);

  factory EmployeeDocument.fromFirestore(String id, Map<String, dynamic> map) {
    return EmployeeDocument(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      category: DocumentCategoryX.fromValue(map['category']?.toString()),
      title: (map['title'] ?? '').toString(),
      fileName: (map['fileName'] ?? '').toString(),
      contentType:
          (map['contentType'] ?? 'application/octet-stream').toString(),
      sizeBytes: parse.toInt(map['sizeBytes']) ?? 0,
      storagePath: (map['storagePath'] ?? '').toString(),
      note: map['note'] as String?,
      visibleToEmployee: parse.toBool(map['visibleToEmployee']) ?? true,
      acknowledgedAt: FirestoreDateParser.readDate(map['acknowledgedAt']),
      retentionUntil: FirestoreDateParser.readDate(map['retentionUntil']),
      uploadedByUid: map['uploadedByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory EmployeeDocument.fromMap(Map<String, dynamic> map) {
    return EmployeeDocument(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      category: DocumentCategoryX.fromValue(map['category']?.toString()),
      title: (map['title'] ?? '').toString(),
      fileName: (map['file_name'] ?? '').toString(),
      contentType:
          (map['content_type'] ?? 'application/octet-stream').toString(),
      sizeBytes: parse.toInt(map['size_bytes']) ?? 0,
      storagePath: (map['storage_path'] ?? '').toString(),
      note: map['note'] as String?,
      visibleToEmployee: parse.toBool(map['visible_to_employee']) ?? true,
      acknowledgedAt: FirestoreDateParser.readLocalDate(map['acknowledged_at']),
      retentionUntil: FirestoreDateParser.readLocalDate(map['retention_until']),
      uploadedByUid: map['uploaded_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'category': category.value,
      'title': title,
      'fileName': fileName,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'storagePath': storagePath,
      'note': note,
      'visibleToEmployee': visibleToEmployee,
      'acknowledgedAt':
          acknowledgedAt == null ? null : Timestamp.fromDate(acknowledgedAt!),
      'retentionUntil': _dateOnly(retentionUntil) == null
          ? null
          : Timestamp.fromDate(_dateOnly(retentionUntil)!),
      'uploadedByUid': uploadedByUid,
      if (createdAt == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'category': category.value,
      'title': title,
      'file_name': fileName,
      'content_type': contentType,
      'size_bytes': sizeBytes,
      'storage_path': storagePath,
      'note': note,
      'visible_to_employee': visibleToEmployee,
      'acknowledged_at': acknowledgedAt?.toIso8601String(),
      'retention_until': _dateOnly(retentionUntil)?.toIso8601String(),
      'uploaded_by_uid': uploadedByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  EmployeeDocument copyWith({
    String? id,
    String? orgId,
    String? userId,
    DocumentCategory? category,
    String? title,
    String? fileName,
    String? contentType,
    int? sizeBytes,
    String? storagePath,
    String? note,
    bool clearNote = false,
    bool? visibleToEmployee,
    DateTime? acknowledgedAt,
    bool clearAcknowledgedAt = false,
    DateTime? retentionUntil,
    bool clearRetentionUntil = false,
    String? uploadedByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmployeeDocument(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      category: category ?? this.category,
      title: title ?? this.title,
      fileName: fileName ?? this.fileName,
      contentType: contentType ?? this.contentType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      storagePath: storagePath ?? this.storagePath,
      note: clearNote ? null : (note ?? this.note),
      visibleToEmployee: visibleToEmployee ?? this.visibleToEmployee,
      acknowledgedAt:
          clearAcknowledgedAt ? null : (acknowledgedAt ?? this.acknowledgedAt),
      retentionUntil:
          clearRetentionUntil ? null : (retentionUntil ?? this.retentionUntil),
      uploadedByUid: uploadedByUid ?? this.uploadedByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
