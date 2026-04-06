# Arbeitszeiterfassung App

Flutter-App fuer Arbeitszeiterfassung, Schichtplanung und Teamverwaltung mit einer gemeinsamen Codebasis fuer Android, iOS und Web.

Die aktuelle Software ist keine reine lokale Zeiterfassungs-App mehr. Der Stand im Repository umfasst inzwischen:

- Firebase Authentication mit Google sowie E-Mail/Passwort-Aktivierung ueber Einladungen
- rollenbasierte Nutzung fuer Admin, Teamleiter und Mitarbeiter
- Firestore als zentrale Datenquelle fuer Team-, Schicht- und Arbeitszeitdaten
- Cloud Functions fuer serverseitige Validierung und sichere Schreiboperationen
- hybriden Speicherbetrieb mit Firestore als Primaerspeicher und lokalem Cache
- optionalen lokalen Entwicklungsmodus ohne Firebase ueber `APP_DISABLE_AUTH=true`

## Funktionsumfang

### Authentifizierung und Rollen

- Google-Login fuer bestehende Benutzer
- E-Mail/Passwort-Aktivierung fuer eingeladene Konten
- Einladungsworkflow ueber `userInvites/{emailLower}`
- Rollen: `admin`, `teamlead`, `employee`
- Aktivieren und Deaktivieren von Benutzerkonten
- Bootstrap des ersten Admins ueber Einladungen oder `APP_BOOTSTRAP_ADMIN_EMAILS`

### Arbeitszeit

- manuelle Zeiteintraege mit Start, Ende, Pause, Notiz und Standort
- Stempeluhr mit gespeichertem Ein-/Ausstempeln
- Arbeitszeit-Vorlagen
- Monatsauswertung mit Stunden, Ueberstunden, Eintragsanzahl und Lohn
- Korrektur von Stempeluhr-Eintraegen
- persoenliche Einstellungen fuer Soll-Stunden, Stundenlohn, Urlaubstage, Auto-Pause und Waehrung

### Schichtplanung und Abwesenheiten

- Tages-, Wochen- und Monatsansicht
- Schichtfilter fuer Mitarbeiter, Team und Status
- wiederkehrende Schichten (`weekly`, `biWeekly`, `monthly`)
- Veroeffentlichen von sichtbaren Schichten
- Kopieren kompletter Wochen
- Schichttausch-Anfragen
- Abwesenheiten fuer Urlaub, Krankheit und Nichtverfuegbarkeit
- Inbox fuer offene Freigaben, Tausch-Anfragen und Rueckmeldungen

### Teamverwaltung

- Einladungen fuer neue Benutzer
- Standorte
- Qualifikationen
- Teams
- Arbeitsvertraege
- Standortzuordnungen pro Mitarbeiter
- Regelwerke fuer Compliance-Pruefungen
- Fahrtzeitregeln zwischen Standorten

### Compliance, Reporting und Export

- Validierung von Zeiteintraegen und Schichten gegen Regelwerke
- Konfliktpruefung bei Ueberschneidungen, Abwesenheiten und Fahrtzeiten
- Monatsbericht als PDF
- Schichtplan-Export als PDF und CSV
- Statistikansicht mit Diagrammen und CSV-Export
- Teilen und Download auf Mobile und Web

### Hybrider Modus, lokaler Modus und Migration

- Hybridmodus als Standard: cloudfaehige Daten werden aus Firestore geladen und lokal zwischengespeichert
- reiner Cloudmodus ohne lokalen Primaercache optional in den Einstellungen
- lokaler Entwicklungsmodus ohne Firebase
- Speicherung lokaler Daten ueber `shared_preferences`
- Migration vorhandener lokaler Altdaten nach dem ersten erfolgreichen Login

## Technologie-Stack

### App

- Flutter
- Provider
- Firebase Core, Auth, Firestore, Functions
- Shared Preferences
- `pdf` und `printing`
- `table_calendar`
- `fl_chart`
- `share_plus`

### Backend

- Firebase Cloud Functions
- Node.js 20

## Projektstruktur

