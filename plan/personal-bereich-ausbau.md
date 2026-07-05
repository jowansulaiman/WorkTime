# Personalbereich-Ausbau — digitale Personalakte, Dokumente, Echtzeit-Stempeln, Rollen

**Stand:** 2026-07-02 · **Status:** Planung (review-gehärtet, Ist-Analyse mit 7 parallelen Code-Lesern belegt) · **Priorität:** hoch
**Auftrag (Betreiber):** Personalbereich verbessern, ergänzen und konsolidieren. Heute verstreut über Teamverwaltung, Laden→Personal und Einstellungen (Stundensatz, Urlaubsanspruch). Kernanforderungen: (1) **alle Geräte synchron** — Einstempeln am Kiosk-Tablet sofort auf Web/iOS/Android sichtbar und umgekehrt; (2) **lückenlose Daten** für Gehaltsabrechnung und Monatsabschluss; (3) **Dokumenten-Upload** — Admin lädt pro Mitarbeiter hoch, Mitarbeiter sieht und lädt herunter; (4) **Rollen-/Sicherheitsmodell** — wer darf was sehen/bearbeiten; (5) UI/UX weder minimal noch überladen; (6) Schichtplan und Zeitwirtschaft mitdenken.

**Modell-Eignung der Arbeitspakete** (vom Betreiber vorgegeben):
- `Geeignet für: Fable 5` — schwierige Analyse, Architektur, komplexe Businesslogik, riskante Mehrdatei-Änderungen, Datenmodellierung, Entscheidungsfindung.
- `Geeignet für: Opus` — klar spezifizierte Implementierung, Tests, UI-Nacharbeiten, Refactors, Dokumentation, Review.
- `Geeignet für: Beide` — Design-Anteil von Fable 5, mechanische Umsetzung danach von Opus möglich.

## Umsetzungsstand (2026-07-03) — 1386 Flutter-Tests + 30 Functions-Tests grün, `flutter analyze` clean

**FERTIG:** PA-0 (Sicherheits-Fundament, review-gehärtet) · PA-1.3 (Quali-Gültigkeit) · PA-2.3 (Self-Read Akte) · PA-2.4 (Meine-Akte-Screen) · PA-3 (Dokumentenverwaltung, end-to-end) · PA-6.1 (Umlagen/Minijob verlustfrei + PDF) · PA-6.3-Teil (Lohnjournal-CSV-Export) · PA-7.1 (Lohnzettel-Selbstsicht) · PA-7.2 (Urlaubskonto-Selbstsicht) · PA-7.3-Teil (EmployeeStatus-Badge in Liste) · PA-7.4 (Lohn-freigegeben-Push) · PA-8.1-Teil (DSGVO-Aufbewahrungsfrist + Abgelaufen-Anzeige) · PA-8.3 (Server-Audit Kiosk/Stempel). — 1427 Tests grün.

**Status-Update 2026-07-05 (gegen Code verifiziert):**
- **PA-2.1/2.2 — ERLEDIGT durch `plan/personal-alltec-1zu1.md`** (überholt in besserer Form): `/personal/:id`-Route + `EmployeeDetailScreen` mit 9 Tabs + Deep-Link-Gate + Suche/Filter in der Liste. Globale Suche deep-linkt seit 05.07. auf `/personal/{uid}`. Nicht mehr aus diesem Plan zu bauen.
- **PA-1.1 — TEIL-FORTSCHRITT (05.07.):** Das Selbst-Editier-Feld „Urlaubstage" ist mit dem Einstellungs-Aufräumen entfernt (nur noch „Meine Akte"-Anzeige mit echtem `urlaubsReportFor`). WEITER OFFEN: Anzeige-Leser `settings.vacationDays` (home_screen-Chips :963/:3055, Team-Editor-Durchreiche team_management_screen:2317) + Default-Divergenz + Modellfeld-Deprecation.
- **PA-5 — TEIL-ASPEKT extern erledigt (ZV-3.2):** Mitarbeiter können abgeschlossene Einzel-Buchungen nicht mehr ändern (clockEntries-update nur noch `status=='ongoing'` self). Die **Monats-Festschreibung bleibt aber NICHT durchgesetzt** — `zeitkontoSnapshots.abgeschlossen` wird weiterhin von keinem Mutator/keiner Callable/keiner Rule geprüft.

