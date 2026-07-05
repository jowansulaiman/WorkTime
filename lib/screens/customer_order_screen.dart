import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/money.dart';
import '../models/customer_order.dart';
import '../models/product.dart';
import '../models/site_definition.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/team_provider.dart';
import '../services/export_service.dart';
import '../ui/ui.dart';
import '../widgets/action_fab.dart';
import '../widgets/contact_picker_field.dart';

final NumberFormat _euroFormat =
    NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
final DateFormat _dateFormat = DateFormat('dd.MM.yyyy', 'de_DE');

String _formatCents(int? cents) {
  if (cents == null) {
    return '–';
  }
  return _euroFormat.format(cents / 100);
}

int? _parseEuroToCents(String value) => Money.parseCents(value);

String _centsToEuroInput(int? cents) {
  if (cents == null) {
    return '';
  }
  return (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> _confirm(BuildContext context, String title, String message) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Bestätigen'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Warn-Banner fuer bald faellige, nicht vorbereitete Kundenbestellungen.
/// Beobachtet den [InventoryProvider] selbst und blendet sich aus, wenn nichts
/// ansteht oder der Nutzer keine Berechtigung hat. Tippen oeffnet den
/// [CustomerOrderScreen]. Wird auf den Home-Dashboards eingebettet.
class CustomerOrderWarningBanner extends StatelessWidget {
  const CustomerOrderWarningBanner({super.key, this.parentLabel = 'Heute'});

  final String parentLabel;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    if (profile == null || !profile.canViewInventory) {
      return const SizedBox.shrink();
    }
    final due = context.watch<InventoryProvider>().ordersDueSoonNotPrepared();
    if (due.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(bottom: context.spacing.md),
      child: AppStatusBanner(
        tone: AppStatusTone.warning,
        icon: Icons.warning_amber_rounded,
        message:
            '${due.length} ${due.length == 1 ? 'Kundenbestellung ist' : 'Kundenbestellungen sind'} bald fällig und nicht vorbereitet.',
        action: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CustomerOrderScreen(parentLabel: parentLabel),
            ),
          ),
          child: const Text('Ansehen'),
        ),
      ),
    );
  }
}

/// Verwaltung der Kundenbestellungen (Sonderbestellungen): Kunden geben
/// Bestellungen auf, die sie zu einem Abholtermin abholen — einige
/// wiederkehrend (woechentlich/monatlich). Ist eine Bestellung kurz vor der
/// Abholung nicht vorbereitet, wird der Mitarbeiter gewarnt.
class CustomerOrderScreen extends StatefulWidget {
  const CustomerOrderScreen({
    super.key,
    this.parentLabel = 'Profil',
  });

  final String parentLabel;

  @override
  State<CustomerOrderScreen> createState() => _CustomerOrderScreenState();
}

class _CustomerOrderScreenState extends State<CustomerOrderScreen> {
  String? _selectedSiteId;
  String _search = '';
  CustomerOrderStatus? _statusFilter;
  String? _categoryFilter;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final inventory = context.watch<InventoryProvider>();
    final team = context.watch<TeamProvider>();
    final profile = auth.profile;

    final breadcrumbs = [
      BreadcrumbItem(
        label: widget.parentLabel,
        onTap: () => Navigator.of(context).pop(),
      ),
      const BreadcrumbItem(label: 'Kundenbestellungen'),
    ];

    if (profile == null || !profile.canViewInventory) {
      return Scaffold(
        appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
        body: const Center(
          child: Text('Keine Berechtigung für Kundenbestellungen.'),
        ),
      );
    }

    final canManage = profile.canManageInventory;
    final sites = team.sites;
    final dueOrders = inventory.ordersDueSoonNotPrepared(siteId: _selectedSiteId);
    final dueIds = dueOrders.map((order) => order.id).whereType<String>().toSet();
    final categories = inventory.customerOrderCategories.toList()..sort();

