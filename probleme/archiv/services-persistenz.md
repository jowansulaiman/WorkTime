# DatabaseService / lokale Persistenz · Export / PDF / Scanner / Download

> Teil des WorkTime-Code-Reviews. Zurück zur [Übersicht](README.md).

## DatabaseService / lokale Persistenz

### 6. Schema-Versionierung ist ein No-op-Stempel – Typwechsel an Modellen droppt lokale Daten still

- **Schweregrad:** Mittel  ·  **Kategorie:** data-integrity  ·  **Konfidenz:** medium  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/services/database_service.dart`

**Problem.** Die lokale Schema-Versionierung (_ensureScopedSchemaVersion, database_service.dart:1112-1123) liest die gespeicherte Version, und sobald currentLocalSchemaVersion (==1, Zeile 102) erreicht ist, stempelt sie nur und macht sonst nichts. Es gibt aktuell keinen einzigen Migrationsschritt. Gleichzeitig schluckt _loadCollection (Zeile 1059-1068) sowohl FormatException als auch TypeError und ueberspringt den betroffenen Eintrag stillschweigend ('continue'). Wenn ein Modell-Feld in einer kuenftigen Release den Typ wechselt oder umbenannt wird, OHNE dass currentLocalSchemaVersion erhoeht und ein echter Migrationsschritt ergaenzt wird, faengt der TypeError-Catch jeden inkompatiblen alten Eintrag ab und verwirft ihn beim Laden — exakt das Szenario, das die Versionierung laut Doc-Kommentar (Zeile 97-101) verhindern sollte. Der No-op-Stempel macht die Versionierung wirkungslos: nach einem Upgrade wird die Version sofort auf 1 gestempelt, ohne dass je eine Migration laeuft.

**Auswirkung.** Stiller Datenverlust bei einem Modell-Refactoring, das vergisst die Schema-Version zu erhoehen. Im local-Modus ist SharedPreferences die einzige Quelle der Wahrheit (kein Firestore-Backup) — verworfene Eintraege sind unwiederbringlich. Im hybrid-Modus wuerde der Firestore-Cache zwar greifen, aber die lokal gespiegelten userContent-Daten (Schichten/Zeiteintraege) gingen lokal verloren.

**Beleg.** database_service.dart:1112-1123 (No-op-Stempel), :1059-1068 (stiller TypeError/FormatException-Skip), :102 (currentLocalSchemaVersion = 1), :97-101 (Doc-Kommentar beschreibt die Absicht).

**Empfehlung.** Die Kopplungsregel explizit machen: bei jedem breaking Modell-Change MUSS currentLocalSchemaVersion erhoeht und ein geordneter Migrationsschritt in _ensureScopedSchemaVersion ergaenzt werden (so wie der Kommentar es vorsieht). Zusaetzlich erwaegen, den TypeError-Catch in _loadCollection zu loggen (AppLogger.warning mit Collection-Key + Eintrag), damit ein versehentlicher Drop nicht voellig unsichtbar bleibt.

### 33. Legacy-Migration kopiert Eintraege mit leerem orgId in JEDEN Org-Scope (Cross-Org-Leak bei Altdaten)

- **Schweregrad:** Niedrig  ·  **Kategorie:** data-integrity  ·  **Konfidenz:** low  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/services/database_service.dart`

**Problem.** _matchesScopedOrgItem (database_service.dart:1313-1319) liefert true, wenn der orgId des Legacy-Eintrags LEER ist ODER mit dem Scope uebereinstimmt. Beim ersten scoped Zugriff jeder Org laeuft _ensureOrgScopedStorageInitialized (:1125ff) und liest die globalen Legacy-Collections (loadLegacyEntries/loadLocalShifts/... ohne scope), filtert mit _matchesScopedOrgItem und kopiert die Treffer in den Org-Prefix. Die globalen Legacy-Keys werden dabei NICHT geloescht (clearLegacyWorkData entfernt nur work_entries/work_templates/Settings, nicht shifts/teams/sites/etc.). Loggt sich auf demselben Geraet danach ein Nutzer einer ANDEREN Org ein, wird dessen Org-Scope erneut aus denselben globalen Legacy-Keys befuellt — und jeder Legacy-Eintrag mit leerem orgId landet in beiden (allen) Orgs. Fuer den dokumentierten Betrieb (zwei Laeden in EINER Org) ist das praktisch irrelevant; bei Mehr-Org-Nutzung auf einem Geraet mit pre-v2-Altdaten ohne orgId ist es ein echter Datenleck-Pfad.

