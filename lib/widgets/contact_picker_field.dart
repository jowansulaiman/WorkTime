import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/contact.dart';
import '../providers/contact_provider.dart';

/// Auswahlfeld, das eine Bestellung (o.Ä.) mit einem echten [Contact] aus der
/// Kontakte-Kartei verknüpft. Liest die **bereits gestreamte** Liste aus dem
/// [ContactProvider] (keine zusätzlichen Firestore-Reads) und bietet zusätzlich
/// „Laufkunde" (keine Verknüpfung). [onSelected] erhält den gewählten Kontakt
/// oder `null` für Laufkunde; bei Abbruch wird nichts ausgelöst.
class ContactPickerField extends StatelessWidget {
  const ContactPickerField({
    super.key,
    required this.contactId,
    required this.onSelected,
    this.label = 'Kontakt verknüpfen',
  });

  final String? contactId;
  final ValueChanged<Contact?> onSelected;
  final String label;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ContactProvider>();
    final selected = provider.contactById(contactId);
    return InkWell(
      onTap: () async {
        final result = await showModalBottomSheet<_ContactPick>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _ContactPickerSheet(contacts: provider.contacts),
        );
        if (result != null) {
          onSelected(result.contact);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.person_search_outlined),
          border: const OutlineInputBorder(),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected?.name ?? 'Laufkunde (kein Kontakt)',
                style: selected == null
                    ? TextStyle(color: Theme.of(context).hintColor)
                    : null,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

/// Ergebnis-Wrapper, um „Laufkunde gewählt" (contact == null) von „Sheet
/// abgebrochen" (Sheet liefert null) zu unterscheiden.
class _ContactPick {
  const _ContactPick(this.contact);
  final Contact? contact;
}

class _ContactPickerSheet extends StatefulWidget {
  const _ContactPickerSheet({required this.contacts});

  final List<Contact> contacts;

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = widget.contacts.where((c) {
      if (query.isEmpty) return true;
      return c.name.toLowerCase().contains(query) ||
          (c.email?.toLowerCase().contains(query) ?? false) ||
          (c.primaryPhone?.toLowerCase().contains(query) ?? false);
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Kontakt suchen',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Laufkunde (kein Kontakt)'),
              onTap: () => Navigator.of(context).pop(const _ContactPick(null)),
            ),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('Keine Kontakte gefunden.'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final contact = filtered[index];
                        return ListTile(
                          leading: CircleAvatar(child: Text(contact.initials)),
                          title: Text(contact.name),
                          subtitle: Text(
                            [
                              contact.type.shortLabel,
                              contact.primaryPhone ?? contact.email ?? '',
                            ].where((s) => s.isNotEmpty).join(' · '),
                          ),
                          onTap: () => Navigator.of(context)
                              .pop(_ContactPick(contact)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
