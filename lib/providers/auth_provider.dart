import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/app_config.dart';
import '../core/local_demo_data.dart';
import '../firebase_options.dart';
import '../models/app_user.dart';
import '../models/notification_prefs.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../core/app_logger.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({
    required AuthService authService,
    required FirestoreService firestoreService,
  })  : _authService = authService,
        _firestoreService = firestoreService;

  final AuthService _authService;
  final FirestoreService _firestoreService;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<AppUserProfile?>? _profileSubscription;

  User? _firebaseUser;
  AppUserProfile? _profile;
  bool _initialized = false;
  bool _busy = false;
  String? _errorMessage;
  int _authChangeExecutionId = 0;

  bool get initialized => _initialized;
  bool get busy => _busy;
  String? get errorMessage => _errorMessage;
  User? get firebaseUser => _firebaseUser;
  AppUserProfile? get profile => _profile;
  bool get isAuthenticated => authDisabled
      ? _profile != null
      : _firebaseUser != null && _profile != null;

  /// Push-Präferenzen des eigenen Profils setzen (M5). Optimistisch lokal
  /// übernommen (UI sofort), dann best-effort in die Cloud — im local-/Offline-
  /// Modus bleibt die lokale Übernahme bestehen.
  Future<void> updateNotificationPrefs(NotificationPrefs prefs) async {
    final current = _profile;
    if (current == null) {
      return;
    }
    _profile = current.copyWith(notificationPrefs: prefs);
    notifyListeners();
    if (authDisabled) {
      return;
    }
    try {
      await _firestoreService.updateNotificationPrefs(
        current.uid,
        prefs.toFirestoreMap(),
      );
    } catch (error, stackTrace) {
      AppLogger.error('Push-Präferenzen speichern fehlgeschlagen',
          error: error, stackTrace: stackTrace);
    }
  }
  bool get isResolvingProfile =>
      !authDisabled &&
      _firebaseUser != null &&
      _profile == null &&
      _errorMessage == null;
  bool get isAdmin => _profile?.isAdmin ?? false;
  bool get authDisabled => AppConfig.disableAuthentication;
  List<LocalDemoAccount> get localDemoAccounts => LocalDemoData.accounts;

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  bool get firebaseConfigured =>
      authDisabled ||
      DefaultFirebaseOptions.isConfigured ||
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    if (authDisabled) {
      final localUserId = await DatabaseService.loadLocalAuthUserId();
      _profile = LocalDemoData.profileForUid(
        localUserId,
        orgId: AppConfig.defaultOrganizationId,
      );
      _initialized = true;
      _errorMessage = null;
      notifyListeners();
      return;
    }

    if (!firebaseConfigured) {
      _initialized = true;
      notifyListeners();
      return;
    }

    await _authService.configurePersistence();
    await _authService.completePendingRedirectSignIn();
    await _onAuthChanged(_authService.currentUser);
    _authSubscription = _authService.authStateChanges().listen((user) {
      if (_initialized && user?.uid == _firebaseUser?.uid) {
        return;
      }
      unawaited(_onAuthChanged(user));
    });
  }

  Future<void> signInWithGoogle() {
    if (authDisabled) {
      return Future.value();
    }
    return _runAction(
      () => _authService.signInWithGoogle(),
    );
  }

  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) {
    if (authDisabled) {
      return _runAction(() async {
        final profile = LocalDemoData.authenticate(
          email: email,
          password: password,
          orgId: AppConfig.defaultOrganizationId,
        );
        if (profile == null) {
          throw StateError(
            'Unbekannter Demo-Login. Nutze einen der Demo-Accounts mit dem Passwort demo1234: '
            'admin@demo.local, peter@example.com, maria@example.com oder lea.teamlead@example.com.',
          );
        }
        await DatabaseService.saveLocalAuthUserId(profile.uid);
        _firebaseUser = null;
        _profile = profile;
        notifyListeners();
      });
    }
    return _runAction(
      () => _authService.signInWithEmailPassword(
        email: email,
        password: password,
      ),
    );
  }

  Future<void> signInWithLocalDemoProfile(String uid) {
    if (!authDisabled) {
      return Future.value();
    }
    return _runAction(() async {
      final profile = LocalDemoData.profileForUid(
        uid,
        orgId: AppConfig.defaultOrganizationId,
      );
      if (profile == null) {
        throw StateError('Das ausgewaehlte Demo-Profil wurde nicht gefunden.');
      }
      await DatabaseService.saveLocalAuthUserId(profile.uid);
      _firebaseUser = null;
      _profile = profile;
      notifyListeners();
    });
  }

  Future<void> activateInvite({
    required String email,
    required String password,
  }) {
    if (authDisabled) {
      return Future.value();
    }
    return _runAction(() async {
      final hasPendingAccess =
          await _firestoreService.hasPendingAccessForEmail(email);
      if (!hasPendingAccess) {
        throw StateError(
          'Fuer diese E-Mail liegt keine aktive Einladung vor.',
        );
      }
      await _authService.registerWithEmailPassword(
        email: email,
        password: password,
      );
    });
  }

  Future<void> signOut() {
    if (authDisabled) {
      return _runAction(() async {
        await DatabaseService.saveLocalAuthUserId(null);
        _firebaseUser = null;
        _profile = null;
      }, clearError: true);
    }
    return _runAction(
      () => _authService.signOut(),
      clearError: true,
    );
  }

  /// Anmelde-Anbieter des aktuellen Nutzers (`password`/`google.com`) — steuert,
  /// welches Reauth-UI vor dem Kontolöschen gezeigt wird. Null im Demo-Modus.
  String? get primaryProviderId =>
      authDisabled ? null : _authService.primaryProviderId;

  /// Bestätigt die Identität vor einer destruktiven Aktion (Kontolöschen) neu.
  /// Bei Passwort-Konten muss [password] gesetzt sein; Google-Konten lösen einen
  /// erneuten Google-Login aus. Liefert `true` bei Erfolg, sonst steht der Grund
  /// in [errorMessage]. Im Demo-Modus (kein Firebase) ein No-op mit `true`.
  Future<bool> reauthenticate({String? password}) async {
    if (authDisabled) {
      return true;
    }
    final providerId = _authService.primaryProviderId;
    await _runAction(() async {
      if (providerId == 'password') {
        final pw = password ?? '';
        if (pw.isEmpty) {
          throw StateError('Bitte gib dein Passwort ein.');
        }
        await _authService.reauthenticateWithPassword(pw);
      } else {
        await _authService.reauthenticateWithGoogle();
      }
    }, clearError: true);
    return _errorMessage == null;
  }

  /// Löscht das **eigene** Konto komplett (Plan `plan/account-loeschung.md`).
  /// Voraussetzung: [reauthenticate] lief zuvor erfolgreich (UI-Gate).
  ///
  /// Real: serverseitige Löschung über die Callable (Auth-Nutzer + persönliche
  /// Daten hart, aufbewahrungspflichtige Daten anonymisiert), danach lokaler
  /// Bulk-Wipe + Sign-out → Gate leitet auf `/anmelden`. Demo/Offline: es gibt
  /// keinen Server — nur lokaler Wipe + State-Reset.
  Future<bool> deleteOwnAccount() async {
    if (authDisabled) {
      await _runAction(() async {
        await DatabaseService.wipeAllLocalData();
        _firebaseUser = null;
        _profile = null;
      }, clearError: true);
      return _errorMessage == null;
    }
    final uid = _firebaseUser?.uid;
    if (uid == null) {
      _errorMessage = 'Kein angemeldetes Konto gefunden.';
      notifyListeners();
      return false;
    }
    // 1) Die serverseitige Löschung ist der maßgebliche Erfolg.
    await _runAction(
      () => _firestoreService.deleteUserAccount(uid),
      clearError: true,
    );
    if (_errorMessage != null) {
      return false;
    }
    // 2) Lokaler Wipe + Sign-out sind best-effort: ein Fehler hier darf die
    // bereits erfolgte Server-Löschung NICHT als Fehlschlag maskieren (der
    // Profil-Stream/Auth-Event leitet ohnehin auf /anmelden um).
    try {
      await DatabaseService.wipeAllLocalData();
    } catch (error, stackTrace) {
      AppLogger.warning('Lokaler Wipe nach Kontolöschung fehlgeschlagen',
          error: error, stackTrace: stackTrace);
    }
    try {
      await _authService.signOut();
    } catch (error, stackTrace) {
      AppLogger.warning('Sign-out nach Kontolöschung fehlgeschlagen',
          error: error, stackTrace: stackTrace);
    }
    return true;
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    bool clearError = false,
  }) async {
    _busy = true;
    if (clearError) {
      _errorMessage = null;
    }
    notifyListeners();

    try {
      await action();
      _errorMessage = null;
    } catch (error) {
      _errorMessage = _mapError(error);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _onAuthChanged(User? user) async {
    final executionId = ++_authChangeExecutionId;

    await _profileSubscription?.cancel();
    _profileSubscription = null;
    _firebaseUser = user;
    _profile = null;

    if (user == null) {
      _initialized = true;
      notifyListeners();
      return;
    }

    // Anonyme Sessions stammen von der öffentlichen Kundenwunsch-Seite
    // (/wunsch) und haben kein Mitarbeiter-Profil. Sie dürfen den internen
    // App-Zustand nicht verschmutzen (sonst wirft ensureProfileForSignedInUser
    // "keine E-Mail" und blockiert den echten Login auf demselben Browser).
    // Wie "abgemeldet" behandeln und die anonyme Session still beenden.
    if (user.isAnonymous) {
      _firebaseUser = null;
      _initialized = true;
      notifyListeners();
      unawaited(_authService.signOut());
      return;
    }

    try {
      final ensuredProfile =
          await _firestoreService.ensureProfileForSignedInUser(user);
      if (executionId != _authChangeExecutionId) return;

      _profile = ensuredProfile;
      notifyListeners();
      _profileSubscription =
          _firestoreService.watchUserProfile(user.uid).listen((profile) async {
        _profile = profile;
        notifyListeners();

        if (profile != null) {
          await _firestoreService.migrateLegacyDataIfNeeded(
            orgId: profile.orgId,
            userId: profile.uid,
            currentSettings: profile.settings,
          );
        }
      }, onError: (Object error, StackTrace stackTrace) {
        _errorMessage = _mapError(error);
        notifyListeners();
      });
      _errorMessage = null;
    } catch (error) {
      if (executionId != _authChangeExecutionId) return;
      _errorMessage = _mapError(error);
      await _authService.signOut();
    } finally {
      if (executionId == _authChangeExecutionId) {
        _initialized = true;
        notifyListeners();
      }
    }
  }

  String _mapError(Object error) {
    AppLogger.warning('AuthProvider Fehler: ${error.runtimeType}: $error');

    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'invalid-email' => 'Die E-Mail-Adresse ist ungueltig.',
        'user-not-found' => 'Kein Benutzer mit dieser E-Mail gefunden.',
        'wrong-password' => 'Das Passwort ist ungueltig.',
        'invalid-credential' => 'E-Mail oder Passwort sind ungueltig.',
        'email-already-in-use' => 'Diese E-Mail ist bereits registriert.',
        'weak-password' => 'Das Passwort ist zu schwach.',
        'popup-closed-by-user' ||
        'cancelled-popup-request' =>
          'Die Google-Anmeldung wurde abgebrochen.',
        'popup-blocked' =>
          'Das Anmelde-Popup wurde vom Browser blockiert. Bitte erlaube Popups fuer diese Seite.',
        'network-request-failed' =>
          'Netzwerkfehler. Bitte pruefe deine Internetverbindung.',
        'too-many-requests' =>
          'Zu viele Anmeldeversuche. Bitte warte einen Moment und versuche es erneut.',
        'user-disabled' => 'Dieses Konto wurde deaktiviert.',
        'requires-recent-login' =>
          'Aus Sicherheitsgründen bitte erneut anmelden und die Aktion wiederholen.',
        'user-mismatch' =>
          'Die Bestätigung passt nicht zum angemeldeten Konto.',
        'account-exists-with-different-credential' =>
          'Ein Konto mit dieser E-Mail existiert bereits mit einer anderen Anmeldemethode.',
        _ =>
          error.message ?? 'Authentifizierung fehlgeschlagen (${error.code}).',
      };
    }
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' =>
          'Firestore verweigert den Zugriff. Fuer den ersten Admin lege zuerst eine Admin-Einladung in userInvites/<deine-mail> an.',
        'unavailable' =>
          'Firestore ist momentan nicht erreichbar. Bitte versuche es erneut.',
        _ =>
          error.message ?? 'Firestore-Zugriff fehlgeschlagen (${error.code}).',
      };
    }
    if (error is GoogleSignInException) {
      return switch (error.code) {
        GoogleSignInExceptionCode.canceled =>
          'Die Google-Anmeldung wurde abgebrochen.',
        _ => error.description ?? 'Google-Anmeldung fehlgeschlagen.',
      };
    }
    if (error is PlatformException) {
      AppLogger.warning(
          'PlatformException code: ${error.code}, message: ${error.message}');
      if (error.code == 'sign_in_canceled') {
        return 'Die Google-Anmeldung wurde abgebrochen.';
      }
      return error.message ??
          'Plattform-Fehler bei der Anmeldung (${error.code}).';
    }
    if (error is StateError) {
      return error.message;
    }
    if (error is UnsupportedError) {
      return error.message ??
          'Diese Funktion wird auf dieser Plattform nicht unterstuetzt.';
    }
    return 'Fehler bei der Anmeldung: $error';
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _profileSubscription?.cancel();
    super.dispose();
  }
}
