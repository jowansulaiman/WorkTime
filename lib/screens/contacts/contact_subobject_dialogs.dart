import 'package:flutter/material.dart';

import '../../models/contact.dart';
import '../../models/contact_details.dart';

/// Eindeutige ID für ein neues Sub-Objekt (eingebettet, kein Firestore-Doc).
String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

String? _trim(String value) {
  final t = value.trim();
  return t.isEmpty ? null : t;
}

// ─────────────────────────────────────────────────────────────────────────────
// Adresse
// ─────────────────────────────────────────────────────────────────────────────

/// Dialog zum Anlegen/Bearbeiten einer [ContactAddress]. Gibt bei „Speichern"
/// die Adresse zurück, sonst `null`.
Future<ContactAddress?> showAddressDialog(
  BuildContext context, {
  ContactAddress? existing,
}) {
  return showDialog<ContactAddress>(
    context: context,
    builder: (_) => _AddressDialog(existing: existing),
  );
}

class _AddressDialog extends StatefulWidget {
  const _AddressDialog({this.existing});
  final ContactAddress? existing;

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final _formKey = GlobalKey<FormState>();
  late AddressType _type;
  late final TextEditingController _label;
  late final TextEditingController _street;
  late final TextEditingController _houseNumber;
  late final TextEditingController _zip;
  late final TextEditingController _city;
  late final TextEditingController _country;
  late final TextEditingController _addressExtra;
  late final TextEditingController _postbox;
  late final TextEditingController _postboxZip;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _type = a?.type ?? AddressType.rechnung;
    _label = TextEditingController(text: a?.label ?? '');
    _street = TextEditingController(text: a?.street ?? '');
    _houseNumber = TextEditingController(text: a?.houseNumber ?? '');
    _zip = TextEditingController(text: a?.zip ?? '');
    _city = TextEditingController(text: a?.city ?? '');
    _country = TextEditingController(text: a?.country ?? 'Deutschland');
    _addressExtra = TextEditingController(text: a?.addressExtra ?? '');
    _postbox = TextEditingController(text: a?.postbox ?? '');
    _postboxZip = TextEditingController(text: a?.postboxZip ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _label,
      _street,
      _houseNumber,
      _zip,
      _city,
      _country,
      _addressExtra,
      _postbox,
      _postboxZip,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Neue Adresse' : 'Adresse bearbeiten'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<AddressType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Adresstyp *'),
                  items: [
                    for (final t in AddressType.values)
                      DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? AddressType.haupt),
                ),
                TextFormField(
                  controller: _label,
                  decoration: const InputDecoration(
                    labelText: 'Bezeichnung',
                    hintText: 'z. B. Niederlassung Berlin',
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _street,
                        decoration: const InputDecoration(labelText: 'Straße'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: TextFormField(
                        controller: _houseNumber,
                        decoration: const InputDecoration(labelText: 'Nr.'),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: TextFormField(
                        controller: _zip,
                        decoration: const InputDecoration(labelText: 'PLZ'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _city,
                        decoration: const InputDecoration(labelText: 'Ort'),
                      ),
                    ),
                  ],
                ),
                TextFormField(
                  controller: _country,
                  decoration: const InputDecoration(labelText: 'Land'),
                ),
                TextFormField(
                  controller: _addressExtra,
                  decoration: const InputDecoration(labelText: 'Adresszusatz'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _postbox,
                        decoration: const InputDecoration(labelText: 'Postfach'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 120,
                      child: TextFormField(
                        controller: _postboxZip,
                        decoration:
                            const InputDecoration(labelText: 'PLZ Postfach'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
            final country = _trim(_country.text) ?? 'Deutschland';
            Navigator.of(context).pop(ContactAddress(
              id: widget.existing?.id ?? _newId(),
              type: _type,
              label: _trim(_label.text),
              street: _trim(_street.text),
              houseNumber: _trim(_houseNumber.text),
              zip: _trim(_zip.text),
              city: _trim(_city.text),
              country: country,
              addressExtra: _trim(_addressExtra.text),
              postbox: _trim(_postbox.text),
              postboxZip: _trim(_postboxZip.text),
            ));
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bankverbindung
// ─────────────────────────────────────────────────────────────────────────────

/// Dialog zum Anlegen/Bearbeiten einer [BankAccount].
Future<BankAccount?> showBankAccountDialog(
  BuildContext context, {
  BankAccount? existing,
}) {
  return showDialog<BankAccount>(
    context: context,
    builder: (_) => _BankAccountDialog(existing: existing),
  );
}

class _BankAccountDialog extends StatefulWidget {
  const _BankAccountDialog({this.existing});
  final BankAccount? existing;

  @override
  State<_BankAccountDialog> createState() => _BankAccountDialogState();
}

class _BankAccountDialogState extends State<_BankAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _iban;
  late final TextEditingController _bic;
  late final TextEditingController _bankName;
  late final TextEditingController _accountHolder;
  late bool _deactivated;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _iban = TextEditingController(text: b?.iban ?? '');
    _bic = TextEditingController(text: b?.bic ?? '');
    _bankName = TextEditingController(text: b?.bankName ?? '');
    _accountHolder = TextEditingController(text: b?.accountHolder ?? '');
    _deactivated = b?.deactivated ?? false;
  }

  @override
  void dispose() {
    for (final c in [_iban, _bic, _bankName, _accountHolder]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Neue Bankverbindung'
          : 'Bankverbindung bearbeiten'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _iban,
                  decoration: const InputDecoration(
                    labelText: 'IBAN *',
                    hintText: 'DE89 3704 0044 0532 0130 00',
                  ),
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) {
                    final raw = (v ?? '').replaceAll(' ', '');
                    if (raw.isEmpty) return 'Pflichtfeld';
                    if (raw.length < 15) return 'IBAN zu kurz';
                    return null;
                  },
                ),
                TextFormField(
                  controller: _bic,
                  decoration: const InputDecoration(labelText: 'BIC'),
                  textCapitalization: TextCapitalization.characters,
                ),
                TextFormField(
                  controller: _bankName,
                  decoration: const InputDecoration(labelText: 'Bankname'),
                ),
                TextFormField(
                  controller: _accountHolder,
                  decoration: const InputDecoration(labelText: 'Kontoinhaber'),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _deactivated,
                  onChanged: (v) => setState(() => _deactivated = v),
                  title: const Text('Deaktiviert'),
                  subtitle: const Text('Konto wird nicht mehr verwendet.'),
                ),
              ],
            ),
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
            Navigator.of(context).pop(BankAccount(
              id: widget.existing?.id ?? _newId(),
              iban: _iban.text.replaceAll(' ', '').trim(),
              bic: _trim(_bic.text),
              bankName: _trim(_bankName.text),
              accountHolder: _trim(_accountHolder.text),
              deactivated: _deactivated,
            ));
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Kommunikationskanal
// ─────────────────────────────────────────────────────────────────────────────

/// Dialog zum Anlegen/Bearbeiten eines [CommunicationChannel].
Future<CommunicationChannel?> showChannelDialog(
  BuildContext context, {
  CommunicationChannel? existing,
}) {
  return showDialog<CommunicationChannel>(
    context: context,
    builder: (_) => _ChannelDialog(existing: existing),
  );
}

class _ChannelDialog extends StatefulWidget {
  const _ChannelDialog({this.existing});
  final CommunicationChannel? existing;

  @override
  State<_ChannelDialog> createState() => _ChannelDialogState();
}

// ─────────────────────────────────────────────────────────────────────────────
// DSGVO-Einwilligung
// ─────────────────────────────────────────────────────────────────────────────

/// Dialog zum Erfassen einer neuen [ContactConsent] (Einwilligung). Das Datum
/// ist der Erfassungszeitpunkt. Gibt den Consent zurück oder `null`.
Future<ContactConsent?> showConsentDialog(
  BuildContext context, {
  required DateTime now,
}) {
  return showDialog<ContactConsent>(
    context: context,
    builder: (_) => _ConsentDialog(now: now),
  );
}

class _ConsentDialog extends StatefulWidget {
  const _ConsentDialog({required this.now});
  final DateTime now;

  @override
  State<_ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends State<_ConsentDialog> {
  ConsentType _type = ConsentType.dataProcessing;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.shield_outlined),
      title: const Text('Einwilligung erfassen'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<ConsentType>(
              initialValue: _type,
              decoration:
                  const InputDecoration(labelText: 'Art der Einwilligung'),
              items: [
                for (final t in ConsentType.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (v) =>
                  setState(() => _type = v ?? ConsentType.dataProcessing),
            ),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Kontext / Grund',
                hintText: 'z. B. Telefonisches Einverständnis am …',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(ContactConsent(
              id: _newId(),
              consentType: _type,
              grantedAt: widget.now,
              note: _trim(_note.text),
            ));
          },
          child: const Text('Erfassen'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ansprechpartner-Verknüpfung (Firma ↔ Person)
// ─────────────────────────────────────────────────────────────────────────────

/// Dialog zum Verknüpfen/Bearbeiten eines Ansprechpartners (Referenz auf einen
/// Personen-Kontakt) an einer Firma. [availablePersons] sind die wählbaren
/// Personen-Kontakte.
Future<ContactPerson?> showContactPersonDialog(
  BuildContext context, {
  ContactPerson? existing,
  required List<Contact> availablePersons,
}) {
  return showDialog<ContactPerson>(
    context: context,
    builder: (_) => _ContactPersonDialog(
      existing: existing,
      availablePersons: availablePersons,
    ),
  );
}

class _ContactPersonDialog extends StatefulWidget {
  const _ContactPersonDialog({this.existing, required this.availablePersons});
  final ContactPerson? existing;
  final List<Contact> availablePersons;

  @override
  State<_ContactPersonDialog> createState() => _ContactPersonDialogState();
}

class _ContactPersonDialogState extends State<_ContactPersonDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _personId;
  late final TextEditingController _role;
  late bool _isPrimary;

  @override
  void initState() {
    super.initState();
    _personId = widget.existing?.personContactId;
    _role = TextEditingController(text: widget.existing?.role ?? '');
    _isPrimary = widget.existing?.isPrimary ?? false;
    // Fallback: falls die bestehende Person nicht (mehr) wählbar ist, trotzdem
    // anzeigen (defensive) — hier lassen wir _personId, das Dropdown ergänzt sie.
  }

  @override
  void dispose() {
    _role.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = [...widget.availablePersons];
    // Bestehende, nicht mehr gelistete Person defensiv aufnehmen.
    if (_personId != null && !options.any((c) => c.id == _personId)) {
      final existing =
          widget.availablePersons.where((c) => c.id == _personId).toList();
      if (existing.isEmpty) _personId = null;
    }
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Ansprechpartner zuordnen'
          : 'Ansprechpartner bearbeiten'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _personId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Person *'),
                items: [
                  for (final c in options)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(c.displayName, overflow: TextOverflow.ellipsis),
                    ),
                ],
                validator: (v) => v == null ? 'Bitte Person wählen' : null,
                onChanged: (v) => setState(() => _personId = v),
              ),
              TextFormField(
                controller: _role,
                decoration: const InputDecoration(
                  labelText: 'Rolle',
                  hintText: 'z. B. Geschäftsführer',
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _isPrimary,
                onChanged: (v) => setState(() => _isPrimary = v),
                title: const Text('Haupt-Ansprechpartner'),
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
            Navigator.of(context).pop(ContactPerson(
              id: widget.existing?.id ?? _newId(),
              personContactId: _personId!,
              role: _trim(_role.text),
              isPrimary: _isPrimary,
            ));
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

/// Dialog zur Auswahl der zugehörigen Firma (parentContactId) für einen
/// Personen-Kontakt. Gibt die gewählte Firmen-ID oder `null` (Abbruch) zurück;
/// eine leere Auswahl signalisiert der Aufrufer separat.
Future<String?> showCompanyPickerDialog(
  BuildContext context, {
  required List<Contact> companies,
  String? selectedId,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CompanyPickerDialog(
      companies: companies,
      selectedId: selectedId,
    ),
  );
}

class _CompanyPickerDialog extends StatefulWidget {
  const _CompanyPickerDialog({required this.companies, this.selectedId});
  final List<Contact> companies;
  final String? selectedId;

  @override
  State<_CompanyPickerDialog> createState() => _CompanyPickerDialogState();
}

class _CompanyPickerDialogState extends State<_CompanyPickerDialog> {
  String? _companyId;

  @override
  void initState() {
    super.initState();
    _companyId = widget.selectedId;
    if (_companyId != null &&
        !widget.companies.any((c) => c.id == _companyId)) {
      _companyId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Zugehörige Firma'),
      content: SizedBox(
        width: 480,
        child: DropdownButtonFormField<String>(
          initialValue: _companyId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Firma *'),
          items: [
            for (final c in widget.companies)
              DropdownMenuItem(
                value: c.id,
                child: Text(c.displayName, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _companyId = v),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _companyId == null
              ? null
              : () => Navigator.of(context).pop(_companyId),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

class _ChannelDialogState extends State<_ChannelDialog> {
  final _formKey = GlobalKey<FormState>();
  late ChannelType _type;
  late CommunicationContext _context;
  late bool _isPrimary;
  late final TextEditingController _value;
  late final TextEditingController _label;
  late final TextEditingController _availability;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _type = c?.type ?? ChannelType.email;
    _context = c?.context ?? CommunicationContext.dienst;
    _isPrimary = c?.isPrimary ?? false;
    _value = TextEditingController(text: c?.value ?? '');
    _label = TextEditingController(text: c?.label ?? '');
    _availability = TextEditingController(text: c?.availability ?? '');
  }

  @override
  void dispose() {
    for (final c in [_value, _label, _availability]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Neuer Kanal' : 'Kanal bearbeiten'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<ChannelType>(
                        initialValue: _type,
                        decoration: const InputDecoration(labelText: 'Art'),
                        items: [
                          for (final t in ChannelType.values)
                            DropdownMenuItem(value: t, child: Text(t.label)),
                        ],
                        onChanged: (v) =>
                            setState(() => _type = v ?? ChannelType.email),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<CommunicationContext>(
                        initialValue: _context,
                        decoration: const InputDecoration(labelText: 'Kontext'),
                        items: [
                          for (final c in CommunicationContext.values)
                            DropdownMenuItem(value: c, child: Text(c.label)),
                        ],
                        onChanged: (v) => setState(
                            () => _context = v ?? CommunicationContext.dienst),
                      ),
                    ),
                  ],
                ),
                TextFormField(
                  controller: _value,
                  decoration: const InputDecoration(labelText: 'Wert *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null,
                ),
                TextFormField(
                  controller: _label,
                  decoration: const InputDecoration(
                    labelText: 'Bezeichnung',
                    hintText: 'z. B. Sekretariat',
                  ),
                ),
                TextFormField(
                  controller: _availability,
                  decoration: const InputDecoration(
                    labelText: 'Erreichbarkeit',
                    hintText: 'z. B. Mo–Fr 9–17 Uhr',
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _isPrimary,
                  onChanged: (v) => setState(() => _isPrimary = v),
                  title: const Text('Primärer Kanal'),
                ),
              ],
            ),
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
            Navigator.of(context).pop(CommunicationChannel(
              type: _type,
              value: _value.text.trim(),
              context: _context,
              label: _trim(_label.text),
              availability: _trim(_availability.text),
              isPrimary: _isPrimary,
            ));
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
