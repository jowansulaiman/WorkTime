import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;
import 'employment_contract.dart';

class BreakRule {
  const BreakRule({
    required this.afterMinutes,
    required this.requiredBreakMinutes,
  });

  final int afterMinutes;
  final int requiredBreakMinutes;

  factory BreakRule.fromMap(Map<String, dynamic> map) {
    return BreakRule(
      afterMinutes: parse.toInt(map['afterMinutes']) ?? 0,
      requiredBreakMinutes: parse.toInt(map['requiredBreakMinutes']) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'afterMinutes': afterMinutes,
      'requiredBreakMinutes': requiredBreakMinutes,
    };
  }
}

class ComplianceRuleSet {
  const ComplianceRuleSet({
    this.id,
    required this.orgId,
    required this.name,
    this.siteId,
    this.employmentType,
    this.minRestMinutes = 660,
    this.breakRules = const [
      BreakRule(afterMinutes: 360, requiredBreakMinutes: 30),
      BreakRule(afterMinutes: 540, requiredBreakMinutes: 45),
    ],
    this.maxPlannedMinutesPerDay = 600,
    this.minijobMonthlyLimitCents = 60300,
    this.nightWindowStartMinutes = 23 * 60,
    this.nightWindowEndMinutes = 6 * 60,
    this.warnForwardRotation = true,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String name;
  final String? siteId;
  final EmploymentType? employmentType;
  final int minRestMinutes;
  final List<BreakRule> breakRules;
  final int maxPlannedMinutesPerDay;
  final int minijobMonthlyLimitCents;
  final int nightWindowStartMinutes;
  final int nightWindowEndMinutes;
  final bool warnForwardRotation;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ComplianceRuleSet.defaultRetail(String orgId,
      {String? createdByUid}) {
    return ComplianceRuleSet(
      orgId: orgId,
      name: 'DE Einzelhandel Standard',
      createdByUid: createdByUid,
    );
  }

  factory ComplianceRuleSet.fromFirestore(String id, Map<String, dynamic> map) {
    return ComplianceRuleSet(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      siteId: map['siteId'] as String?,
      employmentType: map['employmentType'] == null
          ? null
          : EmploymentTypeX.fromValue(map['employmentType']?.toString()),
      minRestMinutes: parse.toInt(map['minRestMinutes']) ?? 660,
      breakRules: ((map['breakRules'] as List<dynamic>?) ?? const [])
          .map((item) => BreakRule.fromMap(
                (item as Map<Object?, Object?>).cast<String, dynamic>(),
              ))
          .toList(growable: false),
      maxPlannedMinutesPerDay:
          parse.toInt(map['maxPlannedMinutesPerDay']) ?? 600,
      minijobMonthlyLimitCents:
          parse.toInt(map['minijobMonthlyLimitCents']) ?? 60300,
      nightWindowStartMinutes:
          parse.toInt(map['nightWindowStartMinutes']) ?? (23 * 60),
      nightWindowEndMinutes:
          parse.toInt(map['nightWindowEndMinutes']) ?? (6 * 60),
      warnForwardRotation: parse.toBool(map['warnForwardRotation']) ?? true,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory ComplianceRuleSet.fromMap(Map<String, dynamic> map) {
    return ComplianceRuleSet(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      siteId: map['site_id'] as String?,
      employmentType: map['employment_type'] == null
          ? null
          : EmploymentTypeX.fromValue(map['employment_type']?.toString()),
      minRestMinutes: parse.toInt(map['min_rest_minutes']) ?? 660,
      breakRules: ((map['break_rules'] as List<dynamic>?) ?? const [])
          .map((item) => BreakRule.fromMap(
                (item as Map<Object?, Object?>).cast<String, dynamic>(),
              ))
          .toList(growable: false),
      maxPlannedMinutesPerDay:
          parse.toInt(map['max_planned_minutes_per_day']) ?? 600,
      minijobMonthlyLimitCents:
          parse.toInt(map['minijob_monthly_limit_cents']) ?? 60300,
      nightWindowStartMinutes:
          parse.toInt(map['night_window_start_minutes']) ?? (23 * 60),
      nightWindowEndMinutes:
          parse.toInt(map['night_window_end_minutes']) ?? (6 * 60),
      warnForwardRotation: parse.toBool(map['warn_forward_rotation']) ?? true,
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
      'siteId': siteId,
      'employmentType': employmentType?.value,
      'minRestMinutes': minRestMinutes,
      'breakRules':
          breakRules.map((item) => item.toMap()).toList(growable: false),
      'maxPlannedMinutesPerDay': maxPlannedMinutesPerDay,
      'minijobMonthlyLimitCents': minijobMonthlyLimitCents,
      'nightWindowStartMinutes': nightWindowStartMinutes,
      'nightWindowEndMinutes': nightWindowEndMinutes,
      'warnForwardRotation': warnForwardRotation,
      'createdByUid': createdByUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'name': name,
      'site_id': siteId,
      'employment_type': employmentType?.value,
      'min_rest_minutes': minRestMinutes,
      'break_rules':
          breakRules.map((item) => item.toMap()).toList(growable: false),
      'max_planned_minutes_per_day': maxPlannedMinutesPerDay,
      'minijob_monthly_limit_cents': minijobMonthlyLimitCents,
      'night_window_start_minutes': nightWindowStartMinutes,
      'night_window_end_minutes': nightWindowEndMinutes,
      'warn_forward_rotation': warnForwardRotation,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  ComplianceRuleSet copyWith({
    String? id,
    String? orgId,
    String? name,
    String? siteId,
    bool clearSiteId = false,
    EmploymentType? employmentType,
    bool clearEmploymentType = false,
    int? minRestMinutes,
    List<BreakRule>? breakRules,
    int? maxPlannedMinutesPerDay,
    int? minijobMonthlyLimitCents,
    int? nightWindowStartMinutes,
    int? nightWindowEndMinutes,
    bool? warnForwardRotation,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ComplianceRuleSet(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      name: name ?? this.name,
      siteId: clearSiteId ? null : (siteId ?? this.siteId),
      employmentType:
          clearEmploymentType ? null : (employmentType ?? this.employmentType),
      minRestMinutes: minRestMinutes ?? this.minRestMinutes,
      breakRules: breakRules ?? this.breakRules,
      maxPlannedMinutesPerDay:
          maxPlannedMinutesPerDay ?? this.maxPlannedMinutesPerDay,
      minijobMonthlyLimitCents:
          minijobMonthlyLimitCents ?? this.minijobMonthlyLimitCents,
      nightWindowStartMinutes:
          nightWindowStartMinutes ?? this.nightWindowStartMinutes,
      nightWindowEndMinutes:
          nightWindowEndMinutes ?? this.nightWindowEndMinutes,
      warnForwardRotation: warnForwardRotation ?? this.warnForwardRotation,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
