import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/local_demo_data.dart';
import '../models/app_user.dart';
import '../models/contact.dart';
import '../models/contact_activity.dart';
import '../repositories/contact_repository.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';

/// Verwaltet die Kontakte (Kunden, Lieferanten, Geschaeftspartner, Behoerden, …)
/// einer Organisation.
///
/// Im Cloud-/Hybridmodus werden die Daten ueber Firestore-Streams geladen
/// (Offline-Cache aktiv). Im lokalen Entwicklungsmodus
/// ([AppConfig.disableAuthentication] bzw. localStorageOnly) werden sie im
/// Speicher gehalten und in SharedPreferences gespiegelt, damit die App auch
/// ohne Firebase nutzbar bleibt. Struktur analog zu [InventoryProvider].
class ContactProvider extends ChangeNotifier {
  ContactProvider({
    required FirestoreService firestoreService,
    ContactRepository? contactRepository,
    bool? disableAuthentication,
  })  : _firestoreService = firestoreService,
        _injectedContacts = contactRepository,
        _forceLocalStorage =
            disableAuthentication ?? AppConfig.disableAuthentication;

  // Provider haengt an der Repository-Abstraktion, nicht an der konkreten
  // FirestoreService-Klasse (no-domain-repository-interfaces-dip). Cloud-
  // Repository LAZY (wie [InventoryProvider]): im lokalen/disableAuth-Modus nie
  // aufgeloest, sodass FirebaseFirestore.instance ohne Firebase nicht ausgewertet
  // wird (sonst Crash schon bei Provider-Konstruktion -> rote Fehlerseite).
  final FirestoreService _firestoreService;
  final ContactRepository? _injectedContacts;
  ContactRepository get _contacts =>
      _injectedContacts ?? _firestoreService.contactRepository;
  final bool _forceLocalStorage;
  bool _localStorageOnly = false;
  bool _hybridStorageEnabled = false;

  StreamSubscription<List<Contact>>? _contactsSubscription;

  AppUserProfile? _currentUser;
  List<Contact> _items = [];
  bool _loading = false;
  String? _errorMessage;
  bool _disposed = false;
  bool _seededLocalDemo = false;
  int _localSeq = 0;

  List<Contact> get contacts => _items;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;

  bool get usesLocalStorage => _forceLocalStorage || _localStorageOnly;
  bool get _usesFirestore => !usesLocalStorage;
  bool get usesHybridStorage =>
      !_forceLocalStorage && !_localStorageOnly && _hybridStorageEnabled;
  String? get _orgId => _currentUser?.orgId;

  // --- Abgeleitete Sichten ------------------------------------------------

  List<Contact> get activeContacts =>
      _items.where((contact) => contact.isActive).toList(growable: false);

  List<Contact> get favorites =>
      _items.where((contact) => contact.isFavorite).toList(growable: false);

  /// Anzahl Kontakte je Kategorie (fuer Filter-Badges / Statistik).
  Map<ContactType, int> get countsByType {
    final result = <ContactType, int>{};
    for (final contact in _items) {
      result.update(contact.type, (value) => value + 1, ifAbsent: () => 1);
    }
    return result;
  }

  /// Alle vergebenen Schlagworte (alphabetisch, fuer Tag-Filter).
  List<String> get tagsInUse {
    final result = <String>{};
    for (final contact in _items) {
      result.addAll(contact.tags);
    }
    final list = result.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Contact? contactById(String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final contact in _items) {
      if (contact.id == id) {
        return contact;
      }
    }
    return null;
  }

