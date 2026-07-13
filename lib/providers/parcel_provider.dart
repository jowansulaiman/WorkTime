import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../models/app_user.dart';
import '../models/audit_log_entry.dart';
import '../models/paketshop_settings.dart';
import '../models/parcel_customer.dart';
import '../models/parcel_shipment.dart';
import '../models/shelf_compartment.dart';
import '../repositories/parcel_repository.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import 'audit_sink.dart';

/// Verwaltet den Hermes-Paketshop: Pakete, Fächer und das Kunden-Namensregister
/// eines Standorts.
///
/// Wie [InventoryProvider] drei Speichermodi: **cloud** (Firestore-Streams),
/// **hybrid** (Cloud-Reads + lokaler Fallback bei Offline) und **local**
/// (SharedPreferences, u. a. `APP_DISABLE_AUTH`). Das Cloud-Repository wird
/// LAZY aufgelöst (nie im Konstruktor), damit der offline-/Demo-Modus ohne
/// konfiguriertes Firebase nicht crasht.
///
/// v1 (Betreiber-Entscheidung §0): **keine** automatische Anonymisierung/
/// Löschung — gelöscht wird nur manuell auf Wunsch. Audit-Summaries sind
/// **strikt personenfrei** (nur Fach/Status, nie Empfängername).
class ParcelProvider extends ChangeNotifier {
  ParcelProvider({
    required FirestoreService firestoreService,
    ParcelRepository? parcelRepository,
    bool? disableAuthentication,
  })  : _firestoreService = firestoreService,
        _injectedParcel = parcelRepository,
        _forceLocalStorage =
            disableAuthentication ?? AppConfig.disableAuthentication;

  final FirestoreService _firestoreService;
  final ParcelRepository? _injectedParcel;
  ParcelRepository get _parcel =>
      _injectedParcel ?? _firestoreService.parcelRepository;

  final bool _forceLocalStorage;
  bool _localStorageOnly = false;
  bool _hybridStorageEnabled = false;

  StreamSubscription<List<ParcelShipment>>? _parcelsSubscription;
  StreamSubscription<List<ShelfCompartment>>? _compartmentsSubscription;
  StreamSubscription<List<ParcelCustomer>>? _customersSubscription;

  AppUserProfile? _currentUser;
  List<ParcelShipment> _parcels = [];
  List<ShelfCompartment> _compartments = [];
  List<ParcelCustomer> _customers = [];
  PaketshopSettings _settings = PaketshopSettings.defaults();

  bool _loading = false;
  String? _errorMessage;
  bool _disposed = false;
  int _localSeq = 0;
  String? _lastSessionKey;

  AuditSink? _audit;

  /// Senke fürs Änderungsprotokoll (best-effort). Wird in main.dart verdrahtet.
  void setAuditSink(AuditSink sink) {
    _audit = sink;
  }

  // --- Zustand -------------------------------------------------------------

  List<ParcelShipment> get parcels => _parcels;
  List<ShelfCompartment> get compartments => _compartments;
  List<ParcelCustomer> get customers => _customers;
  PaketshopSettings get settings => _settings;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;

  bool get usesLocalStorage => _forceLocalStorage || _localStorageOnly;
  bool get _usesFirestore => !usesLocalStorage;
  bool get usesHybridStorage =>
      !_forceLocalStorage && !_localStorageOnly && _hybridStorageEnabled;
  String? get _orgId => _currentUser?.orgId;

  // --- Abgeleitete Sichten (rein clientseitig, kein Index) -----------------

  /// Noch nicht ausgegebene/zurückgeschickte Pakete.
  List<ParcelShipment> get openParcels =>
      _parcels.where((p) => p.status.isOpen).toList(growable: false);

  /// Offene Pakete, deren Empfänger auf [query] passt (einfache normalisierte
  /// Teilstring-Suche; die tolerante Fuzzy-Suche kommt in P-5).
  List<ParcelShipment> parcelsForRecipient(String query) {
    final q = _norm(query);
    if (q.isEmpty) return const [];
    return openParcels
        .where((p) => p.recipientNameLower.contains(q))
        .toList(growable: false);
  }

