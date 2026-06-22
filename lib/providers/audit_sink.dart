import '../models/audit_log_entry.dart';

/// Signatur zum Anhängen eines Eintrags ins Änderungsprotokoll (Audit-Trail).
///
/// **Best-effort, fire-and-forget** – darf die eigentliche Mutation nie
/// blockieren oder werfen. Die [AuditProvider]-Instanz, die diese Senke
/// bereitstellt, füllt Akteur (uid/Name) und Zeitstempel selbst; Provider-
/// Mutatoren übergeben nur die fachlichen Felder. So wird **jede** Änderung
/// zentral protokolliert – egal von welchem Bildschirm oder Mitarbeiter sie
/// ausgelöst wird (Lesen bleibt admin-only, siehe `firestore.rules`).
typedef AuditSink = void Function({
  required AuditAction action,
  required String entityType,
  String? entityId,
  required String summary,
});
