import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';

/// Freitext-Notiz zu einem Mitarbeiter (HR-Sub-Entität, AllTec-Parität).
///
/// Org-skopiert unter `organizations/{orgId}/employeeNotes/{noteId}`, admin-only
/// (Rules). Nur Anlegen + Löschen (kein Bearbeiten, analog AllTec). Hält die
/// Zwei-Serialisierungs-Regel ein (camelCase+Timestamp / snake_case+ISO).
class EmployeeNote {
  const EmployeeNote({
    this.id,
    required this.orgId,
    required this.userId,
    this.text = '',
    this.createdByUid,
    this.createdAt,
  });

  final String? id;
  final String orgId;
  final String userId;
  final String text;
  final String? createdByUid;
  final DateTime? createdAt;

  factory EmployeeNote.fromFirestore(String id, Map<String, dynamic> map) {
    return EmployeeNote(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
    );
  }

  factory EmployeeNote.fromMap(Map<String, dynamic> map) {
    return EmployeeNote(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'text': text,
      'createdByUid': createdByUid,
      // Doc-ID wird vor dem Schreiben gesetzt → an createdAt festmachen.
      if (createdAt == null) 'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'text': text,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  EmployeeNote copyWith({
    String? id,
    String? orgId,
    String? userId,
    String? text,
    String? createdByUid,
    DateTime? createdAt,
  }) {
    return EmployeeNote(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      text: text ?? this.text,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
