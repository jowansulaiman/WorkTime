import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Art einer Schicht-Vorgabe eines Mitarbeiters.
/// - [prefer] / [avoid] sind **weiche** Wünsche (fließen nur ins Scoring ein,
///   können bei Bedarf übergangen werden — Abdeckung leidet nie).
/// - [block] ist eine **harte** Sperre (wird wie eine Abwesenheit behandelt:
///   die Schicht wird diesem Mitarbeiter NIE automatisch zugewiesen).
enum PreferenceKind { prefer, avoid, block }

extension PreferenceKindX on PreferenceKind {
  String get value => switch (this) {
        PreferenceKind.prefer => 'prefer',
        PreferenceKind.avoid => 'avoid',
        PreferenceKind.block => 'block',
      };

  String get label => switch (this) {
        PreferenceKind.prefer => 'Bevorzugen',
        PreferenceKind.avoid => 'Meiden',
        PreferenceKind.block => 'Sperren',
      };

  bool get isHard => this == PreferenceKind.block;

  static PreferenceKind fromValue(String? value) => switch (value) {
        'avoid' => PreferenceKind.avoid,
        'block' => PreferenceKind.block,
        _ => PreferenceKind.prefer,
      };
}

/// Tageszeit-Voreinstellungen für die UI (mappen auf Minutenfenster). `null` in
/// einer Regel bedeutet „eigenes Zeitfenster" (frei gewählte Start-/Endzeit).
enum ShiftDaypart { morning, afternoon, evening }

extension ShiftDaypartX on ShiftDaypart {
  String get value => switch (this) {
        ShiftDaypart.morning => 'morning',
        ShiftDaypart.afternoon => 'afternoon',
        ShiftDaypart.evening => 'evening',
      };

  String get label => switch (this) {
        ShiftDaypart.morning => 'Vormittag',
        ShiftDaypart.afternoon => 'Nachmittag',
        ShiftDaypart.evening => 'Abend',
      };

  /// Startminute des Tagesabschnitts (ab Mitternacht). Vormittag 06–12,
  /// Nachmittag 12–18, Abend 18–24.
  int get startMinute => switch (this) {
        ShiftDaypart.morning => 6 * 60,
        ShiftDaypart.afternoon => 12 * 60,
        ShiftDaypart.evening => 18 * 60,
      };

  int get endMinute => switch (this) {
        ShiftDaypart.morning => 12 * 60,
        ShiftDaypart.afternoon => 18 * 60,
        ShiftDaypart.evening => 24 * 60,
      };

  static ShiftDaypart? fromValue(String? value) => switch (value) {
        'morning' => ShiftDaypart.morning,
        'afternoon' => ShiftDaypart.afternoon,
        'evening' => ShiftDaypart.evening,
        _ => null,
      };
}

/// Eine einzelne Regel innerhalb der Vorgaben eines Mitarbeiters: „[kind] an
/// [weekdays] im Zeitfenster [startMinute]–[endMinute]". Leere [weekdays] = alle
/// Wochentage. Optionaler [daypart]-Hinweis erhält die UI-Voreinstellung über
/// den Round-Trip (rein kosmetisch; maßgeblich sind die Minuten).
class ShiftPreferenceRule {
  const ShiftPreferenceRule({
    required this.kind,
    this.weekdays = const {},
    this.startMinute = 0,
    this.endMinute = 24 * 60,
    this.daypart,
  });

  final PreferenceKind kind;

  /// Wochentage 1 (Montag) … 7 (Sonntag). Leer = gilt an allen Tagen.
  final Set<int> weekdays;

  /// Zeitfenster in Minuten ab Mitternacht (0 … 1440).
  final int startMinute;
  final int endMinute;

  /// Optionale Tageszeit-Voreinstellung (nur UI/Anzeige).
  final ShiftDaypart? daypart;

  bool get coversWholeDay => startMinute <= 0 && endMinute >= 24 * 60;

  bool matchesWeekday(int weekday) =>
      weekdays.isEmpty || weekdays.contains(weekday);

  /// Überlappungsminuten des Schicht-Tagesfensters mit dem Regelfenster.
  int overlapMinutes(int shiftStartMinute, int shiftEndMinute) {
    final lo = startMinute > shiftStartMinute ? startMinute : shiftStartMinute;
    final hi = endMinute < shiftEndMinute ? endMinute : shiftEndMinute;
    final overlap = hi - lo;
    return overlap > 0 ? overlap : 0;
  }

  /// Anteil der Schichtdauer (0 … 1), der ins Regelfenster fällt — Grundlage
  /// der weichen Gewichtung („überwiegend vormittags" zählt mehr als „streift").
  double overlapFraction(int shiftStartMinute, int shiftEndMinute) {
    final duration = shiftEndMinute - shiftStartMinute;
    if (duration <= 0) return 0;
    return overlapMinutes(shiftStartMinute, shiftEndMinute) / duration;
  }

  ShiftPreferenceRule copyWith({
    PreferenceKind? kind,
    Set<int>? weekdays,
    int? startMinute,
    int? endMinute,
    ShiftDaypart? daypart,
    bool clearDaypart = false,
  }) {
    return ShiftPreferenceRule(
      kind: kind ?? this.kind,
      weekdays: weekdays ?? this.weekdays,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
      daypart: clearDaypart ? null : (daypart ?? this.daypart),
    );
  }

