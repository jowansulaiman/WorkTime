import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/core/redesign_flags.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/feature_flag_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/theme/app_theme.dart';

/// Schritt 2 (Theme-Flip): verifiziert die Komposition aus main.dart end-to-end
/// auf Logik-Ebene — org-Flag `redesign_v2` -> FeatureFlagProvider ->
/// RedesignFlags.resolve -> AppTheme.resolveLight/Dark. Ohne dart-define ist der
/// Dev-Override compile-time false, also entscheidet hier allein das Server-Flag.
void main() {
  const navy = Color(0xFF244A66); // V1-Leitfarbe
  const teal = Color(0xFF0E7C7B); // V2-Leitfarbe (hell)

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

  // Spiegelt _resolveUseV2 aus main.dart (private dort).
  bool useV2(FeatureFlagProvider flags) => RedesignFlags.resolve(
        serverFlag: flags.isEnabled(RedesignFlags.flagKey, fallback: false),
      );

  test('org-Flag redesign_v2=true schaltet das Theme auf Teal', () async {
    await seedConfig({
      'featureFlags': {'redesign_v2': true},
    });
    final provider = FeatureFlagProvider(firestoreService: firestoreService);

    await provider.updateSession(user, localStorageOnly: false);

    expect(useV2(provider), isTrue);
    expect(AppTheme.resolveLight(useV2: useV2(provider)).colorScheme.primary,
        teal);
  });

  test('org-Flag redesign_v2=false bleibt bei V1 (Navy)', () async {
    await seedConfig({
      'featureFlags': {'redesign_v2': false},
    });
    final provider = FeatureFlagProvider(firestoreService: firestoreService);

    await provider.updateSession(user, localStorageOnly: false);

    expect(useV2(provider), isFalse);
    expect(AppTheme.resolveLight(useV2: useV2(provider)).colorScheme.primary,
        navy);
  });

  test('fehlendes Flag -> Fallback false -> V1', () async {
    await seedConfig({'minimumBuildNumber': 1});
    final provider = FeatureFlagProvider(firestoreService: firestoreService);

    await provider.updateSession(user, localStorageOnly: false);

    expect(useV2(provider), isFalse);
    expect(AppTheme.resolveLight(useV2: useV2(provider)).colorScheme.primary,
        navy);
  });

  test('lokaler/Offline-Modus rendert deterministisch V1 (kein Remote-Read)',
      () async {
    await seedConfig({
      'featureFlags': {'redesign_v2': true},
    });
    final provider = FeatureFlagProvider(firestoreService: firestoreService);

    // localStorageOnly -> Provider liest keine Remote-Config, Flag bleibt false.
    await provider.updateSession(user, localStorageOnly: true);

    expect(useV2(provider), isFalse);
    expect(AppTheme.resolveDark(useV2: useV2(provider)).colorScheme.primary,
        const Color(0xFF9FC2DB)); // V1-Dunkel-Leitfarbe
  });

  // Deckt die Lese-Mechanik ab, die der _AuthGate-Chooser nutzt
  // (context.watch<FeatureFlagProvider> via RedesignFlags.isOn).
  testWidgets('RedesignFlags.isOn liest das org-Flag im Widget-Baum',
      (tester) async {
    await seedConfig({
      'featureFlags': {'redesign_v2': true},
    });
    final provider = FeatureFlagProvider(firestoreService: firestoreService);
    await provider.updateSession(user, localStorageOnly: false);

    late bool onValue;
    await tester.pumpWidget(
      ChangeNotifierProvider<FeatureFlagProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              onValue = RedesignFlags.isOn(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(onValue, isTrue);
  });

  testWidgets('RedesignFlags.isOn ist false ohne Flag', (tester) async {
    final provider = FeatureFlagProvider(firestoreService: firestoreService);
    await provider.updateSession(user, localStorageOnly: false);

    late bool onValue;
    await tester.pumpWidget(
      ChangeNotifierProvider<FeatureFlagProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              onValue = RedesignFlags.isOn(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(onValue, isFalse);
  });
}
