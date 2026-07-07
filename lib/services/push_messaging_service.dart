import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import 'fcm_token_repository.dart';

/// FCM-Hintergrund-Handler (eigenes Isolate, kein Provider-/Widget-Zugriff).
/// MUSS eine Top-Level-Funktion sein. FCM zeigt die `notification`-Payload im
/// Hintergrund/terminiert selbst an — hier bewusst nichts Schweres.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {}

/// Ein fachlicher Android-Notification-Channel (= iOS-Kategorie/-Stufe + App-
/// Einstellungs-Schalter aus M5). Deckungsgleich mit der Push-Taxonomie.
class _PushChannel {
  const _PushChannel(this.id, this.name, this.description, this.importance);
  final String id;
  final String name;
  final String description;
  final Importance importance;
}

const List<_PushChannel> _pushChannels = <_PushChannel>[
  _PushChannel('genehmigungen', 'Genehmigungen',
      'Abwesenheits- und Tauschanträge', Importance.high),
  _PushChannel('schichtplan', 'Schichtplan',
      'Veröffentlichte und geänderte Schichten', Importance.high),
  _PushChannel('aufgaben', 'Aufgaben & Kühlschrank',
      'Operative To-dos und Feedback', Importance.defaultImportance),
  _PushChannel('kundenwuensche', 'Kundenwünsche',
      'Neue Kundenwünsche', Importance.defaultImportance),
  _PushChannel('bestand', 'Bestand & Nachbestellung',
      'Artikel unter Meldebestand', Importance.low),
];

/// Kapselt Firebase Cloud Messaging (FCM) + lokale Anzeige plattform-sicher —
/// nach dem Vorbild von `QuickActionsService`. Auf nicht unterstützten
/// Plattformen, bei ausgeschaltetem [AppConfig.pushEnabled] und im
/// APP_DISABLE_AUTH-Demo-Modus ist **alles ein No-op**. `FirebaseMessaging`/
/// `FlutterLocalNotifications` werden NIE im Konstruktor aufgelöst.
///
/// M1: Token-Lebenszyklus. M4: Berechtigung, Android-Channels, Foreground-
/// Anzeige (`onMessage` → flutter_local_notifications), Tap → Deep-Link in den
/// go_router (gate-konform über die Pending-Route, wie Schnellaktionen).
class PushMessagingService {
  PushMessagingService._();

  static final PushMessagingService instance = PushMessagingService._();

  static const String _installIdKey = 'fcm_install_id';

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  int _localId = 0;
  String? _activeUid;
  String? _activeOrgId;
  String? _pendingRoute;
  FcmTokenRepository? _repository;

  /// Vom App-Widget injiziert (wie `QuickActionsService.navigate`): führt die
  /// Navigation aus (`context.go`). Bei Cold-Start evtl. noch `null` → dann
  /// zählt allein die Pending-Route, die der Gate-Redirect zustellt.
  void Function(String route)? navigate;

