# Dritte-Hand-/Treuhand-/Fremdgeld-Beträge beim Kassenzählen (Tablet-Arbeitsmodus)

> Stand: 2026-07-03 · Status: **PLAN (nur Design/Planung, kein finaler Code)** · Zielumgebung: Blaze
> Kern: Lotto, Post, KVG-Tickets, externe Dienste als **Fremdgeld/Durchlaufposten** in der Kasse erfassen, **strikt getrennt** vom Umsatz, ohne bestehende Kassenberichte zu verfälschen.

---

## 0. Leitprinzip (nicht verhandelbar)

**Dritte-Hand-Geld ist Fremdgeld/Treuhand — kein Umsatz, kein Rohertrag, keine USt der Filiale.** Es liegt physisch in derselben Schublade wie das eigene Bargeld, gehört aber wirtschaftlich Dritten (Lotto-Gesellschaft, Deutsche Post, KVG, …). Daraus folgen drei harte Trennlinien, die aus den Analyse-Fakten stammen:

1. **Umsatz-Trennung:** Dritte-Hand darf **niemals** als `isRevenue`-Beleg oder in `PosDailyStat.revenueGrossCents`/`revenueNetCents`/`taxes` landen — sonst kaputt: `kasse_report.dart` (alle KPIs), `daily_closing.dart`, `functions/oktopos_stats.js:96`.
2. **Soll/Zählung-Konsistenz:** In `CashState.sollCents` (`cash_state.dart:114`) und in der Kassendifferenz-Rechnung (`cash_closing.dart:116-118`) muss Dritte-Hand **entweder auf beiden Seiten oder gar nicht** auftauchen. Der **sauberste Weg = gar nicht** in dieser Rechnung → Fremdgeld getrennt führen, die eigene Kassendifferenz bleibt exakt wie heute.
3. **Aggregat-Overlap:** Dritte-Hand berührt **kein** Steuer-Bucket, **kein** `net`/`gross`, **kein** `netUncoveredGross`. Es lebt in einer **eigenen, separaten Struktur**.

**Konsequenz für die Architektur:** Wir addieren Dritte-Hand **nicht** in `countedCents` und **nicht** in `cashExpectedCents`. Wir führen es als **eigene, klar separierte Beträge** neben der Zählung. `countedCents` bleibt „eigenes Bargeld-Ist der Kasse". Die Gesamtsumme in der Schublade ist eine **reine Anzeige-Rechnung** (`countedCents + Σ Dritte-Hand`), die nirgends gespeichert in ein Umsatz-Aggregat fließt.

---

## 1. Datenmodell

### 1.1 Kategorien-Konfiguration je Filiale — `ThirdPartyCashType`

**Fachliche Frage: org-weit oder filial-granular?** Die Anforderung lautet „pro Filiale konfigurierbar, welche Arten verfügbar sind". Das spricht — analog zu `weekdayHours`/`staffingDemands` an `SiteDefinition` — für **filial-granulare Aktivierung**. Aber: die **Kategorie-Stammdaten** (Name „Lotto", Sortierung, Pflichtfeld-Regel) sollen org-weit **einheitlich benannt** sein (sonst driften „Lotto" und „Lotterie" auseinander). Deshalb **zwei-schichtiges Modell**:

- **Kategorie-Katalog = org-weit** (ein Stammsatz je Art, admin-verwaltet).
- **Aktivierung + filialspezifische Overrides = je Filiale** (welche Katalog-Arten sind hier aktiv, ist hier Pflicht?).

Das vermeidet Duplikat-Kategorien und erlaubt trotzdem „Lotto nur in Filiale Tabak Börse aktiv".

#### Ablageort: `OrgSettings` (Katalog) + `SiteDefinition` (Aktivierung)

| Schicht | Ablage | Begründung (aus Fakten) |
|---|---|---|
| **Katalog** `thirdPartyCashTypes: List<ThirdPartyCashType>` | **`OrgSettings`** (`config/orgSettings`, admin-write/sameOrg-read, `org_settings.dart:3-5,21-22`) | Org-weite einheitliche Benennung; `OrgSettings` ist genau für org-weite operative Defaults gedacht. Kopplung #1 gilt (`OrgSettings` ist dual-serialisiert). |
| **Aktivierung je Filiale** `thirdPartyCashConfig: SiteThirdPartyConfig?` (nullable) | **`SiteDefinition`** (`organizations/{orgId}/sites`) | Exakt das Muster `weekdayHours`/`staffingDemands` (Nested-Array je Filiale, `site_definition.dart:63,67`). 6-Stellen-Regel greift voll. |

> **Alternative erwogen & verworfen:** Alles nur in `SiteDefinition` (Katalog dupliziert je Filiale) → Namensdrift, kein zentrales Umbenennen. Alles nur in `OrgSettings` mit `enabledSiteIds` je Type → verstößt gegen die Konvention „filialspezifische Listen-Config gehört an `SiteDefinition`" und macht die Site-Config-Karte inkonsistent. Der Zwei-Schichten-Ansatz ist der Fit.

#### `ThirdPartyCashType` (Katalog-Eintrag, lebt in `OrgSettings.thirdPartyCashTypes`)

Kein eigenes Top-Level-Doc, keine eigene Collection — es ist ein **eingebettetes Value-Object** in `OrgSettings` (wie `WeekdayHours` in `SiteDefinition`). Dadurch **keine** neuen Rules, **kein** neuer Index, **keine** neue Collection.

