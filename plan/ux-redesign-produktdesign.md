# WorkTime — Professionelles UI/UX-Redesign (Produkt-Design-Perspektive)

> Stand 2026-07-03. Dieser Plan schärft die **Produkt-Design-Perspektive** des Redesigns: Personas & Jobs-to-be-Done, konkrete Ist-Probleme mit `Datei:Zeile`-Beleg, intelligente UX-Funktionen aus bereits vorhandenen Daten und eine Modul-für-Modul-Vorher/Nachher-Betrachtung.
>
> **Verhältnis zu [plan/redesign-gesamt.md](redesign-gesamt.md):** komplementär, kein Duplikat. Der große Vorgänger-Plan organisiert das **Fundament** (Tokens, Offline-Banner, Dynamic Type, Kontrast-Gate) und die Tab-Rollouts entlang von „30 UX-Anforderungen"; Phase 0 ist dort bereits gebaut. Dieser Plan liefert die **produkt- und kontextgetriebene Priorisierung** darüber: welche Aktion für welche Persona in der Ladenrealität zuerst kommt, welche KPIs eine Entscheidung auslösen und wie die Gott-Screens entlang der Navigation geschnitten werden. Wo dieser Plan Fundament-Themen berührt (Offline, Skeleton, WCAG), verweist er auf den Vorgänger statt sie neu zu definieren.
>
> **Harte Leitplanken (nicht verhandelbar):** nur Optik/Layout/IA/UX — **keine** Änderung an Providern/Services/Models/Firestore/Functions/Compliance/Serialisierung. Feature-Anteile (Biometrie, Konnektivität, Permissions, Offline-Puffer) laufen als **getrennte** Pakete und sind hier nur UX-seitig markiert. Deutsch, `de_DE`. Status-Farben ausschließlich `Theme.of(context).appColors`. Tokens statt Magic-Numbers. **Farbwelt = Strichmännchen-Marken-Palette** (`StrichTokens`, 1:1 aus der Ladenseite; ersetzt Signal-Teal app-weit) — weiterhin nur über Tokens/`appColors`, Dark/Light + WCAG-AA neu verifiziert. Sieben Shell-Tabs unverändert. Strangler-Umbau hinter `redesign_v2`. Definition of Done je Schritt: `flutter analyze` clean + `flutter test` grün (offline, `APP_DISABLE_AUTH=true`). Keine neuen Lint-Rules, kein Mockito.

---

## 1. Zusammenfassung

**Ziel.** Aus einer feature-vollständigen, aber optisch/interaktiv uneinheitlichen Arbeitssoftware ein Produkt machen, das im **aktiven Ladenbetrieb** — zwischen Kundschaft, an der Kasse, einhändig am Handy, am geteilten Tablet — in Sekunden bedienbar ist. Nicht Marketing-Optik, sondern produktive Werkzeug-Ergonomie.

**Ausgangslage.** Das Design-System V2 (`redesign_v2`) ist Default-live: Tokens als `ThemeExtension` in [theme_extensions.dart](../lib/theme/theme_extensions.dart), Komponentenbibliothek [lib/ui/](../lib/ui/ui.dart) — aktuell noch mit Teal-Seed `#0E7C7B`/`#5FD4CE`. **Verbindliche Richtungsentscheidung (03.07.):** Die App-Farbwelt wird 1:1 auf die **Strichmännchen-Ladenseiten-Palette** umgestellt (navy `#061B36` / gold `#CAA65A` / paper `#F4EFE4` / gelber CTA `#F0C738` / rose `#B8435A`); die belegten Tokens liegen fertig in [strichmaennchen_tokens.dart](../lib/theme/strichmaennchen_tokens.dart) (`StrichTokens`), sind aber **noch nicht ins Theme verdrahtet** — die App rendert real weiter Teal. Der Rebrand ist damit die **erste tragende Maßnahme** dieses Plans (§4.2, §4.10, Roadmap Phase 0). Das Inventar über elf Bereiche belegt zudem drei systematische Schwächen:

1. **Parallele Alt-Systeme.** V1-Branches (`home_screen_tabs.dart`) mit hardkodierten Abständen/Farben stehen neben token-konformen V2-Widgets im selben Build-Tree.
2. **~30 duplizierte file-private Klon-Widgets** (`_StatusChip`, `_StatCard`, `_MonthPicker`, `_ErrorBanner`, `_EmptyState`, `_QuickActionCard` …) statt der vorhandenen `lib/ui`-Komponenten.
3. **Kontext-blinde Interaktion.** Kern-Aktionen versteckt hinter Scroll (Einstempeln), horizontale Tabellen auf Handy, Rohfehler-SnackBars, org-weite Aggregation über zwei Läden, stille `take(n)`-Kürzungen.

**Kernstrategie.** Sieben kontextuelle Anforderungen (K1–K7, Abschnitt 2.1) bilden das Bewertungsraster. Darauf: (a) **Primäraktion zuerst** je Rolle (Heute-Dashboard 11→6 Blöcke), (b) **kanonische Muster** (Tabelle→Karte < 840 dp, Sheet statt Dialog, Status = Farbe+Icon+Text), (c) **intelligente Assistenz aus vorhandenen Provider-Daten** (Nachbestell-Vorschlag, Vorbefüllung, Anomalie-Warnungen — ohne neues Backend), (d) **Klon→lib/ui-Migration**, (e) **IA-getriebener Schnitt** der vier Gott-Screens entlang der Hub-Struktur, (f) **Marken-Rebrand** — die Strichmännchen-Palette app-weit als eigenständige Handschrift (§4.10) statt generischem Teal-Material-3.

**Erwartete Wirkung.** Klicks bis Kernaufgabe messbar senken (Nachbestellen 7→2, Abwesenheit 10→3, Genehmigung Modal-Marathon→Bulk), Heute-Tab ≤6 Kacheln je Rolle, 0 hardkodierte Farben/dp in neuen Widgets, kein Horizontal-Scroll für Primärdaten auf Handy.

---

## 2. Analyse

### 2.1 Zielgruppen & Nutzungskontext

Rollen laut [app_user.dart](../lib/models/app_user.dart): `admin`, `teamlead`, `employee`. Das Kiosk-Tablet ist **keine** eigene `UserRole`, sondern ein Geräte-Konto im Dauer-Modus ([kiosk_screen.dart](../lib/screens/kiosk/kiosk_screen.dart)) — kein Identitätswechsel, Name+PIN autorisiert nur einzelne Aktionen. Öffentliche Wunsch-/Feedback-Nutzer laufen über eine isolierte `MaterialApp` ohne Provider-Kette/go_router ([main.dart](../lib/main.dart)). Permission-Getter (`isAdmin`, `canManageShifts`, `canViewSchedule`, `canViewInventory`, `canEditTimeEntries`, `canViewReports`) gaten UI **und** Provider.

#### Personas

| Persona | Rolle | Wo/Wie | Info sofort nötig | Muss schnell erreichbar sein |
|---|---|---|---|---|
| **P1 Verkäufer:in / Lagerkraft** | `employee` | Handy hochkant, einhändig, kurze Fenster; auch am Kiosk | Bin ich eingestempelt? Wie lange läuft die Schicht? Antwort auf gestrigen Antrag? | Ein-/Ausstempeln als oberster CTA, Antrag melden ohne Scrollen, eigener Status ohne Tab-Wechsel |
| **P2 Filialleitung / Schichtleiter:in** | `teamlead` | Handy im Betrieb, Tablet im Backoffice | Wie viele Anträge warten (große Zahl)? Wer ist krank? Wer arbeitet wo? Besetzungslücken? | Inline-Genehmigung aus Inbox, team-gefilterte Ansicht, Auto-Plan fürs eigene Team |
| **P3 Inhaber:in / Admin** | `admin` | Desktop/Tablet im Büro, Handy für Tagesüberblick | Welcher Laden braucht Aufmerksamkeit? Lohn-Anomalien? Warenwert & Ladenhüter? | Pro-Laden-Aufschlüsselung, Batch-Freigabe, Drill-in in ≤3 Taps |
| **P4 Geteiltes Laden-Tablet** | Geräte-Konto | Fest installiert, Vollbild, Distanz 1–2 m, wechselnde Nutzer | Wer ist im Dienst? Was ist offen? Uhrzeit + Ladename | Anmelden-Fläche groß, PIN-Auto-Submit, 1-Tap-Quittierung, Status als großer Farbindikator |
| **P5 Öffentliche:r Kunde** | unauth. | Eigenes Handy, einmalig, QR am POS | Was soll ich eingeben? Kam es an (Referenz-Code)? | Kurzes Formular, ein Absende-Button, klare Bestätigung |

#### Jobs-to-be-Done (verdichtet)

- **P1:** Morgens einstempeln, Stunden-Status sehen, Abwesenheit einreichen — jeweils in Sekunden.
- **P2:** Heute-Schichten überblicken, fehlende Zuweisungen erkennen, Anträge schnell entscheiden — für **ein** Team, nicht die ganze Org.
- **P3:** Tagesüberblick **zwei Läden**, Anomalien erkennen, Lohn/Abschluss ohne Einzel-Klick-Marathon.
- **P4:** In 5 Sekunden „wer arbeitet heute"; angemeldet: stempeln, blind zählen — ohne Dialoge.

#### Nutzungskontext als Design-Zwang → Anforderungen K1–K7

