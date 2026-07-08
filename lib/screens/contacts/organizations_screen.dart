import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/contact_organization.dart';
import '../../providers/auth_provider.dart';
import '../../providers/contact_provider.dart';
import '../../ui/ui.dart';

/// Eigenständiges Adressbuch der Kontakt-Organisationen (Agentur für Arbeit,
/// Jobcenter, Behörden …) — AllTec-1:1 (`OrganizationListPage`). Lesen alle
/// aktiven Mitglieder, verwalten Admins + Schichtleiter. Wird über eine Aktion
/// der Kontaktliste imperativ gepusht.
class OrganizationsScreen extends StatelessWidget {
  const OrganizationsScreen({super.key, this.parentLabel = 'Kontakte'});

  final String parentLabel;

  Future<void> _create(BuildContext context) async {
    final result = await showDialog<ContactOrganization>(
      context: context,
      builder: (_) => const _OrganizationDialog(),
    );
    if (result == null || !context.mounted) return;
    await _save(context, result);
  }

  Future<void> _edit(BuildContext context, ContactOrganization org) async {
    final result = await showDialog<ContactOrganization>(
      context: context,
      builder: (_) => _OrganizationDialog(existing: org),
    );
    if (result == null || !context.mounted) return;
    await _save(context, result);
  }

  Future<void> _save(BuildContext context, ContactOrganization org) async {
    try {
      await context.read<ContactProvider>().saveOrganization(org);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $error')),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context, ContactOrganization org) async {
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Organisation löschen?',
      message: '„${org.name}" wird gelöscht.',
      confirmLabel: 'Löschen',
      destructive: true,
    );
    if (!ok || !context.mounted || org.id == null) return;
    await context.read<ContactProvider>().deleteOrganization(org.id!);
  }

  @override
  Widget build(BuildContext context) {
    final profile =
        context.select<AuthProvider, AppUserProfile?>((a) => a.profile);
    final canView = profile?.canViewContacts ?? false;
    final canManage = profile?.canManageContacts ?? false;
    final organizations = context.watch<ContactProvider>().organizations;

    final breadcrumbs = <BreadcrumbItem>[
      BreadcrumbItem(
        label: parentLabel,
        onTap: () => Navigator.of(context).maybePop(),
      ),
      const BreadcrumbItem(label: 'Organisationen'),
    ];

    if (!canView) {
      return Scaffold(
        appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
        body: const Center(child: Text('Keine Berechtigung für Kontakte.')),
      );
    }

    return Scaffold(
      appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              heroTag: 'organizations_add_fab',
              onPressed: () => _create(context),
              icon: const Icon(Icons.add_business),
              label: const Text('Organisation'),
            )
          : null,
      body: organizations.isEmpty
          ? const EmptyState(
              icon: Icons.domain_outlined,
              title: 'Keine Organisationen',
              message: 'Noch keine Kontakt-Organisationen angelegt.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: organizations.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final org = organizations[index];
                return ListTile(
                  leading: CircleAvatar(child: Icon(_typeIcon(org.type))),
                  title: Text(org.name),
                  subtitle: (org.city?.trim().isNotEmpty ?? false)
                      ? Text(org.city!.trim())
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(
                        label: Text(org.type.label),
                        visualDensity: VisualDensity.compact,
                      ),
                      if (canManage)
                        PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') _edit(context, org);
                            if (v == 'delete') _delete(context, org);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'edit', child: Text('Bearbeiten')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Löschen')),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

IconData _typeIcon(OrganizationType type) => switch (type) {
      OrganizationType.agenturFuerArbeit => Icons.account_balance_outlined,
      OrganizationType.jobcenter => Icons.work_outline,
      OrganizationType.praktikumsbetrieb => Icons.factory_outlined,
      OrganizationType.kooperationspartner => Icons.handshake_outlined,
      OrganizationType.behoerde => Icons.gavel_outlined,
      OrganizationType.sonstige => Icons.domain_outlined,
    };

class _OrganizationDialog extends StatefulWidget {
  const _OrganizationDialog({this.existing});
  final ContactOrganization? existing;

  @override
  State<_OrganizationDialog> createState() => _OrganizationDialogState();
}

class _OrganizationDialogState extends State<_OrganizationDialog> {
  final _formKey = GlobalKey<FormState>();
  late OrganizationType _type;
  late final TextEditingController _name;
  late final TextEditingController _city;
  late final TextEditingController _website;

  @override
  void initState() {
    super.initState();
    final o = widget.existing;
    _type = o?.type ?? OrganizationType.sonstige;
    _name = TextEditingController(text: o?.name ?? '');
    _city = TextEditingController(text: o?.city ?? '');
    _website = TextEditingController(text: o?.website ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _website.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Neue Organisation'
          : 'Organisation bearbeiten'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null,
              ),
              DropdownButtonFormField<OrganizationType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Typ'),
                items: [
                  for (final t in OrganizationTypeX.ordered)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (v) =>
                    setState(() => _type = v ?? OrganizationType.sonstige),
              ),
              TextFormField(
                controller: _city,
                decoration: const InputDecoration(labelText: 'Ort'),
              ),
              TextFormField(
                controller: _website,
                decoration: const InputDecoration(labelText: 'Website'),
                keyboardType: TextInputType.url,
                validator: (v) {
                  final raw = v?.trim() ?? '';
                  if (raw.isEmpty) return null;
                  final uri = Uri.tryParse(raw);
                  if (uri == null || !uri.hasScheme) {
                    return 'Bitte vollständige URL (https://…)';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            final base = widget.existing ??
                const ContactOrganization(id: null, orgId: '', name: '');
            Navigator.of(context).pop(base.copyWith(
              name: _name.text.trim(),
              type: _type,
              city: _city.text.trim().isEmpty ? null : _city.text.trim(),
              clearCity: _city.text.trim().isEmpty,
              website:
                  _website.text.trim().isEmpty ? null : _website.text.trim(),
              clearWebsite: _website.text.trim().isEmpty,
            ));
          },
          child: Text(widget.existing == null ? 'Anlegen' : 'Speichern'),
        ),
      ],
    );
  }
}
