import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/employee_child.dart';
import '../../../providers/personal_provider.dart';
import '../../../ui/ui.dart';

/// Kinder-Tab der Mitarbeiter-Detailseite — **AllTec-1:1** (`employee_children_tab`):
/// Liste aller Kinder mit Zähler-Kopf und „Kind hinzufügen", je Eintrag
/// Bearbeiten/Löschen; Formular-Dialog analog AllTec (Vorname*/Nachname/
/// Geburtstag/Anmerkungen/Kindergeldanspruch). Schreibpfad über
/// [PersonalProvider.saveEmployeeChild]/[PersonalProvider.deleteEmployeeChild].
class EmployeeKinderTab extends StatelessWidget {
  const EmployeeKinderTab({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final theme = Theme.of(context);
    final children = personal.childrenForUser(userId);
    final df = DateFormat('dd.MM.yyyy', 'de_DE');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${children.length} Kinder', style: theme.textTheme.titleMedium),
            FilledButton.icon(
              onPressed: () => _showDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Kind hinzufügen'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (children.isEmpty)
          const EmptyState(
            icon: Icons.child_care_outlined,
            title: 'Keine Kinder hinterlegt',
            message: 'Fügen Sie Kinder hinzu.',
          )
        else
          for (final child in children)
            Card(
              child: ListTile(
                leading: const Icon(Icons.child_care_outlined),
                title: Text(child.anzeigeName),
                subtitle: Text(
                  [
                    if (child.geburtstag != null)
                      'Geb.: ${df.format(child.geburtstag!)}',
                    if (child.zaehltFuerFreibetrag) 'Kindergeldanspruch',
                    if (child.anmerkungen != null &&
                        child.anmerkungen!.isNotEmpty)
                      child.anmerkungen!,
                  ].join(' · '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Bearbeiten',
                      onPressed: () => _showDialog(context, existing: child),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outlined),
                      tooltip: 'Löschen',
                      onPressed: () => _confirmDelete(context, child),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _showDialog(BuildContext context, {EmployeeChild? existing}) async {
    final personal = context.read<PersonalProvider>();
    final result = await showDialog<EmployeeChild>(
      context: context,
      builder: (_) => _ChildDialog(userId: userId, existing: existing),
    );
    if (result != null) {
      await personal.saveEmployeeChild(result);
    }
  }

  Future<void> _confirmDelete(BuildContext context, EmployeeChild child) async {
    final personal = context.read<PersonalProvider>();
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Kind löschen',
      message: '„${child.anzeigeName}" wirklich löschen?',
      icon: Icons.delete_outline,
    );
    if (!ok || child.id == null) return;
    await personal.deleteEmployeeChild(child.id!);
  }
}

/// Anlegen/Bearbeiten eines Kindes (analog AllTec `_ChildDialog`). Gibt beim
/// Speichern das (neue oder aktualisierte) [EmployeeChild] via `pop` zurück;
/// erhält beim Bearbeiten die WorkTime-Zusatzfelder (geschlecht/steuerIdKind).
class _ChildDialog extends StatefulWidget {
  const _ChildDialog({required this.userId, this.existing});

  final String userId;
  final EmployeeChild? existing;

  @override
  State<_ChildDialog> createState() => _ChildDialogState();
}

class _ChildDialogState extends State<_ChildDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _vorname;
  late final TextEditingController _nachname;
  late final TextEditingController _anmerkungen;
  DateTime? _geburtstag;
  late bool _kindergeld;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _vorname = TextEditingController(text: c?.vorname ?? '');
    _nachname = TextEditingController(text: c?.name ?? '');
    _anmerkungen = TextEditingController(text: c?.anmerkungen ?? '');
    _geburtstag = c?.geburtstag;
    _kindergeld = c?.zaehltFuerFreibetrag ?? true;
  }

  @override
  void dispose() {
    _vorname.dispose();
    _nachname.dispose();
    _anmerkungen.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final vorname = _vorname.text.trim();
    final nachname = _nachname.text.trim();
    final anmerkung = _anmerkungen.text.trim();
    final existing = widget.existing;
    final child = existing == null
        ? EmployeeChild(
            orgId: '',
            userId: widget.userId,
            vorname: vorname,
            name: nachname,
            geburtstag: _geburtstag,
            anmerkungen: anmerkung.isEmpty ? null : anmerkung,
            zaehltFuerFreibetrag: _kindergeld,
          )
        : existing.copyWith(
            vorname: vorname,
            name: nachname,
            geburtstag: _geburtstag,
            clearGeburtstag: _geburtstag == null,
            anmerkungen: anmerkung.isEmpty ? null : anmerkung,
            clearAnmerkungen: anmerkung.isEmpty,
            zaehltFuerFreibetrag: _kindergeld,
          );
    Navigator.of(context).pop(child);
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy', 'de_DE');
    return AlertDialog(
      title: Text(widget.existing != null ? 'Kind bearbeiten' : 'Kind hinzufügen'),
      content: SizedBox(
        width: math.min(400, MediaQuery.sizeOf(context).width - 64),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _vorname,
                      decoration: const InputDecoration(labelText: 'Vorname *'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Pflichtfeld'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _nachname,
                      decoration: const InputDecoration(labelText: 'Nachname'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Geburtstag'),
                subtitle: Text(_geburtstag != null ? df.format(_geburtstag!) : '—'),
                trailing: IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _geburtstag ?? DateTime.now(),
                      firstDate: DateTime(1950),
                      lastDate: DateTime.now(),
                      locale: const Locale('de', 'DE'),
                    );
                    if (picked != null) setState(() => _geburtstag = picked);
                  },
                ),
              ),
              TextFormField(
                controller: _anmerkungen,
                decoration: const InputDecoration(labelText: 'Anmerkungen'),
                maxLines: 2,
              ),
              SwitchListTile(
                title: const Text('Kindergeldanspruch'),
                value: _kindergeld,
                onChanged: (v) => setState(() => _kindergeld = v),
                contentPadding: EdgeInsets.zero,
              ),
            ],
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