| # | Anforderung | Herleitung |
|---|---|---|
| **K1** | Primäraktion zuerst, im Daumenradius (≥48 dp, ohne Scroll) | JTBD P1 „Einstempeln oberster CTA", P2 „Entscheidungs-Count als große Zahl" |
| **K2** | Status glanceable, nicht lesbar (Farbe+Icon+Größe, `appColors`) | Kiosk 1–2 m Distanz, schwaches Licht |
| **K3** | Kein horizontales Scrollen für Kern-Inhalte auf Handy (Tabelle→Karte < **840 dp**) | Einhändig-hochkant; mehrfach belegte „unbrauchbare horizontale Rolle" |
| **K4** | Formulare intelligent vorbefüllen, Muster vorschlagen | „gleiche Arbeitszeit täglich neu eingeben", `DateTime.now()`-Defaults |
| **K5** | Frühes, verständliches Feedback statt später Backend-Ablehnung | „Compliance-Check erst nach Übernehmen", rohe Exception-Strings |
| **K6** | Pro-Standort statt org-weit | Zwei Läden Kiel; JTBD P3 „welcher Laden braucht Aufmerksamkeit" |
| **K7** | Progressive Disclosure statt stillem `take(n)`-Abschneiden | „nur 6 sichtbar ohne Kontext '5 weitere verborgen'" |

### 2.2 Aktuelle UI/UX-Probleme (priorisiert, mit Beleg)

Belegstellen aus dem Inventar. Wo keine Zeilennummer belegt ist, wird die Stelle beschrieben ohne Nummer.

| # | Bereich | Problem | Schwere | Beleg | Kategorie |
|---|---|---|---|---|---|
| B1 | Heute | Einstempeln erst nach ~1,5 Screens; 11 gleichgewichtete Blöcke, >3000 px Scroll | hoch | `home_screen_tabs.dart:48–200`, `home_dashboards_v2.dart:148` | Unübersichtlich / CTA versteckt |
| B2 | Heute | `DashboardActionItemsCard` (Warnungen) rendert **vor** der Stempeluhr | mittel | `home_dashboards_v2.dart:71` | Falsche Priorität |
| B3 | Heute | Pending-Absences still auf `take(3)` gekürzt, kein „mehr" | mittel | `home_screen_tabs.dart:867` | Info versteckt |
| B4 | Heute | Team-Kalender-Breakpoint 700 px → iPad kriegt Horizontal-Scroll; Desktop-Zellen skalieren nicht mit Schrift | hoch | `home_screen_tabs.dart:1335`, `home_dashboards_v2.dart:348` | Responsive / A11y |
| B5 | Heute/Admin | 6 Verwaltungs-Metriken, **0** operative KPI (Umsatz/Kasse/Ware) | hoch | `home_dashboards_v2.dart:689–718` | Falsche KPIs |
| B6 | Schichtplan | Berechnete Board-Breite ~1386 dp (`_sideWidth 154 + 7×_dayWidth 176`) erzwingt Horizontal-Scroll auf Handy | hoch | `shift_planner_screen.dart:1449` | Responsive |
| B7 | Schichtplan | Rohe `Text('Fehler: $error')`-SnackBars (Secret-Leak-Risiko) | hoch | `shift_planner_screen.dart:585,607,3681` (705 nutzt bereits `_cleanErrorText`) | Fehler-Feedback |
| B8 | Schichtplan | Monatszellen fixe Höhe → Overflow bei vielen Schichten | hoch | `shift_planner_screen.dart:2479–2484,2605` | Overflow |
| B9 | Zeit | 7-Spalten-Tabelle als horizontale Rolle auf Handy | hoch | `lib/screens/zeitwirtschaft/zeiterfassung_screen.dart:274–320` | Responsive |
| B10 | Zeit | Zeiteintrag-Defaults hart 8–17 Uhr, ignoriert geplante Schicht | mittel | `entry_form_screen.dart:68–75` | Keine Vorbefüllung |
| B11 | Zeit | Keine Bulk-Freigabe: Genehmigung nur je Mitarbeiter einzeln | hoch | `lib/screens/zeitwirtschaft/mitarbeiterabschluss_screen.dart:244–271` | Zu viele Klicks |
| B12 | Anfragen | Gebündelte MHD/Bestand-Warnungen ohne Drill-Down | mittel | `notification_screen.dart:898–939` | Kontextwechsel |
| B13 | Anfragen | Tausch-/Abwesenheits-Compliance erst beim Speichern, nicht früh | mittel | `notification_screen.dart:977–1170,2149–2172` | Spätes Feedback |
| B14 | Anfragen | Rohe `error.toString()`-SnackBars | mittel | `notification_screen.dart:1694–1703,2215–2220` | Fehler-Feedback |
| B15 | Kontakte | CSV-Import-Dialog `width: 460` bricht auf Handy | hoch | `contacts_screen.dart:472` | Responsive |
| B16 | Kontakte | Dialoge (CSV/Aktivität) vs. Sheets (Editor) — zwei Modal-Stile | mittel | `contacts_screen.dart:467–505,570–649` | Uneinheitlich |
| B17 | Kontakte | Filter-Chips horizontal ohne Fade-Edge (versteckte Interaktion) | mittel | `contacts_screen.dart:250–273,276–323` | Discoverability |
| B18 | Laden | 6-Item-PopupMenu je Artikel (Abgang/Korrektur/Inventur …) | hoch | `inventory_screen.dart:1311–1323` | Zu viele Klicks |
| B19 | Laden | Nachbestellen = 7 Schritte; Reorder-Banner nur tapbar | hoch | `inventory_screen.dart:1135–1139,1304` | Zu viele Klicks |
| B20 | Laden | `purchase_order_screens.dart` Status-Farben aus `colorScheme` statt `appColors` | mittel | `purchase_order_screens.dart:23–30` | Uneinheitlich |
| B21 | Personal | God-Editor Stammdaten (15 Controller, 4500+ Zeilen) | mittel | `personal_screen.dart:4400–4900` | Wartbarkeit/UX |
| B22 | Personal | Error-SnackBars ohne Farb-Ton | mittel | `personal_screen.dart:538,3081,3433,5000` | Fehler-Feedback |
| B23 | Personal | Lohnabrechnung ohne „letzte duplizieren", kein Batch | hoch | `personal_screen.dart:958–967` | Zu viele Klicks |
| B24 | Team | `loeschen`/`Loeschen` ohne Umlaut in UI-Strings | hoch | `team_management_screen.dart:28,37,1953,2014` | Uneinheitlich (Deutsch) |
| B25 | Team | Editor-Sheets ohne Loading/Error, stiller Speicher-Fehler | hoch | `team_management_screen.dart:209–479` | Fehlender Zustand |
| B26 | Team | Compliance-Toggle je Mitarbeiter einzeln (50× Klick) | mittel | `team_management_screen.dart:1407–1602` | Zu viele Klicks |
| B27 | Team | Audit-Log ohne Datumsbereich, Export „alle" | mittel | `audit_log_screen.dart:107–145` | Fehlende Funktion |
| B28 | Kiosk | Monolith 1421 Zeilen, hardkodierte `EdgeInsets`, rohes `Card` | hoch | `kiosk_screen.dart:251,372,459,502,516` | Wartbarkeit / V2-Bruch |
| B29 | Kiosk | Stempel-Status als Klartext, nicht glanceable auf 1–2 m | mittel | `kiosk_screen.dart:641–643` | Status nicht sichtbar |
| B30 | Kiosk | Board bis 42 Items (`.take(6)`×7) ohne „X weitere" | mittel | `kiosk_screen.dart:441–449,820–834` | Info versteckt |
| B31 | Navigation | Breadcrumb hardkodiert `fromLTRB(20,16,20,0)` ≠ responsivem `screenPadding` | hoch | `breadcrumb_app_bar.dart:121` | Uneinheitlich |
| B32 | Navigation | Avatar-als-Menü-Button ohne Cue (Nutzer erwartet Zurück) | niedrig | `home_screen.dart:1231–1248` | Native-Bruch |
| B33 | Navigation | ~30 flache Section-Routen ohne Hub-Hierarchie | mittel | `shell_tab.dart` (`AppRoutes`) | IA überladen |

---

## 3. Designprinzipien

Verbindliche Abnahme-Checkliste je Screen. Reihenfolge = Priorität bei Konflikten (Barrierefreiheit/Touch schlägt Ästhetik).

1. **Eine Primäraktion je Screen, in der Daumenzone.** Genau ein `FilledButton`/FAB trägt die Hauptaufgabe (Einstempeln, Speichern, Checkout, Antrag senden). Auf Mobil im unteren Drittel, nicht hinter Scroll.
2. **Progressive Offenlegung statt Datenflut.** Wichtigstes zuerst, Details on-demand. `take(N)`-Kürzungen bekommen immer sichtbaren „+N weitere / Details"-Zugang.
3. **Karten statt Tabellen auf Mobil.** Jede tabellarische Ansicht wird < 840 dp zur Kartenliste. Kein horizontaler Scroll für Primärdaten.
4. **Ein kanonisches Muster je Konzept.** Status → `AppStatusBadge`, leer → `AppEmptyState`, Fehler → `AppErrorState`, Kennzahl → `AppMetricCard`/`AppStatCard`, Monatswahl → `AppMonthPicker`, modales Formular → `AppBottomSheetScaffold`. Klone verboten; ein Vokabular je Status.
5. **Native, plattformgerechte Bedienung.** Zurück-Geste respektieren, `leading` = Zurück-Konvention, Bottom-Sheets mit Drag-Handle, Touch-Ziele ≥ 48 dp (44 pt iOS). Kiosk: große Flächen, minimale Dialoge, sub-300-ms-Feedback.
6. **Dark/Light-Parität.** Jeder Farbwert existiert in beiden `AppThemeColors`-Varianten; kein `Colors.*`/Hex. Vor Auslieferung in beiden Modi sichten.
7. **WCAG-AA durchgängig.** Kontrast ≥ 4.5:1 (Text) / 3:1 (große Schrift & UI-Grafik) über das bestehende Kontrast-Gate (DS2). Status **nie nur über Farbe** → Icon+Text. Dynamic Type bis **2,0×** (dichte Raster dokumentiert 1,5×) ohne Clipping — intrinsische Höhen, Golden bei 1,0/1,5/2,0 (Entscheidung E1 des Vorgängers, bereits live).
8. **Reduce-Motion respektieren.** Jede Animation über `AppMotion.resolve(context, …)`/`context.motionDuration` (`Duration.zero` bei `disableAnimations`). Keine hardkodierten `Duration(...)`.
9. **Antizipieren statt abfragen.** Auto-Vorschläge, Vorbefüllung, Anomalie-Warnungen (Plan/Ist, > 10 h, Compliance-Konflikt) **vor** der Aktion; rollen-/kontextgerechte Dichte (Kiosk read-first & fingergroß, Admin dicht, Employee auf Selbstbedienung reduziert).

