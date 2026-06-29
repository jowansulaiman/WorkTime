# Tiefenanalyse: Bereichsübergreifende Integration der WorkTime-App — Befund-Report

*Methode: 7 code-lesende Verifikations-Agenten + adversariale Re-Prüfung der 9 folgenreichsten Befunde, dazu unabhängige Gegen-Greps. Jeder tragende Satz ist mit `Datei:Zeile` belegt. Stand der Codebasis zum Analysezeitpunkt. Alle 9 adversarial geprüften Hypothesen wurden **bestätigt** (mit drei Präzisierungen, s. u.).*

> ⚠️ **STAND-KORREKTUR (2026-06-23) — dieser Report ist überholt.**
> Eine unabhängige Re-Verifikation (13 Agenten + Gegen-Greps) zeigt: Der Report beschreibt den Code-Stand vom **22.06. 22:48**. Seither wurde — entlang seiner eigenen Empfehlungen — eine große HR-/Finanz-/Audit-Integration gebaut. **~15 von ~18 Hypothesen sind im Working-Tree inzwischen umgesetzt** (H-A1, H-A2, H-B1, H-B2, H-B3, H-C1, H-C2, H-C3, H-D1, H-E1, H-F1, H-F2, H-F3, H-H1, H-H2). Insbesondere ist **das Finanzmodul kein Silo mehr** (Personalkosten/Umsatz/Wareneinsatz buchen automatisch `JournalEntry`, `main.dart:451-459`), und die als „gefährlichste Integration" bezeichnete Doppelbuchung ist via `PayrollRecord.journalEntryId` entschärft. Real offen bleiben nur **H-A3, H-D2, H-G1, H-G2** (+ Mantelzeit/M11).
> **Verbindlicher Ist-Stand, vollständiger Diff & Auslassungen:** [`bereichsuebergreifende-integration-analyse-VERIFIKATION.md`](bereichsuebergreifende-integration-analyse-VERIFIKATION.md). Die folgenden Befund-/Roadmap-Tabellen (Abschnitte 1, 2d, 3a, 6, 8, 9) sind teils nicht mehr aktuell.

---

## 0. Wichtigste Korrekturen an der Ausgangs-Landkarte

Bevor die Analyse beginnt — drei Abweichungen vom in der Aufgabe beschriebenen Stand, die das Bild verschieben:

