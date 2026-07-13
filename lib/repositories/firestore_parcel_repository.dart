import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/paketshop_settings.dart';
import '../models/parcel_customer.dart';
import '../models/parcel_shipment.dart';
import '../models/shelf_compartment.dart';
import 'parcel_repository.dart';

/// Firestore-Implementierung der [ParcelRepository] — die einzige Stelle mit
/// Paketshop-Datenzugriffslogik. Reiner Cloud-Zugriff (kein Callable, keine
/// Cloud Function in v1); org-skopiert unter `organizations/{orgId}/...`.
class FirestoreParcelRepository implements ParcelRepository {
  FirestoreParcelRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _organizationDoc(String orgId) =>
      _firestore.collection('organizations').doc(orgId);

  CollectionReference<Map<String, dynamic>> _parcelCollection(String orgId) =>
      _organizationDoc(orgId).collection('parcelShipments');

  CollectionReference<Map<String, dynamic>> _compartmentCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('shelfCompartments');

  CollectionReference<Map<String, dynamic>> _customerCollection(String orgId) =>
      _organizationDoc(orgId).collection('parcelCustomers');

  DocumentReference<Map<String, dynamic>> _settingsDoc(String orgId) =>
      _organizationDoc(orgId).collection('config').doc('paketshopSettings');

  // Reiner orderBy-Stream (Single-Field, auto-indiziert) — kein Composite-Index
  // in v1 (Plan §6.5/§12.2). snapshots() liefert nach dem ersten Snapshot nur
  // Deltas aus dem lokalen Cache; die Bestände (zwei Läden) sind klein.
  @override
  Stream<List<ParcelShipment>> watchParcels(String orgId) {
    return _parcelCollection(orgId).orderBy('recipientNameLower').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => ParcelShipment.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Future<String> saveParcel(ParcelShipment shipment) async {
    final collection = _parcelCollection(shipment.orgId);
    final docRef =
        shipment.id == null ? collection.doc() : collection.doc(shipment.id);
    final data = {
      ...shipment.copyWith(id: docRef.id).toFirestoreMap(),
      if (shipment.id == null) 'createdAt': FieldValue.serverTimestamp(),
    };
    await docRef.set(data, SetOptions(merge: true));
    return docRef.id;
  }

  @override
  Future<void> deleteParcel({required String orgId, required String id}) {
    return _parcelCollection(orgId).doc(id).delete();
  }

  @override
  Stream<List<ShelfCompartment>> watchCompartments(String orgId) {
    return _compartmentCollection(orgId).orderBy('labelLower').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => ShelfCompartment.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Future<String> saveCompartment(ShelfCompartment compartment) async {
    final collection = _compartmentCollection(compartment.orgId);
    final docRef = compartment.id == null
        ? collection.doc()
        : collection.doc(compartment.id);
    final data = {
      ...compartment.copyWith(id: docRef.id).toFirestoreMap(),
      if (compartment.id == null) 'createdAt': FieldValue.serverTimestamp(),
    };
    await docRef.set(data, SetOptions(merge: true));
    return docRef.id;
  }

  @override
  Future<void> deleteCompartment({
    required String orgId,
    required String id,
  }) {
    return _compartmentCollection(orgId).doc(id).delete();
  }

  @override
  Stream<List<ParcelCustomer>> watchCustomers(String orgId) {
    return _customerCollection(orgId).orderBy('nameLower').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => ParcelCustomer.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Future<String> saveCustomer(ParcelCustomer customer) async {
    final collection = _customerCollection(customer.orgId);
    final docRef =
        customer.id == null ? collection.doc() : collection.doc(customer.id);
    final data = {
      ...customer.copyWith(id: docRef.id).toFirestoreMap(),
      if (customer.id == null) 'firstSeenAt': FieldValue.serverTimestamp(),
    };
    await docRef.set(data, SetOptions(merge: true));
    return docRef.id;
  }

  @override
  Future<void> deleteCustomer({required String orgId, required String id}) {
    return _customerCollection(orgId).doc(id).delete();
  }

  @override
  Future<PaketshopSettings?> fetchSettings(String orgId) async {
    final snapshot = await _settingsDoc(orgId).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      return null;
    }
    return PaketshopSettings.fromFirestore(data);
  }

  @override
  Future<void> saveSettings(String orgId, PaketshopSettings settings) {
    return _settingsDoc(orgId).set(
      settings.toFirestoreMap(),
      SetOptions(merge: true),
    );
  }
}