---

## 4. Modernes Designsystem

Baut auf der V2-**Token-Struktur** auf, stellt die **Farbwelt aber verbindlich auf die Strichmännchen-Marken-Palette** um (§4.2) — das ist die eigentliche Antwort auf „keine Standard-UI". Vervollständigt zugleich drei Struktur-Lücken: parallele Alt-Systeme, Klon-Widgets, uneinheitliche Status. **§4.10 kodifiziert die Design-Signatur** — Marken-Palette **plus** strukturelle Handschrift, die diesen Umbau von generischem Material 3 unterscheidet. §4.1/4.3–4.9 sind Hygiene/Vereinheitlichung; ohne §4.2+§4.10 bliebe das Ergebnis korrekt, aber austauschbar.

### 4.1 Kanonische Token-Referenz

Zugriff **immer** über `context`-Getter (`AppDesignTokensX`), nie über Konstruktor-Konstanten oder Rohzahlen.

| Rolle | Zugriff | Werte (V2) | Verbindliche Verwendung |
|---|---|---|---|
| Abstände | `context.spacing` | `xxs2 · xs4 · s6 · sm8 · s12 · md16 · lg24 · xl32 · xxl48` | Jeder `EdgeInsets`/`SizedBox` |
| Radien | `context.radii` | `xs8 · sm12 · md16 · lg20 · xl28 · xxl36 · pill` | Inputs/Segmented `md16`, **Buttons = `StadiumBorder`-Pill** (56 dp, app-weites Signal — §4.10 S4, **nicht** `md16`), Cards/Dialoge `xl28`, Hero `xxl36`, Nav-Indicator `lg20`, Chips/Badges `pill` |
| Bewegung | `context.motion` + `AppMotion.resolve(...)` | `short150 · medium300 · long450 · extraLong600` | Jede Animation über `resolve` (Reduce-Motion) |
| Elevation | `context.elevation` | `flat0 · raised1 · floating3 · overlay6` | Sparsam; nie auf Grid-/Planner-Zellen |
| Icons | `context.iconSizes` | `sm18 · md24 · lg28 · xl32 · hero40` | Ersetzt jedes `size:`-Literal |
| Status | `Theme.of(context).appColors` | `success/warning/info` + `on*`/`*Container` (re-tuned auf `StrichTokens`: green/yellow/blue, §4.2) | Ampel/Coverage/Planner-Palette; nie `Colors.*` |
| Ziffern | `textStyle.tabular` / `kTabularFigures` | `FontFeature.tabularFigures()` | Uhr, Stunden, Plan/Ist, €, Countdown, Bestand |

**Anti-Pattern-Check vor Auslieferung** (`grep` in geänderter Datei): `EdgeInsets.all(1[0-9])`, `SizedBox(height: [0-9]`, `size: [12][0-9]`, `Colors\.`, `#[0-9A-Fa-f]{6}`.

### 4.2 Farbe — Strichmännchen-Marken-Palette (app-weit)

Die Farbwelt wird **1:1 auf die Strichmännchen-Ladenseite** umgestellt (Quelle der Wahrheit: `styles.css :root`, extrahiert und je Wert mit Quellzeile belegt in [strichmaennchen_tokens.dart](../lib/theme/strichmaennchen_tokens.dart) `StrichTokens`). Das ersetzt den Teal-Seed als App-Identität. Vorgehen: `_buildColorSchemeV2` **und** `AppThemeColors` auf `StrichTokens` re-tunen — **kein Screen** bekommt Hex; alles fließt weiter über `colorScheme.*` / `appColors`. Dark = navy-Flächen (`textOnDark`/`mutedOnDark` vorhanden).

**Rollen-Mapping (verbindlich):**

| Rolle | Wert (`StrichTokens`) | Regel |
|---|---|---|
| `primary` (Marke, Header, Links) | navy `#061B36`; `onPrimary` = white | im Dark navy-Fläche, paper-Text |
| **CTA-Füllung** (Pill, §4.10 S4) | **yellow `#F0C738` + `ink`-Text** (`primaryAction`/`onPrimaryAction`) | Gelb **nie** mit weißem Text (Kontrast) |
| `secondary` / Akzent | gold `#CAA65A`, Text darauf navy | gold = Akzent/Border/Fill-mit-dunklem-Text, **nie Text auf Weiß** |
| Hintergrund / Fläche | paper `#F4EFE4` / Karte white `#FFFDF8` | warme Neutralen statt Grau (§4.10 S1/S9) |
| Text / gedämpft | ink `#171615` / ink@72 % | auf Navy: paper / paper@72 % |
| Hairline-Border | ink@14 % (`--line`) | ersetzt teal `outlineVariant` |

**Status-Semantik (`appColors` re-tunen; Icon+Text-Pflicht bleibt):**

| Semantik | Tone | Wert | Kontrast-Regel |
|---|---|---|---|
| Erledigt / genehmigt / eingestempelt | `success` | openGreen `#2FAD64` (Punkt/Icon) · **green `#2D6D55` für Text** | openGreen nur ~2,8:1 → nie Text |
| Offen / fällig / **MHD bald** / Warnung | `warning` | yellow `#F0C738` + ink · Vorstufe gold | Fläche mit ink-Text; nie gelber Text auf Weiß |
| Über Soll / Ziel übertroffen | `accent` | gold `#CAA65A` | **ersetzt** das entfallende Violett-Tertiär |
| Hinweis / neutrale Meldung | `info` | blue `#246CA0` + white | — |
| Fehler / abgelehnt / abgelaufen / „geschlossen" | `error` | rose `#B8435A` + white | — |
| Neutral / Entwurf / archiviert | `neutral` | paperDeep `#E7DCC7` | — |

Mapping `Domänen-Enum → Tone` bleibt im Screen, der Farbwert kommt **nur** aus dem Tone/Token; kein Screen definiert eigene Farbtabellen. `Colors.transparent` (`team_management_screen.dart:131`) → `surface`/`border`. **Das Violett-Tertiär entfällt** (nicht in der Marken-Palette) → „über Soll" wird gold. Der Signal-Verlauf (`signalGradient` gelb→rose→blau, aus der Ladenseite) ist **nur** für den einen Aufmerksamkeits-Moment reserviert (z. B. Ladefortschritt), nie Flächendeko.

### 4.3 Typografie

Basis `fontFamily: 'NotoSans'` (hart, `app_theme.dart`), Locale `de_DE`. Widgets referenzieren **nur benannte `textTheme`-Rollen**, kein Inline-`fontSize`/`fontWeight`.

| Rolle | Gewicht (V2, ausgeliefert) | Tracking | Einsatz |
|---|---|---|---|
| `displaySmall` | `w800` | `-1,0` | Große Hero-Zahlen/-Titel (§4.10 S2) |
| `headlineMedium` | `w800` | `-0,6` | Screen-/Bereichstitel |
| `headlineSmall` | `w700` | `-0,4` | Sekundärtitel |
| `titleLarge` | `w700` | `-0,2` | Card-/Sheet-Titel |
| AppBar-Titel | `w800` | — | Kopfzeile |
| `titleMedium/Small` | `w700` | — | Kachel-/Listenüberschriften |
| `labelLarge` | `w700` | `+0,2` | Buttons (Pill) |
| Nav-Labels | `w800` selected / `w600` | 11 pt, `+0,1` | BottomNav/Rail (gefüllte Fläche, §4.10 S6) |
| `bodyMedium/Small` | `w400` | — | Fließtext, Helper/Error |

> **Nicht abschwächen:** Diese Gewichte/Trackings sind im ausgelieferten V2-Theme ([app_theme.dart](../lib/theme/app_theme.dart) `_buildThemeV2`) bereits so gesetzt — `w800` + negatives Tracking ist **Teil der Handschrift** (§4.10 S2). Eine frühere Fassung dieser Tabelle mit `w700`/`w600` lag *hinter* dem Theme und hätte die Signatur zurückgebaut; hier korrigiert.

**Tabellen-Ziffern verpflichtend** (`.tabular`) für: Stempel-Live-Ticker, Wochen-/Monatssaldo, Plan/Ist, Kiosk-Countdown, Bestandswerte EK/VK/Spanne, €-Beträge. Kein Inline-`fontFamily`-Override (Apple-Fonts würden NotoSans still ersetzen). Dynamic Type: Titel/Labels nie in feste Höhen zwingen (intrinsisch statt fixes `SizedBox`).

