# Personal-Modul (HR)

Ausführliche Beschreibung des **Personal-Bereichs** der WorkTime-App: ein
Admin-Bereich für **Aufträge**, **Gehälter/Lohn**, **Finanzen (Personalkosten)**
und **Statistiken** (Krankheit, Nicht-Verfügbarkeit, Urlaub) – mit Filtern und
PDF-/CSV-Export.

> Stand: Juni 2026. Das Modul folgt durchgängig den bestehenden App-Mustern
> (Dual-Serialisierung, org-skopierte Collections, drei Speichermodi, V2-Design-
> System `lib/ui/`) und ergänzt sie um eine HR-/Finanz-Sicht über vorhandene und
> neue Daten.

---

## 1. Zweck & fachlicher Kontext

Die App wird für zwei Geschäfte in Kiel betrieben (**Strichmännchen**, **Tabak
Börse**), abgebildet als zwei **Standorte (`sites`)** innerhalb **einer
Organisation**. Der Personal-Bereich bündelt die personalbezogene Verwaltung an
einer Stelle:

- **Aufträge** – interne Aufgaben/To-Dos für Mitarbeiter **und** ein Spiegel der
  Kundenaufträge aus der Warenwirtschaft.
- **Gehälter/Lohn** – eine transparente Brutto→Netto-Berechnung als **Richtwert**
  (siehe Abschnitt 6 und den Warnhinweis weiter unten).
- **Finanzen** – abgeleitete Personalkosten pro Mitarbeiter, pro Standort und pro
  Monat.
- **Statistiken** – wie oft ein Mitarbeiter krank, nicht verfügbar oder im Urlaub
  war.

> ⚠️ **Rechtlicher Hinweis (Lohn):** Die Lohnabrechnung ist ein **unverbindlicher
> Richtwert – keine offizielle Lohnabrechnung**. Steuer- und Sozialversicherungs-
> beträge werden vereinfacht geschätzt (siehe Abschnitt 6). Dieser Hinweis wird in
> der UI (Banner) **und** im PDF (Fußzeile) prominent angezeigt.

---

## 2. Zugriff & Einstieg

- **Nur Administratoren.** Gate über `AppUserProfile.isAdmin` – es wird **keine
  neue Permission** eingeführt (vermeidet Änderungen an `UserPermissions` und den
  Rules-Invarianten).
- **Kein Bottom-Nav-Tab.** Der Bereich folgt dem Muster von **Team** und
  **Warenwirtschaft**: ein Eintrag in der V2-Menügruppe **„Verwaltung"**, der per
  `Navigator.push` einen Vollbild-Screen öffnet.
  - `lib/widgets/app_nav_menu.dart` – Callback `onOpenPersonal` + Kachel
    „Personal" (`Icons.badge_outlined`), gegated mit `if (isAdmin)`.
  - `lib/screens/home_screen.dart` – `onOpenPersonal: () => _pushFromMenu(const
    PersonalScreen(parentLabel: 'Profil'))`.
- **Reines V2-Design.** Der Screen nutzt ausschließlich `lib/ui/`-Komponenten und
  Design-Tokens (`context.spacing/.radii/.iconSizes`, `context.appColors`) – kein
  V1-Zweig.

---

## 3. Funktionsumfang (UI)

`lib/screens/personal_screen.dart` (`PersonalScreen`, gepusht) baut auf einem
`DefaultTabController` mit fünf Tabs auf, darüber eine **Monatsleiste**
(`< Juni 2026 >`) als globaler Zeitfilter.

### 3.1 Übersicht
Mitarbeiterliste (`TeamProvider.members`) als Karten mit Kennzahlen: geleistete
Stunden im Monat, offene Aufgaben, letztes Netto, Krank-Tage. Tippen öffnet die
**Mitarbeiter-Detailseite** (Hero, KPIs, Abwesenheits-Statistik, Aufträge,
Lohnabrechnungen, Schnellaktionen).

### 3.2 Aufträge
- **Arbeitsaufträge** (`WorkTask`): Anlegen/Bearbeiten/Löschen über ein
  Bottom-Sheet (`AppBottomSheetScaffold` + `AppFormField` + `AppSegmented`).
  Felder: Mitarbeiter, Titel, Beschreibung, Fälligkeit, Priorität, Status.
  Filter nach Status (Chips).
