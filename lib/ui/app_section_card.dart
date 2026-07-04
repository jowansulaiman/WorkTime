import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';
import 'app_card.dart';

/// Vereinheitlichte Abschnittskarte (Signal-Teal-Redesign). Restyle der
/// frueheren `SectionCard` (Titel-Pille) und Dedup der Statistik-Variante
/// `_SectionCard` (schlichter Titel) zu einem klaren Header + Inhalt auf Basis
/// von [AppCard]. Optionales [icon] / [trailing] fuer Aktionen rechts.
class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.padding,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    return AppCard(
      padding: padding ?? EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: context.iconSizes.md, color: theme.colorScheme.primary),
                SizedBox(width: spacing.sm),
              ],
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          SizedBox(height: spacing.s12),
          child,
        ],
      ),
    );
  }
}