### 4.4 Icons

Outline = inaktiv, filled/rounded = aktiv (Nav-Rail/BottomNav, Favorit `star_border`↔`star`). Größen nur aus `context.iconSizes` (`15/16`→`sm18`, `20/22`→`md24`, `28`→`lg28`, `40`→`hero40`). Deutsche Zeichensetzung, Umlaute korrekt (`Ungueltiger Barcode`→`Ungültiger Barcode`, `loeschen`→`löschen`).

### 4.5 Buttons

Genau **eine** Primäraktion je Screen als `FilledButton`. Form = **`StadiumBorder`-Pill** (56 dp, §4.10 S4); die Primär-Pill ist **gelb** (`primaryAction` + `ink`-Text), nicht teal/rechteckig.

| Ebene | Widget | Semantik |
|---|---|---|
| Primär | `FilledButton` | Speichern, Einstempeln, Antrag senden, Checkout — nur einer |
| Sekundär | `FilledButton.tonal` / `OutlinedButton` | Alternative Bestätigung |
| Tertiär | `TextButton` | Abbrechen, „mehr anzeigen", Links |
| Icon-Aktion | `IconButton` (Größe aus `iconSizes`) | Kontextaktionen in Zeilen |
| Zerstörend | Button mit `tone: error` | Löschen (immer via `AppConfirmDialog` + `mounted`-Guard) |

Custom-Färbung nie via `styleFrom(backgroundColor: hardcoded)` (`_ClockCorrectionDialog`), sondern Tone-abgeleitet.

### 4.6 Formulare

Kanonisches Feld = `AppFormField` (mit `helperText`/`errorText`/`validator`). Rohe `TextField`/`InputDecoration` migrieren (Kontakte CSV/Aktivität, `kiosk_pin_setup_sheet.dart:102–122`, Payroll-/Stammdaten-Editoren). Inline-Validierung `onUserInteraction` statt Backend-Ablehnung. Intelligente Defaults (`endDate = startDate`; Zeiteintrag aus geplanter Schicht; letzte Laden-Wahl). Modale Formulare = `AppBottomSheetScaffold` (`showDragHandle`, `isScrollControlled`, `useSafeArea`), Speichern-Button in sichtbarer Bottom-Bar; keine `AlertDialog` für mehrfeldrige Eingaben.

### 4.7 Tabellen → adaptive Karten

< **840 dp** (`expandedWindow`, alleinige Tabelle→Karte-Autorität): jede `DataTable` wird zur **Kartenliste** (Vorbild `_MonthEntryTile` in `stempel_screen.dart`), ≥ 840 dp: `DataTable` in `ConstrainedBox(maxWidth:)` + tabulare Zahlen. (600 dp hat **nur** eine Rolle: Inline-Chips vs. Sheet der `AppFilterBar`, §6.2 — nie als Tabellen-Breakpoint.) Heatmaps (Staffing/Planner) bekommen kompakte Tages-/Top-N-Ansicht statt Zwang zum Querscrollen.

### 4.8 Statusanzeigen

Kanonisch = `AppStatusBadge` (Label + `tone` + `icon?`) bzw. `AppStatusBanner`. Nie nur Farbe → immer Icon+Text. Fehler = `AppErrorState` (mit Retry) statt roher `SnackBar('Fehler: $error')`; technische Strings via `_cleanErrorText`-Sanitisierung. Offline = `AppOfflineBanner`. Status-Labels vereinheitlichen: **genehmigt/ausstehend/abgelehnt** (Anträge), **Entwurf/eingereicht/freigegeben** (Zeiteinträge) — Mapping zentral am Enum, keine `.value`-Änderung (Zwei-Serialisierungs-Regel unberührt).

### 4.9 Migration der Klon-Widgets → lib/ui

