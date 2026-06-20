# Komplett-Redesign WorkTime — „Signal Teal" (M3 Expressive)

## Context

Das aktuelle Design ist ein konservatives Navy-Theme (Seed `#244A66`, alles flach, runde Cards) — funktional, aber visuell müde. Ziel: ein **komplett neues, frisches Erscheinungsbild** über die **gesamte App** (13 Screens, ~27k Zeilen UI), **ohne eine einzige Funktion zu verlieren**. Die App bleibt eine Flutter-Codebasis für Android/iOS/Web/Desktop.

**Vom Nutzer festgelegt:**
- **Stil:** Modernes Material 3 (Expressive) — Flutter-nativ, kräftigere Farben, größere Radien, mehr Weißraum, ausdrucksstarke Buttons.
- **Leitfarbe:** **Signal Teal `#0E7C7B`** (hell) / `#5FD4CE` (dunkel) — ersetzt das Navy. Logo & Status-Farben bleiben.
- **Geräte-Fokus:** Ausgewogen — BottomNav am Handy, NavigationRail ab 600 dp, erweiterte Labels ab 840 dp.
- **Rollout:** Inkrementell hinter Feature-Flag (`redesign_v2`), Screen-für-Screen, jederzeit umschaltbar — passt zur bestehenden „Strangler Schritt N"-Commit-Praxis.

Dieser Plan basiert auf einer vollständigen read-only-Inventarisierung (alle Design-Tokens, der Shell mit 70+ file-private Widgets, jedem Screen, einem 54-Punkte-Funktionsvertrag) plus den `claude-skills/` (UX/UI, Mobile, Performance, Refactoring). Eine adversariale Vollständigkeitsprüfung hat die kritischen Widersprüche/Lücken aufgedeckt, die unten bereits aufgelöst sind.

---

## Leitplanken (NICHT verhandelbar)

1. **Nur Optik/Layout ändern.** Provider, Services, Models, Firestore, Cloud Functions, Compliance-Logik, Serialisierung bleiben verhaltensidentisch. Der Diff jedes Schritts ist **UI-Baum + Theme**, sonst nichts.
2. **Architektur bleibt:** `provider ^6.1.1` (KEIN Riverpod/Bloc), **index-basierte Shell** in `home_screen.dart` (KEIN go_router), Detail-Screens via `Navigator.push`. → Die `go_router`/Riverpod/Bloc/Result-Type-Regeln aus den 98 UX-Skill-Regeln sind **hier ungültig** (sie widersprechen `CLAUDE.md`).
3. **Alles Deutsch, Locale hart `de_DE`.** Neue Strings = deutsche Literale; jedes `DateFormat` bekommt `'de_DE'`. Bestehende „spelled-out"-Umlaut-Strings (`Loeschen`, `uebernehmen`) **nicht** umschreiben (werden ggf. in Tests/PDF gematcht). `'h a', 'en_US'` in Planner-Schichtkarten ist **Absicht**, kein Bug.
4. **Status-Farben (success/warning/info) kommen aus `AppThemeColors`** via `Theme.of(context).appColors` — **nie hardcoden**. In V2 bleiben die success/warning/info-Basiswerte **unverändert** (Ampel, Coverage-Card, Planner-Palette sind auf exakt diese Hues getunt).
5. **Pro Strangler-Schritt:** `flutter analyze` sauber + `flutter test` grün, eigener flag-gegateter Commit, alter Pfad bleibt erreichbar bis Schritt 100 % stabil. **Refactor und Verhaltensänderung nie im selben Commit.**

---

## Das neue Design-System (V2-Tokens)

Additiv neben den V1-Tokens, ausgewählt per `redesign_v2`. Dateien: `lib/theme/app_theme.dart`, `lib/theme/theme_extensions.dart`.

### Farbe — ColorScheme (Auszug; volle Tabellen in der Token-Spec)
`ColorScheme.fromSeed(seedColor: 0xFF0E7C7B, dynamicSchemeVariant: DynamicSchemeVariant.vibrant)`, danach Rollen wie bisher hand-tunen. Hell & Dunkel **unabhängig** definiert (keine Inversion).

