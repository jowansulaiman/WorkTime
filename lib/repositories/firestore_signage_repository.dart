import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/ad_media.dart';
import '../models/signage_display.dart';
import 'signage_repository.dart';

/// Firestore-Implementierung der [SignageRepository] — die einzige Stelle mit
/// Signage-Datenzugriffslogik. Reiner Cloud-Zugriff; die Speicherstrategie
/// (cloud/hybrid/local) liegt im `SignageProvider`.
///
/// Collections: `organizations/{orgId}/adMedia`,
/// `organizations/{orgId}/signageDisplays` (beide admin-only, org-skopiert) und
/// die Top-Level-Collection `publicDisplays/{token}` (öffentlich lesbar, per
/// Token; Schreiben nur Admin – siehe firestore.rules).
class FirestoreSignageRepository implements SignageRepository {
  FirestoreSignageRepository({
    required FirebaseFirestore firestore,
  }) : _firestore = firestore;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _organizationDoc(String orgId) =>
      _firestore.collection('organizations').doc(orgId);

  CollectionReference<Map<String, dynamic>> _mediaCollection(String orgId) =>
      _organizationDoc(orgId).collection('adMedia');

  CollectionReference<Map<String, dynamic>> _displayCollection(String orgId) =>
      _organizationDoc(orgId).collection('signageDisplays');

  CollectionReference<Map<String, dynamic>> get _publicDisplays =>
      _firestore.collection('publicDisplays');

  // --- Werbebild-Bibliothek -------------------------------------------------

  @override
  Stream<List<AdMedia>> watchMedia(String orgId) {
    // Sortierung über den abgeleiteten `titleLower` (immer gesetzt) → kein
    // Composite-Index und kein serverTimestamp-null-Ordering-Problem.
    return _mediaCollection(orgId).orderBy('titleLower').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => AdMedia.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  String newMediaId(String orgId) => _mediaCollection(orgId).doc().id;

  @override
  Future<void> saveMedia(AdMedia media) async {
    final collection = _mediaCollection(media.orgId);
    final docRef =
        media.id == null ? collection.doc() : collection.doc(media.id);
    await docRef.set({
      ...media.copyWith(id: docRef.id).toFirestoreMap(),
      if (media.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteMedia({
    required String orgId,
    required String mediaId,
  }) {
    return _mediaCollection(orgId).doc(mediaId).delete();
  }

  // --- Displays -------------------------------------------------------------

  @override
  Stream<List<SignageDisplay>> watchDisplays(String orgId) {
    return _displayCollection(orgId).orderBy('nameLower').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => SignageDisplay.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Future<void> saveDisplay(SignageDisplay display) async {
    final collection = _displayCollection(display.orgId);
    final docRef =
        display.id == null ? collection.doc() : collection.doc(display.id);
    await docRef.set({
      ...display.copyWith(id: docRef.id).toFirestoreMap(),
      if (display.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteDisplay({
    required String orgId,
    required String displayId,
  }) {
    return _displayCollection(orgId).doc(displayId).delete();
  }

  // --- Öffentliche Player-Projektion ---------------------------------------

  @override
  Future<void> publishPublicDisplay(
    String token,
    Map<String, dynamic> projection,
  ) {
    return _publicDisplays.doc(token).set(projection, SetOptions(merge: true));
  }

  @override
  Future<void> unpublishPublicDisplay(String token) {
    return _publicDisplays.doc(token).delete();
  }
}
