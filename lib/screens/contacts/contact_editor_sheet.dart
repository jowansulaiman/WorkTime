import 'package:flutter/material.dart';

import '../../models/contact.dart';
import '../../models/contact_details.dart';
import '../../models/site_definition.dart';
import '../../ui/ui.dart';
import 'contact_visuals.dart';

/// Reicher Kontakt-Editor (AllTec-1:1) — Anlegen **und** Bearbeiten.
///
/// Gehoben aus dem file-privaten `_ContactEditorSheet` in `contacts_screen.dart`
/// und um die AllTec-Parität erweitert: **Person/Firma-Umschalter** mit den
/// passenden Stammdaten (Vor-/Nachname/Anrede/Titel/Position/Abteilung bzw.
/// Firmenname/offizieller Name/Handelsregister), Status, Alias sowie
/// Debitoren-/Kreditoren-Nummer. Der [Contact.name] (Pflicht-Sortier-/Such-
/// schlüssel) wird beim Speichern aus diesen Feldern **abgeleitet**
/// (Alias → Firma → Vor-/Nachname), sodass Bestandsdaten weiter funktionieren.
///
/// Gibt via `Navigator.pop(Contact)` das Ergebnis an den Aufrufer zurück, der
/// die Persistenz über den `ContactProvider` übernimmt (Liste **und**
/// Detailseite teilen diesen Editor). Sub-Objekte (Adressen/Bank/Kanäle) werden
/// in eigenen Dialogen gepflegt (folgt); dieser Editor lässt die vorhandenen
/// Sub-Listen unangetastet.
class ContactEditorSheet extends StatefulWidget {
  const ContactEditorSheet({
    super.key,
    required this.contact,
    required this.sites,
    required this.orgId,
  });

  final Contact? contact;
  final List<SiteDefinition> sites;
  final String orgId;

  @override
  State<ContactEditorSheet> createState() => _ContactEditorSheetState();
}

class _ContactEditorSheetState extends State<ContactEditorSheet> {
  final _formKey = GlobalKey<FormState>();

  // Person/Firma-Stammdaten.
  late final TextEditingController _companyName;
  late final TextEditingController _legalName;
  late final TextEditingController _registrationNumber;
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _title;
  late final TextEditingController _position;
  late final TextEditingController _department;
  late final TextEditingController _alias;

  // Kommunikation / Adresse / Nummern / Sonstiges.
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
  late final TextEditingController _debitorNumber;
  late final TextEditingController _creditorNumber;
  late final TextEditingController _notes;
  late final TextEditingController _tags;

  late ContactKind _kind;
  late ContactType _type;
  late ContactStatus _status;
  late Gender _gender;
  late String? _siteId;
  late bool _isFavorite;
  late bool _isActive;
  late bool _blacklisted;
  DateTime? _birthday;
  DateTime? _companyAnniversary;
  DateTime? _customerSince;

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    _kind = c?.kind ?? ContactKind.company;
    final legacyName = c?.name ?? '';

