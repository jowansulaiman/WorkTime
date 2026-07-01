# Plan: UI aufräumen & besser verteilen

> Stand 2026-06-30. Grundlage: 7-dimensionale Code-Analyse (Riesen-Screens, Design-System, Theme/Tokens, Responsive, Home/Hubs, Accessibility, Navigation/IA) + adversariale Plan-Kritik. Befunde sind mit `datei:zeile` belegt; alle Zeilenzahlen wurden gegen den aktuellen Stand verifiziert.

## 0. Ausgangslage (kurz)

**Was schon gut ist** (nicht anfassen, nur ausweiten):
- **Token-/Farbdisziplin ist reif**: 0 hartkodierte Status-`Colors.green/red/...`, 0 deprecated `withOpacity`, ~204 `appColors`-Zugriffe, ~647 `textTheme`-Nutzungen, ~218 `context.spacing`-Zugriffe. Die Extensions `AppSpacing/AppRadii/AppMotion/AppElevation/AppIconSizes/AppThemeColors` existieren vollständig.
- **Gute Aufteilungs-Vorbilder existieren bereits**: `lib/screens/shift_planner/` (Cells/Logic/Sheet), `lib/screens/zeitwirtschaft/` (Hub + Sub-Screens), der `part of`-Split der `home_screen`-Familie und v.a. der **Descriptor-getriebene Hub** in `zeitwirtschaft_hub_screen.dart:203-270` (`_HubDestination`-Liste, rollen-gefiltert). Diese Muster werden im Plan konsequent verallgemeinert.
- **V2-Design-System `lib/ui/` (Signal-Teal)** deckt fachlich fast alle Muster ab.

**Die echten Probleme** (= Ziel dieses Plans):
1. **God-Files**: 6 Screens > 2.000 Z (Spitze `shift_planner_screen.dart` 6.352 Z mit einer 2.704-Z-State-Klasse). Reuse-Widgets liegen `file-private` und werden deshalb **kopiert statt geteilt**.
2. **Design-System-Fragmentierung**: nur 15/46 Screens importieren `lib/ui`; 14+ duplizierte `file-private`-Klon-Familien (`_StatusChip` 4×, `_StatusBadge`/`_SectionHeader`/`_InfoChip`/`_ErrorBanner` je 3×). `home_screen` importiert `lib/ui`, nutzt die V2-Stat-/Quick-Action-Komponenten im V1-Pfad aber **0×**.
3. **Magic Numbers trotz Tokens**: ~735 `SizedBox(<zahl>)`, ~167 `BorderRadius.circular(<zahl>)`, ~576 `EdgeInsets(<zahl>)` umgehen die Skala. Zwei häufige Werte (**12** und **6**) haben gar **kein Token** → blockiert die Migration aktiv.
4. **Navigation/IA verteilt schlecht**: dieselben Module sind über **3 konkurrierende Oberflächen** (Laden-Hub, Profil-Hub, Verwaltungs-Drawer) mit **divergierenden Teilmengen** erreichbar (Personal 3×, Warenwirtschaft/Kundenbestellungen je 2-3×); je V1/V2-Flag verschwindet eine ganze Oberfläche. **Konkrete Lücken/Bugs** (Navigations-Analyse): Route `/kundenwuensche` ist definiert + pushbar, aber von **keiner** Oberfläche verlinkt → faktisch unerreichbar; **Scanner** wird über **3 verschiedene Permission-Logiken** gegatet (`isLocationAllowed(scanner)` / `canUseScanner` / `showScanner && canManageInventory`); Zeit-Admin-Funktionen (Lohnlauf, Mitarbeiterabschluss) liegen **3 Klicks tief** nur im Zeit-Hub (nicht im Drawer/Schnellaktionen); Kundenfeedback nur im Shop-Hub.
5. **Raum auf breiten Screens verschenkt**: Datenlisten laufen als schmale Spalte mit leeren Rändern, kein Master-Detail; `personal_screen` hat **gar keinen** `maxWidth`-Cap.
6. **Überladene Startseiten**: 10-13 vertikal gestapelte Blöcke je Rolle, keine klare Primäraktion; `home_dashboards_v2.dart` (844 Z) ist eine **fast byte-gleiche Kopie** der V1-Dashboards.
7. **A11y uneinheitlich**: zahlreiche Tap-Targets < 48 dp, Badge-Zähler für Screenreader stumm, `GestureDetector` ohne Semantik.

## 1. Leitprinzipien

- **Strangler-Fig, klein & mergebar**: jedes Arbeitspaket (AP) ist einzeln reviewbar und einzeln mergebar. Kein Big-Bang.
- **Verhaltenserhaltend zuerst**: Datei-Splits und Komponenten-Swaps dürfen Pixel/Verhalten nicht ändern. Logik-Extraktion (Lohn/Steuer) wird **strikt getrennt** von reinen Splits.
- **Fundament vor Konsument**: erst Token-Lücken + fehlende Komponenten, dann Migration. Komponenten werden **nie auf Vorrat** gebaut — jede neue Komponente hat in ihrem Paket sofort Konsumenten.
- **Eine kanonische Quelle je Konzept**: ein Status-Badge, ein Banner, eine Quick-Action-Karte, **eine** Modul-/Navigations-Descriptor-Liste.
- **`part of` für God-Files** (erhält `file-private`-Sichtbarkeit, ändert keine Aufrufstellen); eigenständige Bibliotheken nur, wo Sub-Komponenten ausschließlich über Konstruktor-Parameter koppeln.
- **CLAUDE.md-Kopplungen sind bindend** (Tab-Reihenfolge = `ShellTab`, Zwei-Serialisierungs-Regel, deutsche Strings, `de_DE`, keine neuen Lint-Rules, kein Mockito).
- **Sicherheitsnetz**: jede Änderung muss `flutter analyze` + `flutter test` grün halten; UI-strukturelle Pakete zusätzlich gegen `test/support/router_harness.dart` (`pumpApp`). Definition of Done je AP = beides grün + visueller Smoke im `APP_DISABLE_AUTH=true`-Modus.

