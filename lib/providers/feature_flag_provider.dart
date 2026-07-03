import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/error_reporter.dart';
import '../core/firestore_num_parser.dart' as parse;
import '../models/app_user.dart';
import '../models/org_settings.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';

/// Liest org-skopierte Remote-Konfiguration (Mindest-Build-Nummer +
/// Feature-Flags) aus `organizations/{orgId}/config/appFlags` und stellt ein
/// Force-Update-Signal bereit (no-feature-flags-force-update). Entkoppelt Deploy
/// von Release: ein fehlerhaftes Feature kann serverseitig deaktiviert und eine
/// zu alte App-Version zum Update gezwungen werden – ohne Store-Roundtrip.
///
/// Ergaenzt das bereits serverseitig vorhandene `APP_UPDATE_REQUIRED`-Signal der
/// Callables (no-api-contract-versioning) um den Client-Gate.
class FeatureFlagProvider extends ChangeNotifier {
  FeatureFlagProvider({
    required FirestoreService firestoreService,
    int? currentBuildNumber,
  })  : _firestoreService = firestoreService,
        _currentBuildNumber = currentBuildNumber ?? AppConfig.buildNumber;

  final FirestoreService _firestoreService;
  final int _currentBuildNumber;

  bool _disposed = false;
  int _minimumBuildNumber = 0;
  Map<String, bool> _flags = const {};
  String? _updateMessage;
  String? _sessionDedupKey;

  // Org-weite operative Einstellungen (Auto-Schichtverteilung). Bewusst hier
  // mitgeführt statt eigener Provider — FeatureFlagProvider hängt bereits in der
  // Kette (Proxy2<Auth,Storage>) und wird vom go_router-Redirect gelesen.
  OrgSettings? _orgSettings;
  String? _orgId;
  bool _localStorageOnly = false;
  bool _hybridStorageEnabled = false;
  LocalStorageScope? _localScope;

  /// True, wenn der Server eine hoehere Mindest-Build-Nummer fordert als dieses
  /// Binary hat. Greift NUR bei echten Release-Builds (buildNumber > 0);
  /// Dev-/Local-Builds (buildNumber 0) werden nie blockiert. Fail-open: fehlt
  /// das Config-Doc oder schlaegt der Read fehl, bleibt [minimumBuildNumber] 0.
  bool get requiresUpdate =>
      _currentBuildNumber > 0 && _minimumBuildNumber > _currentBuildNumber;

  int get minimumBuildNumber => _minimumBuildNumber;
  int get currentBuildNumber => _currentBuildNumber;
  String? get updateMessage => _updateMessage;

  /// Laufzeit-Feature-Flag; [fallback] greift, wenn der Server nichts vorgibt.
  bool isEnabled(String flag, {bool fallback = false}) =>
      _flags[flag] ?? fallback;

  /// Org-weite operative Einstellungen; liefert [OrgSettings.defaults], solange
  /// nichts geladen ist (fail-safe — nie null).
  OrgSettings get orgSettings => _orgSettings ?? OrgSettings.defaults(_orgId ?? '');

  /// Bequemer Zugriff: ob Stundengrenzen im Verteiler hart durchgesetzt werden.
  bool get enforceHourCapHard => orgSettings.enforceHourCapHard;

  /// Bequemer Zugriff (Kassen-Modul E1/§3.4): ob die gepflegten Einkaufspreise
  /// MwSt enthalten (brutto) und für Rohertrag/Wareneinsatz normalisiert werden.
  bool get purchasePricesIncludeVat => orgSettings.purchasePricesIncludeVat;

  Future<void> updateSession(
    AppUserProfile? user, {
    bool localStorageOnly = false,
    bool hybridStorageEnabled = false,
  }) async {
    final orgId = user?.orgId;
    _localStorageOnly = localStorageOnly;
    _hybridStorageEnabled = hybridStorageEnabled;

    if (user == null || orgId == null || orgId.isEmpty) {
      _orgId = null;
      _localScope = null;
      _resetIfNeeded();
      _resetOrgSettingsIfNeeded();
      _sessionDedupKey = null;
      return;
    }
    _orgId = orgId;
    _localScope = LocalStorageScope.fromUser(user);

    final dedupKey = '$orgId|$localStorageOnly|$hybridStorageEnabled';
    if (dedupKey == _sessionDedupKey) {
      return;
    }
    _sessionDedupKey = dedupKey;

    // OrgSettings auch im Local-/Demo-Modus laden (aus lokalem Speicher) — der
    // Cap-Toggle muss überall greifen, nicht nur bei aktivem Firebase.
    await _loadOrgSettings(
      orgId,
      localStorageOnly: localStorageOnly,
      hybridStorageEnabled: hybridStorageEnabled,
    );

    // Im reinen Offline-/Demo-Modus gibt es keine Remote-AppConfig -> Flags
    // zuruecksetzen, kein Firestore-Read.
    if (localStorageOnly || AppConfig.disableAuthentication) {
      _resetIfNeeded();
      return;
    }

    try {
      final data = await _firestoreService.fetchAppConfig(orgId);
      _applyConfig(data);
    } catch (error, stackTrace) {
      // Fail-open: ein fehlgeschlagener Read darf Nutzer NICHT aussperren.
      ErrorReporter.report(error, stackTrace,
          context: 'FeatureFlagProvider.fetchAppConfig');
      AppLogger.warning('Remote-Config konnte nicht geladen werden',
          error: error);
    }
  }