- **Kundenaufträge**: read-only Spiegel der Warenwirtschafts-`CustomerOrder`
  (`InventoryProvider.customerOrders`) mit Status-Pill und Summe. Die **Verwaltung
  bleibt in der Warenwirtschaft** – bewusst keine Dublette (siehe Abschnitt 9).

### 3.3 Lohn
Liste der Abrechnungen des Monats. „Abrechnung" öffnet den Lohn-Editor:
Mitarbeiter, Bruttolohn (mit Vorbefüllung aus Stunden×Stundenlohn bzw. Vertrag),
Steuerklasse, Beschäftigungsart (SV-pflichtig/Minijob/Midijob), Kirchensteuer.
Die **Brutto→Netto-Aufschlüsselung** wird live berechnet; Speichern persistiert
einen `PayrollRecord`, „PDF" exportiert die Abrechnung. Ein **Richtwert-Banner**
ist dauerhaft sichtbar.

### 3.4 Finanzen
Personalkosten-Übersicht für den gewählten Monat:
- KPIs (Gesamtkosten, Stunden, ggf. AG-Gesamtkosten aus Lohnabrechnungen),
- **Kosten pro Mitarbeiter** und **Kosten pro Standort** je als Balkendiagramm
  (fl_chart) + Liste,
- Export als **PDF** oder **CSV** (Menü oben rechts).

### 3.5 Statistik
Abwesenheiten des Jahres aggregiert: **Krank / Nicht verfügbar / Urlaub** als
Team-Summen (Tage), ein Balkendiagramm „Krank-Tage pro Mitarbeiter" und eine
Detailtabelle pro Mitarbeiter.

---

## 4. Datenmodell

Zwei **neue org-skopierte Collections** unter `organizations/{orgId}/`:

| Collection | Modell | Datei |
|---|---|---|
| `workTasks` | `WorkTask` | `lib/models/work_task.dart` |
| `payrollRecords` | `PayrollRecord` | `lib/models/payroll_record.dart` |

Beide halten die **Zwei-Serialisierungs-Regel** ein
(`toFirestoreMap`/`fromFirestore` = camelCase + `Timestamp`;
`toMap`/`fromMap` = snake_case + ISO-8601), nutzen `firestore_num_parser` /
`FirestoreDateParser` und `clearX`-Flags in `copyWith`.

### 4.1 `WorkTask` (interne Aufgaben)
Felder: `id?`, `orgId`, `assignedUserId`, `title`, `description?`, `dueDate?`,
`priority`, `status`, `createdByUid?`, `createdAt?`, `updatedAt?`.

- `enum TaskStatus { open, inProgress, done }` → `open` / `in_progress` / `done`,
  Labels „Offen" / „In Arbeit" / „Erledigt".
- `enum TaskPriority { low, medium, high }` → `low` / `medium` / `high`,
  Labels „Niedrig" / „Mittel" / „Hoch".
- Helfer: `isDone`, `isOverdue` (fällig in der Vergangenheit und nicht erledigt).

### 4.2 `PayrollRecord` (monatlicher Lohn-Snapshot)
Eingaben: `userId`, `periodYear`, `periodMonth`, `grossCents`, `taxClass`
(`TaxClass { i..vi }` → `'1'..'6'`), `churchTax`, `federalState?`,
`kind` (`PayrollEmploymentKind { standard, minijob, midijob }`).
Persistierte berechnete Positionen (alle in Cent): `incomeTaxCents`, `soliCents`,
`churchTaxCents`, KV/PV/RV/ALV je **AN** und **AG**, `netCents`,
`employerTotalCents`.

- **Deterministische Doc-ID** `"<userId>-<jahr>-<mm>"` → eine erneute Abrechnung
  desselben Monats **überschreibt** den Eintrag (kein Duplikat).
- Abgeleitet: `employeeSocialTotalCents`, `employerSocialTotalCents`,
  `totalDeductionsCents`.

### 4.3 `PayrollSettings` (konfigurierbare Sätze, kein Collection-Modell)
`lib/models/payroll_settings.dart` – Wertobjekt mit allen Sätzen + Factories
`defaults2025()` / `defaults2026()`. Optionaler Org-Override wäre unter
`organizations/{orgId}/config/payroll` möglich (Standard: die Const-Defaults).

