# Kritische & hohe Befunde (Triage zuerst)

> Gebündelte Sicht der dringendsten Punkte. Volltext jeweils auch in der jeweiligen Bereichsdatei.

### 1. Serverseitige Zeiteintrag-Compliance prüft nur 4 von ~12 Regeln (Spiegel-Drift: validateSingleWorkEntry << validateWorkEntry)

- **Schweregrad:** Kritisch  ·  **Kategorie:** compliance-drift  ·  **Konfidenz:** high  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `functions/index.js:872-932`, `functions/index.js:561-608`, `lib/services/compliance_service.dart:352-597`

**Problem.** functions/index.js validateSingleWorkEntry validiert ausschließlich site_required, site_assignment_missing, break_required und daily_limit (Zeilen 888-929). Der Dart-Spiegel validateWorkEntry prüft dagegen zusätzlich: invalid_range (Z.380), overlap_existing (Z.411-427), daily_average_warning (Z.462-472), rest_time / Ruhezeit-Lücke zu vorigem UND nächstem Eintrag inkl. Fahrtzeitregeln (Z.474-507), minijob_limit (Z.509-534), minor_night_work + minor_daily_limit (Z.536-556), pregnancy_night_work + pregnancy_daily_limit (Z.558-578) und overtime_warning (Z.580-594). grep bestätigt: minijob_limit/minor_night_work/pregnancy_*/rest_time/overtime_warning/overlap_existing kommen in index.js NUR in validateSingleShift vor, nie im Work-Entry-Pfad. Konsequenterweise lädt validateWorkEntry-Context (Z.561-608) auch keine travelTimeRules und übergibt keine.

**Auswirkung.** Der Server ist die einzige verlässliche Compliance-Grenze (Client-Checks lassen sich umgehen / direkte Firestore-Writes ebenfalls). Über die Callable upsertWorkEntry/upsertWorkEntryBatch lassen sich Zeiteinträge speichern, die die gesetzlich relevanten Ruhezeit-, Minijob-, Jugendschutz- (JArbSchG) und Mutterschutz-Regeln verletzen, weil der Server sie gar nicht prüft. Blockierende Verletzungen, die der Client anzeigt, werden serverseitig nicht durchgesetzt -> rechtliches/Lohn-Risiko und inkonsistentes Verhalten (Client blockt, Server akzeptiert nach Umgehung).

**Beleg.** index.js validateSingleWorkEntry endet nach daily_limit mit return dedupeViolations(violations); (Z.931) — keine rest/minijob/minor/pregnancy-Blöcke. Dart hat alle ab Z.474.

**Empfehlung.** validateSingleWorkEntry in functions/index.js exakt an validateWorkEntry angleichen: invalid_range, overlap_existing, daily_average_warning-Zweig, Ruhezeit-Gaps zu vorigem/nächstem Eintrag (mit travelTimeRules im Context laden), minijob_limit, minor/pregnancy-Checks und overtime_warning ergänzen. travelTimeRules in validateWorkEntry-Context (Z.561-608) mitladen und durchreichen.

### 2. Drift bei Tages-/Monats-Minutenaggregation: Dart rundet auf volle Stunden (workedHours.round()*60), JS minutengenau

