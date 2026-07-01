import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../models/app_user.dart';
import '../models/audit_log_entry.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';

/// Leichtes, clientseitiges Änderungsprotokoll (Audit-Trail).
///
/// Schreibt append-only Einträge für sensible Mutationen (Lohn, Preise,
/// Kontakt-Löschungen). **Best-effort**: ein fehlgeschlagenes Logging darf die
/// eigentliche Aktion nie blockieren. Speicher-Verhalten analog der übrigen
/// Provider (Cloud/Hybrid über Firestore-Stream, local über SharedPreferences;
/// im Hybrid wird zusätzlich lokal gespiegelt). Lesen ist admin-only (Rules).
class AuditProvider extends ChangeNotifier {
  AuditProvider({
    required FirestoreService firestoreService,
    bool? disableAuthentication,
  })  : _firestore = firestoreService,
        _forceLocalStorage =
            disableAuthentication ?? AppConfig.disableAuthentication;

  final FirestoreService _firestore;
  final bool _forceLocalStorage;
  bool _localStorageOnly = false;
  bool _hybridStorageEnabled = false;

  /// Seitengröße / aktuelles Stream-Limit. Wird über [loadMore] erhöht.
  static const int pageSize = 200;

  AppUserProfile? _currentUser;
  List<AuditLogEntry> _entries = [];
  StreamSubscription<List<AuditLogEntry>>? _subscription;
  bool _disposed = false;
  int _localSeq = 0;
  String? _lastSessionKey;
  int _limit = pageSize;
  bool _hasMore = false;
  // Ob der Firestore-Stream die Anzeige speist (Admin + Cloud/Hybrid) — steuert,
  // ob `log()` zusätzlich lokal spiegelt (#43).
  bool _streamActive = false;

  List<AuditLogEntry> get entries => _entries;

  /// Aktuell geladenes Limit des Cloud-Streams (nur im Firestore-Modus aktiv).
  int get limit => _limit;

  /// `true`, wenn der letzte Stream genau das Limit füllte (mehr ladbar).
  bool get hasMore => _hasMore;

  bool get usesLocalStorage => _forceLocalStorage || _localStorageOnly;
  bool get _usesFirestore => !usesLocalStorage;
  bool get usesHybridStorage =>
      !_forceLocalStorage && !_localStorageOnly && _hybridStorageEnabled;
  bool get _mirrorsLocally => usesLocalStorage || usesHybridStorage;

  String? get _orgId => _currentUser?.orgId;

  LocalStorageScope? get _localScope {
    final user = _currentUser;
    if (user == null) return null;
    return LocalStorageScope.fromUser(user);
  }

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
    await _subscription?.cancel();
    _subscription = null;
    // Beim Sessionwechsel die Seitengröße zurücksetzen (kein „Mehr laden"-Leck
    // in eine andere Org/Modus).
    _limit = pageSize;
    _hasMore = false;

    if (user == null) {
      _entries = [];
      _safeNotify();
      return;
    }
    // Protokoll nur für Admins streamen (Rules erlauben Lesen nur Admins).
    if (_usesFirestore && user.isAdmin) {
      _streamActive = true;
      _subscribeFirestore(user.orgId);
    } else {
      _streamActive = false;
      // #42: Lese- und Schreibpfad konsistent halten — nur wenn lokal gespiegelt
      // wird (local/hybrid) das lokale Log laden; im reinen cloud-only-Modus für
      // Nicht-Admins gibt es keinen lokalen Mirror → leer statt veraltet.
      _entries = _mirrorsLocally
          ? await DatabaseService.loadLocalAuditLog(scope: _localScope)
          : <AuditLogEntry>[];
      _safeNotify();
    }
  }

  void _subscribeFirestore(String orgId) {
    _subscription?.cancel();
    _subscription =
        _firestore.watchAuditLog(orgId, limit: _limit).listen((items) {
      _entries = items;
      // Wenn der Stream das Limit exakt füllt, gibt es vermutlich mehr.
      _hasMore = items.length >= _limit;
      _safeNotify();
    }, onError: (Object error) {
      AppLogger.warning('Audit: Stream-Fehler', error: error);
    });
  }

  /// Lädt die nächste Seite (erhöht das Cloud-Stream-Limit). Nur im
  /// Firestore-Admin-Modus wirksam; im lokalen Modus liegt ohnehin alles vor.
  Future<void> loadMore() async {
    final user = _currentUser;
    if (user == null || !_usesFirestore || !user.isAdmin || !_hasMore) {
      return;
    }
    _limit += pageSize;
    _subscribeFirestore(user.orgId);
  }

  /// Protokolliert eine Änderung (best-effort – wirft nie).
  Future<void> log({
    required AuditAction action,
    required String entityType,
    String? entityId,
    required String summary,
  }) async {
    final orgId = _orgId;
    if (orgId == null) return;
    final entry = AuditLogEntry(
      orgId: orgId,
      action: action,
      entityType: entityType,
      entityId: entityId,
      summary: summary,
      actorUid: _currentUser?.uid,
      actorName: _currentUser?.displayName,
      createdAt: DateTime.now(),
    );
    if (_usesFirestore) {
      try {
        await _firestore.appendAuditLog(entry);
        if (!usesHybridStorage) return;
      } catch (error) {
        AppLogger.warning('Audit: Schreiben fehlgeschlagen', error: error);
        if (!usesHybridStorage) return;
      }
    }
    // #43: Wenn der Firestore-Stream aktiv ist (Admin), liefert er den neuen
    // Eintrag ohnehin — kein lokaler Prepend (sonst transienter Doppel-Eintrag
    // bis zum nächsten Snapshot). Lokal gespiegelt wird nur, wenn kein Stream
    // die Anzeige speist (local/hybrid-Nicht-Admin).
    if (_mirrorsLocally && !_streamActive) {
      _localSeq += 1;
      final stored = entry.copyWith(
        id: 'local-audit-${DateTime.now().microsecondsSinceEpoch}-$_localSeq',
      );
      _entries = [stored, ..._entries];
      try {
        await DatabaseService.saveLocalAuditLog(_entries, scope: _localScope);
      } catch (error) {
        AppLogger.warning('Audit: lokale Persistenz fehlgeschlagen',
            error: error);
      }
      _safeNotify();
    }
  }

  // --- Speichermodus-Migration (H-H1) -------------------------------------

  /// Snapshot des aktuellen (Cloud-)Protokolls in den lokalen Speicher, damit
  /// der Verlauf nach dem Wechsel in den local-Modus sichtbar bleibt.
  Future<void> cacheCloudStateLocally() async {
    if (usesLocalStorage) return;
    try {
      await DatabaseService.saveLocalAuditLog(_entries, scope: _localScope);
    } catch (error) {
      AppLogger.warning('cacheCloudStateLocally(audit): $error');
    }
  }

  /// Das Protokoll ist **append-only**: ein erneutes Hochladen lokaler Einträge
  /// würde duplizieren. Lokale Audit-Einträge bleiben daher bewusst lokal (kein
  /// Up-Sync). Methode existiert nur für einen einheitlichen Aufruf in
  /// settings_screen.
  Future<void> syncLocalStateToCloud() async {}

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