### 4.4 Wiederverwendete Modelle
`AppUserProfile` (Mitarbeiter), `EmploymentContract` (Stundenlohn/Wochenstunden,
für Kosten + Lohn-Vorbefüllung), `AbsenceRequest` (Krank/Nicht verfügbar/Urlaub),
`WorkEntry` (geleistete Stunden, Standort) und `CustomerOrder` (Warenwirtschaft).

---

## 5. `PersonnelCostRow` & Finanz-Berechnung

`lib/core/personnel_cost.dart` – ein Wertobjekt für die Personalkosten-Übersicht
(`label`, `workedHours`, `laborCostCents`, `employerTotalCents`).

- **Kosten pro Mitarbeiter** = Σ `WorkEntry.workedHours` (für die Person im Monat)
  × `EmploymentContract.hourlyRate`; zusätzlich AG-Gesamtkosten aus einer
  vorhandenen `PayrollRecord` des Monats.
- **Kosten pro Standort** = Aggregation der Zeiteinträge über `WorkEntry.siteName`
  mit dem jeweiligen Stundenlohn der erfassenden Person.

Die org-weiten Zeiteinträge eines Monats liefert die **neue** Methode
`FirestoreService.getOrgWorkEntriesForMonth({orgId, month})` (Range + `orderBy`
auf demselben Feld `date` → **kein** zusätzlicher Composite-Index).

---

## 6. Lohn-Rechner (Richtwert)

`lib/core/payroll_calculator.dart` – **reine, dependency-freie und voll
testbare** Klasse. `PayrollCalculator.calculate({grossCents, taxClass, churchTax,
federalState, kind, settings})` liefert ein `PayrollResult` (alle Positionen in
Cent) und konstruiert via `buildRecord(...)` einen persistierbaren
`PayrollRecord`.

### 6.1 Rechenschritte (ganzzahlige Cent-Arithmetik)
1. **Minijob** (`kind == minijob`): keine AN-Abzüge, **Netto = Brutto**; der
   Arbeitgeber zahlt eine Pauschale (Default 30 %). Frühzeitiger Rücksprung.
2. **Lohnsteuer** = `Brutto × Pauschalsatz je Steuerklasse` – **bewusst
   vereinfacht** (NICHT die amtliche Lohnsteuertabelle / der Programmablaufplan).
3. **Solidaritätszuschlag** = 5,5 % der Lohnsteuer, nur oberhalb der Schwelle.
4. **Kirchensteuer** = 9 % (bzw. 8 % in Bayern/Baden-Württemberg) der Lohnsteuer,
   nur wenn aktiviert.
5. **SV-Beiträge AN** auf die (bei Midijob reduzierte, sonst auf die BBG
   gedeckelte) Bemessungsgrundlage:
   - KV = (allg. Satz + Zusatzbeitrag)/2, PV = Satz/2, RV = Satz/2, ALV = Satz/2.
   - **Midijob** (`kind == midijob`): reduzierte beitragspflichtige Einnahme über
     den Übergangsbereich-Faktor F; AG rechnet auf das volle Brutto.
6. **SV-Beiträge AG** spiegelbildlich (auf das gedeckelte Brutto).
7. **Netto** = Brutto − Lohnsteuer − Soli − KiSt − Σ(SV-AN).
8. **Arbeitgeber-Gesamtkosten** = Brutto + Σ(SV-AG) (bzw. + Minijob-Pauschale).

### 6.2 Konfigurierbare Standard-Sätze (`defaults2026`, Richtwerte)
| Größe | Wert |
|---|---|
| Lohnsteuer-% je Steuerklasse (Richtwert) | I 18 % · II 16 % · III 10 % · IV 18 % · V 30 % · VI 33 % |
| Solidaritätszuschlag | 5,5 % (ab Lohnsteuer > 1.340 €) |
| Kirchensteuer | 9 % (BY/BW 8 %) |
| Krankenversicherung | 14,6 % + 2,5 % Zusatzbeitrag |
| Pflegeversicherung | 3,6 % |
| Rentenversicherung | 18,6 % |
| Arbeitslosenversicherung | 2,6 % |
| BBG KV/PV (Monat) | 5.512,50 € |
| BBG RV/ALV (Monat) | 8.050,00 € |
| Minijob-Grenze / AG-Pauschale | 556 € / 30 % |
| Midijob-Obergrenze / Faktor F | 2.000 € / 0,6683 |

