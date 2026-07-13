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
/// **PERSONAL-4:** abgeleiteter Bearbeitungsstand eines Dokuments (kein
/// persistiertes Feld — s. [EmployeeDocument.workflowStatus]).
enum EmployeeDocumentWorkflowStatus {
  offen,
  bereitgestellt,
  geoeffnet,
  bestaetigt,
  abgelehnt,
}

extension EmployeeDocumentWorkflowStatusX on EmployeeDocumentWorkflowStatus {
  String get label => switch (this) {
        EmployeeDocumentWorkflowStatus.offen => 'Offen',
        EmployeeDocumentWorkflowStatus.bereitgestellt => 'Bereitgestellt',
        EmployeeDocumentWorkflowStatus.geoeffnet => 'Geöffnet',
        EmployeeDocumentWorkflowStatus.bestaetigt => 'Bestätigt',
        EmployeeDocumentWorkflowStatus.abgelehnt => 'Abgelehnt',
      };
}

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
    this.requiresAcknowledgement = false,
    this.visibleSince,
    this.openedAt,
    this.downloadedAt,
    this.acknowledgedAt,
    this.declinedAt,
    this.declineComment,
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

  /// **PERSONAL-4:** Ob der Mitarbeiter das Dokument aktiv bestätigen muss
  /// (steuert Erinnerungen + Workflow-Status). Default false = reine Ablage.
  final bool requiresAcknowledgement;

  /// **PERSONAL-4:** Zeitpunkt der **Bereitstellung** (admin-seitig beim
  /// Sichtbarschalten/Upload gesetzt — NICHT vom MA). Leser/Nightly nutzen
  /// `visibleSince ?? createdAt` (Bestands-Dokumente ohne Feld, Q6).
  final DateTime? visibleSince;

  /// **PERSONAL-4:** Zeitpunkt des **bewussten Öffnens** durch den MA (Viewer-/
  /// Download-Aktion — NICHT das bloße Rendern der Dokumentliste).
  final DateTime? openedAt;

  /// **PERSONAL-4:** optionaler Download-Zeitpunkt durch den MA.
  final DateTime? downloadedAt;

  /// Zeitpunkt der Lesebestätigung durch den Mitarbeiter (optional, PA-3.4).
  final DateTime? acknowledgedAt;

  /// **PERSONAL-4:** Zeitpunkt der **Ablehnung** durch den MA (schlägt eine
  /// Bestätigung — s. [workflowStatus]).
  final DateTime? declinedAt;

  /// **PERSONAL-4:** Pflicht-Kommentar zur Ablehnung (nur zusammen mit
  /// [declinedAt] — Rules erzwingen das).
  final String? declineComment;

  /// Ende der Aufbewahrungsfrist (PA-8) — aus [DocumentCategory.defaultRetentionYears]
  /// vorbelegt, überschreibbar. `null` = keine Frist gesetzt.
  final DateTime? retentionUntil;

  final String? uploadedByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get acknowledged => acknowledgedAt != null;

  /// **PERSONAL-4:** Bereitstellungszeitpunkt für Leser/Erinnerungen —
  /// `visibleSince ?? createdAt` (Bestands-Dokumente ohne `visibleSince`, Q6).
  DateTime? get effectiveVisibleSince => visibleSince ?? createdAt;

  /// **PERSONAL-4:** ABGELEITETER Workflow-Status (kein persistiertes Enum →
  /// keine Drift). Reihenfolge: eine **Ablehnung schlägt** eine Bestätigung.
  EmployeeDocumentWorkflowStatus get workflowStatus {
    if (declinedAt != null) return EmployeeDocumentWorkflowStatus.abgelehnt;
    if (acknowledgedAt != null) {
      return EmployeeDocumentWorkflowStatus.bestaetigt;
    }
    if (openedAt != null) return EmployeeDocumentWorkflowStatus.geoeffnet;
    if (visibleToEmployee && effectiveVisibleSince != null) {
      return EmployeeDocumentWorkflowStatus.bereitgestellt;
    }
    return EmployeeDocumentWorkflowStatus.offen;
  }

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
      requiresAcknowledgement:
          parse.toBool(map['requiresAcknowledgement']) ?? false,
      visibleSince: FirestoreDateParser.readDate(map['visibleSince']),
      openedAt: FirestoreDateParser.readDate(map['openedAt']),
      downloadedAt: FirestoreDateParser.readDate(map['downloadedAt']),
      acknowledgedAt: FirestoreDateParser.readDate(map['acknowledgedAt']),
      declinedAt: FirestoreDateParser.readDate(map['declinedAt']),
      declineComment: map['declineComment'] as String?,
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
      requiresAcknowledgement:
          parse.toBool(map['requires_acknowledgement']) ?? false,
      visibleSince: FirestoreDateParser.readLocalDate(map['visible_since']),
      openedAt: FirestoreDateParser.readLocalDate(map['opened_at']),
      downloadedAt: FirestoreDateParser.readLocalDate(map['downloaded_at']),
      acknowledgedAt: FirestoreDateParser.readLocalDate(map['acknowledged_at']),
      declinedAt: FirestoreDateParser.readLocalDate(map['declined_at']),
      declineComment: map['decline_comment'] as String?,
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
      'requiresAcknowledgement': requiresAcknowledgement,
      'visibleSince':
          visibleSince == null ? null : Timestamp.fromDate(visibleSince!),
      'openedAt': openedAt == null ? null : Timestamp.fromDate(openedAt!),
      'downloadedAt':
          downloadedAt == null ? null : Timestamp.fromDate(downloadedAt!),
      'acknowledgedAt':
          acknowledgedAt == null ? null : Timestamp.fromDate(acknowledgedAt!),
      'declinedAt': declinedAt == null ? null : Timestamp.fromDate(declinedAt!),
      'declineComment': declineComment,
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
      'requires_acknowledgement': requiresAcknowledgement,
      'visible_since': visibleSince?.toIso8601String(),
      'opened_at': openedAt?.toIso8601String(),
      'downloaded_at': downloadedAt?.toIso8601String(),
      'acknowledged_at': acknowledgedAt?.toIso8601String(),
      'declined_at': declinedAt?.toIso8601String(),
      'decline_comment': declineComment,
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
    bool? requiresAcknowledgement,
    DateTime? visibleSince,
    bool clearVisibleSince = false,
    DateTime? openedAt,
    bool clearOpenedAt = false,
    DateTime? downloadedAt,
    bool clearDownloadedAt = false,
    DateTime? acknowledgedAt,
    bool clearAcknowledgedAt = false,
    DateTime? declinedAt,
    bool clearDeclinedAt = false,
    String? declineComment,
    bool clearDeclineComment = false,
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
      requiresAcknowledgement:
          requiresAcknowledgement ?? this.requiresAcknowledgement,
      visibleSince:
          clearVisibleSince ? null : (visibleSince ?? this.visibleSince),
      openedAt: clearOpenedAt ? null : (openedAt ?? this.openedAt),
      downloadedAt:
          clearDownloadedAt ? null : (downloadedAt ?? this.downloadedAt),
      acknowledgedAt:
          clearAcknowledgedAt ? null : (acknowledgedAt ?? this.acknowledgedAt),
      declinedAt: clearDeclinedAt ? null : (declinedAt ?? this.declinedAt),
      declineComment: clearDeclineComment
          ? null
          : (declineComment ?? this.declineComment),
      retentionUntil:
          clearRetentionUntil ? null : (retentionUntil ?? this.retentionUntil),
      uploadedByUid: uploadedByUid ?? this.uploadedByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
