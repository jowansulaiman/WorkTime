import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/app_config.dart';

/// Persistiert FCM-Geräte-Tokens unter `users/{uid}/fcmTokens/{installationId}`
/// — ein Doc je Geräte-Installation, sodass ein Token-Refresh dasselbe Doc
/// überschreibt (kein Waisen-Doc) und ein Nutzer mit mehreren Geräten mehrere
/// Docs hat.
///
/// Bewusst **reiner Firestore-Zugriff** (kein FCM-SDK), damit die Token-Ablage
/// offline mit `FakeFirebaseFirestore` testbar ist. Das FCM-spezifische Holen
/// des Tokens liegt im [PushMessagingService]. Die Feld-Allowlist
/// (`token`, `platform`, `orgId`, `appVersion`, `updatedAt`) muss mit dem
/// `match /users/{uid}/fcmTokens/{tokenId}`-Block in `firestore.rules`
/// übereinstimmen.
class FcmTokenRepository {
  FcmTokenRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _tokens(String uid) =>
      _firestore.collection('users').doc(uid).collection('fcmTokens');

  /// Legt/aktualisiert das Token-Doc dieses Geräts (merge, Doc-ID =
  /// Installations-ID → Self-Refresh überschreibt sauber). `orgId` MUSS die
  /// eigene Org sein (Rules: `orgId == currentOrgId()`).
  Future<void> saveToken({
    required String uid,
    required String orgId,
    required String installationId,
    required String token,
    required String platform,
  }) {
    return _tokens(uid).doc(installationId).set(<String, dynamic>{
      'token': token,
      'platform': platform,
      'orgId': orgId,
      'appVersion': AppConfig.buildNumber.toString(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Entfernt das Token-Doc dieses Geräts (Logout/Nutzerwechsel-Cleanup).
  Future<void> deleteToken({
    required String uid,
    required String installationId,
  }) {
    return _tokens(uid).doc(installationId).delete();
  }
}