> Diese Sätze sind zentral in `PayrollSettings` gepflegt und pro Jahr austauschbar
> (`defaults2025` / `defaults2026`). Eine **rechtsverbindliche** Abrechnung würde
> amtliche, jährlich gepflegte Tabellen und eine Zertifizierung erfordern – das
> ist hier bewusst **nicht** der Anspruch.

---

## 7. Provider & Verdrahtung

`lib/providers/personal_provider.dart` (`PersonalProvider extends ChangeNotifier`)
nach dem Muster von `InventoryProvider`/`TeamProvider`:

- **Speichermodi**: `usesLocalStorage` / `usesHybridStorage`; Cloud/Hybrid über
  Firestore-Streams (`watchWorkTasks`, `watchPayrollRecords`,
  `watchAllAbsenceRequests`), local über SharedPreferences. Schreibende
  Operationen fallen im Hybrid-Modus offline lokal zurück (`_tryFirestore`).
- **Stammdaten** via `updateReferenceData({members, contracts, sites})` aus dem
  `TeamProvider` (alle org-weit).
- **Org-weite Zeiteinträge** lädt der Provider bei Bedarf direkt
  (`loadOrgWorkEntriesForMonth`) – **nicht** über den `WorkProvider`, der user-/
  monatsskopiert ist.
- **Aggregationen**: `absenceStatsForUser`, `tasksForUser`, `payrollForUser`,
  `contractForUser`, `latestPayrollForUser` …
- **Schreibgate**: jede Mutation prüft `_currentUser?.isAdmin`.

**Einhängung** in `lib/main.dart`: ein
`ChangeNotifierProxyProvider3<AuthProvider, TeamProvider, StorageModeProvider,
PersonalProvider>` direkt **nach** dem `TeamProvider`-Block.

---

## 8. Services, Persistenz, Export

- **`lib/services/firestore_service.dart`** – Collection-Getter `_workTaskCollection`,
  `_payrollRecordCollection`; `watch/save/delete` für beide; `savePayrollRecord`
  nutzt die deterministische Doc-ID; `getOrgWorkEntriesForMonth`. Die `watch`-
  Queries laufen **ohne `orderBy`** (kleine org-skopierte Collections): nullbare
  Felder würden sonst ausgeblendet, und es sind keine Composite-Indizes nötig –
  sortiert wird clientseitig.
- **`lib/services/database_service.dart`** – Keys `work_tasks`, `payroll_records`
  in `_orgScopedCollectionKeys`; `loadLocal…`/`saveLocal…` über
  `_loadCollection`/`_saveCollection`. Keine Legacy-Migration (neue Collections).
- **`lib/services/pdf_service.dart`** – `generatePayrollReport` (Header,
  Summenkarten, AN-/AG-Positionstabelle, **fetter Richtwert-Hinweis**) und
  `generatePersonnelCostReport` (Kosten-Tabelle). NotoSans-Fonts sind harte
  Abhängigkeit.
- **`lib/services/export_service.dart`** – `exportPayrollPdf`,
  `exportPersonnelCostPdf`, `exportPersonnelCostCsv` / `buildPersonnelCostCsv`
  (UTF-8-BOM, `;`-Delimiter für deutsches Excel).

---

## 9. Bewusste Entscheidungen

- **Kundenaufträge nicht dupliziert.** Die App enthält bereits ein
  Warenwirtschafts-`CustomerOrder` (Sonderbestellungen). Der Personal-Bereich
  **liest** diese Daten read-only und gruppiert sie; die Verwaltung verbleibt in
  der Warenwirtschaft. So entsteht keine zweite, konkurrierende Auftragslogik.
- **Lohn = Richtwert.** Statt eine vorgeblich exakte (aber nicht zertifizierte)
  Lohnsteuer-Engine zu bauen, ist die Berechnung transparent, konfigurierbar und
  klar als Richtwert markiert.
