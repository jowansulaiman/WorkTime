# OktoPOS-Anruf – Checkliste

**Ziel:** Kasse (OktoPOS Manager) mit der WorkTime-App verbinden.
**Stand:** Die Anbindung ist in der App **fertig programmiert**. Es fehlen nur noch die
**Zugangsdaten + Freischaltungen von OktoPOS**. Genau die holst du dir mit diesem Anruf.

---

## In einem Satz (falls sie fragen, was du willst)

> „Ich möchte die **Hersteller-API des OktoPOS Manager** nutzen, um die **Verkäufe meiner
> Kasse automatisch in mein Warenwirtschaftssystem** zu übernehmen (und später Artikel/Preise
> und Kundendaten von dort **in die Kasse** zu schreiben). Dafür brauche ich die Schnittstelle
> freigeschaltet, einen **API-Key**, die **Basis-URL meiner Instanz** und die **Kassen-Nummern**."

---

## ✅ Das MUSS ich aus dem Gespräch mitnehmen (harte Blocker)

Ohne diese 4 Dinge läuft nichts:

- [ ] **1. API-Key (`X-API-KEY`)**
  → Der statische Schlüssel für die Schnittstelle (kein Login/OAuth, nur dieser eine Key).
  → Frage: **Ein Key für beide Läden** oder **je Standort ein eigener Key**?
  → (Im OktoPOS Manager wird er unter „OktoPOS → System" vergeben, pro Division/Standort möglich.)
  → ⚠️ Key **niemals** per Mail unverschlüsselt / nie an Dritte. Ich hinterlege ihn sicher im Server-Tresor.

- [ ] **2. Basis-URL meiner Instanz**
  → Format `https://<meine-instanz>/v1` — die steht **nicht** in der öffentlichen Doku, ist pro Kunde anders.
  → **Muss `https://` sein** (Pflicht, sonst verweigert das System die Verbindung).

- [ ] **3. Kassen-Nummer(n) (`cash-register`) je Laden**
  → Welche Nummer hat welche Kasse / welcher Standort?
    - Strichmännchen = Kasse-Nr. ____
    - Tabak Börse   = Kasse-Nr. ____
  → ⚠️ Wichtig bei zwei Läden: Ohne eindeutige Kassen-Nr. je Laden kann ein Verkauf sonst
    im falschen Laden landen (gleicher Barcode in beiden Sortimenten).

- [ ] **4. Schnittstelle(n) freischalten** (siehe nächster Abschnitt)

---

## 🔌 Diese Schnittstellen freischalten lassen

Sag ihnen, welche der dokumentierten Schnittstellen ich brauche:

- [ ] **Transaktions-Export nach Zeitraum** *(die wichtigste – Verkäufe → Bestand)*
  → Endpunkt: `GET /v1/transactions/from/{von}/until/{bis}/page/{seite}/size/{größe}/cash-register/{kasse}`
  → **read-only**, ändert nichts an der Kasse.

- [ ] **Artikel-Import / ArticleApi** *(um Artikel, Preise & Barcodes aus meiner App in die Kasse zu schreiben)*
  → Endpunkte: `POST /v1/articles`, `.../change-prices`, `.../add-barcodes`,
    `GET /v1/articles/units`, `GET /v1/articles/distribution-channels`

- [ ] **CustomerApi** *(optional – Kundenstamm aus meiner App in die Kasse schreiben)*
  → Endpunkte: `GET /v1/customers/findByExternalIdentifier/{id}`, `POST /v1/customers`

> Wenn ich klein anfangen will: **nur der Transaktions-Export** reicht, um die Verkäufe
> automatisch in den Bestand zu ziehen. Artikel-/Kunden-Push kann später dazu.

---

## ❓ Technische Klärungen (kurz nachfragen, spart später Ärger)

- [ ] **Barcode je Verkaufsposition:** Liefert der Transaktions-Export pro Artikelzeile den
  **gescannten Barcode/EAN** (`scannedBarcode`) und/oder eine **externe Artikel-Referenz**
  (`externalReference`)? → Daran hängt die automatische Zuordnung zu meinen Artikeln.
- [ ] **Geld-Format:** Kommt der Preis als **Dezimalbetrag** (z. B. `3.50`), nicht in Cent? *(erwartet: ja, Dezimal)*
- [ ] **Trainings-/Übungsbuchungen:** Sind Test-/Trainingsbons als `training` markiert, damit ich sie rausfiltern kann?
- [ ] **Distribution-Channels & Einheiten:** Welche gültigen **Kanal-Tokens** (z. B. `INHOUSE`)
  und **Einheiten-Tokens** (z. B. „Stück") gibt es? *(brauche ich nur für den Artikel-Push;
  kann ich auch selbst über `/units` bzw. `/distribution-channels` abrufen)*
- [ ] **API-Version:** Welche Version ist aktiv? *(In der Doku gab es eine Unstimmigkeit:
  Swagger 1.0.1 vs. Redoc 1.3.0 – kurz bestätigen lassen.)*
- [ ] **Limits / Rate Limits:** Gibt es Aufruf-Beschränkungen pro Tag/Minute?
  *(Ich frage die Kasse nächtlich einmal + bei Bedarf manuell ab – sollte unkritisch sein.)*
- [ ] **Testzugang / Sandbox** vorhanden, um es gefahrlos zu testen?

---

## 💶 Organisatorisch

- [ ] **Kosten** der API-Schnittstelle (einmalig / monatlich)?
- [ ] **Freischaltdauer** – ab wann ist der Zugang nutzbar?
- [ ] **Ansprechpartner / Ticket-Nr.** für Rückfragen notieren: ____________________

---

## 📝 Notizfeld (während des Anrufs ausfüllen)

| Angabe | Wert |
|---|---|
| API-Key(s) | *(sicher separat notieren, nicht hier)* |
| Basis-URL (`https://…/v1`) | |
| Kassen-Nr. Strichmännchen | |
| Kassen-Nr. Tabak Börse | |
| Ein Key für beide / je Laden? | |
| Freigeschaltete Schnittstellen | |
| API-Version | |
| Kosten | |
| Ansprechpartner / Ticket | |

---

## Nach dem Anruf – was ICH dann mache (zur Info, kein Kassen-Thema)

1. **Blaze-Plan** bei Firebase muss aktiv sein (ausgehende Calls + Secret Manager + Scheduler).
2. API-Key sicher hinterlegen (Server-Tresor `OKTOPOS_API_KEYS`) – **nie** in der App.
3. In der App unter **Warenwirtschaft → Menü „Kasse" → Einstellungen**: Basis-URL + Kassen-Nr. je Laden eintragen.
4. Funktionen deployen, App-Schalter `APP_OKTOPOS_ENABLED=true` setzen.
5. Testlauf: **„Verkäufe aus Kasse übernehmen"** auslösen → Bestand prüfen. Danach läuft es nächtlich (03:30) automatisch.

> Details dazu stehen im Anbindungsplan: `plan/archiv/oktopos-kassenanbindung.md`.