  bool get _isSupported {
    if (!AppConfig.pushEnabled) return false;
    if (kIsWeb) return true; // M6: Web-Token-Registrierung (vapidKey)
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Vom Gate-Redirect konsumiert: liefert die offene Push-Deep-Link-Route
  /// (falls vorhanden) und löscht sie. Idempotent → kein Redirect-Loop.
  String? takePendingRoute() {
    final route = _pendingRoute;
    _pendingRoute = null;
    return route;
  }

  /// Einmalige Initialisierung im Bootstrap (nur wenn Firebase konfiguriert &
  /// Flag an). Registriert Hintergrund-Handler, legt die Channels an und hängt
  /// die Foreground-/Tap-Listener ein. Fehler werden geschluckt (fail-open).
  Future<void> initialize() async {
    if (_initialized || !_isSupported) return;
    _initialized = true;
    _repository ??= FcmTokenRepository();

    // Mobile: lokale Anzeige + Channels + Hintergrund-Handler. Web rendert
    // Hintergrund-Pushes über web/firebase-messaging-sw.js (M6).
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);

      const androidInit =
          AndroidInitializationSettings('@drawable/ic_stat_notification');
      const iosInit = DarwinInitializationSettings(
        // Berechtigung läuft zentral über FirebaseMessaging.requestPermission().
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _local.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: _onLocalTap,
      );

      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      for (final channel in _pushChannels) {
        await android?.createNotificationChannel(AndroidNotificationChannel(
          channel.id,
          channel.name,
          description: channel.description,
          importance: channel.importance,
        ));
      }

      // iOS zeigt im Vordergrund nichts automatisch → wir rendern selbst über
      // flutter_local_notifications (einheitlich mit Android).
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );
    }

    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _deliverRoute(_routeOf(message)),
    );
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _deliverRoute(_routeOf(initialMessage));
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((String token) {
      final uid = _activeUid;
      if (uid == null) return;
      _persist(uid: uid, token: token).catchError(
        (Object error, StackTrace stack) => AppLogger.error(
          'FCM-Token-Refresh fehlgeschlagen',
          error: error,
          stackTrace: stack,
        ),
      );
    });
  }

  /// Berechtigung anfragen (iOS-Prompt, Android 13+ POST_NOTIFICATIONS, Web).
  /// Bewusst NICHT beim Cold-Start, sondern kontextuell nach Login (aus
  /// [registerForUser]).
  Future<void> requestPermission() async {
    if (!_isSupported) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (error, stack) {
      AppLogger.error('FCM-Berechtigung fehlgeschlagen',
          error: error, stackTrace: stack);
    }
  }

  /// Nach erfolgreichem Login: Berechtigung anfragen + Token holen/persistieren.
  /// Mehrfachaufruf für dieselbe uid ist ein No-op (Session-Dedupe).
  Future<void> registerForUser({
    required String uid,
    required String orgId,
  }) async {
    if (!_isSupported || !_initialized) return;
    if (_activeUid == uid) return;
    _activeUid = uid;
    _activeOrgId = orgId;
    try {
      await requestPermission();
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb && AppConfig.webPushVapidKey.isNotEmpty
            ? AppConfig.webPushVapidKey
            : null,
      );
      if (token == null) return;
      await _persist(uid: uid, token: token);
    } catch (error, stack) {
      AppLogger.error('FCM-Token-Registrierung fehlgeschlagen',
          error: error, stackTrace: stack);
    }
  }

  /// Beim Abmelden / Nutzerwechsel: Geräte-Token-Doc entfernen.
  Future<void> unregisterCurrentDevice(String uid) async {
    final wasActive = _activeUid == uid;
    if (_activeUid == uid) {
      _activeUid = null;
      _activeOrgId = null;
    }
    if (!_isSupported || !_initialized || !wasActive) return;
    try {
      final installId = await _installationId();
      await (_repository ??= FcmTokenRepository())
          .deleteToken(uid: uid, installationId: installId);
      await FirebaseMessaging.instance.deleteToken();
    } catch (error, stack) {
      AppLogger.error('FCM-Token-Abmeldung fehlgeschlagen',
          error: error, stackTrace: stack);
    }
  }

  // --- Foreground-Anzeige + Tap-Routing -----------------------------------

  Future<void> _showForeground(RemoteMessage message) async {
    // Web: keine lokale Anzeige (flutter_local_notifications ist mobil-only);
    // Vordergrund-Pushes landen später im In-App-Center.
    if (kIsWeb) return;
    final notification = message.notification;
    final data = message.data;
    final title = notification?.title ?? data['title'] ?? 'Benachrichtigung';
    final body = notification?.body ?? data['body'] ?? '';
    final channel = _channelFor(data['type']?.toString() ?? '');
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: channel.importance,
        priority: channel.importance == Importance.high
            ? Priority.high
            : Priority.defaultPriority,
        icon: '@drawable/ic_stat_notification',
        groupKey: data['thread']?.toString(),
      ),
      iOS: DarwinNotificationDetails(threadIdentifier: data['thread']?.toString()),
    );
    _localId = (_localId + 1) % 100000;
    await _local.show(_localId, title, body, details,
        payload: jsonEncode(data));
  }

  void _onLocalTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      _deliverRoute(data['deepLink']?.toString());
    } catch (_) {
      // defekte Payload ignorieren
    }
  }

  String? _routeOf(RemoteMessage message) =>
      message.data['deepLink']?.toString();

  void _deliverRoute(String? route) {
    if (route == null || route.isEmpty) return;
    _pendingRoute = route;
    navigate?.call(route);
  }

  _PushChannel _channelFor(String type) {
    final id = _channelIdForType(type);
    return _pushChannels.firstWhere((c) => c.id == id,
        orElse: () => _pushChannels.first);
  }

  Future<void> _persist({required String uid, required String token}) async {
    final orgId = _activeOrgId;
    if (orgId == null) return;
    final installId = await _installationId();
    await (_repository ??= FcmTokenRepository()).saveToken(
      uid: uid,
      orgId: orgId,
      installationId: installId,
      token: token,
      platform: _platformLabel(),
    );
  }

  String _platformLabel() {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }

  Future<String> _installationId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_installIdKey);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_installIdKey, id);
    }
    return id;
  }
}

/// Ordnet einen Ereignis-`type` (Server-Payload) einem Channel zu. Top-Level +
/// testbar (test/push_channel_mapping_test.dart).
String channelIdForType(String type) => _channelIdForType(type);

String _channelIdForType(String type) {
  switch (type) {
    case 'absence_submitted':
    case 'absence_decision':
    case 'work_entry_decision':
    case 'shift_swap_request':
    case 'shift_swap_accepted':
    case 'shift_swap_declined':
    case 'shift_swap_confirmed':
    case 'shift_swap_rejected':
      return 'genehmigungen';
    case 'shift_published':
    case 'shift_open':
      return 'schichtplan';
    case 'customer_wish':
      return 'kundenwuensche';
    case 'low_stock':
    case 'expiry':
      return 'bestand';
    case 'customer_feedback':
    default:
      return 'aufgaben';
  }
}
