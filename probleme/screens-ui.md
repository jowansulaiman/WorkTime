# Screens: Schichtplaner & Team · Screens: Inventar / Scanner / Bestellkorb / Wünsche · Screens: Personal / Zeit / Reports / Settings

> Teil des WorkTime-Code-Reviews. Zurück zur [Übersicht](README.md).

## Screens: Schichtplaner & Team

### 5. Übernacht-Schichten können im Schicht-Editor nicht angelegt werden (Endzeit < Startzeit wird als Fehler abgewiesen)

- **Schweregrad:** Hoch  ·  **Kategorie:** bug  ·  **Konfidenz:** high  ·  **Status:** selbst verifiziert
- **Fundstellen:** `lib/screens/shift_planner/shift_editor_sheet.dart`

**Problem.** Im Schicht-Editor werden Start- und Endzeitpunkt über die Getter `_selectedStartDateTime` und `_selectedEndDateTime` (Zeilen 1797-1811) gebildet, die BEIDE dasselbe Kalenderdatum `_date` verwenden und nur `_startTime`/`_endTime` einsetzen. Es gibt keinerlei Tages-Rollover, wenn die gewählte Endzeit zeitlich vor der Startzeit liegt. In `_buildProposedShifts` (Zeile 1606) sowie in `_buildTemplateDraft` (Zeile 1452) wird dann `if (!endTime.isAfter(startTime))` bzw. `if (endMinutes <= startMinutes)` geprüft und mit 'Endzeit muss nach Startzeit liegen.' abgebrochen. Eine Schicht von z. B. 22:00 bis 06:00 ist somit nicht erfassbar, obwohl das Datenmodell `Shift` (endTime kann auf den Folgetag fallen) und die Compliance-Logik (Nachtfenster 23:00-06:00) Nachtschichten ausdrücklich vorsehen. Auch `_AdditionalShiftAssignmentDraft` über `_dateTimeFor` (Zeile 1813) hat dasselbe Problem.

**Auswirkung.** Ein zentraler Anwendungsfall der Schichtplanung – Nacht-/Übernacht-Schichten (im Einzelhandel/Gastro üblich, hier sogar mit eigenem Nachtfenster-Regelwerk) – ist über die UI komplett unmöglich. Planer erhalten stattdessen die irreführende Fehlermeldung, ihre Endzeit liege vor der Startzeit, ohne Lösungsweg.

**Beleg.** shift_editor_sheet.dart:1797-1811 (_selectedStart/EndDateTime nutzen identisches _date), :1606 (!endTime.isAfter(startTime) -> return null), :1452 (endMinutes <= startMinutes -> return null), :1743 (Zusatzbesetzung). Modell: lib/models/shift.dart:109 workedHours würde für endTime<startTime negativ.

**Empfehlung.** Beim Bilden von endTime einen Tagesübergang erlauben: Wenn `_endTime` (in Minuten) <= `_startTime`, einen Tag zur Endzeit addieren (z. B. `final end = endMinutes <= startMinutes ? _dateTimeFor(_endTime).add(Duration(days: 1)) : _dateTimeFor(_endTime)`), und die `endTime.isAfter(startTime)`-Validierung entsprechend gegen die so korrigierte Endzeit laufen lassen. Gleiches für Zusatzbesetzungen und für `_buildTemplateDraft` (dort werden startMinutes/endMinutes gespeichert; eine Endzeit < Startzeit als 'nächster Tag' interpretieren).

### 15. Schichtzeiten auf dem Admin-Board werden in englischem 12-Stunden-Format (AM/PM) statt deutschem HH:mm angezeigt

