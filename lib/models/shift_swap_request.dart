import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';

/// Art des Tauschs.
/// - [exchange]: beide Schichten benannt → bei Bestätigung werden beide
///   `userId`/`employeeName` getauscht.
/// - [giveAway]: einseitig / Übernahme → `targetShiftId == null`. Nur die
///   Antragsteller-Schicht wandert zum Kollegen; es entsteht eine Gutschrift
///   ([SwapCredit]), die nächsten Monat eingelöst wird.
enum SwapKind { exchange, giveAway }

extension SwapKindX on SwapKind {
  String get value => switch (this) {
        SwapKind.exchange => 'exchange',
        SwapKind.giveAway => 'give_away',
      };

  String get label => switch (this) {
        SwapKind.exchange => 'Tausch',
        SwapKind.giveAway => 'Übernahme (Gutschrift)',
      };

  static SwapKind fromValue(String? value) => switch (value) {
        'give_away' => SwapKind.giveAway,
        _ => SwapKind.exchange,
      };
}

/// Lebenszyklus einer Tauschanfrage:
/// `pending` → Kollege (`acceptedByColleague`/`declinedByColleague`)
///           → Chef (`confirmed`/`rejectedByManager`); `cancelled` durch den
///             Antragsteller solange noch nicht bestätigt.
enum SwapStatus {
  pending,
  acceptedByColleague,
  declinedByColleague,
  confirmed,
  rejectedByManager,
  cancelled,
}

extension SwapStatusX on SwapStatus {
  String get value => switch (this) {
        SwapStatus.pending => 'pending',
        SwapStatus.acceptedByColleague => 'accepted_by_colleague',
        SwapStatus.declinedByColleague => 'declined_by_colleague',
        SwapStatus.confirmed => 'confirmed',
        SwapStatus.rejectedByManager => 'rejected_by_manager',
        SwapStatus.cancelled => 'cancelled',
      };

  String get label => switch (this) {
        SwapStatus.pending => 'Offen',
        SwapStatus.acceptedByColleague => 'Vom Kollegen angenommen',
        SwapStatus.declinedByColleague => 'Vom Kollegen abgelehnt',
        SwapStatus.confirmed => 'Bestätigt',
        SwapStatus.rejectedByManager => 'Vom Chef abgelehnt',
        SwapStatus.cancelled => 'Zurückgezogen',
      };

  /// Endzustände – keine weiteren Aktionen mehr möglich.
  bool get isClosed => switch (this) {
        SwapStatus.declinedByColleague ||
        SwapStatus.confirmed ||
        SwapStatus.rejectedByManager ||
        SwapStatus.cancelled =>
          true,
        _ => false,
      };

  static SwapStatus fromValue(String? value) => switch (value) {
        'accepted_by_colleague' => SwapStatus.acceptedByColleague,
        'declined_by_colleague' => SwapStatus.declinedByColleague,
        'confirmed' => SwapStatus.confirmed,
        'rejected_by_manager' => SwapStatus.rejectedByManager,
        'cancelled' => SwapStatus.cancelled,
        _ => SwapStatus.pending,
      };
}

