import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/contact.dart';
import '../../models/contact_activity.dart';
import '../../models/contact_details.dart';
import '../../providers/auth_provider.dart';
import '../../providers/contact_provider.dart';
import '../../providers/team_provider.dart';
import '../../ui/ui.dart';
import '../../widgets/info_row.dart';
import 'contact_avatar.dart';
import 'contact_editor_sheet.dart';
import 'contact_subobject_dialogs.dart';

/// Kontakt-Detailseite — **AllTec-1:1**: Kopf-Visitenkarte + eine scrollbare
/// TabBar mit **exakt 7 Tabs** (Icon + Text), analog `ContactDetailPage` aus
/// AllTec (Übersicht · Adressen · Kommunikation · Ansprechpartner ·
/// Einwilligungen · Bank · Notizen).
///
/// Deep-linkbar über `/kontakte/{id}`. Lesen darf **jedes aktive Mitglied**
/// ([AppUserProfile.canViewContacts]) — gated in
/// [RoutePermissions.isLocationAllowed] per `/kontakte/`-Prefix und hier im
/// In-Screen-Gate. Verwaltungs-Aktionen bleiben an
/// [AppUserProfile.canManageContacts] gebunden (Editor folgt in M5).
///
/// M4: die Tabs zeigen das volle AllTec-Datenmodell (Person/Firma-Stammdaten,
/// Mehrfach-Adressen, typisierte Kanäle gruppiert nach Kontext, Bankverbindungen).
/// Fahrplan: `plan/kontakte-alltec-1zu1.md`.
class ContactDetailScreen extends StatelessWidget {
  const ContactDetailScreen({
    super.key,
    required this.contactId,
    this.parentLabel = 'Kontakte',
  });

  /// Doc-ID des Kontakts (Path-Parameter `:id`).
  final String contactId;

  /// Rücksprung-Beschriftung im Breadcrumb (Standard: die Kontaktliste).
  final String parentLabel;

  /// Tab-Reihenfolge **exakt wie AllTec** (`contact_detail_page.dart`).
  static const List<_DetailTab> _tabs = <_DetailTab>[
    _DetailTab('Übersicht', Icons.info_outline),
    _DetailTab('Adressen', Icons.place_outlined),
    _DetailTab('Kommunikation', Icons.phone_outlined),
    _DetailTab('Ansprechpartner', Icons.people_outline),
    _DetailTab('Einwilligungen', Icons.shield_outlined),
    _DetailTab('Bank', Icons.account_balance_outlined),
    _DetailTab('Notizen', Icons.notes),
  ];

