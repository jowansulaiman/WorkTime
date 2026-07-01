# Arbeitsmodus / Laden-Tablet (Kiosk) — Plan

> Stand: 2026-06-30 · Status: **Entwurf, code-verifiziert** · Greenfield-Feature
> Verwandt: [kuehlschrank-nachfuell-automatik.md](kuehlschrank-nachfuell-automatik.md) · [push-benachrichtigungen-plan.md](push-benachrichtigungen-plan.md) · [ida-hr-zeit-uebernahme.md](ida-hr-zeit-uebernahme.md) (§6.3 Terminal/Kiosk war hier reserviert) · [zeitwirtschaft-alltec-1zu1.md](zeitwirtschaft-alltec-1zu1.md)

## 1. Was der Inhaber will

Ein **fest im Laden installiertes Tablet** als „Arbeitsmodus" für das Team — immer eingeschaltet, immer an, zeigt dauerhaft die operativ wichtigen Dinge und lässt Routinearbeiten direkt erledigen:

- **Dauer-Anzeige (ohne Anmeldung):** Kundenwünsche, Laden-To-Dos (vom Leiter festgelegt), Mitteilungen, „Kühlschrank muss nachgefüllt werden" — die wichtigen Sachen, gut sichtbar.
- **Aktiv arbeiten (mit kurzer Anmeldung):** Bestellungen aufgeben, Nachfüllen quittieren, To-Dos abhaken, **ein-/ausstempeln** und „weitere für die Arbeit wichtige Sachen" (bewusst **erweiterbar** halten).
- **Anmeldung am Tablet:** Liste der Mitarbeiter des Ladens wird gezeigt → Mitarbeiter tippt seinen **Namen** an → gibt eine **PIN** ein, die er vorher selbst auf seinem **eigenen Handy** gesetzt hat → ist angemeldet.
- **Datensparsamkeit:** Auf dem geteilten Tablet werden **nicht** alle persönlichen Daten gezeigt — nur das, was er für die Ladenarbeit braucht (kein Lohn, keine HR-Akte, keine Auswertungen, keine Einstellungen).

### Festgezurrte Entscheidungen des Inhabers (2026-06-30)

| # | Entscheidung | Gewählt |
|---|---|---|
| E1 | PIN-Prüfung | **Server-geprüft** — Hash client-unlesbar, Cloud Function prüft + Rate-Limit/Sperre |
| E2 | Tablet ↔ Laden | **Fest pro Laden** (Strichmännchen / Tabak Börse) — Filter automatisch auf diesen Standort |
| E3 | Anmeldung | **Namensliste antippen + PIN** (schnellste Bedienung) |
| E4 | Aktionen am Kiosk | **Voll**: Stempeln, Kühlschrank quittieren, Bestellungen wirklich auslösen, To-Dos abhaken — **+ erweiterbar** |
| E5 | Plattform | **Android-Tablet + iPad** (kein Web-Vollbild) — native Always-On/Immersive, `persistenceEnabled:false` unkompliziert |
| E6 | PIN-Länge | **4-stellig** + serverseitige Sperre nach **5** Fehlversuchen |
| E7 | Bestellung am Kiosk | **Server-geprüft** via `kioskSubmitOrder` — Geräte-Konto bekommt **kein** `canManageInventory` |
| E8 | Defaults (gesetzt) | To-Do anlegen = **Leiter/Admin only** · Auto-Logout = **90 s** + Countdown · Provisioning = **MVP-Login → Setup-Code später** |

## 2. Datenbefund (ehrlich, code-verifiziert) — was da ist, was fehlt

**Direkt wiederverwendbar (existiert & getestet):**