  static List<int> _parseWeekdays(dynamic raw) {
    if (raw is! List) return const [];
    final out = <int>{};
    for (final e in raw) {
      final d = parse.toInt(e);
      if (d != null && d >= 1 && d <= 7) out.add(d);
    }
    final sorted = out.toList()..sort();
    return sorted;
  }

  factory ShiftPreferenceRule.fromFirestore(Map<String, dynamic> map) {
    return ShiftPreferenceRule(
      kind: PreferenceKindX.fromValue(map['kind']?.toString()),
      weekdays: _parseWeekdays(map['weekdays']).toSet(),
      startMinute: parse.toInt(map['startMinute']) ?? 0,
      endMinute: parse.toInt(map['endMinute']) ?? 24 * 60,
      daypart: ShiftDaypartX.fromValue(map['daypart']?.toString()),
    );
  }

  factory ShiftPreferenceRule.fromMap(Map<String, dynamic> map) {
    return ShiftPreferenceRule(
      kind: PreferenceKindX.fromValue(map['kind']?.toString()),
      weekdays: _parseWeekdays(map['weekdays']).toSet(),
      startMinute: parse.toInt(map['start_minute']) ?? 0,
      endMinute: parse.toInt(map['end_minute']) ?? 24 * 60,
      daypart: ShiftDaypartX.fromValue(map['daypart']?.toString()),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    final sortedDays = weekdays.toList()..sort();
    return {
      'kind': kind.value,
      'weekdays': sortedDays,
      'startMinute': startMinute,
      'endMinute': endMinute,
      if (daypart != null) 'daypart': daypart!.value,
    };
  }

  Map<String, dynamic> toMap() {
    final sortedDays = weekdays.toList()..sort();
    return {
      'kind': kind.value,
      'weekdays': sortedDays,
      'start_minute': startMinute,
      'end_minute': endMinute,
      if (daypart != null) 'daypart': daypart!.value,
    };
  }
}

/// Schicht-Vorgaben **eines** Mitarbeiters (org-skopiert, Doc-ID = userId).
/// Enthält eine Liste von [ShiftPreferenceRule]. Wird von der automatischen
/// Schichtverteilung ausgewertet: [block]-Regeln hart, [prefer]/[avoid] weich.
class EmployeeShiftPreference {
  const EmployeeShiftPreference({
    this.id,
    required this.orgId,
    required this.userId,
    this.rules = const [],
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String userId;
  final List<ShiftPreferenceRule> rules;
  final DateTime? updatedAt;

  bool get isEmpty => rules.isEmpty;
  bool get isNotEmpty => rules.isNotEmpty;

  factory EmployeeShiftPreference.empty(String orgId, String userId) =>
      EmployeeShiftPreference(orgId: orgId, userId: userId);

  /// Ist die Schicht (Wochentag + Tages-Minutenfenster) hart gesperrt?
  bool isBlocked(int weekday, int shiftStartMinute, int shiftEndMinute) {
    for (final rule in rules) {
      if (rule.kind != PreferenceKind.block) continue;
      if (!rule.matchesWeekday(weekday)) continue;
      if (rule.overlapMinutes(shiftStartMinute, shiftEndMinute) > 0) {
        return true;
      }
    }
    return false;
  }

  /// Weicher Score in [-1, 1]: positiv = bevorzugt, negativ = gemieden,
  /// 0 = neutral. Jeweils stärkster überlappender Wunsch je Richtung zählt.
  double softScore(int weekday, int shiftStartMinute, int shiftEndMinute) {
    var prefer = 0.0;
    var avoid = 0.0;
    for (final rule in rules) {
      if (rule.kind == PreferenceKind.block) continue;
      if (!rule.matchesWeekday(weekday)) continue;
      final frac = rule.overlapFraction(shiftStartMinute, shiftEndMinute);
      if (frac <= 0) continue;
      if (rule.kind == PreferenceKind.prefer) {
        if (frac > prefer) prefer = frac;
      } else {
        if (frac > avoid) avoid = frac;
      }
    }
    return prefer - avoid;
  }

  EmployeeShiftPreference copyWith({
    String? id,
    String? orgId,
    String? userId,
    List<ShiftPreferenceRule>? rules,
    DateTime? updatedAt,
  }) {
    return EmployeeShiftPreference(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      rules: rules ?? this.rules,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static List<ShiftPreferenceRule> _parseRules(
    dynamic raw, {
    required bool local,
  }) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) {
          final map = parse.toMap(e);
          return local
              ? ShiftPreferenceRule.fromMap(map)
              : ShiftPreferenceRule.fromFirestore(map);
        })
        .toList(growable: false);
  }

  factory EmployeeShiftPreference.fromFirestore(
    String id,
    Map<String, dynamic> map,
  ) {
    return EmployeeShiftPreference(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      rules: _parseRules(map['rules'], local: false),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory EmployeeShiftPreference.fromMap(Map<String, dynamic> map) {
    return EmployeeShiftPreference(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      rules: _parseRules(map['rules'], local: true),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'rules': rules.map((r) => r.toFirestoreMap()).toList(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'rules': rules.map((r) => r.toMap()).toList(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}
