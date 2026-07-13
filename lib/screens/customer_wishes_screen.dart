import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/local_demo_inventory_data.dart';
import '../models/audit_log_entry.dart';
import '../models/contact.dart';
import '../models/customer_order.dart';
import '../models/customer_wish.dart';
import '../models/site_definition.dart';
import '../providers/audit_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/contact_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/team_provider.dart';
import '../services/firestore_service.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/contact_picker_field.dart';
import '../widgets/empty_state.dart';

/// Interner Eingang der über die öffentliche Webseite (/wunsch) abgegebenen
/// Kundenwünsche. Aktive Mitglieder sehen den Eingang; Manager
/// (canManageInventory) bearbeiten Status/löschen.
///
/// Produktiv sind Wünsche reine Cloud-Daten und werden direkt per
/// [FirestoreService]-Stream gelesen. Der lokale Demo-Modus hält eine
/// kurzlebige In-Memory-Liste, damit Filter und Bearbeitungsabläufe testbar sind.
class CustomerWishesScreen extends StatefulWidget {
  const CustomerWishesScreen({
    super.key,
    this.parentLabel = 'Warenwirtschaft',
    this.firestoreService,
  });

  final String parentLabel;

  /// Injizierbar für Tests; sonst eigene Instanz (FirebaseFirestore.instance).
  final FirestoreService? firestoreService;

  @override
  State<CustomerWishesScreen> createState() => _CustomerWishesScreenState();
}

class _CustomerWishesScreenState extends State<CustomerWishesScreen> {
  late final FirestoreService _service =
      widget.firestoreService ?? FirestoreService();

  bool _showClosed = false;
  String? _demoOrgId;
  List<CustomerWish> _demoWishes = const [];

  static final DateFormat _dateTimeFormat = DateFormat(
    'dd.MM.yyyy HH:mm',
    'de_DE',
  );
  static final DateFormat _dateFormat = DateFormat('dd.MM.yyyy', 'de_DE');

  static IconData categoryIcon(CustomerWishCategory category) =>
      switch (category) {
        CustomerWishCategory.magazine => Icons.menu_book_outlined,
        CustomerWishCategory.cigarettes => Icons.smoking_rooms_outlined,
        CustomerWishCategory.tobacco => Icons.grass_outlined,
        CustomerWishCategory.other => Icons.more_horiz,
      };

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;

    final appBar = BreadcrumbAppBar(
      breadcrumbs: [
        BreadcrumbItem(
          label: widget.parentLabel,
          onTap: () => Navigator.of(context).pop(),
        ),
        const BreadcrumbItem(label: 'Kundenwünsche'),
      ],
    );

    if (profile == null || !profile.canViewInventory) {
      return Scaffold(
        appBar: appBar,
        body: const Center(
          child: Text('Keine Berechtigung für die Kundenwünsche.'),
        ),
      );
    }

