import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/section_header.dart';

/// Oeffnet ein modales Bottom-Sheet mit der app-weiten Chrome-Konvention
/// (Drag-Handle, scroll-controlled, SafeArea). Inhalt typischerweise via
/// [AppBottomSheetScaffold].
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    builder: builder,
  );
}

/// Vereinheitlichte Sheet-Chrome (Signal-Teal-Redesign): scrollbarer Rahmen mit
/// optionalem Kopf (Titel/Untertitel/Breadcrumbs/Aktionen) und tastatur-sicherem
/// Bodenabstand. Fasst das wiederholte Sheet-Gerüst von Stempeluhr-, Schicht-,
/// Abwesenheits- und Team-Editor-Sheets zusammen.
class AppBottomSheetScaffold extends StatelessWidget {
  const AppBottomSheetScaffold({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.breadcrumbs,
    this.actions,
    this.padding,
    this.controller,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final List<BreadcrumbItem>? breadcrumbs;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final pagePadding = MobileBreakpoints.screenPadding(context);
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final hasHeader = title != null || (breadcrumbs?.isNotEmpty ?? false);

    return SingleChildScrollView(
      controller: controller,
      padding: padding ??
          EdgeInsets.fromLTRB(
            pagePadding.left,
            spacing.sm,
            pagePadding.right,
            spacing.lg + viewInsets,
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasHeader) ...[
            _buildHeader(context),
            SizedBox(height: spacing.md),
          ],
          child,
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    // Mit Breadcrumbs lehnen wir uns an die bestehende SectionHeader-Optik an;
    // ohne Breadcrumbs reicht ein kompakter Titel + optionale Aktionen.
    if (breadcrumbs != null && breadcrumbs!.isNotEmpty) {
      return SectionHeader(
        title: title ?? '',
        subtitle: subtitle ?? '',
        breadcrumbs: breadcrumbs,
      );
    }

    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title!,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                SizedBox(height: context.spacing.xs + context.spacing.xxs),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actions != null && actions!.isNotEmpty) ...[
          SizedBox(width: context.spacing.sm),
          ...actions!,
        ],
      ],
    );
  }
}
