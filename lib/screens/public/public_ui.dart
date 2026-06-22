import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';

/// Gemeinsames, flaches Design-System der öffentlichen Seiten (`/wunsch`,
/// `/feedback`). Ein eigenständiges, **nicht** mittig-gestapeltes Layout:
/// auf breiten Viewports eine seitliche Teal-Marken-Schiene neben dem
/// links-verankerten, in nummerierte Zonen gegliederten Formular; auf schmalen
/// ein kompaktes Marken-Band über dem Formular. Flach (keine Verläufe, kein
/// Glow, keine Schlagschatten) auf dem Signal-Teal-V2-Theme.

/// Ab dieser Breite wird die seitliche Marken-Schiene neben dem Formular
/// gezeigt (sonst Band oben + Einspalter).
const double kPublicSplitBreakpoint = 880;

/// Lokale Schwelle (eigener [LayoutBuilder] je Paar), ab der zwei Felder
/// nebeneinander statt untereinander stehen. Bewusst entkoppelt vom
/// Seiten-Breakpoint, damit Paare in einer schmalen Formularspalte nicht
/// gequetscht werden (jede Hälfte bleibt ≥ ~260 px breit).
const double kPublicPairBreakpoint = 540;

/// Maximale Breite der links-verankerten Formularspalte (breit genug, damit
/// Feldpaare auf Desktop/Tablet tatsächlich nebeneinander Platz finden).
const double _kFormMaxWidth = 720;

const double _kBrandBadgeAlpha = 0.16; // dezente Badge-/Chip-Flächen auf Teal
const double _kSectionNumeralAlpha = 0.22;
const double _kErrorBorderAlpha = 0.40;
const double _kCodeBorderAlpha = 0.35;

/// Marken-Fläche: hell = kräftiges `primary`-Teal mit weißem Text; dunkel der
/// ruhigere `primaryContainer`, damit kein grelles Teal-Feld blendet. Der
/// Text läuft bewusst volldeckend in der On-Farbe (kein Alpha) — auf dem hellen
/// Teal hat selbst reines Weiß nur ~5:1 Kontrast, jede Abdunklung fiele unter
/// WCAG-AA (4.5:1). Hierarchie kommt daher über Größe/Gewicht, nicht Opazität.
(Color, Color) _brandSurface(BuildContext context) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  return theme.brightness == Brightness.dark
      ? (scheme.primaryContainer, scheme.onPrimaryContainer)
      : (scheme.primary, scheme.onPrimary);
}

/// Füllt die verfügbare Höhe (Inhalt oben, optionaler [Spacer] schiebt das
/// Ende nach unten) und scrollt erst, wenn der Inhalt höher als der Viewport
/// ist — robust für kurze Fenster.
Widget _fillOrScroll({required Widget child}) {
  return LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: IntrinsicHeight(child: child),
      ),
    ),
  );
}

/// Inhaltliche Marken-Daten (kein Widget) für Schiene/Band.
class PublicBrandContent {
  const PublicBrandContent({
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.trustText,
    required this.steps,
    this.singleStoreName,
  });

  final IconData glyph;

  /// Darf `\n` enthalten (zweizeilige Editorial-Überschrift in der Schiene).
  final String title;
  final String subtitle;
  final String trustText;

  /// „So funktioniert's"-Schritte (nur in der breiten Schiene).
  final List<String> steps;

  /// Wird nur gesetzt, wenn es genau einen Laden gibt (Badge in der Schiene).
  final String? singleStoreName;
}

/// Responsiver Rahmen beider öffentlicher Seiten. Tauscht ausschließlich das
/// [child] (Formular ↔ Erfolg) aus; die Marken-Zone bleibt bestehen.
class PublicPageScaffold extends StatelessWidget {
  const PublicPageScaffold({
    super.key,
    required this.brand,
    required this.child,
    this.trailingAction,
  });

  final PublicBrandContent brand;