    final canManage = profile.canManageInventory;
    final isLocalDemo = context.read<AuthProvider>().authDisabled;
    if (isLocalDemo && _demoOrgId != profile.orgId) {
      _demoOrgId = profile.orgId;
      _demoWishes = LocalDemoInventoryData.customerWishesForOrg(
        orgId: profile.orgId,
        handledByUid: profile.uid,
      );
    }

    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child:
                isLocalDemo
                    ? _buildWishList(_demoWishes, canManage: canManage)
                    : StreamBuilder<List<CustomerWish>>(
                      stream: _service.watchCustomerWishes(profile.orgId),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Center(
                            child: Text(
                              'Kundenwünsche konnten nicht geladen werden.',
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return _buildWishList(
                          snapshot.data!,
                          canManage: canManage,
                        );
                      },
                    ),
          ),
        ),
      ),
    );
  }

  Widget _buildWishList(List<CustomerWish> all, {required bool canManage}) {
    final visible =
        _showClosed ? all : all.where((wish) => wish.status.isOpen).toList();
    final openCount = all.where((wish) => wish.status.isOpen).length;
    return Column(
      children: [
        _buildHeader(context, openCount),
        Expanded(
          child:
              visible.isEmpty
                  ? const Center(
                    child: EmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'Keine Kundenwünsche',
                      message:
                          'Über die öffentliche Seite (/wunsch) abgegebene Wünsche erscheinen hier.',
                    ),
                  )
                  : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder:
                        (context, index) => _WishCard(
                          wish: visible[index],
                          canManage: canManage,
                          dateTimeFormat: _dateTimeFormat,
                          dateFormat: _dateFormat,
                          onStatus:
                              (status) => _updateStatus(visible[index], status),
                          onDelete: () => _delete(visible[index]),
                          onConvert: () => _convertToOrder(visible[index]),
                          onLinkContact: () => _linkContact(visible[index]),
                        ),
                  ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, int openCount) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.inbox_outlined,
              color: scheme.onPrimaryContainer,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kundenwünsche', style: theme.textTheme.titleLarge),
                Text(
                  openCount == 1
                      ? '1 offener Wunsch'
                      : '$openCount offene Wünsche',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          FilterChip(
            label: const Text('Erledigte'),
            selected: _showClosed,
            onSelected: (value) => setState(() => _showClosed = value),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(
    CustomerWish wish,
    CustomerWishStatus status,
  ) async {
    final id = wish.id;
    if (id == null) {
      return;
    }
    final profile = context.read<AuthProvider>().profile;
    // Kundenwünsche haben keinen eigenen Provider (Mutation läuft direkt über
    // FirestoreService) → der Audit-Eintrag wird hier auf dem Erfolgspfad
    // gesetzt, sonst umginge diese interne Manager-Aktion das Änderungsprotokoll.
    final audit = context.read<AuditProvider>();
    try {
      if (context.read<AuthProvider>().authDisabled) {
        final now = DateTime.now();
        setState(() {
          final index = _demoWishes.indexWhere((item) => item.id == id);
          if (index >= 0) {
            _demoWishes[index] = wish.copyWith(
              status: status,
              handledByUid: profile?.uid,
              handledAt: now,
              updatedAt: now,
            );
          }
        });
      } else {
        await _service.updateCustomerWishStatus(
          orgId: wish.orgId,
          wishId: id,
          status: status,
          handledByUid: profile?.uid,
        );
      }
      audit.log(
        action: AuditAction.updated,
        entityType: 'Kundenwunsch',
        entityId: id,
        summary: 'Wunsch ${wish.referenceCode}: Status „${status.label}"',
      );
    } catch (_) {
      _snack('Status konnte nicht geändert werden.');
    }
  }

  /// Verknüpft einen Wunsch mit einem Kontakt aus der Kontakte-Kartei (H-D2)
  /// bzw. löst die Verknüpfung. Wie bei [_updateStatus] hat der Wunsch keinen
  /// eigenen Provider → der Audit-Eintrag wird hier auf dem Erfolgspfad gesetzt.
  Future<void> _linkContact(CustomerWish wish) async {
    final id = wish.id;
    if (id == null) {
      return;
    }
    final audit = context.read<AuditProvider>();
    final isLocalDemo = context.read<AuthProvider>().authDisabled;
    final selection = await showContactPicker(
      context,
      currentContactId: wish.contactId,
      allowedTypes: const [ContactType.customer],
      emptyLabel: 'Kein Kontakt (Verknüpfung entfernen)',
    );
    if (!mounted || selection == null) {
      return; // abgebrochen
    }
    final contact = selection.contact;
    if (contact?.id == wish.contactId) {
      return; // unverändert → kein Write/Audit für einen No-op
    }
    try {
      if (isLocalDemo) {
        setState(() {
          final index = _demoWishes.indexWhere((item) => item.id == id);
          if (index >= 0) {
            _demoWishes[index] = wish.copyWith(
              contactId: contact?.id,
              clearContactId: contact == null,
              updatedAt: DateTime.now(),
            );
          }
        });
      } else {
        await _service.updateCustomerWishContact(
          orgId: wish.orgId,
          wishId: id,
          contactId: contact?.id,
        );
      }
      audit.log(
        action: AuditAction.updated,
        entityType: 'Kundenwunsch',
        entityId: id,
        summary:
            contact == null
                ? 'Wunsch ${wish.referenceCode}: Kontakt-Verknüpfung entfernt'
                : 'Wunsch ${wish.referenceCode}: Kontakt „${contact.name}" verknüpft',
      );
    } catch (_) {
      _snack('Kontakt konnte nicht verknüpft werden.');
    }
  }

  /// Übernimmt einen Kundenwunsch in eine echte [CustomerOrder] (H-E1).
  /// Idempotent über [CustomerOrder.sourceWishId] (keine Doppel-Übernahme).
  /// Der Wunsch trägt nur einen Klartext-Ladennamen → Standort wird ausgewählt
  /// (mit Namens-Vorauswahl). Anschließend wird der Wunsch auf „erledigt" gesetzt.
  Future<void> _convertToOrder(CustomerWish wish) async {
    final wishId = wish.id;
    if (wishId == null) return;
    final inventory = context.read<InventoryProvider>();
    final sites = context.read<TeamProvider>().sites;

    if (inventory.customerOrders.any((o) => o.sourceWishId == wishId)) {
      _snack('Dieser Wunsch wurde bereits in eine Bestellung übernommen.');
      return;
    }
    if (sites.isEmpty) {
      _snack('Kein Standort angelegt – bitte zuerst einen Laden einrichten.');
      return;
    }

    final siteId = await _pickSite(wish, sites);
    if (siteId == null) return; // abgebrochen
    SiteDefinition? site;
    for (final s in sites) {
      if (s.id == siteId) {
        site = s;
        break;
      }
    }

    // Zuordnung Wunsch→Bestellung zentral im Model (überträgt u. a. die
    // CRM-Verknüpfung contactId/H-D2 und sourceWishId/H-E1, sonst gingen sie
    // beim Übergang still verloren).
    final order = CustomerOrder.fromCustomerWish(
      wish,
      siteId: siteId,
      siteName: site?.name,
    );

    try {
      await inventory.saveCustomerOrder(order);
    } catch (_) {
      _snack('Bestellung konnte nicht angelegt werden.');
      return;
    }
    // Wunsch als erledigt markieren (zweiter, nicht-transaktionaler Write –
    // schlägt er fehl, verhindert sourceWishId trotzdem eine Doppel-Übernahme).
    await _updateStatus(wish, CustomerWishStatus.done);
    _snack('Bestellung aus Wunsch ${wish.referenceCode} angelegt.');
  }

  /// Standort-Auswahl für die Wunsch-Übernahme. Bei genau einem Standort wird
  /// dieser direkt genommen; sonst ein Dialog mit Namens-Vorauswahl.
  Future<String?> _pickSite(
    CustomerWish wish,
    List<SiteDefinition> sites,
  ) async {
    if (sites.length == 1) return sites.first.id;
    final store = wish.storeName.trim().toLowerCase();
    String? preselect;
    for (final s in sites) {
      if (s.name.trim().toLowerCase() == store) {
        preselect = s.id;
        break;
      }
    }
    return showDialog<String>(
      context: context,
      builder:
          (context) => SimpleDialog(
            title: const Text('Standort der Bestellung'),
            children: [
              for (final s in sites)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(s.id),
                  child: Row(
                    children: [
                      Icon(
                        s.id == preselect
                            ? Icons.check_circle
                            : Icons.store_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(s.name)),
                    ],
                  ),
                ),
            ],
          ),
    );
  }

  Future<void> _delete(CustomerWish wish) async {
    final id = wish.id;
    if (id == null) {
      return;
    }
    final audit = context.read<AuditProvider>();
    final isLocalDemo = context.read<AuthProvider>().authDisabled;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Wunsch löschen?'),
            content: Text('Wunsch ${wish.referenceCode} wird gelöscht.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Löschen'),
              ),
            ],
          ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    try {
      if (isLocalDemo) {
        setState(() => _demoWishes.removeWhere((item) => item.id == id));
      } else {
        await _service.deleteCustomerWish(orgId: wish.orgId, wishId: id);
      }
      audit.log(
        action: AuditAction.deleted,
        entityType: 'Kundenwunsch',
        entityId: id,
        summary: 'Wunsch ${wish.referenceCode} gelöscht',
      );
    } catch (_) {
      _snack('Wunsch konnte nicht gelöscht werden.');
    }
  }

  void _snack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _WishCard extends StatelessWidget {
  const _WishCard({
    required this.wish,
    required this.canManage,
    required this.dateTimeFormat,
    required this.dateFormat,
    required this.onStatus,
    required this.onDelete,
    required this.onConvert,
    required this.onLinkContact,
  });

  final CustomerWish wish;
  final bool canManage;
  final DateFormat dateTimeFormat;
  final DateFormat dateFormat;
  final ValueChanged<CustomerWishStatus> onStatus;
  final VoidCallback onDelete;
  final VoidCallback onConvert;
  final VoidCallback onLinkContact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Verknüpften Kontakt live aus der Kontakte-Kartei auflösen (H-D2). `null`,
    // wenn nicht verknüpft ODER der Kontakt (noch) nicht geladen/gelöscht ist.
    // Nur verknüpfte Karten abonnieren den ContactProvider (spart Rebuilds in
    // einem langen Eingang, wenn sich irgendwo ein Kontakt ändert).
    final linkedContact =
        wish.contactId == null
            ? null
            : context.watch<ContactProvider>().contactById(wish.contactId);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    wish.referenceCode,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _StatusChip(status: wish.status),
                const Spacer(),
                if (canManage)
                  PopupMenuButton<_WishAction>(
                    onSelected: (action) {
                      switch (action) {
                        case _WishAction.convert:
                          onConvert();
                        case _WishAction.linkContact:
                          onLinkContact();
                        case _WishAction.seen:
                          onStatus(CustomerWishStatus.seen);
                        case _WishAction.done:
                          onStatus(CustomerWishStatus.done);
                        case _WishAction.rejected:
                          onStatus(CustomerWishStatus.rejected);
                        case _WishAction.delete:
                          onDelete();
                      }
                    },
                    itemBuilder:
                        (_) => [
                          const PopupMenuItem(
                            value: _WishAction.convert,
                            child: Text('In Bestellung übernehmen'),
                          ),
                          PopupMenuItem(
                            value: _WishAction.linkContact,
                            child: Text(
                              wish.contactId == null
                                  ? 'Kontakt verknüpfen'
                                  : 'Kontakt ändern',
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: _WishAction.seen,
                            child: Text('Als gesehen markieren'),
                          ),
                          const PopupMenuItem(
                            value: _WishAction.done,
                            child: Text('Als erledigt markieren'),
                          ),
                          const PopupMenuItem(
                            value: _WishAction.rejected,
                            child: Text('Ablehnen'),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: _WishAction.delete,
                            child: Text('Löschen'),
                          ),
                        ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _InfoChip(
                  icon: _CustomerWishesScreenState.categoryIcon(wish.category),
                  label: wish.category.label,
                ),
                _InfoChip(icon: Icons.tag, label: '${wish.quantity}×'),
                if (wish.storeName.trim().isNotEmpty)
                  _InfoChip(icon: Icons.store_outlined, label: wish.storeName),
                if (wish.desiredDate != null)
                  _InfoChip(
                    icon: Icons.event_outlined,
                    label: dateFormat.format(wish.desiredDate!),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(wish.wishText, style: theme.textTheme.bodyLarge),
            if (wish.hasContact) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [
                          if (wish.customerName?.trim().isNotEmpty ?? false)
                            wish.customerName!.trim(),
                          if (wish.customerContact?.trim().isNotEmpty ?? false)
                            wish.customerContact!.trim(),
                        ].join('  ·  '),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (wish.contactId != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.link, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      linkedContact != null
                          ? 'Kontakt: ${linkedContact.name}'
                          : 'Verknüpfter Kontakt (nicht gefunden)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (wish.createdAt != null) ...[
              const SizedBox(height: 10),
              Text(
                'Eingegangen: ${dateTimeFormat.format(wish.createdAt!.toLocal())}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _WishAction { convert, linkContact, seen, done, rejected, delete }

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final CustomerWishStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (status) {
      CustomerWishStatus.pending => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      CustomerWishStatus.seen => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      CustomerWishStatus.done => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      CustomerWishStatus.rejected => (
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
