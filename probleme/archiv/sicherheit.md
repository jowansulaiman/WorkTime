# Sicherheit: Firestore-Rules & Permissions

> Teil des WorkTime-Code-Reviews. Zurück zur [Übersicht](README.md).

### 17. customerWishes: jeder authentifizierte Nutzer (inkl. fremder Org) kann unbegrenzt in main-org schreiben — Spam/Cross-Tenant-Write

- **Schweregrad:** Mittel  ·  **Kategorie:** security  ·  **Konfidenz:** medium  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `firestore.rules:803-849`, `firestore.rules:356-362`, `firestore.rules:5-7`, `firestore.rules:72-74`

**Problem.** Der öffentliche Create-Pfad `match /customerWishes` verlangt nur `request.auth != null` und pinnt `orgId == publicWishOrg()` (= 'main-org'). Damit darf JEDER eingeloggte Account — auch ein voll authentifizierter Mitarbeiter einer ANDEREN Org oder ein beliebiger anonymer Account — beliebig viele Wunsch-Dokumente in die main-org schreiben. Es gibt keine Rate-Begrenzung; der Schutz ist laut Kommentar allein App Check, das aber in den Rules nicht erzwungen wird und im Repo nicht nachweislich aktiv ist.

**Auswirkung.** Massen-Spam in den internen Wunsch-Eingang von main-org möglich (Storage-/Kosten-/Bedien-Abuse), und ein Nutzer aus Org B kann gezielt Daten in den Datenbestand von Org A (main-org) einschleusen — eine Aufweichung der Mandanten-Isolation für genau diese Collection.

**Empfehlung.** App Check verbindlich machen (im Projekt aktivieren und ggf. via `request.appCheck`/Functions erzwingen) und/oder den öffentlichen Pfad auf anonyme Auth einschränken bzw. über eine Cloud Function mit Rate-Limiting leiten. Mindestens das Restrisiko (kein Rate-Limit in Rules) explizit als Betriebsannahme festhalten und App-Check-Status verifizieren.

### 60. orderCarts-Schreibregel: keine Feld-Allowlist und keine items-Validierung (BOPLA) — abweichend vom sonst durchgezogenen Muster

- **Schweregrad:** Niedrig  ·  **Kategorie:** security  ·  **Konfidenz:** high  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `firestore.rules:858-867`, `lib/models/order_cart.dart:233-243`

**Problem.** Die neue Regel `match /orderCarts/{siteId}` erlaubt `create, update` für JEDES aktive Org-Mitglied (auch Mitarbeiter ohne Verwaltungsrecht) und prüft nur `sameOrg`, `orgId == orgId` und `siteId == siteId`. Es gibt KEINE `keys().hasOnly(...)`-Allowlist und KEINE Typ-/Größenprüfung der eingebetteten `items`. Im Gegensatz dazu sind `stockMovements` (Zeile 893-914), `priceHistory` (751-771) und `customerWishes` (810-848) bewusst streng allowlisted. Ein beliebiger Mitarbeiter kann das Singleton-Korb-Doc seines Ladens mit beliebigen Zusatzfeldern, beliebig großen `items`-Arrays oder Mülldaten überschreiben.

**Auswirkung.** Ein einzelner (auch niedrig privilegierter) Mitarbeiter kann den gemeinsamen Korb-Datensatz beliebig aufblähen oder mit Fremdfeldern verseuchen (Mass Assignment / Document-Größen-Abuse, bis 1 MiB). Da der Korb ein Singleton je Laden ist (last-writer-wins, dokumentiert), kann er auch den gesamten Korbinhalt aller Kollegen löschen/verfälschen — Datenintegrität des geteilten Bestellkorbs.

**Empfehlung.** Analog zu stockMovements/customerWishes eine `request.resource.data.keys().hasOnly([...])`-Allowlist ergänzen (orgId, siteId, siteName, kind, items, updatedByUid, updatedAt), `items is list` mit Größenobergrenze (z.B. `items.size() <= 500`) prüfen und `kind` auf zulässige Werte ('cart') beschränken.

### 61. orderCarts: updatedByUid/addedByUid nicht an den Aufrufer gebunden (Audit-Spoofing)

- **Schweregrad:** Niedrig  ·  **Kategorie:** security  ·  **Konfidenz:** high  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `firestore.rules:863-865`, `lib/models/order_cart.dart:69-70`, `lib/models/order_cart.dart:184`

**Problem.** Beim Schreiben des Korbs (`orderCarts`) bzw. der Wochenliste (`weeklyOrderLists`) wird `updatedByUid` (SiteOrderList) und `addedByUid` (OrderListItem) nicht gegen `request.auth.uid` geprüft. Bei stockMovements/priceHistory/auditLog wird `createdByUid`/`actorUid` bewusst an den Aufrufer gepinnt (z.B. Zeile 768-770, 910-912, 722-724). Hier fehlt diese Bindung, obwohl der Korb die einzige Stelle ist, an der auch normale Mitarbeiter schreiben.

**Auswirkung.** Ein Mitarbeiter kann Korbpositionen im Namen eines anderen Mitarbeiters eintragen (`addedByUid` frei wählbar) bzw. `updatedByUid` fälschen. Die ohnehin dünne Nachvollziehbarkeit, wer was in den Korb gelegt hat, wird wertlos und kann gezielt einem Kollegen untergeschoben werden.

**Empfehlung.** In der orderCarts-Regel `request.resource.data.updatedByUid == request.auth.uid` (oder null) erzwingen. Für `addedByUid` je item ist eine Rules-Prüfung über Arrays schwer; alternativ den Wert serverseitig/in der Allowlist neutralisieren oder dokumentieren, dass es kein Sicherheitsfeld ist.

### 62. publicWishOrg() ist hart auf 'main-org' verdrahtet, AppConfig.defaultOrganizationId aber per dart-define überschreibbar — Drift-Risiko

- **Schweregrad:** Niedrig  ·  **Kategorie:** compliance-drift  ·  **Konfidenz:** high  ·  **Status:** adversarial verifiziert
- **Fundstellen:** `firestore.rules:360-362`, `firestore.rules:810-812`, `lib/screens/public/public_wish_screen.dart:72`, `lib/core/app_config.dart:11-14`

**Problem.** Die Rules-Funktion `publicWishOrg()` liefert konstant `'main-org'`. `AppConfig.defaultOrganizationId` hat denselben Default, ist aber via `--dart-define=APP_DEFAULT_ORG_ID` frei änderbar. Wird die App mit einer anderen Default-Org deployt (z.B. echter Prod-Org-Slug), pinnt der Client `orgId` auf diesen Wert, die Regel verlangt jedoch weiterhin 'main-org' → alle öffentlichen Kundenwünsche werden still mit permission-denied abgewiesen. Der Kommentar dokumentiert die Kopplung, aber sie ist nicht erzwungen.

**Auswirkung.** Stille Funktionsstörung der öffentlichen Wunsch-Seite bei jedem Deployment, das eine andere Org-ID verwendet — schwer zu diagnostizieren (keine Fehlermeldung außer permission-denied). Klassischer Hardcoding-Footgun in einer mandantenfähigen App.

**Empfehlung.** Beim Setzen einer abweichenden APP_DEFAULT_ORG_ID den Wert in `publicWishOrg()` synchron mitziehen (Deploy-Checkliste) oder die öffentliche Wunsch-Org explizit als separaten, dokumentierten Konfigurationswert führen und in beiden Welten aus derselben Quelle ableiten.
