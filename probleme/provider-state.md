# Work- & Schedule-Provider · Team- / Personal- / Auth-Provider · Inventory- / Contact- / Audit-Provider

> Teil des WorkTime-Code-Reviews. Zurück zur [Übersicht](README.md).

## Work- & Schedule-Provider

### 20. Stream-Leak: _allAbsenceSubscription wird in dispose() nicht gecancelt

- **Schweregrad:** Mittel  ·  **Kategorie:** race-lifecycle  ·  **Konfidenz:** high  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/providers/schedule_provider.dart:2059`, `lib/providers/schedule_provider.dart:1643`, `lib/providers/schedule_provider.dart:119`

**Problem.** dispose() cancelt _shiftsSubscription, _absenceSubscription und _templatesSubscription, aber NICHT _allAbsenceSubscription. Diese Subscription wird in _restartSubscriptions() (Zeile 1643) auf einen watchAllAbsenceRequests-Firestore-Stream gesetzt und an allen anderen Stellen (updateSession bei logout/changed) korrekt gecancelt – nur im dispose() fehlt sie.

**Auswirkung.** Beim Verwerfen des ScheduleProvider (Hot-Reload, Logout-Rebuild der Provider-Kette, Org-Wechsel) bleibt ein offener Firestore-Snapshot-Listener auf organizations/{org}/absenceRequests bestehen. Der onData-Callback ruft _safeNotify() auf, das wegen _disposed=true zwar nicht crasht, aber die Subscription läuft weiter, verursacht bezahlte Firestore-Reads und hält den Provider samt _orgMembers/_localAbsenceRequests im Speicher (Memory-Leak). Über mehrere Lebenszyklen akkumulieren sich verwaiste Listener.

**Beleg.** dispose(): nur _shiftsSubscription?.cancel(); _absenceSubscription?.cancel(); _templatesSubscription?.cancel(); — _allAbsenceSubscription fehlt, obwohl es ein eigener langlebiger Stream ist.

**Empfehlung.** In dispose() zusätzlich '_allAbsenceSubscription?.cancel();' aufrufen (analog zu den anderen drei Subscriptions).

### 21. ScheduleProvider cancelt alte Subscriptions erst im listen-Callback statt vor dem Tausch

- **Schweregrad:** Mittel  ·  **Kategorie:** race-lifecycle  ·  **Konfidenz:** medium  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/providers/schedule_provider.dart:1547`, `lib/providers/schedule_provider.dart:1587`, `lib/providers/schedule_provider.dart:1608`, `lib/providers/schedule_provider.dart:1649`, `lib/providers/schedule_provider.dart:1674`, `lib/providers/work_provider.dart:1616`

**Problem.** In _restartSubscriptions wird die alte Subscription (oldShiftsSub/oldAbsenceSub/...) NICHT synchron nach dem Aufbau der neuen gecancelt, sondern erst innerhalb des onData/onError-Callbacks der NEUEN Subscription ('oldShiftsSub?.cancel();' als erste Zeile in jedem listen). WorkProvider macht es korrekt: dort wird nach Aufbau der neuen Subscriptions 'await oldEntriesSub?.cancel()' aufgerufen (work_provider.dart:1616).

**Auswirkung.** Emittiert der neue Stream (z.B. nach Mode-/Datums-/Userwechsel) verzögert oder nie ein erstes Event (Firestore liefert für leere Collections zwar i.d.R. sofort einen leeren Snapshot, aber bei Latenz/Offline-Cache-Verzögerung nicht garantiert), bleibt der alte Stream aktiv und schreibt weiter veraltete Daten in _shifts/_absenceRequests. Zwei parallele Listener können sich gegenseitig überschreiben (Race) und kurzzeitig falsche/alte Schichten anzeigen.

**Beleg.** listen((items) { oldShiftsSub?.cancel(); ... }) — cancel im Daten-Callback statt deterministisch nach dem Setup.

