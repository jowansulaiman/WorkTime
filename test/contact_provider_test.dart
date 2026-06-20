import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/contact.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/contact_provider.dart';
import 'package:worktime_app/repositories/contact_repository.dart';
import 'package:worktime_app/repositories/firestore_contact_repository.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// Handgeschriebener Fake (kein Mockito): delegiert an ein echtes
/// FirestoreContactRepository, laesst aber saveContact fehlschlagen, um den
/// hybrid-Offline-Fallback des Providers zu testen.
class _OfflineContactRepository implements ContactRepository {
  _OfflineContactRepository(FakeFirebaseFirestore firestore)
      : _delegate = FirestoreContactRepository(firestore: firestore);

  final ContactRepository _delegate;

  @override
  Future<void> saveContact(Contact contact) async {
    throw Exception('offline');
  }

  @override
  Stream<List<Contact>> watchContacts(String orgId) =>
      _delegate.watchContacts(orgId);

  @override
  Future<void> deleteContact({
    required String orgId,
    required String contactId,
  }) =>
      _delegate.deleteContact(orgId: orgId, contactId: contactId);
}

/// Fake fuer den Cloud-Stream-Fehlerpfad: der Kontakt-Stream schlaegt fehl.
class _StreamErrorContactRepository extends _OfflineContactRepository {
  _StreamErrorContactRepository(super.firestore);

  @override
  Stream<List<Contact>> watchContacts(String orgId) =>
      Stream<List<Contact>>.error(
        StateError('Kontakt-Stream fehlgeschlagen'),
      );
}

void main() {
  // Nicht-Demo-Nutzer, damit _maybeSeedLocalDemo NICHT greift.
  const user = AppUserProfile(
    uid: 'owner-1',
    orgId: 'org-1',
    email: 'owner@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Inhaber'),
  );

  late FakeFirebaseFirestore firestore;
  late FirestoreService firestoreService;

  ContactProvider newLocalProvider() => ContactProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    firestore = FakeFirebaseFirestore();
    firestoreService = FirestoreService(firestore: firestore);
  });

  group('ContactProvider – lokaler Modus', () {
    test('weist neuen Kontakten lokale IDs zu und sortiert', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);

      await provider.saveContact(const Contact(orgId: 'org-1', name: 'Zeta'));
      await provider.saveContact(const Contact(orgId: 'org-1', name: 'Alpha'));

      expect(provider.contacts, hasLength(2));
      expect(provider.contacts.first.name, 'Alpha'); // alphabetisch
      expect(provider.contacts.every((c) => c.id != null), isTrue);
    });

    test('persistiert lokal und stellt nach Neustart wieder her', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveContact(
        const Contact(orgId: 'org-1', name: 'Tabak Nord', isFavorite: true),
      );

      final restored = newLocalProvider();
      await restored.updateSession(user);

      expect(restored.contacts.single.name, 'Tabak Nord');
      expect(restored.contacts.single.isFavorite, isTrue);
    });

    test('toggleFavorite schaltet die Markierung um', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveContact(const Contact(orgId: 'org-1', name: 'X'));

      await provider.toggleFavorite(provider.contacts.single);

      expect(provider.contacts.single.isFavorite, isTrue);
    });

    test('deleteContact entfernt den Kontakt lokal', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveContact(const Contact(orgId: 'org-1', name: 'X'));

      await provider.deleteContact(provider.contacts.single.id!);

      expect(provider.contacts, isEmpty);
    });

    test('countsByType zählt je Kategorie', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveContact(
        const Contact(orgId: 'org-1', name: 'A', type: ContactType.customer),
      );
      await provider.saveContact(
        const Contact(orgId: 'org-1', name: 'B', type: ContactType.customer),
      );
      await provider.saveContact(
        const Contact(orgId: 'org-1', name: 'C', type: ContactType.supplier),
      );

      expect(provider.countsByType[ContactType.customer], 2);
      expect(provider.countsByType[ContactType.supplier], 1);
    });

    test('updateSession(null) setzt den Zustand zurück', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveContact(const Contact(orgId: 'org-1', name: 'X'));
      expect(provider.contacts, isNotEmpty);

      await provider.updateSession(null);

      expect(provider.contacts, isEmpty);
    });
  });

  group('ContactProvider – hybrid', () {
    test(
        'hybrid-Offline: fehlgeschlagener Cloud-Write wirft nicht und wird '
        'lokal persistiert', () async {
      final provider = ContactProvider(
        firestoreService: firestoreService,
        contactRepository: _OfflineContactRepository(firestore),
      );
      await provider.updateSession(user, hybridStorageEnabled: true);

      await provider.saveContact(
        const Contact(id: 'c-off', orgId: 'org-1', name: 'Offline-Kontakt'),
      );

      final persisted = await DatabaseService.loadLocalContacts(
        scope: LocalStorageScope.fromUser(user),
      );
      expect(persisted.any((c) => c.id == 'c-off'), isTrue);
    });
  });

  group('ContactProvider – Cloud-Modus', () {
    test('lädt Kontakte aus Firestore', () async {
      await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('contacts')
          .doc('c1')
          .set(const Contact(orgId: 'org-1', name: 'Wolke GmbH')
              .toFirestoreMap());

      final provider = ContactProvider(firestoreService: firestoreService);
      await provider.updateSession(user, localStorageOnly: false);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.contacts.map((c) => c.name), contains('Wolke GmbH'));
    });

    test('Stream-onError setzt errorMessage und crasht nicht', () async {
      final provider = ContactProvider(
        firestoreService: firestoreService,
        contactRepository: _StreamErrorContactRepository(firestore),
      );
      var notified = false;
      provider.addListener(() => notified = true);

      await provider.updateSession(user, localStorageOnly: false);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.errorMessage, contains('Kontakt-Stream fehlgeschlagen'));
      expect(notified, isTrue);
    });
  });
}
