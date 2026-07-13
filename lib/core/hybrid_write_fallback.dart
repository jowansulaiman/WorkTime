import 'app_logger.dart';
import 'retry.dart';

/// **Q1 — Offline-Positivliste für Hybrid-Schreibpfade.**
///
/// Der hybrid-Fallback (lokal weiterschreiben, wenn die Cloud nicht erreichbar
/// ist) darf **nur bei echten Offline-Fehlern** greifen — sonst verwandelt er
/// jeden Rules-Deny (`permission-denied`) oder fehlenden Composite-Index
/// (`failed-precondition`, sieht sonst wie „offline" aus!) still in einen
/// scheinbar erfolgreichen lokalen Write **samt Audit** und unterläuft damit
/// jede serverseitige Härtung.
///
/// **Positivliste** (via [isTransientError]): NUR `unavailable`,
/// `deadline-exceeded` und `TimeoutException` fallen lokal zurück. ALLES andere
/// (`permission-denied`/`unauthenticated`, `failed-precondition`,
/// `invalid-argument`, `resource-exhausted`, `unknown`, …) scheitert sichtbar
/// (rethrow, KEIN lokaler Write, KEIN Audit).
///
/// Kopplungs-Regel (CLAUDE.md): **Neuer Hybrid-Mutator → dieses Mixin/Muster
/// verwenden + Deny-Test „permission-denied → Fehler sichtbar, kein lokaler
/// Write".**
mixin HybridWriteFallback {
  /// Ob der Provider gerade im hybrid-Modus (Cloud + lokaler Spiegel) läuft.
  bool get usesHybridStorage;

  /// Log-Präfix des Providers (z. B. `Finance`/`Personal`/`Inventory`).
  String get hybridFallbackLabel;

  /// Führt einen Cloud-Write [action] aus.
  ///
  /// - Erfolg → `true` (im autoritativen Speicher gelandet).
  /// - Fehler + **kein** Hybrid → rethrow (cloud-only scheitert sichtbar).
  /// - Fehler + Hybrid + **echter Offline-Fehler** ([isTransientError]) →
  ///   lokaler Fallback, `false`.
  /// - Fehler + Hybrid + **anderer Fehler** (Rules-Deny, fehlender Index, …) →
  ///   rethrow (sichtbar, KEIN stiller lokaler Write).
  Future<bool> tryFirestoreWrite(
    String label,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      return true;
    } catch (error) {
      if (usesHybridStorage && isTransientError(error)) {
        AppLogger.warning(
          '$hybridFallbackLabel: $label offline – lokaler Fallback aktiv',
          error: error,
        );
        return false;
      }
      // Nicht-transient (permission-denied/failed-precondition/…) ODER
      // cloud-only → sichtbar scheitern, damit die Härtung nicht unterlaufen wird.
      rethrow;
    }
  }
}
