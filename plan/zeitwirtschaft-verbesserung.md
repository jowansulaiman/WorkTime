# Zeitwirtschaft-Verbesserung — Geräte-Sync, Datenvollständigkeit, Kassen-Zuordnung, Rollen

**Stand:** 2026-07-03 · **Status:** Umsetzung großteils erledigt (ZV-1…ZV-7 code-fertig+getestet; Deploy offen) · **Priorität:** sehr hoch

> **Umsetzungsstand 2026-07-03 (Opus[1M]):** Kern gebaut + getestet — `flutter analyze` clean (nur 1 vorbestehende, fremde Warnung), Flutter-Suite **1424 grün** (+38 neue), Functions **31 grün** (+1). **Fertig:** ClockEntry-Erweiterung (shiftId/source/device/session/korrektur, Kopplung #1 vollständig), purer `dienst_abgleich.dart`-Soll-Ist-Kern (14 Tests), ClockService-Vergessen-Schwelle, Klärung als Monatsabschluss-Blocker (in beide Abschluss-Screens verdrahtet, ZV-5.2), ConnectivityStatusProvider-Härtung (3-Wert-Enum + Reachability-Probe + Debounce + Resume, ZV-1.1, 9 Tests), ZeitwirtschaftProvider (Klärungs-Stream + resolveKlaerung/dismissKlaerung/addManualClockEntry + shiftId-clockIn + Pending-Metadaten + refetch + loadDienstHeute, 6 Tests), Kassen-Personen-Zuordnung `countedByUserId` (Model + Kiosk-Callable via Session-employeeId + App-Pin + Rules-Pin, ZV-4.1), clockEntries-Korrektur-Rules (ZV-3.2), Functions (autoKlaerungNightly onSchedule + kioskClockPunch/-clockOut shiftId + buildAutoKlaerungNotification), Stempel-Screen-UI (Pending-Badge, Quelle Tablet/App, Dienst-heute-Manager-Karte, Klärungs-Inbox mit Resolve-/Verwerfen-Sheet, 4 Widget-Tests). **Offen (bewusst):** ZV-1.3 Web-Multi-Tab-Bootstrap-Entscheid, ZV-1.1-Produktiv-Probe-URL (Mechanik steht, Default null = keine Regression), ZV-1.4 App-Resume-Observer-Verdrahtung (`refetch()` existiert), ZV-4.2/4.3 Kassen-Plausibilisierung/Sicht-Screens, ZV-6.2/6.3 Hub-Gruppen/Monats-Selbstsicht (Hub blendet Admin-Kacheln bereits aus), Kiosk-UI-Schicht-Vorschlag (Callable+Wrapper akzeptieren shiftId schon), ZV-8 **Blaze-Deploy** (rules+indexes+functions) + Emulator-Verifikation + Commit.
**Auftrag (Betreiber):** Zeitwirtschaft verbessern, ergänzen und passend machen. Kernanforderungen: (a) **alle Geräte synchron** — Einstempeln am Kiosk-Tablet ist sofort auf Web/iOS/Android sichtbar und umgekehrt (4 Geräteklassen: Web, iOS, Android, Kiosk-Tablet/Arbeitsmodus); (b) **lückenlose Datenerfassung** für Gehaltsabrechnung, Monatsabschluss usw.; (c) **Mitarbeiter sehen nur eigene Daten** bzw. genau das, was sie sehen sollen; (d) **Kassenabschlüsse werden dem ausführenden Mitarbeiter zugewiesen**; (e) **Datensicherheit + Rollenmodell** (wer sieht/bearbeitet was); (f) UI/UX weder minimal noch überladen; (g) Schichtplan und Personal mitberücksichtigen.

**Modell-Eignung der Arbeitspakete** (vom Betreiber vorgegeben):
- `Geeignet für: Fable 5` — schwierige Analyse, Architektur, komplexe Businesslogik, riskante Mehrdatei-Änderungen, Datenmodellierung, Entscheidungsfindung.
- `Geeignet für: Opus` — klar spezifizierte Implementierung, Tests, UI-Nacharbeiten, Refactors, Dokumentation, Review.
- `Geeignet für: Beide` — Design-Anteil von Fable 5, mechanische Umsetzung danach von Opus möglich.

---

## §0 Verbindliche Vorentscheidungen + Plan-Abgrenzung (NICHT neu verhandeln)

Dieser Plan ist die **Zeitwirtschaft-zentrierte Ergänzung** zu `plan/personal-bereich-ausbau.md` (dort: PA-0…PA-9). Der Personal-Plan hat sich die Stempel-Härtung, die Monats-Festschreibung und das Sicherheits-Fundament bereits **zugewiesen** (dessen §0.7: „keine dritte Parallelbaustelle"). Dieser Plan baut sie darum NICHT nochmal, sondern setzt auf ihnen auf:

| Bereich | Owner (wird DORT gebaut) | Dieser Plan |
|---|---|---|
| Kiosk-Read-Scope, Verträge-Leck, users.settings-Pin | personal-bereich-ausbau **PA-0.1–0.3** | Voraussetzung (ZV-0), hier nur konsumiert |
| `{userId}-open`-Doppel-Stempel-Guard, clockIn/clockOut-Callables (M7b), Legacy-Uhr-Stilllegung, Kiosk-Resilienz/Roster, Reconnect-Refetch, Anwesenheits-Sichten, Klärungs-Push | personal-bereich-ausbau **PA-4.1–4.7** | Voraussetzung (ZV-0); dieser Plan liefert die darauf aufbauenden Zeit-Funktionen |
| Monatsabschluss = echte Festschreibung (Client+Callable+Rules), Pro-MA-Abrechnungssperre | personal-bereich-ausbau **PA-5** | Voraussetzung (ZV-0); hier: Abschluss-Arbeitsliste (ZV-5.2) |
| Lohn-Vervollständigung (Umlagen, Lines-Verrechnung, DATEV-Lohn, Lohnjournal) | personal-bereich-ausbau **PA-6** | unberührt; hier nur §3b-Transparenz-UI (ZV-5.3) |
| Lohnzettel-/Urlaubskonto-Selbstsicht | personal-bereich-ausbau **PA-7** | unberührt |
| Kassenzustand/Kassenabschluss-Modul (cashCounts/cashClosings, M1–M6, E1–E3) | `plan/kassen-modul.md` | dieser Plan definiert **verbindliche Auflagen** an dessen Datenmodell/Rules (ZV-4) — Umsetzung im Kassen-Modul |
| Zeitwirtschaft-Hub-Screens (M1–M6, M7a, M8 fertig) | `plan/zeitwirtschaft-alltec-1zu1.md` | dieser Plan ist die Fortsetzung; M7b gilt nach PA-4.2 als erledigt |
| Entscheidungen E1–E9 + Leitentscheidungen (nur Mantelzeit E2, Sollzeit versioniert E3, §3b voll E9, Abschluss org-weit + Sperre pro MA Nr. 10) | `plan/ida-hr-zeit-uebernahme.md` | gelten unverändert |

Weitere bindende Grundsätze:

1. **Firestore-`snapshots()`-Streams sind der einzige Live-Sync-Mechanismus** (kein Polling, kein Custom-Socket, kein FCM-als-Datentransport). Für Firestore-Daten ist die **eingebaute Offline-Queue** die einzige Outbox — kein Eigenbau (Skill 19/21; `claude-skills/daten/19_datensynchronisierung.md`, `21_offline-modus.md`).
2. **Kiosk-Stempeln ist server-only** (PIN-Prüfung via `kioskClockPunch`-Callable) und damit **offline bewusst gesperrt** — klare deutsche Meldung statt Offline-Queue mit unverifizierter Identität (PA-4.4f). App-Stempeln bleibt offline-fähig über die Firestore-Write-Queue (E-Z1, §3.4).
3. **Geräte-Konto bleibt einzige Firebase-Identität am Kiosk**; die fachliche Person kommt IMMER aus der server-geprüften Session (`kioskSessions.employeeId`) — Muster `kioskClockPunch` gilt auch für die Kassen-Zuordnung (ZV-4).
4. **Rules sind keine Filter:** Jede Read-Verschärfung erfordert zuerst den Client-Umbau auf self-Queries, dann den Rules-Deploy (belegtes Zwei-Schritt-Muster PA-0.2).
5. Mitbestimmungs-/Datenschutz-Leitplanke (analog OktoPOS-Datenwert 3.2): Soll-Ist-/Verspätungs-Sichten (ZV-2.2) sind **operative Tagessichten für Manager**, keine dauerhaft aggregierte Verhaltens-Statistik pro Mitarbeiter; Aufbewahrung von Arbeitszeitnachweisen folgt PA-8.1 (§16 ArbZG: 2 Jahre).

---

## §1 Ist-Befund (belegt, Kurzfassung)

### 1.1 Was schon funktioniert (mehr als erwartet)

- **Stempeluhr ist bereits echtzeitfähig (Cloud-Modus):** `ClockEntry` in `organizations/{orgId}/clockEntries` mit autoritativem `status` (`ongoing/completed/klaerung/deaktiviert`, `lib/models/clock_entry.dart:12`); eigene offene Buchung als Live-Stream `watchOpenClockEntry`, org-weites „wer ist eingestempelt" als `watchOngoingClockEntries` (`lib/services/firestore_service.dart:219/236`, abonniert in `lib/providers/zeitwirtschaft_provider.dart:250-278`).
- **Kiosk→App-Sync funktioniert by design:** `kioskClockPunch` (Callable, Admin SDK, server-geprüfte PIN-Session) schreibt in DIESELBE Collection → App-Streams sehen den Tablet-Stempel sofort. Der Kiosk-Client ruft nur die Callable (`lib/screens/kiosk/kiosk_clock_service.dart:147-186`).
- **Stempel→Lohn-Kette existiert:** clockOut erzeugt `WorkEntry(status: submitted, category: 'stempel', sourceClockEntryId)` über den `_workEntryPoster`-Seam (`zeitwirtschaft_provider.dart:700-730`); Genehmigungs-Workflow `draft→submitted→approved/rejected` inkl. `approveWorkEntry` (`lib/providers/work_provider.dart:636`); Zeitkonto-Snapshots + Monatsabschluss-Validierung/Sperre (`lib/core/monatsabschluss_service.dart`), Entwurfs-Lohndatensatz beim Abschluss (`_payrollDraftPoster`); §3b-Herleitung (`lib/core/lohn_herleitung.dart:58-75`) und Feiertagskalender (`lib/core/feiertage.dart`) vorhanden.
- **Rollen-Grundschnitt der Zeitdaten stimmt schon:** `workEntries`/`clockEntries`/`zeitkontoSnapshots`/`payrollRecords` sind rules-seitig „self ODER canManageShifts/admin" (`firestore.rules:530-626, 909-923`) — Anforderung (c) ist für Zeit-/Lohndaten strukturell erfüllt. Zeit-Routen sauber gestuft (`lib/routing/route_permissions.dart:19-93`; Mitarbeiterabschluss/Lohnlauf admin-only).
- **Offline-Fundament:** Firestore-Offline-Persistence auf Web UND mobil vor dem ersten Read (`lib/main.dart:177-218`); `ConnectivityStatusProvider` existiert (uncommitted, Redesign Phase 0).

### 1.2 Die Lücken (Zielbild-relevant, mit Beleg)

| # | Befund | Beleg |
|---|---|---|
| Z-L1 | **App→Kiosk nicht live:** Kiosk-`_ClockTile` pollt den Stempel-Status 1× pro Session; offline hängt die Kachel (kein try/catch). *(Fix: PA-4.4, ZV-0)* | `kiosk_screen.dart:583`, personal-Plan L7 |
| Z-L2 | **Doppel-Stempeln möglich:** clockIn/clockOut sind Direct-Writes, Guard nur client-seitig (`isClockedIn`), Doc-ID zufällig, kein `{userId}-open`; Kiosk-Guard read-then-write ohne Transaktion. *(Fix: PA-4.1/4.2, ZV-0)* | `zeitwirtschaft_provider.dart:632`, `functions/index.js:1141` |
| Z-L3 | **Monats-/Jahres-Sichten sind Einmal-Reads:** `_loadMonthEntries`/`loadSnapshots`/Org-Loader ohne Invalidierung bei Reconnect/Resume; hybrid-Fallback-Writes (`_persist`-catch) bleiben gerätelokal ohne Rück-Sync. *(Teil-Fix: PA-4.6; Rest hier ZV-1)* | `zeitwirtschaft_provider.dart:294-324, 736-758` |
| Z-L4 | **Konnektivitäts-Signal unehrlich:** `ConnectivityStatusProvider` liest nur den Interface-Status (Captive-Portal-False-Positive), keine Reachability-Probe, kein Resume-Recheck — Skill-21-Verstoß; kein Konsument triggert Refetch. | `lib/providers/connectivity_status_provider.dart:8-12` |
| Z-L5 | **Kein Pending-/Sync-Status sichtbar:** Optimistische Writes (Firestore-Queue) sind vom Server-Stand nicht unterscheidbar; `SnapshotMetadata.hasPendingWrites` wird nirgends ausgewertet → stille Eventual-Consistency (Skill-21-Anti-Pattern). | grep `hasPendingWrites` = 0 Treffer in lib/ |
| Z-L6 | **Stempeln kennt den Schichtplan nicht:** `ClockEntry` hat kein `shiftId`; das aus dem Stempel erzeugte WorkEntry setzt `sourceShiftId` nie → Schicht-Completion-Hook und Soll-Ist-Abgleich laufen am Stempel vorbei; kein Verspätungs-/No-Show-Signal für Manager. | `clock_entry.dart:50-76`, `zeitwirtschaft_provider.dart:703-717` |
| Z-L7 | **Klärungsfälle enden im Nichts:** `status=='klaerung'` wird erzeugt (Vortag-Buchung) und farblich angezeigt, aber es gibt keine Klärungs-Inbox, kein Resolve-Flow, keinen WorkEntry nach Klärung — die Stunden fehlen still in Zeitkonto und Lohn. | `stempel_screen.dart:291,453`; kein Resolve-Mutator im Provider |
| Z-L8 | **Vergessenes Ausstempeln bleibt tagelang offen:** kein Schichtende-Hinweis, keine Auto-Klärung über Nacht — `ongoing`-Buchungen laufen unbegrenzt weiter (Klärung entsteht erst beim manuellen Ausstempeln am Folgetag). | `clock_service.dart` (needsClarification nur bei clockOut) |
| Z-L9 | **Kassenabschluss: keine Personen-Zuordnung, nichts persistiert:** `DailyClosing` ist eine transiente Aggregation der posReceipts ohne jedes Personen-Feld (admin-only Screen, Future-Load). Der Kassen-Modul-Plan sieht nur `countedByLabel` (freier String) + `kioskSessionId` vor — **kein hartes `countedByUserId`**; cashCounts/cashClosings existieren mit 0 Zeilen Code. | `lib/core/daily_closing.dart`, `daily_closing_screen.dart`, `plan/kassen-modul.md` §3.1 |
| Z-L10 | **Festschreibung wirkungslos, Lecks offen** *(Owner: PA-0/PA-5, ZV-0)*: `abgeschlossen`-Flag wird von keiner Rule/Callable geprüft; `employmentContracts` read=sameOrg; users-Self-Update pinnt `settings` nicht; Kiosk-Gerätekonto erbt via `permissionOrDefault`-Fallback Lese-/Schreibrechte (canViewTimeTracking/canEditTimeEntries = isActiveUser-Default). | `firestore.rules:80-114, 414-432, 570-626, 818-824` |
| Z-L11 | **Kein Zeit-Ereignis erreicht abwesende Geräte:** kein Push-Trigger auf clockEntries (Klärung, Auto-Klärung), Monatsabschluss ohne MA-Benachrichtigung. *(Teil-Fix: PA-4.7/PA-7.4; Delta hier ZV-7)* | personal-Plan L8 |
| Z-L12 | **UX-Streuung:** Stempel-Status nur im Stempel-Screen sichtbar (Home-Tab nutzt Legacy-Pfad, bis PA-4.3 greift); Zeit-Hub zeigt allen Rollen dieselben 8 Kacheln (Admin-Kacheln erscheinen als Sackgasse/gesperrt statt ausgeblendet); Monatswerte (Soll/Ist/Saldo/Übertrag) über Stundenkonto/Stempel-Screen verteilt. | `zeitwirtschaft_hub_screen.dart` |

---

## §2 Zielbild

1. **Ein Stempelzustand, überall live und ehrlich:** Jeder Punch (Kiosk oder App) ist innerhalb von Sekunden auf allen angemeldeten Geräten sichtbar; offline getätigte App-Stempel sind als „ausstehend" markiert und synchronisieren automatisch idempotent; das Kiosk sperrt Stempeln offline sichtbar statt zu hängen.
2. **Stempeln kennt die Schicht:** Einstempeln schlägt die heutige Schicht vor (Standort vorbelegt), verknüpft `ClockEntry↔Shift↔WorkEntry`; Manager sehen pro Tag Soll-Ist (verspätet, nicht erschienen, früher gegangen, ungeplant anwesend).
3. **Keine Stunde geht verloren:** Klärungsfälle landen in einer Manager-Inbox mit Resolve-Flow (korrigieren → WorkEntry nacherzeugen); vergessene Ausstempelungen werden nachts automatisch zur Klärung geschlossen und gemeldet; offene Posten (Klärungen, eingereichte Einträge) sind vor dem Monatsabschluss als Arbeitsliste sichtbar. Damit sind die Monatsdaten für Gehaltsabrechnung/Abschluss vollständig und nachvollziehbar (Audit auf jedem Korrekturpfad).
4. **Kassenabschluss trägt den Mitarbeiter:** Jede Kassenzählung/jeder Abschluss ist einem echten `users`-uid zugeordnet (Kiosk: aus der PIN-Session; App: der angemeldete Nutzer), fälschungssicher über den Callable-Pfad, nachträgliche Zuweisung nur admin mit Audit; Plausibilisierung gegen die Anwesenheit („war zur Abschlusszeit eingestempelt").
5. **Rollen-Matrix vollständig und durchgesetzt** (§3.3): Mitarbeiter sehen nur eigene Zeit-/Lohn-/Kassendaten, Teamleads führen operative Zeitkorrekturen aus, Lohn/Abschluss-Hoheit beim Admin, Kiosk-Gerätekonto sieht nichts Sensibles.
6. **UI/UX „genau richtig":** ein wiederverwendbares Live-Stempel-Widget (Home, Zeit-Hub, Kiosk-Parität), rollengerechter Hub (drei Gruppen statt 8 gleichrangiger Kacheln), eine kompakte Monats-Selbstsicht — keine neuen Screens ohne klaren Konsumenten.

**Bewusst NICHT im Zielbild:** GPS-/Geofencing- oder Foto-Verifikation beim Stempeln (Überwachungstiefe unangemessen für 2 Läden); Pausen-Einzelstempel (E2: nur Mantelzeit — Pause bleibt Minuten-Angabe beim Ausstempeln inkl. Auto-Pflichtpause); Offline-Stempeln am Kiosk (§0.2); amtlicher Lohn (bleibt „Richtwert", PA-6); Schichttausch-/Abwesenheits-Logik (eigene Module, fertig); Kassen-Modul-Kernumsetzung (Owner: kassen-modul.md); No-Show-**Push**-Automatik in v1 (E-Z5, Manager-Tagessicht reicht zunächst).

---

## §3 Zielarchitektur

### 3.1 Sync-Matrix der 4 Geräteklassen (Soll)

| Fluss | Heute | Soll (Paket) |
|---|---|---|
| Kiosk-Stempel → Web/iOS/Android | ✅ live (Callable → `clockEntries` → Streams) | bleibt; + Pending-/Quelle-Transparenz (`source:'kiosk'` sichtbar, ZV-6.1) |
| App-Stempel → andere App-Geräte | ✅ live (`watchOpenClockEntry`/`watchOngoingClockEntries`) | bleibt; + `{userId}-open`-Guard (PA-4.1) verhindert Konkurrenz-Doppelstempel |
| App-Stempel → Kiosk | ❌ 1×-Poll pro Session | Status aus Callable-Antwort nach jedem Punch + Refresh bei Session-Start + `kioskPresence`-Stream (PA-4.4/4.5, ZV-0) |
| App-Stempel offline (iOS/Android/Web) | teils: Firestore-Queue puffert, aber unsichtbar; hybrid-Fallback bleibt gerätelokal | Direct-Write über Firestore-Queue = Standard-Offline-Pfad, sichtbar als „ausstehend" (`hasPendingWrites`, ZV-1.2); Callable-first sobald online (PA-4.2); hybrid-Fallback-Rück-Sync bei Reconnect (PA-4.6) |
| Kiosk offline | ❌ Kachel hängt | hart gesperrt mit Meldung „Keine Verbindung – Stempeln derzeit nicht möglich" (PA-4.4f) |
| Monats-/Konto-/Abschluss-Sichten | ❌ Einmal-Reads | gezielter Refetch bei eigenem Punch (existiert), Reconnect (PA-4.6) und **App-Resume (ZV-1.4)**; bewusst KEIN Dauer-Stream über Org-Monatsdaten (Kosten) |
| Zeit-Ereignisse → abwesende Geräte | ❌ | Push als **Benachrichtigung, nie Datentransport**: Klärung→Manager (PA-4.7), Auto-Klärung→MA (ZV-7), Abschluss→MA (PA-7.4) |
| `local`-Speichermodus | per Definition kein Cross-Device | bleibt; dauerhafter Hinweis „Lokaler Modus – keine Geräte-Synchronisation" in Zeit-Screens (PA-2-Muster) |

### 3.2 Datenmodell-Änderungen

**`ClockEntry`-Erweiterung** (Kopplung #1: `toFirestoreMap`/`fromFirestore`/`toMap`/`fromMap`/`copyWith`+clearX, snake_case-Parse in `functions/index.js`):

```
shiftId (String?)        // NEU (ZV-2.1): geplante Schicht, der der Stempel zugeordnet ist
source (String?)         // 'app' | 'kiosk' — kioskClockPunch schreibt es bereits, Dart-Model verliert es (PA-§3.2, hier mitgezogen)
deviceId, sessionId      // dito (Kiosk-Forensik, PA-§3.2)
korrigiertVonUid (String?), korrekturGrund (String?)   // NEU (ZV-3): Korrektur-Historie am Datensatz (zusätzlich zum Audit-Log)
```

Bestehende Felder decken den Rest bereits ab: `siteId/siteName` (Standort), `pauseMinuten`, `nettoMinutes`, `ipKommen/ipGehen`, `manuellErfasst`, `klaerung`, `workEntryId` (Rückverknüpfung — wird ab PA-4.1 endlich gesetzt), `createdByUid`.

**Kassen-Auflage (an `plan/kassen-modul.md` §3.1, dort umzusetzen):** `CashCount` und `CashClosing` erhalten ein **hartes `countedByUserId`/`closedByUserId`** (echte `users`-uid) zusätzlich zu `countedByLabel`; am Kiosk füllt es die Callable aus `kioskSessions/{sid}.employeeId` (Client kann es NICHT setzen), in der App = `request.auth.uid` (Rules-Pin analog `stockMovements.createdByUid`). Nachträgliche Um-Zuweisung: eigener Admin-Mutator mit Audit. → ZV-4.1.

**Neue Composite-Indexes** (`firestore.indexes.json`, mit Rules gebündelt deployen):
- `clockEntries(status ASC, kommen DESC)` — Klärungs-Inbox org-weit (ZV-3.1); nur nötig, falls die Query `where status=='klaerung' orderBy kommen` läuft (Single-Field-Exemptions reichen NICHT bei orderBy auf zweitem Feld).
- `clockEntries(siteId ASC, status ASC)` — Kassen-Plausibilisierung „wer war am Standort eingestempelt" (ZV-4.2).
- Bestand prüfen: `clockEntries(userId, kommen)` ist laut alltec-Plan Teil des ausstehenden Deploy-Satzes.

**Keine neue lokale Collection** (Kopplung #5 unberührt): `clockEntries`-Local-Spiegel existiert (`local_v2`), neue Felder müssen im `toMap`/`fromMap`-Roundtrip mitlaufen (Test!).

### 3.3 Rollen-/Sichtbarkeits-Matrix Zeitwirtschaft (Soll)

Legende: **L** = lesen, **S** = schreiben, **–** = kein Zugriff. „self" = eigener Datensatz. Baut auf der Matrix in personal-bereich-ausbau §3.3 auf und ergänzt die Zeit-/Kassen-Zeilen:

| Datenart | admin | teamlead | employee (self) | employee (fremd) | Kiosk-Gerätekonto |
|---|---|---|---|---|---|
| Stempel live (`clockEntries`, ongoing) | L+S | L+S org-weit | L+S (nur eigener Punch) | – | – (nur Callables + `kioskPresence`-Projektion) |
| Stempel abgeschlossen — **Korrektur** | S | S (operative Korrektur, mit Audit + `korrigiertVonUid`) | **– (E-Z3: keine Self-Korrektur abgeschlossener Buchungen; Antrag an Manager)** | – | – |
| Klärungs-Inbox (ZV-3.1) | L+S | L+S | sieht nur eigene Klärungsfälle (Hinweis, kein Resolve) | – | – |
| Zeiteinträge (`workEntries`) | L+S | L+S org-weit (genehmigen) | L+S self (draft/submitted) | – | – |
| Soll-Ist-Tagesabgleich (ZV-2.2) | L | L | eigener Tages-Status | – | – |
| Stundenkonto (`zeitkontoSnapshots`) | L+S | L+S solange nicht festgeschrieben (PA-5) | L self | – | – |
| Monatsabschluss sperren / **entsperren** | S / S | S / – (Reopen admin-only, PA-5) | – | – | – |
| Lohnlauf (`payrollRecords`) | L+S | – | L self (nur freigegeben/bezahlt, PA-7.1) | – | – |
| Kassenzählung erfassen (`cashCounts`) | L+S | L | S (blind zählen, via Kiosk-Callable oder App self) | – | – (Callable trägt Session-MA) |
| Kassenabschluss (`cashClosings`) | L+S | L | **L self (nur eigene, E-Z4)** | – | – |
| Anwesenheit „wer ist im Dienst" | L | L | eigener Status | – | L (nur `kioskPresence`-Vornamen) |

Durchsetzung dreischichtig (Kopplung #6): UI-Gating (`RoutePermissions` + `AppUserProfile`-Getter) · Provider-Mutator-Guards · `firestore.rules` (+ Callable-Checks). Neu erforderliche Rules-Änderungen: clockEntries-Self-Update auf abgeschlossene Buchungen schließen (ZV-3.2), cashCounts/cashClosings-Blöcke von Tag 1 nach dieser Matrix (ZV-4.1), Kiosk-Denies (PA-0.1). **Zusätzlich (aus Rules-Audit):** die Zeit-Erfassungs-Routen sollten neben `canViewTimeTracking` auch `canEditTimeEntries` fürs Stempeln/Erfassen spiegeln (heute erreicht ein Nur-Leser die Editor-Screens und scheitert erst am Write) → ZV-6.2.

### 3.4 Zeitquelle & Offline-Scoping (Design-Entscheidungen)

- **E-Z1 (Scope, empfohlen so umsetzen):** App-Stempeln ist **read-write-offline** über die eingebaute Firestore-Queue (Direct-Write-Pfad; Callable-first wenn online, PA-4.2). Kiosk-Stempeln ist **server-only** (offline gesperrt, §0.2). Alles andere (Monatslisten, Konten, Abschluss) ist read-only-offline aus dem Firestore-Cache.
- **E-Z2 (Zeitquelle):** `kommen`/`gehen` bleiben **Client-Zeit** — der Punch-Moment ist fachlich die Gerätezeit, `serverTimestamp` würde offline gepufferte Stempel auf den Flush-Zeitpunkt verfälschen. Absicherung gegen Uhr-Drift: Callable-Pfad vergleicht Client-Zeit mit Serverzeit und markiert Abweichung > 10 min als `klaerung` (+ Audit mit beiden Zeiten); `createdAt/updatedAt` bleiben `serverTimestamp` (Beweisanker). Direct-Write-/Offline-Stempel haben diese Prüfung nicht — dokumentierte Restlücke bis Callable-only (E-P4 im Personal-Plan).
- **Konfliktfall Doppelgerät:** gelöst über `{userId}-open` + Transaktions-Guard (PA-4.1) — zweites Einstempeln schlägt fehl statt still zu überschreiben (kein LWW auf kritischen Daten, Skill 19).
- **Web-Eigenheiten:** Persistenz ist Single-Tab-Default; zweiter Tab → `failed-precondition`. Entscheidung ZV-1.3: Multi-Tab-Manager aktivieren ODER graceful degradieren + dokumentieren. Web-IndexedDB ist evictbar → Web gilt NIE als verlässlicher Puffer für ungesyncte Stempel (Banner-Hinweis bei pending > 0 und offline).

---

## §4 Meilensteine & Arbeitspakete

Reihenfolge: **ZV-0 (extern) → ZV-1 → ZV-2 → ZV-3 → ZV-5 → ZV-6 → ZV-7 → ZV-8**; ZV-4 ist ab ZV-0 parallelisierbar (Kassen-Modul-Track). Jedes Paket endet grün auf `flutter analyze` + `flutter test` (+ `node --test` bei Functions-Anteil). **Kleinster lauffähiger erster Schritt:** ZV-2.2a (purer Soll-Ist-Rechenkern, komplett offline testbar mit `APP_DISABLE_AUTH=true`) — kein Deploy, keine Kopplung, unabhängig von ZV-0/ZV-1 sofort startbar.

| Paket | Inhalt | Status |
|---|---|---|
| ZV-0 | Fundament aus Fremdplänen (PA-0, PA-4, PA-5) | teils gelandet (clockEntries `!isKiosk()`/`canManageShifts` vorhanden; {userId}-open-Guard + Callables weiterhin Owner personal-Plan) |
| ZV-1 | Konnektivität ehrlich + Pending-Transparenz + Resume | **ZV-1.1/1.2/1.4 gebaut+getestet** (ZV-1.4: Stempel-Screen `WidgetsBindingObserver` → `refetch()` bei Resume); ZV-1.3 (Web-Multi-Tab-Bootstrap-Entscheid) offen |
| ZV-2 | Schichtplan ↔ Stempeln (Kontext, Soll-Ist, Auto-Klärung) | **gebaut+getestet** (shiftId, dienst_abgleich-Kern, Dienst-heute-Karte, autoKlaerungNightly); Kiosk-UI-Schicht-Vorschlag offen |
| ZV-3 | Klärungs- & Korrektur-Workflow | **gebaut+getestet** (Inbox + Resolve/Verwerfen/Nachtrag + Rules-Härtung) |
| ZV-4 | Kassenabschluss-Zuordnung | **ZV-4.1 gebaut+getestet** (countedByUserId); ZV-4.2/4.3 (Plausibilisierung/Sicht) offen |
| ZV-5 | Payroll-Kette schließen + Abschluss-Arbeitsliste | **ZV-5.2 gebaut+getestet** (Klärungs-Blocker verdrahtet); ZV-5.1/5.3 offen |
| ZV-6 | UI/UX Zeit-Hub | **ZV-6.1 + ZV-6.2 gebaut+getestet** (Live-Stempelkarte-Signale; Hub in 3 Gruppen Mein Tag/Meine Konten/Team & Abschluss, nicht-berechtigte Gruppe ausgeblendet, 2 Widget-Tests); **ZV-6.3 bereits durch bestehende Stundenkonto-`_SummaryCard` abgedeckt** (Soll/Ist/Überstunden/Saldo/Übertrag) — kein Redundanz-Bau |
| ZV-7 | Push-Delta „Zeit-Ereignisse" | **Auto-Klärung-Push gebaut** (buildAutoKlaerungNotification + Nightly); Klärung-gelöst-Push offen |
| ZV-8 | Deploy & Verifikation (gebündelt) | **offen** — Blaze-Deploy (rules+indexes+functions) + Emulator-Verifik. + Commit |

---

### ZV-0 · Fundament (BLOCKIEREND, wird im Personal-Plan gebaut — hier nur Abnahme)

Nicht bauen, sondern **abnehmen**: PA-0.1 (Kiosk-Scope), PA-0.2 (Verträge-Leck, Zwei-Schritt!), PA-0.3 (settings-Pin), PA-4.1–4.7 (open-Guard, Callables, Legacy-Uhr, Kiosk-Resilienz, Presence, Reconnect, Klärungs-Push), PA-5 (Festschreibung). Abnahme-Kriterium je Punkt = die manuelle Matrix in §6. Erst wenn PA-4.1/4.2 stehen, lohnen ZV-2/ZV-3 (sie hängen am einheitlichen Stempel-Pfad).
`Geeignet für: Beide` (Abnahme/Verifikations-Interpretation: Fable 5; Testdurchführung/Doku: Opus)

---

### ZV-1 · Konnektivität ehrlich machen + Sync-Transparenz

**ZV-1.1 Reachability + Resume-Recheck im `ConnectivityStatusProvider`.**
Interface-Signal (connectivity_plus) um echte Reachability-Probe ergänzen (leichtgewichtiger HTTPS-HEAD/GET mit kurzem Timeout; Web nur HTTP wegen CORS — Ziel z. B. das eigene Hosting); Ergebnis als dreiwertiges Enum `online | offline | backendUnreachable`; Statuswechsel 1–3 s entprellen; bei `AppLifecycleState.resumed` erneut prüfen. Probe/Stream bleiben injizierbar (bestehendes Test-Seam). API-kompatibel erweitern (`isOnline` bleibt), damit `AppOfflineBanner`/bestehende Konsumenten nicht brechen. Unit-Tests: Debounce, False-Positive (Interface up, Probe fail), Resume-Recheck.
`Geeignet für: Beide` (Probe-/Debounce-Design + Plattform-Fallstricke: Fable 5; Tests + Banner-Anbindung: Opus)

**ZV-1.2 Pending-Transparenz („ausstehend"-Badge).**
`watchOpenClockEntry`/Monatsliste auf `includeMetadataChanges` + `SnapshotMetadata.hasPendingWrites/isFromCache` auswerten; `ZeitwirtschaftProvider` exponiert `openEntryPending`/`monthHasCachedData`; UI: kleines „ausstehend"-Badge an der Stempel-Karte + „zuletzt aktualisiert"-Zeile an Monats-/Kontolisten, `AppStatusBadge`-Wiederverwendung. Kein Verhalten ändern, nur sichtbar machen (Skill-21-Leitlinie: Eventual Consistency zeigen, keine stillen Zustände).
`Geeignet für: Opus`

**ZV-1.3 Web-Mehr-Tab-Entscheidung + Bootstrap-Verifikation.**
Prüfen, wie `lib/main.dart:177-218` die Web-Persistenz setzt (kIsWeb-Zweig, `persistentLocalCache`); entscheiden: `persistentMultipleTabManager` aktivieren (Chef hat Dashboard + zweiten Tab offen) vs. Single-Tab + graceful `failed-precondition`-Catch. Inkognito/IndexedDB-aus muss graceful online weiterlaufen. Achtung Footgun: Cache-Settings MÜSSEN vor dem ersten Read gesetzt bleiben — Reihenfolge in `main()` nicht verschieben.
`Geeignet für: Fable 5` (Bootstrap-Reihenfolge ist der riskanteste Ort der App)

**ZV-1.4 Resume-Refetch.**
`WidgetsBindingObserver` (App-Ebene oder im Provider): bei `resumed` → `_loadMonthEntries()` + `loadSnapshots(jahr)` + (wenn Manager-Sicht offen) Org-Loader neu; kombiniert mit PA-4.6 (Reconnect-Flanke) sind damit alle Einmal-Read-Sichten selbstheilend. Doppel-Trigger entprellen (resumed + reconnect in kurzer Folge = 1 Refetch).
`Geeignet für: Opus`

---

### ZV-2 · Schichtplan ↔ Stempeln

**ZV-2.2a Purer Soll-Ist-Rechenkern (ERSTER SCHRITT des Plans).**
Neue pure Klasse `lib/core/dienst_abgleich.dart`: Input = Tages-`Shift`-Liste + `ClockEntry`-Liste + genehmigte Abwesenheiten + Toleranzen (aus `OrgSettings`, Default: 5 min Karenz); Output pro Mitarbeiter/Schicht: `puenktlich | verspaetet(minuten) | nichtErschienen | frueherGegangen(minuten) | ungeplantAnwesend | abwesendEntschuldigt`. Kein IO/`now()` (Zeitpunkt injiziert), deterministisch — Muster `ShiftSlotGenerator`. Vollständige Unit-Tests inkl. Über-Mitternacht-Schichten, mehreren Buchungen pro Tag, Abwesenheits-Vorrang.
`Geeignet für: Fable 5` (Matching-Logik Stempel↔Schicht ist die eigentliche Denkarbeit: Mehrfach-Schichten, Standort-Mismatch, Teil-Überdeckung)

**ZV-2.1 Schichtkontext am Stempel.**
`ClockEntry.shiftId` (§3.2, Kopplung #1 — 6 Stellen + snake_case in `functions/index.js`-Helpern von `kioskClockPunch`/neuen clockIn-Callables). Einstempel-Flow (App `stempel_screen` + Kiosk-Kachel): heutige eigene Schicht(en) aus `ScheduleProvider`/Projektion ermitteln → als Vorschlag anzeigen („Frühschicht 08:00–14:00 · Strichmännchen"), `siteId/siteName` vorbelegen, `shiftId` mitschreiben; ohne Schicht → freies Stempeln wie heute (`shiftId=null`, gilt als `ungeplantAnwesend`). clockOut übernimmt `sourceShiftId` ins erzeugte WorkEntry → bestehender Schicht-Completion-Hook greift endlich auch für gestempelte Zeit. Kiosk-Seite: `kioskClockPunch` bekommt optionales `shift_id` (Server validiert: Schicht gehört dem Session-MA und liegt am selben Tag).
`Geeignet für: Beide` (Model-/Functions-Kopplung + Matching-Regeln: Fable 5; UI-Vorschlag + Tests: Opus)

**ZV-2.2b Manager-Tagessicht „Dienst heute".**
Karte im Zeit-Hub + Heute-Tab (nur `canManageShifts`): ZV-2.2a-Ergebnis live aus `ongoingEntries`-Stream + Tages-Shifts + heutigen ClockEntries; Chips je Status (verspätet rot mit Minuten, nicht erschienen, ungeplant). Bewusst NUR Tagessicht (Leitplanke §0.5) — keine Wochen-/Monats-Aggregation pro Person. Mitarbeiter sieht in seiner Stempel-Karte nur den eigenen Status („5 min vor Schichtbeginn").
`Geeignet für: Opus` (Rechenkern existiert dann; reine Verdrahtung + UI)

**ZV-2.3 Auto-Klärung „vergessen auszustempeln".**
(a) **Client-Hinweis:** läuft die eigene Buchung > X min nach Schichtende (oder > 12 h ohne Schicht), zeigt die Stempel-Karte einen Warnhinweis + Push-losen Banner. (b) **Nightly Job:** `onSchedule`-Function (Region `europe-west3`, Blaze — Zielumgebung IST Blaze) schließt um 03:00 alle `ongoing`-Buchungen mit `kommen` vor dem Vortag-Schwellwert auf `status='klaerung'` (`gehen=null` bleibt leer! Nur Status + Anmerkung „automatisch zur Klärung gelegt"), schreibt Server-Audit (PA-8.3-Helper) und stößt Push an MA + Manager an (ZV-7). Idempotent (Query-basiert), Batch-Grenzen beachten. WICHTIG: Auto-Klärung erfasst KEINE Zeiten — die echten Zeiten setzt der Resolve-Flow (ZV-3.1).
`Geeignet für: Beide` (Schwellwert-/Idempotenz-Design + Function: Fable 5; Client-Hinweis + Tests: Opus)

---

### ZV-3 · Klärungs- & Korrektur-Workflow (keine Stunde geht verloren)

**ZV-3.1 Klärungs-Inbox (Manager) + Resolve-Flow.**
Neuer Abschnitt im Zeit-Hub (nur `canManageShifts`, Badge mit Anzahl): Query `clockEntries where status=='klaerung' orderBy kommen desc` (Index §3.2). Resolve-Sheet: korrekte `kommen`/`gehen`/`pauseMinuten` setzen (Vorschlag: Schichtzeiten aus `shiftId`, sonst letzte Werte), Pflicht-`korrekturGrund` → Status `completed`, `korrigiertVonUid` = Akteur, `manuellErfasst=true`, danach WorkEntry über den bestehenden `_workEntryPoster`-Pfad nacherzeugen (läuft durch Compliance!) und `workEntryId` zurückschreiben; alternativ „verwerfen" → `status='deaktiviert'` (z. B. Doppel-Buchung) mit Grund. Audit auf jedem Pfad (deutsche Summaries). Mitarbeiter-Sicht: eigener Klärungsfall erscheint in seiner Monatsliste mit Hinweis „wird vom Team-Lead geklärt".
`Geeignet für: Fable 5` (Resolve-Semantik: Compliance-Re-Validierung, WorkEntry-Nacherzeugung ohne Duplikat via `workEntryId`/`sourceClockEntryId`, Monats-Sperre-Interaktion)

**ZV-3.2 Korrektur-Regeln härten (abgeschlossene Buchungen).**
Rules: clockEntries-`update` für self auf die **offene eigene Buchung + den definierten clockOut-Übergang** beschränken (baut auf PA-4.2-Sonderpfad auf); abgeschlossene/geklärte Buchungen ändert nur noch `canManageShifts` (mit `korrigiertVonUid`-Pflicht ab Client). VORHER Client-Flows prüfen, die heute legitim self-updaten (Zwei-Schritt-Regel §0.4). Mitarbeiter-Wunsch „meine Zeit stimmt nicht" läuft als Korrekturantrag über den bestehenden WorkEntry-Workflow (draft→submitted an Manager) — kein neues Antrags-Model.
`Geeignet für: Fable 5` (Rules-Übergangs-Semantik, Bruchgefahr bestehender Flows)

**ZV-3.3 Manueller Nachtrags-Stempel (Manager).**
„Buchung nachtragen"-Sheet in der Manager-Sicht (MA wählen, kommen/gehen/Pause, Standort, Grund): erzeugt `ClockEntry(manuellErfasst: true, korrigiertVonUid, status: completed)` + WorkEntry-Kette wie ZV-3.1. Deckt „Handy vergessen/Akku leer"-Fälle, damit der Monat vollständig wird.
`Geeignet für: Opus` (Muster aus ZV-3.1 wiederverwenden)

---

### ZV-4 · Kassenabschluss → Mitarbeiter (verbindliche Auflagen an `plan/kassen-modul.md`)

Diese Auflagen werden im Kassen-Modul umgesetzt; dieser Plan definiert das Interface und prüft ab:

**ZV-4.1 Harte Personen-Zuordnung.**
`CashCount.countedByUserId` + `CashClosing.closedByUserId` als echte `users`-uid (§3.2). Kiosk-Pfad: Zählung/Abschluss läuft als **Callable** (`kioskCashCount`-Familie), die uid kommt server-seitig aus `kioskSessions/{sid}.employeeId` — Client-Payload kann sie nicht setzen (sonst fälschbar; Muster `kioskClockPunch`). App-Pfad: Direct-Write mit Rules-Pin `request.resource.data.countedByUserId == request.auth.uid` (Muster `stockMovements.createdByUid`). Nachträgliche Um-Zuweisung: admin-only-Mutator mit Audit („Kassenabschluss vom 02.07. Maria zugewiesen"). Kassen-Modul-Entscheidung E2 („alle MA zählen blind via Kiosk") impliziert: die Kiosk-Callable-Härtung wird von dort-M6 in die v1 vorgezogen.
`Geeignet für: Fable 5` (Sicherheits-/Callable-Design, Rules von Tag 1 nach Matrix §3.3)

**ZV-4.2 Anwesenheits-Plausibilisierung.**
Beim Speichern der Zählung/des Abschlusses prüft der Server (Callable) bzw. der Client (App-Pfad): existiert ein `clockEntries`-Doc des Zählers mit `status=='ongoing'` am `siteId` (Index §3.2) bzw. eine abgeschlossene Buchung, die `countedAt` überdeckt? Ergebnis als `zaehlerWarEingestempelt (bool)` am Datensatz + Warnbadge in der Abschluss-Ansicht („Zähler war nicht eingestempelt") — **Warnung, kein Blocker** (Chef zählt auch mal außerhalb der eigenen Schicht).
`Geeignet für: Beide` (Prüf-Semantik + Index: Fable 5; Badge + Tests: Opus)

**ZV-4.3 Sichtbarkeit der Zuordnung.**
(a) Admin: Kassenabschluss-Liste + Personalakte-Abschnitt „Kassenabschlüsse" (Anzahl/Differenzen je MA, read-only, aus `cashClosings where closedByUserId`). (b) Mitarbeiter: „Meine Kassenabschlüsse" (nur eigene, E-Z4) in der Meine-Akte/Zeit-Bereich — Rules-read self nach M7a-Muster. (c) Kein Kassen-Geld-Betrag aufs Kiosk-Board (Leitlinie „Lohn-/Finanz-Daten nie aufs geteilte Tablet").
`Geeignet für: Opus`

---

### ZV-5 · Payroll-Kette schließen (Stempel → WorkEntry → Zeitkonto → Lohn)

**ZV-5.1 Ketten-Verifikation + Lücken schließen.**
End-to-End-Tests (Fakes + Emulator): Punch → ClockEntry → WorkEntry(submitted, mit `sourceShiftId`/`sourceClockEntryId`) → Genehmigung → Zeitkonto-Snapshot (`zeitkonto_calculator` inkl. Feiertage) → Monatsabschluss → Entwurfs-PayrollRecord. Dabei belegte Detail-Lücken schließen: WorkEntry-Ablehnung (`rejected`) eines Stempel-Eintrags muss am ClockEntry sichtbar werden (Hinweis in Monatsliste statt stilles Loch); Klärungs-Resolve erzeugt den WorkEntry nachträglich (ZV-3.1); `workEntryId`-Rückschreibung als Duplikat-Schutz asserten.
`Geeignet für: Beide` (Fehlerpfad-Semantik rejected↔ClockEntry: Fable 5; Test-Suite: Opus)

**ZV-5.2 Abschluss-Arbeitsliste („offene Posten").**
Im Monatsabschluss-/Mitarbeiterabschluss-Screen vor dem Sperren: Liste aller Blocker mit Absprung — offene Klärungsfälle (→ Inbox ZV-3.1), nicht entschiedene Einträge draft/submitted (→ Genehmigen-Flow), laufende Buchung im Zielmonat. Klärungsfälle werden zusätzlicher Blocker in `MonatsabschlussService.validate` (heute nur draft/submitted, `monatsabschluss_service.dart:75-84`). So wird „Monat vollständig?" eine abarbeitbare Liste statt einer Fehlermeldung.
`Geeignet für: Opus` (Service-Erweiterung trivial, UI klar spezifiziert)

**ZV-5.3 Zuschlags-Transparenz (§3b-Vorschau).**
Stundenkonto-/Monatssicht zeigt aus den genehmigten WorkEntries abgeleitete Nacht-/Sonn-/Feiertagsstunden (bestehende Helfer `lohn_herleitung.dart` + `feiertage.dart`) als Info-Zeile („davon Nacht: 12 h · Sonntag: 6 h") — reine Anzeige, Verrechnung bleibt PA-6.2. Mitarbeiter sieht so, dass seine Zuschlagszeiten erfasst sind (Vertrauens-Feature).
`Geeignet für: Opus`

---

### ZV-6 · UI/UX Zeit-Hub („nicht minimal, nicht überladen")

**ZV-6.1 Eine Live-Stempelkarte für alle Flächen.**
Wiederverwendbares Widget `lib/widgets/stempel_status_card.dart` (aus `stempel_screen`-Logik gehoben, Muster PA-4.5a): Zustand aus `ZeitwirtschaftProvider.openEntry`-Stream — „Eingestempelt seit 08:12 · Strichmännchen · Quelle Tablet" + Pending-Badge (ZV-1.2) + Schicht-Kontext (ZV-2.1) + Klärungs-/Vergessen-Warnung (ZV-2.3a). Eingesetzt auf: Heute-Tab (ersetzt Legacy-Punch nach PA-4.3), Zeit-Hub-Kopf, Stempel-Screen. Ein Zustand, drei Flächen, null Duplikatlogik.
`Geeignet für: Opus`

**ZV-6.2 Rollengerechter Hub + Routen-Feinschliff.**
Hub-Kacheln in drei Gruppen: **Mein Tag** (Stempeln, Zeiterfassung, Abwesenheiten), **Meine Konten** (Stundenkonto, Monatsübersicht), **Team & Abschluss** (nur `canManageShifts`/admin: Dienst heute ZV-2.2b, Klärungs-Inbox ZV-3.1, Mitarbeiterabschluss, Lohnlauf) — nicht berechtigte Gruppen werden AUSGEBLENDET statt gesperrt gezeigt. Erfassungs-/Stempel-Route zusätzlich an `canEditTimeEntries` spiegeln (§3.3-Befund; reine Leser sehen Konten, aber keine Editoren). Kompatibel zum Redesign-Z-Rollout (der bleibt reine Optik; Struktur passiert hier zuerst — Reihenfolge-Auflage wie personal-Plan §7).
`Geeignet für: Opus` (klare Spezifikation; Route-Gating-Muster existiert)

**ZV-6.3 Kompakte Monats-Selbstsicht.**
Ein Monats-Kopf über Stempel-Monatsliste + Stundenkonto: Soll / Ist / Saldo / Übertrag (`carryover` existiert im Provider) / Abwesenheitstage / §3b-Zeile (ZV-5.3) als `AppKontoTile`-Reihe; Monatsnavigation wie heute. Keine neuen Datenquellen — nur Zusammenführung dessen, was verteilt schon berechnet wird.
`Geeignet für: Opus`

---

### ZV-7 · Push-Delta „Zeit-Ereignisse"

Kanal: **`personal` wiederverwenden** (kommt mit PA-3.5; KEIN neuer Kanal — vermeidet die 6 NotificationPrefs-Kopplungsstellen erneut). Delta zu PA-4.7 (Klärung→Manager) und PA-7.4 (Abschluss→MA): (a) Auto-Klärung (ZV-2.3b) pusht an den betroffenen MA („Deine Buchung von gestern wurde zur Klärung gelegt") + Manager-Sammelhinweis; (b) Klärung-gelöst → MA („Deine Zeiten vom 01.07. wurden korrigiert: 8,0 h"). Idempotenz via dedupeKey = clockEntryId+Status. Alles über bestehendes `fanOutPush` + `documentTrigger`-Wrapper.
`Geeignet für: Opus` (Trigger-Template existiert im Push-Plan)

---

### ZV-8 · Deploy & Verifikation (gebündelt, Blaze)

1. **Commit-Hygiene:** Arbeitsbaum trägt uncommittete Phase-0-/Scanner-/MHD-Stände — vor ZV-Beginn trennen und committen (gleiche Auflage wie personal-Plan PA-9.1).
2. `firebase deploy --only firestore:rules,firestore:indexes` — gebündelt: ausstehende alltec-Blöcke (clockEntries/zeitkontoSnapshots/M7a + Index `clockEntries(userId,kommen)`), PA-Blöcke, neue ZV-Indexes (`clockEntries(status,kommen)`, `clockEntries(siteId,status)`), ZV-3.2-Korrektur-Rules, cashCounts/cashClosings-Blöcke (mit Kassen-Modul abgestimmt).
3. `firebase deploy --only functions` — kioskClockPunch-Erweiterung (`shift_id`), Nightly-Auto-Klärung (`onSchedule`, braucht **Blaze** — Zielumgebung ist Blaze), Push-Trigger-Delta, ggf. `kioskCashCount`.
4. Emulator-Verifikation: Doppel-Stempel-Race (2 Geräte), Klärungs-Resolve inkl. WorkEntry-Nacherzeugung ohne Duplikat, Auto-Klärung-Idempotenz (2 Läufe), Kassen-Zuordnung (Kiosk-Session-uid nicht vom Client setzbar), Rules-Matrix §3.3 (admin/teamlead/self/fremd/kiosk je Collection).
5. `APP_PUSH_ENABLED`-Gating unverändert (Push-Delta no-op im Demo-Modus).

`Geeignet für: Beide` (Verifikations-Interpretation: Fable 5; Ausführung/Doku: Opus)

---

## §5 Kopplungs-Check (die 8 CLAUDE.md-Kopplungen)

| # | Kopplung | Betroffen durch | Pflicht |
|---|---|---|---|
| 1 | Model-Feld → 6 Stellen | ZV-2.1 (`shiftId`), ZV-3 (`korrigiertVonUid`/`korrekturGrund`), `source/deviceId/sessionId` | beide Serialisierungen + copyWith(+clearX) + snake_case-Parse in `functions/index.js`; Local-Roundtrip-Test |
| 2 | Compliance-Spiegel | ZV-3.1/ZV-5.1 (WorkEntry-Nacherzeugung läuft durch bestehende Validierung) | KEINE Schwellen-Änderung geplant — Spiegel unangetastet lassen |
| 3 | Enum-Wert | keiner (ClockStatus/WorkEntryStatus unverändert; Soll-Ist-Status ist reines Dart-Ergebnis-Enum ohne Persistenz) | — |
| 4 | Neuer Provider | keiner (alles in bestehenden Providern; ConnectivityStatusProvider existiert bereits in der Kette) | — |
| 5 | Lokale Collection | keine neue; `clockEntries`-Spiegel bekommt neue Felder | `toMap`/`fromMap`-Roundtrip-Test |
| 6 | Neuer Firestore-Write-Pfad | ZV-3 (Korrektur/Resolve), ZV-4 (cashCounts/cashClosings), ZV-2.3b (Nightly) | je: Rules + ggf. Callable + Payload-Format (Callable=snake_case!) synchron; 3 Enforcement-Punkte |
| 7 | Gate-Route/Tab | keiner (keine neue Top-Level-Route; Hub-Abschnitte sind screen-intern; falls Klärungs-Inbox eigene URL bekommt → `AppRoutes`+`_sectionRoute`+`isLocationAllowed`) | bei URL-Entscheid Kopplung ausführen |
| 8 | Functions-Region | ZV-2.3b/ZV-4.1 neue Functions | `europe-west3` = `const REGION` |

---

## §6 Tests & Definition of Done

- **Pro Paket:** `flutter analyze` clean, `flutter test` grün (Fakes, kein echtes Firebase; FakeFirestore-Zahlen als double), Functions mit `node --test`. Coverage-Ziel kritische neue Kerne (dienst_abgleich, Resolve-Flow) ≥ 70 %.
- **Neue Pflicht-Tests:** `dienst_abgleich`-Matrix (pünktlich/verspätet/No-Show/früher/ungeplant/entschuldigt, Über-Mitternacht, Mehrfach-Schicht); ClockEntry-Roundtrip mit neuen Feldern (beide Serialisierungen); Klärungs-Resolve (WorkEntry genau 1×, Audit, Monats-Sperre respektiert); Auto-Klärung idempotent; Konnektivitäts-Provider (Probe-Fail, Debounce, Resume); Pending-Badge (hasPendingWrites-Fake); Kassen-Zuordnungs-Rules (self-Pin, Kiosk-Callable-only, fremd-deny) im Emulator; Route-Gating `canEditTimeEntries`.
- **Manuelle Abnahme-Matrix (Betreiber, alle 4 Geräteklassen):**
  1. Tablet einstempeln → Handy (iOS+Android) + Web zeigen es < 5 s live; ausstempeln am Handy → Tablet-Status stimmt nach Punch/Refresh.
  2. Zwei Geräte gleichzeitig einstempeln → zweites scheitert mit deutscher Meldung (nach ZV-0/PA-4.1).
  3. Handy in Flugmodus einstempeln → „ausstehend"-Badge; online → Badge weg, alle Geräte konsistent, kein Duplikat.
  4. Kiosk offline → Stempel-Kachel gesperrt mit Meldung, kein Hänger.
  5. Ausstempeln „vergessen" → nachts Auto-Klärung, MA + Manager benachrichtigt; Resolve in der Inbox → Stunden erscheinen in Zeitkonto/Monat.
  6. Einstempeln mit geplanter Schicht → Vorschlag mit Standort; „Dienst heute" zeigt Verspätung korrekt.
  7. Kassenabschluss am Kiosk als Maria → Datensatz trägt Marias uid; Mitarbeiter Peter sieht ihn NICHT, Maria sieht ihren eigenen; nicht eingestempelter Zähler → Warnbadge.
  8. Employee-Login: sieht ausschließlich eigene Stempel/Konten/Lohnzettel/Kassenabschlüsse; Deep-Link auf Manager-Routen → Redirect `/`.
  9. Festgeschriebener Monat verweigert Nachbuchung/Korrektur auf allen Pfaden (nach PA-5).

## §7 Offene Entscheidungen (Betreiber)

| ID | Frage | Empfehlung |
|---|---|---|
| E-Z1 | App-Stempeln offline erlauben (Firestore-Queue + Pending-Badge) oder server-only wie Kiosk? | **Offline erlauben** — Ladenkeller/Funkloch darf Stempeln nicht verhindern; Drift-Risiko über E-Z2 abgefedert |
| E-Z2 | Zeitquelle Client-Zeit + Server-Drift-Check (>10 min → Klärung) ok? | **Ja** (§3.4); Alternative serverTimestamp verfälscht Offline-Stempel |
| E-Z3 | Darf der MA eigene abgeschlossene Buchungen selbst korrigieren? | **Nein** — Korrekturantrag über WorkEntry-Workflow; Manager korrigiert mit Grund (revisionssicher) |
| E-Z4 | Sieht der MA seine eigenen Kassenabschlüsse (Beträge/Differenzen)? | **Ja, nur eigene** (Transparenz bei Differenzen); Betreiber kann auf admin-only stellen |
| E-Z5 | No-Show-Push an Manager X min nach Schichtbeginn ohne Einstempeln? | **v1 nein** (Scheduler-Polling alle 5–10 min nötig; „Dienst heute"-Karte deckt es); als v2 hinter Entscheid |
| E-Z6 | Toleranz-Schwellen (Verspätungs-Karenz 5 min, Auto-Klärung 03:00/Volltag) als `OrgSettings`-Felder editierbar? | **Ja, mit Defaults** — kein UI-Zwang in v1, Felder von Tag 1 im Model |

## §8 Sequenzierung mit anderen Plänen

- **personal-bereich-ausbau.md:** PA-0/PA-4/PA-5 sind Blocker (ZV-0). ZV-Pakete dort NICHT doppeln; nach PA-4.2 M7b im alltec-Plan als erledigt markieren (dortige §7-Auflage).
- **kassen-modul.md:** ZV-4-Auflagen (countedByUserId/closedByUserId, Kiosk-Callable in v1, Rules-Matrix, Plausibilisierungs-Feld) VOR dessen M1-Umsetzung dort einarbeiten — Querverweis statt Duplikat.
- **zeitwirtschaft-alltec-1zu1.md:** dieser Plan ist die Fortsetzung; Deploy-Reste laufen gebündelt in ZV-8.
- **redesign-gesamt.md:** Zeit-Rollout (Teil C „Zeit") erst NACH ZV-6 (Struktur vor Optik — gleiche Regel wie personal-Plan §7).
- **push-benachrichtigungen-plan.md:** ZV-7 nutzt Kanal `personal` (PA-3.5) — Ereignis-Katalog dort um die zwei Zeit-Ereignisse ergänzen.

## §9 Memory-/Plan-Pflege

Nach jedem Meilenstein: Status-Spalte in §4 aktualisieren, Memory-Eintrag `zeitwirtschaft-verbesserung-plan` pflegen, betroffene Fremd-Pläne (§8) mit Querverweis versehen statt Inhalte zu duplizieren.
