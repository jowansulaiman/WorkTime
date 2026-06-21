# CLAUDE.md

Leitfaden für Claude Code in diesem Repo. Ziel: ohne erneutes Durchsuchen produktiv arbeiten. Kurz halten, beim Ändern aktuell halten.

## Was ist das

**WorkTime** – Flutter-App für Arbeitszeiterfassung, Schichtplanung, Teamverwaltung (Android/iOS/Web, eine Codebasis). Backend: Firebase (Auth, Firestore, Cloud Functions). Mandantenfähig: jede Org getrennt.

- Package: `worktime_app` (pubspec.yaml), Dart `>=3.0.0 <4.0.0`, plain `flutter` (kein fvm).
- State Management: `provider` ^6.1.1. Charts: `fl_chart`. PDF: `pdf` + `printing`.
- **Drei Namen, kein Bug:** `MaterialApp.title` = `timework`, Projekt/Ordner = `WorkTime`, Default-Org-Name = `Worktime`.
- **Alle UI- und Fehlertexte sind Deutsch.** Locale ist hart auf `de_DE` (ThemeProvider löscht gespeicherte `locale`). Keine i18n/ARB/gen-l10n. Neue Strings = deutsche Literale. Jedes `DateFormat` MUSS `'de_DE'` explizit übergeben.

## App starten

```bash
flutter pub get

# Schnellster Weg (offline, kein Firebase) — IMMER hiermit testen:
flutter run --dart-define=APP_DISABLE_AUTH=true
#   Demo-Logins, Passwort überall "demo1234":
#   admin@demo.local (admin) · peter@example.com / maria@example.com (employee) · lea.teamlead@example.com (teamlead)

# Mit echtem Firebase: alle FIREBASE_* + APP_* dart-defines nötig (es gibt KEINE committete Config!):
flutter run --dart-define-from-file=<deine-config>.json   # Datei musst du selbst anlegen
```

Ein nacktes `flutter run` ohne dart-defines verbindet sich mit **nichts** Nutzbarem. `flutter run --dart-define=APP_DISABLE_AUTH=true` ist der Default für Entwicklung.

## Quality Gates (= Definition of Done)

Es gibt **keine CI**, kein Makefile. Vor jedem Commit selbst ausführen:

```bash
flutter analyze    # lint: nur package:flutter_lints/flutter.yaml, rules leer — NICHT ohne Auftrag erweitern
flutter test       # 16 Files, ~107 Cases, komplett offline (fakes)
flutter test test/work_provider_test.dart --plain-name 'teil des testnamens'   # einzeln
flutter test --coverage   # erzeugt coverage/lcov.info; pragmatisches Ziel: kritische Provider/Services ≥ 70 %
#   Report ansehen (lcov installiert): genhtml coverage/lcov.info -o coverage/html && open coverage/html/index.html
#   Kein Merge-Gate (self-hosted), nur Sichtbarkeit — macht u. a. sichtbar, wie weit das Warenwirtschaft-Modul gedeckt ist.
```

## dart-define-Inventar (gesamte Laufzeitkonfig — kein .env, keine flutterfire-Datei)

| Key | Default | Wirkung |
|---|---|---|
| `APP_DISABLE_AUTH` | `false` | Offline-Demo-Modus ohne Firebase. **In Release-Build verboten** → `AppConfig.validateEnvironment()` wirft `StateError`. |
| `APP_DEFAULT_ORG_ID` | `main-org` | `defaultOrganizationId` |
| `APP_DEFAULT_ORG_NAME` | `Worktime` | Name des lazy angelegten Org-Docs |
| `APP_BOOTSTRAP_ADMIN_EMAILS` | `''` | CSV; per Login selbst-provisionierende Admins (nur Dev). Lies via `AppConfig.bootstrapAdminEmailList`. |
| `FIREBASE_FUNCTIONS_REGION` | `europe-west3` | Functions-Region. **Muss** `const REGION` in `functions/index.js` entsprechen. |
| `FIREBASE_{ANDROID,IOS,WEB}_*` | – | Creds in `lib/firebase_options.dart` (`API_KEY`, `APP_ID`, `MESSAGING_SENDER_ID`, `PROJECT_ID`, …). Platzhalter `REPLACE_ME`/`YOUR_VALUE_HERE`/leer gelten als „unset" → Firebase still deaktiviert. |

