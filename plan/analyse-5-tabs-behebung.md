# Analyse & Behebungsplan: 5 Haupt-Tabs (Heute · Plan · Anfragen · Kontakte · Laden)

> Stand: 01.07.2026 · Quelle: Multi-Agent-Tiefenanalyse (9 Analyse-Einheiten × 2 Lenses
> [funktional + Handy-UI] + adversariale Verifikation aller schweren Befunde).
> Betrifft die Shell-Tabs `today` `/`, `plan` `/plan`, `inbox` `/anfragen`,
> `contacts` `/kontakte`, `shop` `/laden` (+ geteilte Shell-Chrome).

## 0. Umsetzungsstand (01.07.2026) — ALLE Meilensteine umgesetzt ✅

M1–M6 vollständig umgesetzt; `flutter analyze` ohne neue Issues (2 verbleibende Warnungen sind
Baseline: `analysis_options.yaml`-`removed_lint` + vestigialer `onNavigateBack`-Param an `_TimeTrackingTab`),
**alle 1246 Tests grün**. Neue Datei `lib/core/hex_color.dart` (`tryParseHexColor`). Kernänderungen:

- **M1** Avatar-`RangeError` + zentraler `tryParseHexColor` (Board+Zellen) + Bestand beim Bearbeiten read-only (keine stille Überschreibung ohne Bewegung).
- **M2 (Q1)** try/catch + Erfolg-nur-bei-Erfolg über Warenwirtschaft/Kundenbestellungen/Plan-Abwesenheit; `WorkProvider.clockIn/clockOut/correctClockEntry` werfen bei fehlender Berechtigung statt still zu returnen.
- **M3** Serien-Dropdown entfernt (Read-only-Hinweis), „Veröffentlichen" auf **eine** Aktion, Kontakte-Fehlerbanner, 50er-Kopiergrenze, Schicht-Lösch-Bestätigung, Auto-Plan-Spinner, Q5-Entscheidungskacheln antippbar (V2), Kleinbugs (Zeitausgleich-Validierung, Über-Mitternacht-Korrektur, wiederkehrende Bestellung immer in Zukunft, Autocomplete-Controller, BEGINN/ENDE, `destructive:false`, Kühlschrank-Aktion, „Alle anzeigen", Umlager-Validierung).
- **M4** `InfoChip` (Wurzel-Overflow-Fix), Header/TabBar (`isScrollable`)/AppBar-Auswertungsmenü/Position-Dialog + medium-Overflows (Statuspille, Wochenfortschritt, Status-Banner, Rail-`minWidth`, V2-Wochenstreifen).
- **M5** Touch-Ziele ≥40–48dp (Board-Popup, Toolbar-Nav, Warenkorb-Stepper, Breadcrumb, Kalender, Zeitpicker, Aktionszeilen) + BottomNav-Text-Scaling 1.0→1.3.
- **M6** V2-Hero → `zeitStempeln` (kein Schicht-Gate), ASCII→echte Umlaute, FutureBuilder-Fehlerhinweis, Aktivität rückdatierbar, Export-Menü bei leer deaktiviert.

**Ehemals offene Punkte — jetzt ebenfalls erledigt:**
- **redesign_v2 ist Code-Default:** `RedesignFlags.defaultEnabled = true`, angewandt an allen 3 Fallback-Stellen (`isOn`/`isOnRead` + `main.dart`-Theme). V2 ist damit ohne org-Flag live; eine Org kann per explizitem `redesign_v2: false` bei V1 bleiben. Test-Harness (`router_harness.pumpApp`) schreibt das Flag jetzt explizit (`flagOn`), damit V1-Tests deterministisch bleiben; 2 Tests auf neuen Default angepasst.
- **Push bei „Veröffentlichen" ist real (kein Fake):** Der Server-Trigger `onShiftWritten` (`functions/index.js:488`) sendet beim Übergang `planned → confirmed` je zugewiesenem Mitarbeiter eine echte Benachrichtigung (`buildShiftPublishedNotification`, In-App-`notifications`-Doc + FCM, pro Woche gebündelt). Der Client-Publish schreibt `confirmed` → Trigger feuert. Die 3 alten Menü-Optionen waren nur redundant/irreführend (das Finding hatte den Trigger übersehen); jetzt 1 ehrliche Aktion + ehrliche Erfolgsmeldung („… Mitarbeiter werden benachrichtigt").

