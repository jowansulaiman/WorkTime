# Personalbereich — UI/Tabs genau 1:1 wie AllTec

**Stand:** 2026-07-04 · **Status:** **M1–M11 fertig+verifiziert; alle 9 Tabs gefüllt; committet + auf `main` + gepusht** (nur M12-Deploy offen) · **Priorität:** hoch
**Auftrag (Betreiber):** „Das Design bzw. die UI des Personalbereichs soll genau 1:1 wie in AllTec sein — die Tabs."

**Umsetzungsstand (2026-07-04):**
- **M1** (Routing + Sicherheit): Route `/personal/:id` + `personalDetailPath`, explizite GoRoute, Admin-Gate. **Sicherheitsfund geschlossen** (Deep-Link war `default:true` → admin-only).
- **M2** (Detail-Gerüst): `employee_detail_screen.dart` — VCard + scrollbare 9-Tab-TabBar (exakte AllTec-Reihenfolge), Admin-/Lade-/Not-Found-Zustand; Listen-Karte navigiert per `context.push`.
- **M3** (Reuse): `lib/widgets/info_row.dart` (öffentliches `InfoRow`) + `lib/widgets/summary_card_row.dart` (responsive KPI-Reihe auf `AppMetricCard`). FilterBar → mit M10.
- **M4** (Tabs mit voller Datenlage): **Kinder** (voll CRUD, `+anmerkungen`-Feld an `EmployeeChild` für Parität), **Dokumente** (reuse `EmployeeDocumentsCard`), **Übersicht** (read-only: Status-Badges + 4 KPI-Karten + Info-Karten). Unter `lib/screens/personal/tabs/`.
- **M5** (Quali/Ausbildung, volle Feld-Parität): **Qualifikationen** (`EmployeeQualification` +`qualifikationsart`/`beschreibung`/`zertifikatNr`/`ausstellendeStelle`) + **Ausbildungen** (`EmployeeAusbildung` +`ausbildungsart`/`ausbildungsstaette`/`fachrichtung`/`abschluss` + neues `AusbildungStatus`-Enum fürs Status-Badge). Beide voll CRUD, je 6 Serialisierungsstellen + Round-Trip-/Enum-Tests.

- **M6** (Stammdaten-Parität, größter Feld-Milestone): `EmployeeProfile` +22 Felder + 2 Enums (`Erwerbsart`, `KuendigungsfristTyp`) + 15 gezielte `clearX`-Flags (nur für die per-Abschnitt-Editoren). **DSGVO Art. 9 bewusst weggelassen** (GdB/Flüchtling/Aufenthalt) + `leitenderAngestellter` via `PersonnelGroup`. Tab **Stammdaten** = 4 Read-Karten (Stammdaten/Status & Vereinbarungen/Klassifizierungen/Arbeitszeit) + 3 Editor-Dialoge (Arbeitszeit read-only, Quelle SollzeitProfile). Round-Trip-/clearX-Tests + Render-Test.

- **M7** (Gehalt-Parität): 3 neue eingebettete Nebenobjekte (`VwlData`, `SalaryAllowance`, `BankAccount` in `lib/models/payroll_extras.dart`, je volle Zwei-Serialisierung analog `PayrollLine`) + 5 `EmployeeProfile`-Felder (`entgeltgruppe`, `gehaltGueltigAb`, `vwl`, `zulagen`-Liste, `bankAccounts`-Liste). Tab **Gehalt** = 4 Karten (Gehaltsdaten/VWL/Zulagen/Bankverbindungen) + 4 Dialoge; Gehaltsdaten-Dialog schreibt `PayrollProfile` **und** `EmployeeProfile`, Brutto/Stundensatz read-only aus Vertrag.

- **M10** (Top-Level-Umbau, **sichtbare Änderung**): `PersonalScreen` öffnet jetzt direkt in die Personalverwaltungs-Liste (`_MonthBar` + `_OverviewTab`: Kennzahlen + Mitarbeiter-Karten → 9-Tab-Detail) statt der 5 Aggregat-Tabs. Die org-/monatsweiten Auswertungen (Aufträge/Lohn/Finanzen/Statistik) sind **erhaltend verlagert** in `_PersonalAuswertungenScreen`, erreichbar über die „Auswertungen"-AppBar-Aktion (`insights_outlined`). Nicht destruktiv. personal_screen-Tests angepasst. (Offen als spätere Politur: SummaryCardRow/FilterBar-Suche exakt wie AllTec.)

