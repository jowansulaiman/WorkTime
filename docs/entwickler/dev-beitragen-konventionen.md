# Beitragen & Konventionen

Diese Seite fasst zusammen, wie ein Feature in diesem Repo end-to-end entsteht – und welche Regeln nicht verhandelbar sind.

## Definition of Done

Vor jedem Commit selbst ausführen (es gibt keine CI):

```bash
flutter analyze          # muss sauber sein
flutter test             # muss grün sein
flutter run --dart-define=APP_DISABLE_AUTH=true   # offline gegenchecken
```

Details: [Test-Konventionen](article:dev-testing).

## Sprache & Formatierung

> [!IMPORTANT]
> **Deutsch-only.** Neue UI-/Fehlertexte sind deutsche Literale. Jedes `DateFormat` bekommt explizit `'de_DE'`. Locale ist hart `de_DE` – keine i18n.

## Lint

Nur `package:flutter_lints/flutter.yaml` (rules leer). **Nicht ohne Auftrag erweitern.**

## Berechtigungen gaten UI und Provider

Die Permission-Getter in `lib/models/app_user.dart` (`isAdmin`, `canManageShifts`, …) gaten **sowohl UI als auch Provider-Mutatoren**. URL-Gating zentral in `RoutePermissions`. Serverseitige Spiegelung in `firestore.rules` synchron halten.

## Reuse statt Kopie

- V2-Bausteine aus `lib/ui/ui.dart` verwenden (Tokens, `AppCard`, `AppSectionCard`, `AppSearchField`, …).
- Status-Farben über `Theme.of(context).appColors`, nie hardcoden.
- File-private Reuse-Widgets ggf. nach `lib/widgets/`/`lib/ui/` heben statt kopieren.

## Der übliche Feature-Weg

1. Model(e) anlegen – **beide** Serialisierungen + `copyWith` (siehe [Zwei-Serialisierung](article:dev-zwei-serialisierung)).
2. Persistenz: Firestore-Getter in `FirestoreService`, ggf. lokale Collection in `DatabaseService`.
3. Provider (in der Kette an korrekter Stelle), Mutatoren im Drei-Modi-Muster, Audit auf Erfolgs-Pfad.
4. Rules/Indexes anpassen (+ Callable, falls shift/entry).
5. UI: Screen + Route + Permission + Einstiegspunkt.
6. Tests (Fakes, `de_DE`).
7. Die [kritischen Kopplungen](article:dev-kritische-kopplungen) durchgehen.

## Fachautorität: claude-skills

Unter `claude-skills/` liegen 23 Experten-Rollen-Prompts (auch als `.claude/skills/flutter-*`). Sie sind die **verbindliche Fachautorität** für ihren Bereich – verankern Sie Entscheidungen darin. Für Code-/PR-Review: `review/22_code-entwicklungs-review.md`; für Pläne/Outputs: `review/23_plan-output-review.md`.

## Pläne

Größere Vorhaben werden als Plan unter `plan/` versioniert abgelegt (nicht nur global). Der Memory-Index verweist auf die relevanten Pläne.

## Weiter

- [Kritische Kopplungen](article:dev-kritische-kopplungen)
- [Test-Konventionen](article:dev-testing)
- [Überblick & Tech-Stack](article:dev-ueberblick-tech-stack)
