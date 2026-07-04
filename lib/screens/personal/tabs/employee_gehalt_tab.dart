import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/money.dart';
import '../../../models/employee_profile.dart';
import '../../../models/employment_contract.dart';
import '../../../models/payroll_extras.dart';
import '../../../models/payroll_profile.dart';
import '../../../models/payroll_record.dart';
import '../../../providers/personal_provider.dart';
import '../../../providers/team_provider.dart';
import '../../../ui/ui.dart';
import '../../../widgets/info_row.dart';

/// Gehalt-Tab der Mitarbeiter-Detailseite — **AllTec-1:1** (`employee_gehalt_tab`):
/// vier Karten — Gehaltsdaten, VWL, Zulagen (Liste), Bankverbindungen (Liste).
/// Gehaltsdaten liest aus [EmploymentContract] (Brutto/Stundensatz/Typ,
/// read-only) + [PayrollProfile] (Steuer) + [EmployeeProfile] (Steuer-ID/SV/KK/
/// Entgeltgruppe). VWL/Zulagen/Bank sind auf dem [EmployeeProfile] eingebettet.
class EmployeeGehaltTab extends StatelessWidget {
  const EmployeeGehaltTab({super.key, required this.userId});

  final String userId;

  static final _df = DateFormat('dd.MM.yyyy', 'de_DE');
  static String _v(String? s) =>
      (s == null || s.trim().isEmpty) ? '—' : s.trim();
  static String _cents(int? c) => c == null ? '—' : Money(c).format();

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final team = context.watch<TeamProvider>();
    final p = personal.employeeProfileForUser(userId) ??
        EmployeeProfile(orgId: '', userId: userId);
    final payroll = personal.profileForUser(userId) ??
        PayrollProfile(orgId: '', userId: userId);
    EmploymentContract? contract;
    for (final c in team.contracts) {
      if (c.userId == userId) {
        contract = c;
        break;
      }
    }

