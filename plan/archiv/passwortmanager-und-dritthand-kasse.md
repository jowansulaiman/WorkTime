# Plan: Passwortmanager für Mitarbeiter + Dritte-Hand-/Treuhand-Beträge im Kassenzählen

**Datei-Ablage:** `plan/passwortmanager-und-dritthand-kasse.md`
**Status:** Entwurf / Konzept — **nur Planung, kein Code**. Umsetzungsreif (Feld-, Callable-, Rules-Skizzen enthalten).
**Datum:** 2026-07-03
**Zielumgebung:** Blaze (Secret Manager, Cloud Functions, Admin SDK, Scheduler — alles bereits durch OktoPOS/Kiosk/Push etabliert).
**Region:** `europe-west3` (muss `const REGION` in [functions/index.js:20](functions/index.js#L20) entsprechen — Kopplung #8).

> **Getroffene Entscheidungen (03.07.2026):**
> 1. **Passwortmanager-KEK: Cloud KMS (HSM)** — der Key-Encryption-Key verlässt das HSM nie; DEK-Wrap/Unwrap über KMS `encrypt`/`decrypt`, native Key-Versionierung/Rotation. (Secret-Manager-Variante verworfen.)
> 2. **Dritte-Hand-Kasse v1: Minimal-Variante** — Katalog **und** Filial-Aktivierung zusammen an `SiteDefinition.thirdPartyCashTypes`; **kein** `OrgSettings`-Katalog, **kein** zweiter Admin-Screen. (Org-weiter Katalog bleibt späterer Refactor > 3 Filialen.)

> **Entstehung & Härtung:** Dieser Plan wurde gegen den Ist-Code verankert (alle zitierten Datei:Zeile-Belege verifiziert) und durch ein adversariales **Security-Review** (OWASP MASVS / Krypto-Auditor) sowie ein **Plan-/Kopplungs-Review** geschärft. Wo das naive Erst-Design zu schwach war (z. B. Metadaten client-streamen, weiche Reauth, `contacts`-RBAC-Muster), enthält dieser Plan bereits die **korrigierte, gehärtete Variante**. Kritische Review-Fixes sind als `⚠ Review-Fix` markiert.

---

## 1. Zusammenfassung

Zwei fachlich unabhängige Funktionen, ein gemeinsames Design-Fundament (Strichmännchen-Farbpalette, Blaze-Backend, Zwei-Serialisierungs-Regel, Callable = validierter Pfad).

**Teil 1 — Passwortmanager für Mitarbeiter.** Ein sicherer, mandantenfähiger Zugangsdaten-Tresor. Mitarbeiter speichern **eigene** Passwörter; der Admin stellt **zentrale** Zugangsdaten (KVG, Lotto, Post, Lieferantenportale, interne/Behördensysteme) bereit und weist sie **Mitarbeitern, Rollen oder Filialen** zu; optional verwalten Filialleiter Passwörter der eigenen Filiale. Kernprinzip: **Klartext verlässt nie den Server, außer bei einem autorisierten, zeitlich begrenzten, auditierten „Anzeigen"-Vorgang.** Serverseitige Envelope-Verschlüsselung (`node:crypto` AES-256-GCM für die Daten, **Cloud KMS** wrappt den pro-Eintrag-DEK — der KEK verlässt das HSM nie). Rollenbasierte Sichtbarkeit, dediziertes fälschungssicheres Zugriffsprotokoll.

**Teil 2 — Dritte-Hand-/Treuhand-Beträge im Kassenzählen (Tablet-Arbeitsmodus).** Beim Kassensturz am geteilten Store-Tablet (Kiosk) und im Tagesabschluss der Leitung wird zusätzlich zur eigenen Kasse ein **separater, additiver Block „Dritte Hand / Fremdgelder"** erfasst (Lotto, Post, KVG, externe Dienste). Fremdgeld ist ein **Durchlaufposten** — physisch in der Lade, wirtschaftlich Dritten gehörend. **Härteste Invariante:** Fremdgeld fließt **niemals** in Umsatz-, Rohertrags-, USt- oder Kassendifferenz-Aggregate. Pro Filiale konfigurierbare Kategorien, getrennte Speicherung, getrennte Auswertung im Kassenbericht, keine Verfälschung bestehender Berichte, kein Backfill.

**Gemeinsames Designsystem:** Beide Features nutzen **1:1 die bereits im Projekt hinterlegte Strichmännchen-Palette** ([lib/theme/strichmaennchen_tokens.dart](lib/theme/strichmaennchen_tokens.dart) `StrichTokens`, byte-identisch mit `/Users/jowan/Documents/dev/Strichmänschen/styles.css` — 12/12 Hex verifiziert). Kein Hex im Screen; Status über `appColors`; Danger über `colorScheme.error`.

---

## 2. Ziel der Funktionen

| # | Ziel | Nutzen |
|---|---|---|
| **PM-1** | Mitarbeiter finden & verwalten eigene Zugangsdaten sicher an einem Ort | Schluss mit Passwörtern auf Zetteln/Chat/Notizen |
| **PM-2** | Admin stellt zentrale Zugangsdaten filial-/rollen-/personengenau bereit | Onboarding, Vertretung, Portale (KVG/Lotto/Post/Behörden) ohne Passwort-Weitergabe per Zuruf |
| **PM-3** | Zugriff nur nach Berechtigung, jede Anzeige/Kopie revisionssicher protokolliert | DSGVO/Innentäter-Schutz, Nachvollziehbarkeit |
| **PM-4** | Passwörter nie im Klartext gespeichert/geloggt/unautorisiert ausgegeben | Kein Klartext-Leak bei Datenbank-/Backup-/Log-Zugriff |
| **DH-1** | Fremdgelder beim Kassenzählen sauber getrennt erfassen | Kasse und Treuhandgelder nicht mehr vermischt |
| **DH-2** | Klare Sicht auf Kassenbestand vs. Dritte-Hand-Beträge vs. Gesamtgeld in der Lade | Zählende & Leitung sehen sofort, was wem gehört |
| **DH-3** | Auswertung „eigene Kasse vs. externe Dienste" im Kassenbericht | Betriebswirtschaftliche Trennung, korrekte Zahlen |
| **DH-4** | Bestehende Kassenberichte/Buchungen bleiben **unverändert** | Keine Schein-Differenzen, keine Falsch-Buchungen |

---

## 3. Benutzerrollen

Bestehende Rollen aus [lib/models/app_user.dart](lib/models/app_user.dart) (`isAdmin`, `canManageShifts`/teamlead-Signale, aktiver Mitarbeiter). Kiosk-Geräte­konto ist eine **Sonderidentität** (dauerhaft „aktiv") — für den Passwortmanager bewusst **ausgeschlossen**.

### Teil 1 — Passwortmanager

| Rolle | Rechte |
|---|---|
| **Mitarbeiter (employee)** | Eigene (`personal`) Einträge anlegen/bearbeiten/löschen/anzeigen; **freigegebene** (`shared`) Einträge sehen & anzeigen, wenn ihm/seiner Rolle/seiner Filiale zugewiesen. Sieht **nie** fremde persönliche oder nicht-freigegebene Einträge. |
| **Filialleiter / Teamleitung (teamlead)** | Optional (Feature-Flag `passwordTeamleadEnabled`, Default aus): zusätzlich zentrale Einträge **der eigenen Filiale** anlegen/bearbeiten und anzeigen. Ohne Flag = wie Mitarbeiter. |
| **Admin** | Vollzugriff: zentrale (`shared`) Einträge erstellen/bearbeiten/löschen und **Mitarbeitern, Rollen oder Filialen zuweisen**; alle Einträge anzeigen; Zugriffsprotokoll lesen. |
| **Kiosk-Gerätekonto** | **Kein Zugriff** — Passwörter erscheinen nie am geteilten Tablet (Rules `!isKiosk()` / `if false`). Bewusste Sicherheitsgrenze. |

### Teil 2 — Dritte-Hand-Kasse

| Rolle | Rechte |
|---|---|
| **Mitarbeiter (am Kiosk, Session)** | Fremdgeld-Beträge beim Kassenzählen **erfassen** (blind, wie die Kassenzählung). Person server-authoritativ aus der Kiosk-Session. |
| **Teamleitung / Admin (Tagesabschluss)** | Fremdgeld erfassen im Tagesabschluss-Screen (offen, optional mit Soll); Abschluss festschreiben. |
| **Admin** | Fremdgeld-Kategorien **verwalten** (anlegen/umbenennen/deaktivieren) und pro Filiale **aktivieren**; Auswertung im Kassenbericht sehen. |

**Kein neuer Permission-Getter für Teil 2 nötig** — die Rechte spiegeln exakt die bestehende Kassen-Rechtematrix ([daily_closing_screen.dart:287](lib/screens/daily_closing_screen.dart#L287) `isAdmin || isTeamLead`).

---

## 4. Fachliche Anforderungen

### Teil 1 — Passwortmanager

- **PM-F1** Mitarbeiter: eigene Passwörter anlegen, bearbeiten, löschen.
- **PM-F2** Admin: zentrale Passwörter anlegen/bearbeiten/löschen + Mitarbeitern/Rollen/Filialen zuweisen.
- **PM-F3** Filialleiter (optional, Flag): Passwörter für die eigene Filiale verwalten.
- **PM-F4** Kategorien: `KVG`, `Lotto`, `Post`, `Lieferantenportal`, `Internes System`, `Behördenportal`, `Sonstige`.
- **PM-F5** Sortierung nach Kategorie / Filiale / Mitarbeiter (Owner) / Dienst (Titel) / zuletzt geändert.
- **PM-F6** Volltextsuche (über die **sichtbaren** Metadaten: Titel, Filiale, Kategorie).
- **PM-F7** Zugangsdaten kopieren (Benutzername / Passwort) — protokolliert.
- **PM-F8** Kein Dauer-Klartext: Passwort nie in Liste/Detail sichtbar; nur über „Anzeigen".
- **PM-F9** „Anzeigen" mit kurzer Sicherheitsbestätigung (Reauth), zeitlich begrenzt (Auto-Hide).
- **PM-F10** Optional: Zwischenablage nach kurzer Zeit automatisch leeren (plattformabhängig, ehrlich kommuniziert).
- **PM-F11** Optional: Hinweise, wenn Passwörter alt / schwach / mehrfach verwendet sind — **ohne Klartext-Leak** (§13/§ Health).

### Teil 2 — Dritte-Hand-Kasse

- **DH-F1** Beim Kassenzählen zusätzlicher Bereich „Dritte Hand / Fremdgelder", optisch klar von der Kasse getrennt.
- **DH-F2** Pro Filiale konfigurierbar, welche Dritte-Hand-Arten angeboten werden (Admin verwaltet; pro Filiale aktivieren/deaktivieren).
- **DH-F3** Optional Pflichtfelder/Hinweise, wenn eine Filiale z. B. Lotto oder Post aktiviert hat.
- **DH-F4** Mitarbeiter tragen Beträge ein; getrennt von der eigentlichen Kasse gespeichert.
- **DH-F5** Klar sichtbar: Kassenbestand · Dritte-Hand-Beträge (je Art) · Gesamtsumme Geldbestand · Differenzen.
- **DH-F6** Auswertung zeigt: welcher Teil eigene Kasse, welcher Teil externe Dienste.
- **DH-F7** Beträge einfach ergänzen/ändern/auf 0 setzen; klare Zusammenfassung vor Abschluss.
- **DH-F8** Fehlende/ungewöhnliche Werte verständlich markiert (Pflicht-Art ohne Betrag, unplausibel hoch).
- **DH-F9** Bestehende Kassenberichte dürfen **nicht** verfälscht werden.

---

## 5. Sicherheitsanforderungen

### Teil 1 — Passwortmanager (kryptografischer Kern)

- **PM-S1 Serverseitige Verschlüsselung.** Klartext existiert nur transient im Function-Prozess. Speicherung ausschließlich als AES-256-GCM-Ciphertext. **Keine** Client-seitige Krypto (Begründung §5.4).
- **PM-S2 Envelope-Verschlüsselung.** Pro Eintrag ein frischer **Data Encryption Key (DEK)**, gewrappt mit einem **Key Encryption Key (KEK)**. DEK nie im Klartext gespeichert.
- **PM-S3 KEK via Cloud KMS (entschieden).** Der Key-Encryption-Key liegt als symmetrischer CryptoKey in einem KMS-Keyring (Region `europe-west3`) und verlässt das HSM **nie** — DEK-Wrap/Unwrap laufen als KMS-`encrypt`/`decrypt`-Aufrufe, der Klartext-KEK ist im Function-Prozess **nicht** präsent (Vorteil ggü. Secret-Manager-KEK: keine Heap-/Memory-Forensik-Fläche, kein menschlicher `secrets:access`). **IAM:** der Function-Service-Account braucht `roles/cloudkms.cryptoKeyEncrypterDecrypter` **nur** auf diesem Key; kein weiterer Principal. **Rotation nativ** (automatische KMS-Key-Versionen; alte Versionen entschlüsseln Alt-Ciphertexte weiter). Package `@google-cloud/kms` zu [functions/package.json](functions/package.json). **AAD:** `orgId|entryId` als `additionalAuthenticatedData` an KMS `encrypt`/`decrypt` gebunden (Confused-Deputy-Schutz).
- **PM-S4 Zugriff nur nach Berechtigung.** Sichtbarkeit **server-authoritativ** geprüft, **live** gegen `employeeSiteAssignments`/`audienceUids`/`audienceRoles` (nie gegen materialisierte Optimierungs-Kopien als Autorität — ⚠ Review-Fix B3).
- **PM-S5 Klartext-Ausgabe nur autorisiert + auditiert.** Einziger Ausgabepfad: `revealPasswordSecret`-Callable. Zeitlich begrenzt (Auto-Hide-Timer), server-erzwungene Reauth.
- **PM-S6 Reauth server-durchgesetzt.** ⚠ **Review-Fix (H3):** **Harte** Reauth (server-signierter Einmal-Nonce via `beginPasswordReauth`, TTL 60 s, `timingSafeEqual`) ist **Default**, nicht Option. `local_auth` (Biometrie/Geräte-PIN) ist nur **zusätzliche** Gerätehürde. **Auf Web** hat `local_auth` keinen kryptografischen Wert → harte Reauth dort erzwingen (frisches ID-Token / `reauthenticateWithCredential`, serverseitige `auth_time`-Prüfung).
- **PM-S7 Kein Klartext in Logs/Fehlern/API-Antworten** (außer der autorisierten Reveal-Antwort). Klartext-Buffer in `finally` nullen; Entschlüsselungs-Exceptions ziehen nie den Klartext in die Message (`truncateError`-Disziplin [functions/index.js:4351](functions/index.js#L4351)).
- **PM-S8 App Check ≠ Autorisierung.** ⚠ **Review-Fix (B2):** `enforceAppCheck:true` **explizit** an allen Passwort-Callables (nicht vererbt — nur Kiosk-Callables setzen es heute) **plus** eigenständige serverseitige Autorisierung.
- **PM-S9 Rate-Limit & Brute-Force-Schutz.** ⚠ **Review-Fix (H4):** Reveal transaktional gezählt (`runTransaction`), **globales** Tages-Budget pro Nutzer + pro-Eintrag-Limit (~5/min), Reauth-Nonce-Fehlversuche zählen & sperren (Muster `KIOSK_MAX_PIN_ATTEMPTS` [functions/index.js:1104](functions/index.js#L1104)). Anomalie-Alarm an Admin bei Massen-Reveal.
- **PM-S10 Screenshot-Schutz.** ⚠ **Review-Fix (N1):** Reveal-Sheet mit `FLAG_SECURE` (Android) / `isSecureTextEntry`-Äquivalent (iOS). Dart-String-Immutabilität → kein sicheres Client-Wipe möglich (ehrlich als Grenze dokumentiert; Auto-Hide + kein Provider-State ist das Maximum).
- **PM-S11 Kein lesbarer Klartext-Kanal in Metadaten.** ⚠ **Review-Fix (H1/H2/M5):** `notes`, `username`, `password`, `strengthMeta` (Länge/Zeichenklassen), `dupGroupHash`, `keyVersion` **nie** in client-lesbare Metadaten. Nur strukturierte Metadaten (Titel/Kategorie/Filiale/URL).
- **PM-S12 Löschung & Backups.** ⚠ **Review-Fix (H5):** Krypto-Shredding: Löschen entfernt `passwordEntries` + `passwordSecrets` atomar. **Restrisiko dokumentiert:** Firestore-Backups/PITR enthalten das (verschlüsselte) Secret weiter, solange die KEK-Version existiert → Backup-Retention der `passwordSecrets` ist Betreiber-Aufgabe.

### Teil 2 — Dritte-Hand-Kasse

- **DH-S1 Getrennte Speicherung.** Fremdgeld als eigener, additiver `thirdParty`-Block — nie in `countedCents`/`cashExpectedCents`/`cashDifferenceCents`/`revenueGrossCents`.
- **DH-S2 Kiosk-Blindheit erhalten.** Fremdgeld-Erfassung am Kiosk blind (kein Soll/keine Differenz sichtbar). Server erzwingt `expectedCents = null` ([functions/index.js](functions/index.js) `kioskSaveCashCount`).
- **DH-S3 Person server-authoritativ.** `countedByUserId = session.employeeId` aus der validierten Kiosk-Session — Fremdgeld ist reine Client-Eingabe wie Betrag/Notiz, kein neuer Vertrauenspfad.
- **DH-S4 Keine Falsch-Buchung.** `cash_difference_posting.dart` / Finanzjournal bleiben Fremdgeld-frei.

---

## 6. UI/UX-Konzept

### Teil 1 — Passwortmanager (Bereich `/passwoerter`, Profil/Hub)

**Liste (Kartenlayout `<840dp`):**
- AppBar „Passwörter" + `AppSearchField` (Suche über sichtbare Metadaten).
- **Filter-Chips:** Kategorie (`ChoiceChip`-Reihe), Filiale (Dropdown aus `sites`), Scope (Eigene / Freigegeben / Zentral).
- **Sortierung:** „Kategorie · Filiale · Dienst · Zuletzt geändert".
- **Karte je Eintrag:** Kategorie-Icon + Titel; Untertitel `Filiale`; Trailing `Icons.visibility_outlined` (Anzeigen) + Overflow (Bearbeiten/Löschen bei Recht). **Nie Klartext in der Liste.** Health-Badge (schwach/alt/doppelt) nur als grobes Signal (§ Health).
- Leerzustand über `AppErrorState`/`_EmptyState`.

**Editor-Sheet** (`showModalBottomSheet(showDragHandle:true, isScrollControlled:true, useSafeArea:true)`):
- Abschnitte: **Dienst** (Titel, Kategorie-Chips, URL) · **Zuordnung** (Filiale, Scope personal/shared) · **Zielgruppe** (nur bei `shared` + Recht: Mitarbeiter/Rolle/Filiale) · **Zugangsdaten** (Benutzername, Passwort mit Show/Hide **im Editor**, Notiz) · **Sicherheit** (Passwort-Generator optional).
- Bearbeiten ohne Passwortänderung: Passwortfeld leer → Secret unberührt (reines Metadaten-Update über Callable).

**Reveal-Flow (PM-F8/F9, PM-S5/S6/S10):**
1. „Anzeigen" → **harte Reauth** (server-Nonce; zusätzlich `local_auth` auf Mobile).
2. `revealPasswordSecret` → Klartext transient im Sheet-`State`.
3. **Auto-Hide-Countdown** (z. B. 30 s) → Klartext aus Widget-State entfernt, Sheet maskiert/schließt. `FLAG_SECURE` aktiv.
4. **Copy** → `Clipboard.setData` → `logPasswordCopy` → Toast „In Zwischenablage kopiert" (Auto-Clear-Hinweis **plattformabhängig** formuliert — ⚠ Review-Fix N2: auf Web kein falsches Versprechen).

**Zielgruppen-Picker (PM-F2):** drei Sektionen Mitarbeiter (Multi-Select Roster → `audienceUids`) / Rolle (Chips → `audienceRoles`) / Filiale (Multi-Select `sites` → `audienceSiteIds`, server materialisiert zusätzlich `audienceUids`).

### Teil 2 — Dritte-Hand-Kasse (Tablet-Arbeitsmodus, Kern)

**Ablauf am Kiosk** ([kiosk_screen.dart:689](lib/screens/kiosk/kiosk_screen.dart#L689) `_CashCountTile`):
1. **Eigene Kasse** (unverändert, blind) → `countedCents`.
2. **Dritte Hand / Fremdgelder** (NEU) — nur wenn die Filiale aktivierte Arten hat, sonst übersprungen.
3. **Zusammenfassung & Bestätigung** (NEU) → ein Speichern = ein Callable-Aufruf.

**Erweitertes `cash_count_sheet.dart` — Sektions-Layout:**

```
┌─────────────────────────────────────────┐
│  💶  Kasse zählen                         │
├─────────────────────────────────────────┤
│  EIGENE KASSE           (surfaceContainerLow)
│      [   123,45   ] €      (blind: kein Soll)
├═════════════════════════════════════════┤ ← klare Trennung
│  🤝 DRITTE HAND / FREMDGELDER  (getrennt) │   (appColors.info-getönt / tertiaryContainer)
│   Lotto              [ 0,00 ] € ✎         │
│   Deutsche Post *    [ 45,00 ] € ✎        │ ← * Pflicht-Art
│   KVG-Tickets        [ 0,00 ] € ✎         │
│   ⚠ „Deutsche Post" ist Pflicht — 0,00 €  │
│      wirkt ungewöhnlich, bestätigen?      │ (appColors.warning)
├─────────────────────────────────────────┤
│  ZUSAMMENFASSUNG                          │
│  Kasse (eigen)            123,45 €        │
│  Lotto/Post/KVG …           …             │
│  Geld in der Lade gesamt  168,45 €  (fett)│ ← grandTotal
├─────────────────────────────────────────┤
│         [  Zählung speichern  ]           │
└─────────────────────────────────────────┘
```

**Tablet-Konventionen:**
- Kassen- und Fremdgeld-Sektion in **getrennten Cards** mit unterschiedlicher Hintergrundfarbe (Status-Farben nie hardcoden → `appColors`/ColorScheme-Rollen).
- **Große Touch-Numpads** (konsistent mit dem PIN-`_NumPad`, `SizedBox(84×64)`) für die Beträge — mehrere Felder schnell nacheinander.
- Jede Zeile: „Bearbeiten" (Numpad) + „auf 0" (Long-Press/Button). Default alle Beträge 0.
- **Feste Zusammenfassung** vor Freigabe des „Speichern"-Buttons.
- **Blind bleibt blind:** Fremdgeld-Sektion am Kiosk ohne Soll/Differenz.
- **Tagesabschluss (Leitung)** nutzt dasselbe Sheet, aber **mit** Kassen-Soll und optional Fremdgeld-Soll (nur hier). Blind-Modus als **expliziter Pflicht-Parameter** `showThirdPartySoll: bool` (Kiosk immer `false` — ⚠ Review-Fix B4).

---

## 7. Designsystem und Farbübernahme aus `/Users/jowan/Documents/dev/Strichmänschen`

**Quelle der Wahrheit** ist `styles.css` (einzige Farbquelle). Die App-seitige Umsetzung liegt **bereits vollständig** in [lib/theme/strichmaennchen_tokens.dart](lib/theme/strichmaennchen_tokens.dart) (`StrichTokens`), [lib/theme/theme_extensions.dart](lib/theme/theme_extensions.dart) (`AppThemeColors`/`appColors`) und [lib/theme/app_theme.dart](lib/theme/app_theme.dart) (Strich-ColorScheme). **Neue Screens konsumieren ausschließlich diese Tokens/Rollen — kein Hex im Screen.**

### 7.1 Finale Design-Token-Tabelle (autoritativ, aus dem Referenzprojekt übernommen)

| Token | Exakter Hex | Quelle (`styles.css` / `StrichTokens`) | Flutter-Zugriff |
|---|---|---|---|
| **primary** (Marke) | `#061B36` | `--navy` :3 · `StrichTokens.primary` | `colorScheme.primary` |
| **primaryAction** (CTA-Gelb, Pill) ¹ | `#F0C738` | `--yellow` :10 (`.btn-primary` :201) · `StrichTokens.primaryAction` | `colorScheme.tertiary` / `onTertiary` |
| **secondary** | `#CAA65A` | `--gold` :9 · `StrichTokens.secondary` | `colorScheme.secondary` |
| **background** (Scaffold) | `#F4EFE4` | `--paper` :6 · `StrichTokens.background` | `colorScheme.surface` |
| **surface** (Karten) | `#FFFDF8` | `--white` :8 · `StrichTokens.surface` | `colorScheme.surfaceContainerLow`/`…Lowest` |
| **border** (Hairline) | `rgba(23,22,21,0.14)` | `--line` :14 · `StrichTokens.border` | `colorScheme.outlineVariant` |
| **text** | `#171615` | `--ink` :5 · `StrichTokens.text` | `colorScheme.onSurface` |
| **muted** | `rgba(23,22,21,0.72)` | Muted-Literale :694/915/1015 · `StrichTokens.muted` | `colorScheme.onSurfaceVariant` |
| **success** | `#2FAD64` | `.status-pill.is-open` :351 · `StrichTokens.success` | `appColors.success` (Text: `.successDeep` `#2D6D55`) |
| **warning** | `#F0C738` | `--yellow` :10 · `StrichTokens.warning` | `appColors.warning` |
| **danger** | `#B8435A` | `--rose` :11 · `StrichTokens.danger` | `colorScheme.error`/`onError` (**nicht** `appColors`) |

¹ **Doppelrolle „primary":** Marken-Identität = navy; die **Haupt-Aktions-/CTA-Füllung** ist bewusst **gelb** und liegt im Strich-ColorScheme auf `tertiary` ([app_theme.dart:1047](lib/theme/app_theme.dart#L1047)). Gelber Primär-CTA → `colorScheme.tertiary`/`onTertiary` bzw. `StrichTokens.primaryAction`/`onPrimaryAction` (Ink-Text), **nie** `primary`.

**Ergänzende Rollen (vorhanden):** `backgroundDeep #E7DCC7`, `borderStrong navy@28%`, `borderCard navy@12%`, `info #246CA0` (→ `appColors.info`), `signalGradient [#F0C738,#B8435A,#246CA0]`, `cardAccents [#CAA65A,#B8435A,#2D6D55,#246CA0]`.

### 7.2 Konsistenzprüfung: Tokens ↔ Referenzprojekt — **12/12 exakt, keine Abweichung**

navy `#061b36`, navySoft `#0b2d55`, ink `#171615`, paper `#f4efe4`, paperDeep `#e7dcc7`, white `#fffdf8`, gold `#caa65a`, yellow `#f0c738`, rose `#b8435a`, green `#2d6d55`, blue `#246ca0`, openGreen `#2fad64` — jeweils byte-identisch zwischen `styles.css` (:3–13/351) und `strichmaennchen_tokens.dart` (:27–68). **Handlungsbedarf an den Tokens: keiner.**

### 7.3 Hover-/Focus-/Button-States (aus dem Referenzprojekt)

Referenzprojekt hat **keine Farbwechsel** bei Hover/Focus (nur `transform: translateY(-2px)` + Gelb-Glow `rgba(240,199,56,0.25)` :203) und **keine dedizierte Focus-Farbe**. Flutter-Abbildung ohne Palette zu verlassen:
- **Hover:** M3-State-Layer (aktuelle `on…`-Farbe @ 8 %), kein eigenes Hex.
- **Focus:** Ring aus `colorScheme.primary` (bzw. `tertiary` bei Gelb-CTA), State-Layer @ 10 %. **A11y-Ergänzung:** sichtbarer 2 px-Ring ist Pflicht (übertrifft bewusst das Referenzprojekt — WCAG-Fokus-Sichtbarkeit).
- **Selected** (`.is-active` BG→navy/Text→white): über `secondaryContainer`/`onSecondaryContainer` bzw. `primary`/`onPrimary`.
- **Disabled/Pressed:** M3-Default.
- **Keine** `WidgetStateProperty` mit Hex-Overlays in Feature-Screens — `AppTheme.strichmaennchen(brightness)` liefert die State-Layer bereits paletten-korrekt.

### 7.4 Lücken + begründete Ergänzungen (nur wo im Referenzprojekt fehlend)

- **`danger` in `appColors`:** Der Wert existiert (`StrichTokens.danger #B8435A`), aber `AppThemeColors` hat kein `danger`-Feld → Danger läuft über `colorScheme.error` (= rose, [app_theme.dart:1054](lib/theme/app_theme.dart#L1054)). **Regel:** neue Screens nutzen `colorScheme.error`/`onError`/`errorContainer`. Kein neues `danger`-Feld einführen (würde das Kontrast-Gate `test/contrast_audit_test.dart` berühren).
- **`warning` (echte Palette-Lücke):** `styles.css` hat keinen Warn-Token. **Ergänzung (bereits verdrahtet, begründet): `warning = StrichTokens.yellow #F0C738`, `onWarning = #171615`** — Gelb ist der etablierte Marken-Aufmerksamkeits-Akzent, Ink-Text erreicht hohen Kontrast. DS2-geprüft.
- **Dark-Info:** Referenzprojekt hat keinen Dark Mode; WorkTime hellt `info` auf `#7FB0DF` auf ([theme_extensions.dart:101](lib/theme/theme_extensions.dart#L101)) — transparent über `appColors.info`.
- **Keine weiteren erfundenen Farben.** Container-/Zwischentöne per `Color.alphaBlend`/`lerp` aus Palette-Tokens.

### 7.5 Verbindliche Nutzungsregel (beide Features)

1. **Kein Hex im Screen.** Farbe kommt aus `Theme.of(context)` (ColorScheme-Rolle/`appColors`) oder — Spezialfall ohne Rolle — direkt aus `StrichTokens`.
2. **Status (success/warning/info) immer über `appColors`** (Text-Kontrast: `appColors.successDeep`).
3. **Danger/Fehler über `colorScheme.error`** (nicht `appColors`).
4. **Nur benannte ColorScheme-Rollen** für Fläche/Text/Rand. Gelber CTA → `tertiary`.
5. **Palette 1:1** — zugelassene Ergänzungen ausschließlich `warning=yellow`, dark-`info=#7FB0DF`, komponierte Container.
6. **Theme-Bezug:** neue Screens opt-in via `StrichmaennchenTheme(child:…)` wrappen (ändert den App-Default nicht), dann über `Theme.of(context)` konsumieren.
7. **Spacing/Radius/Motion** über `context.spacing`/`context.radii`/`context.motion`; Zahlen `TextStyle.tabular`.

---

## 8. Datenmodell-Vorschlag

### Teil 1 — Passwortmanager (zwei Collections unter `organizations/{orgId}/`)

⚠ **Review-Fix (B1/P0-A1):** **Metadaten werden NICHT client-gestreamt.** Sowohl Ciphertext als auch die zugriffsgestufte Liste laufen über Callables (Begründung §11). Das Metadaten-Model existiert dennoch als Dart-Klasse (für Callable-Payloads & Typisierung) und folgt der Zwei-Serialisierungs-Regel.

#### 8.1 `passwordEntries` (Metadaten)

`PasswordEntry` ([lib/models/password_entry.dart], neu). 6 Serialisierungs-Stellen (`toFirestoreMap`/`fromFirestore`/`toMap`/`fromMap`/`copyWith`+`clearX`). Callable-Payload = **snake_case `toMap()`** + separates Klartext-Feld (nie ein Model-Feld).

| Feld | Typ | camelCase | snake_case | Hinweis |
|---|---|---|---|---|
| `id` | String | (Doc-ID) | `id` | |
| `orgId` | String | `orgId` | `org_id` | Mandant |
| `title` | String | `title` | `title` | Dienstname |
| `category` | `PasswordCategory` | `category` (`.value`) | `category` | Enum §8.3 |
| `siteId` | String? | `siteId` | `site_id` | nullable → `clearSiteId` |
| `siteName` | String? | `siteName` | `site_name` | Anzeige-Snapshot |
| `ownerUid` | String | `ownerUid` | `owner_uid` | Ersteller |
| `ownerLabel` | String | `ownerLabel` | `owner_label` | Anzeige (server-gesetzt) |
| `scope` | `PasswordScope` | `scope` (`.value`) | `scope` | `personal`/`shared` |
| `audienceUids` | List\<String> | `audienceUids` | `audience_uids` | freigegebene MA (+materialisiert) |
| `audienceRoles` | List\<String> | `audienceRoles` | `audience_roles` | z. B. `['teamlead']` |
| `audienceSiteIds` | List\<String> | `audienceSiteIds` | `audience_site_ids` | freigegebene Filialen |
| `url` | String? | `url` | `url` | nullable → `clearUrl` |
| `hasSecret` | bool | `hasSecret` | `has_secret` | ob Ciphertext existiert (server-gesetzt) |
| `createdAt` / `createdByUid` | DateTime/String | camelCase | snake_case | |
| `updatedAt` / `updatedByUid` | DateTime/String | camelCase | snake_case | server-gesetzt |
| `lastRotatedAt` | DateTime? | `lastRotatedAt` | `last_rotated_at` | nullable → `clearLastRotatedAt` |

⚠ **Review-Fix (H1/H2/S11):** **Nicht** im Metadaten-Model: `username`, `keyVersion`, `strengthMeta` (Länge/Zeichenklassen), `dupGroupHash`, freies `notes`. `keyVersion`/`strengthMeta` leben ausschließlich im Secret-Doc bzw. werden nur als grobes Signal über den Callable geliefert.

#### 8.2 `passwordSecrets` (Ciphertext — `read,write:if false`)

Doc-ID **identisch** zur `passwordEntries`-Doc-ID (1:1, wie `userSecrets/{uid}`). Cloud-only, nur Admin-SDK. Klartext-Struktur vor Verschlüsselung: `{ "u": username, "p": password, "n": notes }` (ein Envelope).

```
{
  orgId, entryId,
  ciphertext, iv, authTag,            // Secret-Chiffre (node:crypto AES-256-GCM); AAD = orgId|entryId
  wrappedDek,                         // DEK, via Cloud KMS encrypt gewrappt (KMS-Ciphertext, base64); KMS-AAD = orgId|entryId
  kmsKeyVersion,                      // KMS-CryptoKeyVersion-Name — nur Audit/Diagnose (decrypt braucht ihn NICHT, KMS erkennt die Version am Ciphertext)
  encAlgo: "AES-256-GCM",
  updatedAt (Timestamp), updatedByUid
}
```

⚠ **Vereinfachung durch KMS (löst den M2-Bug des Erst-Designs strukturell):** Die Key-Versionierung übernimmt **KMS intern** — es gibt keinen app-seitigen `keyVersion`-in-AAD-Zwang mehr. Die Secret-Chiffre-AAD ist `orgId|entryId` (ohne Versionsbezug), die KMS-Wrap-AAD ebenso `orgId|entryId`. Bei KEK-Rotation entschlüsselt KMS Alt-Ciphertexte über die alte Key-Version automatisch weiter → **kein** Re-Encrypt des Klartexts nötig. `kmsKeyVersion` wird nur zur Nachvollziehbarkeit gespeichert.

#### 8.3 Enums (`.value` snake_case + `fromValue`-Default + deutsches `label`)

- **`PasswordCategory`:** `kvg`→„KVG", `lotto`→„Lotto", `post`→„Post", `supplierPortal`→`supplier_portal`/„Lieferantenportal", `internalSystem`→`internal_system`/„Internes System", `authorityPortal`→`authority_portal`/„Behördenportal", `other`→„Sonstige".
- **`PasswordScope`:** `personal` (nur Owner + Admin), `shared` (Zielgruppe via audience-Felder).
- `fromValue` mit Default-Branch (`other`/`personal`), wirft nie (Kopplung #3). Rules- und Client-Strings identisch.

#### 8.4 `passwordAccessLog` (Zugriffsprotokoll — admin-only lesbar, `write:if false`)

Siehe §12.

### Teil 2 — Dritte-Hand-Kasse

⚠ **Review-Fix (P2-B6): v1 = Minimal-Variante.** Katalog **und** Aktivierung leben zusammen an **`SiteDefinition`** — kein `OrgSettings`-Touch, kein zweiter Admin-Screen. (Der org-weite Katalog in `OrgSettings.thirdPartyCashCatalog` bleibt als späterer Refactor dokumentiert, sinnvoll erst > 3 Filialen. Bei zwei Kieler Läden ist Doppelpflege trivial.)

#### 8.5 `ThirdPartyCashType` (Kategorie-Definition, genestet in `SiteDefinition`)

**Freitext-Katalog mit stabiler `id` (kein Dart-Enum)** — sonst Code-Deploy je neuer Art (Kopplung #3). `id` ist revisionsfest, `name` änderbar. Dual-serialisiert (Nested wie `StaffingDemand`):

```dart
class ThirdPartyCashType {
  final String id;              // stabil, slug/uuid — NIE ändern
  final String name;            // 'Lotto', 'Deutsche Post', 'KVG-Tickets'
  final bool enabled;           // an dieser Filiale angeboten
  final bool required;          // Pflicht-Betrag (0 erlaubt, aber Eingabe erzwungen)
  final String? hint;           // 'Lottokasse separat zählen'
  final int sortOrder;
}
```
`toFirestoreMap`/`fromFirestore` (camelCase) + `toMap`/`fromMap` (snake_case: `required_by_default`? → hier `required`, `sort_order`).

Erweiterung `SiteDefinition` ([lib/models/site_definition.dart]): neues Feld `thirdPartyCashTypes: List<ThirdPartyCashType>` (6 Stellen, dual-serialisiert, Default `const []`). `sites`-Rules: read `sameOrg`, write admin — **kein Rules-Update nötig** (keine `hasOnly`-Allowlist auf `sites`).

#### 8.6 `ThirdPartyAmount` (erfasster Einzelbetrag, genestet in `CashCount`/`CashClosing`)

```dart
class ThirdPartyAmount {
  final String typeId;          // FK auf ThirdPartyCashType.id
  final String typeName;        // Snapshot (überlebt Umbenennung/Löschung — wie ReceiptTax/siteName)
  final int amountCents;        // Ist-Betrag >= 0
  final int? expectedCents;     // optionales Fremdgeld-Soll (nur Tagesabschluss); null = reine Ist-Erfassung
  final String? note;
}
```
Dual-serialisiert (`type_id`/`type_name`/`amount_cents`/`expected_cents`/`note`). Der **produktive Kiosk-Pfad** ist camelCase (Kiosk-Callable-Payload); snake_case für Round-Trip-Sicherheit/Tests.

#### 8.7 Erweiterung `CashCount` + `CashClosing` (je additiv, cloud-only)

Beide Modelle sind **cloud-only** (nur `toFirestoreMap`/`fromFirestore`/`copyWith`, kein snake_case — [cash_count.dart:10-13](lib/models/cash_count.dart#L10-L13)). Neu:

```dart
// CashCount + CashClosing:
final List<ThirdPartyAmount> thirdParty;              // Default const []
int get thirdPartyTotalCents => thirdParty.fold(0, (s,e)=>s+e.amountCents);

// nur CashClosing:
int get grandTotalCashCents => (cashCountedCents ?? 0) + thirdPartyTotalCents; // Geld in der Lade gesamt
```
- `fromDailyClosing(...)` bekommt Parameter `thirdParty` (aus `zaehlung?.thirdParty ?? const []`).
- ⚠ **`cashDifferenceCents` bleibt EXAKT** `counted − cashExpectedCents` ([cash_closing.dart:116-118](lib/models/cash_closing.dart#L116-L118)) — Fremdgeld fließt **nicht** ein.
- **Warum Sub-Liste statt eigener Collection:** atomarer Write (Zählung + Fremdgeld in einem `set`), additiv, minimaler Rules-/Callable-Touch, folgt dem bestehenden `taxes: List<ReceiptTax>`-Muster. **Warum nicht `denominations`:** das `Map<String,int>?`-Feld ist für Stückelung reserviert (Nennwert→Anzahl), Fremdgeld ist semantisch anders (Art→Betrag mit Typ/Pflicht/Hinweis).

---

## 9. API-/Backend-Konzept

### Teil 1 — Passwortmanager (Callables in [functions/index.js](functions/index.js), snake_case Payloads)

Wrapper `callable(name, options, handler)` ([functions/index.js:71-103](functions/index.js#L71-L103)) — `requestId`, `callable_start/done`, **loggt nie uid/E-Mail/Secret**. ⚠ Alle Passwort-Callables: `enforceAppCheck:true` **explizit** (Review-Fix B2); Verschlüsselungs-Callables zusätzlich `secrets:[…KEK…]`.

**Envelope-Ablauf (Schreiben):** frischer `dek = randomBytes(32)`, `iv = randomBytes(12)` → `aes-256-gcm(dek, iv)` mit `setAAD(orgId|entryId)` → Secret-Ciphertext + AuthTag; **DEK wrappen** über **Cloud KMS** `encrypt({name: keyName, plaintext: dek, additionalAuthenticatedData: orgId|entryId})` → `wrappedDek` (+ `kmsKeyVersion` aus der Antwort). `dek.fill(0)` sofort. **Lesen:** KMS `decrypt({name: keyName, ciphertext: wrappedDek, additionalAuthenticatedData: orgId|entryId})` → DEK → Secret entschlüsseln, DEK-Buffer in `finally` nullen. IV-Nonce-Regel: pro Op frisch, durch frischen DEK je Update keine (Key,IV)-Kollision möglich. Der KEK-Klartext ist zu **keinem** Zeitpunkt im Function-Prozess.

| Callable | Zweck | Guards / Besonderheiten |
|---|---|---|
| `listPasswordEntries` | ⚠ **Review-Fix B1:** server-gefilterte Metadaten-Liste (Ersatz für Client-Stream) | `sameOrg` + server-authoritative Sichtbarkeit (admin=alle; personal=owner; shared=`uid∈audienceUids` OR `role∈audienceRoles` OR Filiale des Callers **live** in `audienceSiteIds`). Liefert nur sichtbare Metadaten + **grobes** Health-Signal, **nie** `strengthMeta`/`dupGroupHash`/`keyVersion`. |
| `upsertPasswordEntry` | Metadaten + optional Klartext-Secret | `sameOrg`; scope-basierte Autorisierung (personal=owner/admin; shared=admin oder teamlead+eigene Filiale bei Flag); Validierung §13; Secret verschlüsseln → `passwordSecrets`; `writeAudit(created/updated)` **ohne** Klartext. Rückgabe `{entry_id}`. |
| `deletePasswordEntry` | Löschen | Recht: admin (shared) / owner-or-admin (personal). Löscht **beide** Docs atomar (`WriteBatch`). `writeAudit(deleted)`. Krypto-Shredding + Backup-Restrisiko (§5 PM-S12). |
| `beginPasswordReauth` | ⚠ **Review-Fix H3:** server-signierten Reauth-Nonce ausstellen (TTL 60 s) | Default-Pflicht vor Reveal. `timingSafeEqual`-Verifikation, Fehlversuche zählen/sperren (H4). |
| `revealPasswordSecret` | **einziger** Klartext-Ausgabepfad | siehe unten. |
| `logPasswordCopy` | Kopieren protokollieren | Sichtbarkeitsprüfung wie Reveal (ohne Entschlüsselung), `passwordAccessLog(copied)`. ⚠ **best-effort, nicht erzwingbar** (Review-Fix M3). |
| `rewrapPasswordDeks` | **Optional** (KMS rotiert nativ) — nur nötig, um eine alte KMS-Key-Version endgültig zu **deaktivieren/zerstören** | Batch ≤ 50, `assertAdmin`, idempotent/resumable (Cursor); KMS `decrypt`(alt) → `encrypt`(neu) **nur des DEK**, Secret-Klartext nie berührt; `wrappedDek`+`kmsKeyVersion` in **einem** `set(merge)`. Im Normalbetrieb nicht erforderlich. |

**`revealPasswordSecret` — Ablauf (⚠ mehrere Review-Fixes):**
1. `sameOrg` + `enforceAppCheck` (B2) + **harte Reauth-Nonce** verifizieren (H3; Web: frisches ID-Token/`auth_time`).
2. **Sichtbarkeit server-authoritativ, LIVE** gegen `employeeSiteAssignments`/`audienceUids`/`audienceRoles` — **nie** gegen materialisierte `audienceUids` als Autorität (B3: sonst behält ein versetzter Mitarbeiter Reveal-Rechte).
3. **Rate-Limit** transaktional (`runTransaction`), pro-Eintrag (~5/min) **und** globales Tages-Budget/uid (H4). Überschreitung → `resource-exhausted`.
4. ⚠ **Audit VOR Entschlüsselung** (B4): `passwordAccessLog(action:'reveal_requested')` **garantiert** schreiben → **dann** DEK unwrappen (KEK-Version aus Doc) + Secret entschlüsseln (AAD `orgId|entryId` prüfen) → **dann** `action:'revealed'` bestätigen. Klartext-Buffer in `finally` `fill(0)`. Audit-Write-Fehler → `internal`, **kein Klartext** („no reveal without record" — fail-closed, **kein** best-effort AuditSink).
5. Rückgabe `{ username, password, notes }` — bewusst, autorisiert, auditiert.

**KEK-Rotation (§ PM-S2/S3):** **KMS-nativ** — neue Primary-CryptoKeyVersion (automatisch oder manuell); Alt-Ciphertexte bleiben über die alten (aktivierten) Versionen entschlüsselbar, **ohne** App-Eingriff. `rewrapPasswordDeks` ist nur nötig, wenn eine Alt-Version endgültig **zerstört** werden soll (dann erst alle Docs auf die neue Version umwrappen). Klartext des Secrets wird dabei nie berührt.

⚠ **Sichtbarkeits-Spiegel-Kopplung (Review-Fix A4):** Die Sichtbarkeitslogik existiert an **drei** Stellen (`listPasswordEntries`, `upsertPasswordEntry`, `revealPasswordSecret`) und in den Rules (Metadaten-Read-Gate). Sie ist eine **dokumentierte Spiegel-Kopplung** (Klasse `compliance_service.dart ↔ functions/index.js`): Änderung an einer Stelle → an allen mitziehen. In die Kopplungs-Checkliste aufgenommen (§19).

### Teil 2 — Dritte-Hand-Kasse

- **`kioskSaveCashCount` erweitern** ([functions/index.js:1479](functions/index.js#L1479)): zusätzlicher Payload-Key `thirdParty` (camelCase-Liste). ⚠ **Review-Fix P1-B3:** **streng optional** parsen (`Array.isArray(request.data?.thirdParty) ? … : []`), jeder Eintrag validiert (`typeId` non-empty String, `amountCents` `Number.isFinite && >= 0`, Liste ≤ 20), ungültig → `HttpsError('invalid-argument')`. Person weiter server-authoritativ (`countedByUserId = session.employeeId`), Blindheit erzwungen (`expectedCents/differenceCents = null`). Session-Guard (`requireKioskSession`) unverändert.
- **Dev-/Local-Fallback** ([kiosk_screen.dart:716-728](lib/screens/kiosk/kiosk_screen.dart#L716-L728)): `thirdParty` direkt im `CashCount(...)`-Konstruktor (camelCase via `toFirestoreMap`).
- **Auswertung:** neue **getrennte** pure Funktion `computeThirdPartySummary(closings, periode)` in [kasse_report.dart](lib/core/kasse_report.dart) (oder `third_party_report.dart`), aggregiert aus `List<CashClosing>` je Periode: Gesamt + `byType: Map<typeId,{name,total,count}>`. **Kein** bestehendes `KassenPeriode`-Feld wird berührt (paralleles Ergebnisobjekt). `PosDailyStat` und [functions/oktopos_stats.js](functions/oktopos_stats.js) bleiben unangetastet (Fremdgeld ist kein Beleg).

⚠ **Review-Fix P2-B5 (vor Umsetzung verifizieren):** Der Report liest bisher **keine** `CashClosing`-Docs. Prüfen, ob `loadCashClosings`/`getCashClosingsInRange` bereits einen Range-Query kann. Falls ein **neuer** `where(businessDay ≥ x, ≤ y) + orderBy` nötig → **Composite-Index** in [firestore.indexes.json](firestore.indexes.json) (aktuell 24) ergänzen + deployen. Die „kein Index nötig"-Aussage gilt nur, wenn `loadCashClosings` schon range-fähig ist bzw. der Report ohnehin alle Closings der Org lädt (Client-Filter, Read-Kosten dokumentieren).

---

## 10. Frontend-Komponenten

### Teil 1 — Passwortmanager

- **Provider `PasswordProvider`** ([lib/providers/password_provider.dart], neu; Skelett an [contact_provider.dart](lib/providers/contact_provider.dart)): Repo **lazy** (nie im Konstruktor — sonst Crash im `APP_DISABLE_AUTH`/Web-Modus, siehe [[provider-lazy-cloud-repo]]). `updateSession` mit Session-Key-Guard `'${uid}:${orgId}:$mode'`; `setAuditSink(audit.log)`; `_safeNotify()`. **Kein** Metadaten-Stream, **kein** Direkt-Write (⚠ Review-Fix P0-A1) — alle Lese-/Schreib-/Reveal-Pfade laufen über die `FirestoreService`-Callable-Bridge (`listPasswordEntries`/`upsert…`/`reveal…`/`delete…`/`logPasswordCopy`).
- ⚠ **Review-Fix P0-A1 — Feature komplett Blaze/Cloud-only:** im gesamten `APP_DISABLE_AUTH`/local/hybrid-Kontext **ausgeblendet** (nicht halb-degradiert). Gate: `AppConfig.passwordManagerEnabled && !AppConfig.disableAuthentication` (analog `oktoposEnabled`, Default aus).
- **Provider-Registrierung** in [lib/main.dart](lib/main.dart) **nach** `AuditProvider` (Kopplung #4), `ChangeNotifierProxyProvider3<Auth,Storage,Audit>`, `_dispatchProviderUpdate(...)`.
- **Route + Gate:** `AppRoutes.passwords = '/passwoerter'` ([shell_tab.dart](lib/routing/shell_tab.dart)) + `_sectionRoute` ([app_router.dart](lib/routing/app_router.dart)) + Single-Source-Permission in [route_permissions.dart](lib/routing/route_permissions.dart) (aktiver Nutzer sieht eigene Einträge; Verwaltung admin/teamlead-gegated im Screen) + Profil-Kachel mit **identischem** Gate.
- **Screens/Sheets:** `PasswordsScreen` (Liste/Filter/Suche/Sort), Editor-Sheet, Reveal-Sheet (Reauth + Auto-Hide + `FLAG_SECURE`), Zielgruppen-Picker. `_QuickActionCard` ist file-private → dort verwenden.
- **Kiosk:** bewusst **keine** Passwort-Kachel/-Sicht.

### Teil 2 — Dritte-Hand-Kasse

- **`cash_count_sheet.dart` erweitern** ([lib/widgets/cash_count_sheet.dart]): zweite Sektion + Zusammenfassung; `CashCountInput` um `thirdParty: List<ThirdPartyAmount>`; Pflicht-Parameter `showThirdPartySoll: bool` (Kiosk `false`).
- **`kiosk_screen.dart` `_CashCountTile`:** Fremdgeld-Schritt (nur bei aktivierten Arten) + erweiterter `kioskSaveCashCount`-Aufruf + Dev-Direkt-Write.
- **`daily_closing_screen.dart`:** Fremdgeld im Zähl-/Abschluss-Fluss ([:120-159](lib/screens/daily_closing_screen.dart#L120-L159), [:163-211](lib/screens/daily_closing_screen.dart#L163-L211)); `CashClosing.fromDailyClosing(thirdParty:…)`.
- **`kassenbericht_screen.dart`:** neuer, **getrennter** Block (KPI-Karte „Eigene Kasse vs. Fremdgelder" + Aufschlüsselung je Art; optionale `fl_chart`-Zeitreihe als Stretch). Datenquelle `computeThirdPartySummary`.
- **Admin-Config (Minimal):** Abschnitt „Dritte-Hand-Arten dieser Filiale" im Filial-Editor (`SiteDefinition`-Bearbeitung, admin-only, direkter `sites`-Write).
- **CSV-Export:** zusätzliche Spalten/Block **hinten anhängen** (UTF-8-BOM + `;` behalten — deutsches Excel), bestehende Umsatz-Spalten unverändert.

---

## 11. Berechtigungslogik

### Teil 1 — Passwortmanager

⚠ **Review-Fix B1 (BLOCKER):** Ein per-Doc-`allow read: if passwordVisibleToCaller(resource.data)` **filtert Listen-Queries nicht** — Firestore lehnt die ganze Query ab, wenn nicht jedes Doc die Regel erfüllt. Das `contacts`-Muster ([firestore.rules:1481](firestore.rules#L1481)) ist bewusst prädikatlos (`sameOrg && !isKiosk()`) und würde hier **jedem Mitarbeiter alle Metadaten org-weit** offenlegen. ⚠ **Review-Fix P0-A2:** `contacts` ist zudem **kein** employee-Read-Modell (admin/teamlead-gegated) — das RBAC ist **neu**, nicht „wie Contacts".

**Konsequenz — Zugriffsschicht:**
- **Metadaten-Read ausschließlich über `listPasswordEntries`-Callable** (server-authoritative Sichtbarkeit). Direkter Client-Read: `passwordEntries` `allow read: if isAdmin()` (nur Admin/Diagnose), Mitarbeiter lesen **nur** über den Callable.
- **`passwordSecrets`:** `allow read, write: if false` (exakt `userSecrets`/`kioskSessions` [firestore.rules:951-958](firestore.rules#L951-L958)).
- **`passwordAccessLog`:** `read: if sameOrg && isAdmin() && !isKiosk()`; `write: if false`.
- **Schreiben ausschließlich über Callable** (`upsert…`/`delete…`) — ⚠ **kein Metadaten-Direkt-Write** (Review-Fix H6/P0-A1: verhindert Mass-Assignment von `hasSecret`/`ownerUid`/`audience…`; Credential-Sensitivität schlägt Contacts-Konsistenz).

**Rules-Helper — korrigiert** (⚠ Review-Fix A3/M4): `normalizedRoleValue(currentUser().data.role)` verwenden (es gibt **kein** bare `role`, **kein** `currentRole()`); `canManagePasswords()` direkt über `isAdmin()` / `roleIsTeamLeadValue(currentUser().data.role)` bauen, keine neuen Helper erfinden.

**RBAC-Matrix (server-authoritativ im Callable durchgesetzt):**

| Rolle | personal | shared lesen | shared anlegen/ändern | reveal |
|---|---|---|---|---|
| **employee** | CRUD eigene | wenn in audience (uid/role/site→live) | nein | eigene + freigegebene |
| **teamlead (Flag an)** | wie employee | eigene Filiale | eigene Filiale | + Filial-Einträge |
| **admin** | alle | alle | alle/zentral + zuweisen | alle |

**Neuer Getter** [app_user.dart](lib/models/app_user.dart): `canManagePasswords` (= `isActive && (isAdmin || (passwordTeamleadEnabled && canManageShifts))`) — gated die Verwaltungs-UI; jeder aktive Nutzer hat das Grundrecht auf **eigene** Einträge.

**Materialisierung `audienceSiteIds → audienceUids`** (Query-Optimierung, **nicht** Autorität): der Server berechnet beim `upsert` die betroffenen `audienceUids` aus `employeeSiteAssignments`. ⚠ Reveal/Sichtbarkeit rechnen **immer live** (B3); Materialisierung ist nur Listen-Optimierung. Drift bei Personalwechsel → **Reconcile-Job** als eigener (später) Meilenstein M6.

### Teil 2 — Dritte-Hand-Kasse

- **Erfassen** (Kiosk): `kioskSaveCashCount` + `requireKioskSession` (Person server-authoritativ).
- **Erfassen** (Tagesabschluss): `isAdmin || isTeamLead` ([daily_closing_screen.dart:287](lib/screens/daily_closing_screen.dart#L287)).
- **Kategorien verwalten / Filial-Aktivierung:** admin (`sites`-Write admin-only).
- **Auswertung:** admin (`/kassenbericht` bestehendes Route-Gate; `CashClosing`-Read admin/teamlead).
- **Rules `hasOnly`-Update Pflicht** (⚠ P0-B1): `thirdParty` in die `keys().hasOnly([...])`-Allowlisten von `cashCounts` ([firestore.rules:1549](firestore.rules#L1549)) **und** `cashClosings` ([firestore.rules:1618](firestore.rules#L1618)) aufnehmen — **optional**, kein Pflicht-Check (`!('thirdParty' in …) || thirdParty is list`), sonst brechen Filialen ohne Fremdgeld. Blind-Zwang (`expectedCents==null`) unberührt (Fremdgeld hat keine top-level Soll-Felder).

---

## 12. Audit- und Verlaufskonzept

### Teil 1 — Passwortmanager (zwei Ebenen)

**a) Metadaten-Mutationen (create/update/delete)** — server-seitig via `writeAudit(...)` ([functions/index.js:240-266](functions/index.js#L240-L266)): `action` ∈ `created/updated/deleted`, `entityType:'password'`, `entityId`, **deutsche** `summary` (z. B. „Zentrales Passwort „KVG Portal" (Filiale Kiel) angelegt") — **nie** Klartext/Username im Summary. `AuditAction`-Whitelist der Rules ([firestore.rules:1179-1180](firestore.rules#L1179-L1180)) beachten.

**b) `passwordAccessLog` (reveal/copy)** — dediziert, admin-only lesbar, `write:if false`. ⚠ **Review-Fix A6:** Dies ist **NICHT** der best-effort `AuditSink`, sondern ein **fail-closed Vertragsbestandteil** des Reveal (§9 Schritt 4). Felder:

| Feld | Beispiel | Feld | Beispiel |
|---|---|---|---|
| `orgId` | | `action` | `reveal_requested`/`revealed`/`copied` |
| `entryId` / `entryTitle` | „KVG Portal" (Snapshot, kein Secret) | `category` | `kvg` |
| `siteId` / `siteName` | „Kiel" | `field` (copy) | `password`/`username` |
| `actorUid` / `actorLabel` | server-authoritativ | `reason` | optionaler Freitext |
| `at` | `serverTimestamp` | `requestId` / `appCheck` | Korrelation |

**Nie enthalten:** username-/password-Klartext, ciphertext, DEK, KEK. Erfüllt „wer / was / wann / Filiale / Kategorie / Dienst" ohne Leak. Optional Admin-Screen `/passwort-zugriffe` (Revisionssicht). ⚠ **Ehrlichkeit (M3):** **Reveal** ist der revisionssichere Audit-Anker; **Copy** ist best-effort und client-seitig nicht erzwingbar (Klartext liegt nach Reveal ohnehin im Client). Wer Copy hart erzwingen will: Reveal-Antwort nur maskiert, Klartext erst als Antwort eines `copy`-Callable — als Option dokumentiert.

### Teil 2 — Dritte-Hand-Kasse

Kassenzählung/-abschluss laufen über den bestehenden Audit-Pfad. Fremdgeld-Erfassung erzeugt (falls geloggt) `summary` **ohne** konkrete Beträge (nur Anzahl Arten/Titel) — nur auf Erfolgspfad, wie AuditSink-Konvention.

---

## 13. Validierung und Fehlerfälle

### Teil 1 — Passwortmanager (Server, fail-closed)

- `title` nicht leer, ≤ 200; `category` ∈ Enum (Default `other`); `scope` ∈ {personal,shared}; `plain_password` ≤ 4096, UTF-8, nicht nur Whitespace; `siteId` (falls gesetzt) existiert in der Org; `audience…` ≤ 200 Einträge.
- `scope=='shared'` ohne `isAdmin`/`canManagePasswords` → `permission-denied`.

| Fall | Server-Code | Client (deutsch) |
|---|---|---|
| Kein Recht (reveal/write) | `permission-denied` | „Keine Berechtigung für dieses Passwort." |
| Reauth fehlgeschlagen/abgelaufen | `unauthenticated` | Reveal abgebrochen, Sheet maskiert |
| Rate-Limit / Tages-Budget | `resource-exhausted` | „Zu viele Zugriffe – bitte kurz warten." |
| App Check fehlt | `failed-precondition` | „Sicherheitsprüfung fehlgeschlagen." |
| Entschlüsselung/AuthTag scheitert | `internal` | „Passwort konnte nicht entschlüsselt werden." (Server-Log ohne Klartext) |
| Audit-Write scheitert beim Reveal | `internal` | **kein Klartext** („no reveal without record") |
| Feature aus / Offline-Modus | (kein Call) | Bereich ausgeblendet |

### Teil 2 — Dritte-Hand-Kasse

- **Client:** Beträge ≥ 0 (`Money.parseCents`, negativ verworfen); Pflicht-Art ohne Betrag → visuell markiert (`appColors.warning`) + **bewusste Quittierung** (0,00 € ist legitim); unplausibel hoher Betrag (> 10.000 €) → sanfter Hinweis, blockiert nicht; deaktivierte Art bleibt in Alt-Erfassungen gültig (Snapshot `typeName`).
- **Server:** `thirdParty[]` streng validiert (§9). `expectedCents` am Kiosk immer `null` (Blind-Zwang).
- **Fehlerfälle:** Filiale ohne Arten → Schritt entfällt; Offline → wie heute („Zählung braucht Internet" [kiosk_screen.dart:747](lib/screens/kiosk/kiosk_screen.dart#L747)); Auto-Logout → `controller.touch()` je Teilschritt; Kategorie mid-day gelöscht/umbenannt → Snapshot bewahrt Lesbarkeit.

### Auswirkung auf bestehende Berichte (Teil 2 — explizit UNVERÄNDERT)

| Aggregat / Pfad | Änderung |
|---|---|
| `PosDailyStat` (alle Felder) · [functions/oktopos_stats.js](functions/oktopos_stats.js) | **UNVERÄNDERT** |
| `kasse_report.dart` `KassenPeriode` (Umsatz/Rohertrag/USt/Δ) | **UNVERÄNDERT** (paralleler Block) |
| `daily_closing_posting.dart` · `cash_difference_posting.dart` · Finanzjournal | **UNVERÄNDERT** (Fremdgeld nie gebucht) |
| `CashClosing.cashDifferenceCents/cashExpectedCents/cashCountedCents/revenueGrossCents` | **UNVERÄNDERT** |

**Migration (Teil 2):** **Kein Backfill.** Alt-Docs ohne `thirdParty` → `fromFirestore` liest tolerant `const []`. Einziger harter Schritt: **Rules-Deploy vor App-Rollout** (⚠ Deploy-Reihenfolge §16). Optionaler **opt-in Seed** (Lotto/Post/KVG/Paket/Guthabenkarten) beim ersten Öffnen des Filial-Editors — nicht automatisch.

---

## 14. Tests

**Quality Gates (Definition of Done):** `flutter analyze` clean · `flutter test` (offline, `APP_DISABLE_AUTH`) · `node --test` in `functions/` · Rules-Emulator-Tests.

### Teil 1 — Passwortmanager

- **Krypto-Core (`node:test`, offline):** `encrypt→decrypt` round-trip (JSON u/p/n); **AAD-Bindung** (Wrap aus Doc A in Doc B → KMS/Unwrap schlägt fehl); IV-Einzigartigkeit; Reauth-Nonce `timingSafeEqual` + Brute-Force-Sperre; **Redaction** (kein Log/keine Antwort enthält Klartext/DEK). ⚠ **KMS-Offline-Testbarkeit (`KeyWrapper`-Abstraktion):** Da KMS-`encrypt`/`decrypt` nicht offline laufen, kapselt eine Schnittstelle `KeyWrapper.wrap(dek, aad)`/`unwrap(wrapped, aad)` das DEK-Wrapping. **Prod-Impl** = `KmsKeyWrapper` (`@google-cloud/kms`); **Test-Impl** = deterministischer lokaler `aes-256-gcm`-Wrapper mit fixem Test-KEK. Die **Daten-Verschlüsselung** (DEK+GCM+AAD) bleibt so vollständig offline-testbar; nur der Wrap-Schritt ist im Test gemockt. Ein Vertragstest prüft, dass beide Wrapper dieselbe AAD-Semantik erzwingen (fremde AAD → Fehler).
- **Rules-Emulator (⚠ P0-Gate):** `passwordSecrets` read/write immer deny (auch Admin); `passwordEntries` direkt nur admin; employee liest **nur** über Callable (kein org-weiter Metadaten-Leak); `passwordAccessLog` nur admin-read/client-write-deny; Kiosk deny; Cross-Org deny.
- **Provider (Fakes):** `cloudFunctionInvoker`-Simulation; Sichtbarkeitsfilter (eigene + freigegeben); `reveal`-Mapping; `logPasswordCopy` bei Copy; Feature im Offline-Modus ausgeblendet; Audit nur auf Erfolgspfad (Subklassen-Seam, kein Mockito).
- **Widget (Reveal-Flow):** Reauth-Gate → Klartext erscheint → Auto-Hide entfernt Klartext nach TTL; Liste zeigt **nie** Klartext (Finder-Assertion); Router-Harness `/passwoerter`.

### Teil 2 — Dritte-Hand-Kasse

- **Engine (pure, offline):** ⚠ **Regressionsbeweis zuerst** — `CashClosing.fromDailyClosing(thirdParty:…)` → `cashDifferenceCents` **exakt** `counted − cashExpectedCents`; `grandTotalCashCents == counted + Σ thirdParty`; `kasse_report`-Regression (Umsatz/Rohertrag/Δ **identisch** mit/ohne Fremdgeld). `computeThirdPartySummary` byType/Gesamt/leer.
- **Serialisierung:** `ThirdPartyAmount`/`ThirdPartyCashType` Round-Trip (camelCase ↔ snake_case); ⚠ `FakeFirebaseFirestore` liefert Zahlen als `double` → keine int-Gleichheit asserten; `parse.toInt` fängt ab.
- **Provider:** `saveCashCount` mit `thirdParty` (Cloud + hybrid-Fallback via `FirebaseFunctionsException`), Audit ohne Beträge.
- **Widget (Kiosk):** getrennte Sektionen; Pflicht-Art blockiert bis Quittierung; Zusammenfassung korrekt; ⚠ „Kiosk-Aufruf zeigt nie `expectedCents`" (Blind-Test, Review-Fix B4).
- **Functions (`node:test`):** erweitertes `kioskSaveCashCount` (thirdParty optional/validiert; Doc enthält `thirdParty` + `countedByUserId=session.employeeId` + `expectedCents=null`; Session-Guard unverändert).

---

## 15. Risiken und offene Fragen

### Risiken (mit Gegenmaßnahme)

| Risiko | Schwere | Gegenmaßnahme |
|---|---|---|
| **PM:** Org-weiter Metadaten-Leak bei Client-Stream | **BLOCKER (B1)** | `listPasswordEntries`-Callable, kein Client-Stream/Direkt-Write (gelöst im Plan) |
| **PM:** Reauth nur clientseitig umgehbar | HOCH (H3) | Harte Server-Nonce als Default; Web erzwingt harte Variante |
| **PM:** Versetzter Mitarbeiter behält Reveal-Rechte | HOCH (B3) | Reveal live gegen `employeeSiteAssignments`; Reconcile-Job M6 |
| **PM:** `keyVersion`-in-Secret-AAD bricht KEK-Rotation | MITTEL (M2) | `keyVersion` nur in DEK-Wrap-AAD (gelöst) |
| **PM:** KEK im Prozessspeicher (Secret-Manager-Variante) | MITTEL (M1) | KMS als empfohlener Default; sonst strikte IAM |
| **PM:** Gelöschtes Secret in Backups/PITR | HOCH (H5) | Krypto-Shredding + Backup-Retention als Betreiber-Aufgabe |
| **PM:** Dart-String-Immutabilität → kein Client-Wipe | NIEDRIG (N1) | Auto-Hide + `FLAG_SECURE`; ehrlich dokumentiert |
| **DH:** Rules-`hasOnly` nicht deployt → Direkt-Write deny | **P0-B1** | Deploy-Reihenfolge **Rules → Functions → App** hart |
| **DH:** Neuer Client gegen alte Function → stiller Fremdgeld-Datenverlust | P1-B3 | Deploy-Reihenfolge; Server `thirdParty` streng optional; optional `_api_version`-Bump |
| **DH:** Schein-Differenz durch naive Fremdgeld-Addition | (verhindert) | Getrennter additiver Block; Regressionsbeweis im Test |

### Offene Fragen für den Auftraggeber

> **Entschieden (03.07.):** ① Passwortmanager-KEK = **Cloud KMS (HSM)**. ② Dritte-Hand-Kasse v1 = **Minimal-Variante an `SiteDefinition`**.

**Passwortmanager (noch offen):**
1. `passwordTeamleadEnabled` (Filialleiter dürfen zentrale Filial-Passwörter verwalten) — an oder aus?
2. Auto-Hide-TTL (Standard 30 s) und Reveal-Tages-Budget/Nutzer?
3. Clipboard-Auto-Clear aktiv (plattformabhängig; auf Web unzuverlässig)?
4. Passwort-Health (alt/schwach/doppelt) in v1 oder als späterer Meilenstein M6?

**Dritte-Hand-Kasse (noch offen):**
5. Fremdgeld-Soll: v1 reine Ist-Erfassung (empfohlen) — optionaler Soll-Abgleich pro Art als Stretch?
6. Betrags-Eingabe am Kiosk: dediziertes On-Screen-Numpad (empfohlen) vs. bestehendes `TextField`?
7. Zeitreihe je Art im Bericht in v1 oder Stretch?
8. Opt-in Seed-Vorschlagsliste anbieten?

---

## 16. Priorisierte Umsetzung in Phasen

> **Prinzip (kleinster lauffähiger, offline-testbarer Schnitt zuerst).** Deploy immer zuletzt, **strikte Reihenfolge `firestore:rules → functions → App`** (⚠ P0-B1: der Kiosk-Callable umgeht Rules und schreibt sofort nach Functions-Deploy — Rules müssen davor stehen).

### Teil 1 — Passwortmanager

| Phase | Inhalt | Offline testbar |
|---|---|---|
| **PM-M0** | Pure Krypto-Core in `functions/` (`encrypt/decrypt/wrap/unwrap/AAD`, testbarer KEK-Loader) + `node:test`-Roundtrip | ✅ |
| **PM-M1** | Model `PasswordEntry` (6 Stellen) + Enums + Dart-Roundtrip-Tests | ✅ |
| **PM-M2** | Rules (`passwordEntries`/`passwordSecrets`/`passwordAccessLog`, korrigierte Helper) + **Emulator-Rules-Tests (P0-Gate)** | ✅ (Emulator) |
| **PM-M3** | Callables `list/upsert/reveal/delete/logCopy/beginReauth` + `node:test` (fail-closed-Audit, AAD, Visibility, Rate-Limit) | ✅ |
| **PM-M4** | `PasswordProvider` + `FirestoreService`-Callable-Bridge + Provider-Tests (Fakes) | ✅ |
| **PM-M5** | Screen `/passwoerter` + Route + Gate + Reveal-Flow (Reauth/Auto-Hide/`FLAG_SECURE`) + Widget-Tests | ✅ |
| **PM-M6** (spät) | `rewrapPasswordDeks` (**optional**, nur für KMS-Version-Zerstörung — Rotation ist KMS-nativ) · Passwort-Health · `audienceUids`-Reconcile-Job · Admin-Zugriffsprotokoll-Screen | ✅ |
| **Deploy** | **KMS-Keyring + CryptoKey** (`europe-west3`) anlegen + IAM-Binding `cryptoKeyEncrypterDecrypter` auf den Function-SA · Secret `PASSWORD_DUP_PEPPER` setzen · `@google-cloud/kms` in `functions/package.json` · Rules+Indexes · Functions · App mit `APP_PASSWORD_MANAGER_ENABLED=true` · AppCheck | — |

### Teil 2 — Dritte-Hand-Kasse

| Phase | Inhalt | Offline testbar |
|---|---|---|
| **DH-M0** | Modelle `ThirdPartyAmount` + `ThirdPartyCashType` (dual-serialisiert) + Roundtrip-Tests | ✅ |
| **DH-M1** | `CashCount.thirdParty` + `CashClosing.thirdParty` + `fromDailyClosing` + **Regressionsbeweis `cashDifferenceCents` unverändert** | ✅ |
| **DH-M2** | Rules `hasOnly`-Update (cashCounts + cashClosings, optional) + Emulator-Test — **Blocker vor Direkt-Writes** | ✅ (Emulator) |
| **DH-M3** | `kioskSaveCashCount` erweitern (Server-Validierung, thirdParty optional) + `node:test` | ✅ |
| **DH-M4** | `firestore_service.kioskSaveCashCount`-Signatur + Sheet-Erweiterung (Sektionen/Numpad/Zusammenfassung/Blind-Param) + Widget-Tests | ✅ |
| **DH-M5** | Kiosk `_CashCountTile` + Tagesabschluss-Flow | ✅ |
| **DH-M6** | `computeThirdPartySummary` + Kassenbericht-Block + CSV (Spalten hinten) | ✅ |
| **DH-M7** | Admin-Config (Minimal: Filial-Editor-Abschnitt) | ✅ |
| **Deploy** | **Rules → Functions → App** (strikte Reihenfolge) | — |

---

## 17. Quick Wins

- **DH-M0/M1 zuerst** — Modelle + Regressionsbeweis sind rein offline, ohne Firebase, und liefern sofort die härteste Invariante (keine Verfälschung) als Test. Hoher Wert, null Deploy-Risiko.
- **DH Minimal-Variante** (`SiteDefinition.thirdPartyCashTypes`) spart einen kompletten `OrgSettings`-Touch + einen Admin-Screen — bei zwei Läden voll ausreichend.
- **PM-M0 Krypto-Core** — isoliert, deterministisch, `node:test`, blockiert nichts; schafft früh Vertrauen in den kryptografischen Kern (der laut Review bereits solide ist).
- **Farb-Tokens sind fertig** — `StrichTokens`/`appColors` sind 1:1 verifiziert; keine Design-Token-Arbeit nötig, nur korrektes Konsumieren.
- **Feature-Flags** (`APP_PASSWORD_MANAGER_ENABLED`, `passwordTeamleadEnabled`) erlauben Merge vor Blaze-Cutover ohne UI-Sichtbarkeit.

---

## 18. Akzeptanzkriterien

**Passwortmanager:**
- [ ] Ein Mitarbeiter kann eigene Zugangsdaten speichern und **nur selbst** sehen.
- [ ] Ein Admin kann ein Passwort für eine bestimmte **Filiale oder Rolle** bereitstellen (Zielgruppen-Zuweisung).
- [ ] Ein Mitarbeiter **ohne** Berechtigung kann fremde Passwörter **nicht** sehen — auch nicht per direktem Firestore-Read (Emulator-Test beweist es).
- [ ] Ein Passwort wird **verschlüsselt** gespeichert und **nie** im Klartext geloggt (Redaction-Test).
- [ ] „Anzeigen" verlangt eine **server-durchgesetzte** Sicherheitsbestätigung und blendet den Klartext nach kurzer Zeit automatisch aus.
- [ ] Jeder Reveal erzeugt **garantiert** einen `passwordAccessLog`-Eintrag (kein Reveal ohne Protokoll).
- [ ] Kopieren wird protokolliert (Reveal ist der revisionssichere Anker; Copy best-effort — ehrlich kommuniziert).
- [ ] Der Bereich ist im Offline-/Demo-Modus **ausgeblendet** (kein kaputt wirkendes Feature).

**Dritte-Hand-Kasse:**
- [ ] Beim Kassenzählen kann ein Mitarbeiter **Lotto-, Post- oder KVG-Beträge** zusätzlich eintragen.
- [ ] Dritte-Hand-Beträge werden **getrennt** von der normalen Kasse gespeichert.
- [ ] Kassenberichte zeigen **eigene Kasse und Fremdgelder getrennt** an.
- [ ] Die Kassendifferenz (`cashDifferenceCents`) bleibt **beweisbar unverändert** (Regressionstest).
- [ ] Pro Filiale ist konfigurierbar, welche Dritte-Hand-Arten angeboten werden.
- [ ] Bestehende `PosDailyStat`/Umsatz-/Rohertrags-Aggregate bleiben **unverändert**.

**Gemeinsam:**
- [ ] Die UI verwendet **exakt** die Farben aus `/Users/jowan/Documents/dev/Strichmänschen` (`StrichTokens`, kein Hex im Screen).

---

## 19. Checkliste für die Umsetzung (kritische Kopplungen)

### Teil 1 — Passwortmanager
- [ ] Krypto-Core hinter `KeyWrapper`-Abstraktion (Prod `KmsKeyWrapper` / Test lokaler AES-Wrapper); KMS `encrypt`/`decrypt` mit AAD `orgId|entryId`; DEK-Buffer in `finally` gewiped.
- [ ] **Cloud KMS:** Keyring + CryptoKey in `europe-west3`; IAM `roles/cloudkms.cryptoKeyEncrypterDecrypter` **nur** für den Function-SA; `@google-cloud/kms` in `functions/package.json`.
- [ ] `sameOrg` (Rules) ⇔ `assertSameOrg` (Functions) ⇔ KMS-AAD `orgId` — Mandantengrenze dreifach.
- [ ] **Sichtbarkeits-Spiegel-Kopplung** dokumentiert: `listPasswordEntries` ⇔ `upsertPasswordEntry` ⇔ `revealPasswordSecret` ⇔ Rules-Read-Gate.
- [ ] `PasswordCategory`/`PasswordScope` `.value` ⇔ `fromValue`-Default ⇔ deutsches `label` ⇔ Rules-Strings (Kopplung #3).
- [ ] Model-Feld → 6 Stellen; Callable-Payload snake_case `toMap()` + separates Klartext-Feld (Kopplung #1).
- [ ] `enforceAppCheck:true` **explizit** an allen Passwort-Callables (nicht vererbt).
- [ ] Reveal: harte Server-Reauth-Nonce (Default) · Audit **vor** Entschlüsselung · `finally`-wipe · transaktionales + globales Rate-Limit · `FLAG_SECURE`.
- [ ] **Kein** Metadaten-Direkt-Write/-Stream — alles über Callable; `passwordSecrets` `if false`; `passwordAccessLog` admin-read/`if false`-write.
- [ ] Rules-Helper: `normalizedRoleValue(currentUser().data.role)`, kein `currentRole()`; RBAC ist **neu** (nicht Contacts) → Emulator-Rules-Test P0-Gate.
- [ ] Provider **nach** Auth/Storage/Audit (Kopplung #4), lazy Repo, `setAuditSink`, `_safeNotify`; Feature Blaze/Cloud-only, im Offline-Modus ausgeblendet.
- [ ] Route `AppRoutes.passwords` + `_sectionRoute` + `route_permissions` (Single Source) + Profil-Kachel gleiches Gate (Kopplung #7).
- [ ] `FIREBASE_FUNCTIONS_REGION = europe-west3` = `const REGION` (Kopplung #8).
- [ ] Secrets/Keys: **Cloud KMS-CryptoKey** (KEK) + **separates** `PASSWORD_DUP_PEPPER`-Secret (nicht KEK-abgeleitet, für Health-HMAC); je Function `secrets:[PASSWORD_DUP_PEPPER]` + KMS-IAM; KEK/Klartext nie geloggt.
- [ ] Composite-Index nur falls `where+orderBy` genutzt ([firestore.indexes.json](firestore.indexes.json), aktuell 24) — Zwei-Stream-Merge vermeidet ihn.

### Teil 2 — Dritte-Hand-Kasse
- [ ] `ThirdPartyCashType` + `ThirdPartyAmount` (dual-serialisiert, Snapshot-`typeName`).
- [ ] `SiteDefinition.thirdPartyCashTypes` (6 Stellen).
- [ ] `CashCount.thirdParty` + `CashClosing.thirdParty` (je 3 cloud-only Stellen + Getter).
- [ ] `CashClosing.fromDailyClosing`: `thirdParty` übernehmen, `cashDifferenceCents` **beweisbar unverändert**.
- [ ] `cash_count_sheet.dart` erweitert (Sektionen/Numpad/Zusammenfassung/`showThirdPartySoll`-Pflichtparam) + `CashCountInput.thirdParty`.
- [ ] `kiosk_screen.dart` `_CashCountTile` + erweiterter Callable + Dev-Direkt-Write; `daily_closing_screen.dart`-Flow.
- [ ] `firestore_service.kioskSaveCashCount`-Signatur (camelCase `thirdParty`).
- [ ] `functions/index.js` `kioskSaveCashCount`: `thirdParty` **streng optional** parsen/validieren/schreiben; Person server-authoritativ; Blindheit erhalten.
- [ ] `firestore.rules`: `thirdParty` in `hasOnly` von `cashCounts` (:1549) **und** `cashClosings` (:1618), **optional** (kein Pflicht-Check).
- [ ] `computeThirdPartySummary` + Kassenbericht-Block + CSV (Spalten hinten, BOM behalten).
- [ ] Composite-Index-Frage `loadCashClosings`-Range **vor Umsetzung verifizieren** (P2-B5).
- [ ] Tests grün; `flutter analyze` clean; **Deploy `firestore:rules → functions → App`** (strikte Reihenfolge).

---

**Kernurteil beider Reviews:** Der kryptografische Kern (DEK-pro-Eintrag, frisches IV, AuthTag, AAD-Bindung) und die Dritte-Hand-Architektur (strikt separater additiver Block, keine Verfälschung) sind solide. Die entscheidende Härtung liegt in der **Zugriffsschicht des Passwortmanagers** (Metadaten nur über Callable, harte Server-Reauth, live-Autorisierung, kein Metadaten-Leak, kein Direkt-Write) und in der **strikten Deploy-Reihenfolge** der Kasse. Alle diese Fixes sind in diesem Plan eingearbeitet.