    final orders = _applyFilters(
      inventory.customerOrdersForSite(_selectedSiteId),
    );

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: breadcrumbs,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Exportieren',
            // Ohne Bestellungen gibt es nichts zu exportieren → deaktiviert.
            enabled: orders.isNotEmpty,
            onSelected: (value) => _export(context, value, orders),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Als PDF exportieren')),
              PopupMenuItem(value: 'csv', child: Text('Als CSV exportieren')),
            ],
          ),
        ],
      ),
      floatingActionButton: canManage
          ? ExpandableFab(
              heroTag: 'customer_order_add_fab',
              actions: [
                FabAction(
                  icon: Icons.add,
                  label: 'Bestellung',
                  onPressed: () => _addOrder(context, inventory, sites),
                ),
              ],
            )
          : null,
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              children: [
                if (sites.length > 1)
                  _SiteFilterBar(
                    sites: sites,
                    selectedSiteId: _selectedSiteId,
                    onChanged: (value) =>
                        setState(() => _selectedSiteId = value),
                  ),
                _FilterBar(
                  statusFilter: _statusFilter,
                  categoryFilter: _categoryFilter,
                  categories: categories,
                  onStatusChanged: (value) =>
                      setState(() => _statusFilter = value),
                  onCategoryChanged: (value) =>
                      setState(() => _categoryFilter = value),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Kunde, Bestellnr. oder Artikel suchen',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _search = value),
                  ),
                ),
                if (inventory.errorMessage != null)
                  _ErrorBanner(
                    message: inventory.errorMessage!,
                    onDismiss: inventory.clearError,
                  ),
                if (dueOrders.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: AppStatusBanner(
                      tone: AppStatusTone.warning,
                      icon: Icons.warning_amber_rounded,
                      message:
                          '${dueOrders.length} ${dueOrders.length == 1 ? 'Bestellung ist' : 'Bestellungen sind'} bald fällig und noch nicht vorbereitet.',
                    ),
                  ),
                Expanded(
                  child: orders.isEmpty
                      ? EmptyState(
                          icon: Icons.shopping_bag_outlined,
                          message: inventory.customerOrders.isEmpty
                              ? 'Noch keine Kundenbestellungen. Lege über das Plus die erste Sonderbestellung an.'
                              : 'Keine Bestellungen passen zu den Filtern.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          itemCount: orders.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final order = orders[index];
                            return _CustomerOrderTile(
                              order: order,
                              canManage: canManage,
                              sites: sites,
                              needsPreparation:
                                  order.id != null && dueIds.contains(order.id),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<CustomerOrder> _applyFilters(List<CustomerOrder> source) {
    final query = _search.trim().toLowerCase();
    final result = source.where((order) {
      if (_statusFilter != null && order.status != _statusFilter) {
        return false;
      }
      if (_categoryFilter != null &&
          !order.items.any((item) =>
              (item.category?.trim().toLowerCase() ?? '') ==
              _categoryFilter!.toLowerCase())) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return order.customerName.toLowerCase().contains(query) ||
          (order.customerContact?.toLowerCase().contains(query) ?? false) ||
          (order.orderNumber?.toLowerCase().contains(query) ?? false) ||
          order.items.any((item) =>
              item.name.toLowerCase().contains(query) ||
              (item.category?.toLowerCase().contains(query) ?? false));
    }).toList();

    // Offene zuerst, dann nach Abholtermin (frueheste zuerst, ohne Termin ans Ende).
    result.sort((a, b) {
      if (a.status.isClosed != b.status.isClosed) {
        return a.status.isClosed ? 1 : -1;
      }
      final da = a.pickupDate;
      final db = b.pickupDate;
      if (da == null && db == null) {
        return 0;
      }
      if (da == null) {
        return 1;
      }
      if (db == null) {
        return -1;
      }
      return da.compareTo(db);
    });
    return result;
  }

  Future<void> _addOrder(
    BuildContext context,
    InventoryProvider inventory,
    List<SiteDefinition> sites,
  ) async {
    if (sites.isEmpty) {
      _showSnack(context,
          'Bitte zuerst unter Personal → Organisation einen Standort anlegen.');
      return;
    }
    final result = await showCustomerOrderDialog(
      context,
      sites: sites,
      defaultSiteId: _selectedSiteId ?? sites.first.id,
    );
    if (result != null) {
      try {
        await inventory.saveCustomerOrder(result);
        if (context.mounted) {
          _showSnack(context, 'Kundenbestellung gespeichert.');
        }
      } catch (error) {
        if (context.mounted) {
          _showSnack(context, 'Fehler: $error');
        }
      }
    }
  }

  Future<void> _export(
    BuildContext context,
    String format,
    List<CustomerOrder> orders,
  ) async {
    if (orders.isEmpty) {
      _showSnack(context, 'Keine Bestellungen zum Exportieren.');
      return;
    }
    final team = context.read<TeamProvider>();
    final siteLabel = _selectedSiteId == null
        ? null
        : team.sites
            .where((site) => site.id == _selectedSiteId)
            .map((site) => site.name)
            .cast<String?>()
            .firstWhere((name) => true, orElse: () => null);
    try {
      if (format == 'pdf') {
        await ExportService.exportCustomerOrdersPdf(
          orders: orders,
          siteLabel: siteLabel,
        );
      } else {
        await ExportService.exportCustomerOrdersCsv(
          orders: orders,
          siteLabel: siteLabel,
        );
      }
      if (context.mounted) {
        _showSnack(context, 'Export erstellt.');
      }
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, 'Export fehlgeschlagen: $error');
      }
    }
  }
}

