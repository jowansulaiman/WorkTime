# Plan: Personalbereich & Personalverwaltung aus IDA übernehmen

> **Auftrag (Nutzer, 2026-06-22):** Den Personalbereich & die Personalverwaltung aus dem
> IDA-Ökosystem nach WorkTime übernehmen — **ALLE Punkte in der Tiefe**: Gehalt/Lohn (inkl.
> Gehalt-vs-Stundenlohn), Urlaub, Zeit, Sozialversicherung, Sollzeiten, Stundenkonto/Über-
> stunden, Mantelzeiten/Stempeln, Abwesenheit/Krankheit/EAU, Qualifikationen/Ausbildung,
> Kinder, Recruiting, Schichten, Monatsabschluss/Abrechnung, DATEV, Reports. UI analysieren
> und konkrete Muster übernehmen.
>
> **Quellen:** `ida` (PHP/Vue-ERP, kanonische Rechen-/Geschäftslogik in
> `ZEITEN_functions.inc.php`/`hr_*`/`zeit_*`), `ida_app` (Flutter, UI/UX-Vorlage: Stempeln,
> Terminal, Stundenkonto-Tiles, Anträge), `idadwh` (Node/TS, DATEV-LuG-Brücke).

Dieser Plan ist der direkte Nachfolger von `plan/personal-finanz-ausbau.md` (M-A Stammakte,
M-B Lohn/Steuer/Lohnlauf, M-C Finanzen/DATEV-EXTF sind dort **erledigt**). Hier geht es um die
**zweite Ausbaustufe**: Zeitwirtschaft (Stundenkonto, Mantelzeit/Stempeln, Sollzeit), die
**Brücke Zeit→Lohn** (Gehalt vs. Stundenlohn, automatische Brutto-Herleitung), das volle
Urlaubs-/Abwesenheitsregime (BUrlG werktagsgenau), Lohnarten/Zulagen inkl. §3b-Zuschlägen,
VwL, Einmalzahlungen, AG-Umlagen (U1/U2/InsO), SV-/DATEV-Stammakte, Qualifikation/Ausbildung/
Kinder, Monatsabschluss, DATEV-Lohn und (Phase 2) Terminal/Recruiting.

> **Review-Konsequenzen, die in DIESE Fassung eingearbeitet sind** (Kurzform, Details inline):
> Drei parallele Urlaubsquellen + Migration (M0/§5.1), BUrlG-**Werktags/Teilzeit**-Umrechnung +
> 31.3.-Verfall + Hinweisobliegenheit (§5.1/§5.2), **Gehalt-vs-Stundenlohn** + automatische
> Brutto-Herleitung (neuer M-B0), §3b-Zuschläge / VwL / Pfändung / Einmalzahlungen-§39b /
> U1/U2/InsO / BG-UV (§4.3/§5), EFZG-6-Wochen-Grenze + **Anrechnungsmatrix je AbsenceType**
> (§5.4a), Kinder-**Einzelquelle** (§4.4), **admin-only statt self-read** ACL (§4/Rules),
> **pro-MA-Abrechnungssperre** statt org-globalem Monatsabschluss (§4.5), Compliance-Spiegel
> für das **Event-Modell** als eigenes Aggregat (§5.10, eigener Aufwand), risiko-/nutzen-
> orientierte **Meilenstein-Umsortierung** (M0 → M-U → M-H → M-Settings → M-B0 → Mantelzeit/
> Terminal zuletzt), und **userContent-vs-Stammdaten-Hybrid-Spiegelung je Collection** (§4.0).

---

## 0. Audit-Korrekturen (2026-06-22, adversariales Multi-Agenten-Review)

> Dieser Plan wurde durch ein 6-Linsen-Audit (Codebase-Fit · IDA-Quelltreue · dt. Lohn-/Arbeitsrecht ·
> Architektur/Security/Spark-Kosten · Meilenstein-Sequenz · Vollständigkeit) gegen den **echten**
> WorkTime-Code, die **echten** IDA-Quellen (`ida`/`ida_app`/`idadwh`) und das Gesetz geprüft; jeder Fund
> wurde adversarial gegenverifiziert (35 bestätigt, 6 verworfen). **Diese Korrekturen gehen den §-Abschnitten
> unten vor.** Load-bearing-Funde (B1, H4/H5/H6) sind zusätzlich **inline** eingearbeitet.
>
> **Verhältnis zu §11:** §11 (Verifikations-Anhang) prüfte v. a. **Quelltreue/Schema** (Tabellen-/Funktionsnamen).
> Dieser §0 ergänzt **Korrektheits-, Sequenz- und Security-Funde**. Wo beide überlappen, bestätigen sie sich
> unabhängig (IDA kennt keinen Verfall → K8≙M2; `PayrollProfile.monthlyGrossCents` existiert → §11.2≙M1;
> `_midijobBase` reduziert beide Zweige gleich → §11.3≙H1). **Neu ggü. §11** ist v. a. der BLOCKER B1: die
> **plan-interne** Inkonsistenz der Teilzeit-Formel (6-Tage-Basis) mit den migrierten 5-Tage-Bestandswerten.

**🔴 BLOCKER**
- **B1 — BUrlG-Teilzeit doppelt skaliert: 5-Tage-Vollzeitler bekäme 25 statt 30 Urlaubstage.** §4.1/§5.1
  deklarieren `urlaubstageJahr` als 6-Tage-Basis und teilen durch `urlaubsbasisWerktage=6`; M0 migriert aber die
  **5-Tage**-Bestandswerte (`EmploymentContract.vacationDays=30`, `weeklyHours=40` → verifiziert
  `employment_contract.dart:40-44`) **verbatim** hinein → 30×(5/6)=25 für JEDEN Bestands-MA, gesetzwidrig.
  **Fix (Option A, gewählt, inline):** `urlaubstageJahr` = **5-Tage-Woche-Basis (vollzeit-äquivalent)**,
  `urlaubsbasisWerktage` **Default 5**, M0 kopiert ohne Skalierung; gesetzl. Mindesturlaub (20 Tage/5-Tage)
  als separater Cross-Check. Tests: 5-Tage-Vollzeit 30→30; 3-Tage-Teilzeit→18; M0-Round-Trip senkt Vollzeit nicht.

**🟠 HIGH**
- **H1 — 2026-Sätze sind FALSCH, nicht nur „Platzhalter + Disclaimer".** `defaults2026()` trägt 2025-Werte:
  Minijob 556 € statt **603 €**, Mindestlohn 12,82 € statt **13,90 €** (`payroll_settings.dart:155/157`). Die
  Minijob-Grenze ist die Midijob-Untergrenze `g` in `_midijobBase` (`payroll_calculator.dart:259`) → falsche
  beitragspflichtige Einnahme 556–603 €, und `isBelowMinimumWage` greift unter 13,90 € nicht. **Fix:** echte
  2026-Zahlen in `defaults2026()` (60300 / 1390), `midijobFactorF` 2026 verifizieren, Test
  `payroll_calculator_test.dart:113-114` anziehen. ⚠️ **Eigener Code-Fix (kein reiner Plan-Edit).**
- **H2 — App Check ist client-aktiv, aber server-seitig NICHT erzwungen.** Kein `onCall` in `functions/index.js`
  setzt `enforceAppCheck:true`; `main.dart:151-165` ist bewusst fail-open. „App Check" als Terminal-Schutz (E1)
  gibt sonst Scheinsicherheit. **Fix:** `enforceAppCheck:true` auf neue Callables (terminalAuth/clockIn/…) UND
  Retrofit der 5 bestehenden; + Replay-Schutz (Nonce/Server-Dedupe) + Device-Binding; `terminalLockouts/{deviceId}`
  nur per Callable schreibbar, Direct-Write in Rules **deny**.
- **H3 — clockIn/clockOut nach dem `workEntries`-Direct-Write-Muster reißt das Compliance-Loch + die
  pro-MA-Abrechnungssperre auf.** Ein Direct-Write umgeht `assertNichtAbgerechnet` und das §5.10-Aggregat.
  **Fix:** Für `mantelzeiten` in `firestore.rules` **alle** Client-Writes verbieten → **callable-only**;
  zusätzlich Defense-in-Depth-Guard `allow update,delete: if !resource.data.abgerechnet &&
  !resource.data.tagesabschluss`. §8-Regel 8/9 um den Rules-Enforcement-Punkt ergänzen.
- **H4 — Meilenstein M-L steht VOR M-Z1, hängt aber von dessen `ZeitkontoSnapshot.abgerechnet`/Stundenkonto ab**
  (Saldo = Ist−Soll, `ZEITEN_functions.inc.php:1080`). **Fix:** M-L **splitten** → **M-L-a** (statische Lines +
  §3b/VwL/Einmalzahlung + Grundlohn-Line, nur M-B0 nötig) bleibt früh; **M-L-b** (Überstunden-Auszahlung +
  Konto-Reduktion + pro-MA-Sperre) **nach M-Z1**. Reihenfolge inline aktualisiert.
- **H5 — M-U-Teilzeiturlaub auf Sollzeit-„Stub" liefert falsche Zahlen.** IDA zählt genommene Tage aus
  **per-Wochentag-Sollzeit** (`CAL_functions.inc.php:127-128`, Tag zählt nur bei `sollstunden>0`) — genau die
  Minijob/Teilzeit-Population, die §5.1 als kritisch nennt. **Fix:** das **per-Wochentag-`SollzeitProfile`-Modell**
  (7 Tagesfelder + `effektiveArbeitstage`/`sollMinutesForWeekday` + admin-CRUD) **vor M-U** ziehen;
  `ZeitkontoSnapshot`/Calculator/Mantelzeit bleiben im späteren M-Z1/M-Z2. (Reihenfolge inline.) Bezug „M-Stamm"
  in §7 Z.675 existiert nicht — durch dieses Sollzeit-Modell-Stück ersetzen.
- **H6 — Feiertagskalender liest `EmployeeProfile.federalState` — das Feld existiert nicht** (verifiziert: kein
  `federalState` in `employee_profile.dart`; es lebt auf `SiteDefinition.federalState:51`). Folge: SH-Spezifika
  (Reformationstag, gesetzl. Feiertag in SH seit 2018) gehen verloren → Soll/Urlaub falsch. **Fix (inline):**
  Bundesland aus dem **Standort** (`SiteDefinition.federalState` via `EmployeeSiteAssignment`, Org-Default
  „Schleswig-Holstein") auflösen, KEIN redundantes Per-MA-Feld; `feiertage.dart`-Vertrag explizit machen
  (Oster-Computus, SH-Reformationstag), Tests.
- **H7 — Gleichzeitiges Stempeln (zwei Geräte / Doppeltap) erzeugt zwei offene Buchungen.** Der einzige analoge
  Callable `upsertWorkEntry` macht read-then-write **ohne** Transaktion (`functions/index.js:588-601`). **Fix:**
  offene Buchung mit **deterministischer Doc-ID** `mantelzeiten/{userId}-open` + create-only (Rule verbietet
  Overwrite) ODER `clockIn` server-seitig in `runTransaction` (Muster `firestore_inventory_repository.dart:215`);
  Concurrency-Test ergänzen (zweiter clockIn auf stale State → genau eine offene Buchung).

**🟡 MEDIUM**
- **M1 — Doppelte Festgehalt-Quelle:** `PayrollProfile.monthlyGrossCents` existiert bereits
  (`payroll_profile.dart:41`, Lohnlauf-Prefill `personal_screen.dart:1995`). Neues
  `EmploymentContract.monthlyGrossCents` ohne Vorrangregel = 4. divergierende Quelle (verletzt §1-Einzelquelle).
  **Fix:** Contract = kanonisch (versioniert), PayrollProfile = Prefill-Cache, M0-Backfill + Vorrang dokumentieren.
- **M2 — IDA-Fehlattribution Resturlaub-Verfall:** `zeitfunc_getResturlaubByTimestamp` (`ZEITEN_functions.inc.php:818-873`)
  trägt den Vorjahresrest **unbegrenzt/verfallfrei** fort und subtrahiert kein `geplant`. 31.3.-Verfall +
  Hinweisobliegenheit + `−geplant` sind **eigene** (gute) EuGH/BAG-Erweiterungen, **nicht** aus IDA. §3-Tabelle Z.155 /
  Leitentscheidung #4 / Header Z.24 entsprechend als „NEU ggü. IDA" kennzeichnen.
- **M3 — DATEV-Mapping ist in IDA eine konfigurierbare DZeLt-Regel-Engine, keine statische Tabelle;** die zitierten
  Codes sind der **Stamer**-Mandanten-Fallback (`ZeitUndLohndatenExport.ts:162-198`). **Faktenfehler:** §5.4a mappt
  `childSick`→Ausfallschlüssel **„KK"**, existiert nirgends — IDA: erkrankung_kind = **„K"** (Lohnart 1657). **Fix:**
  childSick→„K"; `datev_lohn_mapping.dart` als **editierbarer Org-Seed** (Stamer-Werte nur Beispiel) statt
  kanonisch; §9 um „Schwellen-bedingte Code-Auswahl bewusst weggelassen" ergänzen.
- **M4 — `Mantelzeit.nettoMinutes` plättet IDAs Tag-Netto** (`netto = anwesenheit − pause − fakultativ − rahmenzeit −
  gekappt`, `HR_functions.inc.php:2015`; Auto-Pflichtpause nur als **Fehlbetrag** zu gestempelten Lücken,
  `ZEITEN_functions.inc.php:2926-3035`). Ein flaches `pauseMinutes` kann „Pause nur abziehen, wenn nicht schon
  gestempelt" nicht. **Fix:** Pausen-/Netto-Berechnung auf **Tagesebene** in `stundenkonto_calculator.dart` (gleicher
  Seam wie §5.10-Aggregat); `pauseMinutes` nur noch manueller Override. Rahmenzeit/Karenz/Kappung bleiben E3.
- **M5 — Stempel-Rundung/Karenzzeit gehört nach M-Z2, nicht E3:** IDA rundet **beide** Stempel-Enden
  (`zeitfunc_unixTimestampRunden`, `ZEITEN_functions.inc.php:3848-3873`; Ende `_job_functions.inc.php:314`) mit
  Ausnahmen (nicht runden wenn Tagesarbeit schon erfolgt / in Karenzzeit). Rundung mutiert jedes Netto. **Fix:**
  In M-Z2 **entscheiden** — entweder bewusst „keine Rundung (exakte Minute)" dokumentieren, oder `azRunden:bool`
  → `azRundenStart/Ende`+`azRundenAufMinutes` server-seitig. Nicht still nach E3 schieben.
- **M6 — EFZG-„42-Tage je Fall" über-bezahlt systematisch und ist lohnwirksam** (speist §5.6 Brutto). Ohne Einheit-
  des-Verhinderungsfalls + 6-/12-Monats-Frist (§3 Abs.1 S.2 EFZG) vergibt der naive Zähler frische 42 Tage. **Fix:**
  überlappende/lückenlos angrenzende `sickness` zu EINEM Fall ketten (Zähler **nicht** zurücksetzen); frische 42 Tage
  nur nach ≥6 Monaten krankheitsfrei; Disclaimer „tendenziell zu hoch" + Hinweis auf Brutto-Durchschlag; Test.
- **M7 — `getMySelfService()`-Projektion ist die TEURERE, nicht die Spark-frugale Variante** (Function-Invocation +
  N admin-Reads pro View; Functions brauchen ohnehin **Blaze**, CLAUDE.md zielt auf Spark). **Fix:** denormalisiertes
  `selfService/{userId}`-Doc, von den Callables/Abschluss geschrieben, vom MA **direkt gelesen** — Rule-Prädikat exakt
  wie `workEntries`/`absenceRequests` (`firestore.rules:492-500`, schon erprobt — widerlegt „self-read unausgereift").
  Live-Timer braucht nur den `kommen`-Timestamp daraus (kein Re-Poll). `getMySelfService()` nur als Fallback.
- **M8 — M0-Schritt „WorkEntry→Ist-Minuten als Stundenkonto-Startwert" hat kein Ziel** (Stundenkonto/Sollzeit erst in
  M-Z1). **Fix:** Bullet aus M0 entfernen (inline), als **Eröffnungs-Snapshot** nach M-Z1 verschieben; explizit als
  Legacy-Opening-Balance markieren (WorkEntry hat kein `nettoMinutes`/keine Anrechnungsmatrix).
- **M9 — §5.6 „abgerechnete istMinutes" hängt an einer Sperre, die es vor M-Z1/M-Z2 nicht gibt.** **Fix:** §5.6/M-B0
  phasen-explizit: bis M-Z1 nur rohe WorkEntry-Summe + bezahlte Abwesenheit (§5.4a), **ohne** abgerechnet-Filter;
  Forward-Note, dass die Quelle später auf Mantelzeit/Snapshot umschaltet. M-B0-Abhängigkeiten bleiben.
- **M10 — Server-Spiegel (`functions/index.js` inkl. §5.10-Event-Aggregat) bleibt ungetestet** (kein `*.test.js`).
  Drift zwischen Dart-/JS-Spiegel — das §5.10-Risiko — bliebe unentdeckt. **Fix:** reine JS-Unit-Tests
  (`node --test`, kein firebase-admin) für `validateMantelzeitDay`/`aggregateDayEvents` mit **denselben** Fixtures
  wie die Dart-Tests; verletzt „Nie echtes Firebase" nicht. In §10/M-Z2 aufnehmen.
