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
| `APP_LEGAL_*` | `''` | Impressum/Datenschutz-Stammdaten der öffentlichen Seiten: `_OPERATOR_NAME`, `_STREET`, `_POSTAL_CITY`, `_EMAIL`, `_PHONE`, `_REPRESENTATIVE`, `_VAT_ID`, `_REGISTER`, `_CONTENT_RESPONSIBLE` (Opt-in § 18 MStV, nur bei redaktionellen Inhalten), `_LAST_UPDATED`. Gebündelt in `LegalInfo`. Leer ⇒ Rechtsseiten zeigen sichtbaren „noch zu hinterlegen"-Hinweis (`LegalInfo.isComplete` = Name+Anschrift+E-Mail+Telefon). |
| `APP_PUSH_ENABLED` | `false` | Schaltet mobile Push-Benachrichtigungen (FCM) frei (Plan `plan/push-benachrichtigungen-plan.md`). **Kein Secret** — nur Sichtbarkeits-/Aktivierungs-Schalter; FCM-Init zusätzlich gegen `DefaultFirebaseOptions.isConfigured` gegated → No-op im Demo-/Offline-Modus. Default aus bis Blaze-Cutover (APNs-Key + sendende Functions deployt). |
| `APP_WEB_PUSH_VAPID_KEY` | `''` | Web-Push-Zertifikat (VAPID public key), nur für Web-FCM (`getToken(vapidKey:)`). Leer ⇒ kein Web-Token. **Kein Secret** (public key). Der Web-Service-Worker `web/firebase-messaging-sw.js` braucht zusätzlich die Web-Firebase-Config (kann dart-defines nicht lesen → Build-Step/Hardcode, bewusste Ausnahme). M6/Stretch. |
| `FIREBASE_FUNCTIONS_REGION` | `europe-west3` | Functions-Region. **Muss** `const REGION` in `functions/index.js` entsprechen. |
| `FIREBASE_{ANDROID,IOS,WEB}_*` | – | Creds in `lib/firebase_options.dart` (`API_KEY`, `APP_ID`, `MESSAGING_SENDER_ID`, `PROJECT_ID`, …). Platzhalter `REPLACE_ME`/`YOUR_VALUE_HERE`/leer gelten als „unset" → Firebase still deaktiviert. |

## Verzeichnis-Map

```
lib/core/        Config (app_config.dart), Parser-Helfer, Demo-Daten, Compliance-Fallback, pure Auto-Schichtverteilung (shift_slot_generator.dart Phase A, shift_auto_assigner.dart Phase B)
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

**Bootstrap** (`lib/main.dart`): `main()` → `AppConfig.validateEnvironment()` → `usePathUrlStrategy()` (saubere Web-URLs, kein `#`) → globale Error-Handler → `Firebase.initializeApp` (mit Options wenn konfiguriert, sonst nativ nur auf Android; `duplicate-app` wird geschluckt) → **Firestore-Offline-Persistence setzen (vor dem ersten Read!)** → `authProvider.init()`.

**Routing = go_router** (`lib/routing/app_router.dart`; `MaterialApp.router` in `WorkTimeApp`). Der Router wird EINMALIG im `Consumer2`-Builder von `WorkTimeApp` memoisiert (`_router ??= buildAppRouter(auth, featureFlags, theme)`); `refreshListenable: Listenable.merge([auth, featureFlags, theme])`. Statt eines `_AuthGate`-Widgets reproduziert **`_gateRedirect`** die Root-Wahl als Redirect → Gate-Routen: `!firebaseConfigured`→`/einrichtung`(FirebaseSetup), `!initialized`/`isResolvingProfile`→`/start`(Loader), `!isAuthenticated`→`/anmelden`(AuthScreen), `profile && !isActive`→`/gesperrt`(AccessBlocked), `requiresUpdate`→`/aktualisierung`(ForceUpdate), sonst Shell. V1/V2 der Gate-Screens via `RedesignFlags.isOnRead`. Der Redirect macht zusätzlich URL-Permission-Gating (Deep-Link ohne Recht → `/`). Analytics-Observer hängt am `GoRouter(observers:)`, NICHT an `MaterialApp` (dort ignoriert). Pfad-Konstanten: `shellTabPaths` (Tabs) + `AppRoutes` (Gate-/Section-Routen) in `lib/routing/shell_tab.dart`.

