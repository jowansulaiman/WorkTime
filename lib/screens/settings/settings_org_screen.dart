import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/audit_log_entry.dart';
import '../../providers/audit_provider.dart';
import '../../providers/feature_flag_provider.dart';
import '../../widgets/breadcrumb_app_bar.dart';

/// Admin-only Unterseite „Organisation" des Einstellungs-Hubs: org-weite Defaults
/// der automatischen Schichtverteilung (Cap-Härte + Generator-Vorgaben) und die
/// MwSt-Behandlung der Einkaufspreise.
class SettingsOrgScreen extends StatelessWidget {
  const SettingsOrgScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: 'Einstellungen',
            onTap: () => Navigator.of(context).pop(),
          ),
          const BreadcrumbItem(label: 'Organisation'),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Automatische Schichtverteilung',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Gilt org-weit für alle Standorte und Mitarbeitenden.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                const _OrgAutoPlanSettingsCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Steuert die org-weiten Defaults der automatischen Schichtverteilung (Cap-
/// Härte + Generator-Vorgaben). Persistiert über
/// [FeatureFlagProvider.saveOrgSettings]; die Änderung wird ins
/// Änderungsprotokoll geschrieben (persönliche UserSettings bleiben ungeloggt).
class _OrgAutoPlanSettingsCard extends StatefulWidget {
  const _OrgAutoPlanSettingsCard();

  @override
  State<_OrgAutoPlanSettingsCard> createState() =>
      _OrgAutoPlanSettingsCardState();
}

class _OrgAutoPlanSettingsCardState extends State<_OrgAutoPlanSettingsCard> {
  late bool _enforceHard;
  late bool _purchasePricesIncludeVat;
  late TextEditingController _shiftMinutesCtrl;
  late TextEditingController _breakMinutesCtrl;
  late TextEditingController _requiredCountCtrl;
  late TextEditingController _qualiVorlaufCtrl;
  bool _saving = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    final settings = context.read<FeatureFlagProvider>().orgSettings;
    _enforceHard = settings.enforceHourCapHard;
    _purchasePricesIncludeVat = settings.purchasePricesIncludeVat;
    _shiftMinutesCtrl =
        TextEditingController(text: settings.defaultShiftMinutes.toString());
    _breakMinutesCtrl =
        TextEditingController(text: settings.defaultBreakMinutes.toString());
    _requiredCountCtrl =
        TextEditingController(text: settings.defaultRequiredCount.toString());
    _qualiVorlaufCtrl =
        TextEditingController(text: settings.qualiWarnVorlaufTage.toString());
    _initialized = true;
  }

  @override
  void dispose() {
    _shiftMinutesCtrl.dispose();
    _breakMinutesCtrl.dispose();
    _requiredCountCtrl.dispose();
    _qualiVorlaufCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enforceHard,
              onChanged: (value) => setState(() => _enforceHard = value),
              title: const Text('Stundengrenzen hart durchsetzen'),
              subtitle: const Text(
                'Aus: Grenzen dürfen bei Engpässen überschritten werden '
                '(Warnung in der Vorschau).',
              ),
              secondary: const Icon(Icons.gpp_maybe_outlined),
            ),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _shiftMinutesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Schichtlänge',
                      suffixText: 'min',
                      prefixIcon: Icon(Icons.timelapse_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _breakMinutesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Pause',
                      suffixText: 'min',
                      prefixIcon: Icon(Icons.free_breakfast_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _requiredCountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Standard-Bedarf je Öffnungsfenster',
                helperText: 'Genutzt, wenn ein Standort keinen Bedarf hinterlegt',
                prefixIcon: Icon(Icons.groups_outlined),
              ),
            ),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _purchasePricesIncludeVat,
              onChanged: (value) =>
                  setState(() => _purchasePricesIncludeVat = value),
              title: const Text('Einkaufspreise enthalten MwSt (brutto)'),
              subtitle: const Text(
                'Gilt für alle Artikel: Rohertrag und Wareneinsatz rechnen '
                'die Einkaufspreise dann über den Steuersatz des Artikels '
                'auf netto herunter. Aus = Einkaufspreise sind netto.',
              ),
              secondary: const Icon(Icons.receipt_long_outlined),
            ),
            const Divider(height: 32),
            TextFormField(
              controller: _qualiVorlaufCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Vorlauf Qualifikations-Ablauf (Tage)',
                helperText:
                    'Ab wie vielen Tagen vor Ablauf gewarnt wird (Standard 30)',
                prefixIcon: Icon(Icons.workspace_premium_outlined),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Speichern'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final featureFlags = context.read<FeatureFlagProvider>();
    final audit = context.read<AuditProvider>();
    final updated = featureFlags.orgSettings.copyWith(
      enforceHourCapHard: _enforceHard,
      defaultShiftMinutes: int.tryParse(_shiftMinutesCtrl.text.trim()) ?? 480,
      defaultBreakMinutes: int.tryParse(_breakMinutesCtrl.text.trim()) ?? 30,
      defaultRequiredCount: int.tryParse(_requiredCountCtrl.text.trim()) ?? 1,
      purchasePricesIncludeVat: _purchasePricesIncludeVat,
      qualiWarnVorlaufTage:
          int.tryParse(_qualiVorlaufCtrl.text.trim())?.clamp(0, 3650) ?? 30,
    );
    try {
      await featureFlags.saveOrgSettings(updated);
      // Org-Settings-Änderung IST fachlich relevant → genau einmal loggen.
      await audit.log(
        action: AuditAction.updated,
        entityType: 'Organisationseinstellungen',
        summary:
            'Org-Einstellungen angepasst (Stundengrenzen ${_enforceHard ? 'hart' : 'weich'}, '
            'Einkaufspreise ${_purchasePricesIncludeVat ? 'brutto' : 'netto'})',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Einstellungen gespeichert')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
