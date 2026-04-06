# Firebase Setup

## 1. Dienste aktivieren

- Firebase Authentication
  - Google
  - Email/Password
- Cloud Firestore
- Optional: Firebase Hosting fuer Web

## 2. App-Konfiguration

Die App kann auf zwei Arten konfiguriert werden:

1. Mit `flutterfire configure` und einer projektspezifischen `firebase_options.dart`
2. Mit `--dart-define` Werten gegen die vorhandene `lib/firebase_options.dart`

Wichtige Defines:

- `FIREBASE_WEB_API_KEY`
- `FIREBASE_WEB_APP_ID`
- `FIREBASE_WEB_MESSAGING_SENDER_ID`
- `FIREBASE_WEB_PROJECT_ID`
- `FIREBASE_WEB_AUTH_DOMAIN`
- `FIREBASE_WEB_STORAGE_BUCKET`
- `FIREBASE_ANDROID_API_KEY`
- `FIREBASE_ANDROID_APP_ID`
- `FIREBASE_ANDROID_MESSAGING_SENDER_ID`
- `FIREBASE_ANDROID_PROJECT_ID`
- `FIREBASE_ANDROID_STORAGE_BUCKET`
- `FIREBASE_IOS_API_KEY`
- `FIREBASE_IOS_APP_ID`
- `FIREBASE_IOS_MESSAGING_SENDER_ID`
- `FIREBASE_IOS_PROJECT_ID`
- `FIREBASE_IOS_STORAGE_BUCKET`
- `FIREBASE_IOS_BUNDLE_ID`
- `APP_DEFAULT_ORG_ID`
- `APP_DEFAULT_ORG_NAME`
- `APP_BOOTSTRAP_ADMIN_EMAILS`

## 3. Bootstrapping des ersten Admins

Die laufenden Security Rules gehen von einem bereits legitimen Admin oder einer vorhandenen Einladung aus.

Fuer den ersten Admin gibt es zwei produktionsnahe Wege:

1. Ein erstes `users/{uid}` Dokument manuell in Firestore oder per Admin-Skript anlegen.
2. Zeitlich begrenzt mit einer gelockerten Regel bootstrappen und danach auf `firestore.rules` wechseln.

Die App selbst unterstuetzt zusaetzlich eine lokale Bootstrap-Liste ueber `APP_BOOTSTRAP_ADMIN_EMAILS`. Das ist fuer Entwicklung und Erstinbetriebnahme hilfreich, ersetzt aber nicht das saubere serverseitige Admin-Seeding vor produktiven Rules.

Der einfachste manuelle Weg ohne Admin-Skript ist eine Einladung direkt in Firestore:

- Collection: `userInvites`
- Dokument-ID: die E-Mail in lowercase, z. B. `jowansulaiman@gmail.com`
- Felder:

```json
{
  "orgId": "main-org",
  "email": "jowansulaiman@gmail.com",
  "emailLower": "jowansulaiman@gmail.com",
  "role": "admin",
  "isActive": true,
  "createdByUid": "bootstrap",
  "settings": {
    "name": "Jowan",
    "hourlyRate": 0,
    "dailyHours": 8,
    "currency": "EUR"
  }
}
```

Danach kann sich dieser Benutzer per Google anmelden. Das `users/{uid}` Profil wird beim ersten Login automatisch erzeugt.

## 4. Einladungskonzept

- Admin legt eine Einladung in `userInvites/{emailLower}` an.
- Benutzer meldet sich mit Google oder aktiviert ein E-Mail/Passwort-Konto mit derselben E-Mail.
- Beim ersten Login wird daraus automatisch ein `users/{uid}` Profil erzeugt.

## 5. Firestore-Struktur

- `users/{uid}`
  - Rolle, Status, Org-ID, persoenliche Soll-/Lohndaten
- `userInvites/{emailLower}`
  - Einladung fuer neue Benutzer
- `organizations/{orgId}`
  - Organisations-Metadaten
- `organizations/{orgId}/workEntries/{entryId}`
  - Zeiteintraege
- `organizations/{orgId}/workTemplates/{templateId}`
  - persoenliche Vorlagen
- `organizations/{orgId}/shifts/{shiftId}`
  - Schichten
- `organizations/{orgId}/absenceRequests/{requestId}`
  - Urlaub, Krankheit, Nichtverfuegbarkeit

## 6. Migration vorhandener lokaler Daten

Die App migriert alte `SharedPreferences` Daten nach dem ersten erfolgreichen Login:

- alte Zeiteintraege
- alte Vorlagen
- alte Benutzereinstellungen

Nach erfolgreicher Migration werden die lokalen Altdaten geloescht und der Benutzer lokal als migriert markiert.

## 7. Deployment der Regeln

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

## 8. Empfohlene Tests

- Google-Login auf Web, Android und iOS
- Einladung aktivieren per E-Mail/Passwort
- Mitarbeiter darf nur eigene Zeiteintraege und Schichten lesen
- Admin darf Teamdaten und alle Org-Daten lesen/schreiben
- Konfliktpruefung bei ueberschneidenden Schichten
- PDF-Export im Browser und auf Mobilgeraeten
