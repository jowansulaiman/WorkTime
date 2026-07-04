import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/employee_qualification.dart';
import '../../../providers/personal_provider.dart';
import '../../../ui/ui.dart';

/// Qualifikationen-Tab der Mitarbeiter-Detailseite — **AllTec-1:1**
/// (`employee_qualifications_tab`): Liste mit Zähler-Kopf und „Qualifikation
/// hinzufügen", je Eintrag Bearbeiten/Löschen; Dialog mit Bezeichnung*/Art/
/// Beschreibung/Zertifikat-Nr./Ausstellende Stelle/Erworben am/Gültig bis.
class EmployeeQualifikationenTab extends StatelessWidget {
  const EmployeeQualifikationenTab({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final theme = Theme.of(context);
    final quals = personal.qualificationsForUser(userId);
    final df = DateFormat('dd.MM.yyyy', 'de_DE');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${quals.length} Qualifikationen',
                style: theme.textTheme.titleMedium),
            FilledButton.icon(
              onPressed: () => _showDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Qualifikation hinzufügen'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (quals.isEmpty)
          const EmptyState(
            icon: Icons.verified_outlined,
            title: 'Keine Qualifikationen vorhanden',
            message: 'Fügen Sie Qualifikationen hinzu.',
          )
        else
          for (final q in quals)
            Card(
              child: ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: Text(q.qualificationName.isEmpty
                    ? 'Qualifikation'
                    : q.qualificationName),
                subtitle: Text(
                  [
                    if (q.qualifikationsart != null &&
                        q.qualifikationsart!.isNotEmpty)
                      q.qualifikationsart!,
                    if (q.ausstellendeStelle != null &&
                        q.ausstellendeStelle!.isNotEmpty)
                      q.ausstellendeStelle!,
                    if (q.erworbenAm != null)
                      'Erworben: ${df.format(q.erworbenAm!)}',
                    if (q.gueltigBis != null)
                      'Gültig bis: ${df.format(q.gueltigBis!)}',
                  ].join(' · '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Bearbeiten',
                      onPressed: () => _showDialog(context, existing: q),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outlined),
                      tooltip: 'Löschen',
                      onPressed: () => _confirmDelete(context, q),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _showDialog(BuildContext context,
      {EmployeeQualification? existing}) async {
    final personal = context.read<PersonalProvider>();
    final result = await showDialog<EmployeeQualification>(
      context: context,
      builder: (_) => _QualificationDialog(userId: userId, existing: existing),
    );
    if (result != null) {
      await personal.saveEmployeeQualification(result);
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, EmployeeQualification q) async {
    final personal = context.read<PersonalProvider>();
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Qualifikation löschen',
      message: '„${q.qualificationName}" wirklich löschen?',
      icon: Icons.delete_outline,
    );
    if (!ok || q.id == null) return;
    await personal.deleteEmployeeQualification(q.id!);
  }
}

class _QualificationDialog extends StatefulWidget {
  const _QualificationDialog({required this.userId, this.existing});

  final String userId;
  final EmployeeQualification? existing;

  @override
  State<_QualificationDialog> createState() => _QualificationDialogState();
}

class _QualificationDialogState extends State<_QualificationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _bezeichnung;
  late final TextEditingController _art;
  late final TextEditingController _beschreibung;
  late final TextEditingController _zertifikatNr;
  late final TextEditingController _stelle;
  DateTime? _erworbenAm;
  DateTime? _gueltigBis;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final q = widget.existing;
    _bezeichnung = TextEditingController(text: q?.qualificationName ?? '');
    _art = TextEditingController(text: q?.qualifikationsart ?? '');
    _beschreibung = TextEditingController(text: q?.beschreibung ?? '');
    _zertifikatNr = TextEditingController(text: q?.zertifikatNr ?? '');
    _stelle = TextEditingController(text: q?.ausstellendeStelle ?? '');
    _erworbenAm = q?.erworbenAm;
    _gueltigBis = q?.gueltigBis;
  }

  @override
  void dispose() {
    _bezeichnung.dispose();
    _art.dispose();
    _beschreibung.dispose();
    _zertifikatNr.dispose();
    _stelle.dispose();
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
        ? EmployeeQualification(
            orgId: '',
            userId: widget.userId,
            qualificationName: _bezeichnung.text.trim(),
            qualifikationsart: _trim(_art),
            beschreibung: _trim(_beschreibung),
            zertifikatNr: _trim(_zertifikatNr),
            ausstellendeStelle: _trim(_stelle),
            erworbenAm: _erworbenAm,
            gueltigBis: _gueltigBis,
          )
        : existing.copyWith(
            qualificationName: _bezeichnung.text.trim(),
            qualifikationsart: _trim(_art),
            clearQualifikationsart: _trim(_art) == null,
            beschreibung: _trim(_beschreibung),
            clearBeschreibung: _trim(_beschreibung) == null,
            zertifikatNr: _trim(_zertifikatNr),
            clearZertifikatNr: _trim(_zertifikatNr) == null,
            ausstellendeStelle: _trim(_stelle),
            clearAusstellendeStelle: _trim(_stelle) == null,
            erworbenAm: _erworbenAm,
            clearErworbenAm: _erworbenAm == null,
            gueltigBis: _gueltigBis,
            clearGueltigBis: _gueltigBis == null,
          );
    Navigator.of(context).pop(result);
  }

  Future<void> _pick({required bool gueltig}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (gueltig ? _gueltigBis : _erworbenAm) ?? DateTime.now(),
      firstDate: DateTime(1950),
      lastDate: DateTime(2100),
      locale: const Locale('de', 'DE'),
    );
    if (picked == null) return;
    setState(() {
      if (gueltig) {
        _gueltigBis = picked;
      } else {
        _erworbenAm = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy', 'de_DE');
    return AlertDialog(
      title: Text(_isEdit ? 'Qualifikation bearbeiten' : 'Neue Qualifikation'),
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
                TextFormField(
                  controller: _art,
                  decoration:
                      const InputDecoration(labelText: 'Qualifikationsart'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _beschreibung,
                  decoration: const InputDecoration(labelText: 'Beschreibung'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _zertifikatNr,
                        decoration:
                            const InputDecoration(labelText: 'Zertifikat-Nr.'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _stelle,
                        decoration: const InputDecoration(
                            labelText: 'Ausstellende Stelle'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Erworben am'),
                  subtitle:
                      Text(_erworbenAm != null ? df.format(_erworbenAm!) : '—'),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () => _pick(gueltig: false),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gültig bis'),
                  subtitle:
                      Text(_gueltigBis != null ? df.format(_gueltigBis!) : '—'),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () => _pick(gueltig: true),
                  ),
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