- **Schweregrad:** Mittel  ·  **Kategorie:** compliance-drift  ·  **Konfidenz:** high  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/screens/shift_planner/planner_cells.dart`

**Problem.** In `_PlannerBoardShiftCard.build` wird die Zeitformatierung der Schichtkarten auf dem Haupt-Schichtplan-Board mit `final timeFmt = DateFormat('h a', 'en_US');` (Zeile 176) erzeugt und in Zeile 267 als `'${timeFmt.format(shift.startTime)} - ${timeFmt.format(shift.endTime)} · ...h'` gerendert. Das verstößt gegen die in CLAUDE.md verbindlich festgelegte Regel ('Jedes DateFormat MUSS de_DE explizit übergeben' und 'Alle UI-Texte sind Deutsch'). Ausgegeben wird z. B. '10 AM - 6 PM' statt '10:00 - 18:00'. Alle anderen Stellen im Modul nutzen korrekt `DateFormat('HH:mm', 'de_DE')` (z. B. planner_cells.dart selbst in shift_planner_screen.dart:4004/4074).

**Auswirkung.** Auf der wichtigsten Admin-Ansicht (Wochen-/Tages-Board) erscheinen alle Schichtzeiten in englischem AM/PM-Format. Für deutsche Nutzer unerwartet und potenziell mehrdeutig; das Format 'h a' lässt zudem Minuten weg (10:30 würde als '10 AM' verfälscht dargestellt). Inkonsistent zum Rest der App, die 24h-Zeiten zeigt.

**Beleg.** planner_cells.dart:176 `final timeFmt = DateFormat('h a', 'en_US');`, verwendet in :267. Regel: CLAUDE.md 'Jedes DateFormat MUSS de_DE explizit übergeben.'

**Empfehlung.** Auf `DateFormat('HH:mm', 'de_DE')` umstellen (konsistent mit den übrigen Zeitdarstellungen) und die Minuten einbeziehen.

### 16. Serverseitige Compliance-Ablehnung im Schicht-Editor verliert strukturierte Verstöße und zeigt 'Bad state:'-Präfix

- **Schweregrad:** Mittel  ·  **Kategorie:** error-handling  ·  **Konfidenz:** high  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/screens/shift_planner_screen.dart`, `lib/services/compliance_rejected_exception.dart`

**Problem.** `_openShiftEditor` (shift_planner_screen.dart:825-847) fängt zuerst `ShiftConflictException` (zeigt Konfliktdialog), danach generisch `catch (error)` mit `SnackBar(content: Text(error.toString()))`. Wird eine Schicht serverseitig wegen einer blockierenden Compliance-Verletzung abgelehnt, wirft der Service eine `ComplianceRejectedException` (firestore_service.dart:1606), die `extends StateError` (compliance_rejected_exception.dart:14) und die strukturierten `violations` mitträgt. Da diese keine `ShiftConflictException` ist, landet sie im generischen Handler: (1) `StateError.toString()` liefert 'Bad state: <deutsche Meldung>', der englische Präfix wird – anders als in team_management_screen.dart, das `.replaceFirst('Bad state: ', '')` nutzt – NICHT entfernt; (2) die im Service bewusst bewahrte `violations`-Liste wird verworfen und nicht über `_showShiftConflictDialog`/`_ShiftConflictList` angezeigt. `_copyWeek` (Zeile 677) hat denselben generischen Fallback.

**Auswirkung.** Bei serverseitiger Ablehnung (z. B. Regeln, die die clientseitige Vorschau nicht abdeckt, oder veraltete Client-Daten) sieht der Planer eine technisch wirkende Meldung mit 'Bad state:' und keine Aufschlüsselung der konkreten Verstöße, obwohl diese strukturiert vorliegen. Der UX-Mehrwert der ComplianceRejectedException-Einführung verpufft an diesem Call-Site.

**Beleg.** shift_planner_screen.dart:831-846 (catch-Reihenfolge, Text(error.toString())), :677 (_copyWeek generic catch); compliance_rejected_exception.dart:14 (extends StateError, trägt violations); firestore_service.dart:1604-1611.

**Empfehlung.** In `_openShiftEditor` (und `_copyWeek`) zusätzlich `on ComplianceRejectedException catch (e)` behandeln und die `e.violations` in einem Dialog/Liste rendern; mindestens das 'Bad state: '-Präfix wie in team_management_screen.dart entfernen.

### 54. Abwesenheiten werden pro Board-Zelle neu gefiltert und sortiert (quadratischer Aufwand pro Frame)