| Rolle | Hell | Dunkel |
|---|---|---|
| primary | `#0E7C7B` | `#5FD4CE` |
| onPrimary | `#FFFFFF` | `#003735` |
| primaryContainer | `#9CF0E9` | `#00504D` |
| secondary | `#3F7C8E` (Logo-Cyan, bleibt) | `#A8CDD9` |
| **tertiary (NEU)** | `#7A5BD6` Violett | `#C9BCFF` |
| surface | `#F6FBFA` (near-white, 2 % Teal) | `#0E1514` |
| surfaceContainerLow…Highest | nahezu neutral, Hauch Teal | dito dunkel |
| outline/outlineVariant | `#6F7977` / `#BEC9C7` (Border @0.7) | `#889391` / `#3F4948` |

- **Status-Farben `AppThemeColors` (12 Felder): unverändert** gegenüber V1 (success `#187A58`, warning `#A76E00`, info `#2D6CDF` + Container + Dark). Feldnamen/Kontrakt sind unantastbar (97 Consumer).
- **surfaceTint überall transparent** (kein Tonal-Tint) — die flache, ruhige Canvas bleibt; Expressive lebt von **kräftigen Akzenten + Containern**, nicht von Schatten.

### Form, Typo, Bewegung, Abstände (Expressive)
Neue Token-Extensions additiv in `theme_extensions.dart`; bestehende Felder/Werte bleiben (0 Regression für die 1–2 aktuellen Consumer).

