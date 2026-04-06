import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;
import 'user_settings.dart';

enum UserRole { admin, teamlead, employee }

extension UserRoleX on UserRole {
  String get value => switch (this) {
        UserRole.admin => 'admin',
        UserRole.teamlead => 'teamlead',
        UserRole.employee => 'employee',
      };

  String get label => switch (this) {
        UserRole.admin => 'Admin',
        UserRole.teamlead => 'Teamleiter',
        UserRole.employee => 'Mitarbeiter',
      };

  static UserRole fromValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'admin':
        return UserRole.admin;
      case 'teamlead':
      case 'teamleiter':
        return UserRole.teamlead;
      default:
        return UserRole.employee;
    }
  }
}

class UserPermissions {
  const UserPermissions({
    required this.canViewSchedule,
    required this.canEditSchedule,
    required this.canViewTimeTracking,
    required this.canEditTimeEntries,
    required this.canViewReports,
  });

  final bool canViewSchedule;
  final bool canEditSchedule;
  final bool canViewTimeTracking;
  final bool canEditTimeEntries;
  final bool canViewReports;

  static UserPermissions defaultsForRole(UserRole role) {
    return switch (role) {
      UserRole.admin => const UserPermissions(
          canViewSchedule: true,
          canEditSchedule: true,
          canViewTimeTracking: true,
          canEditTimeEntries: true,
          canViewReports: true,
        ),
      UserRole.teamlead => const UserPermissions(
          canViewSchedule: true,
          canEditSchedule: true,
          canViewTimeTracking: true,
          canEditTimeEntries: true,
          canViewReports: true,
        ),
      UserRole.employee => const UserPermissions(
          canViewSchedule: true,
          canEditSchedule: false,
          canViewTimeTracking: true,
          canEditTimeEntries: true,
          canViewReports: true,
        ),
    };
  }

  factory UserPermissions.fromMap(
    Map<String, dynamic>? map, {
    required UserRole fallbackRole,
  }) {
    final defaults = defaultsForRole(fallbackRole);
    final data = map ?? const <String, dynamic>{};
    return UserPermissions(
      canViewSchedule:
          parse.toBool(data['canViewSchedule']) ?? defaults.canViewSchedule,
      canEditSchedule:
          parse.toBool(data['canEditSchedule']) ?? defaults.canEditSchedule,
      canViewTimeTracking: parse.toBool(data['canViewTimeTracking']) ??
          defaults.canViewTimeTracking,
      canEditTimeEntries: parse.toBool(data['canEditTimeEntries']) ??
          defaults.canEditTimeEntries,
      canViewReports:
          parse.toBool(data['canViewReports']) ?? defaults.canViewReports,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'canViewSchedule': canViewSchedule,
      'canEditSchedule': canEditSchedule,
      'canViewTimeTracking': canViewTimeTracking,
      'canEditTimeEntries': canEditTimeEntries,
      'canViewReports': canViewReports,
    };
  }

  Map<String, dynamic> toMap() => toFirestoreMap();

  UserPermissions copyWith({
    bool? canViewSchedule,
    bool? canEditSchedule,
    bool? canViewTimeTracking,
    bool? canEditTimeEntries,
    bool? canViewReports,
  }) {
    return UserPermissions(
      canViewSchedule: canViewSchedule ?? this.canViewSchedule,
      canEditSchedule: canEditSchedule ?? this.canEditSchedule,
      canViewTimeTracking: canViewTimeTracking ?? this.canViewTimeTracking,
      canEditTimeEntries: canEditTimeEntries ?? this.canEditTimeEntries,
      canViewReports: canViewReports ?? this.canViewReports,
    );
  }

  List<String> summaryLabels() {
    final labels = <String>[];
    if (canEditSchedule) {
      labels.add('Plan bearbeiten');
    } else if (canViewSchedule) {
      labels.add('Plan ansehen');
    }
    if (canEditTimeEntries) {
      labels.add('Zeit bearbeiten');
    } else if (canViewTimeTracking) {
      labels.add('Zeit ansehen');
    }
    if (canViewReports) {
      labels.add('Berichte');
    }
    return labels;
  }
}

class WorkRuleSettings {
  const WorkRuleSettings({
    this.enforceMinRestTime = true,
    this.enforceBreakAfterSixHours = true,
    this.enforceBreakAfterNineHours = true,
    this.enforceMaxDailyMinutes = true,
    this.enforceMinijobLimit = true,
    this.warnDailyAverageExceeded = true,
    this.warnForwardRotation = true,
    this.warnOvertime = true,
    this.warnSundayWork = true,
  });

  static const int ruleCount = 9;

  final bool enforceMinRestTime;
  final bool enforceBreakAfterSixHours;
  final bool enforceBreakAfterNineHours;
  final bool enforceMaxDailyMinutes;
  final bool enforceMinijobLimit;
  final bool warnDailyAverageExceeded;
  final bool warnForwardRotation;
  final bool warnOvertime;
  final bool warnSundayWork;

