import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/employee_document.dart';
import '../models/employee_qualification.dart';
import '../providers/personal_provider.dart';
import '../services/download_service.dart';
import '../ui/ui.dart';

/// PERSONAL-6: Selbstsicht-Abschnitt „Meine Qualifikationen" der Personalakte.
///
/// Zeigt die eigenen – per Self-Read-Rules geladenen – Qualifikationen
/// ([PersonalProvider.qualificationsForUser]) mit Gültigkeits-Badge
/// (`gueltigkeitStatus` → gültig / läuft ab / abgelaufen, `appColors` über
/// [AppStatusBadge]). Ist ein Nachweis-Dokument verknüpft und für den
/// Mitarbeiter sichtbar, wird ein Download angeboten; verweist die weiche FK
/// ins Leere (Dokument gelöscht/unsichtbar), erscheint ein Hinweis.
/// Read-only – die Pflege bleibt der Verwaltung vorbehalten.
class MeineQualifikationenCard extends StatelessWidget {
  const MeineQualifikationenCard({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final now = DateTime.now();
    final quals = [...personal.qualificationsForUser(userId)]..sort(
        (a, b) => a.qualificationName
            .toLowerCase()
            .compareTo(b.qualificationName.toLowerCase()),
      );

    return AppSectionCard(
      title: 'Meine Qualifikationen',
      icon: Icons.workspace_premium_outlined,
      child: quals.isEmpty
          ? Text(
              'Es sind keine Qualifikationen hinterlegt. Wende dich für '
              'Änderungen an die Verwaltung.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            )
          : Column(
              children: [
                for (final q in quals)
                  _QualiTile(userId: userId, quali: q, now: now),
              ],
            ),
    );
  }
}

class _QualiTile extends StatefulWidget {
  const _QualiTile({
    required this.userId,
    required this.quali,
    required this.now,
  });

  final String userId;
  final EmployeeQualification quali;
  final DateTime now;

  @override
  State<_QualiTile> createState() => _QualiTileState();
}

class _QualiTileState extends State<_QualiTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final quali = widget.quali;
    final personal = context.watch<PersonalProvider>();

    // Verknüpften Nachweis unter den eigenen sichtbaren Dokumenten suchen.
    EmployeeDocument? nachweis;
    if (quali.documentId != null) {
      for (final d in personal.documentsForUser(widget.userId)) {
        if (d.id == quali.documentId) {
          nachweis = d;
          break;
        }
      }
    }
    final nachweisFehlt = quali.documentId != null && nachweis == null;

    final badge = switch (quali.gueltigkeitStatus(widget.now)) {
      QualiGueltigkeit.abgelaufen => const AppStatusBadge(
          label: 'Abgelaufen',
          tone: AppStatusTone.error,
          icon: Icons.error_outline,
        ),
      QualiGueltigkeit.laeuftAb => const AppStatusBadge(
          label: 'Läuft ab',
          tone: AppStatusTone.warning,
          icon: Icons.schedule_outlined,
        ),
      QualiGueltigkeit.gueltig => null,
    };

    final trailing = <Widget>[
      if (badge != null) badge,
      if (_busy)
        const SizedBox(
            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
      else if (nachweis != null)
        IconButton(
          icon: const Icon(Icons.download_outlined),
          tooltip: 'Nachweis herunterladen',
          onPressed: () => _download(nachweis!),
        ),
    ];

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.verified_outlined),
      title: Text(quali.qualificationName.isEmpty
          ? 'Qualifikation'
          : quali.qualificationName),
      subtitle: Text([
        quali.erwerb.label,
        if (quali.gueltigBis != null)
          'gültig bis ${_formatDate(quali.gueltigBis!)}',
        if (nachweisFehlt) 'Nachweis nicht mehr vorhanden',
      ].join(' · ')),
      trailing: trailing.isEmpty
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: trailing),
    );
  }

  Future<void> _download(EmployeeDocument doc) async {
    final messenger = ScaffoldMessenger.of(context);
    final personal = context.read<PersonalProvider>();
    setState(() => _busy = true);
    try {
      final bytes = await personal.downloadDocument(doc);
      if (bytes == null) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Datei nicht gefunden.')));
        return;
      }
      await downloadFileBytes(
        bytes: bytes,
        fileName: doc.fileName.isEmpty ? '${doc.title}.pdf' : doc.fileName,
        mimeType: doc.contentType,
      );
      // Bewusstes Öffnen/Download durch den Mitarbeiter vermerken (PERSONAL-4).
      await personal.markDocumentOpened(doc, alsoDownloaded: true);
    } catch (error) {
      messenger.showSnackBar(
          SnackBar(content: Text('Download fehlgeschlagen: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}
