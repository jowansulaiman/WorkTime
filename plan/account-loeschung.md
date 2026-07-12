# Account-Löschung (komplett) — Plan

Stand: 2026-07-08 · Branch `feat/zeit-schichtbindung-freigabe`

## Ziel

Ein Konto soll sich **komplett löschen** lassen — nicht nur wie bisher
deaktivieren (`isActive=false`). Auslöser laut Nutzerentscheidung (08.07.):

1. **Datenumfang = Anonymisieren.** Konto + persönliche Daten hart löschen;
   aufbewahrungspflichtige Zeit-/Lohn-/Vertrags-/Kassendaten **behalten, aber die
   Personen-Verknüpfung anonymisieren** (Art. 17 Abs. 3 lit. b DSGVO vs.
   GoBD/ArbZG/§147 AO). Keine Auto-Löschung nach Fristablauf.
2. **Berechtigung = Self + Admin.** Der eingeloggte Nutzer löscht sein eigenes
   Konto; ein Admin darf zusätzlich fremde Org-Mitglieder komplett löschen (statt
   nur deaktivieren).
3. **Sicherheit = Reauth + Dialog.** Vor der Löschung Passwort erneut eingeben
   (bzw. Google-Reauth), dann destruktiver Bestätigungsdialog.

Die bisherige „Löschen = Deaktivieren"-Entscheidung
(`plan/personal-alltec-1zu1.md`) bleibt als **reversibler Standard** bestehen;
die harte Löschung ist der neue, bewusst abgesicherte Zusatzweg.

## Architektur-Entscheidung: Server-getriebene Löschung (Admin SDK)

`users/{uid}` ist per `firestore.rules` bewusst unlöschbar (`allow delete: if
false`), und ein Client kann fremde Firebase-Auth-Nutzer nie löschen. Deshalb
läuft die eigentliche Löschung **serverseitig** über eine neue Callable
`deleteUserAccount` (Admin SDK, umgeht Rules). Vorteile:

- Ein einheitlicher Pfad für Self- und Admin-Löschung.
- `admin.auth().deleteUser(uid)` braucht **keine** Firebase-Reauth
  (`requires-recent-login` gilt nur für den Client-`user.delete()`). Die Reauth
  ist primär das **Client-Sicherheitsgate** vor dem Callable-Aufruf; server-seitig
  verankert ein **Step-up-Check** (`assertRecentAuth`, `auth_time` ≤ 10 min) sie
  zusätzlich, damit ein bloß gültiges (evtl. entwendetes) Token allein nicht
  genügt. Der Client erzwingt dafür nach der Reauth ein frisches ID-Token
  (`getIdToken(true)`).
- **`firestore.rules` bleiben unverändert** (kein Aufweichen des Delete-Verbots).

Blaze ist Produktions-Standard (Memory `blaze-zielumgebung`); kein neues Secret
nötig (Service-Account-Identität). Deploy reiht sich in den bekannten
„undeployed Blaze-Module"-Stau ein.

## Datenklassifikation (`functions/account_deletion.js`, pure + node-testbar)

**Anonymer, pro Nutzer stabiler Marker:** `anonSentinel(uid)` =
`geloescht:<sha256(uid)[:12]>` — gleiche uid → gleicher Marker, damit
aufbewahrungspflichtige Aggregate (Lohn/Zeit je Person) zusammenhängend bleiben,
die Person aber nicht mehr identifizierbar ist.

### A) HART LÖSCHEN — persönliche Daten ohne Aufbewahrungspflicht

- Top-Level: `users/{uid}` (via `recursiveDelete` inkl. Subcollection
  `fcmTokens`), `userInvites/{emailLower}` (sonst Bootstrap-Falle:
  `ensureProfileForSignedInUser` sperrt den nächsten Login mit `StateError`).
- Doc-ID == uid: `shiftPreferences`, `employeeProfiles`, `payrollProfiles`,
  `userSecrets`, `kioskRoster`, `kioskPresence`.
