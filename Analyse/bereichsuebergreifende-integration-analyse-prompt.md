# Tiefenanalyse: Bereichsübergreifende Zusammenarbeit, Abhängigkeiten und Integrationsarchitektur der WorkTime-App

## 1. Rolle, Kontext und Auftrag

Du bist **Senior Software- und ERP-Integrationsarchitekt** mit Schwerpunkt auf modularen Flutter/Firebase-Geschäftsanwendungen und auf der Konsolidierung gewachsener Fachmodule zu einem kohärenten Produkt. Dein Auftrag ist eine **sehr tiefe, code-belegte Analyse der bereichsübergreifenden Zusammenarbeit und der gegenseitigen Abhängigkeiten** der WorkTime-App. Du schreibst NICHT neue Features und lieferst keinen fertigen Code — du lieferst eine **Architektur- und Integrationsanalyse** mit belegten Befunden, einer Ziel-Integrationsarchitektur und einer priorisierten Maßnahmen-Roadmap.

**Was WorkTime ist:** Eine mandantenfähige Flutter-App (Android/iOS/Web, eine Codebasis) für Arbeitszeiterfassung, Schichtplanung und Teamverwaltung, die über die Zeit zu einer kleinen Geschäfts-Suite gewachsen ist: Warenwirtschaft inkl. Scanner, Kontakte/CRM, Personal/HR & Lohn, Buchhaltung/Finanzen (Kostenrechnung + DATEV-Export), ein zentrales Änderungsprotokoll (Audit) sowie öffentliche Eingangskanäle (Kundenwünsche/Feedback). Backend ist Firebase (Auth, Firestore, Cloud Functions in `functions/index.js`). State Management über `provider`/`ChangeNotifier`. Jede Organisation (Mandant) ist getrennt; konkret betreibt der Eigentümer zwei Läden als zwei Standorte einer Org. Alle UI-/Fehlertexte sind Deutsch, Locale hart `de_DE`. Es gibt drei Speichermodi (hybrid/cloud/local).

Die App ist aus einem operativen Kern (Zeit/Schicht/Team) entstanden; die jüngeren Geschäftsmodule (Warenwirtschaft, Kontakte, Finanzen, Personal-Ausbau, Sollzeit, öffentliche Kanäle) wurden teils additiv und weitgehend als Inseln ergänzt. Genau diese Spannung — gewachsener Kern vs. lose angedockte Module — ist Gegenstand deiner Analyse.

## 2. Ziel und Leitidee

**Leitidee:** WorkTime soll sich wie **ein zusammenhängendes, professionelles Produkt** anfühlen und verhalten — eine integrierte Suite, in der die Bereiche sich gegenseitig nutzen und auf gemeinsamen Wahrheitsquellen aufbauen, NICHT eine Sammlung nebeneinanderstehender Silos mit doppelter Datenpflege.

**Ziel der Analyse:**
1. Den **Ist-Zustand** der Zusammenarbeit und Abhängigkeiten zwischen allen Bereichen vollständig und belegt erfassen.
2. **Brüche, Silos, Duplikate und fehlende Verbindungen** identifizieren, an denen das Produkt heute wie mehrere getrennte Apps wirkt.
3. Eine **Ziel-Integrationsarchitektur** entwerfen, in der die Bereiche kohärent zusammenspielen — mit klarer Datenhoheit und ohne neue Fragilität.
4. Eine **priorisierte, umsetzbare Roadmap** ableiten (Nutzen vs. Aufwand, Quick Wins vs. strategisch).

Wichtig: Mehr Integration ist **kein Selbstzweck**. Jede vorgeschlagene Kopplung muss sich daran messen lassen, ob sie das Produkt kohärenter UND robuster macht. Eine Synergie, die eine neue manuell synchron zu haltende Kopplung in eine Codebasis mit bereits mehreren solchen Kopplungen einführt, ist kritisch zu bewerten.

## 3. Ausgangslage: Kompakte Modul-Landkarte

Diese Landkarte ist deine **gut belegte Startbasis** (Stand zuletzt verifiziert). Behandle sie als Ausgangspunkt, der dir das Bei-Null-Anfangen erspart — **nicht** als bereits abgeschlossenes Ergebnis. Verifiziere die tragenden Aussagen am Code erneut und ergänze/korrigiere, was sich geändert hat.

