# FirestoreService / Callables · Repositories

> Teil des WorkTime-Code-Reviews. Zurück zur [Übersicht](README.md).

## FirestoreService / Callables

### 3. Hybrid-/Cloud-Fallback erzeugt Duplikat-Dokumente bei verlorenem Callable-Ack (deterministische Server-ID vs. zufällige Client-ID)

- **Schweregrad:** Hoch  ·  **Kategorie:** data-integrity  ·  **Konfidenz:** high  ·  **Status:** selbst verifiziert
- **Fundstellen:** `lib/services/firestore_service.dart`, `functions/index.js`

**Problem.** Der Server leitet für neue Zeiteinträge/Schichten ohne id eine DETERMINISTISCHE Doc-ID aus dem Inhalt ab (functions/index.js:143 `buildWorkEntryDocumentId`, :449 `buildShiftDocumentId`). Der direkte Fallback-Pfad im Client schreibt dagegen mit einer ZUFÄLLIGEN Auto-ID: `_saveWorkEntryDirect` (firestore_service.dart:657-658) und `_saveShiftBatchDirect` (:1347-1350) nutzen `entry.id == null ? collection.doc() : ...`. Szenario: Callable `upsertWorkEntry`/`upsertWorkEntryBatch`/`upsertShiftBatch` committet serverseitig erfolgreich, aber die Antwort geht als `unavailable` verloren (Netzabbruch nach Commit). `_callCloudFunctionIfAvailable` gibt bei `unavailable` `false` zurück (firestore_service.dart:1599-1601) → der direkte Fallback schreibt denselben Eintrag erneut, diesmal unter einer zufälligen ID. Ergebnis: zwei Dokumente desselben Eintrags. Ein späteres Edit (wieder über Callable) trifft nur die deterministische ID und lässt das zufällig-ID-Duplikat verwaist zurück.

**Auswirkung.** Doppelte Zeiteinträge/Schichten → falsche Arbeitszeit-/Lohn-/Compliance-Summen (z. B. doppelte Stunden in Personalkosten/Lohnabrechnung). Nutzer sieht dieselbe Schicht zweimal. Die im Kommentar (firestore_service.dart:1586-1588) behauptete Idempotenz greift NUR auf dem Callable-Retry-Pfad, nicht auf dem direkten Fallback-Pfad.

**Beleg.** Server: `const docId = entry.id ?? buildWorkEntryDocumentId(entry)` (index.js:143). Client-Fallback: `entry.id == null ? collection.doc() : collection.doc(entry.id)` (firestore_service.dart:657-658, gleiches Muster :1347-1350).

**Empfehlung.** Im direkten Fallback dieselbe deterministische Doc-ID verwenden wie der Server (gemeinsame Hash-Funktion in compliance_service-ähnlichem geteilten Code oder Dart-Portierung von buildWorkEntryDocumentId/buildShiftDocumentId), oder vor dem Fallback einen idempotenten Pre-Write (clientseitig erzeugte stabile id setzen, bevor der Callable aufgerufen wird) durchführen. Generell: client-generierte stabile IDs für Neuanlagen, damit Callable- und Direktpfad dieselbe Identität schreiben.

### 8. Behauptete Callable-Idempotenz ohne clientMutationId — Retry-Idempotenz hängt allein an inhaltsbasierter Server-ID, _request_id wird pro Versuch neu erzeugt

- **Schweregrad:** Mittel  ·  **Kategorie:** data-integrity  ·  **Konfidenz:** high  ·  **Status:** selbst verifiziert
- **Fundstellen:** `lib/services/firestore_service.dart`, `functions/index.js`

