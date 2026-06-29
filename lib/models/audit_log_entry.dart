import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';

/// Art einer protokollierten Änderung.
///
/// [corrected] ist eine fachliche Korrektur eines bestehenden Datensatzes
/// (z. B. nachträglich geänderter Zeiteintrag) – bewusst getrennt vom
/// generischen [updated], damit revisionsrelevante Korrekturen filterbar sind.
enum AuditAction { created, updated, deleted, corrected }

extension AuditActionX on AuditAction {
  String get value => switch (this) {
        AuditAction.created => 'created',
        AuditAction.updated => 'updated',
        AuditAction.deleted => 'deleted',
        AuditAction.corrected => 'corrected',
      };

  String get label => switch (this) {
        AuditAction.created => 'Angelegt',
        AuditAction.updated => 'Geändert',
        AuditAction.deleted => 'Gelöscht',
        AuditAction.corrected => 'Korrigiert',
      };

  static AuditAction fromValue(String? value) => switch (value) {
        'created' => AuditAction.created,
        'deleted' => AuditAction.deleted,
        'corrected' => AuditAction.corrected,
        _ => AuditAction.updated,
      };
}

/// Ein Eintrag im leichten, clientseitigen Änderungsprotokoll (Audit-Trail).
///
/// Append-only „wer/wann/was" für sensible Mutationen (Lohn-Snapshots, die per
/// deterministischer Doc-ID still überschrieben werden, Preisänderungen,
/// Kontakt-Löschungen, Bestandskorrekturen). Adaptiert aus AllTecs
/// `AuditLogEntry` – **ohne** die serverseitige Hash-Chain. Org-skopiert unter
/// `organizations/{orgId}/auditLog`. Hält die Zwei-Serialisierungs-Regel ein.
class AuditLogEntry {
  const AuditLogEntry({
    this.id,
    required this.orgId,
    required this.action,
    required this.entityType,
    this.entityId,
    required this.summary,
    this.actorUid,
    this.actorName,
    this.createdAt,
  });

  final String? id;
  final String orgId;
  final AuditAction action;

  /// Fachliche Art des betroffenen Objekts (z.B. „Lohnabrechnung", „Kontakt").
  final String entityType;
  final String? entityId;

  /// Menschlich lesbare Zusammenfassung der Änderung.
  final String summary;
  final String? actorUid;
  final String? actorName;
  final DateTime? createdAt;

  factory AuditLogEntry.fromFirestore(String id, Map<String, dynamic> map) {
    return AuditLogEntry(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      action: AuditActionX.fromValue(map['action']?.toString()),
      entityType: (map['entityType'] ?? '').toString(),
      entityId: map['entityId'] as String?,
      summary: (map['summary'] ?? '').toString(),
      actorUid: map['actorUid'] as String?,
      actorName: map['actorName'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
    );
  }

  factory AuditLogEntry.fromMap(Map<String, dynamic> map) {
    return AuditLogEntry(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      action: AuditActionX.fromValue(map['action']?.toString()),
      entityType: (map['entity_type'] ?? '').toString(),
      entityId: map['entity_id'] as String?,
      summary: (map['summary'] ?? '').toString(),
      actorUid: map['actor_uid'] as String?,
      actorName: map['actor_name'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'action': action.value,
      'entityType': entityType,
      'entityId': entityId,
      'summary': summary,
      'actorUid': actorUid,
      'actorName': actorName,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'action': action.value,
      'entity_type': entityType,
      'entity_id': entityId,
      'summary': summary,
      'actor_uid': actorUid,
      'actor_name': actorName,
      'created_at': (createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .toIso8601String(),
    };
  }

  AuditLogEntry copyWith({String? id, DateTime? createdAt}) {
    return AuditLogEntry(
      id: id ?? this.id,
      orgId: orgId,
      action: action,
      entityType: entityType,
      entityId: entityId,
      summary: summary,
      actorUid: actorUid,
      actorName: actorName,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
