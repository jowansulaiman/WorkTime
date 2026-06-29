import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';

enum AbsenceType {
  vacation,
  sickness,
  unavailable,
  // M-U: feinere Abwesenheitsarten (siehe abwesenheit_matrix.dart §5.4a).
  specialLeave,
  unpaidLeave,
  timeOff,
  parentalLeave,
  maternity,
  vocationalSchool,
  volunteering,
  shortTimeWork,
  childSick,
}

enum AbsenceStatus { pending, approved, rejected }

/// Halbtags-Lage (für `halfDay`-Anträge).
enum HalfDayPeriod { vormittags, nachmittags }

extension HalfDayPeriodX on HalfDayPeriod {
  String get value => switch (this) {
        HalfDayPeriod.vormittags => 'vormittags',
        HalfDayPeriod.nachmittags => 'nachmittags',
      };

  String get label => switch (this) {
        HalfDayPeriod.vormittags => 'Vormittags',
        HalfDayPeriod.nachmittags => 'Nachmittags',
      };

  static HalfDayPeriod? fromValue(String? value) => switch (value) {
        'vormittags' => HalfDayPeriod.vormittags,
        'nachmittags' => HalfDayPeriod.nachmittags,
        _ => null,
      };
}

extension AbsenceTypeX on AbsenceType {
  String get value => switch (this) {
        AbsenceType.vacation => 'vacation',
        AbsenceType.sickness => 'sickness',
        AbsenceType.unavailable => 'unavailable',
        AbsenceType.specialLeave => 'special_leave',
        AbsenceType.unpaidLeave => 'unpaid_leave',
        AbsenceType.timeOff => 'time_off',
        AbsenceType.parentalLeave => 'parental_leave',
        AbsenceType.maternity => 'maternity',
        AbsenceType.vocationalSchool => 'vocational_school',
        AbsenceType.volunteering => 'volunteering',
        AbsenceType.shortTimeWork => 'short_time_work',
        AbsenceType.childSick => 'child_sick',
      };

  String get label => switch (this) {
        AbsenceType.vacation => 'Urlaub',
        AbsenceType.sickness => 'Krank',
        AbsenceType.unavailable => 'Nicht verfuegbar',
        AbsenceType.specialLeave => 'Sonderurlaub',
        AbsenceType.unpaidLeave => 'Unbezahlt',
        AbsenceType.timeOff => 'Zeitausgleich',
        AbsenceType.parentalLeave => 'Elternzeit',
        AbsenceType.maternity => 'Mutterschutz',
        AbsenceType.vocationalSchool => 'Berufsschule',
        AbsenceType.volunteering => 'Ehrenamt',
        AbsenceType.shortTimeWork => 'Kurzarbeit',
        AbsenceType.childSick => 'Kind krank',
      };

  static AbsenceType fromValue(String? value) => switch (value) {
        'sickness' => AbsenceType.sickness,
        'unavailable' => AbsenceType.unavailable,
        'special_leave' => AbsenceType.specialLeave,
        'unpaid_leave' => AbsenceType.unpaidLeave,
        'time_off' => AbsenceType.timeOff,
        'parental_leave' => AbsenceType.parentalLeave,
        'maternity' => AbsenceType.maternity,
        'vocational_school' => AbsenceType.vocationalSchool,
        'volunteering' => AbsenceType.volunteering,
        'short_time_work' => AbsenceType.shortTimeWork,
        'child_sick' => AbsenceType.childSick,
        _ => AbsenceType.vacation,
      };
}

extension AbsenceStatusX on AbsenceStatus {
  String get value => switch (this) {
        AbsenceStatus.pending => 'pending',
        AbsenceStatus.approved => 'approved',
        AbsenceStatus.rejected => 'rejected',
      };

  String get label => switch (this) {
        AbsenceStatus.pending => 'Offen',
        AbsenceStatus.approved => 'Genehmigt',
        AbsenceStatus.rejected => 'Abgelehnt',
      };

  static AbsenceStatus fromValue(String? value) => switch (value) {
        'approved' => AbsenceStatus.approved,
        'rejected' => AbsenceStatus.rejected,
        _ => AbsenceStatus.pending,
      };
}

class AbsenceRequest {
  AbsenceRequest({
    this.id,
    required this.orgId,
    required this.userId,
    required this.employeeName,
    required DateTime startDate,
    required DateTime endDate,
    required this.type,
    this.note,
    this.status = AbsenceStatus.pending,
    this.reviewedByUid,
    this.halfDay = false,
    this.halfDayPeriod,
    this.hours,
    this.vertreterUserIds = const [],
    this.eauAttached = false,
    this.createdAt,
    this.updatedAt,
  })  : startDate = _normalizeCalendarDate(startDate),
        endDate = _normalizeCalendarDate(endDate);

  final String? id;
  final String orgId;
  final String userId;
  final String employeeName;
  final DateTime startDate;
  final DateTime endDate;
  final AbsenceType type;
  final String? note;
  final AbsenceStatus status;
  final String? reviewedByUid;

  /// Halbtägige Abwesenheit (zählt 0,5 statt 1,0 je Tag).
  final bool halfDay;

  /// Lage des halben Tags (nur bei [halfDay]).
  final HalfDayPeriod? halfDayPeriod;

  /// Stunden für Zeitausgleich ([AbsenceType.timeOff]) – gegen das Stundenkonto.
  final double? hours;

