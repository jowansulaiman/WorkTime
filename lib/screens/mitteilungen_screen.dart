import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/app_notification.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';
import '../routing/route_permissions.dart';
import '../ui/ui.dart';

/// **PERSONAL-9/Q4 — Mitteilungs-Inbox `/mitteilungen`.** Liest die eigenen
/// In-App-Mitteilungen (server-erzeugt); Tap navigiert über das `route`-Feld
/// und markiert als gelesen. Für jeden angemeldeten Nutzer erreichbar.
class MitteilungenScreen extends StatelessWidget {
  const MitteilungenScreen({super.key, this.parentLabel = 'Übersicht'});

  final String parentLabel;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();
    final items = provider.notifications;
    final df = DateFormat('dd.MM.yyyy HH:mm', 'de_DE');

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: parentLabel,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const BreadcrumbItem(label: 'Mitteilungen'),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: items.isEmpty
                ? const AppEmptyState(
                    icon: Icons.notifications_none_outlined,
                    message: 'Keine Mitteilungen.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _NotificationTile(
                      notification: items[index],
                      dateLabel: items[index].createdAt == null
                          ? ''
                          : df.format(items[index].createdAt!),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.dateLabel,
  });

  final AppNotification notification;
  final String dateLabel;

  Future<void> _onTap(BuildContext context) async {
    final provider = context.read<NotificationProvider>();
    await provider.markAsRead(notification);
    if (!context.mounted) return;
    // Navigation über das vorhandene `route`-Feld — nur, wenn der Nutzer das
    // Ziel überhaupt sehen darf (sonst würde der Redirect ihn ohnehin abweisen).
    final route = notification.route;
    if (route != null && route.isNotEmpty) {
      final profile = context.read<AuthProvider>().profile;
      if (RoutePermissions.isLocationAllowed(route, profile)) {
        context.push(route);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    return Card(
      margin: EdgeInsets.zero,
      color: notification.isUnread ? appColors.infoContainer : null,
      child: ListTile(
        leading: Icon(
          notification.isUnread
              ? Icons.notifications_active_outlined
              : Icons.notifications_none_outlined,
          color: notification.isUnread ? appColors.info : null,
        ),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight:
                notification.isUnread ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(notification.body),
            if (dateLabel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(dateLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ],
          ],
        ),
        trailing: (notification.route != null && notification.route!.isNotEmpty)
            ? const Icon(Icons.chevron_right)
            : null,
        onTap: () => _onTap(context),
      ),
    );
  }
}
