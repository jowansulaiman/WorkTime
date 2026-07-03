import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/employee_document.dart';
import '../providers/personal_provider.dart';
import '../services/download_service.dart';
import '../ui/ui.dart';

/// Dokumenten-Abschnitt der digitalen Personalakte (PA-3). Wiederverwendbar für
/// die Admin-Detailseite ([canManage] = true: hochladen/löschen) und die
/// Mitarbeiter-Selbstsicht ([canManage] = false: nur ansehen/downloaden +
/// Lesebestätigung).
class EmployeeDocumentsCard extends StatelessWidget {
  const EmployeeDocumentsCard({
    super.key,
    required this.userId,
    required this.canManage,
  });

  final String userId;
  final bool canManage;

  static const _allowedExtensions = ['pdf', 'jpg', 'jpeg', 'png'];

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final docs = personal.documentsForUser(userId);
    final available = personal.documentsAvailable;

    return AppSectionCard(
      title: 'Dokumente',
      icon: Icons.folder_outlined,
      trailing: canManage && available
          ? IconButton(
              icon: const Icon(Icons.upload_file_outlined),
              tooltip: 'Dokument hochladen',
              onPressed: () => _openUpload(context, personal),
            )
          : null,
      child: !available
          ? const _Hint(
              'Dokumente benötigen den Cloud-Modus (im lokalen/Demo-Modus '
              'nicht verfügbar).')
          : docs.isEmpty
              ? const _Hint('Keine Dokumente hinterlegt.')
              : Column(
                  children: [
                    for (final doc in docs)
                      _DocumentTile(
                        doc: doc,
                        canManage: canManage,
                        personal: personal,
                      ),
                  ],
                ),
    );
  }

  Future<void> _openUpload(
      BuildContext context, PersonalProvider personal) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      if (context.mounted) {
        _snack(context, 'Datei konnte nicht gelesen werden.', isError: true);
      }
      return;
    }
    if (bytes.length >= 15 * 1024 * 1024) {
      if (context.mounted) {
        _snack(context, 'Datei ist zu groß (max. 15 MB).', isError: true);
      }
      return;
    }
    if (!context.mounted) return;
    await showAppBottomSheet<void>(
      context: context,
      builder: (_) => _DocumentUploadSheet(
        personal: personal,
        userId: userId,
        fileName: file.name,
        bytes: bytes,
        contentType: _contentTypeFor(file.extension),
      ),
    );
  }

  static String _contentTypeFor(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }
}

class _DocumentTile extends StatefulWidget {
  const _DocumentTile({
    required this.doc,
    required this.canManage,
    required this.personal,
  });

  final EmployeeDocument doc;
  final bool canManage;
  final PersonalProvider personal;

  @override
  State<_DocumentTile> createState() => _DocumentTileState();
}

