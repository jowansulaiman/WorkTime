# Änderungsprotokoll (Audit)

Das zentrale Änderungsprotokoll erfasst fachlich relevante Mutationen über **alle** Daten-Provider – via einer gemeinsamen Senke.

## Aufbau

- `AuditProvider` (`lib/providers/audit_provider.dart`) ist in der Provider-Kette absichtlich **früh** registriert (vor allen Daten-Providern), damit jeder Daten-Provider via `provider.setAuditSink(audit.log)` die Senke bezieht.
- `AuditSink` (`lib/providers/audit_sink.dart`) ist **fire-and-forget** und **wirft nie**.
- Modell: `AuditLogEntry` (`lib/models/audit_log_entry.dart`).

## Die Log-Regel

> [!IMPORTANT]
> Jeder fachliche Mutator loggt `_audit?.call(action:, entityType:, entityId:, summary:)` **NUR auf dem Erfolgs-Pfad** – in JEDEM Storage-Zweig (local-return UND hybrid-catch-Fallback), **NIE** auf rethrow-/Permission-Deny-Pfaden, **NIE** doppelt bei Delegation. Akteur/Zeitstempel füllt `AuditProvider.log` selbst. Summaries sind **deutsch**.

## Was NICHT geloggt wird

Bewusstes Rauschen wird ausgelassen: Vorlagen, persönliche Einstellungen, Warenkorb, Favoriten.

## Lesen ist admin-only

Der Audit-Trail ist über die Rules **admin-only** lesbar; Screen: `audit_log_screen.dart` (`/protokoll`).

## Bekannte Einschränkung

> [!NOTE]
> Cloud-erzeugte Stammdaten (saveSite/Team/Qualification/RuleSet/TravelTimeRule) bekommen beim Anlegen `entityId == null`, weil `FirestoreService` die Doc-ID intern via `collection.doc()` vergibt. Aktion/Summary/Akteur sind korrekt, nur die ID-Verknüpfung fehlt (harmlos; `entityId` ist nullable).

## Für neue Mutatoren

Ein neuer Mutator mit fachlicher Relevanz ergänzt `_audit?.call(...)` **im Provider** (nicht im Screen).

## Weiter

- [Provider-Kette & State-Management](article:dev-provider-kette)
- [Logging & Observability](article:dev-logging-observability)
