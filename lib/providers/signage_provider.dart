import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../models/ad_media.dart';
import '../models/app_user.dart';
import '../models/audit_log_entry.dart';
import '../models/signage_display.dart';
import '../repositories/signage_repository.dart';
import '../services/database_service.dart';
import '../services/document_storage.dart';
import '../services/firestore_service.dart';
import 'audit_sink.dart';

/// Verwaltet die digitalen Werbe-Displays (Store-Fernseher): die Werbebild-
/// Bibliothek ([AdMedia]), die Displays ([SignageDisplay]) samt Playlist und die
/// öffentliche Player-Projektion (`publicDisplays/{token}`), die ein Fernseher
/// login-frei über die Route `/anzeige/<token>` liest.
///
/// **Admin-only** (die Screen-/Route-Gates prüfen `isAdmin`; die firestore.rules
/// spiegeln das server-seitig). Struktur analog [ContactProvider] +
/// [PersonalProvider] (Storage-Seam für den Bild-Upload).
///
/// Bild-Upload + öffentlicher Player sind **cloud-only** (Firebase Storage +
/// Firestore). Im lokalen/Demo-Modus ([AppConfig.disableAuthentication] bzw.
/// localStorageOnly) bleiben Displays offline verwaltbar, aber ohne Upload und
/// ohne veröffentlichte Projektion.
class SignageProvider extends ChangeNotifier {
  SignageProvider({
    required FirestoreService firestoreService,
    SignageRepository? signageRepository,
    bool? disableAuthentication,
  })  : _firestoreService = firestoreService,
        _injectedSignage = signageRepository,
        _forceLocalStorage =
            disableAuthentication ?? AppConfig.disableAuthentication;

  final FirestoreService _firestoreService;
  final SignageRepository? _injectedSignage;

  // Cloud-Repository LAZY (wie [ContactProvider]): im lokalen/disableAuth-Modus
  // nie aufgelöst, sonst würde FirebaseFirestore.instance ohne Firebase schon
  // bei der Provider-Konstruktion crashen (rote Fehlerseite).
  SignageRepository get _signage =>
      _injectedSignage ?? _firestoreService.signageRepository;

  final bool _forceLocalStorage;
  bool _localStorageOnly = false;
  bool _hybridStorageEnabled = false;

  // Storage-Seam für den Bild-Upload (nur konstruiert, wenn Firebase aktiv ist;
  // sonst null → Upload deaktiviert). Verdrahtet in main.dart.
  DocumentStorage? _documentStorage;
  void setDocumentStorage(DocumentStorage storage) {
    _documentStorage = storage;
  }

  StreamSubscription<List<AdMedia>>? _mediaSubscription;
  StreamSubscription<List<SignageDisplay>>? _displaysSubscription;

  AppUserProfile? _currentUser;
  List<AdMedia> _media = [];
  List<SignageDisplay> _displays = [];
  bool _loading = false;
  String? _errorMessage;
  bool _disposed = false;
  int _localSeq = 0;

  List<AdMedia> get media => _media;
  List<SignageDisplay> get displays => _displays;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;

  bool get usesLocalStorage => _forceLocalStorage || _localStorageOnly;
  bool get _usesFirestore => !usesLocalStorage;
  bool get usesHybridStorage =>
      !_forceLocalStorage && !_localStorageOnly && _hybridStorageEnabled;
  String? get _orgId => _currentUser?.orgId;

  /// Ob der Bild-Upload möglich ist (Firebase Storage + Cloud-Modus). Im
  /// Offline-/Demo-Modus false → die UI zeigt einen ehrlichen Hinweis.
  bool get mediaUploadAvailable => _documentStorage != null && _usesFirestore;

