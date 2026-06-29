import '../core/firestore_num_parser.dart' as parse;

/// Wert-Typen für Standort-Öffnungszeiten und Personalbedarf
/// ([SiteDefinition.weekdayHours] / [SiteDefinition.staffingDemands]).
///
/// Bewusst **minutengenaue int-Werte ab Mitternacht** statt `TimeOfDay`: nur
/// rohe Zahlen sind stabil über die Zwei-Serialisierungs-Regel
/// (Firestore camelCase ↔ lokal/Payload snake_case) hinweg round-trip-fähig.
/// `TimeOfDay` ist nicht serialisierbar. Parser sind tolerant via
/// [parse.toInt] / [parse.toMap].

/// Ein Zeitfenster innerhalb eines Tages, minutengenau ab Mitternacht.
class TimeWindow {
  const TimeWindow({required this.startMinute, required this.endMinute});

  /// Start in Minuten ab Mitternacht (0..1440, inklusiv).
  final int startMinute;

  /// Ende in Minuten ab Mitternacht (1..1440, exklusiv; `> startMinute`).
  final int endMinute;

  int get durationMinutes => endMinute - startMinute;

  /// `true`, wenn das Fenster valide ist (Ende nach Start, in Tagesgrenzen).
  bool get isValid =>
      startMinute >= 0 &&
      endMinute > startMinute &&
      endMinute <= 24 * 60;

  /// `true`, wenn sich dieses Fenster mit [other] überschneidet
  /// (halb-offen `[start, end)`).
  bool overlaps(TimeWindow other) =>
      startMinute < other.endMinute && endMinute > other.startMinute;

  factory TimeWindow.fromFirestore(Map<String, dynamic> map) {
    return TimeWindow(
      startMinute: parse.toInt(map['startMinute']) ?? 0,
      endMinute: parse.toInt(map['endMinute']) ?? 0,
    );
  }

  factory TimeWindow.fromMap(Map<String, dynamic> map) {
    return TimeWindow(
      startMinute: parse.toInt(map['start_minute']) ?? 0,
      endMinute: parse.toInt(map['end_minute']) ?? 0,
    );
  }

  Map<String, dynamic> toFirestoreMap() => {
        'startMinute': startMinute,
        'endMinute': endMinute,
      };

  Map<String, dynamic> toMap() => {
        'start_minute': startMinute,
        'end_minute': endMinute,
      };

  TimeWindow copyWith({int? startMinute, int? endMinute}) => TimeWindow(
        startMinute: startMinute ?? this.startMinute,
        endMinute: endMinute ?? this.endMinute,
      );

  @override
  bool operator ==(Object other) =>
      other is TimeWindow &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute;

  @override
  int get hashCode => Object.hash(startMinute, endMinute);
}

/// Öffnungszeiten eines Wochentags. Mehrere Fenster erlaubt (z.B. Mittagspause).
class WeekdayHours {
  const WeekdayHours({required this.weekday, required this.windows});

  /// `DateTime.monday`..`DateTime.sunday` (1..7).
  final int weekday;
  final List<TimeWindow> windows;

  factory WeekdayHours.fromFirestore(Map<String, dynamic> map) {
    return WeekdayHours(
      weekday: parse.toInt(map['weekday']) ?? DateTime.monday,
      windows: ((map['windows'] as List?) ?? const [])
          .map((e) => TimeWindow.fromFirestore(parse.toMap(e)))
          .toList(growable: false),
    );
  }

  factory WeekdayHours.fromMap(Map<String, dynamic> map) {
    return WeekdayHours(
      weekday: parse.toInt(map['weekday']) ?? DateTime.monday,
      windows: ((map['windows'] as List?) ?? const [])
          .map((e) => TimeWindow.fromMap(parse.toMap(e)))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toFirestoreMap() => {
        'weekday': weekday,
        'windows': windows.map((e) => e.toFirestoreMap()).toList(),
      };

  Map<String, dynamic> toMap() => {
        'weekday': weekday,
        'windows': windows.map((e) => e.toMap()).toList(),
      };

  WeekdayHours copyWith({int? weekday, List<TimeWindow>? windows}) =>
      WeekdayHours(
        weekday: weekday ?? this.weekday,
        windows: windows ?? this.windows,
      );
}

/// Bedarf an Personal in einem Zeitfenster eines Wochentags.
class StaffingDemand {
  const StaffingDemand({
    required this.weekday,
    required this.window,
    required this.requiredCount,
    this.requiredQualificationIds = const [],
  });

  /// `DateTime.monday`..`DateTime.sunday` (1..7).
  final int weekday;

  /// Zeitfenster des Bedarfs (sollte in einem Öffnungsfenster liegen — weiche
  /// Validierung in der UI, kein harter Block).
  final TimeWindow window;

  /// Anzahl gleichzeitig benötigter Mitarbeiter (>= 1).
  final int requiredCount;

  /// Erforderliche Qualifikationen; leer = keine Quali-Anforderung.
  final List<String> requiredQualificationIds;

  factory StaffingDemand.fromFirestore(Map<String, dynamic> map) {
    return StaffingDemand(
      weekday: parse.toInt(map['weekday']) ?? DateTime.monday,
      window: TimeWindow.fromFirestore(parse.toMap(map['window'])),
      requiredCount: parse.toInt(map['requiredCount']) ?? 1,
      requiredQualificationIds:
          ((map['requiredQualificationIds'] as List?) ?? const [])
              .map((e) => e.toString())
              .toList(growable: false),
    );
  }

  factory StaffingDemand.fromMap(Map<String, dynamic> map) {
    return StaffingDemand(
      weekday: parse.toInt(map['weekday']) ?? DateTime.monday,
      window: TimeWindow.fromMap(parse.toMap(map['window'])),
      requiredCount: parse.toInt(map['required_count']) ?? 1,
      requiredQualificationIds:
          ((map['required_qualification_ids'] as List?) ?? const [])
              .map((e) => e.toString())
              .toList(growable: false),
    );
  }

  Map<String, dynamic> toFirestoreMap() => {
        'weekday': weekday,
        'window': window.toFirestoreMap(),
        'requiredCount': requiredCount,
        'requiredQualificationIds': requiredQualificationIds,
      };

  Map<String, dynamic> toMap() => {
        'weekday': weekday,
        'window': window.toMap(),
        'required_count': requiredCount,
        'required_qualification_ids': requiredQualificationIds,
      };

  StaffingDemand copyWith({
    int? weekday,
    TimeWindow? window,
    int? requiredCount,
    List<String>? requiredQualificationIds,
  }) =>
      StaffingDemand(
        weekday: weekday ?? this.weekday,
        window: window ?? this.window,
        requiredCount: requiredCount ?? this.requiredCount,
        requiredQualificationIds:
            requiredQualificationIds ?? this.requiredQualificationIds,
      );
}