/// Eine Tauschanfrage zwischen zwei Mitarbeitern (eigene Collection
/// `shiftSwapRequests`, gespiegelt von [AbsenceRequest]). Wird – wie der
/// Abwesenheitsantrag – **direkt** nach Firestore geschrieben (keine Callable).
///
/// Die denormalisierten Schicht-Snapshots (`*ShiftStart`/`*ShiftLabel`,
/// `targetName`) sind Pflicht: die Inbox des Kollegen bzw. des Chefs rendert die
/// Anfrage allein aus dem Request-Doc, ohne Lesezugriff auf die jeweils fremde
/// Schicht zu benötigen.
class ShiftSwapRequest {
  ShiftSwapRequest({
    this.id,
    required this.orgId,
    required this.requesterUid,
    required this.requesterName,
    required this.requesterShiftId,
    required this.targetUid,
    required this.targetName,
    this.targetShiftId,
    this.kind = SwapKind.exchange,
    this.status = SwapStatus.pending,
    this.reviewedByUid,
    this.overriddenCompliance = false,
    this.note,
    required this.requesterShiftStart,
    this.targetShiftStart,
    this.requesterShiftLabel,
    this.targetShiftLabel,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;

  /// Antragsteller (gibt seine Schicht ab). Bei Anlage == `auth.uid`.
  final String requesterUid;
  final String requesterName;
  final String requesterShiftId;

  /// Zielmitarbeiter / Kollege, dessen Schicht ausgewählt wurde.
  final String targetUid;
  final String targetName;

  /// Schicht des Kollegen – `null` bei [SwapKind.giveAway].
  final String? targetShiftId;

  final SwapKind kind;
  final SwapStatus status;

  /// Chef, der bestätigt/abgelehnt hat.
  final String? reviewedByUid;

  /// Chef hat einen Compliance-Verstoß bewusst übersteuert.
  final bool overriddenCompliance;

  final String? note;

  // Denormalisierte Snapshots (für die Inbox-Darstellung).
  final DateTime requesterShiftStart;
  final DateTime? targetShiftStart;
  final String? requesterShiftLabel;
  final String? targetShiftLabel;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isGiveAway => kind == SwapKind.giveAway;

  factory ShiftSwapRequest.fromMap(Map<String, dynamic> map) {
    return ShiftSwapRequest(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      requesterUid: (map['requester_uid'] ?? '').toString(),
      requesterName: (map['requester_name'] ?? '').toString(),
      requesterShiftId: (map['requester_shift_id'] ?? '').toString(),
      targetUid: (map['target_uid'] ?? '').toString(),
      targetName: (map['target_name'] ?? '').toString(),
      targetShiftId: map['target_shift_id'] as String?,
      kind: SwapKindX.fromValue(map['kind']?.toString()),
      status: SwapStatusX.fromValue(map['status']?.toString()),
      reviewedByUid: map['reviewed_by_uid'] as String?,
      overriddenCompliance: (map['overridden_compliance'] as bool?) ?? false,
      note: map['note'] as String?,
      requesterShiftStart:
          FirestoreDateParser.readLocalDate(map['requester_shift_start']) ??
              DateTime.now(),
      targetShiftStart:
          FirestoreDateParser.readLocalDate(map['target_shift_start']),
      requesterShiftLabel: map['requester_shift_label'] as String?,
      targetShiftLabel: map['target_shift_label'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  factory ShiftSwapRequest.fromFirestore(String id, Map<String, dynamic> map) {
    return ShiftSwapRequest(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      requesterUid: (map['requesterUid'] ?? '').toString(),
      requesterName: (map['requesterName'] ?? '').toString(),
      requesterShiftId: (map['requesterShiftId'] ?? '').toString(),
      targetUid: (map['targetUid'] ?? '').toString(),
      targetName: (map['targetName'] ?? '').toString(),
      targetShiftId: map['targetShiftId'] as String?,
      kind: SwapKindX.fromValue(map['kind']?.toString()),
      status: SwapStatusX.fromValue(map['status']?.toString()),
      reviewedByUid: map['reviewedByUid'] as String?,
      overriddenCompliance: (map['overriddenCompliance'] as bool?) ?? false,
      note: map['note'] as String?,
      requesterShiftStart:
          FirestoreDateParser.readDate(map['requesterShiftStart']) ??
              DateTime.now(),
      targetShiftStart: FirestoreDateParser.readDate(map['targetShiftStart']),
      requesterShiftLabel: map['requesterShiftLabel'] as String?,
      targetShiftLabel: map['targetShiftLabel'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'requesterUid': requesterUid,
      'requesterName': requesterName,
      'requesterShiftId': requesterShiftId,
      'targetUid': targetUid,
      'targetName': targetName,
      'targetShiftId': targetShiftId,
      'kind': kind.value,
      'status': status.value,
      'reviewedByUid': reviewedByUid,
      'overriddenCompliance': overriddenCompliance,
      'note': note,
      'requesterShiftStart': Timestamp.fromDate(requesterShiftStart),
      'targetShiftStart':
          targetShiftStart == null ? null : Timestamp.fromDate(targetShiftStart!),
      'requesterShiftLabel': requesterShiftLabel,
      'targetShiftLabel': targetShiftLabel,
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'requester_uid': requesterUid,
      'requester_name': requesterName,
      'requester_shift_id': requesterShiftId,
      'target_uid': targetUid,
      'target_name': targetName,
      'target_shift_id': targetShiftId,
      'kind': kind.value,
      'status': status.value,
      'reviewed_by_uid': reviewedByUid,
      'overridden_compliance': overriddenCompliance,
      'note': note,
      'requester_shift_start': requesterShiftStart.toIso8601String(),
      'target_shift_start': targetShiftStart?.toIso8601String(),
      'requester_shift_label': requesterShiftLabel,
      'target_shift_label': targetShiftLabel,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  ShiftSwapRequest copyWith({
    String? id,
    String? orgId,
    String? requesterUid,
    String? requesterName,
    String? requesterShiftId,
    String? targetUid,
    String? targetName,
    String? targetShiftId,
    bool clearTargetShiftId = false,
    SwapKind? kind,
    SwapStatus? status,
    String? reviewedByUid,
    bool clearReviewedByUid = false,
    bool? overriddenCompliance,
    String? note,
    bool clearNote = false,
    DateTime? requesterShiftStart,
    DateTime? targetShiftStart,
    bool clearTargetShiftStart = false,
    String? requesterShiftLabel,
    bool clearRequesterShiftLabel = false,
    String? targetShiftLabel,
    bool clearTargetShiftLabel = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ShiftSwapRequest(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      requesterUid: requesterUid ?? this.requesterUid,
      requesterName: requesterName ?? this.requesterName,
      requesterShiftId: requesterShiftId ?? this.requesterShiftId,
      targetUid: targetUid ?? this.targetUid,
      targetName: targetName ?? this.targetName,
      targetShiftId:
          clearTargetShiftId ? null : (targetShiftId ?? this.targetShiftId),
      kind: kind ?? this.kind,
      status: status ?? this.status,
      reviewedByUid:
          clearReviewedByUid ? null : (reviewedByUid ?? this.reviewedByUid),
      overriddenCompliance: overriddenCompliance ?? this.overriddenCompliance,
      note: clearNote ? null : (note ?? this.note),
      requesterShiftStart: requesterShiftStart ?? this.requesterShiftStart,
      targetShiftStart: clearTargetShiftStart
          ? null
          : (targetShiftStart ?? this.targetShiftStart),
      requesterShiftLabel: clearRequesterShiftLabel
          ? null
          : (requesterShiftLabel ?? this.requesterShiftLabel),
      targetShiftLabel: clearTargetShiftLabel
          ? null
          : (targetShiftLabel ?? this.targetShiftLabel),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
