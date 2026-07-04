# Cloud Functions

Die Cloud Functions liegen in `functions/index.js` – **v2 `onCall`**, Region `europe-west3`, **Node 20, plain JS, kein Build-Step**.

## Die Callables

- `upsertShiftBatch`, `publishShiftBatch`
- `upsertWorkEntry`, `upsertWorkEntryBatch`
- `previewCompliance`

Zusätzliche Function-Dateien: `functions/oktopos_stats.js`, `functions/push_notifications.js`, `functions/password_crypto.js`, `functions/password_access.js`, `functions/third_party_cash.js`.

## Was über Callables läuft – und was nicht

> [!IMPORTANT]
> **Nur Schichten + Zeiteinträge** laufen über Callables (gated durch `!AppConfig.disableAuthentication`). Templates/Teams/Sites/Abwesenheiten/Verträge schreiben **direkt** in Firestore.

Callables prüfen Caller-Rolle/Permissions + Same-Org und **re-validieren Compliance serverseitig**. Bei blockierender Verletzung → `failed-precondition`.

> [!WARNING]
> Der Client wirft `failed-precondition` als `StateError(deutscheMessage)` und **verwirft** die strukturierten `{issues}`/`{validations}`. Batch-Limit = **50**.

## previewCompliance wird NICHT vom Client aufgerufen

> [!NOTE]
> `previewCompliance` wird vom Dart-Client **nicht** aufgerufen – die Preview macht clientseitig der `ComplianceService`. Siehe [Compliance-Engine](article:dev-compliance-engine).

## Die Sicherheitslücke per Design

`firestore.rules` erlauben **direkte** Client-Writes auf shifts/workEntries (self+permission oder admin) und rufen die Functions **nicht** auf → direkte Writes umgehen die Compliance-Validierung. Der **Callable-Pfad ist der validierte Pfad**. Details: [Sicherheit & Mandantentrennung](article:dev-sicherheit-multi-tenancy).

## Region-Kopplung

`FIREBASE_FUNCTIONS_REGION` (dart-define) muss `const REGION` in `functions/index.js` entsprechen. Weicht sie ab, schlagen Callables fehl und der direkte Fallback greift still.

## Deploy

```bash
firebase deploy --only functions   # kein Build-Step
```

## Weiter

- [Compliance-Engine (Client/Server-Spiegel)](article:dev-compliance-engine)
- [OktoPOS-Kassenanbindung](article:dev-oktopos)
- [Deployment & Release](article:dev-deployment-release)
