# Verbesserungsplan: Duplikate entdoppeln & Komponenten koppeln

> ## Umsetzungsstand 2026-06-29 (Aufräum-/Konsolidierungs-Lauf)
>
> **Erledigt & getestet** (alle hinter `flutter analyze` + `flutter test` grün):
> - **F1** Zentraler `EmploymentContractResolver.activeOn` (`lib/core/employment_contract_resolver.dart`,
>   + Tests) — Personal- und Work-Provider bedienen sich daraus, keine divergierende
>   „aktiver Vertrag"-Implementierung mehr (fallbackToLatest in beiden identisch).
> - **F2** `PersonalProvider.personnelCostFor` + `deriveGrossCentsFor` + `abgerechnetesIstMinutesFor`
>   (einheitliche Brutto-/AG-Kosten + SSoT-Ist).
> - **L1** `_costByEmployee`/`_costBySite`/`WorkProvider.totalWageThisMonth` über F2 →
>   **Festgehalt-Lücke geschlossen** (Monatslöhner nicht mehr 0 €).
> - **L2** Lohn-Editor-Brutto aus `abgerechnetesIstMinutesFor` (inkl. bezahlter Abwesenheit;
>   behebt nebenbei screens-ui #53 falscher Monat). **L3** Festgehalt Vertrag-zuerst + Doku.
>   **L4** toter `incomeTaxRateFor()` entfernt, `soliRate/soliThresholdCents` als veraltet markiert.
> - **Z3** Zeitwirtschaft-Org-Monatslader: CLAUDE.md-Fehlermuster (hybrid→lokal/cloud-only→rethrow).
>   **Z4** Statistik-Soll aus Vertrags-Tagessoll statt `settings.dailyHours`. **Z5** Zeitkonto-Card
>   „Ist (gearb.)" klar gelabelt. (**Z1** war bereits erledigt.)
> - **M4** verbrauchte Einladung wird beim Annehmen deaktiviert (+ Rules-Relaxation: nur Deaktivieren).
>
> **Noch offen** (eigene fokussierte Läufe empfohlen):
> - **M1** Jahresurlaub-Konsolidierung auf `SollzeitProfile` + Migration + `UserSettings.vacationDays`
>   entfernen (6-Stellen-Regel, MA-Anzeige-Risiko) — Resolver `effektiveUrlaubstage` existiert bereits.
> - **M2** Quali-Gültigkeit (`gueltigBis`) in die Schichtverteilung (Compliance-Spiegel #2!) — bzw.
>   Minimal-Variante Team-Editor-Warnung. **M3** Anzeige-Stundensatz Vertrag-zuerst in
>   `pdf_service`/`month_report` (deferred: würde In-App↔PDF-Inkonsistenz erzeugen ohne weite API-Änderung).
> - **M5** Ownership doppelt editierbarer Felder (read-only mit Quellhinweis). **Q1** `CostTypeRole`
>   statt `name.contains` + sichtbare Warnung + Nachbuchung. **Q2** dedizierter `AbsenceProvider`
>   (dreifacher Stream). **Q3** Summary-Card V1/V2-Dedup. **L5/Z2** bleiben user-gated.
>
> Details der offenen Problem-Befunde: [../probleme/README.md](../probleme/README.md).



> Stand: 2026-06-28. Quelle: tiefe Multi-Agent-Code-Analyse (6 Domänen kartiert,
> 31 Befunde, 23 am Code bestätigt, 7 als bewusste/dokumentierte Trade-offs
> widerlegt). Dieser Plan ist der **Konsolidierungs-Fahrplan** — er baut kein
> neues Feature, sondern entfernt Doppelhaltung von Daten und schließt fehlende
> Datenflüsse, v.a. **Lohn ↔ Personal ↔ Zeit**.

## 1. Die zwei bestätigten Grundprobleme

Beide Vermutungen des Auftraggebers sind am Code belegt:

**(A) Dieselbe Sache wird an mehreren Stellen gespeichert/gepflegt.**
Ein „Mitarbeiter" ist über `AppUserProfile` (Login/Rolle/Name/Lohn-Settings),
`EmploymentContract` (Stunden/Satz/Festgehalt), `SollzeitProfile` (Soll/Urlaub),
`EmployeeProfile` (HR-Stammakte) und `EmployeeSiteAssignment` (Standort/Quali)
verteilt. Mehrere Felder existieren **zwei- bis vierfach**: Stundensatz, Jahres-
urlaub (4×), Festgehalt (2×), Rolle/Rechte (2×), Qualifikation (2×). Gepflegt
wird er an **zwei getrennten Oberflächen** ohne gemeinsamen Editor:
`TeamManagementScreen` (AppUser+Vertrag+Standort) und `PersonalScreen`
(Stammakte+Kinder+Quali+Lohn). → genau das „Doppelte" zwischen *Personal* und
*Teamverwaltung*.

**(B) Komponenten hängen nicht voneinander ab, obwohl sie sollten.**
Der Lohn rechnet teils mit **eigenen, abweichenden Eingaben** statt aus Personal/
Zeit abzuleiten: drei unabhängige „Monatslohn"-Berechnungen, der manuelle Lohn-
Editor nimmt rohe `workedHours` statt das Zeitkonto-Ist, die Statistik rechnet
Soll aus `settings.dailyHours` statt aus `SollzeitProfile`, „aktiver Vertrag"
ist zweimal verschieden implementiert. Ergebnis: für *denselben* Mitarbeiter/
Monat können je nach Bildschirm **verschiedene Stunden-, Soll- und Lohnzahlen**
herauskommen.

## 2. Ziel-Architektur — eine Quelle der Wahrheit (SSoT) je Konzept

```
                 ┌───────────────────────────────────────────────┐
   IDENTITÄT     │ AppUserProfile  (uid, name, email, role, perms)│  ← SSoT Identität
                 └───────────────────────────────────────────────┘
   VERTRAG       EmploymentContract (versioniert: Stunden, Satz,      ← SSoT Lohn-Konditionen
                  Festgehalt, Typ, validFrom/Until)
   SOLL/URLAUB   SollzeitProfile (Soll-Arbeitszeit, Urlaubsanspruch)  ← SSoT Soll & Urlaub
   HR-STAMM      EmployeeProfile (Anschrift, SV, Bank, Steuer, Kinder)← SSoT HR-Personaldaten
   IST-ZEIT      WorkEntry / ClockEntry → Zeitkonto-Snapshot          ← SSoT geleistete Zeit
                 ───────────────────────────────────────────────────
   LOHN          PayrollRecord  =  ABLEITUNG aus Vertrag (Satz/Fest-  ← KEINE eigenen Stammdaten,
                  gehalt) + Sollzeit (Soll) + Zeit (Ist) + Stammakte    nur Berechnung + ein-
                  (Steuer/Kinder/SV) ; speichert eingefrorenen Snapshot  gefrorener Snapshot
   BUCHHALTUNG   JournalEntry  =  Auto-Buchung aus freigegebenem Lohn  ← stabile ID-Kopplung
```

**Leitregeln:**
1. Jedes Feld hat **genau einen Schreib-Ort** (Editor) und einen **Resolver**
   für Leser. `UserSettings.hourlyRate/vacationDays/dailyHours` sind nur noch
   selbst-gemeldete Anzeige-/Fallback-Werte, nie Berechnungseingang.
2. **Lohn leitet ab, erfindet nicht.** Jede Lohn-/Kostenzahl geht durch
   `LohnHerleitung`/einen geteilten Resolver, der `salaryKind` respektiert.
3. **Ableiten zur Lesezeit** statt denormalisierter Kopien; wo Snapshot bewusst
   (siteName, PayrollRecord), bleibt er — aber kein zweiter *Pflege*-Pfad.
4. Bewusste Trade-offs (siehe §6) bleiben, werden aber **als solche im Code
   markiert**, nicht stillschweigend dupliziert.

## 3. Fundament zuerst (ermöglicht fast alle Folgeschritte)

### F1 — Zentraler Vertrags-Resolver  *(Befund: contract-resolver-divergent)*
Heute zwei divergierende „aktiver Vertrag"-Implementierungen:
`PersonalProvider.contractForUser` (now(), Fallback *latest*) vs.
`WorkProvider._activeContractForCurrentUser` (date-Param, Fallback *null*).
→ Bei abgelaufenem Vertrag liefert Personal den alten Vertrag, Work fällt auf
`settings` — inkonsistente Sätze/Sollzeiten zwischen Modulen.

**Tun:** Pure Funktion `EmploymentContractResolver.activeOn(contracts, userId, date, {fallbackToLatest})` nach `lib/core/` extrahieren (offline testbar). Beide
Provider darüber bedienen. Bewusst entscheiden + dokumentieren, ob Personal bei
abgelaufenem Vertrag wirklich *latest* nutzen soll; in beiden Modulen identisch.
**Aufwand:** S · **Nutzen:** hoch (Basis für L1–L3, B-Konsistenz).

### F2 — Zentraler Lohn-/Stundensatz-/Soll-Resolver
`LohnHerleitung.grundlohnCents` ist bereits der kanonische, `salaryKind`-bewusste
Brutto-Ableiter — aber UI-Kennzahlen und Kostensichten umgehen ihn. Einen dünnen
Provider-Getter (z.B. in `PersonalProvider`) schaffen, der pro Mitarbeiter/Monat
Brutto/Personalkosten **einheitlich** über `LohnHerleitung` + F1-Resolver liefert,
und Soll/Ist über `computeZeitkonto`. Alle Kennzahl-Leser ziehen daraus.
**Aufwand:** S–M · **Nutzen:** hoch (Basis für L1, B6, C4).

## 4. Block L — Lohn als reiner Konsument (Kernanliegen B)

| ID | Befund | Maßnahme | Aufw. | Nutzen |
|----|--------|----------|-------|--------|
| **L1** | drei-lohnkosten-pfade / parallele-lohnschaetzung-totalwage | `WorkProvider.totalWageThisMonth` und `personal_screen` `_costByEmployee/_costBySite` auf den F2-Resolver umstellen (respektiert Festgehalt vs. Stundenlohn). Wo ein freigegebener `PayrollRecord` existiert, dessen `grossCents/employerTotalCents` bevorzugen; Stunden×Satz nur als gekennzeichnete Schätzung. **Festgehalt-Lücke schließen:** bei `salaryKind==monthly` `monthlyGrossCents` nutzen statt still 0/hourlyRate. | M | hoch |
| **L2** | gross-manuell-vs-istminutes | Brutto-Vorschlag im manuellen Lohn-Editor (`_grossFromHours`/`_hoursForUser`) aus `buildZeitkontoSnapshot.istMinutes` (inkl. anrechenbarer bezahlter Abwesenheit) speisen statt roher `workedHours`-Summe — gleiche Stunden-SSoT wie der Lohnlauf. Feld bleibt editierbar (Richtwert). | S | mittel |
| **L3** | festgehalt-doppelt | `EmploymentContract.monthlyGrossCents` = SSoT. In `buildDraftPayrollForMonth` den `profile.monthlyGrossCents`-Fallback nur greifen lassen, wenn **kein** aktiver Vertrag existiert; `personal_screen.dart:2253`-Prefill auf Vertrag-zuerst angleichen. `PayrollProfile.monthlyGrossCents` als reinen UI-Prefill kennzeichnen. | S | mittel |
| **L4** | tote-steuersatz-felder | `incomeTaxRateFor()` entfernen (kein Aufrufer); `incomeTaxRateByClass`/`minijobEmployerFlatRate` mit `@Deprecated(...)` markieren, von `required` auf Default umstellen. fromMap/toMap tolerant lassen (Altdocs nicht brechen). | S | niedrig (Wartung) |
| **L5** | lines-nicht-brutto-netto-wirksam | **Bewusst geplant (M-L-b), kein Bug.** Wenn gewünscht: `PayrollCalculator.calculate` um optionale Lines erweitern (steuer-/sv-pflichtige Anteile in die Bemessung, steuerfreie §3b net-neutral). Doppelzählung mit Grundlohn vermeiden. Solange nicht umgesetzt: als „bekannte Einschränkung" stehen lassen, Doc-Kommentare sind konsistent. | L | optional |

> **Kopplung beachten:** L1/L2/L3 berühren keine Callable-Payloads, aber jede
> Änderung an Compliance-Schwellen/Lohnlogik, die durch `functions/index.js`
> läuft, muss serverseitig gespiegelt werden (CLAUDE.md Kopplung #2/#6).

## 5. Block M — Mitarbeiter-Stammdaten entdoppeln (Kernanliegen A)

| ID | Befund | Maßnahme | Aufw. | Nutzen |
|----|--------|----------|-------|--------|
| **M1** | urlaub-vierfach | **Jahresurlaub auf `SollzeitProfile.urlaubstageJahr` konsolidieren.** `settings_screen.dart:788` und `home_screen.dart:949/2987` von `settings.vacationDays` auf `PersonalProvider.effektiveUrlaubstage(userId)` umstellen. Vertrags-Seed (`team_management_screen.dart:2840`, `team_provider.dart:1839`) nicht mehr aus `settings.vacationDays`, sondern leer/nullable (gesetzl. Minimum greift). Default-Divergenz angleichen (20 statt 30). Migration `migriereUrlaubstageInSollzeit` für Bestand fahren, danach `UserSettings.vacationDays` entfernen. | M | hoch (rechtlich relevant) |
| **M2** | standort-quali-doppelt | `EmployeeQualification` (HR, mit `gueltigBis`) zur **Gültigkeitsquelle** für die Schichtverteilung machen: gültige Quali-IDs zum Schichtdatum als Eingabe-Parameter in `ShiftAutoAssigner`/`ComplianceService` injizieren (analog `approvedAbsences`), gesammelt vom `ScheduleProvider`. Minimal-Variante: Konsistenzwarnung im Team-Editor gegen abgelaufene/fehlende Quali. | M | mittel–hoch |
| **M3** | lohn-stundensatz-doppelt | **Kein SSoT-Bruch im Lohnpfad** (Vertrag ist dort bereits führend). Nur Anzeige härten: `month_report_screen`, `pdf_service`, `home_*` über denselben Vertrag-zuerst-Fallback-Helfer (`_hourlyRateOn`-Muster) leiten, damit Anzeige & Lohnlauf konsistent. `settings.hourlyRate` als Selbstpflege-Fallback dokumentieren. | S | niedrig |
| **M4** | rolle-permissions-invite / name-invite-kopie | Beim Annehmen der Einladung (`ensureProfileForSignedInUser`) zusätzlich `isActive:false` auf das Invite-Doc setzen → verbrauchte Invite kann nicht latent re-provisionieren. Struktur belassen (im Local-Modus ist Invite die Stammquelle, via `_syncInviteForMember` konsistent). | S | niedrig (defensiv) |
| **M5** | Zwei Edit-Oberflächen für einen Mitarbeiter | **Konzeptionell:** Ownership festschreiben — Team-Editor = Identität/Vertrag/Standort, Personal-Editor = HR-Stammakte/Lohn. Doppelt editierbare Felder (Urlaub, Satz) je nur an *einem* Ort schreibbar machen (anderswo read-only mit Quellenhinweis, wie es bei Kinder/childrenCount schon vorbildlich gelöst ist). Optional späterer Schritt: gemeinsamer „Mitarbeiter"-Editor mit Tabs. | M–L | hoch (UX/Konsistenz) |

> **Kopplung beachten:** M2 berührt `ComplianceService` → Spiegelung in
> `functions/index.js` zwingend (Kopplung #2), sonst umgeht der direkte
> Write-Pfad die Quali-Prüfung. M1 berührt mehrere Models → 6-Stellen-Regel
> (Kopplung #1) beim Entfernen von `vacationDays`.

## 6. Block Z — Zeitwirtschaft konsolidieren

| ID | Befund | Maßnahme | Aufw. | Nutzen |
|----|--------|----------|-------|--------|
| **Z1** ✅ | zeitausgleich-hours-ohne-saldo-abzug | **ERLEDIGT (28.06.2026).** `timeOff` bleibt bewusst in der Ist-Anrechnung (hält `istMinutes`/Lohn-Grundlage stabil), aber `buildZeitkontoSnapshot` zieht über die neue pure Funktion `zeitausgleichSaldoMinutes` exakt den timeOff-Anteil der Anrechnung vom Saldo ab → Saldo sinkt jetzt korrekt um das abgefeierte Tagessoll. 3 Unit-Tests ergänzt, alle 1060 Tests grün, analyze sauber. Dateien: [zeitkonto_snapshot_builder.dart](lib/core/zeitkonto_snapshot_builder.dart), [zeitkonto_snapshot_test.dart](test/zeitkonto_snapshot_test.dart). | S | hoch |
| **Z2** | doppelter-stempel-mechanismus / halbseitige-clockentry-verknuepfung | **Laufende AllTec-Migration (M7b) abschließen:** `home_screen_tabs` auf `ZeitwirtschaftProvider`-Stempelpfad umleiten, alten `WorkProvider.clockIn/Out` + `_clockInKey`-State entfernen oder zum Delegaten machen. Schichtdeckungs-/Überstunden-Split-Logik in den ClockEntry-Pfad übernehmen, damit keine Validierung verloren geht. `ClockEntry.workEntryId` nach Post zurückschreiben (Poster gibt Id zurück). Doppel-Session ausschließen. | M–L | hoch |
| **Z3** | redundante-org-monatszeit-lader | `loadOrgWorkEntriesForMonth` in Personal- & ZeitwirtschaftProvider zusammenführen: gemeinsamer Helfer/Mixin um die zentrale `FirestoreService.getOrgWorkEntriesForMonth`-Query, Fehlerverhalten auf CLAUDE.md-Muster angleichen (hybrid→lokal, cloud-only→rethrow; Zeitwirtschaft schluckt aktuell Fehler). **Nicht** `WorkProvider._entries` nutzen (user-skopiert, falscher Scope). | S | niedrig |
| **Z4** | vier-soll-quellen-statistik | `StatisticsScreen` Soll nicht mehr `workingDays × settings.dailyHours`, sondern aus `computeZeitkonto` (SollzeitProfile) über einen Provider-Getter (Soll/Ist/Saldo). Fehlt das Sollprofil: „kein Soll hinterlegt" statt still `settings.dailyHours`. Mittelfristig `WorkProvider.overtimeThisMonth` ebenfalls darauf. | S–M | mittel |
| **Z5** | soll-ist-zwei-rechenpfade | **Kein Rechner-Refactor** (Schichtung `computeZeitkonto` + `buildZeitkontoSnapshot` ist gewollt). UX-Inkonsistenz beheben: das `_ZeitkontoCard` im Lohnformular zeigt anderes Ist als der erzeugte Lohnentwurf → auf `buildZeitkontoSnapshot`(mit Abwesenheit) umstellen oder beide Werte klar labeln („Ist gearbeitet" vs. „Ist abgerechnet inkl. Abwesenheit"). | S | mittel |

## 7. Block Q — Querschnitt

| ID | Befund | Maßnahme | Aufw. | Nutzen |
|----|--------|----------|-------|--------|
| **Q1** | costtype-needle-name-matching | Auto-Buchung Lohn/Ware/Umsatz → Kostenart koppelt per `name.contains(needle)` und **überspringt still** (nur `AppLogger.warning`), wenn kein Namenstreffer → Finanzjournal lautlos unvollständig. Stabiles Rollen-Feld (`CostTypeRole{personnel,goods,revenue}`) ODER Default-Kostenart-IDs in `OrgSettings` einführen; bei fehlender Zuordnung **sichtbare** Warnung im UI; Nachbuchungs-Pfad für `isFinalized && journalEntryId==null`. | M | mittel |
| **Q2** | abwesenheiten-dreifach-stream | `absenceRequests` wird 3× live gestreamt (Schedule ×2, Personal ×1). PersonalProvider die org-weite Sicht aus einer gemeinsamen Quelle beziehen (sauber: dedizierter `AbsenceProvider`/Repository in der main.dart-Kette); in Schedule den range-Stream aus dem Voll-Stream in-memory ableiten → ein Listener weniger (spart bezahlte Reads, Spark-Tier). | M | niedrig–mittel |
| **Q3** | summary-cards-v1-v2-dup | Kennzahl-/Format-Logik der Dashboard-Karten (`_SummaryCards` V1 ↔ `_SummaryCardsV2`) als geteilte `List<SummaryStat>`-Struktur nach `lib/widgets/`/`lib/ui/` heben; V1/V2 bauen nur noch ihre Karten-Hülle. | S | niedrig |

## 8. Bewusst NICHT ändern (verifizierte, dokumentierte Trade-offs)

Die Analyse hat 7 „Befunde" widerlegt — sie sind **gewollt** und sollten so
bleiben (ggf. nur Kommentar/Hinweis ergänzen):

- **Kinderzahl** `EmployeeProfile.childrenCount` ↔ `EmployeeChild`: vorbildliches
  Vorrang-Muster, Feld read-only sobald Kinder gepflegt. Mustervorlage für M5.
- **Eintrittsdatum** `hireDate` ↔ `Contract.validFrom`: fachlich verschieden
  (einmaliger Eintritt vs. versionierte Verträge). Dürfen abweichen.
- **Bundesland** `PayrollProfile.federalState` ↔ `SiteDefinition.federalState`:
  bewusster Override-mit-Fallback (Wohnsitz darf vom Standort abweichen).
- **§3b-Lage manuell** (statt aus Mantelzeit): geplant M-Z2, Mantelzeit-Lage
  noch offene Leitentscheidung.
- **Saldo/Überstunden fließt nicht in Grundlohn**: korrekt — Auszahlung läuft
  über separate `PayLineKind.einmalzahlung` (§39b), Grundlohn-Einrechnung wäre
  Doppelzählung.
- **Standortname denormalisiert** (`EmployeeSiteAssignment.siteName`): bewusster
  Snapshot, zur Anzeigezeit über `siteNameById` aufgelöst.
- **`totalWageThisMonth` als Brutto-Schätzung**: legitime, klar gelabelte MA-
  Selbstschätzung — nur die Festgehalt-Lücke (L1) ist real.

## 9. Empfohlene Reihenfolge

1. ~~**Quick Win zuerst:** `Z1` (Zeitausgleich-Saldo)~~ ✅ **erledigt 28.06.2026.**
2. **Fundament:** `F1` (Vertrags-Resolver) → `F2` (Lohn-/Soll-Resolver). ← nächster Schritt
3. **Konsistenz-Welle (baut auf F1/F2):** `L1`, `L2`, `L3`, `Z4`, `Z5`.
4. **Entdopplung Stammdaten:** `M1` (Urlaub + Migration), `M2` (Quali),
   `M5` (Ownership/Read-only-Felder).
5. **Aufräumen:** `L4`, `Z3`, `Q2`, `Q3`, `M3`, `M4`.
6. **Größere Brocken nach Bedarf:** `Z2` (Stempel-Migration M7b), `Q1`
   (Kostenart-Kopplung), `L5` (M-L-b Lines-Verrechnung).

## 10. Test- & Sicherheitsnetz

- Vor jedem Refactor Characterization-Tests für die betroffene Berechnung
  (pures Core ist offline testbar: Resolver, Zeitkonto, Lohn).
- Quality Gates pro Schritt: `flutter analyze` + `flutter test` (CLAUDE.md).
- Bei Model-Feld-Entfernung (`vacationDays`) die 6-Stellen-Regel (Kopplung #1)
  und tolerantes `fromMap` (Altdocs) beachten.
- Bei Compliance-/Quali-Regeländerungen (`M2`) `compliance_service.dart` **und**
  `functions/index.js` synchron halten (Kopplung #2/#6).
- `firestore.indexes.json` ergänzen, falls neue `where`+`orderBy`-Queries
  entstehen (z.B. zentrale org-weite Reads).
