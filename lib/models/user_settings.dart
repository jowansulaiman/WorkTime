// lib/models/user_settings.dart

import '../core/firestore_num_parser.dart' as parse;

class UserSettings {
  final String name;
  final double hourlyRate;
  final double dailyHours;
  final String currency;
  final int vacationDays;
  final int autoBreakAfterMinutes;

  const UserSettings({
    this.name = '',
    this.hourlyRate = 0.0,
    this.dailyHours = 8.0,
    this.currency = 'EUR',
    this.vacationDays = 30,
    this.autoBreakAfterMinutes = 360,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'hourly_rate': hourlyRate,
        'daily_hours': dailyHours,
        'currency': currency,
        'vacation_days': vacationDays,
        'auto_break_after_minutes': autoBreakAfterMinutes,
      };

  factory UserSettings.fromMap(Map<String, dynamic> map) => UserSettings(
        name: map['name'] ?? '',
        hourlyRate: parse.toDouble(map['hourly_rate']) ?? 0.0,
        dailyHours: parse.toDouble(map['daily_hours']) ?? 8.0,
        currency: map['currency'] ?? 'EUR',
        vacationDays: parse.toInt(map['vacation_days']) ?? 30,
        autoBreakAfterMinutes:
            parse.toInt(map['auto_break_after_minutes']) ?? 360,
      );

  factory UserSettings.fromFirestoreMap(Map<String, dynamic> map) =>
      UserSettings(
        name: (map['name'] ?? '').toString(),
        hourlyRate:
            parse.toDouble(map['hourlyRate'] ?? map['hourly_rate']) ?? 0.0,
        dailyHours:
            parse.toDouble(map['dailyHours'] ?? map['daily_hours']) ?? 8.0,
        currency: (map['currency'] ?? 'EUR').toString(),
        vacationDays:
            parse.toInt(map['vacationDays'] ?? map['vacation_days']) ?? 30,
        autoBreakAfterMinutes: parse.toInt(
              map['autoBreakAfterMinutes'] ?? map['auto_break_after_minutes'],
            ) ??
            360,
      );

  Map<String, dynamic> toFirestoreMap() => {
        'name': name,
        'hourlyRate': hourlyRate,
        'dailyHours': dailyHours,
        'currency': currency,
        'vacationDays': vacationDays,
        'autoBreakAfterMinutes': autoBreakAfterMinutes,
      };

  UserSettings copyWith({
    String? name,
    double? hourlyRate,
    double? dailyHours,
    String? currency,
    int? vacationDays,
    int? autoBreakAfterMinutes,
  }) =>
      UserSettings(
        name: name ?? this.name,
        hourlyRate: hourlyRate ?? this.hourlyRate,
        dailyHours: dailyHours ?? this.dailyHours,
        currency: currency ?? this.currency,
        vacationDays: vacationDays ?? this.vacationDays,
        autoBreakAfterMinutes:
            autoBreakAfterMinutes ?? this.autoBreakAfterMinutes,
      );
}
