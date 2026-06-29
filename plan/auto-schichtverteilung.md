# Implementierungs-Auftrag (V2): Automatische Schichtverteilung — Bedarfsgesteuerte Generierung + Zuweisung + Stundengrenzen (WorkTime)

> **V2-Änderung gegenüber V1:** Der Verteiler füllt nicht mehr nur vorhandene unbesetzte Schichten, sondern **generiert** Schichten aus **Standort-Öffnungszeiten + Personalbedarf** (Phase A) und **besetzt** sie anschließend (Phase B). Neu hinzugekommen: Site-Öffnungszeiten-Modell, Personalbedarf-Modell, **Wochen- UND Monats-Stundengrenze** im Vertrag, **umschaltbare Cap-Härte** (org-weites Settings-Flag), explizite Blockade durch **Urlaub UND Krankheit**.

## 0. Kontext & Ziel

Du arbeitest im Flutter-Repo **WorkTime** (`worktime_app`, Provider-State, Firebase-Backend, Dual-Serialisierung). Lies vorab `CLAUDE.md` (Zwei-Serialisierungs-Regel, Provider-Kette, Storage-Modi, Audit, Compliance-Spiegel, go_router) sowie die Skills `claude-skills/entwicklung/15_mobile-entwicklung.md`, `claude-skills/architektur/04_software-architektur.md`, `claude-skills/entwicklung/08_testing-qa.md`, `claude-skills/daten/16_datenbank.md`.

Sechs zusammenhängende Bausteine:
1. **Site-Öffnungszeiten** (neues Modell-Feld auf `SiteDefinition`): pro Wochentag von–bis, mehrere Zeitfenster möglich.
2. **Personalbedarf** (neues Modell-Feld auf `SiteDefinition`): wie viele Mitarbeiter (+ optional welche Qualifikation) pro Zeitfenster gebraucht werden.
3. **Vertrags-Stundengrenzen**: `monthlyMaxHours` **und** `weeklyMaxHours` (beide `double?`, nullable).
4. **Umschaltbare Cap-Härte**: org-weites Flag `enforceHourCapHard` (bool, Default `true`). Hart = Grenze nie überschreiten (Rest-Slots bleiben offen mit Grund). Weich = darf überschritten werden, Vorschau warnt deutlich.
5. **Schicht-Generator + Verteiler** (zwei pure, testbare Core-Klassen): Phase A generiert Schicht-Slots aus Öffnungszeiten+Bedarf für einen Zeitraum (Woche/Monat); Phase B verteilt Mitarbeiter unter harten Constraints (Cap, Compliance, Quali, Standort, Abwesenheit) und weichen Zielen (Fairness Richtung Sollzeit).
6. **Planner-UI**: Aktion „Automatisch planen" → Vorschau (zu erstellende Schichten + Zuweisungen + Warnungen + nicht zuweisbar) → Bestätigen → Speichern (erzeugt UND besetzt).

**Realität im Repo (Code-Wahrheit, nichts erfinden):**
- Eine offene Schicht = `Shift` mit `userId.trim().isEmpty == true` (Getter `Shift.isUnassigned`, `lib/models/shift.dart:112`).
- Schicht-Pflichtfelder im Konstruktor: `orgId, userId, employeeName, title, startTime, endTime` (`shift.dart` Z.57–82). `workedHours = (endTime − startTime − breakMinutes)/60` (Z.109–110).
- Es existiert **kein** Öffnungszeiten-/Bedarfs-Konzept — wird in §1/§2 minimal neu definiert.
- Serien/Batch-Mechanik vorhanden: `buildShiftOccurrences` (stabiler `seriesId = shift.seriesId ?? _uuid.v4()`, `firestore_service.dart` Z.2327–2391), `saveShiftBatch` mit Chunking **≤ 50** (Z.1824–1855), `newSeriesId()` im Provider (`schedule_provider.dart` Z.2206), `_nextLocalId('shift') = shift-{uuid-v4}` (Z.2199).

---

## 1. Site-Öffnungszeiten (neues Modell)

Datei: `lib/models/site_definition.dart` (`class SiteDefinition`). Heutige 15 Felder: `id, orgId, name, code, street, postalCode, city, federalState, countryCode, latitude, longitude, description, createdByUid, createdAt, updatedAt` (Feld-Deklarationen Z.44–58).

### 1.1 Neue Wert-Typen (im selben File oder neuer `lib/models/site_schedule.dart` — bevorzugt eigenes File, sauber testbar)

```dart
/// Ein Zeitfenster innerhalb eines Tages, minutengenau ab Mitternacht (0..1440).
/// KEIN TimeOfDay im Modell (nicht serialisierbar) — int-Minuten.
class TimeWindow {
  final int startMinute; // 0..1440, inkl.
  final int endMinute;   // 1..1440, exkl. Ende; endMinute > startMinute
  const TimeWindow({required this.startMinute, required this.endMinute});
  int get durationMinutes => endMinute - startMinute;
  // toMap/fromMap (snake_case): {'start_minute':..,'end_minute':..}
  // toFirestoreMap/fromFirestore (camelCase): {'startMinute':..,'endMinute':..}
}

/// Öffnungszeiten eines Wochentags. weekday = DateTime.monday..sunday (1..7).
class WeekdayHours {
  final int weekday;              // 1..7 (DateTime.monday==1)
  final List<TimeWindow> windows; // mehrere Fenster erlaubt (z.B. Mittagspause)
  const WeekdayHours({required this.weekday, required this.windows});
}
```

- **Minuten statt `TimeOfDay`**, weil `TimeOfDay` nicht stabil serialisierbar ist und die Zwei-Serialisierungs-Regel rohe Werte verlangt. Parser tolerant via `import '../core/firestore_num_parser.dart' as parse;` (`parse.toInt`).
- Liste statt Map, deterministische Sortierung nach `weekday` beim Lesen.

### 1.2 Neues Feld auf `SiteDefinition`

`final List<WeekdayHours> weekdayHours;` — Default `const []` (leer = keine Öffnungszeiten hinterlegt → Generator erzeugt für diesen Standort nichts).