Rein operativ offen (kein Code): **`firebase deploy --only functions`** (Trigger/Callables scharfschalten, Blaze) + optional Metrik-Kachel-Tap (bewusst verworfen — redundant zu den Entscheidungskacheln).

---

## 1. Scope & Methode

Analysiert wurden pro Tab die tatsächlich gerenderten Screens (siehe `buildHomeTab` in
`lib/screens/home_screen.dart:1343`):

| Tab | Screen(s) | Einheit(en) |
|---|---|---|
| **Heute** `/` | `_AdminDashboardTab`/`_EmployeeDashboardTab` (V1, `home_screen_tabs.dart`) · `…V2` (`home_dashboards_v2.dart`) — **redesign_v2 ist Default AUS → V1 ist live** im Offline/Demo | 2 |
| **Plan** `/plan` | `ShiftPlannerScreen` (`shift_planner_screen.dart`, 6.1k Z.) + `shift_planner/` (Editor-Sheet 3.6k Z., Zellen) | 2 |
| **Anfragen** `/anfragen` | `NotificationScreen` (`notification_screen.dart`) | 1 |
| **Kontakte** `/kontakte` | `ContactsScreen` (`contacts_screen.dart`) | 1 |
| **Laden** `/laden` | `_ShopHubTab` (Hub) → Warenwirtschaft (`inventory_screen.dart` 103 KB), Kundenbestellungen (`customer_order_screen.dart`), Warenkorb, Bestell-Auswertung | 2 |
| **(Shell)** | Cross-cutting Nav/Chrome (BottomNav↔Rail, `InfoChip`, Breadcrumb, `SectionHeader`) | 1 |

**151 Befunde** insgesamt (76 funktional, 75 Handy-UI). Verteilung: **24 high · 49 medium · 78 low**.
Alle 24 high-Befunde wurden adversarial gegengeprüft: **18 bestätigt, 6 widerlegt/herabgestuft**
(siehe §7 — Flutter-Constraint-Modell-Missverständnisse, die wir bewusst NICHT anfassen).

Kategorien: 31 bug · 28 responsiveness · 23 overflow · 21 missing_ui · 18 improvement ·
15 touch_target · 7 keyboard_safearea · 3 pointless_ui · 3 accessibility · 2 unimplemented.

> Vollständige Roh-Befundliste (alle 151, mit Belegen): siehe Anhang-Dump
> `scratchpad/all_findings.md` (nicht versioniert) — dieser Plan destilliert das Handlungsrelevante.

---

## 2. Querschnitts-Muster zuerst (größter Hebel — einmal fixen, viele Befunde erledigt)

Diese Muster wiederholen sich über mehrere Tabs. Sie zuerst zu beheben räumt ~40 Einzelbefunde ab.

### Q1 — „Erfolg gemeldet, obwohl der Mutator still scheiterte" (systemisch, **P0/P1**)
Mehrere Handler `await`en einen Provider-Mutator **ohne try/catch** und zeigen danach
**unbedingt** eine Erfolgs-Snackbar. Zwei Fehlerquellen:
- **cloud-only-Modus** (`usesHybridStorage == false`): Mutator `rethrow`t → im Handler unbehandelte Exception, Snackbar teils trotzdem/vorher.
- **stiller `return` bei fehlender Berechtigung** (`work_provider.dart` `clockIn`/`clockOut`/`correctClockEntry` kehren bei `!canEditTimeEntries` ohne Exception zurück) → UI zeigt „gestempelt", obwohl nichts passierte.

