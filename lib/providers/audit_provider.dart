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

  AppUserProfile? _currentUser;
  List<AuditLogEntry> _entries = [];
  StreamSubscription<List<AuditLogEntry>>? _subscription;
  bool _disposed = false;
  int _localSeq = 0;
  String? _lastSessionKey;

  List<AuditLogEntry> get entries => _entries;

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

    if (user == null) {
      _entries = [];
      _safeNotify();
      return;
    }
    // Protokoll nur für Admins streamen (Rules erlauben Lesen nur Admins).
    if (_usesFirestore && user.isAdmin) {
      _subscription = _firestore.watchAuditLog(user.orgId).listen((items) {
        _entries = items;
        _safeNotify();
      }, onError: (Object error) {
        AppLogger.warning('Audit: Stream-Fehler', error: error);
      });
    } else {
      _entries = await DatabaseService.loadLocalAuditLog(scope: _localScope);
      _safeNotify();
    }
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
    if (_mirrorsLocally) {
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
