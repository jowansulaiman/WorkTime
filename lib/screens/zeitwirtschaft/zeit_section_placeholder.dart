import 'package:flutter/material.dart';

import '../../ui/ui.dart';

/// Platzhalter für einen Zeitwirtschafts-Bereich, der erst in einem späteren
/// Meilenstein gebaut wird (M1 stellt das Gerüst + den Hub bereit, die einzelnen
/// Bereiche folgen in M2–M6). Klar beschriftet, damit die Navigation jetzt
/// vollständig begehbar ist, ohne Funktion vorzutäuschen.
class ZeitSectionPlaceholder extends StatelessWidget {
  const ZeitSectionPlaceholder({
    super.key,
    required this.title,
    required this.meilenstein,
    this.parentLabel = 'Zeitwirtschaft',
  });

  /// Anzeigename des Bereichs (z. B. „Kommen und Gehen").
  final String title;

  /// Meilenstein-Kennung, z. B. „M3", für den ehrlichen Hinweistext.
  final String meilenstein;

  final String parentLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: parentLabel,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          BreadcrumbItem(label: title),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(context.spacing.lg),
            child: AppEmptyState(
              icon: Icons.construction_outlined,
              message:
                  '„$title" entsteht in Meilenstein $meilenstein.\n'
                  'Das Gerüst und die Navigation stehen bereits — der Bereich '
                  'wird als Nächstes gefüllt.',
            ),
          ),
        ),
      ),
    );
  }
}
