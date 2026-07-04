import 'package:flutter/material.dart';

/// Vereinheitlichter Bestaetigungsdialog (Signal-Teal-Redesign). Ersetzt die
/// verstreuten inline-`showDialog(AlertDialog)`-Bloecke fuer Loesch-/Bestaetigen-
/// Aktionen.
///
/// [show] liefert `true` nur bei aktiver Bestaetigung, sonst `false` (auch bei
/// Wegtippen) — entspricht dem bisherigen `confirmed == true`-Muster, sodass die
/// nachgelagerte Provider-Methode unveraendert gerufen wird. Aufrufer, deren
/// Tests/Flows einen exakten Button-Text matchen (z. B. `Löschen`), uebergeben
/// ihn explizit via [confirmLabel].
abstract final class AppConfirmDialog {
  AppConfirmDialog._();

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Löschen',
    String cancelLabel = 'Abbrechen',
    bool destructive = true,
    IconData? icon,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: icon != null ? Icon(icon) : null,
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(cancelLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: colorScheme.error,
                      foregroundColor: colorScheme.onError,
                    )
                  : null,
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }
}