Betroffen (bestätigt): Warenwirtschaft `_edit`/`_adjust`/`_stocktake`/Supplier-`_edit`
(`inventory_screen.dart:1320+`), Kundenbestellungen `_onMenu`-Status + `_edit`
(`customer_order_screen.dart:660,706`), Plan „Abwesenheit melden" (`shift_planner_screen.dart:1176`),
Stempeluhr V1 (`home_screen_tabs.dart:2104,452` ↔ `work_provider.dart:1161,1342`).

**Fix (Standardrezept, wie `_addProduct`/`_addOrder` es bereits richtig machen):**
```dart
try {
  await provider.mutate(...);
  if (!context.mounted) return;
  _showSnack('… gespeichert');          // NUR im Erfolgsfall
} catch (e) {
  if (!context.mounted) return;
  _showSnack('Fehler: $e');             // deutsch
}
```
Plus: Stempel-/Korrektur-Buttons zusätzlich an `canEditTimeEntries` gaten **oder**
`clockIn/clockOut/correctClockEntry` ein Ergebnis zurückgeben lassen (kein „return ohne Rückmeldung"
auf nutzer-ausgelöstem Pfad).

### Q2 — `InfoChip` ohne Überlaufschutz (1 Widget, ~24 Aufrufstellen, **P2**)
`lib/widgets/info_chip.dart:29-42` rendert das Label als reinen `Text` in einer `Row(mainAxisSize.min)`
**ohne** `Flexible`/`maxLines`/`ellipsis`. In einem `Wrap` bekommt der Chip unbegrenzte Breite →
lange Standortnamen („Strichmännchen Kiel Innenstadt", „Tabak Börse Holstenstraße") oder
Text-Scaling ≥ 1.3 sprengen 320pt (iPhone SE) / 360dp. Trifft V2-Hero
(`home_dashboards_v2.dart:265`) und die Shell.
**Fix:** Label in `Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis))`.
Ein Fix → 3 Befunde weg. Nebeneffekt: das duplizierte `_HeaderChip` in `app_nav_menu.dart`
wird obsolet und kann auf `InfoChip` zusammengeführt werden.

### Q3 — Touch-Targets < 48 dp (15 Befunde, **P3**)
Material/WCAG-Mindestmaß 48×48 dp wird an vielen dichten Tap-Zielen unterschritten. Häufigstes
Muster: `IconButton`/`PopupMenuButton` mit `padding: EdgeInsets.zero` + `constraints: const BoxConstraints()`
+ `visualDensity: compact`. Schlimmster Fall: Board-Schichtkarten-`more_horiz` mit **~16 px**
(`planner_cells.dart:234`).
**Fix (Rezept):** `constraints: const BoxConstraints(minWidth: 48, minHeight: 48)`,
`visualDensity.compact` an frei stehenden Tap-Zielen entfernen, Icon-Größe ≥ 20.
Betroffen: Planer-Popup + Toolbar-Nav (`shift_planner_screen.dart:3828`), Warenkorb-Stepper
(`order_cart_screen.dart:959`), Breadcrumb-Zurück (`breadcrumb_app_bar.dart:125`),
Mehrtage-Kalenderzellen (`shift_editor_sheet.dart:517`), Dashboard-Aktionszeilen
(`dashboard_action_items_card.dart:177`), Zeitpicker im Korrektur-Dialog (`home_screen_tabs.dart:523`).

### Q4 — Leerer String → `substring(0,1)`-Crash (**P0**)
`''.substring(0, 1)` wirft `RangeError`. `Shift.employeeName` ist bei **unbesetzten** Schichten leer
(`(map['employee_name'] ?? '')`), `displayName` kann leer sein.
- `shift_planner_screen.dart:4814` `CircleAvatar(Text(shift.employeeName.substring(0,1)))` — **bestätigt high**, rendert für freie Schichten im Nicht-Admin-Fallback & Monatsdetail.
- `home_screen.dart:1200` Shell-Initial aus leerem `displayName`.
**Fix:** `name.isEmpty ? '?' : name.characters.first.toUpperCase()` (Muster existiert bereits in
`_PlannerBoardRowData.fallbackEmployee`).