| Klon-Widget (Fundstellen) | Ziel (`lib/ui`) |
|---|---|
| `_EmptyState` (`home_screen.dart:2503`) | `AppEmptyState` (typedef auf `EmptyState`) |
| `_StatCard` (`home_screen.dart:2668`, `bestand_insights:368`, `sortiment:353`) | `AppStatCard` / `AppMetricCard` |
| `_QuickActionCard` (`home_screen.dart:1808`) | `AppQuickActionCard` (behebt „Expanded im Wrap") |
| `_SectionCard` (`order_analytics:275`, `statistics:230`) + Legacy `SectionCard` | `AppSectionCard` |
| `_StatusChip`/`_StatusBadge` (Feedback, Wishes, Inventory, daily_closing, zeiterfassung, abwesenheiten, mitarbeiterabschluss, monatsabschluss, purchase_order) | `AppStatusBadge` |
| `_InfoChip` (Feedback, Wishes, Scanner) | geteiltes `info_chip.dart` |
| `_ErrorBanner` (`inventory:994`, `auth:762`, `customer_order:500`) | `AppErrorState` / `AppStatusBanner(tone: error)` |
| `_MonthPicker`/`_MonthNavigation`/`_MonthHeader` (lohnlauf, mitarbeiterabschluss, stempel, stundenkonto, abwesenheitskalender, zeitwirtschaft_hub) | **neu `AppMonthPicker`** |
| `_HeaderSection` (`statistics:198`) | `SectionHeader` |

**Neu zu bauen (gerechtfertigte Lücken):** `AppMonthPicker` (Monats-/Jahres-Navigation, tabular), `AppAdaptiveTable`/`AppDataList` (kapselt 4.7), `AppShiftColorMapper` (pure, testbar, ersetzt kollidierenden `title.hashCode % 5`-Fallback in `_resolveShiftColor`). Migration ist reine Optik/IA/UX — kein Provider/Model/Serialisierungs-Eingriff; jeder Schritt hält `flutter analyze` + `flutter test` grün.

### 4.10 Design-Signatur — gegen Standard-UI

> **Diagnose.** §4.1/4.3–4.9 machen den Umbau *korrekt und einheitlich* — Korrektheit allein ergäbe aber eine austauschbare Material-3-App. Die Unverwechselbarkeit kommt aus **zwei** Quellen: (a) der **Strichmännchen-Marken-Palette** (§4.2, warm-editorial: paper, navy, gold, gelber CTA — nicht kühles Teal-/Grau-M3) und (b) einer Handvoll **struktureller Signatur-Züge**, die palette-unabhängig gelten und schon halb im V2-Theme stecken. Referenzklasse: Linear / Things 3 / Stripe (ruhig, präzise, unverwechselbar — nie verspielt). Jeder Zug ist in Dark **und** Light definiert und hält das (nach Rebrand neu gefahrene) Kontrast-Gate.

**S1 — Warm-editoriale Flächensprache (Marke + flach).** Fläche = paper/white, Trennung über **Hairline** (`StrichTokens.border` = ink@14 %) + 0,8-Divider, `surfaceTint: transparent`, `elevation 0` als Default; genau **ein** erlaubter weicher Schatten (`AppCard`). *Verbot:* `Colors.grey`, kühle M3-Neutralen, Tonal-Elevation, `overlay`-Schatten auf Flächen. *Überall.* *Abgrenzung:* Stock-M3 ist neutralgrau + tonal gestapelt; WorkTime ist warm + flach.

**S2 — Zahlen sind der Held.** Neue Display-Zahl-Rolle: große tabulare Ziffer (`.tabular`, `w800`, negatives Tracking) in **ink** auf paper/white, Akzent **gold/navy**. **Neu** `AppMetricValue` (Vorschlag) / Ausbau `AppStatCard`. Einsatz: Stempel-Ticker, Wochen-/Monatssaldo, Kassendifferenz, Bestand EK/VK/Spanne, Kiosk-Countdown. *Abgrenzung:* Things/Stripe sind über Zahlen-Typografie wiedererkennbar; Default-M3 nicht.

**S3 — Der Hero-Moment (einzige Sonderfläche).** `AppHeroCard` ist die einzige Stelle mit Verlauf + farbigem Schatten — **umgefärbt auf navy→gold** (paper→gold-Tint im Light, navy-Fläche im Dark), `xxl36`-Radius. Verbindliche Schale je Haupt-Tab für den wichtigsten Statusmoment (Employee Stempel-Hero, Teamlead Team-Status, Admin Betriebs-Hero). *Regel:* kein zweiter Verlauf sonst. *Abgrenzung:* verhindert „gewöhnliche Card mit Badge".

**S4 — Der gelbe Pill-CTA (Markenzeichen der Ladenseite).** Primäraktion = `StadiumBorder`-Pill (56 dp) in **yellow `#F0C738` + ink-Text** — exakt der `.btn-primary` der Ladenseite. Genau eine je Screen (Stempeln, Speichern, Checkout, Antrag senden). *Abgrenzung:* nicht der rechteckige Default-M3-Button, nicht teal, **nie weißer Text auf Gelb**.

**S5 — Ledger als Datenlisten-Kanon.** `AppKontoTile` (`+/−/=`, Summenzeilen `w800`, `dividerDavor`, Ton gut/warnung) ist Vorbild für **alle** Aufstellungslisten: Urlaubs-/Zeitkonto, Lohnbestandteile, Kassenzählung, Bestell-Positionssummen, Monatsabschluss. *Abgrenzung:* eigenes „Aufstellung-mit-Saldo"-Vokabular statt generischer `ListTile`-Reihen.

**S6 — Auswahl = gold-getönte Fläche.** „Ausgewählt" hat ein Signal: gefüllte Fläche (gold-/paperDeep-Tint) — Nav-Indicator, **TabBar-Indikator als Fläche statt M3-Unterstrich**, Chips, `IconButton`-selected. Neue `AppFilterBar`/`AppSegmented` erben es. *Abgrenzung:* kein M3-Unterstrich, kein Farbwechsel-only.

**S7 — Motion-Signatur (Katalog, nicht pro Screen erfunden).** Fixe Zuordnung über die vorhandenen Kurven (`standard = easeInOutCubicEmphasized`, `spring = easeOutBack`), immer via `AppMotion.resolve`: (a) Erscheinen/Statuswechsel = `medium` emphasized; (b) **Erfolgs-/Quittierungsmoment** (Einstempeln, Kiosk-Bestätigung, „Nachgefüllt") = `spring` + dezentes Scale/Fade; (c) Zahlwechsel = kurzer Cross-Fade (tabular verhindert Springen). *Abgrenzung:* nicht die Default-Transition mit korrekter Dauer, sondern ein benanntes Muster.

**S8 — Kiosk als Anzeigetafel (Distanz-UI, eigene Skala).** Das 1–2-m-Tablet ist keine vergrößerte Handy-Card: großflächiger Status aus Fläche + Display-Zahl (S2) + Marken-Farbe (green „im Dienst" / rose „aus" / gelb „Achtung"), Countdown als Display-Zahl, Board mit klarer Zeilenrhythmik, eigene kompakt-präzise Dichte (Werkzeug-Charakter). **Neu** `KioskStatusPanel` (Vorschlag). *Abgrenzung:* der Kiosk wird **nicht** auf Settings-Karten normalisiert.

**S9 — Warme Neutralen & Marken-Grün/Gold als Vokabular.** paper/white statt Grau; success = **green `#2D6D55`** (Text) / openGreen (Punkt); Akzent gold; „über Soll" gold statt Violett. *Regel:* keine neue Grau-/Fremd-Palette; Flächen und Akzente kommen aus `StrichTokens`.

**Governance — Signatur-Gate (Definition of Done, nicht nur grep):**
- Jeder neu gebaute/umgebaute Screen nutzt **mindestens zwei** Signatur-Züge — S1 (warm-flach) ist Pflicht, dazu mind. einer aus S2–S8 passend zum Screen.
- **Keine Regression:** kein `w700` wo das Theme `w800` liefert, keine `md16`-Buttons statt gelber Pill, keine flache Card statt `AppHeroCard` am Hero-Moment, keine generischen Rows statt Ledger, **kein Teal-Rest, kein Grau**.
- **Referenz-Screens** (so sieht WorkTime aus): `home_dashboards_v2` (Hero), `abwesenheit_screen`/MA-Detail (Ledger), `auth_screen_v2` (Pill/Form) — nach Rebrand als Erste umgestellt und als „Golden" fixiert. Neue Komponenten (`AppMetricValue`, `AppMonthPicker`, `AppAdaptiveTable`, `AppFilterBar`, `KioskStatusPanel`) werden **visuell** an diesen Referenzen spezifiziert, nicht nur funktional.

---

## 5. Intelligente UX-Funktionen

**Kernidee:** Die Daten liegen bereits in den Providern — sie werden dem Nutzer nur nicht an der richtigen Stelle serviert. Alles unten ist **client-seitige Ableitung aus bereits geladenen Daten**, außer explizit als **[Ausblick · Backend]** markiert.

**Legende:** ✅ vorhandene Daten (rein clientseitig) · 🔶 clientseitig möglich, Genauigkeit hängt von OktoPOS-Sync ab · 🧱 **[Ausblick · Backend]** neue Server-/Modell-Arbeit.

### 5.1 Automatische Vorschläge

| # | Feature | Wo | Datenquelle | Quelle |
|---|---|---|---|---|
| V1 | Nachbestell-Vorschlag mit Zielmenge | Bestand-Tab Reorder-Banner (`:1135`) + Tile-Schnellaktion (`:1304`) | `Product.needsReorder` + `suggestedReorderQuantity` | ✅ |
| V2 | Datengetriebene Meldebestand-Empfehlung | Bestand-Tab Hinweis + `/bestand-insights` | `SalesInsightsProvider.reorderChanges` → `ReorderSuggestion` | 🔶 |
| V3 | Häufig-bestellt-zuerst | Scanner-Chips (`:1361`), auch Buchen-/Inventur; Bestand-Suche | Ableitung aus `purchaseOrders`-Historie | ✅ |
| V4 | Kühlschrank-Auto-Lücken | Kühlschrank-Tab | `Product.fridgeNeedsRefill`/`fridgeDeficit` | ✅ |
| V5 | Schicht-Auto-Vorschlag *(existiert)* | Planner-Toolbar „Automatisch planen" | `ScheduleProvider.proposeAutoAssignment` | ✅ |
| V6 | Kundenwunsch → Bestellung vorbefüllen | Kundenwünsche PopupMenu | `CustomerOrder.fromCustomerWish(...)` + Standort vorwählen | ✅ |
| V7 | Brutto-Vorschlag Lohn *(prominenter)* | `_PayrollEditorSheet:2612` | `_grossFromHours()`; + „letzte duplizieren" | ✅ |

**V1/V3 Quick-Win:** Reorder-Banner mit zwei Inline-Buttons `[+ In Korb (X Stk)]` (vorbefüllt) und `[+ Neue Bestellung]` — kein Zwischendialog, `success`-SnackBar mit Undo. V2 nur **anzeigen**, nie `minStock` automatisch überschreiben. Ohne POS-Sync degradiert V2/V3-Präzision sichtbar-leer, nicht falsch.

### 5.2 Kontextabhängige Aktionen

**Zustandsabhängige Bestell-Primäraktion:** `!status.isClosed` (via `openOrders`) → „Wareneingang buchen" (`receiveOrder(...)`); `status.isClosed` → „Erneut bestellen". Offene Positionen als `warning`-Chip in der Listenzeile. **Kontextuelle FAB je Tab:** Bestand → Scanner, Bestellkorb → „Bestellen" (nur voll + `canManageInventory`), Bestellungen → „Neue Bestellung". **Swipe-Aktionen** (Tablet): Kühlschrank rechts „Nachgefüllt"/links „Löschen"; Artikel-Tile rechts „In Korb"; Wunsch/Feedback rechts „Erledigt". Menü bleibt Long-Press-Fallback.

### 5.3 Vorausgefüllte Felder

| Feld | Vorbelegung | Quelle |
|---|---|---|
| Standort (Korb/Zeit/Wunsch→Bestellung/Zählung) | aktiver Kontext; bei 1 Zuweisung ohne Dialog | ✅ |
| Lieferant / Bestellmenge / EK | zuletzt genutzt bzw. `suggestedReorderQuantity` / `priceHistoryFor` | ✅ |
| Datum / Enddatum Abwesenheit | heute; `endDate = startDate` bei Single-Day | ✅ |
| Arbeitszeit (Zeiteintrag) | Zeiten der geplanten Schicht am selben Tag statt 8–17 | ✅ |
| MHD-Vorschlag (Charge) | jüngstes MHD desselben Produkts | ✅ |

Vorbelegung ist **überschreibbar** und als Vorschlag erkennbar (`onSurfaceVariant`-Hinweis „aus letzter Bestellung").

### 5.4 Warnungen bei Fehlern/ungewöhnlichen Werten

| # | Warnung | Schwelle | Wo | Quelle |
|---|---|---|---|---|
| W1 | MHD-/Ablauf *(existiert)* | ≤ `leadDays` (3) | Inbox/Kiosk/Bestand | ✅ `computeExpiryWarnings` |
| W2 | Meldebestand *(existiert)* | `currentStock ≤ minStock` | Reorder-Banner/Inbox/Heute | ✅ `lowStockProducts` |
| W3 | Kassendifferenz-Anomalie | `\|cashDifferenceCents\|` > Schwelle | Tagesabschluss, Heute (Admin) | ✅ `CashClosing.cashDifferenceCents` |
| W4 | Unplausible Menge | > 10× Vorschlag / negativer Bestand | Erfassungs-Sheets inline | ✅ |
| W5 | Unplausibler Preis | VK < EK / Preissprung ≫ Historie | Preis-Korrektur | ✅ `marginCents`/`priceHistoryFor` |
| W6 | Compliance-Schicht *(Logik da)* | `ComplianceService.validateShift` | Editor live + Tausch/Abwesenheit als Vorwarnung | ✅ |
| W7 | Minijob-Grenze | > 60300 ct/Monat | Vorschau + Lohn-Editor | ✅ |
| W8 | Lange Arbeitszeit rückwirkend | > 10 h (ArbZG) | Stempel-/Zeit-Liste `warning`-Chip | ✅ |
| W9 | Urlaubsverfall-Vorwarnung | Verfall-/Hinweis überfällig | Urlaubskonto-Card, Admin-Heute | ✅ |
| W10 | Quali-Ablauf | ≤ 30 Tage | Personal-Übersicht, Team-Compliance | ✅ |

**Muster:** blockierend (`error`, Button disabled) nur bei echten Compliance-Blockern (W6/W7); warnend (`warning`, Bestätigung) W3/W4/W5/W8; informativ (`info`) W9/W10. **Frühe Compliance-Vorschau (W6):** in Tausch-/Abwesenheits-Sheets `validateShift`/`checkCompliance` **beim Öffnen** ausführen. Roh-Exceptions nie zeigen (`_cleanErrorText`, Details nur ins Log via `AppLogger`).

### 5.5 Schnellaktionen

App-Icon-Shortcuts *(existiert, `QuickActionsService`)*; Heute-Quick-Actions umsortieren (Einstempeln vor `DashboardActionItemsCard`); Ein-Klick-Muster-Abwesenheit („Heute krank", „Nächste Woche Urlaub"); Standort-Merken beim Stempeln; Bulk „Alle Lücken erledigt" (Kühlschrank); Bulk-Genehmigung (Callable-Limit 50 beachten); Bulk-Regel-Toggle (Team); Favoriten-Filter (Kontakte); Kiosk-Kachel-1-Tap. Alles über `AppQuickActionCard`/`AppQuickActionTile` — kein zweites Quick-Action-Widget. **Bulk = UI-Schleife über bestehende Provider-Mutatoren** (kein neuer Write-Pfad, `upsertWorkEntryBatch` ≤ 50, Audit je Eintrag bleibt korrekt) — kein additiver Provider-Bulk-Mutator ohne separate Kopplungs-Freigabe.

### 5.6 Rollenbasiertes „Heute"-Dashboard — nur relevante KPIs

Siehe Abschnitt 6.1 (Dashboard-Redesign) für die vollständige Blockstruktur je Rolle. Kern: max. 6 Blöcke, Modell **A Wo stehe ich · B Was ist heute los · C Was muss ich tun**. Admin bekommt statt 6 Verwaltungs-Metriken **operative KPIs** aus realen Quellen (`PosDailyStat.revenueGrossCents` 🔶, `CashClosing.cashDifferenceCents` ✅, `lowStockProducts` ✅, `expiryWarningCount` ✅, `fridgeShortfallCount` ✅, `openCustomerOrders` ✅) mit **Standort-Umschalter** (`AppSegmented`, Getter nehmen bereits `siteId`).

### 5.7 Roadmap Aufwand vs. Wirkung

| Prio | Bündel | Aufwand | Backend? |
|---|---|---|---|
| P0 | V1 interaktives Banner, Vorbelegung, W3/W8, Heute-Umsortierung | gering | nein ✅ |
| P1 | Bestell-FAB + Swipe, Arbeitszeit aus Schicht, W6-Vorschau, Bulk | mittel | nein ✅ |
| P2 | Rollen-Dashboards + Site-Umschalter, W4/W5/W9/W10 | mittel | nein ✅ |
| P3 | Datengetriebener Meldebestand (V2), Umsatz je Laden | mittel | teils 🔶 |
| P-Ausblick | 🧱 geräteübergreifendes „zuletzt genutzt", 🧱 prognostische Nachbestellung (Wetter/Saison) | hoch | ja 🧱 |

---

## 6. Modulbezogene Maßnahmen

### 6.1 Dashboard / Heute — 11 Blöcke → 6 je Rolle

Weiche in `home_screen.dart:1387–1411` (`buildHomeTab`). Neue Widgets in `home_dashboards_v2.dart`; V1 (`home_screen_tabs.dart`) bleibt Legacy.

**Employee (P0/P1):** 1) **Status-Hero + Stempel-CTA** (Hero und Stempeluhr verschmelzen, grün „eingestempelt seit HH:mm"). 2) **Heute für mich** (nächste Schicht + Wochen-Ist/Soll kompakt). 3) **Meine offenen Anträge** (vollständig, Zähler statt `take(3)`). 4) Schnellaktionen (Krank/Urlaub/Zeit). 5) Wochenstreifen. 6) Monat kompakt. — *Entfällt:* „Letzte Einträge" (→ `/zeit`), „Nächste Schichten"-Liste (in Block 2), `DashboardActionItemsCard` (für Employee raus).

**Teamlead (neuer Zweig `_TeamleadDashboardTabV2`, Annahme):** Fokus eigenes Team. 1) Team-Status-Hero („X von Y eingestempelt · Z Schichten heute"). 2) **Heute entscheiden** (offene Abwesenheiten + Tausch **meines Teams**, große Zahl → Inbox inline). 3) Unbesetzt heute (`unassignedToday`, `error` wenn > 0). 4) Team-Kalender heute (Tagesspalte). 5) Schnellaktionen. 6) Nächste Schichten `take(8)`.

**Admin:** operative KPIs statt Verwaltungs-Metriken. 1) Betriebs-Hero (+ **Site-Umschalter** `AppSegmented`). 2) **Umsatz & Kasse heute** (`PosDailyStat` 🔶 + `cashDifferenceCents` ✅, rot ≠ 0). 3) Heute entscheiden. 4) **Waren-Ampel** (Meldebestand / Ablauf ≤ 3 T / Kühlschrank-Lücken). 5) Team-Kalender heute (Breakpoint 700→**840**, `expandedWindow` — deckt iPad-Portrait ab). 6) Nächste Entscheidungen (inline Accept/Reject). — *Gestrichen:* „Offene Einladungen" (gehört auf `/team`).