```
class ThirdPartyCashType {
  final String id;            // stabile Kurz-ID, z.B. 'lotto' (slug, lowercase, [a-z0-9_])
  final String name;          // Anzeigename, z.B. 'Lotto'
  final String? hint;         // optionaler Hinweistext, z.B. 'Nur Bareinnahmen, keine Auszahlungen'
  final bool archived;        // statt hartem Löschen (Bestandsdaten referenzieren id weiter)
  final int sortOrder;        // Anzeige-Reihenfolge im Katalog
}
```

- **Enum vs. Freitext:** **Freitext-Name + stabile String-`id`** (kein Dart-Enum). Begründung: Die Arten sind **betreiberspezifisch** (Lotto/Post/KVG heute, morgen „DHL-Filiale" oder „Paketshop") — ein Dart-Enum wäre ein Code-Deploy je neuer Art und verstößt gegen „Admin verwaltet Kategorien". Die `id` ist der revisionsfeste Schlüssel (bleibt stabil, wenn `name` umbenannt wird); `name` ist nur Anzeige. Das ist konsistent mit `denominations` als frei geformter `Map<String,int>` (`cash_count.dart:72-73`).
- **Löschen = `archived: true`** (nicht hart entfernen), weil historische Zählungen die `id` referenzieren — sonst brechen alte Auswertungen. Archivierte Arten erscheinen nicht mehr zur Erfassung, aber alte Werte bleiben zuordenbar.

**Serialisierung `ThirdPartyCashType`** (Teil von `OrgSettings`, das dual serialisiert):

`toFirestoreMap()` (camelCase) — Teil von `OrgSettings.toFirestoreMap`:
```json
{ "id": "lotto", "name": "Lotto", "hint": "…", "archived": false, "sortOrder": 0 }
```
`toMap()` (snake_case) — Teil von `OrgSettings.toMap` (lokaler Fallback `local_v2/org_settings`):
```json
{ "id": "lotto", "name": "Lotto", "hint": "…", "archived": false, "sort_order": 0 }
```
Beide `fromFirestore`/`fromMap` tolerant via `parse.toBool/toInt`, String-Fallbacks. `copyWith` mit `clearHint`-Flag (nullable `hint`).

#### `SiteThirdPartyConfig` (Aktivierung je Filiale, lebt in `SiteDefinition.thirdPartyCashConfig`)

```
class SiteThirdPartyConfig {
  final List<SiteThirdPartyEntry> entries;   // nur aktivierte Arten dieser Filiale
}
class SiteThirdPartyEntry {
  final String typeId;        // FK auf ThirdPartyCashType.id
  final bool enabled;         // aktiv an dieser Filiale
  final bool required;        // Pflichtbetrag beim Zählen an dieser Filiale (Betrag muss eingegeben werden, auch 0)
  final int sortOrder;        // filialspezifische Reihenfolge (überschreibt Katalog-sortOrder)
}
```