**Empfehlung.** Muster von WorkProvider übernehmen: neue Subscriptions aufbauen, danach 'await oldXSub?.cancel()' EINMALIG aufrufen statt im wiederholt feuernden onData-Callback. So ist garantiert genau ein aktiver Listener.

### 22. Hybrid-LWW vergleicht client-lokales updatedAt (DateTime.now) mit serverTimestamp – Clock-Skew kann lokale Edits verlieren

- **Schweregrad:** Mittel  ·  **Kategorie:** data-integrity  ·  **Konfidenz:** medium  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/providers/work_provider.dart:1831`, `lib/providers/work_provider.dart:1907`, `lib/providers/work_provider.dart:1797`, `lib/models/work_entry.dart:184`, `lib/models/work_entry.dart:161`

**Problem.** _upsertLocalEntry stempelt lokale Schreibvorgänge mit 'DateTime.now()' (Client-Uhr). Der Cloud-Snapshot trägt dagegen den über FieldValue.serverTimestamp() gesetzten Wert (Server-Uhr), gelesen via _parseNullableFirestoreDate. In _mergeByKey entscheidet 'localTs.isAfter(remoteTs)' per Client- gegen Server-Zeit. Bei nachgehender Client-Uhr (Skew, falsche Zeitzone, Sommerzeit) ist localTs scheinbar älter als der gleichzeitig geschriebene Server-Snapshot.

**Auswirkung.** Eine gerade lokal vorgenommene, noch nicht synchronisierte Änderung kann durch einen älteren Cloud-Snapshot überschrieben werden (oder umgekehrt eine veraltete lokale Version gewinnt), weil zwei verschiedene Uhren verglichen werden. Im Warenwirtschafts-/Zeiterfassungskontext führt das zu still verlorenen Zeiteinträgen/Schichten beim Hybrid-Merge.

**Beleg.** _upsertLocalEntry: 'entry.copyWith(updatedAt: DateTime.now())' vs. toFirestoreMap: 'updatedAt: FieldValue.serverTimestamp()'; _mergeByKey: 'if (localTs.isAfter(remoteTs)) continue;'.

**Empfehlung.** Für LWW eine einheitliche Zeitquelle nutzen: entweder lokal beim Cachen denselben Server-updatedAt übernehmen, oder eine monotone client-seitige Versionsnummer/Sequenz statt Wall-Clock vergleichen. Alternativ den lokalen Stempel erst beim erfolgreichen Server-Write durch den serverTimestamp ersetzen.

### 74. setViewMode/setVisibleDate/setSelectedUserId starten async _restartSubscriptions fire-and-forget ohne Fehlerbehandlung

- **Schweregrad:** Niedrig  ·  **Kategorie:** error-handling  ·  **Konfidenz:** medium  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/providers/schedule_provider.dart:334`, `lib/providers/schedule_provider.dart:343`, `lib/providers/schedule_provider.dart:356`

**Problem.** Diese synchronen Setter rufen am Ende '_restartSubscriptions()' ohne await und ohne unawaited/catchError auf. _restartSubscriptions ist async und kann werfen (z.B. wenn _firestoreService.watchShifts beim Aufbau wirft) bevor der onError-Handler greift. Ein solcher Fehler wird zu einem unbehandelten Future-Error.

**Auswirkung.** Bei einem synchronen Fehler im Subscription-Aufbau (z.B. fehlender Index, Plugin-Exception) entsteht ein unhandled async error, der nur global geloggt wird; die UI bleibt im _loading=true-Zustand hängen (loading wurde gesetzt, aber der Erfolgs-/Fehlerpfad nie erreicht). Nutzer sehen einen Dauer-Spinner statt einer Fehlermeldung.

**Beleg.** setViewMode: '_restartSubscriptions();' am Methodenende, Rückgabewert verworfen, kein catch.