- **M11 — Interaktion Mantelzeit ↔ bestehende Schicht-Completion unadressiert.** Heute markiert
  `WorkProvider`→`ScheduleProvider` die Schicht completed (`work_provider.dart:87`, „einziger direkter
  Provider→Provider-Call"). Mit Stempeln zwei Ist-Quellen. **Fix:** (a) **Ist-Einzelquelle**: sobald Mantelzeit aktiv,
  ist sie maßgeblich (WorkEntry nicht mehr additiv) — Leitentscheidung #2 vs §5.4 auflösen; (b) entscheiden, ob clockOut
  die Schicht completed; Seam in §8-Kopplungen aufnehmen.
- **M12 — DSGVO-Aufbewahrung/Löschung fehlt;** „NIE hart löschen" (Z.261) kollidiert mit Art. 17. **Fix:** §9-Unterabschnitt
  „Aufbewahrung & Löschung": Fristen (Lohnkonten 6 J. §41 EStG, Arbeitszeit 2 J. §16 ArbZG), Rechtsgrundlage
  (Art. 17 Abs.3 lit. b), admin-getriggerter Hard-Delete/Anonymisierung nach Fristablauf (AuditSink loggt).

**⚪ LOW (Präzisierungen, gesammelt):** §3b nennt nur 25 €/h (SV) — **50 €/h-Steuerfreiheitsgrenze fehlt**; U1-Schwelle
„bis 30" (nicht „<30"), gewichtete Kopfzählung; U1/U2/InsO liegen in IDA **nicht** in `hr_lohnnebenkosten` (dort UV),
sondern am Krankenkassen-Satz; „Nacht 23–06 bereits im Spiegel" = ungenutztes gespeichertes Feld; „EmploymentContract
kennt nur hourlyRate" untertreibt (auch `weeklyHours/dailyHours/vacationDays`); Mantelzeit-ACL „exakt wie workEntries"
stimmt nicht (workEntries gewährt self-read); §5.10-Aufwand leicht überzeichnet (Tages-Aggregation/Ruhezeit existiert
für WorkEntry bereits in beiden Spiegeln); **PersonalProvider** soll ~11 neue Collections schlucken → eigener
`ZeitwirtschaftProvider` erwägen; fakultative Überstunden sind in IDA ein echter Soll-Ist-Mechanismus (nicht nur Toggle);
§6.6 „showAbsenceRequestSheet erweitern" untertreibt (Sheet kodiert die 3 AbsenceTypes hart, keine Halbtags-Logik); Plan
ist zu groß für **einen** Durchlauf — explizit in Phase A (M0/M-H/M-Settings/Sollzeit-Modell/M-U) und Phase B
(M-B0/M-L/M-Z/M-MA/M-D) phasen.

> **Verworfen (6, gegenverifiziert nicht stichhaltig):** „IDA-Quellbaum fehlt" (Quellen sind vorhanden);
> Hybrid-Spiegel `mantelzeiten` „stale-cache-Risiko"; „E3 blockt M0"; „Scope-Überinvestition §3b/DATEV/Terminal";
> „Stempeln zu spät einsortiert"; „Test-Bestand 555 vs ~455".

---

## 1. Auftrag & Leitentscheidungen

### Bestätigte Architektur-Leitplanken (ZWINGEND)

- **Nur Domänenmodelle/Logik/UX re-implementieren**, NICHT die IDA-Architektur. IDA ist
  REST/Dio + MobX + Sembast + json_serializable-Codegen. WorkTime bleibt: **provider
  (ChangeNotifier), Hand-Dual-Serialisierung, KEIN bloc/Freezed/Hive/build_runner/Codegen/
  GoRouter-Codegen**, Firestore + SharedPreferences, 3 Speichermodi, Spark-frugal, alles
  `de_DE` (jedes `DateFormat` explizit `'de_DE'`), Geld als `int` Cent (`Money`).
- **Backend-Wahrheit aus IDA wird Client-/Cloud-Function-Logik in WorkTime.** IDA rechnet
  Urlaubsanspruch/Stundenkonto/Sollzeit serverseitig in PHP. WorkTime hat kein solches Backend
  → die **reine Rechenlogik** (BUrlG-Urlaub, Soll/Ist-Saldo, Brutto-Herleitung) wird als
  testbare, dependency-freie Dart-Funktionen in `lib/core/...` implementiert (Muster
  `payroll_calculator.dart`/`german_tax.dart`); nur **validierte Schreibpfade** (Stempeln,
  Monatsabschluss-Sperre) laufen über Cloud Functions (`functions/index.js`).
- **Personal-/Zeit-Verwaltung ist admin-only** (Eingang über Verwaltungsmenü
  `app_nav_menu.dart`, KEIN Bottom-Tab). Mitarbeiterseitige Selbstansicht (Stempeln, eigenes
  Stunden-/Urlaubskonto, eigener Antrag) wird **nicht** über self-read auf Personaldaten
  gelöst, sondern über eine **Cloud-Function-Projektion** — siehe §4.0/Rules (Review-Korrektur).
- **UI nur `lib/ui` (Signal-Teal) + Material 3.** IDA-Muster konzeptionell übernehmen, NICHT
  IDA-Farben (Seed-Rot, `AppColors.success`). Statusfarben strikt über
  `Theme.of(context).appColors` (ThemeExtension `AppThemeColors`), nicht hartkodiert.
- **Compliance-Spiegel:** Jede neue Zeit-/Pausen-/Höchstarbeitszeit-Regel MUSS in
  `compliance_service.dart` UND `functions/index.js` synchron sein. Für das neue Mantelzeit-
  **Event-Modell** (mehrere Kommen/Gehen pro Tag) ist das **kein bloßes „erneut anwenden"**,
  sondern eine neue Tages-Aggregationsschicht — siehe §5.10 (eigener Aufwandsposten).
- **Lohnrelevanz steuert SV/Lohnsteuer aus genau EINER Quelle.** Kinderzähler, Urlaubsanspruch
  und SV-Sätze dürfen nicht aus mehreren divergierenden Feldern gespeist werden (§4.4/§5.1).

### Leitentscheidungen

| # | Entscheidung | Status |
|---|---|---|
| 1 | **Nur Mantelzeit (Anwesenheit, Kommen/Gehen)** — IDAs zweite Ebene (Istzeit/Kostenträger) **entfällt** (E2: nein). Kostenstelle = **Standort**. Reiner Einzelhandel braucht keine produktive Projektzeit. | **E2 entschieden** |
| 2 | **Stundenkonto Soll/Ist/Saldo** als Kern-Neuerung. Soll aus neuem `SollzeitProfile`, Ist aus `WorkEntry`+`Mantelzeit`. Saldo monatlich als Snapshot (`ZeitkontoSnapshot`) fortgeschrieben. | gesetzt |
| 3 | **Sollzeit** als eigenes **gültig-ab-versioniertes** Modell (nicht Feld an `EmploymentContract`), weil IDA es korrekt versioniert (Vertragsänderungen). | gesetzt |
| 4 | **Urlaubskonto** wird real: BUrlG-**werktagsgenauer** + teilzeitskalierter Anspruch (5-Tage-Basis, Audit-Korr. B1) + Vorjahresübertrag (31.3.-Verfall + Hinweisobliegenheit = **NEUE** EuGH/BAG-Erweiterung, **kein** IDA-Pendant — IDA trägt unbegrenzt fort, Audit-Korr. M2) + Anpassungen − genommen − geplant. Zentrale Quelle: `SollzeitProfile.urlaubstageJahr`; `annualVacationDays`/`vacationDays` werden **deprecated + migriert** (M0). | gesetzt |
| 5 | **Abwesenheitsarten** als `(art, status)`-Tupel + zentrale **Anrechnungsmatrix** (§5.4a) für Lohnfortzahlung/Sollanrechnung/DATEV/§3b. Halbtägig (0,5, AM/PM) + Zeitausgleich-in-Stunden. | gesetzt |
| 6 | **Gehalt vs. Stundenlohn** als Lohntyp am Vertrag (`salaryKind`); für Stundenlöhner automatische **Brutto-Herleitung** „erfasste Stunden × Stundenlohn" (eigener M-B0). | gesetzt |
| 7 | **Lohnarten/Zulagen** als org-Lookup (`PayLineType`) + Zuordnung am Lohn (`PayrollRecord.lines`) mit DATEV-Lohnartnummer, inkl. **§3b-steuerfreie Zuschläge**, **VwL**, Einmalzahlungen. | gesetzt |
| 8 | **DATEV-Lohnexport** (Bewegungsdaten tages-/monatsweise) als `ExportService`-Methode; **statische** Ausfallschlüssel-Tabelle (KEINE Formel-Eval). Lohnartnummer-Validierung **weich** (max 4-stellig, kein fester Bereich — Review-Korrektur). | gesetzt |
| 9 | **SV/AG-Sätze editierbar** als `OrgPayrollSettings` (KV-Zusatz, PV, RV/ALV, **U1/U2/InsO**, BBG, Minijob-Grenze) — früher Meilenstein, weil Grundlage jeder Lohn-/AG-Kostenrechnung. | gesetzt |
| 10 | **Monatsabschluss** org-weit als Orchestrierung, ABER **Abrechnungssperre + Klärung pro Mitarbeiter** (`abgerechnetBis` je `userId`) — ein Klärungsfall blockiert nicht die ganze Org (Review-Korrektur). | gesetzt |
| 11 | **Terminal-/Kiosk-Modus** und **Recruiting** sind **Phase 2** (optional, separat) — nicht im Kern-Scope. | gesetzt |

### ✅ Getroffene Entscheidungen (Nutzer, 2026-06-22)

- ✅ **E1 — Terminal-Login-Sicherheit: Empfehlung.** Serverseitige Validierung
  (`terminalAuth`-Callable) + Rate-Limiting (`terminalLockouts/{deviceId}`) + Lockout + App Check +
  org-Pin. Bleibt **Phase 2** (M-X) mit eigenem Security-Review. KEIN client-seitiges `SHA1(PIN+Salt)`
  wie IDA.
- ✅ **E2 — Istzeit/Kostenträger: NEIN.** Keine „produktive Zeit auf Projekt". **Nur Mantelzeit
  (Anwesenheit)**; Kostenstelle = **Standort**. → Istzeit-Buchung, Live-Tätigkeits-Timer und die
  `WorkEntry`-Kostenträger-Erweiterung **entfallen**. Reduziert M-Z2 und das DATEV-Mapping (nur
  Anwesenheits-/Abwesenheits-Lohnarten, keine Kostenträger-Aufteilung).
- ✅ **E3 — Sollzeit: VOLLES IDA-Modell.** `SollzeitProfile` bekommt den kompletten
  `hr_sollzeiten`-Umfang: Tagessoll Mo–So **plus** Kern-/Rahmenzeit je Wochentag, Pausenfenster,
  `pause_karenz`/`kernzeit_karenz`, `az_runden(_auf/_start/_ende)`, `az_maximum`/Kappung,
  `fakultative_ueberstunden(_typ/_zeitraum)`, Gleitzeit, `urlaub_als_stunden`. (Referenz:
  `hr_sollzeiten`.) → M-Z1 ist **Vollausbau** (nicht pragmatisch); Aufwand steigt M → **M–L**.
- ✅ **E4 — Recruiting: Empfehlung (zurückstellen).** M-R bleibt Phase 2.
- ✅ **E5 — DATEV-Lohn: JA.** Modell + Export werden gebaut (M-D), hinter **Feature-Flag**
  (Lohnartnummern mandantenspezifisch). Zusätzlich zum bestehenden DATEV-EXTF (Finanz, M-C).
- ✅ **E6 — „Anrechnung bis Null": Empfehlung (weglassen).** Schlechtwetter/S-KUG bleibt
  out-of-scope (§9).
- ✅ **E7 — Stundenkonto-Snapshot: WIE BEI IDA (verifiziert).** IDA persistiert **einen
  Monats-Snapshot je MA** (`hr_zeitkonto` per `personen_id,jahrmonat` mit
  `stundenkonto/resturlaub/ausgezahlte_stunden`), geschrieben **beim Monats-/Jahresabschluss**
  (`zeitfunc_setJahresabschlussStundenkontoUndUrlaub`); der **laufende** Saldo wird on-demand aus
  Buchungen berechnet (`get_actual_stundenkonto_by_timestamp`). → `ZeitkontoSnapshot` wird **beim
  Monatsabschluss** geschrieben (**kein** nächtlicher Cron), Live-KPI rechnet WorkTime
  clientseitig on-demand (= deckt sich mit der Spark-frugalen Variante).
- ✅ **E8 — Einmalzahlungen: WIE BEI IDA, NICHT vereinfachen (verifiziert).** Befund: **IDA rechnet
  selbst keine Lohnsteuer** — Einmalzahlungen sind Stammdaten-Lohnarten
  (`hr_gehalt.weihnachtsgeld_*`/`urlaubsgeld_*`/`sonstige_praemien`); die korrekte §39b-Abs.-3-
  Besteuerung macht **DATEV** (LODAS-Bearbeitungsschlüssel `ABRUF_JAHRESSONDERZAHLUNG`). →
  WorkTime: (a) Einmalzahlung als eigene `PayLineKind.einmalzahlung`/Sonderbezug, im **DATEV-Lohn-
  Export korrekt als Jahressonderzahlung gekennzeichnet**; (b) für den **eigenen Richtwert** das
  **§39b-Abs.-3-Jahresverfahren** (`german_tax.sonstigerBezugTax(...)`) umsetzen (voraussichtl.
  Jahresarbeitslohn mit/ohne Bezug → Differenz = LSt auf den Bezug). **Keine** „laufender-Monat"-
  Vereinfachung als Default.
- ✅ **E9 — §3b-Zuschläge: VOLL, NICHT vereinfacht.** Volle §3b-Aufteilung steuerfrei/SV-frei vs.
  -pflichtig (Nacht +25 %/+40 %, Sonntag +50 %, Feiertag +125/150 %; SV-Grundlohngrenze **25 €/h**,
  Steuerfreiheit auf Bemessung bis 50 €/h) **direkt in M-L** umgesetzt — **nicht** hinter
  Default-aus-Feature-Flag.

---

## 2. Quellen-Überblick (HR/Zeit-Bereich, kompakt)

| Projekt | Rolle | Kann im HR/Zeit-Bereich | Architektur |
|---|---|---|---|
| **ida** (PHP/Vue) | kanonische Wahrheit | Stammakte (Lohn/SV/Sollzeit historisiert, gültig-ab), anteiliger Urlaubsanspruch (**Kalendertag-Zwölftelung**) + Resturlaub-Saldo (genommen-basiert, **ohne** 31.3.-Verfall), Stundenkonto (Ist−Soll fortlaufend), Mantelzeit-Netto (Pausen/Rundung/Rahmen/Karenz), fakultative Überstunden, Monatsabschluss + LODAS, SV-Beitragsgruppen (AG-Umlagen U1/U2/InsO liegen in `crm_krankenkassen`), Lohnarten/Zulagen/Auszahlungen, Krankenstand-KPI, Recruiting, Teams, Vertreter | PHP-Funktionsbibliotheken + MySQL `hr_*`/`zeit_*` (volle CREATE-TABLE in `__deployment/db/sql/1_ida_master.sql` + 58 datierte `__development/db/migrations/`); Punkt-in-Zeit als unix-ts (Sek.), Perioden als `YYYYMM`/`YYYYMMDD`-Int; mandantenfähig |
| **ida_app** (Flutter) | UI/UX-Vorlage | Stempeln (Kommen/Gehen + FlipFlop), Live-Tätigkeit mit Ticker, Bulk-Nacherfassung, Stundenkonto/Urlaubskonto-ExpansionTiles, Terminal/Kiosk (PIN/NFC, Auto-Logout), Urlaubsantrag-Formular, MA-Auswahl-Sheets, Genehmigungs-/Änderungsantrag-Workflow, Abrechnungssperre, Journal | Dio/GetIt/**MobX**/Sembast, json_serializable, Material 3 (Seed-Rot) |
| **idadwh** (Node/TS) | DATEV-Brücke | DATEV-LuG-Export tages-/monatsweise (Tagesanteils-Verteilung, Industrieminuten, .ini), DZeLt-Mapping-Engine (IDA→DATEV-Lohnart/Ausfallschlüssel), LODAS-Stammdaten, DATEV-HR-Payroll-Rückimport (Lohnzettel), A351K (kundenspez.) | Node/TS, OAuth, ASCII-Festformat |
| **WorkTime** (Ist) | Zielsystem | `EmployeeProfile` (≈34 Felder), `PayrollRecord/Profile/Settings` (inkl. `PayrollProfile.monthlyGrossCents`, `EmployeeProfile.healthInsuranceSurchargePercent`, `careChildlessSurchargeRate` — **bereits implementiert**), `payroll_calculator`/`german_tax` (§32a), `PayrollStatus`-Workflow, Lohnlauf, Finanz/DATEV-EXTF, ShiftPlanner, `WorkEntry`, `AbsenceRequest`, `ComplianceService` (ArbZG-nah) | Flutter/Firebase, provider, Hand-Dual, 3 Modi |

