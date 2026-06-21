import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../screens/customer_order_screen.dart';
import '../screens/inventory_screen.dart';
import '../ui/ui.dart';

/// Eine gebuendelte „Hinweise & Aktionspunkte"-Karte fuer das Home-Dashboard.
///
/// Fasst die verstreuten Warnungen (ueberfaellige/bald faellige, nicht
/// vorbereitete Kundenbestellungen sowie nachzubestellende Artikel) zu einer
/// severity-sortierten Liste zusammen und ersetzt die fruheren Einzel-Banner
/// ([CustomerOrderWarningBanner], LowStockWarningBanner). Speist sich aus
/// denselben Quellen der Wahrheit im [InventoryProvider]. Blendet sich aus,
/// wenn nichts ansteht oder die Berechtigung fehlt. Spark-frugal: rein
/// berechnet, keine Persistenz.
class DashboardActionItemsCard extends StatelessWidget {
  const DashboardActionItemsCard({super.key, this.parentLabel = 'Heute'});

  final String parentLabel;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    if (profile == null || !profile.canViewInventory) {
      return const SizedBox.shrink();
    }
    final inventory = context.watch<InventoryProvider>();
    final dueOrders = inventory.ordersDueSoonNotPrepared();
    final lowStock = inventory.lowStockProducts();
    if (dueOrders.isEmpty && lowStock.isEmpty) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final overdue = dueOrders
        .where((o) => o.pickupDate != null && o.pickupDate!.isBefore(today))
        .length;
    final dueSoon = dueOrders.length - overdue;

    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final errorColor = theme.colorScheme.error;

    void openOrders() => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CustomerOrderScreen(parentLabel: parentLabel),
          ),
        );
    void openInventory() => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => InventoryScreen(parentLabel: parentLabel),
          ),
        );

    final items = <_ActionItem>[
      if (overdue > 0)
        _ActionItem(
          severity: 2,
          icon: Icons.shopping_bag_outlined,
          color: errorColor,
          label: '$overdue ${overdue == 1 ? 'Bestellung ist überfällig' : 'Bestellungen sind überfällig'} '
              'und nicht vorbereitet',
          onTap: openOrders,
        ),
      if (dueSoon > 0)
        _ActionItem(
          severity: 1,
          icon: Icons.shopping_bag_outlined,
          color: appColors.warning,
          label: '$dueSoon ${dueSoon == 1 ? 'Bestellung ist' : 'Bestellungen sind'} '
              'bald fällig und nicht vorbereitet',
          onTap: openOrders,
        ),
      if (lowStock.isNotEmpty)
        _ActionItem(
          severity: 1,
          icon: Icons.inventory_2_outlined,
          color: appColors.warning,
          label: '${lowStock.length} '
              '${lowStock.length == 1 ? 'Artikel sollte' : 'Artikel sollten'} '
              'nachbestellt werden',
          onTap: openInventory,
        ),
    ]..sort((a, b) => b.severity.compareTo(a.severity));

    return Padding(
      padding: EdgeInsets.only(bottom: context.spacing.md),
      child: AppCard(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.md,
          vertical: context.spacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: context.spacing.xs),
              child: Row(
                children: [
                  Icon(Icons.notifications_active_outlined,
                      size: context.iconSizes.sm, color: appColors.warning),
                  SizedBox(width: context.spacing.sm),
                  Text(
                    'Hinweise & Aktionspunkte',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            for (final item in items) _ActionItemRow(item: item),
          ],
        ),
      ),
    );
  }
}

class _ActionItem {
  const _ActionItem({
    required this.severity,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  /// Hoeher = dringender (Sortierschluessel).
  final int severity;
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
}

class _ActionItemRow extends StatelessWidget {
  const _ActionItemRow({required this.item});

  final _ActionItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(context.radii.sm),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: context.spacing.sm),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(context.radii.sm),
              ),
              child: Icon(item.icon, size: context.iconSizes.sm, color: item.color),
            ),
            SizedBox(width: context.spacing.sm),
            Expanded(
              child: Text(item.label, style: theme.textTheme.bodyMedium),
            ),
            Icon(Icons.chevron_right,
                size: context.iconSizes.sm,
                color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