- Feld-basiert: `absenceRequests`, `workTemplates`, `shiftTemplates`, `shifts`
  (löst das `userId`-required-Problem + gibt Planung frei),
  `sollzeitProfiles`, `employeeSiteAssignments`, `employeeChildren`,
  `employeeNotes`, `employeeQualifications`, `employeeAusbildungen`,
  `kioskSessions` (Feld `employeeId`), `notifications` (Feld `recipientUid`).

### B) ANONYMISIEREN — Personen-Verknüpfung durch Marker ersetzen, Doc behalten

Nur die genannten **Link-Felder** werden auf den Marker gesetzt; die
fachlichen Nutzdaten (Stunden, Beträge) bleiben für Steuer/Prüfung erhalten.
**Alle** uid-Link-Felder eines Docs werden erfasst — auch als Freigeber/
Ersteller/Korrektor in FREMDEN Datensätzen, sonst bliebe die uid dort roh stehen.

- `workEntries` [`userId`,`approvedByUid`,`correctedByUid`],
  `clockEntries` [`userId`,`createdByUid`,`korrigiertVonUid`],
  `zeitkontoSnapshots` [`userId`,`createdByUid`],
  `employmentContracts` [`userId`], `payrollRecords` [`userId`,`createdByUid`],
  `cashCounts` [`createdByUid`,`countedByUserId`], `cashClosings` [`closedByUid`],
  `journalEntries` [`createdByUid`], `stockMovements` [`createdByUid`],
  `auditLog` [`actorUid`], `shiftSwapRequests` [`requesterUid`,`targetUid`],
  `swapCredits` [`creditorUid`,`debtorUid`],
  `urlaubskontoJahre` [`userId`], `urlaubsanpassungen` [`userId`]
  (Urlaub ist arbeitszeit-/lohn-nah → behalten + anonymisieren, nicht hart löschen).
- **Produkt-Subcollection** `priceHistory` [`changedByUid`] via
  `collectionGroup('priceHistory').where('orgId',==).where('changedByUid',==)`
  (liegt unter `products/{pid}/` — org-Top-Level-Query griffe ins Leere). Braucht
  einen **collectionGroup-Composite-Index** (`orgId`+`changedByUid`).
- `passwordEntries`: uid aus `audienceUids[]` per `arrayRemove` entfernen;
  eigene Einträge (`ownerUid==uid`) samt `passwordSecrets`/`passwordAccessLog`
  löschen.

### C) BEWUSST UNANGETASTET (dokumentierte Residuen)

- **`employeeDocuments` + Storage `employee-documents/{orgId}/{userId}/**`**:
  aufbewahrungspflichtig (bis 10 J.). Bleiben; der bestehende „Dokumente-Tab"-Flow
  (`documentsWithExpiredRetention`) räumt abgelaufene selbst ab.
- **`auditLog`-Summaries**: `actorUid` wird anonymisiert, deutsche Summaries mit
  Klarnamen bleiben (admin-only lesbar, Forensik/Nachweis).
- **Denormalisierte Namensfelder** in einzelnen Transaktions-Docs (z. B.
  `requesterName`) werden nicht generisch gescrubbt — historischer Snapshot.
- **`zeitkontoSnapshots`/`urlaubskontoJahre`-Doc-IDs** enthalten die uid als
  technischen Schlüssel; nur das Feld wird anonymisiert.
- **Backups/PITR** behalten gelöschte Daten bis Ablauf der Backup-Retention —
  Betreiber-Aufgabe, nicht in-App lösbar.

## Schutzschranken (Server)

- **Berechtigung:** `caller.uid == targetUid` (Self) ODER `caller.isAdmin`
  (Fremd). `assertSameOrg(caller, targetOrg)` (Mandantengrenze, spiegelt Rules).
- **Step-up:** `assertRecentAuth(request)` — `auth_time` des Callers ≤ 10 min
  (Client-Reauth erneuert das Token), sonst `failed-precondition`.
- **Letzter-Admin-Schutz:** Ist das Ziel `admin` und der einzige *aktive* Admin
  der Org → `failed-precondition` (Org darf nicht verwaisen).
- **Audit:** `writeAudit({action:'deleted', entityType:'Benutzerkonto', ...})`
  nur auf Erfolgspfad.

