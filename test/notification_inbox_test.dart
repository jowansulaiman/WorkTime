import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_notification.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/notification_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

const _employee = AppUserProfile(
  uid: 'emp-1',
  orgId: 'org-1',
  email: 'peter@example.com',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Peter'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late FirestoreService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    firestore = FakeFirebaseFirestore();
    service = FirestoreService(firestore: firestore);
  });

  Future<void> seed(String id, String uid,
      {bool read = false, int day = 1}) async {
    await firestore
        .collection('organizations')
        .doc('org-1')
        .collection('notifications')
        .doc(id)
        .set({
      'recipientUid': uid,
      'category': 'delivery',
      'title': 'Titel $id',
      'body': 'Text $id',
      'route': '/mitteilungen',
      'entityType': 'x',
      'entityId': 'e$id',
      'readAt': read ? Timestamp.fromDate(DateTime(2026, 6, day)) : null,
      'createdAt': Timestamp.fromDate(DateTime(2026, 6, day)),
    });
  }

  group('AppNotification model', () {
    test('fromFirestore liest die echten Felder + isUnread', () {
      final n = AppNotification.fromFirestore('n1', {
        'recipientUid': 'emp-1',
        'category': 'document',
        'title': 'T',
        'body': 'B',
        'route': '/dok',
        'entityType': 'employeeDocument',
        'entityId': 'd1',
        'readAt': null,
      });
      expect(n.recipientUid, 'emp-1');
      expect(n.route, '/dok');
      expect(n.isUnread, isTrue);
    });
  });

  group('NotificationProvider Inbox (PERSONAL-9/Q4)', () {
    test('streamt eigene Mitteilungen (neueste zuerst) + unreadCount', () async {
      await seed('a', 'emp-1', day: 1, read: true);
      await seed('b', 'emp-1', day: 3);
      await seed('c', 'emp-2', day: 2); // fremd — darf nicht erscheinen

      final provider =
          NotificationProvider(firestoreService: service);
      addTearDown(provider.dispose);
      await provider.updateSession(_employee, hybridStorageEnabled: true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.notifications.map((n) => n.id), ['b', 'a']); // desc
      expect(provider.unreadCount, 1); // nur 'b' ungelesen
    });

    test('markAsRead setzt readAt feldgranular', () async {
      await seed('b', 'emp-1', day: 3);
      final provider =
          NotificationProvider(firestoreService: service);
      addTearDown(provider.dispose);
      await provider.updateSession(_employee, hybridStorageEnabled: true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.unreadCount, 1);
      await provider.markAsRead(provider.notifications.first);
      final snap = await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('notifications')
          .doc('b')
          .get();
      expect(snap.data()?['readAt'], isNotNull);
    });

    test('local-Modus: leere Inbox (bewusste Degradation)', () async {
      await seed('b', 'emp-1', day: 3);
      final provider =
          NotificationProvider(firestoreService: service);
      addTearDown(provider.dispose);
      await provider.updateSession(_employee, localStorageOnly: true);
      await Future<void>.delayed(Duration.zero);
      expect(provider.notifications, isEmpty);
      expect(provider.unreadCount, 0);
    });
  });
}