**Empfehlung.** Rückgabe als unawaited markieren und Fehler über surfaceSessionError/_setStreamError-Äquivalent sichtbar machen, z.B. 'unawaited(_restartSubscriptions().catchError((e){ _errorMessage = ...; _loading=false; _safeNotify(); }))'.

### 75. _notifyShiftWorked: Fehler beim Schicht-Abschluss überschreibt errorMessage ohne _errorArea, _markStreamHealthy kann ihn nicht mehr löschen

- **Schweregrad:** Niedrig  ·  **Kategorie:** ux  ·  **Konfidenz:** low  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/providers/work_provider.dart:1815`, `lib/providers/work_provider.dart:188`

**Problem.** _notifyShiftWorked setzt bei einem Fehler von completeShiftForEntry '_errorMessage = ...' direkt, ohne _errorArea zu setzen. Die Fehlerverwaltung des WorkProviders erwartet aber, dass persistente Fehler über _errorArea einem Bereich zugeordnet sind, damit _markStreamHealthy(bereich) sie wieder löschen kann.

**Auswirkung.** Eine fehlgeschlagene Schicht-Completion (Folgeaktion nach erfolgreichem Eintrag-Speichern) hinterlässt eine Dauer-Fehlermeldung, die durch keinen sich erholenden Stream gelöscht wird (da _errorArea==null nicht zu einem Bereich passt). Der Eintrag wurde gespeichert, aber die UI zeigt fälschlich einen anhaltenden Fehler.

**Beleg.** _notifyShiftWorked catch: '_errorMessage = 'Fehler beim Abschluss der Schicht: $e'; _safeNotify();' — kein _errorArea.

**Empfehlung.** _errorArea entsprechend setzen (z.B. 'Schichtabschluss') oder den Fehler nur transient/als Snackbar behandeln statt als persistente errorMessage; alternativ _errorArea=null konsistent in _markStreamHealthy berücksichtigen.

### 76. WorkProvider.updateSession Hybrid-Dedup-Pfad spiegelt geänderte UserSettings nicht in lokalen Cache

- **Schweregrad:** Niedrig  ·  **Kategorie:** data-integrity  ·  **Konfidenz:** low  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/providers/work_provider.dart:305`, `lib/providers/work_provider.dart:382`

**Problem.** Wenn sessionKey == _lastSessionKey (gleicher User/Org/Modus), wird nur _currentUser aktualisiert und früh zurückgekehrt (Zeile 305-314). Die Settings des neuen Profils werden im Hybrid-Modus nicht via saveLocalUserSettings gespiegelt (das passiert nur im vollständigen Hybrid-Zweig, Zeile 383). Beim nächsten _loadLocalState (overrideUserSettings=false wird im Hybrid genutzt) bleibt der lokale Settings-Cache potentiell veraltet.

**Auswirkung.** Ändern sich Profil-Settings serverseitig ohne Modus-/User-Wechsel, kann der lokale Settings-Snapshot im Hybrid-Modus driften; nach Offline-Neustart werden alte hourlyRate/dailyHours verwendet -> falsche Lohn-/Überstundenberechnung (totalWageThisMonth basiert auf settings.hourlyRate).

**Beleg.** Dedup-Branch aktualisiert nur _currentUser/_reportUser und ruft _ensureClockAvailabilityWatcher(); kein saveLocalUserSettings.

**Empfehlung.** Im Dedup-Pfad bei aktualisiertem Profil auch DatabaseService.saveLocalUserSettings(user.settings) im Hybrid-Modus aufrufen, oder Settings konsequent aus dem Profil statt aus lokalem Cache lesen.

## Team- / Personal- / Auth-Provider

### 18. PersonalProvider abonniert Admin-only Lohndaten-Streams für ALLE Nutzer → garantierte permission-denied-Fehler bei jedem Nicht-Admin-Login