  factory WorkRuleSettings.fromMap(Map<String, dynamic>? map) {
    final data = map ?? const <String, dynamic>{};
    return WorkRuleSettings(
      enforceMinRestTime: parse.toBool(
            data['enforceMinRestTime'] ?? data['enforce_min_rest_time'],
          ) ??
          true,
      enforceBreakAfterSixHours: parse.toBool(
            data['enforceBreakAfterSixHours'] ??
                data['enforce_break_after_six_hours'],
          ) ??
          true,
      enforceBreakAfterNineHours: parse.toBool(
            data['enforceBreakAfterNineHours'] ??
                data['enforce_break_after_nine_hours'],
          ) ??
          true,
      enforceMaxDailyMinutes: parse.toBool(
            data['enforceMaxDailyMinutes'] ?? data['enforce_max_daily_minutes'],
          ) ??
          true,
      enforceMinijobLimit: parse.toBool(
            data['enforceMinijobLimit'] ?? data['enforce_minijob_limit'],
          ) ??
          true,
      warnDailyAverageExceeded: parse.toBool(
            data['warnDailyAverageExceeded'] ??
                data['warn_daily_average_exceeded'],
          ) ??
          true,
      warnForwardRotation: parse.toBool(
            data['warnForwardRotation'] ?? data['warn_forward_rotation'],
          ) ??
          true,
      warnOvertime:
          parse.toBool(data['warnOvertime'] ?? data['warn_overtime']) ?? true,
      warnSundayWork:
          parse.toBool(data['warnSundayWork'] ?? data['warn_sunday_work']) ??
              true,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'enforceMinRestTime': enforceMinRestTime,
      'enforceBreakAfterSixHours': enforceBreakAfterSixHours,
      'enforceBreakAfterNineHours': enforceBreakAfterNineHours,
      'enforceMaxDailyMinutes': enforceMaxDailyMinutes,
      'enforceMinijobLimit': enforceMinijobLimit,
      'warnDailyAverageExceeded': warnDailyAverageExceeded,
      'warnForwardRotation': warnForwardRotation,
      'warnOvertime': warnOvertime,
      'warnSundayWork': warnSundayWork,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'enforce_min_rest_time': enforceMinRestTime,
      'enforce_break_after_six_hours': enforceBreakAfterSixHours,
      'enforce_break_after_nine_hours': enforceBreakAfterNineHours,
      'enforce_max_daily_minutes': enforceMaxDailyMinutes,
      'enforce_minijob_limit': enforceMinijobLimit,
      'warn_daily_average_exceeded': warnDailyAverageExceeded,
      'warn_forward_rotation': warnForwardRotation,
      'warn_overtime': warnOvertime,
      'warn_sunday_work': warnSundayWork,
    };
  }

  WorkRuleSettings copyWith({
    bool? enforceMinRestTime,
    bool? enforceBreakAfterSixHours,
    bool? enforceBreakAfterNineHours,
    bool? enforceMaxDailyMinutes,
    bool? enforceMinijobLimit,
    bool? warnDailyAverageExceeded,
    bool? warnForwardRotation,
    bool? warnOvertime,
    bool? warnSundayWork,
  }) {
    return WorkRuleSettings(
      enforceMinRestTime: enforceMinRestTime ?? this.enforceMinRestTime,
      enforceBreakAfterSixHours:
          enforceBreakAfterSixHours ?? this.enforceBreakAfterSixHours,
      enforceBreakAfterNineHours:
          enforceBreakAfterNineHours ?? this.enforceBreakAfterNineHours,
      enforceMaxDailyMinutes:
          enforceMaxDailyMinutes ?? this.enforceMaxDailyMinutes,
      enforceMinijobLimit: enforceMinijobLimit ?? this.enforceMinijobLimit,
      warnDailyAverageExceeded:
          warnDailyAverageExceeded ?? this.warnDailyAverageExceeded,
      warnForwardRotation: warnForwardRotation ?? this.warnForwardRotation,
      warnOvertime: warnOvertime ?? this.warnOvertime,
      warnSundayWork: warnSundayWork ?? this.warnSundayWork,
    );
  }

  int get enabledCount => [
        enforceMinRestTime,
        enforceBreakAfterSixHours,
        enforceBreakAfterNineHours,
        enforceMaxDailyMinutes,
        enforceMinijobLimit,
        warnDailyAverageExceeded,
        warnForwardRotation,
        warnOvertime,
        warnSundayWork,
      ].where((value) => value).length;
}