## Verzeichnis-Map

```
lib/core/        Config (app_config.dart), Parser-Helfer, Demo-Daten, Compliance-Fallback
lib/models/      Datenklassen, dual serialisiert (kein codegen)
lib/services/    Datenzugriff/Seiteneffekte: Firestore, lokale Persistenz, Compliance, Auth, PDF/CSV, Download
lib/providers/   State (ChangeNotifier)
lib/screens/     UI (home_screen.dart ist die Shell, riesig)
lib/widgets/     wiederverwendbare Widgets, lib/theme/ Theme
functions/       Cloud Functions (plain JS, Node 20, kein Build-Step)
test/            flach, fakes statt Firebase
firestore.rules · firestore.indexes.json · docs/firebase_setup.md
```

## Architektur / Datenfluss

**Bootstrap** (`lib/main.dart`): `main()` → `AppConfig.validateEnvironment()` → globale Error-Handler → `Firebase.initializeApp` (mit Options wenn konfiguriert, sonst nativ nur auf Android; `duplicate-app` wird geschluckt) → **Firestore-Offline-Persistence setzen (vor dem ersten Read!)** → `authProvider.init()`. `_AuthGate` wählt Root-Screen: `!firebaseConfigured`→`FirebaseSetupScreen`, `!initialized`/`isResolvingProfile`→Loader, `!isAuthenticated`→`AuthScreen`, `profile != null && !isActive`→`AccessBlockedScreen`, sonst `HomeScreen`.

**Provider-Kette** (Reihenfolge in `lib/main.dart` ist tragend, neue abhängige Provider DANACH einfügen):

```
AuthProvider(.value, vor runApp init'd) → ThemeProvider → StorageModeProvider
  → FeatureFlagProvider (Proxy2<Auth,Storage>)  // erster Proxy, von _AuthGate gelesen
  → TeamProvider (Proxy2<Auth,Storage>)         // einziger Produzent von Stammdaten
  → ScheduleProvider (Proxy3<Auth,Team,Storage>)
  → InventoryProvider (Proxy2<Auth,Storage>)    // Warenwirtschaft + Kundenbestellungen
  → ContactProvider (Proxy2<Auth,Storage>)      // Kontakte
  → AuditProvider (Proxy2<Auth,Storage>)        // Änderungsprotokoll (best-effort)
  → PersonalProvider (Proxy3<Auth,Team,Storage>)// HR (workTasks/payrollRecords/-Profiles)
  → WorkProvider (Proxy4<Auth,Team,Storage,Schedule>)
```
> Inventory/Contact/Audit/Personal lösen ihr Cloud-Repository **lazy** auf (nie im
> Konstruktor) — sonst Crash im `APP_DISABLE_AUTH`/Web-Modus. Neue abhängige
> Provider weiterhin DANACH einfügen.
- Jeder Proxy ruft `provider.updateSession(auth.profile, localStorageOnly: storage.isLocalOnly, hybridStorageEnabled: storage.isHybrid)`. `updateSession` ist `async`, der Proxy-Callback aber sync → wird via `_dispatchProviderUpdate` **fire-and-forget** ausgeführt; Fehler werden nur per `debugPrint` geloggt. **Nie annehmen, dass updateSession beim Rebuild fertig ist.**
- `TeamProvider` schiebt seine Listen synchron via `updateReferenceData(...)` in Schedule/Work (die lesen Stammdaten nie selbst). Diese Setter rufen kein `notifyListeners` (sonst Rebuild-Loops).
- `WorkProvider` bekommt zusätzlich die lebende `ScheduleProvider`-Instanz via `updateScheduleProvider` (markiert Schicht als completed bei Entry-Save). Einziger direkter Provider→Provider-Call.
- In async-/Stream-/Timer-Callbacks immer `_safeNotify()` (prüft `_disposed`), nie bare `notifyListeners`.

