# Sicherheit & Mandantentrennung

WorkTime ist mandantenfähig: Organisationen sind strikt getrennt. Die Trennung wird an **zwei** Stellen erzwungen, die synchron bleiben müssen.

## sameOrg an zwei Stellen

- `firestore.rules`: die `sameOrg`-Funktion prüft, dass Leser/Schreiber zur Org des Dokuments gehören.
- Functions: `assertSameOrg` prüft dasselbe serverseitig.

> [!WARNING]
> Ändern Sie die Org-Isolationslogik in einem, ziehen Sie das andere mit. Ein Auseinanderlaufen ist ein Datenleck. (CLAUDE.md, Kopplung #4/#8.)

## Der validierte Pfad

> [!IMPORTANT]
> `firestore.rules` erlauben **direkte** Client-Writes auf shifts/workEntries und rufen die Functions **nicht** auf. Direkte Writes umgehen also die Compliance-Validierung. Der **Callable-Pfad ist der validierte Pfad** – bewusst eine „Sicherheitslücke per Design", um Offline-/Fallback-Fähigkeit zu erhalten.

## Rollen & Berechtigungen

- Client: Permission-Getter in `lib/models/app_user.dart` (`isAdmin`, `canManageShifts`, `canViewInventory`, …) gaten **UI und Provider-Mutatoren**; URL-Gating in `RoutePermissions`.
- Server: `firestore.rules` spiegeln dieselben `canManage*`-Regeln (`normalizeRole` mappt z. B. `teamleiter`→`teamlead` in beiden Welten).

## Secrets nie im Client

> [!WARNING]
> API-Keys/Secrets liegen **nie im Client** – ausgehende HTTP-Calls (z. B. OktoPOS, `X-API-KEY`) laufen ausschließlich über Functions mit **Secret Manager**. Pull-Writes nutzen das Admin SDK (umgeht Rules) mit `source:'oktopos'`.

## Weitere Härtung

- **Obfuskierte Release-Builds** mit getrennten Debug-Symbolen (`--obfuscate --split-debug-info`) erschweren Reverse-Engineering der Client-Compliance-/Berechtigungslogik. Symbole nicht committen (`build/symbols/` ist gitignored).
- **App Check** (`firebase_app_check`) schützt den öffentlichen Schreibpfad (`/wunsch`), aktiv nur mit gesetztem reCAPTCHA-Key.
- `lib/core/screen_security.dart` für sensible Bildschirme.

## Fachautorität

Die Sicherheits-Skills unter `claude-skills/sicherheit/` (API-Sicherheit, Software-Sicherheit) sind die verbindliche Fachautorität für diesen Bereich.

## Weiter

- [Cloud Functions](article:dev-cloud-functions)
- [Firestore-Datenmodell](article:dev-datenmodell-firestore)
- [Passwortmanager (Envelope/KMS)](article:dev-passwortmanager-technik)