## 2. Phasen-Überblick

| Phase | Ziel | Pakete | Risiko |
|---|---|---|---|
| **0 — Fundament** | Token-Lücken schließen, fehlende V2-Komponenten, geteilte Widgets heben | AP0.1–AP0.3 | niedrig |
| **1 — DS-Adoption** | Klone durch V2-Komponenten ersetzen (mechanische Swaps) | AP1.1–AP1.4 | niedrig |
| **2 — God-File-Split** | Riesen-Screens verhaltenserhaltend in Ordner zerlegen | AP2.1–AP2.7 | niedrig–mittel |
| **3 — Magic-Number-Migration** | SizedBox/EdgeInsets/Radii/TextStyle tokenisieren | AP3.1–AP3.3 | niedrig |
| **4 — Navigation/IA & Raum** | Quick-Wins/Korrekturen, eine Modul-Quelle, Hub-Trennung, Startseiten verdichten, Master-Detail | AP4.0–AP4.5 | niedrig–hoch |
| **5 — Accessibility** | Tap-Targets, Semantics, Kontrast, Ladezustände | AP5.1–AP5.2 | niedrig |

Die Phasen laufen grob sequenziell, aber innerhalb einer Phase sind die Pakete parallelisierbar. **Wichtige paketübergreifende Reihenfolge** ist je AP unter „Abhängigkeiten" notiert.

---

## Phase 0 — Fundament

