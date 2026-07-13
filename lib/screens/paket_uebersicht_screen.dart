import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/parcel_shipment.dart';
import '../providers/parcel_provider.dart';

/// Übersicht (Plan §8): Überfällig-Board mit Rücklauf-Sammelaktion + Tages-
/// Reconciliation (heute angenommen / ausgegeben) zum Abgleich mit dem Gerät
/// des Paketdiensts. Rein beratend — kein Auto-Rücklauf.
class PaketUebersichtScreen extends StatelessWidget {
  const PaketUebersichtScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Übersicht'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Überfällig'),
              Tab(text: 'Heute'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _OverdueTab(),
            _TodayTab(),
          ],
        ),
      ),
    );
  }
}

class _OverdueTab extends StatelessWidget {
  const _OverdueTab();

  @override
  Widget build(BuildContext context) {
    final parcel = context.watch<ParcelProvider>();
    final now = DateTime.now();
    final overdue = parcel.overdueParcels(now);

    if (overdue.isEmpty) {
      return const Center(child: Text('Keine überfälligen Pakete. 🎉'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: () => _returnAll(context, overdue),
          icon: const Icon(Icons.assignment_return_outlined),
          label: Text('Alle ${overdue.length} als Rücklauf markieren'),
        ),
        const SizedBox(height: 8),
        for (final p in overdue)
          Card(
            child: ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(p.recipientDisplayName),
              subtitle: Text([
                if (p.compartmentLabel != null) 'Fach ${p.compartmentLabel}',
                'seit ${now.difference(p.arrivedAt).inDays} Tagen',
              ].join(' · ')),
              trailing: OutlinedButton(
                onPressed: () => context.read<ParcelProvider>().returnParcel(p),
                child: const Text('Rücklauf'),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _returnAll(
      BuildContext context, List<ParcelShipment> parcels) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rücklauf-Sammelaktion'),
        content: Text('${parcels.length} überfällige Pakete als Rücklauf '
            'markieren?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Markieren')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final provider = context.read<ParcelProvider>();
    for (final p in parcels) {
      await provider.returnParcel(p);
    }
  }
}

class _TodayTab extends StatelessWidget {
  const _TodayTab();

  @override
  Widget build(BuildContext context) {
    final parcel = context.watch<ParcelProvider>();
    final now = DateTime.now();
    final arrived = parcel.parcelsArrivedOn(now);
    final handedOut = parcel.parcelsHandedOutOn(now);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Heute angenommen (${arrived.length})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        if (arrived.isEmpty)
          const Text('—')
        else
          for (final p in arrived)
            ListTile(
              dense: true,
              leading: const Icon(Icons.call_received),
              title: Text(p.recipientDisplayName),
              subtitle:
                  p.compartmentLabel == null ? null : Text('Fach ${p.compartmentLabel}'),
            ),
        const Divider(height: 32),
        Text('Heute ausgegeben (${handedOut.length})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        if (handedOut.isEmpty)
          const Text('—')
        else
          for (final p in handedOut)
            ListTile(
              dense: true,
              leading: const Icon(Icons.call_made),
              title: Text(p.recipientDisplayName),
            ),
      ],
    );
  }
}
