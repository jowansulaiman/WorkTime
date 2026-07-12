import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';
import 'responsive_layout.dart';

/// Ein Breadcrumb-Pfad-Element. `label` = Anzeigetext, `onTap` = optionaler
/// Sprung (typisch: `Navigator.maybePop`) — nur für Vorfahren sinnvoll, der
/// letzte Krümel ist die aktuelle Seite und nie klickbar.
class BreadcrumbItem {
  const BreadcrumbItem({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;
}

/// Professionelle, adaptive Kopfleiste für gepushte Bereichs-/Detail-Screens.
///
/// Löst das frühere Mobile-Anti-Pattern ab (eine Chevron-Kette als AppBar-Titel
/// mit **doppelter** Zurück-Affordanz — Auto-Back-Pfeil *und* klickbarer
/// Eltern-Krümel — sowie einem zu schwachen Seitentitel). Neu, je Fensterbreite:
///
/// - **Schmal (< [MobileBreakpoints.mediumWindow]):** eine einzige, klare
///   Zurück-Taste + ein prominenter Seitentitel (letzter Krümel) mit einer
///   dezenten Eltern-Zeile („Eyebrow") darüber. Kein Chevron-Gewusel.
/// - **Breit (≥ 600):** die volle, klickbare Breadcrumb-Kette (Desktop-/Web-
///   Muster), wo sie hingehört.
///
/// Die **öffentliche API bleibt unverändert** (`breadcrumbs`, `actions`) — alle
/// ~47 Aufrufer profitieren ohne Änderung.
class BreadcrumbAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BreadcrumbAppBar({
    super.key,
    required this.breadcrumbs,
    this.actions,
  });

  /// Pfad von der Wurzel zur aktuellen Seite. Letztes Element = aktuelle Seite.
  final List<BreadcrumbItem> breadcrumbs;
  final List<Widget>? actions;

  /// Zweizeiliger Kopf (Eyebrow + Titel), sobald es einen Eltern-Pfad gibt,
  /// sonst die schlanke Standardhöhe. `+1` für die Hairline unten.
  bool get _hasEyebrow => breadcrumbs.length > 1;
  double get _toolbarHeight => _hasEyebrow ? 66 : 56;

  /// Obergrenze der Chrome-Skalierung. Der Kopf hat feste Höhe, darf also nicht
  /// unbegrenzt mitwachsen — aber 1,5× hält Titel/Eyebrow bei großer
  /// Systemschrift lesbar (statt sie deutlich kleiner als den bis 2,0
  /// skalierenden Body zu lassen und so die Hierarchie zu verkehren).
  static const double _chromeTextScaleCap = 1.5;

  @override
  Size get preferredSize => Size.fromHeight(_toolbarHeight + 1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= MobileBreakpoints.mediumWindow;
    final canPop = Navigator.of(context).canPop();

    final title = breadcrumbs.isEmpty ? '' : breadcrumbs.last.label;
    final ancestors = _hasEyebrow
        ? breadcrumbs.sublist(0, breadcrumbs.length - 1)
        : const <BreadcrumbItem>[];

    final Widget titleContent = wide && ancestors.isNotEmpty
        ? _WideTrail(breadcrumbs: breadcrumbs)
        : _NarrowTitle(title: title, ancestors: ancestors);

    return AppBar(
      automaticallyImplyLeading: false,
      centerTitle: false, // iOS zentriert sonst den zweizeiligen Titel.
      toolbarHeight: _toolbarHeight,
      // Flach: Trennung erfolgt über die Hairline unten, nicht über einen
      // Scroll-Schatten (Design-System: Border/Divider statt Elevation).
      scrolledUnderElevation: 0,
      titleSpacing: canPop ? 4 : 16,
      leading: canPop
          ? IconButton(
              tooltip: 'Zurück',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,
      // Chrome nur bis [_chromeTextScaleCap] mitskalieren (der Kopf hat feste
      // Höhe) — der Body skaliert weiterhin voll bis 2,0.
      title: MediaQuery.withClampedTextScaling(
        maxScaleFactor: _chromeTextScaleCap,
        child: titleContent,
      ),
      actions: actions,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          // Volle Trennstärke: die Leiste ist flach (kein Scroll-Schatten), die
          // Hairline ist also die einzige Abgrenzung zum Inhalt — sie muss tragen.
          color: colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

/// Schmaler Kopf: dezente Eltern-Zeile (Eyebrow) + prominenter Seitentitel.
class _NarrowTitle extends StatelessWidget {
  const _NarrowTitle({required this.title, required this.ancestors});

  final String title;
  final List<BreadcrumbItem> ancestors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ancestors.isNotEmpty) ...[
          // Nur der unmittelbare Elternteil (= wohin „Zurück" führt) — die volle
          // Kette gibt es auf breiten Screens. So bleibt der Kopf ruhig und es
          // gibt kein Glyph-vs-Icon-Trenner-Wirrwarr.
          _Eyebrow(label: ancestors.last.label),
          const SizedBox(height: 1),
        ],
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

/// Dezente, rein **informative** Eltern-Zeile über dem Titel (Orientierung:
/// „wo bin ich, wohin führt Zurück"). Bewusst kein Tap-Ziel — der Rücksprung
/// läuft eindeutig über die Zurück-Taste; ein zweites, winziges, kaum als
/// klickbar erkennbares Ziel wäre schlechter als keins.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        height: 1.1,
      ),
    );
  }
}

/// Breiter Kopf: volle, klickbare Breadcrumb-Kette (Desktop-/Web-Muster).
class _WideTrail extends StatelessWidget {
  const _WideTrail({required this.breadcrumbs});

