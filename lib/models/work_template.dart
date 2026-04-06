import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_num_parser.dart' as parse;

class WorkTemplate {
  final String? id;
  final String orgId;
  final String userId;
  final String name;
  final int startMinutes;
  final int endMinutes;
  final double breakMinutes;
  final String? note;

  WorkTemplate({
    this.id,
    this.orgId = '',
    this.userId = '',
    required String name,
    required int startMinutes,
    required int endMinutes,
    double breakMinutes = 0,
    String? note,
  })  : name = name.trim(),
        startMinutes = _normalizeMinutes(startMinutes),
        endMinutes = _normalizeMinutes(endMinutes),
        breakMinutes = breakMinutes < 0 ? 0 : breakMinutes,
        note = _normalizeNote(note);

  int get startHour => startMinutes ~/ 60;
  int get startMinute => startMinutes % 60;
  int get endHour => endMinutes ~/ 60;
  int get endMinute => endMinutes % 60;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'name': name,
      'start_minutes': startMinutes,
      'end_minutes': endMinutes,
      'break_minutes': breakMinutes,
      'note': note,
    };
  }

  factory WorkTemplate.fromMap(Map<String, dynamic> map) {
    return WorkTemplate(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      startMinutes: parse.toInt(map['start_minutes']) ?? 0,
      endMinutes: parse.toInt(map['end_minutes']) ?? 0,
      breakMinutes: parse.toDouble(map['break_minutes']) ?? 0,
      note: map['note'] as String?,
    );
  }

  factory WorkTemplate.fromFirestore(
    String id,
    Map<String, dynamic> map,
  ) {
    return WorkTemplate(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      startMinutes: parse.toInt(map['startMinutes']) ?? 0,
      endMinutes: parse.toInt(map['endMinutes']) ?? 0,
      breakMinutes: parse.toDouble(map['breakMinutes']) ?? 0,
      note: map['note'] as String?,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'name': name,
      'startMinutes': startMinutes,
      'endMinutes': endMinutes,
      'breakMinutes': breakMinutes,
      'note': note,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  WorkTemplate copyWith({
    String? id,
    String? orgId,
    String? userId,
    String? name,
    int? startMinutes,
    int? endMinutes,
    double? breakMinutes,
    String? note,
    bool clearNote = false,
  }) {
    return WorkTemplate(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      breakMinutes: breakMinutes ?? this.breakMinutes,
      note: clearNote ? null : (note ?? this.note),
    );
  }

  static int _normalizeMinutes(int value) {
    if (value < 0) return 0;
    if (value > 1439) return 1439;
    return value;
  }

  static String? _normalizeNote(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}
