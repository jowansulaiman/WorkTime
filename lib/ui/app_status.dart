import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';

/// Semantischer Farbton fuer Status-Komponenten ([AppStatusBadge],
/// [AppStatusBanner]). Bindet an benannte Theme-Rollen bzw. [AppThemeColors] —
/// nie an Hex-Werte. So bleiben Ampel-/Status-Hues die eine Quelle der Wahrheit.
enum AppStatusTone { neutral, primary, secondary, tertiary, success, warning, info, error }

/// Aufgeloeste Farbquadrupel eines [AppStatusTone] aus dem aktiven Theme.
class _ToneColors {
  const _ToneColors(this.color, this.onColor, this.container, this.onContainer);
  final Color color;
  final Color onColor;
  final Color container;
  final Color onContainer;
}

_ToneColors _resolveTone(BuildContext context, AppStatusTone tone) {
  final scheme = Theme.of(context).colorScheme;
  final status = Theme.of(context).appColors;
  switch (tone) {
    case AppStatusTone.neutral:
      return _ToneColors(
        scheme.onSurfaceVariant,
        scheme.surface,
        scheme.surfaceContainerHigh,
        scheme.onSurface,
      );
    case AppStatusTone.primary:
      return _ToneColors(scheme.primary, scheme.onPrimary,
          scheme.primaryContainer, scheme.onPrimaryContainer);
    case AppStatusTone.secondary:
      return _ToneColors(scheme.secondary, scheme.onSecondary,
          scheme.secondaryContainer, scheme.onSecondaryContainer);
    case AppStatusTone.tertiary:
      return _ToneColors(scheme.tertiary, scheme.onTertiary,
          scheme.tertiaryContainer, scheme.onTertiaryContainer);
    case AppStatusTone.error:
      return _ToneColors(scheme.error, scheme.onError, scheme.errorContainer,
          scheme.onErrorContainer);
    case AppStatusTone.success:
      return _ToneColors(status.success, status.onSuccess,
          status.successContainer, status.onSuccessContainer);
    case AppStatusTone.warning:
      return _ToneColors(status.warning, status.onWarning,
          status.warningContainer, status.onWarningContainer);
    case AppStatusTone.info:
      return _ToneColors(
          status.info, status.onInfo, status.infoContainer, status.onInfoContainer);
  }
}

/// Vereinheitlichtes Status-Pill (Signal-Teal-Redesign). Loest die frueheren
/// file-private `_ShiftStatusBadge` (weicher Akzent @0.12) und
/// `_LocationStatusBadge` (gefuellter Container) in **ein** Widget auf. Der
/// Aufrufer waehlt Ton + Variante; das Mapping fachlicher Enums (z. B.
/// `ShiftStatus`) auf [AppStatusTone] bleibt im jeweiligen Screen.
class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.filled = false,
  });

  final String label;
  final AppStatusTone tone;
  final IconData? icon;

  /// `false` (Default): weiche Variante — Akzentfarbe @0.12 als Hintergrund,
  /// Akzentfarbe als Text (entspricht dem alten Schicht-Status-Badge).
  /// `true`: gefuellte Variante — Container-Farbe als Hintergrund,
  /// onContainer als Text (entspricht dem alten Standort-Badge).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final tones = _resolveTone(context, tone);
    final background =
        filled ? tones.container : tones.color.withValues(alpha: 0.12);
    // §4.11 G5: Soft-Variante trug bisher `tones.color` als Text — bei hellen
    // Tönen (Strich: warning=gelb ~1,4:1, success=openGreen ~2,8:1) ein WCAG-Fail.
    // `onContainer` (kontrastgeprüft) ist auf Container UND auf color@0.12 lesbar.
    final foreground = tones.onContainer;
    final spacing = context.spacing;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.s12,
        vertical: spacing.s6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(context.radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: context.iconSizes.sm, color: foreground),
            SizedBox(width: spacing.s6),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

/// Praesentationaler Status-Banner (Signal-Teal-Redesign). Die Render-Haelfte
/// des frueheren `_ShellStatusBanner` — die Provider-Beobachtung (Local-/Sync-/
/// Fehlerstatus) bleibt bewusst im Home-Screen. Der Aufrufer wickelt das Widget
/// in das gewuenschte aeussere Padding.
class AppStatusBanner extends StatelessWidget {
  const AppStatusBanner({
    super.key,
    required this.icon,
    required this.message,
    required this.tone,
    this.action,
  });

  final IconData icon;
  final String message;
  final AppStatusTone tone;

  /// Optionale Aktion rechts (z. B. „Jetzt synchronisieren").
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = _resolveTone(context, tone).color;
    final spacing = context.spacing;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: spacing.s12,
        vertical: spacing.s12,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(context.radii.lg),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: context.iconSizes.sm),
          SizedBox(width: spacing.s12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
