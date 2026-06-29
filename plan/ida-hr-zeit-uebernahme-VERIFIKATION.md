# Verifikations-Report — plan/ida-hr-zeit-uebernahme.md

> Adversariale Prüfung jeder konkreten Plan-Behauptung gegen den echten Quellcode von
> **ida** (PHP/MySQL + Vue), **ida_app** (Flutter), **idadwh** (Node/DATEV) und **WorkTime** selbst.
> 8 parallele Prüfer, je Aussage Verdikt + Datei:Zeile-Beleg. Erstellt 2026-06-22.
> Geprüfte Aussagen gesamt: **141**, davon problematisch: **28**.

## 1. Gesamturteil

Gesamt-Trefferquote ca. 85% ueber alle 8 Bereiche (Einzelschaetzungen: Schema 70%, PHP-Logik 80%, Vue-HR 90%, Vue-Zeit 90%, ida_app-Flutter 88%, idadwh-DATEV 92%, ida_app-UI 88%, WorkTime-IST 90%). Der Plan ist stark beim Erkennen realer Strukturen: fast alle Architektur-Konzepte (Zwei-Ebenen-Zeitmodell, 7-Status-Monatsabschluss, gueltig_ab-Historisierung, DATEV-Pipeline), die meisten Funktions-/Klassen-/Interface-/Komponenten-Namen und die WorkTime-IST-Analyse sind exakt belegt. Schwach ist er bei (a) drei konkreten ida-Tabellennamen (hr_tagesabschluss, ma_quali, 'keine versionierten Schemata' alle falsch), (b) zwei Quellen-Zuordnungen (U1/U2/InsO liegen in crm_krankenkassen, nicht hr_lohnnebenkosten; hr_kinder ist reine Verknuepfungstabelle ohne Stammfelder), (c) einer halluzinierten Funktion (hr_kpi_setSicknessRate -> real ...PerPerson), (d) einer ueberhoehten Zahl (~250 statt ~148 Funktionen) und (e) der Darstellung des werktagsgenauen/teilzeitskalierten Urlaubs + 31.3.-Verfall als ida-Bestand, obwohl dies faktisch Plan-Neuerungen sind (in §5.1/§5.2 zwar als 'Review-Korrektur' markiert, in der §3-Gap-Tabelle aber als ida-Quelle attribuiert).

## 2. Korrekturen (mit Code-Beleg)

### Schwere HOCH

- **ida-Schema (§3 Gap-Tabelle Z.177/180)**
  - Plan: 'AG-Umlagen U1/U2/InsO | hr_lohnnebenkosten' (Z.177) und 'AG-Lohnnebenkosten-Saetze + BG/UV | hr_lohnnebenkosten' (Z.180)
  - Problem: Falsche Quellen-Zuordnung fuer U1/U2/InsO; hr_lohnnebenkosten enthaelt KEINE U1/U2/InsO-Spalten.
  - Korrekt: hr_lohnnebenkosten traegt nur AG-Anteile KV/PV/AV/RV/UV (inkl. BG via unfallversicherungstraeger). U1/U2/InsO stammen aus crm_krankenkassen.umlage_1 (Lohnfortzahlung/U1), umlage_2 (Mutterschaftsgeld/U2), umlage_3 (Insolvenzgeld/InsO) - kassenindividuell.
  - Beleg: `1_ida_master.sql:10031-10033 (crm_krankenkassen.umlage_1/2/3); CREATE TABLE `hr_lohnnebenkosten` (krankenvers.-/pflege-/arbeitslosen-/rentenvers.beitrag, unfallversicherungstraeger/-beitrag, gueltig_ab)`

### Schwere MITTEL

- **ida-Schema (§3 Gap-Tabelle Z.148)**
  - Plan: 'Tagesabschluss (Tag sperren) | hr_tagesabschluss'
  - Problem: Tabellenname falsch/halluziniert; Tabelle hr_tagesabschluss existiert nicht (0 Treffer).
  - Korrekt: Tabelle heisst hr_zeit_tagesabschluesse; Schluessel tag ist YYYYMMDD-int (Spalten-COMMENT), kein Unix-Timestamp.
  - Beleg: `__deployment/db/sql/1_ida_master.sql: CREATE TABLE `hr_zeit_tagesabschluesse` (tag int(11) COMMENT 'YYYYMMDD', person_created, timestamp_created, PK tag)`
