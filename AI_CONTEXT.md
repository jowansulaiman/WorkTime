# Projektueberblick

Dieses Repository enthaelt eine Flutter-App fuer Arbeitszeiterfassung, Schichtplanung und Teamverwaltung mit gemeinsamem Code fuer Android, iOS und Web sowie ein kleines Firebase-Functions-Backend.

Der sichtbare Stand des Projekts unterstuetzt:

- Firebase Authentication mit Google sowie E-Mail/Passwort-Aktivierung ueber Einladungen
- rollenbasierte Nutzung fuer `admin`, `teamlead`, `employee`
- Firestore als zentrale Datenquelle fuer Benutzer, Teamdaten, Schichten, Abwesenheiten und Zeiteintraege
- Cloud Functions fuer validierte Schreiboperationen bei Schichten und Zeiteintraegen
- lokalen Entwicklungsmodus ohne Firebase ueber `APP_DISABLE_AUTH=true`
- lokale Persistenz und Legacy-Migration ueber `shared_preferences`
- PDF-/CSV-Export fuer Monatsberichte und Schichtplaene

# Technologien

- Flutter / Dart 3
- `provider` fuer State Management
- `firebase_core`
- `firebase_auth`
- `cloud_firestore`
- `cloud_functions`
- `google_sign_in`
- `shared_preferences`
- `pdf`
- `printing`
- `table_calendar`
- `fl_chart`
- `share_plus`
- Firebase Cloud Functions (Node.js 20)
- Firestore Security Rules

# Projektstruktur

```text
.
├── lib/
│   ├── main.dart                    # App-Bootstrap, Theme, Provider-Verdrahtung
│   ├── core/
│   │   └── app_config.dart          # Laufzeitkonfiguration via dart-define
│   ├── models/                      # Fachmodelle fuer Auth, Zeit, Schichten, Team
│   ├── providers/                   # App-State und Session-abhaengige Logik
│   ├── screens/                     # UI-Screens und Dialog-/Sheet-Workflows
│   └── services/                    # Firestore, Auth, Compliance, Export, lokale Persistenz
├── functions/
│   ├── index.js                     # Callable Functions fuer validierte Backendschreibvorgaenge
│   └── package.json
├── test/                            # Provider-, Modell-, PDF- und Widget-Tests
├── docs/
│   └── firebase_setup.md            # Setup- und Betriebsdokumentation fuer Firebase
├── firebase.json                    # Firebase-Projektkonfiguration
├── firestore.rules                  # Firestore-Zugriffsregeln
├── firestore.indexes.json           # Firestore-Indizes
├── pubspec.yaml                     # Flutter-Abhaengigkeiten
└── README.md
```

Nicht relevant fuer Schnellkontext:

- generierte Build-Artefakte unter `build/`
- IDE-/Tooling-Verzeichnisse wie `.idea/`, `.dart_tool/`
- generierte Flutter-/Plattformdateien ohne projektspezifische Logik

# Einstiegspunkte

## Flutter-App

- `lib/main.dart`
  - `main()` initialisiert Flutter-Binding, globale Fehlerbehandlung und startet `AppBootstrap`
  - `AppBootstrap` laedt Datumsformatierung und initialisiert Firebase nur, wenn `DefaultFirebaseOptions.isConfigured == true`
  - `WorkTimeApp` verdrahtet die Provider mit `MultiProvider`
  - `_AuthGate` entscheidet zwischen Firebase-Setup, Ladezustand, Auth-Screen, gesperrtem Konto und `HomeScreen`

## Laufzeitkonfiguration

- `lib/core/app_config.dart`
  - `APP_DISABLE_AUTH`
  - `APP_DEFAULT_ORG_ID`
  - `APP_DEFAULT_ORG_NAME`
  - `APP_BOOTSTRAP_ADMIN_EMAILS`

- `lib/firebase_options.dart`
  - liest Firebase-Konfiguration ausschliesslich aus `--dart-define`
  - erkennt, ob Firebase fuer die aktuelle Plattform vollstaendig konfiguriert ist

## Backend

- `functions/index.js`
  - enthaelt die serverseitigen Callable Functions
  - zentrale Backend-Einstiegspunkte:
    - `upsertShiftBatch`
    - `publishShiftBatch`
    - `upsertWorkEntry`
    - `previewCompliance`

## Betriebs-/Security-Konfiguration

