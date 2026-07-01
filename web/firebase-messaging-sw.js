/* Firebase Cloud Messaging — Web-Service-Worker (M6, Stretch).
 *
 * Rendert Hintergrund-/Closed-Tab-Pushes auf dem Web (Foreground läuft über
 * Dart `onMessage`). Wird von `flutter build web` unverändert nach build/web/
 * kopiert; das firebase_messaging-Web-Plugin registriert ihn automatisch unter
 * /firebase-messaging-sw.js an der Origin-Root (koexistiert mit dem Flutter-SW).
 *
 * WICHTIG (bewusste Ausnahme zum "keine committete Config"-Prinzip aus CLAUDE.md):
 * Ein Service Worker kann die `--dart-define FIREBASE_WEB_*`-Creds NICHT lesen.
 * Die Web-Firebase-Config muss hier vor dem Go-Live eingetragen ODER per
 * Build-Step aus den dart-defines generiert werden (siehe Plan-Abschnitt 5,
 * offene Entscheidung "Web-Config im SW"). Solange Platzhalter stehen, ist
 * Web-Background-Push inaktiv (mobiler Push ist davon unberührt).
 */
importScripts(
    "https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js");
importScripts(
    "https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "REPLACE_ME",
  authDomain: "REPLACE_ME",
  projectId: "REPLACE_ME",
  messagingSenderId: "REPLACE_ME",
  appId: "REPLACE_ME",
});

const messaging = firebase.messaging();

// Hintergrund-Nachricht: System-Notification mit dem Marken-Status-Icon zeigen.
messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  const data = payload.data || {};
  self.registration.showNotification(
      notification.title || "WorkTime", {
        body: notification.body || "",
        icon: "/icons/Icon-192.png",
        tag: data.thread || undefined,
        data: {deepLink: data.deepLink || "/"},
      });
});

// Tap auf die Hintergrund-Notification → Tab fokussieren / Deep-Link öffnen.
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.deepLink) ||
      "/";
  event.waitUntil(clients.matchAll({type: "window", includeUncontrolled: true})
      .then((wins) => {
        for (const win of wins) {
          if ("focus" in win) {
            win.focus();
            if ("navigate" in win) win.navigate(target);
            return;
          }
        }
        if (clients.openWindow) return clients.openWindow(target);
      }));
});
