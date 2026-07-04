# Passwortmanager (Envelope/KMS)

Der Passwortmanager ist **Blaze/Cloud-only** und nutzt **Envelope-Verschlüsselung**. Der Client sieht nie Klartext-Secrets ohne serverseitige Freigabe.

## Envelope-Verschlüsselung

- **Cloud KMS** (HSM) wrappt einen Data Encryption Key (**DEK**).
- Der eigentliche Klartext wird mit `node:crypto` **AES-256-GCM** unter dem DEK verschlüsselt (`functions/password_crypto.js`).
- Eine **KeyWrapper-Abstraktion** entkoppelt KMS, damit die Krypto **offline testbar** bleibt (`node --test`).

## Zugriff nur über Callables

`functions/password_access.js` stellt die Callables:

- **Metadaten** kommen nur über `listPasswordEntries` (keine direkten Reads des Klartexts).
- Vor dem Entschlüsseln erzwingt der Server eine **harte Re-Authentifizierung (Reauth)**.
- Blueprint-Collection `userSecrets`.

> [!WARNING]
> Der KMS-Key (`PASSWORD_KMS_KEY`) und die Krypto liegen **serverseitig**. Der Client (`lib/providers/password_provider.dart`, `lib/models/password_entry.dart`) hält nur Metadaten und ruft die Callables.

## Rollen

- Jeder aktive Nutzer darf **eigene** (`personal`) Passwörter anlegen.
- **Zentrale** (`shared`) Passwörter verwaltet/zuweist per UI-Gate ein Admin; die echte Autorisierung (inkl. optionalem teamlead-Filialrecht per Server-Flag) setzt `upsertPasswordEntry` durch (`AppUserProfile.canManagePasswords`).

## Feature-Gate

`AppConfig.passwordManagerEnabled` (`APP_PASSWORD_MANAGER_ENABLED`, Default aus) gated die UI und die Route `/passwoerter` (`RoutePermissions`). Ohne Blaze/KMS ist das Feature inaktiv.

## Deploy-Voraussetzungen

> [!IMPORTANT]
> Extern nötig: KMS-Key + IAM, `npm i @google-cloud/kms` in `functions/`, `firebase deploy` (rules/indexes/functions), Env `PASSWORD_KMS_KEY`, App-Build mit `APP_PASSWORD_MANAGER_ENABLED=true`. Plan-Dokument: `plan/passwortmanager-und-dritthand-kasse.md`.

## Weiter

- [Sicherheit & Mandantentrennung](article:dev-sicherheit-multi-tenancy)
- [Cloud Functions](article:dev-cloud-functions)