**Querschnitt:** `DashboardActionItemsCard` hinter das Clock-Widget; feste Reihenfolge A→B→C; Kern-CTA above the fold; Skeleton statt Mini-Progress; `snapshot.hasError` → `AppErrorState` mit Retry; `DateFormat`-Strings zentral in `home_screen_helpers.dart`.

### 6.2 Navigation & IA — 3 Ebenen (Tab → Hub → Detail)

7 Tabs unverändert. ~30 flache Section-Routen kuratiert unter Hubs bündeln (URLs/`AppRoutes` bleiben, Deep-Links funktionieren):

- **`shop` (`/laden`)** von 5 internen `TabBar`-Tabs zu einem `AppSectionCard`-Hub. Analyse-Routen (`/bestell-auswertung`, `/bestand-insights`, `/sortimentsanalyse`, `/kassenbericht`, `/laden-benchmark`) unter Gruppe „Auswertungen" (Permission unverändert `route_permissions.dart`).
- **`profile` (`/profil`)** wird einziger Einstieg in Verwaltung: permission-gegate Sektion (nur `isAdmin`) → `/personal`, `/team`, `/buchhaltung`, `/protokoll`, `/einstellungen`. Employees sehen nur „Meine Akte" + Benachrichtigungen + Abmelden.
- **`plan`** bekommt `/besetzungs-profil` als Hub-Kachel neben „Automatisch planen".
- **Suche:** global = `GlobalSearchDelegate` (um Mitarbeiter/offene Schichten/Bestellungen erweitern; bleibt **clientseitig** über bereits geladene Provider-Listen — keine neuen Firestore-Queries/Composite-Indizes); lokal = `AppSearchField` überall (rohe `TextField`-Suchen ersetzen). **Filter:** neues `AppFilterBar` (≥ 600 dp inline-Chips, < 600 dp Filter-Button → Sheet); Fade-Edge für inline-Chip-Leisten (B17); „X von Y + Reset" überall.
- **Breadcrumb:** `fromLTRB(20,16,20,0)` → `MobileBreakpoints.screenPadding` (B31).

### 6.3 Tabellen & Listen

Kanon: Handy = Karte, ≥ 840 = Tabelle/Master-Detail (6.1 Muster-Bausteine). Betrifft `zeiterfassung_screen.dart`, `stundenkonto_screen.dart`, `monatsabschluss_screen.dart`, `staffing_profile_screen.dart` (Heatmap Ausnahme: Fade-Edge + Sticky-Spalte), `audit_log_screen.dart` (+`ConstrainedBox`, Datumsbereich B27), Team-Compliance (`ListView.builder` statt 50× `ExpansionTile`). Sekundäraktionen aus PopupMenu in sichtbare Icon-Buttons heben (B18); `take(n)` → „+N weitere" (B3/B12/B30).

### 6.4 Formulare

Alle Editor-Sheets = `AppBottomSheetScaffold` mit Abschnittsgliederung (`_EditorSection`); feste-Breite-`AlertDialog` ersetzen (B15/B16). Alle Felder = `AppFormField` mit Label + Inline-Validierung; fachliche Frühwarnung vor Submit (B13). **PopScope-Dirty-Guard** verbindlich (kein stiller Datenverlust); Speicher-Feedback (Button disabled + Spinner, B25); Content in `ConstrainedBox` zentriert auf Desktop. Stammdaten-God-Editor (B21) als **linearer Wizard** (Person → Vertrag → Familie/Bank).

### 6.5 Detailseiten

Aufbau **Kopf → Fakten → Aktionen**, eine Primäraktion. Einheitliche Status via `AppStatusBadge` (Farbe+Icon+Text); `purchase_order_screens.dart:23–30` von `colorScheme` auf `appColors` (B20). Verlauf als eingebettete Scroll-Sektion (keine zwei divergierenden Sheet-Implementierungen, Kontakte). Inbox-Karten-Titel klickbar (Deeplink), gebündelte Warnungen mit Drill-Down-Sheet (B12). Order-Checkout: ein Sheet mit einer Primäraktion statt zwei Dialogen.

### 6.6 Kalender- & Zeitansichten

Handy (< 840): **Agenda** (chronologische Liste), nie zeit-proportionales Raster. Schichtplan-Board → Tag-Agenda (B6); Monatszellen min-Höhe + „+N"-Chip statt fixer Höhe/Overflow (B8); Desktop-Zellhöhe an `textScaler` koppeln (B4). Navigation vereinheitlichen: **ein** Datums-Baustein (‹ › + „Heute" + Datums-Popup) — löst Navigations-Wildwuchs im Planner und das `_MonthNavigation`/`_MonthHeader`/`_MonthPicker`-Trio.

### 6.7 Personalbereich

