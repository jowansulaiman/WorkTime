import '../models/contact.dart';
import '../models/contact_organization.dart';

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

  // --- Kontakt-Organisationen (eigenständiges Adressbuch, M9) ---------------

  Stream<List<ContactOrganization>> watchOrganizations(String orgId);

  /// Speichert eine Organisation (Anlage oder Update). Bei neuen Organisationen
  /// wird eine Dokument-Id vergeben.
  Future<void> saveOrganization(ContactOrganization organization);

  Future<void> deleteOrganization({
    required String orgId,
    required String organizationId,
  });
}
