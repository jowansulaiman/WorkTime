# Test-Qualität & Lücken

> Teil des WorkTime-Code-Reviews. Zurück zur [Übersicht](README.md).

### 19. Hybrid-Offline-Fallback der Bestellkorb-Mutationen ist ungetestet (darf nicht rethrowen)

- **Schweregrad:** Mittel  ·  **Kategorie:** test-gap  ·  **Konfidenz:** high  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/providers/inventory_provider.dart:1546`, `lib/providers/inventory_provider.dart:1552`, `test/order_cart_provider_test.dart:248`, `test/inventory_provider_test.dart:536`

**Problem.** _persistOrderList nutzt _tryFirestore: bei Cloud-Fehler im Hybrid-Modus muss lokal zurückgefallen werden (kein rethrow), nur cloud-only rethrowt – ein dokumentierter Kern-Invariant (CLAUDE.md Mutator-Muster). Für saveProduct existiert genau dieser Hybrid-Fallback-Test (inventory_provider_test.dart:536). Für die neuen Bestelllisten-Mutationen (addToCart/setCartItemQuantity/clearCart/checkoutCart/saveWeeklyList/prefillCartFromWeeklyList) gibt es ihn NICHT: order_cart_provider_test.dart testet nur reinen local-Modus (disableAuthentication:true) und einen einzigen Cloud-Happy-Path (addToCart, Zeile 248). Der Hybrid-Catch-Pfad (Firestore wirft -> lokal speichern + _safeNotify, Zeile 1567-1578) wird nie ausgeführt.

**Auswirkung.** Regression im Fallback (z.B. versehentliches rethrow oder fehlendes lokales Persistieren) würde dazu führen, dass ein offline in den Korb gelegter Artikel still verloren geht oder die UI mit einer Exception abstürzt – genau das Szenario, gegen das das Hybrid-Muster schützen soll. Der Korb ist ein kollaboratives Mehrnutzer-Feature; Datenverlust hier ist schmerzhaft.

**Beleg.** order_cart_provider_test.dart Zeile 252: 'await provider.updateSession(user, localStorageOnly: false)' – aber kein Fehler-Repo; alle anderen Cart-Tests setzen disableAuthentication:true (reiner local-Modus).

**Empfehlung.** Analog zum saveProduct-Test einen _OfflineInventoryRepository (saveOrderList wirft FirebaseException) im Hybrid-Modus verwenden und prüfen, dass addToCart NICHT wirft und der Korb über DatabaseService.loadLocalOrderCarts lokal persistiert ist. Zusätzlich cloud-only: saveOrderList-Fehler MUSS rethrowen.

### 66. Öffentlicher Kundenwunsch-Submit-Pfad (einziger anonymer Schreibpfad) hat keinen Widget-Test

- **Schweregrad:** Niedrig  ·  **Kategorie:** test-gap  ·  **Konfidenz:** high  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/screens/public/public_wish_screen.dart:50`, `lib/screens/public/public_wish_screen.dart:91`, `lib/screens/public/public_wish_screen.dart:223`, `lib/screens/public/public_wish_screen.dart:279`, `lib/screens/public/public_wish_screen.dart:65`

**Problem.** Der gesamte öffentliche Wunsch-Abgabe-Flow in PublicWishScreen ist ungetestet (keine Datei public_wish_screen_test.dart). Getestet sind nur Model-Serialisierung (customer_wish_model_test.dart) und der Service mit FakeFirestore (customer_wish_service_test.dart). Der Bildschirm enthält aber kritische, ungeprüfte Logik: anonymes Sign-in via FirebaseAuth.signInAnonymously (mit Sonderbehandlung von 'operation-not-allowed' vs. generischem Fehler in _submit/_handleError), Formularvalidierung (wishText Pflicht, Zeile 223), die Mengen-Clamp 1..999 (Zeile 279/289) sowie die _reset-Logik nach Erfolg. Keiner dieser Pfade wird ausgeführt.

**Auswirkung.** Dies ist der einzige öffentliche (anonyme) Schreibpfad der App und damit die größte Angriffs-/Fehlerfläche. Ein Regress in der Fehlerbehandlung (z.B. falscher Fehlertext bei deaktiviertem Anonymous-Provider, Crash bei nicht gemountetem State, Mehrfach-Submit ohne Sperre) bliebe unbemerkt und träfe echte Endkunden ohne Login.

