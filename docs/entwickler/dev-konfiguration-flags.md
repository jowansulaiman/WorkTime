# Konfiguration, dart-defines & Feature-Flags

Die **gesamte Laufzeitkonfig** kommt über **dart-defines** – es gibt **kein `.env`, keine flutterfire-Datei, keine committete Firebase-Config**. Zentral gebündelt in `AppConfig` (`lib/core/app_config.dart`).

## Das dart-define-Inventar (Auszug)

| Key | Default | Wirkung |
| --- | --- | --- |
| `APP_DISABLE_AUTH` | `false` | Offline-Demo-Modus ohne Firebase. **Im Release verboten** → `validateEnvironment()` wirft `StateError`. |
| `APP_DEFAULT_ORG_ID` | `main-org` | `defaultOrganizationId` |
| `APP_DEFAULT_ORG_NAME` | `Worktime` | Name des lazy angelegten Org-Docs |
| `APP_BOOTSTRAP_ADMIN_EMAILS` | `''` | CSV; selbst-provisionierende Admins (nur Dev) |
| `APP_LEGAL_*` | `''` | Impressum/Datenschutz-Stammdaten (`LegalInfo`) |
| `APP_PUSH_ENABLED` | `false` | Schaltet mobile Push frei (kein Secret) |
| `APP_OKTOPOS_ENABLED` | `false` | OktoPOS-UI-Schalter |
| `APP_PASSWORD_MANAGER_ENABLED` | `false` | Passwortmanager-UI |
| `FIREBASE_FUNCTIONS_REGION` | `europe-west3` | **muss** `const REGION` in `functions/index.js` entsprechen |
| `FIREBASE_{ANDROID,IOS,WEB}_*` | – | Creds in `lib/firebase_options.dart` |

Platzhalter `REPLACE_ME`/`YOUR_VALUE_HERE`/leer gelten als „unset" → Firebase still deaktiviert.

## Dev-Start

```bash
flutter run --dart-define=APP_DISABLE_AUTH=true
```

Ein nacktes `flutter run` ohne dart-defines verbindet sich mit **nichts Nutzbarem**. Demo-Logins: Passwort überall `demo1234` (`admin@demo.local` usw.).

## AppConfig lesen

Konfig **immer über `AppConfig`** lesen (z. B. `AppConfig.disableAuthentication`, `AppConfig.passwordManagerEnabled`, `AppConfig.bootstrapAdminEmailList`, `AppConfig.oktoposEnabled`). `validateEnvironment()` läuft ganz früh in `main()`.

## Runtime-Feature-Flags

`FeatureFlagProvider` lädt/schreibt **zwei** Config-Singletons aus Firestore: `config/appFlags` (Feature-Flags, Force-Update-Schwellen) und `config/orgSettings` (org-weite operative Einstellungen). `RedesignFlags` (`lib/core/redesign_flags.dart`) steuert den V1/V2-Design-Read.

> [!WARNING]
> Ändert man `FIREBASE_FUNCTIONS_REGION`, muss `const REGION` in `functions/index.js` mitgezogen werden – sonst schlagen Callables fehl (`not-found`/`unavailable`) und triggern still den direkten Fallback (umgeht Compliance).

## Weiter

- [Bootstrap & main.dart](article:dev-bootstrap-main)
- [Cloud Functions](article:dev-cloud-functions)
- [Deployment & Release](article:dev-deployment-release)