- `firebase.json`
- `firestore.rules`
- `docs/firebase_setup.md`

# Zentrale Module und Verantwortlichkeiten

## Modelle

- `lib/models/app_user.dart`
  - Benutzerprofil, Rollenmodell, Rechteableitungen (`isAdmin`, `canManageShifts`)

- `lib/models/user_settings.dart`
  - persoenliche Arbeitszeit-, Lohn-, Urlaub- und Pausenparameter

- `lib/models/work_entry.dart`
  - Zeiteintrag mit Firestore- und lokaler Serialisierung
  - lokale Speicherung nutzt snake_case
  - Firestore nutzt camelCase

- `lib/models/shift.dart`
  - Schichtdaten, Status, Wiederholung, Tauschstatus, Qualifikationsanforderungen

Weitere Modelle decken Abwesenheiten, Regelwerke, Vertraege, Standorte, Teams, Einladungen und Fahrtzeiten ab.

## Provider

- `AuthProvider`
  - verwaltet Login-Status, Profilaufloesung und Fehlermeldungen
  - erzeugt im lokalen Modus ein festes lokales Admin-Profil
  - stoesst Profilanlage und Legacy-Migration an

- `ThemeProvider`
  - verwaltet ThemeMode und Locale
  - speichert UI-Einstellungen lokal in `shared_preferences`

- `TeamProvider`
  - verwaltet Teamdaten der Organisation
  - laedt Mitglieder, Einladungen, Teams, Standorte, Qualifikationen, Vertraege, Standortzuordnungen, Regelwerke und Fahrtzeitregeln
  - bietet Admin-Schreiboperationen fuer Teamverwaltung
  - laedt im lokalen Modus diese Daten aus lokaler Persistenz

- `WorkProvider`
  - verwaltet Zeiteintraege, Vorlagen, Monatsauswahl, Berichtsnutzer und Stempeluhr
  - validiert Zeiteintraege mit `ComplianceService`
  - nutzt Team-Referenzdaten aus `TeamProvider`
  - laedt im lokalen Modus Eintraege/Vorlagen aus lokaler Persistenz

- `ScheduleProvider`
  - verwaltet Schichten, Abwesenheiten, Filter und sichtbaren Zeitraum
  - validiert Schichten und Besetzbarkeit mit `ComplianceService`
  - unterstuetzt Wiederholungen, Wochenkopie, Veroeffentlichung und Tausch-Workflows
  - laedt im lokalen Modus Schichten/Abwesenheiten aus lokaler Persistenz

## Services

- `AuthService`
  - duenner Wrapper um Firebase Auth
  - Web-spezifische Persistence- und Redirect-Behandlung

- `FirestoreService`
  - zentrale Firestore- und Callable-API des Flutter-Clients
  - enthaelt Watcher, Query-Methoden, Speichermethoden, Einladungs-/Profilbootstrap und Legacy-Migration
  - nutzt bei authentifizierten Schicht- und Zeiteintrag-Schreibvorgaengen Cloud Functions

- `DatabaseService`
  - lokale Persistenz ueber `shared_preferences`
  - speichert nicht nur UI-Settings, sondern auch lokale Arbeits-, Schicht- und Teamdaten fuer den auth-losen Modus

- `ComplianceService`
  - fachliche Regelpruefung fuer Schichten und Zeiteintraege
  - prueft u. a. Ueberschneidungen, Pausenregeln, Tagesgrenzen, Minijob-Grenzen, Jugendarbeitsschutz, Standortzuordnung, Qualifikationen und Ruhezeiten

- `ExportService`
  - Orchestrierung fuer PDF-/CSV-Exports

- `PdfService`
  - eigentliche PDF-Generierung fuer Monatsberichte und Schichtplaene

- `download_service.dart`
  - plattformspezifischer Download/Share-Zugriff
  - Web: HTML-Download
  - Nicht-Web: `share_plus`

## Screens

- `AuthScreen`
  - Login mit Google sowie Einladung/Aktivierung per E-Mail/Passwort

- `HomeScreen`
  - Haupt-Shell
  - verwendet `NavigationRail` oder `NavigationBar`
  - laedt Tabs lazy ueber `_LazyDestinationStack`
  - Hauptziele: `Heute`, `Plan`, `Zeit`, `Anfragen`, `Profil`

- `ShiftPlannerScreen`
  - Schichtplanung, Filter, Veroeffentlichung, Export, Wiederholungen, Serien, Konfliktpruefung

