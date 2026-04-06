import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';

class QualificationDefinition {
  const QualificationDefinition({
    this.id,
    required this.orgId,
    required this.name,
    this.description,
    this.color,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String name;
  final String? description;
  final String? color;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory QualificationDefinition.fromFirestore(
    String id,
    Map<String, dynamic> map,
  ) {
    return QualificationDefinition(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      description: map['description'] as String?,
      color: map['color'] as String?,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory QualificationDefinition.fromMap(Map<String, dynamic> map) {
    return QualificationDefinition(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      description: map['description'] as String?,
      color: map['color'] as String?,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'name': name.trim(),
      'nameLower': name.trim().toLowerCase(),
      'description': description,
      'color': color,
      'createdByUid': createdByUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'name': name,
      'description': description,
      'color': color,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  QualificationDefinition copyWith({
    String? id,
    String? orgId,
    String? name,
    String? description,
    String? color,
    bool clearDescription = false,
    bool clearColor = false,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return QualificationDefinition(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      name: name ?? this.name,
      description: clearDescription ? null : (description ?? this.description),
      color: clearColor ? null : (color ?? this.color),
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
