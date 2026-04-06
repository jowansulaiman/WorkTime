import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

enum EmploymentType { fullTime, partTime, miniJob, trainee }

extension EmploymentTypeX on EmploymentType {
  String get value => switch (this) {
        EmploymentType.fullTime => 'full_time',
        EmploymentType.partTime => 'part_time',
        EmploymentType.miniJob => 'mini_job',
        EmploymentType.trainee => 'trainee',
      };

  String get label => switch (this) {
        EmploymentType.fullTime => 'Vollzeit',
        EmploymentType.partTime => 'Teilzeit',
        EmploymentType.miniJob => 'Minijob',
        EmploymentType.trainee => 'Ausbildung',
      };

  static EmploymentType fromValue(String? value) => switch (value) {
        'part_time' => EmploymentType.partTime,
        'mini_job' => EmploymentType.miniJob,
        'trainee' => EmploymentType.trainee,
        _ => EmploymentType.fullTime,
      };
}

class EmploymentContract {
  const EmploymentContract({
    this.id,
    required this.orgId,
    required this.userId,
    this.label,
    this.type = EmploymentType.fullTime,
    required this.validFrom,
    this.validUntil,
    this.weeklyHours = 40,
    this.dailyHours = 8,
    this.hourlyRate = 0,
    this.currency = 'EUR',
    this.vacationDays = 30,
    this.maxDailyMinutes,
    this.monthlyIncomeLimitCents,
    this.isMinor = false,
    this.isPregnant = false,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String userId;
  final String? label;
  final EmploymentType type;
  final DateTime validFrom;
  final DateTime? validUntil;
  final double weeklyHours;
  final double dailyHours;
  final double hourlyRate;
  final String currency;
  final int vacationDays;
  final int? maxDailyMinutes;
  final int? monthlyIncomeLimitCents;
  final bool isMinor;
  final bool isPregnant;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool isActiveOn(DateTime date) {
    if (date
        .isBefore(DateTime(validFrom.year, validFrom.month, validFrom.day))) {
      return false;
    }
    if (validUntil == null) {
      return true;
    }
    final inclusiveEnd = DateTime(
        validUntil!.year, validUntil!.month, validUntil!.day, 23, 59, 59);
    return !date.isAfter(inclusiveEnd);
  }

  factory EmploymentContract.fromFirestore(
      String id, Map<String, dynamic> map) {
    return EmploymentContract(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      label: map['label'] as String?,
      type: EmploymentTypeX.fromValue(map['type']?.toString()),
      validFrom:
          FirestoreDateParser.readDate(map['validFrom']) ?? DateTime.now(),
      validUntil: FirestoreDateParser.readDate(map['validUntil']),
      weeklyHours: parse.toDouble(map['weeklyHours']) ?? 40,
      dailyHours: parse.toDouble(map['dailyHours']) ?? 8,
      hourlyRate: parse.toDouble(map['hourlyRate']) ?? 0,
      currency: (map['currency'] ?? 'EUR').toString(),
      vacationDays: parse.toInt(map['vacationDays']) ?? 30,
      maxDailyMinutes: parse.toInt(map['maxDailyMinutes']),
      monthlyIncomeLimitCents:
          parse.toInt(map['monthlyIncomeLimitCents']),
      isMinor: parse.toBool(map['isMinor']) ?? false,
      isPregnant: parse.toBool(map['isPregnant']) ?? false,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory EmploymentContract.fromMap(Map<String, dynamic> map) {
    return EmploymentContract(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      label: map['label'] as String?,
      type: EmploymentTypeX.fromValue(map['type']?.toString()),
      validFrom: FirestoreDateParser.readLocalDate(map['valid_from']) ??
          DateTime.now(),
      validUntil: FirestoreDateParser.readLocalDate(map['valid_until']),
      weeklyHours: parse.toDouble(map['weekly_hours']) ?? 40,
      dailyHours: parse.toDouble(map['daily_hours']) ?? 8,
      hourlyRate: parse.toDouble(map['hourly_rate']) ?? 0,
      currency: (map['currency'] ?? 'EUR').toString(),
      vacationDays: parse.toInt(map['vacation_days']) ?? 30,
      maxDailyMinutes: parse.toInt(map['max_daily_minutes']),
      monthlyIncomeLimitCents:
          parse.toInt(map['monthly_income_limit_cents']),
      isMinor: parse.toBool(map['is_minor']) ?? false,
      isPregnant: parse.toBool(map['is_pregnant']) ?? false,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'label': label,
      'type': type.value,
      'validFrom': Timestamp.fromDate(
        DateTime(validFrom.year, validFrom.month, validFrom.day),
      ),
      'validUntil': validUntil == null
          ? null
          : Timestamp.fromDate(
              DateTime(validUntil!.year, validUntil!.month, validUntil!.day),
            ),
      'weeklyHours': weeklyHours,
      'dailyHours': dailyHours,
      'hourlyRate': hourlyRate,
      'currency': currency,
      'vacationDays': vacationDays,
      'maxDailyMinutes': maxDailyMinutes,
      'monthlyIncomeLimitCents': monthlyIncomeLimitCents,
      'isMinor': isMinor,
      'isPregnant': isPregnant,
      'createdByUid': createdByUid,
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'label': label,
      'type': type.value,
      'valid_from': validFrom.toIso8601String(),
      'valid_until': validUntil?.toIso8601String(),
      'weekly_hours': weeklyHours,
      'daily_hours': dailyHours,
      'hourly_rate': hourlyRate,
      'currency': currency,
      'vacation_days': vacationDays,
      'max_daily_minutes': maxDailyMinutes,
      'monthly_income_limit_cents': monthlyIncomeLimitCents,
      'is_minor': isMinor,
      'is_pregnant': isPregnant,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  EmploymentContract copyWith({
    String? id,
    String? orgId,
    String? userId,
    String? label,
    EmploymentType? type,
    DateTime? validFrom,
    DateTime? validUntil,
    bool clearValidUntil = false,
    double? weeklyHours,
    double? dailyHours,
    double? hourlyRate,
    String? currency,
    int? vacationDays,
    int? maxDailyMinutes,
    int? monthlyIncomeLimitCents,
    bool clearMaxDailyMinutes = false,
    bool clearMonthlyIncomeLimitCents = false,
    bool? isMinor,
    bool? isPregnant,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmploymentContract(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      label: label ?? this.label,
      type: type ?? this.type,
      validFrom: validFrom ?? this.validFrom,
      validUntil: clearValidUntil ? null : (validUntil ?? this.validUntil),
      weeklyHours: weeklyHours ?? this.weeklyHours,
      dailyHours: dailyHours ?? this.dailyHours,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      currency: currency ?? this.currency,
      vacationDays: vacationDays ?? this.vacationDays,
      maxDailyMinutes: clearMaxDailyMinutes
          ? null
          : (maxDailyMinutes ?? this.maxDailyMinutes),
      monthlyIncomeLimitCents: clearMonthlyIncomeLimitCents
          ? null
          : (monthlyIncomeLimitCents ?? this.monthlyIncomeLimitCents),
      isMinor: isMinor ?? this.isMinor,
      isPregnant: isPregnant ?? this.isPregnant,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