class _DocumentTileState extends State<_DocumentTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final colors = Theme.of(context).appColors;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_iconFor(doc.category)),
      title: Text(doc.title.isEmpty ? doc.fileName : doc.title),
      subtitle: Text([
        doc.category.label,
        _formatBytes(doc.sizeBytes),
        if (!doc.visibleToEmployee) 'intern',
        if (doc.acknowledged) 'bestätigt',
        if (widget.canManage && doc.retentionExpired(DateTime.now()))
          'Aufbewahrung abgelaufen',
      ].join(' · ')),
      trailing: _busy
          ? const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.canManage && !doc.acknowledged)
                  IconButton(
                    icon: Icon(Icons.check_circle_outline, color: colors.success),
                    tooltip: 'Gelesen bestätigen',
                    onPressed: _acknowledge,
                  ),
                IconButton(
                  icon: const Icon(Icons.download_outlined),
                  tooltip: 'Herunterladen',
                  onPressed: _download,
                ),
                if (widget.canManage)
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error),
                    tooltip: 'Löschen',
                    onPressed: _delete,
                  ),
              ],
            ),
    );
  }

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      final bytes = await widget.personal.downloadDocument(widget.doc);
      if (bytes == null) {
        if (mounted) _snack(context, 'Datei nicht gefunden.', isError: true);
        return;
      }
      await downloadFileBytes(
        bytes: bytes,
        fileName: widget.doc.fileName.isEmpty
            ? '${widget.doc.title}.pdf'
            : widget.doc.fileName,
        mimeType: widget.doc.contentType,
      );
    } catch (error) {
      if (mounted) {
        _snack(context, 'Download fehlgeschlagen: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acknowledge() async {
    setState(() => _busy = true);
    try {
      await widget.personal.acknowledgeDocument(widget.doc);
    } catch (error) {
      if (mounted) {
        _snack(context, 'Bestätigung fehlgeschlagen: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Dokument löschen?',
      message:
          '„${widget.doc.title}" wird endgültig aus der Personalakte entfernt.',
      confirmLabel: 'Löschen',
    );
    if (!confirmed) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await widget.personal.deleteDocument(widget.doc);
    } catch (error) {
      if (mounted) {
        _snack(context, 'Löschen fehlgeschlagen: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _DocumentUploadSheet extends StatefulWidget {
  const _DocumentUploadSheet({
    required this.personal,
    required this.userId,
    required this.fileName,
    required this.bytes,
    required this.contentType,
  });

  final PersonalProvider personal;
  final String userId;
  final String fileName;
  final List<int> bytes;
  final String contentType;

  @override
  State<_DocumentUploadSheet> createState() => _DocumentUploadSheetState();
}

class _DocumentUploadSheetState extends State<_DocumentUploadSheet> {
  late final TextEditingController _title;
  final TextEditingController _note = TextEditingController();
  DocumentCategory _category = DocumentCategory.sonstiges;
  bool _visibleToEmployee = true;
  bool _uploading = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    // Titel aus dem Dateinamen ohne Endung vorbelegen.
    final base = widget.fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    _title = TextEditingController(text: base);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return AppBottomSheetScaffold(
      title: 'Dokument hochladen',
      subtitle: widget.fileName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<DocumentCategory>(
            initialValue: _category,
            decoration: const InputDecoration(
              labelText: 'Kategorie',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: [
              for (final c in DocumentCategory.values)
                DropdownMenuItem(value: c, child: Text(c.label)),
            ],
            onChanged: _uploading
                ? null
                : (v) => setState(() => _category = v ?? _category),
          ),
          SizedBox(height: spacing.md),
          TextField(
            controller: _title,
            enabled: !_uploading,
            decoration: const InputDecoration(
              labelText: 'Titel',
              prefixIcon: Icon(Icons.title_outlined),
            ),
          ),
          SizedBox(height: spacing.md),
          TextField(
            controller: _note,
            enabled: !_uploading,
            decoration: const InputDecoration(
              labelText: 'Notiz (optional)',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          SizedBox(height: spacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Für Mitarbeiter sichtbar'),
            subtitle: const Text(
                'Aus: interne Ablage, nur für Admins sichtbar.'),
            value: _visibleToEmployee,
            onChanged: _uploading
                ? null
                : (v) => setState(() => _visibleToEmployee = v),
          ),
          SizedBox(height: spacing.md),
          if (_uploading) ...[
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            SizedBox(height: spacing.md),
          ],
          FilledButton.icon(
            onPressed: _uploading ? null : _upload,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(_uploading ? 'Wird hochgeladen…' : 'Hochladen'),
          ),
        ],
      ),
    );
  }

  Future<void> _upload() async {
    if (_title.text.trim().isEmpty) {
      _snack(context, 'Bitte einen Titel angeben.', isError: true);
      return;
    }
    setState(() {
      _uploading = true;
      _progress = 0;
    });
    try {
      await widget.personal.uploadDocument(
        userId: widget.userId,
        category: _category,
        title: _title.text,
        fileName: widget.fileName,
        contentType: widget.contentType,
        bytes: Uint8List.fromList(widget.bytes),
        visibleToEmployee: _visibleToEmployee,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) {
        Navigator.of(context).pop();
        _snack(context, 'Dokument hochgeladen.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _uploading = false);
        _snack(context, 'Upload fehlgeschlagen: $error', isError: true);
      }
    }
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.sm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

IconData _iconFor(DocumentCategory category) => switch (category) {
      DocumentCategory.arbeitsvertrag => Icons.description_outlined,
      DocumentCategory.lohnabrechnung => Icons.euro_outlined,
      DocumentCategory.bescheinigung => Icons.verified_outlined,
      DocumentCategory.krankmeldung => Icons.healing_outlined,
      DocumentCategory.zeugnis => Icons.workspace_premium_outlined,
      DocumentCategory.schulung => Icons.school_outlined,
      DocumentCategory.sonstiges => Icons.insert_drive_file_outlined,
    };

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

void _snack(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
    ),
  );
}
