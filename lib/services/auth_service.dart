import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  Future<void> configurePersistence() async {
    if (!kIsWeb) {
      return;
    }
    try {
      await _firebaseAuth.setPersistence(Persistence.LOCAL);
    } catch (error) {
      debugPrint(
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
      debugPrint(
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