- **Schweregrad:** Niedrig  ·  **Kategorie:** performance  ·  **Konfidenz:** high  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/screens/shift_planner_screen.dart`

**Problem.** Während Schichten im Board bewusst einmalig pro Build in Buckets gruppiert werden (Kommentar 'planner-build-on-on-quadratic-filtering', _groupShiftsByRow/_groupShiftsByDay), gibt es für Abwesenheiten keine solche Vorgruppierung. `_buildPlannedRow` ruft pro Tag `_rowAbsencesForDay(row, day)` (Zeile 2651), das wiederum `_dayAbsences(day)` (Zeile 3419) aufruft. `_dayAbsences` iteriert jedes Mal komplett über `widget.visibleAbsenceRequests`, ruft pro Eintrag `_matchesAbsenceFilters` + `request.overlaps(...)` auf und sortiert das Ergebnis anschließend mit `..sort(_plannerAbsenceRequestSort)`. Damit entsteht O(Zeilen × Tage × Abwesenheiten) plus eine Sortierung je Zelle in jedem Build. Zusätzlich rufen `_dayAbsences`/`_applyBoardFilters` jeweils `context.read<ScheduleProvider>()` auf.

**Auswirkung.** Bei vielen Mitarbeiterzeilen und Abwesenheiten unnötige CPU-Last und potenzielles Scroll-Jank im Board – genau das Problem, das für Schichten bereits gelöst wurde, bleibt für Abwesenheiten bestehen.

**Beleg.** shift_planner_screen.dart:3419-3443 (_dayAbsences iteriert+sortiert pro Aufruf), :3433-3444 (_rowAbsencesForDay ruft _dayAbsences), :2647-2658 (_buildPlannedRow ruft pro Tag _rowAbsencesForDay); Kontrast: :979-993 + :1023-1024 (Schicht-Bucketing).

**Empfehlung.** Abwesenheiten analog zu Schichten einmalig pro Build nach Tag (und ggf. Mitarbeiter) in Buckets gruppieren und in `_buildPlannedRow`/`_buildHeaderRow` nur per Lookup lesen; Sortierung einmalig statt pro Zelle.

### 55. Mehrere DateFormat-Aufrufe ohne explizites 'de_DE' (Verstoß gegen Projekt-Invariante)

- **Schweregrad:** Niedrig  ·  **Kategorie:** compliance-drift  ·  **Konfidenz:** medium  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/screens/shift_planner/planner_cells.dart`, `lib/screens/shift_planner/shift_editor_sheet.dart`, `lib/screens/team_management_screen.dart`, `lib/screens/shift_planner_screen.dart`

**Problem.** CLAUDE.md schreibt vor: 'Jedes DateFormat MUSS de_DE explizit übergeben.' Mehrere Stellen im Schichtplaner-/Teamverwaltungs-Bereich verletzen das: planner_cells.dart:308 `DateFormat('dd.MM.yyyy')` (Abwesenheits-Pill Tooltip), shift_editor_sheet.dart:796 und :1126 (`_date` bzw. Wiederholungs-Enddatum), team_management_screen.dart:2563 ('Gültig ab'), shift_planner_screen.dart:4144 (`endFmt = DateFormat('HH:mm')` in der Schicht-Detailkarte), :4345 und :5246/:5253 (Abwesenheits-Editor 'Von'/'Bis'). Bei rein numerischen Mustern (dd.MM.yyyy, HH:mm) ist die Ausgabe locale-unabhängig, daher i. d. R. ohne sichtbaren Effekt – dennoch ein konsistenter Regelverstoß und ein latentes Risiko, falls ein Muster künftig Monats-/Wochentagsnamen erhält oder der globale Default-Locale sich ändert.

**Auswirkung.** Aktuell überwiegend kosmetischer/konsistenzbezogener Verstoß ohne falsche Ausgabe; erhöht jedoch das Risiko, dass beim Erweitern eines Musters (z. B. um 'MMM'/'EEE') versehentlich eine nicht-deutsche Ausgabe entsteht, und untergräbt die im Projekt bewusst gesetzte Invariante.

