# Personal & Lohn (technisch)

Der Personal-/HR-Bereich hängt an `PersonalProvider` (`lib/providers/personal_provider.dart`), der `workTasks`, `payrollRecords` und `-Profiles` verwaltet (Cloud-Repo lazy).

## Lohn-Herleitung (pure Cores)

Die Lohnberechnung ist in mehrere pure Core-Klassen zerlegt:

- `lib/core/payroll_calculator.dart` – Grundberechnung.
- `lib/core/german_tax.dart` – steuerliche Grundlagen (§39b u. a.).
- `lib/core/sfn_lage.dart` + `lib/core/sfn_zuschlag.dart` – Sonn-, Feiertags-, Nachtzuschläge (§3b).
- `lib/core/lohn_herleitung.dart` – nachvollziehbare Herleitung eines Betrags.
- `lib/core/personnel_cost.dart`, `lib/core/lohnquote.dart` – Personalkosten/Lohnquote.

Modelle: `PayrollRecord`, `PayrollProfile`, `PayLineType`, `OrgPayrollSettings`, `EmploymentContract`.

## DATEV-Export

`lib/core/datev_export.dart` erzeugt DATEV-EXTF für die Lohn-/Finanzweitergabe. Tests: `test/datev_export_test.dart`.

## Digitale Personalakte

`EmployeeProfile`, `EmployeeDocument`, `EmployeeQualification`, `EmployeeAusbildung`, `EmployeeChild` bilden die Akte. Dokumente werden per **Firebase Storage** hochgeladen (`lib/services/document_storage.dart`). Selbstsicht: `MeineAkteScreen` (self-scoped Streams + Rules) – jeder aktive Nutzer nur die eigenen Daten.

## Zeitkonto & Urlaub

Eng verbunden mit der [Zeitwirtschaft](article:dev-zeitwirtschaft-technik): `zeitkonto_calculator.dart`, `urlaub_calculator.dart`, `monatsabschluss_service.dart` (echte Monats-Festschreibung).

> [!NOTE]
> Lohn-/Steuerlogik ist fachlich heikel. Änderungen an Schwellen/Formeln immer mit Tests belegen und die Herleitung (`lohn_herleitung.dart`) mitziehen. Der HR-Bereich ist admin-only.

## Weiter

- [Zeitwirtschaft (technisch)](article:dev-zeitwirtschaft-technik)
- [Kasse/POS (technisch)](article:dev-kasse-pos-technik)
