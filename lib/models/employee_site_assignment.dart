import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

class EmployeeSiteAssignment {
  const EmployeeSiteAssignment({
    this.id,
    required this.orgId,
    required this.userId,
    required this.siteId,
    required this.siteName,
    this.role,
    this.qualificationIds = const [],
    this.isPrimary = false,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String userId;
  final String siteId;
  final String siteName;
  final String? role;
  final List<String> qualificationIds;
  final bool isPrimary;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory EmployeeSiteAssignment.fromFirestore(
    String id,
    Map<String, dynamic> map,
  ) {
    return EmployeeSiteAssignment(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      siteId: (map['siteId'] ?? '').toString(),
      siteName: (map['siteName'] ?? '').toString(),
      role: map['role'] as String?,
      qualificationIds:
          ((map['qualificationIds'] as List<dynamic>?) ?? const [])
              .map((value) => value.toString())
              .toList(growable: false),
      isPrimary: parse.toBool(map['isPrimary']) ?? false,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory EmployeeSiteAssignment.fromMap(Map<String, dynamic> map) {
    return EmployeeSiteAssignment(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      siteId: (map['site_id'] ?? '').toString(),
      siteName: (map['site_name'] ?? '').toString(),
      role: map['role'] as String?,
      qualificationIds:
          ((map['qualification_ids'] as List<dynamic>?) ?? const [])
              .map((value) => value.toString())
              .toList(growable: false),
      isPrimary: parse.toBool(map['is_primary']) ?? false,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'siteId': siteId,
      'siteName': siteName,
      'role': role,
      'qualificationIds': qualificationIds,
      'isPrimary': isPrimary,
      'createdByUid': createdByUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'site_id': siteId,
      'site_name': siteName,
      'role': role,
      'qualification_ids': qualificationIds,
      'is_primary': isPrimary,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  EmployeeSiteAssignment copyWith({
    String? id,
    String? orgId,
    String? userId,
    String? siteId,
    String? siteName,
    String? role,
    List<String>? qualificationIds,
    bool clearRole = false,
    bool? isPrimary,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmployeeSiteAssignment(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      siteId: siteId ?? this.siteId,
      siteName: siteName ?? this.siteName,
      role: clearRole ? null : (role ?? this.role),
      qualificationIds: qualificationIds ?? this.qualificationIds,
      isPrimary: isPrimary ?? this.isPrimary,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