**Beleg.** Grep-Ergebnis: planner_cells.dart:308; shift_editor_sheet.dart:796,1126; team_management_screen.dart:2563; shift_planner_screen.dart:4144,4345,5246,5253 (alle ohne 'de_DE').

**Empfehlung.** Allen genannten DateFormat-Instanzen das Locale-Argument 'de_DE' hinzufügen, konsistent zu den korrekt lokalisierten Aufrufen im selben Modul.

## Screens: Inventar / Scanner / Bestellkorb / Wünsche

### 4. parseEuroToCents interpretiert den Punkt immer als Tausendertrenner – Preiseingabe "1.99" wird zu 199,00 € statt 1,99 €

- **Schweregrad:** Hoch  ·  **Kategorie:** data-integrity  ·  **Konfidenz:** high  ·  **Status:** selbst verifiziert
- **Fundstellen:** `lib/screens/inventory_screen.dart`, `lib/screens/scanner_screen.dart`, `lib/screens/customer_order_screen.dart`

**Problem.** Sowohl `parseEuroToCents` (lib/screens/inventory_screen.dart:34) als auch die identische Kopie `_parseEuroToCents` (lib/screens/customer_order_screen.dart:27) normalisieren mit `trimmed.replaceAll('.', '').replaceAll(',', '.')`. Der Punkt wird also IMMER ersatzlos entfernt (als Tausendertrenner gewertet), bevor das Komma zum Dezimalpunkt wird. Eine Eingabe mit Punkt als Dezimaltrenner ergibt damit den 100-fachen Wert. Verifiziert per Dart-Lauf: "1.99" -> 19900 Cent (=199,00 €), "12.50" -> 125000 Cent, "0.99" -> 9900 Cent; korrekt nur "1,99" -> 199. Der Doc-Kommentar der Funktion behauptet ausdrücklich, sie verarbeite "1,99" ODER "1.99" – das ist falsch. Die betroffenen Preisfelder benutzen `TextInputType.numberWithOptions(decimal: true)` OHNE InputFormatter (Scanner _changePrice: scanner_screen.dart:568-573; Positions-Preis im Kundenbestelldialog: customer_order_screen.dart:1303-1311), sodass viele Tastaturen/Locales tatsächlich einen Punkt liefern.

**Auswirkung.** Falsche Verkaufs-/Einkaufspreise werden um Faktor 100 zu hoch gespeichert. Im Scanner-Preisupdate landet der Fehler direkt am Artikel (updateProductPrices), in Kundenbestellungen in den Positionspreisen/Summen. Geld-Daten werden korrumpiert; der Nutzer bekommt keine Warnung, weil die Eingabe scheinbar gültig parst.

**Beleg.** inventory_screen.dart:39 `final normalized = trimmed.replaceAll('.', '').replaceAll(',', '.');` (identisch customer_order_screen.dart:32). Doc-Kommentar inventory_screen.dart:33 behauptet "1.99" werde unterstützt. Dart-Probe bestätigte "1.99"->19900.

**Empfehlung.** Eingabe robust parsen: nur den LETZTEN von Punkt/Komma als Dezimaltrenner behandeln und alle vorherigen Trenner entfernen (oder bei genau einem Punkt ohne Komma den Punkt als Dezimalpunkt akzeptieren). Zusätzlich plausibilisieren und auf den Preisfeldern einen InputFormatter setzen, der nur Ziffern + ein Dezimalzeichen erlaubt. Die duplizierte Funktion zu einer gemeinsamen Helfer-Funktion zusammenführen.

### 12. Kamerafehler im Scanner wird nie zurückgesetzt – Fehlerüberlagerung bleibt nach Wiederherstellung sichtbar