**Öffentliche Web-Routen bleiben VOR der Provider-Kette + go_router** (eigene isolierte `MaterialApp`, kein `authProvider.init()`, KEIN go_router — bewusste Sicherheits-/Kosten-Grenze): `/wunsch` (`PublicWishApp`), `/feedback` (`PublicFeedbackApp`) — beide brauchen Firebase (anonymer Schreibpfad). `/impressum` + `/datenschutz` (`PublicLegalApp`) sind **reine Statik** ohne Firebase. `_AppBootstrap` liest `Uri.base` einmalig und wählt öffentliche App vs. `WorkTimeApp` (nur Letztere bekommt go_router). Alle vier teilen das flache Signal-Teal-Design (`lib/screens/public/public_ui.dart`). Impressum/Datenschutz (§ 5 DDG / Art. 13 DSGVO) sind zusätzlich per Footer (`PublicLegalLinks`) aus Wunsch-/Feedback-Seite erreichbar; Inhalt aus `LegalInfo`/`APP_LEGAL_*`. Neue öffentliche Route → `isPublic*Route()` + Zweig in `_AppBootstrapState.build` + ins `_publicMode`-Getter (Pfad darf nicht mit einem go_router-Pfad kollidieren).

**Provider-Kette** (Reihenfolge in `lib/main.dart` ist tragend, neue abhängige Provider DANACH einfügen):

```
AuthProvider(.value, vor runApp init'd) → ThemeProvider → StorageModeProvider
  → FeatureFlagProvider (Proxy2<Auth,Storage>)  // erster Proxy, vom go_router-Redirect gelesen
  → AuditProvider (Proxy2<Auth,Storage>)        // Änderungsprotokoll (best-effort); FRÜH, da Senke aller Folgenden
  → TeamProvider (Proxy3<Auth,Storage,Audit>)   // einziger Produzent von Stammdaten
  → ScheduleProvider (Proxy4<Auth,Team,Storage,Audit>)
  → InventoryProvider (Proxy3<Auth,Storage,Audit>) // Warenwirtschaft + Kundenbestellungen
  → ContactProvider (Proxy3<Auth,Storage,Audit>)   // Kontakte
  → PersonalProvider (Proxy4<Auth,Team,Storage,Audit>) // HR (workTasks/payrollRecords/-Profiles)
  → WorkProvider (Proxy5<Auth,Team,Storage,Schedule,Audit>)
```
> Inventory/Contact/Audit/Personal lösen ihr Cloud-Repository **lazy** auf (nie im
> Konstruktor) — sonst Crash im `APP_DISABLE_AUTH`/Web-Modus. Neue abhängige
> Provider weiterhin DANACH einfügen.
- **Zentrales Änderungsprotokoll:** `AuditProvider` ist absichtlich FRÜH (vor allen Daten-Providern) registriert, damit jeder Daten-Provider via `provider.setAuditSink(audit.log)` die best-effort-Senke `AuditSink` (`lib/providers/audit_sink.dart`, fire-and-forget, wirft nie) bezieht. Jeder fachliche Mutator loggt `_audit?.call(action:, entityType:, entityId:, summary:)` NUR auf dem Erfolgs-Pfad (in JEDEM Storage-Zweig: local-return UND hybrid-catch-Fallback; NIE auf rethrow-/Permission-Deny-Pfaden, NIE doppelt bei Delegation). Akteur/Zeitstempel füllt `AuditProvider.log` selbst. Lesen ist admin-only (Rules). Deutsche Summaries. Rauschen (Vorlagen, persönliche Einstellungen, Warenkorb, Favoriten) wird bewusst NICHT geloggt. **Neuer Mutator mit fachlicher Relevanz → dort `_audit?.call(...)` ergänzen (nicht im Screen).** Cloud-erzeugte Stammdaten (saveSite/Team/Qualification/RuleSet/TravelTimeRule) bekommen beim Anlegen `entityId == null`, weil `FirestoreService` die Doc-ID intern via `collection.doc()` vergibt — Aktion/Summary/Akteur sind korrekt, nur die ID-Verknüpfung fehlt (bekannte, harmlose Einschränkung; Model-`entityId` ist nullable).
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
- **Org-skopiert** unter `organizations/{orgId}/`: `workEntries`, `workTemplates`, `shifts`, `shiftTemplates`, `absenceRequests`, `teams`, `sites`, `qualifications`, `employmentContracts`, `employeeSiteAssignments`, `ruleSets`, `travelTimeRules`. **Config-Singletons** unter `config/`: `appFlags` (FeatureFlagProvider) und `orgSettings` (org-weite operative Einstellungen der Auto-Schichtverteilung, fixe Doc-ID, ebenfalls von `FeatureFlagProvider` geladen/geschrieben; lokaler Fallback `local_v2/org_settings`). Beide deckt der generische `config/{configId}`-Rules-Block (sameOrg-read/admin-write).
- `ComplianceViolation` ist **transient** (keine Collection, nur in-memory). Org-Isolation in `firestore.rules` (`sameOrg`) **und** in Functions (`assertSameOrg`) — müssen synchron bleiben.
- Pfade nie hardcoden — `FirestoreService` hat die Collection-Getter.
- Enums serialisieren via `.value`-Getter zu snake_case-Strings ≠ Dart-Name: `RecurrencePattern.biWeekly`→`bi_weekly`, `EmploymentType.fullTime`→`full_time`/`miniJob`→`mini_job`, `ShiftStatus` = `planned/confirmed/completed/cancelled`. `fromValue` hat immer einen Default-Branch (wirft nie) → falscher String fällt still auf Default.

