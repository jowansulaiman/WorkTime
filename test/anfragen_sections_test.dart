import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/absence_request.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/providers/schedule_provider.dart';
import 'package:worktime_app/screens/notification_screen.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/theme/app_theme.dart';

import 'support/router_harness.dart';

/// Belegt die neue Bereichs-Gliederung der Anfragen-Inbox: statt einer flachen,
/// nach Datum sortierten Liste landen Vorgänge in „Zu erledigen" (Entscheidung
/// nötig), „Läuft & wartet" und „Verlauf & Hinweise".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  const employee = AppUserProfile(
    uid: 'employee-1',
    orgId: 'org-1',
    email: 'employee@example.com',
    role: UserRole.employee,
    isActive: true,
    settings: UserSettings(name: 'Mira'),
  );

  const manager = AppUserProfile(
    uid: 'admin-1',
    orgId: 'org-1',
    email: 'admin@example.com',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Chefin'),
  );

  AbsenceRequest vacationFor(String uid, String name) => AbsenceRequest(
        orgId: 'org-1',
        userId: uid,
        employeeName: name,
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 3),
        type: AbsenceType.vacation,
      );

  Future<void> pumpInbox(
    WidgetTester tester, {
    required ScheduleProvider schedule,
    required InventoryProvider inventory,
    required AuthProvider auth,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ScheduleProvider>.value(value: schedule),
          ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: NotificationScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'eigener offener Antrag → „Läuft & wartet"; „Zu erledigen" ist leer',
    (tester) async {
      final firestore = FirestoreService(firestore: FakeFirebaseFirestore());
      final schedule = ScheduleProvider(
        firestoreService: firestore,
        disableAuthentication: true,
      );
      await schedule.updateSession(employee);
      await schedule.submitAbsenceRequest(vacationFor('employee-1', 'Mira'));

      final inventory = InventoryProvider(
        firestoreService: firestore,
        disableAuthentication: true,
      );
      await inventory.updateSession(employee);

      await pumpInbox(
        tester,
        schedule: schedule,
        inventory: inventory,
        auth: FakeAuthProvider(
          firestoreService: firestore,
          profile: employee,
        ),
      );

      // Primärbereich ist immer sichtbar – hier ohne Entscheidung → ruhige
      // Erfolgsmeldung statt Karten.
      expect(find.text('Zu erledigen'), findsOneWidget);
      expect(
        find.text('Alles erledigt – nichts wartet auf deine Entscheidung.'),
        findsOneWidget,
      );
      // Der eigene offene Antrag steckt im Sekundärbereich.
      expect(find.text('Läuft & wartet'), findsOneWidget);
      // Erledigte Infos gibt es (noch) keine.
      expect(find.text('Verlauf & Hinweise'), findsNothing);
    },
  );

  testWidgets(
    'Manager sieht fremden offenen Antrag in „Zu erledigen"',
    (tester) async {
      final firestore = FirestoreService(firestore: FakeFirebaseFirestore());
      final schedule = ScheduleProvider(
        firestoreService: firestore,
        disableAuthentication: true,
      );
      // Antrag als Mitarbeiter einreichen, danach Sitzung auf die Chefin
      // umstellen (gleiche Org, org-skopierte lokale Collection).
      await schedule.updateSession(employee);
      await schedule.submitAbsenceRequest(vacationFor('employee-1', 'Mira'));
      await schedule.updateSession(manager);

      final inventory = InventoryProvider(
        firestoreService: firestore,
        disableAuthentication: true,
      );
      await inventory.updateSession(manager);

      await pumpInbox(
        tester,
        schedule: schedule,
        inventory: inventory,
        auth: FakeAuthProvider(
          firestoreService: firestore,
          profile: manager,
        ),
      );

      expect(find.text('Zu erledigen'), findsOneWidget);
      // Es liegt eine echte Entscheidung an → keine Erledigt-Meldung.
      expect(
        find.text('Alles erledigt – nichts wartet auf deine Entscheidung.'),
        findsNothing,
      );
      // Review-Aktionen am Vorgang.
      expect(find.text('Genehmigen'), findsOneWidget);
      expect(find.text('Ablehnen'), findsOneWidget);
    },
  );
}
