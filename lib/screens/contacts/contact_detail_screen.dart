import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/contact.dart';
import '../../models/contact_activity.dart';
import '../../providers/auth_provider.dart';
import '../../providers/contact_provider.dart';
import '../../providers/team_provider.dart';
import '../../ui/ui.dart';
import '../../widgets/info_row.dart';

/// Kontakt-Detailseite — **AllTec-1:1**: Kopf-Visitenkarte + eine scrollbare
/// TabBar mit **exakt 7 Tabs** (Icon + Text), analog `ContactDetailPage` aus
/// AllTec (Übersicht · Adressen · Kommunikation · Ansprechpartner ·
/// Einwilligungen · Bank · Notizen).
///
/// Deep-linkbar über `/kontakte/{id}`. Lesen darf **jedes aktive Mitglied**
/// ([AppUserProfile.canViewContacts]) — gated in
/// [RoutePermissions.isLocationAllowed] per `/kontakte/`-Prefix und hier im
/// In-Screen-Gate. Verwaltungs-Aktionen bleiben an
/// [AppUserProfile.canManageContacts] gebunden (folgt in späteren
/// Meilensteinen). Die Tab-Inhalte werden auf AllTec-Feldparität ausgebaut
/// (M4–M9); dieses M1-Gerüst liefert Kopf, Navigation und die über das heutige
/// (flache) Modell verfügbaren Daten. Fahrplan: `plan/kontakte-alltec-1zu1.md`.
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

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: BreadcrumbAppBar(
          breadcrumbs: <BreadcrumbItem>[
            BreadcrumbItem(
              label: parentLabel,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            BreadcrumbItem(label: contact.name),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _ContactVCard(contact: contact),
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
                  _AdressenTab(contact: contact),
                  _KommunikationTab(contact: contact),
                  _AnsprechpartnerTab(contact: contact),
                  const _PlaceholderTab(
                    icon: Icons.shield_outlined,
                    title: 'Einwilligungen',
                    message: 'DSGVO-Einwilligungen (Datenverarbeitung, E-Mail, '
                        'Telefon, Weitergabe) folgen in einem der nächsten '
                        'Schritte.',
                  ),
                  const _PlaceholderTab(
                    icon: Icons.account_balance_outlined,
                    title: 'Bank',
                    message: 'Bankverbindungen (IBAN, BIC, Kontoinhaber) folgen '
                        'in einem der nächsten Schritte.',
                  ),
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

/// Kompakte Visitenkarte des Kontakts (analog AllTec-Kopf-VCard): Avatar mit
/// Initialen, Name, Kontaktart und Kontakt-/Status-Zeile.
class _ContactVCard extends StatelessWidget {
  const _ContactVCard({required this.contact});

  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = <String>[
      contact.type.label,
      if (contact.primaryPhone != null) contact.primaryPhone!,
      if ((contact.email?.trim().isNotEmpty ?? false)) contact.email!.trim(),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              child: Text(contact.initials, style: theme.textTheme.titleLarge),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(contact.name,
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
                  if (subtitleParts.isNotEmpty)
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
            const SizedBox(width: 12),
            AppStatusBadge(
              label: contact.isActive ? 'Aktiv' : 'Archiviert',
              tone:
                  contact.isActive ? AppStatusTone.success : AppStatusTone.neutral,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab „Übersicht": Geschäftsdaten, Standort, Kommunikation-Quickview,
/// Hauptadresse und die (WorkTime-eigene, erhaltene) Aktivitäten-Historie.
class _UebersichtTab extends StatelessWidget {
  const _UebersichtTab({required this.contact, required this.team});

  final Contact contact;
  final TeamProvider team;

  @override
  Widget build(BuildContext context) {
    final hasBusiness = (contact.customerNumber?.trim().isNotEmpty ?? false) ||
        (contact.taxId?.trim().isNotEmpty ?? false);
    final comms = _commRows(contact);
    final siteLabel =
        team.siteNameById(contact.siteId, fallback: contact.siteName) ??
            'Allgemein (beide Läden)';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (hasBusiness)
          AppSectionCard(
            title: 'Geschäftsdaten',
            icon: Icons.badge_outlined,
            child: Column(
              children: [
                if (contact.customerNumber?.trim().isNotEmpty ?? false)
                  InfoRow(label: 'Kundennummer', value: contact.customerNumber!),
                if (contact.taxId?.trim().isNotEmpty ?? false)
                  InfoRow(label: 'USt-ID / Steuer-Nr.', value: contact.taxId!),
              ],
            ),
          ),
        if (hasBusiness) const SizedBox(height: 12),
        AppSectionCard(
          title: 'Zuordnung',
          icon: Icons.store_outlined,
          child: InfoRow(label: 'Standort', value: siteLabel),
        ),
        if (comms.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppSectionCard(
            title: 'Kommunikation',
            icon: Icons.phone_outlined,
            child: Column(children: comms),
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

/// Tab „Adressen": zeigt heute die (einzelne) Hauptadresse. Mehrfach-Adressen
/// (Rechnung/Lieferung/Niederlassung) folgen mit dem Modell-Ausbau.
class _AdressenTab extends StatelessWidget {
  const _AdressenTab({required this.contact});

  final Contact contact;

  @override
  Widget build(BuildContext context) {
    if (!contact.hasAddress) {
      return const _PlaceholderTab(
        icon: Icons.place_outlined,
        title: 'Keine Adresse hinterlegt',
        message: 'Für diesen Kontakt ist noch keine Adresse erfasst.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
      ],
    );
  }
}

/// Tab „Kommunikation": E-Mail, Festnetz, Mobil, Website (heutige flache
/// Felder). Typisierte Kanäle mit Kontext/Primär folgen mit dem Modell-Ausbau.
class _KommunikationTab extends StatelessWidget {
  const _KommunikationTab({required this.contact});

  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final rows = _commRows(contact);
    if (rows.isEmpty) {
      return const _PlaceholderTab(
        icon: Icons.phone_outlined,
        title: 'Keine Kommunikationsdaten',
        message: 'Für diesen Kontakt sind noch keine Kontaktdaten hinterlegt.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppSectionCard(
          title: 'Kommunikation',
          icon: Icons.phone_outlined,
          child: Column(children: rows),
        ),
      ],
    );
  }
}

/// Tab „Ansprechpartner": heute der (einzelne) Ansprechpartner-Freitext.
/// Mehrere Ansprechpartner + Firma↔Person-Beziehungen folgen mit dem
/// Modell-Ausbau.
class _AnsprechpartnerTab extends StatelessWidget {
  const _AnsprechpartnerTab({required this.contact});

  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final person = contact.contactPerson?.trim();
    if (person == null || person.isEmpty) {
      return const _PlaceholderTab(
        icon: Icons.people_outline,
        title: 'Keine Ansprechpartner',
        message: 'Für diesen Kontakt ist noch kein Ansprechpartner hinterlegt.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppSectionCard(
          title: 'Ansprechpartner',
          icon: Icons.person_outline,
          child: InfoRow(label: 'Name', value: person),
        ),
      ],
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

/// Neutraler Leer-/Platzhalter-Tab (für Tabs ohne Daten oder noch nicht
/// modellierte Bereiche wie Einwilligungen/Bank).
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

/// Baut die Kommunikations-Zeilen aus den heutigen flachen Feldern.
List<Widget> _commRows(Contact contact) {
  return [
    if (contact.email?.trim().isNotEmpty ?? false)
      InfoRow(label: 'E-Mail', value: contact.email!.trim()),
    if (contact.phone?.trim().isNotEmpty ?? false)
      InfoRow(label: 'Telefon', value: contact.phone!.trim()),
    if (contact.mobile?.trim().isNotEmpty ?? false)
      InfoRow(label: 'Mobil', value: contact.mobile!.trim()),
    if (contact.website?.trim().isNotEmpty ?? false)
      InfoRow(label: 'Website', value: contact.website!.trim()),
  ];
}

IconData _activityIcon(ContactActivityType type) => switch (type) {
      ContactActivityType.call => Icons.phone_outlined,
      ContactActivityType.email => Icons.email_outlined,
      ContactActivityType.meeting => Icons.groups_outlined,
      ContactActivityType.note => Icons.sticky_note_2_outlined,
      ContactActivityType.task => Icons.check_circle_outline,
    };

String _formatDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year}';
}
