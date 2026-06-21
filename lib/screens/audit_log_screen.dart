import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/audit_log_entry.dart';
import '../providers/audit_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/empty_state.dart';

/// Admin-only Viewer für das leichte Änderungsprotokoll (Audit-Trail).
class AuditLogScreen extends StatelessWidget {
  const AuditLogScreen({super.key, this.parentLabel = 'Personal'});

  final String parentLabel;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final breadcrumbs = [
      BreadcrumbItem(
        label: parentLabel,
        onTap: () => Navigator.of(context).maybePop(),
      ),
      const BreadcrumbItem(label: 'Änderungsprotokoll'),
    ];
    if (profile == null || !profile.isAdmin) {
      return Scaffold(
        appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
        body: const Center(child: Text('Nur für Administratoren.')),
      );
    }
    final entries = context.watch<AuditProvider>().entries;
    final dateFmt = DateFormat('dd.MM.yyyy HH:mm', 'de_DE');
    return Scaffold(
      appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
      body: entries.isEmpty
          ? const EmptyState(
              icon: Icons.history_outlined,
              message: 'Noch keine protokollierten Änderungen.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final colorScheme = Theme.of(context).colorScheme;
                return ListTile(
                  leading: Icon(_iconFor(entry.action),
                      color: colorScheme.primary),
                  title: Text('${entry.action.label} · ${entry.entityType}'),
                  subtitle: Text(
                    [
                      entry.summary,
                      [
                        if (entry.actorName != null) entry.actorName,
                        if (entry.createdAt != null)
                          dateFmt.format(entry.createdAt!),
                      ].whereType<String>().join(' · '),
                    ].where((s) => s.isNotEmpty).join('\n'),
                  ),
                  isThreeLine: true,
                );
              },
            ),
    );
  }

  IconData _iconFor(AuditAction action) => switch (action) {
        AuditAction.created => Icons.add_circle_outline,
        AuditAction.updated => Icons.edit_outlined,
        AuditAction.deleted => Icons.delete_outline,
      };
}
