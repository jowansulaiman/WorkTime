import 'package:flutter/material.dart';

import '../core/money.dart';
import '../models/third_party_cash.dart';
import '../theme/theme_extensions.dart';

/// Ergebnis einer Kassenzählung aus dem [CashCountSheet].
class CashCountInput {
  const CashCountInput({
    required this.countedCents,
    this.note,
    this.thirdParty = const [],
  });

  final int countedCents;
  final String? note;

  /// Erfasste Dritte-Hand-/Fremdgeld-Beträge (§8.7) — getrennt von der Kasse.
  final List<ThirdPartyAmount> thirdParty;
}

/// Öffnet das Kassenzähl-Sheet (Kassen-Modul M3, §7.2/§7.3).
///
/// [expectedCents] `!= null` blendet Soll/Differenz **live** ein (Leitung, die
/// den rechnerischen Sollbestand sehen darf); `null` = **blinde Zählung**
/// (Mitarbeitende/Kiosk) — kein Soll, kein „Hinzählen".
///
/// [thirdPartyTypes] (Dritte-Hand-/Fremdgeld-Modul §8.5): die an dieser Filiale
/// angebotenen Fremdgeld-Arten. Leer = keine Fremdgeld-Sektion (Prozess wie
/// bisher). Fremdgeld wird **immer** rein als Ist-Betrag erfasst (kein Soll,
/// auch nicht für die Leitung — v1 Minimal-Variante).
Future<CashCountInput?> showCashCountSheet(
  BuildContext context, {
  int? expectedCents,
  String title = 'Kasse zählen',
  String? subtitle,
  List<ThirdPartyCashType> thirdPartyTypes = const [],
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
      thirdPartyTypes: thirdPartyTypes,
    ),
  );
}

/// Formular für eine Kassenzählung: ein großes Betragsfeld, optional Notiz und
/// — wenn die Filiale Fremdgeld-Arten hat — eine optisch klar getrennte
/// Sektion „Dritte Hand / Fremdgelder" plus Zusammenfassung vor dem Abschluss.
class CashCountSheet extends StatefulWidget {
  const CashCountSheet({
    super.key,
    this.expectedCents,
    this.title = 'Kasse zählen',
    this.subtitle,
    this.thirdPartyTypes = const [],
  });

  final int? expectedCents;
  final String title;
  final String? subtitle;
  final List<ThirdPartyCashType> thirdPartyTypes;

  @override
  State<CashCountSheet> createState() => _CashCountSheetState();
}

class _CashCountSheetState extends State<CashCountSheet> {
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  int? _countedCents;

  /// Betrags-Controller je Fremdgeld-Art (nach sortOrder).
  late final List<ThirdPartyCashType> _types;
  final Map<String, TextEditingController> _tpCtrls = {};

