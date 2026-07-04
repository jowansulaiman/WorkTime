import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/personal_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/screens/personal/employee_detail_screen.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/theme/app_theme.dart';

import 'support/router_harness.dart' show FakeAuthProvider;

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

/// Tab-Reihenfolge, die exakt AllTecs `EmployeeDetailPage` spiegeln muss.
const _expectedTabs = <String>[
  'Übersicht',
  'Stammdaten',
  'Gehalt',
  'Qualifikationen',
  'Ausbildungen',
  'Kinder',
  'Dokumente',
  'Notizen',
  'Verwalten',
];

Future<void> _pump(
  WidgetTester tester, {
  required AppUserProfile viewer,
  required String userId,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final firestore = FakeFirebaseFirestore();
  final service = FirestoreService(firestore: firestore);
  final auth = FakeAuthProvider(firestoreService: service, profile: viewer);
  final team =
      TeamProvider(firestoreService: service, disableAuthentication: true);
  final personal =
      PersonalProvider(firestoreService: service, disableAuthentication: true);
  addTearDown(team.dispose);
  addTearDown(personal.dispose);

  // Lokaler Modus setzt members = [viewer]; wir öffnen die Detailseite des
  // Sitzungsnutzers (self), damit ein Mitglied gefunden wird.
  await team.updateSession(viewer, localStorageOnly: true);
  await personal.updateSession(viewer, localStorageOnly: true);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<TeamProvider>.value(value: team),
        ChangeNotifierProvider<PersonalProvider>.value(value: personal),
      ],
      child: MaterialApp(
        theme: AppTheme.resolveLight(useV2: true),
        home: EmployeeDetailScreen(userId: userId),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    await initializeDateFormatting('de_DE');
  });

  testWidgets('zeigt genau die 9 AllTec-Tabs in korrekter Reihenfolge',
      (tester) async {
    await _pump(tester, viewer: _admin, userId: 'admin-1');

    expect(find.byType(Tab), findsNWidgets(9));
    for (final label in _expectedTabs) {
      // Auf den Tab selbst prüfen (der aktive Tab rendert seinen Namen zusätzlich
      // im Platzhalter-Inhalt → `find.text` wäre mehrdeutig).
      expect(find.widgetWithText(Tab, label), findsOneWidget,
          reason: 'Tab „$label" fehlt');
    }
    // Kopf-Visitenkarte zeigt den Namen.
    expect(find.text('Sandra'), findsWidgets);
  });

  testWidgets('Nicht-Admin sieht nur den Zugriffshinweis (kein Tab)',
      (tester) async {
    await _pump(tester, viewer: _employee, userId: 'emp-1');

    expect(find.text('Nur für Administratoren.'), findsOneWidget);
    expect(find.byType(Tab), findsNothing);
  });
}
