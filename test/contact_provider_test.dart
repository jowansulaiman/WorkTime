import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/audit_log_entry.dart';
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

  group('ContactProvider – Änderungsprotokoll (Audit)', () {
    late List<
        ({
          AuditAction action,
          String entityType,
          String? entityId,
          String summary
        })> logged;

    ContactProvider auditedLocalProvider() {
      final provider = newLocalProvider();
      provider.setAuditSink((
          {required AuditAction action,
          required String entityType,
          String? entityId,
          required String summary}) {
        logged.add((
          action: action,
          entityType: entityType,
          entityId: entityId,
          summary: summary,
        ));
      });
      return provider;
    }

    setUp(() => logged = []);

    test('neuer Kontakt -> genau ein created-Eintrag', () async {
      final provider = auditedLocalProvider();
      await provider.updateSession(user);

      await provider.saveContact(const Contact(orgId: 'org-1', name: 'Neu'));

      expect(logged, hasLength(1));
      expect(logged.single.action, AuditAction.created);
      expect(logged.single.entityType, 'Kontakt');
      expect(logged.single.summary, contains('angelegt'));
    });

    test('toggleFavorite protokolliert NICHTS (Rauschen)', () async {
      final provider = auditedLocalProvider();
      await provider.updateSession(user);
      await provider.saveContact(const Contact(orgId: 'org-1', name: 'X'));
      logged.clear();

      await provider.toggleFavorite(provider.contacts.single);

      expect(logged, isEmpty);
    });

    test('setActive schreibt genau einen fachlichen updated-Eintrag', () async {
      final provider = auditedLocalProvider();
      await provider.updateSession(user);
      await provider.saveContact(const Contact(orgId: 'org-1', name: 'X'));
      logged.clear();

      await provider.setActive(provider.contacts.single, isActive: false);

      // Delegierter Eintrag (kein zusätzlicher generischer „aktualisiert").
      expect(logged, hasLength(1));
      expect(logged.single.action, AuditAction.updated);
      expect(logged.single.summary, contains('deaktiviert'));
    });

    test('deleteContact -> genau ein deleted-Eintrag', () async {
      final provider = auditedLocalProvider();
      await provider.updateSession(user);
      await provider.saveContact(const Contact(orgId: 'org-1', name: 'X'));
      logged.clear();

      await provider.deleteContact(provider.contacts.single.id!);

      expect(logged, hasLength(1));
      expect(logged.single.action, AuditAction.deleted);
      expect(logged.single.summary, contains('gelöscht'));
    });

    test('importContacts schreibt EINEN Sammel-Eintrag statt N', () async {
      final provider = auditedLocalProvider();
      await provider.updateSession(user);

      final count = await provider.importContacts(const [
        Contact(orgId: 'org-1', name: 'A'),
        Contact(orgId: 'org-1', name: 'B'),
        Contact(orgId: 'org-1', name: 'C'),
      ]);

      expect(count, 3);
      expect(logged, hasLength(1));
      expect(logged.single.action, AuditAction.created);
      expect(logged.single.summary, '3 Kontakte importiert');
    });

    test('Suppress-Flag leckt nach fehlgeschlagener Delegation nicht', () async {
      final provider = auditedLocalProvider();
      // Kein Nutzer -> orgId null -> saveContact wirft. setActive hat zuvor das
      // Suppress-/Delegations-Flag gesetzt; ohne Reset-VOR-dem-Wurf würde es in
      // den nächsten regulären saveContact lecken (Regression-Schutz).
      await expectLater(
        provider.setActive(
          const Contact(id: 'c1', orgId: 'org-1', name: 'X'),
          isActive: false,
        ),
        throwsStateError,
      );
      expect(logged, isEmpty);

      // Danach reguläre Speicherung mit aktiver Org -> sauberer created-Eintrag,
      // NICHT der unterdrückte/delegierte „deaktiviert"-Eintrag.
      await provider.updateSession(user);
      await provider.saveContact(const Contact(orgId: 'org-1', name: 'Neu'));

      expect(logged, hasLength(1));
      expect(logged.single.action, AuditAction.created);
      expect(logged.single.summary, contains('angelegt'));
    });
  });
}