- **ida-Schema (§3 Gap-Tabelle Z.185)**
  - Plan: 'Qualifikationen (MA-Zuordnung) | ma_quali'
  - Problem: Tabellenname falsch; ma_quali ist nur der PK-Spaltenstamm (ma_quali_id), keine Tabelle.
  - Korrekt: Tabelle heisst hr_ma_qualifikationen (ma_quali_id PK); Quali-Stammdaten in hr_qualifikationen / hr_qualifikationsarten.
  - Beleg: `1_ida_master.sql: CREATE TABLE `hr_ma_qualifikationen` (ma_quali_id mediumint PK, personen_id, qualifikation_id, erworben_am/gueltig_bis, erwerb, dokument_id)`
- **ida-Schema (§3 Z.184 / §4.4)**
  - Plan: 'Kinder (Freibetraege) | hr_kinder | childrenCount:int | Kind-Sub-Entitaet' + §4.4 EmployeeChild mit name/vorname/geschlecht/geburtstag
  - Problem: hr_kinder hat KEINE Kind-Stammdatenfelder; das skizzierte EmployeeChild-Schema bildet ida nicht 1:1 ab.
  - Korrekt: hr_kinder ist reine Verknuepfungstabelle (nur personen_id_elternteil, personen_id_kind, steuer_id_kind). Name/Geburtstag/Geschlecht liegen am verknuepften Personen-Satz, nicht in hr_kinder; EmployeeChild ist Neukonstruktion.
  - Beleg: `1_ida_master.sql: CREATE TABLE `hr_kinder` (personen_id_elternteil, personen_id_kind, steuer_id_kind, PK beide personen_id)`
- **ida-PHP-Logik (§3 Gap-Tabelle Z.154)**
  - Plan: 'Urlaubsanspruch BUrlG werktagsgenau + Teilzeit | hrfunc_getUrlaubsanspruchInRange' (Werktagsbasis, Teilzeit-Umrechnung, §5(2)-Rundung als ida-Quelle)
  - Problem: Die §3-Tabelle attribuiert werktagsgenaue + teilzeitskalierte Berechnung der ida-Funktion. ida rechnet aber anteilig ueber KALENDERtage und ohne Teilzeit-Skalierung; das ist faktisch Plan-Neuerung (in §5.1 als 'Review-Korrektur' markiert, in §3 als ida-Quelle).
  - Korrekt: hrfunc_getUrlaubsanspruchInRange macht nur anteilige Zwoelftelung ueber gueltig-ab-Perioden auf Kalendertagbasis ($urlaub/$days_in_range)*$days_in_period; KEINE Werktags-/Teilzeit-Umrechnung. Werktagsgenau+Teilzeit ist Plan-NEU-Design.
  - Beleg: `_functions/HR_functions.inc.php:228-263 (diff->days, days_in_range Kalendertage)`
- **ida-PHP-Logik (§3 Gap-Tabelle Z.155)**
  - Plan: 'Resturlaub-Saldo + 31.3.-Verfall | zeitfunc_getResturlaubByTimestamp' (Vortrag+Anspruch+Anpassung-genommen-geplant, Uebertragungsfrist §7(3), Hinweisobliegenheit als ida-Quelle)
  - Problem: ida-Funktion enthaelt KEINEN 31.3.-Verfall, KEINE Hinweisobliegenheit und KEINE 'geplant'-Subtraktion; nur genommener Urlaub wird abgezogen. Diese sind Plan-Neuerungen, in §3 aber der ida-Quelle zugeschrieben.
  - Korrekt: Formel = Vortrag + Anspruch + Anpassung - genommen (Z.872). 31.3.-Verfall/Hinweisobliegenheit/geplant-Trennung sind WorkTime-Eigenleistung.
  - Beleg: `_functions/ZEITEN_functions.inc.php:818-872 (return $resturlaub_vorjahr + $urlaubsanspruch - $urlaub + $urlaub_anpassungen)`

### Schwere NIEDRIG

- **ida-PHP-Logik (§3 Gap-Tabelle Z.165)**
  - Plan: 'Krankenstand-KPI | hr_kpi_setSicknessRate'
  - Problem: Funktionsname halluziniert; hr_kpi_setSicknessRate existiert nicht (0 Treffer).
  - Korrekt: Korrekt: hr_kpi_setSicknessRatePerPerson (KPI pro Person) bzw. hrfunc_setSicknessRatePerPerson (Orchestrierung).
  - Beleg: `_functions/HR_functions.inc.php:1041 function hr_kpi_setSicknessRatePerPerson(...); HR_functions.inc.php:774 function hrfunc_setSicknessRatePerPerson(...)`
- **ida-PHP-Logik (§2 / Quellen-Ueberblick)**
  - Plan: ZEITEN_functions.inc.php hat ~250 Funktionen
  - Problem: Funktionszahl ueberhoeht.
  - Korrekt: Tatsaechlich ca. 148 Funktionen in der Datei.
  - Beleg: `grep -c '^\s*function ' _functions/ZEITEN_functions.inc.php => 148`
