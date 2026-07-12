import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/work_template.dart';
import '../../providers/work_provider.dart';
import '../../widgets/breadcrumb_app_bar.dart';

/// Unterseite „Stempeluhr & Vorlagen" des Einstellungs-Hubs: Auto-Pause der
/// Stempeluhr und die persönlichen Arbeitszeit-Vorlagen.
class SettingsTimeclockScreen extends StatefulWidget {
  const SettingsTimeclockScreen({super.key});

  @override
  State<SettingsTimeclockScreen> createState() =>
      _SettingsTimeclockScreenState();
}

class _SettingsTimeclockScreenState extends State<SettingsTimeclockScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _autoBreakCtrl;
  bool _saving = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _autoBreakCtrl = TextEditingController(
      text: context
          .read<WorkProvider>()
          .settings
          .autoBreakAfterMinutes
          .toString(),
    );
    _initialized = true;
  }

  @override
  void dispose() {
    _autoBreakCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkProvider>();
    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: 'Einstellungen',
            onTap: () => Navigator.of(context).pop(),
          ),
          const BreadcrumbItem(label: 'Stempeluhr & Vorlagen'),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _sectionTitle(context, 'Stempeluhr'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextFormField(
                        controller: _autoBreakCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Auto-Pause nach (Minuten)',
                          prefixIcon: Icon(Icons.coffee),
                          suffixText: 'min',
                          helperText:
                              'Stempeluhr fuegt 30 min Pause hinzu, wenn '
                              'die Arbeitszeit diesen Wert ueberschreitet. '
                              '0 = deaktiviert.',
                        ),
                        validator: (value) {
                          final parsed = int.tryParse(value ?? '');
                          if (parsed == null || parsed < 0) {
                            return 'Ungueltiger Wert';
                          }
                          return null;
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Wird gespeichert...' : 'Speichern'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _sectionTitle(context, 'Arbeitszeit-Vorlagen'),
                      TextButton.icon(
                        onPressed: () => _openTemplateEditor(),
                        icon: const Icon(Icons.add),
                        label: const Text('Neu'),
                      ),
                    ],
                  ),
                  _TemplateListCard(
                    templates: work.templates,
                    onCreate: () => _openTemplateEditor(),
                    onEdit: _openTemplateEditor,
                    onDelete: _deleteTemplate,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);

    // Nur die Auto-Pause ändern; übrige (Personal-)Felder unverändert
    // mitschreiben (Rules-Pin PA-0.3 `settingsPayrollFieldsUnchanged`).
    final work = context.read<WorkProvider>();
    final updated = work.settings.copyWith(
      autoBreakAfterMinutes: int.tryParse(_autoBreakCtrl.text) ?? 360,
    );

    try {
      await work.updateSettings(updated);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Einstellungen gespeichert'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler beim Speichern: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _openTemplateEditor([WorkTemplate? template]) async {
    final provider = context.read<WorkProvider>();
    final result = await showModalBottomSheet<WorkTemplate>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _TemplateEditorSheet(template: template),
      ),
    );

    if (result == null) {
      return;
    }

    if (template == null) {
      await provider.addTemplate(result);
    } else {
      await provider.updateTemplate(result);
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          template == null ? 'Vorlage gespeichert' : 'Vorlage aktualisiert',
        ),
      ),
    );
  }

  Future<void> _deleteTemplate(WorkTemplate template) async {
    if (template.id == null) {
      return;
    }
    final provider = context.read<WorkProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Vorlage löschen?'),
        content: Text(
          'Die Vorlage "${template.name}" wird unwiderruflich geloescht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await provider.deleteTemplate(template.id!);
  }
}

class _TemplateListCard extends StatelessWidget {
  const _TemplateListCard({
    required this.templates,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
  });