  /// Üblicherweise ein [AnimatedSwitcher] Formular ↔ Erfolg.
  final Widget child;

  /// Optionale Aktion oben rechts im Formularbereich (z. B. Theme-Umschalter
  /// der Wunsch-Seite). `null` blendet sie aus.
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth >= kPublicSplitBreakpoint
                  ? _buildWide(context)
                  : _buildNarrow(context),
        ),
      ),
    );
  }

  Widget _formArea(BuildContext context) {
    final action = trailingAction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (action != null)
          Padding(
            padding: EdgeInsets.only(bottom: context.spacing.sm),
            child: Align(alignment: Alignment.centerRight, child: action),
          ),
        child,
      ],
    );
  }

  Widget _buildWide(BuildContext context) {
    final spacing = context.spacing;
    final scheme = Theme.of(context).colorScheme;
    final (brandBg, _) = _brandSurface(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 4,
          child: Container(
            color: brandBg,
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 320, maxWidth: 460),
                child: _fillOrScroll(child: PublicBrandRail(brand: brand)),
              ),
            ),
          ),
        ),
        Expanded(
          flex: 6,
          child: ColoredBox(
            color: scheme.surface,
            child: SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: _kFormMaxWidth),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        spacing.lg, spacing.xl, spacing.lg, spacing.xxl),
                    child: _formArea(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrow(BuildContext context) {
    final spacing = context.spacing;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(bottom: spacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PublicBrandBand(brand: brand),
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kFormMaxWidth),
              child: Padding(
                padding:
                    EdgeInsets.fromLTRB(spacing.md, spacing.lg, spacing.md, 0),
                child: _formArea(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Logo in einem nahezu weißen Chip, damit es auf der Teal-Fläche in beiden
/// Modi lesbar bleibt (`AppLogo` rendert hell Markenblau, dunkel Teal).
class PublicLogoChip extends StatelessWidget {
  const PublicLogoChip({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(context.spacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: AppLogo(height: context.iconSizes.lg),
    );
  }
}

/// Breite, persistente Marken-Schiene (ersetzt den Verlaufs-Hero).
class PublicBrandRail extends StatelessWidget {
  const PublicBrandRail({super.key, required this.brand});

  final PublicBrandContent brand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    final iconSizes = context.iconSizes;
    final (_, on) = _brandSurface(context);
    return Padding(
      padding: EdgeInsets.all(spacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          const PublicLogoChip(),
          SizedBox(height: spacing.xl),
          ExcludeSemantics(
            child: Container(
              padding: EdgeInsets.all(spacing.md),
              decoration: BoxDecoration(
                color: on.withValues(alpha: _kBrandBadgeAlpha),
                shape: BoxShape.circle,
              ),
              child: Icon(brand.glyph, size: iconSizes.hero, color: on),
            ),
          ),
          SizedBox(height: spacing.lg),
          Text(
            brand.title,
            style: theme.textTheme.displaySmall?.copyWith(color: on),
          ),
          SizedBox(height: spacing.md),
          Text(
            brand.subtitle,
            style: theme.textTheme.bodyLarge?.copyWith(color: on),
          ),
          const Spacer(),
          SizedBox(height: spacing.xl),
          Text(
            'So funktioniert’s',
            style: theme.textTheme.titleSmall?.copyWith(color: on),
          ),
          SizedBox(height: spacing.sm),
          for (var i = 0; i < brand.steps.length; i++) ...[
            if (i > 0) SizedBox(height: spacing.sm),
            _PublicBrandStep(index: i + 1, text: brand.steps[i], on: on),
          ],
          if (brand.singleStoreName != null) ...[
            SizedBox(height: spacing.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: spacing.md, vertical: spacing.sm),
                decoration: BoxDecoration(
                  color: on.withValues(alpha: _kBrandBadgeAlpha),
                  borderRadius: BorderRadius.circular(context.radii.pill),
                ),
                child: Text(
                  brand.singleStoreName!,
                  style: theme.textTheme.labelLarge?.copyWith(color: on),
                ),
              ),
            ),
          ],
          SizedBox(height: spacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: iconSizes.sm, color: on),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Text(
                  brand.trustText,
                  style: theme.textTheme.bodySmall?.copyWith(color: on),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PublicBrandStep extends StatelessWidget {
  const _PublicBrandStep({
    required this.index,
    required this.text,
    required this.on,
  });

  final int index;
  final String text;
  final Color on;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    final size = context.iconSizes.lg;
    return Row(
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on.withValues(alpha: _kBrandBadgeAlpha),
            shape: BoxShape.circle,
          ),
          child: Text('$index',
              style: theme.textTheme.labelLarge?.copyWith(color: on)),
        ),
        SizedBox(width: spacing.sm),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(color: on),
          ),
        ),
      ],
    );
  }
}

/// Kompaktes Marken-Band oben auf schmalen Viewports.
class PublicBrandBand extends StatelessWidget {
  const PublicBrandBand({super.key, required this.brand});

  final PublicBrandContent brand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    final (bg, on) = _brandSurface(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.vertical(bottom: context.radii.xlRadius),
      ),
      padding:
          EdgeInsets.fromLTRB(spacing.md, spacing.lg, spacing.md, spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PublicLogoChip(),
          SizedBox(height: spacing.md),
          Text(
            brand.title.replaceAll('\n', ' '),
            style: theme.textTheme.headlineSmall?.copyWith(color: on),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: spacing.xs),
          Text(
            brand.subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(color: on),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Flache Zonen-Karte (Rahmen, Radius, **kein** Schatten). Optionaler
/// übergroßer, gedämpfter Index als Editorial-Akzent (Echo der Schienen-
/// Schritte).
class PublicSection extends StatelessWidget {
  const PublicSection({
    super.key,
    this.index,
    this.title,
    this.titleTrailing,
    this.padding,
    required this.child,
  });

  final String? index;
  final String? title;
  final String? titleTrailing;
  final EdgeInsetsGeometry? padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spacing = context.spacing;
    return Container(
      width: double.infinity,
      padding: padding ?? EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(context.radii.xl),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (index != null) ...[
                  // Rein dekorativer Editorial-Akzent (Echo der Schienen-
                  // Schritte) — aus dem Semantik-Baum nehmen, sonst liest der
                  // Screenreader „Eins, Worum geht es?".
                  ExcludeSemantics(
                    child: Text(
                      index!,
                      style: theme.textTheme.displaySmall?.copyWith(
                        height: 1,
                        color: scheme.primary
                            .withValues(alpha: _kSectionNumeralAlpha),
                      ),
                    ),
                  ),
                  SizedBox(width: spacing.md),
                ],
                Expanded(
                  // header: true → Screenreader können die Sektionen per
                  // Überschriften-Navigation (Rotor) überfliegen statt den
                  // ganzen (auf den Rechtsseiten langen) Text linear zu hören.
                  child: Semantics(
                    header: true,
                    child: Text(title!, style: theme.textTheme.titleLarge),
                  ),
                ),
                if (titleTrailing != null) ...[
                  SizedBox(width: spacing.sm),
                  Text(
                    titleTrailing!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
            SizedBox(height: spacing.md),
          ],
          child,
        ],
      ),
    );
  }
}

/// Feld-Beschriftung mit optionalem „(optional)"-Zusatz.
class PublicFieldLabel extends StatelessWidget {
  const PublicFieldLabel(this.text, {super.key, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );
    final trailing = this.trailing;
    if (trailing == null) {
      return label;
    }
    return Row(
      children: [
        label,
        SizedBox(width: context.spacing.sm),
        Text(
          trailing,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Schlanke Feld-Dekoration auf Basis des V2-`inputDecorationTheme`
/// (Füllung/Rahmen/Fokus kommen aus dem Theme; nur Hint/Icon/Counter hier).
InputDecoration publicFieldDecoration(
  BuildContext context, {
  String? hint,
  IconData? icon,
}) {
  return InputDecoration(
    hintText: hint,
    prefixIcon: icon != null ? Icon(icon) : null,
    counterText: '',
  );
}

/// Zwei Felder nebeneinander ab [kPublicPairBreakpoint] (eigener
/// [LayoutBuilder]), sonst untereinander. Ist [right] `null`, nur [left].
class PublicFieldPair extends StatelessWidget {
  const PublicFieldPair({
    super.key,
    required this.left,
    this.right,
    this.gap,
  });

  final Widget left;
  final Widget? right;
  final double? gap;

  @override
  Widget build(BuildContext context) {
    final right = this.right;
    if (right == null) {
      return left;
    }
    final gap = this.gap ?? context.spacing.md;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= kPublicPairBreakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              SizedBox(width: gap),
              Expanded(child: right),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [left, SizedBox(height: gap), right],
        );
      },
    );
  }
}

/// Auswahl-Chips (ersetzt die inline-`Wrap`s). Behält die bestehende
/// Avatar-Tönung (ausgewählt → `onSecondaryContainer`).
class PublicChipRow<T> extends StatelessWidget {
  const PublicChipRow({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelected,
    required this.labelOf,
    this.iconOf,
  });

  final List<T> values;
  final T selected;
  final ValueChanged<T> onSelected;
  final String Function(T) labelOf;
  final IconData Function(T)? iconOf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spacing = context.spacing;
    final iconOf = this.iconOf;
    return Wrap(
      spacing: spacing.sm,
      runSpacing: spacing.sm,
      children: [
        for (final value in values)
          ChoiceChip(
            avatar: iconOf != null
                ? Icon(
                    iconOf(value),
                    size: context.iconSizes.sm,
                    color: selected == value
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant,
                  )
                : null,
            label: Text(labelOf(value)),
            selected: selected == value,
            onSelected: (_) => onSelected(value),
          ),
      ],
    );
  }
}

/// Flache Mengen-Kachel (−/Zahl/+).
class PublicStepperTile extends StatelessWidget {
  const PublicStepperTile({
    super.key,
    required this.value,
    required this.label,
    required this.onMinus,
    required this.onPlus,
  });

  final int value;
  final String label;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spacing = context.spacing;
    return Container(
      padding: EdgeInsets.fromLTRB(spacing.md, spacing.xs, spacing.xs, spacing.xs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.tag, size: context.iconSizes.sm, color: scheme.onSurfaceVariant),
          SizedBox(width: spacing.sm),
          Text(label, style: theme.textTheme.bodyLarge),
          const Spacer(),
          IconButton.filledTonal(
            onPressed: onMinus,
            icon: const Icon(Icons.remove),
            tooltip: 'Weniger',
          ),
          SizedBox(
            width: 44,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
          ),
          IconButton.filledTonal(
            onPressed: onPlus,
            icon: const Icon(Icons.add),
            tooltip: 'Mehr',
          ),
        ],
      ),
    );
  }
}

