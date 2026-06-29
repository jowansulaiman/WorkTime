# Plan: Zeitwirtschaft „genau 1:1 wie AllTec" (adaptiert auf WorkTime)

> **Auftrag (Nutzer, 2026-06-24):** Die Zeitwirtschaft soll **genau 1:1 wie in AllTec**
> sein, angepasst auf uns (Einzelhandel, zwei Läden in Kiel). Geforderte Bereiche:
> **Kommen und Gehen · Zeiterfassungen · Stundenkonto · Abwesenheiten · Mein
> Monatsabschluss · Mitarbeiterabschluss · Lohnlauf.**
>
> **Quelle:** Schwester-App **AllTec** (`/Users/jowan/Documents/dev/AllTec`,
> `lib/features/time_tracking/`, ~25 kLOC, Flutter/Clean-Arch/bloc/freezed). AllTec
> ist seinerseits ein Flutter-Nachbau des IDA-Zeitmodells („analog IDA"-Kommentare) —
> also eine **näher an WorkTime liegende** Vorlage als das rohe IDA-Ökosystem.

## 0. Vier Leitentscheidungen (Nutzer, 2026-06-24) — ZWINGEND

| # | Frage | Entscheidung |
|---|---|---|
| **L1** | Was heißt „1:1"? | **Screens/Workflow 1:1, WorkTimes Rechenkerne behalten.** AllTecs 8 Screens + Status-Workflow + Monatsabschluss + Lohnlauf werden 1:1 nachgebaut — aber auf WorkTimes vorhandenen, deutsch-rechtlich präziseren Engines. AllTecs `HourAccountService`/`GermanTaxService`/`VacationService` werden **nicht** portiert (WorkTime ist vollständiger). |
| **L2** | Self-Service? | **Rollen-adaptiv wie AllTec.** Mitarbeiter: eigenes Kommen/Gehen, eigene Zeiterfassung, eigenes Stundenkonto, eigene Abwesenheiten, „Mein Monatsabschluss". Admin zusätzlich: Mitarbeiterabschluss-Hub + Lohnlauf. → `firestore.rules` bekommen **self-read** auf eigene Sollzeit/Stundenkonto/Lohn. |
| **L3** | Navigation? | **Eigener „Zeitwirtschaft"-Hub** als Section-Route, Kachel-Hub zu den 8 Screens; Kommen/Gehen zusätzlich als **FAB**. Kein neuer Bottom-Tab — fügt sich ins bestehende Hub-Muster (Warenwirtschaft/Team). Anker: der **bereits existierende** `ShellTab.time` (`/zeit`). |
| **L4** | Stempel-Tiefe? | **Persistente Stempel-Sessions + Freigabe.** Neue `ClockEntry`-Buchung (offen→abgeschlossen), org-weite „Wer ist eingestempelt"-Sicht, Status-Workflow (Entwurf/eingereicht/genehmigt) + Änderungsantrag auf Zeiteinträgen. |

## 1. Architektur-Leitplanken (aus CLAUDE.md, ZWINGEND)

- **Domänenmodell/Logik/UX von AllTec übernehmen, NICHT die Technik.** AllTec ist
  bloc/freezed/GoRouter/Hive/get_it. WorkTime bleibt **provider (ChangeNotifier),
  Hand-Dual-Serialisierung (kein codegen/freezed), Firestore + SharedPreferences, 3
  Speichermodi, Spark-frugal, alles `de_DE`** (jedes `DateFormat('…','de_DE')`), Geld
  als `int` Cent (`Money`), UI nur `lib/ui` Signal-Teal + Material 3, Statusfarben via
  `Theme.of(context).appColors`.
- **Zwei-Serialisierungs-Regel** für jedes neue Modell: `toFirestoreMap()`/
  `fromFirestore(id,map)` (camelCase/Timestamp, Doc-ID separat) **und** `toMap()`/
  `fromMap(map)` (snake_case/ISO-String, `id` im Map). `copyWith` + `clearX`-Flag für
  nullable. Parser tolerant via `firestore_num_parser.dart` + `FirestoreDateParser`.
  Enums via `.value`→snake_case + `fromValue`-Default (wirft nie) + deutsches `label`.
- **Callable-Payload = immer `toMap()` (snake_case).** Stempeln (`clockIn`/`clockOut`)
  läuft über Cloud Functions (validierter Pfad); Templates/Stammdaten direkt.
- **Compliance-Spiegel:** jede Zeit-/Pausen-/Höchstarbeitszeit-Regel synchron in
  `compliance_service.dart` UND `functions/index.js`. AllTecs Schwellen sind **identisch**
  zu WorkTimes (Pause 30@360 / 45@540, max 600/Tag, Ruhe 660, Nacht-Tiefen) → kein Drift.
- **Audit:** jeder fachliche Mutator loggt `_audit?.call(action:, entityType:, entityId:,
  summary:)` nur auf Erfolgs-Pfad (jeder Storage-Zweig), deutsche Summaries.
- **Provider lazy:** Cloud-Repo nie im Konstruktor auflösen ([[provider-lazy-cloud-repo]]).
- **Hybrid-Spiegelung je Collection** (userContent ja, Stammdaten nein) explizit, s. §6.

## 2. Quell→Ziel-Mapping (AllTec-Konzept → WorkTime-Umsetzung)

| AllTec | WorkTime-Umsetzung | Hinweis |
|---|---|---|
| `ClockEntry` (Stempel-Session) | **NEU** `lib/models/clock_entry.dart` | persistent, ersetzt WorkProvider-Ephemeral-State |
| `ClockService` (auto-Pause, force-close, Klärung) | **NEU** `lib/core/clock_service.dart` (pure) | Schwellen = AllTec = ArbZG |
| `TimeEntry` (status draft/submitted/approved/rejected) | **bestehendes `WorkEntry`** + neues Feld `status` + `aenderungsantrag` | Kopplung #1, abwärtskompatibel (Default `approved`) |
| `TimeEntryComplianceService` | **bestehendes `compliance_service.dart`** | nur Approval-Gate ergänzen |
| `Absence` (19 Typen, unified) | **bestehender `AbsenceRequest`-Stack** (12 Typen + `abwesenheit_matrix` + `urlaub_calculator`) | WorkTime ist **reicher** (§5/§7/§9 BUrlG); KEIN neues Absence-Modell |
| `VacationService` / `SickLeaveService` | **`urlaub_calculator.dart`** + neue dünne Krank-Helper (AU ≥3 Tage, 15 %-Warnung) | AU-/Quoten-Regeln aus AllTec ergänzen |
| `HourAccount` (persistent monatlich) | **NEU** `lib/models/zeitkonto_snapshot.dart` (im IDA-Plan vorgespect) | gespeist von `zeitkonto_calculator` + `abwesenheit_matrix` |
| `HourAccountService` (carryover, §3-Check) | **`zeitkonto_calculator.dart`** + neue `zeitkonto_konto_service.dart` (Übertrag/Lock/Auszahlung) | |
| `MonthClosingService` (validate/lock) | **NEU** `lib/core/monatsabschluss_service.dart` (pure) | Status-Maschine 1:1 |
| `Payroll`/`PayrollService`/`GermanTaxService` | **bestehende** `payroll_record`/`payroll_calculator`/`german_tax`/`lohn_herleitung`/`sfn_zuschlag` | nur Batch-**Run-Page** + Close→Draft-Generierung neu |
| `payrolls`-Collection | **bestehende `payrollRecords`** | Doc-ID identisch `{userId}-{jahr}-{monat}` |
| `Activity`/`activities`, `costCenterId`, `projectRef` | **weglassen** (E2 IDA = Standort=Kostenstelle) | `WorkEntry.siteId` genügt |

## 3. Was wird WEGGELASSEN (Bildungsträger-spezifisch, passt nicht auf Einzelhandel)

- **Teilnehmer/Participant** (`ClockEntry.participantId`, `actor=participant`,
  `ClockApprovalStatus`, Dozenten-Genehmigung, `participant_checkin_page`,
  `instructor_approval_page`) → entfällt; `ClockEntry` kennt nur **Mitarbeiter**.
- **Klasse/Kurs** (`classId`/`className`, Pflicht bei Kommen) → entfällt; optional
  stattdessen `siteId` (welcher Laden). **Standort-Auswahl beim Einstempeln** (zwei Läden!).
- **Bildungs-spezifische Abwesenheitsarten** (`bildungsurlaub`, `berufsschule`,
  `weiterbildung`) und **TimeEntryType** `training`/`travel` (`Unterricht`/`Fahrt`) →
  weglassen. WorkTimes `AbsenceType` (vacation, sickness, childSick, specialLeave,
  unpaidLeave, timeOff, parentalLeave, maternity, shortTimeWork, …) bleibt maßgeblich.
- **EPC-/SEPA-QR** (`epc_qr_service`, `auszahlung_modal` QR-Button) → **optional/zurückgestellt**
  (nett, aber nicht Kern; nur falls IBAN am Profil vorhanden — Phase 2).

## 4. Ziel-Datenmodell (neue Modelle)

> Dual-Serialize-Pflicht (§1). Geld int Cent. Datum normalisiert (12:00 lokal wie `WorkEntry`).

### 4.1 `lib/models/clock_entry.dart` — `ClockEntry` (NEU)
- **Collection:** `organizations/{orgId}/clockEntries` · org-skopiert · self-write own
  ODER admin · **read own + admin** (Selbst-Sicht erlaubt) · Hybrid: **gespiegelt** (userContent).
- **Doc-ID:** offene Buchung **deterministisch** `{userId}-open` (create-only, Overwrite per
  Rules verboten) → verhindert Doppel-Stempeln bei zwei Geräten (IDA-Audit H7); beim
  Ausstempeln auf Auto-ID umschreiben/abschließen. (Alternativ `clockIn` server in `runTransaction`.)
- Felder: `id, orgId, userId, userName?, siteId?, siteName?, kommen: DateTime,
  gehen: DateTime?` (null=offen), `pauseMinuten: int`, `nettoStundenMinutes: int`
  (bei Abschluss gesetzt), `status: ClockStatus` (`ongoing/completed/klaerung/deaktiviert`),
  `klaerung: bool`, `anmerkung: String?`, `manuellErfasst: bool`, `ipKommen/ipGehen: String?`,
  `workEntryId: String?` (verknüpfter erzeugter `WorkEntry`), `createdByUid, createdAt, updatedAt`.
- `ongoing` ist **Getter** `gehen == null` (kein redundantes Flag).
- **Datums-Ausnahme** wie `WorkEntry`: `kommen` Pflicht (`FormatException`).

### 4.2 `lib/models/zeitkonto_snapshot.dart` — `ZeitkontoSnapshot` (NEU; = AllTec `HourAccount`)
- **Collection:** `organizations/{orgId}/zeitkontoSnapshots` · org-skopiert · read own + admin ·
  write admin/Close-Pfad · Hybrid: **nicht** gespiegelt (nur beim Abschluss geschrieben).
- **Doc-ID:** deterministisch `{userId}-{jahr}-{mm}` (Upsert). Index `userId`+`jahr`+`monat`.
- Felder (Minuten als `int`, nicht `double`): `id, orgId, userId, jahr, monat,
  sollMinutes, istMinutes, ueberstundenMinutes` (=Ist−Soll), `ausgezahltMinutes,
  uebertragMinutes` (Saldo Vormonat), `saldoMinutes` (=Übertrag+Überstunden−Ausgezahlt),
  `urlaubstageGesamt, urlaubstageGenommen, urlaubstageRest: double` (aus `urlaub_calculator`),
  `kranktage: int`, `abgeschlossen: bool` (=AllTec `isLocked`), `abgeschlossenVon: String?`,
  `abgeschlossenAm: DateTime?`, `createdByUid, createdAt, updatedAt`.
  > Urlaub bleibt **kalenderjahr**-bezogen (Quelle `urlaub_calculator`/`UrlaubskontoJahr`),
  > nur als Anzeige in den Monats-Snapshot gespiegelt — Periodizitäten nicht mischen.

### 4.3 `lib/models/lohnstunden.dart` — `Lohnstunden` (NEU, optional bei Auszahlung)
- **Collection:** `organizations/{orgId}/lohnstunden` · admin-only. **Doc-ID:** `{userId}-{jahr}-{mm}`.
- Felder: `ausgezahltMinutes, bemerkung, Meta`. Reduziert das Stundenkonto, Audit-geloggt.
  (Kann in M4 in `ZeitkontoSnapshot.ausgezahltMinutes` integriert bleiben; eigenes Modell nur
  falls Historie mehrerer Auszahlungen je Monat nötig.)

### 4.4 `WorkEntry`-Erweiterung (Kopplung #1 — 6 Stellen + `functions/index.js`)
- Neues Feld `status: WorkEntryStatus` (`draft/submitted/approved/rejected`), Default
  **`approved`** (Altdaten + heutige Direkterfassung bleiben gültig). `approvedByUid: String?`,
  `approvedAt: DateTime?`. Eingebetteter `aenderungsantrag: WorkEntryAenderungsantrag?`
  (`art: neu/aenderung/deaktivieren`, `antragStart/-Ende: DateTime?`, `begruendung: String`,
  `requestedByUid/At`, `entschiedenVon/Am`, `abgelehnt: bool`, `ablehnungsgrund: String?`).
- `sourceClockEntryId: String?` (Duplikat-Vermeidung, Verknüpfung zur Stempel-Session).
- 6 Stellen: `toFirestoreMap`/`fromFirestore`/`toMap`/`fromMap`/`copyWith` (+`clearAenderungsantrag`)
  + snake_case-Parse/Serialize in `parseWorkEntry`/Serializer in `functions/index.js`.

## 5. Screens (1:1 AllTec, im neuen Hub)

> Reuse-First: `lib/ui`-Komponenten, `home_screen`-private Widgets ggf. nach `lib/widgets/` heben.
> Tabellen analog AllTec (`DataTable`), Statusfarben via `appColors`. Modals via
> `showModalBottomSheet(showDragHandle:true, isScrollControlled:true, useSafeArea:true)`.

| Screen | Route | Rolle | Inhalt (1:1 AllTec) |
|---|---|---|---|
| **Hub** (rollen-adaptiv) | `/zeit/uebersicht` | alle | KPI-Reihe (Ist/Soll, Überstunden, Saldo, Resturlaub) + Kachel-Grid auf die 8 Ziele; Admin sieht zusätzlich Mitarbeiterabschluss/Lohnlauf-Kacheln |
| **Kommen / Gehen** | `/zeit/stempeln` | alle | Timer-Card (läuft, „Eingestempelt seit HH:mm"), Warnbanner (>10h / Vortag), „Wer ist eingestempelt"-Karte (org-weit), Monatsliste; **FAB** grün „Kommen" (Laden-Auswahl bei 2 Läden) / rot „Gehen · {Laden}" → Ausstempeln-Sheet (Pause-Default 30, Anmerkung, >10h-Ausnahme-Hinweis) |
| **Zeiterfassung** | `/zeit/erfassung` | alle (eigene) / admin (alle) | 3 Tabs **Arbeitszeiten / Urlaub / Krankmeldungen**; Monatsnav, Filter „Nur Klärung"; DataTable (Tag/Kommen/Gehen/Pause/Stunden/Typ/Status/Klärung/Anmerkung/Optionen); Summenzeile; „Neue Arbeitszeit"-Modal; **Änderungsantrag**-Modal (Neu/Änderung/Deaktivieren + Begründung-Vorlagen „Vergessen/Fehlbuchung/Absprache"); Genehmigen/Ablehnen (Manager) |
| **Stundenkonto** | `/zeit/stundenkonto` | alle (eigene) | `HourAccountSummaryCard` (Soll/Ist/Überstunden/Saldo/Übertrag/Ausbezahlt), Urlaub-/Krank-Karten, Jahres-Übersichtstabelle (12 Monate, Lock-Icon), **§3-ArbZG-48h-Warnung**, „Monatsabschluss durchführen"-Button bzw. Chip „abgeschlossen am…", **Auszahlung-anpassen**-Modal |
| **Abwesenheiten** | `/zeit/abwesenheiten` | admin (org-weit), MA (eigene) | org-weite Liste (Mitarbeiter/Grund/Zeitraum/Arbeitstage/Status/AU/Optionen), Antrags-Buttons (Krankmeldung/Urlaubsantrag/Zeitausgleich/…), Filter, AU-Nachweis-Shield (≥3 Tage rot), Genehmigen/Ablehnen — **reuse `showAbsenceRequestSheet` + `AbsenceRequest`** |
| **Abwesenheitskalender** | `/zeit/abwesenheiten/kalender` | admin | Monatskalender Mitarbeiter×Tage, farbcodiert je Typ, Laden-Filter |
| **Mein Monatsabschluss** | `/zeit/monatsabschluss` | MA (eigene) | 12-Monats-Übersicht eigenes Konto; Status-Badges (Laufend/Bereit/Abgeschlossen/Vormonat offen/Klärung offen); „Monat abschließen"/„zurücknehmen"; Auszahlung |
| **Mitarbeiterabschluss** (Admin-Hub) | `/zeit/mitarbeiterabschluss` | admin | alle aktiven MA eines Monats; KPI (Mitarbeiter/Offen/Abgeschlossen/Lohnabrechnungen x/y); Filter (Nur offene/abgeschlossene/mit Warnungen + Suche); pro MA: Status, Ist/Soll/Überstunden, „Detail/Abschließen/Zurücknehmen/Lohnabrechnung"; **Batch** „Alle abschließbaren schließen" + „Zum Lohnlauf" |
| → **Detail** | `/zeit/mitarbeiterabschluss/:userId` | admin | MA-Karte (Stammdaten/Steuer/IBAN) + Stundenkonto-Summary + **Lohnabrechnung-Vorschau** (Bezüge/Abzüge-Tabellen) |
| **Lohnlauf** | `/zeit/lohnlauf` | admin | Batch-Monatslauf: KPI (Mitarbeiter/Brutto/Abzüge/Netto), DataTable (Steuerklasse/Brutto/Netto/Status/Aktionen), Statuschips, „Finalisieren"/„Alle Entwürfe finalisieren", PDF, „Zum Monatsabschluss" — **reuse Payroll-Engines + `finalizeAllDrafts` + Journal-Poster** |

## 6. Firestore-Rules & Hybrid-Spiegelung (Kopplung #6)

| Collection | Klasse | Read | Write | Hybrid-Spiegel |
|---|---|---|---|---|
| `clockEntries` | userContent | own + admin | own (self) + admin; offene Buchung create-only `{userId}-open`, kein Overwrite | **ja** |
| `workEntries` (best.) | userContent | own + admin | own + permission/admin (unverändert) | ja (unverändert) |
| `zeitkontoSnapshots` | abgeleitet | **own** + admin | admin/Close-Pfad | nein |
| `lohnstunden` | Stammdaten | own + admin | admin | nein |
| `payrollRecords` (best.) | Stammdaten | **own (NEU self-read) + admin** | admin (unverändert) | nein |
| `sollzeitProfiles` (best.) | Stammdaten | **own (NEU self-read) + admin** | admin (unverändert) | nein |
| `absenceRequests` (best.) | userContent | unverändert (own + reviewer) | unverändert | ja |

- **Self-read-Erweiterung** (L2): `payrollRecords`, `sollzeitProfiles`, `zeitkontoSnapshots`,
  `clockEntries`, `lohnstunden` bekommen `… || isOwnEmployee(resource.data.userId)`. Doc-IDs
  tragen `userId` → sauberes Prädikat (Muster wie `workEntries`/`absenceRequests`).
- **Footgun:** neue PersonalProvider-/ZeitwirtschaftProvider-Collections MÜSSEN in
  `cacheCloudStateLocally` + `syncLocalStateToCloud` (Speichermodus-Migration) ergänzt werden.
- **Deploy vor Cloud-Nutzung:** `firebase deploy --only firestore:rules` (+ ggf. `:indexes`).

## 7. Provider & Bootstrap

- **Neuer `ZeitwirtschaftProvider`** (`lib/providers/`) — bündelt `clockEntries` +
  `zeitkontoSnapshots` + Monatsabschluss-Orchestrierung; löst Cloud-Repo **lazy** auf.
  Reuse: liest `WorkEntry` über `WorkProvider`, Abwesenheiten über `ScheduleProvider`/
  `PersonalProvider`, Lohn über `PersonalProvider`. Vermeidet PersonalProvider-Bloat (IDA-§0-LOW).
- **Einfügereihenfolge `main.dart`** (Kopplung #4): **nach** Personal (braucht Auth/Team/
  Storage/Audit + lebende `WorkProvider`/`PersonalProvider`-Referenzen analog
  `WorkProvider.updateScheduleProvider`). `setAuditSink` verdrahten.
- Stempeln über Callables `clockIn`/`clockOut`/`upsertClockEntry` in `functions/index.js`
  (Region `europe-west3`, `enforceAppCheck` konsistent zu Bestand), Compliance-Re-Validierung;
  Batch-Limit 50. **Kopplung #8** (Region) beachten.

## 8. Navigation (Kopplung #7)

- **Section-Route `/zeit/...`** über die Shell (Detail-/Editor-Sheets bleiben imperativ).
  Anker am bestehenden **`ShellTab.time` (`/zeit`)**: dessen Tab-Screen wird der **Hub**
  (`/zeit/uebersicht`), die 7 weiteren Screens sind `context.push(AppRoutes.zeit…)`.
- Neue `AppRoutes`-Konstanten (`zeitHub`, `zeitStempeln`, `zeitErfassung`, `zeitStundenkonto`,
  `zeitAbwesenheiten`, `zeitAbwesenheitenKalender`, `zeitMonatsabschluss`,
  `zeitMitarbeiterabschluss`, `zeitLohnlauf`) + `_sectionRoute`-Einträge + Permission im
  Redirect (`_isLocationAllowed`) + `route_permissions.dart` (rollen-adaptiv: MA-Routen vs
  Admin-Routen Mitarbeiterabschluss/Lohnlauf).
- **FAB** Kommen/Gehen: im Hub + ggf. global im `/zeit`-Tab (heroTag `clock_fab`).

## 9. Meilensteine (Risiko-/Wert-orientiert)

> Jeder Meilenstein endet mit grünem `flutter analyze` + `flutter test` + adversarialem
> Multi-Linsen-Review (Codebase-Fit · dt. Arbeits-/Lohnrecht · Security/Rules/Spark · Tests).

- ✅ **M1 — Gerüst & Hub (erledigt 2026-06-25).** `ZeitwirtschaftHubScreen` ist jetzt der
  `/zeit`-Tab-Inhalt (rollen-adaptiv: KPI-Reihe Soll/Ist + Überstunden aus `WorkProvider` +
  geplanten Schichten, read-only; Kachel-Grid auf die 8 Bereiche, Admin-Kacheln gegated). Die
  frühere Monats-Zeiterfassung lebt als öffentliche `ZeiterfassungScreen` unter
  `AppRoutes.zeitErfassung` (Wrapper um den library-privaten `_TimeTrackingTab`). 8 neue
  `AppRoutes.zeit*`-Konstanten + `_sectionRoute`-Einträge; die 7 noch nicht gebauten Bereiche als
  `ZeitSectionPlaceholder` (M-Hinweis). `RoutePermissions`: MA-Routen `canViewTimeTracking`,
  `mitarbeiterabschluss`/`lohnlauf` `isAdmin`. Shell-FAB (Stempeluhr) bleibt auf dem Tab. Kein
  neues Modell, keine Rules-Änderung. **analyze sauber, 931 Tests grün** (3 neue Router-Tests:
  Sub-Route-Auflösung trotz `/zeit`-Präfix + Admin-Gating). Dateien: `lib/screens/zeitwirtschaft/
  zeitwirtschaft_hub_screen.dart`, `…/zeit_section_placeholder.dart`, Edits in
  `routing/shell_tab.dart`, `routing/app_router.dart`, `routing/route_permissions.dart`,
  `screens/home_screen.dart`, `screens/home_screen_tabs.dart`, `test/router_test.dart`.
- **M2 — Zeiterfassung + Status-Workflow.**
  - ✅ **M2a — Status-Fundament (erledigt 2026-06-25).** `WorkEntryStatus`
    (`draft/submitted/approved/rejected`, `.value`/`label`/`fromValue`-Default `approved`) +
    Felder `status`/`approvedByUid`/`approvedAt`/`sourceClockEntryId` an `WorkEntry` — alle 6
    Serialisierungs-Stellen + Spiegel in `functions/index.js` (`normalizeWorkEntryStatus`,
    parse/toFirestore/fromFirestore). **Abwärtskompatibel** (fehlender Status → `approved`, Alt-/
    Direkteinträge zählen voll). **943 Tests grün** (7 neue Round-trip-/Default-/copyWith-Tests),
    analyze sauber, `node --check` ok. Noch ohne UI/Provider-Mutatoren.
  - ✅ **M2b — 3-Tab-Zeiterfassung (erledigt 2026-06-25).** Neue `ZeiterfassungScreen`
    (`lib/screens/zeitwirtschaft/zeiterfassung_screen.dart`) unter `AppRoutes.zeitErfassung`:
    Tabs **Arbeitszeiten** (eigene `WorkEntry`s des Monats als DataTable Tag/Kommen/Gehen/Pause/
    Stunden/**Status-Chip**/Optionen + Summenzeile + Filter „Nur Klärung" + „Neue Arbeitszeit"/
    Bearbeiten via `EntryFormScreen` + **Einreichen**) / **Urlaub** + **Krankmeldungen** (eigene
    `AbsenceRequest`s, Status-Chip, Antrag via `showAbsenceRequestSheet`). Neue `WorkProvider`-
    Mutatoren `submitWorkEntry`/`approveWorkEntry`/`rejectWorkEntry` + `_persistEntryStatus`
    (lokal/Cloud/Hybrid, Audit, **kein userId-Overwrite** → Manager genehmigt fremde Einträge).
    M1-Wrapper → `ZeitKalenderScreen` umbenannt (erhalten, aktuell unverlinkt). **948 Tests grün**
    (5 neue Mutator-Tests), analyze sauber, `node --check` ok.
    > **Bewusst nach M5 verschoben:** `submit` ist im Self-Service-Screen verdrahtet; **approve/
    > reject-UI** gehört in den org-weiten Mitarbeiterabschluss-Hub (M5, dort sieht der Manager
    > fremde Einträge — `WorkProvider.entries` ist self-gefiltert). **Änderungsantrag-Modal**
    > erst sinnvoll mit Monats-Lock (M5); bis dahin editieren Mitarbeiter direkt. Mutatoren
    > approve/reject existieren + getestet, warten nur auf die M5-UI.
- **M3 — Kommen/Gehen persistent.**
  - ✅ **M3a — Modell + Rechenkern (erledigt 2026-06-25).** `lib/models/clock_entry.dart`
    (`ClockEntry` + `ClockStatus` ongoing/completed/klaerung/deaktiviert; dual-serialisiert;
    `kommen` Pflicht/`FormatException`, `gehen` nullable, präzise Timestamps ohne Mittag-Norm;
    `createdAt`-Guard `if(createdAt==null)`) + `lib/core/clock_service.dart` (pure: `requiredBreakMinutes`
    ArbZG §4 = compliance-Schwellen, `netMinutes`, `effectivePauseMinutes` Auto-Pflichtpause,
    `runningMinutes`, `needsForceClose` >10 h, `needsClarification` Vortag). **972 Tests grün**
    (24 neu), analyze sauber. **Designentscheid vs. §4.1:** `status` ist **autoritativ** (treibt
    die org-weite „wer ist eingestempelt"-Abfrage `where status==ongoing`); `isOngoing` liest nur
    `status`, KEIN `gehen==null`-Zweitsignal. Noch ohne Provider/Cloud/UI.
  - ✅ **M3b-1 — Persistenz-Schicht (erledigt 2026-06-25).** Neuer `ZeitwirtschaftProvider`
    (`lib/providers/zeitwirtschaft_provider.dart`, lazy, 3 Speichermodi, Audit, cache/sync) mit
    `clockIn`/`clockOut` (Auto-Pflichtpause + Netto + Klärung via `ClockService`), `openEntry`/
    `isClockedIn`/`runningMinutes`. `clockEntries`-Collection verdrahtet: `FirestoreService`
    (`saveClockEntry`/`deleteClockEntry`/`watchOpenClockEntry` — 2 Equality-Filter, kein Index),
    `DatabaseService` (`clock_entries`-Key org-skopiert + load/save + `_orgScopedCollectionKeys`),
    `main.dart` (Proxy3 nach Personal), `firestore.rules` (`clockEntries`-Block: MA eigene,
    Manager org-weit, Löschen admin-only). **Additiv** — der bestehende `WorkProvider`-Clock bleibt
    unangetastet. **978 Tests grün** (6 neue), analyze sauber. **Deploy nötig:**
    `firebase deploy --only firestore:rules`.
  - ✅ **M3b-2 — Stempel-UI (erledigt 2026-06-25).** `StempelScreen`
    (`lib/screens/zeitwirtschaft/stempel_screen.dart`) unter `/zeit/stempeln`: Timer-Karte mit
    Live-Ticker (30 s) + >10 h-/Vortag-Warnbanner, „Wer ist eingestempelt"-Karte (Manager, aus
    `watchOngoingClockEntries`), Monatsliste (eigene, `getClockEntriesInRange` + neuer
    Composite-Index `clockEntries(userId,kommen)`) + Monatsnavigation, **FAB** grün „Kommen"/rot
    „Gehen · {Laden}" mit **Laden-Auswahl-Sheet** (2 Läden) + Ausstempeln-Sheet (Pause/Anmerkung).
    Provider erweitert: `ongoingEntries` (Manager-gegated Stream), `monthEntries`/`selectMonth`/
    `_loadMonthEntries` (refresht bei clockIn/out). Router-Harness um `ZeitwirtschaftProvider`
    ergänzt. **980 Tests grün** (2 neue), analyze sauber. **Deploy nötig:**
    `firebase deploy --only firestore:rules,firestore:indexes`.
  - ✅ **M3c (Teil b) — WorkEntry-Erzeugung (erledigt 2026-06-25).** Poster-Seam
    `ZeitwirtschaftProvider.setWorkEntryPoster` (in `main.dart` mit `WorkProvider.addEntry`
    verdrahtet, Muster Finance→Personal). Sauberes Ausstempeln (status `completed`, **nicht**
    Klärung) erzeugt `WorkEntry(status: submitted, sourceClockEntryId, category 'stempel')` →
    gestempelte Zeit fließt ins Stundenkonto/Lohn. **Best-effort** (Compliance-Fehler bricht das
    bereits gespeicherte Ausstempeln nicht ab). **983 Tests grün** (3 neue), analyze sauber.
  - ⏳ **M3c (Teil a) — Clock-UI-Migration (offen, bewusst separat).** Home-FAB/Employee-Dashboard
    vom alten ephemeren `WorkProvider`-Clock auf `ZeitwirtschaftProvider` umstellen (heute
    koexistieren zwei Clocks: Home = alt, `/zeit/stempeln` = neu). Fasst die gut getestete
    Shell-Infra an → eigener, vorsichtiger Schritt (ggf. nach M4/M5). Später (M7): Callable-Härtung
    + `{userId}-open`-Concurrency.
- **M4 — Stundenkonto persistent.**
  - ✅ **M4a — Modell + Builder (erledigt 2026-06-25).** `lib/models/zeitkonto_snapshot.dart`
    (`ZeitkontoSnapshot` = AllTec `HourAccount`: Soll/Ist/Überstunden/Übertrag/Auszahlung/Saldo +
    Urlaub-Spiegel + Kranktage + `abgeschlossen`-Lock; dual-serial.; Doc-ID `buildId({userId}-{jahr}-{mm})`;
    `createdAt`-Guard) + pure `lib/core/zeitkonto_snapshot_builder.dart`: `buildZeitkontoSnapshot`
    (erweitert `computeZeitkonto` um **Abwesenheits-Anrechnung ins Ist** via `abwesenheitsMatrix`
    `alsSollAngerechnet`, **Übertrag** aus Vormonats-Snapshot, **Auszahlung**, kumulierten **Saldo**),
    `anrechenbareAbwesenheitsMinutes` (Werktag-genau, Halbtag), `krankTageImMonat`. **994 Tests grün**
    (11 neue), analyze sauber.
  - ✅ **M4b — Persistenz + Stundenkonto-Screen (erledigt 2026-06-25).** `zeitkontoSnapshots`-Collection
    verdrahtet: `FirestoreService` (`saveZeitkontoSnapshot` Upsert via deterministische Doc-ID +
    `getZeitkontoSnapshotsForYear` = 2 Equality-Filter, kein Index), `DatabaseService`
    (`zeitkonto_snapshots`-Key org-skopiert + load/save + `_orgScopedCollectionKeys`),
    `firestore.rules` (Block: MA eigene read, Schreiben nur `canManageShifts`). `ZeitwirtschaftProvider`:
    `loadSnapshots(jahr)`/`yearSnapshots`/`snapshotFor` + `saveSnapshot` (für M5/Auszahlung) +
    Cache/Sync-Erweiterung. Screen `StundenkontoScreen` (`/zeit/stundenkonto`): Summary-Card
    (Soll/Ist/Überstunden/Saldo/Übertrag/Ausbezahlt, live via `buildZeitkontoSnapshot` aus
    Sollzeit+WorkEntries+Abwesenheiten), Jahres-Übersicht (12 Monate, Lock-Icon), **§3-48h-Warnung**
    (vereinfacht), degradierte Self-View ohne Sollzeit. **996 Tests grün** (2 neue), analyze sauber.
    **Bewusst deferred:** Auszahlung-Modal → M5 (Lohnstunden); volle MA-Self-View Soll → M7 (Self-Read).
    **Deploy:** `firebase deploy --only firestore:rules` (zeitkontoSnapshots-Block).
- ✅ **M5 — Monatsabschluss + Mitarbeiterabschluss (erledigt 2026-06-28).**
  - **M5a:** `lib/core/monatsabschluss_service.dart` (pure): `validate({snapshot, entries, vormonat, now})`
    → `MonatsabschlussValidation{canClose, errors, warnings}`. Blocker: bereits abgeschlossen · **Monat
    noch nicht vollständig vorbei** (nur vergangene Kalendermonate, `now` injiziert) · offene
    `draft/submitted`-Einträge · Vormonats-Snapshot existiert & nicht gesperrt (fehlt er ganz → kein
    Blocker, AllTec-konform). Warnungen: Ist=0 trotz Soll · >20 Kranktage. `applyLock/applyUnlock`.
  - **M5b:** `ZeitwirtschaftProvider.closeMonth` (validate → `_writeSnapshot` lock → Draft-Lohn
    best-effort **nur für Admins** via Seam `setPayrollDraftPoster`) / `reopenMonth` + org-weite
    Lese-Helfer `loadOrgWorkEntriesForMonth/-ApprovedAbsencesForMonth/-SnapshotsForMonth` (3
    Speichermodi). `PersonalProvider.buildDraftPayrollForMonth` (reuse `LohnHerleitung.grundlohnCents`
    + `PayrollCalculator.calculate` → Entwurfs-`PayrollRecord`, **auch M6 nutzt das**).
    `FirestoreService.getOrgZeitkontoSnapshotsForMonth` (2 Equality-Filter, kein Index). `main.dart`-Seam.
  - **M5c:** `monatsabschluss_screen.dart` — „Mein Monatsabschluss" (self, 12-Monats-Grid,
    abschließen/zurücknehmen **gegated auf `canManageShifts`**, da Snapshot-Writes managergebunden;
    reine MA sehen read-only Status). Januar-Vormonat cross-year via org-Loader.
  - **M5d:** `mitarbeiterabschluss_screen.dart` — Admin-Hub **org-weit**: KPIs, Filter
    (Suche/offen/abgeschlossen/Hinweise), je MA Live-Snapshot, **approve/reject** offener Einträge
    (`work.approveWorkEntry/rejectWorkEntry` — `WorkProvider.entries` ist self-gefiltert, daher hier
    org-weit), Abschließen/Zurücknehmen, **Auszahlung** (`ausgezahltMinutes` → Saldo neu), Batch-Close
    (mit Fehler-Summary). Close nur für **vollständig vergangene** Monate (`_isCompletedMonth`).
  - **Keine Rules/Index-Änderung in M5** — org-weite Manager-Reads (`workEntries`/`zeitkontoSnapshots`)
    in `firestore.rules` bereits offen; Sollzeit-Self-Read bleibt bewusst M7 (graceful degradation).
  - **1039 Tests grün** (+22), analyze sauber. Adversariales 4-Linsen-Review (Codebase-Fit · Lohnrecht ·
    Security/Rules/Spark · Tests, 28 Agenten) → 8 Funde behoben: createdAt-Cross-Contamination (userId-Guard),
    stale Einträge bei Close (frisch nachladen), laufender Monat nicht schließbar, Teamlead-Draft-Post
    nur-Admin, Self-Close-Defense-Guards, Batch-Close-Fehler-Summary, `_load`-try/finally, Januar-Vormonat
    cross-year. (Verworfen u.a.: „2 Equality-Filter brauchen Composite-Index" = falsch; Foreign-Approve-Gate
    = pre-existing & via Admin-only-Route unerreichbar.)
  - **Bewusst offen:** Detail-Route `/zeit/mitarbeiterabschluss/:userId` (Lohnabrechnung-Vorschau) → M6/M7
    (Lohn-Editor existiert bereits im Personal-Bereich); Auszahlung-EPC-QR (Phase 2).
- ✅ **M6 — Lohnlauf (erledigt 2026-06-28).** `lib/screens/zeitwirtschaft/lohnlauf_screen.dart`
  (`/zeit/lohnlauf`, admin-only): dedizierte **Batch-Run-Seite** eines Abrechnungsmonats. Summen-KPIs
  (Brutto/Abzüge/Netto/AG-Kosten, stornierte ausgenommen) + Statusverteilung; **„Alle Entwürfe freigeben"**
  (`PersonalProvider.finalizeAllDrafts` → H-A1-Personalkosten-Buchung); je Abrechnung Status-Menü
  (`setPayrollStatus`), „Gebucht"-Badge (`journalEntryId`), **PDF** (`ExportService.exportPayrollPdf` →
  `PdfService.generatePayrollReport`); „Zum Mitarbeiterabschluss". Default-Monat = **Vormonat** (zuletzt
  abschließbar). **Reine Reuse-Seite** über öffentliche APIs (kein Duplikat der Lohn-Engines; Einzel-
  Bearbeitung bleibt im Personal-Bereich). **1041 Tests grün** (+2 Widget-Tests Finalize-Flow, Router-Smoke
  aktualisiert), analyze sauber. Adversariales 2-Linsen-Review (7 Agenten) → 3 Funde behoben (KPI-Subtitle
  zählt nur aktive Abrechnungen, memberById-Lookup einmal, Monat im Summen-Titel); verworfen: Dialog-Pattern-
  Angleichung in `personal_screen` (out of scope). **Keine neue Collection/Rules/Index** (nutzt `payrollRecords`).
