import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/contact_csv_import.dart';
import '../core/contact_dedup.dart';
import '../models/app_user.dart';
import '../models/contact.dart';
import '../models/contact_activity.dart';
import '../models/site_definition.dart';
import '../providers/auth_provider.dart';
import '../providers/contact_provider.dart';
import '../providers/team_provider.dart';
import '../services/export_service.dart';
import '../ui/ui.dart';
import '../widgets/action_fab.dart';

/// Sentinel-Wert fuer den Standort-Filter „Allgemein" (Kontakte ohne Laden).
const String _kGeneralSite = '__general__';

/// Bereich „Kontakte": Kunden, Lieferanten, Geschaeftspartner, Behoerden, …
///
/// Wird als Haupt-Tab in der Shell eingehaengt. Lesen darf jedes aktive
/// Mitglied; Anlegen/Bearbeiten/Löschen sind Admins und Schichtleitern
/// vorbehalten ([AppUserProfile.canManageContacts]).
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({
    super.key,
    this.canNavigateBack = false,
    this.onNavigateBack,
  });

  final bool canNavigateBack;
  final VoidCallback? onNavigateBack;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  ContactType? _typeFilter;
  String? _siteFilter; // null = alle, _kGeneralSite = ohne Laden, sonst siteId
  bool _favoritesOnly = false;
  bool _showInactive = false;
  bool _exporting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile =
        context.select<AuthProvider, AppUserProfile?>((a) => a.profile);
    final canManage = profile?.canManageContacts ?? false;
    final canView = profile?.canViewContacts ?? false;

    final contactProvider = context.watch<ContactProvider>();
    final sites = context.watch<TeamProvider>().sites;
    final spacing = context.spacing;

    if (!canView) {
      return const Scaffold(
        body: Center(child: Text('Keine Berechtigung für Kontakte.')),
      );
    }

    final all = contactProvider.contacts;
    final filtered = _applyFilters(all);

    return Scaffold(
      floatingActionButton: canManage
          ? ExpandableFab(
              heroTag: 'contacts_add_fab',
              actions: [
                FabAction(
                  icon: Icons.person_add_alt_1,
                  label: 'Kontakt',
                  onPressed: () => _openEditor(),
                ),
              ],
            )
          : null,
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      spacing.md,
                      spacing.sm,
                      spacing.md,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionHeader(
                          title: 'Kontakte',
                          subtitle:
                              'Kunden, Lieferanten und Partner der beiden Läden',
                          breadcrumbs: const [BreadcrumbItem(label: 'Kontakte')],
                          onBack: widget.canNavigateBack
                              ? widget.onNavigateBack
                              : null,
                        ),
                        SizedBox(height: spacing.md),
                        _StatsRow(contacts: all),
                        SizedBox(height: spacing.md),
                        _buildSearchAndExport(filtered, sites),
                        SizedBox(height: spacing.sm),
                        _buildCategoryFilters(all),
                        SizedBox(height: spacing.xs),
                        _buildSiteAndToggleFilters(sites),
                        SizedBox(height: spacing.sm),
                        _ResultCountBar(
                          shown: filtered.length,
                          total: all.length,
                          onReset: _hasActiveFilters ? _resetFilters : null,
                        ),
                        SizedBox(height: spacing.xs),
                      ],
                    ),
                  ),
                ),
                if (contactProvider.errorMessage != null)
                  SliverToBoxAdapter(
                    child: _ContactsErrorBanner(
                      message: contactProvider.errorMessage!,
                      onDismiss: contactProvider.clearError,
                    ),
                  ),
                if (contactProvider.loading && all.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: contactProvider.errorMessage != null
                        ? const SizedBox.shrink()
                        : _buildEmptyState(all.isEmpty, canManage),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      spacing.md,
                      0,
                      spacing.md,
                      // Platz fuer den FAB.
                      spacing.xxl + spacing.xxl,
                    ),
                    sliver: SliverList.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final contact = filtered[index];
                        return Padding(
                          padding: EdgeInsets.only(bottom: spacing.sm),
                          child: _ContactCard(
                            contact: contact,
                            canManage: canManage,
                            onTap: () => _openDetail(contact),
                            onToggleFavorite: () =>
                                contactProvider.toggleFavorite(contact),
                            onEdit: () => _openEditor(contact),
                            onDelete: () => _confirmDelete(contact),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Filterleiste -------------------------------------------------------

  bool get _hasActiveFilters =>
      _searchQuery.trim().isNotEmpty ||
      _typeFilter != null ||
      _siteFilter != null ||
      _favoritesOnly ||
      _showInactive;

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _typeFilter = null;
      _siteFilter = null;
      _favoritesOnly = false;
      _showInactive = false;
    });
  }

  Widget _buildSearchAndExport(
    List<Contact> filtered,
    List<SiteDefinition> sites,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: AppFormField(
            controller: _searchController,
            hint: 'Suchen (Name, Ansprechpartner, Ort, …)',
            prefixIcon: const Icon(Icons.search),
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        SizedBox(width: context.spacing.sm),
        _ExportButton(
          enabled: filtered.isNotEmpty && !_exporting,
          busy: _exporting,
          onSelected: (asCsv) => _export(filtered, sites, asCsv: asCsv),
        ),
        IconButton(
          tooltip: 'Kontakte aus CSV importieren',
          icon: const Icon(Icons.file_upload_outlined),
          onPressed: _importCsv,
        ),
      ],
    );
  }

  Widget _buildCategoryFilters(List<Contact> all) {
    final counts = <ContactType, int>{};
    for (final contact in all) {
      counts.update(contact.type, (v) => v + 1, ifAbsent: () => 1);
    }
    final presentTypes = ContactTypeX.ordered
        .where((type) => counts.containsKey(type))
        .toList(growable: false);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          AppFilterChip(
            label: 'Alle',
            selected: _typeFilter == null,
            onSelected: (_) => setState(() => _typeFilter = null),
          ),
          for (final type in presentTypes) ...[
            SizedBox(width: context.spacing.xs),
            AppFilterChip(
              label: '${type.label} (${counts[type]})',
              icon: _typeIcon(type),
              selected: _typeFilter == type,
              onSelected: (_) => setState(
                () => _typeFilter = _typeFilter == type ? null : type,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSiteAndToggleFilters(List<SiteDefinition> sites) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (sites.isNotEmpty) ...[
            AppFilterChip(
              label: 'Alle Standorte',
              icon: Icons.place_outlined,
              selected: _siteFilter == null,
              onSelected: (_) => setState(() => _siteFilter = null),
            ),
            SizedBox(width: context.spacing.xs),
            AppFilterChip(
              label: 'Allgemein',
              selected: _siteFilter == _kGeneralSite,
              onSelected: (_) => setState(
                () => _siteFilter =
                    _siteFilter == _kGeneralSite ? null : _kGeneralSite,
              ),
            ),
            for (final site in sites) ...[
              SizedBox(width: context.spacing.xs),
              AppFilterChip(
                label: site.name,
                selected: _siteFilter == site.id,
                onSelected: (_) => setState(
                  () => _siteFilter = _siteFilter == site.id ? null : site.id,
                ),
              ),
            ],
            SizedBox(width: context.spacing.md),
          ],
          AppFilterChip(
            label: 'Wichtig',
            icon: Icons.star_outline,
            selected: _favoritesOnly,
            onSelected: (value) => setState(() => _favoritesOnly = value),
          ),
          SizedBox(width: context.spacing.xs),
          AppFilterChip(
            label: 'Archivierte zeigen',
            icon: Icons.inventory_2_outlined,
            selected: _showInactive,
            onSelected: (value) => setState(() => _showInactive = value),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool noContactsAtAll, bool canManage) {
    if (noContactsAtAll) {
      return AppEmptyState(
        icon: Icons.contacts_outlined,
        title: 'Noch keine Kontakte',
        message: canManage
            ? 'Lege über den Button „Kontakt" den ersten Eintrag an.'
            : 'Es wurden noch keine Kontakte hinterlegt.',
        action: canManage
            ? FilledButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Ersten Kontakt anlegen'),
              )
            : null,
      );
    }
    return AppEmptyState(
      icon: Icons.search_off,
      title: 'Keine Treffer',
      message: 'Für die aktuelle Filterauswahl gibt es keine Kontakte.',
      action: TextButton.icon(
        onPressed: _resetFilters,
        icon: const Icon(Icons.filter_alt_off_outlined),
        label: const Text('Filter zurücksetzen'),
      ),
    );
  }

  // --- Filter-Logik -------------------------------------------------------

  List<Contact> _applyFilters(List<Contact> all) {
    final query = _searchQuery.trim().toLowerCase();
    final result = all.where((contact) {
      if (!_showInactive && !contact.isActive) {
        return false;
      }
      if (_favoritesOnly && !contact.isFavorite) {
        return false;
      }
      if (_typeFilter != null && contact.type != _typeFilter) {
        return false;
      }
      if (_siteFilter != null) {
        final hasSite = contact.siteId != null && contact.siteId!.isNotEmpty;
        if (_siteFilter == _kGeneralSite) {
          if (hasSite) return false;
        } else if (contact.siteId != _siteFilter) {
          return false;
        }
      }
      if (query.isNotEmpty) {
        final haystack = [
          contact.name,
          contact.contactPerson ?? '',
          contact.email ?? '',
          contact.phone ?? '',
          contact.mobile ?? '',
          contact.city ?? '',
          contact.customerNumber ?? '',
          contact.tags.join(' '),
        ].join(' ').toLowerCase();
        if (!haystack.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();

    result.sort((a, b) {
      if (a.isFavorite != b.isFavorite) {
        return a.isFavorite ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  String _filterLabel(List<SiteDefinition> sites) {
    final parts = <String>[];
    if (_typeFilter != null) {
      parts.add(_typeFilter!.label);
    }
    if (_siteFilter == _kGeneralSite) {
      parts.add('Allgemein');
    } else if (_siteFilter != null) {
      final site = sites.where((s) => s.id == _siteFilter).toList();
      parts.add(site.isEmpty ? 'Standort' : site.first.name);
    }
    if (_favoritesOnly) {
      parts.add('Nur wichtige');
    }
    if (_searchQuery.trim().isNotEmpty) {
      parts.add('Suche: ${_searchQuery.trim()}');
    }
    return parts.isEmpty ? 'Alle Kontakte' : parts.join(' · ');
  }

  // --- Aktionen -----------------------------------------------------------

  Future<void> _export(
    List<Contact> contacts,
    List<SiteDefinition> sites, {
    required bool asCsv,
  }) async {
    if (contacts.isEmpty) {
      return;
    }
    setState(() => _exporting = true);
    final label = _filterLabel(sites);
    try {
      if (asCsv) {
        await ExportService.exportContactsCsv(
          contacts: contacts,
          filterLabel: label,
        );
      } else {
        await ExportService.exportContactsPdf(
          contacts: contacts,
          filterLabel: label,
        );
      }
      _snack(asCsv
          ? 'Kontakte als CSV exportiert.'
          : 'Kontakte als PDF exportiert.');
    } catch (error) {
      _snack('Export fehlgeschlagen: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _importCsv() async {
    final profile = context.read<AuthProvider>().profile;
    if (profile == null || !profile.canManageContacts) {
      _snack('Keine Berechtigung zum Importieren.', isError: true);
      return;
    }
    final controller = TextEditingController();
    final start = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kontakte aus CSV importieren'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CSV-Inhalt einfügen (deutsches Excel, mit „;" getrennt). '
                'Erste Zeile = Spaltennamen, z.B. '
                'Name;Kategorie;E-Mail;Telefon;PLZ;Ort.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 5,
                maxLines: 12,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Name;Kategorie;E-Mail;Telefon\n…',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Einlesen'),
          ),
        ],
      ),
    );
    if (start != true || !mounted) {
      return;
    }
    final result =
        ContactCsvImport.parse(controller.text, orgId: profile.orgId);
    if (!result.hasContacts) {
      _snack(
        'Keine Kontakte gefunden. '
        '${result.errors.isNotEmpty ? result.errors.first : ''}',
        isError: true,
      );
      return;
    }
    final proceed = await AppConfirmDialog.show(
      context,
      title: 'Importieren?',
      message: '${result.contacts.length} Kontakt(e) werden importiert'
          '${result.errors.isNotEmpty ? ', ${result.errors.length} Zeile(n) übersprungen' : ''}.',
      icon: Icons.file_upload_outlined,
      confirmLabel: 'Importieren',
      destructive: false,
    );
    if (!proceed || !mounted) {
      return;
    }
    try {
      final count =
          await context.read<ContactProvider>().importContacts(result.contacts);
      _snack('$count Kontakt(e) importiert.');
    } catch (error) {
      _snack('Import fehlgeschlagen: $error', isError: true);
    }
  }

  Future<void> _openDetail(Contact contact) async {
    final canManage =
        context.read<AuthProvider>().profile?.canManageContacts ?? false;
    final action = await showAppBottomSheet<_DetailAction>(
      context: context,
      builder: (_) => _ContactDetailSheet(
        contact: contact,
        canManage: canManage,
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _DetailAction.edit:
        await _openEditor(contact);
      case _DetailAction.delete:
        await _confirmDelete(contact);
      case _DetailAction.toggleFavorite:
        await context.read<ContactProvider>().toggleFavorite(contact);
      case _DetailAction.addActivity:
        await _addActivity(contact);
    }
  }

  Future<void> _addActivity(Contact contact) async {
    var type = ContactActivityType.note;
    var occurredAt = DateTime.now();
    final noteController = TextEditingController();
    final result = await showDialog<ContactActivity>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Aktivität erfassen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<ContactActivityType>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Art'),
                items: [
                  for (final t in ContactActivityType.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => type = value);
                },
              ),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Datum'),
                subtitle: Text(
                  '${occurredAt.day.toString().padLeft(2, '0')}.'
                  '${occurredAt.month.toString().padLeft(2, '0')}.'
                  '${occurredAt.year}',
                ),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: occurredAt,
                    firstDate: DateTime(occurredAt.year - 5),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => occurredAt = DateTime(
                          picked.year,
                          picked.month,
                          picked.day,
                          occurredAt.hour,
                          occurredAt.minute,
                        ));
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notiz',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                ContactActivity(
                  type: type,
                  occurredAt: occurredAt,
                  note: noteController.text.trim().isEmpty
                      ? null
                      : noteController.text.trim(),
                ),
              ),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    try {
      await context.read<ContactProvider>().addContactActivity(contact, result);
      _snack('Aktivität erfasst.');
    } catch (error) {
      _snack('Speichern fehlgeschlagen: $error', isError: true);
    }
  }

  Future<void> _openEditor([Contact? contact]) async {
    final sites = context.read<TeamProvider>().sites;
    final orgId = context.read<AuthProvider>().profile?.orgId ?? '';
    final result = await showAppBottomSheet<Contact>(
      context: context,
      builder: (_) => _ContactEditorSheet(
        contact: contact,
        sites: sites,
        orgId: orgId,
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    // Dubletten-Hinweis nur beim Neuanlegen (in-memory, keine extra Reads).
    if (contact == null) {
      final dups = ContactDedup.findDuplicates(
        result,
        context.read<ContactProvider>().contacts,
      );
      if (dups.isNotEmpty) {
        final proceed = await AppConfirmDialog.show(
          context,
          title: 'Möglicherweise doppelt',
          message: 'Es gibt bereits einen ähnlichen Kontakt: '
              '„${dups.first.contact.name}". Trotzdem neu anlegen?',
          icon: Icons.people_alt_outlined,
          confirmLabel: 'Trotzdem anlegen',
          destructive: false,
        );
        if (!proceed || !mounted) {
          return;
        }
      }
    }
    try {
      await context.read<ContactProvider>().saveContact(result);
      _snack(contact == null
          ? 'Kontakt „${result.name}" angelegt.'
          : 'Kontakt „${result.name}" aktualisiert.');
    } catch (error) {
      _snack('Speichern fehlgeschlagen: $error', isError: true);
    }
  }

  Future<void> _confirmDelete(Contact contact) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Kontakt löschen?',
      message: '„${contact.name}" wird unwiderruflich gelöscht.',
      icon: Icons.delete_outline,
    );
    if (!confirmed || !mounted || contact.id == null) {
      return;
    }
    try {
      // Audit-Logging erfolgt zentral in ContactProvider.deleteContact.
      await context.read<ContactProvider>().deleteContact(contact.id!);
      _snack('Kontakt gelöscht.');
    } catch (error) {
      _snack('Löschen fehlgeschlagen: $error', isError: true);
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }
}

enum _DetailAction { edit, delete, toggleFavorite, addActivity }

// --- Statistik-Zeile ------------------------------------------------------

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.contacts});

  final List<Contact> contacts;

  @override
  Widget build(BuildContext context) {
    final active = contacts.where((c) => c.isActive).length;
    final customers = contacts.where((c) => c.type == ContactType.customer).length;
    final suppliers = contacts
        .where((c) =>
            c.type == ContactType.supplier || c.type == ContactType.wholesaler)
        .length;
    final spacing = context.spacing;
    return Row(
      children: [
        Expanded(
          child: AppMetricCard(
            label: 'Aktiv',
            value: '$active',
            icon: Icons.contacts_outlined,
          ),
        ),
        SizedBox(width: spacing.sm),
        Expanded(
          child: AppMetricCard(
            label: 'Kunden',
            value: '$customers',
            icon: Icons.person_outline,
          ),
        ),
        SizedBox(width: spacing.sm),
        Expanded(
          child: AppMetricCard(
            label: 'Lieferanten',
            value: '$suppliers',
            icon: Icons.local_shipping_outlined,
          ),
        ),
      ],
    );
  }
}

class _ResultCountBar extends StatelessWidget {
  const _ResultCountBar({
    required this.shown,
    required this.total,
    this.onReset,
  });

  final int shown;
  final int total;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          shown == total
              ? '$total Kontakte'
              : '$shown von $total Kontakten',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        if (onReset != null)
          TextButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
            label: const Text('Filter zurücksetzen'),
          ),
      ],
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.enabled,
    required this.busy,
    required this.onSelected,
  });

  final bool enabled;
  final bool busy;
  final ValueChanged<bool> onSelected; // true = CSV, false = PDF

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return PopupMenuButton<bool>(
      enabled: enabled,
      tooltip: 'Exportieren',
      icon: const Icon(Icons.ios_share),
      onSelected: onSelected,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: false,
          child: ListTile(
            leading: Icon(Icons.picture_as_pdf_outlined),
            title: Text('Als PDF exportieren'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: true,
          child: ListTile(
            leading: Icon(Icons.table_view_outlined),
            title: Text('Als CSV exportieren'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

// --- Kontakt-Karte --------------------------------------------------------

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.contact,
    required this.canManage,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onEdit,
    required this.onDelete,
  });

  final Contact contact;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    final subtitle = _subtitle();
    // Standortnamen live aus der siteId auflösen (H-C2); persistierter
    // contact.siteName nur als Fallback (gelöschter Standort / Offline).
    final siteLabel = context
        .watch<TeamProvider>()
        .siteNameById(contact.siteId, fallback: contact.siteName);

    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.all(spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(contact: contact),
          SizedBox(width: spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        contact.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: contact.isActive
                              ? null
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (contact.isFavorite)
                      Icon(Icons.star_rounded,
                          size: context.iconSizes.sm,
                          color: theme.appColors.warning),
                  ],
                ),
                SizedBox(height: spacing.xs),
                Wrap(
                  spacing: spacing.xs,
                  runSpacing: spacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppStatusBadge(
                      label: contact.type.shortLabel,
                      tone: _typeTone(contact.type),
                      icon: _typeIcon(contact.type),
                    ),
                    if (!contact.isActive)
                      const AppStatusBadge(
                        label: 'Archiviert',
                        tone: AppStatusTone.neutral,
                      ),
                    if (siteLabel != null)
                      _MetaChip(
                        icon: Icons.place_outlined,
                        label: siteLabel,
                      ),
                  ],
                ),
                if (subtitle != null) ...[
                  SizedBox(height: spacing.xs),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (canManage)
            _CardMenu(
              isFavorite: contact.isFavorite,
              onToggleFavorite: onToggleFavorite,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
        ],
      ),
    );
  }

  String? _subtitle() {
    final parts = <String>[];
    if (contact.contactPerson != null) {
      parts.add(contact.contactPerson!);
    }
    final phone = contact.primaryPhone;
    if (phone != null) {
      parts.add(phone);
    }
    if (contact.email != null) {
      parts.add(contact.email!);
    }
    if (parts.isEmpty && contact.city != null) {
      parts.add(contact.city!);
    }
    return parts.isEmpty ? null : parts.join('  ·  ');
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.contact});

  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      alignment: Alignment.center,
      child: Icon(
        _typeIcon(contact.type),
        color: colorScheme.onSecondaryContainer,
        size: context.iconSizes.md,
      ),
    );
  }
}

