# MHD-/Ablaufdatum-Warnung — Plan

**Stand:** 2026-07-01 · **Status:** **M1–M4 code-fertig** (`flutter analyze` clean, volle Suite grün, `node --check`/`node --test` grün) · offen nur **Deploy** (Rules/Index/Functions, Blaze) + manuelle Verifikation · **Priorität:** hoch (Inhaber: „sehr wichtig")
**Verwandt:** Kiosk-Kachel in [`plan/arbeitsmodus-kachel-ausbau.md`](arbeitsmodus-kachel-ausbau.md) (§2.6) · Push-Infra [`plan/push-benachrichtigungen-plan.md`](push-benachrichtigungen-plan.md) · Vorbild [`plan/kuehlschrank-nachfuell-automatik.md`](kuehlschrank-nachfuell-automatik.md)

> **Umsetzungsstand M1–M4 (2026-07-01):** Vollständig gebaut + getestet.
> **M1 (offline):** [`lib/models/product_batch.dart`](../lib/models/product_batch.dart), [`lib/core/expiry_warning.dart`](../lib/core/expiry_warning.dart), Tests [`test/product_batch_test.dart`](../test/product_batch_test.dart) + [`test/expiry_warning_test.dart`](../test/expiry_warning_test.dart) + Provider-Batch-Test. Geändert: `InventoryRepository`(+FirestoreImpl+Test-Fake), `DatabaseService` (Collection `product_batches`), `InventoryProvider` (`_batches`-Stream + `expiryWarnings`/`expiryWarningCount` + `saveBatch`/`resolveBatch`, 3 Storage-Modi + Audit), `scanner_screen.dart` (Button „MHD erfassen"), `notification_screen.dart` (`_InboxItemKind.expiry`), `kiosk_screen.dart` (`_ExpiryTile`).
> **M2 (Rules):** `firestore.rules`-Block `productBatches` (read `sameOrg`; create/update `sameOrg` + Feld-Allowlist + `status`-Enum, offen für Scanner-Staff UND Kiosk-Geräte-Konto = „direct-device"; delete `canManageInventory`).
> **M3 (Index):** `firestore.indexes.json` Composite `productBatches(status ASC, expiryDay ASC)` für die Nightly-Range-Query. Client-Board braucht keinen Index (einzelnes `orderBy(expiryDay)`).
> **M4 (Push):** `functions/index.js` `expiryWarningNightly` (`onSchedule` täglich 07:00 Europe/Berlin) → Query aktive Chargen `expiryDay <= heute+3` je Org → Standortnamen auflösen → **bestehende `fanOutPush`** (Kanal `bestand`), idempotent via `dedupeId = batchId:expiryDay` (je Charge genau ein Push). `push_notifications.js` `buildExpiryNotification` + `channelIdForType('expiry')→'bestand'` (+ Dart-Parität in `push_messaging_service.dart`). Tests: `node --test` 18/18, `push_channel_mapping_test` grün.
> **Offen:** **Deploy** (`firebase deploy --only firestore:rules,firestore:indexes,functions`, Blaze) + Rules-Emulator-Verifikation + manuelle Geräte-Prüfung (Scan→Inbox→Kiosk→abhaken, Nightly→Push).

> Datei-/Zeilenangaben gegen HEAD (`fix/web-scanner-csp-selfhost-zxing`) verifiziert. Unverifizierbares ist **(Annahme)** markiert.

---

## 1. Ziel & Scope

**Ziel (Inhaber, „sehr wichtig"):** MHD/Ablaufdatum von Getränken & Süßwaren erfassen und **2–3 Tage vor Ablauf** warnen. Die Warnung erscheint auf **allen Laden-Tablets (Kiosk-Board)** UND **in der App** (In-App-Inbox), sowie als **Push** (App zu/Hintergrund). Kein Artikel läuft unbemerkt ab.

**Fachliche Kernentscheidung:** Reale Ware hat **mehrere Chargen mit unterschiedlichem MHD** (zwei Lieferungen Cola → zwei Ablaufdaten). Ein einzelnes `expiry`-Feld am `Product` ([lib/models/product.dart](../lib/models/product.dart)) wäre fachlich falsch, weil `Product.currentStock` (:85) EINE Zahl ohne Chargenbezug ist. **Entscheidung: eigenes Chargen-/Los-Model `ProductBatch`** (mehrere je Produkt) als eigene org-skopierte Collection. `Product` bleibt unangetastet (keine Änderung an dessen 6 Serialisierungsstellen).

**Bewusst NICHT im Scope (Grenzen):**
- Keine bilanzielle Chargen-Bestandsführung (FIFO-Abwertung, chargengenaue Warenwert-Rechnung). `ProductBatch.quantity` ist eine **weiche Mengenangabe** analog `Product.fridgeStock` (nicht bilanziell), nur zur Priorisierung/Anzeige. Der bilanzielle Bestand bleibt `Product.currentStock`.
- Kein automatischer Chargen-Abbau durch OktoPOS-Verkäufe in M1 (Verkauf weiß nicht, welche Charge verkauft wurde) — spätere Ausbaustufe (§Offene Punkte).
- Kein Zwang zur MHD-Erfassung — optional beim Wareneingang.

## 2. Datenmodell

### Neues Model `ProductBatch` (`lib/models/product_batch.dart`, Greenfield)

Eine Charge/Los eines Produkts mit genau einem MHD. Mehrere Batches je `productId`.

| Feld | Typ | Zweck |
|---|---|---|
| `id` | `String?` | Doc-ID (von `FirestoreService` via `collection.doc()`, `entityId==null` beim Anlegen — bekannte harmlose Audit-Einschränkung, siehe CLAUDE.md) |
| `orgId` | `String` | Mandant |
| `siteId` | `String` | Laden (Multi-Tenancy + Kiosk-Skopierung) |
| `productId` | `String` | FK → `Product.id` |
| `productName` | `String?` | denormalisiert für Anzeige ohne Join (analog `Product.siteName`) |
| `expiryDate` | `DateTime` | **MHD** — Pflicht (ohne MHD keine Charge). Auf lokale Mittagszeit (12:00) normalisieren wie `WorkEntry.date`, um Zeitzonen-/DST-Off-by-one zu vermeiden |
| `quantity` | `int` | verbleibende Menge dieser Charge (weich, nicht bilanziell) |
| `note` | `String?` | Freitext (z.B. „Palette hinten links") |
| `status` | `BatchStatus` | `active` / `soldOut` / `discarded` — abgehakte Chargen verschwinden aus der Warnung, bleiben zur Historie |
| `resolvedByUid` | `String?` | wer als erledigt/entsorgt markiert hat |
| `resolvedAt` | `DateTime?` | wann |
| `createdByUid` | `String?` | Erfasser |
| `createdAt` / `updatedAt` | `DateTime?` | Timestamps |

**Enum `BatchStatus`** nach Projektregel 3:
- `.value`-Getter → snake_case: `active` / `sold_out` / `discarded`
- `fromValue(String?)` mit **Default-Branch** (`active`, wirft nie)
- deutsches `label`: „Aktiv" / „Abverkauft" / „Entsorgt"

**Zwei-Serialisierungs-Regel (Pflicht — je Feld 6 Stellen):**
- `toFirestoreMap()` — **camelCase**, `expiryDate`→`Timestamp`, `updatedAt`→`FieldValue.serverTimestamp()`, plus `expiryDay: 'YYYY-MM-DD'` (String, für stabile Sortierung/Query ohne Timestamp-Tücken — analog `nameLower` beim Product)
- `fromFirestore(String id, Map map)` — ID als separates erstes Argument; Zahlen via `parse.toInt`, Datum via `FirestoreDateParser.readDate`, Enum via `BatchStatus.fromValue`
- `toMap()` — **snake_case**, `expiry_date`→ISO-8601-String
- `fromMap(Map map)` — liest `map['id']`, Datum via `FirestoreDateParser.readLocalDate`
- `copyWith(...)` — mit **`clearNote`/`clearResolvedByUid`/`clearResolvedAt`** (nullable → `clearX ? null : (x ?? this.x)`). `expiryDate` ist **non-null** → kein `clearX`.
- `functions/index.js`: **entfällt in M1** (Batches laufen nicht über Callables, sondern als direkter Firestore-Write wie Templates/Teams). Der Nightly-Job (M4) liest per Admin-SDK die **camelCase**-Firestore-Docs direkt → **kein** snake_case-Parser nötig.

Round-Trip-Test verpflichtend: `toFirestoreMap`→`fromFirestore` und `toMap`→`fromMap` müssen identisch round-trippen.

## 3. Pure Warn-Engine — spiegelt `computeFridgeShortfalls` 1:1

### `lib/core/expiry_warning.dart` (Greenfield, pure)

Spiegelt exakt [lib/core/fridge_refill_shortfall.dart](../lib/core/fridge_refill_shortfall.dart) (`computeFridgeShortfalls` :51, `FridgeShortfall` :24): **kein State, kein IO, kein `DateTime.now()` — `now` wird injiziert** → deterministisch offline testbar.

```dart
enum ExpirySeverity { expired, critical, soon }   // .value/label deutsch:
  // expired = „Abgelaufen", critical = „Läuft heute/morgen ab", soon = „Läuft bald ab"

class ExpiryWarning {
  final ProductBatch batch;
  final int daysUntilExpiry;   // negativ = schon abgelaufen
  ExpirySeverity get severity; // abgeleitet aus daysUntilExpiry + leadDays
}

List<ExpiryWarning> computeExpiryWarnings(
  Iterable<ProductBatch> batches,
  DateTime now, {                 // injiziert — Pflicht, KEIN Default now()
  int leadDays = 3,               // „2–3 Tage vorher" → Default 3, konfigurierbar
  String? siteId,
}) { ... }
```

Regeln (deterministisch):
- Nur `status == BatchStatus.active`.
- Optional `siteId`-Filter (analog Fridge-Engine).
- Tagesdifferenz aus **auf Mitternacht normalisierten Kalendertagen** von `now` und `batch.expiryDate` (nicht Millisekunden-Delta → sonst Off-by-one). `daysUntilExpiry = expiryDay − nowDay`.
- Aufgenommen wird eine Charge, wenn `daysUntilExpiry <= leadDays` (schließt abgelaufene mit ein).
- `severity`: `daysUntilExpiry < 0` → `expired`; `<= 1` → `critical`; sonst `soon`.
- Sortierung: aufsteigend nach `daysUntilExpiry` (dringendste zuerst).

**Test** `test/expiry_warning_test.dart` analog der Fridge-Engine-Tests: feste `now`, feste Batch-MHDs, assert auf `severity`/`daysUntilExpiry`/Reihenfolge/`leadDays`-Grenze/`siteId`-Filter/`status`-Filter. Wall-Clock-frei.

## 4. Provider-Anbindung (`InventoryProvider`)

Batches leben im `InventoryProvider` ([lib/providers/inventory_provider.dart](../lib/providers/inventory_provider.dart)) wie die anderen Inventar-Daten. **Cloud-Repo LAZY auflösen** (nie im Konstruktor).

**Lese-API** (analog `fridgeShortfalls` :457 / `fridgeShortfallCount` :461):
```dart
List<ExpiryWarning> expiryWarnings({String? siteId, int leadDays = 3, DateTime? now})
  => computeExpiryWarnings(_batches, now ?? DateTime.now(), leadDays: leadDays, siteId: siteId);
int expiryWarningCount([String? siteId])  // für Badge/Kachel-Zähler
```
`now` als optionaler Test-Parameter (Muster wie `orderFrequencyByProduct({DateTime? now})`), sonst `DateTime.now()`.

**Mutatoren** (drei Storage-Modi, Muster wie `adjustStock` :1781):
- `saveBatch(ProductBatch)` — anlegen/ändern.
- `resolveBatch(String batchId, {required BatchStatus status})` — als abverkauft/entsorgt markieren (setzt `status`, `resolvedByUid`, `resolvedAt`).

Jeder Mutator nach Muster:
```
if (usesLocalStorage) { lokal mutieren + persist + _safeNotify(); _audit?.call(...); return; }
try { Firestore-Write; _audit?.call(...); }
catch (e) { if (hybrid) { lokal fallbacken; _audit?.call(...); } else { rethrow; } }
```

**Audit:** MHD erfassen (`batch_created`), als erledigt/entsorgt abhaken (`batch_resolved`) sind fachlich relevant → `_audit?.call(action:, entityType:'productBatch', entityId:, summary:<deutsch>)` **im Provider-Mutator, nur auf Erfolgs-Pfad** (in jedem Storage-Zweig: local-return UND hybrid-catch-Fallback; NIE auf rethrow/Deny). Deutsche Summaries, z.B. „Charge angelegt: Cola 0,33l, MHD 05.07.2026" / „Charge entsorgt: Cola 0,33l".

**Lokale Persistenz:** Neue Collection `product_batches` in `DatabaseService` registrieren, **org-skopiert**, über `_load/_saveCollection`, `toMap`/`fromMap` muss round-trippen. Im **hybrid**-Modus werden Batches — wie userContent (Zeiteinträge/Templates) — lokal gespiegelt (spart Firestore-Writes); Batches sind bewegliche Nutzdaten, nicht Stammdaten.

## 5. Erfassungspunkt (UX)

**Wareneingang im Scanner** ([lib/screens/scanner_screen.dart](../lib/screens/scanner_screen.dart)): Beim Einbuchen von Ware über `adjustStock` (Aufruf `:449`) bzw. den Produkt-Editor-Sheet (`showModalBottomSheet` :378) wird ein optionales Feld **„MHD erfassen"** (Datumsauswahl) angeboten. Bestätigen legt via `InventoryProvider.saveBatch(...)` eine Charge mit eingebuchter Menge + gewähltem MHD an.
- `DatePicker` mit `locale: Locale('de','DE')`; jedes `DateFormat` explizit `'de_DE'`.
- Kein Zwang: MHD leer → keine Charge, reiner Bestandszugang wie bisher.
- MHD-Feld pragmatisch für **alle** Produkte einblendbar (nicht hart an `category` „Getränke"/„Süßwaren" koppeln — `category` ist Freitext, `product.dart:64`); die zwei Kategorien sind der fachliche Haupt-Anwendungsfall, aber MHD gibt es auch anderswo.
- Zusätzlicher Einstieg (später): Chargen eines Produkts im Produkt-Editor listen/bearbeiten. M1 nur Anlegen beim Eingang.

## 6. Anzeige App — In-App-Inbox

**M1-Entscheidung: abgeleitet/transient über neuen `_InboxItemKind`**, NICHT persistierte Notification. Die Inbox in [lib/screens/notification_screen.dart](../lib/screens/notification_screen.dart) ist bereits **abgeleitet** (`_buildItems()` :548, `_InboxItem` :80, enum `_InboxItemKind { request, swap, shift, update }` :45) und nicht persistiert. Eine Ablauf-Warnung ist ebenfalls rein aus `expiryWarnings()` ableitbar → geringste Kopplung, keine neue Collection/Rules/Index für M1.

Umsetzung:
- Enum erweitern: `_InboxItemKind { request, swap, shift, update, expiry }` (:45).
- In `_buildItems(...)` (:548) für die sichtbaren Läden des Nutzers `inventory.expiryWarnings(siteId: ...)` einlesen und je Warnung ein `_InboxItem(kind: expiry, ...)` erzeugen. Deutsch: „N Artikel laufen bald ab" bzw. je Artikel „Cola 0,33l — läuft in 2 Tagen ab (05.07.2026)".
- Sortierprio in der bestehenden Sort-Funktion für `expiry` (dringlich, nahe oben).
- Sichtbarkeit: alle Mitarbeiter des Ladens (Ablauf ist operativ, nicht admin-only) — konsistent mit der Kühlschrank-Nachfüllliste.

> **Ergänzung ab M4:** Der Nightly-Job schreibt zusätzlich **persistierte** `notifications`-Docs (dieselbe Collection, die `fanOutPush` befüllt, §9). Wenn der In-App-Notification-Reader (`NotificationProvider`) diese Collection ohnehin anzeigt, erscheint die Warnung dann auch bei geschlossener App / nach Neustart — ohne den M1-Ableitungspfad zu ersetzen (beide koexistieren).

## 7. Anzeige Kiosk-Board

Board existiert real ([lib/screens/kiosk/kiosk_screen.dart](../lib/screens/kiosk/kiosk_screen.dart)). Die Tile-Liste `tiles` in `_KioskBoard.build` (`:437–443`: `_ClockTile`/`_StoreTasksTile`/`_FridgeTile`/`_WishesTile`/`_HintsTile`) ist der Erweiterungspunkt. **`_FridgeTile(siteId:)` (:440) ist die exakte Vorlage.**

- **Neue Kachel `_ExpiryTile(siteId: siteId)`** in die Liste (`:437–443`) einfügen (bzw. via `_KioskTileSpec`-Registry, s. Kiosk-Plan §4).
- Board-Anzeige (read-only, glanceable, **site-skopiert** via Geräte-`siteId`): Zähler „**N Artikel laufen in ≤ 3 Tagen ab**" + die dringendsten 3–5 Artikel mit Restlaufzeit. Farbe über `Theme.of(context).appColors` (warning/error), **nie hardcoden**.
- Datenquelle: `context.watch<InventoryProvider>().expiryWarnings(siteId: siteId)` — dieselbe Engine, keine Extra-Query.
- **Session-Aktion (nach PIN):** „MHD erfassen" (öffnet dasselbe Batch-Anlege-Sheet) und je Warnung „als abverkauft/entsorgt abhaken" → `resolveBatch(...)`. Läuft über den Kiosk-Session-Mechanismus (Geräte-Konto `role:kiosk` bleibt einzige Identität, kein Identitätswechsel — s. Kiosk-Plan). Board-Kachel ist ein reiner Client-Stream (kein Server nötig).
- `DateFormat('dd.MM.yyyy', 'de_DE')` für MHD-Anzeige.

## 8. Firestore: Rules, Index, Multi-Tenancy

**Collection:** `organizations/{orgId}/productBatches` (org-skopiert, Konvention wie `shifts`/`workEntries`). Collection-Getter in `FirestoreService` ergänzen — **Pfad nie hardcoden**.

**Rules (`firestore.rules`):** neuen `productBatches`-Block analog `products`/`stockMovements`: `sameOrg`-read; write für Rollen mit `canManageInventory` **plus** — falls der Kiosk-Session-Mitarbeiter erfassen/abhaken darf — ein schmaler, feld-whitelisted Pfad für das Geräte-Konto (analog `storeTasks.completedBySite`, s. Kiosk-Plan §6). **Kiosk-Read** ist site-skopiert/datensparsam (nur Batches des eigenen `siteId`). `sameOrg` in Rules ↔ (Nightly-Job) `assertSameOrg`/Admin-SDK synchron.

**Composite-Index (`firestore.indexes.json`):** Für die serverseitige Range-Abfrage (Nightly M4):
```
collection: productBatches, fields: [status ASC, siteId ASC, expiryDay ASC]
```
bzw. minimal `[siteId ASC, expiryDay ASC]`. Index **hinzufügen + deployen**, sonst Laufzeitfehler.
> **M1-Hinweis:** Solange die Batches im `InventoryProvider` im Speicher liegen (wie Produkte) und die Warnung **rein clientseitig** aus `_batches` abgeleitet wird, ist in M1 **keine** `where+orderBy`-Query und damit **kein** Index nötig. Der Index wird erst mit der Cloud-Range-Query/Nightly (M4) fällig. Bewusst so geschnitten.

## 9. Push — bestehende Infra wiederverwenden (KEIN Doppelbau)

**Push ist bereits im Code gebaut** (nicht greenfield — Push-Plan M1–M7 fertig+getestet, nur Blaze-Deploy/Commit steht aus): `functions/index.js` hat `fanOutPush({orgId, recipientUids, notif, requestId})` (**:150**) → schreibt idempotent in die **`notifications`-Collection** (:152), liest `fcmTokens` (:186) und sendet via `admin.messaging().sendEachForMulticast` (:203). **Sechs Trigger nutzen es bereits:** `onCustomerWishCreated` (:234), `onCustomerFeedbackCreated` (:357), `onAbsenceRequestWritten` (:381), `onShiftSwapRequestWritten` (:429), `onShiftWritten` (:488), **`onProductWritten` (:536)**. Helfer `push_notifications.js` (:11), Trigger-Wrapper `documentCreatedTrigger` (:112)/`documentWrittenTrigger` (:273), Token-Pflege `pruneStaleFcmTokens` onSchedule (:578). `notificationPrefs`/`APP_PUSH_ENABLED`-Gating vorhanden.

- **MHD nutzt exakt diese Infra:** der Nightly-Job (M4) ruft die bestehende `fanOutPush(...)` mit `notif = {Kanal „Ablauf/MHD"}` → schreibt `notifications`-Docs + Push. **Kein** neuer FCM-/Messaging-Code.
- **Warum Nightly statt Event-Trigger:** MHD-Warnungen sind **zeitbasiert** (2–3 Tage vor Ablauf) — kein Schreib-Event feuert „in 2 Tagen". Daher `onSchedule` (§10), NICHT `documentWrittenTrigger`. (Der bestehende `onProductWritten`-Trigger passt nicht, weil er beim Produkt-Write feuert, nicht zeitgesteuert.)
- Push ist **nicht M1** (M1 ist rein clientseitig/offline), sondern M4.
- **Empfänger (Datensparsamkeit):** alle aktiven Mitarbeiter des betroffenen Ladens (operative Info), gefiltert über `notificationPrefs`. Nicht org-weit, nicht nur Leiter.

## 10. Nightly-Job / serverseitige Warnung (M4)

`onSchedule`-Function analog `oktoposNightlySync` (`functions/index.js:2920`) / `pruneStaleFcmTokens` (:578), Region `const REGION = 'europe-west3'` (:19), **Blaze**. Ablauf:
1. Je Org/Site die aktiven Batches mit `expiryDay <= now+leadDays` lesen (Index §8, Admin-SDK, umgeht Rules).
2. Empfänger je Site auflösen (aktive Mitarbeiter + `notificationPrefs`).
3. **Bestehende `fanOutPush({orgId, recipientUids, notif, requestId})` (:150) aufrufen** → `notifications`-Docs + Push.
4. **Idempotenz:** pro Batch+Tag nur eine Warnung (z.B. `lastWarnedDay` am Batch oder ein Marker-Doc), damit nicht täglich dieselbe Push doppelt kommt — Muster wie `fanOutPush` es für Inbox-Docs schon macht.

Keine Client-Änderung für die reine serverseitige Erzeugung nötig.

## 11. Meilensteine

| M | Inhalt | Server? | Offline-testbar (`APP_DISABLE_AUTH=true`)? |
|---|---|---|---|
| **M1** ✅ | `ProductBatch`-Model (6 Serialisierungsstellen, `BatchStatus`-Enum) · pure `computeExpiryWarnings` + Test · `InventoryProvider` Lese-API + `saveBatch`/`resolveBatch` (3 Storage-Modi, Audit) · `DatabaseService` lokale Collection · Scanner-Erfassung · In-App-Inbox `expiry`-Kind · Kiosk `_ExpiryTile` (Board-Zähler + Session-Aktion) — **umgesetzt 2026-07-01** | **Nein** | **Ja** (voller Nutzen ohne Server) |
| **M2** ✅ | Rules-Block `productBatches` (Feld-Allowlist, direct-device für Scanner+Kiosk, delete manager-only) — **code-fertig**, Deploy offen | Deploy | — |
| **M3** ✅ | Composite-Index `productBatches(status, expiryDay)` — **code-fertig**, Deploy offen | Deploy | — |
| **M4** ✅ | Nightly `expiryWarningNightly` (`onSchedule`) → bestehende `fanOutPush` (Kanal `bestand`), idempotent `batchId:expiryDay` — **code-fertig**, Deploy offen | Blaze | — |

**M1-Schnitt (verbindlich):** M1 läuft vollständig offline (`flutter run --dart-define=APP_DISABLE_AUTH=true`), liefert echten Nutzen (Erfassen + Warnen in App & Kiosk), **ohne** Push/Nightly/Index/Rules-Deploy.

## 12. Kritische Kopplungen & Risiken

1. **Neues Model `ProductBatch`** → 6 Serialisierungsstellen (`toFirestoreMap`/`fromFirestore`/`toMap`/`fromMap`/`copyWith`+`clearX`) + Round-Trip-Test; `BatchStatus`-Enum mit `.value`/`fromValue`(Default)/deutschem `label`.
2. **Neue lokal-persistierte Collection `product_batches`** → in `DatabaseService` registrieren (org-skopiert), über `_load/_saveCollection`.
3. **Composite-Index** bei jeder `where(siteId/status)+orderBy(expiryDay)`-Query → `firestore.indexes.json` + Deploy (nur ab M3/M4).
4. **Rules ↔ Functions synchron** (`sameOrg` ↔ Admin-SDK/`assertSameOrg`); Kiosk-Read site-skopiert; optionaler Kiosk-Write feld-whitelisted.
5. **Push reuse** (`fanOutPush:150`, `notifications`-Collection) — **nicht** neu bauen; Nightly zeitgesteuert (`onSchedule`), Region `europe-west3`, Blaze.
6. **Audit** nur auf Erfolgs-Pfad in jedem Storage-Zweig (nie doppelt, nie auf Deny).
7. **Datum** auf lokale Mittagszeit normalisieren (wie `WorkEntry.date`); Tagesdifferenz kalendertag-basiert (Off-by-one-Falle).
8. **Deutsch-only**, jedes `DateFormat`/`DatePicker` explizit `'de_DE'`.

## 13. Offene Punkte / Restrisiken

- **Chargen-Abbau bei Verkauf** ungelöst (OktoPOS-Verkauf kennt die Charge nicht) → Chargenmengen driften; M1 akzeptiert das bewusst (weiche Menge, nicht bilanziell). Später: FIFO-Heuristik (ältestes MHD zuerst mindern) prüfen.
- **Kiosk-Write-Recht für `productBatches`** (Erfassen/Abhaken am Kiosk unter dem Geräte-Konto) muss zur Kiosk-Rules-Skopierung passen — vor M2 gegen `firestore.rules` verifizieren.
- **Idempotenz des Nightly** (nicht täglich dieselbe Push) — Marker `lastWarnedDay` am Batch vs. separates Marker-Doc entscheiden.
- Deploy (Rules/Index/Functions) für M2–M4 gebündelt; Blaze für M4.

## 14. Quality Gates / Definition of Done

```bash
flutter analyze                                   # lint clean
flutter test                                      # inkl. expiry_warning_test.dart + ProductBatch-Round-Trip
flutter run --dart-define=APP_DISABLE_AUTH=true   # M1 offline verifizieren
```
- **M1 manuell offline:** Charge im Scanner anlegen → Inbox-Item + Kiosk-Kachel-Zähler steigen → „entsorgt" abhaken → Warnung verschwindet.
- Alle Texte deutsch; jedes `DateFormat`/`DatePicker` explizit `'de_DE'`.
- Audit-Einträge für Anlegen/Auflösen (nur Erfolgs-Pfad, alle Storage-Zweige).
- Emulator für Rules (M2) + Nightly/Push (M4). Deploy gebündelt vor Go-Live.
