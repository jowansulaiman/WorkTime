import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';

/// Status einer Schicht-Gutschrift.
enum SwapCreditStatus { open, settled, cancelled }

extension SwapCreditStatusX on SwapCreditStatus {
  String get value => switch (this) {
        SwapCreditStatus.open => 'open',
        SwapCreditStatus.settled => 'settled',
        SwapCreditStatus.cancelled => 'cancelled',
      };

  String get label => switch (this) {
        SwapCreditStatus.open => 'Offen',
        SwapCreditStatus.settled => 'Eingelöst',
        SwapCreditStatus.cancelled => 'Storniert',
      };

  static SwapCreditStatus fromValue(String? value) => switch (value) {
        'settled' => SwapCreditStatus.settled,
        'cancelled' => SwapCreditStatus.cancelled,
        _ => SwapCreditStatus.open,
      };
}

/// Eine Schicht-Gutschrift aus einem **einseitigen** Tausch
/// ([SwapKind.giveAway]): Der Kollege ([creditorUid]) hat die Schicht des
/// Antragstellers ([debtorUid]) zusätzlich übernommen und bekommt dafür eine
/// Schicht gut. Entsteht automatisch, wenn der Chef einen Übernahme-Tausch
/// bestätigt. Wird „eingelöst", sobald der Schuldner eine Schicht zurückgibt.
class SwapCredit {
  SwapCredit({
    this.id,
    required this.orgId,
    required this.creditorUid,
    required this.creditorName,
    required this.debtorUid,
    required this.debtorName,
    required this.originSwapRequestId,
    required this.originShiftStart,
    this.originShiftLabel,
    this.status = SwapCreditStatus.open,
    this.settledBySwapRequestId,
    this.settledAt,
    this.note,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;

  /// Wem geschuldet wird (Kollege, der die Schicht übernommen hat).
  final String creditorUid;
  final String creditorName;

  /// Wer schuldet (Antragsteller, der seine Schicht abgegeben hat).
  final String debtorUid;
  final String debtorName;

  final String originSwapRequestId;
  final DateTime originShiftStart;
  final String? originShiftLabel;

  final SwapCreditStatus status;
  final String? settledBySwapRequestId;
  final DateTime? settledAt;
  final String? note;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isOpen => status == SwapCreditStatus.open;

  factory SwapCredit.fromMap(Map<String, dynamic> map) {
    return SwapCredit(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      creditorUid: (map['creditor_uid'] ?? '').toString(),
      creditorName: (map['creditor_name'] ?? '').toString(),
      debtorUid: (map['debtor_uid'] ?? '').toString(),
      debtorName: (map['debtor_name'] ?? '').toString(),
      originSwapRequestId: (map['origin_swap_request_id'] ?? '').toString(),
      originShiftStart:
          FirestoreDateParser.readLocalDate(map['origin_shift_start']) ??
              DateTime.now(),
      originShiftLabel: map['origin_shift_label'] as String?,
      status: SwapCreditStatusX.fromValue(map['status']?.toString()),
      settledBySwapRequestId: map['settled_by_swap_request_id'] as String?,
      settledAt: FirestoreDateParser.readLocalDate(map['settled_at']),
      note: map['note'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  factory SwapCredit.fromFirestore(String id, Map<String, dynamic> map) {
    return SwapCredit(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      creditorUid: (map['creditorUid'] ?? '').toString(),
      creditorName: (map['creditorName'] ?? '').toString(),
      debtorUid: (map['debtorUid'] ?? '').toString(),
      debtorName: (map['debtorName'] ?? '').toString(),
      originSwapRequestId: (map['originSwapRequestId'] ?? '').toString(),
      originShiftStart:
          FirestoreDateParser.readDate(map['originShiftStart']) ??
              DateTime.now(),
      originShiftLabel: map['originShiftLabel'] as String?,
      status: SwapCreditStatusX.fromValue(map['status']?.toString()),
      settledBySwapRequestId: map['settledBySwapRequestId'] as String?,
      settledAt: FirestoreDateParser.readDate(map['settledAt']),
      note: map['note'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'creditorUid': creditorUid,
      'creditorName': creditorName,
      'debtorUid': debtorUid,
      'debtorName': debtorName,
      'originSwapRequestId': originSwapRequestId,
      'originShiftStart': Timestamp.fromDate(originShiftStart),
      'originShiftLabel': originShiftLabel,
      'status': status.value,
      'settledBySwapRequestId': settledBySwapRequestId,
      'settledAt': settledAt == null ? null : Timestamp.fromDate(settledAt!),
      'note': note,
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'creditor_uid': creditorUid,
      'creditor_name': creditorName,
      'debtor_uid': debtorUid,
      'debtor_name': debtorName,
      'origin_swap_request_id': originSwapRequestId,
      'origin_shift_start': originShiftStart.toIso8601String(),
      'origin_shift_label': originShiftLabel,
      'status': status.value,
      'settled_by_swap_request_id': settledBySwapRequestId,
      'settled_at': settledAt?.toIso8601String(),
      'note': note,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  SwapCredit copyWith({
    String? id,
    String? orgId,
    String? creditorUid,
    String? creditorName,
    String? debtorUid,
    String? debtorName,
    String? originSwapRequestId,
    DateTime? originShiftStart,
    String? originShiftLabel,
    bool clearOriginShiftLabel = false,
    SwapCreditStatus? status,
    String? settledBySwapRequestId,
    bool clearSettledBySwapRequestId = false,
    DateTime? settledAt,
    bool clearSettledAt = false,
    String? note,
    bool clearNote = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SwapCredit(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      creditorUid: creditorUid ?? this.creditorUid,
      creditorName: creditorName ?? this.creditorName,
      debtorUid: debtorUid ?? this.debtorUid,
      debtorName: debtorName ?? this.debtorName,
      originSwapRequestId: originSwapRequestId ?? this.originSwapRequestId,
      originShiftStart: originShiftStart ?? this.originShiftStart,
      originShiftLabel: clearOriginShiftLabel
          ? null
          : (originShiftLabel ?? this.originShiftLabel),
      status: status ?? this.status,
      settledBySwapRequestId: clearSettledBySwapRequestId
          ? null
          : (settledBySwapRequestId ?? this.settledBySwapRequestId),
      settledAt: clearSettledAt ? null : (settledAt ?? this.settledAt),
      note: clearNote ? null : (note ?? this.note),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
