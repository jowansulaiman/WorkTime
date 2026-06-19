import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/feature_flag_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  const user = AppUserProfile(
    uid: 'owner-1',
    orgId: 'org-1',
    email: 'owner@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Inhaber'),
  );

  late FakeFirebaseFirestore firestore;
  late FirestoreService firestoreService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    firestore = FakeFirebaseFirestore();
    firestoreService = FirestoreService(firestore: firestore);
  });

  Future<void> seedConfig(Map<String, dynamic> data) {
    return firestore
        .collection('organizations')
        .doc('org-1')
        .collection('config')
        .doc('appFlags')
        .set(data);
  }

  test('liest Mindest-Build + Flags und fordert Update bei zu altem Build',
      () async {
    await seedConfig({
      'minimumBuildNumber': 5,
      'updateMessage': 'Bitte aktualisieren',
      'featureFlags': {'neuesModul': true, 'altesModul': false},
    });
    final provider = FeatureFlagProvider(
      firestoreService: firestoreService,
      currentBuildNumber: 3,
    );

    await provider.updateSession(user, localStorageOnly: false);

    expect(provider.minimumBuildNumber, 5);
    expect(provider.requiresUpdate, isTrue);
    expect(provider.updateMessage, 'Bitte aktualisieren');
    expect(provider.isEnabled('neuesModul'), isTrue);
    expect(provider.isEnabled('altesModul'), isFalse);
    expect(provider.isEnabled('unbekannt', fallback: true), isTrue);
  });

  test('aktueller Build >= Mindest-Build -> kein Force-Update', () async {
    await seedConfig({'minimumBuildNumber': 5});
    final provider = FeatureFlagProvider(
      firestoreService: firestoreService,
      currentBuildNumber: 10,
    );

    await provider.updateSession(user, localStorageOnly: false);

    expect(provider.minimumBuildNumber, 5);
    expect(provider.requiresUpdate, isFalse);
  });

  test('lokaler Modus liest keine Remote-Config (kein Force-Update)', () async {
    await seedConfig({'minimumBuildNumber': 99});
    final provider = FeatureFlagProvider(
      firestoreService: firestoreService,
      currentBuildNumber: 3,
    );

    await provider.updateSession(user, localStorageOnly: true);

    expect(provider.minimumBuildNumber, 0);
    expect(provider.requiresUpdate, isFalse);
  });

  test('fehlendes Config-Doc ist fail-open (kein Block)', () async {
    final provider = FeatureFlagProvider(
      firestoreService: firestoreService,
      currentBuildNumber: 3,
    );

    await provider.updateSession(user, localStorageOnly: false);

    expect(provider.minimumBuildNumber, 0);
    expect(provider.requiresUpdate, isFalse);
  });
}