**Kernbefund:** WorkTime hat das **Lohn-Fundament** (Brutto→Netto §32a, Stammakte, Status/
Lohnlauf, DATEV-EXTF-Finanz). Aber: das Brutto wird **manuell** als `PayrollRecord.grossCents`
gepflegt, und `EmploymentContract` kennt nur `hourlyRate` (kein Gehaltstyp). **Es fehlen:** die
gesamte Zeitwirtschaft, die **Brücke Zeit→Lohn** (Stunden×Lohn→Brutto), das echte Urlaubskonto
(werktagsgenau), Lohnarten/Zulagen inkl. §3b/VwL/Einmalzahlung, AG-Umlagen (U1/U2/InsO),
SV-/DATEV-Stammakte, Monatsabschluss und DATEV-Lohn. Das ist der Übernahme-Kern.

---

## 3. Gap-Analyse (granular, jedes Feature)

| Feature | ida-Quelle | WorkTime heute | Lücke | Prio |
|---|---|---|---|---|
| **ZEIT** | | | | |
| Mantelzeit Kommen/Gehen (Stempeln) | ida_app zeit, `hr_mantelzeiten` | nur `WorkEntry` (Tagesmodell, Start/Ende fix) | offene Buchung (Kommen ohne Gehen), Live-Timer, Event-Modell | **hoch** |
| FlipFlop/Quick-Stempeln | ida_app | — | Dashboard-QuickAction „Jetzt stempeln" | mittel |
| Stundenkonto / Soll-Ist-Saldo | `ZeitReportStundenkontoKpi`, `hr_zeitkonto` | nur `overtimeThisMonth`-Getter | Soll aus Sollzeit, Ist-Summe, kumulierter Saldo, KPI heute/Woche/Monat | **hoch** |
| Sollzeit-Modell (Wochenprofil) | `hr_sollzeiten` (gültig-ab) | `EmploymentContract.weeklyHours/dailyHours` (pauschal) | Tagessoll je Wochentag, Feiertag=0, Halbtag, Versionierung | **hoch** |
| Pausen-/Rundung-/Rahmenzeit | `zeitfunc_getMantelzeitInfoByDay` | Compliance prüft nur (30@6h/45@9h) | Netto-Berechnung mit Pausenabzug/Rundung/Karenz | mittel |
| Fakultative Überstunden / Kappung | `hr_sollzeiten` | — | freiwillige, nicht angerechnete Überstunden | niedrig |
| Live-Tätigkeitserfassung (Timer) | ida_app `ZeitErfassung` | — | ~~offene Buchung auf Kostenträger~~ **entfällt (E2: nein)** | — |
| Istzeit/Kostenträgerbuchung | `hr_zeitwirtschaft` | `WorkEntry.category/siteId` | ~~Kostenstelle/Projekt/Tätigkeit als FK~~ **entfällt (E2: nein)** — Kostenstelle = Standort genügt | — |
| Tagesabschluss (Tag sperren) | `hr_zeit_tagesabschluesse` (Schlüssel `tag`=YYYYMMDD-int) | — | Tag read-only | mittel |
| **Abrechnungssperre (`abgerechnetBis`) pro MA** | Vue `state.hr.abgerechnetBis` (`ZeitCheckList.vue`); `ZeitAbrechnungsstatus` ist ida_app-Flutter | — | gesperrte Perioden immutable, **je userId** | **hoch** |
| Journal (Tag/Woche-Ansicht) | ida_app zeit | `month_report_screen` | Wochentags-Summen | mittel |
| Änderungsantrag Zeitbuchung | ida Genehmigung | nur Abwesenheits-Antrag | Antrag statt Direktedit (ACL-gated) | mittel |
| Klärungsfälle (needs-review) **pro MA** | ida-vue zeit | — | Flag + Sammel-Reset, blockiert Abschluss **dieses MA** | mittel |
| **URLAUB / ABWESENHEIT** | | | | |
| Urlaubsanspruch (anteilig) | `hrfunc_getUrlaubsanspruchInRange` rechnet anteilig per **Kalendertag-Zwölftelung** über gültig-ab-Perioden — **keine** Werktags-/Teilzeit-Umrechnung | `annualVacationDays`-Feld (nur Statistik) | werktagsgenau + Teilzeit-Skalierung + §5(2)-Rundung = **Plan-Neudesign** (§5.1); nur „anteilig" stammt aus ida | **hoch** |
| Resturlaub-Saldo | `zeitfunc_getResturlaubByTimestamp` = Vortrag + Anspruch + Anpassung − **genommen** (kein „geplant"-Abzug, kein Verfall) | — | 31.3.-Verfall §7(3) + Hinweisobliegenheit + geplant/genommen-Trennung = **Plan-Neudesign** (§5.2) | **hoch** |
| Geplante vs. genommene Tage | ida | `AbsenceStats` (nur Zählung) | Trennung geplant/genommen, Live-Vorschau | **hoch** |
| Halbtägig (0,5) + AM/PM | ida_app/-vue | — | halber Tag, vormittags/nachmittags | **hoch** |
| Zeitausgleich in Stunden | ida_app | — | Stunden statt Tage, gegen Stundenkonto | mittel |
| Abwesenheitsarten (fein) | `CalTerminartConst` | `AbsenceType{vacation,sickness,unavailable}` | Sonderurlaub, unbezahlt, Elternzeit, Mutterschutz, Berufsschule, Ehrenamt, Kurzarbeit, Kind-krank | **hoch** |
| **EFZG-Lohnfortzahlung (6-Wochen-Grenze)** | ida | — | Krank bezahlt bis 6 Wo., danach unbezahlt/Krankengeld; **Sollanrechnung ab Tag X** | **hoch** |
| Antragsarten + Vertreterpflicht | ida_app CMS | Antrag pending/approved/rejected | Vertreter-Auswahl, Self-Exclusion | mittel |
| Urlaub-bei-Krankheit-Gutschrift (§9 BUrlG) | ida-vue | — | Erkrankung im Urlaub → Urlaub zurück | mittel |
| Urlaubs-Anpassung (Korrektur-Ledger) | `hr_urlaubsanpassungen` | — | manuelle ±-Buchung pro Jahr | mittel |
| Urlaubskonto-Vorschau (Live) | ida_app/-vue | — | „neuer Resturlaub nach Antrag" | mittel |
| Krankenstand-KPI | `hr_kpi_setSicknessRatePerPerson` / `hrfunc_setSicknessRatePerPerson` | — | Krankquote Zeit-/Kalenderjahr | niedrig |
| EAU (elektr. AU) | `show_eau` | — | Krankschein-Flag/Upload | niedrig |
| **LOHN / SV** | | | | |
| **Gehalt vs. Stundenlohn (Lohntyp)** | `hr_gehalt` (`fixum_bezug`/`gehalt_fixum`/`stundenlohn` + `hr_gehaltstyp`-Lookup) | nur `hourlyRate` am Vertrag (kein Typ-Flag) | `salaryKind` (monatlich/stündlich) — ida hat die Vorlage bereits | **hoch** |
| **Brutto-Herleitung aus Stunden** | ida Lohnstunden | `PayrollProfile.monthlyGrossCents` existiert, wird aber **manuell** gepflegt | erfasste/gestempelte Stunden × Stundenlohn → Monatsbrutto **automatisch** | **hoch** |
| Itemisierte Lohn-Bezüge (lines) | `hr_gehalt_zulagen` | `PayrollRecord` Einzelfelder | `lines[]` mit DATEV-Lohnart | **hoch** |
| Lohnarten/Zulagen-Katalog | `hr_gehalt_zulagen` | — | org-Lookup, €/%-Typ, Intervall, §3b-Flag | **hoch** |
| **§3b-Zuschläge (Nacht/Sonn/Feiertag steuerfrei)** | ida | — | steuerfrei/SV-frei vs. -pflichtig, Grundlohngrenze 25 €/h | mittel (E9) |
| **VwL (vermögenswirksame Leistungen)** | ida | — | AG-Zuschuss + AN-Abzug, eigene DATEV-Lohnart | mittel |
| **Einmalzahlungen (Urlaubs-/Weihnachtsgeld/Bonus)** | ida | implizit über Intervall | sonstige Bezüge §39b Abs. 3 (Jahresverfahren) | mittel (E8) |
| Überstunden-Auszahlung (Lohnstunden) | ida-vue `hr_lohnstunden` | — | Plus-Stunden auszahlen, reduziert Konto | **hoch** |
| Unbezahlte Überstunden (Abzug) | ida-vue | — | manueller Konto-Abzug/Verfall | mittel |
| **AG-Umlagen U1/U2/InsO** | `crm_krankenkassen.umlage_1/2/3` (kassenindividuell; **NICHT** `hr_lohnnebenkosten`) | nur im Minijob-Pauschalsatz | U1 (Krankheit, <30 MA), U2 (Mutterschutz, immer), InsO (immer) für reguläre MA | **hoch** |
| **Pfändung/Lohnabtretung** | ida | — | Nettopfändung, Pfändungsfreibetrag | niedrig (bewusst weglassen §9) |
| SV-Beitragsgruppen (KV/RV/AV/PV) | `hr_gehalt` | `EmployeeProfile` (KV-Typ/Zusatz) | Beitragsgruppen-Schlüssel, Personengruppe | mittel (DATEV) |
| AG-Lohnnebenkosten-Sätze + BG/UV | `hr_lohnnebenkosten` | `PayrollSettings` (hartkodiert/2026-Platzhalter) | org-/jahr-editierbar, UV-Träger/Gefahrtarif | **hoch** |
| Gehalt historisiert (gültig-ab) | `hr_gehalt` | `PayrollProfile` (ein aktueller) | Versionierung | niedrig |
| **Tarif/Entgeltgruppe** | ida | — | optionales Stammdatenfeld (Einzelhandel-Tarif) | niedrig |
| **HR-STAMM** | | | | |
| Kinder (Freibeträge) | `hr_kinder` = reine **Verknüpfungstabelle** (`personen_id_elternteil/_kind`, `steuer_id_kind`); Name/Geburtstag am Personensatz | `childrenCount: int` | Kind-Sub-Entität (**Neukonstruktion**, ida bildet sie nicht 1:1 ab); **Einzelquelle** für Lohnsteuer-Zähler | niedrig |
| Qualifikationen (MA-Zuordnung) | `hr_ma_qualifikationen` (Stammdaten in `hr_qualifikationen`/`hr_qualifikationsarten`) | `qualifications` (Schicht-Anforderung) | MA-Quali mit Erwerb/Gültigkeit/Doku | mittel |
| Ausbildung | `hr_ausbildung` | — | Beginn/Ende/Noten/Ausbilder | niedrig |
| Vertreter/Stellvertretung | `hr_vertreter` | — | `vertreterUserIds` am Antrag/User | mittel |
| Mitarbeiter-Farbe/Kürzel/Personalnr | `hr_mitarbeiter` | Personalnr vorhanden | Farbe/Kürzel für Planer-Visual | niedrig |
| RFID/NFC-Token | `creds/rfid` | — | Terminal-Login | niedrig (E1) |
| **ABSCHLUSS / DATEV** | | | | |
| Monatsabschluss-Status-Maschine | `zeitMonatabschluss` | — | 7-Status sequenziell, Klärung blockiert **pro MA** | **hoch** |
| Stundenzettel-PDF | ida-vue | `month_report_screen` PDF | Monats-Stundenzettel je MA | mittel |
| DATEV LuG Bewegungsdaten | idadwh | DATEV-EXTF (nur Finanz) | Lohn-Bewegungsdaten-Export | mittel (E5) |
| DZeLt-Mapping (Ausfallschlüssel) | idadwh | — | statische Mapping-Tabelle | mittel |
| Lohnzettel-Rückimport | idadwh DATEV-API | — | PDF-Storage je MA | niedrig |
| **RECRUITING** (E4, Phase 2) | ida | — | eigenes Modul | niedrig |

---

## 4. Ziel-Datenmodell

> **Dual-Serialize-Pflicht für JEDES Modell:** `toFirestoreMap()`/`fromFirestore(id,map)`
> (camelCase, `Timestamp`, Doc-ID separat) **und** `toMap()`/`fromMap(map)` (snake_case,
> ISO-String, `id` im Map). `copyWith` mit `clearX`-Flag für nullable. Parser tolerant via
> `firestore_num_parser.dart` (`parse.toInt/toDouble/toBool/toMap`) + `FirestoreDateParser`
> (`readDate`/`readLocalDate`). Enums via `.value`→snake_case + `fromValue`-Default (wirft nie).
> Geld als `int` Cent. **Callable-Payload = immer `toMap()`** (snake_case).

### 4.0 ACL- und Hybrid-Spiegel-Grundsatzentscheid (Review-Korrektur)

- **ACL: durchgängig admin-only** für ALLE Personaldaten — exakt wie das bestehende HR-Muster
  in `firestore.rules` (`isAdmin() && sameOrg(orgId)` für `employeeProfiles`/`payrollRecords`/
  `payrollProfiles`/`costCenters`/…; Audit-Lesen ist admin-only). Das im Entwurf vorgesehene
  **„self-read" auf Personaldaten wird NICHT eingeführt** (kein neues, unausgereiftes
  `request.auth.uid == userId`-Predicate pro Collection — Bruchgefahr: entweder org-weit
  lesbar oder Selbstansicht kaputt). Die **mitarbeiterseitige Selbstansicht** (eigenes
  Stunden-/Urlaubskonto, Stempel-Status) wird über eine **Cloud-Function-Projektion**
  realisiert: `getMySelfService()`-Callable liest serverseitig (admin-äquivalent), filtert auf
  `request.auth.uid` und gibt nur die eigenen aggregierten Werte zurück. Schreiben (Stempeln,
  Antrag) läuft ohnehin über validierende Callables. **Einzige Ausnahme** mit direktem
  self-write bleibt `Mantelzeit` (Stempel-Event), exakt nach dem `workEntries`-Muster
  (self+permission ODER admin), aber **kein self-read** auf fremde — read bleibt admin-only.
- **Hybrid-Spiegelung je Collection explizit festgelegt** (CLAUDE.md: userContent gespiegelt,
  Stammdaten nicht):

| Collection | Klasse | In hybrid lokal gespiegelt? | Begründung |
|---|---|---|---|
| `mantelzeiten` | userContent | **ja** | Mitarbeiter-Zeiten, viele Writes → Spark-frugal |
| `absenceRequests` (best.) | userContent | **ja** | bereits userContent |
| `sollzeitProfiles` | Stammdaten | nein | selten geändert, Firestore-Offline-Cache reicht |
| `zeitkontoSnapshots` | Stammdaten/abgeleitet | nein | nur beim Abschluss geschrieben |
| `lohnstunden` | Stammdaten | nein | admin, selten |
| `urlaubsanpassungen` | Stammdaten | nein | admin-Ledger |
| `payLineTypes` | Stammdaten | nein | org-Lookup |
| `employeeChildren`/`-Qualifications`/`-Ausbildungen` | Stammdaten | nein | admin, selten |
| `monatsabschluesse` | Stammdaten | nein | admin, org-weit |
| `payrollConfig` | Stammdaten | nein | org-Settings |

### 4.1 Zeitwirtschaft

#### `lib/models/sollzeit_profile.dart` — `SollzeitProfile` (NEU, gültig-ab-versioniert)
- **Collection:** `organizations/{orgId}/sollzeitProfiles` · org-skopiert · **admin-only**.
- **Doc-ID:** auto (mehrere je User durch `gueltigAb`). Composite-Index `userId`+`gueltigAb`.
- Felder: `id`, `orgId`, `userId`, `gueltigAb: DateTime`, `isMonatsarbeitszeit: bool`,
  `monatsarbeitszeitMinutes: int?`, `montagMinutes..sonntagMinutes: int` (Tagessoll Minuten),
  `arbeitstageProWoche: int` (für BUrlG-Teilzeit-Umrechnung — abgeleitet aus „Tage mit Soll>0",
  aber **explizit** speicherbar für Sonderfälle), `pauseAb6hMinutes: int` (Default 30),
  `pauseAb9hMinutes: int` (Default 45), **`urlaubstageJahr: double` (zentrale Urlaubsquelle,
  **5-Tage-Woche-Basis = vollzeit-äquivalent** — Audit-Korrektur B1)**, `urlaubsbasisWerktage: int` (Default
  **5**; gesetzl. Mindesturlaub 20 Tage/5-Tage als separater Cross-Check), `zusatzurlaubstage:
  double`, `azRunden: bool`, `createdByUid`, `createdAt`, `updatedAt`.
- **Vollausbau (E3: volles IDA-Modell):** zusätzlich je Wochentag `kernzeitVonMinutes`/
  `kernzeitBisMinutes`, `rahmenVonMinutes`/`rahmenBisMinutes`, `pauseKarenzMinutes`,
  `kernzeitKarenzMinutes`, `azRundenAufMinutes`/`azRundenStart`/`azRundenEnde`,
  `azMaximumMinutes` (Kappung), `gleitzeit: bool`, `fakultativeUeberstunden: bool` +
  `fakultativeUeberstundenTyp`/`-Zeitraum`, `urlaubAlsStunden: bool` (1:1 zu `hr_sollzeiten`).