- **Schweregrad:** Mittel  ·  **Kategorie:** error-handling  ·  **Konfidenz:** high  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/screens/scanner_screen.dart`

**Problem.** `_cameraError` wird in `_startScanner` bei einem Startfehler gesetzt (scanner_screen.dart:182-187), aber an keiner Stelle wieder auf null gesetzt (Grep: nur Set/Reads, kein weiteres Set). Bei einem erfolgreichen Start (auch nach App-Resume via didChangeAppLifecycleState oder nach Ladenwechsel, der `_startScanner()` erneut aufruft) bleibt der alte Fehler erhalten. Die Folge: die Hinweis-Box (`_buildScanArea`, scanner_screen.dart:845 `_cameraError ?? ...`) und das schwarze Overlay (scanner_screen.dart:867-877) zeigen weiterhin „Kamera nicht verfügbar … manuell eingeben“, obwohl die Kamera inzwischen läuft.

**Auswirkung.** Nutzer, die einmal die Kamera-Berechtigung verweigert (oder einen transienten Startfehler) hatten und sie später erlauben/zurückkehren, sehen dauerhaft die Fehlermeldung über dem (funktionierenden) Kamerabild, bis sie den Screen komplett neu öffnen. Verwirrend und lässt Scan-Funktion fälschlich als kaputt erscheinen.

**Beleg.** scanner_screen.dart:74 Deklaration; :183 einziges Setzen; :845/:867/:873 Reads; `_startScanner` (:176-189) und `didChangeAppLifecycleState` (:158-165) setzen es nie zurück.

**Empfehlung.** In `_startScanner` nach erfolgreichem `_scanner.start()` (bzw. zu Beginn eines Neuversuchs) `setState(() => _cameraError = null)` setzen, damit ein erfolgreicher Start die alte Fehleranzeige löscht.

### 49. Scan & Go: Erfolgs-Feedback (Blitz/Ton) wird vor dem await ausgelöst, auch wenn das Hinzufügen scheitert

- **Schweregrad:** Niedrig  ·  **Kategorie:** ux  ·  **Konfidenz:** medium  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/screens/scanner_screen.dart`

**Problem.** In `_addScannedToCart` (scanner_screen.dart:339-358) werden `_flash(true)` und `_feedback.success()` VOR dem `await inventory.addToCart(...)` aufgerufen. Schlägt `addToCart` fehl, gibt es zwar danach einen Fehler-Snack (Zeile 349), aber der Nutzer hat bereits den grünen Erfolgsblitz und den Erfolgston bekommen. Gleiches Muster in `_chooseAndAddToCart` (Erfolgs-Feedback bei der Mehrfachauswahl vor dem await).

**Auswirkung.** Bei Fehlern (z.B. Persistenz/Cloud-Schreibfehler im cloud-only-Modus) erhält der Kassierer ein widersprüchliches Signal: Erfolgston/Blitz, dann Fehlermeldung. An einer schnellen Selbstscan-Kasse kann das dazu führen, dass der Fehler übersehen wird und der Artikel nicht im Korb landet, obwohl es so „klang“.

**Beleg.** scanner_screen.dart:343-351 `_flash(true); unawaited(_feedback.success()); try { await inventory.addToCart(...) } catch ... _showSnack('Fehler beim Hinzufuegen: $error')`.

**Empfehlung.** Feedback erst nach erfolgreichem `await addToCart` geben; im catch `_flash(false)` + `_feedback.failure()` auslösen. Alternativ optimistisches Feedback beibehalten, aber bei Fehler explizit per Blitz/Ton korrigieren.

### 50. Doppel-Scan-Entprellung (_lastCode/_lastCodeAt) wird beim Moduswechsel nicht zurückgesetzt