  /// Versucht eine Firestore-Mutation. Erfolg -> true (Aufrufer ist fertig).
  /// Im Hybrid-Modus bei Fehler -> false (Aufrufer faellt lokal zurueck, damit
  /// offline nichts verloren geht). Im Cloud-only-Modus wird der Fehler
  /// durchgereicht.
  Future<bool> _tryFirestore(
    String label,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      return true;
    } catch (error) {
      if (!usesHybridStorage) {
        rethrow;
      }
      AppLogger.warning(
        'Contacts: $label offline – lokaler Fallback aktiv',
        error: error,
      );
      return false;
    }
  }

  LocalStorageScope? get _localScope {
    final user = _currentUser;
    if (user == null) {
      return null;
    }
    return LocalStorageScope.fromUser(user);
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _setError(Object error) {
    _errorMessage = error is StateError ? error.message : error.toString();
    _safeNotify();
  }

  /// Macht einen Fehler beim fire-and-forget Sitzungsaufbau in der UI sichtbar
  /// (fire-and-forget-updatesession).
  void surfaceSessionError(Object error) {
    _errorMessage =
        'Kontakte konnten nicht geladen werden. Bitte später erneut versuchen.';
    _safeNotify();
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      _safeNotify();
    }
  }

  String? _lastSessionKey;

  String get _storageModeKey => usesLocalStorage
      ? 'local'
      : (_hybridStorageEnabled ? 'hybrid' : 'cloud');

  Future<void> updateSession(
    AppUserProfile? user, {
    bool localStorageOnly = false,
    bool hybridStorageEnabled = false,
  }) async {
    _localStorageOnly = localStorageOnly;
    _hybridStorageEnabled = hybridStorageEnabled;
    final sessionKey =
        user == null ? null : '${user.uid}:${user.orgId}:$_storageModeKey';
    if (sessionKey == _lastSessionKey) {
      _currentUser = user;
      return;
    }
    _lastSessionKey = sessionKey;
    _currentUser = user;

    await _cancelSubscriptions();

    if (user == null) {
      _items = [];
      _loading = false;
      _seededLocalDemo = false;
      _safeNotify();
      return;
    }

    if (_usesFirestore) {
      _startFirestoreSubscriptions(user.orgId);
    } else {
      await _loadLocalData();
      final seeded = _maybeSeedLocalDemo(user);
      if (seeded) {
        await _persistContacts();
      }
      _safeNotify();
    }
  }

  Future<void> _loadLocalData() async {
    _items = await DatabaseService.loadLocalContacts(scope: _localScope);
  }

  Future<void> _persistContacts() =>
      DatabaseService.saveLocalContacts(_items, scope: _localScope);

  /// Befuellt den lokalen Modus einmalig mit Demo-Kontakten, damit der Bereich
  /// ohne Firebase nicht leer ist. Echte lokale Daten bleiben unangetastet.
  bool _maybeSeedLocalDemo(AppUserProfile user) {
    if (_seededLocalDemo || !LocalDemoData.isDemoUser(user)) {
      return false;
    }
    _seededLocalDemo = true;
    if (_items.isNotEmpty) {
      return false;
    }
    _items = LocalDemoData.contactsForOrg(
      orgId: user.orgId,
      createdByUid: user.uid,
    );
    _sortContacts();
    return true;
  }

  void _startFirestoreSubscriptions(String orgId) {
    _loading = true;
    _safeNotify();

    _contactsSubscription = _contacts.watchContacts(orgId).listen((items) {
      _items = items;
      _loading = false;
      _safeNotify();
    }, onError: _setError);
  }

  Future<void> _cancelSubscriptions() async {
    await _contactsSubscription?.cancel();
    _contactsSubscription = null;
  }

  String _nextLocalId(String prefix) {
    _localSeq += 1;
    return 'local-$prefix-${DateTime.now().microsecondsSinceEpoch}-$_localSeq';
  }

  void _sortContacts() {
    _items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  // --- CRUD ---------------------------------------------------------------

  Future<void> saveContact(Contact contact) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    final prepared = contact.copyWith(
      orgId: orgId,
      createdByUid: contact.createdByUid ?? _currentUser?.uid,
    );
    if (_usesFirestore &&
        await _tryFirestore(
          'saveContact',
          () => _contacts.saveContact(prepared),
        )) {
      return;
    }
    _upsertLocal(
      prepared.id == null
          ? prepared.copyWith(id: _nextLocalId('contact'))
          : prepared,
    );
    _sortContacts();
    await _persistContacts();
    _safeNotify();
  }

  /// Importiert mehrere Kontakte (z.B. aus CSV) und gibt die Anzahl der
  /// gespeicherten zurück. Speichert nacheinander über [saveContact].
  Future<int> importContacts(List<Contact> contacts) async {
    var saved = 0;
    for (final contact in contacts) {
      if (contact.name.trim().isEmpty) continue;
      await saveContact(contact);
      saved++;
    }
    return saved;
  }

  /// Fügt der Kontakthistorie eine Aktivität hinzu (neueste zuerst, gedeckelt
  /// auf 50 Einträge) und speichert den Kontakt.
  Future<void> addContactActivity(
    Contact contact,
    ContactActivity activity,
  ) async {
    final updated = contact.copyWith(
      activities: [activity, ...contact.activities].take(50).toList(),
    );
    await saveContact(updated);
  }

  Future<void> deleteContact(String contactId) async {
    final orgId = _orgId;
    if (orgId == null) {
      return;
    }
    if (_usesFirestore &&
        await _tryFirestore(
          'deleteContact',
          () => _contacts.deleteContact(orgId: orgId, contactId: contactId),
        )) {
      return;
    }
    _items =
        _items.where((contact) => contact.id != contactId).toList(growable: false);
    await _persistContacts();
    _safeNotify();
  }

  /// Schaltet die Favoriten-Markierung um (Speicherung ueber [saveContact]).
  Future<void> toggleFavorite(Contact contact) {
    return saveContact(contact.copyWith(isFavorite: !contact.isFavorite));
  }

  /// Aktiviert/Archiviert einen Kontakt (Speicherung ueber [saveContact]).
  Future<void> setActive(Contact contact, {required bool isActive}) {
    return saveContact(contact.copyWith(isActive: isActive));
  }

  void _upsertLocal(Contact item) {
    final index = _items.indexWhere((existing) => existing.id == item.id);
    if (index >= 0) {
      _items[index] = item;
    } else {
      _items = [..._items, item];
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSubscriptions();
    super.dispose();
  }
}
