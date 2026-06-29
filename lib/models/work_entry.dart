// lib/models/work_entry.dart

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_num_parser.dart' as parse;

/// Freigabe-Status eines Zeiteintrags (AllTec-Zeitwirtschafts-Workflow, M2).
///
/// **Default ist [approved]** — Alt-Einträge ohne `status`-Feld und die heutige
/// Direkterfassung bleiben gültig und zählen voll (abwärtskompatibel). Die
/// Zustände `draft`/`submitted` werden erst von den neuen Workflows gesetzt
/// (Stempel-Ausgang → `submitted`, Klärungs-Markierung → `draft`); ein Manager
/// genehmigt (`approved`) oder lehnt ab (`rejected`).
enum WorkEntryStatus {
  draft,
  submitted,
  approved,
  rejected;

  /// snake_case-Wert für beide Serialisierungen (≠ Dart-Name garantiert stabil).
  String get value => switch (this) {
        WorkEntryStatus.draft => 'draft',
        WorkEntryStatus.submitted => 'submitted',
        WorkEntryStatus.approved => 'approved',
        WorkEntryStatus.rejected => 'rejected',
      };

  /// Deutsches UI-Label.
  String get label => switch (this) {
        WorkEntryStatus.draft => 'Entwurf',
        WorkEntryStatus.submitted => 'Eingereicht',
        WorkEntryStatus.approved => 'Genehmigt',
        WorkEntryStatus.rejected => 'Abgelehnt',
      };

  /// Tolerant: unbekannter/leerer Wert fällt still auf [approved] (Default-Branch
  /// wirft nie — CLAUDE.md Enum-Regel).
  static WorkEntryStatus fromValue(Object? raw) {
    final value = (raw ?? '').toString().trim();
    for (final status in WorkEntryStatus.values) {
      if (status.value == value) {
        return status;
      }
    }
    return WorkEntryStatus.approved;
  }
}

class WorkEntry {
  final String? id;
  final String orgId;
  final String userId;
  final DateTime date;
  final DateTime startTime;
  final DateTime endTime;
  final double breakMinutes;
  final String? siteId;
  final String? siteName;
  final String? sourceShiftId;
  final String? correctionReason;
  final String? correctedByUid;
  final DateTime? correctedAt;
  final String? note;
  final String? category;

  /// Freigabe-Status (Zeitwirtschafts-Workflow, M2). Default [WorkEntryStatus.approved].
  final WorkEntryStatus status;

  /// Manager, der genehmigt/abgelehnt hat (null solange offen).
  final String? approvedByUid;

  /// Zeitpunkt der Genehmigung/Ablehnung.
  final DateTime? approvedAt;

  /// Verknüpfte Stempel-Session ([ClockEntry], M3) — gesetzt, wenn dieser Eintrag
  /// beim Ausstempeln erzeugt wurde (Duplikat-Vermeidung).
  final String? sourceClockEntryId;

  /// Letzte Aenderung. Server-autoritativ (serverTimestamp) in Firestore; lokal
  /// beim Speichern auf die Geraetezeit gesetzt. Dient als Last-Write-Wins-
  /// Tie-Breaker beim Hybrid-Merge, damit eine lokal neuere Version nicht von
  /// einem aelteren Server-Snapshot ueberschrieben wird.
  final DateTime? updatedAt;

  WorkEntry({
    this.id,
    this.orgId = '',
    this.userId = '',
    required DateTime date,
    required DateTime startTime,
    required DateTime endTime,
    double breakMinutes = 0,
    this.siteId,
    this.siteName,
    this.sourceShiftId,
    this.correctionReason,
    this.correctedByUid,
    this.correctedAt,
    this.note,
    this.category,
    this.status = WorkEntryStatus.approved,
    this.approvedByUid,
    this.approvedAt,
    this.sourceClockEntryId,
    this.updatedAt,
  })  : date = normalizeDate(date),
        startTime = normalizeDateTime(startTime),
        endTime = normalizeDateTime(endTime),
        breakMinutes = breakMinutes < 0 ? 0 : breakMinutes;

