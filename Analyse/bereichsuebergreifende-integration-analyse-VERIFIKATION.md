# Verifikation & Stand-Abgleich des Integrations-Reports

*Auftrag: jede `Datei:Zeile`-Behauptung des Reports `bereichsuebergreifende-integration-analyse-REPORT.md` unabhängig & adversarial am **aktuellen** Code prüfen und auf Auslassungen prüfen.*
*Methode: 13 Agenten (9 skeptische Belege-Verifizierer je Cluster + 4 blinde Gap-Hunter), ~1,0 Mio Token, 343 Tool-Aufrufe; danach eigene Gegen-Greps der folgenreichsten Umkehrungen. Stand: 2026-06-23.*

---

## 1. Kernbefund (in einem Satz)

> **Der Report ist überholt.** Er beschreibt den Code-Stand vom 22.06. 22:48 Uhr; in der Nacht/am Folgetag wurde genau entlang seiner eigenen Empfehlungen eine große HR-/Finanz-/Audit-Integration gebaut (neue Dateien `lib/core/zeitkonto_calculator.dart` 23.06. 12:57, `lib/routing/route_permissions.dart` 23.06. 10:48, `lib/core/site_name_resolver.dart` 23.06. 10:52 u. a.). **~15 der ~18 verifizierten Hypothesen sind im Working-Tree inzwischen umgesetzt** — die Code-Kommentare zitieren die Report-IDs (`H-A1`, `H-B1`, `H-H2` …) sogar als Umsetzungs-Begründung.

Folge: Die drei meistgelesenen Aussagen des Reports sind **sachlich falsch gegen den Ist-Stand**:

| Report-Aussage (Executive Summary) | Ist-Stand 2026-06-23 |
|---|---|
| „Das Finanzmodul ist ein **vollständiges Silo** ohne jede ein-/ausgehende fachliche Kante." (Z. 19/69/186) | **Falsch.** Finance hat 3 eingehende Geldfluss-Kanten (Personal→Finance, Inventory→Finance ×2, via Poster-Seams `main.dart:451-459`) + eine Screen-READ-Kante Finance→Team (`finance_screen.dart:1220`). |
| „Größter **Hebel**: der Geldfluss in die Buchhaltung (H-A1/H-A2) … erreicht den Steuerberater nie automatisch." (Z. 21) | **Umgesetzt.** Freigegebene `PayrollRecord` und Order-Statuswechsel buchen automatisch `JournalEntry` (deterministische IDs `pay-`/`po-`/`co-`). Offen bleibt nur **H-A3** (Lohn-DATEV). |
| „Gefährlichste Integration: Personalkosten→Journal — **Doppelbuchungsgefahr**, weil `PayrollRecord` kein `journalEntryId` trägt." (Z. 23/244) | **Entschärft.** `journalEntryId` existiert (`payroll_record.dart:184`, voll dual-serialisiert) + dreifache Idempotenz (`!wasFinalized`, `journalEntryId==null`, deterministische Doc-ID). |