**Problem.** Der Kommentar bei `_callCloudFunctionIfAvailable` (firestore_service.dart:1586-1588) begründet das Retry mit "Callables sind durch stabile Client-IDs idempotent". Tatsächlich enthält der Payload KEINE clientMutationId/Idempotenzschlüssel — `entry.toMap()`/`shift.toMap()` liefern keinen solchen, und `functions/index.js` liest `_request_id` (Zeile 35-39) ausschließlich zum Logging, nicht zur Dedup. Die _request_id wird zudem in `_callCloudFunction` (firestore_service.dart:1565) bei JEDEM Retry-Versuch neu via `_uuid.v4()` erzeugt, ist also über Retries hinweg nicht stabil → taugt weder als Idempotenzschlüssel noch für eine durchgehende Trace-Korrelation über Retries. Die Idempotenz beruht real allein auf `buildWorkEntryDocumentId`/`buildShiftDocumentId`. Für Einträge, die ein Feld tragen, das NICHT in den Hash eingeht (z. B. note/category-Varianten), oder bei zwei legitim identischen Einträgen am selben Tag/Zeitfenster kollidieren zwei verschiedene fachliche Einträge auf DIESELBE Doc-ID und überschreiben sich.

**Auswirkung.** Zwei tatsächlich unterschiedliche, aber in allen Hash-Feldern (orgId,userId,date,start,end,break,siteId,category) identische Zeiteinträge desselben Mitarbeiters überschreiben sich gegenseitig (Datenverlust). Trace-Korrelation Client↔Server bricht bei Retries (Observability-Lücke).

**Beleg.** grep zeigt clientMutationId existiert nur im Inventar-Pfad, nicht für WorkEntry/Shift. functions/index.js:35-39 nutzt requestId nur für `console.log`. firestore_service.dart:1565 erzeugt `_request_id` innerhalb der pro-Versuch aufgerufenen `_callCloudFunction`.

**Empfehlung.** Echten, stabilen Idempotenzschlüssel (clientMutationId) einführen, der vor dem ersten Versuch erzeugt und über alle Retries konstant bleibt; serverseitig zur Dedup und als Doc-ID-Basis verwenden. Mindestens _request_id einmal pro logischer Operation (vor retryTransient) erzeugen statt in _callCloudFunction pro Versuch.

### 9. Persistente Callable-Timeouts (deadline-exceeded/internal) lösen KEINEN Hybrid-Fallback aus, sondern werfen StateError

- **Schweregrad:** Mittel  ·  **Kategorie:** error-handling  ·  **Konfidenz:** medium  ·  **Status:** selbst verifiziert
- **Fundstellen:** `lib/services/firestore_service.dart`

**Problem.** `_callCloudFunctionIfAvailable` gibt nur bei `not-found` und `unavailable` `false` zurück (Zeile 1599-1601), wodurch der direkte/Hybrid-Fallback greift. Ein `deadline-exceeded` (z. B. durch den 30s-HttpsCallableOptions-Timeout bei schlechter Verbindung, firestore_service.dart:1576) wird von `retryTransient` zwar 3× wiederholt, aber bei dauerhafter Überschreitung schließlich als `FirebaseFunctionsException(deadline-exceeded)` rethrown. Dieser Code ist nicht in `{not-found, unavailable}`, nicht `failed-precondition` → fällt in den Zweig `error.message?.trim().isNotEmpty == true` und wirft einen `StateError` (Zeile 1613-1614). Der im Code-Kommentar (Zeile 1571-1572) erwartete Hybrid-Fallback ("bei Überschreitung greift der Hybrid-Fallback") greift damit NICHT für deadline-exceeded — der Aufruf schlägt hart fehl statt lokal zu fallbacken.

**Auswirkung.** Bei langsamer/instabiler Verbindung sieht der Nutzer im Hybrid-Modus einen harten Fehler (StateError-Dialog) statt der dokumentierten lokalen Spiegelung; die Mutation geht clientseitig verloren statt offline gepuffert zu werden. Widerspricht der CLAUDE.md-Regel "im catch: bei hybrid lokal fallbacken".

**Beleg.** firestore_service.dart:1599 `if (error.code == 'not-found' || error.code == 'unavailable') return false;` deckt deadline-exceeded NICHT ab; Zeile 1576 setzt einen 30s-Timeout; Kommentar Zeile 1571-1572 verspricht Fallback.

