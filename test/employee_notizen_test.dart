import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/employee_note.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/personal_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/screens/personal/tabs/employee_notizen_tab.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/theme/app_theme.dart';

const _admin = AppUserProfile(
  uid: 'admin-1',
  orgId: 'org-1',
  email: 'admin@example.com',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Sandra'),
);

Future<PersonalProvider> _pumpTab(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 2200);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final service = FirestoreService(firestore: FakeFirebaseFirestore());
  final personal =
      PersonalProvider(firestoreService: service, disableAuthentication: true);
  final team =
      TeamProvider(firestoreService: service, disableAuthentication: true);
  addTearDown(personal.dispose);
  addTearDown(team.dispose);
  await personal.updateSession(_admin, localStorageOnly: true);
  await team.updateSession(_admin, localStorageOnly: true);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PersonalProvider>.value(value: personal),
        ChangeNotifierProvider<TeamProvider>.value(value: team),
      ],
      child: MaterialApp(
        theme: AppTheme.resolveLight(useV2: true),
        home: const Scaffold(body: EmployeeNotizenTab(userId: 'admin-1')),
      ),
    ),
  );
  await tester.pump();
  return personal;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    await initializeDateFormatting('de_DE');
  });

  group('EmployeeNote Serialisierung', () {
    EmployeeNote sample() => EmployeeNote(
          orgId: 'org-1',
          userId: 'emp-1',
          text: 'Zuverlässig, gerne Frühschicht.',
          createdByUid: 'admin-1',
          createdAt: DateTime(2026, 7, 4, 9, 30),
        );

    test('lokaler Round-Trip (snake_case)', () {
      final r = EmployeeNote.fromMap(sample().toMap());
      expect(r.orgId, 'org-1');
      expect(r.userId, 'emp-1');
      expect(r.text, 'Zuverlässig, gerne Frühschicht.');
      expect(r.createdByUid, 'admin-1');
      expect(r.createdAt, DateTime(2026, 7, 4, 9, 30));
    });

    test('Firestore Round-Trip (camelCase + Timestamp)', () async {
      final fs = FakeFirebaseFirestore();
      final ref = fs.collection('employeeNotes').doc();
      await ref.set(sample().toFirestoreMap());
      final snap = await ref.get();
      final r = EmployeeNote.fromFirestore(snap.id, snap.data()!);
      expect(r.id, ref.id);
      expect(r.text, 'Zuverlässig, gerne Frühschicht.');
      expect(r.userId, 'emp-1');
    });
  });

  group('PersonalProvider Notizen', () {
    testWidgets('addNote → Liste + deleteNote leert wieder', (tester) async {
      final personal = await _pumpTab(tester);

      expect(find.text('0 Notizen'), findsOneWidget);
      expect(find.text('Keine Notizen vorhanden'), findsOneWidget);

      await personal.addNote('admin-1', 'Testnotiz für Sandra');
      await tester.pump();
      expect(find.text('1 Notizen'), findsOneWidget);
      expect(find.text('Testnotiz für Sandra'), findsOneWidget);

      final note = personal.notesForUser('admin-1').single;
      await personal.deleteNote(note.id!);
      await tester.pump();
      expect(find.text('0 Notizen'), findsOneWidget);
      expect(find.text('Keine Notizen vorhanden'), findsOneWidget);
    });
  });
}
