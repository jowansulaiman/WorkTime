import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';
import '../ui/app_stat_cards.dart';

/// Eine Kennzahl für die [SummaryCardRow].
class SummaryCardItem {
  const SummaryCardItem({
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;
}

/// Responsive Reihe aus [AppMetricCard]s (analog AllTecs `SummaryCardRow`):
/// 2–4 Karten pro Zeile je nach Breite, sonst Umbruch. Für die KPI-Kopfzeile der
/// Mitarbeiter-Übersicht und (später) der Personalverwaltungs-Liste.
class SummaryCardRow extends StatelessWidget {
  const SummaryCardRow({super.key, required this.items});

  final List<SummaryCardItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final gap = context.spacing.sm;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxPerRow = constraints.maxWidth >= 720
            ? 4
            : constraints.maxWidth >= 480
                ? 3
                : 2;
        final perRow =
            items.length < maxPerRow ? items.length : maxPerRow;
        final width =
            (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: AppMetricCard(
                  label: item.label,
                  value: item.value,
                  icon: item.icon,
                ),
              ),
          ],
        );
      },
    );
  }
}
