# Schichtplaner-Verbesserung: Auto-Plan-Logik, Personal-Kopplung, Überstunden, Mobile-UI

Stand: 05.07.2026 · Basis: 9-Agenten-Tiefenanalyse (Auto-Planer-Kern, Provider, Board-UI, Editor, Personal-Daten, Zeitkonto, Compliance, Mobile-Fundament + Vollständigkeits-Kritik)

## Ziel

1. **Auto-Planungs-Logik verbessern** (Fairness-Ziel ≠ Maximum, Datensammlungs-Bugs, Cap-Awareness der Lokalsuche).
2. **Personal-Kopplung**: Maximalstunden + Sollzeit + Austrittsdatum aus dem Personalbereich speisen die Planung; die Stunden-Anzeigen im Board kommen aus dem Vertrag statt aus `settings.dailyHours`.
3. **Überstunden-Planung**: Planung ÜBER die Vertrags-Maximalstunden wird nicht mehr blockiert, sondern als **geplante Überstunden** markiert (strukturiert am Shift persistiert, in Vorschau/Board/Editor sichtbar). Minijob-Grenze + gesetzliche Compliance (Ruhezeit, 10h-Tag, Pausen) bleiben **immer hart**.
4. **UI-Modernisierung mit Mobile-Fokus**: Karten-Layout für Tag/Woche unter 840 dp, 1-px-Overflow-Fix, prominenter Veröffentlichen-Button mobil, modernisierte Auto-Plan-Vorschau mit Teilübernahme, Umlaut-Bereinigung.

## Zentrale Analyse-Befunde (verifiziert, mit Beleg)

- **Kein Überstunden-Konzept**: hart-Modus blockiert (`UnassignableReason.monthlyCap/weeklyCap`, shift_auto_assigner.dart:709-718), weich-Modus erzeugt nur Freitext-Warnung; nichts wird am Shift persistiert.
- **Cap=Ziel-Vermengung**: `_computeMonthlyTarget/_computeWeeklyTarget` priorisieren `monthlyMaxHours/weeklyMaxHours` VOR der Sollzeit (shift_auto_assigner.dart:947-991) → Planer füllt Richtung Maximum statt Soll.
- **Sollzeit-Anbindung tot**: `sollzeitByUserId` wird von `proposeAutoAssignment` nie übergeben (schedule_provider.dart:719-732).
- **Duplikat-Slots**: `generatePlannedShifts` nutzt das GEFILTERTE `_shifts` als Idempotenz-Basis (schedule_provider.dart:654-658 + 2981-2991); Statusfilter versteckt offene Schichten vor Phase B (shift_planner_screen.dart:726-731).
- **Monatsgrenzen-Randfall**: Folgemonat wird nur wochenweise gesammelt → Monats-Cap/Minijob unterzählt (schedule_provider.dart:693-707). Stornierte Schichten zählen mit (749-753).
- **Lokalsuche cap-blind**: Soft-Cap-Penalty nur im Konstruktions-Score, nicht in `_userCost` (791-805 vs. 814-835).
- **Vertrag-Editor-Datenverlust (Blocker)**: `_save()` baut den Vertrag per Konstruktor neu → `monthlyGrossCents` + `validUntil` werden bei JEDEM Speichern gelöscht, `weeklyHours` mit `dailyHours×5` überschrieben (team_management_screen.dart:2303-2325).
- **Editor prüft Caps gar nicht**: manuelle Über-Max-Planung heute still möglich (loadAssigneeAvailability: nur Overlap/Abwesenheit/Compliance) — Asymmetrie zum Auto-Planer.
- **Board-Pille falsch gespeist**: Soll aus `member.settings.dailyHours×Werktage Mo–Fr` (planner_cells.dart:78-85) statt Vertrag; Standort-Zeilen dauerhaft rot (Soll 0).
- **1-px-Overflow bewiesen**: feste Höhe 78 in `_PlannerDayHeaderCell` (planner_cells.dart:107) + InkWell-Padding 10 (Z.131); Test-Harness maskiert mit textScale 0.78 (test/shift_planner_screen_test.dart:584); zweite 78 in shift_planner_screen.dart:2875.
- **Kein Handy-Pfad für Tag/Woche**: fixes 1386-px-Grid im Quer-Scroll (shift_planner_screen.dart:1440-1451); nur Monat hat Kompakt-Modus (<860, Ad-hoc statt `expandedWindow=840`).
- **Assigner-Vertragsauswahl ohne Fallback**: abgelaufener Vertrag → null → alle Caps/Minijob-Checks entfallen still (shift_auto_assigner.dart:993-998), obwohl `EmploymentContractResolver` existiert.
- **functions/index.js hat DREI Shift-Feldlisten**: parseShift (~3457), toFirestoreShift (~3543, **destruktiv**: fehlendes Feld wird bei jedem Callable-Update gelöscht), fromFirestoreShift (~3596).

