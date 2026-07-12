# Sicherheits- & Bug-Audit + Behebungsplan (Juli 2026)

**Erstellt:** 2026-07-11
**Scope-Auftrag:** Gesamte Software, Schwerpunkt **Warenwirtschaft**, **Login/Account-Anlage**, **OktoPOS-API-Anbindung**.
**Status:** Analyse abgeschlossen (mit Einschränkung, s. Methodik). Behebung offen.

---

## 0. Methodik & Vertrauensgrad (WICHTIG zu lesen)

Das Audit lief als Multi-Agent-Workflow: 14–15 parallele Prüfer je Bereich, danach adversariale Verifikation je Befund (ein Skeptiker versucht jeden Befund zu widerlegen), danach Synthese.

**Der Lauf ist mitten in der Verifikationsphase am Session-Token-Limit hart abgebrochen.** Folgen:
- Die automatische Synthese meldete fälschlich „0 Befunde / alles widerlegt". Das ist **falsch** — die Befunde wurden nicht widerlegt, sondern ihre Verifizierer-Agenten stürzten ab, und die Pipeline verwarf Befunde ohne Verdikt zu `null`.
- Die echten Befunde wurden aus dem Workflow-Journal wiederhergestellt: **15 Finder-Befunde aus 6 abgeschlossenen Dimensionen** + **2 unabhängig CONFIRMED-Verdikte**.
- Zusätzlich wurden die tragenden Befunde **manuell am Code gegengeprüft** (diese Person: eigene Lektüre von firestore.rules, functions/index.js, account_deletion.js, inventory_provider.dart, den Warenwirtschaft-Models).