**Drei Speichermodi** (`StorageModeProvider`, enum `DataStorageLocation{hybrid(Default), cloud, local}`):
- **local**: nur SharedPreferences. **cloud**: nur Firestore-Streams. **hybrid (Default)**: Cloud-Reads, lokal gecacht.
- Im **hybrid**-Modus werden *userContent* (Schichten, Zeiteinträge, Templates, Abwesenheiten) zusätzlich in SharedPreferences gespiegelt (spart bezahlte Firestore-Writes → Spark-Free-Tier); *Stammdaten* (sites/teams/quals/contracts/ruleSets/travelTimeRules) werden **nicht** gespiegelt und verlassen sich auf Firestores eigenen Offline-Cache.
- Mutator-Muster: `if (usesLocalStorage) { lokal mutieren + persist + notify; return; }` sonst Firestore versuchen; **im catch: bei hybrid lokal fallbacken (NICHT rethrow), bei cloud-only rethrow.**

> **Lokale Persistenz ist SharedPreferences (`shared_preferences`), KEIN SQLite.** JSON-Collections unter Key-Namespace `local_v2/...`. Es gibt keine DB, kein Schema, keine Migrationen im SQL-Sinn. `DatabaseService` ist komplett statisch.

## Die Zwei-Serialisierungs-Regel (wichtigster Footgun – betrifft models/services/functions/tests)

Jedes Model hat **zwei** nicht austauschbare Formate:

| Methoden | Keys | Datum/Zahlen | Verwendung |
|---|---|---|---|
| `toFirestoreMap()` / `fromFirestore(id, map)` | **camelCase** | `Timestamp` / `FieldValue.serverTimestamp()` | direkte Firestore-Writes **und** Seeding von `FakeFirebaseFirestore` in Tests |
| `toMap()` / `fromMap(map)` | **snake_case** | ISO-8601-Strings | SharedPreferences **und** Cloud-Function-Callable-Payloads |

- `fromFirestore` bekommt die Doc-ID als **separates erstes Argument** (`fromFirestore(doc.id, doc.data())`); Firestore-Maps enthalten die `id` nie. `fromMap` liest `map['id']`.
- Parser nie hart casten. Zahlen/Bools via `import '../core/firestore_num_parser.dart' as parse;` → `parse.toInt/toDouble/toBool/toMap` (tolerant für num|String|bool|null). Daten via `FirestoreDateParser.readDate` (camelCase/Firestore) bzw. `readLocalDate` (snake_case/lokal).
- **Ausnahme `WorkEntry`**: eigene `_parseFirestoreDate`/`_parseStoredDate`, die bei fehlendem/kaputtem Datum `FormatException` **werfen** (kein Fallback). `date` wird auf lokale Mittagszeit (12:00) normalisiert; lokal als `'YYYY-MM-DD'`-String, in Firestore als `Timestamp`.
- `copyWith` kann ein Feld **nicht** durch `null` leeren → explizites `clearX: true`-Flag (Muster `clearX ? null : (x ?? this.x)`).
- **Eine Callable bekommt `toMap()` (snake_case). `toFirestoreMap()` an eine Callable zu schicken verliert still Felder** (Server `parseShift`/`parseWorkEntry` versteht nur snake_case).

## Firestore-Datenmodell

- **Top-Level:** `users/{uid}` (trägt `orgId`-Feld!) und `userInvites/{emailLower}` (Doc-ID = getrimmte lowercase-E-Mail, `/`→`_`).
- **Org-skopiert** unter `organizations/{orgId}/`: `workEntries`, `workTemplates`, `shifts`, `shiftTemplates`, `absenceRequests`, `teams`, `sites`, `qualifications`, `employmentContracts`, `employeeSiteAssignments`, `ruleSets`, `travelTimeRules`.
- `ComplianceViolation` ist **transient** (keine Collection, nur in-memory). Org-Isolation in `firestore.rules` (`sameOrg`) **und** in Functions (`assertSameOrg`) — müssen synchron bleiben.
- Pfade nie hardcoden — `FirestoreService` hat die Collection-Getter.
- Enums serialisieren via `.value`-Getter zu snake_case-Strings ≠ Dart-Name: `RecurrencePattern.biWeekly`→`bi_weekly`, `EmploymentType.fullTime`→`full_time`/`miniJob`→`mini_job`, `ShiftStatus` = `planned/confirmed/completed/cancelled`. `fromValue` hat immer einen Default-Branch (wirft nie) → falscher String fällt still auf Default.

