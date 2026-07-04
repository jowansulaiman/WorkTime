import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';

/// Label-/Wert-Zeile für Info-/Stammdaten-Karten: feste Label-Spalte links,
/// Wert rechts. Gehoben aus dem file-privaten `_InfoRow` des Personal-Screens,
/// damit die neuen AllTec-1:1-Detail-Tabs sie teilen können.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.labelWidth = 150,
  });

  final String label;
  final String value;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
