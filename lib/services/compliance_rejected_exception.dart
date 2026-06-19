import '../models/compliance_violation.dart';

/// Geworfen, wenn der Server (`failed-precondition`) einen Schicht- oder
/// Zeiteintrag wegen einer **blockierenden Compliance-Verletzung** ablehnt.
///
/// Trägt – anders als der bisherige nackte `StateError(message)` – die
/// strukturierten [violations] mit, sodass die UI die einzelnen Verstöße
/// anzeigen kann, statt nur eine zusammengefügte Sammelnachricht.
///
/// Erbt bewusst von [StateError]: Der Client behandelt Compliance-Blocks
/// bereits als `StateError` (siehe `WorkProvider`/`ScheduleProvider`) – eine
/// terminale, gewollte Ablehnung, KEIN transienter Infrastrukturfehler. Dadurch
/// greift im Hybrid-Modus korrekt **kein** lokaler Fallback (`on StateError`).
class ComplianceRejectedException extends StateError {
  ComplianceRejectedException(super.message, this.violations);

  final List<ComplianceViolation> violations;

  /// Parst die `error.details`-Map einer Cloud-Functions-`failed-precondition`.
  /// Server-Form: `{issues: [...]}` (Schichten) bzw. `{validations: [...]}`
  /// (Zeiteinträge); beide enthalten Objekte mit je einer `violations`-Liste,
  /// die hier flachgezogen werden. Leere Liste, wenn nichts Parsbares vorliegt.
  static List<ComplianceViolation> parseDetails(Object? details) {
    if (details is! Map) return const [];
    final groups = details['issues'] ?? details['validations'];
    if (groups is! List) return const [];
    final result = <ComplianceViolation>[];
    for (final group in groups) {
      if (group is! Map) continue;
      final violations = group['violations'];
      if (violations is! List) continue;
      for (final violation in violations) {
        if (violation is Map) {
          result.add(
            ComplianceViolation.fromMap(
              violation.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          );
        }
      }
    }
    return result;
  }
}
