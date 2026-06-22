# Core-Logik (Config, Parser, Lohn, Steuer)

> Teil des WorkTime-Code-Reviews. Zurück zur [Übersicht](README.md).

### 27. Money.parseCents widerspricht der eigenen Doku für Eingaben mit Dezimalpunkt ("12.34")

- **Schweregrad:** Niedrig  ·  **Kategorie:** bug  ·  **Konfidenz:** high  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/core/money.dart:50`, `lib/core/money.dart:58`, `test/money_test.dart:25`, `lib/screens/inventory_screen.dart:33`

**Problem.** Der Doc-Kommentar von parseCents nennt ausdrücklich `"12.34"` als gültige Eingabe, die 12,34 € ergeben soll. Die Implementierung entfernt jedoch ALLE Punkte (`replaceAll('.', '')`), behandelt den Punkt also strikt als Tausendertrenner. `"12.34"` wird zu `"1234"` → 1234,00 € = 123400 Cent statt 1234 Cent. Der Test in test/money_test.dart bestätigt nur die de_DE-Variante (`1.234` → 123400) und deckt den dokumentierten `12.34`-Fall nicht ab.

**Auswirkung.** Wer (z. B. von englischer Tastatur, Copy-Paste, oder weil die Doc es suggeriert) einen Preis mit Dezimalpunkt eingibt, bekommt still den 100-fachen Betrag — ein Geld-/Preisfehler ohne Fehlermeldung. Aktuell ist die Klasse noch in kein Eingabefeld verdrahtet (keine Aufrufer außerhalb money.dart), daher begrenzte reale Wirkung; das Risiko entsteht beim ersten produktiven Einsatz.

**Beleg.** Doc: `Parst eine deutsche Eingabe ("1.234,56", "12,34 €", "12.34") in Cent` vs. Code: `trimmed.replaceAll('.', '').replaceAll(',', '.')` → '12.34' wird zu 1234.0 Euro.

**Empfehlung.** Entweder den irreführenden `"12.34"`-Eintrag aus dem Doc-Kommentar entfernen ODER (sicherer) die Eingabe heuristisch behandeln: wenn genau ein Punkt und kein Komma vorhanden ist und nach dem Punkt 1–2 Stellen folgen, den Punkt als Dezimaltrenner interpretieren. Dann den Fall mit einem Test absichern.

### 28. PayrollSettings.taxTariff wird nie aus Map deserialisiert und ist auch für 2025 hart auf year2026

- **Schweregrad:** Niedrig  ·  **Kategorie:** data-integrity  ·  **Konfidenz:** high  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/models/payroll_settings.dart:37`, `lib/models/payroll_settings.dart:134`, `lib/models/payroll_settings.dart:156`, `lib/models/payroll_settings.dart:245`, `lib/core/german_tax.dart:71`, `lib/core/payroll_calculator.dart:172`

**Problem.** `taxTariff` hat den festen Default `TaxTariff.year2026` und wird in `fromMap` gar nicht gelesen (Kommentar: 'taxTariff wird über year abgeleitet'), in `toMap` nicht geschrieben. Sowohl `defaults2025()` als auch `defaults2026()` verwenden denselben 2026er-Tarif. Damit rechnet eine als Jahr 2025 markierte/persistierte Settings-Instanz mit den 2026er Steuerzonen, und ein per Firestore/SharedPrefs gespeichertes `year` hat keinerlei Wirkung auf den tatsächlich angewandten Tarif.

**Auswirkung.** Lohnsteuer-Richtwerte sind unabhängig vom konfigurierten Bezugsjahr immer der 2026-Tarif. Sobald ein zweiter Tarif (z. B. year2027) eingeführt wird, greift er nach Deserialisierung still NICHT, ohne dass ein Test oder Lint anschlägt — latente Compliance-/Korrektheits-Falle. Heute nur 'Richtwert', daher niedrig.

**Beleg.** fromMap baut PayrollSettings ohne `taxTariff:`-Argument → const Default year2026; defaults2025() ebenfalls ohne `taxTariff:` → year2026.

**Empfehlung.** `year`→`TaxTariff` in `fromMap` explizit auflösen (Switch auf year mit Default) und in den Factories `defaults2025` einen tatsächlich abweichenden Tarif zuordnen oder den Default-Tarif-Mechanismus dokumentiert zentralisieren, damit Jahr und Tarif konsistent bleiben.

### 29. soliRate/soliThresholdCents in PayrollSettings sind toter Code und driften gegen die tatsächliche Soli-Berechnung

