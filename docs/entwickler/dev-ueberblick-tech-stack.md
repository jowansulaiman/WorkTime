# Überblick & Tech-Stack

WorkTime ist eine **Flutter-App für Arbeitszeiterfassung, Schichtplanung und Ladenverwaltung** – eine Codebasis für Android, iOS und Web. Backend ist Firebase (Auth, Firestore, Cloud Functions). Die App ist **mandantenfähig**: jede Organisation ist strikt getrennt.

## Eckdaten

- **Package**: `worktime_app` (`pubspec.yaml`), Dart `>=3.7.0 <4.0.0`, reines `flutter` (kein fvm).
- **State-Management**: `provider`. Charts: `fl_chart`. PDF: `pdf` + `printing`. Routing: `go_router`.
- **Backend**: Firebase Auth, Cloud Firestore, Cloud Functions (Node 20, Region `europe-west3`).
- Zielumgebung ist **Blaze** (Cloud Functions, Admin SDK, Secret Manager, Scheduler, Outbound HTTP).

## Drei Namen, kein Bug

- `MaterialApp.title` = **timework**
- Projekt/Ordner = **WorkTime**
- Default-Org-Name = **Worktime**

Das ist gewollt und historisch gewachsen – kein Fehler.

## Deutsch-only

Alle UI- und Fehlertexte sind **Deutsch**. Die Locale ist hart auf `de_DE` (der `ThemeProvider` löscht eine gespeicherte `locale`). Es gibt **keine i18n / ARB / gen-l10n**. Konsequenzen für neuen Code:

- Neue Strings sind deutsche Literale.
- Jedes `DateFormat` MUSS explizit `'de_DE'` übergeben.

## Verzeichnis-Map

```
lib/core/        Config, Parser-Helfer, Demo-Daten, pure Engines (z. B. Auto-Schichtverteilung)
lib/models/      Datenklassen, dual serialisiert (kein codegen)
lib/services/    Datenzugriff/Seiteneffekte: Firestore, lokale Persistenz, Compliance, Auth, PDF/CSV
lib/providers/   State (ChangeNotifier)
lib/screens/     UI (home_screen.dart ist die Shell, riesig)
lib/widgets/     wiederverwendbare Widgets
lib/ui/          Design-System V2 (Signal-Teal) + Tokens
lib/theme/       Theme
lib/routing/     go_router, Shell-Tabs, Berechtigungen
functions/       Cloud Functions (plain JS, Node 20, kein Build-Step)
test/            flach, Fakes statt Firebase
```

## Wo weiterlesen

- Start der App: [Bootstrap & main.dart](article:dev-bootstrap-main)
- State: [Provider-Kette & State-Management](article:dev-provider-kette)
- Der wichtigste Footgun: [Die Zwei-Serialisierungs-Regel](article:dev-zwei-serialisierung)
- Die verbindlichen Kopplungen: [Kritische Kopplungen](article:dev-kritische-kopplungen)

> [!IMPORTANT]
> Die verbindliche Kurzreferenz des Projekts ist `CLAUDE.md` im Repo-Root. Diese Doku ist die ausführliche, lesbare Ergänzung dazu – bei Widersprüchen gilt der Code, dann `CLAUDE.md`.
