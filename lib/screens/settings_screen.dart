import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../models/user_settings.dart';
import '../models/work_template.dart';
import '../providers/auth_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/storage_mode_provider.dart';
import '../providers/team_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/work_provider.dart';
import '../widgets/breadcrumb_app_bar.dart';

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
                                  TextFormField(
                                    controller: _rateCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    decoration: const InputDecoration(
                                      labelText: 'Stundenlohn (optional)',
                                      prefixIcon: Icon(Icons.euro),
                                    ),
                                    validator: (value) {
                                      if ((value ?? '').isEmpty) {
                                        return null;
                                      }
                                      final parsed = double.tryParse(value!);
                                      if (parsed == null || parsed < 0) {
                                        return 'Ungueltiger Betrag';
                                      }
                                      return null;
                                    },
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
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed:
                                (_saving || _changingStorage) ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
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
    if (auth.authDisabled || storage.location == location) {
      return;
    }

    setState(() => _changingStorage = true);

    try {
      if (location == DataStorageLocation.local) {
        await teamProvider.cacheCloudStateLocally();
        await workProvider.cacheCloudStateLocally();
        await scheduleProvider.cacheCloudStateLocally();
      } else if (storage.isLocalOnly) {
        await teamProvider.syncLocalStateToCloud();
        await workProvider.syncLocalStateToCloud();
        await scheduleProvider.syncLocalStateToCloud();
      } else if (location == DataStorageLocation.hybrid) {
        await teamProvider.cacheCloudStateLocally();
        await workProvider.cacheCloudStateLocally();
        await scheduleProvider.cacheCloudStateLocally();
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
        child: Column(
          children: [
            RadioListTile<DataStorageLocation>(
              value: DataStorageLocation.hybrid,
              groupValue: location,
              onChanged: busy ? null : (value) => onChanged(value!),
              title: const Text('Hybrid-Speicher'),
              subtitle: const Text(
                'Cloud faehige Daten werden mit Firebase gespeichert und lokal als Cache vorgehalten. Lokale App-Zustaende bleiben auf dem Geraet.',
              ),
            ),
            RadioListTile<DataStorageLocation>(
              value: DataStorageLocation.cloud,
              groupValue: location,
              onChanged: busy ? null : (value) => onChanged(value!),
              title: const Text('Cloud-Speicher'),
              subtitle: const Text(
                'Daten werden direkt aus Firebase geladen. Lokale Cache-Kopien werden nicht als primaerer Speicher verwendet.',
              ),
            ),
            RadioListTile<DataStorageLocation>(
              value: DataStorageLocation.local,
              groupValue: location,
              onChanged: busy ? null : (value) => onChanged(value!),
              title: const Text('Nur lokal speichern'),
              subtitle: const Text(
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
            TextFormField(
              controller: vacationDaysCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Urlaubstage pro Jahr',
                prefixIcon: Icon(Icons.event_available),
                suffixText: 'Tage',
              ),
              validator: (value) {
                final parsed = int.tryParse(value ?? '');
                if (parsed == null || parsed < 0) {
                  return 'Ungueltiger Wert';
                }
                return null;
              },
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