**Empfehlung.** `deadline-exceeded` (und ggf. `internal`/`cancelled`) ebenfalls als fallback-fähig behandeln (return false), sodass der direkte/Hybrid-Pfad greift — oder den Kommentar Zeile 1571-1572 korrigieren. Da der direkte Pfad mit deterministischer ID idempotent gemacht werden sollte (siehe anderes Finding), ist der Fallback dann auch duplikatfrei.

### 39. watchAbsenceRequests/getApprovedVacationsForYear/findBlockingAbsences lesen ohne untere Datumsgrenze — unbeschränkt wachsende Reads

- **Schweregrad:** Niedrig  ·  **Kategorie:** performance  ·  **Konfidenz:** medium  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/services/firestore_service.dart`

**Problem.** Mehrere Abwesenheits-Queries setzen nur eine OBERE Grenze auf startDate und filtern den Rest clientseitig: `watchAbsenceRequests` (Zeile 536-547: `where('startDate', isLessThanOrEqualTo: end)` + clientseitiges `overlaps`), `getApprovedVacationsForYear` (Zeile 1532-1535: `where('startDate', isLessThan: yearEnd)`), `findBlockingAbsences` (Zeile 1474-1481: `where('startDate', isLessThanOrEqualTo: shift.endTime)`). Es gibt keine untere Grenze (z. B. `startDate >= start - maxDauer`), weil mehrjährige Anträge sonst verloren gingen. Dadurch werden mit zunehmendem Datenalter ALLE historischen Abwesenheitsanträge ab Org-Beginn geladen und der Stream behält das dauerhaft.

**Auswirkung.** Mit den Jahren wachsende Lese-/Speicherkosten und Stream-Payload; auf Spark-Free-Tier (laut CLAUDE.md ein Ziel) relevante Read-Kosten. Kein Korrektheitsbug, aber Skalierungs-/Performancefalle.

**Beleg.** firestore_service.dart:536-541 (nur isLessThanOrEqualTo), :1532-1535, :1474-1481 — jeweils nur obere Schranke + clientseitiges overlaps/Statusfilter.

**Empfehlung.** Untere Grenze einführen, die die maximal erlaubte Abwesenheitsdauer abdeckt (z. B. `startDate >= start.subtract(maxAbsenceDuration)`), oder beendete Anträge per Status/Jahr archivieren. Stream-Limit erwägen.

### 40. Batch-Direktschreiber gehen von einheitlicher orgId aus (entries.first/shifts.first) — gemischte orgIds würden in falsche Org geschrieben

- **Schweregrad:** Niedrig  ·  **Kategorie:** security  ·  **Konfidenz:** medium  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/services/firestore_service.dart`

**Problem.** `_saveWorkEntryBatchDirect` (Zeile 666), `_saveWorkEntryBatchChunk`-Callable-Payload (Zeile 643) und `_saveShiftBatchDirect` (Zeile 1343) wählen die Ziel-Collection bzw. den orgId-Payload anhand von `entries.first.orgId` / `shifts.first.orgId`, schreiben dann aber ALLE Elemente in diese eine Org-Collection, ohne zu prüfen, dass alle Elemente dieselbe orgId tragen. Bei einem aufrufenden Fehler mit gemischten orgIds würden fremd-org-Einträge in die Org des ersten Elements geschrieben. Die Provider verwenden zwar aktuell stets eine Org, aber die Methode hat keine defensive Zusicherung.

**Auswirkung.** Potenzielle Mandanten-Vermischung bei künftigem Fehlgebrauch; firestore.rules würde fremd-org-Writes zwar serverseitig ablehnen (sameOrg), aber der gesamte Batch schlägt dann atomar fehl bzw. im disableAuth/lokalen Modus greift keine Regel. Reines Robustheits-/Defense-in-Depth-Risiko.

**Beleg.** firestore_service.dart:666 `_entryCollection(entries.first.orgId)`, :643 `'orgId': entries.first.orgId`, :1343 `_shiftCollection(shifts.first.orgId)` — keine Konsistenzprüfung der übrigen Elemente.

