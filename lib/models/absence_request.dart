import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';

enum AbsenceType { vacation, sickness, unavailable }

enum AbsenceStatus { pending, approved, rejected }

extension AbsenceTypeX on AbsenceType {
  String get value => switch (this) {
        AbsenceType.vacation => 'vacation',
        AbsenceType.sickness => 'sickness',
        AbsenceType.unavailable => 'unavailable',
      };

  String get label => switch (this) {
        AbsenceType.vacation => 'Urlaub',
        AbsenceType.sickness => 'Krank',
        AbsenceType.unavailable => 'Nicht verfuegbar',
      };

  static AbsenceType fromValue(String? value) => switch (value) {
        'sickness' => AbsenceType.sickness,
        'unavailable' => AbsenceType.unavailable,
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
  final DateTime? createdAt;
  final DateTime? updatedAt;

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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime _normalizeCalendarDate(DateTime value) {
    return DateTime(value.year, value.month, value.day, 12);
  }
}
