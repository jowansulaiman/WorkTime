import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

class TravelTimeRule {
  const TravelTimeRule({
    this.id,
    required this.orgId,
    required this.fromSiteId,
    required this.toSiteId,
    required this.travelMinutes,
    this.countsAsWorkTime = true,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String fromSiteId;
  final String toSiteId;
  final int travelMinutes;
  final bool countsAsWorkTime;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool matches(String fromSiteId, String toSiteId) {
    return this.fromSiteId == fromSiteId && this.toSiteId == toSiteId;
  }

  factory TravelTimeRule.fromFirestore(String id, Map<String, dynamic> map) {
    return TravelTimeRule(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      fromSiteId: (map['fromSiteId'] ?? '').toString(),
      toSiteId: (map['toSiteId'] ?? '').toString(),
      travelMinutes: parse.toInt(map['travelMinutes']) ?? 0,
      countsAsWorkTime: parse.toBool(map['countsAsWorkTime']) ?? true,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory TravelTimeRule.fromMap(Map<String, dynamic> map) {
    return TravelTimeRule(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      fromSiteId: (map['from_site_id'] ?? '').toString(),
      toSiteId: (map['to_site_id'] ?? '').toString(),
      travelMinutes: parse.toInt(map['travel_minutes']) ?? 0,
      countsAsWorkTime: parse.toBool(map['counts_as_work_time']) ?? true,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'fromSiteId': fromSiteId,
      'toSiteId': toSiteId,
      'travelMinutes': travelMinutes,
      'countsAsWorkTime': countsAsWorkTime,
      'createdByUid': createdByUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'from_site_id': fromSiteId,
      'to_site_id': toSiteId,
      'travel_minutes': travelMinutes,
      'counts_as_work_time': countsAsWorkTime,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  TravelTimeRule copyWith({
    String? id,
    String? orgId,
    String? fromSiteId,
    String? toSiteId,
    int? travelMinutes,
    bool? countsAsWorkTime,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TravelTimeRule(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      fromSiteId: fromSiteId ?? this.fromSiteId,
      toSiteId: toSiteId ?? this.toSiteId,
      travelMinutes: travelMinutes ?? this.travelMinutes,
      countsAsWorkTime: countsAsWorkTime ?? this.countsAsWorkTime,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