**Beleg.** Keine Datei test/public_wish_screen_test.dart vorhanden; ls bestätigte das Fehlen. _submit fängt FirebaseAuthException getrennt (Zeile 91) – dieser Zweig ist nirgends ausgeführt.

**Empfehlung.** Widget-Test für PublicWishScreen ergänzen: injizierten FirestoreService(FakeFirebaseFirestore) verwenden, leere wishText -> Validierungsfehler, erfolgreicher Submit zeigt Referenzcode (_buildSuccess) und schreibt genau einen customerWishes-Doc, sowie der Fehlerpfad (FirestoreService, der wirft) zeigt _ErrorBanner statt zu crashen. Anonymous-Sign-in über einen injizierbaren Seam testbar machen oder via Auth-Mock abdecken.

### 67. checkoutCart/saveWeeklyList/clearCart im Cloud-Modus ungetestet – Stream-basierte Lese-Mutations-Schleife nicht abgesichert

- **Schweregrad:** Niedrig  ·  **Kategorie:** test-gap  ·  **Konfidenz:** high  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/providers/inventory_provider.dart:1437 (checkoutCart)`, `lib/providers/inventory_provider.dart:1481 (Teilfehler-Kompensation/deletePurchaseOrder-Rollback)`, `lib/providers/inventory_provider.dart:1511 (_removeCartItems Cloud-Lesepfad)`, `lib/providers/inventory_provider.dart:1546 (_persistOrderList Cloud-Schreibpfad)`, `test/order_cart_provider_test.dart:248 (einzige Cloud-Modus-Gruppe, nur addToCart)`, `test/order_cart_provider_test.dart:205 (Kompensationstest nur local via disableAuthentication: true)`

**Problem.** Alle anspruchsvollen Korb-Operationen (checkoutCart mit Lieferanten-Gruppierung + Kompensation, _removeCartItems, saveWeeklyList, prefillCartFromWeeklyList, clearCart, setCartItemQuantity, removeCartItem) werden ausschließlich im local-Modus getestet. Im Cloud-/Hybrid-Modus lesen diese Mutatoren den Stand aus dem gestreamten _orderCarts, mutieren und schreiben die ganze Liste zurück (last-writer-wins, dokumentiert). Genau diese Read-from-stream-then-write-Logik (inkl. der Notwendigkeit, nach saveOrderList auf die Stream-Emission zu warten, vgl. Zeile 261-262) ist im Cloud-Modus nirgends geprüft. Auch der Teilfehler-Kompensationspfad in checkoutCart (Zeile ~1400, deletePurchaseOrder-Rollback) läuft nur local (_FailSecondOrderProvider mit disableAuthentication:true).

**Auswirkung.** Im local-Modus mutiert der Mutator dieselbe synchrone In-Memory-Liste; im Cloud-Modus hängt die Korrektheit am asynchronen Stream-Roundtrip. Bugs, die nur im Cloud-Pfad auftreten (z.B. Mutation auf veraltetem Stream-Stand, _removeCartItems entfernt nichts weil Stream noch nicht aktualisiert), bleiben unentdeckt, obwohl Produktion fast immer Cloud/Hybrid ist.

**Beleg.** order_cart_provider_test.dart: einzige Cloud-Gruppe (Zeile 248) testet nur addToCart; checkoutCart-Tests (Zeile 148, 203) und prefill (Zeile 114) laufen über newLocalProvider() = disableAuthentication:true.

**Empfehlung.** Mindestens checkoutCart und prefillCartFromWeeklyList im Cloud-Modus (localStorageOnly:false, FakeFirebaseFirestore) testen, jeweils mit den nötigen Future.delayed(Duration.zero)-Pumps, und assertieren, dass PurchaseOrders in Firestore landen und der Korb-Doc danach leer/reduziert ist. Den Teilfehler-Rollback auch im Cloud-Modus prüfen.

### 68. Interner Kundenwunsch-Eingang (CustomerWishesScreen) und Bestellkorb-Screen ohne Widget-Tests

- **Schweregrad:** Niedrig  ·  **Kategorie:** test-gap  ·  **Konfidenz:** high  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/screens/customer_wishes_screen.dart:164`, `lib/screens/customer_wishes_screen.dart:66`, `lib/screens/order_cart_screen.dart:760`, `lib/screens/order_cart_screen.dart:785`, `lib/screens/order_cart_screen.dart:1157`

