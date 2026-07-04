import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';
import 'app_card.dart';

/// Grosse Schnellaktions-Kachel (Signal-Teal-Redesign). Restyle von
/// `_QuickActionCard{icon, title, subtitle, onTap}`: dezenter Flaechen-Gradient,
/// Icon-Chip, Pfeil, Titel + Untertitel. API unveraendert.
class AppQuickActionCard extends StatelessWidget {
  const AppQuickActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;

    // Solide Teal-getoente Kachel auf AppCard (Schatten + Radius) — klarer
    // Kachel-Rand und konsistente Tiefe mit den uebrigen Karten.
    return AppCard(
      onTap: onTap,
      color: Color.alphaBlend(
        colorScheme.primaryContainer.withValues(alpha: 0.30),
        colorScheme.surfaceContainerLowest,
      ),
      padding: EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(spacing.s12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(context.radii.md),
            ),
            child: Icon(icon, color: colorScheme.onPrimaryContainer),
          ),
          SizedBox(height: spacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: colorScheme.onSurfaceVariant,
                size: context.iconSizes.sm,
              ),
            ],
          ),
          SizedBox(height: spacing.s12),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Schnellaktions-Listenkachel (Signal-Teal-Redesign). Restyle von
/// `_QuickActionListTile{icon, title, subtitle, onTap}`: [AppCard] mit ListTile,
/// Icon-Avatar und Chevron. Abstand zwischen Kacheln uebernimmt der Parent.
class AppQuickActionTile extends StatelessWidget {
  const AppQuickActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ListTile(
        minVerticalPadding: context.spacing.s12,
        leading: CircleAvatar(
          backgroundColor:
              colorScheme.primaryContainer.withValues(alpha: 0.7),
          child: Icon(icon, color: colorScheme.onPrimaryContainer),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
