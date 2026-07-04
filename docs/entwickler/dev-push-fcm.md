# Push/FCM-Technik

Mobile Push-Benachrichtigungen laufen über **Firebase Cloud Messaging (FCM)**, **server-getriggert**. Der Kern liegt in `functions/push_notifications.js`.

## Server: fanOutPush + Trigger

- `fanOutPush(...)` ist die zentrale Sende-Funktion: sie liest Empfänger-Tokens und ihre `notificationPrefs` und stellt pro Kanal zu.
- Mehrere `onDocument`-Trigger lösen sie aus – u. a. bei neuen/geänderten Schichten, Abwesenheiten und Produkten (`onProductWritten` deckt MHD/Bestand ab).
- Ereignisse werden zusätzlich in die `notifications`-Collection geschrieben (In-App-Postfach), auch wenn Push aus ist.

## Client

- `lib/services/push_messaging_service.dart`: Init, Foreground-Anzeige (via `flutter_local_notifications`), Android-Notification-Channels, getippte-Push-Routen (Cold-Start via Gate-Redirect Pending-Route).
- `lib/services/fcm_token_repository.dart`: Geräte-Token-Registrierung.
- Kanäle/Präferenzen: `lib/models/notification_prefs.dart` (Teil des `AppUserProfile`).

## Gating

> [!WARNING]
> Push ist doppelt gegated: `APP_PUSH_ENABLED` (Sichtbarkeits-/Aktivierungs-Schalter, **kein Secret**) **und** `DefaultFirebaseOptions.isConfigured` – im Demo-/Offline-Modus ist FCM-Init ein No-op.

## Web-Push (Stretch)

Web-FCM braucht `APP_WEB_PUSH_VAPID_KEY` (public VAPID key) für `getToken(vapidKey:)`. Der Service-Worker `web/firebase-messaging-sw.js` kann keine dart-defines lesen → die Web-Firebase-Config wird dort per Build-Step/Hardcode gesetzt (bewusste Ausnahme).

> [!NOTE]
> Push braucht **Blaze** (sendende Functions, APNs-Key). Der Plan liegt in `plan/push-benachrichtigungen-plan.md`; M1–M7 sind code-fertig, offen ist nur der Blaze-Deploy.

## Weiter

- [Cloud Functions](article:dev-cloud-functions)
- [Änderungsprotokoll (Audit)](article:dev-audit-trail)