- **Schweregrad:** Mittel  ·  **Kategorie:** error-handling  ·  **Konfidenz:** high  ·  **Status:** selbst verifiziert
- **Fundstellen:** `lib/providers/personal_provider.dart`, `firestore.rules`

**Problem.** In `PersonalProvider.updateSession` (lib/providers/personal_provider.dart:289-294) wird für jeden angemeldeten Nutzer mit orgId bedingungslos `_startFirestoreSubscriptions(user.orgId)` aufgerufen — ohne Admin-Prüfung. Das startet u. a. `watchPayrollRecords` und `watchPayrollProfiles` (Zeilen 307-318). Die firestore.rules (firestore.rules:697-712) erlauben das Lesen von `payrollRecords` und `payrollProfiles` aber ausdrücklich nur `isAdmin()` ('Lohndaten ... Lesen Admin-only'). Für jeden Nicht-Admin-Mitarbeiter liefern diese Streams daher zuverlässig `permission-denied`, das über `onError: _setError` (Zeile 311/316) verarbeitet wird. Da Hybrid der Default-Speichermodus ist (`_usesFirestore` = true für hybrid und cloud), tritt das bei praktisch jedem regulären Mitarbeiter bei jeder Sitzung auf. Die Mutator-Methoden sind korrekt per `_assertAdmin()` geschützt, aber die READ-Subscriptions nicht.

**Auswirkung.** Bei jedem Nicht-Admin-Login werden zwei permission-denied-Fehler erzeugt. Diese landen über `_setError` im `_errorMessage` und werden zudem nicht zentral gedrosselt — bei Verwendung eines Crash-/Fehler-Reporters entsteht dauerhaftes Fehler-Rauschen, das echte Probleme verdeckt. Außerdem unnötige Firestore-Listener-Aufbauten. Kein Datenleck (Rules blockieren korrekt), aber schlechte Graceful-Degradation und irreführende interne Fehlerzustände.

**Beleg.** personal_provider.dart:289 `if (_usesFirestore) { _startFirestoreSubscriptions(user.orgId); }` ohne `isAdmin`-Gate; _startFirestoreSubscriptions Zeilen 307-318 abonnieren watchPayrollRecords/watchPayrollProfiles; firestore.rules:698 `allow read: if isAdmin() && sameOrg(orgId);` (payrollRecords), :707 dito (payrollProfiles).

**Empfehlung.** In `updateSession`/`_startFirestoreSubscriptions` die Lohndaten-Streams (payrollRecords, payrollProfiles) nur für `user.isAdmin` starten — analog zur Admin-only-Regel in firestore.rules. workTasks/Abwesenheiten dürfen org-weit gelesen werden und können bleiben. Alternativ alle Personal-Streams nur für Admins aufbauen, da der Personal-Screen ohnehin admin-only ist (home_screen.dart / app_nav_menu.dart gaten 'Personal' mit `if (isAdmin)`).

### 63. TeamProvider: loading bleibt für Nicht-Manager im Cloud-Only-Modus dauerhaft true

