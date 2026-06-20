import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../theme/theme_extensions.dart';
import 'app_logo.dart';

/// Ein Eintrag der [AppNavRail].
class AppNavRailItem {
  const AppNavRailItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Moderne, maßgeschneiderte Seitenleiste für das V2-Redesign (Signal-Teal).
/// Ersetzt die generische Material-`NavigationRail`: getönter Vertikal-Gradient,
/// Brand-Marke oben, Nav-Items mit weichem Teal-Indikator (animiert) und ein
/// Account-Knopf unten (Avatar mit Gradient-Ring), der das Slide-in-Menü öffnet.
///
/// Bewusst rein präsentational (Daten + Callbacks herein) — isoliert testbar.
class AppNavRail extends StatelessWidget {
  const AppNavRail({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.onOpenMenu,
    required this.user,
    this.expandedLabels = false,
  });

  final List<AppNavRailItem> items;

  /// Index des aktiven Eintrags; `-1` = keiner (z. B. Menü offen).
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onOpenMenu;
  final AppUserProfile? user;

  /// Mehr Breite + Weißraum ab dem Expanded-Window-Breakpoint (≥840).
  final bool expandedLabels;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final spacing = context.spacing;
    final width = expandedLabels ? 188.0 : 112.0;

    return Container(
      width: width,
      decoration: BoxDecoration(
        // Dezent teal-getönter Vertikal-Gradient — hebt die Leiste sanft vom
        // Inhalt ab, ohne eine harte Trennlinie zu brauchen.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.14),
            colorScheme.surfaceContainerLow,
          ],
        ),
        border: Border(
          right: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.sm,
          vertical: spacing.md,
        ),
        child: Column(
          children: [
            _Brand(expanded: expandedLabels),
            SizedBox(height: spacing.lg),
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) SizedBox(height: spacing.xs),
              _RailItem(
                item: items[i],
                selected: i == selectedIndex,
                onTap: () => onSelected(i),
              ),
            ],
            const Spacer(),
            SizedBox(height: spacing.sm),
            _AccountButton(user: user, onTap: onOpenMenu),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(context.spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(context.radii.lg),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: AppLogo(height: expanded ? 34 : 30),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AppNavRailItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    final radius = BorderRadius.circular(context.radii.lg);

    final fg = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: AnimatedContainer(
            duration: context.motion.short,
            curve: context.motion.standard,
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: spacing.sm + spacing.xs),
            decoration: BoxDecoration(
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colorScheme.secondaryContainer,
                        colorScheme.primaryContainer.withValues(alpha: 0.7),
                      ],
                    )
                  : null,
              borderRadius: radius,
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? item.selectedIcon : item.icon,
                  color: fg,
                  size: context.iconSizes.md,
                ),
                SizedBox(height: spacing.xs),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.user, required this.onTap});

  final AppUserProfile? user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    final name = user?.displayName ?? 'Profil';
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();

    return Tooltip(
      message: 'Menü öffnen',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(context.radii.lg),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              vertical: spacing.sm,
              horizontal: spacing.xs,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(context.radii.lg),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Avatar mit weichem Gradient-Ring (Teal → Tertiär).
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [colorScheme.primary, colorScheme.tertiary],
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                    child: Text(
                      initial,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: spacing.xs),
                Text(
                  user?.role.label ?? 'Profil',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: spacing.xxs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.unfold_more_rounded,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        'Menü',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
