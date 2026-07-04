# OktoPOS-Datenwert — Deploy-Runbook (Scharfschalten)

Schritt-für-Schritt, um die gebaute Datenwert-Strecke (P0–P4) in den echten Betrieb
zu bringen. Was geändert wurde und deployt werden muss:

- `firestore.rules` — neuer `posReceipts`-Block (read admin/teamlead, write:false)
- `firestore.indexes.json` — `posReceipts(siteId↑, transactionDate↓)`-Index
- `functions/index.js` — schreibt `posReceipts` (inkl. cash/training, USt/Zahlart),
  `payments[]`-Erfassung, kollisionssichere Beleg-Doc-ID

Alle Änderungen sind **additiv/abwärtskompatibel** (neue Collection/Felder; keine
bestehenden Daten betroffen).

---

## A) Einmalige Voraussetzungen (nur beim ersten Mal)

1. **Blaze-Tarif aktivieren** (Firebase Console → Zahnrad → Tarif → „Blaze").
   Nötig für: ausgehende HTTPS-Calls zur Kasse, Secret Manager, Scheduler
   (nächtlicher Sync). Ohne Blaze schlägt der Functions-Deploy fehl.

2. **Firebase-CLI einrichten** (Terminal):
   ```bash
   npm install -g firebase-tools     # CLI installieren/aktualisieren
   firebase login                    # einmal anmelden
   firebase projects:list            # Projekt-ID herausfinden
   firebase use <projekt-id>         # dieses Projekt aktiv setzen
   ```

3. **Functions-Abhängigkeiten installieren** (für den Deploy nötig):
   ```bash
   cd functions && npm install && cd ..
   ```

4. **API-Key als Secret hinterlegen** (kommt NIE ins Repo):
   ```bash
   firebase functions:secrets:set OKTOPOS_API_KEYS
   # Wert eingeben: entweder der reine Key,
   # ODER bei mehreren Läden JSON: {"<siteId-A>":"keyA","<siteId-B>":"keyB"}
   ```

5. **Config-Dokument anlegen**: `organizations/{orgId}/config/oktoposSync`
   - `baseUrl` (https-URL der Kasse), `enabled: true`
   - `sites: { "<siteId>": { "cashRegisterId": <Kassen-Nr.> } }`
     (Kassen-Nr. ist bei mehreren Läden Pflicht — sonst Doppelbuchung.)
   - Geht über die App (Warenwirtschaft → Kasse → Einstellungen, wenn
     `APP_OKTOPOS_ENABLED=true` gebaut) **oder** manuell in der Firestore-Console.

---

## B) Deploy (Reihenfolge ist wichtig: Indizes/Regeln VOR Functions)

0. **Lokales Quality-Gate** (sicherstellen, dass alles grün ist):
   ```bash
   flutter analyze && flutter test
   node --check functions/index.js
   ```

1. **Regeln + Indizes hochladen:**
   ```bash
   firebase deploy --only firestore:rules,firestore:indexes
   ```
   → In der Console (Firestore → Indizes) bauen die neuen Indizes ein paar
   Minuten. **Warten, bis Status „Enabled" ist**, sonst Laufzeitfehler
   (`FAILED_PRECONDITION`) beim ersten Query.

2. **Cloud Functions hochladen:**
   ```bash
   firebase deploy --only functions
   ```
   → Beim ersten Mal ggf. Rückfragen zu Scheduler-/Secret-Berechtigungen
   bestätigen.

   (Alternativ alles zusammen: `firebase deploy --only
   firestore:rules,firestore:indexes,functions` — getrennt ist aber sicherer
   wegen der Index-Bauzeit.)

---

## C) Scharfschalten & erster Lauf

1. **App mit Flag bauen**, damit der manuelle Sync-/Kassen-Button sichtbar ist:
   ```bash
   flutter build appbundle --release --obfuscate --split-debug-info=build/symbols \
     --dart-define=APP_OKTOPOS_ENABLED=true   # + die FIREBASE_*/APP_*-defines
   ```
   Hinweis: Die neuen Admin-Auswertungen (Bestand-Insights, Sortiment,
   Besetzungs-Profil, Tagesabschluss, Laden-Benchmark, Kassierer-Prüfung) sind
   admin-only und brauchen das Flag NICHT — zeigen aber erst Daten, wenn
   `posReceipts` gefüllt sind.

2. **Ersten Sync auslösen:** in der App (Warenwirtschaft → Kasse → „Verkäufe aus
   Kasse übernehmen") ODER auf den nächtlichen Lauf warten (03:30 Europe/Berlin;
   läuft nur, wenn `config/oktoposSync.enabled == true`).

---

## D) Verifizieren

- Firestore-Console: Dokumente unter `organizations/{orgId}/posReceipts`?
- Functions-Logs: `firebase functions:log` → Eintrag `oktopos_sync_done` mit
  `receiptsPersisted > 0`.
- App (Admin): Bestand-Insights / Tagesabschluss zeigen jetzt Zahlen.

---

## E) Sicherheit / Rollback

- Regeln & Functions sind additiv → kein Risiko für bestehende Daten.
- Rollback Functions: vorherige Version in der Console „Wiederherstellen" oder
  `git revert` + erneut deployen.
- Der entfernte `businessDay`-Index ist harmlos (keine Query nutzt ihn).

## F) Noch offen NACH dem Deploy (kein Blocker fürs Scharfschalten)

- **Kassen-Geldfelder gegen OktoPOS-Swagger verifizieren**, bevor man
  Marge/USt/DATEV-Zahlen produktiv vertraut (Velocity/Schwund/Bestand sind
  nicht betroffen).
- **P3.2 Kassierer-Prüfung**: Logik deployt, aber Nutzung erst nach
  Mitbestimmungs-/DSGVO-Klärung.
- **P2.3 Push** (FCM) und **P4.3 Open-Meteo-Wetter** sind optionale Anschlüsse.
