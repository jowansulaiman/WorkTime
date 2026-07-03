import 'package:flutter/material.dart';

import '../core/money.dart';
import '../theme/theme_extensions.dart';

/// Ergebnis einer Kassenzählung aus dem [CashCountSheet].
class CashCountInput {
  const CashCountInput({required this.countedCents, this.note});

  final int countedCents;
  final String? note;
}

/// Öffnet das Kassenzähl-Sheet (Kassen-Modul M3, §7.2/§7.3).
///
/// [expectedCents] `!= null` blendet Soll/Differenz **live** ein (Leitung, die
/// den rechnerischen Sollbestand sehen darf); `null` = **blinde Zählung**
/// (Mitarbeitende/Kiosk) — kein Soll, kein „Hinzählen".
Future<CashCountInput?> showCashCountSheet(
  BuildContext context, {
  int? expectedCents,
  String title = 'Kasse zählen',
  String? subtitle,
}) {
  return showModalBottomSheet<CashCountInput>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => CashCountSheet(
      expectedCents: expectedCents,
      title: title,
      subtitle: subtitle,
    ),
  );
}

/// Formular für eine Kassenzählung: ein großes Betragsfeld, optional Notiz.
/// Bei bekanntem Soll wird die Differenz sofort mitgerechnet.
class CashCountSheet extends StatefulWidget {
  const CashCountSheet({
    super.key,
    this.expectedCents,
    this.title = 'Kasse zählen',
    this.subtitle,
  });

  final int? expectedCents;
  final String title;
  final String? subtitle;

  @override
  State<CashCountSheet> createState() => _CashCountSheetState();
}

class _CashCountSheetState extends State<CashCountSheet> {
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  int? _countedCents;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_recompute);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _recompute() {
    final parsed = Money.parseCents(_amountCtrl.text);
    // Ein negativer Bargeldbestand ist fachlich unsinnig; 0 (leere Kasse) bleibt
    // gültig.
    setState(() => _countedCents = (parsed != null && parsed >= 0) ? parsed : null);
  }

  void _submit() {
    final counted = _countedCents;
    if (counted == null) return;
    final note = _noteCtrl.text.trim();
    Navigator.of(context).pop(
      CashCountInput(countedCents: counted, note: note.isEmpty ? null : note),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expected = widget.expectedCents;
    final counted = _countedCents;
    final diff = (expected != null && counted != null) ? counted - expected : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.point_of_sale_outlined,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.title, style: theme.textTheme.headlineSmall),
              ),
            ],
          ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.subtitle!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _amountCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              labelText: 'Gezählter Bargeldbestand',
              suffixText: '€',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(
              labelText: 'Notiz (optional)',
              hintText: 'z. B. Wechselgeld eingelegt',
              border: OutlineInputBorder(),
            ),
          ),
          if (expected != null) ...[
            const SizedBox(height: 20),
            _SollDifferenzZeile(expectedCents: expected, diffCents: diff),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: counted == null ? null : _submit,
            icon: const Icon(Icons.check),
            label: const Text('Zählung speichern'),
          ),
        ],
      ),
    );
  }
}

class _SollDifferenzZeile extends StatelessWidget {
  const _SollDifferenzZeile({required this.expectedCents, required this.diffCents});

  final int expectedCents;
  final int? diffCents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diff = diffCents;
    final (color, label) = switch (diff) {
      null => (theme.colorScheme.onSurfaceVariant, '—'),
      0 => (theme.appColors.success, 'stimmt'),
      _ when diff > 0 => (
          theme.appColors.warning,
          '+${Money.formatCents(diff)} (Überschuss)'
        ),
      _ => (theme.colorScheme.error, '${Money.formatCents(diff)} (Fehlbetrag)'),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Soll (rechnerisch)', style: theme.textTheme.bodyMedium),
              Text(Money.formatCents(expectedCents),
                  style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Differenz', style: theme.textTheme.titleMedium),
              Text(
                label,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
