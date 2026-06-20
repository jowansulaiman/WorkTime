import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/work_task.dart';

void main() {
  group('WorkTask', () {
    test('round-trips toMap/fromMap (snake_case)', () {
      final task = WorkTask(
        id: 't1',
        orgId: 'org-1',
        assignedUserId: 'u1',
        title: 'Lager auffüllen',
        description: 'Tabakregal nachräumen',
        dueDate: DateTime(2026, 6, 20),
        priority: TaskPriority.high,
        status: TaskStatus.inProgress,
      );

      final restored = WorkTask.fromMap(task.toMap());

      expect(restored.id, 't1');
      expect(restored.assignedUserId, 'u1');
      expect(restored.title, 'Lager auffüllen');
      expect(restored.description, 'Tabakregal nachräumen');
      expect(restored.priority, TaskPriority.high);
      expect(restored.status, TaskStatus.inProgress);
      expect(restored.dueDate!.year, 2026);
      expect(restored.dueDate!.month, 6);
      expect(restored.dueDate!.day, 20);
    });

    test('round-trips toFirestoreMap/fromFirestore (camelCase)', () {
      const task = WorkTask(
        orgId: 'org-1',
        assignedUserId: 'u1',
        title: 'Inventur',
        priority: TaskPriority.low,
      );

      final map = task.toFirestoreMap();
      expect(map['assignedUserId'], 'u1');
      expect(map['priority'], 'low');
      expect(map['status'], 'open');

      final restored = WorkTask.fromFirestore('doc1', map);
      expect(restored.id, 'doc1');
      expect(restored.priority, TaskPriority.low);
      expect(restored.status, TaskStatus.open);
    });

    test('enum values and fromValue defaults', () {
      expect(TaskStatus.inProgress.value, 'in_progress');
      expect(TaskStatus.done.value, 'done');
      expect(TaskStatusX.fromValue(null), TaskStatus.open);
      expect(TaskStatusX.fromValue('zzz'), TaskStatus.open);
      expect(TaskPriority.high.value, 'high');
      expect(TaskPriorityX.fromValue('zzz'), TaskPriority.medium);
    });

    test('isOverdue only when past due and not done', () {
      final past = DateTime.now().subtract(const Duration(days: 2));
      final task = WorkTask(
        orgId: 'o',
        assignedUserId: 'u',
        title: 'x',
        dueDate: past,
      );
      expect(task.isOverdue, isTrue);
      expect(task.copyWith(status: TaskStatus.done).isOverdue, isFalse);

      const noDue = WorkTask(orgId: 'o', assignedUserId: 'u', title: 'x');
      expect(noDue.isOverdue, isFalse);
    });

    test('copyWith clear flags null out fields', () {
      final task = WorkTask(
        orgId: 'o',
        assignedUserId: 'u',
        title: 'x',
        description: 'd',
        dueDate: DateTime(2026, 1, 1),
      );
      final cleared = task.copyWith(clearDescription: true, clearDueDate: true);
      expect(cleared.description, isNull);
      expect(cleared.dueDate, isNull);
    });
  });
}
