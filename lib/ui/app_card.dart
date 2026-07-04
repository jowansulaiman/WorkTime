import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';

/// V2-Basiskarte (Signal-Teal-Redesign). Ersetzt das ueberall wiederholte
/// `Card(Padding(16))`-Muster durch ein tokenisiertes Primitiv: Form, Rahmen und
/// Hintergrund kommen aus `CardThemeData` (V2: surfaceContainerLow, Hairline-
/// Border, Radius xl28), der Innenabstand aus [AppSpacing]. Optionaler [onTap]
/// erhaelt eine korrekt geclippte Ripple.
///
/// Nutzt ausschliesslich benannte Theme-Rollen + Tokens (kein Hex, keine festen
/// dp). Alle weiteren V2-Karten bauen auf diesem Primitiv auf.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final Widget child;

  /// Innenabstand; Default `EdgeInsets.all(context.spacing.md)` (16).
  final EdgeInsetsGeometry? padding;

  /// Macht die Karte antippbar (mit geclippter Ripple).
  final VoidCallback? onTap;

  /// Ueberschreibt die Kartenfarbe aus dem Theme.
  final Color? color;

  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final pad = padding ?? EdgeInsets.all(context.spacing.md);
    Widget content = Padding(padding: pad, child: child);

    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.radii.xl),
        child: content,
      );
    }

    return Card(
      color: color,
      // Weicher Schatten fuer dezente Tiefe (modern). In hellem Theme sichtbar,
      // im dunklen praktisch unsichtbar (dort tragen Border/Container-Kontrast).
      elevation: 1,
      shadowColor: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.5),
      clipBehavior: onTap != null ? Clip.antiAlias : Clip.none,
      child: content,
    );
  }
}
