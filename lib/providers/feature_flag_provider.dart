import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/error_reporter.dart';
import '../core/firestore_num_parser.dart' as parse;
import '../models/app_user.dart';
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

  Future<void> updateSession(
    AppUserProfile? user, {
    bool localStorageOnly = false,
    bool hybridStorageEnabled = false,
  }) async {
    final orgId = user?.orgId;
    // Im reinen Offline-/Demo-Modus oder ohne angemeldeten Nutzer gibt es keine
    // Remote-Config -> zuruecksetzen, kein Firestore-Read.
    if (user == null ||
        orgId == null ||
        orgId.isEmpty ||
        localStorageOnly ||
        AppConfig.disableAuthentication) {
      _resetIfNeeded();
      _sessionDedupKey = null;
      return;
    }

    final dedupKey = orgId;
    if (dedupKey == _sessionDedupKey) {
      return;
    }
    _sessionDedupKey = dedupKey;

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