  @override
  Widget build(BuildContext context) {
    final viewer = context.watch<AuthProvider>().profile;
    final contactProvider = context.watch<ContactProvider>();
    final team = context.watch<TeamProvider>();

    final breadcrumbs = <BreadcrumbItem>[
      BreadcrumbItem(
        label: parentLabel,
        onTap: () => Navigator.of(context).maybePop(),
      ),
      const BreadcrumbItem(label: 'Kontakt'),
    ];

    // Lese-Gate (spiegelt das URL-Gate; schützt auch den imperativen Push).
    // Kontakte darf jedes aktive Mitglied ansehen (NICHT admin-only).
    if (viewer == null || !viewer.canViewContacts) {
      return Scaffold(
        appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
        body: const Center(child: Text('Keine Berechtigung für Kontakte.')),
      );
    }

    final Contact? contact = contactProvider.contactById(contactId);

    // Cold-Start / Deep-Link: Kontakte evtl. noch nicht gestreamt
    // (updateSession ist fire-and-forget) → Lade- statt Not-Found-Zustand.
    if (contact == null) {
      if (contactProvider.contacts.isEmpty) {
        return Scaffold(
          appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      return Scaffold(
        appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
        body: const EmptyState(
          icon: Icons.person_off_outlined,
          title: 'Kontakt nicht gefunden',
          message: 'Zu dieser Kennung existiert kein Kontakt in dieser '
              'Organisation.',
        ),
      );
    }

    final canManage = viewer.canManageContacts;

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: BreadcrumbAppBar(
          breadcrumbs: <BreadcrumbItem>[
            BreadcrumbItem(
              label: parentLabel,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            BreadcrumbItem(label: contact.displayName),
          ],
          actions: canManage
              ? [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Bearbeiten',
                    onPressed: () => _editContact(context, contact),
                  ),
                ]
              : null,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _ContactVCard(contact: contact, canManage: canManage),
            ),
            TabBar(
              isScrollable: true,
              tabs: [
                for (final t in _tabs) Tab(icon: Icon(t.icon), text: t.label),
              ],
            ),
            Expanded(
              child: TabBarView(
                // Reihenfolge exakt wie _tabs / AllTec.
                children: [
                  _UebersichtTab(contact: contact, team: team),
                  _AdressenTab(contact: contact, canManage: canManage),
                  _KommunikationTab(contact: contact, canManage: canManage),
                  _AnsprechpartnerTab(contact: contact, canManage: canManage),
                  _EinwilligungenTab(contact: contact, canManage: canManage),
                  _BankTab(contact: contact, canManage: canManage),
                  _NotizenTab(contact: contact),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ein Tab-Deskriptor (Beschriftung + Icon), 1:1 zu AllTecs `Tab(icon:, text:)`.
class _DetailTab {
  const _DetailTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Kompakte Visitenkarte des Kontakts: Avatar (Bild oder Initialen), Name,
/// Kontakt-Kurzzeile und eine Chip-Reihe (Person/Firma · Kategorie · Status ·
/// Blacklist/Archiviert · Favorit).
class _ContactVCard extends StatelessWidget {
  const _ContactVCard({required this.contact, required this.canManage});

  final Contact contact;
  final bool canManage;

  Future<void> _uploadAvatar(BuildContext context) async {
    final orgId = context.read<AuthProvider>().profile?.orgId ?? contact.orgId;
    final id = contact.id;
    if (id == null) return;
    try {
      final url = await ContactAvatarUploader.pickAndUpload(
        orgId: orgId,
        contactId: id,
      );
      if (url == null || !context.mounted) return;
      await _persistContact(context, contact.copyWith(avatarUrl: url));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bild-Upload fehlgeschlagen: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = contact.displayName;
    final avatarUrl = contact.avatarUrl?.trim();
    final canEditAvatar = canManage && ContactAvatarUploader.isAvailable;
    final subtitleParts = <String>[
      if (contact.position?.trim().isNotEmpty ?? false) contact.position!.trim(),
      contact.type.label,
      if (contact.customerNumber?.trim().isNotEmpty ?? false)
        'Nr. ${contact.customerNumber!.trim()}',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundImage:
                          (avatarUrl != null && avatarUrl.isNotEmpty)
                              ? NetworkImage(avatarUrl)
                              : null,
                      child: (avatarUrl == null || avatarUrl.isEmpty)
                          ? Text(_initials(name),
                              style: theme.textTheme.titleLarge)
                          : null,
                    ),
                    if (canEditAvatar)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Material(
                          color: theme.colorScheme.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => _uploadAvatar(context),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(Icons.photo_camera,
                                  size: 14,
                                  color: theme.colorScheme.onPrimary),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(name,
                                style: theme.textTheme.titleLarge,
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (contact.isFavorite) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.star,
                                size: 18, color: theme.colorScheme.tertiary),
                          ],
                        ],
                      ),
                      if (contact.legalName?.trim().isNotEmpty ?? false)
                        Text(contact.legalName!.trim(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            )),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitleParts.join(' · '),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _MetaChip(
                  icon: contact.kind == ContactKind.company
                      ? Icons.business
                      : Icons.person_outline,
                  label: contact.kind.label,
                ),
                AppStatusBadge(
                  label: contact.status.label,
                  tone: _statusTone(contact.status),
                ),
                if (contact.blacklisted)
                  const AppStatusBadge(
                    label: 'Blacklist',
                    tone: AppStatusTone.error,
                    icon: Icons.block,
                  ),
                if (!contact.isActive)
                  const AppStatusBadge(
                    label: 'Archiviert',
                    tone: AppStatusTone.neutral,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab „Übersicht": Stammdaten (Person/Firma), Geschäftsdaten, Zuordnung,
/// Kommunikation-Quickview, Hauptadresse und die erhaltene Aktivitäten-Historie.
class _UebersichtTab extends StatelessWidget {
  const _UebersichtTab({required this.contact, required this.team});

  final Contact contact;
  final TeamProvider team;

  @override
  Widget build(BuildContext context) {
    final stammRows = _stammRows(contact);
    final businessRows = _businessRows(contact);
    final channels = _effectiveChannels(contact);
    final siteLabel =
        team.siteNameById(contact.siteId, fallback: contact.siteName) ??
            'Allgemein (beide Läden)';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (stammRows.isNotEmpty) ...[
          AppSectionCard(
            title: 'Stammdaten',
            icon: Icons.badge_outlined,
            child: Column(children: stammRows),
          ),
          const SizedBox(height: 12),
        ],
        if (businessRows.isNotEmpty) ...[
          AppSectionCard(
            title: 'Geschäftsdaten',
            icon: Icons.numbers_outlined,
            child: Column(children: businessRows),
          ),
          const SizedBox(height: 12),
        ],
        AppSectionCard(
          title: 'Zuordnung',
          icon: Icons.store_outlined,
          child: InfoRow(label: 'Standort', value: siteLabel),
        ),
        if (channels.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppSectionCard(
            title: 'Kommunikation',
            icon: Icons.phone_outlined,
            child: Column(
              children: [
                for (final c in channels)
                  InfoRow(label: c.type.label, value: c.value),
              ],
            ),
          ),
        ],
        if (contact.hasAddress) ...[
          const SizedBox(height: 12),
          AppSectionCard(
            title: 'Hauptadresse',
            icon: Icons.place_outlined,
            child: InfoRow(label: 'Adresse', value: contact.displayAddress),
          ),
        ],
        const SizedBox(height: 12),
        AppSectionCard(
          title: 'Letzte Aktivitäten',
          icon: Icons.history_outlined,
          child: contact.activities.isEmpty
              ? Text(
                  'Noch keine Aktivitäten erfasst.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                )
              : Column(
                  children: [
                    for (final a in contact.activities.take(5))
                      _ActivityRow(activity: a),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Tab „Adressen": Hauptadresse (flach am Contact, über den Editor gepflegt) +
/// typisierte Zusatzadressen (eigene Dialoge, hinzufügen/bearbeiten/entfernen).
class _AdressenTab extends StatelessWidget {
  const _AdressenTab({required this.contact, required this.canManage});

  final Contact contact;
  final bool canManage;

  Future<void> _add(BuildContext context) async {
    final a = await showAddressDialog(context);
    if (a == null || !context.mounted) return;
    await _persistContact(
        context, contact.copyWith(addresses: [...contact.addresses, a]));
  }

  Future<void> _edit(BuildContext context, ContactAddress addr) async {
    final a = await showAddressDialog(context, existing: addr);
    if (a == null || !context.mounted) return;
    await _persistContact(
      context,
      contact.copyWith(
        addresses:
            contact.addresses.map((x) => x.id == addr.id ? a : x).toList(),
      ),
    );
  }

  Future<void> _remove(BuildContext context, ContactAddress addr) async {
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Adresse entfernen?',
      message: '„${addr.type.label}" wird entfernt.',
      confirmLabel: 'Entfernen',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await _persistContact(
      context,
      contact.copyWith(
        addresses: contact.addresses.where((x) => x.id != addr.id).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final empty = !contact.hasAddress && contact.addresses.isEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (canManage)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _add(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Adresse'),
            ),
          ),
        if (canManage && !empty) const SizedBox(height: 8),
        if (empty && !canManage)
          const _PlaceholderTab(
            icon: Icons.place_outlined,
            title: 'Keine Adresse hinterlegt',
            message: 'Für diesen Kontakt ist noch keine Adresse erfasst.',
          ),
        if (contact.hasAddress)
          AppSectionCard(
            title: 'Hauptadresse',
            icon: Icons.home_outlined,
            child: Column(
              children: [
                if (contact.street?.trim().isNotEmpty ?? false)
                  InfoRow(label: 'Straße', value: contact.street!),
                if (contact.postalCode?.trim().isNotEmpty ?? false)
                  InfoRow(label: 'PLZ', value: contact.postalCode!),
                if (contact.city?.trim().isNotEmpty ?? false)
                  InfoRow(label: 'Ort', value: contact.city!),
              ],
            ),
          ),
        for (final addr in contact.addresses) ...[
          const SizedBox(height: 12),
          AppSectionCard(
            title: addr.type.label,
            icon: _addressIcon(addr.type),
            trailing: canManage
                ? _ItemMenu(
                    onEdit: () => _edit(context, addr),
                    onRemove: () => _remove(context, addr),
                  )
                : (addr.label?.trim().isNotEmpty ?? false)
                    ? Text(addr.label!.trim(),
                        style: Theme.of(context).textTheme.bodySmall)
                    : null,
            child: Column(
              children: [
                if (addr.label?.trim().isNotEmpty ?? false)
                  InfoRow(label: 'Bezeichnung', value: addr.label!),
                if ((addr.street?.trim().isNotEmpty ?? false) ||
                    (addr.houseNumber?.trim().isNotEmpty ?? false))
                  InfoRow(
                    label: 'Straße',
                    value: [
                      addr.street?.trim() ?? '',
                      addr.houseNumber?.trim() ?? ''
                    ].where((v) => v.isNotEmpty).join(' '),
                  ),
                if (addr.zip?.trim().isNotEmpty ?? false)
                  InfoRow(label: 'PLZ', value: addr.zip!),
                if (addr.city?.trim().isNotEmpty ?? false)
                  InfoRow(label: 'Ort', value: addr.city!),
                InfoRow(label: 'Land', value: addr.country),
                if (addr.addressExtra?.trim().isNotEmpty ?? false)
                  InfoRow(label: 'Zusatz', value: addr.addressExtra!),
                if (addr.postbox?.trim().isNotEmpty ?? false)
                  InfoRow(label: 'Postfach', value: addr.postbox!),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Tab „Kommunikation": strukturierte Kanäle gruppiert nach Kontext
/// (bearbeitbar), zusätzlich die flachen Stammdaten-Felder (read-only, über den
/// Editor gepflegt). Primär-Markierung, Kopieren.
class _KommunikationTab extends StatelessWidget {
  const _KommunikationTab({required this.contact, required this.canManage});

  final Contact contact;
  final bool canManage;

  Future<void> _add(BuildContext context) async {
    final c = await showChannelDialog(context);
    if (c == null || !context.mounted) return;
    await _persistContact(
        context, contact.copyWith(channels: [...contact.channels, c]));
  }

  Future<void> _edit(
      BuildContext context, int index, CommunicationChannel channel) async {
    final c = await showChannelDialog(context, existing: channel);
    if (c == null || !context.mounted) return;
    final list = [...contact.channels];
    list[index] = c;
    await _persistContact(context, contact.copyWith(channels: list));
  }

  Future<void> _remove(BuildContext context, int index) async {
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Kanal entfernen?',
      message: 'Der Kommunikationskanal wird entfernt.',
      confirmLabel: 'Entfernen',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final list = [...contact.channels]..removeAt(index);
    await _persistContact(context, contact.copyWith(channels: list));
  }

  @override
  Widget build(BuildContext context) {
    final structured = contact.channels;
    // Flache Felder nur zeigen, wenn keine strukturierten Kanäle da sind
    // (sonst wären sie redundant) — read-only, Quelle ist der Stammdaten-Editor.
    final flat = structured.isEmpty ? _flatChannels(contact) : const [];
    final empty = structured.isEmpty && flat.isEmpty;

    // Strukturierte Kanäle nach Kontext gruppieren (mit Original-Index für Edit).
    final groups = <CommunicationContext, List<int>>{};
    for (var i = 0; i < structured.length; i++) {
      groups.putIfAbsent(structured[i].context, () => []).add(i);
    }
    final ordered = [
      CommunicationContext.dienst,
      CommunicationContext.privat,
      CommunicationContext.firma,
    ].where(groups.containsKey);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (canManage)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _add(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Kanal'),
            ),
          ),
        if (canManage && !empty) const SizedBox(height: 8),
        if (empty && !canManage)
          const _PlaceholderTab(
            icon: Icons.phone_outlined,
            title: 'Keine Kommunikationsdaten',
            message:
                'Für diesen Kontakt sind noch keine Kontaktdaten hinterlegt.',
          ),
        for (final ctx in ordered) ...[
          AppSectionCard(
            title: ctx.label,
            icon: _contextIcon(ctx),
            child: Column(
              children: [
                for (final i in groups[ctx]!)
                  _ChannelRow(
                    channel: structured[i],
                    onEdit:
                        canManage ? () => _edit(context, i, structured[i]) : null,
                    onRemove: canManage ? () => _remove(context, i) : null,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (flat.isNotEmpty)
          AppSectionCard(
            title: 'Aus Stammdaten',
            icon: Icons.badge_outlined,
            child: Column(
              children: [
                for (final c in flat) _ChannelRow(channel: c),
              ],
            ),
          ),
      ],
    );
  }
}

/// Tab „Ansprechpartner / Beziehungen": bei Firmen verknüpfte Personen-Kontakte
/// (Rolle, Haupt-Ansprechpartner), bei Personen die zugehörige Firma
/// (parentContactId). Zusätzlich der einzelne Freitext-Ansprechpartner aus den
/// Stammdaten (read-only).
class _AnsprechpartnerTab extends StatelessWidget {
  const _AnsprechpartnerTab({required this.contact, required this.canManage});

  final Contact contact;
  final bool canManage;

  Future<void> _linkPerson(BuildContext context, List<Contact> all) async {
    final linked = contact.contactPersons.map((p) => p.personContactId).toSet();
    final available = all
        .where((c) =>
            c.kind == ContactKind.person &&
            c.id != contact.id &&
            !linked.contains(c.id))
        .toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Keine weiteren Personen-Kontakte verfügbar.')),
      );
      return;
    }
    final result =
        await showContactPersonDialog(context, availablePersons: available);
    if (result == null || !context.mounted) return;
    await _persistContact(
        context, _withContactPerson(contact, result, add: true));
  }

  Future<void> _editPerson(
      BuildContext context, ContactPerson person, List<Contact> all) async {
    final linked = contact.contactPersons
        .where((p) => p.id != person.id)
        .map((p) => p.personContactId)
        .toSet();
    final available = all
        .where((c) =>
            c.kind == ContactKind.person &&
            c.id != contact.id &&
            (!linked.contains(c.id) || c.id == person.personContactId))
        .toList();
    final result = await showContactPersonDialog(
      context,
      existing: person,
      availablePersons: available,
    );
    if (result == null || !context.mounted) return;
    await _persistContact(
        context, _withContactPerson(contact, result, add: false));
  }

  Future<void> _removePerson(BuildContext context, ContactPerson person) async {
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Ansprechpartner entfernen?',
      message: 'Die Verknüpfung wird entfernt.',
      confirmLabel: 'Entfernen',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await _persistContact(
      context,
      contact.copyWith(
        contactPersons:
            contact.contactPersons.where((p) => p.id != person.id).toList(),
      ),
    );
  }

  Future<void> _setCompany(BuildContext context, List<Contact> all) async {
    final companies =
        all.where((c) => c.kind == ContactKind.company && c.id != contact.id).toList();
    if (companies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Firmen-Kontakte verfügbar.')),
      );
      return;
    }
    final result = await showCompanyPickerDialog(
      context,
      companies: companies,
      selectedId: contact.parentContactId,
    );
    if (result == null || !context.mounted) return;
    await _persistContact(context, contact.copyWith(parentContactId: result));
  }

  Future<void> _clearCompany(BuildContext context) async {
    await _persistContact(
        context, contact.copyWith(clearParentContactId: true));
  }

  @override
  Widget build(BuildContext context) {
    final all = context.watch<ContactProvider>().contacts;
    final legacyPerson = contact.contactPerson?.trim();
    final isCompany = contact.kind == ContactKind.company;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Freitext-Ansprechpartner aus den Stammdaten (read-only).
        if (legacyPerson != null && legacyPerson.isNotEmpty) ...[
          AppSectionCard(
            title: 'Ansprechpartner (Stammdaten)',
            icon: Icons.person_outline,
            child: InfoRow(label: 'Name', value: legacyPerson),
          ),
          const SizedBox(height: 12),
        ],

        if (isCompany)
          _companySection(context, all)
        else
          _personSection(context, all),
      ],
    );
  }

  Widget _companySection(BuildContext context, List<Contact> all) {
    final theme = Theme.of(context);
    final persons = [...contact.contactPersons]
      ..sort((a, b) => a.isPrimary == b.isPrimary ? 0 : (a.isPrimary ? -1 : 1));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Ansprechpartner', style: theme.textTheme.titleSmall),
            ),
            if (canManage)
              FilledButton.icon(
                onPressed: () => _linkPerson(context, all),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Zuordnen'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (persons.isEmpty)
          const _PlaceholderTab(
            icon: Icons.people_outline,
            title: 'Keine Ansprechpartner',
            message: 'Diesem Kontakt ist noch keine Person zugeordnet.',
          )
        else
          for (final p in persons)
            _RelationshipTile(
              title: _lookupName(all, p.personContactId),
              subtitle: p.role,
              isPrimary: p.isPrimary,
              onEdit: canManage ? () => _editPerson(context, p, all) : null,
              onRemove: canManage ? () => _removePerson(context, p) : null,
            ),
      ],
    );
  }

  Widget _personSection(BuildContext context, List<Contact> all) {
    final parentId = contact.parentContactId;
    final hasCompany = parentId != null && parentId.isNotEmpty;
    return AppSectionCard(
      title: 'Zugehörige Firma',
      icon: Icons.business_outlined,
      trailing: canManage
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.swap_horiz, size: 20),
                  tooltip: 'Firma auswählen',
                  onPressed: () => _setCompany(context, all),
                ),
                if (hasCompany)
                  IconButton(
                    icon: Icon(Icons.clear,
                        size: 20, color: Theme.of(context).colorScheme.error),
                    tooltip: 'Firma entfernen',
                    onPressed: () => _clearCompany(context),
                  ),
              ],
            )
          : null,
      child: InfoRow(
        label: 'Firma',
        value: hasCompany ? _lookupName(all, parentId) : 'Keine Firma hinterlegt',
      ),
    );
  }

  /// Fügt/aktualisiert einen [ContactPerson] und erzwingt genau einen Primär.
  Contact _withContactPerson(Contact c, ContactPerson person,
      {required bool add}) {
    var list = [...c.contactPersons];
    if (add) {
      list.add(person);
    } else {
      list = list.map((p) => p.id == person.id ? person : p).toList();
    }
    if (person.isPrimary) {
      list = [
        for (final p in list)
          if (p.id == person.id) p else p.copyWith(isPrimary: false),
      ];
    }
    return c.copyWith(contactPersons: list);
  }

  String _lookupName(List<Contact> all, String id) {
    for (final c in all) {
      if (c.id == id) return c.displayName;
    }
    return 'Unbekannter Kontakt';
  }
}

/// Karte für eine Ansprechpartner-Beziehung (Name, Rolle, Hauptkontakt-Chip).
class _RelationshipTile extends StatelessWidget {
  const _RelationshipTile({
    required this.title,
    this.subtitle,
    required this.isPrimary,
    this.onEdit,
    this.onRemove,
  });

  final String title;
  final String? subtitle;
  final bool isPrimary;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isPrimary
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: const Icon(Icons.person_outline),
        ),
        title: Text(title),
        subtitle: (subtitle?.trim().isNotEmpty ?? false) ? Text(subtitle!) : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPrimary)
              const Chip(
                label: Text('Hauptkontakt'),
                visualDensity: VisualDensity.compact,
              ),
            if (onEdit != null || onRemove != null)
              _ItemMenu(onEdit: onEdit, onRemove: onRemove),
          ],
        ),
      ),
    );
  }
}

/// Tab „Bank": Bankverbindungen (IBAN/BIC/Bank/Inhaber, aktiv/inaktiv),
/// hinzufügen/bearbeiten/entfernen.
class _BankTab extends StatelessWidget {
  const _BankTab({required this.contact, required this.canManage});

  final Contact contact;
  final bool canManage;

  Future<void> _add(BuildContext context) async {
    final b = await showBankAccountDialog(context);
    if (b == null || !context.mounted) return;
    await _persistContact(
        context, contact.copyWith(bankAccounts: [...contact.bankAccounts, b]));
  }

  Future<void> _edit(BuildContext context, BankAccount bank) async {
    final b = await showBankAccountDialog(context, existing: bank);
    if (b == null || !context.mounted) return;
    await _persistContact(
      context,
      contact.copyWith(
        bankAccounts:
            contact.bankAccounts.map((x) => x.id == bank.id ? b : x).toList(),
      ),
    );
  }

  Future<void> _remove(BuildContext context, BankAccount bank) async {
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Bankverbindung entfernen?',
      message: 'IBAN „${bank.iban}" wird entfernt.',
      confirmLabel: 'Entfernen',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await _persistContact(
      context,
      contact.copyWith(
        bankAccounts:
            contact.bankAccounts.where((x) => x.id != bank.id).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (canManage)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _add(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Bankverbindung'),
            ),
          ),
        if (canManage && contact.bankAccounts.isNotEmpty)
          const SizedBox(height: 8),
        if (contact.bankAccounts.isEmpty && !canManage)
          const _PlaceholderTab(
            icon: Icons.account_balance_outlined,
            title: 'Keine Bankverbindungen',
            message:
                'Für diesen Kontakt ist noch keine Bankverbindung hinterlegt.',
          ),
        for (final bank in contact.bankAccounts)
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.account_balance_outlined),
              ),
              title: Text(bank.iban),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (bank.bic?.trim().isNotEmpty ?? false)
                    Text('BIC: ${bank.bic!.trim()}'),
                  if (bank.bankName?.trim().isNotEmpty ?? false)
                    Text(bank.bankName!.trim()),
                  if (bank.accountHolder?.trim().isNotEmpty ?? false)
                    Text('Inhaber: ${bank.accountHolder!.trim()}'),
                  if (bank.deactivated)
                    Text('Inaktiv',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.error)),
                ],
              ),
              trailing: canManage
                  ? _ItemMenu(
                      onEdit: () => _edit(context, bank),
                      onRemove: () => _remove(context, bank),
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}

/// Tab „Einwilligungen": DSGVO-Einwilligungen (Datenverarbeitung/E-Mail/Telefon/
/// Weitergabe) — Status-Chips + Liste erteilter/widerrufener Consents; erfassen
/// und widerrufen (Widerruf setzt `withdrawnAt`, kein Löschen).
class _EinwilligungenTab extends StatelessWidget {
  const _EinwilligungenTab({required this.contact, required this.canManage});

  final Contact contact;
  final bool canManage;

  bool _isActive(ConsentType type) =>
      contact.consents.any((c) => c.consentType == type && c.isActive);

  Future<void> _add(BuildContext context) async {
    final c = await showConsentDialog(context, now: DateTime.now());
    if (c == null || !context.mounted) return;
    await _persistContact(
        context, contact.copyWith(consents: [...contact.consents, c]));
  }

  Future<void> _withdraw(BuildContext context, ContactConsent consent) async {
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Einwilligung widerrufen?',
      message: 'Dies kann nicht rückgängig gemacht werden.',
      confirmLabel: 'Widerrufen',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final now = DateTime.now();
    await _persistContact(
      context,
      contact.copyWith(
        consents: contact.consents
            .map((c) => c.id == consent.id ? c.copyWith(withdrawnAt: now) : c)
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final consents = [...contact.consents]
      ..sort((a, b) => b.grantedAt.compareTo(a.grantedAt));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (canManage)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _add(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Erfassen'),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ConsentChip(
                label: 'Datenverarbeitung',
                granted: _isActive(ConsentType.dataProcessing)),
            _ConsentChip(
                label: 'E-Mail', granted: _isActive(ConsentType.emailContact)),
            _ConsentChip(
                label: 'Telefon', granted: _isActive(ConsentType.phoneContact)),
            _ConsentChip(
                label: 'Weitergabe',
                granted: _isActive(ConsentType.dataSharing)),
          ],
        ),
        const SizedBox(height: 12),
        if (consents.isEmpty)
          Text('Keine Einwilligungen erfasst.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
        else
          for (final c in consents)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    c.isActive ? Icons.check_circle : Icons.cancel,
                    size: 18,
                    color: c.isActive
                        ? theme.appColors.success
                        : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.consentType.label,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text(
                          c.isActive
                              ? 'Erteilt am ${_formatDate(c.grantedAt)}'
                              : 'Widerrufen am ${_formatDate(c.withdrawnAt!)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (c.note?.trim().isNotEmpty ?? false)
                          Text(c.note!.trim(),
                              style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  if (c.isActive && canManage)
                    TextButton(
                      onPressed: () => _withdraw(context, c),
                      child: const Text('Widerrufen'),
                    ),
                ],
              ),
            ),
      ],
    );
  }
}

/// Status-Chip einer Einwilligungs-Art (erteilt/nicht erteilt).
class _ConsentChip extends StatelessWidget {
  const _ConsentChip({required this.label, required this.granted});

  final String label;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        granted ? theme.appColors.success : theme.colorScheme.onSurfaceVariant;
    return Chip(
      avatar: Icon(granted ? Icons.check : Icons.close, size: 16, color: color),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Tab „Notizen": interne Bemerkungen + Schlagworte.
class _NotizenTab extends StatelessWidget {
  const _NotizenTab({required this.contact});

  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = contact.notes?.trim() ?? '';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppSectionCard(
          title: 'Interne Bemerkungen',
          icon: Icons.notes,
          child: Text(
            notes.isEmpty ? 'Keine Notizen vorhanden.' : notes,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        if (contact.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppSectionCard(
            title: 'Schlagworte',
            icon: Icons.label_outline,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in contact.tags) Chip(label: Text(tag)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Eine Kanal-Zeile: Icon + Wert (+ Primär-Badge/Label/Erreichbarkeit) +
/// Kopieren, optional Bearbeiten/Entfernen.
class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.channel, this.onEdit, this.onRemove});

  final CommunicationChannel channel;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_channelIcon(channel.type),
              size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(channel.value,
                          style: theme.textTheme.bodyMedium),
                    ),
                    if (channel.isPrimary) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Primär',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ],
                  ],
                ),
                if (channel.label?.trim().isNotEmpty ?? false)
                  Text(channel.label!.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                if (channel.availability?.trim().isNotEmpty ?? false)
                  Text(channel.availability!.trim(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: 'Kopieren',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: channel.value));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('In Zwischenablage kopiert')),
              );
            },
          ),
          if (onEdit != null || onRemove != null)
            _ItemMenu(onEdit: onEdit, onRemove: onRemove),
        ],
      ),
    );
  }
}