```text
.
├── lib/
│   ├── core/                  # Laufzeit-Konfiguration ueber dart-define
│   ├── models/                # Datenmodelle fuer Auth, Zeit, Schichten, Team
│   ├── providers/             # State Management fuer Auth, Team, Zeit, Planung
│   ├── screens/               # UI fuer Dashboard, Planung, Inbox, Report, Settings
│   ├── services/              # Firestore, Export, PDF, lokale Persistenz
│   ├── firebase_options.dart  # Firebase-Konfiguration ueber dart-define
│   └── main.dart              # Bootstrap, Theme, App-Start
├── functions/                 # Cloud Functions fuer Shift- und Entry-Validierung
├── test/                      # Provider-, Model-, PDF- und Widget-Tests
├── docs/
│   └── firebase_setup.md      # detailliertes Firebase-Setup
├── firestore.rules
├── firestore.indexes.json
└── firebase.json
```

## Voraussetzungen

- Flutter SDK 3.x
- Dart SDK 3.x
- Android Studio und/oder Xcode fuer mobile Builds
- optional: Firebase CLI
- optional: Node.js 20 fuer Cloud Functions

## App starten

### 1. Abhaengigkeiten installieren

```bash
flutter pub get
```

### 2. Lokaler Modus ohne Firebase

Fuer UI-, Provider- und Workflow-Entwicklung kann die App komplett ohne Firebase gestartet werden:

```bash
flutter run --dart-define=APP_DISABLE_AUTH=true
```

Im lokalen Modus stehen vier Demo-Logins bereit:

- `admin@demo.local` / `demo1234`
- `peter@example.com` / `demo1234`
- `maria@example.com` / `demo1234`
- `lea.teamlead@example.com` / `demo1234`

Zusatzlich werden zwei Dummy-Standorte automatisch angelegt:

- `Hauptstandort Berlin`
- `Filiale Hamburg`

Optional koennen im lokalen Modus noch diese Defines gesetzt werden:

- `APP_DEFAULT_ORG_ID`
- `APP_DEFAULT_ORG_NAME`

### 3. Mit Firebase starten

Es gibt zwei Wege:

1. `flutterfire configure` verwenden und `lib/firebase_options.dart` projektspezifisch erzeugen.
2. Die vorhandene Datei mit `--dart-define` Werten versorgen.

Beispiel:

```bash
flutter run \
  --dart-define=FIREBASE_ANDROID_API_KEY=... \
  --dart-define=FIREBASE_ANDROID_APP_ID=... \
  --dart-define=FIREBASE_ANDROID_MESSAGING_SENDER_ID=... \
  --dart-define=FIREBASE_ANDROID_PROJECT_ID=... \
  --dart-define=APP_DEFAULT_ORG_ID=main-org
```

Die vollstaendige Liste aller benoetigten Defines steht in [docs/firebase_setup.md](docs/firebase_setup.md).

Wenn Firebase fuer die Plattform nicht konfiguriert ist, zeigt die App beim Start eine eigene Setup-Ansicht an.

## Firebase und Backend

### Firestore

Wichtige Collections:

- `users`
- `userInvites`
- `organizations/{orgId}/workEntries`
- `organizations/{orgId}/workTemplates`
- `organizations/{orgId}/shifts`
- `organizations/{orgId}/absenceRequests`
- `organizations/{orgId}/teams`
- `organizations/{orgId}/sites`
- `organizations/{orgId}/qualifications`
- `organizations/{orgId}/employmentContracts`
- `organizations/{orgId}/employeeSiteAssignments`
- `organizations/{orgId}/ruleSets`
- `organizations/{orgId}/travelTimeRules`

### Cloud Functions

Das Repository enthaelt serverseitige Callables fuer:

- `upsertShiftBatch`
- `publishShiftBatch`
- `upsertWorkEntry`
- `previewCompliance`

Die Functions sichern Schreiboperationen fuer Schichten und Zeiteintraege ab und fuehren dabei Compliance-Pruefungen aus.

## Tests

Vorhandene Tests decken u. a. diese Bereiche ab:

- `work_provider`
- `schedule_provider`
- `team_provider`
- `compliance_service`
- `pdf_service`
- Widget-Regression fuer die Inbox/Abwesenheiten

Starten:

```bash
flutter test
```

## Deployment

### Firestore-Regeln und Indizes

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

### Cloud Functions

```bash
cd functions
npm install
cd ..
firebase deploy --only functions
```

## Hinweise

- Im Repository sind keine produktiven Firebase-Zugangsdaten hinterlegt.
- Der lokale Modus ist fuer Entwicklung hilfreich, ersetzt aber kein sauberes Firebase-Setup.
- Details zum Invite-Bootstrap, zu Admin-Seeding und zur Firestore-Struktur stehen in [docs/firebase_setup.md](docs/firebase_setup.md).