- **ida-PHP-Logik (Auftrag Rechenregeln / falls im Plan als Standard dargestellt)**
  - Plan: Ueberstunden-Aufschlag-Split 25%/50% als ida-Rechenregel
  - Problem: Der Split ist kundenspezifisch (Mandant 'Funke') hinter Feature-Flag, keine allgemeine ida-Regel und fuer Einzelhandel/WorkTime nicht repraesentativ.
  - Korrekt: ueber25/ueber50 existieren nur hinter $alternatives_stundenzettel_csv (Kommentar: 'ausschliesslich bei Funke genutzt'). Nicht als Standard-Rechenregel darstellen.
  - Beleg: `_functions/ZEITEN_functions.inc.php:6005-6008, 7739-7740`
- **idadwh-DATEV (§5.11 Z.584/758/859)**
  - Plan: Tagesanteils-Verteilung rundungserhaltend via 'Groesster-Rest-Verfahren' (Hare-Niemeyer)
  - Problem: 'Groesster-Rest-Verfahren' ist eine Plan-Eigenbezeichnung, kein Code-Begriff; das Verfahren ist nicht exakt der klassische Hare-Niemeyer-Algorithmus.
  - Korrekt: Im idadwh heisst es sumPreservingRounding und verteilt die Rundungsdifferenz via sortRoundingErrors + Korrektureinheiten (funktional ein Restausgleich, aber anders benannt/implementiert). Sigma-exakt-Ziel und Division-durch-0-Schutz sind real.
  - Beleg: `src/utils/numberHelper/rounder.ts:76-124 sumPreservingRounding + sortRoundingErrors:127ff`
- **ida-Vue-Zeit (§3 Z.149)**
  - Plan: 'Abrechnungssperre (abgerechnetBis) pro MA | ZeitAbrechnungsstatus' als Vue-Quelle
  - Problem: Eine Datei/Konstante 'ZeitAbrechnungsstatus' ist im Vue-zeit-Ordner nicht auffindbar; belegt ist nur state.hr.abgerechnetBis. (Im Flutter ida_app existiert ZeitAbrechnungsstatus dagegen sehr wohl.)
  - Korrekt: Vue-Quelle ist state.hr.abgerechnetBis (ZeitCheckList.vue); der Klassenname ZeitAbrechnungsstatus stammt aus ida_app (Flutter), nicht aus dem Vue-zeit-Modul.
  - Beleg: `ZeitCheckList.vue:1097/1209 (mapState abgerechnetBis, fetchHrAbgerechnetBis); ida_app lib/modules/zeit/models/zeit_abrechnungsstatus.dart:9`
- **ida-Vue-HR / Auftrag (IHrLohn-Interpretation)**
  - Plan: IHrLohn als Lohn-/Gehaltsstammdaten-Interface (implizit angenommen)
  - Problem: IHrLohn.ts enthaelt nur Auszahlungs-Payloads, KEIN Gehalts-Stammdaten-Interface.
  - Korrekt: Lohn-/Gehaltsstammdaten (steuerklasse, entgeltgruppe, gehaltstyp, gueltig_ab) sind in ida untypisiert (IHrMitarbeiter.gehalt: any) und nur in HrMitarbeiterLohnStammdatenActionCard.vue greifbar; IHrLohn.ts = nur IHrLohnZahlungenApiParams/PostParams.
  - Beleg: `interfaces/IHrLohn.ts:1-18; IHrMitarbeiter.ts:99 'gehalt: any'; HrMitarbeiterLohnStammdatenActionCard.vue:98/106/147`
- **ida-Vue-HR / ida_app (Urlaubsfeld-Herkunft, §4.1)**
  - Plan: urlaubstageJahr/zusatzurlaubstage als aus ida-Sollzeit abgeleitete zentrale Urlaubsquelle (SollzeitProfile)
  - Problem: In ida liegen urlaub/zusatzurlaub NICHT am Sollzeit-Interface, sondern am Schicht-Interface IHrSchicht; die ida-Herkunft wird falsch (Sollzeit) angegeben.
  - Korrekt: ida-Quelle ist IHrSchicht.urlaub/zusatzurlaub (Schicht = Sollzeit-Vorlage in ida); IHrSollzeit hat KEIN urlaub-Feld. Plan-Abstraktion nach SollzeitProfile ist ok, die Herkunftsangabe nicht.
  - Beleg: `schichten/interfaces/IHrSchicht.ts:18-19 (urlaub, zusatzurlaub); IHrSollzeit.ts:13-22 (kein urlaub)`