### Q5 — „Nur-Anzeige"-Kacheln, die Handlungsbedarf zeigen aber nicht auflösen (**P1**)
Admin-Dashboard (V1 **und** V2): „Heute priorisieren" / „Nächste Entscheidungen"
(`home_dashboards_v2.dart:715`, `home_screen_tabs.dart:1067`, Tiles in `home_screen.dart:2299`)
zeigen „X Entscheidungen offen", sind aber **nicht antippbar** — der Admin muss selbst zum
Anfragen-Tab wechseln.
**Fix:** Tiles `onTap` → `context.go(shellTabPaths[ShellTab.inbox]!)` bzw. direkt ins Antrags-Detail.

---

## 3. Priorisierte Arbeitspakete

### P0 — Abstürze & Datenintegrität (zuerst, klein, hoher Impact)
1. **Avatar-RangeError bei leerem `employeeName`** — `shift_planner_screen.dart:4814` (Q4). *high, bestätigt.*
2. **Farb-Parse crasht Board** — `Color(int.parse(shift.color!…))` wirft `FormatException` bei
   fehlerhaftem Hex (Import/Altdaten/Firestore-Edit). Betrifft `shift_planner_screen.dart:4670`
   **und** `planner_cells.dart:471` (zeichnet **jede** Board-Karte).
   **Fix:** zentrale `Color? tryParseHexColor(String?)` (mit `int.tryParse` + Längen-Check 6/8) einführen,
   beide Stellen darauf umstellen. *high, bestätigt.*
3. **Artikel-Editor überschreibt Live-Bestand ohne Bestandsbewegung** —
   `inventory_screen.dart:2015` setzt `currentStock` direkt in `copyWith` → umgeht `adjustStock`/
   `recordStocktake` (die `StockMovement`+Audit buchen) → inkonsistente Historie/Warenwert.
   **Fix:** Bestandsfeld beim **Bearbeiten** read-only/ausblenden (Änderung nur über
   „Bestand korrigieren"/„Inventur"), **oder** `currentStock` in `saveProduct` analog zu `fridgeStock`
   aus dem Merge nehmen. *high, bestätigt.* → Kopplung: `inventory_provider.dart:967`,
   `firestore_inventory_repository.dart:224`.

### P1 — Funktionale Bugs & stille Fehler
4. **Q1-Rezept** flächendeckend anwenden (Warenwirtschaft, Kundenbestellungen, Plan-Abwesenheit,
   Stempeluhr) — try/catch + Erfolg-nur-bei-Erfolg + Permission-Gate.
5. **Wiederholungs-Dropdown ist tot** — im Editor nur im Edit-Modus sichtbar und dort `onChanged: null`;
   für Neuanlage fehlt es, `_recurrenceEndDate` bleibt `null`, aber `buildShiftOccurrences` expandiert
   nur bei Neuanlage (`shift.id == null`). **Folge: über den Editor kann NIE eine Serie entstehen.**
   `shift_editor_sheet.dart:2840`. **Fix:** Feld für Neuanlage aktivieren (inkl. Enddatum-Picker) **oder**
   tot entfernen und Wiederkehr allein über den Mehrtage-Picker führen (Entscheidung nötig, §9).
6. **„Veröffentlichen"-Trilemma ist Fake** — drei Menüpunkte (melden / alle benachrichtigen / ohne
   Benachrichtigung) rufen alle dieselbe `_publishVisibleShifts`; **keine** Benachrichtigung wird
   versendet (`shift_planner_screen.dart:2002`). **Fix:** auf **eine** Aktion reduzieren, bis Push
   angebunden ist (`fanOutPush` in `functions/index.js:150` existiert) — sonst verspricht die UI etwas,
   das nicht passiert.