- **Schweregrad:** Niedrig  ·  **Kategorie:** bug  ·  **Konfidenz:** high  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/providers/team_provider.dart`

**Problem.** In `TeamProvider.updateSession` wird beim Sitzungsaufbau `_loading = true` gesetzt (team_provider.dart:270). Im reinen Cloud-Modus (nicht hybrid) wird `_loading = false` ausschließlich im Mitglieder-Stream-Listener zurückgesetzt (Zeile 303). Dieser Listener wird aber nur aufgebaut, wenn `user.canManageShifts` true ist (Zeile 289). Für einen normalen Mitarbeiter ohne Schicht-Verwaltungsrecht läuft stattdessen der else-Zweig (Zeilen 337-341), der `_members`/`_invites`/`_teams` synchron setzt, aber `_loading` nie zurücksetzt. Die übrigen Cloud-Stream-Listener (Standorte, Qualifikationen, Verträge usw.) rufen nur `_safeNotify()`, aber kein `_loading = false`. Im Hybrid-Modus (Default) tritt das Problem nicht auf, weil `_storeHybridCollection` → `_applyLocalState()` `_loading = false` setzt (Zeile 1229).

**Auswirkung.** Für Nicht-Manager im Cloud-Only-Modus meldet `TeamProvider.loading` dauerhaft true. UI-Auswirkung begrenzt, da die Hauptkonsumenten (z. B. team_management_screen) admin-gegated sind und Cloud-Only kein Default ist; potenziell hängender Lade-Indikator/inkonsistenter Zustand, falls künftig ein für Mitarbeiter sichtbares Widget `team.loading` liest.

**Beleg.** team_provider.dart:270 `_loading = true;`; nur Zeile 303 (`_loading = false;`) im members-Listener setzt es im Cloud-Pfad zurück; dieser Listener nur unter `if (user.canManageShifts)` (Zeile 289); else-Zweig 337-341 setzt _loading nicht; Sites/Quals/Contracts-Listener (343-426) setzen _loading nicht.

**Empfehlung.** Im else-Zweig (Nicht-Manager) `_loading = false` setzen bzw. `_loading` generell nach Abschluss des Stream-Aufbaus oder beim ersten Eintreffen eines beliebigen Snapshots zurücksetzen (z. B. in einem gemeinsamen Helfer), statt es nur an den Mitglieder-Stream zu koppeln.

### 64. TeamProvider: Profil-/Rollen-/Rechte-Änderung mit gleicher uid wird im Local-Modus durch Session-Dedup verworfen

- **Schweregrad:** Niedrig  ·  **Kategorie:** data-integrity  ·  **Konfidenz:** medium  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/providers/team_provider.dart`

**Problem.** In `updateSession` greift die Dedup-Logik, wenn `sessionKey == _lastSessionKey` (team_provider.dart:155). Der sessionKey besteht nur aus `uid:orgId:storageModeKey` (Zeile 154) und enthält weder Rolle noch Permissions noch isActive. Im Dedup-Zweig wird `_currentUser` nur aktualisiert, wenn `!usesLocalStorage || _currentUser?.uid != user.uid` (Zeile 156). Im Local-Modus (usesLocalStorage true) und gleicher uid ist diese Bedingung false, sodass ein geändertes Profil (z. B. Rolle employee→admin, geänderte Permissions oder isActive) für denselben Nutzer NICHT in `_currentUser` übernommen wird, obwohl der Proxy mit dem neuen Profil aufruft.

**Auswirkung.** Im Offline/Local-Modus (APP_DISABLE_AUTH oder gewählter local-Storage) spiegelt der TeamProvider eine geänderte Rolle/Berechtigung des aktuellen Nutzers nicht wider, solange uid/orgId/Modus gleich bleiben — Provider-Mutatoren prüfen `_currentUser.isAdmin` und könnten so auf veraltetem Recht operieren. In der Praxis selten, da Selbständerungen meist über `updateMember` laufen (das `_currentUser` direkt setzt); dennoch eine echte Inkonsistenz der Annahme 'updateSession übernimmt das neueste Profil'.

**Beleg.** team_provider.dart:154 `final sessionKey = ... '${user.uid}:${user.orgId}:$_storageModeKey';` (keine Rolle/Permissions); :156 `if (!usesLocalStorage || _currentUser?.uid != user.uid) { _currentUser = user; }` — im Local-Modus mit gleicher uid bleibt _currentUser unverändert.

**Empfehlung.** Im Local-Dedup-Zweig `_currentUser = user` immer setzen (das ist eine billige reine Referenz-Zuweisung und löst keinen Stream-Neuaufbau aus), oder den sessionKey/Dedup so anpassen, dass Profiländerungen desselben Nutzers nicht stillschweigend ignoriert werden.