- **WorkTime-IST (§3 Leitentscheidung 4 / §5.1)**
  - Plan: 'drei Urlaubsquellen' (annualVacationDays, vacationDays, SollzeitProfile.urlaubstageJahr) - Tabellenformulierung lesbar als IST-Stand
  - Problem: Heute existieren nur ZWEI Urlaubsquellen; die dritte (urlaubstageJahr/SollzeitProfile) existiert im Code nicht und ist geplante Neuerung.
  - Korrekt: IST: genau zwei Quellen - EmployeeProfile.annualVacationDays (int?) und EmploymentContract.vacationDays (Default 30). SollzeitProfile/urlaubstageJahr: 0 Treffer in lib/. (Plan stellt es in §5.1 korrekt als NEU dar, aber Tabelle kann missverstanden werden.)
  - Beleg: `lib/models/employee_profile.dart:303; lib/models/employment_contract.dart:65; grep 'urlaubstageJahr|SollzeitProfile' lib/ = 0`
- **WorkTime-IST (§2 Quellen-Ueberblick Z.124)**
  - Plan: 'EmployeeProfile (34 Felder)'
  - Problem: Feldzahl ist eine grobe Schaetzung, nicht exakt belegbar.
  - Korrekt: Je nach Zaehlweise ~31 fachliche Felder bzw. ~37 Konstruktor-Parameter (inkl. id/orgId/userId/3 Meta), nicht exakt 34.
  - Beleg: `lib/models/employee_profile.dart Konstruktor Z.205-257`
- **ida-Schema (§2 Architektur 'unix-ts')**
  - Plan: Zeiten pauschal als Unix-Timestamps (Sekunden)
  - Problem: Pauschale stimmt nicht fuer alle Zeitfelder.
  - Korrekt: Punkt-in-Zeit-Felder (kommen/gehen/start/ende/gueltig_ab) sind Unix-Sekunden; Perioden-/Tagesschluessel sind YYYYMM (hr_zeitkonto/hr_lohnstunden.jahrmonat) bzw. YYYYMMDD (hr_zeit_tagesabschluesse.tag) Ints.
  - Beleg: `1_ida_master.sql: hr_zeitkonto.jahrmonat int(10) YYYYMM, hr_zeit_tagesabschluesse.tag COMMENT 'YYYYMMDD', hr_mantelzeiten.kommen/gehen int unsigned`
- **ida_app-Flutter / ida_app-UI (Font-Family)**
  - Plan: Schrift 'Product Sans'
  - Problem: Family-String falsch geschrieben (mit Leerzeichen).
  - Korrekt: Family heisst 'ProductSans' (ein Wort) - relevant nur bei 1:1 Asset-Uebernahme; WorkTime nutzt ohnehin NotoSans.
  - Beleg: `ida_app lib/constants/font_family.dart:4 static String productSans = 'ProductSans'`
- **ida_app-Flutter (§1/§2 Architektur-Leitplanken)**
  - Plan: ida_app-Tech 'kein Provider/Firestore' (pauschal)
  - Problem: Pauschalaussage ungenau.
  - Korrekt: 'kein Firestore' korrekt (cloud_firestore: 0 Treffer); aber provider:^6.1.1 IST in pubspec deklariert (im HR/Zeit-Modulcode ungenutzt, MobX) und firebase_core/firebase_messaging (Push) sind praesent.
  - Beleg: `ida_app pubspec.yaml (mobx, dio, sembast, provider:^6.1.1, firebase_core ^3.12.1, firebase_messaging); 0 cloud_firestore`
- **ida_app-UI (Bereichsvorgabe VCard)**
  - Plan: VCard als 'VCard-Tiles' (UI-Baustein/Widget)
  - Problem: Begriffsverwechslung; VCard ist kein Tile-Widget.
  - Korrekt: VCard ist in ida_app ein Daten-/Referenzmodell-Muster (BaseEntityReferenzVCard, *_vcard.dart, ParsableEntityVCardFactory); kein 'VCardTile'-Widget (0 Treffer).
  - Beleg: `ida_app lib/models/entity/base_entity_referenz_vcard.dart:8; keine Treffer 'class.*VCardTile'`

## 3. Lücken / Überzeichnungen (vom Plan übersehen oder verzerrt)

