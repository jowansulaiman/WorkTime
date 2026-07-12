import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/core/local_demo_data.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/services/auth_service.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

// Tests für die komplette Konto-Löschung (Plan plan/account-loeschung.md),
// Slices 1 & 2 — vollständig offline (kein echtes Firebase, Fake-Invoker).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseService.wipeAllLocalData', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({'fremder_key': 'behalten'});
      DatabaseService.resetCachedPrefs();
    });

    test('entfernt alle App-Daten, lässt fremde Keys stehen', () async {
      const scope = LocalStorageScope(orgId: 'org-1', userId: 'user-1');
      await DatabaseService.saveLocalEntries(
        [
          WorkEntry(
            id: 'e1',
            orgId: 'org-1',
            userId: 'user-1',
            date: DateTime(2026, 4, 1),
            startTime: DateTime(2026, 4, 1, 8),
            endTime: DateTime(2026, 4, 1, 16),
            breakMinutes: 30,
            siteId: 's1',
            siteName: 'Kiel',
          ),
        ],
        scope: scope,
      );
      await DatabaseService.saveLocalUserSettings(
        const UserSettings(name: 'Anna', hourlyRate: 15),
        scope: scope,
      );
      await DatabaseService.saveLocalAuthUserId('user-1');
      await DatabaseService.saveDataStorageLocation('local');

      final before = (await SharedPreferences.getInstance()).getKeys();
      expect(before.any((k) => k.startsWith('local_v2')), isTrue);
      expect(before.contains('local_auth_user_id'), isTrue);

      await DatabaseService.wipeAllLocalData();

      final after = (await SharedPreferences.getInstance()).getKeys();
      expect(
        after.where((k) =>
            k.startsWith('local_v2') ||
            k.startsWith('setting_') ||
            k == 'local_auth_user_id'),
        isEmpty,
      );
      // Fremde (nicht app-eigene) Keys bleiben unberührt.
      expect(after.contains('fremder_key'), isTrue);
      expect(await DatabaseService.loadLocalAuthUserId(), isNull);
    });
  });

  group('FirestoreService.deleteUserAccount (Callable-Seam)', () {
    test('ruft Callable deleteUserAccount mit userId auf', () async {
      String? name;
      Map<String, dynamic>? payload;
      final svc = FirestoreService(
        cloudFunctionInvoker: (n, p) async {
          name = n;
          payload = p;
          return <String, dynamic>{'ok': true};
        },
      );

      await svc.deleteUserAccount('u-42');

      expect(name, 'deleteUserAccount');
      expect(payload?['userId'], 'u-42');
    });

    test('propagiert failed-precondition (Letzter-Admin-Schutz)', () async {
      final svc = FirestoreService(
        cloudFunctionInvoker: (n, p) async {
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'letzter Admin',
          );
        },
      );

      expect(
        () => svc.deleteUserAccount('u-1'),
        throwsA(isA<FirebaseFunctionsException>()),
      );
    });
  });

  group('AuthProvider.deleteOwnAccount (Demo/Offline)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
    });

    test('wiped lokale Daten und meldet ab', () async {
      const scope = LocalStorageScope(orgId: 'main-org', userId: 'x');
      await DatabaseService.saveLocalUserSettings(
        const UserSettings(name: 'X'),
        scope: scope,
      );

      final provider = _LocalAuthProvider(
        authService: AuthService(),
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      );
      await provider.init();
      await provider.signInWithLocalDemoProfile(LocalDemoData.adminAccount.uid);
      expect(provider.isAuthenticated, isTrue);

      // Reauth ist im Demo-Modus ein No-op mit true.
      expect(await provider.reauthenticate(), isTrue);

      final ok = await provider.deleteOwnAccount();

      expect(ok, isTrue);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.profile, isNull);
      final keys = (await SharedPreferences.getInstance()).getKeys();
      expect(
        keys.where((k) =>
            k.startsWith('local_v2') ||
            k.startsWith('setting_') ||
            k == 'local_auth_user_id'),
        isEmpty,
      );
    });
  });
}

class _LocalAuthProvider extends AuthProvider {
  _LocalAuthProvider({
    required super.authService,
    required super.firestoreService,
  });

  @override
  bool get authDisabled => true;
}
