# WorkTime — Vollständiges UI-Inventar

> Automatisch aus dem Quellcode extrahiert (`lib/screens`, `lib/widgets`, `lib/routing`, `lib/core/app_config.dart`). Erfasst **jede sichtbare und versteckte Oberfläche**: die 7 Shell-Tabs mit ihren Hubs, alle Section-Routen, Detail-Tabs, Sheets & Dialoge, den Kiosk-Vollbildmodus, die öffentlichen Web-Routen und die Gate-Screens.

| Kennzahl | Wert |
|---|--:|
| Cluster | 14 |
| UI-Bereiche | 156 |
| Unterbereiche / Tabs | 431 |
| Sheets & Dialoge | 251 |
| Versteckte / gegatete Elemente | 644 |

**Zugriffs-Hinweis:** Rollen-/Berechtigungsangaben stammen aus den `if`-Bedingungen bzw. `canX`-Gettern im Screen-Code. Maßgeblich für das echte Gating bleiben `lib/routing/route_permissions.dart` (Client) und `firestore.rules` (Server).

---

## Inhalt

1. [Shell + Heute-Tab + Navigation](#cluster-1) — 22 Bereiche
2. [Plan / Schichtplanung](#cluster-2) — 10 Bereiche
3. [Zeit / Zeitwirtschaft](#cluster-3) — 11 Bereiche
4. [Anfragen / Inbox / Mitteilungen](#cluster-4) — 4 Bereiche
5. [Kontakte (Liste + Detail 7 Tabs + Editor)](#cluster-5) — 6 Bereiche
6. [Warenwirtschaft Kern (Inventar/Bestellungen/Inventur)](#cluster-6) — 26 Bereiche
7. [Warenwirtschaft Scanner + Kunde](#cluster-7) — 8 Bereiche
8. [Kasse & Buchhaltung](#cluster-8) — 5 Bereiche
9. [Paketshop](#cluster-9) — 6 Bereiche
10. [Personal / HR (Detail 9 Tabs)](#cluster-10) — 14 Bereiche
11. [Personal Auswertungen + Reporting](#cluster-11) — 5 Bereiche
12. [Profil / Einstellungen / Wissen / Protokoll / Passwörter](#cluster-12) — 13 Bereiche
13. [Kiosk / Arbeitsmodus (Vollbild-Tablet)](#cluster-13) — 14 Bereiche
14. [Öffentliche Web-Routen + Gate-Screens + Signage](#cluster-14) — 12 Bereiche

---

<a id="cluster-1"></a>

## 1. Shell + Heute-Tab + Navigation

*22 Bereiche.*

### App-Shell (HomeScreen-Gerüst) · `tab-hub`

**Route:** `— (StatefulShellRoute.indexedStack, 7 Branches)`  
**Zugriff:** authentifiziert + aktiv (Gate-Redirect); Tab-Sichtbarkeit je Recht  
**Feature-Flag:** RedesignFlags V1/V2 (RedesignFlags.isOn) steuert Layout (V1 NavigationBar/-Rail vs. V2 AppNavRail/Slide-in-Menü)

**Unterbereiche / Tabs (3)**

- **7 Shell-Branches** — ShellTab-Reihenfolge = Branch-Index: Heute · Plan · Zeit · Anfragen · Kontakte · Laden · Profil. Lazy IndexedStack, state-erhaltend.
- **Layout-Umschaltung** — BottomNav < 600 Breite; NavigationRail 600–839 (nur ausgewähltes Label) + Höhen-Guard; volle Rail-Labels >=840.
- **Cross-Tab-Zurück** — _navHistory + PopScope + _ShellScope-InheritedWidget; Zurück-Chevron im Tab-Header, System-Pop-Fallback.

**Aktionen (2)**

- Strg/Ctrl+1..9 springt auf n-te sichtbare Nav-Destination (layoutabhängig)
- Tab-Wechsel via goBranch; Re-Tap des aktiven Tabs setzt Branch auf Wurzel zurück

**Sheets & Dialoge (2)**

- Schnellaktionen-Sheet (Planner/Employee) über Shell-FAB
- V2 Slide-in-Menü (drawer mobil / endDrawer Rail)

**Versteckt / gegatet (2)**

- ⨯ Profil-Tab in V2 aus der Nav ausgeblendet (durch Slide-in-Menü ersetzt) — _isTabVisible-Sonderfall
- ⨯ Alle Tabs außer Heute/Anfragen sind permission-gegatet über RoutePermissions.isShellTabAllowed

> Shell rebuildet eng gescopt nur bei Profil-/Storage-/Inbox-Badge-Änderung.

### Untere Navigationsleiste V1 · `widget`

**Route:** `— (bottomNavigationBar)`  
**Zugriff:** permission-gefilterte Branch-Leiste (nur erlaubte Tabs)  
**Feature-Flag:** nur wenn RedesignFlags V1 (useV2=false)

**Unterbereiche / Tabs (1)**

- **Dynamische Ziele** — Alle sichtbaren ShellTabs inkl. Profil; Anfragen-Icon trägt Zähler-Badge (offene Inbox-Aktionen).

**Aktionen (1)**

- NavigationDestination-Tap → Branch-Wechsel

**Versteckt / gegatet (1)**

- ⨯ Text-Scaling hart auf 1,0 geklemmt (einzeilig)

> Icons: Heute(home) Plan(view_timeline) Zeit(schedule) Anfragen(inbox+Badge) Kontakte(contacts) Laden(storefront) Profil(person).

### Untere Navigationsleiste V2 (feste 5er-Leiste) · `widget`

**Route:** `— (bottomNavigationBar)`  
**Zugriff:** Heute/Anfragen/Mehr immer; Plan nur canViewSchedule; Scanner nur mit Scanner-Recht  
**Feature-Flag:** nur wenn RedesignFlags V2 (useV2=true)

**Unterbereiche / Tabs (5)**

- **Heute** — Branch-Wechsel (home).
- **Plan** — Branch-Wechsel, nur wenn ShellTab.plan erlaubt (view_timeline).
- **Scanner** — KEIN Branch — pusht AppRoutes.scanner; nur wenn Scanner-Route erlaubt (qr_code_scanner).
- **Anfragen** — Branch-Wechsel, Inbox-Badge (inbox).
- **Mehr** — Öffnet das Slide-in-Menü (menu-Icon) — kein Branch.

**Aktionen (1)**

- _handleBottomNavTap: branch→goBranch, scanner→context.push, more→openDrawer

**Sheets & Dialoge (1)**

- Slide-in-Menü (über »Mehr«)

**Versteckt / gegatet (2)**

- ⨯ Plan/Scanner schrumpfen die Leiste weg, wenn Recht fehlt
- ⨯ Aktiver Branch außerhalb der Leiste (Zeit/Kontakte/Laden über Mehr) markiert »Mehr«

> Text-Scaling moderat auf 1,3 gedeckelt (Accessibility).

### Navigations-Rail V1 · `widget`

**Route:** `— (Row-Leading bei useRail && V1)`  
**Zugriff:** permission-gefilterte Ziele ohne Profil (Profil im Leading-Header)  
**Feature-Flag:** nur RedesignFlags V1 + Rail-Breakpoint

**Unterbereiche / Tabs (2)**

- **Leading** — AppLogo + _RailProfileHeader (Avatar-Initiale, Rolle, »Profil«-Button → aktiviert Profil-Branch).
- **Trailing** — Logout-IconButton (Tooltip »Abmelden« bzw. »Profil wechseln« im authDisabled-Modus).

**Aktionen (3)**

- Rail-Destination-Tap → Branch
- Profil-Header-Tap → Profil-Branch
- Logout-Button → signOut

**Versteckt / gegatet (1)**

- ⨯ Profil erscheint NICHT als Rail-Item, sondern nur als Leading-Header

> minWidth 124 für 96px-Profil-Header; Badge am Anfragen-Icon.

### Navigations-Rail V2 (AppNavRail, Signal-Teal) · `widget`

**Route:** `— (Row-Leading bei useRail && V2)`  
**Zugriff:** permission-gefilterte Bereiche (railDestinations ohne Profil)  
**Feature-Flag:** nur RedesignFlags V2 + Rail-Breakpoint

**Unterbereiche / Tabs (4)**

- **Brand** — AppLogo im getönten Container oben.
- **Suchen** — _RailUtilityButton öffnet globale Suche (showGlobalSearch).
- **BEREICHE-Liste** — Nav-Items mit animiertem Teal-Indikator + Badge (Anfragen); volle Labels ab 840, sonst Icon+Label gestapelt.
- **Account-Button** — Avatar mit Gradient-Ring + Rolle/»Menü« → öffnet endDrawer (Slide-in-Menü).

**Aktionen (3)**

- Item-Tap → onSelected/Branch
- Suchen → globale Suche
- Account-Button → Menü öffnen (endDrawer)

**Sheets & Dialoge (1)**

- Slide-in-Menü (endDrawer)

**Versteckt / gegatet (2)**

- ⨯ themeAction (Hell/Dunkel) optional, hier bewusst NICHT übergeben — Theme nur unter Profil
- ⨯ Hell/Dunkel liegt bewusst nicht in der Rail

> Breite 216 (expanded) bzw. 104; rein präsentational (Daten+Callbacks herein).

### V2 Slide-in-Menü / »Mehr« (AppNavMenu) · `modal-sheet`

**Route:** `— (Scaffold drawer links / endDrawer rechts)`  
**Zugriff:** gruppen- und rollengegatet (isAdmin, canViewReports, canViewInventory, canManageInventory, canViewTimeTracking, canViewContacts)  
**Feature-Flag:** nur RedesignFlags V2

**Unterbereiche / Tabs (6)**

- **Profil-Kopf** — _ProfileHeader: Avatar, Name, Rolle · Stammstandort, Soll/Tag + Urlaubstage-Chips, »Menü schließen«-Button (X).
- **Arbeitsbereiche** — Nur im mobilen drawer (showAreas): Zeit (canViewTimeTracking), Kontakte (canViewContacts), Laden (canViewInventory). Aktiver Bereich hervorgehoben.
- **Laden & Bestand** — Warenwirtschaft (canViewInventory), Scanner (showScanner && canManageInventory), Kundenbestellungen (canViewInventory), Bestell-Auswertung (canViewInventory).
- **Verwaltung** — Personal (isAdmin), Buchhaltung (isAdmin).
- **Auswertungen** — Monatsbericht + Statistiken (beide canViewReports).
- **Konto & Hilfe** — Meine Akte (optional onOpenMeineAkte), Einstellungen (immer), Wissen & Hilfe (optional onOpenKnowledge).

**Aktionen (2)**

- Jeder Menüpunkt: Drawer schließen dann context.push/Branch-Wechsel
- Abmelden/Profil-wechseln-Button unten (scrollunabhängig)

**Versteckt / gegatet (4)**

- ⨯ Arbeitsbereiche-Gruppe nur im mobilen drawer (showAreas=true), in der Rail (endDrawer showAreas=false) versteckt, da schon in der Leiste
- ⨯ Scanner-Eintrag nur showScanner && canManageInventory
- ⨯ Verwaltung (Personal/Buchhaltung) nur isAdmin
- ⨯ Meine Akte / Wissen nur wenn Callback gesetzt

> Rein präsentational; Buchhaltung (AppRoutes.finance) ist NUR hier erreichbar, nicht im Laden-Hub.

### V2 Top-Bar (_V2MenuTopBar) · `widget`

**Route:** `— (Scaffold.appBar bei V2 && !Rail)`  
**Zugriff:** alle (mobil V2); Warenkorb nur canViewInventory  
**Feature-Flag:** nur RedesignFlags V2 im BottomNav-Modus

**Aktionen (3)**

- Menü-Button (links) → Drawer öffnen
- Suchen-IconButton → globale Suche
- Warenkorb-IconButton (mit Stück-Badge) → context.push /warenwirtschaft?tab=korb

**Sheets & Dialoge (1)**

- globale Suche

**Versteckt / gegatet (2)**

- ⨯ Warenkorb-Knopf nur mit canViewInventory (Stück-Badge nur bei count>0)
- ⨯ Hell/Dunkel bewusst NICHT in der App-Leiste

> Bewusst ohne Titel; Abschnittstitel kommt vom SectionHeader jedes Tabs.

### Speichermodus-/Sync-Banner (_ShellStatusBanner) · `widget`

**Route:** `— (oben in der Shell)`  
**Zugriff:** alle

**Aktionen (1)**

- »Jetzt synchronisieren«-Button (nur bei ausstehenden Löschungen/Tombstones) → work+schedule.syncLocalStateToCloud

**Versteckt / gegatet (2)**

- ⨯ Nur sichtbar bei: lokalem Modus / Fehler / Laden / ausstehenden Löschungen — sonst SizedBox.shrink
- ⨯ Sync-Button nur wenn pendingDeletions>0

> Texte: »Lokaler Modus aktiv…«, »Daten werden aktualisiert«, Fehlermeldung, »N ausstehende Löschungen…«.

### Offline-Banner (AppOfflineBanner) · `widget`

**Route:** `— (oben in der Shell)`  
**Zugriff:** alle

**Versteckt / gegatet (1)**

- ⨯ Nur bei fehlender Verbindung; im lokalen Modus bewusst unterdrückt (redundant zum Speichermodus-Banner)

> Konnektivitäts-Abhängigkeit wird nur außerhalb des local-Modus registriert.

### Shell-FAB (Stempeluhr + Aktionen) · `widget`

**Route:** `— (floatingActionButton)`  
**Zugriff:** nur auf Tabs mit showFab (Heute/Plan/Zeit/Anfragen); Stempeluhr nur canEditTimeEntries

**Unterbereiche / Tabs (2)**

- **Aktionen-FAB** — Runder bolt-FAB: canManageShifts→Planner-Schnellaktionen, sonst Employee-Schnellaktionen.
- **Stempeluhr-FAB** — Extended-FAB grün »Einstempeln« / rot »Ausstempeln« je isClockedIn → context.push /zeit stempeln.

**Aktionen (2)**

- Aktionen-FAB → Schnellaktionen-Sheet
- Stempeluhr-FAB → Stempel-Screen (disabled ohne currentUser)

**Sheets & Dialoge (2)**

- Planner-Schnellaktionen-Sheet
- Employee-Schnellaktionen-Sheet

**Versteckt / gegatet (2)**

- ⨯ Stempeluhr-FAB nur bei canEditTimeEntries; ohne das Recht bleibt nur der Aktionen-FAB
- ⨯ Kein FAB auf Kontakte/Laden/Profil (showFab=false)

> Nebeneinander in einer Row (Höhe wie ein einzelner FAB).

### Schnellaktionen-Sheet (Planner/Admin/Teamlead) · `modal-sheet`

**Route:** `— (Sheet, imperativ)`  
**Zugriff:** canManageShifts

**Aktionen (10)**

- Zeiterfassung und Stunden (wenn Zeit-Tab da)
- Offene Anfragen prüfen (wenn Inbox-Tab da)
- In den Warenkorb (canViewInventory) → showQuickAddCartSheet
- Kühlschrank nachfüllen (canViewInventory) → showFridgeRefillAddSheet
- Krankmeldung an Admin / Urlaub anfragen / Nicht verfügbar (nur isTeamLead) → showAbsenceRequestSheet
- Personal → AppRoutes.personal
- Kennzahlen (isAdmin || canManageShifts) → AppRoutes.kennzahlen
- Standortvergleich (isAdmin) → AppRoutes.standortvergleich
- Mitteilungen (mit Ungelesen-Zähler) → AppRoutes.mitteilungen
- Monatsbericht (canViewReports) → AppRoutes.monthReport

**Sheets & Dialoge (3)**

- Warenkorb-Sheet
- Kühlschrank-Sheet
- Abwesenheits-Sheet

**Versteckt / gegatet (2)**

- ⨯ Teamlead-Abwesenheitsaktionen nur isTeamLead
- ⨯ Kennzahlen nur isAdmin||canManageShifts; Standortvergleich nur isAdmin; Warenkorb/Kühlschrank nur canViewInventory; Monatsbericht nur canViewReports

> Titel »Schnellaktionen«; Mitteilungen-Titel zeigt (N) bei ungelesenen.

### Schnellaktionen-Sheet (Mitarbeiter) · `modal-sheet`

**Route:** `— (Sheet, imperativ)`  
**Zugriff:** Nicht-canManageShifts

**Aktionen (6)**

- In den Warenkorb (canViewInventory)
- Kühlschrank nachfüllen (canViewInventory)
- Arbeitszeit erfassen (canEditTimeEntries) → EntryFormScreen
- Krank melden → Abwesenheits-Sheet
- Urlaub anfragen → Abwesenheits-Sheet
- Mitteilungen (mit Zähler) → AppRoutes.mitteilungen

**Sheets & Dialoge (4)**

- Warenkorb-Sheet
- Kühlschrank-Sheet
- Abwesenheits-Sheet
- EntryFormScreen (Navigator.push)

**Versteckt / gegatet (1)**

- ⨯ Warenkorb/Kühlschrank nur canViewInventory; Zeit erfassen nur canEditTimeEntries

> Untertitel »Die häufigsten Aufgaben direkt mit einer Hand auslösen.«

### Heute-Tab: Mitarbeiter-Dashboard · `section-screen`

**Route:** `— (Shell-Branch Heute, Nicht-canManageShifts)`  
**Zugriff:** jeder Nicht-Planer; einzelne Karten permission-gegatet  
**Feature-Flag:** V1 (_EmployeeDashboardTab) vs. V2 (_EmployeeDashboardTabV2) via RedesignFlags

**Unterbereiche / Tabs (9)**

- **Hero-Karte** — Nächste Schicht / »Heute ohne geplante Schicht«, Ein-/Ausstempeln-Button → /zeit stempeln, Details-Button (Schichtdetail-Sheet).
- **Hinweise & Aktionspunkte** — DashboardActionItemsCard (nur canViewInventory).
- **Schnellaktionen-Grid** — Krank melden, Urlaub anfragen, Zeit erfassen (nur canEditTimeEntries).
- **Deine Woche** — _EmployeeWeekStrip (nur canViewSchedule), 7-Tage-Streifen.
- **Offene Aufgaben** — Nur wenn offene Abwesenheiten/Tauschanfragen (_ActionStateTile).
- **Stempeluhr-Widget** — _ClockInOutWidget mit Ein-/Ausstempeln, Korrigieren-Dialog.
- **Wochenfortschritt** — _WeeklyProgressWidget (Soll/Ist Balken).
- **Monats-Summary** — Stunden, Soll/Ist, Überstunden, Bruttolohn (nur hourlyRate>0).
- **Nächste Schichten / Letzte Einträge** — Je bis 5 Einträge, Schicht-Tap → Detail-Sheet.

**Aktionen (4)**

- Krank/Urlaub → Abwesenheits-Sheet
- Zeit erfassen → EntryFormScreen
- Ein-/Ausstempeln → Stempel-Screen
- Schicht-Tile → Schichtdetail-Sheet

**Sheets & Dialoge (4)**

- Abwesenheits-Sheet
- EntryFormScreen
- Schichtdetail-Sheet
- Stempeluhr-Korrektur-Dialog

**Versteckt / gegatet (5)**

- ⨯ Zeit-erfassen-Kachel nur canEditTimeEntries
- ⨯ Deine-Woche nur canViewSchedule
- ⨯ Offene-Aufgaben-Karte nur bei vorhandenen offenen Anträgen/Tausch
- ⨯ Bruttolohn-Karte nur bei hourlyRate>0
- ⨯ Letzte-Einträge/Summary nur bei canViewTimeTracking||canViewReports

> SectionHeader »Heute«. V2 nutzt lib/ui-Komponenten, Texte byte-gleich zu V1.

### Heute-Tab: Admin/Planer-Dashboard · `section-screen`

**Route:** `— (Shell-Branch Heute, canManageShifts)`  
**Zugriff:** canManageShifts; einzelne Kacheln isAdmin  
**Feature-Flag:** V1 (_AdminDashboardTab) vs. V2 (_AdminDashboardTabV2)

**Unterbereiche / Tabs (8)**

- **Hero »Filialbetrieb im Blick«** — Kennzahl-Chips: aktiv, offen, Tausch.
- **Hinweise & Aktionspunkte** — DashboardActionItemsCard.
- **Jetzt im Dienst** — _JetztImDienstCard (nur V2) — Live-Anwesenheit; blendet sich aus wenn niemand eingestempelt.
- **Schnellaktionen** — Plan öffnen, Personal verwalten (isAdmin), Anfragen prüfen (context.go Inbox).
- **Metrik-Kacheln** — Aktive Mitarbeiter, Offene Einladungen, Schichten heute, Erledigt, Noch offen, Offene Abwesenheiten.
- **Heute priorisieren** — Entscheidungen offen + freie/unbesetzte Schichten (V2: Tap → Anfragen).
- **Nächste Schichten / Entscheidungen** — bis 8 Schichten (Tap → Detail-Sheet »Im Schichtplan bearbeiten«); Manager-Entscheidungsliste.
- **Team-Kalender** — _TeamCalendarWidget.

**Aktionen (4)**

- Plan öffnen → Plan-Tab
- Personal verwalten → AppRoutes.personal
- Anfragen prüfen → Inbox-Branch
- Schicht-Tile → Schichtdetail-Sheet (Planner-Variante)

**Sheets & Dialoge (1)**

- Schichtdetail-Sheet

**Versteckt / gegatet (2)**

- ⨯ Personal-verwalten-Kachel nur isAdmin
- ⨯ Jetzt-im-Dienst nur V2 und nur wenn eingestempelte Einträge (canManageShifts-Stream)

> SectionHeader »Heute«; max 1160 Breite.

### Hinweise & Aktionspunkte-Karte (DashboardActionItemsCard) · `widget`

**Route:** `— (auf Heute-Dashboards)`  
**Zugriff:** nur canViewInventory

**Aktionen (3)**

- Überfällige/bald fällige Bestellungen → AppRoutes.customerOrders
- Nachzubestellende Artikel → AppRoutes.inventory
- Fehlende Kühlschrank-Getränke → /warenwirtschaft?tab=kuehl

**Versteckt / gegatet (3)**

- ⨯ Ganze Karte versteckt wenn keine Warnungen ODER kein Inventar-Recht (SizedBox.shrink)
- ⨯ Kühlschrank-Warnung nur für eigene Läden (siteAssignments), sonst org-weit
- ⨯ »Vor Ladenschluss«-Boost nur wenn Laden bald schließt (Öffnungszeiten)

> Severity-sortiert; ersetzt frühere Einzel-Banner.

### Team-Kalender (_TeamCalendarWidget) · `widget`

**Route:** `— (im Admin-Dashboard)`  
**Zugriff:** canManageShifts (im Admin-Dashboard eingebettet)

**Unterbereiche / Tabs (4)**

- **Wochen-Navigation** — Vorherige/Nächste Woche, »Diese Woche«.
- **Metrik-Pills** — im Dienst / abwesend / frei + Legende (Schicht/Urlaub/Krank/Nicht verfügbar).
- **Kalender-Ansicht** — < 840 Breite: Karten (_buildMobileCalendar mit Tages-Chips); >=840: scrollbare Tabelle (Mitarbeiter × Tage).
- **Tagesdetails** — Schichten- und Abwesenheiten-Panel für den gewählten Tag.

**Aktionen (2)**

- Tag-/Zelle-Tap → Tag auswählen
- Wochenpfeile / »Diese Woche«

**Versteckt / gegatet (2)**

- ⨯ Leerer Zustand »Keine aktiven Mitarbeiter«
- ⨯ Mobile-Kartenansicht vs. Tabelle je Breakpoint 840

> Zellen mit Tooltip; Farbcodierung je Status (frei/Schicht/Urlaub/Krank/nicht verfügbar).

### Stempeluhr-Widget + Korrektur (_ClockInOutWidget) · `widget`

**Route:** `— (auf Mitarbeiter-Dashboard)`  
**Zugriff:** Mitarbeiter; Stempeln nur mit Primärstandort + laufender Schicht

**Unterbereiche / Tabs (1)**

- **Status/Beginn/Ende/Dauer** — Im Dienst / Aus Eintrag aktiv / Nicht aktiv; Beginn/Ende/Dauer + Pausen-Label.

**Aktionen (2)**

- Einstempeln/Ausstempeln → _handlePunchClockAction (Overtime-Dialog möglich)
- Korrigieren → _ClockCorrectionDialog (Start/Ende Zeit-Picker + Pflicht-Begründung)

**Sheets & Dialoge (2)**

- Stempeluhr-Korrektur-Dialog
- Überstunden-Bestätigungs-Dialog (»Arbeitszeit verlängern?«)

**Versteckt / gegatet (3)**

- ⨯ Korrigieren-Button nur bei vorhandenem Stempeluhr-Eintrag (note enthält »Stempeluhr«)
- ⨯ Hinweis »Check-in nur während laufender Schicht« bzw. »Primärstandort erforderlich«
- ⨯ Button disabled ohne canUseClock

> Über-Mitternacht-Ende wird auf Folgetag geschoben.

### Laden-Hub (_ShopHubTab) · `section-screen`

**Route:** `— (Shell-Branch Laden)`  
**Zugriff:** Laden-Tab: canViewInventory (RoutePermissions); Kacheln je Recht  
**Feature-Flag:** Displays & Werbung nur AppConfig.signageEnabled

**Unterbereiche / Tabs (4)**

- **Warenwirtschaft-Hero** — Nur canViewInventory: Bestände-Status-Badges (knappe Artikel, offene Bestellungen, überfällige/offene Pakete), »Warenwirtschaft öffnen« → AppRoutes.inventory.
- **Tagesgeschäft** — Kundenbestellungen (canViewInventory, Badge »N offen«), Paketshop (canViewParcels, Badge »N überfällig/offen«).
- **Auswertungen & Kasse** — Bestell-Auswertung (canViewInventory), Kassenbericht (isAdmin).
- **Verwaltung** — Personal (isAdmin), Kundenfeedback (canManageFeedback), Displays & Werbung (isAdmin && signageEnabled), Änderungsprotokoll (isAdmin).

**Aktionen (1)**

- Kachel-Tap → context.push jeweilige AppRoute (customerOrders, paketshop, orderAnalytics, kassenbericht, personal, feedbackInbox, signage, auditLog, inventory)

**Versteckt / gegatet (5)**

- ⨯ Ganze Sektionen erscheinen nur wenn nicht leer
- ⨯ Kassenbericht/Personal/Änderungsprotokoll nur isAdmin
- ⨯ Kundenfeedback nur canManageFeedback
- ⨯ Paketshop nur canViewParcels
- ⨯ Displays & Werbung nur isAdmin && AppConfig.signageEnabled

> Bündelt Geschäftsmodule; Live-Badges rein In-Memory (offline/Demo-sicher).

### Profil-Hub (_ProfileHubTab) · `section-screen`

**Route:** `— (Shell-Branch Profil; in V2 nur via Menü/Rail)`  
**Zugriff:** jeder; einzelne Kacheln permission-/flag-gegatet  
**Feature-Flag:** Passwörter nur AppConfig.passwordManagerEnabled

**Unterbereiche / Tabs (4)**

- **Kopf** — SectionHeader »Profil« + ThemeModeButton (Hell/Dunkel-Schnellschalter; Tap wechselt, Langdruck=Menü).
- **Profil-Karte** — Avatar, Name, Rolle, Chips: Stammstandort, Soll/Tag, Urlaubstage.
- **Kachel-Grid** — Personal (isAdmin), Warenwirtschaft (canViewInventory), Kundenbestellungen (canViewInventory), Wissen & Hilfe (immer), Einstellungen (immer), Passwörter (passwordManagerEnabled && isActive), Monatsbericht (canViewReports), Statistiken (canViewReports).
- **Sicherheit** — Session-aktiv-Zeile + Abmelden/»Profil wechseln«-Button.

**Aktionen (3)**

- Theme-Umschalter (Tap/Langdruck)
- Kachel-Tap → AppRoutes (personal, inventory, customerOrders, knowledge, settings, passwords, monthReport, statistics)
- Abmelden → signOut

**Versteckt / gegatet (5)**

- ⨯ Hell/Dunkel-Schalter bewusst NUR hier (nicht in App-Leiste/Rail)
- ⨯ Personal-Kachel nur isAdmin
- ⨯ Warenwirtschaft/Kundenbestellungen nur canViewInventory
- ⨯ Passwörter nur passwordManagerEnabled && isActive
- ⨯ Monatsbericht/Statistiken nur canViewReports

> authDisabled-Modus zeigt »Profil wechseln« statt »Abmelden« + Dev-Hinweis-Text.

### Schichtdetail-Sheet (_showShiftDetailsSheet) · `modal-sheet`

**Route:** `— (Sheet, imperativ)`  
**Zugriff:** Planer- vs. Mitarbeiter-Variante

**Aktionen (3)**

- Planer: »Im Schichtplan bearbeiten« → Plan-Tab für Datum
- Mitarbeiter: »Tausch anfragen« (nur wenn shift.id && kein swapStatus) → requestShiftSwap
- Mitarbeiter: »Krank melden« → Abwesenheits-Sheet

**Sheets & Dialoge (1)**

- Abwesenheits-Sheet

**Versteckt / gegatet (2)**

- ⨯ Tausch-anfragen-Button nur wenn Schicht noch keinen swapStatus hat
- ⨯ Planer- vs. Mitarbeiter-Buttons je isPlanner

> Zeigt Titel, Status-Badge, Zeit, Standort/Name/Stunden-Chips, ggf. Notiz.

### Breadcrumb-Kopf (SectionHeader/ShellBreadcrumb/BreadcrumbAppBar) · `widget`

**Route:** `— (Kopf jedes Hub/Tabs)`  
**Zugriff:** alle

**Unterbereiche / Tabs (2)**

- **Schmal** — Eine Zurück-Taste + prominenter Titel + dezente Eltern-Zeile (Eyebrow).
- **Breit (>=600)** — Volle klickbare Breadcrumb-Kette (Desktop/Web).

**Aktionen (2)**

- Zurück-Pille / Zurück-Pfeil → Cross-Tab-Zurück (onBack) bzw. Navigator.maybePop
- Klickbare Vorfahren-Krümel (nur breit, nur mit onTap)

**Versteckt / gegatet (2)**

- ⨯ Zurück-Element nur wenn navigierbar (canGoBack / Navigator.canPop)
- ⨯ Eyebrow nur bei Eltern-Pfad (breadcrumbs.length>1)

> Chrome-Text-Scaling auf 1,5 gedeckelt; flache Hairline statt Scroll-Schatten.

### Legacy Zeiterfassung-Tab (_TimeTrackingTab) · `section-screen`

**Route:** `— (nicht mehr instanziiert)`  
**Zugriff:** canViewTimeTracking (historisch)

**Unterbereiche / Tabs (2)**

- **Kein-Zugriff-Gate** — Ohne canViewTimeTracking: SectionCard »Kein Zugriff«.
- **Kalender/Monat** — TableCalendar mit Soll/Ist-Markern, Monatsnavigation, Summary-Karten, Tagesdetails.

**Aktionen (1)**

- Monatsbericht (canViewReports), Eintrag (canEditTimeEntries) → EntryFormScreen

**Sheets & Dialoge (1)**

- EntryFormScreen

**Versteckt / gegatet (1)**

- ⨯ Komplettes Widget seit Zeit-Hub (ZeitwirtschaftHubScreen) nicht mehr an ShellTab.time gehängt — toter Code im File

> Im File vorhanden, aber buildHomeTab rendert für ShellTab.time den ZeitwirtschaftHubScreen (anderer Cluster).

---

<a id="cluster-2"></a>

## 2. Plan / Schichtplanung

*10 Bereiche.*

### Schichtplan (Nicht-Admin-Fallback: Meine Schichten) · `section-screen`

**Route:** `/plan (Tab)`  
**Zugriff:** canViewSchedule (sonst Sperrtext); dieser Zweig rendert nur für Nicht-Admins (employee/teamlead), da canManageShifts früh das Admin-Board zurückgibt

**Unterbereiche / Tabs (5)**

- **Ansichts-Umschalter** — SegmentedButton Tag / Woche / Monat
- **Zeitnavigation** — OutlinedButtons 'Zurück' / 'Weiter' + Bereichslabel (rangeLabel)
- **Monatskalender** — Nur bei viewMode==month: TableCalendar (de_DE) mit Schicht-(primary) + Abwesenheits-(tertiary) Markern
- **Schichten-Liste** — Card 'Schichten' mit _ShiftCard je Schicht oder Leerzustand 'Keine Schichten im aktuellen Zeitfenster.'
- **Abwesenheiten-Liste** — Card 'Abwesenheiten' mit _AbsenceCard oder Leerzustand 'Keine Abwesenheiten im aktuellen Zeitfenster.'

**Aktionen (4)**

- FilledButton 'Abwesenheit melden' (event_busy_outlined) — für employee (statt 'Schicht anlegen')
- OutlinedButton 'Abwesenheit melden' — zusätzlich nur wenn isTeamLead
- Export-PopupMenuButton (download_outlined, enabled nur wenn Schichten vorhanden): 'Als PDF exportieren' / 'Als CSV exportieren' / 'Als Kalender (.ics)'
- Breadcrumb 'Plan > Meine Schichten' mit optionalem Zurück

**Sheets & Dialoge (2)**

- Abwesenheit melden (_AbsenceEditorSheet)
- Tausch anfragen (showSwapRequestSheet, aus _ShiftCard-Button)

**Versteckt / gegatet (8)**

- ⨯ Mitarbeiter-Filter Dropdown 'Alle Mitarbeiter' — hinter if(isAdmin), im Fallback nie sichtbar (toter Admin-Zweig)
- ⨯ Team-Filter Dropdown 'Alle Teams' — if(isAdmin)
- ⨯ Status-Filter Dropdown 'Alle Status' — if(isAdmin)
- ⨯ FilledButton 'Schicht anlegen' (add_task) — nur if(isAdmin)
- ⨯ OutlinedButton 'Woche kopieren' — nur if(isAdmin)
- ⨯ _ShiftCard Admin-PopupMenu (Bearbeiten/Einzeln löschen/Serie löschen) — nur isAdmin; Nicht-Admin sieht stattdessen Status-Label
- ⨯ Tausch-Anfrage-Button in _ShiftCard nur für Nicht-Admin + shift.id != null; ausgeblendet wenn bereits offene Tauschanfrage läuft (zeigt dann 'Tauschanfrage: <status>')
- ⨯ Abwesenheit genehmigen/ablehnen (Icon-Buttons) in _AbsenceCard — nur canReviewRequest (Admin und nicht eigene TeamLead-Anfrage) + status==pending

> Untertitel wechselt je Rolle (teamlead/admin/employee). Titel 'Meine Schichten' bzw. 'Schichtplaner'.

### Schichtplan-Board (Admin) · `section-screen`

**Route:** `/plan (Tab)`  
**Zugriff:** canManageShifts (Admin/Manager) — früher return _AdminShiftPlannerBoard in ShiftPlannerScreen.build

**Unterbereiche / Tabs (8)**

- **Toolbar (breit ≥1040dp)** — Datums-Nav (chevron), 'HEUTE', Layout-Pill (Mitarbeiter/Standort, nur nicht-Monat & nicht-Mobil), Ansicht-Pill (Tag/Woche/Monat), 'Filter zurücksetzen', 'Neue Schicht', 'AKTIONEN'-Menü, grüner 'VERÖFFENTLICHEN'-Button
- **Toolbar (kompakt <1040dp)** — Menü-Button (nur Monat: Kalender-Menü-Sheet), Datums-Nav, +Neue-Schicht (IconButton), auto_fix_high 'Automatisch planen', ⋮-Aktionen-Menü, 'HEUTE', Ansicht-Popup, Layout-Popup, Filter-zurücksetzen, breiter grüner 'Veröffentlichen'-Button
- **Filterleiste** — Filter-Pills: Standort, Arbeitsbereiche, Mitarbeiter, Funktion, Abwesenheiten, Tags(Status) + aktive-Filter-Chips (löschbar)
- **FREIE SCHICHTEN Zeile** — 'Offene Slots' Zeile mit Tageszellen + Quick-Add je Tag (initialUnassigned)
- **PLANMÄSSIGE SCHICHTEN** — Zeilen je Mitarbeiter (Layout Mitarbeiter) oder je Standort; Stunden-Pille Ist/Soll + ÜS-Badge; Tageszellen mit Schichtkarten; Leerzustand _PlannerEmptyBoardState
- **Monatslayout** — Desktop: Sidebar (Mini-Kalender + Mitarbeiter/Standorte-Checkboxen mit Std-Badges) + Monatsboard; Kompakt: nur Board
- **Mobile Tagesliste (<840dp, Tag/Woche)** — Vertikale Tagesabschnitte mit +Button, Anmerkungs-Pille, _PlannerMobileShiftCard
- **Abwesenheiten im Zeitraum** — Container mit _PlannerAbsencePill je Abwesenheit (nur wenn vorhanden)

**Aktionen (10)**

- 'Neue Schicht' (Toolbar + IconButton + Zeilen-/Zellen-Quick-Add + Header 'SCHICHT'-Zelle)
- 'Automatisch planen' (auto_fix_high Button kompakt + AKTIONEN-Menü)
- 'VERÖFFENTLICHEN' / 'Veröffentlichen' (grüner Button + Menüeintrag)
- AKTIONEN-Menü: 'Schicht anlegen', 'Freie Schicht anlegen', 'Woche kopieren', 'Automatisch planen', 'Besetzungs-Profil (Kassendaten)', 'Als PDF exportieren', 'Als CSV exportieren', (Layout: Mitarbeiter/Standort), (Veröffentlichen)
- Layout umschalten (Mitarbeiter/Standort Popup)
- Ansicht umschalten (Tag/Woche/Monat Popup)
- 'Filter zurücksetzen' (filter_alt_off)
- Schichtkarte: Tap=Bearbeiten; PopupMenu 'Bearbeiten' / 'Kopieren (Mitarbeiter/Tage) ...' / 'Einzeln löschen' / 'Serie löschen'
- Drag & Drop einer Schichtkarte auf andere Tageszelle/Mitarbeiterzeile (Kopie/Reassign; Maus=Draggable, Touch=LongPressDraggable)
- Tageszellen-Notiz/Abwesenheit antippen (_showDayNotes Dialog)

**Sheets & Dialoge (9)**

- Schicht-Editor (_ShiftEditorSheet, showModalBottomSheet)
- Auto-Plan-Vorschau (_AutoPlanPreviewSheet)
- Woche kopieren (showDatePicker → copyWeekShifts)
- Schicht kopieren (_CopyShiftSheet → _MultiDayPickerSheet)
- Kalender-Menü (Monats-Sidebar-Sheet, kompakt)
- Monats-Tagesdetails-Dialog (_showMonthDayDetails)
- Tages-Anmerkungen-Dialog (_showDayNotes)
- Schichtkonflikte-Dialog / Regelverstoss(Compliance)-Dialog
- Löschbestätigung 'Schicht löschen?' / 'Ganze Serie löschen?'

**Versteckt / gegatet (7)**

- ⨯ Layout-Umschalter (Mitarbeiter/Standort) ausgeblendet in Monatsansicht und in mobiler Tagesliste (<840dp)
- ⨯ Kalender-Menü-Button (menu_rounded) nur im Kompakt-Modus UND Monatsansicht
- ⨯ Monats-Sidebar nur ab 840dp (darunter nur kompaktes Board ohne Sidebar)
- ⨯ ÜS-Badge in Zeilenidentität nur wenn Ist > Vertrags-Wochenmaximum; Warn-Pille nur wenn Ist>Soll; kein Soll in Tag-Ansicht (nur Ist)
- ⨯ Stunden-Badges neben Mitarbeiter-Checkboxen (geplant/Monatssoll) mit Überstunden-Warnfarbe über Vertragsmaximum
- ⨯ '+N mehr'-Hinweis in kompakten Monatszellen nur wenn Höhenbudget überschritten
- ⨯ Admin-Tausch-Genehmigen/Ablehnen-Icons in _ShiftCard nur wenn shift.swapStatus=='pending'

> UI-Footgun (CLAUDE.md): Admin-Aktionen müssen als Callbacks (onAutoPlan/onCopyWeek/onOpenShiftEditor) ins Board gereicht werden, nicht in den Fallback-Pfad. Board hat maxWidth 1440.

### Schicht-Editor (Neue Schicht / Schicht bearbeiten) · `modal-sheet`

**Route:** `— (showModalBottomSheet, imperativ)`  
**Zugriff:** canManageShifts (nur aus Admin-Board / Fallback-Admin-Zweig)

**Unterbereiche / Tabs (6)**

- **Vorlagen-Leiste** — 'Aus Vorlage' (Picker), 'Als Vorlage' speichern, Vorlagen-Aktionen (aktualisieren/löschen) wenn Vorlage gewählt + Zusammenfassung
- **Eckdaten** — Schichttitel, Datum (Edit) bzw. Tage (Mehrtage-Picker bei Neuanlage), Beginn/Ende, Pause (Min.), Standort-Dropdown; Hinweis wenn keine Standorte / kein Standort gewählt
- **Besetzung** — SegmentedButton Mitarbeiter/Freie Schicht; Mitarbeiter-Picker (frei/gesperrt-Zähler, 'Alle freien', gekappt auf 8 mit 'Weitere anzeigen'), Verfügbarkeits-Tiles mit Sperrgründen/Überstunden-Hinweis, Fan-out-Summe N/50, Zusatzbesetzungen ('Person hinzufügen')
- **Details** — Gespeichertes Team, Team/Bereich-Freitext, erforderliche Qualifikationen (FilterChips), Status-Dropdown, Wiederholung (read-only bei Serie), Farbauswahl (8 Farben), Notiz
- **Konfliktkarte** — Bei Konflikten: Liste + optional 'Betroffene überspringen und Rest speichern'
- **Footer** — Fixierter 'Speichern'/'Aktualisieren'-Button ('Prüfe Konflikte...')

**Aktionen (9)**

- Speichern/Aktualisieren (mit serverseitiger Konfliktprüfung)
- Schließen (X / maybePop)
- Vorlage wählen/speichern/aktualisieren/löschen
- Mehrtage-Picker öffnen (Wochentags-Maske + Kalender-Mehrfachauswahl)
- Datum/Beginn/Ende-Picker
- Standort/Status/Team-Dropdowns, Qualifikations-Chips, Farbwahl
- Mitarbeiter (ab)wählen, 'Alle freien', gesperrte aufklappen, blockierte abwählen
- Zusatzbesetzung hinzufügen/entfernen/Zeiten/Pause/Mitarbeiter setzen
- 'Betroffene überspringen und Rest speichern' (nur bei Mehrfach-Anlage + Konflikten)

**Sheets & Dialoge (5)**

- Schichtvorlage auswählen (_ShiftTemplatePickerSheet)
- Schichtvorlage speichern/bearbeiten (_ShiftTemplateSaveSheet)
- Schichtvorlage löschen? (Dialog)
- Tage wählen (_MultiDayPickerSheet)
- showDatePicker / showTimePicker

**Versteckt / gegatet (10)**

- ⨯ Mehrtage-Feld 'Tage' nur bei Neuanlage; im Edit-Modus stattdessen einzelnes 'Datum'
- ⨯ Standort-Pflicht-Hinweis (errorContainer) nur wenn Standorte existieren aber keiner gewählt
- ⨯ Warnkarte 'Noch keine Standorte angelegt' nur wenn sites leer (dann nur Pause-Feld)
- ⨯ Verfügbarkeits-Badges neutral ('– frei/– gesperrt') solange kein Standort gewählt (Verfügbarkeit ungeprüft)
- ⨯ 'Weitere N anzeigen' nur wenn >8 Mitarbeiter
- ⨯ Fan-out-Summe nur wenn total>1; Fehlerfarbe über 50
- ⨯ Vorlagen-Aktionen-Menü nur wenn Vorlage ausgewählt
- ⨯ Zusatzbesetzungen-Block nur im Nicht-freie-Schicht-Modus mit Mitgliedern
- ⨯ Überstunden-Hinweis nur wenn capOverageMinutes>0
- ⨯ Wiederholung-Anzeige nur bei bestehender Serie im Edit

> Speicher-Obergrenze _kMaxShiftsPerSave=50 (Fan-out Tage×Mitarbeiter+Zusatz). groupAsSeries bei Mehrtage-Neuanlage.

### Automatische Planung — Vorschau · `modal-sheet`

**Route:** `— (showModalBottomSheet, DraggableScrollableSheet)`  
**Zugriff:** canManageShifts

**Unterbereiche / Tabs (5)**

- **Kopf-Statistiken** — Chips: 'N neu', 'N besetzt' (bzw. N von M), 'N offen', Überstunden-Summe, Warnungen
- **Weich-Hinweis** — Warnbox 'Stundengrenzen sind weich…' nur wenn !enforceHourCapHard
- **Neu zu erstellen** — Anzahl neuer Schichten je Standort
- **Zuweisungen** — Pro Mitarbeiter gruppiert (Kopf: geplante Std + ÜS), CheckboxListTile je Zuweisung (abwählbar, Teilübernahme), Grund + Überstunden-Hinweis
- **Warnungen / Nicht zuweisbar** — Listen mit Warntext bzw. Slot + Grund

**Aktionen (3)**

- Zuweisungen einzeln ab-/anwählen (Teilübernahme)
- 'Abbrechen'
- 'Übernehmen & speichern' (gibt abgewählte Schicht-IDs zurück)

**Sheets & Dialoge (2)**

- Blockierender Ladespinner-Dialog während proposeAutoAssignment
- danach Schichtkonflikte-/Compliance-Dialog bei applyAutoPlan-Fehler

**Versteckt / gegatet (3)**

- ⨯ Weich-Hinweisbox nur bei weichem Cap-Modus
- ⨯ Überstunden-Chip/-Zeile nur wenn overtimeMinutes>0
- ⨯ Warnungen-/Nicht-zuweisbar-Abschnitte nur wenn vorhanden

> Erreichbar über 'Automatisch planen'. Rückgabe null=Abbruch, sonst Set abgewählter Zuweisungs-IDs.

### Schicht kopieren (Mitarbeiter/Tage) · `modal-sheet`

**Route:** `— (showModalBottomSheet)`  
**Zugriff:** canManageShifts

**Unterbereiche / Tabs (3)**

- **Mitarbeiter** — FilterChips je aktivem Mitarbeiter (Standard: bisheriger Mitarbeiter)
- **Tage** — _DateTile öffnet _MultiDayPickerSheet (Standard: Quelltag)
- **Kopien-Info** — 'Es werden bis zu N Kopien erstellt' + Fehler bei >50

**Aktionen (3)**

- Mitarbeiter-Chips wählen
- Tage wählen (Mehrtage-Picker)
- 'Kopieren' (deaktiviert bei leerer Auswahl oder >50)

**Sheets & Dialoge (1)**

- Tage wählen (_MultiDayPickerSheet)

**Versteckt / gegatet (2)**

- ⨯ Fehlertext 'Zu viele Kopien: max. 50' nur wenn copyCount>50
- ⨯ 'Keine aktiven Mitarbeiter vorhanden.' wenn members leer

> Aufgerufen aus Schichtkarten-Menü 'Kopieren (Mitarbeiter/Tage) ...'.

### Tage wählen (Mehrtage-Picker) · `modal-sheet`

**Route:** `— (showModalBottomSheet)`  
**Zugriff:** canManageShifts

**Unterbereiche / Tabs (3)**

- **Wochentage** — FilterChips Mo–So
- **Zeitraum** — Von/Bis _DateTile (Standard 4 Wochen) + 'Wochentage/Alle Tage im Zeitraum hinzufügen'
- **Monatskalender** — Monats-Grid zum Einzeltag-Antippen + Monatsnavigation

**Aktionen (6)**

- Wochentage togglen
- Von/Bis wählen
- '…im Zeitraum hinzufügen'
- Einzeltage antippen
- 'Zurücksetzen'
- 'Übernehmen'

**Sheets & Dialoge (1)**

- showDatePicker (Von/Bis)

> Gibt normalisiertes Tages-Set zurück; genutzt von Editor (Neuanlage) und Schicht-kopieren.

### Abwesenheit melden · `modal-sheet`

**Route:** `— (showModalBottomSheet)`  
**Zugriff:** Alle (employee/teamlead/admin) — für sich selbst

**Unterbereiche / Tabs (1)**

- **Formular** — Von/Bis _DateTile, Art-Dropdown (AbsenceType.values), Notiz

**Aktionen (3)**

- Von/Bis wählen
- Art wählen
- 'Abwesenheit senden'

**Sheets & Dialoge (1)**

- showDatePicker

> submitAbsenceRequest; Enddatum-Validierung.

### Tausch anfragen · `modal-sheet`

**Route:** `— (showModalBottomSheet, showSwapRequestSheet)`  
**Zugriff:** Nicht-Admin (eigene Schicht mit id) — Button in _ShiftCard

**Unterbereiche / Tabs (4)**

- **Modus** — SegmentedButton 'Tauschen' / 'Abgeben'
- **Tauschen-Liste** — Tauschbare Kollegenschichten (aktueller+nächster Monat) auswählbar
- **Abgeben-Liste** — Kollegen-Auswahl (Gutschrift-Hinweis)
- **Notiz** — Optionale Notiz + 'Anfrage senden'

**Aktionen (3)**

- Modus wechseln
- Zielschicht bzw. Kollege wählen
- 'Anfrage senden'

**Versteckt / gegatet (2)**

- ⨯ Tauschen-Leerzustand 'Keine tauschbaren Schichten…' bzw. Abgeben-Leerzustand 'Keine Kollegen verfügbar.'
- ⨯ Ladespinner während getSwappableShiftsInRange

> SwapKind.exchange/giveAway; submitShiftSwapRequest.

### Besetzungs-Profil (Kassendaten) · `section-screen`

**Route:** `AppRoutes.staffingProfile (context.push)`  
**Zugriff:** isAdmin (sonst 'Nur für Administratoren.')

**Unterbereiche / Tabs (3)**

- **Standortauswahl** — DropdownButton nur wenn >1 Standort
- **Stoßzeiten & Besetzungs-Vorschlag** — Top-6 Stunden mit Ø Belegen + Kräfte-Vorschlag + 'übernehmen'-Button
- **Heatmap** — Ø Belege/Std je Wochentag×Stunde (Farbintensität)

**Aktionen (4)**

- Standort wechseln
- 'Aktualisieren' (AppBar refresh)
- 'übernehmen' — schreibt StaffingDemand.requiredCount in den Standort (saveSite)
- 'Erneut versuchen' bei Fehler

**Versteckt / gegatet (2)**

- ⨯ Standort-Dropdown nur bei >1 Standort
- ⨯ Leerzustände: 'Keine Standorte', 'Analyse fehlgeschlagen', 'Noch kein Kassenabgleich' (keine Verkäufe)

> Erreichbar aus Board-AKTIONEN-Menü 'Besetzungs-Profil (Kassendaten)'. Datenbasis 28 Tage aus posReceipts.

### Abwesenheit / Urlaubskonto-Übersicht · `section-screen`

**Route:** `— (Navigator.push aus Personal-Bereich)`  
**Zugriff:** isAdmin (sonst 'Kein Zugriff')

**Unterbereiche / Tabs (3)**

- **Jahr-Wähler** — 'Urlaubsjahr <Jahr>' mit Vor-/Zurück
- **§9-Sammelbanner** — Warnbanner wenn Mitarbeiter mit Krankheit im genehmigten Urlaub
- **Urlaubskonten je Mitarbeiter** — AppKontoTile mit Resturlaub-Kennzahl + +/−/=-Aufstellung (Jahresanspruch, Vortrag, verfallen, genommen, geplant, Resturlaub) + §9-Banner

**Aktionen (2)**

- Jahr vor/zurück
- Kachel aufklappen (Aufstellung)

**Versteckt / gegatet (4)**

- ⨯ Leerzustand 'Keine Mitarbeiter'
- ⨯ §9-Sammelbanner nur wenn Betroffene vorhanden
- ⨯ §9-Kachel-Banner nur wenn krankheitTage>0
- ⨯ '− verfallen' / '− geplant (offen)' Zeilen nur wenn Wert != 0

> Gehört fachlich zum Personal-Bereich, wird per Navigator.push geöffnet; reine Anzeige des Urlaubskontos.

---

<a id="cluster-3"></a>

## 3. Zeit / Zeitwirtschaft

*11 Bereiche.*

### Zeitwirtschaft (Hub) · `tab-hub`

**Route:** `/zeit`  
**Zugriff:** canViewTimeTracking (sonst 'Kein Zugriff'-Karte); Kacheln teils reviewerOnly (canManageShifts) / adminOnly (isAdmin)

**Unterbereiche / Tabs (4)**

- **Kennzahl-Reihe** — AppComparisonStatCard (Soll/Ist geplant vs. actualHours) + AppMetricCard 'Überstunden (Monat)' mit Vorzeichen; Monatsnavigation (Vorheriger/Nächster Monat via IconButtons)
- **Gruppe 'Mein Tag'** — Kacheln: 'Kommen und Gehen', 'Zeiterfassung', 'Abwesenheiten'
- **Gruppe 'Meine Konten'** — Kacheln: 'Stundenkonto', 'Abwesenheitskalender', 'Mein Monatsabschluss'
- **Gruppe 'Team & Abschluss'** — Kacheln: 'Mitarbeiterabschluss' (nur canManageShifts), 'Lohnlauf' (nur isAdmin); Gruppe wird komplett ausgeblendet wenn keine Kachel berechtigt

**Aktionen (9)**

- Kachel 'Kommen und Gehen' → /zeit/stempeln
- Kachel 'Zeiterfassung' → /zeit/erfassung
- Kachel 'Abwesenheiten' → /zeit/abwesenheiten
- Kachel 'Stundenkonto' → /zeit/stundenkonto
- Kachel 'Abwesenheitskalender' → /zeit/abwesenheiten/kalender
- Kachel 'Mein Monatsabschluss' → /zeit/monatsabschluss
- Kachel 'Mitarbeiterabschluss' → /zeit/mitarbeiterabschluss
- Kachel 'Lohnlauf' → /zeit/lohnlauf
- Vorheriger Monat / Nächster Monat (IconButtons)

**Versteckt / gegatet (5)**

- ⨯ 'Kein Zugriff'-Karte statt Hub wenn !canViewTimeTracking
- ⨯ Kachel 'Mitarbeiterabschluss' nur bei canManageShifts (reviewerOnly)
- ⨯ Kachel 'Lohnlauf' nur bei isAdmin (adminOnly)
- ⨯ Gruppe 'Team & Abschluss' verschwindet ganz für reine Mitarbeiter
- ⨯ 'Überstunden (Monat)' zeigt +/- Vorzeichen nur bei Wert > 0,05

> Rollen-adaptiver Hub-Einstieg für den /zeit-Tab (ZeitwirtschaftHubScreen). Reine Lese-Ansicht, KPIs aus WorkProvider + geplanten Monatsschichten. Kacheln gruppiert (Mein Tag / Meine Konten / Team & Abschluss).

### Zeiterfassung · `section-screen`

**Route:** `/zeit/erfassung`  
**Zugriff:** self-service (eigene Einträge); Bearbeiten/Anlegen/Einreichen nur bei canEditTimeEntries

**Unterbereiche / Tabs (3)**

- **Tab 'Arbeitszeiten'** — Monatsliste eigener WorkEntry in DataTable (Tag/Kommen/Gehen/Pause/Stunden/Status/Optionen); Summe zählt nur approved (E3), 'in Freigabe'-Zusatz für submitted; FilterChip 'Nur Klärung' (draft+rejected)
- **Tab 'Urlaub'** — Liste eigener Urlaubs-/Freistellungsanträge (alles außer sickness/childSick) mit Status-Chip; Button 'Urlaubsantrag'
- **Tab 'Krankmeldungen'** — Liste eigener Krankmeldungen (sickness/childSick) mit Status-Chip; Button 'Krankmeldung'

**Aktionen (7)**

- Monatsnavigation Vorheriger/Nächster Monat
- FilterChip 'Nur Klärung'
- FilledButton 'Neue Arbeitszeit' (nur canEditTimeEntries) → EntryFormScreen
- Zeilen-IconButton 'Einreichen' (send) bei draft/rejected + canEditTimeEntries → submitWorkEntry
- Zeilen-IconButton 'Bearbeiten' (edit) bei canEditTimeEntries → EntryFormScreen
- Button 'Urlaubsantrag' → showAbsenceRequestSheet (vacation)
- Button 'Krankmeldung' → showAbsenceRequestSheet (sickness)

**Sheets & Dialoge (3)**

- EntryFormScreen (Navigator.push, MaterialPageRoute)
- showAbsenceRequestSheet (Urlaub)
- showAbsenceRequestSheet (Krankmeldung)

**Versteckt / gegatet (4)**

- ⨯ Button 'Neue Arbeitszeit' nur wenn canEditTimeEntries
- ⨯ 'Einreichen'/'Bearbeiten'-IconButtons nur bei canEditTimeEntries (Einreichen zusätzlich nur bei draft/rejected)
- ⨯ '+ X h in Freigabe'-Zeile nur wenn vorläufige Stunden > 0,05
- ⨯ Status-Chips farbcodiert (approved=success, submitted=info, rejected=error, draft=onSurfaceVariant)

> 3-Tab-Screen (DefaultTabController length 3, TabBar mit Text-Labels). Genehmigen/Ablehnen läuft NICHT hier, sondern über Mitarbeiterabschluss.

### Kommen und Gehen (Stempeln) · `section-screen`

**Route:** `/zeit/stempeln`  
**Zugriff:** self (eigene Stempel-Sessions); Manager-Karten nur bei canManageShifts

**Unterbereiche / Tabs (5)**

- **Timer-Karte** — laufende Buchung mit Live-Ticker (30s), 'Eingestempelt seit …', Dauer, Quelle (Tablet/App), 'ausstehend'-Badge bei offline-pending; Warnbanner bei >10h Buchung bzw. Buchung vom Vortag
- **'Aktuell eingestempelt'-Karte** — Liste aller ongoing-Buchungen mit Initialen + 'seit HH:mm' (nur wenn ongoingEntries vorhanden)
- **'Dienst heute'-Karte** — Manager-only Soll-Ist-Abgleich (Pünktlich/Verspätet/Früher/Nicht erschienen/Ungeplant) mit Refresh-Button; FutureBuilder
- **Klärungs-Inbox-Karte** — Manager-only (nur wenn klaerungEntries vorhanden): offene/vergessene Stempelungen mit 'Korrigieren'/'Verwerfen'
- **Monatsliste** — eigene Stempel-Buchungen des Monats mit Status-Badge (completed/ongoing/klaerung/deaktiviert); leerer Zustand 'Keine Stempelzeiten'

**Aktionen (6)**

- FAB 'Kommen' (grün, login) → Schicht-Match-Prüfung + ggf. Laden-Auswahl → clockIn
- FAB 'Gehen' (rot, logout, mit Ladenname) → Ausstempeln-Sheet → clockOut
- Monatsnavigation Vorheriger/Nächster Monat
- 'Dienst heute' Refresh-Button (nur Manager)
- Klärung 'Korrigieren' → _ResolveKlaerungSheet (nur Manager)
- Klärung 'Verwerfen' → Grund-Sheet → dismissKlaerung (nur Manager)

**Sheets & Dialoge (4)**

- Laden-Auswahl-Sheet (showModalBottomSheet, nur bei >1 Standort)
- Ausstempeln-Sheet _ClockOutSheet (Pause-Minuten, Anmerkung)
- _ResolveKlaerungSheet (Kommen/Gehen-TimePicker, Pause, Pflicht-Grund)
- Grund-Sheet 'Klärung verwerfen' (_askGrund TextField)

**Versteckt / gegatet (7)**

- ⨯ 'Dienst heute'-Karte nur bei canManageShifts
- ⨯ Klärungs-Inbox nur bei canManageShifts UND klaerungEntries nicht leer
- ⨯ FAB wechselt Farbe/Label/Aktion je isClockedIn
- ⨯ Warnbanner nur bei überlanger Buchung (>10h) oder Buchung vom Vortag
- ⨯ 'ausstehend'-Badge nur bei offline-pending Write
- ⨯ Einstempeln HART gegated: nur innerhalb geplanter Schicht (±15 Min), sonst SnackBar-Fehler und Abbruch
- ⨯ Laden-Auswahl-Sheet nur wenn mehrere Standorte (sites.length > 1)

> StempelScreen; nutzt ZeitwirtschaftProvider. Lifecycle-resume löst refetch aus. Schichtbindung E1/Z1 hart über matchShiftForPunch.

### Stundenkonto · `section-screen`

**Route:** `/zeit/stundenkonto`  
**Zugriff:** self (eigenes Konto); Soll nur wenn SollzeitProfile (admin-gepflegt) vorhanden

**Unterbereiche / Tabs (3)**

- **Summen-Karte** — Soll / Geplant / Ist / Überstunden / Saldo (emphasize); + Übertrag Vormonat + Ausbezahlt (nur wenn Soll vorhanden). Live berechnet aus buildZeitkontoSnapshot
- **Zuschlagszeiten-Karte (§3b)** — Nacht/Sonntag/Feiertag-Stunden aus genehmigten Einträgen (nur wenn nicht null); reine Transparenz-Anzeige
- **Jahresübersicht** — DataTable je Monat: Soll/Geplant/Ist/Saldo/Status (lock=abgeschlossen, lock_open=persistiert, 'laufend', 'offen')

**Aktionen (1)**

- Monatsnavigation Vorheriger/Nächster Monat (lädt Snapshots + Carryover)

**Versteckt / gegatet (5)**

- ⨯ Warnbanner ArbZG §3 wenn wöchentl. Durchschnitt > 48h (nur bei hasSoll)
- ⨯ Info-Banner 'keine Sollzeit hinterlegt' wenn Profil ohne SollzeitProfile → nur Ist
- ⨯ Soll/Überstunden/Saldo zeigen '—' wenn kein Soll-Profil
- ⨯ §3b-Karte nur wenn SfnLage nicht zero
- ⨯ 'Übertrag Vormonat'/'Ausbezahlt' nur bei hasSoll

> StundenkontoScreen. Bundesland-Default SH (Kiel) für §3b. Live-Monat berechnet, abgeschlossene Monate aus persistierten ZeitkontoSnapshots.

### Abwesenheiten · `section-screen`

**Route:** `/zeit/abwesenheiten`  
**Zugriff:** self (eigene Anträge, bearbeiten/löschen solange offen); Manager (canManageShifts) sehen org-weit + genehmigen/ablehnen

**Unterbereiche / Tabs (3)**

- **Antrags-Buttons** — 'Urlaubsantrag' (filled), 'Krankmeldung' (tonal), 'Zeitausgleich' (outlined); Manager zusätzlich 'Kalender'
- **Status-Filterleiste** — ChoiceChips Alle / Offen (mit Count) / Genehmigt / Abgelehnt
- **Antragsliste** — AbsenceCard je Antrag mit Typ/Zeitraum/Tage/Notiz, Status-Chip, AU-Nachweis-Schild (bei Krankheit ≥3 Tage), Aktionen

**Aktionen (8)**

- 'Urlaubsantrag' → showAbsenceRequestSheet (vacation)
- 'Krankmeldung' → showAbsenceRequestSheet (sickness)
- 'Zeitausgleich' → showAbsenceRequestSheet (timeOff)
- 'Kalender' → /zeit/abwesenheiten/kalender (nur Manager)
- Status-ChoiceChips (Alle/Offen/Genehmigt/Abgelehnt)
- 'Genehmigen' / 'Ablehnen' (nur Manager, offene Anträge)
- 'Bearbeiten' (eigener offener Antrag) → showAbsenceRequestSheet mit initialRequest
- 'Löschen' (eigener offener Antrag) → Bestätigungsdialog

**Sheets & Dialoge (2)**

- showAbsenceRequestSheet (Urlaub/Krank/Zeitausgleich/Bearbeiten)
- AlertDialog 'Antrag löschen?'

**Versteckt / gegatet (6)**

- ⨯ Button 'Kalender' nur bei canManage
- ⨯ 'Genehmigen'/'Ablehnen' nur bei canManage UND pending
- ⨯ 'Bearbeiten'/'Löschen' nur bei isOwn UND pending
- ⨯ Antragsteller-Name im Titel nur für Manager (showEmployee)
- ⨯ AU-Nachweis-Schild (rot/grün) nur bei Krankmeldung ≥3 Kalendertage (§5 EFZG)
- ⨯ Notiz-Zeile nur wenn vorhanden

> AbwesenheitenScreen; rollen-adaptiv über allAbsenceRequests (self-gescoped für Nicht-Manager). Mutationen über ScheduleProvider.

### Abwesenheitskalender · `section-screen`

**Route:** `/zeit/abwesenheiten/kalender`  
**Zugriff:** Manager (canManageShifts) sehen alle aktiven Mitarbeiter; Mitarbeiter nur eigene Zeile

**Unterbereiche / Tabs (3)**

- **Kalenderraster** — Mitarbeiter × Tage-Grid, eingefrorene Namensspalte + horizontal scrollbares Tagesraster, Zellen farbcodiert je AbsenceType, Wochenenden schattiert, Tooltip je belegtem Tag
- **Laden-Filter** — ChoiceChips 'Alle Läden' + je Standort (nur Manager UND >1 Standort)
- **Legende** — Farb-Legende der im Monat vorkommenden Abwesenheitsarten

**Aktionen (2)**

- Monatsnavigation Vorheriger/Nächster Monat
- Laden-Filter ChoiceChips (nur Manager, >1 Standort)

**Versteckt / gegatet (6)**

- ⨯ Laden-Filterleiste nur bei canManage UND sites.length > 1
- ⨯ Nicht-Manager sehen nur die eigene Zeile
- ⨯ rejected-Anträge ausgeblendet (nur pending+approved)
- ⨯ leerer Zustand 'Keine Mitarbeiter im gewählten Filter'
- ⨯ Hinweis 'Keine Abwesenheiten in diesem Monat' wenn Reihen aber keine Belegung
- ⨯ Legende nur wenn Abwesenheiten vorhanden

> AbwesenheitskalenderScreen; reine Lese-Ansicht. Farben strikt über Theme-Rollen/appColors.

### Mein Monatsabschluss · `section-screen`

**Route:** `/zeit/monatsabschluss`  
**Zugriff:** self-Sicht; Abschließen/Zurücknehmen nur bei canManageShifts (Snapshot-Writes managergebunden per Rules)

**Unterbereiche / Tabs (1)**

- **Jahres-Monatstabelle** — DataTable 12 Monate: Monat/Status/Ist/Saldo/Aktion. Status: Zukünftig/Laufend/Offen/Bereit/Abgeschlossen mit farbigem Badge

**Aktionen (3)**

- Jahresnavigation Vorheriges/Nächstes Jahr
- Zeilen-IconButton 'Monat abschließen' (lock, nur canManage, Status offen/bereit) → Bestätigungsdialog + closeMonth
- Zeilen-IconButton 'Abschluss zurücknehmen' (lock_open, nur canManage, abgeschlossen) → Bestätigung + reopenMonth

**Sheets & Dialoge (3)**

- AppConfirmDialog 'abschließen?'
- AppConfirmDialog 'zurücknehmen?'
- AlertDialog Validierung (blockiert / mit Hinweisen)

**Versteckt / gegatet (6)**

- ⨯ Info-Banner 'Abschluss nimmt Leitung vor' für Nicht-Manager (!canManage)
- ⨯ Aktions-Spalte zeigt '—' für Nicht-Manager
- ⨯ LinearProgressIndicator während _busy
- ⨯ nur vergangene Monate (offen/bereit) abschließbar, laufender Monat = 'Laufend' ohne Aktion
- ⨯ Abschluss blockiert bei offenen Klärungsfällen (ZV-5.2)
- ⨯ SnackBar-Hinweis wenn kein Lohn-Entwurf erzeugt (kein Festgehalt/Stundensatz)

> MonatsabschlussScreen; schreibt gesperrten ZeitkontoSnapshot + Entwurfs-Lohndatensatz. Defense-in-depth: Aktion doppelt gegen canManageShifts geprüft.

### Mitarbeiterabschluss · `section-screen`

**Route:** `/zeit/mitarbeiterabschluss`  
**Zugriff:** reviewerOnly / Manager (canManageShifts); org-weite Lese-Helfer via ZeitwirtschaftProvider

**Unterbereiche / Tabs (5)**

- **Monats-Picker** — AppCard mit Vorheriger/Nächster Monat + 'Heute'-Button
- **KPI-Reihe** — Mitarbeiter / Offen / Abgeschlossen / Lohn-Entwürfe (X / total)
- **Filter** — Suchfeld 'Name suchen…', FilterChips 'Nur offene', 'Nur abgeschlossene', 'Mit Hinweisen'
- **Mitarbeiter-Karten** — je aktiver MA: Avatar+Name, Status-Badge (Abgeschlossen/Offene Einträge/Bereit), StatChips (Ist/Soll/Überstunden/Offen/Ausbezahlt), Aktions-Buttons
- **Batch-Aktionen** — 'Alle abschließbaren schließen' + 'Zum Lohnlauf'

**Aktionen (8)**

- Monats-Picker Vorheriger/Nächster + 'Heute'
- Suchfeld + FilterChips (Nur offene / Nur abgeschlossene / Mit Hinweisen)
- Karten-Button 'Prüfen (N)' → _OffeneEintraegeSheet (nur bei offenen Einträgen)
- Karten-Button 'Abschließen' (nur completed Monat + isCloseable) → Bestätigung + closeMonth
- Karten-Button 'Zurücknehmen' (nur isLocked) → Bestätigung + reopenMonth
- Karten-Button 'Auszahlung' (nur wenn persisted) → _AuszahlungSheet
- 'Alle abschließbaren schließen' → Batch-Bestätigung + closeAll
- 'Zum Lohnlauf' → /zeit/lohnlauf

**Sheets & Dialoge (4)**

- _OffeneEintraegeSheet (Genehmigen/Ablehnen einzeln, Sammel-Freigabe schicht-konformer, Ablehn-Grund-Dialog)
- _AuszahlungSheet (Auszahlung Stunden)
- AppConfirmDialog Abschließen / Zurücknehmen / Batch
- AlertDialog 'Abschluss nicht möglich' (Fehlerliste)

**Versteckt / gegatet (9)**

- ⨯ 'Prüfen'-Button nur bei offenen Einträgen
- ⨯ 'Abschließen' nur wenn Monat vollständig vergangen UND isCloseable (keine offenen Einträge)
- ⨯ 'Zurücknehmen' nur wenn abgeschlossen
- ⨯ 'Auszahlung' nur wenn persisted Snapshot vorhanden
- ⨯ Sammel-Freigabe-Button im Sheet nur wenn >1 schicht-konformer Eintrag (isEligibleForBulkApproval)
- ⨯ 'Alle abschließbaren'-Button disabled wenn kein completed Monat / keine abschließbaren
- ⨯ StatChip 'Offen' nur bei offenen Einträgen, 'Ausbezahlt' nur wenn >0
- ⨯ Abschluss blockiert bei offenen Klärungsfällen (ZV-5.2)
- ⨯ SnackBar wenn abgeschlossen aber kein Lohn-Entwurf

> MitarbeiterabschlussScreen (Admin/Manager-Hub, org-weit). Genehmigen/Ablehnen fremder WorkEntries passiert HIER, nicht in Zeiterfassung.

### Lohnlauf · `section-screen`

**Route:** `/zeit/lohnlauf`  
**Zugriff:** adminOnly (isAdmin); DATEV-Lohn zusätzlich nur bei Flag + isAdmin  
**Feature-Flag:** APP_DATEV_LOHN_ENABLED (AppConfig.datevLohnEnabled) für DATEV-Lohn-Teile

**Unterbereiche / Tabs (4)**

- **Monats-Picker** — Vorheriger/Nächster Monat (Default = Vormonat)
- **Summen-Karte** — AppSectionCard 'Lohnlauf <Monat>' mit StatCards Brutto/Abzüge/Netto/AG-Kosten + Zeile Anzahl je Status (Entwurf/freigegeben/bezahlt/storniert)
- **Export-Leiste** — 'Lohnjournal (CSV)'; bei Flag+Admin zusätzlich 'DATEV-Lohn (Export)' + 'DATEV-Lohn-Einstellungen'
- **Lohn-Karten** — je PayrollRecord: Name, Status-Badge, Kind-Badge (Minijob/Steuerklasse), 'Gebucht'-Badge; Beträge Brutto/Netto/AG-Kosten; Status-PopupMenu + PDF-Button

**Aktionen (8)**

- Monats-Picker Vorheriger/Nächster
- 'Lohnjournal (CSV)' → ExportService.exportLohnjournalCsv
- 'DATEV-Lohn (Export)' → Vorprüfungs-Sheet → Run + Download (nur Flag+Admin)
- 'DATEV-Lohn-Einstellungen' → _DatevLohnConfigSheet (nur Flag+Admin)
- 'Alle Entwürfe freigeben (N)' → Bestätigung + finalizeAllDrafts (bucht Personalkosten)
- Karten-PopupMenuButton 'Status' → setPayrollStatus (Entwurf/freigegeben/bezahlt/storniert)
- Karten-Button 'PDF' → ExportService.exportPayrollPdf
- 'Zum Mitarbeiterabschluss' → /zeit/mitarbeiterabschluss

**Sheets & Dialoge (4)**

- _DatevLohnVorpruefungSheet (Probleme + DSGVO-Hinweis, 'Trotzdem exportieren')
- _DatevLohnConfigSheet (Format LODAS/Lohn&Gehalt, Berater-/Mandantennr, Grundlohn-Lohnart)
- AppConfirmDialog 'Alle Entwürfe freigeben'
- PopupMenuButton Status-Auswahl je Record

**Versteckt / gegatet (7)**

- ⨯ 'DATEV-Lohn (Export)' + '-Einstellungen' nur bei AppConfig.datevLohnEnabled && isAdmin
- ⨯ 'Alle Entwürfe freigeben' nur wenn Entwürfe > 0
- ⨯ Export-Leiste nur wenn Records vorhanden
- ⨯ 'Gebucht'-Badge nur wenn journalEntryId gesetzt
- ⨯ leerer Zustand 'keine Lohnabrechnungen … Entwürfe entstehen beim Mitarbeiterabschluss'
- ⨯ 'storniert'-Count nur wenn > 0
- ⨯ DATEV-Export blockiert offline (Historie kann nicht geschrieben werden) / wenn Config unvollständig

> LohnlaufScreen (M6); Reuse-Seite über PersonalProvider + ExportService. Einzel-Bearbeitung der Abrechnungen bleibt im Personal-Bereich. DATEV-Lohn hinter APP_DATEV_LOHN_ENABLED (Default aus).

### Zeiteintrag-Formular (EntryForm) · `detail-tab`

**Route:** `— (Navigator.push MaterialPageRoute)`  
**Zugriff:** nur canEditTimeEntries (sonst Sperrhinweis-Screen)

**Unterbereiche / Tabs (1)**

- **Abschnitte** — Datum, Vorlage (nur wenn Vorlagen vorhanden), Bestätigte Schicht (Pflicht-Auswahl), Arbeitszeit (Beginn/Ende), Schichtprüfung, Standort, Pause, Stundenzusammenfassung, Korrekturgrund (nur Edit), Notiz

**Aktionen (10)**

- AppBar-IconButton 'Löschen' (nur Edit-Modus) → Lösch-Bestätigungsdialog
- Datum-Tile → showDatePicker
- Vorlage-Tile → _TemplatePickerSheet
- Schicht-Auswahl (Choice-Tiles) + Switch 'Komplette Schicht übernehmen'
- Beginn/Ende-Tiles → showTimePicker (deaktiviert bei applyFullShift)
- Standort-Dropdown
- Pause-TextFormField
- Korrekturgrund-Feld (Edit)
- Notiz-Feld
- FilledButton 'Speichern'/'Aktualisieren' (nur bei Schichtabdeckung gültig)

**Sheets & Dialoge (5)**

- showDatePicker
- showTimePicker (Beginn/Ende)
- _TemplatePickerSheet (showModalBottomSheet)
- AlertDialog 'Arbeitszeit verlängern?' (Überstunden-Bestätigung)
- AlertDialog 'Eintrag löschen?'

**Versteckt / gegatet (9)**

- ⨯ Ganzer Screen ersetzt durch Sperrhinweis 'Zeiteinträge dürfen … nicht bearbeitet werden' wenn !canEditTimeEntries
- ⨯ AppBar-'Löschen' nur im Edit-Modus
- ⨯ Vorlage-Abschnitt nur wenn Vorlagen vorhanden
- ⨯ Korrekturgrund-Abschnitt nur im Edit-Modus (Pflicht bei Änderung an Zeit/Pause/Standort)
- ⨯ Standort-Karte 'kein Standort hinterlegt' wenn sites leer
- ⨯ Beginn/Ende/Pause/Standort deaktiviert wenn 'Komplette Schicht übernehmen' aktiv
- ⨯ Speichern-Button disabled bis gültige Schicht ausgewählt + keine Coverage-Fehler
- ⨯ Überstunden-Dialog nur wenn Eintrag über Schicht hinausreicht (OvertimeApprovalRequired)
- ⨯ Schichtprüfungs-Karte wechselt Farbe/Icon je Zustand (gültig/Überstunden/Fehler)

> EntryFormScreen; harte Schichtbindung (Eintrag muss bestätigte Schicht mindestens teilweise abdecken; Überstunden nur mit Bestätigung). Von Zeiterfassung geöffnet mit parentLabel 'Zeiterfassung'.

### Zeit-Bereich Platzhalter · `section-screen`

**Route:** `— (generisch, je Meilenstein)`  
**Zugriff:** —

**Versteckt / gegatet (1)**

- ⨯ Ehrlicher Leer-/Baustellen-Zustand 'X entsteht in Meilenstein Y' mit construction-Icon

> ZeitSectionPlaceholder — Gerüst-Platzhalter für noch nicht gebaute Zeitwirtschafts-Bereiche (M1 stellte Hub bereit, Bereiche folgten M2–M6). Aktuell sind alle produktiven Sub-Screens gebaut; Platzhalter dient nur als ehrlicher Lückenfüller.

---

<a id="cluster-4"></a>

## 4. Anfragen / Inbox / Mitteilungen

*4 Bereiche.*

### Anfragen (Inbox / Benachrichtigungs-Center) · `tab-hub`

**Route:** `/anfragen (Shell-Tab) — auch als Section eingebettet ohne eigenes Scaffold`  
**Zugriff:** alle angemeldeten Nutzer; Inhalt rollenabhängig (canManageShifts/isTeamLead/Mitarbeiter; Inventar-Einträge nur canViewInventory/canManageInventory; Schicht-Einträge nur canViewSchedule)

**Unterbereiche / Tabs (5)**

- **Header + Hero-Card** — Titel 'Anfragen' + rollenabhängiger Untertitel (TeamLead/Manager/Mitarbeiter je eigener Text). _InboxHeroCard: 'Arbeitsdruck jetzt' (Manager) bzw. 'Deine offenen Rueckmeldungen' (Mitarbeiter), 3 Pillen (X Antraege / X Tausch / X kritisch bzw. X Updates).
- **Bereich 'Zu erledigen'** — _InboxSection.todo, immer offen/oben, in Warnfarbe hervorgehoben mit Anzahl-Pille. Leer-Zustand: grüner Erfolgs-Banner 'Alles erledigt – nichts wartet auf deine Entscheidung.' (nur bei Filter Alle/Kritisch). Enthält Freigabe-pflichtige Vorgänge.
- **Bereich 'Läuft & wartet'** — _InboxSection.inProgress, einklappbare ExpansionTile (Standard eingeklappt) mit Live-Anzahl-Pille, dense Karten. Kommende Schichten zuerst, dann nach Aktualität.
- **Bereich 'Verlauf & Hinweise'** — _InboxSection.history, einklappbare ExpansionTile (Standard eingeklappt), reine Info-Einträge (genehmigt/abgelehnt, abgeschlossene Tausche, Nachbestell-Hinweis).
- **Filter-Chips (ChoiceChip, horizontal scrollbar)** — 'Alle', 'Kritisch' (Mitarbeiter: 'Offen'), 'Antraege', 'Tausch', und 'Updates' (Mitarbeiter: 'Schichten'). Label + verfügbare Filter wechseln je nach canManageShifts.

**Aktionen (14)**

- Schnell-Buttons 'Krank' / 'Urlaub' / 'Nicht verfuegbar' (OutlinedButton, öffnen Abwesenheits-Sheet) — nur bei canCreateOwnRequests (Nicht-Manager ODER TeamLead)
- Filter-Chips wechseln
- Bereiche 'Läuft & wartet' / 'Verlauf & Hinweise' auf-/zuklappen
- Karten-Aktionen Abwesenheit (Review): 'Ablehnen' / 'Genehmigen' — nur canReviewAbsence (Manager, fremder Antrag)
- Karten-Aktionen eigener offener Antrag: 'Bearbeiten' (öffnet Sheet) / 'Löschen' (Bestätigungsdialog)
- Karten-Aktionen genehmigter Urlaub (Manager): 'Bearbeiten' / 'Löschen' (Dialog 'Urlaub löschen')
- Tausch (alte shift.swapStatus): 'Ablehnen' / 'Freigeben' — nur canManageShifts
- Kommende eigene Schicht (nur Nicht-Manager): 'Tausch' / 'Krank melden' — max. 6
- Tauschanfrage an mich (Kollege): 'Ablehnen' / 'Annehmen'
- Eigene Tauschanfrage: 'Zurückziehen'
- Tausch bestätigen (Chef, acceptedByColleague): 'Ablehnen' / 'Übernehmen' (mit Compliance-Preview)
- Schicht-Gutschrift: 'Stornieren' (nur Manager) / 'Eingelöst'
- Kundenbestellung: 'Als vorbereitet markieren' — nur canManageInventory
- Kühlschrank-Warnung: 'Zum Kühlschrank' (Deeplink /warenwirtschaft?tab=kuehl) — nur canViewInventory

**Sheets & Dialoge (4)**

- showAbsenceRequestSheet (Antrag erstellen/bearbeiten)
- AlertDialog 'Antrag löschen'
- AlertDialog 'Urlaub löschen'
- AlertDialog 'Regelverstoß beim Übernehmen' (_showSwapComplianceDialog, Trotzdem übernehmen)

**Versteckt / gegatet (11)**

- ⨯ Schnell-Buttons Krank/Urlaub/Nicht verfuegbar nur bei canCreateOwnRequests (versteckt für reine Admins)
- ⨯ TeamLead-Hinweistext 'Deine eigenen Antraege landen zur Freigabe beim Admin.' nur bei isTeamLead
- ⨯ Review-Buttons Genehmigen/Ablehnen nur canManageShifts und nicht eigener Antrag (TeamLead darf eigene nicht selbst genehmigen)
- ⨯ Kommende-Schicht-Einträge nur für Nicht-Manager und canViewSchedule
- ⨯ Alle Inventar-Einträge (Kundenbestellung, Ablauf/MHD, Meldebestand, Kühlschrank) nur bei canViewInventory; 'Als vorbereitet markieren'/Aktionen nur canManageInventory
- ⨯ Gutschrift-Storno nur canManageShifts
- ⨯ Filter-Set/-Labels wechseln je Rolle (Kritisch↔Offen, Updates↔Schichten)
- ⨯ Hero-Text und Untertitel variieren nach Rolle
- ⨯ MHD-/Ablauf-Warnung erscheint nur wenn expiryWarnings vorhanden; Meldebestand/Kühlschrank nur bei Datenzustand > 0
- ⨯ 'Zu erledigen'-Erfolgsbanner nur wenn leer UND Filter Alle/Kritisch
- ⨯ Bei komplett leerer Inbox: großer Leerzustand 'Keine passenden Eintraege...' bzw. Manager 'Im aktuellen Filter gibt es keine offenen Vorgänge.'

> Zentrale rollen-/status-adaptive Inbox aus 5 Quellen (Abwesenheiten, alte+neue Tausche, Gutschriften, Inventar-Warnungen). Kann eingebettet in Shell (ohne Scaffold, mit Breadcrumb 'Anfragen') oder standalone (BreadcrumbAppBar Heute>Anfragen) laufen. Karten-Aktionen zeigen 'Bitte warten...' während _busy, Erfolgs-SnackBar via successMessage.

### Abwesenheits-Antrag (Sheet) · `modal-sheet`

**Route:** `— (Sheet/imperativ) showAbsenceRequestSheet`  
**Zugriff:** alle die einen Antrag stellen dürfen; Bearbeiten genehmigten Urlaubs nur Manager

**Unterbereiche / Tabs (8)**

- **Art-Dropdown** — DropdownButtonFormField über alle AbsenceType.values (t.label). Bei genehmigtem Urlaub gesperrt (isApprovedVacationEdit → onChanged null).
- **Halbtägig-Schalter + Segment** — SwitchListTile 'Halbtägig' nur wenn regelFor(_type).halbtagFaehig; darunter SegmentedButton 'Vormittags'/'Nachmittags'.
- **Krankheits-Hinweis** — Bei AbsenceType.sickness: Info 'Lohnfortzahlung 6 Wochen (EFZG); danach Krankengeld der Kasse.'
- **Stunden-Feld (Zeitausgleich)** — Bei AbsenceType.timeOff: TextField 'Stunden (Zeitausgleich)' mit Suffix h, deutsches Dezimalkomma.
- **Zeitraum Von/Bis** — Zwei ListTiles mit showDatePicker (locale de_DE, -30 bis +365 Tage).
- **Resturlaub-Vorschau** — _buildResturlaubVorschau: Live 'Resturlaub JJJJ: X → nach Antrag Y (Z angefragt).' NUR bei Urlaub UND profile.isAdmin UND PersonalProvider vorhanden. Warnfarbe bei Überziehung.
- **Vertreter-Auswahl** — _buildVertreterSelector: FilterChips über Org-Mitglieder (Self-Exclusion), 'Vertretung (optional)'. Versteckt wenn keine Mitglieder geladen.
- **Hinweis-Feld + Absenden** — TextField 'Hinweis' (optional). FilledButton 'Antrag senden' bzw. 'Aenderungen speichern' (Bearbeiten), Spinner 'Wird gespeichert...'.

**Aktionen (7)**

- Art wählen
- Halbtägig umschalten + Vormittags/Nachmittags
- Von/Bis-Datum wählen (DatePicker)
- Stunden eingeben (nur Zeitausgleich)
- Vertreter per Chip wählen/abwählen
- Hinweis eingeben
- 'Antrag senden' / 'Aenderungen speichern'

**Sheets & Dialoge (1)**

- showDatePicker (Von/Bis)

**Versteckt / gegatet (7)**

- ⨯ Halbtägig-Bereich nur bei halbtag-fähiger Art
- ⨯ Krankheits-Hinweistext nur bei sickness
- ⨯ Stunden-Feld nur bei timeOff (Zeitausgleich)
- ⨯ Resturlaub-Vorschau nur bei Urlaub + isAdmin + geladenen PersonalProvider-Daten (sonst keine Scheinzahlen)
- ⨯ Vertreter-Selector versteckt ohne geladene Org-Mitglieder
- ⨯ Bei genehmigtem Urlaub: Art-Dropdown + Halbtägig gesperrt (nur Zeitraum/Hinweis änderbar)
- ⨯ Titel/Untertitel wechseln zwischen Erstellen/Bearbeiten/genehmigter-Urlaub-Bearbeiten

> Ein wiederverwendetes Bottom-Sheet für Krank/Urlaub/Nicht verfügbar/Zeitausgleich, aufgerufen von Anfragen-Screen, kommenden Schichten und mehreren Stellen der App. Validiert Enddatum>=Start und Stunden>0. Provider tolerant via _maybeRead (crasht nicht im Widget-Test).

### Mitteilungen (In-App-Inbox) · `section-screen`

**Route:** `/mitteilungen`  
**Zugriff:** jeder angemeldete Nutzer (self-scoped, eigene server-erzeugte Mitteilungen)

**Unterbereiche / Tabs (2)**

- **Mitteilungsliste** — ListView.separated der eigenen AppNotifications; ungelesene in infoContainer-Farbe + aktives Glocken-Icon + fette Schrift. Titel, Body, Datum (dd.MM.yyyy HH:mm).
- **Leerzustand** — AppEmptyState Icon notifications_none + 'Keine Mitteilungen.'

**Aktionen (1)**

- ListTile-onTap: markiert als gelesen (markAsRead) und navigiert via notification.route (nur wenn RoutePermissions.isLocationAllowed) — chevron_right nur wenn Route vorhanden

**Versteckt / gegatet (3)**

- ⨯ chevron_right/Navigation nur wenn notification.route gesetzt
- ⨯ Navigation nur wenn Nutzer das Ziel sehen darf (Permission-Check unterdrückt sonst still)
- ⨯ Ungelesen-Hervorhebung (Farbe/Icon/Fettschrift) nur bei isUnread

> PERSONAL-9/Q4. Breadcrumb 'Übersicht > Mitteilungen'. Reine Anzeige der server-erzeugten Push-/In-App-Mitteilungen, self-scoped.

### Benachrichtigungs-Einstellungen · `section-screen`

**Route:** `— (Push-Einstellungen, via Einstellungen erreichbar)`  
**Zugriff:** jeder Nutzer (eigene notificationPrefs in users/{uid})  
**Feature-Flag:** APP_PUSH_ENABLED (Push nur bei gesetztem Flag real wirksam; Screen selbst zeigt Präferenzen)

**Unterbereiche / Tabs (3)**

- **Master-Schalter** — SwitchListTile 'Push-Benachrichtigungen' / 'Mitteilungen auf dieses Gerät senden.'
- **Kategorien** — 5 SwitchListTiles: 'Genehmigungen' (Abwesenheits-/Tauschanträge), 'Schichtplan', 'Aufgaben & Kühlschrank', 'Kundenwünsche', 'Bestand & Nachbestellung'. Alle deaktiviert wenn Master aus.
- **Ruhezeiten** — SwitchListTile 'Nicht stören' (nur Genehmigungen kommen durch) + bei aktiv: ListTiles 'Von'/'Bis' mit showTimePicker.

**Aktionen (5)**

- Master-Schalter umlegen
- Je Kategorie-Schalter umlegen
- 'Nicht stören' umschalten
- 'Von'-Zeit wählen (showTimePicker)
- 'Bis'-Zeit wählen (showTimePicker)

**Sheets & Dialoge (1)**

- showTimePicker (Von / Bis Ruhezeit)

**Versteckt / gegatet (4)**

- ⨯ Kategorie-Schalter alle disabled wenn Master aus
- ⨯ 'Nicht stören' + Von/Bis disabled wenn Master aus
- ⨯ Von/Bis-ListTiles nur sichtbar wenn quietHoursEnabled UND master
- ⨯ Fußnote 'Alle Vorgänge findest du auch unter Anfragen. Push ist nur der Auslöser.'

> Persistiert via AuthProvider.updateNotificationPrefs ins users/{uid}-Doc; Server respektiert Präferenzen vor Versand. 5 Kategorien deckungsgleich mit den Android-Channels.

---

<a id="cluster-5"></a>

## 5. Kontakte (Liste + Detail 7 Tabs + Editor)

*6 Bereiche.*

### Kontakte (Liste) · `tab-hub`

**Route:** `/kontakte`  
**Zugriff:** canViewContacts (lesen alle aktiven Mitglieder); ohne Recht Vollbild „Keine Berechtigung für Kontakte.“

**Unterbereiche / Tabs (8)**

- **SectionHeader „Kontakte“** — Titel + Untertitel „Kunden, Lieferanten und Partner der beiden Läden“, Breadcrumb, optionaler Zurück-Pfeil (canNavigateBack)
- **Statistik-Zeile** — 3 AppMetricCards: „Aktiv“, „Kunden“, „Lieferanten“ (Zähler)
- **Such-/Export-Zeile** — Suchfeld „Suchen (Name, Ansprechpartner, Ort, …)“ + Export-Button + CSV-Import-Button
- **Kind-Filter (SegmentedButton)** — „Alle“ / „Personen“ (person_outline) / „Firmen“ (business)
- **Kategorie-Filter (Chips)** — „Alle“ + je vorhandener ContactType ein AppFilterChip mit Label+Anzahl, z. B. „Kunde (n)“, horizontal scrollbar
- **Standort-/Toggle-Filter (Chips)** — nur wenn Standorte vorhanden: „Alle Standorte“, „Allgemein“, je Standort ein Chip; immer: „Wichtig“ (star), „Archivierte zeigen“ (inventory_2)
- **Ergebnis-Zählleiste** — „N Kontakte“ bzw. „M von N Kontakten“ + „Filter zurücksetzen“ (nur bei aktiven Filtern)
- **Kontaktliste** — Karten (_ContactCard): Avatar, displayName, Favoriten-Stern, Kategorie-Badge, „Archiviert“-Badge, Standort-Chip, Untertitel (Ansprechpartner/Telefon/E-Mail/Ort)

**Aktionen (10)**

- ExpandableFab (nur canManage) mit FabAction „Kontakt“ (Neuanlage)
- Export-Button (PopupMenuButton, ios_share): „Als PDF exportieren“, „Als CSV exportieren“
- CSV-Import-Button (file_upload) → Dialog „Kontakte aus CSV importieren“
- TextButton „Organisationen“ (domain_outlined) → OrganizationsScreen
- Suchfeld onChanged (Live-Filter)
- Kind-/Kategorie-/Standort-/Toggle-Filterchips
- „Filter zurücksetzen“ (Zählleiste + Leerzustand)
- Karte onTap → Kontakt-Detailseite
- Karten-Overflow-Menü (_CardMenu, nur canManage): „Als wichtig“/„Nicht mehr wichtig“, „Bearbeiten“, „Löschen“
- Leerzustand-CTA „Ersten Kontakt anlegen“ (nur canManage)

**Sheets & Dialoge (7)**

- ContactEditorSheet (Bottom-Sheet, Anlegen/Bearbeiten)
- CSV-Import-Dialog (AlertDialog mit Textfeld „Einlesen“)
- AppConfirmDialog „Importieren?“
- Dubletten-Dialog „Möglicherweise doppelt“ (Abbrechen/Trotzdem anlegen/Zusammenführen)
- AppConfirmDialog „Kontakt löschen?“
- _ContactDetailSheet (Fallback-Detail-Sheet für Kontakte ohne Doc-ID)
- Aktivität-erfassen-Dialog (aus Detail-Sheet-Fallback)

**Versteckt / gegatet (9)**

- ⨯ ExpandableFab + Karten-Overflow-Menü (Bearbeiten/Löschen/Favorit) nur bei canManageContacts
- ⨯ CSV-Import prüft canManageContacts erneut, sonst „Keine Berechtigung zum Importieren.“
- ⨯ Standort-Filterchips nur wenn sites.isNotEmpty
- ⨯ Kategorie-Chips nur für tatsächlich vorhandene ContactTypes
- ⨯ „Filter zurücksetzen“ nur bei aktiven Filtern
- ⨯ Archivierte (isActive==false) nur sichtbar bei aktivem Toggle „Archivierte zeigen“
- ⨯ Favoriten-Stern-Icon nur bei isFavorite
- ⨯ Fehler-Banner nur bei contactProvider.errorMessage
- ⨯ Fallback-Detail-Sheet (_ContactDetailSheet) nur bei Kontakt ohne Doc-ID (Randfall)

> Sentinel _kGeneralSite='__general__' für Kontakte ohne Laden. Sortierung: Favoriten zuerst, dann Name. Fallback-Sheet zeigt zusätzlich Detail-Aktion „Aktivität erfassen“ und Detailfelder mit Kopieren.

### Kontakt-Detailseite · `detail-tab`

**Route:** `/kontakte/{id}`  
**Zugriff:** canViewContacts (lesen alle aktiven Mitglieder, NICHT admin-only); Verwaltungs-Aktionen nur canManageContacts

**Unterbereiche / Tabs (8)**

- **VCard (Kopf-Visitenkarte)** — Avatar (Bild/Initialen) mit Kamera-Overlay zum Upload, Name, Favoriten-Stern, legalName, Untertitel (Position · Kategorie · Nr.), Chips: Person/Firma, Status, „Blacklist“, „Archiviert“
- **Tab „Übersicht“** — Stammdaten, Geschäftsdaten (Kundennr./Debitoren/Kreditoren/USt-ID/Handelsregister/Kunde seit), Zuordnung (Standort), Kommunikation-Quickview, Hauptadresse, „Letzte Aktivitäten“ (5)
- **Tab „Adressen“** — Hauptadresse (Straße/PLZ/Ort) + typisierte Zusatzadressen (Haupt/Rechnung/Lieferung/Niederlassung) mit Bearbeiten/Entfernen
- **Tab „Kommunikation“** — Strukturierte Kanäle gruppiert nach Kontext (Dienst/Privat/Firma), Primär-Badge, Kopieren; flache Stammdaten-Kanäle „Aus Stammdaten“ (read-only)
- **Tab „Ansprechpartner“** — Firma: verknüpfte Personen (Rolle, Hauptkontakt) mit Zuordnen; Person: zugehörige Firma (parentContactId) auswählen/entfernen; Freitext-Ansprechpartner aus Stammdaten (read-only)
- **Tab „Einwilligungen“** — DSGVO-Consent-Status-Chips (Datenverarbeitung/E-Mail/Telefon/Weitergabe) + Liste erteilter/widerrufener Consents; Erfassen und Widerrufen
- **Tab „Bank“** — Bankverbindungen (IBAN/BIC/Bankname/Inhaber, aktiv/inaktiv) mit Hinzufügen/Bearbeiten/Entfernen
- **Tab „Notizen“** — Interne Bemerkungen + Schlagworte (Chips)

**Aktionen (9)**

- AppBar-Action „Bearbeiten“ (edit_outlined, nur canManage) → ContactEditorSheet
- Avatar-Kamera-Overlay (nur canManage & Firebase konfiguriert) → Bild-Upload
- Breadcrumb-Rücksprung (maybePop)
- Adressen: „Adresse“ (hinzufügen), _ItemMenu Bearbeiten/Entfernen je Adresse
- Kommunikation: „Kanal“ (hinzufügen), je Kanal Kopieren + _ItemMenu Bearbeiten/Entfernen
- Ansprechpartner (Firma): „Zuordnen“, je Person _ItemMenu Bearbeiten/Entfernen
- Ansprechpartner (Person): „Firma auswählen“ (swap_horiz), „Firma entfernen“ (clear)
- Einwilligungen: „Erfassen“, je aktivem Consent „Widerrufen“
- Bank: „Bankverbindung“ (hinzufügen), _ItemMenu Bearbeiten/Entfernen

**Sheets & Dialoge (9)**

- ContactEditorSheet
- showAddressDialog
- showChannelDialog
- showContactPersonDialog
- showCompanyPickerDialog
- showConsentDialog
- showBankAccountDialog
- AppConfirmDialog (Adresse/Kanal/Ansprechpartner/Consent-Widerruf/Bankverbindung entfernen)
- Datei-Picker (Avatar-Upload)

**Versteckt / gegatet (12)**

- ⨯ Alle Hinzufügen-/Bearbeiten-/Entfernen-Buttons in allen Tabs nur bei canManageContacts (sonst read-only + Platzhalter-Leerzustände)
- ⨯ Avatar-Kamera-Overlay nur wenn canManage && ContactAvatarUploader.isAvailable (Firebase konfiguriert, kein Demo/Offline-Modus)
- ⨯ AppBar „Bearbeiten“ nur canManage
- ⨯ „Blacklist“-Badge nur bei blacklisted
- ⨯ „Archiviert“-Badge nur bei !isActive
- ⨯ Favoriten-Stern nur bei isFavorite
- ⨯ legalName-Zeile nur wenn gesetzt
- ⨯ Ansprechpartner-Tab wechselt Inhalt je Person/Firma (isCompany)
- ⨯ Kommunikation: flache Stammdaten-Kanäle nur wenn keine strukturierten Kanäle vorhanden
- ⨯ Übersicht/Stammdaten/Geschäftsdaten-Karten nur wenn Werte vorhanden
- ⨯ Cold-Start: Ladeindikator bei leerer Liste, sonst „Kontakt nicht gefunden“
- ⨯ Lese-Gate: ohne canViewContacts „Keine Berechtigung für Kontakte.“

> Exakt 7 Tabs (Icon+Text, scrollbar) 1:1 zu AllTec: Übersicht·Adressen·Kommunikation·Ansprechpartner·Einwilligungen·Bank·Notizen. Sub-Objekt-Änderungen persistieren via ContactProvider.saveContact. Widerruf setzt withdrawnAt (kein Löschen).

### Kontakt-Editor (Sheet) · `modal-sheet`

**Route:** `— (Sheet/imperativ)`  
**Zugriff:** canManageContacts (Aufrufer gatet den Öffnen-Button)

**Unterbereiche / Tabs (6)**

- **Person/Firma-Umschalter** — SegmentedButton „Person“ / „Firma“ — blendet passende Stammdatenfelder ein
- **Personenfelder** — Anrede (Gender), Titel, Vorname, Nachname* (Pflicht/Alias), Position, Abteilung, Geburtstag
- **Firmenfelder** — Firmenname* (Pflicht/Alias), Offizieller Name (Handelsregister), Handelsregister-Nr., Firmen-Jubiläum
- **Kategorie + Status** — Dropdown Kategorie (ContactType), Dropdown Status (aktiv/inaktiv/gesperrt)
- **Gemeinsame Felder** — Anzeigename (Alias), Ansprechpartner, Telefon, Mobil, E-Mail, Website, Straße & Nr., PLZ, Ort, USt-IdNr./Steuer-Nr., Kunden-/Lief.-Nr., Debitoren-Nr., Kreditoren-Nr., „Kunde seit“, Standort (Dropdown), Schlagworte, Notiz
- **Schalter** — „Auf der Blacklist“, „Als wichtig markieren“, „Aktiv“

**Aktionen (5)**

- SegmentedButton Person/Firma
- DatePicker-Felder (Geburtstag/Firmen-Jubiläum/Kunde seit) mit Löschen
- Standort-Dropdown „Allgemein (beide Läden)“ + je Standort
- 3 SwitchListTiles
- „Kontakt anlegen“ / „Speichern“ (Submit mit Validierung)

**Sheets & Dialoge (1)**

- showDatePicker (3 Datumsfelder)

**Versteckt / gegatet (3)**

- ⨯ Personen- vs. Firmenfelder wechseln über _kind-Umschalter
- ⨯ Standort-Dropdown nur wenn sites.isNotEmpty
- ⨯ Pflicht (Nachname*/Firmenname*) entfällt wenn Alias gesetzt (_requiredOrAlias)

> name wird beim Speichern abgeleitet: Alias → Firma/Person → Bestand. Legacy-Prefill splittet alten name in Vor-/Nachname. Sub-Objekt-Listen (Adressen/Bank/Kanäle/Consents) bleiben unangetastet. Rückgabe via Navigator.pop(Contact), Persistenz beim Aufrufer.

### Sub-Objekt-Dialoge (Kontakt-Detail) · `dialog`

**Route:** `— (Modal)`  
**Zugriff:** canManageContacts

**Unterbereiche / Tabs (6)**

- **Adress-Dialog** — Adresstyp* (Haupt/Rechnung/Lieferung/Niederlassung), Bezeichnung, Straße, Nr., PLZ, Ort, Land (Default Deutschland), Adresszusatz, Postfach, PLZ Postfach
- **Bank-Dialog** — IBAN* (Validierung Länge≥15), BIC, Bankname, Kontoinhaber, Schalter „Deaktiviert“
- **Kanal-Dialog** — Art (ChannelType), Kontext (Dienst/Privat/Firma), Wert*, Bezeichnung, Erreichbarkeit, Schalter „Primärer Kanal“
- **Consent-Dialog** — Art der Einwilligung (ConsentType), Kontext/Grund; „Erfassen“ setzt grantedAt
- **Ansprechpartner-Dialog** — Person* (Dropdown wählbarer Personen), Rolle, Schalter „Haupt-Ansprechpartner“
- **Firmen-Picker-Dialog** — Dropdown „Firma*“ zur Auswahl der zugehörigen Firma (parentContactId)

**Aktionen (2)**

- Speichern/Anlegen/Erfassen (mit Formvalidierung)
- Abbrechen

**Versteckt / gegatet (3)**

- ⨯ Nur canManage öffnet diese Dialoge (Buttons in Detail-Tabs sind gated)
- ⨯ Firmen-Picker Speichern deaktiviert bis Firma gewählt
- ⨯ Ansprechpartner-Dropdown ergänzt defensiv bestehende, nicht mehr gelistete Person

> Eingebettete Sub-Objekte mit lokal generierter ID (_newId, kein Firestore-Doc). Consent-Widerruf erfolgt nicht hier, sondern im Tab (setzt withdrawnAt).

### Organisationen (Adressbuch) · `section-screen`

**Route:** `— (imperativ Navigator.push von Kontaktliste)`  
**Zugriff:** canViewContacts (lesen), canManageContacts (verwalten)

**Unterbereiche / Tabs (1)**

- **Organisationsliste** — ListTiles mit Typ-Icon, Name, Ort (Untertitel), Typ-Chip; Typen: Agentur für Arbeit, Jobcenter, Praktikumsbetrieb, Kooperationspartner, Behörde, Sonstige

**Aktionen (2)**

- FloatingActionButton.extended „Organisation“ (add_business, nur canManage) → Anlege-Dialog
- Je Zeile PopupMenuButton (nur canManage): „Bearbeiten“, „Löschen“

**Sheets & Dialoge (2)**

- _OrganizationDialog (Neu/Bearbeiten: Name*, Typ, Ort, Website mit URL-Validierung)
- AppConfirmDialog „Organisation löschen?“

**Versteckt / gegatet (3)**

- ⨯ FAB + Zeilen-Overflow-Menü nur bei canManageContacts
- ⨯ Leerzustand „Keine Organisationen“ wenn leer
- ⨯ ohne canViewContacts „Keine Berechtigung für Kontakte.“

> AllTec-1:1 (OrganizationListPage). Eigenständiges Adressbuch getrennt von Contacts. Website-Validierung erzwingt vollständige URL (https://…).

### Kontaktauswahl (Picker) · `modal-sheet`

**Route:** `— (Sheet/imperativ)`  
**Zugriff:** liest ContactProvider (bereits gestreamte Liste); von Aufrufern genutzt (z. B. Bestellungen, Kundenwünsche/-feedback)

**Unterbereiche / Tabs (2)**

- **ContactPickerField** — Auswahlfeld mit person_search-Icon, zeigt gewählten Kontaktnamen oder emptyLabel (z. B. „Laufkunde (kein Kontakt)“)
- **Picker-Sheet** — Suchfeld „Kontakt suchen“, „Kein Kontakt“-Eintrag, gefilterte/sortierte Kontaktliste mit Initialen-Avatar, Typ + Telefon/E-Mail

**Aktionen (4)**

- Feld onTap → Picker-Sheet
- Suche onChanged
- „Kein Kontakt“/emptyLabel wählen (Laufkunde)
- Kontakt in Liste antippen

**Sheets & Dialoge (1)**

- _ContactPickerSheet (showModalBottomSheet)

**Versteckt / gegatet (2)**

- ⨯ Optionaler Typfilter allowedTypes (z. B. nur Lieferanten); bereits verknüpfter Kontakt bleibt sichtbar auch außerhalb Filter
- ⨯ Leerzustand „Keine Kontakte gefunden.“

> ContactSelection unterscheidet „kein Kontakt gewählt“ (contact==null) von „Sheet abgebrochen“ (Rückgabe null). Keine zusätzlichen Firestore-Reads.

---

<a id="cluster-6"></a>

## 6. Warenwirtschaft Kern (Inventar/Bestellungen/Inventur)

*26 Bereiche.*

### Warenwirtschaft (Hub + App-Leiste) · `tab-hub`

**Route:** `/warenwirtschaft`  
**Zugriff:** canViewInventory (sonst Vollbild „Keine Berechtigung fuer die Warenwirtschaft.“)

**Unterbereiche / Tabs (5)**

- **Tab: Bestand** — inventory_2_outlined, Badge = lowStockCount (Warnton). Deeplink initialTabIndex 0
- **Tab: Kühlschrank** — kitchen_outlined, Badge = max(offene Nachfüll, Soll-Ist-Lücken) nur bei eindeutigem Laden. Deeplink ?tab=kuehl (Index 1)
- **Tab: Lieferanten** — local_shipping_outlined, kein Badge
- **Tab: Bestellkorb** — shopping_cart_outlined, Badge = cartItemCount. Deeplink cartTabIndex 3
- **Tab: Bestellungen** — receipt_long_outlined, Badge = Anzahl offener Bestellungen (ggf. laden-gefiltert)

**Aktionen (7)**

- AppBar: Lupe „Artikel suchen“/„Suche schließen“ (nur Bestand-Tab, blendet eingeklapptes Suchfeld ein)
- AppBar: „Inventur (Bestand zählen)“ fact_check_outlined → /inventur (nur canManage + Bestand-Tab)
- AppBar: OktoPOS-Menü point_of_sale (Verkäufe übernehmen / Artikel an Kasse senden / Kunden an Kasse senden / Preisabgleich Kasse / Einstellungen)
- AppBar: Auswertungen-Menü insights_outlined (Bestell-Auswertung / Bestand-Insights / Sortimentsanalyse / Kassenbericht / Laden-Benchmark / Tagesabschluss (Kasse))
- AppBar: „Kundenwünsche“ inbox_outlined → /kundenwuensche
- AppBar: Export-Menü ios_share (Bestandsliste PDF/CSV, Nachbestellliste PDF/CSV)
- Standort-Filterleiste ChoiceChips „Alle Läden“ + je Laden (nur bei >1 Standort)

**Sheets & Dialoge (3)**

- OktoPOS-Laden-Auswahl-Sheet „Welcher Laden?“
- Bestätigungsdialoge „Artikel an Kasse senden?“ / „Kunden an Kasse senden?“
- Kassen-Einstellungen-Sheet (OktoPOS)

**Versteckt / gegatet (8)**

- ⨯ Suchfeld ist standardmäßig eingeklappt, nur über Lupen-Button sichtbar (autofokussiert)
- ⨯ Inventur-AppBar-Button nur bei canManageInventory + aktivem Bestand-Tab
- ⨯ OktoPOS-Menü nur bei AppConfig.oktoposEnabled && profile.isAdmin
- ⨯ Auswertungen-Menüpunkte Bestand-Insights/Sortiment/Kassenbericht/Laden-Benchmark nur isAdmin; Tagesabschluss nur isAdmin||isTeamLead; Bestell-Auswertung immer
- ⨯ Standort-Filterleiste nur wenn sites.length > 1
- ⨯ Auf Handybreite (<mediumWindow 600) zeigen alle Tabs NUR Icon+Badge, Label lebt in Tooltip/Semantics
- ⨯ Tab-Badges verschwinden ohne eindeutigen Laden (Kühlschrank/Bestellkorb zeigen dann „Laden wählen“)
- ⨯ Fehler-Banner (errorContainer) nur bei inventory.errorMessage != null

> InventoryScreen, 5-Tab TabController (SingleTickerProvider). parentLabel default „Profil“. maxWidth 1100 zentriert. FAB je Tab unterschiedlich (siehe Tab-Areas). OktoPOS-Aktionen lösen Cloud Functions aus, API-Key bleibt serverseitig.

### Bestand-Tab · `sub-tab`

**Route:** `— (Tab 0 in /warenwirtschaft)`  
**Zugriff:** canViewInventory (Bearbeiten/Buchen nur canManageInventory)

**Unterbereiche / Tabs (5)**

- **Warenwert-Metrikblock** — EK-Warenwert / Verkaufswert / Spanne — nur canManage & valueCents>0
- **Nachbestell-Banner** — „X Artikel unter Mindestbestand – jetzt nachbestellen“, tappbar → Bestell-Editor mit prefillReorder
- **Schnellfilter-Chips** — Nachbestellen (n) / Leer (n) / Kühlschrank + Warengruppen-Popup
- **Sortierung-Popup** — Name (A–Z) / Bestand (niedrig zuerst) / Warenwert (hoch zuerst, nur canManage)
- **Artikelliste** — _ProductTile mit Bestandsavatar, Status-Pillen (Leer/Bestellt unterwegs/Nachbestellen), Min/VK/Warengruppe/Standort-Pillen

**Aktionen (9)**

- Suchfeld TextField (Name, Artikelnr. oder Barcode) — eingeblendet via AppBar-Lupe
- Filter-Chip Nachbestellen / Leer / Kühlschrank
- Warengruppe-Filter-Popup (Chip)
- Sortier-Popup (sort-Icon)
- Nachbestell-Banner-Tap → Bestell-Editor
- Pro Tile: „In den Bestellkorb“ add_shopping_cart (ALLE aktiven)
- Pro Tile: onTap Bearbeiten (nur canManage)
- Pro Tile: Artikel-Aktionen-Popup (Bearbeiten / Zugang buchen / Abgang buchen / Bestand korrigieren / Inventur / Umlagern / Bewegungen anzeigen / Preisverlauf / Löschen) — nur canManage
- FAB (ExpandableFab): Scanner (canManage) / Artikel (canManage) / Kühlschrank nachfüllen / In den Warenkorb

**Sheets & Dialoge (12)**

- showOrderQuantityDialog „In den Bestellkorb“
- Artikel-Dialog (Neu/Bearbeiten)
- Dialog „Zugang buchen“ (Wareneingang ohne Bestellung)
- Dialog „Abgang buchen“ (Menge + Grund, Live-Validierung)
- Dialog „Bestand korrigieren“ (delta + Grund)
- Dialog „Inventur“ (gezählter Bestand, keine Vorbefüllung)
- Dialog „Umlagern“ (Ziel-Standort + Menge, Auto-Anlage am Ziel)
- Bewegungen-Sheet (Bewegungshistorie)
- Preisverlauf-Sheet
- Löschen-Bestätigung
- Scanner-Screen (context.push AppRoutes.scanner)
- showQuickAddCartSheet / showFridgeRefillAddSheet (via FAB)

**Versteckt / gegatet (8)**

- ⨯ Warenwert-Metrikblock (EK/VK/Spanne) nur canManage und wenn Warenwert>0
- ⨯ Nachbestell-Banner nur wenn lowStock nicht leer UND canManage
- ⨯ Warengruppe-Filter-Popup nur wenn Warengruppen existieren
- ⨯ Sortieroption „Warenwert“ nur canManage (wird bei Rechtsentzug defensiv auf Name zurückgesetzt)
- ⨯ Schnellfilter-/Sortier-Zeile nur wenn allForSite nicht leer
- ⨯ Status-Pille „Bestellt, unterwegs“ nur wenn needsReorder & Zulauf deckt
- ⨯ Artikel-Aktionen-Popup + onTap-Bearbeiten nur canManage
- ⨯ FAB-Aktionen Scanner/Artikel nur canManage (Mitarbeiter sehen nur Korb+Kühlschrank)

> _StockTab/_StockTabState. Clientseitige Substring-Suche (kein Index). _StockFilter{alle,nachbestellen,leer,kuehlschrank}, _StockSort{name,bestand,wert}. Bestand beim Bearbeiten read-only (nur über Korrektur/Inventur).

### Kühlschrank-Tab · `sub-tab`

**Route:** `— (Tab 1 in /warenwirtschaft)`  
**Zugriff:** alle aktiven (Liste leeren nur canManageInventory)

**Unterbereiche / Tabs (3)**

- **Abschnitt „Fehlt im Kühlschrank“** — automatische Soll-Ist-Lücken (_FridgeShortfallTile) mit Severity leer/nachfüllen/Lager knapp
- **Abschnitt „Aus dem Lager holen“** — offene manuelle Positionen (_FridgeItemTile) mit Checkbox + Mengenstepper
- **Abschnitt „Erledigt“** — abgehakte Positionen (durchgestrichen)

**Aktionen (6)**

- „Zur Liste hinzufügen“ (öffnet Kühlschrank-Hinzufügen-Sheet)
- „Erledigte aufräumen (n)“ (wenn erledigte existieren)
- „Liste leeren“ (nur canManage)
- Shortfall: „Nachgefüllt“ (voll) + Teilmengen-Popup (+1/+5/+10/volle Lücke)
- Item: Checkbox erledigt, +/- Mengenstepper, Entfernen (Papierkorb)
- FAB: Kühlschrank nachfüllen (ExpandableFab)

**Sheets & Dialoge (2)**

- Kühlschrank-Hinzufügen-Sheet (_FridgeAddSheet)
- Bestätigung „Liste leeren?“

**Versteckt / gegatet (5)**

- ⨯ „Bitte oben einen Laden wählen“ EmptyState wenn kein eindeutiger Laden
- ⨯ „Erledigte aufräumen“ nur wenn erledigte Positionen existieren
- ⨯ „Liste leeren“ nur canManage && Liste nicht leer
- ⨯ Shortfall-Abschnitt nur wenn automatische Lücken bestehen; Dedupe gegen manuelle Positionen
- ⨯ Mengenstepper nur bei offenen (nicht erledigten) Positionen

> FridgeRefillTab (fridge_refill_screen.dart). Kombiniert manuelle Nachfüllliste + automatische Soll-Ist-Shortfalls. FridgeShortfallSeverity{empty,refill,warehouseLow}.

### Lieferanten-Tab · `sub-tab`

**Route:** `— (Tab 2 in /warenwirtschaft)`  
**Zugriff:** canViewInventory (Bearbeiten/Löschen/Anlegen nur canManage)

**Unterbereiche / Tabs (1)**

- **Lieferantenliste** — Card je Lieferant: Name-Avatar, Ansprechpartner+Lieferzeit, antippbare Telefon-/E-Mail-Chips

**Aktionen (5)**

- Telefon-Chip → tel: (extern)
- E-Mail-Chip → mailto: (extern)
- onTap → Lieferant bearbeiten (nur canManage)
- Trailing-Popup: Bearbeiten / Löschen (nur canManage)
- FAB: Lieferant (nur canManage)

**Sheets & Dialoge (2)**

- Lieferant-Dialog (Neu/Bearbeiten)
- Löschen-Bestätigung

**Versteckt / gegatet (3)**

- ⨯ EmptyState „Noch keine Lieferanten“ mit Plus-Hinweis
- ⨯ onTap/Trailing-Popup/FAB nur canManage
- ⨯ Telefon-/E-Mail-Chips nur wenn Kontaktdaten vorhanden

> _SuppliersTab. effectiveOrderEmail bevorzugt orderEmail vor email.

### Bestellkorb-Tab · `sub-tab`

**Route:** `— (Tab 3 in /warenwirtschaft)`  
**Zugriff:** alle aktiven (Wochenliste bearbeiten / Korb leeren / Checkout nur canManage)

**Unterbereiche / Tabs (3)**

- **Korb-Aktionsleiste** — Wrap mit Standard-Wochenliste laden / Artikel / Wochenliste bearbeiten / Korb leeren
- **Korb-Positionen nach Lieferant gruppiert** — _CartItemTile mit Mengenstepper + Entfernen
- **Bestellen-Leiste** — _CheckoutButton (in-flight-Sperre) nur canManage

**Aktionen (7)**

- „Standard-Wochenliste laden“ (nur wenn Wochenliste existiert)
- „Artikel“ (öffnet Schnell-Warenkorb-Sheet)
- „Wochenliste bearbeiten“ (nur canManage) → Wochenlisten-Editor
- „Korb leeren“ (nur canManage & Positionen vorhanden)
- Pro Position: +/- Stepper, Entfernen
- „Bestellen (n Positionen)“ Checkout (nur canManage)
- FAB: In den Warenkorb (ExpandableFab)

**Sheets & Dialoge (4)**

- Schnell-Warenkorb-Sheet (_QuickAddCartSheet)
- Bestätigung „Bestellkorb leeren?“
- Bestätigung „Bestellung auslösen?“ (Liste der zu erzeugenden Bestellungen)
- Wochenlisten-Editor (WeeklyOrderListEditorScreen, Navigator.push)

**Versteckt / gegatet (5)**

- ⨯ „Bitte oben einen Laden wählen“ EmptyState ohne eindeutigen Laden
- ⨯ EmptyState-Unterscheidung: Stream-Fehler (cloud_off) vs. leerer Korb
- ⨯ Wochenliste-laden nur wenn weekly nicht leer
- ⨯ Wochenliste bearbeiten / Korb leeren / Checkout-Leiste nur canManage
- ⨯ Checkout gruppiert je Lieferant → mehrere Bestellungen; Doppel-Tap gesperrt

> OrderCartTab (order_cart_screen.dart). onCheckoutDone wechselt in Bestellungen-Tab. Checkout leert danach den Korb.

### Bestellungen-Tab · `sub-tab`

**Route:** `— (Tab 4 in /warenwirtschaft)`  
**Zugriff:** canViewInventory (Anlegen nur canManage)

**Unterbereiche / Tabs (3)**

- **„Heute erwartet“-Banner** — tappbar → Filter Erwartet, nur wenn heute Lieferungen erwartet
- **Status-Schnellfilter** — Alle / Offen (n) / Erwartet (n) / Geliefert / Storniert
- **Bestellliste** — Card mit Bestellnr., StatusChip, Lieferant, Positionen, Summe, offen-Mengen, heute-erwartet/überfällig-Badges

**Aktionen (4)**

- Filter-Chips (FilterChip)
- „Heute erwartet“-Banner-Tap
- onTap Bestellung → Bestellung-Detail
- FAB: Bestellung (nur canManage) → Bestell-Editor

**Sheets & Dialoge (2)**

- Bestellung-Detail (PurchaseOrderDetailScreen, Navigator.push)
- Bestell-Editor (PurchaseOrderEditorScreen)

**Versteckt / gegatet (5)**

- ⨯ EmptyState „Noch keine Bestellungen“
- ⨯ „Heute erwartet“-Banner nur wenn expectedToday nicht leer
- ⨯ FAB nur canManage
- ⨯ offen-von-Mengen-Pillen nur bei Status ordered/partiallyReceived
- ⨯ Liefertermin-Badge (heute erwartet/überfällig) nur bei fälligem Termin

> _OrdersTab. _OrderFilter{alle,offen,erwartet,geliefert,storniert}. Filter clientseitig, kein Index.

### Artikel-Dialog (Neu/Bearbeiten) · `dialog`

**Route:** `— (Dialog)`  
**Zugriff:** canManageInventory

**Unterbereiche / Tabs (3)**

- **Stammdaten** — Name*, Laden* (bei >1), Lieferant, Warengruppe, Einheit, Artikelnr., Barcode/EAN (Eindeutigkeit je Laden)
- **Preise/Bestände** — EK-Preis, VK-Preis, Bestand (nur Neuanlage editierbar), Mindestbestand, Bestellmenge, Zielbestand, USt-Satz
- **Kühlschrank-Block** — SwitchListTile „Im Verkaufs-Kühlschrank führen“ + Kühlschrank-Soll + Vorschlag-Button

**Aktionen (4)**

- Speichern / Abbrechen
- Kühlschrank-Soll „Vorschlag“ (velocity-basiert, nur bei gespeichertem Artikel)
- Barcode-Eindeutigkeitsvalidierung
- Preis-Validierung (blockiert Speichern bei unparsebar)

**Versteckt / gegatet (4)**

- ⨯ Laden-Dropdown nur bei sites.length > 1
- ⨯ Bestand-Feld read-only beim Bearbeiten (Helper „Nur über Bestand korrigieren/Inventur“)
- ⨯ Kühlschrank-Soll + Vorschlag-Button nur wenn Switch „Im Kühlschrank führen“ aktiv
- ⨯ Vorschlag meldet „erst nach Speichern / zu wenig Verkaufsdaten“

> _ProductDialog. Auch aus Scanner mit initialBarcode aufrufbar. clearX-Flags für nullbare Felder.

### Lieferant-Dialog (Neu/Bearbeiten) · `dialog`

**Route:** `— (Dialog)`  
**Zugriff:** canManageInventory

**Unterbereiche / Tabs (2)**

- **Kontaktverknüpfung** — ContactPickerField (Kontakt Typ Lieferant/Großhändler) — befüllt Name/Ansprechpartner/E-Mail/Telefon vor
- **Felder** — Name*, Ansprechpartner, E-Mail, Bestell-E-Mail, Telefon, eigene Kundennr., Lieferzeit, Mindestbestellmenge, Gebinde, Notiz

**Aktionen (2)**

- Speichern / Abbrechen
- Kontakt verknüpfen (ContactPickerField)

**Sheets & Dialoge (1)**

- Kontakt-Picker (aus ContactPickerField)

> _SupplierDialog. clearX-Flags an allen nullbaren Feldern.

### Bewegungen-Sheet (Bewegungshistorie) · `modal-sheet`

**Route:** `— (Sheet)`  
**Zugriff:** canManageInventory (aus Artikel-Aktionen)

**Unterbereiche / Tabs (1)**

- **Bewegungsliste** — je Bewegung Icon je Typ, Datum, Grund, Kasse-Marker, Delta +/-, Bestand danach

**Versteckt / gegatet (3)**

- ⨯ EmptyState „Artikel noch nicht gespeichert“ / „Noch keine Bewegungen“
- ⨯ „Kasse“-Marker nur bei POS-Bewegung
- ⨯ Bestand-danach nur wenn balanceAfter vorhanden

> _MovementsSheet, Höhe 60% Bildschirm. StockMovementType{receipt,issue,adjustment,stocktake,transfer,fridgeRefill}. Future im initState gehalten.

### Kassen-Einstellungen-Sheet (OktoPOS) · `modal-sheet`

**Route:** `— (Sheet)`  
**Zugriff:** isAdmin  
**Feature-Flag:** AppConfig.oktoposEnabled (APP_OKTOPOS_ENABLED)

**Unterbereiche / Tabs (2)**

- **Basis-Konfiguration** — Basis-URL (https), nächtlicher Auto-Abgleich, Kassen-Nr. je Laden (mit „Zuletzt abgeglichen bis“)
- **Artikel-Versand (Push)** — Vertriebskanal-Token, Standard-Einheit-Token, Standard-USt-Satz, „Kasse darf Preis ändern“, Kundengruppe

**Aktionen (3)**

- Speichern
- „Tokens laden“ (holt Einheiten/Vertriebskanäle aus Kasse → Auswahldialog, Antippen setzt ein)
- Auto-Abgleich-Switch, Preis-ändern-Switch

**Sheets & Dialoge (1)**

- Dialog „Kassen-Tokens“ (Vertriebskanäle/Einheiten zum Übernehmen)

**Versteckt / gegatet (3)**

- ⨯ Ladevorgang zeigt Spinner
- ⨯ API-Schlüssel wird NIE hier eingegeben (Hinweistext), liegt serverseitig
- ⨯ „Zuletzt abgeglichen bis“ nur wenn lastBusinessDay je Laden vorhanden

> _OktoposSettingsSheet. Schreibt merge-sicher in config/oktoposSync. defaultSize round-getrippt (nicht editierbar).

### Schnell-Warenkorb-Sheet · `modal-sheet`

**Route:** `— (Sheet)`  
**Zugriff:** alle aktiven

**Unterbereiche / Tabs (2)**

- **Filter** — Laden-Dropdown (bei >1), Suchfeld, Warengruppen-Chips
- **Artikelliste** — _QuickAddRow mit Live-Menge im Korb, +/- direkt

**Aktionen (3)**

- In den Warenkorb (+1) je Artikel
- Menge -1 je Artikel
- „Fertig“ / „Warenkorb (n)“ (springt zum Korb-Tab)

**Versteckt / gegatet (3)**

- ⨯ Laden-Dropdown nur bei >1 Standort
- ⨯ Warengruppen-Chips nur wenn Kategorien existieren
- ⨯ -Button/Menge nur wenn Artikel im Korb

> showQuickAddCartSheet, Höhe 85%. sortByOrderFrequency (häufig bestellt zuerst). Auch als „Artikel“-Button im Korb-Tab.

### Kühlschrank-Hinzufügen-Sheet · `modal-sheet`

**Route:** `— (Sheet)`  
**Zugriff:** alle aktiven

**Unterbereiche / Tabs (3)**

- **Filter** — Laden-Dropdown (bei >1), Suchfeld „Getränk suchen oder eintippen“, Warengruppen-Chips
- **Freitext-Zeile** — _FreeTextAddRow „X eintragen“ wenn Suchtext + eindeutiger Laden
- **Artikelliste** — _FridgeAddRow mit Live-Menge auf Liste, +/-

**Aktionen (3)**

- Artikel auf die Kühlschrank-Liste (+1) / -1
- Freitext eintragen (wenn Sorte kein Artikel)
- „Fertig“ / „Auf der Liste (n)“

**Versteckt / gegatet (2)**

- ⨯ Freitext-Zeile nur wenn Suchtext eingegeben; disabled ohne eindeutigen Laden (Hinweis „oben Laden wählen“)
- ⨯ Laden-Dropdown / Warengruppen-Chips konditional

> showFridgeRefillAddSheet (_FridgeAddSheet), Höhe 85%. Auch aus Bestand-FAB und Kühlschrank-Tab.

### Standard-Wochenliste-Editor · `section-screen`

**Route:** `— (Navigator.push)`  
**Zugriff:** canManageInventory

**Unterbereiche / Tabs (1)**

- **Positionsliste** — je Artikel Name, Kategorie/Einheit, +/- Stepper, Entfernen

**Aktionen (3)**

- „Artikel“ (öffnet Produkt-Picker-Sheet)
- Pro Position +/- / Entfernen
- „Speichern“ (bottomNavigationBar)

**Sheets & Dialoge (1)**

- Produkt-Picker-Sheet (showOrderProductPicker mit Menge)

**Versteckt / gegatet (2)**

- ⨯ EmptyState „Noch keine Artikel in der Standard-Wochenliste“
- ⨯ Laden-Name-Zeile nur wenn siteName gesetzt

> WeeklyOrderListEditorScreen (order_cart_screen.dart). Lokaler Entwurf bis Speichern (saveWeeklyList). OrderListKind.weeklyTemplate.

### Produkt-Picker-Sheet · `modal-sheet`

**Route:** `— (Sheet)`  
**Zugriff:** canManageInventory (aus Wochenlisten-Editor)

**Unterbereiche / Tabs (2)**

- **Suche + Kategorie-Chips** — Suchfeld autofokussiert, ChoiceChips Alle + je Kategorie
- **Artikelliste** — häufig bestellt zuerst, onTap → Mengendialog

**Aktionen (1)**

- Artikel antippen → showOrderQuantityDialog → zurück mit (Artikel, Menge)

**Sheets & Dialoge (1)**

- showOrderQuantityDialog

**Versteckt / gegatet (2)**

- ⨯ Kategorie-Chips nur wenn Kategorien existieren
- ⨯ nur aktive Artikel

> _ProductPickerSheet, Höhe 72%.

### Bestell-Editor (Neue Bestellung) · `section-screen`

**Route:** `— (Navigator.push)`  
**Zugriff:** canManageInventory

**Unterbereiche / Tabs (4)**

- **Kopf** — Laden-Dropdown (bei >1), Lieferant* Dropdown, Liefertermin (erwartet, DatePicker)
- **Positionen** — _OrderLineEditor je Kandidat-Artikel (Bestand/Min/EK) mit Stepper, nachzubestellende zuerst
- **Notiz** — Freitextfeld
- **Aktionsleiste** — „Als Entwurf“ / „Bestellen (n)“

**Aktionen (4)**

- Liefertermin wählen/entfernen (DatePicker)
- Pro Position +/- Stepper
- „Als Entwurf“ speichern (Status draft)
- „Bestellen (n)“ (Status ordered)

**Sheets & Dialoge (1)**

- DatePicker Liefertermin

**Versteckt / gegatet (5)**

- ⨯ Laden-Dropdown nur bei >1 Standort
- ⨯ Liefertermin-Feld nur wenn Lieferant gewählt
- ⨯ „Bitte zuerst einen Lieferanten waehlen“ / „keine Artikel für Lieferanten“ Platzhalter
- ⨯ prefillReorder-Modus füllt Nachbestellmengen automatisch (aus Nachbestell-Banner)
- ⨯ Speichern-Buttons disabled wenn selectedCount==0

> PurchaseOrderEditorScreen (purchase_order_screens.dart). USt-Satz je Position aus Artikel übernommen. Enthält zusätzlich ungenutzten _ReceiveDialog.

### Bestellung-Detail + Wareneingang · `detail-tab`

**Route:** `— (Navigator.push)`  
**Zugriff:** canViewInventory (buchende Aktionen nur canManage)

**Unterbereiche / Tabs (4)**

- **Kopf-Card** — Lieferant, StatusBadge, Standort, Bestellt/Erwartet/Geliefert/Rest-geschlossen-Daten, Begründung, Notiz
- **MHD/Charge-Nachtrag-Card** — Warnung wenn Chargen nicht gespeichert, „Nachtragen“-Button (canManage)
- **Wareneingangs-Protokoll** — Mengen-/Preis-Abweichungen (nur wenn geliefert & Abweichung)
- **Positionen + Summe** — je Position Bestellt/Geliefert/Zeile, Gesamt (EK) bzw. Geliefert (EK)

**Aktionen (6)**

- AppBar: Als PDF teilen (picture_as_pdf)
- AppBar: Per E-Mail senden (mailto, nur wenn Bestell-E-Mail)
- AppBar: Bestelltext kopieren (Zwischenablage)
- AppBar Popup (canManage): Wareneingang buchen / Rest schließen / Als bestellt markieren / Stornieren / Avis erfassen / Lieferavise… / Löschen
- FAB: Wareneingang (ExpandableFab, nur canManage & receive möglich)
- „Nachtragen“ (pending Batches retry)

**Sheets & Dialoge (5)**

- Wareneingang-Sheet (showPurchaseReceiptSheet)
- Dialog „Restmenge schließen?“ (_CloseRemainderDialog, Pflicht-Begründung)
- Lieferavis-Editor-Sheet (Avis erfassen, prefill offene Mengen)
- Lieferavis-Verwaltung (Lieferavise… → DeliveryAdviceScreen)
- Löschen-Bestätigung

**Versteckt / gegatet (7)**

- ⨯ „Bestellung nicht gefunden“ Fallback
- ⨯ E-Mail-Action nur wenn supplier.effectiveOrderEmail != null
- ⨯ canManage-Popup + FAB nur canManage
- ⨯ Menüpunkt „Wareneingang buchen“ nur wenn acceptsReceipt & offen; „Rest schließen“ nur bei teil-geliefert & nicht voll; „Als bestellt markieren“ nur draft; „Stornieren“ nur nicht-geschlossen
- ⨯ MHD/Charge-Nachtrag-Card nur wenn pendingReceiptBatches vorhanden
- ⨯ Wareneingangs-Protokoll nur wenn Abweichungen (computeReceiptDeviations)
- ⨯ Summenzeile nur wenn hasPrices

> PurchaseOrderDetailScreen. PurchaseOrderStatus{draft,ordered,partiallyReceived,received,cancelled}.

### Wareneingang-Sheet (gegen Bestellung) · `modal-sheet`

**Route:** `— (Sheet)`  
**Zugriff:** canManageInventory

**Unterbereiche / Tabs (3)**

- **Kopf** — Lieferschein-Nr. (optional)
- **Positionen** — _PositionTile je offene Position: Menge (Default=Rest) + aufklappbar MHD/Charge/Ist-EK
- **Optionen** — „Einkaufspreis am Artikel aktualisieren?“ / „Mehrlieferung zulassen?“

**Aktionen (5)**

- Menge je Position eingeben
- MHD erfassen/ändern/entfernen (DatePicker)
- Charge/Los + Ist-EK erfassen (ExpansionTile)
- Switches EK-aktualisieren / Überlieferung
- „Wareneingang buchen“

**Sheets & Dialoge (1)**

- DatePicker MHD

**Versteckt / gegatet (4)**

- ⨯ „Alle Positionen bereits vollständig geliefert“ wenn keine offenen
- ⨯ MHD/Charge/Ist-EK hinter ExpansionTile eingeklappt
- ⨯ Warnhinweis (Warnfarbe) wenn Charge ohne MHD
- ⨯ Buchen disabled wenn keine offenen Positionen

> showPurchaseReceiptSheet (purchase_receipt_sheet.dart). PurchaseReceiptLine mit allowOverdelivery.

### Geführter Wareneingang-Sheet (Einzelartikel) · `modal-sheet`

**Route:** `— (Sheet)`  
**Zugriff:** canManageInventory (aus Avis-Wareneingang ohne Bestellbezug)

**Unterbereiche / Tabs (3)**

- **Menge-Stepper** — Menge Zugang mit +/-
- **MHD (optional)** — erfassen/ändern/entfernen
- **Charge/Los (optional)** — Textfeld

**Aktionen (4)**

- Menge +/-
- MHD wählen (DatePicker)
- Charge eingeben
- „Wareneingang buchen (+n)“

**Sheets & Dialoge (1)**

- DatePicker MHD

**Versteckt / gegatet (2)**

- ⨯ MHD gesetzt → Chip statt Button
- ⨯ Warnfarbe wenn Charge ohne MHD (Charge nur mit MHD gespeichert)

> showGoodsReceiptSheet (goods_receipt_sheet.dart). GS1-Scan kann MHD/Charge vorbefüllen. Buchung macht Aufrufer.

### Lieferavis-Verwaltung · `section-screen`

**Route:** `— (Navigator.push, keine go_router-Route)`  
**Zugriff:** canManageInventory (aus Bestellung-Detail „Lieferavise…“)

**Unterbereiche / Tabs (3)**

- **Angekündigt** — offene Avise (Chip info)
- **Eingegangen** — received (Chip success)
- **Storniert** — cancelled

**Aktionen (2)**

- FAB „Avis erfassen“
- Pro Avis Popup: Wareneingang starten (offen) / Bearbeiten / Stornieren (offen) / Löschen

**Sheets & Dialoge (3)**

- Lieferavis-Editor-Sheet (Neu/Bearbeiten)
- Wareneingang-Sheet (mit Bestellbezug) bzw. Geführter Wareneingang-Sheet (ohne Bezug, je Position)
- Löschen-Bestätigung

**Versteckt / gegatet (4)**

- ⨯ EmptyState „Noch keine Lieferavise erfasst“
- ⨯ „Wareneingang starten“/„Stornieren“ nur bei Status announced
- ⨯ Aktionen deaktiviert während _busy
- ⨯ Ref-Zeile nur wenn reference & supplierName vorhanden

> DeliveryAdviceScreen (delivery_advice_screen.dart). DeliveryAdviceStatus{announced,received,cancelled}. WW-4/WW-7.

### Lieferavis-Editor-Sheet · `modal-sheet`

**Route:** `— (Sheet)`  
**Zugriff:** canManageInventory

**Unterbereiche / Tabs (3)**

- **Kopf** — Erwartet-am (DatePicker), Lieferant-Dropdown (optional), Referenz
- **Positionen** — _ItemRow je Position (Artikel + Menge), Position hinzufügen/entfernen
- **Notiz** — optional

**Aktionen (5)**

- Datum ändern (DatePicker)
- Lieferant wählen
- „Position“ hinzufügen
- Position entfernen
- „Avis speichern“

**Sheets & Dialoge (1)**

- DatePicker Liefertermin

**Versteckt / gegatet (3)**

- ⨯ Lieferant-Dropdown nur wenn suppliers-Liste übergeben, sonst statischer supplierName-Text
- ⨯ Entfernen-Button pro Position nur wenn >1 Position
- ⨯ Fehler-Snack wenn keine Position mit Menge>0

> showDeliveryAdviceSheet (delivery_advice_sheet.dart). Prefill aus Bestellung (offene Mengen) möglich.

### Inventur (geführte Bestandszählung) · `section-screen`

**Route:** `/inventur`  
**Zugriff:** canManageInventory (sonst „Keine Berechtigung“-EmptyState)

**Unterbereiche / Tabs (4)**

- **Standort-Auswahl** — ChoiceChips (Pflicht bei >1 Laden, KEIN „Alle“)
- **Warengruppen-Filter + Suche** — Dropdown Warengruppe + Suchfeld (Suche verengt nur Anzeige)
- **Fortschrittsheader** — „X von Y gezählt“ + LinearProgress
- **Zähl-Liste** — _CountRow je Artikel: Status-Icon, Buchbestand, Eingabefeld „Gezählt“

**Aktionen (4)**

- Standort wählen (Chip)
- Warengruppe filtern / Suche
- Gezählten Bestand je Artikel eintippen
- „Differenzen prüfen“ (bottomNavigationBar, wenn Eingaben vorhanden)

**Sheets & Dialoge (2)**

- Differenz-Vorschau-Sheet (_DiffPreviewSheet)
- Dialog „Zählung verwerfen?“ (PopScope-Verlassen-Schutz)

**Versteckt / gegatet (6)**

- ⨯ „Standort wählen“ EmptyState bei >1 Laden ohne Auswahl
- ⨯ Warengruppen-Dropdown nur wenn Kategorien existieren
- ⨯ EmptyStates: keine aktiven Artikel / keine Suchtreffer
- ⨯ PopScope blockt Verlassen bei ungebuchten Zählständen (Verwerfen-Dialog)
- ⨯ „Differenzen prüfen“ disabled ohne Eingaben
- ⨯ EK-Bewertung im Vorschau-Sheet nur bei canManage & EK gepflegt

> InventurScreen (inventur_screen.dart). Keine Vorbefüllung (echtes Zählen). Bucht je Differenz recordStocktake (StockMovement stocktake). Route AppRoutes.inventur, RoutePermissions canManageInventory (Kopplung #7).

### Differenz-Vorschau-Sheet (Inventur) · `modal-sheet`

**Route:** `— (Sheet)`  
**Zugriff:** canManageInventory

**Unterbereiche / Tabs (2)**

- **Zusammenfassung** — Anzahl Abweichungen / ohne Differenz, optional „Differenz nach EK“
- **Abweichungsliste** — je Artikel Buchbestand/gezählt + farbcodiertes Delta

**Aktionen (1)**

- „n Differenzen buchen“ (mit Spinner) ODER „Zählung abschließen“ (wenn keine Abweichung)

**Versteckt / gegatet (3)**

- ⨯ „Differenz nach EK“ nur wenn valuationCents (canManage & EK gepflegt)
- ⨯ Bei keinen Abweichungen: Abschließen ohne Buchung
- ⨯ Artikel ohne Eingabe erscheinen nie

> _DiffPreviewSheet. Bucht sequenziell je Artikel (eigener try/catch), deutsche Ergebnis-SnackBar.

### Sortimentsanalyse · `section-screen`

**Route:** `/sortiment`  
**Zugriff:** isAdmin (sonst „Nur für Administratoren.“)

**Unterbereiche / Tabs (4)**

- **KPI-Karten** — Rohertrag / Umsatz / Unbewertet
- **Rohertrag je Warengruppe** — SectionCard Liste
- **Artikel nach Rohertrag** — ABC-Badge + Menge/Umsatz/Rohertrag (Top 100)
- **Häufig zusammen gekauft** — Warenkorb-Paare mit Lift (Top 20)

**Aktionen (3)**

- AppBar Aktualisieren
- Laden-Dropdown (bei >1)
- Pull-to-Refresh

**Versteckt / gegatet (5)**

- ⨯ Admin-Guard: sonst nur Text „Nur für Administratoren.“
- ⨯ EmptyStates: keine Artikel / Analyse fehlgeschlagen (Retry) / kein Kassenabgleich
- ⨯ Laden-Dropdown nur bei >1 Standort
- ⨯ „Unbewartet“-KPI nur wenn unvaluatedCount>0
- ⨯ Ranking nach Deckungsbeitrag (EK/Marge) → admin-only

> SortimentScreen (sortiment_screen.dart). Lädt posReceipts (loadAssortmentAnalysis + loadBasketAnalysis). purchasePricesIncludeVat-Flag steuert netto/brutto. Fenster = SalesVelocity.defaultReliableDays.

### Bestand-Insights · `section-screen`

**Route:** `/bestand-insights`  
**Zugriff:** isAdmin (sonst „Nur für Administratoren.“)

**Unterbereiche / Tabs (6)**

- **KPI-Karten** — Ladenhüter / Totes Kapital / Umlagerungen / Schwellen-Tipps / Schwund
- **Ladenhüter** — Bestand + gebundenes Kapital + 0 Verkäufe (Top 50)
- **Umlagerung in anderen Laden** — _TransferTile mit „Umlagern“-Button + Match-Label
- **Bestellschwellen-Vorschläge** — _ReorderTile Melde/Ziel → mit „Übernehmen“
- **Schwund / Inventurdifferenz** — Verlust je Artikel
- **Listungslücken** — läuft im anderen Laden, hier nicht geführt

**Aktionen (5)**

- AppBar Aktualisieren
- Laden-Dropdown (bei >1)
- Pull-to-Refresh
- „Umlagern“ pro Vorschlag (transferStock, paarweise)
- „Übernehmen“ pro Schwellen-Vorschlag (saveProduct min/target)

**Versteckt / gegatet (6)**

- ⨯ Admin-Guard
- ⨯ EmptyStates je Sektion (Erfolgs-Häkchen) + Fehler-Retry
- ⨯ Laden-Dropdown nur bei >1 Standort
- ⨯ Schwund-KPI nur wenn shrinkageValueCents>0
- ⨯ „Umlagern“/„Übernehmen“ deaktiviert während _applying
- ⨯ Enthält EK-Preise → admin-only (Route + Guard)

> BestandInsightsScreen (bestand_insights_screen.dart). Liest SalesInsightsProvider. Fenster defaultReliableDays, Ladenhüter 60 Tage.

### Bestell-Auswertung · `section-screen`

**Route:** `/bestell-auswertung`  
**Zugriff:** canViewInventory (sonst „für dieses Profil deaktiviert“)

**Unterbereiche / Tabs (3)**

- **Filter** — Laden-Dropdown (bei >1), Woche/Monat SegmentedButton, optional Artikel-Filter-Chip
- **Balkendiagramm** — Bestellungen pro Woche/Monat (fl_chart) mit Gesamtzahl
- **Häufig bestellte Artikel** — Rangliste Top 15 mit Balken, antippbar zum Filtern

**Aktionen (4)**

- Laden-Dropdown
- Woche/Monat umschalten (SegmentedButton)
- Artikel in Rangliste antippen → filtert Diagramm auf diesen Artikel
- Filter-Chip „Nur: X“ entfernen

**Versteckt / gegatet (4)**

- ⨯ Berechtigungs-Guard-Text bei fehlendem canViewInventory
- ⨯ Laden-Dropdown nur bei >1 Standort
- ⨯ Artikel-Filter-Chip nur wenn Artikel gewählt
- ⨯ EmptyState im Chart/Ranking wenn keine Bestellungen

> OrderAnalyticsScreen (order_analytics_screen.dart), parentLabel default „Laden“. FrequencyGranularity{week(12),month(6)}. Rein aus gestreamter Bestellhistorie, kein Index.

### Preisverlauf-Sheet · `modal-sheet`

**Route:** `— (Sheet)`  
**Zugriff:** canManageInventory (aus Artikel-Aktionen; auch aus Scanner)

**Unterbereiche / Tabs (1)**

- **Historie-Liste** — EK/VK-Änderungen: Feld-Icon (sell/cart), alt → neu, Zeitstempel

**Versteckt / gegatet (2)**

- ⨯ EmptyState „Noch keine Preisaenderungen erfasst.“
- ⨯ Ladeindikator (FutureBuilder)

> showPriceHistorySheet (price_history_sheet.dart). priceHistoryFor (cloud/hybrid Subcollection, local Spiegel). PriceField.selling/purchase. Wiederverwendbar (Scanner-Treffer).

---

<a id="cluster-7"></a>

## 7. Warenwirtschaft Scanner + Kunde

*8 Bereiche.*

### Scanner · `section-screen`

**Route:** `— (Navigator.push MaterialPageRoute, parentLabel Breadcrumb)`  
**Zugriff:** profile.canUseScanner (leerer Zustand: „Keine Berechtigung fuer den Scanner.")

**Unterbereiche / Tabs (3)**

- **Modus Bestellen (Scan & Go)** — Standard-Modus. Jeder Scan legt Artikel direkt in den Bestellkorb wie an Selbstscan-Kasse; laufender Warenkorb, Häufig-bestellt-Chips, Erfolgs-Banner „… in den Warenkorb gelegt".
- **Modus Buchen** — Zeigt Artikel-Karte mit Buchungs-Buttons (Wareneingang/Abgang/Inventur/Preis/Preisverlauf/MHD erfassen) je gescanntem Artikel.
- **Modus Inventur (Sammelzählung)** — Dauer-Scan in eine Zähl-Session (productId→Menge); jeder Scan +1, Zeilen mit +/-/Entfernen, Diff-Anzeige, Abschluss-Dialog.

**Aktionen (25)**

- AppBar: Erweiterter Modus umschalten (qr_code_2 / qr_code_scanner_outlined — QR/DataMatrix/Karton-Codes an/aus)
- AppBar: Scan-Statistik (insights_outlined) → ScanStatistikScreen
- AppBar: Ton & Vibration an/aus (volume_up/volume_off, persistiert 'scanner_sound_enabled')
- Modus-SegmentedButton: Bestellen / Buchen / Inventur
- Laden-Dropdown / Laden-Anzeige (nur bei >1 Standort Dropdown)
- Kamera-Overlay: Taschenlampe (nur supportsTorch)
- Kamera-Overlay: Kamera wechseln (cameraswitch, nur supportsTorch)
- Dunkelheits-Hinweis-Banner „Nichts erkannt — zu dunkel? Tippen für Licht." (nur supportsTorch, nach ~4s ohne Erkennung)
- Zoom-Slider (nur supportsZoom)
- Manuelle Eingabe: TextField „Barcode manuell eingeben" + Button „Suchen"
- Foto scannen (kleiner/beschaedigter Code) (nur supportsPhotoAnalysis)
- Buchen-Karte: Wareneingang (gefuehrt, GS1-vorbefuellt)
- Buchen-Karte: Abgang
- Buchen-Karte: Inventur (Einzel-Dialog)
- Buchen-Karte: Preis (ändern)
- Buchen-Karte: Preisverlauf
- Buchen-Karte: MHD erfassen
- Buchen-Karte: Menge +/-
- Häufig-bestellt ActionChips (Tipp = in Warenkorb)
- Warenkorb-Zeile: Menge +/-/Entfernen
- Warenkorb: Fertig — Warenkorb (n) (schließt Screen)
- Nicht-gefunden-Karte: Neu anlegen
- Deaktiviert-Karte: Reaktivieren
- QR-Inhalt-Karte: Inhalt kopieren
- Inventur-Session: Zeile +/-/Entfernen, Inventur abschliessen (n)

**Sheets & Dialoge (10)**

- showGoodsReceiptSheet (gefuehrter Wareneingang: Menge+MHD+Charge)
- Mehrfach-Treffer-Auswahl-Sheet (showModalBottomSheet „Mehrere Artikel mit diesem Barcode — bitte waehlen")
- Inventur-Einzeldialog (AlertDialog „Inventur", Gezaehlter Bestand)
- Preis-ändern-Sheet (showModalBottomSheet „Verkaufspreis …") + Bestätigungsdialog „Preis uebernehmen?"
- MHD-DatePicker „Mindesthaltbarkeitsdatum (MHD)"
- showProductDialog (Neuanlage Artikel)
- Inventur-verwerfen-Dialog beim Moduswechsel („Inventur verwerfen?")
- Inventur-abgeschlossen-Zusammenfassung (AlertDialog)
- showPriceHistorySheet (Preisverlauf)
- Foto-Aufnahme via ImagePicker Kamera

**Versteckt / gegatet (11)**

- ⨯ Erweiterter Scan-Modus (QR/DataMatrix/GS1) hinter AppBar-Icon-Toggle
- ⨯ Taschenlampe + Kamera-wechseln nur bei supportsTorch (Handy)
- ⨯ Zoom-Slider nur bei supportsZoom
- ⨯ Foto-scannen-Button nur bei supportsPhotoAnalysis
- ⨯ Dunkelheits-Hinweis nur nach ~4s ohne Treffer + supportsTorch
- ⨯ GS1-Info-Box (MHD/Charge) nur bei GS1-Scan mit expiryDate/lot
- ⨯ Deaktiviert-Artikel-Karte nur wenn inaktiver Treffer existiert
- ⨯ QR-Inhalt-Karte nur bei Nicht-Produkt-QR (URL/Freitext)
- ⨯ Laden-Dropdown nur bei >1 Standort; bei 1 Standort auto-gewählt
- ⨯ Leerer Zustand „Bitte zuerst unter Personal → Organisation einen Standort anlegen" wenn keine sites
- ⨯ Kamera-Fehler-Overlay „Kamera nicht verfuegbar…"

> Fester Bottomnav-Tab (Mitte) laut Memory; hier via Navigator.push mit parentLabel. Kamera pausiert bei App-Lifecycle. QR-Inhalte bewusst KEINE Telemetrie (Datenschutz).

### Scan-Statistik & Fehleranalyse · `detail-tab`

**Route:** `— (Navigator.push aus Scanner-AppBar)`  
**Zugriff:** Manager/Admin (Doc-Kommentar); Aufruf aus Scanner-AppBar. Kein hartes if im Screen selbst

**Unterbereiche / Tabs (4)**

- **Erkennung (KPI-Card)** — Scans, Trefferquote (farbcodiert), Ø/Median bis Treffer, Manuell eingegeben (%), Foto-Scans, Nicht gefunden, Pruefziffer ungueltig; Warnhinweis bei >25% manuell.
- **Codes mit Fehlversuchen** — Liste oft gescannter, aber nicht gefundener Codes mit Zähler und Zeitpunkt (nur wenn vorhanden).
- **Verteilung** — Chips nach Quelle (Kamera/Manuell/Foto), Geraeteklasse (Android/iPhone/Web/Mac), Modus (Bestellen/Buchen/Inventur).
- **Doppelte Barcodes** — Duplikat-Report je Laden (mehrfach vergebene Barcodes); grüner OK-Zustand oder Warnliste mit Bereinigungs-Hinweis.

**Aktionen (3)**

- AppBar: Neu laden (refresh)
- Zeitfenster-SegmentedButton: 7 Tage / 30 Tage
- Laden-Dropdown „Alle Laeden" + je Standort (nur bei >1 Standort)

**Versteckt / gegatet (5)**

- ⨯ Laden-Dropdown nur bei sites.length > 1
- ⨯ Failing-Codes-Card nur wenn stats.failingCodes nicht leer
- ⨯ KPI/Verteilung nur wenn stats nicht leer, sonst Hinweis „Noch keine Scans…"
- ⨯ Warn-Text >25% manuell nur bei hohem Manuell-Anteil
- ⨯ Duplikate-Card zeigt entweder verifiziert-OK oder Warnliste

> Reine Auswertung, lädt Events einmalig on demand (fetchScanEvents), rechnet clientseitig (computeScanStats), kein Live-Stream.

### Preisabgleich Kasse (Preisabweichung) · `section-screen`

**Route:** `— (Navigator.push, Breadcrumb Warenwirtschaft → Preisabgleich Kasse)`  
**Zugriff:** admin (isAdmin, OktoPOS-Menü der Warenwirtschaft)  
**Feature-Flag:** App-Preis-an-Kasse-senden gated durch AppConfig.oktoposEnabled (canPush = isAdmin && oktoposEnabled)

**Unterbereiche / Tabs (2)**

- **Info-Card Laden** — Zeigt Ladenname + Erklärung: vergleicht App-VK mit zuletzt an Kasse kassiertem Stückpreis (Belege letzte 30 Tage).
- **Abweichungs-Liste** — Je Artikel Karte mit Diff (+/−), App- vs. Kassenpreis, zuletzt-verkauft-Datum, Beobachtungszahl.

**Aktionen (3)**

- AppBar: Neu laden (refresh)
- Card: Kassen-Preis uebernehmen (adopt POS price → updateProductPrices)
- Card: App-Preis an Kasse senden (nur canPush = admin && oktoposEnabled)

**Versteckt / gegatet (3)**

- ⨯ Button „App-Preis an Kasse senden" nur bei isAdmin && AppConfig.oktoposEnabled
- ⨯ Leerer Zustand „Keine Preisabweichungen…"
- ⨯ Fehler-Card bei Ladefehler

> siteId/siteName als Konstruktor-Parameter. Push via pushOktoposArticles Cloud Function.

### Laden-Benchmark (Store-Health / Multi-Store) · `section-screen`

**Route:** `— (Navigator.push, Breadcrumb Warenwirtschaft → Laden-Benchmark)`  
**Zugriff:** admin (profile.isAdmin; sonst „Nur für Administratoren.")

**Unterbereiche / Tabs (1)**

- **Tagesvergleich je Laden** — Pro Laden Karte: Belege heute (große Zahl), Trend-Delta % (farbcodiert north_east/south_east/trending_flat), Wochentag-Schnitt + Sample-Tage, optional Umsatz heute, Dip-Warnung „Deutlich unter dem Schnitt — prüfen."

**Aktionen (3)**

- AppBar: Aktualisieren (refresh)
- RefreshIndicator: Pull-to-refresh
- Fehler-EmptyState: Erneut versuchen

**Versteckt / gegatet (5)**

- ⨯ Ganzer Screen admin-only (sonst „Nur für Administratoren.")
- ⨯ EmptyState „Noch kein Kassenabgleich" wenn keine Belege
- ⨯ Dip-Warnung nur bei health.isDip()
- ⨯ Umsatz-heute nur bei revenueTodayCents > 0
- ⨯ Delta-Fall „keine Basis" wenn zu wenige Vergleichstage

> P2.3. Basis = anonyme Beleg-Zählung, lädt via loadStoreBenchmark. Push-Alarm separat (Infra).

### Kundenbestellungen (Sonderbestellungen) · `section-screen`

**Route:** `— (Navigator.push, Breadcrumb parentLabel → Kundenbestellungen)`  
**Zugriff:** profile.canViewInventory (Ansicht); Anlegen/Bearbeiten nur canManageInventory

**Unterbereiche / Tabs (4)**

- **Standort-Filterleiste** — ChoiceChips „Alle Läden" + je Standort (nur bei >1 Standort).
- **Status-/Kategorie-Filterleiste** — ChoiceChips „Alle" + je CustomerOrderStatus (offen/vorbereitet/abgeholt/storniert); FilterChips je Warengruppe.
- **Suche** — TextField „Kunde, Bestellnr. oder Artikel suchen".
- **Bestell-Liste** — Tiles mit Avatar, Status-Badge, Abholtermin, Rhythmus, Positionszahl, Preis; „Nicht vorbereitet"-Badge bei fälligen.

**Aktionen (5)**

- AppBar: Exportieren (PopupMenu ios_share): Als PDF exportieren / Als CSV exportieren (deaktiviert wenn keine Bestellungen)
- FAB (ExpandableFab, nur canManage): Bestellung anlegen
- Tile onTap (nur canManage): Bearbeiten
- Tile PopupMenu (nur canManage): Bearbeiten / Als vorbereitet markieren / Vorbereitung zurücknehmen / Als abgeholt markieren / Stornieren / Löschen
- Filter-Chips ändern

**Sheets & Dialoge (5)**

- showCustomerOrderDialog (Neue/Bestellung bearbeiten) mit ContactPickerField, Rhythmus, Abholtermin-DatePicker, Positionen-Editor, Notiz
- showCustomerOrderItemDialog (Position anlegen/bearbeiten) mit Kategorie-Autocomplete
- _ProductPickSheet (Aus Warenwirtschaft wählen — durchsuchbares Artikel-Sheet)
- Stornieren-Bestätigung / Löschen-Bestätigung (AlertDialog)
- Abholtermin-DatePicker

**Versteckt / gegatet (11)**

- ⨯ FAB nur bei canManageInventory
- ⨯ Tile-onTap + PopupMenu nur bei canManage
- ⨯ PopupMenu-Einträge bedingt: prepare/unprepare je isPrepared, pickup/cancel nur bei status.isOpen
- ⨯ Export-Menü deaktiviert (enabled:false) wenn keine Bestellungen
- ⨯ Standort-Filter nur bei sites.length>1
- ⨯ Kategorie-FilterChips nur wenn Kategorien existieren
- ⨯ Fälligkeits-Warnbanner nur wenn dueOrders nicht leer
- ⨯ Error-Banner bei inventory.errorMessage
- ⨯ Leerer Zustand differenziert (noch keine vs. Filter)
- ⨯ Laden-Dropdown im Dialog nur bei >1 Standort
- ⨯ Kein-Berechtigung-Zustand wenn !canViewInventory

> CustomerOrderWarningBanner (eingebettet in Home-Dashboards) warnt bei bald fälligen, nicht vorbereiteten Bestellungen; nur bei canViewInventory sichtbar, Tipp → CustomerOrderScreen. Abholung bei Rhythmus legt Folgetermin an.

### Kundenwünsche (Eingang /wunsch) · `section-screen`

**Route:** `— (Navigator.push, Breadcrumb Warenwirtschaft → Kundenwünsche)`  
**Zugriff:** profile.canViewInventory (Ansicht); Bearbeiten/Status/Löschen/Übernehmen nur canManageInventory

**Unterbereiche / Tabs (2)**

- **Header + Erledigt-Filter** — Inbox-Icon, „n offene Wünsche", FilterChip „Erledigte" zum Einblenden geschlossener.
- **Wunsch-Liste** — Karten mit Referenzcode, Status-Chip, Kategorie/Menge/Laden/Wunschdatum-Chips, Wunschtext, Kundenkontakt-Box, verknüpfter Kontakt, Eingangszeit.

**Aktionen (2)**

- Karten-PopupMenu (nur canManage): In Bestellung übernehmen / Kontakt verknüpfen (bzw. ändern) / Als gesehen markieren / Als erledigt markieren / Ablehnen / Löschen
- FilterChip „Erledigte" umschalten

**Sheets & Dialoge (3)**

- showContactPicker (Kontakt verknüpfen, ContactType.customer)
- Standort-Auswahl-SimpleDialog „Standort der Bestellung" (bei Übernahme, nur >1 Standort)
- Löschen-Bestätigung (AlertDialog „Wunsch löschen?")

**Versteckt / gegatet (8)**

- ⨯ PopupMenu nur bei canManageInventory
- ⨯ Verknüpfter-Kontakt-Zeile nur wenn wish.contactId gesetzt
- ⨯ Kundenkontakt-Box nur bei wish.hasContact
- ⨯ Diverse Chips bedingt (Laden/Wunschdatum)
- ⨯ Erledigte-Wünsche nur bei aktiviertem Filter
- ⨯ Leerer Zustand EmptyState „Keine Kundenwünsche"
- ⨯ Kein-Berechtigung-Zustand wenn !canViewInventory
- ⨯ Lokaler Demo-Modus: In-Memory-Liste statt Firestore-Stream (authDisabled)

> Wünsche haben keinen eigenen Provider → Mutation direkt via FirestoreService + Audit-Log manuell. In Bestellung übernehmen idempotent via sourceWishId; überträgt contactId. Aktive Mitglieder sehen Eingang, Manager bearbeiten.

### Kundenfeedback (Eingang /feedback) · `section-screen`

**Route:** `— (Navigator.push, Breadcrumb Laden → Kundenfeedback)`  
**Zugriff:** profile.canManageFeedback (Manager-only; sonst „Keine Berechtigung für das Kundenfeedback.")

**Unterbereiche / Tabs (2)**

- **Header + Erledigt-Filter** — „n offene Rückmeldungen", FilterChip „Erledigte zeigen".
- **Feedback-Liste** — Karten mit Typ-Chip (Beschwerde/Verbesserungsvorschlag/Lob), Referenzcode, Status-Chip, Sterne-Bewertung, Laden/Vorfallsdatum-Chips, Nachricht, Kundenkontakt, verknüpfter Kontakt, Eingangszeit.

**Aktionen (2)**

- Karten-PopupMenu: Kontakt verknüpfen (bzw. ändern) / Als gesehen markieren / Als erledigt markieren / Ablehnen / Löschen
- FilterChip „Erledigte zeigen" umschalten

**Sheets & Dialoge (2)**

- showContactPicker (Kontakt verknüpfen, ContactType.customer)
- Löschen-Bestätigung (AlertDialog „Rückmeldung löschen?")

**Versteckt / gegatet (8)**

- ⨯ Ganzer Eingang manager-only (canManageFeedback), strenger als Kundenwünsche — Beschwerden sensibel
- ⨯ Sterne-Zeile nur wenn rating != null
- ⨯ Verknüpfter-Kontakt-Zeile nur wenn contactId gesetzt
- ⨯ Kundenkontakt-Zeile nur bei hasContact
- ⨯ Laden/Vorfallsdatum-Chips bedingt
- ⨯ Erledigte nur bei aktiviertem Filter
- ⨯ Leerer Zustand EmptyState „Kein Feedback"
- ⨯ Lokaler Demo-Modus: In-Memory-Liste statt Firestore-Stream (authDisabled)

> Kein eigener Provider → Mutation direkt via FirestoreService + Audit-Log manuell. Typen: complaint/suggestion/praise.

### Wiederverwendbares Barcode-Scan-Sheet · `modal-sheet`

**Route:** `— (showBarcodeScanSheet, imperativ)`  
**Zugriff:** — (Aufrufer-abhängig; z.B. Paketshop)

**Aktionen (5)**

- Kamera-Preview mit Live-Scan (liefert rohen Code zurück)
- Taschenlampe (nur supportsTorch)
- Foto scannen (schwierige Codes, nur supportsPhotoAnalysis)
- Zoom-Slider (nur supportsZoom)
- Manuelle Eingabe „Code manuell eingeben" + Button „Übernehmen"

**Sheets & Dialoge (1)**

- Foto-Aufnahme via ImagePicker Kamera

**Versteckt / gegatet (3)**

- ⨯ Kamera-Preview nur wenn Kamera verfügbar, sonst Hinweis „Kamera hier nicht verfügbar — bitte den Code manuell eingeben."
- ⨯ Taschenlampe/Foto/Zoom je Capability-Flag
- ⨯ Manuelle Eingabe autofocus nur wenn keine Kamera

> Generisch, OHNE Retail-Prüfziffer und OHNE scanWindow (opake Paket-/Fach-/Kundenhandy-Codes). Standardziel ScannerTarget.extended. Titel/Hint konfigurierbar. Nicht produktbezogen — für Paketshop u.a.

---

<a id="cluster-8"></a>

## 8. Kasse & Buchhaltung

*5 Bereiche.*

### Buchhaltung (Finanzbereich) · `section-screen`

**Route:** `AppRoutes-Sektion (context.push, geöffnet aus /laden bzw. parentLabel „Laden")`  
**Zugriff:** admin-only (finance.isAdmin; sonst EmptyState „Kein Zugriff — Der Finanzbereich ist nur für Administratoren verfügbar.")

**Unterbereiche / Tabs (4)**

- **Tab „Übersicht"** — Stat-Karten Jahresbudget/Ist gebucht/Kosten/Gutschriften, Über-Budget-Warnbanner, „Plan / Ist je Kostenstelle" (Fortschrittsbalken je Kostenstelle), „Monatsverlauf"-Balken. Leerer Zustand „Noch keine Finanzdaten".
- **Tab „Journal"** — Buchungen des Jahres als Liste (Kosten/Gutschrift), Button „Buchung" (nur wenn Kostenstelle+Kostenart existieren), Info-Banner „Legen Sie zuerst … an", Tile-onTap öffnet Buchungs-Editor.
- **Tab „Stammdaten"** — Sektion Kostenstellen (+„Neu") und Kostenarten (+„Neu"), Tiles öffnen jeweiligen Editor; Inline-Leerzustände; inaktiv-Badge; Kostenart-Gruppen-Badge.
- **Tab „Budgets"** — Budgets des Jahres, Button „Budget" (nur wenn Kostenstellen existieren), Info-Banner „Legen Sie zuerst Kostenstellen an.", Tile-onTap öffnet Budget-Editor.

**Aktionen (7)**

- AppBar: Icon „Tagesabschluss (Kasse)" (point_of_sale) → context.push(AppRoutes.dailyClosing)
- AppBar: PopupMenu „Exportieren" (ios_share) mit Einträgen: Finanzbericht (PDF), Buchungsjournal (CSV), DATEV-Buchungsstapel (EXTF), Erstellte Exporte …, DATEV-Einstellungen …
- Jahres-Leiste: Vorjahr / Folgejahr (chevron_left/right)
- Tab „Journal": FilledButton „Buchung"
- Tab „Stammdaten": „Neu" (Kostenstelle), „Neu" (Kostenart)
- Tab „Budgets": FilledButton „Budget"
- ListTile-onTap auf Buchung/Kostenstelle/Kostenart/Budget öffnet Editor

**Sheets & Dialoge (7)**

- Sheet Neue/Buchung bearbeiten (Datum, Kostenstelle, Kostenart, Bezeichnung, Art Kosten/Gutschrift, Betrag, Beleg/Referenz, Löschen/Speichern)
- Sheet Neue/Kostenstelle bearbeiten (Nummer KOST1, Name, Beschreibung, Jahresbudget, Kostenträger KOST2, Standort, Abrechenbar, Aktiv, Löschen)
- Sheet Neue/Kostenart bearbeiten (Sachkonto-Nr, Name, Gruppe-Segmente, Aktiv, Löschen)
- Sheet Neues/Budget bearbeiten (Kostenstelle, Kostenart optional/Gesamtbudget, Planbetrag, Löschen)
- Sheet „DATEV-Prüflauf" (_DatevCheckSheet: Befundliste Fehler/Warnung/Info, Disclaimer, Abbrechen / Trotz Warnungen exportieren)
- Sheet „Erstellte Exporte" (_DatevRunsSheet: DATEV-Historie, je Run „Neu aufbauen & vergleichen", Hash-Abgleich; im lokalen Modus Hinweis „keine Export-Historie")
- Sheet „DATEV-Einstellungen" (_DatevConfigSheet: Beraternummer, Mandantennummer, Sachkontenlänge 4-8, Gegenkonto, Bezeichnung des Stapels, Disclaimer)

**Versteckt / gegatet (7)**

- ⨯ Gesamter Screen hinter admin-Gate (sonst „Kein Zugriff")
- ⨯ DATEV-Prüflauf-Sheet erscheint nur bei Fehlern/Warnungen — bei nur Info/keinen Befunden wird ohne Sheet exportiert
- ⨯ „Trotz Warnungen exportieren"-Button nur wenn keine Fehler
- ⨯ Export-Historie-Schreibung + Snapshot nur bei finance.supportsExportHistory (nicht im local-Modus); DATEV-Prüflauf lädt Kassenabschlüsse nur im Cloud/Hybrid-Modus (local → null)
- ⨯ „Buchung"/„Budget"-Buttons deaktiviert bis Stammdaten existieren
- ⨯ overrideBestaetigt-Warndreieck an Export-Run nur bei akzeptierten Warnungen
- ⨯ Kostenstellen-Abrechenbar-Euro-Icon nur bei isBillable; Fortschrittsbalken/Prozent nur bei plannedCents>0

> Reines V2-Design, BreadcrumbAppBar „Laden › Buchhaltung". Beträge de_DE ohne Symbol. DATEV-EXTF-Export mit reproduzierbarem Build (fester generatedAt) + SHA-256; H11-Absicherung gegen Offline-Historie.

### Tagesabschluss (Kasse) · `section-screen`

**Route:** `AppRoutes.dailyClosing`  
**Zugriff:** Admin ODER Teamleitung (profile.isAdmin || profile.isTeamLead; deckungsgleich mit posReceipts-Rules). Sonst „Nur für Leitung/Admin." Abschließen/Buchen/Konten-Auswahl strikt admin-only.

**Unterbereiche / Tabs (3)**

- **Kassenzustand-Karte** — Rechnerischer Bargeld-Sollbestand (falls verankert) + letzte Zählung (inkl. getrennt Fremdgeld-Treuhand), sonst Warnhinweis „Noch keine Zählung im Zeitfenster". Button „Kasse zählen".
- **Erlöskonten je USt-Satz (admin-only)** — Nur für Admin und wenn USt-Sätze vorhanden: Dropdown Konto je Satz, „Konten merken" (speichert in DatevConfig.revenueAccountByRate).
- **Abschluss-Karten je Geschäftstag** — Pro Tag: Umsatz brutto, Verkäufe/Erstattungen, USt-Buckets netto/USt, Zahlarten, Bargeld-Bewegung, Kassendifferenz, Fremdgeld-Treuhand-Auflistung; Status-Chips festgeschrieben/gebucht; admin-Buttons Tag abschließen / Ins Journal buchen.

**Aktionen (7)**

- AppBar: Icon „Aktualisieren" (refresh)
- Standort-Dropdown (nur bei >1 Standort)
- „Kasse zählen" (FilledButton, öffnet Kassenzähl-Sheet)
- „Konten merken" (TextButton, admin-only)
- je Erlöskonto-Zeile: Dropdown Konto wählen
- Abschluss-Karte: „Tag abschließen" (admin, nur wenn nicht festgeschrieben) → Bestätigungsdialog
- Abschluss-Karte: „Ins Journal buchen" (admin, nur wenn festgeschrieben & nicht gebucht)

**Sheets & Dialoge (2)**

- Kassenzähl-Sheet (showCashCountSheet — mit Soll/Differenz, Fremdgeld-Sektion, Umschalter)
- AlertDialog „Tag <Tag> abschließen?" (Abbrechen / Abschließen)

**Versteckt / gegatet (8)**

- ⨯ Ganzer Screen hinter Admin/Teamlead-Gate
- ⨯ Erlöskonten-Karte nur bei isAdmin && USt-Sätze vorhanden
- ⨯ Aktions-Zeile (Tag abschließen / Ins Journal buchen) NUR bei isAdmin — Teamleitung sieht nur Status/Gebucht-Badge
- ⨯ „Tag abschließen" nur wenn nicht festgeschrieben; „Ins Journal buchen" nur wenn festgeschrieben & !gebucht
- ⨯ Kassenzustand nur bei Cloud/Hybrid (loadCashClosings etc. im local-Modus eingeschränkt)
- ⨯ Standort-Dropdown nur bei >1 Standort; Fremdgeld-Sektion nur wenn Filiale Fremdgeld-Arten aktiv hat
- ⨯ Fremdgeld-Umschalter-Default aus SiteDefinition.thirdPartyCashInTill
- ⨯ Buttons während _booking deaktiviert; Hinweis-Snackbars bei Offline-nur-lokal / fehlendem Erlöskonto je USt-Satz

> Kassen-Modul M3/P2.0. Gebucht-Status aus cashClosings (bookedToFinance), nicht Journal. Kassendifferenz wird beim Buchen idempotent mitgebucht (Fehlbetrag→Kosten, Überschuss→Gutschrift). Fremdgeld ist Treuhand, kein Umsatz. Richtwert — Steuerberater prüft.

### Kassenzählungs-Sheet (Cash-Count) · `modal-sheet`

**Route:** `— (Sheet/imperativ, showCashCountSheet)`  
**Zugriff:** aufrufabhängig: mit Soll (Leitung/Admin, expectedCents!=null) oder blind (Mitarbeitende/Kiosk, expectedCents==null)

**Unterbereiche / Tabs (3)**

- **Fremdgeld-Modus-Umschalter** — SwitchListTile „Fremdgeld liegt in der Kassenlade" (inklusiv vs. getrennt); nur bei vorhandenen Fremdgeld-Arten sichtbar.
- **Dritte Hand / Fremdgelder-Sektion** — Betragsfeld je Fremdgeld-Art (Pflicht-Arten mit *; 0,00-Bestätigungs-Checkbox), Hinweis-Texte.
- **Zusammenfassung + Soll/Differenz** — Soll (rechnerisch) + Differenz-Zeile (stimmt/Überschuss/Fehlbetrag), Zusammenfassung Lade gesamt/eigene Kasse/Fremdgeld; Warnung bei negativer eigener Kasse.

**Aktionen (5)**

- Betragsfeld (Gesamt inkl. Fremdgeld / Eigene Kasse / Bargeldbestand je Modus)
- Notiz-Feld
- je Fremdgeld-Art: Betragsfeld + ggf. „0,00 € bewusst bestätigen"-Checkbox
- Umschalter „Fremdgeld liegt in der Kassenlade"
- „Zählung speichern" (FilledButton, nur bei _canSubmit)

**Versteckt / gegatet (5)**

- ⨯ Soll/Differenz-Zeile nur wenn expectedCents!=null (blinde Zählung ohne Soll für Mitarbeitende/Kiosk)
- ⨯ Fremdgeld-Sektion + Umschalter + Zusammenfassung nur wenn thirdPartyTypes nicht leer
- ⨯ Pflicht-Art-0-Bestätigung erscheint nur wenn Pflichtbetrag 0 und nicht quittiert
- ⨯ Negativ-eigene-Kasse-Warnung nur im Inklusiv-Modus wenn Fremdgeld > Gesamt (blockiert Speichern)
- ⨯ countedCents wird IMMER netto (ohne Fremdgeld) zurückgegeben

> Wiederverwendbares Widget (cash_count_sheet.dart). Dritte-Hand-Fremdgeld §8.5b. countedCents-Invariante: nie Fremdgeld enthalten.

### Kassenbericht · `section-screen`

**Route:** `AppRoutes (context.push, parentLabel „Warenwirtschaft")`  
**Zugriff:** admin-only (profile.isAdmin; sonst „Nur für Administratoren.")

**Unterbereiche / Tabs (4)**

- **Granularitäts-Segmente** — SegmentedButton Woche / Monat / Jahr (mit Icons).
- **KPI-Raster** — Umsatz brutto/netto, Käufe netto (+brutto-Subtitle), Rohertrag netto (hervorgehoben, +brutto), Δ Vorperiode, Δ Vorjahr.
- **Dritte-Hand/Fremdgelder-Karte** — Nur wenn Fremdgeld erfasst: Treuhand je Typ, Fremdgeld gesamt, eigener Umsatz brutto zum Vergleich.
- **Umsatz-Diagramm + Tabellen** — BarChart „Umsatz pro Woche/Monat/Jahr", Datenqualität-Hinweis, Lohnquote-Karte (nur Monat/Jahr & ohne Standortfilter), „Alle Perioden"-Tabelle.

**Aktionen (4)**

- AppBar: „Als CSV exportieren" (download, deaktiviert wenn leer/exporting)
- AppBar: „Aktualisieren" (refresh)
- Laden-Dropdown (nur bei >1 Standort: „Alle Läden" + je Standort)
- SegmentedButton Woche/Monat/Jahr

**Versteckt / gegatet (8)**

- ⨯ Ganzer Screen admin-only (zeigt EK/Marge/Gewinn)
- ⨯ Laden-Dropdown nur bei >1 Standort
- ⨯ Langzeit-Hinweis nur wenn älteste dargestellte Periode ohne Daten (Übergang vor Server-Backfill)
- ⨯ Dritte-Hand-Karte nur wenn Fremdgeld nicht leer
- ⨯ Lohnquote & Betriebsergebnis-Karte nur bei Monat/Jahr UND _siteId==null (org-weit) UND vorhandenen Personalkosten
- ⨯ Erstattungs-Warnung nur bei positiven Erstattungs-Belegen (Vorzeichen-Prüfung)
- ⨯ Leerzustand „Noch keine Kassendaten" wenn keine Periode Daten hat; Buckets ohne Deckung als „keine Daten" (—) statt 0
- ⨯ Monats-Sicht auf 3 Buckets begrenzt bis Server-Aggregate (M5), Jahres-Sicht braucht Server

> Kassen-Modul M4. Richtwert-Banner (Steuerberater maßgeblich). Aggregation clientseitig aus ≤92-Tage-Belegefenster. fl_chart BarChart.

### Kassierer-Prüfung (Storno-/Refund-Anomalie) · `section-screen`

**Route:** `AppRoutes (context.push, parentLabel „Personal")`  
**Zugriff:** strikt admin-only (profile.isAdmin; sonst „Nur für Administratoren.")

**Unterbereiche / Tabs (2)**

- **Rechts-/Ethik-Disclaimer** — Nicht ausblendbarer Warnhinweis: statistischer Verdacht, keine Schuldfeststellung/Sanktion, Mitbestimmung (BetrVG) + DSGVO, Zweckbindung Verlustprävention.
- **Kassierer-Liste** — Standort-Schnitt Erstattungsquote, Mindest-Fallzahl, z-Schwelle; je Kassierer Erstattungsquote/z-Wert, auffällige mit „prüfen"-Markierung.

**Aktionen (2)**

- AppBar: „Aktualisieren" (refresh)
- Standort-Dropdown (nur bei >1 Standort)

**Versteckt / gegatet (5)**

- ⨯ Ganzer Screen admin-only (sehr sensible Leistungskontrolle)
- ⨯ Standort-Dropdown nur bei >1 Standort
- ⨯ Leerzustand „Keine belastbare Datenbasis" wenn zu wenige Vorgänge je Kassierer (Mindest-Fallzahl)
- ⨯ „prüfen"-Trailing nur bei geflaggten (z ≥ Schwelle)
- ⨯ Namen aus TeamProvider, sonst „Kassier-ID …"

> P3.2. Fenster 28 Tage. z-Wert-Vergleich gegen Standort-Schnitt. Disclaimer bewusst nicht ausblendbar.

---

<a id="cluster-9"></a>

## 9. Paketshop

*6 Bereiche.*

### Paketshop (Hub) · `section-screen`

**Route:** `/paketshop (unter /laden, PaketshopHubScreen)`  
**Zugriff:** alle aktiven Mitarbeiter (aufs Postgeheimnis verpflichtet); kein isAdmin-Gate im Screen

**Unterbereiche / Tabs (3)**

- **Hinweis-Banner** — Info-Box: 'Internes Sortier- und Wiederfinde-Register.' bzw. 'Internes Register · Standort <Name>'; Zusatz dass offizieller Paketdienst-Ablauf zwingend bleibt
- **KPI-Chips** — Kennzahlen-Chips: 'Offen', 'Überfällig' (Chip wird warning-getönt wenn >0), 'Freie Fächer', 'Heute angenommen', 'Heute ausgegeben'
- **Offene Pakete (Liste)** — Liste der offenen Pakete mit recipientDisplayName, Untertitel 'Fach <Label> · <Absender>'; Uhr-Icon (warning) bei überfälligen; Leerzustand 'Keine offenen Pakete.'

**Aktionen (5)**

- 'Paket annehmen' (FilledButton, deaktiviert wenn kein Paketshop-Standort gesetzt)
- 'Paket ausgeben' (OutlinedButton)
- 'Fächer verwalten' (OutlinedButton)
- 'Übersicht & Überfällig' (OutlinedButton)
- 'Kundenregister' (OutlinedButton)

**Sheets & Dialoge (5)**

- PaketEinlagernScreen (Navigator.push, Vollbild)
- PaketAusgebenScreen (Navigator.push, Vollbild)
- FachVerwaltungScreen (Navigator.push, Vollbild)
- PaketUebersichtScreen (Navigator.push, Vollbild)
- KundenRegisterScreen (Navigator.push, Vollbild)

**Versteckt / gegatet (3)**

- ⨯ 'Paket annehmen'-Button ist disabled (onPressed null) wenn site?.id == null (kein Paketshop-Standort auflösbar; Fallback nur bei genau einem Standort)
- ⨯ Hinweistext 'Paketshop-Standort in den Einstellungen festlegen, um Pakete anzunehmen.' erscheint nur wenn site?.id == null
- ⨯ Standort-Auflösung implizit: bei genau 1 Standort automatisch, sonst muss paketshopSiteId in Einstellungen gesetzt sein

> Einstieg via Kachel 'Laden'-Hub → 'Paketshop'. Standort kommt aus parcel.settings.paketshopSiteId bzw. Single-Site-Fallback.

### Paket annehmen (Einlagern-Flow) · `detail-tab`

**Route:** `— (Navigator.push, PaketEinlagernScreen)`  
**Zugriff:** alle aktiven Mitarbeiter

**Unterbereiche / Tabs (4)**

- **1 · Paket** — Paket-Barcode scannen oder ohne Barcode erfassen; zeigt gescannten trackingCode als Chip bzw. 'Ohne Barcode'-Chip
- **2 · Fach** — Fach per Barcode scannen; Vorschlag 'freies Fach <Label>'; gewähltes Fach als Chip 'Fach <Label>'
- **3 · Empfänger** — Typeahead-Namenssuche im Register ('Name suchen', bis 6 Treffer als ListTile) oder 'Neu anlegen' (Vorname/Nachname-Felder → 'Übernehmen'); gewählter Empfänger als löschbarer Chip
- **Optional** — Freitextfelder 'Absender / Shop (z. B. Amazon)' und 'Paketdienst (z. B. DHL, Hermes, DPD)'

**Aktionen (7)**

- 'Paket scannen' (FilledButton, öffnet Scan-Sheet)
- 'Ohne Barcode' (OutlinedButton)
- 'Fach scannen' (FilledButton)
- 'Neu anlegen' (TextButton, Empfänger)
- 'Zurück' / 'Übernehmen' (im Neu-anlegen-Modus)
- Empfänger-Chip löschen (onDeleted → Empfänger zurücksetzen)
- 'Einlagern' (FilledButton in bottomNavigationBar, disabled bis Fach+Empfänger gesetzt; zeigt Spinner beim Speichern)

**Sheets & Dialoge (5)**

- showBarcodeScanSheet 'Paket scannen' (Sendungsnummer)
- showBarcodeScanSheet 'Fach scannen'
- AlertDialog 'Bereits eingelagert' (Paket schon im Bestand → 'Trotzdem'/'Abbrechen')
- AlertDialog 'Fach nicht registriert' (Fach jetzt anlegen, Label vergeben → 'Anlegen')
- AlertDialog 'Fach belegt' (Fach enthält fremde Pakete → 'Trotzdem'/'Abbrechen')

**Versteckt / gegatet (5)**

- ⨯ Bestätigungsdialog 'Bereits eingelagert' erscheint nur wenn zum gescannten Code bereits ein offenes Paket existiert
- ⨯ 'Fach nicht registriert'-Dialog nur wenn gescannter Fach-Barcode unbekannt (legt Fach inline an)
- ⨯ 'Fach belegt'-Warnung nur wenn Fach bereits offene Pakete anderer enthält (zeigt Namen der Belegungen)
- ⨯ Freifach-Vorschlag '_freeHint' nur sichtbar solange noch kein Fach gewählt und freie Fächer vorhanden
- ⨯ Neu-anlegen-Formular (Vorname/Nachname) nur im _newRecipientMode; Suchfeld+Treffer nur wenn kein Empfänger gewählt

> SnackBar-Bestätigung 'Paket für <Name> in Fach <Label> eingelagert'; legt Empfänger via upsertCustomer im Register an. Scanner/Feedback injizierbar (Tests).

### Paket ausgeben (Ausgeben-Flow) · `detail-tab`

**Route:** `— (Navigator.push, PaketAusgebenScreen)`  
**Zugriff:** alle aktiven Mitarbeiter

**Unterbereiche / Tabs (3)**

- **Suche + Scan** — Namenssuche ('Name suchen') und 'Scannen'-Button (Paket-Barcode oder Code vom Kundenhandy)
- **Empfänger-Gruppenliste** — Offene Pakete gruppiert nach Empfänger; ListTile pro Kunde mit '<n> Paket(e)' → antippen öffnet Bündel-Karte
- **Kunden-Bündel-Karte (_RecipientBundle)** — Gebündelte Karte: alle offenen Pakete des Kunden mit Fach/Absender/Tracking-Suffix, je Paket 'Ausgegeben'-Button, plus 'Alle <n> ausgeben'; Hinweis dass offizieller Paketdienst-Ablauf zwingend bleibt

**Aktionen (5)**

- 'Scannen' (FilledButton, öffnet Scan-Sheet)
- Kunde antippen (ListTile.onTap → Bündel öffnen)
- 'Ausgegeben' je Paket (OutlinedButton)
- 'Alle <n> ausgeben' / 'Ausgegeben' (FilledButton im Bündel)
- SnackBar-Aktion 'Rückgängig' (Undo der Ausgabe)

**Sheets & Dialoge (2)**

- showBarcodeScanSheet 'Paket / Code scannen' (Barcode oder Kundenhandy-Code)
- AlertDialog 'Mehrere Pakete ausgeben' (nur bei >1 Paket → 'Alle ausgeben'/'Abbrechen')

**Versteckt / gegatet (5)**

- ⨯ Fehler-Karte (errorContainer) 'Nicht gefunden: <Code>' mit Hinweis 'Kein offenes Paket zu diesem Code…' nur wenn Scan keinen Treffer liefert
- ⨯ Bestätigungsdialog 'Mehrere Pakete ausgeben' nur wenn Kunde >1 offenes Paket hat
- ⨯ Leerzustände: 'Keine offenen Pakete.' (nichts offen) vs. 'Kein Treffer.' (Suche ohne Match)
- ⨯ Undo-SnackBar-Aktion 'Rückgängig' nur nach erfolgter Ausgabe sichtbar (macht handOut per undoHandOut rückgängig)
- ⨯ Scan füllt _selectedKey direkt aus dem ersten Treffer → springt direkt zur Bündel-Karte

> SnackBar '<n> Paket(e) ausgegeben' mit Rückgängig. Scanner/Feedback injizierbar.

### Übersicht & Überfällig · `detail-tab`

**Route:** `— (Navigator.push, PaketUebersichtScreen; DefaultTabController length 2)`  
**Zugriff:** alle aktiven Mitarbeiter

**Unterbereiche / Tabs (2)**

- **Tab 'Überfällig'** — Überfällig-Board: Sammelaktion 'Alle <n> als Rücklauf markieren' + Karten je Paket (Fach, 'seit <n> Tagen') mit 'Rücklauf'-Button; Leerzustand 'Keine überfälligen Pakete. 🎉'
- **Tab 'Heute'** — Tages-Reconciliation: 'Heute angenommen (<n>)' (call_received-ListTiles + Fach) und 'Heute ausgegeben (<n>)' (call_made-ListTiles); leere Abschnitte zeigen '—'

**Aktionen (3)**

- 'Alle <n> als Rücklauf markieren' (FilledButton, Sammelaktion)
- 'Rücklauf' je Paket (OutlinedButton → returnParcel)
- Tab-Wechsel 'Überfällig' / 'Heute'

**Sheets & Dialoge (1)**

- AlertDialog 'Rücklauf-Sammelaktion' (<n> überfällige Pakete als Rücklauf markieren? → 'Markieren'/'Abbrechen')

**Versteckt / gegatet (4)**

- ⨯ Sammelaktion-Button + Kartenliste nur wenn überfällige Pakete existieren, sonst Leerzustand-Text
- ⨯ Überfällig-Schwelle datengesteuert (6 Tage laut Plan) — Board erscheint nur bei überfälligen Vorgängen
- ⨯ Tages-Abschnitte fallen auf '—' zurück wenn heute nichts angenommen/ausgegeben
- ⨯ Rein beratend — kein Auto-Rücklauf

> Überfällig-Berechnung via parcel.overdueParcels(now); Tag via parcelsArrivedOn/parcelsHandedOutOn.

### Fächer (Fach-Verwaltung) · `detail-tab`

**Route:** `— (Navigator.push, FachVerwaltungScreen)`  
**Zugriff:** alle aktiven Mitarbeiter

**Unterbereiche / Tabs (1)**

- **Fächer-Liste** — Karten je Fach: 'Fach <Label>', Status 'frei' / '<n> Paket(e)' (belegt→inventory_2-Icon), Löschen-IconButton; Leerzustand 'Noch keine Fächer angelegt.'

**Aktionen (3)**

- Reverse-Lookup 'Fach scannen (Reverse-Lookup)' (AppBar-IconButton)
- FAB 'Fach' (FloatingActionButton.extended, neues Fach anlegen)
- Löschen je Fach (IconButton delete_outline; bei belegt Tooltip 'Belegt — nicht löschbar')

**Sheets & Dialoge (4)**

- showBarcodeScanSheet 'Fach scannen' (Reverse-Lookup)
- AlertDialog Reverse-Lookup-Ergebnis ('Fach <Label>' mit Empfängerliste / 'Leer.' / 'Unbekanntes Fach')
- AlertDialog '_CreateFachDialog' — 'Neues Fach' (Label + Fach-Barcode-Feld + 'Scannen' → 'Anlegen'/'Abbrechen')
- showBarcodeScanSheet 'Fach-Barcode scannen' (im Anlege-Dialog)

**Versteckt / gegatet (4)**

- ⨯ Löschen eines belegten Fachs schlägt fehl → StateError-Message als SnackBar (belegtes Fach geschützt); Tooltip signalisiert 'Belegt — nicht löschbar', Button bleibt aber tappbar
- ⨯ Duplikat-Barcode je Standort → StateError-SnackBar beim Anlegen (Barcode-Eindeutigkeit)
- ⨯ Reverse-Lookup-Dialog unterscheidet unbekanntes Fach / leeres Fach / Belegungsliste
- ⨯ Umbenennen bewusst NICHT vorhanden (v1-Auslassung, Label-Cache-Nachzug)

> siteId aus Aufruf oder settings.paketshopSiteId. Scanner/Feedback injizierbar.

### Kundenregister · `detail-tab`

**Route:** `— (Navigator.push, KundenRegisterScreen)`  
**Zugriff:** alle aktiven Mitarbeiter

**Unterbereiche / Tabs (1)**

- **Namenssuche + Liste** — Suchfeld 'Name suchen' filtert das dauerhafte name-only Register; ListTiles je Kunde (displayName) mit Löschen-IconButton; Leerzustand 'Keine Einträge.'; Fußnote zur dauerhaften Speicherung + Löschmöglichkeit

**Aktionen (2)**

- Suche 'Name suchen' (filtert via parcelCustomersMatching)
- 'Kunde löschen' je Eintrag (IconButton delete_outline)

**Sheets & Dialoge (1)**

- AlertDialog 'Kunde löschen' (‚<Name>' aus Register löschen? Offene Pakete bleiben, verlieren Namensverknüpfung → 'Löschen'/'Abbrechen')

**Versteckt / gegatet (3)**

- ⨯ Löschung (Art. 17/21-Widerspruch) entfernt Registerdaten und entkoppelt parcelCustomerId an offenen Paketen
- ⨯ Liste zeigt bei leerer Suche alle customers, sonst gefilterte Treffer; Leerzustand 'Keine Einträge.'
- ⨯ Fußnoten-Hinweis: 'Namen werden dauerhaft gespeichert… Löschung jederzeit hier möglich.'

> Dauerhaftes name-only ParcelCustomer-Register für Typeahead; keine Auto-Anonymisierung.

---

<a id="cluster-10"></a>

## 10. Personal / HR (Detail 9 Tabs)

*14 Bereiche.*

### Personalverwaltung (Personal-Hub) · `section-screen`

**Route:** `— (Navigator.push aus Profil/Verwaltungsmenü; keine eigene go_router-URL)`  
**Zugriff:** admin-only (personal.isAdmin) — Nicht-Admin bekommt EmptyState „Kein Zugriff / Der Personal-Bereich ist Administratoren vorbehalten.“

**Unterbereiche / Tabs (4)**

- **Kennzahlen-Zeile** — Drei AppMetricCards: Mitarbeiter (Anzahl), Stunden (Monatskürzel, „…“ beim Laden), Personalkosten (€)
- **Abwesenheits-Übersicht (Schnellzugriff)** — AppCard → öffnet AbwesenheitScreen (Urlaubskonten & §9-Hinweise je Mitarbeiter)
- **Mitarbeiterliste** — Gefilterte/sortierte _EmployeeCards mit Avatar, Rolle, Status-Badge, Monatsstunden, MiniChips (offen/Krank-Tg./Netto); Tap → Detail /personal/{uid}
- **Monatsleiste (_MonthBar)** — Vorheriger/Nächster Monat mit Monatslabel, lädt Org-Zeiteinträge des Monats neu

**Aktionen (13)**

- AppBar: Neuer Mitarbeiter (einladen) [person_add_alt_1]
- AppBar: Auswertungen (Aufträge · Lohn · Finanzen · Statistik) [insights_outlined]
- AppBar: Organisation (Standorte · Teams · Regelwerk) [domain_outlined]
- AppBar: Kassierer-Prüfung (Verdachtshinweis) [fact_check_outlined] → context.push(AppRoutes.cashierAnomaly)
- Vorheriger/Nächster Monat
- Mitarbeiter suchen (AppSearchField, Name/Rolle)
- Statusfilter-Chips: Alle · Aktiv · Probezeit · Inaktiv
- Standortfilter-Chips: Alle Standorte + je Standort
- Sortieren (PopupMenu): Name (A–Z) · Stunden (meiste zuerst) · Rolle
- Filter zurücksetzen (im Leer-Treffer-Zustand)
- Urlaub-Migration: „Übernehmen“ (Bestandsurlaub → Sollzeit-Modell)
- Offene Einladung zurückziehen [delete_outline]
- Mitarbeiterkarte → Mitarbeiter-Detail (9 Tabs)

**Sheets & Dialoge (4)**

- _NewEmployeeDialog „Neuer Mitarbeiter“ (Name*/E-Mail*/Rolle → TeamProvider.saveInvite)
- Sortier-PopupMenu
- AppConfirmDialog „Einladung zurückziehen?“
- AbwesenheitScreen (Push)

**Versteckt / gegatet (8)**

- ⨯ Ganzer Screen admin-only (sonst „Kein Zugriff“)
- ⨯ Standortfilter-Zeile nur wenn personal.sites.length > 1
- ⨯ _UrlaubMigrationCard selbst-versteckend — nur wenn offene Urlaubs-Übernahmen existieren
- ⨯ _PendingInvitesSection „Offene Einladungen (n)“ selbst-versteckend — nur wenn aktive userInvites existieren
- ⨯ Status-Badge an der Karte nur wenn Status ≠ aktiv (probezeit/ruhend/gekündigt/ausgeschieden)
- ⨯ MiniChips (offene Aufgaben/Krank-Tage/Netto-Lohn) nur bei vorhandenen Werten
- ⨯ _NoEmployeeMatches (Filter-Leerzustand) vs. EmptyState „Keine Mitarbeiter“ (gar keine)
- ⨯ Kassierer-Prüfung nur in AppBar wenn isAdmin

> Öffnet nach AllTec-M10 direkt in die _OverviewTab-Liste; die früheren 5 Aggregat-Tabs sind in „Auswertungen“ verlagert. Es existiert im selben File ein privates _EmployeeDetailScreen (HR-Karten) — toter/legacy Code, nicht mehr geroutet (Detail läuft über EmployeeDetailScreen mit 9 Tabs).

### Auswertungen (Aufträge · Lohn · Finanzen · Statistik) · `section-screen`

**Route:** `— (Navigator.push aus Personalverwaltung-AppBar)`  
**Zugriff:** admin-only (nur über Personal-Hub erreichbar)

**Unterbereiche / Tabs (4)**

- **Aufträge** — Arbeitsaufträge (Statusfilter Alle/offen/in Arbeit/erledigt, „Neu“, Tiles → Editor) + Kundenaufträge (read-only aus Warenwirtschaft, max. 20)
- **Lohn** — Abrechnungen des Monats: Disclaimer-Banner, Lohnlauf-Summen (_PayrollRunSummary) mit Batch-Freigabe, _PayrollTile je Abrechnung (Status ändern, PDF), Zeitkonto-Karte
- **Finanzen** — Personalkosten pro Mitarbeiter + pro Standort (BarCharts, _CostRowTile), KPIs Personalkosten/Stunden/AG-Gesamtkosten; PDF-/CSV-Export
- **Statistik** — Abwesenheiten des Jahres: KPIs Krank/Urlaub/Nicht verfügbar, _StatsBarChart, per-Mitarbeiter-Zeilen (read-only)

**Aktionen (6)**

- Aufträge: „Neu“ (Arbeitsauftrag) + Statusfilter-Chips
- Lohn: Lohnarten-Katalog [list_alt], Lohn-Einstellungen {Jahr} [tune], „Abrechnung“ (neu)
- Lohn: „Alle Entwürfe freigeben (n)“ (Batch)
- Lohn: Status ändern (PopupMenu: entwurf/freigegeben/bezahlt/storniert), PDF-Export je Abrechnung
- Finanzen: Export-Menü (PDF / CSV) für Kosten pro Mitarbeiter
- Monatsleiste (Prev/Next)

**Sheets & Dialoge (7)**

- _TaskEditorSheet (Arbeitsauftrag anlegen/bearbeiten, Löschen)
- _PayrollEditorSheet (Abrechnung erstellen: Lohnzeilen, Kirchensteuer, „Aus Stunden/Vertrag“, Löschen)
- _PayLineEditorSheet (Lohnzeile hinzufügen)
- _PayLineTypeKatalogSheet (Lohnarten-Katalog: neue Lohnart, bearbeiten, löschen)
- _PayLineTypeEditorSheet (Lohnart: Steuerfrei/SV-frei/Deaktiviert, DATEV-Lohnartnummer)
- _OrgPayrollSettingsSheet (Lohn-Einstellungen des Jahres: U1-Umlage, Defaults)
- showDialog „Alle Entwürfe freigeben“ (Bestätigung)

**Versteckt / gegatet (5)**

- ⨯ „Alle Entwürfe freigeben (n)“ nur wenn Entwürfe > 0
- ⨯ AG-Gesamtkosten-StatCard nur wenn totalEmployer > 0
- ⨯ Kundenaufträge-Leerzustand vs. Liste
- ⨯ DATEV-Lohnartnummer-Feld in Lohnart-Editoren (Validierung 1–5 Ziffern)
- ⨯ PayrollResult.disclaimer-Banner (Richtwert-Hinweis)

> Eigenes Monats-State (_month). DATEV-Lohn-Export selbst (buildBewegungsdaten) liegt NICHT hier, sondern im Zeitwirtschaft-Lohnlauf-Screen (gated APP_DATEV_LOHN_ENABLED && isAdmin); hier nur die Lohnart-Zuordnung.

### Mitarbeiter-Detail (9-Tab-Hub) · `detail-tab`

**Route:** `/personal/{uid} (deep-linkbar, AppRoutes.personalDetailPath)`  
**Zugriff:** admin-only (viewer.isAdmin; URL-Gate per /personal/-Prefix + _gateRedirect; sonst „Nur für Administratoren.“)

**Unterbereiche / Tabs (2)**

- **Visitenkarte (_EmployeeVCard)** — Avatar/Initialen, Name, E-Mail, Aktiv/Inaktiv-Badge
- **TabBar (scrollbar, Icon+Text)** — 9 Tabs: Übersicht · Stammdaten · Gehalt · Qualifikationen · Ausbildungen · Kinder · Dokumente · Notizen · Verwalten

**Aktionen (2)**

- Breadcrumb-Rücksprung zur Personal-Liste
- Tab-Wechsel zwischen den 9 Tabs

**Versteckt / gegatet (2)**

- ⨯ Cold-Start/Deep-Link: CircularProgressIndicator solange Stammdaten laden (team.members leer)
- ⨯ EmptyState „Mitarbeiter nicht gefunden“ wenn kein member und kein empProfile

> DefaultTabController length 9, Reihenfolge exakt wie AllTec employee_detail_page. Jeder Tab unten als eigene detail-tab-Area erfasst.

### Detail-Tab: Übersicht · `detail-tab`

**Route:** `/personal/{uid} (Tab 1)`  
**Zugriff:** admin-only

**Unterbereiche / Tabs (3)**

- **Status-Badges** — Beschäftigungsstatus + „Befristet“ + „Zugang inaktiv“ (tonbasiert)
- **KPI-Zählkarten** — SummaryCardRow: Qualifikationen / Ausbildungen / Kinder / Dokumente
- **Info-Karten** — Persönliche Daten, Anschrift, Beschäftigung (Eintritt/Probezeit/Befristet/Austritt), Kontakt, Letzte Notizen

**Versteckt / gegatet (3)**

- ⨯ EmptyState „Noch keine Stammakte“ wenn kein EmployeeProfile (Verweis auf Stammdaten-Tab)
- ⨯ Anschrift-Zusatzzeile nur wenn addressExtra gesetzt
- ⨯ „Letzte Notizen“-Karte nur wenn Notizen vorhanden (max. 3)

> Rein lesend; Bearbeitung über die Fach-Tabs.

### Detail-Tab: Stammdaten · `detail-tab`

**Route:** `/personal/{uid} (Tab 2)`  
**Zugriff:** admin-only

**Unterbereiche / Tabs (4)**

- **Karte Stammdaten** — Kürzel, Personalnummer, Familienstand, Anzahl Kinder, Personengruppe, Nationalität, Geburtsort, Konfession, Geburtsname
- **Karte Status & Vereinbarungen** — Status, Eintritt, Erwerbsart, Teilnahme Zeiterfassung, Auto-Buchung, Probezeit/Befristung/Langzeitkrank/Letzter Arbeitstag/Kündigung/Austritt-Felder
- **Karte Klassifizierungen** — Abteilung, Position, Vorgesetzter, Vertreter, Kostenstelle, Produktive Zeit %
- **Karte Arbeitszeit (read-only)** — FTE-Faktor, Urlaubstage/Jahr, Teilnahme Zeiterfassung (Quelle Zeitwirtschaft/SollzeitProfile)

**Aktionen (2)**

- Bearbeiten je Karte 1–3 [edit_outlined]
- Datumsfelder wählen/leeren (showDatePicker)

**Sheets & Dialoge (3)**

- _StammdatenDialog (Kürzel/Personalnr./Familienstand/Kinder/Personengruppe/Konfession/Nationalität/Geburtsort/Geburtsname)
- _StatusDialog (Status/Erwerbsart/Daten/Kündigungsfrist Wert+Typ/Anmerkung/Gründe/Austrittsmodalitäten/Teilnahme+Auto-Buchung Switches)
- _KlassifizierungDialog (Abteilung/Position/Vorgesetzter/Vertreter/Kostenstelle/Produktive Zeit)

**Versteckt / gegatet (1)**

- ⨯ Arbeitszeit-Karte hat keinen Bearbeiten-Button (read-only)

> Schreibpfad PersonalProvider.saveEmployeeProfile (copyWith mit clearX-Flags). DSGVO-Art.-9-Felder bewusst nicht erfasst.

### Detail-Tab: Gehalt (Lohn-Pin/payroll) · `detail-tab`

**Route:** `/personal/{uid} (Tab 3)`  
**Zugriff:** admin-only (sensible Lohn-/Gehaltsdaten)

**Unterbereiche / Tabs (4)**

- **Gehaltsdaten** — Gehaltstyp/Brutto/Stundensatz (aus EmploymentContract), Steuerklasse/Beschäftigungsart/Kirchensteuer (PayrollProfile), Steuer-ID/SV-Nr./Krankenkasse/KK-Art/Entgeltgruppe/Gültig ab (EmployeeProfile)
- **Vermögenswirksame Leistungen (VWL)** — AG-/AN-Anteil, Institut, Vertragsnr., Beginn/Ende
- **Zulagen (Liste)** — Bezeichnung/Betrag/Prozent/Bemerkung, je Eintrag löschen
- **Bankverbindungen (Liste)** — IBAN/BIC/Bank/Kontoinhaber, Haupt-Chip, löschen

**Aktionen (5)**

- Gehaltsdaten bearbeiten [edit] → speichert PayrollProfile + EmployeeProfile
- VWL bearbeiten [edit]
- Zulage hinzufügen [add]
- Bankverbindung hinzufügen [add]
- Zulage/Bankverbindung löschen [delete_outlined]

**Sheets & Dialoge (4)**

- _GehaltDialog (Steuerklasse/Beschäftigungsart/KK-Art/Steuer-ID/SV-Nr./Krankenkasse/Entgeltgruppe/Kirchensteuer-Switch)
- _VwlDialog (AG-/AN-Anteil €, Institut, Vertragsnummer)
- _ZulageDialog (Bezeichnung*/Betrag/Bemerkung)
- _BankDialog (Kontoinhaber/IBAN*/BIC/Bank; erste = isPrimary)

**Versteckt / gegatet (3)**

- ⨯ Stundensatz nur wenn Vertrag salaryKind == hourly
- ⨯ Karten-Hinweise „Keine VWL-Daten / Keine Zulagen / Keine Bankverbindungen“ bei leeren Listen
- ⨯ Haupt-Chip nur bei isPrimary-Bankkonto

> Payroll-Pin: getrennte Saves (savePayrollProfile + saveEmployeeProfile). Brutto/Stundensatz/Gehaltstyp read-only aus dem Arbeitsvertrag (Pflege im Verwalten-Tab-Konfigurationssheet).

### Detail-Tab: Qualifikationen · `detail-tab`

**Route:** `/personal/{uid} (Tab 4)`  
**Zugriff:** admin-only

**Unterbereiche / Tabs (1)**

- **Zähler-Kopf + Liste** — „n Qualifikationen“, je Eintrag Bezeichnung/Art/Ausstellende Stelle/Erworben/Gültig bis

**Aktionen (3)**

- Qualifikation hinzufügen [add]
- Bearbeiten [edit_outlined]
- Löschen [delete_outlined] (AppConfirmDialog)

**Sheets & Dialoge (1)**

- _QualificationDialog (Bezeichnung*/Qualifikationsart/Beschreibung/Zertifikat-Nr./Ausstellende Stelle/Erworben am/Gültig bis)

**Versteckt / gegatet (1)**

- ⨯ EmptyState „Keine Qualifikationen vorhanden“

> saveEmployeeQualification / deleteEmployeeQualification.

### Detail-Tab: Ausbildungen · `detail-tab`

**Route:** `/personal/{uid} (Tab 5)`  
**Zugriff:** admin-only

**Unterbereiche / Tabs (1)**

- **Zähler-Kopf + Liste** — „n Ausbildungen“, je Eintrag Bezeichnung/Art/Stätte/Fachrichtung/Von–Bis + Status-Badge (laufend/abgeschlossen/abgebrochen)

**Aktionen (3)**

- Ausbildung hinzufügen [add]
- Bearbeiten [edit_outlined]
- Löschen [delete_outlined] (AppConfirmDialog)

**Sheets & Dialoge (1)**

- _AusbildungDialog (Bezeichnung*/Ausbildungsart/Ausbildungsstätte/Fachrichtung/Abschluss/Status/Beginn/Ende/Anmerkungen)

**Versteckt / gegatet (1)**

- ⨯ EmptyState „Keine Ausbildungen vorhanden“

> saveEmployeeAusbildung / deleteEmployeeAusbildung.

### Detail-Tab: Kinder · `detail-tab`

**Route:** `/personal/{uid} (Tab 6)`  
**Zugriff:** admin-only

**Unterbereiche / Tabs (1)**

- **Zähler-Kopf + Liste** — „n Kinder“, je Eintrag Anzeigename/Geburtstag/Kindergeldanspruch/Anmerkungen

**Aktionen (3)**

- Kind hinzufügen [add]
- Bearbeiten [edit_outlined]
- Löschen [delete_outlined] (AppConfirmDialog)

**Sheets & Dialoge (1)**

- _ChildDialog (Vorname*/Nachname/Geburtstag/Anmerkungen/Kindergeldanspruch-Switch)

**Versteckt / gegatet (1)**

- ⨯ EmptyState „Keine Kinder hinterlegt“

> saveEmployeeChild / deleteEmployeeChild.

### Detail-Tab: Dokumente (Upload) · `detail-tab`

**Route:** `/personal/{uid} (Tab 7)`  
**Zugriff:** admin-only (EmployeeDocumentsCard canManage=true)

**Unterbereiche / Tabs (2)**

- **Dokumentenliste** — je Dokument Kategorie/Größe/intern/Bestätigung/Workflow-Status; Icon je Kategorie (Arbeitsvertrag/Lohnabrechnung/Bescheinigung/Krankmeldung/Zeugnis/Schulung/Abmahnung/Kündigung/Führungszeugnis/Gesundheitszeugnis/Sonstiges)
- **Aufbewahrungs-Banner** — _ExpiredRetentionBanner (DSGVO Art. 17) mit Bulk-Löschen

**Aktionen (6)**

- Dokument hochladen [upload_file] (FilePicker pdf/jpg/jpeg/png, max 15 MB)
- Ansehen [visibility] (In-App-Viewer PDF/Bild)
- Herunterladen [download]
- Metadaten bearbeiten [edit]
- Löschen [delete] (AppConfirmDialog)
- Banner: Abgelaufene löschen (Bulk)

**Sheets & Dialoge (4)**

- _DocumentUploadSheet (Kategorie/Titel/Notiz/„Für Mitarbeiter sichtbar“/„Bestätigung nötig“ + Fortschritt)
- _DocumentMetaSheet (Kategorie/Titel/Notiz/Sichtbarkeit ändern)
- _DocumentViewerPage (Vollbild PDF via printing / Bild via InteractiveViewer)
- AppConfirmDialog „Dokument löschen?“ / „Abgelaufene Dokumente löschen?“

**Versteckt / gegatet (5)**

- ⨯ Nur Cloud-Modus: _Hint „Dokumente benötigen den Cloud-Modus“ wenn !documentsAvailable (lokal/Demo)
- ⨯ _ExpiredRetentionBanner nur wenn ein Dokument die Aufbewahrungsfrist überschritten hat
- ⨯ Upload-Button nur bei canManage && available
- ⨯ „Bestätigung nötig“-Switch nur aktiv wenn „Für Mitarbeiter sichtbar“ an
- ⨯ Ansehen-Button nur bei viewbarem contentType

> Geteilte Widget-Card mit der Selbstsicht (Meine Akte, canManage=false). PA-8.1 geführte DSGVO-Löschung admin-getriggert.

### Detail-Tab: Notizen · `detail-tab`

**Route:** `/personal/{uid} (Tab 8)`  
**Zugriff:** admin-only

**Unterbereiche / Tabs (1)**

- **Zähler-Kopf + Liste** — „n Notizen“ (neueste zuerst), Text + Ersteller + Zeitstempel; kein Bearbeiten

**Aktionen (2)**

- Notiz hinzufügen [add]
- Löschen [delete_outlined] (AppConfirmDialog)

**Sheets & Dialoge (1)**

- _NoteDialog (Freitext, max 4 Zeilen)

**Versteckt / gegatet (1)**

- ⨯ EmptyState „Keine Notizen vorhanden“

> addNote / deleteNote (admin-only, Audit).

### Detail-Tab: Verwalten · `detail-tab`

**Route:** `/personal/{uid} (Tab 9)`  
**Zugriff:** admin-only; Fremdlöschung zusätzlich hinter Reauth + Server-Step-up

**Unterbereiche / Tabs (5)**

- **Status & Zugang** — Switch „Zugang aktiv“ (steuert Login/Sichtbarkeit) + Dropdown Beschäftigungsstatus
- **Rolle, Vertrag & Standorte** — Buttons: Konfiguration bearbeiten (Rolle/Rechte/Vertrag/Standorte/Qualis) + Schicht-Vorlieben
- **Offboarding (bedingt)** — Checkliste: Zugang deaktivieren, Kiosk-PIN zurücksetzen, Dokumente/DSGVO-Aufbewahrung
- **Gefahrenzone** — Mitarbeiter deaktivieren (empfohlen) + Endgültig löschen
- **Technische Infos** — Benutzer-ID, Org-ID, Profil-ID, Erstellt am

**Aktionen (7)**

- Zugang aktiv umschalten (team.updateMember isActive)
- Beschäftigungsstatus wählen (aktiv/probezeit/gekündigt/ausgeschieden/ruhend)
- Konfiguration bearbeiten → showMemberConfigurationSheet
- Schicht-Vorlieben → showShiftPreferenceSheet
- Offboarding: Deaktivieren / Kiosk-PIN zurücksetzen
- Mitarbeiter deaktivieren (AppConfirmDialog)
- Endgültig löschen (Reauth + AccountDeleteConfirmDialog)

**Sheets & Dialoge (4)**

- _MemberEditorSheet (showMemberConfigurationSheet — aus team_management_screen.dart)
- _ShiftPreferenceEditorSheet (showShiftPreferenceSheet)
- AccountDeleteConfirmDialog + Reauth (deleteMemberAccount)
- AppConfirmDialog „Mitarbeiter deaktivieren“

**Versteckt / gegatet (5)**

- ⨯ _OffboardingCard nur wenn !status.isCurrent ODER exitDate gesetzt
- ⨯ Für das EIGENE Konto KEIN „Endgültig löschen“, stattdessen Hinweis „unter Einstellungen → Konto & Profil“ (Self-Erkennung über team.currentUser)
- ⨯ „Mitarbeiter deaktivieren“-Button disabled wenn bereits inaktiv („Bereits deaktiviert“)
- ⨯ Offboarding-Schritt Kiosk-PIN done-State nach Reset; Dokumente-Schritt zeigt abgelaufene Aufbewahrung
- ⨯ EmptyState „Mitarbeiter nicht gefunden“ wenn member fehlt

> Standard = Deaktivieren (reversibel). Endgültig löschen = serverseitige Komplett-Löschung mit Anonymisierung aufbewahrungspflichtiger Daten (plan/account-loeschung.md).

### Meine Akte (Selbstsicht) · `section-screen`

**Route:** `— (Navigator.push aus Profil; keine Admin-Gate)`  
**Zugriff:** alle angemeldeten (self) — self-scoped Streams via Self-Read-Rules; read-only für den MA

**Unterbereiche / Tabs (6)**

- **Header (_HeaderCard)** — Name + „Deine persönliche Personalakte“
- **Meine Stammdaten (read-only)** — Anschrift/Telefon/E-Mail privat/Personalnummer + „Änderungen an Verwaltung melden“
- **Mein Urlaub {Jahr}** — AppMetricCards Anspruch + Resturlaub
- **Meine Lohnabrechnungen** — Liste je Monat mit Netto + Status, PDF-Download
- **Meine Qualifikationen (MeineQualifikationenCard)** — Liste mit Gültigkeits-Badge (gültig/läuft ab/abgelaufen), Nachweis-Download; read-only
- **Dokumente (canManage=false)** — Ansehen/Herunterladen + Gelesen bestätigen / Ablehnen

**Aktionen (4)**

- AppBar: Meine Daten exportieren (Art. 15 DSGVO) [download_for_offline] → PDF-Selbstauskunft
- Lohnabrechnung als PDF herunterladen
- Qualifikations-Nachweis herunterladen
- Dokument ansehen / herunterladen / Gelesen bestätigen / Ablehnen (mit Pflichtkommentar)

**Sheets & Dialoge (2)**

- showDialog „Dokument ablehnen“ (Grund*)
- _DocumentViewerPage (In-App-Viewer)

**Versteckt / gegatet (6)**

- ⨯ Export-Aktion nur wenn profile != null
- ⨯ EmptyState „Nicht angemeldet“ ohne Profil
- ⨯ Stammdaten-Karte zeigt Hinweis statt Daten wenn kein EmployeeProfile
- ⨯ Lohnabrechnungen-Karte Hinweis wenn keine freigegebenen Abrechnungen
- ⨯ Qualifikations-Nachweis-Download nur wenn verknüpftes sichtbares Dokument existiert; „Nachweis nicht mehr vorhanden“ bei toter FK
- ⨯ „Gelesen bestätigen“ nur wenn nicht bestätigt; „Ablehnen“ nur wenn Bestätigung nötig & nicht abgelehnt

> Art.-15-Selbstauskunft sammelt Profil/Vertrag/Urlaub/Payrolls/Dokumente ins PDF (ExportService.exportSelbstauskunftPdf).

### Organisation (Teamverwaltung — Standorte/Teams/Regelwerk) · `section-screen`

**Route:** `— (Navigator.push aus Personal-Hub, parentLabel „Personal“)`  
**Zugriff:** admin-only (auth.isAdmin; sonst „Die Organisation ist nur fuer Admins verfuegbar.“)

**Unterbereiche / Tabs (3)**

- **Standorte** — Standort-Karten (Adresse/Öffnungszeiten/Bedarf), Fahrtzeit-Regeln; anlegen/bearbeiten/löschen
- **Teams & Qualifikationen** — Team-Karten (Mitglieder) + Qualifikations-Katalog; anlegen/bearbeiten/löschen
- **Regelwerk (Compliance)** — Basis-Regelwerk (Ruhezeit/Pausen/Max-Schicht/Minijob/Nachtfenster) + Regelaktivierung pro Mitarbeiter (Jugend-/Mutterschutz + WorkRuleSettings-Switches)

**Aktionen (7)**

- Standort anlegen [add]
- Fahrtzeitregel [route] (braucht ≥2 Standorte)
- Team anlegen [add]
- Qualifikation [add]
- Regelwerk „Bearbeiten“ [edit]
- Karte bearbeiten/löschen (PopupMenu je Karte, _confirmDelete)
- Pro Mitarbeiter: Jugendarbeitsschutz/Mutterschutz + einzelne Regel-Switches (Ruhezeit/Pausen/Tagesgrenze/Minijob/Warnhinweise)

**Sheets & Dialoge (6)**

- _SiteEditorSheet (Standort anlegen/bearbeiten)
- _TravelTimeRuleEditorSheet (Fahrtzeitregel)
- _TeamEditorSheet (Team)
- _QualificationEditorSheet (Qualifikation)
- _RuleSetEditorSheet (Regelwerk)
- _confirmDelete-Dialoge je Entität

**Versteckt / gegatet (5)**

- ⨯ Ganzer Screen admin-only
- ⨯ Fahrtzeiten-Sektion nur wenn travelTimeRules nicht leer
- ⨯ Fahrtzeitregel-Aktion bricht mit SnackBar ab wenn < 2 Standorte
- ⨯ Regelaktivierung-Sektion nur wenn Regelwerk (ruleSet) existiert; sonst _TeamEmptyState „Noch kein Regelwerk vorhanden.“
- ⨯ Leerzustände je Sektion (keine Standorte/Teams/Qualifikationen)

> Frühere Teamverwaltung ohne Mitarbeiter-Tab; nur noch aus dem Personalbereich erreichbar. Mitarbeiter-Konfig/Schicht-Vorlieben-Sheets werden vom Verwalten-Tab wiederverwendet (showMemberConfigurationSheet/showShiftPreferenceSheet).

---

<a id="cluster-11"></a>

## 11. Personal Auswertungen + Reporting

*5 Bereiche.*

### Monatsbericht · `section-screen`

**Route:** `— (Navigator.push, parentLabel meist "Zeit")`  
**Zugriff:** canViewReports (sonst Gate-Hinweis); Admin-Zusatz-UI hinter isAdmin

**Unterbereiche / Tabs (6)**

- **Monatsauswahl (_MonthSelector)** — Container mit chevron_left/chevron_right IconButtons + Monatslabel (MMMM yyyy de_DE); previousMonth/nextMonth
- **Mitarbeiter-Auswahl (_EmployeeSelector)** — Nur isAdmin: DropdownButtonFormField 'Mitarbeiter fuer Bericht' (aktive Members); leerer Zustand Card 'Keine Mitarbeiter verfuegbar'
- **Profilkarte** — Card/ListTile mit Avatar, displayName, email, role.label des reportUser
- **Standort-Filter** — Nur wenn availableSites nicht leer: Wrap aus FilterChips je Standort (Mehrfachauswahl, _selectedSiteIds)
- **Zusammenfassung (_StatsGrid)** — Kacheln: Gesamtstunden, Arbeitstage, Ueberstunden, Bruttolohn (nur wenn hourlyRate>0). Nur genehmigte Zeiten (countsAsIst)
- **Eintraege-Liste** — _ReportEntryTile je Eintrag (Datum, Zeitspanne, Notiz, Stunden, Lohn, Ueberstunden-Icon trending_up); leer -> _EmptyReportState 'Keine Eintraege fuer diesen Monat'

**Aktionen (5)**

- PDF exportieren (FilledButton, deaktiviert wenn keine Eintraege / _exporting; Label 'Wird exportiert...')
- Vormonat (chevron_left)
- Folgemonat (chevron_right)
- FilterChip Standort an/aus
- Breadcrumb-Zurück (parentLabel-Tap -> pop)

**Versteckt / gegatet (6)**

- ⨯ Gate-Ersatzseite 'Der Monatsbericht ist fuer dieses Profil deaktiviert.' wenn !canViewReports
- ⨯ Mitarbeiter-Dropdown _EmployeeSelector nur bei isAdmin
- ⨯ Bruttolohn-Kachel + Lohn-Spalte im Eintrag nur wenn settings.hourlyRate>0
- ⨯ Standort-Filter nur wenn Eintraege/Sites Standortdaten haben
- ⨯ Ueberstunden-trending_up-Icon nur bei isOvertime
- ⨯ Leerer-Mitarbeiter-Hinweis-Card 'Keine Mitarbeiter verfuegbar'

> BreadcrumbAppBar Zeit > Monatsbericht. Export sendet nur countsAsIst (approved). maxWidth 1100.

### Statistik · `section-screen`

**Route:** `— (Navigator.push, parentLabel meist "Profil")`  
**Zugriff:** canViewReports (sonst Gate-Hinweis)

**Unterbereiche / Tabs (5)**

- **Kopf (_HeaderSection)** — Titel 'Statistik' + Untertitel 'Auswertungen und Diagramme fuer <Monat>'
- **Summary-Karten (_SummaryCardsRow)** — _MetricCard: Gesamtstunden, Ueberstunden, Arbeitstage
- **Ueberstunden-Ampel (_OvertimeTrafficLight)** — Status-Card grün/gelb/rot: 'Im Soll' / 'Nahe am Soll (+x h)' / 'Ueberstunden (+x h)', Ist vs Soll
- **Stunden pro Tag (_MonthlyHoursChart)** — _SectionCard mit BarChart Stunden je Tag (nur countsAsIst); leer -> 'Keine Daten fuer diesen Monat vorhanden.'
- **Jahresuebersicht (_YearOverviewChart)** — _SectionCard 'Jahresuebersicht <Jahr>' BarChart Stunden je Monat, aktueller Monat hervorgehoben

**Aktionen (3)**

- CSV exportieren (FilledButton, Icon download; SnackBar 'Keine Eintraege zum Exportieren vorhanden.' wenn leer)
- Breadcrumb-Zurück (parentLabel-Tap -> pop)
- Chart-Tooltips per Touch (BarTouchData)

**Versteckt / gegatet (2)**

- ⨯ Gate-Ersatzseite 'Die Statistik ist fuer dieses Profil deaktiviert.' wenn !canViewReports
- ⨯ Chart-Leerzustand 'Keine Daten fuer diesen Monat vorhanden.'

> BreadcrumbAppBar Profil > Statistik. CSV mit UTF-8-BOM, ;-Delimiter, Status-Spalte, Formel-Injection-Escaping. maxWidth 1100. fl_chart.

### Kennzahlen (Management-Dashboard) · `section-screen`

**Route:** `/kennzahlen`  
**Zugriff:** isAdmin || canManageShifts (RoutePermissions); einzelne KPIs Katalog-gesteuert über visibleKpis/KpiPermissions

**Unterbereiche / Tabs (3)**

- **Monatsnavigation (_MonthRow)** — chevron_left 'Vormonat' + Monatslabel + chevron_right 'Folgemonat'; Default abgeschlossener Vormonat
- **KPI-Kacheln (_KpiTile)** — Sollzeit (Org), Istzeit (approved), Saldo (grün/gelb je Vorzeichen), Offene Freigaben, Offene Abwesenheiten, Bestandswert (EK), Bestandswert (VK) — je nur wenn Datenfeld vorhanden/berechtigt
- **Hinweistext** — 'Bindende Istzeit zählt nur freigegebene Zeiteinträge; Kennzahlen richten sich nach deiner Berechtigung.'

**Aktionen (3)**

- Vormonat (chevron_left)
- Folgemonat (chevron_right)
- Breadcrumb-Zurück (Übersicht -> maybePop)

**Versteckt / gegatet (5)**

- ⨯ Lade-Spinner während dashboard.isLoading
- ⨯ Fehler-Banner (AppStatusBanner error) bei dashboard.error
- ⨯ AppEmptyState 'Für deine Berechtigung sind derzeit keine Kennzahlen sichtbar.' wenn tiles leer
- ⨯ Einzelne KPI-Kacheln erscheinen nur bei vorhandenem Datenfeld (orgZeit/offeneAbwesenheiten/bestandswertEk/Vk) — Lohn/EK per KpiPermissions ausblendbar
- ⨯ Bestandswert EK/VK-Kacheln nur wenn Werte != null

> REPORTING-4. BreadcrumbAppBar Übersicht > Kennzahlen. maxWidth 900, Kacheln Wrap 220px.

### Standortvergleich · `section-screen`

**Route:** `/standortvergleich`  
**Zugriff:** admin-only (erster Schnitt; teamlead bewusst ausgeschlossen wg. REPORTING-7)

**Unterbereiche / Tabs (3)**

- **Monatsnavigation (_MonthRow)** — chevron_left 'Vormonat' + Monatslabel + chevron_right 'Folgemonat'; Default Vormonat
- **Standort-Karten (_SiteCard)** — Je Standort: Rang-Avatar (Rang 1 grün), Name/'Ohne Standort', Umsatz-Delta%, Umsatz brutto, Rohertrag netto, Belege, Personalstunden, Bestandswert EK, Lohn (Richtwert), Umsatzanteil-Balken '% des Org-Umsatzes'
- **Lohn-Richtwert-Hinweis** — AppStatusBanner info wenn hatLohnAllokation: Lohnkosten sind Richtwert nach geleisteten Stunden

**Aktionen (3)**

- Vormonat (chevron_left)
- Folgemonat (chevron_right)
- Breadcrumb-Zurück (Übersicht -> maybePop)

**Versteckt / gegatet (7)**

- ⨯ Lade-Spinner während isSiteVergleichLoading
- ⨯ Fehler-Banner (AppStatusBanner error) bei siteVergleichError
- ⨯ AppEmptyState 'Keine Standortdaten für diesen Monat.' wenn kein/leerer Vergleich
- ⨯ Umsatz-Delta% nur wenn delta<0 (negativ, gelb)
- ⨯ Rohertrag/Bestandswert/Lohn-Zeilen nur wenn Wert != null
- ⨯ Lohn-Richtwert-Banner nur wenn hatLohnAllokation
- ⨯ Kartenbreite 340px nur bei breitem Layout (useNavigationRail), sonst volle Breite

> REPORTING-6. BreadcrumbAppBar Übersicht > Standortvergleich. purchasePricesIncludeVat aus FeatureFlagProvider. maxWidth 1100.

### SummaryCardRow (Reporting-KPI-Widget) · `widget`

**Route:** `— (wiederverwendbar)`  
**Zugriff:** —

**Versteckt / gegatet (2)**

- ⨯ Rendert SizedBox.shrink (nichts) wenn items leer
- ⨯ 2–4 Karten pro Zeile je nach Breite (720/480-Breakpoints)

> Wiederverwendbare responsive Reihe aus AppMetricCards; KPI-Kopfzeile Mitarbeiter-Übersicht/Personalliste. Keine eigenen Aktionen.

---

<a id="cluster-12"></a>

## 12. Profil / Einstellungen / Wissen / Protokoll / Passwörter

*13 Bereiche.*

### Einstellungen (Kachel-Hub) · `section-screen`

**Route:** `— (Navigator.push von SettingsScreen; Suchziel AppRoutes.settings)`  
**Zugriff:** alle angemeldeten Nutzer (Organisations-Kachel nur Admin)

**Unterbereiche / Tabs (2)**

- **Identitäts-Karte (_IdentityCard)** — Avatar mit Initiale, Anzeigename, E-Mail, '<Rolle> · Organisation <orgId>'. Nur wenn user != null.
- **Info-Karte (_InfoCard)** — Hinweis: persönliche Daten in 'Meine Akte', Rollen/Einladungen/Organisation pflegt Admin im Personalbereich.

**Aktionen (8)**

- Kachel 'Konto & Profil' → SettingsProfileScreen
- Kachel 'Erscheinungsbild' (Untertitel zeigt aktuellen Modus) → SettingsAppearanceScreen
- Kachel 'Benachrichtigungen' → NotificationSettingsScreen
- Kachel 'Stempeluhr & Vorlagen' → SettingsTimeclockScreen
- Kachel 'Datenspeicher' (Untertitel Hybrid/Cloud/Nur lokal) → SettingsStorageScreen
- Kachel 'Arbeitsmodus' → Kiosk-PIN-Sheet
- Kachel 'Organisation' (admin-only) → SettingsOrgScreen
- AppBar: ThemeModeButton (Hell/Dunkel-Schnellschalter)

**Sheets & Dialoge (1)**

- showKioskPinSetupSheet (Kiosk-PIN fürs Laden-Tablet)

**Versteckt / gegatet (2)**

- ⨯ Kachel 'Organisation' nur bei user.isAdmin
- ⨯ Identitäts-Karte nur wenn Profil geladen

> BreadcrumbAppBar 'Profil > Einstellungen'. AdaptiveCardGrid, maxWidth 980. Detailformulare in lib/screens/settings/.

### Konto & Profil (SettingsProfileScreen) · `section-screen`

**Route:** `— (Navigator.push aus Hub)`  
**Zugriff:** alle (Self)

**Unterbereiche / Tabs (3)**

- **Konto-Info-Karte** — Avatar, Anzeigename, E-Mail, Rolle · Organisation. Nur wenn currentUser != null.
- **Anzeigename-Feld** — TextFormField 'Anzeigename'; speichert nur name, Personal-/Lohnfelder unverändert (Rules-Pin settingsPayrollFieldsUnchanged).
- **Gefahrenzone (_buildDangerZone)** — Rot abgesetzte Karte 'Gefahrenzone': Konto komplett/unwiderruflich löschen, aufbewahrungspflichtige Daten anonymisiert.

**Aktionen (3)**

- ListTile 'Meine Akte' → context.push(AppRoutes.meineAkte)
- FilledButton 'Speichern' / 'Wird gespeichert...'
- OutlinedButton 'Konto löschen' / 'Wird gelöscht...' → AccountDeleteConfirmDialog + Reauth + deleteOwnAccount

**Sheets & Dialoge (1)**

- AccountDeleteConfirmDialog (Bestätigung + optional Passwort-Reauth)

**Versteckt / gegatet (2)**

- ⨯ Gefahrenzone immer sichtbar aber bewusst abgesetzt
- ⨯ Passwortfeld im Lösch-Dialog nur bei Passwort-Konten (needsPassword)

> Reauth via auth.reauthenticate(password); bei Erfolg leitet Router-Gate auf Anmeldung um. Fehler als SnackBar.

### Erscheinungsbild (SettingsAppearanceScreen) · `section-screen`

**Route:** `— (Navigator.push aus Hub)`  
**Zugriff:** alle  
**Feature-Flag:** RedesignFlags/V2-Toggle nur bei APP_DISABLE_AUTH oder kDebugMode

**Unterbereiche / Tabs (2)**

- **Farbschema-Selektor (_ThemeSelector)** — Card mit 3 InkWell-Segmenten: 'System' (brightness_auto), 'Hell' (light_mode), 'Dunkel' (dark_mode); setzt ThemeProvider.setThemeMode.
- **Redesign-Toggle (_RedesignToggle)** — SwitchListTile 'Neues Design (Signal Teal)' — Vorschau des Redesigns, live umschaltbar; setzt setRedesignV2Override.

**Aktionen (2)**

- Tap auf System/Hell/Dunkel-Segment
- Switch 'Neues Design (Signal Teal)'

**Versteckt / gegatet (2)**

- ⨯ Redesign-Toggle nur wenn AppConfig.disableAuthentication || kDebugMode — sonst SizedBox.shrink()
- ⨯ Info-Tipp-Zeile zum Sonne/Mond-Knopf

> Hinweis, dass Sonne/Mond-Knopf in App-Leiste hell/dunkel mit einem Tap wechselt.

### Organisation (SettingsOrgScreen) · `section-screen`

**Route:** `— (Navigator.push aus Hub)`  
**Zugriff:** admin-only (Kachel nur bei isAdmin sichtbar)

**Unterbereiche / Tabs (2)**

- **Automatische Schichtverteilung (_OrgAutoPlanSettingsCard)** — Switch 'Stundengrenzen hart durchsetzen'; Felder 'Schichtlänge' (min), 'Pause' (min), 'Standard-Bedarf je Öffnungsfenster'.
- **MwSt-Behandlung** — Switch 'Einkaufspreise enthalten MwSt (brutto)' — steuert Rohertrag/Wareneinsatz netto/brutto.

**Aktionen (3)**

- Switch 'Stundengrenzen hart durchsetzen'
- Switch 'Einkaufspreise enthalten MwSt (brutto)'
- FilledButton 'Speichern' (mit Spinner)

**Versteckt / gegatet (1)**

- ⨯ Ganzer Screen nur über admin-only Hub-Kachel erreichbar

> Persistiert via FeatureFlagProvider.saveOrgSettings; Änderung wird ins Änderungsprotokoll geloggt (AuditAction.updated, 'Organisationseinstellungen'). SnackBar 'Einstellungen gespeichert'.

### Datenspeicher (SettingsStorageScreen) · `section-screen`

**Route:** `— (Navigator.push aus Hub)`  
**Zugriff:** alle (im Demo-/local-Modus gesperrt)

**Unterbereiche / Tabs (2)**

- **Speicherort-Auswahl (_StorageLocationCard)** — RadioGroup: 'Hybrid-Speicher', 'Cloud-Speicher', 'Nur lokal speichern' mit Erklärtexten; LinearProgressIndicator während Migration.
- **Gesperrter Zustand** — Bei auth.authDisabled: Karte mit cloud_off-Icon 'Diese App wurde im lokalen Modus gestartet. Der Speicherort kann in diesem Build nicht gewechselt werden.'

**Aktionen (1)**

- RadioListTile Hybrid / Cloud / Nur lokal auswählen → _changeStorageLocation (cacheAll/syncAll aller Provider)

**Versteckt / gegatet (2)**

- ⨯ Radio-Auswahl versteckt bei authDisabled (stattdessen Info-Karte)
- ⨯ Fortschrittsbalken nur während busy

> Migriert alle Provider (Team/Work/Schedule/Inventory/Contact/Personal/Finance/Audit/Zeit) in kanonischer Reihenfolge, dann storage.setLocation. Modus-abhängige SnackBar-Texte.

### Stempeluhr & Vorlagen (SettingsTimeclockScreen) · `section-screen`

**Route:** `— (Navigator.push aus Hub)`  
**Zugriff:** alle (Self)

**Unterbereiche / Tabs (2)**

- **Stempeluhr** — TextFormField 'Auto-Pause nach (Minuten)' — Stempeluhr fügt 30 min Pause hinzu wenn überschritten, 0 = deaktiviert.
- **Arbeitszeit-Vorlagen (_TemplateListCard)** — Liste persönlicher WorkTemplates mit Name/Zeitraum/Pause/Notiz; leerer Zustand 'Noch keine Vorlagen vorhanden'.

**Aktionen (5)**

- FilledButton 'Speichern' (Auto-Pause)
- TextButton 'Neu' → Vorlagen-Editor-Sheet
- Vorlage-ListTile IconButton 'Bearbeiten'
- IconButton 'Löschen' → Bestätigungsdialog
- Leerzustand OutlinedButton 'Vorlage anlegen'

**Sheets & Dialoge (2)**

- _TemplateEditorSheet (showModalBottomSheet: Name, Beginn/Ende TimePicker, Pause, Notiz)
- AlertDialog 'Vorlage löschen?'

**Versteckt / gegatet (2)**

- ⨯ Leerzustand-Karte mit CTA nur wenn keine Vorlagen
- ⨯ Notiz-Zeile / isThreeLine nur wenn Vorlage Notiz hat

> Speichert nur autoBreakAfterMinutes (Rules-Pin, übrige Settings unverändert). Editor-Sheet validiert Endzeit > Startzeit.

### Passwortmanager (PasswordsScreen /passwoerter) · `section-screen`

**Route:** `AppRoutes (/passwoerter)`  
**Zugriff:** alle aktiven Nutzer (eigene Einträge); zentrale/'Zentral'-Einträge nur canManagePasswords/Admin  
**Feature-Flag:** PasswordProvider.isEnabled (passwordManagerEnabled / Blaze)

**Unterbereiche / Tabs (3)**

- **Nicht-verfügbar-Zustand** — Wenn !provider.isEnabled: zentrierter Text 'Der Passwortmanager ist in dieser Umgebung nicht verfügbar.'
- **Suche + Kategorie-Filter** — Suchfeld 'Suchen (Dienst, Filiale, Kategorie)'; horizontale ChoiceChips 'Alle' + je PasswordCategory (KVG/Lotto/Post/Lieferantenportal/Internes System/Behördenportal/Sonstiges).
- **Passwort-Liste (_PasswordCard)** — Karten mit Kategorie-Icon, Titel, Untertitel (Kategorie · Filiale · 'freigegeben'); leerer Zustand 'Noch keine Passwörter hinterlegt.'

**Aktionen (6)**

- AppBar IconButton 'Aktualisieren' (refresh)
- FAB 'Neu' → Editor-Sheet
- Card IconButton 'Anzeigen' (nur wenn hasSecret) → Reveal-Flow
- Card PopupMenuButton 'Bearbeiten'/'Löschen' (nur canManage)
- RefreshIndicator Pull-to-refresh
- Reveal-Sheet Kopier-Buttons (Benutzername/Passwort/Notiz)

**Sheets & Dialoge (4)**

- _confirmReveal: Biometrie/Geräte-PIN (local_auth, nicht Web) oder AlertDialog 'Passwort anzeigen'
- _RevealSheet (showModalBottomSheet, Auto-Hide-Countdown 30s, Screenshot-Schutz, Clipboard-Auto-Clear 20s)
- _PasswordEditorSheet (Titel/Kategorie/URL/Filiale/Scope/Zielgruppe/Zugangsdaten)
- AlertDialog '„<Titel>" löschen?'

**Versteckt / gegatet (7)**

- ⨯ Ganzer Screen ausgeblendet/ersetzt durch Hinweis wenn !isEnabled
- ⨯ 'Anzeigen'-Button disabled ohne Secret
- ⨯ PopupMenu (Bearbeiten/Löschen) nur bei canManage
- ⨯ Editor: SegmentedButton 'Eigenes'/'Zentral' + Zielgruppen-Chips (Rollen/Filialen/Mitarbeiter) nur bei canManagePasswords
- ⨯ Filiale-Dropdown nur wenn Sites vorhanden
- ⨯ Fehlermeldung nur wenn provider.errorMessage != null
- ⨯ biometricAuthOverride nur für Tests

> Nie Klartext in Liste. Reveal erzwingt frischen Reauth-Nonce + Server-Rate-Limit; Kopieren wird protokolliert (logCopy). ScreenSecurity aktiv solange Secret sichtbar.

### Änderungsprotokoll (AuditLogScreen) · `section-screen`

**Route:** `AppRoutes.auditLog`  
**Zugriff:** admin-only

**Unterbereiche / Tabs (3)**

- **Zugriff-verweigert-Zustand** — Wenn Profil null oder !isAdmin: 'Nur für Administratoren.'
- **Filterleiste (_FilterBar)** — Volltext-Suchfeld 'Protokoll durchsuchen' (mit Clear); Dropdown 'Aktion' (Alle + AuditAction-Werte); Dropdown 'Objekttyp' (Alle + dynamische Typen).
- **Protokoll-Liste** — ListTiles Aktion·Objekttyp mit Icon, Summary, Akteur, Zeitstempel (de_DE); leerer Zustand 'Noch keine protokollierten Änderungen.' bzw. 'Keine Einträge für die aktuelle Filterauswahl.'

**Aktionen (4)**

- AppBar IconButton 'Als CSV exportieren' (disabled wenn leer/exportiert)
- 'Mehr laden'-Button (erhöht Cloud-Stream-Limit, nur wenn hasMore)
- Filter-Dropdowns Aktion/Objekttyp
- Suchfeld + Clear-Button

**Versteckt / gegatet (4)**

- ⨯ Ganzer Screen nur für Admins (sonst Hinweis)
- ⨯ 'Mehr laden'-Zeile nur wenn auditProvider.hasMore
- ⨯ Objekttyp-Filter setzt sich automatisch zurück wenn Typ nicht mehr vorkommt
- ⨯ Suchfeld-Clear-Icon nur bei Text

> Breadcrumb 'Personal > Änderungsprotokoll'. CSV via ExportService.exportAuditLogCsv. Icons je AuditAction (created/updated/corrected/deleted).

### Wissen & Hilfe (KnowledgeScreen) · `section-screen`

**Route:** `— (Suchziel /wissen; Navigator.push)`  
**Zugriff:** alle angemeldeten (Fach-Doku); Abschnitt 'Technik' nur Admin

**Unterbereiche / Tabs (3)**

- **Suche** — AppSearchField 'Wissen durchsuchen …'; leere Anfrage → Browse, sonst Trefferliste.
- **Browse (_Browse)** — Intro-Hero-Card 'Wissen & Hilfe'; Abschnitt-Header 'Anleitungen' und (admin) 'Technik (für Entwickler)'; Kapitel-Gruppen mit Artikel-Kacheln.
- **Suchergebnisse (_Results)** — Artikel-Kacheln mit Sektions-Label; leerer Zustand 'Keine Treffer. Versuchen Sie ein anderes Stichwort.'

**Aktionen (2)**

- Artikel-Kachel antippen → KnowledgeArticleScreen
- Suchfeld eingeben

**Versteckt / gegatet (4)**

- ⨯ Abschnitt 'Technik (für Entwickler)' / DocAudience.entwickler nur für Admin sichtbar (visibleArticles(profile))
- ⨯ Leerzustand 'Für dieses Profil sind noch keine Artikel freigegeben.'
- ⨯ Fehlerzustand 'Die Wissensdatenbank konnte nicht geladen werden.'
- ⨯ Ladeindikator während Manifest-Load

> Breadcrumb 'Profil > Wissen'. Manifest/Artikel aus DocRepository; permission-/audience-gefiltert.

### Wissens-Artikel (KnowledgeArticleScreen) · `detail-tab`

**Route:** `— (Navigator.push aus KnowledgeScreen/Querverweis)`  
**Zugriff:** abhängig von Artikel-Sichtbarkeit (isVisibleTo(profile))

**Unterbereiche / Tabs (2)**

- **Markdown-Ansicht (MarkdownView)** — Gerenderter Artikeltext (maxWidth 760) mit article:<slug>-Querverweisen.
- **Pending-Zustand (_PendingArticle)** — Wenn Body == kDocArticlePendingMarker: Titel + Zusammenfassung + 'Dieser Wissens-Artikel wird gerade geschrieben...'.

**Aktionen (2)**

- Querverweis-Tap (onOpenArticle → _openArticle) öffnet Zielartikel
- Breadcrumb 'Wissen' zurück

**Versteckt / gegatet (3)**

- ⨯ Pending-Platzhalter statt Inhalt wenn Artikel noch nicht geschrieben
- ⨯ SnackBar 'Dieser Artikel ist nicht verfügbar.' wenn Ziel nicht sichtbar
- ⨯ Ladeindikator während Body-Load

> Breadcrumb 'Wissen > <Sektionstitel>'. Querverweise re-prüfen isVisibleTo.

### Globale Suche (GlobalSearchPalette / showGlobalSearch) · `modal-sheet`

**Route:** `— (showGeneralDialog, ⌘K-Palette)`  
**Zugriff:** alle; Treffer per RoutePermissions/Rolle gefiltert

**Unterbereiche / Tabs (4)**

- **Bereiche/Module** — Permission-gefilterte Deep-Links: Tabs (Heute/Plan/Zeit/Anfragen/Kontakte/Laden/Profil) + Hauptbereiche (Warenwirtschaft, Kundenbestellungen, Scanner, Kundenwünsche, Feedback-Eingang, Inventur, Sortimentsanalyse, Bestand-Insights, Bestell-Auswertung, Laden-Benchmark, Kassierer-Prüfung, Personal, Buchhaltung, Tagesabschluss, Statistik, Monatsbericht, Besetzungs-Profil, Änderungsprotokoll, Einstellungen, Stempeluhr, Zeiterfassung, Stundenkonto, Abwesenheiten).
- **Kontakte** — Datensatz-Treffer (nur canViewContacts) → Kontakt-Detail oder /kontakte.
- **Artikel** — Aktive Produkte (nur canViewInventory) → Warenwirtschaft.
- **Mitarbeiter** — Nur Admin → Personalakte-Detail (personalDetailPath).

**Aktionen (5)**

- Suchfeld eingeben
- Treffer antippen → navigate (go/push)
- ↑/↓ navigieren, ↵ öffnen, Esc schließen
- 'Suche leeren'-Button
- 'Schließen'/'Zurück'-Button

**Versteckt / gegatet (8)**

- ⨯ Kontakt-Gruppe nur bei canViewContacts
- ⨯ Artikel-Gruppe nur bei canViewInventory
- ⨯ Mitarbeiter-Gruppe nur bei isAdmin
- ⨯ Bereiche per RoutePermissions.isLocationAllowed gefiltert
- ⨯ je Gruppe auf 8 Treffer gedeckelt ('+N weitere – Suche verfeinern')
- ⨯ Tastatur-Hinweiszeile nur breit (≥600)
- ⨯ leere Anfrage zeigt nur Bereiche-Sprungbrett
- ⨯ 'Keine Treffer für ...'-Zustand

> Responsive: breit = zentrierte ⌘K-Karte, schmal = Vollbild. Fuzzy-Ranking + Highlight. Screenreader-Announcements.

### Hell/Dunkel-Schnellschalter (ThemeModeButton) · `widget`

**Route:** `— (App-Leiste / Navigations-Rail / Einstellungs-Hub AppBar)`  
**Zugriff:** alle

**Unterbereiche / Tabs (2)**

- **Tap-Toggle** — Tippen wechselt sofort hell↔dunkel (bei 'System' bezogen auf Plattform-Helligkeit).
- **Optionen-Menü (showThemeModeMenu)** — Langdruck/Rechtsklick öffnet PopupMenu System · Hell · Dunkel mit Häkchen am aktiven Modus.

**Aktionen (3)**

- Tap → _quickToggle
- Langdruck / Rechtsklick → showThemeModeMenu
- Menüpunkt System/Hell/Dunkel wählen

**Sheets & Dialoge (1)**

- showThemeModeMenu (PopupMenu am Widget verankert)

> Icon spiegelt aktuellen Modus (brightness_auto/light_mode/dark_mode outline). Tooltip beschreibt Tap+Langdruck. 48px-Trefferzone.

### Konto-Löschen-Dialog (AccountDeleteConfirmDialog) · `dialog`

**Route:** `— (showDialog aus Profil bzw. Personalakte-Gefahrenzone)`  
**Zugriff:** Self-Löschung (alle) oder Admin-Fremdlöschung

**Unterbereiche / Tabs (2)**

- **Bestätigungstext** — Titel 'Konto endgültig löschen' (überschreibbar), Warnmeldung; irreversibel.
- **Passwort-Reauth-Feld** — Nur bei Passwort-Konten (needsPassword): 'Passwort zur Bestätigung', Fehlertext 'Bitte Passwort eingeben.'

**Aktionen (3)**

- TextButton 'Abbrechen' (confirmed=false)
- FilledButton 'Endgültig löschen' (rot) → _submit
- onSubmitted im Passwortfeld

**Versteckt / gegatet (1)**

- ⨯ Passwortfeld nur bei needsPassword (Passwort-Konten); Google-/Demo-Konten bestätigen nur

> Gibt AccountDeleteConfirmResult (confirmed + optional password) zurück; Aufrufer reicht Passwort an AuthProvider.reauthenticate. Wiederverwendet für Self + Admin-Fremdlöschung.

---

<a id="cluster-13"></a>

## 13. Kiosk / Arbeitsmodus (Vollbild-Tablet)

*14 Bereiche.*

### Arbeitsmodus / Laden-Tablet (Kiosk-Board) · `kiosk`

**Route:** `— (KioskScreen, ersetzt die Shell wenn AppConfig.kioskModeEnabled)`  
**Zugriff:** Geräte-Konto (niedrig-privilegiert, ohne canManageShifts); Vollbild-Board ist kundensichtbar; personenbezogene Kacheln erst nach Name+PIN-Anmeldung  
**Feature-Flag:** AppConfig.kioskModeEnabled (Kiosk-Build ersetzt ganze Shell)

**Unterbereiche / Tabs (3)**

- **Kopfzeile (_KioskTopBar)** — Ladenname + Datum (EEEE, d. MMMM) + Live-Uhr (HH:mm, Timer 1s). Rechts: entweder FilledButton 'Anmelden' (Icons.login) wenn niemand angemeldet, oder _ActiveEmployeeChip mit 'Angemeldet' + Name + Countdown 'Abmeldung in Ns' + FilledButton.tonalIcon 'Fertig' (Logout). Optional IconButton 'Laden wechseln' (edit_location_alt) nur wenn kein APP_KIOSK_SITE_ID-Override und >1 Standort.
- **Offline-Banner (AppOfflineBanner)** — Erscheint nur bei ConnectivityStatusProvider.isOffline: 'Offline – Stempeln und Kassenzählung sind gerade nicht möglich. Bitte Verbindung prüfen.'
- **Board (_KioskBoard)** — Responsive Wrap-Kachelgrid, 1/2/3 Spalten je nach Breite (>=720 zwei, >=1100 drei). 9 Kacheln in fester Registry-Reihenfolge.

**Aktionen (3)**

- Anmelden (öffnet _KioskLoginSheet)
- Fertig / Abmelden (Logout via KioskController.logout)
- Laden wechseln (öffnet _KioskSitePicker-Sheet, bedingt)

**Sheets & Dialoge (4)**

- _KioskLoginSheet (Namensliste + PIN-Pad)
- _KioskSitePicker (Laden wählen, als Bottom-Sheet beim Wechseln)
- showCashCountSheet (Kasse zählen)
- showStoreTaskEditorSheet (Aufgabe anlegen)

**Versteckt / gegatet (4)**

- ⨯ _ActiveEmployeeChip inkl. Auto-Logout-Countdown nur bei aktiver Session (KioskController.employee != null)
- ⨯ IconButton 'Laden wechseln' nur wenn AppConfig.kioskSiteId leer UND sites.length > 1
- ⨯ Offline-Banner nur bei isOffline (im Demo-/Offline-Modus optimistisch online → eingeklappt)
- ⨯ Anmelde-Roster kommt im Echtbetrieb aus kioskRoster-Projektion (getKioskRoster); Fallback auf TeamProvider.members nur Demo/Übergang

> Vollbild ersetzt komplette App-Shell. Always-On: Wakelock + immersiveSticky (best-effort, No-op auf Web/Desktop). Auto-Logout nach 90s Inaktivität (KioskController.inactivityTimeout).

### Laden wählen (_KioskSitePicker) · `gate`

**Route:** `— (Vollbild-Erstwahl oder Bottom-Sheet beim Wechsel)`  
**Zugriff:** Geräte-Ersteinrichtung (jeder am Tablet)

**Aktionen (1)**

- Laden aus Liste antippen (ListTile onTap → KioskDeviceStore.setSiteId)

**Versteckt / gegatet (2)**

- ⨯ Nur sichtbar wenn kein Laden auflösbar: kein APP_KIOSK_SITE_ID-Override, keine lokale Gerätewahl, und nicht genau EIN Standort
- ⨯ Leerer Zustand '_KioskEmpty': 'Keine Standorte hinterlegt.'

> Titel 'Laden wählen' (storefront). Ordnet Tablet einem Laden zu (pro Gerät, SharedPreferences). Zeigt Name + Adresse je Standort. ListTile deaktiviert wenn s.id == null.

### Zeiterfassung-Kachel (_ClockTile) · `widget`

**Route:** `—`  
**Zugriff:** Stempeln nur nach Anmeldung (controller.employee != null); Server-Callable kioskClockPunch mit Session-sid

**Aktionen (3)**

- Kommen (FilledButton.icon, Icons.login) → clockIn
- Gehen (FilledButton.tonalIcon, Icons.logout) → clockOut
- Erneut versuchen (OutlinedButton, bei Fehler)

**Versteckt / gegatet (4)**

- ⨯ Ohne Anmeldung leerer Zustand: 'Zum Stempeln oben „Anmelden“ antippen.'
- ⨯ Fehler-/Offline-Zustand: 'Keine Verbindung — Stempel-Status/Stempeln …' + 'Erneut versuchen'
- ⨯ Ladespinner während Status geladen wird
- ⨯ Status-Text '{Name}: eingestempelt' / 'nicht eingestempelt'

> Titel 'Zeiterfassung' (schedule). Buttons disabled bei _busy. Offline-Callable-Aufrufe werfen deutsche Meldung statt zu hängen; bewusst keine Offline-Queue.

### Im Dienst-Kachel (_PresenceTile) · `widget`

**Route:** `—`  
**Zugriff:** Liest server-gepflegte kioskPresence-Projektion (Gerätekonto liest nie clockEntries)

**Versteckt / gegatet (3)**

- ⨯ Komplett unsichtbar (SizedBox.shrink) wenn orgId == null ODER AppConfig.disableAuthentication (Demo-Modus)
- ⨯ Badge mit Anzahl nur wenn Einträge vorhanden
- ⨯ Leerer Zustand: 'Gerade ist niemand eingestempelt.'

> Titel 'Im Dienst' (people_alt). StreamBuilder auf watchKioskPresence. Zeigt bewusst NUR Vornamen (e.name.split(' ').first) + 'seit HH:mm' — kundensichtbares Board.

### Tauschanfragen-Kachel (_SwapTile) · `widget`

**Route:** `—`  
**Zugriff:** Nur für angemeldeten Session-Mitarbeiter (personenbezogen); KioskSwapService session-gebunden (sid), nicht ScheduleProvider

**Aktionen (3)**

- Annehmen (FilledButton) → respond accept=true
- Ablehnen (OutlinedButton) → respond accept=false
- Erneut versuchen (OutlinedButton, bei Fehler)

**Versteckt / gegatet (6)**

- ⨯ Ohne Anmeldung: 'Zum Ansehen deiner Tauschanfragen oben „Anmelden“ antippen.'
- ⨯ Fehler-/Offline-Zustand + 'Erneut versuchen'
- ⨯ Ladespinner
- ⨯ Leerer Zustand: 'Keine offenen Tauschanfragen für dich.'
- ⨯ Badge = Anzahl offener Anfragen
- ⨯ Optionale Notiz-Zeile je Anfrage nur wenn request.note gesetzt

> Titel 'Tauschanfragen' (swap_horiz). Zeigt max. 6 Anfragen (_SwapRow): 'Von {Name}', kind.label, 'Abgegeben: {Schicht}'. Nur Kollegen-Schritt (annehmen/ablehnen); Chef bestätigt in der App. Snackbars bei Erfolg/Fehler.

### Kasse zählen-Kachel (_CashCountTile) · `widget`

**Route:** `—`  
**Zugriff:** Alle Mitarbeitenden nach Anmeldung (E2); blinde Zählung ohne Soll; Echtbetrieb via kioskSaveCashCount-Callable (server-authoritativ)

**Aktionen (1)**

- Kasse zählen (FilledButton.icon, calculate_outlined) → öffnet showCashCountSheet

**Sheets & Dialoge (1)**

- showCashCountSheet (blinde Zählung, optional Fremdgeld-Sektion)

**Versteckt / gegatet (4)**

- ⨯ Ohne Anmeldung: 'Zum Zählen oben „Anmelden“ antippen.'
- ⨯ Fremdgeld-Sektion im Sheet nur wenn site.activeThirdPartyCashTypes gesetzt (thirdPartyInTill)
- ⨯ Fehler-Snackbar: 'Zählung braucht Internet — bitte später erneut.'
- ⨯ Dev-/Local-Modus schreibt Direkt-Write (CashCount.sourceKiosk), sonst gehärtetes Callable

> Titel 'Kasse zählen' (point_of_sale). Blind ohne Soll/Differenz (Gerätekonto hat kein Beleg-Leserecht); Leitung prüft Differenz im Tagesabschluss. Button disabled bei _busy/kein siteId.

### Laden-To-Dos-Kachel (_StoreTasksTile) · `widget`

**Route:** `—`  
**Zugriff:** Abhaken nur nach Anmeldung (employee != null); Aufgabe anlegen nur bei StoreTaskProvider.canManage

**Aktionen (2)**

- Aufgabe anlegen (IconButton +, nur canManage) → showStoreTaskEditorSheet
- Erledigt (FilledButton je Aufgabe) → markDoneForSite

**Sheets & Dialoge (1)**

- showStoreTaskEditorSheet (Neue/Bearbeiten Laden-Aufgabe)

**Versteckt / gegatet (5)**

- ⨯ '+ Aufgabe anlegen'-Trailing nur wenn provider.canManage (Leiter/Admin)
- ⨯ 'Erledigt'-Button je Zeile nur wenn employee != null (angemeldet)
- ⨯ Badge = Anzahl offener Aufgaben (warning-Farbe)
- ⨯ Leerer Zustand: 'Keine offenen Aufgaben. 👍'
- ⨯ Überfällige Aufgaben mit error_outline-Icon (warning-Farbe)

> Titel 'Laden-To-Dos' (checklist_rtl). Zeigt max. 6 offene Aufgaben für den Laden (_StoreTaskRow: Titel + optional Beschreibung).

### Kühlschrank nachfüllen-Kachel (_FridgeTile) · `widget`

**Route:** `—`  
**Zugriff:** Nachfüllen-Button nur nach Anmeldung (employee != null)

**Aktionen (1)**

- Nachgefüllt (FilledButton.tonal je Artikel) → inventory.refillFridge

**Versteckt / gegatet (4)**

- ⨯ 'Nachgefüllt'-Button nur wenn angemeldet
- ⨯ Badge = Anzahl Fehlmengen (info-Farbe)
- ⨯ Leerer Zustand: 'Kühlschrank ist gut gefüllt.'
- ⨯ Severity-Farbe je Zeile: empty=error, warehouseLow=warning, refill=info

> Titel 'Kühlschrank nachfüllen' (kitchen_outlined). Max. 6 Fehlmengen (_FridgeRow: Name, 'Kühlschrank x/y · Lager z').

### Läuft bald ab (MHD)-Kachel (_ExpiryTile) · `widget`

**Route:** `—`  
**Zugriff:** Erledigt-Menü nur nach Anmeldung (employee != null)

**Aktionen (1)**

- Erledigt (PopupMenuButton, check_circle) mit Optionen 'Abverkauft' (soldOut) / 'Entsorgt' (discarded) → resolveBatch

**Versteckt / gegatet (4)**

- ⨯ PopupMenu 'Erledigt' je Zeile nur wenn angemeldet
- ⨯ Badge = Anzahl Warnungen; error-Farbe wenn abgelaufene dabei, sonst warning
- ⨯ Leerer Zustand: 'Nichts läuft in den nächsten Tagen ab.'
- ⨯ Zustands-Text je Batch: 'seit N Tagen abgelaufen' / 'läuft heute/morgen ab' / 'in N Tagen'

> Titel 'Läuft bald ab' (timelapse). Max. 6 Warnungen (_ExpiryRow: Produktname, 'MHD dd.mm.yyyy · …'). Severity-Farben expired/critical/soon.

### Kundenwünsche-Kachel (_WishesTile) · `widget`

**Route:** `—`  
**Zugriff:** Nur-Lesen, kundensichtbar (keine Anmeldung nötig)

**Versteckt / gegatet (5)**

- ⨯ Demo-Modus (AppConfig.disableAuthentication) zeigt 2 Demo-Wünsche (Spiegel Ausgabe 26, Marlboro Gold) statt Live-Stream
- ⨯ orgId == null → leere Liste
- ⨯ Live: StreamBuilder watchCustomerWishes, gefiltert auf offene Wünsche des Ladens
- ⨯ Badge = Anzahl offener Wünsche
- ⨯ Leerer Zustand: 'Keine offenen Wünsche.'

> Titel 'Kundenwünsche' (card_giftcard). Max. 6 (ListTile: wishText, '{Kategorie} · {Menge}× · {Referenzcode}').

### Hinweise-Kachel (_HintsTile) · `widget`

**Route:** `—`  
**Zugriff:** Nur-Lesen (keine Anmeldung nötig)

**Versteckt / gegatet (3)**

- ⨯ Badge = Anzahl Niedrigbestand-Artikel (warning-Farbe)
- ⨯ Leerer Zustand: 'Keine Hinweise.'
- ⨯ Nur Artikel mit isActive && needsReorder

> Titel 'Hinweise' (notifications_active). 'Artikel mit niedrigem Bestand (nachbestellen):' + max. 6 (Name, 'Bestand x'). trending_down-Icon.

### Anmelde-Sheet (_KioskLoginSheet) · `modal-sheet`

**Route:** `— (Sheet/imperativ)`  
**Zugriff:** Jeder am Tablet; PIN-Prüfung server-geprüft (kioskBeginSession) bzw. Dev-lokal

**Unterbereiche / Tabs (2)**

- **Schritt 1: Namensliste** — 'Wer bist du?' — ListView aus Roster (CircleAvatar mit Initialen + Name + chevron). Tippen wählt Mitarbeiter.
- **Schritt 2: PIN-Pad (_PinPad)** — Name + 'PIN eingeben' + wachsende Punkt-Anzeige (4–8) + _NumPad (Ziffern, Backspace, OK/check). Zurück-Pfeil zur Namensliste.

**Aktionen (5)**

- Mitarbeiter wählen (ListTile onTap)
- Ziffer eingeben (_NumPad-Tasten)
- Backspace (backspace_outlined)
- OK/Bestätigen (check, aktiv ab 4 Ziffern) → beginSession
- Zurück (arrow_back) zur Namensliste

**Versteckt / gegatet (4)**

- ⨯ Leerer Zustand: 'Keine Mitarbeiter hinterlegt.'
- ⨯ Fehlermeldung ersetzt 'PIN eingeben' (z. B. 'Falsche PIN, bitte erneut.', 'Zu viele Fehlversuche…', 'Für dich ist noch keine PIN hinterlegt.')
- ⨯ Demo-Hinweis 'Demo: Standard-PIN 1234' NUR bei AppConfig.disableAuthentication
- ⨯ OK-Taste disabled (null) unter 4 Ziffern oder während _checking

> PIN 4–8 Ziffern (Spiegel KIOSK_PIN_REGEX). Kein Auto-Submit — explizite OK-Taste. Bei Erfolg pop + KioskController.login mit sid.

### Kiosk-PIN festlegen-Sheet (showKioskPinSetupSheet) · `modal-sheet`

**Route:** `— (Sheet/imperativ, vom eigenen Handy aufgerufen)`  
**Zugriff:** Angemeldeter Nutzer setzt eigene PIN (nicht am Kiosk selbst, sondern in der normalen App)

**Aktionen (3)**

- Neue PIN eingeben (TextField, obscure, digitsOnly, max 8)
- PIN wiederholen (TextField)
- PIN speichern (FilledButton.icon, check) → KioskPinService.setPin

**Versteckt / gegatet (2)**

- ⨯ Fehlermeldungen: 'Die PIN muss aus 4 bis 8 Ziffern bestehen.', 'Die PINs stimmen nicht überein.', 'Kein angemeldeter Nutzer.', 'Speichern fehlgeschlagen: …'
- ⨯ Spinner im Button während _saving

> Titel 'Kiosk-PIN festlegen'. Erklärung: 4-8-stellige PIN fürs Laden-Tablet. Offline lokal (KioskPinStore), echt via setKioskPin-Callable. Erfolgs-Snackbar 'Kiosk-PIN gespeichert.'

### Laden-Aufgabe-Editor-Sheet (showStoreTaskEditorSheet) · `modal-sheet`

**Route:** `— (Sheet/imperativ)`  
**Zugriff:** Leiter (StoreTaskProvider.canManage; Aufruf über '+' in Laden-To-Dos-Kachel)

**Aktionen (6)**

- Titel eingeben (TextField)
- Beschreibung eingeben (TextField, optional, mehrzeilig)
- Priorität wählen (SegmentedButton: Niedrig/Mittel/Hoch)
- Fälligkeitsdatum wählen (ListTile → showDatePicker) + Löschen (clear-Icon)
- Für alle Läden umschalten (SwitchListTile) — Broadcast
- Speichern/Anlegen (FilledButton.icon, check) → saveStoreTask

**Sheets & Dialoge (1)**

- showDatePicker (Fälligkeitsdatum)

**Versteckt / gegatet (5)**

- ⨯ Titel 'Laden-Aufgabe bearbeiten' vs. 'Neue Laden-Aufgabe' je nach existing
- ⨯ SwitchListTile 'Für alle Läden' nur wenn widget.siteId != null; Subtitle 'Erscheint in jedem Laden' vs. 'Nur für {Laden}'
- ⨯ clear-Icon am Datum nur wenn Datum gesetzt
- ⨯ Fehler-Snackbars: 'Bitte einen Titel eingeben.', 'Speichern fehlgeschlagen: …'
- ⨯ Spinner im Button während _saving

> Button-Label 'Anlegen' (neu) vs. 'Speichern' (Bearbeiten). Ohne siteId ist Aufgabe org-weit; mit Schalter 'für alle Läden' Broadcast.

---

<a id="cluster-14"></a>

## 14. Öffentliche Web-Routen + Gate-Screens + Signage

*12 Bereiche.*

### Wunsch abgeben (öffentlich) · `public`

**Route:** `/wunsch`  
**Zugriff:** login-frei (anonymer Firebase-Auth-Schreibpfad); keine Rolle

**Unterbereiche / Tabs (2)**

- **Formular-Ansicht** — 3 nummerierte Sektionen: '1 Worum geht es?' (Laden-ChipRow nur bei >1 Laden, Kategorie-ChipRow: Zeitschrift/Zigaretten/Tabak/Sonstiges, Wunsch-Textfeld Pflicht), '2 Details' (Mengen-Stepper 1–999, Wunschtermin-DatePicker optional), '3 Kontakt (optional)' (Name, Telefon/E-Mail, Datenschutz-Hinweis)
- **Erfolgs-Ansicht** — PublicSuccessView mit Referenznummer ('DEINE WUNSCH-NUMMER'), 'Nummer kopieren', 'Weiteren Wunsch abgeben'; per AnimatedSwitcher statt Formular

**Aktionen (9)**

- Wunsch absenden (PublicSubmitButton)
- Menge − / + (Stepper)
- Wunschtermin hinzufügen (DatePicker)
- Termin entfernen (clear)
- Nummer kopieren (Clipboard + SnackBar 'Nummer kopiert')
- Weiteren Wunsch abgeben (Reset)
- Hell/Dunkel-Umschalter (trailingAction, nur wenn onSelectThemeMode!=null)
- Impressum (Footer)
- Datenschutz (Footer)

**Sheets & Dialoge (3)**

- showDatePicker 'Wunschtermin wählen'
- Navigator.push PublicLegalScreen (Impressum)
- Navigator.push PublicLegalScreen (Datenschutz)

**Versteckt / gegatet (6)**

- ⨯ Laden-ChipRow nur sichtbar wenn mehr als 1 Laden konfiguriert (sonst nur Kategorie)
- ⨯ singleStoreName-Badge in Marken-Schiene nur bei genau 1 Laden
- ⨯ Theme-Umschalter nur wenn onSelectThemeMode-Callback gesetzt
- ⨯ Fehlerbanner nur bei Fehler; im Debug-Build zusätzlich '[Debug] <cause>'-Text
- ⨯ Demo-Erfolgspfad bei APP_DISABLE_AUTH ohne Firebase (generiert Fake-Referenzcode)
- ⨯ ehrliche 'nicht mit Backend verbunden'-Meldung wenn Firebase.apps leer und nicht disableAuth

> Eigene isolierte MaterialApp (PublicWishApp), kein go_router, kein authProvider.init. Signal-Teal PublicPageScaffold (breit: Marken-Schiene + Formular ab 880px; schmal: Marken-Band oben). Anonymes signInAnonymously, Web: Persistence.SESSION.

### Rückmeldung / Feedback (öffentlich) · `public`

**Route:** `/feedback (auch /beschwerde)`  
**Zugriff:** login-frei (anonymer Firebase-Auth-Schreibpfad); Eingang jedoch MANAGER-ONLY (Rules), keine Rolle beim Absenden

**Unterbereiche / Tabs (2)**

- **Formular-Ansicht** — '1 Worum geht es?' (Laden-ChipRow nur bei >1 Laden, Art-ChipRow: Beschwerde/Verbesserungsvorschlag/Lob, Nachricht-Textfeld Pflicht mit typabhängigem Hint), '2 Details' (Sterne-Bewertung 1–5 optional, Vorfallsdatum optional), '3 Kontakt (optional)' (Name, Telefon/E-Mail)
- **Erfolgs-Ansicht** — PublicSuccessView 'Danke für deine Rückmeldung!', 'Deine Vorgangs-Nummer', kopieren, 'Weitere Rückmeldung abgeben'

**Aktionen (9)**

- Absenden (PublicSubmitButton, busy: 'Wird gesendet …')
- Sterne 1–5 tippen (erneut = löschen)
- Wann war das? (DatePicker, Vergangenheit)
- Datum entfernen
- Nummer kopieren
- Weitere Rückmeldung abgeben
- Hell/Dunkel-Umschalter
- Impressum (Footer)
- Datenschutz (Footer)

**Sheets & Dialoge (3)**

- showDatePicker 'Wann war das?'
- Navigator.push PublicLegalScreen (Impressum)
- Navigator.push PublicLegalScreen (Datenschutz)

**Versteckt / gegatet (5)**

- ⨯ Laden-ChipRow nur bei >1 Laden
- ⨯ Theme-Umschalter nur wenn Callback gesetzt
- ⨯ Fehlerbanner nur bei Fehler (Debug: '[Debug]'-Zusatz)
- ⨯ Demo-Erfolgspfad bei APP_DISABLE_AUTH
- ⨯ 'nicht mit Backend verbunden'-Meldung ohne Firebase

> Isolierte PublicFeedbackApp, teilt public_ui-Design mit Wunsch. Anders als Wünsche: Eingang ist Manager-only (per firestore.rules), nicht im UI sichtbar. Nachricht-Hint wechselt je Art (Beschwerde/Vorschlag/Lob).

### Impressum (öffentlich, statisch) · `public`

**Route:** `/impressum`  
**Zugriff:** login-frei, rein statisch (kein Firebase)

**Unterbereiche / Tabs (6)**

- **Angaben gemäß § 5 DDG** — Betreiber-Adressblock (Name, ggf. Vertretung, Straße, PLZ/Ort), optional Register
- **Kontakt** — Telefon, E-Mail
- **Umsatzsteuer-ID** — nur wenn info.vatId gesetzt (§ 27a UStG)
- **Verantwortlich § 18 Abs. 2 MStV** — nur wenn APP_LEGAL_CONTENT_RESPONSIBLE gesetzt (Opt-in, journalistisch-redaktionell)
- **Verbraucherstreitbeilegung** — statischer Absatz § 36 VSBG
- **Haftung für Inhalte** — statischer Absatz § 7 Abs. 1 DDG

**Aktionen (3)**

- Zurück (nur wenn Navigator.canPop)
- Hell/Dunkel-Umschalter (nur wenn Callback)
- Datenschutz (Cross-Link, pushReplacement)

**Versteckt / gegatet (8)**

- ⨯ 'noch nicht vollständig hinterlegt'-Warnbanner (PublicLegalSetupNotice) solange !info.isComplete
- ⨯ Umsatzsteuer-ID-Sektion nur bei gesetzter vatId
- ⨯ § 18 MStV-Sektion nur bei content-responsible Opt-in
- ⨯ Register-Zeile nur wenn registerEntry gesetzt
- ⨯ Platzhalter-Klammern '[Name des Betreibers …]' bei leeren Pflichtfeldern
- ⨯ 'Stand: <lastUpdated>' nur wenn gesetzt
- ⨯ Zurück-Pfeil nur wenn gestapelt (aus Formular), nicht als eigene Route
- ⨯ Impressum-Link im Cross-Footer ausgeblendet (ist selbst Impressum)

> PublicLegalScreen, page=impressum. Erreichbar als eigene Route (PublicLegalApp) UND per Footer-Push aus Wunsch/Feedback. Inhalt aus LegalInfo/APP_LEGAL_*. maxWidth 760.

### Datenschutzerklärung (öffentlich, statisch) · `public`

**Route:** `/datenschutz`  
**Zugriff:** login-frei, rein statisch (kein Firebase)

**Unterbereiche / Tabs (9)**

- **1. Verantwortlicher** — Adressblock + E-Mail + ggf. Telefon, kein DSB
- **2. Geltungsbereich** — Wunsch- + Feedback-Formular
- **3. Welche Daten wir verarbeiten** — Von dir angegebene Daten, Automatisch verarbeitete Daten (anonyme Auth, IP beim Hoster), Schutz vor Missbrauch (App Check/reCAPTCHA)
- **4. Zwecke und Rechtsgrundlagen** — Art. 6 lit. b/f/a DSGVO Bullets
- **5. Empfänger und Auftragsverarbeiter** — Google/Firebase, EU-Rechenzentrum, USA-Übermittlung SCC
- **6. Speicherdauer** — keine feste Löschfrist
- **7. Deine Rechte** — Art. 15–21, 7(3) DSGVO Bullets
- **8. Beschwerderecht Aufsichtsbehörde** — ULD Schleswig-Holstein, Kiel
- **9. Keine Pflicht zur Bereitstellung / keine automatisierte Entscheidung** — Art. 22 DSGVO

**Aktionen (3)**

- Zurück (nur wenn canPop)
- Hell/Dunkel-Umschalter (nur wenn Callback)
- Impressum (Cross-Link, pushReplacement)

**Versteckt / gegatet (4)**

- ⨯ Setup-Warnbanner solange !info.isComplete
- ⨯ E-Mail/Telefon-Platzhalter bei leeren Feldern
- ⨯ Datenschutz-Link im Cross-Footer ausgeblendet (ist selbst Datenschutz)
- ⨯ Stand-Zeile nur wenn lastUpdated gesetzt

> PublicLegalScreen page=datenschutz. Gleiche Statik-Basis wie Impressum. Cross-Link via pushReplacement (keine Rechtsseiten-Kette).

### Anzeige-Player / Digital Signage (öffentlich) · `public`

**Route:** `/anzeige/<token> (auch /anzeige ohne Code)`  
**Zugriff:** login-frei, liest publicDisplays/{token} (get:true/list:false)

**Unterbereiche / Tabs (3)**

- **Vollbild-Player** — Werbebild-Schleife (schwarzer Hintergrund), Standzeit je Bild, Übergänge Fade/Slide/Zoom/None/KenBurns, Fit contain/cover; Live-Stream aus Firestore, aktualisiert sich selbst
- **Pairing-Ansicht** — 'Display koppeln': Eingabe Anzeige-Code + 'Werbung starten'; erscheint nur ohne Token in URL und ohne gemerkten Token
- **Hinweis-/Fehlerschirme** — 'Anzeige wird gestartet …'/geladen (Loader), 'Nicht verbunden', 'Display nicht gefunden', 'Anzeige nicht verfügbar', 'Diese Anzeige ist derzeit pausiert.', 'Es ist noch keine Werbung hinterlegt.', 'Bild nicht ladbar'

**Aktionen (3)**

- Anzeige-Code eingeben + 'Werbung starten' (Pairing)
- (automatisch) Slide-Wechsel per Timer
- (automatisch) Token merken in localStorage + Auto-Start bei Neustart

**Versteckt / gegatet (6)**

- ⨯ Pairing-Seite nur wenn kein Token in URL UND kein gemerkter Token
- ⨯ Loader während gemerkter Token geladen wird (_resolving)
- ⨯ 'Nicht verbunden' wenn Firebase fehlt und nicht disableAuth
- ⨯ Demo-Stream (LocalDemoOperationsData) nur bei APP_DISABLE_AUTH
- ⨯ 'pausiert' vs 'noch keine Werbung' abhängig von isActive/leerer Playlist
- ⨯ WakelockPlus hält Bildschirm wach (best-effort, Web Screen Wake Lock)

> PublicDisplayScreen, StatefulWidget. Token aus URL wird gespeichert (SignageTokenStore). Kein AppBar, reiner Vollbild-Player für Store-Fernseher. KenBurns zoomt langsam.

### Anmeldung (Login) V1 · `gate`

**Route:** `/anmelden`  
**Zugriff:** unauthentifiziert (Gate: !isAuthenticated)  
**Feature-Flag:** RedesignFlags V1 (aktiv wenn NICHT redesign_v2)

**Unterbereiche / Tabs (4)**

- **Intro-Panel** — Marken-Gradient, Logo, Feature-Items Zeiterfassung/Schichtplanung/Auswertungen (links bzw. gestapelt oben)
- **Tab Login** — E-Mail + Passwort-Formular ('Mit E-Mail anmelden')
- **Tab Einladung** — Invite-Aktivierung: E-Mail aus Einladung, neues Passwort, bestätigen ('Einladung aktivieren')
- **Demo-Modus-Sektion** — nur bei authDisabled: 'Lokale Demo-Profile' Liste + Email-Login 'Mit Demo-Account anmelden'

**Aktionen (6)**

- Mit Google anmelden (nur wenn !authDisabled)
- Mit E-Mail anmelden (Login-Tab)
- Einladung aktivieren (Einladung-Tab)
- Als <Rolle> anmelden (je Demo-Profil-Kachel, nur authDisabled)
- Mit Demo-Account anmelden (authDisabled Email-Form)
- Fehlerbanner schließen (Icons.close)

**Versteckt / gegatet (6)**

- ⨯ TabBar Login/Einladung + Google-Button nur wenn !authDisabled
- ⨯ Demo-Profile-Sektion + Demo-Email-Form nur wenn authDisabled (APP_DISABLE_AUTH)
- ⨯ Badge-Text wechselt 'Demo-Zugang' vs 'Sicherer Zugang'
- ⨯ Fehlerbanner nur bei auth.errorMessage
- ⨯ Buttons disabled während auth.busy (Loader-Spinner)
- ⨯ Layout wechselt gestapelt/nebeneinander bei <760px

> AuthScreen. Enthält im selben File auch FirebaseSetupScreen und AccessBlockedScreen (siehe eigene Areas). 2-Tab TabController.

### Anmeldung (Login) V2 · `gate`

**Route:** `/anmelden`  
**Zugriff:** unauthentifiziert (Gate: !isAuthenticated)  
**Feature-Flag:** RedesignFlags V2 (redesign_v2, Default)

**Unterbereiche / Tabs (5)**

- **Intro-Panel V2** — Gradient-Panel, Pill 'Digitale Betriebsorganisation', Feature-Items Zeit & Schicht / Warenwirtschaft / Personal & Auswertungen (nur wide ≥760)
- **Mobile-Body 'Formular zuerst'** — kompakter Marken-Header (Logo + Tagline) + Karte, Google-Button unter Formular (<760)
- **Segment Login** — AppSegmented, E-Mail + Passwort mit Sichtbarkeits-Toggle, Autofill-Hints
- **Segment Einladung** — E-Mail/Neues Passwort/bestätigen mit je Sichtbarkeits-Toggle
- **Demo-Modus-Sektion V2** — nur authDisabled: 'Lokale Demo-Profile' + Demo-Email-Form (Autofill aus)

**Aktionen (7)**

- Mit Google anmelden (!authDisabled)
- Mit E-Mail anmelden / Mit Demo-Account anmelden
- Einladung aktivieren
- Als <Rolle> anmelden (Demo-Kachel)
- Passwort anzeigen/verbergen (suffixIcon)
- Fehlerbanner schließen
- Segment umschalten Login/Einladung

**Versteckt / gegatet (7)**

- ⨯ Segmented + Google + 'oder'-Trenner nur wenn !authDisabled
- ⨯ Google-Button (mobil) nur auf Login-Segment
- ⨯ Demo-Sektion nur wenn authDisabled
- ⨯ Badge 'Demo-Zugang'/'Sicherer Zugang'
- ⨯ Fehlerbanner (AppStatusBanner) nur bei errorMessage
- ⨯ enableCredentialAutofill=false im Demo-Modus (Wegwerf-Zugangsdaten nicht speichern)
- ⨯ wide/mobile-Layout-Wechsel bei 760px

> AuthScreenV2 (lib/ui-Komponenten). Funktion identisch zu V1. Enthält auch FirebaseSetupScreenV2 und AccessBlockedScreenV2.

### Firebase-Setup / Anmeldung nicht verfügbar (Gate) · `gate`

**Route:** `/einrichtung`  
**Zugriff:** Gate: !firebaseConfigured  
**Feature-Flag:** V1 FirebaseSetupScreen / V2 FirebaseSetupScreenV2 (RedesignFlags)

**Versteckt / gegatet (1)**

- ⨯ V1 vs V2 je RedesignFlags

> Reiner Hinweis-Screen 'Anmeldung derzeit nicht verfuegbar' + Logo. Keine Aktionen. V2 zusätzlich Gradient-Hintergrund.

### Zugriff gesperrt / Konto deaktiviert (Gate) · `gate`

**Route:** `/gesperrt`  
**Zugriff:** Gate: profile vorhanden && !isActive  
**Feature-Flag:** V1 AccessBlockedScreen / V2 AccessBlockedScreenV2

**Aktionen (1)**

- Abmelden (AuthProvider.signOut)

**Versteckt / gegatet (1)**

- ⨯ V1 vs V2 je RedesignFlags

> 'Konto deaktiviert', Icon lock_person, einzige Aktion Abmelden.

### Update erforderlich / Force-Update (Gate) · `gate`

**Route:** `/aktualisierung`  
**Zugriff:** Gate: requiresUpdate (Server-Mindest-Build > aktueller Build)

**Versteckt / gegatet (2)**

- ⨯ optionale message überschreibt Default-Text
- ⨯ Zeile 'Installiert: Build X · benötigt: Build Y'

> ForceUpdateScreen. Bewusst OHNE Abmelden-/Weiter-Aktion (zu alter Client darf keine Schreibpfade erreichen). Icon system_update.

### Splash / Start-Loader (Gate) · `gate`

**Route:** `/start`  
**Zugriff:** Gate: !initialized || isResolvingProfile

**Aktionen (1)**

- optionale Aktion (actionLabel/onActionPressed) in StartupStatusCard

**Versteckt / gegatet (2)**

- ⨯ Loader (CircularProgressIndicator) nur wenn showLoader
- ⨯ Aktions-Button nur wenn actionLabel und onActionPressed gesetzt (Fehlerzustand)

> BootstrapFrame + StartupStatusCard (lib/widgets/bootstrap_frame.dart). Geteilt von AppBootstrap (vor Provider-Kette) und go_router /start. Logo + Titel/Meldung.

### Displays & Werbung / Signage-Verwaltung (admin) · `section-screen`

**Route:** `/werbung`  
**Zugriff:** admin-only (isAdmin; RoutePermissions + Defense-in-depth im Screen)  
**Feature-Flag:** APP_SIGNAGE_ENABLED (signageEnabled)

**Unterbereiche / Tabs (2)**

- **Tab Displays** — Liste der SignageDisplay-Karten (Name, Standort, Bildanzahl, Sekunden, Aktiv/Pausiert-Badge, Fernseh-Link); FAB 'Neues Display'
- **Tab Werbebilder** — GridView der AdMedia-Kacheln; FAB 'Bild hochladen'; Upload-Warnbanner wenn Cloud-Modus fehlt

**Aktionen (11)**

- FAB 'Neues Display' (Editor)
- FAB 'Bild hochladen' (FilePicker, nur wenn mediaUploadAvailable)
- Display-Karte antippen (Editor öffnen)
- Fernseh-Link kopieren (copy_outlined + SnackBar)
- Aktiv-Switch je Display (setDisplayActive)
- Werbebild-Overflow: Umbenennen / Löschen (PopupMenuButton)
- Editor: Löschen (AppBar delete_outline, nur bei bestehendem)
- Editor: Speichern
- Editor: Playlist-Bild entfernen (remove_circle)
- Editor: Bild aus Bibliothek hinzufügen (Tap-Kachel mit +)
- Editor: Playlist neu ordnen (ReorderableListView Drag)

**Sheets & Dialoge (5)**

- Navigator.push _DisplayEditorScreen (Vollbild-Editor)
- showDialog 'Bild umbenennen' (_promptText)
- showDialog 'Werbebild löschen?' (_confirm)
- showDialog 'Display löschen?' (_confirm)
- FilePicker.pickFiles (Bild-Upload)

**Versteckt / gegatet (7)**

- ⨯ Nicht-Admin: BreadcrumbAppBar + 'Dieser Bereich ist nur für Administratoren.' statt Inhalt
- ⨯ Upload-FAB disabled + Warnbanner 'Der Bild-Upload benötigt den Cloud-Modus' wenn !mediaUploadAvailable (Offline/Demo)
- ⨯ Editor Löschen-Button nur wenn !_isNew
- ⨯ Playlist-Bereich leer-Text 'Noch keine Bilder in der Playlist.'
- ⨯ Bibliothek leer-Text 'Noch keine Werbebilder hochgeladen'/'Alle Bilder sind bereits in der Playlist.'
- ⨯ Standort-Dropdown 'Kein Standort'-Option
- ⨯ gesamter Bereich hinter APP_SIGNAGE_ENABLED versteckt

> SignageScreen (Section-Route unter /laden bzw. parentLabel). Editor: Name, Standort optional, Anzeigedauer 3–60s Slider, Bild-Einpassung Füllen/Ganz zeigen (SegmentedButton), Animation-Dropdown, 'Display aktiv'-Switch, Playlist + Bibliothek. Player-URL via signagePlayerUrl (AppConfig.signagePlayerBaseUrl).

---

_Ende des Inventars._
