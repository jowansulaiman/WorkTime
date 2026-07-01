# Arbeitsmodus / Laden-Tablet — Kachel-Ausbau

**Stand:** 2026-07-01 · **Status:** Entwurf (final, review-gehärtet) · §9-Entscheidungen getroffen (Inhaber delegiert) · MHD-Warnung ergänzt (§2.6 + [`plan/mhd-ablauf-warnung.md`](mhd-ablauf-warnung.md))
**Fundament:** [`plan/arbeitsmodus-laden-tablet.md`](arbeitsmodus-laden-tablet.md) (I0–I3 umgesetzt: Gate-Route `/arbeitsmodus` in der Shell, Board/Session-Trennung, PIN-Login, Stempeln, Kühlschrank, Laden-To-Dos, Kundenwünsche, Kachel-Registry, 90 s-Auto-Logout, Always-On).

Dieses Dokument **dupliziert das Fundament nicht**, sondern beschreibt den **Ausbau**: aus jedem Software-Bereich die *wirklich arbeitsrelevanten* Kacheln ergänzen — und den Rest bewusst weglassen.

> **Zeilennummern** in diesem Dokument sind gegen den aktuellen `HEAD` (Branch `fix/web-scanner-csp-selfhost-zxing`) verifiziert. Wo ich etwas nicht am Code prüfen konnte, steht **(Annahme)**.

---

## 0. Zwingende Vorbedingung (blockiert alles andere): Kiosk-Read-Scope härten

