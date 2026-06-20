import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';

/// Ein Segment fuer [AppSegmented].
class AppSegment<T> {
  const AppSegment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Tokenisierter Wrapper um [SegmentedButton] (Signal-Teal-Redesign).
/// Vereinheitlicht Day/Week/Month-, Abwesenheitstyp- u. a. Umschalter.
///
/// [enabled] schaltet die Auswahl hart ab (onSelectionChanged → null): wichtig
/// z. B. fuer den Storage-Modus-Umschalter, der waehrend einer laufenden
/// Migration nicht erneut ausgeloest werden darf (keine ueberlappende Migration).
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.showSelectedIcon = false,
  });

  final List<AppSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool enabled;
  final bool showSelectedIcon;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<T>(
      showSelectedIcon: showSelectedIcon,
      segments: [
        for (final segment in segments)
          ButtonSegment<T>(
            value: segment.value,
            label: Text(segment.label),
            icon: segment.icon != null ? Icon(segment.icon) : null,
          ),
      ],
      selected: {selected},
      onSelectionChanged: enabled
          ? (selection) => onChanged(selection.first)
          : null,
    );
  }
}

/// Duenner, tokenisierter Wrapper um [FilterChip] (Signal-Teal-Redesign) fuer
/// die Filter-Pillen (z. B. im Planer). Form/Farben kommen aus `chipTheme`.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      avatar: icon != null ? Icon(icon, size: context.iconSizes.sm) : null,
      showCheckmark: false,
    );
  }
}
