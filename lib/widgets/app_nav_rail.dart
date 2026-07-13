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
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Anzahl offener Punkte als kleines Badge am Icon (0 = kein Badge).
  final int badgeCount;
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
    this.onSearch,
    this.themeAction,
    this.expandedLabels = false,
  });

  final List<AppNavRailItem> items;

  /// Index des aktiven Eintrags; `-1` = keiner (z. B. Menü offen).
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onOpenMenu;

  /// Globale Suche (Anf. 24). Null → kein Such-Button (Rückwärtskompatibel).
  final VoidCallback? onSearch;

  /// Optionaler Aktions-Knopf oben in der Leiste (z. B. Hell/Dunkel-Umschalter).
  /// Null → kein Knopf (rückwärtskompatibel; isolierte Tests brauchen dann
  /// keinen zusätzlichen Provider).
  final Widget? themeAction;
  final AppUserProfile? user;

  /// Mehr Breite + Weißraum ab dem Expanded-Window-Breakpoint (≥840).
  final bool expandedLabels;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final spacing = context.spacing;
    final width = expandedLabels ? 216.0 : 104.0;

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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Brand(expanded: expandedLabels),
            SizedBox(height: spacing.md),
            if (onSearch != null) ...[
              _RailUtilityButton(
                icon: Icons.search_rounded,
                label: 'Suchen',
                expanded: expandedLabels,
                onTap: onSearch!,
              ),
              SizedBox(height: spacing.s12),
            ],
            if (themeAction != null) ...[
              themeAction!,
              SizedBox(height: spacing.s12),
            ],
            if (expandedLabels) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(
                  spacing.s12,
                  spacing.xs,
                  spacing.s12,
                  spacing.sm,
                ),
                child: Text(
                  'BEREICHE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: items.length,
                separatorBuilder: (_, _) => SizedBox(height: spacing.xs),
                itemBuilder:
                    (context, index) => _RailItem(
                      item: items[index],
                      selected: index == selectedIndex,
                      expanded: expandedLabels,
                      onTap: () => onSelected(index),
                    ),
              ),
            ),
            SizedBox(height: spacing.sm),
            _AccountButton(
              user: user,
              expanded: expandedLabels,
              onTap: onOpenMenu,
            ),
          ],
        ),
      ),
    );
  }
}

class _RailUtilityButton extends StatelessWidget {
  const _RailUtilityButton({
    required this.icon,
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return IconButton(tooltip: label, icon: Icon(icon), onPressed: onTap);
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: context.iconSizes.sm),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.symmetric(horizontal: context.spacing.s12),
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
    required this.expanded,
    required this.onTap,
  });

  final AppNavRailItem item;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    final radius = BorderRadius.circular(context.radii.lg);

    final fg = selected ? colorScheme.primary : colorScheme.onSurfaceVariant;
    final icon =
        item.badgeCount > 0
            ? Badge(
              label: Text('${item.badgeCount}'),
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                color: fg,
                size: context.iconSizes.md,
              ),
            )
            : Icon(
              selected ? item.selectedIcon : item.icon,
              color: fg,
              size: context.iconSizes.md,
            );

    final label = Text(
      item.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: expanded ? TextAlign.start : TextAlign.center,
      style: theme.textTheme.labelLarge?.copyWith(
        color: selected ? colorScheme.onSurface : fg,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
      ),
    );

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
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? spacing.s12 : spacing.xs,
              vertical: spacing.s12,
            ),
            decoration: BoxDecoration(
              color:
                  selected
                      ? colorScheme.secondaryContainer.withValues(alpha: 0.72)
                      : Colors.transparent,
              borderRadius: radius,
              border:
                  selected
                      ? Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.22),
                      )
                      : null,
            ),
            child:
                expanded
                    ? Row(
                      children: [
                        icon,
                        SizedBox(width: spacing.s12),
                        Expanded(child: label),
                        if (selected)
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: colorScheme.primary,
                          ),
                      ],
                    )
                    : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [icon, SizedBox(height: spacing.xs), label],
                    ),
          ),
        ),
      ),
    );
  }
}

class _AccountButton extends StatelessWidget {
  const _AccountButton({
    required this.user,
    required this.expanded,
    required this.onTap,
  });

  final AppUserProfile? user;
  final bool expanded;
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
            child:
                expanded
                    ? Row(
                      children: [
                        _AccountAvatar(initial: initial),
                        SizedBox(width: spacing.s12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: spacing.xxs),
                              Text(
                                user?.role.label ?? 'Profil',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    )
                    : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _AccountAvatar(initial: initial),
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
                        Text(
                          'Menü',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
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

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
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
    );
  }
}