- Helper: `sollMinutesForWeekday(int weekday)`, `wochensollMinutes`, `effektiveArbeitstage`.
- **Dual-serialize:** 7 int-Felder (kein Sub-Objekt → simpler round-trip).

#### `lib/models/mantelzeit.dart` — `Mantelzeit` (NEU, Anwesenheit Kommen/Gehen, Event-Modell)
- **Collection:** `organizations/{orgId}/mantelzeiten` · org-skopiert · **self+permission ODER
  admin write** (wie `workEntries`), **read admin-only** (Selbstansicht via Projektion §4.0).
  Hybrid: **gespiegelt** (userContent).
- Felder: `id`, `orgId`, `userId`, `kommen: DateTime`, `gehen: DateTime?` (null=offen),
  `pauseMinutes: int`, `manuellErfasst: bool`, `klaerung: bool` (needs-review),
  `abgerechnet: bool`, `tagesabschluss: bool`, `deaktiviert: bool` (Soft-Delete, NIE hart
  löschen — IDA-Lektion), `anmerkung: String?`, `ipKommen/ipGehen: String?` (Audit),
  `genehmigungsantrag: MantelzeitAntrag?` (eingebettet), `createdByUid`, `createdAt`, `updatedAt`.
  > `ongoing` ist **kein persistiertes Feld**, sondern Getter `gehen == null` (IDA-Lektion:
  > nie auf ein redundantes Flag verlassen).
- Eingebettet `MantelzeitAntrag`: `antragKommen: DateTime?`, `antragGehen: DateTime?`,
  `antragDeaktiviert: bool`, `bemerkung: String?`.
- Helper: `nettoMinutes = max(0,(gehen−kommen)−pauseMinutes)`; `dateFetched` (Client-`now()`
  beim Parsen, NICHT persistiert) für Live-Timer-Drift.
- **Schreibpfad:** Cloud Functions `clockIn`/`clockOut`/`upsertMantelzeitBatch` (validiert
  gegen Abrechnungssperre **pro MA** + Überlappung + Compliance-Aggregat §5.10).
- **Datums-Ausnahme wie `WorkEntry`:** eigene Parser, `kommen` Pflicht (`FormatException`).

#### `lib/models/zeitkonto_snapshot.dart` — `ZeitkontoSnapshot` (NEU, Monats-Saldo, pro MA)
- **Collection:** `organizations/{orgId}/zeitkontoSnapshots` · org-skopiert · admin-only.
- **Doc-ID:** deterministisch `{userId}-{jahr}-{mm}` (Upsert). Index `userId`+`jahr`+`monat`.
- Felder: `id`, `orgId`, `userId`, `jahr: int`, `monat: int`, `sollMinutes`, `istMinutes`,
  `bilanzMinutes` (Ist−Soll des Monats), `stundenkontoMinutes` (kumulierter Saldo zum
  Monatsende), `ausgezahlteMinutes`, `unbezahlteUeberstundenMinutes`,
  **`abgerechnet: bool` + `abgerechnetAm: DateTime?`** (= die **pro-MA-Abrechnungssperre**,
  Review-Korrektur), `createdByUid`, `createdAt`, `updatedAt`.
  > **Kein `resturlaubTage` mehr hier** (Review-Korrektur): Urlaub ist **kalenderjahr**-bezogen,
  > der Snapshot **monats**-bezogen — Periodizitäten nicht vermischen. Resturlaub-Vortrag kommt
  > aus eigener Jahres-Quelle `urlaubskonto_jahr` (§4.2).
- **Lektion (IDA):** wird beim Monatsabschluss fortgeschrieben (Upsert); kumulierte Saldo-
  Berechnung startet ab dem letzten abgeschlossenen Monat.

#### `lib/models/urlaubskonto_jahr.dart` — `UrlaubskontoJahr` (NEU, Jahres-Vortragsquelle)
- **Collection:** `organizations/{orgId}/urlaubskontoJahre` · org-skopiert · admin-only.
- **Doc-ID:** `{userId}-{jahr}`.
- Felder: `id`, `orgId`, `userId`, `jahr`, `vortragVorjahrTage: double`,
  `vortragVerfaelltAm: DateTime?` (Default 31.3.), `hinweisErteiltAm: DateTime?`
  (EuGH/BAG-Hinweisobliegenheit — Verfall NUR wenn dokumentiert), `gewaehrterMehrurlaubTage:
  double`, Meta. (Trennt sauber gesetzlich vs. vertraglich, §5.2.)

#### `lib/models/lohnstunden.dart` — `Lohnstunden` (NEU, Überstunden-Auszahlung)
- **Collection:** `organizations/{orgId}/lohnstunden` · org-skopiert · admin-only.
- **Doc-ID:** `{userId}-{jahr}-{mm}`. Felder: `lohnstundenMinutes` (ausgezahlt),
  `unbezahltMinutes` (Abzug/Verfall), `bemerkung`, Meta. Audit-geloggt.

#### ~~Erweiterung `WorkEntry` (Istzeit/Kostenträger)~~ — **entfällt (E2: nein)**
- Keine Kostenträger-Felder. `WorkEntry`/Mantelzeit buchen auf den **Standort** (= Kostenstelle);
  das bestehende `siteId` genügt für die DATEV-Kostenstellen-Zuordnung. Keine `projektRef`/
  `taetigkeit`-Erweiterung.

### 4.2 Urlaub / Abwesenheit

#### Erweiterung `lib/models/absence_request.dart` — `AbsenceRequest`
- **`AbsenceType` erweitern:** `+specialLeave, unpaidLeave, timeOff, parentalLeave, maternity,
  vocationalSchool, volunteering, shortTimeWork, childSick`. Deutsche `.value`/`label`,
  `fromValue`-Default `vacation`.
- **Neue Felder:** `halfDay: bool`, `halfDayPeriod: HalfDayPeriod?` (`vormittags`/`nachmittags`),
  `hours: double?` (Zeitausgleich), `vertreterUserIds: List<String>`, `eauAttached: bool`.
- Helper: `durationDays` (ganztägig=Werktage, halbtägig=0,5), `durationHours`.

#### `lib/models/urlaubsanpassung.dart` — `Urlaubsanpassung` (NEU, Korrektur-Ledger)
- **Collection:** `organizations/{orgId}/urlaubsanpassungen` · org-skopiert · admin-only.
- Felder: `id`, `orgId`, `userId`, `jahr`, `tage: double` (signiert), `art:
  UrlaubsAnpassungArt`, `anmerkung`, Meta. Enum `{abzugAllgemein, abzugFrist, sonderurlaub,
  allgemein}`.

#### `UrlaubsReport` (NICHT persistiert — Wert-Objekt in `lib/core/urlaub_calculator.dart`)
- Felder: `anspruchJahr`, `vortragVorjahr`, `vortragVerfallen`, `anspruchGesamt`, `genommen`,
  `geplant`, `resturlaub` (alle `double`).
- Quelle: `SollzeitProfile.urlaubstageJahr` (zentral) + `EmployeeProfile.hireDate/exitDate` +
  `UrlaubskontoJahr` (Vortrag/Verfall) + `Urlaubsanpassung` + genehmigte `AbsenceRequest`.

### 4.3 Lohn / SV / Zulagen

#### Erweiterung `lib/models/employment_contract.dart` — Lohntyp (Review-Korrektur)
- **Neues Enum `SalaryKind { stundenlohn, monatsgehalt }`** + Feld `salaryKind`
  (Default `stundenlohn`, rückwärtskompatibel). Neues Feld `monthlyGrossCents: int?`
  (Festgehalt, nur bei `monatsgehalt`). `hourlyRate` bleibt für `stundenlohn`. Optionales
  `tarifgruppe: String?`/`entgeltgruppe: String?` (Einzelhandel-Tarif). copyWith mit `clearX`.
  → schließt die Lücke „Gehalt vs. Stundenlohn".

#### `lib/models/pay_line_type.dart` — `PayLineType` (NEU, Lohnart-Katalog)
- **Collection:** `organizations/{orgId}/payLineTypes` · org-skopiert · admin-only.
- Felder: `id`, `orgId`, `name`, `datevLohnartNr: String?` (**weiche** Validierung: max
  4-stellig numerisch, **kein** fester Bereich — Review-Korrektur: Bereiche sind mandanten-/
  LuG-vs-LODAS-spezifisch, harte 1–5999/8000–9999-Validierung lehnt gültige ab),
  `kind: PayLineKind` (`grundlohn`/`zulage`/`abzug`/`fixum`/`vwl`/`zuschlag3b`/`einmalzahlung`),
  `wertTyp: WertTyp` (`nominal`€/`prozent`%), `intervall: PayInterval`
  (`einmalig`/`monatlich`/`quartal`/`jaehrlich`), `steuerfrei: bool` (§3b/VwL-Steuer-Handling),
  `svFrei: bool`, `deaktiviert: bool`, Meta.

#### Erweiterung `lib/models/payroll_record.dart` — `PayrollRecord.lines`
- **Neues Feld:** `lines: List<PayrollLine>` (eingebettet). `PayrollLine`: `lineTypeId: String?`,
  `name`, `datevLohnartNr: String?`, `amountCents: int` (signiert), `kind: PayLineKind`,
  `steuerfrei: bool`, `svFrei: bool`, `note: String?`.
- `grossCents`/Netto-Logik: bestehende Einzelfelder bleiben; `lines` sind **zusätzliche**
  Bezüge/Abzüge. Getter `linesTotalCents`, `steuerpflichtigeLinesCents`, `svPflichtigeLinesCents`.
  Brutto-Herleitung speist `grundlohn`-Line (§4.3-Vertrag, M-B0).

#### Erweiterung `lib/models/employee_profile.dart` — SV-/DATEV-Stammakte (optional)
- Neue nullable Felder: `personengruppenSchluessel: String?` (SGB), `beitragsgruppeKV/RV/AV/PV:
  String?`, **`uvTraeger: String?`/`gefahrtarifstelle: String?`** (Berufsgenossenschaft —
  Pflicht für DATEV-Lohn, Review-Lücke), `mitarbeiterFarbe: String?`, `kuerzel: String?`,
  `erwerbsart: Erwerbsart?`. copyWith mit `clearX`. (Steuer-ID/SV-Nr bereits vorhanden.)
- Enum `Erwerbsart{haupterwerb, nebenerwerb, minijob, midijob, praktikum, werkstudent}`.

#### `lib/models/org_payroll_settings.dart` → `OrgPayrollSettings` (org-/jahr-editierbar)
- **Collection:** `organizations/{orgId}/payrollConfig/{jahr}` · org-skopiert · admin-only.
  Fallback auf `PayrollSettings.defaults<jahr>()`.
- Übernimmt alle bestehenden Sätze (`healthRate`, `healthAdditionalRate`, `careRate`,
  `pensionRate`, `unemploymentRate`, BBG, Minijob-Sätze) **PLUS** die fehlenden AG-Umlagen
  (Review-Lücke): `umlageU1Rate: double` (Krankheit, pflicht <30 MA), `umlageU2Rate: double`
  (Mutterschutz, immer), `insolvenzgeldumlageRate: double` (immer), `uvRate: double` (UV-Beitrag/
  Gefahrtarif). → AG-Kostenrechnung wird damit **vollständig** (bisher zu niedrig).
  > **Korrektur-Hinweis (Review):** `defaults2026` ist heute **Platzhalter = identisch 2025**
  > (`healthAdditionalRate 0.025`, `careRate 0.036`). Im UI-Editor + PDF/Export muss ein
  > sichtbarer „**Richtwert, Sätze prüfen/aktualisieren**"-Hinweis stehen, damit die Werte nicht
  > fälschlich als amtlich-2026 erscheinen.

### 4.4 HR-Sub-Entitäten

#### `lib/models/employee_child.dart` — `EmployeeChild` (NEU, **Einzelquelle Kinderzähler**)
- **Collection:** `organizations/{orgId}/employeeChildren` · org-skopiert · admin-only.
- Felder: `id`, `orgId`, `userId`, `name`, `vorname`, `geschlecht: String?`, `steuerIdKind:
  String?` (11-stellig), `geburtstag: DateTime?`, **`zaehltFuerFreibetrag: bool`** (Default
  true), Meta.
- **Review-Korrektur (Doppelquelle):** Lohnsteuer-Kinderzähler kommt aus **GENAU EINER** Quelle.
  Regel: solange **keine** `EmployeeChild` existiert, bleibt `childrenCount: int` (bestehend,
  speist `german_tax.childCount`) die Quelle (rückwärtskompatibel). **Sobald** ≥1
  `EmployeeChild` gepflegt ist, wird der Zähler aus `count(zaehltFuerFreibetrag)` abgeleitet und
  `childrenCount` wird in der UI **read-only/abgeleitet** angezeigt (nicht doppelt editierbar).
  M0 migriert `childrenCount>0` → entsprechend viele Platzhalter-`EmployeeChild` oder belässt
  die int-Quelle (Migrations-Schalter §M0).

#### `lib/models/employee_qualification.dart` — `EmployeeQualification` (NEU)
- **Collection:** `organizations/{orgId}/employeeQualifications` · admin-only.
- Felder: `qualificationId: String?` (FK auf `qualifications`), `qualificationName`, `erwerb:
  QualiErwerb` (`vorab`/`intern`/`extern`), `erworbenAm`, `gueltigBis`, `bemerkung`, Meta.

#### `lib/models/employee_ausbildung.dart` — `EmployeeAusbildung` (NEU, niedrig)
- **Collection:** `organizations/{orgId}/employeeAusbildungen` · admin-only.
- Felder: `bezeichnung`, `beginn`, `ende`, `ausbilderUserId`, `noteZwischen`, `noteAbschluss`,
  `bemerkung`, Meta.

### 4.5 Monatsabschluss (org-Orchestrierung, Sperre pro MA — Review-Korrektur)

#### `lib/models/monatsabschluss.dart` — `Monatsabschluss` (NEU)
- **Collection:** `organizations/{orgId}/monatsabschluesse` · org-skopiert · admin-only.
- **Doc-ID:** `{jahr}-{mm}`. Felder: `jahr`, `monat`, `status: MonatsabschlussStatus`,
  `stundenzettelDocPath: String?`, `datevExportPath: String?`, `finalizedByUid`, `finalizedAt`,
  `tagesabschlussTage: List<DateTime>`, Meta.
- **Review-Korrektur:** Der Monatsabschluss ist nur die **org-Orchestrierung/Übersicht**. Die
  **harte Sperre + Klärung sind PRO MITARBEITER** auf `ZeitkontoSnapshot.abgerechnet`/
  `abgerechnetAm` (§4.1) bzw. `Mantelzeit.klaerung`. Ein offener Klärungsfall eines MA
  blockiert **nur diesen MA** (sein Snapshot bleibt unabgerechnet), nicht die ganze Org. Der
  org-`Monatsabschluss.status` zeigt aggregiert „X von Y MA abgerechnet, Z mit Klärung".
- Enum `MonatsabschlussStatus{aktuellerMonat, inZukunft, kannAbgeschlossen, abgeschlossen,
  nichtAbgeschlossenerVormonat, hatKlaerung, kannZurueckgenommen}` (IDA-1..7).

### 4.6 Recruiting (E4, Phase 2)
- `lib/models/stellenausschreibung.dart` + `bewerbung.dart` — nur falls E4=ja. Org-skopiert,
  admin-only. Hier nicht detailliert (Prio niedrig, separate Phase).

---

## 5. Rechen- & Geschäftsregeln (Detail)

> Implementierung als **reine, testbare Dart-Funktionen** in `lib/core/`, aufgerufen vom
> Provider. Wo Schreibvalidierung nötig (Stempeln, Abschluss), zusätzlich Cloud Function.