## Cloud Functions & Compliance

`functions/index.js` (v2 `onCall`, Region `europe-west3`, Node 20): `upsertShiftBatch`, `publishShiftBatch`, `upsertWorkEntry`, `upsertWorkEntryBatch`, `previewCompliance`.
- Nur **Schichten + Zeiteinträge** laufen über Callables (gated durch `!AppConfig.disableAuthentication`). Templates/Teams/Sites/Abwesenheiten/Verträge schreiben **direkt** in Firestore.
- Callables prüfen Caller-Rolle/Permissions + Same-Org und re-validieren Compliance serverseitig. Bei blockierender Verletzung → `failed-precondition`. **Client wirft das als `StateError(deutscheMessage)` und verwirft die strukturierten `{issues}`/`{validations}`.** Batch-Limit = **50**.
- **`previewCompliance` wird vom Dart-Client NICHT aufgerufen** — Preview macht clientseitig `ComplianceService`.
- **Sicherheitslücke per Design:** `firestore.rules` erlauben direkte Client-Writes auf shifts/workEntries (self+permission oder admin) und rufen die Functions **nicht** auf → direkte Writes umgehen die Compliance-Validierung. Callables = validierter Pfad.
- Neuer `where`+`orderBy`-Query → passenden Composite-Index in `firestore.indexes.json` (14 vorhanden) ergänzen + deployen, sonst Laufzeitfehler.

**`lib/services/compliance_service.dart` ist ein bewusster fast-exakter Spiegel** von `validateSingleShift`/`validateSingleWorkEntry` in `functions/index.js` (gleiche Violation-Codes, gleiche Schwellen: minRest 660min, Pausen 30@360 + 45@540, maxPlanned 600min/Tag, Minijob 60300 Cent, Nacht 23:00–06:00). Regel in einem ändern → im anderen mitziehen.

## „Wenn du X änderst, ändere auch Y" (kritische Kopplungen)

1. **Feld zu Model hinzufügen** → 6 Stellen: `toFirestoreMap`, `fromFirestore`, `toMap`, `fromMap`, `copyWith` (+`clearX` wenn nullable), und falls es durch Callables geht: snake_case parse/serialize in `functions/index.js`.
2. **Compliance-Regel/Schwelle/Code ändern** → in `compliance_service.dart` **und** `functions/index.js` (+ `ComplianceRuleSet.defaultRetail()` ↔ `defaultRuleSet('DE Einzelhandel Standard')`).
3. **Enum-Wert hinzufügen/umbenennen** → `.value`-Getter + `fromValue`-Default + deutsches `label` + ggf. passender String in `functions/index.js`/`firestore.rules` (z.B. `normalizeRole` mappt `teamleiter`→`teamlead` in beiden).
4. **Neuer abhängiger Provider** → nach Auth/Team/Schedule/Storage in `main.dart`-Kette einfügen.
5. **Neue lokal-persistierte Collection** → Key in `DatabaseService` registrieren, org- vs. user-skopiert via `_orgScopedCollectionKeys` entscheiden (nur `work_templates` + Settings sind user-skopiert), über `_load/_saveCollection` laufen lassen, `toMap`/`fromMap` muss round-trippen.
6. **Neuer Firestore-Write-Pfad** → 3 Enforcement-Punkte abgleichen: Callable (falls shift/entry), `firestore.rules` (erlauben direkte Writes!), und Payload-Format (Callable=snake_case, direkt=camelCase).
7. **Neuer Root-UI-State** → `_AuthGate` (kein Router!). **Neuer Tab** → `_ShellDestinationId`-Enum + `_buildDestinations` in `home_screen.dart`, per `AppUserProfile`-Permission-Getter gaten; **nie per Literal-Index** (Indizes variieren mit Permissions → `destinations.indexWhere`).
8. **`FIREBASE_FUNCTIONS_REGION` ändern** → muss `const REGION` in `functions/index.js` entsprechen, sonst schlagen Callables fehl (`not-found`/`unavailable`) und triggern still den direkten Fallback (umgeht Compliance).