/// Flache Bewertungs-Kachel (5 Sterne, erneutes Tippen löscht).
class PublicRatingTile extends StatelessWidget {
  const PublicRatingTile({
    super.key,
    required this.rating,
    required this.emptyLabel,
    required this.setLabel,
    required this.onTap,
  });

  final int? rating;
  final String emptyLabel;
  final String setLabel;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spacing = context.spacing;
    final rating = this.rating;
    // Zweizeilig (Beschriftung oben, Sterne darunter): so behalten die 5 Sterne
    // ihre ≥48-px-Tap-Ziele auch auf einem schmalen Handy, ohne zu überlaufen.
    return Container(
      padding: EdgeInsets.fromLTRB(spacing.md, spacing.xs, spacing.xs, spacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: spacing.sm),
            child: Row(
              children: [
                Icon(Icons.star_outline,
                    size: context.iconSizes.sm, color: scheme.onSurfaceVariant),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Text(
                    rating == null ? emptyLabel : setLabel,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              for (var star = 1; star <= 5; star++)
                // Eine Semantik-Quelle mit `selected`-Status (sonst ist die
                // Bewertung nur visuell erkennbar) und eigenem `onTap`, damit
                // die Aktivierung per Screenreader erhalten bleibt; der innere
                // Button wird aus dem Semantik-Baum genommen (kein Doppel-
                // Vorlesen). Der visuelle Tooltip bleibt für die Maus.
                Semantics(
                  button: true,
                  selected: rating != null && star <= rating,
                  label: '$star von 5 Sternen',
                  onTap: () => onTap(star),
                  child: ExcludeSemantics(
                    child: IconButton(
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      onPressed: () => onTap(star),
                      tooltip: '$star von 5',
                      icon: Icon(
                        (rating != null && star <= rating)
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: (rating != null && star <= rating)
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Flache Datums-Kachel (tappbar) + optionaler Entfernen-Button.
class PublicDateTile extends StatelessWidget {
  const PublicDateTile({
    super.key,
    required this.label,
    required this.onPick,
    required this.hasDate,
    required this.onClear,
    required this.clearTooltip,
  });

  final String label;
  final VoidCallback onPick;
  final bool hasDate;
  final VoidCallback onClear;
  final String clearTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spacing = context.spacing;
    final radius = BorderRadius.circular(context.radii.md);
    return Row(
      children: [
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: radius,
              onTap: onPick,
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: radius,
                  border: Border.all(color: scheme.outlineVariant),
                ),
                padding: EdgeInsets.symmetric(
                    horizontal: spacing.md, vertical: spacing.md),
                child: Row(
                  children: [
                    Icon(Icons.event_outlined,
                        size: context.iconSizes.sm,
                        color: scheme.onSurfaceVariant),
                    SizedBox(width: spacing.sm),
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (hasDate)
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.clear),
            tooltip: clearTooltip,
          ),
      ],
    );
  }
}

/// Vollbreiter Pill-CTA mit Lade-Zustand (ersetzt den Verlaufs-Button).
class PublicSubmitButton extends StatelessWidget {
  const PublicSubmitButton({
    super.key,
    required this.submitting,
    required this.onPressed,
    required this.idleLabel,
    this.busyLabel,
    this.icon = Icons.send_rounded,
  });

  final bool submitting;
  final VoidCallback? onPressed;
  final String idleLabel;
  final String? busyLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: submitting ? null : onPressed,
        icon: submitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon),
        label: Text(submitting ? (busyLabel ?? idleLabel) : idleLabel),
      ),
    );
  }
}

/// Flacher Fehler-Hinweis (live region für Screenreader).
class PublicErrorBanner extends StatelessWidget {
  const PublicErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spacing = context.spacing;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: EdgeInsets.all(spacing.md),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(context.radii.md),
          border:
              Border.all(color: scheme.error.withValues(alpha: _kErrorBorderAlpha)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline,
                color: scheme.onErrorContainer, size: context.iconSizes.sm),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Flacher Referenznummer-Block (Teal-Tint, crisper Rahmen, kein Glow) mit
/// barrierefrei vorlesbarer Nummer und Kopier-Button.
class PublicReferenceCode extends StatelessWidget {
  const PublicReferenceCode({
    super.key,
    required this.code,
    required this.caption,
    required this.copyLabel,
    required this.onCopy,
  });

  final String code;
  final String caption;
  final String copyLabel;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spacing = context.spacing;
    return Container(
      padding:
          EdgeInsets.symmetric(vertical: spacing.lg, horizontal: spacing.md),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(context.radii.lg),
        border:
            Border.all(color: scheme.primary.withValues(alpha: _kCodeBorderAlpha)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            caption,
            style: theme.textTheme.labelMedium?.copyWith(
              letterSpacing: 1.5,
              color: scheme.onPrimaryContainer,
            ),
          ),
          SizedBox(height: spacing.sm),
          // Eine einzige Semantik-Quelle: gesprochen werden die einzelnen
          // Zeichen gruppenweise, der Bindestrich als Pause (nicht als „Binde-
          // strich"). SelectableText bleibt für die Maus-Auswahl, wird aber aus
          // dem Semantik-Baum genommen.
          Semantics(
            label: 'Referenznummer',
            value: code.split('-').map((g) => g.split('').join(' ')).join(', '),
            readOnly: true,
            child: ExcludeSemantics(
              child: SelectableText(
                code,
                style: theme.textTheme.displaySmall?.copyWith(
                  letterSpacing: 6,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          SizedBox(height: spacing.md),
          Semantics(
            button: true,
            label: 'Schaltfläche Nummer kopieren',
            child: FilledButton.tonalIcon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded),
              label: Text(copyLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// Footer mit Links zu den rechtlichen Pflichtseiten (Impressum, Datenschutz).
///
/// Bewusst callback-basiert: `public_ui` darf keine Screen-Imports haben (sonst
/// Zyklus mit `public_legal_screen`). Jede Seite entscheidet selbst, wie sie
/// navigiert (Push aus dem Formular bzw. Cross-Link auf der Rechtsseite). Ein
/// `null`-Callback blendet den jeweiligen Link aus (z. B. den Impressum-Link auf
/// der Impressum-Seite selbst). Sind beide `null`, rendert nichts.
class PublicLegalLinks extends StatelessWidget {
  const PublicLegalLinks({
    super.key,
    this.onImpressum,
    this.onDatenschutz,
  });

  final VoidCallback? onImpressum;
  final VoidCallback? onDatenschutz;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spacing = context.spacing;
    final links = <Widget>[
      if (onImpressum != null)
        TextButton(onPressed: onImpressum, child: const Text('Impressum')),
      if (onDatenschutz != null)
        TextButton(onPressed: onDatenschutz, child: const Text('Datenschutz')),
    ];
    if (links.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(top: spacing.lg),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < links.length; i++) ...[
            if (i > 0)
              Text(
                '·',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            links[i],
          ],
        ],
      ),
    );
  }
}

/// Erfolgs-Ansicht (flach, links-verankert) mit grünem Häkchen-Badge,
/// Referenznummer und „weiteren Vorgang"-Aktion.
class PublicSuccessView extends StatelessWidget {
  const PublicSuccessView({
    super.key,
    required this.code,
    required this.headline,
    required this.lead,
    required this.codeCaption,
    required this.copyLabel,
    required this.onCopy,
    required this.resetLabel,
    required this.onReset,
  });

  final String code;
  final String headline;
  final String lead;
  final String codeCaption;
  final String copyLabel;
  final VoidCallback onCopy;
  final String resetLabel;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final spacing = context.spacing;
    return PublicSection(
      key: const ValueKey('success'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: EdgeInsets.all(spacing.md),
              decoration: BoxDecoration(
                color: appColors.successContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_rounded,
                  size: context.iconSizes.xl,
                  color: appColors.onSuccessContainer),
            ),
          ),
          SizedBox(height: spacing.lg),
          Text(headline, style: theme.textTheme.headlineSmall),
          SizedBox(height: spacing.sm),
          Text(
            lead,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: spacing.lg),
          PublicReferenceCode(
            code: code,
            caption: codeCaption,
            copyLabel: copyLabel,
            onCopy: onCopy,
          ),
          SizedBox(height: spacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.add),
              label: Text(resetLabel),
            ),
          ),
        ],
      ),
    );
  }
}