class AppUserProfile {
  const AppUserProfile({
    required this.uid,
    required this.orgId,
    required this.email,
    required this.role,
    required this.isActive,
    required this.settings,
    this.workRuleSettings = const WorkRuleSettings(),
    this.permissions,
    this.photoUrl,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String orgId;
  final String email;
  final UserRole role;
  final bool isActive;
  final UserSettings settings;
  final WorkRuleSettings workRuleSettings;
  final UserPermissions? permissions;
  final String? photoUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayName =>
      settings.name.trim().isEmpty ? email.split('@').first : settings.name;

  bool get isAdmin => role == UserRole.admin;

  bool get isTeamLead => role == UserRole.teamlead;
  UserPermissions get effectivePermissions => isAdmin
      ? UserPermissions.defaultsForRole(UserRole.admin)
      : (permissions ?? UserPermissions.defaultsForRole(role));
  bool get canViewSchedule => isAdmin || effectivePermissions.canViewSchedule;
  bool get canManageShifts => isAdmin || effectivePermissions.canEditSchedule;
  bool get canViewTimeTracking =>
      isAdmin || effectivePermissions.canViewTimeTracking;
  bool get canEditTimeEntries =>
      isAdmin || effectivePermissions.canEditTimeEntries;
  bool get canViewReports => isAdmin || effectivePermissions.canViewReports;

  bool canReviewAbsenceRequestFor(AppUserProfile requester) {
    if (!canManageShifts || !isActive) {
      return false;
    }
    if (isAdmin) {
      return true;
    }
    if (requester.uid == uid) {
      return false;
    }
    return !requester.canManageShifts;
  }

  bool canManageApprovedVacationFor(AppUserProfile requester) {
    if (!canManageShifts || !isActive) {
      return false;
    }
    if (isAdmin) {
      return true;
    }
    if (requester.uid == uid) {
      return true;
    }
    return !requester.canManageShifts;
  }

  factory AppUserProfile.fromMap(Map<String, dynamic> map) {
    final role = UserRoleX.fromValue(map['role']?.toString());
    return AppUserProfile(
      uid: (map['uid'] ?? '').toString(),
      orgId: (map['org_id'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      role: role,
      isActive: parse.toBool(map['is_active']) ?? true,
      settings: UserSettings.fromMap(
        parse.toMap(map['settings']),
      ),
      workRuleSettings: WorkRuleSettings.fromMap(
        parse.toMap(map['work_rule_settings'] ?? map['workRuleSettings']),
      ),
      permissions: UserPermissions.fromMap(
        parse.toMap(map['permissions']),
        fallbackRole: role,
      ),
      photoUrl: map['photo_url']?.toString(),
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  factory AppUserProfile.fromFirestore(
    String id,
    Map<String, dynamic> map,
  ) {
    final role = UserRoleX.fromValue(map['role']?.toString());
    final orgId = (map['orgId'] ?? map['org_id'] ?? '').toString();
    return AppUserProfile(
      uid: id,
      orgId: orgId,
      email: (map['email'] ?? '').toString(),
      role: role,
      isActive: parse.toBool(map['isActive'] ?? map['is_active']) ?? true,
      settings: UserSettings.fromFirestoreMap(
        parse.toMap(map['settings']),
      ),
      workRuleSettings: WorkRuleSettings.fromMap(
        parse.toMap(map['workRuleSettings'] ?? map['work_rule_settings']),
      ),
      permissions: UserPermissions.fromMap(
        parse.toMap(map['permissions']),
        fallbackRole: role,
      ),
      photoUrl: (map['photoUrl'] ?? map['photo_url'])?.toString(),
      createdAt:
          FirestoreDateParser.readDate(map['createdAt'] ?? map['created_at']),
      updatedAt:
          FirestoreDateParser.readDate(map['updatedAt'] ?? map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'email': email,
      'role': role.value,
      'isActive': isActive,
      'settings': settings.toFirestoreMap(),
      'workRuleSettings': workRuleSettings.toFirestoreMap(),
      'permissions': effectivePermissions.toFirestoreMap(),
      'photoUrl': photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'org_id': orgId,
      'email': email,
      'role': role.value,
      'is_active': isActive,
      'settings': settings.toMap(),
      'work_rule_settings': workRuleSettings.toMap(),
      'permissions': effectivePermissions.toMap(),
      'photo_url': photoUrl,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  AppUserProfile copyWith({
    String? uid,
    String? orgId,
    String? email,
    UserRole? role,
    bool? isActive,
    UserSettings? settings,
    WorkRuleSettings? workRuleSettings,
    UserPermissions? permissions,
    String? photoUrl,
    bool clearPhotoUrl = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppUserProfile(
      uid: uid ?? this.uid,
      orgId: orgId ?? this.orgId,
      email: email ?? this.email,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      settings: settings ?? this.settings,
      workRuleSettings: workRuleSettings ?? this.workRuleSettings,
      permissions: permissions ?? this.permissions,
      photoUrl: clearPhotoUrl ? null : (photoUrl ?? this.photoUrl),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
