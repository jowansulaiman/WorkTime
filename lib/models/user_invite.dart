import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;
import 'app_user.dart';
import 'user_settings.dart';

class UserInvite {
  const UserInvite({
    this.id,
    required this.orgId,
    required this.email,
    required this.role,
    required this.settings,
    required this.createdByUid,
    this.permissions,
    this.createdAt,
    this.acceptedByUid,
    this.acceptedAt,
    this.isActive = true,
  });

  final String? id;
  final String orgId;
  final String email;
  final UserRole role;
  final UserSettings settings;
  final String createdByUid;
  final UserPermissions? permissions;
  final DateTime? createdAt;
  final String? acceptedByUid;
  final DateTime? acceptedAt;
  final bool isActive;

  String get emailLower => email.trim().toLowerCase();

  bool get isAccepted => acceptedByUid != null;
  UserPermissions get effectivePermissions =>
      permissions ?? UserPermissions.defaultsForRole(role);

  factory UserInvite.fromMap(Map<String, dynamic> map) {
    final role = UserRoleX.fromValue(map['role']?.toString());
    return UserInvite(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      role: role,
      settings: UserSettings.fromMap(
        parse.toMap(map['settings']),
      ),
      createdByUid: (map['created_by_uid'] ?? '').toString(),
      permissions: UserPermissions.fromMap(
        parse.toMap(map['permissions']),
        fallbackRole: role,
      ),
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      acceptedByUid: map['accepted_by_uid']?.toString(),
      acceptedAt: FirestoreDateParser.readLocalDate(map['accepted_at']),
      isActive: parse.toBool(map['is_active']) ?? true,
    );
  }

  factory UserInvite.fromFirestore(String id, Map<String, dynamic> map) {
    final role = UserRoleX.fromValue(map['role']?.toString());
    return UserInvite(
      id: id,
      orgId: (map['orgId'] ?? map['org_id'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      role: role,
      settings: UserSettings.fromFirestoreMap(
        parse.toMap(map['settings']),
      ),
      createdByUid:
          (map['createdByUid'] ?? map['created_by_uid'] ?? '').toString(),
      permissions: UserPermissions.fromMap(
        parse.toMap(map['permissions']),
        fallbackRole: role,
      ),
      createdAt:
          FirestoreDateParser.readDate(map['createdAt'] ?? map['created_at']),
      acceptedByUid:
          (map['acceptedByUid'] ?? map['accepted_by_uid'])?.toString(),
      acceptedAt:
          FirestoreDateParser.readDate(map['acceptedAt'] ?? map['accepted_at']),
      isActive: parse.toBool(map['isActive'] ?? map['is_active']) ?? true,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'email': email.trim(),
      'emailLower': emailLower,
      'role': role.value,
      'settings': settings.toFirestoreMap(),
      'permissions': effectivePermissions.toFirestoreMap(),
      'createdByUid': createdByUid,
      'createdAt': FieldValue.serverTimestamp(),
      'acceptedByUid': acceptedByUid,
      'acceptedAt':
          acceptedAt == null ? null : Timestamp.fromDate(acceptedAt!.toLocal()),
      'isActive': isActive,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'email': email,
      'role': role.value,
      'settings': settings.toMap(),
      'permissions': effectivePermissions.toMap(),
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'accepted_by_uid': acceptedByUid,
      'accepted_at': acceptedAt?.toIso8601String(),
      'is_active': isActive,
    };
  }

  UserInvite copyWith({
    String? id,
    String? orgId,
    String? email,
    UserRole? role,
    UserSettings? settings,
    String? createdByUid,
    UserPermissions? permissions,
    DateTime? createdAt,
    String? acceptedByUid,
    DateTime? acceptedAt,
    bool? isActive,
  }) {
    return UserInvite(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      email: email ?? this.email,
      role: role ?? this.role,
      settings: settings ?? this.settings,
      createdByUid: createdByUid ?? this.createdByUid,
      permissions: permissions ?? this.permissions,
      createdAt: createdAt ?? this.createdAt,
      acceptedByUid: acceptedByUid ?? this.acceptedByUid,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      isActive: isActive ?? this.isActive,
    );
  }
}
