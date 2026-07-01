# Plan: Schichttausch (Tauschanfrage) zwischen Mitarbeitern

Stand: 2026-06-24 · Status: UMGESETZT (flutter analyze sauber, 903 Tests grün)

Zusatz-Entscheidungen (bestätigt + umgesetzt):
- Gutschrift „eingelöst" dürfen Schichtleitung **und** beteiligte Mitarbeiter
  (Gläubiger/Schuldner) markieren.
- Anfragen-Tab trägt ein Zähler-Badge (offene Anträge + Tausch-Aktionen) –
  in Bottom-Nav, klassischer NavigationRail und V2-AppNavRail.

Deploy noch offen (durch dich): `firebase deploy --only firestore:rules`.
(Indizes brauchen keinen Deploy – keine neuen Composite-Indizes nötig.)

## Ziel

Ein Mitarbeiter kann eine **Tauschanfrage** stellen: Er wählt die Schicht eines
Kollegen, mit dem er tauschen möchte. Der eingeplante Kollege bekommt die Anfrage
und kann **annehmen/ablehnen**. Zusätzlich gibt es den **einseitigen Tausch**
(Übernahme): der Kollege übernimmt die Schicht, gibt aber **nichts zurück** –
das wird als **Gutschrift** festgehalten und nächsten Monat geregelt.

## Getroffene Entscheidungen (vom Nutzer bestätigt)

