import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

enum ShiftStatus { planned, confirmed, completed, cancelled }

enum RecurrencePattern { none, weekly, biWeekly, monthly }

extension ShiftStatusX on ShiftStatus {
  String get value => switch (this) {
        ShiftStatus.planned => 'planned',
        ShiftStatus.confirmed => 'confirmed',
        ShiftStatus.completed => 'completed',
        ShiftStatus.cancelled => 'cancelled',
      };

  String get label => switch (this) {
        ShiftStatus.planned => 'Geplant',
        ShiftStatus.confirmed => 'Bestätigt',
        ShiftStatus.completed => 'Erledigt',
        ShiftStatus.cancelled => 'Abgesagt',
      };

  static ShiftStatus fromValue(String? value) => switch (value) {
        'confirmed' => ShiftStatus.confirmed,
        'completed' => ShiftStatus.completed,
        'cancelled' => ShiftStatus.cancelled,
        _ => ShiftStatus.planned,
      };
}

extension RecurrencePatternX on RecurrencePattern {
  String get value => switch (this) {
        RecurrencePattern.none => 'none',
        RecurrencePattern.weekly => 'weekly',
        RecurrencePattern.biWeekly => 'bi_weekly',
        RecurrencePattern.monthly => 'monthly',
      };

  String get label => switch (this) {
        RecurrencePattern.none => 'Keine',
        RecurrencePattern.weekly => 'Woechentlich',
        RecurrencePattern.biWeekly => 'Alle 2 Wochen',
        RecurrencePattern.monthly => 'Monatlich',
      };

  static RecurrencePattern fromValue(String? value) => switch (value) {
        'weekly' => RecurrencePattern.weekly,
        'bi_weekly' => RecurrencePattern.biWeekly,
        'monthly' => RecurrencePattern.monthly,
        _ => RecurrencePattern.none,
      };
}

class Shift {
  Shift({
    this.id,
    required this.orgId,
    required this.userId,
    required this.employeeName,
    required this.title,
    required this.startTime,
    required this.endTime,
    double breakMinutes = 0,
    this.teamId,
    this.team,
    this.siteId,
    this.siteName,
    this.location,
    this.requiredQualificationIds = const [],
    this.notes,
    this.seriesId,
    this.recurrencePattern = RecurrencePattern.none,
    this.color,
    this.swapRequestedByUid,
    this.swapStatus,
    this.status = ShiftStatus.planned,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  }) : breakMinutes = breakMinutes < 0 ? 0 : breakMinutes;

  final String? id;
  final String orgId;
  final String userId;
  final String employeeName;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final double breakMinutes;
  final String? teamId;
  final String? team;
  final String? siteId;
  final String? siteName;
  final String? location;
  final List<String> requiredQualificationIds;
  final String? notes;
  final String? color;
  final String? swapRequestedByUid;
  final String? swapStatus;
  final String? seriesId;
  final RecurrencePattern recurrencePattern;
  final ShiftStatus status;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get workedHours =>
      (endTime.difference(startTime).inMinutes - breakMinutes) / 60;

  bool get isUnassigned => userId.trim().isEmpty;
  String? get effectiveSiteLabel =>
      siteName?.trim().isNotEmpty == true ? siteName : location;

  bool overlaps(Shift other) {
    if (isUnassigned || other.isUnassigned) {
      return false;
    }
    if (userId != other.userId) {
      return false;
    }
    return startTime.isBefore(other.endTime) &&
        endTime.isAfter(other.startTime);
  }

