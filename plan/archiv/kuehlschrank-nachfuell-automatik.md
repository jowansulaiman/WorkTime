# Kühlschrank-Nachfüll-Automatik — Plan

> Für **Strichmännchen & Tabak Börse** (zwei Kieler Läden, eine Org). Baut auf der bestehenden
> **manuellen Kühlschrank-Nachfüllliste** ([lib/models/fridge_refill.dart](lib/models/fridge_refill.dart),
> [lib/screens/fridge_refill_screen.dart](lib/screens/fridge_refill_screen.dart)) und der
> **OktoPOS-Anbindung** ([plan/oktopos-datenwert-plan.md](plan/oktopos-datenwert-plan.md)) auf.
>
> **Stand: 2026-06-30, ✅ IMPLEMENTIERT (Phase 1 + 2, 1209 Tests grün, `flutter analyze` sauber, `node --check` ok).**
> Offen nur noch: Deploy (`firestore:rules` + `functions`, Blaze) und Emulator-Verifikation des Refill-Rule-Zweigs. Siehe §14.
>
> ⚠️ **Zeilen-Referenzen driften ~6-10 Zeilen** (Datei wächst) — beim Bau per **Symbolnamen** anspringen, nicht blind die Zeile. Alle genannten Symbole/Blöcke existieren (verifiziert).

## 1. Was der Inhaber will

Getränke liegen im **Kühlschrank** (Verkaufsregal) und im **Lager**. Wird ein Getränk verkauft, sinkt
der Kühlschrank-Bestand. Man will den **Kühlschrank-Stand kennen**. Wenn **viel verkauft** wird **oder**
**am Tagesende vor Ladenschluss** soll die UI zeigen, **was im Kühlschrank fehlt**, und die Mitarbeiter
sollen **benachrichtigt** werden: „Es ist noch im Lager vorhanden — bitte Kühlschrank nachfüllen."

## 2. Datenbefund (ehrlich, code-verifiziert) — drei harte Wahrheiten

Diese drei Befunde bestimmen das ganze Design. Ohne sie wird das Feature eine Lüge anzeigen.

