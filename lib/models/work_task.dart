import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';

/// Interner Arbeitsauftrag / To-Do, der einem Mitarbeiter zugewiesen wird.
///
/// Org-skopiert unter `organizations/{orgId}/workTasks`. Teil des
/// Personal-Bereichs (nur Admin). Duale Serialisierung wie alle Models.
enum TaskStatus { open, inProgress, done }

enum TaskPriority { low, medium, high }

extension TaskStatusX on TaskStatus {
  String get value => switch (this) {
        TaskStatus.open => 'open',
        TaskStatus.inProgress => 'in_progress',
        TaskStatus.done => 'done',
      };

  String get label => switch (this) {
        TaskStatus.open => 'Offen',
        TaskStatus.inProgress => 'In Arbeit',
        TaskStatus.done => 'Erledigt',
      };

  static TaskStatus fromValue(String? value) => switch (value) {
        'in_progress' => TaskStatus.inProgress,
        'done' => TaskStatus.done,
        _ => TaskStatus.open,
      };
}

extension TaskPriorityX on TaskPriority {
  String get value => switch (this) {
        TaskPriority.low => 'low',
        TaskPriority.medium => 'medium',
        TaskPriority.high => 'high',
      };

  String get label => switch (this) {
        TaskPriority.low => 'Niedrig',
        TaskPriority.medium => 'Mittel',
        TaskPriority.high => 'Hoch',
      };

  static TaskPriority fromValue(String? value) => switch (value) {
        'low' => TaskPriority.low,
        'high' => TaskPriority.high,
        _ => TaskPriority.medium,
      };
}

class WorkTask {
  const WorkTask({
    this.id,
    required this.orgId,
    required this.assignedUserId,
    required this.title,
    this.description,
    this.dueDate,
    this.priority = TaskPriority.medium,
    this.status = TaskStatus.open,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String assignedUserId;
  final String title;
  final String? description;
  final DateTime? dueDate;
  final TaskPriority priority;
  final TaskStatus status;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isDone => status == TaskStatus.done;

  bool get isOverdue {
    final due = dueDate;
    if (due == null || isDone) return false;
    final today = DateTime.now();
    return DateTime(due.year, due.month, due.day)
        .isBefore(DateTime(today.year, today.month, today.day));
  }

  factory WorkTask.fromFirestore(String id, Map<String, dynamic> map) {
    return WorkTask(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      assignedUserId: (map['assignedUserId'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      description: map['description'] as String?,
      dueDate: FirestoreDateParser.readDate(map['dueDate']),
      priority: TaskPriorityX.fromValue(map['priority']?.toString()),
      status: TaskStatusX.fromValue(map['status']?.toString()),
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory WorkTask.fromMap(Map<String, dynamic> map) {
    return WorkTask(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      assignedUserId: (map['assigned_user_id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      description: map['description'] as String?,
      dueDate: FirestoreDateParser.readLocalDate(map['due_date']),
      priority: TaskPriorityX.fromValue(map['priority']?.toString()),
      status: TaskStatusX.fromValue(map['status']?.toString()),
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    final due = dueDate;
    return {
      'orgId': orgId,
      'assignedUserId': assignedUserId,
      'title': title,
      'description': description,
      'dueDate':
          due == null ? null : Timestamp.fromDate(DateTime(due.year, due.month, due.day)),
      'priority': priority.value,
      'status': status.value,
      'createdByUid': createdByUid,
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'assigned_user_id': assignedUserId,
      'title': title,
      'description': description,
      'due_date': dueDate?.toIso8601String(),
      'priority': priority.value,
      'status': status.value,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  WorkTask copyWith({
    String? id,
    String? orgId,
    String? assignedUserId,
    String? title,
    String? description,
    bool clearDescription = false,
    DateTime? dueDate,
    bool clearDueDate = false,
    TaskPriority? priority,
    TaskStatus? status,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WorkTask(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      assignedUserId: assignedUserId ?? this.assignedUserId,
      title: title ?? this.title,
      description:
          clearDescription ? null : (description ?? this.description),
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      priority: priority ?? this.priority,
      status: status ?? this.status,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
