import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/work_provider.dart';
import 'package:worktime_app/screens/zeitwirtschaft/zeitwirtschaft_hub_screen.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// Widget-Test: rollengerechte Hub-Gruppen (ZV-6.2).
void main() {
  const admin = AppUserProfile(
    uid: 'admin-1',
    orgId: 'org-1',
    email: 'admin@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Chef'),
  );
  const employee = AppUserProfile(
    uid: 'emp-1',
    orgId: 'org-1',
    email: 'peter@laden.test',
    role: UserRole.employee,
    isActive: true,
    settings: UserSettings(name: 'Peter'),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    await initializeDateFormatting('de_DE');
  });

  Future<void> pump(WidgetTester tester, AppUserProfile profile) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = FirestoreService(firestore: FakeFirebaseFirestore());
    final work = WorkProvider(firestoreService: service);
    addTearDown(work.dispose);
    await tester.runAsync(() async {
      await work.updateSession(profile, localStorageOnly: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WorkProvider>.value(value: work),
        ],
        child: const MaterialApp(home: Scaffold(body: ZeitwirtschaftHubScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('Admin sieht alle drei Gruppen inkl. Team & Abschluss',
      (tester) async {
    await pump(tester, admin);
    expect(find.text('Mein Tag'), findsOneWidget);
    expect(find.text('Meine Konten'), findsOneWidget);
    expect(find.text('Team & Abschluss'), findsOneWidget);
    expect(find.text('Mitarbeiterabschluss'), findsOneWidget);
    expect(find.text('Lohnlauf'), findsOneWidget);
  });

  testWidgets('Mitarbeiter sieht KEINE Team & Abschluss-Gruppe',
      (tester) async {
    await pump(tester, employee);
    expect(find.text('Mein Tag'), findsOneWidget);
    expect(find.text('Meine Konten'), findsOneWidget);
    expect(find.text('Team & Abschluss'), findsNothing);
    expect(find.text('Mitarbeiterabschluss'), findsNothing);
    expect(find.text('Lohnlauf'), findsNothing);
    // Eigene Kacheln bleiben sichtbar.
    expect(find.text('Kommen und Gehen'), findsOneWidget);
  });
}