**Empfehlung.** Am Methodenanfang per assert/Exception sicherstellen, dass alle Elemente dieselbe orgId besitzen (`entries.every((e) => e.orgId == entries.first.orgId)`), sonst frühzeitig werfen.

## Repositories

### 11. orderCarts-Schreibpfad ohne Feld-Allowlist/BOPLA: jeder Mitarbeiter kann updatedByUid/addedByUid faelschen und beliebige Daten injizieren

- **Schweregrad:** Mittel  ·  **Kategorie:** security  ·  **Konfidenz:** high  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `firestore.rules`, `lib/models/order_cart.dart`, `lib/repositories/firestore_inventory_repository.dart`

**Problem.** Die neue Collection `orderCarts` ist bewusst fuer JEDES aktive Org-Mitglied beschreibbar (`allow create, update: if sameOrg(orgId) && request.resource.data.orgId == orgId && request.resource.data.siteId == siteId`). Anders als die uebrigen breit beschreibbaren bzw. append-only Pfade (`stockMovements`, `priceHistory`, `customerWishes`) gibt es hier KEINE `keys().hasOnly([...])`-Allowlist und keine Bindung von `updatedByUid`/`items[].addedByUid` an `request.auth.uid`. Das Modell `SiteOrderList.toFirestoreMap()` schreibt `updatedByUid` und je Position `addedByUid` frei aus dem Client (`order_cart.dart:101`, `order_cart.dart:240`). Ein beliebiger aktiver Mitarbeiter kann daher (a) `updatedByUid`/`addedByUid` auf eine fremde UID setzen (Zuschreibung faelschen), und (b) unbegrenzt grosse `items`-Arrays / fremde Felder in das Korb-Dokument schreiben (Mass Assignment / Storage-Abuse). Da der gesamte gestreamte Korb beim naechsten `addToCart` ueberschrieben wird ('last writer wins'), kann ein Mitarbeiter zudem den Korb-Inhalt anderer Laeden bzw. die Mengen kollektiv manipulieren, solange siteId/orgId passen.

**Auswirkung.** Innerhalb einer Org koennen normale Mitarbeiter Bestell-Zuschreibungen faelschen (wer hat was bestellt) und das Korb-Dokument als unkontrollierten Schreib-/Speicherkanal missbrauchen. Mandanten-Isolation (sameOrg) bleibt gewahrt, aber das dokumentierte BOPLA-Haertungsmuster der Warenwirtschaft wird hier nicht eingehalten.

**Beleg.** firestore.rules orderCarts-Block: `allow create, update: if sameOrg(orgId) && request.resource.data.orgId == orgId && request.resource.data.siteId == siteId;` — keine hasOnly/Pin von updatedByUid; SiteOrderList.toFirestoreMap schreibt updatedByUid + items[].addedByUid frei.

**Empfehlung.** Analog zu stockMovements/priceHistory eine `keys().hasOnly([...])`-Allowlist fuer orderCarts ergaenzen, `items` auf eine sinnvolle Maximalanzahl begrenzen (z.B. size() <= N) und `request.resource.data.updatedByUid == request.auth.uid` erzwingen. Falls addedByUid je Position nicht serverseitig pruefbar ist, zumindest updatedByUid pinnen und items-Groesse deckeln.

### 47. Leerer siteId fuehrt zu .doc('')-Absturz beim Speichern/Loeschen von Bestelllisten