### 5.1 Urlaubsanspruch (BUrlG, werktagsgenau + Teilzeit — Review-Korrektur)
- **Migrationsregel/Vorrang (drei Quellen!):** Es gibt heute `EmployeeProfile.annualVacationDays
  (int?)` UND `EmploymentContract.vacationDays (Default 30)`. Der Plan führt
  `SollzeitProfile.urlaubstageJahr` als **kanonische dritte** Quelle ein. **Vorrang ab M0:**
  `SollzeitProfile.urlaubstageJahr` → sonst `EmployeeProfile.annualVacationDays` → sonst
  `EmploymentContract.vacationDays`. Die ersten beiden werden als **deprecated** markiert (Kommentar
  + UI „verschoben nach Sollzeit") und in M0 nach `urlaubstageJahr` migriert.
- **Teilzeit-Umrechnung — Basis-Konsistenz (Audit-Korrektur B1):** Die BAG-Teilzeitformel teilt durch die
  Wochenarbeitstage **der Basis, in der der Anspruch ausgedrückt ist**. Da die Bestandswerte (`vacationDays=30`,
  `weeklyHours=40` → 5-Tage-Vollzeit) bereits **5-Tage-basiert** sind, ist `urlaubstageJahr` die **5-Tage-Basis**
  und `urlaubsbasisWerktage` = **5** (NICHT 6 — sonst bekäme ein 5-Tage-Vollzeitler 30×(5/6)=25). **Teilzeit-
  Umrechnung** (BAG-Rechtsprechung, Beispiel 20/5×3=12):
  `effektiverAnspruch = urlaubstageJahr × (eigeneArbeitstageProWoche / urlaubsbasisWerktage)` mit
  `urlaubsbasisWerktage=5`, `eigeneArbeitstageProWoche = SollzeitProfile.effektiveArbeitstage` (Tage mit Soll>0).
  → 5-Tage-Vollzeit 30→30; 3-Tage-Teilzeit 30×(3/5)=18. M0 kopiert die Altwerte **verbatim** (keine Skalierung).
  Den gesetzl. BUrlG-Mindesturlaub (20 Tage/5-Tage-Basis bzw. 24 Werktage/6-Tage) separat als Floor cross-checken,
  NICHT den kanonischen Wert auf 6-Tage-Basis speichern. → ohne korrekte Umrechnung liefern Minijobber mit
  2–3 Tagen/Woche **massiv falschen** Anspruch.
- **Anteilig bei Ein-/Austritt:** Σ über gültig-ab-Perioden, Zwölftelung gekappt auf
  `hireDate`/`exitDate`.
- **§5(2)-Rundung — getrennt gesetzlich/vertraglich (Review-Korrektur):** Die „≥0,5 aufrunden"-
  Regel gilt **nur für den gesetzlichen Mindesturlaub** (§5 Abs. 2 BUrlG, „mindestens halbe
  Tage werden aufgerundet"). **Vertraglicher Mehrurlaub** (`zusatzurlaubstage`/über Minimum) darf
  abweichend (kaufmännisch/exakt) gerundet werden. `urlaub_calculator` trennt daher
  `gesetzlicherTeil` (aufrunden) und `vertraglicherTeil` (konfigurierbar) statt die Rundung
  pauschal auf den Gesamtanspruch anzuwenden.
- **Genommene Tage:** zählen nur Werktage des Sollzeitprofils ohne Feiertage; 24./31.12.
  konfigurierbar; halbtägig=0,5. → braucht **lokalen Feiertagskalender**
  (`lib/core/feiertage.dart`). **Bundesland-Quelle = Standort (Audit-Korrektur H6):**
  `SiteDefinition.federalState` via `EmployeeSiteAssignment` (bevorzugt `isPrimary`), Org-Default
  „Schleswig-Holstein" (beide Kieler Filialen) — **`EmployeeProfile.federalState` existiert NICHT**, kein
  redundantes Per-MA-Feld anlegen. `feiertage.dart` nimmt das Bundesland als **expliziten Parameter**,
  berechnet bewegliche Feste per Oster-Computus (kein statisches Jahres-Table) und kennt SH-Spezifika
  (Reformationstag 31.10., gesetzl. in SH seit 2018 → Soll=0, kein Urlaubsverbrauch).

### 5.2 Resturlaub-Saldo + Übertragung/Verfall (Review-Korrektur)
- `resturlaub = vortragVorjahr − vortragVerfallen + anspruchJahr + Σ Anpassung − genommen −
  geplant`.
- **Quelle Vortrag = `UrlaubskontoJahr` (Jahres-Doc), NICHT der Monats-`ZeitkontoSnapshot`**
  (Review-Korrektur: Urlaub ist kalenderjahr-, Snapshot monatsbezogen; ein nicht
  abgeschlossener Dezember dürfte sonst den Vortrag brechen).
- **31.3.-Verfall (§7 Abs. 3 BUrlG):** Übertragener Resturlaub verfällt zum 31.3. des Folgejahres
  **nur** wenn der AG seiner **Hinweisobliegenheit** (EuGH C-684/16 / BAG) nachgekommen ist —
  abgebildet über `UrlaubskontoJahr.hinweisErteiltAm`. Ohne dokumentierten Hinweis **kein**
  Verfall (`vortragVerfallen = 0`). UI-Warnung „Hinweis nicht erteilt → kein Verfall".
- **Live-Vorschau (Antrag):** `neuerResturlaub = resturlaub − antragsdauer` (nur bei `vacation`).
- **Erkrankung im Urlaub (§9 BUrlG):** überlappt `sickness` einen genehmigten `vacation` →
  Urlaubstage gutgeschrieben (Warnung beim Anlegen). Prio mittel.

### 5.3 Sollzeit pro Tag/Zeitraum
- `sollMinutesForDay(date)` = Wochentagsfeld der zum Stichtag gültigen `SollzeitProfile`;
  Feiertag → 0; vor `hireDate`/nach `exitDate` → 0; 24./31.12. → /2.
- `isMonatsarbeitszeit`: `monatsarbeitszeitMinutes` gleichmäßig auf Arbeitstage des Monats.
- Σ über Zeitraum = `getSummeSollMinutesInRange`.

### 5.4 Stundenkonto / Soll-Ist-Saldo
- **Ist-Minuten** = Σ `Mantelzeit.nettoMinutes` (gestempelt) + Soll-Anrechnung anrechenbarer
  Abwesenheit **gemäß Anrechnungsmatrix §5.4a** (NICHT pauschal — Review-Korrektur).
- **Bilanz (Monat)** = Ist − Soll. **Stundenkonto (kumuliert)** = Vortrag (letzter Snapshot)
  + Σ Bilanz − ausgezahlte − unbezahlte Überstunden.
- **KPI heute/Woche/Monat** = je `{ist, soll}` (clientseitig berechnet, on-demand).
- **Snapshot-Trigger (E7: wie IDA):** der kumulierte Saldo wird **nur beim Monatsabschluss** als
  `ZeitkontoSnapshot` persistiert (Pendant `hr_zeitkonto` per `jahrmonat`); der **laufende** Saldo
  wird sonst on-demand aus Buchungen ab dem letzten Snapshot gerechnet (Pendant
  `get_actual_stundenkonto_by_timestamp`). **Kein** nächtlicher Cron (Spark-frugal).
- **„Anrechnung bis Null"** (Schlechtwetter/S-KUG): bewusst weggelassen (E6, §9).

### 5.4a Anrechnungsmatrix je `AbsenceType` (NEU, zentrale Tabelle — Review-Verbesserung)
> Eine einzige Quelle `lib/core/abwesenheit_matrix.dart` (Map `AbsenceType → AbwesenheitsRegel`),
> die **Calculator, Stundenkonto, Lohnberechnung und DATEV-Mapping gemeinsam lesen** — statt die
> Eigenschaften über §5.1/5.4/5.9 zu verstreuen.

| AbsenceType | bezahlt | sollmindernd / als Soll angerechnet | urlaubswirksam | halbtag-fähig | §3b-relevant | DATEV-Ausfallschlüssel |
|---|---|---|---|---|---|---|
| `vacation` | ja | als Soll | zählt genommen | ja | nein | U |
| `sickness` | **bezahlt bis 6 Wo. (EFZG), danach unbezahlt** | als Soll **nur im EFZG-Zeitraum**; danach **nicht** | nein | ja | nein | K |
| `childSick` | begrenzt (§45 SGB V) | als Soll begrenzt | nein | ja | nein | KK |
| `specialLeave` | ja | als Soll | nein | ja | nein | SU |
| `unpaidLeave` | **nein** | **nicht** (kein Soll, kein Ist) | nein | ja | nein | UU |
| `timeOff` (Zeitausgleich) | aus Konto | reduziert Stundenkonto (Stunden) | nein | ja | nein | ZA |
| `parentalLeave` | nein | nicht | nein | nein | nein | EZ |
| `maternity` | Sonderregel | nicht (Mutterschutzlohn separat) | nein | nein | nein | MU |
| `vocationalSchool` | ja | als Soll | nein | ja | nein | BS |
| `volunteering` | ggf. | als Soll | nein | ja | nein | EH |
| `shortTimeWork` | KUG | **nicht** ist-soll-neutral (E6 weggelassen) | nein | nein | nein | — |

- **EFZG-6-Wochen-Grenze (Review-Lücke):** `sickness` wird **nur die ersten 42 Kalendertage je
  Krankheitsfall** als bezahltes Soll angerechnet (Lohnfortzahlung); ab Tag 43 weder Soll-Ist-
  neutral noch lohnwirksam (Krankengeld der Kasse). Der Stundenkonto-Calculator führt daher je
  Krankheitsfall einen 42-Tage-Zähler (Fortsetzungserkrankungs-Vereinfachung dokumentiert).
- **Wichtig (Review):** `unpaidLeave`, `shortTimeWork` und Krank > 6 Wo. dürfen **NICHT** als
  Ist=Soll angerechnet werden — sonst entsteht falsches Plus/Minus im Stundenkonto.

### 5.5 Überstunden bezahlt/unbezahlt + Auszahlung
- **Auszahlung:** `Lohnstunden.lohnstundenMinutes` reduziert das ausgewiesene Stundenkonto;
  erzeugt eine `PayrollLine` (DATEV-Lohnart „Überstundenvergütung") im `PayrollRecord`.
- **Unbezahlt/Verfall:** `Lohnstunden.unbezahltMinutes` reduziert Konto ohne Auszahlung.
- **Sperre:** nur wenn Zielmonat **nicht abgerechnet** (`ZeitkontoSnapshot.abgerechnet`, pro MA).
- Sammel-Auszahlung („alle mit Konto>0") als Batch.

### 5.6 Brutto-Herleitung aus Stunden (NEU, Brücke Zeit→Lohn — Review-Lücke)
- `lib/core/lohn_herleitung.dart` (rein testbar):
  - `salaryKind == monatsgehalt` → `grundlohnCents = monthlyGrossCents` (Festgehalt).
  - `salaryKind == stundenlohn` → `grundlohnCents = round(istMinutes/60 × hourlyRateCents)`,
    wobei `istMinutes` = abgerechnete Mantelzeit-/WorkEntry-Stunden des Monats + bezahlte
    Abwesenheit gemäß §5.4a. Erzeugt eine `PayrollLine(kind: grundlohn)`.
- Das ist der **Kern eines Einzelhandels mit Minijobbern** (Brutto folgt aus gestempelten
  Stunden). Bisher manuell — wird automatisch ableitbar (eigener M-B0, **vor** Lohnarten M-L).

### 5.7 SV-Beiträge + AG-Umlagen (bestehende Logik + Erweiterung)
- WorkTime hat KV/PV/RV/AV hälftig, Minijob-Pauschalen, Midijob-Faktor F bereits
  (`payroll_calculator.dart`). **Erweiterung:** AG-Sätze aus editierbarem `OrgPayrollSettings`
  statt hartkodiert.
- **AG-Umlagen (Review-Lücke):** für **reguläre** Beschäftigte zusätzlich `U1` (nur Betriebe
  <30 MA, konfigurierbar), `U2` (immer) und **Insolvenzgeldumlage** (immer) auf das SV-Brutto
  rechnen — **nur AG-Kosten**, kein AN-Abzug. Bisher fehlten sie ganz (außer im Minijob-
  Pauschalsatz) → die AG-Lohnnebenkosten waren zu niedrig. **Quellen-Hinweis (verifiziert):** in
  ida sind U1/U2/InsO **kassenindividuell** in `crm_krankenkassen.umlage_1/2/3` hinterlegt (NICHT
  in `hr_lohnnebenkosten`, das nur KV/PV/AV/RV/UV+BG trägt). → In WorkTime entweder pauschal in
  `OrgPayrollSettings` ODER (sauberer) optional je Krankenkasse am `EmployeeProfile` überschreibbar.
- **Midijob (Review-Hinweis):** Der bestehende `_midijobBase` reduziert KV/PV **und** RV/ALV auf
  **denselben** Wert. Korrekt ist die reduzierte beitragspflichtige Einnahme als Bemessung; im
  Übergangsbereich weicht aber die **AN-Beitragsverteilung je Zweig** ab (RV-Sonderregel/
  Verzicht-Option). → in M-B0/M-L **explizit als bekannte Vereinfachung dokumentieren**
  (Disclaimer „Richtwert"), nicht ungeprüft als korrekt übernehmen; saubere Zweig-Aufteilung als
  spätere Opt-in-Stufe.
- **SV-Beitragsgruppen/BG-UV** nur als **Stammdaten für DATEV** (rechnen nicht mit; Schwellen
  bleiben in `OrgPayrollSettings`).

### 5.8 Lohnarten / Zulagen / VwL
- `PayLineType` → bei Lohnlauf als `PayrollLine` instanziiert. Bei `prozent`:
  `amountCents = round(grossCents × prozent)`. DATEV-Lohnartnummer wandert in den Export.
- **VwL (Review-Lücke):** als zwei gekoppelte Lines — AG-Zuschuss (Bezug, eigene Lohnart) +
  AN-Eigenanteil (Abzug). Eigenes `PayLineKind.vwl`.

### 5.8a Einmalzahlungen / sonstige Bezüge (§39b Abs. 3 EStG — E8: wie IDA, **§39b umsetzen**)
- Urlaubs-/Weihnachtsgeld/Bonus/Prämie als `PayLineKind.einmalzahlung` (Sonderbezug).
  IDA-Stammdaten-Pendant: `hr_gehalt.weihnachtsgeld_*`/`urlaubsgeld_*`/`sonstige_praemien`.
- **Befund (verifiziert, E8):** IDA **rechnet selbst keine Lohnsteuer** — die korrekte Besteuerung
  sonstiger Bezüge macht **DATEV** (LODAS-Bearbeitungsschlüssel `ABRUF_JAHRESSONDERZAHLUNG`). „Wie
  bei IDA" heißt also: Sonderbezug sauber als eigene Lohnart führen + im Export korrekt
  kennzeichnen — und für WorkTimes **eigenen Richtwert** das amtliche Verfahren umsetzen statt zu
  vereinfachen.
- **Plan (E8, beschlossen):**
  1. **§39b-Abs.-3-Jahresverfahren** in `german_tax.sonstigerBezugTax(...)`: voraussichtlicher
     Jahresarbeitslohn **mit** und **ohne** sonstigem Bezug → Lohnsteuer-Differenz = LSt auf den
     Bezug (Soli/KiSt analog auf die Differenz; SV nur bis Jahres-BBG, anteilig). Abfindung/
     mehrjährige Vergütung: Fünftelregelung als Sonderzweig (sofern relevant; sonst dokumentiert
     ausgenommen).
  2. **DATEV-Lohn-Export (M-D):** Einmalzahlung als **Jahressonderzahlung** kennzeichnen
     (Bearbeitungsschlüssel/Lohnart), damit der Steuerberater-DATEV das amtliche Verfahren fährt.
  3. **Kein** „laufender-Monat"-Default. Richtwert-Disclaimer bleibt (amtliche Tabelle ≠ unsere
     §32a-Näherung), aber **das Jahresverfahren ist Pflicht-Logik in M-L**, nicht Opt-in.

### 5.8b §3b-Zuschläge (Nacht/Sonn/Feiertag — E9: **voll umsetzen**, nicht vereinfacht)
- Nacht 20–06 (+25 %, +40 % für 00–04 Uhr bei Arbeitsbeginn vor 00 Uhr), Sonntag +50 %,
  Feiertag +125 %, 25.12./26.12./1.5. +150 % sind nach **§3b EStG steuerfrei**; **steuerfrei** auf
  Grundlohn-Bemessung bis **50 €/h**, **SV-frei** nur bis Grundlohngrenze **25 €/h** (darüber
  SV-pflichtig, aber weiter steuerfrei).
- **Plan (E9, beschlossen):** `PayLineKind.zuschlag3b` mit `steuerfreiAnteilCents`/
  `steuerpflichtigAnteilCents`/`svFreiAnteilCents` am `PayrollLine`. Die Aufteilung rechnet
  `lohn_herleitung.dart`/`payroll_calculator` **direkt in M-L** (Default **an**):
  - steuerfreier Anteil = `zuschlagProzent × min(grundlohnProStunde, 50 €) × stunden`;
  - SV-freier Anteil = `zuschlagProzent × min(grundlohnProStunde, 25 €) × stunden`;
  - Rest = steuer-/SV-pflichtig. Zuschlagstunden stammen aus der Mantelzeit-Lage (Nacht-Fenster
    aus `OrgPayrollSettings`, Sonn-/Feiertag aus dem Feiertagskalender §5.3).
- **Kein** Default-aus-Flag. Disclaimer „Richtwert" bleibt, die §3b-Aufteilung ist Pflicht-Logik.

### 5.9 Steuerklasse / Kinder (bestehende Logik + Review-Hinweise)
- **Kinderzähler-Einzelquelle (§4.4):** `german_tax.childCount` bezieht den Zähler aus **genau
  einer** Quelle (int `childrenCount` ODER `count(EmployeeChild.zaehltFuerFreibetrag)`), nie
  beide parallel.
- **Steuerklasse V/VI (Review-Hinweis):** die bestehende V/VI-Approximation (zvE+Grundfreibetrag,
  min 14 %) ist grob — für Mehrfachbeschäftigung (Kl. VI, im Einzelhandel mit Minijob-Zweitjob
  häufig) im UI/PDF/DATEV-Hinweis als **„Richtwert, Kl. V/VI näherungsweise"** ausweisen. Keine
  stille Genauigkeitsannahme beim Lohnarten-/Auszahlungs-Aufbau.

### 5.10 Compliance-Spiegel für Mantelzeit (Event-Modell — Review-Korrektur, eigener Aufwand)
- Der bestehende `compliance_service.dart` ↔ `functions/index.js`-Spiegel arbeitet auf
  **Shift/WorkEntry** (ein Start/Ende). `Mantelzeit` ist ein **Kommen/Gehen-Event-Modell**
  (mehrere offene/geschlossene Buchungen pro Tag). Die Höchstarbeitszeit (10h/Tag),
  Pausenpflicht (30@6h/45@9h) und Ruhezeit (660 min zwischen Tagen) brauchen daher eine **NEUE
  Tages-Aggregationsschicht** (mehrere Events eines Tages summieren, Tagesgrenzen/Über-Mitternacht
  behandeln, letzte Buchung Tag N ↔ erste Buchung Tag N+1 für Ruhezeit). Das ist **kein
  „Regel erneut anwenden"**, sondern neuer Spiegel-Code in **beiden** Dateien (gleiche Codes/
  Schwellen wie bisher: `min_rest 660`, `break_required`, `max_daily 600`).
- **Aufwands-Konsequenz:** dieser Spiegel ist ein **eigener Posten in M-Mantelzeit** (nicht
  Nebenpunkt). Tests gegen `.code`, FakeFirestore-Doubles beachten.

### 5.11 DATEV-Lohn-Bewegungsdaten-Mapping (vereinfacht)
- **Tagesweise:** `tagesanzahl_i = stunden_i / gesamtstunden_tag`, **rundungserhaltend** auf
  2 NK, so dass Σ exakt 1,00 (bzw. 0,50 Halbtag) ergibt — ausführlich umgesetzt, da DATEV-LuG
  Rundungsdifferenzen als **Importfehler** zurückweist. Division-durch-0-Schutz. **Referenz
  (verifiziert):** idadwh nennt das `sumPreservingRounding` + `sortRoundingErrors`
  (`src/utils/numberHelper/rounder.ts`) — ein Restausgleich (kein exakter Hare-Niemeyer);
  WorkTime spiegelt das Verhalten, nicht den Namen.
- **Monatsweise:** Aggregation je `(personalnr, lohnart, ausfallschluessel, kostenstelle)`.
- **DZeLt-Ersatz:** statische Tabelle `lib/core/datev_lohn_mapping.dart`
  (`AbsenceType`/Lohnart → `{datevLohnart, ausfallschluessel}`, gespeist aus §5.4a-Matrix),
  **keine Formel-Eval** (Sicherheit). Beispiele: Urlaub→508/U, Krank→111/K, Feiertag→29/F,
  Zeitausgleich→20/ZA, Berufsschule→403/BS, Auszahlung→1100. **Hinweis (verifiziert):** diese
  Beispielwerte stammen aus dem **Legacy-stamer-Mapping** (`ZeitUndLohndatenExport.ts`), nicht aus
  der DZeLt-Engine selbst. Die echte DZeLt ist deutlich mächtiger (~20 Bedingungsfelder +
  frei evaluierte `wert_formel`) — unser statischer Ersatz bildet bewusst nur die
  Abwesenheits-Achse ab (Lohnart-Nummern mandantenspezifisch; E5: ja, hinter Feature-Flag).
- **Industrieminuten** (0,75h→„75") vs. echte Minuten (→„45") konfigurierbar; Personalnr
  0-padded; Header `beraternummer;mandantennummer;MM/YYYY`. Export als
  `ExportService.buildDatevLohnCsv(...)` (UTF-8-BOM/`;`/Komma-Dezimal — BOM nicht entfernen).

---

## 6. UI/UX-Plan (Signal-Teal / Material 3)

> ida_app-Muster konzeptionell mit `lib/ui`-Komponenten. Status über
> `Theme.of(context).appColors`, NICHT IDA-Farben.

### 6.1 Stundenkonto-/Urlaubskonto-Widget (`lib/ui/widgets/app_konto_tile.dart`, NEU)
- **ExpansionTile** (IDA `ZeitStundenkontoListTile`/`ZeitVacationStatusListTile`): Kopf =
  Anwesend-Punkt + Saldo/Live-Wert; Body = Soll/Ist (Heute/Woche/Monat) bzw. Urlaubs-Aufstellung
  mit **+/−/=-Vorzeichen** (Anspruch, +Vortrag, −verfallen, =Gesamt, −genommen, −geplant,
  =Resturlaub), fette Summen. Wiederverwendbar in Admin-Detail UND MA-Selbstansicht (Daten der
  Selbstansicht aus `getMySelfService()`-Projektion §4.0, nicht aus direktem Read).

### 6.2 Stempel-Dashboard (Mitarbeiter-Self)
- **QuickAction „Jetzt stempeln"** (FlipFlop) auf `home_dashboards_v2`.
- **Live-Timer** als `AppLiveTimer` (`lib/ui/widgets/app_live_timer.dart`) via `Ticker`,
  `dateFetched`-Drift-Kompensation.
- **Zwei KPI-Kacheln** (Resturlaub | Stundensaldo) via `AppStatCard`/`AppMetricCard`.

### 6.3 Terminal-/Kiosk-Modus (Phase 2, `lib/screens/public/terminal_app.dart`)
- **Isolierte Route** `/terminal` (wie `/wunsch`/`/feedback`, VOR Provider-Kette/go_router —
  `isPublicTerminalRoute()` + Zweig in `_AppBootstrapState` + `_publicMode`-Getter, Pfad-
  Kollision mit go_router vermeiden). Eigener `Navigator`-Key.
- Große **Kommen/Gehen-`FilledButton`s** (≥80px), PIN-Pad ODER NFC, **Auto-Logout** via
  Countdown, Kundenlogo. **E1 (entschieden):** serverseitige Validierung + Rate-Limit + Lockout +
  App Check + org-Pin (siehe §1).

### 6.4 Mitarbeiter-Stammakte-Tabs (Erweiterung `personal_screen.dart` Detail)
- `_EmployeeStammdatenCard` um Sub-Sektionen: **Kinder** (`EmployeeChild`, mit „zählt für
  Freibetrag"-Hinweis §4.4), **Qualifikationen** (Gültigkeits-Badge), **Ausbildung**,
  **SV/DATEV** (inkl. BG/UV-Träger), **Lohntyp** (Gehalt/Stundenlohn-Toggle §4.3). IDA-Muster
  „Weitere Informationen" als `AppSectionCard` + ListTiles mit Anzahl-Badge.

### 6.5 Lohn-Detail (Erweiterung `_PayrollTab`/`_PayrollTile`)
- **Itemisierte `lines`** (Bezüge/Abzüge mit DATEV-Lohnart-Chip, steuerfrei/SV-frei-Marker),
  Zulagen-Editor-Sheet, **Brutto-Herleitungs-Banner** (Stunden×Lohn, §5.6),
  **Überstunden-Auszahlung-Sheet** (Betrag vorbelegt) + Sammel-Auszahlung-Button,
  **Richtwert-Disclaimer** (Einmalzahlung/Kl. V-VI/Midijob/2026-Sätze).

### 6.6 Abwesenheits-Antrag (Erweiterung `showAbsenceRequestSheet`)
- `AppSegmented` für Antragsart, Ganztägig/Halbtag-Toggle (AM/PM), Datums-Range, bedingtes
  Vertreter-Feld (Self-Exclusion), Anmerkung, **Live-Resturlaub-Vorschau-Karte** (§5.2),
  EFZG-/§9-Hinweis bei Krank. `autovalidateMode.onUserInteraction`.

### 6.7 Urlaubskalender / Abwesenheits-Übersicht (`lib/screens/abwesenheit_screen.dart`, NEU)
- Zeitraum-QuickFilter (7/30/90 Tage), Team-Filter (permission-gated), „Nicht-genehmigte
  ausblenden", farbcodierte Karten je Art.

### 6.8 Monatsabschluss (`lib/screens/monatsabschluss_screen.dart`, NEU, admin-only)
- Jahres-Liste mit org-Status-Badge **+ MA-Tabelle** („X von Y abgerechnet, Z Klärung" — pro-MA-
  Sperre sichtbar), Vormonat-Sperre, Abschließen/Zurücknehmen/Export je Status, Stundenzettel-/
  DATEV-Links.

### 6.9 Geteilte Bausteine nach `lib/ui` heben
- `AppAvatar`, `AppEmptyState`/`AppErrorState`/Skeleton (aus `home_screen` file-private
  `_EmptyState` heben), durchsuchbarer Listen-Wrapper.

---

## 7. Meilenstein-Plan (risiko-/nutzenorientiert umsortiert — Review-Verbesserung)

> **Umsetzungsstand (2026-06-22):**
> - ✅ **H1** (Settings-Fix): `defaults2026()` → Mindestlohn 13,90 €, Minijob-Grenze 603 €
>   (= Midijob-Untergrenze); `defaults2025` explizit. Test angezogen.
> - ✅ **M-Z1a** (Sollzeit-Modell, Vollausbau E3): `lib/models/sollzeit_profile.dart` +
>   FirestoreService/DatabaseService/PersonalProvider (admin-only, org-skopiert, Auto-ID,
>   gültig-ab, `activeSollzeitFor`/`sollzeitProfilesForUser` mit Tie-Break) + `firestore.rules`
>   (`sollzeitProfiles` admin-only) + Tests (`sollzeit_profile_test.dart`, Provider-Tests).
>   Kein neuer Composite-Index (watch ohne orderBy, clientseitig sortiert). **612+ Tests grün**,
>   `analyze` sauber, adversariales 3-Linsen-Review bestanden (3 Funde eingearbeitet).
> - ✅ **M-Settings** (`OrgPayrollSettings` editierbar + AG-Umlagen): `lib/models/org_payroll_settings.dart`
>   (NEU, dual-serialize, **eingebettete `PayrollSettings` als nested `settings`-Map**, Collection
>   `payrollConfig/{jahr}`, Doc-ID = Jahr, `defaultsFor`/`defaultSettingsForYear`-Fallback) +
>   Verdrahtung FirestoreService/DatabaseService/PersonalProvider (admin-only, org-skopiert, Audit
>   auf Erfolgspfad, `effectivePayrollSettings(jahr)` mit Override→`defaults<jahr>`-Fallback) +
>   `firestore.rules` (`payrollConfig/{jahr}` admin-only, orgId-Pin) + Editor-Sheet
>   `_OrgPayrollSettingsSheet` (Umlagen/SV-Sätze/Grenzwerte, Richtwert-/2026-Platzhalter-Banner) +
>   AG-Umlagen-Zeile im Lohn-Breakdown. **Design:** die AG-Umlage-**Sätze** (`umlageU1Rate`/`umlageU2Rate`/
>   `insolvenzgeldumlageRate`/`uvRate` + `u1Applies`) liegen auf `PayrollSettings` (Rechner liest sie
>   ohne Signaturänderung); `PayrollResult` trägt `employerU1/U2/Insolvency/Accident` + `employerLeviesTotalCents`,
>   Umlagen nur im regulären/Midijob-Zweig (Minijob = Pauschalsatz, keine Doppelzählung). **637 Tests grün**,
>   `analyze` sauber, adversariales **6-Linsen-Review** (24 Agenten) — 8 Funde eingearbeitet:
>   ① **HIGH** Periodenjahr-Bug (Rechner nutzte `payrollSettings`=Wall-Clock-Jahr → jetzt
>   `effectivePayrollSettings(month.year)`); ② **InsO-Default 0,06 %→0,15 %** (gesetzl. §360 SGB III, seit
>   2025); ③ `createdAt`-Persistenz (`if(createdAt==null)` statt totem `id==null`); ④–⑧ Tests
>   (Midijob-Umlagen-Exaktwerte, Hybrid-Fallback, Audit-Sink, `de_number_input`-Util-Unit-Tests).
>   Kein neuer Composite-Index. Richtwert-Disclaimer durchgängig.
> - ✅ **M0** (Urlaubsquellen-Migration + Vorrangregel §5.1): `lib/core/urlaub_calculator.dart`
>   (`resolveUrlaubstageJahr` — aktives `SollzeitProfile.urlaubstageJahr` → `annualVacationDays`
>   → `vacationDays` → gesetzl. Mindesturlaub; **Existenz** des Profils ist das Signal; **keine**
>   Teilzeit-Skalierung B1) + `lib/core/urlaub_migration.dart` (`buildUrlaubMigrationProfile`:
>   verbatim, deterministische Doc-ID `urlaub-migration-<userId>`, Default-30-Vertrag zählt **nicht**
>   als deliberater Altwert) + `PersonalProvider` (`effektiveUrlaubstage`,
>   `mitarbeiterMitOffenerUrlaubsMigration`, admin-only `migriereUrlaubstageInSollzeit` mit
>   Zukunfts-`hireDate`-Clamp, Audit pro Profil) + Deprecation-Doc-Kommentare auf beiden Altfeldern
>   (kein `@Deprecated`-Annotation → analyze sauber) + UI (selbst-versteckende `_UrlaubMigrationCard`
>   in der Übersicht; Stammakte zeigt/editiert nach Migration **read-only** den kanonischen Sollzeit-Wert
>   statt des toten Altfelds). **658 Tests grün**, analyze sauber, adversariales **5-Linsen-Review**
>   (20 Agenten) — **9 Funde eingearbeitet**: ① **HIGH** Stammakte-Altfeld-Divergenz (read-only-Gate);
>   ② Default-30-Vertrag kein Migrations-Trigger; ③ deterministische Doc-ID (Cloud-Idempotenz);
>   ④ Zukunfts-`hireDate`-Clamp; ⑤–⑨ Tests (at-Param/Zeitverlauf, Cloud-Pfad-Idempotenz, Admin-Gate).
> - ✅ **M-H** (HR-Sub-Entitäten + Kinderzähler-Einzelquelle): 3 dual-serialisierte Modelle
>   `lib/models/employee_child.dart` (Einzelquelle §4.4), `employee_qualification.dart` (`QualiErwerb`,
>   `istGueltig`), `employee_ausbildung.dart` — Collections `employeeChildren`/`employeeQualifications`/
>   `employeeAusbildungen`, admin-only, org-skopiert + volle Verdrahtung (FirestoreService/DatabaseService/
>   PersonalProvider CRUD/firestore.rules). **Kinderzähler-Einzelquelle §4.4:** `effektiveKinderzahl(userId)`
>   = gepflegte Kinder `count(zaehltFuerFreibetrag)` schlagen `EmployeeProfile.childrenCount`, nie beide;
>   in den Lohnrechner verdrahtet; Stammakte-Feld read-only sobald Kinder gepflegt. UI: `_EmployeeHrCard`
>   (3 Sub-Sektionen) + 3 Editor-Sheets + `_DateField`. **SV-/BG-DATEV-Felder am EmployeeProfile bewusst
>   auf M-D verschoben** (kein Konsument bis DATEV-Lohn). **711 Tests grün**, analyze sauber, adversariales
>   **5-Linsen-Review (13 Agenten) → 7 Funde eingearbeitet**: ① **HIGH** Speichermodus-Migration
>   (`cacheCloudStateLocally`/`syncLocalStateToCloud`) deckte die 3 neuen Collections nicht ab (→ stiller
>   Kinderzahl-/Steuer-Drift bei Moduswechsel); ② PV-Kinderlosenzuschlag von Freibetrag-Zähler **entkoppelt**
>   (Elterneigenschaft, § 55 SGB XI); ③ `createdAt`-Guard-Fix (3 Modelle + sollzeit); ④ Datum-Normalisierung
>   12:00; ⑤–⑦ `_DateField`-Clamp, all-false→0-Test, childrenCount-read-only-Gate.
> - ✅ **M-U** (Urlaubskonto/Abwesenheitsmatrix) — erledigt (eigene Modelle/Calculator/Provider/UI/Tests,
>   siehe Memory). Phase A damit abgeschlossen.
> - ✅ **M-B0 + M-L-a** (2026-06-23): Lohntyp-Brutto-Herleitung + Lohnarten/§3b/§39b — Details unten.
> - **Deploy vor Cloud-Nutzung:** `firebase deploy --only firestore:rules` (neue Blöcke
>   `sollzeitProfiles`, `payrollConfig`, `employeeChildren`, `employeeQualifications`, `employeeAusbildungen`,
>   **`payLineTypes`**).
>
> **✅ M-B0 + M-L-a — Lohnarten/Zulagen + §3b/§39b + Brutto-Herleitung (2026-06-23):**
> Modelle `PayLineType` (Katalog: `PayLineKind`{grundlohn,zulage,abzug,fixum,vwl,zuschlag3b,einmalzahlung},
> `PayWertTyp`,`PayInterval`, weiche DATEV-Lohnartnr-Validierung) + eingebettetes `PayrollLine`
> (+`PayrollLine.zuschlag3b`-Factory bindet `sfn_zuschlag`-Kern) + `PayrollRecord.lines`
> (**additiv/informativ — Einzelfelder bleiben für Brutto/Netto maßgeblich**). **M-B0:**
> `EmploymentContract.monthlyGrossCents` (M1, kanonisches Festgehalt, Vorrang vor PayrollProfile-Cache);
> `lib/core/lohn_herleitung.dart` (`grundlohnCents` §5.6 — KEINE separate grundlohn-Line, das ist
> `grossCents`; `grundlohnProStundeCents`; `sfn3bLine` aus Lage; `einmalzahlungSteuer` §39b-Wrapper+KiSt).
> **§39b (E8):** `german_tax.sonstigerBezug` Jahresverfahren (mit/ohne Bezug → Differenz; `_annualTaxes`
> mit `monthly` geteilt). **§3b (E9):** voller Kern in `sfn_zuschlag` (steuerfrei≤50€/h, SV-frei≤25€/h);
> `PayrollLine` trägt die volle Aufteilung. Wiring `payLineTypes` (admin-only): FirestoreService +
> DatabaseService (orgScoped, NICHT hybrid-gespiegelt §4.0) + PersonalProvider (CRUD/Audit nur Erfolgspfad/
> hybrid-Fallback/cache+sync) + `firestore.rules`. UI (`personal_screen`): Lohnarten-Katalog-CRUD-Sheets,
> Lohnzeilen-Editor (Katalog/ad-hoc, §3b-Live-Vorschau, §39b-Einmalzahlung-Vorschau), Brutto-Herleitungs-
> Banner (Stundenlöhner), Lines-Anzeige im Breakdown. **828 Tests grün**, analyze sauber, adversariales
> **6-Linsen-Review (32 Agenten) → Funde behoben** (mounted/§39b-Tests/KiSt-je-Land/Doc-Klarstellungen).
> **Bewusst auf M-L-b verschoben:** Überstunden-Auszahlung + Konto-Reduktion + pro-MA-Sperre (braucht
> M-Z1b `ZeitkontoSnapshot`); volle Netto-Integration der Lines; SV-Aufteilung der Einmalzahlung. **VwL**:
> als einzelne `vwl`-Zeilen über den Bezug/Abzug-Schalter modelliert (Auto-Kopplung AG-Zuschuss↔AN-Anteil
> verschoben — Modell hat 1 `vwl`-Kind, nicht 2).
>
> **Leitidee der Umsortierung:** Urlaub + HR-Stamm + editierbare Settings + Brutto-Herleitung
> liefern den **höchsten Nutzen für zwei Einzelhandelsläden bei geringster Cloud-Function-
> Komplexität** und kommen **VOR** den riskanten Brocken Mantelzeit/Stempeln/Terminal. Migration
> (M0) zuerst, sonst brechen Calculator-Annahmen für Bestandsdaten. Jeder Meilenstein endet mit
> `flutter analyze` sauber + `flutter test` grün + adversariales 3-Agenten-Review (wie M-A/B/C).

### M0 — Migration / Backfill / Vorrangregeln · **S–M** (NEU, ZUERST) · ✅ ERLEDIGT 2026-06-22
**Abhängigkeit:** keine. **Risiko:** Bestandsdaten-Inkonsistenz.
> ✅ Umgesetzt (nur Urlaubsteil; Kinder→M-H, Lohntyp→M-B0). Details im Umsetzungsstand-Block oben in §7.
> **Kern-Designentscheidungen:** Profil-Existenz = Vorrang-Signal; verbatim (B1); Default-30-Vertrag kein
> Migrations-Trigger (sonst org-weite Stubs); deterministische Doc-ID; Stammakte-Altfeld nach Migration read-only.
- **Urlaub:** `EmployeeProfile.annualVacationDays`/`EmploymentContract.vacationDays` → `Sollzeit
  Profile.urlaubstageJahr` migrieren (Vorrangregel §5.1), Altfelder deprecaten.
- **Kinder:** Einzelquellen-Regel etablieren (§4.4); Migrations-Schalter `childrenCount`↔
  `EmployeeChild`.
- **Lohntyp:** Bestandsverträge `salaryKind = stundenlohn` (Default, rückwärtskompatibel).
- **Zeit:** ~~bestehende `WorkEntry` → Ist-Minuten-Aggregation als Startwert fürs Stundenkonto~~ **→ nach M-Z1
  verschoben (Audit-Korrektur M8):** Stundenkonto/`ZeitkontoSnapshot`/Sollzeit existieren erst in M-Z1; die
  Legacy-Ist-Aggregation landet dort als **Eröffnungs-Snapshot** (explizit Legacy-Opening-Balance — `WorkEntry`
  hat kein `nettoMinutes`/keine Anrechnungsmatrix), nicht in M0.
- **Tests:** Migrations-Mapper round-trip, Vorrang-Auflösung, kein Datenverlust.

### M-U — Urlaubskonto + Abwesenheitsarten + Anrechnungsmatrix · **M** (hoher Nutzwert, niedrige CF-Komplexität)
**Abhängigkeit:** M0 (+ minimal Sollzeit für Teilzeitfaktor — kann mit M-Stamm-Sollzeit-Stub
starten). **Risiko:** BUrlG Werktags/Teilzeit, Verfall/Hinweisobliegenheit, EFZG-6-Wochen.
- **Modelle:** `AbsenceRequest`-Erweiterung, `Urlaubsanpassung`, `UrlaubskontoJahr`,
  `lib/core/abwesenheit_matrix.dart` (§5.4a), `lib/core/urlaub_calculator.dart`, `UrlaubsReport`,
  `lib/core/feiertage.dart`.
- **Provider:** `PersonalProvider` Anpassungs-/Jahres-CRUD + Urlaubskonto-Getter; geplant/
  genommen + automatischer Abzug.
- **Rules/Index:** `urlaubsanpassungen`/`urlaubskontoJahre` admin-only.
- **UI:** Antrag-Sheet (Live-Vorschau), `AppKontoTile` (Urlaub), `abwesenheit_screen`.
- **Tests:** Werktags/Teilzeit-Anspruch (Minijob 2–3 Tage/Wo), §5(2)-Rundung getrennt
  gesetzlich/vertraglich, Vortrag + 31.3.-Verfall **nur mit Hinweis**, Halbtag=0,5, EFZG-Grenze,
  §9-Gutschrift, Anrechnungsmatrix je Typ.

### M-H — HR-Sub-Entitäten (Kinder/Quali/Ausbildung/SV+BG) · **S–M** · ✅ ERLEDIGT 2026-06-23 (SV/BG → M-D)
**Abhängigkeit:** Stammakte (vorhanden). **Risiko:** gering.
- **Modelle:** `EmployeeChild` (Einzelquelle §4.4), `EmployeeQualification`, `EmployeeAusbildung`,
  SV-/BG-UV-Felder am `EmployeeProfile`. Alle admin-only.
- **UI:** Sub-Sektionen im Stammakte-Detail. **Tests:** dual-serialize round-trip je Modell,
  Kinderzähler-Einzelquelle.
> ✅ Umgesetzt — Details im Umsetzungsstand-Block oben in §7. Die 3 Sub-Entitäten + Kinderzähler-Einzelquelle
> sind fertig; die **SV-/BG-UV-Stammdatenfelder am `EmployeeProfile`** sind **bewusst auf M-D verschoben**
> (reine DATEV-Stammdaten ohne Konsument bis zum Lohn-DATEV-Export; bei M-D mitziehen).

### M-Settings — `OrgPayrollSettings` editierbar + AG-Umlagen · **S–M** (Review: VOR M-L) · ✅ ERLEDIGT 2026-06-22
**Abhängigkeit:** keine. **Risiko:** Default-Sätze nicht als amtlich präsentieren.
> ✅ Umgesetzt — Details im Umsetzungsstand-Block oben in §7. Akzeptanzpunkte alle erfüllt
> (editierbar, U1/U2/InsO/UV, `defaults<jahr>`-Fallback, Calculator liest Settings statt hartkodiert,
> Richtwert-Banner). **Periodenjahr-Auflösung** im Lohnrechner über `effectivePayrollSettings(month.year)`.
- **Modell:** `OrgPayrollSettings` (`payrollConfig/{jahr}`), inkl. **U1/U2/InsO/UV** (§4.3).
- **Calculator:** AG-Umlagen in AG-Kosten (`payroll_calculator`), Sätze aus Settings statt
  hartkodiert.
- **UI:** Settings-Editor (admin) + **Richtwert-/2026-Platzhalter-Hinweis**.
- **Tests:** AG-Kosten mit/ohne U1 (<30 MA), U2/InsO immer, Fallback auf `defaults<jahr>`.

### M-B0 — Lohntyp + Brutto-Herleitung (Brücke Zeit→Lohn) · **M** · ✅ ERLEDIGT 2026-06-23
> ✅ Umgesetzt — Details im Umsetzungsstand-Block oben (M-B0 + M-L-a). `salaryKind` (vorab) +
> `monthlyGrossCents` (M1) + `lohn_herleitung.dart` + Brutto-Banner.
**Abhängigkeit:** M-Settings (Sätze), M-U (bezahlte Abwesenheit für Stunden). **Risiko:**
Stunden→Brutto-Korrektheit, Midijob-Vereinfachung dokumentieren.
- **Modelle:** `EmploymentContract.salaryKind`/`monthlyGrossCents`, `lib/core/lohn_herleitung.dart`.
- **Calculator:** `grundlohn`-Line aus `salaryKind` (Festgehalt | Stunden×Lohn).
- **UI:** Lohntyp-Toggle (§6.4), Brutto-Herleitungs-Banner (§6.5).
- **Tests:** Stundenlöhner-Brutto = Stunden×Satz, Festgehalt, bezahlte Abwesenheit zählt,
  unpaid/Krank>6Wo zählt nicht (Matrix).

### M-L — Lohnarten/Zulagen + Lines + **§3b (voll)/VwL/§39b-Einmalzahlung** + Überstunden-Auszahlung · **L** (E9/E8 erhöhen Umfang)
> ✅ **M-L-a ERLEDIGT 2026-06-23** (statische Lines + §3b/VwL/§39b-Einmalzahlung + Grundlohn-Bezug,
> Details im Umsetzungsstand-Block oben). ⏳ **M-L-b OFFEN:** Überstunden-Auszahlung (`Lohnstunden`) +
> Stundenkonto-Reduktion + pro-MA-Abrechnungssperre — hängt an M-Z1b (`ZeitkontoSnapshot`).
**Abhängigkeit:** M-B0 (Grundlohn-Line), M-Z (Stundenkonto für Auszahlung). **Risiko:** %-vs-€,
**§3b-Aufteilung (steuerfrei/SV-frei-Grenzen 25/50 €/h, E9)**, **§39b-Jahresverfahren (E8)**,
Auszahlung↔Konto-Konsistenz.
- **Modelle:** `PayLineType` (inkl. `zuschlag3b`/`vwl`/`einmalzahlung`),
  `PayrollRecord.lines`/`PayrollLine` (mit `steuerfrei`/`svFrei`-Anteilen), `Lohnstunden`.
- **Core:** `german_tax.sonstigerBezugTax(...)` (§39b Abs. 3, E8); §3b-Aufteilung in
  `lohn_herleitung.dart` (E9, Default an).
- **Provider:** Lohnart-CRUD, Zulagen-Zuordnung, Auszahlung (Line + Konto-Reduktion),
  Sammel-Auszahlung; Sperre via `ZeitkontoSnapshot.abgerechnet` (pro MA).
- **UI:** Zulagen-/Auszahlung-Sheets, Lines-Anzeige (steuerfrei/-pflichtig getrennt), Richtwert-Disclaimer.
- **Tests:** %-Line, VwL-Paar (Zuschuss+Abzug), **§3b-Aufteilung (Grundlohn <25/25–50/>50 €/h)**,
  **§39b-Jahresverfahren (Differenzsteuer Bezug)**, Auszahlung reduziert Konto, gesperrter Monat
  blockiert, Sammel-Batch.

### M-Z1 — Sollzeit-Profil (Vollausbau) · **M**
**Abhängigkeit:** M0 (Stub), M-U (urlaubstageJahr-Quelle). **Risiko:** Feiertagskalender.
- **Modelle:** `SollzeitProfile` (voll, gültig-ab), `ZeitkontoSnapshot`,
  `lib/core/stundenkonto_calculator.dart`.
- **Provider/Rules:** admin-only CRUD; Collections + Keys (Hybrid: nicht gespiegelt §4.0).
- **UI:** Sollzeit-Editor-Sheet, `AppKontoTile` (Stunden).
- **Tests:** Soll je Wochentag/Feiertag/Halbtag, Monatsarbeitszeit, kumulierter Saldo.

### M-Z2 — Mantelzeit / Stempeln + Compliance-Event-Spiegel + Abrechnungssperre · **L** (riskantester Brocken)
**Abhängigkeit:** M-Z1. **Risiko (hoch):** offene Buchung/Live-Timer-Drift, **Compliance-Event-
Aggregat (§5.10, eigener Posten!)**, Überlappungs-/Sperr-Validierung Client↔Function synchron.
- **Modelle:** `Mantelzeit` (+`MantelzeitAntrag`), `Monatsabschluss`.
- **Cloud Functions:** `clockIn`/`clockOut`/`upsertMantelzeitBatch` (`europe-west3`,
  Batch-Limit 50, `assertSameOrg`, `assertNichtAbgerechnet` **pro MA**, Überlappungs-Check
  409→`StateError`), `getMySelfService()` (Selbstansicht-Projektion §4.0).
- **Compliance:** Tages-Aggregation (10h/Pause/Ruhezeit) auf Event-Modell — **neu in
  `compliance_service.dart` UND `functions/index.js`** (§5.10), gleiche Codes/Schwellen.
- **UI:** Stempel-Dashboard + FlipFlop + `AppLiveTimer`; Mantelzeit-Liste (Schloss/Klärung/
  Soft-Delete).
- **Tests:** Kommen ohne Gehen, Doppel-Kommen→Fehler, `nettoMinutes`, Über-Mitternacht,
  Ruhezeit-Aggregat über Tagesgrenze, Sperre wirft, Soft-Delete.

### M-MA — Monatsabschluss-Workflow (pro-MA-Sperre) + Stundenzettel-PDF · **M**
**Abhängigkeit:** M-Z2 + M-L. **Risiko:** sequenzielle Status-Maschine, **pro-MA-Klärungs-Gate**.
- **Provider/Service:** Status-Übergänge, Snapshot-/Lohnstunden-Fortschreibung beim Abschluss
  (atomar), Stundenzettel-PDF via `PdfService`, Cloud-Function-Sperrsetzung pro MA.
- **UI:** `monatsabschluss_screen` (org-Status + MA-Tabelle).
- **Tests:** Vormonat-Sperre (sequenziell), Klärung eines MA blockiert **nur** ihn, Abschluss
  schreibt Snapshot + setzt `abgerechnet` pro MA, Rücknahme.

### M-D — DATEV-Lohn-Bewegungsdaten-Export · **M** (E5: **ja**, hinter Feature-Flag)
**Abhängigkeit:** M-MA. **Risiko:** Industrieminuten/Spalten/Rundung + Lohnartnummern müssen den
DATEV-Mandanten treffen (mandantenspezifisch, daher Feature-Flag).
- **Core:** `lib/core/datev_lohn_mapping.dart` (statisch, aus §5.4a-Matrix),
  `ExportService.buildDatevLohnCsv` (tages-/monatsweise, Restausgleich-Rundung §5.11) + `.ini`.
- **Einmalzahlung (E8):** Sonderbezüge als **Jahressonderzahlung** kennzeichnen (Bearbeitungs-
  schlüssel/Lohnart, analog LODAS `ABRUF_JAHRESSONDERZAHLUNG`), damit DATEV §39b fährt.
- **UI:** Export-Button im Monatsabschluss.
- **Tests:** Tagesanteil Σ exakt 1,00/0,50 (Restausgleich), Industrieminuten, Monats-Aggregation,
  Jahressonderzahlung-Kennzeichen, Nulleinträge gefiltert.

### M-X — Terminal/Kiosk-Modus · **L** (Phase 2, E1: Empfehlung) — separat, nach Kern
**Abhängigkeit:** M-Z2. Isolierte Route, PIN/NFC, Auto-Logout, **Rate-Limit/Lockout/App Check/
org-Pin** (E1, serverseitig — kein client-`SHA1` wie IDA). Eigenes Security-Review zwingend (§1/§9).

### M-R — Recruiting · **M** (Phase 2, E4: zurückgestellt) — separat
Zurückgestellt bis Zeit/Lohn/Urlaub produktiv. Dann: `Stellenausschreibung`/`Bewerbung`, eigener
admin-Screen.

**Empfohlene Reihenfolge:**
**Korrigierte Reihenfolge (Audit-Korrektur H4/H5/M8) — Sollzeit-Modell vorgezogen, M-L gesplittet:**
**M0 → M-H → M-Settings → M-Z1a (Sollzeit-Modell, per-Wochentag) → M-U → M-B0 → M-L-a (statische Lines +
§3b/VwL/Einmalzahlung) → M-Z1b (ZeitkontoSnapshot + Calculator) → M-Z2 (Mantelzeit/Stempeln) → M-L-b
(Überstunden-Auszahlung + pro-MA-Sperre) → M-MA → (M-D) → [Phase 2: M-X → M-R]**

> **Phasung (Audit-Korrektur):** zu groß für einen Durchlauf → **Phase A** = M0 · M-H · M-Settings · M-Z1a · M-U
> (höchster Nutzen, niedrige CF-Komplexität, korrekte Teilzeit-Zahlen ab Tag 1); **Phase B** = M-B0 · M-L-a ·
> M-Z1b · M-Z2 · M-L-b · M-MA · M-D. Begründung: M-U/M-B0 brauchen das **echte** per-Wochentag-Sollzeit (kein Stub,
> H5); M-L-bs Auszahlung braucht das Stundenkonto aus M-Z1b (H4). Ursprüngliche Reihenfolge unten ist überholt.

---

## 8. „Wenn du X änderst, ändere auch Y" (neue Kopplungen)

1. **Feld zu `Mantelzeit`/`SollzeitProfile`/`ZeitkontoSnapshot`/`UrlaubskontoJahr` etc.** → 6
   Stellen (`toFirestoreMap`/`fromFirestore`/`toMap`/`fromMap`/`copyWith`+`clearX`) + falls durch
   Callable: snake_case parse/serialize in `functions/index.js`.
2. **Neue Mantelzeit-/Pausen-/Höchstarbeitszeit-Compliance-Regel** → `compliance_service.dart`
   **UND** `functions/index.js` (Codes/Schwellen) — **inkl. der neuen Tages-Aggregation §5.10**.
3. **Neue Abwesenheitsart (`AbsenceType`)** → `.value`/`label`/`fromValue`-Default **+**
   `lib/core/abwesenheit_matrix.dart` (§5.4a: bezahlt/sollmindernd/urlaubswirksam/§3b/Ausfall-
   schlüssel) **+** `datev_lohn_mapping.dart` **+** Urlaubs-/Stundenkonto-Calculator.
4. **Anrechnungsmatrix-Regel (§5.4a)** → wirkt auf **Stundenkonto, Brutto-Herleitung (§5.6),
   Urlaubsanspruch, DATEV-Mapping** gleichzeitig — eine Quelle, vier Leser.
5. **Urlaubsquelle/-vorrang (§5.1)** → bei jeder Änderung an `urlaubstageJahr`/`annualVacationDays`/
   `vacationDays` die **Vorrang-/Migrationsregel** und den Teilzeitfaktor mitziehen.
6. **Kinderzähler-Quelle (§4.4)** → `german_tax.childCount` immer aus **genau einer** Quelle;
   `EmployeeChild`-Änderung darf `childrenCount` nicht doppelt zählen.
7. **Neue Collection** → `FirestoreService`-Getter **+** `firestore.rules` (**admin-only**,
   `sameOrg`, orgId-Pin; KEIN self-read §4.0) **+** `DatabaseService`-Key (org-skopiert,
   `_orgScopedCollectionKeys`) **+** Hybrid-Spiegel-Entscheid laut §4.0-Tabelle **+** lokaler
   Hybrid-Fallback im Provider.
8. **Neuer Cloud-Function-Schreibpfad** (`clockIn`/`clockOut`/Abschluss/`getMySelfService`) → 3
   Enforcement-Punkte: Callable (snake_case `toMap`-Payload!), `firestore.rules`,
   `assertSameOrg`/`assertNichtAbgerechnet` synchron.
9. **`abgerechnet`-Sperre (pro MA)** → Schreibvalidierung in **Cloud Function UND Client-Mutatoren
   UND UI** (Schloss-Icon/Edit ausblenden) konsistent; org-`Monatsabschluss` aggregiert nur.
10. **Snapshot-Trigger (Monatsabschluss)** → `ZeitkontoSnapshot` + `Lohnstunden` + `Urlaubskonto
    Jahr`-Vortrag atomar fortschreiben.
11. **`PayrollRecord.lines`** → Netto-/Summen-Getter (`linesTotalCents`,
    `steuerpflichtigeLinesCents`) + PDF-Ausweis + DATEV-Lohn-Export müssen Lines (inkl.
    steuerfrei/SV-frei-Flags) berücksichtigen.
12. **`OrgPayrollSettings`-Satz (U1/U2/InsO/UV/KV-Zusatz)** → `payroll_calculator` (AG-Kosten) +
    UI-Editor + Richtwert-Disclaimer + DATEV-AG-Anteil.
13. **`EmploymentContract.salaryKind`** → `lohn_herleitung.dart` (Festgehalt vs. Stunden×Lohn) +
    Lohn-Editor-UI + Brutto-Banner.
14. **Neuer admin-Screen** (Monatsabschluss/Abwesenheit) → `AppRoutes`-Konstante + `_sectionRoute`
    + `_isLocationAllowed` + Eingang im Verwaltungsmenü (`app_nav_menu.dart`).
15. **Neue isolierte Route `/terminal`** (Phase 2) → `isPublicTerminalRoute()` + Zweig in
    `_AppBootstrapState.build` + `_publicMode`-Getter (keine go_router-Kollision).
16. **Neuer Composite-Index** für jede neue `where`+`orderBy`-Query (Mantelzeit `userId`+`kommen`,
    Snapshot `userId`+`jahr`+`monat`, Sollzeit `userId`+`gueltigAb`) → `firestore.indexes.json` +
    deployen.

---

## 9. Compliance / Recht

- **ArbZG/JArbSchG:** Ruhezeit 11h (660 min), Pause 30@6h/45@9h, max 10h/Tag (600 min), Nacht
  23–06 — bereits im Spiegel. Mantelzeit-Stempeln prüft **erneut** über die neue **Tages-
  Aggregation (§5.10)**, nicht nur „dieselbe Regel".
- **BUrlG:** §3/§5(2) **werktagsgenauer + teilzeitskalierter** Anspruch (§5.1), getrennte Rundung
  gesetzlich/vertraglich; §7(3) Übertragung + **31.3.-Verfall nur mit Hinweisobliegenheit**
  (EuGH/BAG, §5.2); §9 Erkrankung im Urlaub → Gutschrift; Mindesturlaub 24 Werktage (Warnung).
- **EFZG:** Lohnfortzahlung Krank **6 Wochen** (42 Kalendertage je Fall), danach Krankengeld —
  abgebildet in der Anrechnungsmatrix (§5.4a), wirkt auf Stundenkonto + Brutto-Herleitung.
- **Lohnsteuer/SV:** §32a EStG (Richtwert) bereits implementiert. **§39b-Abs.-3-Jahresverfahren
  für Einmalzahlungen (E8, §5.8a)** und **volle §3b-Aufteilung (E9, §5.8b)** werden umgesetzt — sind
  also **keine** Vereinfachungen mehr. **Disclaimer „unverbindlicher Richtwert" Pflicht** in
  UI+PDF+DATEV bleibt, **explizit** für: Steuerklasse **V/VI**-Näherung (§5.9), **Midijob**-Zweig-
  Vereinfachung (§5.7) und **2026-Sätze als Platzhalter** (§4.3). AG-Umlagen U1/U2/InsO + BG/UV
  ergänzt (§5.7). SV-Beitragsgruppen/BG nur Stammdaten (kein zertifiziertes ELStAM/PAP).
- **DSGVO Art. 9 — bewusst weggelassen:** GdB/Schwerbehinderung, Aufenthaltstitel/Flüchtling,
  PEP; Personengruppe nur optionaler DATEV-String. Konfession bleibt (lohnrelevant, vorhanden).
  EAU nur als Flag/Upload-Referenz, kein Diagnosedatum.
- **Bewusst weggelassen (dokumentiert):** **Pfändung/Lohnabtretung** (Nettopfändung/Freibeträge —
  Review-Lücke, hier explizit als *out of scope* festgehalten), „Anrechnung bis Null"
  (Schlechtwetter/S-KUG, E6), LODAS-Stammdatenexport, DATEV-Cloud-OAuth-Rückimport, dynamische
  DZeLt-Formel-Eval (Sicherheitsrisiko), A351K, Ticket/LV/Asset/Material-Kostenträger.
- **Terminal-PIN (E1):** schwacher Client-Hash aus IDA **nicht** übernehmen → serverseitige
  Validierung **+ Rate-Limiting + Lockout + App Check + org-Pin** (§1, Phase-2-Security-Review).

---

## 10. Verifikation & Deploy

**Pro Meilenstein:**
```bash
flutter pub get
flutter analyze                 # sauber, lints nicht erweitern
flutter test                    # alle grün (aktuell 555+; je M wächst)
flutter test --coverage         # kritische Calculator/Provider ≥ 70 %
flutter run --dart-define=APP_DISABLE_AUTH=true   # Offline-Smoke-Test
```
**Reine Rechenlogik isoliert testen** (dependency-frei, wie `german_tax_test.dart`, feste
Referenzdaten, `.code`/Cent-genaue Assertions, **keine int-Gleichheit** bei FakeFirestore-
Doubles): `feiertage`, `abwesenheit_matrix`, `urlaub_calculator` (Werktags/Teilzeit/Verfall/
EFZG), `stundenkonto_calculator`, `lohn_herleitung` (Stunden×Lohn/Festgehalt), `datev_lohn_
mapping` (Restausgleich-Rundung, §5.11).

**Cloud (bei echtem Firebase, je Meilenstein):**
```bash
firebase deploy --only firestore:rules            # neue admin-only-Blöcke
firebase deploy --only firestore:indexes          # Mantelzeit/Snapshot/Sollzeit-Indizes
firebase deploy --only functions                  # clockIn/clockOut/upsertMantelzeitBatch/getMySelfService/Abschluss
```
**Reihenfolge zwingend:** Rules+Indizes **vor** Functions **vor** Client-Nutzung der Cloud-Pfade.
`FIREBASE_FUNCTIONS_REGION` ⟷ `const REGION` in `functions/index.js` synchron halten.

**Adversariales Review je Meilenstein** (wie M-A/B/C): 3-Agenten, Funde beheben, dokumentieren.
**Besonders prüfen:** Compliance-Event-Aggregat-Spiegel (§5.10), pro-MA-Sperre vs. org-Abschluss,
Urlaubs-Werktags/Teilzeit-Korrektheit, Kinder-/Urlaubs-Einzelquelle, Richtwert-Disclaimer.

**Memory-Update nach Abschluss:** Eintrag in `memory/MEMORY.md` + neue Notiz
`memory/zeitwirtschaft-modul.md` (Seams, pro-MA-Sperrhierarchie, Event-Compliance-Spiegel,
Urlaubs-/Kinder-Einzelquelle, Footguns).

---

## 11. Verifikations-Anhang (gegen echten Quellcode geprüft, 2026-06-22)

> Dieser Plan wurde nach Erstellung **adversarial gegen die Quell-Repos verifiziert** (8 parallele
> Prüfer über ida-PHP/MySQL, ida-Vue, ida_app/Flutter, idadwh/DATEV + WorkTime; jede konkrete
> Aussage mit Datei:Zeile belegt). **Gesamt-Trefferquote ≈ 85 %** (Schema 70 %, PHP-Logik 80 %,
> Vue-HR 90 %, Vue-Zeit 90 %, Flutter 88 %, DATEV 92 %, UI 88 %, WorkTime-IST 90 %). Keine breite
> Halluzination — fast alle Architektur-Konzepte, Funktions-/Klassen-/Interface-Namen stimmen.
> Die unten gelisteten Korrekturen sind oben bereits eingearbeitet. Voller Report:
> `plan/ida-hr-zeit-uebernahme-VERIFIKATION.md`.

### 11.1 Eingearbeitete Korrekturen

| # | Schwere | Plan sagte | Korrekt (belegt) | Beleg |
|---|---|---|---|---|
| K3 | **hoch** | AG-Umlagen U1/U2/InsO in `hr_lohnnebenkosten` | kassenindividuell in `crm_krankenkassen.umlage_1/2/3`; `hr_lohnnebenkosten` = nur KV/PV/AV/RV/UV+BG | `1_ida_master.sql:10031-10033` |
| K1 | mittel | `hr_tagesabschluss` | `hr_zeit_tagesabschluesse` (`tag`=YYYYMMDD-int) | `1_ida_master.sql` |
| K2 | mittel | `ma_quali` | `hr_ma_qualifikationen` (+ `hr_qualifikationen`/`hr_qualifikationsarten`) | `1_ida_master.sql` |
| K4 | mittel | `hr_kinder` trägt Kind-Stammdaten | reine Verknüpfungstabelle; Name/Geburtstag am Personensatz → `EmployeeChild` ist Neukonstruktion | `1_ida_master.sql` |
| K7 | mittel | Urlaubsanspruch werktagsgenau+Teilzeit = ida-Quelle | ida rechnet **Kalendertag-Zwölftelung**, ohne Teilzeit → werktags+Teilzeit ist Plan-Neudesign (§5.1) | `HR_functions.inc.php:228-263` |
| K8 | mittel | Resturlaub inkl. 31.3.-Verfall/geplant = ida-Quelle | ida = Vortrag+Anspruch+Anpassung−genommen; Verfall/Hinweisobliegenheit = Plan-Neudesign (§5.2) | `ZEITEN_functions.inc.php:818-872` |
| K5 | niedrig | `hr_kpi_setSicknessRate` | `hr_kpi_setSicknessRatePerPerson` / `hrfunc_setSicknessRatePerPerson` | `HR_functions.inc.php:1041/774` |
| K11 | niedrig | `ZeitAbrechnungsstatus` (als Vue-Quelle) | Vue = `state.hr.abgerechnetBis` (`ZeitCheckList.vue`); `ZeitAbrechnungsstatus` ist ida_app-Flutter | `ZeitCheckList.vue:1097` / `zeit_abrechnungsstatus.dart` |
| K10 | niedrig | „Größter-Rest-Verfahren (Hare-Niemeyer)" | idadwh: `sumPreservingRounding`/`sortRoundingErrors` (Restausgleich, kein exakter Hare-Niemeyer) | `src/utils/numberHelper/rounder.ts:76-124` |
| K16 | niedrig | Zeiten pauschal Unix-ts | Punkt-in-Zeit = Unix-Sek.; Perioden = `YYYYMM`/`YYYYMMDD`-Int | `1_ida_master.sql` (hr_zeitkonto.jahrmonat, …) |
| K15 | niedrig | `EmployeeProfile` „34 Felder" | ≈31–37 je Zählweise → „≈34" | `employee_profile.dart:205-257` |

### 11.2 Zusätzliche Befunde (Lücken/Über­zeichnungen — in den Plan eingeflossen)

- **WorkTime hat mehr als der Plan teils suggerierte:** `PayrollProfile.monthlyGrossCents`,
  `EmployeeProfile.healthInsuranceSurchargePercent` (MA-KV-Zusatz-Override) und
  `careChildlessSurchargeRate` (PV-Kinderlosenzuschlag) sind **bereits implementiert** → M-B0
  ist kleiner (Brutto-Feld existiert, nur `salaryKind`-Flag + Auto-Herleitung fehlen). §2/§3 korrigiert.
- **ida kodiert Lohntyp bereits:** `hr_gehalt.fixum_bezug`/`gehalt_fixum`/`stundenlohn` + `hr_gehaltstyp` →
  `salaryKind` hat eine erprobte Vorlage (in §3 ergänzt).
- **„Keine versionierten Schemata" war falsch:** volle CREATE-TABLEs in `__deployment/db/sql/1_ida_master.sql`
  + 58 datierte Migrationen in `__development/db/migrations/` = beste Quelle für exakte Spalten/Typen (§2 ergänzt).
- **`hr_sollzeiten` ist vollständig** (Rahmen-/Kernzeit/Karenz/Rundung/Kappung/fakultativ/Gleitzeit/
  `urlaub_als_stunden`) → E3 hat eine fertige Referenz (Hinweis an E3 ergänzt).
- **25/50-Überstundenzuschlag** ist kundenspezifisch (Mandant „Funke", Feature-Flag) — bewusst **nicht**
  als WorkTime-Standardregel übernommen (war auch nicht im Plan-Körper).
- **`ongoing`/laufende Buchung** ist in ida ein echtes persistiertes Feld (Vue+Flutter); WorkTimes
  „Getter gehen==null" ist eine bewusste Designabweichung, kein ida-Bestand.

### 11.3 Als KORREKT bestätigt (verlässlich)

Zwei-Ebenen-Zeitmodell (Mantelzeit/Istzeit) real; 7-Status-Monatsabschluss (`zeitMonatabschlussConstants.ts`,
sequenziell) exakt; `gueltig_ab`-Historisierung durchgängig; Pflichtpausen 30@6h/45@9h
(`constants.php`); Stundenkonto = Ist−Soll kumuliert; Funktionsnamen `hrfunc_getUrlaubsanspruchInRange`/
`zeitfunc_getResturlaubByTimestamp`/`zeitfunc_getMantelzeitInfoByDay`/`hrcon_*` (114 Endpunkte) exakt;
idadwh-Bausteine (DZeLt, A351K, LODAS, LuG tages-/monatsweise, HR-Payroll-Rückimport) real; ida_app-UI
(Seed-Rot #B7172F, Scaffold #F0F0F0, ExpansionTile-Konto-Tiles, Terminal/Kiosk PIN/RFID/NFC) real;
WorkTime-IST (nur `hourlyRate`, kein `salaryKind`, `_midijobBase` reduziert beide Zweige gleich,
admin-only Rules, `AbsenceType{vacation,sickness,unavailable}`) korrekt.
