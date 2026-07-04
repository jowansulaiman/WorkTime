import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/employee_note.dart';
import '../../../providers/personal_provider.dart';
import '../../../providers/team_provider.dart';
import '../../../ui/ui.dart';

/// Notizen-Tab der Mitarbeiter-Detailseite — **AllTec-1:1** (`employee_notes_tab`):
/// Freitext-Notizen anlegen, auflisten (neueste zuerst) und löschen (kein
/// Bearbeiten). Schreibpfad [PersonalProvider.addNote]/[PersonalProvider.deleteNote]
/// (admin-only, Audit).
class EmployeeNotizenTab extends StatelessWidget {
  const EmployeeNotizenTab({super.key, required this.userId});

  final String userId;

  static final _df = DateFormat('dd.MM.yyyy HH:mm', 'de_DE');

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final team = context.watch<TeamProvider>();
    final theme = Theme.of(context);
    final notes = personal.notesForUser(userId);

    String creator(String? uid) {
      if (uid == null) return '—';
      for (final m in team.members) {
        if (m.uid == uid) return m.displayName;
      }
      return uid;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${notes.length} Notizen', style: theme.textTheme.titleMedium),
            FilledButton.icon(
              onPressed: () => _showAddDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Notiz hinzufügen'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (notes.isEmpty)
          const EmptyState(
            icon: Icons.note_outlined,
            title: 'Keine Notizen vorhanden',
            message: 'Erfasse eine Notiz zu diesem Mitarbeiter.',
          )
        else
          for (final n in notes)
            Card(
              child: ListTile(
                leading: const Icon(Icons.sticky_note_2_outlined),
                title: Text(n.text),
                subtitle: Text([
                  creator(n.createdByUid),
                  if (n.createdAt != null) _df.format(n.createdAt!),
                ].join(' · ')),
                isThreeLine: n.text.length > 40,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outlined),
                  tooltip: 'Löschen',
                  onPressed: () => _confirmDelete(context, n),
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final personal = context.read<PersonalProvider>();
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _NoteDialog(),
    );
    if (text != null && text.trim().isNotEmpty) {
      await personal.addNote(userId, text.trim());
    }
  }

  Future<void> _confirmDelete(BuildContext context, EmployeeNote note) async {
    final personal = context.read<PersonalProvider>();
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Notiz löschen',
      message: 'Diese Notiz wirklich löschen?',
      icon: Icons.delete_outline,
    );
    if (!ok || note.id == null) return;
    await personal.deleteNote(note.id!);
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog();
  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Notiz hinzufügen'),
      content: SizedBox(
        width: math.min(440, MediaQuery.sizeOf(context).width - 64),
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Notiz',
            hintText: 'Freitext …',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