- **Schweregrad:** Niedrig  ·  **Kategorie:** ux  ·  **Konfidenz:** medium  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/screens/scanner_screen.dart`

**Problem.** `_onCodeDetected` ignoriert denselben Code für 2 Sekunden (scanner_screen.dart:199-210). `_setMode` (scanner_screen.dart:942-977) leert zwar Treffer-/Zählzustand, setzt aber `_lastCode`/`_lastCodeAt` NICHT zurück. Scannt man einen Artikel im Bestellen-Modus und wechselt direkt in den Buchen-/Inventur-Modus, um denselben Artikel erneut zu scannen, wird der zweite Scan innerhalb der 2-Sekunden-Sperre verschluckt.

**Auswirkung.** Geringer, aber real: ein bewusster erneuter Scan desselben Artikels unmittelbar nach Moduswechsel passiert scheinbar nichts (kein Beep, keine Karte), bis der Nutzer 2 s wartet oder einen anderen Code scannt. Wirkt wie ein hängender Scanner.

**Beleg.** scanner_screen.dart:83-84 Felder; :202-206 Entprell-Check; :967-976 `_setMode`-setState leert nur `_match`, `_multiMatches`, `_inactiveMatch`, `_notFoundCode`, `_lastAddedName`, Zähl-Maps – nicht `_lastCode`/`_lastCodeAt`.

**Empfehlung.** In `_setMode` zusätzlich `_lastCode = ''` und `_lastCodeAt = null` setzen, damit ein Moduswechsel den Entprell-Zustand neutralisiert.

### 51. Öffentliches Wunschformular: keine Längenbegrenzung des Laden-Klartexts gegen die Rules-Grenze von 120 Zeichen

- **Schweregrad:** Niedrig  ·  **Kategorie:** error-handling  ·  **Konfidenz:** low  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/screens/public/public_wish_screen.dart`, `lib/models/customer_wish.dart`, `firestore.rules`

**Problem.** `storeName` stammt im öffentlichen Formular aus einer Dropdown-Liste (`AppConfig.publicStoreNameList`, public_wish_screen.dart:30), wird aber ungeprüft als Klartext in `toPublicSubmissionMap` (customer_wish.dart:212) übernommen. Die firestore.rules verlangen `storeName.size() <= 120` (firestore.rules:840). Da die Ladennamen über `--dart-define=APP_PUBLIC_STORES` frei konfigurierbar sind, kann ein konfigurierter Name >120 Zeichen den Create serverseitig mit permission-denied scheitern lassen. Der Nutzer sieht dann nur die generische Meldung „… für diesen Laden nicht freigeschaltet“ (public_wish_screen.dart:108-110), ohne dass die Ursache (zu langer Ladenname) erkennbar ist.

**Auswirkung.** Fehlkonfiguration (langer Ladenname) macht die gesamte öffentliche Wunschabgabe für diesen Laden unmöglich, mit irreführender Fehlermeldung. Reiner Konfigurationspfad, daher niedrige Schwere; aber schwer zu diagnostizieren.

**Beleg.** firestore.rules:839-840 `storeName is string && storeName.size() <= 120`; customer_wish.dart:212 `'storeName': storeName.trim()` ohne Längenprüfung; public_wish_screen.dart:30 `_stores = AppConfig.publicStoreNameList`.

**Empfehlung.** Beim Aufbau von `publicStoreNameList` Namen auf <=120 Zeichen trimmen/kürzen bzw. validieren, oder im Submission-Pfad defensiv kürzen. Mindestens als bekannte Einschränkung dokumentieren.

## Screens: Personal / Zeit / Reports / Settings

### 13. CSV-Export der Statistik zerstört Umlaute (kein UTF-8, kein BOM)

- **Schweregrad:** Mittel  ·  **Kategorie:** data-integrity  ·  **Konfidenz:** high  ·  **Status:** selbst verifiziert
- **Fundstellen:** `lib/screens/statistics_screen.dart`

**Problem.** `_exportCsv` (statistics_screen.dart) baut die CSV inline und schreibt die Bytes via `final bytes = buffer.toString().codeUnits;` (Zeile 169) ohne vorangestelltes UTF-8-BOM. `String.codeUnits` liefert UTF-16-Code-Units; für Zeichen außerhalb ASCII (deutsche Umlaute ä/ö/ü/ß, z. B. in der frei eingebbaren Notiz-Spalte `entry.note`) entstehen dabei falsche Bytes, sodass die Datei beim Öffnen in Excel/Editor zerstörte Umlaute zeigt. Der zentrale `ExportService` macht es bewusst anders und korrekt: Buffer beginnt mit `'﻿'` (BOM) und wird mit `utf8.encode(csv)` serialisiert (export_service.dart Zeilen 112 und 79/171/245/...). Die CLAUDE.md-Konvention verlangt explizit UTF-8-BOM für deutsche-Excel-CSV.