Folge der **„Feld hinzufügen"-Regel** an allen 7 Stellen in `site_definition.dart` (Zeilennummern aus Recherche):
1. **Konstruktor-Parameter** (Z.26–42): `this.weekdayHours = const []`.
2. **Feld-Deklaration** (Z.44–58): `final List<WeekdayHours> weekdayHours;`.
3. **`fromFirestore(id, map)`** (Z.105–126, camelCase): `weekdayHours: (map['weekdayHours'] as List?)?.map((e) => WeekdayHours.fromFirestore(parse.toMap(e))).toList() ?? const []`.
4. **`fromMap(map)`** (Z.128–149, snake_case): `weekdayHours: (map['weekday_hours'] as List?)?.map((e) => WeekdayHours.fromMap(parse.toMap(e))).toList() ?? const []`.
5. **`toFirestoreMap()`** (Z.151–169, camelCase): `'weekdayHours': weekdayHours.map((e) => e.toFirestoreMap()).toList()`.
6. **`toMap()`** (Z.171–189, snake_case): `'weekday_hours': weekdayHours.map((e) => e.toMap()).toList()`.
7. **`copyWith()`** (Z.191–234): Parameter `List<WeekdayHours>? weekdayHours` (Listen werden nie auf null geleert → kein `clearX` nötig, leere Liste genügt): `weekdayHours: weekdayHours ?? this.weekdayHours`.

`WeekdayHours`/`TimeWindow` brauchen je eigene `toMap/fromMap/toFirestoreMap/fromFirestore` (verschachtelt, beide Formate round-trip-fähig).

**Persistenz unverändert nutzbar:** `FirestoreService.saveSite()` (`firestore_service.dart` Z.875–883, `merge:true`) und lokal `DatabaseService` Key `local_v2/sites` (org-skopiert, `_orgScopedCollectionKeys`) — beide laufen über `toFirestoreMap`/`toMap`, also automatisch abgedeckt. **Keine** Callable für Sites (direkter Firestore-Write) → `functions/index.js` unberührt. Verträge/Sites laufen nicht über Callables (CLAUDE.md). Prüfe trotzdem kurz `firestore.indexes.json`: kein neuer `where`+`orderBy`-Query → **kein** neuer Index nötig.

---

## 2. Personalbedarf (neues Modell)

Minimal modelliert, ebenfalls auf `SiteDefinition` (gleiches File/`site_schedule.dart`).

```dart
/// Bedarf an Personal in einem Zeitfenster eines Wochentags.
class StaffingDemand {
  final int weekday;                       // 1..7
  final TimeWindow window;                 // muss in Öffnungszeit liegen (Validierung weich)
  final int requiredCount;                 // >= 1, Anzahl gleichzeitig benötigter MA
  final List<String> requiredQualificationIds; // leer = keine Quali-Anforderung
  const StaffingDemand({
    required this.weekday,
    required this.window,
    required this.requiredCount,
    this.requiredQualificationIds = const [],
  });
}
```

Neues Feld `final List<StaffingDemand> staffingDemands;` (Default `const []`) — **dieselben 7 Serialisierungs-Stellen** wie §1.2:
- camelCase Keys: `staffingDemands`, je Element `{weekday, window:{startMinute,endMinute}, requiredCount, requiredQualificationIds}`.
- snake_case Keys: `staffing_demands`, je Element `{weekday, window:{start_minute,end_minute}, required_count, required_qualification_ids}`.
- Zahlen via `parse.toInt`, Listen tolerant (`(x as List?) ?? const []`).

**Semantik:** Hat ein Standort keine `staffingDemands`, aber Öffnungszeiten, erzeugt der Generator **eine** Schicht pro Öffnungsfenster (impliziter Bedarf 1). Optional konfigurierbar via Settings-Default (§4, `defaultRequiredCount`), aber Modell-Default bleibt 1.

---

## 3. Vertrags-Stundengrenzen: Woche UND Monat

Datei: `lib/models/employment_contract.dart` (`class EmploymentContract`, Z.55). Vorhandene Felder: `weeklyHours` (double, Default 40, Z.87), `dailyHours` (Z.88), `monthlyGrossCents` (int?, Z.98), `maxDailyMinutes` (int?, Z.106), `monthlyIncomeLimitCents` (int?, Z.107, Minijob 60300=603 €), `EmploymentType` (Z.6: `fullTime/partTime/miniJob/trainee` → `.value` `full_time/part_time/mini_job/trainee`).

**Zwei neue Felder** (beide `double?`, nullable; leer = keine vertragliche Grenze, nur Compliance/Minijob greifen):
- `monthlyMaxHours`
- `weeklyMaxHours`

Folge der „Feld hinzufügen"-Regel an allen Stellen in `employment_contract.dart` (V1-Zeilennummern bleiben gültig):
1. **`toFirestoreMap()`** (Z.184): `'monthlyMaxHours': monthlyMaxHours`, `'weeklyMaxHours': weeklyMaxHours` (camelCase, roher double/null).
2. **`fromFirestore(id, map)`** (Z.127): `monthlyMaxHours: map['monthlyMaxHours'] == null ? null : parse.toDouble(map['monthlyMaxHours'])` (analog `weeklyMaxHours`). Spiegle die exakte Null-Erhalt-Konvention des Files (`import '../core/firestore_num_parser.dart' as parse;`).
3. **`toMap()`** (Z.215): `'monthly_max_hours': monthlyMaxHours`, `'weekly_max_hours': weeklyMaxHours` (snake_case).
4. **`fromMap(map)`** (Z.156): `monthlyMaxHours: map['monthly_max_hours'] == null ? null : parse.toDouble(...)` (analog `weekly_max_hours`).
5. **`copyWith()`** (Z.241): Parameter `double? monthlyMaxHours, double? weeklyMaxHours` **+** `bool clearMonthlyMaxHours = false, bool clearWeeklyMaxHours = false` (nullable-Leeren-Muster `clearX ? null : (x ?? this.x)`). Spiegle bestehende `clearX`-Flags (z.B. `clearMonthlyGrossCents`).
6. **`functions/index.js`**: Verträge laufen **NICHT** über Callables → kein Eingriff. Verifiziere per Suche nach `weeklyHours`/`weekly_hours` in `functions/index.js`; falls dort doch Vertragsfelder geparst werden, ergänze beide Felder analog.

**Konstruktor:** `this.monthlyMaxHours`, `this.weeklyMaxHours` (nullable, ohne Default). Bestehende Instanzen bleiben gültig (null).

**Verhältnis zu Compliance:** Beide Caps sind **Planungsschranken im Verteiler**, KEINE neue Compliance-Violation. `compliance_service.dart`/`functions/index.js`-Schwellen bleiben unangetastet (minRest 660, Pausen 30@360/45@540, maxPlanned 600/Tag, Minijob 60300). Eine neue Violation würde CLAUDE.md-Kopplung #2 (beide Dateien + `defaultRetail`↔`defaultRuleSet`) auslösen — NICHT tun.

