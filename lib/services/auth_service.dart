import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/app_logger.dart';

class AuthService {
  AuthService({FirebaseAuth? firebaseAuth})
      : _providedFirebaseAuth = firebaseAuth;

  final FirebaseAuth? _providedFirebaseAuth;
  FirebaseAuth? _firebaseAuthInstance;
  bool _googleSignInInitialized = false;

  FirebaseAuth get _firebaseAuth =>
      _providedFirebaseAuth ??
      (_firebaseAuthInstance ??= FirebaseAuth.instance);

  Stream<User?> authStateChanges() => _firebaseAuth.authStateChanges();

  User? get currentUser => _firebaseAuth.currentUser;

  /// Setzt auf Web die Firebase-Auth-Persistenz.
  ///
  /// Risikoabwägung (01_api-sicherheit §1): Auf Web gibt es keinen sicheren
  /// nativen Token-Speicher. [Persistence.LOCAL] legt den Refresh-Token in
  /// IndexedDB ab — JS-zugänglich, also bei einer XSS-Lücke exfiltrierbar.
  /// Das ist der Firebase-SPA-Standard (überlebt Tab-/Browser-Neustart) und für
  /// die 2-Läden-Größe vertretbar, solange die zweite Verteidigungslinie steht:
  /// CSP-Meta in `web/index.html` + Security-Header in `firebase.json`.
  /// Wer Token nur für die Session-Dauer halten will, kann hier auf
  /// [Persistence.SESSION] umstellen (Login geht beim Tab-Schließen verloren).
  Future<void> configurePersistence() async {
    if (!kIsWeb) {
      return;
    }
    try {
      await _firebaseAuth.setPersistence(Persistence.LOCAL);
    } catch (error) {
      AppLogger.warning(
          'AuthService: Persistence konnte nicht gesetzt werden: $error');
    }
  }

  Future<void> completePendingRedirectSignIn() async {
    if (!kIsWeb) {
      return;
    }
    try {
      await _firebaseAuth.getRedirectResult();
    } catch (error) {
      AppLogger.warning(
          'AuthService: Redirect-Ergebnis konnte nicht gelesen werden: $error');
    }
  }

  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider()..addScope('email');
      await _firebaseAuth.signInWithPopup(provider);
      return;
    }

    // Native Plattformen: google_sign_in v7 API
    await _ensureGoogleSignInInitialized();
    final googleSignIn = GoogleSignIn.instance;
    if (googleSignIn.supportsAuthenticate()) {
      final account = await googleSignIn.authenticate(
        scopeHint: ['email'],
      );
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw FirebaseAuthException(
          code: 'invalid-credential',
          message: 'Google lieferte kein ID-Token.',
        );
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await _firebaseAuth.signInWithCredential(credential);
    } else {
      // Fallback: Firebase signInWithProvider
      final provider = GoogleAuthProvider()..addScope('email');
      await _firebaseAuth.signInWithProvider(provider);
    }
  }

  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) {
      return;
    }
    await GoogleSignIn.instance.initialize();
    _googleSignInInitialized = true;
  }

  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    await _firebaseAuth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> registerWithEmailPassword({
    required String email,
    required String password,
  }) async {
    await _firebaseAuth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() => _firebaseAuth.signOut();
}
