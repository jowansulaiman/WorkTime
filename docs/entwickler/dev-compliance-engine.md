# Compliance-Engine (Client/Server-Spiegel)

`lib/services/compliance_service.dart` ist ein **bewusster, fast-exakter Spiegel** von `validateSingleShift`/`validateSingleWorkEntry` in `functions/index.js`. Beide prüfen dieselben Arbeitszeit-Regeln – einmal im Client (Preview), einmal serverseitig (verbindlich).

## Warum doppelt?

- **Client** (`ComplianceService`): sofortige Preview/Warnungen in der UI, offline-fähig.
- **Server** (Callable): die **verbindliche** Re-Validierung. Bei blockierender Verletzung → `failed-precondition`.

## Die Schwellen (müssen synchron bleiben)

- **Mindestruhezeit**: 660 min
- **Pausen**: 30 min ab 360 min, 45 min ab 540 min
- **max. geplante Zeit**: 600 min/Tag
- **Minijob-Verdienstgrenze**: (in Cent) hart, in beiden Modi
- **Nacht**: 23:00–06:00

## Die goldene Regel

> [!WARNING]
> Ändern Sie eine Compliance-Regel/Schwelle/einen Code, müssen Sie **beide** Seiten mitziehen: `compliance_service.dart` **und** `functions/index.js` – **plus** `ComplianceRuleSet.defaultRetail()` ↔ `defaultRuleSet('DE Einzelhandel Standard')`.

## Codes, nicht Messages

`ComplianceViolation` ist transient (keine Collection). Tests und Logik hängen an den **Codes**, nicht an Messages:

```dart
expect(violations.map((v) => v.code), contains('break_required'));
```

## Verbindung zur Auto-Schichtverteilung

Der `ShiftAutoAssigner` nutzt `ComplianceService.validateShift` als **harten Constraint**. Stundengrenzen (`monthlyMaxHours`/`weeklyMaxHours`) sind dagegen **Planungsschranken**, keine Compliance-Violation – siehe [Automatische Schichtverteilung](article:dev-auto-schichtverteilung).

## Weiter

- [Cloud Functions](article:dev-cloud-functions)
- [Automatische Schichtverteilung](article:dev-auto-schichtverteilung)
- [Kritische Kopplungen](article:dev-kritische-kopplungen)