**Der Read-Scope des Geräte-Kontos ist heute zu weit — nicht zu eng.** Die Datensparsamkeit-Argumentation des Fundaments („Mitarbeiter loggt sich nie ein → HR/Lohn nie am Gerät") hält an einer Stelle **nicht**, solange das Kiosk-`users/{uid}` keine expliziten Permission-Overrides trägt.

Verifiziert in `firestore.rules`:
- `sameOrg(orgId)` verlangt `isActiveUser()` = `hasProfile()` (`:72–74`) → das Geräte-Konto **muss** ein aktives `users/{uid}` haben, um überhaupt zu lesen.
- `canViewSchedule()` (`:245`) → `permissionOrDefault('canViewSchedule', defaultCanViewSchedule())`, und `defaultCanViewSchedule()` (`:80–82`) = `isActiveUser()`. Analog `defaultCanViewTimeTracking()` (`:92–94`) und `defaultCanViewReports()` (`:100–102`) = `isActiveUser()`.
- `permissionOrDefault` (`:110–114`) fällt bei **fehlendem** `permissions.<feld>` auf diesen Default zurück.

**Konsequenz:** Ein Kiosk-Profil **ohne** `permissions`-Overrides erfüllt per Default `canViewSchedule == canViewTimeTracking == canViewReports == true`. Damit liest es heute **schon** `shifts` (`:702–703`) und **jede** Collection, die nur eines dieser drei Rechte verlangt. Das ist der größte Datensparsamkeits-Leak des Ausbaus, nicht die (fälschlich angenommene) fehlende Öffnung.

**Fix (verbindlich, vor jeder neuen Kachel):** Das Kiosk-`users/{uid}`-Profil trägt **explizite** Permission-Overrides auf `false`:

```
permissions: {
  canViewSchedule: false,      // Board liest Schichten NICHT über users-Permission,
  canViewTimeTracking: false,  //   sondern über eine schmale Projektion (§5/§6)
  canViewReports: false,
  canEditSchedule: false,
  canEditTimeEntries: false,
}
```

Damit greift `permissionOrDefault` den **gesetzten** `false`-Wert statt des `isActiveUser()`-Defaults. Alternative (robuster, aber invasiver): einen `isKiosk()`-Helper einführen und in `defaultCanViewSchedule/-TimeTracking/-Reports` jeweils `&& !isKiosk()` ergänzen. **Empfehlung: Profil-Overrides**, weil sie den generischen Rules-Kern nicht anfassen und pro Gerät auditierbar sind. Der Bootstrap des Geräte-Kontos (I0 im Fundament) **muss** diese Overrides setzen — ein Kiosk-Konto ohne sie gilt als Fehlkonfiguration.

**Voll-Audit der offenen `sameOrg`-Reads** (Ist-Stand, `grep -n "allow read: if sameOrg(orgId);" firestore.rules`): u. a. `teams:690`, `sites:503`, `shifts:702` (mit Permission-Zusatz), `storeTasks:877`, `kioskRoster:905`, `products:1078`, `customerWishes:1150`, `contacts:1343`, `stockMovements:1354`, `customerOrders:1132`, `fridgeRefillLists:1325`. Jede Zeile ist im Kiosk-Kontext einzeln zu bewerten (§3/§6): bewusst zulassen oder für `role:kiosk` verweigern. **`stockMovements` (`:1354`) und `contacts` (`:1343`) sind heute offen und ungewollt** — s. §6.

---

## 1. Ziel & Leitprinzip

Das Laden-Tablet ist ein **fest installiertes, geteiltes Gerät** (Android-Tablet + iPad, kein Web), immer an, fest pro Laden (feste `siteId`). Der Inhaber will *„nur wichtige Sachen zur Arbeit"* — jede Kachel muss eine **echte Ladentisch-Frage** beantworten. Alles andere (HR, Lohn, Finanz, Analytik, Verwaltung) bleibt bewusst draußen.

**Zwei Sichtbarkeitsebenen** (unverändert aus dem Fundament):

| Ebene | Trigger | Inhalt | Beispiel |
|---|---|---|---|
| **Board** | keine Anmeldung, Dauer-Anzeige | read-only, glanceable, **PII-arm & site-skopiert** | „5 Kundenwünsche offen", „Kühlschrank: 3 Lücken" |
| **Session** | nach PIN (server-geprüft, `kioskSessions/{sid}`) | Aktionen mit Mitarbeiter-Attribution, verschwindet beim Auto-Logout (90 s) | Stempeln, Krankmeldung, Wunsch quittieren |

**Drei Leitplanken (verbindlich):**

1. **Datensparsamkeit** — nichts Personenbezogenes/Sensibles auf ein Gerät, an dem sich niemand persönlich einloggt und an dem auch Kunden vorbeilaufen. Keine Löhne, keine EK-Preise/Margen, keine Umsätze, keine Kunden-PII aufs Board. **Grundlage:** §0-Overrides + die Feld-Whitelists in §5.
2. **Geräte-Konto ≠ Mitarbeiter** — das `role:kiosk`-Konto bleibt die einzige Firebase-Identität, **kein** Identitätswechsel beim Login. Sensible Writes laufen als Cloud-Function (Admin SDK *als* Session-Mitarbeiter). Leichte Writes laufen direkt unterm Geräte-Konto mit Mitarbeiter aus `sid` als Metadatum.
3. **Feste `siteId`** — jede Kachel liest/schreibt nur den **eigenen** Laden. Die `siteId` kommt aus `KioskDeviceStore.getSiteId()` (`lib/screens/kiosk/kiosk_screen.dart:62`), bei Callables serverseitig aus dem Geräte-Konto — **nie** aus dem Request-Payload.

---

## 2. Kachel-Katalog nach Bereich

Legende: **B** = Board (ohne Login) · **S** = Session (nach PIN) · Write-Pfad: *none* / *direct-device* (leichter Write unterm Geräte-Konto mit Feld-Whitelist) / *callable* (Cloud-Function *als* Mitarbeiter). Effort: S/M/L.

### 2.1 Zeit & Schicht

| Kachel | B/S | Read/Action | Quelle / Reuse | Write-Pfad | Effort | Inc. |
|---|---|---|---|---|---|---|
| Stempeln (Kommen/Gehen) *(gebaut, nur UX-Feinschliff)* | S | Action | `kiosk_clock_service.dart` → `FirestoreService.kioskClockPunch` → Callable `functions/index.js:1017`; Tile `_ClockTile` (`kiosk_screen.dart`); Status via `ZeitwirtschaftProvider` (`openEntry`/`isClockedIn`/`runningMinutes`) | callable | S | A1b |
| Heutige Schichten im Laden *(Wer arbeitet heute?)* | B | Read | **Projektion `kioskRoster`-analog** (§5 #2, nur `{name, startTime, endTime, siteId}`) — Board zeigt **nur Vornamen** (kundensichtbar, Entscheidung §9 #2); **nicht** direkt `shifts`, Client-Filter `siteId == Geräte-siteId` + heute | none | M | A2 |
| Meine nächste Schicht | S | Read | dieselbe Projektion, client-Filter `userId == sid.employeeId && startTime >= now`, `take(1)` | none | S | A2 |
| Wer fehlt heute *(genehmigte Abwesenheiten)* | S | Read | **Session-only** (nicht aufs kundensichtbare Board — Entscheidung §9 #2); **Read-Projektion `kioskAbsences/{siteId}` (§5 #7)**, nur `{name, startDate, endDate, type}` — **kein** Grund, **kein** direkter `absenceRequests`-Read (Rules verlangen `canManageShifts()`, `:717`; feldweise Beschneidung geht in Rules nicht) | none | M | A3 |
| Krankmeldung *(heute ausgefallen)* | S | Action | **neu:** Callable `kioskSubmitAbsence` (analog `kioskClockPunch`); portiert die *„Chef gibt frei"*-Logik aus `ScheduleProvider.submitAbsenceRequest` (`schedule_provider.dart:1411`) **serverseitig**; Typ auf `sickness`/`childSick` begrenzt | callable | L | A3 |

> **Warum Callable bei Krankmeldung:** Direkt-Write scheitert — `absenceRequests`-**create** (`firestore.rules:719–721`) verlangt `request.resource.data.userId == request.auth.uid`; das Geräte-Konto ist nicht der Mitarbeiter. Server setzt `userId = Session-Mitarbeiter`. **Wichtig (Aufwand):** die Schichtfreigabe (*„Chef gibt frei"*, Memory `krankmeldung-gibt-schicht-frei`) lebt heute **Client-seitig** in `ScheduleProvider.submitAbsenceRequest` — es gibt dafür **keine** bestehende Function. Sie wird im Callable **neu geschrieben** (nicht „gespiegelt"): serverseitig via Admin SDK die betroffene(n) `shifts` desselben Kalendertags des Mitarbeiters ermitteln und `status='cancelled'` + `userId` freiräumen (konkrete Felder in §5/§8 festlegen). Effort daher **L**.

### 2.2 Kühlschrank, Kundenwünsche & Feedback

| Kachel | B/S | Read/Action | Quelle / Reuse | Write-Pfad | Effort | Inc. |
|---|---|---|---|---|---|---|
| Kühlschrank nachfüllen (Soll-Ist-Alarm) *(gebaut)* | B | Read | `InventoryProvider.fridgeShortfalls({siteId})` (`inventory_provider.dart:457`) → `core/fridge_refill_shortfall.dart`; Tile `_FridgeTile` (`kiosk_screen.dart`), Top-6 | none | S | A1a |
| Nachgefüllt quittieren *(gebaut)* | S | Action | `InventoryProvider.refillFridge` (`inventory_provider.dart:1860`) → `FirestoreService.setFridgeStock`; Button in `_FridgeRow` (`kiosk_screen.dart`) | direct-device | S | A1a |
| Offene Kundenwünsche *(gebaut)* | B | Read | `FirestoreService.watchCustomerWishes(orgId, limit:300)`; client-Filter `status.isOpen + storeName==siteName`; Tile `_WishesTile` — **nur** `wishText`/Kategorie/Menge/`referenceCode`, **kein** `customerName`/`customerContact` | none | S | A1a |
| Wunsch als gesehen/erledigt quittieren | S | Action | **neu:** Callable `kioskUpdateWishStatus(sid, wishId, status)`; heutiger [`FirestoreService.updateCustomerWishStatus`](../lib/services/firestore_service.dart#L1925)-Pfad verlangt `canManageInventory` (`firestore.rules:1151–1153`, Read `:1150`), das dem Geräte-Konto fehlt; Status ∈ {gesehen, erledigt}, **kein** Ablehnen/Löschen | callable | M | A3 |

### 2.3 Scanner & Kasse (OktoPOS)

| Kachel | B/S | Read/Action | Quelle / Reuse | Write-Pfad | Effort | Inc. |
|---|---|---|---|---|---|---|
| Preis-Scanner *(Was kostet das?)* | S | Read | `InventoryProvider.productByBarcode(barcode, siteId:)` (`inventory_provider.dart:239`) + `BarcodeScanner`-Code-Stream (`lib/services/barcode_scanner.dart`, Seam wie `scanner_screen.dart`); zeigt **nur** Name + `sellingPriceCents` (+ optional Bestand), **nie** `purchasePriceCents`/Marge (§6.2) | none | M | A1b |
| Bestand prüfen *(Ist der Artikel da?)* | S | Read | gleicher Scan-Treffer → `Product.currentStock`/`needsReorder`; Ampel genug/knapp/leer, keine Warenwerte | none | S | A1b |
| Schnellwahl häufige Artikel | S | Read | `InventoryProvider.frequentlyOrderedProducts(siteId:, limit:)` (`inventory_provider.dart:555`), client-seitig aus Bestellhistorie; Chip-Leiste für Artikel ohne (lesbaren) Barcode | none | S | A2 |
| Kassenabgleich-Status *(Warnsignal)* | B | Read | **neu (server):** `runOktoposSync` (`functions/index.js:3025`) / `oktoposNightlySync` (`:2920`) schreibt schlankes `config/oktoposSyncStatus` (`lastRunAt`, `ok`, DE-`message`, `siteId`) via Admin SDK; Board liest **nur** dieses Status-Doc, **nie** `posReceipts` | callable (server-schreibt) | M | A3 |

### 2.4 Mitteilungen & Laden-To-Dos

| Kachel | B/S | Read/Action | Quelle / Reuse | Write-Pfad | Effort | Inc. |
|---|---|---|---|---|---|---|
| Laden-To-Dos *(gebaut)* | B | Read | `StoreTaskProvider.openStoreTasksForSite/openStoreTaskCount` (`store_task_provider.dart:87/92`); Tile `_StoreTasksTile` (`kiosk_screen.dart`), `take(6)` | none | S | A1a |
| Laden-To-Do abhaken *(gebaut)* | S | Action | `StoreTaskProvider.markDoneForSite(task, siteId, {employeeId, employeeName})` (`store_task_provider.dart:169`); schmaler Rule-Pfad `hasOnly(['completedBySite','updatedAt'])` (`firestore.rules:881–885`) | direct-device | S | A1a |
| Mitteilung der Leitung *(Aushang)* | B | Read | **neu (Greenfield):** Model `StoreAnnouncement` + Collection `organizations/{orgId}/announcements` + `AnnouncementProvider`; Editor analog `store_task_editor_sheet.dart` mit „für alle Läden"-Toggle (`siteId==null` = Broadcast, wie `StoreTask`); Ablaufdatum (`expiresAt`) | none | M | A3 |

### 2.5 Team / Anwesenheit

| Kachel | B/S | Read/Action | Quelle / Reuse | Write-Pfad | Effort | Inc. |
|---|---|---|---|---|---|---|
| Wer ist gerade im Dienst | B | Read | **neu:** schmale server-gepflegte Projektion `kioskPresence/{siteId}` (nur `uid`+Name+Foto+`istImDienst`+`at`), gepflegt von `kioskBeginSession`/`kioskClockPunch`; Namensquelle bleibt `kioskRoster` (`firestore.rules:904–906`), **kein** `users/{uid}`-Read, **keine** `clockEntries`-Details | none (Server schreibt Projektion) | M | A2 |

### 2.6 Warenwirtschaft & Bestellungen

| Kachel | B/S | Read/Action | Quelle / Reuse (file:line) | Write-Pfad | Effort | Inc. |
|---|---|---|---|---|---|---|
| Niedrigbestand / Nachbestellen | B | Read | **Bugfix:** [`_HintsTile`](../lib/screens/kiosk/kiosk_screen.dart#L908) filtert `p.isActive && p.needsReorder` (`:915–917`) und **ignoriert das bereits durchgereichte `siteId`** (`:909`) → auf [`InventoryProvider.lowStockProducts({siteId})`](../lib/providers/inventory_provider.dart#L275) umstellen; Top-3 + „+ N weitere". `needsReorder` = [`Product`-Getter](../lib/models/product.dart#L113) | none | S | A2 |
| Fällige Kundenbestellungen *(nicht vorbereitet)* | B | Read | [`InventoryProvider.ordersDueSoonNotPrepared({withinDays, siteId})`](../lib/providers/inventory_provider.dart#L352) (Default `withinDays:2`); nur Kundenkürzel + Abholdatum + `itemCount`, **kein** `customerContact`/Adresse | none | M | A2 |
| Kundenbestellung als vorbereitet melden | S | Action | **neu:** Callable `kioskMarkOrderPrepared` (setzt `preparedAt`+`updatedAt`+`preparedByUid` via Admin SDK). **Nicht** über [`markCustomerOrderPrepared`](../lib/providers/inventory_provider.dart#L2317)/`saveCustomerOrder` — s. Hinweis | callable | M | A3 |
| Nachbestell-Vormerkung *(„X ist knapp")* | S | Action | [`InventoryProvider.addToCart`](../lib/providers/inventory_provider.dart#L2395) → geteilter Bestellkorb `orderCarts/{siteId}` (`OrderListKind.cart`); Rule erlaubt **jedem** sameOrg-User Feld-Allowlist-Write (`firestore.rules:1280–1291`, **kein** `canManageInventory`) | direct-device | M | A3 |
| Preis / Bestand am Artikel scannen | S | Read | → **s. §2.3** (Preis-Scanner + Bestand prüfen; EK/Marge ausgeblendet, §6.2) | none | — | A1b |
| **MHD-/Ablauf-Warnung** *(Getränke/Süßware)* | B | Read | **neu — eigenes Plan [`plan/mhd-ablauf-warnung.md`](mhd-ablauf-warnung.md):** pure `computeExpiryWarnings` (Vorbild `computeFridgeShortfalls`, `fridge_refill_shortfall.dart:51`); Board zeigt „N Artikel laufen in ≤ 3 Tagen ab" (Ampel rot=abgelaufen, orange ≤ 3 Tage), site-gefiltert | none | M | s. MHD-Plan |
| **MHD erfassen / erledigt abhaken** | S | Action | **neu (MHD-Plan):** MHD beim Wareneingang per Scan erfassen (Datum + Menge); „erledigt: abverkauft/reduziert/entsorgt" abhaken | direct-device/callable | M | s. MHD-Plan |

> **MHD-/Ablauf-Warnung (Inhaber-Priorität „sehr wichtig").** Getränke & Süßwaren bekommen ein Ablaufdatum; 2–3 Tage vor Ablauf warnt eine Kachel auf **allen** Laden-Tablets **und** die App (In-App-Inbox + Push). Vollständiges Design im eigenen Dokument [`plan/mhd-ablauf-warnung.md`](mhd-ablauf-warnung.md) — hier nur die Kiosk-Kachel. Board-Kachel ist ein reiner Client-Stream (kein Server nötig); die App-/Push-Zustellung ist der Server-Teil des MHD-Plans.

> **„Bestellungen aufgeben" — Vormerkung statt echter Bestellung.** Echtes Bestellen ([`savePurchaseOrder`](../lib/providers/inventory_provider.dart#L2023), `PurchaseOrderStatus.ordered`) verlangt `canManageInventory()` (`firestore.rules:1121`-Kontext) und ist eine Beschaffungs-/Kostenentscheidung — bewusst **nicht** aufs geteilte Gerät. **Empfehlung: „Nachbestell-Vormerkung"** über den ohnehin für alle aktiven Mitarbeiter offenen geteilten Bestellkorb (`orderCarts/{siteId}`, Feld-Allowlist `firestore.rules:1280–1291`): der Mitarbeiter merkt „X ist knapp" vor, der Manager löst später im App-Tab die echte Bestellung aus. Der Kiosk-Scanner bleibt so **read-only für Bestand/Preis** und schreibt nur die harmlose Vormerkung. Eine server-geprüfte `kioskSubmitOrder`-Callable ist **machbar, aber vorerst abgelehnt** (§9 #8).

> **`kioskMarkOrderPrepared` = Callable, keine enge Rule.** `customerOrders`-create/update verlangt `canManageInventory()` (`firestore.rules:1133–1134`), das dem Geräte-Konto fehlt. Eine schmale Rule `hasOnly(['preparedAt','updatedAt'])` (analog `storeTasks.completedBySite`, `:881`) wäre technisch möglich, **verlöre aber die Mitarbeiter-Attribution** (Write liefe unterm Geräte-Konto). Der Callable setzt `preparedByUid` serverseitig aus `sid`. **Wichtig:** der App-Pfad [`markCustomerOrderPrepared`](../lib/providers/inventory_provider.dart#L2317) delegiert an `saveCustomerOrder`; dessen Umsatzbuchung [`_bookCustomerOrderRevenueIfNeeded`](../lib/providers/inventory_provider.dart#L119) feuert **nur** beim Übergang → `pickedUp` (nicht bei `prepared`) — der Kiosk geht dennoch **nie** über `saveCustomerOrder`. Er schreibt ausschließlich `preparedAt`/`updatedAt`/`preparedByUid` (neues Feld `preparedByUid` an `CustomerOrder` → 6 Serialisierungs-Stellen, Kopplung #1).

**Bewusst ausgeschlossen aus diesem Bereich** (ergänzt §3): Wareneingang/-abgang buchen · Inventur ([`recordStocktake`](../lib/providers/inventory_provider.dart#L1839)) · Umlagerung ([`transferStock`](../lib/providers/inventory_provider.dart#L1959)) · Preis ändern per Scan ([`updateProductPrices`](../lib/providers/inventory_provider.dart#L1011)) · Preishistorie ([`priceHistoryFor`](../lib/providers/inventory_provider.dart#L1100), enthält EK) · Bestellungen auslösen/stornieren · Kundenbestellung anlegen/abholen/stornieren · Warenwert/Marge · Reorder-/Sortiments-Analytik ([`suggestReorderLevels`](../lib/providers/inventory_provider.dart#L1226), [`loadAssortmentAnalysis`](../lib/providers/inventory_provider.dart#L1384)) · OktoPOS manuell auslösen. Alle brauchen `canManageInventory` (hat/bekommt das Geräte-Konto **nicht**) oder sind Analytik mit EK/Umsatz/Kapital — kein Ladentisch-Bezug, Manipulations-/Datensparsamkeits-Risiko am geteilten Gerät.

---

## 3. Bewusst ausgeschlossen (Datensparsamkeit)

Diese Dinge kommen **nicht** aufs Tablet. Rechte Spalte = `firestore.rules`-Konsequenz für `role:kiosk` **nach** den §0-Overrides.

| Ausgeschlossen | Begründung | Rules-Konsequenz für `role:kiosk` |
|---|---|---|
| **Kundenfeedback / Beschwerden** | Sensibel (Reklamationen über Personal/Qualität), Manager-only Eingang | `customerFeedback`-Read ist `canManageFeedback()` → automatisch verweigert; Scope **nicht** öffnen |
| **Kontakte** (Kunden/Lieferanten ansehen/bearbeiten) | Kunden-PII auf geteiltem Gerät | **OFFENER PUNKT:** `contacts`-Read läuft heute über `sameOrg` (`firestore.rules:1343`) → Geräte-Konto **kann heute** die volle Kontaktliste lesen. **Muss** für `role:kiosk` verweigert werden (§6) |
| **Kontakt-Aktivitäten erfassen** | braucht `canManageContacts`, kein Ladentisch-Bezug | kein Schreibrecht nötig — nie referenzieren |
| **Preishistorie / EK-VK-Verlauf** | enthält EK-Preise (Betriebsgeheimnis) | `products.purchasePriceCents` / `priceHistory` nie aufs Gerät (§6.2) |
| **Bestandsbewegungs-Log** (`stockMovements`) | Wareneingänge/-abgänge/Korrekturen = internes Audit, kein Ladentisch-Bezug | **OFFENER PUNKT:** `stockMovements`-Read ist heute `sameOrg` (`firestore.rules:1354`) → Geräte-Konto liest es heute mit. **Muss** für `role:kiosk` verweigert werden (§6) |
| **Wareneingang/-abgang buchen, Inventur, Preis ändern per Scan** | schreibende Warenwirtschaft, Manipulationsrisiko am geteilten Gerät | braucht `canManageInventory` (`firestore.rules:1078`-Kontext) → Geräte-Konto hat es **nicht** und soll es **nicht** bekommen; Kiosk-Scanner strikt read-only |
| **OktoPOS manuell auslösen / PosReceipts einsehen** | Secret-Manager/Outbound; Belege = PII + Umsatz | `syncOktoposTransactions` (`functions/index.js:2881`) ist `assertAdmin`; `posReceipts`-Read = Admin/teamlead (`firestore.rules:1401`-Kontext) → verweigert |
| **Bestand-Insights, Sortiment, Kassierer-Anomalie, Tagesabschluss, Bestellauswertung, Monatsbericht** | Analytik/Buchhaltung/Leistungskontrolle; EK/Umsatz/DATEV; z. T. mitbestimmungspflichtig | admin-only Screens; nie am `/arbeitsmodus`-Gate erreichbar; Reads für `role:kiosk` verweigert |
| **HR-Stammakte, Lohn, Steuer/SV, Sollzeit, Urlaubskonto** (`employeeProfiles`, `payrollRecords:910`, `payrollProfiles`, `sollzeitProfiles`, `payrollConfig`, `employeeChildren`) | vertrauliche Personen-/Vergütungsdaten | alle `isAdmin() && sameOrg()` → automatisch verweigert; **niemals** per `sameOrg` für Kiosk lockern |
| **Stundenkonto / Monatsabschluss / Arbeitszeit-Statistik des Mitarbeiters** | Lohndaten; Kernprinzip: Mitarbeiter loggt sich nie mit eigener Identität ein | `clockEntries`-Vollsicht (`firestore.rules:575`-Kontext) verlangt `canManageShifts()` → **nach §0-Overrides** verweigert (vorher NICHT!); `zeitkontoSnapshots` Manager-only; gehört aufs eigene Handy |
| **Schichtplan-Editor / Auto-Verteilung / Schichttausch** | Planungs-/Koordinationswerkzeug; Fremd-Tauschanfragen auf geteiltem Gerät | `shifts`-Write = `canManageShifts()` → Geräte-Konto hat es nicht; nur **Read** (Name+Zeit) über schmale Projektion |
| **Urlaubskonto/Resturlaub, ungenehmigte/abgelehnte Anträge, Schichttausch-Gutschriften** | personenbezogen; nur genehmigte, grundlose Abwesenheit darf aufs Board | Board zeigt bewusst nur `status==approved`, ohne `reason` (über `kioskAbsences`-Projektion) |
| **Wer ist gerade eingestempelt (org-weite `clockEntries`)** | HR-nahe Felder, Manager-only | ersetzt durch schmale `kioskPresence`-Projektion (nur Name + rein/raus) |
| **Team-Verwaltung, Settings, Notification-Prefs, Auth-Screen, Audit-Log** | Verwaltung/persönliche Einstellungen/Login — kein Ladenkontext | admin-only bzw. Geräte-Konto hat kein persönliches Profil; `_gateRedirect` pinnt Kiosk auf `/arbeitsmodus` |
| **Wunsch → echte Bestellung konvertieren, Wunsch ablehnen/löschen, Nachfüllliste bearbeiten** | Verwaltungs-/Beschaffungs-/destruktive Aktionen | brauchen `canManageInventory` → bleiben im App-Tab; Kiosk kennt nur den harmlosen Vorwärts-Status |
| **WorkTasks (individuelle Aufträge, `assignedUserId`)** | persönlicher HR-Auftrag ≠ Laden-To-Do (Broadcast) | am Kiosk erscheinen **nur** `storeTasks` (`firestore.rules:876–887`), nie `workTasks` |

---

## 4. Kachel-Registry & Architektur

**Erweiterungspunkt = die Board-Liste** `tiles` in `_KioskBoard.build` ([`kiosk_screen.dart:437`](../lib/screens/kiosk/kiosk_screen.dart#L437)), gerendert via `_KioskTile` ([:473](../lib/screens/kiosk/kiosk_screen.dart#L473)) in einem **eigenen** `LayoutBuilder`+`Wrap` mit hartkodierten Breakpoints (`>=1100→3`, `>=720→2`, sonst 1; [:445–468](../lib/screens/kiosk/kiosk_screen.dart#L445)) — **nicht** `AdaptiveCardGrid` (Vereinheitlichung s. §4a). Vorbild-Tiles: `_ClockTile`, `_StoreTasksTile`, `_FridgeTile`, `_WishesTile`, `_HintsTile`.

**Ist-Stand (verifiziert):** `tiles` ist eine **flache `List<Widget>` ohne board/session-Metadatum** ([:437–443](../lib/screens/kiosk/kiosk_screen.dart#L437)). Board- vs. Session-Verhalten steckt heute **innerhalb** jeder Tile (z. B. `_FridgeTile.canRefill = controller.employee != null` [:761](../lib/screens/kiosk/kiosk_screen.dart#L761), `_StoreTasksTile.canCheck` [:677](../lib/screens/kiosk/kiosk_screen.dart#L677)). Reine Session-Kacheln (Preis-Scan, „Meine nächste Schicht") gibt es noch nicht — sobald sie kommen, würde die flache Liste sie **auch ohne Login** rendern. Deshalb **jetzt** minimalinvasiv eine Spec-Liste einführen.

**Minimalinvasiver Vorschlag — `_KioskTileSpec` (eine Datei, kein neues Framework):**

```dart
enum _KioskVisibility { board, session } // session: nur wenn employee != null

class _KioskTileSpec {
  const _KioskTileSpec({required this.visibility, required this.builder});
  final _KioskVisibility visibility;
  final WidgetBuilder builder; // baut die bestehende _KioskTile
}
```

`_KioskBoard.build` filtert dann `specs.where((s) => s.visibility == board || hasSession)` (mit `hasSession = context.watch<KioskController>().employee != null`). „Aus jedem Bereich eine Kachel ergänzen" = **eine Zeile** in `specs`, mit expliziter board/session-Entscheidung an genau **einer** Stelle statt verstreut in jeder Tile. Beim 90-s-Auto-Logout (`KioskController.logout`, [`kiosk_controller.dart:50`](../lib/screens/kiosk/kiosk_controller.dart#L50)) blenden Session-Kacheln automatisch aus — **nichts Personenbezogenes bleibt stehen**. Jede Session-Aktion ruft weiter `controller.touch()` (Timer-Reset, verifiziert `_FridgeRow.onRefill` [:777](../lib/screens/kiosk/kiosk_screen.dart#L777)). `severity`/Badge bleibt Sache der jeweiligen `_KioskTile` (`badge`/`badgeColor`, [:486](../lib/screens/kiosk/kiosk_screen.dart#L486)) — bewusst **kein** Spec-Feld (kein Over-Engineering). `_ClockTile` bleibt `board` (zeigt ohne Login den „Anmelden"-Hinweis, [:622](../lib/screens/kiosk/kiosk_screen.dart#L622)).

**`_HintsTile`-Bugfix (präzise).** Das Widget bekommt `siteId` **bereits durchgereicht** (`final String? siteId;`), **ignoriert** es aber im Filter (`p.isActive && p.needsReorder`) → auf `InventoryProvider.lowStockProducts({siteId})` umstellen. Kein neuer Parameter, nur den vorhandenen nutzen.

**Feste Tablet-`siteId`.** Jede neue Kachel **muss** die `siteId` aus `KioskDeviceStore.getSiteId()` (`kiosk_screen.dart:62`) an ihre Provider-Hooks durchreichen (`ordersDueSoonNotPrepared`, `lowStockProducts`, `productByBarcode`, `fridgeShortfalls`, …).

**Reuse-Prinzip & cloud-only-Kiosk.** Board-Reads laufen über die schon gestreamten Provider-Listen (`_products`, `watchCustomerWishes`) → umgehen den Lazy-Cloud-Repo-Footgun. Der Kiosk-Build ist **cloud-only** (`persistenceEnabled:false`, **kein** SharedPreferences-Mirror). Alle neuen Kiosk-Provider (`AnnouncementProvider`) lösen ihr Cloud-Repo **lazy** auf und werden **bewusst nicht** in `DatabaseService` registriert (kein lokaler Persistenz-Pfad im Kiosk). Für den `APP_DISABLE_AUTH`-Demo-/Offline-Lauf liefern die neuen Provider **leere Listen / Demo-Stubs** statt eines früh aufgelösten Cloud-Repos — sonst rote Seite (Memory `provider-lazy-cloud-repo`).

**Voller Provider-Chain.** `/arbeitsmodus` ist eine **Gate-Route in der Shell** — `ScheduleProvider`, `InventoryProvider`, `StoreTaskProvider`, `ZeitwirtschaftProvider` hängen bereits in der Kette. Ein neuer `AnnouncementProvider` (A3) wird **nach** Auth/Storage/Audit in `main.dart` eingefügt (Kopplung #4).

---

## 4a. Tablet-Anzeige & UX (geteiltes Board)

> **Regelhierarchie:** Barrierefreiheit > Performance > Konsistenz > Layout.
> Das Board ist eine **Dauer-Anzeige aus 2–3 m Distanz** auf einem fest
> installierten Tablet (Querformat) — nicht ein Handy-Screen aus 30 cm. Alle
> Empfehlungen sind an [`kiosk_screen.dart`](../lib/screens/kiosk/kiosk_screen.dart) gebunden.

### 4a.0 Ist-Stand (verifiziert)
- **Always-On ist gebaut:** `_enableAlwaysOn()` ([:87](../lib/screens/kiosk/kiosk_screen.dart#L87)) ruft `WakelockPlus.enable()` + `SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)`, im `dispose` zurückgesetzt ([:96](../lib/screens/kiosk/kiosk_screen.dart#L96)). Best-effort, No-op auf Web/Desktop.
- **Kein Landscape-Lock:** `SystemChrome.setPreferredOrientations(...)` kommt im Kiosk **nicht** vor (nur `setEnabledSystemUIMode`). Fehlt.
- **Kein Offline-/Konnektivitäts-Zustand:** weder Banner „zuletzt aktualisiert" noch Konnektivitäts-Indikator. `_WishesTile` ([:849](../lib/screens/kiosk/kiosk_screen.dart#L849)) zeigt ohne Netz still eine leere Liste.
- **Sekundentakt-Timer:** `Timer.periodic(Duration(seconds: 1), …)` mit `setState` auf dem **ganzen** `KioskScreen` ([:54](../lib/screens/kiosk/kiosk_screen.dart#L54)) → rebuildet jede Sekunde die gesamte Board-Subtree (Performance/Burn-in-relevant).
- **Layout:** `_KioskBoard` nutzt **nicht** `AdaptiveCardGrid`, sondern ein eigenes `LayoutBuilder`+`Wrap` mit hartkodierten Breakpoints (`>=1100→3`, `>=720→2`, sonst 1; [:445–468](../lib/screens/kiosk/kiosk_screen.dart#L445)).

### 4a.1 Checkliste (priorisiert; Effort S/M/L · Increment)

**Barrierefreiheit & Glanceability (KRITISCH — zuerst)**
- [ ] **Zähler-Badges aus Distanz lesbar.** Heute ist der Zähler ein `labelLarge`-Text in einer 10×4-Pill ([`_KioskTile`:507–523](../lib/screens/kiosk/kiosk_screen.dart#L507)) — aus 2 m unlesbar. Auf `displaySmall`/`headlineMedium` (36–45 sp) in einem größeren, kontraststarken Chip; Ampel `0 → grün (appColors.success)`, `>0 → severity-Farbe`. — **S · A1a**
- [ ] **Severity durchgängig über `context.appColors`, nie hardcoden.** Verifiziert: `_FridgeRow` mappt `empty→colorScheme.error`, `warehouseLow→appColors.warning`, `refill→appColors.info` ([:801–805](../lib/screens/kiosk/kiosk_screen.dart#L801)); `_StoreTasksTile`/`_HintsTile` nutzen `appColors.warning` ([:683](../lib/screens/kiosk/kiosk_screen.dart#L683)/[:923](../lib/screens/kiosk/kiosk_screen.dart#L923)). Beim Vergrößern die Farbrollen beibehalten (`success` existiert in `AppThemeColors`, im Kiosk heute ungenutzt). — **S · A1a**
- [ ] **Touch-Ziele auf Tablet-Distanz.** `_NumPad`-Tasten 84×64 dp ([:1161](../lib/screens/kiosk/kiosk_screen.dart#L1161)) — grenzwertig fürs stehende Bedienen → ≥ 72 dp + `headlineMedium`-Ziffern. PIN-Punkte 18×18 ([:1124](../lib/screens/kiosk/kiosk_screen.dart#L1124)) → ≥ 24. Aktionsbuttons Mindesthöhe 56 dp. — **S · A1b**
- [ ] **Bestätigungs-Overlay für Session-Aktionen.** Stempeln/Nachfüllen/Abhaken feuern heute ohne Rückmeldung (`_toggle` [:580](../lib/screens/kiosk/kiosk_screen.dart#L580), `onRefill` [:776](../lib/screens/kiosk/kiosk_screen.dart#L776)). Kurzes, großflächiges Erfolgs-Overlay („✓ Kommen 08:14 — Max", 2 s, `appColors.successContainer`) — auf geteiltem Gerät wichtig. — **M · A1b**

**Offline-degradiert (KRITISCH — Kiosk ist cloud-only)**
- [ ] **Konnektivitäts-Banner + „zuletzt aktualisiert".** Bei Netzverlust zeigt `_WishesTile` still leere Listen — leer ≠ „keine Wünsche". Schmales `appColors.warning`-Banner unter `_KioskTopBar` ([:159](../lib/screens/kiosk/kiosk_screen.dart#L159)): „Offline — Stand HH:mm". `connectivity_plus` + entprelltes Online-Enum (Skill `flutter-offline-modus`); **keine roten/leeren Kacheln**, letzten Stand halten + dimmen. — **M · A2**
- [ ] **Degraded statt leer.** Board-Kacheln unterscheiden „geladen & leer" (grün) von „nie geladen / offline" (neutraler Platzhalter). `_KioskEmpty` ([:539](../lib/screens/kiosk/kiosk_screen.dart#L539)) um `degraded`-Zustand erweitern. — **S · A2**

**Always-On / Burn-in / Ruhemodus (HOCH)**
- [ ] **Landscape-Lock ergänzen.** In `_enableAlwaysOn()` ([:87](../lib/screens/kiosk/kiosk_screen.dart#L87)) `setPreferredOrientations([landscapeLeft, landscapeRight])`, im `_disableAlwaysOn()` ([:96](../lib/screens/kiosk/kiosk_screen.dart#L96)) auf `[]` zurück. — **S · A1b**
- [ ] **Burn-in-Gegenmaßnahme (Pixel-Shift).** Bei Board-Leerlauf (kein `employee`) alle ~60 s das Board um ±2–4 px verschieben (`AnimatedPadding` um den `_KioskBoard`-`Expanded` [:170](../lib/screens/kiosk/kiosk_screen.dart#L170)). — **M · A2**
- [ ] **Sekunden-Rebuild eindämmen.** Der 1-s-`setState` ([:54](../lib/screens/kiosk/kiosk_screen.dart#L54)) rebuildet das ganze Board pro Sekunde. Board-Uhr auf **Minutentakt**; nur der Auto-Logout-Countdown im `_ActiveEmployeeChip` ([:334](../lib/screens/kiosk/kiosk_screen.dart#L334)) braucht Sekunden → in ein isoliertes Widget mit eigenem Timer ziehen (Rebuild-Scoping). — **M · A2**
- [ ] **Nacht-/Ruhemodus bei Ladenschluss.** `isNearClosing(site, now)` existiert ([`fridge_refill_shortfall.dart:87`](../lib/core/fridge_refill_shortfall.dart#L87), pure) + `SiteDefinition.weekdayHours`. Außerhalb der Öffnungszeiten dunkle, dimmende „Geschlossen"-Ansicht (nur große Uhr + Ladenname) — spart OLED/Strom, **Datensparsamkeit-Bonus:** keine Zähler im nächtlichen Schaufenster. — **M · A3**

**Layout / Adaptive (HOCH)**
- [ ] **Board-Grid auf `AdaptiveCardGrid` vereinheitlichen.** Das hartkodierte `LayoutBuilder`+`Wrap` ([:445–468](../lib/screens/kiosk/kiosk_screen.dart#L445)) durch `AdaptiveCardGrid(minItemWidth: 340, …)` ([`responsive_layout.dart:63`](../lib/widgets/responsive_layout.dart#L63)) ersetzen. **Achtung:** `gridColumns` clampt auf max 4 ([:55](../lib/widgets/responsive_layout.dart#L55)); für sehr breite Tablets Cap prüfen. — **M · A2**
- [ ] **Split-View bewusst ignorieren.** Kiosk läuft Vollbild (immersiveSticky + Landscape-Lock); Kacheln brechen bei schmaler Breite auf 1 Spalte (schon durch `SizedBox(width: itemWidth)` gedeckt). — **S · A2**

**Session-Trennung (HOCH — Datensparsamkeit + UX)**
- [ ] **Session-Kacheln erst nach Login rendern, beim Logout sofort weg** — via `visibility`-Feld der Registry (§4). Reine Session-Kacheln (Preis-Scan, „Meine nächste Schicht") **gar nicht** rendern, solange `employee == null`; beim 90-s-Auto-Logout (`KioskController.logout` [`kiosk_controller.dart:50`](../lib/screens/kiosk/kiosk_controller.dart#L50)) verschwinden sie automatisch. — **M · A2**

---

## 5. Neue Datenmodelle / Collections & Indizes

Nur was **wirklich** neu ist. Zwei-Serialisierungs-Regel gilt für jedes neue Model-Feld = 6 Stellen (`toFirestoreMap` camelCase / `fromFirestore` / `toMap` snake_case / `fromMap` / `copyWith` (+`clearX`) / ggf. `functions/index.js` snake_case bei Callable).

| # | Was | Art | Serialisierung / Feld-Whitelist | Index |
|---|---|---|---|---|
| 1 | `StoreAnnouncement` + Collection `organizations/{orgId}/announcements` (Aushang) | **neues Model + Collection** | volle 6 Stellen; Vorlage `StoreTask` (`store_task.dart`), inkl. optionalem `siteId==null`=Broadcast + `expiresAt` (nullable → `clearX`) | nur falls Query `where(siteId)+orderBy(createdAt/expiresAt)`; bei In-Memory-Filter des vollen Streams **kein** Index |
| 2 | `kioskShifts/{siteId}` (Heute-im-Laden-Projektion) **oder** Read-Callable | **neue schmale Projektion**, server-gepflegt | Whitelist `{name, startTime, endTime, siteId, userId}` — **kein** `payRelevant`/`ruleSetId`/Notizen. Server (`upsertShiftBatch`/`publishShiftBatch`) pflegt die Projektion mit; Client `read:sameOrg / write:false` | Doc-ID = `siteId`, In-Memory-Filter → **kein** Composite-Index |
| 3 | `kioskPresence/{siteId}` (Anwesenheits-Projektion) | **neue schmale Collection**, server-gepflegt | Whitelist `{uid, name, photoUrl, istImDienst, at}`; nur `kioskBeginSession`/`kioskClockPunch` schreiben; Client `read:sameOrg / write:false` | Doc-ID = `siteId` → Punkt-Read, **kein** Index |
| 4 | `config/oktoposSyncStatus` (Kassenabgleich-Status) | **leichtes Feld-Set im config-Singleton** (kein Model) | nur serverseitig geschrieben (`{lastRunAt, ok, message, siteId}`); Client-Read über generischen `config/{configId}`-Block (`sameOrg`) | **kein** Index |
| 5 | Callable `kioskSubmitAbsence` (Krankmeldung) | **neue Cloud-Function**, kein Model | nutzt `AbsenceRequest`-Schema, **snake_case**-Payload; setzt `userId` serverseitig aus `sid`; **portiert** die Schichtfreigabe (s. §8.3) | — |
| 6 | Callable `kioskUpdateWishStatus` (Wunsch-Status) | **neue Cloud-Function**, kein Model | snake_case-Payload; App-Pfad [`FirestoreService.updateCustomerWishStatus`](../lib/services/firestore_service.dart#L1925). **`CustomerWishStatus` serialisiert deutsche `value`-Strings** `neu/gesehen/erledigt/abgelehnt` (`customer_wish.dart:39–48`) — Callable schreibt diese, nicht die Dart-Namen | — |
| 7 | `kioskAbsences/{siteId}` (Wer-fehlt-Projektion) **oder** Read-Callable | **neue schmale Projektion**, server-gepflegt | Whitelist `{name, startDate, endDate, type}` — **explizit ohne** `reason`/`approvedByUid`; nur `status==approved`; gepflegt beim Genehmigen bzw. via `kioskSubmitAbsence`; Client `read:sameOrg / write:false` | Doc-ID = `siteId` → Punkt-Read, **kein** Index |
| 8 | Callable `kioskMarkOrderPrepared` (Bestellung vorbereitet) | **neue Cloud-Function** | setzt `preparedAt`/`updatedAt`/`preparedByUid` via Admin SDK; **nicht** über `saveCustomerOrder` | — |

> **Projektionen #2/#3/#7 sind der Kern der Datensparsamkeit.** Firestore-Rules können **nicht feldweise** beschneiden — deshalb liest das Board **nie** `shifts`/`absenceRequests`/`clockEntries`/`users` direkt, sondern immer eine server-gepflegte, whitelisted Projektion. Das ist konsistent mit der `kioskRoster`-Entscheidung des Fundaments (`firestore.rules:904`).

**Composite-Indizes (nur falls serverseitige Aggregation kommt):** Reine Board-Reads brauchen **keinen** neuen Index. Zwei potenzielle Kandidaten, **falls** die Kacheln „Heute im Laden" (Beleg-Zählung) oder „Ladenhüter-Tipp" doch als server-aggregierende Callables gebaut werden (aktuell **nicht** priorisiert, s. §9):
- `posReceipts`: `siteId` + `businessDay`/`transactionDate`.
- `stockMovements`: `siteId` + `createdAt`.
Beide dann in `firestore.indexes.json` ergänzen **und deployen** (sonst Laufzeitfehler).

---

## 6. Security & Datensparsamkeit

**`role:kiosk` ist ein Geräte-Konto, kein `UserRole`-Enum-Wert** (`app_user.dart` kennt nur `admin/teamlead/employee`). Sein Read-Scope entsteht heute allein über `sameOrg` **plus** den `isActiveUser()`-Default der drei View-Permissions — **genau das** wird durch §0 stillgelegt.

**6.1 Kein neuer `isKiosk()`-Zweig für `shifts`.** Verifiziert: `shifts`-Read (`firestore.rules:702–703`) ist `sameOrg && (canManageShifts() || canViewSchedule())`. Nach §0 (`canViewSchedule:false`) liest das Geräte-Konto `shifts` **nicht mehr** direkt — es liest die Projektion `kioskShifts/{siteId}` (§5 #2). Ein zusätzlicher `isKiosk()`-Read-Zweig für `shifts` ist damit **überflüssig** und würde die Feldbeschneidung (ganzes `Shift`-Doc leserbar) gerade wieder aufreißen. **Verworfen.**

**6.2 `products`-EK-Leak — konsequent lösen, nicht nur UI.** `products`-Read ist `sameOrg` (`firestore.rules:1078`) und **nicht feldweise** begrenzbar. Reine UI-Ausblendung ist auf einem geteilten, potenziell auslesbaren Gerät schwach (der volle `Product`-Doc inkl. `purchasePriceCents` liegt im Wire/Cache). **Zwei zulässige Wege — Inhaber entscheidet (§9):**
- **(a) schmale Projektion** `kioskProducts/{...}` (nur `{name, sellingPriceCents, currentStock, barcode, siteScope}`), analog `kioskRoster` — sauber datensparsam, aber Server-Pflege für den Produktkatalog nötig.
- **(b) Restrisiko akzeptieren:** `products` bleibt `sameOrg`-lesbar, EK wird nur UI-seitig nie gerendert; dokumentiert akzeptiert („Online-Wired, Blaze, kein Offline-Dump"). Preishistorie nie laden.
Bis zur Entscheidung gilt **(b)** als Interim, **(a)** ist die Ziel-Empfehlung, wenn EK als echtes Betriebsgeheimnis behandelt werden soll.

**6.3 Zwei offene Deny-Punkte (unabhängig von neuen Kacheln, jetzt fixen):**
1. **`contacts`-Read** über `sameOrg` (`firestore.rules:1343`) → `role:kiosk` **verweigern** (oder später auf supplier-only einschränken, wenn ein Lieferanten-Tile kommt).
2. **`stockMovements`-Read** über `sameOrg` (`firestore.rules:1354`) → `role:kiosk` **verweigern** (Bestandsbewegungs-Audit gehört nicht aufs Tablet).
Beides braucht einen `isKiosk()`-Ausschluss in den jeweiligen Read-Zweigen **oder** — konsistent mit §0 — greift bereits, wenn diese Collections statt `sameOrg` ein View-/Manage-Recht verlangen. Da sie heute reines `sameOrg` sind, ist hier ein **`&& !isKiosk()`** der klarste Fix.

**6.4 `isKiosk()`-Helper — wofür wirklich nötig.** In `firestore.rules` existiert **noch kein** `isKiosk()` (verifiziert: kein `function isKiosk`). Gebraucht wird er **nur** für die aktiven Deny-Ausschlüsse in 6.3 (`contacts`, `stockMovements`) — **nicht** für `shifts`/`absenceRequests`-Öffnung (die laufen über Projektionen). Er prüft das Rollenfeld/Custom-Claim `== 'kiosk'` des Geräte-Kontos.

**6.5 HR/Lohn/Finanz bleiben verweigert.** `employeeProfiles/payrollRecords:910/payrollProfiles/sollzeitProfiles/payrollConfig/zeitkontoSnapshots/posReceipts/journalEntries` sind schon `isAdmin()`/Manager-only → automatisch verweigert; **niemals** per `sameOrg` für Kiosk lockern. `clockEntries`-Vollsicht (`:575`-Kontext, `canManageShifts()`) ist **erst nach §0** dicht — vorher hätte der `isActiveUser()`-Default an `canViewTimeTracking` sie geöffnet.

**6.6 Callable vs. direct-device:**
- **Callable (Admin SDK *als* Session-Mitarbeiter):** alles mit Attribution/Finanzwirkung — Stempeln (`kioskClockPunch`, gebaut), Krankmeldung (`kioskSubmitAbsence`), Wunsch-Status (`kioskUpdateWishStatus`), Bestellung-vorbereitet (`kioskMarkOrderPrepared`). Jede prüft die aktive `kioskSessions/{sid}` **serverseitig** (`sid` ist kein Firebase-Token, Rules sehen ihn nicht — `kioskSessions` ist `read,write:false`, `firestore.rules:897–898`), setzt die richtige `userId`/`preparedByUid` und re-prüft Same-Org/`siteId`-Bindung. Region `europe-west3` (`const REGION`, `functions/index.js:19`).
- **direct-device (Geräte-Konto + Feld-Whitelist):** leichte Writes — Kühlschrank (`refillFridge`), To-Do abhaken (`hasOnly(['completedBySite','updatedAt'])`, `:881–885`). Mitarbeiter aus `sid` als **Metadatum**. **Muster für alle künftigen leichten Kiosk-Writes: Feld-Whitelist statt breitem Schreibrecht.**

---

## 7. Increments A1..A3

Jeder Increment = kleinster offline-testbarer Schritt. **Vor A1 zwingend: §0-Overrides** (blockiert die ganze Datensparsamkeit).

### ☐ A0 — Read-Scope härten *(blockierend, muss zuerst)*
- Kiosk-`users/{uid}` bekommt explizite `permissions:{canViewSchedule:false, canViewTimeTracking:false, canViewReports:false, canEditSchedule:false, canEditTimeEntries:false}` (§0). Bootstrap des Geräte-Kontos anpassen.
- `isKiosk()`-Helper + `&& !isKiosk()` in `contacts`-Read (`:1343`) und `stockMovements`-Read (`:1354`) (§6.3).
- Emulator-Test (§10) **gegen ein Kiosk-Profil OHNE Overrides**: es darf `clockEntries`/`zeitkontoSnapshots`/`shifts` **nicht** lesen. Deploy `firestore:rules`.

### ☐ A1a — Bestehende Kacheln bestätigen + PII-Feldreduktion *(kein Rules-Change, kein Callable, echt sofort)*
- Kühlschrank nachfüllen + Nachgefüllt quittieren *(gebaut)* — Session-Attribution + `touch()` verifizieren.
- Offene Kundenwünsche *(gebaut)* — **PII-Feldreduktion verbindlich** (`customerName`/`customerContact` nie rendern).
- Laden-To-Dos + abhaken *(gebaut)* — bestätigen.

### ☐ A1b — Neue read-only Scan-Tiles *(kein Rules-Change, aber neue Widget-Verdrahtung)*
- Stempeln — UX-Feinschliff (Bestätigungs-Overlay, große Kommen/Gehen-Buttons).
- Preis-Scanner + Bestand prüfen — neue read-only Scan-Tile, `siteId` gepinnt, EK/Marge ausgeblendet (§6.2).

### ☐ A2 — Board-Reads über Projektionen *(schmale Projektionen, keine direkten sensiblen Reads)*
- Niedrigbestand / Nachbestellen — `_HintsTile`-**Bugfix** (`siteId` nutzen, `lowStockProducts`).
- Fällige Kundenbestellungen — `ordersDueSoonNotPrepared({siteId})`, PII-arm.
- Schnellwahl häufige Artikel — Scanner-Ergänzung.
- Heutige Schichten + Meine nächste Schicht — `kioskShifts/{siteId}`-Projektion (§5 #2), server-gepflegt beim Publish.
- Wer ist gerade im Dienst — `kioskPresence`-Projektion (§5 #3).

### ☐ A3 — Neue Callables, Projektionen & Greenfield *(Rules + Functions + ggf. Model)*
- Wer fehlt heute — **Session-only** (§9 #2); `kioskAbsences/{siteId}`-Projektion (§5 #7, feldbeschnitten, kein `reason`).
- Krankmeldung — Callable `kioskSubmitAbsence` (+ Bestätigungs-Dialog, **serverseitige** Schichtfreigabe, §8.3).
- Wunsch quittieren — Callable `kioskUpdateWishStatus`.
- Kundenbestellung vorbereitet melden — Callable `kioskMarkOrderPrepared`.
- Kassenabgleich-Status — `config/oktoposSyncStatus` am Ende von `runOktoposSync`.
- Mitteilung der Leitung (Aushang) — **Greenfield:** `StoreAnnouncement`-Model + `announcements`-Collection + Rules-Block + Leiter-Editor + `AnnouncementProvider`.

> **Deploy-Bündel:** A0 → `firebase deploy --only firestore:rules`. A2/A3 → `firestore:rules` (Projektions-/`announcements`-Blöcke), `functions` (neue Callables + Projektions-Pflege in bestehenden Functions), `firestore:indexes` (nur falls server-Aggregation gebaut wird). Emulator vor Go-Live.

---

## 8. Kritische Kopplungen & Risiken („Wenn du X änderst, ändere auch Y")

1. **§0-Overrides sind Voraussetzung** — ohne sie liest das Geräte-Konto `shifts`/`clockEntries`-nahe Collections über den `isActiveUser()`-Default. Ein Kiosk-Konto **ohne** Overrides = Fehlkonfiguration; im Bootstrap erzwingen und im Emulator gegenprüfen.
2. **Board liest sensible Daten NUR über Projektionen** (`kioskShifts`/`kioskPresence`/`kioskAbsences`), **nie** direkt `shifts`/`absenceRequests`/`clockEntries`/`users` — weil Rules nicht feldweise beschneiden. Neue Board-Kachel mit personenbezogener Quelle → **immer** neue whitelisted Projektion, nicht den Roh-Read öffnen.
3. **Krankmeldung** → `kioskSubmitAbsence` **portiert** die *„Chef gibt frei"*-Schichtfreigabe aus `ScheduleProvider.submitAbsenceRequest` (`schedule_provider.dart:1411`) **serverseitig neu** (es existiert keine Function dafür): betroffene `shifts` desselben Kalendertags via Admin SDK auf `status='cancelled'` + `userId` freiräumen; nur `sickness/childSick`. Compliance-Schwellen bei jeder Änderung in `compliance_service.dart` **und** `functions/index.js` synchron (Kopplung #2). Effort **L**.
4. **`kioskMarkOrderPrepared`** → **nicht** über `saveCustomerOrder`/[`markCustomerOrderPrepared`](../lib/providers/inventory_provider.dart#L2317). Dessen Umsatzbuchung [`_bookCustomerOrderRevenueIfNeeded`](../lib/providers/inventory_provider.dart#L119) (Def. `:119`, Aufrufe `:2248`/`:2277`) feuert **nur** beim Übergang → `pickedUp` (nicht bei `prepared`) — der Kiosk geht dennoch nie über `saveCustomerOrder` (kein `pickedUp`, keine Folge-/Umsatzwirkung). Der Callable schreibt nur `preparedAt`/`updatedAt`/`preparedByUid`; `role:kiosk` darf **nie** `pickedUp`/Umsatz schreiben. Callable statt enger Rule (Attribution, §2.6).
5. **Neuer Callable** (`kioskSubmitAbsence`/`kioskUpdateWishStatus`/`kioskMarkOrderPrepared`) → Region `europe-west3` (`const REGION`, `functions/index.js:19`), **snake_case**-Payload, `sid`-Session-Validierung serverseitig + App-Check, Client-Seam via `cloudFunctionInvoker` für Fakes/Dev.
6. **`StoreAnnouncement`-Model** → 6 Serialisierungs-Stellen + `copyWith` (+`clearX` für nullable `siteId`/`expiresAt`); neuer Rules-Block (`read:sameOrg`, `write:canManageShifts`); **bewusst cloud-only**, **kein** `DatabaseService`-Eintrag (Kiosk hat keinen lokalen Persistenz-Pfad, §4).
7. **`AnnouncementProvider`** → in `main.dart`-Kette **nach** Auth/Storage/Audit einfügen (Kopplung #4), Cloud-Repo **lazy** auflösen; im `APP_DISABLE_AUTH`-Demo leere Liste/Stub liefern (sonst rote Seite).
8. **`kioskPresence`/`kioskShifts`/`kioskAbsences`-Projektionen** → server-only Write; Client `read:sameOrg / write:false`. **Nicht** `clockEntries`/`users`/`shifts`/`absenceRequests` für `role:kiosk` öffnen.
9. **`config/oktoposSyncStatus`** → nur am **Erfolgs-/Fehler-Ende** von `runOktoposSync` schreiben, PII-frei (kein Beleg, keine Kassierer-/Kunden-ID, kein Umsatz).
10. **`siteId`-Pinning** → jede neue Kachel + jeder neue Callable liest `siteId` aus Geräte-Konto/`KioskDeviceStore`, **nie** aus dem Request-Payload (sonst Fremd-Laden-Leak).

---

## 9. Getroffene Entscheidungen (Inhaber delegiert, 2026-07-01)

Der Inhaber hat die Entscheidung delegiert („mach, was sinnvoll ist"). Festgelegt — danach wird gebaut, Einspruch jederzeit:

1. **Krankmeldung am Tablet → JA.** Session (nach PIN), Callable `kioskSubmitAbsence`, Typ `krank`/`Kind krank`, mit **unübersehbarem Bestätigungs-Dialog**. (A3)
2. **„Wer fehlt heute" NICHT aufs öffentliche Board → nur Session.** Abwesenheits-Namen gehören nicht auf ein **kundensichtbares** Dauer-Board; die feldbeschnittene `kioskAbsences`-Projektion (Name/Datum/Typ, **kein** Grund) wird **erst nach PIN** gezeigt. Das öffentliche Board zeigt nur „wer arbeitet heute" (nur **Vornamen**, operativ nötig). (§2.1, jetzt Session)
3. **Kassenabgleich-Status aufs Board → JA.** Nur Ampel + Uhrzeit + Meldung, **keine** Umsatzzahlen (`config/oktoposSyncStatus`). (A3)
4. **EK-Schutz beim Scanner → Interim Restrisiko (b), Ziel Projektion (a).** Start: `products` bleibt lesbar, EK/Marge/Preishistorie **nie** gerendert; dokumentiert akzeptiert (online-wired, cloud-only, kein Offline-Dump). Die schmale `kioskProducts`-Projektion (§6.2 a) kommt **nur**, wenn der EK als striktes Betriebsgeheimnis behandelt werden soll — späterer optionaler Baustein. (A1b interim)
5. **„Heute im Laden"-Beleg-Zählung / „Ladenhüter-Tipp" → NEIN (vorerst).** Nicht in A0–A3; separater, server-aggregierender Baustein, falls später gewünscht.
6. **Kontakte am Tablet → NEIN (vorerst).** Datensparsamkeit > Komfort; ein reines Lieferanten-Tile (Firmenname + Telefon, supplier-only) bleibt eine spätere Option.
7. **Aushang-Ablaufdatum → Default 7 Tage.** `StoreAnnouncement.expiresAt` = Erstellzeit + 7 Tage (im Editor überschreibbar), danach automatisch ausgeblendet.
8. **Echtes Bestellen am Kiosk → NEIN, nur Nachbestell-Vormerkung.** `kioskSubmitOrder` wird vorerst **nicht** gebaut; der Kiosk merkt Nachbestellungen im geteilten Korb vor (§2.6), die echte Bestellung löst der Manager im App-Tab aus.

**Neu ergänzt (Inhaber, „sehr wichtig"): MHD-/Ablauf-Warnung.** Getränke & Süßwaren bekommen ein Ablaufdatum; **2–3 Tage vor Ablauf** warnt eine Kachel auf **allen** Laden-Tablets **und** die App (In-App + Push). Eigenes Plan-Dokument [`plan/mhd-ablauf-warnung.md`](mhd-ablauf-warnung.md); Kiosk-Kachel s. §2.6.

*(Ausdrücklich **nicht** offen — bewusst abgelehnt: Feedback/Beschwerden, Lohn-/HR-/Finanz-Zahlen, EK-Preise/Margen/Umsatz je Beleg, Kassierer-Anomalie, `stockMovements`, `contacts`-Vollzugriff auf dem geteilten Tablet.)*

---

## 10. Quality Gates / Definition of Done

```bash
flutter analyze                                   # lint clean
flutter test                                      # alle offline (Fakes), de_DE
flutter run --dart-define=APP_DISABLE_AUTH=true   # Kiosk-Board/Session im Offline-Demo
```

- **Read-Scope-Regression (A0, kritisch):** Emulator-Test **gegen ein Kiosk-Profil OHNE Permission-Overrides** — es darf `clockEntries`/`zeitkontoSnapshots`/`shifts`/`contacts`/`stockMovements` **nicht** lesen (belegt, dass die Overrides bzw. `!isKiosk()` greifen, nicht der `isActiveUser()`-Default).
- **Erlaubt-Test:** `role:kiosk` **darf** `storeTasks`/`products`(bzw. `kioskProducts`)/`customerWishes`/`customerOrders`/`kioskRoster`/`kioskShifts`/`kioskPresence`/`kioskAbsences`/`config/oktoposSyncStatus` lesen; **darf nicht** direkt `shifts`/`absenceRequests`/`workEntries`/`clockEntries` schreiben.
- **Neue Callables** über `cloudFunctionInvoker`-Seam testen (Fakes); `FirebaseFunctionsException(code:'not-found'|'unavailable')` für Fallback-Pfade. Region `europe-west3` prüfen. `sid`-Session-Validierung serverseitig testen (abgelaufene/fremde `sid` → Deny).
- **Zwei-Serialisierungs-Regel** für `StoreAnnouncement` per Round-Trip-Test (`toMap`↔`fromMap`, `toFirestoreMap`↔`fromFirestore`; `clearX` für `siteId`/`expiresAt`).
- **Schichtfreigabe (`kioskSubmitAbsence`)**: Test, dass eine `sickness`-Meldung die betroffene `shifts` desselben Tags auf `cancelled` setzt und `userId` freiräumt; kein Effekt, wenn keine Schicht am Tag.
- **PII-Feldreduktion** als Widget-Test/Review-Punkt: Wünsche-Tile rendert **kein** `customerName`/`customerContact`; Scan-Tile rendert **kein** `purchasePriceCents`.
- **Deutsch-only**, `Theme.of(context).appColors` für Status (nie hardcoden), große Touch-Ziele (≥ 48 dp, für Tablet-Distanz eher größer), `DateFormat` immer `'de_DE'`.
- Kein Merge-Gate (self-hosted) — Gates vor dem Commit selbst ausführen; `firebase deploy --only firestore:rules,firestore:indexes,functions` gebündelt vor Go-Live.