| # | Frage | Entscheidung |
|---|---|---|
| D1 | Was passiert bei Annahme? | **Chef bestätigt/führt aus.** Nach Annahme durch den Kollegen erscheint die Anfrage beim Chef, der sie mit „Übernehmen" vollzieht. Chef ist Torwächter (mehr als nur informiert). |
| D2 | Wer schreibt den Tausch? | Der **Chef** (hat `canManageShifts`). **Keine neue Cloud Function nötig** – läuft über den bestehenden `saveShifts`-Pfad. |
| D4 | Einseitiger Tausch | **Vollständiges Gutschrift-Konto** (eigene Collection `swapCredits`): wer wem eine Schicht schuldet, „eingelöst"-Markierung, optionaler Rück-Vorschlag. |
| D3 | Regelverletzung beim Übernehmer | **Warnen, Chef kann übersteuern.** Compliance ist beim Bestätigen ein *weiches* Gate (Vorschau + „Trotzdem übernehmen" → Direkt-Write, bewusster Bypass). |
| D4b | Sichtbarkeit | **Kollegen-Schichten im Zeitraum sichtbar** – Lese-Regel für `shifts` wird geöffnet (jeder mit `canViewSchedule` darf org-weit lesen). |

## Wichtige Vorabentscheidung

Die bestehende, halbfertige Tausch-Logik (`Shift.swapStatus` /
`requestShiftSwap` / `reviewShiftSwap`) bleibt **unangetastet** (Altlast: im
Cloud-Modus durch die Rules ohnehin blockiert, kein Tauschpartner-Feld, schreibt
`userId` nie um). Das neue Feature nutzt eine **eigene Collection**
`shiftSwapRequests` und spiegelt das bewährte `AbsenceRequest`-Muster
(Self-Service-Anlage + Manager-Review). In der UI ersetzt der neue Pfad den alten
„Tausch anfragen"-Button.

---

## 1. Datenmodell

### 1a. `lib/models/shift_swap_request.dart` (NEU, spiegelt `absence_request.dart`)

```dart
enum SwapKind { exchange, giveAway }       // .value: exchange / give_away
//   exchange = beide Schichten benannt → beide userIds werden getauscht
//   giveAway = einseitig: targetShiftId == null → nur die Antragsteller-Schicht
//              wandert, es entsteht eine Gutschrift

enum SwapStatus {                          // .value (snake_case) / fromValue → pending
  pending,             // wartet auf Kollegen
  acceptedByColleague, // Kollege hat angenommen → wartet auf Chef
  declinedByColleague, // Kollege hat abgelehnt   (Endzustand)
  confirmed,           // Chef hat ausgeführt      (Endzustand, Tausch vollzogen)
  rejectedByManager,   // Chef hat abgelehnt       (Endzustand)
  cancelled,           // Antragsteller hat zurückgezogen (Endzustand)
}
```
`.label` deutsch: Offen / Vom Kollegen angenommen / Vom Kollegen abgelehnt /
Bestätigt / Vom Chef abgelehnt / Zurückgezogen. `fromValue` mit Default-Branch
(wirft nie – Enum-Regel #3).

Felder:

```dart
class ShiftSwapRequest {
  final String? id;
  final String orgId;
  // Antragsteller
  final String requesterUid;        // == auth.uid bei Anlage (server-/regel-pinned)
  final String requesterName;       // denormalisiert
  final String requesterShiftId;    // Schicht, die abgegeben wird
  // Zielmitarbeiter (Kollege)
  final String targetUid;
  final String targetName;
  final String? targetShiftId;      // NULL bei giveAway (der „nächsten Monat"-Fall)
  final SwapKind kind;
  final SwapStatus status;
  final String? reviewedByUid;      // Chef, der bestätigt/abgelehnt hat
  final bool overriddenCompliance;  // Chef hat Regelverstoß übersteuert
  final String? note;
  // denormalisierte Schicht-Snapshots (Inbox ohne Lesezugriff auf Fremd-Schicht)
  final DateTime requesterShiftStart;
  final DateTime? targetShiftStart; // null bei giveAway
  final String? requesterShiftLabel;
  final String? targetShiftLabel;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}
```

Begründung der Snapshots: Inbox des Kollegen / des Chefs muss die Anfrage
**aus dem Request-Doc allein** rendern – auch wenn Lesezugriff auf die
Fremd-Schicht (noch) fehlt.

Zwei-Serialisierungs-Regel (beide Pflicht, wie `AbsenceRequest`):
- `toFirestoreMap()` / `fromFirestore(id, map)` – camelCase + `Timestamp` +
  `FieldValue.serverTimestamp()` bei Anlage.
- `toMap()` / `fromMap(map)` – snake_case + ISO-8601, `id` aus `map['id']`.
- `copyWith(...)` mit `clearX`-Flags für **jedes** nullable Feld
  (`clearTargetShiftId`, `clearReviewedByUid`, `clearNote`, `clearTargetShiftStart`,
  `clearTargetShiftLabel`, …).
- Fließt **nicht** durch eine Callable → **kein** `functions/index.js`-Eingriff
  für das Request-Doc.

### 1b. `lib/models/swap_credit.dart` (NEU – das Gutschrift-Konto)

```dart
enum SwapCreditStatus { open, settled, cancelled }   // .value / fromValue → open

class SwapCredit {
  final String? id;
  final String orgId;
  final String creditorUid;     // wem geschuldet wird (= Kollege/target, der übernommen hat)
  final String creditorName;
  final String debtorUid;       // wer schuldet (= Antragsteller/requester)
  final String debtorName;
  final String originSwapRequestId;
  final DateTime originShiftStart;   // die abgegebene Schicht
  final String? originShiftLabel;
  final SwapCreditStatus status;
  final String? settledBySwapRequestId;
  final DateTime? settledAt;
  final String? note;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}
```
Entsteht **automatisch**, wenn der Chef einen `giveAway`-Tausch bestätigt.
Richtung: creditor = `targetUid` (hat die Schicht zusätzlich übernommen → ist eine
zurück gut), debtor = `requesterUid` (hat seinen Tag abgegeben → schuldet eine).
Gleiche Zwei-Serialisierungs-Regel + `copyWith`/`clearX`.

---

## 2. Provider — `ScheduleProvider` (`lib/providers/schedule_provider.dart`)

Eigentümer ist `ScheduleProvider` (besitzt schon Schichten + Abwesenheiten).
**Kein** neuer Provider, **keine** `main.dart`-Kettenänderung (Kopplung #4 nicht
ausgelöst). Neue Caches/Streams neben den Abwesenheits-Caches
(`_swapRequests`/`_allSwapRequests`/`_localSwapRequests`,
`_swapCredits`/…), zurückgesetzt in `updateSession` + `dispose`, mit gleicher
Tombstone-/Merge-Logik im Hybrid-Modus.

Neue Mutatoren (Muster strikt wie `submitAbsenceRequest`/`reviewAbsenceRequest`,
Storage-Modus-Muster + Audit auf jedem Erfolgspfad, nie auf rethrow):

- `submitShiftSwapRequest(ShiftSwapRequest req)` — Antragsteller. `orgId`/
  `requesterUid`/`requesterName` aus `_currentUser` setzen, `status=pending`
  erzwingen. Audit: `entityType:'Schichttausch'`, `'Tauschanfrage gesendet'`.
- `respondToShiftSwapRequest({requestId, accept})` — **Kollege** (Guard:
  `req.targetUid == _currentUser.uid`). Nur das Request-Doc:
  accept → `acceptedByColleague`, decline → `declinedByColleague`. **Keine
  Schicht wird hier angefasst.** Audit `'Tauschanfrage angenommen/abgelehnt'`.
- `cancelShiftSwapRequest(requestId)` — Antragsteller, nur solange
  `pending`/`acceptedByColleague` → `cancelled`.
- `confirmShiftSwapRequest({requestId, overrideCompliance=false})` — **Chef**
  (Guard `canManageShifts`). Der lasttragende Teil:
  1. Schicht-Kopien bauen: `requesterShift.copyWith(userId: targetUid,
     employeeName: targetName)`; bei `exchange` zusätzlich
     `targetShift.copyWith(userId: requesterUid, employeeName: requesterName)`.
     `employeeName` aus `_orgMembers` neu ableiten (nicht dem Snapshot trauen).
     Nur `userId`/`employeeName` wandern – `id`/Zeiten/`siteId`/`seriesId`/`status`
     bleiben.
  2. Schreiben über `saveShifts([...], skipCompliance: overrideCompliance)`
     (neuer Parameter, s. u.). Ohne Override hart (wirft `ShiftConflictException`/
     `ComplianceRejectedException` → UI zeigt Warnung, Chef kann mit Override
     erneut). **Status erst auf `confirmed` setzen, NACHDEM `saveShifts`
     erfolgreich war** (transaktionale Absicht).
  3. Bei `giveAway`: `SwapCredit` anlegen (creditor=target, debtor=requester).
  4. Audit `entityType:'Schichttausch'`, `'Schichttausch durchgeführt: A ↔ B'`
     (eigene Summary nach `saveShifts`, wie `applyAutoPlan`).
- `rejectShiftSwapRequest(requestId)` — Chef → `rejectedByManager`.
- `previewSwapCompliance(req)` — liefert `List<ShiftConflictIssue>` für die
  vorgeschlagene Umbuchung (nutzt `validateShifts` auf den Schicht-Kopien),
  damit der Chef die Warnung **vor** dem Bestätigen sieht.
- `getSwappableShiftsInRange(start, end)` — org-weite Schichten für den Picker
  (Cloud/Hybrid via neuem `firestore_service.getShiftsInRange`-Aufruf ohne
  uid-Filter / Local aus vollem Cache). Setzt die geöffnete Lese-Regel voraus.
- `settleSwapCredit(creditId, {settledBySwapRequestId, note})` /
  `cancelSwapCredit(creditId)` — Chef (oder Beteiligte) markiert Gutschrift
  eingelöst. Audit `entityType:'Gutschrift'`.

`saveShifts(...)` bekommt **einen** neuen Parameter `bool skipCompliance = false`:
- `true` ⇒ überspringt den `validateShifts`→throw und routet Cloud/Hybrid-Writes
  über einen **direkten** Pfad (`FirestoreService.saveShiftBatchDirect`, neuer
  öffentlicher Wrapper um das vorhandene `_saveShiftBatchDirect`) statt über die
  Callable → bewusster Compliance-Bypass (vom Chef autorisiert). Local-Modus:
  schreibt wie gehabt lokal.

`FirestoreService`: neue Collection-Getter `_swapRequestCollection(orgId)` +
`_swapCreditCollection(orgId)` (neben `_absenceCollection`, Z. 142), Stream-/
Save-/Review-Methoden gespiegelt von den Abwesenheits-Methoden, plus public
`saveShiftBatchDirect(shifts)`.

---

## 3. Benachrichtigung / Sichtbarkeit (am tatsächlichen Mechanismus)

**Es gibt KEIN Push/FCM** – „Benachrichtigung" = abgeleitete In-App-Liste im
**Anfragen-Tab** (`lib/screens/notification_screen.dart`), live aus Firestore-
Streams. Daher:

- **Kollege** sieht die eingehende Anfrage: neuer `_InboxItem`-Zweig gefiltert
  `targetUid == ownUserId && status == pending` → Aktionen **Annehmen/Ablehnen**.
- **Chef** sieht zur Bestätigung: `_InboxItem`-Zweig `canManageShifts() &&
  status == acceptedByColleague` → Compliance-Vorschau + **Übernehmen/Ablehnen**.
- **Gutschriften**: eigener Abschnitt – Mitarbeiter sieht eigene
  („Du schuldest X eine Schicht" / „Y schuldet dir eine"), Chef sieht alle mit
  „Eingelöst"-Aktion.
- Optional (nicht zwingend): numerisches `Badge` am `ShellTab.inbox`
  (`home_screen.dart`). Hinweis: Im **Local-Modus** keine geräteübergreifende
  Zustellung (nur SharedPreferences) – Tausch funktioniert real nur Cloud/Hybrid.

---

## 4. Firestore Rules + Indizes

### `firestore.rules` (neuer Block in `match /organizations/{orgId}`)

```
match /shiftSwapRequests/{requestId} {
  allow read: if sameOrg(orgId) && (
    canManageShifts()
    || resource.data.requesterUid == request.auth.uid
    || resource.data.targetUid == request.auth.uid);
  allow create: if sameOrg(orgId)
    && request.resource.data.requesterUid == request.auth.uid
    && request.resource.data.orgId == orgId
    && request.resource.data.status == 'pending';
  allow update: if sameOrg(orgId)
    && request.resource.data.orgId == resource.data.orgId
    && request.resource.data.requesterUid == resource.data.requesterUid
    && request.resource.data.targetUid == resource.data.targetUid
    && (
      // Kollege nimmt an / lehnt ab
      (resource.data.targetUid == request.auth.uid && resource.data.status == 'pending'
        && request.resource.data.status in ['accepted_by_colleague','declined_by_colleague'])
      // Antragsteller zieht zurück
      || (resource.data.requesterUid == request.auth.uid
        && resource.data.status in ['pending','accepted_by_colleague']
        && request.resource.data.status == 'cancelled')
      // Chef bestätigt / lehnt ab
      || (canManageShifts() && resource.data.status == 'accepted_by_colleague'
        && request.resource.data.status in ['confirmed','rejected_by_manager'])
    );
  allow delete: if sameOrg(orgId) && (canManageShifts()
    || (resource.data.requesterUid == request.auth.uid && resource.data.status == 'pending'));
}

match /swapCredits/{creditId} {
  allow read: if sameOrg(orgId) && (canManageShifts()
    || resource.data.creditorUid == request.auth.uid
    || resource.data.debtorUid == request.auth.uid);
  allow create: if sameOrg(orgId) && canManageShifts()
    && request.resource.data.orgId == orgId;          // nur über Chef-Bestätigung
  allow update: if sameOrg(orgId) && canManageShifts()
    && request.resource.data.orgId == resource.data.orgId;
  allow delete: if sameOrg(orgId) && canManageShifts();
}
```

### Lese-Regel `shifts` öffnen (D4b)

```
allow read: if sameOrg(orgId) && (canManageShifts() || canViewSchedule());
```
(statt bisher uid-gebunden). Bewusste Öffnung: jeder Mitarbeiter mit
`canViewSchedule` darf org-weit Schichten lesen (für den Tausch-Picker).

### `firestore.indexes.json`

**Keine neuen Composite-Indizes nötig** (umgesetzt): alle Tausch-/Gutschrift-
Streams nutzen nur Einzelfeld-Gleichheit (`targetUid`/`requesterUid` bzw.
`creditorUid`/`debtorUid`) und sortieren clientseitig; die Kandidaten-Abfrage
ist ein Einzelfeld-Range+OrderBy auf `startTime` (automatisch indexiert).

---

## 5. UI-Flächen (+ `canManageShifts`-Footgun)

1. **„Tausch anfragen" (Mitarbeiter, Picker)** — im Mitarbeiter-Pfad von
   `shift_planner_screen.dart` (`_ShiftCard`, der `!isAdmin`-Block). Statt direkt
   `requestShiftSwap`: neues `showModalBottomSheet`
   `_SwapTargetPickerSheet` (in `shift_editor_sheet.dart`, Muster `_CopyShiftSheet`):
   listet Kandidatenschichten (Datum + Zeit + Kollegenname) aus
   `getSwappableShiftsInRange`, plus Option **„Niemand zurück (Gutschrift
   nächsten Monat)"** → `kind = giveAway`, `targetShiftId = null`. → `submitShiftSwapRequest`.
2. **Annehmen/Ablehnen (Kollege)** — `_InboxItem`-Zweig in `notification_screen.dart`.
3. **Übernehmen/Ablehnen (Chef)** — `_InboxItem`-Zweig (`canManageShifts`),
   mit Compliance-Vorschau-Warnung + „Trotzdem übernehmen".
4. **Gutschriften-Liste** — Abschnitt in `notification_screen.dart`.

**Footgun:** `ShiftPlannerScreen.build` gibt für `canManageShifts` **früh**
`_AdminShiftPlannerBoard` zurück → der Mitarbeiter-Pfad rendert nur für
Nicht-Admins. Mitarbeiter-Picker dort korrekt; alle Chef-Flächen gehören nach
`notification_screen.dart` (nicht in den Fallback-Pfad). Fehler via SnackBar /
`_showComplianceRejectionDialog`/`_showShiftConflictDialog`. Alle Texte deutsch,
jedes `DateFormat` mit `'de_DE'`.

---

## 6. Kopplungs-Checkliste („Wenn X, dann Y")

1. **Neue Modelle** `ShiftSwapRequest`, `SwapCredit` → je 5 Serialisierungspunkte
   (`toFirestoreMap`/`fromFirestore`/`toMap`/`fromMap`/`copyWith`+`clearX`).
   Keine `functions/index.js`-Änderung (Direkt-Writes).
2. **Neue Enums** `SwapKind`/`SwapStatus`/`SwapCreditStatus` → `.value` + dt.
   `.label` + `fromValue`-Default (#3).
3. **Neue Collections** → Getter in `firestore_service.dart` + Rules-Block +
   Indizes (#5/#6).
4. **Neue lokal-persistierte Collections** `shift_swap_requests`, `swap_credits`
   → in `DatabaseService` als **org-skopiert** registrieren, `toMap`/`fromMap`
   round-trippt (#5).
5. **Schicht-Umbuchung** über bestehenden `saveShifts`/Callable – `userId`/
   `employeeName` schon serialisiert → keine Functions-Änderung. Override-Pfad
   = neuer `saveShiftBatchDirect`.
6. **Audit** `entityType:'Schichttausch'` + `'Gutschrift'` – nur Erfolgspfade.
7. **Provider-Caches/Streams** → `updateSession`-Reset + `dispose` + Hybrid-Merge.
8. **Compliance** wird wiederverwendet, nicht geändert (#2 nicht ausgelöst).
9. **Kein** neuer Provider in `main.dart` (#4 nicht ausgelöst).
10. **Rules-Öffnung** `shifts` read – Sicherheits-relevant, vom Nutzer (D4b) freigegeben.

---

## 7. Tests (`test/`, offline, fakes)

Neues `test/shift_swap_test.dart`:
- Modell-Round-Trip beider Formate (`ShiftSwapRequest`, `SwapCredit`).
- Provider-Flow: submit (pending) → respond(accept) (acceptedByColleague) →
  confirm vertauscht `userId`/`employeeName` beider Schichten.
- `giveAway`-Confirm: nur eine Schicht wandert + `SwapCredit` (open) entsteht.
- Override: confirm mit Regelverstoß ohne Override wirft, mit Override schreibt.
- decline / cancel / managerReject Zustandsübergänge.
- `settleSwapCredit` → status `settled`.
Muster: `FakeFirebaseFirestore`, `SharedPreferences.setMockInitialValues({})` +
`DatabaseService.resetCachedPrefs()`, `await provider.updateSession(user)` +
`updateReferenceData(...)`. Compliance auf `.code` asserten.

## 8. Reihenfolge der Umsetzung

1. Modelle (`shift_swap_request.dart`, `swap_credit.dart`).
2. `firestore_service.dart` (Collections, Streams, save/review, `saveShiftBatchDirect`).
3. `DatabaseService` (lokale Collections).
4. `ScheduleProvider` (Caches/Streams, Mutatoren, `saveShifts` skipCompliance,
   `getSwappableShiftsInRange`, Gutschriften).
5. `firestore.rules` + `firestore.indexes.json`.
6. UI (Picker-Sheet, Inbox-Zweige Kollege/Chef, Gutschriften).
7. Tests + `flutter analyze` + `flutter test`.
8. (Deploy `firestore:rules,indexes` macht der Nutzer.)
