import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/store_task.dart';
import '../../models/work_task.dart' show TaskPriority;
import '../../providers/store_task_provider.dart';

/// Leiter-Editor zum Anlegen/Bearbeiten eines Laden-To-Dos ([StoreTask]).
///
/// Wird vom Kiosk-Board (und später vom Admin-Bereich) als Bottom-Sheet
/// geöffnet. Bei [existing] == null wird eine neue Aufgabe angelegt, die fest an
/// [siteId] (den Laden des Tablets) gebunden ist; mit Schalter „für alle Läden"
/// kann sie org-weit (Broadcast) gemacht werden.
Future<void> showStoreTaskEditorSheet(
  BuildContext context, {
  StoreTask? existing,
  String? siteId,
  String? siteName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _StoreTaskEditorSheet(
      existing: existing,
      siteId: siteId,
      siteName: siteName,
    ),
  );
}

class _StoreTaskEditorSheet extends StatefulWidget {
  const _StoreTaskEditorSheet({this.existing, this.siteId, this.siteName});

  final StoreTask? existing;
  final String? siteId;
  final String? siteName;

  @override
  State<_StoreTaskEditorSheet> createState() => _StoreTaskEditorSheetState();
}

class _StoreTaskEditorSheetState extends State<_StoreTaskEditorSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late TaskPriority _priority =
      widget.existing?.priority ?? TaskPriority.medium;
  late DateTime? _dueDate = widget.existing?.dueDate;
  // Broadcast (für alle Läden) wenn keine siteId gesetzt ist.
  late bool _allSites = widget.existing != null
      ? widget.existing!.siteId == null
      : false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      locale: const Locale('de', 'DE'),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte einen Titel eingeben.')),
      );
      return;
    }
    setState(() => _saving = true);
    final provider = context.read<StoreTaskProvider>();
    final base = widget.existing ??
        StoreTask(orgId: '', title: title); // orgId wird im Provider gesetzt
    final task = base.copyWith(
      title: title,
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      clearDescription: _description.text.trim().isEmpty,
      priority: _priority,
      dueDate: _dueDate,
      clearDueDate: _dueDate == null,
      siteId: _allSites ? null : widget.siteId,
      clearSiteId: _allSites,
    );
    try {
      await provider.saveStoreTask(task);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final dateLabel = _dueDate == null
        ? 'Kein Fälligkeitsdatum'
        : DateFormat('EEEE, d. MMMM y', 'de_DE').format(_dueDate!);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEdit ? 'Laden-Aufgabe bearbeiten' : 'Neue Laden-Aufgabe',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: !isEdit,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Titel',
                hintText: 'z. B. Kühltheke abwischen',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Beschreibung (optional)',
              ),
            ),
            const SizedBox(height: 16),
            Text('Priorität', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<TaskPriority>(
              segments: const [
                ButtonSegment(value: TaskPriority.low, label: Text('Niedrig')),
                ButtonSegment(value: TaskPriority.medium, label: Text('Mittel')),
                ButtonSegment(value: TaskPriority.high, label: Text('Hoch')),
              ],
              selected: {_priority},
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(dateLabel),
              trailing: _dueDate == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _dueDate = null),
                    ),
              onTap: _pickDueDate,
            ),
            if (widget.siteId != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Für alle Läden'),
                subtitle: Text(
                  _allSites
                      ? 'Erscheint in jedem Laden'
                      : 'Nur für ${widget.siteName ?? 'diesen Laden'}',
                ),
                value: _allSites,
                onChanged: (v) => setState(() => _allSites = v),
              ),
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
              label: Text(isEdit ? 'Speichern' : 'Anlegen'),
            ),
          ],
        ),
      ),
    );
  }
}
