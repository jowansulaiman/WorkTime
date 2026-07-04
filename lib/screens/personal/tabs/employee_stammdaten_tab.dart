import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/employee_profile.dart';
import '../../../providers/personal_provider.dart';
import '../../../ui/ui.dart';
import '../../../widgets/info_row.dart';

/// Stammdaten-Tab der Mitarbeiter-Detailseite — **AllTec-1:1**
/// (`employee_stammdaten_tab`): vier Read-Only-Karten (Stammdaten · Status &
/// Vereinbarungen · Klassifizierungen · Arbeitszeit) mit je einem
/// Bearbeiten-Dialog (Arbeitszeit read-only, Quelle Zeitwirtschaft/SollzeitProfile).
///
/// Schreibpfad: [PersonalProvider.saveEmployeeProfile] (baut die volle Akte via
/// `copyWith` neu auf; DSGVO-Art.-9-Felder bewusst nicht erfasst).
class EmployeeStammdatenTab extends StatelessWidget {
  const EmployeeStammdatenTab({super.key, required this.userId});

  final String userId;

  static final _df = DateFormat('dd.MM.yyyy', 'de_DE');

  static String _v(String? value) =>
      (value == null || value.trim().isEmpty) ? '—' : value.trim();
  static String _d(DateTime? d) => d == null ? '—' : _df.format(d);
  static String _ja(bool? b) => b == true ? 'Ja' : 'Nein';

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final p = personal.employeeProfileForUser(userId);

    Future<void> save(EmployeeProfile updated) =>
        personal.saveEmployeeProfile(updated);

    final base = p ?? EmployeeProfile(orgId: '', userId: userId);