**Auswirkung.** Jeder CSV-Export aus der Statistik mit umlauthaltigen Notizen liefert beschädigte Daten; in deutschem Excel werden Umlaute außerdem ohne BOM generell falsch interpretiert. Das betrifft Nachweis-/Auswertungsexporte, also die Datenintegrität nach außen.

**Beleg.** statistics_screen.dart:169 `final bytes = buffer.toString().codeUnits;` und Zeile 159-168 (keine BOM-Zeile). Gegenbeispiel export_service.dart:112 `final buffer = StringBuffer('﻿');` + :79/:171 `Uint8List.fromList(utf8.encode(csv))`.

**Empfehlung.** Analog zu ExportService vorgehen: Buffer mit `StringBuffer('﻿')` starten und `Uint8List.fromList(utf8.encode(buffer.toString()))` statt `.codeUnits` an `downloadPdfBytes` übergeben. Idealerweise diesen Export ganz auf `ExportService` heben, um die Konvention an einer Stelle zu halten.

### 14. DateFormat ohne explizites 'de_DE' kann auf nicht-deutschen Geräten crashen (Datum-Muster)

- **Schweregrad:** Mittel  ·  **Kategorie:** error-handling  ·  **Konfidenz:** medium  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/screens/statistics_screen.dart`, `lib/screens/notification_screen.dart`

**Problem.** In `main.dart` wird nur `initializeDateFormatting('de_DE', null)` aufgerufen und `Intl.defaultLocale` NICHT gesetzt. Mehrere `DateFormat`-Aufrufe mit Datum-Symbol-Mustern lassen die Locale weg und fallen damit auf die System-Locale zurück, deren Symboldaten aber nicht geladen wurden: `DateFormat('dd.MM.yyyy')` (statistics_screen.dart:161) und `DateFormat('yyyy-MM')` (für den Dateinamen, :173) im CSV-Export sowie `DateFormat('dd.MM.')` in `_formatTime` (notification_screen.dart:1022 und :1033). `_formatTime` formatiert die Zeitstempel JEDES Inbox-Eintrags, der älter als 7 Tage oder in der Zukunft liegt. Auf einem Gerät mit z. B. en_US als System-Locale wirft `DateFormat` mit Datum-Symbol-Mustern eine `LocaleDataException`, da nur `de_DE` initialisiert ist.

**Auswirkung.** Auf Geräten mit nicht-deutscher System-Locale (App ist aber hart auf de_DE ausgelegt) drohen Laufzeit-Exceptions: das Anfragen-/Benachrichtigungs-Center kann beim Rendern von Einträgen mit Datum-Anzeige abstürzen, und der Statistik-CSV-Export kann fehlschlagen. Verstößt zudem gegen die harte CLAUDE.md-Regel 'Jedes DateFormat MUSS de_DE explizit übergeben'.

**Beleg.** main.dart:108 `await initializeDateFormatting('de_DE', null);` (kein defaultLocale). statistics_screen.dart:161 `DateFormat('dd.MM.yyyy')`, :173 `DateFormat('yyyy-MM')`. notification_screen.dart:1022/:1033 `DateFormat('dd.MM.').format(time)` in `_formatTime`, das in `_InboxItemCard` (Zeile 942) für jeden Eintrag genutzt wird.

**Empfehlung.** Allen genannten `DateFormat`-Konstruktoren `'de_DE'` als zweites Argument mitgeben (konsistent mit den korrekten Aufrufen wie `DateFormat('MMMM yyyy', 'de_DE')` in denselben Dateien). Alternativ `Intl.defaultLocale='de_DE'` global setzen — aber die Konvention bevorzugt das explizite Argument.

### 52. Zeit-DateFormat ('HH:mm') ohne 'de_DE' an vielen Stellen – Konventionsverstoß

- **Schweregrad:** Niedrig  ·  **Kategorie:** compliance-drift  ·  **Konfidenz:** high  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/screens/entry_form_screen.dart`, `lib/screens/month_report_screen.dart`, `lib/screens/notification_screen.dart`