  final List<WorkTemplate> templates;
  final VoidCallback onCreate;
  final ValueChanged<WorkTemplate> onEdit;
  final ValueChanged<WorkTemplate> onDelete;

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Noch keine Vorlagen vorhanden',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Lege Standardzeiten wie Fruehdienst oder Buerotag an und uebernimm sie spaeter im Eintragsformular.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Vorlage anlegen'),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          for (var i = 0; i < templates.length; i++) ...[
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              title: Text(templates[i].name),
              subtitle: Text(
                _formatTemplateSummary(context, templates[i]),
                maxLines: templates[i].note != null ? 3 : 2,
                overflow: TextOverflow.ellipsis,
              ),
              isThreeLine: templates[i].note != null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Bearbeiten',
                    onPressed: () => onEdit(templates[i]),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Löschen',
                    onPressed: () => onDelete(templates[i]),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
            if (i < templates.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _TemplateEditorSheet extends StatefulWidget {
  const _TemplateEditorSheet({this.template});

  final WorkTemplate? template;

  @override
  State<_TemplateEditorSheet> createState() => _TemplateEditorSheetState();
}

class _TemplateEditorSheetState extends State<_TemplateEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _breakCtrl;
  late final TextEditingController _noteCtrl;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    _nameCtrl = TextEditingController(text: template?.name ?? '');
    _breakCtrl = TextEditingController(
      text:
          template == null ? '30' : _formatBreakMinutes(template.breakMinutes),
    );
    _noteCtrl = TextEditingController(text: template?.note ?? '');
    _startTime = template == null
        ? const TimeOfDay(hour: 8, minute: 0)
        : _timeOfDayFromMinutes(template.startMinutes);
    _endTime = template == null
        ? const TimeOfDay(hour: 17, minute: 0)
        : _timeOfDayFromMinutes(template.endMinutes);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _breakCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.template != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isEdit ? 'Vorlage bearbeiten' : 'Neue Vorlage',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name der Vorlage',
                prefixIcon: Icon(Icons.bookmark_outline),
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Bitte Namen eingeben';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.login),
                    title: const Text('Beginn'),
                    trailing: Text(_formatTime(context, _startTime)),
                    onTap: _pickStart,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Ende'),
                    trailing: Text(_formatTime(context, _endTime)),
                    onTap: _pickEnd,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _breakCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Pause in Minuten',
                prefixIcon: Icon(Icons.coffee_outlined),
                suffixText: 'min',
              ),
              validator: (value) {
                final parsed = double.tryParse(value ?? '');
                if (parsed == null || parsed < 0) {
                  return 'Ungueltiger Wert';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _noteCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notiz (optional)',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(
                isEdit ? 'Vorlage aktualisieren' : 'Vorlage speichern',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked == null) {
      return;
    }
    setState(() => _startTime = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked == null) {
      return;
    }
    setState(() => _endTime = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final startMinutes = _toMinutes(_startTime);
    final endMinutes = _toMinutes(_endTime);

    if (endMinutes <= startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Endzeit muss nach Startzeit liegen.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      WorkTemplate(
        id: widget.template?.id,
        orgId: widget.template?.orgId ?? '',
        userId: widget.template?.userId ?? '',
        name: _nameCtrl.text,
        startMinutes: startMinutes,
        endMinutes: endMinutes,
        breakMinutes: double.tryParse(_breakCtrl.text) ?? 0,
        note: _noteCtrl.text,
      ),
    );
  }
}

String _formatTemplateSummary(BuildContext context, WorkTemplate template) {
  final timeRange =
      '${_formatTime(context, _timeOfDayFromMinutes(template.startMinutes))} - '
      '${_formatTime(context, _timeOfDayFromMinutes(template.endMinutes))}';
  final breakText = 'Pause: ${_formatBreakMinutes(template.breakMinutes)} min';
  final noteText = template.note == null ? '' : '\n${template.note}';
  return '$timeRange · $breakText$noteText';
}

String _formatTime(BuildContext context, TimeOfDay time) {
  return MaterialLocalizations.of(context).formatTimeOfDay(
    time,
    alwaysUse24HourFormat: true,
  );
}

String _formatBreakMinutes(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(1);
}

TimeOfDay _timeOfDayFromMinutes(int minutes) {
  return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
}

int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;