Der Report disclaimt das selbst („Stand der Codebasis zum Analysezeitpunkt", Z. 3) — er war zum Zeitpunkt seiner Erstellung **inhaltlich korrekt**. Es ist kein Analysefehler, sondern reiner **Zeitverzug**. Dieses Dokument ist der verbindliche Ist-Stand.

---

## 2. Status je Hypothese — die große Umkehr-Tabelle

Legende: ✅ **umgesetzt** (Report-Empfehlung gebaut) · 🟡 **offen** (Befund trägt weiter) · 🔁 **verfeinert**.

| Hyp. | Report-Verdikt | IST-Stand 2026-06-23 | Aktueller Beleg (verifiziert) |
|---|---|---|---|
| **H-A1** Personalkosten→Journal | „bestätigt" (= fehlt) | ✅ **umgesetzt** | `personal_provider.dart:904` `setPayrollStatus` → `_bookPersonnelCostIfNeeded` (:963-983, Aufruf :942/955) → injizierter `_journalPoster` (:519/523); `finance_provider.dart:411-444` `postPersonnelCostJournal`, ID `pay-<documentId>` (:428/433); Verdrahtung `main.dart:453` |
| **H-A2** Wareneinsatz/Umsatz→Journal | „bestätigt" (= fehlt) | ✅ **umgesetzt** (Status-getriggert) | `inventory_provider.dart:103-131` Buchungs-Helper; `savePurchaseOrder`→received (:1204/1234, `po-<id>`), `saveCustomerOrder`→pickedUp (:1401/1430, `co-<id>`); `finance_provider.dart:487/502`; `main.dart:458-459`. **`adjustStock` (:985) bucht bewusst NICHT** (Wertbuchung am Order-Status) |
| **H-A3** Lohn-DATEV / `DatevExportConfig` teilen | „bestätigt" | 🟡 **offen** (korrekt) | `datev_export.dart:4-66` = rein Finanz-EXTF; kein LODAS/Lohnart (grep 0). Nur **geplant** (Plan E5/M-D, `plan/ida-hr-zeit-uebernahme.md:227-230`) |
| **H-B1** Work-Lohn auf Vertrag statt `UserSettings` | „bestätigt" | ✅ **umgesetzt** | `work_provider.dart:254-298`: `_hourlyRateOn` (:269-275) / `_dailyHoursOn` (:278-284) lösen den am `entry.date` gültigen Vertrag via `_activeContractForCurrentUser` (:289-299) auf; `settings` nur Fallback. Kommentar :254 „Quelle: EmploymentContract (SSoT, H-B1)". **Keine neue Provider-Kante** (eigene `_contracts`-Kopie) |
| **H-B2** `SollzeitProfile` ungenutztes Silo | „partly" | ✅ **angeschlossen** (außer Mantelzeit) | `personal_provider.dart:257-292` `activeSollzeitFor`/`zeitkontoFor`/`effektiveUrlaubstage`; neue Cores `lib/core/zeitkonto_calculator.dart`, `urlaub_calculator.dart`, `urlaub_migration.dart`; UI `personal_screen.dart:2346` `_ZeitkontoCard`; `salaryKind` (`employment_contract.dart:12/91`). **Mantelzeit weiter bewusst NICHT** (`zeitkonto_calculator.dart:34`, M11 offen) |
| **H-B3** Stundenlöhner-Brutto ableiten | „bestätigt" | ✅ **umgesetzt** | `personal_screen.dart:2188-2198` `_prefillGross` (bei `salaryKind==hourly`) + `_grossFromHours` (:2479-2487) = `workedHours × contract.hourlyRate` → fließt in `grossCents`. Feld bleibt manuell überschreibbar |
| **H-C1** `CostCenter.siteId` (Enabler) | „bestätigt" (= fehlt) | ✅ **umgesetzt** | `finance_models.dart:71` `final String? siteId` + alle 6 Serialisierungsstellen (:48/89/107/124/141/160/178). Doc :70 „DATEV bleibt `number` (KOST1)" |
| **H-C2** `siteName`-Denorm-Drift | „verfeinert (≥9)" | 🔁 **bestätigt + Resolver gebaut** | 9 Modelle tragen `siteName` (s. §5). **Resolver** `lib/core/site_name_resolver.dart:16` + `TeamProvider.siteNameById:79`; Back-Propagation in `saveSite` weiter bewusst absent. **Report übersieht 2 Klartext-Halteorte** (s. §4) |
| **H-C3** Bundesland aus Site vorbefüllen | „bestätigt" (= fehlt) | ✅ **umgesetzt** | `personal_provider.dart:505-515` `federalStateForUserPrimarySite`; `personal_screen.dart:2183-2186` Vorbefüllung. `SiteDefinition.federalState` (`:51`) **nicht mehr ungenutzt**; `PayrollRecord.federalState` bleibt Snapshot |
| **H-D1** Lieferant→Kontakt | „verfeinert" | ✅ **umgesetzt** | `supplier.dart:59` `contactId` (dual-serial.); `inventory_screen.dart:1650-1679` gefilterter `ContactPickerField` (`allowedTypes: supplier/wholesaler`) + Auto-Fill; `saveSupplier` direkt (`inventory_provider.dart:693`, callable-frei) |
| **H-D2** Wunsch/Feedback→Contact-Link | „bestätigt" | 🟡 **offen** (korrekt) | `CustomerWish`/`CustomerFeedback` tragen **kein** `contactId` (`customer_wish.dart:120-123`, `customer_feedback.dart:121-125`); Screens ohne `ContactPickerField` (grep 0) |
| **H-E1** Wunsch→CustomerOrder | „bestätigt" (= fehlt) | ✅ **umgesetzt** | `customer_wishes_screen.dart:210-267` `_convertToOrder` → `inventory.saveCustomerOrder`, idempotent über `sourceWishId` (:220/254; Modellfeld `customer_order.dart:266`) |
| **H-F1** Cloud-Stammdaten `entityId=null` | „bestätigt" | ✅ **behoben** | `firestore_service.dart:838-865` `saveSite/saveTeam` liefern `Future<String>` (Doc-ID); `team_provider.dart:892-898` loggt `entityId: prepared.id ?? savedId` |
| **H-F2** Stempel-Korrektur nur `updated` | „bestätigt" | ✅ **behoben** | `audit_log_entry.dart:10` `AuditAction.corrected`; `work_provider.dart:514/545` (`addEntry` loggt `corrected`), `correctClockEntry:1173-1221` |
| **H-F3** `AuditLogScreen` ohne Filter/Export/Pagination | „bestätigt" | ✅ **behoben** | `_FilterBar` (Volltext/Aktion/Objekttyp); CSV `export_service.dart:589`; Pagination `audit_provider.dart:121-126` `loadMore`; `watchAuditLog` `{int limit=200}` parametrisiert (`firestore_service.dart:1262`) |
| **H-G1** Plan speist Lohn nicht; kein §3b-Nachtzuschlag | „bestätigt" | 🟡 **offen** (korrekt) | `personal_provider` liest nur `WorkEntries` (:425-447), nie `Shift` (grep 0); `payroll_calculator.dart` ohne SFN/Nacht/§3b (grep 0). Beleg-Zeile verschoben (war :304-328) |
| **H-G2** Qualifikation = blockierendes Gate, Rules ungeprüft | „verfeinert" | 🟡 **gültig** (korrekt) | `compliance_service.dart:88-97` blocking `missing_qualification` + `functions/index.js:690-696`; `firestore.rules` prüft Shift-Writes nicht → Direct-Write umgeht |
| **H-H1** Speichermodus-Migration nur Team/Schedule/Work | „bestätigt" | ✅ **behoben** | **Alle 8** Provider haben `cacheCloudStateLocally`/`syncLocalStateToCloud` (Inventory :540/549, Contact :233/240, Personal :783/795, Finance :612/623, Audit :178/191); `settings_screen.dart:388-408` migriert über alle. Audit-`sync` bewusst leer (append-only) |
| **H-H2** Permission-Mapping 3-4-fach, Shop-Divergenz | „bestätigt" | ✅ **behoben** | Zentrale `lib/routing/route_permissions.dart` (Single Source of Truth); Router (`app_router.dart:187`) + Home (`home_screen.dart:881`) teilen sie; Shop-Tab beidseitig nur `canViewInventory` (`route_permissions.dart:37`) — **keine Divergenz mehr** |

**Bilanz:** ✅ umgesetzt: H-A1, H-A2, H-B1, H-B2, H-B3, H-C1, H-C2(Resolver), H-C3, H-D1, H-E1, H-F1, H-F2, H-F3, H-H1, H-H2 (**15**). 🟡 weiter offen: **H-A3, H-D2, H-G1, H-G2** (+ Mantelzeit/M11 als Leitentscheidung).

---

## 3. Was real noch offen ist (die belastbare Rest-Roadmap)

1. **H-A3 — Lohn-DATEV / LODAS** existiert nicht; nur Finanz-EXTF. Geplant (E5/M-D, Feature-Flag). Teilbar wäre nur Berater-/Mandantennummer. **Blockiert:** sitzt am Ende der Kette `M-D→M-MA→M-Z2+M-L`; ohne PayLine-/Lohnart-Quelldaten kein Export.
2. **H-D2 — Wunsch/Feedback → Contact-Verknüpfung** ✅ **umgesetzt (2026-06-23):** `contactId` (intern-only) in `CustomerWish`/`CustomerFeedback`, gegateter Update-Pfad, `showContactPicker`, Audit, Anzeige; Propagation Wunsch→Order über `CustomerOrder.fromCustomerWish`. (Siehe `integration-ausbau`-Memory.)
3. **H-G1 — §3b-Zuschlag (Nacht/Sonn/Feiertag)** 🟡 **teilweise umgesetzt (2026-06-23):** die **reine §3b-Aufteilung** (steuerfrei/SV-frei/-pflichtig mit 50 €/25 €-Caps, Plan §5.8b/E9, Meilenstein **M-L-a**) ist als quellen-entkoppelter Kern `lib/core/sfn_zuschlag.dart` gebaut + getestet. **Offen bleibt** die *Lage-Ermittlung* (welche Stunden = Nacht/Sonn/Feiertag) — sie speist sich laut §5.8b aus der **Mantelzeit-Lage** und hängt damit weiter an der Mantelzeit-Leitentscheidung. Plan-Schicht→Lohn ebenfalls dort.
4. **H-G2 — Qualifikations-Gate serverseitig** ⚙️ **akzeptierter Trade-off (kein baubarer Fix).** Das Gate (`missing_qualification`) ist im Client (`compliance_service.dart`) + in der Callable (`functions/index.js`) blockierend; `firestore.rules` prüft Shift-Writes bewusst nicht — **dieselbe „Sicherheitslücke per Design"** wie bei Ruhezeit/Pausen/Höchstarbeitszeit (Direct-Write umgeht ALLE Compliance, nicht nur Qualifikation). Eine Rules-eigene Prüfung ist **technisch nicht umsetzbar** (`employeeSiteAssignments`-Doc-IDs sind zufällig → ein Rules-`get()` kann die Zuordnung `(userId,siteId)` nicht auflösen; Rules können nicht queryen) und deckte zudem nur Qualifikation, nicht die ~8 übrigen Codes. Der **einzige** architektur-treue Fix ist Callable-only-Writes (= **Leitentscheidung #1 / M-Z1**, bricht den Hybrid-/Offline-Direct-Write-Fallback) — eine bewusste Entscheidung, kein neuer Defekt.
5. **Mantelzeit (M11)** bewusst nicht implementiert — die einzige Teilaussage von H-B2, die noch trägt. ⚠️ **Plan-Referenz im Report falsch zugeordnet** (s. §4, Punkt 6). **Dies ist die zentrale offene USER-Leitentscheidung (#2 „Ist-Einzelquelle"), die H-A3, H-G1-Ende und die §3b-Lage gemeinsam entsperrt.**

---

## 4. Vergessen / ignoriert (Auslassungen — die direkte Antwort auf „was wurde übersehen?")

Diese Befunde fehlen im Report **unabhängig vom Zeitverzug** — sie waren teils schon zum Report-Zeitpunkt da:

1. **Finanzmodul ist KEIN Silo — die 3 Poster-Seam-Kanten fehlen in der Matrix (🔴 hoch).** `main.dart:451-459` verdrahtet drei echte Cross-Provider-Mutations-Kanten über Funktionspointer (analog zur `AuditSink`, die der Report sehr wohl als Kante 2c führt): `setPayrollJournalPoster` (Personal←Finance), `setRevenueJournalPoster` + `setGoodsCostJournalPoster` (Inventory←Finance). Plus Screen-READ Finance→Team (`finance_screen.dart:1220`). → Abschnitte 2a/2b/2d **falsch**.
2. **Scanner-Modul fehlt komplett in der Bereichs-Landkarte (mittel).** Der Brief nennt „Warenwirtschaft & **Scanner**" als eigenen Bereich; der Report erwähnt `scanner`/`barcode`/`productByBarcode` **0×**. `scanner_screen.dart` liest `TeamProvider.sites` (:168/650/735) **und** `InventoryProvider` (:248/649/734) und schreibt über `adjustStock`/`issueStock`/`saveProduct` (auditiert). Fehlende Matrix-Zeile.
3. **Interne Manager-Inbox (Wunsch/Feedback) umgeht die Provider-Kette und ist un-auditiert (mittel). — ✅ BEHOBEN (s. Nachtrag).** `customer_feedback_screen.dart:36-37` und `customer_wishes_screen.dart:38-39` lesen/schreiben **direkt** über `FirestoreService` (`updateCustomerFeedbackStatus` :1509, `deleteCustomerFeedback` :1525 — **kein** `_audit`). Eigenes Architektur-Muster `Screen→Service`, das in der Matrix als Kategorie fehlt. Der Report nennt „kein Audit" nur für den *öffentlichen* Schreibpfad, nicht für die *internen* Mutationen.
4. **`siteName`-Liste unvollständig (mittel).** Abschnitt 3b zählt „genau 9". Es fehlen **zwei Klartext-Halteorte einer anderen Drift-Klasse**: `CustomerWish.storeName` (`customer_wish.dart:107`, required) und `CustomerFeedback.storeName` (`customer_feedback.dart:112`) — Klartext **ohne** `siteId`, nie gegen `SiteDefinition.name` reconcilierbar (öffentlicher Schreibpfad). Real: 9 (siteId+siteName) **+ 2** (storeName-Klartext). Klarstellung: „OrderCart" = Klasse `SiteOrderList` in `order_cart.dart:164` (kein 10. Modell); `StockMovement.productName` ist Produkt- nicht Standort-Denorm (Report-Ausschluss korrekt).
5. **Fehlende READ-Kanten in 2b (mittel/niedrig).** Work(Screen)→Team (`month_report_screen.dart:35/77/137`, `entry_form_screen.dart:133/747`); Schedule(Screen)→Team (`shift_planner_screen.dart:114`, `shift_editor_sheet.dart:363/398`); unvollständige Belege für Inventory→Team (`scanner_screen`, `customer_wishes_screen:218`) und Home/Dashboard (`dashboard_action_items_card.dart:30`, `home_screen_tabs.dart`).
6. **Plan-Referenz „M11" falsch zugeordnet (mittel).** Der Report verlangt mehrfach „Leitentscheidung **Mantelzeit (M11)** zuerst" (Z. 226/236/250/273/288). Im Plan ist **Leitentscheidung #11 = Terminal/Kiosk + Recruiting** (`plan/ida-hr-zeit-uebernahme.md:209`), **nicht** Mantelzeit. Gemeint sind: **Audit-Korrektur M11** (Mantelzeit↔Schicht-Completion, `plan:140-144`) + **Leitentscheidung #2** (Ist-Einzelquelle, `plan:200/217`) + **Meilenstein M-Z2** (`plan:969`).
7. **Org-Isolation neuer Write-Pfade nicht konkret an `firestore.rules` geprüft (🔴 hoch). — ⚙️ GEPRÜFT: kein Defekt (s. Nachtrag).** Brief Abschnitt 7/10.4 fordert je neuem Write-Pfad `sameOrg` (Rules) **und** ggf. `assertSameOrg` (Functions). Der Report nennt das nur abstrakt; **`assertSameOrg` kommt 0× vor**. Konkret fehlt: (a) `Supplier.contactId` — `suppliers`-Rule offen (`firestore.rules:826-831`), additiv unkritisch (hätte belegt werden müssen); (b) Personal→`JournalEntry` — `journalEntries`-Rule ist `isAdmin()`+`sameOrg` (`:793-799`), ein **Client-direkter** Write (vom Report selbst Z. 227 vorgeschlagen) läuft **ohne** Callable/`assertSameOrg` → server-seitig keine Compliance/Idempotenz. Die Verzweigung Client-direct vs. Callable bleibt unentschieden.
8. **Bundesland-SSoT (H-C3) ist im Plan bereits beschlossen (niedrig).** Der Report präsentiert „Bundesland aus Standort" als Neufund + warnt vor `EmployeeProfile.federalState`. Der Plan hat das längst als **Audit-Korrektur H6** (`plan:86-90`) + §5.1 (`plan:596-601`) entschieden — inkl. „`EmployeeProfile.federalState` existiert nicht", Org-Default Schleswig-Holstein, `isPrimary`-Auflösung. Anschluss an den Plan statt Doppelung.
9. **§3b/§39b-Lohnarten, Monatsabschluss-pro-MA, Compliance-Spiegel-Risiko nur dünn (mittel).** Als Voraussetzung der Personalkosten→Journal-Buchung (welche Lohnarten/Lines gebucht werden) fehlt die Verknüpfung zu Plan §5.8a/b (E8/E9) und §4.5 (M-MA). Das vom Plan §5.10 eigens als Aufwandsposten markierte **Compliance-Spiegel-Risiko** des Mantelzeit-Event-Modells (neue Tages-Aggregation in `compliance_service.dart` **und** `functions/index.js`, das `SollzeitProfile` nicht kennt) wird nur in einem Halbsatz (Z. 250) gestreift — nicht als eigene Dimension der Compliance-Spiegel-Kopplung (Brief 10.2).
10. **`journalEntryId`-Idempotenz-Prämisse überzeichnet (hoch).** Die „gefährlichste Integration" (Doppelbuchung, weil Schlüssel fehlt) trägt nicht: `payroll_record.dart:184` führt `journalEntryId` schon — der vom Report geforderte Baustein **existiert bereits**.
11. **Systematischer Zeilennummern-Versatz (mittel).** Die Preamble behauptet „jeder tragende Satz ist mit `Datei:Zeile` belegt". Real ist `personal_provider.dart` durchgängig **~220-260 Zeilen** verschoben, `main.dart` ab Personal **~+10-15**, viele Modellfelder ±1-2. Untergräbt die Nachprüfbarkeit; Symptom des älteren Trees.

---

## 5. Zeilennummern-Korrekturen (Auswahl, zur Nachpflege)

| Report-Zitat | Tatsächlich (2026-06-23) |
|---|---|
| `work_provider.dart:1871` (Work→Schedule CALL) | `:1905-1917` (Call :1911, catch :1913) |
| Team→Schedule PUSH `main.dart:476-483 → work_provider.dart:271` | `main.dart:490-497 → work_provider.dart:311-325` |
| Team→Personal PUSH `main.dart:432-436` „nur members/contracts/sites" | `main.dart:432-437` — **4 Felder** (members/contracts/sites/**siteAssignments**) → `personal_provider.dart:470-482` |
| `setAuditSink` `…401,445,466` | `…402(Contact),446(Finance),480(Work)` |
| `setPayrollStatus/finalizeAllDrafts personal_provider.dart:686-720` | `:904` / `:1010` (`:686-720` = `saveWorkTask`) |
| Personal liest WorkEntries `:311` / `:304-328` | `:425-447` (`loadOrgWorkEntriesForMonth`), `:430` |
| `watchAllAbsenceRequests personal_provider.dart:406` | `:570` (Feld `_absences`) |
| `activeSollzeitFor personal_provider.dart:190-193` | `:257-292` |
| UI-State `_federalState personal_screen.dart:1980` | `:2149`; Vorbefüllung `:2183-2186` |
| `Shift.displayLocation shift.dart:113-114` | Getter heißt **`effectiveSiteLabel`** (`:113-114`), kein `displayLocation` |
| `EmployeeSiteAssignment siteName :24` | `:12` (ctor required) / `:30` (Feld); `:24` = `siteId` |
| siteName-Felder Product:42/Contact:141/PO:195/CO:236/Shift:94/Tmpl:40/WE:17/Cart:180 | +1/+2: `43/142/196/238/95/41/18/181` |
| `payroll_record.federalState :151` | `:152` |
| `adjustStock clientMutationId inventory_provider.dart:907` | `:985-1014` (Param :990, default :1003, Übergabe :1014) |
| `firestore_service watchAuditLog :1156-1159` | `:1262-1265` |
| `app_router.dart:193-226` (Permission-Mapping) | jetzt `_SplashScreen`; Matrix in `route_permissions.dart:17-66`, Router-Aufruf `app_router.dart:187` |

---

## 6. Was der Report korrekt erfasst (faire Bilanz)

Der Report ist methodisch sauber; folgende Kernaussagen bleiben **richtig** (z. T. mit korrigierter Zeile):

- **Provider-Kette** inkl. korrekter Finance-Position (`Proxy3<Auth,Storage,Audit>` zwischen Personal und Work, `main.dart:441-471`); Work bleibt `Proxy5` ohne Finance-Abhängigkeit.
- **Einzige Provider-typisierte Feld-Kante**: `WorkProvider._scheduleProvider` (`work_provider.dart:85-89`) → `completeShiftForEntry` (`schedule_provider.dart:1466`). Korrekt. *(Aber: die 3 Poster-**Seams** sind funktionale Cross-Provider-Kanten, s. §4.1.)*
- **Team als einziger Stammdaten-Produzent**, 3 PUSH-Kanten ohne `notifyListeners`.
- Die **3 Section-0-Korrekturen** an der Ausgangs-Landkarte (Finance als Kettenglied; Personal→CustomerOrders ist Screen-READ, kein Provider-Read; `ContactPickerField` ist ein wiederverwendbares Widget) sind belegt richtig — Letzteres wird inzwischen an **zwei** Stellen genutzt (`customer_order_screen.dart:806` **und** `inventory_screen.dart:1650`).
- **Compliance-Doppelpfad** (3c) inkl. der bewussten Rules-Lücke (direkte shift/workEntry-Writes umgehen die Callable-Validierung).
- **SSoT-Methodik** (Snapshot vs. echtes Duplikat sauber getrennt: CustomerOrder-Laufkunde als Snapshot, `StockMovement.siteId` als saubere FK).
- **Abschnitt 10 (aktive Falsifikation)**: H-G2 (Gate existiert doch), Steuer-Default-Richtung (9 % = Über-, nicht Unterzahlung; `payroll_settings.dart:18-19/144-150`), kein `clientMutationId`-Modellfeld (nur Methoden-Param), 16-Länder-vs-3-Stufen-Dropdown — alle korrekt.

---

## 7. Empfehlung

1. **Den Report nicht weiter als Ist-Stand verwenden.** Er ist als historische Sondierung wertvoll (seine Empfehlungen wurden umgesetzt), aber seine Befund- und Roadmap-Tabellen (Abschnitte 1, 2d, 3a, 6, 8, 9) sind überholt. Eine Warn-Notiz wurde im Report-Kopf ergänzt.
2. **Reale Rest-Roadmap = §3** dieses Dokuments: H-A3 (Lohn-DATEV), H-D2 (Wunsch/Feedback→Contact), H-G1/§3b, H-G2 (Rules-Gate), Mantelzeit-Leitentscheidung.
3. **Vor der Mantelzeit-/Zeitkonto-Arbeit**: die korrekte Plan-Verankerung nutzen (Leitentscheidung #2 + Audit-Korrektur M11 + M-Z2, **nicht** „Leitentscheidung #11") und das Compliance-Spiegel-Risiko (Plan §5.10) als eigene Dimension führen.
4. **Architektur-Hygiene aus §4**: die 3 Poster-Seams + Scanner + die un-auditierte interne Inbox in eine künftige Matrix aufnehmen; org-Isolation der neuen Journal-Writes (`firestore.rules` `journalEntries` = `isAdmin`+`sameOrg`, ohne Callable) bewusst entscheiden.

---

## Nachtrag: behobene Defekte (2026-06-23)

Auftrag „konkrete Defekte beheben" — Ergebnis (alle Quality Gates grün: `flutter analyze` ohne neue Funde, **736 Tests grün**):

**✅ FIX 1 — Interne Wunsch/Feedback-Inbox wird jetzt auditiert (§4.3).**
Die internen Manager-Mutationen liefen direkt über `FirestoreService` (kein Provider → keine `AuditSink`) und umgingen damit das Änderungsprotokoll. Audit-Eintrag auf dem Erfolgspfad ergänzt in `customer_wishes_screen.dart` (`_updateStatus` → `AuditAction.updated`, `_delete` → `deleted`) und `customer_feedback_screen.dart` (analog), entityType `Kundenwunsch`/`Kundenfeedback`. Bewusst **im Screen** (Abweichung von „nicht im Screen"), da diese Entitäten keinen Provider haben — mit Code-Kommentar begründet. Der **öffentliche** anonyme CREATE-Pfad bleibt absichtlich un-auditiert.

**✅ FIX 1b — `firestore.rules`: `auditLog`-create erlaubt jetzt `corrected`.**
Die Create-Regel listete nur `['created','updated','deleted']`; die von H-F2 eingeführte `AuditAction.corrected` (Stempel-Korrektur) wäre damit im Cloud-Modus serverseitig **abgelehnt** und still verschluckt worden (best-effort). Wert ergänzt → Korrekturen persistieren jetzt. **Deploy nötig:** `firebase deploy --only firestore:rules`.

**⚙️ FIX 2 — Org-Isolation der Auto-Journal-Writes: kein Defekt (falsifiziert).**
Die vermutete Lücke (non-admin Order→Journal scheitert/umgeht Rules) besteht **nicht**: `_postOrderJournal`/`postPersonnelCostJournal` (`finance_provider.dart:524/416`) haben `if (!isAdmin \|\| _orgId == null) return null` — sauberer No-op für Nicht-Admins, **keine** abgelehnte Schreiboperation. Konsistent an allen drei Schichten (Finance-Guard + `saveJournalEntry._assertAdmin` + `firestore.rules isAdmin`). **Bewusst NICHT geändert** (Aufweichen würde Sicherheit reduzieren). Residual-Hinweis bleibt: ein Callable wäre die Härtung gegen fehlende serverseitige Buchungs-Validierung (gleiche „Sicherheitslücke per Design" wie bei shifts/workEntries — kein neuer Defekt). Bekannter Trade-off: von Nicht-Admins abgeschlossene Bestellungen erzeugen keine Auto-Buchung (Admin bucht manuell) — Feature-Entscheidung, kein Bug.

**✅ FIX 3 — M11-Fehlreferenz: korrekt verankert.**
Die richtige Zuordnung (Mantelzeit = **Audit-Korrektur M11**, `plan/ida-hr-zeit-uebernahme.md:140`, + Leitentscheidung #2 + M-Z2; **nicht** „Leitentscheidung #11" = Terminal/Recruiting) ist in §4.6 dieses Dokuments dokumentiert. Der REPORT selbst trägt die alte Referenz, ist aber per Kopf-Banner als überholt markiert — keine weitere Edit nötig.