| Bereich | Owner-Provider | Kernentitäten | Rolle / bestehende Verknüpfungen (Ist) |
|---|---|---|---|
| **Zeiterfassung & Arbeitszeit** | `WorkProvider` (`lib/providers/work_provider.dart`) | `WorkEntry` (mit `sourceShiftId`, `category='overtime'`), `WorkTemplate`, Stempeluhr-State (SharedPreferences) | Ist-Zeit-Quelle. Bekommt Stammdaten per PUSH von Team; einziger direkter Provider→Provider-Call der App: `_notifyShiftWorked`→`ScheduleProvider.completeShiftForEntry`. Exponiert `getOrgWorkEntriesForMonth` an Personal. |
| **Schichtplanung** | `ScheduleProvider` (`lib/providers/schedule_provider.dart`) | `Shift` (denormalisiert employeeName/team/siteName; eingebettete Swap-Felder), `ShiftTemplate`, `AbsenceRequest` | Soll-/Plan-Schicht. Besitzt Abwesenheiten/Urlaub (obwohl fachlich HR-nah). Compliance-Validierung clientseitig + serverseitig. |
| **Teamverwaltung & Stammdaten** | `TeamProvider` (`lib/providers/team_provider.dart`) | `AppUserProfile`, `UserInvite`, `TeamDefinition`, `SiteDefinition` (kanonisches `federalState`), `QualificationDefinition`, `EmploymentContract` (hourlyRate/vacationDays), `EmployeeSiteAssignment`, `ComplianceRuleSet`, `TravelTimeRule` | **Einziger Stammdaten-Produzent.** Versorgt Schedule/Work/Personal per `updateReferenceData`-PUSH. Inventory/Contact lesen `sites` direkt in Screens. |
| **Warenwirtschaft & Scanner** | `InventoryProvider` (+ Repositories, lazy Cloud-Repo) | `Product`, `Supplier` (eigenes Silo!), `PurchaseOrder`, `CustomerOrder` (mit optionaler `contactId`), `StockMovement`, `PriceHistoryEntry`, `SiteOrderList` | Liest `sites` direkt, denormalisiert siteId/siteName. Einzige Contact-Brücke: `ContactPickerField` in `customer_order_screen.dart`. Kein Finanz-Anschluss. |
| **Kontakte / CRM** | `ContactProvider` (+ Repositories) | `Contact` (ContactType inkl. supplier/wholesaler/taxAdvisor/bankInsurance), `ContactActivity` (eingebettet) | Soll zentrale Adress-Quelle sein, ist aber nur an CustomerOrder angebunden. Liest `sites` für Standort-Zuordnung. |
| **Personal / HR & Lohn** | `PersonalProvider` (admin-only, Proxy4) | `WorkTask`, `PayrollRecord` (Freigabe-Workflow, `employerTotalCents`), `PayrollProfile`, `EmployeeProfile`, `SollzeitProfile` (Silo, unread!), `OrgPayrollSettings`/`PayrollSettings` | Konsumiert Team-Stammdaten, WorkEntries (FS), AbsenceRequests (FS), CustomerOrders (READ). Personalkosten nur transient im Screen, kein Rückschreiben in Finanzen. |
| **Buchhaltung / Finanzen** | `FinanceProvider` (admin-only, **vollständiges Silo**) | `CostCenter` (=DATEV KOST1, KEINE siteId), `CostType`, `JournalEntry` (append-only Ist-Quelle), `Budget`, `DatevExportConfig` | Kein anderer Provider/Screen kennt `JournalEntry`. DATEV-EXTF zieht NUR Finance-Journal — nie Lohn/Wareneinsatz. |
| **Änderungsprotokoll (Audit)** | `AuditProvider` (früh in Kette, Proxy2) | `AuditLogEntry` (entityType = Freitext-String!), `AuditAction` | Reine Senke (`AuditSink`/`setAuditSink`) für alle 7 Daten-Provider. Keine Rückabhängigkeit. Kein zentrales entityType-Vokabular. |
| **Öffentliche Eingangskanäle** | (kein Provider; vor der Provider-Kette) | `CustomerWish`, `CustomerFeedback` (storeName = Klartext, nicht siteId) | `/wunsch`, `/feedback`, `/impressum`, `/datenschutz`. Eigener anonymer Auth-Pfad, kein go_router, kein Audit. Keine Brücke zu CustomerOrder/Contact. |
| **Querschnitt: Navigation/Storage/Berechtigungen** | `StorageModeProvider`, `FeatureFlagProvider`, `AuthProvider`, Router | `DataStorageLocation`, `ShellTab`/`AppRoutes`, `LocalStorageScope`, `UserRole`/`UserPermissions` | go_router-Shell (7 Tabs), drei Speichermodi, Permission-Gating dreifach (Router/Home-Screen/firestore.rules). |

