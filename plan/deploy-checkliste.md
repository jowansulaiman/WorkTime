# Deploy-/Auslieferungs-Checkliste — den „Shipping-Stau" abbauen

> Stand: 2026-07-08 · Zweck: Die vielen *code-fertig+getestet, aber undeployed* Module in Produktion
> bringen. Reihenfolge ist bewusst gewählt (Indizes vor Rules vor Functions vor Hosting).
>
> **Wichtig:** „undeployed" ist der Stand laut Plan-/Memory-Dokumenten. `firebase deploy` ist idempotent
> und zeigt vor dem Schreiben ein Diff — im Zweifel deployen, es schadet nicht. Produktivprojekt ist
> **Blaze** (`taskmaster-ebcez`). Diese Aktionen laufen NICHT durch Claude (Prod-Zugriff/Credentials) —
> der Betreiber führt sie aus.

## 0. Voraussetzungen (einmalig, vor dem ersten Cutover)

- [ ] **Blaze aktiv** (laut Memory bereits der Fall) — bestätigen (`firebase projects:list`, Billing).
- [ ] **Secret Manager**: `OKTOPOS_API_KEYS` gesetzt (für OktoPOS-Outbound, `X-API-KEY`). Nie im Client.
- [ ] **APNs Auth Key** in Firebase (iOS-Push) hochgeladen; Android FCM automatisch.
- [ ] **Config-Docs** angelegt: `config/oktoposSync` (baseUrl/cashRegisterId/Tokens), `config/orgSettings`
      (Auto-Plan-Einstellungen — Default `enforceHourCapHard=false`/weich seit W2).
- [ ] **VAPID-Key** (optional, Web-Push): `APP_WEB_PUSH_VAPID_KEY` + Web-Config im Service-Worker.

## 1. Deploy-Reihenfolge (ein Durchlauf, idempotent)

```bash
# 1. Indizes ZUERST (24 vorhanden; CLAUDE.md kannte 14 → ~10 neue). Neue where+orderBy-Queries
#    laufen sonst auf Laufzeitfehler. Nach Deploy warten, bis Firebase-Konsole „Enabled" zeigt.
firebase deploy --only firestore:indexes

# 2. Firestore-Rules (Kontakte, Personal/employeeProfiles, Push notificationPrefs,
#    sollzeitProfiles-read, workEntries-Freigabe-Semantik). Muss VOR den Clients live sein.
firebase deploy --only firestore:rules

# 3. Storage-Rules (Personal-/Kontakte-Dokument-Upload).
firebase deploy --only storage

# 4. Functions (plain JS, kein Build-Step). Enthält u.a.:
#    - overtimeMinutes in parseShift/toFirestoreShift/fromFirestoreShift  ⚠ SIEHE UNTEN
#    - OktoPOS (pushOktoposArticles/syncOktoposTransactions/oktoposNightlySync/pushOktoposCustomers/getOktoposLookups)
#    - Kassen (rebuildPosDailyStats + Aggregate)
#    - Push (fanOutPush + onDocument-Trigger)
#    - Passwortmanager (listPasswordEntries)
firebase deploy --only functions

# 5. Backfill NACH functions (Kassen-Modul): rebuildPosDailyStats einmalig aufrufen,
#    sonst fehlen historische Tagesstatistiken.

# 6. Web-Hosting — flutter clean ist PFLICHT (sonst droppt web_plugin_registrant neue Web-Plugins still)
flutter clean && flutter pub get
flutter build web --release --dart-define-from-file=firebase.prod.json
firebase deploy --only hosting
```

### ⚠ overtimeMinutes-Sonderfall (der dringendste Punkt)
`toFirestoreShift` in `functions/index.js` ist **destruktiv**: solange die Functions das neue Feld nicht
kennen, **löscht jeder Callable-Update `overtimeMinutes` wieder**. Bis Schritt 4 gelaufen ist, trägt nur
der Direkt-Write-/Local-Pfad das Feld. → Functions-Deploy nicht aufschieben.

## 2. dart-defines scharfschalten (NACH der Infra)

| Flag | Wert | Voraussetzung |
|---|---|---|
| `APP_PUSH_ENABLED` | `true` | APNs-Key hochgeladen, fanOutPush + Trigger deployt |
| `APP_OKTOPOS_ENABLED` | `true` | `OKTOPOS_API_KEYS`-Secret + `config/oktoposSync` gesetzt |
| `APP_WEB_PUSH_VAPID_KEY` | `<key>` | nur Web-Push (optional) |
| `APP_ESL_ENABLED` | **aus lassen** | ESL-Hardware/Entscheidung offen (siehe esl-preisschilder-minew.md) |

## 3. Modul-für-Modul (was jedes braucht + Verifikation)

| Modul | Deploy-Bedarf | Nachlauf | Smoke-Test |
|---|---|---|---|
| **Schichtplaner overtimeMinutes** (heute committed) | functions | — | Auto-Plan über Vertrags-Max → Überstunden-Badge bleibt nach Callable-Save |
| **Push-Benachrichtigungen** | functions + rules(notificationPrefs) | APNs-Key, `APP_PUSH_ENABLED` | Testevent → Push auf Gerät |
| **OktoPOS-Kassenanbindung** | functions | Secret + `config/oktoposSync`, `APP_OKTOPOS_ENABLED` | Verkaufs-Pull senkt Bestand; Artikel-Push idempotent |
| **Kassen-Modul** | functions + rules | **rebuildPosDailyStats-Backfill** | Tagesabschluss zeigt Aggregate |
| **Passwortmanager + Dritte-Hand-Kasse** | functions + rules | Cloud-KMS-Key (Envelope) | listPasswordEntries entschlüsselt |
| **MHD-/Ablauf-Warnung** | functions(nightly) + rules | Scheduler | Ablauf-Batch erzeugt Warnung/Push |
| **Kontakte AllTec 1:1** | rules + storage | — | Kontakt-Detail-Tabs, Doku-Upload |
| **Personalbereich AllTec 1:1** | rules + storage | — | Personalakte-Upload, 9 Tabs |

## 4. Nach dem Deploy

- [ ] Je Modul einen **Smoke-Test** in Prod (Tabelle §3).
- [ ] **Mobile-Release** obfuskiert bauen (`--obfuscate --split-debug-info=build/symbols`), Symbole
      aufheben (NICHT committen — `build/symbols/` ist gitignored).
- [ ] CLAUDE.md-Index-Zahl aktualisieren (Composite-Indexes 14 → 24).
- [ ] In MEMORY.md die betroffenen Modul-Einträge von „offen Deploy" auf „live" umschreiben.

## 5. Bewusst NICHT in diesem Cutover

- **ESL-Preisschilder** — Hardware (Gateway) + Minew-Antworten fehlen; Entscheidung offen.
- **Compliance-Bypass-Härtung** (direkte Rules-Writes umgehen Callable-Validierung) — eigener Schritt.
- **CI-Pipeline** — separates Qualitäts-Thema, kein Deploy.