- **Schweregrad:** Niedrig  ·  **Kategorie:** error-handling  ·  **Konfidenz:** medium  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/repositories/firestore_inventory_repository.dart`, `lib/providers/inventory_provider.dart`, `lib/models/product.dart`

**Problem.** `saveOrderList` adressiert das Dokument hart ueber `_orderListCollection(list.orgId, list.kind).doc(list.siteId)` und `deleteOrderList` ueber `.doc(siteId)`. `siteId` stammt letztlich aus `Product.siteId`, das zwar als `required String` deklariert, aus Firestore aber tolerant als `(map['siteId'] ?? '').toString()` geparst wird (product.dart:131) und damit Leerstring sein kann. `addToCart` erzeugt dann eine `SiteOrderList(siteId: product.siteId)` mit `siteId == ''`, und der nachfolgende Repository-Write ruft `.doc('')` auf — Firestore wirft dafuer einen `AssertionError`/`ArgumentError` (Doc-ID darf nicht leer sein). Im cloud-only-Modus wird der Fehler durchgereicht (kein Hybrid-Fallback), im hybrid-Modus faellt es zwar lokal zurueck, schreibt dort aber unter Doc-ID '' eine sammelnde Korb-Liste, die spaeter mit anderen leeren-siteId-Listen kollidieren kann.

**Auswirkung.** Ein Artikel mit (kaputt/leer importiertem) siteId fuehrt beim 'In den Korb legen' zu einem harten Fehler bzw. zu einer kollidierenden Korb-Liste. Edge-Case, aber unbehandelt im Repository.

**Beleg.** firestore_inventory_repository.dart:354-359 `return _orderListCollection(list.orgId, list.kind).doc(list.siteId).set(...)`; product.dart:131 `siteId: (map['siteId'] ?? '').toString()`.

**Empfehlung.** Im Repository (saveOrderList/deleteOrderList) bzw. im Provider (_persistOrderList) frueh pruefen, ob siteId nicht leer ist, und sonst mit klarer deutscher Fehlermeldung abbrechen, statt Firestore mit leerer Doc-ID aufzurufen.

### 48. Bestelllisten-Streams werden nie auf Repository-Fehler defensiv behandelt; onError ueberschreibt globale Fehleranzeige fuer alle Inventory-Streams

- **Schweregrad:** Niedrig  ·  **Kategorie:** error-handling  ·  **Konfidenz:** medium  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/providers/inventory_provider.dart`, `lib/repositories/firestore_inventory_repository.dart`, `lib/screens/order_cart_screen.dart`

**Problem.** Die neuen Streams `watchOrderCarts`/`watchWeeklyOrderLists` werden mit `onError: _setError` verdrahtet (inventory_provider.dart:591-601), genau wie alle anderen Inventory-Streams. `_setError` setzt eine einzelne `_errorMessage`. Schlaegt z.B. der orderCarts-Stream wegen fehlender Leserechte/Regeln dauerhaft fehl, wird die globale Inventory-Fehlermeldung gesetzt und bleibt stehen, obwohl Lieferanten/Artikel/Bestellungen problemlos laden — und umgekehrt ueberschreibt ein spaeterer erfolgreicher anderer Stream die Sichtbarkeit nicht (Fehler bleibt). Es gibt zudem keinen Stream-spezifischen Leerzustand: bei Stream-Fehler bleibt `_orderCarts` einfach leer, sodass die UI 'Korb leer' statt 'Korb konnte nicht geladen werden' zeigt. Im Repository selbst gibt es keine Fehler-Kapselung (reines `.snapshots().map`).

**Auswirkung.** Teil-Ausfaelle eines einzelnen Streams (z.B. Bestelllisten) faerben die gesamte Inventory-Fehleranzeige ein bzw. werden als 'leer' fehlinterpretiert. Resilienz-/UX-Schwaeche, kein Datenverlust.

**Beleg.** inventory_provider.dart:591-601 beide neuen Streams nutzen `onError: _setError`, das eine einzige globale `_errorMessage` setzt; Repository watchOrderCarts/watchWeeklyOrderLists kapseln keine Mapping-Fehler ab.

**Empfehlung.** Pro Stream ein eigenes Fehler-/Ladeflag fuehren oder zumindest die Bestelllisten-Streams tolerant behandeln (Fehler loggen, vorhandene Liste behalten), damit ein Korb-Stream-Fehler nicht die gesamte Warenwirtschaft als fehlerhaft markiert.