/// Kompaktes Kontextmenü (Bearbeiten/Entfernen) für Sub-Objekt-Zeilen/-Karten.
class _ItemMenu extends StatelessWidget {
  const _ItemMenu({this.onEdit, this.onRemove});

  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      tooltip: 'Aktionen',
      onSelected: (value) {
        if (value == 'edit') onEdit?.call();
        if (value == 'remove') onRemove?.call();
      },
      itemBuilder: (_) => [
        if (onEdit != null)
          const PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
        if (onRemove != null)
          const PopupMenuItem(value: 'remove', child: Text('Entfernen')),
      ],
    );
  }
}

/// Speichert einen geänderten Kontakt über den [ContactProvider] (Storage-Modus-
/// bewusst) und zeigt bei Fehlern einen Hinweis.
Future<void> _persistContact(BuildContext context, Contact updated) async {
  try {
    await context.read<ContactProvider>().saveContact(updated);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $error')),
      );
    }
  }
}

/// Eine Zeile der Aktivitäten-Historie (Icon + Art + Datum + Notiz).
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity});

  final ContactActivity activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
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
                  '${activity.type.label} · ${_formatDate(activity.occurredAt)}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if ((activity.note?.trim().isNotEmpty ?? false))
                  Text(activity.note!.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Kompakter Info-Chip (Icon + Text) für die VCard-Chip-Reihe.
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
          ],
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

