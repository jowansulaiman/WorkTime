# OktoPOS — Nächste sinnvolle Schritte

Stand: Code für **M1–M6a fertig** (Verkaufs-Pull → Bestand, Artikel-Push, Kunden-Push),
**M6b bewusst nicht** gebaut. Alles **uncommitted & undeployed**. Details:
[oktopos-kassenanbindung.md](oktopos-kassenanbindung.md).

## Prioritäten-Überblick

| Prio | Schritt | Nutzen | Aufwand | Voraussetzung |
|---|---|---|---|---|
| **P0** | Scharfschalten (commit → deploy → Freischaltung → config → Test) | Ohne das läuft nichts produktiv | klein (Code) / Setup beim Nutzer | Token, Blaze |
| **P0** | Echt-Validierung gegen reale/`demode`-Instanz (dryRun) | Bestätigt die dokumentierten Annahmen | klein | Token |
| **P1** | **Umsatz/USt/Zahlart → Buchhaltung** (Daten kommen schon mit) | DATEV-fertige Tagesumsätze, kein Abtippen | mittel | Pull läuft |
| **P1** | **Abverkaufs-Analyse** (echte Verkaufsgeschwindigkeit) | Bessere Nachbestellung, Ladenhüter erkennen | mittel | Pull läuft |
| **P1** | Functions-Test-Harness (Pull/Push/Batch absichern) | Härtung der untesteten JS-Logik | mittel | — |
| **P2** | **Artikel-Export Kasse → WorkTime** (MenuApi) | Keine Doppelpflege, falls Kasse = Artikelquelle | mittel | Richtungsentscheidung |
| **P2** | **Push-Dienst/Webhook** statt Polling | Near-realtime Bestand, weniger Kosten | mittel–groß | Hersteller-Klärung |
| **P3** | Online-Shop / Click-and-Collect → schaltet M6b frei | Neues Standbein | groß | Geschäftsentscheidung |

---

## P0 — Scharfschalten (Go-Live)

1. **Committen** (sauber in einem Branch, getrennt vom restlichen Arbeitsbaum).
2. **Freischaltung** beim OktoPOS-Support (Transaktions-Export, ArticleApi, CustomerApi) →
   API-Key(s), Base-URL, Kassen-Nr. je Laden besorgen.
3. **Blaze-Plan** aktivieren (ausgehende Calls + Secret Manager + Scheduler).
4. **Secret** setzen: `firebase functions:secrets:set OKTOPOS_API_KEYS`.
5. **Deploy:** `firebase deploy --only firestore:rules,functions`.
6. **App:** Build mit `--dart-define=APP_OKTOPOS_ENABLED=true`.
7. **Config** im Einstellungs-Sheet: Base-URL, Kassen-Nr., „Tokens laden" (Kanal/Einheit),
   Standard-USt, Kundengruppe.

## P0 — Echt-Validierung

- Erst gegen die **`demode`-Instanz** bzw. mit wenigen Datensätzen testen:
  - Verkaufs-Pull (Tagesfenster) → Bestand sinkt, Bewegungen „Kasse" sichtbar, kein Duplikat
    beim 2. Lauf.
  - Artikel-Push (`dryRun`, dann echt) → Artikel/Preis erscheint in der Kasse.
  - Kunden-Push → Kunde angelegt, 2. Lauf = „bereits vorhanden".
- **Annahmen prüfen** (siehe Hauptplan): Transaktions-Antwort Objekt vs. Array,
  `POST /articles` 409-Semantik, Einheiten-/Kanal-/Steuer-Tokens, `addressCountry`.

---

## P1 — Mehrwert aus Daten, die wir SCHON ziehen

> Der Verkaufs-Pull liefert je Beleg bereits **Brutto, USt-Aufschlüsselung, Zahlart,
> Kassierer** — wir nutzen bisher nur die Menge. Größter Hebel ohne neue Hersteller-Schnittstelle.

### P1a — Umsatz/USt → Buchhaltung/DATEV
- Im Pull zusätzlich **Tages-/Beleg-Umsätze** + USt-Sätze (`ReceiptTax`) + Zahlart erfassen
  und ins **Buchhaltung-Modul** posten (deterministische Journal-IDs → idempotent).
- Ergebnis: DATEV-fertige Tagesabschlüsse, Zahlart-Split, kein manuelles Abtippen.

### P1b — Abverkaufs-Analyse
- Aus den Verkaufspositionen **Verkaufsgeschwindigkeit je Artikel** ableiten →
  Renner/Ladenhüter, datengetriebene Nachbestellmengen (speist Bestellhäufigkeit-Modul mit
  *echten* Zahlen statt nur Bestell-Historie).
- Optional: Umsatz je Schicht/Mitarbeiter (Kassierer-Feld) — **datenschutz-sensibel**,
  separat entscheiden.

### P1c — Functions-Test-Harness
- Kleiner Node-Test (z.B. mit gemocktem `fetch` + Firestore-Emulator/Fake) für die
  untestete JS-Logik: Pagination, Batch-Idempotenz, Money→Cent, Name-Split, 409-Fallback.
- Schließt die einzige echte Test-Lücke der Anbindung.

---

## P2 — Weitere OktoPOS-Schnittstellen (Hersteller-Klärung nötig)

### P2a — Artikel-Export Kasse → WorkTime (MenuApi, read-only)
- Umgekehrte Richtung zu M5: Kassen-Katalog + Preise + Steuersätze nach WorkTime spiegeln.
- **Nur sinnvoll, wenn die Kasse die führende Artikelquelle ist** (dann keine Doppelpflege).
- Caveat: MenuApi liefert **kein** Barcode-Feld → Join über Artikelnummer/`externalReference`.
- **Entscheidung vorab:** Pflegt ihr Artikel in WorkTime (→ Push, M5) oder in der Kasse
  (→ Export, P2a)? Bidirektional nur mit Konfliktstrategie.

### P2b — Push-Dienst / Webhook für Kassentransaktionen
- Im OktoPOS-Menü existiert „Push Dienst für Kassentransaktionen" (noch nicht recherchiert).
- Falls echter Webhook: **HTTPS-Function als Empfänger** → Verkäufe near-realtime statt
  nächtlichem Polling → frischerer Bestand, sofortige Leer-Warnung, geringere Firestore-Kosten.
- **Schritt:** beim Hersteller erfragen, ob/wie extern andockbar (Auth, Format, Retry).

---

## P3 — Geschäftliche Optionen (Entscheidung, dann Integration)

- **Online-Shop / Click-and-Collect / Take-Away-App / Self-Order-Terminal** (OktoPOS bietet
  das). Würde u.a. **M6b (Bestell-Import)** sinnvoll machen.
- Reine Geschäftsentscheidung — erst klären, ob ein Vorbestell-/Online-Kanal gewollt ist.

## Bewusst NICHT verfolgen (Nische für Tabak/Kiosk)
OktoKitchen-Anzeige, Einzeltransaktion per Belegnummer, Zeitsteuerung von Menükarten,
individuelle Material-Lieferanten-Anbindung.

---

## Empfohlene Reihenfolge

1. **P0** scharfschalten + validieren (sobald Token da ist).
2. **P1a/P1b** Umsatz/USt + Abverkauf — größter Nutzen, keine neue Freischaltung.
3. **P1c** Test-Harness parallel/danach (Härtung).
4. **P2** je nach Hersteller-Antwort (Webhook) bzw. Artikel-Quellen-Entscheidung.
5. **P3** nur bei konkretem Geschäftsplan.