## UI-Konventionen

- **Kein** go_router/named routes. Root nur in `_AuthGate`. In-Shell-Navigation ist index-basiert (`_navIndex` + `_navHistory` + `PopScope`), Tabs lazy via `_LazyDestinationStack`. Detail-Screens via `Navigator.push(MaterialPageRoute(...))`.
- Material 3, `AppTheme.light/dark`, `fontFamily: NotoSans`. ColorScheme ist nach `fromSeed` fast komplett überschrieben → nur benannte Rollen nutzen (`surfaceContainerLow` = Card-BG, `onSurfaceVariant` = gedämpfter Text, `secondaryContainer` = ausgewählt).
- **Status-Farben (success/warning/info) nie hardcoden** → `Theme.of(context).appColors` (ThemeExtension `AppThemeColors`).
- Reuse-Widgets in `home_screen.dart` (`_SectionCard`, `_HeaderSection`, `_EmptyState`, `_InfoChip` …) sind **file-private** → nicht importierbar, ggf. nach `lib/widgets/` heben statt kopieren.
- Modals dominant via `showModalBottomSheet(showDragHandle: true, isScrollControlled: true, useSafeArea: true)`. Abwesenheiten immer über `showAbsenceRequestSheet(...)` (in `notification_screen.dart`).
- Logo via `const AppLogo(...)` (remappt Markenfarben exakt per ARGB nur im Dark Mode). Rail-vs-BottomNav-Breakpoint ist hartes `>= 1120` in `home_screen` (nicht in `MobileBreakpoints`).
- Permission-Getter in `lib/models/app_user.dart` (`isAdmin`, `canManageShifts`, `canViewSchedule`, `canViewTimeTracking`, `canEditTimeEntries`, `canViewReports`) gaten **sowohl UI als auch Provider-Mutatoren**.

## Erster (echter) Admin / „warum kann ich mich nicht einloggen"

`ensureProfileForSignedInUser` wirft deutschen `StateError`, wenn der Nutzer weder `users/{uid}` noch eine aktive `userInvites/{emailLower}` hat noch in `APP_BOOTSTRAP_ADMIN_EMAILS` steht. Für echten Admin: `userInvites/{lowercase-email}`-Doc manuell anlegen (`orgId`, `email`, `emailLower`, `role:'admin'`, `isActive:true`) — `users/{uid}` wird beim ersten Login automatisch erzeugt. Details: `docs/firebase_setup.md`.

## Tests

- **Nie echtes Firebase.** `FirestoreService(firestore: FakeFirebaseFirestore())` (`fake_cloud_firestore`). Konstruktor nimmt optional `firestore`, `functions`, `cloudFunctionInvoker`, `uuid`.
- Callables simulieren: `cloudFunctionInvoker: (name, payload) async => ...`. `FirebaseFunctionsException(code:'not-found'|'unavailable', …)` werfen, um direkte-Write-/Hybrid-Fallbacks zu testen.
- SharedPreferences immer in `setUp`: `SharedPreferences.setMockInitialValues({}); DatabaseService.resetCachedPrefs();` (statischer Cache!).
- Binding/Datum: `TestWidgetsFlutterBinding.ensureInitialized();` + `await initializeDateFormatting('de_DE')`.
- Provider-Tests: `await provider.updateSession(user)` dann `provider.updateReferenceData(sites:, contracts:, siteAssignments:, ruleSets:, travelTimeRules:)` (Schedule auch `members:`). `ruleSets` meist `[ComplianceRuleSet.defaultRetail('org-1')]`. Nach Moduswechsel `await Future<void>.delayed(Duration.zero)` (ggf. 2×).
- Seam zum Abfangen von Writes = Subklasse (`_TestWorkProvider extends WorkProvider`), kein Mockito (nicht vorhanden — nicht einführen).
- Compliance asserten auf `.code`, nicht auf Message: `expect(violations.map((v)=>v.code), contains('break_required'))`.
- `FakeFirebaseFirestore` gibt Zahlen als `double` zurück (`breakMinutes == 30.0`) — keine int-Gleichheit asserten.
- „Current week"-Tests via `dayInCurrentWeek(offset)` o.ä. (Wall-Clock-abhängig), keine harten Daten. Reine Compliance-Tests dürfen feste Daten nutzen (alle Referenzdaten explizit).
- `assets/fonts/NotoSans-{Regular,Bold,Italic}.ttf` sind harte Abhängigkeit (PdfService wirft sonst). CSV (`ExportService.buildShiftPlanCsv`) hat UTF-8-BOM + `;`-Delimiter (deutsches Excel) — BOM nicht entfernen.