  factory Shift.fromMap(Map<String, dynamic> map) {
    return Shift(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      employeeName: (map['employee_name'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      startTime: FirestoreDateParser.readLocalDate(map['start_time']) ??
          DateTime.now(),
      endTime:
          FirestoreDateParser.readLocalDate(map['end_time']) ?? DateTime.now(),
      breakMinutes: parse.toDouble(map['break_minutes']) ?? 0,
      teamId: map['team_id'] as String?,
      team: map['team'] as String?,
      siteId: map['site_id'] as String?,
      siteName: map['site_name'] as String?,
      location: map['location'] as String?,
      requiredQualificationIds:
          ((map['required_qualification_ids'] as List<dynamic>?) ?? const [])
              .map((value) => value.toString())
              .toList(growable: false),
      notes: map['notes'] as String?,
      color: map['color'] as String?,
      swapRequestedByUid: map['swap_requested_by_uid'] as String?,
      swapStatus: map['swap_status'] as String?,
      seriesId: map['series_id'] as String?,
      recurrencePattern:
          RecurrencePatternX.fromValue(map['recurrence_pattern']?.toString()),
      status: ShiftStatusX.fromValue(map['status']?.toString()),
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  factory Shift.fromFirestore(String id, Map<String, dynamic> map) {
    return Shift(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      employeeName: (map['employeeName'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      startTime:
          FirestoreDateParser.readDate(map['startTime']) ?? DateTime.now(),
      endTime: FirestoreDateParser.readDate(map['endTime']) ?? DateTime.now(),
      breakMinutes: parse.toDouble(map['breakMinutes']) ?? 0,
      teamId: map['teamId'] as String?,
      team: map['team'] as String?,
      siteId: map['siteId'] as String?,
      siteName: map['siteName'] as String?,
      location: map['location'] as String?,
      requiredQualificationIds:
          ((map['requiredQualificationIds'] as List<dynamic>?) ?? const [])
              .map((value) => value.toString())
              .toList(growable: false),
      notes: map['notes'] as String?,
      color: map['color'] as String?,
      swapRequestedByUid: map['swapRequestedByUid'] as String?,
      swapStatus: map['swapStatus'] as String?,
      seriesId: map['seriesId'] as String?,
      recurrencePattern:
          RecurrencePatternX.fromValue(map['recurrencePattern']?.toString()),
      status: ShiftStatusX.fromValue(map['status']?.toString()),
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'employeeName': employeeName,
      'title': title,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'breakMinutes': breakMinutes,
      'teamId': teamId,
      'team': team,
      'siteId': siteId,
      'siteName': siteName,
      'location': location,
      'requiredQualificationIds': requiredQualificationIds,
      'notes': notes,
      'color': color,
      'swapRequestedByUid': swapRequestedByUid,
      'swapStatus': swapStatus,
      'seriesId': seriesId,
      'recurrencePattern': recurrencePattern.value,
      'status': status.value,
      'createdByUid': createdByUid,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'employee_name': employeeName,
      'title': title,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'break_minutes': breakMinutes,
      'team_id': teamId,
      'team': team,
      'site_id': siteId,
      'site_name': siteName,
      'location': location,
      'required_qualification_ids': requiredQualificationIds,
      'notes': notes,
      'color': color,
      'swap_requested_by_uid': swapRequestedByUid,
      'swap_status': swapStatus,
      'series_id': seriesId,
      'recurrence_pattern': recurrencePattern.value,
      'status': status.value,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Shift copyWith({
    String? id,
    String? orgId,
    String? userId,
    String? employeeName,
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    double? breakMinutes,
    String? teamId,
    String? team,
    String? siteId,
    String? siteName,
    String? location,
    List<String>? requiredQualificationIds,
    String? notes,
    String? color,
    String? swapRequestedByUid,
    String? swapStatus,
    bool clearTeamId = false,
    bool clearTeam = false,
    bool clearSiteId = false,
    bool clearSiteName = false,
    bool clearLocation = false,
    bool clearNotes = false,
    bool clearColor = false,
    bool clearSwap = false,
    String? seriesId,
    RecurrencePattern? recurrencePattern,
    ShiftStatus? status,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Shift(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      employeeName: employeeName ?? this.employeeName,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      breakMinutes: breakMinutes ?? this.breakMinutes,
      teamId: clearTeamId ? null : (teamId ?? this.teamId),
      team: clearTeam ? null : (team ?? this.team),
      siteId: clearSiteId ? null : (siteId ?? this.siteId),
      siteName: clearSiteName ? null : (siteName ?? this.siteName),
      location: clearLocation ? null : (location ?? this.location),
      requiredQualificationIds:
          requiredQualificationIds ?? this.requiredQualificationIds,
      notes: clearNotes ? null : (notes ?? this.notes),
      color: clearColor ? null : (color ?? this.color),
      swapRequestedByUid:
          clearSwap ? null : (swapRequestedByUid ?? this.swapRequestedByUid),
      swapStatus: clearSwap ? null : (swapStatus ?? this.swapStatus),
      seriesId: seriesId ?? this.seriesId,
      recurrencePattern: recurrencePattern ?? this.recurrencePattern,
      status: status ?? this.status,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