- **M9** (Verwalten): Tab mit Aktiv-Umschalter (`TeamProvider.updateMember(isActive:)`) + Beschäftigungsstatus-Dropdown (`saveEmployeeProfile(status)`) + Gefahrenzone („Löschen" = **Deaktivieren-Alias**, sicher/reversibel) + Meta-IDs.
- **M8** (Notizen, neue Collection — Kopplung #5): neues `EmployeeNote`-Model + org-skopierte Collection `employeeNotes` end-to-end verdrahtet — `FirestoreService` (watch/save/delete, kein orderBy → kein Index), `DatabaseService` (`_employeeNotesKey` + `_orgScopedCollectionKeys` + load/save), `PersonalProvider` (Stream + `addNote`/`deleteNote`/`notesForUser`, admin-only + Audit + hybrid-Fallback + lokale Persistenz), `firestore.rules` (admin-only, add/delete-only). Tab **Notizen** (Anlegen/Löschen, kein Bearbeiten) + „Letzte Notizen"-Karte im Übersicht-Tab.

- **M11** (Anlegen — WorkTime-konform statt AllTec-1:1): „Neuer Mitarbeiter"-Aktion (`person_add_alt_1`) in der Personalverwaltung öffnet einen **Einladungs-Dialog** (Name/E-Mail/Rolle) → `TeamProvider.saveInvite` (Mitarbeiter = Auth-gebundenes Login via `userInvites`; HR-Stammdaten danach in den Detail-Tabs). Bearbeiten läuft über die Detail-Tabs; Rollen bestehender MA bleiben in der Teamverwaltung. `_NewEmployeeDialog` in `personal_screen.dart` + Test.

**Tab-Stand: 9/9 gefüllt** ✅ Übersicht · ✅ Stammdaten · ✅ Gehalt · ✅ Qualifikationen · ✅ Ausbildungen · ✅ Kinder · ✅ Dokumente · ✅ Notizen · ✅ Verwalten. Top-Level-Liste (M10) ✅ + „Neuer Mitarbeiter" (M11) ✅. **`flutter analyze` ohne Fehler** (nur 2 vorbestehende Fremd-Warnungen). **Committet als `ef56423` (+ M11-Folgecommit), auf `main` + `origin/main` gepusht.** Offen nur M12-Deploy (`firebase deploy --only firestore:rules` für `employeeNotes`).

`flutter analyze` sauber (nur 3 vorbestehende, fremde Baseline-Hinweise). Tests grün: route_permissions 8, employee_detail_screen 2, employee_kinder_tab 2, employee_hr_models (EmployeeChild-Round-Trip inkl. `anmerkungen`), personal_provider/-screen/-documents. Uncommitted auf `feat/mhd-ablauf-warnung`.

**Offen:** M5 (Quali/Ausbildung +Felder) · M6 (EmployeeProfile ~15 Felder + Stammdaten) · M7 (VWL/Zulagen/Multi-Bank + Gehalt) · M8 (EmployeeNote + Notizen) · M9 (Verwalten) · M10 (Liste + Aggregat-Verlagerung) · M11 (Dialoge) · M12 (Gates+Deploy).

AllTec (`/Users/jowan/Documents/dev/AllTec`, Schwester-App desselben Entwicklers) hat im Personnel-Modul das Muster **Liste → Mitarbeiter-Detail mit 9 Tabs**. Dieses Muster wird in WorkTime **per Hand** in dessen Konventionen re-implementiert (Provider + go_router, kein bloc/GoRouter/Freezed-Transplant, Material 3, AllTec-Farbpalette ist bereits app-weit aktiv, Deutsch-only, Zwei-Serialisierungs-Regel).

## Betreiber-Entscheidungen (2026-07-04, fixiert)

1. **Strikt AllTec-Muster.** Der `/personal`-Bereich wird auf reines AllTec-Muster reduziert: **Liste → 9-Tab-Detail**. Die bisherigen 4 org-/monatsweiten Aggregat-Tabs (Aufträge/Lohn/Finanzen/Statistik) haben in AllTec kein Pendant und wandern von der Personal-Haupttab-Struktur weg. **Nicht destruktiv:** die Auswertungen werden erhaltend in einen separaten Admin-Auswertungs-Einstieg verlagert (nicht gelöscht), damit Lohnlauf/Finanzen/Statistik erreichbar bleiben.
2. **Volle Feld-Parität.** Das Datenmodell wird auf AllTec-Niveau ausgebaut (~15 EmployeeProfile-/Status-Felder + VWL/Zulagen/Multi-Bank-Models + EmployeeNote). **Ausnahme (bleibt bewusst aus, DSGVO Art. 9 / frühere Entscheidung):** GdB (Grad der Behinderung), Aufenthaltsstatus/isFluechtling, PEP. Diese werden auch bei „voller Parität" NICHT übernommen.
3. **„Mitarbeiter löschen" = Deaktivieren-Alias.** In WorkTime ist ein Mitarbeiter ein Auth-gebundenes `AppUserProfile` (users-Doc), kein reines HR-Objekt. Der Verwalten-Tab-„Löschen"-Button deaktiviert (`setMemberActive(false)`) — sicher, reversibel, Login bleibt. Kein echter Voll-Löschpfad.

## Ziel-IA

```
/personal (admin-only, Section-Route)
  └─ Personalverwaltung (Liste): SummaryCardRow + FilterBar (Suche/Status/Standort) + Mitarbeiter-Karten-Grid
        └─ Zeile → context.push('/personal/{uid}')
/personal/:id  (NEU, admin-only, Top-Level deep-linkbar)
  └─ EmployeeDetailScreen: BreadcrumbAppBar + Kopf-VCard + scrollbare TabBar (Icon+Text) mit 9 Tabs:
       Übersicht · Stammdaten · Gehalt · Qualifikationen · Ausbildungen · Kinder · Dokumente · Notizen · Verwalten
```

Editoren bleiben imperativ (`Navigator.push` / `showModalBottomSheet`) — der Detail-Screen ist die einzige neue URL. `team_management_screen` bleibt für Standorte/Teams/Regelwerk; seine Mitarbeiter-Editor-Inhalte werden zusätzlich aus Detail-Tabs erreichbar.

## AllTec-Tab → WorkTime-Datenquelle (belegt via Analyse-Workflow)

| Tab | WorkTime-Quelle | Datenlage | Für 1:1 zu tun |
|---|---|---|---|
| Übersicht | `employeeProfileForUser` + Vertrag (TeamProvider) + Counts (Quali/Ausbildung/Kinder/Doku) + „Letzte Notizen" | 🟡 partial | Status-Badge-Reihe, 4 KPI-Karten, Info-Karten; „Letzte Notizen" nach M8 |
| Stammdaten | `EmployeeProfile` (`saveEmployeeProfile`) + `EmploymentContract` (`saveMemberConfiguration`) + `SollzeitProfile` | 🟡 partial | ~15 Felder ergänzen (M6) |
| Gehalt | `PayrollProfile` + `EmploymentContract` + `EmployeeProfile` (Steuer/SV/Bank) | 🟡 partial | VWL/Zulagen/Multi-Bank-Models (M7) |
| Qualifikationen | `qualifications*` + `saveEmployeeQualification`/`delete…` | 🟡 partial | +4 Felder (M5) |
| Ausbildungen | `ausbildungen*` + `saveEmployeeAusbildung`/`delete…` | 🟡 partial | +status-Enum (Badge) +4 Felder (M5) |
| Kinder | `children*` + `saveEmployeeChild`/`delete…` | ✅ full | ggf. 1 `anmerkungen`-Feld |
| Dokumente | `documents*` + upload/download/`deleteDocument` | 🟡 partial | Kategorie-Enum 7→9, Icon/Farb-Mapping, Metadaten-Dialog |
| Notizen | — (fehlt komplett) | ❌ missing | Model + Collection + Rules + CRUD (M8) |
| Verwalten | `setMemberActive` + `EmployeeProfile.status` | 🟡 partial | „Löschen"=Deaktivieren-Alias, Status-Dropdown, Meta |

## Reuse (vorhanden) vs. neu

**Vorhanden:** `AppSectionCard`, `AppStatusBadge` (tone-basiert), `BreadcrumbAppBar`/`BreadcrumbItem`/`ShellBreadcrumb`, `AppSegmented`, `AppConfirmDialog`, `AppErrorState`, `EmptyState`, `AppMetricCard`/`AppStatCard`, `AppSearchField`, `AppFilterChip`, TabBar-/`DefaultTabController`-Muster, appColors/spacing/radii-Tokens, `_MonthBar`.

**Neu bauen:** `EmployeeDetailScreen` (Top-Level, uid-basiert) + 9 Tab-Widgets; `InfoRow` aus `personal_screen`/`team_management` nach `lib/widgets/` heben (heute file-private, dupliziert); `SummaryCardRow`-Wrapper; `FilterBar`-Komposition; Dokument-Metadaten-Dialog + Kategorie-Mapping; Status-Badge-Reihe.

## Sicherheit / kritische Kopplungen

- **Deep-Link-Leck (P0, M1):** `/personal/{id}` matcht keinen exakten `case` in `RoutePermissions.isLocationAllowed` → fällt auf `default:true` = **kein Admin-Gate**. Fix: `if (loc.startsWith('/personal/')) return p?.isAdmin ?? false;` vor dem `switch` (Kopplung #4/#7). In `firestore.rules` gespiegelt lassen.
- **Path-Parameter:** `_sectionRoute` reicht keine `:id` durch → explizite `GoRoute(path: '/personal/:id', parentNavigatorKey: rootNavigatorKey, builder: liest state.pathParameters['id'])`.
- **Zwei-Provider-Merge:** EmployeeProfile (PersonalProvider) + Vertrag/Rechte/Standort (TeamProvider). `updateSession` ist fire-and-forget → beim Deep-Link-Cold-Start Loading-/Not-Found-Zustand pro Tab.
- **Jedes neue Model-Feld = 6 Stellen** (`toFirestoreMap`/`fromFirestore`/`toMap`/`fromMap`/`copyWith`+`clearX`) + Round-Trip-Test (Kopplung #1). Callable betroffen? Nein (Personal schreibt direkt).
- **EmployeeNote = neue Collection** (Kopplung #5): local-Key + `_orgScopedCollectionKeys` + Rules (sameOrg-read admin, admin-write) + ggf. Composite-Index (where+orderBy) + AuditSink.
- **Enum-Erweiterungen** (Kopplung #3): DocumentCategory 7→9, neue TrainingStatus/… → `.value`/`fromValue`-Default + deutsches Label.

## Meilensteine (kleinste offline-testbare Schritte)

- **M1 — Routing + Sicherheit.** `AppRoutes.personalDetail='/personal/:id'` + `personalDetailPath(uid)`; explizite GoRoute; `isLocationAllowed`-Prefix-Guard; Rules-Spiegel; Router-Harness-Test (Nicht-Admin geblockt, Admin erlaubt). *Dateien:* `shell_tab.dart`, `app_router.dart`, `route_permissions.dart`, `firestore.rules`, `test/support/router_harness.dart`.
- **M2 — Detail-Gerüst.** `EmployeeDetailScreen` (DefaultTabController 9, BreadcrumbAppBar, VCard, scrollbare TabBar, Not-Found). Listen-Karte → `context.push`. Widget-Test: 9 Reiter.
- **M3 — Reuse-Bausteine.** `InfoRow` heben, `SummaryCardRow`, `FilterBar`.
- **M4 — Tabs mit voller Datenlage.** Kinder (CRUD 1:1), Dokumente (reuse + Metadaten-Dialog + Kategorie-Mapping), Übersicht (read-only, „Letzte Notizen" noch aus).
- **M5 — Model+Tabs Quali/Ausbildung.** EmployeeQualification +4 Felder; EmployeeAusbildung +status-Enum +4 Felder; beide Tabs.
- **M6 — Stammdaten-Parität.** EmployeeProfile/StatusData +~15 Felder (ohne DSGVO-Art.-9); Tab Stammdaten (Anzeige + 3 Editor-Sheets).
- **M7 — Gehalt-Parität.** Models VwlData/SalaryAllowance/BankAccount-Liste; Tab Gehalt.
- **M8 — Notizen.** EmployeeNote Model+Collection+Rules+CRUD; Tab Notizen + Übersicht-„Letzte Notizen".
- **M9 — Verwalten.** Deaktivieren-Alias, Status-Dropdown, Meta-IDs.
- **M10 — Liste + Aggregat-Verlagerung.** Personalverwaltungs-Liste (SummaryCardRow+FilterBar+Karten-Grid); Aggregat-Tabs erhaltend in separaten Auswertungs-Einstieg.
- **M11 — Dialoge.** EmployeeDialog (Anlegen/Bearbeiten) + Rollen-Dialog-Parität.
- **M12 — Quality Gates + Deploy.** `flutter analyze` clean, `flutter test` grün, de_DE, appColors; Deploy-Notizen (Rules/Indexe/ggf. Storage).

## Offene Punkte / Restrisiken

- Exakter Zielort der verlagerten Aggregat-Auswertungen (eigener `/personal-auswertungen`-Screen vs. Buchhaltung-Modul) — in M10 entscheiden, Betreiber-Rückfrage möglich.
- Volle Feld-Parität = viele Zwei-Serialisierungs-Kopplungen → Regressionsrisiko an bestehenden Editoren (`team_management_screen._MemberEditorSheet`, `personal_screen`-Editoren); je Feld Round-Trip-Test.
- `personal_screen.dart` (5685 Z) file-private Widgets nicht importierbar → Heraushebung mit Merge-Risiko.
- Deploy (Rules/Indexe/ggf. Storage) bleibt extern/Blaze; nichts wird in diesem Plan deployt.
