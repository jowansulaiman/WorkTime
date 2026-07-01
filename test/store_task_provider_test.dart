import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/store_task.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/store_task_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

const _admin = AppUserProfile(
  uid: 'admin-1',
  orgId: 'org-1',
  email: 'admin@example.com',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Sandra'),
);

const _employee = AppUserProfile(
  uid: 'emp-1',
  orgId: 'org-1',
  email: 'peter@example.com',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Peter'),
);

StoreTaskProvider _localProvider() => StoreTaskProvider(
      firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      disableAuthentication: true,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  test('Leiter kann eine Laden-Aufgabe anlegen (local)', () async {
    final provider = _localProvider();
    await provider.updateSession(_admin);

    await provider.saveStoreTask(
      const StoreTask(
          orgId: 'org-1', siteId: 'site-1', title: 'Kühltheke abwischen'),
    );

    expect(provider.tasks, hasLength(1));
    expect(provider.tasks.single.title, 'Kühltheke abwischen');
    expect(provider.tasks.single.id, isNotNull);
    expect(provider.tasks.single.createdByUid, 'admin-1');
    expect(provider.tasks.single.completedBySite, isEmpty);
  });

  test('Mitarbeiter darf NICHT anlegen (canManage-Gate)', () async {
    final provider = _localProvider();
    await provider.updateSession(_employee);

    expect(
      () => provider.saveStoreTask(const StoreTask(orgId: 'org-1', title: 'X')),
      throwsStateError,
    );
  });

  test('Abhaken je Standort setzt erledigt-von; jeder darf es', () async {
    final provider = _localProvider();
    await provider.updateSession(_admin);
    await provider.saveStoreTask(
      const StoreTask(orgId: 'org-1', siteId: 'site-1', title: 'Boden wischen'),
    );

    await provider.updateSession(_employee);
    final task = provider.tasks.single;
    await provider.markDoneForSite(task, 'site-1',
        employeeId: 'emp-1', employeeName: 'Peter');

    final done = provider.tasks.single;
    expect(done.isDoneForSite('site-1'), isTrue);
    expect(done.completionForSite('site-1')!.employeeId, 'emp-1');
    expect(done.completionForSite('site-1')!.name, 'Peter');
    expect(done.completionForSite('site-1')!.at, isNotNull);
  });

  test('KERN: Broadcast erledigt in Laden A → Laden B bleibt offen', () async {
    final provider = _localProvider();
    await provider.updateSession(_admin);
    await provider.saveStoreTask(
      const StoreTask(orgId: 'org-1', title: 'Für alle Läden'), // Broadcast
    );

    // Laden A (site-1) hakt ab.
    await provider.markDoneForSite(provider.tasks.single, 'site-1',
        employeeName: 'A');

    // Laden A: nicht mehr offen. Laden B (site-2): weiterhin offen.
    expect(provider.openStoreTasksForSite('site-1'), isEmpty);
    expect(provider.openStoreTasksForSite('site-2'), hasLength(1));
    expect(provider.tasks.single.isDoneForSite('site-1'), isTrue);
    expect(provider.tasks.single.isDoneForSite('site-2'), isFalse);
  });

  test('reopenForSite entfernt nur den Vermerk dieses Ladens', () async {
    final provider = _localProvider();
    await provider.updateSession(_admin);
    await provider.saveStoreTask(const StoreTask(orgId: 'org-1', title: 'T'));
    final t = provider.tasks.single;
    await provider.markDoneForSite(t, 'site-1', employeeName: 'A');
    await provider.markDoneForSite(provider.tasks.single, 'site-2', employeeName: 'B');
    expect(provider.tasks.single.isDoneForSite('site-1'), isTrue);
    expect(provider.tasks.single.isDoneForSite('site-2'), isTrue);

    await provider.reopenForSite(provider.tasks.single, 'site-1');
    expect(provider.tasks.single.isDoneForSite('site-1'), isFalse);
    expect(provider.tasks.single.isDoneForSite('site-2'), isTrue);
  });

  test('storeTasksForSite: Broadcast überall, Laden-Aufgabe nur im Laden',
      () async {
    final provider = _localProvider();
    await provider.updateSession(_admin);
    await provider.saveStoreTask(
      const StoreTask(orgId: 'org-1', siteId: 'site-1', title: 'Nur Laden 1'),
    );
    await provider.saveStoreTask(
      const StoreTask(orgId: 'org-1', title: 'Für alle Läden'),
    );

    expect(provider.storeTasksForSite('site-1').map((t) => t.title),
        containsAll(['Nur Laden 1', 'Für alle Läden']));
    expect(provider.storeTasksForSite('site-2').map((t) => t.title),
        ['Für alle Läden']);
  });

  test('Löschen entfernt die Aufgabe (Leiter)', () async {
    final provider = _localProvider();
    await provider.updateSession(_admin);
    await provider.saveStoreTask(const StoreTask(orgId: 'org-1', title: 'Weg damit'));
    final id = provider.tasks.single.id!;

    await provider.deleteStoreTask(id);
    expect(provider.tasks, isEmpty);
  });

  test('lokale Persistenz: Aufgaben (inkl. Erledigt-je-Standort) überleben', () async {
    final provider = _localProvider();
    await provider.updateSession(_admin);
    await provider.saveStoreTask(
      const StoreTask(orgId: 'org-1', title: 'Persistiert'),
    );
    await provider.markDoneForSite(provider.tasks.single, 'site-1', employeeName: 'A');

    final reloaded = _localProvider();
    await reloaded.updateSession(_admin);
    expect(reloaded.tasks.single.title, 'Persistiert');
    expect(reloaded.tasks.single.isDoneForSite('site-1'), isTrue);
    expect(reloaded.tasks.single.isDoneForSite('site-2'), isFalse);
  });
}