| Fähigkeit | Bestehender Hebel |
|---|---|
| Ein-/Ausstempeln | `ZeitwirtschaftProvider.clockIn({siteId, siteName, at})` (`lib/providers/zeitwirtschaft_provider.dart:628`) + `clockOut({pauseMinuten, anmerkung, at})` (`:659`); Modell `ClockEntry` (`lib/models/clock_entry.dart`); ArbZG-Pausen pur in `ClockService` (`lib/core/clock_service.dart`); Stempel→WorkEntry-Brücke über `_workEntryPoster`-Seam (`:185`, in `main.dart` auf `WorkProvider.addEntry` gesetzt) |
| Kundenwünsche anzeigen | `FirestoreService.watchCustomerWishes(orgId, limit:300)` (`lib/services/firestore_service.dart:1823`) → `Stream<List<CustomerWish>>`; Filter `w.status.isOpen` (`lib/models/customer_wish.dart`); Kategorie-/Status-Labels vorhanden |
| Kühlschrank-Alarme | `InventoryProvider.fridgeShortfalls(siteId?)` (`:457`) / `fridgeShortfallCount(siteId?)` (`:461`); pur `computeFridgeShortfalls` + `isNearClosing` (`lib/core/fridge_refill_shortfall.dart`); Tile `_FridgeShortfallTile` (`fridge_refill_screen.dart:298`) |
| Nachfüllen quittieren | `InventoryProvider.refillFridge(product, quantity?)` (`:1860`); Rule erlaubt jedem `isActiveUser()` Update auf nur `{fridgeStock, updatedAt}` |
| Bestellungen auslösen | `InventoryProvider.savePurchaseOrder(PurchaseOrder)` (`:2023`), `reorderSuggestions`/`needsReorder` (`:274`), `openOrders`, `ordersForSite(siteId)` (`:308`) |
| Mitteilungen-Layout | `notification_screen.dart` `_buildItems()` + `_InboxItem` (abgeleitete Inbox; **user-spezifisch** — für Kiosk store-/site-gefiltert neu zusammenstellen) |
| Routing-Bausteine | `_gateRedirect` (`lib/routing/app_router.dart:215`), `_gatePaths`-Set (`:52`), `AppRoutes` (`lib/routing/shell_tab.dart:36`), `RoutePermissions.isLocationAllowed` (`lib/routing/route_permissions.dart:19`) |
| Config-Flag-Muster | `AppConfig.oktoposEnabled` (`:142`) / `pushEnabled` (`:154`) als Vorlage; `FeatureFlagProvider.isEnabled(flag, fallback:)` (`config/appFlags`) |
| Theme/Tablet | `AppThemeColors` via `context.appColors`; `MobileBreakpoints` (Rail ab 600, volle Labels ab 840); flache V2-Tokens |

**Echte Lücken (von Grund auf neu):**