    // Legacy-Prefill: alte Kontakte haben nur `name`, keine Struktur-Felder.
    // Firma → Firmenname aus name; Person → name auf Vor-/Nachname aufteilen.
    var companyName = c?.companyName ?? '';
    if (companyName.isEmpty &&
        _kind == ContactKind.company &&
        legacyName.isNotEmpty) {
      companyName = legacyName;
    }
    var firstName = c?.firstName ?? '';
    var lastName = c?.lastName ?? '';
    if (_kind == ContactKind.person &&
        firstName.isEmpty &&
        lastName.isEmpty &&
        legacyName.isNotEmpty) {
      final parts = legacyName.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        firstName = parts.sublist(0, parts.length - 1).join(' ');
        lastName = parts.last;
      } else {
        lastName = legacyName;
      }
    }

    _companyName = TextEditingController(text: companyName);
    _legalName = TextEditingController(text: c?.legalName ?? '');
    _registrationNumber =
        TextEditingController(text: c?.registrationNumber ?? '');
    _firstName = TextEditingController(text: firstName);
    _lastName = TextEditingController(text: lastName);
    _title = TextEditingController(text: c?.title ?? '');
    _position = TextEditingController(text: c?.position ?? '');
    _department = TextEditingController(text: c?.department ?? '');
    _alias = TextEditingController(text: c?.alias ?? '');

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
    _debitorNumber = TextEditingController(text: c?.debitorNumber ?? '');
    _creditorNumber = TextEditingController(text: c?.creditorNumber ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
    _tags = TextEditingController(text: c?.tags.join(', ') ?? '');

    _type = c?.type ?? ContactType.customer;
    _status = c?.status ?? ContactStatus.aktiv;
    _gender = c?.gender ?? Gender.unbekannt;
    _isFavorite = c?.isFavorite ?? false;
    _isActive = c?.isActive ?? true;
    _blacklisted = c?.blacklisted ?? false;
    _birthday = c?.birthday;
    _companyAnniversary = c?.companyAnniversary;
    _customerSince = c?.customerSince;
    final siteId = c?.siteId;
    _siteId = (siteId != null && widget.sites.any((s) => s.id == siteId))
        ? siteId
        : null;
  }

  @override
  void dispose() {
    for (final controller in [
      _companyName,
      _legalName,
      _registrationNumber,
      _firstName,
      _lastName,
      _title,
      _position,
      _department,
      _alias,
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
      _debitorNumber,
      _creditorNumber,
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
    final isPerson = _kind == ContactKind.person;
    return AppBottomSheetScaffold(
      title: isEditing ? 'Kontakt bearbeiten' : 'Neuer Kontakt',
      subtitle: 'Kunde, Lieferant, Partner, Behörde …',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Person / Firma
            SegmentedButton<ContactKind>(
              segments: const [
                ButtonSegment(
                  value: ContactKind.person,
                  icon: Icon(Icons.person_outline),
                  label: Text('Person'),
                ),
                ButtonSegment(
                  value: ContactKind.company,
                  icon: Icon(Icons.business),
                  label: Text('Firma'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            SizedBox(height: spacing.md),

            // Stammdaten je nach Person/Firma.
            if (isPerson) ..._personFields(spacing) else ..._companyFields(spacing),
            SizedBox(height: spacing.md),

            // Kategorie + Status.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<ContactType>(
                    initialValue: _type,
                    isExpanded: true,
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
                              Icon(contactTypeIcon(type), size: 18),
                              const SizedBox(width: 10),
                              Flexible(
                                  child: Text(type.label,
                                      overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _type = value ?? ContactType.customer),
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: DropdownButtonFormField<ContactStatus>(
                    initialValue: _status,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                    items: [
                      for (final s in ContactStatus.values)
                        DropdownMenuItem(value: s, child: Text(s.label)),
                    ],
                    onChanged: (value) =>
                        setState(() => _status = value ?? ContactStatus.aktiv),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _alias,
              label: 'Anzeigename (Alias)',
              hint: 'z. B. „Praxis Dr. Müller" (überschreibt den Namen)',
              prefixIcon: const Icon(Icons.badge_outlined),
            ),
            SizedBox(height: spacing.md),
            AppFormField(
              controller: _contactPerson,
              label: 'Ansprechpartner',
              prefixIcon: const Icon(Icons.support_agent_outlined),
              textCapitalization: TextCapitalization.words,
            ),
            SizedBox(height: spacing.md),

            // Kommunikation.
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

            // Adresse.
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

            // Nummern.
            AppFormField(
              controller: _taxId,
              label: 'USt-IdNr. / Steuer-Nr.',
              prefixIcon: const Icon(Icons.receipt_long_outlined),
            ),
            SizedBox(height: spacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppFormField(
                    controller: _customerNumber,
                    label: 'Kunden-/Lief.-Nr.',
                    prefixIcon: const Icon(Icons.tag_outlined),
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: AppFormField(
                    controller: _debitorNumber,
                    label: 'Debitoren-Nr.',
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: AppFormField(
                    controller: _creditorNumber,
                    label: 'Kreditoren-Nr.',
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.md),
            _DateField(
              label: 'Kunde seit',
              value: _customerSince,
              icon: Icons.event_available_outlined,
              onChanged: (d) => setState(() => _customerSince = d),
            ),
            SizedBox(height: spacing.md),

            // Standort (Zwei-Läden-Zuordnung).
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
              value: _blacklisted,
              onChanged: (value) => setState(() => _blacklisted = value),
              secondary: const Icon(Icons.block_outlined),
              title: const Text('Auf der Blacklist'),
              subtitle: const Text('z. B. bei Zahlungsausfall.'),
            ),
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
              subtitle: const Text(
                  'Archivierte Kontakte sind standardmäßig ausgeblendet.'),
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

  List<Widget> _personFields(AppSpacing spacing) {
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: DropdownButtonFormField<Gender>(
              initialValue: _gender,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Anrede'),
              items: [
                for (final g in Gender.values)
                  DropdownMenuItem(value: g, child: Text(g.salutation)),
              ],
              onChanged: (value) =>
                  setState(() => _gender = value ?? Gender.unbekannt),
            ),
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: AppFormField(
              controller: _title,
              label: 'Titel',
              hint: 'z. B. Dr.',
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
              controller: _firstName,
              label: 'Vorname',
              prefixIcon: const Icon(Icons.person_outline),
              textCapitalization: TextCapitalization.words,
            ),
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: AppFormField(
              controller: _lastName,
              label: 'Nachname *',
              textCapitalization: TextCapitalization.words,
              validator: (value) => _requiredOrAlias(value),
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
              controller: _position,
              label: 'Position',
              textCapitalization: TextCapitalization.words,
            ),
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: AppFormField(
              controller: _department,
              label: 'Abteilung',
              textCapitalization: TextCapitalization.words,
            ),
          ),
        ],
      ),
      SizedBox(height: spacing.md),
      _DateField(
        label: 'Geburtstag',
        value: _birthday,
        icon: Icons.cake_outlined,
        onChanged: (d) => setState(() => _birthday = d),
      ),
    ];
  }

  List<Widget> _companyFields(AppSpacing spacing) {
    return [
      AppFormField(
        controller: _companyName,
        label: 'Firmenname *',
        hint: 'z. B. Nord-Tabak Großhandel GmbH',
        prefixIcon: const Icon(Icons.business_outlined),
        textCapitalization: TextCapitalization.words,
        validator: (value) => _requiredOrAlias(value),
      ),
      SizedBox(height: spacing.md),
      AppFormField(
        controller: _legalName,
        label: 'Offizieller Name (Handelsregister)',
        prefixIcon: const Icon(Icons.gavel_outlined),
        textCapitalization: TextCapitalization.words,
      ),
      SizedBox(height: spacing.md),
      AppFormField(
        controller: _registrationNumber,
        label: 'Handelsregister-Nr.',
        prefixIcon: const Icon(Icons.numbers_outlined),
      ),
      SizedBox(height: spacing.md),
      _DateField(
        label: 'Firmen-Jubiläum',
        value: _companyAnniversary,
        icon: Icons.celebration_outlined,
        onChanged: (d) => setState(() => _companyAnniversary = d),
      ),
    ];
  }

  /// Pflichtfeld — es sei denn, ein Alias ist gesetzt (dann trägt der Alias den
  /// Anzeigenamen). Spiegelt AllTecs Pflicht (Firmenname bzw. Nachname).
  String? _requiredOrAlias(String? value) {
    if (_trim(value ?? '') != null) return null;
    if (_trim(_alias.text) != null) return null;
    return 'Pflichtfeld';
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final selectedSite = widget.sites.where((s) => s.id == _siteId).toList();
    final alias = _trim(_alias.text);
    final companyName = _trim(_companyName.text);
    final firstName = _trim(_firstName.text);
    final lastName = _trim(_lastName.text);

    // `name` ableiten: Alias → Firma/Person → Bestand.
    String derivedName;
    if (_kind == ContactKind.company) {
      derivedName = alias ?? companyName ?? '';
    } else {
      final person = [firstName ?? '', lastName ?? '']
          .where((v) => v.isNotEmpty)
          .join(' ');
      derivedName = alias ?? (person.isNotEmpty ? person : '');
    }
    if (derivedName.isEmpty) {
      derivedName = widget.contact?.name ?? '';
    }

    final base = widget.contact ??
        Contact(orgId: widget.orgId, name: derivedName);
    final result = base.copyWith(
      orgId: widget.orgId,
      name: derivedName,
      kind: _kind,
      type: _type,
      status: _status,
      blacklisted: _blacklisted,
      gender: _gender,
      birthday: _birthday,
      clearBirthday: _birthday == null,
      companyAnniversary: _companyAnniversary,
      clearCompanyAnniversary: _companyAnniversary == null,
      customerSince: _customerSince,
      clearCustomerSince: _customerSince == null,
      alias: alias,
      clearAlias: alias == null,
      companyName: companyName,
      clearCompanyName: companyName == null,
      legalName: _trim(_legalName.text),
      clearLegalName: _trim(_legalName.text) == null,
      registrationNumber: _trim(_registrationNumber.text),
      clearRegistrationNumber: _trim(_registrationNumber.text) == null,
      firstName: firstName,
      clearFirstName: firstName == null,
      lastName: lastName,
      clearLastName: lastName == null,
      title: _trim(_title.text),
      clearTitle: _trim(_title.text) == null,
      position: _trim(_position.text),
      clearPosition: _trim(_position.text) == null,
      department: _trim(_department.text),
      clearDepartment: _trim(_department.text) == null,
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
      debitorNumber: _trim(_debitorNumber.text),
      clearDebitorNumber: _trim(_debitorNumber.text) == null,
      creditorNumber: _trim(_creditorNumber.text),
      clearCreditorNumber: _trim(_creditorNumber.text) == null,
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

/// Datumsauswahl-Feld (Anzeige dd.MM.yyyy, Auswahl über [showDatePicker],
/// löschbar). Für Geburtstag/Firmen-Jubiläum/Kunde-seit im Kontakt-Editor.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final IconData icon;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: v ?? DateTime(2000),
          firstDate: DateTime(1900),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: v != null
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => onChanged(null),
                )
              : null,
        ),
        child: Text(v == null
            ? 'Nicht gesetzt'
            : '${v.day.toString().padLeft(2, '0')}.'
                '${v.month.toString().padLeft(2, '0')}.${v.year}'),
      ),
    );
  }
}