- **M7 — Rollen-Härtung & Rules-Deploy.**
  - ✅ **M7a — Self-Read (erledigt 2026-06-28).** `firestore.rules`: **Self-Read** auf `sollzeitProfiles`
    **und** `payrollRecords` (`resource.data.userId == request.auth.uid && canViewTimeTracking()`, Schreiben
    bleibt admin-only); `zeitkontoSnapshots` hatte Self-Read schon (M4). `FirestoreService.watchSollzeitProfilesForUser`
    (self-scoped, 1 Gleichheitsfilter, kein Index). `PersonalProvider`: Nicht-Admins laden im Cloud-Modus ihr
    **eigenes** Sollzeit-Profil (vor dem admin-only-Early-Return) → **hebt die degradierte „keine Sollzeit"-
    Self-View** in `StundenkontoScreen` (watch → rebuild) und `MonatsabschlussScreen` (liest Sollzeit zur
    Close-Zeit) auf. **1042 Tests grün** (+1 self-scoped-Load-Test), analyze sauber. **Deploy nötig** (neue
    Self-Read-Blöcke).
  - ⏳ **M7b — Callable-Härtung Stempeln (offen, bewusst separat).** clockIn/clockOut über Cloud Functions
    (validierter Pfad) + **`{userId}-open`-Concurrency** (deterministische Doc-ID, create-only gegen Doppel-
    Stempeln, IDA-Audit H7) — ändert das funktionierende M3-Direct-Write-Modell + ClockEntry-Persistenz (clockOut
    = copy-to-auto-id + delete), keine lokale Functions-Test-Infra, geringer Wert für 2-Läden-Setting. **App-Check
    bleibt bewusst AUS** (kein Callable `enforceAppCheck` — Aktivierung ohne konfigurierten App-Check-Provider
    bräche alle Callables in Dev/Demo; Go-Live-Härtung). Eigener vorsichtiger Schritt nach Nutzer-Entscheid.