## Cloud Functions & Compliance

`functions/index.js` (v2 `onCall`, Region `europe-west3`, Node 20): `upsertShiftBatch`, `publishShiftBatch`, `upsertWorkEntry`, `upsertWorkEntryBatch`, `previewCompliance`.
- **OktoPOS-Kassenanbindung** (`plan/oktopos-kassenanbindung.md`): **Pull** `syncOktoposTransactions` (onCall) + `oktoposNightlySync` (onSchedule) — Verkäufe→Bestand; **Artikel-Push** `pushOktoposArticles` + `getOktoposLookups` (onCall) — Artikel/Preise→Kasse; **Kunden-Push** `pushOktoposCustomers` (onCall) — Contacts(Typ Kunde)→Kasse, idempotent via `findByExternalIdentifier` create-if-absent (CustomerApi hat kein Update). OrderApi (Bestell-Import) bewusst NICHT gebaut (keine Kiosk-Quelldaten). **Einzige Functions mit ausgehendem HTTP** (`fetch` gegen die Kasse, Header `X-API-KEY`); Key im **Secret Manager `OKTOPOS_API_KEYS`**, NIE im Client. Pull schreibt Bestandsbewegungen via Admin SDK (umgeht Rules) mit `source:'oktopos'` (Client darf das laut `stockMovements`-Rules NICHT). Push-Idempotenz über `externalReferenceNumber = Produkt-ID` (409→change-prices). Config (baseUrl/cashRegisterId/push-Tokens) in `config/oktoposSync`. Brauchen **Blaze** (Outbound + Secret + Scheduler). UI-Schalter `AppConfig.oktoposEnabled` (`APP_OKTOPOS_ENABLED`, Default aus).
- Nur **Schichten + Zeiteinträge** laufen über Callables (gated durch `!AppConfig.disableAuthentication`). Templates/Teams/Sites/Abwesenheiten/Verträge schreiben **direkt** in Firestore.
- Callables prüfen Caller-Rolle/Permissions + Same-Org und re-validieren Compliance serverseitig. Bei blockierender Verletzung → `failed-precondition`. **Client wirft das als `StateError(deutscheMessage)` und verwirft die strukturierten `{issues}`/`{validations}`.** Batch-Limit = **50**.
- **`previewCompliance` wird vom Dart-Client NICHT aufgerufen** — Preview macht clientseitig `ComplianceService`.
- **Sicherheitslücke per Design:** `firestore.rules` erlauben direkte Client-Writes auf shifts/workEntries (self+permission oder admin) und rufen die Functions **nicht** auf → direkte Writes umgehen die Compliance-Validierung. Callables = validierter Pfad.
- Neuer `where`+`orderBy`-Query → passenden Composite-Index in `firestore.indexes.json` (14 vorhanden) ergänzen + deployen, sonst Laufzeitfehler.