**Auswirkung.** Daten eines Mandanten koennten im local/hybrid-Modus in den lokalen Scope eines anderen Mandanten dupliziert werden, sofern echte Pre-v2-Altdaten ohne gesetzten orgId existieren und mehrere Orgs dasselbe Geraet teilen. Verletzt die Mandantentrennung lokal.

**Beleg.** database_service.dart:1313-1319 (leerer orgId == Treffer), :1139-1248 (Migration liest globale Keys, loescht sie nie), :962-969 (clearLegacyWorkData loescht nur entries/templates/Settings).

**Empfehlung.** Im Migrationsfilter Eintraege mit leerem orgId nur in EINE definierte Org (z.B. defaultOrganizationId) statt in jede Org uebernehmen, ODER die globalen Legacy-Collections nach erfolgreicher Migration der jeweiligen Org loeschen, ODER _matchesScopedOrgItem fuer den Migrationspfad strenger fassen (leerer orgId != Treffer). Da es Altdaten betrifft, mindestens dokumentieren.

### 34. Keine Test-Abdeckung fuer Org-Isolation der neuen order_carts/weekly_order_lists auf DatabaseService-Ebene

- **Schweregrad:** Niedrig  ·  **Kategorie:** test-gap  ·  **Konfidenz:** high  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `test/database_service_test.dart`, `test/order_cart_provider_test.dart`, `lib/services/database_service.dart`

**Problem.** Die neuen Collections order_carts und weekly_order_lists sind korrekt als org-skopiert registriert (_orgScopedCollectionKeys, database_service.dart:127-128) und besitzen Round-Trip-Helfer (loadLocalOrderCarts/saveLocalOrderCarts/loadLocalWeeklyOrderLists/saveLocalWeeklyOrderLists, :728-772). Die vorhandenen Tests pruefen aber nur den Provider-Round-Trip im local-Modus (order_cart_provider_test.dart 'Korb ueberlebt einen Neustart') und das Modell-Mapping (order_cart_models_test.dart). Es fehlt ein DatabaseService-Test, der belegt, dass (a) zwei Orgs ihre Koerbe NICHT teilen (Org-Isolation ueber den _orgScopePrefix) und (b) zwei Nutzer DERSELBEN Org den Korb SEHR WOHL teilen (das ist das fachliche Designziel des geteilten Wochen-Bestellkorbs). Genau diese org- vs. user-Skopierung ist die fehleranfaellige Invariante laut CLAUDE.md (_orgScopedCollectionKeys), wird fuer die neuen Collections aber nicht abgesichert.

**Auswirkung.** Eine versehentliche Verschiebung von order_carts in den user-Scope (oder umgekehrt) wuerde die geteilte-Korb-Semantik brechen, ohne dass ein Test fehlschlaegt. Regressions-Risiko bei kuenftigen Aenderungen an _resolveCollectionKey/_orgScopedCollectionKeys.

**Beleg.** database_service.dart:127-128 (Registrierung), :728-772 (Helfer); test/order_cart_provider_test.dart hat keinerlei LocalStorageScope-/Cross-Org-Assertions; test/database_service_test.dart deckt nur entries/shifts/settings ab.

**Empfehlung.** Analog zum vorhandenen Test 'shares org data but keeps user settings separate' (database_service_test.dart:21) einen Test ergaenzen, der saveLocalOrderCarts mit Scope (org-1/user-1) schreibt und mit Scope (org-1/user-2) wiederliest (muss sichtbar sein) sowie mit Scope (org-2/user-3) wiederliest (muss leer sein).

### 35. Scanner-Tonschalter wird global (ohne Scope) persistiert – geteilt ueber alle Nutzer/Orgs auf dem Geraet