### 65. TeamProvider.setMemberActive prüft beim Cloud-Pfad nicht die Org-Zugehörigkeit des Ziel-Nutzers (Defense-in-Depth-Lücke)

- **Schweregrad:** Niedrig  ·  **Kategorie:** security  ·  **Konfidenz:** medium  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/providers/team_provider.dart`, `lib/services/firestore_service.dart`

**Problem.** `TeamProvider.setMemberActive` (team_provider.dart:953-981) ruft im Cloud-Pfad `_firestoreService.setUserActive(uid: uid, isActive: ...)` auf. `setUserActive` schreibt auf das Top-Level-Dokument `_users.doc(uid)` (firestore_service.dart:737-745) und scoped die uid in keiner Weise auf die Org des aufrufenden Admins — anders als z. B. `deleteSite`/`deleteTeam`, die `orgId` mitgeben. Die Org-Isolation wird ausschließlich durch firestore.rules erzwungen (Admin-Update verlangt `dataOrgId(resource.data) == currentOrgId()`, firestore.rules:424-428).

**Auswirkung.** Kein ausnutzbares Loch, solange die Rules deployt und korrekt sind (sie blockieren Cross-Org-Updates). Es fehlt jedoch die clientseitige Verteidigungsschicht: ein Bug/Tippfehler bei der uid (anderer Org) führt zu einem stillen permission-denied statt zu einer frühen, klaren Ablehnung, und der Client verlässt sich allein auf die Rules.

**Beleg.** team_provider.dart:980 `await _firestoreService.setUserActive(uid: uid, isActive: isActive);` (kein orgId); firestore_service.dart:741 `return _users.doc(uid).set({'isActive': ...}, merge);` (Top-Level, kein orgId-Filter); Schutz nur via firestore.rules:425-428.

**Empfehlung.** In `setMemberActive` prüfen, dass das Ziel `uid` zu `currentUser.orgId` gehört (z. B. via vorhandenem `members`-Cache), bevor `setUserActive` aufgerufen wird; optional `setUserActive` um einen orgId-Parameter erweitern, analog zu den übrigen org-skopierten Mutationen.

## Inventory- / Contact- / Audit-Provider

### 10. Ladespinner bleibt bei Firestore-Stream-Fehler dauerhaft aktiv (Inventory & Contacts)

- **Schweregrad:** Mittel  ·  **Kategorie:** error-handling  ·  **Konfidenz:** high  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/providers/inventory_provider.dart`, `lib/providers/contact_provider.dart`

**Problem.** In _startFirestoreSubscriptions wird _loading nur im *Daten*-Callback der Lieferanten-Subscription auf false gesetzt (inventory_provider.dart:561-565). Der gemeinsame onError-Handler _setError (Z. 401-404) setzt ausschliesslich _errorMessage und ruft _safeNotify, lässt _loading aber unangetastet. Emittiert der suppliers-Stream zuerst einen Fehler (fehlende Firestore-Berechtigung, fehlender Composite-Index, Netzwerkfehler) statt eines ersten Datensatzes, wird _loading nie auf false zurückgesetzt. Identisch im ContactProvider: _startFirestoreSubscriptions setzt loading nur im Daten-Callback (contact_provider.dart:236-240), das onError _setError (Z. 143-146) lässt _loading=true.

**Auswirkung.** Im cloud/hybrid-Modus zeigt der betroffene Bereich gleichzeitig eine Fehlermeldung UND einen dauerhaften Ladeindikator. Je nach Screen-Logik (loading-Flag vor errorMessage geprüft) kann die Fehlermeldung sogar unsichtbar bleiben und der Nutzer sieht nur einen endlosen Spinner – kein Recovery ohne App-Neustart.

**Beleg.** inventory_provider.dart:556-602 (_loading=false nur im suppliers-Daten-Callback Z.563); _setError Z.401-404 ohne _loading-Reset. contact_provider.dart:232-241 (loading=false nur im Daten-Callback) + _setError Z.143-146.