**`lib/services/compliance_service.dart` ist ein bewusster fast-exakter Spiegel** von `validateSingleShift`/`validateSingleWorkEntry` in `functions/index.js` (gleiche Violation-Codes, gleiche Schwellen: minRest 660min, Pausen 30@360 + 45@540, maxPlanned 600min/Tag, Minijob 60300 Cent, Nacht 23:00–06:00). Regel in einem ändern → im anderen mitziehen.

## Automatische Schichtverteilung (zwei pure Core-Klassen)

**Phase A** `ShiftSlotGenerator` (`lib/core/shift_slot_generator.dart`): generiert unbesetzte `Shift`-Slots aus `SiteDefinition.weekdayHours` (Öffnungszeiten, `TimeWindow`/`WeekdayHours` in `site_schedule.dart`) + `SiteDefinition.staffingDemands` (Bedarf > 1 = mehrere `Shift`-Objekte, **kein** headcount-Feld). **Phase B** `ShiftAutoAssigner` (`lib/core/shift_auto_assigner.dart`): verteilt sie unter harten Constraints (Standort, Quali, Abwesenheit, Doppelbelegung, **Compliance via `ComplianceService.validateShift`**, Cap/Minijob) + weichen Zielen (Fairness Richtung Sollzeit), Greedy + stabile Sortierung. **Beide sind pure** (kein State/IO/`now()`/Zufall; `seriesId`/`shiftIdFactory` injiziert) → deterministisch + offline testbar (`test/shift_slot_generator_test.dart`, `test/shift_auto_assigner_test.dart`).

