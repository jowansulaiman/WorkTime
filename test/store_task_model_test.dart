import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/store_task.dart';
import 'package:worktime_app/models/work_task.dart';

void main() {
  group('StoreTask duale Serialisierung', () {
    final task = StoreTask(
      id: 'st-1',
      orgId: 'org-1',
      siteId: 'site-1',
      title: 'Kühltheke abwischen',
      description: 'Vor Ladenschluss',
      dueDate: DateTime(2026, 7, 15),
      priority: TaskPriority.high,
      completedBySite: {
        'site-1': StoreTaskCompletion(
          employeeId: 'emp-9',
          name: 'Peter',
          at: DateTime(2026, 7, 14, 18, 30),
        ),
      },
      createdByUid: 'admin-1',
      createdAt: DateTime(2026, 7, 1, 8),
      updatedAt: DateTime(2026, 7, 14, 18, 30),
    );

    test('toMap/fromMap (snake_case) rundläuft inkl. completedBySite', () {
      final restored = StoreTask.fromMap(task.toMap());
      expect(restored.id, 'st-1');
      expect(restored.siteId, 'site-1');
      expect(restored.priority, TaskPriority.high);
      expect(restored.completedBySite.keys, ['site-1']);
      expect(restored.completedBySite['site-1']!.name, 'Peter');
      expect(restored.completedBySite['site-1']!.employeeId, 'emp-9');
      expect(restored.isDoneForSite('site-1'), isTrue);
    });

    test('fromFirestore (camelCase, Timestamp) liest korrekt', () {
      final restored = StoreTask.fromFirestore('st-1', {
        'orgId': 'org-1',
        'siteId': 'site-1',
        'title': 'Kühltheke abwischen',
        'dueDate': Timestamp.fromDate(DateTime(2026, 7, 15)),
        'priority': 'high',
        'completedBySite': {
          'site-1': {'by': 'emp-9', 'name': 'Peter', 'at': '2026-07-14T18:30:00.000'},
        },
      });
      expect(restored.priority, TaskPriority.high);
      expect(restored.isDoneForSite('site-1'), isTrue);
      expect(restored.completionForSite('site-1')!.name, 'Peter');
    });

    test('toFirestoreMap: camelCase-Keys, serverTimestamp bei neu, kein Status',
        () {
      const neu = StoreTask(orgId: 'org-1', title: 'Neu');
      final map = neu.toFirestoreMap();
      expect(map['priority'], 'medium');
      expect(map['completedBySite'], isA<Map>());
      expect(map.containsKey('status'), isFalse);
      expect(map.containsKey('assignedUserId'), isFalse);
      expect(map['createdAt'], isA<FieldValue>());
      expect(map['updatedAt'], isA<FieldValue>());
    });

    test('leere siteId wird zu null (Broadcast) normalisiert', () {
      final fromFs = StoreTask.fromFirestore('x', {
        'orgId': 'org-1',
        'title': 'T',
        'siteId': '',
      });
      expect(fromFs.siteId, isNull);
    });
  });

  group('StoreTask copyWith / clearX', () {
    const task = StoreTask(
      id: 'st-1',
      orgId: 'org-1',
      siteId: 'site-1',
      title: 'T',
      description: 'D',
    );

    test('clearSiteId leert das Feld (Broadcast)', () {
      expect(task.copyWith(clearSiteId: true).siteId, isNull);
    });

    test('clearDescription leert die Beschreibung', () {
      expect(task.copyWith(clearDescription: true).description, isNull);
    });
  });

  group('StoreTask appliesToSite + isDoneForSite (per-Standort)', () {
    test('Broadcast-Aufgabe gilt in jedem Laden', () {
      const t = StoreTask(orgId: 'o', title: 'T');
      expect(t.appliesToSite('site-1'), isTrue);
      expect(t.appliesToSite('site-2'), isTrue);
    });

    test('Laden-Aufgabe gilt nur im eigenen Laden', () {
      const t = StoreTask(orgId: 'o', title: 'T', siteId: 'site-1');
      expect(t.appliesToSite('site-1'), isTrue);
      expect(t.appliesToSite('site-2'), isFalse);
    });

    test('Erledigt je Standort: A erledigt lässt B offen', () {
      const t = StoreTask(
        orgId: 'o',
        title: 'T',
        completedBySite: {'site-1': StoreTaskCompletion(name: 'A')},
      );
      expect(t.isDoneForSite('site-1'), isTrue);
      expect(t.isDoneForSite('site-2'), isFalse);
    });
  });
}
