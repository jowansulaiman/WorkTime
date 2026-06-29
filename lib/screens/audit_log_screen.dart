import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/audit_log_entry.dart';
import '../providers/audit_provider.dart';
import '../providers/auth_provider.dart';
import '../services/export_service.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/empty_state.dart';

/// Admin-only Viewer für das leichte Änderungsprotokoll (Audit-Trail).
///
/// Bietet Filter (Aktion, Objekttyp, Volltext), CSV-Export der gefilterten
/// Sicht und „Mehr laden" (erhöht das Cloud-Stream-Limit seitenweise).
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key, this.parentLabel = 'Personal'});

  final String parentLabel;

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  AuditAction? _actionFilter;
  String? _entityTypeFilter;
  bool _exporting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final breadcrumbs = [
      BreadcrumbItem(
        label: widget.parentLabel,
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

    final auditProvider = context.watch<AuditProvider>();
    final allEntries = auditProvider.entries;
    final entityTypes = _entityTypesOf(allEntries);
    // Filter, dessen Objekttyp nicht mehr vorkommt, automatisch zurücksetzen.
    if (_entityTypeFilter != null &&
        !entityTypes.contains(_entityTypeFilter)) {
      _entityTypeFilter = null;
    }
    final filtered = _applyFilters(allEntries);
    final dateFmt = DateFormat('dd.MM.yyyy HH:mm', 'de_DE');

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: breadcrumbs,
        actions: [
          IconButton(
            tooltip: 'Als CSV exportieren',
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            onPressed: (_exporting || filtered.isEmpty)
                ? null
                : () => _exportCsv(filtered),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            searchController: _searchController,
            onQueryChanged: (value) => setState(() => _query = value),
            actionFilter: _actionFilter,
            onActionChanged: (value) =>
                setState(() => _actionFilter = value),
            entityTypeFilter: _entityTypeFilter,
            entityTypes: entityTypes,
            onEntityTypeChanged: (value) =>
                setState(() => _entityTypeFilter = value),
          ),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(
                    icon: Icons.history_outlined,
                    message: allEntries.isEmpty
                        ? 'Noch keine protokollierten Änderungen.'
                        : 'Keine Einträge für die aktuelle Filterauswahl.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: filtered.length + (auditProvider.hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (index >= filtered.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Center(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  context.read<AuditProvider>().loadMore(),
                              icon: const Icon(Icons.expand_more),
                              label: const Text('Mehr laden'),
                            ),
                          ),
                        );
                      }
                      final entry = filtered[index];
                      final colorScheme = Theme.of(context).colorScheme;
                      return ListTile(
                        leading: Icon(_iconFor(entry.action),
                            color: colorScheme.primary),
                        title:
                            Text('${entry.action.label} · ${entry.entityType}'),
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
          ),
        ],
      ),
    );
  }

  List<String> _entityTypesOf(List<AuditLogEntry> entries) {
    final set = <String>{
      for (final e in entries)
        if (e.entityType.trim().isNotEmpty) e.entityType,
    };
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<AuditLogEntry> _applyFilters(List<AuditLogEntry> entries) {
    final query = _query.trim().toLowerCase();
    return entries.where((e) {
      if (_actionFilter != null && e.action != _actionFilter) {
        return false;
      }
      if (_entityTypeFilter != null && e.entityType != _entityTypeFilter) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return e.summary.toLowerCase().contains(query) ||
          e.entityType.toLowerCase().contains(query) ||
          (e.actorName?.toLowerCase().contains(query) ?? false) ||
          (e.entityId?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  Future<void> _exportCsv(List<AuditLogEntry> entries) async {
    setState(() => _exporting = true);
    try {
      await ExportService.exportAuditLogCsv(entries: entries);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export fehlgeschlagen: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  IconData _iconFor(AuditAction action) => switch (action) {
        AuditAction.created => Icons.add_circle_outline,
        AuditAction.updated => Icons.edit_outlined,
        AuditAction.corrected => Icons.build_outlined,
        AuditAction.deleted => Icons.delete_outline,
      };
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchController,
    required this.onQueryChanged,
    required this.actionFilter,
    required this.onActionChanged,
    required this.entityTypeFilter,
    required this.entityTypes,
    required this.onEntityTypeChanged,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final AuditAction? actionFilter;
  final ValueChanged<AuditAction?> onActionChanged;
  final String? entityTypeFilter;
  final List<String> entityTypes;
  final ValueChanged<String?> onEntityTypeChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Protokoll durchsuchen',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        searchController.clear();
                        onQueryChanged('');
                      },
                    ),
            ),
            onChanged: onQueryChanged,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<AuditAction?>(
                  initialValue: actionFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Aktion',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Alle')),
                    for (final action in AuditAction.values)
                      DropdownMenuItem(
                        value: action,
                        child: Text(action.label),
                      ),
                  ],
                  onChanged: onActionChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: entityTypeFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Objekttyp',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Alle')),
                    for (final type in entityTypes)
                      DropdownMenuItem(value: type, child: Text(type)),
                  ],
                  onChanged: onEntityTypeChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