- **Schweregrad:** Niedrig  ·  **Kategorie:** ux  ·  **Konfidenz:** medium  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/screens/scanner_screen.dart`, `lib/services/database_service.dart`

**Problem.** Der Scanner-Tonschalter liest/schreibt sein Setting ohne scope-Argument (scanner_screen.dart:122 getLocalSetting(_soundSettingKey) und :140 saveLocalSetting(...)). _resolveSettingKey faellt bei scope==null auf _resolveGlobalSettingKey zurueck (database_service.dart:1358-1370), d.h. der Wert liegt unter dem globalen setting_-Namespace und nicht unter dem User-Scope. Andere geraetebezogene Settings (theme_mode, locale, data_storage_location) sind bewusst ebenfalls global. Der Scanner-Ton ist jedoch eine pro-Nutzer-Praeferenz, waehrend Stempeluhr-Settings (clockIn) explizit scope: _localScope nutzen (work_provider.dart:933-947). Inkonsistenz: meldet sich ein anderer Mitarbeiter auf demselben Geraet an, erbt er die Ton-Einstellung des vorigen Nutzers.

**Auswirkung.** Reine UX-Inkonsistenz: die Ton/Haptik-Praeferenz ist nicht nutzer- sondern geraetegebunden. Keine Daten- oder Sicherheitsfolgen.

**Beleg.** scanner_screen.dart:122 und :140 (kein scope), database_service.dart:1358-1370 (_resolveSettingKey global bei scope==null) vs. work_provider.dart:933-947 (clockIn mit scope: _localScope).

**Empfehlung.** Falls die Praeferenz nutzergebunden sein soll, beim Lesen/Schreiben des Scanner-Tonschalters einen LocalStorageScope (aus dem aktiven Profil) uebergeben. Falls geraetegebunden gewollt, im Code kurz dokumentieren, damit es nicht als Bug missverstanden wird.

## Export / PDF / Scanner / Download

### 7. CSV-Exporte neutralisieren Formel-Prefixe nicht (CSV/Formula Injection in Excel)

- **Schweregrad:** Mittel  ·  **Kategorie:** security  ·  **Konfidenz:** high  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/services/export_service.dart`

**Problem.** `_escapeCsv` (export_service.dart:529-537) quotet ein Feld nur, wenn es `;`, `"` oder `\n` enthaelt. Es entschaerft NICHT fuehrende Formel-Zeichen (`=`, `+`, `-`, `@`, Tab, CR). Alle CSV-Builder (buildShiftPlanCsv, buildCustomerOrderCsv, buildStockListCsv, buildReorderListCsv, buildContactsCsv, buildPersonnelCostCsv) geben benutzerkontrollierte Freitextfelder ungeschuetzt aus: Produktnamen, Kontaktnamen/-notizen (`contact.notes`, `contact.name`), Kundenbestell-Notizen, Schicht-Notizen/Mitarbeiternamen. Ein Feldinhalt wie `=HYPERLINK("http://evil","klick")` oder `=cmd|'/c calc'!A1` landet als formelfaehige Zelle in der Datei. Verschaerfend: Kontakte koennen via `lib/core/contact_csv_import.dart` aus CSV importiert werden (also angreifer-/fremdkontrolliert) und spaeter unveraendert via buildContactsCsv re-exportiert werden — ein klassischer Round-Trip-Injektionsvektor. Die Exporte werden laut CLAUDE.md gezielt fuer deutsches Excel (`;`-Delimiter, BOM) erzeugt; Excel/LibreOffice fuehren formelpraefixierte Zellen beim Oeffnen aus.

**Auswirkung.** Beim Oeffnen eines exportierten CSV in Excel/LibreOffice koennen eingeschleuste Formeln Daten exfiltrieren (HYPERLINK/WEBSERVICE), Inhalte verfaelschen oder (bei aktiviertem DDE) Befehle ausfuehren. In einer mandantenfaehigen App mit importierbaren Kontakten ist das ein realer, fremddatengetriebener Angriffsweg gegen die Mitarbeiter, die Listen oeffnen.

**Empfehlung.** In `_escapeCsv` Zellen, die mit `=`, `+`, `-`, `@`, Tab oder CR beginnen, neutralisieren (gaengig: voranstellen eines `'` oder das Feld mit fuehrendem Apostroph/Leerzeichen quoten) und zusaetzlich quoten. Einen Test analog zu export_service_test.dart ergaenzen, der einen Formel-Praefix asserted.

### 36. PDF-DateFormat ohne explizites 'de_DE' verletzt dokumentierte Invariante und ist latent absturzgefaehrdet