**Problem.** Zwei umfangreiche, mutationslastige Screens haben null Testabdeckung: customer_wishes_screen.dart (421 Zeilen, Status-Änderung/Löschen, Berechtigungs-Gate canManageInventory, Open/Closed-Filter _showClosed) und order_cart_screen.dart (1169 Zeilen!) mit showQuickAddCartSheet, _ProductPickerSheet, dem WeeklyOrderListEditorScreen (_save -> saveWeeklyList) und dem Checkout-Flow inkl. _CheckoutButton-Doppeltap-Sperre (Zeile 785). Die Doppeltap-Sperre existiert genau, weil checkoutCart nicht idempotent ist – sie ist aber nicht getestet.

**Auswirkung.** Diese Screens steuern die Geld-/Bestell-relevanten Aktionen (echte PurchaseOrders auslösen, Standard-Wochenliste kuratieren, Kundenwünsche bearbeiten). Ohne Widget-Tests bleiben Berechtigungs-Gates, der in-flight-Schutz gegen doppelte Bestellungen und die Status-Übergänge ungeprüft; ein Regress könnte doppelte Bestellungen oder unautorisierte Aktionen ermöglichen.

**Beleg.** ls bestätigte: keine customer_wishes_screen_test.dart und keine order_cart_screen_test.dart. _CheckoutButton-Kommentar Zeile 785: 'in-flight-Sperre gegen Doppel-Tap (Checkout ist nicht idempotent)' – ungetestet.

**Empfehlung.** Widget-Tests ergänzen: (1) CustomerWishesScreen mit FirestoreService(Fake) – Mitarbeiter ohne canManageInventory sieht keine Bearbeiten-Buttons, Manager kann Status setzen/löschen. (2) WeeklyOrderListEditorScreen: Artikel hinzufügen -> Speichern ruft saveWeeklyList. (3) _CheckoutButton: zweiter Tap während laufendem Checkout löst checkoutCart nur einmal aus.

### 69. CustomerWish: toFirestoreMap/fromFirestore-Round-Trip und updateCustomerWishStatus-Felder unzureichend geprüft

- **Schweregrad:** Niedrig  ·  **Kategorie:** test-gap  ·  **Konfidenz:** high  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/models/customer_wish.dart:226`, `lib/models/customer_wish.dart:161`, `lib/services/firestore_service.dart:1088`, `test/customer_wish_model_test.dart:79`, `test/customer_wish_service_test.dart:69`

**Problem.** Das Model hat drei Serialisierungsformen, aber der camelCase-Voll-Round-Trip (toFirestoreMap -> fromFirestore) ist NICHT getestet. customer_wish_model_test.dart prüft nur toMap/fromMap (snake_case, Zeile 78) und toPublicSubmissionMap-Keys (Zeile 39). Felder, die nur in toFirestoreMap/fromFirestore relevant sind (notes, handledByUid, handledAt, voller status/source), werden im camelCase-Format nie hin- und zurückgeführt. updateCustomerWishStatus (Service) schreibt status/notes/handledByUid/handledAt – der Service-Test (Zeile 69) prüft nur status + handledByUid, nicht den notes-Parameter und nicht, dass handledAt gesetzt wurde.

**Auswirkung.** Ein camelCase-Parser-Fehler (z.B. falscher Key, fehlender Parser für handledAt) bei intern bearbeiteten Wünschen bliebe unbemerkt, weil watchCustomerWishes über fromFirestore liest, aber kein Test einen Wunsch mit gesetzten Bearbeitungs-Feldern (notes/handledAt) zurückliest. Status-Historie/Bearbeiter könnten still verloren gehen.

**Beleg.** customer_wish_model_test.dart enthält nur 'toMap/fromMap (snake_case) trippt rund' (Zeile 79); kein toFirestoreMap-Round-Trip. customer_wish_service_test.dart:69-82 prüft nur status + handledByUid.

**Empfehlung.** (1) Im Model-Test einen toFirestoreMap->fromFirestore-Round-Trip mit allen Feldern (notes, handledByUid, handledAt, status=seen, source) ergänzen. (2) Im Service-Test nach updateCustomerWishStatus(notes: '…') auch notes und handledAt!=null assertieren.

### 70. Bestellkorb-Mandanten-/Standort-Isolation und Einzel-Laden-Fallback (_listForSite) ungetestet

- **Schweregrad:** Niedrig  ·  **Kategorie:** test-gap  ·  **Konfidenz:** high  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/providers/inventory_provider.dart:323`, `lib/providers/inventory_provider.dart:326`, `lib/providers/inventory_provider.dart:337`, `lib/providers/inventory_provider.dart:1551`, `lib/repositories/firestore_inventory_repository.dart:357`, `test/order_cart_provider_test.dart:80`

