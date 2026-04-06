import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/core/local_demo_data.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/services/auth_service.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthProvider local demo mode', () {
    late FirestoreService firestoreService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
      firestoreService = FirestoreService(
        firestore: FakeFirebaseFirestore(),
      );
    });

    test('starts signed out when no local demo session exists', () async {
      final provider = _LocalAuthProvider(
        authService: AuthService(),
        firestoreService: firestoreService,
      );

      await provider.init();

      expect(provider.initialized, isTrue);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.profile, isNull);
    });

    test('signs in employee demo account and restores persisted session',
        () async {
      final provider = _LocalAuthProvider(
        authService: AuthService(),
        firestoreService: firestoreService,
      );

      await provider.init();
      await provider.signInWithEmailPassword(
        email: LocalDemoData.employeeAccount.email,
        password: LocalDemoData.employeeAccount.password,
      );

      expect(provider.isAuthenticated, isTrue);
      expect(provider.profile?.uid, LocalDemoData.employeeAccount.uid);
      expect(
        await DatabaseService.loadLocalAuthUserId(),
        LocalDemoData.employeeAccount.uid,
      );

      final restored = _LocalAuthProvider(
        authService: AuthService(),
        firestoreService: firestoreService,
      );
      await restored.init();

      expect(restored.isAuthenticated, isTrue);
      expect(restored.profile?.uid, LocalDemoData.employeeAccount.uid);
      expect(restored.profile?.role.label, 'Mitarbeiter');
    });

    test('signs in teamlead demo account with planning permissions', () async {
      final provider = _LocalAuthProvider(
        authService: AuthService(),
        firestoreService: firestoreService,
      );

      await provider.init();
      await provider.signInWithEmailPassword(
        email: LocalDemoData.teamLeadAccount.email,
        password: LocalDemoData.teamLeadAccount.password,
      );

      expect(provider.isAuthenticated, isTrue);
      expect(provider.profile?.uid, LocalDemoData.teamLeadAccount.uid);
      expect(provider.profile?.role, UserRole.teamlead);
      expect(provider.profile?.canManageShifts, isTrue);
    });

    test('clears local demo session on sign out', () async {
      final provider = _LocalAuthProvider(
        authService: AuthService(),
        firestoreService: firestoreService,
      );

      await provider.init();
      await provider.signInWithLocalDemoProfile(LocalDemoData.adminAccount.uid);
      await provider.signOut();

      expect(provider.isAuthenticated, isFalse);
      expect(provider.profile, isNull);
      expect(await DatabaseService.loadLocalAuthUserId(), isNull);
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