- **Stundengrenzen** `EmploymentContract.monthlyMaxHours`/`weeklyMaxHours` (beide `double?`, nullable) sind **Planungsschranken im Verteiler, KEINE Compliance-Violation** (Kopplung #2 NICHT auslösen). Hart/weich umschaltbar via `OrgSettings.enforceHourCapHard` (**Default weich** = Überstunden-Modus); weich → `AssignmentWarning` + Score-Penalty + geplante Überstunden. **Minijob-Verdienstgrenze + Compliance bleiben in beiden Modi hart.**
- **Geplante Überstunden:** `Shift.overtimeMinutes` (int, Default 0) ist ein reines **Plan-Metadatum** („Anteil dieser Schicht über der Vertrags-Maximalstunde zum Planungszeitpunkt", berechnet via pure Helfer `lib/core/overtime_projection.dart`) — fließt **nie** ins Zeitkonto-Ist (Ist läuft über WorkEntries). Serialisiert an allen 6 Dart-Stellen (Kopplung #1) + 3 JS-Stellen in `functions/index.js` (`overtime_minutes` snake_case im Callable-Payload; parseShift/toFirestoreShift/fromFirestoreShift).
- **Personal→Plan-Kopplung:** `PersonalProvider` pusht Sollzeit-Profile + Austrittsdaten via `setPlanningDataSink` (verdrahtet in `main.dart`) an `ScheduleProvider.updatePersonalReferenceData({sollzeitProfiles, exitDateByUserId})` — Setter ohne `notifyListeners` (Muster wie `updateReferenceData`). Fairness-Ziel ist **Sollzeit-first** (`SollzeitProfile` → `contract.weeklyHours×4,33` → erst zuletzt maxHours); Caps sind nur noch Grenze.
- Provider-Anbindung in `ScheduleProvider`: `generatePlannedShifts` (Phase A, sync), `proposeAutoAssignment` (Phase B, **`Future`** — sammelt besetzte Schichten + genehmigte Abwesenheiten für den **vollen Monat + ISO-Wochen der offenen Schichten**, NICHT nur `_shifts`/sichtbare Woche, sonst zählen Caps/Minijob zu niedrig; Cloud/Hybrid via `getShiftsInRange`/`getApprovedAbsencesInRange` org-weit, Local aus dem vollständigen lokalen Cache), `applyAutoPlan` delegiert an `saveShifts` (erbt Batch ≤50 / Storage-Modi / Compliance-Re-Validierung). `updateReferenceData` bekommt zusätzlich `sites:` (aus `TeamProvider`).
- **UI-Footgun:** `ShiftPlannerScreen.build` gibt für `canManageShifts` FRÜH `_AdminShiftPlannerBoard` zurück; der Fallback-Pfad (mit der Wrap-Toolbar) rendert NUR für Nicht-Admins. Admin-Aktionen müssen daher als Callback ins Board durchgereicht werden (`onAutoPlan`/`onCopyWeek`, Toolbar-Button + `_buildPlannerActionMenuItems`/`_handleToolbarActionSelection`), NICHT in den Fallback-Pfad. „Automatisch planen" liegt im Board-Toolbar (`auto_fix_high`-Button + Aktionen-Menü „Automatisch planen") → Vorschau-Sheet → speichern.

## „Wenn du X änderst, ändere auch Y" (kritische Kopplungen)

1. **Feld zu Model hinzufügen** → 6 Stellen: `toFirestoreMap`, `fromFirestore`, `toMap`, `fromMap`, `copyWith` (+`clearX` wenn nullable), und falls es durch Callables geht: snake_case parse/serialize in `functions/index.js`.
2. **Compliance-Regel/Schwelle/Code ändern** → in `compliance_service.dart` **und** `functions/index.js` (+ `ComplianceRuleSet.defaultRetail()` ↔ `defaultRuleSet('DE Einzelhandel Standard')`).
3. **Enum-Wert hinzufügen/umbenennen** → `.value`-Getter + `fromValue`-Default + deutsches `label` + ggf. passender String in `functions/index.js`/`firestore.rules` (z.B. `normalizeRole` mappt `teamleiter`→`teamlead` in beiden).
4. **Neuer abhängiger Provider** → nach Auth/Team/Schedule/Storage in `main.dart`-Kette einfügen.
5. **Neue lokal-persistierte Collection** → Key in `DatabaseService` registrieren, org- vs. user-skopiert via `_orgScopedCollectionKeys` entscheiden (nur `work_templates` + Settings sind user-skopiert), über `_load/_saveCollection` laufen lassen, `toMap`/`fromMap` muss round-trippen.
6. **Neuer Firestore-Write-Pfad** → 3 Enforcement-Punkte abgleichen: Callable (falls shift/entry), `firestore.rules` (erlauben direkte Writes!), und Payload-Format (Callable=snake_case, direkt=camelCase).
7. **Neuer Root-UI-State** → Gate-Route + Zweig in `_gateRedirect` (`lib/routing/app_router.dart`). **Neuer Tab** → `ShellTab`-Enum (`lib/routing/shell_tab.dart`, Reihenfolge = Branch-Index!) + `StatefulShellBranch` in `buildAppRouter` + `_destinationMeta`/`_isTabVisible`/`buildHomeTab` in `home_screen.dart` + Permission im Redirect (`_isLocationAllowed`); **nie per Listenposition** mappen, immer `shellBranchIndex(tab)` / `destinations.indexWhere`. **Neuer Hauptbereich-Screen mit URL** → `AppRoutes`-Konstante + `_sectionRoute` + `_isLocationAllowed`, Aufruf via `context.push(AppRoutes.x)` (Detail-/Editor-Sheets bleiben imperativ `Navigator.push`).
8. **`FIREBASE_FUNCTIONS_REGION` ändern** → muss `const REGION` in `functions/index.js` entsprechen, sonst schlagen Callables fehl (`not-found`/`unavailable`) und triggern still den direkten Fallback (umgeht Compliance).
9. **Zeit-Freigabe-Workflow ändern** (plan `plan/zeit-schichtbindung-freigabe.md`) → SSoT ist `lib/core/work_entry_rules.dart` (`countsAsIst`, `applyOwnEntrySubmissionPolicy`, `isMaterialWorkEntryChange`, `isEligibleForBulkApproval`). **Zwei Kern-Invarianten:** (a) **strenge Zählung (E3)** — bindendes Ist zählt NUR `approved` (`countsAsIst`); alle Ist-Verbraucher (Zeitkonto, `totalHoursThisMonth`/Lohn, personal/month_report/home/Zeiterfassung, Statistik) müssen es respektieren, `submitted` wird als „vorläufig/in Freigabe" separat gezeigt. (b) **Freigabe nur durch Freigeber** — Nicht-Admins schreiben nur `draft/submitted` (nie selbst genehmigen); nur `canManageShifts` + `entry.userId != self` + Zielperson **kein Admin** darf `approved/rejected`. Diese Semantik ist an **drei** Enforcement-Punkten identisch zu halten: Client (`work_provider._addEntry`/`addEntries`/`approveWorkEntry`), Rules (`firestore.rules` workEntries, `weSelfSubmissionOk`/`weReviewerTargetOk`/`weReviewerStatusOk`), Callable (`functions/index.js` `resolveWorkEntryApproval`). **Material-Feld-Set** `{startTime,endTime,breakMinutes,siteId}` (= JS `correctionReasonRequired`) ist der einzige Re-Approval-Trigger — bei Änderung an allen drei Stellen nachziehen. E1 **hart**: Erfassen/Stempeln nur in einer Schicht (`validateEntry`-`shift_required` + `matchShiftForPunch` im `stempel_screen`). `ZeitkontoSnapshot.geplantMinutes` (E6) = reine Planzeit-Anzeige (Kopplung #1, snake_case `geplant_minutes`).

## UI-Konventionen

- **Routing via go_router** (`lib/routing/app_router.dart`), deutsche Pfade in der URL. Shell = `StatefulShellRoute.indexedStack` (7 statische Branches = lazy, state-erhaltender IndexedStack; ersetzt den früheren `_LazyDestinationStack`/`_navIndex`). Tab-Wechsel via `navigationShell.goBranch(branchIndex)`; Cross-Tab-Zurück via `_navHistory` + `PopScope` + `_ShellScope`-InheritedWidget. Hauptbereiche (`/warenwirtschaft`, `/team`, …) sind Top-Level-Routen, via `context.push(AppRoutes.x)` über die Shell gepusht (Back → Hub). Tab-Ziele via `context.go`/`goBranch`. Detail-/Editor-Screens (EntryForm, PurchaseOrder-Editor, Sheets) bleiben imperativ `Navigator.push(MaterialPageRoute(...))`. Tests gegen die echte Shell laufen über `test/support/router_harness.dart` (`pumpApp`).
- Material 3, `AppTheme.light/dark`, `fontFamily: NotoSans`. ColorScheme ist nach `fromSeed` fast komplett überschrieben → nur benannte Rollen nutzen (`surfaceContainerLow` = Card-BG, `onSurfaceVariant` = gedämpfter Text, `secondaryContainer` = ausgewählt).
- **Status-Farben (success/warning/info) nie hardcoden** → `Theme.of(context).appColors` (ThemeExtension `AppThemeColors`).
- Reuse-Widgets in `home_screen.dart` (`_SectionCard`, `_HeaderSection`, `_EmptyState`, `_InfoChip` …) sind **file-private** → nicht importierbar, ggf. nach `lib/widgets/` heben statt kopieren.
- Modals dominant via `showModalBottomSheet(showDragHandle: true, isScrollControlled: true, useSafeArea: true)`. Abwesenheiten immer über `showAbsenceRequestSheet(...)` (in `notification_screen.dart`).
- Logo via `const AppLogo(...)` (remappt Markenfarben exakt per ARGB nur im Dark Mode). Rail-vs-BottomNav-Breakpoint: Rail ab `mediumWindow=600` über `MobileBreakpoints.useNavigationRail(maxWidth)` (+ Höhen-Guard `maxHeight>=600`), volle Rail-Labels ab `expandedWindow=840` — definiert in `lib/widgets/responsive_layout.dart`, nicht hartkodiert in `home_screen`.
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

Im Verzeichnis `claude-skills/` liegen 23 Flutter-spezifische Experten-Rollen-Prompts (Web, iOS, Android, Desktop aus einer Codebasis). **Claude liest und wendet den jeweils passenden Skill aktiv an**, bevor es an einer Aufgabe in diesem Bereich arbeitet. Die Dateien sind die verbindliche Fachautorität für ihren Bereich — Entscheidungen sollen darin verankert sein.

Diese 23 Prompts sind zusätzlich als **auto-ladende Claude-Code-Skills** unter `.claude/skills/flutter-<domäne>/SKILL.md` verfügbar (Slash-Command `/flutter-…`, greifen via `description`-Keywords automatisch). Sie sind dünne Pointer auf die Quell-Prompts (Single Source of Truth bleibt `claude-skills/`). Generiert/validiert via `node claude-skills/build-skills.mjs` (+ `--check`) und `node claude-skills/validate-skills.mjs`. **Quell-Prompt geändert → `build-skills.mjs` erneut ausführen** (Kompetenz-Liste/Titel werden aus der Quelle extrahiert).

| Aufgabe | Skill-Datei(en) |
|---|---|
| Firebase-Auth, Firestore-Rules, JWT, Token-Speicherung, OWASP | `sicherheit/01_api-sicherheit.md` · `sicherheit/02_software-sicherheit.md` |
| Flutter-Cross-Platform-Architektur, Provider, App-Store-Release | `entwicklung/15_mobile-entwicklung.md` · `architektur/04_software-architektur.md` |
| UI/UX, Material 3, Adaptive Layouts, Accessibility (WCAG) | `architektur/03_ux-ui-design.md` · `entwicklung/13_frontend-architektur.md` |
| Lokale Persistenz, Firestore-Schema, Indexes, Queries | `daten/16_datenbank.md` · `daten/17_datenbankarchitektur.md` |
| Cloud Functions, Backend-APIs, Daten-Pipelines | `daten/18_backend-daten.md` · `architektur/06_api-architektur.md` · `architektur/05_microservices.md` |
| Offline-Sync, Konflikt­lösung, Eventual Consistency | `daten/19_datensynchronisierung.md` |
| App offline nutzbar machen (Web/iOS/Android): PWA/Service-Worker-Caching, Plattform-Offline-Persistenz (Firestore Web vs. mobil), Konnektivitäts-State, Offline-UX | `daten/21_offline-modus.md` |
| Tests (Unit/Widget/Integration/Golden) schreiben oder erweitern | `entwicklung/08_testing-qa.md` |
| Fehler­behandlung, Retry, Resilience, Graceful Degradation | `entwicklung/12_error-handling-resilience.md` |
| Performance, Jank, Flutter DevTools, Bundle-Größe | `entwicklung/10_performance.md` |
| Code-Qualität (Effective Dart), Refactoring, Tech Debt | `entwicklung/07_clean-code.md` · `entwicklung/11_refactoring-techdebt.md` |
| Crash-Reporting, Monitoring/RUM, Distributed Tracing, Analytics, SLO | `entwicklung/14_observability.md` |
| Logging-Mechanik (Erzeugung/Struktur/Redaction/Routing), debugPrint→AppLogger, Request-Korrelation, API-/Functions-Logs | `entwicklung/20_logging.md` |
| CI/CD, GitHub Actions, Signing, Store-Deployment | `entwicklung/09_cicd-devops.md` |
| **Code-/Diff-/PR-Review vor Commit** (Korrektheit, Zwei-Serialisierungs- & Kopplungs-Check, Compliance-Spiegel, Quality Gates) | `review/22_code-entwicklungs-review.md` |
| **Plan-Dokumente (plan/) abnehmen + Outputs/Antworten selbst-reviewen** (Vollständigkeit, Machbarkeit, Treue zur Anfrage, Definition of Done) | `review/23_plan-output-review.md` |
