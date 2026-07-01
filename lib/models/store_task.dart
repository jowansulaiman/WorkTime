import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import 'work_task.dart' show TaskPriority, TaskPriorityX;

/// Erledigt-Vermerk einer Laden-Aufgabe **für einen bestimmten Laden**: wer sie
/// wann abgehakt hat. Als verschachtelter Wert in [StoreTask.completedBySite]
/// gespeichert; `at` wird bewusst als ISO-String abgelegt (nested, nie
/// abgefragt) und über [FirestoreDateParser.readLocalDate] gelesen.
class StoreTaskCompletion {
  const StoreTaskCompletion({this.employeeId, this.name, this.at});

  final String? employeeId;
  final String? name;
  final DateTime? at;

  Map<String, dynamic> toMap() => {
        if (employeeId != null) 'by': employeeId,
        if (name != null) 'name': name,
        if (at != null) 'at': at!.toIso8601String(),
      };

  factory StoreTaskCompletion.fromMap(Map<String, dynamic> map) =>
      StoreTaskCompletion(
        employeeId: map['by'] as String?,
        name: map['name'] as String?,
        at: FirestoreDateParser.readLocalDate(map['at']),
      );
}

/// Laden-To-Do („Aufgabe im Laden"), das der Leiter fürs Team festlegt und das
/// auf dem geteilten Laden-Tablet (Arbeitsmodus/Kiosk) angezeigt wird.
///
/// [siteId] `null` = **Broadcast** (gilt in allen Läden). Erledigt wird **je
/// Standort** in [completedBySite] festgehalten (Schlüssel = `siteId`): so hakt
/// jeder Laden dieselbe Broadcast-Aufgabe **unabhängig** ab — erledigt in Laden A
/// lässt sie in Laden B offen. Eine an genau einen Laden gebundene Aufgabe hat
/// höchstens einen Eintrag (ihren eigenen Laden).
///
/// Org-skopiert unter `organizations/{orgId}/storeTasks`. Duale Serialisierung.
class StoreTask {
  const StoreTask({
    this.id,
    required this.orgId,
    this.siteId,
    required this.title,
    this.description,
    this.dueDate,
    this.priority = TaskPriority.medium,
    this.completedBySite = const {},
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;

  /// Laden, für den die Aufgabe gilt. `null` = alle Läden (Broadcast).
  final String? siteId;

  final String title;
  final String? description;
  final DateTime? dueDate;
  final TaskPriority priority;

  /// Erledigt-Status **je Standort** (Schlüssel = `siteId`, siehe [siteKey]).
  final Map<String, StoreTaskCompletion> completedBySite;

  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Normalisierter Map-Schlüssel für einen (evtl. null/leeren) Laden.
  static String siteKey(String? siteId) =>
      (siteId == null || siteId.isEmpty) ? '__nosite__' : siteId;

  /// Ist die Aufgabe für [targetSiteId] bereits erledigt?
  bool isDoneForSite(String? targetSiteId) =>
      completedBySite.containsKey(siteKey(targetSiteId));

  StoreTaskCompletion? completionForSite(String? targetSiteId) =>
      completedBySite[siteKey(targetSiteId)];

  /// Überfällig (unabhängig vom Standort; die Board-Anzeige filtert bereits auf
  /// „für diesen Laden offen").
  bool get isOverdue {
    final due = dueDate;
    if (due == null) return false;
    final today = DateTime.now();
    return DateTime(due.year, due.month, due.day)
        .isBefore(DateTime(today.year, today.month, today.day));
  }

  /// Gilt die Aufgabe für [targetSiteId]? Broadcast ([siteId] == null) gilt
  /// überall; ein leerer Filter ([targetSiteId] == null) zeigt alles.
  bool appliesToSite(String? targetSiteId) {
    if (targetSiteId == null) return true;
    final own = siteId;
    return own == null || own.isEmpty || own == targetSiteId;
  }

  static Map<String, StoreTaskCompletion> _parseCompletions(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, StoreTaskCompletion>{};
    raw.forEach((key, value) {
      if (value is Map) {
        result[key.toString()] =
            StoreTaskCompletion.fromMap(value.cast<String, dynamic>());
      }
    });
    return result;
  }

  Map<String, dynamic> _serializeCompletions() =>
      completedBySite.map((key, value) => MapEntry(key, value.toMap()));

  factory StoreTask.fromFirestore(String id, Map<String, dynamic> map) {
    return StoreTask(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: (map['siteId'] as String?)?.trim().isEmpty ?? true
          ? null
          : map['siteId'] as String?,
      title: (map['title'] ?? '').toString(),
      description: map['description'] as String?,
      dueDate: FirestoreDateParser.readDate(map['dueDate']),
      priority: TaskPriorityX.fromValue(map['priority']?.toString()),
      completedBySite: _parseCompletions(map['completedBySite']),
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory StoreTask.fromMap(Map<String, dynamic> map) {
    return StoreTask(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      siteId: (map['site_id'] as String?)?.trim().isEmpty ?? true
          ? null
          : map['site_id'] as String?,
      title: (map['title'] ?? '').toString(),
      description: map['description'] as String?,
      dueDate: FirestoreDateParser.readLocalDate(map['due_date']),
      priority: TaskPriorityX.fromValue(map['priority']?.toString()),
      completedBySite: _parseCompletions(map['completed_by_site']),
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    final due = dueDate;
    return {
      'orgId': orgId,
      'siteId': siteId,
      'title': title,
      'description': description,
      'dueDate': due == null
          ? null
          : Timestamp.fromDate(DateTime(due.year, due.month, due.day)),
      'priority': priority.value,
      'completedBySite': _serializeCompletions(),
      'createdByUid': createdByUid,
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'site_id': siteId,
      'title': title,
      'description': description,
      'due_date': dueDate?.toIso8601String(),
      'priority': priority.value,
      'completed_by_site': _serializeCompletions(),
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  StoreTask copyWith({
    String? id,
    String? orgId,
    String? siteId,
    bool clearSiteId = false,
    String? title,
    String? description,
    bool clearDescription = false,
    DateTime? dueDate,
    bool clearDueDate = false,
    TaskPriority? priority,
    Map<String, StoreTaskCompletion>? completedBySite,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StoreTask(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      siteId: clearSiteId ? null : (siteId ?? this.siteId),
      title: title ?? this.title,
      description:
          clearDescription ? null : (description ?? this.description),
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      priority: priority ?? this.priority,
      completedBySite: completedBySite ?? this.completedBySite,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