/// Neutraler Leer-/Platzhalter-Tab.
class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return EmptyState(icon: icon, title: title, message: message);
  }
}

// ── Datenaufbereitung ────────────────────────────────────────────────────────

/// Stammdaten-Zeilen je nach Person/Firma (nur gesetzte Werte).
List<Widget> _stammRows(Contact c) {
  final rows = <Widget>[];
  if (c.kind == ContactKind.person) {
    if (c.gender != Gender.unbekannt) {
      rows.add(InfoRow(label: 'Anrede', value: c.gender.salutation));
    }
    if (c.title?.trim().isNotEmpty ?? false) {
      rows.add(InfoRow(label: 'Titel', value: c.title!.trim()));
    }
    if (c.firstName?.trim().isNotEmpty ?? false) {
      rows.add(InfoRow(label: 'Vorname', value: c.firstName!.trim()));
    }
    if (c.lastName?.trim().isNotEmpty ?? false) {
      rows.add(InfoRow(label: 'Nachname', value: c.lastName!.trim()));
    }
    if (c.department?.trim().isNotEmpty ?? false) {
      rows.add(InfoRow(label: 'Abteilung', value: c.department!.trim()));
    }
  } else {
    if (c.companyName?.trim().isNotEmpty ?? false) {
      rows.add(InfoRow(label: 'Firmenname', value: c.companyName!.trim()));
    }
    if (c.legalName?.trim().isNotEmpty ?? false) {
      rows.add(InfoRow(label: 'Offizieller Name', value: c.legalName!.trim()));
    }
  }
  return rows;
}

