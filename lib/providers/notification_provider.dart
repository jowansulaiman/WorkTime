import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../services/firestore_service.dart';
import '../services/push_messaging_service.dart';

/// Brücke zwischen Session (Auth + Storage-Modus) und Benachrichtigungen:
/// registriert beim Login den FCM-Geräte-Token (Push) **und** hält die
/// persistierte In-App-Inbox (`notifications`-Collection, PERSONAL-9/Q4)
/// gelesen/ungelesen.
///
/// Eingehängt als `ChangeNotifierProxyProvider2<AuthProvider,
/// StorageModeProvider>` am Ende der `main.dart`-Kette (hängt nur von Auth +
/// Storage ab). Im reinen local-Modus/Demo bleibt die Inbox leer (bewusste
/// Degradation — die Docs erzeugt nur die Cloud Function).
class NotificationProvider extends ChangeNotifier {
  NotificationProvider({FirestoreService? firestoreService})
      : _firestore = firestoreService;

  final FirestoreService? _firestore;

  String? _sessionUid;
  String? _orgId;
  bool _localOnly = false;
  bool _disposed = false;

  StreamSubscription<List<AppNotification>>? _inboxSub;
  List<AppNotification> _notifications = const [];

  /// Alle geladenen Mitteilungen (neueste zuerst); leer im local-Modus.
  List<AppNotification> get notifications => _notifications;

  /// Anzahl ungelesener Mitteilungen (für das Glocken-Badge).
  int get unreadCount => _notifications.where((n) => n.isUnread).length;

  /// Vom ProxyProvider bei jedem Rebuild aufgerufen (fire-and-forget). Push +
  /// Inbox nur im Cloud-/Hybrid-Modus mit aktivem Profil.
  Future<void> updateSession(
    AppUserProfile? user, {
    bool localStorageOnly = false,
    bool hybridStorageEnabled = false,
  }) async {
    final uid = (user != null && user.isActive && !localStorageOnly)
        ? user.uid
        : null;
    final orgId = user?.orgId;

    // Inbox-Abo neu aufsetzen, wenn sich Nutzer/Org/Modus ändert.
    if (uid != _sessionUid ||
        orgId != _orgId ||
        localStorageOnly != _localOnly) {
      _localOnly = localStorageOnly;
      _orgId = orgId;
      await _inboxSub?.cancel();
      _inboxSub = null;
      _notifications = const [];
      if (uid != null && orgId != null && _firestore != null) {
        _inboxSub = _firestore
            .watchNotifications(orgId: orgId, uid: uid)
            .listen((items) {
          _notifications = items;
          _safeNotify();
        }, onError: (_) {
          // Fehlender Index/Offline → leere Inbox, kein Crash.
          _notifications = const [];
          _safeNotify();
        });
      }
      _safeNotify();
    }

    // Push-Token-Lebenszyklus (unverändert).
    if (uid == _sessionUid) return;
    final previous = _sessionUid;
    _sessionUid = uid;
    if (previous != null && previous != uid) {
      await PushMessagingService.instance.unregisterCurrentDevice(previous);
    }
    if (uid != null) {
      await PushMessagingService.instance
          .registerForUser(uid: uid, orgId: user!.orgId);
    }
  }

  /// Markiert eine Mitteilung als gelesen (feldgranular `readAt`). No-op im
  /// local-Modus / ohne Service.
  Future<void> markAsRead(AppNotification notification) async {
    final orgId = _orgId;
    if (orgId == null || _firestore == null || !notification.isUnread) return;
    await _firestore.markNotificationRead(
      orgId: orgId,
      notificationId: notification.id,
    );
    // Der Stream liefert das Update; optimistisch nicht nötig.
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _inboxSub?.cancel();
    super.dispose();
  }
}