1. **Die Provider-Kette hat einen Provider mehr als genannt.** Zwischen Personal und Work steht ein **`FinanceProvider`** (`lib/main.dart:440-457`, `Proxy3<Auth,Storage,Audit>`). Die in der Aufgabe zitierte Kette (`… → Personal → Work`) ist unvollständig. Korrekte Reihenfolge: `Auth → Theme → Storage → FeatureFlag → Audit → Team → Schedule → Inventory → Contact → Personal → **Finance** → Work`. Finance kommt **vor** Work, aber Work hängt nicht an Finance.
2. **Die „Personal nutzt CustomerOrders (READ)"-Kante ist eine *UI*-Kante, kein Provider-Datenlesen.** `PersonalProvider` liest selbst **keine** CustomerOrders (grep negativ). Die Kopplung sitzt im `personal_screen.dart:519/534` (`context.watch<InventoryProvider>()` rendert `inventory.customerOrders`). Das ändert die Datenhoheits-Bewertung.
3. **`ContactPickerField` ist bereits ein wiederverwendbares Widget** in `lib/widgets/contact_picker_field.dart:12` (nicht, wie vermutet, in `customer_order_screen.dart` „eingesperrt") — es liest die bereits gestreamte `ContactProvider.contacts`-Liste. Genutzt wird es nur an *einer* Stelle (`customer_order_screen.dart:806`), aber der Baustein ist sauber extrahiert.

---

## 1. Executive Summary

**Kernbefund Kopplungsgrad:** WorkTime ist heute ein **fest verdrahteter operativer Kern (Team→Schicht→Zeit) plus fünf weitgehend isolierte Inseln** (Warenwirtschaft, Kontakte, Personal/HR, Finanzen, öffentliche Kanäle). Es existiert genau **eine** echte Provider→Provider-Code-Kante (`WorkProvider → ScheduleProvider`, `work_provider.dart:1871`) und **drei** Stammdaten-Push-Kanten von Team. Alles andere ist entweder Querschnitt (Audit-Senke, Session) oder lose Screen-READ/geteilte-Collection-Kopplung. **Das Finanzmodul ist ein vollständiges Silo ohne jede eingehende oder ausgehende fachliche Kante.**

**Größter Hebel:** Der **Geldfluss in die Buchhaltung** (H-A1/H-A2). Freigegebene `PayrollRecord` (Personalkosten) und Wareneinsatz/Umsatz erzeugen **keinen** `JournalEntry`; DATEV zieht ausschließlich das **manuell** getippte Finanz-Journal (`datev_export.dart:129-137`, `finance_screen.dart:71-72`). Die gesamte Buchhaltung wird von Hand gefüttert — Lohn- und Warenkosten erreichen den Steuerberater nie automatisch.

**Gefährlichste Integration:** Die **Personalkosten→Finanzen-Buchung** selbst. Append-only-Journal + steuerrelevant + hybrid-Fallback ohne Idempotenz-Schlüssel (`PayrollRecord` trägt kein `journalEntryId`) = **Doppelbuchungsgefahr**; zusätzlich liegt Finance gar nicht in der genutzten Proxy-Kette von Personal. Diese Integration berührt vier der acht harten Codebasis-Kopplungen gleichzeitig.

**Schnellster „Suite"-Effekt:** **Lieferant→Kontakt** (H-D1) — additives, nullable `Supplier.contactId` + gefilterter `ContactPickerField`. Rein additiv, callable-frei (`saveSupplier` schreibt direkt), bricht keinen Pfad, nutzt vorhandene Bausteine. Sichtbarer Effekt: eine Lieferanten-/Adressquelle statt zwei.

**Strategischer Kernhinweis (bestätigt):** Fast alle „Synergien" sind in Wahrheit **SSoT-Konsolidierungen, die VOR der Verdrahtung fallen müssen.** Drei konkurrierende Wahrheitsquellen sind belegt: Stundenlohn/Tagessoll (`UserSettings` vs. `EmploymentContract` vs. `SollzeitProfile`), Bundesland (`PayrollProfile`/`PayrollRecord` vs. `SiteDefinition.federalState`), Lieferant (`Supplier`-Silo vs. `Contact`). Diese müssen erst auf je eine Quelle reduziert werden.

---

## 2. Ist-Abhängigkeitsmatrix

Legende: **CALL** = direkter Provider→Provider-Call · **PUSH** = `updateReferenceData`-Stammdaten · **READ** = UI liest Fremd-Provider (`context.watch/read`) · **FS** = geteilte Firestore-Collection ohne Provider-Kontakt · **MODEL** = denormalisierte Kopie · **SINK** = Audit-Senke · **SESSION** = Auth/Storage. **🔴 = harte Kante** (echter Provider-Kontakt, CALL/PUSH).

### 2a. Harte Kanten (echter Provider-Kontakt) — es gibt nur vier

| # | X nutzt Y | Mechanismus | Beleg | Anmerkung |
|---|---|---|---|---|
| 🔴1 | Work → Schedule | **CALL** | `work_provider.dart:1871` | **Einzige Provider→Provider-Code-Kante der App.** `_notifyShiftWorked → schedule.completeShiftForEntry(shiftId)` setzt Quell-Schicht auf `completed` (`schedule_provider.dart:1466-1494`). Lebende Instanz via `updateScheduleProvider` (`work_provider.dart:87-88`, `main.dart:465`). Fehler werden geschluckt (`try/catch :1873`). |
| 🔴2 | Team → Schedule | **PUSH** | `main.dart:365-371` | `members/contracts/siteAssignments/ruleSets/travelTimeRules` → `Schedule.updateReferenceData` (`schedule_provider.dart:217`). Kein `notifyListeners` (Rebuild-Loop-Schutz). |
| 🔴3 | Team → Work | **PUSH** | `main.dart:476-483` | `members/sites/contracts/siteAssignments/ruleSets/travelTimeRules` → `Work.updateReferenceData` (`work_provider.dart:271`). |
| 🔴4 | Team → Personal | **PUSH** | `main.dart:432-436` | Schmalere Teilmenge: nur `members/contracts/sites` → `Personal.updateReferenceData` (`personal_provider.dart:351-361`, kein `notifyListeners :359`). |

> `TeamProvider` ist der **einzige Stammdaten-Produzent** und hat selbst kein `updateReferenceData`.

### 2b. Lose Kanten (geteilte Collection / Screen-READ — kein Provider-Kontakt)

| X nutzt Y | Mechanismus | Beleg | Anmerkung |
|---|---|---|---|
| Personal → Work | **FS** | `personal_provider.dart:311`, `firestore_service.dart:391-408` | Liest dieselbe `workEntries`-Collection (`getOrgWorkEntriesForMonth`), die Work besitzt. Ausgelöst aus `personal_screen.dart:52`. Kein WorkProvider involviert. |
| Personal → Schedule | **FS** | `personal_provider.dart:406` | Abonniert `watchAllAbsenceRequests`; Schedule ist der *Schreiber* derselben `absenceRequests`-Collection (`schedule_provider.dart:993,1056,1641`). Beide kennen sich nicht. |
| Personal *(Screen)* → Inventory | **READ** | `personal_screen.dart:519,534` | UI liest `inventory.customerOrders`. **Provider liest nichts** — reine Screen-Kante. |
| Inventory *(Screen)* → Team | **READ** | `inventory_screen.dart:122`, `customer_order_screen.dart:130,353` | Screens lesen `TeamProvider.sites` für Standort-Auswahl. |
| Contact *(Screen)* → Team | **READ** | `contacts_screen.dart:63,623` | Liest `TeamProvider.sites` für Standort-Zuordnung. |
| Inventory *(Screen)* → Contact | **READ** | `customer_order_screen.dart:806` (`ContactPickerField`, `contact_picker_field.dart:12`) | Einzige Inventory↔Contact-Brücke; liest gestreamte `ContactProvider.contacts`, keine Zusatz-Reads. |
| Notification *(Screen)* → Inventory/Schedule | **READ** | `notification_screen.dart:98,99` | Aggregator-UI (`ordersDueSoonNotPrepared`, Abwesenheiten), gegated. |
| Home/Dashboard *(Shell)* → Inventory/Schedule/Work/Team | **READ** | `home_screen.dart`, `home_dashboards_v2.dart` | Multi-Bereichs-Aggregator per Definition. |

### 2c. Querschnitt (versorgt ALLE Daten-Provider gleich — keine Punkt-zu-Punkt-Kanten)

| Querschnitt | Mechanismus | Beleg |
|---|---|---|
| Alle Daten-Provider → Audit | **SINK** | `setAuditSink(audit.log)` an Team`:335` Schedule`:355` Inventory`:382` Contact`:401` Personal`:422` Finance`:445` Work`:466` (alle `main.dart`). Fire-and-forget (`audit_sink.dart`), wirft nie. |
| Auth+Storage → alle | **SESSION** | `updateSession(profile, localStorageOnly, hybridStorageEnabled)` in jedem Proxy: `main.dart:296,318,337,357,384,404,424,447,468`. |
| FeatureFlag/Router/Theme → Gating | — | `Consumer2` + `refreshListenable` (`main.dart:488`); nur Routing/Sichtbarkeit, keine Daten. |

### 2d. Vollständige Silos (keinerlei fachliche Kante)

- **Finanzen (`FinanceProvider`)**: keine eingehende und keine ausgehende fachliche Kante. Nur SINK(Audit) + SESSION. `JournalEntry` ist außerhalb der finance-nahen Dateien (`finance_provider`, `finance_models`, `finance_screen`, `finance_analytics`, `datev_export`, plus Plumbing `firestore_service`/`database_service`/`export_service`) **nirgends** referenziert.
- **Öffentliche Kanäle (Wunsch/Feedback)**: eigener anonymer Schreibpfad vor der Provider-Kette, kein Audit, keine Brücke zu Contact/CustomerOrder.

---

## 3. Datenfluss-Tracing (zentrale Flüsse + exakte Bruchpunkte)

### 3a. Operativer Kern → Lohn → Buchhaltung → DATEV (der entscheidende Fluss)

```
TeamProvider (Stammdaten: Mitarbeiter, Verträge, Sites, RuleSets)
   │ PUSH (updateReferenceData)            main.dart:365/432/476
   ▼
ScheduleProvider ──Plan-Schicht──┐
   │                             │
   │ (Work→Schedule CALL)        │  ✗ BRUCH G1: Plan speist HR/Lohn NICHT
   ▼                             │     personal_provider.dart:304-328 liest WorkEntries, nie Shifts
WorkProvider (Ist-Zeit: WorkEntry) ◀──┘
   │ FS (geteilte workEntries-Collection)  personal_provider.dart:311
   ▼
PersonalProvider / personal_screen
   │  • Brutto MANUELL getippt              ✗ BRUCH B3: personal_screen.dart:2047,2151
   │    (workedHours×rate wird nebenan      (Stunden×Vertrag wird für Statistik berechnet,
   │     berechnet, aber NICHT für Lohn)        :219-223 — fließt NICHT in grossCents)
   │  • Lohn-Schätzung im Dashboard nutzt    ✗ BRUCH B1: work_provider.dart:254/256
   │    settings.hourlyRate statt Vertrag       (UserSettings statt EmploymentContract)
   ▼
PayrollRecord.employerTotalCents  (Freigabe-Workflow, setPayrollStatus)
   │
   ▼   ╔══════════════════════════════════════════════════════════╗
   ✗   ║  HARTER BRUCH A1: personal_provider.dart:686-720          ║
       ║  setPayrollStatus / finalizeAllDrafts → NUR savePayroll-  ║
       ║  Record + _audit. KEIN saveJournalEntry, KEIN Finance-    ║
       ║  Import (personal_provider.dart:1-22). Danach KEINE Kante.║
       ╚══════════════════════════════════════════════════════════╝
                                          ┌─ Warenwirtschaft ─────────────┐
                                          │ adjustStock / savePurchaseOrder│
                                          │ / saveCustomerOrder            │
                                          │   inventory_provider.dart      │
                                          │   :889 / :1080 / :1241         │
                                          │ ✗ BRUCH A2: nur _audit, nie    │
                                          │   JournalEntry (grep = 0)      │
                                          └────────────┬───────────────────┘
                                                       ✗
FinanceProvider.saveJournalEntry  ◀── EINZIGER Aufrufer: manueller Editor finance_screen.dart:1091
   │  (Journal = append-only Ist-Quelle, von Hand getippt)
   ▼
DatevExport.buildBuchungsstapel(List<JournalEntry>)   datev_export.dart:129-137
   ▼   (KOST1 = CostCenter.number, KOST2 = costBearerRef; KEINE siteId-Auflösung :188)
DATEV-EXTF
```

**Folge:** Personalkosten und Wareneinsatz/Umsatz erscheinen in Kostenrechnung, Budget-Soll/Ist und DATEV **nur**, wenn ein Admin sie separat als `JournalEntry` einträgt.

### 3b. Stammdaten-Fan-out + Denormalisierungs-Drift

```
TeamProvider.saveSite (einziger Site-Produzent)
   │ PUSH (nur in-memory Listen an Schedule/Work/Personal)
   ▼
   siteId bleibt korrekt überall   ────────►  ✓ Joins/Auswertungen stabil
   siteName-SNAPSHOT in ≥9 Modellen ───────►  ✗ DRIFT bei Umbenennung
       Product:42 · Contact:141 · PurchaseOrder:195 · CustomerOrder:236
       · Shift:94 · ShiftTemplate:40 · WorkEntry:17 · OrderCart:180
       · EmployeeSiteAssignment:24 (siteName REQUIRED — stärkste Drift-Quelle)
   KEIN Back-Propagation-Pfad in saveSite → Altdaten zeigen alten Namen
   (z. B. Shift.displayLocation bevorzugt siteName, shift.dart:113-114)
```

### 3c. Compliance-Doppelpfad (intakt — Positiv-Beispiel)

```
compliance_service.dart  ──(bewusster Spiegel)──  functions/index.js
   gleiche Codes/Schwellen: minRest 660 · Pausen 30@360+45@540 · maxPlanned 600 · Minijob 60300 · Nacht 23:00-06:00
   ABER: firestore.rules erlauben direkte shift/workEntry-Writes → umgehen die Callable-Validierung (Lücke per Design)
```

### 3d. Öffentlicher Eingang → interne Bearbeitung (Bruch)

```
/wunsch (anonym, vor Provider-Kette)  →  CustomerWish (storeName = Klartext, kein siteId)
   │  Model-Doc: „Vorstufe einer CustomerOrder" (customer_wish.dart:73-74)
   ▼
customer_wishes_screen._updateStatus  →  NUR updateCustomerWishStatus   customer_wishes_screen.dart:184-203
   ✗ BRUCH E1: keine CustomerOrder-Erzeugung, kein InventoryProvider (grep = 0)
   ✗ BRUCH D2: customerName/customerContact = Freitext, kein Contact-Link (kein contactId)
```

---

## 4. Single-Source-of-Truth-Prüfung

| Datum | Alle Haltestellen (Beleg) | Kanonisch (Soll) | Art | Drift-Risiko |
|---|---|---|---|---|
| **Stundenlohn** | `EmploymentContract.hourlyRate` (`employment_contract.dart:62`) · `UserSettings.hourlyRate` (`user_settings.dart:7`, **von Work genutzt**, `work_provider.dart:254`) · einmalige Einweg-Kopie `team_provider.dart:1830` | `EmploymentContract` (versioniert) | **echtes Duplikat** | **Hoch** — kein laufender Sync; Vertragsänderung wirkt nicht aufs Dashboard |
| **Tagessoll/Std.** | `UserSettings.dailyHours` (`work_provider.dart:256`) · `EmploymentContract.dailyHours/weeklyHours` · `SollzeitProfile` (Tagessoll je Wochentag, `sollzeit_profile.dart`) | mittelfristig `SollzeitProfile`, kurzfristig `EmploymentContract` | **echtes Duplikat (dreifach)** | **Hoch** |
| **Urlaubsanspruch** | `EmploymentContract.vacationDays` · `UserSettings.vacationDays` · `SollzeitProfile.urlaubstageJahr` (Doc: „Migration in M0", `sollzeit_profile.dart:11-13`) | `EmploymentContract` (Migration offen) | **echtes Duplikat (dreifach)** | **Hoch** |
| **Bundesland (Kirchensteuer)** | `PayrollProfile.federalState` (`payroll_profile.dart:38`) · `PayrollRecord.federalState` (`payroll_record.dart:151`) · UI-State `_federalState` (`personal_screen.dart:1980`) — alle **manuell**; `SiteDefinition.federalState` (`site_definition.dart:51`) **ungenutzt** | `SiteDefinition.federalState` als **Vorbefüllung**, `PayrollRecord` als eingefrorener Snapshot | **Duplikat + ungenutzte Quelle** | **Mittel** (Richtgröße, Disclaimer; falscher Default = 9 % statt 8 %, *Über*zahlung) |
| **Standortname** | `siteName`-Snapshot in **≥9 Modellen** (§3b) | `SiteDefinition.name` via `siteId`-Resolver | Snapshot (teils REQUIRED → unentschieden) | **Mittel** (nur 2 Läden, aber bei Umbenennung sichtbar) |
| **Lieferant** | `Supplier`-Silo (`supplier.dart:30-56`, **kein contactId**) · `Contact` mit `ContactType.supplier` (`contact.dart:16`) | `Contact` als Adressquelle, `Supplier` als WaWi-Bestellprofil mit `contactId`-Link | **echtes Duplikat (parallele Felder)** | **Mittel-Hoch** |
| **Kunde** | `CustomerOrder.customerName/customerContact` (Freitext) + optional `contactId` (`customer_order.dart:247`) · `Contact` | `Contact`; `contactId` als Link | bewusster Snapshot (Laufkunde) — **korrekt gelöst** | Niedrig |
| **Kostenstelle ↔ Standort** | `CostCenter` (`finance_models.dart:40-72`, **kein siteId**) — nur Konvention „Nummer = Laden" | optionales `CostCenter.siteId` als Zuordnung, `number` (KOST1) bleibt kanonisch | **fachliche Nähe ohne Kante** | n/a (Enabler fehlt) |

**Positiv-Beispiele (saubere FK ohne Name-Denorm):** `StockMovement.siteId` (nur ID), `WorkEntry.sourceShiftId`, `JournalEntry.costCenterId/costTypeId`, `Budget`. Deterministische Doc-IDs als Idempotenz-Schlüssel: `PayrollRecord` (`userId-jahr-mm`, `payroll_record.dart:184`), `PayrollProfile` (`payroll_profile.dart:48`), `Budget` (`finance_models.dart:443`).

---

## 5. Kopplungsgrad-Einordnung je Bereich

| Bereich | Einordnung | Begründung (belegt) |
|---|---|---|
| **Team/Stammdaten** | **Hub (stark, ausgehend)** | Einziger Produzent; 3 harte PUSH-Kanten (`main.dart:365/432/476`). Korrekt zentralisiert. |
| **Schicht (Schedule)** | **stark gekoppelt** | Empfängt PUSH von Team, CALL von Work (`work_provider.dart:1871`), teilt `absenceRequests` mit Personal (FS). |
| **Zeit (Work)** | **stark gekoppelt** | PUSH von Team, einzige CALL-Kante zu Schedule, `workEntries` von Personal gelesen (FS). |
| **Personal/HR** | **lose** | Konsumiert über geteilte Collections (FS) + Screen-READ (Inventory), aber **keine** Provider-Kante hinaus; Personalkosten transient. |
| **Warenwirtschaft** | **lose Insel** | Nur Screen-READs (Team.sites, Contact via Picker); kein Finanz-Anschluss; `Supplier`-Silo. |
| **Kontakte/CRM** | **fast Silo** | Soll zentrale Adressquelle sein, ist aber nur über **einen** Picker an CustomerOrder angebunden; Lieferanten/Wunsch/Feedback ignorieren es. |
| **Finanzen** | **vollständiges Silo** | Keine fachliche Kante rein/raus (`JournalEntry` nirgends sonst referenziert). Von Hand gefüttert. |
| **Audit** | **Senke (Querschnitt)** | many-to-one SINK; keine Rückabhängigkeit; `entityType` Freitext, kein Vokabular. |
| **Öffentliche Kanäle** | **isolierte Insel** | Eigener anonymer Pfad, kein Audit, keine interne Brücke. |

---

## 6. Gap-/Synergie-Liste (Hypothesen-Status)

| ID | Status | Kurzbefund + Fachnutzen | Bausteine vorhanden | Beleg |
|---|---|---|---|---|
| **H-A1** | ✅ bestätigt | Freigegebene `PayrollRecord` → **kein** `JournalEntry`. Auto-Buchung machte Personalkosten DATEV-fähig. | `saveJournalEntry`, det. `PayrollRecord.documentId`, `PayrollStatus.isFinalized` | `personal_provider.dart:686-720`, `personal_screen.dart:183-234` |
| **H-A2** | ✅ bestätigt | Wareneinsatz/Umsatz → **keine** Buchung. Deckungsbeitrag/Rohgewinn fehlt. | `saveJournalEntry`, atomare `adjustStock`, Einkaufspreis-Felder | `inventory_provider.dart:889/1080/1241` (grep finance = 0) |
| **H-A3** | ✅ bestätigt | Lohn-DATEV existiert noch **gar nicht**; `DatevExportConfig` ist rein Finanz-EXTF. Nur Berater-/Mandantennr. wäre teilbar. | `DatevExportConfig.consultantNumber/clientNumber` | `datev_export.dart:3-66`, `plan/ida-hr-zeit-uebernahme.md:227-228` |
| **H-B1** | ✅ bestätigt | Work rechnet Lohn/Überstunden gegen `UserSettings`, nicht Vertrag. Doppelpflege. | `WorkProvider._contracts` (bereits vorhanden!), `contractForUser` | `work_provider.dart:254,256-259`, `:2366-2378` |
| **H-B2** | ⚠️ **partly** | `SollzeitProfile` = **Silo mit vollem CRUD, aber 0 Konsumenten** (`activeSollzeitFor` nur in Tests gelesen). **Mantelzeit-Kollision existiert NICHT** (zukünftiges Risiko M11, nicht IST). | `activeSollzeitFor` (gültig-ab-Auflösung fertig) | `personal_provider.dart:190-193`; grep `lib/screens|widgets|core` = leer |
| **H-B3** | ✅ bestätigt | Stundenlöhner-Brutto wird manuell getippt, obwohl `Stunden×Vertrag` nebenan berechnet wird. | `contractForUser(...).hourlyRate`, `workedHours` | `personal_screen.dart:2047,2151,219-223` |
| **H-C1** | ✅ bestätigt | `CostCenter` hat **kein** `siteId`. Auto-Kostenstellenzuordnung unmöglich. | `SiteDefinition`, `JournalEntry.costCenterId` | `finance_models.dart:40-72` (grep siteId = 0) |
| **H-C2** | 🔁 **verfeinert** | `siteName` denorm in **≥9 Modellen** (mehr als genannt: +ShiftTemplate, OrderCart, EmployeeSiteAssignment). Drift bei Umbenennung. | `siteId` überall stabil; Team einziger Hook | §3b |
| **H-C3** | ✅ bestätigt | Bundesland **dreifach** manuell statt aus `SiteDefinition.federalState`. | `SiteDefinition.federalState`, `EmployeeSiteAssignment`, `churchTaxRateFor` | `payroll_profile.dart:38`, `personal_screen.dart:2050-2054` |
| **H-D1** | 🔁 **verfeinert** | `Supplier` ohne `contactId`; Formular Freitext. `ContactPickerField` ist **Widget** (nicht eingesperrt). `ContactType.supplier` **wird genutzt** (Statistik), aber vom Bestellpfad entkoppelt. | `ContactPickerField`, `contactById`, callable-frei | `supplier.dart:30-56`, `inventory_screen.dart:1582-1754` |
| **H-D2** | ✅ bestätigt | Wunsch/Feedback-Kontakt = Freitext, kein Contact-Link beim Bearbeiten. | `ContactProvider.saveContact`, Picker | `customer_wishes_screen.dart:363-382` |
| **H-E1** | ✅ bestätigt | Wunsch → keine CustomerOrder (nur Status). | CustomerWish-Felder, Inventory-Mutatoren | `customer_wishes_screen.dart:184-203` |
| **H-F1** | ✅ bestätigt | Cloud-Stammdaten loggen `entityId = null` (Doc-ID intern vergeben). | `docRef.id` müsste nur durchgereicht werden | `team_provider.dart:885-890`, `firestore_service.dart:838-840` |
| **H-F2** | ✅ bestätigt | Stempel-Korrektur nur generisch `updated`; keine `corrected`-Aktion. | `_audit?.call` bereits verdrahtet | `audit_log_entry.dart:6`, `work_provider.dart:1164` |
| **H-F3** | ✅ bestätigt | `AuditLogScreen`: kein Filter/Export/Pagination, Stream hart `limit=200`. | Felder vorhanden; CSV-Muster `buildShiftPlanCsv` | `firestore_service.dart:1156-1159`, `audit_log_screen.dart:42-66` |
| **H-G1** | ✅ bestätigt | Plan speist HR/Lohn nicht; **Nachtzuschlag (§3b) existiert im Payroll-Code gar nicht**. | `WorkEntry.start/end`, Nacht-Schwelle 23-06 in Compliance | `personal_provider.dart:304-328`, `payroll_calculator.dart` (grep nacht = 0) |
| **H-G2** | 🔁 **verfeinert** | Qualifikation **IST** ein Gate (blockierende `missing_qualification`-Violation gatet `saveShifts`+Callable). **Aber**: nur wenn Assignment existiert, nur Client/Callable (Rules prüfen nicht → Direct-Write umgeht), Vorschau ohne eigenes Signal. | Violation bereits in beiden Spiegeln | `compliance_service.dart:82-99`, `schedule_provider.dart:389-396`, `firestore.rules:655` |
| **H-H1** | ✅ bestätigt | `cacheCloudStateLocally`/`syncLocalStateToCloud` nur Team/Schedule/Work. Inventory/Contact/Personal/Finance/Audit migrieren beim Moduswechsel **nicht**. | Etabliertes Muster; alle haben `usesLocalStorage` | `settings_screen.dart:365-392` (grep = 0 für die 5) |
| **H-H2** | ✅ bestätigt | Permission-Mapping **3-4-fach** dupliziert; **reale Divergenz**: shop-Tab `canViewInventory \|\| isAdmin` (Home) vs. nur `canViewInventory` (Router). | `ShellTab`/`AppRoutes`, Getter `app_user.dart` | `app_router.dart:193-226`, `home_screen.dart:871-888`, `firestore.rules:76-160` |

---

## 7. Ziel-Integrationsarchitektur (Soll-Datenhoheit + Soll-Mechanismus)

**Leitprinzip:** Keine neuen Provider→Provider-Calls außer dort, wo unvermeidbar. Bevorzugt: (a) bereits gepushte In-Memory-Kopien lesen, (b) geteilter `FirestoreService`, (c) Stammdaten-Push. **SSoT-Konsolidierung VOR Verdrahtung.**

| Verbindung | Soll-Datenhoheit | Soll-Mechanismus | Voraussetzung (SSoT zuerst) |
|---|---|---|---|
| **Work-Lohn/Überstunden** (H-B1) | `EmploymentContract` | Work liest seine **eigene** `_contracts`-Kopie (schon via PUSH da, `work_provider.dart:271`) — gleiche `isActiveOn(date)`-Auflösung wie `_effectiveRuleSetFor`. **Keine neue Kante zu Personal.** | `UserSettings.hourlyRate/dailyHours` als Lohnquelle aufgeben |
| **Stundenlöhner-Brutto** (H-B3) | `WorkEntry.workedHours × EmploymentContract.hourlyRate` | Berechnung im `personal_screen` (Bausteine `:219-223` schon da) als *Vorschlag* für `grossCents` | `salaryKind` (Gehalt/Stundenlohn) am Vertrag ergänzen |
| **Soll/Ist-Zeitkonto** (H-B2) | `SollzeitProfile` (Soll) + `WorkEntry` (Ist) | Calculator liest `activeSollzeitFor` (fertig) + WorkEntries | **Leitentscheidung Mantelzeit (M11) zuerst** — sonst zwei Ist-Quellen |
| **Personalkosten → Buchung** (H-A1) | `PayrollRecord` (Quelle) → `JournalEntry` (Buchung) | Nicht aus dem Provider — am besten **Screen-orchestriert** oder eine bewusst nach Personal eingehängte Finance-Instanz; **deterministische Journal-ID aus `PayrollRecord.documentId`** | `CostCenter.siteId` (H-C1) für Standort-Kostenstelle; `journalEntryId` an PayrollRecord |
| **Wareneinsatz/Umsatz → Buchung** (H-A2) | StockMovement/CustomerOrder → `JournalEntry` | wie A1; Idempotenz-Schlüssel zwingend | `CostCenter.siteId`; Idempotenz auf Order-Mutatoren |
| **Kostenstelle ↔ Standort** (H-C1) | `SiteDefinition` | optionales, nullable `CostCenter.siteId`; `number` (KOST1) bleibt kanonisch für DATEV | — (reiner Enabler) |
| **Bundesland** (H-C3) | `SiteDefinition.federalState` | **Vorbefüllung** bei neuer Abrechnung via `EmployeeSiteAssignment(primary).siteId` → Lookup; `PayrollRecord.federalState` bleibt **Snapshot** | Mapping 16-Länder→3-Stufen klären; nie live ableiten |
| **Lieferant** (H-D1) | `Contact` (Adresse) | additives nullable `Supplier.contactId` + gefilterter `ContactPickerField` (callable-frei) | — (sicherste, rein additiv) |
| **Standortname** (H-C2) | `SiteDefinition.name` | Resolver: Anzeige-`siteName` zur Laufzeit aus `siteId` auflösen; ODER Back-Propagation-Batch in `saveSite` | — |
| **Wunsch/Feedback → Contact/Order** (H-D2/E1) | `Contact` / `CustomerOrder` | „In Bestellung übernehmen"-Button; nicht-transaktional → Idempotenz-Schutz | — |
| **Permission-Quelle** (H-H2) | eine Route/Tab→Getter-Matrix | zentral an `AppRoutes`/`ShellTab`; Rules gegen dieselbe Matrix testen | shop-Divergenz auflösen |

**Reihenfolge der Voraussetzungen:** `CostCenter.siteId` (H-C1) ist **Enabler** für die saubere Kostenstellen-Auflösung in H-A1/H-A2. Die Stundenlohn-SSoT (H-B1) ist **Enabler** für H-B3 (abgeleitetes Brutto) und für eine korrekte Personalkosten-Buchung. Die Mantelzeit-Leitentscheidung (Plan M11) muss **vor** dem Zeitkonto (H-B2) fallen.

---

## 8. Risiko-/Akzeptanz-Analyse je Integration (gegen Abschnitt 10)

| Integration | Hauptgefahr (belegt) | „Richtig gelöst, wenn…" |
|---|---|---|
| **Personalkosten → Journal** (H-A1) | **Doppelbuchung** im hybrid-Fallback: `setPayrollStatus` läuft Cloud→catch→lokal (`personal_provider.dart:686-701`); jeder erneute Status-Set buchte erneut, da `PayrollRecord` **kein** `journalEntryId` trägt. + **Ketten-Reihenfolge**: Finance nicht in Personals Proxy; kein Zugriff auf lebende Instanz (`personal_provider.dart:1-22` importiert finance nicht). + **Zwei-Serialisierung**: handgebauter Entry mit falschem Soll/Haben/Default läuft still in DATEV. | Journal-ID **deterministisch** aus `PayrollRecord.documentId`; Buchung nur bei `isFinalized`-Übergang **einmal**; `journalEntryId`-Rückverweis; Org-Isolation in Rules; Audit nur im Erfolgspfad, nicht doppelt. |
| **Wareneinsatz → Journal** (H-A2) | `savePurchaseOrder`/`saveCustomerOrder` haben **keinen** Idempotenz-Schlüssel (anders als `adjustStock`, das `clientMutationId` nutzt, `inventory_provider.dart:907`); hybrid-catch (`:1106-1114`/`:1266-1274`) erzeugt Doppel-Write. | Buchung an **deterministische** ID (Order-ID) gebunden; nur einmal pro Order; CostCenter via `siteId` aufgelöst. |
| **CostCenter.siteId** (H-C1) | Zwei-Serialisierung (6 Stellen `finance_models.dart`); fehlender `toMap`/`fromMap`-Zweig lässt Zuordnung im local/hybrid still verschwinden. Auto-Resolver bei **mehreren** Kostenstellen/Site nicht-deterministisch. | `siteId` **nullable, nicht-unique**; `number` bleibt KOST1; Resolver liefert nur Vorbelegung, keine harte 1:1-Annahme. |
| **Bundesland aus Site** (H-C3) | **Rückwirkende Steueränderung**: live aus Site abgeleitet änderte abgeschlossene Monate bei Standortwechsel → Idempotenz-/Snapshot-Verletzung. `_stateCode` wirft nie → leere `SiteDefinition.federalState` fällt still auf 9 %. | Nur **Vorbefüllung** bei *neuer* Abrechnung; `PayrollRecord.federalState` bleibt unveränderlicher Snapshot; Ableitung über `siteId` (stabil), **nicht** `siteName`; sichtbare Validierung statt stillem Default. |
| **Supplier.contactId** (H-D1) | Zwei-Serialisierung (6 Stellen `supplier.dart`); Altdaten ohne `contact_id` müssen tolerant gelesen werden. **Geringstes Risiko** — additiv, nullable, callable-frei (`saveSupplier` direkt). | `contactId` nullable; `clearContactId`-Flag; `fromMap`/`fromFirestore` Null-tolerant; Picker auf `ContactType.supplier/wholesaler` gefiltert. |
| **Work-Lohn auf Vertrag** (H-B1) | Neue Kante zu Personal **vermeiden** — Work hat `_contracts` schon. Falscher Default (kein Vertrag → 0.0) erzeugt still-falsche Lohnzahlen. | Auflösung lokal aus `_contracts` mit `isActiveOn(entry.date)` **pro Eintrag** (nicht `now()`); fehlender Vertrag sichtbar, nicht still 0. |
| **Zeitkonto** (H-B2) | Mantelzeit als 2. Ist-Quelle ohne Leitentscheidung → Doppelzählung; neuer Server-Spiegel `validateMantelzeitDay` driftet (functions kennt SollzeitProfile nicht). | Leitentscheidung M11 zuerst; eine Ist-Quelle oder klare Additionsregel; Spiegel synchron. |
| **Wunsch → Order** (H-E1) | Zwei nicht-transaktionale Writes (Wunsch direkt vs. Order mit Hybrid-Fallback) → Inkonsistenz; keine Bindung Order↔wishId. | Idempotenz an `wishId`; kein Audit-Doppellog (Order loggt schon); Status + Order konsistent. |
| **Speichermodus-Migration der 5** (H-H1) | Jeder Provider braucht **beide** Methoden tombstone-bewusst; `syncLocalStateToCloud` muss snake→camel korrekt round-trippen; Finance braucht Idempotenz. | Symmetrische `cacheCloudStateLocally`/`syncLocalStateToCloud` + Einhängen in alle drei Zweige `settings_screen.dart:378-390`; Audit-Migration ohne Re-Audit. |

---

## 9. Priorisierte Roadmap

Wert ÷ Aufwand. **QW** = Quick Win, **S** = strategisch.

| # | Maßnahme | Typ | Nutzen | Aufwand | Enabler / Abhängig von |
|---|---|---|---|---|---|
| 1 | **Lieferant→Kontakt** (`Supplier.contactId` + gefilterter Picker) (H-D1) | QW | Hoch (eine Adressquelle, Kontakthistorie für Lieferanten) | Niedrig (additiv, callable-frei) | — |
| 2 | **Audit-Verbesserungen**: `entityId` durchreichen (H-F1), `corrected`-Aktion (H-F2), Filter/Pagination/Export im `AuditLogScreen` (H-F3) | QW | Mittel-Hoch (Revisionssicherheit) | Niedrig-Mittel | — |
| 3 | **Permission-Matrix zentralisieren** + shop-Divergenz fixen (H-H2) | QW | Mittel (Konsistenz, weniger tote Deep-Links) | Niedrig-Mittel | — |
| 4 | **`siteName`-Resolver** statt Persistenz, ODER Back-Propagation in `saveSite` (H-C2) | QW | Mittel (Drift weg) | Mittel | — |
| 5 | **`CostCenter.siteId`** (optional, nullable) (H-C1) | S (**Enabler**) | Hoch (Voraussetzung für 6/7) | Niedrig-Mittel | — |
| 6 | **Work-Lohn/Überstunden auf `_contracts`** umstellen (H-B1) | S | Hoch (eine Lohnquelle) | Mittel | SSoT: UserSettings-Lohn aufgeben |
| 7 | **Stundenlöhner-Brutto ableiten** (`salaryKind`) (H-B3) | S | Mittel-Hoch (weniger Tippfehler) | Mittel | #6 |
| 8 | **Bundesland-Vorbefüllung aus Site** (H-C3) | S | Mittel (Kirchensteuer-Konsistenz) | Mittel | Mapping-Klärung; Snapshot beibehalten |
| 9 | **Personalkosten → JournalEntry** (Auto-Buchung) (H-A1) | S (**größter Hebel**) | Sehr hoch (DATEV vollständig) | Hoch (Idempotenz, Ketten-Workaround) | #5, `journalEntryId` |
| 10 | **Wareneinsatz/Umsatz → JournalEntry** (H-A2) | S | Hoch (Deckungsbeitrag) | Hoch (Idempotenz auf Order-Mutatoren zuerst) | #5, #9-Muster |
| 11 | **Speichermodus-Migration für 5 Provider** (H-H1) | S | Hoch (Datenverlust-Schutz) | Hoch (5× Muster + Tombstones) | wird mit jeder Cross-Modul-Referenz dringender |
| 12 | **Soll/Ist-Zeitkonto** (H-B2) + **Mantelzeit-Leitentscheidung** | S | Hoch | Hoch | **Leitentscheidung M11 zuerst** |
| 13 | **Wunsch→Order** + Wunsch/Feedback→Contact (H-E1/D2) | S | Mittel | Mittel (Idempotenz, 2 Writes) | #1 |

**Empfohlene Sequenz für schnellsten Suite-Effekt:** **1 → 2 → 3** (sichtbare Quick Wins ohne SSoT-Risiko) → **5** (Enabler) → **6 → 7** (Lohn-SSoT) → **9 → 10** (Geldfluss, der große Hebel) — **11 parallel hochziehen**, sobald die erste Cross-Modul-Referenz (z. B. #1) live ist, weil Cross-Modul-Referenzen nur so konsistent sind wie der schwächste Migrationspfad ihrer Endpunkte.

---

## 10. Aktiv falsifizierte / entschärfte Annahmen (ehrliche Gegenrede)

- **„Still-falscher Steuer-Default ist gefährlich" (Abschnitt 10.8):** Real, aber **die Richtung ist Über-, nicht Unterzahlung.** Unbekanntes/leeres Bundesland fällt auf **9 %** (den höheren Satz, `payroll_settings.dart:144-150`); der gesamte Lohnteil ist als „Richtwert – keine zertifizierte Lohnbuchhaltung" disclaimt (`german_tax.dart:10-11`). Die Schwäche ist fehlende **Validierung/Ableitung**, nicht eine gefährliche Default-Logik.
- **„Bundesland hart aus Standort ableiten" wäre falsch:** `SiteDefinition.federalState` führt 16 Länder, das Lohn-Dropdown nur 3 Stufen; ein Mitarbeiter kann mehreren Sites zugeordnet sein, und das **Lohnsteuer**-Bundesland ist nicht zwingend das Standort-Bundesland. Nur als **Vorbefüllung** zulässig, nie als harte FK.
- **„Work an `PersonalProvider.contractForUser` koppeln":** unnötig fragil — es entstünde eine **zweite** Provider→Provider-Kante. Work hält `_contracts` bereits selbst (`work_provider.dart:271`). Die saubere Lösung liest diese Kopie, keine neue Kante.
- **„DatevExportConfig vereinheitlichen" (H-A3):** Finanz-EXTF (Sachkonten, festes Gegenkonto) und Lohn (Lohnartnummern, LODAS) haben **disjunkte** Pflichtfelder. Nur Berater-/Mandantennummer als gemeinsamer Org-Stammsatz heben — formatspezifische Felder getrennt lassen.
- **Idempotenz-Annahme der Aufgabe korrigiert:** Es gibt **kein** `clientMutationId` auf `PurchaseOrder/StockMovement/CustomerOrder` als Modellfeld; `adjustStock` nutzt einen Mutations-Schlüssel auf Transaktionsebene (`inventory_provider.dart:907`), die Order-Mutatoren **nicht**. Idempotenz lebt sonst nur über deterministische Doc-IDs (PayrollRecord/Profile/Budget).
- **H-G2 (Qualifikations-Gate):** Die Hypothese „kein Gate" ist **widerlegt** — es *ist* ein blockierendes Gate (Client + Callable). Die echte Lücke ist die fehlende Rules-Durchsetzung (Direct-Write umgeht) und das fehlende Vorschau-Signal.
- **H-B2 (Mantelzeit-Kollision):** Die behauptete „zweite Ist-Quelle" existiert **zur Laufzeit nicht** (`Mantelzeit`/`ZeitkontoSnapshot`/`salaryKind` nirgends implementiert). Es ist ein **geplantes** Risiko (M11), kein aktueller Bug — die Leitentscheidung muss aber vor dem Zeitkonto fallen.
