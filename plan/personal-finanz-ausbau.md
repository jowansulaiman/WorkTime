# Plan: Personal- & Finanzbereich auf AllTec-Niveau (und darüber)

> **Auftrag (Nutzer, 2026-06-22):** „Der Personalbereich und Finanz soll genau wie in
> dem Projekt AllTec sein. Sogar besser und verbessert."
>
> **Entscheidungen (vom Nutzer bestätigt):**
> 1. **Reihenfolge:** Mitarbeiter-Stammakte zuerst (Fundament), dann Lohn, dann Finanzen.
> 2. **Finanz-Tiefe:** voll wie AllTec **inkl. DATEV-EXTF-Export** (Kostenstellen/Kostenarten/
>    Buchungsjournal/Budget + CSV/PDF).
> 3. **Sensible HR-Daten:** nur **lohnrelevant** (Konfession + Familienstand + Kinderzahl);
>    GdB, Aufenthaltsstatus, PEP, Flüchtlingsstatus **bewusst weggelassen** (DSGVO Art. 9).

## Kontext / Gap-Analyse (AllTec `/Users/jowan/Documents/dev/AllTec` vs. WorkTime)

Multi-Agent-Analyse der AllTec-Module `personnel`, `finance`, `time_tracking/payroll`. Befund:
WorkTime hatte aus M0–M7 bereits §32a-Lohnsteuer, `PayrollProfile`/`PayrollRecord`,
`payroll_calculator`, Personal-Screen (5 Tabs) und `Money`. **Fehlend ggü. AllTec:**

- **Mitarbeiter-Stammakte:** WorkTime las nur Team-Daten. AllTec pflegt Anschrift, Geburtstag,
  Eintritt/Austritt, Probezeit/Befristung, Familienstand/Konfession, SV-/Steuer-/Bankdaten,
  Urlaub, Notizen. → **Meilenstein A.**
- **Lohn reicher & genauer:** itemisierte `lines` (Bezüge) + `deductions` (Abzüge); Status-
  Workflow draft→finalized→paid→cancelled; **Lohnlauf** (Monatsbatch über alle MA mit
  Summen-KPIs + „alle finalisieren"); Steuer-Verbesserungen (PV-Kinderlosenzuschlag,
  Kinderfreibeträge→Soli/KiSt, Steuerklasse II Alleinerziehend-Entlastung, KV-Zusatzbeitrag
  konfigurierbar); EPC-QR-Überweisung. → **Meilenstein B.**
- **Finanzen = echte Kostenrechnung:** Kostenstellen/Kostenarten/Buchungsjournal/Budget,
  Plan/Ist, DATEV-EXTF-Export, CSV-Import/Export, PDF-Jahresbericht. WorkTimes „Finanzen"
  war nur Personalkosten (mit Doppelzählungs-Bug). → **Meilenstein C.**

**Architektur-Leitplanke (wie alltec-uebernahme.md):** nur Domänenmodelle/Logik/UX
re-implementieren — **kein** bloc/GoRouter/Freezed/Hive/codegen. provider · Hand-Dual-
Serialisierung · SharedPreferences · Spark-frugal · de_DE · int Cent · firestore.rules synchron.

---

## Meilenstein A — Mitarbeiter-Stammakte · ✅ ERLEDIGT (2026-06-22)

Neues Modell `lib/models/employee_profile.dart` (`EmployeeProfile`, 34 HR-Felder, 5 Enums:
`MaritalStatus`/`Confession`/`PersonnelGroup`/`EmployeeStatus`/`HealthInsuranceType`), voll
dual-serialisiert. Org-skopierte Collection `organizations/{orgId}/employeeProfiles/{userId}`
(deterministische Doc-ID = userId, **admin-only**).