  /// Vertretende Mitarbeiter (Self-Exclusion in der UI).
  final List<String> vertreterUserIds;

  /// Elektronische Arbeitsunfähigkeitsbescheinigung beigefügt (nur Flag).
  final bool eauAttached;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Inklusive Kalendertage des Zeitraums (grobe Spanne; die urlaubswirksamen
  /// **Werktage** rechnet `urlaub_calculator` mit Sollzeit + Feiertagen).
  int get kalenderTage => endDate.difference(startDate).inDays + 1;

  /// Stunden des Antrags (für [AbsenceType.timeOff]/Zeitausgleich gegen das
  /// Stundenkonto); 0, wenn kein Stundenwert hinterlegt ist.
  double get durationHours => hours ?? 0;

  factory AbsenceRequest.fromMap(Map<String, dynamic> map) {
    return AbsenceRequest(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      employeeName: (map['employee_name'] ?? '').toString(),
      startDate: FirestoreDateParser.readLocalDate(map['start_date']) ??
          DateTime.now(),
      endDate:
          FirestoreDateParser.readLocalDate(map['end_date']) ?? DateTime.now(),
      type: AbsenceTypeX.fromValue(map['type']?.toString()),
      note: map['note'] as String?,
      status: AbsenceStatusX.fromValue(map['status']?.toString()),
      reviewedByUid: map['reviewed_by_uid'] as String?,
      halfDay: (map['half_day'] as bool?) ?? false,
      halfDayPeriod: HalfDayPeriodX.fromValue(map['half_day_period']?.toString()),
      hours: (map['hours'] as num?)?.toDouble(),
      vertreterUserIds:
          (map['vertreter_user_ids'] as List?)?.cast<String>() ?? const [],
      eauAttached: (map['eau_attached'] as bool?) ?? false,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  factory AbsenceRequest.fromFirestore(String id, Map<String, dynamic> map) {
    return AbsenceRequest(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      employeeName: (map['employeeName'] ?? '').toString(),
      startDate:
          FirestoreDateParser.readDate(map['startDate']) ?? DateTime.now(),
      endDate: FirestoreDateParser.readDate(map['endDate']) ?? DateTime.now(),
      type: AbsenceTypeX.fromValue(map['type']?.toString()),
      note: map['note'] as String?,
      status: AbsenceStatusX.fromValue(map['status']?.toString()),
      reviewedByUid: map['reviewedByUid'] as String?,
      halfDay: (map['halfDay'] as bool?) ?? false,
      halfDayPeriod: HalfDayPeriodX.fromValue(map['halfDayPeriod']?.toString()),
      hours: (map['hours'] as num?)?.toDouble(),
      vertreterUserIds:
          (map['vertreterUserIds'] as List?)?.cast<String>() ?? const [],
      eauAttached: (map['eauAttached'] as bool?) ?? false,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'employeeName': employeeName,
      'startDate': Timestamp.fromDate(_normalizeCalendarDate(startDate)),
      'endDate': Timestamp.fromDate(_normalizeCalendarDate(endDate)),
      'type': type.value,
      'note': note,
      'status': status.value,
      'reviewedByUid': reviewedByUid,
      'halfDay': halfDay,
      'halfDayPeriod': halfDayPeriod?.value,
      'hours': hours,
      'vertreterUserIds': vertreterUserIds,
      'eauAttached': eauAttached,
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'employee_name': employeeName,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'type': type.value,
      'note': note,
      'status': status.value,
      'reviewed_by_uid': reviewedByUid,
      'half_day': halfDay,
      'half_day_period': halfDayPeriod?.value,
      'hours': hours,
      'vertreter_user_ids': vertreterUserIds,
      'eau_attached': eauAttached,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  bool overlaps(DateTime rangeStart, DateTime rangeEnd) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final endExclusive = DateTime(
      endDate.year,
      endDate.month,
      endDate.day + 1,
    );
    return start.isBefore(rangeEnd) && endExclusive.isAfter(rangeStart);
  }

  AbsenceRequest copyWith({
    String? id,
    String? orgId,
    String? userId,
    String? employeeName,
    DateTime? startDate,
    DateTime? endDate,
    AbsenceType? type,
    String? note,
    bool clearNote = false,
    AbsenceStatus? status,
    String? reviewedByUid,
    bool? halfDay,
    HalfDayPeriod? halfDayPeriod,
    bool clearHalfDayPeriod = false,
    double? hours,
    bool clearHours = false,
    List<String>? vertreterUserIds,
    bool? eauAttached,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AbsenceRequest(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      employeeName: employeeName ?? this.employeeName,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      type: type ?? this.type,
      note: clearNote ? null : (note ?? this.note),
      status: status ?? this.status,
      reviewedByUid: reviewedByUid ?? this.reviewedByUid,
      halfDay: halfDay ?? this.halfDay,
      halfDayPeriod:
          clearHalfDayPeriod ? null : (halfDayPeriod ?? this.halfDayPeriod),
      hours: clearHours ? null : (hours ?? this.hours),
      vertreterUserIds: vertreterUserIds ?? this.vertreterUserIds,
      eauAttached: eauAttached ?? this.eauAttached,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime _normalizeCalendarDate(DateTime value) {
    return DateTime(value.year, value.month, value.day, 12);
  }
}