1. **Es gibt heute KEINEN Kühlschrank-Bestand.** [Product](lib/models/product.dart) trägt genau **einen**
   `currentStock` je Standort (plus `minStock`/`targetStock`), und das ist der **Gesamt-/Lagerbestand**.
   Der OktoPOS-Verkauf dekrementiert genau diesen einen Wert (`FieldValue.increment`,
   [functions/index.js:2601-2604](functions/index.js#L2601-L2604)). Die bestehende
   `FridgeRefillList` ist eine **manuelle Checkliste** (`FridgeRefillItem` mit `productId`/`quantity`/`done`)
   **ohne Soll/Ist** — sie misst keinen Füllstand. Die vom Inhaber skizzierte Zeile „Cola 8/24, im Lager 30"
   ist mit dem heutigen Modell **nicht ableitbar**.

2. **„Verkauf senkt den Kühlschrank automatisch" braucht den OktoPOS-Verkaufsstrom.** Nur der Kassen-Pull
   liefert die Verkaufsbewegungen. Der Code ist gebaut, aber **noch nicht scharfgeschaltet / deployt**
   (braucht **Blaze** + Secret + Scheduler, siehe OktoPOS-Memos). **Ohne ihn kann nichts automatisch sinken.**
   Vor dem Go-Live degradiert das Feature bewusst auf das manuelle Modell (Phase 1).

3. **Es gibt KEIN Push/FCM** (kein `firebase_messaging`, kein `flutter_local_notifications` — verifiziert).
   „Mitarbeiter benachrichtigen" = **In-App**: Home-Aktionskarte + Posteingang-Eintrag + Tab-Badge,
   sichtbar **beim nächsten Öffnen der App**. Ein echter Handy-Push („pingt abends, auch wenn die App zu ist")
   ist ein **separates späteres Projekt** (Phase 3).

## 3. Modell-Entscheidung: `fridgeStock` als Teilmenge von `currentStock`

Drei Architektur-Ansätze wurden ausgearbeitet und von einer Jury bewertet (Gewicht auf POS-Sync-Korrektheit
und Daten-Integrität):

| Ansatz | Kern | Score | Urteil |
|---|---|---|---|
| **A** Teilbestand am Product (`fridgeStock`/`fridgeTargetStock`/`inFridge`) | echtes Soll/Ist, Lager abgeleitet | 71 | exakt, aber Eingriff am bezahlten POS-Pfad |
| **B** separate `fridgeSlots`-Collection | Product unangetastet | 52 | zweite Wahrheit, fragiles `productId`-Matching, teuerste Migration |
| **C** verkaufsgeschätzt (`fridgeCapacity` + `lastRefilledAt`, Ist aus Verkäufen geschätzt) | kein zweiter Zähler | 84 | sauberste Integrität, aber **tot ohne OktoPOS** und keine konkrete Ist-Zahl |

**Empfehlung dieses Plans: Ansatz A, gehärtet mit den robusten Ideen aus C** (Refill-Reset als Wahrheitsanker
+ clamp-on-read). Begründung der Abweichung von der reinen Jury-Empfehlung (C): C produziert **heute nichts**
(OktoPOS nicht live) und **nie im local-Modus**, und es liefert keine konkrete „8/24"-Zahl, die die gewünschte
UI voraussetzt. Der gehärtete A-Ansatz funktioniert **sofort in allen drei Speichermodi** (über den
Refill-Reset) und schaltet die echte Verkaufs-Automatik **additiv** frei, sobald OktoPOS läuft.

### Semantik (die tragende Invariante)

```
currentStock   = Gesamt-Bestand im Laden (Lager + Kühlschrank) — POS-autoritativ, unverändert
fridgeStock    = Menge, die physisch im Verkaufs-Kühlschrank liegt   (Teilmenge ⊆ currentStock)
Lager (abgel.) = max(0, currentStock − fridgeStock)                  — NIE separat gespeichert
```

- **Verkauf** eines Kühlschrank-Artikels: `currentStock −1` **und** `fridgeStock −1` → Lager unverändert ✓
- **Nachfüllen** N (Lager→Kühlschrank): `currentStock` **0** (nur physische Umlagerung), `fridgeStock +N`,
  Lager `−N` ✓ — **kein** Gesamt-Abgang. Es wird eine **`fridgeRefill`-Bewegung** (Protokoll, §12.6) geschrieben,
  die `currentStock` aber **nicht** verändert.
- **„Fehlt im Kühlschrank"**: `inFridge && fridgeStockClamped < fridgeTargetStock && Lager > 0`
  (das `Lager > 0` ist die Idee aus A, die die Anforderung „**noch im Lager vorhanden**, bitte nachfüllen"
  exakt trifft und ausverkaufte Artikel herausfiltert).

`fridgeStock` ist eine **weiche Schätzung**, die bei jedem Nachfüllen **neu auf den Soll-Wert verankert** wird
(siehe §6). Sie steuert **nur die Vorschlagsqualität** und wird **bewusst aus Warenwert-/Schwund-Auswertungen
herausgehalten** ([BestandInsightsScreen](lib/screens/bestand_insights_screen.dart) bleibt auf `currentStock`).
Damit ist ein gelegentlich falscher `fridgeStock` harmlos.

## 4. Datenmodell-Änderung — Kopplung #1 (die 6 Stellen)

Drei neue Felder an [Product](lib/models/product.dart), alle **non-nullable mit Default** (wie `currentStock`),
damit **kein** `clearX`-Flag nötig ist:

| Feld | Typ | Default | Wer pflegt |
|---|---|---|---|
| `inFridge` | `bool` | `false` | Manager (Stammdaten) |
| `fridgeTargetStock` | `int` | `0` | Manager (Soll-Füllstand des Kühlschranks) |
| `fridgeStock` | `int` | `0` | Refill-Reset (alle) + POS (Phase 2) |

Zu ändernde Stellen (Muster wie `currentStock`/`targetStock`):
- Konstruktor + `final`-Felder (~Z.28-31 / 82-92)
- `fromFirestore` camelCase: `parse.toInt(map['fridgeStock']) ?? 0`, `parse.toBool(map['inFridge']) ?? false` (~Z.159-162)
- `fromMap` snake_case: `map['fridge_stock']`, `map['fridge_target_stock']`, `map['in_fridge']` (~Z.189-193)
- `toFirestoreMap` camelCase (~Z.217-221)
- `toMap` snake_case (~Z.244-248)
- `copyWith` (~Z.313-319) — **kein** `clearX`, da non-nullable
- **Convenience-Getter** (analog `needsReorder` Z.98, `isOutOfStock` Z.101): `fridgeStockClamped => fridgeStock < 0 ? 0 : fridgeStock`, `warehouseStock => (currentStock - fridgeStockClamped).clamp(0, currentStock)`, `fridgeDeficit => (fridgeTargetStock - fridgeStockClamped).clamp(0, fridgeTargetStock)`, `fridgeNeedsRefill => inFridge && fridgeDeficit > 0 && warehouseStock > 0`.

**Zusätzlich betroffen** (durch die festgezurrten Entscheidungen): `stock_movement.dart` — neuer Enum-Wert
`StockMovementType.fridgeRefill` (**Kopplung #3**: `.value`/`.label`/`fromValue`-Default + ggf. Rules-`type`-Allowlist),
weil das Nachfüllen als Bewegung protokolliert wird (§12.6); `functions/index.js` — der POS-Decrement wird **mitgebaut**
(Phase 1 + 2 zusammen, §12.3). **Nicht** betroffen: `firestore.indexes.json` (kein neuer `where+orderBy`-Query —
Shortfall wird in-memory aus dem laufenden Produkt-Stream berechnet), neuer `DatabaseService`-Key (Products bereits lokal registriert).

**`firestore.rules`** — **eine** Ergänzung am `products`-Block ([firestore.rules:1007-1012](firestore.rules#L1007-L1012)):
nur der **schmale Mitarbeiter-Schreibpfad fürs Nachfüllen** (siehe §6/§10). Der `products`-Block hat **keine**
Mass-Assignment-Allowlist (`allow create, update: if sameOrg(orgId) && canManageInventory() && …orgId==orgId`) —
die drei neuen Felder werden vom Manager-Pfad **automatisch** zugelassen, ein Allowlist-Eintrag ist gegenstandslos.

## 5. Berechnung „Was fehlt" — pure Core-Funktion

Kanonische Ablage wie [lib/core/reorder_suggestion.dart](lib/core/reorder_suggestion.dart) /
`sales_velocity.dart` / `dead_stock.dart` (rein, deterministisch, kein State/IO/`now()`, offline testbar):

- **`lib/core/fridge_refill_shortfall.dart`** (neu): immutables `FridgeShortfall { product, deficit, warehouseAvailable, severity }` + `List<FridgeShortfall> computeFridgeShortfalls(Iterable<Product> products, {String? siteId})` — filtert `inFridge`, sortiert absteigend nach `fridgeDeficit`, Kriterium aus §3.
- **`InventoryProvider`** ([lib/providers/inventory_provider.dart](lib/providers/inventory_provider.dart)):
  dünne Getter neben `lowStockProducts` (Z.266) bzw. `fridgeRefillOpenCount` (Z.437):
  `List<FridgeShortfall> fridgeShortfalls({String? siteId})` und `int fridgeShortfallCount([String? siteId])`.
  **Reaktiv ohne neuen Stream** — die Produkte kommen aus dem bereits laufenden Abo
  (`_startFirestoreSubscriptions` Z.768-820), Rebuild via `_safeNotify`. Cloud-only-Reads entfallen,
  also **kein** `_usesFirestore`-Guard nötig (rein in-memory).
- **Soll-Vorschlag aus Velocity (§12.4)**: `fridgeTargetStock` wird **vorgeschlagen** (nicht automatisch gesetzt)
  analog `suggestReorderLevels`/[reorder_suggestion.dart](lib/core/reorder_suggestion.dart) — Tagesabsatz des Artikels
  × gewünschte Kühlschrank-Eindeckung (z.B. 1–2 Tage). Manager **übernimmt** den Vorschlag im Produkt-Editor (ein Tap,
  wie der Reorder-Übernehmen-Pfad). **Fallback**: bis ~4 Wochen POS-Daten vorliegen (Velocity `isReliable`), bleibt das
  Soll **manuell** — der Vorschlag erscheint erst, wenn er belastbar ist.

## 6. Nachfüllen — Refill-Reset als Wahrheitsanker

Ein-Tap **„Nachgefüllt"** je Artikel (Primäraktion). Optional Mengen-Variante (Stepper) für Teil-Refill.

- Mutator **`InventoryProvider.refillFridge(Product p, {int? quantity})`**: ohne `quantity` →
  `fridgeStock = fridgeTargetStock` (**Reset = Inventur des Kühlschranks** §12.5, tilgt jeden aufgelaufenen
  Schätz-/Negativ-Drift); mit `quantity` (Stepper-Sekundäraktion) → `fridgeStock = (fridgeStockClamped + quantity).clamp(0, …)`.
- **Schreibt `fridgeStock` (+ `updatedAt`) am Product UND eine `fridgeRefill`-Bewegung** (§12.6): neue, eng gefasste
  Repo-Methode `setFridgeStock(productId, value, {refilledQty})` → (a) `.doc(productId).set({fridgeStock, updatedAt}, merge:true)`
  (**nicht** der volle `saveProduct`-Pfad, der die ganze `toFirestoreMap` schreibt), (b) ein `StockMovement`-Doc
  `type: fridgeRefill, quantityDelta: refilledQty, balanceAfter: fridgeStock, source: 'manual'`. **`currentStock`
  bleibt unberührt** — die `fridgeRefill`-Bewegung ist rein informativ und läuft **nicht** durch die
  `currentStock`-Fortschreibung (Vermeidung der Doppel-Dekrement-Falle; siehe §11).
- **Drei-Speichermodi**: Standard-Muster (`if (_usesFirestore && await _tryFirestore(...)) return;` sonst lokal
  `_upsertLocal` + `_persistProducts` + `_persistMovements` + `_safeNotify`). Funktioniert in **allen** Modi identisch.
- **Protokoll statt Audit** (§12.6): die Rückverfolgbarkeit liefert die `fridgeRefill`-**Bewegung** (im Bestand-/
  Bewegungsverlauf), **kein** `_audit?.call` (konsistent damit, dass die Fridge-Mutatoren nicht ins AuditProvider schreiben).
- **Reconcile mit der manuellen Liste**: beim Nachfüllen eines Artikels die ggf. passende **offene manuelle
  Checklisten-Position** desselben `productId` mit-abhaken (`setFridgeRefillItemDone`,
  [fridge_refill_screen.dart:218](lib/screens/fridge_refill_screen.dart#L218)) — keine Doppelpflege.

## 7. Phasen

> **§12.3: Phase 1 + 2 werden zusammen gebaut & deployt.** Die Trennung bleibt nur **funktional**: Phase 2
> (POS-Decrement) ist erst **wirksam, sobald OktoPOS live + Blaze** ist — bis dahin trägt das manuelle Soll-Ist
> aus Phase 1. Der `saveProduct`-Clobber-Fix (unten) ist damit **Pflicht im ersten Wurf**, nicht später.

### Phase 1 — Manuelles Soll-Ist (alle Speichermodi) · Status: ✅ umgesetzt
Liefert **sofort** die volle UI und Benachrichtigung, unabhängig vom Kassen-Go-Live.
- Modell §4, pure Core §5, Refill-Reset §6, UI §9, Benachrichtigung §8, Rechte §10.
- Ist-Stand bewegt sich über **Refill-Reset + optionale manuelle Mengen-Erfassung**. Ehrliche Grenze:
  ohne POS sinkt `fridgeStock` **nicht von selbst** — der „was fehlt"-Trigger speist sich primär aus der
  Soll-Pflege + der bestehenden manuellen Markierung (Mitarbeiter markiert leeres Getränk → erscheint in der
  Liste, Lager-Verfügbarkeit wird automatisch geprüft).
- **Deploy** (Phase-1-Anteil): `firebase deploy --only firestore:rules` (Mitarbeiter-Refill-Zweig §10). Kein Index.
  Da Phase 2 mitgebaut wird, läuft der **Gesamt-Deploy inkl. `functions` (Blaze)** — siehe §13.

### Phase 2 — Verkaufsgetriebene Automatik (POS-Decrement) · Status: ✅ umgesetzt (Code), wirksam ab OktoPOS-Go-Live + Deploy
Jetzt sinkt der Kühlschrank **automatisch beim Verkauf** — exakt der vom Inhaber beschriebene Ablauf.
- **Andockpunkt** in [functions/index.js](functions/index.js): im `applyOktoposMovementsBatch`-`batch.set`
  (Z.2601-2604) einen **zweiten** `FieldValue.increment(totalDelta)` auf `fridgeStock` ergänzen — **nur** für
  `inFridge==true`-Produkte. Dafür `loadProductLookups` (Z.2472-2495) um `inFridge` erweitern und das Flag
  über `matchProduct`/`pending.push` durchreichen; eine zweite Aggregation `fridgeDeltaByProduct` nur für
  Fridge-Artikel. Vorzeichen ist automatisch korrekt (sales −1 / refund +1, identisch zu `currentStock`).
- **Flooring**: `FieldValue.increment` kann nicht bei 0 clampen → `fridgeStock` darf **roh negativ** werden;
  Flooring **leseseitig** über `fridgeStockClamped` (§4). Akzeptiert, da `fridgeStock` weiche Schätzung ist.
  Der **Refill-Reset** (§6) tilgt den Drift bei jedem Nachfüllzyklus.
- **Clobber-Schutz (Jury-Hauptrisiko) — STRUKTURELL, nicht per Disziplin**: `saveProduct` schreibt die **volle**
  `toFirestoreMap` mit `merge:true` ([firestore_inventory_repository.dart:218-221](lib/services/repositories/firestore_inventory_repository.dart#L218-L221)).
  Da `fridgeStock` ein **non-nullable int** ist, emittiert `toFirestoreMap` es **immer** — bei Edit mit dem **stale**
  Stream-Wert, bei Neuanlage mit `0`. Beides racet last-writer-wins gegen den frischen POS-`FieldValue.increment` und
  überschreibt ihn. „Editor bearbeitet `fridgeStock` nie" reicht am Wire-Level **nicht** (geschrieben wird trotzdem).
  **Fix**: `fridgeStock` **explizit aus dem `saveProduct`-Merge entfernen**
  (`final data = {...toFirestoreMap()}..remove('fridgeStock');`) **und** denselben Ausschluss im lokalen
  `_upsertLocal`-Pfad (inventory_provider.dart). Damit ist `fridgeStock` **allein** durch `setFridgeStock` (Refill)
  + POS-Increment autoritativ — bewusst **anders** als das akzeptierte `currentStock`-Editor-Muster (das ist nicht POS-increment-geführt).
- **Deploy**: `firebase deploy --only firestore:rules,functions` (Blaze).

### Phase 3 — Echter Handy-Push · ausgelagert an [push-benachrichtigungen-plan.md](push-benachrichtigungen-plan.md) (M3)
Damit die Erinnerung „kurz vor Ladenschluss" auch **bei geschlossener App** zustellbar ist. **Entschieden 30.06.2026 (Trennung Signal ↔ Zustellung):** Dieser Plan **besitzt das Soll-Ist-Signal** (`fridgeStock ⊆ currentStock` am Product, §3–§5 = „was fehlt"); der **echte FCM-Push gehört dem [Push-Benachrichtigungen-Plan](push-benachrichtigungen-plan.md)**, der die Flanke „Standort hat offene Defizite" (`products` onUpdate, gebündelt je Standort) als Trigger konsumiert und nach `/warenwirtschaft?tab=kuehl` deeplinkt. Hier ist also **nur das Signal** zu liefern; Token-Registrierung, FCM-Versand, Channels und Zustellung baut der Push-Plan. Der Client-Trigger (§8) deckt „App ist offen" weiterhin vollständig ab.

## 8. Benachrichtigung & Trigger (kein FCM)

Spiegelt das erprobte, Spark-frugale Muster (`CustomerOrderWarningBanner` / `ordersDueSoonNotPrepared`)
1:1 — **kein** neuer Banner-Widget-Typ, **keine** Persistenz, **kein** Server-Cron.

- **(a) Home-Aktionskarte**: in [DashboardActionItemsCard](lib/widgets/dashboard_action_items_card.dart)
  (build ab Z.30) eine dritte `_ActionItem`-Zeile analog zum `lowStock`-Block (Z.70-79):
  `Icons.kitchen_outlined`, `appColors.warning`, Label „$n Getränke in den Kühlschrank nachfüllen",
  `onTap` → `context.push('${AppRoutes.inventory}?tab=kuehl')`. Erscheint automatisch an den **vier** Mount-Punkten
  der Karte (V1: home_screen_tabs.dart:73 + :956 · V2: home_dashboards_v2.dart:71 + :651). Gating: `profile.canViewInventory`.
  **Achtung Deeplink**: der `?tab=`-Parser liegt im **Router** ([app_router.dart:138](lib/routing/app_router.dart#L138)),
  **nicht** im InventoryScreen, und kennt heute nur `korb` (jeder andere Wert → Tab 0). Für `?tab=kuehl` dort einen
  Zweig + Konstante `InventoryScreen.fridgeTabIndex = 1` (analog `cartTabIndex`) ergänzen — sonst zielt die Karte ins Leere.
- **(b) Posteingang**: in `_buildItems` von [notification_screen.dart](lib/screens/notification_screen.dart)
  (neben dem lowStock-Block Z.886-901) ein `_InboxItem(kind: update, section: todo, badge: 'Nachfüllen',
  color: warning, icon: kitchen_outlined)`. Section **`todo`** (sofort handelbar), nicht `history`.
- **(c) Tab-Badge**: das Kühlschrank-`badgeCount` ([inventory_screen.dart:297-299](lib/screens/inventory_screen.dart#L297-L299))
  von `fridgeRefillOpenCount` auf `max(manuelle offene, fridgeShortfallCount)` heben — **im `effectiveSiteId != null`-Zweig**
  und `fridgeShortfallCount` mit demselben `effectiveSiteId`-Filter (ohne eindeutigen Laden zeigt der Badge bewusst 0;
  sonst bricht bei zwei Läden die „kein Summen-Badge"-Konvention).
- **Trigger „Tagesende vor Ladenschluss"**: client-seitiger Helfer `_isNearClosing(site, {leadMinutes=90})` —
  Ladenschluss aus [SiteDefinition.weekdayHours](lib/models/site_definition.dart) ableiten:
  `closeMin = max(endMinute aller heutigen TimeWindows)` ([site_schedule.dart:19](lib/models/site_schedule.dart#L19)),
  Fenster `now ∈ [closeMin − leadMinutes, closeMin)`. **`now` als Parameter injizieren** (Wall-Clock-Test-Footgun,
  CLAUDE.md). **Fallback** bei Läden ohne hinterlegte Öffnungszeiten (häufig leer): ganztägig warnen, sobald Defizit > 0.
  **`InventoryProvider` hält KEINE `sites`** → die `SiteDefinition` aus `context.watch<TeamProvider>().sites` holen und
  in `_isNearClosing(site, …)` reinreichen (Helfer im Widget-Layer, nicht im Provider).
- **Trigger „viel verkauft"**: Phase 1 = Proxy (offene Defizite + Lager-Verfügbarkeit). Phase 2 = echt
  (`fridgeStock` unter Schwelle, z.B. `< 50 %` des Soll, durch den POS-Decrement).
- **Standort-Skopierung**: bei zwei Läden muss die Warnung pro Laden gelten (Laden A nach Schluss soll keinen
  Mitarbeiter in Laden B nerven). Standort des eingeloggten Mitarbeiters über `employeeSiteAssignments`/Schicht
  ableiten — **offene Entscheidung** (§12).

## 9. UX (Material 3, `appColors`-Tokens, a11y kritisch)

Den **bestehenden Kühlschrank-Tab erweitern**, keinen neuen Tab/Screen
([FridgeRefillTab](lib/screens/fridge_refill_screen.dart#L24)):

- Oben angeheftete Sektion **„Fehlt im Kühlschrank (n)"** über der manuellen Liste (`_SectionHeader` Z.165 reuse).
- **`_FridgeShortfallTile`** je Defizit-Artikel (Vorlage `_FridgeItemTile` Z.192): Status-Icon **+ Text-Label**
  (Farbe **nie** allein — WCAG kritisch) · Name (`titleMedium`, w600) · Mengen-Subtitle mit
  `FontFeature.tabularFigures()`: „Kühlschrank 8/24 · Lager 30" · `FilledButton.tonal('Nachgefüllt')` (≥48 dp) ·
  Überlauf-`IconButton` für Teilmenge/Stepper (`_FridgeQtyStepper` Z.277 reuse).
- **Status-Stufen** (Icon + Label + `appColors`): leer/0 → `error_outline` „leer"; Defizit & genug Lager →
  `warning_amber_outlined` „nachfüllen"; Lager reicht nicht fürs volle Soll → `inventory_2_outlined` „Lager knapp".
- **`Semantics`** je Zeile: „{Name}, Kühlschrank {ist} von {soll}, Lager {lager}, {status}"; Aktion als Button-Semantics.
- **Zustände**: leere Sektion → Header weglassen; Gesamt-Empty → `EmptyState` „Alles aufgefüllt"
  (`check_circle_outline`, `appColors.success`); Loading → Skeleton; Error → das vorhandene Empty-/Inline-Muster der
  `FridgeRefillTab` (fridge_refill_screen.dart:42/88). (Das `_ErrorBanner` liegt **file-private** in
  inventory_screen.dart:924, ist also **nicht** importierbar — ggf. nach `lib/widgets/` heben.)
- **Dedupe**: ein Getränk, das manuell **und** automatisch defizitär ist, nur **einmal** zeigen (Match `productId`).
- **Home** behält die bestehende Schnellaktion „Kühlschrank nachfüllen"
  ([home_screen.dart:709](lib/screens/home_screen.dart#L709)) + die neue Aktionskarte (§8a).

## 10. Rechte

- **`inFridge` + `fridgeTargetStock` (Soll) = Stammdaten → nur Manager** (`canManageInventory` = Admin ||
  Schichtleiter). Läuft über den bestehenden `products`-Block ([firestore.rules:1007-1012](firestore.rules#L1007-L1012)),
  Manager-gegated — **keine** Allowlist am `products`-Block (§4), die neuen Felder sind automatisch zugelassen.
- **Nachfüllen (`fridgeStock`-Reset) = ALLE aktiven Mitarbeiter** (wie Bestellkorb / manuelle Checkliste —
  der Inhaber will „die Mitarbeiter können nachfüllen"). **Sicherheits-Falle**: das ist ein Write auf einem
  Product, dessen Rule sonst Manager-only ist. **Nicht** `canManageInventory` für alle öffnen (würde Preis-/
  Lager-Writes leaken). Stattdessen ein **eng gefasster zusätzlicher `allow update`-Zweig** am `products`-Block
  ([firestore.rules:1007-1012](firestore.rules#L1007-L1012)):
  ```
  allow update: if sameOrg(orgId)
      && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['fridgeStock','updatedAt']);
  ```
  `sameOrg(orgId)` schließt `isActiveUser()` (firestore.rules:72) bereits ein — **kein** separater Aktiv-Check
  (⚠️ `isActiveMember()` existiert **nicht**; der reale Helfer heißt `isActiveUser()`). ⚠️ Das
  `diff().affectedKeys().hasOnly()`-Muster ist im Projekt **bisher nirgends** verwendet (alle bestehenden Allowlists
  nutzen `keys().hasOnly()` auf `create`) — hier bewusst **neu** und **vor Deploy im Firestore-Emulator** gegen den
  echten `setFridgeStock`-Write zu verifizieren (Merge muss **exakt** `{fridgeStock, updatedAt}` treffen;
  `serverTimestamp` taucht in `affectedKeys` auf). Lässt jedes aktive Mitglied **ausschließlich** `fridgeStock`
  ändern. Alternative: eng gescopte Callable `confirmFridgeRefill(productId)` (Admin SDK).
- Die UI-Sichtbarkeit des Kühlschrank-Tabs hängt heute an `canViewInventory` (= `isActive`) — das **ist**
  „alle aktiven Mitarbeiter", passt also bereits.
- Client- und Server-Recht **synchron halten** (CLAUDE.md Kopplung #4/#8).

## 11. Kritische Kopplungen & Risiken

- **Clobber durch `saveProduct`** (Phase 2, **wire-level Bug, kein Disziplin-Problem**): voller `toFirestoreMap`-Merge
  schreibt `fridgeStock` **immer** (stale beim Edit, `0` beim Neuanlegen) → überschreibt den POS-Increment.
  **Strukturell** lösen: `fridgeStock` aus dem `saveProduct`-Merge **und** aus `_upsertLocal` (local/hybrid) entfernen — §7.
- **Negativer `fridgeStock`** (Phase 2): `FieldValue.increment` floored nicht → **clamp-on-read in JEDER** Lese-/UI-/
  Core-Stelle über `fridgeStockClamped` (nie roh in UI/Auswertung), aus Warenwert/Schwund heraushalten; Refill-Reset tilgt den Drift.
- **`diff()/affectedKeys()`-Refill-Rule ist projektweit unerprobt** (§10) → vor Deploy im Firestore-Emulator gegen den
  echten `setFridgeStock`-Write verifizieren (Merge muss exakt `{fridgeStock, updatedAt}` treffen).
- **Doppel-Dekrement & Bewegungs-Typ-Isolation**: Nachfüllen ändert **kein** `currentStock` (reine Umlagerung).
  Die `fridgeRefill`-Bewegung ist **rein informativ** — sie darf **nicht** in die `currentStock`-Fortschreibung,
  nicht in Schwund/Warenwert ([BestandInsightsScreen](lib/screens/bestand_insights_screen.dart)) und nicht in die
  POS-Velocity (`sales_velocity.dart` zählt nur `issue`) einfließen. Jeder Movement-Konsument muss `fridgeRefill` ignorieren.
- **OktoPOS-Abhängigkeit**: die echte Verkaufs-Automatik (Phase 2) ist tot, bis der Kassen-Pull live ist (Blaze).
  Phase 1 deshalb so geschnitten, dass sie **ohne** OktoPOS vollen Nutzen liefert.
- **Stammdaten-Pflegelast**: `inFridge` muss je Kühlschrank-Artikel gesetzt sein (Default `false`), sonst schlägt
  die Liste nichts vor. `fridgeTargetStock` kommt als **Velocity-Vorschlag** (§12.4), den der Manager übernimmt —
  **bis ~4 Wochen POS-Daten** vorliegen, ist es manuell zu setzen, sonst bleibt das Soll 0 (kein Defizit, leere Liste).
- **`weekdayHours` oft leer** → Ladenschluss-Trigger greift nicht; Fallback definieren (§8).
- **Hybrid spiegelt Stammdaten nicht lokal** → keine Logik auf einen lokalen Product-Spiegel im hybrid-Modus stützen
  (Reads aus Firestore-Offline-Cache). `fridgeStock`-Reset funktioniert in allen Modi über den Standard-Mutator-Pfad.
- **Last-writer-wins** auf den geteilten Listen (zwei Mitarbeiter gleichzeitig) — für zwei kleine Läden bewusst akzeptiert.
- **Kein echter Push hier** (§12.8): In-App-Surfacing erscheint beim nächsten App-Öffnen; der echte Handy-Push
  (auch bei geschlossener App) kommt aus [push-benachrichtigungen-plan.md](push-benachrichtigungen-plan.md) — dieser Plan liefert nur das Signal.

## 12. Festgezurrte Entscheidungen (Stand 2026-06-30)

Alle acht Punkte sind entschieden — der Plan ist build-ready.

| # | Entscheidung | Festgelegt | Folge im Plan |
|---|---|---|---|
| 1 | Kühlschrank-Ist-Stand | **Persistiert** am Product (`fridgeStock`) | §3–§6 wie beschrieben |
| 2 | Refill-Recht | **Alle aktiven Mitarbeiter** | schmaler Rules-Zweig §10 + Emulator-Test (§13.6) |
| 3 | Phasen-Schnitt | **Phase 1 + 2 zusammen** bauen | Phase-2-POS-Decrement auf dem kritischen Pfad; wirksam erst ab OktoPOS-Go-Live; `saveProduct`-Clobber-Fix (§7) damit Pflicht |
| 4 | `fridgeTargetStock` initial | **Velocity-abgeleiteter Vorschlag** (analog `suggestReorderLevels`/[reorder_suggestion.dart](lib/core/reorder_suggestion.dart)) | neuer Vorschlags-Pfad §5/§13; Manager übernimmt; **manueller Fallback**, bis genug POS-Daten (~4 Wochen) da sind |
| 5 | Ein-Tap „Nachgefüllt" | **fix auf Soll** (`fridgeStock = fridgeTargetStock`) | Stepper bleibt Sekundär-Aktion (§6/§9) |
| 6 | Protokollierung | **Als Bewegung** (`StockMovementType.fridgeRefill`) | **Kopplung #3**; Movement ändert `currentStock` **nicht** (§6/§11) |
| 7 | Standort der Warnung | **Nur Laden des Mitarbeiters** (Schicht/`employeeSiteAssignments`) | Standort-Auflösung in §8 |
| 8 | Echter FCM-Push | **Über [push-benachrichtigungen-plan.md](push-benachrichtigungen-plan.md)** | dieser Plan liefert nur das Soll-Ist-Signal (§7 Phase 3) |

## 13. Reihenfolge, Aufwand, Tests, Deploy

**Reihenfolge (Phase 1 + 2 zusammen gebaut, §12.3):**
1. Modell §4: 3 Product-Felder + Getter — **S** · `toMap`/`fromMap` (snake_case) **nicht vergessen** (sonst verliert der local/hybrid-Spiegel die Felder)
2. `StockMovementType.fridgeRefill` (Kopplung #3: `.value`/`.label`/`fromValue`-Default) §4/§12.6 — **S**
3. **`saveProduct`/`_upsertLocal` härten**: `fridgeStock` aus dem Merge entfernen (§7-Clobber) — **S**
4. Produkt-Editor: `inFridge`-Schalter + `fridgeTargetStock`-Feld + **Velocity-Soll-Vorschlag „übernehmen"** (§12.4, analog Reorder-Übernehmen) — **S–M**
5. pure Core `fridge_refill_shortfall.dart` + Provider-Getter §5 — **S**
6. `refillFridge` + `setFridgeStock` (feld-gescopter Merge **+ `fridgeRefill`-Bewegung**) §6 — **M**
7. `firestore.rules`: Mitarbeiter-Refill-Zweig §10 (`isActiveUser()`, `diff().affectedKeys()`) — **erst im Emulator gegen `setFridgeStock` verifizieren** — **S**
8. UX-Sektion „Fehlt im Kühlschrank" + Refill-Tile §9 — **M**
9. Benachrichtigung: Aktionskarte + Inbox + Tab-Badge (§8c im non-null-Zweig) + Router-`?tab=kuehl`-Zweig + Near-Closing (sites aus TeamProvider, **nur Laden des Mitarbeiters** §12.7) §8 — **M**
10. **Phase-2-POS-Decrement** (functions/index.js): `loadProductLookups` um `inFridge` + zweite Aggregation `fridgeDeltaByProduct` (nur `inFridge`) + zweiter `fridgeStock`-Increment **innerhalb** `applyOktoposMovementsBatch` (dryRun-sicher) §7 — **M**

**Definition of Done** (CLAUDE.md): `flutter analyze` sauber · `flutter test` grün · Offline-Lauf
`flutter run --dart-define=APP_DISABLE_AUTH=true` ohne rote Seiten.
**Neue Tests**: `test/fridge_refill_shortfall_test.dart` (pure Core, Muster `reorder_suggestion_test`) ·
Provider-Test (`refillFridge` setzt `fridgeStock=Soll` in allen Modi; `FakeFirestore` gibt `double` zurück →
**keine int-Gleichheit** asserten) · Widget-Test (Shortfall-Tile + Aktionskarte zeigt/blendet korrekt) ·
Near-Closing mit injiziertem `now` (kein Wall-Clock-Assert).
**Deploy** (gebündelt, §12.3): `firebase deploy --only firestore:rules,functions` — **Blaze** (wegen Phase-2-Functions/OktoPOS).
Rules **erst nach** Emulator-Verifikation des Refill-Zweigs (§13.7) deployen.
**Neue Tests zusätzlich**: `fridgeRefill`-Bewegung wird geschrieben, `currentStock` bleibt unverändert; Velocity-Soll-Vorschlag (pure, analog `reorder_suggestion_test`).

## 14. Umsetzungs-Stand (2026-06-30)

**Gebaut & getestet** — 1209 Tests grün, `flutter analyze` sauber, `node --check` ok:
- **Modell**: [product.dart](lib/models/product.dart) (`inFridge`/`fridgeTargetStock`/`fridgeStock` + Getter `fridgeStockClamped`/`warehouseStock`/`fridgeDeficit`/`fridgeNeedsRefill`); [stock_movement.dart](lib/models/stock_movement.dart) (`StockMovementType.fridgeRefill`).
- **Core**: [fridge_refill_shortfall.dart](lib/core/fridge_refill_shortfall.dart) (`computeFridgeShortfalls`, `suggestFridgeTarget`, `isNearClosing`).
- **Provider** [inventory_provider.dart](lib/providers/inventory_provider.dart): `fridgeShortfalls`/`fridgeShortfallCount`, `refillFridge` + `_applyLocalFridgeRefill`, `suggestFridgeTargets`/`suggestFridgeTargetForProduct`; `saveProduct` clobber-gehärtet.
- **Repo**: `setFridgeStock` (Batch, `currentStock` unberührt, schreibt `fridgeRefill`-Bewegung) in Interface + Firestore-Impl + Test-Fake.
- **UI**: Produkt-Editor (inFridge-Schalter + Soll + Velocity-Vorschlag), „Fehlt im Kühlschrank"-Sektion + Refill-Tile ([fridge_refill_screen.dart](lib/screens/fridge_refill_screen.dart)), Home-Aktionskarte + Near-Closing ([dashboard_action_items_card.dart](lib/widgets/dashboard_action_items_card.dart)), Posteingang-Item ([notification_screen.dart](lib/screens/notification_screen.dart)), Tab-Badge, Router-Deeplink `?tab=kuehl` ([app_router.dart](lib/routing/app_router.dart) + `InventoryScreen.fridgeTabIndex`).
- **Rules**: [firestore.rules](firestore.rules) Mitarbeiter-Refill-Zweig (`diff().affectedKeys().hasOnly(['fridgeStock','updatedAt'])`).
- **Functions** [functions/index.js](functions/index.js): `loadProductLookups` liest `inFridge`, `applyOktoposMovementsBatch` dekrementiert `fridgeStock` der Kühlschrank-Artikel (zweite Aggregation `fridgeDeltaByProduct`, dryRun-sicher).

**Offen (Betrieb/extern, kein Code mehr):**
1. **Emulator-Verifikation** des `diff/affectedKeys`-Refill-Zweigs gegen den echten `setFridgeStock`-Write.
2. **Deploy**: `firebase deploy --only firestore:rules,functions` (Blaze).
3. **Phase 2 wirksam** erst, wenn die OktoPOS-Anbindung scharf ist (Token/Secret/Scheduler) und Verkäufe pullt.
4. **Stammdaten**: je Kühlschrank-Artikel `inFridge` + Soll pflegen (Velocity-Vorschlag greift erst nach ~4 Wochen POS-Daten).

**Bewusste Scope-Grenze:** Die Home-Aktionskarte zählt Lücken **org-weit** (wie die bestehende Low-Stock-/Bestell-Warnung); der **Tab-Badge** ist standortgenau. Strikt per-Mitarbeiter-Standort-Scoping der Home-Karte (§12.7) ist ein kleiner Folgeschritt (Auflösung des Mitarbeiter-Standorts nötig), bewusst zurückgestellt.