- **FirestoreService:** `_employeeProfileCollection` + `watch/save/deleteEmployeeProfile`.
- **DatabaseService:** `_employeeProfilesKey` (org-skopiert) + `load/saveLocalEmployeeProfiles`.
- **PersonalProvider:** Stream/Getter/`employeeProfileForUser`/`saveEmployeeProfile`/
  `deleteEmployeeProfile` (+ Lifecycle, lokaler Hybrid-Fallback, `_assertAdmin`).
- **firestore.rules:** Block `employeeProfiles` admin-only (read+write, `sameOrg`, orgId-Pin).
- **UI** (`personal_screen.dart`): `_EmployeeStammdatenCard` (read-only, blendet leere Felder
  aus) + `_EmployeeProfileEditorSheet` (voller Editor: Persönlich/Anschrift/Kontakt/
  Beschäftigung/Lohn+SV inkl. KV-Zusatzbeitrag/Bank/Urlaub/Notfall/Notiz) im Mitarbeiter-Detail.
- **Tests:** `test/employee_profile_test.dart` (12) + `personal_provider_test.dart` (+2).
- **Verifikation:** `flutter analyze` sauber · `flutter test` **555 grün**. Adversariales
  3-Agenten-Review: solide, 3 niedrige Funde behoben (createdAt-Erst-Write, `_formatPercent`
  ohne „,0", KV-Feld-Validator).

> **Deploy vor Cloud-Nutzung:** `firebase deploy --only firestore:rules` (neuer Block
> `employeeProfiles`). Keine neuen Composite-Indizes.

---

## Meilenstein B — Lohn-Ausbau · ⏳ TEILWEISE

### ✅ B1 — Steuer/SV genauer (2026-06-22)
`german_tax.dart`/`payroll_calculator.dart`/`payroll_settings.dart` + Lohn-Editor:
- **Kinderfreibeträge** senken NUR die Bemessung für Soli/Kirchensteuer (§ 51a EStG), nicht die
  Lohnsteuer — bewusst **korrekter als AllTec** (dort fälschlich auf die ganze Lohnsteuer).
  Zähler je Klasse: III voll, II/IV halb, I/V/VI keiner (review-korrigiert: II war zunächst voll).
- **Steuerklasse II**: Alleinerziehenden-Entlastungsbetrag (4.260 €) senkt die echte Lohnsteuer.
- **PV-Kinderlosenzuschlag** (+0,6 %) nur AN, nur nachweislich ≥23 J. (ohne Geburtsdatum konservativ
  kein Zuschlag — review-korrigiert).
- **KV-Zusatzbeitrag** kassenindividuell aus `EmployeeProfile.healthInsuranceSurchargePercent`
  (wirkt AN+AG+Vorsorgepauschale).
- Lohn-Editor liest die Stammakte automatisch (Kinder/Alter/KV-Zusatz) + Transparenz-Banner.
- Rückwärtskompatibel (ohne neue Parameter bit-identisch). **568 Tests grün**, adversarial reviewt
  (2 mittel-Funde behoben). `childAllowanceUnitsForTesting` als Test-Seam.

### ✅ B2 — Status-Workflow (2026-06-22)
`PayrollStatus { entwurf, freigegeben, bezahlt, storniert }` + `finalizedByUid`/`finalizedAt` an
`PayrollRecord` (alle 6 Touchpoints + clear-Flags). Provider `setPayrollStatus(record, status)`
stempelt Freigeber+Zeit bei Freigabe/Bezahlt (leert sonst) + Audit-Eintrag. UI: Status-Badge
(farbcodiert) + Statuswechsel-Menü im `_PayrollTile`. Bearbeiten einer Abrechnung setzt bewusst
auf Entwurf zurück. Tests: `payroll_record_test` (+3), `personal_provider_test` (+1).

### ✅ B3 — Lohnlauf (Kern, 2026-06-22)
`_PayrollRunSummary` im Lohn-Tab: Monats-Summen-KPIs (Σ Brutto/Abzüge/Netto/AG-Kosten, stornierte
ausgenommen) + Statusverteilung + „Alle Entwürfe freigeben (N)" (Bestätigungsdialog → Batch).
Provider `payrollForPeriod(year, month)` + `finalizeAllDrafts(year, month)`. Test (+1).
**579 Tests grün, analyze sauber.**

### ✅ Audit-Sink-Umbau übernommen
`AuditProvider` → `PersonalProvider` (Proxy4 in `main.dart`, `setAuditSink`, Audit-Logging in allen
Personal-Mutatoren inkl. Stammakte/Lohn/Status). Vom Nutzer begonnen, von Claude verifiziert + grün.

### ⏳ Offen (bewusst aufgeschoben)
4. **Itemisierte Bezüge:** `PayrollRecord.lines` (Grundgehalt/Stunden/Überstunden/Zulagen/VwL) —
   additiv; Abzüge sind bereits einzeln gespeichert.
5. **EPC-QR-Überweisung** aus Netto + IBAN — braucht ein QR-Paket (`qr_flutter` o. ä.); Dependency-
   Entscheidung offen, daher vorerst nicht gebaut.
6. **PayrollSettings editierbar** (statt hartkodiert) — optional.

## Meilenstein C — Finanzen voll inkl. DATEV · ✅ KERN ERLEDIGT (2026-06-22)

- **C1 Modelle** `lib/models/finance_models.dart`: `CostCenter`/`CostType`/`JournalEntry`/`Budget`
  (int Cent, dual-serialisiert, org-skopiert) + `CostTypeGroup`-Enum. Schlank gehalten (ohne AllTecs
  Hierarchie/Abteilung/Budget-Pool/Ist-Cache). Budget-Doc-ID deterministisch. Vorzeichen-Konvention
  (amount>0=Kosten, <0=Gutschrift). Pure Analytik `lib/core/finance_analytics.dart` (Plan/Ist,
  Monatsverlauf, KPIs).
- **C2 Provider/Plumbing** `lib/providers/finance_provider.dart` (Proxy3<Auth,Storage,Audit> in
  `main.dart`, 4 Streams, Storage-Modi + Hybrid-Fallback, Audit, admin-only) + FirestoreService
  (watch/save/delete) + DatabaseService (4 org-skopierte Keys) + firestore.rules (4 admin-only Blöcke).
- **C3 UI** `lib/screens/finance_screen.dart`: Tabs Übersicht (KPIs/Plan-Ist-Ampel/Monatsverlauf/
  Prüfpunkte) / Journal / Stammdaten (Kostenstellen+Kostenarten) / Budgets — mit Editor-Sheets.
  Admin-only ins Menü („Buchhaltung") + Router (`AppRoutes.finance`) eingehängt.
- **C4 Export** `lib/core/datev_export.dart`: **DATEV-EXTF-Buchungsstapel (Format 700)** + Journal-CSV
  (`ExportService`), Export-Menü in der Buchhaltung. Getestet (`datev_export_test`, `finance_*_test`).
- **595 Tests grün, analyze sauber.** Adversariales Review läuft.

> **Deploy:** `firebase deploy --only firestore:rules` (neue Blöcke costCenters/costTypes/
> journalEntries/budgets). Keine neuen Composite-Indizes.
> **Offen:** Finanz-PDF-Jahresbericht (PdfService), DATEV-Config-Dialog (Berater/Mandant), CSV-/DATEV-Import.

---

## Verifikation (nach jedem Meilenstein)

```bash
flutter analyze        # sauber
flutter test           # alle grün (inkl. neuer)
flutter run --dart-define=APP_DISABLE_AUTH=true   # Offline-Demo, admin@demo.local / demo1234
```
Pro Modelländerung: alle 4 Serialisierungs-Stellen + copyWith; firestore.rules synchron;
Enums `.value`/`fromValue`-Default; keine neuen Composite-Indizes anstreben.