  /// Pakete zu einem gescannten/eingegebenen Code: exakter `trackingCode` zuerst,
  /// danach Suffix-/Präfix-Treffer (z. B. letzte Stellen der Sendungsnummer).
  List<ParcelShipment> findParcelByCode(String code) {
    final c = code.trim();
    if (c.isEmpty) return const [];
    final exact = <ParcelShipment>[];
    final partial = <ParcelShipment>[];
    for (final p in _parcels) {
      final t = p.trackingCode?.trim();
      if (t == null || t.isEmpty) continue;
      if (t == c) {
        exact.add(p);
      } else if (t.endsWith(c) || c.endsWith(t)) {
        partial.add(p);
      }
    }
    return [...exact, ...partial];
  }

  /// Aktives Fach zu einem gescannten Bin-Barcode (oder null).
  ShelfCompartment? compartmentByBarcode(String code) {
    final c = code.trim();
    if (c.isEmpty) return null;
    for (final f in _compartments) {
      if (f.active && f.barcode.trim() == c) return f;
    }
    return null;
  }

  /// Belegung je Fach-Id, abgeleitet aus den OFFENEN Paketen.
  Map<String, int> get compartmentOccupancy {
    final map = <String, int>{};
    for (final p in openParcels) {
      final id = p.compartmentId;
      if (id != null) {
        map[id] = (map[id] ?? 0) + 1;
      }
    }
    return map;
  }

  /// Aktive Fächer ohne offenes Paket.
  List<ShelfCompartment> get freeCompartments {
    final occupied = compartmentOccupancy.keys.toSet();
    return _compartments
        .where((f) => f.active && !occupied.contains(f.id))
        .toList(growable: false);
  }

  /// Offene Pakete in einem Fach.
  List<ParcelShipment> parcelsInCompartment(String compartmentId) => openParcels
      .where((p) => p.compartmentId == compartmentId)
      .toList(growable: false);

  /// Offene Pakete, die zum Zeitpunkt [now] als überfällig gelten (Frist aus
  /// den Einstellungen, Default 6 Kalendertage).
  List<ParcelShipment> overdueParcels(DateTime now) => openParcels
      .where((p) => p.isOverdue(_settings.overdueFristTage, now))
      .toList(growable: false);

  /// Registrierte Kunden, deren Name auf [query] passt (Typeahead-Quelle).
  List<ParcelCustomer> parcelCustomersMatching(String query) {
    final q = _norm(query);
    if (q.isEmpty) return const [];
    return _customers
        .where((c) => c.nameLower.contains(q))
        .toList(growable: false);
  }

  /// Pakete, die an [day] angenommen wurden (Tages-Reconciliation).
  List<ParcelShipment> parcelsArrivedOn(DateTime day) => _parcels
      .where((p) => _isSameDay(p.arrivedAt, day))
      .toList(growable: false);

  /// Pakete, die an [day] ausgegeben wurden (Tages-Reconciliation).
  List<ParcelShipment> parcelsHandedOutOn(DateTime day) => _parcels
      .where((p) => p.handedOutAt != null && _isSameDay(p.handedOutAt!, day))
      .toList(growable: false);

  // --- Storage-Hilfen ------------------------------------------------------