Lohnabrechnung: „Letzte Abrechnung duplizieren" + Batch-Freigabe prominent (B23); Lohnarten-Katalog aus Payroll-Editor erreichbar. Error-SnackBars mit `tone: error` (B22). Urlaubskonto visuell (Resturlaub grün/rot, `AppStatCard` statt `row()`). `_ZeitkontoCard` `EdgeInsets.all(12)` → `context.spacing.md`.

### 6.8 Kassenbereich

Tagesabschluss (`daily_closing_screen.dart`): Kassendifferenz als glanceable `AppStatusBadge` (W3); blinde Zählung über geteiltes `cash_count_sheet`. Kassenbericht (`/kassenbericht`): KPI-Karten mit tabularen Zahlen, CSV-Export sichtbar. Umsatz/Kasse **pro Standort** (K6). Kiosk-Zählung Offline-Hinweis ehrlich, Offline-Puffer als getrenntes Paket markiert.

### 6.9 Warenwirtschaft / Laden

Interaktives Reorder-Banner (V1, B19); Artikel-Tile mit sichtbarer „In Korb"-Aktion + Swipe (B18); FAB-Kontext klar je Tab; Kühlschrank Auto-Lücken vs. manuell visuell trennen + Bulk-Abhaken; Bestellungen-Liste mit offene-Positionen-Chip + Sortierung nach Lieferdatum; Bestandskennziffern EK/VK/Spanne nicht überladen (KPI-Hierarchie, `AppStatCard`). Scanner: Häufig-bestellt-Chips auch im Buchen-Modus.

### 6.10 Kontakte

CSV-Import/Aktivität von `AlertDialog` → `AppBottomSheetScaffold` (B15/B16); alle Felder `AppFormField`; `_ContactsErrorBanner` → `AppErrorState` (B16); Filter-Chips Fade-Edge (B17); ContactPicker `DraggableScrollableSheet` statt fixer 70 %; Favorit-Icon direkt auf Karte (1 Tap); Edit-Aktion sichtbar statt erst über Detail-Sheet.

### 6.11 Anfragen / Inbox

Filter als Tabs/`AppSegmented` statt versteckt-scrollbarer Chips; gebündelte Warnungen mit „Details"-Sheet (B12); Inventory-Karten klickbar; frühe Compliance/Konflikt-Vorschau in Tausch-/Abwesenheits-Sheet (B13); `endDate = startDate` vorbelegen; Resturlaub-Vorschau auch für Mitarbeiter; Fehler via `AppErrorState` statt roher SnackBar (B14); kommende Schichten `take(6)` → „+N weitere".

### 6.12 Plan / Schicht

Admin-Board Tag-Agenda < 840 (B6); `_cleanErrorText` konsequent (B7); Monatszellen Overflow-fest (B8); Toolbar `_buildToolbarCompact()`/`_buildToolbarFull()`; `AppErrorState`/`_PlannerEmptyBoardState` bei Fehler/leer; Auto-Plan mit Diff-Feedback (welche Schichten neu); `AppShiftColorMapper` statt kollidierendem Hash. Staffing-Profil als Plan-Hub-Kachel.

### 6.13 Zeit

7-Spalten-Tabelle → Kartenliste < 840 (B9); Zeiteintrag-Defaults aus geplanter Schicht (B10); Bulk-Genehmigung statt Einzelfreigabe je Mitarbeiter (B11); Ladeindikation bei approve/reject; Jahressummen-Zeile im Stundenkonto oben; Status-Labels vereinheitlichen; ein `AppMonthPicker`.

### 6.14 Team / Verwaltung

`loeschen`→`löschen` global (B24); Editor-Sheets mit Loading/Error + Dirty-Guard (B25); Bulk-Regel-Toggle „Für alle anwenden" (B26); `AppConfirmDialog` + `mounted`-Guard für Deletes; Audit-Log Datumsbereich + gefilterter Export (B27); Member/Site-Karten sekundäre Badges auf Mobil kollabieren; alle `SizedBox`/`size:` → Tokens.

### 6.15 Kiosk

Monolith entlang `_KioskTopBar`/`_KioskBoard`/`_KioskLoginSheet`/`_PinPad` aufteilen (B28); `EdgeInsets`/`Card`/`BorderRadius.circular(999)` → Tokens/`AppCard`/`radii.pill` (B28); Stempel-Status als großer farbiger `AppStatusBadge`-Indikator (B29); Board-Kacheln „X weitere" (B30); PIN Auto-Submit + Spinner nach 4. Ziffer; Countdown rot < 10 s; `kiosk_pin_setup_sheet` → `AppFormField`.

### 6.16 Anmeldung

`auth_screen_v2.dart` ist bereits V2-Vorbild (AppCard/context.spacing/AppFormField/AppSegmented) — Kiosk-Login daran angleichen. Öffentliche Wunsch-/Feedback-Formulare (P5): kurzes Formular, ein Absende-Button, klare Bestätigung + Referenz-Code (nur `public_ui.dart`, keine Architektur-Änderung).

### 6.17 Mobile Nutzung

Primäraktionen ins untere Drittel (FAB/Bottom-Bar); Skeleton statt Spinner ab ~300 ms; `AppOfflineBanner` an Konnektivitäts-State (Feature-Paket); „zuletzt aktualisiert HH:mm" an gecachten Listen (**[Annahme]** `AppOfflineBanner` exponiert heute kein `lastUpdated` — optionalen Parameter oder eigene Fußzeile); Predictive-Back/Edge-Swipe nicht blockieren, gepushte Routen (Scanner) in `_navHistory` einbetten (B32 Avatar-Cue); `.adaptive`-Konstruktoren; Haptik sparsam; Touch statt Hover.

---

## 7. Priorisierte Roadmap

> **Status:** alle Maßnahmen **offen** (Stand 2026-07-03, reine Planung). Bei Umsetzung je Zeile fortschreiben (umgesetzt/offen/verworfen), analog zur Statustabelle des Vorgänger-Plans.

### Phase 0 — Marken-Rebrand (Fundament, MUSS vor den Modul-Rollouts)

| Maßnahme | Aufwand | Risiko | Abhängigkeit | Akzeptanz |
|---|---|---|---|---|
| `StrichTokens` in `_buildColorSchemeV2` + `AppThemeColors` verdrahten (Teal → navy/gold/paper) | M | mittel | `StrichTokens` (vorhanden) | App rendert Marken-Palette; 0 Teal-Reste (`0E7C7B`/`5FD4CE` grep = 0) |
| Kontrast-Gate (DS2) mit neuer Palette neu fahren | S | **hoch** | Theme verdrahtet | WCAG-AA grün: gelber CTA nur ink-Text, green statt openGreen für Text, gold/rose geprüft |
| `AppHeroCard`-Verlauf navy→gold; Pill-CTA = yellow+ink (§4.10 S3/S4) | S | niedrig | Theme | Hero + CTA in Markenfarbe; Dark (navy-Grund) geprüft |
| Hardkodierte Farben (`Colors.*`/Hex) → Tokens, damit der Rebrand durchschlägt | M | mittel | — | grep-Anti-Pattern (4.1) = 0 in umgebauten Screens |
| Öffentliche Seiten (`/wunsch`,`/feedback`) + Kiosk auf `StrichTokens` | S | niedrig | Theme | Markenkontakt außen = Ladenseite |

> **Warum vor allem anderen:** Der Rebrand ist eine **zentrale** Theme-Änderung — dank Token-Disziplin recolored er die ganze App auf einen Schlag; die eigentliche Arbeit steckt im Kontrast-Neu-Gate und im Aufräumen hartkodierter Farben (ohnehin Plan-Ziel). Die Modul-Rollouts (Phase 1–3) erben die Marke danach automatisch. Referenz-Screens (§4.10) zuerst umstellen und als „Golden" fixieren.

### Phase 1 — Quick Wins (Optik/Reihenfolge, risikoarm)

| Maßnahme | Aufwand | Risiko | Abhängigkeit | Akzeptanz |
|---|---|---|---|---|
| Heute: `DashboardActionItemsCard` hinter Stempeluhr, Einstempeln above fold | S | niedrig | — | Stempeln ohne Scroll auf 360 dp sichtbar |
| `loeschen`→`löschen`, Umlaut-Fixes | S | niedrig | — | 0 Treffer `loeschen` in `lib/` |
| Reorder-Banner interaktiv (V1) | S | niedrig | — | Nachbestellen 7→2 Klicks |
| `endDate = startDate`, Standort-Merken, Zeiteintrag aus Schicht | S | niedrig | — | Abwesenheit ≤ 3 Schritte |
| `take(3/6/8)` → „+N weitere" (Heute/Inbox/Kiosk) | S | niedrig | — | keine stille Kürzung |
| Error-SnackBars → `tone`/`_cleanErrorText` | S | niedrig | — | keine rohen Exception-Strings |
| Team-Kalender-Breakpoint 700→840 (`expandedWindow`) | S | niedrig | — | kein Horizontal-Scroll auf iPad |

### Phase 2 — Mittelfristige UI-Verbesserungen (Komponenten)

| Maßnahme | Aufwand | Risiko | Abhängigkeit | Akzeptanz |
|---|---|---|---|---|
| Klon→lib/ui-Migration (4.9) inkrementell | M | mittel | — | `_StatusChip`/`_StatCard`/`_EmptyState`-Klone entfernt |
| `AppMonthPicker` bauen, 6 Klone ersetzen | M | niedrig | Komponente | ein Monatspicker app-weit |
| `AppAdaptiveTable`/`AppDataList` + Tabelle→Karte < 840 | M | mittel | Komponente | keine Horizontal-Tabelle auf Handy |
| `AppFilterBar` + `AppSearchField` überall | M | mittel | Komponenten | ein Filter-/Suchmuster |
| Editor-Sheets: Dirty-Guard + Loading/Error | M | mittel | — | kein stiller Datenverlust/Speicher-Fehler |
| Kiosk V2-Angleich (Tokens/AppCard/Status) | M | mittel | — | Kiosk token-konform, Status glanceable |
| Frühe Compliance-Vorschau (W6) + Warnungen W3–W10 | M | mittel | `ComplianceService` | Warnung vor Submit |