class _CardMenu extends StatelessWidget {
  const _CardMenu({
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onEdit,
    required this.onDelete,
  });

  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Aktionen',
      onSelected: (value) {
        switch (value) {
          case 'favorite':
            onToggleFavorite();
          case 'edit':
            onEdit();
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'favorite',
          child: ListTile(
            leading: Icon(
              isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
            ),
            title: Text(isFavorite ? 'Nicht mehr wichtig' : 'Als wichtig'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Bearbeiten'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Löschen'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final spacing = context.spacing;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xxs + spacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(context.radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: context.iconSizes.sm, color: colorScheme.onSurfaceVariant),
          SizedBox(width: spacing.xxs + spacing.xxs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

// --- Detail-Sheet ---------------------------------------------------------

IconData _activityIcon(ContactActivityType type) => switch (type) {
      ContactActivityType.call => Icons.call_outlined,
      ContactActivityType.email => Icons.email_outlined,
      ContactActivityType.meeting => Icons.groups_outlined,
      ContactActivityType.task => Icons.check_circle_outline,
      ContactActivityType.note => Icons.sticky_note_2_outlined,
    };

String _formatActivityDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year} '
      '${two(date.hour)}:${two(date.minute)}';
}

class _ContactDetailSheet extends StatelessWidget {
  const _ContactDetailSheet({
    required this.contact,
    required this.canManage,
  });

  final Contact contact;
  final bool canManage;

  /// Zeigt die vollständige Kontakthistorie in einem scrollbaren Sheet
  /// (die Detailansicht selbst zeigt nur die letzten 8 Einträge).
  void _showAllActivities(BuildContext context, Contact contact) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          builder: (context, scrollController) => ListView.separated(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: contact.activities.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 20),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Text(
                  'Verlauf (${contact.activities.length})',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                );
              }
              final activity = contact.activities[index - 1];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_activityIcon(activity.type),
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${activity.type.label} · ${_formatActivityDate(activity.occurredAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (activity.note != null &&
                            activity.note!.trim().isNotEmpty)
                          Text(activity.note!),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final siteLabel = context
        .watch<TeamProvider>()
        .siteNameById(contact.siteId, fallback: contact.siteName);
    return AppBottomSheetScaffold(
      title: contact.name,
      subtitle: contact.type.label,
      actions: [
        if (contact.isFavorite)
          Icon(Icons.star_rounded, color: Theme.of(context).appColors.warning),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: spacing.xs,
            runSpacing: spacing.xs,
            children: [
              AppStatusBadge(
                label: contact.type.label,
                tone: _typeTone(contact.type),
                icon: _typeIcon(contact.type),
                filled: true,
              ),
              if (!contact.isActive)
                const AppStatusBadge(
                  label: 'Archiviert',
                  tone: AppStatusTone.neutral,
                ),
              _MetaChip(
                icon: Icons.place_outlined,
                label: siteLabel ?? 'Allgemein (beide Läden)',
              ),
              for (final tag in contact.tags)
                _MetaChip(icon: Icons.sell_outlined, label: tag),
            ],
          ),
          SizedBox(height: spacing.md),
          if (contact.contactPerson != null)
            _DetailRow(
              icon: Icons.badge_outlined,
              label: 'Ansprechpartner',
              value: contact.contactPerson!,
            ),
          if (contact.phone != null)
            _DetailRow(
              icon: Icons.call_outlined,
              label: 'Telefon',
              value: contact.phone!,
              copyable: true,
            ),
          if (contact.mobile != null)
            _DetailRow(
              icon: Icons.smartphone_outlined,
              label: 'Mobil',
              value: contact.mobile!,
              copyable: true,
            ),
          if (contact.email != null)
            _DetailRow(
              icon: Icons.mail_outline,
              label: 'E-Mail',
              value: contact.email!,
              copyable: true,
            ),
          if (contact.website != null)
            _DetailRow(
              icon: Icons.language_outlined,
              label: 'Website',
              value: contact.website!,
              copyable: true,
            ),
          if (contact.hasAddress)
            _DetailRow(
              icon: Icons.location_on_outlined,
              label: 'Adresse',
              value: contact.displayAddress,
              copyable: true,
            ),
          if (contact.taxId != null)
            _DetailRow(
              icon: Icons.receipt_long_outlined,
              label: 'USt-IdNr. / Steuernr.',
              value: contact.taxId!,
              copyable: true,
            ),
          if (contact.customerNumber != null)
            _DetailRow(
              icon: Icons.tag_outlined,
              label: 'Kunden-/Lieferantennr.',
              value: contact.customerNumber!,
            ),
          if (contact.notes != null)
            _DetailRow(
              icon: Icons.sticky_note_2_outlined,
              label: 'Notiz',
              value: contact.notes!,
            ),
          if (contact.activities.isNotEmpty) ...[
            SizedBox(height: spacing.md),
            Text(
              'Verlauf',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: spacing.xs),
            for (final activity in contact.activities.take(8))
              Padding(
                padding: EdgeInsets.symmetric(vertical: spacing.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_activityIcon(activity.type),
                        size: 18,
                        color: Theme.of(context).colorScheme.primary),
                    SizedBox(width: spacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${activity.type.label} · ${_formatActivityDate(activity.occurredAt)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                          if (activity.note != null &&
                              activity.note!.trim().isNotEmpty)
                            Text(activity.note!),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (contact.activities.length > 8)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _showAllActivities(context, contact),
                  child: Text('Alle ${contact.activities.length} anzeigen'),
                ),
              ),
          ],
          if (canManage)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(_DetailAction.addActivity),
                icon: const Icon(Icons.add_comment_outlined, size: 18),
                label: const Text('Aktivität erfassen'),
              ),
            ),
          if (canManage) ...[
            SizedBox(height: spacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(_DetailAction.delete),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Löschen'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(_DetailAction.edit),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Bearbeiten'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: context.iconSizes.md, color: colorScheme.primary),
          SizedBox(width: spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
          if (copyable)
            IconButton(
              tooltip: 'Kopieren',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.copy_outlined, size: context.iconSizes.sm),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(content: Text('„$label" kopiert.')),
                  );
              },
            ),
        ],
      ),
    );
  }
}