**Empfehlung.** Im onError-Pfad ebenfalls _loading = false setzen, z.B. einen dedizierten Stream-Error-Handler verwenden: onError: (e){ _loading = false; _setError(e); }. Alternativ _setError generell um _loading = false ergänzen.

### 41. Wiederkehrende Kundenbestellung verliert die Kontaktverknüpfung (contactId)

- **Schweregrad:** Niedrig  ·  **Kategorie:** data-integrity  ·  **Konfidenz:** high  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/providers/inventory_provider.dart`, `lib/models/customer_order.dart`

**Problem.** markCustomerOrderPickedUp legt bei wiederkehrenden Bestellungen (weekly/monthly) automatisch eine Folgebestellung an (inventory_provider.dart:1229-1246). Der dort konstruierte CustomerOrder übernimmt customerName, customerContact, siteName, items, notes etc., lässt das Feld contactId aber aus. CustomerOrder besitzt contactId als optionale Verknüpfung zur echten Kundenkartei (customer_order.dart:221/245-247). Die Folgebestellung startet damit ohne Kontakt-Link, obwohl die Ausgangsbestellung verknüpft war.

**Auswirkung.** Bei jeder automatischen Verlängerung einer wiederkehrenden Sonderbestellung geht die Zuordnung zum Kontakt (Stammkunde) verloren. Funktionen, die über contactId verknüpfen (z.B. Bestellhistorie am Kontakt), zeigen die Folgebestellungen nicht mehr beim Kunden an – schleichender Datenverlust über die Wochen/Monate.

**Beleg.** inventory_provider.dart:1231-1245 — CustomerOrder(...) ohne contactId; Feld vorhanden in customer_order.dart:221,247.

**Empfehlung.** Im Folgebestellungs-Konstruktor contactId: order.contactId ergänzen (analog zu customerContact).

### 42. AuditProvider mirrort lokal nur bei Admins (non-admin cloud-only erhält nie persistierten Audit-Mirror)

- **Schweregrad:** Niedrig  ·  **Kategorie:** data-integrity  ·  **Konfidenz:** medium  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/providers/audit_provider.dart`

**Problem.** In updateSession streamt nur ein Admin im _usesFirestore-Modus den Audit-Log (audit_provider.dart:83-89); jeder Nicht-Admin (auch im cloud-only-Modus) fällt in den else-Zweig und lädt _entries aus dem lokalen Spiegel via loadLocalAuditLog (Z.90-93). log() spiegelt jedoch nur lokal, wenn _mirrorsLocally true ist, also bei usesLocalStorage ODER usesHybridStorage (Z.45, Z.124). Ein Nicht-Admin im reinen cloud-only-Modus schreibt seine Audit-Einträge somit ausschliesslich nach Firestore, sieht beim nächsten Session-Aufbau aber den (in diesem Modus nie befüllten) lokalen Spiegel.

**Auswirkung.** Inkonsistenz ist weitgehend kosmetisch, da die Audit-Ansicht laut Rules ohnehin admin-only ist und Nicht-Admins die Liste nicht anzeigen. Tritt nur als verwaiste, nie aktualisierte _entries beim Nicht-Admin in cloud-only auf. Sollte ein künftiger Screen den Audit-Log auch Nicht-Admins zeigen, wäre die Liste irreführend (zeigt alte/leere lokale Daten statt der tatsächlich geschriebenen Einträge).

**Beleg.** audit_provider.dart:45 (_mirrorsLocally), 83-93 (Stream nur Admin; else lädt lokal), 115-138 (log spiegelt lokal nur bei _mirrorsLocally).

**Empfehlung.** Verhalten dokumentieren oder den else-Zweig auf _mirrorsLocally konditionieren (im reinen cloud-only-Modus _entries=[] statt loadLocalAuditLog), damit Lese- und Schreibpfad zum selben Storage zeigen.