**Vertrauensgrad je Befund** ist unten markiert:
- `[CONFIRMED]` = durch Verifizierer-Agent **und** manuelle Code-Lektüre bestätigt.
- `[BELEGT]` = manuell am Code gegengeprüft, Zitat stimmt.
- `[KONDITIONAL]` = realer Defekt, aber abhängig von externem Verhalten (z. B. OktoPOS-API-Feldnamen, die der Code selbst als „gegen Swagger zu verifizieren" markiert). OktoPOS ist noch nicht deployt → Pre-Production-Härtung, kein Live-Vorfall.

**Nicht abgedeckte Dimensionen (Absturz vor Ergebnis) → Rest-Risiko, Re-Run nötig (s. §5):**
Warenwirtschaft-Provider (tief), Warenwirtschaft-Models (nur stichprobenhaft, unauffällig), Cloud-Functions allgemein (übrige Callables), Dart-Korrektheit quer, Auth-Service tief, Compliance-Spiegel-Drift, neue Signage-Module. **Account-Löschung** wurde manuell geprüft und ist solide.

---

## 1. Kritisch (Multi-Tenancy / Secret-Leck) — SOFORT

> **Nachtrag 11.07.:** Ein **dritter kritischer Fund K3** (Cross-Tenant-Schicht-Schreiben) kam im Re-Run dazu — siehe §9. K3 ist **breiter angreifbar** als K1/K2 (jeder Planer/Teamlead, nicht nur Admin) und liegt auf dem „validierten" Callable-Pfad.

### K1 — `config/{configId}`-Write nicht org-gebunden `[CONFIRMED]`
**Datei:** `firestore.rules:641`
```
match /config/{configId} {
  allow read: if sameOrg(orgId);
  allow write: if isAdmin();          // <-- KEIN sameOrg(orgId)
}
```
`isAdmin()` (`firestore.rules:76-78`) prüft **nur die eigene Rolle** des Aufrufers aus dessen `users`-Doc, nicht die `{orgId}` im Pfad. Alle anderen admin-verwalteten Collections nutzen `isAdmin() && sameOrg(orgId) && ...orgId == orgId` (Referenz `firestore.rules:893-895`). Der Config-Block ist der **einzige Ausreißer** und trägt kein `orgId`-Feld für einen Body-Check.

**Angriff:** Admin von Org A schreibt `organizations/<orgB>/config/oktoposSync` (baseUrl→Angreifer-URL, `enabled:true`), `.../config/appFlags` (hohe Mindest-Build-Nr → alle Clients von Org B im ForceUpdate-Gate = Aussperr-DoS) oder `.../config/orgSettings`/`thirdParty` fremder Orgs. Koppelt mit K2 zur Key-Exfiltration.

**Fix:** `allow write: if isAdmin() && sameOrg(orgId);` — bricht keinen legitimen Eigen-Org-Write (FeatureFlagProvider/saveOrgSettings/saveOktoposConfig schreiben immer `profile.orgId == currentOrgId()`).
**Aufwand:** S. **Deploy:** `firestore:rules` — die Rules sind produktiv deployt, das ist ein **Live-Loch**.

### K2 — OktoPOS `baseUrl` ohne Host-Allowlist → Secret-Key-Exfiltration (SSRF) `[CONFIRMED]`
**Dateien:** `functions/index.js:4697` & `:5695` (nur `https://`-Präfix-Check), `:5309`/`:5318` (`X-API-KEY` an `${baseUrl}`), Client-Seam `lib/services/firestore_service.dart:187`, UI-Check nur clientseitig `lib/screens/inventory_screen.dart:3049`.

`baseUrl` kommt aus dem admin-schreibbaren `config/oktoposSync`. Einzige Server-Prüfung ist das `https://`-Präfix — **keine Host-/Domain-/IP-Allowlist**. `oktoposFetch` hängt das Secret `OKTOPOS_API_KEYS` als `X-API-KEY`-Header an **jeden** so konfigurierten Host.

**Angriff:** Admin (oder übernommene Admin-Session) setzt `baseUrl='https://attacker.example'`, löst „Verkäufe übernehmen" aus → Server sendet `X-API-KEY: <Secret>` an den Angreifer. Der Key soll laut Design **nie** in Admin-Reichweite gelangen. Ist das Secret ein Single-String (nicht die siteId-JSON-Map), ist es **mandantenübergreifend** → alle Orgs kompromittiert. Über K1 auch cross-tenant auslösbar (nächtlicher Sync gegen vergiftete fremde Config).

**Fix:** Server-seitige Host-Allowlist in `runOktoposSync`/`resolveOktoposBaseUrl`: `new URL(baseUrl).hostname` exakt gegen erlaubte OktoPOS-Domains (festes Suffix / zweites Secret) prüfen, sonst `failed-precondition`. Zusätzlich private/link-local-IPs blocken. Optional baseUrl komplett aus client-schreibbarer Config in eine Server-Konstante ziehen.
**Aufwand:** M. **Deploy:** `functions` — OktoPOS ist noch **nicht** deployt → vor dem OktoPOS-Cutover fixen, kein Live-Loch.

---

## 2. Hoch (Privilege-Escalation / Datenintegrität)

### H1 — users-create: permissions-Kurzschluss `[BELEGT]`
**Datei:** `firestore.rules:531-537`
```
&& ( !('permissions' in ownInvite().data)
     || permissionsEquivalent(request.resource.data, ownInvite().data) );
```
Fehlt am Invite das `permissions`-Feld, ist die Klausel **immer wahr** → der selbst-provisionierende Nutzer darf **beliebige** permissions in sein `users`-Doc schreiben. Manuell/legacy angelegte Invites **ohne** permissions sind real und dokumentiert (CLAUDE.md/docs: Invite mit nur `orgId,email,emailLower,role,isActive`); `userInvites`-create (`:598`) verlangt kein permissions-Feld.

**Folge:** `employee` setzt sich `canEditSchedule=true` → `canManageShifts()=true` → Schichten/Warenwirtschaft/Kontakte verwalten **und** via users-read-Rule (`:516-520`) fremde `users`-Docs inkl. `hourlyRate` lesen.
**Fix:** Oder-Klausel entfernen, permissions **immer** prüfen (`permissionsEquivalent` fällt über `permissionValueFromData` bereits auf Rollen-Defaults zurück, funktioniert auch für permission-lose Invites).
**Aufwand:** S. **Deploy:** `firestore:rules` (Live).

### H2 — users-create: Lohnfelder nicht ans Invite gepinnt `[BELEGT]`
**Datei:** `firestore.rules:522-537` (create-Block). Pinnt role/orgId/isActive/permissions, aber **nicht** `settings.hourlyRate`/`vacationDays`. Der update-Pfad hat dafür `settingsPayrollFieldsUnchanged` (`:557-560`) — dem create fehlt es.

**Folge:** Eingeladener Mitarbeiter provisioniert per Direct-Write `users/{uid}` mit `settings.hourlyRate=99.0` → überhöhte Lohnabrechnung, bis ein Admin es bemerkt.
**Fix:** Im create-Block `&& settingsPayrollFieldsUnchanged(request.resource.data, ownInvite().data)` (Invite trägt settings via `UserInvite.toFirestoreMap`) — oder settings-Lohnfelder gegen `ownInvite().data.settings` prüfen.
**Aufwand:** S. **Deploy:** `firestore:rules` (Live).

### H3 — OktoPOS: siteId nicht gegen Org validiert + `*`/default-Key-Fallback `[BELEGT]`
**Datei:** `functions/index.js:4678`, `:4660-4688` (`resolveOktoposApiKey`)
```
const key = parsed?.[siteId] || parsed?.["*"] || parsed?.default;
```
`siteId` kommt ungeprüft aus `request.data`; `assertSameOrg` prüft nur `orgId`. Es wird nie geprüft, dass `siteId` ein Standort der Org des Callers ist. Das Secret ist eine mandantenübergreifende JSON-Map → Org A kann mit einer fremden `siteId` den Key von Org B auflösen. Der `*`/`default`-Fallback liefert jeder beliebigen `siteId` einen Key.
**Fix:** `siteId` vor Key-Auflösung gegen `loadOktoposConfig(orgId).sites[siteId]` validieren; Secret pro `orgId` partitionieren (`{"<orgId>":{"<siteId>":"<key>"}}`); `*`/default-Fallback entfernen oder auf Single-Tenant beschränken.
**Aufwand:** M. **Deploy:** `functions` (OktoPOS undeployt).

### H4 — OktoPOS: Belegzeilen kollabieren bei fehlendem `item.id` `[KONDITIONAL]`
**Datei:** `functions/index.js:4884-4885`, `buildOktoposMovementId` `:5456`
```
movementId: buildOktoposMovementId(cashRegisterId, ref, asInteger(item?.id, 0)),
```
Fehlt `item.id` (Feldname laut Code-Kommentar unverifiziert), liefert `asInteger` für **jede** Zeile `0` → identische `movementId` → der Dedup in `applyOktoposMovementsBatch` (`:5049-5053`, keep-first) kollabiert alle Zeilen eines Belegs auf **eine** Bewegung → nur das erste Produkt wird abgebucht, Bestand aller weiteren Produkte bleibt zu hoch.
**Fix:** Positions-Index (Schleifenindex) oder `productId` + laufenden Zähler als stabilen Diskriminator in die `movementId` aufnehmen; bei fehlendem `item.id` Warn-Log.
**Aufwand:** S. **Deploy:** `functions` (OktoPOS undeployt).

### H5 — OktoPOS: Pagination stoppt bei fehlendem `wrapper.lastPage` `[KONDITIONAL]`
**Datei:** `functions/index.js:4773`, Schleife `:4763/:4917`
```
pageLastPage = Math.max(pageLastPage, asInteger(wrapper.lastPage, page));
```
Fehlt `lastPage`, fällt `asInteger` auf `page` zurück → `lastPage == page` → Schleife bricht nach **einer** Seite ab (ohne Log). Bei `size 50` werden max. 50 Transaktionen/Lauf verarbeitet, der Rest des Tages dauerhaft ignoriert (Cursor rückt trotzdem vor).
**Fix:** Ohne belastbare `lastPage`/`hasMore`-Angabe weiterblättern, solange eine **volle** Seite (`== size`) kam; Warn-Log `pagination_field_missing`.
**Aufwand:** S. **Deploy:** `functions` (OktoPOS undeployt).

---

## 3. Mittel

### M1 — `organizations/{orgId}` create/update nicht org-gebunden `[BELEGT]`
**Datei:** `firestore.rules:633` — `allow create, update: if isAdmin() && request.resource.data.name is string;` (kein `sameOrg`). Admin von Org A kann fremdes Org-Doc umbenennen / mit Fremdfeldern verunreinigen.
**Fix:** `... if isAdmin() && sameOrg(orgId) && request.resource.data.name is string;` (Bootstrap `_ensureOrganization` schreibt immer die eigene orgId → bleibt erlaubt).
**Aufwand:** S. **Deploy:** `firestore:rules` (Live).

### M2 — `userInvites` get/list nicht org-skopiert `[BELEGT]`
**Datei:** `firestore.rules:589-596`. `allow list: if isAdmin();` + Admin-Zweig von `get` ohne `sameOrg`. Admin von Org A kann **alle** Einladungen aller Orgs listen/lesen (E-Mails=PII, Rollen, orgId).
**Fix:** get-Admin-Zweig `&& dataOrgId(resource.data) == currentOrgId()`; list org-gepinnt erzwingen (Client-Query `where('orgId','==',currentOrgId)` + Rule anpassen).
**Aufwand:** S–M (Client-Query anpassen). **Deploy:** `firestore:rules` (Live).

### M3 — OktoPOS: `OKTOPOS_MAX_PAGES`(200)-Cap schneidet still ab `[BELEGT]`
**Datei:** `functions/index.js:4917`. Bei `lastPage > 200` werden Restseiten kommentarlos verworfen; danach rückt der Cursor auf `maxBusinessDay` der nur teilweise gelesenen Transaktionen → bei absteigender Sortierung entsteht eine dauerhafte Lücke.
**Fix:** Nach der Schleife prüfen, ob das Cap griff → Warn/Error-Log (`truncated:true`); Cursor **nicht** über den zuletzt vollständig verarbeiteten Tag hinaus fortschreiben.
**Aufwand:** S. **Deploy:** `functions` (OktoPOS undeployt).

### M4 — OktoPOS: `cashRegisterId`-Wechsel → Doppelbuchung `[BELEGT]`
**Datei:** `functions/index.js:4884` / `buildOktoposMovementId :5456` / `buildOktoposReceiptId :5470`. Idempotenz-Schlüssel enthält den Scope-Präfix `cr` (=cashRegisterId oder `all`). Wird die Kassen-Nr. nachträglich gesetzt/geändert (z. B. beim Hinzufügen eines 2. Standorts, wo sie ab `:4718` Pflicht wird), bekommt dieselbe Transaktion eine neue Doc-ID → Re-Pull im 3-Tage-Lookback bucht Bestand ein zweites Mal ab.
**Fix:** Idempotenz-Schlüssel unabhängig von der (änderbaren) `cashRegisterId` machen (Scope aus stabiler `siteId` ableiten, Belegnr.+Rohhash als Diskriminator).
**Aufwand:** M. **Deploy:** `functions` (OktoPOS undeployt).

### M5 — OktoPOS-Stats: `cogs` zählt Erstattungen falschherum `[KONDITIONAL]`
**Datei:** `functions/oktopos_stats.js:142` — `a.cogs += qty * ekNetto` mit `qty = line.quantity || 0` (Roh-Menge, `index.js:4820` unsigniert). Für Refund-Belege (`isRevenue`, `type=refund`) steigt `cogs`, obwohl retournierte Ware den Tages-Wareneinsatz **senken** müsste — sofern OktoPOS die Erstattungsmenge nicht negativ liefert. `grossCents` wird beim Refund gegenläufig, `cogs` gleichläufig → verfälschter Rohertrag.
**Fix:** `cogs`-Richtung an den Beleg-`type` koppeln (bei `refund` subtrahieren), konsistent zur Bestandsbewegung; im Dart-Pendant `dailyStatsFromReceipts` identisch mitziehen (Spiegel-Kopplung).
**Aufwand:** M. **Deploy:** `functions` (OktoPOS undeployt).

---

## 4. Niedrig

### L1 — Kiosk-Gerätekonto darf Einkaufspreise/Bestellungen lesen `[BELEGT]`
**Datei:** `firestore.rules:1395` (products), `:1439` (purchaseOrders), `:1387` (suppliers) — Read nur `sameOrg(orgId)`, **kein** `!isKiosk()`, obwohl `stockMovements` (`:1727`) und `contacts` (`:1682`) den Guard haben. products trägt `purchasePriceCents`/`marginCents`, purchaseOrders `unitPriceCents`. Das geteilte Tablet (`role:'kiosk'`) erfüllt `sameOrg()`.
**Fix:** `!isKiosk()` auf `purchaseOrders`/`suppliers` ergänzen; für `products` (vom Kiosk-Scanner/Board gebraucht) entweder ebenfalls gaten + kostenfreie Projektion, oder `purchasePriceCents`-Zugriff dokumentiert akzeptieren.
**Aufwand:** S. **Deploy:** `firestore:rules` (Live).

### L2 — `oktoposNightlySync` verarbeitet nur die ersten 50 Orgs `[BELEGT]`
**Datei:** `functions/index.js:4532` — `db.collection("organizations").limit(50).get()` ohne Pagination. Ab der 51. Org kein Nachtlauf (still). Aktuell unkritisch (wenige Orgs), aber latent.
**Fix:** Über alle Orgs paginieren (startAfter-Cursor) oder gezielt Orgs mit aktivem `oktoposSync` via `collectionGroup('config')` abfragen.
**Aufwand:** S. **Deploy:** `functions` (OktoPOS undeployt).

---

## 5. Rest-Risiko / Prüfstatus (aktualisiert 11.07. nach Re-Run)

Der Re-Run über die zuvor abgestürzten 7 Dimensionen ist **sauber durchgelaufen** (10 Agenten, 0 Fehler, 15 neue Befunde). Befunde in §9. Aktueller Status:

| Bereich | Status | Ergebnis |
|---|---|---|
| Warenwirtschaft-**Provider** | **geprüft** | K-neu H6 (currentStock-Clobber, CONFIRMED) + N4 (Inventur-Delta) |
| Warenwirtschaft-**Models** | **geprüft** | N5 (ProductBatch-Datum-Fallback); Serialisierung sonst sauber |
| Cloud Functions **allgemein** | **geprüft** | **K3 Cross-Tenant-Schicht-Schreiben (CONFIRMED, kritisch)** + N6/N7 (Kiosk) |
| **Dart-Korrektheit** quer | **geprüft** | N1 (PDF-Export zählt nicht-genehmigte als Ist, E3-Verstoß) |
| **Auth-Service** tief | **geprüft** | N2 (Blip→Sign-out), N8 (Legacy-Norm.-Write), N9 (Bootstrap-Gate), N10 (Invite-ID-Norm.) |
| **Compliance-Spiegel-Drift** | **geprüft** | H7 (Schicht-Ruhezeit-Guard-Drift, CONFIRMED) + N3 (workedMinutes-Klemmung). minor/pregnancy synchron. |
| **Neue Signage-Module** | **geprüft** | N11 (Storage-isAdmin ohne isActive), N12 (Player-Token→Doc-ID-Crash) |
| Account-**Löschung** | **geprüft — solide** | (recent-auth Step-up, self-or-admin, assertSameOrg, Letzter-Admin-Schutz) |

**Verbleibendes Rest-Risiko:** gering. Signage nur teil-tief (Bild-Rotation-Timer/Provider-Dispose nicht erschöpfend). Die medium/low-Befunde (N1–N12) sind Finder-Befunde **ohne** adversariale Verifikation (nur critical/high wurden verifiziert) → vor Umsetzung je einzeln am Code bestätigen.

---

## 6. Umsetzungsreihenfolge (Meilensteine)

**S0 — Cloud-Functions-Sicherheit SOFORT (Deploy `functions`)** — NEU, höchste Priorität neben S1:
**K3** (Cross-Tenant-Schicht-Schreiben) — `upsertShiftBatch`/`publishShiftBatch` sind **deployt** (Compliance-Callables laufen produktiv) → **Live-Loch**. Fix ist klein (per-Schicht `assertSameOrg` + `orgId` erzwingen), gehört aber zwingend vor alles OktoPOS. Zusammen mit N1 (E3-Export) prüfen.

**S1 — Rules-Fixes (sofort, EIN Deploy `firestore:rules`)** — alle Live-Löcher auf einmal:
K1, H1, H2, M1, M2, L1 (+ N11 Storage-Rule isActive, separater `storage:rules`-Deploy). Rein deklarativ, kein Client-Code (außer M2 optional Client-Query). Testbar über `firestore.rules`-Emulator + neue Test-Cases.
> Reihenfolge Deploy laut `plan/deploy-checkliste.md`: indexes → **rules** → **storage** → functions → hosting.

**S2 — OktoPOS-Härtung (vor OktoPOS-Cutover, Deploy `functions`)** — kein Live-Loch (undeployt):
K2 (Host-Allowlist), H3 (siteId/Key-Scope), H4 (lineId), H5 (Pagination), M3 (MAX_PAGES), M4 (Idempotenz), M5 (cogs-Refund). Node-Tests in `functions/test/` ergänzen.

**S3 — Client-Korrektheit (Deploy = App-Build)** — Warenwirtschaft + Compliance-Spiegel + Freigabe:
H6 (currentStock-Clobber, **CONFIRMED, Datenverlust**), H7 (Schicht-Ruhezeit-Spiegel-Drift, **CONFIRMED**), N1 (PDF-Export E3), N4 (Inventur-Delta), N2 (Login-Blip→Sign-out). Je mit Regressionstest.

**S4 — Rest (low, opportunistisch):** N3, N5, N6–N12. Vor Umsetzung einzeln verifizieren.

---

## 7. Definition of Done

- [ ] S1: firestore.rules-Fixes umgesetzt + Deny-Tests (fremde Org, permission-loses Invite, self-hourlyRate, Kiosk-Read) grün.
- [ ] `flutter analyze` sauber, `flutter test` grün (bestehende ~107 Cases + neue).
- [ ] S1 deployt (`firebase deploy --only firestore:rules`), Live-Löcher geschlossen.
- [ ] S2: OktoPOS-Fixes + `node --test` in `functions/test/` grün; Deploy **gebündelt** mit dem ausstehenden OktoPOS-/overtimeMinutes-functions-Deploy (`plan/deploy-checkliste.md`).
- [ ] S3: Rest-Dimensionen (§5) geprüft, Nachtrag ergänzt.
- [ ] Commit (Branch `feat/zeit-schichtbindung-freigabe` ist voller unrelated uncommitted Arbeit — Rules-/Functions-Fixes in eigenem Commit isolieren).

---

## 8. Rohdaten

Wiederhergestellte Finder-Befunde + Verdikte: Workflow-Journal
`/Users/jowan/.claude/projects/-Users-jowan-Documents-dev-WorkTime/0d0b2e1c-c207-4695-8e79-1eeed129ed76/subagents/workflows/wf_b5a1b361-ade/journal.jsonl`
(15 Befunde aus 6 Dimensionen: okto-auth, ww-rules, auth-rules, okto-integrity, rules-tenancy, okto-client; 2 CONFIRMED-Verdikte auf K1 + K2.)
Re-Run (§9): `wf_0adeb69e-ded/journal.jsonl` (7 Dimensionen sauber, 15 Befunde, 3 CONFIRMED).

---

## 9. Nachtrag: Re-Run der Rest-Dimensionen (11.07.2026)

Sauberer Lauf über die zuvor abgestürzten 7 Dimensionen. 3 Befunde adversarial verifiziert (CONFIRMED), 12 als Finder-Befunde (medium/low, `[FINDER]` = noch nicht adversarial verifiziert → vor Umsetzung einzeln bestätigen).

### K3 — Cross-Tenant-Schicht-Schreiben/-Überschreiben `[CONFIRMED]` — KRITISCH, LIVE
**Datei:** `functions/index.js:1040` (`upsertShiftBatch`), `:1076` (`publishShiftBatch`), `:3916` (`parseShift`), `:2766` (`writeShiftBatch`).
Beide Callables prüfen nur die **Top-Level**-`orgId` (`assertSameOrg(caller, orgId)` `:1046`/`:1082`), aber **nicht** die `org_id` jeder einzelnen Schicht. `parseShift` übernimmt die client-gelieferte Org: `orgId: stringOrEmpty(map.org_id) || fallbackOrgId` (`:3916`). `writeShiftBatch` schreibt in die Collection der **ersten** Schicht: `organizationCollection(shifts[0].orgId, "shifts")` (`:2766`) mit `batch.set(..., {merge:true})` → kann bestehende Fremd-Docs überschreiben. Der Work-Entry-Pfad prüft dagegen **jede** Zeile (`:1215-1217` `for (const entry of entries) assertSameOrg(caller, entry.orgId)`) — der Schicht-Pfad ist die Ausnahme. Cloud Functions nutzen das Admin SDK → `firestore.rules` (sameOrg) werden umgangen; die Compliance-Re-Validierung lädt Kontext für die **eigene** Org des Callers → merkt den Fremd-Write nicht.

**Angriff:** Ein **Planer** (`assertScheduler` = Teamlead+, nicht nur Admin) von Org A ruft `upsertShiftBatch` mit `data.orgId=A` und `shifts=[{org_id:"main-org", id:"<Opfer-Schicht-ID>", user_id, start_time, end_time}]`. `shift.orgId="main-org"`, Compliance grün (harmlose Schicht), `writeShiftBatch` schreibt/überschreibt `organizations/main-org/shifts/<ID>`. Fremde Schichten anlegen, umbuchen, Zeiten ändern — unter Umgehung von Rules **und** Compliance, auf dem als „validiert" geltenden Callable-Pfad.
**Fix:** In beiden Callables nach dem Parsen die Org erzwingen: `const shifts = rawShifts.map((item,i) => ({...parseShift(item,i,orgId), orgId}))` (bei publish zusätzlich `status` mergen); **und** `writeShiftBatch` explizit `orgId` statt `shifts[0].orgId` übergeben. Regressionstest: Caller Org A, `org_id=B` im Payload → `permission-denied`, kein Write nach B.
**Aufwand:** S. **Deploy:** `functions` — **deployt** (Compliance-Callables laufen produktiv) → **Live-Loch, S0**.

### H6 — Warenwirtschaft: `saveProduct` überschreibt `currentStock` (Lost-Update) `[CONFIRMED]`
**Datei:** `lib/providers/inventory_provider.dart:1034`, `lib/repositories/firestore_inventory_repository.dart:349-353`, `lib/models/product.dart:259`.
`saveProduct` schützt beim Manager-Edit nur `fridgeStock` vor dem Clobbern (`copyWith(fridgeStock: productById(...)?.fridgeStock)` + Repo `..remove('fridgeStock')` vor `set(merge:true)`). `currentStock` steht aber in `toFirestoreMap()` (`:259`) und wird per merge mitgeschrieben — obwohl es demselben nebenläufigen `FieldValue`-Increment unterliegt (`adjustProductStock`/`receivePurchaseOrder`/OktoPOS-Pull, transaktional aus dem frischen Serverwert). Der Editor sichert sogar fälschlich zu „Live-Bestand bleibt unangetastet" (`inventory_screen.dart:2416`).

**Angriff/Szenario:** Manager öffnet Artikel (currentStock=10 eingefroren), ändert nur den Preis; parallel bucht ein Verkauf/POS `-1` → Server=9; Manager speichert → `set(merge:true)` schreibt `currentStock:10` zurück → **verkaufte Einheit verschwindet** (Phantombestand, falscher Warenwert, verfälschte Meldebestand-Signale). Tritt auch ohne offenen Editor via `updateProductPrices` (Scanner-Preisabweichung, `:1094`) auf.
**Fix:** `currentStock` wie `fridgeStock` schützen, aber **nur auf dem UPDATE-Pfad** (`product.id != null`, damit Anfangsbestand neuer Artikel weiter persistiert): im Repo `if (product.id != null) data.remove('currentStock');` vor `set(merge:true)`; im Provider für bestehende Artikel den frischen In-Memory-Wert re-injizieren. Regressionstest: offener Edit + paralleler `adjustProductStock(-1)` + Preis-Speichern → `currentStock` bleibt dekrementiert.
**Aufwand:** S–M. **Deploy:** App-Build (S3).

### H7 — Compliance-Spiegel-Drift: Schicht-Ruhezeit ohne Selben-Tag-Guard `[CONFIRMED]`
**Datei:** `functions/index.js:3454` (`singleRestGapViolations`, kein Guard) vs. `lib/services/compliance_service.dart:724` (`_shouldEnforceRestGap`).
Der Dart-Client überspringt die Ruhezeitprüfung für zwei getrennte Ein-Tages-Schichten am **selben Kalendertag** (Split-Shift, `_shouldEnforceRestGap`). Der JS-Server ruft diesen Guard im **Schicht-Pfad** nirgends auf (`restViolations :3404` → `singleRestGapViolations :3454` ohne Guard); serverseitig existiert er nur im WorkEntry-Pfad. Asymmetrie = Client zeigt Split-Shift grün, Server blockt.

**Szenario:** Split-Shift 08:00–12:00 + 14:00–18:00 (Lücke 120 min). Vorschau grün (Guard greift). Speichern via `upsertShiftBatch` → `rest_time` blocking (120 < 660) → `failed-precondition` → Client wirft `StateError`, Batch verworfen. Legitime Planung wird abgelehnt, obwohl die Vorschau OK war. (Richtung: Server strenger als Client → Workflow-Blocker, kein Bypass — aber Kopplung #2 verletzt.)
**Fix:** Guard oben in `singleRestGapViolations` spiegeln: `if (!shouldEnforceRestGap(earlier.startTime, earlier.endTime, later.startTime)) return [];` (im gemeinsamen Helfer → deckt Schicht-Pfad, idempotent für WorkEntry-Pfad). Split-Shift-Regressionstest node-seitig.
**Aufwand:** S. **Deploy:** `functions` (mit S0/S2 bündeln).

### Medium `[FINDER]`
- **N1** — PDF-Monatsbericht zählt nicht-genehmigte (inkl. abgelehnte) Zeiten als Ist (`lib/services/pdf_service.dart:53`). Screen filtert korrekt via `countsAsIst` (`month_report_screen.dart:93`), übergibt aber die **ungefilterte** Liste an den Export (`:191`) → `totalHours`/`totalWage`/Overtime im offiziellen PDF überzeichnet (E3-Verstoß). Fix: Kennzahlen im PDF/Aufrufer über `entries.where(countsAsIst)`. → S3.
- **N4** — `recordStocktake` erreicht den gezählten Bestand nicht (`inventory_provider.dart:2234`): `delta = countedStock − staleUiValue` wird transaktional auf den **frischen** Serverwert addiert → bei Parallelbuchung landet die Inventur nicht auf dem gezählten Wert. Fix: absolut setzender Inventur-Pfad (`newStock = countedStock` in der Transaktion). → S3.
- **N2** — Transienter Firestore-Fehler beim Login erzwingt kompletten Sign-out (`auth_provider.dart:366`): pauschaler `signOut()` auf **jede** Exception aus `ensureProfileForSignedInUser`, auch `unavailable`/`network-request-failed` → intakter Nutzer bei Backend-Blip ausgeloggt. Fix: nur bei endgültigen Autorisierungsfehlern abmelden; retrybare Codes halten/Retry. → S3.

### Low `[FINDER]` (S4, je vor Umsetzung verifizieren)
- **N3** — `workedMinutesFromEntry` klemmt server-seitig auf ≥0 (`Math.max(0,...)`, `index.js:3740`), Dart nicht (`compliance_service.dart:992/429`) → bei Pause > Arbeitszeit divergente Tages-/Monatssummen (Server strenger). Beide Seiten angleichen.
- **N5** — `ProductBatch.expiryDate` fällt bei fehlendem/kaputtem Datum still auf `2000-01-01` statt zu werfen (`product_batch.dart:135/156`) → dauerhafte Falsch-Ablaufwarnung. Wie `WorkEntry.date` als load-bearing behandeln (werfen/überspringen).
- **N6** — Kiosk-Clock-out schreibt `WorkEntry.date` als rohen Stempel-Zeitpunkt statt Mittags-normalisiert (`index.js:1941`, emulator-pending). Server-seitig auf lokale Mittagszeit normalisieren.
- **N7** — `kioskSaveCashCount` speichert unvalidierte client-`siteId` (Session trägt keine siteId, `index.js:2006`) → Fehlattribution innerhalb der Org. siteId gegen Org-Sites validieren.
- **N8** — Legacy-Profil-Normalisierung schreibt ungeschützt (`firestore_service.dart:2703`): ändert sie `email` von '' → Auth-Mail, verweigern die Self-Update-Rules (`email` muss gleich bleiben) → Login-Abbruch für Alt-Accounts. Write in try/catch kapseln (best-effort).
- **N9** — Bootstrap-Admin-Selbstprovisionierung ist nicht code-seitig Dev-gegated (`firestore_service.dart:2639`), nur durch Rules gebremst → Defense-in-Depth: an `kDebugMode`/`disableAuthentication` binden.
- **N10** — Invite-Doc-ID-Normalisierung divergiert: Rules `inviteIdForCurrentUser()` (`firestore.rules:498`) ohne `trim`/`'/'→'_'`, Client/Functions mit. Praktisch derzeit nicht ausbeutbar (valide E-Mails), aber SSoT-Divergenz an Trust-Grenze. Angleichen/dokumentieren.
- **N11** — Signage-**Storage**-Rule `isAdmin()` prüft `isActive` nicht (`storage.rules:121`): deaktivierter (entlassener) Admin behält gültiges Token → kann Werbebild-Blobs lesen/überschreiben/löschen. Gleiche Lücke bei `employee-documents`/Kontakt-Avatar. Fix: `&& isTruthy(callerDoc().data.isActive)` konsistent; optional `revokeRefreshTokens` bei Deaktivierung. → mit S1/`storage:rules`.
- **N12** — Player-Token ungeprüft als Firestore-Doc-ID (`public_display_screen.dart:82`): Token mit `/` (Prozent-Encoding/Tippfehler) → synchrone Exception in `initState`/`_pair` → Fernseher zeigt Flutter-Fehlerbildschirm statt „Display nicht gefunden". Token vor `.doc()` validieren (kein `/`, Länge, Alphabet).
