import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/contact.dart';
import '../providers/contact_provider.dart';

/// Ergebnis von [showContactPicker]. `contact == null` bedeutet bewusst
/// „kein Kontakt" (Laufkunde / Verknüpfung entfernen) — zu unterscheiden von
/// einem abgebrochenen Sheet (dann liefert [showContactPicker] selbst `null`).
class ContactSelection {
  const ContactSelection(this.contact);
  final Contact? contact;
}

/// Öffnet die Kontaktauswahl (Suche + „kein Kontakt") als Bottom-Sheet und
/// liefert das Ergebnis. Liest die **bereits gestreamte** Liste aus dem
/// [ContactProvider] (keine zusätzlichen Firestore-Reads). Rückgabe `null` =
/// abgebrochen; sonst eine [ContactSelection] (`contact == null` = „kein
/// Kontakt"). Wird sowohl von [ContactPickerField] als auch direkt aus
/// Aktions-Menüs (z. B. Kundenwünsche/-feedback, H-D2) genutzt.
Future<ContactSelection?> showContactPicker(
  BuildContext context, {
  String? currentContactId,
  List<ContactType>? allowedTypes,
  String emptyLabel = 'Kein Kontakt',
}) async {
  final provider = context.read<ContactProvider>();
  // Ein bereits verknüpfter Kontakt bleibt sichtbar, auch wenn sein Typ nicht
  // im Filter liegt (kein stiller Verlust) — analog ContactPickerField.
  final available = allowedTypes == null
      ? provider.contacts
      : provider.contacts
          .where((c) => allowedTypes.contains(c.type) || c.id == currentContactId)
          .toList();
  final result = await showModalBottomSheet<_ContactPick>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ContactPickerSheet(
      contacts: available,
      emptyLabel: emptyLabel,
    ),
  );
  return result == null ? null : ContactSelection(result.contact);
}

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
    this.emptyLabel = 'Laufkunde (kein Kontakt)',
    this.allowedTypes,
  });

  final String? contactId;
  final ValueChanged<Contact?> onSelected;
  final String label;

  /// Text fuer „kein Kontakt verknuepft" (Platzhalter + Auswahl-Eintrag).
  final String emptyLabel;

  /// Optionaler Filter auf bestimmte [ContactType]s (z. B. nur Lieferanten).
  /// `null` = alle Kontakte. Ein bereits verknuepfter Kontakt wird auch dann
  /// angezeigt, wenn sein Typ nicht im Filter liegt (kein stiller Verlust).
  final List<ContactType>? allowedTypes;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ContactProvider>();
    final selected = provider.contactById(contactId);
    return InkWell(
      onTap: () async {
        final selection = await showContactPicker(
          context,
          currentContactId: contactId,
          allowedTypes: allowedTypes,
          emptyLabel: emptyLabel,
        );
        if (selection != null) {
          onSelected(selection.contact);
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
                selected?.name ?? emptyLabel,
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
  const _ContactPickerSheet({
    required this.contacts,
    required this.emptyLabel,
  });

  final List<Contact> contacts;
  final String emptyLabel;

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
              title: Text(widget.emptyLabel),
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
