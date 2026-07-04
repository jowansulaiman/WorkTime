import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/password_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/screens/passwords_screen.dart';
import 'package:worktime_app/services/firestore_service.dart';

import 'support/router_harness.dart';

class _FakeTeamProvider extends TeamProvider {
  _FakeTeamProvider(FirestoreService service)
      : super(firestoreService: service);
  @override
  List<SiteDefinition> get sites =>
      const [SiteDefinition(orgId: 'org-1', id: 'site-1', name: 'Kiel')];
  @override
  List<AppUserProfile> get members => const [];
}

/// PM-M5: Widget-Test des Passwörter-Screens — Liste ohne Klartext + Reveal-Flow.
void main() {
  const employee = AppUserProfile(
    uid: 'u1',
    orgId: 'org-1',
    email: 'peter@laden.test',
    role: UserRole.employee,
    isActive: true,
    settings: UserSettings(name: 'Peter'),
  );

  Future<PasswordProvider> pump(
    WidgetTester tester,
    Future<dynamic> Function(String, Map<String, dynamic>) invoker,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fs = FakeFirebaseFirestore();
    final service =
        FirestoreService(firestore: fs, cloudFunctionInvoker: invoker);
    final provider = PasswordProvider(
        firestoreService: service, featureEnabledOverride: true);
    await tester.runAsync(() async {
      await provider.updateSession(employee);
    });
    final auth = FakeAuthProvider(firestoreService: service, profile: employee);
    final team = _FakeTeamProvider(service);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<TeamProvider>.value(value: team),
        ChangeNotifierProvider<PasswordProvider>.value(value: provider),
      ],
      child: const MaterialApp(home: PasswordsScreen()),
    ));
    await tester.pumpAndSettle();
    return provider;
  }

  Map<String, dynamic> entryMap() => {
        'id': 'e1',
        'orgId': 'org-1',
        'title': 'KVG Portal',
        'category': 'kvg',
        'scope': 'personal',
        'ownerUid': 'u1',
        'hasSecret': true,
      };

  testWidgets('zeigt Einträge ohne Klartext', (tester) async {
    await pump(tester, (name, payload) async {
      if (name == 'listPasswordEntries') {
        return {'entries': [entryMap()]};
      }
      return <String, dynamic>{};
    });
    expect(find.text('KVG Portal'), findsOneWidget);
    // Kein Klartext-Passwort in der Liste.
    expect(find.textContaining('geheim'), findsNothing);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });

  testWidgets('Reveal-Flow: Bestätigung → Secret-Sheet mit Klartext',
      (tester) async {
    await pump(tester, (name, payload) async {
      switch (name) {
        case 'listPasswordEntries':
          return {'entries': [entryMap()]};
        case 'beginPasswordReauth':
          return {'reauth_token': 'nonce'};
        case 'revealPasswordSecret':
          expect(payload['reauth_token'], 'nonce');
          return {'username': 'kvg-user', 'password': 'geheim', 'notes': ''};
      }
      return <String, dynamic>{};
    });

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    // Sicherheitsbestätigung.
    expect(find.text('Passwort anzeigen'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Anzeigen'));
    await tester.pumpAndSettle();

    // Secret-Sheet zeigt Klartext + Auto-Hide-Hinweis.
    expect(find.text('geheim'), findsOneWidget);
    expect(find.text('kvg-user'), findsOneWidget);
    expect(find.textContaining('automatisch ausgeblendet'), findsOneWidget);
  });
}
