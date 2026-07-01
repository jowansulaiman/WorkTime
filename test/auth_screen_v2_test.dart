import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/core/local_demo_data.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/screens/auth_screen_v2.dart';
import 'package:worktime_app/services/auth_service.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/theme/app_theme.dart';

/// Kontrollierbares AuthProvider-Double: ueberschreibt die Zustands-Getter und
/// zeichnet die Aktions-Aufrufe auf, ohne echtes Firebase zu beruehren.
class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider({this.authDisabledOverride = false})
      : super(
          authService: AuthService(),
          firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
        );

  final bool authDisabledOverride;
  bool busyOverride = false;
  String? errorOverride;

  final List<String> calls = <String>[];
  String? lastDemoUid;
  String? lastLoginEmail;
  String? lastLoginPassword;
  String? lastActivateEmail;

  @override
  bool get authDisabled => authDisabledOverride;
  @override
  bool get busy => busyOverride;
  @override
  String? get errorMessage => errorOverride;

  @override
  Future<void> signInWithGoogle() async => calls.add('google');

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    calls.add('emailLogin');
    lastLoginEmail = email;
    lastLoginPassword = password;
  }

  @override
  Future<void> signInWithLocalDemoProfile(String uid) async {
    calls.add('demo');
    lastDemoUid = uid;
  }

  @override
  Future<void> activateInvite({
    required String email,
    required String password,
  }) async {
    calls.add('activate');
    lastActivateEmail = email;
  }

  @override
  Future<void> signOut() async => calls.add('signout');

  @override
  void clearError() {
    calls.add('clearError');
    errorOverride = null;
    notifyListeners();
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeAuthProvider auth,
  Widget screen,
) async {
  await tester.binding.setSurfaceSize(const Size(520, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: MaterialApp(theme: AppTheme.lightV2, home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  group('AuthScreenV2 — Demo-Modus', () {
    testWidgets('zeigt Demo-Badge, Demo-Profile und Demo-Submit-Label',
        (tester) async {
      final auth = _FakeAuthProvider(authDisabledOverride: true);
      await _pump(tester, auth, const AuthScreenV2());

      expect(find.text('Demo-Zugang'), findsOneWidget);
      expect(find.text('Lokale Demo-Profile'), findsOneWidget);
      expect(find.text('Mit Demo-Account anmelden'), findsOneWidget);
      // kein Google-Button im Demo-Modus
      expect(find.text('Mit Google anmelden'), findsNothing);
    });

    testWidgets('Demo-Tile ruft signInWithLocalDemoProfile mit uid',
        (tester) async {
      final auth = _FakeAuthProvider(authDisabledOverride: true);
      await _pump(tester, auth, const AuthScreenV2());

      final account = LocalDemoData.accounts.first;
      await tester.tap(find.text('Als ${account.role.label} anmelden').first);
      await tester.pump();

      expect(auth.calls, contains('demo'));
      expect(auth.lastDemoUid, account.uid);
    });
  });

  group('AuthScreenV2 — echter Modus', () {
    testWidgets('zeigt Sicherer-Zugang-Badge + Google-Button', (tester) async {
      final auth = _FakeAuthProvider();
      await _pump(tester, auth, const AuthScreenV2());
      expect(find.text('Sicherer Zugang'), findsOneWidget);
      expect(find.text('Mit Google anmelden'), findsOneWidget);
    });

    testWidgets('Google-Button ruft signInWithGoogle', (tester) async {
      final auth = _FakeAuthProvider();
      await _pump(tester, auth, const AuthScreenV2());
      await tester.tap(find.text('Mit Google anmelden'));
      await tester.pump();
      expect(auth.calls, contains('google'));
    });

    testWidgets('Login mit gueltigen Daten ruft signInWithEmailPassword',
        (tester) async {
      final auth = _FakeAuthProvider();
      await _pump(tester, auth, const AuthScreenV2());

      await tester.enterText(
          find.byType(TextFormField).at(0), 'chef@laden.test');
      await tester.enterText(find.byType(TextFormField).at(1), 'geheim123');
      await tester.tap(find.text('Mit E-Mail anmelden'));
      await tester.pump();

      expect(auth.calls, contains('emailLogin'));
      expect(auth.lastLoginEmail, 'chef@laden.test');
      expect(auth.lastLoginPassword, 'geheim123');
    });

    testWidgets('ungueltige E-Mail zeigt Validierungsfehler, kein Call',
        (tester) async {
      final auth = _FakeAuthProvider();
      await _pump(tester, auth, const AuthScreenV2());

      await tester.enterText(find.byType(TextFormField).at(0), 'keine-mail');
      await tester.enterText(find.byType(TextFormField).at(1), 'x');
      await tester.tap(find.text('Mit E-Mail anmelden'));
      await tester.pump();

      expect(find.text('Bitte eine gueltige E-Mail-Adresse eingeben'),
          findsOneWidget);
      expect(auth.calls, isNot(contains('emailLogin')));
    });

    testWidgets('Einladung-Segment wechselt zum Aktivierungsformular + Call',
        (tester) async {
      final auth = _FakeAuthProvider();
      await _pump(tester, auth, const AuthScreenV2());

      await tester.tap(find.text('Einladung'));
      await tester.pumpAndSettle();

      expect(find.text('Einladung aktivieren'), findsOneWidget);
      // Aktivierungsformular hat genau 3 Felder (E-Mail, Passwort, Bestaetigen).
      expect(find.byType(TextFormField), findsNWidgets(3));

      await tester.enterText(
          find.byType(TextFormField).at(0), 'neu@laden.test');
      await tester.enterText(find.byType(TextFormField).at(1), 'geheim123');
      await tester.enterText(find.byType(TextFormField).at(2), 'geheim123');
      await tester.tap(find.text('Einladung aktivieren'));
      await tester.pump();

      expect(auth.calls, contains('activate'));
      expect(auth.lastActivateEmail, 'neu@laden.test');
    });

    testWidgets('nicht uebereinstimmende Passwoerter blockieren Aktivierung',
        (tester) async {
      final auth = _FakeAuthProvider();
      await _pump(tester, auth, const AuthScreenV2());
      await tester.tap(find.text('Einladung'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField).at(0), 'neu@laden.test');
      await tester.enterText(find.byType(TextFormField).at(1), 'geheim123');
      await tester.enterText(find.byType(TextFormField).at(2), 'anders123');
      await tester.tap(find.text('Einladung aktivieren'));
      await tester.pump();

      expect(find.text('Passwoerter stimmen nicht ueberein'), findsOneWidget);
      expect(auth.calls, isNot(contains('activate')));
    });
  });

  group('AuthScreenV2 — Fehlerbanner', () {
    testWidgets('zeigt errorMessage und Dismiss ruft clearError',
        (tester) async {
      final auth = _FakeAuthProvider()..errorOverride = 'Anmeldung fehlgeschlagen';
      await _pump(tester, auth, const AuthScreenV2());

      expect(find.text('Anmeldung fehlgeschlagen'), findsOneWidget);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
      await tester.pump();
      expect(auth.calls, contains('clearError'));
    });
  });

  group('AuthScreenV2 — Mobile-Modernisierung', () {
    testWidgets('Passwort ist verborgen; Toggle schaltet Sichtbarkeit um',
        (tester) async {
      final auth = _FakeAuthProvider();
      await _pump(tester, auth, const AuthScreenV2());

      // Feld 1 (EditableText) = Passwort, initial verborgen.
      EditableText passwordField() =>
          tester.widget<EditableText>(find.byType(EditableText).at(1));
      expect(passwordField().obscureText, isTrue);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();

      expect(passwordField().obscureText, isFalse);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });

    testWidgets('Enter im Passwortfeld loest den Login aus', (tester) async {
      final auth = _FakeAuthProvider();
      await _pump(tester, auth, const AuthScreenV2());

      await tester.enterText(
          find.byType(TextFormField).at(0), 'chef@laden.test');
      await tester.enterText(find.byType(TextFormField).at(1), 'geheim123');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(auth.calls, contains('emailLogin'));
      expect(auth.lastLoginEmail, 'chef@laden.test');
    });

    testWidgets('Google-Button nur im Login-Tab, nicht bei Einladung',
        (tester) async {
      final auth = _FakeAuthProvider();
      await _pump(tester, auth, const AuthScreenV2());
      expect(find.text('Mit Google anmelden'), findsOneWidget);

      await tester.tap(find.text('Einladung'));
      await tester.pumpAndSettle();
      expect(find.text('Mit Google anmelden'), findsNothing);
    });
  });

  group('AccessBlockedScreenV2 + FirebaseSetupScreenV2', () {
    testWidgets('AccessBlocked: Abmelden ruft signOut', (tester) async {
      final auth = _FakeAuthProvider();
      await _pump(tester, auth, const AccessBlockedScreenV2());
      expect(find.text('Konto deaktiviert'), findsOneWidget);
      await tester.tap(find.text('Abmelden'));
      await tester.pump();
      expect(auth.calls, contains('signout'));
    });

    testWidgets('FirebaseSetup zeigt Hinweistext', (tester) async {
      final auth = _FakeAuthProvider();
      await _pump(tester, auth, const FirebaseSetupScreenV2());
      expect(find.text('Anmeldung derzeit nicht verfuegbar'), findsOneWidget);
    });
  });
}