  Future<void> _loadOrgSettings(
    String orgId, {
    required bool localStorageOnly,
    required bool hybridStorageEnabled,
  }) async {
    final useLocalOnly = localStorageOnly || AppConfig.disableAuthentication;
    if (useLocalOnly) {
      final local = await DatabaseService.loadLocalOrgSettings(scope: _localScope);
      _setOrgSettings(local ?? OrgSettings.defaults(orgId));
      return;
    }
    try {
      final remote = await _firestoreService.fetchOrgSettings(orgId);
      final resolved = remote ?? OrgSettings.defaults(orgId);
      _setOrgSettings(resolved);
      // Hybrid: Remote-Snapshot lokal spiegeln (nur, wenn es ein Doc gibt).
      if (hybridStorageEnabled && remote != null && _localScope != null) {
        await DatabaseService.saveLocalOrgSettings(resolved, scope: _localScope);
      }
    } catch (error, stackTrace) {
      // Fail-safe: lokalen Snapshot bzw. Defaults verwenden.
      ErrorReporter.report(error, stackTrace,
          context: 'FeatureFlagProvider.fetchOrgSettings');
      final local = await DatabaseService.loadLocalOrgSettings(scope: _localScope);
      _setOrgSettings(local ?? OrgSettings.defaults(orgId));
    }
  }

  /// Speichert die org-weiten operativen Einstellungen (admin-only über die
  /// Rules erzwungen) und aktualisiert den In-Memory-Stand. Storage-Modus-
  /// Muster: local/demo -> nur lokal; cloud -> Firestore; hybrid -> beides.
  /// Audit erfolgt bewusst aus der UI (AuditProvider), nicht hier.
  Future<void> saveOrgSettings(OrgSettings settings) async {
    final orgId = _orgId;
    if (orgId == null || orgId.isEmpty) {
      return;
    }
    final prepared = settings.copyWith(orgId: orgId);
    final useLocalOnly = _localStorageOnly || AppConfig.disableAuthentication;
    if (useLocalOnly) {
      await DatabaseService.saveLocalOrgSettings(prepared, scope: _localScope);
      _setOrgSettings(prepared);
      return;
    }
    await _firestoreService.saveOrgSettings(prepared);
    if (_hybridStorageEnabled && _localScope != null) {
      await DatabaseService.saveLocalOrgSettings(prepared, scope: _localScope);
    }
    _setOrgSettings(prepared);
  }

  void _setOrgSettings(OrgSettings settings) {
    final current = _orgSettings;
    if (current != null &&
        current.orgId == settings.orgId &&
        current.enforceHourCapHard == settings.enforceHourCapHard &&
        current.defaultShiftMinutes == settings.defaultShiftMinutes &&
        current.defaultBreakMinutes == settings.defaultBreakMinutes &&
        current.defaultRequiredCount == settings.defaultRequiredCount &&
        current.purchasePricesIncludeVat == settings.purchasePricesIncludeVat) {
      return;
    }
    _orgSettings = settings;
    _safeNotify();
  }

  void _resetOrgSettingsIfNeeded() {
    if (_orgSettings == null) {
      return;
    }
    _orgSettings = null;
    _safeNotify();
  }

  void _applyConfig(Map<String, dynamic>? data) {
    if (data == null) {
      _resetIfNeeded();
      return;
    }
    _minimumBuildNumber = parse.toInt(data['minimumBuildNumber']) ?? 0;
    final message = (data['updateMessage'] as String?)?.trim();
    _updateMessage = (message == null || message.isEmpty) ? null : message;
    final rawFlags = parse.toMap(data['featureFlags']);
    _flags = {
      for (final entry in rawFlags.entries)
        entry.key: parse.toBool(entry.value) ?? false,
    };
    _safeNotify();
  }

  void _resetIfNeeded() {
    if (_minimumBuildNumber == 0 && _flags.isEmpty && _updateMessage == null) {
      return;
    }
    _minimumBuildNumber = 0;
    _flags = const {};
    _updateMessage = null;
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