class _SiteFilterBar extends StatelessWidget {
  const _SiteFilterBar({
    required this.sites,
    required this.selectedSiteId,
    required this.onChanged,
  });

  final List<SiteDefinition> sites;
  final String? selectedSiteId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('Alle Läden'),
              selected: selectedSiteId == null,
              onSelected: (_) => onChanged(null),
            ),
            const SizedBox(width: 8),
            for (final site in sites) ...[
              ChoiceChip(
                label: Text(site.name),
                selected: selectedSiteId == site.id,
                onSelected: (_) => onChanged(site.id),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.statusFilter,
    required this.categoryFilter,
    required this.categories,
    required this.onStatusChanged,
    required this.onCategoryChanged,
  });

  final CustomerOrderStatus? statusFilter;
  final String? categoryFilter;
  final List<String> categories;
  final ValueChanged<CustomerOrderStatus?> onStatusChanged;
  final ValueChanged<String?> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('Alle'),
              selected: statusFilter == null,
              onSelected: (_) => onStatusChanged(null),
            ),
            const SizedBox(width: 8),
            for (final status in CustomerOrderStatus.values) ...[
              ChoiceChip(
                label: Text(status.label),
                selected: statusFilter == status,
                onSelected: (_) => onStatusChanged(status),
              ),
              const SizedBox(width: 8),
            ],
            if (categories.isNotEmpty) ...[
              const _FilterDivider(),
              for (final category in categories) ...[
                FilterChip(
                  label: Text(category),
                  selected: categoryFilter == category,
                  onSelected: (selected) =>
                      onCategoryChanged(selected ? category : null),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterDivider extends StatelessWidget {
  const _FilterDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        height: 24,
        child: VerticalDivider(
          width: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: colorScheme.onErrorContainer),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _CustomerOrderTile extends StatelessWidget {
  const _CustomerOrderTile({
    required this.order,
    required this.canManage,
    required this.sites,
    required this.needsPreparation,
  });

  final CustomerOrder order;
  final bool canManage;
  final List<SiteDefinition> sites;
  final bool needsPreparation;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final inventory = context.read<InventoryProvider>();

    final subtitleParts = <String>[
      if (order.orderNumber?.isNotEmpty ?? false) order.orderNumber!,
      if (order.pickupDate != null)
        'Abholung ${_dateFormat.format(order.pickupDate!)}',
      if (order.recurrence.isRecurring) order.recurrence.label,
      '${order.itemCount} ${order.itemCount == 1 ? 'Position' : 'Positionen'}',
      if (order.hasPrices) _formatCents(order.totalCents),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        isThreeLine: needsPreparation,
        onTap: canManage ? () => _edit(context, inventory) : null,
        leading: CircleAvatar(
          backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
          foregroundColor: colorScheme.primary,
          child: Text(
            order.customerName.isNotEmpty
                ? order.customerName.characters.first.toUpperCase()
                : '?',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                order.customerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            _statusBadge(order.status),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              subtitleParts.join('  ·  '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            if (needsPreparation)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: AppStatusBadge(
                  label: 'Nicht vorbereitet',
                  tone: AppStatusTone.warning,
                  icon: Icons.warning_amber_rounded,
                ),
              ),
          ],
        ),
        trailing: canManage
            ? PopupMenuButton<String>(
                onSelected: (value) => _onMenu(context, inventory, value),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
                  if (!order.isPrepared && order.status.isOpen)
                    const PopupMenuItem(
                      value: 'prepare',
                      child: Text('Als vorbereitet markieren'),
                    ),
                  if (order.isPrepared && order.status.isOpen)
                    const PopupMenuItem(
                      value: 'unprepare',
                      child: Text('Vorbereitung zurücknehmen'),
                    ),
                  if (order.status.isOpen)
                    const PopupMenuItem(
                      value: 'pickup',
                      child: Text('Als abgeholt markieren'),
                    ),
                  if (order.status.isOpen)
                    const PopupMenuItem(
                      value: 'cancel',
                      child: Text('Stornieren'),
                    ),
                  const PopupMenuItem(value: 'delete', child: Text('Löschen')),
                ],
              )
            : null,
      ),
    );
  }

  Widget _statusBadge(CustomerOrderStatus status) {
    final tone = switch (status) {
      CustomerOrderStatus.open => AppStatusTone.neutral,
      CustomerOrderStatus.prepared => AppStatusTone.info,
      CustomerOrderStatus.pickedUp => AppStatusTone.success,
      CustomerOrderStatus.cancelled => AppStatusTone.error,
    };
    return AppStatusBadge(label: status.label, tone: tone);
  }

  Future<void> _onMenu(
    BuildContext context,
    InventoryProvider inventory,
    String value,
  ) async {
    try {
      switch (value) {
        case 'edit':
          await _edit(context, inventory);
          break;
        case 'prepare':
          await inventory.markCustomerOrderPrepared(order);
          if (context.mounted) {
            _showSnack(context, 'Als vorbereitet markiert.');
          }
          break;
        case 'unprepare':
          await inventory.markCustomerOrderPrepared(order, prepared: false);
          if (context.mounted) {
            _showSnack(context, 'Vorbereitung zurückgenommen.');
          }
          break;
        case 'pickup':
          await inventory.markCustomerOrderPickedUp(order);
          if (context.mounted) {
            _showSnack(
              context,
              order.recurrence.isRecurring
                  ? 'Abgeholt. Folgetermin wurde angelegt.'
                  : 'Als abgeholt markiert.',
            );
          }
          break;
        case 'cancel':
          if (await _confirm(context, 'Bestellung stornieren?',
                  '${order.customerName}: Bestellung wird storniert.') &&
              context.mounted) {
            await inventory.cancelCustomerOrder(order);
            if (context.mounted) {
              _showSnack(context, 'Bestellung storniert.');
            }
          }
          break;
        case 'delete':
          if (await _confirm(context, 'Bestellung löschen?',
                  '${order.customerName}: Bestellung wird unwiderruflich gelöscht.') &&
              order.id != null) {
            await inventory.deleteCustomerOrder(order.id!);
            if (context.mounted) {
              _showSnack(context, 'Bestellung gelöscht.');
            }
          }
          break;
      }
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, 'Fehler: $error');
      }
    }
  }

  Future<void> _edit(BuildContext context, InventoryProvider inventory) async {
    final result = await showCustomerOrderDialog(
      context,
      sites: sites,
      order: order,
    );
    if (result != null) {
      try {
        await inventory.saveCustomerOrder(result);
        if (context.mounted) {
          _showSnack(context, 'Kundenbestellung gespeichert.');
        }
      } catch (error) {
        if (context.mounted) {
          _showSnack(context, 'Fehler: $error');
        }
      }
    }
  }
}

