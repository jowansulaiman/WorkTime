import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../services/push_messaging_service.dart';

/// Brücke zwischen Session (Auth + Storage-Modus) und dem
/// [PushMessagingService]: registriert beim Login den FCM-Geräte-Token und
/// meldet ihn beim Logout / Nutzerwechsel ab.
///
/// **M1: nur Token-Lebenszyklus.** Die persistierte In-App-Inbox
/// (`notifications`-Collection + gelesen/ungelesen-Status, Parität zum
/// „Anfragen"-Center) folgt in M2/M3 hier. Eingehängt als
/// `ChangeNotifierProxyProvider2<AuthProvider, StorageModeProvider>` am Ende
/// der `main.dart`-Kette (hängt nur von Auth + Storage ab).
class NotificationProvider extends ChangeNotifier {
  String? _sessionUid;

  /// Vom ProxyProvider bei jedem Rebuild aufgerufen (fire-and-forget). Push nur
  /// im Cloud-/Hybrid-Modus mit aktivem Profil; im local-only- und Demo-Modus
  /// (kein Firebase) bleibt alles inaktiv. Der [PushMessagingService] ist
  /// zusätzlich plattform-/flag-gegated → hier genügt der Session-Wechsel.
  Future<void> updateSession(
    AppUserProfile? user, {
    bool localStorageOnly = false,
    bool hybridStorageEnabled = false,
  }) async {
    final uid = (user != null && user.isActive && !localStorageOnly)
        ? user.uid
        : null;
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
}