- **Schweregrad:** Hoch  ·  **Kategorie:** compliance-drift  ·  **Konfidenz:** high  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/services/compliance_service.dart:181`, `lib/services/compliance_service.dart:229`, `lib/services/compliance_service.dart:450`, `functions/index.js:743`, `functions/index.js:784`, `functions/index.js:919`, `functions/index.js:1255-1264`

**Problem.** Dart akkumuliert die Arbeitszeit benachbarter Schichten/Einträge als candidate.workedHours.round() * 60 (Operatorrang: erst .round() der Bruchstunden, dann *60). Eine 7,5-h-Schicht wird so als 8*60=480 Min, eine 7,4-h-Schicht als 7*60=420 Min gezählt. JS nutzt an denselben Stellen workedMinutesFromShift/workedMinutesFromEntry = Math.round((end-start)/60000 - breakMinutes), also minutengenau (450 Min). Betrifft plannedDayMinutes (daily_limit/daily_average), monthlyMinutes (minijob_limit) und sameDayMinutes im Entry-Pfad.

**Auswirkung.** Client und Server fällen für identische Daten unterschiedliche Grenzwert-Entscheidungen (z.B. Tageslimit 600 Min, Minijob 60300 Cent). Der Dart-Wert ist zudem systematisch verfälscht: bei .5-Stunden überschätzt er, sonst meist unterschätzt er die akkumulierte Zeit -> falsche Blockierungen ODER fälschlich erlaubte Überschreitungen von Tages-/Monatsgrenzen. Bei Minijob kann das zu falscher 60300-Cent-Bewertung und damit Verlust des Minijob-Status führen.

**Beleg.** Dart: (sum, candidate) => sum + candidate.workedHours.round() * 60 (Z.181); JS: (sum, candidate) => sum + workedMinutesFromShift(candidate) (Z.743).

**Empfehlung.** In compliance_service.dart die Aggregation auf minutengenaue Arbeitszeit umstellen, analog JS: statt candidate.workedHours.round() * 60 die Minuten direkt (endTime.difference(startTime).inMinutes - breakMinutes.round()) summieren. Alle vier Stellen (Schicht-Tag, Schicht-Monat, Entry-Tag, Entry-Monat) angleichen.

### 3. Hybrid-/Cloud-Fallback erzeugt Duplikat-Dokumente bei verlorenem Callable-Ack (deterministische Server-ID vs. zufällige Client-ID)

- **Schweregrad:** Hoch  ·  **Kategorie:** data-integrity  ·  **Konfidenz:** high  ·  **Status:** selbst verifiziert
- **Fundstellen:** `lib/services/firestore_service.dart`, `functions/index.js`

**Problem.** Der Server leitet für neue Zeiteinträge/Schichten ohne id eine DETERMINISTISCHE Doc-ID aus dem Inhalt ab (functions/index.js:143 `buildWorkEntryDocumentId`, :449 `buildShiftDocumentId`). Der direkte Fallback-Pfad im Client schreibt dagegen mit einer ZUFÄLLIGEN Auto-ID: `_saveWorkEntryDirect` (firestore_service.dart:657-658) und `_saveShiftBatchDirect` (:1347-1350) nutzen `entry.id == null ? collection.doc() : ...`. Szenario: Callable `upsertWorkEntry`/`upsertWorkEntryBatch`/`upsertShiftBatch` committet serverseitig erfolgreich, aber die Antwort geht als `unavailable` verloren (Netzabbruch nach Commit). `_callCloudFunctionIfAvailable` gibt bei `unavailable` `false` zurück (firestore_service.dart:1599-1601) → der direkte Fallback schreibt denselben Eintrag erneut, diesmal unter einer zufälligen ID. Ergebnis: zwei Dokumente desselben Eintrags. Ein späteres Edit (wieder über Callable) trifft nur die deterministische ID und lässt das zufällig-ID-Duplikat verwaist zurück.

**Auswirkung.** Doppelte Zeiteinträge/Schichten → falsche Arbeitszeit-/Lohn-/Compliance-Summen (z. B. doppelte Stunden in Personalkosten/Lohnabrechnung). Nutzer sieht dieselbe Schicht zweimal. Die im Kommentar (firestore_service.dart:1586-1588) behauptete Idempotenz greift NUR auf dem Callable-Retry-Pfad, nicht auf dem direkten Fallback-Pfad.

**Beleg.** Server: `const docId = entry.id ?? buildWorkEntryDocumentId(entry)` (index.js:143). Client-Fallback: `entry.id == null ? collection.doc() : collection.doc(entry.id)` (firestore_service.dart:657-658, gleiches Muster :1347-1350).

**Empfehlung.** Im direkten Fallback dieselbe deterministische Doc-ID verwenden wie der Server (gemeinsame Hash-Funktion in compliance_service-ähnlichem geteilten Code oder Dart-Portierung von buildWorkEntryDocumentId/buildShiftDocumentId), oder vor dem Fallback einen idempotenten Pre-Write (clientseitig erzeugte stabile id setzen, bevor der Callable aufgerufen wird) durchführen. Generell: client-generierte stabile IDs für Neuanlagen, damit Callable- und Direktpfad dieselbe Identität schreiben.

### 4. parseEuroToCents interpretiert den Punkt immer als Tausendertrenner – Preiseingabe "1.99" wird zu 199,00 € statt 1,99 €

- **Schweregrad:** Hoch  ·  **Kategorie:** data-integrity  ·  **Konfidenz:** high  ·  **Status:** selbst verifiziert
- **Fundstellen:** `lib/screens/inventory_screen.dart`, `lib/screens/scanner_screen.dart`, `lib/screens/customer_order_screen.dart`

**Problem.** Sowohl `parseEuroToCents` (lib/screens/inventory_screen.dart:34) als auch die identische Kopie `_parseEuroToCents` (lib/screens/customer_order_screen.dart:27) normalisieren mit `trimmed.replaceAll('.', '').replaceAll(',', '.')`. Der Punkt wird also IMMER ersatzlos entfernt (als Tausendertrenner gewertet), bevor das Komma zum Dezimalpunkt wird. Eine Eingabe mit Punkt als Dezimaltrenner ergibt damit den 100-fachen Wert. Verifiziert per Dart-Lauf: "1.99" -> 19900 Cent (=199,00 €), "12.50" -> 125000 Cent, "0.99" -> 9900 Cent; korrekt nur "1,99" -> 199. Der Doc-Kommentar der Funktion behauptet ausdrücklich, sie verarbeite "1,99" ODER "1.99" – das ist falsch. Die betroffenen Preisfelder benutzen `TextInputType.numberWithOptions(decimal: true)` OHNE InputFormatter (Scanner _changePrice: scanner_screen.dart:568-573; Positions-Preis im Kundenbestelldialog: customer_order_screen.dart:1303-1311), sodass viele Tastaturen/Locales tatsächlich einen Punkt liefern.

**Auswirkung.** Falsche Verkaufs-/Einkaufspreise werden um Faktor 100 zu hoch gespeichert. Im Scanner-Preisupdate landet der Fehler direkt am Artikel (updateProductPrices), in Kundenbestellungen in den Positionspreisen/Summen. Geld-Daten werden korrumpiert; der Nutzer bekommt keine Warnung, weil die Eingabe scheinbar gültig parst.

**Beleg.** inventory_screen.dart:39 `final normalized = trimmed.replaceAll('.', '').replaceAll(',', '.');` (identisch customer_order_screen.dart:32). Doc-Kommentar inventory_screen.dart:33 behauptet "1.99" werde unterstützt. Dart-Probe bestätigte "1.99"->19900.

**Empfehlung.** Eingabe robust parsen: nur den LETZTEN von Punkt/Komma als Dezimaltrenner behandeln und alle vorherigen Trenner entfernen (oder bei genau einem Punkt ohne Komma den Punkt als Dezimalpunkt akzeptieren). Zusätzlich plausibilisieren und auf den Preisfeldern einen InputFormatter setzen, der nur Ziffern + ein Dezimalzeichen erlaubt. Die duplizierte Funktion zu einer gemeinsamen Helfer-Funktion zusammenführen.

### 5. Übernacht-Schichten können im Schicht-Editor nicht angelegt werden (Endzeit < Startzeit wird als Fehler abgewiesen)

- **Schweregrad:** Hoch  ·  **Kategorie:** bug  ·  **Konfidenz:** high  ·  **Status:** selbst verifiziert
- **Fundstellen:** `lib/screens/shift_planner/shift_editor_sheet.dart`

**Problem.** Im Schicht-Editor werden Start- und Endzeitpunkt über die Getter `_selectedStartDateTime` und `_selectedEndDateTime` (Zeilen 1797-1811) gebildet, die BEIDE dasselbe Kalenderdatum `_date` verwenden und nur `_startTime`/`_endTime` einsetzen. Es gibt keinerlei Tages-Rollover, wenn die gewählte Endzeit zeitlich vor der Startzeit liegt. In `_buildProposedShifts` (Zeile 1606) sowie in `_buildTemplateDraft` (Zeile 1452) wird dann `if (!endTime.isAfter(startTime))` bzw. `if (endMinutes <= startMinutes)` geprüft und mit 'Endzeit muss nach Startzeit liegen.' abgebrochen. Eine Schicht von z. B. 22:00 bis 06:00 ist somit nicht erfassbar, obwohl das Datenmodell `Shift` (endTime kann auf den Folgetag fallen) und die Compliance-Logik (Nachtfenster 23:00-06:00) Nachtschichten ausdrücklich vorsehen. Auch `_AdditionalShiftAssignmentDraft` über `_dateTimeFor` (Zeile 1813) hat dasselbe Problem.

**Auswirkung.** Ein zentraler Anwendungsfall der Schichtplanung – Nacht-/Übernacht-Schichten (im Einzelhandel/Gastro üblich, hier sogar mit eigenem Nachtfenster-Regelwerk) – ist über die UI komplett unmöglich. Planer erhalten stattdessen die irreführende Fehlermeldung, ihre Endzeit liege vor der Startzeit, ohne Lösungsweg.

**Beleg.** shift_editor_sheet.dart:1797-1811 (_selectedStart/EndDateTime nutzen identisches _date), :1606 (!endTime.isAfter(startTime) -> return null), :1452 (endMinutes <= startMinutes -> return null), :1743 (Zusatzbesetzung). Modell: lib/models/shift.dart:109 workedHours würde für endTime<startTime negativ.

**Empfehlung.** Beim Bilden von endTime einen Tagesübergang erlauben: Wenn `_endTime` (in Minuten) <= `_startTime`, einen Tag zur Endzeit addieren (z. B. `final end = endMinutes <= startMinutes ? _dateTimeFor(_endTime).add(Duration(days: 1)) : _dateTimeFor(_endTime)`), und die `endTime.isAfter(startTime)`-Validierung entsprechend gegen die so korrigierte Endzeit laufen lassen. Gleiches für Zusatzbesetzungen und für `_buildTemplateDraft` (dort werden startMinutes/endMinutes gespeichert; eine Endzeit < Startzeit als 'nächster Tag' interpretieren).