1. **Laden-To-Do existiert nicht.** `WorkTask` (`lib/models/work_task.dart`) ist **ausdrücklich ein individueller HR-Auftrag an *einen* Mitarbeiter** (`assignedUserId` Pflichtfeld, Admin-Personal-Tab). Es gibt kein laden-weites, broadcast-fähiges To-Do. → neues Modell `StoreTask`.
2. **PIN-Mechanik existiert nirgends.** Kein Feld, kein Hash, keine Callable. (Im IDA-Plan §6.3 nur als Idee reserviert: „server-side rate-limit/lockout/App Check, NICHT Client-SHA1".)
3. **Kiosk-Geräteidentität / -Session existiert nicht.** Auth ist heute rein nutzer-eigen (Firebase-UID, `users/{uid}` trägt `orgId`).
4. **Kein Wakelock/Immersive/Fullscreen** in `pubspec.yaml` (Always-On-Display fehlt komplett).

**Tragende Sicherheits-Wahrheit:** Ein geteiltes Tablet ist **einmal** bei Firebase eingeloggt. Jeder Read/Write läuft unter genau diesem einen Token. Eine reine Client-PIN entscheidet nur, *welche UI* sichtbar ist — sie schränkt **nicht** ein, was das Token serverseitig darf. Dazu kommt: Firestore-Offline-Persistence (`main.dart`, `persistenceEnabled`) legt **alle gelesenen Daten lokal auf Platte** und wird bei „Logout" **nicht** geleert. → Das Auth-Modell muss das aktiv lösen (§4).

## 3. Architektur-Entscheidung: Gate-Route innerhalb der Shell, eigenes Geräte-Konto

Drei mögliche Einbau-Orte wurden geprüft:

| Ansatz | Bewertung |
|---|---|
| **Isolierte Public-App** (wie `/wunsch`, eigenes `MaterialApp`, keine Provider) | ❌ Kiosk braucht den **lebenden Provider-Chain** (Inventory, Zeitwirtschaft, Wishes). Eine isolierte App müsste alles parallel verdrahten — doppelte Wahrheit, kein Reuse. |
| **Neuer Shell-Tab** | ❌ Kiosk **ersetzt** die ganze Shell (Vollbild, keine 7-Tab-Navigation, keine HR-/Lohn-Tabs sichtbar). Ein Tab wäre das Gegenteil. |
| **Gate-Route `/arbeitsmodus` in der Shell-App** | ✅ **Gewählt.** Volle Provider-Kette verfügbar, eigene Vollbild-UI, Navigation gesperrt. `_gateRedirect` lenkt das **Geräte-Konto** zwingend auf `/arbeitsmodus`. |

**Geräte-Konto statt Personen-Konto:** Das Tablet meldet sich als dediziertes **Kiosk-Geräte-Konto** an (`role: kiosk`, Claims/Felder `deviceId` + `siteId` + `orgId`). Dieses Konto:
- darf **nur** store-operative, **site-skopierte** Daten lesen (Produkte/Kühlschrank des Ladens, offene Kundenwünsche, Laden-To-Dos, eine **minimale Namensliste** — siehe `kioskRoster` §4),
- darf **keine** Personaldaten (Lohn, Verträge, HR-Akte, Stundenkonto, Auswertungen) lesen,
- landet beim Start via neuem `_gateRedirect`-Zweig auf `/arbeitsmodus` (Vollbild-Board, **ohne** Anmeldung sichtbar).

## 4. Auth-Modell für „Name antippen + PIN" (Entscheidung E1 = server-geprüft)

**Tragende Korrektur (verworfene Variante B1):** Die Mitarbeiter-Identität wird **nicht** per `signInWithCustomToken` auf der Default-`FirebaseAuth` getauscht. Ein Identitätstausch arbeitet gegen die bestehende Architektur: `AuthProvider` hört auf `authStateChanges`, löst beim Wechsel das **Mitarbeiter-Profil** neu auf, und `_gateRedirect` (im `refreshListenable = merge([auth, featureFlags, theme])`) bewertet neu → ein normaler `employee` würde sofort in die **normale Shell** (`/`) umgeleitet, der Kiosk-Lock bräche. Außerdem müsste das Geräte-Konto nach jeder Session neu eingeloggt und der Firestore-Cache des Mitarbeiters geräumt werden. **Deshalb bleibt das Geräte-Konto die einzige Firebase-Identität.**

**Gewähltes Modell — „Geräte-Konto bleibt angemeldet + serverseitige Kiosk-Session (`sid`) + Callable nur für sensible Writes":**

```
[Tablet = Geräte-Konto (role:kiosk), Dauer-Board sichtbar, _gateRedirect pinnt auf /arbeitsmodus]
   │  Mitarbeiter tippt Namen (aus kioskRoster, site-gefiltert) + PIN am On-Screen-Zahlenpad
   ▼
kioskBeginSession(employeeId, pin, deviceId)         ← neue Callable, App Check erzwungen
   │  Server: scrypt-Hash aus userSecrets/{uid} prüfen
   │          + assertSameOrg + Site-Zugehörigkeit + Rate-Limit/Lockout pro employeeId
   │          + Audit (Erfolg UND Fehlschlag) mit deviceId/sessionId
   ▼  Erfolg → kioskSessions/{sid} anlegen (employeeId, deviceId, kurze exp) + sid zurückgeben
[Tablet hält nur `sid` IM SPEICHER — KEIN Firebase-Identitätswechsel, AuthProvider/Gate unberührt]
   │  • Sensible Writes (Stempeln; optional Bestellen): Callable mit `sid` → Server validiert
   │       Session + schreibt via Admin SDK ALS der Mitarbeiter (gleiche ClockEntry/WorkEntry/
   │       Compliance-Logik wie upsertWorkEntry).
   │  • Leichte Writes (Kühlschrank refillFridge, StoreTask.done): direkt unter Geräte-Konto,
   │       Mitarbeiter (aus sid) als INFORMATIVE Metadaten gestempelt.
   │  Auto-Logout nach Inaktivität (z. B. 90 s) oder „Fertig" → sid verwerfen (+ serverseitig abgelaufen)
   ▼
[Tablet bleibt durchgehend Geräte-Konto — nichts neu zu signen, kein Cache-Wechsel]
```

**Warum nicht „jede Aktion eine Callable" (Vollvariante B2):** Wir nehmen nur für die **wirklich sensiblen, compliance-gebundenen** Writes (Stempeln; optional Bestellen) eine Callable. Leichte, ohnehin jedem aktiven User per Rule erlaubte Writes (Kühlschrank `{fridgeStock,updatedAt}`, To-Do-`done`-Flip) laufen **direkt** unter dem Geräte-Konto. So bleibt der neue Server-Code klein, und der Board-Read-Pfad nutzt die bestehenden Provider/Services **unverändert**.

**Datensparsamkeit — am stärksten durch „Mitarbeiter loggt sich nie ein":**
1. **Keine Mitarbeiter-Identität auf dem Gerät:** Da nie ein Mitarbeiter-Token existiert, sind dessen HR-/Lohn-Daten auf dem Tablet **prinzipiell nie lesbar** — die stärkste Minimierung (stärker als der zuvor angedachte `kiosk:true`-Claim-Trick).
2. **Geräte-Konto-Read-Scope (Rules):** `firestore.rules` beschränken `role:kiosk` auf site-skopierte, store-operative Reads und **verweigern** Lohn-/HR-/Finanz-/Personal-Collections.
3. **UI:** fixe, reduzierte Screen-Menge — HR/Lohn/Auswertungen/Einstellungen nicht erreichbar.
4. **Persistenz:** Kiosk-Build mit `persistenceEnabled:false` + cloud-only Storage-Modus → nichts Personenbezogenes dauerhaft auf der Platte; In-Memory bei Session-Ende/App-Neustart verworfen. (Wired-Tablet = online die Norm; offline = degradierter Nur-Anzeige-Zustand.)

**Geräte-Provisionierung (Geräte-Konto ohne Menschen-Passwort):**
- Admin legt im Admin-Bereich ein Kiosk-Gerät an → Server erzeugt `kioskDevices/{deviceId}` (`{orgId, siteId, setupCodeHash, active}`) + zeigt einen **einmaligen Setup-Code**.
- Am Tablet Setup-Code eingeben → `kioskActivateDevice(deviceId, setupCode)` (App Check erzwungen) → Server gibt Geräte-Custom-Token zurück + persistiert ein Geräte-Secret in `flutter_secure_storage`. Token-Refresh via `kioskRefreshDeviceToken(deviceId, deviceSecret)`.
- **MVP-Abkürzung (Increment 2):** Gerät meldet sich vorerst mit einem dedizierten Kiosk-E-Mail/Passwort-Konto an (in `flutter_secure_storage`), Upgrade auf Setup-Code-Provisioning später (Increment 4). Bewusster, dokumentierter Tradeoff.

**PIN-Lebenszyklus (auf dem eigenen Handy):**
- Mitarbeiter setzt/ändert PIN im **normalen** (authentifizierten) App-Profil → `setKioskPin(pin)` → Server **hasht serverseitig** (scrypt/bcrypt, **nie** Client-SHA1) → `organizations/{orgId}/userSecrets/{uid}` (Client `read,write: if false`, nur Admin-SDK).
- Policy (E6, festgezurrt): **4-stellige PIN**, Lockout nach **5** Fehlversuchen pro `employeeId` (Server-State, z. B. 5 min Sperre), Admin kann PIN **zurücksetzen** (löschen → Mitarbeiter muss neu setzen). Kein Ablauf im MVP.

## 5. Neue Datenmodelle & Collections

Alle org-skopiert unter `organizations/{orgId}/`. **Duale Serialisierung beachten (Zwei-Serialisierungs-Regel, 6 Stellen je Feld).**

### 5.1 `StoreTask` — Laden-To-Do (broadcast, nach Vorlage `WorkTask`)
Collection `storeTasks`. Felder: `id`, `orgId`, `siteId` (**Broadcast-Scope statt `assignedUserId`** — `null` = alle Läden), `title`, `description?`, `priority` (`low`/`medium`/`high`), `dueDate?`, `createdByUid` (Leiter), **`completedBySite: Map<siteId, {by,name,at}>`** (Erledigt-Status **je Standort**), `createdAt`, `updatedAt`.
- **Entscheidung „Erledigt je Standort" (2026-07-01):** Eine Broadcast-Aufgabe erscheint in jedem Laden und wird von **jedem Laden unabhängig** abgehakt — erledigt in Laden A lässt sie in Laden B offen. Realisiert über die `completedBySite`-Map (Schlüssel = `siteId`) statt eines globalen `status`; `isDoneForSite(siteId)`/`openStoreTasksForSite(siteId)` filtern je Tablet-Standort. (Kein globales `status`/`done`-Feld mehr.)
- Enums mit `.value`/`fromValue`(Default-Branch)/deutschem `label` — wie `WorkTask`.
- `copyWith` mit `clearX` für nullable Felder (`dueDate`, `doneAt`, …).
- Provider: **`StoreTaskProvider`** (oder Erweiterung von `PersonalProvider`) mit `storeTasksForSite(siteId)`-Getter; lazy Cloud-Repo (nie im Konstruktor). Drei Storage-Modi + Audit-Sink **nur auf Erfolgs-Pfad**.

### 5.2 `kioskRoster` — minimale Namensliste (Datensparsamkeit)
Collection `kioskRoster/{uid}`: `{uid, displayName, photoUrl?, siteIds:[…], active}`. **Nur** diese Projektion — **kein** Lohn, **keine** Settings. Damit das Geräte-Konto die Namensliste lesen kann, **ohne** die vollen `users/{uid}`-Docs (die `hourlyRate` etc. enthalten) zu sehen. (Firestore-Rules können Reads **nicht** feldweise beschneiden → separate Projektion nötig.)
- Gepflegt per **Cloud-Function-Trigger** auf `users/{uid}`-Writes (onWrite → Projektion schreiben) oder beim Speichern des Profils. Verwandt mit dem Fan-out-Muster aus [push-benachrichtigungen-plan.md](push-benachrichtigungen-plan.md).

### 5.3 `userSecrets/{uid}` — PIN-Hash (client-unlesbar)
`{pinHash, pinAlgo, failedAttempts, lockedUntil?, updatedAt}`. Rules: `allow read, write: if false;` (nur Admin-SDK). Nie im Client.

### 5.4 `kioskDevices/{deviceId}` — Geräte-Registrierung
`{orgId, siteId, label, setupCodeHash?, active, lastSeenAt}`. Rules: Admin-write, Geräte-Konto darf nur sein eigenes Doc lesen.

### 5.5 `kioskSessions/{sid}` — aktive Kiosk-Anmeldung (server-only)
`{sid, orgId, siteId, deviceId, employeeId, startedAt, expiresAt, revokedAt?}`. Vom Server (`kioskBeginSession`) angelegt, von `kioskClockPunch`/`kioskSubmitOrder` validiert, bei Logout/Timeout `revokedAt`/abgelaufen. Rules: Client `read,write: if false` (nur Admin-SDK). Der `sid` lebt am Tablet **nur im Speicher**. Trägt zugleich den Server-State für **Rate-Limit/Lockout** (bzw. separater Zähler an `userSecrets`).

> **Composite-Indizes prüfen:** `storeTasks where(siteId) + orderBy(createdAt)` und ggf. `where(status)+orderBy(dueDate)` → passende Einträge in `firestore.indexes.json` (sonst Laufzeitfehler). `customerWishes`/`fridge` brauchen keine neuen Indizes (Wishes nur `orderBy createdAt`; Fridge ist In-Memory-Compute).

## 6. Kiosk-UI — modularer Kachel-Aufbau (erweiterbar, E4)

Das **Dauer-Board** (Geräte-Identität, ohne Anmeldung) ist eine **modulare Kachel-Liste**, damit „weitere wichtige Sachen" billig ergänzbar sind. Jede Kachel = ein `KioskModule`-Widget mit `(title, severity, count, body, onTap)`; eine Registry-Liste rendert sie responsive (`AdaptiveCardGrid`).

**Kachel-Module (MVP):**
- **Kundenwünsche** (offen, `watchCustomerWishes` → `isOpen`, site-gefiltert via `storeName`) — read-only, prominent.
- **Kühlschrank nachfüllen** (`fridgeShortfalls(siteId)`, `isNearClosing`-Boost) — Quittieren nur in Session.
- **Laden-To-Dos** (`storeTasksForSite(siteId)`, offen/in Arbeit) — Abhaken nur in Session.
- **Mitteilungen** (store-gefilterte Adaption von `notification_screen._buildItems`: fällige Kundenbestellungen, Niedrigbestand, neue Wünsche — **ohne** personenbezogene Schicht-/Abwesenheits-Items).

**Session-Module (erst nach PIN sichtbar):**
- **Stempeln** (großer „Kommen/Gehen"-Button → `kioskClockPunch`-Callable, Site fix = Geräte-`siteId`; im Offline-/Demo-Modus lokaler Pfad).
- **Bestellen** (`reorderSuggestions` + `savePurchaseOrder`, Editor-Sheet imperativ `Navigator.push`).
- **Meine nächste Schicht / heutige Schichten im Laden** (Read aus `ScheduleProvider`, nur Klartext-Zeiten — Kandidat für „weitere wichtige Sachen").

**UI-Konventionen:** Deutsch-only, `context.appColors` für Status (nie hardcoden), große Touch-Ziele (a11y kritisch — `flutter-ux-ui-design`), `showModalBottomSheet(showDragHandle:true, isScrollControlled:true, useSafeArea:true)` für Aktionen. Zahlen-Pad als **eigenes On-Screen-Widget** (keine System-Tastatur → kein Key-Logging, kiosk-typisch). **Wakelock + Immersive** (`SystemChrome.setEnabledSystemUIMode`) hinter `kioskModeEnabled` gaten.

## 7. Phasen / Inkremente (jeweils kleinster offline-testbarer Schritt)

### Increment 0 — Kiosk-Shell + Dauer-Board, offline testbar · Status: ✅ umgesetzt (2026-07-01)
Ziel: komplette UX **ohne Firebase** beweisen (`flutter run --dart-define=APP_DISABLE_AUTH=true --dart-define=APP_KIOSK_ENABLED=true`, CLAUDE.md-Default).
Umgesetzt: `StoreTask`-Model+`StoreTaskProvider` (3 Speichermodi, Audit-Sink, in Kette) inkl. FirestoreService/DatabaseService/**firestore.rules** (kein neuer Index — Client-Sortierung); `AppConfig.kioskModeEnabled`+`kioskSiteId`; Gate-Route `/arbeitsmodus` (`_gateRedirect`-Zweig, GoRoute); `KioskScreen` mit modularer Kachel-Registry (Zeiterfassung, Laden-To-Dos, Kühlschrank, Kundenwünsche, Hinweise), Namensliste + 4-stelliges PIN-Pad (Dev-Pfad `KioskPinStore`, Demo-PIN 1234), Auto-Logout (`KioskController`, 90 s), Leiter-Editor-Sheet. Tests: `store_task_model_test.dart` + `store_task_provider_test.dart` (17 Fälle, grün). `flutter analyze` sauber; volle Suite grün außer 1 vorbestehendem, wall-clock-abhängigem `store_health_screen_test` (teilt keinen Code mit diesem Feature).
- `AppConfig.kioskModeEnabled = bool.fromEnvironment('APP_KIOSK_ENABLED', false)` (Muster `oktoposEnabled`).
- `AppRoutes.kiosk = '/arbeitsmodus'` + in `_gatePaths` aufnehmen + `GoRoute` + `_gateRedirect`-Zweig (Demo: per Flag erzwingbar).
- Vollbild-`KioskScreen` mit modularem Board, gespeist aus **Demo-Daten** + bestehenden Providern (`fridgeShortfalls`, Demo-Wishes).
- Namensliste + Zahlen-Pad-UI mit **lokalem Dev-PIN-Pfad** (nur unter `disableAuthentication`, kein Callable) → UX end-to-end offline.
- `StoreTask`-Modell + `StoreTaskProvider` (lokaler Modus) + Leiter-Authoring-Sheet. Round-trip-Tests (`toMap`/`fromMap`, `toFirestoreMap`/`fromFirestore`).
- Quality Gate: `flutter analyze` + `flutter test` grün.

### Increment 1 — StoreTask Cloud + Rules + Index · Status: ☐
- Firestore-Pfad `storeTasks`, Rules (`sameOrg` read; `canManageShifts`/Admin write; Geräte-Konto darf `done`-Flip + `doneByEmployeeId` setzen), Composite-Index.
- Provider drei Storage-Modi + Audit-Sink. `firestore.rules` ↔ Provider-Mutatoren synchron.

### Increment 2 — Server-PIN + Kiosk-Session + Stempeln scharf (Blaze) · Status: ◑ Code fertig, Deploy/Emulator offen (2026-07-01)
Umgesetzt (Code): Cloud Functions `setKioskPin`/`resetKioskPin`/`kioskBeginSession`/`kioskEndSession`/`kioskClockPunch` in `functions/index.js` (scrypt-Hash, Rate-Limit 5 + 5 min Lockout, `kioskSessions` TTL, App Check erzwungen; `node --check` grün); `firestore.rules` für `userSecrets`/`kioskSessions` (client `if false`) + `kioskRoster` (read sameOrg) + Composite-Index `clockEntries(userId,status)`; Client-Seam `KioskPinService` (Dev lokal / Server-Callable, Fehler-Mapping), FirestoreService `setKioskPin`/`kioskBeginSession`/`kioskEndSession`, Login-Sheet + `KioskController.sessionId` verdrahtet, PIN-Setup-Sheet in den Einstellungen (Profil). Tests `test/kiosk_pin_service_test.dart` (7, grün).
**Stempeln pro Mitarbeiter (2026-07-01):** Der Kiosk-Stempel ist jetzt an die **Session-Mitarbeiter** gebunden (nicht mehr Geräte-Konto) — Seam `KioskClockService`: Dev-Pfad schreibt ClockEntry + WorkEntry(submitted) **lokal dem Mitarbeiter zugeordnet** (org-skopiert, reuse `ClockService`, getestet); Server-Pfad `kioskClockPunch(sid, direction: in/out/status)` legt/schließt die ClockEntry als Mitarbeiter an **und erzeugt den WorkEntry(submitted)** (ArbZG-Pause `kioskRequiredBreakMinutes` = Spiegel von `ClockService`). `_ClockTile` zeigt Kommen/Gehen anhand des Session-Status.
**Offen (Betreiber/Infra):** Blaze-Deploy (`firebase deploy --only functions,firestore:rules,firestore:indexes`), App-Check-Enforcement, **Emulator-Verifikation von `kioskClockPunch`** (Server-Schreibpfad/WorkEntry-Feldshape ungetestet); `kioskRoster`-Pflege-Trigger + Umstellung der Namensliste auf `kioskRoster` im Cloud-Modus (Demo/Team-Provider-Pfad funktioniert).

### Increment 2 (Rest) — ursprünglich geplant: ☐
- Callables in `functions/index.js` (Region == `europe-west3`, snake_case-Payload, **App Check erzwungen**, Audit `deviceId`/`sessionId`):
  - `setKioskPin` / `resetKioskPin` — scrypt-Hash nach `userSecrets/{uid}`.
  - `kioskBeginSession(employeeId, pin, deviceId)` — PIN-Verify + Rate-Limit/Lockout + `kioskSessions/{sid}` anlegen + `sid` zurückgeben (**kein** Custom-Token, **kein** Identitätswechsel).
  - `kioskClockPunch(sid, direction, …)` — Session validieren, ClockEntry/WorkEntry via Admin SDK als Mitarbeiter schreiben (gleiche Compliance-Re-Validierung wie `upsertWorkEntry`).
- `userSecrets/{uid}` + `kioskSessions/{sid}` + `kioskRoster/{uid}` (+ onWrite-Trigger) + Rules.
- `firestore.rules`: `role:kiosk`-Geräte-Konto auf site-skopierte store-operative Reads beschränken, Lohn-/HR-/Finanz-/Personal-Reads **verweigern**.
- PIN-Setup-UI im normalen Profil (Handy). Kiosk-Build: `persistenceEnabled:false` + cloud-only.
- Geräte-Konto via dedizierte Kiosk-E-Mail/Passwort (MVP-Abkürzung, Provisioning-Upgrade in Increment 4).
- Test: Callables via `cloudFunctionInvoker`-Seam simulieren; Emulator für Rules.

### Increment 3 — Leichte Aktionen + Bestellen + Auto-Logout + Always-On · Status: ◑ (2026-07-01)
Umgesetzt: **Always-On** (`wakelock_plus` + `SystemChrome.immersiveSticky`, best-effort/No-op off-Mobile, im `KioskScreen`), **Auto-Logout** (`KioskController`, 90 s, in I0). Kühlschrank-Refill + To-Do-Abhaken laufen bereits (I0). **Offen:** Bestellen scharf (`kioskSubmitOrder` + Editor-Anbindung — aktuell Anzeige/Hinweis „Niedrigbestand"), leichte Writes serverseitig unter Session-Attribution.
- Kühlschrank `refillFridge` + `StoreTask.done` direkt unter Geräte-Konto, Mitarbeiter aus `sid` als informative Metadaten (Stempel-Site fix = Geräte-`siteId`).
- Bestellen (E7): `kioskSubmitOrder(sid, order)`-Callable prüft serverseitig das Bestellrecht des Session-Mitarbeiters und schreibt via Admin SDK. Geräte-Konto bleibt **ohne** `canManageInventory`.
- Inaktivitäts-Timer + sichtbarer Countdown → `sid` verwerfen, Board-Zustand zurück (kein Re-Sign-in nötig, Geräte-Konto bleibt).
- `wakelock`-Plugin + `SystemChrome` Immersive/Orientation-Lock (hinter `kioskModeEnabled`).
- Audit: `AuditLogEntry` um `sessionId`/`deviceId` erweitern (6 Serialisierungsstellen + Rules).

### Increment 4 — Geräte-Provisioning + „weitere Sachen" · Status: ☐
- `kioskActivateDevice` / `kioskRefreshDeviceToken` + Setup-Code-Flow (ersetzt MVP-Abkürzung).
- Admin-UI „Kiosk-Geräte verwalten".
- Weitere Kachel-Module nach Bedarf (heutige Schichten, Niedrigbestand-Vormerkung …) — Registry macht das billig.

## 8. Kritische Kopplungen & Risiken („Wenn du X änderst, ändere auch Y")

1. **Neue Gate-Route** (#7 CLAUDE.md): `AppRoutes.kiosk` + `_gatePaths` (sonst Redirect-Loop) + `_gateRedirect`-Zweig (vor „voll aufgelöst", `app_router.dart:~268`) + `RoutePermissions.isLocationAllowed` + `GoRoute`-Builder.
2. **Neues Model-Feld** (`StoreTask`, #1): `toFirestoreMap`/`fromFirestore`/`toMap`/`fromMap`/`copyWith(+clearX)` + falls über Callable: snake_case in `functions/index.js`.
3. **Neue Collections** (#6): `storeTasks`/`userSecrets`/`kioskRoster`/`kioskDevices` → je `firestore.rules`-Block (`sameOrg`/Admin/`if false`) **und** ggf. `assertSameOrg` in Functions synchron; lokal-persistierte Collection (`storeTasks`) in `DatabaseService` registrieren (org-skopiert).
4. **Geräte-Konto `role:kiosk` als Read-Scope** ist der neue Autorisierungs-Vektor: jede Rule, die HR/Lohn/Finanz/Personal liest, muss `role:kiosk` aktiv verweigern (das Geräte-Konto ist ein aktiver Org-User und käme sonst über `sameOrg` an Daten). **Bei neuem sensiblen Read-Pfad mitziehen.** `kioskSessions` (Stempeln/Bestellen) wird **serverseitig** validiert — `sid` ist kein Firebase-Token, Rules sehen ihn nicht.
5. **Functions-Region** muss `const REGION` (`europe-west3`) entsprechen, sonst stiller Direkt-Fallback (umgeht Validierung).
6. **Stempeln läuft über `kioskClockPunch` (Admin SDK als Mitarbeiter), NICHT über den Client-`clockIn/Out` des Geräte-Kontos** — sonst würde der Eintrag dem Geräte-Konto zugeschrieben. Die Callable spiegelt die `ClockEntry`/`WorkEntry`/Compliance-Logik von `upsertWorkEntry` (Kopplung #2: Compliance-Spiegel mitziehen). Stempel-`siteId` = Geräte-`siteId`.
7. **Firestore-Persistence-off nur im Kiosk-Build:** der normale App-Build behält Persistence — Flag-gegated, nicht global ändern.
8. **`kioskRoster`-Projektion** muss bei jeder relevanten `users/{uid}`-Änderung nachgezogen werden (Trigger), sonst veraltete/fehlende Namen.

**Risiken:**
- **PIN-Verleih** (A gibt B seine PIN): Restrisiko; gemildert durch Server-Audit (`employeeId` + `deviceId` + `sessionId` bei jedem Versuch). Out-of-scope: NFC/Foto/Biometrie.
- **App Check Deploy-Stand:** `enforceAppCheck:true` muss auf den Kiosk-Callables aktiv sein (Voraussetzung E1). **Zu verifizieren**, ob App Check bereits org-weit deployt ist.
- **Blaze:** Custom Tokens, Callables, Secret-/Admin-SDK-Writes, Trigger brauchen **Blaze** — passt zur Zielumgebung (siehe Memory „Blaze-Zielumgebung"); Emulator bis Go-Live.
- **Offline-Board:** ohne Persistence zeigt das Board offline nur In-Memory; bewusst degradiert (wired Tablet).

## 9. Rechte / Sichtbarkeit

- **Leiter/Admin** (`canManageShifts`/`isAdmin`): legen `StoreTask` an, sehen alles.
- **Mitarbeiter am Kiosk** (aktive `kioskSessions/{sid}`): stempeln (`kioskClockPunch`, serverseitig als Mitarbeiter), nachfüllen, `StoreTask.done` setzen, Bestellungen (server-geprüftes Bestellrecht via `kioskSubmitOrder` — sonst nur Vormerkung). **Keine** HR/Lohn/Reports (gar nicht erst auf dem Gerät, da kein Mitarbeiter-Login).
- **Geräte-Konto** (`role:kiosk`, ohne aktive Session): nur site-skopierte Board-Reads.
- Default „wer darf To-Dos anlegen": **nur Leiter/Admin** (Mitarbeiter abhaken, nicht anlegen) — bestätigen.

## 10. Entscheidungen & offene Punkte

**Festgezurrt (E1–E7):** server-geprüfte PIN · fest pro Laden · Namensliste+PIN · volle Aktionen+erweiterbar · **Android-Tablet + iPad (kein Web)** · **4-stellige PIN + Sperre nach 5** · **Bestellen server-geprüft via `kioskSubmitOrder`** (Geräte-Konto ohne `canManageInventory`).

**Per Default gesetzt (E8 — ich baue so, Einspruch jederzeit):** To-Do anlegen nur Leiter/Admin · Auto-Logout 90 s + Countdown · Provisioning MVP-Login → Setup-Code später.

**Bleibt offen (entscheidbar später, blockiert I0 nicht):**
1. **Laden-To-Dos zusätzlich in die persönliche Handy-Inbox** broadcasten (Kopplung an Push-Plan/`AppNotification`), oder rein Kiosk-Anzeige? → relevant ab I1.
2. **„Weitere wichtige Sachen":** welche Zusatz-Kacheln fürs Board (heutige Schichten? Niedrigbestand-Vormerkung? Lieferanten-Termine?) → I4, Registry macht's billig.
3. **App-Check-Deploy-Stand:** Voraussetzung für die Server-PIN (I2) — **prüfe ich selbst** in deiner Firebase-Konfig, sobald wir dort sind (keine Entscheidung, eine Tatsache).

## 11. Quality Gates / Definition of Done (je Increment)

```bash
flutter run --dart-define=APP_DISABLE_AUTH=true   # UX offline beweisen (Increment 0)
flutter analyze
flutter test
firebase emulators:start                           # Rules + Callables ab Increment 1/2
```
- Neue Tests: `StoreTask`-Round-trip, `StoreTaskProvider` drei Modi, `kioskBeginSession`/`kioskClockPunch` via `cloudFunctionInvoker`-Seam (inkl. PIN-Falsch/Lockout), Rules gegen `userSecrets`/`kioskSessions`/`kioskRoster` + `role:kiosk` Read-Scope (Emulator). Fakes statt echtem Firebase, `de_DE`.
- Deploy gebündelt: `firebase deploy --only firestore:rules,firestore:indexes` + `--only functions`.