### Phase 3 — Größere UX-Umstrukturierungen (IA/Refactoring)

| Maßnahme | Aufwand | Risiko | Abhängigkeit | Akzeptanz |
|---|---|---|---|---|
| Rollen-Dashboards (Employee/Teamlead/Admin) + Site-Umschalter | L | mittel | Phase 1/2 | ≤ 6 Blöcke je Rolle, operative KPIs |
| `shop`-Hub statt 5 Tabs, `profile`-Verwaltungs-Sektion | L | mittel | IA | Einstiege kuratiert, Employees ohne Admin-Menü |
| Gott-Screen-Schnitt entlang Hubs (Planner→Personal→Team→Home) | XL | hoch | Characterization-Tests zuerst | Verhalten unverändert, Dateien < 1500 Z |
| Kalender-Agenda-Muster (Planner/Zeit) | L | mittel | Komponenten | Agenda < 840, große Touch-Ziele |

---

## 8. Umsetzung

> **Deploy: keiner.** Dieser Plan ist reine Client-UI — kein `firestore:rules`-/`firestore:indexes`-Deploy, kein `functions`-Deploy, kein neuer Composite-Index, kein Secret/Blaze. Auslieferung ausschließlich über die normalen App-/Web-Builds (`flutter build appbundle`/`ipa`/`web`). Auch der Marken-Rebrand (Phase 0) ist reine Client-Theme-Arbeit. Feature-Anteile mit Infrastruktur (Biometrie, Konnektivität, Offline-Puffer) laufen als **getrennte** Pakete außerhalb dieses Plans.

### 8.1 Checkliste für Umsetzung (DoD je Bereich)

- [ ] Keine nackten dp/Hex/`Colors.*` — nur `context.spacing/radii/motion/iconSizes` + `appColors` (grep-Check bestanden).
- [ ] **Marke:** Farben nur aus `StrichTokens`/`appColors`; 0 Teal-Reste (`0E7C7B`/`5FD4CE`); gelber CTA nur mit `ink`-Text; Kontrast-Gate (DS2) mit neuer Palette grün.
- [ ] **Design-Signatur (§4.10):** ≥ 2 Signatur-Züge je Screen (S1 Pflicht); keine Regression hinter V2-Theme (w800, gelbe Pill-CTA, Hero-Verlauf, Ledger).
- [ ] Alle Texte Deutsch, `DateFormat` mit explizitem `'de_DE'`.
- [ ] Status = Farbe **+** Icon **+** Text (`AppStatusBadge`), nie Farbe allein.
- [ ] Genau eine Primäraktion (`FilledButton`/FAB) je Screen/Sheet, in der Daumenzone.
- [ ] Tabelle < 840 dp als Kartenliste, kein Horizontal-Scroll für Primärdaten.
- [ ] Editor-Sheets: `AppBottomSheetScaffold` + Dirty-Guard + Speicher-Spinner + Inline-Fehler.
- [ ] Fehler via `AppErrorState`/gestufte SnackBar mit Retry, `_cleanErrorText`; roh nie zeigen.
- [ ] Skeleton statt Spinner ab ~300 ms; Empty/Error/Offline-Zustände vorhanden.
- [ ] Permission-Getter gaten UI **und** Provider-Aufruf.
- [ ] `take(n)` → „+N weitere"/Drill-in ohne Tab-Wechsel.
- [ ] Multi-Site: Standort-Filter statt org-weiter Aggregation wo relevant.
- [ ] Dynamic Type bis ≥ 1.4× ohne Clipping; Reduce-Motion via `AppMotion.resolve`.
- [ ] Klon-Widgets durch `lib/ui`-Komponenten ersetzt (kein `_StatusChip`/`_StatCard`/`_EmptyState`-Duplikat).
- [ ] Keine Änderung an Provider/Service/Model/Firestore/Functions/Serialisierung.
- [ ] `flutter analyze` clean, `flutter test` grün (offline, `APP_DISABLE_AUTH=true`); auf 375 / 768 / 1280 dp geprüft, hell + dunkel.

### 8.2 Messbare Erfolgskriterien

> **Baseline-Regel:** Jede Klick-Metrik wird **einmalig vor dem Umbau** über einen definierten Klickpfad (mit `Datei:Zeile` des Einstiegs) gezählt und hier als Ist festgeschrieben; danach ist der Zielwert das Regressionsgate. Wo automatisierbar, ersetzt ein Widget-Test über [test/support/router_harness.dart](../test/support/router_harness.dart) (`pumpApp`) die manuelle Zählung — so wird „gemessen" statt „behauptet".

| Metrik | Ist (Baseline) | Ziel | Prüfung |
|---|---|---|---|
| Einstempeln erreichbar (Employee, 360×640) | hinter ~1,5 Screens Scroll (`home_dashboards_v2.dart:71`) | Stempel-CTA im ersten Viewport, 1 Tap | Widget-Test: CTA ohne Scroll sichtbar |
| Klicks bis Nachbestellen | 7 (`inventory_screen.dart:1135,1304`) | 2 | Klickpfad dokumentiert; Widget-Test Banner→Korb |
| Klicks bis Abwesenheit einreichen | 10 (Klickpfad ab Inbox/Heute) | ≤ 3 | Klickpfad dokumentiert; manuell |
| Genehmigung mehrerer Einträge | 1 Modal je Eintrag (`…/mitarbeiterabschluss_screen.dart:244`) | 1 Bulk-Aktion (≤ 50/Batch) | Widget-Test Bulk-Freigabe |
| Kachelzahl Heute je Rolle | 11 (`home_screen_tabs.dart`) | ≤ 6 | Widget-Test: max. 6 Blöcke je Rollen-Dashboard |
| Hardkodierte Farben/dp in neuen Widgets | — | 0 | grep-Check (Anti-Pattern 4.1) im Diff |
| Datentabellen als Karten < 840 dp | Horizontal-Scroll (B6/B9) | 100 % | Widget-Test: Kartenliste < 840, `DataTable` ≥ 840 |
| WCAG-AA-Kontrast neue Farbpaare | Gate grün (1 Near-Miss dokumentiert) | ≥ 4.5:1 Text / 3:1 groß+UI | Kontrast-Gate (DS2), automatisiert |
| Textskalierung ohne Clipping | gestuft 2,0/1,5 bereits live (F1, Vorgänger §0.3) | umgebaute Screens ohne Clipping bei 2,0× (dichte Raster dok. 1,5) | Golden bei 1,0 / 1,5 / 2,0 |
| Ladezustand | 32 Content-Spinner (Vorgänger-Plan) | Skeleton + `AppErrorState`-Retry | manuell + Presence-Test |
| `flutter analyze` / `flutter test` | grün | clean / grün (offline) | lokales Gate je Merge |
| Klon-Widgets entfernt | ~30 Duplikate (4.9) | 0 (`_StatusChip`/`_StatCard`/`_MonthPicker`/`_ErrorBanner`/`_EmptyState`) | grep-Check |
| Teal-Reste nach Rebrand | Teal live (`0E7C7B`/`5FD4CE`) | 0 | grep-Check |
| Kontrast-Gate neue Palette | — | WCAG-AA grün (gelb+ink, green-Text, gold/rose) | DS2 automatisiert |
| Design-Signatur je Screen | — | ≥ 2 Züge (§4.10), 0 Regressionen | Signatur-Review-Gate (nicht nur grep) |

---

**Belege der Faktenbasis (verifiziert):** Rollen & Permission-Getter [app_user.dart](../lib/models/app_user.dart); Tokens & `AppMotion.resolve`/`.tabular` [theme_extensions.dart](../lib/theme/theme_extensions.dart); Komponenten [lib/ui/](../lib/ui/ui.dart); Breakpoints 390/600/840 [responsive_layout.dart](../lib/widgets/responsive_layout.dart); Routing/Tabs [app_router.dart](../lib/routing/app_router.dart), [shell_tab.dart](../lib/routing/shell_tab.dart), [route_permissions.dart](../lib/routing/route_permissions.dart); Dashboards [home_dashboards_v2.dart](../lib/screens/home_dashboards_v2.dart), [home_screen.dart](../lib/screens/home_screen.dart); Provider-Getter [inventory_provider.dart](../lib/providers/inventory_provider.dart), [finance_provider.dart](../lib/providers/finance_provider.dart), [schedule_provider.dart](../lib/providers/schedule_provider.dart); Compliance [compliance_service.dart](../lib/services/compliance_service.dart). **Marken-Rebrand:** verbindliche Entscheidung 03.07. („Strichmännchen 1:1"); `StrichTokens` ([strichmaennchen_tokens.dart](../lib/theme/strichmaennchen_tokens.dart)) vorhanden + je Wert belegt, aber **noch nicht ins Theme verdrahtet** (Phase 0). **Gekennzeichnete Annahmen:** Teamlead-Dashboard-Zweig existiert noch nicht; `AppOfflineBanner.lastUpdated` fehlt; Kiosk-Offline-Puffer als getrenntes Feature-Paket; App-Font bleibt NotoSans (Direktive betrifft **Farbe** 1:1, nicht Typo).
