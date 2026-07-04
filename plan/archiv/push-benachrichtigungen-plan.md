# Plan: Mobile Push-Benachrichtigungen (FCM)

**Status:** Entwurf · **Datum:** 2026-06-30 · **Modul:** Benachrichtigungen / Firebase Cloud Messaging
**Zielplattformen:** Android + iOS (Web optional / Stretch) · **Tarif:** Entwicklung vollständig auf **Spark**; **Blaze** nur für den produktiven Versand am Go-Live (siehe [Tarif-Strategie](#tarif-strategie-entwicklung-auf-spark-go-live-auf-blaze))

> Dieser Plan wurde durch eine code-gestützte Analyse der gesamten WorkTime-Codebasis erstellt (8 Recherche-Bereiche + 5 Entwurfsabschnitte). Alle Architektur-Aussagen sind gegen den realen Code (`lib/`, `functions/index.js`, `firestore.rules`, `pubspec.yaml`, `android/`, `ios/`, `web/`) verifiziert.

## Ziel & Auslöser

> Betreiber-Wunsch: **„Mitarbeiter sollen auf dem Handy benachrichtigt werden, wenn etwas Wichtiges passiert — z. B. Kundenwünsche vorbereiten, Kühlschrank nachfüllen usw. Die Anzeige der Benachrichtigung auf dem Handy soll professionell sein."**

Daraus abgeleitet: Ein server-getriebenes Push-System, das fachliche Ereignisse (neuer Kundenwunsch, Kühlschrank-Nachfüllliste, Schichtplan veröffentlicht, Schichttausch, Abwesenheits-/Tausch-Genehmigungen, Krankmeldung, Meldebestand, Feedback) gezielt an die **richtigen** Mitarbeiter zustellt — mit einer auf dem Sperrbildschirm professionell aussehenden, deutschen, handlungsorientierten Darstellung.

## Ausgangslage (verifiziert — Greenfield)

- **Keine Push-Infrastruktur vorhanden:** `firebase_messaging`/`flutter_local_notifications` fehlen in `pubspec.yaml`; keine APNs-Entitlement (`ios/`), kein FCM-Eintrag im `AndroidManifest.xml`, kein `firebase-messaging-sw.js` (`web/`).
- **Cloud Functions** (`functions/index.js`, ~3 400 Zeilen, v2, Region `europe-west3`, Node 20) nutzen heute ausschließlich `onCall` + **einen** `onSchedule` — **keine** `onDocument`-Trigger, kein `admin.messaging()`. Der erste Firestore-Trigger des Projekts entsteht hier.
- **Das heutige „Anfragen"-Center** (`lib/screens/notification_screen.dart`, Tab `/anfragen`) ist **vollständig derived**: es rekonstruiert bei jedem `build()` ephemere Items aus Live-Provider-Listen. Es gibt **kein** persistiertes Notification-Model, **keine** Inbox-Collection und **keinen** gelesen/ungelesen-Status. Das Tab-Badge zählt nur offene Abwesenheiten + Tauschvorgänge.
- **Alle Bausteine werden neu gebaut**, orientieren sich aber strikt an etablierten Repo-Mustern: OktoPOS-Idempotenz (`batch.create`-Anker), `oktoposEnabled`-Feature-Flag, Lazy-Cloud-Repo, Zwei-Serialisierungs-Regel, Secret Manager, Drei-Speichermodi.

## Leitentscheidungen (verbindlich, TL;DR)

1. **Serverseitig getriggert, nie Client-Direktversand.** Push läuft ausschließlich über Cloud-Functions-Firestore-Trigger (`onDocumentCreated`/`onDocumentWritten`) + Admin-SDK-Messaging. Das ist der **einzige** Pfad, der auch direkte Client-Writes (Compliance-Override) und die anonymen öffentlichen Schreibpfade (`/wunsch`, `/feedback`) garantiert erfasst.
2. **Geräte-Tokens** in der Subcollection `users/{uid}/fcmTokens/{installationId}` (cloud-only, Doc-ID = Installations-ID → sauberer Self-Refresh), self-write per Rules, Versand server-side via Admin SDK.
3. **Persistierte `notifications`-Collection** (org-skopiert, ein Doc je Empfänger, `readAt`) als In-App-Pendant zur flüchtigen Systembenachrichtigung → Tap-Ziel, Historie, gelesen-Status; schließt die Lücke des heute rein derived Centers.
4. **`notificationPrefs`** als Feld-Objekt am `users/{uid}`-Doc: Kategorie-Opt-out + Ruhezeiten; serverseitig vor dem Versand ausgewertet.
5. **Fünf fachliche Kanäle** (Android Notification Channels) deckungsgleich mit iOS-Interruption-Levels und den App-Einstellungs-Schaltern: Genehmigungen, Schichtplan, Aufgaben & Kühlschrank, Kundenwünsche, Bestand.
6. **Doppelt gegatetes Feature-Flag** `APP_PUSH_ENABLED` (+ `DefaultFirebaseOptions.isConfigured`), fail-open im `catch`, **No-op** im `APP_DISABLE_AUTH`/local-only-Modus → Demo-/Offline-Start bleibt unverändert.
7. **Idempotenz/Dedupe** über deterministische `batch.create`-Anker (OktoPOS-Muster) + Flankenerkennung bei `onDocumentWritten` → kein Doppel-Push trotz At-least-once-Trigger.
8. **Empfänger-Auflösung serverseitig**, spiegelt exakt die Client-Sichtbarkeits-/Rollenlogik (`canManageShifts == isAdmin || canEditSchedule`, `normalizeRole`, Team `memberIds`, `employeeSiteAssignments.siteId`, immer `isActive` + `orgId`).
9. **Standort-Routing** für die zwei Kieler Läden (Strichmännchen, Tabak Börse) als zwei `SiteDefinition`-Standorte einer Org — Standortname immer im Body.
10. **Storage-Modi-Grenze (bewusst):** Server-Trigger feuern nur bei einem realen Firestore-Doc → im `local`-Modus und im hybrid-Offline-Fallback kein Push. Push ist inhärent cloud-/Blaze-gebunden.
11. **Roadmap M1–M7**, jeder Meilenstein für sich deploybar und wertbringend; Web-Push ist Stretch (M6) und blockiert M1–M5 nicht.

## Status & bewusste Nicht-Ziele

**Status (Stand 30.06.2026):** **M1 = umgesetzt (Code, Spark-Phase)** — `firebase_messaging` 15.1.0, Flag `APP_PUSH_ENABLED`, `PushMessagingService` + `FcmTokenRepository` + `NotificationProvider` (Token-Lebenszyklus), Bootstrap-Init, `fcmTokens`-Rules-Block; `flutter analyze`/`flutter test` grün (Repo-Test `test/fcm_token_repository_test.dart`). **Rules emulator-validiert** (10/10: ALLOW self-create/read/refresh/delete; DENY Org-Spoofing, Mass-Assignment, non-string-Token, Fremd-Lesen/-Schreiben, anonym). **Offen in M1:** Geräte-Test (Android schreibt Token sofort; iOS erst mit APNs aus M4), Deploy (Blaze-Cutover).
>
> **M2 = umgesetzt (Code, Spark-Phase)** — `onCustomerWishCreated`-Trigger (`onDocumentCreated` auf `customerWishes`), `documentCreatedTrigger`-Wrapper (requestId/Logging), `fanOutPush` (idempotentes Inbox-Doc via `.create()` + Multicast + Stale-Token-Pruning), Empfänger = alle aktiven Org-Mitarbeiter, deutscher PII-armer Text, `notifications`-Rules-Block. Pure Logik in `functions/push_notifications.js`; **6/6 Pure-Unit-Tests** (`node --test`) + **16/16 Rules-Emulator-Tests** (fcmTokens + notifications) grün; `node --check` OK. **Offen in M2:** Trigger-E2E im Functions-Emulator (Messaging-Stub) + Geräte-Test + Deploy.
>
> **M3 = umgesetzt (Code, Spark-Phase)** — fünf weitere Trigger in `functions/index.js`: `onCustomerFeedbackCreated` (→Manager, Beschwerde=high), `onAbsenceRequestWritten` (eingereicht→Manager, Entscheidung→Antragsteller), `onShiftSwapRequestWritten` (phasenabhängig target/requester/Manager/beide, je Phase eigener `type`/Dedupe), `onShiftWritten` (planned→confirmed→MA; frei geworden→Manager), `onProductWritten` (Meldebestand-Flanke→Manager, Tages-Re-Alert-Bucket). `documentWrittenTrigger`-Wrapper + serverseitige Empfänger-Auflösung (`managerUids` = aktiv ∧ (Admin ∨ canEditSchedule), reuse `resolvePermissions`/`normalizeRole`). Deutsche TZ-korrekte Texte. **12/12 Pure-Unit-Tests** grün; `node --check` OK; kein neuer Index nötig. **Offen M3:** Functions-Emulator-E2E + Deploy; bewusst vereinfacht: Krankmeldung→Schicht-frei geht an Manager (nicht Standort-Team), Tausch-Body ohne Schichtdatum.
>
> **M4 = umgesetzt (Code, Spark-Phase)** — `flutter_local_notifications` 19.5.0; `PushMessagingService` erweitert: 5 Android-Channels (genehmigungen/schichtplan/aufgaben/kundenwuensche/bestand), Foreground-Anzeige (`onMessage`→local notification mit Channel+Gruppierung), Berechtigung kontextuell nach Login, Tap→Deep-Link gate-konform (Pending-Route + `_gateRedirect`, wie Schnellaktionen), Top-Level-Background-Handler. AndroidManifest: `POST_NOTIFICATIONS` + FCM-Meta (Icon/Farbe/Default-Channel), monochromes `ic_stat_notification`-Drawable (Platzhalter-Glocke), Akzentfarbe `push_accent`. `channelIdForType` testbar (4 Tests). **`flutter analyze` 0 Issues, `flutter test` 1207 grün.** **Offen M4:** Aktions-Buttons (Erledigt/Genehmigen) noch nicht gebaut, Marken-Icon ersetzt Platzhalter, Android-/iOS-Build + Geräte-Abnahme, iOS-APNs (Cutover).
>
> **M5 = umgesetzt (Code, Spark-Phase)** — `NotificationPrefs`-Modell (5 Kategorie-Schalter = Channels + Master + Ruhezeiten, dual serialisiert) als eingebettetes Feld am `AppUserProfile` (6 Kopplungs-Stellen + copyWith); `firestoreService.updateNotificationPrefs` (Self-Update, merge) + `authProvider.updateNotificationPrefs` (optimistisch + best-effort Cloud); `NotificationSettingsScreen` (Master/Kategorien/Ruhezeiten, in Einstellungen verlinkt). Serverseitig: `pushAllowed`/`channelIdForType`/`inQuietWindow` (pur) + `fanOutPush` lädt je Empfänger die Prefs und unterdrückt den **System-Push** (Inbox-Doc wird IMMER geschrieben) bei Master/Kategorie aus oder Ruhezeit (Genehmigungen zeitkritisch=Ausnahme). **Dart 5 Tests + JS 15 Tests grün, `flutter test` 1214, analyze clean, Rules weiter 16/16.** **Offen M5:** Geräte-Test + Deploy; rollenabhängige Kategorie-Sichtbarkeit bewusst weggelassen (alle 5 sichtbar).
>
> **M6 = umgesetzt (Code/Artefakte, Stretch)** — `web/firebase-messaging-sw.js` (Background-Push + notificationclick→Deep-Link), `AppConfig.webPushVapidKey` (`APP_WEB_PUSH_VAPID_KEY`) + CLAUDE.md-Eintrag, `PushMessagingService` web-tauglich gemacht (`kIsWeb`-Guards: keine fln/Channels/Background-Handler auf Web; `getToken(vapidKey:)` auf Web; Plattform-Label `web`). analyze clean. **Offen M6:** Web-Firebase-Config im SW (Platzhalter `REPLACE_ME` → Build-Step/Hardcode, bewusste Ausnahme), `firebase.json`-SW-Header prüfen, Browser-Test; Web bleibt Stretch.
>
> **M7 = umgesetzt (Code, Spark-Phase)** — (a) **Batch-Publish-Bündelung:** `shift_published`-Push wird je Mitarbeiter & **ISO-Woche** dedupliziert (`isoWeek` + `dedupeId=uid:jahr-woche`), Text wechselt auf „Dein Plan für KW X" → bei `publishShiftBatch` (bis 50 Schichten) **ein** Push statt 50. (b) **Token-GC:** `pruneStaleFcmTokens` (`onSchedule` täglich 03:30 Berlin) löscht Tokens >270 Tage via `collectionGroup` + neuer **COLLECTION_GROUP-Index** `fcmTokens.updatedAt` (`firestore.indexes.json` fieldOverrides). (c) **Metriken:** strukturierte Logs `push_sent` (sent/failed/pruned/**suppressed**) + `fcm_token_gc` (deleted) + `trigger_start/done/error` mit requestId — Basis für Log-based Metrics. **functions 17/17, `node --check` OK.** **Offen M7:** Functions-Emulator-E2E + Deploy.
>
> **Functions-Emulator-E2E (Firestore + Functions, Spark) durchgeführt: 6/6 grün** — Kundenwunsch→2 Inbox-Docs (aktive MA, inaktive ausgeschlossen), Feedback→1 (nur Manager/Admin), Payload korrekt, Dedupe (Neuanlage erzeugt keine Doppel-Docs). Dabei **echten latenten Bug gefunden + behoben**: `admin.firestore.FieldValue`/`Timestamp` sind unter **firebase-admin v13 `undefined`** → JEDER Inbox-Write (und der bestehende OktoPOS-Code, 30 Stellen gesamt) wäre produktiv gescheitert; Fix = Subpath-Import `require("firebase-admin/firestore")`.
>
> **➡️ Alle M1–M7 sind code-fertig + getestet (Spark-Phase), inkl. Functions-Emulator-E2E. Verbleibend für den Go-Live: Blaze-Cutover (Functions-Deploy + Rules/Indizes-Deploy + APNs-Key/VAPID + `APP_PUSH_ENABLED=true`), Geräte-Abnahme, Marken-Notification-Icon, optional Aktions-Buttons (M4).**

**Verwandte Pläne (vor M3 abstimmen):** [kuehlschrank-nachfuell-automatik.md](kuehlschrank-nachfuell-automatik.md) berührt dieselbe Kühlschrank-Benachrichtigung — siehe offener Punkt P1 in Abschnitt 5.

**Bewusst NICHT Teil dieses Vorhabens (Scope-Out):**
- **Kein Client-Direktversand** von Push — Empfänger-/Token-Auflösung bleibt serverseitig (Sicherheits-/PII-Grenze, anonyme öffentliche Pfade).
- **Kein Per-Item-Push** für hochfrequente Quellen (Kühlschrankliste je Mengenänderung, Bestellkorb, Bestandsbewegung je Verkauf) — nur gebündelt/flankenbasiert (Rauschen-Prinzip wie beim Audit-Trail).
- **Kein Push im local-only-Modus / `APP_DISABLE_AUTH`** und im hybrid-Offline-Fallback (kein Firestore-Doc → kein Server-Trigger; bewusste, dokumentierte Asymmetrie).
- **Web-Push ist Stretch (M6)** und blockiert M1–M5 nicht.
- **Keine Compliance-Umgehung:** Genehmigungs-Aktionen mit Compliance-Prüfung (Schichttausch) öffnen die App statt eines Silent-Background-Writes.

## Inhaltsverzeichnis

1. [Architektur & Datenmodell](#1-architektur--datenmodell) — Sendepfad, Token-Lebenszyklus, `notifications`-Collection, Rules/Indizes, Idempotenz, Skalierung, `APP_PUSH_ENABLED`
2. [Benachrichtigungs-Taxonomie & Empfänger-Routing](#2-benachrichtigungs-taxonomie--empfänger-routing) — Ereignis-Katalog (Tabelle), serverseitige Empfänger-Auflösung, einheitliches FCM-Payload-Schema
3. [Client-Integration & Plattform-Setup](#3-client-integration--plattform-setup) — Pakete, Bootstrap-Anbindung, Permission-UX, Foreground/Background/Terminated, Deep-Links, iOS/Android/Web-Setup, In-App-Parität
4. [Professionelle Darstellung, UX & Nutzereinstellungen](#4-professionelle-darstellung-ux--nutzereinstellungen) — Notification-Anatomie, Kanäle/Interruption-Levels, Gruppierung, Aktions-Buttons, deutsche Copy, Ruhezeiten, Einstellungs-Screen, Barrierefreiheit
5. [Umsetzungsplan, Sicherheit, Tests & Rollout](#5-umsetzungsplan-sicherheit-tests--rollout) — Roadmap M1–M7, kritische Kopplungen, Datenschutz, Teststrategie, Observability, Deployment, offene Entscheidungen

---

## 1. Architektur & Datenmodell

Dieser Abschnitt legt das technische Fundament für mobile Push-Benachrichtigungen fest: wie ein fachliches Ereignis zur Gerätebenachrichtigung wird, wie Geräte-Tokens verwaltet werden, welche Datenmodelle und Firestore-Rules nötig sind und wie Mandantentrennung, Idempotenz und Kosten beherrscht werden. Plattform-Setup (APNs, Web-VAPID, Manifest/Entitlements) und die clientseitige Empfangs-/Tap-Routing-Logik sind in den jeweils eigenen Abschnitten beschrieben.

> **Greenfield-Hinweis:** Es existiert heute keinerlei Push-/FCM-Infrastruktur. `firebase_messaging` fehlt in `pubspec.yaml`, es gibt keine Token-Collection in `firestore.rules`, und `functions/index.js` (3429 Zeilen) nutzt ausschließlich `onCall` + genau einen `onSchedule`-Trigger — keine `onDocument`-Trigger und kein `admin.messaging()`. Alle hier beschriebenen Bausteine werden neu gebaut, orientieren sich aber strikt an etablierten Mustern des Repos (OktoPOS-Idempotenz, `oktoposEnabled`-Flag, Lazy-Cloud-Repo, Zwei-Serialisierungs-Regel).

### 1. Gesamtarchitektur-Überblick

Der Sendepfad ist **ereignisgetrieben über Firestore-Trigger**, nicht über Client-Callables:

```
Fachliche Mutation (Provider-Mutator ODER öffentlicher anonymer Schreibpfad
  ODER serverseitiger OktoPOS-Pull)
        │
        ▼
Firestore-Dokument geschrieben  (organizations/{orgId}/<collection>/{docId})
        │
        ▼  onDocumentCreated / onDocumentWritten  (firebase-functions/v2/firestore)
┌─────────────────────────────────────────────────────────────┐
│  Cloud Function (Region europe-west3, Admin SDK, umgeht Rules)│
│  1. requestId = crypto.randomUUID()  (Logging-Korrelation)    │
│  2. orgId aus dem Pfad ziehen → Org-Isolation prüfen          │
│  3. Dedupe-Anker prüfen (siehe Abschnitt 5) → ggf. früh raus  │
│  4. Empfängermenge ermitteln (Rollen-/Zuordnungslogik         │
│     serverseitig repliziert) → uids                           │
│  5. notificationPrefs je Empfänger filtern (Opt-out/Ruhezeit) │
│  6. Tokens laden: users/{uid}/fcmTokens/*  (collectionGroup    │
│     ODER per-User-Read, siehe Abschnitt 4)                    │
│  7. admin.messaging().sendEachForMulticast({tokens, ...})     │
│  8. Antwort auswerten → ungültige Tokens prunen (Abschnitt 2) │
│  9. (optional) Inbox-Dokument schreiben (Abschnitt 3)         │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
FCM → APNs / FCM-Android / Web-Push → Gerät
```

**Warum Firestore-Trigger statt Callable-Fan-out (verbindliche Entscheidung):**

- **Vollständigkeit / „Sicherheitslücke per Design".** Laut CLAUDE.md erlauben die Rules **direkte Client-Writes** auf `shifts`/`workEntries` und erzwingen die Callables **nicht** — direkte Writes umgehen die Compliance-Callable. Ein an die Callable gehängter Push würde alle diese Direkt-Writes verpassen. Konkret schreibt auch der Tausch-/Compliance-Override (`saveShifts` mit `skipCompliance=true` → `saveShiftBatchDirect`) direkt, ebenso der serverseitige OktoPOS-Pull (`source:'oktopos'`). Ein `onDocumentWritten`-Trigger auf der Collection feuert bei **jedem** Write — Callable, Direkt-Write, Admin-SDK — und ist damit der einzige Ort, der Benachrichtigungen garantiert.
- **Öffentliche anonyme Pfade haben keinen Mediator.** Kundenwunsch (`FirestoreService.submitCustomerWish`) und Feedback (`submitCustomerFeedback`) schreiben direkt aus den isolierten `PublicWishApp`/`PublicFeedbackApp` (anonyme Auth, keine Provider-Kette, kein go_router). Hier ist ein Client-Hook unmöglich und unerwünscht — der anonyme Client darf interne Empfänger nicht kennen. Nur ein serverseitiger `onDocumentCreated`-Trigger auf `customerWishes`/`customerFeedback` kann das.
- **Keine Empfänger-Auflösung im Client.** Rollen-/Zuordnungslogik (`canManageShifts`, `employeeSiteAssignments`, `TeamDefinition.memberIds`) zum Empfänger-Mapping gehört serverseitig (PII, Org-Isolation, kein org-übergreifendes Token-Leck). Der Trigger läuft mit Admin SDK und kann `users.where('orgId','==',orgId)` org-weit lesen — wie heute schon `functions/index.js` bei `loadCallerProfile`/OktoPOS.

**Bewusste Einschränkung (Storage-Modi):** Der Server-Trigger feuert nur, wenn ein **Firestore-Dokument** entsteht. Im **local-only**-Modus (`DataStorageLocation.local` bzw. `APP_DISABLE_AUTH`) gibt es kein Firestore-Doc → kein Push. Im **hybrid**-Offline-catch-Fallback wird zunächst nur lokal geschrieben → Push erst beim späteren Cloud-Sync (es gibt laut Architektur kein Outbox-Re-Sync). Das ist akzeptabel: Push ist inhärent cloud-/Blaze-gebunden und wird per `APP_PUSH_ENABLED` + Firebase-konfiguriert-Guard ohnehin nur im Online-/Cloud-Pfad aktiv. Ein clientseitiger Trigger in jedem Mutator-Zweig (analog `_audit?.call`) wäre die Alternative, ist aber über Multi-Device unzuverlässig/duplizierend und wird **verworfen**.

**Wrapper-Konvention:** `functions/index.js` hat heute den `callable(name, options, handler)`-Wrapper nur für `onCall`. Für Trigger wird ein **analoger `documentTrigger`-Wrapper** eingeführt (eigene `crypto.randomUUID()`-`requestId`, strukturiertes `trigger_start`/`trigger_done`/`trigger_error`-Logging, niemals Secrets/PII) — exakt nach dem Muster von `traceCallable`/`oktoposNightlySync`. Region wird wie überall via `{region: REGION}` mit `const REGION = "europe-west3"` gesetzt (Trigger-Pfad-Match ist regionsunabhängig, aber Konvention bleibt).

### 2. FCM-Geräte-Token-Lebenszyklus

Tokens liegen in der **Subcollection `users/{uid}/fcmTokens/{tokenId}`** (nicht als Array/Map am User-Doc). Begründung: mehrere Geräte je Nutzer ohne Array-Merge-Race, einfaches Pro-Gerät-Delete, kein 1-MB-Doc-Limit-Risiko, und konsistent mit den bestehenden Subcollection-Mustern (`priceHistory`, `stockMovements` mit Feld-Allowlist + Actor-Pinning).

**Doc-ID (`tokenId`):** **nicht** der rohe FCM-Token (kann >1500 Bytes werden → als Doc-ID grenzwertig), sondern die **`firebase_installations`-ID** (stabil pro App-Installation, ein Token-Doc je Gerät, natürliche Dedup bei Refresh). Der rohe Token bleibt als Feld.

**Felder je Token-Doc** (Zwei-Serialisierungs-Regel gilt nur, falls über eine Callable serialisiert; bei Direkt-Write camelCase):

| Feld | Typ | Zweck |
|---|---|---|
| `token` | String | aktueller FCM-Token (Sende-Adresse) |
| `platform` | String | `android` / `ios` / `web` (Channel-/Diagnose) |
| `orgId` | String | **Duplikat** des User-`orgId`; erlaubt `collectionGroup('fcmTokens').where('orgId','==',orgId)` ohne users-Join |
| `updatedAt` | Timestamp | letzter Refresh/Heartbeat; Basis für stale-Cleanup |
| `appVersion` | String | Diagnose / Force-Update-Korrelation (`AppConfig.buildNumber`) |

**Lebenszyklus (Client, neuer `PushNotificationService` nach dem `QuickActionsService`-Vorbild — No-op auf nicht unterstützten Plattformen, `kIsWeb`/Platform-Guard):**

1. **Holen:** Nach erfolgreichem Login + Permission-Grant `FirebaseMessaging.instance.getToken()` (Web zusätzlich `vapidKey:`). Schreiben via merge-set auf `users/{uid}/fcmTokens/{installationId}` (sauberer Weg: eine schlanke Callable `registerFcmToken` über den `_callRegisteredFunction`-Pfad, snake_case-Payload — alternativ self-Direkt-Write, da Rules es erlauben).
2. **Refresh:** `FirebaseMessaging.instance.onTokenRefresh` → dasselbe Doc per merge updaten (`token`, `updatedAt`). Da Doc-ID = Installation-ID, überschreibt sich der alte Token automatisch (kein Waisen-Doc).
3. **Multi-Device:** Pro Installation ein Doc → ein Nutzer mit Handy + Tablet + Web hat drei Docs. `sendEachForMulticast` adressiert alle.
4. **Logout-Cleanup:** Beim Abmelden das eigene Token-Doc löschen (`isSelf`-Delete erlaubt), damit ein abgemeldetes Gerät keine fremden Org-Pushes mehr bekommt.
5. **Server-Pruning bei Versand:** `sendEachForMulticast` liefert `response.responses[i]`. Bei `messaging/registration-token-not-registered` oder `messaging/invalid-registration-token` (404-äquivalent) wird das zugehörige Token-Doc per Admin SDK gelöscht. Zusätzlich kann ein periodischer Job (`updatedAt` älter als z. B. 270 Tage → FCM verfällt ohnehin) Altlasten räumen.

### 3. Datenmodell: Inbox-Persistenz vs. derived

Heute ist das „Anfragen"-Center (`notification_screen.dart`) **vollständig derived**: bei jedem `build()` werden ephemere `_InboxItem`-Objekte aus Live-Provider-Listen (`allAbsenceRequests`, `swapRequests`, `swapCredits`, `ordersDueSoonNotPrepared`, `lowStockProducts`) rekonstruiert. Es gibt **kein** persistiertes Notification-Model, **keine** Inbox-Collection und **keinen** gelesen/ungelesen-Status pro Ereignis; das Badge (`pendingInboxActionCount`) ist eine reine Live-Ableitung offener Vorgänge.

**Empfehlung: persistierte `notifications`-Collection (Inbox-Parität In-App↔Push).** Begründung:

- **Push braucht ein Pendant.** Eine Systembenachrichtigung ist flüchtig; tippt der Nutzer sie weg, muss er sie in der App wiederfinden. Ohne persistierte Historie gibt es nichts, worauf der Tap-Deep-Link zeigen kann, und kein „als gelesen markieren".
- **Der derived-Ansatz deckt nicht alle Push-Anlässe ab.** Kundenwünsche und Feedback erscheinen heute gar nicht in der Inbox; das Badge ignoriert Inventar/Bestellungen. Wenn Push breiter ist als das heutige Badge, divergieren In-App-Sicht und Push — eine eigene Collection schließt die Lücke ohne die fragile derived-Logik aufzubohren.
- **Konsistenter Schreibort.** Derselbe Trigger, der den Push sendet, schreibt das Inbox-Doc — ein Producer, garantierte Parität.

**Modell `AppNotification`** (Collection `organizations/{orgId}/notifications/{notificationId}`, org-skopiert wie alle Fachdaten; Zwei-Serialisierungs-Regel + `copyWith` mit `clearX` nach Kopplung #1):

| Feld | Zweck |
|---|---|
| `recipientUid` | Empfänger (ein Doc je Empfänger — einfaches `where('recipientUid','==',uid)` + per-User-Read-Status) |
| `category` | Enum (`shiftPublished`, `shiftSwapRequest`, `absenceSubmitted`, `absenceDecision`, `sickReplacement`, `customerWish`, `customerFeedback`, `lowStock`, `customerOrderDue` …) — `.value`-Getter snake_case, `fromValue` mit Default-Branch |
| `title` / `body` | deutsche Texte (Audit-Summaries sind die Vorlage); identisch zur FCM-Payload |
| `route` | Deep-Link-Ziel (z. B. `/anfragen`, `/feedback-eingang`, `/bestand-insights`) |
| `entityType` / `entityId` | Verknüpfung zur Quelle (wie Audit-Sink) |
| `createdAt` | Serverzeit, Sortier-/Verfallsanker |
| `readAt` | nullable; gesetzt = gelesen → ersetzt das heutige reine Live-Badge |
| `dedupeKey` | deterministischer Schlüssel zur Idempotenz (siehe Abschnitt 5) |

> **Bewusst NICHT persistiert / kein Push:** hochfrequentes Rauschen (Kühlschrank-Nachfüllliste je Mengenänderung, Bestellkorb, Vorlagen, Favoriten) — exakt die Quellen, die laut CLAUDE.md auch **nicht auditiert** werden. Meldebestand/Bestandsbewegungen werden nur **flankenbasiert + entprellt/gebündelt** zu einem Push (Schwellen-Übertritt `currentStock <= minStock`, nicht jeder Verkauf).

**Push-Präferenzen pro User** als verschachteltes Feld-Objekt `notificationPrefs` direkt am `users/{uid}`-Doc (Muster wie `permissions`/`workRuleSettings`/`settings`; eigenes Modell mit 4-fach-Serialisierung). Inhalt:

- **Kategorie-Opt-out:** ein Bool je `category` (Default rollenabhängig analog `UserPermissions.defaultsForRole` — z. B. Manager-Kategorien für employees aus).
- **Ruhezeiten:** `quietHoursStart`/`quietHoursEnd` (lokale Uhrzeit). Der Trigger unterdrückt während Ruhezeit den **System-Push**, schreibt aber weiterhin das Inbox-Doc (kein Informationsverlust). Optional: zeitunkritische Kategorien werden nach Ruhezeitende gebündelt nachgereicht.

Das `notificationPrefs`-Feld kollidiert **nicht** mit der strengen Self-Update-Rule (siehe unten), da es nicht Teil der Äquivalenzprüfung ist und keine `hasOnly`-Allowlist existiert — der Nutzer darf seine eigenen Prefs ändern, ohne Admin zu sein.

### 4. Firestore-Rules-Skizzen + Indizes

**Token-Subcollection** (eigener `match`-Block zwingend — Doc-Rules vererben **nicht** auf Subcollections; ohne Block greift Default-Deny). Read bewusst eng (PII; Versand läuft server-side via Admin SDK, Manager brauchen fremde Tokens nie):

```
match /users/{uid}/fcmTokens/{tokenId} {
  allow read, delete: if isSelf(uid);
  allow create, update: if isSelf(uid)
      && request.resource.data.keys().hasOnly(
           ['token','platform','orgId','updatedAt','appVersion'])
      && request.resource.data.orgId == currentOrgId()   // kein Org-Spoofing
      && request.resource.data.token is string;
}
```

**Inbox-Collection** (org-skopiert; nur eigene Notifications lesen, nur `readAt` selbst setzen dürfen — Erzeugung ausschließlich serverseitig per Admin SDK, analog `posReceipts` `allow write: if false`):

```
match /organizations/{orgId}/notifications/{notificationId} {
  allow read: if sameOrg(orgId)
      && resource.data.recipientUid == request.auth.uid;
  allow create, delete: if false;                 // nur Cloud Function (Admin SDK)
  allow update: if sameOrg(orgId)
      && resource.data.recipientUid == request.auth.uid
      && request.resource.data.diff(resource.data).affectedKeys()
           .hasOnly(['readAt']);                  // nur „gelesen"-Toggle
}
```

**Push-Präferenzen** brauchen **keinen** neuen Rules-Block: `notificationPrefs` lebt am bestehenden `users/{uid}`-Doc; der Self-Update-Zweig (Rules-Zeilen 414–432) prüft nur `orgId`/`role`/`email`/`isActive`/`permissions`/`workRuleSettings` auf Unveränderlichkeit und hat **keine** `hasOnly`-Allowlist — neue Felder sind im Self-Update zulässig. (Beim späteren Hinzufügen einer Allowlist `notificationPrefs` mit aufnehmen — als Kopplungs-Notiz.)

**Indizes** (`firestore.indexes.json`, deployen sonst Laufzeitfehler):

- **Inbox-Query:** `notifications` Composite `recipientUid ASC + createdAt DESC` (Liste „meine neuesten").
- **Token-Versand:** Bei serverseitigem `collectionGroup('fcmTokens').where('orgId','==',orgId)` ist ein **COLLECTION_GROUP**-Index auf `fcmTokens.orgId` nötig — bislang sind **alle** 18 Indizes (Stand 30.06.2026) `queryScope: COLLECTION` (vgl. `users`-Index `orgId+settings.name`). Alternativ pro Empfänger-uid die Subcollection direkt lesen (kein collectionGroup-Index, mehr Reads). **Empfehlung:** per-uid-Read, da die Empfängermenge je Event meist klein ist und `orgId`-Duplikat im Token-Doc trotzdem für Org-Sicherheit nützt.
- **Präferenz-gefilterte Empfänger-Query** (z. B. `users.where('orgId',==).where('notificationPrefs.shiftPublished',==,true)`): bräuchte `orgId + notificationPrefs.<flag>`. **Empfehlung:** Prefs nicht in der Query, sondern nach dem Laden der Empfänger im Function-Code filtern → kein zusätzlicher Index, flexibler bei vielen Kategorien.

### 5. Mandantenfähigkeit, Idempotenz, Skalierung

**Org-Isolation.** Der Trigger zieht `orgId` aus dem Pfad (`organizations/{orgId}/...`) und sammelt Empfänger **ausschließlich** innerhalb dieser Org (`users.where('orgId','==',orgId)`, `employeeSiteAssignments`/`teams` org-skopiert). Da das Token-Doc `orgId` dupliziert, kann zusätzlich vor dem Send geprüft werden, dass `token.orgId == orgId` — ein Token darf nie eine fremde Org adressieren. Das spiegelt `assertSameOrg`/`sameOrg` aus dem Callable-/Rules-Pfad.

**Empfänger-Auflösung** repliziert die Client-Sichtbarkeitslogik serverseitig (sonst Pushes für Vorgänge, die der Nutzer in der Inbox gar nicht sieht):
- *Manager-Events* (Abwesenheit eingereicht, Tausch-Annahme-Bestätigung, Feedback, Meldebestand): `role=='admin'` **oder** effektives `canEditSchedule` (nicht Rolle allein — `canManageShifts == isAdmin || canEditSchedule`). Die Default-Logik `permissionDefaultsForRole` ist in `functions/index.js` bereits vorhanden und wird wiederverwendet. Rollen-Normalisierung `teamleiter→teamlead` muss mitgezogen werden.
- *Personenbezogene Events* (Abwesenheits-Entscheidung, Schicht zugewiesen, Tausch-Ziel): konkrete uids aus den Modellfeldern (`userId`/`requesterUid`/`targetUid`/`reviewedByUid`/`vertreterUserIds`).
- *Standort-/Team-Events* (`publishShifts`, Meldebestand je `siteId`): `employeeSiteAssignments.where('siteId',==)` bzw. `TeamDefinition.memberIds`.
- Immer `isActive==true` filtern; Invite-only-Personen (nur `userInvites`, noch kein `users/{uid}`) haben keine uid/kein Token und werden toleriert übersprungen.

**Idempotenz / Dedupe (kein Doppelversand).** Firestore-Trigger sind **at-least-once** und feuern auch bei eigenen Re-Writes; `onDocumentWritten` zusätzlich bei jedem Status-Übergang. Drei Schutzmechanismen — exakt nach dem etablierten OktoPOS-Muster (`getAll`-Existenzcheck + `batch.create` als Einmaligkeits-Anker):

1. **Deterministischer `dedupeKey`** je logischem Ereignis, z. B. `${docId}:${category}:${recipientUid}:${statusFrom}->${statusTo}`. Das Inbox-Doc wird mit `batch.create(notifications.doc(dedupeKey))` angelegt — schlägt der `create` fehl (Doc existiert), wurde das Event schon verarbeitet → **kein** erneuter Send. Das ist derselbe Mechanismus wie `movementId`/`receiptId` beim OktoPOS-Pull.
2. **Flanken-Erkennung bei `onDocumentWritten`:** before/after vergleichen; nur echte fachliche Übergänge auslösen (z. B. `ShiftStatus planned→confirmed` beim Veröffentlichen, `absence pending→approved`). Reine Feld-Touches (z. B. `updatedAt`) lösen nichts aus.
3. **`event.id`** als zusätzlicher Idempotenzschlüssel gegen Trigger-Doppel-Feuerung derselben Invocation.

Gekoppelte Vorgänge erzeugen bewusst dosierte Pushes: Eine Krankmeldung (`sickness/childSick`) löst über `_releaseShiftsForSickAbsence` logisch zwei Anlässe aus (Genehmiger informieren + freigegebene Schicht ans Team) — der `dedupeKey` trennt diese sauber, verhindert aber Wiederholungen.

**Skalierung & Kosten (Blaze nur fürs Go-Live).** Das Projekt bleibt während der Entwicklung auf **Spark**; die Trigger werden bis zum Schluss lokal im **Emulator** ausgeführt und erst zum Go-Live auf **Blaze** deployt (siehe Abschnitt 5, Tarif-Strategie). `admin.messaging()` braucht kein zusätzliches Secret (Admin-SDK-Credentials), läuft produktiv aber nur auf Blaze. Kostentreiber sind Trigger-Invocations bei Batch-Writes: `publishShiftBatch` schreibt bis zu 50 Schichten → 50 Trigger-Feuerungen. Gegenmaßnahmen: (a) `publishShifts` erzeugt **eine** gebündelte „Plan veröffentlicht"-Notification je betroffenem Mitarbeiter statt einer je Schicht (Aggregation im Trigger über `dedupeKey` pro uid+Woche); (b) hochfrequente Collections (`workEntries`, Bestandsbewegungen) nur bei echten Statusflanken bzw. entprellt auslösen; (c) `sendEachForMulticast` bündelt mehrere Tokens eines Nutzers in einem Send.

### 6. AppConfig-Flag `APP_PUSH_ENABLED`

Sichtbarkeits-/Aktivierungs-Schalter analog `oktoposEnabled` — **kein Secret**, nur ein Compile-Time-Default. In `lib/core/app_config.dart`:

```dart
/// Schaltet mobile Push-Benachrichtigungen (FCM) frei. Default aus, bis
/// firebase_messaging integriert, APNs-Auth-Key (.p8) in der Firebase-Console
/// hinterlegt, der Web-VAPID-Key konfiguriert und die Sende-Cloud-Functions
/// deployt sind. Per `--dart-define=APP_PUSH_ENABLED=true` an.
/// **Kein Secret** — nur ein Sichtbarkeits-/Aktivierungs-Schalter.
static const bool pushEnabled = bool.fromEnvironment(
  'APP_PUSH_ENABLED',
  defaultValue: false,
);
```

Die FCM-Init wird **zweifach gegatet**: `AppConfig.pushEnabled` **und** `DefaultFirebaseOptions.isConfigured` (nicht nur `firebaseConfigured` — bei `APP_DISABLE_AUTH` ist Letzteres `true`, Firebase aber nicht initialisiert → jeder `FirebaseMessaging.instance`-Zugriff crasht). Sie liegt im Firebase-konfiguriert-Block von `_AppBootstrapState._initializeApp`, **nach** dem Setzen der Firestore-Settings, im `try/catch` **fail-open** (wie App Check — FCM darf den Start nie blockieren, sonst meldet `runZonedGuarded` einen fatalen Zonenfehler). `APP_PUSH_ENABLED` wird ins dart-define-Inventar in CLAUDE.md ergänzt.

### Code-Skizze: zentrale Sende-Function (Trigger)

```js
// functions/index.js — neuer Import + Wrapper (nach dem callable()-Vorbild)
const {onDocumentCreated, onDocumentWritten} =
    require("firebase-functions/v2/firestore");
const {getMessaging} = require("firebase-admin/messaging");

// Beispiel: Abwesenheitsantrag eingereicht → Manager benachrichtigen.
exports.onAbsenceRequested = onDocumentCreated(
  {region: REGION, document: "organizations/{orgId}/absenceRequests/{reqId}"},
  async (event) => {
    const requestId = crypto.randomUUID();
    const {orgId, reqId} = event.params;
    const data = event.data?.data();
    if (!data || normalizeStatus(data.status) !== "pending") return;

    // Dedupe-Anker: einmal pro logischem Ereignis (batch.create-Semantik).
    const dedupeKey = `${reqId}:absenceSubmitted`;

    // Empfänger = aktive Manager der Org (Rolle ODER canEditSchedule).
    const usersSnap = await db.collection("users")
        .where("orgId", "==", orgId).get();
    const recipients = usersSnap.docs
        .map((d) => ({uid: d.id, ...d.data()}))
        .filter((u) => isTruthy(u.isActive) && isManager(u)   // permissionDefaults
            && prefAllows(u, "absenceSubmitted"));            // Opt-out/Ruhezeit

    await fanOut(orgId, recipients, dedupeKey, {
      category: "absenceSubmitted",
      title: "Neuer Abwesenheitsantrag",
      body: `${displayNameOf(data)} hat Urlaub/Abwesenheit beantragt.`,
      route: "/anfragen",
      entityType: "absenceRequest", entityId: reqId,
    }, requestId);
  },
);

// Gemeinsamer Fan-out: Inbox-Doc (idempotent) + Multicast + Token-Pruning.
async function fanOut(orgId, recipients, dedupeKey, payload, requestId) {
  const notifCol = organizationCollection(orgId, "notifications");
  const tokenDocs = [];          // {ref, token, uid}
  for (const r of recipients) {
    // 1) Inbox-Doc idempotent anlegen (create schlägt fehl, wenn schon da).
    const ref = notifCol.doc(`${dedupeKey}:${r.uid}`);
    try {
      await ref.create({
        recipientUid: r.uid, ...payload, dedupeKey,
        createdAt: FieldValue.serverTimestamp(), readAt: null,
      });
    } catch (e) {
      continue;                  // bereits zugestellt → nicht erneut senden
    }
    // 2) Tokens des Empfängers sammeln (per-User-Read, kein CG-Index).
    const toks = await db.collection("users").doc(r.uid)
        .collection("fcmTokens").get();
    toks.forEach((t) => tokenDocs.push({ref: t.ref, token: t.get("token"), uid: r.uid}));
  }
  if (tokenDocs.length === 0) return;

  const resp = await getMessaging().sendEachForMulticast({
    tokens: tokenDocs.map((t) => t.token),
    notification: {title: payload.title, body: payload.body},
    data: {route: payload.route, category: payload.category,
           entityId: String(payload.entityId || ""), _request_id: requestId},
  });

  // 3) Ungültige Tokens prunen (404/unregistered).
  const stale = ["messaging/registration-token-not-registered",
                 "messaging/invalid-registration-token"];
  const dead = [];
  resp.responses.forEach((res, i) => {
    if (!res.success && stale.includes(res.error?.code)) dead.push(tokenDocs[i].ref);
  });
  await Promise.all(dead.map((ref) => ref.delete()));
  logger.info("push_fan_out_done", {requestId, sent: resp.successCount,
      failed: resp.failureCount, pruned: dead.length});
}
```

### Code-Skizze: Token-Repository (Client)

```dart
// lib/services/fcm_token_repository.dart — Lazy-Cloud-Repo-Muster:
// FirebaseMessaging/FirebaseFirestore NIE im Konstruktor auflösen.
class FcmTokenRepository {
  FcmTokenRepository(this._firestore);
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _tokens(String uid) =>
      _firestore.collection('users').doc(uid).collection('fcmTokens');

  /// Holt/aktualisiert den Token und persistiert ihn als ein Doc je
  /// Installation (Doc-ID = installationId → Self-Refresh überschreibt sauber).
  Future<void> registerCurrentDevice({
    required String uid, required String orgId,
    required String installationId, String? vapidKey,
  }) async {
    final token = await FirebaseMessaging.instance.getToken(vapidKey: vapidKey);
    if (token == null) return;
    await _tokens(uid).doc(installationId).set({
      'token': token,
      'platform': _platformLabel(),         // android/ios/web
      'orgId': orgId,
      'appVersion': AppConfig.buildNumber.toString(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// onTokenRefresh-Hook → dasselbe Doc updaten.
  Future<void> onRefresh(String uid, String installationId, String token) =>
      _tokens(uid).doc(installationId).set(
        {'token': token, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true));

  /// Logout: eigenes Gerät-Doc entfernen (isSelf-Delete erlaubt).
  Future<void> unregister(String uid, String installationId) =>
      _tokens(uid).doc(installationId).delete();
}
```

Der zugehörige `NotificationProvider` (In-App-Inbox-Speicher + Read-Status) wird wie `ContactProvider`/`InventoryProvider` als `ChangeNotifierProxyProvider` **nach** `AuthProvider`/`AuditProvider` in die `main.dart`-Kette gehängt, löst sein Cloud-Repo **lazy** auf und bindet via `setAuditSink` an — Details dazu im Abschnitt zur Provider-/Bootstrap-Integration.

---

## 2. Benachrichtigungs-Taxonomie & Empfänger-Routing

Dieser Abschnitt definiert den verbindlichen Katalog aller Push-Ereignisse, die serverseitige Auflösung der Empfänger (Org → Rolle/Team/Standort → aktive Tokens) und das einheitliche FCM-Payload-Schema. Inhaltliche Vorgaben:

- **Alle Texte Deutsch** (Hard-Locale `de_DE`); Datums-/Zeit-Platzhalter werden serverseitig mit `DateFormat(..., 'de_DE')`-Äquivalent (Cloud Function eigene Formatierung) gefüllt.
- **Zwei Läden in Kiel als zwei Standorte** (`SiteDefinition`-Docs, z. B. „Strichmännchen", „Tabak Börse") in EINER Org. Standort-Routing läuft über `Shift.siteId`, `employeeSiteAssignments.siteId` bzw. `FridgeRefillList`-Doc-ID (= `siteId`). Der Standortname (`{site}`) gehört in jeden standortbezogenen Body, damit ein Mitarbeiter mit Zuordnung zu beiden Läden sofort weiß, welcher Laden gemeint ist.
- **`{platzhalter}`** = serverseitig ersetzte Felder aus dem Quell-Dokument.
- **Deep-Link-Ziel** = realer go_router-Pfad (verifiziert in `lib/routing/shell_tab.dart` + `lib/routing/app_router.dart`). Das Kühlschrank-Ereignis nutzt `/warenwirtschaft?tab=kuehl` (Soll-Ist-Ansicht gem. Automatik-Plan); existiert für ein Ereignis keine eigene URL, wird auf den nächstgelegenen Pfad geleitet und ein Sheet clientseitig aus dem Tap geöffnet.

### Ereignis-Katalog

| Ereignis | Auslöser (Collection / Trigger) | Empfänger | Prio | Android-Channel / iOS-Kategorie | Titel (DE) | Text / Body (DE) | Deep-Link (go_router) | Gruppierung (`thread`/`tag`) |
|---|---|---|---|---|---|---|---|---|
| **Neuer Kundenwunsch** | `customerWishes` · onCreate (öffentl. anonymer Write via `submitCustomerWish`) | Alle aktiven Mitarbeiter der Org (read=sameOrg, bewusst breit) | Standard | `kundenwunsch` / `KUNDENWUNSCH` | Neuer Kundenwunsch | „{customerName} wünscht: {wishSummary}. Bitte vorbereiten." | `/kundenwuensche` (`AppRoutes.customerWishes`) | `wishes_{orgId}` |
| **Kundenbestellung bald fällig & nicht vorbereitet** | `customerOrders` · onUpdate / täglicher onSchedule (Fälligkeits-Check) | Mitarbeiter mit `canManageInventory` (Org, ggf. Standort der Bestellung) | Hoch | `bestellungen` / `BESTELLUNG` | Bestellung vorbereiten | „Bestellung für {customerName} ist am {dueDate} fällig und noch nicht vorbereitet." | `/bestellungen` (`AppRoutes.customerOrders`) | `orders_{orgId}` |
| **Kühlschrank: Nachfüllen nötig (Soll-Ist)** | Soll-Ist-Signal des **Automatik-Plans**: `products` onUpdate, Flanke Kühlschrank-Soll (`fridgeStock`) unterschritten; gebündelt je Standort | Aktive Mitarbeiter mit Zuordnung zu `siteId` (`employeeSiteAssignments`) | Niedrig | `kuehlschrank` / `BETRIEB` | Kühlschrank nachfüllen · {site} | „{openCount} Artikel zum Nachfüllen in {site}." (gebündelt, nicht pro Eintrag) | `/warenwirtschaft?tab=kuehl` (Ziel gem. Automatik-Plan) | `fridge_{siteId}` (collapse) |
| **Schichtplan veröffentlicht** | `shifts` · `publishShiftBatch` / onWrite (`status` → `confirmed`) | Jede(r) Mitarbeiter(in) mit ≥1 Schicht im Batch (`shift.userId`) | Hoch | `schichtplan` / `SCHICHT` | Schichtplan veröffentlicht | „Dein Plan für KW {week} ({site}) steht: {shiftCount} Schichten." | `/plan` (`ShellTab.plan`) | `plan_{orgId}_{week}` |
| **Schicht zugewiesen / geändert** | `shifts` · onWrite (`userId`-Wechsel oder Zeit/Standort geändert) | Neu zugewiesene(r) MA (`shift.userId`); bei Umbesetzung zusätzlich vorher Zugewiesene(r) | Hoch | `schichtplan` / `SCHICHT` | Neue Schicht · {site} | „{date}, {startTime}–{endTime} in {site}." | `/plan` | `plan_{orgId}_{week}` |
| **Schichttausch-Anfrage gestellt** | `shiftSwapRequests` · onCreate (`status=pending`) | Ziel-Kollege (`targetUid`) | Hoch | `schichttausch` / `SCHICHT` | Tauschanfrage | „{requesterName} möchte am {requesterShiftDate} mit dir tauschen." | `/anfragen` (`ShellTab.inbox`) | `swap_{requestId}` |
| **Tausch: Kollege hat angenommen** | `shiftSwapRequests` · onUpdate (`status=accepted_by_colleague`) | Mitarbeiter mit `canEditSchedule` (Genehmiger) | Hoch | `schichttausch` / `SCHICHT` | Tausch bestätigen | „{targetName} hat den Tausch mit {requesterName} angenommen. Bitte bestätigen." | `/anfragen` | `swap_{requestId}` |
| **Tausch: Kollege hat abgelehnt** | `shiftSwapRequests` · onUpdate (`status=declined_by_colleague`) | Antragsteller (`requesterUid`) | Standard | `schichttausch` / `SCHICHT` | Tausch abgelehnt | „{targetName} hat deine Tauschanfrage abgelehnt." | `/anfragen` | `swap_{requestId}` |
| **Tausch: Chef bestätigt** | `shiftSwapRequests` · onUpdate (`status=confirmed`) | Beide Beteiligten (`requesterUid` + `targetUid`) | Hoch | `schichttausch` / `SCHICHT` | Tausch bestätigt | „Dein Tausch mit {otherName} am {shiftDate} ist bestätigt." | `/plan` | `swap_{requestId}` |
| **Tausch: Chef lehnt ab / zurückgezogen** | `shiftSwapRequests` · onUpdate (`status=rejected_by_manager` / `cancelled`) | Bei reject: beide; bei cancel: `targetUid` | Standard | `schichttausch` / `SCHICHT` | Tausch abgelehnt | „Der Tausch am {shiftDate} wurde nicht durchgeführt." | `/anfragen` | `swap_{requestId}` |
| **Abwesenheits-/Urlaubsantrag gestellt** | `absenceRequests` · onCreate (`status=pending`) | Mitarbeiter mit `canEditSchedule` (Genehmiger) | Standard | `abwesenheit` / `ANTRAG` | Neuer Antrag | „{employeeName}: {absenceTypeLabel} {startDate}–{endDate}." | `/anfragen` | `absence_{requestId}` |
| **Abwesenheit genehmigt** | `absenceRequests` · onUpdate (`status=approved`) | Antragsteller (`userId`) | Standard | `abwesenheit` / `ANTRAG` | Antrag genehmigt | „Dein {absenceTypeLabel} vom {startDate} bis {endDate} ist genehmigt." | `/zeit/abwesenheiten` (`AppRoutes.zeitAbwesenheiten`) | `absence_{requestId}` |
| **Abwesenheit abgelehnt** | `absenceRequests` · onUpdate (`status=rejected`) | Antragsteller (`userId`) | Standard | `abwesenheit` / `ANTRAG` | Antrag abgelehnt | „Dein {absenceTypeLabel} vom {startDate}–{endDate} wurde abgelehnt." | `/zeit/abwesenheiten` | `absence_{requestId}` |
| **Krankmeldung → Schicht freigegeben** | `absenceRequests` · onUpdate (`type∈{sickness,childSick}`, Schichtfreigabe via `_releaseShiftsForSickAbsence`) | Mitarbeiter mit `canEditSchedule` + Team/Standort der freigegebenen Schicht | Hoch | `schichtplan` / `SCHICHT` | Schicht offen · {site} | „{employeeName} ist krank — Schicht {date} {startTime}–{endTime} in {site} ist offen." | `/plan` | `plan_{orgId}_{week}` |
| **Bestand unter Meldebestand** | `products` · onUpdate (Flanken­erkennung `needsReorder` false→true) bzw. OktoPOS-Pull-Stelle in `functions/index.js` | `canManageInventory` (Org; ggf. Standort über `siteId` des Produkts/Bewegung) | Standard | `bestand` / `BETRIEB` | Nachbestellen · {site} | „{productName}: nur noch {currentStock} {unit} (Meldebestand {minStock})." | `/warenwirtschaft?tab=korb` (`AppRoutes.inventory`) | `lowstock_{siteId}` (collapse) |
| **Neues Feedback / Beschwerde** | `customerFeedback` · onCreate (öffentl. anonymer Write via `submitCustomerFeedback`) | NUR Manager/Admin (`canManageFeedback` = isActive && (isAdmin \|\| canEditSchedule)) | Hoch bei `complaint`, sonst Standard | `feedback` / `FEEDBACK` | Neues {feedbackTypeLabel} | „{feedbackTypeLabel}: {feedbackExcerpt}" | `/feedback-eingang` (`AppRoutes.feedbackInbox`) | `feedback_{orgId}` |
| **Zeiteintrag eingereicht** | `workEntries` · onWrite (`status=submitted`) | Mitarbeiter mit `canEditTimeEntries` (Genehmiger) | Niedrig | `zeit` / `ZEIT` | Zeiteintrag prüfen | „{employeeName} hat den {entryDate} zur Freigabe eingereicht." | `/zeit/erfassung` (`AppRoutes.zeitErfassung`) | `time_{orgId}` |
| **Zeiteintrag genehmigt / abgelehnt** | `workEntries` · onWrite (`status∈{approved,rejected}`) | Mitarbeiter (`entry.userId`) | Niedrig | `zeit` / `ZEIT` | Zeiteintrag {approved?„genehmigt":„abgelehnt"} | „Dein {entryDate} wurde {…}." | `/zeit/erfassung` | `time_{orgId}` |
| **Monatsabschluss-Erinnerung** | onSchedule (z. B. 27.–letzter Tag, opt-in je Org) | `canEditSchedule` (Abschluss-Berechtigte) | Niedrig | `zeit` / `ZEIT` | Monatsabschluss fällig | „Der Monatsabschluss für {monthName} steht noch aus." | `/zeit/monatsabschluss` (`AppRoutes.zeitMonatsabschluss`) | `monthclose_{orgId}_{month}` |

**Hinweise zur Taxonomie**

- **Drei Prioritätsstufen** mappen auf FCM/Plattform: *Hoch* → `android.notification.notification_priority = PRIORITY_HIGH` + iOS `interruption-level: active`; *Standard* → Default; *Niedrig* → `PRIORITY_LOW` (Android-Channel mit `IMPORTANCE_LOW`, kein Ton), iOS `passive`. Die Priorität ist Channel-gebunden (Android-Channel-Importance ist nach Anlage user-übersteuerbar) — die Channel-Liste oben ist damit gleichzeitig die anzulegende `NotificationChannel`-Liste.
- **Entprellung / Anti-Spam:** Hochfrequente Quellen (Kühlschrank-Soll-Ist + `products`-Meldebestand) senden **gebündelt** mit `collapse_key`/`tag` (Android) bzw. `apns-collapse-id` (iOS) je `{siteId}` — eine neue Push überschreibt die vorige statt sich zu stapeln. Pro-Mengenänderung-Push (jeder Verkauf, jede Soll-Ist-Änderung) ist bewusst ausgeschlossen (entspricht dem Audit-Rauschen-Prinzip: Kühlschrank/Bestellkorb werden nicht auditiert). Nur die **Flanke** „Standort hat jetzt offene Defizite" löst aus.
- **Gekoppelte Ereignisse:** Eine Krankmeldung erzeugt logisch zwei Anlässe (Antrag-genehmigt → Antragsteller, Schicht-frei → Team). Diese laufen über **getrennte Trigger** (`absenceRequests`-Status vs. `shifts`-Freigabe-Write) mit unterschiedlichen `tag`s, dürfen sich also nicht überschreiben.
- **Standort-Asymmetrie:** Mitarbeitende ohne `employeeSiteAssignment` zu einem Laden bekommen standortbezogene Pushes (Kühlschrank, Meldebestand) dieses Ladens **nicht** — Org-weite Ereignisse (Kundenwunsch) erreichen alle.

### Serverseitiges Empfänger-Auflösungs-Verfahren

Alle Trigger laufen als Cloud Functions (Region `europe-west3`, Admin SDK, umgeht Rules — wie der OktoPOS-Pull). Die Auflösung erfolgt in vier Stufen und **dupliziert die Rollen-/Permission-Logik** serverseitig (analog zu `permissionDefaultsForRole`/`compliance_service ↔ functions`), da die Sichtbarkeit heute nur im Client (`notification_screen`, `pendingInboxActionCount`) lebt:

```
resolveRecipients(orgId, event):
  1. ORG-FILTER:    db.collection('users').where('orgId','==',orgId)
                    .where('isActive','==',true)            // deaktivierte nie pushen
                    // orgId muss normalisiert sein (Top-Level users, Feld orgId)
  2. ZIELGRUPPE je Ereignis:
     a) ROLLE:      effectiveCanEditSchedule(u) = u.role=='admin'
                       || permissionFlag(u,'canEditSchedule', defaultForRole(u.role))
                    // NICHT über role=='teamlead' allein filtern — employee mit
                    //   canEditSchedule ist Manager, teamlead kann es entzogen sein.
                    // role serverseitig normalizeRole() (teamleiter→teamlead).
        canManageInventory(u) / canManageFeedback(u) analog aus Permissions+Rolle.
     b) EINZELNUTZER (targetUid/requesterUid/userId/reviewedByUid/entry.userId):
                    direkt als uid-Menge — kein Query nötig.
     c) TEAM:       Team-Doc lesen → teamDoc.memberIds (Array von uids).
                    Kein teamId-Feld am User → immer über Team-Doc.
     d) STANDORT:   db.collection('organizations').doc(orgId)
                       .collection('employeeSiteAssignments')
                       .where('siteId','==',siteId) → userId-Liste.
                    Alternativ ereignisbezogen über shifts.where('siteId',==).
  3. UNION/DEDUP:   Empfänger-uids vereinigen, deduplizieren, Absender (actorUid)
                    optional ausschließen (keine Selbst-Benachrichtigung).
  4. TOKENS:        je uid users/{uid}/fcmTokens/* lesen (Admin SDK) → aktive Tokens.
                    Versand in 500er-Chunks via getMessaging().sendEachForMulticast().
                    Stale Tokens (messaging/registration-token-not-registered) löschen.
```

Begründete Festlegungen:

- **isActive-Filter ist Pflicht** (deaktivierte Nutzer dürfen keine Pushes erhalten) — entspricht der `isActiveUser()`-Rule.
- **Manager-Empfänger nie über die Rolle allein**, sondern über das effektive `canEditSchedule`/`canManageInventory`/`canManageFeedback`-Flag (Admin = immer true), mit Rolle→Default→gespeicherte Permissions in genau dieser Reihenfolge.
- **Org-Isolation** (`sameOrg`) gilt im Push-Pfad genauso wie in Rules/Functions: jeder Empfänger-Query filtert hart auf `orgId`; kein org-übergreifendes Sammeln.
- **Invite-only-Personen** (nur `userInvites`, noch kein `users/{uid}`) haben keine uid und kein Token → werden toleriert übersprungen.
- **Storage-Modus-Grenze:** Server-Trigger feuern nur, wenn ein Firestore-Dokument existiert (cloud/hybrid-online). Im `local`-Modus und im hybrid-Offline-catch-Fallback existiert kein Cloud-Doc → kein Server-Push (bewusste, dokumentierte Lücke; kein Outbox-Re-Sync).

### Einheitliches FCM-Payload-Schema

Jede Push verwendet **immer beide Blöcke** — `data` (für deterministisches In-App-Routing aus dem Tap, auch im Hintergrund vom `firebase-messaging-sw.js` lesbar) und `notification` (für die System-Darstellung). Channel/Kategorie und Collapse stehen in den plattformspezifischen Sub-Objekten.

```jsonc
{
  // Stabile, maschinenlesbare Routing-Daten (alle Werte sind Strings):
  "data": {
    "type":     "shift_swap_request",      // kanonischer Ereignistyp (snake_case)
    "entityId": "<requestId|shiftId|...>",  // Quell-Doc-ID
    "deepLink": "/anfragen",                // realer go_router-Pfad
    "orgId":    "<orgId>",                  // für Multi-Account-Geräte-Filter
    "siteId":   "<siteId|''>",              // bei Standort-Ereignissen, sonst leer
    "thread":   "swap_<requestId>"          // = notification thread/tag (Gruppierung)
  },
  // Menschlich lesbare, bereits DE-formatierte Anzeige:
  "notification": { "title": "Tauschanfrage", "body": "Peter möchte am 03.07. mit dir tauschen." },
  "android": {
    "collapseKey": "swap_<requestId>",
    "notification": {
      "channelId": "schichttausch",         // = anzulegender NotificationChannel
      "tag": "swap_<requestId>",            // ersetzt vorige Push gleicher Gruppe
      "notificationPriority": "PRIORITY_HIGH"
    }
  },
  "apns": {
    "headers": { "apns-collapse-id": "swap_<requestId>", "apns-priority": "10" },
    "payload": { "aps": { "category": "SCHICHT", "thread-id": "swap_<requestId>",
                          "interruption-level": "active" } }
  }
}
```

**Mapping-Logik (Ereignis → Payload), serverseitig zentral:**

1. `type` ist der kanonische snake_case-Schlüssel (Spalte „Ereignis"), eindeutig pro Zeile; clientseitig ist `type` die `switch`-Achse für Foreground-Handling/Analytics.
2. `deepLink` ist **immer ein realer go_router-Pfad** aus der Tabelle. Beim Tap übernimmt der Client `context.go`/`context.push` auf `data.deepLink`. Das Kühlschrank-Ereignis (`type=fridge_refill`) leitet auf `/warenwirtschaft?tab=kuehl` (Kühlschrank-Soll-Ist-Ansicht gem. Automatik-Plan); die Query `tab=kuehl` ist im Automatik-Plan definiert, hier nur konsumiert.
3. `data.orgId` wird auf dem Gerät gegen das aktuell eingeloggte Profil geprüft — Pushes für eine andere Org werden verworfen (Multi-Account-Schutz).
4. `notification.title/body` werden **serverseitig** aus den `{platzhalter}` der Tabelle und den Quell-Doc-Feldern (DE-formatierte Datums-/Mengen-Werte) gerendert; der Client formatiert nicht nach.
5. `channelId` (Android) und `aps.category` (iOS) stammen aus der Channel-Spalte; die Priorität pro Zeile setzt `notificationPriority` bzw. `apns-priority`/`interruption-level`.
6. `thread`/`tag`/`collapseKey`/`apns-collapse-id` tragen denselben Gruppierungs-Schlüssel (Spalte „Gruppierung") → mehrere Pushes zum selben Vorgang (z. B. Tausch-Lebenszyklus) stapeln nicht, sondern aktualisieren die bestehende Benachrichtigung.

> **Standort-Routing-Merksatz:** `data.siteId` ist die einzige verlässliche Maschinen-Referenz auf den betroffenen Laden; der Standortname steht zusätzlich im `body` (`{site}`), weil ein Mitarbeiter mit Zuordnung zu beiden Kieler Läden Strichmännchen und Tabak Börse nicht unterscheiden kann, wenn nur die uid/siteId zugestellt wird.

---

## 3. Client-Integration & Plattform-Setup

Dieser Abschnitt beschreibt die clientseitige Integration von Firebase Cloud Messaging (FCM) in die bestehende WorkTime-Codebasis sowie das plattformspezifische Setup für iOS, Android und Web. Das Datenmodell (Token-Collection, `notificationPrefs`), das Empfänger-Routing und die sendenden Cloud Functions sind Gegenstand anderer Abschnitte; hier geht es ausschließlich um Paket-Einbindung, Bootstrap-Anbindung, Permission-UX, Message-Handling, Token-Lifecycle im Client und die nativen Build-Schritte.

**Leitprinzip:** Push ist ein reines Cloud-/Hybrid-Feature. Im `APP_DISABLE_AUTH`-Offline-Demo-Modus und auf nicht konfigurierten Builds (`!DefaultFirebaseOptions.isConfigured`) wird die gesamte FCM-Schicht zu einem **No-op** — analog zu `QuickActionsService` (`_isSupported`) und `FirebaseAppCheck` (gated auf `AppConfig.appCheckEnabled`, fail-open).

### 1. Neue Pakete (pubspec.yaml)

Zwei Pakete, eingefügt im Firebase-Block (`pubspec.yaml`, nach Zeile 51 `firebase_app_check`):

```yaml
  # Push-Benachrichtigungen (FCM). Versionen kompatibel zu firebase_core ^3 /
  # cloud_functions ^5 wählen (BOM-Linie wie firebase_auth ^5 / firestore ^5.4).
  # Achtung iOS: zieht das echte FirebaseMessaging-Pod (heute nur transitiv
  # FirebaseMessagingInterop via App Check/Auth) -> pod install nötig.
  firebase_messaging: ^15.1.0
  # Pflicht, um Foreground-Pushes sichtbar zu machen und den Android-
  # Notification-Channel anzulegen (firebase_messaging zeigt im Vordergrund
  # NICHTS automatisch an).
  flutter_local_notifications: ^17.2.0
```

Begründung der zweiten Abhängigkeit: `firebase_messaging` rendert Systembenachrichtigungen nur automatisch, wenn die App im **Hintergrund/terminiert** ist und die Server-Payload einen `notification`-Block enthält. Im **Vordergrund** (`onMessage`) gibt es keine sichtbare Anzeige — dafür braucht es `flutter_local_notifications`. Zugleich definiert dieses Paket den Android-`NotificationChannel`, ohne den Notifications auf Android 8+ verworfen werden.

> Versions-Hinweis (wie der dokumentierte `mobile_scanner`-Pod-Konflikt): Vor dem Commit `flutter pub get` + iOS `pod install` laufen lassen und prüfen, dass keine `GTMSessionFetcher`/Firebase-SDK-Versionskonflikte entstehen. `firebase_messaging` muss zur installierten `firebase_core ^3.4.0`-BOM passen.

Neues Feature-Flag in `lib/core/app_config.dart` (exakt nach dem `oktoposEnabled`-Muster, Z.142-145):

```dart
/// Schaltet Push-Benachrichtigungen (FCM) frei. Default aus, bis APNs-Key
/// (iOS), Web-VAPID-Key und die sendenden Functions deployt sind.
/// Kein Secret — nur ein Sichtbarkeits-/Aktivierungs-Schalter.
static const bool pushEnabled = bool.fromEnvironment(
  'APP_PUSH_ENABLED',
  defaultValue: false,
);

/// Web-Push-Zertifikat (VAPID public key) aus Firebase-Console >
/// Cloud Messaging > Web Push certificates. NUR für Web nötig
/// (getToken(vapidKey:)); leer => Web-Token wird nicht angefordert.
static const String webPushVapidKey = String.fromEnvironment(
  'APP_WEB_PUSH_VAPID_KEY',
);
```

Beide Keys gehören ins dart-define-Inventar in `CLAUDE.md` (analog `APP_OKTOPOS_ENABLED`).

### 2. Init-Punkt im Bootstrap + NotificationProvider

**FCM-Init** gehört in `_AppBootstrapState._initializeApp` (`lib/main.dart`), **innerhalb** des Firebase-konfiguriert-Blocks (Z.128-174), **nach** dem Setzen der Firestore-Settings (Z.173) — das ist der einzige Punkt, an dem Firebase garantiert initialisiert ist. Gating wie bei App Check, fail-open im catch:

```dart
// nach FirebaseFirestore.instance.settings = _buildFirestoreSettings();
if (AppConfig.pushEnabled && !_publicMode) {
  try {
    // Background-Handler MUSS ein Top-Level- oder static-Funktion sein und
    // VOR runApp registriert werden (FCM ruft ihn in einem eigenen Isolate).
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await PushMessagingService.instance.initialize();
  } catch (error, stackTrace) {
    // Push darf den Start nie blockieren (fail-open wie App Check).
    ErrorReporter.report(error, stackTrace,
        context: 'PushMessagingService.initialize');
  }
}
```

Wichtig: Der `_publicMode`-Guard (Z.109-113: `/wunsch`, `/feedback`, `/impressum`, `/datenschutz`) ist zwingend — diese isolierten öffentlichen Hüllen haben keine Provider-Kette, keinen go_router und sollen keine Push-Permission anfragen. Zusätzlich greift implizit `DefaultFirebaseOptions.isConfigured`, weil der gesamte Block nur dann läuft (im `APP_DISABLE_AUTH`-Demo ohne echte Firebase-Config ist `isConfigured` false → Block übersprungen → FCM-Init nie erreicht). Damit gilt: `APP_DISABLE_AUTH=true` ⇒ kein `FirebaseMessaging.instance`-Zugriff ⇒ kein Crash.

**PushMessagingService** (neu, `lib/services/push_messaging_service.dart`) ist ein plattform-sicherer Singleton nach dem `QuickActionsService`-Vorbild — kapselt FCM-SDK-Aufrufe, hält `_isSupported`/`_initialized`-Guards, und löst `FirebaseMessaging.instance` **nie im Konstruktor** auf (Lazy-Cloud-Repo-Muster, sonst Crash im Demo-Modus). Er kennt keinen Provider-State, weil Token-Refresh und Background-Handler außerhalb des Widget-Baums feuern. Eine injizierte `navigate`-Callback-Funktion (wie bei `QuickActionsService.navigate`) übernimmt das Deep-Linking.

**NotificationProvider** (neu, `lib/providers/notification_provider.dart`) ist der In-App-Speicher (siehe Punkt 7). Er wird wie `ContactProvider`/`InventoryProvider` als `ChangeNotifierProxyProvider2<AuthProvider, StorageModeProvider, NotificationProvider>` in die `main.dart`-Kette gehängt — **nach `AuditProvider`** (damit `setAuditSink(audit.log)` verfügbar ist) und nach `AuthProvider` (Kopplung #4). Konkret zwischen `ContactProvider` und `PersonalProvider` einfügen. Der `update`-Callback folgt dem Standardmuster:

```dart
provider ??= NotificationProvider(firestoreService: firestoreService);
provider.setAuditSink(audit.log);
_dispatchProviderUpdate(
  provider.updateSession(
    auth.profile,
    localStorageOnly: storage.isLocalOnly,
    hybridStorageEnabled: storage.isHybrid,
  ),
  'NotificationProvider.updateSession',
  onError: provider.surfaceSessionError,
);
```

Der Provider löst sein Cloud-Repository lazy auf (Getter, nie im Konstruktor) und respektiert die Drei-Speichermodi-Regel: im local-/`disableAuth`-Modus bleibt er leer/inaktiv (kein FCM, keine Cloud-Reads).

**Token-Brücke Service → Provider:** Nach erfolgreichem Login/Profil-Auflösung (in `updateSession`, wenn `usesLocalStorage == false` und ein Profil vorliegt) ruft der `NotificationProvider` `PushMessagingService.instance.registerForUser(uid, orgId)` auf. So bleibt der reine SDK-Service vom Provider-State entkoppelt, und die Token-Registrierung passiert erst, wenn eine adressierbare uid existiert.

### 3. Berechtigungs-Anfrage-UX (Wann fragen?)

**Nicht** beim Cold-Start fragen — eine Permission-Anfrage vor dem ersten sinnvollen Kontext führt zu hoher Ablehnungsquote (gleiche Vorsicht wie bei der Quick-Actions-/Gate-Redirect-Logik). Stattdessen **kontextuell nach erfolgreichem Login**, sobald Auth/Profil aufgelöst und der Nutzer aktiv ist — der erste stabile Moment ist die montierte Shell.

Empfohlener Ablauf:

1. **Pre-Permission-Hinweis (Soft-Ask):** Beim ersten Erreichen der Shell nach Login zeigt ein dezentes deutsches Bottom-Sheet (`showModalBottomSheet(showDragHandle: true, …)`, UI-Konvention) eine Erklärung: „WorkTime kann dich benachrichtigen, wenn ein Schichtplan veröffentlicht wird, ein Kundenwunsch vorzubereiten ist oder der Kühlschrank nachgefüllt werden muss." Buttons: „Benachrichtigungen erlauben" / „Später". Wird nur einmal gezeigt (Flag in `UserSettings`/SharedPreferences), damit kein erneutes Nerven bei Ablehnung.
2. **System-Prompt:** Erst bei „Erlauben" → `FirebaseMessaging.instance.requestPermission(...)`. Das löst:
   - **iOS:** den nativen APNs-Berechtigungs-Dialog (`alert`/`badge`/`sound`).
   - **Android 13+ (API 33):** den `POST_NOTIFICATIONS`-Runtime-Dialog. (Realer Wert ist `minSdk = flutter.minSdkVersion` aus [build.gradle.kts](../android/app/build.gradle.kts) — Flutter-Default, vor Implementierung den effektiven API-Level prüfen; der Runtime-Flow ist ab API 33 ohnehin relevant, der Manifest-Eintrag allein genügt dann nicht.) Auf Android < 13 ist die Permission implizit erteilt.
   - **Web:** den Browser-`Notification.requestPermission`-Prompt. Auf Web-FCM zusätzlich `getToken(vapidKey: AppConfig.webPushVapidKey)` (siehe Punkt 6).
3. Bei `AuthorizationStatus.denied`/`notDetermined` keine weiteren Prompts; die App bleibt voll funktionsfähig (In-App-Inbox existiert weiter). Den Zustand für eine spätere Einstellungs-Seite („Benachrichtigungen aktivieren" verlinkt in die System-Einstellungen) merken.

Da der Soft-Ask nur im Shell-Kontext (mit `AuthProvider.isAuthenticated && profile.isActive`) erscheint, greift er nicht in den öffentlichen Routen und nicht im Demo-Modus.

### 4. Foreground / Background / Terminated-Handling

Drei Lebenszyklus-Pfade, alle im `PushMessagingService` verdrahtet:

- **Foreground (`FirebaseMessaging.onMessage`):** App ist sichtbar → FCM zeigt **nichts** automatisch. Der Stream-Listener (a) übergibt das Event an den `NotificationProvider` (In-App-Eintrag + Badge-Update, Punkt 7) und (b) rendert eine sichtbare Systembenachrichtigung via `flutter_local_notifications` über den definierten Android-Channel/iOS-Presentation-Options. Optional zusätzlich ein In-App-Banner — dafür müsste ein app-weiter `GlobalKey<ScaffoldMessengerState>` in `WorkTimeApp` eingeführt werden (existiert heute nicht), der an `MaterialApp.router(scaffoldMessengerKey:)` hängt.
- **Background, App läuft (`FirebaseMessaging.onMessageOpenedApp`):** Nutzer tippt die Systembenachrichtigung an → Stream liefert die `RemoteMessage`. Deep-Link auswerten (siehe unten).
- **Terminated, Cold-Start aus Notification (`FirebaseMessaging.instance.getInitialMessage()`):** Einmalig beim Init prüfen, ob die App durch einen Notification-Tap gestartet wurde → identisches Deep-Linking, aber **route bleibt pending bis nach dem Login**.
- **Background/terminiert, Daten-Payload (`onBackgroundMessage`):** Der Top-Level-Handler `firebaseMessagingBackgroundHandler` läuft in einem eigenen Isolate (kein Provider-State, kein Widget-Baum) und sollte nur leichtgewichtig sein. Die eigentliche Anzeige übernimmt FCM aus dem `notification`-Block der Server-Payload.

**Deep-Link in go_router:** Die Server-Payload trägt im `data`-Map ein `route`-Feld (deutsche go_router-Pfade, z.B. `/anfragen`, `AppRoutes.feedbackInbox`). Die Navigation läuft über das **bewährte Pending-Route-Muster von `QuickActionsService`** statt eines direkten `context.go`:

- Bei `onMessageOpenedApp`/`getInitialMessage` setzt der Service eine pending route und ruft den injizierten `navigate`-Callback (`rootNavigatorKey.currentContext?.go(route)`) — exakt wie `QuickActionsService.navigate` in `WorkTimeApp.initState` (`main.dart` Z.289-292).
- Beim **Cold-Start aus Notification** ist der Router beim Permission-/Auth-Gate noch nicht am Ziel. Deshalb wird die Route — wie bei Quick Actions — erst im **`_gateRedirect`** (`lib/routing/app_router.dart` Z.222-237) zugestellt, nachdem `auth.isAuthenticated && profile.isActive` gilt. Dafür wird die Push-Pending-Route in dieselbe `takePendingRoute()`-Senke gelegt (oder eine analoge zweite Quelle ergänzt), inklusive des bestehenden `RoutePermissions.isLocationAllowed(route, profile)`-Checks — so kann niemand per Notification-Tap auf eine Route ohne Berechtigung springen, und die Redirect-Schleifen-Sicherheit (idempotentes `take`) bleibt erhalten.

Damit ist das Push-Routing **gate-konform und cold-start-sicher** und dupliziert die Sicherheits-/Permission-Grenze nicht.

### 5. Token-Registrierung / -Refresh im Client

Im `PushMessagingService.registerForUser(uid, orgId)`:

- **Initial:** Auf iOS zuerst auf den APNs-Token warten (`getAPNSToken()`), dann `getToken()` (Web: mit `vapidKey`). Plattform-Wert (`web`/`android`/`ios`) und `appVersion` mitführen.
- **Persistenz:** Token über den Token-Repository-/Callable-Pfad an die Subcollection `users/{uid}/fcmTokens/{tokenId}` schreiben (Datenmodell separat). Schreiben **nur** im Cloud-/Hybrid-Modus (`usesLocalStorage == false`); im local-Modus No-op.
- **Refresh:** `FirebaseMessaging.instance.onTokenRefresh.listen(...)` ersetzt den persistierten Token (FCM rotiert Tokens). Listener im Service halten, mit `_disposed`-Schutz-Äquivalent / Re-Registrierung pro Session.
- **Logout / Nutzerwechsel:** Beim Abmelden den aktuellen Geräte-Token-Eintrag löschen und `FirebaseMessaging.instance.deleteToken()` aufrufen, damit der nächste Nutzer auf demselben Gerät keine Pushes des Vorgängers erhält. Anbindung über `NotificationProvider.updateSession` (Profil → null) bzw. den Auth-Logout-Pfad.
- **Stale-Token-Cleanup** passiert serverseitig (Function entfernt Tokens bei `messaging/registration-token-not-registered`) — der Client muss das nicht abdecken.

### 6. Plattform-Setup-Schritte

**iOS** (alle vier Punkte sind gekoppelt — einzeln bleibt Push wirkungslos):
- **APNs-Key (Betreiber, nicht im Repo):** APNs-Auth-Key (`.p8`, mit Team-ID + Key-ID) in Firebase-Console → Project Settings → Cloud Messaging hinterlegen. Ohne den liefert FCM auf iOS gar nichts.
- **Capability + Entitlement:** In Xcode „Push Notifications" + „Background Modes → Remote notifications" aktivieren. Das erzeugt eine **neue** `ios/Runner/Runner.entitlements` (heute existiert keine) mit `aps-environment` und setzt `CODE_SIGN_ENTITLEMENTS` in `project.pbxproj`. **`aps-environment` muss zum Build-Typ passen** (`development` für Debug, `production` für Release/TestFlight/Store) — falsche Umgebung = stille Nicht-Zustellung (klassischer iOS-Stolperstein).
- **Info.plist:** `UIBackgroundModes` mit `remote-notification` ergänzen (`ios/Runner/Info.plist`, heute nicht vorhanden).
- **AppDelegate:** `ios/Runner/AppDelegate.swift` ist minimal. Mit aktiviertem Firebase-Method-Swizzling (Default) reicht das meist; falls Swizzling deaktiviert wird, muss der APNs-Token manuell an `Messaging.messaging().apnsToken` gebrückt werden. Firebase wird über `firebase_options.dart` initialisiert — eine `GoogleService-Info.plist` ist nicht zwingend, das Verhalten der Apple-SDK-/APNs-Brücke ist aber zu verifizieren.

**Android** (`google-services`-Plugin + `google-services.json` für `com.app.timework` sind bereits vorhanden; `minSdk = flutter.minSdkVersion` — effektiven Wert vor Implementierung prüfen):
- **Manifest (`android/app/src/main/AndroidManifest.xml`):** `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>` ergänzen (Android 13+). Zusätzlich `meta-data` für `com.google.firebase.messaging.default_notification_channel_id`, `default_notification_icon` und `default_notification_color` setzen.
- **Notification-Icon:** Ein **monochromes** Drawable als Notification-Icon bereitstellen — das farbige App-Launcher-Icon erscheint sonst als weißer Block (Android-Stolperstein).
- **Channel-Anlage:** Den Default-Channel zur Laufzeit via `flutter_local_notifications` (`AndroidNotificationChannel`) erzeugen, sonst landen Foreground-Data-Messages ohne sichtbaren Channel. Die Channel-ID muss mit der `default_notification_channel_id`-Meta übereinstimmen.

**Web** (heute kein FCM-Setup, Stolperstein SW-Koexistenz):
- **`web/firebase-messaging-sw.js` neu anlegen** (statische Datei, wird von `flutter build web` unverändert nach `build/web/` kopiert). Inhalt: `importScripts(...)` für `firebase-app-compat` + `firebase-messaging-compat` von gstatic, `firebase.initializeApp(...)` mit der Web-Config, `onBackgroundMessage`-Handler.
- **SW-Koexistenz:** Der Flutter-Bootstrap registriert seinen eigenen (heute selbst-deregistrierenden Stub-)Service-Worker. Der FCM-SW läuft **separat** unter `/firebase-messaging-sw.js` an der Origin-Root — beide koexistieren (verschiedene Dateinamen/Scripts), Firebase registriert seinen SW selbst. Background-/Closed-Tab-Pushes rendert ausschließlich dieser SW (`onBackgroundMessage`); Foreground-Pushes laufen über Dart `onMessage`.
- **VAPID-Key:** Web-Push-Zertifikat in der Firebase-Console erzeugen und als `APP_WEB_PUSH_VAPID_KEY` (dart-define) an `getToken(vapidKey:)` übergeben — ist nicht in `firebase_options.dart`.
- **Config-im-SW-Problem (Entscheidung nötig):** Der SW kann die `--dart-define FIREBASE_WEB_*`-Creds **nicht** lesen. Die Web-Firebase-Config muss im SW entweder hartcodiert oder per Build-Step/Query-Param injiziert werden — das widerspricht dem „keine committete Config"-Prinzip aus CLAUDE.md und braucht eine bewusste Entscheidung (z.B. Build-Step, der `web/firebase-messaging-sw.js` aus den dart-defines generiert).
- **Hosting-Header:** `firebase.json` setzt `no-store, no-cache` auf `**`. Für `/firebase-messaging-sw.js` ist `no-cache` für reines Push (ohne Offline-Caching) unkritisch und für SW-Updates sogar gewünscht — die `no-store`-Politik muss aber bewusst beibehalten/geprüft werden. CSP in `web/index.html` (Z.30-39) vor dem Go-Live gegen einen echten Token-Flow smoke-testen (FCM-Endpunkte laufen über `*.googleapis.com`, das gstatic-SDK-Script über `script-src` — bei weißem Screen/blockiertem `connect-src` nachschärfen).
- iOS-Safari Web-Push setzt eine **installierte PWA** ab iOS 16.4 voraus (`manifest.json` mit `display: standalone` ist vorhanden) — Browser-Tab-Push auf iOS-Safari ist nicht zustellbar.

### 7. In-App-Notification-Center-Parität

Das heutige „Anfragen"-Center (`lib/screens/notification_screen.dart`, Tab `ShellTab.inbox` → `/anfragen`) ist vollständig **derived**: es rekonstruiert bei jedem `build()` ephemere `_InboxItem`-Objekte aus den Live-Daten von `ScheduleProvider`/`InventoryProvider`/`AuthProvider`. Es gibt **kein** persistentes Notification-Model und **keinen** gelesen/ungelesen-Status pro Ereignis; das Badge (`pendingInboxActionCount`) ist eine reine Live-Ableitung offener Vorgänge.

Für Push-Parität (Push-Tap landet in einer nachvollziehbaren In-App-Historie, Markieren-als-gelesen, Badge-Sync) dockt der **`NotificationProvider`** als persistente Spiegel-Schicht an:

- Jeder gesendete Push erzeugt serverseitig ein Notification-Dokument (Datenmodell separat) mit `readAt`/`seenAt` pro Empfänger. Der `NotificationProvider` streamt diese org-/user-skopiert (Cloud/Hybrid) bzw. bleibt im local-Modus leer.
- `notification_screen.dart` bekommt eine zusätzliche Quelle: neben den weiterhin derived Inbox-Items (Abwesenheiten, Tausch, Kundenbestellungen, Meldebestand) blendet es die persistierten Push-Ereignisse als eigene Items ein — bevorzugt in eine vierte Logik der bestehenden Sektions-/Filter-Struktur (`_InboxSection.todo/inProgress/history`) integriert, damit die UI-Konvention erhalten bleibt.
- **Badge-Angleichung (Entscheidung):** Heute zählt `pendingInboxActionCount` (`schedule_provider.dart` Z.263) nur Abwesenheiten + Tausch, nicht Inventar/Kundenbestellungen. Wenn Push diese abdeckt, divergiert die Push-Menge vom heutigen Badge. Empfehlung: einen **ungelesen-Zähler aus dem `NotificationProvider`** als zweite Quelle in das Tab-Badge (`home_screen.dart` `_badgedNavIcon`, Z.981) einrechnen, statt die enge `pendingInboxActionCount`-Logik aufzubohren — so bleibt In-App-Badge und Push-Inbox konsistent.
- **Markieren-als-gelesen:** Beim Öffnen des Anfragen-Tabs bzw. eines Items setzt der `NotificationProvider` `readAt` (best-effort, Drei-Speichermodi). Foreground-`onMessage` legt sofort ein ungelesenes Item an, sodass App-Badge und Systembenachrichtigung synchron bleiben.

**Bewusste Asymmetrie:** Kundenwünsche (`/wunsch`) und Feedback (`/feedback-eingang`) sind heute keine Inbox-Ereignisse. Wenn Push diese (rollen-gegated: Wünsche an alle, Feedback nur Manager) abdeckt, ist Push breiter als die heutige In-App-Inbox — diese Erweiterung sollte dann konsequent auch als persistierte Notification-Items im Center erscheinen, damit Push und In-App-Historie nicht auseinanderlaufen.

---

## 4. Professionelle Darstellung, UX & Nutzereinstellungen

> Zielsatz des Betreibers: **„Die Anzeige auf dem Handy soll professionell sein."** Dieser Abschnitt definiert verbindlich, *wie* eine WorkTime-Push-Benachrichtigung im Android-/iOS-Benachrichtigungsbereich aussieht, klingt und sich verhält — und welche Einstellungen der Mitarbeiter dazu bekommt. Die Empfänger-, Trigger- und Token-Mechanik ist in den anderen Abschnitten beschrieben und wird hier nicht wiederholt.
>
> **Markenanker (verifiziert):** Leitfarbe ist **Signal-Teal** `#0E7C7B` (hell, `app_theme.dart:865/873`) bzw. `#5FD4CE` (dunkel). Status-/Akzentfarben kommen aus der ThemeExtension `AppThemeColors` (`lib/theme/theme_extensions.dart`): `success #187A58`, `warning #A76E00`, `info #2D6CDF` (+ `*Container`-Töne). Diese Farben — niemals Hardcodes — gelten auch für die Notification-Akzente.

### 1. Anatomie einer professionellen Benachrichtigung

Eine Push-Benachrichtigung wirkt professionell, wenn sie in **unter einer Sekunde lesbar** ist und sofort klarmacht, *was passiert ist* und *was zu tun ist*. Verbindliche Anatomie:

| Element | Vorgabe |
|---|---|
| **Kleines Status-Icon** (Android Statusleiste / iOS-Pille) | **Monochrom, transparenter Hintergrund, nur Alpha** (Silhouette des WorkTime-Emblems). Ein farbiges Vollbild-Icon erscheint auf Android als **weißer Block** — das wirkt amateurhaft. Neues Drawable `ic_stat_worktime` (24dp, weiß auf transparent), abgeleitet aus `assets/icon/app_icon_foreground.svg`. |
| **Markenfarbe (Akzent)** | Android: `setColor(Signal-Teal)` färbt Icon-Tint + App-Name-Zeile. iOS tönt nicht — dort trägt das **App-Icon** (Emblem, bereits Launcher-Icon) die Marke. |
| **App-Name-Zeile** | Android zeigt automatisch „timework" (= `MaterialApp.title`). Nicht in den Titel duplizieren. |
| **Titel (deutsch, prägnant)** | Max. ~5–6 Wörter, Substantiv-getrieben, **nennt die Domäne**: „Neuer Kundenwunsch", „Kühlschrank nachfüllen", „Schichtplan veröffentlicht". |
| **Body (handlungsorientiert)** | 1–2 kurze Sätze: *konkretes Objekt + erwartete Handlung*. „Für **Tabak Börse**: 3 Artikel nachfüllen." |
| **BigText / BigPicture (optional)** | Aufgeklappt: bei mehreren Positionen `BigTextStyle` mit Aufzählung; bei Kundenwunsch optional `BigPictureStyle` nur, wenn ein Foto vorliegt (sonst weglassen — leeres Bild wirkt kaputt). |
| **Zeitstempel** | Vom System gesetzt (Eingangszeit). Keine Zeit in den Body schreiben — das System formatiert lokalisiert. |
| **Deep-Link-Ziel** | Tap öffnet via go_router die zuständige Inbox-Sektion bzw. den Fachbereich (siehe Abschnitt 4 + Routing-Abschnitt). |

```
ANDROID — eingeklappt (Sperrbildschirm / Statusleiste)
┌────────────────────────────────────────────────┐
│ ▟ timework · jetzt                              │  ← ▟ = monochromes Teal-getöntes Status-Icon
│ Kühlschrank nachfüllen                          │  ← Titel (fett)
│ Tabak Börse: 3 Artikel zum Nachfüllen.          │  ← Body
│            [ ANSEHEN ]      [ ERLEDIGT ]        │  ← Aktions-Buttons
└────────────────────────────────────────────────┘

ANDROID — aufgeklappt (BigTextStyle)
┌────────────────────────────────────────────────┐
│ ▟ timework · vor 2 Min.                         │
│ Kühlschrank nachfüllen                          │
│ Tabak Börse – aus dem Lager nachfüllen:         │
│  • Cola 0,33 l  ×6                              │
│  • Mineralwasser  ×4                            │
│  • Energy-Drink  ×3                             │
│            [ ANSEHEN ]      [ ERLEDIGT ]        │
└────────────────────────────────────────────────┘
```

```
iOS — Sperrbildschirm
┌────────────────────────────────────────────────┐
│  [▢]  TIMEWORK                          jetzt   │  ← [▢] App-Icon (Emblem), App-Name groß
│  Neuer Kundenwunsch                             │  ← Titel
│  Strichmännchen: „Sammelfigur Edition 7"        │  ← Body
└────────────────────────────────────────────────┘
   (3D-Touch / lang drücken → Aktionen: Ansehen)
```

### 2. Kanäle (Android Notification Channels) & iOS Interruption Levels

Android erzwingt ab API 26 **Channels**; sie sind die Stellschraube für Wichtigkeit, Ton und Vibration und vom Nutzer pro Kanal in den Systemeinstellungen feinjustierbar. WorkTime definiert genau **fünf** fachliche Kanäle, deckungsgleich mit den Push-Kategorien und mit den Kategorie-Schaltern im App-Einstellungs-Screen (Abschnitt 7). Channels werden beim ersten Start nach Login einmalig via `flutter_local_notifications` erzeugt (Channel-Pflicht gilt ab API 26 unabhängig vom konkreten `minSdk`).

| Kanal-ID | Anzeigename (deutsch) | Android Importance | Ton / Vibration | iOS Interruption Level | Begründung |
|---|---|---|---|---|---|
| `genehmigungen` | „Genehmigungen" | **HIGH** (Heads-up) | Ton + Vibration | **time-sensitive** | Abwesenheits-/Tausch-Genehmigung blockiert Dienstplanung → darf Fokus durchbrechen. |
| `schichtplan` | „Schichtplan" | **HIGH** | Ton + Vibration | **active** (Standard) | „Plan veröffentlicht / Schicht geändert" ist relevant, aber nicht stör-dringlich. |
| `aufgaben` | „Aufgaben & Kühlschrank" | **DEFAULT** | leiser Ton, keine Vibration | **active** | Operative To-dos, häufig → bewusst gedämpft, keine Heads-ups. |
| `kundenwuensche` | „Kundenwünsche" | **DEFAULT** | leiser Ton | **active** | Tagesgeschäft; sammelt sich, kein Alarm. |
| `bestand` | „Bestand & Nachbestellung" | **LOW** | stumm | **passive** | Meldebestand ist Hintergrundinfo für Bestellberechtigte → **passive**: erscheint im Center, ohne zu unterbrechen. |

Hinweise:
- **Channel-Importance ist nach Erstanlage nicht mehr per Code änderbar** (Android-Regel). Stufen daher von Anfang an konservativ wählen; spätere Änderung nur durch neue Channel-ID (= „v2"-Migration).
- iOS-Stufen werden pro Versand-Payload gesetzt (`interruption-level`), nicht global. **`time-sensitive`** erfordert das Entitlement *Time Sensitive Notifications* — nur für `genehmigungen` beantragen, nicht pauschal (sonst App-Review-Beanstandung).
- **`critical`/kritische Alarme werden NICHT verwendet** — WorkTime hat keine sicherheitskritischen Ereignisse; das wäre unangemessen und review-gefährdet.

### 3. Gruppierung & Bündelung gegen Spam

Operative Ereignisse (Kühlschrank, Bestand) sind hochfrequent — laut Architektur-Memo sind Kühlschrankliste/Bestellkorb bewusst *nicht* einmal auditiert (Rauschen). Push muss das gleiche Maß an Zurückhaltung zeigen, sonst stumpfen Mitarbeiter ab und schalten alles aus.

- **Android Group + Summary:** Pro Kanal eine `setGroup('<kanalId>')` + eine **Summary-Notification** mit `InboxStyle`. Mehrere Einzel-Pushes desselben Kanals kollabieren unter eine Sammelzeile.
- **iOS `threadIdentifier`:** identisch zur Kanal-ID — iOS stapelt Benachrichtigungen mit gleichem Thread automatisch.
- **Server-seitige Entprellung (Coalescing):** Für Kühlschrank/Bestand werden Einzeländerungen **serverseitig gebündelt** (z. B. ein Push pro Standort/Liste statt pro Position; siehe Trigger-Abschnitt zu Dedup/`notifiedAt`). Eine Mengenänderung an einem Artikel löst **keinen** eigenen Push aus.
- **Collapse-Key / `tag`:** Folge-Pushes zum selben Vorgang (z. B. derselbe Kühlschrank-Standort) tragen denselben `tag` (Android) bzw. `apns-collapse-id` (iOS) → die neue ersetzt die alte, statt zu stapeln. Bei genau einer offenen „Kühlschrank nachfüllen"-Karte je Standort.

```
ANDROID — Summary (mehrere Aufgaben gebündelt)
┌────────────────────────────────────────────────┐
│ ▟ timework · Aufgaben & Kühlschrank             │
│ 3 offene Aufgaben                               │
│ • Kühlschrank nachfüllen – Tabak Börse          │
│ • Kühlschrank nachfüllen – Strichmännchen       │
│ • 2 Kundenwünsche vorbereiten                   │
└────────────────────────────────────────────────┘
```

### 4. Aktions-Buttons direkt in der Benachrichtigung

Direkt-Aktionen machen die Benachrichtigung professionell und sparen dem Mitarbeiter das Öffnen der App. Pro Kategorie maximal **zwei** Buttons (mehr passt nicht in die eingeklappte Ansicht).

| Kategorie | Button(s) | Verarbeitung |
|---|---|---|
| Kühlschrank/Aufgabe | **Erledigt** · **Ansehen** | „Erledigt" → Hintergrund-Aktion ruft den vorhandenen Mutator `setFridgeRefillItemDone` / `markCustomerOrderPrepared` (`inventory_provider.dart`). „Ansehen" → Deep-Link in die Inbox-Sektion „Zu erledigen". |
| Kundenwunsch | **Ansehen** | Deep-Link in den Fachbereich; kein Direkt-Abschluss (Wunsch braucht Bearbeitung). |
| Genehmigung (Abwesenheit/Tausch) | **Genehmigen** · **Ablehnen** | Ruft `reviewAbsenceRequest` / `confirmShiftSwapRequest` / `rejectShiftSwapRequest` (`schedule_provider.dart`). **ABER:** Schichttausch erfordert eine Compliance-Vorschau (`previewSwapCompliance`) + ggf. Override-Dialog — eine blinde Hintergrund-Genehmigung würde diese Prüfung umgehen. Daher: **„Genehmigen" aus der Notification öffnet die App im Bestätigungs-Sheet** (deep-link, nicht silent), „Ablehnen" darf still im Hintergrund laufen. |
| Schichtplan/Bestand | (keine Aktion, nur Tap) | Rein informativ → Tap = Deep-Link. |

**Verarbeitungsmechanik:** Buttons werden bei der Channel-/Notification-Erstellung als `AndroidNotificationAction` / iOS `UNNotificationAction` (Kategorien-`identifier` = Kanal-ID) registriert. Taps landen im **Background-Handler** von `firebase_messaging` bzw. im `flutter_local_notifications`-Response-Callback. Da Hintergrund-Aktionen **ohne UI-Kontext** laufen, gelten die Storage-Modi-Regeln: im `APP_DISABLE_AUTH`/local-only-Modus existiert kein Cloud-Pfad → silent actions sind dort no-op (Push ist ohnehin cloud-gebunden). Jede stille Erfolgsaktion folgt dem etablierten `_audit?.call(...)`-Muster auf dem Erfolgspfad.

```
ANDROID — Genehmigung mit zwei Aktionen
┌────────────────────────────────────────────────┐
│ ▟ timework · Genehmigungen · vor 5 Min.         │
│ Urlaubsantrag prüfen                            │
│ Maria M. – 12.07. bis 19.07. (6 Werktage)       │
│        [ ABLEHNEN ]      [ GENEHMIGEN ]         │  ← „Genehmigen" öffnet Bestätigungs-Sheet
└────────────────────────────────────────────────┘
```

### 5. Deutsche Copy-Richtlinien

**Tonalität:** sachlich, freundlich-knapp, **Sie-Form vermeiden zugunsten neutraler Substantivierung** (passt zur bestehenden Audit-Summary-Sprache, die als Vorlage dient). Keine Ausrufezeichen, keine Emojis im Titel, keine Werbesprache.

Regeln:
1. **Titel = Was**, **Body = Welches Objekt + erwartete Handlung.**
2. **Maximal-Längen einhalten:** Titel ≤ ~40 Zeichen, Body ≤ ~120 Zeichen (sonst auf Sperrbildschirm abgeschnitten).
3. **Keine Secrets/PII über das Nötige hinaus.** Kundennamen aus öffentlichen Wünschen/Beschwerden **nicht** in den Lock-Screen-Body — Beschwerden sind sensibel (manager-only). Mitarbeiter-Nachnamen abkürzen, wenn die Notification auf einem geteilten Gerät landen kann.
4. **Konkrete Zahl statt Vagheit:** „3 Artikel" statt „mehrere Artikel".
5. **Standort nennen** (zwei Läden: Strichmännchen, Tabak Börse) — sonst weiß der Mitarbeiter nicht, wo.

| | Kundenwunsch | Kühlschrank |
|---|---|---|
| **Gut** | T: „Neuer Kundenwunsch" · B: „Strichmännchen: 1 Wunsch wartet auf Bearbeitung." | T: „Kühlschrank nachfüllen" · B: „Tabak Börse: 3 Artikel zum Nachfüllen." |
| **Gut (gebündelt)** | T: „2 neue Kundenwünsche" · B: „In beiden Läden warten Wünsche." | T: „Kühlschrank-Liste aktualisiert" · B: „Strichmännchen: jetzt 5 Positionen offen." |
| **Schlecht** | „Hey! 🎉 Es gibt was Neues!!!" *(reißerisch, keine Info)* | „Update" *(nichtssagend)* |
| **Schlecht (PII)** | „Anna Schmidt (anna@gmail.com) wünscht sich…" *(personenbezogene Daten aus anonymem öffentlichem Formular auf dem Lock-Screen)* | „currentStock < minStock für product_x7f3" *(technisch, Code-Leak)* |

**Single Source für Texte:** Push-Titel/Bodies werden **serverseitig** in den Sende-Functions formuliert (deutsche Literale, wie die bestehenden Audit-Summaries) — der anonyme öffentliche Client darf Empfängertexte nicht kennen, und nur der Server kennt die Empfängermenge.

### 6. Ruhezeiten, nicht-dringende Bündelung, Badge-Zähler

- **Ruhezeiten / Nicht-stören (App-seitig):** Pro Mitarbeiter ein Zeitfenster (Default **22:00–06:00**, anpassbar). In diesem Fenster werden **nicht-dringende** Kanäle (`aufgaben`, `kundenwuensche`, `bestand`, `schichtplan`) **serverseitig zurückgehalten und gebündelt am Fensterende** zugestellt; nur `genehmigungen` (time-sensitive) darf durch. Die Auswertung läuft serverseitig (der Sende-Function liegt die `notificationPrefs.quietHours` des Empfängers vor), damit kein Push das Gerät nachts überhaupt erreicht. Android-System-DND respektiert der Kanal-Importance ohnehin; die App-Ruhezeit ist die feinere, kategoriebewusste Schicht darüber.
- **Bündelung nicht-dringender Push:** Außerhalb von Ruhezeiten greift die Coalescing-Logik aus Abschnitt 3; in Ruhezeiten zusätzlich zeitliche Sammlung.
- **Badge-Zähler:** Das App-Icon-Badge (iOS Zahl, Android Punkt/Zahl) wird auf die **Anzahl offener, den Nutzer betreffender Vorgänge** gesetzt — server-berechnet je Push (`apns badge` / Android `setNumber`). **Wichtig für Parität:** Der heutige In-App-Badge (`ScheduleProvider.pendingInboxActionCount`) zählt nur Abwesenheiten + Tausch, *nicht* Inventar/Kundenbestellungen. Soll das System-Badge identisch zum App-Badge sein, muss entweder (a) die Push-Badge-Menge auf dieselbe enge Definition beschränkt oder (b) `pendingInboxActionCount` um Inventar erweitert werden. **Empfehlung:** App-Badge-Logik erweitern, damit System- und In-App-Badge nie divergieren (sonst wirkt die App fehlerhaft). Beim App-Öffnen wird das System-Badge auf den aktuell berechneten In-App-Wert zurückgesetzt.

### 7. Einstellungs-Screen „Benachrichtigungen"

Neuer Screen, eingehängt unter der bestehenden Einstellungs-Route **`/einstellungen`** (`shell_tab.dart:52`, `ShellTab` → `SettingsScreen`) als eigene Unterseite, erreichbar via `context.push`. Aufbau spiegelt das vorhandene Muster aus `settings_screen.dart` (`SwitchListTile`, `BreadcrumbAppBar`, Material 3), nutzt strikt `Theme.of(context).colorScheme` + `Theme.of(context).appColors` und deutsche Texte. Die fünf Kategorie-Schalter sind 1:1 die fünf Android-Kanäle / Push-Kategorien — so bleibt die App-Einstellung und die System-Channel-Einstellung mental deckungsgleich.

```
EINSTELLUNGS-SCREEN „Benachrichtigungen"
┌──────────────────────────────────────────────────────┐
│  ‹ Einstellungen › Benachrichtigungen                 │
├──────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────┐  │
│  │  Push-Benachrichtigungen           [●——○ AN ]   │  │ ← Master-Schalter (Teal)
│  │  Mitteilungen auf dieses Gerät senden.          │  │
│  └────────────────────────────────────────────────┘  │
│                                                        │
│  KATEGORIEN                                            │
│  ┌────────────────────────────────────────────────┐  │
│  │  Genehmigungen                     [●——○ AN ]   │  │
│  │  Abwesenheits- und Tauschanträge.   (wichtig)   │  │
│  │  Schichtplan                       [●——○ AN ]   │  │
│  │  Aufgaben & Kühlschrank            [●——○ AN ]   │  │
│  │  Kundenwünsche                     [●——○ AN ]   │  │
│  │  Bestand & Nachbestellung          [○——● AUS]   │  │
│  └────────────────────────────────────────────────┘  │
│                                                        │
│  RUHEZEITEN                                            │
│  ┌────────────────────────────────────────────────┐  │
│  │  Nicht stören                      [●——○ AN ]   │  │
│  │  Von  22:00     Bis  06:00                       │  │
│  │  Nur „Genehmigungen" kommen während dieser Zeit. │  │
│  └────────────────────────────────────────────────┘  │
│                                                        │
│  [ Systemeinstellungen für Mitteilungen öffnen → ]    │ ← öffnet Android-/iOS-Settings
└──────────────────────────────────────────────────────┘
```

Verhalten:
- **Master-Schalter aus** → alle Kategorie-Schalter ausgegraut/disabled. Beim Einschalten wird (falls noch nicht geschehen) der **System-Permission-Flow** ausgelöst (Android 13+ `POST_NOTIFICATIONS`, iOS `requestPermission`). **Nicht beim Cold-Start fragen** — erst bei bewusster Aktivierung (vermeidet Reflex-Ablehnung).
- Verweigert das System die Berechtigung → Inline-Hinweis (`appColors.warning`) „In den Systemeinstellungen aktivieren" mit Button.
- **Rollenabhängige Sichtbarkeit:** „Genehmigungen" und „Bestand & Nachbestellung" nur für Manager/Bestellberechtigte sichtbar (`canManageShifts` / `canManageInventory`) — spiegelt die Empfänger-Logik, damit niemand eine Kategorie sieht, die er nie bekäme.
- **Persistenz:** Präferenzen liegen als `notificationPrefs`-Feldobjekt am `users/{uid}`-Doc (vgl. `permissions`/`workRuleSettings`-Muster, Zwei-Serialisierungs-Regel, Kopplung #1) — der Sende-Server liest sie zur Versandentscheidung. Defaults je Rolle analog `UserPermissions.defaultsForRole`.
- **Parität zum In-App-Center:** Jede Push-Kategorie hat ein Gegenstück im bestehenden Anfragen-Center (`/anfragen`). Der Screen weist explizit darauf hin („Alle Vorgänge finden Sie auch unter *Anfragen*.") — Push ist Auslöser, das Center die vollständige Historie. Wo Push breiter ist als das heutige Center (Kundenwünsche, Feedback erscheinen heute *nicht* in `/anfragen`), ist das eine bewusste, im Plan dokumentierte Asymmetrie.

### 8. Barrierefreiheit

- **Kein Sinn allein über Farbe:** Status (kritisch/erledigt) immer zusätzlich über **Text + Icon** transportieren — der Teal-Akzent ist nur Verstärker. `success/warning/info` aus `AppThemeColors` sind kontrastgeprüft, aber im Notification-Text nie der einzige Träger der Bedeutung.
- **Screenreader (TalkBack/VoiceOver):** Titel + Body sind echter Text und werden vorgelesen; Aktions-Buttons tragen **klare deutsche Labels** („Genehmigen", nicht „OK"). Im Einstellungs-Screen erhalten alle `SwitchListTile` ein `subtitle`, das den Zweck erklärt (wird mitgelesen), und die Schalter haben ausreichend große Touch-Ziele (`MaterialTapTargetSize.padded` ist Theme-Default).
- **Kontrast:** Monochromes Status-Icon ist reines Weiß-auf-Transparent (maximaler Kontrast in der Statusleiste). Body-Text nutzt System-Notification-Styling → respektiert die System-Schriftgröße/Dynamic Type automatisch; keine festen `fontSize`-Pixel in Notification-Texten.
- **Dynamic Type / große Schrift:** BigText-Stil bevorzugen, damit langer Body bei großer Systemschrift nicht abgeschnitten, sondern umgebrochen wird.
- **Reduzierte Reizbelastung:** Mitarbeiter mit Reizempfindlichkeit profitieren direkt von den konservativen Kanal-Importances (Bestand stumm/passive) und den Ruhezeiten — die Defaults sind bewusst zurückhaltend.

---

## 5. Umsetzungsplan, Sicherheit, Tests & Rollout

Dieser Abschnitt legt die Reihenfolge der Umsetzung, die kritischen Repo-Kopplungen, Sicherheits-/Datenschutz-Vorgaben, die Teststrategie, Observability, die Deployment-Schritte und die offenen Entscheidungen fest. Jeder Meilenstein ist so geschnitten, dass er für sich deploybar ist und einen Wert liefert; Datenmodell, Empfänger-Routing und Darstellung sind in den vorigen Abschnitten beschrieben und werden hier nicht wiederholt.

### Meilenstein-Roadmap (M1–M7)

Grundprinzip: **Push wird ausschließlich serverseitig getriggert** (Cloud Functions, Admin SDK Messaging), nie vom Client direkt. Der Client registriert nur Geräte-Tokens und stellt Foreground-Nachrichten dar. Jeder Meilenstein bleibt im `APP_DISABLE_AUTH`-/local-only-Modus ein No-op (Firebase nicht initialisiert).

**M1 — Token-Infrastruktur + Rules + Flag (Fundament, kein sichtbarer Push) · Status: umgesetzt (Code), offen: Emulator-Rules-Test + Geräte-Test + Deploy**
> Abweichung: `flutter_local_notifications` bewusst auf **M4** verschoben (erst dort Foreground-Anzeige/Channels nötig) — M1 fügt nur `firebase_messaging` hinzu. Doc-ID = SharedPreferences-UUID (`fcm_install_id`) statt `firebase_app_installations` (keine Extra-Abhängigkeit).
- `firebase_messaging` (kompatibel zu `firebase_core ^3` / `cloud_functions ^5`; gegen `mobile_scanner ^7`-Pod-Constraints prüfen) und `flutter_local_notifications` in `pubspec.yaml` ergänzen.
- `AppConfig.pushEnabled` als `bool.fromEnvironment('APP_PUSH_ENABLED', defaultValue: false)` nach Vorlage `oktoposEnabled` (`lib/core/app_config.dart`), Kommentar „kein Secret, nur Sichtbarkeits-/Aktivierungs-Schalter"; Eintrag im dart-define-Inventar in `CLAUDE.md`.
- FCM-Init **im Firebase-konfiguriert-Block** von `_AppBootstrapState._initializeApp` (`lib/main.dart`, nach `FirebaseFirestore.instance.settings` Z.173), gegated per `AppConfig.pushEnabled` **und** `DefaultFirebaseOptions.isConfigured` (nicht nur `firebaseConfigured`), im `catch` fail-open analog App Check. Permission-Request **nicht** beim Cold-Start.
- Plattform-sicherer `PushService` nach Vorlage `QuickActionsService` (`_isSupported = !kIsWeb && (Android||iOS)`, No-op sonst), Token holen/`onTokenRefresh`/Logout-Cleanup.
- Token-Ablage: Subcollection `users/{uid}/fcmTokens/{tokenId}` (tokenId = Hash/Installations-ID, Token als Feld), Felder `token, platform, orgId, appVersion, updatedAt`. Eigener `match`-Block in `firestore.rules` (Subcollection erbt die `users/{uid}`-Doc-Rule NICHT): `read/write` nur `isSelf(uid)` + Feld-Allowlist `hasOnly([...])` nach Muster `stockMovements`/`priceHistory`; Functions lesen via Admin SDK ungated.
- **DoD:** Auf realem Android- und iOS-Gerät wird beim Login ein Token-Doc geschrieben/aktualisiert, beim Logout entfernt; `flutter analyze` + `flutter test` grün; Demo-/Offline-Modus startet unverändert ohne FCM-Zugriff.

**M2 — Zentrale Sende-Function + ein Ereignis (Kundenwunsch) end-to-end · Status: umgesetzt (Code + Tests), offen: Functions-Emulator-E2E + Geräte-Test + Deploy**
- Neuer `onDocumentCreated`-Trigger auf `organizations/{orgId}/customerWishes/{wishId}` in `functions/index.js` (erster Firestore-Trigger des Projekts; `firebase-functions/v2/firestore` importieren), `{region: REGION}`.
- Wrapper analog `callable()` für Trigger: eigene `crypto.randomUUID()`-requestId, strukturiertes `start/done/error`-Logging (kein Client-`_request_id` vorhanden).
- Empfänger-Auflösung serverseitig: Kundenwunsch → alle aktiven Mitarbeiter der Org (`users.where('orgId','==',orgId)` + `isActive==true`), Token-Sammlung, `admin.messaging().sendEachForMulticast()`; Stale-Token-Pruning bei `messaging/registration-token-not-registered`.
- Dedupe: deterministisches `notifications/{notificationId}`-Doc per `batch.create` (wie OktoPOS `movementId`) oder `notifiedAt`-Sentinel, damit at-least-once/Doppel-Feuerung keinen Doppel-Push erzeugt.
- Deutsche Payload (Titel/Body), Deep-Link-Route in die Inbox; **keine PII** im Payload (nur IDs/generische Texte).
- **DoD:** Ein über `/wunsch` eingereichter Kundenwunsch erzeugt auf einem registrierten Gerät eine sichtbare, professionell formatierte Push; erneutes Feuern desselben Events sendet nicht doppelt; Function-Unit-Test (Empfänger + Dedupe) grün.

**M3 — Weitere Ereignisse + Routing-Matrix · Status: umgesetzt (Code + Tests), offen: Functions-Emulator-E2E + Deploy**
- Trigger für die übrigen serverseitig erfassbaren Events (cloud-/hybrid-online-Pfad): `customerFeedback` (nur Manager/Admin, `canManageFeedback`), `absenceRequests` (eingereicht→Manager; genehmigt/abgelehnt→Antragsteller; bei sickness/childSick zusätzlich Schicht-Freigabe an Team), `shiftSwapRequests` (phasenabhängig `targetUid`/`requesterUid`/Manager), `shifts` veröffentlicht (`status→confirmed`, betroffene `userId`), Meldebestand (Flankenerkennung `currentStock<=minStock`, gebündelt, an `canManageInventory` des Standorts).
- Empfänger-Auflösungs-Helfer, der die Client-Sichtbarkeits-/Rollenlogik exakt spiegelt: `canManageShifts == isAdmin || canEditSchedule`, Rollen-Default via `permissionDefaultsForRole`, `normalizeRole` (`teamleiter→teamlead`), Team via `TeamDefinition.memberIds`, Standort via `employeeSiteAssignments.where(siteId)`, immer `isActive==true` + `orgId`-Filter.
- Entprellung gekoppelter Events (Krankmeldung→Schichtfreigabe; Tausch-Confirm→Umbuchung+Gutschrift): pro Vorgang definierte Anzahl Pushes, kein Widerspruch.
- **DoD:** Für jedes Event ist in einer dokumentierten Routing-Matrix (Event → Empfängergruppe → Trigger → Push-Text) festgehalten und durch Function-Unit-Tests gegen die Empfänger-Auflösung abgedeckt; hochfrequente Quellen (Kühlschrankliste, Bestandsbewegungen) lösen bewusst **keinen** Per-Item-Push aus.

**M4 — Professionelle Darstellung, Channels, Actions, Deep-Links · Status: umgesetzt (Code + Tests; Aktions-Buttons + Marken-Icon + Geräte-Abnahme offen)**
- Android-Notification-Channels (z.B. „Schichten", „Anfragen", „Kunden", „Bestand") via `flutter_local_notifications`; monochromes Notification-Icon (drawable), `default_notification_channel_id`/`-icon`/`-color`-Meta im `AndroidManifest.xml`; `POST_NOTIFICATIONS`-Permission + Runtime-Request-UX (Android 13+).
- iOS: Foreground-Darstellung via `flutter_local_notifications` (sonst keine sichtbare Foreground-Notification), Gruppierung/Thread-IDs für saubere Bündelung.
- Notification-Tap → go_router-Deep-Link in die passende Inbox-Section (`/anfragen` ist bereits im Deep-Link-Permission-Gating freigegeben); Foreground-`onMessage` in eine app-weite Senke (neuer `scaffoldMessengerKey` oder Push-Provider) statt verloren zu gehen.
- **DoD:** Pushes erscheinen mit korrektem Channel, App-Icon/Marken-Farbe und deutschem, knappem Text; Tap öffnet zielgenau die richtige Stelle (cold start + warm); Darstellung auf Android und iOS visuell abgenommen.

**M5 — Einstellungen, Präferenzen, Ruhezeiten · Status: umgesetzt (Code + Tests), offen: Geräte-Test + Deploy**
- `notificationPrefs`-Feld-Objekt am `AppUserProfile` (nach Muster `permissions`/`workRuleSettings`), mit Flags je Domäne (z.B. `customerWish`, `shiftPublished`, `shiftSwap`, `absenceDecision`, `lowStock`) und `quietHours` (von/bis). Default-Werte je Rolle wie `UserPermissions.defaultsForRole`.
- Einstellungs-UI (deutsch), Self-Update bleibt durch die strenge `users/{uid}`-Self-Update-Rule erlaubt (`notificationPrefs` ist nicht Teil der equivalence-Prüfung); beim späteren Hinzufügen einer `hasOnly`-Allowlist daran denken.
- Sende-Function filtert Empfänger zusätzlich nach Präferenz/Ruhezeit (ggf. neuer Composite-Index `orgId + notificationPrefs.<flag>`).
- **DoD:** Mitarbeiter kann Push-Kategorien abschalten und Ruhezeiten setzen; abgeschaltete Kategorien/Ruhezeiten werden serverseitig respektiert; Round-Trip beider Serialisierungsformate getestet.

**M6 — Web-Push (optional / Stretch) · Status: umgesetzt (Code/Artefakte), offen: SW-Config + Browser-Test**
- `firebase-messaging-sw.js` im Origin-Root (`web/`), `getToken(vapidKey:)` mit VAPID-Key als dart-define/Config; Caching-Header in `firebase.json` für den SW lockern (heute global `no-store, no-cache` — kollidiert mit SW-Update/Caching); CSP in `web/index.html` gegen echten FCM-Token-Flow smoke-testen.
- **Entscheidung Web-Config im SW:** Der SW kann die `FIREBASE_WEB_*`-dart-defines nicht lesen — widerspricht dem „keine committete Config"-Prinzip; Injektion per Build-Step oder bewusste Ausnahme.
- iOS-Safari nur als installierte PWA (display:standalone vorhanden).
- **DoD:** Im unterstützten Browser kommt eine Background- (über SW) und Foreground-Push an; SW-Update funktioniert trotz Header-Anpassung; Web bleibt explizit Stretch und blockiert M1–M5 nicht.

**M7 — Härtung, Metriken, Skalierung · Status: umgesetzt (Code + Tests), offen: Functions-Emulator-E2E + Deploy**
- Token-GC-Job (verwaiste/abgelaufene Tokens), Idempotenz-/Dedupe-Review unter Last (Batch-Writes bis 50 auf shifts/workEntries → Trigger-Invocation-Volumen), Bündelung/Entprellung bei Batch-Publish.
- Strukturierte Metriken (Zustellrate, Opt-in-Rate, Fehlercodes), Alarm auf erhöhte `registration-token-not-registered`-Rate.
- **DoD:** Lasttest mit Wochenplan-Veröffentlichung erzeugt keine Push-Flut/Doppel-Pushes; Metriken sichtbar; keine Secrets/PII in Logs.

### Kritische Kopplungen ("Wenn du X änderst, ändere auch Y")

- **`FIREBASE_FUNCTIONS_REGION` (dart-define) ↔ `const REGION = "europe-west3"`** (`functions/index.js` Z.15): Jeder neue Trigger MUSS `{region: REGION}` setzen. (Firestore-Trigger-Pfad-Match ist regionsunabhängig, aber konsistent halten; FCM-Send ist global.)
- **Neues Token-/Callable-Modell ↔ Zwei-Serialisierungs-Regel:** Geht ein Token-Modell durch eine Callable, braucht es `toMap()`/`fromMap` (snake_case) **plus** snake_case-Parsing in `functions/index.js`; direkter Firestore-Write nutzt `toFirestoreMap()` (camelCase). `notificationPrefs`-Feld am `AppUserProfile` löst Kopplung #1 aus: `toFirestoreMap/fromFirestore/toMap/fromMap/copyWith` (+`clearX` wenn nullable).
- **Rules ↔ Functions Org-Isolation:** `sameOrg` in `firestore.rules` und die serverseitige Empfänger-Auflösung müssen synchron `orgId`-skopiert bleiben; ein Routing-Query darf **nie** org-übergreifend Tokens sammeln. Admin-SDK-Trigger umgehen Rules → Org-Check im Trigger-Code selbst (orgId aus dem Pfad).
- **Rollen-Mapping `teamleiter→teamlead`** muss an drei Stellen synchron bleiben (Dart `UserRoleX.fromValue`, Functions `normalizeRole`, Rules `normalizedRoleValue`) — die Empfänger-Function muss ebenfalls normalisieren, sonst werden Altdaten verfehlt.
- **Neuer Provider in `main.dart`-Kette (Kopplung #4):** Ein `NotificationProvider` (falls In-App-Speicher) wird als `ChangeNotifierProxyProvider` **nach** `AuthProvider`/`AuditProvider` eingehängt (AuditProvider ist FRÜH, Z.338); Cloud-Repo **lazy**, nie im Konstruktor (sonst rote Fehlerseite im `disableAuth`/Web-Modus).
- **Neue Collection / Subcollection (Kopplungen #5/#6):** `fcmTokens`-Subcollection braucht eigenen `match`-Block in `firestore.rules`; eine `collectionGroup('fcmTokens')`-Empfänger-Query braucht einen neuen Index mit `queryScope: COLLECTION_GROUP` in `firestore.indexes.json` (heute existieren ausschließlich `COLLECTION`-Indizes) + Deploy, sonst Laufzeitfehler. Falls lokal gespiegelt: Key in `DatabaseService` registrieren — empfohlen ist Token = **cloud-only** (PII, kein lokaler Spiegel nötig).
- **`AppConfig.pushEnabled` (neues Flag):** in `app_config.dart` ergänzen **und** im dart-define-Inventar in `CLAUDE.md` dokumentieren; FCM-Init zusätzlich gegen `DefaultFirebaseOptions.isConfigured` gaten.
- **Trigger an Firestore-onWrite, nicht an Callable:** Compliance-/Tausch-Override schreibt direkt (`saveShifts skipCompliance=true` → `saveShiftBatchDirect`, umgeht Callable). Ein Trigger an der Callable würde Override-Umbuchungen verpassen → Trigger an die Collection hängen, dafür dort dedupen (Callable + Direkt-Write erzeugen denselben logischen Zustand).

### Sicherheit & Datenschutz

- **Kein Client-Direktversand:** Pushes werden ausschließlich von Cloud Functions (Admin SDK) ausgelöst. Der Client darf keine Empfänger-/Token-Listen kennen (insb. anonyme öffentliche Schreibpfade `/wunsch`, `/feedback`).
- **Keine PII/Secrets im Payload:** Push-Bodies enthalten nur generische deutsche Texte und IDs für den Deep-Link; keine Namen sensibler Vorgänge (Beschwerdeinhalt, Lohn, Gesundheitsdaten). APNs-/FCM-Server-Keys nur in der Firebase-Console/Admin-SDK-Credentials, nie im Client/Firestore/dart-define (Muster wie `OKTOPOS_API_KEYS` im Secret Manager).
- **FCM-Token ist personenbezogen (DSGVO):** Token-Doc wird beim Logout und bei Account-Löschung/`isActive==false` entfernt; Stale-Token-Pruning nach Send-Fehler; Token-Lesen ist self-only (Manager dürfen fremde Tokens NICHT lesen — Versand läuft server-side).
- **App Check** bleibt auf dem Token-Schreibpfad/Callables aktiv (vorhandener `firebase_app_check`-Mechanismus); Org-Isolation serverseitig erzwingen (`assertSameOrg`-Äquivalent im Trigger, `orgId`-Filter in jeder Empfänger-Query).
- **Opt-out & Ruhezeiten** (M5) sind auch Akzeptanz-/DSGVO-relevant: Mitarbeiter müssen Kategorien abschalten können.

### Teststrategie

- **Function-Unit-Tests (neu aufzusetzen — `functions/` hat heute keine Test-Infrastruktur, kein `functions/test`, keine devDeps):** Test-Runner (z.B. Jest/Mocha) in `functions/package.json` ergänzen. Pure Helfer extrahieren und testen: Empfänger-Auflösung (Rolle/Permission/Team/Standort/`isActive`/`orgId`, `teamleiter`-Normalisierung), Dedupe (deterministische `notificationId`, kein Doppel-Push), Token-Pruning (Mapping `registration-token-not-registered` → Doc-Delete), Payload-Bau (kein PII). `admin.messaging()` mocken — keine echten Sends im Test.
- **Client-Tests:** weiterhin `FakeFirebaseFirestore`, **nie echtes Firebase**; `flutter_local_notifications` und `FirebaseMessaging` über Test-Doubles/Subklassen mocken (kein Mockito einführen). Token-Lifecycle (register/refresh/logout-cleanup) und Foreground-`onMessage`→Inbox-Senke testen; SharedPreferences-Mock + `initializeDateFormatting('de_DE')` in `setUp`. Gate-/Routing-Tests über `test/support/router_harness.dart` (`pumpApp`).
- **Manuelles Geräte-Testen:** reale Android- und iOS-Geräte (Foreground/Background/terminated), Cold-Start-Deep-Link, Permission-Ablehnung, Channel-Darstellung, Ruhezeiten.
- **FCM-Test über Firebase Console** (Cloud Messaging → Testnachricht an Token) zur Verifikation von APNs-Brücke/iOS-Zustellung, bevor Trigger live gehen.
- Quality Gates wie gehabt vor jedem Commit: `flutter analyze` + `flutter test`.

### Observability & Metriken

- **Strukturierte Cloud-Logs** im bestehenden Stil (requestId via `crypto.randomUUID()` je Trigger-Event, `start/done/error`, `durationMs`), **niemals** Token/Secrets/PII loggen (E-Mail ggf. maskiert) — entsprechend dem `flutter-logging`-Skill und der `callable_*`-Konvention.
- **Metriken:** Zustellrate (gesendet vs. erfolgreich), Fehlerquote je Code (`invalid-argument`, `registration-token-not-registered`), Opt-in-/Permission-Rate (Anteil aktiver User mit gültigem Token), Empfängermenge je Event-Typ.
- **Client-seitig** Crash-/Fehler-Reporting für Init-/Permission-/Tap-Routing-Fehler über die bestehende `ErrorReporter`-Fassade (fail-open, darf Start nicht fataler Zonenfehler werden).

### Tarif-Strategie: Entwicklung auf Spark, Go-Live auf Blaze

**Betreiber-Vorgabe:** Die **Zielumgebung ist Blaze** — die gesamte Architektur wird durchgängig auf Blaze-Basis entworfen (server-getriggerte Functions + Admin-SDK-Messaging, keine Spark-Workarounds, kein Client-Direktversand zum Umgehen von Functions). Lediglich der **Zeitpunkt** des produktiven Functions-Deploys ist aufgeschoben: Das Projekt bleibt während der Entwicklung auf **Spark** (Free-Tier), die Trigger laufen bis zum Schluss im **Emulator** + Unit-Tests, und die Umstellung auf **Blaze** erfolgt unmittelbar vor dem Go-Live.

**Genau EIN Baustein ist Blaze-gebunden:** das **Deployen + produktive Ausführen der sendenden Cloud Functions** (Firestore-Trigger → `admin.messaging().send`). Cloud-Functions-Deploys brauchen seit 2024 Blaze (Cloud Build / Artifact Registry). Alles andere ist auf Spark voll baubar **und** testbar:

| Baustein | Spark? | Anmerkung |
|---|---|---|
| FCM-Token holen/registrieren, `fcmTokens`-Subcollection schreiben | ✅ | normaler Firestore-Write |
| Rules + Indizes deployen (`fcmTokens`, `notifications`) | ✅ | kostenfrei |
| Push **empfangen + anzeigen** (Channels, Icon, Aktionen, Deep-Link, Foreground/Background) | ✅ | FCM-Zustellung ist auf Spark frei |
| Test-Push an ein Gerät senden | ✅ | Firebase-Console → Cloud Messaging → „Testnachricht an Token" (kein Blaze) |
| Sende-Trigger + Empfänger-Auflösung + Dedupe **schreiben & testen** | ✅ | Function-Unit-Tests (gemocktes `admin.messaging()`) + **Emulator Suite** (Functions + Firestore lokal) |
| `notifications`-Inbox, `notificationPrefs`, Einstellungs-Screen, In-App-Parität | ✅ | für Dev die Inbox-Docs im Emulator schreiben lassen oder per Test-Seed |
| Sende-Functions **produktiv deployen & live auslösen** | ❌ **Blaze** | der einzige aufgeschobene Schritt — Cutover am Ende |

**Konsequenz für die Roadmap:** M1, M4, M5 sowie das **Schreiben + Emulator-Testen** der Trigger aus M2/M3 laufen vollständig in der Spark-Phase. Erst der finale „Blaze-Cutover" (Functions-Deploy + APNs-Key/VAPID + Flag `APP_PUSH_ENABLED=true`) braucht den Tarifwechsel — die Deployment-Schritte 1, 5 (und 6 für Web) sind genau dieser Cutover. So bleibt die gesamte Entwicklung kostenfrei und nur die Live-Schaltung wartet auf Blaze.

### Deployment-Schritte

> Schritt 4 (Rules/Indizes), das iOS/Android-Client-Setup (2/3) und das gesamte Client-Verhalten lassen sich bereits in der **Spark-Phase** umsetzen und mit Console-Testnachrichten + Emulator verifizieren. Schritte **1, 5 und 6** sind der **Blaze-Cutover** am Ende.

1. **Blaze-Tarif** erforderlich für das produktive Deploy der sendenden Functions (Admin Messaging + Firestore-Trigger). **Erst am Ende der Entwicklung** — bis dahin laufen die Trigger lokal im Emulator. (OktoPOS/Scheduler warten auf denselben Cutover.)
2. **iOS:** APNs-Auth-Key (.p8, Team-ID, Key-ID) in der Firebase-Console (Cloud Messaging) hinterlegen; Push-Notifications-Capability + `Runner.entitlements` (`aps-environment` passend zu dev/prod) + `UIBackgroundModes: remote-notification` in `Info.plist`; ggf. AppDelegate um Messaging-/APNs-Delegate. Falsche `aps-environment`-Umgebung = stille Nicht-Zustellung.
3. **Android:** `POST_NOTIFICATIONS` + Default-Channel-Meta im Manifest; monochromes Notification-Icon.
4. **Rules + Indizes:** `firebase deploy --only firestore:rules,firestore:indexes` (neuer `fcmTokens`-`match`-Block; ggf. `COLLECTION_GROUP`-Index).
5. **Functions:** `firebase deploy --only functions` (kein Build-Step).
6. **Web (M6):** VAPID-Key (Cloud Messaging → Web Push certificates) als Config/dart-define; `firebase-messaging-sw.js` deployen; Caching-Header in `firebase.json` für den SW anpassen.
7. **Flag:** Release-Build mit `--dart-define=APP_PUSH_ENABLED=true` (Default bleibt aus), obfuskiert + getrennte Debug-Symbole wie bei allen Mobile-Releases.

### Offene Entscheidungen & Risiken

- **P1 — Abstimmung mit [kuehlschrank-nachfuell-automatik.md](kuehlschrank-nachfuell-automatik.md) · ENTSCHIEDEN (30.06.2026): Trennung Signal ↔ Zustellung.** Der Automatik-Plan **besitzt das Soll-Ist-Signal** (`fridgeStock ⊆ currentStock` am Product = „was fehlt im Kühlschrank"); dieser Push-Plan **besitzt die Zustellung** (M3) und konsumiert die **Flanke** „Standort hat offene Defizite" als Trigger (`products` onUpdate, gebündelt je Standort) — **nicht** mehr `fridgeRefillLists/{siteId}`. Deep-Link `/warenwirtschaft?tab=kuehl` (Ansicht gehört dem Automatik-Plan). Damit ein Datenmodell, keine Divergenz. Der echte Push ersetzt die im Automatik-Plan als „Phase 3 (nicht eingeplant)" geführte Stufe; reziproker Querverweis dort gesetzt.
- **Trigger-Strategie:** `onDocumentCreated` (nur Neuanlage, einfacher) vs. `onDocumentWritten` (Status-Übergänge wie `planned→confirmed`, Genehmigungen — braucht before/after-Vergleich). Wahrscheinlich gemischt je Event.
- **local-only-Lücke:** Im `local`-Modus existiert kein Firestore-Doc → kein Server-Trigger; im hybrid-Offline-`catch`-Fallback feuert der Trigger erst beim späteren Cloud-Sync (kein Outbox-Re-Sync). Bewusst akzeptierte Asymmetrie oder client-seitiger Trigger pro Mutator-Zweig (wie `_audit?.call`) — gegen Duplizierung über mehrere Geräte abwägen.
- **Scope-Asymmetrie In-App ↔ Push:** Kundenwunsch/Feedback sind heute **keine** Inbox-Events; Meldebestand/Kundenbestellungen zählen nicht ins Inbox-Badge. Entscheiden, ob Push breiter ist als die In-App-Inbox und ob das Badge (`pendingInboxActionCount`) angeglichen wird.
- **In-App-Persistenz:** Ob zusätzlich ein persistiertes Notification-/Read-Status-Modell eingeführt wird (heute ist die Inbox rein derived, kein gelesen/ungelesen-Zustand). Orthogonal zur reinen Token-Registrierung; bei Bedarf eigene Collection + Rules + Index + Zwei-Serialisierung.
- **Token-Doc-ID:** roher FCM-Token (lang, >1500 Bytes — grenzwertig als Doc-ID) vs. Installations-ID/Hash (empfohlen).
- **Web-Config im SW** widerspricht dem „keine committete Config"-Prinzip (siehe M6).
- **Spam-/Quota-Risiko:** hochfrequente Quellen (Kühlschrankliste, Bestandsbewegungen, Batch-Publish bis 50 Schichten) → Bündelung/Entprellung zwingend; Memory markiert Kühlschrank/Bestellkorb bereits als Rauschen (kein Audit) — analog kein Per-Item-Push.
- **Invite-only-Personen** (nur `userInvites`, noch kein `users/{uid}`) haben keine uid/kein Token → nicht adressierbar bis zum ersten Login; Routing muss das tolerieren.
