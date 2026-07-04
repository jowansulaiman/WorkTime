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
    // Tonaler Teal-Gradient als markanter Fokuspunkt (M3 Expressive). Text bleibt
    // dunkel/lesbar (helle Container-Toene). Weicher Akzent-Schatten gibt Tiefe.
    final gradient = switch (tone) {
      AppHeroTone.neutral => LinearGradient(
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.55),
            colorScheme.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      AppHeroTone.accent => LinearGradient(
          colors: [
            colorScheme.secondaryContainer,
            colorScheme.primaryContainer.withValues(alpha: 0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
    };

    return Container(
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(context.radii.xxl),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.10),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.all(context.spacing.xl),
        child: child,
      ),
    );
  }
}
