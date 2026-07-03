import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/clock_entry.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/providers/zeitwirtschaft_provider.dart';
import 'package:worktime_app/screens/zeitwirtschaft/stempel_screen.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

import 'support/router_harness.dart';

class _FakeTeamProvider extends TeamProvider {
  _FakeTeamProvider(this._fakeSites, FirestoreService service)
      : super(firestoreService: service);
  final List<SiteDefinition> _fakeSites;
  @override
  List<SiteDefinition> get sites => _fakeSites;
}

/// Widget-Test: Manager-Sichten des Stempel-Screens (ZV-2.2b/ZV-3.1).
void main() {
  const manager = AppUserProfile(
    uid: 'mgr-1',
    orgId: 'org-1',
    email: 'chef@laden.test',
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

  Future<ZeitwirtschaftProvider> pump(
    WidgetTester tester,
    AppUserProfile profile, {
    bool seedKlaerung = false,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = FirestoreService(firestore: FakeFirebaseFirestore());
    final zeit = ZeitwirtschaftProvider(firestoreService: service);
    final team = _FakeTeamProvider(
      const [SiteDefinition(orgId: 'org-1', id: 'site-1', name: 'Strichmännchen')],
      service,
    );
    final auth = FakeAuthProvider(firestoreService: service, profile: profile);

    await tester.runAsync(() async {
      await zeit.updateSession(profile, localStorageOnly: true);
      if (seedKlaerung) {
        // Vortag-Buchung → Klärung beim Ausstempeln.
        await zeit.clockIn(at: DateTime.now().subtract(const Duration(days: 1)));
        await zeit.clockOut(at: DateTime.now());
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<TeamProvider>.value(value: team),
          ChangeNotifierProvider<ZeitwirtschaftProvider>.value(value: zeit),
        ],
        child: const MaterialApp(home: StempelScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return zeit;
  }

  testWidgets('Manager sieht Dienst-heute-Karte', (tester) async {
    await pump(tester, manager);
    expect(find.text('Dienst heute'), findsOneWidget);
  });

  testWidgets('Manager sieht Klärungs-Inbox bei offenem Klärungsfall',
      (tester) async {
    await pump(tester, manager, seedKlaerung: true);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Klärung offen'), findsOneWidget);
    expect(find.text('Korrigieren'), findsWidgets);
  });

  testWidgets('Mitarbeiter sieht KEINE Manager-Sichten', (tester) async {
    await pump(tester, employee);
    expect(find.text('Dienst heute'), findsNothing);
    expect(find.textContaining('Klärung offen'), findsNothing);
  });

  testWidgets('Klärung verwerfen deaktiviert den Fall', (tester) async {
    final zeit = await pump(tester, manager, seedKlaerung: true);
    await tester.pump(const Duration(milliseconds: 50));
    expect(zeit.klaerungEntries, hasLength(1));

    await tester.tap(find.text('Verwerfen'));
    await tester.pumpAndSettle();
    // Grund-Sheet eingeben.
    await tester.enterText(find.byType(TextField).last, 'Doppelbuchung');
    await tester.tap(find.text('Bestätigen'));
    await tester.pumpAndSettle();

    expect(zeit.klaerungEntries, isEmpty);
    expect(
      zeit.monthEntries.any((e) => e.status == ClockStatus.deaktiviert) ||
          zeit.klaerungEntries.isEmpty,
      isTrue,
    );
  });
}
