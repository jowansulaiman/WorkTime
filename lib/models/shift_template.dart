import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_num_parser.dart' as parse;

class ShiftTemplate {
  ShiftTemplate({
    this.id,
    this.orgId = '',
    this.userId = '',
    required String name,
    required String title,
    required int startMinutes,
    required int endMinutes,
    this.breakMinutes = 0,
    this.teamId,
    String? teamName,
    this.siteId,
    String? siteName,
    this.requiredQualificationIds = const [],
    String? notes,
    this.color,
  })  : name = name.trim(),
        title = title.trim(),
        startMinutes = _normalizeMinutes(startMinutes),
        endMinutes = _normalizeMinutes(endMinutes),
        teamName = _normalizeNullable(teamName),
        siteName = _normalizeNullable(siteName),
        notes = _normalizeNullable(notes);

  final String? id;
  final String orgId;
  final String userId;
  final String name;
  final String title;
  final int startMinutes;
  final int endMinutes;
  final double breakMinutes;
  final String? teamId;
  final String? teamName;
  final String? siteId;
  final String? siteName;
  final List<String> requiredQualificationIds;
  final String? notes;
  final String? color;

  factory ShiftTemplate.fromMap(Map<String, dynamic> map) {
    return ShiftTemplate(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      startMinutes: parse.toInt(map['start_minutes']) ?? 0,
      endMinutes: parse.toInt(map['end_minutes']) ?? 0,
      breakMinutes: parse.toDouble(map['break_minutes']) ?? 0,
      teamId: map['team_id']?.toString(),
      teamName: map['team_name']?.toString(),
      siteId: map['site_id']?.toString(),
      siteName: map['site_name']?.toString(),
      requiredQualificationIds:
          ((map['required_qualification_ids'] as List<dynamic>?) ?? const [])
              .map((value) => value.toString())
              .toList(growable: false),
      notes: map['notes']?.toString(),
      color: map['color']?.toString(),
    );
  }

  factory ShiftTemplate.fromFirestore(
    String id,
    Map<String, dynamic> map,
  ) {
    return ShiftTemplate(
      id: id,
      orgId: (map['orgId'] ?? map['org_id'] ?? '').toString(),
      userId: (map['userId'] ?? map['user_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      startMinutes:
          parse.toInt(map['startMinutes'] ?? map['start_minutes']) ?? 0,
      endMinutes: parse.toInt(map['endMinutes'] ?? map['end_minutes']) ?? 0,
      breakMinutes:
          parse.toDouble(map['breakMinutes'] ?? map['break_minutes']) ?? 0,
      teamId: (map['teamId'] ?? map['team_id'])?.toString(),
      teamName: (map['teamName'] ?? map['team_name'])?.toString(),
      siteId: (map['siteId'] ?? map['site_id'])?.toString(),
      siteName: (map['siteName'] ?? map['site_name'])?.toString(),
      requiredQualificationIds: List<String>.from(
        (map['requiredQualificationIds'] ??
            map['required_qualification_ids'] ??
            const <dynamic>[]) as List<dynamic>,
      ),
      notes: (map['notes'] ?? map['note'])?.toString(),
      color: map['color']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'name': name,
      'title': title,
      'start_minutes': startMinutes,
      'end_minutes': endMinutes,
      'break_minutes': breakMinutes,
      'team_id': teamId,
      'team_name': teamName,
      'site_id': siteId,
      'site_name': siteName,
      'required_qualification_ids': requiredQualificationIds,
      'notes': notes,
      'color': color,
    };
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'name': name,
      'nameLower': name.toLowerCase(),
      'title': title,
      'startMinutes': startMinutes,
      'endMinutes': endMinutes,
      'breakMinutes': breakMinutes,
      'teamId': teamId,
      'teamName': teamName,
      'siteId': siteId,
      'siteName': siteName,
      'requiredQualificationIds': requiredQualificationIds,
      'notes': notes,
      'color': color,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  ShiftTemplate copyWith({
    String? id,
    String? orgId,
    String? userId,
    String? name,
    String? title,
    int? startMinutes,
    int? endMinutes,
    double? breakMinutes,
    String? teamId,
    bool clearTeamId = false,
    String? teamName,
    bool clearTeamName = false,
    String? siteId,
    bool clearSiteId = false,
    String? siteName,
    bool clearSiteName = false,
    List<String>? requiredQualificationIds,
    String? notes,
    bool clearNotes = false,
    String? color,
    bool clearColor = false,
  }) {
    return ShiftTemplate(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      title: title ?? this.title,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      breakMinutes: breakMinutes ?? this.breakMinutes,
      teamId: clearTeamId ? null : (teamId ?? this.teamId),
      teamName: clearTeamName ? null : (teamName ?? this.teamName),
      siteId: clearSiteId ? null : (siteId ?? this.siteId),
      siteName: clearSiteName ? null : (siteName ?? this.siteName),
      requiredQualificationIds:
          requiredQualificationIds ?? this.requiredQualificationIds,
      notes: clearNotes ? null : (notes ?? this.notes),
      color: clearColor ? null : (color ?? this.color),
    );
  }

  static int _normalizeMinutes(int value) {
    if (value < 0) return 0;
    if (value > 1439) return 1439;
    return value;
  }

  static String? _normalizeNullable(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
