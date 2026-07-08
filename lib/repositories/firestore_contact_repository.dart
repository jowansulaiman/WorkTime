import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/contact.dart';
import '../models/contact_organization.dart';
import 'contact_repository.dart';

/// Firestore-Implementierung der [ContactRepository] — die einzige Stelle mit
/// Kontakt-Datenzugriffslogik. Reiner Cloud-Datenzugriff; die Speicherstrategie
/// (cloud/hybrid/local) liegt im [ContactProvider].
class FirestoreContactRepository implements ContactRepository {
  FirestoreContactRepository({
    required FirebaseFirestore firestore,
  }) : _firestore = firestore;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _organizationDoc(String orgId) =>
      _firestore.collection('organizations').doc(orgId);

  CollectionReference<Map<String, dynamic>> _contactCollection(String orgId) =>
      _organizationDoc(orgId).collection('contacts');

  // Vollstaendiger, nach nameLower sortierter Stream (analog
  // Lieferanten/Artikel). Firestore-snapshots() liefern nach dem ersten
  // Snapshot nur DocChanges aus dem lokalen Cache; ein updatedAt-Cursor + Index
  // lohnt erst bei deutlich groesseren Bestaenden als den zwei Laeden.
  @override
  Stream<List<Contact>> watchContacts(String orgId) {
    return _contactCollection(orgId).orderBy('nameLower').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => Contact.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Future<void> saveContact(Contact contact) async {
    final collection = _contactCollection(contact.orgId);
    final docRef =
        contact.id == null ? collection.doc() : collection.doc(contact.id);
    await docRef.set({
      ...contact.copyWith(id: docRef.id).toFirestoreMap(),
      if (contact.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteContact({
    required String orgId,
    required String contactId,
  }) {
    return _contactCollection(orgId).doc(contactId).delete();
  }

  // --- Kontakt-Organisationen (M9) ------------------------------------------

  CollectionReference<Map<String, dynamic>> _organizationCollection(
          String orgId) =>
      _organizationDoc(orgId).collection('contactOrganizations');

  @override
  Stream<List<ContactOrganization>> watchOrganizations(String orgId) {
    return _organizationCollection(orgId).orderBy('nameLower').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => ContactOrganization.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Future<void> saveOrganization(ContactOrganization organization) async {
    final collection = _organizationCollection(organization.orgId);
    final docRef = organization.id == null
        ? collection.doc()
        : collection.doc(organization.id);
    await docRef.set({
      ...organization.copyWith(id: docRef.id).toFirestoreMap(),
      if (organization.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteOrganization({
    required String orgId,
    required String organizationId,
  }) {
    return _organizationCollection(orgId).doc(organizationId).delete();
  }
}
