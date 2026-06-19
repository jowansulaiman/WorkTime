import 'package:flutter/widgets.dart';

/// Breakpoints for mobile-first responsive design.
abstract final class MobileBreakpoints {
  /// Compact phones (iPhone SE, Galaxy S series) - 320..389px
  static const double compact = 360;

  /// Standard phones - 390..599px
  static const double standard = 390;

  /// Large phones / small tablets - 600px+
  static const double expanded = 600;

  /// Material-3 Window-Size-Class-Grenze: ab hier wird statt der BottomNav eine
  /// [NavigationRail] gezeigt (medium: 600–839, iPad Portrait, Split-View,
  /// kleine Desktopfenster).
  static const double mediumWindow = 600;

  /// Material-3 Window-Size-Class-Grenze: ab hier zeigt die Rail alle Labels
  /// (expanded: 840px+), darunter nur das ausgewaehlte.
  static const double expandedWindow = 840;

  /// NavigationRail statt BottomNav ab medium (>= 600dp).
  static bool useNavigationRail(double width) => width >= mediumWindow;

  /// Rail mit allen Labels (statt nur ausgewaehltem) ab expanded (>= 840dp).
  static bool useExpandedRailLabels(double width) => width >= expandedWindow;

  /// Returns true for screens narrower than [standard].
  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < standard;

  /// Returns adaptive horizontal padding: tighter on small screens.
  static EdgeInsets screenPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < compact) return const EdgeInsets.symmetric(horizontal: 12);
    if (width < standard) return const EdgeInsets.symmetric(horizontal: 14);
    return const EdgeInsets.symmetric(horizontal: 20);
  }

  /// Returns the number of grid columns for a card grid at given width.
  static int gridColumns(double availableWidth, {double minItemWidth = 160}) {
    final count = (availableWidth / minItemWidth).floor();
    return count.clamp(1, 4);
  }
}

/// Adaptive grid that arranges children in responsive columns.
///
/// On narrow screens, items stack vertically. On wider screens, they flow
/// into multiple columns with equal widths.
class AdaptiveCardGrid extends StatelessWidget {
  const AdaptiveCardGrid({
    super.key,
    required this.children,
    this.spacing = 12,
    this.runSpacing = 12,
    this.minItemWidth = 160,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final double minItemWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            MobileBreakpoints.gridColumns(constraints.maxWidth, minItemWidth: minItemWidth);
        final itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}