- **Schweregrad:** Niedrig  ·  **Kategorie:** compliance-drift  ·  **Konfidenz:** medium  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/services/pdf_service.dart`

**Problem.** CLAUDE.md schreibt verbindlich vor: 'Jedes `DateFormat` MUSS `'de_DE'` explizit uebergeben.' In pdf_service.dart fehlt der Locale an 5 Stellen: Zeile 21 `static final _timeFormat = DateFormat('HH:mm')` (genutzt fuer ALLE Schicht-/Eintrags-Begin/Ende-Zeiten in _buildEntriesTable und _buildShiftPlanTable), Zeile 967 `DateFormat('dd.MM.yyyy')`, Zeile 1026 `DateFormat('dd.MM.yyyy HH:mm')`, Zeile 1278 `DateFormat('dd.MM.yy')`, Zeile 1350 `DateFormat('dd.MM.yyyy')`. `Intl.defaultLocale` wird nirgends gesetzt (per grep verifiziert: keine Zuweisung in lib/), und `initializeDateFormatting('de_DE', null)` in main.dart laedt nur de_DE + System-Locale-Daten, setzt aber NICHT defaultLocale. Locale-lose DateFormat-Instanzen fallen damit auf `Intl.systemLocale` zurueck. Fuer rein numerische Muster (HH:mm, dd.MM.yyyy) ist der gerenderte Text zwar locale-unabhaengig, aber der DateFormat-Konstruktor ruft `Intl.verifiedLocale` auf, das werfen kann, wenn die System-Locale-Daten nicht initialisiert sind.

**Auswirkung.** Heute meist funktionierend (System-Locale-Daten werden i.d.R. mit-initialisiert), aber: (1) direkter Bruch einer als kritisch dokumentierten Kopplung, der bei einem Refactoring still zu falschem/abstuerzendem Verhalten fuehrt; (2) latentes Risiko einer LocaleDataException bei PDF-Erzeugung auf Geraeten mit exotischer, nicht initialisierter System-Locale.

**Empfehlung.** Alle 5 Vorkommen auf `DateFormat('...', 'de_DE')` umstellen (inkl. der statischen `_timeFormat`-Konstante), konsistent zu den bereits korrekten Stellen (z.B. Zeile 196, 567).

### 37. iOS/iPad-Share-Sheet ohne sharePositionOrigin (Popover ohne Anker)

- **Schweregrad:** Niedrig  ·  **Kategorie:** ux  ·  **Konfidenz:** medium  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/services/download_service_io.dart`

**Problem.** `downloadFileBytes` (download_service_io.dart:9-24) ruft `Share.shareXFiles(...)` ohne den optionalen Parameter `sharePositionOrigin` auf. share_plus (verifiziert in der lokalen Quelle von share_plus 9.0.0/share_plus.dart:118-129) dokumentiert diesen Rect als Ursprung des Share-Sheet-Popovers 'on iPads and Macs'. Ohne Anker hat das Popover auf iPad/macOS keine definierte Ursprungsposition. Laut CLAUDE.md ist iOS ein Release-Ziel (App-Store-Build). Alle Exporte (PDF/CSV/iCal) laufen ueber genau diese eine Funktion.

**Auswirkung.** Auf iPad/macOS erscheint das Teilen-Popover an einer Default-Position (Ecke) statt am ausloesenden Button; je nach iOS-Version kann ein fehlender Ursprung in der Vergangenheit auch zu einer Exception gefuehrt haben. Schlechte/verwirrende Export-UX auf Tablet/Desktop.

**Empfehlung.** `sharePositionOrigin` aus dem RenderBox des ausloesenden Widgets berechnen und durchreichen (Signatur von downloadFileBytes/downloadPdfBytes um einen optionalen `Rect? originRect` erweitern, vom aufrufenden Screen befuellen).

### 38. _escapeCsv quotet einzelnes Carriage-Return (\r) nicht

- **Schweregrad:** Niedrig  ·  **Kategorie:** data-integrity  ·  **Konfidenz:** medium  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/services/export_service.dart`

**Problem.** `_escapeCsv` (export_service.dart:531-533) quotet nur bei `;`, `"` oder `\n` (LF), nicht bei einem alleinstehenden `\r` (CR). Ein Feldwert, der ein nacktes CR ohne LF enthaelt (z.B. aus Windows-/Alt-Mac-Zwischenablage in eine Notiz/einen Namen eingefuegt), wird daher NICHT gequotet. Da jede Zeile mit `buffer.writeln(...)` (haengt `\n` an) geschrieben wird, ergibt sich im Feld eine ungewollte `\r`-Sequenz, die viele CSV-Parser/Excel als Zeilen- bzw. Datensatztrenner interpretieren. Der vorhandene Test deckt nur den `\n`-Fall ab (export_service_test.dart:118-124), nicht `\r`.

**Auswirkung.** Ein Notiz-/Namensfeld mit eingebettetem CR kann die Datensatzstruktur eines exportierten CSV zerstoeren (Spaltenversatz/zusaetzliche Zeile), wodurch nachgelagerte Auswertungen/Importe in Excel die Daten falsch zuordnen.

**Empfehlung.** In `_escapeCsv` die Quote-Bedingung um `normalized.contains('\r')` erweitern; einen Round-Trip-Test mit `\r` und `\r\n` ergaenzen.
