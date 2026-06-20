import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';
import 'app_card.dart';

/// Tabellenziffern fuer Zahlen-Rollen (Uhr, Stunden, Plan/Ist) — gleiche
/// Zeichenbreite, damit Werte nicht „springen". Opt-in (nicht global, sonst
/// bricht Fliesstext).
const List<FontFeature> _tabularFigures = [FontFeature.tabularFigures()];

/// Kompakte Kennzahlkarte (Label + grosser Wert + optionales Icon).
/// Restyle von `_DashboardMetricCard` (mit Icon) und der Statistik-`_MetricCard`
/// (ohne Icon) — daher [icon] optional. Wert in Tabellenziffern.
class AppMetricCard extends StatelessWidget {
  const AppMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (icon != null)
                Icon(icon, color: colorScheme.primary, size: context.iconSizes.sm),
            ],
          ),
          SizedBox(height: context.spacing.md - context.spacing.xxs),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: _tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kennzahlkarte mit farbigem Icon-Chip, Wert und Untertitel.
/// Restyle von `_StatCard{label, value, subtitle, icon, color}`; [color] treibt
/// weiterhin den Akzent (Aufrufer uebergibt eine benannte Theme-Rolle).
class AppStatCard extends StatelessWidget {
  const AppStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    return AppCard(
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(spacing.sm + spacing.xxs),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(context.radii.md),
            ),
            child: Icon(icon, color: color),
          ),
          SizedBox(width: spacing.sm + spacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: spacing.xxs),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFeatures: _tabularFigures,
                  ),
                ),
                SizedBox(height: spacing.xs),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Soll/Ist-Vergleichskarte mit Fortschrittsbalken. Restyle von
/// `_PlannedActualStatCard{plannedHours, actualHours, loading}`.
///
/// **Die Mathematik ist 1:1 erhalten** (Schwellen, Akzentfarb-Logik,
/// Fortschritts-Clamp, Signed-Hours-Format, exakte deutsche Texte), damit der
/// spaetere Screen-Swap verhaltensidentisch ist. Akzent: laedt → primary,
/// ueber Soll → tertiary, unter Soll → error, sonst → `appColors.success`.
class AppComparisonStatCard extends StatelessWidget {
  const AppComparisonStatCard({
    super.key,
    required this.plannedHours,
    required this.actualHours,
    required this.loading,
  });

  final double? plannedHours;
  final double actualHours;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    final spacing = context.spacing;

    final safePlannedHours = plannedHours ?? 0;
    final diff = actualHours - safePlannedHours;
    final isOver = diff > 0.1;
    final isUnder = diff < -0.1;
    final accentColor = loading
        ? colorScheme.primary
        : isOver
            ? colorScheme.tertiary
            : isUnder
                ? colorScheme.error
                : appColors.success;
    final progress = safePlannedHours > 0
        ? (actualHours / safePlannedHours).clamp(0.0, 1.0)
        : 0.0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(spacing.sm + spacing.xxs),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(context.radii.md),
                ),
                child: Icon(Icons.compare_arrows, color: accentColor),
              ),
              SizedBox(width: spacing.sm + spacing.xs),
              Expanded(
                child: Text(
                  'Soll / Ist',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                loading ? 'Laedt...' : _formatSignedHours(diff),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                  fontFeatures: _tabularFigures,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.md - spacing.xs),
          Text(
            loading
                ? 'Geplante Schichten werden geladen'
                : '${actualHours.toStringAsFixed(1)} h Ist von ${safePlannedHours.toStringAsFixed(1)} h Soll',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: spacing.sm + spacing.xxs),
          ClipRRect(
            borderRadius: BorderRadius.circular(context.radii.pill),
            child: LinearProgressIndicator(
              value: loading ? null : progress,
              minHeight: 8,
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Vorzeichenbehaftete Stundenformatierung — identisch zum frueheren
/// `_formatSignedHours` im Home-Screen (Vorzeichen nur ab > 0.05).
String _formatSignedHours(double value) {
  final prefix = value > 0.05 ? '+' : '';
  return '$prefix${value.toStringAsFixed(1)} h';
}