// ===========================================================================
// Dialog: Kundenbestellung anlegen / bearbeiten
// ===========================================================================

Future<CustomerOrder?> showCustomerOrderDialog(
  BuildContext context, {
  required List<SiteDefinition> sites,
  CustomerOrder? order,
  String? defaultSiteId,
}) {
  return showDialog<CustomerOrder>(
    context: context,
    builder: (_) => _CustomerOrderDialog(
      sites: sites,
      order: order,
      defaultSiteId: defaultSiteId,
    ),
  );
}

class _CustomerOrderDialog extends StatefulWidget {
  const _CustomerOrderDialog({
    required this.sites,
    this.order,
    this.defaultSiteId,
  });

  final List<SiteDefinition> sites;
  final CustomerOrder? order;
  final String? defaultSiteId;

  @override
  State<_CustomerOrderDialog> createState() => _CustomerOrderDialogState();
}

class _CustomerOrderDialogState extends State<_CustomerOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _customerName;
  late final TextEditingController _customerContact;
  late final TextEditingController _notes;
  String? _siteId;
  String? _contactId;
  CustomerOrderRecurrence _recurrence = CustomerOrderRecurrence.none;
  DateTime? _pickupDate;
  late List<CustomerOrderItem> _items;

  @override
  void initState() {
    super.initState();
    final order = widget.order;
    _customerName = TextEditingController(text: order?.customerName ?? '');
    _customerContact =
        TextEditingController(text: order?.customerContact ?? '');
    _contactId = order?.contactId;
    _notes = TextEditingController(text: order?.notes ?? '');
    _siteId = order?.siteId ??
        widget.defaultSiteId ??
        (widget.sites.isNotEmpty ? widget.sites.first.id : null);
    _recurrence = order?.recurrence ?? CustomerOrderRecurrence.none;
    _pickupDate = order?.pickupDate;
    _items = [...?order?.items];
  }

  @override
  void dispose() {
    _customerName.dispose();
    _customerContact.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.order != null;
    return AlertDialog(
      title: Text(isEdit ? 'Bestellung bearbeiten' : 'Neue Kundenbestellung'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ContactPickerField(
                  contactId: _contactId,
                  onSelected: (contact) => setState(() {
                    _contactId = contact?.id;
                    if (contact != null) {
                      _customerName.text = contact.name;
                      final reach = contact.primaryPhone ?? contact.email;
                      if (reach != null && reach.trim().isNotEmpty) {
                        _customerContact.text = reach;
                      }
                    }
                  }),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _customerName,
                  decoration: const InputDecoration(labelText: 'Kunde *'),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Bitte einen Kundennamen angeben'
                      : null,
                ),
                TextFormField(
                  controller: _customerContact,
                  decoration: const InputDecoration(
                    labelText: 'Kontakt (Telefon/E-Mail)',
                  ),
                ),
                if (widget.sites.length > 1)
                  DropdownButtonFormField<String>(
                    initialValue: _siteId,
                    decoration: const InputDecoration(labelText: 'Laden *'),
                    items: [
                      for (final site in widget.sites)
                        DropdownMenuItem(
                          value: site.id,
                          child: Text(site.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _siteId = value),
                    validator: (value) =>
                        value == null ? 'Bitte einen Laden wählen' : null,
                  ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<CustomerOrderRecurrence>(
                        initialValue: _recurrence,
                        decoration:
                            const InputDecoration(labelText: 'Rhythmus'),
                        items: [
                          for (final recurrence
                              in CustomerOrderRecurrence.values)
                            DropdownMenuItem(
                              value: recurrence,
                              child: Text(recurrence.label),
                            ),
                        ],
                        onChanged: (value) => setState(
                          () => _recurrence =
                              value ?? CustomerOrderRecurrence.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PickupDateField(
                        value: _pickupDate,
                        onPick: _pickDate,
                        onClear: () => setState(() => _pickupDate = null),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _ItemsEditor(
                  items: _items,
                  categories: _knownCategories(context),
                  onAdd: _addItem,
                  onEdit: _editItem,
                  onRemove: (index) => setState(() => _items.removeAt(index)),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Notiz'),
                  maxLines: 2,
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
          onPressed: _submit,
          child: const Text('Speichern'),
        ),
      ],
    );
  }

  List<String> _knownCategories(BuildContext context) {
    final fromOrders =
        context.read<InventoryProvider>().customerOrderCategories;
    final fromProducts = context
        .read<InventoryProvider>()
        .products
        .map((product) => product.category?.trim())
        .whereType<String>()
        .where((category) => category.isNotEmpty);
    return ({...fromOrders, ...fromProducts}.toList())..sort();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickupDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      setState(() => _pickupDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            12,
          ));
    }
  }

  Future<void> _addItem() async {
    final item = await showCustomerOrderItemDialog(
      context,
      categories: _knownCategories(context),
    );
    if (item != null) {
      setState(() => _items.add(item));
    }
  }

  Future<void> _editItem(int index) async {
    final item = await showCustomerOrderItemDialog(
      context,
      item: _items[index],
      categories: _knownCategories(context),
    );
    if (item != null) {
      setState(() => _items[index] = item);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final siteId = _siteId;
    if (siteId == null) {
      return;
    }
    if (_items.isEmpty) {
      _showSnack(context, 'Bitte mindestens eine Position hinzufügen.');
      return;
    }
    final site = widget.sites.firstWhere(
      (s) => s.id == siteId,
      orElse: () => widget.sites.first,
    );
    final contact = _customerContact.text.trim();
    final notes = _notes.text.trim();

    final base = widget.order ??
        CustomerOrder(
          orgId: '',
          siteId: siteId,
          customerName: _customerName.text.trim(),
        );

    final result = base.copyWith(
      siteId: siteId,
      siteName: site.name,
      customerName: _customerName.text.trim(),
      customerContact: contact.isEmpty ? null : contact,
      clearCustomerContact: contact.isEmpty,
      contactId: _contactId,
      clearContactId: _contactId == null,
      recurrence: _recurrence,
      items: List<CustomerOrderItem>.unmodifiable(_items),
      notes: notes.isEmpty ? null : notes,
      clearNotes: notes.isEmpty,
      pickupDate: _pickupDate,
      clearPickupDate: _pickupDate == null,
    );
    Navigator.of(context).pop(result);
  }
}

class _PickupDateField extends StatelessWidget {
  const _PickupDateField({
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Abholtermin',
        suffixIcon: value == null
            ? const Icon(Icons.event)
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: onClear,
              ),
      ),
      child: InkWell(
        onTap: onPick,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            value == null ? 'Kein Termin' : _dateFormat.format(value!),
          ),
        ),
      ),
    );
  }
}