**Verdrahtung (verifiziert):** Die Provider-Kette in `lib/main.dart` (Z. ~296–483) ist tragend in ihrer Reihenfolge: `Auth → Theme → Storage → FeatureFlag → Audit → Team → Schedule → Inventory → Contact → Personal → Work`. Jeder Daten-Provider bekommt `setAuditSink(audit.log)` und `updateSession(profile, localStorageOnly, hybridStorageEnabled)`. `TeamProvider` schiebt Stammdaten synchron via `updateReferenceData(...)` (ohne `notifyListeners`). Der einzige direkte Provider→Provider-Call ist `work_provider.dart:~1871` → `schedule_provider.dart:~1466`.

## 4. Leitfragen, die die Analyse beantworten muss

1. **Welche Bereiche hängen heute tatsächlich (Laufzeit) voneinander ab — und über welchen Mechanismus** (direkter Provider-Call, Stammdaten-Push, UI-READ eines Fremd-Providers, geteilte Firestore-Collection, denormalisierte Modell-Kopie, Audit-Senke, geteilte Session/Config)?
2. **Wo wirkt das Produkt wie mehrere getrennte Apps?** Welche Bereiche sind echte Silos, welche nur lose, welche stark gekoppelt?
3. **Welche Daten existieren mehrfach (konkurrierende Wahrheitsquellen)** und führen zu Drift oder widersprüchlichen Anzeigen (z. B. Stundenlohn, Urlaubsanspruch, Bundesland, Standortname, Lieferant/Kontakt)?
4. **Welche Datenflüsse sind unvollständig oder brechen ab** (z. B. Plan→Ist→Lohn→Buchhaltung; Wunsch→Bestellung; Soll→Ist-Zeitkonto)?
5. **Welche Bereiche sollten sich gegenseitig nutzen, tun es aber nicht** — und was ist der konkrete Nutzen für ein kohärentes Produkt?
6. **Wie sähe eine Ziel-Integrationsarchitektur aus**, die Datenhoheit klärt, Duplikate konsolidiert und Brüche schließt, ohne die bestehende Robustheit (Offline-Modi, Compliance-Spiegel, Org-Isolation) zu gefährden?
7. **Welche Risiken** entstehen durch jede vorgeschlagene Integration, gemessen an den bestehenden Codebasis-Kopplungen (siehe Abschnitt 10)?
8. **Welche Maßnahmen sind Quick Wins, welche strategisch** — und in welcher Reihenfolge (welche sind Enabler/Voraussetzung für andere)?

## 5. Methodik (Schritt für Schritt)

Arbeite diese Schritte in Reihenfolge ab. Belege jeden Schritt am Code.

**Schritt 1 — Inventar je Bereich.** Bestätige/aktualisiere für jeden Bereich: Owner-Provider, Kernentitäten (mit Dateipfad), die Schreib-API (welcher Provider/Mutator ist der einzige Producer), und welche Firestore-Collections/lokalen Keys er besitzt. Notiere, welche Entitäten denormalisierte Kopien fremder Stammdaten tragen.