/// Geschäftsdaten-Zeilen (nur gesetzte Werte).
List<Widget> _businessRows(Contact c) {
  final rows = <Widget>[];
  void add(String label, String? value) {
    if (value?.trim().isNotEmpty ?? false) {
      rows.add(InfoRow(label: label, value: value!.trim()));
    }
  }

  add('Kundennummer', c.customerNumber);
  add('Debitoren-Nr.', c.debitorNumber);
  add('Kreditoren-Nr.', c.creditorNumber);
  add('USt-ID / Steuer-Nr.', c.taxId);
  add('Handelsregister', c.registrationNumber);
  if (c.customerSince != null) {
    rows.add(InfoRow(label: 'Kunde seit', value: _formatDate(c.customerSince!)));
  }
  return rows;
}

/// Effektive Kanäle: strukturierte [Contact.channels], sonst aus den flachen
/// Feldern (E-Mail/Telefon/Mobil/Website) abgeleitet.
List<CommunicationChannel> _effectiveChannels(Contact c) {
  if (c.channels.isNotEmpty) return c.channels;
  return _flatChannels(c);
}

/// Implizite Kanäle aus den flachen Stammdaten-Feldern (E-Mail/Telefon/Mobil/
/// Website) — read-only, gepflegt über den Stammdaten-Editor.
List<CommunicationChannel> _flatChannels(Contact c) {
  final flat = <CommunicationChannel>[];
  void add(ChannelType type, String? value, {bool primary = false}) {
    final v = value?.trim();
    if (v != null && v.isNotEmpty) {
      flat.add(CommunicationChannel(type: type, value: v, isPrimary: primary));
    }
  }

  add(ChannelType.email, c.email, primary: true);
  add(ChannelType.phone, c.phone);
  add(ChannelType.mobile, c.mobile);
  add(ChannelType.website, c.website);
  return flat;
}