class _ItemsEditor extends StatelessWidget {
  const _ItemsEditor({
    required this.items,
    required this.categories,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final List<CustomerOrderItem> items;
  final List<String> categories;
  final VoidCallback onAdd;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Positionen',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Position'),
            ),
          ],
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Noch keine Positionen.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          )
        else
          for (var i = 0; i < items.length; i++)
            _ItemRow(
              item: items[i],
              onTap: () => onEdit(i),
              onRemove: () => onRemove(i),
            ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  final CustomerOrderItem item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final details = <String>[
      '${item.quantity} ${item.unit}',
      if (item.category?.isNotEmpty ?? false) item.category!,
      if (item.unitPriceCents != null)
        '${_formatCents(item.unitPriceCents)} / ${item.unit}',
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      onTap: onTap,
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        details.join('  ·  '),
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Entfernen',
        onPressed: onRemove,
      ),
    );
  }
}

// ===========================================================================
// Dialog: einzelne Position
// ===========================================================================

Future<CustomerOrderItem?> showCustomerOrderItemDialog(
  BuildContext context, {
  CustomerOrderItem? item,
  List<String> categories = const [],
}) {
  return showDialog<CustomerOrderItem>(
    context: context,
    builder: (_) => _CustomerOrderItemDialog(item: item, categories: categories),
  );
}