  static DateTime normalizeDate(DateTime value) {
    final localValue = normalizeDateTime(value);
    // Day-only values are normalized to local noon to avoid timezone drift
    // when they are serialized through Firestore.
    return DateTime(localValue.year, localValue.month, localValue.day, 12);
  }

  static DateTime normalizeDateTime(DateTime value) {
    return value.isUtc ? value.toLocal() : value;
  }

  static DateTime _parseStoredDate(dynamic rawValue) {
    final raw = (rawValue ?? '').toString().trim();
    if (raw.isEmpty) {
      throw const FormatException('WorkEntry date is missing or empty');
    }

    final parts = raw.split('-');
    if (parts.length == 3 && !raw.contains('T')) {
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);

      if (year != null && month != null && day != null) {
        return DateTime(year, month, day, 12);
      }
    }

    return normalizeDate(DateTime.parse(raw));
  }

  static String _formatStoredDate(DateTime value) {
    final normalized = normalizeDate(value);
    final year = normalized.year.toString().padLeft(4, '0');
    final month = normalized.month.toString().padLeft(2, '0');
    final day = normalized.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Gearbeitete Stunden (abzüglich Pause)
  double get workedHours {
    final diff = endTime.difference(startTime).inMinutes - breakMinutes;
    return math.max<double>(0, diff.toDouble()) / 60.0;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'date': _formatStoredDate(date),
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'break_minutes': breakMinutes,
      'site_id': siteId,
      'site_name': siteName,
      'source_shift_id': sourceShiftId,
      'correction_reason': correctionReason,
      'corrected_by_uid': correctedByUid,
      'corrected_at': correctedAt?.toIso8601String(),
      'note': note,
      'category': category,
      'status': status.value,
      'approved_by_uid': approvedByUid,
      'approved_at': approvedAt?.toIso8601String(),
      'source_clock_entry_id': sourceClockEntryId,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory WorkEntry.fromMap(Map<String, dynamic> map) {
    return WorkEntry(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      date: _parseStoredDate(map['date']),
      startTime: normalizeDateTime(DateTime.parse(map['start_time'])),
      endTime: normalizeDateTime(DateTime.parse(map['end_time'])),
      breakMinutes: parse.toDouble(map['break_minutes']) ?? 0,
      siteId: map['site_id'] as String?,
      siteName: map['site_name'] as String?,
      sourceShiftId: map['source_shift_id'] as String?,
      correctionReason: map['correction_reason'] as String?,
      correctedByUid: map['corrected_by_uid'] as String?,
      correctedAt: _parseNullableFirestoreDate(map['corrected_at']),
      note: map['note'],
      category: map['category'],
      status: WorkEntryStatus.fromValue(map['status']),
      approvedByUid: map['approved_by_uid'] as String?,
      approvedAt: _parseNullableFirestoreDate(map['approved_at']),
      sourceClockEntryId: map['source_clock_entry_id'] as String?,
      updatedAt: _parseNullableFirestoreDate(map['updated_at']),
    );
  }

  factory WorkEntry.fromFirestore(
    String id,
    Map<String, dynamic> map,
  ) {
    return WorkEntry(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      date: _parseFirestoreDate(map['date']),
      startTime: _parseFirestoreDate(map['startTime']),
      endTime: _parseFirestoreDate(map['endTime']),
      breakMinutes: parse.toDouble(map['breakMinutes']) ?? 0,
      siteId: map['siteId'] as String?,
      siteName: map['siteName'] as String?,
      sourceShiftId: map['sourceShiftId'] as String?,
      correctionReason: map['correctionReason'] as String?,
      correctedByUid: map['correctedByUid'] as String?,
      correctedAt: _parseNullableFirestoreDate(map['correctedAt']),
      note: map['note'] as String?,
      category: map['category'] as String?,
      status: WorkEntryStatus.fromValue(map['status']),
      approvedByUid: map['approvedByUid'] as String?,
      approvedAt: _parseNullableFirestoreDate(map['approvedAt']),
      sourceClockEntryId: map['sourceClockEntryId'] as String?,
      updatedAt: _parseNullableFirestoreDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'date': Timestamp.fromDate(normalizeDate(date)),
      'startTime': Timestamp.fromDate(normalizeDateTime(startTime)),
      'endTime': Timestamp.fromDate(normalizeDateTime(endTime)),
      'breakMinutes': breakMinutes,
      'siteId': siteId,
      'siteName': siteName,
      'sourceShiftId': sourceShiftId,
      'correctionReason': correctionReason,
      'correctedByUid': correctedByUid,
      'correctedAt':
          correctedAt == null ? null : Timestamp.fromDate(correctedAt!),
      'note': note,
      'category': category,
      'status': status.value,
      'approvedByUid': approvedByUid,
      'approvedAt': approvedAt == null ? null : Timestamp.fromDate(approvedAt!),
      'sourceClockEntryId': sourceClockEntryId,
      'workedHours': workedHours,
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static DateTime _parseFirestoreDate(dynamic rawValue) {
    if (rawValue is Timestamp) {
      return normalizeDateTime(rawValue.toDate());
    }
    if (rawValue is DateTime) {
      return normalizeDateTime(rawValue);
    }
    if (rawValue is String) {
      return normalizeDateTime(DateTime.parse(rawValue));
    }
    throw FormatException(
      'WorkEntry: unexpected date type ${rawValue.runtimeType}',
    );
  }

  static DateTime? _parseNullableFirestoreDate(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }
    return _parseFirestoreDate(rawValue);
  }

  WorkEntry copyWith({
    String? id,
    String? orgId,
    String? userId,
    DateTime? date,
    DateTime? startTime,
    DateTime? endTime,
    double? breakMinutes,
    String? siteId,
    String? siteName,
    String? sourceShiftId,
    String? correctionReason,
    String? correctedByUid,
    DateTime? correctedAt,
    bool clearSiteId = false,
    bool clearSiteName = false,
    bool clearSourceShiftId = false,
    bool clearCorrectionReason = false,
    bool clearCorrectedByUid = false,
    bool clearCorrectedAt = false,
    String? note,
    String? category,
    WorkEntryStatus? status,
    String? approvedByUid,
    DateTime? approvedAt,
    String? sourceClockEntryId,
    bool clearApprovedByUid = false,
    bool clearApprovedAt = false,
    bool clearSourceClockEntryId = false,
    DateTime? updatedAt,
  }) {
    return WorkEntry(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      breakMinutes: breakMinutes ?? this.breakMinutes,
      siteId: clearSiteId ? null : (siteId ?? this.siteId),
      siteName: clearSiteName ? null : (siteName ?? this.siteName),
      sourceShiftId:
          clearSourceShiftId ? null : (sourceShiftId ?? this.sourceShiftId),
      correctionReason: clearCorrectionReason
          ? null
          : (correctionReason ?? this.correctionReason),
      correctedByUid:
          clearCorrectedByUid ? null : (correctedByUid ?? this.correctedByUid),
      correctedAt: clearCorrectedAt ? null : (correctedAt ?? this.correctedAt),
      note: note ?? this.note,
      category: category ?? this.category,
      status: status ?? this.status,
      approvedByUid:
          clearApprovedByUid ? null : (approvedByUid ?? this.approvedByUid),
      approvedAt: clearApprovedAt ? null : (approvedAt ?? this.approvedAt),
      sourceClockEntryId: clearSourceClockEntryId
          ? null
          : (sourceClockEntryId ?? this.sourceClockEntryId),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