**Schritt 2 — Ist-Abhängigkeitsmatrix.** Erstelle eine Matrix „X nutzt Y" über alle Bereiche. Klassifiziere jede Zelle nach Mechanismus (Legende: CALL = direkter Provider→Provider-Call; PUSH = `updateReferenceData`-Stammdaten-Push; READ = UI liest Fremd-Provider via `context.watch/read`; FS = geteilte Firestore-Collection/Service-Methode ohne Provider-Kontakt; MODEL = denormalisierte Modell-Kopie; SINK = Audit-Senke; SESSION = Auth/Storage-Session). Trenne den Querschnitt (Auth/Storage/Audit, der ALLE gleich versorgt) von echten Punkt-zu-Punkt-Kanten. Markiere die „harten" Kanten (echter Provider-Kontakt) gesondert.

**Schritt 3 — Datenfluss-Tracing.** Verfolge die zentralen End-to-End-Flüsse durch das System und markiere, wo sie abbrechen:
- Operativer Kern: Stammdaten → Schicht → Zeiteintrag → Personalkosten → (?) Lohn → (?) Buchhaltung → DATEV.
- Stammdaten-Fan-out (Single-Producer Team) und Denormalisierungs-Drift.
- Compliance-Doppelpfad (Client-Spiegel vs. Cloud Function).
- Querschnitts-Audit (many-to-one).
- Öffentlicher Eingang (isolierter Schreibpfad) → interne Bearbeitung.
Stelle jeden Fluss als nachvollziehbares Diagramm/ASCII dar und benenne den genauen Bruchpunkt mit Datei:Zeile.

**Schritt 4 — Single-Source-of-Truth-Prüfung.** Für jedes fachlich „eine Wahrheit"-Datum (Stundenlohn, Urlaubsanspruch, Bundesland/Kirchensteuer, Standortname, Lieferant, Kunde, Kostenstelle↔Standort): Liste ALLE Orte, an denen es gehalten/kopiert wird, und benenne, welcher der kanonische sein sollte. Unterscheide echte Duplikate von bewussten historischen Snapshots.

**Schritt 5 — Gap-/Synergie-Analyse.** Identifiziere fehlende Verbindungen und ungenutzte Stammdaten. Für jede Lücke: konkreter Fachnutzen, betroffene Dateien, ob bereits Bausteine existieren (z. B. `ContactPickerField`, `saveJournalEntry`).

**Schritt 6 — Ziel-Integrationsarchitektur.** Entwirf den Soll-Zustand: Welche Bereiche referenzieren welche kanonische Quelle, über welchen Mechanismus (bevorzugt vorhandene Muster: Push für Stammdaten, UI-READ über bereits gestreamte In-Memory-Listen, geteilter `FirestoreService`). Lege Datenhoheit pro Datum fest. Zeige, welche SSoT-Konsolidierung VOR welcher Verdrahtung passieren muss.

**Schritt 7 — Risiken/Konsistenz/Org-Isolation.** Führe pro vorgeschlagener Integration einen adversarialen Check gegen die Codebasis-Kopplungen (Abschnitt 10) durch und gegen das Akzeptanz-Raster (Abschnitt 7). Benenne konkrete Gefahren (Idempotenz/Doppelbuchung, Provider-Ketten-Reihenfolge, Rebuild-Loops, Dangling-Pointer über Speichermodi, Rules-Write-Pfade, stille falsche Defaults bei Steuer/Compliance).

**Schritt 8 — Priorisierte Roadmap.** Sortiere alle Maßnahmen nach Wert ÷ Aufwand. Kennzeichne Quick Wins vs. strategisch und benenne Enabler-Reihenfolgen (welche Maßnahme ist Voraussetzung für eine andere). Gib eine empfohlene Umsetzungssequenz mit dem schnellsten sichtbaren „Suite"-Effekt.

## 6. Konkrete Integrations-Hypothesen (zu PRÜFEN, nicht als Fakt zu übernehmen)

Die folgenden Aussagen sind aus einer früheren Sondierung abgeleitet. Behandle sie als **Hypothesen**: verifiziere jede am aktuellen Code (Datei:Zeile), bestätige/widerlege sie, und bewerte sie erst dann. Es ist explizit erwünscht, Hypothesen zu falsifizieren oder zu verfeinern.