### AP0.1 — Token-Lücken schließen (Spacing + theme-bewusstes Radii-Mapping)
- **Ziel**: Bevor irgendetwas tokenisiert wird, muss die Skala die real existierenden Werte abbilden — sonst entstehen erneut Magic Numbers oder sichtbare Regressionen.
- **Begründung** (VK-02): Häufigste reale Spacing-Werte sind **12** (213×) und **6** (61×) — für beide gibt es **kein** Token (`AppSpacing`: 2/4/8/16/24/32/48). Auch 10 (49×) und 14 (26×) fehlen.
- **Grounding-Korrektur (kritisch)**: Ein pauschales `12 → radii.sm` ist **falsch**. `AppRadii`-V1-Default hat `xs=8` **und** `sm=8` ([theme_extensions.dart:213-214](lib/theme/theme_extensions.dart#L213-L214)); nur `AppRadii.v2` hat `sm=12` ([:227-235](lib/theme/theme_extensions.dart#L227-L235)). Da `redesign_v2` per Default **aus** ist, würde `12→sm` live auf 8 px auflösen → 4 px-Regression an jeder Ecke. Das Radii-Mapping muss **theme-bewusst** spezifiziert werden (siehe AP3.2).
- **Schritte**:
  1. Entscheidung dokumentieren: **12** und **6** als eigene Spacing-Stufen aufnehmen (z. B. `sm12`/`xxs6`) ODER bewusst auf `sm(8)`/`md(16)` konsolidieren und die wenigen optischen Regressionen abnehmen. **Empfehlung**: neue Zwischenstufen aufnehmen (verhaltenserhaltend, blockiert Migration nicht).
  2. `AppSpacing` + `copyWith` + `lerp` erweitern; V1- und V2-Wert je neuer Stufe identisch setzen (kein Theme-Drift bei Spacing).
  3. **Radii-Mapping-Tabelle festschreiben** (in diesem Plan, als Referenz für AP3.2): pro Magic-Wert den Ziel-Token **getrennt für V1 und V2** angeben; Ausreißer 22/30 (z. B. [shift_planner_screen.dart:1344](lib/screens/shift_planner_screen.dart#L1344)) auf die nächste Token-Stufe normalisieren.
  4. Optionale Insets-Helfer (`context.spacing.allMd`, `insets(h:, v:)`) als Boilerplate-Senker — nur wenn ohne Verhaltensänderung.
- **Scope**: `lib/theme/theme_extensions.dart`.
- **Effort**: S · **Risiko**: niedrig · **Abhängigkeiten**: keine (echter Blocker für Phase 3).

### AP0.2 — Fehlende V2-Komponenten (nur mit sofortigem Konsumenten)
- **Ziel**: Die 4-5 Muster bereitstellen, für die heute kein V2-Baustein existiert und die deshalb dupliziert bleiben.
- **Komponenten** (jede hat in Phase 1 sofort Konsumenten — kein Vorratsbau):
  - `AppListSectionHeader(title, count?, emphasize?)` — Listen-Abschnittstitel mit Count-Pille (3× Klon: [fridge_refill_screen.dart:165](lib/screens/fridge_refill_screen.dart#L165), [team_management_screen.dart:1605](lib/screens/team_management_screen.dart#L1605), [notification_screen.dart:1368](lib/screens/notification_screen.dart#L1368)). **Nicht** mit der seitenweiten `SectionHeader` (Breadcrumb/Back) vermengen.
  - `AppSiteFilterBar(sites, selectedSiteId, onChanged)` + generisch `AppChoiceChipBar<T>` — Standort-/Status-Filterleiste (2×+2× Klon, Label divergiert „Alle Läden" vs „Alle Laden": [customer_order_screen.dart:384](lib/screens/customer_order_screen.dart#L384), [inventory_screen.dart:823](lib/screens/inventory_screen.dart#L823)). In einer Zwei-Läden-App allgegenwärtig.
  - `AppMonthSwitcher(label, onPrevious, onNext, onToday?)` — Monatsnavigation (4× Klon `_MonthPicker`/`_MonthHeader` in Zeitwirtschaft: [lohnlauf:466](lib/screens/zeitwirtschaft/lohnlauf_screen.dart#L466), [mitarbeiterabschluss:531](lib/screens/zeitwirtschaft/mitarbeiterabschluss_screen.dart#L531), [stundenkonto:376](lib/screens/zeitwirtschaft/stundenkonto_screen.dart#L376), [stempel:397](lib/screens/zeitwirtschaft/stempel_screen.dart#L397); zusätzlich `_MonthNavigation` im Hub).
  - `AppDateField(label, value, onChanged, firstDate?, lastDate?, clearable)` — kapselt `de_DE`-`showDatePicker` (2× Klon: [finance_screen.dart:1829](lib/screens/finance_screen.dart#L1829), [personal_screen.dart:3092](lib/screens/personal_screen.dart#L3092); `personal`-Variante = nullable Obermenge).
  - `AppInfoRow(label, value)` — label/value-Stammdatenzeile ([personal_screen.dart:4277](lib/screens/personal_screen.dart#L4277)). Die namensgleiche icon+text-`_InfoRow` ([purchase_order_screens.dart:757](lib/screens/purchase_order_screens.dart#L757)) ist **kein** Duplikat → separat halten (`AppIconTextRow`).
- **Quick-Action-Konsolidierung**: Badge-Fähigkeit von `_QuickActionCard` ([home_screen.dart:1748](lib/screens/home_screen.dart#L1748)) in `AppQuickActionCard` ([app_quick_action.dart:9](lib/ui/app_quick_action.dart#L9)) heben → **eine** Karte für Dashboards UND Hubs (Voraussetzung für AP4.2/AP4.4).
- **Scope**: `lib/ui/` (+ Barrel `lib/ui/ui.dart`).
- **Effort**: M · **Risiko**: niedrig · **Abhängigkeiten**: AP0.1 (Tokens).

### AP0.3 — Geteilte Reuse-Widgets heben (Duplikat-Wurzel kappen)
- **Ziel**: Die Footgun „`file-private` Reuse-Widgets werden kopiert" **vor** den God-File-Splits entschärfen, sonst entsteht in jedem neuen Unterordner eine neue Kopie.
- **Schritte**: generische/duplizierte `file-private`-Widgets als öffentliche Komponenten nach `lib/ui` (bzw. `lib/widgets`) heben und alle Kopien durch Importe ersetzen:
  - `_EmptyState` ([home_screen.dart:2410](lib/screens/home_screen.dart#L2410)) → vorhandenes `AppEmptyState`/`EmptyState`.
  - `_DateField`/`_InlineEmpty`/`_StatsRow` (Klone über `personal`/`finance`/`contacts`) → `AppDateField` (AP0.2) bzw. `EmptyState`; `contacts._StatsRow` (nutzt schon `AppMetricCard`) als Zielmuster, `personal._StatsRow` (Datenklasse) umbenennen (Namenskollision auflösen).
  - `_SectionCard`-Klone ([statistics:230](lib/screens/statistics_screen.dart#L230), [order_analytics:275](lib/screens/order_analytics_screen.dart#L275)) + Legacy `SectionCard` → `AppSectionCard`.
- **Scope**: `lib/ui/`, `lib/widgets/`, betroffene Screens (nur Import-Tausch).
- **Effort**: M · **Risiko**: niedrig · **Abhängigkeiten**: AP0.2.

---

## Phase 1 — Design-System-Adoption (mechanische Swaps)

> Geringes Risiko, hoher Konsistenzgewinn. Reihenfolge: erst die screen-unabhängigen Klone, **home/statistics zuletzt** (koordiniert mit dem home-Split AP2.4, s. Abhängigkeiten).

### AP1.1 — Status-Badges & Banner vereinheitlichen
- `_StatusChip` (4×) + `_StatusBadge` (3×) → `AppStatusBadge(label, tone, icon?, filled)` ([app_status.dart:59](lib/ui/app_status.dart#L59)). Enum→`AppStatusTone`-Mapping bleibt als kleine Helper-Funktion im Screen; rohe `Color`-Durchreichung entfällt.
- `_ErrorBanner` (3×) + `_Banner` (2×) → `AppStatusBanner(icon, message, tone, action?)` ([app_status.dart:119](lib/ui/app_status.dart#L119)). Dismiss = `action`.
- **Scope**: customer_feedback, inventory, customer_wishes, purchase_order, monatsabschluss, mitarbeiterabschluss, auth_screen, customer_order, stundenkonto, zeiterfassung.
- **Effort**: M · **Risiko**: niedrig · **Abhängigkeiten**: AP0.3.

### AP1.2 — Stat-/Quick-Action-/Section-Card-Klone → V2
- `_DashboardMetricCard`/`_StatCard`/`_PlannedActualStatCard`/`_QuickActionListTile`/`_QuickActionCard`/`_ShiftStatusBadge` ([home_screen.dart:2362/2575/2640/1713/1748/3081](lib/screens/home_screen.dart#L2362)) und `statistics._MetricCard` ([:311](lib/screens/statistics_screen.dart#L311)) → `AppMetricCard`/`AppStatCard`/`AppComparisonStatCard`/`AppQuickActionCard`/`AppStatusBadge`.
- **Grounding-Hinweis**: Die V2-Komponenten werden bereits in `home_dashboards_v2.dart` (`part of home_screen.dart`) genutzt ([:75/:119](lib/screens/home_dashboards_v2.dart#L75)). Der „0×"-Befund gilt nur für den **V1-Pfad**. Der Swap muss daher die ganze `home_screen`-Library konsistent treffen, ohne die V2-Konsumenten zu brechen.
- **Scope**: `home_screen`-Familie, `statistics`, `order_analytics`.
- **Effort**: M · **Risiko**: niedrig · **Abhängigkeiten**: AP0.3 **und AP2.4** (home-Split). **Reihenfolge**: home-Familie **zuerst splitten** (AP2.4), dann in den entstandenen kleinen Dateien adoptieren — sonst wird die 3.610-Z-Datei in zwei Phasen doppelt angefasst (Merge-Konflikt-Risiko).

### AP1.3 — Month-Switcher / FilterBar / DateField adoptieren
- Alle 4-5 Monatsnavigations-Klone → `AppMonthSwitcher`; beide `_SiteFilterBar` → `AppSiteFilterBar`; `_FilterBar` → `AppChoiceChipBar`; beide `_DateField` → `AppDateField`.
- **Scope**: zeitwirtschaft/*, inventory, customer_order, audit_log, finance, personal.
- **Effort**: M · **Risiko**: niedrig · **Abhängigkeiten**: AP0.2.

### AP1.4 — Restliche V2-Adoption der Nicht-Importeure
- Migrationsziel = die **echten UI-Screens**, die `lib/ui` noch nicht importieren: audit_log, customer_feedback, customer_wishes, entry_form, fridge_refill, month_report, order_analytics, order_cart, purchase_order_screens, scanner, settings, statistics, force_update. `_InfoChip`-Klone ([customer_wishes:660](lib/screens/customer_wishes_screen.dart#L660), [customer_feedback:563](lib/screens/customer_feedback_screen.dart#L563)) → Legacy `InfoChip`; `scanner._InfoChip` ist semantisch eine Kennzahl-Zelle → eigener Baustein/Umbenennen.
- **Bewusst ausgenommen**: `public/*` (isoliertes `public_ui.dart`, gewollte Sicherheits-/Kostengrenze laut CLAUDE.md), `home_screen_helpers.dart` & `planner_logic.dart` (logik-only).
- **Effort**: L · **Risiko**: niedrig · **Abhängigkeiten**: AP1.1–AP1.3 (Bausteine vorhanden). Kann inkrementell je Screen gemergt werden.

---

## Phase 2 — God-File-Aufteilung (verhaltenserhaltend)

> Muster: pro Riesen-Screen ein Unterordner; `part of` wo `file-private` gekoppelt, eigenständige `showX(...)`-Sheets wo nur Parameter koppeln. **Kein** Logik-/Verhaltens-Change in diesen Paketen.

### AP2.1 — `shift_planner_screen.dart` (6.352 Z) splitten
- `_AdminShiftPlannerBoardState` ist allein **2.704 Z** ([:1221](lib/screens/shift_planner_screen.dart#L1221)). Schnitte (als `part of`, ins bestehende `lib/screens/shift_planner/`):
  - `planner_month_cells.dart` ← Monatszellen ([:3925-4640](lib/screens/shift_planner_screen.dart#L3925)) ~715 Z
  - `planner_week_cards.dart` ← `_ShiftCard`/`_AbsenceCard`/Pills/MiniCalendar ([:4640-5476](lib/screens/shift_planner_screen.dart#L4640)) ~836 Z
  - `planner_editor_notices.dart`, `absence_editor_sheet.dart`, `auto_plan_preview_sheet.dart` ([:5476-6352](lib/screens/shift_planner_screen.dart#L5476))
  - **Grounding-Korrektur**: Filter-Helfer ([:3390-3924](lib/screens/shift_planner_screen.dart#L3390)) nur dann nach `planner_logic.dart` (das ist eine eigenständige `library;`, **kein** `part of`), wenn sie wirklich State-/Typ-frei sind; andernfalls als `part of` in eine `planner_board_filters.dart`. `_buildToolbar`/`_buildFilters` → `_PlannerToolbar`/`_PlannerFilters`-Widgets mit Callbacks.
- **Effort**: L · **Risiko**: mittel · **Abhängigkeiten**: AP0.3.

### AP2.2 — `personal_screen.dart` (5.639 Z) splitten — **reiner Split**
- Neuer Ordner `lib/screens/personal/`: 5 Tabs je Datei, Sheets gebündelt (`payroll_sheets.dart`, `hr_stammakte_sheets.dart`, `urlaub_sheets.dart`), `_EmployeeDetailScreen` eigen.
- **Over-Engineering-Korrektur**: Die Verschiebung der **Lohn-/Steuer-Berechnung** (§3b/§39b/Minijob) aus den Sheets nach `PersonalProvider`/`PayrollCalculator` ist **NICHT** Teil dieses Pakets → eigenes Paket **AP2.2b** (Risiko **hoch**, eigene Charakterisierungs-Tests, berührt ggf. Zwei-Serialisierungs-Regel + `functions/index.js`). AP2.2 bleibt verhaltenserhaltend und sofort mergebar.
- **Effort**: L (AP2.2) / M (AP2.2b) · **Risiko**: niedrig / hoch · **Abhängigkeiten**: AP0.3.

### AP2.3 — `team_management_screen.dart` (4.633 Z) splitten
- Ordner `lib/screens/team/`: 4 Tabs + 8 Editor-Sheets je Datei (als eigenständige `showXEditor(...)`-Bibliotheken, da nur über Parameter gekoppelt). `_SectionHeader` → `AppListSectionHeader` (AP0.2). `_SiteEditorSheet`-Hilfsstrukturen (`_DemandRow`/`_RuleDraft`) mit auslagern.
- **Effort**: L · **Risiko**: mittel · **Abhängigkeiten**: AP0.2, AP0.3.

### AP2.4 — `home_screen`-Familie (~7.300 Z über 4 part-Dateien) weiter splitten
- Split zu ~50 % begonnen. Fortsetzen: `home_shell_nav.dart` (Shell-Navigation/Drawer/BottomNav/`_ShellScope`/`_V2MenuTopBar`/`_RailProfileHeader`), `home_today_widgets.dart` (~30 Präsentations-Widgets [:1675-3610](lib/screens/home_screen.dart#L1675)), `home_team_calendar.dart` (`_TeamCalendarWidget` ~800 Z aus [home_screen_tabs.dart:1103-1893](lib/screens/home_screen_tabs.dart#L1103)). Ziel: `_HomeScreenState` auf reines Shell-Routing reduzieren.
- **Cross-Coupling-Hinweis (AP8/Fehlertext)**: `_formatUserError` lebt in `home_screen_helpers.dart` (`part of home_screen.dart`, [:55](lib/screens/home_screen_helpers.dart#L55)). Eine spätere Zentralisierung nach `lib/core` berührt diese Library → in AP2.5 mitdenken.
- **Effort**: L · **Risiko**: mittel · **Abhängigkeiten**: AP0.3. **Vor** AP1.2 und AP4.x ausführen (alle fassen home an).

### AP2.5 — `inventory_screen.dart` (2.811 Z) splitten
- Ordner `lib/screens/inventory/`: `stock_tab.dart`/`suppliers_tab.dart`/`orders_tab.dart`, `product_dialog.dart`, `supplier_dialog.dart`, `oktopos_settings_sheet.dart` (gehört thematisch nicht in den Bestands-Screen). `_friendlyError`/`_cleanErrorText`/`_formatUserError`-Muster zentral als `formatUserError` nach `lib/core` (berührt AP2.4-Library, s. o.).
- **Effort**: M · **Risiko**: niedrig · **Abhängigkeiten**: AP0.3, AP2.4 (wegen `_formatUserError`).

### AP2.6 — `notification_screen.dart` (2.149 Z) splitten
- Ordner `lib/screens/notification/`: `absence_request_sheet.dart` (öffentlicher `showAbsenceRequestSheet`-Wrapper bleibt stabil — app-weit genutzt!), `inbox_cards.dart`, **`inbox_model.dart`** (Aggregation `_InboxItem`/`_InboxAction` aus heterogenen Quellen als **reine, `BuildContext`-freie Funktion** → unit-testbar).
- **Effort**: M · **Risiko**: niedrig · **Abhängigkeiten**: AP0.2 (`AppListSectionHeader`).

### AP2.7 — `finance` / `contacts` / `scanner` splitten
- `lib/screens/finance/`: Tabs + Editor-Sheets je Datei. `lib/screens/contacts/`: Detail-/Editor-Sheet eigen, Such-/Filter-/Sortier-Logik aus `_ContactsScreenState` in reinen Helper/`ContactProvider`. `lib/screens/scanner/`: **`_ScannerScreenState` ist faktisch die ganze Datei** (~1.513 Z, 17 `_build`-Methoden) → `scanner_inventory_session.dart` + `scanner_order_session.dart` als Widgets mit Callbacks; State behält nur Kamera-Lifecycle/Scan-Dispatch.
- **Effort**: L · **Risiko**: niedrig–mittel · **Abhängigkeiten**: AP0.3. (Drei separat mergebare Sub-Pakete.)

---

## Phase 3 — Magic-Number-Migration (eigene Vollzugspakete)

> **Wichtig**: Diese Migration „passiert nicht von selbst" beim Split — `part of`-Verschieben tokenisiert nichts. Daher **eigene** Pakete, nach Token-Fundament (AP0.1) und nach den Splits (kleinere Dateien = leichter zu migrieren).

### AP3.1 — Spacing/EdgeInsets-Tokenisierung (Hotspots zuerst)
- ~735 `SizedBox` + ~576 `EdgeInsets` → `context.spacing.*`. Hotspots: team_management (123×), shift_planner (95×/69×), home_screen_tabs (68×), home_screen (54×) — decken allein > 300 Stellen. Pro Datei `grep 'SizedBox((height|width): [0-9]'` als Checkpoint; `lib/ui` als Null-Magic-Referenz.
- **Effort**: L · **Risiko**: niedrig · **Abhängigkeiten**: AP0.1, jeweiliger Split.

### AP3.2 — Radii-Tokenisierung (**theme-bewusst**)
- ~167 `BorderRadius.circular` + ~172 `Radius.circular` → `context.radii.*` gemäß der in **AP0.1** festgeschriebenen V1/V2-Tabelle. `999→pill`, Ausreißer 22/30 normalisieren. Schatten-Schwarzwerte ([action_fab.dart:293](lib/widgets/action_fab.dart#L293), [shift_planner_screen.dart:3237](lib/screens/shift_planner_screen.dart#L3237)) → `colorScheme.shadow`/`AppElevation` (VK-06).
- **Effort**: M · **Risiko**: niedrig (mit korrekter Tabelle) · **Abhängigkeiten**: AP0.1.

### AP3.3 — Typografie-Tokenisierung (`textTheme`)
- ~76 inline `TextStyle()` + 22 `fontSize:`-Overrides (10/11/12) → `Theme.of(context).textTheme.<rolle>?.copyWith(...)` (nur Farbe/Gewicht überschreiben). `const TextStyle` ohne Theme-Bezug vermeiden (**CanvasKit-Font-Falle**: unsichtbarer Text auf Web — die App ist Web-Target). Beispiele: [fridge_refill:298](lib/screens/fridge_refill_screen.dart#L298), [order_cart:48](lib/screens/order_cart_screen.dart#L48).
- **Effort**: M · **Risiko**: niedrig · **Abhängigkeiten**: keine (eigenständig). *Eigenes Paket, weil web-relevant und sonst zwischen den Spacing/Radii-Paketen durchfallend.*

---

## Phase 4 — Navigation/IA & Raumverteilung

> Das Kern-Anliegen „besser verteilen". Verhaltensändernd → kleine, einzeln mergebare und **rollbackbare** Pakete (das ursprünglich gebündelte XL-Paket wurde bewusst in AP4.0–AP4.5 zerlegt).

### AP4.0 — Navigations-Quick-Wins & Korrekturen (unabhängig, sofort wertvoll)
- **Ziel**: drei konkrete Befunde der Navigations-Analyse, die unabhängig vom großen Umbau sofort behebbar sind und teils echte Lücken schließen.
  1. **Orphan-Route `/kundenwuensche` anbinden** (HOCH): Route existiert ([shell_tab.dart:55](lib/routing/shell_tab.dart#L55)) und ist pushbar, aber von keiner Oberfläche verlinkt → Kachel im Laden-Hub neben „Kundenbestellungen" ergänzen (`canViewInventory`). Verhindert „vergessenes Feature".
  2. **Scanner-Permission vereinheitlichen** (MITTEL): BottomNav nutzt `isLocationAllowed(scanner)` ([home_screen.dart:490](lib/screens/home_screen.dart#L490)), Drawer `showScanner && canManageInventory` ([app_nav_menu.dart:170](lib/widgets/app_nav_menu.dart#L170)), Permission selbst `canUseScanner` ([route_permissions.dart:59-64](lib/routing/route_permissions.dart#L59)). Alle drei auf **`canUseScanner`** standardisieren (eine Funktion = eine Permission).
  3. **Zeit-Admin-Funktionen sichtbar machen** (HOCH): Lohnlauf/Mitarbeiterabschluss zusätzlich in Drawer-Gruppe „Verwaltung" bzw. Admin-Schnellaktionen aufnehmen (heute nur 3 Klicks tief im Zeit-Hub).
- **Hinweis**: berührt die `home_screen`-Hubs → idealerweise **nach** AP2.4 (sauberere Dateien), aber bei Bedarf eigenständig vorab shippbar. Nach AP4.1 werden 1) und 3) ohnehin durch die Descriptor-Liste getragen — dieses Paket ist die schnelle Zwischenlösung.
- **Effort**: S · **Risiko**: niedrig · **Abhängigkeiten**: keine (optional AP2.4 für Sauberkeit).

### AP4.1 — Eine kanonische Modul-/Bereichs-Descriptor-Liste
- **Problem** (HUB-06): Laden-Hub, Profil-Hub und `AppNavMenu`-Drawer führen **je eine andere Teilmenge** derselben Module; je V1/V2-Flag verschwindet eine ganze Oberfläche ([home_screen.dart:1053-1056](lib/screens/home_screen.dart#L1053), [app_nav_menu.dart:145-180](lib/widgets/app_nav_menu.dart#L145)).
- **Lösung**: **eine** Descriptor-Liste (`{label, icon, route, requiredPermission, domain}`) — exakt nach Vorbild `zeitwirtschaft_hub_screen.dart`'s `_hubDestinations` ([:203-270](lib/screens/zeitwirtschaft/zeitwirtschaft_hub_screen.dart#L203)). `AppNavMenu` **und** die Hubs rendern daraus. Teilmengen können dann nicht mehr divergieren; V1/V2 zeigen denselben Funktionsumfang. Löst strukturell auch die **Mehrfach-Erreichbarkeit** (Personal 3×: [home_screen.dart:2998/2814](lib/screens/home_screen.dart#L2998) + Drawer; Warenwirtschaft/Kundenbestellungen je 2-3×) und das **Permission-Single-Source**-Problem (ein `requiredPermission` je Route statt 3 divergierender Checks).
- **Effort**: M · **Risiko**: mittel · **Abhängigkeiten**: AP2.4 (home gesplittet).

### AP4.2 — Hub-Domänentrennung (Laden = Geschäft, Profil = Persönlich)
- **Problem** (HUB-05): Warenwirtschaft/Personal/Kundenbestellungen liegen in **beiden** Hubs ([home_screen.dart:2782-3014](lib/screens/home_screen.dart#L2782)).
- **Lösung**: Laden-Hub = nur Geschäftsmodule, in **Gruppen** statt flachem 6er-Grid (Lagerwirtschaft & Vertrieb: Warenwirtschaft/Kundenbestellungen/Bestell-Auswertung/Kundenwünsche/Kundenfeedback · Verwaltung: Personal/Änderungsprotokoll). Profil-Hub = nur Persönliches (Profilkarte, Einstellungen, eigene Berichte, Sicherheit/Abmelden) + Link „zum Laden-Bereich". Jede Destination hat genau **einen** Heimat-Hub — fällt nach AP4.1 fast automatisch aus dem `domain`-Feld.
- **V1/V2-Profil-Asymmetrie auflösen**: In V2 ist der Profil-Tab versteckt ([home_screen.dart:1056](lib/screens/home_screen.dart#L1056)), die Migration ins Drawer aber unvollständig (Monatsbericht/Statistiken unter „Auswertungen", Personal unter „Verwaltung" → Struktur zerlegt). Entscheidung treffen: Profil-Tab in V2 **konsistent behalten** (empfohlen, weniger Bruch) **oder** vollständig + sauber strukturiert ins Drawer migrieren — nicht der heutige Hybrid.
- **Effort**: M · **Risiko**: niedrig · **Abhängigkeiten**: AP4.1.

### AP4.3 — V1/V2-Dashboard-Entdopplung (`home_dashboards_v2.dart`)
- **Problem** (HUB-01): 844 Z fast byte-gleiche Spiegel-Klassen; jede Home-Änderung muss doppelt nachgezogen werden.
- **Lösung**: Datenermittlung in einen gemeinsamen Controller/Helper, Section-Reihenfolge als **eine** Liste; V1/V2 unterscheiden sich nur noch über injizierte Präsentations-Wrapper (möglich, seit AP0.2 die Quick-Action-Karte vereinheitlicht hat). **Eigenes Paket** (riskanter Refactor des selten getesteten Flag-Pfads) — nicht mit AP4.4 bündeln.
- **Effort**: L · **Risiko**: hoch · **Abhängigkeiten**: AP0.2, AP1.2, AP2.4.

### AP4.4 — Startseiten verdichten + Auswertungen umverteilen
- **Problem** (HUB-02/03): Employee-Home stapelt 12+ Blöcke, Admin-Home mischt Tagesbetrieb mit 6er-Kennzahlraster + vollem Team-Kalender; Primäraktion unklar, Kennzahlen mehrfach.
- **Lösung**: „eine Bildschirmhöhe = Tagesentscheidung". Employee: Hero mit **DER** Primäraktion (Stempeln/nächste Schicht) + eine Aktionspunkte-Karte + kompakter Wochenstreifen; `_WeeklyProgressWidget`/`_MonthlyShiftSummaryCards`/`Letzte Einträge` in den **Zeit-Tab** verschieben (Auswertung ≠ Tagesentscheidung). Admin: Hero+Metrik+„Heute priorisieren" zu **einer** Kennzahlzeile verdichten (jede Zahl 1×, mit Tap-Sprung); `_TeamCalendarWidget` von Home in den **Plan-/Team-Bereich** verschieben.
- **Cross-Coupling**: `_TeamCalendarWidget` wird in AP2.4 als `part` ausgelagert; hier final verschoben — Reihenfolge AP2.4 → AP4.4 vermeidet Doppelarbeit. Quick-Action-Dopplung Dashboard↔FAB (HUB-04) aus **einer** Descriptor-Liste speisen.
- **Effort**: L · **Risiko**: mittel · **Abhängigkeiten**: AP2.4, AP4.1; **nach** AP4.5 (gemeinsame Grid-Formel) oder koordiniert, da beide die Dashboard-Grids anfassen.

### AP4.5 — Master-Detail & zentrale Raumverteilung auf breiten Screens
- **Problem** (Responsive F1/F2/F4): Datenlisten als schmale Spalte mit leeren Rändern; `personal_screen` ohne `maxWidth`-Cap; Cap pro Screen dupliziert/fehleranfällig.
- **Lösung**:
  1. **Zentraler Shell-Content-Cap**: `Expanded(child: Align(topCenter, ConstrainedBox(maxWidth: kContentMaxWidth, child: shellContent)))` in [home_screen.dart:303](lib/screens/home_screen.dart#L303). **Pflicht-Migrationsschritt**: gleichzeitig die per-Screen-Caps (`contacts:93`, `inventory:253`, `statistics:79`) entfernen — sonst doppelter Cap. `personal_screen` profitiert automatisch (behebt F2).
  2. **Master-Detail** ab `expandedWindow` (≥ ~1000 px): `LayoutBuilder` schaltet zwischen schmal (Liste + Sheet wie heute) und breit (Liste 360-420 px + `VerticalDivider` + `Expanded`-Detail-Pane). **Kontakte zuerst** (geringste Komplexität), dann Inventar.
  3. **Eine** Spaltenformel: `AdaptiveCardGrid` + die zwei parallelen Home-Formeln ([home_screen.dart:2549](lib/screens/home_screen.dart#L2549), home_dashboards_v2) auf eine Funktion in `responsive_layout.dart` vereinheitlichen; `maxColumns` konfigurierbar (Default 5-6 statt hart 4).
- **Effort**: L · **Risiko**: mittel (Punkt 1 global wirksam → Punkt 1 als eigener kleiner Merge vor Punkt 2/3). · **Abhängigkeiten**: AP2.7 (contacts gesplittet) für den Master-Detail-Umbau.

---

## Phase 5 — Accessibility (nach den Splits, re-anchored)

> **Hinweis**: Die `datei:zeile`-Stellen unten liegen teils in Code, den Phase 2 in neue Dateien verschiebt → A11y **nach** dem jeweiligen Split, Stellen dann re-anchoren.

### AP5.1 — Tap-Targets & fehlende Semantik (hoch)
- Tausch-genehmigen/-ablehnen-Buttons ~20 dp ([shift_planner:4737/4767](lib/screens/shift_planner_screen.dart#L4737)) → 48 dp bzw. beschriftete `FilledButton.tonal`/`OutlinedButton` (Primäraktionen).
- Mengen-Stepper ohne Label & < 48 dp ([fridge_refill:288/301](lib/screens/fridge_refill_screen.dart#L288), [scanner:1507/1521](lib/screens/scanner_screen.dart#L1507)) → `tooltip`/`Semantics`, kein `visualDensity.compact`.
- `_navIconButton` ~36 dp ([shift_planner:3823](lib/screens/shift_planner_screen.dart#L3823)) → `IconButton` mit `tooltip`; Mini-Kalender-Tage 28 dp ([:5123](lib/screens/shift_planner_screen.dart#L5123)) → Hitbox ≥ 44-48 dp; Schicht-Popup `more_horiz` 16 dp/zero-constraints ([planner_cells.dart:234](lib/screens/shift_planner/planner_cells.dart#L234)) → Default-Constraints + `tooltip`.
- **Effort**: M · **Risiko**: niedrig · **Abhängigkeiten**: AP2.1, AP2.7.

### AP5.2 — Semantik, Kontrast, Konsistenz, Ladezustände (mittel/niedrig)
- Badge-Zähler in `Semantics`-Label aufnehmen („Anfragen, 3 ungelesen") in Nav-Rail & BottomNav ([app_nav_rail.dart:148/187](lib/widgets/app_nav_rail.dart#L148), [home_screen.dart:982](lib/screens/home_screen.dart#L982)).
- Close-`IconButton`s einheitlich `tooltip: 'Schließen'` (mal mit, mal ohne) → gemeinsames `CloseButton`-Widget.
- `GestureDetector` → `InkWell`/`SegmentedButton` + `Semantics` (Theme-Auswahl [settings:693](lib/screens/settings_screen.dart#L693), Farbpicker [shift_editor_sheet:1672](lib/screens/shift_planner/shift_editor_sheet.dart#L1672)).
- Kontrast: Text auf getöntem Container → gepaarte `onXContainer`-Rollen statt Vollton-auf-Selbst-Tint ([planner_cells.dart:222](lib/screens/shift_planner/planner_cells.dart#L222)); Badge `fontSize` ≥ 11-12.
- Passwort-Sichtbarkeits-Toggle (auth_screen[s]); gemeinsames `LoadingState`-Widget mit `semanticsLabel` für ~56 ad-hoc-Spinner.
- **Effort**: M · **Risiko**: niedrig · **Abhängigkeiten**: AP0.2/AP0.3 (gemeinsame Widgets).

---

## 3. Risiken & Gegenmaßnahmen

- **Verhaltens-Drift bei Splits**: `part of` erhält Sichtbarkeit; jede Split-PR muss `flutter analyze`+`flutter test`+`router_harness` grün halten und im `APP_DISABLE_AUTH`-Modus visuell identisch sein. Keine Logikänderung im Split-Paket.
- **Radii-Regression V1/V2**: gelöst durch theme-bewusste Mapping-Tabelle (AP0.1) — **nicht** flach `12→sm`.
- **Doppelter Layout-Cap** (AP4.5): per-Screen-Caps zwingend im selben Merge entfernen.
- **Flag-Pfad-Refactor** (AP4.3): höchstes Einzelrisiko; isoliertes Paket, beide Flag-Zustände manuell durchklicken.
- **Lohn-/Steuer-Logik** (AP2.2b): getrennt, mit eigener Charakterisierung, blockiert den reinen `personal`-Split nicht.

## 4. Bewusst außerhalb des Scope

- Öffentliche Seiten `public/*` (isoliert, eigenes Design — gewollte Grenze).
- i18n/Lokalisierung (App ist hart `de_DE`, keine ARB).
- Neue Lint-Rules, Mockito, State-Management-Wechsel (bleibt `provider`).
- Fachliche Feature-Änderungen (Compliance-Schwellen, Datenmodelle) — dieser Plan ist rein UI-/Struktur-getrieben.

## 5. Empfohlener Startpunkt

**AP0.1 → AP0.2 → AP0.3** (Fundament, ~1 Iteration, niedriges Risiko) schaffen die Voraussetzung für alles Weitere. Danach liefert **AP2.4 (home-Split) + AP4.1 (eine Modul-Quelle) + AP4.2 (Hub-Trennung)** den sichtbarsten „besser verteilt"-Effekt bei überschaubarem Risiko.

**Sofort-Option ohne Vorarbeit**: **AP4.0** (Orphan-Route `/kundenwuensche` anbinden, Scanner-Permission vereinheitlichen, Zeit-Admin sichtbar machen) ist unabhängig, billig (S) und schließt eine echte Feature-Lücke — guter erster sichtbarer Win, falls vor dem Fundament gewünscht.