  /// Pflicht-Arten, deren 0-Betrag der Nutzer bewusst quittiert hat.
  final Set<String> _confirmedZero = {};

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_recompute);
    _types = [...widget.thirdPartyTypes]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (final t in _types) {
      final ctrl = TextEditingController();
      ctrl.addListener(() => setState(() {}));
      _tpCtrls[t.id] = ctrl;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    for (final c in _tpCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _recompute() {
    final parsed = Money.parseCents(_amountCtrl.text);
    // Ein negativer Bargeldbestand ist fachlich unsinnig; 0 (leere Kasse) bleibt
    // gültig.
    setState(
        () => _countedCents = (parsed != null && parsed >= 0) ? parsed : null);
  }

  /// Betrag einer Fremdgeld-Art in Cent (0 bei leer/ungültig/negativ).
  int _tpAmount(String typeId) {
    final parsed = Money.parseCents(_tpCtrls[typeId]?.text ?? '');
    return (parsed != null && parsed >= 0) ? parsed : 0;
  }

  int get _thirdPartyTotal =>
      _types.fold(0, (acc, t) => acc + _tpAmount(t.id));

  /// Eine Pflicht-Art ist offen, wenn ihr Betrag 0 ist und der Nutzer die 0
  /// noch nicht quittiert hat.
  bool _requiredOpen(ThirdPartyCashType t) =>
      t.required && _tpAmount(t.id) == 0 && !_confirmedZero.contains(t.id);

  bool get _canSubmit =>
      _countedCents != null && !_types.any(_requiredOpen);

  void _submit() {
    final counted = _countedCents;
    if (counted == null || !_canSubmit) return;
    final note = _noteCtrl.text.trim();
    final thirdParty = <ThirdPartyAmount>[
      for (final t in _types)
        ThirdPartyAmount(
          typeId: t.id,
          typeName: t.name,
          amountCents: _tpAmount(t.id),
        ),
    ];
    Navigator.of(context).pop(
      CashCountInput(
        countedCents: counted,
        note: note.isEmpty ? null : note,
        thirdParty: thirdParty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expected = widget.expectedCents;
    final counted = _countedCents;
    final diff =
        (expected != null && counted != null) ? counted - expected : null;
    final hasThirdParty = _types.isNotEmpty;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
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
                  child:
                      Text(widget.title, style: theme.textTheme.headlineSmall),
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
            if (hasThirdParty)
              Text('Eigene Kasse',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (hasThirdParty) const SizedBox(height: 8),
            TextField(
              controller: _amountCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
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
            if (hasThirdParty) ...[
              const SizedBox(height: 20),
              _ThirdPartySection(
                types: _types,
                controllers: _tpCtrls,
                confirmedZero: _confirmedZero,
                requiredOpen: _requiredOpen,
                onConfirmZero: (id, value) => setState(() {
                  if (value) {
                    _confirmedZero.add(id);
                  } else {
                    _confirmedZero.remove(id);
                  }
                }),
              ),
              const SizedBox(height: 20),
              _SummarySection(
                countedCents: counted,
                types: _types,
                amountOf: _tpAmount,
                thirdPartyTotal: _thirdPartyTotal,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _canSubmit ? _submit : null,
              icon: const Icon(Icons.check),
              label: const Text('Zählung speichern'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Optisch klar abgesetzte Sektion für Fremdgeld/Treuhand-Beträge.
class _ThirdPartySection extends StatelessWidget {
  const _ThirdPartySection({
    required this.types,
    required this.controllers,
    required this.confirmedZero,
    required this.requiredOpen,
    required this.onConfirmZero,
  });

  final List<ThirdPartyCashType> types;
  final Map<String, TextEditingController> controllers;
  final Set<String> confirmedZero;
  final bool Function(ThirdPartyCashType) requiredOpen;
  final void Function(String id, bool value) onConfirmZero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.appColors.infoContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.handshake_outlined,
                  color: theme.appColors.onInfoContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Dritte Hand / Fremdgelder',
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.appColors.onInfoContainer,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Getrennt von der Kasse — Geld gehört Dritten.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.appColors.onInfoContainer),
          ),
          const SizedBox(height: 12),
          for (final t in types) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.required ? '${t.name} *' : t.name,
                        style: theme.textTheme.bodyLarge,
                      ),
                      if (t.hint != null && t.hint!.trim().isNotEmpty)
                        Text(
                          t.hint!.trim(),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 130,
                  child: TextField(
                    key: Key('tp_amount_${t.id}'),
                    controller: controllers[t.id],
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    textAlign: TextAlign.end,
                    decoration: const InputDecoration(
                      hintText: '0,00',
                      suffixText: '€',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            if (requiredOpen(t))
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 18, color: theme.appColors.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Pflichtbetrag — 0,00 € bewusst bestätigen?',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Checkbox(
                      key: Key('tp_confirm_${t.id}'),
                      value: confirmedZero.contains(t.id),
                      onChanged: (v) => onConfirmZero(t.id, v ?? false),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

/// Zusammenfassung vor dem Abschluss: Kasse + jede Fremdgeld-Art + Gesamt.
class _SummarySection extends StatelessWidget {
  const _SummarySection({
    required this.countedCents,
    required this.types,
    required this.amountOf,
    required this.thirdPartyTotal,
  });

  final int? countedCents;
  final List<ThirdPartyCashType> types;
  final int Function(String typeId) amountOf;
  final int thirdPartyTotal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counted = countedCents ?? 0;
    final grandTotal = counted + thirdPartyTotal;
    Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: bold
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.bodyMedium),
              Text(value,
                  style: (bold
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(
                          fontWeight: bold ? FontWeight.w700 : null)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Zusammenfassung',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          row('Kasse (eigen)', Money.formatCents(counted)),
          for (final t in types)
            row(t.name, Money.formatCents(amountOf(t.id))),
          const Divider(height: 16),
          row('Geld in der Lade gesamt', Money.formatCents(grandTotal),
              bold: true),
        ],
      ),
    );
  }
}

class _SollDifferenzZeile extends StatelessWidget {
  const _SollDifferenzZeile(
      {required this.expectedCents, required this.diffCents});

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