**Problem.** Alle Korb-Tests laufen mit genau einem Laden (site-1). Der _listForSite-Fallback hat aber eine standortübergreifende Sonderregel: bei siteId==null/leer und genau einer vorhandenen Liste wird diese zurückgegeben (Zeile 327-329), bei mehreren Listen null. Damit liefert cartItemCount(null) eine Summe über alle Läden, orderCartForSite(null) je nach Listenzahl mal die einzige Liste, mal null. Es gibt keinen Test mit zwei Läden (zwei orderCarts), der prüft, dass addToCart(product mit site-1) NICHT in den site-2-Korb mischt und dass der Einzel-Laden-Fallback korrekt greift. Ebenso ungetestet: ein Produkt mit leerer siteId würde in _persistOrderList als Doc-ID '' geschrieben (Firestore-ungültig).

**Auswirkung.** Die App ist bewusst Zwei-Läden (Strichmännchen / Tabak Börse, MEMORY business-context). Eine Standort-Vermischung im Korb würde dazu führen, dass Bestellungen dem falschen Laden zugeordnet werden – ein echtes Geschäftsdaten-Integritätsproblem, das der aktuelle Ein-Laden-Test nicht fangen kann.

**Beleg.** _listForSite Zeile 327: 'return lists.length == 1 ? lists.first : null;'; alle Tests in order_cart_provider_test.dart verwenden ausschließlich siteId 'site-1'.

**Empfehlung.** Test mit zwei Läden: addToCart für site-1 und site-2, dann orderCartForSite('site-1')/('site-2') sind getrennt, cartItemCount() summiert beide, cartItemCount('site-1') nur den einen. Zusätzlich Fall 'genau eine Liste -> orderCartForSite(null) liefert sie' und 'zwei Listen -> orderCartForSite(null) == null' absichern. Edge-Case leere product.siteId klären/abfangen und testen.

### 71. addToCart-Merge: Denormalisierungs-Update (clearCategory/clearSupplier) bei Lieferantenwechsel ungetestet

- **Schweregrad:** Niedrig  ·  **Kategorie:** test-gap  ·  **Konfidenz:** medium  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/providers/inventory_provider.dart:1290`, `lib/providers/inventory_provider.dart:1293`, `test/order_cart_provider_test.dart:86`, `test/order_cart_models_test.dart:116`

**Problem.** Beim erneuten addToCart eines bereits im Korb liegenden Artikels werden die denormalisierten Felder aus dem Live-Produkt aktualisiert, inklusive der bedingten Clear-Flags: clearCategory: product.category == null und clearSupplier: product.supplierId == null (Zeile ~1300). Der einzige Merge-Test (Zeile 81) verwendet zweimal denselben Artikel ohne Kategorie/Lieferant und prüft nur die Mengensumme. Der Fall 'Artikel hatte beim ersten Add eine Kategorie/Lieferant und verliert ihn beim zweiten Add' (Clear-Pfad) wird nie ausgeführt.

**Auswirkung.** Würde der Clear-Pfad brechen (z.B. clearSupplier fälschlich nicht greifen), behielte die Korb-Position einen veralteten Lieferanten und checkoutCart gruppierte sie unter dem falschen Lieferanten – falsche Bestellzuordnung. Geringe Wahrscheinlichkeit, aber Geld-/Bestell-relevant.

**Beleg.** addToCart Merge übergibt clearCategory: product.category == null und clearSupplier: product.supplierId == null; Merge-Test (Zeile 86-94) nutzt nur 'Pueblo Tabak' ohne Kategorie/Lieferant.

**Empfehlung.** Test: addToCart(Produkt mit category/supplierId), dann saveProduct desselben Produkts ohne category/supplierId (oder direkt addToCart mit so verändertem Produkt-Objekt), erneut addToCart, dann assertieren, dass die Korb-Position category==null und supplierId==null hat.

### 72. _removeCartItems Name-basierter Schlüssel-Fallback ist faktisch ungetestete (tote) Robustheits-Logik

- **Schweregrad:** Niedrig  ·  **Kategorie:** test-gap  ·  **Konfidenz:** medium  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/providers/inventory_provider.dart:1503`, `lib/providers/inventory_provider.dart:1519`, `lib/providers/inventory_provider.dart:1521`