## Client-Seams / Slices

**Slice 1 — offline (Demo-Modus, kein Firebase, kein Blaze):**
- `DatabaseService.wipeAllLocalData()` — entfernt alle `local_v2/*`- und
  `setting_*`-Keys + `local_auth_user_id` + `data_storage_location`.
- `AuthService.reauthenticateWithPassword` / `reauthenticateWithGoogle` +
  `primaryProviderId`-Getter (aus `currentUser.providerData`).
- `AuthProvider.reauthenticate(...)`, `deleteOwnAccount()` mit `if(authDisabled)`-
  Zweig (Demo: nur lokaler Wipe + Sign-out); `_mapError` um
  `requires-recent-login` erweitert.
- UI: Danger-Zone in `settings_profile_screen.dart` → Reauth-Dialog →
  `AppConfirmDialog(destructive:true)` → Löschen → Gate `/anmelden`.

**Slice 2 — Callable-Seam (offline über Fake-Invoker testbar):**
- `FirestoreService.deleteUserAccount({required userId})` via `_callCloudFunction`.
- `TeamProvider.deleteMemberAccount(uid)` (admin-gated; Cloud ruft Callable,
  Local entfernt Mitglied + persistiert).

**Slice 3 — Cloud Function (Blaze, erst nach Cutover deploybar):**
- `functions/account_deletion.js` (Klassifikation/pure Helfer) + Callable
  `deleteUserAccount` in `functions/index.js` (+ `_testables`).

## Betroffene Kopplungen (CLAUDE.md)

- **3 Enforcement-Ebenen** synchron: Client-Guard (self/isAdmin) ↔
  `firestore.rules` (`users delete:if false` bleibt) ↔ Callable
  (`assertSameOrg`/Rollen). Löschpfad läuft ausschließlich über die Callable.
- **Region (#8):** neue Callable in `europe-west3`.
- **Composite-Index:** neuer **collectionGroup**-Index `priceHistory`
  (`orgId`+`changedByUid`) in `firestore.indexes.json` → mit-deployen.
- **Provider-Kette (#4):** nach Self-Löschung `auth.profile==null` → Gate
  `/anmelden`; Löschung endet mit lokalem Wipe + Sign-out.
- **Zwei-Serialisierung (#1):** kein neues Model-Feld nötig (Anonymisierung
  passiert serverseitig auf Roh-Feldern). `isActive` bleibt unberührt.

## Definition of Done

- `flutter analyze` clean, `flutter test` grün (neue Tests: DB-Wipe,
  AuthProvider-Demo-Delete, Callable-Seam), `npm test` in `functions/` grün
  (account_deletion-Helfer).
- Demo-Modus end-to-end: Konto löschen → zurück auf Anmeldung, lokale Daten weg.
- Cloud Function code-complete; **Deploy offen** (Blaze) →
  `plan/deploy-checkliste.md` (functions).

## Offene Punkte / Restrisiken

- Storage-Cleanup von `employee-documents` bewusst nicht Teil der Löschung
  (Aufbewahrung) — ggf. später abgelaufene Blobs mit-räumen.
- `employmentContracts`/`payrollRecords` behalten fachliche Nutzdaten inkl. ggf.
  denormalisierter Beträge; Personen-Link ist anonymisiert.
- Deploy-Reihenfolge: **erst `firestore:indexes`** (collectionGroup-Index), dann
  `functions` nach Blaze-Cutover; vorher ist der Client-Aufruf ein
  `not-found`/`unavailable` → UI zeigt Fehler (kein stiller Fallback, da kein
  Direkt-Write-Pfad existiert).
- **Empfohlene Zusatzhärtung:** `enforceAppCheck: true` an der Callable (wie
  Passwort-/Kiosk-Callables), sobald App Check für alle Löschpfade
  (Web-Selbstlöschung!) sicher konfiguriert ist. Aktuell absichtlich weggelassen,
  um den Deploy nicht an eine ungetestete App-Check-Konfiguration zu koppeln;
  der `auth_time`-Step-up deckt das Kern-Risiko bereits ab.