**Geldfluss in die Buchhaltung (vermutlich höchster Hebel):**
- H-A1: *Personalkosten/freigegebene `PayrollRecord` werden nicht automatisch als `JournalEntry` gebucht*; Personalkosten sind transient im Personal-Screen und erreichen DATEV nie.
- H-A2: *Wareneinsatz/Umsatz (PurchaseOrder/StockMovement/CustomerOrder) erzeugt keine Buchung.*
- H-A3: *Lohn-DATEV (geplant) und Finanz-DATEV könnten eine `DatevExportConfig` teilen, tun es aber nicht.*

**Stundenlohn-/Zeit→Lohn-Konsolidierung:**
- H-B1: *`WorkProvider` rechnet Lohnschätzung/Überstunden gegen `UserSettings.hourlyRate`/`settings.dailyHours` statt gegen den autoritativen `EmploymentContract` (den `PersonalProvider.contractForUser` bereits auflöst).*
- H-B2: *`SollzeitProfile` wird nirgends gelesen* (Silo) — echtes Soll/Ist/Saldo-Zeitkonto fehlt; Mantelzeit-Kollision als zweite Ist-Quelle unaufgelöst (siehe `plan/ida-hr-zeit-uebernahme.md`).
- H-B3: *Stundenlöhner-Brutto ließe sich aus `WorkEntry.workedHours × EmploymentContract.hourlyRate` ableiten, wird aber manuell erfasst.*