- `NotificationScreen`
  - Inbox fuer Abwesenheitsantraege, Tausch-Anfragen, Updates und Schnellaktionen

- `MonthReportScreen`
  - Monatsbericht und PDF-Export

- `SettingsScreen`
  - Profil-, Arbeitszeit-, Lohn-, Vorlagen-, Theme- und Spracheinstellungen

- `TeamManagementScreen`
  - Admin-Bereich fuer Einladungen, Standorte, Qualifikationen, Teams, Regelwerk und Fahrtzeitregeln

- `StatisticsScreen`
  - Diagramme und CSV-Export fuer Zeiteintraege

# Architektur

## Schichtenmodell

Das Projekt folgt im sichtbaren Code einer klaren Aufteilung:

1. UI in `screens/`
2. zustandsbehaftete Anwendungslogik in `providers/`
3. Infrastruktur- und Persistenzlogik in `services/`
4. Fachmodelle in `models/`
5. serverseitige Validierung/Schreiblogik in `functions/`

## Provider-Abhaengigkeiten

Die App nutzt in `lib/main.dart` eine abhaengige Provider-Kette:

- `AuthProvider` ist die Session-Quelle
- `ThemeProvider` ist unabhaengig von Auth
- `TeamProvider` haengt von `AuthProvider` ab
- `WorkProvider` haengt von `AuthProvider` und `TeamProvider` ab
- `ScheduleProvider` haengt von `AuthProvider` und `TeamProvider` ab

`TeamProvider` liefert Referenzdaten, die in `WorkProvider` und `ScheduleProvider` fuer Validierung und UI-Kontext benoetigt werden.

## Persistenzstrategie

- Normalbetrieb:
  - Auth ueber Firebase Auth
  - Daten ueber Firestore
  - sensible Schreiboperationen fuer Schichten und Zeiteintraege ueber Callable Functions

- Lokaler Modus:
  - kein Firebase-Login notwendig
  - Providers lesen/schreiben primaer ueber `DatabaseService`
  - lokales Admin-Profil wird synthetisch erzeugt

## Sicherheitsmodell

`firestore.rules` erlaubt direkte Firestore-Schreibzugriffe nicht fuer alles:

- `workEntries` und `shifts`: direkte Client-Create/Update/Delete sind verboten
- `absenceRequests`, `workTemplates`, Team-Metadaten: teilweise direkte Client-Schreibrechte, abhaengig von Rolle und Organisation
- Rollen- und Organisationsbezug werden in den Rules geprueft

Folge fuer Aenderungen:

- Aenderungen an Zeiteintrag- oder Schichtschreiblogik betreffen oft sowohl Flutter-Code als auch `functions/index.js` und `firestore.rules`

# Datenfluss

## App-Start

1. `main()` startet `AppBootstrap`
2. `AppBootstrap` initialisiert Datumsformatierung und optional Firebase
3. `WorkTimeApp` erstellt Provider
4. `AuthProvider.init()` entscheidet zwischen lokalem Modus, fehlender Firebase-Konfiguration oder echtem Auth-Flow
5. `_AuthGate` zeigt Setup-, Lade-, Login- oder Hauptansicht

## Auth- und Profilfluss

1. Benutzer meldet sich an
2. `AuthProvider` beobachtet `authStateChanges()`
3. `FirestoreService.ensureProfileForSignedInUser()`:
   - laedt vorhandenes Profil oder
   - erzeugt es aus Einladung bzw. Bootstrap-Adminliste
4. `AuthProvider` startet anschliessend `watchUserProfile()`
5. bei erfolgreichem Profil-Laden startet Legacy-Migration lokaler Alt-Daten

## Teamdatenfluss

1. `AuthProvider.profile` aendert sich
2. `TeamProvider.updateSession(profile)` startet/cancelt Firestore-Subscriptions
3. Teamdaten werden als Streams geladen
4. `WorkProvider` und `ScheduleProvider` erhalten ueber `updateReferenceData()` die relevanten Referenzdaten

## Zeiteintragsfluss

1. UI erstellt/aendert Eintrag ueber `WorkProvider`
2. `WorkProvider.validateEntry()` ruft `ComplianceService` auf
3. bei aktivem Firebase:
   - `FirestoreService.saveWorkEntry()` ruft Callable `upsertWorkEntry`
   - Backend validiert erneut und schreibt nach Firestore