class _CustomerOrderItemDialog extends StatefulWidget {
  const _CustomerOrderItemDialog({this.item, this.categories = const []});

  final CustomerOrderItem? item;
  final List<String> categories;

  @override
  State<_CustomerOrderItemDialog> createState() =>
      _CustomerOrderItemDialogState();
}

class _CustomerOrderItemDialogState extends State<_CustomerOrderItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _unit;
  late final TextEditingController _quantity;
  late final TextEditingController _price;
  String? _productId;
  String? _sku;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name = TextEditingController(text: item?.name ?? '');
    _category = TextEditingController(text: item?.category ?? '');
    _unit = TextEditingController(text: item?.unit ?? 'Stück');
    _quantity = TextEditingController(text: (item?.quantity ?? 1).toString());
    _price = TextEditingController(text: _centsToEuroInput(item?.unitPriceCents));
    _productId = item?.productId;
    _sku = item?.sku;
  }

  Future<void> _pickProduct() async {
    final products = context.read<InventoryProvider>().products;
    final picked = await showModalBottomSheet<Product>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ProductPickSheet(products: products),
    );
    if (picked == null) return;
    setState(() {
      _productId = picked.id;
      _sku = picked.sku;
      _name.text = picked.name;
      if (picked.category != null) _category.text = picked.category!;
      _unit.text = picked.unit;
      if (picked.sellingPriceCents != null) {
        _price.text = _centsToEuroInput(picked.sellingPriceCents);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _unit.dispose();
    _quantity.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.item != null;
    return AlertDialog(
      title: Text(isEdit ? 'Position bearbeiten' : 'Neue Position'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _pickProduct,
                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: Text(_productId == null
                        ? 'Aus Warenwirtschaft wählen'
                        : 'Verknüpfter Artikel ändern'),
                  ),
                ),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Artikel *'),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Bitte einen Artikel angeben'
                      : null,
                ),
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: _category.text),
                  optionsBuilder: (value) {
                    if (value.text.isEmpty) {
                      return widget.categories;
                    }
                    return widget.categories.where((category) => category
                        .toLowerCase()
                        .contains(value.text.toLowerCase()));
                  },
                  onSelected: (value) => _category.text = value,
                  fieldViewBuilder:
                      (context, controller, focusNode, onSubmit) {
                    // controller.text NICHT bei jedem Rebuild überschreiben —
                    // das setzt den Cursor zurück und zerstört die Eingabe.
                    // initialValue (oben) seedet den Startwert einmalig.
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration:
                          const InputDecoration(labelText: 'Warengruppe'),
                      onChanged: (value) => _category.text = value,
                    );
                  },
                ),
                Builder(
                  builder: (context) {
                    final quantityField = TextFormField(
                      controller: _quantity,
                      decoration: const InputDecoration(labelText: 'Menge *'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      validator: (value) {
                        final qty = int.tryParse((value ?? '').trim());
                        return (qty == null || qty <= 0) ? 'Menge > 0' : null;
                      },
                    );
                    final unitField = TextFormField(
                      controller: _unit,
                      decoration: const InputDecoration(labelText: 'Einheit'),
                    );
                    final priceField = TextFormField(
                      controller: _price,
                      decoration: const InputDecoration(labelText: 'Preis €'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    );
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        // Auf schmalen Geräten (iPhone SE/kleines Android)
                        // brechen drei Felder in einer Row die Labels ab →
                        // zweizeilig: Menge+Einheit oben, Preis darunter.
                        if (constraints.maxWidth < 340) {
                          return Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: quantityField),
                                  const SizedBox(width: 12),
                                  Expanded(child: unitField),
                                ],
                              ),
                              priceField,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: quantityField),
                            const SizedBox(width: 12),
                            Expanded(child: unitField),
                            const SizedBox(width: 12),
                            Expanded(child: priceField),
                          ],
                        );
                      },
                    );
                  },
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
          onPressed: _submit,
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final category = _category.text.trim();
    final unit = _unit.text.trim();
    final result = CustomerOrderItem(
      productId: _productId,
      name: _name.text.trim(),
      sku: _sku,
      category: category.isEmpty ? null : category,
      unit: unit.isEmpty ? 'Stück' : unit,
      quantity: int.tryParse(_quantity.text.trim()) ?? 1,
      unitPriceCents: _parseEuroToCents(_price.text),
    );
    Navigator.of(context).pop(result);
  }
}

/// Durchsuchbares Auswahl-Sheet für Artikel aus der Warenwirtschaft, um eine
/// Bestellposition mit einem echten [Product] zu verknüpfen.
class _ProductPickSheet extends StatefulWidget {
  const _ProductPickSheet({required this.products});

  final List<Product> products;

  @override
  State<_ProductPickSheet> createState() => _ProductPickSheetState();
}

class _ProductPickSheetState extends State<_ProductPickSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = widget.products.where((p) {
      if (!p.isActive) return false;
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query) ||
          (p.sku?.toLowerCase().contains(query) ?? false) ||
          (p.barcode?.toLowerCase().contains(query) ?? false);
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Artikel suchen',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('Keine Artikel gefunden.'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final product = filtered[index];
                        return ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text(product.name),
                          subtitle: Text([
                            if (product.siteName != null) product.siteName,
                            'Bestand ${product.currentStock} ${product.unit}',
                          ].whereType<String>().join(' · ')),
                          trailing: Text(_formatCents(product.sellingPriceCents)),
                          onTap: () => Navigator.of(context).pop(product),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