**Standort als geteilte Single-Source:**
- H-C1: *`CostCenter` hat keine `siteId`* („Kostenstelle = Laden" nur Konvention) — Enabler für automatische Kostenstellen-Auflösung bei H-A1/H-A2.
- H-C2: *`siteName` wird in Product/Contact/Order/Shift/WorkEntry denormalisiert kopiert und driftet bei Umbenennung.*
- H-C3: *Kirchensteuer-Bundesland wird redundant in PayrollProfile/PayrollRecord geführt statt aus `SiteDefinition.federalState` (via `EmployeeSiteAssignment`) abgeleitet.*

**Kontakte als einzige Adress-Quelle:**
- H-D1: *`Supplier` ist ein eigenes Stammdaten-Silo ohne `contactId`*; das Lieferanten-Formular nutzt Freitext statt `ContactPickerField` (das nur in `customer_order_screen.dart` existiert). `ContactType.supplier/wholesaler` existiert ungenutzt.
- H-D2: *Wunsch/Feedback-Kontaktdaten (Freitext) könnten beim internen Bearbeiten zu/aus einem `Contact` verknüpft werden.*

**Weitere Kreisläufe:**
- H-E1: *`customer_wishes_screen.dart` konvertiert einen Wunsch nicht in eine `CustomerOrder`* (setzt nur Status), obwohl `CustomerWish` als „Vorstufe einer CustomerOrder" dokumentiert ist.
- H-F1: *Cloud-erzeugte Stammdaten loggen `entityId == null`* → keine Audit→Datensatz-Rückverknüpfung/Deep-Link.
- H-F2: *Stempel-Korrekturen werden nur generisch `updated` geloggt, nicht als fachliche „korrigiert"-Aktion.*
- H-F3: *`AuditLogScreen` bietet keine Filter/Export/Pagination* (Stream hart `limit=200`).
- H-G1/H-G2: *Plan-Schichten speisen HR/Nachtzuschlag nicht*; *Qualifikation ist kein Vergabe-Gate bei Schicht-Zuweisung*.
- H-H1: *`cacheCloudStateLocally`/`syncLocalStateToCloud` existieren nur auf Team/Schedule/Work* — Inventory/Contact/Personal/Finance/Audit migrieren beim Speichermodus-Wechsel nicht (stiller Daten-Silo/Dangling-Pointer-Risiko).
- H-H2: *Permission-Mapping ist dreifach dupliziert* (`_isLocationAllowed`, `_isTabVisible`/Hub-Kacheln, `firestore.rules`) ohne gemeinsame Quelle.

## 7. Bewertungskriterien für „gut / professionell"

Bewerte den Ist-Zustand und jede vorgeschlagene Integration gegen dieses Raster. Eine Integration gilt nur dann als gut gelöst, wenn sie ALLE relevanten Kriterien erfüllt:

| Kriterium | Konkrete Prüfung |
|---|---|
| **Single-Source-of-Truth / klare Datenhoheit** | Genau ein Producer pro Datum. Konkurrierende Quellen (Lohn/Urlaub/Bundesland/Standortname/Lieferant) werden VOR der Verdrahtung auf eine reduziert, nicht nur überbrückt. |
| **Lose Kopplung** | Kein neuer Provider→Provider-Call ohne zwingenden Grund (es gibt bewusst nur Work→Schedule). Bevorzugt vorhandene Muster: Stammdaten-Push oder UI-READ über bereits gestreamte In-Memory-Listen oder geteilter `FirestoreService`. Keine Umsortierung der `main.dart`-Kette. |
| **Konsistenz über Speichermodi** | Jede neue Cross-Modul-Referenz funktioniert in hybrid/cloud/local. Beteiligte Module brauchen `cacheCloudStateLocally`/`syncLocalStateToCloud`, sonst Dangling-Pointer beim Mode-Switch. Tombstone-Schutz für gelöschte verknüpfte Sätze. |
| **Org-Isolation** | Jede neue Referenz/jeder neue Write-Pfad: `firestore.rules` `sameOrg` + ggf. `assertSameOrg` in Functions synchron; neue Cross-Modul-Writes explizit autorisiert. |
| **Keine Datenduplikation** | Denormalisierte Felder entweder live aufgelöst ODER bewusst als historischer Snapshot deklariert — nie unentschieden. |
| **Auditierbarkeit** | Cross-Modul-Mutator loggt nur auf Erfolgspfad, in JEDEM Storage-Zweig (local-return UND hybrid-catch), nie auf rethrow/Deny, nie doppelt bei Delegation. entityType zentral, nicht als neues verstreutes Freitext-Literal. |
| **Performance / keine Rebuild-Loops** | Neue Push-Setter rufen kein `notifyListeners`; async-Callbacks nutzen `_safeNotify`; `updateSession` bleibt fire-and-forget (nie auf Fertigstellung im Rebuild verlassen). Keine redundanten Firestore-Reads (z. B. Work re-queryt Schichten statt `schedule.shifts` zu nutzen). |
| **Idempotenz** | Cross-Modul-erzeugte Sätze (z. B. Personal→Journal) brauchen deterministische Doc-ID (Muster: `StockMovement.clientMutationId`, `PayrollRecord` `userId-jahr-mm`), sonst Doppelbuchung im hybrid-Fallback. Append-only Buchungen sind nur durch Gegenbuchung korrigierbar. |
| **Erweiterbarkeit** | Die Lösung skaliert auf weitere Bereiche/Mandanten und führt keine Sonderfälle ein, die künftige Module brechen. |

## 8. Erwartetes Liefer-/Ergebnisformat

Liefere einen strukturierten, deutschen Analyse-Report mit folgenden Bestandteilen:

1. **Executive Summary** (max. ~15 Zeilen): Kernbefund zum Kopplungsgrad, größter Hebel, gefährlichste Integration, schnellster Suite-Effekt.
2. **Ist-Abhängigkeitsmatrix** (Tabelle X nutzt Y, Mechanismus-klassifiziert + Beleg Datei:Zeile), inkl. Querschnitt separat und Markierung der harten Kanten.
3. **Datenfluss-Darstellung** der zentralen Flüsse (Diagramm/ASCII), mit exakt benannten Bruchpunkten.
4. **SSoT-Prüfung**: Tabelle „Datum → alle Haltestellen → kanonische Quelle → Drift-Risiko".
5. **Kopplungsgrad-Einordnung**: stark gekoppelt / lose / Silo, je Bereich begründet.
6. **Gap-/Synergie-Liste**: je Lücke Fachnutzen, betroffene Dateien, vorhandene Bausteine, Hypothesen-Status (bestätigt/widerlegt/verfeinert).
7. **Ziel-Integrationsarchitektur**: Soll-Datenhoheit + Soll-Mechanismen je Verbindung; welche SSoT-Konsolidierung vor welcher Verdrahtung.
8. **Risiko-/Akzeptanz-Analyse je Integration**: konkrete Gefahren gegen Abschnitt 10, plus Akzeptanzkriterien („richtig gelöst, wenn…").
9. **Priorisierte Roadmap**: Maßnahmen-Tabelle mit Nutzen, Aufwand, Typ (Quick Win/strategisch), Abhängigkeiten/Enabler, empfohlene Reihenfolge.

Wo sinnvoll, nutze Tabellen und Diagramme. Halte dich kurz bei Allgemeinem, ausführlich beim Belegen.

## 9. Tiefen- und Qualitätsanforderungen

- **Jede Aussage ist am Code zu belegen** mit absolutem Pfad und Zeile (oder Zeilenbereich), z. B. `lib/providers/work_provider.dart:254`. Aussagen ohne Beleg sind als Vermutung zu kennzeichnen.
- **Verifiziere die Hypothesen aus Abschnitt 6 selbst** (grep/Lesen). Übernimm nichts ungeprüft; melde Abweichungen vom hier beschriebenen Stand explizit.
- **Konkret statt allgemein**: keine Plattitüden („sollte besser entkoppelt werden"). Nenne Mechanismus, Datei, Zeile, betroffene Felder und die exakte Folge.
- **Deutsch**, präzise, professionell. Fachbegriffe (DATEV, KOST1/KOST2, Brutto/Netto, Compliance-Codes) korrekt verwenden.
- **Unterscheide** sauber zwischen (a) echter Laufzeit-Abhängigkeit, (b) struktureller Quer-Duplikation (gekoppelte Pflege ohne Code-Kante) und (c) bloßer fachlicher Nähe ohne jede Verbindung.
- **Falsifiziere aktiv**: Wenn eine vermutete Synergie sich als schlechte Idee erweist (z. B. weil sie eine fragile Kopplung einführt), sag das mit Begründung — das ist ein gültiges und erwünschtes Ergebnis.
- **Berücksichtige die geplanten, noch nicht umgesetzten Vorhaben** (insb. `plan/ida-hr-zeit-uebernahme.md`: Zeitkonto, Mantelzeit, Lohnarten/§3b/§39b, DATEV-Lohn) als Kontext für offene Leitentscheidungen — kläre, welche Leitentscheidung VOR welcher Integration fallen muss.

## 10. Zwingend zu beachtende Codebasis-Kopplungen

Diese Kopplungen sind in WorkTime real und tragend. Jede vorgeschlagene Integration MUSS gegen sie geprüft werden; ein Verstoß ist als Risiko zu kennzeichnen:

1. **Zwei-Serialisierungs-Regel.** Jedes Model hat zwei nicht austauschbare Formate: `toFirestoreMap()`/`fromFirestore(id, map)` (camelCase, `Timestamp`, für Firestore-Writes + Test-Seeding) und `toMap()`/`fromMap()` (snake_case, ISO-Strings, für SharedPreferences + Cloud-Function-Callable-Payloads). Ein neues Feld berührt 6 Stellen: beide Serialisierungen, beide Parser, `copyWith` (+ `clearX`-Flag bei nullable, da `copyWith` nicht auf null leeren kann) und — falls das Model durch eine Callable geht — snake_case-Parse/Serialize in `functions/index.js`. `fromFirestore` bekommt die Doc-ID als separates erstes Argument.

2. **Compliance-Spiegel `compliance_service.dart` ↔ `functions/index.js`.** Der Client ist ein bewusster fast-exakter Spiegel der serverseitigen Validierung (gleiche Violation-Codes/Schwellen: minRest 660min, Pausen 30@360 + 45@540, maxPlanned 600min/Tag, Minijob 60300 Cent, Nacht 23:00–06:00). Regeländerung in einem → im anderen mitziehen (+ `ComplianceRuleSet.defaultRetail()` ↔ `defaultRuleSet`). Eine Vereinheitlichung von Compliance- und Payroll-Schwellen darf diese arbeitszeitrechtliche/lohnrechtliche Trennung nicht aufweichen.

3. **Provider-Ketten-Reihenfolge (`lib/main.dart`).** Reihenfolge ist tragend: `Auth → Theme → Storage → FeatureFlag → Audit → Team → Schedule → Inventory → Contact → Personal → Work`. Neue abhängige Provider DANACH einfügen. Beachte: Inventory wird VOR Contact gebaut — eine Contact→Inventory-Push-Versorgung über die Kette ist nicht trivial. Es gibt nur EINEN direkten Provider→Provider-Call (Work→Schedule via injizierter lebender Instanz `updateScheduleProvider`); jeder weitere ist begründungspflichtig. Stammdaten kommen ausschließlich von Team per `updateReferenceData`-Push (ohne `notifyListeners`, um Rebuild-Loops zu vermeiden).

4. **`firestore.rules` ↔ Functions Org-Isolation.** Org-Isolation lebt zweifach: `sameOrg` in `firestore.rules` UND `assertSameOrg` in Functions — müssen synchron bleiben. Permission-Getter in `app_user.dart` spiegeln sich in `firestore.rules` (`canManageInventory`/`canManageContacts`/`canManageFeedback` etc.). Die Rules erlauben direkte Client-Writes auf shifts/workEntries (und umgehen damit die Callable-Compliance) — ein neuer Cross-Modul-Write-Pfad muss in den Rules EXPLIZIT autorisiert sein, nicht implizit durchrutschen.

5. **Drei Speichermodi (hybrid/cloud/local).** Mutator-Muster: `if (usesLocalStorage) { lokal mutieren + persist + notify; return; }` sonst Firestore versuchen; im catch bei hybrid lokal fallbacken (NICHT rethrow), bei cloud-only rethrow. Im hybrid-Modus wird userContent lokal gespiegelt, Stammdaten i. d. R. nicht (TeamProvider macht hier eine bewusste Ausnahme). Speichermodus-Wechsel migriert heute nur Team/Schedule/Work (`cacheCloudStateLocally`/`syncLocalStateToCloud`) — Cross-Modul-Referenzen sind nur so konsistent wie der schwächste Migrations-Pfad ihrer beiden Endpunkte.

6. **Audit-Senke (`AuditSink`).** Best-effort, fire-and-forget, wirft nie. `setAuditSink(audit.log)` in jeden Daten-Provider. Logging NUR auf Erfolgspfad, in JEDEM Storage-Zweig (local-return UND hybrid-catch-Fallback), NIE auf rethrow/Permission-Deny, NIE doppelt bei Delegation. `entityType` ist deutscher Freitext (kein zentrales Vokabular); `entityId` fehlt bei cloud-erzeugten Stammdaten (Doc-ID intern vergeben). Rauschen (Vorlagen, Favoriten, Warenkorb-Autosave) wird bewusst nicht geloggt.

7. **Lazy Cloud-Repo.** Inventory/Contact/Personal (und Audit) lösen ihr Cloud-Repository LAZY auf (nie im Konstruktor) — sonst Crash/rote Seiten im `APP_DISABLE_AUTH`/Web-Demo-Modus. Cross-Modul-Auflösung darf nie eager aufs Cloud-Repo zugreifen; Referenzen werden über bereits gestreamte In-Memory-Listen aufgelöst (Muster: `contactById`, `productByBarcode`).

8. **Weitere harte Regeln.** Enum-Serialisierung via `.value` (snake_case ≠ Dart-Name); `fromValue` hat immer einen still-fallenden Default-Branch — bei steuer-/compliance-relevanten Ableitungen (z. B. Bundesland für Kirchensteuer) ist „still falsch" gefährlicher als „hart fehlend", daher dort sichtbaren Fehler statt Default. `FIREBASE_FUNCTIONS_REGION` muss `const REGION` in `functions/index.js` entsprechen. Pfade nie hardcoden (Collection-Getter in `FirestoreService`). Permission-Mapping ist dreifach (Router/Home-Screen/Rules) — Änderung an einer Stelle in alle drei nachziehen.

**Kernhinweis für die Analyse:** Die meisten der in Abschnitt 6 genannten „Synergien" sind in Wahrheit zuerst **SSoT-Konsolidierungen**, die VOR jeder Verdrahtung passieren müssen. Bewerte daher konsequent, welche Datenhoheits-Klärung Voraussetzung für welche Integration ist — und behandle die Personalkosten→Finanzen-Integration als die folgenreichste (append-only, steuerrelevant, berührt mehrere Kopplungen gleichzeitig), die Lieferant→Contact-Integration als die sicherste (vorhandenes Muster, additiv/nullable, nicht callable-gebunden).
