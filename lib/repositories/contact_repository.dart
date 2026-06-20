import '../models/contact.dart';

/// Abstraktion ueber den Datenzugriff fuer Kontakte (Kunden, Lieferanten,
/// Geschaeftspartner, Behoerden, …).
///
/// Die High-Level-Schicht ([ContactProvider]) haengt von dieser Abstraktion
/// statt von der konkreten `FirestoreService`-Klasse ab (DIP,
/// no-domain-repository-interfaces-dip). Implementierungen kapseln den
/// konkreten Datenzugriff (Firestore) bzw. lassen sich in Tests durch einen
/// handgeschriebenen Fake ersetzen.
abstract interface class ContactRepository {
  Stream<List<Contact>> watchContacts(String orgId);

  /// Speichert einen Kontakt (Anlage oder Update). Bei neuen Kontakten wird eine
  /// Dokument-Id vergeben.
  Future<void> saveContact(Contact contact);

  Future<void> deleteContact({
    required String orgId,
    required String contactId,
  });
}
