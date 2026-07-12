# Compliance-Spiegel (Dart ↔ Cloud Function)

> Teil des WorkTime-Code-Reviews. Zurück zur [Übersicht](README.md).

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

### 23. correction_reason_required nur serverseitig erzwungen, im Dart-Spiegel/Preview nicht vorhanden

- **Schweregrad:** Niedrig  ·  **Kategorie:** compliance-drift  ·  **Konfidenz:** high  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `functions/index.js:610-621`, `functions/index.js:1266-1274`, `lib/services/compliance_service.dart:352-597`, `lib/screens/entry_form_screen.dart:759-773`, `lib/services/firestore_service.dart:1594-1613`, `lib/providers/work_provider.dart:485-489`, `lib/providers/work_provider.dart:542-544`

**Problem.** functions/index.js fügt bei geänderten bestehenden Zeiteinträgen ohne Begründung die blockierende Verletzung correction_reason_required hinzu (Z.610-621, via correctionReasonRequired). Der Dart-ComplianceService kennt diesen Code nicht; validateWorkEntry erzeugt ihn nirgends. Da der Client laut CLAUDE.md die Compliance-Preview clientseitig über ComplianceService macht (previewCompliance wird nicht aufgerufen), sieht der Nutzer diese Verletzung erst beim finalen Speichern als generischen StateError.

**Auswirkung.** Der Nutzer ändert einen bestehenden Eintrag, der Client meldet keine Verletzung (Preview grün), der Server lehnt jedoch mit failed-precondition ab. Im Hybrid-/Fallback-Pfad kann das je nach Fehlerbehandlung zu einem stillen lokalen Fallback führen, der die Begründungspflicht umgeht, oder zu verwirrender später Fehlermeldung. Inkonsistente UX und potenziell umgangene Korrektur-Begründungspflicht.

**Beleg.** index.js Z.615: violations.push({code: "correction_reason_required", ...}); grep in compliance_service.dart nach correction -> kein Treffer.

**Empfehlung.** Entweder correction_reason_required-Logik in compliance_service.dart spiegeln (erfordert Zugriff auf den bestehenden Eintrag zum Vergleich von start/end/break/siteId) oder im UI explizit eine Begründung bei Änderungen bestehender Einträge erzwingen, bevor gespeichert wird.

### 24. Spiegel-Drift bei Pausen-/Break-Rundung: JS subtrahiert ungerundete breakMinutes, Dart rundet break vor Subtraktion