**UI zum Pflegen der Grenzen:** Ergänze die bestehende Vertrags-/Mitarbeiter-Vertragsmaske in `lib/screens/team_management_screen.dart` um zwei optionale Zahlenfelder:
- „Max. Wochenstunden" → `weeklyMaxHours`
- „Max. Monatsstunden" → `monthlyMaxHours`

Beide Felder sind nullable und müssen explizit leerbar sein (entspricht den `clearWeeklyMaxHours`/`clearMonthlyMaxHours`-Flags). Anzeige/Eingabe deutsch formatiert (`de_DE`), aber Modellwerte bleiben `double?`. Ohne diese UI bleiben die neuen Caps praktisch immer `null` und der Verteiler kann die gewünschte Grenze nicht nutzen.

---

## 4. Umschaltbare Cap-Härte: org-weites Settings-Flag

**Settings-Heimat (aus Recherche):** Es gibt heute **kein** org-weites Operational-Settings-Dokument. `FeatureFlagProvider` liest `organizations/{orgId}/config/appFlags` (sameOrg-lesbar, admin-write). `OrgPayrollSettings` liegt unter `payrollConfig/{jahr}` (nur Lohn). Beste Lösung: **neues Dokument** `organizations/{orgId}/config/orgSettings` (analog `appFlags`).

### 4.1 Modell + Provider

- Neues Modell `lib/models/org_settings.dart`, `class OrgSettings` mit:
  - `bool enforceHourCapHard` (Default `true`)
  - `int defaultShiftMinutes` (Default `480` = 8 h) — Ziel-Schichtlänge im Generator
  - `int defaultBreakMinutes` (Default `30`)
  - `int defaultRequiredCount` (Default `1`) — Fallback-Bedarf, wenn `staffingDemands` leer
  - Zwei-Serialisierung wie üblich (camelCase Firestore / snake_case lokal+Payload). Doc-ID fix `orgSettings` (deterministisch, kein Jahr).
- Lade es analog `FeatureFlagProvider.fetchAppConfig`/`watchOrgPayrollSettings`. **Zwei gangbare Wege — wähle den geringsten Eingriff:**
  - **(Bevorzugt)** Erweitere `FeatureFlagProvider` (`lib/providers/feature_flag_provider.dart`, Proxy2<Auth,Storage>, registriert in `main.dart` Z.289–301) um einen `OrgSettings`-Getter (`orgSettings`/`enforceHourCapHard`), zweiter Stream/Read auf `config/orgSettings`. Vorteil: bereits in der Provider-Kette, vom Redirect gelesen, kein neuer Proxy.
  - (Alternativ) Neuer `OrgSettingsProvider` (Proxy2<Auth,Storage>) **nach** `FeatureFlagProvider` in der Kette (`main.dart`, CLAUDE.md-Reihenfolge tragend). Nur wenn FeatureFlagProvider-Erweiterung zu groß wird.
- `FirestoreService`: Collection-Getter `_organizationDoc(orgId).collection('config').doc('orgSettings')` analog `fetchAppConfig`; `fetchOrgSettings()`/`watchOrgSettings()` + `saveOrgSettings()`-Write.
- Lokaler Fallback: `DatabaseService`-Key `local_v2/org_settings` (org-skopiert, in `_orgScopedCollectionKeys` registrieren). Im reinen Local-/Demo-Modus darf `FeatureFlagProvider.updateSession` die Settings **nicht** einfach zurücksetzen, sondern muss `OrgSettings.defaults()` bzw. lokal gespeicherte Settings liefern. Im Hybrid-Modus Remote-Snapshot lokal spiegeln.
- `firestore.rules`: prüfen. Der aktuelle generische Block `match /config/{configId}` erlaubt bereits sameOrg-read/admin-write für `appFlags`; wenn er unverändert vorhanden ist, ist für `orgSettings` **kein zusätzlicher Rules-Block nötig**. Nur ergänzen, wenn im Zielstand kein generischer Config-Block existiert oder feldgenaue Validierung gewünscht ist.

### 4.2 UI zum Umschalten

Datei `lib/screens/settings_screen.dart` zeigt heute nur `UserSettings` (persönlich). Ergänze eine **admin-only** Org-Sektion (sichtbar nur bei `profile.isAdmin`, Getter aus `lib/models/app_user.dart`):
- `SwitchListTile` „Stundengrenzen hart durchsetzen" (`enforceHourCapHard`), Helper deutsch: „Aus: Grenzen dürfen bei Engpässen überschritten werden (Warnung in der Vorschau)."
- Optional: numerische Felder für `defaultShiftMinutes`/`defaultBreakMinutes`/`defaultRequiredCount` (deutsche Eingabe, `de_DE`).
- Speichern via `featureFlagProvider.saveOrgSettings(...)` (bzw. neuer Provider). Audit: org-Settings-Änderung IST fachlich relevant → auf Erfolgs-Pfad genau einmal loggen, entweder über `AuditProvider.log(...)` aus der UI oder über eine bewusst ergänzte Audit-Senke im Settings-Provider (`action:'updated', entityType:'Organisationseinstellungen', summary:'...'`). Persönliche UserSettings weiterhin NICHT loggen — die sind Rauschen.

### 4.3 UI zum Pflegen der Site-Öffnungszeiten + Bedarf

Datei `lib/screens/team_management_screen.dart`, `_SiteEditorSheet` (Z.2968–3190), aufgerufen via `showModalBottomSheet` (Z.316), Persistenz `TeamProvider.saveSite()` (Z.849–899). Ergänze unterhalb der Adressfelder:
- Pro Wochentag (Mo–So, deutsche Labels) eine Zeile mit „+ Zeitfenster"-Aktion: je Fenster zwei Zeit-Picker (`showTimePicker`, Ergebnis → Minuten) für von/bis, plus „Benötigte MA" (numerisch, Default 1) und optional Multi-Select Qualifikationen (`requiredQualificationIds`, vorhandene Quali-Liste aus `TeamProvider`).
- Beim `_save()` der Site: `weekdayHours` und `staffingDemands` in `SiteDefinition.copyWith(...)` setzen; `TeamProvider.saveSite()` persistiert (Audit dort vorhanden: `entityType:'Standort'`).
- Validierung weich: `endMinute > startMinute`; `requiredCount >= 1`; Bedarf-Fenster sollte in einem Öffnungsfenster liegen (Warnung, kein harter Block).

---

## 5. Phase A — Schicht-Generator (pure, testbar)

**Neue Datei:** `lib/core/shift_slot_generator.dart`. **Kein** Provider-State, **kein** `BuildContext`, **keine** Firestore/Async-IO. Keine `DateTime.now()` außer injiziert. Vorbild für pure Logik: `lib/screens/shift_planner/planner_logic.dart`.

