import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/password_entry.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/password_provider.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// PM-M4: Provider gegen einen gefälschten Callable-Invoker. Prüft: Laden über
/// listPasswordEntries, Reveal-Mapping, Copy-Log, Deaktivierung im Local-Modus.
void main() {
  AppUserProfile user() => const AppUserProfile(
        uid: 'u1',
        email: 'u1@example.com',
        role: UserRole.employee,
        orgId: 'org-1',
        isActive: true,
        settings: UserSettings(name: 'Test'),
      );

  late List<String> calls;

  FirestoreService serviceWith(
      Future<dynamic> Function(String, Map<String, dynamic>) invoker) {
    return FirestoreService(
      firestore: FakeFirebaseFirestore(),
      cloudFunctionInvoker: (name, payload) {
        calls.add(name);
        return invoker(name, payload);
      },
    );
  }

  setUp(() => calls = []);

  test('deaktiviert (kein Override) → lädt nichts, ruft keine Callable', () async {
    final fs = serviceWith((_, __) async => {'entries': []});
    final provider = PasswordProvider(firestoreService: fs); // Flag aus (compile)
    await provider.updateSession(user());
    expect(provider.isEnabled, isFalse);
    expect(provider.entries, isEmpty);
    expect(calls, isEmpty);
  });

  test('aktiviert: updateSession lädt sichtbare Metadaten', () async {
    final fs = serviceWith((name, payload) async {
      if (name == 'listPasswordEntries') {
        return {
          'entries': [
            {
              'id': 'e1',
              'orgId': 'org-1',
              'title': 'KVG Portal',
              'category': 'kvg',
              'scope': 'shared',
              'ownerUid': 'admin',
              'hasSecret': true,
              'audienceUids': ['u1'],
            },
          ],
        };
      }
      return <String, dynamic>{};
    });
    final provider =
        PasswordProvider(firestoreService: fs, featureEnabledOverride: true);
    await provider.updateSession(user());
    expect(provider.isEnabled, isTrue);
    expect(provider.entries.length, 1);
    expect(provider.entries.first.title, 'KVG Portal');
    expect(provider.entries.first.category, PasswordCategory.kvg);
    expect(provider.entries.first.hasSecret, isTrue);
    expect(calls, contains('listPasswordEntries'));
  });

  test('local-Modus deaktiviert das Feature trotz Override', () async {
    final fs = serviceWith((_, __) async => {'entries': []});
    final provider =
        PasswordProvider(firestoreService: fs, featureEnabledOverride: true);
    await provider.updateSession(user(), localStorageOnly: true);
    expect(provider.isEnabled, isFalse);
    expect(calls, isEmpty);
  });

  test('reveal mappt die Callable-Antwort auf PasswordSecret', () async {
    final fs = serviceWith((name, payload) async {
      if (name == 'listPasswordEntries') return {'entries': []};
      if (name == 'revealPasswordSecret') {
        expect(payload['entry_id'], 'e1');
        expect(payload['reauth_token'], 'tok');
        return {'username': 'user', 'password': 'geheim', 'notes': 'n'};
      }
      return <String, dynamic>{};
    });
    final provider =
        PasswordProvider(firestoreService: fs, featureEnabledOverride: true);
    await provider.updateSession(user());
    final secret = await provider.reveal('e1', reauthToken: 'tok');
    expect(secret.username, 'user');
    expect(secret.password, 'geheim');
    expect(secret.notes, 'n');
  });

  test('beginReauth liefert Token; logCopy ruft Callable', () async {
    final fs = serviceWith((name, payload) async {
      if (name == 'listPasswordEntries') return {'entries': []};
      if (name == 'beginPasswordReauth') return {'reauth_token': 'nonce'};
      if (name == 'logPasswordCopy') return {'ok': true};
      return <String, dynamic>{};
    });
    final provider =
        PasswordProvider(firestoreService: fs, featureEnabledOverride: true);
    await provider.updateSession(user());
    expect(await provider.beginReauth(), 'nonce');
    await provider.logCopy('e1', field: 'password');
    expect(calls, contains('logPasswordCopy'));
  });

  test('save ruft upsert + lädt neu', () async {
    var upserts = 0;
    final fs = serviceWith((name, payload) async {
      if (name == 'listPasswordEntries') return {'entries': []};
      if (name == 'upsertPasswordEntry') {
        upserts++;
        expect(payload['plain_password'], 'pw');
        return {'entry_id': 'e9'};
      }
      return <String, dynamic>{};
    });
    final provider =
        PasswordProvider(firestoreService: fs, featureEnabledOverride: true);
    await provider.updateSession(user());
    await provider.save(
      entry: const PasswordEntry(orgId: 'org-1', title: 'Neu', ownerUid: 'u1'),
      plainPassword: 'pw',
    );
    expect(upserts, 1);
    // nach save: erneutes listPasswordEntries (refresh)
    expect(calls.where((c) => c == 'listPasswordEntries').length, greaterThan(1));
  });
}