7. **Q5** — Entscheidungs-Kacheln antippbar machen (V1+V2).
8. **Fehler-Banner fehlt in Kontakte** — `ContactProvider` hat `errorMessage`/`clearError`, aber
   `ContactsScreen` liest es nie → Ladefehler erscheint als irreführender „Noch keine Kontakte"-Leerzustand.
   `contacts_screen.dart:135`. **Fix:** Inline-Banner + Leer-vs-Fehler unterscheiden (Muster wie
   `inventory_screen`).
9. **Kopier-Sheet ohne 50er-Grenze** — `_CopyShiftSheet` lässt beliebig viele Kopien zu; > 50 chunkt in
   nicht-atomare Server-Calls (Teil-Write bei Compliance-Fehler). Editor prüft `_kMaxShiftsPerSave`,
   das Kopier-Sheet nicht (`shift_editor_sheet.dart:684`). **Fix:** Button ab `copyCount > 50` sperren
   + deutsche Meldung.
10. **Kleinere Bugs:** Zeitausgleich-Stunden ohne Validierung absendbar (`notification_screen.dart:2112`);
    Korrektur-Dialog bricht bei Über-Mitternacht-Einträgen (`home_screen_tabs.dart:581`);
    wiederkehrende Kundenbestellung kann Folgetermin in der Vergangenheit setzen
    (`inventory_provider.dart:2345`); Autocomplete-Warengruppe überschreibt Controller bei jedem Rebuild
    (`customer_order_screen.dart:1262`); englische Labels `STARTS/ENDS` im deutschen Stempel-Widget
    (`home_screen_tabs.dart:320`); roter „Gefahr"-Button für harmlose Import/Dedup-Bestätigung
    (`contacts_screen.dart:511`, `destructive:false`).

### P1b — Fehlende UI (erwartete, aber fehlende Elemente)
11. **Kein Bestätigungsdialog vor „Schicht löschen"** — Board (`shift_planner_screen.dart:3638`) und
    Karten-Popup (`planner_cells.dart:243`); beim Serienlöschen zusätzlich Anzahl betroffener anzeigen.
    (Urlaub-Löschen hat den Dialog bereits — Muster übernehmen.)
