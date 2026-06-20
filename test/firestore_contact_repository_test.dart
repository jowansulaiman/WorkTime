import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/contact.dart';
import 'package:worktime_app/repositories/firestore_contact_repository.dart';

void main() {
  const orgId = 'org-1';
  late FakeFirebaseFirestore firestore;
  late FirestoreContactRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = FirestoreContactRepository(firestore: firestore);
  });

  test('saveContact legt ein Dokument mit nameLower und orgId an', () async {
    await repo.saveContact(const Contact(orgId: orgId, name: 'Zeta GmbH'));

    final docs = await firestore
        .collection('organizations')
        .doc(orgId)
        .collection('contacts')
        .get();

    expect(docs.docs, hasLength(1));
    expect(docs.docs.first['nameLower'], 'zeta gmbh');
    expect(docs.docs.first['orgId'], orgId);
  });

  test('watchContacts liefert alphabetisch nach nameLower sortiert', () async {
    await repo.saveContact(const Contact(orgId: orgId, name: 'Zeta'));
    await repo.saveContact(const Contact(orgId: orgId, name: 'alpha'));

    final contacts = await repo.watchContacts(orgId).first;

    expect(contacts.map((c) => c.name), ['alpha', 'Zeta']);
  });

  test('saveContact aktualisiert ein bestehendes Dokument (merge)', () async {
    await repo.saveContact(const Contact(id: 'c1', orgId: orgId, name: 'Alt'));
    await repo.saveContact(
      const Contact(id: 'c1', orgId: orgId, name: 'Neu', isFavorite: true),
    );

    final contacts = await repo.watchContacts(orgId).first;
    expect(contacts, hasLength(1));
    expect(contacts.single.name, 'Neu');
    expect(contacts.single.isFavorite, isTrue);
  });

  test('deleteContact entfernt das Dokument', () async {
    await repo.saveContact(const Contact(id: 'c1', orgId: orgId, name: 'X'));
    await repo.deleteContact(orgId: orgId, contactId: 'c1');

    final contacts = await repo.watchContacts(orgId).first;
    expect(contacts, isEmpty);
  });
}
