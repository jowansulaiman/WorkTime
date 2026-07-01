import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import 'kiosk_pin_service.dart';

/// Bottom-Sheet, in dem ein Mitarbeiter auf dem **eigenen Handy** seine
/// Kiosk-PIN setzt/ändert (Arbeitsmodus/Laden-Tablet). Offline über den lokalen
/// Dev-Speicher, im echten Betrieb server-geprüft (`setKioskPin`).
Future<void> showKioskPinSetupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _KioskPinSetupSheet(),
  );
}

class _KioskPinSetupSheet extends StatefulWidget {
  const _KioskPinSetupSheet();

  @override
  State<_KioskPinSetupSheet> createState() => _KioskPinSetupSheetState();
}

class _KioskPinSetupSheetState extends State<_KioskPinSetupSheet> {
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _pin.text.trim();
    final confirm = _confirm.text.trim();
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      setState(() => _error = 'Die PIN muss aus 4 bis 8 Ziffern bestehen.');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'Die PINs stimmen nicht überein.');
      return;
    }
    final uid = context.read<AuthProvider>().profile?.uid;
    if (uid == null) {
      setState(() => _error = 'Kein angemeldeter Nutzer.');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await KioskPinService.resolve().setPin(uid, pin);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kiosk-PIN gespeichert.')),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Speichern fehlgeschlagen: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Kiosk-PIN festlegen', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Mit dieser 4- bis 8-stelligen PIN meldest du dich am Laden-Tablet '
            '(Arbeitsmodus) an — z. B. zum Stempeln oder Aufgaben abhaken.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Neue PIN',
              prefixIcon: Icon(Icons.password),
            ),
          ),
          TextField(
            controller: _confirm,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'PIN wiederholen',
              prefixIcon: Icon(Icons.password),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('PIN speichern'),
          ),
        ],
      ),
    );
  }
}