**Problem.** Zahlreiche `DateFormat('HH:mm')`-Aufrufe übergeben keine Locale: entry_form_screen.dart (Zeilen 694, 695, 854, 1209, 1354, 1365), month_report_screen.dart:611, notification_screen.dart:509 und :549. Die reine Uhrzeit-Ausgabe 'HH:mm' ist zwar locale-unabhängig in der Darstellung, aber `DateFormat` benötigt grundsätzlich initialisierte Locale-Symboldaten der aufgelösten Locale. Da nur de_DE initialisiert ist und keine Default-Locale gesetzt wurde, besteht dasselbe latente Risiko wie beim vorigen Befund, und es ist ein klarer Verstoß gegen die CLAUDE.md-Regel.

**Auswirkung.** Inkonsistenz zur dokumentierten Hard-Regel; latentes (geringeres) Crash-Risiko auf Nicht-de-System-Locale beim Erstellen der DateFormat-Instanz. Im de-only-Betrieb funktional unauffällig.

**Beleg.** grep-Treffer: entry_form_screen.dart:694/695/854/1209/1354/1365 `DateFormat('HH:mm')`; month_report_screen.dart:611 `final timeFmt = DateFormat('HH:mm');`; notification_screen.dart:509/549 `DateFormat('HH:mm').format(...)`.

**Empfehlung.** Konsequent `DateFormat('HH:mm', 'de_DE')` verwenden (wie es z. B. bei den Datumsmustern in denselben Screens bereits korrekt gemacht wird), um die Konvention durchzuhalten und das Locale-Daten-Risiko zu eliminieren.

### 53. Lohn-Prefill im Mitarbeiter-Detail nutzt Stunden des falschen Monats

- **Schweregrad:** Niedrig  ·  **Kategorie:** bug  ·  **Konfidenz:** medium  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/screens/personal_screen.dart`

**Problem.** Im `_EmployeeDetailScreen` werden bestehende Lohnabrechnungen über `_PayrollTile` gerendert, dabei wird `month: DateTime(record.periodYear, record.periodMonth)` (also die Periode des Records), aber `monthEntries: monthEntries` (die Zeiteinträge des aktuell im Personal-Screen gewählten Monats) durchgereicht (personal_screen.dart:1510-1515). Öffnet man eine historische Abrechnung aus einem anderen Monat und drückt im `_PayrollEditorSheet` den 'Aus Stunden/Vertrag'-Button (`_prefillGross`), berechnet dieser `_hoursForUser(widget.monthEntries, userId)` aus den Stunden des Screen-Monats statt der Record-Periode. Brutto wird also aus dem falschen Monat vorgeschlagen. (Im `_PayrollTab` ist `month` und `monthEntries` konsistent derselbe Monat, dort tritt das nicht auf.)

**Auswirkung.** Beim Bearbeiten älterer/anderer Monatsabrechnungen über die Mitarbeiter-Detailseite kann der vorausgefüllte Bruttowert falsch sein. Es ist nur ein Vorschlagswert (manuell überschreibbar) und betrifft nur den Prefill-Button, daher geringe Schwere; ein Admin könnte aber unbemerkt einen aus dem falschen Monat abgeleiteten Wert übernehmen.

**Beleg.** personal_screen.dart:1510-1515 (`month: DateTime(record.periodYear, record.periodMonth)` mit `monthEntries: monthEntries`); _prefillGross personal_screen.dart:1973-1989 (`_hoursForUser(widget.monthEntries, userId)`).

**Empfehlung.** Für die Detailseite die Monats-Zeiteinträge passend zur jeweiligen Record-Periode laden (z. B. `loadOrgWorkEntriesForMonth(DateTime(record.periodYear, record.periodMonth))`) oder den Prefill-Button deaktivieren, wenn die Editor-Periode nicht dem geladenen `monthEntries`-Monat entspricht.
