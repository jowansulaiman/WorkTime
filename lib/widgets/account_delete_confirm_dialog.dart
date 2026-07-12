import 'package:flutter/material.dart';

/// Ergebnis des [AccountDeleteConfirmDialog]: bestätigt + (bei Passwort-Konten)
/// das zur Reauth eingegebene Passwort.
class AccountDeleteConfirmResult {
  const AccountDeleteConfirmResult({required this.confirmed, this.password});

  final bool confirmed;
  final String? password;
}

/// Bestätigungs- + Reauth-Dialog vor dem endgültigen Löschen eines Kontos
/// (Plan `plan/account-loeschung.md`). Wird sowohl für die Selbst-Löschung
/// (Einstellungen → Konto & Profil) als auch für die Admin-Fremdlöschung
/// (Personalakte → Gefahrenzone) verwendet.
///
/// Bei Passwort-Konten wird das Passwort direkt hier abgefragt (Sicherheits-Gate,
/// der Aufrufer reicht es an `AuthProvider.reauthenticate` weiter); Google-/
/// Demo-Konten bestätigen nur (Reauth läuft dann als Google-Popup bzw. No-op).
class AccountDeleteConfirmDialog extends StatefulWidget {
  const AccountDeleteConfirmDialog({
    super.key,
    required this.needsPassword,
    required this.message,
    this.title = 'Konto endgültig löschen',
    this.confirmLabel = 'Endgültig löschen',
  });

  final bool needsPassword;
  final String message;
  final String title;
  final String confirmLabel;

  static Future<AccountDeleteConfirmResult?> show(
    BuildContext context, {
    required bool needsPassword,
    required String message,
    String title = 'Konto endgültig löschen',
    String confirmLabel = 'Endgültig löschen',
  }) {
    return showDialog<AccountDeleteConfirmResult>(
      context: context,
      builder: (_) => AccountDeleteConfirmDialog(
        needsPassword: needsPassword,
        message: message,
        title: title,
        confirmLabel: confirmLabel,
      ),
    );
  }

  @override
  State<AccountDeleteConfirmDialog> createState() =>
      _AccountDeleteConfirmDialogState();
}

class _AccountDeleteConfirmDialogState
    extends State<AccountDeleteConfirmDialog> {
  final _pwCtrl = TextEditingController();
  bool _error = false;

  @override
  void dispose() {
    _pwCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          if (widget.needsPassword) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _pwCtrl,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Passwort zur Bestätigung',
                prefixIcon: const Icon(Icons.lock_outline),
                errorText: _error ? 'Bitte Passwort eingeben.' : null,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            const AccountDeleteConfirmResult(confirmed: false),
          ),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }

  void _submit() {
    if (widget.needsPassword && _pwCtrl.text.isEmpty) {
      setState(() => _error = true);
      return;
    }
    Navigator.of(context).pop(
      AccountDeleteConfirmResult(
        confirmed: true,
        password: widget.needsPassword ? _pwCtrl.text : null,
      ),
    );
  }
}