- **Schweregrad:** Niedrig  ·  **Kategorie:** maintainability  ·  **Konfidenz:** high  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/models/payroll_settings.dart:53`, `lib/models/payroll_settings.dart:54`, `lib/models/payroll_settings.dart:168`, `lib/models/payroll_settings.dart:224`, `lib/core/german_tax.dart:184`, `lib/core/payroll_calculator.dart:169`

**Problem.** `PayrollSettings.soliRate` (0.055) und `soliThresholdCents` (134000) werden serialisiert und wirken konfigurierbar, fließen aber nirgends in die Berechnung ein. Der Soli wird in `GermanIncomeTax._soli` mit den hartkodierten Konstanten 0.055/0.119/Faktor 1.85 und `tariff.soliFreigrenzeJahrEuro` (18130 Jahres-Lohnsteuer) gerechnet. Die `soliThresholdCents`-Schwelle (als Cent-Betrag) und die `soliFreigrenzeJahrEuro` (Euro-Jahres-Lohnsteuer) modellieren dieselbe Größe in inkompatiblen Einheiten.

**Auswirkung.** Wer per Org-Override `soli_rate`/`soli_threshold_cents` setzt, erwartet eine Änderung der Soli-Berechnung — es passiert nichts. Verwirrende, irreführende Konfiguration; Risiko falscher Annahmen bei künftiger Pflege.

**Beleg.** `final double soliRate` + `soliThresholdCents` werden in toMap geschrieben, aber `_soli(annualTax, tariff)` nutzt ausschließlich `t.soliFreigrenzeJahrEuro` und literale 0.055/0.119/1.85.

**Empfehlung.** Entweder die beiden Felder entfernen (und aus toMap/fromMap streichen) oder `_soli` so umbauen, dass es `settings.soliRate` und eine konsistente Schwelle nutzt. Mindestens als 'unbenutzt/deprecated' im Doc-Kommentar markieren wie bei `incomeTaxRateByClass`.

### 30. incomeTaxRateByClass wird weiterhin deserialisiert/gemappt, ist aber für den Rechner wirkungslos

- **Schweregrad:** Niedrig  ·  **Kategorie:** maintainability  ·  **Konfidenz:** medium  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/models/payroll_settings.dart:112`, `lib/models/payroll_settings.dart:156`, `lib/models/payroll_settings.dart:124`

**Problem.** `incomeTaxRateByClass`/`incomeTaxRateFor` sind laut Doc 'veraltet' (Rechner nutzt § 32a-Tarif), werden in fromMap aber noch aktiv aus `income_tax_rate_by_class` geparst und in toMap geschrieben. Eine Org, die diese Pauschalsätze pflegt, hat keinerlei Effekt auf die Lohnsteuer.

**Auswirkung.** Konfigurationsillusion: gepflegte Pauschal-Steuersätze bleiben folgenlos; Pflege-/Erwartungsfalle bei künftigen Änderungen. Keine falschen Beträge, daher niedrig.

**Beleg.** Doc: 'wird aber vom Rechner nicht mehr verwendet'; PayrollCalculator.calculate ruft ausschließlich GermanIncomeTax.monthly(...) mit dem Tarif auf, nie incomeTaxRateFor.

**Empfehlung.** Feld + Serialisierung entfernen oder die Wirkungslosigkeit auch in fromMap/toMap-Nähe klar als 'nur Abwärtskompatibilität' kommentieren; Getter `incomeTaxRateFor` ggf. als @Deprecated annotieren.

### 31. _midijobBase liefert bei Brutto unterhalb der Minijob-Grenze die volle (ungeminderte) Bemessung

- **Schweregrad:** Niedrig  ·  **Kategorie:** bug  ·  **Konfidenz:** medium  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/core/payroll_calculator.dart:239`, `lib/core/payroll_calculator.dart:242`

**Problem.** `_midijobBase` gibt für `gross <= g` (Minijob-Grenze, 556 €) `gross` zurück, also volle Beitragsbemessung. Aufgerufen wird die Funktion nur, wenn `kind == midijob`. Ein als Midijob klassifizierter Datensatz mit Brutto unter 556 € erhält damit keine Übergangsbereich-Minderung und volle AN-Beiträge auf das volle Brutto — inkonsistent zur Erwartung, dass ein Midijob immer die reduzierte Bemessung nutzt. Das ist ein Datenklassifikations-Edge-Case (Brutto < Untergrenze trotz Midijob-Kennzeichnung).

**Auswirkung.** Falsch klassifizierte Datensätze erzeugen leicht zu hohe AN-Beiträge/zu niedriges Netto für den betroffenen Monat. Selten und nur bei Fehl-Klassifikation; nur Richtwert. Daher niedrig.

**Beleg.** `if (gross <= g || o <= g) { return gross; }` — gross unter Untergrenze ⇒ keine Übergangsbereich-Reduktion trotz kind==midijob.

**Empfehlung.** Entweder die Klassifikation vorab erzwingen (gross < minijobCeiling ⇒ Minijob/normal, nicht Midijob) oder im Übergangsbereich-Branch dokumentieren, dass unterhalb der Untergrenze bewusst keine Minderung greift.

### 32. AppConfig.validateEnvironment greift nur in kReleaseMode, nicht in Profile-Builds

- **Schweregrad:** Niedrig  ·  **Kategorie:** security  ·  **Konfidenz:** medium  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/core/app_config.dart:73`

**Problem.** `validateEnvironment` wirft nur, wenn `kReleaseMode && disableAuthentication`. Ein Profile-Build (`flutter build --profile` / `flutter run --profile`) ist nicht `kReleaseMode`, könnte also mit `APP_DISABLE_AUTH=true` ohne Auth ausgeliefert/getestet werden, obwohl er performance-/distributionsnah ist.

**Auswirkung.** Ein versehentlich mit deaktivierter Auth gebauter Profile-Build umgeht die Schutzschranke und liefert Demo-/Offline-Zugriff ohne Firebase-Auth. Geringe Wahrscheinlichkeit, da Profile selten verteilt wird, aber ein echtes Sicherheits-Schlupfloch.

**Beleg.** `if (kReleaseMode && disableAuthentication) { throw StateError(...) }` — kProfileMode ist weder kReleaseMode noch kDebugMode.

**Empfehlung.** Die Prüfung auf `!kDebugMode && disableAuthentication` umstellen (also Release UND Profile blockieren) oder explizit `kProfileMode` mit einbeziehen.
