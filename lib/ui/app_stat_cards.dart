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
          SizedBox(height: context.spacing.s12),
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
          // §4.11 G4: kein Akzent-@0.12-Chip (Admin-Template-Look) — nur das
          // farbige Icon (flach, warm-editorial); der Wert trägt die Aussage.
          Icon(icon, color: color, size: context.iconSizes.lg),
          SizedBox(width: spacing.s12),
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
                    fontWeight: FontWeight.w800,
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
/// **Schwellen, Clamp & Format bleiben 1:1** (Signed-Hours, Fortschritts-Clamp,
/// exakte deutsche Texte). Akzent (§4.11 G2): laedt → primary, unter Soll →
/// error, auf/über Soll → `appColors.success` (grün; früher „über Soll" =
/// tertiary = im Strichmännchen-Theme Warngelb).
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
    final isUnder = diff < -0.1;
    // §4.11 G2: „über Soll" bezog die Farbe aus colorScheme.tertiary — im
    // Strichmännchen-Theme = Warngelb (semantische Kollision). Ziel erreicht
    // ODER übertroffen = grün (appColors.success); nur „unter Soll" bleibt rot.
    final accentColor = loading
        ? colorScheme.primary
        : isUnder
            ? colorScheme.error
            : appColors.success;
    // §4.11 G2b: Der Balken trägt den vollen (hellen) success-Ton; als Text/Icon
    // ist openGreen (~2,84:1) im Strich-Theme zu hell → `onSuccessContainer`
    // (text-sicher in hell UND dunkel). under/loading sind bereits text-sicher.
    final accentInk = loading
        ? colorScheme.primary
        : isUnder
            ? colorScheme.error
            : appColors.onSuccessContainer;
    final progress = safePlannedHours > 0
        ? (actualHours / safePlannedHours).clamp(0.0, 1.0)
        : 0.0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // §4.11 G4: Icon ohne Chip (flach, warm-editorial).
              Icon(Icons.compare_arrows,
                  color: accentInk, size: context.iconSizes.lg),
              SizedBox(width: spacing.s12),
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
                  color: accentInk,
                  fontWeight: FontWeight.w800,
                  fontFeatures: _tabularFigures,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.s12),
          Text(
            loading
                ? 'Geplante Schichten werden geladen'
                : '${actualHours.toStringAsFixed(1)} h Ist von ${safePlannedHours.toStringAsFixed(1)} h Soll',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: spacing.s12),
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