IconData _addressIcon(AddressType type) => switch (type) {
      AddressType.haupt => Icons.home_outlined,
      AddressType.rechnung => Icons.receipt_long_outlined,
      AddressType.lieferung => Icons.local_shipping_outlined,
      AddressType.niederlassung => Icons.apartment_outlined,
    };

IconData _channelIcon(ChannelType type) => switch (type) {
      ChannelType.email => Icons.email_outlined,
      ChannelType.phone => Icons.phone_outlined,
      ChannelType.mobile => Icons.phone_android,
      ChannelType.fax => Icons.fax_outlined,
      ChannelType.website => Icons.language,
    };

IconData _contextIcon(CommunicationContext ctx) => switch (ctx) {
      CommunicationContext.dienst => Icons.work_outline,
      CommunicationContext.privat => Icons.home_outlined,
      CommunicationContext.firma => Icons.business_outlined,
    };

IconData _activityIcon(ContactActivityType type) => switch (type) {
      ContactActivityType.call => Icons.phone_outlined,
      ContactActivityType.email => Icons.email_outlined,
      ContactActivityType.meeting => Icons.groups_outlined,
      ContactActivityType.note => Icons.sticky_note_2_outlined,
      ContactActivityType.task => Icons.check_circle_outline,
    };

AppStatusTone _statusTone(ContactStatus status) => switch (status) {
      ContactStatus.aktiv => AppStatusTone.success,
      ContactStatus.inaktiv => AppStatusTone.neutral,
      ContactStatus.gesperrt => AppStatusTone.error,
    };

String _initials(String value) {
  final parts =
      value.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first)
      .toUpperCase();
}

String _formatDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year}';
}

/// Öffnet den reichen [ContactEditorSheet] (Liste + Detail teilen ihn) und
/// speichert das Ergebnis über den [ContactProvider]. Nur für Manager
/// (`canManageContacts`) — der Aufrufer gatet den Button.
Future<void> _editContact(BuildContext context, Contact contact) async {
  final team = context.read<TeamProvider>();
  final orgId = context.read<AuthProvider>().profile?.orgId ?? contact.orgId;
  final result = await showAppBottomSheet<Contact>(
    context: context,
    builder: (_) => ContactEditorSheet(
      contact: contact,
      sites: team.sites,
      orgId: orgId,
    ),
  );
  if (result == null || !context.mounted) return;
  try {
    await context.read<ContactProvider>().saveContact(result);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kontakt „${result.displayName}" aktualisiert.')),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $error')),
      );
    }
  }
}