12. **Kein Ladeindikator während Auto-Planung** (potenziell langsam) — `shift_planner_screen.dart:746`.
13. **Kühlschrank-Todo** hängt dauerhaft in „Zu erledigen" ohne Aktion — `notification_screen.dart:907`
    (Navigations-Aktion „Zum Kühlschrank" ergänzen).
14. **Kontakthistorie auf 8 gedeckelt** ohne „Alle anzeigen" — `contacts_screen.dart:1225`.
15. **Umlagern ohne Mengen-Validierung** gegen Zielbestand — `inventory_screen.dart:2295`.

### P2 — Handy-Overflow / Responsiveness (echte Bruchstellen ≤ 393pt / bei Text-Scaling)
16. **Q2 — InfoChip** (Wurzel-Fix, §2).
17. **Header „Offene Abwesenheitsanträge" bricht** ohne `Flexible`/`ellipsis` —
    `home_screen_tabs.dart:813`. *high, bestätigt.* Langes Wort passt auf 320/375pt nicht in eine Zeile.
18. **5er-`TabBar` ohne `isScrollable`** in Warenwirtschaft → Labels „Kühlschrank/Lieferanten"
    abgeschnitten, Badges kollidieren (`inventory_screen.dart:293`). **Fix:** `isScrollable: true`
    + `tabAlignment: TabAlignment.start`.
19. **Warenwirtschafts-AppBar mit bis zu 7 Action-Icons** — auf Handybreite überladen
    (`inventory_screen.dart:190`). **Fix:** Analyse-Aktionen (Insights/Sortiment/Benchmark/Auswertung)
    in ein „Auswertungen"-`PopupMenu` bündeln.
20. **Position-Dialog Menge/Einheit/Preis** — 3 Felder in einer `Row` zu eng ≤ 380pt
    (`customer_order_screen.dart:1273`). **Fix:** auf schmalen Breiten 2-zeilig umbrechen.
21. **Weitere Overflow-/Responsiveness-Stellen** (medium): Stempeluhr-Statuspill + Korrigieren-Row
    ohne `Flexible` (`home_screen_tabs.dart:288,382`); Wochenfortschritt-Kopf (`:697`);
    V2-Wochenstreifen feste Höhe 110 (`home_dashboards_v2.dart:366`); Kontakte-Statistik 3 Karten
    auf 320pt (`contacts_screen.dart:719`); Mitarbeiter-Zeile 154px fix + Board-Tageszelle 176px fix
    (`shift_planner_screen.dart:3029,1426`); V1-Rail 96px-Profil-Header überläuft 72px-Rail
    (`home_screen.dart:1275`); Status-Banner „Jetzt synchronisieren" (`home_screen.dart:1634`);
    `_CartItemTile` fixe Trailing-Breite (`order_cart_screen.dart:890`);
    `TableCalendar` enge cellMargins auf 320pt (`home_screen_tabs.dart:2406`).

### P3 — Touch-Targets & Accessibility
22. **Q3-Rezept** an allen 15 Stellen (§2).
23. **BottomNav-Labels gegen Text-Scaling geklemmt** (`maxScaleFactor: 1.0`) — Accessibility-Verstoß,
    `home_screen.dart:414`. **Fix:** moderater Deckel (z.B. 1.3) + `ellipsis`.

### P4 — Verbesserungen / Politur
24. **Doppelte Stempel-UI vereinheitlichen** — V1 & V2 zeigen Hero-Button *und* `_ClockInOutWidget`,
    die **unterschiedliche** Provider (`ZeitwirtschaftProvider.isClockedIn` vs.
    `WorkProvider.hasActiveClockSession`) bedienen und ihren Clock-State **nicht teilen**
    (`home_screen.dart:1987` + `home_screen_tabs.dart:151`; Paar auch in V2). Auf **eine** Quelle der
    Wahrheit konsolidieren; V2-Hero auf den `zeitStempeln`-Pfad wie V1 ziehen (Header-Kommentar
    „byte-gleich zu V1" ist derzeit falsch). *Ursprünglich high, verifiziert → medium.*
25. **ASCII-Transliteration → echte Umlaute** in `home_dashboards_v2.dart` (52 Stellen: „Naechste",
    „moeglich", „pruefen") — steht direkt neben Karten mit korrekten Umlauten. Reiner Textfix.
26. **FutureBuilder verschluckt Ladefehler still** (`home_dashboards_v2.dart:471`, `snapshot.hasError`
    nie geprüft) → dezenter Hinweis statt stiller Ausblendung.
27. **Aktivität rückdatierbar machen** (`contacts_screen.dart:599`, Datum hart `now()`);
    **Export-Menü** deaktivieren wenn keine Bestellungen (`customer_order_screen.dart:164`);
    Metrik-Kacheln im Admin-Dashboard antippbar (`home_dashboards_v2.dart:679`).

---

## 4. Bereichsweiser Kurzbefund

- **Heute (V1 live / V2 latent):** solide, aber zwei parallele Stempel-Systeme (P4-24) und
  „nur Anzeige"-Entscheidungskacheln (Q5). Handy: Header-Overflow (P2-17), Statuspills ohne `Flexible`.
  V2 zusätzlich ASCII-Umlaute (P4-25) und doppelte Einstempeln-UI.
- **Plan:** funktional am dichtesten — **zwei Crash-Klassen** (Avatar, Farbe = P0), totes
  Wiederholungs-Feld (P1-5), Fake-„Veröffentlichen" (P1-6), fehlende Lösch-Bestätigung (P1b-11),
  kein Auto-Plan-Spinner. Handy: feste Spaltenbreiten (154/176px), Mini-Touch-Targets.
- **Anfragen:** am saubersten (nur 10 Befunde, keine high). Kleinere: Zeitausgleich-Validierung,
  Kühlschrank-Todo ohne Aktion.
- **Kontakte:** funktional ok; **Fehler-Banner fehlt** (P1-8), Historie gedeckelt, Aktivität nicht
  rückdatierbar. Handy: Statistik-Row eng.
- **Laden:** **Bestand-Überschreib-Bug (P0-3)** + flächendeckend fehlende Fehlerbehandlung (Q1).
  Handy: 5er-TabBar (P2-18), überladene AppBar (P2-19), enge Steppers/Dialoge.

---

## 5. Verifikation — was NICHT angefasst wird (6 widerlegte high-„Overflow")

Der adversariale Check hat 6 als „high overflow" gemeldete Befunde als **Missverständnisse des
Flutter-Constraint-Modells** entlarvt — hier **keine** Änderung nötig:
- `SizedBox(width: 460/420)` **im `AlertDialog.content`** erzwingt **keinen** Overflow — der Dialog
  klemmt den Content auf die verfügbare Breite (Import-Dialog `contacts_screen.dart:462`,
  Artikel-Dialog `inventory_screen.dart:1735`).
- `SegmentedButton` „Mitarbeiter/Freie Schicht" bricht auf 320pt **nicht** (`shift_editor_sheet.dart:2173`).
- `AlertDialog` weicht der **Tastatur** eigenständig aus — Artikel-/Lieferanten-Dialoge sind ok
  (`inventory_screen.dart:1733`).
- Abwesenheits-Sheet-Tastatur-Padding: Beleg beruhte auf erfundenem Code — **kein** Bug
  (`shift_planner_screen.dart:1160`).
- „In den Bestellkorb" zeigt **keinen** falschen Erfolg (der Kern-Vorwurf war falsch) — herabgestuft auf
  low; das echte Restrisiko (cloud-only ohne try/catch) ist über **Q1** abgedeckt.

> Konsequenz für die Umsetzung: Feste Dialogbreiten sind hier **kein** Overflow-Grund. Die *echte*
> Enge (medium) liegt in mehrspaltigen Feld-`Row`s (P2-20) und Touch-Targets — dort ansetzen.

---

## 6. Empfohlene Reihenfolge (Meilensteine)

- **M1 — P0 (½ Tag):** #1 Avatar, #2 Farb-Parse (`tryParseHexColor`), #3 Bestand-Überschreiben.
  Klein, crash-/datenkritisch, isoliert testbar.
- **M2 — Q1-Rezept (P1, 1 Tag):** try/catch + Erfolg-nur-bei-Erfolg + Permission-Gate über
  Warenwirtschaft/Kundenbestellungen/Plan/Stempeluhr. Ein Muster, viele Callsites.
- **M3 — Funktionale Lücken (P1/P1b, 1 Tag):** #5 Wiederholung (Entscheidung §9), #6 Veröffentlichen,
  #8 Kontakte-Banner, #9 50er-Grenze, #11 Lösch-Bestätigung, #12 Auto-Plan-Spinner, Q5-Kacheln.
- **M4 — Handy-UI (P2, 1 Tag):** Q2 InfoChip (Wurzel), #17 Header, #18 TabBar, #19 AppBar-Menü,
  #20 Position-Dialog, + medium-Overflow-Stellen.
- **M5 — Touch/A11y (P3, ½ Tag):** Q3-Rezept + BottomNav-Text-Scaling.
- **M6 — Politur (P4):** Stempel-UI-Konsolidierung, Umlaute, FutureBuilder-Fehler, Kleinkram.

## 7. Definition of Done / Hinweise

- Nach jedem Meilenstein: `flutter analyze` + `flutter test` grün; Offline-Smoke
  `flutter run --dart-define=APP_DISABLE_AUTH=true`.
- **Overflow-Regression sichtbar machen:** Golden-/Widget-Tests bei 320pt (iPhone SE) und
  `textScaler: 2.0` für die gefixten Screens (Header, TabBar, InfoChip) — sonst kommen die
  Overflows unbemerkt zurück.
- **Kein Deploy nötig** für P0–P4 (reine Client-/UI-Änderungen). **Ausnahme:** echter Notify-Modus
  bei #6 bräuchte Function-Anbindung (`fanOutPush`) → separater Blaze-Schritt, hier bewusst
  ausgeklammert (erst UI ehrlich machen).
- Deutsch-only, `appColors` statt Hex-Statusfarben, `MobileBreakpoints`/`screenPadding` respektieren.

## 8. Getroffene Entscheidungen (01.07.2026)

1. **Wiederholung/Serien (#5): TOT ENTFERNEN.** Das Wiederholungs-Feld wird aus dem Editor entfernt;
   Wiederkehr läuft ausschließlich über den Mehrtage-Picker. Bei bestehenden Serien nur eine
   **Read-only-Anzeige** (z. B. „Wiederholung: <Muster>"), kein editierbares Dropdown mehr.
2. **Stempel-UI (#24): Hero → Stempel-Screen.** Der Hero-Stempelbutton navigiert zu
   `AppRoutes.zeitStempeln` (`ZeitwirtschaftProvider.isClockedIn`), das inline `_ClockInOutWidget`
   bleibt die einzige Inline-Uhr. Kein `activeShiftNow`-Gate mehr; V2-Hero
   (`home_dashboards_v2.dart:283`) auf denselben Pfad ziehen wie V1 es meint.
3. **Fokus NUR auf V2 — V1-Dashboards nicht mehr anfassen.** `redesign_v2` gilt als Go-Forward.
   **⚠️ Wichtige Abgrenzung (nicht falsch verstehen):** V2 (`home_dashboards_v2.dart`) **rendert
   geteilte Widgets aus `home_screen_tabs.dart` wieder** — laut V2-Header „bewusst unverändert
   wiederverwendet": `_ClockInOutWidget` (`:204`), `_PendingAbsencesWidget` (`:790`),
   `_WeeklyProgressWidget`. **Deren Befunde bleiben in Scope**, weil V2 sie zeigt:
   - #4/Q1 Stempel-Erfolg-ohne-Berechtigung, STARTS/ENDS-Labels, Korrektur-Dialog (Über-Mitternacht,
     Erfolg-ohne-Berechtigung, Touch-Targets, Tastatur-Insets) — alle in `_ClockInOutWidget` → **fixen**.
   - P2-17 „Offene Abwesenheitsanträge"-Header-Overflow (`home_screen_tabs.dart:813`) — in
     `_PendingAbsencesWidget`, von V2 gerendert → **fixen**.
   **Außer Scope (nur-V1):** die reinen Dashboard-Shells `_EmployeeDashboardTab`/`_AdminDashboardTab`
   (`home_screen_tabs.dart:12/875`) und der V1-Fallback-Pfad in `buildHomeTab`. Konkrete V2-Aufgaben:
   ASCII→Umlaute (#25), Hero-Stempel-Pfad (#2), Metrik-/Entscheidungs-Kacheln antippbar (Q5/#27),
   FutureBuilder-Fehler (#26), V2-Wochenstreifen feste Höhe 110 (P2-21).
   **Folge-To-do:** `redesign_v2`-Flag produktiv **einschalten** (org-Flag `appFlags.redesign_v2` bzw.
   Override), damit V2 überhaupt live ist — sonst laufen die Fixes ins Leere.