- `thirdPartyCashConfig` ist **nullable** → alte Sites ohne Feld = `null` = „keine Dritte-Hand-Arten aktiv" = heutiges Verhalten. **Kein Backfill nötig** (siehe §7).
- `required` je Filiale (nicht je Katalog), weil dieselbe Art in einer Filiale Pflicht (Lotto-Filiale) und in einer anderen optional sein kann.
- Serialisierung folgt exakt `WeekdayHours`: `toFirestoreMap`/`fromFirestore` camelCase (`typeId`, `sortOrder`), `toMap`/`fromMap` snake_case (`type_id`, `sort_order`), `copyWith` (+ `clearThirdPartyCashConfig` am `SiteDefinition`, weil nullable → Kopplung #1, 6 Stellen: `site_definition.dart` `toFirestoreMap:190`, `fromFirestore:134`, `toMap:212`, `fromMap:163`, `copyWith:233` + `clearX`).

### 1.2 Erfasste Beträge beim Zählen — **NEUE getrennte Struktur**

**Entscheidung: eingebettete Sub-Liste im `CashCount` UND im `CashClosing`, KEINE separate Collection.**

**Begründung (belastbar aus den Fakten):**
- `CashCount` und `CashClosing` sind **cloud-only, unveränderlich, create-only** (`cash_count.dart:10-16`, `cash_closing.dart:14-19`). Eine eingebettete Liste erbt automatisch die Unveränderlichkeit — keine Zweit-Konsistenz zwischen Zählung und einem separaten Fremdgeld-Doc, das getrennt geschrieben/gelöscht werden könnte.
- Eine **separate Collection `cashClosingThirdParty` verknüpft über `closingId`** würde ein **zweites Write** je Abschluss verlangen (Race: Abschluss geschrieben, Fremdgeld-Doc nicht) und einen **zweiten Index** + eine **zweite Rules-Block** + einen **zweiten Read** im Bericht. Das ist mehr Fehleroberfläche für null funktionalen Gewinn — die Fremdgeld-Beträge werden **immer zusammen** mit der Zählung erfasst und gelesen (1:1-Kardinalität, gemeinsame Lebensdauer).
- Der Trenn-Effekt (keine Verfälschung) kommt **nicht** aus der physischen Collection-Trennung, sondern daraus, dass die Beträge **niemals** in `countedCents`/`revenueGrossCents`/`taxes` addiert werden. Ein **separates Feld genügt** dafür vollständig — bestätigt in den Analyse-Fakten (Abschnitt 7 der Kassen-Doku: „bevorzugt neues Feld auf `PosDailyStat`/`CashClosing`").

**Also: neues Feld `thirdPartyAmounts: List<ThirdPartyAmount>?` auf `CashCount` und auf `CashClosing`.**

```
class ThirdPartyAmount {
  final String typeId;        // FK auf ThirdPartyCashType.id (Snapshot des Schlüssels)
  final String typeName;      // Snapshot des Anzeigenamens (revisionsfest, falls Katalog später umbenannt/archiviert)
  final int amountCents;      // erfasster Ist-Betrag, >= 0 (Fremdgeld ist Bargeld in der Schublade)
  final String? note;         // optional
}
```

- **`typeName` als Snapshot** (nicht nur `typeId`): wird eine Art später umbenannt/archiviert, bleibt der historische Anzeigename lesbar — gleiches Prinzip wie `siteName`-Snapshot in `EmployeeSiteAssignment` und `countedByLabel` in `CashCount`.
- **Nur Ist, kein Soll pro Betrag** (Default). Fremdgeld hat betrieblich selten ein tagesscharfes „Soll" in der App — die Erfassung ist eine reine Bestandsaufnahme („so viel Lotto-Geld liegt heute in der Kasse"). **Optionales Soll bewusst verworfen für V1** (siehe §2.3). `amountCents` ist damit reine Ist-Erfassung.

#### Model-Änderungen `CashCount` (cloud-only → nur 3 Model-Stellen, KEIN snake_case)

`cash_count.dart` bekommt `final List<ThirdPartyAmount>? thirdPartyAmounts;`:
- **Konstruktor** (`cash_count.dart:18-36`) + Deklaration (`:48-94`).
- **`fromFirestore`** (`:96`): `thirdPartyAmounts: _readThirdParty(map['thirdPartyAmounts'])` — tolerant, `null`/leer → `null`.
- **`toFirestoreMap`** (`:174`): nur schreiben wenn nicht null/leer (`if (thirdPartyAmounts != null && thirdPartyAmounts!.isNotEmpty) 'thirdPartyAmounts': thirdPartyAmounts!.map((e) => e.toFirestoreMap()).toList()`).
- **`copyWith`** (`:134`): `List<ThirdPartyAmount>? thirdPartyAmounts` + **`bool clearThirdPartyAmounts = false`** (Abweichung: `CashCount.copyWith` ist heute bewusst ohne clearX weil create-only — für dieses eine nullable Feld ist `clearX` trotzdem sauber, oder wir bleiben create-only-konform und lassen clearX weg, da `CashCount` nie „geleert" wird; **Empfehlung: kein clearX**, konsistent mit dem create-only-Charakter).
- **`ThirdPartyAmount` selbst** ist camelCase-only (`toFirestoreMap`/`fromFirestore`), weil es nur eingebettet in cloud-only-Models lebt.

**Kiosk-Ausnahme (snake_case-Bedarf!):** Der Kiosk-Weg geht über die **Callable** `kioskSaveCashCount`. Kiosk-Callables nutzen laut Fakten **camelCase**-Payloads (kein Model geht durch `toMap()`, Fakten Abschnitt 1 „NEIN, camelCase"). Also **kein** snake_case für den Kiosk-Pfad — der Client baut die Payload direkt camelCase in `FirestoreService.kioskSaveCashCount`. Damit entfällt die snake_case-Serialisierung komplett. `ThirdPartyAmount` braucht **nur** `toFirestoreMap`/`fromFirestore`.

#### Model-Änderungen `CashClosing` (cloud-only → 3 Model-Stellen)

`cash_closing.dart` bekommt ebenfalls `final List<ThirdPartyAmount>? thirdPartyAmounts;` + Summen-Convenience:
- **`fromDailyClosing`** (`:86-122`): übernimmt `thirdPartyAmounts` aus der eingebetteten Zählung (`zaehlung?.thirdPartyAmounts`) — reiner Durchreich-Snapshot. **`cashDifferenceCents` bleibt exakt `counted − cashExpectedCents`** (`:116-118`), **unverändert**, ohne Dritte-Hand. Das ist die Kern-Nichtverfälschungs-Garantie.
- **`fromFirestore`/`toFirestoreMap`** analog `CashCount`.
- **Rules `keys().hasOnly(...)`** (`firestore.rules:1618-1625` für `cashClosings`, `:1549-1555` für `cashCounts`): `thirdPartyAmounts` in die feste Feldliste aufnehmen (sonst Deny). Für `cashCounts` zusätzlich Typ-Check-Block optional (map/list-Check).

**Zusammenfassung Model-Aufwand:** 3 Model-Stellen je Model (kein snake_case, cloud-only), 1 neues Value-Object `ThirdPartyAmount` (camelCase-only), Katalog `ThirdPartyCashType` + `SiteThirdPartyConfig` dual-serialisiert (in `OrgSettings`/`SiteDefinition`, die durch beide Pfade gehen). Rules-`hasOnly`-Listen erweitern. **Keine neue Collection, kein neuer Index.**

---

## 2. Backend-Logik & Berechnung

### 2.1 Gesamt-Geldbestand (reine Anzeige-Rechnung, nirgends persistiert in Umsatz)

```
gesamtGeldbestandCents = countedCents (eigenes Kassen-Ist)
                       + Σ thirdPartyAmounts[].amountCents (Fremdgeld)
```

Diese Summe ist eine **Anzeige-/Abgleich-Größe** (Tablet-Zusammenfassung, Kassenbericht-KPI). Sie wird **nicht** als neues Umsatzfeld gespeichert, **nicht** in `PosDailyStat` geschrieben, **nicht** ins Finanzjournal gebucht. Optional als **abgeleitetes** Getter `CashClosing.totalCashDrawerCents` (computed, nicht persistiert) für die Anzeige.

### 2.2 Differenz-Logik — zwei komplett getrennte Welten

| Welt | Formel | Quelle | Ändert sich? |
|---|---|---|---|
| **Eigene Kasse** (wie heute) | `cashDifferenceCents = cashCountedCents − cashExpectedCents` | `cash_closing.dart:116-118`, `cash_count.dart differenceCents`, `cash_state.dart:114` | **NEIN — 1:1 unverändert.** `countedCents`/`expectedCents` enthalten **kein** Fremdgeld. |
| **Dritte Hand** | **kein Soll in V1** → nur Ist-Summe je Art + Gesamt-Fremdgeld | neues `thirdPartyAmounts` | additiv, isoliert |

**Die eigene Kassendifferenz und ihre Journal-Buchung (`buildCashDifferenceEntry`, `cash_difference_posting.dart`) bleiben unberührt.** Das ist genau die kritische Nicht-Verfälschung: würde man Fremdgeld in `countedCents` mitzählen, aber nicht ins `expectedCents`, entstünde eine **Schein-Differenz**, die fälschlich ins Journal gebucht würde (Fakten Abschnitt 7-C). Durch die Trennung passiert das **nie**.

**Fremdgeld-Soll (bewusst verworfen für V1):** Ein tagesscharfes Fremdgeld-Soll (z. B. „Lotto-Vortag + heutige Lotto-Verkäufe − Abschöpfungen") würde einen Fremdgeld-`CashState`-Analogpfad und POS-Kategorisierung der Lotto-Umsätze verlangen — die es ohne OktoPOS-Kategorien nicht gibt. **V1 = reine Ist-Erfassung** („wie viel Fremdgeld liegt heute in der Schublade"). Ein späteres Fremdgeld-Soll wäre additiv (neues optionales `expectedCents` pro `ThirdPartyAmount`) und ist in §2.3 als Ausbaustufe vermerkt.

### 2.3 Einfluss auf `kasse_report.dart` — additiver, separater Block, **null Änderung an bestehenden Aggregaten**

- **`PosDailyStat` bleibt komplett unverändert.** Fremdgeld fließt **nicht** in `revenueGrossCents`/`revenueNetCents`/`taxes`/`cashMovementCents`. `functions/oktopos_stats.js` wird **nicht** angefasst (kein `isRevenue`-Beleg, kein `type='cash'`-Beleg für Fremdgeld). Damit sind **alle** Kassenbericht-KPIs (`umsatzBrutto/Netto`, `rohertrag*`, `delta*`, `wareneinsatz*`) byte-identisch zu heute.
- **Neue, getrennte Aggregation** im Bericht: Der Kassenbericht liest zusätzlich die `CashClosing`-Docs der Periode (bzw. deren `thirdPartyAmounts`) und bildet einen **eigenen Block** `KassenPeriode.dritteHand`:

```
class ThirdPartyPeriodAgg {
  final int gesamtFremdgeldCents;                 // Σ aller thirdPartyAmounts der Periode
  final Map<String,int> jeArtCents;               // typeId -> Σ amountCents
  final Map<String,String> artName;               // typeId -> letzter typeName (Anzeige)
  final int eigeneKasseGezaehltCents;             // Σ cashCountedCents (nur zur Kontext-Anzeige)
}
```

- **Wichtig:** Der Kassenbericht kennt heute **weder `CashCount` noch `CashClosing`** (Fakten Abschnitt 3: „Differenz fließt NICHT in kasse_report"). Der Fremdgeld-Block ist also eine **neue, additive Datenquelle** im Report — er **verändert keine** vorhandene Zeile, er hängt einen separaten Abschnitt an. Falls die `CashClosing`-Docs im Bericht bisher nicht geladen werden, kommt ein zusätzlicher, klar getrennter Read hinzu (org-skopiert, Zeitraum-gefiltert), der die Umsatz-Aggregation nicht berührt.
- **Auswertung „eigene Kasse vs. externe Dienste":** `anteilFremdgeldPct = gesamtFremdgeldCents / (gesamtFremdgeldCents + eigeneKasseGezaehltCents)`. Reine Bestandsbetrachtung des Bargelds, **nicht** des Umsatzes — sauber getrennt kommuniziert (siehe §5).

---

## 3. Kiosk-/Tablet-UX (Kern)

### 3.1 Position im Zählprozess

**Reihenfolge am Tablet (blinde Zählung, `_CashCountTile`):**

```
[Kasse zählen]  →  Schritt 1: Eigenes Bargeld (wie heute, blind)
                →  Schritt 2: Dritte Hand / Fremdgelder  (NUR wenn Filiale Arten aktiv hat)
                →  Schritt 3: Zusammenfassung (Kasse | Dritte Hand je Art | Gesamt)  →  [Speichern]
```

- **Schritt 2 erscheint nur, wenn** `site.thirdPartyCashConfig?.entries.any((e) => e.enabled) == true`. Sonst bleibt der Flow **exakt wie heute** (ein Betrag, direkt speichern) — keine UX-Regression für Filialen ohne Fremdgeld.
- **Getrennte Sektion, eigene Card + eigene Farbe:** Der Fremdgeld-Block bekommt eine visuell klar abgesetzte Card (eigener Header „Dritte Hand / Fremdgelder", eigenes Icon `Icons.account_balance_wallet_outlined`, dezente `Theme.of(context).appColors.info`-getönte Fläche statt der Kassen-Standardfarbe) — die Anforderung „optisch klar getrennt von normaler Kasse" wird auf Layout-Ebene erfüllt. **Kein Hardcode** von Farben → `appColors` (ThemeExtension).

### 3.2 Umbau `cash_count_sheet.dart` — von „ein Feld" zu „Kasse + Fremdgeld-Sektion"

Das heutige Sheet hat **genau ein** Betragsfeld (`cash_count_sheet.dart:127-138`) und liefert `CashCountInput{countedCents, note}`. Erweiterung:

- Neuer optionaler Parameter `showCashCountSheet(..., List<SiteThirdPartyEntry>? thirdPartyEntries, Map<String,String> typeNames)`.
- Ist `thirdPartyEntries == null || leer` → **Sheet bleibt 1:1 wie heute** (Rückwärtskompatibilität für den Tagesabschluss-Screen und Filialen ohne Fremdgeld).
- Sonst: unter dem Kassen-Betragsfeld eine **`_ThirdPartySection`** (eigene Card) mit **je aktivierter Art eine Zeile**:
  - Zeilen-Layout: `Art-Name` (+ `hint` als kleiner Untertext, + `required`-Badge „Pflicht") — großes Touch-Ziel, `ListTile`-artig.
  - Betrag pro Zeile: **großes Touch-Numpad** (nicht nur System-Tastatur). Vorschlag: pro Zeile ein „Betrag eingeben"-Button, der ein **fokussiertes Zahlen-Sheet** mit dem PIN-Style-Numpad-Layout öffnet (`_NumPad`-Muster aus `kiosk_screen.dart:1374`, `SizedBox(width:84,height:64)`-Tasten, `headlineSmall`), plus Komma-Taste für Cent. Alternativ inline ein großes zentriertes `TextField` (`headlineMedium`, `suffixText '€'`) wie beim Kassenbetrag — konsistent mit der bestehenden Betrags-Konvention (Fakten Abschnitt 4: „Betrag nutzt System-Zifferntastatur, nur PIN hat eigenes Numpad"). **Empfehlung Tablet-first: eigenes großes On-Screen-Numpad je Betrag**, da geteiltes Store-Tablet oft ohne komfortable Systemtastatur und Touch-Targets kritisch sind.
  - Aktionen je Zeile: **Betrag ergänzen/ändern** (Sheet öffnet mit aktuellem Wert) und **auf 0 setzen** (expliziter „0 €"-Chip/Reset-Button — wichtig für „heute kein Lotto-Geld", damit Pflicht-Arten sauber mit 0 quittiert werden können).
  - Live-Summe unter der Sektion: „Fremdgeld gesamt: X €".
- `controller.touch()` bei **jeder** Teilaktion (Betrag öffnen, eingeben, 0 setzen) — Auto-Logout (90 s Client, 10 min Server-TTL) darf mitten in der Erfassung nicht zuschlagen (Fakten Abschnitt 5-c).
- Rückgabe erweitert: `CashCountInput{countedCents, note, thirdPartyAmounts: List<ThirdPartyAmount>}`.

### 3.3 Zusammenfassung vor Abschluss

Neuer **Schritt 3** (eigene Sektion im selben Sheet, gescrollt, oder ein Confirm-Screen vor „Speichern"):

```
Zusammenfassung
────────────────────────────
Eigenes Bargeld (Kasse)        1.234,50 €
Dritte Hand / Fremdgelder
  Lotto                           320,00 €
  Post                            85,50 €
  KVG                          (Pflicht)  ⚠ fehlt      ← Markierung
────────────────────────────
Fremdgeld gesamt                 405,50 €
GELDBESTAND GESAMT             1.640,00 €
```

- **Markierung fehlender/ungewöhnlicher Werte:**
  - **Pflicht-Art ohne Betrag** (`required && Betrag nicht eingegeben` — nicht: Betrag == 0, denn 0 ist ein valider expliziter Wert): rote Warn-Markierung „⚠ Pflicht — bitte Betrag eintragen (0 € bestätigen möglich)". „Speichern" bleibt möglich, aber die Zeile ist visuell markiert und es erscheint ein **Bestätigungsdialog** („KVG wurde nicht erfasst — trotzdem speichern?"). Kein harter Block (Kassenschluss darf nicht verhindert werden), aber deutliche Reibung.
  - **Ungewöhnlich hoher Wert** (heuristisch, z. B. > 5.000 € pro Art oder > eigenes Kassen-Ist): gelbe Info-Markierung „Bitte prüfen — ungewöhnlich hoch". Reine Warnung.
- Farbcodierung über `appColors` (`error`/`warning`/`success`), nie hardcoded.

### 3.4 Speicherpfad Kiosk — `kioskSaveCashCount`-Payload erweitern (session-validiert)

Der Echtbetrieb-Zweig läuft **ausschließlich** über die gehärtete Callable (Fakten Abschnitt 2/5). Erweiterung **additiv**:

- **Client** `firestore_service.dart:1414-1432` — `kioskSaveCashCount(sid, countedCents, businessDay, {note, siteId, cashRegisterId, thirdPartyAmounts})`. `thirdPartyAmounts` als **camelCase-Liste** in die Payload (`[{typeId, typeName, amountCents, note}]`) — konsistent mit den übrigen camelCase-Kiosk-Payloads, **kein** snake_case.
- **Server** `functions/index.js:1445-1513` — nach `requireKioskSession` (`:1452`, Session-Validierung intakt) die `thirdPartyAmounts` validieren (siehe §7) und in das `ref.set(...)` schreiben. **Person bleibt server-authoritativ** (`countedByUserId = session.employeeId` `:1506`), **Blindheit bleibt** (`expectedCents/differenceCents = null` `:1497-1498`). Der Client liefert **nur** Beträge — keine Personen-, keine Soll-Daten.
- **Dev/Fallback-Zweig** (`disableAuth || sid == null`, `kiosk_screen.dart:711-728`): Direkt-Write `inventory.saveCashCount(CashCount(... thirdPartyAmounts: ...))` mit `createdByUid = Geräte-Konto` (Rules-Pin `firestore.rules:1596`). Blind-Zwang (`expectedCents/differenceCents == null`) bleibt erfüllt — `thirdPartyAmounts` berührt diese Felder nicht.

**Anti-Pattern (vermeiden):** ein **separater** zweiter Direkt-Write in eine eigene Fremdgeld-Collection ohne `sid` → würde `createdByUid` auf das Geräte-Konto pinnen und die harte Personen-Zuordnung (ZV-4.1) verlieren. Deshalb **eingebettet in dieselbe session-validierte Zählung**.

### 3.5 Tagesabschluss-Screen (`daily_closing_screen.dart`, Leitung, offen mit Soll)

- `_count()` (`:120-159`) öffnet das Sheet mit `expectedCents: _cashState?.sollCents` (offen für die eigene Kasse) **und** zusätzlich `thirdPartyEntries` der Filiale. Die Fremdgeld-Sektion ist auch hier **blind** (kein Fremdgeld-Soll in V1), nur Ist-Erfassung — die eigene-Kasse-Soll/Differenz-Zeile bleibt exakt wie heute.
- Beim Abschluss `_close()` (`:163-211`) bettet `fromDailyClosing` die `thirdPartyAmounts` der jüngsten Tages-Zählung mit ein (Durchreich-Snapshot). **`cashDifferenceCents` bleibt `counted − cashExpectedCents`**, unverändert.

---

## 4. Admin-Verwaltung der Kategorien

### 4.1 Wo

Andocken an die bestehende **Site-/OrgSettings-Konfiguration**, zweischichtig (§1.1):

- **Katalog verwalten (org-weit):** neuer Abschnitt in den **Einstellungen** (`settings_screen.dart`) bzw. am ehesten dort, wo `OrgSettings`/`FeatureFlagProvider` bereits editiert werden. Ein **`_ThirdPartyCatalogSheet`** (`showModalBottomSheet`, Drag-Handle, scrollControlled): Liste der `ThirdPartyCashType` mit Add/Umbenennen/Hinweis/Archivieren/Sortieren (Reorder). Schreibt in `OrgSettings.thirdPartyCashTypes` (admin-write via `config/{configId}`-Rules, `firestore.rules:549-552`).
- **Aktivierung je Filiale:** neue Sektion **in der Site-Editor-Karte** (wo `weekdayHours`/`staffingDemands` editiert werden, `SiteDefinition`). Pro Filiale: Liste aller **nicht-archivierten** Katalog-Arten mit Switch „aktiv" + Switch „Pflicht" + Reorder. Schreibt `SiteDefinition.thirdPartyCashConfig` (admin-write auf `sites`, `firestore.rules` sites-write admin-only).

### 4.2 UX

- Katalog-Sheet: `ReorderableListView`, je Eintrag `name`-`TextField` + `hint`-`TextField` + Archiv-Toggle. Slug-`id` wird beim Anlegen aus `name` generiert (`_slugify`), danach **unveränderlich** (revisionsfest).
- Filial-Sektion: `SwitchListTile` je Art (aktiv), darunter optional `SwitchListTile` „Pflicht", nur sichtbar wenn aktiv.
- **Audit:** Anlegen/Umbenennen/Archivieren einer Art und Aktivieren/Deaktivieren je Filiale via `_audit?.call(action:, entityType: 'Dritte-Hand-Kategorie', summary: 'Kategorie „Lotto" angelegt' / 'Lotto in Filiale Tabak Börse aktiviert')` — auf dem Erfolgs-Pfad, deutsche Summaries. (Fremdgeld-**Beträge** selbst werden nicht als Rauschen geloggt; die **Konfig-Änderung** ist relevant.)

---

## 5. Auswertung/Berichte (`kassenbericht_screen.dart`)

### 5.1 Neue KPI-Karte „Eigene Kasse vs. Fremdgelder"

Additive Karte, **verändert keine** bestehende KPI (die 6 bestehenden Karten bleiben unberührt):

```
┌─ Geldbestand-Aufteilung (Periode) ──────────┐
│ Eigene Kasse (gezählt)        24.310,00 €    │
│ Dritte Hand / Fremdgelder      3.120,50 €    │
│ ─────────────────────────────────────────── │
│ Anteil Fremdgeld                   11,4 %    │
└─────────────────────────────────────────────┘
```

- Speist sich aus `ThirdPartyPeriodAgg` (§2.3). **Klare Beschriftung**, dass dies **Bargeld-Bestand** ist, nicht Umsatz (Fußnote „Fremdgeld ist kein Umsatz und nicht Teil von Rohertrag/USt").

### 5.2 Aufschlüsselung je Art (+ optionale Zeitreihe)

- Balken-/Listen-Darstellung je `typeId`: „Lotto 2.100 € · Post 620 € · KVG 400,50 €".
- Optionale `fl_chart`-Zeitreihe (Woche/Monat) je Art — analog zur bestehenden Chart-Nutzung im Kassenbericht. Nur bei genügend Datenpunkten, sonst reine Liste.
- Zugriff **admin-only** (wie der restliche Kassenbericht, `/kassenbericht`).

### 5.3 CSV-Export erweitern

- Bestehende Kassenbericht-CSV bekommt **zusätzliche Spalten/Block** am Ende (Reihenfolge/Trennung so, dass bestehende Spalten byte-stabil bleiben): `Fremdgeld gesamt`, je Art eine Spalte `Fremdgeld_Lotto`, `Fremdgeld_Post`, … **UTF-8-BOM + `;`-Delimiter** beibehalten (deutsches Excel, Konvention). Bestehende Zeilen/Spalten **nicht** umordnen — nur anhängen.

---

## 6. Rechte / Bearbeitbarkeit

| Aktion | Wer | Enforcement |
|---|---|---|
| **Fremdgeld erfassen (Kiosk, blind)** | jeder aktive Mitarbeiter in Session | `kioskSaveCashCount` + `requireKioskSession` (server), Blind-Zwang (Rules `:1599-1602`). Person = `session.employeeId`. |
| **Fremdgeld erfassen (Tagesabschluss, offen)** | Admin ODER Teamleitung | wie heute `canView = isAdmin \|\| isTeamLead` (`daily_closing_screen.dart:287`). |
| **Kategorien-Katalog verwalten (Add/Umbenennen/Archivieren)** | **Admin only** | `OrgSettings` write via `config/{configId}` = `isAdmin()` (`firestore.rules:549-552`). |
| **Aktivierung je Filiale** | **Admin only** | `sites`-write admin-only. |
| **Auswertung ansehen (Kassenbericht-Fremdgeld-Block)** | **Admin only** | `/kassenbericht` ist admin-only. |
| **Zählung/Fremdgeld lesen (`cashCounts`)** | Admin/Teamlead | `cashCounts`-read admin/teamlead (`firestore.rules:1544-1545`), Kiosk nie (`!isKiosk`-Prinzip). |

- **Keine neue Rolle.** Fremdgeld-Konfiguration ist admin (hochsensibel, org-weit); Erfassung folgt exakt den bestehenden Zähl-Rechten. Kein `permissionOrDefault→isActive`-Leak, weil der Kiosk-Schreibpfad server-authoritativ ist und der Lesepfad admin/teamlead-gegated bleibt.

---

## 7. Validierung, Fehlerfälle, Nicht-Verfälschung, Migration

### 7.1 Validierung (Server, in `kioskSaveCashCount` + Direkt-Write-Rules)

- Jeder `amountCents`: `Number.isFinite && >= 0` (analog `:1456-1461`). Negativ → `invalid-argument`.
- `typeId`: nicht-leerer String; **Server prüft nicht** gegen den Katalog (Katalog ist Client-Config; ein archivierter/unbekannter `typeId` wird toleriert und via `typeName`-Snapshot lesbar gehalten — verhindert harte Kopplung Kiosk↔Katalog-Ladezustand).
- Liste ≤ sinnvolles Limit (z. B. ≤ 30 Arten) gegen Payload-Missbrauch.
- **Rules:** `thirdPartyAmounts` in `keys().hasOnly(...)` (`firestore.rules:1549-1555`, `:1618-1625`) + optionaler `is list`-Typ-Check. Blind-Zwang (`expectedCents/differenceCents == null`, `:1599-1602`) **unangetastet**.

### 7.2 Fehlerfälle (UX)

- **Kein Internet** (Kasse ist cloud-only): wie heute SnackBar „Zählung braucht Internet" (`saveCashCount` wirft im Local-Modus `StateError`). Fremdgeld teilt dieses Verhalten.
- **Pflicht-Art nicht erfasst:** Bestätigungsdialog (§3.3), kein harter Block.
- **Katalog leer / Filiale hat keine Arten:** Fremdgeld-Sektion erscheint nicht → Flow wie heute.
- **Art nach Erfassung archiviert:** historische Werte bleiben über `typeName`-Snapshot lesbar; Auswertung gruppiert weiter nach `typeId`.

### 7.3 Was bleibt **explizit unverändert** (Nicht-Verfälschungs-Garantie)

- `PosDailyStat` (alle Felder), `functions/oktopos_stats.js`, `daily_closing.dart`-Umsatzlogik.
- `kasse_report.dart` **alle bestehenden KPIs** (`umsatzBrutto/Netto`, `rohertrag*`, `wareneinsatz*`, `delta*`, `nettoUnsicher`) — Fremdgeld ist ein **zusätzlicher** Block, keine Änderung an `_PeriodAgg`/Bucketing.
- `cashExpectedCents`, `cashCountedCents`, `cashDifferenceCents` und deren **Journal-Buchung** (`cash_difference_posting.dart`, `daily_closing_posting.dart`) — Fremdgeld fließt **nie** in diese Rechnung oder Buchung.
- `countedCents` bleibt „eigenes Bargeld-Ist" (ohne Fremdgeld).

### 7.4 Migration

- **Kein Backfill nötig.** Alle neuen Felder sind **nullable/optional** und werden **weggelassen**, wenn leer:
  - `SiteDefinition.thirdPartyCashConfig == null` → keine Arten aktiv → heutiges Verhalten.
  - `CashCount.thirdPartyAmounts == null`, `CashClosing.thirdPartyAmounts == null` → Bestandszählungen/-abschlüsse unverändert lesbar (`fromFirestore` tolerant, fehlendes Feld → `null`).
  - `OrgSettings.thirdPartyCashTypes` fehlt → leerer Katalog.
- **Optionaler Seed (nicht erzwungen):** Ein Admin-Button „Standardkategorien anlegen" seedet `[Lotto, Post, KVG]` in den Katalog (deaktiviert je Filiale, bis der Admin aktiviert). Rein additiv, keine automatische Aktivierung.
- **Rules-Deploy zuerst:** Die `keys().hasOnly(...)`-Erweiterung um `thirdPartyAmounts` muss **vor** dem ersten Client-Write mit dem neuen Feld deployt sein, sonst Deny. (`firestore.rules` deploy vor App-Rollout.)

---

## 8. Tests

### 8.1 Engine-/Reiner-Kern-Test (Trennung Kasse ↔ Dritte-Hand)

- **`cash_state`-Test:** `sollCents`/`differenceCents` sind **invariant** gegenüber `thirdPartyAmounts` — eine Zählung mit und ohne Fremdgeld ergibt **identische** eigene-Kasse-Differenz. Kernnachweis der Nicht-Verfälschung.
- **`CashClosing.fromDailyClosing`-Test:** `cashDifferenceCents == counted − cashExpectedCents` unabhängig von `thirdPartyAmounts`; `thirdPartyAmounts` wird 1:1 durchgereicht.
- **`kasse_report`-Test:** eine Periode mit Fremdgeld-`CashClosing`s → **alle** bestehenden KPIs identisch zu einer Vergleichsperiode ohne Fremdgeld; neuer `ThirdPartyPeriodAgg` korrekt aggregiert (Σ je Art, Gesamt, Anteil). `FakeFirebaseFirestore` gibt Zahlen als `double` → keine int-Gleichheit asserten.
- **Gesamt-Geldbestand-Getter:** `countedCents + Σ amountCents`.

### 8.2 Provider-Tests

- `InventoryProvider.saveCashCount` mit `thirdPartyAmounts`: cloud-only, `StateError` im Local-Modus (wie heute); Audit auf Erfolgspfad. Fakes statt echtem Firebase.
- `FeatureFlagProvider`/`OrgSettings`-Roundtrip: `thirdPartyCashTypes` dual-serialisiert round-trippt (camelCase ↔ snake_case). `SiteDefinition.thirdPartyCashConfig` round-trippt (`toFirestoreMap`/`fromFirestore` **und** `toMap`/`fromMap`), inkl. `null`-Fall und `clearThirdPartyCashConfig`.

### 8.3 Widget-Tests (Kiosk-Flow, `de_DE`)

- `cash_count_sheet` ohne Fremdgeld-Entries → unverändert ein Feld, liefert `thirdPartyAmounts == []`.
- Mit Entries → Fremdgeld-Sektion sichtbar, Betrag pro Art eingebbar, „auf 0 setzen" funktioniert, Pflicht-Art ohne Betrag → Warn-Markierung + Bestätigungsdialog.
- Zusammenfassung zeigt Kasse | je Art | Gesamt korrekt.
- `_CashCountTile`-Flow (blind) unter `APP_DISABLE_AUTH=true` (Dev-Direkt-Write-Zweig) — Fremdgeld landet in `CashCount.thirdPartyAmounts`.

### 8.4 Functions `node:test` (erweitertes `kioskSaveCashCount`)

- Payload mit `thirdPartyAmounts` (camelCase) → Doc enthält die Liste; Person = `session.employeeId`; `expectedCents/differenceCents == null` (Blindheit intakt).
- Validierung: negativer `amountCents` → `invalid-argument`; überlange Liste → Fehler; leere/fehlende Liste → Doc ohne `thirdPartyAmounts` (rückwärtskompatibel).
- `requireKioskSession` weiterhin erzwungen (abgelaufene/ widerrufene Session → Fehler, kein Write).

---

## 9. Deploy-Reihenfolge (Blaze)

1. `firestore.rules` (erweiterte `keys().hasOnly`-Listen für `cashCounts`/`cashClosings`) — **zuerst**.
2. `functions` (erweitertes `kioskSaveCashCount`) — `node --test` grün, Region `europe-west3`.
3. App-Rollout (Models, Provider, Admin-Sheets, Sheet-Umbau, Kassenbericht-Block).
4. **Kein Index nötig** (keine neue `where+orderBy`-Query; Fremdgeld liegt eingebettet, wird mit den vorhandenen `cashClosings`-/`cashCounts`-Reads geladen).
5. **Kein Backfill.** Optionaler Katalog-Seed durch Admin nach Rollout.

---

## 10. Offene Punkte / bewusste V1-Grenzen

- **Fremdgeld-Soll** (tagesscharfe Erwartung je Art) = **nicht in V1** (kein POS-Kategorie-Feed). Ausbaustufe: optionales `expectedCents` je `ThirdPartyAmount` + Fremdgeld-`CashState`-Analog.
- **Fremdgeld-Abschöpfung/Abrechnung** (Übergabe an Lotto/Post) = nicht modelliert; V1 ist reine tägliche Bestandserfassung.
- **Kein eigenes Finanzjournal-Konto für Fremdgeld** in V1 (Durchlaufposten wird nicht gebucht). Falls buchhalterisch nötig, später als separate, klar als „Verbindlichkeit gegenüber Dritten" gekennzeichnete Buchung — **niemals** über die Umsatz-/Kassendifferenz-Buchung.
- **Numpad-Variante** (eigenes On-Screen-Numpad je Betrag vs. System-Tastatur) im Kiosk final in der Umsetzung testen; Tablet-first spricht für eigenes Numpad, Konsistenz mit Kassenbetrag spricht für das große `TextField` — Empfehlung: eigenes Numpad, aber A/B am Gerät verifizieren.
