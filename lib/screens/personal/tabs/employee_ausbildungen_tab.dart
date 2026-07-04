import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/employee_ausbildung.dart';
import '../../../providers/personal_provider.dart';
import '../../../ui/ui.dart';

/// Ausbildungen-Tab der Mitarbeiter-Detailseite — **AllTec-1:1**
/// (`employee_trainings_tab`): Liste mit Zähler-Kopf, Status-Badge je Eintrag
/// und „Ausbildung hinzufügen"; Dialog mit Bezeichnung*/Art/Stätte/Fachrichtung/
/// Abschluss/Status/Beginn/Ende/Anmerkungen.
class EmployeeAusbildungenTab extends StatelessWidget {
  const EmployeeAusbildungenTab({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final theme = Theme.of(context);
    final items = personal.ausbildungenForUser(userId);
    final df = DateFormat('dd.MM.yyyy', 'de_DE');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${items.length} Ausbildungen',
                style: theme.textTheme.titleMedium),
            FilledButton.icon(
              onPressed: () => _showDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ausbildung hinzufügen'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          const EmptyState(
            icon: Icons.school_outlined,
            title: 'Keine Ausbildungen vorhanden',
            message: 'Fügen Sie Ausbildungen hinzu.',
          )
        else
          for (final t in items)
            Card(
              child: ListTile(
                leading: const Icon(Icons.school_outlined),
                title:
                    Text(t.bezeichnung.isEmpty ? 'Ausbildung' : t.bezeichnung),
                subtitle: Text(
                  [
                    if (t.ausbildungsart != null &&
                        t.ausbildungsart!.isNotEmpty)
                      t.ausbildungsart!,
                    if (t.ausbildungsstaette != null &&
                        t.ausbildungsstaette!.isNotEmpty)
                      t.ausbildungsstaette!,
                    if (t.fachrichtung != null && t.fachrichtung!.isNotEmpty)
                      t.fachrichtung!,
                    if (t.beginn != null) 'Von: ${df.format(t.beginn!)}',
                    if (t.ende != null) 'Bis: ${df.format(t.ende!)}',
                  ].join(' · '),
                ),
                isThreeLine: false,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppStatusBadge(
                      label: t.status.label,
                      tone: _statusTone(t.status),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Bearbeiten',
                      onPressed: () => _showDialog(context, existing: t),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outlined),
                      tooltip: 'Löschen',
                      onPressed: () => _confirmDelete(context, t),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  static AppStatusTone _statusTone(AusbildungStatus s) => switch (s) {
        AusbildungStatus.laufend => AppStatusTone.info,
        AusbildungStatus.abgeschlossen => AppStatusTone.success,
        AusbildungStatus.abgebrochen => AppStatusTone.error,
      };

  Future<void> _showDialog(BuildContext context,
      {EmployeeAusbildung? existing}) async {
    final personal = context.read<PersonalProvider>();
    final result = await showDialog<EmployeeAusbildung>(
      context: context,
      builder: (_) => _AusbildungDialog(userId: userId, existing: existing),
    );
    if (result != null) {
      await personal.saveEmployeeAusbildung(result);
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, EmployeeAusbildung t) async {
    final personal = context.read<PersonalProvider>();
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Ausbildung löschen',
      message: '„${t.bezeichnung}" wirklich löschen?',
      icon: Icons.delete_outline,
    );
    if (!ok || t.id == null) return;
    await personal.deleteEmployeeAusbildung(t.id!);
  }
}

class _AusbildungDialog extends StatefulWidget {
  const _AusbildungDialog({required this.userId, this.existing});

  final String userId;
  final EmployeeAusbildung? existing;

  @override
  State<_AusbildungDialog> createState() => _AusbildungDialogState();
}

class _AusbildungDialogState extends State<_AusbildungDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _bezeichnung;
  late final TextEditingController _art;
  late final TextEditingController _staette;
  late final TextEditingController _fachrichtung;
  late final TextEditingController _abschluss;
  late final TextEditingController _anmerkungen;
  late AusbildungStatus _status;
  DateTime? _beginn;
  DateTime? _ende;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _bezeichnung = TextEditingController(text: t?.bezeichnung ?? '');
    _art = TextEditingController(text: t?.ausbildungsart ?? '');
    _staette = TextEditingController(text: t?.ausbildungsstaette ?? '');
    _fachrichtung = TextEditingController(text: t?.fachrichtung ?? '');
    _abschluss = TextEditingController(text: t?.abschluss ?? '');
    _anmerkungen = TextEditingController(text: t?.bemerkung ?? '');
    _status = t?.status ?? AusbildungStatus.laufend;
    _beginn = t?.beginn;
    _ende = t?.ende;
  }

  @override
  void dispose() {
    _bezeichnung.dispose();
    _art.dispose();
    _staette.dispose();
    _fachrichtung.dispose();
    _abschluss.dispose();
    _anmerkungen.dispose();
    super.dispose();
  }

  String? _trim(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.existing;
    final result = existing == null
        ? EmployeeAusbildung(
            orgId: '',
            userId: widget.userId,
            bezeichnung: _bezeichnung.text.trim(),
            ausbildungsart: _trim(_art),
            ausbildungsstaette: _trim(_staette),
            fachrichtung: _trim(_fachrichtung),
            abschluss: _trim(_abschluss),
            bemerkung: _trim(_anmerkungen),
            status: _status,
            beginn: _beginn,
            ende: _ende,
          )
        : existing.copyWith(
            bezeichnung: _bezeichnung.text.trim(),
            ausbildungsart: _trim(_art),
            clearAusbildungsart: _trim(_art) == null,
            ausbildungsstaette: _trim(_staette),
            clearAusbildungsstaette: _trim(_staette) == null,
            fachrichtung: _trim(_fachrichtung),
            clearFachrichtung: _trim(_fachrichtung) == null,
            abschluss: _trim(_abschluss),
            clearAbschluss: _trim(_abschluss) == null,
            bemerkung: _trim(_anmerkungen),
            clearBemerkung: _trim(_anmerkungen) == null,
            status: _status,
            beginn: _beginn,
            clearBeginn: _beginn == null,
            ende: _ende,
            clearEnde: _ende == null,
          );
    Navigator.of(context).pop(result);
  }

  Future<void> _pick({required bool ende}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (ende ? _ende : _beginn) ?? DateTime.now(),
      firstDate: DateTime(1950),
      lastDate: DateTime(2100),
      locale: const Locale('de', 'DE'),
    );
    if (picked == null) return;
    setState(() {
      if (ende) {
        _ende = picked;
      } else {
        _beginn = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy', 'de_DE');
    return AlertDialog(
      title: Text(_isEdit ? 'Ausbildung bearbeiten' : 'Neue Ausbildung'),
      content: SizedBox(
        width: math.min(480, MediaQuery.sizeOf(context).width - 64),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _bezeichnung,
                  decoration: const InputDecoration(labelText: 'Bezeichnung *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _art,
                        decoration:
                            const InputDecoration(labelText: 'Ausbildungsart'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _staette,
                        decoration: const InputDecoration(
                            labelText: 'Ausbildungsstätte'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _fachrichtung,
                        decoration:
                            const InputDecoration(labelText: 'Fachrichtung'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _abschluss,
                        decoration:
                            const InputDecoration(labelText: 'Abschluss'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AusbildungStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    for (final s in AusbildungStatus.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _status = v);
                  },
                ),
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Beginn'),
                  subtitle: Text(_beginn != null ? df.format(_beginn!) : '—'),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () => _pick(ende: false),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ende'),
                  subtitle: Text(_ende != null ? df.format(_ende!) : '—'),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () => _pick(ende: true),
                  ),
                ),
                TextFormField(
                  controller: _anmerkungen,
                  decoration: const InputDecoration(labelText: 'Anmerkungen'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _save, child: const Text('Speichern')),
      ],
    );
  }
}