**Umsetzung 2026-07-05 (zweite Welle, produktionsreif — 1572 Flutter-Tests + 65 Functions-Tests grün, analyze clean):**
- **PA-5 KOMPLETT — Monats-Festschreibung, dreifach durchgesetzt:** (1) Client-Guard `MonatsFestschreibung` (`lib/core/monats_festschreibung.dart`, fail-open offline, deutsche Meldung) in `WorkProvider._addEntry`/`deleteEntry`/`_persistEntryStatus` (deckt update/correct/submit/approve/reject; bei Monats-Verschiebung wird ALT+NEU geprüft) und `ZeitwirtschaftProvider.resolveKlaerung`/`dismissKlaerung`/`addManualClockEntry`; (2) Callable-Guard in `upsertWorkEntry`/`Batch` (`failed-precondition`, dedupliziert je Mitarbeiter-Monat; pure Spiegel `functions/monats_lock.js`, node-getestet — UTC-sicher via 12:00-Normalisierung); (3) Rules-Guard `workEntryMonatFrei` (exists()-sicher, zero-padded `buildId`-Nachbau, alt+neu bei update, tolerant gegen Alt-Docs; bewusst NUR workEntries — `kommen` kippt in UTC an der Monatsgrenze). `zeitkontoSnapshots`: gesperrte Snapshots nur noch admin-änderbar. **Abschluss-Blocker neu:** laufende (ongoing) Stempelung blockiert `closeMonth` (verhindert WorkEntry-Erzeugung in den gesperrten Monat an der Wurzel). **PA-5.2:** `reopenMonth` admin-only + Abrechnungssperre (freigegebener/bezahlter Lohn ⇒ erst stornieren; Lookup-Seam `setPayrollStatusLookup` → PersonalProvider in main.dart). 12 neue Tests (`monats_festschreibung_test.dart`).
- **PA-4.1 KOMPLETT — `{userId}-open`-Doppel-Stempel-Guard:** `FirestoreService.clockInOpen` (Transaktion, create-only-Semantik → zweiter clockIn wirft „Bereits eingestempelt") + `closeOpenClockEntry` (transaktional copy-to-final-ID + delete → open-ID wieder frei); Provider-clockIn/clockOut umgestellt (Local-Modus + hybrid-Offline-Fallback bewusst mit zufälliger ID → kein ID-Blockieren; Legacy-Buchungen schließen in place; `sourceClockEntryId` zeigt auf die ENDGÜLTIGE ID); Rules: `kommen`-Pin auf self-update (kein Overwrite-Doppelstempel per set) + self-delete NUR fürs eigene `{uid}-open`-Doc; `kioskClockPunch`: `create()` statt read-then-write (Race atomar zu, ALREADY_EXISTS idempotent) + out-Zweig transaktional (sonst bliebe die open-ID für immer belegt!). 5 neue Tests (`clock_open_guard_test.dart`, inkl. Cross-Device-Stream-Beweis + Legacy).
- **PA-7.3-Rest:** Offboarding-Checkliste im Verwalten-Tab (`_OffboardingCard`, erscheint bei nicht-laufendem Status/exitDate): Zugang deaktivieren (= bestehende isActive-Kopplung sperrt Login/Planung/Kiosk), Kiosk-PIN-Reset (neuer Client-Pfad `FirestoreService.resetKioskPin` + `PersonalProvider.resetKioskPinFor`, Server-Audit vorhanden), DSGVO-Aufbewahrungs-Hinweis.
- **PA-8.1-Rest:** Bulk-Löschung abgelaufener Dokumente (`_ExpiredRetentionBanner` in der Dokumenten-Karte, admin-getriggert mit Confirm, je Dokument Storage+Metadaten+Audit über `deleteDocument`).
- **PA-8.2:** Art.-15-Selbstauskunft als PDF (`PdfService.generateSelbstauskunft` + `exportSelbstauskunftPdf`, Download-Aktion in „Meine Akte"): Stammdaten (nur belegte Felder), Vertragseckdaten, Urlaubskonto, Lohnabrechnungen, Dokument-Metadaten.

**Dritte Welle 2026-07-05 (PA-4 KOMPLETT — 1572 Tests + 65 Functions grün):**
- **PA-4.4 (a–g, Aktivierungs-Vorbedingung erfüllt):** `_ClockTile` mit try/catch + „Keine Verbindung"-Meldung + Retry (busy-Reset im finally); `kioskEndSession` beim (Auto-)Logout via `KioskController.onSessionEnd`-Seam (best-effort, fire-and-forget); PIN-Pad 4–8 Ziffern mit OK-Taste (Auto-Submit@4 entfernt, mitwachsende Punkte); `persistenceEnabled:false` im Kiosk-Build (Datensparsamkeit auf dem geteilten Tablet); InventoryProvider überspringt `watchStockMovements` im Kiosk-Build (sonst Provider-Fehlerzustand nach PA-0.1-Deny); **`kioskRoster` lebt:** `onUserWrittenKioskRoster`-Trigger projiziert users→`kioskRoster/{uid}` (nur Name+aktiv, `role:kiosk` nie), Login-Liste lädt `getKioskRoster` mit TeamProvider-Fallback (Demo/Übergangsphase). **`role:'kiosk'` darf nach Deploy provisioniert werden.**
- **PA-4.5a/b:** „Jetzt im Dienst"-Karte im Admin-Heute-Tab (`_JetztImDienstCard`, aus `ongoingEntries`, selbst-versteckend, zeigt Kiosk-Quelle); `kioskPresence/{uid}`-Projektion via erweitertem `onClockEntryWritten`-Trigger (deckt Callable- UND Direct-Write, Review-Auflage; delete-korrekt dank {userId}-open-Eindeutigkeit) + Rules (read sameOrg/write false) + Kiosk-Board-Kachel „Im Dienst" (nur Vornamen, Kachel-Entscheidung #2).
- **PA-4.7:** Klärungs-Push an Manager (Flanke →`klaerung`, Typ `clock_klaerung`, Kanal `genehmigungen` = zeitkritisch) im selben Trigger; ZV-Klärung-gelöst-Push unverändert.
- **PA-4.6:** bereits durch ZV-1 (Reachability/Pending-Badge/Resume) abgedeckt — nicht doppelt gebaut.

**OFFEN (bewusst, je eigene fokussierte Session):** PA-4.2 (clockIn/clockOut-Callables — Go-Live-Schritt mit App-Check; Direct-Write ist transaktional gehärtet) · **PA-6.2** (nächste Session, Startbrief unten) · **PA-6.3-DATEV** (Lohn-Bewegungsdaten-Format) · **PA-1.1-Rest/PA-1.2** (migrations-gated: erst Vertrags-Seed-Migration für Bestandsdaten, dann Synthese-Entfernung — Betreiber-Timing) · **PA-9** (Deploy, Blaze/extern — Emulator-Matrix: Rules-Festschreibung [Monat ohne Snapshot frei], {userId}-open-Race, kioskClockPunch-Shape inkl. create()/Transaktion, kioskRoster-/Presence-Trigger, Storage-Matrix).

**Committet 2026-07-05:** `01b2911` (Kontakte-WIP, baut allein nicht — HEAD grün) + `43d18d6` (kompletter Personalbereich, 1572+65 Tests grün).

### PA-6.2 — Startbrief für die nächste Session (Lines-Verrechnung in die Bemessung)

**Ziel:** `PayrollRecord.lines` (§3b-Zuschläge, VwL, Zulagen, Einmalzahlungen, Überstunden-Auszahlung) wirken in Brutto/Steuer/SV statt nur informativ zu sein.
**Einstiegspunkte:** `lib/core/payroll_calculator.dart` (`calculate` — bekommt `List<PayrollLine> lines`), `lib/core/lohn_herleitung.dart` (produziert die Zeilen; `einmalzahlungSteuer` rechnet §39b Abs. 3 bereits SEPARAT — nicht doppeln!), `lib/models/payroll_record.dart` (`PayrollLine.steuerpflichtigCents`/`svPflichtigCents`-Getter existieren), `PersonalProvider.buildDraftPayrollForMonth` (:~540, ruft calculate).
**Fachregeln:** Steuer-Bemessung = Grundlohn + Σ `steuerpflichtigCents` der LAUFENDEN Bezüge (Einmalzahlungen NICHT — die laufen über `einmalzahlungSteuer`); SV-Bemessung = Grundlohn + Σ `svPflichtigCents` (auf BBG gedeckelt; Einmalzahlungen SV: bewusste Alt-Entscheidung „nicht gerechnet" — beibehalten oder als Betreiber-Frage klären); Auszahlungsbetrag = Netto + steuer- UND sv-freie Anteile; §3b bleibt netto-neutral korrekt, wenn die Anteile-Getter benutzt werden. Überstunden-Auszahlung (M-L-b): Line vom Typ Auszahlung reduziert zusätzlich `ZeitkontoSnapshot.ausgezahltMinutes`-Konto (Mechanik existiert am Snapshot).
**Pflicht: Golden-Zahlen-Tests** gegen handgerechnete Fälle (mind.: nur Grundlohn [Regression = heutiges Ergebnis], +§3b unter/über 25€/50€-Grenze, +steuer-sv-pflichtige Zulage, Minijob mit Zulage [Grenzprüfung 603€], Midijob-Übergang durch Zulage). Kopplung #2 beachten: `functions/index.js` rechnet Compliance, NICHT Lohn — kein Server-Spiegel nötig; aber `buildDraftPayrollForMonth` + `LohnlaufScreen`-Vorschau müssen dieselben Zahlen zeigen.

**NICHT DEPLOYT** — nichts committet/deployt; Arbeitsbaum mischt diese Änderungen mit fremder Kassen-/Scanner-WIP. Deploy-Reihenfolge-Auflagen: PA-0.2 (Client vor Rules), PA-0.1 (`role:kiosk` erst nach PA-4.4 scharfschalten), Storage aktivieren + `firebase deploy --only storage`. Neue Composite-Indexe: `payrollRecords(userId,status)`. Emulator-Verifikation offen (kein lokaler Rules-/Storage-Emulator).

---

## §0 Verbindliche Vorentscheidungen (NICHT neu verhandeln)

Dieser Plan baut auf getroffenen Entscheidungen auf und referenziert bestehende Plan-IDs statt sie umzubenennen:

1. **ida-Plan E1–E9 + Leitentscheidungen 1–11** (`plan/ida-hr-zeit-uebernahme.md:195-250`): u. a. nur Mantelzeit/Anwesenheit (E2), Sollzeit als versioniertes Modell (E3), Urlaubsquelle = `SollzeitProfile.urlaubstageJahr` (Nr. 4), §3b voll (E9), DATEV-Lohn ja hinter Flag (E5), Monatsabschluss org-weit + Sperre pro Mitarbeiter (Nr. 10).
2. **AllTec-Plan L1–L4** (`plan/zeitwirtschaft-alltec-1zu1.md:13-20`): AllTec-Screens auf WorkTime-Rechenkernen; **Self-Read statt Cloud-Projektion ist geltender Stand** (M7a: `sollzeitProfiles`/`payrollRecords`/`zeitkontoSnapshots` mit `resource.data.userId == request.auth.uid && canViewTimeTracking()`). Der ida-§4.0-Grundsatz „admin-only + Projektion" ist damit überstimmt — neue Personal-Collections folgen dem M7a-Self-Read-Muster, Schreiben bleibt admin-only.
3. **Kiosk E1–E8 + Kachel-Ausbau §9 #1–8** (`plan/arbeitsmodus-laden-tablet.md:15-27`, `plan/arbeitsmodus-kachel-ausbau.md:328-343`): Geräte-Konto bleibt einzige Firebase-Identität, PIN server-geprüft (scrypt, Rate-Limit, Lockout), **Lohn-/HR-/Finanz-Daten NIEMALS aufs geteilte Tablet**, Board liest sensible Daten nur über whitelisted Projektionen.
4. **personal-finanz-ausbau Kopf-Entscheidungen 1–3**: sensible HR-Daten nur lohnrelevant (Konfession, Familienstand, Kinderzahl); GdB/Aufenthaltsstatus/PEP **bewusst weggelassen** (DSGVO Art. 9). Gilt auch für Dokument-Metadaten (keine Diagnosen, keine Art.-9-Kategorien als Felder).
5. **Redesign E1–E6** (`plan/redesign-gesamt.md:31-42`): Rollout-Reihenfolge, Leitplanke „Redesign = reine Optik". Dieser Plan liefert die **Datenmodell-/Logik-Arbeiten VOR** den Redesign-Rollouts an denselben Dateien (siehe §9).
6. **Konsolidierungs-Leitregeln** (`plan/konsolidierung-duplikate-kopplung.md:41-92`): jedes Feld genau ein Schreib-Ort + Resolver; `UserSettings.hourlyRate/vacationDays/dailyHours` sind nie Berechnungseingang; Lohn leitet ab, erfindet nicht. Die §8-Trade-offs (childrenCount-Vorrangmuster, hireDate vs. validFrom, `PayrollProfile.federalState`-Override, Standortname-Snapshot) bleiben unangetastet.
7. **Zwei parallele Uhren:** Die Restarbeit aus zeitwirtschaft-M3c-a (pausiert) und konsolidierung-Z2 wird **diesem Plan zugewiesen** (PA-4) — keine dritte Parallelbaustelle.

---

## §1 Ist-Befund (belegt, Kurzfassung)

### 1.1 Was schon da ist (mehr als erwartet)

- **Personal-Stammakte existiert:** `EmployeeProfile` (`lib/models/employee_profile.dart:204`, Doc-ID = userId, ~34 Felder: Anschrift, Geburtsdatum, Personalnummer, hire/exit/probation, Familienstand, Konfession, Steuer-ID, SV-Nummer, Krankenkasse + Zusatzbeitrag, IBAN/BIC, Notfallkontakt). Plus `EmployeeChild`/`EmployeeQualification`/`EmployeeAusbildung`, Urlaubskonto-Ledger (`urlaubskontoJahre`/`urlaubsanpassungen`), versionierte `SollzeitProfile`.
- **Lohnlauf als „Richtwert" existiert:** `PayrollCalculator` (§32a-Tarif 2026, SV mit BBG, Minijob/Midijob inkl. Faktor F, PV-Kinderlosenzuschlag, KV-Zusatz, Umlagen U1/U2/InsO/UV, `lib/core/payroll_calculator.dart:157`), §3b-Zuschläge + §39b-Einmalzahlungen als `PayrollRecord.lines` (`lib/core/lohn_herleitung.dart`), Workflow entwurf→freigegeben→bezahlt (`PayrollStatus`), Monatsabschluss-Draft-Kopplung.
- **Stempeluhr ist echtzeitfähig:** `ClockEntry` in `organizations/{orgId}/clockEntries`, eigene offene Buchung via `watchOpenClockEntry` und org-weites `watchOngoingClockEntries` („wer ist eingestempelt") als `snapshots()`-Streams (`lib/services/firestore_service.dart:219/236`). **Ein Kiosk-Punch (Callable `kioskClockPunch`, Admin SDK) schreibt in dieselben Collections und ist in den App-Streams sofort sichtbar** — die Grundanforderung „Tablet-Stempel überall sehen" funktioniert in Richtung Kiosk→App bereits by design.
- **Sync-Fundament solide:** users/Team-Stammdaten, workEntries (Monat+User), shifts (Range), absenceRequests und alle 13 Personal-Collections sind Streams; Firestore-Offline-Persistence auf Web UND mobil vor dem ersten Read aktiv (`lib/main.dart:177-218`).
- **Push-Infrastruktur fertig designt:** `fanOutPush` + 6 Trigger + notifications-Inbox + `notificationPrefs` (`functions/index.js:150`, `plan/push-benachrichtigungen-plan.md`).

### 1.2 Die Lücken (Zielbild-relevant)

| # | Befund | Beleg |
|---|---|---|
| L1 | **Dokumente: Greenfield.** Kein `firebase_storage`-Paket, keine `storage.rules`, kein storage-Block in `firebase.json`, kein Dokument-Model, `file_picker` deklariert aber unbenutzt. Kein bestehender Plan deckt das ab. | `pubspec.yaml:83`, plaene-Analyse |
| L2 | **Keine Mitarbeiter-Selbstsicht:** `employeeProfiles`/`payrollProfiles`/Urlaubskonto sind rules-seitig strikt admin-only (`firestore.rules:926-1010`); die Self-Read-Rule für `payrollRecords` (:911) hat **keinen Client-Konsumenten** — MA sieht weder Akte noch Lohnzettel noch echtes Urlaubskonto. Kein „Meine Personalakte"-Screen. | personal_provider.dart:814, firestore.rules:936 |
| L3 | **Stammdaten verstreut + selbst manipulierbar:** Stundenlohn an 3 Orten (`UserSettings.hourlyRate` self-editierbar in Einstellungen `settings_screen.dart:376`; Team-Editor `team_management_screen.dart:2465`; `EmploymentContract.hourlyRate`), Urlaub an 3–4 Orten (konsolidierung-M1 offen). Die users-Update-Rule **pinnt `settings` nicht** (`firestore.rules:414-432`) → MA kann eigenen (Anzeige-)Stundensatz/Urlaubsanspruch still ändern; `TeamProvider` leitet Verträge sogar aus `settings.hourlyRate` ab (`team_provider.dart:1965-1983`). | ui-navigation-, sicherheit-Analyse |
| L4 | **Lohndaten-Leck:** `employmentContracts` sind `read: sameOrg` — **jedes aktive Org-Mitglied (inkl. Kiosk-Gerätekonto) liest alle Verträge inkl. `hourlyRate`/`monthlyGrossCents`** (`firestore.rules:818-824`). Teamleads lesen zudem alle users-Docs inkl. `settings.hourlyRate` (:389-395). Nirgends als bewusst dokumentiert. | firestore.rules:818 |
| L5 | **Doppel-Stempeln möglich:** clockIn/clockOut sind Direct-Writes ohne Server-Guard (nur Client-`isClockedIn`, `zeitwirtschaft_provider.dart:632`); Doc-ID zufällig, keine `{userId}-open`-Concurrency; Kiosk-Guard read-then-write ohne Transaktion (`functions/index.js:1141`). M7b explizit offen (`plan/zeitwirtschaft-alltec-1zu1.md:339`). Parallel existiert die **Legacy-WorkProvider-Uhr** (rein gerätelokal, SharedPreferences, `work_provider.dart:32/1151`) — beide Uhren wissen nichts voneinander. | zeitwirtschaft-Analyse |
| L6 | **Monats-Festschreibung wirkungslos:** `ZeitkontoSnapshot.abgeschlossen` wird von KEINEM Mutator, KEINER Callable und KEINER Rule geprüft — WorkEntries eines abgeschlossenen Monats bleiben frei änderbar; Rules erlauben Überschreiben gesperrter Snapshots durch jeden `canManageShifts` (`firestore.rules:611-628`). | zeitwirtschaft-Analyse |
| L7 | **Kiosk-Lücken:** (a) Read-Scope zu weit — `permissionOrDefault`-Fallback macht ein Kiosk-Konto ohne Overrides zum Voll-Leser von shifts/clockEntries/zeitkontoSnapshots (Kachel-Plan **A0, blockierend**); (b) `kioskRoster` ist tot (kein Pflege-Trigger, kein Client-Read) → Anmelde-Namensliste hängt an `TeamProvider.members` und **bricht im echten Betrieb** (Nicht-Manager sieht nur sich selbst); (c) offline hängt die Stempel-Kachel (kein try/catch, `kiosk_screen.dart:583`), Stempel geht verloren; (d) `_ClockTile` pollt nur 1× pro Session; (e) `kioskEndSession` wird nie aufgerufen; (f) PIN-Pad kann nur 4 Ziffern, erlaubt sind 4–8; (g) `persistenceEnabled:false` für Kiosk-Build fehlt. | kiosk-Analyse |
| L8 | **Sync-Brüche:** Monatslisten/Org-Loader (`getClockEntriesInRange`, `getOrgWorkEntriesForMonth`, Zeitkonto-Snapshots) sind Einmal-Reads ohne Invalidierung; hybrid-Fallback-Writes bleiben ohne automatischen Rück-Sync gerätelokal (`zeitwirtschaft_provider.dart:750-758`); `ConnectivityStatusProvider` triggert keinen Refetch; kein Push-Trigger auf clockEntries/workEntries; notifications-Inbox ohne Client-Leser. | sync-Analyse |
| L9 | **Lohn-Reste:** kein DATEV-Lohnexport (`datevLohnartNr` erfasst, nie exportiert), `PayrollRecord` verliert Umlagen-/Minijob-Einzelfelder (`payroll_calculator.dart:99-138`), PDF rendert `lines` nicht, kein Lohnjournal-CSV, `PayrollSettings.defaults2026` mit 2025-Platzhaltern (BBG/PV), M-L-b (Überstunden-Auszahlung als Lohn-Line) offen. | personal-modul-Analyse |
| L10 | **Status-Workflow ohne Wirkung:** `EmployeeStatus.isCurrent` wird nirgends konsumiert — kein Listen-Filter, keine Kopplung an `isActive`, Schichtplanung oder Offboarding. Onboarding läuft isoliert über `userInvites`. | employee_profile.dart:127 |
| L11 | **Audit-Lücken:** `savePayrollProfile`/`deletePayrollProfile` (`personal_provider.dart:1330/1386`) und `WorkProvider.updateSettings` (:993) ohne Audit; **Functions schreiben generell kein auditLog** (Kiosk-Stempel, PIN-Operationen unsichtbar). | sicherheit-Analyse |
| L12 | **UX:** Akte 4–5 Ebenen tief und URL-los (kein Deep-Link auf Mitarbeiter), keine Suche im Personal-Bereich, Personal-Kachel 3× mit 3 Wortlauten, `personal_screen.dart` 5.649 Z / `team_management_screen.dart` 4.648 Z (V1-Legacy), Einstellungen V1. | ui-navigation-Analyse |

---

## §2 Zielbild

1. **Eine digitale Personalakte pro Mitarbeiter** als kanonischer Ort mit eigener URL: Stammdaten, Vertrag & Vergütung, Sollzeit & Urlaub, Stundenkonto, Lohnabrechnungen, **Dokumente**, Qualifikationen, Verlauf. Team-Editor und Einstellungen behalten nur ihre Ownership-Felder, alles andere read-only mit Quellhinweis (konsolidierung-M5).
2. **„Meine Personalakte" für Mitarbeiter** (Self-Service, lesend): eigene Stammdaten, eigener Vertrag, echtes Urlaubskonto, Lohnzettel als PDF, eigene Dokumente — über das etablierte M7a-Self-Read-Muster.
3. **Dokumentenverwaltung** auf Firebase Storage (Blaze): Admin lädt hoch (Kategorien, Aufbewahrungsfrist), MA sieht/downloadet auf Web/iOS/Android, Push „Neues Dokument", Kiosk bewusst ausgeschlossen.
4. **Ein Stempel-Pfad, hart geführt:** `{userId}-open`-Concurrency (kein Doppel-Stempeln von zwei Geräten), Callable-Härtung (M7b erledigt), Legacy-Uhr stillgelegt, Kiosk-Resilienz (Fehlertoleranz, Streams/Refresh, Roster-Fix), Anwesenheits-Sicht auf Heute-Tab + Kiosk-Board.
5. **Monatsabschluss = echte Festschreibung** (Client + Callable + Rules), pro-MA-Abrechnungssperre; Lohnlauf-Daten vollständig (Umlagen persistiert, Lines verrechnet, Lohnjournal, DATEV-Lohn hinter Flag).
6. **Klares Rollenmodell** mit Berechtigungsmatrix (§3.3), geschlossene Lecks (Verträge, users.settings, Kiosk-Scope), Audit lückenlos inkl. Server-Pfad, DSGVO-Aufbewahrung/-Löschung/-Auskunft.

**Bewusst NICHT im Zielbild** (Abgrenzung): amtlicher §39b-Programmablaufplan/ELStAM, SV-Meldewesen/Beitragsnachweis/eAU-Abruf, Recruiting (ida M-R, Phase 2), Pfändung/Lohnabtretung, Identitätswechsel am Kiosk. Der Lohnlauf bleibt deklarierter „Richtwert" mit Pflicht-Disclaimer — die App ersetzt kein Lohnbüro, sie bereitet DATEV-fähig vor.

---

## §3 Zielarchitektur

### 3.1 Kanonische Datenquelle je Feld (SSoT-Tabelle)

| Feld | Kanonische Quelle (Schreib-Ort) | Leser/Resolver | Was mit Duplikaten passiert |
|---|---|---|---|
| Stundenlohn | `EmploymentContract.hourlyRate` (Team-Editor, versioniert) | `EmploymentContractResolver.activeOn` (F1) | `UserSettings.hourlyRate`: deprecaten — Anzeige read-only aus Vertrag, Rules-Pin gegen Self-Write (PA-0), Contract-Ableitung aus settings (`team_provider.dart:1965`) entfernen (PA-1) |
| Monatsbrutto (Festgehalt) | `EmploymentContract.monthlyGrossCents` (kanonisch seit M-B0) | `deriveGrossCentsFor` (L3: Vertrag zuerst, Cache-Fallback) | `PayrollProfile.monthlyGrossCents` bleibt reiner Prefill-Cache (dokumentierter Trade-off) |
| Jahresurlaub | `SollzeitProfile.urlaubstageJahr` (seit ida-M0) | `resolveUrlaubstageJahr` (Vorrangregel §5.1) | konsolidierung-M1 umsetzen: `settings_screen.dart:788`, `home_screen.dart:949/2987`, Vertrags-Seed umstellen; `UserSettings.vacationDays` entfernen; Default-Divergenz 20/30 auflösen (PA-1) |
| Sollzeit | `SollzeitProfile` (gültig-ab-versioniert) | `zeitkonto_calculator` | `UserSettings.dailyHours` nur Anzeige-Fallback (Leitregel 1) |
| Steuer-/SV-Merkmale, Bank, Anschrift, Notfallkontakt | `EmployeeProfile` (Personal-Editor) | PersonalProvider | bleibt; SV-/BG-UV-Zusatzfelder kommen mit M-D (PA-6) |
| Steuerklasse/Kirchensteuer/Beschäftigungsart (Lohn) | `PayrollProfile` (Lohn-Editor, Cache-Semantik) | `PayrollCalculator` | bleibt; bekommt Audit (PA-0) |
| Rolle/Rechte/Login-Status | `users/{uid}` (Team-Editor) | AuthProvider/Rules | bleibt; `EmployeeStatus`-Kopplung in PA-7 |
| Beschäftigungsstatus (HR) | `EmployeeProfile.status` | wird wirksam: Listen-Filter, Autoplan, Offboarding (PA-7) | — |
| **Dokumente (NEU)** | `employeeDocuments` + Storage (PA-3) | PersonalDocumentsProvider | — |
| Live-Stempelzustand | `clockEntries` mit `status=='ongoing'`, künftig Doc-ID `{userId}-open` (PA-4) | `watchOpenClockEntry`/`watchOngoingClockEntries` | Legacy-WorkProvider-Uhr wird Delegat/entfernt (PA-4) |

### 3.2 Neue Collections & Modelle

**`organizations/{orgId}/employeeDocuments/{docId}`** — Model `EmployeeDocument` (`lib/models/employee_document.dart`, NEU):

```
id, orgId, userId                        // Zuordnung; Doc-ID zufällig
category (DocumentCategory)              // Enum: arbeitsvertrag, lohnabrechnung, bescheinigung,
                                         //   krankmeldung, zeugnis, schulung, sonstiges
                                         //   (.value snake_case, fromValue-Default sonstiges, deutsches label)
title                                    // Anzeigetitel (Pflicht)
fileName, contentType, sizeBytes         // Datei-Metadaten (Anzeigename ≠ Storage-Pfad)
storagePath                              // voller Storage-Pfad (s. u.)
note                                     // optional
visibleToEmployee (bool, Default true)   // false = interne Ablage (z. B. Abmahnungs-Entwurf)
acknowledgedAt (DateTime?)               // optionale Lesebestätigung durch den MA
retentionUntil (DateTime?)               // Aufbewahrungs-Ende (aus Kategorie-Default, PA-8)
uploadedByUid, createdAt, updatedAt
```

Zwei Serialisierungen nach Repo-Regel (`toFirestoreMap` camelCase/Timestamp, `toMap` snake_case/ISO). **Bewusste Ausnahme:** kein `local_v2`-Spiegel in `DatabaseService` — Dokumente sind **cloud-only** (Binärdateien passen nicht in SharedPreferences; Metadaten ohne Datei sind wertlos). Im `local`-Speichermodus zeigt der Dokumente-Abschnitt einen Hinweis „Dokumente benötigen den Cloud-Modus".

**Storage-Pfadschema** (keine PII im Pfad, org-skopiert):
```
employee-documents/{orgId}/{userId}/{docId}          // Objektname = docId, KEIN Dateiname
```

**Composite-Index:** `employeeDocuments(userId ASC, createdAt DESC)` → `firestore.indexes.json` ergänzen (Kopplung: neuer where+orderBy-Query).

**`ClockEntry`-Erweiterung:** Felder `source` (`'app'|'kiosk'`), `deviceId`, `sessionId` ins Dart-Model aufnehmen — `kioskClockPunch` schreibt sie heute schon, der Client-Round-Trip **verliert sie** (Kopplung #1: 6 Stellen + snake_case-Parse in `functions/index.js`). Zusätzlich `workEntryId` beim clockOut endlich zurückschreiben (Plan §4.1, bisher nie gesetzt).

**`PayrollRecord`-Erweiterung (PA-6):** Einzelfelder `minijobEmployerFlatCents`, `umlageU1Cents`, `umlageU2Cents`, `umlageInsoCents`, `umlageUvCents` persistieren statt nur `employerTotalCents`-Aggregat.

**`kioskPresence/{siteId}`** (aus Kachel-Plan A2, hier gebaut weil Stempel-gekoppelt): server-gepflegte Projektion `{einträge: [{uid, vorname, fotoUrl, seit}]}`, `read: sameOrg / write: false`. **Pflege über einen `onClockEntryWritten`-Trigger** (nicht in den Callables): nur so werden auch Direct-Write-/hybrid-Fallback-Stempel abgedeckt — Client kann die Projektion wegen `write: false` nie selbst reparieren. Restgrenze (offline entstandene, erst später gesyncte Buchungen aktualisieren die Presence verzögert) ist akzeptiert und dokumentiert.

### 3.3 Berechtigungsmatrix (Soll)

Legende: **L** = lesen, **S** = schreiben, **–** = kein Zugriff. „self" = eigener Datensatz.

| Datenart | admin | teamlead | employee (self) | employee (fremd) | Kiosk-Gerätekonto |
|---|---|---|---|---|---|
| Stammdaten Akte (`employeeProfiles`) | L+S | – ¹ | **L (neu, PA-2)** | – | – |
| Vertrag/Vergütung (`employmentContracts`) | L+S | **L (nur via canManageShifts, für Planung/Compliance)** ² | **L self (neu, PA-0)** | **– (Leck schließen, PA-0)** | – |
| Lohn-Stammdaten (`payrollProfiles`) | L+S | – | – ³ | – | – |
| Lohnabrechnungen (`payrollRecords`) | L+S | – | L (Rule existiert; **Client-Konsument neu, PA-7**) | – | – |
| Dokumente (`employeeDocuments`) | L+S | – | L (nur `visibleToEmployee`) + S nur `acknowledgedAt` | – | – |
| Sollzeit (`sollzeitProfiles`) | L+S | L (Team) | L self (M7a, live) | – | – |
| Stundenkonto (`zeitkontoSnapshots`) | L+S | L+S (Abschluss) → **S nur wenn nicht festgeschrieben (PA-5)** | L self | – | – |
| Urlaubskonto (`urlaubskontoJahre`/`-anpassungen`) | L+S | – | **L self (neu, PA-7)** | – | – |
| Stempel live (`clockEntries`) | L+S | L+S org-weit | L+S self | – | – (nur `kioskPresence`-Projektion + Callables) |
| Anwesenheit („wer ist da") | L | L | eigener Status | – | L (nur Projektion) |
| Audit-Log (`auditLog`) | L | – | – | – | – |
| `users/{uid}` settings-Lohnfelder | S | L ⁴ | **read-only (Pin, PA-0)** | – | – |

¹ Teamlead bewusst OHNE HR-/Lohn-Akte (Betreiber-Entscheidung E-P5 kann das später öffnen — Rules-Zeile ist vorbereitet, Default zu).
² Verträge braucht die Planung (Caps/Minijob im Auto-Verteiler) und die client-seitige Compliance. Neue Rule: `read: canManageShifts || self` statt `sameOrg`.
³ Steuerklasse etc. sieht der MA über seine Lohnabrechnung (dort abgedruckt), nicht als Roh-Collection.
⁴ Entschärft sich, sobald `settings.hourlyRate` deprecated ist (PA-1); bis dahin dokumentierte Übergangs-Lücke.

**Kiosk-Kopplungsregel (aus Kachel-Plan A0/Kopplung #4, gilt ab sofort):** Jede NEUE Personal-/Dokument-Collection und jeder Storage-Pfad bekommt von Tag 1 einen expliziten Kiosk-Deny (`role != 'kiosk'` bzw. explizite `permissions:false`-Overrides am Gerätekonto) und einen Emulator-Regressionstest gegen ein Kiosk-Profil ohne Overrides.

### 3.4 Echtzeit-Sync über die 4 Geräteklassen

**Prinzip:** Firestore-`snapshots()`-Streams sind der einzige Sync-Mechanismus für Live-Zustand (kein Polling, kein Custom-Socket). Push (FCM) ist Benachrichtigung, nicht Datentransport. Was heute schon live ist, bleibt; die Brüche werden geschlossen:

| Fluss | Heute | Soll (Paket) |
|---|---|---|
| Kiosk-Stempel → App (Web/iOS/Android) | ✅ live (Callable schreibt `clockEntries`, Streams greifen) | bleibt; zusätzlich Presence-Projektion (PA-4) |
| App-Stempel → Kiosk | ❌ `_ClockTile` pollt 1×/Session | Status aus Callable-Antwort nach jedem Punch + Refresh bei Session-Start + `kioskPresence`-Stream fürs Board (PA-4) |
| App-Stempel → andere App-Geräte | ✅ live (`watchOpenClockEntry`) | bleibt; Doppel-Stempel-Guard kommt dazu (PA-4) |
| Monats-/Abschluss-Ansichten | ❌ Einmal-Reads | gezielter Refetch: nach eigenem Stempel (existiert), bei App-Resume und bei Reconnect (`ConnectivityStatusProvider`-Kopplung, PA-4); bewusst KEIN Dauer-Stream über Org-Monatsdaten (Kosten) |
| hybrid-Fallback-Writes | ❌ bleiben gerätelokal bis manueller Moduswechsel | Outbox-Light: Rück-Sync-Versuch bei Reconnect + sichtbarer „ausstehend"-Badge (PA-4, ehrliche Grenze: kein voller Sync-Engine-Umbau) |
| `local`-Speichermodus | per Definition kein Cross-Device | bleibt; Personal-/Zeit-Screens zeigen dauerhaften Hinweis „Lokaler Modus – keine Geräte-Synchronisation" (PA-2) |
| Dokumente | — | Metadaten als Stream (live), Datei on-demand Download; Upload nur online (PA-3) |
| HR-Ereignisse → Push | ❌ kein Trigger auf clockEntries/Dokumente/Lohn | neuer Kanal `personal` + Trigger (PA-3/PA-7) |

---

## §4 Meilensteine & Arbeitspakete

Reihenfolge: **PA-0 → PA-1 → PA-2 → PA-3 → PA-4 → PA-5 → PA-6 → PA-7 → PA-8 → PA-9.** PA-4 ist ab PA-0 parallelisierbar (andere Dateien); PA-3 braucht PA-2 (Akte-Screen als Träger). Jedes Paket endet grün auf `flutter analyze` + `flutter test` (+ `node --test` bei Functions-Anteil) — keine halben Zwischenstände über Paketgrenzen.

---

### PA-0 · Sicherheits-Fundament (BLOCKIEREND — vor allen neuen Collections)

**PA-0.1 Kiosk-Read-Scope-Härtung (= Kachel-Plan A0). — UMGESETZT (2026-07-03)**
`isKiosk()`-Helper in `firestore.rules` (`normalizedRoleValue == 'kiosk'`, nutzt `hasProfile()`) + `&& !isKiosk()`-Deny an allen sensiblen Read-Pfaden: users (org-weiter Zweig), workEntries, clockEntries, zeitkontoSnapshots, employmentContracts (PA-0.2), contacts, stockMovements. **Zusätzlich serverseitig (über Plan hinaus):** `permissionDefaultsForRole` in `functions/index.js` bekommt einen `case "kiosk"` mit ALLEN Rechten `false` — sonst fiele ein Kiosk-Konto ohne explizite Overrides in den employee-`default` (`canEditTimeEntries:true`) und käme z. B. durch `assertTimeEntryEditor`; `normalizeRole` gibt `'kiosk'` bereits unverändert durch. Dart-`UserRole` bewusst NICHT erweitert. Die expliziten `permissions:false`-Overrides am Kiosk-users-Doc bleiben ein Provisionierungs-Schritt (Deploy/PA-9); der `!isKiosk()`-Deny wirkt unabhängig davon (Defense-in-Depth). **Offen:** Emulator-Regressionstest (Repo hat keine Rules-Unit-Infra → PA-9).

> **⚠️ AKTIVIERUNGS-VORBEDINGUNG (Security-Review 2026-07-03).** Die `!isKiosk()`-Denies sind heute **schlummernd**: Es existiert noch KEIN `role:'kiosk'`-Konto (das Tablet meldet sich derzeit mit einem Nicht-Kiosk-Konto an), also ändert sich am laufenden Betrieb nichts. **Sobald aber ein `role:'kiosk'`-Konto provisioniert wird, macht diese Härtung das Kiosk-Board unbenutzbar, bis PA-4 fertig ist** — zwei belegte Bruchstellen: (1) `InventoryProvider._startFirestoreSubscriptions` abonniert `watchStockMovements(orgId)` **bedingungslos** (`inventory_provider.dart:869`, `onError: _setError`) → permission-denied setzt den GESAMTEN Provider in den Fehlerzustand (Board liest ihn für Produkte/Kühlschrank/Ablauf/Kasse); (2) die Kiosk-Anmelde-Namensliste kommt aus `TeamProvider.members` = org-weiter `users`-Stream (`kiosk_screen.dart:206`), der jetzt hart verweigert wird → **leere Namensliste**. **Deshalb:** `role:'kiosk'` erst provisionieren, NACHDEM PA-4.4 (Roster ← `kioskRoster`) UND die InventoryProvider-Kiosk-Unterdrückung (neu in PA-4.4) stehen. Bis dahin bleibt der Deny reine Defense-in-Depth für ein noch nicht existierendes Konto.
`Geeignet für: Fable 5` (Rules-Architektur + Fallback-Semantik von `permissionOrDefault` ist der riskante Teil)

**PA-0.2 Verträge-Leck schließen. — UMGESETZT (2026-07-03)**
`employmentContracts`-read jetzt `sameOrg && !isKiosk() && (canManageShifts() || resource.data.userId == request.auth.uid)`. Client synchron umgebaut: neue Service-Methode `watchEmploymentContractsForUser(orgId, userId)` (self-Query, nutzt Index `employmentContracts(userId, validFrom)`); `TeamProvider` wählt für Nicht-Manager diesen self-Stream, Manager streamen weiter org-weit. Test `PA-0.2: Nicht-Manager streamt NUR den eigenen Vertrag` (kein Vergütungs-Leck) grün. Deploy-Reihenfolge (Client vor Rules) siehe unten / PA-9. **Minor (Security-Review, nicht blockierend):** `_storeHybridContractsSnapshot` merged per Union — ein früher als Manager gecachter Fremd-Vertrag bleibt im lokalen Hybrid-Cache liegen (kein neues Firestore-Leck, nur geräte-lokale Cache-Hygiene). Optional beim Rollenwechsel Contracts-Cache auf die self-Menge zurücksetzen; in PA-1 mitnehmen. **Achtung, Rules sind keine Filter:** der heutige org-weite Stream (`TeamProvider.watchEmploymentContracts`, für ALLE Rollen abonniert, `team_provider.dart:423-434`) fällt für Nicht-Manager dann KOMPLETT aus (`_setStreamError`, Verlust auch des eigenen Vertrags → Compliance-/Minijob-Preview verliert still Referenzdaten). Deshalb zwingende Reihenfolge: **(1) App-Release mit self-Query für Nicht-Manager ausrollen** (Composite-Index `employmentContracts(userId, validFrom)` existiert bereits, `firestore.indexes.json:148-159`), **(2) erst danach Rules verschärfen.** Compliance-Preview (eigene Einträge) braucht nur eigene Verträge → self reicht.
`Geeignet für: Fable 5` (Rules + Provider-Query-Umbau müssen synchron, sonst bricht der Client)

**PA-0.3 users-Self-Update feldgranular. — UMGESETZT (2026-07-03)**
Helper `settingsValue`/`settingsPayrollFieldsUnchanged` (camelCase, tolerant gegen fehlende Keys) im users-Self-Update-Zweig ergänzt; UI in `settings_screen.dart` — Stundenlohn- und Urlaubstage-Feld auf `enabled: false` + Quellhinweis („Wird vom Admin im Vertrag/Sollzeit-Profil gepflegt"). Damit ist Redesign-Widerspruch #4 (PV-M3) entschieden: Anzeige statt Editor. Restdetail unten.
Self-Zweig der users-Update-Rule pinnt zusätzlich `settings.hourlyRate` und `settings.vacationDays` — **camelCase!** Im users-Doc liegen die Settings via `UserSettings.toFirestoreMap()` (`user_settings.dart:57-62`) in camelCase; `hourly_rate`/`vacation_days` ist nur das lokale `toMap()`-Format (Zwei-Serialisierungs-Regel). Pin tolerant gegen fehlende Keys formulieren (Muster `permissionsEquivalent`, `firestore.rules:424` — Alt-Docs/Teil-Maps dürfen nicht error-denyen). `photoUrl`/`notificationPrefs`/übrige settings bleiben frei. UI: die beiden Felder in `settings_screen.dart` (:246-306, :884-899) werden read-only mit Quellhinweis „wird vom Admin im Vertrag/Sollzeit-Profil gepflegt" — **damit ist Redesign-Widerspruch #4 (PV-M3 „Meine Vorgaben") entschieden: Anzeige statt Editor.**
`Geeignet für: Beide` (Rules-Pin: Fable 5; UI-read-only + Tests: Opus)

**PA-0.4 Audit-Lücken (Client). — UMGESETZT (2026-07-03)**
`_audit?.call(...)` auf beiden Erfolgs-Pfaden ergänzt in `savePayrollProfile`/`deletePayrollProfile` (`personal_provider.dart`), Entity-Typ `Lohn-Stammdaten`, deutsche Summaries, `isNew` über `profileForUser`.
**Bewusste Abweichung bei `WorkProvider.updateSettings`:** KEIN Audit ergänzt. Grund: PA-0.3 pinnt `settings.hourlyRate`/`vacationDays` rules-seitig gegen Selbstschreiben und macht die Felder read-only — die verbleibenden `UserSettings`-Felder (Name, dailyHours-Anzeige, Auto-Pause, Währung) sind laut Konsolidierungs-Leitregel 1 reine Anzeige-/Fallback-Werte (nie Berechnungseingang), und CLAUDE.md schreibt ausdrücklich vor, *persönliche Einstellungen NICHT zu loggen* (Rausch-Vermeidung). Der ursprüngliche Auditgrund (still änderbarer abrechnungsrelevanter Stundensatz) ist durch PA-0.3 an der Wurzel geschlossen; ein Audit wäre jetzt genau das verbotene Rauschen.
`Geeignet für: Opus` (klares Muster existiert in Nachbar-Mutatoren)

---

### PA-1 · Stammdaten-Konsolidierung (= konsolidierung M1 + M5, hier ausgeführt)

**PA-1.1 Jahresurlaub-Einquellenprinzip (konsolidierung-M1). — MIGRATIONS-GATED, offen**
Alle Leser auf `resolveUrlaubstageJahr` umstellen: `settings_screen.dart` (_VacationQuotaCard), `home_screen.dart:963/3054` (Profil-Chips), `app_nav_menu.dart` (Header-Chip); Vertrags-Seed (`team_provider.dart:1989`) auf Sollzeit-Quelle; `UserSettings.vacationDays` aus Model/UI entfernen (Serialisierung tolerant lesen, nicht mehr schreiben); Default-Divergenz 20 vs. 30 auf gesetzeskonformen Default auflösen.
> **Analyse-Befund (2026-07-03, warum nicht in diesem Durchgang bulldozert):** Die DISPLAY-Leser zeigen den Wert des **aktuellen (oft Nicht-Admin-)Nutzers**. `resolveUrlaubstageJahr` lebt im `PersonalProvider`, dessen Stammakten-Streams für Nicht-Admins early-returnen — nur das eigene `SollzeitProfile` (M7a-Self-Read) + die eigenen Verträge (via `updateReferenceData`) liegen vor, `EmployeeProfile.annualVacationDays` (mittlere Fallback-Stufe) NICHT. Für die korrekte Selbstanzeige muss also entweder (a) auf das eigene `SollzeitProfile.urlaubstageJahr` resolved werden (reicht meist, da primäre Quelle) ODER (b) PA-2.3 (Self-Read `employeeProfiles`) vorgezogen werden. Reihenfolge: **PA-2.3 → PA-1.1-Display**. Das reine Entfernen des Modellfelds ohne diese Verdrahtung würde die Chips wertlos machen.
`Geeignet für: Beide` (Migrations-/Fallback-Semantik: Fable 5; mechanische Leser-Umstellung + Tests: Opus)

**PA-1.2 Ownership-Festschreibung (konsolidierung-M5). — MIGRATIONS-GATED, offen**
Team-Editor = Identität/Rolle/Rechte/Vertrag/Standort; Personal-Editor = HR-Stammakte/Lohn; doppelt editierbare Felder je nur an EINEM Ort schreibbar, am anderen read-only mit Quellhinweis (childrenCount-Vorbild). `TeamProvider`-Contract-Ableitung aus `settings` (`_defaultContractForMember`, `team_provider.dart:1967-1997`) entfernen — Verträge werden nur noch explizit angelegt.
> **Analyse-Befund (2026-07-03):** `_defaultContractForMember` ist kein Cosmetics-Punkt, sondern ein **Lohn-Fallback**: `_effectiveContracts` synthetisiert für jeden Mitarbeiter OHNE expliziten Vertrag einen Standardvertrag aus `settings` (hourlyRate/dailyHours/vacationDays/currency). Ersatzloses Entfernen strandet vertraglose Mitarbeiter → `contractForUser==null` → `deriveGrossCentsFor` verliert das Festgehalt → **re-öffnet die konsolidierung-L1-Lücke (Monatslöhner 0 €)**. Sichere Reihenfolge: erst **Migration** (für alle aktiven Mitglieder ohne Vertrag einmalig einen expliziten `EmploymentContract` seedn — Muster `migriereUrlaubstageInSollzeit`), DANN die Synthese entfernen. **Sicherheits-Aspekt schon entschärft:** Seit PA-0.3 ist `settings.hourlyRate` rules-seitig gegen Selbstschreiben gepinnt → die „selbst-gemeldeter Satz speist Lohn"-Gefahr besteht nicht mehr; PA-1.2 ist damit reine Architektur-Sauberkeit (mittlere Prio), kein Sicherheitsloch mehr.
`Geeignet für: Fable 5` (Entscheidung, welches Feld wohin, + verdeckte Kopplung im TeamProvider + Migration)

**PA-1.3 Quali-Gültigkeit sichtbar (konsolidierung-M2, Minimal-Variante). — UMGESETZT (2026-07-03)**
Pure, getestete Statusberechnung `EmployeeQualification.gueltigkeitStatus(date, {warnTage=30})` → `enum QualiGueltigkeit { gueltig, laeuftAb, abgelaufen }` (7 Tests, `employee_qualification_test.dart`); Anzeige in der Quali-Liste des Personal-Screens (`_EmployeeHrCard`, `personal_screen.dart:3253`) als dreistufiger `AppStatusBadge` (Abgelaufen=error / Läuft ab=warning / gültig=kein Badge) statt des bisherigen binären Warn-Icons. **Präzisierung:** Der Team-Editor führt nur den Quali-Stammkatalog (`QualificationDefinition`, ohne `gueltigBis`) — die per-Mitarbeiter-Gültigkeit gibt es nur im Personal-Screen, dort ist der Badge. Autoplan-/Compliance-Integration (Spiegel-Kopplung #2) bewusst später.
`Geeignet für: Opus`

---

### PA-2 · Digitale Personalakte (Admin-UI + Self-Service-Fundament)

**PA-2.1 Akte bekommt eine URL.**
`AppRoutes.personalAkte = '/personal/mitarbeiter/:userId'` + `_sectionRoute` — Kopplung #7, **mit einer Besonderheit:** `RoutePermissions.isLocationAllowed` ist ein exakter `switch` über `state.matchedLocation` (die echte URL, nie das Pattern) mit `default: return true` (fail-open, `route_permissions.dart:19-80`) — ein Case auf die `:userId`-Konstante matcht NIE. Deshalb Präfix-Zweig VOR dem switch ergänzen (`if (loc.startsWith('/personal/mitarbeiter/')) return p?.isAdmin ?? false;`, Muster Kiosk `app_router.dart:290`), sonst wäre die Akte per Deep-Link für jeden aktiven Nutzer offen. Editor-Sheets bleiben imperativ. `_EmployeeDetailScreen` aus `personal_screen.dart:1800` in eigene Datei `lib/screens/personal/employee_akte_screen.dart` heben (Monster-Datei entlasten), Monats-Kontext nicht mehr als eingefrorene Konstruktor-Parameter, sondern live aus Provider. Globale Suche verlinkt Mitarbeiter-Treffer direkt auf die Akte.
`Geeignet für: Beide` (Route/Extraktion aus 5.649-Zeilen-Datei riskant: Fable 5; Feinschliff/Tests: Opus)

**PA-2.2 Akte-Struktur (Abschnitte, „nicht minimal, nicht überladen").**
Abschnitts-Layout mit `AppSectionCard` + progressive disclosure: Kopf (Name, Rolle, Status-Badge, Standort) → Stammdaten → Vertrag & Vergütung → Sollzeit & Urlaub (mit `AppKontoTile`) → Stundenkonto (Link /zeit) → Lohnabrechnungen → **Dokumente (PA-3)** → Qualifikationen/Ausbildung/Kinder → Notfallkontakt → Verlauf (Audit-Auszug zum Mitarbeiter). Bestehende Editor-Sheets werden wiederverwendet, nicht neu gebaut. `AppSearchField` in der Personal-Übersicht (Name/Personalnummer-Filter).
`Geeignet für: Opus` (klar spezifizierte UI auf vorhandenen V2-Bausteinen)

**PA-2.3 Self-Read-Rules für die Akte. — UMGESETZT (2026-07-03)**
`employeeProfiles`-read jetzt `sameOrg && (isAdmin() || resource.data.userId == request.auth.uid)` (Schreiben admin-only). Service-Methode `watchEmployeeProfileForUser` (bewusst `where userId ==`-**Query**, nicht `.doc(userId)` — ein Doc-Read einer noch nicht existierenden Akte würde die Self-Read-Regel mit `resource==null` auswerten → permission-denied statt leer). PersonalProvider abonniert sie für Nicht-Admins im selben Zweig wie den Sollzeit-Self-Read; `_employeeProfilesSubscription` wird via `_cancelSubscriptions` zwischen Sessions gecancelt. Test `PA-2.3: Nicht-Admin lädt NUR die eigene Personal-Stammakte` grün. Damit ist das Self-Read-Fundament für „Meine Akte" (PA-2.4) und die PA-1.1-Display-Konsolidierung gelegt.
`Geeignet für: Fable 5` (Rules-Grundsatzentscheidung + Provider-Stream-Gating)

**PA-2.4 „Meine Personalakte"-Screen (Mitarbeiter). — UMGESETZT (fokussiert, 2026-07-03)**
Route `AppRoutes.meineAkte = '/meine-akte'` (route_permissions `p != null`, `_sectionRoute`, AppNavMenu-Eintrag „Meine Akte" via optionalem `onOpenMeineAkte`, in home_screen verdrahtet). `MeineAkteScreen`: Kopf, eigene Stammdaten (read-only aus self-read `employeeProfile` + „Änderungen an die Verwaltung"), Urlaubs-Anspruch/-Rest (`urlaubsReportFor` self), Dokumente (`EmployeeDocumentsCard canManage:false`). **Noch nicht drin (Folgeausbau):** Lohnzettel-Liste (PA-7.1), Stundenkonto-Verweis, Kiosk-PIN-Link — additive Ergänzungen.
`Geeignet für: Opus`

---

### PA-3 · Dokumentenverwaltung (Greenfield) — UMGESETZT (2026-07-03)

> **Status:** Metadaten-/Rules-/Provider-/UI-/Trigger-Ebene komplett + getestet (1385 Tests grün, `employee_document_test` 6, `personal_documents_test` 5 inkl. Upload-Rollback + Self-Scope). `firebase_storage: ^12.2.0` (web ^0.5-kompatibel). Storage-Seam `DocumentStorage`/`FirebaseDocumentStorage` isoliert `firebase_storage` (Tests injizieren Fake). PersonalProvider statt separatem Provider (bewusste Abweichung: gleiche Self-Read-Gating wie employeeProfiles, keine main.dart-Ketten-Chirurgie — Storage-Binärteil bleibt im Seam). Push über Kanal `aufgaben` statt neuem `personal`-Kanal (bewusst, um die 6-Kopplungs-Kanal-Taxonomie nicht mitzuziehen; leicht nachrüstbar). **On-Device-Rest:** echter Storage-Upload/-Download ist nur am Gerät/Emulator verifizierbar (Seam getestet, Binärpfad nicht); `storage.rules` per Emulator-Matrix (PA-9). Composite-Index NICHT nötig (2 Gleichheitsfilter + clientseitige Sortierung).

**PA-3.1 Infrastruktur.**
`firebase_storage` in `pubspec.yaml`; `storage`-Block in `firebase.json`; **`storage.rules` (NEU)**: Pfad `employee-documents/{orgId}/{userId}/{docId}` — `read`: Admin-Check via `firestore.get(/databases/(default)/documents/users/$(request.auth.uid))` (role==admin && orgId match) ODER Self-Zweig `request.auth.uid == userId` **UND** `firestore.get(.../organizations/$(orgId)/employeeDocuments/$(docId)).data.visibleToEmployee == true` (sonst wären interne Dokumente wie Abmahnungs-Entwürfe nur durch die zufällige docId geschützt); niemals `role=='kiosk'`; `write`: nur Admin, `request.resource.size < 15 * 1024 * 1024`, `contentType` in Whitelist (`application/pdf`, `image/jpeg`, `image/png`); `delete`: nur Admin. Hinweis: `firestore.get()` in Storage-Rules (Cross-Service-Rules) kostet 1–2 Reads pro Zugriff — akzeptiert (niedrige Frequenz).
`Geeignet für: Fable 5` (Security-Design; erste Storage-Rules des Projekts)

**PA-3.2 Model + Provider.**
`EmployeeDocument` (§3.2) mit beiden Serialisierungen + `copyWith`/`clearX`; **neuer `PersonalDocumentsProvider`** (ChangeNotifier, `ChangeNotifierProxyProvider3<Auth,Storage,Audit>`, in `main.dart` NACH PersonalProvider — Kopplung #4; Cloud-Repo **lazy** auflösen!): admin → `watchEmployeeDocuments(orgId)`; sonst self-Query `where userId == uid && visibleToEmployee == true`. Firestore-Rules-Block `employeeDocuments`: read admin || (self && `resource.data.visibleToEmployee == true`); create/delete admin-only; update admin ODER self **nur** `acknowledgedAt` via `diff().affectedKeys`-Check (Muster `products.fridgeStock`, `firestore.rules:1086`). Composite-Index eintragen. Kiosk-Deny.
`Geeignet für: Fable 5` (neuer Provider in der Kette + feldgranulare Rules)

**PA-3.3 Upload-Flow (Admin, Akte-Abschnitt „Dokumente").**
`file_picker` (endlich benutzt): Typen-Whitelist pdf/jpg/png, 15-MB-Client-Check vor Upload; `putData` mit `SettableMetadata(contentType)`; Fortschritt via `UploadTask.snapshotEvents` (Determinate-Progress im Sheet); Reihenfolge Storage-Upload → Metadaten-`create`, bei Firestore-Fehler Storage-Objekt aufräumen (best-effort); Kategorie + Titel + `visibleToEmployee`-Schalter + Notiz im Upload-Sheet; Audit auf Erfolgs-Pfad („Dokument ‚X' für &lt;Name&gt; hochgeladen"). Deutsche Fehlertexte (offline: „Upload benötigt eine Internetverbindung").
`Geeignet für: Beide` (Fehler-/Aufräum-Semantik: Fable 5; Sheet-UI + Tests: Opus)

**PA-3.4 Download-Flow (alle Plattformen).**
`getData(bis 15 MB)` → bestehende Download-/Share-Mechanik der PDF-/CSV-Exporte wiederverwenden (`ExportService`-Save-Pfad; Web = Browser-Download, iOS/Android = Teilen/Öffnen-Dialog). Lesebestätigungs-Button (optional pro Dokument, setzt `acknowledgedAt` — der einzige Self-Write). Vorschau bewusst NICHT gebaut (nur Download) — Scope-Disziplin.
`Geeignet für: Opus`

**PA-3.5 Push „Neues Dokument".**
`onEmployeeDocumentCreated`-Trigger (documentTrigger-Wrapper) → `fanOutPush` an genau `userId`, nur wenn `visibleToEmployee`; **neuer Kanal `personal`** — alle 6 Kopplungsstellen des NotificationPrefs-Modells + Android-Channel + Ereignis-Katalog im Push-Plan nachziehen. Idempotenz via dedupeKey = docId.
`Geeignet für: Opus` (Trigger-Template + Kopplungs-Checkliste existieren im Push-Plan)

---

### PA-4 · Stempel-Härtung + Echtzeit (löst zeitwirtschaft-M7b, konsolidierung-Z2, Kiosk-Fixes)

**PA-4.1 `{userId}-open`-Concurrency (Doppel-Stempel-Guard, hart).**
Neues Schreibmuster: clockIn erzeugt `clockEntries/{userId}-open` (ein Schema, überall identisch — Rules-Check, Server-Helper, Client). Die clockIn-**Transaktion prüft zusätzlich per Query auf bestehende `status=='ongoing'`-Einträge** (wie `kioskClockPunch` heute, `functions/index.js:1114-1121`) — das deterministische Doc allein schützt in der Übergangsphase nicht, weil Alt-offene Buchungen zufällige IDs tragen. clockOut in Transaktion: kopiert nach Auto-ID mit `status: completed` + löscht das open-Doc + schreibt `workEntryId` zurück; **Legacy-Zweig:** offene Buchungen mit Alt-ID (`clock-{micros}`) werden weiter per Update geschlossen (kein copy+delete). Streams bleiben query-basiert (`status=='ongoing'`) → Anzeige ist ID-agnostisch. Gilt identisch für App-Pfad und `kioskClockPunch` (gemeinsamer Server-Helper, dessen read-then-write-Race damit auch weg ist).
`Geeignet für: Fable 5` (Concurrency-Design, Transaktions-Semantik, Migrations-Kompatibilität)

**PA-4.2 Callables `clockIn`/`clockOut` (M7b).**
Cloud Functions (Region `europe-west3` = `const REGION`), Payload snake_case `toMap()` (Zwei-Serialisierungs-Regel!), Checks: `assertTimeEntryEditor` + `assertSameOrg` + open-Guard + `kioskRequiredBreakMinutes`-Spiegel; Client `FirestoreService.saveClockEntry` → Callable-first mit Direct-Write-Fallback bei `not-found`/`unavailable` (Repo-Muster). **Damit der Fallback den Guard nicht aushebelt, brauchen die `clockEntries`-Rules einen Sonderpfad für das open-Doc:** (a) heutiges `set(..., merge: true)` (`firestore_service.dart:200-207`) ist rules-seitig ein erlaubtes UPDATE — ein zweites clockIn würde die offene Buchung still überschreiben. Also: create-only auf `{uid}-open` (self-update darauf nur für den definierten clockOut-Status-Übergang), Client-Fallback schreibt das open-Doc OHNE merge; (b) `allow delete` ist heute admin-only (`firestore.rules:605`) — der clockOut-Fallback (copy+delete) bräuchte `delete` für `clockEntryId == request.auth.uid + '-open'`. Ohne diese beiden Rules-Zeilen gilt der harte Guard NUR auf dem Callable-Pfad (dann ehrlich so dokumentieren). Callable-only-Umstellung ist Go-Live-Entscheidung E-P4. `node --test`-Abdeckung.
`Geeignet für: Fable 5` (validierter Pfad + Fallback-Konsistenz ist die heikelste Kopplung des Plans)

**PA-4.3 Legacy-Uhr stilllegen (M3c-a/Z2-Fortsetzung).**
`WorkProvider.clockIn/clockOut/_clockIn` zu Delegaten auf `ZeitwirtschaftProvider` machen bzw. entfernen; `_handlePunchClockAction` (`home_screen_tabs.dart:2110`) auf den ClockEntry-Pfad; Schichtdeckungs-/Overtime-Split (`_splitEntryAgainstShift`) als optionale Nachbearbeitung in den clockOut-Pfad übernehmen; SharedPreferences-Keys `clock_in_*` tot; ida-M11 entschieden: **ClockEntry→WorkEntry ist die einzige Ist-Quelle**, Schicht-Completion bleibt am WorkEntry-Save-Hook.
`Geeignet für: Fable 5` (Verhaltens-erhaltender Umbau zweier verzahnter Provider)

**PA-4.4 Kiosk-Resilienz + Roster-Fix + Read-Scope-Aktivierung.**
(a) `_ClockTile`: try/catch um alle Service-Calls, deutsche Fehlermeldung + Retry-Button, `_busy`-Reset im finally; Status nach jedem Punch aus der Callable-Antwort übernehmen. (b) `kioskRoster`-Pflege-Trigger (`onUserWritten` → Projektion Name/Foto/Standort) + Kiosk-Namensliste von `TeamProvider.members` auf `kioskRoster` umstellen (behebt leere Liste im echten Betrieb). (c) `kioskEndSession` beim Logout/Auto-Logout aufrufen. (d) PIN-Pad 4–8 Ziffern + OK-Taste. (e) `persistenceEnabled:false` im Kiosk-Build (`_buildFirestoreSettings` + `AppConfig.kioskModeEnabled`-Gate). (f) Offline-Grenze ehrlich: KEIN Offline-Stempeln am Kiosk (PIN-Prüfung ist serverseitig, eine Offline-Queue würde unverifizierte Identitäten puffern) — klare Meldung „Keine Verbindung – Stempeln derzeit nicht möglich" statt hängender Kachel. **(g) Client-Kiosk-Read-Unterdrückung (Voraussetzung, damit die PA-0.1-`!isKiosk()`-Denies AKTIVIERT werden können, Security-Review 2026-07-03):** Streams, die für ein `role:'kiosk'`-Konto jetzt permission-denied liefern, dürfen für den Kiosk-Build NICHT abonniert werden — sonst gehen die Provider in den Fehlerzustand. Konkret: `InventoryProvider._startFirestoreSubscriptions` muss `watchStockMovements` (und alle weiteren `!isKiosk()`-gesperrten Reads) überspringen, wenn `AppConfig.kioskModeEnabled` (`inventory_provider.dart:869`, `onError: _setError` reißt sonst den ganzen Provider). Erst wenn (b) + (g) stehen, darf ein `role:'kiosk'`-Konto provisioniert und die Härtung scharf geschaltet werden (siehe PA-0.1-Aktivierungs-Vorbedingung + PA-9).
`Geeignet für: Beide` (Roster-Trigger + Persistence-Gate + Read-Unterdrückung: Fable 5; Tile-Fehlerbehandlung, PIN-Pad, EndSession: Opus)

**PA-4.5 Anwesenheits-Sichten.**
(a) Heute-Tab (V2-Dashboard, nur `canManageShifts`): „Jetzt im Dienst"-Karte aus vorhandenem `ongoingEntries`-Stream (Wiederverwendung `_ActiveEmployeesCard`-Logik aus `stempel_screen.dart:349` → als wiederverwendbares Widget nach `lib/widgets/` heben). (b) Kiosk-Board-Kachel „Wer ist im Dienst" aus `kioskPresence/{siteId}` (nur Vornamen — Kachel-Entscheidung #2), gepflegt über den `onClockEntryWritten`-Trigger (§3.2 — deckt Callable- UND Direct-Write-Pfad).
`Geeignet für: Opus`

**PA-4.6 Reconnect-Refetch.**
`ZeitwirtschaftProvider` (+ PersonalScreen-Monats-Loader) hören auf `ConnectivityStatusProvider`: bei offline→online-Flanke Einmal-Reads (`_loadMonthEntries`, `loadSnapshots`, `getOrgWorkEntriesForMonth`) neu laden; hybrid-Fallback-Buchungen (nur-lokal) bekommen einen sichtbaren „ausstehend"-Badge und einen Rück-Sync-Versuch bei Reconnect (`syncLocalStateToCloud`-Wiederverwendung, idempotent über deterministische Doc-IDs).
`Geeignet für: Fable 5` (Idempotenz-/Doppel-Write-Risiken beim Rück-Sync)

**PA-4.7 Stempel-Ereignis-Push (schmal).**
Trigger `onClockEntryWritten` NUR für Klärungsfälle (`status=='klaerung'`, z. B. vergessenes Ausstempeln) → Manager, Kanal `personal`. Bewusst KEIN Push pro normalem Stempel (Spam; Live-Sicht deckt das ab).
`Geeignet für: Opus`

---

### PA-5 · Monatsabschluss = echte Festschreibung

**PA-5.1 Dreifach-Enforcement des Locks.**
(1) **Client:** `WorkProvider`-/`ZeitwirtschaftProvider`-Mutatoren prüfen vor jedem WorkEntry-/ClockEntry-Write den `ZeitkontoSnapshot` des Zielmonats (`abgeschlossen` → deutsche Fehlermeldung „Monat ist festgeschrieben"). (2) **Callable:** `upsertWorkEntry`/`upsertWorkEntryBatch` + neue clockIn/clockOut prüfen serverseitig → `failed-precondition`. (3) **Rules — nur für `workEntries`**, mit zwei zwingenden Details: **(a) exists()-Zweig:** der laufende Monat hat per Definition NIE einen Snapshot (entsteht erst beim Abschluss) — die Bedingung MUSS `!exists(snapPath) || get(snapPath).data.abgeschlossen != true` lauten, ein nacktes `get()` würde ALLE normalen Writes denyen; Doc-ID-Konstruktion inkl. Monat-Zero-Padding (`buildId` = `$userId-$jahr-${mm.padLeft(2,'0')}`, `zeitkonto_snapshot.dart:77-78`) in Rules per Conditional nachbauen. **(b) UTC-sicher nur bei workEntries:** `WorkEntry.date` ist auf 12:00 LOKAL normalisiert → UTC-Monatsableitung in Rules ist immer korrekt; `ClockEntry.kommen` ist der echte Stempelzeitpunkt (00:00–01:59 lokal = UTC-Vormonat) → für `clockEntries` wird der Lock NUR in Client+Callable durchgesetzt, nicht in Rules (bewusste, dokumentierte Grenze statt Timestamp-Arithmetik-Bugs an Monatsgrenzen). `zeitkontoSnapshots`-update nur wenn `!resource.data.abgeschlossen`, Reopen (`applyUnlock`) admin-only. Klärungsfälle als zusätzlicher Abschluss-Blocker in `monatsabschluss_service.dart`. Emulator-Test: Write in Monat OHNE Snapshot muss durchgehen.
`Geeignet für: Fable 5` (Rules-get-Kosten/Korrektheit über 3 Enforcement-Punkte synchron — Kopplung #6-artig)

**PA-5.2 Pro-MA-Abrechnungssperre (ida Nr. 10 / Teil von M-L-b).**
Nach Lohnlauf-Freigabe (`PayrollStatus.freigegeben`) gilt der MA-Monat als abgerechnet (`abgerechnetBis`-Semantik über den vorhandenen Snapshot-Lock); Aufheben nur admin mit Audit.
`Geeignet für: Beide`

---

### PA-6 · Lohn-Vervollständigung (Gehaltsabrechnungs-Lücken L9)

**PA-6.1 Verlustfreie Persistenz + PDF.**
`PayrollResult.buildRecord` persistiert Minijob-Pauschalen + U1/U2/InsO/UV als Einzelfelder (§3.2, Kopplung #1: 6 Stellen); `pdf_service._payrollTable` rendert `lines` (§3b/VwL/Einmalzahlung) + AG-Aufschlüsselung; Richtwert-Disclaimer bleibt pflicht.
`Geeignet für: Opus` (klar spezifiziert, Rechenkern unangetastet)

**PA-6.2 Lines-Verrechnung (M-L-b / konsolidierung-L5).**
`PayrollCalculator.calculate` verrechnet steuer-/sv-pflichtige Line-Anteile in die Bemessung (§3b net-neutral, `steuerfreiAnteilCents`/`svFreiAnteilCents` respektieren, Doppelzählung mit Grundlohn ausschließen); Überstunden-Auszahlung als Lohn-Line reduziert das Stundenkonto (`ausgezahltMinutes` existiert am Snapshot). Golden-Zahlen-Tests gegen handgerechnete Fälle.
`Geeignet für: Fable 5` (komplexe Businesslogik mit Steuer-/SV-Semantik)

**PA-6.3 Lohnjournal + DATEV-Lohn (M-D, hinter Feature-Flag).**
Monats-Lohnjournal als CSV (UTF-8-BOM + `;`, deutsches Excel — Repo-Konvention); DATEV-Lohn-Bewegungsdaten-Export mit `datevLohnartNr` (Mapping als editierbarer Org-Seed, ida-Audit M3: childSick→'K'); SV-/BG-UV-Stammdatenfelder am `EmployeeProfile` ergänzen (aus M-H bewusst hierher verschoben); `PayrollSettings.defaults2026` echte BBG-/PV-Werte pflegen.
`Geeignet für: Beide` (Export-Formatdesign/Feldmapping: Fable 5; CSV/PDF-Implementierung + Tests: Opus)

---

### PA-7 · Self-Service-Ausbau + Status-Workflow

**PA-7.1 Lohnzettel-Selbstsicht.**
**— UMGESETZT (2026-07-03):** Rule self-Zweig auf `status in ['freigegeben','bezahlt']` beschränkt + Composite-Index `payrollRecords(userId,status)`; `watchPayrollRecordsForUser` (whereIn) + PersonalProvider-Self-Stream; `_LohnabrechnungenCard` in Meine-Akte mit PDF-Download über `exportPayrollPdf`. Test grün.
Client-Konsument für die existierende payrollRecords-Self-Read-Rule: Liste „Meine Lohnabrechnungen" in der Meine-Akte (nur `freigegeben`/`bezahlt` — Entwürfe bleiben unsichtbar). **Rules sind keine Filter:** die Statusbedingung muss in die QUERY (`where userId ==` + `where status whereIn ['freigegeben','bezahlt']`) UND in die Rule — ein reiner Post-Fetch-Filter würde den ganzen Listen permission-denied machen; Composite-Index-Bedarf (`payrollRecords(userId, status[, …])`) prüfen und in `firestore.indexes.json` aufnehmen. PDF-Download über den bestehenden `exportPayrollPdf`-Pfad (statisch, ungegated — self-service-tauglich verifiziert). Self-scoped Stream im PersonalProvider (Nicht-Admin-Zweig).
`Geeignet für: Beide` (Rules-Zusatz + Provider-Gating: Fable 5; UI/Download: Opus)

**PA-7.2 Urlaubskonto-Selbstsicht.**
**— UMGESETZT (2026-07-03):** Self-Read-Rules für `urlaubskontoJahre`/`urlaubsanpassungen` + `watch*ForUser` + PersonalProvider-Self-Streams → `urlaubsReportFor(self)` in Meine-Akte hat jetzt korrekten Vortrag/Anpassungen (`_UrlaubCard` zeigt Anspruch/Rest). (AppKontoTile-Detailaufstellung ist optionaler Feinschliff.)
Self-Read-Rules für `urlaubskontoJahre`/`urlaubsanpassungen` (M7a-Muster; Doc-ID `{userId}-{jahr}` + `resource.data.userId`-Check); „Mein Urlaubskonto" mit `AppKontoTile` (Anspruch/Vortrag/verbraucht/Rest) in Meine-Akte — ersetzt die selbst-editierbare Näherung der `_VacationQuotaCard`.
`Geeignet für: Beide`

**PA-7.3 EmployeeStatus wirksam machen (L10).**
`isCurrent` filtert: Personal-Übersicht (Segment „Aktive/Alle"), Team-Mitgliederliste, Autoplan-Kandidaten (`ShiftAutoAssigner`-Input in `proposeAutoAssignment`), Kiosk-Roster-Projektion. Offboarding-Assistent am Akte-Kopf bei `exitDate`: Checkliste (isActive=false setzen → /gesperrt-Gate, Kiosk-PIN reset, FCM-Token-Deregistrierung, Dokumente-Aufbewahrung starten (PA-8), offene Lohnläufe prüfen). Onboarding: „Mitarbeiter anlegen"-Wizard bündelt Invite + Vertrag + Sollzeit-Profil + Akte-Grunddaten in einem Flow (statt 3 getrennter Orte).
`Geeignet für: Fable 5` (Status→isActive-Kopplung berührt Auth-Gate + Planner + Kiosk — riskante Mehrdatei-Änderung)

**PA-7.4 HR-Push-Ereignisse. — TEILWEISE UMGESETZT (2026-07-03)**
`onPayrollRecordWritten`-Trigger: Status-Übergang → `freigegeben` pusht an den Mitarbeiter (`buildPayrollReleasedNotification`, Deep-Link „Meine Akte", Kanal `aufgaben` statt neuem `personal`-Kanal — bewusst, wie PA-3.5). node --test 30/30. **Offen (Folge):** Monatsabschluss-abgeschlossen-Push (zeitkontoSnapshots-Trigger), Geburtstags-/Jubiläums-Dashboard-Karte.
`Geeignet für: Opus`

---

### PA-8 · DSGVO & Audit-Vervollständigung

**PA-8.1 Aufbewahrung & Löschung (ida-Audit M12, erstmals gebaut).**
Kategorie→Frist-Defaults (Lohnunterlagen 6 J. §41 EStG, Arbeitszeitnachweise 2 J. §16 ArbZG, Verträge/Zeugnisse bis Austritt + 3 J.); `retentionUntil` beim Upload vorbelegt (überschreibbar); Admin-Ansicht „Ablaufende Aufbewahrung"; **admin-getriggerte** Löschung/Anonymisierung nach Austritt+Frist (Storage-Objekt + Metadaten + Akte-Anonymisierung; Audit loggt; Rechtsgrundlage Art. 17 Abs. 3 lit. b als Begründungstext). Kein Auto-Delete (bewusst: Betreiber entscheidet).
`Geeignet für: Fable 5` (Löschkonzept über Storage+Firestore+Audit konsistent)

**PA-8.2 Art.-15-Auskunft.**
„Meine Daten exportieren" in Meine-Akte: eigene Akte + Verträge + Lohnzettel-Liste + Dokument-Liste als PDF über den bestehenden PdfService/ExportService-Pfad.
`Geeignet für: Opus`

**PA-8.3 Serverseitiges Audit. — UMGESETZT (2026-07-03)**
`writeAudit()`-Helper in `functions/index.js` (best-effort, Admin SDK umgeht Rules, wirft nie, `action∈created/updated/deleted/corrected`, Zusatzfelder `sessionId`/`deviceId`/`source:'server'`). Verdrahtet: `kioskClockPunch` (in/out → „Stempelung"), `kioskBeginSession` (→ „Kiosk-Anmeldung"), `resetKioskPin` (→ „Kiosk-PIN"). `ctx`-Param für `requestId` ergänzt. node --test 30/30. **Offen (Folge):** Fehlschlag-Audit (falsche PIN), `setKioskPin`, und der `AuditLogEntry`-Dart-Reader um `sessionId`/`deviceId` erweitern (aktuell schreibt der Server sie, der Reader ignoriert sie).
`Geeignet für: Beide` (Helper-Design: Fable 5; Trigger-Verdrahtung + Tests: Opus)

---

### PA-9 · Deploy & Verifikation (gebündelt, Blaze)

1. **Commit-Hygiene zuerst:** aktueller Arbeitsbaum trägt uncommittete Phase-0-/Scanner-/MHD-Stände — vor PA-Beginn trennen und committen (Redesign-Plan-Auflage).
2. Firebase Storage in der Console aktivieren (EU-Region passend zu `europe-west3`).
3. `firebase deploy --only firestore:rules,firestore:indexes` — enthält auch die **ausstehenden** Blöcke (clockEntries/zeitkontoSnapshots/M7a-Self-Read + Index `clockEntries(userId,kommen)`) plus alle PA-Blöcke.
4. `firebase deploy --only functions` — Kiosk-Callables (I2-Rest), Push-Trigger, neue clockIn/clockOut/Dokument-Trigger.
5. `firebase deploy --only storage` (neu im Deploy-Satz).
6. Emulator-Verifikation: `kioskClockPunch`-WorkEntry-Shape (bislang „emulator-pending"!), {userId}-open-Guard-Race (zwei parallele clockIn), Kiosk-Profil-Regressionstest (PA-0.1), Storage-Rules-Matrix (admin/self/fremd/kiosk).
7. App-Check-Enforcement auf App-Callables bleibt Go-Live-Schalter (bewusst, Dev/Demo-Verträglichkeit).
8. **Kiosk-Rolle scharfschalten ZULETZT (Security-Review 2026-07-03):** Die PA-0.1-`!isKiosk()`-Denies sind bereits deployt und schlummern, solange kein `role:'kiosk'`-Konto existiert. Ein solches Konto (mit `permissions:false`-Overrides) erst provisionieren, NACHDEM PA-4.4 (b) `kioskRoster`-Umstellung UND (g) InventoryProvider-Kiosk-Read-Unterdrückung ausgerollt sind — sonst ist das Kiosk-Board sofort tot (leere Namensliste + InventoryProvider-Fehlerzustand). Deploy-Reihenfolge der Verträge-Rule (PA-0.2) bleibt: **Client-Release (self-Query) VOR Rules-Deploy.**

`Geeignet für: Beide` (Verifikations-Interpretation: Fable 5; Ausführung/Doku: Opus)

---

## §5 Tests & Definition of Done

- **Pro Paket:** `flutter analyze` clean, `flutter test` komplett grün (Fakes, kein echtes Firebase; `FakeFirebaseFirestore`-Zahlen als double asserten), Functions-Anteile mit `node --test`.
- **Neue Pflicht-Tests:** EmployeeDocument-Roundtrip (beide Serialisierungen); PersonalDocumentsProvider (admin- vs. self-Stream, local-Modus-Hinweis, Kiosk nie); {userId}-open-Guard (create-only + ongoing-Query in der Transaktion, clockOut-Transaktion, Legacy-ID-Zweig, Übergangsphase mit Alt-offener Buchung); Festschreibungs-Guard in allen 3 Schichten (Client-StateError, Callable failed-precondition simuliert via `cloudFunctionInvoker`, Rules per Emulator); Lines-Verrechnung Golden-Zahlen; Self-Read-Sichtbarkeit (MA sieht nur `visibleToEmployee`/`freigegeben`); Kiosk-`_ClockTile`-Fehlerpfad (Callable wirft `unavailable` → Meldung statt Hänger).
- **Coverage-Ziel:** kritische neue Provider/Services ≥ 70 % (`flutter test --coverage`, Repo-Konvention).
- **Manuelle Abnahme (Betreiber):** Tablet einstempeln → Handy/Web zeigen es live; Handy ausstempeln → Tablet-Status stimmt nach Refresh; Doppel-Stempel-Versuch von zwei Geräten → zweiter schlägt mit deutscher Meldung fehl; Dokument hochladen → MA bekommt Push, sieht + lädt es auf allen drei Plattformen; festgeschriebener Monat verweigert Nachbuchung auf allen Pfaden.

## §6 Offene Entscheidungen (Betreiber)

| ID | Frage | Empfehlung |
|---|---|---|
| E-P1 | Teamlead-Zugriff auf Akten/Stundenkonten seines Teams? | Default **nein** (Matrix §3.3); Rules-Zeile vorbereitet, später öffnbar |
| E-P2 | Darf der MA Kontaktdaten (Telefon/Adresse/Notfallkontakt) selbst ändern? | Phase 1 read-only + „Admin melden"; Selbst-Pflege ggf. später als Callable (validiert + auditiert) |
| E-P3 | Bankverbindungs-Änderung | immer admin-only (Betrugsrisiko) |
| E-P4 | `clockEntries`-Rules auf Callable-only umstellen (Direct-Write zu)? | erst zum Go-Live, zusammen mit App-Check-Enforcement |
| E-P5 | Lesebestätigungs-Pflicht für bestimmte Dokument-Kategorien (z. B. Unterweisungen)? | optional pro Dokument (Schalter existiert via `acknowledgedAt`), keine Pflicht-Logik in Phase 1 |
| E-P6 | Dokument-Limit 15 MB / pdf+jpg+png ausreichend? | ja für Phase 1 |
| E-P7 | `local`-Speichermodus für Personal-/Zeitdaten ganz sperren? | nein — nur dauerhafter Hinweis-Banner (Demo-/Notbetrieb erhalten) |

## §7 Sequenzierung mit anderen Plänen

- **Vor Redesign Teil C:** PA-0/PA-1 (Datenmodell/Ownership) MÜSSEN vor PV-M3 („Meine Vorgaben") und PV-M4/PV-M5 (Team-/Personal-Optik) liegen — sonst wird deprecates UI hübsch gemacht. Zeit-Rollout Z1–Z7 nach PA-4/PA-5.
- **Kiosk-Kachel-Plan:** PA-0.1 = A0 (dort blockierend), PA-4.5(b) = A2-Presence — im Kachel-Plan als „durch Personal-Plan erledigt" markieren, nicht doppelt bauen.
- **Zeitwirtschaft-Plan:** M7b nach PA-4.2 als erledigt markieren; Deploy-Reste wandern in PA-9.
- **Konsolidierungs-Plan:** M1/M5 (PA-1), Z2 (PA-4.3) referenzieren.

## §8 Memory-/Plan-Pflege

Nach jedem Meilenstein: Status-Häkchen hier im Dokument + Memory-Eintrag aktualisieren; betroffene Fremd-Pläne (§7) mit Querverweis versehen statt Inhalte zu duplizieren.