- U1/U2/InsO-Quelle: Der Plan verortet sie in hr_lohnnebenkosten - die DZeLt-/Krankenkassen-individuellen Umlagesaetze liegen real in crm_krankenkassen.umlage_1/2/3. Das ist die hochschwerste Quellen-Verzerrung und beeinflusst die geplante AG-Umlagen-Implementierung.
- hr_sollzeiten ist im ida deutlich umfangreicher als der Plan (als 'optional/E3 spaeter') einstuft: volle Rahmen-/Kernzeit pro Wochentag, Pausenfenster, pause_karenz/kernzeit_karenz, az_runden(_auf/_start/_ende), az_maximum/kappung_ueberstunden, fakultative_ueberstunden(_typ/_zeitraum), gleitzeit, urlaub_als_stunden - alle bereits vorhanden.
- hr_gehalt kodiert Gehalt-vs-Stundenlohn bereits via fixum_bezug (0=Jahres/1=Monats/2=Stundenlohn) + Felder stundenlohn UND gehalt_fixum + Lookup hr_gehaltstyp; der Plan fuehrt salaryKind als Neuerung ein, ohne diese bestehende Vorlage zu nennen.
- Es GIBT versionierte CREATE-TABLE-Schemata (SQL-Dumps in __deployment/db/sql/, stage/, rehau/) plus ein zeitstempelbasiertes Migrationsverzeichnis __development/db/migrations/ mit 58 datierten .sql-Dateien - die beste Beleg-Quelle fuer Spaltennamen/Typen; eine Annahme 'keine versionierten Schemata' waere falsch.
- Die DZeLt-Engine ist maechtiger als der Plan andeutet: ~20 Bedingungsfelder (soll_stunden_weniger/mehr, ist_stunden, bilanz_stunden, stundenkonto, ueberstunden_zuschlagsgruppe, kilometer, datum_gueltig...) + frei evaluierte wert_formel (Eval.evalFormularSafe). Der statische Plan-Ersatz bildet nur die abwesenheit_gleich-Achse ab - bewusste, aber im Plan unterschaetzte Vereinfachung. Zudem: die Plan-Beispielwerte (508/U etc.) stammen aus dem Legacy-stamer-Mapping (ZeitUndLohndatenExport.ts:34 'not using the modern DZeLt'), nicht aus DZeLt-Daten.
- ida-IST-Werte, die der Plan als bereits implementiert uebersieht: PayrollProfile.monthlyGrossCents liefert schon eine Brutto-Vorbefuellung; healthInsuranceSurchargePercent (MA-individueller KV-Zusatz-Override) und careChildlessSurchargeRate (PV-Kinderlosenzuschlag) sind in WorkTime bereits implementiert - der Plan listet sie teils als Luecke.
- ida hat zahlreiche im Plan nicht erwaehnte HR-/Zeit-Dimensionen (Provision, Buchungskonten, Untergebene, Zuordnungsauslastung, Faktura vs Abrechnung der Istzeit, zusaetzliche Tages-KPIs kernzeit-/rahmenzeit-/offsite_verstoss) - bewusst out-of-scope, aber der ida-Umfang ist groesser als der Plan-Scope.
- ZeitCheckList zeigt nur 6h/10h-ArbZG-Verstoesse, KEINE eigene 11h/660min-Ruhezeit-Spalte; die 660min-Ruhezeit-Aggregation ist WorkTime-Eigenleistung (compliance_service), nicht aus der ida-Ansicht uebernommen.
- 'ongoing' ist in ida (sowohl Vue IZeit.ts:24 als auch ida_app zeit_mantelzeiten.dart:33) ein echtes persistiertes Feld; die WorkTime-Entscheidung (Getter gehen==null) ist eine bewusste Abweichung, kein ida-Bestand - der Plan formuliert es korrekt als Designentscheidung, sollte aber nicht suggerieren, ida habe kein ongoing-Feld.

## 4. Als KORREKT bestätigt (verlässlich)

