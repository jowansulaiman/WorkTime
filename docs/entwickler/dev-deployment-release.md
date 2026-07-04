# Deployment & Release

Deployment läuft über die Firebase-CLI; die Zielumgebung ist **Blaze**. Es gibt keinen Build-Step für die Functions (plain JS).

## Firebase deployen

```bash
firebase deploy --only firestore:rules,firestore:indexes
firebase deploy --only functions          # functions/ = plain JS, kein Build-Step
firebase emulators:start
```

Hosting serviert `build/web` (SPA-Rewrite, no-cache Header).

## Reihenfolge

> [!IMPORTANT]
> Deploy-Reihenfolge bei neuen Features: **Rules/Indexes → Functions → App**. Ein neuer `where`+`orderBy`-Query braucht vorher den passenden Composite-Index in `firestore.indexes.json`. Für OktoPOS-Stats: `rebuildPosDailyStats`-Backfill **direkt nach** dem Functions-Deploy laufen lassen.

## Mobile Release-Builds

> [!WARNING]
> Release-Builds **immer obfuskiert + mit getrennten Debug-Symbolen** (erschwert Reverse-Engineering der Client-Compliance-/Berechtigungslogik):

```bash
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols   # Android
flutter build ipa       --release --obfuscate --split-debug-info=build/symbols   # iOS
```

Symbole für lesbares Crash-Mapping aufheben, **nicht** committen (`build/symbols/` ist gitignored). Android-Signierung über `android/key.properties` (Upload-Keystore, nicht im Repo) mit Debug-Fallback.

## Blaze-Voraussetzungen je Feature

Manche Features brauchen Blaze-Bausteine, bevor sie live gehen:

- **Push**: sendende Functions + APNs-Key.
- **OktoPOS**: Outbound HTTP + Secret Manager + Scheduler.
- **Passwortmanager**: Cloud KMS-Key + IAM + `@google-cloud/kms`.

> [!NOTE]
> „Spark bis zum Schluss" heißt nur **Deploy-Timing** – bis Go-Live wird gegen Emulatoren entwickelt. Gebaut wird immer auf Blaze-Basis.

## Icons

Launcher-Icons neu erzeugen: `dart run flutter_launcher_icons`.

## Weiter

- [Cloud Functions](article:dev-cloud-functions)
- [Konfiguration, dart-defines & Feature-Flags](article:dev-konfiguration-flags)
- [Kritische Kopplungen](article:dev-kritische-kopplungen)