### 43. Transienter Doppel-Eintrag im Audit-Log bei Admin im Hybrid-Modus

- **Schweregrad:** Niedrig  ·  **Kategorie:** ux  ·  **Konfidenz:** medium  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/providers/audit_provider.dart`

**Problem.** Ein Admin im Hybrid-Modus hat gleichzeitig den Firestore-Stream aktiv (_usesFirestore=true, audit_provider.dart:83-89) UND _mirrorsLocally=true (usesHybridStorage). In log() wird nach dem erfolgreichen Firestore-Append der Eintrag zusätzlich mit einer local-audit-… ID lokal vorne in _entries eingefügt und notifyListeners ausgelöst (Z.124-137). Der Firestore-Stream re-emittiert kurz darauf dieselbe Mutation mit der server-generierten Doc-ID und überschreibt _entries komplett. Bis zur Stream-Emission enthält _entries den Eintrag doppelt (einmal mit local-ID, einmal nach Stream-Refresh mit Server-ID).

**Auswirkung.** Kurzzeitig erscheint ein gerade protokollierter Audit-Eintrag doppelt in der Admin-Ansicht, bis der Stream den lokalen Spiegel verdrängt. Rein visueller Glitch, keine Datenkorruption (Firestore bleibt korrekt; lokaler Spiegel wird beim nächsten Session-Aufbau für Admins gar nicht gelesen).

**Beleg.** audit_provider.dart:83-89 (Admin streamt) + 115-137 (log mirrort lokal mit eigener local-ID trotz aktivem Stream).

**Empfehlung.** Bei Admin im Hybrid-Modus den lokalen Mirror-Prepend in log() überspringen, da der Stream ohnehin die Wahrheit liefert (z.B. lokal nur spiegeln, wenn der Firestore-Write fehlgeschlagen ist), oder beim Mirror-Insert nach productId/Server-ID deduplizieren.

### 44. FeatureFlagProvider behandelt Hybrid-Modus wie Cloud (kein Caching der Remote-Config offline)

- **Schweregrad:** Niedrig  ·  **Kategorie:** architecture  ·  **Konfidenz:** medium  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/providers/feature_flag_provider.dart`

**Problem.** updateSession ignoriert hybridStorageEnabled vollständig und liest die Remote-Config (Force-Update/Feature-Flags) immer per Einmal-fetchAppConfig, ausser bei localStorageOnly oder disableAuthentication (feature_flag_provider.dart:49-83). fetchAppConfig macht einen einzelnen Firestore-get (firestore_service.dart:86-91) ohne lokalen Spiegel. Anders als Inventory/Contact/Audit gibt es hier keinen Hybrid-Local-Cache. Bei Read-Fehlern wird fail-open zurückgesetzt (requiresUpdate=false).

**Auswirkung.** Gewollt fail-open (ein fehlgeschlagener Read sperrt niemanden aus). Folge: Das Force-Update-Gate (_AuthGate liest requiresUpdate, main.dart:655-656) greift offline/bei Read-Fehler nie, da minimumBuildNumber auf 0 fällt. Eine kritisch veraltete App-Version, die offline startet, wird nicht zum Update gezwungen. Das ist die dokumentierte Designentscheidung, aber die Hybrid-Caching-Asymmetrie zu den übrigen Providern ist erwähnenswert.

**Beleg.** feature_flag_provider.dart:49-83 (hybridStorageEnabled-Parameter ungenutzt, immer fetchAppConfig); firestore_service.dart:86-91 (einmaliger get ohne Mirror).

**Empfehlung.** Falls das Force-Update-Gate auch nach App-Neustarts ohne Netz greifen soll: die zuletzt erfolgreich gelesene minimumBuildNumber lokal cachen und beim Start als Ausgangswert nutzen. Sonst Verhalten bewusst belassen (fail-open ist hier korrekt) und als Designentscheidung dokumentieren.