**Problem.** _cartItemKey nutzt für Positionen ohne productId einen Fallback-Schlüssel 'n:name|unit' (Zeile ~1432). Alle Korb-/Wochenlisten-Items entstehen in der Praxis ausschließlich aus Produkten und tragen daher immer eine productId (showOrderProductPicker, _addItem im Editor, addToCart). Damit wird der Name+Einheit-Fallbackpfad nie ausgeführt und auch nie getestet. Träten je zwei Positionen ohne productId mit gleichem name|unit auf, würden beim Checkout beide gemeinsam entfernt (Schlüsselkollision), obwohl nur eine ausgelöst wurde.

**Auswirkung.** Aktuell kein Live-Risiko (keine productId-losen Items), aber: Code, der gegen einen Zustand schützen soll, der nie eintritt, und gleichzeitig bei diesem Zustand falsch wäre (Kollision), ist eine versteckte Falle für künftige Features (z.B. manuelle Freitext-Positionen).

**Beleg.** _cartItemKey: 'n:${item.name}|${item.unit}' für productId==null; checkout-Test (order_cart_provider_test.dart:148ff) nutzt ausschließlich Items mit productId, Fallbackpfad nie ausgeführt.

**Empfehlung.** Entweder den Fallback entfernen und an einer Stelle eine productId erzwingen, oder – falls manuelle Positionen geplant sind – einen stabilen eindeutigen Schlüssel (z.B. lokale Item-ID) einführen und _removeCartItems damit testen.

### 73. AppConfig.publicStoreNameList-Parsing ungetestet (steuert die öffentliche Laden-Auswahl)

- **Schweregrad:** Niedrig  ·  **Kategorie:** test-gap  ·  **Konfidenz:** low  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `lib/core/app_config.dart:30`, `lib/screens/public/public_wish_screen.dart:32`, `firestore.rules:835`

**Problem.** publicStoreNameList parst APP_PUBLIC_STORES per split(',')/trim()/Filter leerer Werte. Diese Liste füllt das Laden-Dropdown der öffentlichen Wunsch-Seite und liefert den storeName, der in den (rule-validierten) öffentlichen Submit-Payload geht. Es gibt keinen Test für das Parsing (führende/abschließende Leerzeichen, leere Einträge bei 'A,,B', komplett leerer Wert -> leere Liste -> Screen fällt auf 'Laden' zurück).

**Auswirkung.** Ein Parsing-Fehler (z.B. leere Strings nicht gefiltert) würde leere Dropdown-Einträge oder einen storeName='' erzeugen; firestore.rules erlaubt storeName.size()<=120 inkl. leer, also würde ein leerer Laden-Name still durchgehen und im Eingang nutzlos sein. Geringe Schwere, aber trivial absicherbar.

**Beleg.** app_config.dart Zeile 28-33: split(',').map(trim).where(isNotEmpty); keine Testdatei referenziert publicStoreNameList.

**Empfehlung.** Unit-Test für publicStoreNameList: bei nicht überschreibbarem const From.environment ggf. die reine Split-/Trim-/Filter-Logik in eine testbare statische Hilfsfunktion ziehen und 'A, B ,,C' -> ['A','B','C'] sowie '' -> [] prüfen.
