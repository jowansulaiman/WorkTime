# Logging & Observability

WorkTime unterscheidet **technisches Logging** (Diagnose) von **fachlichem Audit** (Änderungsprotokoll). Verwechseln Sie beides nicht.

## Der Client-Logger

Statt verstreuter `debugPrint`/`print` nutzen Sie die Fassade:

- `lib/core/app_logger.dart` – `AppLogger` (Log-Level, plattformgerechte Ausgabe, Compile-Out im Release).
- `lib/core/error_reporter.dart` – `ErrorReporter` für Fehler/Crashes; ein `externalSink`-Adapter erlaubt späteres Anhängen von Crashlytics/Sentry.

> [!WARNING]
> Kein `print` im Release. Produktiv gilt `warning`+. **Niemals** Secrets/PII (API-Keys, Tokens, ganze Bodies) loggen – E-Mails maskieren.

## Analytics & Performance

- `lib/core/analytics_service.dart` – der Navigations-Observer hängt am `GoRouter(observers:)` (NICHT an `MaterialApp`).
- `lib/core/performance_service.dart` – Performance-Signale.

## Server-Logging

Cloud Functions loggen strukturiert über `firebase-functions/logger` mit **requestId** (Korrelation Client→Function), passender Severity und **ohne Secrets** (der `oktoposFetch`-Wrapper redacted Header/Keys).

## Abgrenzung zum Audit

> [!IMPORTANT]
> **Technisches Logging** ist Diagnose (flüchtig, für Entwickler). **Fachliches Audit** (`AuditProvider`, siehe [Änderungsprotokoll](article:dev-audit-trail)) ist ein persistenter, admin-lesbarer Geschäftsvorgang. Ein fachlicher Vorgang gehört in den Audit-Sink, nicht in den Logger – und umgekehrt.

## Fachautorität

`claude-skills/entwicklung/20_logging.md` (Logging-Mechanik) und `14_observability.md` (Monitoring/RUM/Tracing) sind die verbindlichen Leitlinien.

## Weiter

- [Änderungsprotokoll (Audit)](article:dev-audit-trail)
- [Beitragen & Konventionen](article:dev-beitragen-konventionen)