- **Keine neuen Composite-Indizes** (`firestore.indexes.json` unverändert) – alle
  Queries sind index-frei lösbar.

---

## 10. Sicherheit (`firestore.rules`)

Zwei neue `match`-Blöcke unter `organizations/{orgId}/`:

```
match /workTasks/{taskId} {
  allow read: if sameOrg(orgId);
  allow create, update: if isAdmin() && sameOrg(orgId)
      && request.resource.data.orgId == orgId;
  allow delete: if isAdmin() && sameOrg(orgId);
}

// Lohndaten enthalten Vergütungsinformationen -> Lesen Admin-only.
match /payrollRecords/{recordId} {
  allow read: if isAdmin() && sameOrg(orgId);
  allow create, update: if isAdmin() && sameOrg(orgId)
      && request.resource.data.orgId == orgId;
  allow delete: if isAdmin() && sameOrg(orgId);
}
```

> **Hinweis lokale Persistenz:** Lohndaten (Cents) liegen – wie Arbeitsverträge –
> als Klartext-JSON in SharedPreferences (Hybrid spiegelt lokal). Gleiches
> Restrisiko wie bei `employmentContracts`; akzeptiert für das Bedrohungsmodell
> „zwei Läden, eigenes Gerät".

---

## 11. Tests

Alle Tests halten die App-Konventionen ein (`FakeFirebaseFirestore`,
`SharedPreferences.setMockInitialValues({})` + `DatabaseService.resetCachedPrefs()`,
`initializeDateFormatting('de_DE')`, zweifaches `Future.delayed(Duration.zero)`
nach Moduswechsel).

| Datei | Inhalt |
|---|---|
| `test/work_task_test.dart` | Roundtrip beider Formate, Enums, `isOverdue`, `clearX` |
| `test/payroll_record_test.dart` | Roundtrip, deterministische Doc-ID, Enums, Summen |
| `test/payroll_calculator_test.dart` | Exakte Werte (Klasse I), Netto-/AG-Invarianten, Klasse V > I, Soli + BBG-Deckelung, Minijob, Midijob, Kirchensteuer (9 %/8 %/aus) |
| `test/personal_provider_test.dart` | Lokales CRUD + Persistenz, Lohn-Upsert pro Monat, Admin-Gate, Cloud-Stream + Abwesenheits-Aggregation |
| `test/personal_screen_test.dart` | Tabs sichtbar, Richtwert-Hinweis im Lohn-Tab, „Kein Zugriff" für Nicht-Admins |
| `test/app_nav_menu_test.dart` | „Personal" sichtbar für Admins / verborgen für Mitarbeiter; `onOpenPersonal`-Callback |

---

## 12. Lokal ausprobieren

```bash
flutter run --dart-define=APP_DISABLE_AUTH=true
# Login als Admin: admin@demo.local / demo1234
# Menü (oben rechts/links) → Verwaltung → Personal
```

Anschließend: Aufgabe/Kundenauftrag ansehen, Lohn-Richtwert berechnen und als PDF
exportieren, Personalkosten als PDF/CSV exportieren, Statistik-Charts prüfen.

Quality-Gates:

```bash
flutter analyze   # sauber
flutter test      # Personal-Tests grün
```

---

## 13. Dateiübersicht

**Neu**

```
lib/models/work_task.dart
lib/models/payroll_record.dart
lib/models/payroll_settings.dart
lib/core/payroll_calculator.dart
lib/core/personnel_cost.dart
lib/providers/personal_provider.dart
lib/screens/personal_screen.dart
test/work_task_test.dart
test/payroll_record_test.dart
test/payroll_calculator_test.dart
test/personal_provider_test.dart
test/personal_screen_test.dart
```

**Geändert**

```
lib/main.dart                      (PersonalProvider in die Provider-Kette)
lib/services/firestore_service.dart(Collections + Queries)
lib/services/database_service.dart (lokale Persistenz)
lib/services/pdf_service.dart      (Lohn-/Kosten-PDF)
lib/services/export_service.dart   (Lohn-PDF, Kosten-PDF/CSV)
lib/widgets/app_nav_menu.dart      (Menüeintrag „Personal")
lib/screens/home_screen.dart       (Callback + Navigation)
firestore.rules                    (workTasks, payrollRecords)
```
