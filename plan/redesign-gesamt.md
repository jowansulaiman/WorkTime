# Gesamt-Redesign WorkTime — Mobile-First Masterplan (iOS/Android)

> Stand 2026-07-01. Ganzheitlicher UI/UX-Redesign-Plan über **alle sechs Haupt-Tabs** (Heute, Plan, Zeit, Anfragen, Kontakte, Laden) **plus Profil/Verwaltung** und **jeden Unterbereich**. Grundlage: eine 22-Agenten-Tiefenanalyse (7 Bereichs-Inventare mit Datei:Zeile-Belegen → 7 Bereichs-Redesigns, 7 Querschnitt-Entwürfe, 1 adversariale Vollständigkeits-Kritik gegen die 30 Anforderungen). Verbindliche Fachautorität: `claude-skills/architektur/03_ux-ui-design.md` (+ Frontend-Architektur, Mobile, Performance, Offline-Modus).
>
> **Dieser Plan konsolidiert und erweitert** die drei Vorgänger `plan/redesign-signal-teal.md` (Design-System V2), `plan/ui-aufraeumen-und-verteilen.md` (Struktur/God-Files/IA) und `plan/analyse-5-tabs-behebung.md` (Befunde je Tab). Er ersetzt sie nicht, sondern hängt die neuen, dort fehlenden Mobile-/Plattform-/Sicherheits-/Offline-Anforderungen ein (Abschnitt „Verhältnis zu bestehenden Plänen").

---

## 0. Auftrag & Geltungsbereich

**Auftrag:** Die gesamte Software modern, professionell und mobil-first (besonders iOS/Android) neu gestalten — jeder Bereich und jeder Unterbereich. Realisiert werden **30 explizite UX-Eigenschaften** (klare Bedienung, einheitliches/übersichtliches Design, Lesbarkeit, intuitive & native Navigation, Responsive, touch-/daumenfreundlich, kleine Bildschirme, schnelle Ladezeiten, Offline, Push-Hygiene, Performance, Ressourcenschonung, verständliche Fehler & Fehlervermeidung, Barrierefreiheit, Dark/Light, moderne Optik, Konsistenz, klare Struktur, Suche/Filter, wenige Schritte, angenehme Farben, sinnvolle Animationen, sichere Anmeldung inkl. Biometrie/2FA, Datenschutz, Vertrauens-Design).

**Im Geltungsbereich:** Optik, Layout, Informationsarchitektur, Navigation, Komponenten, Interaktion, Formular-/Fehler-/Lade-/Offline-UX, Barrierefreiheit, Dark/Light, Motion — über **alle 46+ Screens**. Zusätzlich als **eigenständige Feature-Pakete** (nicht rein optisch): sichere Anmeldung/Biometrie, kontextuelle Berechtigungen, Konnektivitäts-/Offline-Zustand.

**Außerhalb des Geltungsbereichs (unverändert):** Provider-Kette, Services, Models, Firestore-Schema/Rules, Cloud Functions, Compliance-Logik, die Zwei-Serialisierungs-Regel. Alle deutschen Texte bleiben Deutsch, Locale hart `de_DE`. Status-Farben kommen aus `Theme.of(context).appColors`, nie hartkodiert.

**Ausgangslage (verifiziert):**
- Das Signal-Teal-Design-System **V2 ist bereits Default-aktiv** (`redesign_v2` `defaultEnabled=true`); die Tokens (`AppSpacing/AppRadii/AppMotion/AppElevation/AppIconSizes/AppThemeColors`) und die Komponentenbibliothek `lib/ui/` existieren.
- **Aber:** nur ein Teil der Screens nutzt `lib/ui`; es existieren V1/V2-Doppel-Dashboards, ~14 duplizierte file-private Klon-Widgets, Riesen-Dateien (Schichtplan 6 155 Z, Personal 5 649 Z, Team 4 648 Z), Tabellen mit Horizontal-Scroll auf dem Handy, vergrabene Primäraktionen, uneinheitliche Suche/Filter und A11y-Lücken.
- **Fundament-Lücken, die der Plan zuerst schließt** (aus der Kritik, verifiziert am Code): `lib/ui` hat noch **kein** `AppErrorState` und **kein** `AppSearchField`; es gibt **keine** globale `SearchAnchor`; die Pakete `connectivity_plus`, `local_auth`, `permission_handler`, `url_launcher`, `file_picker` fehlen im `pubspec.yaml` (nur `firebase_auth` + `mobile_scanner` vorhanden); die Textskalierung ist app-weit bei **1,5** geklemmt (`kMaxTextScaleFactor`, `lib/core/accessibility.dart:20`).

### 0.1 Status, Infrastruktur & Architektur-Kopplungen (Abnahme-relevant)

- **Meilenstein-Status:** Das **Fundament (Phase 0)** ist zu großen Teilen **umgesetzt und verifiziert** (siehe [Kap. 0.3 Umsetzungsstand](#03-umsetzungsstand-phase-0--stand-2026-07-01)); die **Bereichs-Rollouts (Teil C)** stehen noch auf **offen/geplant**. Die Aufwands-Spalte (S/M/L/XL) ist eine Schätzung, kein Fortschritt.
- **Deploy / Infrastruktur:** Der Kern ist **reine Client-UI → kein `firestore:rules`/`indexes`/`functions`-Deploy nötig**. Ausnahmen (bewusst außerhalb der „nur Optik"-Leitplanke): **F2 Plattform-Fundament** (neue `pubspec`-Pakete + `Info.plist`/`AndroidManifest`-Einträge + Web-Fallbacks) und **2FA** (Kap. 9, nur *Ausblick*: Firebase-MFA braucht **Blaze** + Console-Aktivierung — siehe [[blaze-zielumgebung]]). Die globale Suche (F4) arbeitet **client-seitig** über bereits geladene Provider-Daten → **kein** neuer Composite-Index.
- **Provider-Kette (CLAUDE.md-Kopplung #4):** Der neue `ConnectivityStatusProvider` (Kap. 10) ist von Auth/Storage **unabhängig** und wird **früh** in der `main.dart`-Kette registriert (vor den Daten-Providern, nach `ThemeProvider`), damit Shell **und** Bereiche den Online-State via `context.select` lesen. Er ist der **einzige** neue Provider dieses Plans.
- **Root-UI-State (Kopplung #7):** Das Biometrie-**App-Lock-Overlay** (Kap. 9, S5) ist ein neuer Root-UI-Zustand → braucht eine **Gate-Route + Zweig in `_gateRedirect`** (`lib/routing/app_router.dart`), analog zu `/gesperrt`/`/aktualisierung`; **nicht** als Ad-hoc-Overlay in der Shell. Keine neuen `ShellTab` (die 7 Tabs bleiben, Reihenfolge = `ShellTab`-Enum).
- **Bewusste Systemgrenze — öffentliche Web-Routen:** Globale Suche (F4/N4), Offline-Banner (OP1) und `ConnectivityStatusProvider` gelten **nur in der authentifizierten `go_router`-Shell**. Die isolierten Public-`MaterialApp`s (`/wunsch`, `/feedback`, `/impressum`, `/datenschutz`) liegen bewusst **vor** Provider-Kette + go_router und dürfen **nicht** an diese Bausteine gekoppelt werden — sie behalten ihr eigenes flaches Signal-Teal-Design.
- **Faktenlage:** Alle `datei:zeile`-Referenzen stammen aus Agenten-Lesungen des realen Codes (Stand 2026-07-01); eine Stichprobe (`accessibility.dart:20`, `home_screen.dart:201/321/1215`, `pubspec`, `RedesignFlags.defaultEnabled`) wurde 1:1 verifiziert. **Vor** dem Umbau eines Screens sind seine konkreten Zeilennummern erneut zu prüfen (God-Files driften).

### 0.2 Getroffene Entscheidungen (verbindlich, Stand 2026-07-01)

Die sechs zuvor offenen Entscheidungen (vgl. Kap. 4 Phase 0 und Kap. 19) sind **entschieden**. Diese Festlegungen sind ab hier bindend; Kap. 19 dient nur noch als Herleitung.

| # | Entscheidung | Festlegung | Konsequenz für den Plan |
|---|---|---|---|
| **E1** | Dynamic Type (Textskala) | **Gestuft.** Lese-lastige Screens bis **2,0**; dichte Raster (Admin-Tabellen, Kiosk-Board, `fl_chart`-Charts, Schichtplan-Raster) als **dokumentierte Ausnahme bei 1,5**. | `kMaxTextScaleFactor` bleibt **nicht** ein einziger globaler Wert: globalen Clamp in [main.dart:680](lib/main.dart#L680) auf **2,0** anheben, dichte Screens lokal per `MediaQuery`-Override wieder auf 1,5 klemmen (`clampTextScaler` scoped). Neuer **DS-Meilenstein „Textskala-Leiter"** vor allen A11y-Bereichsdurchgängen; Golden-Tests bei 1,0/1,5/2,0. Alle „200 %"-Formulierungen bleiben gültig — für die Lese-Screens. |
| **E2** | Sicherheit 28/29/2FA | **Biometrie wird gebaut** (`local_auth`, Face ID/Touch ID/Fingerabdruck als App-Lock). **2FA wird geplant und ist umsetzbar** — die App läuft **bereits auf Blaze** (siehe [[blaze-zielumgebung]]), Firebase-MFA braucht daher nur Console-Aktivierung, keinen Billing-Cutover. | Kap. 9: S5 (Biometrie) von „Opt-in-Option" zu **In-Scope-Feature**; S6 (2FA) von „Ausblick" zu **geplantem Paket** (Firebase-MFA/TOTP, Enrollment-UX). Beide als **getrennte** Feature-Pakete (F2-Pakete + Native-Config), **nie** im Screen-Redesign-Commit. Biometrie-App-Lock = **Gate-Route + `_gateRedirect`** (Kopplung #7). |
| **E3** | Reduce-Motion-API | **`AppMotion.resolve` ist kanonisch;** `context.motionDuration`/`prefersReducedMotion` (`accessibility.dart`) delegiert darauf oder wird deprecated. | In die Review-Checkliste (F5). Neue/umgebaute animierte Widgets führen ihre Dauer ausschließlich durch `AppMotion.resolve`. |
| **E4** | Master-Detail-Breakpoint | **Einheitlich ab 840 dp (expanded).** 600–839 dp: einspaltig + Sheet. | Kontakte **K4 auf 840** korrigiert (kein Bereichs-Sonderweg); zentraler `AdaptiveMasterDetail` ist die Autorität. |
| **E5** | Push-Owner (Anf. 14) | **Exklusiv Anfragen A9** (`notification_settings_screen`) + Querschnitt D3. | Alle anderen Bereiche **verlinken** nur dorthin. Definition of Done für 14 = ein Ziel-Screen + Pre-Permission-Priming. |
| **E6** | Rollout-Reihenfolge | **Bestätigt:** Fundament → Heute → Anfragen → Zeit → Kontakte → Plan → Laden → Profil/Verwaltung. | Kap. 18 gilt unverändert; Strangler hinter `redesign_v2`, DoD je Bereich. |

### 0.3 Umsetzungsstand Phase 0 — Stand 2026-07-01

Das Fundament ist zu großen Teilen gebaut und verifiziert (`flutter analyze`: keine neuen Befunde; **1286 Tests grün**, davon 24 neu). Reihenfolge/DoD wie in Kap. 3.

| Baustein | Status | Artefakte |
|---|---|---|
| **DS3 · `AppErrorState`** (verständlicher Fehlerzustand, Retry, liveRegion) | ✅ umgesetzt + getestet | `lib/ui/app_error_state.dart`, Export in `lib/ui/ui.dart`, Tests in `ui_components_test.dart` |
| **DS3/F4-Baustein · `AppSearchField`** (kanonische Listensuche, Löschen, `search`-Action, Semantics) | ✅ umgesetzt + getestet | `lib/ui/app_search_field.dart`, Export, Tests |
| **F5 · Reduce-Motion konsolidiert** (`context.motionDuration` delegiert an `AppMotion.resolve`) | ✅ umgesetzt | `lib/core/accessibility.dart` |
| **DS1 · Token-Lücken** (Spacing `s6`/`s12` + `kTabularFigures`/`.tabular`) | ✅ umgesetzt + getestet | `lib/theme/theme_extensions.dart`, `theme_tokens_test.dart` |
| **F1 · Dynamic Type gestuft** (globaler Clamp → **2,0**, `DenseContentTextScale` → 1,5; Planer-Tab, Kiosk + dichte Section-Routen gewrappt) | ✅ umgesetzt + getestet | `lib/core/accessibility.dart`, `lib/routing/app_router.dart`, `home_screen.dart`, `accessibility_test.dart` |
| **F2 · Plattform-Pakete** (`connectivity_plus`, `local_auth`, `permission_handler`, `url_launcher`, `file_picker`) + Native-Config (Android-Permissions/`queries`, iOS `NSFaceIDUsageDescription`/`LSApplicationQueriesSchemes`, `MainActivity`→`FlutterFragmentActivity`) | ✅ Pakete + Config + Activity; **offen:** nur Geräte-Verifikation (kein Build hier möglich) | `pubspec.yaml`, `AndroidManifest.xml`, `Info.plist`, `MainActivity.kt` |
| **OP1 · Konnektivität + Offline-Banner** (`ConnectivityStatusProvider` früh in der Kette, `AppOfflineBanner` in der Shell) | ✅ umgesetzt + getestet | `lib/providers/connectivity_status_provider.dart`, `lib/ui/app_offline_banner.dart`, `main.dart`, `home_screen.dart`, Tests + Harness |
| **N4 · Globale Suche** (`SearchDelegate`, permission-gefilterte Bereiche + Datensätze, Top-Bar + Rail-Einstieg, diakritik-insensitiv) | ✅ umgesetzt + getestet; **Ausbau:** Deep-Link auf einzelne Datensätze je Zielscreen | `lib/screens/search/global_search.dart`, `home_screen.dart`, `app_nav_rail.dart`, `global_search_test.dart` |
| **DS2 · Kontrast-Gate** (WCAG-AA, light+dark, Laufzeit-Regressionsgate) | ✅ umgesetzt + getestet (fand `onError`-Near-Miss 4,36 → als Akzent-Ton dokumentiert) | `contrast_audit_test.dart` |
| **DS5 · Dual-Theme-Golden-Baseline** | ⏳ zurückgestellt | schwerere Infra (Font-Loading + Golden-Dateien); nach den ersten Bereichs-Rollouts |
| **F6 · Offline-Verhaltensmatrix (Artefakt)** | ✅ [Kap. 23](#23-anhang--offline-verhaltensmatrix-f6) | Aktions-Typ × Speichermodus × lesbar/schreibbar/gesperrt |

> **Hinweis zum Arbeitsbaum:** Die Phase-0-Änderungen liegen **uncommitted** neben einer **unabhängigen, bereits vorher vorhandenen** WIP-Arbeit (Scanner-Verbesserung: `scanner_screen.dart`, `barcode_scanner.dart`, `ean.dart`, Android-Config, `plan/scanner-verbesserung.md`). Beide sind **nicht** vermischt in der Logik, aber im selben uncommitteten Stand — vor einem Commit trennen.

---

## 1. Executive Summary

Das Ziel ist **nicht** ein weiteres Theme, sondern die **flächendeckende Einlösung** der 30 Eigenschaften über jeden Bereich — auf dem Fundament, das mit Signal-Teal V2 schon steht. Die Strategie:

1. **Fundament vor Fläche (Phase 0).** Erst die fehlenden Bausteine und Plattform-Pakete bauen (Suche, Fehler-Zustand, Offline-Status, Biometrie/Permission-Layer, Test-Gate, eine Grundsatzentscheidung zur Textskalierung). Ohne das entstehen in den Bereichen erneut Klone.
2. **Strangler je Bereich hinter `redesign_v2`.** Reihenfolge nach Nutzen/Risiko: **Fundament → Heute → Anfragen → Zeit → Kontakte → Plan → Laden → Profil/Verwaltung.** Jeder Bereich einzeln reviewbar und mergebar; nach jedem Schritt `flutter analyze` + `flutter test` grün + Dark/Light + Textscale-Abnahme.
3. **Ein durchgängiges Interaktionsmodell.** Pro Screen genau **eine** Primäraktion in der **Daumenzone** (FAB/BottomAppBar); Tabellen → adaptive Karten auf kleinen Displays; breite Screens → Master-Detail; native Muster je Plattform (Predictive-Back/Edge-Swipe, `.adaptive`-Widgets, Cupertino-Feinheiten); Skeleton-Loader statt Spinner; Offline-Banner + „zuletzt aktualisiert"; sparsame, `Reduce-Motion`-treue Animationen.
4. **Ehrlichkeit statt Fassade.** Vertrauens-Design ohne Fake-Siegel, Demo-Modus klar gekennzeichnet, Berechtigungen kontextuell begründet (Least Privilege), Fehlermeldungen deutsch und handlungsleitend.

**Was der Plan zusätzlich zu den Vorgänger-Plänen liefert** (die dort fehlten): plattformadaptive iOS/Android-Schicht, echtes Offline-Verhalten pro Screen, Push-Hygiene mit Pre-Permission-Priming, Biometrie-/2FA-Anmeldung, kontextuelle Berechtigungen und einen konsolidierten, testabgesicherten Rollout.

---

## 2. Die 30 Anforderungen — Abdeckungsmatrix

Jede vom Nutzer geforderte Eigenschaft ist einem konkreten Bereich/Querschnitt und Maßnahme zugeordnet. Status aus der adversarialen Kritik: **✓ abgedeckt** (Konzept + Bausteine tragen), **◐ teilweise** (Konzept steht, aber eine benannte Vorbedingung/Neubau fehlt noch — in Phase 0 adressiert). Kein Punkt ist „fehlend".

| # | Anforderung | Status | Wo adressiert | Restlücke (→ Phase 0) |
|---|---|:--:|---|---|
| 1 | Klare Bedienung | ✓ | Alle Bereiche: genau eine Primäraktion je Rolle/Screen (Heute M3 FAB, Plan P2, Zeit Z2/Z3, Anfragen A4, Kontakte K3, Laden L1); Abgleich-Querschnitt referenziert bestehende AP4/M3. | — |
| 2 | Übersichtliches Design | ✓ | Karten-/Kachel-Reduktion in jedem Bereich (Heute 11→6, Kontakte 7→3 Kopfblöcke, Laden AppBar entschlackt, Zeit Hub-Gruppen). | — |
| 3 | Einheitliches Aussehen | ✓ | Design-System-Querschnitt (lib/ui kanonisch, Tokens, kein Hex/dp) + jede Bereichs-Migration von Klon-Widgets auf lib/ui; verifiziert: lib/ui-Komponenten existieren. | Risiko liegt in der Ausführung (God-Files), nicht im Konzept. |
| 4 | Gute Lesbarkeit | ✓ | Design-System Typo-Tokens (bodyMedium≥14sp, Zeilenhöhe 1.35–1.45), Umlaut-Korrekturen bereichsweit, tabularFigures. | An 'Dynamic Type 200%' gekoppelte Lesbarkeitsversprechen sind durch den 1.5-Clamp real nur bis 150% gedeckt. |
| 5 | Intuitive Navigation | ✓ | Navigation/IA-Querschnitt (Breadcrumb, aktiver Tab-Indikator, deutsche URLs, konsistenter Profil-Tab V1/V2) + Master-Detail in Bereichen. | — |
| 6 | Responsives Design | ✓ | Responsive-Querschnitt (WindowClass-Leiter, AppContentScaffold-Caps, AdaptiveMasterDetail) + Breakpoint-Meilensteine je Bereich. | Kontakte K4-Breakpoint (600) widerspricht der 840-Autorität; personal_screen-Cap erst neu einzuführen. |
| 7 | iOS+Android Optimierung | ◐ | Responsive-Querschnitt AppAdaptive-Fassade (.adaptive, Cupertino-Picker/Dialoge, Physics) + Abgleich-Delta D1. | AppAdaptive-Fassade existiert noch NICHT (nur ~35 verstreute .adaptive-Konstruktoren im Code); zentraler Neubau, in Bereichen als selbstverständlich vorausgesetzt. Web-Guard (kIsWeb statt dart:io) muss diszipliniert durchgezogen werden. |
| 8 | Touch-freundlich | ✓ | A11y-Querschnitt (≥48x48dp, MaterialTapTargetSize.padded) + Zielwerte je Bereich (NumPad ≥64, Scanner ≥56, Kalenderzellen ≥44). | — |
| 9 | Daumenfreundlich | ✓ | FAB/BottomAppBar-Verlagerung der Primäraktion in jedem Bereich + BottomNav-Daumenzone im Nav-Querschnitt. | — |
| 10 | Kleine Bildschirme | ✓ | Horizontal-Scroll-Tabellen→Karten (Zeit Z4, Laden), Pixelraster→Agenda (Plan P2), volle-Breite-Sheets statt fixer Dialoge (Kontakte/Laden). | — |
| 11 | Native Bedienkonzepte | ◐ | Nav-Querschnitt (Predictive-Back/Swipe-Back, Tab-Re-Tap) + Responsive-Querschnitt (PageTransitions iOS/Android, RefreshIndicator.adaptive) + Abgleich-Delta D1. | Predictive-Back und iOS-Edge-Swipe werden durchgängig behauptet, aber CupertinoPageTransitionsBuilder/pageTransitionsTheme sind noch nicht gesetzt (Delta D1); Swipe-Actions-Kollision mit Swipe-Back mehrfach als Risiko genannt, aber ohne konkrete Kollisionsregel. |
| 12 | Schnelle Ladezeiten mobil | ✓ | Skeleton-Loader statt Spinner (Offline/Performance-Querschnitt: 32 Content-Spinner) + Cache-first-Reads; Firestore-Persistenz verifiziert aktiv (main.dart, kIsWeb-Zweig). | 'Startzeit-Messung' (D6) genannt, aber ohne Zielwert/Budget — bleibt Absichtserklärung. |
| 13 | Offline-Funktionalität | ◐ | Offline/Performance-Querschnitt (ConnectivityStatusProvider, AppOfflineBanner, Pending-Chip, Verhaltensmatrix); Datenschicht (Firestore-Persistenz) verifiziert vorhanden. | connectivity_plus ist NICHT im pubspec — ConnectivityStatusProvider + Online-Enum sind Neubau. Offline-Verhaltensmatrix pro Bereich noch nicht konkret ausgefüllt (welche Buttons genau ausgegraut). |
| 14 | Push-Benachrichtigungen | ◐ | Anfragen A9 (Settings-V2, Kategorie-Erklärungen) + Offline/Push-Querschnitt D3 (Priming, Häufigkeits-Hinweise); Push-Infra verifiziert vorhanden. | Mehrere Bereiche deklarieren 14 als 'keine Änderung/neutral' → Ownership-Lücke. Pre-Permission-Priming an OS-Prompt (29-gekoppelt) noch ohne konkreten Screen-Flow. |
| 15 | Gute Performance | ✓ | Offline/Performance-Querschnitt (ListView.builder/Sliver, const/select, RepaintBoundary, Frame-Budget 16/8ms), Deko-CustomPaint-Entfall (Plan P3). | — |
| 16 | Akku-/speicher-/datenschonend | ◐ | Offline/Performance-Querschnitt (kein connectivity-Polling, cacheWidth/cached_network_image, Reduce-Motion) + Abgleich-Delta D6. | cached_network_image als neue Dependency impliziert, nicht im pubspec bestätigt; Timer-/Poll-Reduktion nur als Prinzip, kein konkreter Screen-Audit. |
| 17 | Verständliche Fehlermeldungen | ✓ | AppErrorState/_friendlyError/formatUserError in allen Bereichen (Plan P7, Zeit Z3, Anfragen A3, Kontakte K3, PV-M1); roh-$error-Ersatz. | AppErrorState existiert noch NICHT in lib/ui (nur AppStatusBanner) — als DS3-Delta zu bauen; mehrere Bereiche setzen ihn voraus. |
| 18 | Fehlervermeidung | ✓ | AppFormField + Inline-Validierung + AppConfirmDialog + PopScope-Dirty-Guard flächendeckend (existieren verifiziert in lib/ui). | — |
| 19 | Barrierefreiheit | ◐ | A11y-Querschnitt (WCAG-AA, Semantics-Lücke 16-vs-46 zentral in lib/ui, Status Icon+Text, liveRegion) + Bereichs-A11y-Meilensteine. | Der '200%'-vs-'1.5-Clamp'-Widerspruch untergräbt das A11y-Versprechen; VoiceOver/TalkBack-Smoke-Test nur als Absicht; 220 Colors.*-Cleanup ist großes offenes Backlog, nicht abgeschlossen. |
| 20 | Dark + Light Mode | ✓ | Design-System-Querschnitt (lightV2/darkV2 unabhängig, testgesicherte appColors-Parität) + Dark-Audit-Meilensteine (L9, Z7, K9). | — |
| 21 | Moderne Optik | ✓ | Signal-Teal V2 verifiziert als Default live (redesign_v2 defaultEnabled=true); M3-Expressive im Design-System-Querschnitt. | — |
| 22 | Konsistente Buttons/Icons | ✓ | Design-System (AppIconSizes, Button-Semantik-Leitplanke Filled=Primär) + Klon-Ersatz in allen Bereichen + Nav-Icon-Paarung outline/filled. | AppButton-Semantik-Leitplanke ist als DS-Delta noch zu formalisieren (aktuell Konvention, keine erzwungene Komponente). |
| 23 | Klare Struktur | ✓ | AppSectionCard-Gruppierung + Hub-Domänentrennung (Nav-Querschnitt domain-Feld erzwingt einen Heimat-Hub) + God-File-Split (AP2). | — |
| 24 | Such- und Filterfunktionen | ◐ | Screen-lokale Suche/Filter in jedem Bereich (AppFilterChip/AppSearchField) + globale Suche via SearchAnchor im Nav-Querschnitt (N4). | AppSearchField UND globale SearchAnchor existieren NOCH NICHT im Code (verifiziert: kein SearchAnchor/SearchBar, kein AppSearchField) — beides Neubau; viele Bereiche setzen AppSearchField als vorhanden voraus. |
| 25 | Wenige unnötige Schritte | ✓ | Globale Suche 1-Tap-Sprung (Nav N4/N6), Metric-Drill-down (Heute M5), Month/Year-Picker statt Chevron-Spam (PV-M5/M6), kalendarische Mehrfachauswahl (Plan P5). | — |
| 26 | Angenehme Farben und Kontraste | ✓ | appColors-only, hashCode-Farbe→kontrastgeprüfte Standort-Palette (Plan P3), WCAG-AA-Prüfpaare (Design-System DS2). | — |
| 27 | Sinnvolle Animationen | ✓ | AppMotion-Tokens (verifiziert vorhanden in theme_extensions.dart) + Reduce-Motion via AppMotion.resolve durchgängig. | Zwei parallele Reduce-Motion-APIs (AppMotion.resolve vs. context.motionDuration) — Konsolidierung nötig. |
| 28 | Sichere Anmeldung | ◐ | Sicherheits-Querschnitt (local_auth-Biometrie-Gate, 2FA/TOTP-Roadmap, Angemeldet-bleiben) + Abgleich-Delta D4. | local_auth NICHT im pubspec (verifiziert: nur firebase_auth) — echter Neubau. 2FA nur Roadmap. Biometrie-Toggle in PV-M8 nur 'deaktivierte Vorbereitung' → Erwartungsmanagement-Risiko. |
| 29 | Datenschutzfreundlich | ◐ | Sicherheits-Querschnitt (JIT-Priming vor OS-Dialog, Least-Privilege, keine Standort/Kontakte) + Abgleich-Delta D5; Scanner nur Kamera. | permission_handler NICHT im pubspec — JIT-Priming-Flow ist Neubau. Datei-Picker (Kontakte K6 CSV-Import) fügt neue Berechtigung/Dependency hinzu, die dem Least-Privilege-Narrativ leicht widerspricht und Web zu prüfen ist. |
| 30 | Vertrauenswürdiges Design | ✓ | Sicherheits-Querschnitt (Sicherer-Zugang-Pill, Datenschutz/Impressum-Footer, ehrliche Demo-Kennzeichnung, keine Fake-Siegel) + konsistente V2-Optik überall. | — |

> Alle **◐-Punkte** haben genau eine Ursache: ein noch fehlender Fundament-Baustein (Suchfeld/Fehler-Zustand, ein Plattform-Paket, oder die Textskalierungs-Entscheidung). Diese sind in **Phase 0** gebündelt und gehen den Bereichs-Meilensteinen zeitlich voraus — danach werden die betroffenen Zeilen zu ✓.

---

## 3. Leitprinzipien & Leitplanken

**Gestaltungsprinzipien (gelten in jedem Bereich):**
- **Eine Primäraktion je Screen, in der Daumenzone.** Alles andere ist visuell untergeordnet. Wichtige Aktionen wandern nach unten (FAB/`BottomAppBar`), nie in schwer erreichbare obere Ecken.
- **Progressive Offenlegung.** Oben „Wo stehe ich?", Mitte „Was muss ich wissen?", unten „Was tue ich jetzt?". Karten-/Kachelzahl radikal reduzieren (z. B. Heute 11→6 Blöcke).
- **Karten statt Tabellen auf dem Handy.** Horizontal-Scroll-Tabellen werden zu adaptiven Karten/Listen; feste Dialoge werden zu voll-breiten Sheets.
- **Ein kanonisches Muster je Konzept.** Ein Status-Badge, ein Banner, eine Suche, eine Fehler-/Leerzustands-Komponente, eine Modul-/Navigations-Descriptor-Liste. Klone werden ersetzt, nicht kopiert.
- **Native Bedienkonzepte respektieren.** Android Predictive-Back und iOS-Edge-Swipe nicht blockieren; plattformadaptive Picker/Dialoge/Physics; Tab-Re-Tap scrollt nach oben / pop-to-root.

**Technische Leitplanken (nicht verhandelbar):**
- **Nur Optik/Layout/Struktur/UX** in den Screen-Redesigns — keine Änderung an Provider/Services/Models/Firestore/Functions/Compliance/Serialisierung. Feature-Anteile (Biometrie/Permissions/Konnektivität) laufen als **getrennte** Pakete mit `pubspec`- und Plattform-Konfig, **nie** im selben Commit wie ein Screen-Redesign.
- **Nur Tokens + `lib/ui`.** Kein `Color(0xFF…)`, keine nackten `EdgeInsets`/`BorderRadius`-Zahlen in neuen Widgets. Status ausschließlich über `appColors` und **immer** Icon **und** Kurztext (nie Farbe allein).
- **Dark + Light gemeinsam** entworfen und geprüft (WCAG-AA-Kontrast als Definition-of-Done-Gate).
- **Strangler-Fig, klein & mergebar.** `redesign_v2` bleibt der Schalter; alter Pfad erreichbar bis der neue stabil ist. **Refactor und Verhaltensänderung nie im selben Commit.**
- **Test-Gate je God-File.** Vor dem UI-Umbau eines Riesen-Screens Characterization-/Golden-Tests via `test/support/router_harness.dart` (`pumpApp`) als Merge-Gate. Deutsch/`de_DE`, keine neuen Lint-Rules, kein Mockito.
- **CLAUDE.md-Kopplungen bindend:** Tab-Reihenfolge = `ShellTab`, deutsche URLs, `appColors`, Permission-Getter gaten UI **und** Provider.

---

## 4. Phase 0 — Fundament & Vorbedingungen (MUSS vor den Bereichen)

Die Kritik hat sechs Dinge aufgedeckt, die **fast jeder Bereich stillschweigend voraussetzt**, die es aber **noch nicht gibt**. Sie werden zuerst gebaut und testabgesichert; erst danach dürfen Bereichs-Meilensteine sie konsumieren. Andernfalls entstehen neue Klone und uneinlösbare Versprechen.

| # | Vorbedingung | Warum blockierend | Ergebnis / Definition of Done |
|---|---|---|---|
| **F1** | **Grundsatzentscheidung Dynamic Type** (1,5 vs. 2,0) | Alle Bereiche versprechen „bis 200 % ohne Bruch", der Code klemmt bei `kMaxTextScaleFactor = 1,5` (`lib/core/accessibility.dart:20`, `lib/main.dart:680`). Beides gleichzeitig ist unmöglich. | **✓ Entschieden (E1): gestuft** — globalen Clamp auf **2,0** anheben, dichte Raster (Admin-Tabellen/Kiosk/`fl_chart`/Schichtplan-Raster) lokal per `MediaQuery`-Override wieder auf 1,5. Eigener DS-Meilenstein „Textskala-Leiter" **vor** allen A11y-Bereichsdurchgängen; Golden bei 1,0/1,5/2,0. |
| **F2** | **Plattform-Fundament-Paket** | `connectivity_plus`, `local_auth`, `permission_handler`, `url_launcher`, `file_picker` fehlen im `pubspec`. Offline (13), Biometrie (28), JIT-Permissions (29), Kontakt-Direktaktionen (K3) und CSV-Import (K6) brauchen sie **plus** `Info.plist`/`AndroidManifest`-Einträge + Web-Fallbacks. | Pakete + Plattform-Konfig ergänzt, je Plattform (iOS/Android/Web) lauffähig verifiziert. **Kein „nur Optik".** |
| **F3** | **Design-System-Deltas** DS1–DS4 | Es fehlen `AppErrorState`, `AppSearchField`, die Spacing-Token `s6`/`s12`, eine Tabular-Figures-Konstante und die formalisierte Button-/Status-Semantik-Leitplanke. Anfragen/Zeit/Kontakte/Laden bauen darauf, als existierten sie. | Neue kanonische Komponenten in `lib/ui` + Token-Lücken geschlossen + Semantik-Leitplanken dokumentiert (Details in Querschnitt „Design-System-Fundament"). |
| **F4** | **Globale Suche** (`SearchAnchor`) + einheitliche screen-lokale Suche | Es existiert **keine** globale Suche; „Infos schnell finden" (24) und „wenige Schritte" (25) hängen daran. | Eine `SearchAnchor`-basierte globale Suche (1-Tap-Sprung zu Modul/Datensatz) + `AppSearchField` als Standard je Liste (Details in Querschnitt „Navigation & IA"). |
| **F5** | **Reduce-Motion-API konsolidieren** | Zwei parallele APIs (`AppMotion.resolve` in `theme_extensions.dart` **und** `context.motionDuration` in `accessibility.dart`) tun dasselbe; Pläne referenzieren mal die eine, mal die andere. | `AppMotion.resolve` als kanonisch festgelegt, die andere delegiert/deprecated; in der Review-Checkliste verankert. |
| **F6** | **Test-Gate + Offline-Verhaltensmatrix** | God-File-Umbau ohne Sicherheitsnetz ist das größte Regressionsrisiko; „offline ausgegraut" ohne konkrete Matrix wird inkonsistent. | Golden/Characterization via `pumpApp` als Merge-Gate je God-File **festgeschrieben**; ein Artefakt „Screen × Aktion × Offline-Zustand (lesbar/schreibbar/gesperrt)" erstellt und je Bereich als Checkliste eingehängt (Callables/Compliance/OktoPOS/DATEV sind offline gesperrt). |

Die konkreten Bausteine dieser Phase 0 stehen in den **Querschnitt-Kapiteln** (Design-System-Fundament, Navigation & IA, Barrierefreiheit, Sichere Anmeldung, Offline/Performance/Push). Die Bereichs-Kapitel bauen darauf auf.

---



# Teil B — Fundament & Querschnitt-Design


## 5. Fundament — Design-System (Farbe, Typografie, Form, Motion, Dark/Light)

Dieses Fundament ist die **verbindliche Single Source of Truth** für alle Screens des Redesigns. Es konsolidiert den bereits vorhandenen V2-Stand (Signal-Teal, `redesign_v2`) aus `lib/theme/app_theme.dart`, `lib/theme/theme_extensions.dart` und `lib/ui/*` und definiert die noch fehlenden Token-Lücken. **Regel für alle Screens:** kein Hex, kein `Colors.*`, kein `BorderRadius.circular(<zahl>)`, kein `size: <zahl>` im Widget-Code — ausschließlich benannte Theme-Rollen (`colorScheme.*`, `Theme.of(context).appColors.*`) und Tokens (`context.spacing/radii/motion/elevation/iconSizes`). Damit werden Einheitlichkeit (Anf. 3, 22), Lesbarkeit (4), Farben/Kontrast (26), moderne Optik (21), Dark/Light (20) und sinnvolle Animationen (27) systemisch erzwungen statt pro Screen wiederholt.

### 1. Farbrollen — Signal Teal (hell/dunkel unabhängig)

Seed `#0E7C7B` (hell) / `#5FD4CE` (dunkel), `DynamicSchemeVariant.vibrant`, danach fast alle Rollen hand-getunt (`_buildColorSchemeV2` in `app_theme.dart`). `surfaceTint = transparent` → ruhige, flache Canvas ohne Tonal-Tints; Tiefe entsteht über Container-Kontrast + Hairline-Border, nicht über Schatten (Anf. 21, 26). **Hell und Dunkel sind vollständig getrennt definiert (keine Inversion) → echte Dark/Light-Parität (Anf. 20).**

| Rolle | Hell | Dunkel | Verwendung |
|---|---|---|---|
| primary | `#0E7C7B` | `#5FD4CE` | CTA-Fill, Links, aktive Border, Fokus |
| onPrimary | `#FFFFFF` | `#003735` | Text auf primary |
| primaryContainer | `#9CF0E9` | `#00504D` | FAB, Hero-Akzent |
| onPrimaryContainer | `#00201F` | `#9CF0E9` | Text auf primaryContainer |
| secondary | `#3F7C8E` | `#A8CDD9` | zweitrangige Akzente (Logo-Cyan bleibt) |
| secondaryContainer | `#C7E7F0` | `#294A55` | Nav-Indicator, ausgewählte Chips/Tabs |
| tertiary (Violett) | `#7A5BD6` | `#C9BCFF` | „über Soll"-Akzent, dritter Akzent |
| error | `#BA5C67` | `#F3AFBA` | Cancel/Ausstempeln, Fehler-Border |
| surface | `#F6FBFA` | `#0E1514` | Scaffold-BG (2 % Teal-Hauch) |
| onSurface | `#141D1C` | `#DDE4E2` | Primärtext |
| onSurfaceVariant | `#5A6663` | `#BEC9C7` | gedämpfter Text, Sekundärlabels |
| surfaceContainerLow | `#F0F7F6` | `#131A19` | **Card-BG** |
| surfaceContainer / High / Highest | `#EAF2F1` / `#E3EDEC` / `#DCE7E5` | `#171F1E` / `#212A28` / `#2B3533` | gestufte Flächen, Track, Disabled-BG |
| outline / outlineVariant | `#6F7977` / `#BEC9C7` | `#889391` / `#3F4948` | Border (Hairline @0.7 alpha) |

**Status-Farben** liegen bewusst NICHT im ColorScheme, sondern in `AppThemeColors` (ThemeExtension, 12 Felder, Zugriff nur über `Theme.of(context).appColors`). **In V2 identisch zu V1** (`lightV2 = light`, `darkV2 = dark` in `theme_extensions.dart`) — Ampel, Coverage-Card und Planner-Palette sind auf exakt diese Hues getunt, Feldnamen sind unantastbarer Kontrakt für ~97 Consumer:

| Ton | Hell (Farbe / Container) | Dunkel (Farbe / Container) |
|---|---|---|
| success | `#187A58` / `#DFF3EA` | `#5DD3A2` / `#0F3A2A` |
| warning | `#A76E00` / `#FFE8B8` | `#E1B45C` / `#4C3809` |
| info | `#2D6CDF` / `#DCE8FF` | `#8CB6FF` / `#143C78` |

Der kanonische Zugriff auf semantische Töne ist `AppStatusTone` (`lib/ui/app_status.dart`, Enum `neutral/primary/secondary/tertiary/success/warning/info/error`) → `_resolveTone` mappt auf ColorScheme bzw. `appColors`. Screens dürfen success/warning/info **nie** direkt greifen, sondern über `AppStatusBadge`/`AppStatusBanner` + Ton.

**Kontrast-Ziele (WCAG 2.1 AA, Anf. 4, 19, 26):** Fließtext ≥ 4.5:1, große Schrift (≥ 18.66px bold / 24px) und UI-Grafik ≥ 3:1. Verbindliche Prüfpaare mit gemessenem Ist-Stand:

| Paar (Light-V2) | Kontrast | AA |
|---|---|---|
| onSurface `#141D1C` auf surface `#F6FBFA` | ~15.3:1 | ✓ Text |
| onSurfaceVariant `#5A6663` auf surface `#F6FBFA` | ~5.0:1 | ✓ Text |
| onSurfaceVariant `#5A6663` auf surfaceContainerHigh `#E3EDEC` | ~4.5:1 | Grenzfall Text — nur ab bodyMedium bold nutzen |
| onPrimary `#FFFFFF` auf primary `#0E7C7B` | ~4.6:1 | ✓ Text/CTA |
| onSecondaryContainer `#0E303B` auf secondaryContainer `#C7E7F0` | ~10:1 | ✓ (Nav/Tab-Selektion) |
| primary `#0E7C7B` als Border/Icon auf surface | ~4.6:1 | ✓ UI-Grafik (≥3:1) |

Verbindliche Nachprüfung: **Kontrast-Assertion als Test** über alle 6 Rollen-Paare je Brightness (light/dark) + ein `appColors`-non-null-Test für `lightV2`/`darkV2` (verhindert null-crash bei `appColors`-Consumern). Grenzfälle (onSurfaceVariant auf High-Containern) werden per Konvention nur mit `w600+` verwendet.

### 2. Typografie — NotoSans, hoher Gewichtskontrast, Tabellenziffern

`fontFamily: 'NotoSans'` (harte Asset-Abhängigkeit `assets/fonts/NotoSans-{Regular,Bold,Italic}.ttf`), Basis `Typography.material2021`, danach per-Style-Overrides. **Kritische Reihenfolge (in beiden Themes dokumentiert):** erst `.apply(fontFamily:'NotoSans', bodyColor/displayColor)`, dann Overrides vom bereits angewandten TextTheme ableiten — sonst tragen Overrides die Plattform-Font und Text wird auf Web-CanvasKit unsichtbar. V2 fährt höheren Gewichtskontrast als V1 (moderne Optik, Anf. 21):

| Rolle | Größe/Zeile (M2021) | V2-Gewicht / Tracking | Einsatz |
|---|---|---|---|
| displaySmall | 36 / 1.22 | w800 · -1.0 | Hero-Zahlen, große KPIs |
| headlineMedium | 28 / 1.29 | w800 · -0.6 | Screen-Titel |
| headlineSmall | 24 / 1.33 | w700 · -0.4 | Sektions-Titel |
| titleLarge | 22 / 1.27 | w700 · -0.2 | AppBar-Titel, Card-Titel |
| titleMedium | 16 / 1.5 | w700 | Listen-Kopf, Card-Label |
| titleSmall | 14 / 1.43 | w700 | Tab-/Sub-Label |
| labelLarge | 14 | w700 · +0.2 | Button-/Chip-Text |
| bodyLarge | 16 | height 1.45 | primärer Fließtext |
| bodyMedium | 14 | height 1.4 | Standard-Fließtext |
| bodySmall | 12 | height 1.35 | Meta, Captions |

**Lesbarkeit (Anf. 4, 19):** Fließtext-Minimum ist bodyMedium (14 sp); bodySmall (12) nur für Meta/Captions, nie für primäre Handlungsinformation. Erhöhte Zeilenhöhe (1.35–1.45) für Textblöcke. Die App respektiert System-`textScaleFactor` (Material default) → Layouts müssen Text-Wrap tolerieren, keine fixen Höhen um Text.

**Tabellenziffern (`FontFeature.tabularFigures()`)** als **Opt-in** für Zahlen-Rollen (Uhr, Stunden, Plan/Ist, Bestand, Beträge) — bereits in `app_stat_cards.dart` (`_tabularFigures`) etabliert. Nie global (bricht Fließtext). Kanonisierung: Konstante `kTabularFigures` in `lib/ui/` bereitstellen und in Zahl-Widgets/Uhr-Ticker referenzieren, damit Werte beim Ticken nicht „springen".

### 3. Form — Radien & Elevation (flach, Border-getrieben)

Radien über `AppRadii.v2` (in `theme_extensions.dart`, geliefert via `extensions:` nur im V2-Theme; Zugriff `context.radii`):

| Token | Wert | Einsatz |
|---|---|---|
| xs | 8 | kleinste Chips/Marker |
| sm | 12 | eng geschachtelte Container |
| md | 16 | Buttons, Inputs, ListTile, Segmented, Menüs, SnackBar |
| lg | 20 | Nav-Indicator, Status-Banner |
| xl | 28 | **Cards, Dialoge, BottomSheet-Kante** |
| xxl | 36 | Hero-Container, Extended-FAB |
| pill | 999 | Chips, Status-Badges, Scrollbar, Progress-Track |

Primär-CTAs sind bewusst **`StadiumBorder` (Pill)** (M3-Expressive-Signal in `filledButtonTheme`/`elevated`/`outlined` V2). **Elevation** über `AppElevation` (`flat 0` Default · `raised 1` Hover · `floating 3` FAB/aktives Sheet · `overlay 6` Menüs) — **sparsam, nie auf Grid/Planner-Zellen**. Trennung primär über `dividerTheme` (0.8 dp) + Hairline-Border (`outlineVariant @0.7`). Hinweis: `AppCard` nutzt aktuell `elevation: 1` mit weichem Schatten @0.5 alpha — für Grid-/Planner-Kontexte gilt weiterhin bespoke, schattenfrei (Performance, Dichte).

### 4. Spacing & Icon-Tokens (inkl. der fehlenden 12/6-Stufe)

`AppSpacing` (`context.spacing`): `xxs 2 · xs 4 · sm 8 · md 16 · lg 24 · xl 32 · xxl 48`, 4/8-Rhythmus. **Lücke:** Es fehlt eine **12er- und 6er-Stufe** — heute wird 12 als `sm + xs` und 6 als `xs + xxs` zusammengesetzt (sichtbar in `app_status.dart`/`app_card.dart`/`app_stat_cards.dart`), was schwer lesbar ist und Token-Disziplin unterläuft. **Verbindliche Ergänzung (additiv, defaultet, `copyWith`/`lerp` erweitern):**

| Token | Neuer Wert | Ersetzt Ausdruck |
|---|---|---|
| xxs | 2 | — |
| xxs2 → **`xxs` bleibt 2** | | |
| **`s6` (neu)** | 6 | `spacing.xs + spacing.xxs` |
| sm | 8 | — |
| **`s12` (neu)** | 12 | `spacing.sm + spacing.xs` |
| md | 16 | — |
| lg / xl / xxl | 24 / 32 / 48 | — |

Nach Einführung von `s6`/`s12` werden die zusammengesetzten Ausdrücke in `lib/ui/*` auf die neuen Tokens migriert (reiner Lesbarkeits-Refactor, 0 visuelle Regression). `AppIconSizes` (`context.iconSizes`): `sm 18 · md 24 · lg 28 · xl 32 · hero 40` — ersetzt hartkodierte `size:`-Werte (Anf. 3, 22). Touch-Targets (Anf. 8, 9): Buttons `minimumSize` 64×56, Icon-/Text-Button 48×48 (V2) — erfüllt die 48-dp-Fingerregel.

### 5. Motion — Dauern, Kurven, Reduce-Motion

`AppMotion` (`context.motion`, neu in V2): `short 150ms · medium 300ms · long 450ms · extraLong 600ms`; Kurven `standard = easeInOutCubicEmphasized`, `emphasizedEnter = easeOutCubic`, `emphasizedExit = easeInCubic`, `spring = easeOutBack` (FAB/Chips/Auswahl). **Reduce-Motion ist Pflicht (Anf. 19, 27):** jede animierte Komponente führt ihre Dauer durch `AppMotion.resolve(context, dauer)` → liefert `Duration.zero` bei `MediaQuery.disableAnimations`. Richtwerte: Tab/State-Wechsel `short`, Sheet/Dialog `medium`, Hero/Seiten-Transition `long`. Animationen sparsam und funktional (Lade-/Wechsel-Feedback), keine dekorativen Dauerbewegungen (Akku/Performance, Anf. 15, 16).

### 6. Kanonische Komponentenbibliothek `lib/ui/` (Barrel `lib/ui/ui.dart`)

Ein Import (`package:worktime_app/ui/ui.dart`) liefert Tokens + alle Bausteine. **Vorhanden und kanonisch:**

| Komponente | Ersetzt Klon(e) | Status |
|---|---|---|
| `AppCard` (`app_card.dart`) | rohes `Card(Padding(16))` app-weit | Primitiv |
| `AppSectionCard` (`app_section_card.dart`) | `SectionCard` + `statistics._SectionCard` | DEDUP |
| `AppMetricCard` / `AppStatCard` / `AppComparisonStatCard` (`app_stat_cards.dart`) | `_DashboardMetricCard` / `_StatCard` / `_PlannedActualStatCard` | Restyle, Mathe 1:1 |
| `AppHeroCard` (`app_hero_card.dart`) | `_EmployeeHeroCard` + `_PlannerHeroCard` | Hülle |
| `AppQuickAction*` (`app_quick_action.dart`) | `_QuickActionCard` / `_QuickActionListTile` | Restyle |
| `AppStatusBadge` + `AppStatusTone` / `AppStatusBanner` (`app_status.dart`) | `_ShiftStatusBadge`, `_LocationStatusBadge` / Render-Hälfte `_ShellStatusBanner` | Vereinheitlichen |
| `AppSegmented<T>` + `AppSegment<T>` + `AppFilterChip` (`app_segmented.dart`) | Day/Week/Month-`SegmentedButton` + Planner-Filter-Pills | Wrapper |
| `AppBottomSheetScaffold` (`app_bottom_sheet_scaffold.dart`) | Sheet-Chrome (Punch/Shift/Absence/Team-Editor) | Chrome |
| `AppFormField` (`app_form_field.dart`) / `AppConfirmDialog` (`app_confirm_dialog.dart`) | `TextFormField`+`InputDecoration` / inline `showDialog(AlertDialog)`-Confirms | Wrapper |
| `AppKontoTile` (`app_konto_tile.dart`) | Konto-/Zeitwirtschaft-Zeilen | Primitiv |
| `AppEmptyState` (typedef auf `EmptyState`) | `_EmptyState`, `statistics._EmptyState`, `_PlannerEmptyState`, `_PlannerEmptyBoardState` | DEDUP (4 Klone) |

**Re-exportierte saubere Bestands-Widgets** (nicht neu bauen): `AppLogo`, `BreadcrumbAppBar`, `InfoChip`, `SectionCard`, `SectionHeader`, `responsive_layout` (`MobileBreakpoints`/`AdaptiveCardGrid`). Responsive-Schwellen (Anf. 6, 10): NavRail ab `mediumWindow = 600`, volle Rail-Labels ab `expandedWindow = 840`, BottomNav darunter — zentral in `responsive_layout.dart`, nie hartkodiert.

**Lücken in der Bibliothek (verbindlich zu ergänzen, damit „gleiche Funktion = gleiches Aussehen", Anf. 22, greift):**
1. **`AppButton`-Leitplanke:** kein neues Widget, aber verbindliche Semantik-Zuordnung dokumentieren — `FilledButton` = Primäraktion (max. 1 pro View), `OutlinedButton`/`ElevatedButton` = Sekundär, `TextButton` = tertiär/abbrechen. Cancel/Ausstempeln immer mit `colorScheme.error`-Foreground.
2. **`AppErrorState` / inline Fehler-Widget** (Anf. 17, 18): standardisiertes Widget für Fehlermeldung + Retry-Aktion + verständlicher deutscher Text — heute uneinheitlich. Nutzt `AppStatusTone.error`.
3. **`AppSearchField`** (Anf. 24): einheitliches Such-/Filter-Feld (Prefix-Lupe, Clear-Suffix) über Inventar/Kontakte/Team, statt pro Screen zusammengebautes `TextField`.
4. **Offline-/Sync-Banner-Ton-Konvention** (Anf. 12, 13): `AppStatusBanner` mit `AppStatusTone.warning` (offline/lokal) bzw. `info` (Sync läuft) als kanonischer Weg; „Jetzt synchronisieren" als `action`.

### 7. Dark/Light-Parität & Integration (Strangler)

Beide Varianten (`lightV2`/`darkV2`) MÜSSEN `AppThemeColors` in `extensions:` liefern (sonst null-crash) — dies ist testgesichert. V1 (`AppTheme.light/dark`) bleibt byte-identisch bis `redesign_v2` 100 % stabil; Selektor `AppTheme.resolveLight/Dark({required bool useV2})`. Alle neuen Token-Extensions (`AppMotion`/`AppElevation`/`AppIconSizes` und die neuen Spacing-/Radius-Werte) sind additiv mit Defaults, `copyWith`/`lerp` erweitert → 0 Regression für Bestands-Consumer. **Alle UI-Texte Deutsch, jedes `DateFormat` mit `'de_DE'`.**


## 6. Fundament — Navigation & Informationsarchitektur

> Scope: reine Optik/Layout/Struktur/UX. Keine Änderung an Provider/Services/Models/Firestore/Functions/Compliance/Serialisierung. Alle URL-/Permission-Konstanten bleiben (`lib/routing/shell_tab.dart`, `route_permissions.dart`). Bindende Kopplung: Tab-Reihenfolge = `ShellTab.values` (Branch-Index), CLAUDE.md #7.

### 1. Ist-Zustand & Kernprobleme (belegt)

Die Shell ist technisch solide (`StatefulShellRoute.indexedStack`, 7 statische Branches, `_gateRedirect` als Single-Source der Root-Wahl, `RoutePermissions` als geteilte Permission-Matrix). Die IA leidet aber an drei strukturellen Defekten:

| # | Befund | Beleg |
|---|---|---|
| N1 | **Drei konkurrierende Modul-Oberflächen** mit divergierenden Teilmengen: Laden-Hub, Profil-Hub, `AppNavMenu`-Drawer. Personal 2-3×, Warenwirtschaft/Kundenbestellungen je 2-3× erreichbar. | `home_screen.dart:2782-3014`, `app_nav_menu.dart:141-191` |
| N2 | **Orphan-Route `/kundenwuensche`** ist definiert (`AppRoutes.customerWishes`) und pushbar, aber von **keiner** Oberfläche verlinkt → faktisch unerreichbar. | `app_router.dart:175`, `shell_tab.dart:60` |
| N3 | **Scanner-Permission-Divergenz**: BottomNav prüft `isLocationAllowed(scanner)` (`home_screen.dart:495`), Drawer `showScanner && canManageInventory` (`app_nav_menu.dart:170`), kanonisch aber `canUseScanner` (`route_permissions.dart:72`). Drei Wahrheiten für eine Route. | s. Zellen |
| N4 | **Keine globale Suche** vorhanden. `grep showSearch/SearchAnchor/SearchDelegate` → 0 Treffer in `lib/`. Anforderung 24 unerfüllt. | — |
| N5 | **V1/V2-Asymmetrie**: In V2 ist der Profil-Tab ausgeblendet (`_isTabVisible` → `tab==profile && useV2 ? false`), Ersatz ist das Slide-in-Menü; je Flag verschwindet eine ganze Oberfläche. | `home_screen.dart:1061` |
| N6 | **Zeit-Admin 3 Klicks tief** (Lohnlauf/Mitarbeiterabschluss nur im Zeit-Hub, nicht im Drawer/Schnellaktion). | `route_permissions.dart:38-40` |

### 2. Kanonische Tab-Struktur (7 Tabs bleiben, Rollen-gefiltert)

Die 7 `ShellTab`-Branches und deutschen URLs **bleiben unverändert** (Reihenfolge kanonisch). Neu ist nur ihre konsistente Präsentation je Formfaktor:

| Branch-Index | ShellTab | URL | Label | Icon (outline/filled) | Sichtbarkeit (Permission) |
|---|---|---|---|---|---|
| 0 | `today` | `/` | Heute | `home_outlined`/`home` | immer |
| 1 | `plan` | `/plan` | Plan | `view_timeline_outlined`/`view_timeline` | `canViewSchedule` |
| 2 | `time` | `/zeit` | Zeit | `schedule_outlined`/`schedule` | `canViewTimeTracking` |
| 3 | `inbox` | `/anfragen` | Anfragen | `inbox_outlined`/`inbox` (+Badge) | immer |
| 4 | `contacts` | `/kontakte` | Kontakte | `contacts_outlined`/`contacts` | `canViewContacts` |
| 5 | `shop` | `/laden` | Laden | `storefront_outlined`/`storefront` | `canViewInventory` |
| 6 | `profile` | `/profil` | Profil | `person_outline`/`person` | immer (siehe unten) |

**Entscheidung Profil-Tab-Asymmetrie (N5):** Profil-Tab in **V1 UND V2 konsistent behalten** statt der heutigen Hybrid-Lösung. Der `_isTabVisible`-Sonderfall (`tab==profile && useV2 → false`) entfällt; das Slide-in-Menü bleibt als *zusätzlicher* Schnellzugang (Avatar-Tap / „Mehr"), nicht als Ersatz. Damit sind Funktionsumfang und „wo bin ich" identisch, egal welches Flag greift (Anforderung 3, 5, 23).

### 3. Nav-Muster je Formfaktor (native iOS/Android + Desktop)

Breakpoints aus `MobileBreakpoints` (`responsive_layout.dart`) bleiben Autorität — nicht hartkodieren.

| Formfaktor | Breite | Nav-Chrome | Begründung |
|---|---|---|---|
| **Handy** (Android/iOS nativ) | < 600 dp | **BottomNav** unten, feste 5er-Leiste `Heute · Plan · Scanner · Anfragen · Mehr` | Daumenzone unten (Anf. 9), max. 5 Slots Material-Norm; „Mehr" (`more`) öffnet Drawer für Zeit/Kontakte/Laden/Profil |
| **Tablet Portrait / Split / kleines Desktopfenster** | 600–839 dp | **NavigationRail** links, nur ausgewähltes Label (`useNavigationRail`) | Material-3 medium window; `AppNavRail` (V2) mit 112 px |
| **Tablet Landscape / Desktop** | ≥ 840 dp | **NavigationRail** links, alle Labels (`useExpandedRailLabels`) | `AppNavRail` expandiert auf 188 px |

**BottomNav-Detail (Handy):** Die feste 5er-Leiste bleibt (`_v2BottomNavEntries`), damit Position/Muskelgedächtnis stabil. Scanner pusht `/scanner` (kein Branch), „Mehr" öffnet den Drawer. Der aktive Branch außerhalb der Leiste (Zeit/Kontakte/Laden/Profil) markiert „Mehr" — verhindert „kein Item aktiv". `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3)` bleibt (Labels sprengen die Leiste nicht, aber A11y-Textskalierung erhalten — Anf. 19).

**Rail-Detail (Tablet/Desktop):** In der Rail stehen alle 7 permission-gefilterten Tabs direkt; der Drawer wird zum `endDrawer` (von rechts, via Account-Button) und zeigt **nur** noch Auswertungen/Verwaltung/App (keine „Bereiche"-Gruppe, die stehen ja links). Das ist heute schon so verdrahtet (`showAreas: false` bei Rail) — beibehalten.

**Touch-Targets (Anf. 8):** Nav-Items erben aus dem Theme: `IconButton` min `Size(48,48)`, `NavigationBar`-Destinationen sind bereits ≥ 48 dp hoch. Alle neuen Nav-/Menü-Einträge über `AppQuickActionTile` (ListTile-basiert, ≥ 56 dp). Rail-Item-Vertikalpadding `spacing.sm + spacing.xs` bleibt. Zu prüfen und auf ≥ 44 dp anzuheben: Mini-Icon-Buttons in `BreadcrumbAppBar`/`ShellBreadcrumb` (Zurück-Chevron `size: 20`).

### 4. EINE kanonische Modul-Quelle (behebt N1, N2, N6)

**Kern-Entscheidung:** Eine einzige Descriptor-Liste `AppSection` speist Laden-Hub, Profil-Hub *und* `AppNavMenu`-Drawer. Vorbild ist der bereits existierende Descriptor-Hub `zeitwirtschaft_hub_screen.dart` (`_hubDestinations`, rollen-gefiltert). Damit können Teilmengen **strukturell nicht mehr divergieren**.

```
class AppSection {            // rein präsentational, keine Provider-Zugriffe
  final String label;
  final String subtitle;
  final IconData icon;
  final String route;         // AppRoutes.*
  final AppSectionDomain domain;   // shop | personal | reports | management | app
  final bool Function(AppUserProfile?) canAccess;  // = RoutePermissions.isLocationAllowed(route, p)
}
```

- **`canAccess` delegiert immer an `RoutePermissions.isLocationAllowed(route, p)`** → eine Wahrheit pro Route. Behebt N3 (Scanner) automatisch: Drawer, BottomNav und Hub lesen dieselbe Funktion.
- **`domain` bestimmt den Heimat-Hub** → jede Destination hat genau eine Heimat (behebt Mehrfach-Erreichbarkeit N1). Laden-Hub = `shop` + `management`; Profil-Hub = `reports` + `app` + Persönliches.
- **`/kundenwuensche` bekommt einen Eintrag** (`domain: shop`, `canViewInventory`) → N2 geschlossen.
- **Zeit-Admin sichtbar** (N6): `/zeit/lohnlauf` + `/zeit/mitarbeiterabschluss` als `domain: management`-Einträge (nur `isAdmin`) zusätzlich in den Drawer/Hub — nicht nur 3 Klicks tief im Zeit-Hub.

**Hub-Domänentrennung (Anf. 23):** Laden-Hub in **Gruppen** statt flachem 6er-Grid: *Lagerwirtschaft & Vertrieb* (Warenwirtschaft, Kundenbestellungen, Kundenwünsche, Bestell-Auswertung, Kundenfeedback) · *Verwaltung* (Personal, Buchhaltung, Änderungsprotokoll). Profil-Hub = nur Persönliches (Profilkarte, Einstellungen, eigene Berichte, Sicherheit/Abmelden) + Link „zum Laden-Bereich". Gruppen-Rendering über bestehendes `_MenuGroup` (`app_nav_menu.dart:370`).

### 5. Globale Such- & Filter-Strategie (Anf. 24 — heute komplett fehlend, N4)

Neuer Einstieg: **`AppGlobalSearchBar`** (M3 `SearchAnchor` + `SearchBar`), erreichbar per Such-Icon in der V2-Top-Bar (Handy) bzw. Rail-Kopf (Desktop). Scope-Strategie:

| Ebene | Muster | Datenquelle (nur lesen, keine neue Persistenz) |
|---|---|---|
| **Global** (App-weit) | `SearchAnchor` öffnet Overlay; gruppierte Treffer nach Domäne (Kontakte, Artikel, Mitarbeiter, Bereiche/Navigation) | vorhandene Provider-Listen (`ContactProvider`, `InventoryProvider`, `TeamProvider`) — reines In-Memory-Filtern |
| **Navigations-Sprung** | Sektions-Treffer navigieren via `context.push(section.route)` aus der `AppSection`-Liste | die kanonische Descriptor-Liste (§4) doppelt als Such-Index für Bereiche |
| **Screen-lokal** | konsistente `AppSearchField` + `AppChoiceChipBar`/`AppSiteFilterBar` (Filter) in jeder Liste (Kontakte, Warenwirtschaft, Team) | bestehende Screen-Filterlogik, nur vereinheitlichte Optik |

Ergebnis-Gruppen tragen deutsche Header via `AppListSectionHeader`. Permission-gefiltert über dieselbe `canAccess`-Funktion → keine Treffer auf gesperrte Bereiche. Kein Netz-Roundtrip nötig → offline-fähig (Anf. 13) und schnell (Anf. 15, 25). Debounce 250 ms gegen Rebuild-Last (Anf. 15/16). Bewusst **nicht** im Erst-Inkrement: server-seitiger Volltext (bräuchte Backend-Änderung, out of scope).

### 6. Back-Stack, Deep-Link & „wo bin ich" (Anf. 5, 11, 25)

**Orientierung („wo bin ich", Anf. 5):**
- Aktiver Tab hervorgehoben (BottomNav-Indikator / Rail Teal-Gradient-Indikator, `AppNavRail._RailItem`).
- Gepushte Hauptbereiche zeigen **Breadcrumb** (`ShellBreadcrumb`/`BreadcrumbAppBar`), z. B. „Laden / Warenwirtschaft" — `parentLabel` wird schon durchgereicht (`app_router.dart:148-192`). Konsistent für ALLE Section-Routen sicherstellen (heute teils gesetzt).
- Deutsche URLs in der Web-Adressleiste bleiben sichtbare Orientierung.

**Native Zurück-Navigation (Anf. 11):**
- **Innerhalb eines Tabs**: gepushte Section-Route → `Navigator.pop` → zurück zum Tab-Hub (Standard-`AppBar`-Back, Android-Systemzurück, iOS-Swipe-back via `CupertinoPageTransitionsBuilder` sicherstellen im `PageTransitionsTheme`).
- **Cross-Tab-Zurück**: bestehende `_navHistory` + `PopScope(canPop: _navHistory.isEmpty)` + Zurück-Chevron im Tab-Header über `_ShellScope` (`home_screen.dart:80-83, 142`) — **beibehalten**, das ist die korrekte Lösung gegen „App schließt beim Zurück auf einem Nicht-Heute-Tab".
- **Tab-Re-Tap**: aktiver Branch neu getippt → `goBranch(initialLocation: true)` (Pop auf Tab-Wurzel) — Standard-Erwartung erfüllt.

**Deep-Links / Push / Schnellaktionen:** Bleiben über `_gateRedirect` gate-konform (Pending-Route via `QuickActionsService`/`PushMessagingService`, Permission-geprüft mit `isLocationAllowed`). Keine Änderung nötig — nur sicherstellen, dass neue `AppSection`-Routen dieselbe `isLocationAllowed`-Matrix nutzen (Anf. 18: kein Sprung in gesperrte Bereiche).

### 7. Konsistenz, Motion, A11y der Nav-Chrome (Anf. 3, 19, 22, 27)

- **Icons konsistent** (Anf. 22): eine Icon-Paarung (outline = inaktiv, filled = aktiv) pro Modul, zentral in `_destinationMeta`/`AppSection`. Gleiche Funktion → gleiches Icon in BottomNav, Rail, Drawer, Hub.
- **Badge-A11y (Anf. 19)**: Zähler-Badges (`_badgedNavIcon`, `AppNavRailItem.badgeCount`) in `Semantics(label: 'Anfragen, 3 ungelesen')` fassen — heute stumm für Screenreader.
- **Motion sparsam** (Anf. 27): Rail-Indikator-Animation `AnimatedContainer(duration: context.motion.short, curve: context.motion.standard)` bleibt; keine zusätzlichen Nav-Animationen.
- **Dark/Light** (Anf. 20): alle Nav-Flächen über `colorScheme`-Rollen (`surfaceContainerLow`, `secondaryContainer`, `primaryContainer`) — kein Hardcode, folgt System-Theme automatisch.

### 8. Umsetzung als Strangler-Fig (mergebar, verhaltenserhaltend zuerst)

Reihenfolge minimiert Risiko: erst billige Korrekturen (N2/N3/N6), dann die kanonische Quelle, dann Suche/Master-Detail. Alle Pakete halten `flutter analyze` + `flutter test` + `router_harness` grün und sind im `APP_DISABLE_AUTH=true`-Modus visuell zu smoke-testen.


## 7. Fundament — Responsive & Adaptive Layout

### Ausgangslage (Ist)

Die Grundlagen existieren bereits und werden **nicht ersetzt, sondern konsequent flächendeckend gemacht**:

- `lib/widgets/responsive_layout.dart` liefert `MobileBreakpoints` (Rail ab `mediumWindow=600`, volle Rail-Labels ab `expandedWindow=840`, `isNativeMobile`, `screenPadding`, `gridColumns`) und `AdaptiveCardGrid` (Wrap mit gleich breiten Spalten). Die Shell (`home_screen.dart:157`) schaltet korrekt NavRail↔BottomNav.
- `contacts_screen.dart:92` und `inventory_screen.dart:314` setzen bereits `SafeArea` + `ConstrainedBox(maxWidth: 1100)`. Das ist der Referenz-Wert.
- `kiosk_screen.dart:448` nutzt eine eigene LayoutBuilder-Grid-Staffel (720/1100).
- **Lücken:** `personal_screen.dart` (5649 Zeilen) hat **keinen** `maxWidth`-Cap → Zeilen laufen auf Desktop/Web über die volle Breite. Es gibt **keine** Master-Detail-Nutzung breiter Screens (contacts/inventory öffnen Detail immer als BottomSheet, auch auf 1440px). Adaptive Widgets (Cupertino) sind nur punktuell (`showAdaptiveDialog`, `Switch.adaptive`) statt systematisch. Kein zentraler Breakpoint-/Helper-Baustein für Content-Caps und Master-Detail.

> **Scope-Grenze:** Dieser Abschnitt plant **nur** Optik/Layout/Struktur/UX. Kein Eingriff in Provider/Services/Models/Firestore/Functions/Serialisierung. Alle neuen Bausteine liegen in `lib/widgets/` bzw. `lib/ui/` und konsumieren ausschließlich Design-Tokens (`context.spacing/radii/motion`, `appColors`) — keine Hex-Werte, keine festen dp außer den hier definierten Breakpoints.

### Verbindliche Breakpoint-Leiter (Window Size Classes)

Wir richten uns strikt an Material-3-Window-Size-Classes aus und ergänzen `MobileBreakpoints` um benannte Klassen (kein Ersetzen der bestehenden Konstanten):

| Klasse | Breite (dp) | Geräte-Beispiele | Navigation | Content-Layout |
|---|---|---|---|---|
| `compact` | < 600 | Handys Portrait, iPhone SE..15 | BottomNav (5 Slots) | 1 Spalte, volle Breite, `screenPadding` 12–20 |
| `medium` | 600–839 | iPad Portrait, Split-View, kleine Fenster, Handy Landscape | NavigationRail (nur aktives Label) | 2 Spalten / Master-Detail **optional** |
| `expanded` | 840–1239 | iPad Landscape, Desktop-Fenster | NavigationRail (alle Labels) | Master-Detail **an**, `maxWidth 1100` |
| `large` | ≥ 1240 | Desktop/Web maximiert | NavigationRail (alle Labels) | Master-Detail + zentrierter Content-Cap `maxWidth 1240` |

Neuer Helper in `responsive_layout.dart`:

```dart
enum WindowClass { compact, medium, expanded, large }
WindowClass windowClassOf(double width) => width < 600 ? WindowClass.compact
  : width < 840 ? WindowClass.medium
  : width < 1240 ? WindowClass.expanded : WindowClass.large;
```

### Zentrale Layout-Bausteine (neu in `lib/widgets/`, ins `lib/ui/ui.dart`-Barrel exportiert)

1. **`AppContentScaffold`** — kapselt das wiederkehrende `SafeArea` + `ConstrainedBox(maxWidth)` + `screenPadding`-Muster (heute in contacts/inventory dupliziert). Parameter `maxWidth` (Default `1100`, für Dashboards `1240`, für Formulare `640`). Ersetzt handkopierte `ConstrainedBox`-Blöcke → Konsistenz-Anforderung (3, 23).
2. **`AdaptiveMasterDetail`** — `LayoutBuilder`-basiert: unter `expanded` (840) rendert es nur die Master-Liste und öffnet Detail per Navigation/BottomSheet (Handy-Verhalten unverändert); ab `expanded` rendert es `Row(Master 360–400dp | VerticalDivider | Expanded(Detail))`. Kein State-Umbau: Der ausgewählte Datensatz ist reiner UI-State im Screen; Detail-Panel zeigt bei „nichts gewählt" einen `AppEmptyState`. Löst die Raumnutzungs-Anforderung (6, Master-Detail).
3. **`AppAdaptive`** — dünne Fassade für plattformadaptive Primitiven (siehe Abschnitt „Plattformadaptive Widgets"), damit Screens nicht selbst `defaultTargetPlatform` abfragen.
4. **`AdaptiveCardGrid`** bleibt für Dashboard-Kacheln; `minItemWidth` je Bereich getunt (Stat-Cards 160, Aktions-Kacheln 220).

### Layout-Muster je Bereichstyp

**A) Listen-Bereiche** (Kontakte, Bestand, Sortiment, Team, Bestellungen, Personal-Listen)
- compact: 1-spaltige `ListView.separated` in `AppContentScaffold(maxWidth: 1100)` mit `screenPadding`. Detail = BottomSheet (heutiges Verhalten).
- expanded/large: `AdaptiveMasterDetail` — Liste links (fix 360–400dp), Detail rechts inline statt Sheet. Spart auf Desktop/iPad Landscape den Modal-Sprung (Anforderung 25, wenige Schritte).
- **Sofortmaßnahme:** `personal_screen.dart` bekommt zwingend `AppContentScaffold(maxWidth: 1100)` (heute fehlender Cap → Lesbarkeit/Zeilenlänge, Anforderung 4).

**B) Formulare** (EntryForm, Schicht-Editor, Bestell-Editor, Kontakt-/Artikel-Edit)
- Content-Cap `maxWidth: 640` zentriert (optimale Zeilenlänge, Anforderung 4/23). Felder immer 1-spaltig gestapelt; auf ≥ expanded dürfen kurze Feldpaare (z. B. „von/bis", „Menge/Einheit") in einer `Row` nebeneinander stehen.
- In BottomSheets bleibt `isScrollControlled: true` + `useSafeArea: true`; Sheet-Höhe folgt Content, Tastatur-Inset via `viewInsets` (siehe Safe-Area).

**C) Dashboards** (Home-Tabs, Bestand-Insights, Statistik, Zeitwirtschaft-Hub)
- `AdaptiveCardGrid` mit `gridColumns`: 1 Spalte compact, 2 medium, 3 expanded, bis 4 large (bereits `clamp(1,4)`). Content-Cap `maxWidth: 1240`.
- Hero-/Stat-Cards (`AppHeroCard`/`AppStatCards`) füllen die erste Reihe; sekundäre `AppQuickAction`-Kacheln folgen im Grid.

**D) Boards** (Schichtplaner-Board, Kiosk-Tablet-Board)
- Schichtplaner: horizontale Wochenspalten; compact = eine Tages-/Listenspalte mit Wochen-Swiper, ab medium mehrspaltige Woche. Elevation-Token **nicht** auf Zellen (siehe `AppElevation`-Doku).
- **Kiosk-Board** (`kiosk_screen.dart`): fest tablet-/landscape-orientiert. Grid-Staffel auf die neue Leiter vereinheitlichen (2 Spalten ab 720 → 3 ab 1100), Kachel-Mindesthöhe für große Touch-Ziele (≥ 88dp), da geteiltes Store-Tablet mit Fingerbedienung aus Distanz. `SafeArea` + `viewPadding` für Tablet-Notch/Home-Indicator.

### Plattformadaptive Widgets (iOS/Android native Gewohnheiten — Anforderung 7/11)

Fassade `AppAdaptive` wählt anhand `Theme.of(context).platform` (nicht `dart:io` → Web-sicher). Grundhaltung: **Material bleibt Basis**, Cupertino nur dort, wo iOS-Nutzer eine native Geste/Optik erwarten und Material sich „fremd" anfühlt:

| Element | iOS | Android/Web/Desktop | Umsetzung |
|---|---|---|---|
| Datums-/Zeitwahl | `CupertinoDatePicker` (Rad, im Sheet) | Material `showDatePicker`/`showTimePicker` | `AppAdaptive.pickDate/pickTime` |
| Dialoge | `CupertinoAlertDialog` | Material `AlertDialog` | `showAdaptiveDialog` + `AppConfirmDialog` bereits vorhanden → adaptiv machen |
| Switch/Checkbox/Radio | `.adaptive`-Konstruktoren | Material | flächendeckend `Switch.adaptive` etc. |
| Ladeindikator | `CupertinoActivityIndicator` | `CircularProgressIndicator` | `CircularProgressIndicator.adaptive` |
| Scroll-Physik | `BouncingScrollPhysics` | `ClampingScrollPhysics` | zentral über `ScrollBehavior` im Theme statt pro Liste |
| Zurück-Geste | Edge-Swipe (`CupertinoPageRoute`) | System-Back / Predictive Back | `PageTransitionsTheme` mit `CupertinoPageTransitionsBuilder` für iOS |
| Pull-to-Refresh | Cupertino-Sliver | Material `RefreshIndicator` | `RefreshIndicator.adaptive` |

Zusatz: `MaterialApp.theme.pageTransitionsTheme` erhält je Plattform den passenden Builder (iOS Cupertino-Slide, Android Predictive-Back-Builder) → native Navigations-Haptik ohne Screen-Änderungen (Anforderung 11).

### Safe-Area / Notch / Insets (Anforderung 9/10)

- **Jeder** Screen-Root: `SafeArea` (heute inkonsistent). Boards/Kiosk zusätzlich `viewPadding` für Home-Indicator/Notch.
- Scroll-Container: unteres Padding = `MediaQuery.viewInsetsOf(context).bottom` + BottomNav-Höhe, damit letzter Listeneintrag über BottomNav/Tastatur bleibt.
- **Daumenzonen (Anforderung 9):** Primäraktion je Screen als FAB unten-rechts bzw. Extended-FAB; destruktive/seltene Aktionen in AppBar/Overflow oben. Suchfeld sticky oben, Ergebnis-Interaktion unten erreichbar.
- BottomNav und FAB respektieren `MediaQuery.paddingOf(context).bottom` (gesture-Bar).

### Anti-Overflow / kleine Bildschirme (Anforderung 10)

- Text durchgängig `maxLines` + `TextOverflow.ellipsis`; `Row`-Zellen in `Expanded`/`Flexible` (contacts nutzt das bereits, Muster verbindlich machen).
- `Wrap` statt `Row` bei Chip-/Button-Leisten (Toolbar-Footgun aus `home_screen`: `Expanded` in `Wrap` vermeiden).
- `MediaQuery.textScalerOf` respektieren: keine festen Höhen für Text-Container; große Schrift bis 200 % darf umbrechen, nicht clippen (Anforderung 19).

### Migrationsreihenfolge

1. Bausteine bauen (`AppContentScaffold`, `AdaptiveMasterDetail`, `AppAdaptive`, Breakpoint-Enum) + Barrel-Export.
2. `personal_screen.dart` capsen (schnellster sichtbarer Gewinn).
3. Listen-Screens auf `AppContentScaffold` konsolidieren (contacts/inventory/sortiment/team) — dedupliziert `ConstrainedBox`.
4. Master-Detail auf contacts + inventory aktivieren (expanded+).
5. Plattformadaptive Fassade ausrollen (Datepicker/Dialoge/Switches/Physik/PageTransitions).
6. Kiosk-Board-Grid + Dashboards auf die Leiter vereinheitlichen.

Kein Storage-/Provider-Test bricht (reine Widget-Struktur); `test/support/router_harness.dart` deckt Shell-Navigation weiter ab, ergänzend Golden-/Widget-Tests bei drei Breiten (360/834/1440).


## 8. Fundament — Barrierefreiheit (WCAG, Screenreader, Dynamic Type)

Ziel: WCAG 2.1 **AA** als verbindliches Mindestniveau für alle produktiven Screens (Web/iOS/Android/Desktop), umgesetzt mit den vorhandenen Token- und Helfer-Bausteinen statt neuer Sonderwege. Die Grundlagen sind teilweise schon da (`lib/core/accessibility.dart` mit `prefersReducedMotion`/`motionDuration`, `clampTextScaler` @ 1.5 app-weit in `lib/main.dart:680`, sauber getunte Status-Farben in `lib/theme/theme_extensions.dart`), aber ungleich adoptiert: **Semantics existiert nur an 16 Stellen, fast ausschließlich in `public/`- und `auth`-Screens** — die Hauptbereiche (Warenwirtschaft, Team, Schicht, Zeit, Home-Shell) haben faktisch keine Screenreader-Annotationen. Diese Strategie schließt die Lücke, ohne Provider/Services/Logik anzufassen (reine UI-Ebene).

### 1. Kontrast-Zielwerte (AA) und heutige Verletzungen

| Element | Ziel-Ratio | Regel |
|---|---|---|
| Fließtext, Labels < 18px / < 14px-bold | **4.5:1** | Pflicht auf jeder Fläche (Card, Hero, Sheet) |
| Großtext ≥ 18px oder ≥ 14px-bold | **3:1** | z. B. Kachel-Titel, Screen-Header |
| Icons/Grafik mit Bedeutung, Fokus-/Zustandsränder, Divider mit Semantik | **3:1** | Non-Text-Contrast (WCAG 1.4.11) |
| Deaktivierte Elemente | ausgenommen | müssen aber als „deaktiviert" erkennbar sein (nicht nur per Kontrast) |

Als verbindliche Kontrastpaare gelten ausschließlich die benannten ColorScheme-/AppThemeColors-Rollen. Status-Farben sind bereits AA-tauglich getunt: Light `success #187A58 / onSuccess white`, `warning #A76E00 / onWarning white`, `info #2D6CDF`; Dark `success #5DD3A2 / onSuccess #032217` usw. — diese Paare NICHT verändern.

**Konkret zu prüfende/behebende Verletzungsrisiken (Datei-Bezug):**

| Fundstelle | Risiko | Maßnahme |
|---|---|---|
| `lib/theme/app_theme.dart:237,683` `onSurfaceVariant.withValues(alpha: 0.45)` (Placeholder/Disabled) | ~2:1 auf Card-BG — unter 4.5:1 | Nur für echt deaktivierte Zustände zulassen; Placeholder-Hinweistext auf ≥ 0.60 anheben |
| `lib/ui/app_status.dart:82,147`, `app_stat_cards.dart:93,183`, `app_quick_action.dart:34,107` `color.withValues(alpha: 0.12/0.30)` als Container-BG | BG selbst ist unkritisch, aber **Text darauf** muss gegen die 12%-Fläche geprüft werden | Text/Icon auf diesen Flächen immer über die zugehörige `onXContainer`-Rolle, nie über die 12%-Farbe |
| 220 `Colors.*`-Treffer, gehäuft in `scanner_screen.dart`, `shift_planner_screen.dart`, `home_screen_tabs.dart`, `shift_editor_sheet.dart`, `stempel_screen.dart`, `widgets/action_fab.dart` | hartkodierte Farben ignorieren Dark-Mode-Kontrast und die appColors-Regel | Named-Color-Audit: jede semantische Farbe → `Theme.of(context).appColors` bzw. ColorScheme-Rolle; nur echt neutrale (z. B. Overlay-Scrim, Kamera-Overlay im Scanner) dürfen bleiben |
| `home_dashboards_v2.dart:352` fixe `height: 110 * textScale` (bis 1.6) | eng, aber gedeckelt | ok, als Muster für andere fixe Höhen übernehmen |

**Nicht-farbliche Bedeutung (WCAG 1.4.1):** Ampel/Status (`AppStatusBadge`, `_AbcBadge` in `sortiment_screen.dart`, `_EditorCountBadge` in `shift_planner_screen.dart`) tragen Bedeutung nur über Farbe → jede Statusfarbe zusätzlich mit Icon **und** Textlabel doppeln.

### 2. Semantics-Richtlinien (Screenreader: TalkBack/VoiceOver/NVDA)

Grundsatz: semantische Bedeutung statt visueller Zufall. Zentrale Regeln, umzusetzen in den V2-Komponenten unter `lib/ui/` (Single-Point-of-Fix) und in den Hauptscreens:

- **Buttons/Aktionen:** Jeder tap-bare `InkWell`/`GestureDetector` (16 Semantics vs. 46 Tap-Handler = massives Defizit) bekommt `Semantics(button: true, label: '…', child: …)` oder wird durch echte `*Button`-Widgets ersetzt. `AppQuickAction`, `AppKontoTile`, Kachel-`InkWell`s in `home_screen_tabs.dart` sind die Hauptkandidaten.
- **Icon-only-Controls:** Alle 136 `tooltip:`-Nutzungen liefern dem Screenreader bereits ein Label — beibehalten. Icon-`InkWell`s **ohne** Tooltip (z. B. Scanner-Overlay-Buttons) brauchen ein `Semantics(label:)` oder Tooltip.
- **Badges/Zähler:** Notifications-/Inbox-Badges als `Semantics(label: '$n neue Benachrichtigungen', …)` (Zahl vorlesbar machen; „7" allein ist bedeutungslos). Overflow-Anzeige „9+"/„99+" einführen (heute keine Kappung gefunden) und dann als `label: 'mehr als 9 …'` sprechen. `_AbcBadge` → `label: 'ABC-Klasse A'`.
- **Dekorative Grafik ausblenden:** Muster wie `ExcludeSemantics` in `public_ui.dart:245,440` und `AppLogo` konsequent für rein dekorative Icons/Illustrationen verwenden, damit der Screenreader sie überspringt.
- **Bilder/Avatare:** Avatar mit Initialen → `label: 'Peter Meyer'`; Produkt-/Logo-Bilder ohne Info → `ExcludeSemantics`.
- **Live-Regions für Fehler/Statuswechsel:** Formular-Fehlertexte (`AppFormField`) und Speicher-/Ladehinweise als `Semantics(liveRegion: true, …)`, damit Änderungen automatisch vorgelesen werden (deckt Anf. 17). SnackBars sind bereits live; wichtige Inline-Validierung ist es nicht.
- **Gruppierung/Header:** Screen-Titel und Section-Header (`AppSectionCard`) als `Semantics(header: true)` für schnelle Rotor-/Überschriften-Navigation.
- **Zustände:** ausgewählte Tabs/Segmente (`AppSegmented`, NavRail in `app_nav_rail.dart:148` hat schon Semantics) als `selected: true`; Umschalter mit `toggled:`.

### 3. Dynamic Type / Textskalierung ohne Overflow

- **Deckel bleibt bei `kMaxTextScaleFactor = 1.5`** (`lib/core/accessibility.dart:20`), app-weit via `clampTextScaler` (`main.dart:680`). Das schützt fixe Höhen (NavigationBar, Slide-to-Clock) — aber Ziel ist, die Komponenten **flexibel** zu machen und den Deckel mittelfristig auf iOS-übliche höhere Werte zu lockern.
- **Regel „keine fixen Text-Höhen":** Kacheln/Cards mit fixem `height` (z. B. `dashboard_action_items_card.dart:188`, Stat-Cards) auf `IntrinsicHeight`/min-Höhe + `Flexible` umstellen oder Höhe wie `home_dashboards_v2.dart:352` mit `textScale` mitwachsen lassen.
- **Overflow-Verhalten:** Titel `maxLines: 2` + `TextOverflow.ellipsis` statt Clipping; nebeneinanderliegende Label+Wert bei Skalierung > 1.3 auf Umbruch (Wrap/Column) ausweichen.
- **Golden-/Widget-Test bei 1.0, 1.3, 1.5** für die 8 V2-Kernkomponenten in `lib/ui/` (siehe Checkliste), damit Overflow früh sichtbar wird.
- Zahlenfelder/Zeit-Picker (`alwaysUse24HourFormat` in `team_management_screen.dart`) bleiben unberührt.

### 4. Mindest-Touch-Target-Regel (Anf. 8)

- **Verbindlich: jedes interaktive Element ≥ 48×48 dp** (Material) bzw. ≥ 44×44 pt (iOS-HIG) effektive Trefferfläche — auch wenn das sichtbare Icon kleiner ist. Umsetzung über `padding`/`SizedBox`/`ConstraintedBox(minWidth/minHeight: 48)` bzw. `IconButton`-Default (48). Kleine Icons (`iconSizes.sm`) sind ok, solange die Trefferfläche gepolstert ist.
- **Prüf-/Fixstellen:** die 46 rohen `InkWell`/`GestureDetector` (u. a. Scanner-Sheet `scanner_screen.dart:442,1000,1539`) auf Trefferflächen-Padding prüfen; `dashboard_action_items_card.dart:188` (32 dp) auf 48 anheben. `MaterialTapTargetSize.padded` im Theme sicherstellen.
- **Abstand zwischen Zielen** ≥ 8 dp (`AppSpacing`) gegen Fehlklicks, besonders in dichten Listen (Team/Kontakte).

### 5. Fokus-Reihenfolge & Tastatur (Web/Desktop + Switch-Control)

- **Logische DOM-/Widget-Reihenfolge = Leserichtung** (oben→unten, links→rechts). Bei visuell umsortierten Layouts (Wrap, Stack) `FocusTraversalGroup` + `OrderedTraversalPolicy` setzen.
- **Sichtbarer Fokus-Ring** auf Web/Desktop (Non-Text-Contrast 3:1) — nicht wegstylen; `Focus`/`FocusableActionDetector` für Custom-Controls, die heute nur `onTap` haben.
- **Sheets/Dialoge:** Fokus beim Öffnen auf den ersten sinnvollen Inhalt, beim Schließen zurück auf den Auslöser; `AppBottomSheetScaffold`/`AppConfirmDialog` als zentrale Umsetzungspunkte.
- **Tab-/Zurück-Navigation** nativ belassen (go_router `PopScope` in der Shell), keine Fokus-Fallen.

### 6. Reduce-Motion respektieren (Anf. 27)

- **`context.prefersReducedMotion` / `context.motionDuration(normal)`** (schon vorhanden) wird zur **Pflicht für jede App-eigene Animation**: `AnimatedContainer`, `AnimatedOpacity`, Hero, implizite Übergänge, Ladepuls/Shimmer und Page-Transitions ziehen ihre Dauer aus `motionDuration(AppMotion.…)`.
- **Shimmer/Skeleton-Loader** bei Reduce-Motion auf statischen Platzhalter statt Dauer-Animation umschalten.
- Motion bleibt „sinnvoll & sparsam" (Anf. 27): nur zur Orientierung bei Wechsel/Laden; keine dekorative Dauerbewegung.

### 7. Prüf-Checkliste vor Auslieferung (Definition of Done Accessibility)

- [ ] **Kontrast:** Alle neuen/geänderten Text-auf-Fläche-Paare ≥ 4.5:1 (Großtext ≥ 3:1), Icons/Fokusränder ≥ 3:1 — in Light **und** Dark geprüft.
- [ ] **Keine hartkodierten semantischen Farben** — `flutter analyze` + Grep `Colors.` in geänderten Dateien; nur Neutral-/Overlay-Ausnahmen.
- [ ] **Screenreader-Durchlauf** je Plattform (TalkBack/VoiceOver/NVDA): jeder Button hat Label, Badges sprechen Zahl+Bedeutung, Dekor ist `ExcludeSemantics`, Fehler sind Live-Region.
- [ ] **Touch-Targets ≥ 48 dp** für alle Tap-Handler (Accessibility-Guideline im Flutter-Test / manuell).
- [ ] **Dynamic Type** bei Skalierung 1.0 / 1.3 / 1.5 ohne Overflow (Golden-Tests der `lib/ui/`-Komponenten grün).
- [ ] **Reduce-Motion an**: alle Animationen ⇒ Duration.zero / statisch (kein Ruckeln, keine Endlos-Animation).
- [ ] **Fokus-Reihenfolge** auf Web/Desktop per Tab-Taste logisch; sichtbarer Fokus-Ring vorhanden.
- [ ] **Status nie nur per Farbe** (Icon + Textlabel vorhanden).
- [ ] Flutter DevTools „Accessibility"/Semantics-Debugger stichprobenartig auf dem geänderten Screen laufen lassen.


## 9. Fundament — Sichere Anmeldung, Biometrie & Datenschutz

### 0. Leitidee & Trust-Boundary-Rahmen

Der Anmelde-Flow ist der erste Vertrauensmoment der App. Er muss **sicher wirken** (Anf. 30), **einfach bedienbar** (Anf. 1/25) und **fehlerarm** (Anf. 17/18) sein. Grundregel aus `claude-skills/sicherheit/01_api-sicherheit.md` und `02_software-sicherheit.md`: Der Flutter-Client ist **nie vertrauenswürdig** — jede Sicherheitsentscheidung im Client (Biometrie-Gate, „Angemeldet bleiben", Rollen-Sichtbarkeit) ist reine **UX/Defense-in-Depth**, die eigentliche Grenze liegt in `firestore.rules` + Callables (`assertSameOrg`/`normalizeRole`). Dieser Abschnitt plant **nur Optik/Layout/UX** — die vorhandenen `AuthProvider`-Aufrufe (`signInWithEmailPassword`, `activateInvite`, `signInWithGoogle`, `signInWithLocalDemoProfile`, `signOut`) und die zwei bereits sehr ausgereiften Screens `lib/screens/auth_screen.dart` (V1) und `lib/screens/auth_screen_v2.dart` (V2, Signal-Teal) bleiben funktional unverändert. V2 ist die Zielarchitektur; alles unten baut darauf auf.

Wichtige Ehrlichkeit vorab: **`local_auth` und `permission_handler` sind noch NICHT im `pubspec.yaml`** (nur `firebase_auth: ^5.2.0`). „Biometrie" existiert heute nur als Platzhaltertext in `home_screen.dart:3116`. Die Biometrie-/Permission-Punkte unten sind daher ein **Zielbild**, das je nach Umsetzungswunsch neue Pakete (client-only, kein Backend-Umbau) erfordert; die Optik/Zustände sind aber schon jetzt entwerfbar.

### 1. Login-Zielbild (Anf. 28 sichere Anmeldung, 2/4/21 Optik)

Basis bleibt das V2-Layout aus `auth_screen_v2.dart`: Zwei-Spalten (`_IntroPanelV2` + `_AuthCardV2`) ab Breite `760`, „Formular zuerst" (`_MobileAuthBody`) darunter — das ist bereits daumenfreundlich (Anf. 9) und responsiv (Anf. 6/10). Verfeinerungen:

| Element | Ist (V2) | Ziel-Verfeinerung |
|---|---|---|
| Vertrauens-Pill | `'Sicherer Zugang'` / `'Demo-Zugang'`, Pill in `surfaceContainerHighest` | Icon voranstellen: `Icons.lock_outline` (16 dp) + Text; Demo-Modus zusätzlich `AppStatusTone.warning`-Tönung, damit Demo klar als unsicher lesbar ist |
| Passwort-Feld | `AppFormField` + `obscure`-Toggle vorhanden | ergänzen: optionaler **Passwort-Stärke-Meter** nur im Einladungs-Flow (`_InvitationActivationFormV2`), 3-stufig (schwach/ok/stark) über `appColors.warning/info/success`, unter dem Feld als schmaler `LinearProgressIndicator` (2 dp) + Kurztext |
| „Angemeldet bleiben" | fehlt | neue `AppKontoTile`-artige Checkbox-Zeile unter dem Passwort: `Switch` + Label „Angemeldet bleiben" + Untertext „Nur auf deinem privaten Gerät aktivieren." (Datenschutz-Hinweis, Anf. 29). Default **aus** auf Web/geteiltem Tablet-Verdacht, **an** auf Mobil |
| Passwort vergessen | fehlt | `TextButton` „Passwort vergessen?" rechtsbündig unter dem Passwortfeld → öffnet `showModalBottomSheet` (Reset-Sheet, siehe §5). Nur sichtbar, wenn `!auth.authDisabled` |
| Biometrie-Schnellzugang | fehlt | bei aktiviertem Biometrie-Opt-in (§3) **oberhalb** des E-Mail-Formulars eine große primäre Aktion `FilledButton.icon` „Mit Face ID anmelden" / „Mit Fingerabdruck anmelden" (Label + Icon plattform-/verfügbarkeitsabhängig), `Size.fromHeight(56)` |
| CTA-Höhe | `Size.fromHeight(52)` | einheitlich `52` beibehalten (Konsistenz, Anf. 8/22) — Touch-Ziel > 48 dp erfüllt |

Reihenfolge im Formular (mobile, daumen-optimiert von oben nach unten): Marken-Header → Vertrauens-Pill → optional Biometrie-CTA → E-Mail → Passwort (+ Stärke im Invite) → „Angemeldet bleiben" + „Passwort vergessen?" → primärer CTA → Trenner „oder" → Google. Die **wichtigste Aktion (Login-CTA) sitzt unten** und ist mit dem Daumen erreichbar (Anf. 9).

### 2. Klare Sperr-/Update-Zustände (Anf. 5/17/30)

Die drei Gate-Screens (`FirebaseSetupScreenV2`, `AccessBlockedScreenV2`, `ForceUpdateScreen`) bekommen ein **einheitliches Zustands-Layout** (Anf. 3/23), damit sie als eine Familie erkennbar sind:

- **Gemeinsames Muster:** zentrierte `AppCard` (maxWidth `480`), oben ein farbcodiertes Zustands-Icon in `AppIconSizes.hero`, darunter Headline `headlineSmall/w800`, Erklärtext `bodyMedium`, ganz unten genau **eine** Primäraktion (`Size.fromHeight(52)`).
- **Icon-/Ton-Codierung** über `appColors` statt Hardcode: Konto deaktiviert = `Icons.lock_person_outlined` in `warning`; Update erforderlich = `Icons.system_update_outlined` in `info`; Firebase-Setup = `Icons.cloud_off_outlined` in `neutral/onSurfaceVariant`.
- **`ForceUpdateScreen`** wird auf das V2-Muster gehoben (heute noch reines `Card`/`Icon 48`): Headline „Update erforderlich", Build-Zeile als `AppStatusBanner(tone: info)` statt grauer Kleintext, **plattformgerechter Store-CTA** — „Im App Store aktualisieren" (iOS) / „Bei Google Play aktualisieren" (Android) / „Seite neu laden" (Web). Bewusst weiterhin **kein** Weiter-/Abmelden-Ausweg (der Kommentar im File ist verbindlich: zu alter Client darf keine Schreibpfade erreichen).
- **`AccessBlockedScreenV2`** behält den „Abmelden"-CTA, ergänzt einen sekundären `TextButton` „Support kontaktieren" (mailto aus `LegalInfo.email`, falls gesetzt) — gibt dem gesperrten Nutzer einen Handlungsweg (Anf. 17).

Alle Texte bleiben Deutsch, `de_DE`. Zustands-Screens erhalten `Semantics(liveRegion: true)` auf der Headline (Screenreader, Anf. 19).

### 3. Biometrie-Gate-Konzept (Anf. 28, nur Client-UX)

Ziel: kein Passwort-Neu-Tippen bei jedem App-Start, ohne Sicherheitsniveau zu senken. **Kein Backend-Umbau** — Biometrie schützt nur den lokalen Re-Entry, nicht den Server-Token.

- **Paket:** `local_auth` (client-only). Verfügbarkeit über `LocalAuthentication().canCheckBiometrics` + `getAvailableBiometrics()`; Label dynamisch: `BiometricType.face` → „Face ID"/„Gesichtserkennung", sonst „Fingerabdruck"/„Touch ID".
- **Opt-in-Moment (kontextuell, nicht beim ersten Start):** direkt **nach dem ersten erfolgreichen Passwort-Login** ein `AppBottomSheetScaffold` „Schneller wieder anmelden?" mit Nutzen-Text „Melde dich künftig per {Biometrie} an, ohne dein Passwort einzugeben. Deine biometrischen Daten verlassen das Gerät nie." (Datenschutz-Vertrauen, Anf. 29/30). Buttons: „Aktivieren" (primär) / „Später" (`TextButton`). Das ersetzt/erweitert den heutigen Platzhalter-Text in `home_screen.dart:3116`.
- **Gate beim App-Start:** ist Biometrie aktiviert und eine gültige Firebase-Session vorhanden, zeigt der Start-Screen (`/start`) statt des Loaders ein **Biometrie-Lock-Overlay** (App-Logo, `Icons.lock`, primärer CTA „Entsperren", sekundär „Passwort verwenden") und ruft `authenticate(localizedReason: 'Bitte bestätige deine Identität, um WorkTime zu öffnen.')`. Erfolg → Shell; Abbruch/mehrfacher Fehlschlag → zurück zum vollständigen Login. Rein clientseitiges Gate, kein Redirect-Umbau nötig (es rendert innerhalb des bestehenden `/start`-Loaders).
- **Verweigerte/gesperrte Biometrie:** klarer Fallback-Text „Biometrie derzeit nicht möglich — bitte mit Passwort anmelden." (Anf. 17), niemals Sackgasse.
- **Plattform-Achtung:** local_auth trägt **nicht** auf Web/Desktop wie erwartet → Biometrie-CTA nur zeigen, wenn `canCheckBiometrics == true`; auf Web/Demo (`auth.authDisabled`) komplett ausblenden. `secure_application`/`FLAG_SECURE` (App-Switcher-Verschleierung, MASVS) ist ein sinnvoller Begleiter, aber optional/außerhalb dieses UX-Scopes.

### 4. „Angemeldet bleiben" & Session-Vertrauen (Anf. 28/29)

Optik-/UX-Ebene (Persistenz-Mechanik unverändert bei Firebase Auth):
- **Switch statt Zwang:** Firebase persistiert Sessions ohnehin; der Switch steuert UX-seitig, ob nach `signOut`-freiem App-Neustart direkt der Biometrie-Lock oder das volle Formular kommt. Auf **Web** default **aus** + Hinweistext „Auf gemeinsam genutzten Geräten abmelden nicht vergessen." (`appColors.info`-Banner), weil Browser-Storage laut Security-Skill kein sicherer nativer Speicher ist.
- **Sichtbarer Abmelde-Weg** überall dort, wo eine Session läuft (Profil/Einstellungen) — nie versteckt (Anf. 5).

### 5. Passwort-Reset-UX (Anf. 17/18/25)

Reset über ein `showModalBottomSheet(showDragHandle: true, isScrollControlled: true, useSafeArea: true)`-Sheet (Konvention aus CLAUDE.md), **wenige Schritte**:
1. Vorbelegtes E-Mail-Feld (`AppFormField`, übernimmt Wert aus dem Login-Feld), gleiche `_emailRegex`-Validierung wie im Login.
2. Primär-CTA „Link zum Zurücksetzen senden".
3. **Erfolg = neutraler, Enumeration-sicherer Text** (Security-Skill, kein User-Enumeration-Leak): „Falls ein Konto zu dieser E-Mail existiert, haben wir einen Link zum Zurücksetzen geschickt." → als `AppStatusBanner(tone: success)`, danach Sheet schließbar.
4. Fehler (Netz/Format) → `AppStatusBanner(tone: error)` mit konkreter Handlungsanweisung.

Ruft clientseitig den bestehenden Firebase-Reset (`sendPasswordResetEmail` über `AuthProvider`, falls dort ergänzt) — reine UI hier, kein Rules-/Functions-Touch.

### 6. Fehler-UX & Fehlervermeidung im Login (Anf. 17/18)

- **Einheitliches Fehler-Widget:** durchgängig `AppStatusBanner(tone: error)` mit `Semantics(liveRegion: true)` (in V2 bereits so) — V1s `_ErrorBanner` gilt als Legacy und wird nicht weiter gepflegt.
- **Verständliche deutsche Meldungen statt Firebase-Codes:** Mapping-Tabelle (im `AuthProvider`, hier nur UX-Vorgabe) — `wrong-password`/`invalid-credential` → „E-Mail oder Passwort ist nicht korrekt."; `user-disabled` → führt auf `AccessBlockedScreenV2`; `too-many-requests` → „Zu viele Versuche. Bitte kurz warten und erneut probieren." (Brute-Force-Backoff-Hinweis, Security-Skill Rate Limiting); `network-request-failed` → „Keine Verbindung. Bitte Internet prüfen." Nie Stacktraces/interne Details zeigen (Security-Skill Header-Hygiene).
- **Fehlervermeidung:** Inline-Validierung (schon vorhanden), `TextInputAction.next/done`-Fokuskette (vorhanden), Passwort-Anzeige-Toggle (vorhanden), Autofill-Hints (`AutofillHints.username/email/password`, im Demo-Modus bewusst aus — bereits so). Button ist während `auth.busy` disabled + Spinner (verhindert Doppel-Submit).

### 7. Just-in-time-Permission-Prompts (Anf. 29 datenschutzfreundlich)

Grundsatz Least-Privilege (Security-Skill §8): **keine** Berechtigung beim App-Start, jede Berechtigung **kontextuell** direkt vor Nutzung, mit deutschem Begründungstext **vor** dem OS-Dialog (Pre-Permission-Priming-Sheet), damit ein „Ablehnen" nicht endgültig den OS-Prompt verbrennt.

| Berechtigung | Auslöser (kontextuell) | Deutscher Begründungstext (Priming-Sheet, vor OS-Dialog) | Ablehnungs-Fallback |
|---|---|---|---|
| **Kamera** | Öffnen des Scanners (`scanner_screen.dart`) | „WorkTime nutzt die Kamera nur zum Scannen von Barcodes und EAN-Codes. Es werden keine Fotos gespeichert oder gesendet." | Manuelle Barcode-Eingabe bleibt möglich (existiert bereits) + Banner „Kamera-Berechtigung in den Einstellungen freigeben" mit Deep-Link `openAppSettings()` |
| **Push/Mitteilungen** | erst wenn Nutzer Benachrichtigungen im Profil aktiviert (nicht bei Login) | „Wir informieren dich über Schichtänderungen, Ablaufwarnungen und Nachrichten. Du kannst das jederzeit abschalten." | App voll nutzbar ohne Push; In-App-Inbox als Ersatz |
| **Standort** | nur falls je ein standortgebundenes Feature kommt — **aktuell nicht anfordern** | (n/a) | — |
| **Kontakte** | **gar nicht** — Adressbuch der App ist eigene Daten (`ContactProvider`), kein OS-Kontaktzugriff | (n/a) | — |

- **Paket:** `permission_handler` (client-only). Der `scanner_screen.dart` fängt heute den Kamera-Fehlerfall bereits sauber ab (`_cameraError`-Box, `scanner_screen.dart:199`) — das Priming-Sheet setzt **davor** an. Deutscher Begründungstext zusätzlich in `ios/Runner/Info.plist` (`NSCameraUsageDescription`) und Android-Manifest-Rationale (außerhalb Dart, aber Teil des Zielbilds).
- **Priming-Sheet-Komponente:** wiederverwendbares `AppBottomSheetScaffold` „Kamera erlauben?" mit Icon (`Icons.camera_alt_outlined`), Nutzen-Text, „Erlauben" (primär) / „Nicht jetzt". Erst „Erlauben" triggert den echten OS-Dialog.

### 8. Vertrauens-/Sicherheits-Signale in der UI (Anf. 30)

Dezente, ehrliche Signale — keine Fake-Siegel:
- **„Sicherer Zugang"-Pill** mit Schloss-Icon am Login (vorhanden, wird um Icon ergänzt).
- **Datenschutz-Footer am Login:** dezente `TextButton`-Zeile „Datenschutz · Impressum" → verlinkt auf `/datenschutz` und `/impressum` (bereits existierende statische Rechtsseiten, `PublicLegalLinks`). Schafft Transparenz + erfüllt Erwartung (Anf. 30).
- **Verschlüsselungs-Hinweis** im Einladungs-Flow: Kleintext unter dem Passwort „Deine Verbindung ist mit TLS verschlüsselt." (nur wenn `!authDisabled`).
- **Kein Marketing-Overclaiming:** Demo-Modus bleibt sichtbar als „Demo-Zugang" mit `warning`-Ton — Vertrauen entsteht durch Ehrlichkeit, dass Demo-Daten unsicher sind.
- **Konsistente Ikonografie:** Schloss/Auge/Fingerabdruck/Face überall gleich (Anf. 22) — Icon-Set in einer kleinen `_AuthIcons`-Konstante bündeln.

### 9. 2FA-Ausblick (Anf. 28, künftig)

Realistisch für Firebase Auth, ohne jetzigen Umbau — als Roadmap dokumentiert:
- **Firebase Multi-Factor Authentication (SMS/TOTP)** ist Firebase-nativ; benötigt **Blaze** (bereits die Zielumgebung laut Memory) + Aktivierung in der Firebase Console. UX-seitig: nach Passwort-Erfolg ein zusätzlicher Schritt „Bestätigungscode eingeben" (6-stelliges Code-Feld, `AppFormField` mit `TextInputType.number` + `autofillHints: [AutofillHints.oneTimeCode]` für SMS-Autofill iOS/Android) und ein Enrollment-Flow in den Einstellungen („Zwei-Faktor-Schutz aktivieren").
- **Empfehlung:** **TOTP** (Authenticator-App) bevorzugen vor SMS (SMS ist kosten- und SIM-Swap-anfällig). Enrollment zeigt QR-Code + manuellen Schlüssel.
- **Abgrenzung:** 2FA ist eine **Server-Auth-Erweiterung** (kein reines Client-UX-Thema) und daher explizit außerhalb des jetzigen „nur Optik"-Scopes — hier nur als Zielbild inkl. Screen-Skizze festgehalten, umsetzbar sobald MFA in der Firebase-Console/Blaze scharf geschaltet wird.

### 10. Barrierefreiheit, Dark Mode, Performance (Anf. 19/20/12/15)

- **Kontraste:** alle Ton-Farben aus `appColors` (WCAG-geprüfte Container-Paare, z. B. `success 0xFF187A58` auf `successContainer 0xFFDFF3EA`) — nie hardcoden.
- **Dark/Light:** komplette Auth-Familie über `AppTheme.light/dark`; Gradient-Backgrounds nutzen `withValues(alpha:)` auf Theme-Rollen (bereits so) → automatisch dark-tauglich.
- **Touch-Ziele:** CTAs `52 dp`, `IconButton`-Toggles ≥ 48 dp.
- **Screenreader:** `Semantics(header:/liveRegion:)` auf Marken-Header und Fehlerbannern (in V2 teils vorhanden, konsequent ergänzen).
- **Ladezeit/Performance:** Login ist bewusst leichtgewichtig (kein schweres Bild, nur Gradient + `AppLogo`); Biometrie-Check async ohne Blockieren des ersten Frames.


## 10. Fundament — Offline, Performance & Push

Dieser Abschnitt ist reine **UI/UX-/Struktur-Planung** — keine Änderung an Providern, Services, Models, Firestore, Functions oder Compliance-Logik. Die Datenschicht ist bereits solide: `_buildFirestoreSettings()` in `lib/main.dart` setzt die Offline-Persistenz plattformgerecht **vor dem ersten Read** (`kIsWeb`-Zweig, `CACHE_SIZE_UNLIMITED`), Push ist mit `plan/push-benachrichtigungen-plan.md` (M1–M7 code-fertig) technisch fertig. Es fehlt fast ausschließlich die **sichtbare Oberflächen-Schicht**: Offline-Kommunikation, Skeletons statt Spinner, konsistente Listen-Performance und die In-App-Push-Präferenzen als polierter Screen.

### 1. Ausgangsbefund (verifiziert im Code)

| Bereich | Status heute | Lücke (nur UI/UX) |
|---|---|---|
| Firestore-Offline-Persistenz | `lib/main.dart` `_buildFirestoreSettings()`: `persistenceEnabled:true`, `CACHE_SIZE_UNLIMITED`, Web mit Long-Polling-Autodetect — korrekt vor erstem Read | Reads kommen offline aus dem Cache, aber **kein sichtbares Signal** (kein `isFromCache`/`hasPendingWrites` irgendwo im `lib/` verwendet) |
| Konnektivität | `connectivity_plus` **nicht** in `pubspec.yaml`, kein Online-Enum, kein Reachability-Check | Kein Offline-Banner, kein Konnektivitäts-Indikator |
| Ladezustände | **32 Dateien** nutzen `CircularProgressIndicator`; **keine** Skeleton-/Shimmer-Komponente in `lib/ui/` oder `lib/widgets/` | Spinner statt struktur-erhaltender Skeletons → wahrgenommene Langsamkeit |
| Push | M1–M7 fertig (`PushMessagingService`, `NotificationPrefs`, 5 Kanäle, `NotificationSettingsScreen`), Web-SW `web/firebase-messaging-sw.js` vorhanden | Präferenz-Screen existiert, aber nicht in V2-Signal-Teal-Sprache; kein sichtbarer „letzter Push"-Kontext im Anfragen-Center |
| Web-PWA | `web/manifest.json` mit maskable 192/512-Icons, `firebase.json` liefert `index.html`/`manifest.json` mit `no-cache` — korrekt | `theme_color`/`background_color` noch Flutter-Default `#0175C2` statt Signal-Teal → Splash/Statusbar off-brand |
| Motion | `AppMotion` (short 150 / medium 300 / long 450) + `AppMotion.resolve()` respektiert `disableAnimations` | Nur konsequent nutzen, nichts fehlt |

**Kernaussage:** Die teure Mechanik (Persistenz, Push, PWA-Manifest, Reduce-Motion) ist da. Zu bauen ist die **ehrliche, sichtbare Offline-/Lade-/Push-UX** darüber — genau der UI/UX-Auftrag.

### 2. Offline-Verhaltensmatrix je Bereich (was offline lesbar / schreibbar)

Grundprofil: **Read-everywhere-offline** (Firestore-Cache) + **Write für User-Content optimistisch** (hybrid-Fallback existiert bereits im Provider-Muster), **serverpflichtige Aktionen gesperrt** statt gefälscht. Diese Matrix steuert nur, was die UI anzeigt/ausgraut — die Provider-Fallback-Logik bleibt unverändert.

| Bereich (Tab/Screen) | Offline lesbar | Offline schreibbar | Offline gesperrt (ausgegraut + Tooltip „Offline nicht verfügbar") |
|---|---|---|---|
| Heute / Zeiterfassung | Ja (Cache) | Ja — Eintrag lokal, `pending`-Chip | — |
| Schichtplan (Ansicht) | Ja | Ansehen ja | „Automatisch planen" (Callable/Compliance), „Veröffentlichen" (`publishShiftBatch`) |
| Schicht anlegen/ändern | Ja | Ja (hybrid-Fallback) | Compliance-Override-Bestätigung bleibt, aber Hinweis „ohne Netz nicht serverseitig geprüft" |
| Anfragen (Inbox) | Ja | „gelesen"-Toggle lokal | Genehmigen/Ablehnen bei Compliance-Relevanz (Schichttausch) → App-öffnen statt Silent-Write |
| Kontakte | Ja | Ja | OktoPOS-Kunden-Push (Function) |
| Warenwirtschaft / Bestand | Ja | Bestandsbewegung ja | OktoPOS-Sync, Artikel-Push (Functions) |
| Scanner | Ja (Produktlookup aus Cache) | Vormerkung ja | Preisabruf/Kassen-Aktion (Function) |
| Personal / Buchhaltung / Auswertungen | Ja (Cache) | i. d. R. lesend | DATEV-Export/PDF nur mit frischen Daten → Warnhinweis |
| Anmeldung | — | — | Login braucht Netz (Auth); Biometrie-Reauth lokal möglich |

Regel für alle Screens: **serverpflichtige Buttons offline `onPressed:null` + Tooltip**, nie klickbar-und-dann-Fehler (Skill 21, Anti-Pattern „toter Button").

### 3. Konnektivitäts-Indikator, Offline-Banner, „zuletzt aktualisiert", Optimistic/Pending

Neuer **`ConnectivityStatusProvider`** (reiner `ChangeNotifier`, kein Datenpfad) auf Basis von `connectivity_plus` **plus** entprelltem Reachability-Check (1–3 s Debounce, Recheck bei `AppLifecycleState.resumed`, im Web zusätzlich bei `visibilitychange`). Exponiert ein `enum OnlineState { online, offline, backendUnreachable }`. Konsum ausschließlich über `context.select` (kein globaler Rebuild).

**Komponenten (neu in `lib/ui/`, Signal-Teal, ThemeExtension-Tokens):**

- **`AppOfflineBanner`** — dünner (`36–40 dp`) persistenter Top-Banner unter der AppBar, **nur** wenn `!= online`. Farbe `Theme.of(context).appColors.warning` (offline) / `.info` (backendUnreachable), NIE hardcoden. Text „Offline — Änderungen werden gespeichert und später synchronisiert." Einblenden via `AnimatedSize`/`AnimatedSwitcher` mit `AppMotion.resolve(context, motion.short)`. Persistenter Banner, **keine Snackbar** (Skill 21).
- **`AppConnectivityDot`** — kleiner Status-Punkt in der AppBar/Rail-Kopfzeile (grün online / bernstein offline / grau unreachable), `AppIconSizes`-konform, Tooltip mit Klartext.
- **`AppLastUpdated`** — dezente Zeile „Zuletzt aktualisiert: vor 3 Min." unter Listen-/Detail-Headern. Relativ + lokal markiert (Geräteuhr driftet), deutsch via `DateFormat(..., 'de_DE')`. Speist sich aus Snapshot-Metadaten des jeweiligen Screens (rein Anzeige).
- **`AppPendingChip`** — `AppStatus`-Variante „Wird synchronisiert" (Uhr-Icon, `onSurfaceVariant`) an optimistisch geschriebenen Karten (Zeiteintrag/Schicht), solange `hasPendingWrites`. Optimistic-UI: Mutation sofort sichtbar, Pending-Chip bis Server-Bestätigung, klarer Rollback bei endgültigem Fehler (kein stiller Verlust).
- **Inbox-Badge** bleibt wie heute (`pendingInboxActionCount`), erhält offline den Pending-Chip nicht (Zählung ist lokal).

Platzierung im Shell-Scaffold (`home_screen.dart`) EINMAL zentral über der `StatefulShellRoute`-`IndexedStack`, damit jeder Tab den Banner erbt — nicht pro Screen kopieren.

### 4. Startzeit & Skeleton-Loader statt Spinner (Anf. 12, 15)

- **`AppSkeleton` + `AppSkeletonList`** (neu in `lib/ui/`): struktur-erhaltende Platzhalter (graue Blöcke in `surfaceContainerLow`, Radius `AppRadii.md`) mit sanftem Shimmer über `AnimatedBuilder`+`RepaintBoundary` (kein neues Package nötig; wenn doch, `skeletonizer`). Shimmer-Dauer `AppMotion.long`, respektiert `disableAnimations` → statischer Block bei Reduce-Motion. **Ersetzt die 32 `CircularProgressIndicator`-Stellen** bei Content-Ladevorgängen; Spinner nur noch für kurze imperative Aktionen (Button-Inline).
- **Skeleton-Vorlagen je Listentyp:** `AppSkeletonList.tiles` (Anfragen/Kontakte), `.stats` (Auswertungen `AppStatCards`), `.rows` (Bestand). Jede Liste zeigt beim ersten Frame ihr Skeleton, sobald der Firestore-Stream Daten liefert Cross-Fade (`AnimatedSwitcher`, `motion.medium`).
- **Time-to-First-Frame:** Gate-Loader `/start` bleibt, aber als **leichter Signal-Teal-Splash mit Logo** (kein Vollbild-Spinner). Arbeit aus dem kritischen Startpfad ist bereits ausgelagert (Provider lösen Cloud-Repos lazy auf) — UI-seitig nur den ersten sichtbaren Frame billig halten (const-Splash).
- **Schwaches Netz:** Da Reads aus dem Firestore-Cache kommen, zeigt jeder Tab beim Kaltstart sofort gecachte Daten + `AppLastUpdated` + Skeleton nur für noch nicht gecachte Bereiche. Kein Blank-Screen-Warten.

### 5. Listen-Performance, const/select, Lazy (Anf. 15, 27)

Verbindliche Checkliste für alle Redesign-Screens (Skill 10):

- **Nur `ListView.builder`/`SliverList`** für dynamische Listen (Anfragen, Kontakte, Bestand, Auswertungen). **Verboten:** `ListView(children:[...])` über Fachlisten. `itemExtent`/`prototypeItem` wo Höhen bekannt (Kontakt-Tiles, `AppKontoTile`).
- **`const`-Konstruktoren** überall möglich (leere Zustände, Icons, Trenner). V2-Komponenten aus `lib/ui/` als `const` instanziieren.
- **Rebuild-Scoping** via `context.select`/`Consumer` nur um den datenabhängigen Teilbaum; der neue `ConnectivityStatusProvider` darf **nie** einen Tab-weiten Rebuild auslösen (nur Banner/Dot selektieren).
- **`RepaintBoundary`** um Shimmer, Charts (`fl_chart`) und animierte Karten, damit Repaints isoliert bleiben.
- **Motion sparsam:** `AppMotion.short/medium` für Ein-/Ausblenden, `AppMotion.resolve()` für Reduce-Motion; keine Dauer-Animationen, keine großen `BackdropFilter`/`Opacity`-Layer (Alpha-Farbe statt `Opacity`).
- **Frame-Budget** 16 ms (60 Hz) / 8 ms (120 Hz ProMotion); Profiling nur im Profile-Mode auf echtem Low-End-Gerät.

### 6. Bild-/Asset-Budget (Anf. 16 — speicher-/datenschonend)

- **Fonts:** `assets/fonts/NotoSans-{Regular,Bold,Italic}.ttf` sind harte Abhängigkeit (PdfService). Keine zusätzlichen Font-Weights einführen; Icon-Tree-Shaking (Material-Icons) beim Build aktiv lassen.
- **Bilder:** App nutzt kaum Rasterbilder (Logo als `AppLogo`, SVG-App-Icon). Falls im Redesign Produkt-/Avatar-Bilder dazukommen: `cacheWidth`/`cacheHeight` in Dekodier-Zielgröße, für Netzbilder `cached_network_image` (Cache + Datenersparnis), niemals Volllast-Auflösung für Thumbnails.
- **Web-Bundle:** Für echtes Offline `flutter build web --no-web-resources-cdn` (CanvasKit lokal, sonst hängt Offline-Start an gstatic) — reine Build-Empfehlung, kein Code.
- **Icons/Manifest** per `?v=`-Query versioniert (bereits im Manifest: `?v=20260406`) — bei Icon-Änderung Query erhöhen.

### 7. Push-Kanäle, Frequenz-Hygiene & In-App-Präferenzen (Anf. 14)

Die 5 Kanäle stehen (`plan/push-benachrichtigungen-plan.md`): **Genehmigungen · Schichtplan · Aufgaben & Kühlschrank · Kundenwünsche · Bestand**. Frequenz-Hygiene ist serverseitig bereits umgesetzt (Bündelung je ISO-Woche, Flankenerkennung, Dedupe, Ruhezeiten). **UI-Aufgabe:** den `NotificationSettingsScreen` in die Signal-Teal-Sprache heben und Frequenz-Transparenz sichtbar machen.

- **`NotificationSettingsScreen` (V2-Umbau, reine Optik):** `AppSectionCard` „Benachrichtigungen" mit Master-Schalter obenauf, darunter 5 `AppKontoTile`-artige Zeilen (je Kanal ein Switch + deutsche Ein-Satz-Erklärung „z. B. Kühlschrank nachfüllen"). Ruhezeiten als eigener `AppSectionCard`-Block (Von/Bis-Zeitpicker). Deutlich sichtbarer Hinweis „Genehmigungen sind zeitkritisch und werden auch in Ruhezeiten zugestellt" (spiegelt Server-Logik).
- **Frequenz-Hygiene sichtbar:** je Kanal ein kleiner Hinweistext zur Häufigkeit („gebündelt, max. 1× pro veröffentlichtem Plan"), damit Nutzer Vertrauen fassen und weniger abschalten.
- **Erst-Kontext-Permission:** iOS/Android-Push-Freigabe **nicht** beim Kaltstart, sondern kontextuell nach Login/erster relevanter Aktion (bereits in M4) — UI: ein erklärendes `AppConfirmDialog`-Vorabbottom-Sheet („Warum Push?") vor dem OS-Prompt (Pre-Permission-Priming), erhöht Grant-Rate und ist datenschutzfreundlich (Anf. 29).
- **In-App-Parität:** Anfragen-Center bleibt der Tap-Zielort; persistierte `notifications` (M2) füllen die Inbox, sodass weggewischte System-Pushes in der App wiederfindbar sind.

### 8. Web-PWA / Service-Worker-Hinweise

- **Manifest-Branding:** `web/manifest.json` `theme_color`/`background_color` von `#0175C2` auf **Signal-Teal** (Seed-Farbe des V2-Themes) angleichen → korrekte PWA-Splash-/Statusbar-Farbe, `name`/`short_name` von „timework" belassen (bewusster Drei-Namen-Fall laut CLAUDE.md). Maskable-Icons 192/512 sind vorhanden.
- **SW/Caching:** `firebase.json` liefert `index.html`/`manifest.json` bereits mit `no-cache` — bestätigt korrekt gegen den „veralteter Entry-Point klebt"-Fallstrick. Nichts zu ändern.
- **`firebase-messaging-sw.js`** existiert; offener Punkt aus M6 (Web-Firebase-Config-Platzhalter) bleibt Build-Step, kein UI-Thema.
- **iOS-Safari-PWA-Hinweis:** installierte Home-Screen-PWA ist von ITP-7-Tage-Eviction ausgenommen — im Onboarding/Hilfe „Zum Home-Bildschirm hinzufügen" empfehlen (UX-Text), da Safari kein `beforeinstallprompt` kennt.
- **Inkognito/abgeschaltete IndexedDB:** App muss graceful online weiterlaufen — sicherstellen, dass die UI bei fehlender Persistenz keinen Dauer-Spinner zeigt (Skeleton → Daten → notfalls `EmptyState` mit Netz-Hinweis).

### 9. Neue/berührte UI-Artefakte (Übersicht, alle rein präsentational)

| Artefakt | Ort | Zweck |
|---|---|---|
| `ConnectivityStatusProvider` | `lib/providers/` (neu, kein Datenpfad) | entprelltes Online-Enum |
| `AppOfflineBanner` / `AppConnectivityDot` | `lib/ui/` | Offline-Kommunikation |
| `AppLastUpdated` / `AppPendingChip` | `lib/ui/` | Stale-/Pending-Transparenz |
| `AppSkeleton` / `AppSkeletonList` | `lib/ui/` | Ladezustände statt Spinner |
| `NotificationSettingsScreen` (V2-Umbau) | `lib/screens/` | Push-Präferenzen in Signal-Teal |
| `web/manifest.json` (theme/background_color) | `web/` | PWA-Branding |



# Teil C — Bereichs-Design (alle Tabs & Unterbereiche)


## 11. Bereich — Heute (Start-Tab)

> Zielbild in einem Satz: Der Start-Tab ist ein **rollenadaptives, ruhiges Tages-Cockpit** — oben „Wo stehe ich gerade?" (Hero + Status), in der Mitte „Was muss ich wissen?" (Warnungen, nächste Schicht, Fortschritt), unten in der Daumenzone „Was tue ich jetzt?" (die eine Primäraktion je Rolle: **Stempeln** bzw. **Anfragen prüfen**). Statt vier driftender Klon-Dashboards (V1/V2 × Mitarbeiter/Admin) genau **ein** V2-Bauplan je Rolle, komplett auf `lib/ui`-Komponenten und Design-Tokens.

### Design-System-Verankerung (gilt für alle Unterbereiche)
- Nur Signal-Teal-Tokens: `context.spacing` (4/8-Rhythmus: xxs/xs/sm/md/lg/xl), `context.radii`, `AppMotion`, `AppElevation`, `AppIconSizes`, `Theme.of(context).appColors` für Status (success/warning/info/error). **Kein `Color(0xFF…)`, kein `EdgeInsets.all(16/20)`, kein `BorderRadius.circular(16)` in Widgets** — das ist heute im gesamten Legacy-Zweig verletzt.
- Genau **eine** primäre CTA pro Rolle sichtbar; alles andere visuell untergeordnet (Cards/Chips/Tiles).
- Deutsch/de_DE, korrekte Umlaute überall (das ae/oe/ue-Stripping im V1-Zweig entfällt vollständig).
- Light + Dark gemeinsam entworfen; Status nie allein über Farbe (immer Icon **und** Kurztext).

---

### 1. Shell-Chrome um den Start-Tab (AppBar / Rail / BottomNav / FAB)

**Vision/Zielbild:** Konsistente obere Orientierung in **jedem** Zustand — die V1-„keine AppBar"-Lücke verschwindet, weil V1 ganz entfällt. Kompakt: schlanke transparente Top-Bar (☰ + App-Kontext + Warenkorb), unten 5er-`NavigationBar`. Mittel/Expanded: `AppNavRail`.

**Informationsarchitektur & Primäraktion:** Die Top-Bar trägt Menü (links), einen **Such-Einstieg** (neu, mittig/rechts) und Warenkorb (rechts, permission-gated). Primäraktion des Tabs liegt NICHT in der AppBar, sondern als **rollenabhängiger FAB/Bottom-CTA** (Stempeln / Anfragen).

**Mobile-Layout (Daumenzone):**
- 56dp `SafeArea`-Top-Bar (bleibt), Reihenfolge: `☰` (48dp Target, Semantics-Label „Menü öffnen", nicht nur Tooltip) · Titel „Heute" + Filial-Kurzname · `search` · `shopping_cart` mit Badge.
- BottomNav 5 Items mit Icon **und** Label, aktiver Zustand betont (`onSurface` + Indikator). „Mehr" behält sich, bekommt aber Badge-Summe der versteckten Bereiche, damit versteckte Hauptbereiche (Zeit/Kontakte/Laden) nicht „verschwinden".
- **Kontext-FAB je Rolle** in der Daumenzone: Mitarbeiter → `access_time` „Ein-/Ausstempeln"; Planer → `inbox` „Anfragen prüfen" (Badge). Ersetzt das mittige Vergraben der Primäraktion.

**Tablet/Desktop-Layout:** `AppNavRail` ab 600dp (Breakpoint bleibt `MobileBreakpoints.useNavigationRail`), volle Labels ab 840dp; endDrawer für Bereiche. Suche wandert in die Rail-Kopfzeile. Kein FAB nötig, weil Primäraktion im Hero-Bereich (breiter Button) sichtbar bleibt.

**lib/ui-Komponenten:** `AppLogo`, `SectionHeader`/`BreadcrumbAppBar`, bestehende `AppNavRail`; Suche als leichtgewichtiges `showSearch`/Sheet (kein neues Datenmodell).

**Vorher→Nachher:**
- [home_screen.dart:201](lib/screens/home_screen.dart#L201) `appBar: (useV2 && !useRail) ? _V2MenuTopBar…` → immer aktiv (V1-Zweig entfällt), Menü-Button mit `Semantics(button:true,label:'Menü öffnen')`.
- [home_screen.dart:1215](lib/screens/home_screen.dart#L1215) `tooltip 'Menü'` → zusätzlich `Semantics`-Label (Touch-Discovery).
- [home_screen.dart:321](lib/screens/home_screen.dart#L321) FAB destination-gebunden → auf `ShellTab.today` rollenabhängigen CTA-FAB liefern.
- Neu: Such-Action in `_V2MenuTopBar` ([home_screen.dart:1231](lib/screens/home_screen.dart#L1231) actions).

**Touch-Targets & Barrierefreiheit:** alle IconButtons ≥48dp; Badge zusätzlich als Semantics-Zahl. Fokus-Reihenfolge = visuelle Reihenfolge.

**Offline-Verhalten:** dünnes, entprelltes **Offline-Banner** direkt unter der Top-Bar (aus zentralem Konnektivitäts-State), Text „Offline — zuletzt aktualisiert HH:mm", `appColors.warning`-Tint, kein Layout-Sprung (reservierte Höhe 0→28dp animiert).

**Motion:** Banner ein-/ausblenden 200ms ease-out/ease-in, respektiert `MediaQuery.disableAnimations`.

**iOS/Android-nativ:** Android Predictive Back nicht blockieren (Cross-Tab-`_navHistory`/`PopScope` bleibt); iOS Swipe-Back an den Rändern frei (`drawerEdgeDragWidth` bleibt schmal). BottomNav folgt Material; auf iOS Cupertino-Scroll-Physics für die Dashboard-Liste.

---

### 2. Mitarbeiter-Dashboard (ersetzt _EmployeeDashboardTab V1+V2)

**Vision/Zielbild:** „Meine Schicht, meine Zeit, meine offenen Punkte" auf einen Blick — höchstens 6 statt bis zu 11 schweren Karten, klare vertikale Hierarchie, Stempeln immer daumennah.

**Informationsarchitektur (Reihenfolge oben→unten):**
1. `SectionHeader('Heute')` (korrekte Umlaute, Breadcrumb, optional Zurück).
2. **Hero** (`AppHeroCard`, tone neutral): nächste Schicht + Live-Stempelstatus als Badge (`AppStatus`).
3. **Warnkarte** `DashboardActionItemsCard` (siehe Unterbereich 5).
4. **Quick Actions** (`AppQuickActionCard` im `AdaptiveCardGrid`, minItemWidth 180): Krank melden · Urlaub anfragen · (Zeit erfassen, permission-gated).
5. **WeekStrip** (`_EmployeeWeekStripV2` — bleibt, ist schon AppSectionCard).
6. **Wochenfortschritt** (neu getokent, siehe 7) + **Monats-Stat-Cards** (`AppStatCard`).
7. „Nächste Schichten" + „Letzte Einträge" (`AppSectionCard`, take(5), Tiles tappbar).

Die **Stempeluhr** verlässt die Mitte der Liste: kompakter Status im Hero, ausführliche Bedienung im **Stempel-Sheet** über den FAB → kurze Scrollstrecke, Primäraktion in der Daumenzone.

**Mobile-Layout:** eine `ListView` mit `RefreshIndicator` (Pull-to-Refresh, heute komplett fehlend). CTA-FAB „Stempeln". `AdaptiveCardGrid` bricht auf 1 Spalte um.

**Tablet/Desktop-Layout:** ab 840dp zweispaltig (Hero + Warnungen links, Fortschritt/Stats rechts) via `LayoutBuilder`; `ConstrainedBox(maxWidth 1100)` bleibt gegen zu lange Zeilen.

**lib/ui-Komponenten:** `AppHeroCard`, `AppQuickActionCard`, `AppSectionCard`, `AppStatCard`, `AppStatus`, `AppEmptyState`, `EmptyState`.

**Vorher→Nachher:**
- [home_screen_tabs.dart:12-202](lib/screens/home_screen_tabs.dart#L12) `_EmployeeDashboardTab` (V1) → **gelöscht**; buildHomeTab ruft nur noch die V2-Klasse.
- [home_screen_tabs.dart:63](lib/screens/home_screen_tabs.dart#L63) `'Naechste …'` u. 16 weitere ae/oe/ue-Literale → korrekte Umlaute (bereits in V2 vorhanden, wird kanonisch).
- [home_dashboards_v2.dart:148](lib/screens/home_dashboards_v2.dart#L148) `_ClockInOutWidget` verbatim → durch **kompakten Hero-Status + FAB-Sheet** ersetzt.
- [home_screen_tabs.dart:54](lib/screens/home_screen_tabs.dart#L54) / [home_dashboards_v2.dart:55](lib/screens/home_dashboards_v2.dart#L55) nackte `ListView` → `RefreshIndicator`.

**Touch-Targets & Barrierefreiheit:** jede QuickAction/Tile mit `Semantics(button:true,label:…)`; Hero-Statuszeile als `MergeSemantics` („Nächste Schicht … · Nicht eingestempelt"). Dynamic Type bis 200% ohne Bruch (Umbruch statt `TextOverflow.ellipsis` bei Titeln).

**Offline-Verhalten:** WeekStrip/Schichten/Einträge lesen aus dem lokalen Cache (hybrid/local); Stale-Hinweis im Banner (Unterbereich 1). Pull-to-Refresh löst nur Re-Read aus, schreibt nichts.

**Motion:** Listen-Karten gestaffelt 30–50ms beim ersten Aufbau (`flutter_animate` optional/sparsam), einmalig; Reduce-Motion → sofort sichtbar.

**Formulare:** keine eigenen — Quick Actions öffnen die bestehenden Sheets (`showAbsenceRequestSheet`, `EntryFormScreen`) unverändert.

**iOS/Android-nativ:** iOS `BouncingScrollPhysics`, Android Overscroll-Glow; Haptik (leicht) beim erfolgreichen Stempeln.

---

### 3. Admin/Teamlead-Dashboard (ersetzt _AdminDashboardTab V1+V2)

**Vision/Zielbild:** Filial-Leitstand — Ausnahmen zuerst, dann Kennzahlen mit Weg zur Ursache, dann Plan/Entscheidungen. Kein Sackgassen-Verhalten (V1-Tiles ohne onTap entfällt).

**Informationsarchitektur:** Header → `_PlannerHeroCardV2` (Hero accent) → Warnkarte → Quick Actions (Plan öffnen · Team verwalten · Anfragen prüfen) → **Metric-Grid mit Drill-down** → „Heute priorisieren" (tappbar) → „Nächste Schichten" (take 8) → „Nächste Entscheidungen" → Team-Kalender (siehe 8, entdichtet).

**Mobile-Layout:** Primäraktion Planer = „Anfragen prüfen" als CTA-FAB (Badge). Metric-Grid `AdaptiveCardGrid(minItemWidth 155)` → 2 Spalten mobil.

**Tablet/Desktop (Master-Detail):** ab 840dp Metriken + Priorisieren links, Team-Kalender als eigenes Detail-Panel rechts (statt gequetscht in eine Karte). Breakpoints 600/840.

**lib/ui-Komponenten:** `AppHeroCard(accent)`, `AppQuickActionCard`, `AppMetricCard`, `AppSectionCard`, `AppStatus`.

**Vorher→Nachher:**
- [home_screen_tabs.dart:916-1127](lib/screens/home_screen_tabs.dart#L916) `_AdminDashboardTab` (V1) → **gelöscht**.
- [home_screen_tabs.dart:1065](lib/screens/home_screen_tabs.dart#L1065) `_ActionStateTile` ohne onTap → V2-Verlinkung ([home_dashboards_v2.dart:733](lib/screens/home_dashboards_v2.dart#L736)) wird einzige Wahrheit → keine Verhaltensdivergenz mehr.
- [home_dashboards_v2.dart:689-719](lib/screens/home_dashboards_v2.dart#L689) `AppMetricCard` → `onTap`-Drill-down ergänzen (Offene Abwesenheiten→Inbox, Noch offen/Unbesetzt→Plan, Aktive Mitarbeiter→Team). Rein Navigation, keine Logikänderung.

**Touch-Targets & Barrierefreiheit:** Metric-Cards werden tappbar → `Semantics(button:true,label:'Offene Abwesenheiten: 3, öffnet Anfragen')`; ganze Kachel ≥48dp hoch.

**Offline-Verhalten:** Kennzahlen aus lokalem Cache berechnet; Drill-down-Ziele funktionieren offline (nur Navigation).

**Motion:** Zahlwechsel in Metric-Cards ohne Layout-Sprung (`FontFeature.tabularFigures`), kein Zähl-Effekt (Ablenkung).

**iOS/Android-nativ:** wie Unterbereich 2.

---

### 4. Hero-Karten (Mitarbeiter + Planer)

**Vision/Zielbild:** Der erste Blickfang beantwortet „mein Status jetzt". Mitarbeiter-Hero zeigt nächste Schicht + **Stempelstatus-Badge** und einen breiten Primär-Button „Einstempeln" (Desktop/Tablet, wo kein FAB). Planer-Hero zeigt Tages-Kennzahlen verdichtet.

**IA & Primäraktion:** Mitarbeiter → Stempeln; Planer → Anfragen prüfen. Sekundäres (Datum, Standort) als `InfoChip`.

**lib/ui:** `AppHeroCard` (tone neutral/accent, Teal-Gradient, Radius xxl36), `AppStatus`, `InfoChip`.

**Vorher→Nachher:** `_EmployeeHeroCardV2`/`_PlannerHeroCardV2` bleiben Struktur, bekommen die Stempel-Status-Badge (Live via `provider.hasActiveClockSession`) + optionalen breiten CTA-Button für ≥840dp.

**Barrierefreiheit:** Zahlen tabular; Gradient-Kontrast in Light+Dark ≥4.5:1 gegen Text prüfen (helle Container-Töne, dunkler Text — passt).

---

### 5. DashboardActionItemsCard (Warnungen/Aktionspunkte)

**Vision/Zielbild:** Eine severity-sortierte, screenreader-fassbare Warnliste; überfällig vs. bald fällig auch ohne Farbe unterscheidbar.

**Vorher→Nachher:**
- [dashboard_action_items_card.dart:188-189](lib/widgets/dashboard_action_items_card.dart#L188) Icon-Badge `width/height:32` hartkodiert → `context.iconSizes`/`spacing`-Token; Zeile bleibt minHeight 48.
- [dashboard_action_items_card.dart:82-115](lib/widgets/dashboard_action_items_card.dart#L82) overdue vs. dueSoon identisches Icon `shopping_bag_outlined` → **verschiedene Icons** (overdue: `error_outline`, dueSoon: `schedule`) + Präfix-Text „Überfällig:"/„Bald fällig:" → Redundanzprinzip (nicht nur Farbe).
- [dashboard_action_items_card.dart:126-145](lib/widgets/dashboard_action_items_card.dart#L126) Column → `Semantics(header)` „N Hinweise" + Liste als `Semantics(container:true)`.

**Touch/A11y:** ganze Zeile `InkWell` ≥48dp, `Semantics(button:true)`; Status via `appColors.error`/`appColors.warning` + Icon + Wort.

**Motion:** Ein-/Ausblenden der Karte, wenn Warnungen wegfallen, per `AnimatedSize` 200ms.

---

### 6. Stempeluhr (heute _ClockInOutWidget, künftig Hero-Status + Stempel-Sheet)

**Vision/Zielbild:** Die wichtigste Mitarbeiter-Aktion ist immer daumennah (FAB) und stilkonform. Status (Ein/Aus, Dauer live) im Hero; die volle Bedienung (Beginn/Ende/Pause/Korrigieren) im **Sheet**.

**IA & Primäraktion:** FAB „Ein-/Ausstempeln" → `AppBottomSheetScaffold`-Sheet mit großem Toggle-Button (`Size.fromHeight` ≥56dp), Stat-Tiles, „Korrigieren" sekundär.

**Mobile-Layout:** FAB in Daumenzone; Sheet öffnet aus der Quelle (Scrim 40–60%). Disabled-Zustände **proaktiv erklärt** (Chip „Check-in nur während der Schicht möglich" / „Primärstandort erforderlich") **vor** dem Tap statt Fehltext danach.

**lib/ui:** `AppBottomSheetScaffold`, `AppCard`, `AppStatus`, `AppStatCard`, `AppConfirmDialog` (für Korrektur-Verwerfen).

**Vorher→Nachher:**
- [home_screen_tabs.dart:204-482](lib/screens/home_screen_tabs.dart#L204) `_ClockInOutWidget` (rohe `Card` + `EdgeInsets.all(20)` + `BorderRadius.circular(16)`) → Inhalt in `AppCard`/Tokens; Bedienung ins Sheet.
- [home_screen_tabs.dart:386-423](lib/screens/home_screen_tabs.dart#L386) Button-Row tief in der Card → FAB + Sheet-CTA.
- [home_screen_tabs.dart:373-433](lib/screens/home_screen_tabs.dart#L373) zwei nachgelagerte Umlaut-gestrippte Hinweistexte → ein proaktiver Bedingungs-Chip mit korrekten Umlauten.
- [home_screen_tabs.dart:379/427](lib/screens/home_screen_tabs.dart#L379) `'waehrend…moeglich'`, `'Primaerstandort'` → korrekt.

**Touch/A11y:** Toggle-Button ≥56dp, `Semantics(button:true,label: isClockedIn?'Ausstempeln':'Einstempeln')`; Status als `appColors.success` + Icon + Wort „Eingestempelt".

**Offline-Verhalten:** Stempeln schreibt lokal (hybrid/local-Fallback bleibt in der Logik unangetastet); UI zeigt Pending-Zustand + „wird synchronisiert" statt Fehler.

**Motion:** Statuswechsel (aus→ein) 200ms Farb-/Icon-Cross-Fade, keine Größenänderung die Nachbarn schiebt.

**Formulare (Korrektur-Dialog):** Label pro Feld, Fehler unter dem Feld mit Ursache+Lösung, Bestätigung vor Verwerfen (`AppConfirmDialog`), destruktives Zurücksetzen mit Undo-Hinweis.

**iOS/Android:** leichte Haptik bei Erfolg; iOS-Sheet mit Grabber (Drag-Handle vorhanden).

---

### 7. Wochenfortschritt (_WeeklyProgressWidget)

**Vision/Zielbild:** Ruhiger Ist/Soll-Balken ohne Flackern/Layout-Sprung.

**Vorher→Nachher:**
- [home_screen_tabs.dart:639-817](lib/screens/home_screen_tabs.dart#L639) rohe `Card` → `AppSectionCard`/Tokens.
- [home_screen_tabs.dart:801-808](lib/screens/home_screen_tabs.dart#L801) 3px-Ladebalken am Ende + Wert-Sprung ([:713 fallbackTarget](lib/screens/home_screen_tabs.dart#L713)) → **Skeleton** (reservierter Platz, `AspectRatio`/feste Höhe) statt Fallback→Echt-Sprung; Balken erscheint erst mit echtem Wert.
- [home_screen_tabs.dart:781-782](lib/screens/home_screen_tabs.dart#L781) `'verknuepft'` → korrekt.

**A11y:** `Semantics(value:'12 von 20 Stunden')` auf dem Balken; Fortschritt tabular; `appColors.success`.

**Motion:** Balken animiert 250ms ease-out beim ersten Wert, danach ohne Re-Animation bei Rebuild.

---

### 8. Team-Kalender (_TeamCalendarWidget)

**Vision/Zielbild:** Auf kleinen Screens kompakt/scrollbar, auf Tablet/Desktop als Detail-Panel.

**Mobile-Layout:** horizontal scrollbare Wochen-Chips statt gequetschter 7-Spalten-Matrix; Tag-Tap öffnet Detail-Sheet.

**Tablet/Desktop:** volle 7-Tage-Matrix als rechtes Master-Detail-Panel (Breakpoint 840).

**Vorher→Nachher:**
- [home_screen_tabs.dart:1129/1226](lib/screens/home_screen_tabs.dart#L1129) rohe `Card` + `EdgeInsets.all(16)` → `AppSectionCard`/Tokens; responsive Umschaltung via `LayoutBuilder`.
- [home_dashboards_v2.dart:783](lib/screens/home_dashboards_v2.dart#L783) Einbettung bleibt, Widget selbst wird getokent.

**A11y:** jede Tages-Zelle `Semantics(label:'Montag, 2 Schichten, 1 Abwesenheit')`; Farbe nie allein.

---

### 9. Schicht-Detail-Sheet (_showShiftDetailsSheet)

**Vision/Zielbild:** V2-konformes Sheet mit Undo-sicherer Tausch-Aktion.

**Vorher→Nachher:**
- [home_screen.dart:1462/1516](lib/screens/home_screen.dart#L1462) rohes `showModalBottomSheet` + `Container(BorderRadius.circular(16))` → `showAppBottomSheet`/`AppBottomSheetScaffold`.
- [home_screen.dart:1547-1551](lib/screens/home_screen.dart#L1547) `requestShiftSwap` direkt bei Tap → **`AppConfirmDialog`** davor + `SnackBar` mit „Rückgängig".

**A11y/Touch:** CTA ≥48dp, Statusbadge `AppStatus` mit Icon+Wort.

---

### Querschnitt: Suche & Filter (Anforderung 24)
Leichter Such-Einstieg in der Top-Bar (Unterbereich 1) öffnet ein `showSearch`/Sheet über die bereits geladenen Listen (Schichten, Einträge, Warnungen) — **reine Client-Filterung** der schon vorhandenen Provider-Daten, kein neuer Query/Index. Löst die abgeschnittenen `take(5)/take(8)`-Listen ([home_screen_tabs.dart:170](lib/screens/home_screen_tabs.dart#L170), [:1094](lib/screens/home_screen_tabs.dart#L1094)) ohne Tab-Wechsel.

### Querschnitt: Push (14) / sichere Anmeldung (28) / Datenschutz (29)
- Push bleibt server-getriggert (bestehend); der Tab zeigt nur die resultierenden Warnungen/Badges — keine UI-Änderung an der Push-Logik, nur konsistente Badge-Darstellung.
- Anmeldung/2FA/Biometrie liegen im Gate/Auth-Bereich außerhalb dieses Tabs; hier nur konsistente, vertrauenswürdige Optik.
- Keine neuen Berechtigungen durch dieses Redesign (nur Optik/Layout).


## 12. Bereich — Plan (Schichtplan)

> Zielbild in einem Satz: **Aus zwei divergenten UIs (Desktop-Pixelraster für Admins, Card-Liste für Mitarbeiter) wird ein einziges, mobile-first, Signal-Teal-konsistentes Schichtplan-Erlebnis** — auf dem Handy eine daumenfreundliche Tages-/Agenda-Ansicht mit unterer Aktionsleiste, ab Tablet/Desktop ein aufgeräumtes Wochen-Board bzw. Master-Detail-Layout. Nur Optik/Layout/Struktur/UX; keine Provider-/Service-/Model-/Compliance-Änderung.

### Leitplanken für diesen Bereich
- **Nur UI-Baum + Theme-Tokens.** `ShiftPlannerScreen`, `_AdminShiftPlannerBoard`, `_ShiftEditorSheet`, `planner_cells.dart`, `staffing_profile_screen.dart` werden umgebaut, aber jeder Provider-Call (`generatePlannedShifts`, `proposeAutoAssignment`, `applyAutoPlan`, `saveShifts`, `saveAbsenceRequest`), jede Serialisierung und die Compliance-Karten bleiben verhaltensidentisch.
- **Design-System V2 statt Klon-Helfer:** durchgängig `lib/ui/ui.dart` (`AppSegmented`/`AppFilterChip`/`AppCard`/`AppSectionCard`/`AppBottomSheetScaffold`/`AppFormField`/`AppStatusBadge`/`AppStatusBanner`/`AppEmptyState`/`AppConfirmDialog`) und Tokens (`context.spacing/radii/motion/elevation/iconSizes`, `Theme.of(context).appColors`). Ziel: `grep 'ui/ui.dart'` in beiden Plan-Dateien > 0 (aktuell 0).
- **Ein Kalender-Idiom:** die drei parallelen Kalenderdarstellungen (`TableCalendar` [shift_planner_screen.dart:472-538], eigener Mini-Kalender [2196-2286], eigenes Monatsgitter [4284-4690]) werden auf **einen** wiederverwendbaren `_PlanMonthGrid` (V2-getont) reduziert. `TableCalendar`-Package entfällt in diesem Bereich.
- **Deutsch/de_DE, Status-Farben nur aus `appColors`, Dark+Light gemeinsam entworfen.** Alle „gespelltes-Umlaut"-Strings, die in Tests/PDF gematcht werden, bleiben unverändert; nur reine Anzeige-Strings ohne Match-Abhängigkeit werden auf echte Umlaute korrigiert (z. B. `Veroeffentlichen`→`Veröffentlichen` [1961], `Kalender-Menue`→`Kalender-Menü` [2039]) — vor Umbenennung je String per grep prüfen, dass kein Test/PDF darauf matcht.

### Globale Informationsarchitektur des /plan-Tabs
Ein einziger Screen-Rahmen für **beide** Rollen, der nur den Inhaltsbereich variiert (keine zwei getrennten UI-Welten mehr):

```
┌ AppBar (BreadcrumbAppBar): "Schichtplan"  [Suche-Icon] [Overflow ⋮]
├ Kontext-Kopf (AppHeroCard, kompakt): Datumsbereich + Ansicht-Umschalter (AppSegmented Tag/Woche/Monat)
├ Filterleiste (nur Admin/Teamlead): AppFilterChip-Reihe + aktive Chips  ← einklappbar
├ INHALT (rollen-/breakpoint-abhängig):
│   • Handy:  Agenda-/Tagesansicht (vertikale Liste, kein Pixelraster)
│   • Tablet+: Wochen-Board (Master) bzw. Master-Detail
├ Offline-/Sync-Banner (AppStatusBanner) bei degradiertem Zustand
└ Untere Aktionsleiste / FAB (Daumenzone):
    - Mitarbeiter: FAB "Abwesenheit melden"
    - Admin/Teamlead: primärer FAB "Neue Schicht" + BottomAppBar-Aktionen (Auto-Plan · Woche kopieren · Veröffentlichen)
```

**Eine primäre CTA pro Rolle/Screen:** Mitarbeiter → „Abwesenheit melden"; Admin → „Neue Schicht" (FAB), „Veröffentlichen" ist die prominente Sekundäraktion in der BottomAppBar (nicht mehr grüner Custom-InkWell).

---

### Sub-Bereich 1 — Rollen-Verzweigung + Mitarbeiter-Ansicht („Meine Schichten")
Dateien: [shift_planner_screen.dart:108-668](lib/screens/shift_planner_screen.dart#L108)

**Vision/Zielbild:** Eine einzige, ruhige Agenda-Ansicht der eigenen Schichten + Abwesenheiten, die dieselbe visuelle Sprache wie das Admin-Board nutzt (gleiche Karten, gleiche Segmented-Control, gleicher Kalender) — nur mit reduziertem Funktionsumfang.

**Informationsarchitektur & Primäraktion:** Kopf (Breadcrumb + Titel „Meine Schichten") → `AppSegmented` (Tag/Woche/Monat) → Datums-Navigator → Abschnittskarten „Schichten" und „Abwesenheiten". Primäraktion „Abwesenheit melden" als FAB unten rechts; „Schicht anlegen"/„Woche kopieren" erscheinen für Mitarbeiter gar nicht (Permission-Gate wie bisher).

**Mobile-Layout:** Statt Wrap aus 6 gleichrangigen Buttons [289-461] eine `AppSegmented`-Zeile oben (Tag/Woche/Monat) + kompakter Datums-Navigator (`‹ Heute ›`) + `AppEmptyState` wenn leer. Primäraktion in die Daumenzone (`FloatingActionButton.extended`, „Abwesenheit melden"), Export ins AppBar-Overflow-Menü.

**Tablet/Desktop-Layout:** `ConstrainedBox(maxWidth ~1180)` bleibt; ab 840 dp zweispaltig (Schichten links, Abwesenheiten rechts) via `LayoutBuilder`. Monatsansicht nutzt denselben `_PlanMonthGrid` wie der Admin — kein `TableCalendar` mehr.

**Genutzte lib/ui-Komponenten:** `AppSegmented` (Ansicht), `AppSectionCard` (Schichten/Abwesenheiten), `AppEmptyState` (statt `_PlannerEmptyState`), `AppStatusBadge` (Schicht-/Abwesenheitsstatus), `AppHeroCard` (Kontext-Kopf), `AppStatusBanner` (Offline).

**Vorher→Nachher:**
| Vorher | Nachher |
|---|---|
| Zwei fundamental verschiedene UIs je Rolle [165-221] vs. [223-667] | Ein Screen-Rahmen; nur Inhaltsbereich variiert nach Permission |
| `TableCalendar`-Card [472-538] | gemeinsamer `_PlanMonthGrid` (V2), identisch zum Admin |
| Wrap aus 6+ Controls, Primäraktion mittig [289-461] | `AppSegmented` + FAB in Daumenzone |
| Tote Admin-Fallback-Dropdowns feste Breiten 280/220/200 [324-400] | entfernt (Admin-Pfad returnt ohnehin früh bei :166) |

**Touch-Targets & Barrierefreiheit:** alle Umschalter/Buttons ≥48 dp (SegmentedButton erfüllt das nativ). `Semantics(button:true, label:)` an FAB und Karten-Aktionen. Kartenstatus zusätzlich als Text/Icon, nicht nur Farbe.

**Offline-Verhalten:** `AppStatusBanner(tone: warning, "Offline — zuletzt aktualisiert HH:mm")` wenn kein Netz; eigene Schichten sind read-only aus dem lokalen Cache voll sichtbar. „Abwesenheit melden" bleibt bedienbar (hybrid-Fallback schreibt lokal), Button zeigt bei Offline `helperText` „Wird gesendet, sobald wieder online".

**Motion:** Ansichtwechsel als kurze `AnimatedSwitcher` (context.motion.short, `AppMotion.resolve`), FAB mit `spring`-Einblendung; Reduce-Motion → `Duration.zero`.

**iOS/Android-nativ:** Swipe-Back (iOS) nicht blockieren; auf iOS FAB-Position identisch, aber `CupertinoScrollBehavior` für Bounce-Physics via `.adaptive` an ListView.

---

### Sub-Bereich 2 — Admin-Board Toolbar (kompakt + weit)
Dateien: [shift_planner_screen.dart:1528-1965](lib/screens/shift_planner_screen.dart#L1528)

**Vision/Zielbild:** Aus zwei getrennten Breakpoint-Aufbauten + Custom-Pills + grünem Custom-InkWell wird **eine** tokenisierte Toolbar mit klarer Hierarchie: Navigation oben, Umschalter als `AppSegmented`, kritische Aktionen unten in der Daumenzone.

**Informationsarchitektur & Primäraktion:** Kopf = Datums-Navigator (`‹ Bereich ›` + „Heute") + `AppSegmented` (Ansicht) + `AppSegmented` (Layout Mitarbeiter/Standort). Primäraktion „Neue Schicht" als FAB; „Veröffentlichen", „Automatisch planen", „Woche kopieren" in einer `BottomAppBar` (mobil) bzw. rechts in der Toolbar (Desktop) — als echte `FilledButton`/`OutlinedButton`, nicht als InkWell.

**Mobile-Layout:** Keine horizontal scrollende rechtsbündige Button-Row mehr [1786-1908]. Stattdessen: schlanke Kopfzeile (Datum + Ansicht-Segmented) und eine **`BottomAppBar`** mit den 3 Kernaktionen + zentralem FAB „Neue Schicht". „Veröffentlichen" bekommt einen Zähler-Badge (Anzahl unveröffentlichter Schichten) und `AppStatusTone.success`-Färbung über Theme, nicht hartcodiert.

**Tablet/Desktop-Layout:** Ab 840 dp eine einzeilige Toolbar: links Navigator+Heute, mittig Ansicht/Layout-Segmented, rechts `OutlinedButton`(Auto-Plan) · `OutlinedButton`(Woche kopieren) · `FilledButton`(Neue Schicht) · `FilledButton.tonal`→`FilledButton`(Veröffentlichen, success-getont). Kein `reverse:true`-ScrollView.

**Genutzte lib/ui-Komponenten:** `AppSegmented` (Ansicht **und** Layout — ersetzt beide PopupMenu-Pills), Material-`FilledButton`/`OutlinedButton`/`FloatingActionButton`, `AppStatusBadge` (Zähler an „Veröffentlichen").

**Vorher→Nachher:**
| Vorher | Nachher |
|---|---|
| Ansicht/Layout als PopupMenu-Pill [1650-1698 / 1795-1843] | `AppSegmented` (gleich wie Mitarbeiter-Ansicht) |
| Grüner Custom-InkWell mit BoxShadow als „Veröffentlichen" [1875-1905] | `FilledButton` (success-getont via Theme), echter Fokus/Splash/Disabled/Semantics |
| Kritische Aktionen in horiz. Scroll-Row [1786-1908] | BottomAppBar (mobil) / feste Toolbar-Row (Desktop) |
| „Automatisch planen" doppelt [1620-1635 vs. 1929-1932] | genau ein Einstieg (FAB-Menü/BottomAppBar), im Overflow nur Zweitweg |
| Keine daumenerreichbare Primäraktion mobil | FAB „Neue Schicht" + BottomAppBar |

**Touch-Targets & Barrierefreiheit:** alle Aktionen ≥48 dp; „Veröffentlichen"/„Neue Schicht" als echte Buttons mit `Semantics`-Rolle und Disabled-State (Opacity 0.38). Zähler-Badge zusätzlich als `Semantics`-Label („3 unveröffentlichte Schichten").

**Offline-Verhalten:** „Veröffentlichen"/„Automatisch planen" (Cloud-Pfade) bei Offline sichtbar deaktiviert mit Tooltip „Nur online möglich"; „Neue Schicht"/Bearbeiten bleiben (lokaler Fallback).

**Motion:** BottomAppBar/FAB folgen Material-3-Standard; Umschalt-Feedback via State-Layer, kein Layout-Shift. Reduce-Motion respektiert.

**iOS/Android-nativ:** Auf iOS BottomAppBar-Höhe + `SafeArea`-Bottominset (Home-Indicator); Predictive-Back (Android) und Swipe-Back (iOS) unangetastet.

---

### Sub-Bereich 3 — Filterleiste (6 Popup-Pills + aktive Chips)
Dateien: [shift_planner_screen.dart:2637-2862](lib/screens/shift_planner_screen.dart#L2637), [3798-3844](lib/screens/shift_planner_screen.dart#L3798)

**Vision/Zielbild:** Aus 6 gleich aussehenden, ~40 dp hohen Custom-Popup-Pills ohne Suche wird eine echte, tokenisierte Filter-Ebene mit **Freitext-Suche** und `AppFilterChip`-Reihe; aktive Filter jederzeit sichtbar und einzeln entfernbar.

**Informationsarchitektur & Primäraktion:** Zeile 1 = Suchfeld (`AppFormField` mit `prefixIcon: search`) für Mitarbeiter/Schicht-Titel. Zeile 2 = `AppFilterChip`-Reihe (Standort/Arbeitsbereich/Mitarbeiter/Funktion/Abwesenheit/Status); Auswahl öffnet ein `showAppBottomSheet` mit durchsuchbarer Mehrfachauswahl statt PopupMenu. Zeile 3 = aktive Chips mit `onDeleted` + „Alle zurücksetzen"-`TextButton`.

**Mobile-Layout:** Filterchips horizontal scrollbar (`SingleChildScrollView`), aber jeder Chip ≥48 dp (Material-Chip mit `VisualDensity`/Padding aus Tokens). Auswahl-Sheets sind bottom-sheets mit Suchfeld — kein winziges PopupMenu über hunderte Mitarbeiter.

**Tablet/Desktop-Layout:** ab 600 dp `Wrap` statt Scroll; Suchfeld links fixiert, Chips rechts. Optional als einklappbares Filterpanel im Master-Bereich.

**Genutzte lib/ui-Komponenten:** `AppFilterChip` (ersetzt `_filterPill`), `AppFormField` (Suche), `showAppBottomSheet`/`AppBottomSheetScaffold` (Auswahl mit Suche), `AppEmptyState` (leere Trefferliste im Sheet).

**Vorher→Nachher:**
| Vorher | Nachher |
|---|---|
| Keine Freitext-Suche, PopupMenu über alle Mitglieder [2704-2723] | Suchfeld + durchsuchbares Auswahl-Sheet (Anforderung 24) |
| `_filterPill` ~40 dp, dicht [3805-3843] | `AppFilterChip` ≥48 dp, 8 dp Abstand |
| 6 identische Pills ohne Hierarchie [2659-2792] | Suche visuell führend, Chips gruppiert; aktive Chips separat |
| Pills keine echten Buttons (kein Semantics) | `FilterChip` mit Rolle/`selected`-Ankündigung |

**Touch-Targets & Barrierefreiheit:** Chips ≥48 dp; `selected`-Zustand wird vom Screenreader angesagt; aktive Chips mit `Semantics`-`onDelete`-Hinweis („Filter Standort entfernen").

**Offline-Verhalten:** Filtern/Suchen ist rein clientseitig auf bereits geladenen Daten → voll offline nutzbar.

**Motion:** Chip-Auswahl mit `spring`-State-Layer; aktive-Chip-Einblendung gestaffelt 30 ms, Reduce-Motion → aus.

**Formulare:** Suchfeld mit `helperText` „Name oder Schichttitel", `textInputAction: search`; Auswahl-Sheet ohne Pflicht — jederzeit abbrechbar.

**iOS/Android-nativ:** Suchfeld nutzt native Keyboard-Toolbar; auf iOS Cupertino-Such-Cancel-Verhalten via Clear-Suffix.

---

### Sub-Bereich 4 — Board-Raster (Wochen/Tag): Header, freie/planmäßige Schichten, Zellen
Dateien: [shift_planner_screen.dart:1440-1480](lib/screens/shift_planner_screen.dart#L1440), [2864-3165](lib/screens/shift_planner_screen.dart#L2864), [planner_cells.dart:87-313](lib/screens/shift_planner/planner_cells.dart#L87)

**Vision/Zielbild:** Der Kern. Auf dem Handy **kein** horizontal scrollendes Pixelraster mehr, sondern eine vertikale **Tages-Agenda** (ein Tag = eine Liste von Schichtkarten je Mitarbeiter/Standort). Ab Tablet bleibt das Wochen-Board erhalten, aber tokenisiert, mit Semantics und ohne CustomPaint-Deko-Overhead. Drag&Drop wird durch eine sichtbare, entdeckbare „Kopieren/Verschieben"-Aktion **ergänzt** (nicht ersetzt).

**Informationsarchitektur & Primäraktion:**
- **Handy (Tag-Ansicht als Default bei <600 dp):** oben Tag-Auswahl (`‹ Mo 01.07. ›`), darunter Abschnitte „Freie Schichten" (falls vorhanden, `AppStatusTone.warning`-Akzent) und je Zeile eine `AppCard`-Schichtkarte mit Titel/Zeit/Standort/Status. Primäraktion je Zelle „+ Schicht" als klar sichtbarer `OutlinedButton`/`ListTile`-Add, nicht nur Quick-Add-Icon.
- **Woche (Tablet+):** Raster bleibt, aber Spaltenbreite `LayoutBuilder`-basiert (mind. 176 dp, sonst weniger Tage sichtbar mit Seiten-Snapping) statt fixer `SizedBox`-Gesamtbreite.

**Mobile-Layout:** Ersetzt das horizontal scrollende `SizedBox(width=154+days*176)` [1449-1451]. Auf <600 dp defaultet die Ansicht auf **Tag** (nicht Woche), sodass kein Zwei-Achsen-Scrollen nötig ist. Schichtkarten sind volle Breite, ≥56 dp hoch, mit `AppStatusBadge` für den Status.

**Tablet/Desktop-Layout:** 600–840 dp: 3–4 Tage sichtbar mit Wochen-Snapping; ab 840 dp volle Woche. Master-Detail optional: Tap auf Karte öffnet Detail rechts (Desktop) statt Sheet.

**Genutzte lib/ui-Komponenten:** `AppCard` (Schichtkarte statt CustomPaint-Dashed-Container), `AppStatusBadge` (Status/„frei"), `AppEmptyState` (leerer Tag), `AppSectionCard` (Tages-Sektionen mobil). Farbcodierung: statt hashCode→Palette [planner_cells.dart:481-495] ein **semantischer** Ansatz — Standort-/Team-Farbe aus einer festen, kontrastgeprüften Token-Palette + immer sichtbares Label (Farbe nie alleiniger Träger).

**Vorher→Nachher:**
| Vorher | Nachher |
|---|---|
| Horiz. Pixelraster 176 dp/Tag, ~1,5 Tage sichtbar [1449-1451] | Handy: vertikale Tages-Agenda; Tablet+: LayoutBuilder-Board mit Snapping |
| Drag&Drop (LongPress) einziger Kopier-Weg, unsichtbar [3167-3212] | zusätzlich sichtbare „Kopieren/Verschieben"-Aktion im Karten-Overflow (D&D bleibt als Beschleuniger) |
| 0 Semantics im 6155-Z-File | `Semantics` an Karten („Frühdienst, 08:00–16:00, Kiel, geplant"), Zellen, Add-Buttons |
| „Anmerkungen"-Link (help_outline) unklar [planner_cells.dart:126-155] | Label „Abwesenheiten (2)" + `event_busy`-Icon, öffnet Tagesabwesenheiten |
| Schicht-Farbe per hashCode, gedämpft, schwacher Kontrast [481-495/204-208] | kontrastgeprüfte Standort-Palette + Label; Titeltext ≥4.5:1 |
| 3-Punkt-Popup 40 dp [248-249] | Overflow-Ziel ≥48 dp (Card-Tap = öffnen, Overflow = Aktionen) |
| CustomPaint-Strichrahmen je Karte [193-197/428-462] | schlichter Border/Radius aus Tokens (weniger Paint beim Scroll) |

**Touch-Targets & Barrierefreiheit:** Schichtkarte Tap-Ziel volle Breite ≥56 dp; Overflow-Menü ≥48 dp; jede Karte `Semantics(button:true, label: "<Titel>, <Zeit>, <Standort>, <Status>")`; „frei"-Slots als `Semantics` „Unbesetzte Schicht, zum Zuweisen tippen". Kontrast in Dark+Light geprüft.

**Offline-Verhalten:** Board rendert voll aus lokalem Cache; „frei"→zuweisen und Bearbeiten funktionieren (hybrid-Fallback), Veröffentlichen/Auto-Plan bei Offline deaktiviert. „Zuletzt aktualisiert HH:mm" im Kopf.

**Motion:** Schichtkarten-Erscheinen gestaffelt (30–40 ms, nur beim Ansichtwechsel, `AppMotion.resolve`); D&D-Feedback über Material-Drag-Shadow; keine dauernden Deko-Animationen. Reduce-Motion → sofort.

**Performance:** Vertikale Agenda + Board-Zeilen als `ListView.builder`/Slivers (Virtualisierung ab ~50). `RepaintBoundary` bleibt, aber Deko-CustomPaint entfällt → weniger Paint-Kosten auf schwacher Hardware.

**iOS/Android-nativ:** iOS Bounce-Scroll via `.adaptive`; LongPress-Drag mit `HapticFeedback.selectionClick` (sparsam) beim Aufnehmen; Swipe-Back nicht durch horizontales Board-Scrollen kapern (auf Handy kein horizontales Board mehr → kein Konflikt).

---

### Sub-Bereich 5 — Monatsansicht (Sidebar/BottomSheet + Monatsgitter)
Dateien: [shift_planner_screen.dart:2004-2287](lib/screens/shift_planner_screen.dart#L2004), [4284-4690](lib/screens/shift_planner_screen.dart#L4284)

**Vision/Zielbild:** Ein einziger `_PlanMonthGrid` (V2-getont) + eine **einzige** Quelle für die Mitarbeiter/Standort-Auswahl (kein Sidebar↔BottomSheet-Klon, keine drei Kalender-Looks).

**Informationsarchitektur & Primäraktion:** Monatsgitter mit Tages-Kacheln (Schicht-Zähler/Dichte-Punkt), Tap → springt in Tag-Ansicht dieses Tages. Filter (Mitarbeiter/Standort) über die **gemeinsame** Filterleiste aus Sub-Bereich 3 statt einer separaten Checkbox-Sidebar.

**Mobile-Layout:** Vollbreites Monatsgitter; Filter über die reguläre Filterchip-Zeile (kein extra „Kalender-Menü"-BottomSheet). Chevrons ≥48 dp (statt ~28 dp [2199-2215]).

**Tablet/Desktop-Layout:** ab 840 dp Master-Detail: links Monatsgitter, rechts Tagesdetails des gewählten Tages — die alte 240 dp-Sidebar-Checkboxen wandern in die einheitliche Filterleiste.

**Genutzte lib/ui-Komponenten:** gemeinsamer `_PlanMonthGrid`, `AppFilterChip` (Auswahl), `AppSectionCard` (Tagesdetail), Tokens für Zell-Radius/Abstände.

**Vorher→Nachher:**
| Vorher | Nachher |
|---|---|
| Checkbox-Listen doppelt (Sidebar [2341-2400] + Sheet [2073-2116]) | eine gemeinsame Filterleiste, kein Klon |
| Drei Kalender-Looks (TableCalendar/Mini/Monatsgitter) | ein `_PlanMonthGrid` |
| Parent-setState ∥ modalSetState [2019-2023] | ein State (Filter im Provider-Selektor/lokal, kein Doppel-State) |
| Mini-Kalender-Chevrons ~28 dp [2199-2215] | `IconButton` ≥48 dp |

**Touch-Targets & Barrierefreiheit:** Tageskacheln ≥48 dp; Chevrons ≥48 dp; jede Kachel `Semantics` „1. Juli, 3 Schichten"; Dichte-Signal zusätzlich als Zahl, nicht nur Farbpunkt.

**Offline-Verhalten:** Monatsübersicht aus lokalem Cache; Tap-Navigation offline nutzbar.

**Motion:** Monatswechsel als horizontaler `SlideTransition` (medium, Reduce-Motion → aus); Kachel-Auswahl via State-Layer.

**iOS/Android-nativ:** Monatswechsel auch per horizontalem Swipe (Android/iOS), ohne Swipe-Back zu blockieren (Swipe nur innerhalb des Gitters).

---

### Sub-Bereich 6 — Schicht-Editor-Sheet (Neu/Bearbeiten)
Dateien: [shift_editor_sheet.dart:725-1036](lib/screens/shift_planner/shift_editor_sheet.dart#L725), [2023-2160](lib/screens/shift_planner/shift_editor_sheet.dart#L2023)

**Vision/Zielbild:** Der Editor nutzt die app-weite Sheet-Chrome (`AppBottomSheetScaffold` + `showAppBottomSheet`) und echte `AppFormField`-Felder mit Inline-Validierung, statt eigener `_EditorSection`/`_PickerField`/`_EditorNoticeCard`. Fehler entstehen früh am Feld, nicht erst als SnackBar nach dem Speichern.

**Informationsarchitektur & Primäraktion:** Kopf (Titel „Neue Schicht"/„Schicht bearbeiten" + Schließen) → Template-Leiste → Abschnitte Eckdaten / Besetzung / Details (als `AppSectionCard`) → Konflikt/Compliance-Karten (`AppStatusBanner`/`AppSectionCard` mit `warning`/`error`-Ton) → fixierte Fußleiste mit einer primären CTA „Speichern" (+ sekundär „Abbrechen"). Compliance-Karten und deren Datenlogik bleiben unverändert.

**Mobile-Layout:** `AppBottomSheetScaffold` skaliert mit `MediaQuery.viewInsetsOf` (Tastatur) statt fixer 0.92-Höhe [961-963] — Fußleiste wird nie vom Keyboard verdeckt. Felder volle Breite, ≥48 dp.

**Tablet/Desktop-Layout:** ab 840 dp zweispaltige Feldanordnung (Eckdaten links, Besetzung/Details rechts) innerhalb des Sheets; auf Desktop optional als seitliches Panel statt Bottom-Sheet.

**Genutzte lib/ui-Komponenten:** `AppBottomSheetScaffold`, `AppFormField` (Titel/Pause/Zeiten-Trigger), `AppSectionCard` (Abschnitte), `AppStatusBanner` (Konflikt/Compliance), `AppConfirmDialog` (Verwerfen-Bestätigung), `AppSegmented` wo Auswahl mit wenigen Optionen.

**Vorher→Nachher:**
| Vorher | Nachher |
|---|---|
| Eigene Sheet-Struktur + `_EditorSection`/`_PickerField`/`_EditorNoticeCard` [960-1035/2044-2079] | `AppBottomSheetScaffold` + `AppFormField` + `AppSectionCard` + `AppStatusBanner` |
| Ende>Beginn/Pause nicht inline validiert, Fehler erst nach Speichern [2061-2117] | Inline-Validierung `autovalidateMode.onUserInteraction`: „Ende muss nach Beginn liegen" direkt am Feld |
| >40 rohe SnackBars „Fehler: $error" [1103/1112/1144…] | handlungsleitende Fehlertexte (Ursache + Lösung); technischer Text nur ins Log |
| Pause akzeptiert Dezimal ohne Locale-Hinweis [2108-2117] | `AppFormField` mit `helperText` „Minuten, z. B. 30", `keyboardType: number`, `inputFormatters` (nur Ziffern) → Komma/Punkt-Problem entfällt |
| Fixe 0.92-Höhe, Fußleiste vom Keyboard verdeckt [961-963] | keyboard-sichere Chrome via `viewInsets` |

**Touch-Targets & Barrierefreiheit:** alle Felder/Buttons ≥48 dp; echte `labelText` pro Feld (kein Placeholder-only); Fehlertext unter dem Feld; nach Submit-Fehler wird das erste ungültige Feld fokussiert (`FocusNode`).

**Offline-Verhalten:** Speichern nutzt den bestehenden hybrid-Fallback; bei Offline zeigt die Fußleiste `helperText` „Wird lokal gespeichert und später synchronisiert". Compliance-Preview läuft weiterhin clientseitig (offline-fähig).

**Motion:** Sheet-Einblendung Material-Standard; Fehlerkarten-Erscheinen kurzes Fade (short); keine Wackel-Animation. Reduce-Motion respektiert.

**Formulare (Pflicht/Fehlervermeidung/Fehlermeldungen):** Titel Pflicht (bleibt), zusätzlich sichtbare Pflicht-Markierung; Zeit-Plausibilität inline; Verwerfen ungespeicherter Änderungen mit `AppConfirmDialog`.

**iOS/Android-nativ:** iOS-Keyboard-„Fertig"-Toolbar; Datums-/Zeitpicker `.adaptive` (Cupertino-Wheel auf iOS, Material-Dialog auf Android); Swipe-down-to-dismiss mit Verwerfen-Schutz bei ungespeicherten Daten.

---

### Sub-Bereich 7 — Template-Leiste + Multi-Tag-Picker + Kopieren-Sheet
Dateien: [shift_editor_sheet.dart:36-188](lib/screens/shift_planner/shift_editor_sheet.dart#L36), [225-561](lib/screens/shift_planner/shift_editor_sheet.dart#L225), [563-724](lib/screens/shift_planner/shift_editor_sheet.dart#L563)

**Vision/Zielbild:** Flachere Sheet-Ketten und eine **kalendarische** Mehrfachauswahl statt Textzusammenfassung; alle Unter-Sheets teilen `AppBottomSheetScaffold`/`AppFormField`, Fehler inline statt SnackBar.

**Informationsarchitektur & Primäraktion:** Template-Picker/-Save und Kopieren-Sheet nutzen dieselbe Chrome; Multi-Tag-Auswahl über den gemeinsamen `_PlanMonthGrid` mit Mehrfachmarkierung (getippte Tage sichtbar markiert) statt verschachtelter Kopier-Sheets. Primäraktion je Sheet klar (eine CTA).

**Mobile-Layout:** Kalender-Mehrfachauswahl vollbreit, Tage ≥48 dp; ausgewählte Tage als gefüllte Kacheln + Zähler-Chip „5 Tage".

**Tablet/Desktop-Layout:** Monatsgitter + Zusammenfassungspanel nebeneinander ab 840 dp.

**Genutzte lib/ui-Komponenten:** `AppBottomSheetScaffold`, `AppFormField` (Template-Name mit Validator), gemeinsamer `_PlanMonthGrid` (Mehrfachauswahl), `AppEmptyState` (keine Templates).

**Vorher→Nachher:**
| Vorher | Nachher |
|---|---|
| Sheet öffnet Sheet öffnet Picker, unklarer Zurück-Pfad [1039-1043/602-616] | flachere Kette, konsistente Chrome, klarer Schließen/Zurück |
| Mehrfach-Tag nur als Text-Summary `_selectedDaysSummary` [602-616/2051-2056] | kalendarische Mehrfachauswahl mit sichtbaren markierten Tagen |
| Validierung als SnackBar [272-276] | inline am Feld (Template-Name Pflicht, „Bitte mind. einen Tag wählen" inline) |

**Touch-Targets & Barrierefreiheit:** Kalender-Tage ≥48 dp mit `Semantics(selected:)`; Zähler als Text.

**Offline-Verhalten:** Templates sind userContent → lokal gespiegelt, voll offline.

**Motion:** Auswahl-Toggle via State-Layer; Reduce-Motion respektiert.

**iOS/Android-nativ:** natives Sheet-Dismiss; iOS-Wheel für Einzeldatum via `.adaptive`.

---

### Sub-Bereich 8 — Auto-Planung-Vorschau-Sheet
Dateien: [shift_planner_screen.dart:715-810](lib/screens/shift_planner_screen.dart#L715), [5876-6097](lib/screens/shift_planner_screen.dart#L5876)

**Vision/Zielbild:** Statt eines blockierenden, nicht abbrechbaren Spinner-Dialogs und einer langen ungruppierten Textliste: eine erklärte, abbrechbare Ladephase (Skeleton/Fortschritt mit Text) und eine **gruppierte, scanbare** Vorschau (Zusammenfassung oben, dann pro Standort/Person zusammengefasst).

**Informationsarchitektur & Primäraktion:** Kopf mit Stat-Chips (neu/besetzt/offen/Warnungen) via `AppStatCards`/`AppStatusBadge` → gruppierte `AppSectionCard`-Abschnitte (Neu · Zuweisungen · Warnungen · Nicht-zuweisbar), je Gruppe zusammengefasst → Fußleiste „Abbrechen" + primär „Übernehmen & speichern" (`applyAutoPlan` unverändert).

**Mobile-Layout:** `AppBottomSheetScaffold`; Ladephase als erklärender Zustand („Verteile Schichten für Juli … das kann einen Moment dauern") statt `barrierDismissible:false`-Spinner [751-755] — mit Abbrechen, wo möglich (rein UI; Berechnung selbst bleibt).

**Tablet/Desktop-Layout:** ab 840 dp zweispaltig (Zusammenfassung/Chips links, Detailgruppen rechts).

**Genutzte lib/ui-Komponenten:** `AppBottomSheetScaffold`, `AppStatCards`/`AppStatusBadge` (Stat-Chips statt `_AutoPlanStat` mit hartkodiertem Alpha [6112-6124]), `AppSectionCard` (Gruppen), `AppStatusBanner` (weiche-Grenzen-Hinweis), Skeleton/`LinearProgressIndicator` mit Text.

**Vorher→Nachher:**
| Vorher | Nachher |
|---|---|
| Blockierender, nicht abbrechbarer Spinner ohne Erklärung [751-755] | erklärte Ladephase mit Text (Anforderung 12/17) |
| Lange ungruppierte Text.rich-Liste [5997-6072] | gruppierte, zusammengefasste Abschnitte pro Standort/Person |
| `_AutoPlanStat` hartkodiertes Alpha 0.12 + Akzenttext [6112-6124] | `AppStatusBadge`/`AppStatCards` (kontrastgeprüft, tokenisiert) |

**Touch-Targets & Barrierefreiheit:** Chips/Buttons ≥48 dp; Warnung-Chip mit Icon + Text (nicht nur Gelb); Ergebnis-Zusammenfassung als `Semantics`-Text („12 neue Schichten, 3 Warnungen").

**Offline-Verhalten:** Auto-Plan ist Cloud-lastig (Range-Reads); bei Offline vorher deaktivieren (Sub-Bereich 2) — hier daher kein Offline-Sonderfall.

**Motion:** Ergebnis-Einblendung kurzes Fade; Stat-Chips gestaffelt; Reduce-Motion → sofort.

**Formulare/Fehler:** Bei Fehler in der Verteilung ein handlungsleitender `AppStatusBanner` („Verteilung fehlgeschlagen — bitte Zeitraum verkleinern und erneut versuchen") statt roher SnackBar.

**iOS/Android-nativ:** iOS-Sheet-Dismiss; Abbrechen auch per Swipe-down.

---

### Sub-Bereich 9 — Besetzungs-Profil (Kassendaten-Heatmap)
Route: /besetzungs-profil (AppRoutes.staffingProfile) · Dateien: [staffing_profile_screen.dart:20-347](lib/screens/staffing_profile_screen.dart#L20)

**Vision/Zielbild:** Die Heatmap wird auf Handy lesbar (nicht nur horizontal scrollend), Werte tragen Zahl + Farbe (nicht nur Farbe), der Standort-Wechsler ist tokenisiert, und „übernehmen" bekommt eine Bestätigung.

**Informationsarchitektur & Primäraktion:** Kopf (Breadcrumb + Aktualisieren) → `AppSegmented`/`DropdownButtonFormField` (Standort) → `AppSectionCard` „Stoßzeiten & Besetzungs-Vorschlag" (Top-Liste, „übernehmen" ≥48 dp mit `AppConfirmDialog`) → `AppSectionCard` „Heatmap". Primäraktion „übernehmen" pro Vorschlag, mit Bestätigung, da es direkt `StaffingDemand` ändert.

**Mobile-Layout:** Heatmap responsiv vereinfacht — auf <600 dp Umschalter „nach Wochentag / nach Stunde" statt 34×30-Vollmatrix; Zellen mit Zahl (Ø) beschriftet. „übernehmen" als `OutlinedButton` ≥48 dp.

**Tablet/Desktop-Layout:** Vollmatrix ab 840 dp, weiterhin horizontal scrollbar aber mit Sticky-Achsenbeschriftung.

**Genutzte lib/ui-Komponenten:** `AppSectionCard`, `AppEmptyState` (bleibt), `AppConfirmDialog` (Bestätigung), `DropdownButtonFormField`/`AppSegmented` (Standort statt nackter `DropdownButton` [163-179]).

**Vorher→Nachher:**
| Vorher | Nachher |
|---|---|
| Heatmap 34×30, „übernehmen" klein, nur horiz. scrollbar [290-306/255-258] | responsiv vereinfacht mobil, Zellen ≥ Token-Größe, Buttons ≥48 dp |
| Nackter `DropdownButton` (M2-Look) [163-179] | `DropdownButtonFormField`/`AppSegmented` (V2) |
| Intensität nur Farbe, leere Zellen ohne Text [296-305/338-339] | Ø-Wert als Text in der Zelle (Farbe + Zahl) |
| „übernehmen" ohne Bestätigung [255-258/66-114] | `AppConfirmDialog` vor Änderung |

**Touch-Targets & Barrierefreiheit:** „übernehmen"/Standort-Wähler ≥48 dp; Heatmap-Werte als Text (colorblind-safe); Sektions-`Semantics`-Summary. Kontrast der Heatmap-Skala in Dark+Light geprüft.

**Offline-Verhalten:** Auswertung basiert auf geladenen Kassendaten; bei Offline `AppStatusBanner` „Werte ggf. nicht aktuell (offline)". „übernehmen" (schreibt Bedarf) bei Offline über hybrid-Fallback lokal, sonst deaktiviert im cloud-only-Modus.

**Motion:** Standortwechsel als kurzes Fade der Heatmap; Reduce-Motion respektiert.

**iOS/Android-nativ:** iOS-Bounce beim Heatmap-Scroll; `DropdownButtonFormField` rendert plattformgerecht.

---

### Sub-Bereich 10 — Abwesenheits-Editor + Abwesenheits-Karten/Pills/Dialoge
Dateien: [shift_planner_screen.dart:1172-1202](lib/screens/shift_planner_screen.dart#L1172), [4893-5051](lib/screens/shift_planner_screen.dart#L4893), [planner_cells.dart:316-426](lib/screens/shift_planner/planner_cells.dart#L316)

**Vision/Zielbild:** Abwesenheiten sind nicht mehr an verstreuten Orten redundant und im Tooltip versteckt, sondern konsolidiert dargestellt mit sichtbaren Details und `appColors`-basiertem Status.

**Informationsarchitektur & Primäraktion:** `_AbsenceEditorSheet` nutzt `AppBottomSheetScaffold` + `AppFormField`/`.adaptive`-Datumsfelder; Prüfen/Genehmigen mit `AppConfirmDialog`; Abwesenheit als `AppStatusBadge` (Typ + Status) mit Detail (Datum/Notiz) direkt sichtbar/antippbar, nicht nur im Tooltip.

**Mobile-Layout:** Abwesenheits-Pill zeigt „Urlaub · genehmigt", Tap öffnet Detail-Sheet mit Datum/Notiz (statt Tooltip [planner_cells.dart:357-424]). Melden-CTA als FAB (Mitarbeiter-Ansicht).

**Tablet/Desktop-Layout:** Hover-Tooltip bleibt als Zusatz; auf Touch/Screenreader immer Tap-Detail.

**Genutzte lib/ui-Komponenten:** `AppBottomSheetScaffold`, `AppFormField`, `AppStatusBadge` (Status über `AppStatusTone.success/warning/info` statt secondary/tertiary [planner_cells.dart:332-348]), `AppConfirmDialog`, `AppSectionCard` (konsolidierte Liste).

**Vorher→Nachher:**
| Vorher | Nachher |
|---|---|
| Detail nur im Tooltip (Touch/Screenreader unerreichbar) [357-424] | Detail per Tap-Sheet + `Semantics`-Label |
| Abwesenheit an 4 Orten redundant [1485-1519/3122-3129/641-658] | konsolidiert: Zellen-Badge + Tages-„Abwesenheiten (n)" + eine Listenansicht |
| Status über secondary/tertiary/surface [332-348] | `appColors` success/warning/info (App-Konvention) |

**Touch-Targets & Barrierefreiheit:** Badge-Tap-Ziel ≥48 dp; Status als Text + Icon; `Semantics` „Urlaub, 01.–05.07., genehmigt".

**Offline-Verhalten:** Melden über hybrid-Fallback lokal; genehmigen (manager, Cloud) bei Offline deaktiviert mit Hinweis.

**Motion:** Detail-Sheet Material-Standard; Reduce-Motion respektiert.

**Formulare:** Datum-Pflichtfelder mit Plausibilität (Ende ≥ Beginn) inline; Verwerfen-Schutz.

**iOS/Android-nativ:** `.adaptive`-Datumspicker (Cupertino-Wheel iOS / Material Android); Sheet-Swipe-Dismiss.

---

### Querschnitts-Themen (für den gesamten Plan-Bereich)
- **Sichere Anmeldung / Datenschutz (Anf. 28/29):** Keine neuen Berechtigungen im Plan-Bereich; Kamera/Standort/Kontakte werden hier nicht angefragt. Auth/2FA/Biometrie liegen im Anmelde-Gate (unverändert). Der Plan-Bereich zeigt nur, dass er keine unnötigen Rechte zieht.
- **Vertrauenswürdiges Design (Anf. 30):** einheitliche Umlaut-Rechtschreibung, konsistente Buttons/Icons/Abstände, klare Zustände (Loading/Empty/Error/Offline) — keine „unfertigen" Custom-InkWells mehr.
- **Push (Anf. 14):** Der Plan-Bereich erzeugt keine neuen Pushes; bestehende server-getriggerte Pushes (Veröffentlichung/Tausch) bleiben. UI verlinkt nur (Deep-Link in Schicht), kein zusätzliches Rauschen.
- **Akku/Speicher/Daten (Anf. 16):** Entfall der Deko-CustomPaint + Virtualisierung reduziert Paint/GPU beim Scroll; keine zusätzlichen Dauer-Streams.


## 13. Bereich — Zeit (Zeitwirtschaft)

> Zielbild in einem Satz: Der `/zeit`-Tab wird von einem reinen Kachel-Verteiler zu einem **handlungsfähigen Zeitwirtschafts-Cockpit** — die häufigste Aktion (Kommen/Gehen) ist ohne Umweg in der Daumenzone, alle Sub-Screens teilen genau **eine** Baustein-Sprache (geteilter Monats-Header, `AppStatusBadge`, adaptive Karten-statt-Tabellen), und jede der 30 Anforderungen ist konkret verortet. **Reine Optik-/Layout-/Struktur-Arbeit** — kein Provider/Service/Model/Compliance/Serialisierung wird angefasst.

### 0. Design-System-Fundament für die ganze Domäne (Querschnitt zuerst)

Der wichtigste Hebel ist nicht ein einzelner Screen, sondern die **Auflösung der Duplikate** in geteilte Bausteine. Vor den Sub-Screen-Details: fünf neue/geteilte Widgets nach `lib/ui/` heben (Signal-Teal-Tokens, kein Hex, keine festen dp), damit alle 13 Screens byte-gleich aussehen.

| Neuer geteilter Baustein (`lib/ui/`) | Löst auf (Vorher → Nachher) | Anforderung |
|---|---|---|
| `AppMonthNavigator` (Chevron ◄ · **antippbares Label öffnet MonthPicker** · ► · „Heute"-Chip; Swipe-Geste links/rechts) | 6 Kopien: [zeitwirtschaft_hub_screen.dart:162](lib/screens/zeitwirtschaft/zeitwirtschaft_hub_screen.dart#L162), [stempel_screen.dart:397](lib/screens/zeitwirtschaft/stempel_screen.dart#L397), [zeiterfassung_screen.dart:85](lib/screens/zeitwirtschaft/zeiterfassung_screen.dart#L85), [stundenkonto_screen.dart:376](lib/screens/zeitwirtschaft/stundenkonto_screen.dart#L376), [abwesenheitskalender_screen.dart:458](lib/screens/zeitwirtschaft/abwesenheitskalender_screen.dart#L458), [lohnlauf_screen.dart:466](lib/screens/zeitwirtschaft/lohnlauf_screen.dart#L466) | 3, 5, 8, 22, 25 |
| `AppStatusBadge` (bereits in `lib/ui/app_status.dart` — **konsequent verwenden**, Größe ≥ `labelMedium`/12→13sp, immer Icon+Text) | 7 `_StatusChip`/`_StatusBadge`-Klone (11px): [stempel_screen.dart:489](lib/screens/zeitwirtschaft/stempel_screen.dart#L489), [zeiterfassung_screen.dart:328](lib/screens/zeitwirtschaft/zeiterfassung_screen.dart#L328), [abwesenheiten_screen.dart:414](lib/screens/zeitwirtschaft/abwesenheiten_screen.dart#L414), [monatsabschluss_screen.dart:419](lib/screens/zeitwirtschaft/monatsabschluss_screen.dart#L419), [mitarbeiterabschluss_screen.dart:873](lib/screens/zeitwirtschaft/mitarbeiterabschluss_screen.dart#L873) | 3, 4, 19, 22, 26 |
| `AppBanner` (warning/info/error-Variante über `appColors.*Container`, Icon+Titel+Body) | 3 `_Banner`/`_WarningBanner`-Kopien: [stundenkonto_screen.dart:411](lib/screens/zeitwirtschaft/stundenkonto_screen.dart#L411), [stempel_screen.dart:300](lib/screens/zeitwirtschaft/stempel_screen.dart#L300), [monatsabschluss_screen.dart:485](lib/screens/zeitwirtschaft/monatsabschluss_screen.dart#L485) | 3, 17, 26 |
| `AppMetricRow` (nutzt vorhandene `AppStatCard`/`AppStatCards` responsiv, `Wrap`→`GridView` ab 600dp) | `_Metric`/`_MiniStat`/`_StatChip`-Handbau: [stundenkonto_screen.dart:181](lib/screens/zeitwirtschaft/stundenkonto_screen.dart#L181), [mitarbeiterabschluss_screen.dart:904](lib/screens/zeitwirtschaft/mitarbeiterabschluss_screen.dart#L904) | 3, 6, 21 |
| `AppDataList` (adaptives **Karten-statt-Tabelle**-Muster: Liste aus `AppCard`-Zeilen mobil, `DataTable` erst ab expanded≥840dp) | 4 horizontal-scroll-`DataTable`s: [zeiterfassung_screen.dart:272](lib/screens/zeitwirtschaft/zeiterfassung_screen.dart#L272), [stundenkonto_screen.dart:320](lib/screens/zeitwirtschaft/stundenkonto_screen.dart#L320), [monatsabschluss_screen.dart:323](lib/screens/zeitwirtschaft/monatsabschluss_screen.dart#L323), [abwesenheitskalender_screen.dart:230](lib/screens/zeitwirtschaft/abwesenheitskalender_screen.dart#L230) | 6, 8, 10, 19 |

**Monatszustand vereinheitlichen:** Alle Sub-Screens lesen `WorkProvider.selectedMonth` (statt lokalem State in Kalender/Mitarbeiterabschluss/Lohnlauf/Monatsabschluss) — der gewählte Zeitraum „reist" beim Navigieren mit (Anf. 5). Das ist reine UI-State-Angleichung (kein Provider-Vertrag geändert; `selectedMonth` existiert bereits).

**Globale Motion-Regel:** Jeder Übergang/Staffel-Effekt läuft über `AppMotion.resolve(context, context.motion.short|medium)` → respektiert automatisch Reduce-Motion (Anf. 27). Sheets aus der Quelle (`showModalBottomSheet` mit Scrim 40–60%). Keine layout-verschiebenden Press-States (Farbe/Opacity statt Größe).

**Globales Offline-Verhalten:** Ein `AppConnectivityBanner` (schmaler Streifen unter der AppBar: „Offline — Änderungen werden gespeichert und später synchronisiert") erscheint app-weit, wenn offline. Firestore-Offline-Cache trägt Lesedaten; Schreibaktionen (Stempeln, Antrag, Eintrag) zeigen optimistisch einen „wird gesendet"-Zustand (Anf. 13). Kein neuer Datenpfad — nur Visualisierung des ohnehin vorhandenen Hybrid-Fallbacks.

---

### 1. Zeitwirtschaft-Hub (`/zeit`, Tab-Einstieg)

- **Zielbild:** Rollen-adaptives Cockpit statt reiner Kachelwand. Oben eine kompakte **Statuszeile** (heutiger Stempelzustand + Soll/Ist-KPI), darunter die **Stempel-Schnellaktion** in der Daumenzone, dann thematisch gruppierte Bereichskacheln.
- **Informationsarchitektur & Primäraktion:** Primäraktion = **Kommen/Gehen direkt vom Hub** (nicht erst nach `context.push`). Sekundär = Bereiche „Meine Zeit" (Zeiterfassung, Stundenkonto, Statistik, Monatsbericht), „Abwesenheiten" (Liste, Kalender), „Abschluss & Lohn" (Mein Abschluss + Admin-Kacheln Mitarbeiterabschluss/Lohnlauf). Gruppen mit `SectionHeader`-Zwischenüberschriften statt einer flachen Wrap.
- **Mobile-Layout:** `SafeArea` → Scroll-Body. Ganz unten, in der **Daumenzone**, ein persistenter, breiter **`AppQuickAction`-Balken „Jetzt einstempeln" / „Ausstempeln"** (grün `appColors.success` / bei laufender Session `appColors.warning`), der State live spiegelt. Bereichskacheln 2-spaltig (`GridView`, aspectRatio ~1.6). Monats-KPI via `AppMonthNavigator` mit antippbarem Label (Vorher: nur Chevrons [zeitwirtschaft_hub_screen.dart:162](lib/screens/zeitwirtschaft/zeitwirtschaft_hub_screen.dart#L162)).
- **Tablet/Desktop (≥600/≥840):** Zweispaltiges Master-Layout — links Statuszeile+Stempelbereich sticky, rechts das Kachel-Grid 3–4-spaltig. `ConstrainedBox(maxWidth:1100)` bleibt.
- **lib/ui-Komponenten:** `SectionHeader`, `AppQuickAction`, `AppComparisonStatCard`/`AppMetricCard` (bereits genutzt), neu `AppMonthNavigator`, `AppMetricRow`.
- **Vorher→Nachher:** Erste Kachel „Kommen und Gehen" führt via `context.push` weg ([zeitwirtschaft_hub_screen.dart:220](lib/screens/zeitwirtschaft/zeitwirtschaft_hub_screen.dart#L220)) → **Stempeln inline erledigbar**; manuelle Grid-Breitenrechnung ([:284](lib/screens/zeitwirtschaft/zeitwirtschaft_hub_screen.dart#L284)) → `GridView` mit `SliverGridDelegateWithMaxCrossAxisExtent` (Anf. 6).
- **Touch/Barrierefreiheit:** Kacheln ≥88dp hoch, Stempelbalken ≥56dp; KPI-Reihe als `Semantics`-Gruppe mit gelesenem Kontext („Sollzeit 160 Stunden, Ist 152 Stunden") (Vorher: keine Semantics [:128](lib/screens/zeitwirtschaft/zeitwirtschaft_hub_screen.dart#L128), Anf. 19).
- **Offline:** Stempelbalken bleibt bedienbar (optimistisch); KPI zeigt „Stand: zuletzt aktualisiert HH:mm".
- **Motion:** Kachel-Einblenden gestaffelt 30–50ms via `AppMotion`.
- **iOS/Android:** Cross-Tab-Back bleibt über `_ShellScope`/`PopScope` (Predictive Back Android, Edge-Swipe iOS nicht blockieren).

### 2. Kommen und Gehen (Stempeluhr, `zeitStempeln`)

- **Zielbild:** Ein ruhiger „Uhr"-Screen mit **einer** dominanten, sicheren Stempelaktion und klarem Erfolgs-/Fehler-Feedback.
- **Primäraktion:** großer Kommen/Gehen-Button. **`AppHeroCard`** als Live-Ticker (laufende Buchung, `FontFeature.tabularFigures()` gegen Sekunden-Sprünge, Anf. 4/15).
- **Mobile-Layout:** Body = Ticker-Hero, „Wer ist da" (Manager), Monatsliste. Stempel-Aktion als **untere Aktionsleiste** (bottom bar in `SafeArea`) statt schwebendem FAB, damit Daumenzone + fixe Position. Laden-Auswahl als `AppBottomSheetScaffold` mit ≥56dp-Zeilen + **explizitem „Abbrechen"** (Vorher: nur Drag-Dismiss [stempel_screen.dart:141](lib/screens/zeitwirtschaft/stempel_screen.dart#L141)).
- **Tablet/Desktop:** Ticker + „Wer ist da" nebeneinander (Master-Detail), Monatsliste darunter volle Breite.
- **lib/ui:** `AppHeroCard`, `AppBottomSheetScaffold`, `AppStatusBadge` (statt Container-Chip [:489](lib/screens/zeitwirtschaft/stempel_screen.dart#L489)), `AppFormField` (Pause), `AppBanner`.
- **Vorher→Nachher / Fehler+Offline:** `clockIn/clockOut` ohne try/catch/Bestätigung ([stempel_screen.dart:126](lib/screens/zeitwirtschaft/stempel_screen.dart#L126), [:169](lib/screens/zeitwirtschaft/stempel_screen.dart#L169)) → Button zeigt **Spinner + disabled**, danach `SnackBar`-Bestätigung „Eingestempelt um HH:mm"; bei Fehler verständliche Meldung mit Nächstem-Schritt („Keine Verbindung — erneut versuchen"). **Reine UI-Hülle um denselben Provider-Call** (Anf. 12/13/17).
- **Formulare:** Pause-`AppFormField` mit `keyboardType:number`, Validator ≥0/≤600min, Inline-Fehler unter dem Feld (Vorher: rohes TextField [:555](lib/screens/zeitwirtschaft/stempel_screen.dart#L555), Anf. 18).
- **Farben/Kontrast:** `Colors.white`-foreground hartkodiert ([:216](lib/screens/zeitwirtschaft/stempel_screen.dart#L216)) → `appColors.onSuccess`/`onWarning` (Dark-Mode-sicher, Anf. 20/26).
- **iOS/Android:** Optionaler leichter `HapticFeedback.mediumImpact()` bei erfolgreichem Stempeln (Bestätigung, sparsam).

### 3. Zeiterfassung (Self-Service Tabs, `zeitErfassung`)

- **Zielbild:** Weg von 7-Spalten-Tabelle, hin zu **antippbaren Eintragskarten** je Tag mit Status + Aktionen.
- **Primäraktion:** „Neue Arbeitszeit" als **FAB** (Daumenzone) statt oben-rechts-Button (Vorher [zeiterfassung_screen.dart:229](lib/screens/zeitwirtschaft/zeiterfassung_screen.dart#L229), Anf. 9).
- **Mobile-Layout:** `AppMonthNavigator` + `AppSegmented` (3 Segmente Arbeitszeiten/Urlaub/Krank) + `AppDataList` (Karten: Datum · Kommen–Gehen · Stunden · `AppStatusBadge`; ganze Karte tappbar → Bearbeiten, „Einreichen" als Aktion im Overflow ≥48dp). Suchfeld + Filter (Zeitraum/Standort/„nur Klärung") in kollabierbarer Filterzeile (Anf. 24).
- **Tablet/Desktop (≥840):** `DataTable` erst hier, mit ≥48dp-Zeilen.
- **Vorher→Nachher:** 7-Spalten-Horizontal-Scroll-`DataTable` ([:272](lib/screens/zeitwirtschaft/zeiterfassung_screen.dart#L272)) → `AppDataList`; size-18/`compact`-IconButtons ([:302](lib/screens/zeitwirtschaft/zeiterfassung_screen.dart#L302)) → ≥48dp-Aktionen (Anf. 8/10).
- **Barrierefreiheit:** doppelte `_StatusChip`/`_AbsenceStatusChip` ([:328](lib/screens/zeitwirtschaft/zeiterfassung_screen.dart#L328), [:444](lib/screens/zeitwirtschaft/zeiterfassung_screen.dart#L444)) → `AppStatusBadge`.
- **Offline:** Einträge aus Cache; „Einreichen" optimistisch mit Pending-Badge.

### 4. Stundenkonto (`zeitStundenkonto`)

- **Zielbild:** KPI-Kopf im Domänen-Stil + lesbare Jahres-Liste.
- **Mobile-Layout:** `AppMetricRow` (Soll/Ist/Überstunden/Saldo) statt `_Metric`/`_MiniStat` ([stundenkonto_screen.dart:181](lib/screens/zeitwirtschaft/stundenkonto_screen.dart#L181)); `AppBanner` (ArbZG-Warnung); Jahresübersicht als `AppDataList`-Karten (Monat · Soll · Ist · Saldo · **Status mit Icon+Wort**, Vorher nur Icon+Tooltip [:320](lib/screens/zeitwirtschaft/stundenkonto_screen.dart#L320)).
- **Tablet/Desktop:** 12-Monats-`DataTable` ab 840dp.
- **Anforderungen:** 3/6/10/19/26 (Statuswort ergänzt Icon), 4 (kein 11px).

### 5. Abwesenheiten (Liste, `zeitAbwesenheiten`)

- **Zielbild:** Klare Antrags-Startpunkte + filterbare Liste.
- **Primäraktion:** **ein** primärer FAB „Antrag stellen" (öffnet Auswahl Urlaub/Krank/Zeitausgleich), Kalender als sekundäre AppBar-Aktion — statt 4 gemischter Buttons oben (Vorher [abwesenheiten_screen.dart:139](lib/screens/zeitwirtschaft/abwesenheiten_screen.dart#L139), Anf. 9/22).
- **Mobile-Layout:** `AppSegmented`/ChoiceChips für Status; **Namens-/Zeitraumsuche für Manager** (org-weite Liste, Anf. 24); `_AbsenceCard` mit `AppStatusBadge`.
- **Fehler/Löschen:** generische „Aktion fehlgeschlagen" ([:355](lib/screens/zeitwirtschaft/abwesenheiten_screen.dart#L355)) → verständliche Meldung; rohes AlertDialog ([:367](lib/screens/zeitwirtschaft/abwesenheiten_screen.dart#L367)) → `AppConfirmDialog(destructive:true)` (Anf. 17/18).
- **Sheets:** weiterhin `showAbsenceRequestSheet(...)` (unverändert).

### 6. Abwesenheitskalender (`zeitAbwesenheitenKalender`)

- **Zielbild:** Raster bleibt, wird aber **antippbar, beschriftet, farbfehlsicht-tauglich**.
- **Mobile-Layout:** Namensspalte sticky; Tageszellen ≥44×44dp, **Kürzel im Feld** (U/K/Z) zusätzlich zur Farbe (Vorher reine Farbfläche 26px [abwesenheitskalender_screen.dart:205](lib/screens/zeitwirtschaft/abwesenheitskalender_screen.dart#L205)); Zelle `onTap` → Detail-Sheet (Anf. 8/19); `_Legend` mit Icon+Text.
- **Farbcodierung:** kollidierende Rollen (sickness/childSick, timeOff/shortTimeWork) über **Muster/Kürzel** unterscheidbar machen (Anf. 26), Alpha auf ≥0.7 für Kontrast.
- **Barrierefreiheit:** je Zelle `Semantics(label: 'Name, 3. Juli, Urlaub')` (Vorher nur Hover-Tooltip [:358](lib/screens/zeitwirtschaft/abwesenheitskalender_screen.dart#L358)).
- **Monat:** `WorkProvider.selectedMonth` statt lokal ([:37](lib/screens/zeitwirtschaft/abwesenheitskalender_screen.dart#L37), Anf. 5).

### 7. Mein Monatsabschluss (`zeitMonatsabschluss`)

- **Mobile-Layout:** 12-Monats-Übersicht als `AppKontoTile`/`AppDataList`-Karten mit `AppStatusBadge` + **beschrifteter Aktion** „Abschließen" (Vorher 18px-lock-IconButton [monatsabschluss_screen.dart:398](lib/screens/zeitwirtschaft/monatsabschluss_screen.dart#L398), Anf. 8/10/25).
- **Validierung:** Ergebnis als strukturiertes Panel (Fehler rot / Warnungen gelb getrennt, `AppStatus`/`AppBanner`) statt gemischter „• text"-AlertDialog (Vorher [:239](lib/screens/zeitwirtschaft/monatsabschluss_screen.dart#L239), Anf. 17/23).
- **Bestätigen:** `AppConfirmDialog` (bereits vorhanden) beibehalten.

### 8. Mitarbeiterabschluss (Admin-Hub, `zeitMitarbeiterabschluss`)

- **Mobile-Layout:** `_KpiRow` → `AppMetricRow` (responsiv); Filter: **`AppSegmented`** für „offen/abgeschlossen" (Vorher sich-gegenseitig-ausschließende FilterChips [mitarbeiterabschluss_screen.dart:233](lib/screens/zeitwirtschaft/mitarbeiterabschluss_screen.dart#L233), Anf. 1/23); Such-`AppFormField` **full-width** (Vorher fixe 260px [:666](lib/screens/zeitwirtschaft/mitarbeiterabschluss_screen.dart#L666), Anf. 6/10).
- **Performance:** blockierender Full-Reload pro Monatswechsel ([:71](lib/screens/zeitwirtschaft/mitarbeiterabschluss_screen.dart#L71)) → **Skeleton-Liste** (`skeletonizer`-Muster) statt zentralem Spinner, Karten inkrementell (Anf. 12/15). Reine UI-Ladezustands-Änderung.
- **Tablet/Desktop:** Master (Mitarbeiterliste) — Detail (offene Einträge/Auszahlung) nebeneinander ab 840dp; Sheets bleiben Sheets auf Mobil.

### 9. Lohnlauf (Admin-Batch, `zeitLohnlauf`)

- **Mobile-Layout:** 4 KPI in **responsivem Grid** statt fixer 2×2 (Vorher [lohnlauf_screen.dart:253](lib/screens/zeitwirtschaft/lohnlauf_screen.dart#L253), Anf. 6); Status-Änderung als **`.adaptive`/Cupertino-ActionSheet auf iOS**, Material-`PopupMenu` auf Android (Vorher überall PopupMenu [:391](lib/screens/zeitwirtschaft/lohnlauf_screen.dart#L391), Anf. 7/11).
- **Fehler:** rohes `'$error'` in SnackBar ([:170](lib/screens/zeitwirtschaft/lohnlauf_screen.dart#L170)) → verständliche deutsche Meldung (Anf. 17).
- **lib/ui:** `AppStatCard`/`AppSectionCard`/`AppStatusBadge` bereits genutzt (Referenzstil für die Domäne).

### 10. Zeiteintrag-Formular (EntryForm, imperativ gepusht)

- **Zielbild:** **Komplette V2-Migration** — der einzige harte Stilbruch der Domäne wird beseitigt.
- **Mobile-Layout:** `Form`→`ListView(maxWidth:760)`; Abschnitte per `AppSectionCard` (Eckdaten / Zeiten / Details); Datum/Zeit als `AppFormField`-artige `_PickerField` mit sichtbarer Picker-Affordance (Chevron/Icon); Speichern als **untere sticky Aktionsleiste** (52→56dp).
- **Vorher→Nachher:** rohe Card/ListTile + `_SectionLabel` ([entry_form_screen.dart:200](lib/screens/entry_form_screen.dart#L200)) → `lib/ui`-Komponenten (Anf. 3/21); hardcodierte SizedBox(16/28) ([:198](lib/screens/entry_form_screen.dart#L198)) → `context.spacing`; `Colors.transparent` ([:1150](lib/screens/entry_form_screen.dart#L1150)) → Theme-Rolle (Anf. 20).
- **Formulare/Fehlervermeidung:** Inline-Validierung **Ende > Beginn** (Vorher nur Pause validiert [:452](lib/screens/entry_form_screen.dart#L452)); Pflichtfelder markiert, Fehler unter dem Feld mit Lösung; Bestätigung vor Verwerfen (Anf. 18/17).
- **Deutsch-Qualität (Anf. 4/30):** ASCII-Ersatz beheben — „Loeschen→Löschen", „uebernehmen→übernehmen", „ausgewaehlt→ausgewählt", „Aenderungen→Änderungen", „Ungueltiger→Ungültiger" ([:185](lib/screens/entry_form_screen.dart#L185), [:216](lib/screens/entry_form_screen.dart#L216), [:308](lib/screens/entry_form_screen.dart#L308), [:337](lib/screens/entry_form_screen.dart#L337), [:368](lib/screens/entry_form_screen.dart#L368)).
- **iOS/Android:** `showDatePicker`/`showTimePicker` → `.adaptive`-Varianten (Cupertino-Rad auf iOS).

### 11. Statistik (imperativ gepusht)

- **Mobile-Layout:** `_HeaderSection`/`_SectionCard`/`_SummaryCardsRow`-Klone → `lib/ui` (Anf. 3/21). BarCharts mit **fester Höhe + `Semantics`-Textalternative** („Höchster Wert Dienstag, 9,5 Stunden"), auf schmalen Screens vereinfacht (Vorher [statistics_screen.dart:485](lib/screens/statistics_screen.dart#L485), Anf. 10/19).
- **Deutsch:** „Jahresuebersicht→Jahresübersicht", „fuer→für" ([:86](lib/screens/statistics_screen.dart#L86), [:118](lib/screens/statistics_screen.dart#L118)).
- **Abstände:** hardcodiert ([:81](lib/screens/statistics_screen.dart#L81)) → `context.spacing`.

### 12. Monatsbericht (imperativ gepusht)

- **Mobile-Layout:** manuelle LayoutBuilder-Breakpoints (980/680/360) → geteilte `MobileBreakpoints` aus `responsive_layout.dart` (Vorher [month_report_screen.dart:485](lib/screens/month_report_screen.dart#L485), Anf. 6). Mitarbeiterwahl (Admin) als `AppFormField`-Dropdown.
- **Deutsch:** „fuer→für" ([:127](lib/screens/month_report_screen.dart#L127)).
- **Fehler:** PDF-Export-`'$error'` ([:311](lib/screens/month_report_screen.dart#L311)) → verständliche Meldung; Export-Button behält Ladezustand.

---

### Responsive-Breakpoint-Matrix (ganze Domäne)

| Breite | Navigation | Zeit-Screens-Layout |
|---|---|---|
| < 600dp (Phone) | BottomNav + FAB/untere Aktionsleiste | 1-spaltig, Karten statt Tabellen, Sheets, Segmented |
| 600–840dp (Tablet) | NavigationRail | 2-spaltig, KPI-Grid, Karten; Kalender-Raster breiter |
| ≥ 840dp (Desktop) | Rail volle Labels / Sidebar | Master-Detail, `DataTable` erlaubt, dichtere `VisualDensity` |

### Sicherheit / Datenschutz (Anf. 28/29)

Zeit-Bereich ergänzt keine neue Berechtigung (keine Kamera/Standort/Kontakte). Anmeldung/Biometrie bleibt Sache des Auth-Gate; hier nur konsistent: keine sensiblen Zahlen in Screenshots/Recents (`Semantics(excludeSemantics)` nicht nötig, aber Lohn-KPI nur für Admin-Rolle sichtbar — bleibt über Permission-Getter gegated). Vertrauenswürdiges Design (Anf. 30) = einheitliche V2-Optik + korrekte deutsche Umlaute.


## 14. Bereich — Anfragen (Inbox / Benachrichtigungen)

> Bereich `/anfragen` (Shell-Tab `inbox`) plus die heute ausgelagerten Eingänge **Kundenwünsche**, **Feedback**, **Push-Einstellungen** und die admin-only **Urlaubskonto-Übersicht**. Zielbild: **ein** vertrauenswürdiger, daumenfreundlicher Posteingang für alles, was eine Rückmeldung/Entscheidung braucht — durchgehend auf dem V2-Designsystem (`lib/ui/`), Material-3 Signal-Teal, Deutsch/de_DE, Status ausschließlich über `Theme.of(context).appColors`, Dark+Light gemeinsam, Barrierefreiheit + Touch zuerst. **Nur Optik/Layout/Struktur/UX** — keine Provider-/Service-/Model-/Compliance-Änderung; die vorhandenen Provider-Getter (`schedule.allAbsenceRequests`, `inventory.ordersDueSoonNotPrepared()`, `_service.watchCustomerWishes()` etc.) bleiben unverändert.

### Design-System-Ableitung (verbindlich für alle Unterbereiche)

| Aspekt | Entscheidung |
|---|---|
| Produkttyp | Operatives Team-Tool / Posteingang mit Entscheidungsdruck → **ruhig, seriös, dicht, hohe Signal-Klarheit** |
| Karten | ausschließlich `AppCard` / `AppSectionCard` (surfaceContainerLow, Hairline-Border, Radius xl28, elevation 1) — **nie** rohe `Card`/`Container(BoxShadow)` |
| Status | `AppStatusBadge`/`AppStatusBanner` mit `AppStatusTone` (error=kritisch, warning=wartet, success=erledigt, info=Hinweis, neutral=Verlauf) — Ampel nie farbfrei, immer Icon+Text |
| Kennzahlen | `AppStatCards` (tabular figures) statt handgebauter `_HeroPill` |
| Hero | `AppHeroCard` statt roher Hero-`Card` |
| Sheets | `showAppBottomSheet` + `AppBottomSheetScaffold` + `AppFormField`/`AppSegmented`/`AppConfirmDialog` |
| Icons | ein Outline-Set, Größen aus `AppIconSizes` (sm/md/lg), nie willkürliche `size:`-Literale |
| Spacing | `context.spacing` (4/8-Rhythmus), Radii `context.radii`, Motion `AppMotion` |
| Touch | jede Aktion ≥ 48×48 dp, ≥ 8 dp Abstand, Primär-CTA in Daumenzone |

**Querschnitts-Regeln, die JEDER Unterbereich erbt:** (1) **Umlaute reparieren** — alle „Antraege/Prioritaet/Rueckmeldungen/verfuegbar/spaeter/Aenderungen" → korrektes „Anträge/Priorität/Rückmeldungen/verfügbar/später/Änderungen" (Deutsch-only-Regel). (2) **Fehlermeldungen** nie `error.toString()`, sondern Klartext + Handlung + „Wiederholen". (3) **Semantics** auf jedem Header (`header:true`), jedem Icon-only-Control (`label:`/`tooltip:`), jeder farbcodierten Kennzahl (Text-Äquivalent). (4) **Offline-Banner** (`AppStatusBanner` tone info/warning) statt stiller fire-and-forget-Writes. (5) **Reduce Motion** (`MediaQuery.disableAnimations`) respektieren. (6) **maxWidth-Konstante vereinheitlichen** (Content ~840–980, Master-Detail ab 840).

---

### 1. Inbox-Hauptscreen (Anfragen) — Kopf, Hero, Schnellaktionen, Filter, Suche
`lib/screens/notification_screen.dart`

**Zielbild & Informationsarchitektur.** Der Posteingang bleibt der eine scrollende `CustomScrollView`, aber die Kopfzone wird verschlankt und die drei Bereiche „**Zu erledigen** / **Läuft & wartet** / **Verlauf & Hinweise**" bleiben als tragende Struktur (gute Idee — beibehalten). Neu: eine **persistente Filter-+Such-Leiste** und eine **untere Aktionsleiste** für die Primäraktion „Antrag stellen". Primäraktion des Screens: für Mitarbeiter **Antrag stellen**, für Manager **das oberste offene To-do entscheiden**.

**Mobile-Layout (Daumenzone).**
- Kopf: `SectionHeader` (Titel „Anfragen" als `Semantics(header:true)` + Rollen-Untertitel), darunter **eine** `AppHeroCard` mit **`AppStatCards`** (3 Kacheln: „Offen" / „Tausch" / „Kritisch") — die Zahl steht **nur noch** in den Kacheln, nicht doppelt im Fließtext (behebt Duplizierung `notification_screen.dart:1310-1339`).
- **Suche**: `SearchBar` (Material 3) direkt unter dem Hero, sticky als `SliverPersistentHeader` (bleibt beim Scrollen erreichbar), Debounce 250 ms, filtert Titel/Untertitel/Name clientseitig (rein UI, kein Provider-Touch). Placeholder „In Anfragen suchen".
- **Filter**: horizontale `AppSegmented`-Leiste (Alle/Kritisch/Anträge/Tausch/Updates) **mit Zähler pro Segment** und weichem **Fade-Rand** (`ShaderMask`) als Overflow-Hinweis (behebt `:320-338`).
- Bereiche als Slivers; die drei Quick-Antrag-Buttons wandern aus dem Kopf in eine **untere `SafeArea`-Aktionsleiste** bzw. einen **`FloatingActionButton.extended` „Antrag stellen"** → Bottom-Sheet mit Art-Auswahl (Krank/Urlaub/Nicht verfügbar/Zeitausgleich). Damit liegt die Primäraktion in der Daumenzone (behebt Global-Problem „Aktionen oben in langer Liste").
- **pull-to-refresh** (`RefreshIndicator`, Android) bzw. `CupertinoSliverRefreshControl` (iOS) — löst manuellen Provider-Refresh aus (nutzt bestehende Refresh-Methode, keine neue Logik).

**Tablet/Desktop-Layout (≥ 840 dp Master-Detail).** `LayoutBuilder` + `MobileBreakpoints`: ab **expanded (840)** zweispaltig — links die drei Bereiche als Liste (kompakte Karten), rechts ein **Detail-Pane** des selektierten Vorgangs mit vollen Aktionen (statt Aktionen inline pro Karte). Zwischen **600–840** einspaltig mit größeren Gutters (`ConstrainedBox` maxWidth 720). NavRail-Fall wird von der Shell geliefert; hier nur Content-Breakpoints.

**lib/ui-Komponenten.** `AppHeroCard`, `AppStatCards`, `AppSegmented`, `AppCard`, `AppStatusBadge`, `SectionHeader`, `AppEmptyState`, `AppBottomSheetScaffold`. Ersetzt `_InboxHeroCard`/`_HeroPill`/`_BadgePill`/`_SectionHeader`/`_InboxQuickButton`.

**Vorher → Nachher.**

| Vorher | Nachher |
|---|---|
| [notification_screen.dart:1294](lib/screens/notification_screen.dart#L1294) rohe Hero-`Card` | `AppHeroCard` + `AppStatCards` |
| [notification_screen.dart:1310-1339](lib/screens/notification_screen.dart#L1310) Zahlen doppelt (Text + Pills) | Zahlen nur in `AppStatCards` |
| [notification_screen.dart:320-338](lib/screens/notification_screen.dart#L320) Chip-Scroll ohne Counts/Overflow | `AppSegmented` mit Zählern + Fade-Rand |
| kein Suchfeld (ganze Datei) | sticky `SearchBar` (Sliver) mit Debounce |
| [notification_screen.dart:270-305](lib/screens/notification_screen.dart#L270) Quick-Buttons oben | `FAB.extended`/untere Leiste in Daumenzone |
| [notification_screen.dart:241-254](lib/screens/notification_screen.dart#L241) Titel/Untertitel ohne Semantics, Umlaute entfernt | `SectionHeader` + `Semantics(header:true)`, Umlaute korrekt |

**Touch & Barrierefreiheit.** Segmente/Chips ≥ 48 dp Höhe, ≥ 8 dp Abstand. Hero-Kacheln als `Semantics(label: '3 offene Anträge')`. Kontrast: `onSurfaceVariant`-Untertitel ≥ 4.5:1 in beiden Themes prüfen. Dynamic Type bis 200 %: Hero-Kacheln umbrechen statt truncaten.

**Offline.** Bei fehlender Verbindung `AppStatusBanner` (tone info) „Offline — zeigt zuletzt geladene Anfragen" über den Bereichen; Aktionen, die schreiben, zeigen bei Cloud-Fehler Klartext + Retry (Provider fällt im Hybrid-Modus selbst lokal zurück — UI muss das nur ehrlich anzeigen).

**Motion.** Sektions-Ein/Ausklappen 200 ms ease-out; neue Items via `AnimatedSwitcher`/staggered ≤ 50 ms; alles unter `disableAnimations` deaktiviert. Kein Layout-Reflow animieren.

**iOS/Android.** iOS: `CupertinoSliverRefreshControl`, Swipe-Back nicht blockieren. Android: `RefreshIndicator`, Predictive-Back respektieren. Beide: SafeArea um FAB/untere Leiste (Gesten-Indikator/Notch).

---

### 2. Inbox-Karte (Vorgang) mit Aktionen
`lib/screens/notification_screen.dart` (`_InboxItemCard`, ab :1557)

**Zielbild.** Ein einheitlicher, tokenisierter Vorgangs-Row auf `AppCard`; Status als `AppStatusBadge` (tone-basiert, garantiert kontrastreich); Aktionen mit Bestätigung für irreversible Team-Entscheidungen.

**Informationsarchitektur & Primäraktion.** Führendes Icon (getönt, `AppStatusTone`-Farbe), Titel bold, Zeit + Untertitel, **eine** primäre Aktion (`FilledButton`, z. B. „Genehmigen"), sekundäre als `OutlinedButton`/Overflow. Auf Mobile bleibt die primäre Aktion sichtbar; im Tablet-Detail-Pane wandert sie in eine untere Aktionsleiste.

**Mobile-Layout.** Volle Variante mit Aktionen als **`Row` mit `Expanded`-Buttons** (feste Höhe 48 dp) statt freiem `Wrap` schmaler Buttons (behebt `:1654-1671`, Touch-Target). Dense-Variante (eingeklappte Bereiche) ohne Aktionsleiste, tippbar → öffnet Detail-Sheet. **Swipe-Actions** (`Dismissible`/`flutter_slidable`-Muster): auf Manager-Karten Swipe-rechts „Genehmigen", Swipe-links „Ablehnen" (mit Bestätigung) — native Geste.

**Tablet/Desktop.** Karte kompakter (VisualDensity), Aktionen im Detail-Pane; Hover-State (Desktop) als zusätzliche, nie alleinige Affordance.

**lib/ui-Komponenten.** `AppCard`, `AppStatusBadge`, `AppConfirmDialog`.

**Vorher → Nachher.**

| Vorher | Nachher |
|---|---|
| [notification_screen.dart:1580](lib/screens/notification_screen.dart#L1580) rohe `Card` | `AppCard` |
| [notification_screen.dart:1593,1604,1627](lib/screens/notification_screen.dart#L1593) `item.color` direkt (Kontrastrisiko) | `AppStatusTone` → garantierte Kontraste aus `appColors` |
| [notification_screen.dart:607-618 / 594-605](lib/screens/notification_screen.dart#L594) Genehmigen/Ablehnen sofort | `AppConfirmDialog` vor irreversibler Entscheidung |
| [notification_screen.dart:1654-1671](lib/screens/notification_screen.dart#L1654) `Wrap` schmaler Buttons | `Row`+`Expanded`, 48 dp, `AppConfirmDialog` bei Ablehnen |
| [notification_screen.dart:1698-1703](lib/screens/notification_screen.dart#L1698) `Text(error.toString())` | Klartext-Meldung + „Wiederholen"-Action in SnackBar |

**Touch & Barrierefreiheit.** Avatar-Icon trägt Bedeutung → `Semantics(label: 'Krankmeldung')`. Zeit/Status als Textlabel für Screenreader. Buttons ≥ 48 dp. Disabled-State (busy) 0.38 Opacity + Spinner statt „Bitte warten…"-Textwechsel, der das Layout schiebt.

**Offline/Formulare/Motion.** Aktion async → Button disabled + inline Spinner (bereits vorhanden, nur an V2-Höhe binden). Erfolg: kurze SnackBar; Fehler: Klartext + Retry. Karten-Press 200 ms State-Layer, kein Größensprung.

**iOS/Android.** iOS: Cupertino-Bestätigungsdialog-Anleihe (`.adaptive`), Swipe-Actions von rechts. Android: Material-Dialog, `Dismissible`-Ripple.

---

### 3. Antrag-BottomSheet (`showAbsenceRequestSheet`)
`lib/screens/notification_screen.dart` (`_AbsenceRequestSheet`, ab :1818)

**Zielbild.** Fehlerarmes, scrollbares Formular auf `AppBottomSheetScaffold` mit `AppFormField`; Von/Bis als klar tappbare Datumsfelder; Inline-Validierung; persistente untere CTA.

**Informationsarchitektur & Primäraktion.** Kopf (Titel/Untertitel), dann Felder in logischer Reihenfolge: Art → (Halbtag/Segment) → Von/Bis → kontextuelle Felder (Stunden/EFZG-Hinweis) → Vertreter → Hinweis. Primär-CTA „Antrag senden" **full-width in der Daumenzone**, sticky am Sheet-Boden über `viewInsets`.

**Mobile-Layout.** `AppBottomSheetScaffold` liefert bereits `SingleChildScrollView` + tastatur-sicheren Bodenabstand (behebt `Column(min)`-Abschneiden `:1833`). Von/Bis als **`AppFormField` im read-only-Tap-Stil** (sieht wie Eingabefeld aus, öffnet DatePicker) statt `ListTile` (behebt `:1922-1944`).

**Tablet/Desktop.** Sheet zentriert, maxWidth ~560; Von/Bis nebeneinander; auf Desktop Enter-to-submit + Fokus-Traversal.

**lib/ui-Komponenten.** `AppBottomSheetScaffold`, `AppFormField`, `AppSegmented`, `AppConfirmDialog` (Verwerfen bei ungespeicherten Änderungen).

**Vorher → Nachher.**

| Vorher | Nachher |
|---|---|
| [notification_screen.dart:1825-1833](lib/screens/notification_screen.dart#L1825) handgebautes Padding/`Column(min)` | `AppBottomSheetScaffold` (scroll + keyboard-safe) |
| [notification_screen.dart:1855-1957](lib/screens/notification_screen.dart#L1855) rohe `DropdownButtonFormField`/`TextField` | `AppFormField`-Varianten, konsistent |
| [notification_screen.dart:1922-1944](lib/screens/notification_screen.dart#L1922) Von/Bis als `ListTile` | tappbare Datum-`AppFormField` mit Kalender-Icon |
| [notification_screen.dart:1909-1919](lib/screens/notification_screen.dart#L1909) Stunden ohne Validator | Inline-Validator (Pflicht, Komma-Format), Fehler unter Feld |
| [notification_screen.dart:2149-2157](lib/screens/notification_screen.dart#L2149) Enddatum-Check erst beim Submit als SnackBar | on-blur-Validierung, erstes ungültiges Feld fokussieren |
| [notification_screen.dart:1849,1976](lib/screens/notification_screen.dart#L1849) „spaeter/Aenderungen" | „später/Änderungen" |

**Formulare (Pflicht/Fehlervermeidung/Fehlermeldungen).** Sichtbares Label pro Feld (nicht nur Hint), Pflichtfelder markiert, `helperText` für Stunden/Zeitausgleich, Fehler **unter dem Feld** mit Ursache+Lösung, Validierung on-blur (`autovalidateMode.onUserInteraction`). Bei Verwerfen mit Änderungen → `AppConfirmDialog`.

**Touch & Barrierefreiheit.** Alle Felder/Chips ≥ 48 dp; Vertreter-`FilterChips` ausreichend groß; Segmented ≥ 48 dp. `Semantics` für DatePicker-Trigger. Dynamic Type: Sheet scrollt, bricht nicht.

**Offline.** Absenden im Offline-/Hybrid-Modus: optimistisch speichern, Banner „Wird bei Verbindung übertragen" statt Fehler; echter Cloud-only-Fehler → Klartext + Retry.

**Motion/iOS/Android.** Sheet-Enter aus Quelle 250 ms, Scrim 40–60 %. iOS: `CupertinoDatePicker`-Anleihe via `.adaptive`, Swipe-down-to-dismiss. Android: Material DatePicker (bereits `de_DE`), Predictive-Back schließt Sheet.

---

### 4. Kundenwünsche-Eingang (in den Posteingang integrieren)
`lib/screens/customer_wishes_screen.dart` · Route `customerWishesInbox`

**Zielbild & IA.** Fachlich ein **Eingang/Anfrage** → als **Segment/Filter „Wünsche" im `/anfragen`-Screen** erreichbar machen (Manager-Sicht), zusätzlich zur eigenständigen Route. Der Screen selbst wird auf V2 gehoben und zum Wünsche-Zwilling des Feedback-Screens vereinheitlicht.

**Mobile-Layout.** Kopf via `SectionHeader` (Icon-Container + Titel + offene Zahl), **`SearchBar`** + `AppSegmented` (Offen/Erledigte/Alle) statt einzelnem FilterChip. Liste aus **`AppCard`** statt `_WishCard`-Container-mit-Shadow. **Sichtbare Primäraktion** je Karte („In Bestellung übernehmen" als `FilledButton`) statt alles im `PopupMenuButton`; sekundäres im Overflow (behebt `:498-509`). Skeleton-Ladezustand (`skeletonizer`-Muster) + Fehlerzustand mit **Retry**.

**Tablet/Desktop.** Master-Detail ab 840: Liste links, Wunsch-Detail rechts (Kontakt verknüpfen, Status, Historie).

**lib/ui-Komponenten.** `AppCard`, `AppStatusBadge`, `AppSegmented`, `SectionHeader`, `AppEmptyState`, `AppStatusBanner`.

**Vorher → Nachher.**

| Vorher | Nachher |
|---|---|
| [customer_wishes_screen.dart:460-472](lib/screens/customer_wishes_screen.dart#L460) `Container`+`BoxShadow` | `AppCard` |
| [customer_wishes_screen.dart:205-209](lib/screens/customer_wishes_screen.dart#L205) einziger FilterChip, keine Suche | `SearchBar` + `AppSegmented` |
| [customer_wishes_screen.dart:498-509](lib/screens/customer_wishes_screen.dart#L498) alles im PopupMenu | sichtbare Primär-CTA + Overflow |
| [customer_wishes_screen.dart:115-122](lib/screens/customer_wishes_screen.dart#L115) Fehler nur Text, kein Retry | `AppStatusBanner` + „Wiederholen" |
| [app_router.dart:176](lib/routing/app_router.dart#L176) nur unter Laden | zusätzlich als Wünsche-Filter im `/anfragen` (Manager) |

**Touch/Barrierefreiheit/Offline.** CTA ≥ 48 dp; referenceCode-Badge + Status als `AppStatusBadge` mit Text. StreamBuilder-Offline: „zuletzt aktualisiert"-Zeile + Banner statt nur Demo-`cloud_off`. Pull-to-refresh.

---

### 5. Feedback-Eingang (Beschwerden/Vorschläge/Lob)
`lib/screens/customer_feedback_screen.dart` · Route `feedbackInbox`

**Zielbild & IA.** Exakter **Zwilling** des Wünsche-Screens (gleicher Kopf, gleiche Chip-/Suchleiste, gleiche Karten) — Konsistenz ist hier das Hauptziel. Ebenfalls als **Filter „Feedback" im `/anfragen`** (Manager) erreichbar.

**Mobile/Tablet.** Identisch zu §4: `SectionHeader` mit Icon-Container (behebt fehlenden Icon-Container `:161-181`), `SearchBar` + `AppSegmented`, `AppCard`-Liste mit `_TypeChip`/`_StatusChip` → `AppStatusBadge` (tone: Beschwerde=warning/error, Vorschlag=info, Lob=success). Einheitliches Filter-Label „Erledigte" (behebt Divergenz `:174` vs. Wünsche `:206`).

**lib/ui-Komponenten.** `AppCard`, `AppStatusBadge`, `AppSegmented`, `SectionHeader`, `AppEmptyState`, `AppStatusBanner`.

**Vorher → Nachher.**

| Vorher | Nachher |
|---|---|
| [customer_feedback_screen.dart:161-181](lib/screens/customer_feedback_screen.dart#L161) Kopf ohne Icon-Container | `SectionHeader` identisch zu Wünsche |
| [customer_feedback_screen.dart:174](lib/screens/customer_feedback_screen.dart#L174) „Erledigte zeigen" | „Erledigte" (einheitlich) |
| [customer_feedback_screen.dart:105-112](lib/screens/customer_feedback_screen.dart#L105) Fehler ohne Retry | `AppStatusBanner` + Retry |
| kein Suchfeld/ein Filter | `SearchBar` + `AppSegmented` |

**Touch/Barrierefreiheit/Offline.** Wie §4. Beide Zwillinge teilen künftig ein extrahiertes gemeinsames Listen-Gerüst (nur UI-Refactor, kein Datenpfad).

---

### 6. Push-Einstellungen (Benachrichtigungen)
`lib/screens/notification_settings_screen.dart` · Einstellungen → `NotificationSettingsScreen`

**Zielbild & IA.** V2-Einstellungsscreen mit `AppSectionCard`-Gruppen (Master / Kategorien / Ruhezeiten), `BreadcrumbAppBar`, sichtbarem Speichern-Feedback. Anforderung 14 (informieren, nicht überfluten): pro Kategorie kurze `helperText`-Erklärung, was sie auslöst.

**Mobile-Layout.** `AppSectionCard` „Benachrichtigungen aktiv" (Master-`SwitchListTile`, 48 dp), `AppSectionCard` „Kategorien" (5 Switches mit `subtitle`-Erklärung), `AppSectionCard` „Ruhezeiten" (Nicht-stören + Von/Bis-`ListTile` mit `showTimePicker(locale: de_DE)`). Persistenz: kein stilles fire-and-forget — kurze „Gespeichert"-Bestätigung bzw. bei Fehler Klartext + Retry (behebt `:30-33`).

**Tablet/Desktop.** maxWidth 720 zentriert (bereits), zweispaltige Gruppierung ab 840 optional.

**lib/ui-Komponenten.** `AppSectionCard`, `BreadcrumbAppBar`, `AppStatusBanner`.

**Vorher → Nachher.**

| Vorher | Nachher |
|---|---|
| [notification_settings_screen.dart:57](lib/screens/notification_settings_screen.dart#L57) generische `AppBar` | `BreadcrumbAppBar` |
| [notification_settings_screen.dart:67-126](lib/screens/notification_settings_screen.dart#L67) rohe `Card`/`SwitchListTile` | `AppSectionCard` |
| [notification_settings_screen.dart:30-33](lib/screens/notification_settings_screen.dart#L30) fire-and-forget, kein Fehler | „Gespeichert"/Fehler-Feedback + Retry |
| [notification_settings_screen.dart:38-42](lib/screens/notification_settings_screen.dart#L38) `showTimePicker` ohne Locale | `locale: Locale('de','DE')` |

**Touch/Barrierefreiheit.** Switches ≥ 48 dp; Zustand (an/aus) wird von Screenreader angekündigt (Switch tut das nativ); Von/Bis mit `Semantics`-Label. **Datenschutz (29):** Hinweis, dass Push-Freigabe die einzige Systemberechtigung ist; Master-Aus = keine Benachrichtigungen.

**Offline/iOS/Android.** Optimistisches Umschalten + Sync-Banner bei Offline. iOS: `.adaptive`-Switch/Cupertino-TimePicker-Anleihe. Android: Material-TimePicker (de_DE).

---

### 7. Abwesenheits-/Urlaubskonto-Übersicht (admin)
`lib/screens/abwesenheit_screen.dart` · Personal → `AbwesenheitScreen`

**Zielbild.** Nutzt bereits korrekt `AppKontoTile`/`AppStatusBanner`/`AppEmptyState` — nur gezielt ergänzen: **Suche/Filter** über Mitarbeiter, Jahr-Wähler mit Grenzen, Semantics für farbcodierte Kennzahlen.

**Mobile-Layout.** `SearchBar` über der Mitarbeiterliste (Name-Filter, behebt `:68-96`). `_JahrWaehler` mit min/max-Grenzen → chevron-Buttons an den Enden deaktiviert (behebt `:112-126`). Kennzahl-Kacheln „Resturlaub" → `Semantics(label: 'Resturlaub -2 Tage, kritisch')` zusätzlich zur Farbe (behebt `:178-181`).

**Tablet/Desktop.** Master-Detail ab 840: Mitarbeiterliste links, Konto-Detail rechts.

**lib/ui-Komponenten.** `AppKontoTile`, `AppStatusBanner`, `AppEmptyState`, `SearchBar`.

**Vorher → Nachher.**

| Vorher | Nachher |
|---|---|
| [abwesenheit_screen.dart:68-96](lib/screens/abwesenheit_screen.dart#L68) keine Suche | `SearchBar` (Name-Filter) |
| [abwesenheit_screen.dart:112-126](lib/screens/abwesenheit_screen.dart#L112) unbegrenzter Jahr-Wechsel | min/max, Ende-Buttons disabled |
| [abwesenheit_screen.dart:178-181](lib/screens/abwesenheit_screen.dart#L178) Kennzahl nur farblich | + Semantics-Textäquivalent |

**Touch/Barrierefreiheit/Offline.** Jahr-Buttons ≥ 48 dp; Kontrast der warnung/gut-Töne in beiden Themes; Offline-Banner analog. Reduce-Motion beim Aufklappen der `AppKontoTile`.

---

### Globale Anti-Pattern-Prüfung (Pre-Delivery)
- 🔴 **Barrierefreiheit:** 0 Semantics im ganzen Bereich → Header/Icons/Kennzahlen auszeichnen; Kontrast beider Themes prüfen; Dynamic Type 200 % ohne Bruch.
- 🔴 **Suche fehlt überall** → `SearchBar` in Inbox/Wünsche/Feedback/Urlaubskonto.
- 🟠 **Klon-Widgets** (`_WishCard`/`_FeedbackCard`/`_InboxItemCard`/`_HeroPill`/`_BadgePill`) → durch `AppCard`/`AppStatusBadge`/`AppStatCards` ersetzen.
- 🟠 **Rohe `error.toString()`** → Klartext + Retry.
- 🟠 **Umlaute** flächendeckend reparieren.
- 🟡 **Daumenzone**: Primäraktionen nach unten (FAB/untere Leiste/sticky CTA).
- 🟡 **Offline-UX** statt stiller fire-and-forget/nur Demo-Sperre.
- 🟡 **Native Muster**: pull-to-refresh, Swipe-Actions, `.adaptive`-Controls je Plattform.


## 15. Bereich — Kontakte (Adressbuch)

**Zielbild in einem Satz:** Aus dem einspaltigen „Karteikasten" (contacts_screen.dart, 1883 Z.) wird ein handlungsfähiges, adaptives Adressbuch: mobil eine ruhige, filterbare Liste mit fingergroßen Karten und Direktaktionen (Anrufen/Mailen/Route), auf Tablet/Desktop ein echtes Master-Detail. Alles auf Signal-Teal-V2-Tokens/-Komponenten, Deutsch/de_DE, Dark+Light, konsequent barrierefrei.

Leitplanke eingehalten: **nur Optik/Layout/Struktur/UX**. Kein Eingriff in `ContactProvider`, `Contact`/`ContactActivity`-Modelle, Serialisierung, Firestore/Functions. Die Detailaktionen „Anrufen/Mailen/Website/Route" sind reine `url_launcher`-Aufrufe auf bereits vorhandenen Feldern (kein Datenmodell-Touch). Der `ContactType`-Wortlaut und die Enum-`value`s bleiben unangetastet.

### Übergreifende Architektur & Breakpoints

| Breite | Layout | Navigation |
|---|---|---|
| < 600 dp (Handy) | Single-Column-Liste, Detail als V2-Bottom-Sheet (`AppBottomSheetScaffold`), FAB unten rechts, Filter über eine **eine** Chip-Zeile + Filter-Sheet | Tab-Kontext, System-Zurück schließt Sheets |
| 600–839 dp (Tablet) | **Master-Detail** 40/60 Split (`ResponsiveLayout`/`MobileBreakpoints`): Liste links, Detail-Panel rechts (inline statt Sheet) | Auswahl markiert Zeile, Detail bleibt sichtbar |
| ≥ 840 dp (Desktop) | Master-Detail 33/67, Liste mit dichteren Zeilen, Detail-Panel + optional Verlauf-Spalte | Rail-Kontext; Editor als rechtsseitiges Panel-Sheet |

Der Umschaltpunkt wird über `MobileBreakpoints`/`ResponsiveLayout` aus `lib/widgets/responsive_layout.dart` (bereits im `ui.dart`-Barrel) gelesen — **nicht** hartkodiert. Der bestehende `ConstrainedBox(maxWidth: 1100)` (contacts_screen.dart:92-93) bleibt als Desktop-Obergrenze für das Split, die Liste bekommt eine eigene `maxWidth`.

---

### 1. Liste + Kopfbereich (Haupt-Screen)

**Zielbild:** Ruhiger, gestraffter Kopf. Wichtigstes zuerst: Suche + Kategorie. Kennzahlen und Sekundärfilter verdichtet, damit der erste Kontakt „above the fold" erscheint.

**Informationsarchitektur (vorher 7 gestapelte Kopf-Blöcke, contacts_screen.dart:104-131):**
1. `SectionHeader` (Titel/Breadcrumb) — bleibt.
2. **Sticky-Suchleiste** (`SliverPersistentHeader`, pinned) mit Suchfeld + einem `Icons.tune`-Filter-Button (öffnet Filter-Sheet). Export/Import wandern in ein Überlauf-Menü (`PopupMenuButton`, `Icons.more_vert`) rechts im Header — entlastet die Suchzeile (vorher zwei Icon-Buttons direkt neben dem Suchfeld, :227-236).
3. **Eine** horizontale Kategorie-Chip-Zeile (statt zwei getrennter Scroll-Reihen, :250-273 + :275-324). Standort/„Wichtig"/„Archivierte" ziehen ins Filter-Sheet um; nur ihre **aktiven** Werte erscheinen als entfernbare Chips vor den Kategorien („Standort: Tabak Börse ✕").
4. Kennzahlen (`AppStatCards`, vorher `_StatsRow`/:117) werden zu **einer kompakten `AppStatCards`-Zeile mit 3 Werten** (Aktiv/Kunden/Lieferanten) — auf < 360 dp horizontal scrollbar statt Umbruch, damit sie nicht die halbe erste Bildschirmhöhe füllen.
5. `_ResultCountBar` (:125) wird zu einem schlanken Text „X von Y · Filter zurücksetzen" **nur wenn Filter aktiv** — die doppelte Reset-Affordance (Zählleiste + Leerzustand, :125-129 vs. :343-352) entfällt zugunsten des Leerzustand-Resets.

**Primäraktion:** „Kontakt anlegen" (FAB, `Icons.person_add_alt_1`) — bleibt unten rechts, `ExpandableFab` auf **einfachen `FloatingActionButton.extended`** reduziert (nur eine Aktion, :77-86 → kein Expandable nötig; spart einen Tap).

**Mobile-Layout:** `CustomScrollView` bleibt; Suchleiste als pinned Sliver in der Daumenzone erreichbar beim Scrollen. Listen-Padding unten = `spacing.xxl` (einmal, statt `xxl+xxl`, :161) plus FAB-Höhe.

**Tablet/Desktop:** Liste links (`Flexible`, min 320 dp), Detail rechts. FAB bleibt an der Liste; „anlegen" öffnet Detail-Panel im Editier-Modus.

**lib/ui-Komponenten:** `SectionHeader`, `AppStatCards`, `AppFormField` (Suche), `AppFilterChip`, `AppEmptyState`, `AppCard` (Zeilen), `ResponsiveLayout`.

**Vorher→Nachher:**
- [contacts_screen.dart:250-324](lib/screens/contacts_screen.dart#L250) zwei horizontale Filterreihen → **eine** Kategorie-Zeile + Filter-Sheet.
- [contacts_screen.dart:227-236](lib/screens/contacts_screen.dart#L227) Export/Import als nackte Icon-Buttons → Überlauf-Menü mit Text+Icon.
- [contacts_screen.dart:117](lib/screens/contacts_screen.dart#L117) `_StatsRow` (Umbruch) → kompakte scrollbare `AppStatCards`.
- [contacts_screen.dart:161](lib/screens/contacts_screen.dart#L161) doppeltes `xxl`-Padding → einfaches.

**Touch/A11y:** Filter-Chips ≥ 48 dp Tap-Höhe (min `spacing`-Padding). Suchfeld mit `Semantics(label: 'Kontakte durchsuchen')`. Kennzahl-Karten als `Semantics(label: '128 aktive Kontakte')` zusammengefasst, nicht Ziffern-Fragmente. Kontrast der `onSurfaceVariant`-Texte ≥ 4.5:1 (bereits Theme-konform).

**Offline:** Über der Liste bei fehlender Verbindung ein dezentes `AppStatusBadge`(tone: warning) „Offline · Stand HH:mm" (Konnektivität aus App-State, kein neuer Read). Suche/Filter arbeiten rein clientseitig auf der gestreamten Liste → offline voll nutzbar.

**Motion:** Filter-Sheet slide-up (`AppMotion.medium`), Chip-Selektion ohne Bounce. `MediaQuery.disableAnimations` respektieren → Übergänge auf Cross-Fade reduzieren.

---

### 2. Kontakt-Karte (_ContactCard)

**Zielbild:** Sofort unterscheidbare Zeile mit **Initialen-Avatar** (statt generischem Typ-Icon), klarer Name-Zeile, dezenter Meta-Zeile und rechtsbündigen **Direkt-Aktionen** (Anruf/Mail) plus Überlauf.

**Vorher (contacts_screen.dart:881-1034):** 48×48 Typ-Icon-Avatar (:1027), keine Semantics, `PopupMenuButton` mit 3 Items (:1051-1091), eigenes `_MetaChip` mit hardkodiertem `surfaceContainerHighest` (:1095-1129).

**Nachher:**
- Avatar = `CircleAvatar` mit `contact.initials` (wie der Picker, contact_picker_field.dart:185) + typ-getönter Hintergrund aus `_typeTone`→`appColors`. Konsistent zwischen Liste, Picker und Detail.
- Meta = `AppStatusBadge`(Typ, filled) + optional „Archiviert"-Badge + Standort als `InfoChip` (aus `lib/ui`, ersetzt `_MetaChip`, :1095-1129).
- Rechte Zone: bei vorhandener Telefonnummer ein **Anruf-IconButton** (`Icons.call`, 48 dp), sonst Mail; dahinter das Überlauf-Menü (Favorit/Bearbeiten/Löschen) **nur `canManage`**.
- Ganze Karte in `Semantics(button: true, label: 'Kontakt <Name>, <Typ>, <Standort>', hint: 'Öffnen')`.

**Mobile:** `Dismissible`-Swipe optional: links→Favorit (`Icons.star`), rechts→Bearbeiten (nur `canManage`) — natives Listen-Muster statt 3-Punkt-only. Löschen bleibt bewusst im Menü (destruktiv, kein versehentlicher Swipe).

**Tablet/Desktop:** Zeile wird bei Auswahl `selected`-getönt (`secondaryContainer`), Hover-State auf Desktop.

**lib/ui:** `AppCard`, `AppStatusBadge`/`AppStatus`, `InfoChip`.

**A11y:** Avatar `excludeSemantics` (Initialen sind im Karten-Label enthalten). Aktions-IconButtons mit `tooltip`+`Semantics`-Label („<Name> anrufen"). Touch-Ziele ≥ 48 dp, Mindestabstand `spacing.sm`.

**Motion:** Swipe-Reveal nativ; Favoriten-Toggle mit kurzem Scale-Puls (`AppMotion.fast`), bei Reduce-Motion aus.

---

### 3. Detail — Master-Detail-Panel / Bottom-Sheet (_ContactDetailSheet)

**Zielbild:** Vom reinen Info-Sheet zur **Aktionszentrale**. Oben eine CTA-Zeile mit großen runden Schnellaktionen (Anrufen · SMS/Mobil · E-Mail · Website · Route), darunter gruppierte Daten, darunter Verlauf.

**Vorher (contacts_screen.dart:1147-1409):** nur `_DetailRow`s + Kopier-Icon, keine ausführbaren Aktionen (:1261-1295); „Alle anzeigen" mit hardkodierten 16/18/10 (:1158-1213); Löschen gleichprominent wie Bearbeiten (:1380-1402); Aktivitätsdatum manuell (:1141-1145).

**Nachher:**
- **CTA-Zeile** aus `AppQuickAction`-Kacheln: Anrufen (`tel:`), Nachricht (`sms:` bei Mobil), E-Mail (`mailto:`), Web (`https`), Route (`geo:`/Maps-URL) — **nur die vorhandenen** Kanäle werden gezeigt. Reine `url_launcher`-Aufrufe, kein Modell-Touch. Erfüllt „Datenaktionen ausführbar" (globaler High-Befund) und „wenige Schritte".
- Datenfelder in **Abschnitten**: „Kommunikation" (Ansprechpartner/Telefon/Mobil/Mail/Web), „Adresse" (mit Route-Link), „Geschäftlich" (USt/Kd-Nr.), „Notiz". `_DetailRow` behält Kopier-Icon, bekommt aber `onTap`→Launch bei tel/mail/url.
- **Verlauf** als eigener `AppSectionCard`-Block; „Alle N anzeigen" nutzt `DraggableScrollableSheet` mit **Tokens** statt 16/18/10.
- **Aktionsfußzeile**: „Bearbeiten" = `FilledButton` volle Breite (Primär). „Löschen" abgesetzt als **`TextButton` in error-Ton** darunter/klein (nicht mehr 50/50 gleichprominent) → Fehlervermeidung. „Aktivität erfassen" als sekundärer `OutlinedButton`.
- Aktivitätsdatum via `DateFormat.yMMMMEEEEd('de_DE')`/`Hm('de_DE')` (ersetzt manuelles padLeft :1141-1145).

**Mobile:** Bottom-Sheet, CTA-Zeile in der oberen Sheet-Hälfte, Aktionsfußzeile sticky am unteren Rand (Daumenzone) via `AppBottomSheetScaffold`-Footer.

**Tablet/Desktop:** Inline-Detail-Panel rechts (kein Sheet); Aktionsfußzeile am Panelfuß. Bei „kein Kontakt gewählt" ein `AppEmptyState` „Kontakt auswählen".

**lib/ui:** `AppBottomSheetScaffold`, `AppQuickAction`, `AppSectionCard`, `AppStatusBadge`, `InfoChip`.

**A11y:** CTA-Kacheln mit klaren Labels („Katrin Meyer anrufen"). Kopier-/Launch-Rückmeldung per SnackBar. Kontrast error-Ton aus `appColors.danger`.

**Offline:** `tel:`/`mailto:`/`geo:` funktionieren offline (System-Apps). Web-Link zeigt bei Offline dezenten Hinweis. Verlauf ist gecacht.

**iOS/Android:** `tel:`/`sms:`/`mailto:` sind plattformnativ; Route öffnet Apple Maps (iOS) bzw. Google Maps (Android) über plattformgerechte URL. Sheet-Drag + System-Zurück nativ.

---

### 4. Editor-Sheet (_ContactEditorSheet)

**Zielbild:** Aus dem 13-Felder-Flachformular (contacts_screen.dart:1565-1759) ein **gruppiertes, validiertes** Formular mit stickyem Speichern-Button und Schutz vor Datenverlust.

**Vorher:** flache Column ohne Abschnitte; nur Name validiert (:1576); rohe `DropdownButtonFormField` für Kategorie/Standort (:1580-1601/:1697-1717); kein `PopScope` (:1562); PLZ fixe width 120 (:1657); Speichern scrollt weg (:1751).

**Nachher — Abschnitte (`AppSectionCard`/`_EditorSection`-Muster):**
1. **Basis:** Name* (Pflicht, validiert), Kategorie (V2-Dropdown-Feld im `AppFormField`-Stil statt rohem `DropdownButtonFormField`), „Wichtig"/„Aktiv" als `AppSegmented`/Switch.
2. **Kommunikation:** Ansprechpartner, Telefon/Mobil (Row), E-Mail, Website.
3. **Adresse:** Straße, PLZ/Ort (PLZ mit `TextInputType.number` + `LengthLimitingTextInputFormatter(5)`, responsive Breite statt fixe 120).
4. **Geschäftlich:** USt-/Steuernr., Kd-/Lieferantennr., Standort.
5. **Sonstiges:** Schlagworte, Notiz.

**Validierung/Fehlervermeidung:**
- E-Mail: Format-Regex → Inline-Fehler „Bitte gültige E-Mail eingeben".
- Website: fehlendes `https://` wird toleriert/ergänzt-Hinweis; grobe URL-Prüfung.
- PLZ: 5 Ziffern.
- Alle Fehler inline unter dem Feld (`AppFormField.errorText`), Speichern springt zum ersten Fehler.
- **`PopScope`** mit „Ungespeicherte Änderungen verwerfen?"-`AppConfirmDialog` beim Schließen mit Dirty-State.
- **Speichern-Button sticky** im `AppBottomSheetScaffold`-Footer (immer in Daumenzone).

**Mobile:** `keyboardType`/`textInputAction: next` durchgängig; Sheet scrollt, Footer bleibt. Autofokus auf Name bei Neuanlage.

**Tablet/Desktop:** Editor als rechtsseitiges Panel-Sheet (max 560 dp), zweispaltige Feldpaare (Telefon/Mobil, PLZ/Ort) nebeneinander.

**lib/ui:** `AppFormField`, `AppSectionCard`, `AppSegmented`, `AppBottomSheetScaffold`, `AppConfirmDialog`.

**A11y:** Pflichtfeld mit „*" + `Semantics`-Hint „Pflichtfeld". Fehlermeldungen `liveRegion`. Kontrast der error-Zustände über `appColors`.

**Motion:** Fehler-Feld dezentes Shake nur bei aktivierter Motion.

---

### 5. Aktivität erfassen (_addActivity)

**Zielbild:** Konsistentes **V2-Bottom-Sheet** statt `AlertDialog` (contacts_screen.dart:570-649).

**Nachher:** `AppBottomSheetScaffold` mit `AppSegmented` für die Art (Telefonat/Notiz/Termin/…), Datum **und Uhrzeit** (`showDatePicker`+`showTimePicker`, `occurredAt` trägt Zeit), Notiz-Feld. Datum via `DateFormat.yMd('de_DE')`. **Mindestvalidierung:** Speichern nur, wenn Notiz ODER Typ ≠ „Notiz" → verhindert leere Einträge (vorher :635-645 ungeprüft). Sticky Speichern-Footer.

**lib/ui:** `AppBottomSheetScaffold`, `AppSegmented`, `AppFormField`.

**A11y/iOS/Android:** native Date/Time-Picker; Sheet-Drag; `de_DE`-Formatierung.

---

### 6. CSV-Import (_importCsv)

**Zielbild:** Datei-Picker-first, responsiv, mit Ergebnis-Details.

**Vorher (contacts_screen.dart:460-539):** fixe Dialogbreite 460 (:471), nur Text-Paste (:483), Fehler summarisch (:512).

**Nachher:** V2-Bottom-Sheet (volle Breite mobil, max 560 dp Desktop). Primär: „Datei wählen" (`file_picker`, .csv) — reiner UI-Zweig, füttert denselben `ContactCsvImport.parse`. Text-Paste als Sekundär-Option (Expandable). Nach Parse ein **Vorschau-/Ergebnis-Block**: „N werden importiert, M übersprungen" + aufklappbare Fehlerliste (statt nur `errors.first`, :515). `AppConfirmDialog` bleibt als finale Bestätigung.

**lib/ui:** `AppBottomSheetScaffold`, `AppConfirmDialog`, `AppSectionCard` (Fehlerliste).

**A11y/Fehler:** Jede übersprungene Zeile mit Zeilennummer + Grund; `Semantics`-Zusammenfassung.

---

### 7. Kontakt-Auswahl-Sheet (showContactPicker / ContactPickerField)

**Zielbild:** Den Klon (contact_picker_field.dart:136-204) auf dieselben V2-Bausteine wie die Hauptliste heben — gleicher Avatar (Initialen), `AppFormField`-Suche, `AppCard`/`ListTile`-Konsistenz, plus **Typ-Filterchips** wenn `allowedTypes` gesetzt.

**Vorher:** rohes `TextField`/`ListTile` mit 16/8-Paddings (:159/:184), fixe 70%-Höhe (:155), keine Typ-Filter trotz `allowedTypes` (:142-148).

**Nachher:** `DraggableScrollableSheet` (statt fixe 0.7 → tastaturfreundlich), `AppFormField`-Suche, `AppFilterChip`-Zeile nur bei `allowedTypes`, Einträge mit Initialen-Avatar (identisch zur Karte, :185 bleibt Referenz). `ContactPickerField`-Trigger bleibt `InputDecorator`, aber im `AppFormField`-Stil.

**lib/ui:** `AppFormField`, `AppFilterChip`, `AppBottomSheetScaffold`.

**A11y:** „Kein Kontakt"-Eintrag klar als erste Option mit Icon+Label; Sheet-Titel via `Semantics`.

---

### 8. Fehler-/Lade-/Leerzustände

**Zielbild:** Retry-fähiges Fehlerbanner, Offline-/Stand-Indikator, Skeleton statt nacktem Spinner.

**Vorher (contacts_screen.dart:1851-1883 / :142-153 / :326-353):** `_ContactsErrorBanner` nur mit Close, hardkodiert 16/10 (:1864); zentrierter `CircularProgressIndicator`; kein Offline-Hinweis.

**Nachher:**
- Fehlerbanner: `AppStatusBadge`/`AppSectionCard`(tone: danger) mit Icon+Text+**„Erneut versuchen"** + Close, Tokens statt 16/10.
- Ladezustand: 4–5 **Skeleton-Karten** (schimmernde `AppCard`-Platzhalter) statt Spinner → gefühlt schneller (Performance-Wahrnehmung).
- Offline: `warning`-Banner „Offline · zuletzt aktualisiert HH:mm" (aus App-Konnektivitäts-State).
- Leerzustände: `AppEmptyState` bleibt, einziger Reset-Punkt.

**lib/ui:** `AppEmptyState`, `AppSectionCard`, `AppStatusBadge`.

**A11y:** Banner `liveRegion`; Skeletons `ExcludeSemantics` + `Semantics(label: 'Kontakte werden geladen')`.

---

### Native iOS/Android-Feinheiten (übergreifend)
- **Zurück:** Sheets/Panels reagieren auf iOS-Edge-Swipe und Android-Systemgesture; `PopScope` fängt Dirty-Editor ab.
- **Kommunikation:** `tel:`/`sms:`/`mailto:`/`geo:` plattformnativ; Maps-URL plattformgerecht.
- **Picker:** native Date/Time-Picker (Cupertino-Look auf iOS via Material-Adaptive).
- **Haptik:** leichte `HapticFeedback.selectionClick` bei Favorit-Toggle/Chip (iOS spürbar), bei Reduce-Motion/Systemeinstellung respektiert.
- **Dark/Light:** ausschließlich `appColors`/ColorScheme-Rollen; keine Hex.


## 16. Bereich — Laden (Warenwirtschaft & Kasse)

**Zielbild des Gesamtbereichs.** Der Laden-Bereich wird von einem lose gekoppelten Sammelsurium aus Legacy-`Card`/`ListTile`/`AlertDialog` und file-privaten Klon-Widgets auf das Signal-Teal-Design-System (`lib/ui/ui.dart`) gehoben. Leitmotive: (1) **Eine Primäraktion pro Screen**, in der Daumenzone unten; (2) **Status nie nur über Farbe** — immer Icon + Text + `Semantics`; (3) **Formulare als `AppBottomSheetScaffold`** statt fixbreiter Dialoge; (4) **Master-Detail ab 840 dp** für alle Listen-Screens; (5) **Offline-Transparenz** über ein globales „Zuletzt aktualisiert / Offline"-Band. Alle Farben aus `Theme.of(context).appColors`, alle Abstände/Radii/Motion aus den Tokens (`AppSpacing`/`AppRadii`/`AppMotion`), Dark+Light durchgängig geprüft. Die go_router-Shell und alle Routen (`/warenwirtschaft`, `/kundenbestellungen`, `/scanner`, Analysen, `/arbeitsmodus`) bleiben unverändert — nur die Screen-Innereien werden neu aufgebaut.

**Querschnitts-Prinzipien (gelten für ALLE Unterbereiche)**

| Prinzip | Umsetzung |
|---|---|
| Status-Redundanz | Jeder Status-Indikator = `AppStatus`/`AppStatusPill` mit Icon + Label + `appColors`-Ton; `CircleAvatar`-Farbe nie alleiniger Träger. `Semantics(label: '3 Artikel unter Mindestbestand')`. |
| Formulare | `AppBottomSheetScaffold` (`showDragHandle`, `isScrollControlled`, `useSafeArea`) + `AppFormField`; `autovalidateMode: onUserInteraction`; Fokus-Sprung zum ersten Fehler; sticky Primärbutton unten in `SafeArea`. |
| Suche/Filter | Entprelltes Suchfeld (250 ms Debounce) + horizontale Filter-Chip-Leiste (Kategorie/Lieferant/„nur knapp"); einheitlich `AppFormField`/`AppSegmented` statt nackter `DropdownButton`. |
| Touch/A11y | Alle Tap-Ziele ≥ 48 dp; Dynamic Type bis 200 % ohne Overflow (Grid statt manueller Breitenrechnung); Kontraste ≥ 4,5:1. |
| Motion | Nur `AppMotion.short/medium`; `MediaQuery.disableAnimations`/Reduce-Motion respektiert (Cross-Fade statt Slide). |
| Offline | Globales `_ConnectivityBand` oben (aus `daten/21_offline-modus`): „Offline — Bestand vom … (zuletzt aktualisiert)". Schreibaktionen bleiben nutzbar (Firestore-Offline-Cache), zeigen „wird synchronisiert"-Pending-Chip. |
| Deutsch | Alle `ae`/`oe`/`ue`-Fälle auf echte Umlaute (`'Alle Läden'`, `'wählen'`, `'für'`, `'löschen'`). |

---

### 1. Laden-Hub (`_ShopHubTab`)

**Zielbild.** Der Hub bleibt der Einstieg, wird aber zum vollständigen, gruppierten Cockpit: alle fachlichen Ziele (inkl. der heute versteckten Analysen) sind sichtbar, nach Aufgaben-Blöcken geordnet, mit sprechenden Status-Badges.

**Informationsarchitektur & Primäraktion.** Drei Gruppen via `SectionHeader`: **„Tägliche Arbeit"** (Warenwirtschaft, Scanner, Kundenbestellungen, Kühlschrank), **„Auswertungen"** (Bestell-Auswertung, Bestand-Insights, Sortiment, Laden-Benchmark, Kassierer-Prüfung, Tagesabschluss — admin-gated), **„Verwaltung"** (Personal, Kundenfeedback, Änderungsprotokoll). Primäraktion = die visuell hervorgehobene Warenwirtschafts-Kachel (`AppHeroCard`) mit Live-Kennzahlen.

**Mobile-Layout.** `ListView` mit `AppQuickAction`-Kacheln; 2 Spalten via `_BalancedTileGrid` (bleibt). Oben eine `AppHeroCard` „Warenwirtschaft" mit `AppStatCards`-Minireihe (Warenwert · knappe Artikel · offene Bestellungen). Badges als `AppStatusPill` mit Icon (`warning`-Ton + `Icons.error_outline`) und `Semantics`.

**Tablet/Desktop.** Ab 840 dp 3-spaltiges Raster, `maxWidth 960` bleibt; Hero über volle Breite.

**lib/ui-Komponenten.** `AppHeroCard`, `AppStatCards`/`AppMetricCard`, `AppQuickAction`, `AppStatus`, `SectionHeader`, `AppEmptyState`.

**Vorher→Nachher.**
- Analysen nur über verschachteltes AppBar-Menü ([inventory_screen.dart:247](lib/screens/inventory_screen.dart#L247)) → als eigene „Auswertungen"-Gruppe im Hub direkt sichtbar.
- Nacktes Badge `'3 knapp'` ([home_screen.dart:2854](lib/screens/home_screen.dart#L2854)) → `AppStatusPill(icon: Icons.error_outline, label: '3 Artikel knapp', tone: warning)` + `Semantics`.
- Flache Kachel-Liste ([home_screen.dart:2846](lib/screens/home_screen.dart#L2846)) → gruppiert + Hero-Kachel mit Kennzahlen.

**A11y/Touch.** Kacheln ≥ 88 dp hoch, `Semantics(button: true, label: 'Warenwirtschaft, 3 Artikel knapp')`. **Offline.** Kennzahlen aus In-Memory-Listen (schon offline-sicher), Band zeigt Stand. **Motion.** Kachel-Tap: `AppMotion.short` Ripple. **iOS/Android.** Kein Cupertino nötig (Hub); Back-Geste über Shell-`PopScope`.

---

### 2. Warenwirtschaft — Shell (`InventoryScreen`)

**Zielbild.** Weg von 5 scrollbaren Tabs + überladener AppBar hin zu einer **aufgeräumten Sub-Navigation** mit klarer Primäraktion je Ansicht und Aktionen in der Daumenzone.

**Informationsarchitektur & Primäraktion.** Reduktion auf **4 Kern-Ansichten**: **Bestand · Bestellkorb · Bestellungen · Lieferanten**. Kühlschrank wird aus der Warenwirtschaft-TabBar **in den Hub** verschoben (eigene Kachel — er ist eine geteilte Checkliste, kein WaWi-Kernobjekt). AppBar trägt nur noch **Titel + Suchsymbol + ein „Mehr"-Overflow** (OktoPOS/Export/Auswertungen/Kundenwünsche gebündelt). Primäraktion je Tab = FAB (Artikel/Warenkorb/Bestellung/Lieferant), plus eine **untere Aktionsleiste** auf Mobile für Sekundäraktionen.

**Mobile-Layout (Daumenzone).**
- Untere **`NavigationBar`-artige Segment-Leiste** (`AppSegmented`) für die 4 Ansichten statt scrollbarer Top-TabBar → alle 4 Ziele sichtbar, keine off-screen-Tabs. Badges als kleine `AppStatusPill`.
- Der FAB bleibt unten rechts; Overflow-Aktionen (Export/OktoPOS) wandern in ein **`AppBottomSheetScaffold`-Aktionsblatt** (per „Mehr"-Icon), erreichbar mit dem Daumen statt oben im AppBar-PopupMenu.
- Site-Filter als `AppSegmented`/Chip-Leiste unter dem AppBar (nur bei > 1 Laden).

**Tablet/Desktop (Master-Detail, 600/840).** Ab 600 dp: Site-Filter + Ansichts-Wechsel als linke `NavigationRail` (Icons+Label ab 840). Ab 840 dp **Master-Detail**: links Ansichts-Rail, Mitte Liste, rechts Detail-Panel (Produkt/Bestellung) statt Vollbild-Sheet.

**lib/ui-Komponenten.** `AppSegmented` (Ansichts-/Site-Wechsel), `AppBottomSheetScaffold` (Aktionsblatt), `AppStatus` (Tab-Badges), `BreadcrumbAppBar` (bleibt), `ActionFab`.

**Vorher→Nachher.**
- Bis zu 4 Trailing-AppBar-Aktionen + verschachtelte PopupMenus ([inventory_screen.dart:190-306](lib/screens/inventory_screen.dart#L190)) → 1 Such-Icon + 1 „Mehr"-Overflow → Aktionsblatt.
- `isScrollable` 5-Tab-TabBar ([inventory_screen.dart:325](lib/screens/inventory_screen.dart#L325)) → 4er `AppSegmented` (unten auf Mobile) / Rail (Desktop); Kühlschrank raus.
- `_TabLabel`-Badge `colorScheme.error` ohne Semantics ([inventory_screen.dart:949](lib/screens/inventory_screen.dart#L949)) → `AppStatusPill(tone: warning, Semantics)`.
- `'Alle Laeden'` ([inventory_screen.dart:907](lib/screens/inventory_screen.dart#L907)) → `'Alle Läden'`.

**A11y/Touch.** Segment-Buttons ≥ 48 dp, `Semantics(selected:)`. **Offline.** Band + Pending-Chip. **Motion.** Ansichtswechsel = Cross-Fade (`AnimatedSwitcher`, `AppMotion.medium`), Reduce-Motion → sofort. **iOS/Android.** Untere Segment-Leiste folgt Material-BottomNav (Android) bzw. fühlt sich wie iOS-TabBar an; Edge-Swipe-Back bleibt (kein horizontales Tab-Swipe, das mit iOS-Back kollidiert).

---

### 3. Warenwirtschaft — Tab Bestand (`_StockTab` / `_ProductTile`)

**Zielbild.** Schnell scanbare, filterbare Produktliste; Bestandsstatus sofort erkennbar (Icon+Text), Zahlen in Tabellenziffern.

**Informationsarchitektur & Primäraktion.** Oben: entprelltes Suchfeld + Filter-Chips („nur knapp", Kategorie, Lieferant). Darunter `AppMetricCard`-Reihe (Warenwert). Dann `_ReorderBanner` als `AppStatus`-Banner. Liste aus `AppCard`-Produktkacheln. Primäraktion pro Zeile = „in Korb" (großer Toggle-Button), sekundär = Overflow.

**Mobile-Layout.** Produktkachel: links `AppStatusPill` mit Bestandszahl + Statusfarbe **und** Icon (`Icons.error_outline` leer / `Icons.trending_down` nachbestellen / `Icons.check` ok); Titel fett; Metadaten als **strukturierte Zeile** (Warengruppe-Chip · Min · VK in `tabularFigures`) statt `·`-String. „In Korb" als 48-dp-Button rechts. Destruktives „Löschen" im Overflow **mit Warnfarbe + Trennlinie**.

**Tablet/Desktop.** Ab 840 dp 2-spaltige Kachel-Grid oder Tabelle; Tap → rechtes Detail-Panel statt Sheet.

**lib/ui-Komponenten.** `AppCard`, `AppStatus`/`AppStatusPill`, `AppFormField` (Suche), `AppMetricCard`, `InfoChip`, `AppEmptyState`.

**Vorher→Nachher.**
- Suche `setState` pro Tastenanschlag ([inventory_screen.dart:1056](lib/screens/inventory_screen.dart#L1056)) → 250-ms-Debounce (nur UI-State, keine Provider-Änderung).
- Nur `contains`-Filter ([inventory_screen.dart:1033](lib/screens/inventory_screen.dart#L1033)) → Filter-Chip-Leiste (Kategorie/Lieferant/„nur knapp", clientseitig).
- Status nur Avatar-Farbe ([inventory_screen.dart:1220](lib/screens/inventory_screen.dart#L1220)) → Farbe **+ Icon + Semantics**.
- `·`-verketteter Subtitle ([inventory_screen.dart:1245](lib/screens/inventory_screen.dart#L1245)) → strukturierte Chips + `tabularFigures` bei Preisen.
- Overflow „Löschen" ohne Warnfarbe ([inventory_screen.dart:1289](lib/screens/inventory_screen.dart#L1289)) → `error`-Ton + Divider.

**A11y/Touch.** Zeile ≥ 64 dp, `Semantics` je Kachel („Cola, 3 auf Lager, unter Mindestbestand"). **Offline.** Bestand aus Cache; „in Korb" optimistisch + Pending-Chip. **Motion.** Filter-Wechsel `AnimatedSize`. **iOS/Android.** Swipe-to-Action optional (iOS-typisch) für „in Korb", Android Long-Press-Kontextmenü.

---

### 4. Warenwirtschaft — Lieferanten / Bestellungen (`_SuppliersTab`, `_OrdersTab`)

**Zielbild.** Beide Listen bekommen Suche/Filter und die **kanonische `AppStatus`-Statusanzeige** (Klon-Widget entfällt).

**IA & Primäraktion.** Suchfeld oben; Bestellungen zusätzlich Status-Filter-Chips (offen/gesendet/geliefert). Primäraktion = FAB „Bestellung"/„Lieferant". Bestell-Karte: Lieferant + Datum + Positionszahl + `AppStatus`-Pill.

**Mobile/Tablet.** Mobile Liste; ab 840 dp Master-Detail (Bestell-Detail rechts). Lieferant-Tap → Sheet/Detail.

**lib/ui.** `AppStatus` (ersetzt `_StatusChip`), `AppCard`, `AppFormField`, `AppEmptyState`.

**Vorher→Nachher.**
- `_StatusChip`-Klon ([inventory_screen.dart:1650](lib/screens/inventory_screen.dart#L1650)) → `AppStatus`.
- Keine Suche/Filter ([inventory_screen.dart:1475](lib/screens/inventory_screen.dart#L1475)) → Suchfeld + Status-Chips.

**A11y/Touch/Offline/Motion.** Status mit Icon+Label; ≥ 48 dp; offline aus Cache; Listenwechsel Cross-Fade.

---

### 5. Warenwirtschaft — Produkt-/Lieferanten-Formulare

**Zielbild.** Responsives Bottom-Sheet-Formular mit Live-Validierung, klaren Pflichtfeldern und formatierten Feldern.

**IA & Primäraktion.** `AppBottomSheetScaffold` mit Titel, gescrolltem Formularkörper und **sticky Primärbutton „Speichern"** unten in `SafeArea`. Felder logisch gruppiert (Stammdaten · Preise · Bestand · Steuer) via `SectionHeader`.

**Mobile-Layout.** Einspaltig, volle Breite (kein 420-dp-Quetschen). Preis-Rows brechen auf < 360 dp untereinander. Preisfelder mit €-Suffix (`prefixIcon`/`suffixText`), `keyboardType: numberWithOptions(decimal)`.

**Tablet/Desktop.** Ab 600 dp zentriertes Sheet `maxWidth 560`, Preis-/Bestand-Rows 2-spaltig.

**lib/ui.** `AppBottomSheetScaffold`, `AppFormField`, `AppSectionCard`/`SectionHeader`, `AppConfirmDialog` (Verwerfen-Schutz).

**Vorher→Nachher.**
- `AlertDialog(SizedBox(width: 420))` ([inventory_screen.dart:1808](lib/screens/inventory_screen.dart#L1808)) → `AppBottomSheetScaffold`.
- `Form` ohne `autovalidateMode` ([inventory_screen.dart:1811](lib/screens/inventory_screen.dart#L1811)) → `autovalidateMode: onUserInteraction` + Fokus-Sprung zum ersten Fehler.
- Preisfeld nur `labelText: '€'` ([inventory_screen.dart:1898](lib/screens/inventory_screen.dart#L1898)) → `suffixText: '€'`, numerische Tastatur, Bereichs-Validator.

**Formulare/Fehler.** Pflichtfeld = Label + „*" + `Semantics(hint: 'Pflichtfeld')`; Fehler on-blur mit konkretem deutschen Text („Verkaufspreis muss ≥ Einkaufspreis sein"). **A11y.** Feld-Label immer sichtbar (kein Placeholder-only). **iOS/Android.** iOS: „Fertig"-Toolbar über Nummern-Tastatur; Android: `TextInputAction.next` Feld-zu-Feld. Verwerfen-Schutz via `PopScope` + `AppConfirmDialog`.

---

### 6. Warenwirtschaft — Bestellkorb (`OrderCartTab` / Checkout)

**Zielbild.** Klare Aktionshierarchie, gruppierte Positionen, prominenter Checkout unten.

**IA & Primäraktion.** Toolbar-Buttons in eine `AppSegmented`/Menü-Struktur ordnen: **Primär** = „Wochenliste laden" (`FilledButton`), Sekundär = „Artikel"/„Bearbeiten" (`OutlinedButton`), Destruktiv = „Korb leeren" (`error`-Ton, mit Bestätigung). Checkout-Leiste unten (`AppHeroCard`-artig, sticky) mit Gesamtsumme + „Bestellen".

**Mobile.** Positionen gruppiert je Lieferant (`AppSectionCard`), Mengen-Stepper (± je 48 dp). Bottom-Inset über Token statt Magic Number.

**Tablet/Desktop.** Ab 840 dp Liste links, Zusammenfassung/Checkout als rechtes Panel.

**lib/ui.** `AppSectionCard`, `AppConfirmDialog` (Korb leeren), `AppBottomSheetScaffold` (Checkout-Details), `AppStatus`.

**Vorher→Nachher.**
- Wrap aus 4 gemischten Button-Typen ([order_cart_screen.dart:591](lib/screens/order_cart_screen.dart#L591)) → klare Primär/Sekundär/Destruktiv-Hierarchie.
- Magic-Number-Inset `120` ([order_cart_screen.dart:631](lib/screens/order_cart_screen.dart#L631)) → `kFabSafeBottomInset`/Token.
- „Korb leeren" neutral ([order_cart_screen.dart:613](lib/screens/order_cart_screen.dart#L613)) → `error`-Ton + `AppConfirmDialog`.

**A11y/Offline/Motion.** Stepper mit `Semantics(value:)`; offline erlaubt (lokaler Korb) + Pending-Chip beim Checkout; „bestellen" mit Erfolgs-Snack. iOS/Android: Stepper nativ-groß.

---

### 7. Kühlschrank-Nachfüllliste (`FridgeRefillTab`)

**Zielbild.** Als eigene Hub-Kachel/Route geführte, checklistige Ansicht mit redundanter Status-Codierung.

**IA & Primäraktion.** Primär = „Position hinzufügen" (FAB). Gruppen „Aus Lager auffüllen" / „Lager knapp" als `AppSectionCard` mit **Icon + Label**, nicht nur Farbe.

**Mobile/Tablet.** Liste mit Häkchen-Zeilen (`AppKontoTile`-Stil); Add-Sheet `AppBottomSheetScaffold` (Laden-`AppSegmented` + Artikel/Freitext) mit on-blur-Validierung.

**lib/ui.** `AppSectionCard`, `AppStatus`, `AppBottomSheetScaffold`, `AppFormField`.

**Vorher→Nachher.**
- Status primär farbig ([fridge_refill_screen.dart:349](lib/screens/fridge_refill_screen.dart#L349)) → Icon+Text+`Semantics` (baut das bestehende 1 `Semantics` aus).
- Add-Sheet ohne on-blur ([fridge_refill_screen.dart:600](lib/screens/fridge_refill_screen.dart#L600)) → `autovalidateMode`.

**A11y/Touch/Offline.** Häkchen ≥ 48 dp; offline voll nutzbar (geteilte Liste), Pending-Sync-Chip.

---

### 8. Barcode-Scanner (`ScannerScreen`)

**Zielbild.** Vollflächige Kamera, Bedienung in der Daumenzone, theming-konforme Overlays, Screenreader-Feedback und handhabbare Berechtigungsfehler.

**IA & Primäraktion.** Kamera füllt den Screen (statt `AspectRatio 3/4` im ListView). Oben: dezenter `BreadcrumbAppBar`/Titel + Modus-Chip. **Untere Steuerleiste** (in `SafeArea`, Daumenzone): Torch, Kamera-Wechsel, Ton/Vibration, „manuell eingeben". Scan-Rahmen als `appColors.success/warning`. Ergebnis als von unten einfahrendes `AppBottomSheetScaffold`.

**Mobile-Layout.** Torch-/Wechsel-Buttons von oben rechts nach **unten** verlagert (≥ 56 dp, kontrastreicher Chip-Hintergrund). Manuelle Eingabe als Sheet statt inline-Row.

**Tablet/Desktop.** Kamera zentriert `maxWidth` begrenzt; Web/Desktop ohne Kamera → prominente manuelle Eingabe + Hinweis (kIsWeb).

**lib/ui / Tokens.** `AppBottomSheetScaffold` (Ergebnis/manuell), Overlay-Farben aus `appColors`/`colorScheme` statt `Colors.white/black54`. Torch-Button als `IconButton.filledTonal` statt `_CameraButton`-Klon.

**Vorher→Nachher.**
- `AspectRatio(3/4)` im ListView + Buttons oben rechts ([scanner_screen.dart:963](lib/screens/scanner_screen.dart#L963)) → vollflächige Kamera + untere Steuerleiste.
- `Colors.black54/white`/`black45` ([scanner_screen.dart:981](lib/screens/scanner_screen.dart#L981), [scanner_screen.dart:1794](lib/screens/scanner_screen.dart#L1794)) → Theme-Tokens (Scrim `colorScheme.scrim.withOpacity`, Text `onInverseSurface`), Dark-Mode-geprüft.
- Berechtigungsfehler nur Text ([scanner_screen.dart:979](lib/screens/scanner_screen.dart#L979)) → `AppEmptyState` mit `Icons.no_photography` + **„Einstellungen öffnen"**-Button (`app_settings`/`openAppSettings`) + Erklärtext „Kamera nur zum Scannen".
- Kein Scan-Feedback ([scanner_screen.dart:458](lib/screens/scanner_screen.dart#L458)) → `SemanticsService.announce('Artikel erkannt: Cola')` + Haptik (`HapticFeedback.mediumImpact`).

**A11y/Touch.** Bedienbuttons ≥ 56 dp; Live-Region-Ansage bei Erfolg/Fehler; Rahmen-Status zusätzlich als Text/Icon. **Datenschutz.** Kamera-Only-Berechtigung, Erklär-Text vor Anforderung, kein Standort/Mikrofon. **Offline.** Scan+Buchen offline (lokaler Cache); „wird synchronisiert". **Motion.** Ergebnis-Sheet slide-up (`AppMotion.medium`), Reduce-Motion → Fade. **iOS/Android.** iOS: Kamera-Purpose-String; Android: Runtime-Permission-Rationale; Torch-API plattformneutral (mobile_scanner).

---

### 9. Kundenbestellungen (`CustomerOrderScreen`)

**Zielbild.** Sheet-Formular mit Validierung; Liste mit Suche/Status-Filter.

**IA & Primäraktion.** Suchfeld + Status-Filter oben; Primär = FAB „Neue Bestellung". Formular als `AppBottomSheetScaffold`.

**Mobile/Tablet.** Einspaltiges Sheet; ab 840 dp Master-Detail. `ContactPickerField` bleibt, Telefon/E-Mail mit `keyboardType` + Format-Validator.

**lib/ui.** `AppBottomSheetScaffold`, `AppFormField`, `AppSegmented` (Rhythmus/Laden), `AppStatus`.

**Vorher→Nachher.**
- `AlertDialog(width: 460)` ohne `autovalidateMode` ([customer_order_screen.dart:809](lib/screens/customer_order_screen.dart#L809)) → responsives Sheet + Live-Validierung.
- Kontaktfeld ohne `keyboardType` ([customer_order_screen.dart:842](lib/screens/customer_order_screen.dart#L842)) → `phone`/`emailAddress` + Validator.

**A11y/Formulare/Offline.** Pflichtfeld „Kunde" mit Fehlertext + Fokus-Sprung; offline erfassbar (Pending). iOS/Android: `TextInputAction.next`, Verwerfen-Schutz.

---

### 10. Einkaufsbestellungs-Editor (`PurchaseOrderEditorScreen`)

**Zielbild.** Vollbild-Editor mit größeren Mengenfeldern, Labels/Semantics und Verwerfen-Schutz.

**IA & Primäraktion.** Kopf: Laden/Lieferant (`AppFormField`-Dropdowns). Positionsliste mit **Stepper + Mengenfeld ≥ 48 dp** und `Semantics(label: 'Menge Cola')`. Sticky „Speichern/Senden" unten.

**Mobile/Tablet.** Mobile Vollbild; ab 840 dp zweispaltig (Positionen links, Zusammenfassung rechts).

**lib/ui.** `AppFormField`, `AppSectionCard`, `AppConfirmDialog`, `AppStatus`.

**Vorher→Nachher.**
- Inline-Mengen-TextField ohne Label ([purchase_order_screens.dart:193](lib/screens/purchase_order_screens.dart#L193)) → Stepper+Feld ≥ 48 dp + `Semantics`.
- Kein `PopScope` ([purchase_order_screens.dart:105](lib/screens/purchase_order_screens.dart#L105)) → Verwerfen-Schutz via `PopScope` + `AppConfirmDialog`.

**A11y/Offline/iOS/Android.** Mengenfelder tabular; offline speicherbar; iOS-Zahlen-Toolbar; Predictive-Back (Android 14) via `PopScope`.

---

### 11. Analysen (Bestell-Auswertung, Bestand-Insights, Sortiment, Laden-Benchmark)

**Zielbild.** Einheitliche Analyse-Vorlage: `AppStatCards`-Kennzahlen oben, Chart mit Tooltip + textueller Zusammenfassung, einheitliche Filter.

**IA & Primäraktion.** Filter als `AppSegmented`/`AppFormField`-Dropdown (einheitlich, kein nacktes `DropdownButton`). Kennzahlen via `AppStatCards`/`AppMetricCard`. Chart darunter mit `barTouchData`-Tooltip und **`Semantics`-Textsummary** („Cola: 12 Bestellungen, meistbestellt").

**Mobile/Tablet.** Chart horizontal scrollbar bei vielen Kategorien (keine abgeschnittenen Achsen); ab 840 dp Kennzahlen + Chart nebeneinander. Skeleton-Ladezustand statt Vollbild-Spinner.

**lib/ui.** `AppStatCards`/`AppMetricCard`, `AppSegmented`, `AppEmptyState`, `AppCard`.

**Vorher→Nachher.**
- `BarChart` ohne Tooltip/Semantics ([order_analytics_screen.dart:201](lib/screens/order_analytics_screen.dart#L201)) → Tooltip + Text-Summary + scrollbar.
- `DropdownButton` uneinheitlich ([bestand_insights_screen.dart:164](lib/screens/bestand_insights_screen.dart#L164), [sortiment_screen.dart:116](lib/screens/sortiment_screen.dart#L116)) → `AppSegmented`/`AppFormField`.
- Selbstgebaute Kennzahlkarten ([bestand_insights_screen.dart:221](lib/screens/bestand_insights_screen.dart#L221)) → `AppStatCards`.

**A11y/Offline/Motion.** Chart mit Alternativ-Text; Kennzahlen für Screenreader lesbar; offline aus Cache mit Stand-Hinweis; Chart-Animation nur bei aktivierter Motion.

---

### 12. Analysen — Kassierer-Prüfung / Tagesabschluss

**Zielbild.** Anomalien mit Icon+Text-Schwere; Bargeld-Eingabe mit Live-Validierung und klarer Diskrepanz-Anzeige.

**IA & Primäraktion.** Tagesabschluss: Laden/Datum (`AppSegmented`/Date-Picker), Bargeld-`AppFormField` (numerisch, on-blur), **Diskrepanz als `AppStatus`** (Icon+Betrag+Text), Primär „Abschließen" sticky unten. Kassierer-Prüfung: Warn-Karten mit `AppStatus`-Schwere.

**lib/ui.** `AppStatus`, `AppFormField`, `AppStatCards`, `AppConfirmDialog`.

**Vorher→Nachher.**
- Bargeld-Eingabe ohne Validator ([daily_closing_screen.dart:296](lib/screens/daily_closing_screen.dart#L296)) → `autovalidateMode` + Fehlertext.
- Diskrepanz nur farbig ([daily_closing_screen.dart:378](lib/screens/daily_closing_screen.dart#L378)) → `AppStatus` (Icon+Text).
- Anomalie-Schwere nur Farbe ([cashier_anomaly_screen.dart:200](lib/screens/cashier_anomaly_screen.dart#L200)) → `AppStatus`.

**A11y/Formulare/iOS/Android.** Betrag tabular; „Abschließen" mit Bestätigung; iOS-Nummern-Toolbar.

---

### 13. Kiosk / Arbeitsmodus — Board + Kacheln

**Zielbild.** Overflow-sicheres Grid-Board (Dynamic Type bis 200 %), redundanter Kachel-Status, barrierefreies und sicheres PIN-Login mit sichtbarem Auto-Logout.

**IA & Primäraktion.** Board bleibt Dauer-Ansicht; Primär = „Anmelden" (großer Button in `_KioskTopBar`). Kacheln (`_ClockTile`/`_StoreTasksTile`/`_FridgeTile`/`_ExpiryTile`/`_WishesTile`/`_HintsTile`) mit Icon + Titel + `AppStatus`-Badge (Icon+Text) + Inhalt.

**Mobile/Tablet-Layout.** Statt manueller Breitenrechnung ein **responsives `GridView`/`SliverGrid`** (`SliverGridDelegateWithMaxCrossAxisExtent`) → gleiche Kachelhöhe, kein Overflow bei großer Schrift. 1/2/3 Spalten über Breakpoints (< 600 / 600–840 / > 840). Karten mit `IntrinsicHeight`/`Flexible`-sicherem Inhalt.

**PIN-Login.** `AppBottomSheetScaffold` mit Roster-Liste + `_PinPad`: Ziffernanzeige ≥ 28 dp Punkte, NumPad-Tasten ≥ 64 dp mit `Semantics`-Labels („Ziffer 5", „Löschen"), Haptik pro Tastendruck, Fehler mit Icon+Text + Shake (Reduce-Motion → nur Text). **Demo-PIN nur im Nicht-Release/Demo-Modus** einblenden, nicht produktiv.

**Sicheres Abmelden.** `_ActiveEmployeeChip` mit sichtbarem **Rest-Countdown** (Auto-Logout) + „Abmelden"-Bestätigung.

**lib/ui / Tokens.** `AppSectionCard`/`AppCard` (Kacheln), `AppStatus` (Badges), `AppBottomSheetScaffold` (Login), Tokens statt `Colors.*`.

**Vorher→Nachher.**
- Manuelle Spaltenbreite ([kiosk_screen.dart:448](lib/screens/kiosk/kiosk_screen.dart#L448)) → `GridView`/`SliverGrid` mit Max-Extent.
- Status nur `appColors`-Badge ([kiosk_screen.dart:806](lib/screens/kiosk/kiosk_screen.dart#L806)) → `AppStatus` (Icon+Text+`Semantics`).
- 18×18-Punkte + Demo-PIN im Klartext ([kiosk_screen.dart:1224](lib/screens/kiosk/kiosk_screen.dart#L1224)) → größere Anzeige, Haptik, Demo-PIN nur Demo-Modus.
- NumPad ohne Semantics ([kiosk_screen.dart:1295](lib/screens/kiosk/kiosk_screen.dart#L1295)) → `Semantics`-Labels.

**A11y/Touch.** Tasten ≥ 64 dp; Dynamic-Type-sicher; Screenreader-fähig. **Sichere Anmeldung.** PIN maskiert, Haptik, Fehl-Rückmeldung ohne PIN-Leak, Auto-Logout sichtbar. **Offline.** Board voll offline (geteiltes Tablet); Stand-Band. **Motion.** Shake nur bei aktivierter Motion; Uhr ohne Dauer-Animation (Akku). **iOS/Android.** Wake-Lock/Fullscreen-Kiosk plattformgerecht (nur Layout/Optik hier).


## 17. Bereich — Profil, Einstellungen & Verwaltung

Zielbild des gesamten Bereichs: Der `/profil`-Tab wird vom heutigen gemischten "Kachelbrett" zu einem klar zweigeteilten Hub — **"Mein Konto"** (persönlich, für jeden) oben in der Daumenzone, **"Verwaltung"** (Admin) darunter als gruppierte, permissionsgated Liste. Das ganze Modul wird durchgehend auf das V2-Signal-Teal-Design-System (`lib/ui/ui.dart`) gehoben, sodass der heutige Bruch zwischen Legacy (Hub/Settings/Team/Audit/StoreHealth) und V2 (Personal/Finance) verschwindet. Kritische Aktionen wandern aus versteckten `PopupMenuButton`/AppBar-Icons in sichtbare Bottom-Bars/FABs, jede zerstörerische Aktion bekommt `AppConfirmDialog`, jede Liste bekommt Suche/Filter, und alle Fehlermeldungen werden handlungsleitend statt roher `$error`-Text. Barrierefreiheit (Semantics, ≥48dp, Dynamic Type, Kontrast über `appColors`) und ein einheitliches Loading/Offline/Empty-Muster werden bereichsweit eingezogen.

Leitplanke: **ausschließlich Optik/Layout/Struktur/UX**. Keine Provider-/Service-/Model-/Compliance-/Serialisierungs-Änderung. Alle neuen Widgets sind reine Präsentationsschicht über bestehenden Providern.

### Bereichsweite Muster (gelten für alle Unterbereiche)

| Muster | Vorher | Nachher |
|---|---|---|
| Design-System | Legacy `Card`/`SectionCard`/`InfoChip`/`_QuickActionCard`/`DropdownButtonFormField` gemischt mit V2 | Durchgehend `AppCard`/`AppSectionCard`/`AppStatCards`/`AppSegmented`/`AppFormField`/`AppStatus`/`AppBottomSheetScaffold` aus `lib/ui/ui.dart` |
| Kritische Aktion | `PopupMenuButton`/AppBar-Icon | Sichtbare untere Aktionsleiste (`AppBottomBar`, neu in `lib/ui/`) oder FAB; ≥48dp |
| Zerstörerisch | Sofort ausgeführt | `AppConfirmDialog` mit klarer Konsequenz-Beschreibung |
| Fehler | `SnackBar('… $error')` | `_friendlyError(error)` → Klartext + Handlungshinweis + optional "Erneut versuchen" |
| Liste | Keine Suche | `AppSearchField` (neu) + Filter-Chips, entprellt, `Clear`-Button |
| Zustände | Nur `EmptyState` (nicht von lädt/offline unterscheidbar) | 4-Zustands-Muster: **Laden** (Skeleton), **Offline** (Banner), **Leer** (`EmptyState` + CTA), **Fehler** (Retry) |
| Datum/Zeitraum | Nur Prev/Next-Pfeile | Prev/Next + tappbares Label → `showMonthPicker`/`showYearPicker`-Sheet |
| Tabs | Team mit Count-Badges, Personal/Finance ohne | Einheitliche `AppTabBar` mit Count-Badges überall; Overflow-Fade-Gradient statt hartem Cut |
| Barrierefreiheit | 0 Semantics | Jede Karte = 1 Semantics-Knoten mit Label; Icons `excludeSemantics`; Beträge/Deltas mit Text + Icon (nicht nur Farbe) |

Neue geteilte lib/ui-Komponenten (statt file-privater Klone `_TeamMetaChip`/`_MiniChip`/`_MetaChip`/`_InfoChip`): `AppMetaChip`, `AppSearchField`, `AppBottomBar`, `AppPeriodBar`, `AppListStates` (Loading/Offline/Empty/Error), `AppTabBar`. Diese ersetzen die dutzenden Duplikate über die God-Files hinweg.

---

### 1. Profil-Hub (`_ProfileHubTab`)

**Datei:** [home_screen.dart:2911](lib/screens/home_screen.dart#L2911)

**Zielbild & Informationsarchitektur:** Zwei klar getrennte Zonen statt eines gemischten Kachelbretts.
1. **Profil-Kopf** — `AppHeroCard` mit Avatar, Name, Rollen-Badge (`AppStatus`), 3 Kern-Chips (Stammstandort/Soll-h/Urlaub) als `AppMetaChip`.
2. **Mein Konto** (jeder): `AppSectionCard` "Mein Konto" → `AppKontoTile`-Reihe: Einstellungen · Push-Benachrichtigungen · Monatsbericht · Statistiken (letzte zwei nur bei `canViewReports`).
3. **Verwaltung** (nur wenn ein Admin-Recht vorhanden): `AppSectionCard` "Verwaltung" → gruppierte `AppKontoTile`: Teamverwaltung · Personal · Buchhaltung · Änderungsprotokoll · Warenwirtschaft · Kundenbestellungen · Laden-Benchmark.
4. **Sicherheit/Sitzung** unten, in der Daumenzone.

**Primäraktion:** Kein einzelner Primär-CTA — der Hub ist ein Verteiler; Primäraktion je Zeile ist der Tap in den Bereich.

**Mobile-Layout:** Einspaltige `ListView` mit `AppKontoTile`-Zeilen (volle Breite, ≥56dp Zeilenhöhe, Leading-Icon + Titel + Untertitel + Chevron) statt quadratischer Kacheln — bessere Lesbarkeit/Touch auf schmalen Screens. **Abmelden** wandert in eine untere, gepinnte `AppBottomBar` (Daumenzone) statt links am Ende der langen ListView.

**Tablet/Desktop (≥600/≥840):** `AdaptiveCardGrid` (2 Spalten ab 600, 3 ab 840) für die Verwaltungs-Gruppe als `AppQuickAction`-Kacheln; "Mein Konto" bleibt Liste links, Verwaltung als Grid rechts (leichtes Master-Detail-Gefühl ohne echtes Splitpane).

**Vorher→Nachher:**
- [home_screen.dart:2967](lib/screens/home_screen.dart#L2967) `Card` (Profil) → `AppHeroCard`.
- [home_screen.dart:3004](lib/screens/home_screen.dart#L3004) `InfoChip` → `AppMetaChip`.
- [home_screen.dart:3047](lib/screens/home_screen.dart#L3047) ungruppiertes `AdaptiveCardGrid` (mischt persönlich/Admin) → zwei `AppSectionCard`-Gruppen "Mein Konto" / "Verwaltung".
- [home_screen.dart:3051](lib/screens/home_screen.dart#L3051) `_QuickActionCard` → `AppKontoTile` (mobil) / `AppQuickAction` (Tablet).
- [home_screen.dart:3107](lib/screens/home_screen.dart#L3107) `SectionCard` "Sicherheit" → `AppSectionCard`; [home_screen.dart:3120](lib/screens/home_screen.dart#L3120) linksbündiger `FilledButton` → `AppBottomBar` unten.

**Touch & Barrierefreiheit:** Zeilen ≥56dp. Avatar/Chips `excludeSemantics`, Zeile = `Semantics(button: true, label: '<Titel>, <Untertitel>')`. Rolle als Text-Badge, nicht nur Farbe.

**Offline:** Hub ist rein lokaler State (Profil/Settings) → voll offline nutzbar. Verwaltungsbereiche, die Netz brauchen, zeigen erst im Zielscreen das Offline-Banner (nicht im Hub deaktivieren, sonst Sackgasse).

**Motion:** `AppMotion.short` Fade/Slide beim Öffnen der Sektionen; Reduce-Motion respektieren (`MediaQuery.disableAnimations`).

---

### 2. Einstellungen (`SettingsScreen`)

**Datei:** [settings_screen.dart:88](lib/screens/settings_screen.dart#L88)

**Kernproblem (high):** Gespaltenes Speichermodell — Theme/Storage/Push wirken sofort, Formfelder erst bei "Speichern"; Textänderungen gehen beim Zurück ohne Rückfrage verloren ([settings_screen.dart:320](lib/screens/settings_screen.dart#L320) vs. sofort-Setter). **Lösung:**
- Formularfelder werden in eine **eigene Sektion "Meine Vorgaben"** mit **stickyer unterer Speicherleiste** (`AppBottomBar`, erscheint nur bei "dirty" State) gebündelt. `PopScope` fängt Zurück bei ungespeicherten Änderungen ab → `AppConfirmDialog` "Änderungen verwerfen?".
- Sofort-wirkende Schalter (Theme/Storage/Push) werden **optisch als "wirkt sofort"** markiert (kein Speichern-Button in Reichweite) und klar von der Formular-Sektion getrennt.

**Zielbild & Informationsarchitektur:** Die >10-Sektionen-Column wird zu klar benannten, kollabierbaren `AppSectionCard`-Blöcken in fixer Reihenfolge:
1. **Konto** (`_AccountInfoCard` → `AppCard`)
2. **Meine Vorgaben** (Name, Soll-Stunden, Lohn, Urlaub, Auto-Pause) — die einzige Sektion mit Speicherleiste
3. **Darstellung** (Theme via `AppSegmented`, Dark/Light/System)
4. **Benachrichtigungen** (Push → NotificationSettings)
5. **Arbeitsmodus / Kiosk-PIN**
6. **Daten & Speicher** (Speichermodus, mit Warndialog)
7. **Admin: Automatische Schichtverteilung** (visuell abgesetzt: `AppStatus`-Banner "Org-weit — gilt für alle" statt inline zwischen persönlichen Feldern, [settings_screen.dart:143](lib/screens/settings_screen.dart#L143))

**Primäraktion:** "Speichern" in der stickyen Leiste (nur bei Änderungen sichtbar).

**Mobile-Layout:** Einspaltig, Speicherleiste unten in der Daumenzone. Theme-Selektor als `AppSegmented` (3 Segmente) statt 3 handgebaute `GestureDetector` ([settings_screen.dart:727](lib/screens/settings_screen.dart#L727)) → Ink-Feedback, ≥48dp, Semantics gratis.

**Tablet/Desktop:** Ab 840 zweispaltig (links Formular-Sektionen, rechts Darstellung/Daten/Admin) mit `maxWidth 980` beibehalten.

**Formulare (Fehlervermeidung):** `AppFormField` mit Pflicht-Markierung, `keyboardType`-korrekt (Dezimal für Stunden/Lohn), inline-Validierung ("Bitte Zahl zwischen 0 und 24"), `autovalidateMode: onUserInteraction`. **Speichermodus-Wechsel** ([settings_screen.dart:665](lib/screens/settings_screen.dart#L665)) bekommt vorgeschalteten `AppConfirmDialog`: "Speicherort wechseln? Alle Daten werden neu synchronisiert, das kann bei schwachem Netz dauern." — erst bei Bestätigung `_changeStorageLocation`.

**Fehlermeldungen:** [settings_screen.dart:401](lib/screens/settings_screen.dart#L401)/[:493] rohes `$error` → `_friendlyError`: "Speichern nicht möglich. Bitte Internetverbindung prüfen und erneut versuchen." + Retry.

**Vorher→Nachher:**
- [settings_screen.dart:149](lib/screens/settings_screen.dart#L149) `Card`+`TextFormField` → `AppFormField` in `AppSectionCard`.
- [settings_screen.dart:354](lib/screens/settings_screen.dart#L354) manuelles `_sectionTitle` → `AppSectionCard`-Header.
- [settings_screen.dart:722](lib/screens/settings_screen.dart#L722) `GestureDetector`-Theme-Kacheln (keine Semantics) → `AppSegmented` mit Labels.

**Touch & Barrierefreiheit:** Alle Schalter ≥48dp; Theme-Segmente mit `Semantics(label:'Design: Hell/Dunkel/System, ausgewählt')`. Dynamic Type: keine festen Höhen an Textzeilen.

**Offline:** Theme/Kiosk-PIN-Anzeige/Formular-Eingabe voll offline; Speichern im Offline-Fall lokal gepuffert (bestehendes Storage-Verhalten) → Banner "Offline — wird bei Verbindung übertragen".

**iOS/Android:** Cupertino-Rückgeste durch `PopScope`-Guard nicht brechen (Guard nur bei dirty). Auf iOS `showCupertinoModalPopup`-Feeling für Sheets via `AppBottomSheetScaffold` beibehalten.

---

### 3. Teamverwaltung (`TeamManagementScreen`)

**Datei:** [team_management_screen.dart:75](lib/screens/team_management_screen.dart#L75) (God-File, 4648 Z)

**Zielbild & Informationsarchitektur:** 4 Tabs bleiben (Mitarbeiter · Standorte · Teams & Quali · Regelwerk), aber jeder Tab bekommt **einheitlich** eine Kopfleiste `AppSearchField` + Filter-Chips ([team_management_screen.dart:929](lib/screens/team_management_screen.dart#L929)/[:1039]/[:1156] heute ohne Suche). Karten (`_ManagementCardShell`) werden `AppCard`; die versteckten `PopupMenuButton`-Aktionen ([team_management_screen.dart:1860](lib/screens/team_management_screen.dart#L1860)) werden zu sichtbaren `AppCard`-Trailing-Buttons bzw. bei Auswahl in eine untere `AppBottomBar` (Master-Detail).

**Primäraktion je Tab:** FAB "Einladen" / "Standort" / "Team" / "Regel" (kontextabhängig, unten rechts, Daumenzone).

**Mobile-Layout:** Einspaltige Karten. Meta-Chips auf **max. 3 sichtbare** reduziert ([team_management_screen.dart:1824](lib/screens/team_management_screen.dart#L1824), heute bis 6) + "+n" → Detail-Sheet. Kartenaktion primär (Bearbeiten) als sichtbarer Button; Deaktivieren im Overflow, aber mit `AppConfirmDialog` ([team_management_screen.dart:916](lib/screens/team_management_screen.dart#L916) `setMemberActive` heute ohne Rückfrage).

**Tablet/Desktop (≥840):** Echtes **Master-Detail** — links `_ResponsiveTeamGrid`/Liste, rechts Detail-Panel (statt Vollbild-Sheet). Editor-Sheets bleiben auf Mobil.

**Tabs:** Scrollbare `TabBar` mit langem Label ("Teams & Qualifikationen") ([team_management_screen.dart:127](lib/screens/team_management_screen.dart#L127)) → `AppTabBar` mit kürzeren Labels + Count-Badges + Rand-Fade als Overflow-Hinweis.

**Vorher→Nachher:**
- [team_management_screen.dart:830](lib/screens/team_management_screen.dart#L830) Suche nur im Mitarbeiter-Tab → `AppSearchField` in allen 4 Tabs.
- [team_management_screen.dart:1860](lib/screens/team_management_screen.dart#L1860) `PopupMenuButton` → sichtbarer Trailing-Button + Overflow.
- [team_management_screen.dart:901](lib/screens/team_management_screen.dart#L901) `_TeamEmptyState` (nicht von lädt/offline unterscheidbar) → `AppListStates` (Loading-Skeleton/Offline/Empty/Error).

**Touch & Barrierefreiheit:** Karte = `Semantics`-Knoten "<Name>, <Rolle>, <Standort>". Chips `excludeSemantics`. Aktions-Buttons ≥48dp. Deaktiviert-Status als Text-Badge + Icon, nicht nur ausgegraut.

**Offline:** Stammdaten kommen aus Firestore-Offline-Cache (hybrid) → Liste offline lesbar; Schreibaktionen zeigen Offline-Banner. Leer-vs-Offline klar getrennt via `AppListStates`.

**iOS/Android:** Swipe-to-Edit (iOS-Listen-Gefühl) optional als `Dismissible`-Leading; Android Long-Press-Kontextmenü konsistent mit Overflow.

---

### 4. Personal / HR (`PersonalScreen`)

**Datei:** [personal_screen.dart:80](lib/screens/personal_screen.dart#L80) (größtes God-File, 5649 Z) — bereits V2, daher Feinschliff statt Umbau.

**Zielbild:** Suche/Filter in Aufträge & Lohn ([personal_screen.dart:672](lib/screens/personal_screen.dart#L672)/[:912], heute ohne), Count-Badges an die 5 Tabs ([personal_screen.dart:119](lib/screens/personal_screen.dart#L119), für Muster-Konsistenz mit Team/Finance), Monats-Picker statt nur Pfeile ([personal_screen.dart:286](lib/screens/personal_screen.dart#L286)).

**Informationsarchitektur:** Tabs Übersicht · Aufträge · Lohn · Finanzen · Statistik bleiben; `AppPeriodBar` (tappbares Monatslabel → Month-Picker-Sheet) ersetzt die reine Prev/Next-`_MonthBar`.

**Primäraktion:** Kontextabhängiger FAB (Auftrag anlegen / Lohnlauf starten). Kassierer-Prüfung wandert vom versteckten AppBar-Icon ([personal_screen.dart:99](lib/screens/personal_screen.dart#L99)) in die Übersicht als sichtbare `AppQuickAction`-Kachel "Kassierer-Prüfung".

**Mobile-Layout:** `AppPeriodBar` sticky unter der TabBar (Daumenreichweite mittig-oben ok, Picker öffnet als Bottom-Sheet in Daumenzone). Lohn-Statuswechsel ([personal_screen.dart:1224](lib/screens/personal_screen.dart#L1224)) bleibt Menü, aber Fehler → `_friendlyError` statt `_showError(context, error)` ([personal_screen.dart:1230](lib/screens/personal_screen.dart#L1230)).

**Tablet/Desktop:** Statistik/Finanzen zweispaltig; Charts größer.

**Performance:** Statistik-/Finanz-Tab rechnen im build ([personal_screen.dart:1534](lib/screens/personal_screen.dart#L1534)/[:1386]) → Skeleton-Platzhalter während `entriesLoading` ([personal_screen.dart:138](lib/screens/personal_screen.dart#L138)) statt Sprung; schwere Aggregation nur bei sichtbarem Tab (`AutomaticKeepAlive` + lazy build).

**Barrierefreiheit:** Chart-Balken bekommen `Semantics(label:'<Monat>: <Betrag> €')` ([personal_screen.dart:1674](lib/screens/personal_screen.dart#L1674)/[:1799]). Status-Badges Text+Icon.

**Offline:** Zeit-/Lohnaggregate aus lokalem Cache; Offline-Banner wenn Netz für Lohnlauf/Export nötig.

**iOS/Android:** Month-Picker als plattformgerechtes Sheet; native Zurückgeste erhalten.

---

### 5. Buchhaltung / Finanzen (`FinanceScreen`)

**Datei:** [finance_screen.dart:104](lib/screens/finance_screen.dart#L104) — bereits V2.

**Zielbild:** **Buchungsjournal** ([finance_screen.dart:514](lib/screens/finance_screen.dart#L514), heute ohne Filter) bekommt `AppSearchField` + Filter-Chips (Kostenstelle/-art/Zeitraum) — bei vielen Buchungen sonst unbrauchbar. Export/DATEV/Tagesabschluss aus dem versteckten AppBar-Icon+PopupMenu ([finance_screen.dart:138](lib/screens/finance_screen.dart#L138)) in eine sichtbare untere **`AppBottomBar`** "Exportieren" (öffnet Sheet mit 4 Optionen) + FAB "Buchen".

**Informationsarchitektur:** Tabs Übersicht · Journal · Stammdaten · Budgets bleiben (`AppTabBar` mit Badges + Fade-Overflow, [finance_screen.dart:172](lib/screens/finance_screen.dart#L172)). Jahres-Navigation `AppPeriodBar` mit tappbarem Jahr-Picker ([finance_screen.dart:201](lib/screens/finance_screen.dart#L201)).

**Primäraktion:** FAB "Buchen" (gated auf vorhandene Kostenstellen/-arten, sonst deaktiviert mit erklärendem Tooltip/Hint statt still weg).

**Mobile-Layout:** Journal als `AppCard`-Liste mit Filterleiste oben; Export-Bar unten. **Offline-Hinweis** für Export/DATEV ([finance_screen.dart:61](lib/screens/finance_screen.dart#L61)): Export-Button zeigt bei Offline `AppStatus`-Info "Für Export ist eine Verbindung nötig" statt erst Snackbar bei Fehler.

**Tablet/Desktop:** Journal Master-Detail (Liste + Buchungsdetail rechts).

**Barrierefreiheit/Kontrast:** Beträge/Soll-Haben mit Text (+/−) nicht nur Farbe; `appColors.success/warning`.

**iOS/Android:** Export-Sheet plattformgerecht; DATEV/CSV-Download über bestehenden Download-Service (kein UI-Change am Service).

---

### 6. Änderungsprotokoll (`AuditLogScreen`)

**Datei:** [audit_log_screen.dart:38](lib/screens/audit_log_screen.dart#L38) — vorbildlich bei Suche/Filter, nur V2-Angleichung.

**Zielbild:** `_FilterBar` auf `AppSearchField` + zwei `AppSegmented`/Dropdown-im-V2-Stil ([audit_log_screen.dart:255](lib/screens/audit_log_screen.dart#L255) `DropdownButtonFormField` → V2-Filter-Chips/`AppFormField`-Dropdown; [:232] `TextField`+`OutlineInputBorder` → `AppSearchField`). ListTiles → `AppCard`-Zeilen mit Icon-Badge (Aktion), Titel, strukturierter Meta-Zeile (Akteur/Zeit als `AppMetaChip` statt `\n`-Konkatenation, [audit_log_screen.dart:132](lib/screens/audit_log_screen.dart#L132)).

**Primäraktion:** CSV-Export bleibt AppBar-Action (sekundär, korrekt) — hier ist Lesen/Filtern die Primäraufgabe.

**Mobile-Layout:** Filterleiste sticky oben; "Mehr laden" ([audit_log_screen.dart:116](lib/screens/audit_log_screen.dart#L116)) → **Infinite-Scroll** (Auto-Nachladen am Listenende) statt extra Tap; Fallback-Button bleibt für Fehlerfall.

**Barrierefreiheit:** Jede Zeile `Semantics(label:'<Aktion> <Objekttyp>, durch <Akteur>, am <Datum>')` statt `\n`-Join ([audit_log_screen.dart:142](lib/screens/audit_log_screen.dart#L142) `isThreeLine`).

**Offline:** Audit ist admin-only Cloud-Read → Offline-Banner "Protokoll offline nicht verfügbar"; keine Fehlerkaskade.

---

### 7. Laden-Benchmark / Store-Health (`StoreHealthScreen`)

**Datei:** [store_health_screen.dart:55](lib/screens/store_health_screen.dart#L55)

**Zielbild:** `SectionCard` → `AppStatCards`/`AppSectionCard` ([store_health_screen.dart:172](lib/screens/store_health_screen.dart#L172)). Delta-Signal nicht mehr nur Farbe+Pfeil ([store_health_screen.dart:153](lib/screens/store_health_screen.dart#L153)) → zusätzlich **Text-Label** ("−18 %, unter Schnitt") + `AppStatus`-Badge (`appColors.warning/success`) → farbenblind-sicher.

**Mobile-Layout:** `RefreshIndicator`-Liste bleibt (natives Pull-to-Refresh, gut). Offline ([store_health_screen.dart:46](lib/screens/store_health_screen.dart#L46)) → `AppListStates.offline` mit "Zuletzt aktualisiert …"-Zeile statt generischer Fehler.

**Barrierefreiheit:** Delta-Karte `Semantics(label:'<Laden>: heute <n> Belege, <Delta> gegenüber Wochentag-Schnitt')`.

---

### 8. Force-Update-Gate (`ForceUpdateScreen`)

**Datei:** [force_update_screen.dart:20](lib/screens/force_update_screen.dart#L20)

**Kernproblem (medium):** Sackgasse — sagt "Update nötig", aber nicht WIE ([force_update_screen.dart:6](lib/screens/force_update_screen.dart#L6)). **Lösung:** `Card` → `AppHeroCard` mit Icon, klarer Erklärung, Build-Info und **Store-Button** ("Im App Store / Play Store öffnen" — plattformabhängig via `kIsWeb`/`Platform`, öffnet Store-URL; im Web: "Seite neu laden"). Rein Präsentation, keine Logikänderung an der Sperre selbst. Optional sekundär "Erneut prüfen".

**Barrierefreiheit:** Button ≥48dp, `Semantics(button:true)`. Vertrauenswürdiges, ruhiges Design (kein Alarm-Rot, `appColors.info`).

---

### Sichere Anmeldung / Sitzung (Anforderung 28)

Der Platzhalter "Biometrie kann später ergänzt werden" ([home_screen.dart:3116](lib/screens/home_screen.dart#L3116)) wird zu einer ehrlichen, umgesetzten Sitzungs-Sektion in "Sicherheit": Anzeige des Anmeldestatus (`AppStatus`), Geräte-/Session-Info und ein **UI-Toggle "App mit Face ID / Fingerabdruck sichern"** als Präsentations-Vorbereitung (der reine Schalter + Erklärtext; die eigentliche `local_auth`-Verdrahtung ist außerhalb dieser reinen UI-Aufgabe und wird als klar markierter, deaktivierter Zustand "demnächst verfügbar" gezeigt, statt als verstreuter Kommentar). So ist die Anforderung im UI sichtbar adressiert, ohne Provider-/Auth-Logik zu ändern.

### Datenschutz (Anforderung 29)

Kein Bereich fordert hier Kamera/Standort/Kontakte an — das bleibt so. In "Daten & Speicher" wird ein kurzer Klartext-Hinweis ergänzt, welche Daten wo liegen (lokal/Cloud), plus Link zu `/datenschutz`. Reine Text-/Layout-Ergänzung.



# Teil D — Fahrplan, Risiken & Anhänge


## 18. Konsolidierter Rollout-Fahrplan

Strangler-artig, jeder Bereich hinter `redesign_v2`, jeder Schritt einzeln mergebar. **Reihenfolge nach Nutzen/Risiko** (nach Phase 0):

```
Phase 0  Fundament (F1–F6 + Querschnitt-Deltas DS/N4/Plattform)
   ↓
Heute  →  Anfragen  →  Zeit  →  Kontakte  →  Plan  →  Laden  →  Profil/Verwaltung
```

**Warum diese Reihenfolge:** *Heute* ist der tägliche Ersteindruck und relativ klein (schneller Sieg, etabliert das Muster). *Anfragen* liefert die zentrale Inbox + Push-Owner. *Zeit* enthält die häufigste mobile Aktion (Stempeln). *Kontakte* ist der sauberste Master-Detail-Prototyp. *Plan* und *Laden* sind die größten God-Files (höchstes Risiko, brauchen das Test-Gate zuerst). *Profil/Verwaltung* ist admin-lastig und am wenigsten mobil-kritisch.

**Definition of Done je Bereich:** `flutter analyze` sauber + `flutter test` grün + Golden/Widget-Tests via `pumpApp` + visueller Smoke im `APP_DISABLE_AUTH=true`-Modus in **Light und Dark** + Textscale-Abnahme + Daumenzonen-/Touch-Target-Check + Offline-Checkliste des Bereichs.

### Meilensteine je Bereich & Querschnitt

**Phase 0 — Fundament & Querschnitt-Deltas** (siehe Kapitel 4–10):

**Querschnitt: Design-System-Fundament**

| ID | Meilenstein | Umfang | Aufwand |
|---|---|---|:--:|
| DS1 | Token-Luecken schliessen: Spacing s6/s12 + Tabular-Figures-Konstante | In theme_extensions.dart AppSpacing um s6=6 und s12=12 erweitern (Felder + copyWith + lerp + Defaults, additiv). kTabularFigures-Konstante nach lib/ui/ heben und in app_stat_cards.dart referenzieren. Zusammengesetzte Ausdruecke (xs+xxs, sm+xs) in lib/ui/* auf neue Tokens migrieren. Reiner Refactor, 0 visuelle Regression. | S |
| DS2 | Kontrast- & Paritaets-Tests als Definition-of-Done-Gate | Test: appColors non-null in lightV2/darkV2; Kontrast-Assertion ueber die 6 Rollen-Paare je Brightness gegen WCAG-AA-Schwellen; de_DE-Test fuer neue DateFormat-Nutzung. Sichert Anf. 4/19/20/26 messbar ab. | M |
| DS3 | Fehlende kanonische Komponenten ergaenzen (AppErrorState, AppSearchField) | AppErrorState (Fehlermeldung + Retry + verstaendlicher dt. Text, AppStatusTone.error) und AppSearchField (Prefix-Lupe/Clear, tokenisiert) in lib/ui/ bauen + ins Barrel. Adressiert Anf. 17/18 (Fehler) und 24 (Suche/Filter). Nur Tokens/Rollen, kein Hex/dp. | M |
| DS4 | Komponenten-Semantik-Leitplanken dokumentieren (Button-Hierarchie, Status-Toene, Offline/Sync-Banner) | Verbindliche Zuordnung Filled=Primaer(max.1)/Outlined=Sekundaer/Text=tertiaer, Cancel=error-Foreground; AppStatusBanner-Ton-Konvention offline=warning/sync=info + Aktion. Als Doc-Kommentare in lib/ui/ + Referenz in CLAUDE.md-Konventionen. Sichert Anf. 22/12/13. | S |
| DS5 | Dual-Theme-Golden-Baseline der lib/ui-Komponenten | Golden-Tests je Komponente (AppCard/StatCards/StatusBadge/Segmented/BottomSheetScaffold/FormField) in lightV2 + darkV2, je 1x Phone-Breite und 1x >=600dp Rail-Breite. Friert die Fundament-Optik ein, bevor Screen-Migrationen starten (visuelle Regression sichtbar). | L |

**Querschnitt: Navigation & Informationsarchitektur**

| ID | Meilenstein | Umfang | Aufwand |
|---|---|---|:--:|
| NAV-0 | Navigations-Quick-Wins & Korrekturen | Orphan-Route /kundenwuensche verlinken (Laden-Hub-Kachel, canViewInventory); Scanner-Permission überall auf canUseScanner standardisieren (home_screen.dart:495, app_nav_menu.dart:170 → route_permissions); Zeit-Admin (Lohnlauf/Mitarbeiterabschluss) in Drawer-Gruppe Verwaltung aufnehmen. Unabhängig, sofort shippbar. | S |
| NAV-1 | Profil-Tab V1/V2-Konsistenz | _isTabVisible-Sonderfall (tab==profile && useV2→false) entfernen; Profil-Tab in beiden Flag-Zuständen zeigen; Slide-in-Menü als Zusatzzugang beibehalten. Beide Flag-Pfade manuell durchklicken. | S |
| NAV-2 | Eine kanonische AppSection-Descriptor-Liste | AppSection-Klasse (label/subtitle/icon/route/domain/canAccess=isLocationAllowed) in lib/routing bzw. lib/ui; Laden-Hub, Profil-Hub und AppNavMenu rendern daraus. Ersetzt die 3 divergierenden Kachel-/Item-Blöcke. Nach home-Split (AP2.4) für saubere Dateien. | M |
| NAV-3 | Hub-Domänentrennung in Gruppen | Laden-Hub = shop+management in Gruppen (Lagerwirtschaft&Vertrieb / Verwaltung) statt flachem Grid; Profil-Hub = nur Persönliches + Link zum Laden-Bereich; Rendering über bestehendes _MenuGroup. Genau ein Heimat-Hub je Destination (aus domain). | M |
| NAV-4 | Breadcrumb-/Orientierungs-Konsistenz | ShellBreadcrumb/BreadcrumbAppBar für ALLE gepushten Section-Routen sicherstellen (parentLabel durchgängig); iOS-Swipe-back im PageTransitionsTheme prüfen; Zurück-Chevron/Touch-Targets ≥44dp in Breadcrumb-Leisten. | S |
| NAV-5 | Globale Suche (SearchAnchor) | AppGlobalSearchBar per Such-Icon in V2-Top-Bar/Rail-Kopf; gruppierte In-Memory-Treffer (Kontakte/Artikel/Mitarbeiter/Bereiche) aus vorhandenen Providern + AppSection-Sprünge; permission-gefiltert, 250ms Debounce, deutsche AppListSectionHeader-Gruppen. Nur Lesen, keine neue Persistenz. | L |
| NAV-6 | Vereinheitlichte screen-lokale Suche/Filter | Konsistente AppSearchField + AppChoiceChipBar/AppSiteFilterBar in Kontakte/Warenwirtschaft/Team; ersetzt divergierende Filter-Klone (customer_order vs inventory Label-Drift). Nutzt bestehende Screen-Filterlogik. | M |
| NAV-7 | Nav-Chrome-A11y & Icon-Konsistenz | Badge-Zähler in Semantics-Label (Nav-Rail + BottomNav); eine outline/filled-Icon-Paarung je Modul zentral in AppSection/_destinationMeta; alle Nav-Touch-Targets ≥48dp; Dark/Light über colorScheme-Rollen prüfen. | S |

**Querschnitt: Responsive & Adaptive Layout**

| ID | Meilenstein | Umfang | Aufwand |
|---|---|---|:--:|
| R1 | Layout-Bausteine + Breakpoint-Leiter | WindowClass-Enum + windowClassOf in responsive_layout.dart; AppContentScaffold (SafeArea+ConstrainedBox+screenPadding, Cap-Presets 640/1100/1240); Barrel-Export in lib/ui/ui.dart. Keine Screen-Aenderung. | M |
| R2 | Content-Caps ausrollen + personal_screen capsen | personal_screen.dart auf AppContentScaffold(1100); contacts/inventory/sortiment/team auf AppContentScaffold konsolidieren (dedupliziert ConstrainedBox-Kopien). Anti-Overflow-Muster (Expanded/Flexible/ellipsis/Wrap) verbindlich pruefen. | M |
| R3 | AdaptiveMasterDetail fuer Listen-Bereiche | AdaptiveMasterDetail-Widget; Aktivierung auf contacts + inventory ab expanded (Liste links, Detail-Panel rechts inline statt Sheet, AppEmptyState bei nichts gewaehlt). Handy-Verhalten unveraendert. | L |
| R4 | Plattformadaptive Widget-Fassade | AppAdaptive (pickDate/pickTime/dialog); flaechendeckend .adaptive fuer Switch/CircularProgressIndicator/RefreshIndicator; ScrollBehavior mit plattformabhaengiger Physik; pageTransitionsTheme (iOS Cupertino / Android Predictive-Back). | L |
| R5 | Dashboards + Kiosk-Board vereinheitlichen | Home-Tabs/Insights/Statistik/Zeit-Hub auf AdaptiveCardGrid (1/2/3/4 Spalten, Cap 1240); kiosk_screen.dart-Grid auf die neue Leiter (720/1100) + Touch-Mindesthoehe >=88dp + viewPadding. | M |
| R6 | Safe-Area/Insets + Breiten-Regressionstests | SafeArea/viewInsets/paddingOf-Audit ueber alle Screen-Roots; daumennahe FAB-Platzierung; Widget-/Golden-Tests bei 360/834/1440dp ueber router_harness. | M |

**Querschnitt: Barrierefreiheit**

| ID | Meilenstein | Umfang | Aufwand |
|---|---|---|:--:|
| A11Y-1 | Kontrast- & Farb-Audit (Light+Dark) | Alle Text-auf-Fläche-Paare in lib/ui/ + Hauptscreens gegen AA prüfen; onSurfaceVariant-0.45-Disabled/Placeholder (app_theme.dart:237,683) und 12%/30%-Container-Flächen (app_status/app_stat_cards/app_quick_action) verifizieren; Status-nur-per-Farbe -> Icon+Label doppeln. | M |
| A11Y-2 | Named-Color-Cleanup nach Tokens | 220 Colors.*-Treffer sichten; semantische Farben auf appColors/ColorScheme umstellen (scanner_screen, shift_planner_screen, home_screen_tabs, shift_editor_sheet, stempel_screen, action_fab); Neutral-Ausnahmen dokumentieren. | L |
| A11Y-3 | Semantics für V2-Kernkomponenten | AppQuickAction/AppKontoTile/AppStatusBadge/AppSegmented/AppFormField/AppSectionCard/AppBottomSheetScaffold/AppConfirmDialog mit button/header/selected/label/liveRegion + ExcludeSemantics für Dekor ausstatten (Single-Point-of-Fix). | M |
| A11Y-4 | Screenreader-Coverage Hauptscreens + Badges | 46 rohe InkWell/GestureDetector labeln bzw. auf echte Buttons heben; Notification-/Inbox-Badges + AbcBadge sprechend machen inkl. 9+/99+-Overflow; Icon-only ohne Tooltip nachrüsten. | L |
| A11Y-5 | Dynamic Type ohne Overflow | Fixe Text-Höhen (dashboard_action_items_card:188, Stat-Cards) auf mitwachsend umbauen; maxLines+ellipsis; Golden-Tests der 8 lib/ui/-Komponenten bei Skalierung 1.0/1.3/1.5; Deckel 1.5 evaluieren. | M |
| A11Y-6 | Touch-Targets >= 48 dp | Alle Tap-Handler auf effektive Trefferfläche >= 48 dp bringen (u.a. dashboard_action_items_card:188=32, Scanner-Sheet-Tiles); MaterialTapTargetSize.padded sicherstellen; Mindestabstand 8 dp in dichten Listen. | S |
| A11Y-7 | Reduce-Motion & Fokus-Reihenfolge | Alle App-Animationen auf context.motionDuration(...); Shimmer/Skeleton bei Reduce-Motion statisch; FocusTraversalGroup/OrderedTraversalPolicy + sichtbarer Fokus-Ring für Web/Desktop; Sheet-Fokus-Rückgabe. | M |
| A11Y-8 | A11y-Prüf-Checkliste als DoD verankern | Checkliste (Kontrast/Semantics/Touch/DynamicType/ReduceMotion/Fokus) in Review-Workflow + Golden-/Widget-Test-Suite integrieren; DevTools-Semantics-Stichprobe je geändertem Screen. | S |

**Querschnitt: Sichere Anmeldung, Biometrie & Datenschutz**

| ID | Meilenstein | Umfang | Aufwand |
|---|---|---|:--:|
| S1 | Login-V2-Verfeinerung: Angemeldet-bleiben, Passwort vergessen, Vertrauens-Pill+Icon, Datenschutz-Footer | auth_screen_v2.dart _AuthCardV2/_MobileAuthBody + _EmailLoginFormV2; reine UI, keine Provider-Signaturaenderung | M |
| S2 | Passwort-Reset-Sheet (Enumeration-sicher) + einheitliches deutsches Fehler-Mapping als AppStatusBanner | Neues Reset-BottomSheet + Fehlertext-UX; AuthProvider ggf. um sendPasswordResetEmail-Aufruf ergaenzen (Logik-Anbindung minimal) | M |
| S3 | Gate-Screens vereinheitlichen (FirebaseSetup/AccessBlocked/ForceUpdate) auf gemeinsames V2-Zustands-Layout inkl. plattformgerechtem Store-CTA | auth_screen_v2.dart Gate-Screens + force_update_screen.dart auf AppCard/AppStatusBanner/appColors heben | M |
| S4 | JIT-Kamera-Permission-Priming-Sheet vor Scanner + Info.plist/Manifest-Begruendungstexte | scanner_screen.dart Priming-Sheet vor Kamerastart, permission_handler einfuehren, openAppSettings-Fallback | M |
| S5 | Biometrie-Gate (local_auth): Opt-in-Sheet nach erstem Login, Start-Lock-Overlay, plattform-/verfuegbarkeits-Gating | local_auth einfuehren, Opt-in-Sheet, /start-Lock-Overlay (client-only, kein Redirect-Umbau); Web/Demo ausgeblendet | L |
| S6 | 2FA-Ausblick als Screen-Skizze + Enrollment-UX dokumentieren (Firebase MFA/TOTP), Umsetzung erst bei Blaze-Scharfschaltung | Reine Konzept-/Plan-Doku, kein Code | S |

**Querschnitt: Offline, Performance & Push**

| ID | Meilenstein | Umfang | Aufwand |
|---|---|---|:--:|
| OP1 | Konnektivitaet + Offline-Banner | ConnectivityStatusProvider (connectivity_plus + Reachability-Debounce, Online-Enum, Resume/visibilitychange-Recheck); AppOfflineBanner + AppConnectivityDot in lib/ui/ (appColors.warning/info, AppMotion.short); zentrale Einhaengung im Shell-Scaffold home_screen.dart via context.select. | M |
| OP2 | Skeleton-Loader statt Spinner | AppSkeleton/AppSkeletonList in lib/ui/ (surfaceContainerLow, AppRadii.md, RepaintBoundary-Shimmer, disableAnimations-safe); Vorlagen tiles/stats/rows; die 32 CircularProgressIndicator-Content-Stellen auf Skeleton + AnimatedSwitcher-CrossFade umstellen; Gate-/Start-Splash als const Signal-Teal-Logo. | L |
| OP3 | Optimistic/Pending + zuletzt-aktualisiert | AppPendingChip (AppStatus-Variante) + AppLastUpdated (relativ, de_DE) in lib/ui/; an Zeiterfassung/Schicht/Anfragen-Screens andocken; serverpflichtige Buttons je Offline-Verhaltensmatrix ausgrauen mit Tooltip. | M |
| OP4 | Push-Praeferenzen V2 + Pre-Permission | NotificationSettingsScreen auf AppSectionCard/AppKontoTile/Switches umbauen (Master + 5 Kanaele + Ruhezeiten + Haeufigkeits-Hinweise, Genehmigungen-Ausnahme sichtbar); Pre-Permission-Priming-BottomSheet (AppConfirmDialog) vor dem OS-Prompt; Anfragen-Center bleibt Tap-Ziel. | M |
| OP5 | PWA-Branding + Asset-Budget | web/manifest.json theme_color/background_color auf Signal-Teal; Icon-?v=-Query bump; Reduce-Motion/const/ListView.builder-Checkliste als Review-Gate; ggf. cached_network_image + cacheWidth/cacheHeight fuer neue Bild-Flaechen; no-web-resources-cdn-Build-Hinweis dokumentieren. | S |

**Querschnitt: Verhältnis zu bestehenden Plänen**

| ID | Meilenstein | Umfang | Aufwand |
|---|---|---|:--:|
| D0 | Abgleich-Verankerung: Bestandspläne als Referenzschicht | Masterplan verweist auf AP0.1-AP5.2 (ui-aufraeumen), Strangler-Schritte (redesign-signal-teal) und erledigte M1-M6 (analyse-5-tabs); 18 abgedeckte Anforderungen als Verweis, keine Neuplanung. | S |
| D1 | Plattform-Adaptiv-Layer (iOS/Android nativ) - Anf. 7 + 11 | Theme.of(context).platform-Weiche, .adaptive-Konstruktoren, CupertinoPageTransitionsBuilder fuer iOS, Edge-Swipe-Back, plattformgerechte Sheets/Pull-to-Refresh in lib/ui + AppTheme.pageTransitionsTheme. | L |
| D2 | Offline-UX-Layer - Anf. 13 | connectivity_plus + Reachability, entprelltes Online-Enum im App-State, Offline-Banner, Pending-Write-Kennzeichnung, zuletzt-aktualisiert, PWA-Service-Worker-Pruefung (Datenschicht existiert bereits in main.dart). | M |
| D3 | Push-Hygiene-UX - Anf. 14 | Benachrichtigungs-Einstellungsscreen aus notificationPrefs (Kanaele an/aus), Berechtigungs-Priming vor OS-Prompt, Buendelungs-Hinweise (Push-Infra fanOutPush existiert bereits). | M |
| D4 | Biometrie & sichere Anmeldung - Anf. 28 | local_auth-App-Lock (Face ID/Touch ID/Fingerprint) als Option in auth_screen_v2/Einstellungen, 2FA-Hinweis (Firebase MFA), sichere Token-Ablage; UX/Flow-Planung, minimaler Logik-Anteil als Grenzfall markiert. | M |
| D5 | Kontextuelle Permissions & Vertrauen - Anf. 29 + 30 | Priming-Sheet vor Kamera-Prompt (Scanner), Berechtigungs-Rationale, keine Standort/Kontakte ohne Anlass, sichtbare Sicherheits-/Datenschutz-Signale + Impressum/Datenschutz in-App. | M |
| D6 | Performance & Ressourcen - Anf. 12 + 16 | Skeleton-Loader statt Spinner, const/select-Rebuild-Scoping, Startzeit-Messung, Timer-/Poll-Reduktion offline, Bild-/Cache-Budget. | M |
| D7 | A11y-Ausbau & Dark/Light-Feinschliff - Anf. 19 + 20 | TextScaler bis 2.0 golden-getestet, WCAG-AA-Kontrast-Audit V2-Palette, VoiceOver/TalkBack-Durchlauf, System/Hell/Dunkel-Wahl konsistent (baut auf AP5.1/5.2 + M4/M5 auf). | M |


**Bereichs-Meilensteine:**

**Heute (Start)**

| ID | Meilenstein | Umfang | Aufwand |
|---|---|---|:--:|
| M1 | V1-Dashboards entfernen, V2 kanonisch | buildHomeTab ruft nur noch _EmployeeDashboardTabV2/_AdminDashboardTabV2; _EmployeeDashboardTab (home_screen_tabs.dart:12-202) und _AdminDashboardTab (:916-1127) samt ae/oe/ue-Literalen löschen; RedesignFlags-Verzweigung an dieser Stelle auflösen. Reine Struktur/Text, keine Logik. | M |
| M2 | Legacy-Karten auf lib/ui + Tokens migrieren | _ClockInOutWidget, _WeeklyProgressWidget, _TeamCalendarWidget, _PendingAbsencesWidget von roher Card/Magic-Numbers auf AppCard/AppSectionCard + context.spacing/radii; Skeleton statt Ladebalken-Sprung im Wochenfortschritt. | L |
| M3 | Primäraktion in Daumenzone (FAB + Stempel-Sheet) | Rollen-FAB auf ShellTab.today (Mitarbeiter=Stempeln, Planer=Anfragen); Stempelbedienung in AppBottomSheetScaffold-Sheet; Hero bekommt Live-Stempelstatus. Nur UI, ruft bestehende Stempel-Methoden. | L |
| M4 | Shell-Chrome vereinheitlichen + Offline-Banner + Suche | AppBar immer aktiv (V1-Lücke schließen), Menü-Semantics, Such-Action, entprelltes Offline-/Stale-Banner unter Top-Bar; Pull-to-Refresh in beiden Dashboards. | M |
| M5 | Drill-down & Warnkarte härten | AppMetricCard onTap-Navigation (Inbox/Plan/Team); DashboardActionItemsCard Icon-Token, unterschiedliche overdue/dueSoon-Icons+Text, Semantics-Header. | M |
| M6 | Barrierefreiheit & Motion durchziehen | Semantics auf allen QuickActions/Tiles/Hero/Metriken; Dynamic-Type-Prüfung 200%; gestaffelte List-Animation + Reduce-Motion-Guard; Detail-/Tausch-Sheet auf AppBottomSheetScaffold + AppConfirmDialog+Undo. | M |
| M7 | Responsive Tablet/Desktop-Feinschliff | Zweispaltiges Dashboard ab 840dp via LayoutBuilder; Team-Kalender als Master-Detail-Panel; Metric-Grid-Spalten pro Breakpoint; ConstrainedBox-Lesebreiten prüfen. | M |

**Plan (Schichtplan)**

| ID | Meilenstein | Umfang | Aufwand |
|---|---|---|:--:|
| P0 | V2-Fundament im Plan-Bereich: Barrel-Import + Klon-Helfer-Ersatz | lib/ui/ui.dart in shift_planner_screen.dart + shift_editor_sheet.dart + planner_cells.dart importieren; _controlPill/_filterPill/_outlineActionButton/_PickerField/_EditorSection/_EditorNoticeCard/_PlannerEmptyState/_AutoPlanStat durch AppSegmented/AppFilterChip/AppFormField/AppSectionCard/AppStatusBanner/AppEmptyState/AppStatusBadge ersetzen (reine Optik, API-gleich). | L |
| P1 | Rollen-Vereinheitlichung + Kopf/Umschalter | Ein Screen-Rahmen für beide Rollen; Ansicht/Layout durchgängig AppSegmented (statt PopupMenu-Pills + separatem SegmentedButton); AppHeroCard-Kontext-Kopf; tote Admin-Fallback-Dropdowns entfernen. | M |
| P2 | Mobile-Board: Tages-Agenda + untere Aktionsleiste/FAB | Bei <600 dp Default-Tag-Ansicht als vertikale Agenda statt horizontalem Pixelraster; BottomAppBar (Auto-Plan/Kopieren/Veröffentlichen) + FAB Neue Schicht (Admin) bzw. FAB Abwesenheit melden (Mitarbeiter); Veröffentlichen als FilledButton statt InkWell. | XL |
| P3 | Board-Raster tokenisieren + Barrierefreiheit + Farb-Semantik | Schichtkarten als AppCard, Deko-CustomPaint entfernen, hashCode-Farbe durch kontrastgeprüfte Standort-Palette + Label; Semantics an Karten/Zellen/Add-Buttons; sichtbare Kopieren/Verschieben-Aktion neben D&D; Anmerkungen-Link umbenennen. | L |
| P4 | Filterleiste + Freitext-Suche | AppFilterChip-Reihe + AppFormField-Suche + durchsuchbare Auswahl-Sheets (statt PopupMenu über alle Mitglieder); aktive Chips mit onDeleted + Alle-zurücksetzen; ≥48 dp. | M |
| P5 | Ein Kalender-Idiom: _PlanMonthGrid | TableCalendar (Mitarbeiter-Monat), Admin-Mini-Kalender und eigenes Monatsgitter auf einen wiederverwendbaren _PlanMonthGrid reduzieren; Sidebar/BottomSheet-Klon der Checkboxen auflösen; Chevrons ≥48 dp; Mehrfachauswahl für Multi-Tag-Picker. | L |
| P6 | Schicht-Editor auf AppBottomSheetScaffold + AppFormField + Inline-Validierung | Sheet-Chrome vereinheitlichen, keyboard-sichere Höhe (viewInsets); Ende>Beginn/Pause inline validieren; SnackBar-Fehler → handlungsleitende Meldungen; Pause number-only + helperText; Verwerfen-Schutz (AppConfirmDialog); .adaptive-Picker. | L |
| P7 | Auto-Plan-Vorschau: erklärte Ladephase + gruppierte Vorschau | Blockierenden Spinner durch erklärten Ladezustand ersetzen; Vorschau gruppiert/zusammengefasst pro Standort/Person; Stat-Chips via AppStatCards/AppStatusBadge; Fehler als AppStatusBanner. | M |
| P8 | Besetzungs-Profil-Feinschliff | Standort-Wähler tokenisieren; Heatmap mobil responsiv vereinfachen + Ø-Werte als Text; übernehmen ≥48 dp + AppConfirmDialog; Kontrast/Dark-Mode geprüft. | M |
| P9 | Offline-/Sync-UX + Motion-/A11y-Politur bereichsweit | AppStatusBanner (offline/zuletzt-aktualisiert) im Plan-Kopf; Cloud-Aktionen offline deaktivieren mit Hinweis; AnimatedSwitcher/Staggering über AppMotion.resolve (Reduce-Motion); Dynamic-Type-Test bei 200%; Umlaut-Korrekturen reiner Anzeige-Strings. | M |

**Zeit (Zeitwirtschaft)**

| ID | Meilenstein | Umfang | Aufwand |
|---|---|---|:--:|
| Z1 | Geteilte Bausteine + Monatszustand vereinheitlichen | Neue lib/ui-Widgets AppMonthNavigator/AppBanner/AppMetricRow/AppDataList extrahieren; AppStatusBadge konsequent verwenden; alle 6 Monats-Header-Kopien und 7 Status-Chip-Klone ersetzen; Kalender/Mitarbeiterabschluss/Lohnlauf/Monatsabschluss auf WorkProvider.selectedMonth umstellen. Reine Widget-Extraktion, kein Provider-Vertrag geändert. | L |
| Z2 | Hub zum Cockpit: Stempeln in die Daumenzone | Hub-Grid gruppieren (SectionHeader-Gruppen), persistenter Stempel-Aktionsbalken unten, KPI als Semantics-Gruppe, GridView statt manueller Breitenrechnung, Tablet-2-Spalten-Master. | M |
| Z3 | Stempeluhr: Feedback, Offline, sichere Formulare | clockIn/clockOut mit Spinner+disabled+SnackBar-Bestätigung+verständlicher Fehlermeldung umhüllen (kein Provider-Call geändert); untere Aktionsleiste statt FAB; Laden-Sheet mit Abbrechen+56dp; Pause als validiertes AppFormField; onSuccess/onWarning-Rollen; AppHeroCard-Ticker mit tabularFigures. | M |
| Z4 | Tabellen→adaptive Karten (Zeiterfassung/Stundenkonto/Monatsabschluss/Kalender) | AppDataList-Muster (Karten mobil, DataTable ≥840dp); FAB für Neue Arbeitszeit; Kalenderzellen ≥44dp antippbar+beschriftet+Semantics; Status Icon+Wort; Such-/Filterzeile. | XL |
| Z5 | Abwesenheiten + Admin-Screens: Struktur & Filter | ein primärer Antrags-FAB; Manager-Namens-/Zeitraumsuche; AppConfirmDialog(destructive); AppSegmented für Filter; Such-Feld full-width; Skeleton-Ladezustand Mitarbeiterabschluss; Lohnlauf KPI-Grid + adaptive ActionSheet. | L |
| Z6 | Legacy-Screens auf V2 migrieren (EntryForm/Statistik/Monatsbericht) | lib/ui-Komponenten statt Card/ListTile-Klone; context.spacing statt Hardcode; .adaptive-Picker; Ende>Beginn-Validierung; Chart-Semantics+feste Höhe; geteilte MobileBreakpoints; alle ASCII-Umlaut-Fehler korrigieren. | L |
| Z7 | Politur: Offline-Banner, Motion, Dark-Mode-Kontrast-Audit | App-Connectivity-Banner sichtbar machen; alle Übergänge via AppMotion.resolve (Reduce-Motion); Kontrast in Light+Dark je Screen prüfen (≥4.5:1 Text / ≥3:1 groß); Touch-Target-Audit ≥48dp. | M |

**Anfragen (Inbox)**

| ID | Meilenstein | Umfang | Aufwand |
|---|---|---|:--:|
| A1 | V2-Fundament Inbox-Hauptscreen | notification_screen.dart Kopf/Hero/Filter auf AppHeroCard+AppStatCards+AppSegmented umstellen, Zahlen-Duplizierung entfernen, Umlaute reparieren, Semantics-Header. Keine Datenpfad-Änderung. | M |
| A2 | Suche + sticky Filterleiste + pull-to-refresh | SliverPersistentHeader-SearchBar (Debounce 250ms, clientseitiges Filtern), Fade-Rand an Segmenten, RefreshIndicator/CupertinoSliverRefreshControl. | M |
| A3 | Inbox-Karte auf AppCard + AppStatusBadge + Bestätigungen | _InboxItemCard→AppCard, item.color→AppStatusTone, AppConfirmDialog vor Genehmigen/Ablehnen, Row+Expanded 48dp-Buttons, Fehler-Klartext+Retry, Karten-Semantics. | M |
| A4 | Daumenzone-Primäraktion | Quick-Antrag-Buttons in FAB.extended/untere SafeArea-Leiste verlagern; Sheet-Auswahl der Antragsart. | S |
| A5 | Antrag-Sheet auf AppBottomSheetScaffold + AppFormField | _AbsenceRequestSheet umbauen: scrollbar/keyboard-safe, Von/Bis als tappbare Datum-Felder, Inline-Validierung on-blur, Verwerfen-Bestätigung, Umlaute. | L |
| A6 | Kundenwünsche-Screen V2 + Suche + sichtbare CTA | customer_wishes_screen.dart: AppCard, SectionHeader, SearchBar+AppSegmented, Primär-CTA sichtbar, Skeleton+Retry. | M |
| A7 | Feedback-Screen als Zwilling vereinheitlichen | customer_feedback_screen.dart an §6-Muster angleichen (Kopf/Chips/Karten/Labels), gemeinsames Listen-Gerüst extrahieren (UI-only). | M |
| A8 | Wünsche+Feedback in Posteingang integrieren | Manager-Filter „Wünsche"/„Feedback" im /anfragen-Screen (bestehende Provider-Getter/Streams, kein neuer Datenpfad); Deep-Links bleiben. | M |
| A9 | Push-Einstellungen V2 + Speicher-Feedback | notification_settings_screen.dart: AppSectionCard, BreadcrumbAppBar, TimePicker de_DE, Speichern/Fehler-Feedback, Kategorie-Erklärungen. | S |
| A10 | Urlaubskonto: Suche + Grenzen + Semantics | abwesenheit_screen.dart: SearchBar, Jahr-Grenzen, Kennzahl-Semantics. | S |
| A11 | Master-Detail-Layout ≥840dp | LayoutBuilder+MobileBreakpoints für Inbox/Wünsche/Feedback/Urlaubskonto (Liste+Detail-Pane), Content-maxWidth vereinheitlichen. | L |
| A12 | Offline-UX + native Feinschliff + Reduce-Motion-Audit | AppStatusBanner-Offline/zuletzt-aktualisiert, Swipe-Actions, .adaptive-Controls, disableAnimations-Prüfung, Dark/Light+Kontrast-Abnahme. | M |

**Kontakte (Adressbuch)**

| ID | Meilenstein | Umfang | Aufwand |
|---|---|---|:--:|
| K1 | Kopf & Filter straffen | Sticky-Suchleiste (SliverPersistentHeader), eine Kategorie-Chip-Zeile + Filter-Sheet (Standort/Wichtig/Archiviert), Export/Import ins Überlauf-Menü, kompakte AppStatCards, einzelner Reset-Punkt, FAB vereinfachen. Nur contacts_screen.dart Kopfbereich (Z.104-353). | M |
| K2 | Kontakt-Karte modernisieren | Initialen-Avatar, InfoChip statt _MetaChip, Direkt-Aktion (Anruf/Mail) + Überlauf, volle Semantics, optionaler Swipe (Favorit/Bearbeiten). _ContactCard/_Avatar/_MetaChip (Z.881-1129). | M |
| K3 | Detail als Aktionszentrale + url_launcher | CTA-Zeile (Anrufen/Mail/Web/Route via url_launcher), gruppierte Abschnitte, antippbare _DetailRows, abgesetztes Löschen, DateFormat de_DE, Token-Cleanup im Alle-anzeigen-Sheet. _ContactDetailSheet/_DetailRow (Z.1147-1469). | L |
| K4 | Master-Detail-Split (Tablet/Desktop) | ResponsiveLayout-Zweig ab 600/840: Liste links, Detail-Panel rechts (inline statt Sheet), Editor als Panel-Sheet, Auswahl-Highlight, Empty-Panel. Neuer Layout-Wrapper um build (Z.75-188). | L |
| K5 | Editor gruppieren + validieren | AppSectionCard-Abschnitte, V2-Dropdown-Felder, E-Mail/Website/PLZ-Validierung + Inline-Fehler, PopScope-Dirty-Schutz, sticky Speichern, PLZ-Formatter. _ContactEditorSheet (Z.1473-1821). | L |
| K6 | Aktivität & CSV-Import auf V2-Sheets | AlertDialoge → AppBottomSheetScaffold; Aktivität mit AppSegmented + Uhrzeit + Mindestvalidierung + de_DE; Import mit file_picker-first + Fehlerliste. (Z.460-539, 566-660). | M |
| K7 | Picker-Klon angleichen | contact_picker_field.dart auf AppFormField/AppFilterChip/Initialen-Avatar/DraggableScrollableSheet heben, Typ-Filter bei allowedTypes. (Z.136-204). | S |
| K8 | Zustände: Skeleton, Retry, Offline-Banner | Skeleton-Karten statt Spinner, Retry im Fehlerbanner, Offline-/Stand-Indikator, Token-Cleanup. (Z.135-153, 1851-1883). | S |
| K9 | A11y- & Dark-Mode-Durchgang | Semantics für Karten/Avatare/Icon-Buttons/Chips, Kontrast-Check appColors in Dark+Light, Dynamic-Type-Test, Reduce-Motion. Screenreader-Smoke-Test iOS/Android. | M |

**Laden (Warenwirtschaft & Kasse)**

| ID | Meilenstein | Umfang | Aufwand |
|---|---|---|:--:|
| L1 | Design-System-Fundament & Laden-Hub | Hub gruppiert (Tägliche Arbeit / Auswertungen / Verwaltung) mit AppHeroCard + AppStatCards + AppStatusPill; alle ae/oe/ue→Umlaute; globales _ConnectivityBand + 'Zuletzt aktualisiert' als wiederverwendbares Widget in lib/ui. Reine Optik/Layout. | M |
| L2 | Warenwirtschaft-Shell neu (Sub-Nav + AppBar entschlacken) | 5 scrollbare Tabs → 4er AppSegmented (unten Mobile / Rail Desktop), Kühlschrank in Hub verschoben; AppBar auf Such-Icon + Mehr-Overflow (Aktionsblatt via AppBottomSheetScaffold) reduziert; Master-Detail ab 840 dp; _TabLabel-Badge→AppStatus. | L |
| L3 | Tab Bestand: Suche/Filter + Statusredundanz + Produktkachel | Debounced Suche, Filter-Chips (Kategorie/Lieferant/nur knapp), _ProductTile→AppCard mit Icon+Text-Status+Semantics+tabularFigures, Löschen mit Warnfarbe; AppMetricCard-Warenwert. | M |
| L4 | Formulare auf AppBottomSheetScaffold (Produkt/Lieferant/Kundenbestellung) | AlertDialog(420/460)→AppBottomSheetScaffold + AppFormField; autovalidateMode:onUserInteraction, Fokus-Sprung, €-Suffix/keyboardType/Validatoren, PopScope-Verwerfen-Schutz. | L |
| L5 | Bestellkorb + Lieferanten/Bestellungen + PO-Editor | Button-Hierarchie im Korb, Korb-leeren mit Bestätigung, Token statt Magic-Number; _StatusChip→AppStatus + Suche/Filter in Listen; PO-Editor Mengen ≥48dp+Semantics+PopScope; Master-Detail ab 840. | L |
| L6 | Scanner-Redesign (vollflächig, Daumenzone, Tokens, A11y, Permission) | Vollflächige Kamera + untere Steuerleiste, Colors.*→Tokens, Permission-EmptyState mit 'Einstellungen öffnen'+Erklärtext, SemanticsService.announce + Haptik, Ergebnis-Sheet. | L |
| L7 | Analyse-Vorlage vereinheitlichen | Einheitliche Filter (AppSegmented/AppFormField), AppStatCards, Chart-Tooltip+Semantics-Summary+scrollbar, Skeleton-Ladezustände; Tagesabschluss/Kassierer-Prüfung Validierung + AppStatus-Schwere. | M |
| L8 | Kiosk-Board & PIN-Login härten (Layout/A11y) | Wrap-Rechnung→GridView/SliverGrid, Kachel-Status→AppStatus(Icon+Text+Semantics), PIN-Pad größer+Semantics+Haptik+Demo-PIN nur Demo, Auto-Logout-Countdown + Abmelden-Bestätigung, Tokens statt Colors.*. | L |
| L9 | Querschnitt: Dark-Mode/Dynamic-Type/Reduce-Motion-Audit + Golden-Tests | Alle Laden-Screens in Light+Dark, 200% Textskalierung und Reduce-Motion prüfen; Semantics-Coverage; Golden-Tests via router_harness/pumpApp für Hub, Bestand, Scanner, Kiosk. | M |

**Profil, Einstellungen & Verwaltung**

| ID | Meilenstein | Umfang | Aufwand |
|---|---|---|:--:|
| PV-M1 | Geteilte V2-Bausteine schaffen | Neue lib/ui-Komponenten AppMetaChip, AppSearchField, AppBottomBar, AppPeriodBar, AppListStates (Loading-Skeleton/Offline/Empty/Error), AppTabBar (Count-Badges + Overflow-Fade) und _friendlyError-Helper. Ersetzen die file-privaten Klone. Fundament fuer alle folgenden Meilensteine. Nur Praesentation. | L |
| PV-M2 | Profil-Hub auf V2 + Zwei-Zonen-Struktur | _ProfileHubTab: AppHeroCard, Gruppen Mein Konto/Verwaltung, AppKontoTile statt _QuickActionCard, Abmelden in AppBottomBar, Semantics, kleine-Screen-Liste statt Kacheln. | M |
| PV-M3 | Einstellungen: Speichermodell + V2 + Formular-Haertung | Sticky Speicherleiste nur fuer Formfelder, PopScope-Dirty-Guard, AppSegmented-Theme, AppConfirmDialog fuer Speichermodus-Wechsel, AppFormField mit Pflicht/Validierung, _friendlyError, Admin-Autoplan visuell abgesetzt. | L |
| PV-M4 | Teamverwaltung: Suche/Filter alle Tabs, sichtbare Aktionen, Master-Detail | AppSearchField in 4 Tabs, PopupMenu->sichtbare Buttons/AppBottomBar, AppConfirmDialog bei Deaktivieren, AppListStates, AppTabBar, Chips auf 3+n reduzieren, Tablet-Master-Detail. | XL |
| PV-M5 | Personal-Feinschliff | Count-Badges an Tabs, AppPeriodBar mit Month-Picker, Suche in Auftraege/Lohn, Kassierer-Pruefung als sichtbare Kachel, _friendlyError, Chart-Semantics, Skeleton fuer Stats/Finanzen. | L |
| PV-M6 | Buchhaltung: Journal-Filter, sichtbarer Export, Jahr-Picker | AppSearchField+Filter im Journal, Export/DATEV in AppBottomBar, AppPeriodBar Jahr-Picker, Offline-Hint fuer Export, AppTabBar, Master-Detail Tablet. | L |
| PV-M7 | Audit-Log + Store-Health V2-Angleich | AuditLog: V2-Filterbar, AppCard-Zeilen, Meta-Chips statt \n, Infinite-Scroll, Semantics. StoreHealth: AppStatCards, Delta mit Text+Badge (farbenblind-sicher), Offline-State. | M |
| PV-M8 | Force-Update + Sicherheit/Sitzung + Datenschutz | ForceUpdate: AppHeroCard + Store-Button (Sackgasse aufloesen). Sicherheits-Sektion: echter Sitzungsstatus + Biometrie-Toggle (UI-Vorbereitung, deaktiviert). Datenschutz-Hinweis in Daten & Speicher. | M |

---

## 19. Offene Entscheidungen, Widersprüche & Risiken

> **✓ Entschieden (2026-07-01):** Die sechs Entscheidungs-/Widerspruchspunkte dieses Kapitels sind in **[Kap. 0.2 Getroffene Entscheidungen](#02-getroffene-entscheidungen-verbindlich-stand-2026-07-01)** verbindlich aufgelöst (E1 Textskala gestuft · E2 Biometrie+2FA in-scope, Blaze ist live · E3 `AppMotion.resolve` kanonisch · E4 Master-Detail ab 840 dp · E5 Push-Owner Anfragen A9 · E6 Rollout-Reihenfolge bestätigt). Dieses Kapitel bleibt als **Herleitung** stehen; die Bereichs-Risiken darunter sind weiterhin je Rollout-Schritt zu behandeln.

Aus der adversarialen Vollständigkeits-Kritik. Diese Punkte **vor** dem jeweiligen Rollout-Schritt auflösen — sie sind die einzigen Stellen, an denen die Bereichs-Entwürfe optimistisch waren.

### Zu treffende Entscheidungen / aufzulösende Widersprüche

| Zu entscheiden / Widerspruch | Auflösung / Empfehlung |
|---|---|
| Dynamic-Type-Zielwert widerspricht sich: Fast alle Bereichs-Entwürfe (Heute M6, Plan P9, Zeit Z7, Anfragen A12, Kontakte K9, Laden L9) und das A11y-Querschnittsthema versprechen 'Dynamic Type 200%' bzw. 'Textskalierung bis 200% ohne Bruch'. Der Code klemmt aber bei kMaxTextScaleFactor = 1.5 (lib/core/accessibility.dart:20, angewandt in lib/main.dart:680 via clampTextScaler). Es kann nicht gleichzeitig bei 1.5 geklemmt UND bei 200% getestet/unterstützt werden. | Eine Entscheidung app-weit fixieren: Entweder kMaxTextScaleFactor auf 2.0 anheben und dann jeden dichten Screen (Admin-Raster, Kiosk, Tabellen, Charts) bei 2.0 real auf Overflow prüfen (deutlich mehr Layout-Aufwand als geplant), oder beim 1.5-Clamp bleiben und alle '200%'-Formulierungen auf 'bis 150% (System-Clamp)' korrigieren. Empfehlung: gestuft — Clamp auf 2.0 nur für Text-lastige Lese-Screens, dichte Raster als dokumentierte Ausnahme. |
| Reduce-Motion-Mechanik doppelt beschrieben: Offline/Performance-Querschnitt und mehrere Bereiche referenzieren 'AppMotion.resolve(context, ...)'; das A11y-Querschnittsthema fordert parallel 'context.motionDuration(...)' aus lib/core/accessibility.dart als Pflicht. Beide APIs existieren (AppMotion.resolve in theme_extensions.dart UND motionDuration/prefersReducedMotion in accessibility.dart) und tun dasselbe. | Eine kanonische Reduce-Motion-API festlegen (AppMotion.resolve ist bereits in auth_screen_v2 und den Public-Screens verbreitet) und die andere als Delegat/deprecated markieren. Sonst driften zwei Pfade auseinander und Reviews prüfen den falschen. |
| Master-Detail-Breakpoint uneinheitlich: Kontakte K4 nennt '600/840' bzw. '600–839 (40/60)', während der Responsive-Querschnitt Master-Detail VERBINDLICH erst 'ab expanded (840dp)' erlaubt und unter 840dp BottomSheet-Verhalten beibehält. Heute M7/Anfragen A11/Zeit nennen konsistent 840. Kontakte weicht ab. | Kontakte K4 an die Querschnitts-Leiter angleichen: Master-Detail erst ab 840dp (expanded), 600–839 einspaltig+Sheet. Der Querschnitt ist die Autorität; K4 ist zu korrigieren. |
| Push-Anforderung 14 wird bereichsweise als 'keine Änderung / bewusst neutral' abgehakt (Plan, Zeit, Kontakte, Laden), während Anfragen A9 und der Offline/Push-Querschnitt D3 ein echtes Push-Hygiene-/Einstellungs-Redesign mit Pre-Permission-Priming planen. Ohne klare Zuordnung droht, dass jeder Bereich '14 = nicht mein Thema' sagt und der zentrale Screen keinem fest zugewiesen ist. | Anforderung 14 exklusiv Anfragen A9 (notification_settings_screen) + Querschnitt D3 zuweisen; alle anderen Bereiche verlinken nur dorthin. Ein Owner + ein Ziel-Screen als Definition of Done. |
| Biometrie/Permission-Deltas verletzen die 'nur Optik/Layout'-Leitplanke, die fast jeder Bereich als Grund nennt, warum 28/29 'außerhalb des Tabs' liegen. Der Abgleich-Querschnitt gibt selbst zu, dass 28 (local_auth) und 29 (permission_handler/JIT-Priming) NEUE client-only Pakete + minimalen Logikanteil brauchen — also gerade KEIN reines UI-Delta. Verifiziert: weder local_auth noch permission_handler sind im pubspec. | 28/29 aus der reinen UI-Strangler-Leitplanke herauslösen und als eigenständige Feature-Arbeitspakete mit Pubspec-Änderung, Plattform-Konfig (Info.plist/AndroidManifest) und Tests führen. Nicht als 'nur Optik' in einen Screen-Redesign-Commit mischen. |

### Konkrete Lücken mit Empfehlung

| Lücke | Betrifft | Beschreibung → Empfehlung |
|---|---|---|
| Dynamic-Type-Zielwert app-weit nicht mit dem Code konsistent (150% vs. 200%) | Barrierefreiheit / Design-System | Der Code klemmt textScaler bei kMaxTextScaleFactor=1.5 (lib/core/accessibility.dart:20, lib/main.dart:680). Fast jeder Bereich (Heute M6, Plan P9, Zeit Z7, Anfragen A12, Kontakte K9, Laden L9) und der A11y-Querschnitt versprechen aber '200% ohne Bruch'. Nicht erfüllbar, solange der Clamp bei 1.5 steht. → **Vor Rollout Grundsatzentscheidung: Clamp auf 2.0 anheben und dichte Raster (Kiosk/Admin/Charts) als dokumentierte Ausnahmen behandeln, ODER alle '200%'-Formulierungen auf 'bis 150% (System-Clamp)' korrigieren. Als eigenen Design-System-Meilenstein vor den Bereichs-A11y-Durchgängen einplanen.** |
| Fundament-Komponenten (AppErrorState, AppSearchField, globale SearchAnchor) fehlen noch, werden aber überall vorausgesetzt | Design-System-Fundament | Verifiziert: lib/ui hat AppStatusBanner/AppEmptyState, aber KEIN AppErrorState und KEIN AppSearchField; es gibt kein SearchAnchor/SearchBar im gesamten Code. Anfragen/Zeit/Kontakte/Laden bauen auf AppSearchField/AppErrorState als existierten sie (Anf. 17 und 24). → **DS3 (AppErrorState + AppSearchField) und Nav-N4 (globale SearchAnchor) als harte Vorbedingung VOR die Bereichs-Meilensteine ziehen. Bereichs-Meilensteine, die diese Bausteine nutzen, erst nach DS3/N4 mergen — sonst entstehen erneut Klone.** |
| connectivity_plus / local_auth / permission_handler / url_launcher / file_picker nicht im pubspec — die 'echten Deltas' sind größer als UI | Offline / Sicherheit / Datenschutz / Cross-Platform | Verifiziert: pubspec enthält nur firebase_auth und mobile_scanner; connectivity_plus, local_auth, permission_handler, url_launcher, file_picker fehlen. Offline-UX (13), Biometrie (28), JIT-Permissions (29), Kontakt-Direktaktionen (K3 url_launcher) und CSV-Import (K6 file_picker) brauchen neue Pakete + Plattform-Konfig (Info.plist LSApplicationQueriesSchemes, AndroidManifest queries/permissions). → **Ein eigenes 'Plattform-Fundament'-Arbeitspaket vor 7/11/13/28/29 und vor Kontakte K3/K6: Pakete hinzufügen, Info.plist/AndroidManifest-Einträge, Web-Fallbacks (tel/geo, file_picker), je Plattform (iOS/Android/Web) verifizieren. Diese Deltas NICHT als 'nur Optik' behandeln.** |
| Push-Anforderung 14 hat keinen eindeutigen Owner | Push / Anfragen | Vier Bereiche haken 14 als 'keine Änderung/neutral' ab, während Anfragen A9 + Querschnitt D3 den einzigen echten Push-Hygiene-Screen bauen. Risiko: der zentrale NotificationSettings-Redesign fällt zwischen die Bereiche. → **14 exklusiv Anfragen A9 + Querschnitt D3 zuweisen, alle anderen Bereiche verlinken nur. Ein Ziel-Screen (notification_settings_screen) + Pre-Permission-Priming-Flow als Definition of Done.** |
| God-File-Umbau ohne verpflichtendes Test-Sicherheitsnetz | Testing / Refactoring | Nahezu jeder Bereich nennt sehr große Dateien (shift_planner 6155, shift_editor 3640, notification 2227, contacts 1883, team 4648, personal 5649) und Regressionsrisiko beim UI-Umbau. Golden/Widget-Tests werden nur als 'sollte' erwähnt, nicht als Gate. → **Pro Bereich verpflichtende Characterization-/Golden-Tests via router_harness (pumpApp) als Merge-Gate, BEVOR der jeweilige God-File angefasst wird. Refactor und Verhaltensänderung nie im selben Commit — als Regel festschreiben.** |
| Master-Detail-Breakpoint uneinheitlich zwischen Kontakte (600) und Querschnitt (840) | Responsive Layout | Kontakte K4 aktiviert Master-Detail ab 600dp; der Responsive-Querschnitt legt 840dp als verbindlich fest. Divergenz führt zu inkonsistentem Verhalten Tablet-quer. → **Kontakte K4 auf 840dp (expanded) angleichen; 600–839 einspaltig+Sheet. AdaptiveMasterDetail zentral verwenden, kein Bereichs-Sonderweg.** |
| Offline-Verhaltensmatrix bleibt abstrakt | Offline | Der Offline-Querschnitt nennt eine 'Verhaltensmatrix je Bereich' (lesbar/schreibbar/gesperrt), aber die konkrete Zuordnung pro Screen (welche Buttons genau offline onPressed:null) ist nicht ausgefüllt. Callables/Compliance/OktoPOS/DATEV sind gesperrt — muss je Screen konkret werden. → **Als Artefakt eine konkrete Tabelle Screen×Aktion×Offline-Zustand erstellen und je Bereich als Checkliste in den jeweiligen Offline-Meilenstein aufnehmen; sonst wird 'ausgegraut' inkonsistent umgesetzt.** |
| Reduce-Motion doppelte API | Motion / A11y | AppMotion.resolve (theme_extensions.dart, bereits in auth_screen_v2/public-Screens genutzt) und context.motionDuration/prefersReducedMotion (accessibility.dart) existieren beide. Pläne referenzieren mal die eine, mal die andere. → **AppMotion.resolve als kanonisch festlegen; accessibility.dart-motionDuration intern darauf delegieren oder deprecaten. In Review-Checkliste aufnehmen.** |

> **Bereichs-Risiken:** Jedes Bereichs-Kapitel oben führt am Ende seine eigenen 6–8 spezifischen Risiken (God-File-Regression, Swipe-Kollisionen, Farb-Semantik im Board etc.). Sie sind dort verortet und nicht hier dupliziert.

---

## 20. Verhältnis zu bestehenden Plänen

Vor dem neuen Gesamt-Masterplan wurden die drei bestehenden UI-Pläne vollständig gelesen und ehrlich gegen die 30 UX-Anforderungen des Nutzers abgeglichen. Ziel: **keine Doppelarbeit**. Der Masterplan **konsolidiert und erweitert** diese Pläne — er ersetzt sie nicht. Wo eine Anforderung bereits durch ein bestehendes Arbeitspaket getragen wird, verweist der Masterplan darauf statt es neu zu erfinden; nur echte Lücken (v.a. plattform-native iOS/Android-Muster, Biometrie/2FA, Offline-UX, Push-Hygiene, kontextuelle Permissions, adaptive Cupertino-Widgets) werden als **Delta** neu geplant.

### 1. Was die drei Pläne bereits abdecken (nicht neu bauen)

| Plan | Datei | Deckt bereits ab |
|---|---|---|
| **Signal-Teal Redesign** | `plan/redesign-signal-teal.md` | **Design-System V2** (Seed `#0E7C7B`/`#5FD4CE`, ColorScheme hell/dunkel unabhängig), **V2-Token-Extensions** (`AppRadii` xs8–2xl36, `AppMotion` short150–extraLong600 + `disableAnimations`-Respekt, `AppElevation` flat0–overlay6, `AppSpacing` +xxs2/xxl48, `AppIconSizes` sm18–hero40, Touch-Targets 64×52/48), **Dark+Light** (unabhängig definiert), **`lib/ui/`-Komponentenbibliothek** (AppCard/AppSectionCard/AppMetricCard/AppHeroCard/AppQuickAction/AppSegmented/AppStatus/AppBottomSheetScaffold/AppFormField/AppConfirmDialog), **Screen-für-Screen-Strangler-Rollout** hinter `redesign_v2`, **Charakterisierungs-/Dual-Theme-Goldens** |
| **UI aufräumen & verteilen** | `plan/ui-aufraeumen-und-verteilen.md` | **Token-Lücken** (12/6 als Stufen, theme-bewusstes Radii-Mapping), **God-File-Splits** (shift_planner 6.352 Z, personal 5.639 Z, team 4.633 Z, home ~7.300 Z, inventory/notification/finance/contacts/scanner), **DS-Adoption** (Klon-Dedup Status-Badge/Banner/Stat-/QuickAction-Karten, MonthSwitcher/FilterBar/DateField), **Magic-Number-Migration** (Spacing/Radii/Typo), **Navigation/IA** (eine kanonische Descriptor-Liste, Hub-Domänentrennung, Orphan-Route `/kundenwuensche`, Scanner-Permission-Vereinheitlichung), **Responsive/Raum** (zentraler Content-Cap `kContentMaxWidth`, Master-Detail ab ~1000 px, eine Spaltenformel), **A11y-Phase 5** (Tap-Targets ≥48 dp, Semantics-Badge-Zähler, Kontrast onXContainer, LoadingState) |
| **Analyse 5 Tabs** | `plan/analyse-5-tabs-behebung.md` | **Umgesetzt (M1–M6):** Crash-Fixes (Avatar-RangeError, `tryParseHexColor`), stille-Fehler-Fixes (Q1 try/catch + Erfolg-nur-bei-Erfolg), Handy-Overflows (Q2 InfoChip-Wurzelfix, Header/TabBar `isScrollable`/AppBar-Menü/Position-Dialog), Touch-Targets (Q3, BottomNav-Text-Scaling 1.0→1.3), **`redesign_v2` als Code-Default `true`**, Publish-Push real via `onShiftWritten` |

**Wichtiger Ist-Zustand (verifiziert im Code):** `redesign_v2` ist bereits Default `true` (`RedesignFlags.defaultEnabled`), d.h. **V2 ist live** — das Design-System-Fundament der Anforderungen 3/21/26 existiert also schon und muss nur konsequent adoptiert werden, nicht erfunden. Firestore-Offline-**Persistence** ist in `main.dart` aktiv (`persistenceEnabled: true`, Zeilen 204/214) — Anforderung 13 hat also eine Datenschicht, aber **keine Offline-UX**.

### 2. Was für die 30 Anforderungen NOCH FEHLT oder nur teilweise adressiert ist (Delta-Liste)

Der ehrliche Kern: Die drei Pläne sind stark bei **visueller Konsistenz, Struktur, Aufräumen und A11y-Basics** — sie decken damit Anf. 1–5, 8–10, 15, 17–19, 21–27 überwiegend ab. Sie sind **schwach oder stumm** bei allem **Plattform-Nativen und Sicherheits-/Datenschutz-Nahen**. Konkret fehlt:

| # | Anforderung | Status in bestehenden Plänen | Delta (neu im Masterplan) |
|---|---|---|---|
| **7** | Optimierung iOS + Android (native Design-Gewohnheiten) | **Fehlt fast ganz.** Redesign-Plan ist rein Material-3; `Cupertino` im Code nur als `CircularProgressIndicator.adaptive` (2×) — kein Konzept | **Adaptive-Layer:** `Theme.of(context).platform`-Weiche, `.adaptive`-Konstruktoren (Switch/Slider/Dialog/RefreshIndicator), Cupertino-Bottom-Sheets/Pull-to-Refresh wo iOS-typisch |
| **11** | Native Bedienkonzepte (Zurück-Gesten, Tabs, Listen, Gesten je Plattform) | **Fehlt.** go_router-Back/`PopScope` existiert, aber kein iOS-Swipe-Back-Konzept, keine plattformspezifischen Transitions | **`CupertinoPageTransitionsBuilder` für iOS**, Edge-Swipe-Back-Konsistenz, plattformgerechte Nav-Transitions in `AppTheme.pageTransitionsTheme` |
| **12** | Schnelle Ladezeiten mobil (auch schwaches Netz) | **Nur indirekt** (God-File-Split senkt Rebuild-Kosten). Kein Start-Zeit-/Skeleton-Konzept | **Skeleton-Loader statt Spinner**, `const`/`select`-Rebuild-Scoping als eigenes Paket, Startzeit-Messung (flutter-performance-Skill) |
| **13** | Offline-Funktionalität (wichtige Funktionen ohne Netz) | **Datenschicht ja** (Firestore-Persistence in `main.dart`), **UX nein.** Kein Konnektivitäts-State, kein Offline-Banner, kein „zuletzt aktualisiert", kein Pending-Indikator | **Offline-UX-Layer:** `connectivity_plus` + Reachability, entprelltes Online-Enum im App-State, Offline-Banner, Pending-Write-Kennzeichnung, PWA-Service-Worker-Prüfung (flutter-offline-modus-Skill) |
| **14** | Push-Benachrichtigungen (informieren, nicht zu viele) | **Teilweise.** Push-Infra existiert (`fanOutPush`, `notificationPrefs`, Analyse-Plan machte Publish-Push real) — aber **kein UX-Konzept für Hygiene/Einstellungen im UI** | **Push-Hygiene-UX:** Benachrichtigungs-Einstellungsscreen (Kanäle an/aus, aus `notificationPrefs`), Berechtigungs-Priming-Dialog vor OS-Prompt, Bündelungs-Hinweise |
| **16** | Akku-/speicher-/datenschonend | **Nicht adressiert.** | **Ressourcen-Budget:** Timer-Intervalle prüfen (30 s/60 s-Ticks), Poll-Reduktion offline, Bild-/Cache-Größen — reine UX-/Client-Leitplanken |
| **19** | Barrierefreiheit (Kontraste, größere Schrift, Screenreader) | **Teilweise** (AP5.1/5.2 + M4/M5 umgesetzt). Kein systematisches `TextScaler`-Konzept über 1.3, kein Kontrast-Audit-Gate | **A11y ausbauen:** TextScaler bis 2.0 golden-getestet, WCAG-AA-Kontrast-Audit V2-Palette, Screenreader-Durchlauf iOS VoiceOver/Android TalkBack |
| **20** | Dark + Light Mode | **Ja** (V2 hell/dunkel unabhängig) — **aber** kein System-Follow-Toggle-Audit, Locale erzwingt de_DE, ThemeProvider-Verhalten prüfen | Kleines Delta: „System/Hell/Dunkel"-Wahl konsistent in Einstellungen, System-Default respektieren |
| **28** | Sichere Anmeldung (Passwort, Fingerabdruck, Face ID, 2FA) | **Fehlt komplett.** Kein `local_auth`, keine Biometrie, kein 2FA-Konzept; nur E-Mail/Google in `auth_screen_v2.dart` | **Neu:** Biometrie-Gate (`local_auth`, Face ID/Touch ID/Fingerprint) als App-Lock-Option, 2FA-Hinweis (Firebase MFA), sichere Token-Ablage (flutter-api-sicherheit-Skill) — **UX/Flow-Planung, Auth-Logik nur wo unvermeidlich** |
| **29** | Datenschutzfreundlich (nur nötige Permissions: Kamera/Standort/Kontakte) | **Fehlt.** Scanner nutzt Kamera, aber kein kontextuelles Permission-Priming, keine Just-in-time-Begründung | **Kontextuelle Permissions:** Priming-Sheet vor Kamera-Prompt (Scanner), Berechtigungs-Rationale, keine Standort/Kontakte-Anfrage ohne Anlass |
| **30** | Vertrauenswürdiges Design (professionell, sicher) | **Indirekt** (V2-Optik). Kein explizites Vertrauens-/Sicherheits-Signaling (Login-Sicherheitshinweise, Rechtsseiten-Verlinkung in-App) | Kleines Delta: sichtbare Sicherheits-/Datenschutz-Signale, Impressum/Datenschutz auch in-App erreichbar |
| **6** | Responsives Design (PC/Tablet/Smartphone) | **Weitgehend** (AP4.5 Master-Detail + Content-Cap + eine Spaltenformel) | Nur Restabdeckung: Desktop-Fenster/Menüs (flutter-cross-platform) als Zusatz, kein Kernneubau |

**Vollständig durch bestehende Pläne abgedeckt (kein Delta nötig, nur ausführen):** 1, 2, 3, 4, 5, 8, 9, 10, 15, 17, 18, 21, 22, 23, 24, 25, 26, 27. Diese wandern als **Verweis** (nicht als neue Arbeit) in den Masterplan.

### 3. Verhältnis des neuen Masterplans zu den drei Plänen

- **Konsolidiert, ersetzt nicht.** Der Masterplan referenziert die bestehenden Arbeitspakete (AP0.1–AP5.2 aus `ui-aufraeumen-und-verteilen.md`, die Strangler-Schritte aus `redesign-signal-teal.md`, die erledigten M1–M6 aus `analyse-5-tabs-behebung.md`) als **Bestandsschicht** und legt darüber nur die **Delta-Pakete** (Anf. 7, 11, 12, 13, 14, 16, 28, 29 + A11y-Ausbau 19).
- **Leitplanken bleiben identisch:** Nur Optik/Layout/Struktur/UX — keine Änderung an Provider/Services/Models/Firestore/Functions/Compliance/Serialisierung. Deutsch, `de_DE`. Status-Farben nur aus `Theme.of(context).appColors`. Strangler, klein & mergebar, `flutter analyze` + `flutter test` grün je Paket, Offline-Smoke `APP_DISABLE_AUTH=true`. Ausnahme: die Sicherheits-Deltas (28/29) berühren zwangsläufig Auth-Flow/Permission-Requests — dort wird die **UX/Flow** geplant und der minimale Logik-Anteil (z.B. `local_auth`-Gate, Permission-Priming) explizit als Grenzfall markiert.
- **Reihenfolge-Fit:** Die Delta-Pakete setzen auf dem Fundament auf — erst wenn AP0.1–AP0.3 (Tokens/Komponenten/geteilte Widgets) stehen, greifen adaptive Widgets (7/11) und Skeletons (12) sauber; Offline-UX (13) und Push-Hygiene (14) sind unabhängig davon sofort startbar; Biometrie/Permissions (28/29) hängen nur an `auth_screen_v2`/`scanner` und sind isoliert mergebar.
- **Keine Doppelarbeit:** Da `redesign_v2` bereits Default `true` ist und M1–M6 umgesetzt sind, plant der Masterplan **keine** erneute V2-Grundinstallation und **keine** Wiederholung der 5-Tabs-Fixes — er baut nur die 9 fehlenden plattform-nativen/Sicherheits-Deltas.

---

## 21. Anhang — Priorisierte nächste Schritte

Direkt umsetzbare Reihenfolge aus der Kritik (die ersten drei sind harte Vorbedingungen für alles Weitere):

1. Grundsatzentscheidung Dynamic Type (1.5 vs. 2.0) treffen und app-weit in allen Plan-Texten vereinheitlichen — blockiert sonst jeden A11y-Abnahme-Schritt (Anf. 19/4).
2. Plattform-Fundament-Paket vorziehen: connectivity_plus, local_auth, permission_handler, url_launcher, file_picker in pubspec + Info.plist/AndroidManifest-Einträge + Web-Fallbacks; je Plattform lauffähig verifizieren. Vorbedingung für 7/11/13/28/29 und Kontakte K3/K6.
3. Design-System-Deltas DS3 (AppErrorState, AppSearchField, AppButton-Semantik-Leitplanke) + Nav-N4 (globale SearchAnchor) bauen und testabsichern, BEVOR Bereichs-Meilensteine sie konsumieren (verhindert neue Klone).
4. Reduce-Motion-API konsolidieren (AppMotion.resolve kanonisch) und in die Review-Checkliste aufnehmen.
5. Verpflichtendes Test-Gate je God-File definieren: Characterization/Golden-Tests via pumpApp vor jedem UI-Umbau; Regel 'kein Refactor + Verhalten im selben Commit' festschreiben.
6. Push-Anforderung 14 eindeutig Anfragen A9 + Querschnitt D3 zuweisen (ein Screen, ein Owner, Pre-Permission-Priming als DoD); andere Bereiche nur verlinken.
7. Konkrete Offline-Verhaltensmatrix (Screen × Aktion × lesbar/schreibbar/gesperrt) als Artefakt erstellen und je Bereich als Checkliste einhängen.
8. Kontakte K4 Master-Detail-Breakpoint auf 840dp korrigieren (Angleich an Responsive-Querschnitt).
9. Rollout strangler-artig je Bereich hinter redesign_v2 ausrollen: Fundament (DS3/N4/Plattform) → Heute → Anfragen → Zeit → Kontakte → Plan → Laden → Profil/Verwaltung; nach jedem Bereich flutter analyze + flutter test grün + Dark/Light + Textscale-Abnahme.
10. 220 Colors.*-Cleanup und VoiceOver/TalkBack-Screenreader-Smoke-Test als eigene, terminierte A11y-Backlog-Posten führen (nicht implizit in Bereichs-Meilensteinen versanden lassen).

---

## 22. Anhang — Methodik & Herkunft

Dieser Plan entstand aus einer deterministischen Multi-Agenten-Analyse (22 Agenten, ~1,86 Mio. Tokens): je Bereich ein **Inventar-Agent** (liest die realen Screens, katalogisiert jeden Unterbereich, belegt Probleme mit Datei:Zeile und ordnet sie einer der 30 Anforderungen zu) → ein **Redesign-Agent** (entwirft das Zielbild gegen alle relevanten Anforderungen). Parallel sieben **Querschnitt-Agenten** (Design-System, Navigation/IA, Responsive, Barrierefreiheit, Sicherheit/Anmeldung, Offline/Performance/Push, Abgleich mit Bestandsplänen). Abschließend ein **adversarialer Kritik-Agent**, der die Anforderungs-×-Bereichs-Matrix streng prüft und Lücken/Widersprüche/Vorbedingungen aufdeckt (Grundlage von Phase 0 und der Risiko-Kapitel). Alle Datei:Zeile-Referenzen stammen aus dem realen Code-Stand vom 2026-07-01.

---

## 23. Anhang — Offline-Verhaltensmatrix (F6)

Konkretes Artefakt zur Kritik-Lücke „Offline-Verhaltensmatrix bleibt abstrakt". **Nach Aktions-Typ** statt je Screen (wartbar + akkurat), gegründet auf die drei Speichermodi und die bewussten Systemgrenzen (Firestore-Offline-Persistence ist aktiv; Cloud-Functions/Compliance/OktoPOS/DATEV brauchen Netz). Jeder Bereichs-Offline-Meilenstein hängt diese Zeilen als Checkliste ein: **⛔-Aktionen offline `onPressed:null` + Tooltip „nur online"**, ✅-Aktionen bleiben bedienbar, ⚠️ zeigen einen Hinweis.

| Aktions-Typ | Beispiel-Screens | hybrid | cloud-only | local | Offline-UX |
|---|---|:--:|:--:|:--:|---|
| **Listen/Detail lesen** | alle Bereiche | ✅ Cache | ✅ Cache | ✅ | Offline-Banner + „zuletzt aktualisiert HH:mm" |
| **userContent schreiben** (Zeiteintrag, Schicht-Direktwrite, Abwesenheit, Vorlage, Kühlschrank-Liste, Warenkorb) | Zeit, Plan, Anfragen, Laden | ✅ lokal gepuffert → Sync | ⚠️ Firestore-Queue (optimistisch) | ✅ | Pending-Kennzeichnung, kein Fehler-Dialog |
| **Compliance-validierte Callable-Speicherung** (`upsertShiftBatch`/`upsertWorkEntry`) | Plan, Zeit | ⚠️ Fallback auf lokalen Direkt-Write (ohne Server-Recheck) | ⛔ rethrow → Fehler | ✅ (kein Callable) | Hinweis „ohne Server-Prüfung gespeichert – wird nachvalidiert" |
| **Cloud-only-Aktionen** (OktoPOS-Sync, Kassen-Push, DATEV-/PDF-Export server-seitig, Compliance-Preview) | Laden, Buchhaltung, Personal | ⛔ | ⛔ | ⛔ | Button deaktiviert + Tooltip „nur online" |
| **Öffentliche Schreibpfade** (Wunsch/Feedback, anonymer Write) | Public-Seiten | ⛔ | ⛔ | ⛔ | Hinweis + „Erneut versuchen" (`AppErrorState`) |
| **Auth/Login, Force-Update-Check, Push-Registrierung, Biometrie-Ersteinrichtung** | Gate, Profil | ⛔ | ⛔ | n/a | Offline-Hinweis; Biometrie-Entsperren selbst geht offline |

> Die ⚠️-Zeile (Compliance-Callable-Fallback) ist die einzige heikle: sie entspricht dem **bestehenden** Hybrid-Verhalten (Direkt-Write umgeht die Server-Compliance) — offline unverändert übernommen, nur mit sichtbarem Hinweis. Nichts an der Validierungslogik wird geändert.