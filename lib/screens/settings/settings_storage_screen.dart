import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/audit_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/contact_provider.dart';
import '../../providers/finance_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/personal_provider.dart';
import '../../providers/schedule_provider.dart';
import '../../providers/storage_mode_provider.dart';
import '../../providers/team_provider.dart';
import '../../providers/work_provider.dart';
import '../../providers/zeitwirtschaft_provider.dart';
import '../../widgets/breadcrumb_app_bar.dart';

/// Unterseite „Datenspeicher" des Einstellungs-Hubs: Hybrid/Cloud/Nur-lokal
/// umschalten. Der Moduswechsel migriert alle Provider in kanonischer
/// Reihenfolge (Cache/Sync), bevor der Modus tatsächlich umgestellt wird.
class SettingsStorageScreen extends StatefulWidget {
  const SettingsStorageScreen({super.key});

  @override
  State<SettingsStorageScreen> createState() => _SettingsStorageScreenState();
}

class _SettingsStorageScreenState extends State<SettingsStorageScreen> {
  bool _changingStorage = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final storage = context.watch<StorageModeProvider>();
    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: 'Einstellungen',
            onTap: () => Navigator.of(context).pop(),
          ),
          const BreadcrumbItem(label: 'Datenspeicher'),
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
                  'Wo deine Daten gespeichert werden',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Beim Wechsel werden vorhandene Daten übertragen. Das kann '
                  'einen Moment dauern.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                _StorageLocationCard(
                  authDisabled: auth.authDisabled,
                  location: storage.location,
                  busy: _changingStorage,
                  onChanged: _changeStorageLocation,
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