    Future<void> saveProfile(EmployeeProfile updated) =>
        personal.saveEmployeeProfile(updated);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Gehaltsdaten ────────────────────────────────────────────────
        AppSectionCard(
          title: 'Gehaltsdaten',
          icon: Icons.euro_outlined,
          trailing: _Edit(onPressed: () async {
            final r = await showDialog<_GehaltResult>(
              context: context,
              builder: (_) => _GehaltDialog(profile: p, payroll: payroll),
            );
            if (r != null) {
              await personal.savePayrollProfile(r.payroll);
              await personal.saveEmployeeProfile(r.profile);
            }
          }),
          child: Column(
            children: [
              InfoRow(
                  label: 'Gehaltstyp',
                  value: contract?.salaryKind.label ?? '—'),
              InfoRow(
                  label: 'Bruttogehalt',
                  value: _cents(
                      contract?.monthlyGrossCents ?? payroll.monthlyGrossCents)),
              InfoRow(
                label: 'Stundensatz',
                value: contract != null && contract.salaryKind == SalaryKind.hourly
                    ? Money.fromEuros(contract.hourlyRate).format()
                    : '—',
              ),
              InfoRow(label: 'Steuerklasse', value: payroll.taxClass.label),
              InfoRow(label: 'Beschäftigungsart', value: payroll.kind.label),
              InfoRow(label: 'Steuer-ID', value: _v(p.taxId)),
              InfoRow(label: 'SV-Nummer', value: _v(p.socialSecurityNumber)),
              InfoRow(label: 'Krankenkasse', value: _v(p.healthInsurance)),
              InfoRow(
                  label: 'KK-Art',
                  value: p.healthInsuranceType?.label ?? '—'),
              InfoRow(
                  label: 'Kirchensteuer',
                  value: payroll.churchTax ? 'Ja' : 'Nein'),
              InfoRow(label: 'Entgeltgruppe', value: _v(p.entgeltgruppe)),
              InfoRow(
                  label: 'Gültig ab',
                  value: p.gehaltGueltigAb != null
                      ? _df.format(p.gehaltGueltigAb!)
                      : '—'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── VWL ─────────────────────────────────────────────────────────
        AppSectionCard(
          title: 'Vermögenswirksame Leistungen',
          icon: Icons.savings_outlined,
          trailing: _Edit(onPressed: () async {
            final r = await showDialog<VwlData>(
              context: context,
              builder: (_) => _VwlDialog(existing: p.vwl),
            );
            if (r != null) {
              await saveProfile(
                  p.copyWith(vwl: r.isEmpty ? null : r, clearVwl: r.isEmpty));
            }
          }),
          child: p.vwl == null
              ? const _Hint('Keine VWL-Daten vorhanden.')
              : Column(
                  children: [
                    InfoRow(
                        label: 'AG-Anteil',
                        value: _cents(p.vwl!.arbeitgeberAnteilCents)),
                    InfoRow(
                        label: 'AN-Anteil',
                        value: _cents(p.vwl!.arbeitnehmerAnteilCents)),
                    InfoRow(label: 'Institut', value: _v(p.vwl!.institut)),
                    InfoRow(
                        label: 'Vertragsnr.',
                        value: _v(p.vwl!.vertragsnummer)),
                    InfoRow(
                        label: 'Beginn',
                        value: p.vwl!.vertragBeginn != null
                            ? _df.format(p.vwl!.vertragBeginn!)
                            : '—'),
                    InfoRow(
                        label: 'Ende',
                        value: p.vwl!.vertragEnde != null
                            ? _df.format(p.vwl!.vertragEnde!)
                            : '—'),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        // ── Zulagen ─────────────────────────────────────────────────────
        AppSectionCard(
          title: 'Zulagen',
          icon: Icons.add_card_outlined,
          trailing: IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Zulage hinzufügen',
            onPressed: () async {
              final r = await showDialog<SalaryAllowance>(
                context: context,
                builder: (_) => const _ZulageDialog(),
              );
              if (r != null) {
                await saveProfile(
                    p.copyWith(zulagen: [...p.zulagen, r]));
              }
            },
          ),
          child: p.zulagen.isEmpty
              ? const _Hint('Keine Zulagen vorhanden.')
              : Column(
                  children: [
                    for (final z in p.zulagen)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(z.bezeichnung.isEmpty
                            ? 'Zulage'
                            : z.bezeichnung),
                        subtitle: Text([
                          if (z.betragCents != null)
                            Money(z.betragCents!).format(),
                          if (z.prozentsatz != null)
                            '${z.prozentsatz!.toStringAsFixed(1)}%',
                          if (z.bemerkung != null && z.bemerkung!.isNotEmpty)
                            z.bemerkung!,
                        ].join(' · ')),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outlined),
                          tooltip: 'Löschen',
                          onPressed: () async {
                            await saveProfile(p.copyWith(
                                zulagen: p.zulagen
                                    .where((e) => e.id != z.id)
                                    .toList()));
                          },
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        // ── Bankverbindungen ────────────────────────────────────────────
        AppSectionCard(
          title: 'Bankverbindungen',
          icon: Icons.account_balance_outlined,
          trailing: IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Bankverbindung hinzufügen',
            onPressed: () async {
              final r = await showDialog<BankAccount>(
                context: context,
                builder: (_) =>
                    _BankDialog(isFirst: p.bankAccounts.isEmpty),
              );
              if (r != null) {
                await saveProfile(
                    p.copyWith(bankAccounts: [...p.bankAccounts, r]));
              }
            },
          ),
          child: p.bankAccounts.isEmpty
              ? const _Hint('Keine Bankverbindungen hinterlegt.')
              : Column(
                  children: [
                    for (final b in p.bankAccounts)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(b.isPrimary
                            ? Icons.account_balance
                            : Icons.account_balance_outlined),
                        title: Text(_v(b.iban)),
                        subtitle: Text([
                          if (b.kontoinhaber != null &&
                              b.kontoinhaber!.isNotEmpty)
                            b.kontoinhaber!,
                          if (b.bankname != null && b.bankname!.isNotEmpty)
                            b.bankname!,
                          if (b.bic != null && b.bic!.isNotEmpty) 'BIC: ${b.bic}',
                        ].join(' · ')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (b.isPrimary)
                              const Chip(
                                label: Text('Haupt'),
                                visualDensity: VisualDensity.compact,
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outlined),
                              tooltip: 'Löschen',
                              onPressed: () async {
                                await saveProfile(p.copyWith(
                                    bankAccounts: p.bankAccounts
                                        .where((e) => e.id != b.id)
                                        .toList()));
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Edit extends StatelessWidget {
  const _Edit({required this.onPressed});
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
      icon: const Icon(Icons.edit_outlined),
      tooltip: 'Bearbeiten',
      onPressed: onPressed);
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

int? _euroToCents(String s) {
  final t = s.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  return v == null ? null : Money.fromEuros(v).cents;
}

String _centsInput(int? c) =>
    c == null ? '' : (c / 100).toStringAsFixed(2).replaceAll('.', ',');

/// Ergebnis des Gehaltsdaten-Dialogs: PayrollProfile + EmployeeProfile.
class _GehaltResult {
  const _GehaltResult(this.payroll, this.profile);
  final PayrollProfile payroll;
  final EmployeeProfile profile;
}

class _GehaltDialog extends StatefulWidget {
  const _GehaltDialog({required this.profile, required this.payroll});
  final EmployeeProfile profile;
  final PayrollProfile payroll;

  @override
  State<_GehaltDialog> createState() => _GehaltDialogState();
}

class _GehaltDialogState extends State<_GehaltDialog> {
  late TaxClass _taxClass;
  late PayrollEmploymentKind _kind;
  late bool _churchTax;
  HealthInsuranceType? _kkArt;
  late final TextEditingController _steuerId;
  late final TextEditingController _svNr;
  late final TextEditingController _kk;
  late final TextEditingController _entgelt;

  @override
  void initState() {
    super.initState();
    _taxClass = widget.payroll.taxClass;
    _kind = widget.payroll.kind;
    _churchTax = widget.payroll.churchTax;
    _kkArt = widget.profile.healthInsuranceType;
    _steuerId = TextEditingController(text: widget.profile.taxId ?? '');
    _svNr =
        TextEditingController(text: widget.profile.socialSecurityNumber ?? '');
    _kk = TextEditingController(text: widget.profile.healthInsurance ?? '');
    _entgelt = TextEditingController(text: widget.profile.entgeltgruppe ?? '');
  }

  @override
  void dispose() {
    _steuerId.dispose();
    _svNr.dispose();
    _kk.dispose();
    _entgelt.dispose();
    super.dispose();
  }

  void _save() {
    final payroll = widget.payroll.copyWith(
      taxClass: _taxClass,
      kind: _kind,
      churchTax: _churchTax,
    );
    final profile = widget.profile.copyWith(
      taxId: _steuerId.text.trim(),
      socialSecurityNumber: _svNr.text.trim(),
      healthInsurance: _kk.text.trim(),
      healthInsuranceType: _kkArt,
      entgeltgruppe: _entgelt.text.trim(),
    );
    Navigator.of(context).pop(_GehaltResult(payroll, profile));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gehalt bearbeiten'),
      content: SizedBox(
        width: math.min(520, MediaQuery.sizeOf(context).width - 64),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<TaxClass>(
                initialValue: _taxClass,
                decoration: const InputDecoration(labelText: 'Steuerklasse'),
                items: [
                  for (final t in TaxClass.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (v) => setState(() => _taxClass = v ?? _taxClass),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<PayrollEmploymentKind>(
                initialValue: _kind,
                decoration:
                    const InputDecoration(labelText: 'Beschäftigungsart'),
                items: [
                  for (final k in PayrollEmploymentKind.values)
                    DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged: (v) => setState(() => _kind = v ?? _kind),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<HealthInsuranceType?>(
                initialValue: _kkArt,
                decoration: const InputDecoration(labelText: 'KK-Art'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  for (final h in HealthInsuranceType.values)
                    DropdownMenuItem(value: h, child: Text(h.label)),
                ],
                onChanged: (v) => setState(() => _kkArt = v),
              ),
              TextField(
                  controller: _steuerId,
                  decoration: const InputDecoration(labelText: 'Steuer-ID')),
              TextField(
                  controller: _svNr,
                  decoration: const InputDecoration(labelText: 'SV-Nr.')),
              TextField(
                  controller: _kk,
                  decoration: const InputDecoration(labelText: 'Krankenkasse')),
              TextField(
                  controller: _entgelt,
                  decoration: const InputDecoration(labelText: 'Entgeltgruppe')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Kirchensteuer'),
                value: _churchTax,
                onChanged: (v) => setState(() => _churchTax = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen')),
        FilledButton(onPressed: _save, child: const Text('Speichern')),
      ],
    );
  }
}

class _VwlDialog extends StatefulWidget {
  const _VwlDialog({this.existing});
  final VwlData? existing;
  @override
  State<_VwlDialog> createState() => _VwlDialogState();
}

class _VwlDialogState extends State<_VwlDialog> {
  late final TextEditingController _ag;
  late final TextEditingController _an;
  late final TextEditingController _institut;
  late final TextEditingController _vertragsnr;

  @override
  void initState() {
    super.initState();
    final v = widget.existing;
    _ag = TextEditingController(text: _centsInput(v?.arbeitgeberAnteilCents));
    _an = TextEditingController(text: _centsInput(v?.arbeitnehmerAnteilCents));
    _institut = TextEditingController(text: v?.institut ?? '');
    _vertragsnr = TextEditingController(text: v?.vertragsnummer ?? '');
  }

  @override
  void dispose() {
    _ag.dispose();
    _an.dispose();
    _institut.dispose();
    _vertragsnr.dispose();
    super.dispose();
  }

  void _save() {
    final r = VwlData(
      arbeitgeberAnteilCents: _euroToCents(_ag.text),
      arbeitnehmerAnteilCents: _euroToCents(_an.text),
      institut: _institut.text.trim().isEmpty ? null : _institut.text.trim(),
      vertragsnummer:
          _vertragsnr.text.trim().isEmpty ? null : _vertragsnr.text.trim(),
      vertragBeginn: widget.existing?.vertragBeginn,
      vertragEnde: widget.existing?.vertragEnde,
    );
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('VWL bearbeiten'),
      content: SizedBox(
        width: math.min(440, MediaQuery.sizeOf(context).width - 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: _ag,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'AG-Anteil (€)')),
            TextField(
                controller: _an,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'AN-Anteil (€)')),
            TextField(
                controller: _institut,
                decoration: const InputDecoration(labelText: 'Institut')),
            TextField(
                controller: _vertragsnr,
                decoration: const InputDecoration(labelText: 'Vertragsnummer')),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen')),
        FilledButton(onPressed: _save, child: const Text('Speichern')),
      ],
    );
  }
}

class _ZulageDialog extends StatefulWidget {
  const _ZulageDialog();
  @override
  State<_ZulageDialog> createState() => _ZulageDialogState();
}

class _ZulageDialogState extends State<_ZulageDialog> {
  final _formKey = GlobalKey<FormState>();
  final _bezeichnung = TextEditingController();
  final _betrag = TextEditingController();
  final _bemerkung = TextEditingController();

  @override
  void dispose() {
    _bezeichnung.dispose();
    _betrag.dispose();
    _bemerkung.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final r = SalaryAllowance(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      bezeichnung: _bezeichnung.text.trim(),
      betragCents: _euroToCents(_betrag.text),
      bemerkung:
          _bemerkung.text.trim().isEmpty ? null : _bemerkung.text.trim(),
    );
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Zulage hinzufügen'),
      content: SizedBox(
        width: math.min(440, MediaQuery.sizeOf(context).width - 64),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _bezeichnung,
                decoration: const InputDecoration(labelText: 'Bezeichnung *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null,
              ),
              TextField(
                  controller: _betrag,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Betrag (€)')),
              TextField(
                  controller: _bemerkung,
                  decoration: const InputDecoration(labelText: 'Bemerkung')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen')),
        FilledButton(onPressed: _save, child: const Text('Hinzufügen')),
      ],
    );
  }
}

class _BankDialog extends StatefulWidget {
  const _BankDialog({required this.isFirst});
  final bool isFirst;
  @override
  State<_BankDialog> createState() => _BankDialogState();
}

class _BankDialogState extends State<_BankDialog> {
  final _formKey = GlobalKey<FormState>();
  final _kontoinhaber = TextEditingController();
  final _iban = TextEditingController();
  final _bic = TextEditingController();
  final _bank = TextEditingController();

  @override
  void dispose() {
    _kontoinhaber.dispose();
    _iban.dispose();
    _bic.dispose();
    _bank.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    String? t(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final r = BankAccount(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      kontoinhaber: t(_kontoinhaber),
      iban: t(_iban),
      bic: t(_bic),
      bankname: t(_bank),
      isPrimary: widget.isFirst,
    );
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bankverbindung hinzufügen'),
      content: SizedBox(
        width: math.min(480, MediaQuery.sizeOf(context).width - 64),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: _kontoinhaber,
                  decoration: const InputDecoration(labelText: 'Kontoinhaber')),
              TextFormField(
                controller: _iban,
                decoration: const InputDecoration(labelText: 'IBAN *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                        controller: _bic,
                        decoration: const InputDecoration(labelText: 'BIC')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                        controller: _bank,
                        decoration: const InputDecoration(labelText: 'Bank')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen')),
        FilledButton(onPressed: _save, child: const Text('Hinzufügen')),
      ],
    );
  }
}
