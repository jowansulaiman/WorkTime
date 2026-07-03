import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/redesign_flags.dart';
import '../models/app_user.dart';
import '../models/audit_log_entry.dart';
import '../models/user_settings.dart';
import '../models/work_template.dart';
import '../providers/audit_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/feature_flag_provider.dart';
import '../providers/contact_provider.dart';
import '../providers/finance_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/personal_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/storage_mode_provider.dart';
import '../providers/team_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/work_provider.dart';
import '../providers/zeitwirtschaft_provider.dart';
import '../widgets/breadcrumb_app_bar.dart';
import 'kiosk/kiosk_pin_setup_sheet.dart';
import 'notification_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.parentLabel = 'Profil',
  });

  final String parentLabel;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _rateCtrl;
  late TextEditingController _hoursCtrl;
  late TextEditingController _vacationDaysCtrl;
  late TextEditingController _autoBreakCtrl;
  String _currency = 'EUR';
  bool _saving = false;
  bool _changingStorage = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    final settings = context.read<WorkProvider>().settings;
    _nameCtrl = TextEditingController(text: settings.name);
    _rateCtrl = TextEditingController(
      text:
          settings.hourlyRate > 0 ? settings.hourlyRate.toStringAsFixed(2) : '',
    );
    _hoursCtrl = TextEditingController(
      text: settings.dailyHours.toStringAsFixed(1),
    );
    _vacationDaysCtrl = TextEditingController(
      text: settings.vacationDays.toString(),
    );
    _autoBreakCtrl = TextEditingController(
      text: settings.autoBreakAfterMinutes.toString(),
    );
    _currency = settings.currency;
    _initialized = true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rateCtrl.dispose();
    _hoursCtrl.dispose();
    _vacationDaysCtrl.dispose();
    _autoBreakCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final work = context.watch<WorkProvider>();
    final storage = context.watch<StorageModeProvider>();
    final currentUser = auth.profile;

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: widget.parentLabel,
            onTap: () => Navigator.of(context).pop(),
          ),
          const BreadcrumbItem(label: 'Einstellungen'),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Einstellungen',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Persoenliche Vorgaben, Vorlagen und lokale Theme-Einstellungen.',
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                          const SizedBox(height: 20),
                          if (currentUser != null)
                            _AccountInfoCard(user: currentUser),
                          const SizedBox(height: 20),
                          if (currentUser?.isAdmin == true) ...[
                            _sectionTitle('Automatische Schichtverteilung'),
                            const _OrgAutoPlanSettingsCard(),
                            const SizedBox(height: 20),
                          ],
                          _sectionTitle('Profil'),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: TextFormField(
                                controller: _nameCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Anzeigename',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _sectionTitle('Benachrichtigungen'),
                          Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              leading:
                                  const Icon(Icons.notifications_outlined),
                              title: const Text('Push-Benachrichtigungen'),
                              subtitle: const Text(
                                  'Kategorien und Ruhezeiten festlegen.'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const NotificationSettingsScreen(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _sectionTitle('Arbeitsmodus (Laden-Tablet)'),
                          Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              leading: const Icon(Icons.password_outlined),
                              title: const Text('Kiosk-PIN festlegen'),
                              subtitle: const Text(
                                  'PIN zum Anmelden am Laden-Tablet.'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => showKioskPinSetupSheet(context),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _sectionTitle('Arbeitszeit'),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: TextFormField(
                                controller: _hoursCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Soll-Stunden pro Tag',
                                  prefixIcon: Icon(Icons.schedule),
                                  suffixText: 'h',
                                ),
                                validator: (value) {
                                  final parsed = double.tryParse(value ?? '');
                                  if (parsed == null || parsed <= 0) {
                                    return 'Ungueltiger Wert';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _sectionTitle('Urlaub & Pause'),
                          _VacationQuotaCard(
                            vacationDaysCtrl: _vacationDaysCtrl,
                            autoBreakCtrl: _autoBreakCtrl,
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _sectionTitle('Arbeitszeit-Vorlagen'),
                              TextButton.icon(
                                onPressed: () => _openTemplateEditor(),
                                icon: const Icon(Icons.add),
                                label: const Text('Neu'),
                              ),
                            ],
                          ),
                          _TemplateListCard(
                            templates: work.templates,
                            onCreate: () => _openTemplateEditor(),
                            onEdit: _openTemplateEditor,
                            onDelete: _deleteTemplate,
                          ),
                          const SizedBox(height: 20),
                          _sectionTitle('Lohn'),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  // PA-0.3: Der Stundenlohn ist abrechnungs-
                                  // relevant und gehoert dem Admin (Vertrag) —
                                  // nicht der Selbstpflege. Nur noch Anzeige;
                                  // die Rules pinnen settings.hourlyRate zusaetz-
                                  // lich gegen Selbstschreiben.
                                  TextFormField(
                                    controller: _rateCtrl,
                                    enabled: false,
                                    decoration: const InputDecoration(
                                      labelText: 'Stundenlohn',
                                      prefixIcon: Icon(Icons.euro),
                                      helperText:
                                          'Wird vom Admin im Vertrag gepflegt.',
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  DropdownButtonFormField<String>(
                                    initialValue: _currency,
                                    decoration: const InputDecoration(
                                      labelText: 'Waehrung',
                                      prefixIcon: Icon(Icons.currency_exchange),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'EUR',
                                        child: Text('EUR - Euro'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'CHF',
                                        child: Text('CHF - Schweizer Franken'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'USD',
                                        child: Text('USD - US Dollar'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'GBP',
                                        child: Text('GBP - Britisches Pfund'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      setState(
                                          () => _currency = value ?? 'EUR');
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _sectionTitle('Datenspeicher'),
                          _StorageLocationCard(
                            authDisabled: auth.authDisabled,
                            location: storage.location,
                            busy: _changingStorage,
                            onChanged: _changeStorageLocation,
                          ),
                          const SizedBox(height: 20),
                          _sectionTitle('Erscheinungsbild'),
                          const _ThemeSelector(),
                          const _RedesignToggle(),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed:
                                (_saving || _changingStorage) ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator.adaptive(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: Text(
                              _saving ? 'Wird gespeichert...' : 'Speichern',
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                          ),
                          const SizedBox(height: 32),
                          const _InfoCard(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);

    final settings = UserSettings(
      name: _nameCtrl.text.trim(),
      hourlyRate: double.tryParse(_rateCtrl.text) ?? 0,
      dailyHours: double.tryParse(_hoursCtrl.text) ?? 8,
      currency: _currency,
      vacationDays: int.tryParse(_vacationDaysCtrl.text) ?? 30,
      autoBreakAfterMinutes: int.tryParse(_autoBreakCtrl.text) ?? 360,
    );

    try {
      await context.read<WorkProvider>().updateSettings(settings);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Einstellungen gespeichert'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler beim Speichern: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _changeStorageLocation(DataStorageLocation location) async {
    final auth = context.read<AuthProvider>();
    final storage = context.read<StorageModeProvider>();
    final teamProvider = context.read<TeamProvider>();
    final workProvider = context.read<WorkProvider>();
    final scheduleProvider = context.read<ScheduleProvider>();
    final inventoryProvider = context.read<InventoryProvider>();
    final contactProvider = context.read<ContactProvider>();
    final personalProvider = context.read<PersonalProvider>();
    final financeProvider = context.read<FinanceProvider>();
    final auditProvider = context.read<AuditProvider>();
    final zeitProvider = context.read<ZeitwirtschaftProvider>();
    if (auth.authDisabled || storage.location == location) {
      return;
    }

    // Alle migrationsfähigen Provider in kanonischer Reihenfolge. Inventory/
    // Contact/Personal/Finance/Audit migrierten früher NICHT mit (H-H1) →
    // stiller Daten-Silo beim Moduswechsel.
    Future<void> cacheAll() async {
      await teamProvider.cacheCloudStateLocally();
      await workProvider.cacheCloudStateLocally();
      await scheduleProvider.cacheCloudStateLocally();
      await inventoryProvider.cacheCloudStateLocally();
      await contactProvider.cacheCloudStateLocally();
      await personalProvider.cacheCloudStateLocally();
      await financeProvider.cacheCloudStateLocally();
      await auditProvider.cacheCloudStateLocally();
      await zeitProvider.cacheCloudStateLocally();
    }

    Future<void> syncAll() async {
      await teamProvider.syncLocalStateToCloud();
      await workProvider.syncLocalStateToCloud();
      await scheduleProvider.syncLocalStateToCloud();
      await inventoryProvider.syncLocalStateToCloud();
      await contactProvider.syncLocalStateToCloud();
      await personalProvider.syncLocalStateToCloud();
      await financeProvider.syncLocalStateToCloud();
      await auditProvider.syncLocalStateToCloud();
      await zeitProvider.syncLocalStateToCloud();
    }

    setState(() => _changingStorage = true);

    try {
      if (location == DataStorageLocation.local) {
        await cacheAll();
      } else if (storage.isLocalOnly) {
        await syncAll();
      } else if (location == DataStorageLocation.hybrid) {
        await cacheAll();
      }

      await storage.setLocation(location);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            switch (location) {
              DataStorageLocation.local =>
                'Daten werden ab jetzt nur lokal gespeichert.',
              DataStorageLocation.cloud => storage.isLocalOnly
                  ? 'Lokale Daten wurden in die Cloud synchronisiert.'
                  : 'Cloud-Speicher wurde aktiviert.',
              DataStorageLocation.hybrid => storage.isLocalOnly
                  ? 'Lokale Daten wurden synchronisiert. Hybridmodus ist jetzt aktiv.'
                  : 'Hybridmodus ist jetzt aktiv. Cloud-Daten werden lokal zwischengespeichert.',
            },
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Speicherort konnte nicht gewechselt werden: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _changingStorage = false);
      }
    }
  }

  Future<void> _openTemplateEditor([WorkTemplate? template]) async {
    final provider = context.read<WorkProvider>();
    final result = await showModalBottomSheet<WorkTemplate>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _TemplateEditorSheet(template: template),
      ),
    );

    if (result == null) {
      return;
    }

    if (template == null) {
      await provider.addTemplate(result);
    } else {
      await provider.updateTemplate(result);
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          template == null ? 'Vorlage gespeichert' : 'Vorlage aktualisiert',
        ),
      ),
    );
  }

  Future<void> _deleteTemplate(WorkTemplate template) async {
    if (template.id == null) {
      return;
    }
    final provider = context.read<WorkProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Vorlage loeschen?'),
        content: Text(
          'Die Vorlage "${template.name}" wird unwiderruflich geloescht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Loeschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await provider.deleteTemplate(template.id!);
  }
}

class _AccountInfoCard extends StatelessWidget {
  const _AccountInfoCard({required this.user});

  final AppUserProfile user;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              child: Text(
                user.displayName.isEmpty
                    ? '?'
                    : user.displayName.substring(0, 1).toUpperCase(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(user.email),
                  Text(
                    '${user.role.label} · Organisation ${user.orgId}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageLocationCard extends StatelessWidget {
  const _StorageLocationCard({
    required this.authDisabled,
    required this.location,
    required this.busy,
    required this.onChanged,
  });

  final bool authDisabled;
  final DataStorageLocation location;
  final bool busy;
  final ValueChanged<DataStorageLocation> onChanged;

  @override
  Widget build(BuildContext context) {
    if (authDisabled) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.cloud_off_outlined,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Diese App wurde im lokalen Modus gestartet. Der Speicherort kann in diesem Build nicht gewechselt werden.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: RadioGroup<DataStorageLocation>(
          groupValue: location,
          onChanged: (value) {
            if (busy || value == null) return;
            onChanged(value);
          },
          child: Column(
            children: [
              const RadioListTile<DataStorageLocation>(
                value: DataStorageLocation.hybrid,
                title: Text('Hybrid-Speicher'),
                subtitle: Text(
                  'Cloud faehige Daten werden mit Firebase gespeichert und lokal als Cache vorgehalten. Lokale App-Zustaende bleiben auf dem Geraet.',
                ),
              ),
              const RadioListTile<DataStorageLocation>(
                value: DataStorageLocation.cloud,
                title: Text('Cloud-Speicher'),
                subtitle: Text(
                  'Daten werden direkt aus Firebase geladen. Lokale Cache-Kopien werden nicht als primaerer Speicher verwendet.',
                ),
              ),
              const RadioListTile<DataStorageLocation>(
                value: DataStorageLocation.local,
                title: Text('Nur lokal speichern'),
                subtitle: Text(
                  'Daten bleiben auf diesem Geraet. Beim Zurueckwechsel werden lokale Daten in die Cloud uebertragen.',
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector();

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final current = themeProvider.themeMode;
    final options = [
      (ThemeMode.system, Icons.brightness_auto, 'System'),
      (ThemeMode.light, Icons.light_mode, 'Hell'),
      (ThemeMode.dark, Icons.dark_mode, 'Dunkel'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: options.map((option) {
            final (mode, icon, label) = option;
            final selected = current == mode;
            final colorScheme = Theme.of(context).colorScheme;
            return Expanded(
              child: GestureDetector(
                onTap: () => themeProvider.setThemeMode(mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.all(4),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? colorScheme.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          color: selected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Laufzeit-Schalter fuer das Signal-Teal-Redesign (nur im Demo-/Dev-Modus
/// sichtbar). Setzt den persistierten Override in [ThemeProvider]; Theme und
/// flag-gegatete Screens schalten live um (kein Neustart, kein dart-define).
class _RedesignToggle extends StatelessWidget {
  const _RedesignToggle();

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.disableAuthentication && !kDebugMode) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    final on = RedesignFlags.isOn(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: SwitchListTile(
          value: on,
          onChanged: (value) =>
              context.read<ThemeProvider>().setRedesignV2Override(value),
          title: const Text('Neues Design (Signal Teal)'),
          subtitle: const Text(
            'Vorschau des Redesigns — live umschaltbar (nur Entwicklungsmodus).',
          ),
          secondary: Icon(Icons.auto_awesome, color: colorScheme.primary),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
      ),
    );
  }
}

class _VacationQuotaCard extends StatelessWidget {
  const _VacationQuotaCard({
    required this.vacationDaysCtrl,
    required this.autoBreakCtrl,
  });

  final TextEditingController vacationDaysCtrl;
  final TextEditingController autoBreakCtrl;

  @override
  Widget build(BuildContext context) {
    final schedule = context.watch<ScheduleProvider>();
    final work = context.watch<WorkProvider>();
    final totalDays = work.settings.vacationDays;
    final usedDays = schedule.usedVacationDaysThisYear;
    final remaining = totalDays - usedDays;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.beach_access, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Urlaubskontingent ${DateTime.now().year}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Text(
                  '$usedDays / $totalDays Tage verbraucht',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: remaining < 0
                            ? colorScheme.error
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: totalDays > 0
                    ? (usedDays / totalDays).clamp(0.0, 1.0)
                    : 0.0,
                minHeight: 8,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: remaining < 0
                    ? colorScheme.error
                    : remaining <= 5
                        ? colorScheme.tertiary
                        : colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              remaining >= 0
                  ? '$remaining Tage verbleibend'
                  : '${remaining.abs()} Tage ueberschritten',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: remaining < 0
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            // PA-0.3: Urlaubsanspruch ist planungs-/abrechnungsrelevant und
            // gehoert dem Admin (Sollzeit-Profil, konsolidierung-M1) — nur noch
            // Anzeige; die Rules pinnen settings.vacationDays gegen Selbst-
            // schreiben. Der echte Urlaubskonto-Rest folgt in „Meine Akte" (PA-7).
            TextFormField(
              controller: vacationDaysCtrl,
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Urlaubstage pro Jahr',
                prefixIcon: Icon(Icons.event_available),
                suffixText: 'Tage',
                helperText: 'Wird vom Admin im Sollzeit-Profil gepflegt.',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: autoBreakCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Auto-Pause nach (Minuten)',
                prefixIcon: Icon(Icons.coffee),
                suffixText: 'min',
                helperText:
                    'Stempeluhr fuegt 30 min Pause hinzu wenn Arbeitszeit diesen Wert ueberschreitet. 0 = deaktiviert.',
              ),
              validator: (value) {
                final parsed = int.tryParse(value ?? '');
                if (parsed == null || parsed < 0) {
                  return 'Ungueltiger Wert';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Die gezeigten Lohndaten sind als Bruttowerte zu verstehen. '
          'Rollen, Einladungen und Teamverwaltung befinden sich im Admin-Bereich.',
        ),
      ),
    );
  }
}

class _TemplateListCard extends StatelessWidget {
  const _TemplateListCard({
    required this.templates,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
  });

  final List<WorkTemplate> templates;
  final VoidCallback onCreate;
  final ValueChanged<WorkTemplate> onEdit;
  final ValueChanged<WorkTemplate> onDelete;

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Noch keine Vorlagen vorhanden',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Lege Standardzeiten wie Fruehdienst oder Buerotag an und uebernimm sie spaeter im Eintragsformular.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Vorlage anlegen'),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          for (var i = 0; i < templates.length; i++) ...[
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              title: Text(templates[i].name),
              subtitle: Text(
                _formatTemplateSummary(context, templates[i]),
                maxLines: templates[i].note != null ? 3 : 2,
                overflow: TextOverflow.ellipsis,
              ),
              isThreeLine: templates[i].note != null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Bearbeiten',
                    onPressed: () => onEdit(templates[i]),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Loeschen',
                    onPressed: () => onDelete(templates[i]),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
            if (i < templates.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _TemplateEditorSheet extends StatefulWidget {
  const _TemplateEditorSheet({this.template});

  final WorkTemplate? template;

  @override
  State<_TemplateEditorSheet> createState() => _TemplateEditorSheetState();
}

class _TemplateEditorSheetState extends State<_TemplateEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _breakCtrl;
  late final TextEditingController _noteCtrl;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    _nameCtrl = TextEditingController(text: template?.name ?? '');
    _breakCtrl = TextEditingController(
      text:
          template == null ? '30' : _formatBreakMinutes(template.breakMinutes),
    );
    _noteCtrl = TextEditingController(text: template?.note ?? '');
    _startTime = template == null
        ? const TimeOfDay(hour: 8, minute: 0)
        : _timeOfDayFromMinutes(template.startMinutes);
    _endTime = template == null
        ? const TimeOfDay(hour: 17, minute: 0)
        : _timeOfDayFromMinutes(template.endMinutes);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _breakCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.template != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isEdit ? 'Vorlage bearbeiten' : 'Neue Vorlage',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name der Vorlage',
                prefixIcon: Icon(Icons.bookmark_outline),
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Bitte Namen eingeben';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.login),
                    title: const Text('Beginn'),
                    trailing: Text(_formatTime(context, _startTime)),
                    onTap: _pickStart,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Ende'),
                    trailing: Text(_formatTime(context, _endTime)),
                    onTap: _pickEnd,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _breakCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Pause in Minuten',
                prefixIcon: Icon(Icons.coffee_outlined),
                suffixText: 'min',
              ),
              validator: (value) {
                final parsed = double.tryParse(value ?? '');
                if (parsed == null || parsed < 0) {
                  return 'Ungueltiger Wert';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _noteCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notiz (optional)',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(
                isEdit ? 'Vorlage aktualisieren' : 'Vorlage speichern',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked == null) {
      return;
    }
    setState(() => _startTime = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked == null) {
      return;
    }
    setState(() => _endTime = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final startMinutes = _toMinutes(_startTime);
    final endMinutes = _toMinutes(_endTime);

    if (endMinutes <= startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Endzeit muss nach Startzeit liegen.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      WorkTemplate(
        id: widget.template?.id,
        orgId: widget.template?.orgId ?? '',
        userId: widget.template?.userId ?? '',
        name: _nameCtrl.text,
        startMinutes: startMinutes,
        endMinutes: endMinutes,
        breakMinutes: double.tryParse(_breakCtrl.text) ?? 0,
        note: _noteCtrl.text,
      ),
    );
  }
}

String _formatTemplateSummary(BuildContext context, WorkTemplate template) {
  final timeRange =
      '${_formatTime(context, _timeOfDayFromMinutes(template.startMinutes))} - '
      '${_formatTime(context, _timeOfDayFromMinutes(template.endMinutes))}';
  final breakText = 'Pause: ${_formatBreakMinutes(template.breakMinutes)} min';
  final noteText = template.note == null ? '' : '\n${template.note}';
  return '$timeRange · $breakText$noteText';
}

String _formatTime(BuildContext context, TimeOfDay time) {
  return MaterialLocalizations.of(context).formatTimeOfDay(
    time,
    alwaysUse24HourFormat: true,
  );
}

String _formatBreakMinutes(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(1);
}

TimeOfDay _timeOfDayFromMinutes(int minutes) {
  return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
}

int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

/// Admin-only Org-Sektion: steuert die org-weiten Defaults der automatischen
/// Schichtverteilung (Cap-Härte + Generator-Vorgaben). Persistiert über
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
    _initialized = true;
  }

  @override
  void dispose() {
    _shiftMinutesCtrl.dispose();
    _breakMinutesCtrl.dispose();
    _requiredCountCtrl.dispose();
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