- **Schweregrad:** Niedrig  ·  **Kategorie:** compliance-drift  ·  **Konfidenz:** medium  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/services/compliance_service.dart:45-47`, `lib/services/compliance_service.dart:429-430`, `lib/services/compliance_service.dart:436`, `functions/index.js:1255-1264`, `functions/index.js:730`, `functions/index.js:908`

**Problem.** Dart berechnet durationMinutes/workedMinutes als ...inMinutes - shift.breakMinutes.round() (Z.46-47, 429-430) und vergleicht required > shift.breakMinutes.round(). JS workedMinutesFromShift = Math.round((end-start)/60000 - Number(breakMinutes)) — die Pause wird hier NICHT vorab gerundet, sondern die Differenz als Ganzes gerundet; der break_required-Vergleich nutzt Math.round(shift.breakMinutes). Bei fraktionalen breakMinutes (z.B. 30,5) ergeben sich um 1 Minute abweichende Arbeitszeit-/Pausenwerte zwischen Client und Server, was an Pausen-/Stundengrenzen unterschiedliche Verletzungen auslösen kann.

**Auswirkung.** Edge-Case: An exakten Schwellen (z.B. workedMinutes == afterMinutes 360/540 nach Rundung) kann Client break_required melden, Server nicht (oder umgekehrt). Praktisch selten, da breakMinutes meist ganzzahlig sind, aber echte Spiegel-Abweichung.

**Beleg.** Dart: shift.endTime.difference(shift.startTime).inMinutes - shift.breakMinutes.round(); JS: Math.round((shift.endTime - shift.startTime)/60000 - Number(shift.breakMinutes || 0)).

**Empfehlung.** Rundungsstrategie vereinheitlichen: entweder beide Seiten Math.round(break) vor Subtraktion oder beide die Gesamtdifferenz runden. Da break in der UI meist ganzzahlig ist, niedrige Priorität, aber bei Angleichung mit erledigen.

### 25. JS dedupliziert Verletzungen, Dart nicht — abweichende Violation-Listen

- **Schweregrad:** Niedrig  ·  **Kategorie:** compliance-drift  ·  **Konfidenz:** high  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `functions/index.js:869`, `functions/index.js:931`, `functions/index.js:1277-1287`, `lib/services/compliance_service.dart:349`

**Problem.** validateSingleShift/validateSingleWorkEntry in JS geben dedupeViolations(violations) zurück (Z.869, 931), das nach code|severity|message dedupliziert. Der Dart-ComplianceService gibt die Rohliste ohne Deduplizierung zurück (Z.349, 596). Bei mehrfach auslösbaren Regeln (z.B. rest_time zu previous UND next mit gleicher Message, oder travel_time_missing beidseitig) kann der Client doppelte Einträge anzeigen, die der Server kollabiert.

**Auswirkung.** Kosmetisch/UX: Client zeigt ggf. doppelte Verletzungsmeldungen; Server-Antwort und Client-Preview unterscheiden sich in der Anzahl. Keine falsche Block/Allow-Entscheidung, da Dedup nur Duplikate entfernt.

**Beleg.** index.js: return dedupeViolations(violations); (Z.869) vs compliance_service.dart: return violations; (Z.349) ohne Dedup.

**Empfehlung.** Im Dart-ComplianceService am Ende beider Validate-Methoden analog dedupen (nach code+severity+message), um Spiegelgleichheit und saubere UI herzustellen.

### 26. Konfigurierbares Nachtfenster (nightWindowStart/End 23:00–06:00) wird in Jugend-/Mutterschutz-Prüfung ignoriert (hartkodiert 06:00/20:00) — in beiden Spiegeln

- **Schweregrad:** Niedrig  ·  **Kategorie:** bug  ·  **Konfidenz:** medium  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/services/compliance_service.dart:996-1001`, `functions/index.js:1669-1673`, `lib/services/compliance_service.dart:831-843`, `functions/index.js:1149-1155`, `functions/index.js:1523-1524`, `lib/models/compliance_rule_set.dart:45-46`

**Problem.** _overlapsNightWindow (Dart Z.996-1001) und overlapsNightWindow (JS Z.1669-1673) prüfen hart start.hour < 6 || end.hour >= 20 || nicht-selber-Tag. Die im RuleSet gepflegten Felder nightWindowStartMinutes (Default 23*60) und nightWindowEndMinutes (Default 6*60) — geladen in fromFirestoreRuleSet Z.1523-1524 und im Dart-Modell vorhanden — werden in dieser Funktion NICHT verwendet. Beide Spiegel sind untereinander konsistent (kein Drift zwischen Dart und JS), aber sie ignorieren die konfigurierte Schwelle und die in CLAUDE.md dokumentierte Nacht-Definition 23:00–06:00.

**Auswirkung.** Eine Org, die das Nachtfenster pro RuleSet anpasst, hat keinerlei Wirkung auf die Jugend-/Mutterschutz-Nachtprüfung — die 20:00/06:00-Grenze ist fest verdrahtet. Das kann für Jugendliche (JArbSchG, Nachtarbeit-Verbot) zu falschen Block/Allow-Entscheidungen führen, abweichend von der konfigurierten Regel. Da konsistent auf beiden Seiten, kein Spiegel-Bruch, aber funktional ein versteckter Korrektheitsfehler.

**Beleg.** Dart Z.1000: return start.hour < 6 || end.hour >= 20 || !_isSameDay(start, end); RuleSet-Felder nightWindowStartMinutes/EndMinutes werden nirgends in compliance_service.dart gelesen.

**Empfehlung.** Entscheiden, ob die Jugend-/Mutterschutz-Nachtfenster bewusst eigene (strengere) feste Grenzen haben sollen; falls die RuleSet-Felder maßgeblich sein sollen, _overlapsNightWindow/overlapsNightWindow auf ruleSet.nightWindowStartMinutes/EndMinutes umstellen (in beiden Spiegeln gleichzeitig) und übernächtige Fenster korrekt behandeln.