### Eingaben
- `List<SiteDefinition> sites` (mit `weekdayHours` + `staffingDemands`).
- `DateTime rangeStart`, `DateTime rangeEnd` (Halb-offen `[start, end)` — Woche oder Monat; injiziert, nie `now()`).
- `OrgSettings settings` (Default-Schichtlänge/Pause/Bedarf).
- `List<Shift> existingShifts` im Bereich (um **Doppel-Generierung** zu vermeiden: bereits existierende Slots an gleichem `siteId`+Zeitfenster count-aware berücksichtigen — Vergleich über `startTime`+`endTime`+`siteId`).
- `String orgId`, `String seriesId` (vom Provider via `newSeriesId()` erzeugt) **und** `String Function() shiftIdFactory` (vom Provider via `_nextLocalId('shift')`, in Tests deterministisch). Der Pure-Core erzeugt weder UUID noch `DateTime.now()`, braucht aber stabile IDs, weil Phase B/Preview/Apply Vorschläge über `shift.id` zusammenführen.

### Logik (deterministisch)
1. Für jeden Tag `d` in `[rangeStart, rangeEnd)`:
2. Für jede `site` mit `weekdayHours` an `d.weekday`:
3. Bestimme die Schicht-Slots pro Öffnungsfenster:
   - Bedarf aus `staffingDemands` für (weekday, überlappende Fenster). Falls keiner → ein impliziter Bedarf `requiredCount = settings.defaultRequiredCount`, Quali leer, Fenster = Öffnungsfenster. Bei mehreren Bedarfsfenstern erst in disjunkte Segmente schneiden (oder überlappende Demands deterministisch zusammenfassen), damit pro Zeitraum eindeutig ist, welche `requiredCount`/Qualis gelten.
   - `settings.defaultShiftMinutes` ist **Brutto-Schichtdauer inkl. Pause**. Zerlege lange Öffnungs-/Bedarfsfenster in sinnvolle Brutto-Schichtlängen ~`defaultShiftMinutes`; aufeinanderfolgende Schichten dürfen sich an Tagesrändern **leicht überlappen** (Übergabe), z.B. 0–15 min Overlap — konfigurierbar als Konstante, dokumentiert. Reste < ~50 % der Soll-Länge an die Nachbarschicht anhängen (kein Mini-Splitter-Slot).
   - Break-Minuten deterministisch berechnen: mindestens `settings.defaultBreakMinutes`, aber bei langen Slots ausreichend für die bestehende Compliance-Pausenregel (Default 30@>6h netto, 45@>9h netto). Ein generierter Slot darf nicht allein wegen zu kurzer Pause sofort an `break_required` scheitern.
   - Pro Slot **bis zu `requiredCount` unbesetzte `Shift`-Objekte** erzeugen: `id = shiftIdFactory()`, `userId = ''` (`isUnassigned`), `employeeName = ''`, `title = site.name` (oder „Dienst <Standort>"), `startTime/endTime` aus Slot (Tagesdatum + Minuten, 12:00-Normalisierung NICHT für Schichten — Schichten tragen echte Uhrzeit), `breakMinutes`, `siteId = site.id`, `siteName = site.name`, `requiredQualificationIds` aus dem Bedarf, `orgId`, `seriesId` (übergeben), `status = planned`.
4. **Idempotenz count-aware:** vorhandene Schichten mit gleichem `siteId` + `startTime` + `endTime` zählen, egal ob besetzt oder offen. Bei `requiredCount = 3` und bereits 1 existierender Schicht werden nur noch 2 neue Slots erzeugt. Nicht „wenn eine existiert, alles überspringen".
5. Ausgabe: `List<Shift>` der **neu zu erstellenden, unbesetzten** Schichten (deterministisch sortiert nach `startTime, siteId, id`).

**Determinismus Pflicht:** keine ungeordnete Map-Iteration, kein `now()`, keine Zufallswerte; `seriesId` und `shiftIdFactory` injiziert.

---

## 6. Phase B — Verteiler (pure, testbar)

**Neue Datei:** `lib/core/shift_auto_assigner.dart`. Gleiche Pure-Regeln wie §5.

### Eingaben (alles injiziert)
- `List<Shift> openShifts` — unbesetzte Schichten (Ausgabe von Phase A **plus** ggf. schon vorher vorhandene unbesetzte Schichten im Bereich).
- `List<AppUserProfile> members` — exakter Typ aus `schedule_provider.updateReferenceData(members:, ...)`-Signatur (Z.227).
- `List<EmploymentContract> contracts` **oder** ein injizierter `EmploymentContract? Function(String userId, DateTime at)`-Resolver. Nicht nur `Map<String, EmploymentContract>`, weil Verträge gültig-ab/versioniert sind; pro Schicht muss der aktive Vertrag zum `shift.startTime` gelten.
- `List<EmployeeSiteAssignment> siteAssignments` (`siteId`, `qualificationIds`, `isPrimary`; `lib/models/employee_site_assignment.dart`).
- `List<AbsenceRequest> approvedAbsences` — **nur** `status == AbsenceStatus.approved` (Recherche: nur `approved` blockiert; `pending`/`rejected` nicht). Blockierende Typen siehe §8.
- `List<Shift> existingAssignedShiftsInMonth` und `...InWeek` — bereits besetzte Schichten (für Monats-/Wochen-Stundensummen + minRest + Doppelbelegung).
- `List<ComplianceRuleSet> ruleSets` + `List<TravelTimeRule> travelTimeRules`.
- `ComplianceService complianceService` (injiziert).
- `OrgSettings settings` — liefert `enforceHourCapHard`.
- Optional `Map<String, SollzeitProfile> sollzeitByUserId` (`lib/models/sollzeit_profile.dart`) für Fairness-Zielstunden.

### Ausgabe (pure Result-Struktur, im File)
```dart
class AutoAssignmentResult {
  final List<ShiftAssignmentProposal> assignments; // shiftId -> userId, score, reason
  final List<UnassignableShift> unassigned;         // shiftId + Grund-Enum/-Text
  final List<AssignmentWarning> warnings;           // weiche Verletzungen (Soft-Cap überschritten etc.)
}
```
`ShiftAssignmentProposal`: `shiftId, userId, userName(Snapshot), score, reason(deutsch)`. **Keine** `Shift`-Mutation im Core — die UI/Provider baut `shift.copyWith(userId:..., employeeName:...)`.

### Harte Constraints (Kandidat verworfen)
Pro (Schicht, Kandidat):
0. **Aktive Kandidaten**: nur `members` mit `isActive == true` und passender Org berücksichtigen.
1. **Standort-Berechtigung**: `EmployeeSiteAssignment` mit `siteId == shift.siteId`. Wenn eine offene Schicht keine `siteId` hat, nicht automatisch zuweisen, sondern `unassigned` mit Grund „Standort fehlt"; nach Zuweisung würde `ComplianceService` sonst `site_required` blockieren.
2. **Quali-Match**: `shift.requiredQualificationIds` ⊆ verfügbare Qualis (aus `siteAssignments.qualificationIds`; Annahme dokumentieren).
3. **Abwesenheit**: keine `approvedAbsences` (blockierende Typen, §8) überschneidet den Schichttag (`AbsenceRequest.overlaps`, `absence_request.dart:262`).
4. **Doppelbelegung**: keine Überschneidung mit bereits/innerhalb des Laufs zugewiesenen Schichten (`Shift.overlaps`, `shift.dart:116`).
5. **Compliance** (via `complianceService.validateShift`, mit allen bestehenden + frisch geplanten Schichten des Users): keine **blockierende** Violation. Schwellen aus aufgelöstem `ComplianceRuleSet` (Kaskade siteId+type → siteId → type → global → `defaultRetail`), **nie** hartkodiert.
6. **Monats-Cap** (nur wenn `enforceHourCapHard == true` **und** aktiver Vertrag am `shift.startTime` `monthlyMaxHours != null`): `geplanteMonatsstunden(User) + shift.workedHours ≤ monthlyMaxHours`.
7. **Wochen-Cap** (nur wenn `enforceHourCapHard == true` **und** aktiver Vertrag am `shift.startTime` `weeklyMaxHours != null`): `geplanteWochenstunden(User, ISO-Woche der Schicht) + shift.workedHours ≤ weeklyMaxHours`.
8. **Minijob-Verdienst** (nur aktiver Vertrag `EmploymentType.miniJob`, falls `hourlyRate` bekannt): `(geplanteMonatsstunden + shift.workedHours) × hourlyRate × 100 ≤ monthlyIncomeLimitCents ?? 60300` bzw. RuleSet-Fallback. Fehlt `hourlyRate` → überspringen, auf Compliance verlassen. (Minijob-Verdienst bleibt **immer hart**, unabhängig von `enforceHourCapHard` — gesetzlich, nicht „Stundengrenze".)

> **Cap-Härte umschaltbar (Constraint 6+7):**
> - **Hart** (`enforceHourCapHard == true`): Constraints 6/7 verwerfen Kandidaten. Ist kein Kandidat unter der Grenze → Slot bleibt **offen** (`unassigned`, Grund „Monats-/Wochengrenze erreicht").
> - **Weich** (`false`): Constraints 6/7 werden **nicht** als harter Filter angewendet. Stattdessen darf die Grenze überschritten werden; die Überschreitung erzeugt eine **`AssignmentWarning`** (deutlich: „<Name> über Monatsgrenze: 178/160 h") und einen **Score-Penalty** (siehe unten), sodass weich überlastete Kandidaten zuletzt gewählt werden. Compliance (5) und Minijob (8) bleiben in BEIDEN Fällen hart.

### Weiche Ziele (Scoring, höher = besser)
- **Fairness/Auslastung**: bevorzuge MA, deren `geplanteMonatsstunden` am weitesten **unter** der Zielstunde liegen. Ziel = aktives `monthlyMaxHours` falls gesetzt, sonst `SollzeitProfile`-Monatssoll, sonst aktive `weeklyHours × 4.33`. Term `(ziel − geplant)/ziel` (bei Ziel ≤ 0 neutral behandeln).
- **Wochen-Balance**: analoger Term für aktives `weeklyMaxHours` bzw. Wochensoll (vermeidet, dass jemand seine Woche in einem Tag füllt).
- **Soft-Cap-Penalty** (nur bei `enforceHourCapHard == false`): wenn Zuweisung die Monats- ODER Wochengrenze überschreiten würde, starker negativer Score-Term proportional zur Überschreitung.
- **Primär-Standort**: kleiner Bonus bei `EmployeeSiteAssignment.isPrimary` für `shift.siteId`.
- **Reisezeit** (optional, `travelTimeRules`): Penalty proportional zur Reisezeit.
- **Präferenzen**: kein Modell im Repo → ungenutzter Hook-Parameter `preferenceWeight`.

### Algorithmus (Greedy, stabile Sortierung)
1. Sortiere `openShifts` deterministisch: `startTime`, dann `siteId`, dann `id`.
2. Init `plannedMonthMinutesByUser` / `plannedWeekMinutesByUser` aus `existingAssignedShifts...`.
3. Je Schicht (sortiert):
   a. Kandidaten = alle aktiven `members`, filtere harte Constraints 0–8 (Compliance gegen aktuellen Stand; Cap 6/7 nur wenn hart).
   b. Leer → `unassigned` + **priorisierter deutscher Grund** (Reihenfolge: Quali → Standort → Cap/Minijob → Abwesenheit → Compliance → „keine verfügbaren Mitarbeiter").
   c. Sonst Score je Kandidat, höchsten wählen; Tie-Break deterministisch nach `userId` (lexikografisch).
   d. `ShiftAssignmentProposal` anlegen; Minuten zu Monat+Woche addieren; virtuell zugewiesene Schicht zur Konflikt-/Compliance-Basis des Users hinzufügen; bei Soft-Cap-Überschreitung `warnings` ergänzen.
4. Reines Ergebnis zurückgeben.

**Determinismus Pflicht** (siehe §5).

---

## 7. Integration in `ScheduleProvider`

Datei `lib/providers/schedule_provider.dart` (`class ScheduleProvider`, Z.100). Bausteine: `saveShifts()` (Z.389, Batch ≤50, Callable `upsertShiftBatch` + direkter Firestore-Fallback, Audit, Recurrence/seriesId), `updateReferenceData(members, contracts, siteAssignments, ruleSets, travelTimeRules)` (Z.227), `_currentRange()` (Z.2349, Monat `DateTime(y,m,1)..DateTime(y,m+1,1)`), `usesLocalStorage`/`usesHybridStorage` (Z.210/211), `setAuditSink` (Z.223), `newSeriesId()` (Z.2206), `_nextLocalId('shift')` (Z.2198), `_complianceService`, `_effectiveRuleSets` (Z.2390), `getShiftsInRange`/`getApprovedAbsencesInRange` (über `FirestoreService`, Z.1962/1988).

Der Provider braucht zusätzlich **Sites** (mit Öffnungszeiten/Bedarf). Sites kommen via `updateReferenceData` (prüfen, ob `sites` schon Teil der Referenzdaten sind; `TeamProvider` ist Produzent der Stammdaten und schiebt Listen via `updateReferenceData` — falls `sites` fehlt, ergänze den Setter; CLAUDE.md: diese Setter rufen **kein** `notifyListeners`). `OrgSettings` bevorzugt **als Methoden-Parameter aus der UI** übergeben (`context.read<FeatureFlagProvider>().orgSettings`), damit kein neuer Provider-Zyklus entsteht. Falls `OrgSettings` stattdessen im `ScheduleProvider` gehalten wird, muss `main.dart` die Proxy-Kette explizit erweitern.

**Neue Methoden:**
1. `List<Shift> generatePlannedShifts({required DateTime rangeStart, required DateTime rangeEnd, required OrgSettings settings})` — Wrapper um `ShiftSlotGenerator`: sammelt Sites + vorhandene Schichten im Bereich, injiziert `seriesId = newSeriesId()` und `shiftIdFactory: () => _nextLocalId('shift')`, gibt **neu zu erstellende unbesetzte** Schichten zurück. Keine Mutation/notify/Audit. Permission-Gate `canManageShifts`.
2. `AutoAssignmentResult proposeAutoAssignment({required List<Shift> openShifts, required DateTime month, required OrgSettings settings})` — Wrapper um `ShiftAutoAssigner`: sammelt Referenzdaten (members, contracts, siteAssignments, ruleSets, travelTimeRules, `approvedAbsences` im Monat, bereits zugewiesene Schichten im Monat **und** in den betroffenen ISO-Wochen), instanziiert, gibt Ergebnis. Keine Mutation/notify/Audit. Permission-Gate `canManageShifts` (sonst leeres Ergebnis bzw. Exception wie andere Mutatoren, Z.396).
3. `Future<void> applyAutoPlan({required List<Shift> generatedShifts, required List<Shift> existingOpenShifts, required AutoAssignmentResult result})` — kombiniert Phase A+B beim Speichern:
   - Baue die finale Schichtliste aus **neu generierten Schichten** plus **bereits existierenden offenen Schichten, die im Ergebnis eine Zuweisung bekommen haben**. Für jede Schicht passende `ShiftAssignmentProposal` (per nicht-null `shift.id`) finden und `shift.copyWith(userId: proposal.userId, employeeName: proposal.userName)` setzen.
   - Nicht zugewiesene generierte Schichten **trotzdem** als unbesetzte Schichten speichern (sie bleiben offen, sind aber jetzt angelegt) — ODER (Entscheidung dokumentieren, Default: speichern, damit der Bedarf sichtbar bleibt). Bereits vorher existierende offene Schichten ohne neue Zuweisung nicht erneut speichern.
   - Rufe den **bestehenden** `saveShifts(finalShifts)` (Batch ≤50, Storage-Modi, Compliance-Re-Validierung, Exceptions). Phase-A-Schichten tragen den generierten `seriesId`; übergib ihn **nicht** als neue Recurrence (Schichten sind bereits expandiert) — vorhandene `seriesId` der Shift-Objekte unverändert lassen, `saveShifts(..., seriesId: null, recurrencePattern: null)`.
   - **Audit:** `saveShifts` loggt bereits (`action: updated/created`, `entityType:'Schicht'`, Z.455–462/510–517). Um Doppel-Logs zu vermeiden: genau EINE zusätzliche Summary **einmalig** nach Erfolg: `_audit?.call(action:'created', entityType:'Schicht', entityId:null, summary:'<n> Schichten generiert, <m> automatisch besetzt')` — nur auf Erfolgs-Pfad, nie auf rethrow.
4. (Optional getrennt nutzbar) `Future<void> applyAutoAssignment(AutoAssignmentResult result)` — nur Besetzung vorhandener unbesetzter Schichten ohne Generierung (für „nur verteilen"-Variante).

**Notify:** in async ausschließlich `_safeNotify()`. **Mutator-Muster** erbt `applyAutoPlan` automatisch von `saveShifts` (hybrid-Fallback nicht-rethrow, cloud rethrow, `ComplianceRejectedException` nie fallbacken).

---

## 8. Abwesenheiten: welche Typen blockieren

Aus Recherche (`lib/models/absence_request.dart`): `AbsenceType` (Z.5–19) hat 12 Werte: `vacation, sickness, unavailable, specialLeave, unpaidLeave, timeOff, parentalLeave, maternity, vocationalSchool, volunteering, shortTimeWork, childSick`. `AbsenceStatus` (Z.21): `pending, approved, rejected`. Blockierung erfolgt heute generisch über `status == approved` + `overlaps()` (`schedule_provider.dart` Z.644–645).

**Anforderung:** **Urlaub (`AbsenceType.vacation`) UND Krankheit (`AbsenceType.sickness`)** blockieren die Zuweisung — beide sind `AbsenceRequest` mit `status == AbsenceStatus.approved`. Da die bestehende Logik bereits **jede** genehmigte Abwesenheit blockiert, blockieren `vacation`/`sickness` automatisch mit. Der Verteiler-Filter (§6 Constraint 3) prüft daher: jede `approvedAbsences`-Überschneidung blockiert; in den **Tests** werden `vacation` und `sickness` als eigene Fälle explizit asserted. Eine Typ-Whitelist ist nicht nötig (alle genehmigten Abwesenheiten = nicht verfügbar). Wenn ein Typ doch NICHT blockieren soll (z.B. `timeOff`-Stundenkonto-Teiltag), §10 zurückfragen — Default: alle genehmigten blockieren ganztägig (konservativ).

---

## 9. Compliance-Kopplung

- Verteiler erzeugt **nur** Compliance-konforme Vorschläge via `complianceService.validateShift(...)`; verwirft blockierende Violations. **Keine** hartkodierten Schwellen — alles aus `ComplianceRuleSet` (`defaultRetail`-Fallback).
- Generator (Phase A) setzt Pausen passend zur Pausenregel (30@360/45@540), damit erzeugte Slots compliance-fähig sind.
- Schwellen-Spiegel `compliance_service.dart` ↔ `functions/index.js` (`validateSingleShift`) **nicht** ändern. Stundengrenzen (Woche/Monat) sind Planungsschranken, **keine** Violation (CLAUDE.md-Kopplung #2 nicht auslösen).
- Server re-validiert beim Speichern über `upsertShiftBatch`. `ComplianceRejectedException`/`ShiftConflictException` sauber an die UI propagieren (nicht schlucken).

---

## 10. Planner-UI-Flow: „Automatisch planen"

Dateien:
- `lib/screens/shift_planner_screen.dart` — `_AdminShiftPlannerBoard` (Z.1081), Toolbar/Aktionen, vorhandene Flows `_copyWeek` (Z.661), `_openShiftEditor` (Z.890), `_showShiftConflictDialog` (Z.945), `_showComplianceRejectionDialog` (Z.975).

**Platzierung:** Toolbar-Aktion im Admin-Board neben „Woche kopieren", nur bei `canManageShifts`. Beschriftung **„Automatisch planen"** (bzw. zwei Aktionen: „Schichten generieren" + „Automatisch besetzen", falls getrennte Nutzung gewünscht — Default: eine kombinierte Aktion).

**Flow:**
1. Bereich (Woche/Monat) aus Board-State / `_currentRange`.
2. `settings = context.read<FeatureFlagProvider>().orgSettings`.
3. `generated = scheduleProvider.generatePlannedShifts(rangeStart:, rangeEnd:, settings:)` (Phase A).
4. `existingOpen = vorhandene isUnassigned-Schichten im Bereich`.
5. `openShifts = generated + existingOpen`.
6. `result = scheduleProvider.proposeAutoAssignment(openShifts:, month:, settings:)` (Phase B).
7. **Vorschau-Sheet** (`showModalBottomSheet(showDragHandle:true, isScrollControlled:true, useSafeArea:true)`):
   - **Neu zu erstellen**: Anzahl generierter Schichten je Standort/Tag.
   - **Zuweisungen (Diff)**: „<Datum, Uhrzeit, Standort> → <Mitarbeiter>" + Begründung/Score.
   - **Warnungen** (gelb, `Theme.of(context).appColors.warning`): u.a. Soft-Cap-Überschreitungen mit Stundenzahl.
   - **Nicht zuweisbar** (Warnfarbe): Schicht + Grund.
   - Bei `enforceHourCapHard == false` deutlicher Hinweis-Banner: „Stundengrenzen sind weich — Überschreitungen erlaubt."
   - Datumsformat **immer** `DateFormat(..., 'de_DE')`; Zahlen `NumberFormat(... ,'de_DE')`.
   - Buttons „Abbrechen" / „Übernehmen & speichern".
8. Bei Bestätigung `await scheduleProvider.applyAutoPlan(generatedShifts: generated, existingOpenShifts: existingOpen, result: result)`.
9. Fehler: `ShiftConflictException` → `_showShiftConflictDialog`, `ComplianceRejectedException` → `_showComplianceRejectionDialog`. Erfolg → SnackBar „<n> Schichten geplant, <m> besetzt".

Routing: imperatives Sheet (`showModalBottomSheet`), **keine** neue go_router-Route (CLAUDE.md: Detail/Editor-Sheets imperativ).

---

## 11. Tests (offline, fakes)

Setup (CLAUDE.md „Tests"): `TestWidgetsFlutterBinding.ensureInitialized()`, `await initializeDateFormatting('de_DE')`, `SharedPreferences.setMockInitialValues({}); DatabaseService.resetCachedPrefs();`. Kein echtes Firebase; `FakeFirebaseFirestore`; Callables via `cloudFunctionInvoker`. Compliance-Asserts auf `.code`. `FakeFirebaseFirestore` liefert Zahlen als `double`. Subklassen-Seam statt Mockito.

### A) Generator-Tests — `test/shift_slot_generator_test.dart` (pure, feste Daten, injizierter seriesId)
1. **Slot aus Öffnungszeit**: Site mit `weekdayHours` Mo 09:00–17:00, kein Bedarf → eine unbesetzte 8-h-Brutto-Schicht (Default), korrekter `siteId`, `isUnassigned`, korrekte Pause.
2. **Mehrere Zeitfenster/Tag**: Mo 09:00–13:00 + 15:00–19:00 → zwei Slots, Mittagslücke bleibt frei.
3. **Bedarf > 1**: `staffingDemand.requiredCount = 3` → 3 unbesetzte Schichten im Fenster.
4. **Lange Öffnung gesplittet**: 08:00–22:00 → mehrere Schichten ~`defaultShiftMinutes` mit Übergabe-Overlap; kein Mini-Rest-Slot.
5. **Quali aus Bedarf**: `requiredQualificationIds` landen auf der erzeugten Schicht.
6. **Stabile IDs**: jede generierte Schicht hat eine nicht-leere ID aus dem injizierten `shiftIdFactory`.
7. **Idempotenz count-aware**: vorhandene identische Schicht in `existingShifts` bei Bedarf 3 → nur fehlende Anzahl wird erzeugt, nicht 0 und nicht 3.
8. **Determinismus**: gleicher Input → identische Ausgabe.
9. **Kein weekdayHours** → leere Ausgabe.

### B) Verteiler-Tests — `test/shift_auto_assigner_test.dart` (pure, feste Daten)
1. **Happy Path**: 2 offene Schichten, 2 qualifizierte verfügbare MA → beide zugewiesen, deterministisch.
2. **Monats-Cap hart**: `monthlyMaxHours` fast voll, `enforceHourCapHard=true` → Schicht an anderen Kandidaten; keiner übrig → `unassigned` mit Monats-Cap-Grund.
3. **Monats-Cap weich**: gleiche Lage, `enforceHourCapHard=false` → Zuweisung erfolgt, **`AssignmentWarning`** mit Überschreitung, keine `unassigned`.
4. **Wochen-Cap hart**: `weeklyMaxHours` in der ISO-Woche erschöpft → Kandidat raus (Grund Wochengrenze); andere Woche desselben Monats wieder zuweisbar.
5. **Wochen-Cap weich**: Überschreitung erzeugt Warning + Score-Penalty (überlasteter Kandidat zuletzt gewählt).
6. **Toggle-Pfad-Parität**: identischer Input, nur `enforceHourCapHard` umgeschaltet → hart liefert `unassigned`, weich liefert assignment+warning (beide Pfade asserted).
7. **Urlaub blockiert**: genehmigter `vacation` am Schichttag → Kandidat raus (Grund Abwesenheit).
8. **Krankheit blockiert**: genehmigter `sickness` am Schichttag → Kandidat raus (Grund Abwesenheit).
9. **Pending blockiert NICHT**: `vacation` mit `status=pending` → Kandidat bleibt zuweisbar.
10. **Quali fehlt** → raus (Grund Quali).
11. **Standort-Berechtigung fehlt** → raus (Grund Standort).
12. **Minijob-Verdienstgrenze** (immer hart, auch bei `enforceHourCapHard=false`) → weitere Schicht verweigert.
13. **Compliance minRest 660** → raus.
14. **Doppelbelegung** (`Shift.overlaps`) → raus.
15. **Fairness**: unterausgelasteter Kandidat gewinnt; Tie-Break nach `userId`.
16. **Determinismus**: gleicher Input → identisches Ergebnis.

### C) Provider-Test — `test/schedule_provider_auto_assign_test.dart`
- `generatePlannedShifts` liefert plausible Slots mit injizierten Sites + `OrgSettings`.
- `proposeAutoAssignment` liefert plausibles Ergebnis (`updateSession` + `updateReferenceData`, `ruleSets:[ComplianceRuleSet.defaultRetail('org-1')]`).
- `applyAutoPlan` → `saveShifts`: per Subklassen-Seam (`_TestScheduleProvider`) prüfen, dass generierte Schichten (mit/ohne `userId`) persistiert werden **und** bereits existierende offene Schichten mit Proposal wirklich zugewiesen/gespeichert werden.
- Permission-Gate: ohne `canManageShifts` → leeres/abgelehntes Ergebnis.
- Hybrid-Fallback: Callable `FirebaseFunctionsException(code:'unavailable')` → lokale Persistenz, kein rethrow.
- Cap-Toggle aus `OrgSettings` wirkt durch (hart vs. weich liefert unterschiedliche `unassigned`/`warnings`).

### D) Serialisierungs-Round-Trips
- `test/employment_contract*`: `monthlyMaxHours` UND `weeklyMaxHours` round-trippen (Firestore camelCase ↔ lokal snake_case, inkl. null); `copyWith(...)` setzt/`clearX:true` leert beide.
- `test/site_definition*` (neu/erweitert): `weekdayHours` (inkl. mehrerer `TimeWindow`) und `staffingDemands` round-trippen in beiden Formaten; leere Listen bleiben leer.
- `test/org_settings*` (neu): `OrgSettings` round-trippt; Defaults (`enforceHourCapHard=true` etc.) korrekt.
- Widget-/Formtest für Vertragsmaske: `weeklyMaxHours`/`monthlyMaxHours` setzen und wieder leeren.

---

## 12. Definition of Done / Quality Gates

```bash
flutter analyze            # 0 neue Issues; lint-Regeln NICHT erweitern
flutter test               # alle bestehenden + neuen Tests grün
flutter test test/shift_slot_generator_test.dart
flutter test test/shift_auto_assigner_test.dart
flutter run --dart-define=APP_DISABLE_AUTH=true   # Smoke: Site-Öffnungszeiten+Bedarf pflegen → Settings Cap-Toggle → Planner „Automatisch planen" → Vorschau → Speichern; einmal mit hart, einmal mit weich
```
- Keine neuen Lint-Regeln, kein Mockito, keine neue Dependency.
- UI-/Fehlertexte Deutsch; jedes `DateFormat`/`NumberFormat` mit `'de_DE'`.
- Audit nur auf Erfolgs-Pfad, kein Doppel-Log (Org-Settings-Änderung + eine Auto-Plan-Summary).
- `_safeNotify()` in async; go_router unangetastet (Sheets imperativ).
- `firestore.rules`: `config/orgSettings` ist durch den generischen `config/{configId}`-Block admin-write/sameOrg-read abgedeckt oder ein äquivalenter spezifischer Block ist ergänzt.
- CLAUDE.md aktualisieren (neue Felder `SiteDefinition.weekdayHours/staffingDemands`, `EmploymentContract.monthlyMaxHours/weeklyMaxHours`, neues `config/orgSettings`-Dokument, Pure-Core `shift_slot_generator.dart`/`shift_auto_assigner.dart`). Memory `schichtplan-ux-ausbau.md` ergänzen, falls diese Memory-Datei im Zielkontext existiert.

---

## 13. Nicht-Ziele, Edge Cases & offene Entscheidungen

**Nicht-Ziele:**
- Kein eigenständiges `StaffingRequirement`-Top-Level-Modell/Collection — Bedarf hängt am Standort (`staffingDemands`).
- Kein `headcount`-Feld auf `Shift` — Bedarf > 1 wird durch *mehrere* unbesetzte `Shift`-Objekte abgebildet.
- Kein Präferenz-/Wunsch-Modell (nur ungenutzter Hook).
- Keine neue Compliance-Violation für Wochen-/Monats-Cap (Planungsschranke).
- Keine Schichterzeugung aus Schicht-*Vorlagen* (Generator nutzt Öffnungszeiten+Bedarf, nicht `shiftTemplates`).

**Edge Cases:**
- Schichten ohne `siteId` → nicht automatisch zuweisen; als `unassigned` mit Grund „Standort fehlt" melden, weil gespeicherte zugewiesene Schichten sonst an `site_required` scheitern.
- Schicht über Monatsgrenze → Monat anhand `startTime`; Woche anhand ISO-Woche der `startTime` (dokumentieren).
- MA ohne Vertrag → kein Cap, aber Compliance/Quali greifen.
- `hourlyRate` fehlt bei Minijob → Verdienst-Schranke überspringen.
- Standort mit Öffnungszeit, aber 0 verfügbaren MA → Slots werden generiert, bleiben `unassigned`.
- Bereits besetzte Schichten nie überschreiben — nur `isUnassigned` besetzen; Generator erzeugt idempotent keine Duplikate.
- Weicher Modus: Compliance (ArbZG) bleibt **trotzdem hart** — weich betrifft nur die vertraglichen Stundengrenzen, nicht das Gesetz.

**Vor Implementierung zurückfragen, falls unklar:**
1. `OrgSettings`-Heimat: `FeatureFlagProvider` erweitern vs. neuer `OrgSettingsProvider`? (Annahme: FeatureFlagProvider erweitern.)
2. Sollen alle 12 Abwesenheitstypen ganztägig blockieren, oder Teiltag-Logik für `halfDay`/`timeOff`-Stunden? (Annahme: jede genehmigte Abwesenheit blockiert ganztägig.)
3. Übergabe-Overlap an Tagesrändern: fester Wert (z.B. 0/15 min)? (Annahme: konfigurierbare Konstante, Default 0 — Slots stoßen lückenlos aneinander.)
4. Nicht besetzte generierte Schichten beim Apply trotzdem speichern (sichtbarer Bedarf) oder verwerfen? (Annahme: speichern.)
5. Fairness-Zielstunde-Priorität: `monthlyMaxHours` → `SollzeitProfile` → `weeklyHours×4.33`? (Annahme: ja.)
6. Öffnungszeit über Mitternacht: vorerst als zwei `TimeWindow`s an zwei Kalendertagen pflegen, oder soll das Modell echte Overnight-Fenster unterstützen? (Annahme: splitten, weil `endMinute > startMinute` gilt.)
