import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';

/// Tonalitaet einer [AppHeroCard].
enum AppHeroTone {
  /// Neutrale Flaeche (surfaceContainerLow) — z. B. Mitarbeiter-Hero.
  neutral,

  /// Akzentuierte Flaeche (secondaryContainer-Tint) — z. B. Planer-Hero.
  accent,
}

/// Prominente „Hero"-Huelle (Signal-Teal-Redesign, M3 Expressive). Gemeinsame
/// Schale fuer die zuvor getrennten `_EmployeeHeroCard` und `_PlannerHeroCard`:
/// grosser Radius (xxl36), grosszuegiges Padding, optionaler Akzent-Hintergrund.
///
/// Bewusst minimal (nur [child]), damit die sehr unterschiedlichen Hero-Inhalte
/// + ihre Provider-Logik in den jeweiligen Screens bleiben.
class AppHeroCard extends StatelessWidget {
  const AppHeroCard({
    super.key,
    required this.child,
    this.tone = AppHeroTone.neutral,
    this.padding,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final AppHeroTone tone;
  final EdgeInsetsGeometry? padding;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = switch (tone) {
      AppHeroTone.neutral => colorScheme.surfaceContainerLow,
      AppHeroTone.accent =>
        colorScheme.secondaryContainer.withValues(alpha: 0.72),
    };

    return Container(
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(context.radii.xxl),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.all(context.spacing.lg),
        child: child,
      ),
    );
  }
}