- Zwei-Ebenen-Zeitmodell (Mantelzeit=Anwesenheit kommen/gehen vs. Istzeit=zeitwirtschaft/Kostentraeger) ist real (ida interfaces/IZeit.ts, IZeitIstzeit.ts; ida_app zeit_mantelzeiten.dart, zeit_istzeit.dart).
- Monatsabschluss-Statusmaschine hat exakt 7 Status in zeitMonatabschlussConstants.ts (1..7) in der vom Plan-Enum genannten Reihenfolge, sequenziell (Status 5 'nicht abgeschlossener Vormonat' blockiert).
- Mehrheit der ida-Tabellennamen ist belegt: hr_mantelzeiten, hr_zeitwirtschaft, hr_gehalt, hr_gehalt_zulagen, hr_ausbildung, hr_vertreter, hr_sollzeiten, hr_zeitkonto, hr_lohnnebenkosten, hr_urlaubsanpassungen, hr_mitarbeiter, hr_stammdaten, hr_lohnstunden (volle CREATE-TABLE in __deployment/db/sql/1_ida_master.sql).
- Funktionsnamen hrfunc_getUrlaubsanspruchInRange, zeitfunc_getResturlaubByTimestamp, zeitfunc_getMantelzeitInfoByDay, hrcon_getMitarbeiter existieren exakt (HR_functions.inc.php, ZEITEN_functions.inc.php, HRMitarbeiterController.php mit 114 hrcon_-Endpunkten).
- Pflichtpausen 30@6h / 45@9h exakt (constants.php HR_PFLICHTPAUSE_30_MIN/45_MIN); Stundenkonto = Ist-Soll fortlaufend kumuliert (ZEITEN_functions.inc.php:1080/1340).
- DATEV-Mapping-Beispiele exakt belegt: Urlaub->508/U, Krank->111/K, Feiertag->29/F, Zeitausgleich->20/ZA, Berufsschule->403/BS, Auszahlung->1100 (ZeitUndLohndatenExport.ts:162-198).
- idadwh-Bausteine real: DZeLt (DatevZeitenexportLogiktabelle.ts), A351K, LODAS (Stamm+Bewegung), HR-Payroll-REST-Rueckimport, LuG ASCII tages-/monatsweise mit .ini, Industrieminuten, Monatsaggregation je (personalnr,lohnart,ausfallschluessel,kostenstelle).
- Alle genannten ida-Vue-HR-Artefakte auffindbar (7 Interfaces, 14 Komponenten/Modals/Cards, 8 Selects, Recruiting, Schichten); gueltig_ab-Historisierung durchgaengig; Urlaubsanpassungs-Enum (1=ABZUG_ALLG/2=ABZUG_FRIST/3=SONDERURLAUB/4=ALLG) exakt.
- WorkTime-IST korrekt beschrieben: grossCents manuell, EmploymentContract nur hourlyRate ohne Lohntyp (kein salaryKind im lib/), childrenCount:int im EmployeeProfile, defaults2026==2025 (careRate 3,6% / healthAdditionalRate 2,5% via Default), _midijobBase reduziert KV/PV und RV/ALV identisch, nur overtimeThisMonth-Getter (kein Stundenkonto), AbsenceType=vacation/sickness/unavailable, HR/payroll-Rules admin-only.
- ida_app-Modelle/Features real: HrMitarbeiter, HrBaseMitarbeiter, HrVertreter, ZeitMantelzeiten, ZeitIstzeit, CalAbwesenheit, CmsUrlaubsantragForm; FlipFlop/Quick-Stempel, Live-Timer (Ticker), Terminal/Kiosk PIN/RFID/NFC+Auto-Logout, SHA1(PIN+Salt) client-seitig; CalTerminartConst (61 Werte).
- ida_app-UI: Seed-Rot #B7172F, AppBar/NavigationBar rot/weiss, Scaffold-BG #F0F0F0, useMaterial3:true mit nur teilweise ueberschriebenem ColorScheme, Bootstrap-Statusfarben, ExpansionTile-Konto-Tiles ZeitStundenkontoListTile/ZeitVacationStatusListTile mit +/-/=-Aufstellung.

## 5. Voll-Report

# Verifikations-Report: plan/ida-hr-zeit-uebernahme.md

Konsolidierung aus 8 adversarialen Pruefern gegen die Quell-Repos (ida-PHP/MySQL, ida-Vue, ida_app/Flutter, idadwh/DATEV) und WorkTime selbst.

## 1. Gesamturteil

Trefferquote ca. **85%** ueber alle Bereiche. Einzelschaetzungen: Schema 70%, PHP-Logik 80%, Vue-HR 90%, Vue-Zeit 90%, ida_app-Flutter 88%, idadwh-DATEV 92%, ida_app-UI 88%, WorkTime-IST 90%.

**Stark:** Architektur-Konzepte, Funktions-/Klassen-/Interface-/Komponenten-Namen und die WorkTime-IST-Analyse sind ueberwiegend exakt belegt. Keine breite Halluzination.

**Schwach:** Drei konkrete ida-Tabellennamen sind falsch, zwei Quellen-Zuordnungen verzerrt, eine Funktion halluziniert, eine Funktionszahl ueberhoeht, und werktagsgenauer/teilzeitskalierter Urlaub + 31.3.-Verfall werden in der §3-Gap-Tabelle faelschlich als ida-Bestand attribuiert (sind Plan-Neuerungen).

## 2. Korrekturen (mit Code-Beleg)

### Schwere HOCH
- **U1/U2/InsO-Quelle (§3 Z.177/180):** Plan: 'AG-Umlagen U1/U2/InsO | hr_lohnnebenkosten'. **Falsch** — hr_lohnnebenkosten enthaelt nur AG-Anteile KV/PV/AV/RV/UV (inkl. BG via unfallversicherungstraeger). U1/U2/InsO stammen aus `crm_krankenkassen.umlage_1` (Lohnfortzahlung), `umlage_2` (Mutterschaftsgeld), `umlage_3` (Insolvenzgeld) — kassenindividuell. Beleg: `1_ida_master.sql:10031-10033`.

