import 'package:flutter/material.dart';

import 'breadcrumb_app_bar.dart';
import 'responsive_layout.dart';

/// Wiederverwendbarer Abschnitts-Kopf mit Titel, Untertitel, optionalem
/// Breadcrumb und Zurück-Button.
///
/// Aus dem `home_screen`-God-File gehoben (split-home-screen-god-file); zuvor
/// file-private `_HeaderSection`. Nutzt nur benannte Theme-Rollen.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.breadcrumbs,
    this.onBack,
  });

  final String title;
  final String subtitle;
  final List<BreadcrumbItem>? breadcrumbs;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final compact = MobileBreakpoints.isCompact(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (breadcrumbs != null && breadcrumbs!.isNotEmpty) ...[
          ShellBreadcrumb(
            breadcrumbs: breadcrumbs!,
            onBack: onBack,
          ),
          const SizedBox(height: 10),
        ],
        Text(
          title,
          style: (compact
                  ? Theme.of(context).textTheme.headlineSmall
                  : Theme.of(context).textTheme.headlineMedium)
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