  final List<BreadcrumbItem> breadcrumbs;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < breadcrumbs.length; i++) ...[
            if (i > 0)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: context.spacing.s6),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: context.iconSizes.sm,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            _TrailCrumb(
              item: breadcrumbs[i],
              isLast: i == breadcrumbs.length - 1,
            ),
          ],
        ],
      ),
    );
  }
}

class _TrailCrumb extends StatelessWidget {
  const _TrailCrumb({required this.item, required this.isLast});

  final BreadcrumbItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (isLast) {
      return Text(
        item.label,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      );
    }

    final label = Text(
      item.label,
      style: theme.textTheme.titleMedium?.copyWith(
        color: item.onTap != null
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
    );
    if (item.onTap == null) return label;
    // Als Button für Screenreader ausweisen (InkWell allein meldet nur eine
    // Tap-Aktion, keine Button-Rolle) — konsistent mit [_BackPill].
    return Semantics(
      button: true,
      label: item.label,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(context.radii.xs),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.spacing.sm,
            vertical: context.spacing.s6,
          ),
          child: label,
        ),
      ),
    );
  }
}

/// Inline-Orientierungs-Leiste für Shell-Tabs/Hub-Unterseiten (kein AppBar,
/// nur ein schlankes Pfad-Widget über dem großen Abschnitts-Titel).
///
/// Neu gestaltet passend zu [BreadcrumbAppBar]: eine dezente Zurück-Pille
/// (Cross-Tab-Zurück) + ein ruhiger Krümel-Pfad ohne das frühere große
/// Home-Icon. [trailing] bleibt für Aktionen rechts erhalten.
class ShellBreadcrumb extends StatelessWidget {
  const ShellBreadcrumb({
    super.key,
    required this.breadcrumbs,
    this.onBack,
    this.trailing,
  });

  final List<BreadcrumbItem> breadcrumbs;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          if (onBack != null) ...[
            _BackPill(onTap: onBack!),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < breadcrumbs.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: context.spacing.xs),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: context.iconSizes.sm,
                          color:
                              colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    _ShellCrumb(
                      item: breadcrumbs[i],
                      isLast: i == breadcrumbs.length - 1,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _ShellCrumb extends StatelessWidget {
  const _ShellCrumb({required this.item, required this.isLast});

  final BreadcrumbItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!isLast && item.onTap != null) {
      return Semantics(
        button: true,
        label: item.label,
        child: InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(context.radii.xs),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.spacing.xs,
              vertical: context.spacing.s6,
            ),
            child: Text(
              item.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }
    return Text(
      item.label,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: isLast ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
        fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }
}

/// Ruhige, tonale Zurück-Pille (48×48-Tap-Ziel, Material-Mindestgröße) für die
/// Inline-Leiste.
class _BackPill extends StatelessWidget {
  const _BackPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Zurück',
      child: Tooltip(
        message: 'Zurück',
        child: Material(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radii.md),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 48,
              width: 48,
              child: Icon(
                Icons.arrow_back_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
