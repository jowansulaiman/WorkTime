import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';

class TeamDefinition {
  TeamDefinition({
    this.id,
    required this.orgId,
    required String name,
    this.memberIds = const [],
    String? description,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  })  : name = name.trim(),
        description = _trimmedOrNull(description);

  final String? id;
  final String orgId;
  final String name;
  final List<String> memberIds;
  final String? description;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory TeamDefinition.fromFirestore(String id, Map<String, dynamic> map) {
    return TeamDefinition(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      memberIds: ((map['memberIds'] as List<dynamic>?) ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      description: map['description'] as String?,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory TeamDefinition.fromMap(Map<String, dynamic> map) {
    return TeamDefinition(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      memberIds: ((map['member_ids'] as List<dynamic>?) ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      description: map['description'] as String?,
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
      'memberIds': memberIds,
      'description': description,
      'createdByUid': createdByUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'name': name,
      'member_ids': memberIds,
      'description': description,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  static String? _trimmedOrNull(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  TeamDefinition copyWith({
    String? id,
    String? orgId,
    String? name,
    List<String>? memberIds,
    String? description,
    bool clearDescription = false,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TeamDefinition(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      name: name ?? this.name,
      memberIds: memberIds ?? this.memberIds,
      description: clearDescription ? null : (description ?? this.description),
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