### Schwere MITTEL
- **hr_tagesabschluss (§3 Z.148):** Tabelle existiert nicht (0 Treffer). Korrekt: **hr_zeit_tagesabschluesse**, Schluessel `tag` = YYYYMMDD-int. Beleg: `1_ida_master.sql` CREATE TABLE `hr_zeit_tagesabschluesse`.
- **ma_quali (§3 Z.185):** keine Tabelle, nur PK-Spaltenstamm `ma_quali_id`. Korrekt: **hr_ma_qualifikationen** (+ hr_qualifikationen/hr_qualifikationsarten). Beleg: `1_ida_master.sql`.
- **hr_kinder (§3 Z.184 / §4.4):** hr_kinder ist reine Verknuepfungstabelle (personen_id_elternteil, personen_id_kind, steuer_id_kind) ohne name/geburtstag/geschlecht. Das §4.4-EmployeeChild ist Neukonstruktion. Beleg: `1_ida_master.sql`.
- **Urlaub werktagsgenau+Teilzeit (§3 Z.154):** Tabelle attribuiert dies `hrfunc_getUrlaubsanspruchInRange` als ida-Quelle. Real rechnet ida anteilig ueber **Kalendertage**, ohne Teilzeit-Skalierung — Plan-Neuerung (in §5.1 als 'Review-Korrektur' markiert). Beleg: `HR_functions.inc.php:228-263`.
- **31.3.-Verfall/Hinweisobliegenheit/geplant (§3 Z.155):** in `zeitfunc_getResturlaubByTimestamp` NICHT vorhanden (Formel = Vortrag+Anspruch+Anpassung−genommen). Plan-Neuerung. Beleg: `ZEITEN_functions.inc.php:818-872`.

### Schwere NIEDRIG
- **hr_kpi_setSicknessRate (§3 Z.165):** halluziniert. Korrekt: `hr_kpi_setSicknessRatePerPerson` / `hrfunc_setSicknessRatePerPerson`. Beleg: `HR_functions.inc.php:1041/774`.
- **~250 Funktionen (§2):** real ~148. Beleg: `grep -c '^\\s*function ' ZEITEN_functions.inc.php` = 148.
- **25%/50%-Aufschlag-Split:** kundenspezifisch (Mandant 'Funke') hinter Feature-Flag `$alternatives_stundenzettel_csv`, keine allgemeine Regel. Beleg: `ZEITEN_functions.inc.php:6005-6008`.
- **'Groesster-Rest-Verfahren' (§5.11):** Plan-Eigenbezeichnung; Code = `sumPreservingRounding`+`sortRoundingErrors`, nicht exakt Hare-Niemeyer. Beleg: `rounder.ts:76-124`.
- **ZeitAbrechnungsstatus als Vue-Quelle (§3 Z.149):** im Vue-zeit-Ordner nicht auffindbar; belegt nur `state.hr.abgerechnetBis`. Der Klassenname existiert in ida_app (Flutter), nicht im Vue-Modul. Beleg: `ZeitCheckList.vue:1097/1209`, `ida_app .../zeit_abrechnungsstatus.dart`.
- **IHrLohn:** kein Gehalts-Stammdaten-Interface, nur Auszahlungs-Payloads; echte Felder in `IHrMitarbeiter.gehalt:any` + `HrMitarbeiterLohnStammdatenActionCard.vue`. Beleg: `IHrLohn.ts:1-18`.
- **Urlaubsfeld-Herkunft (§4.1):** urlaub/zusatzurlaub haengen in ida an `IHrSchicht`, nicht `IHrSollzeit`. Beleg: `IHrSchicht.ts:18-19`.
- **'drei Urlaubsquellen' (§3/§5.1):** heute nur ZWEI (annualVacationDays + vacationDays); urlaubstageJahr/SollzeitProfile = 0 Treffer in lib/. Beleg: `employee_profile.dart:303`, `employment_contract.dart:65`.
- **'EmployeeProfile (34 Felder)' (§2):** grobe Schaetzung, real ~31–37. Beleg: `employee_profile.dart:205-257`.
- **Unix-ts-Pauschale (§2):** Punkt-Zeiten = Unix-Sekunden, Perioden-/Tagesschluessel = YYYYMM/YYYYMMDD-Ints. Beleg: `1_ida_master.sql` (jahrmonat int, tag COMMENT 'YYYYMMDD').
- **'Product Sans':** Family heisst `ProductSans`. Beleg: `ida_app font_family.dart:4`.
- **'kein Provider/Firestore' (§1/§2):** 'kein Firestore' ok; aber provider:^6.1.1 + firebase_core/messaging sind in pubspec deklariert. Beleg: `ida_app pubspec.yaml`.
- **'VCard-Tiles':** VCard ist Datenmodell-Muster (BaseEntityReferenzVCard), kein Tile-Widget. Beleg: `ida_app base_entity_referenz_vcard.dart:8`.