  /// Versucht eine Firestore-Mutation. Erfolg → true. Im Hybrid-Modus bei
  /// Fehler → false (Aufrufer fällt lokal zurück). Cloud-only → rethrow.
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
        'Paketshop: $label offline – lokaler Fallback aktiv',
        error: error,
      );
      return false;
    }
  }

  String get _storageModeKey => usesLocalStorage
      ? 'local'
      : (_hybridStorageEnabled ? 'hybrid' : 'cloud');

  LocalStorageScope? get _localScope {
    final user = _currentUser;
    if (user == null) return null;
    return LocalStorageScope.fromUser(user);
  }

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
      _resetData();
      _safeNotify();
      return;
    }

    if (_usesFirestore) {
      _startFirestoreSubscriptions(user.orgId);
      await _loadCloudSettings(user.orgId);
      _safeNotify();
    } else {
      await _loadLocalData();
      _safeNotify();
    }
  }

  void _startFirestoreSubscriptions(String orgId) {
    _loading = true;
    _safeNotify();

    _parcelsSubscription = _parcel.watchParcels(orgId).listen((items) {
      _parcels = items;
      _loading = false;
      _safeNotify();
    }, onError: _setError);

    _compartmentsSubscription =
        _parcel.watchCompartments(orgId).listen((items) {
      _compartments = items;
      _safeNotify();
    }, onError: _setError);

    _customersSubscription = _parcel.watchCustomers(orgId).listen((items) {
      _customers = items;
      _safeNotify();
    }, onError: _setError);
  }

  Future<void> _loadCloudSettings(String orgId) async {
    try {
      _settings =
          await _parcel.fetchSettings(orgId) ?? PaketshopSettings.defaults();
    } catch (error) {
      // Nicht die Session crashen — auf lokalen Spiegel bzw. Defaults fallen.
      final local =
          await DatabaseService.loadLocalPaketshopSettings(scope: _localScope);
      _settings = local ?? PaketshopSettings.defaults();
      AppLogger.warning(
        'Paketshop-Einstellungen konnten nicht geladen werden',
        error: error,
      );
    }
  }

  Future<void> _loadLocalData() async {
    final scope = _localScope;
    _parcels = await DatabaseService.loadLocalParcelShipments(scope: scope);
    _compartments =
        await DatabaseService.loadLocalShelfCompartments(scope: scope);
    _customers = await DatabaseService.loadLocalParcelCustomers(scope: scope);
    _settings =
        await DatabaseService.loadLocalPaketshopSettings(scope: scope) ??
            PaketshopSettings.defaults();
  }

  // --- Mutatoren: Pakete ---------------------------------------------------

  /// Speichert ein Paket (Anlage oder Update) und gibt dessen Id zurück.
  Future<String> saveParcel(ParcelShipment shipment) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    final prepared = shipment.copyWith(orgId: orgId);
    final isNew = prepared.id == null || prepared.id!.isEmpty;
    final fach = _fachSuffix(prepared);

    if (_usesFirestore) {
      String? newId;
      final ok = await _tryFirestore('saveParcel', () async {
        newId = await _parcel.saveParcel(prepared);
      });
      if (ok) {
        _auditParcel(isNew, newId, fach);
        return newId ?? (prepared.id ?? '');
      }
    }

    final stored =
        isNew ? prepared.copyWith(id: _nextLocalId('parcel')) : prepared;
    _parcels = _upsertLocal(_parcels, stored, (p) => p.id);
    _sortParcels();
    await _persistParcels();
    _safeNotify();
    _auditParcel(isNew, stored.id, fach);
    return stored.id!;
  }

  Future<void> deleteParcel(String id) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    final fach = _fachSuffix(_parcelById(id));

    if (_usesFirestore &&
        await _tryFirestore(
          'deleteParcel',
          () => _parcel.deleteParcel(orgId: orgId, id: id),
        )) {
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Paket',
        entityId: id,
        summary: 'Paket gelöscht$fach',
      );
      return;
    }

    _parcels = _parcels.where((p) => p.id != id).toList(growable: true);
    await _persistParcels();
    _safeNotify();
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Paket',
      entityId: id,
      summary: 'Paket gelöscht$fach',
    );
  }

  // --- Mutatoren: Fächer ---------------------------------------------------

  Future<String> saveCompartment(ShelfCompartment compartment) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    final prepared = compartment.copyWith(orgId: orgId);
    final isNew = prepared.id == null || prepared.id!.isEmpty;

    if (_usesFirestore) {
      String? newId;
      final ok = await _tryFirestore('saveCompartment', () async {
        newId = await _parcel.saveCompartment(prepared);
      });
      if (ok) {
        _auditCompartment(isNew, newId, prepared.label);
        return newId ?? (prepared.id ?? '');
      }
    }

    final stored =
        isNew ? prepared.copyWith(id: _nextLocalId('compartment')) : prepared;
    _compartments = _upsertLocal(_compartments, stored, (f) => f.id);
    _compartments.sort((a, b) => a.labelLower.compareTo(b.labelLower));
    await _persistCompartments();
    _safeNotify();
    _auditCompartment(isNew, stored.id, stored.label);
    return stored.id!;
  }

  Future<void> deleteCompartment(String id) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    final label = _compartmentById(id)?.label;

    if (_usesFirestore &&
        await _tryFirestore(
          'deleteCompartment',
          () => _parcel.deleteCompartment(orgId: orgId, id: id),
        )) {
      _auditCompartmentDeleted(id, label);
      return;
    }

    _compartments = _compartments.where((f) => f.id != id).toList(growable: true);
    await _persistCompartments();
    _safeNotify();
    _auditCompartmentDeleted(id, label);
  }

  // --- Mutatoren: Kunden-Namensregister ------------------------------------

  /// Speichert einen Registereintrag (Anlage/Update). **Nicht auditiert** —
  /// Name ist PII und die Anlage ist operatives Rauschen (nur die Löschung ist
  /// fachlich relevant, s. [deleteCustomer]).
  Future<String> saveCustomer(ParcelCustomer customer) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    final prepared = customer.copyWith(orgId: orgId);
    final isNew = prepared.id == null || prepared.id!.isEmpty;

    if (_usesFirestore) {
      String? newId;
      final ok = await _tryFirestore('saveCustomer', () async {
        newId = await _parcel.saveCustomer(prepared);
      });
      if (ok) {
        return newId ?? (prepared.id ?? '');
      }
    }

    final stored =
        isNew ? prepared.copyWith(id: _nextLocalId('customer')) : prepared;
    _customers = _upsertLocal(_customers, stored, (c) => c.id);
    _customers.sort((a, b) => a.nameLower.compareTo(b.nameLower));
    await _persistCustomers();
    _safeNotify();
    return stored.id!;
  }

  /// Legt einen Empfänger im Register an bzw. aktualisiert `lastSeenAt`, wenn
  /// der Name (nach [parcelNameLower]) bereits existiert (Dublettenprüfung).
  Future<ParcelCustomer> upsertCustomer({
    required String firstName,
    required String lastName,
    required String siteId,
  }) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    final key = parcelNameLower(firstName, lastName);
    final now = DateTime.now();

    ParcelCustomer? existing;
    for (final c in _customers) {
      if (c.nameLower == key) {
        existing = c;
        break;
      }
    }

    if (existing != null) {
      final updated = existing.copyWith(lastSeenAt: now);
      final id = await saveCustomer(updated);
      return updated.copyWith(id: id);
    }

    final created = ParcelCustomer(
      orgId: orgId,
      siteId: siteId,
      firstName: firstName,
      lastName: lastName,
      firstSeenAt: now,
      lastSeenAt: now,
    );
    final id = await saveCustomer(created);
    return created.copyWith(id: id);
  }

  /// Löscht einen Registereintrag (Widerspruch/Art. 17) und entkoppelt den
  /// `parcelCustomerId` an allen offenen Paketen. **Auditiert (personenfrei).**
  Future<void> deleteCustomer(String id) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }

    final done = _usesFirestore &&
        await _tryFirestore(
          'deleteCustomer',
          () => _parcel.deleteCustomer(orgId: orgId, id: id),
        );
    if (!done) {
      _customers = _customers.where((c) => c.id != id).toList(growable: true);
      await _persistCustomers();
      _safeNotify();
    }
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Paketkunde',
      entityId: id,
      summary: 'Paketkunde-Registereintrag gelöscht',
    );

    // Fachliche Entkopplung: referenzierende Pakete verlieren den Link.
    final referencing =
        _parcels.where((p) => p.parcelCustomerId == id).toList(growable: false);
    for (final p in referencing) {
      await saveParcel(p.copyWith(clearParcelCustomerId: true));
    }
  }

  // --- Einstellungen -------------------------------------------------------

  Future<void> saveSettings(PaketshopSettings settings) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    _settings = settings;

    if (_usesFirestore &&
        await _tryFirestore(
          'saveSettings',
          () => _parcel.saveSettings(orgId, settings),
        )) {
      if (usesHybridStorage) {
        await DatabaseService.saveLocalPaketshopSettings(
          settings,
          scope: _localScope,
        );
      }
      _safeNotify();
      return;
    }

    await DatabaseService.saveLocalPaketshopSettings(
      settings,
      scope: _localScope,
    );
    _safeNotify();
  }

  // --- intern --------------------------------------------------------------

  void _auditParcel(bool isNew, String? id, String fach) {
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Paket',
      entityId: id,
      summary: isNew ? 'Paket angenommen$fach' : 'Paket aktualisiert$fach',
    );
  }

  void _auditCompartment(bool isNew, String? id, String label) {
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Paketfach',
      entityId: id,
      summary: 'Fach „$label" ${isNew ? 'angelegt' : 'aktualisiert'}',
    );
  }

  void _auditCompartmentDeleted(String id, String? label) {
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Paketfach',
      entityId: id,
      summary: 'Fach${label == null ? '' : ' „$label"'} gelöscht',
    );
  }

  String _fachSuffix(ParcelShipment? shipment) {
    final label = shipment?.compartmentLabel?.trim();
    if (label == null || label.isEmpty) return '';
    return ' (Fach $label)';
  }

  ParcelShipment? _parcelById(String id) {
    for (final p in _parcels) {
      if (p.id == id) return p;
    }
    return null;
  }

  ShelfCompartment? _compartmentById(String id) {
    for (final f in _compartments) {
      if (f.id == id) return f;
    }
    return null;
  }

  void _sortParcels() {
    _parcels.sort(
      (a, b) => a.recipientNameLower.compareTo(b.recipientNameLower),
    );
  }

  Future<void> _persistParcels() =>
      DatabaseService.saveLocalParcelShipments(_parcels, scope: _localScope);

  Future<void> _persistCompartments() =>
      DatabaseService.saveLocalShelfCompartments(
        _compartments,
        scope: _localScope,
      );

  Future<void> _persistCustomers() =>
      DatabaseService.saveLocalParcelCustomers(_customers, scope: _localScope);

  List<T> _upsertLocal<T>(List<T> list, T item, String? Function(T) idOf) {
    final id = idOf(item);
    final index = list.indexWhere((existing) => idOf(existing) == id);
    final next = [...list];
    if (index >= 0) {
      next[index] = item;
    } else {
      next.add(item);
    }
    return next;
  }

  String _nextLocalId(String prefix) {
    _localSeq += 1;
    return 'local-$prefix-${DateTime.now().microsecondsSinceEpoch}-$_localSeq';
  }

  static String _norm(String value) => value.trim().toLowerCase();

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _resetData() {
    _parcels = [];
    _compartments = [];
    _customers = [];
    _settings = PaketshopSettings.defaults();
    _loading = false;
    _errorMessage = null;
  }

  void _setError(Object error) {
    _errorMessage = error is StateError ? error.message : error.toString();
    _loading = false;
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _cancelSubscriptions() async {
    await _parcelsSubscription?.cancel();
    await _compartmentsSubscription?.cancel();
    await _customersSubscription?.cancel();
    _parcelsSubscription = null;
    _compartmentsSubscription = null;
    _customersSubscription = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSubscriptions();
    super.dispose();
  }
}
