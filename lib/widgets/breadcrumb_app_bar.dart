import 'package:flutter/material.dart';

/// Ein Breadcrumb-Pfad-Element.
class BreadcrumbItem {
  const BreadcrumbItem({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;
}

/// AppBar mit Breadcrumb-Pfad fuer gepushte Screens.
///
/// Zeigt einen klickbaren Pfad wie "Profil / Einstellungen" und
/// einen Zurueck-Button.
class BreadcrumbAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BreadcrumbAppBar({
    super.key,
    required this.breadcrumbs,
    this.actions,
  });

  final List<BreadcrumbItem> breadcrumbs;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppBar(
      titleSpacing: 0,
      title: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < breadcrumbs.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              _BreadcrumbChip(
                item: breadcrumbs[i],
                isLast: i == breadcrumbs.length - 1,
              ),
            ],
          ],
        ),
      ),
      actions: actions,
    );
  }
}

class _BreadcrumbChip extends StatelessWidget {
  const _BreadcrumbChip({
    required this.item,
    required this.isLast,
  });

  final BreadcrumbItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (isLast) {
      return Text(
        item.label,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          item.label,
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// Inline-Breadcrumb-Leiste fuer Shell-Tabs (kein AppBar, nur ein Pfad-Widget).
class ShellBreadcrumb extends StatelessWidget {
  const ShellBreadcrumb({
    super.key,
    required this.breadcrumbs,
    this.onBack,
    this.trailing,
  });

  final List<BreadcrumbItem> breadcrumbs;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          if (onBack != null) ...[
            IconButton(
              tooltip: 'Zurueck',
              visualDensity: VisualDensity.compact,
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Icon(
                    Icons.home_outlined,
                    size: 18,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  for (int i = 0; i < breadcrumbs.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    if (i < breadcrumbs.length - 1 &&
                        breadcrumbs[i].onTap != null)
                      InkWell(
                        onTap: breadcrumbs[i].onTap,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Text(
                            breadcrumbs[i].label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      )
                    else
                      Text(
                        breadcrumbs[i].label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: i == breadcrumbs.length - 1
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                          fontWeight: i == breadcrumbs.length - 1
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}