4. danach aktualisiert der Firestore-Stream `watchWorkEntries()` den Provider-State

## Schichtfluss

1. UI erstellt/aendert/veroeffentlicht Schichten ueber `ScheduleProvider`
2. `ScheduleProvider.validateShifts()` nutzt `ComplianceService`
3. `FirestoreService.saveShiftBatch()` bzw. `publishShiftBatch()` ruft Callables auf
4. Backend validiert erneut und schreibt nach Firestore
5. `watchShifts()` aktualisiert den sichtbaren Zustand

## Lokaler Modus

1. `APP_DISABLE_AUTH=true`
2. `AuthProvider` setzt lokales Admin-Profil
3. Team-, Arbeitszeit- und Schichtprovider lesen/schreiben ueber `DatabaseService`
4. UI-Workflows bleiben weitgehend identisch, aber ohne Firebase-Abhaengigkeit

## Exportfluss

1. Screen ruft `ExportService` auf
2. `ExportService` erzeugt PDF/CSV
3. `PdfService` baut PDF-Inhalt
4. `download_service` teilt oder laedt die Datei plattformspezifisch herunter

# Regeln und Konventionen

- Konfiguration erfolgt ueber `--dart-define`, nicht ueber fest eingebettete produktive Firebase-Dateien
- lokale Datenmodelle nutzen haeufig snake_case, Firestore-Modelle camelCase
- Organisationsgrenze (`orgId`) ist zentraler Bestandteil fast aller Datenzugriffe
- Rollenlogik:
  - `admin`: volle Teamverwaltung
  - `teamlead`: darf Schichten verwalten
  - `employee`: nur eigene Bereiche
- `AuthProvider`, `TeamProvider`, `WorkProvider`, `ScheduleProvider` sind die primaeren Einstiegspunkte fuer Feature-Aenderungen
- Regelpruefungen sind nicht nur UI-Logik:
  - Client-seitig in `ComplianceService`
  - serverseitig erneut in `functions/index.js`
- `ThemeProvider` speichert Theme und Locale lokal
- `HomeScreen` laedt Zielseiten lazy; schwere Bereiche nicht unnoetig frueh initialisieren
- Tests verwenden sichtbar `FakeFirebaseFirestore` und gemockte `SharedPreferences`
- Analyzer-Konfiguration basiert auf `package:flutter_lints/flutter.yaml`

# Arbeitsanweisung fuer KI

- Erst `AI_CONTEXT.md` lesen
- Nicht das gesamte Projekt unnoetig analysieren
- Nur relevante Dateien der aktuellen Aufgabe pruefen
- Bestehende Architektur respektieren
- Aenderungen lokal und minimal halten
- Keine unnoetigen Umbenennungen oder Refactorings
- Bei Unsicherheit erst die zustaendigen Dateien identifizieren

Zusaetzliche projektspezifische Hinweise:

- Aenderungen an Schicht- oder Zeiteintragslogik haeufig in drei Stellen pruefen:
  - passender Provider
  - `ComplianceService`
  - `FirestoreService` und ggf. `functions/index.js`
- Bei Problemen im lokalen Modus zusaetzlich `DatabaseService` pruefen
- Bei Rollen-/Zugriffsproblemen immer auch `firestore.rules` pruefen
- Fuer neue UI-Aenderungen zuerst den zustaendigen Screen und den zugehoerigen Provider identifizieren
- Fuer Export-Themen zuerst `ExportService`, dann `PdfService` und `download_service` pruefen

# Offene Punkte

- Unklar: Ein dedizierter CI-/CD- oder Release-Prozess ist im sichtbaren Repository nicht dokumentiert.
- Unklar: `firebase.local.json` ist vorhanden; ob und wie diese Datei ausserhalb lokaler Entwicklung automatisiert verwendet wird, ist im gelesenen Code nicht ersichtlich.
- Unklar: Fuer das Functions-Backend sind im sichtbaren Repository keine separaten Backend-Tests vorhanden.
- Unklar: Es gibt keine sichtbare End-to-End-Teststrecke fuer komplette Auth-/Firestore-/Functions-Workflows.
- Unklar: Plattformspezifische Besonderheiten fuer Android/iOS ausserhalb des Flutter-Codes sind im Kernkontext nicht dokumentiert und sollten bei Bedarf direkt in den Plattformordnern geprueft werden.
