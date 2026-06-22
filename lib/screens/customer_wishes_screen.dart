import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/customer_wish.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/empty_state.dart';

/// Interner Eingang der über die öffentliche Webseite (/wunsch) abgegebenen
/// Kundenwünsche. Aktive Mitglieder sehen den Eingang; Manager
/// (canManageInventory) bearbeiten Status/löschen.
///
/// Wünsche sind reine Cloud-Daten (anonym von außen erzeugt), daher liest der
/// Screen direkt per [FirestoreService]-Stream — kein Provider/lokaler Spiegel.
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

  static final DateFormat _dateTimeFormat =
      DateFormat('dd.MM.yyyy HH:mm', 'de_DE');
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

    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: StreamBuilder<List<CustomerWish>>(
              stream: _service.watchCustomerWishes(profile.orgId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Kundenwünsche konnten nicht geladen werden.'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final all = snapshot.data!;
                final visible = _showClosed
                    ? all
                    : all.where((wish) => wish.status.isOpen).toList();
                final openCount =
                    all.where((wish) => wish.status.isOpen).length;

                return Column(
                  children: [
                    _buildHeader(context, openCount),
                    Expanded(
                      child: visible.isEmpty
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
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 14),
                              itemBuilder: (context, index) => _WishCard(
                                wish: visible[index],
                                canManage: canManage,
                                dateTimeFormat: _dateTimeFormat,
                                dateFormat: _dateFormat,
                                onStatus: (status) =>
                                    _updateStatus(visible[index], status),
                                onDelete: () => _delete(visible[index]),
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
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
            child: Icon(Icons.inbox_outlined,
                color: scheme.onPrimaryContainer, size: 22),
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
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
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
    try {
      await _service.updateCustomerWishStatus(
        orgId: wish.orgId,
        wishId: id,
        status: status,
        handledByUid: profile?.uid,
      );
    } catch (_) {
      _snack('Status konnte nicht geändert werden.');
    }
  }

  Future<void> _delete(CustomerWish wish) async {
    final id = wish.id;
    if (id == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
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
    if (confirmed != true) {
      return;
    }
    try {
      await _service.deleteCustomerWish(orgId: wish.orgId, wishId: id);
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
  });

  final CustomerWish wish;
  final bool canManage;
  final DateFormat dateTimeFormat;
  final DateFormat dateFormat;
  final ValueChanged<CustomerWishStatus> onStatus;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _WishAction.seen,
                        child: Text('Als gesehen markieren'),
                      ),
                      PopupMenuItem(
                        value: _WishAction.done,
                        child: Text('Als erledigt markieren'),
                      ),
                      PopupMenuItem(
                        value: _WishAction.rejected,
                        child: Text('Ablehnen'),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
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
                    Icon(Icons.person_outline,
                        size: 18, color: scheme.onSurfaceVariant),
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
            if (wish.createdAt != null) ...[
              const SizedBox(height: 10),
              Text(
                'Eingegangen: ${dateTimeFormat.format(wish.createdAt!.toLocal())}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _WishAction { seen, done, rejected, delete }

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final CustomerWishStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (status) {
      CustomerWishStatus.pending => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer
        ),
      CustomerWishStatus.seen => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer
        ),
      CustomerWishStatus.done => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant
        ),
      CustomerWishStatus.rejected => (
          scheme.errorContainer,
          scheme.onErrorContainer
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
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
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
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