- **Radius (`AppRadii` V2):** xs8 · sm12 · md16 (Buttons/Inputs/ListTile/Segmented) · lg20 (Nav-Indicator) · xl28 (Cards/Dialoge) · **2xl36 (NEU: Hero, Extended-FAB, prominente Container)** · pill999. Primär-CTAs dürfen `StadiumBorder` (Pill) sein.
- **Typo:** `NotoSans` bleibt; Gewichtskontrast hoch (displaySmall/headlineMedium → w800, titleMedium → w700). **Tabular figures** als opt-in-Helper (`FontFeature.tabularFigures()`) für Zahlen-Rollen (Uhr, Stunden, Plan/Ist) — nicht global, sonst bricht Fließtext.
- **Bewegung (`AppMotion`, NEU):** durationShort150 / Medium300 / Long450 / ExtraLong600; `easeInOutCubicEmphasized` Standard, Emphasized-Enter/Accel-Exit, Spring (`easeOutBack`) für FAB/Chips/Auswahl. **`MediaQuery.disableAnimations` respektieren** → alles auf `Duration.zero`.
- **Elevation (`AppElevation`, NEU):** flat0 (Default, unverändert) · raised1 (Hover) · floating3 (FAB/aktives Sheet) · overlay6 (Menüs). **Nur sparsam, nie auf Grid/Planner.** Dividers 0.8 dp + Border-System bleiben primäres Trennmittel.
- **Spacing (`AppSpacing` V2):** + `xxs2`, + `xxl48` (Desktop-Weißraum). 4/8-Rhythmus bleibt.
- **Icon-Größen (`AppIconSizes`, NEU):** sm18 · md24 · lg28 · xl32 · hero40 (ersetzt hartkodierte `size:` in 70+ Widgets).
- **Touch-Targets:** Button-`minimumSize` 64×52, Icon/Text-Button 48 (Expressive + „Handy first-class").

### Integration (strangler-sicher, additiv)
- `app_theme.dart`: `AppTheme.light/dark` **byte-identisch behalten**; `lightV2`/`darkV2` + Selektor `AppTheme.resolveLight/Dark({required bool useV2})` ergänzen; `_buildThemeV2`/`_buildColorSchemeV2` spiegeln die bestehende Struktur. **Beide Theme-Varianten MÜSSEN `AppThemeColors` in `extensions:` liefern** (sonst null-crash bei `appColors`-Consumern).
- `theme_extensions.dart`: neue Felder/Consts **additiv** mit Defaults (`AppThemeColors.lightV2/darkV2` als neue Consts, alte unangetastet); `copyWith`/`lerp` erweitern; `AppMotion`/`AppElevation`/`AppIconSizes` + `context.motion/elevation/iconSizes` ergänzen.

---

## Gemeinsame Komponenten-Bibliothek (`lib/ui/`)

Neuer Namespace `lib/ui/` (Barrel `lib/ui/ui.dart`), getrennt vom Legacy-`lib/widgets/`. **Saubere bestehende Widgets bleiben** und werden nur re-exportiert: `EmptyState`, `InfoChip`, `SectionCard`, `SectionHeader`, Breadcrumbs, `AppLogo`, `MobileBreakpoints`/`AdaptiveCardGrid`. Alle neuen Komponenten konsumieren **nur Tokens** (kein Hex/keine festen dp).

| Neu | Ersetzt/Vereinheitlicht | Art |
|---|---|---|
| `AppCard` | rohes `Card(Padding(16))` überall | neues Primitiv |
| `AppSectionCard` | `SectionCard` + Duplikat `statistics._SectionCard:214` | Restyle (DEDUP) |
| `AppMetricCard` / `AppStatCard` / `AppComparisonStatCard` | `_DashboardMetricCard:5632` / `_StatCard:5846` / `_PlannedActualStatCard:5911` | Restyle (Mathe 1:1 erhalten) |
| `AppHeroCard` | gemeinsame Hülle für `_EmployeeHeroCard:1376` + `_PlannerHeroCard:1620` | neue Hülle |
| `AppQuickActionCard` / `AppQuickActionTile` | `_QuickActionCard:1244` / `_QuickActionListTile:1209` | Restyle |
| `AppEmptyState` (Alias auf `EmptyState`) | `_EmptyState:5681`, `statistics._EmptyState`, `_PlannerEmptyState:4668`, `_PlannerEmptyBoardState:4508` | DEDUP (4 Klone löschen) |
| `AppStatusBadge` (+ `AppStatusTone`) | `_ShiftStatusBadge:6251`, `_LocationStatusBadge:5515` | vereinheitlichen |
| `AppStatusBanner` | Render-Hälfte von `_ShellStatusBanner:1071` (Provider-Watch bleibt in home) | präsentationaler Extract |
| `AppFilterChip` / `AppSegmented<T>` | Planner-Filter-Pills (~2294–2901) + Day/Week/Month-`SegmentedButton` | dünne Wrapper |
| `AppBottomSheetScaffold` | Sheet-Chrome: `_PunchClockSheet`, `_ShiftEditorSheet`, `_AbsenceEditorSheet`, `showAbsenceRequestSheet`, Team-Editor-Sheets | Chrome vereinheitlichen |
| `AppFormField` / `AppConfirmDialog` | `TextFormField`+`InputDecoration`-Blöcke / inline `showDialog(AlertDialog)`-Confirms | dünne Wrapper |

**Planner-Ausnahme:** Die Leaf-Cells in `shift_planner/planner_cells.dart` übernehmen **NICHT** `AppCard`/`AppStatusBadge`, falls diese Gradient/Schatten/Animation einführen — sie bleiben bespoke (Dichte & Performance). `AppStatusBadge` absorbiert **nicht** `_PlannerAbsencePill`/Schichtkarten-Badges.

---

## Redesign pro Screen (Richtung; Funktion bleibt identisch)

Jeder Screen bekommt eine `…V2`-Variante, an seinem einzigen Einstiegspunkt per Flag umgeschaltet. Optik = M3 Expressive (neue Tokens + `lib/ui/`-Komponenten); alle Interaktionen, Permission-Gates, Provider-Aufrufe, Validierungen **byte-gleich**.

- **App-Shell + Home (`home_screen.dart`):** adaptive Navigation (BottomNav≤5 ↔ Rail ab 600/840), Rail-Leading/Profil/Logout, FAB-Kontextwechsel, `_LazyDestinationStack`, Back-History, **Ctrl+1..9 bleiben**. Frische Employee-/Admin-Dashboards (Hero-, Metric-, QuickAction-Karten), Week-Strip, `_ShellStatusBanner` (Local-/Sync-Status mit „Jetzt synchronisieren"). Clock-In/Out + Punch-Clock-Sheets neu gestaltet — **Timer-Intervalle (30 s Duration-Tick, 60 s Availability-Poll) NICHT anfassen**.
- **Schichtplaner (`shift_planner_screen.dart` + `planner_cells.dart`) — ZULETZT, höchstes Risiko:** Tag/Woche/Monat-Board, Toolbar/Filter/Monat-Sidebar, Reihen-/Tageszellen, Schichtkarten + Farb-Helper, Abwesenheits-Pills, Editor-Sheet (Multi-Assignee, **Recurrence none/daily/weekly/biweekly/monthly**, Templates, **Compliance-/Verfügbarkeits-Overlay**), Publish (3 Modi), Woche kopieren, PDF/CSV. Optik modernisieren, **Bucketing (`_groupShiftsByRow/ByDay`, O(1)-Lookups), `RepaintBoundary`, `_sideWidth`/`_dayWidth`, keine Per-Cell-Schatten/Animation** beibehalten. Schichtfarben (`_resolveShiftColor`/`_plannerAvatarColor`) re-tinten automatisch über den neuen Seed — mit Goldens absichern.
- **Team-Verwaltung (`team_management_screen.dart`):** Admin-Gate (exakter dt. String) bleibt; 4 Tabs (Mitarbeiter/Standorte/Teams&Qualifikationen/Regelwerk) + alle Editor-Sheets (Invite, Member inkl. Vertrag + **Primär-Standort `_clockSiteForUser`**, Site, Qualifikation, RuleSet, Travel-Time, Team, **9 enforce + 9 warn Compliance-Toggles**) neu gestaltet via `AppSectionCard`/`AppFormField`/`AppSegmented`. Eine evtl. Rail-artige Tab-Liste ≥840 dp ist **rein visuell** (über `TabController.index`), registriert **keine** Shortcuts.
- **Einstellungen (`settings_screen.dart`):** Profil, Arbeitszeit, Urlaubs-Quota-Card (Fortschrittsbalken), Auto-Pause, **Arbeitszeit-Vorlagen-CRUD**, Lohn+Währung, **Storage-Modus** (Hybrid/Cloud/Local), Theme-Wahl. Storage-Umschaltung: exakte Branch-Reihenfolge + alle 4 SnackBars + authDisabled/Noop **erhalten**; `AppSegmented` **muss** während `_changingStorage` disabled bleiben (keine überlappende Migration).
- **Zeit & Reports:** `entry_form_screen.dart` (Date/Time-Picker, Shift-Coverage-Card, **Overtime-Approval-Dialog**, Template-Picker, **Korrekturgrund + `correctedAt`/`correctedByUid` + Auto-Pause-Recalc**), `month_report_screen.dart` (Monatsnav, Mitarbeiter-Wahl, Site-Filter, Stats-Grid, **PDF-Export**), `statistics_screen.dart` (Summary-Cards, **Overtime-Ampel** über `appColors`, fl_chart Tages-/Jahres-Balken neu eingefärbt + tabular figures + Tooltips/Pattern, **CSV-Export**). Formulare bekommen echte Labels/Error-Texte (Skill-Regeln 59–68).
- **Inventar/Bestellungen (`inventory_screen.dart`, `purchase_order_screens.dart`):** 3 Tabs (Bestand/Lieferanten/Bestellungen), Suche, Multi-FAB, Produkt-/Lieferanten-Dialoge, **Stock-Delta-Dialog inkl. Typ adjustment/loss/gain + Grund + `StockMovement`-Logging**, Stocktake, Low-Stock-Banner; PO-Editor (Stepper) + Detail (Wareneingang-FAB, Bestelltext kopieren, Status).
- **Auth (`auth_screen.dart`) + Force-Update:** frischer M3-Expressive-Login (Gradient-Zwei-Panel, Google-Sign-In, E-Mail-Login, Invite-Aktivierung, Demo-Konten, Error-Banner, `FirebaseSetupScreen`, `AccessBlockedScreen`). **`AppLogo`-Policy global: Light-Mode-Logo bleibt Markenzeichen (kein Remap auf Teal)**, Dark-Mode-Remap bleibt — das Logo-Blau/Orange ist bewusster Marken-Akzent neben Teal.

---

## Funktions-Erhalt — explizit „nicht modernisieren" (aus der Critique)

Diese hatten in den Specs keinen klaren Eigentümer → je ein Erhalt-Test + Notiz:
1. **Zeit-Korrektur:** `_ClockCorrectionDialog`/`correctClockEntry`, `correctedAt`/`correctedByUid`, Auto-Pause-Recalc.
2. **Clock-Timer:** 30 s Duration-Tick + 60 s Availability-Poll unverändert.
3. **Recurrence-Enum** in **Schicht- UND Abwesenheits-Editor** (none/daily/weekly/biweekly/monthly).
4. **Stock-Adjust-Typ** (adjustment/loss/gain) + Grund + `StockMovement`.
5. **Primär-Standort-für-Clock-in** (`_clockSiteForUser`) beim Restyle der Site-Chips.
6. **Alle Lösch-Pfade** über `AppConfirmDialog` müssen exakt die bisherige Provider-Methode rufen (entry/shift/series/invite/site/template/PO/qualification/team/travel-rule).
7. **Export-Eingaben unverändert:** gleicher Schicht-/Eintrags-Satz an `ExportService.*` bei gleichem Filterzustand (Filter-Chip-Restyle darf keine Zeilen droppen). CSV ohne BOM, `;`-Delimiter, exakte Header.
8. **Force-Update #48:** Vertrag nennt „App-Store-Redirect", Screen hat „kein Button by design". **Vor Umsetzung klären**, ob der Redirect in `main.dart` lebt — falls nicht vorhanden, **nicht** neu erfinden, Vertragsklausel streichen.
9. **Demo/Offline:** `redesign_v2` ist ohne Firestore unlesbar → in `APP_DISABLE_AUTH`/local-Mode rendert deterministisch **V1**, außer `--dart-define=APP_REDESIGN_V2=true`.

---

## Rollout (Strangler) & Feature-Flag

**Flag:** `redesign_v2` über bestehenden `FeatureFlagProvider.isEnabled('redesign_v2', fallback:false)` (server/org-gesteuert, sofort umschaltbar = Rollback). Neuer kleiner Resolver `lib/core/redesign_flags.dart` legt einen Dev-Override darüber (`bool.fromEnvironment('APP_REDESIGN_V2')`), damit es offline/`APP_DISABLE_AUTH` testbar ist; Dart-Define in `app_config.dart` ergänzen.

**Zwei Lese-Stellen:** (1) Theme-Wahl in `main.dart` (`Consumer2<ThemeProvider,FeatureFlagProvider>` → `resolveLight/Dark(useV2:…)`; Bootstrap-Shell auf V1 pinnen gegen Flash). (2) Pro Screen ein dünner Chooser am Einstiegspunkt (`RedesignFlags.isOnRead(context) ? XV2() : X()`).

**Geordnete Schritte (jeder = grüner, flag-gegateter Commit „… (redesign-v2, Strangler Schritt N)"):**
1. **Tokens + `lib/ui/`-Komponenten** (unsichtbar, nichts liest Flag).
2. **Theme-Flip** (erste sichtbare Stufe): Flag in Theme-Wahl; vorher Hardcode-Audit (`Color(0x…)`/`Colors.*`/`BorderRadius.circular(n)` in Screens, `_MapLikePainter`, Planner-Shadow-Alpha, `onPrimary`-Kontrast auf CustomPaint) → auf Tokens ziehen.
3. **auth_screen** (isoliert, pre-login).
4. **Shell + Home-Dashboards** (Gate-Reihenfolge `_buildDestinations` erhalten — Restyle und Duplikat-Löschung in **getrennten** Schritten).
5. **settings_screen** (+ optionaler Debug-Runtime-Toggle).
6. **notification_screen** (hat schon Widget-Test-Abdeckung).
7. **month_report + statistics** (read-mostly; fl_chart nur restylen).
8. **team_management** (4 Tabs + Sheets).
9. **inventory + purchase_orders**.
10. **entry_form** (formularlastig, compliance-nah).
11. **shift_planner ZULETZT** — ggf. Sub-Schritte (Toolbar/Filter → Woche/Tag → Monat → Editor-Sheets).
12. **Cleanup** (erst wenn `redesign_v2` 100 % stabil): alte Screens/Widgets, V1-Token-Bundle, Chooser-Branches, Flag löschen; `lightV2/darkV2` → `light/dark` promoten; V2-Goldens werden kanonisch.

---

## Tests & Verifikation (offline, keine CI)

Werkzeuge wie im Repo: `flutter_test`, `fake_cloud_firestore`, `SharedPreferences.setMockInitialValues({})` + `DatabaseService.resetCachedPrefs()`, `initializeDateFormatting('de_DE')`. Goldens: eingebautes `matchesGoldenFile` (keine neue Dependency).

- **Charakterisierungs-Tests zuerst gegen den ALTEN Screen** (Verhalten einfrieren), dann **denselben Test gegen V2** für Verhaltens-Parität: dt. Strings, Permission-Gating, gleiche Provider-Aufrufe/Sheets, identische Filter-/Sortier-/Bucketing-Sätze, gleiche Compliance-Badges, Farben aus `appColors`.
- **Dual-Theme-Goldens** (lightV2 + darkV2; V1 bis Cleanup) je migriertem Screen, je 1× Phone-Breite und 1× ≥600 dp Rail-Breite.
- **Gezielte Pflicht-Tests (aus Critique):** Export-Eingabe-Parität (Schicht/Monat); CSV-Byte-Test (`Datum;Start;Ende;Pause (min);Stunden;Notiz`, kein BOM, `toStringAsFixed(2)`, Dateiname `arbeitszeit-yyyy-MM.csv`); Per-Rollen-Gating (canViewSchedule/canViewTimeTracking/canManageShifts; 5 Notification-Action-Branches; Admin-Gate-String; canViewInventory/canManageInventory); `appColors`-non-null in `lightV2/darkV2`; de_DE-Test (jedes neue `DateFormat` `'de_DE'`; spelled-out-Umlaute nicht umgeschrieben; `'h a','en_US'` erhalten); Storage „überlappende Migration blockiert".
- **Manuell:** `flutter run --dart-define=APP_DISABLE_AUTH=true --dart-define=APP_REDESIGN_V2=true` → Demo-Admin + Demo-Employee, Checkliste: dt./de_DE, rollen-korrekte Tabs, Kernflows identisch, Status-Farben hell/dunkel, Resize über 600/840 dp. Dann `APP_REDESIGN_V2=false` zum A/B + Rollback-Check.
- **Gate je Schritt:** `flutter analyze` (0) → `flutter test` (grün) → Commit.

---

## Kritische Dateien
- `lib/theme/app_theme.dart` · `lib/theme/theme_extensions.dart` — Tokens + `lightV2/darkV2`.
- `lib/main.dart` — Theme-Wahl-Seam (Consumer2).
- `lib/core/redesign_flags.dart` (neu) · `lib/core/app_config.dart` — Flag-Resolver + Dart-Define.
- `lib/providers/feature_flag_provider.dart` — Flag-Quelle (`redesign_v2`).
- `lib/ui/` (neu, Barrel `ui.dart`) — gemeinsame Komponenten; `lib/widgets/` saubere Widgets re-exportiert.
- Screens (je `…V2`-Variante): `home_screen.dart`, `shift_planner_screen.dart` (+ `shift_planner/planner_cells.dart`), `team_management_screen.dart`, `settings_screen.dart`, `entry_form_screen.dart`, `month_report_screen.dart`, `statistics_screen.dart`, `inventory_screen.dart`, `purchase_order_screens.dart`, `notification_screen.dart`, `auth_screen.dart`.

## Offen / vor Start klären
- **Force-Update-Redirect (#48):** Ort des Redirects bestätigen oder Vertragsklausel streichen (keine neue Funktion erfinden).
- **Logo-Policy bestätigt:** Light-Mode-Logo bleibt unverändert (kein Teal-Remap).