## Entscheidungen

- **E1 Überstunden-Semantik**: Neues Shift-Feld `overtimeMinutes` (int, Default 0) = Plan-Metadatum „Anteil dieser Schicht über der Vertrags-Maximalstunde zum Planungszeitpunkt“. Fließt NIE ins Zeitkonto-Ist (keine Doppelzählung; Ist läuft über WorkEntries). Berechnung chronologisch pro Nutzer (stabil, reihenfolgeunabhängig) über pure Helfer `lib/core/overtime_projection.dart`.
- **E2 Org-Schalter**: `enforceHourCapHard`-Default kippt auf **false** (weich = Überstunden-Modus, vom Betreiber gewünscht). Hart-Modus bleibt wählbar (Settings-UI existiert, settings_screen.dart:1135). Gespeicherte Org-Settings gewinnen weiterhin.
- **E3 Manuelle Planung**: darf IMMER über Max (Chef-Entscheidung), zeigt aber Überstunden-Hinweis im Editor und persistiert `overtimeMinutes` beim Speichern. Auto-Planer respektiert den Org-Schalter.
- **E4 Fairness-Ziel**: Sollzeit-first (`SollzeitProfile` → `contract.weeklyHours×4,33` → erst zuletzt maxHours); Caps sind nur noch Grenze. Lokalsuche wird cap-aware (Überstunden-Penalty in `_userCost`).
- **E5 Personal→Plan-Kopplung**: PersonalProvider pusht `sollzeitProfiles` + `exitDate` (Stammakte) via Sink in ScheduleProvider (Muster wie Work→Schedule, kein notifyListeners im Setter). Schichten nach Austrittsdatum sind unzuweisbar.
  - **Sollzeit auch für Nicht-Admin-Planer (06.07.)**: `firestore.rules` sollzeitProfiles-read + PersonalProvider-Stream-Gating um `canManageShifts` erweitert — Teamleads planen mit denselben Sollzeit-Zielen wie Admins (Sollzeit = Arbeitszeitmodell, keine Lohn-/Art.-9-Daten; Stammakte bleibt admin/self-only).
  - **Bekannte Einschränkung `exitDate`**: das Austrittsdatum kommt aus der HR-Stammakte (`employeeProfiles`, bewusst admin/self-only wegen SV-/Bank-/Steuerdaten). In einer **Nicht-Admin-Planungs-Session (Teamlead)** ist `_exitDateByUserId` daher leer — die Austritts-Sperre wirkt dort nicht (ausgeschiedene MA wären wieder einplanbar). Sauberer Folgeschritt (nicht in diesem Paket): `exitDate` beim Admin-Save der Stammakte als unkritisches Planungsfeld auf `users/{userId}` spiegeln (`AppUserProfile.exitDate`, Kopplung #1: 6 Serialisierungs-Stellen) und in ScheduleProvider aus `_orgMembers` fallbacken.
- **E6 Mobile-Layout**: <`MobileBreakpoints.expandedWindow` (840) rendert Tag/Woche als vertikale Tages-Karten-Liste (Muster Team-Kalender home_screen_tabs.dart), Desktop-Grid bleibt. Monats-Kompakt-Breakpoint 860→840 vereinheitlicht.
- **E7 Kein Compliance-Spiegel-Touch** für Caps (Caps sind verifiziert KEINE Compliance-Regel); nur Umlaut-Korrekturen in Meldungs-TEXTEN werden beidseitig gezogen (Tests asserten auf `.code`).

## Meilensteine

| # | Paket | Dateien (Kern) | Status |
|---|---|---|---|
| W1 | Shift-Feld `overtimeMinutes` durch alle 6 Dart-Stellen + 3 JS-Stellen + node-Tests | shift.dart, functions/index.js, functions/test | fertig |
| W2 | Assigner-Kern: Sollzeit-first-Ziele, cap-aware Lokalsuche, Überstunden-Projektion (Proposal.overtimeMinutes), Resolver-Fallback, exitDate-Constraint; OrgSettings-Default weich; pure overtime_projection.dart | shift_auto_assigner.dart, org_settings.dart, overtime_projection.dart + Tests | fertig |
| W3 | Provider: Duplikat-Slot-Fix, ungefilterte offene Schichten, volle Monats-Sammlung beider Monate, cancelled-Ausschluss, Sollzeit/exitDate-Sink Personal→Schedule (+main.dart), overtimeMinutes bei applyAutoPlan+saveShifts, Teilübernahme-API, Cap-Projektion in loadAssigneeAvailability | schedule_provider.dart, personal_provider.dart, main.dart + Tests | fertig |
| W4 | Vertrag-Editor-Datenverlust-Fix (copyWith statt Neubau; weeklyHours nicht überschreiben) | team_management_screen.dart | fertig |
| W5 | Board-UI: Overflow-Fix (beide 78er), Harness textScale 1.0, Pille aus Vertrag/Sollzeit + Überstunden-Badge, Standort-Pille neutral, Mobile-Tageskarten-Layout Tag/Woche <840, Publish-Button mobil, Vorschau-Sheet (virtualisiert, gruppiert, Teilübernahme, Überstunden-Ausweis), Breakpoint 840 | shift_planner_screen.dart, planner_cells.dart + Widget-Tests | fertig |
| W6 | Editor: Überstunden-Hinweis je Kandidat (Cap-Projektion), keine Still-Entfernung gewählter Mitarbeiter, Standort-Pflicht als Inline-Hinweis statt „alle gesperrt“, Pause-Debounce | shift_editor_sheet.dart | fertig |
| W7 | Umlaut-Sweep Planner+Editor+compliance_service (+functions-Spiegel-Texte) | mehrere | fertig |
| W8 | Quality Gates: flutter analyze + flutter test + node --test, adversarialer Review, CLAUDE.md-Absatz (Default weich, Überstunden-Feld) | – | fertig (06.07.: analyze sauber bis auf 2 dokumentierte paketfremde Findings; flutter test 1623/1623 grün — 1 wall-clock-fragiler PA-4.1-Test `clock_open_guard_test.dart` deterministisch gemacht; node --test 72/72; CLAUDE.md aktualisiert) |

## Kopplungs-Checkliste (aus CLAUDE.md)

- Kopplung #1: `overtimeMinutes` → 6 Dart-Stellen + parseShift/toFirestoreShift/fromFirestoreShift (`overtime_minutes` snake_case im Callable-Payload!).
- Kopplung #2: Compliance-Schwellen unverändert; Meldungs-Texte (Umlaute) beidseitig.
- Kopplung #5: Shift läuft bereits über lokale Persistenz (`toMap/fromMap` round-trip testen).
- Kopplung #6: Rules erlauben direkte Writes — `overtimeMinutes` ist unkritisches Metadatum, kein Rules-Update nötig.

## Deploy / offen nach Code

- `firebase deploy --only functions` (parseShift/toFirestoreShift/fromFirestoreShift erweitert) — ohne Deploy löscht der Callable-Pfad das neue Feld bei jedem Update (toFirestoreShift ist destruktiv!). Bis dahin trägt nur der Direkt-Write-/Local-Pfad das Feld.
- Kein neuer Composite-Index (keine neue where+orderBy-Query geplant).
- Nicht in Scope (bewusst): Wochenend-/Nacht-Rotations-Fairness, Konsekutiv-Tage-Limit, Slot-Generator-Idempotenz bei geänderter Schichtlänge, Sollzeit-Pflege-UI (Tagessoll-Editor), Überstunden-Ausweis im Monatsreport/Zeitkonto-Snapshot.
