import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/parcel_customer.dart';
import '../providers/parcel_provider.dart';

/// Kunden-Namensregister (Plan §0/§8/§13): dauerhafte, name-only Liste der
/// Paketempfänger für den Typeahead. Enthält die **Löschmöglichkeit je Kunde**
/// (Art. 17/21-Widerspruch), die die Registerdaten entfernt und den
/// `parcelCustomerId` an offenen Paketen entkoppelt.
class KundenRegisterScreen extends StatefulWidget {
  const KundenRegisterScreen({super.key});

  @override
  State<KundenRegisterScreen> createState() => _KundenRegisterScreenState();
}

class _KundenRegisterScreenState extends State<KundenRegisterScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _delete(ParcelCustomer c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kunde löschen'),
        content: Text(
          '„${c.displayName}" aus dem Register löschen? Offene Pakete bleiben '
          'erhalten, verlieren aber die Namensverknüpfung.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<ParcelProvider>().deleteCustomer(c.id!);
  }

  @override
  Widget build(BuildContext context) {
    final parcel = context.watch<ParcelProvider>();
    final q = _query.trim();
    final customers = q.isEmpty
        ? parcel.customers
        : parcel.parcelCustomersMatching(q);

    return Scaffold(
      appBar: AppBar(title: const Text('Kundenregister')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                labelText: 'Name suchen',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: customers.isEmpty
                ? const Center(child: Text('Keine Einträge.'))
                : ListView(
                    children: [
                      for (final c in customers)
                        ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(c.displayName),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Kunde löschen',
                            onPressed: () => _delete(c),
                          ),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Namen werden dauerhaft gespeichert, um Stammkunden '
              'wiederzuerkennen. Löschung jederzeit hier möglich.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