## Deployment

```bash
firebase deploy --only firestore:rules,firestore:indexes
firebase deploy --only functions          # functions/ = plain JS, kein Build-Step
firebase emulators:start
```
Hosting serviert `build/web` (SPA-Rewrite, no-cache Header).

**Mobile Release-Builds immer obfuskiert + mit getrennten Debug-Symbolen** (erschwert Reverse-Engineering der Client-Compliance-/Berechtigungslogik; Symbole für lesbares Crash-Mapping aufheben, NICHT committen — `build/symbols/` ist in `.gitignore`):

```bash
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols   # Android (Play Store)
flutter build ipa       --release --obfuscate --split-debug-info=build/symbols   # iOS (App Store)
```

Android-Release-Signierung läuft über `android/key.properties` (Upload-Keystore, nicht im Repo) mit Debug-Fallback, falls die Datei fehlt.

## Claude Skills (Experten-Leitlinien)

Im Verzeichnis `claude-skills/` liegen 19 Flutter-spezifische Experten-Rollen-Prompts (Web, iOS, Android, Desktop aus einer Codebasis). **Claude liest und wendet den jeweils passenden Skill aktiv an**, bevor es an einer Aufgabe in diesem Bereich arbeitet. Die Dateien sind die verbindliche Fachautorität für ihren Bereich — Entscheidungen sollen darin verankert sein.

| Aufgabe | Skill-Datei(en) |
|---|---|
| Firebase-Auth, Firestore-Rules, JWT, Token-Speicherung, OWASP | `sicherheit/01_api-sicherheit.md` · `sicherheit/02_software-sicherheit.md` |
| Flutter-Cross-Platform-Architektur, Provider, App-Store-Release | `entwicklung/15_mobile-entwicklung.md` · `architektur/04_software-architektur.md` |
| UI/UX, Material 3, Adaptive Layouts, Accessibility (WCAG) | `architektur/03_ux-ui-design.md` · `entwicklung/13_frontend-architektur.md` |
| Lokale Persistenz, Firestore-Schema, Indexes, Queries | `daten/16_datenbank.md` · `daten/17_datenbankarchitektur.md` |
| Cloud Functions, Backend-APIs, Daten-Pipelines | `daten/18_backend-daten.md` · `architektur/06_api-architektur.md` · `architektur/05_microservices.md` |
| Offline-Sync, Konflikt­lösung, Eventual Consistency | `daten/19_datensynchronisierung.md` |
| Tests (Unit/Widget/Integration/Golden) schreiben oder erweitern | `entwicklung/08_testing-qa.md` |
| Fehler­behandlung, Retry, Resilience, Graceful Degradation | `entwicklung/12_error-handling-resilience.md` |
| Performance, Jank, Flutter DevTools, Bundle-Größe | `entwicklung/10_performance.md` |
| Code-Qualität (Effective Dart), Refactoring, Tech Debt | `entwicklung/07_clean-code.md` · `entwicklung/11_refactoring-techdebt.md` |
| Logging, Crash-Reporting, Distributed Tracing, SLO | `entwicklung/14_observability.md` |
| CI/CD, GitHub Actions, Signing, Store-Deployment | `entwicklung/09_cicd-devops.md` |