## 10. „Wenn du X änderst" — neue Kopplungen dieses Plans

1. `WorkEntry`-Status → 6 Stellen + `parseWorkEntry`/Serializer in `functions/index.js`
   (Kopplung #1) + jede UI, die `WorkEntry` summiert, ignoriert `rejected`.
2. Neue Collections → `FirestoreService`-Getter, `DatabaseService`-Key (org-skopiert),
   `firestore.rules`, **cache/sync (Speichermodus-Migration)**, Hybrid-Spiegel-Entscheid (§6).
3. Stempel-Callables → Region (#8), Compliance-Re-Validierung, Batch-50, `enforceAppCheck`-Konsistenz.
4. `ZeitwirtschaftProvider` → `main.dart`-Kette **nach** Personal (#4), `setAuditSink`.
5. Neue `/zeit/*`-Routen → `AppRoutes` + `_sectionRoute` + `_isLocationAllowed` +
   `route_permissions.dart` (#7), rollen-adaptiv.
6. Abwesenheits-Anrechnung ins Ist (M4) berührt die bewusste „WorkEntry = einzige Ist-Quelle"-
   Entscheidung → über `abwesenheit_matrix.alsSollAngerechnet` additiv, **kein** Doppelzählen mit
   `ClockEntry` (Stempel erzeugt genau einen `WorkEntry`).

## 11. Tests (CLAUDE.md-Muster)

- Reine Kerne testbar offline: `clock_service` (auto-Pause/force-close/Klärung),
  `monatsabschluss_service` (validate/lock), `zeitkonto_konto_service` (Übertrag/Saldo),
  Snapshot-/ClockEntry-Round-Trip (beide Serialisierungen).
- Provider-Tests mit `FakeFirebaseFirestore` + `cloudFunctionInvoker` (clockIn/-out, Hybrid-Fallback,
  `-open`-Concurrency: zweiter clockIn auf stale State → genau eine offene Buchung).
- Compliance auf `.code` asserten; `FakeFirebaseFirestore` liefert Zahlen als `double`.
- Rules-Tests (self-read own, kein Fremd-read) falls `test_rules`-Harness vorhanden, sonst manuell.

---

**Stand 2026-06-25:** Plan erstellt nach Zwei-Workflow-Kartierung (AllTec `time_tracking` +
WorkTime-Ist) und 4 Nutzer-Leitentscheidungen (L1–L4). Verhältnis zum IDA-Plan
(`plan/ida-hr-zeit-uebernahme.md`): **dieser Plan ist die verbindliche Zeitwirtschaft-Vorlage**
(AllTec-UX 1:1). Bereits gebaute IDA-Engines (Sollzeit/Urlaub/Lohn/§3b/§39b) werden **wiederverwendet**,
nicht ersetzt; offene IDA-Reste (Monatsabschluss, Stempeln, Stundenkonto-Persistenz) werden hier
**AllTec-konform** umgesetzt.

**Stand 2026-06-28: M1–M6 + M7a fertig** (1042 Tests grün, analyze sauber, nichts committet). Damit sind
**alle 8 AllTec-Screens + Status-Workflow + Monatsabschluss + Lohnlauf gebaut**, und reguläre Mitarbeiter sehen
ihr eigenes Soll/Saldo (Self-Read). Offen: **M7b** (Callable-Härtung Stempeln + `{userId}-open` + App-Check —
bewusst separat, s.o.). **Deploy ausstehend vor Cloud-Nutzung** (gebündelt): `firebase deploy --only
firestore:rules,firestore:indexes` — Blöcke `clockEntries`/`zeitkontoSnapshots` (M3/M4) **+ neu M7a Self-Read auf
`sollzeitProfiles`/`payrollRecords`**, Index `clockEntries(userId,kommen)` (M3).

**Offene-Punkte-Abbau (2026-06-28):** ✅ **EFZG-42-Tage-Cap** (`anrechenbareAbwesenheitsMinutes`: `sickness` nur 42
Kalendertage ab Antragsbeginn, §3 EFZG; +3 Tests, lohnrechtlich reviewt). ✅ **Januar-Übertrag** (cross-year
`ZeitwirtschaftProvider.loadCarryover` self-scoped + robust gegen Race/Out-of-order; +2 Tests). ⏭️ **Detail-Route**
`/zeit/mitarbeiterabschluss/:userId` — vom Nutzer als redundant **übersprungen**. ⚠️ **Home-Clock-Migration (M3c-a)** —
Nutzer wählte „freie persistente Uhr"; FAB + V1/V2-Karten teils migriert (→ `/zeit/stempeln`), aber **PAUSIERT wegen
LIVE-Kollision** mit einer Parallel-Session, die `home_screen_tabs.dart` gleichzeitig editiert (AbsenceType-Refactor,
Tree gerade nicht kompilierbar); `home_dashboards_v2.dart`-Hero-Karte + Tot-Code-Reste offen → **nach Settling
reconcilen** (Details Memory `zeitwirtschaft-alltec-1zu1`). **Offen:** M7b Callable-Härtung, Auszahlung-EPC-QR (Phase 2).