  AdMedia? mediaById(String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final item in _media) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  SignageDisplay? displayById(String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final item in _displays) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

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
        'Signage: $label offline – lokaler Fallback aktiv',
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
    _loading = false;
    _safeNotify();
  }

  /// Macht einen Fehler beim fire-and-forget-Sitzungsaufbau in der UI sichtbar.
  void surfaceSessionError(Object error) {
    _errorMessage =
        'Werbe-Displays konnten nicht geladen werden. Bitte später erneut versuchen.';
    _safeNotify();
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      _safeNotify();
    }
  }

  AuditSink? _audit;

  /// Senke fürs Änderungsprotokoll (best-effort). Wird in main.dart verdrahtet.
  void setAuditSink(AuditSink sink) {
    _audit = sink;
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

    // Der gesamte Bereich ist admin-only (Screen/Route/Rules). Für Nicht-Admins
    // gar nicht erst laden/abonnieren — spart Reads und hält den pairingToken
    // (Bearer-Secret) admin-seitig (spiegelt die admin-only Firestore-Rules).
    if (user == null || !user.isAdmin) {
      _media = [];
      _displays = [];
      _loading = false;
      _safeNotify();
      return;
    }

    if (_usesFirestore) {
      _startFirestoreSubscriptions(user.orgId);
    } else {
      await _loadLocalData();
      _safeNotify();
    }
  }

  Future<void> _loadLocalData() async {
    _media = await DatabaseService.loadLocalAdMedia(scope: _localScope);
    _displays = await DatabaseService.loadLocalSignageDisplays(scope: _localScope);
  }

  Future<void> _persistMedia() =>
      DatabaseService.saveLocalAdMedia(_media, scope: _localScope);

  Future<void> _persistDisplays() =>
      DatabaseService.saveLocalSignageDisplays(_displays, scope: _localScope);

  void _startFirestoreSubscriptions(String orgId) {
    _loading = true;
    _safeNotify();

    _mediaSubscription = _signage.watchMedia(orgId).listen((items) {
      _media = items;
      _loading = false;
      _safeNotify();
    }, onError: _setError);

    _displaysSubscription = _signage.watchDisplays(orgId).listen((items) {
      _displays = items;
      _safeNotify();
    }, onError: _setError);
  }

  Future<void> _cancelSubscriptions() async {
    await _mediaSubscription?.cancel();
    _mediaSubscription = null;
    await _displaysSubscription?.cancel();
    _displaysSubscription = null;
  }

  String _nextLocalId(String prefix) {
    _localSeq += 1;
    return 'local-$prefix-${DateTime.now().microsecondsSinceEpoch}-$_localSeq';
  }

  void _sortDisplays() {
    _displays.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  void _sortMedia() {
    _media.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  // --- Werbebild-Bibliothek -------------------------------------------------

  /// Lädt ein Werbebild nach Firebase Storage hoch und legt den Metadaten-
  /// Eintrag an. **Cloud-only** – wirft [StateError], wenn Storage/Cloud fehlt
  /// (Offline-/Demo-Modus). [bytes] kommt aus `file_picker` (`withData: true`),
  /// funktioniert so auf Web UND Mobile.
  Future<AdMedia> uploadMedia({
    required String title,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    final storage = _documentStorage;
    if (storage == null || !_usesFirestore) {
      throw StateError('Bild-Upload benötigt den Cloud-Modus (Firebase).');
    }

    // Storage-Objektname (eigene Id) ≠ Firestore-Doc-Id: der Metadaten-Eintrag
    // wird mit id:null gespeichert, damit das Repository eine frische Doc-Id
    // vergibt UND createdAt via serverTimestamp setzt (die Storage-Referenz
    // steht in storagePath, muss also nicht mit der Doc-Id übereinstimmen).
    final storageId = _signage.newMediaId(orgId);
    final ext = _safeExtension(fileExtension);
    final storagePath = 'organizations/$orgId/signage/$storageId.$ext';
    final contentType = _contentTypeFor(ext);

    await storage.upload(
      path: storagePath,
      bytes: bytes,
      contentType: contentType,
    );

    final String url;
    try {
      url = await storage.getDownloadUrl(storagePath);
    } catch (error) {
      // Ohne URL ist der Eintrag wertlos → hochgeladenes Objekt zurückrollen.
      try {
        await storage.delete(storagePath);
      } catch (_) {}
      rethrow;
    }

    final media = AdMedia(
      orgId: orgId,
      title: title.trim().isEmpty ? 'Werbebild' : title.trim(),
      storagePath: storagePath,
      downloadUrl: url,
      contentType: contentType,
      fileSize: bytes.length,
      createdByUid: _currentUser?.uid,
    );

    try {
      await _signage.saveMedia(media);
    } catch (error) {
      // Metadaten-Write fehlgeschlagen → kein verwaistes Storage-Objekt lassen.
      try {
        await storage.delete(storagePath);
      } catch (_) {}
      rethrow;
    }

    _audit?.call(
      action: AuditAction.created,
      entityType: 'Werbebild',
      // Doc-Id vergibt das Repository (Cloud) → hier null (bekannte, harmlose
      // Einschränkung wie bei anderen Cloud-erzeugten Stammdaten).
      entityId: null,
      summary: 'Werbebild „${media.title}" hochgeladen',
    );
    return media;
  }

  /// Benennt ein Werbebild um (nur der Verwaltungs-Titel; ohne Player-Wirkung).
  Future<void> renameMedia(AdMedia media, String title) async {
    final orgId = _orgId;
    if (orgId == null || media.id == null) {
      return;
    }
    final updated = media.copyWith(orgId: orgId, title: title.trim());
    if (_usesFirestore &&
        await _tryFirestore('renameMedia', () => _signage.saveMedia(updated))) {
      _audit?.call(
        action: AuditAction.updated,
        entityType: 'Werbebild',
        entityId: media.id,
        summary: 'Werbebild in „${updated.title}" umbenannt',
      );
      return;
    }
    _upsertMediaLocal(updated);
    _sortMedia();
    await _persistMedia();
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Werbebild',
      entityId: media.id,
      summary: 'Werbebild in „${updated.title}" umbenannt',
    );
    _safeNotify();
  }

  /// Löscht ein Werbebild: Storage-Objekt + Metadaten + Verweise in allen
  /// Displays (die dann neu projiziert werden).
  Future<void> deleteMedia(String mediaId) async {
    final orgId = _orgId;
    if (orgId == null) {
      return;
    }
    final media = mediaById(mediaId);
    final title = media?.title ?? mediaId;

    // 1) Storage-Objekt best-effort löschen.
    final storage = _documentStorage;
    if (storage != null && media != null && media.storagePath.isNotEmpty) {
      try {
        await storage.delete(media.storagePath);
      } catch (_) {}
    }

    // 2) Metadaten-Doc löschen (cloud → sonst lokal).
    final removedFromCloud = _usesFirestore &&
        await _tryFirestore(
          'deleteMedia',
          () => _signage.deleteMedia(orgId: orgId, mediaId: mediaId),
        );
    if (!removedFromCloud) {
      _media = _media.where((m) => m.id != mediaId).toList(growable: false);
      await _persistMedia();
    }

    // 3) Aus allen Playlists entfernen und die betroffenen Displays neu
    //    projizieren (kein verwaister Verweis auf ein gelöschtes Bild).
    await _pruneMediaFromDisplays(mediaId);

    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Werbebild',
      entityId: mediaId,
      summary: 'Werbebild „$title" gelöscht',
    );
    if (!removedFromCloud) {
      _safeNotify();
    }
  }

  Future<void> _pruneMediaFromDisplays(String mediaId) async {
    final affected = _displays
        .where((display) => display.mediaIds.contains(mediaId))
        .toList(growable: false);
    for (final display in affected) {
      final updated = display.copyWith(
        mediaIds: display.mediaIds
            .where((id) => id != mediaId)
            .toList(growable: false),
      );
      await _writeDisplay(updated, isNew: false, audit: false);
    }
  }

  void _upsertMediaLocal(AdMedia item) {
    final index = _media.indexWhere((existing) => existing.id == item.id);
    if (index >= 0) {
      _media[index] = item;
    } else {
      _media = [..._media, item];
    }
  }

  // --- Displays -------------------------------------------------------------

  /// Legt ein Display an oder aktualisiert es (Name, Standort, Playlist, Dauer,
  /// Einpassung). Bei Neuanlage wird ein [SignageDisplay.pairingToken] erzeugt.
  /// Nach dem Speichern wird die öffentliche Projektion aktualisiert.
  Future<void> saveDisplay(SignageDisplay display) async {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    final isNew = display.id == null || display.id!.isEmpty;
    final prepared = display.copyWith(
      orgId: orgId,
      createdByUid: display.createdByUid ?? _currentUser?.uid,
      pairingToken:
          display.pairingToken.isEmpty ? _generateToken() : display.pairingToken,
    );
    await _writeDisplay(prepared, isNew: isNew, audit: true);
  }

  /// Aktiviert/deaktiviert ein Display (deaktiviert ⇒ öffentliche Projektion
  /// wird entfernt, der Fernseher wird leer).
  Future<void> setDisplayActive(SignageDisplay display, {required bool isActive}) {
    return saveDisplay(display.copyWith(isActive: isActive));
  }

  /// Setzt die geordnete Playlist eines Displays neu (Drag-&-Drop / Auswahl).
  Future<void> setDisplayPlaylist(SignageDisplay display, List<String> mediaIds) {
    return saveDisplay(display.copyWith(mediaIds: mediaIds));
  }

  /// Gemeinsamer Schreibpfad für Displays: cloud (→ öffentliche Projektion) mit
  /// hybrid-lokalem Fallback bzw. rein lokal. [audit] steuert das Protokoll
  /// (false z.B. beim automatischen Entfernen eines gelöschten Bildes).
  Future<void> _writeDisplay(
    SignageDisplay prepared, {
    required bool isNew,
    required bool audit,
  }) async {
    if (_usesFirestore &&
        await _tryFirestore(
          'saveDisplay',
          () => _signage.saveDisplay(prepared),
        )) {
      await _publishProjection(prepared);
      if (audit) {
        _auditDisplaySaved(isNew, prepared.id, prepared.name);
      }
      return;
    }
    final stored = prepared.id == null
        ? prepared.copyWith(id: _nextLocalId('display'))
        : prepared;
    _upsertDisplayLocal(stored);
    _sortDisplays();
    await _persistDisplays();
    if (audit) {
      _auditDisplaySaved(isNew, stored.id, stored.name);
    }
    _safeNotify();
  }

  Future<void> deleteDisplay(String displayId) async {
    final orgId = _orgId;
    if (orgId == null) {
      return;
    }
    final display = displayById(displayId);
    final name = display?.name ?? displayId;
    if (_usesFirestore &&
        await _tryFirestore(
          'deleteDisplay',
          () => _signage.deleteDisplay(orgId: orgId, displayId: displayId),
        )) {
      if (display != null) {
        await _unpublish(display.pairingToken);
      }
      _auditDisplayDeleted(displayId, name);
      return;
    }
    _displays =
        _displays.where((d) => d.id != displayId).toList(growable: false);
    await _persistDisplays();
    _auditDisplayDeleted(displayId, name);
    _safeNotify();
  }

  void _upsertDisplayLocal(SignageDisplay item) {
    final index = _displays.indexWhere((existing) => existing.id == item.id);
    if (index >= 0) {
      _displays[index] = item;
    } else {
      _displays = [..._displays, item];
    }
  }

  void _auditDisplaySaved(bool isNew, String? id, String name) {
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Werbe-Display',
      entityId: id,
      summary: 'Display „$name" ${isNew ? 'angelegt' : 'aktualisiert'}',
    );
  }

  void _auditDisplayDeleted(String id, String name) {
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Werbe-Display',
      entityId: id,
      summary: 'Display „$name" gelöscht',
    );
  }

  // --- Öffentliche Player-Projektion ---------------------------------------

  /// Schreibt die denormalisierte, öffentlich lesbare Projektion eines Displays.
  /// Auch pausierte Displays werden veröffentlicht (mit `isActive:false`), damit
  /// der Player „pausiert" statt „nicht gefunden" zeigt — die Projektion wird
  /// erst beim tatsächlichen LÖSCHEN entfernt (siehe [deleteDisplay]).
  /// Best-effort: der öffentliche Player ist cloud-only; lokal/offline passiert
  /// nichts.
  Future<void> _publishProjection(SignageDisplay display) async {
    if (!_usesFirestore) {
      return;
    }
    final token = display.pairingToken;
    if (token.isEmpty) {
      return;
    }
    try {
      await _signage.publishPublicDisplay(token, _projectionFor(display));
    } catch (error) {
      AppLogger.warning(
        'Signage: Projektion für „${display.name}" nicht veröffentlicht',
        error: error,
      );
    }
  }

  Future<void> _unpublish(String token) async {
    if (!_usesFirestore || token.isEmpty) {
      return;
    }
    try {
      await _signage.unpublishPublicDisplay(token);
    } catch (error) {
      AppLogger.warning('Signage: Projektion nicht entfernt', error: error);
    }
  }

  Map<String, dynamic> _projectionFor(SignageDisplay display) {
    final slides = <Map<String, dynamic>>[];
    for (final mediaId in display.mediaIds) {
      final media = mediaById(mediaId);
      if (media == null || media.downloadUrl.isEmpty) {
        continue;
      }
      slides.add({
        'url': media.downloadUrl,
        'seconds': display.slideSeconds,
        'title': media.title,
      });
    }
    return {
      'orgId': display.orgId,
      'name': display.name.trim(),
      'slideSeconds': display.slideSeconds,
      'fit': display.fit.value,
      'transition': display.transition.value,
      'isActive': display.isActive,
      'slides': slides,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static String _safeExtension(String ext) {
    final normalized = ext.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    return normalized.isEmpty ? 'jpg' : normalized;
  }

  static String _contentTypeFor(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  static const String _tokenAlphabet =
      'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';

  /// Unratbares Bearer-Token für die öffentliche Player-URL (24 Zeichen aus
  /// einem 55er-Alphabet ≈ 139 Bit; ohne leicht verwechselbare Zeichen).
  String _generateToken() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => _tokenAlphabet[random.nextInt(_tokenAlphabet.length)],
    ).join();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSubscriptions();
    super.dispose();
  }
}