// --- Editor-Sheet ---------------------------------------------------------

class _ContactEditorSheet extends StatefulWidget {
  const _ContactEditorSheet({
    required this.contact,
    required this.sites,
    required this.orgId,
  });

  final Contact? contact;
  final List<SiteDefinition> sites;
  final String orgId;

  @override
  State<_ContactEditorSheet> createState() => _ContactEditorSheetState();
}

class _ContactEditorSheetState extends State<_ContactEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _contactPerson;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _mobile;
  late final TextEditingController _website;
  late final TextEditingController _street;
  late final TextEditingController _postalCode;
  late final TextEditingController _city;
  late final TextEditingController _taxId;
  late final TextEditingController _customerNumber;
  late final TextEditingController _notes;
  late final TextEditingController _tags;

  late ContactType _type;
  late String? _siteId;
  late bool _isFavorite;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    _name = TextEditingController(text: c?.name ?? '');
    _contactPerson = TextEditingController(text: c?.contactPerson ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _mobile = TextEditingController(text: c?.mobile ?? '');
    _website = TextEditingController(text: c?.website ?? '');
    _street = TextEditingController(text: c?.street ?? '');
    _postalCode = TextEditingController(text: c?.postalCode ?? '');
    _city = TextEditingController(text: c?.city ?? '');
    _taxId = TextEditingController(text: c?.taxId ?? '');
    _customerNumber = TextEditingController(text: c?.customerNumber ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
    _tags = TextEditingController(text: c?.tags.join(', ') ?? '');
    _type = c?.type ?? ContactType.customer;
    _isFavorite = c?.isFavorite ?? false;
    _isActive = c?.isActive ?? true;
    // Standort nur uebernehmen, wenn er noch existiert (sonst „Allgemein").
    final siteId = c?.siteId;
    _siteId = (siteId != null && widget.sites.any((s) => s.id == siteId))
        ? siteId
        : null;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _contactPerson,
      _email,
      _phone,
      _mobile,
      _website,
      _street,
      _postalCode,
      _city,
      _taxId,
      _customerNumber,
      _notes,
      _tags,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final isEditing = widget.contact != null;
    return AppBottomSheetScaffold(
      title: isEditing ? 'Kontakt bearbeiten' : 'Neuer Kontakt',
      subtitle: 'Kunde, Lieferant, Partner, Behörde …',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppFormField(
              controller: _name,
              label: 'Name / Firma *',
              hint: 'z. B. Nord-Tabak Großhandel GmbH',
              prefixIcon: const Icon(Icons.business_outlined),
              textCapitalization: TextCapitalization.words,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Pflichtfeld' : null,
            ),
            SizedBox(height: spacing.md),
            DropdownButtonFormField<ContactType>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Kategorie',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: [
                for (final type in ContactTypeX.ordered)
                  DropdownMenuItem(
                    value: type,
                    child: Row(
                      children: [
                        Icon(_typeIcon(type), size: 18),
                        const SizedBox(width: 10),
                        Text(type.label),
                      ],
                    ),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _type = value ?? ContactType.customer),
            ),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _contactPerson,
              label: 'Ansprechpartner',
              prefixIcon: const Icon(Icons.badge_outlined),
              textCapitalization: TextCapitalization.words,
            ),
            SizedBox(height: spacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppFormField(
                    controller: _phone,
                    label: 'Telefon',
                    prefixIcon: const Icon(Icons.call_outlined),
                    keyboardType: TextInputType.phone,
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: AppFormField(
                    controller: _mobile,
                    label: 'Mobil',
                    prefixIcon: const Icon(Icons.smartphone_outlined),
                    keyboardType: TextInputType.phone,
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _email,
              label: 'E-Mail',
              prefixIcon: const Icon(Icons.mail_outline),
              keyboardType: TextInputType.emailAddress,
            ),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _website,
              label: 'Website',
              prefixIcon: const Icon(Icons.language_outlined),
              keyboardType: TextInputType.url,
            ),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _street,
              label: 'Straße & Nr.',
              prefixIcon: const Icon(Icons.location_on_outlined),
              textCapitalization: TextCapitalization.words,
            ),
            SizedBox(height: spacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: AppFormField(
                    controller: _postalCode,
                    label: 'PLZ',
                    keyboardType: TextInputType.number,
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: AppFormField(
                    controller: _city,
                    label: 'Ort',
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppFormField(
                    controller: _taxId,
                    label: 'USt-IdNr.',
                    prefixIcon: const Icon(Icons.receipt_long_outlined),
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: AppFormField(
                    controller: _customerNumber,
                    label: 'Kunden-/Lief.-Nr.',
                    prefixIcon: const Icon(Icons.tag_outlined),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.md),
            if (widget.sites.isNotEmpty) ...[
              DropdownButtonFormField<String?>(
                initialValue: _siteId,
                decoration: const InputDecoration(
                  labelText: 'Standort',
                  prefixIcon: Icon(Icons.place_outlined),
                  helperText: 'Allgemein = gilt für beide Läden',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Allgemein (beide Läden)'),
                  ),
                  for (final site in widget.sites)
                    DropdownMenuItem<String?>(
                      value: site.id,
                      child: Text(site.name),
                    ),
                ],
                onChanged: (value) => setState(() => _siteId = value),
              ),
              SizedBox(height: spacing.md),
            ],
            AppFormField(
              controller: _tags,
              label: 'Schlagworte',
              hint: 'Komma-getrennt, z. B. Tabak, Stammlieferant',
              prefixIcon: const Icon(Icons.sell_outlined),
            ),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _notes,
              label: 'Notiz',
              prefixIcon: const Icon(Icons.sticky_note_2_outlined),
              maxLines: 3,
              minLines: 2,
            ),
            SizedBox(height: spacing.sm),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _isFavorite,
              onChanged: (value) => setState(() => _isFavorite = value),
              secondary: const Icon(Icons.star_outline_rounded),
              title: const Text('Als wichtig markieren'),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
              secondary: const Icon(Icons.check_circle_outline),
              title: const Text('Aktiv'),
              subtitle: const Text('Archivierte Kontakte sind standardmäßig ausgeblendet.'),
            ),
            SizedBox(height: spacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.check),
                label: Text(isEditing ? 'Speichern' : 'Kontakt anlegen'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final selectedSite =
        widget.sites.where((s) => s.id == _siteId).toList();
    final base = widget.contact ??
        Contact(orgId: widget.orgId, name: _name.text.trim());
    final result = base.copyWith(
      orgId: widget.orgId,
      name: _name.text.trim(),
      type: _type,
      contactPerson: _trim(_contactPerson.text),
      clearContactPerson: _trim(_contactPerson.text) == null,
      email: _trim(_email.text),
      clearEmail: _trim(_email.text) == null,
      phone: _trim(_phone.text),
      clearPhone: _trim(_phone.text) == null,
      mobile: _trim(_mobile.text),
      clearMobile: _trim(_mobile.text) == null,
      website: _trim(_website.text),
      clearWebsite: _trim(_website.text) == null,
      street: _trim(_street.text),
      clearStreet: _trim(_street.text) == null,
      postalCode: _trim(_postalCode.text),
      clearPostalCode: _trim(_postalCode.text) == null,
      city: _trim(_city.text),
      clearCity: _trim(_city.text) == null,
      taxId: _trim(_taxId.text),
      clearTaxId: _trim(_taxId.text) == null,
      customerNumber: _trim(_customerNumber.text),
      clearCustomerNumber: _trim(_customerNumber.text) == null,
      notes: _trim(_notes.text),
      clearNotes: _trim(_notes.text) == null,
      siteId: _siteId,
      siteName: selectedSite.isEmpty ? null : selectedSite.first.name,
      clearSite: _siteId == null,
      tags: _parseTags(_tags.text),
      isFavorite: _isFavorite,
      isActive: _isActive,
    );
    Navigator.of(context).pop(result);
  }

  static String? _trim(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _parseTags(String raw) {
    return raw
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }
}

// --- Typ-Darstellung ------------------------------------------------------

IconData _typeIcon(ContactType type) => switch (type) {
      ContactType.customer => Icons.person_outline,
      ContactType.supplier => Icons.local_shipping_outlined,
      ContactType.wholesaler => Icons.warehouse_outlined,
      ContactType.company => Icons.handshake_outlined,
      ContactType.serviceProvider => Icons.handyman_outlined,
      ContactType.authority => Icons.account_balance_outlined,
      ContactType.landlord => Icons.home_work_outlined,
      ContactType.bankInsurance => Icons.account_balance_wallet_outlined,
      ContactType.taxAdvisor => Icons.calculate_outlined,
      ContactType.other => Icons.contacts_outlined,
    };

AppStatusTone _typeTone(ContactType type) => switch (type) {
      ContactType.customer => AppStatusTone.primary,
      ContactType.supplier => AppStatusTone.info,
      ContactType.wholesaler => AppStatusTone.info,
      ContactType.company => AppStatusTone.secondary,
      ContactType.serviceProvider => AppStatusTone.tertiary,
      ContactType.authority => AppStatusTone.warning,
      ContactType.landlord => AppStatusTone.secondary,
      ContactType.bankInsurance => AppStatusTone.success,
      ContactType.taxAdvisor => AppStatusTone.tertiary,
      ContactType.other => AppStatusTone.neutral,
    };

/// Fehler-Banner der Kontakteliste (Stream-/Ladefehler des ContactProvider).
class _ContactsErrorBanner extends StatelessWidget {
  const _ContactsErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: colorScheme.onErrorContainer),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