## 3. Bestaetigt (verlaessliche Behauptungen)

- Zwei-Ebenen-Zeitmodell (Mantelzeit vs. Istzeit) real.
- 7-Status-Monatsabschluss exakt in `zeitMonatabschlussConstants.ts`, sequenziell.
- Mehrheit der ida-Tabellennamen belegt (hr_mantelzeiten, hr_zeitwirtschaft, hr_gehalt, hr_gehalt_zulagen, hr_ausbildung, hr_vertreter, hr_sollzeiten, hr_zeitkonto, hr_lohnnebenkosten, hr_urlaubsanpassungen, hr_mitarbeiter, hr_stammdaten, hr_lohnstunden).
- Kern-Funktionsnamen exakt (hrfunc_getUrlaubsanspruchInRange, zeitfunc_getResturlaubByTimestamp, zeitfunc_getMantelzeitInfoByDay, hrcon_getMitarbeiter; 114 hrcon_-Endpunkte).
- Pflichtpausen 30@6h/45@9h; Stundenkonto = Ist−Soll kumuliert.
- DATEV-Mapping-Beispiele exakt (508/U, 111/K, 29/F, 20/ZA, 403/BS, 1100).
- idadwh-Bausteine real (DZeLt, A351K, LODAS, HR-Payroll-Rueckimport, LuG ASCII tages-/monatsweise, .ini, Industrieminuten).
- Alle Vue-HR-Artefakte auffindbar; gueltig_ab-Historisierung durchgaengig; Urlaubsanpassungs-Enum exakt.
- WorkTime-IST korrekt (grossCents manuell, nur hourlyRate, childrenCount:int, defaults2026==2025, _midijobBase identisch KV/PV+RV/ALV, nur overtimeThisMonth, AbsenceType 3 Werte, Rules admin-only).
- ida_app-Modelle/Features + UI (Seed-Rot, useMaterial3, Konto-ExpansionTiles, Terminal/Kiosk SHA1+Salt client-seitig).

## 4. Luecken / Verzerrungen

- **hr_sollzeiten** ist viel umfangreicher als der Plan (Rahmen-/Kernzeit, Karenz, az_runden, Kappung, fakultative_ueberstunden, gleitzeit) — als 'E3 spaeter' unterschaetzt.
- **hr_gehalt** kodiert Gehalt-vs-Stundenlohn bereits (fixum_bezug + stundenlohn/gehalt_fixum + hr_gehaltstyp) — der Plan fuehrt salaryKind als Neuerung ein, ohne die Vorlage zu nennen.
- **Versionierte Schemata existieren** (SQL-Dumps + 58-Datei-Migrationsverzeichnis) — beste Beleg-Quelle.
- **DZeLt-Engine** ist maechtiger (~20 Bedingungen + wert_formel/Eval); Plan-Beispielwerte stammen aus dem Legacy-stamer-Mapping, nicht aus DZeLt.
- **Bereits implementiert in WorkTime** (vom Plan teils als Luecke gelistet): PayrollProfile.monthlyGrossCents (Brutto-Vorbefuellung), healthInsuranceSurchargePercent (MA-KV-Zusatz-Override), careChildlessSurchargeRate (PV-Kinderlosenzuschlag).
- **ida-Mehrumfang** (Provision, Buchungskonten, Faktura-vs-Abrechnung, kernzeit-/rahmenzeit-/offsite-KPIs) out-of-scope, aber zeigt: ida groesser als Plan-Scope.
- **ZeitCheckList** zeigt nur 6h/10h-Verstoesse, keine 11h/660min-Ruhezeit-Spalte — 660min ist WorkTime-Eigenleistung.
- **'ongoing'** ist in ida ein echtes persistiertes Feld (Vue + Flutter); WorkTime-Getter ist bewusste Abweichung, kein ida-Bestand.

## 5. Empfehlung

Die HOCH-/MITTEL-Korrekturen (U1/U2/InsO-Quelle, hr_tagesabschluss, ma_quali, hr_kinder, werktagsgenauer Urlaub/31.3.-Verfall als ida-Quelle) sollten direkt in §3-Gap-Tabelle und §4.3/§5.1/§5.2 des Plans eingetragen werden. Die NIEDRIG-Korrekturen sind kosmetisch/praezisierend. Der Plan bleibt insgesamt tragfaehig — die meisten Falschangaben betreffen Quellen-Attribution, nicht das Zielmodell selbst.
