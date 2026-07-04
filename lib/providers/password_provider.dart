import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../models/app_user.dart';
import '../models/password_entry.dart';
import '../services/firestore_service.dart';
import 'audit_sink.dart';

/// **Passwortmanager-Provider (§5.1).** Rein server-verschlüsselt (Cloud KMS +
/// Callables) → funktioniert NUR mit echtem Firebase/Blaze. Im Offline-/Demo-
/// Modus ([AppConfig.disableAuthentication]) und im lokalen Speichermodus ist
/// das Feature komplett **deaktiviert** (kein halb-degradiertes Feature).
///
/// Es gibt bewusst KEINEN Client-Stream und KEINEN Direkt-Write: die
/// zugriffsgestufte Metadaten-Liste kommt server-gefiltert über
/// `listPasswordEntries`, alle Mutationen laufen über Callables.
class PasswordProvider extends ChangeNotifier {
  PasswordProvider({
    required FirestoreService firestoreService,
    bool? featureEnabledOverride,
  })  : _firestoreService = firestoreService,
        _featureEnabledOverride = featureEnabledOverride;

  final FirestoreService _firestoreService;

  /// Test-Override für den compile-time-Flag [AppConfig.passwordManagerEnabled]
  /// (der in Tests ohne dart-define immer false wäre).
  final bool? _featureEnabledOverride;

  AppUserProfile? _currentUser;
  List<PasswordEntry> _entries = const [];
  bool _loading = false;
  String? _errorMessage;
  bool _disposed = false;
  bool _localStorageOnly = false;
  String? _lastSessionKey;

  List<PasswordEntry> get entries => _entries;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;
  String? get orgId => _currentUser?.orgId;

  /// Feature aktiv nur mit echtem Firebase (nicht disableAuth) UND nicht im
  /// lokalen Speichermodus (Callables brauchen die Cloud).
  bool get isEnabled =>
      (_featureEnabledOverride ?? AppConfig.passwordManagerEnabled) &&
      !_localStorageOnly;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Best-effort-Audit läuft serverseitig in den Callables → hier No-op (kein
  /// Doppel-Logging). Methode existiert für den Proxy-Vertrag in main.dart.
  void setAuditSink(AuditSink _) {}

  void surfaceSessionError(Object error) {
    _errorMessage =
        'Passwörter konnten nicht geladen werden. Bitte später erneut versuchen.';
    _safeNotify();
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      _safeNotify();
    }
  }

  Future<void> updateSession(
    AppUserProfile? user, {
    bool localStorageOnly = false,
    bool hybridStorageEnabled = false,
  }) async {
    _localStorageOnly = localStorageOnly;
    final sessionKey = (user == null || !isEnabled)
        ? null
        : '${user.uid}:${user.orgId}:${localStorageOnly ? 'local' : 'cloud'}';
    _currentUser = user;
    if (sessionKey == _lastSessionKey) return;
    _lastSessionKey = sessionKey;

    if (sessionKey == null) {
      _entries = const [];
      _loading = false;
      _errorMessage = null;
      _safeNotify();
      return;
    }
    await refresh();
  }

  /// Lädt die sichtbaren Metadaten neu (server-gefiltert).
  Future<void> refresh() async {
    final org = orgId;
    if (org == null || !isEnabled) return;
    _loading = true;
    _errorMessage = null;
    _safeNotify();
    try {
      _entries = await _firestoreService.listPasswordEntries(org);
      _loading = false;
      _safeNotify();
    } catch (error) {
      AppLogger.warning('PasswordProvider: Laden fehlgeschlagen', error: error);
      _errorMessage = 'Passwörter konnten nicht geladen werden.';
      _loading = false;
      _safeNotify();
    }
  }

  /// Legt an/aktualisiert einen Eintrag (+ optional Klartext-Secret). Lädt die
  /// Liste danach neu. Wirft bei fehlender Berechtigung/Fehler (deutsche
  /// Message), die die UI anzeigt.
  Future<void> save({
    required PasswordEntry entry,
    String? plainUsername,
    String? plainPassword,
    String? plainNotes,
  }) async {
    final org = orgId;
    if (org == null || !isEnabled) return;
    await _firestoreService.upsertPasswordEntry(
      entry: entry,
      plainUsername: plainUsername,
      plainPassword: plainPassword,
      plainNotes: plainNotes,
    );
    await refresh();
  }

  Future<void> delete(String entryId) async {
    final org = orgId;
    if (org == null || !isEnabled) return;
    await _firestoreService.deletePasswordEntry(orgId: org, entryId: entryId);
    await refresh();
  }

  /// Fordert einen server-signierten Reauth-Nonce an (Pflicht vor Reveal).
  Future<String?> beginReauth() async {
    final org = orgId;
    if (org == null || !isEnabled) return null;
    return _firestoreService.beginPasswordReauth(org);
  }

  /// Zeigt das Secret an (autorisiert + auditiert). Ergebnis transient — NIE im
  /// Provider-State halten.
  Future<PasswordSecret> reveal(
    String entryId, {
    String? reauthToken,
    String? reason,
  }) async {
    final org = orgId;
    if (org == null || !isEnabled) {
      throw StateError('Passwortmanager ist nicht verfügbar.');
    }
    return _firestoreService.revealPasswordSecret(
      orgId: org,
      entryId: entryId,
      reauthToken: reauthToken,
      reason: reason,
    );
  }

  Future<void> logCopy(String entryId, {String? field}) async {
    final org = orgId;
    if (org == null || !isEnabled) return;
    try {
      await _firestoreService.logPasswordCopy(
          orgId: org, entryId: entryId, field: field);
    } catch (error) {
      // Best-effort — Kopieren darf nicht an der Protokollierung scheitern.
      AppLogger.warning('PasswordProvider: Copy-Log fehlgeschlagen',
          error: error);
    }
  }
}