    String kfrist() {
      if (p?.kuendigungsfristWert == null && p?.kuendigungsfristTyp == null) {
        return '—';
      }
      return [
        if (p?.kuendigungsfristWert != null) '${p!.kuendigungsfristWert}',
        if (p?.kuendigungsfristTyp != null) p!.kuendigungsfristTyp!.label,
      ].join(' ');
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Karte 1: Stammdaten ──────────────────────────────────────────
        AppSectionCard(
          title: 'Stammdaten',
          icon: Icons.person_outline,
          trailing: _EditButton(onPressed: () async {
            final r = await showDialog<EmployeeProfile>(
              context: context,
              builder: (_) => _StammdatenDialog(base: base),
            );
            if (r != null) await save(r);
          }),
          child: Column(
            children: [
              InfoRow(label: 'Kürzel', value: _v(p?.kuerzel)),
              InfoRow(label: 'Personalnummer', value: _v(p?.personnelNumber)),
              InfoRow(
                  label: 'Familienstand',
                  value: p?.maritalStatus?.label ?? '—'),
              InfoRow(label: 'Anzahl Kinder', value: '${p?.childrenCount ?? 0}'),
              InfoRow(
                  label: 'Personengruppe',
                  value: p?.personnelGroup?.label ?? '—'),
              InfoRow(label: 'Nationalität', value: _v(p?.nationality)),
              InfoRow(label: 'Geburtsort', value: _v(p?.geburtsort)),
              InfoRow(label: 'Konfession', value: p?.confession?.label ?? '—'),
              InfoRow(label: 'Geburtsname', value: _v(p?.geburtsname)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── Karte 2: Status & Vereinbarungen ─────────────────────────────
        AppSectionCard(
          title: 'Status & Vereinbarungen',
          icon: Icons.assignment_outlined,
          trailing: _EditButton(onPressed: () async {
            final r = await showDialog<EmployeeProfile>(
              context: context,
              builder: (_) => _StatusDialog(base: base),
            );
            if (r != null) await save(r);
          }),
          child: Column(
            children: [
              InfoRow(label: 'Status', value: (p ?? base).status.label),
              InfoRow(label: 'Eintrittsdatum', value: _d(p?.hireDate)),
              InfoRow(label: 'Erwerbsart', value: p?.erwerbsart?.label ?? '—'),
              InfoRow(
                  label: 'Teilnahme Zeiterfassung',
                  value: _ja(p?.teilnahmeZeiterfassung)),
              InfoRow(
                  label: 'Automatische Buchung', value: _ja(p?.autoBuchung)),
              InfoRow(label: 'Probezeit bis', value: _d(p?.probationEnd)),
              InfoRow(label: 'Befristung bis', value: _d(p?.limitedUntil)),
              InfoRow(label: 'Langzeitkrank ab', value: _d(p?.langzeitkrankAb)),
              InfoRow(
                  label: 'Letzter Arbeitstag', value: _d(p?.letzterArbeitstag)),
              InfoRow(label: 'Kündigungsfrist', value: kfrist()),
              InfoRow(
                  label: 'Kündigungsfrist-Anmerkung',
                  value: _v(p?.kuendigungsfristAnmerkung)),
              InfoRow(label: 'Kündigungsdatum', value: _d(p?.kuendigungsDatum)),
              InfoRow(label: 'Kündigungsgrund', value: _v(p?.kuendigungsgrund)),
              InfoRow(label: 'Austrittsdatum', value: _d(p?.exitDate)),
              InfoRow(label: 'Austrittsgrund', value: _v(p?.austrittsgrund)),
              InfoRow(
                  label: 'Austrittsmodalitäten',
                  value: _v(p?.austrittsmodalitaeten)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── Karte 3: Klassifizierungen ───────────────────────────────────
        AppSectionCard(
          title: 'Klassifizierungen',
          icon: Icons.account_tree_outlined,
          trailing: _EditButton(onPressed: () async {
            final r = await showDialog<EmployeeProfile>(
              context: context,
              builder: (_) => _KlassifizierungDialog(base: base),
            );
            if (r != null) await save(r);
          }),
          child: Column(
            children: [
              InfoRow(label: 'Abteilung', value: _v(p?.abteilung)),
              InfoRow(label: 'Position', value: _v(p?.position)),
              InfoRow(label: 'Vorgesetzter', value: _v(p?.vorgesetzterName)),
              InfoRow(label: 'Vertreter', value: _v(p?.vertreterName)),
              InfoRow(label: 'Kostenstelle', value: _v(p?.kostenstelle)),
              InfoRow(
                label: 'Produktive Zeit',
                value: p?.produktiveZeitProzent != null
                    ? '${p!.produktiveZeitProzent!.toStringAsFixed(0)}%'
                    : '—',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── Karte 4: Arbeitszeit (read-only; Quelle Zeitwirtschaft) ──────
        AppSectionCard(
          title: 'Arbeitszeit',
          icon: Icons.schedule_outlined,
          child: Column(
            children: [
              InfoRow(
                label: 'FTE-Faktor',
                value: p?.fteFaktor != null
                    ? p!.fteFaktor!.toStringAsFixed(2)
                    : '—',
              ),
              InfoRow(
                label: 'Urlaubstage / Jahr',
                value: p?.annualVacationDays != null
                    ? '${p!.annualVacationDays}'
                    : '—',
              ),
              InfoRow(
                  label: 'Teilnahme Zeiterfassung',
                  value: _ja(p?.teilnahmeZeiterfassung)),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditButton extends StatelessWidget {
  const _EditButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        icon: const Icon(Icons.edit_outlined),
        tooltip: 'Bearbeiten',
        onPressed: onPressed,
      );
}

// ─────────────────────────── Dialog-Helfer ──────────────────────────────

double? _parseDouble(String s) {
  final t = s.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

/// Datums-Zeile mit Auswahl + optionalem Leeren (analog AllTec DatePicker-Row).
class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onPick,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;
  final VoidCallback? onClear;

  static final _df = DateFormat('dd.MM.yyyy', 'de_DE');

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value != null ? _df.format(value!) : '—'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null && onClear != null)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Leeren',
              onPressed: onClear,
            ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                locale: const Locale('de', 'DE'),
              );
              if (picked != null) onPick(picked);
            },
          ),
        ],
      ),
    );
  }
}

/// Dialog 1 — Stammdaten bearbeiten.
class _StammdatenDialog extends StatefulWidget {
  const _StammdatenDialog({required this.base});
  final EmployeeProfile base;

  @override
  State<_StammdatenDialog> createState() => _StammdatenDialogState();
}

class _StammdatenDialogState extends State<_StammdatenDialog> {
  late final TextEditingController _kuerzel;
  late final TextEditingController _personalnr;
  late final TextEditingController _nationalitaet;
  late final TextEditingController _geburtsort;
  late final TextEditingController _geburtsname;
  late final TextEditingController _kinder;
  MaritalStatus? _familienstand;
  PersonnelGroup? _personengruppe;
  Confession? _konfession;

  @override
  void initState() {
    super.initState();
    final b = widget.base;
    _kuerzel = TextEditingController(text: b.kuerzel ?? '');
    _personalnr = TextEditingController(text: b.personnelNumber ?? '');
    _nationalitaet = TextEditingController(text: b.nationality ?? '');
    _geburtsort = TextEditingController(text: b.geburtsort ?? '');
    _geburtsname = TextEditingController(text: b.geburtsname ?? '');
    _kinder = TextEditingController(text: '${b.childrenCount}');
    _familienstand = b.maritalStatus;
    _personengruppe = b.personnelGroup;
    _konfession = b.confession;
  }

  @override
  void dispose() {
    _kuerzel.dispose();
    _personalnr.dispose();
    _nationalitaet.dispose();
    _geburtsort.dispose();
    _geburtsname.dispose();
    _kinder.dispose();
    super.dispose();
  }

  void _save() {
    final r = widget.base.copyWith(
      kuerzel: _kuerzel.text.trim(),
      personnelNumber: _personalnr.text.trim(),
      nationality: _nationalitaet.text.trim(),
      geburtsort: _geburtsort.text.trim(),
      geburtsname: _geburtsname.text.trim(),
      childrenCount: int.tryParse(_kinder.text.trim()) ?? 0,
      maritalStatus: _familienstand,
      clearMaritalStatus: _familienstand == null,
      personnelGroup: _personengruppe,
      clearPersonnelGroup: _personengruppe == null,
      confession: _konfession,
      clearConfession: _konfession == null,
    );
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Stammdaten bearbeiten'),
      content: SizedBox(
        width: math.min(560, MediaQuery.sizeOf(context).width - 64),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _kuerzel,
                maxLength: 8,
                decoration: const InputDecoration(labelText: 'Kürzel'),
              ),
              TextField(
                controller: _personalnr,
                maxLength: 16,
                decoration: const InputDecoration(labelText: 'Personalnummer'),
              ),
              DropdownButtonFormField<MaritalStatus?>(
                initialValue: _familienstand,
                decoration: const InputDecoration(labelText: 'Familienstand'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  for (final m in MaritalStatus.values)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
                onChanged: (v) => setState(() => _familienstand = v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _kinder,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Anzahl Kinder'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<PersonnelGroup?>(
                initialValue: _personengruppe,
                decoration: const InputDecoration(labelText: 'Personengruppe'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  for (final g in PersonnelGroup.values)
                    DropdownMenuItem(value: g, child: Text(g.label)),
                ],
                onChanged: (v) => setState(() => _personengruppe = v),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<Confession?>(
                initialValue: _konfession,
                decoration: const InputDecoration(labelText: 'Konfession'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  for (final c in Confession.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (v) => setState(() => _konfession = v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nationalitaet,
                decoration: const InputDecoration(labelText: 'Nationalität'),
              ),
              TextField(
                controller: _geburtsort,
                decoration: const InputDecoration(labelText: 'Geburtsort'),
              ),
              TextField(
                controller: _geburtsname,
                decoration: const InputDecoration(labelText: 'Geburtsname'),
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

/// Dialog 2 — Status & Vereinbarungen.
class _StatusDialog extends StatefulWidget {
  const _StatusDialog({required this.base});
  final EmployeeProfile base;

  @override
  State<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<_StatusDialog> {
  late EmployeeStatus _status;
  Erwerbsart? _erwerbsart;
  KuendigungsfristTyp? _kfristTyp;
  DateTime? _eintritt;
  DateTime? _probezeit;
  DateTime? _befristung;
  DateTime? _langzeitkrank;
  DateTime? _letzterTag;
  DateTime? _kuendigung;
  DateTime? _austritt;
  late final TextEditingController _kfristWert;
  late final TextEditingController _kfristAnm;
  late final TextEditingController _kuendigungsgrund;
  late final TextEditingController _austrittsgrund;
  late final TextEditingController _austrittsmod;
  bool _teilnahme = false;
  bool _autoBuchung = false;

  @override
  void initState() {
    super.initState();
    final b = widget.base;
    _status = b.status;
    _erwerbsart = b.erwerbsart;
    _kfristTyp = b.kuendigungsfristTyp;
    _eintritt = b.hireDate;
    _probezeit = b.probationEnd;
    _befristung = b.limitedUntil;
    _langzeitkrank = b.langzeitkrankAb;
    _letzterTag = b.letzterArbeitstag;
    _kuendigung = b.kuendigungsDatum;
    _austritt = b.exitDate;
    _kfristWert = TextEditingController(
        text: b.kuendigungsfristWert != null
            ? '${b.kuendigungsfristWert}'
            : '');
    _kfristAnm = TextEditingController(text: b.kuendigungsfristAnmerkung ?? '');
    _kuendigungsgrund = TextEditingController(text: b.kuendigungsgrund ?? '');
    _austrittsgrund = TextEditingController(text: b.austrittsgrund ?? '');
    _austrittsmod = TextEditingController(text: b.austrittsmodalitaeten ?? '');
    _teilnahme = b.teilnahmeZeiterfassung ?? false;
    _autoBuchung = b.autoBuchung ?? false;
  }

  @override
  void dispose() {
    _kfristWert.dispose();
    _kfristAnm.dispose();
    _kuendigungsgrund.dispose();
    _austrittsgrund.dispose();
    _austrittsmod.dispose();
    super.dispose();
  }

  void _save() {
    final wert = int.tryParse(_kfristWert.text.trim());
    final r = widget.base.copyWith(
      status: _status,
      erwerbsart: _erwerbsart,
      clearErwerbsart: _erwerbsart == null,
      hireDate: _eintritt,
      clearHireDate: _eintritt == null,
      probationEnd: _probezeit,
      clearProbationEnd: _probezeit == null,
      limitedUntil: _befristung,
      clearLimitedUntil: _befristung == null,
      langzeitkrankAb: _langzeitkrank,
      clearLangzeitkrankAb: _langzeitkrank == null,
      letzterArbeitstag: _letzterTag,
      clearLetzterArbeitstag: _letzterTag == null,
      kuendigungsDatum: _kuendigung,
      clearKuendigungsDatum: _kuendigung == null,
      exitDate: _austritt,
      clearExitDate: _austritt == null,
      kuendigungsfristWert: wert,
      clearKuendigungsfristWert: wert == null,
      kuendigungsfristTyp: _kfristTyp,
      clearKuendigungsfristTyp: _kfristTyp == null,
      kuendigungsfristAnmerkung: _kfristAnm.text.trim(),
      kuendigungsgrund: _kuendigungsgrund.text.trim(),
      austrittsgrund: _austrittsgrund.text.trim(),
      austrittsmodalitaeten: _austrittsmod.text.trim(),
      teilnahmeZeiterfassung: _teilnahme,
      autoBuchung: _autoBuchung,
    );
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Status & Vereinbarungen'),
      content: SizedBox(
        width: math.min(620, MediaQuery.sizeOf(context).width - 64),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<EmployeeStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  for (final s in EmployeeStatus.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<Erwerbsart?>(
                initialValue: _erwerbsart,
                decoration: const InputDecoration(labelText: 'Erwerbsart'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  for (final e in Erwerbsart.values)
                    DropdownMenuItem(value: e, child: Text(e.label)),
                ],
                onChanged: (v) => setState(() => _erwerbsart = v),
              ),
              _DateTile(
                label: 'Eintrittsdatum',
                value: _eintritt,
                onPick: (d) => setState(() => _eintritt = d),
                onClear: () => setState(() => _eintritt = null),
              ),
              _DateTile(
                label: 'Probezeit bis',
                value: _probezeit,
                onPick: (d) => setState(() => _probezeit = d),
                onClear: () => setState(() => _probezeit = null),
              ),
              _DateTile(
                label: 'Befristung bis',
                value: _befristung,
                onPick: (d) => setState(() => _befristung = d),
                onClear: () => setState(() => _befristung = null),
              ),
              _DateTile(
                label: 'Langzeitkrank ab',
                value: _langzeitkrank,
                onPick: (d) => setState(() => _langzeitkrank = d),
                onClear: () => setState(() => _langzeitkrank = null),
              ),
              _DateTile(
                label: 'Letzter Arbeitstag',
                value: _letzterTag,
                onPick: (d) => setState(() => _letzterTag = d),
                onClear: () => setState(() => _letzterTag = null),
              ),
              Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _kfristWert,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Frist'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<KuendigungsfristTyp?>(
                      initialValue: _kfristTyp,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Frist-Typ'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('—')),
                        for (final t in KuendigungsfristTyp.values)
                          DropdownMenuItem(value: t, child: Text(t.label)),
                      ],
                      onChanged: (v) => setState(() => _kfristTyp = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _kfristAnm,
                decoration:
                    const InputDecoration(labelText: 'Kündigungsfrist-Anmerkung'),
              ),
              TextField(
                controller: _kuendigungsgrund,
                decoration: const InputDecoration(labelText: 'Kündigungsgrund'),
              ),
              _DateTile(
                label: 'Kündigungsdatum',
                value: _kuendigung,
                onPick: (d) => setState(() => _kuendigung = d),
                onClear: () => setState(() => _kuendigung = null),
              ),
              _DateTile(
                label: 'Austrittsdatum',
                value: _austritt,
                onPick: (d) => setState(() => _austritt = d),
                onClear: () => setState(() => _austritt = null),
              ),
              TextField(
                controller: _austrittsgrund,
                decoration: const InputDecoration(labelText: 'Austrittsgrund'),
              ),
              TextField(
                controller: _austrittsmod,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'Austrittsmodalitäten'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Teilnahme Zeiterfassung'),
                value: _teilnahme,
                onChanged: (v) => setState(() => _teilnahme = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Automatische Buchung'),
                value: _autoBuchung,
                onChanged: (v) => setState(() => _autoBuchung = v),
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

/// Dialog 3 — Klassifizierungen.
class _KlassifizierungDialog extends StatefulWidget {
  const _KlassifizierungDialog({required this.base});
  final EmployeeProfile base;

  @override
  State<_KlassifizierungDialog> createState() => _KlassifizierungDialogState();
}

class _KlassifizierungDialogState extends State<_KlassifizierungDialog> {
  late final TextEditingController _abteilung;
  late final TextEditingController _position;
  late final TextEditingController _vorgesetzter;
  late final TextEditingController _vertreter;
  late final TextEditingController _kostenstelle;
  late final TextEditingController _produktiv;

  @override
  void initState() {
    super.initState();
    final b = widget.base;
    _abteilung = TextEditingController(text: b.abteilung ?? '');
    _position = TextEditingController(text: b.position ?? '');
    _vorgesetzter = TextEditingController(text: b.vorgesetzterName ?? '');
    _vertreter = TextEditingController(text: b.vertreterName ?? '');
    _kostenstelle = TextEditingController(text: b.kostenstelle ?? '');
    _produktiv = TextEditingController(
        text: b.produktiveZeitProzent != null
            ? b.produktiveZeitProzent!.toStringAsFixed(0)
            : '');
  }

  @override
  void dispose() {
    _abteilung.dispose();
    _position.dispose();
    _vorgesetzter.dispose();
    _vertreter.dispose();
    _kostenstelle.dispose();
    _produktiv.dispose();
    super.dispose();
  }

  void _save() {
    final produktiv = _parseDouble(_produktiv.text);
    final r = widget.base.copyWith(
      abteilung: _abteilung.text.trim(),
      position: _position.text.trim(),
      vorgesetzterName: _vorgesetzter.text.trim(),
      vertreterName: _vertreter.text.trim(),
      kostenstelle: _kostenstelle.text.trim(),
      produktiveZeitProzent: produktiv,
      clearProduktiveZeitProzent: produktiv == null,
    );
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Klassifizierungen'),
      content: SizedBox(
        width: math.min(500, MediaQuery.sizeOf(context).width - 64),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _abteilung,
                decoration: const InputDecoration(labelText: 'Abteilung'),
              ),
              TextField(
                controller: _position,
                decoration: const InputDecoration(labelText: 'Position'),
              ),
              TextField(
                controller: _vorgesetzter,
                decoration: const InputDecoration(labelText: 'Vorgesetzter'),
              ),
              TextField(
                controller: _vertreter,
                decoration: const InputDecoration(labelText: 'Vertreter'),
              ),
              TextField(
                controller: _kostenstelle,
                decoration: const InputDecoration(labelText: 'Kostenstelle'),
              ),
              TextField(
                controller: _produktiv,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Produktive Zeit (%)'),
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
