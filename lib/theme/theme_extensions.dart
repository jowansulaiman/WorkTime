import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'strichmaennchen_tokens.dart';

@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  const AppThemeColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
  });

  static const light = AppThemeColors(
    success: Color(0xFF187A58),
    onSuccess: Colors.white,
    successContainer: Color(0xFFDFF3EA),
    onSuccessContainer: Color(0xFF0D3B2B),
    warning: Color(0xFFA76E00),
    onWarning: Colors.white,
    warningContainer: Color(0xFFFFE8B8),
    onWarningContainer: Color(0xFF513400),
    info: Color(0xFF2D6CDF),
    onInfo: Colors.white,
    infoContainer: Color(0xFFDCE8FF),
    onInfoContainer: Color(0xFF102D63),
  );

  static const dark = AppThemeColors(
    success: Color(0xFF5DD3A2),
    onSuccess: Color(0xFF032217),
    successContainer: Color(0xFF0F3A2A),
    onSuccessContainer: Color(0xFFD8F7E8),
    warning: Color(0xFFE1B45C),
    onWarning: Color(0xFF2D1B00),
    warningContainer: Color(0xFF4C3809),
    onWarningContainer: Color(0xFFFFEDC8),
    info: Color(0xFF8CB6FF),
    onInfo: Color(0xFF08224F),
    infoContainer: Color(0xFF143C78),
    onInfoContainer: Color(0xFFDCE8FF),
  );

  /// V2-Aliasse (Signal-Teal-Redesign `redesign_v2`): Die Status-Farben bleiben
  /// in V2 **unveraendert** gegenueber V1 — Ampel, Coverage-Card und
  /// Planner-Palette sind auf exakt diese Hues getunt. Eigene Consts geben dem
  /// flag-gegateten V2-Theme einen klaren Seam (Cleanup-Schritt promotet
  /// lightV2/darkV2 spaeter zu light/dark).
  static const lightV2 = light;
  static const darkV2 = dark;

  /// **Strichmännchen-Theme** (Marken-Rebrand) — Status-Triaden in der 1:1 aus
  /// der Ladenseite übernommenen Palette ([StrichTokens]): success=openGreen
  /// (dunkler Ink-Text, ~7.3:1), warning=`--yellow`, info=`--blue`. Die
  /// Container-/On-Container-Rollen (M3-Pflicht) fehlen in der flachen
  /// Store-Palette und werden nachvollziehbar komponiert — eine Store-Farbe per
  /// `Color.alphaBlend` über der jeweiligen Fläche (Weiß hell / Navy dunkel);
  /// daher `final` statt `const`. Alle Paare erfüllen das DS2-Kontrast-Gate
  /// (siehe `test/contrast_audit_test.dart`). Nur der aufgehellte Info-Ton für
  /// den Dunkelmodus (`#7FB0DF`) ist eine begründete Ergänzung, weil die
  /// Referenzseite (`color-scheme: light`) keinen Dunkelmodus definiert.
  static final AppThemeColors strichmaennchenLight =
      _strichmaennchen(Brightness.light);
  static final AppThemeColors strichmaennchenDark =
      _strichmaennchen(Brightness.dark);

  static AppThemeColors _strichmaennchen(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final surface = isDark ? StrichTokens.navy : StrichTokens.white;
    // Getönter Chip = Statusfarbe mit niedriger Deckkraft über der Fläche.
    Color chip(Color base, double alpha) =>
        Color.alphaBlend(base.withValues(alpha: alpha), surface);
    // Text auf hellem Chip = dunkle Variante der Statusfarbe (Ink eingemischt).
    Color deepInk(Color base, double alpha) =>
        Color.alphaBlend(StrichTokens.ink.withValues(alpha: alpha), base);
    // Auf Dunkelflächen tragen die Chips warmweißen Text (paper).
    final onDark = isDark ? StrichTokens.paper : null;
    return AppThemeColors(
      success: StrichTokens.openGreen,
      onSuccess: StrichTokens.ink,
      successContainer: isDark
          ? chip(StrichTokens.green, 0.55)
          : chip(StrichTokens.openGreen, 0.16),
      onSuccessContainer: onDark ?? deepInk(StrichTokens.green, 0.55),
      warning: StrichTokens.yellow,
      onWarning: StrichTokens.ink,
      warningContainer: isDark
          ? chip(StrichTokens.gold, 0.45)
          : chip(StrichTokens.yellow, 0.22),
      onWarningContainer: onDark ?? deepInk(StrichTokens.gold, 0.68),
      info: isDark ? const Color(0xFF7FB0DF) : StrichTokens.blue,
      onInfo: isDark ? StrichTokens.navy : StrichTokens.white,
      infoContainer: isDark
          ? chip(StrichTokens.blue, 0.5)
          : chip(StrichTokens.blue, 0.16),
      onInfoContainer: onDark ??
          Color.alphaBlend(
            StrichTokens.navy.withValues(alpha: 0.55),
            StrichTokens.blue,
          ),
    );
  }

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  static AppThemeColors fallback(Brightness brightness) {
    return brightness == Brightness.dark ? dark : light;
  }

  @override
  AppThemeColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
  }) {
    return AppThemeColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
    );
  }

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) {
      return this;
    }
    return AppThemeColors(
      success: Color.lerp(success, other.success, t) ?? success,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t) ?? onSuccess,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t) ??
              successContainer,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t) ??
              onSuccessContainer,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      onWarning: Color.lerp(onWarning, other.onWarning, t) ?? onWarning,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t) ??
              warningContainer,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t) ??
              onWarningContainer,
      info: Color.lerp(info, other.info, t) ?? info,
      onInfo: Color.lerp(onInfo, other.onInfo, t) ?? onInfo,
      infoContainer:
          Color.lerp(infoContainer, other.infoContainer, t) ?? infoContainer,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t) ??
          onInfoContainer,
    );
  }
}

extension AppThemeDataExtension on ThemeData {
  AppThemeColors get appColors =>
      extension<AppThemeColors>() ?? AppThemeColors.fallback(brightness);
}

/// Spacing-Tokens (Single Source of Truth statt verstreuter EdgeInsets-/
/// SizedBox-Zahlen). Zugriff bevorzugt über `context.spacing`.
@immutable
class AppSpacing extends ThemeExtension<AppSpacing> {
  const AppSpacing({
    this.xxs = 2,
    this.xs = 4,
    this.s6 = 6,
    this.sm = 8,
    this.s12 = 12,
    this.md = 16,
    this.lg = 24,
    this.xl = 32,
    this.xxl = 48,
  });

  /// `xxs`/`xxl` sind V2-Ergaenzungen (Signal-Teal-Redesign): feinere Hairline-
  /// Abstaende bzw. groesszuegiger Desktop-Weissraum. Der 4/8-Rhythmus bleibt;
  /// V1-Werte (xs..xl) sind unveraendert.
  final double xxs;
  final double xs;

  /// V2-Halbschritt-Tokens (Plan-Entscheidung DS1): die beiden haeufigsten
  /// realen Rohwerte **6** und **12**, fuer die es bisher kein Token gab —
  /// zuvor via `sm + xs` / `xs + xxs` komponiert. `s6`/`s12` machen die
  /// Magic-Number-Migration eindeutig (ein Token statt Summe).
  final double s6;
  final double sm;
  final double s12;
  final double md;
  final double lg;
  final double xl;
  final double xxl;

  @override
  AppSpacing copyWith({
    double? xxs,
    double? xs,
    double? s6,
    double? sm,
    double? s12,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
  }) {
    return AppSpacing(
      xxs: xxs ?? this.xxs,
      xs: xs ?? this.xs,
      s6: s6 ?? this.s6,
      sm: sm ?? this.sm,
      s12: s12 ?? this.s12,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
    );
  }

  @override
  AppSpacing lerp(ThemeExtension<AppSpacing>? other, double t) {
    if (other is! AppSpacing) {
      return this;
    }
    return AppSpacing(
      xxs: lerpDouble(xxs, other.xxs, t) ?? xxs,
      xs: lerpDouble(xs, other.xs, t) ?? xs,
      s6: lerpDouble(s6, other.s6, t) ?? s6,
      sm: lerpDouble(sm, other.sm, t) ?? sm,
      s12: lerpDouble(s12, other.s12, t) ?? s12,
      md: lerpDouble(md, other.md, t) ?? md,
      lg: lerpDouble(lg, other.lg, t) ?? lg,
      xl: lerpDouble(xl, other.xl, t) ?? xl,
      xxl: lerpDouble(xxl, other.xxl, t) ?? xxl,
    );
  }
}

/// Radius-Tokens passend zu den im Theme genutzten Eckenradien. Zugriff
/// bevorzugt über `context.radii`.
@immutable
class AppRadii extends ThemeExtension<AppRadii> {
  const AppRadii({
    this.xs = 8,
    this.sm = 8,
    this.md = 14,
    this.lg = 18,
    this.xl = 24,
    this.xxl = 36,
    this.pill = 999,
  });

  /// V2-Radien (Signal-Teal-Redesign, M3 Expressive): groessere Eckenradien fuer
  /// einen weicheren, ausdrucksstaerkeren Look. Wird vom flag-gegateten V2-Theme
  /// in `extensions:` geliefert; das V1-Default-[AppRadii] bleibt byte-identisch.
  /// xs8 · sm12 · md16 (Buttons/Inputs/ListTile/Segmented) · lg20 (Nav-Indicator)
  /// · xl28 (Cards/Dialoge) · xxl36 (Hero/Extended-FAB) · pill999.
  static const AppRadii v2 = AppRadii(
    xs: 8,
    sm: 12,
    md: 16,
    lg: 20,
    xl: 28,
    xxl: 36,
    pill: 999,
  );

  /// `xs`/`xxl` sind V2-Ergaenzungen; die V1-Felder (sm..xl, pill) behalten ihre
  /// bisherigen Werte (0 Regression fuer die aktuellen Consumer).
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;
  final double pill;

  Radius get xsRadius => Radius.circular(xs);
  Radius get smRadius => Radius.circular(sm);
  Radius get mdRadius => Radius.circular(md);
  Radius get lgRadius => Radius.circular(lg);
  Radius get xlRadius => Radius.circular(xl);
  Radius get xxlRadius => Radius.circular(xxl);
  Radius get pillRadius => Radius.circular(pill);

  @override
  AppRadii copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
    double? pill,
  }) {
    return AppRadii(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
      pill: pill ?? this.pill,
    );
  }

  @override
  AppRadii lerp(ThemeExtension<AppRadii>? other, double t) {
    if (other is! AppRadii) {
      return this;
    }
    return AppRadii(
      xs: lerpDouble(xs, other.xs, t) ?? xs,
      sm: lerpDouble(sm, other.sm, t) ?? sm,
      md: lerpDouble(md, other.md, t) ?? md,
      lg: lerpDouble(lg, other.lg, t) ?? lg,
      xl: lerpDouble(xl, other.xl, t) ?? xl,
      xxl: lerpDouble(xxl, other.xxl, t) ?? xxl,
      pill: lerpDouble(pill, other.pill, t) ?? pill,
    );
  }
}

/// Bewegungs-Tokens (Signal-Teal-Redesign, M3 Expressive). Neu in V2 — V1 nutzt
/// keine dieser Werte. Zugriff bevorzugt ueber `context.motion`; einzelne
/// Animationen MUESSEN `AppMotion.resolve(context, …)` nutzen, damit
/// `MediaQuery.disableAnimations` (Reduce Motion) respektiert wird.
@immutable
class AppMotion extends ThemeExtension<AppMotion> {
  const AppMotion({
    this.short = const Duration(milliseconds: 150),
    this.medium = const Duration(milliseconds: 300),
    this.long = const Duration(milliseconds: 450),
    this.extraLong = const Duration(milliseconds: 600),
    this.standard = Curves.easeInOutCubicEmphasized,
    this.emphasizedEnter = Curves.easeOutCubic,
    this.emphasizedExit = Curves.easeInCubic,
    this.spring = Curves.easeOutBack,
  });

  final Duration short;
  final Duration medium;
  final Duration long;
  final Duration extraLong;
  final Curve standard;
  final Curve emphasizedEnter;
  final Curve emphasizedExit;
  final Curve spring;

  /// Liefert `Duration.zero`, wenn der Nutzer Bewegung reduziert hat
  /// (`MediaQuery.disableAnimations`), sonst [value]. Jede animierte
  /// V2-Komponente fuehrt ihre Dauer hierdurch.
  static Duration resolve(BuildContext context, Duration value) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return reduce ? Duration.zero : value;
  }

  @override
  AppMotion copyWith({
    Duration? short,
    Duration? medium,
    Duration? long,
    Duration? extraLong,
    Curve? standard,
    Curve? emphasizedEnter,
    Curve? emphasizedExit,
    Curve? spring,
  }) {
    return AppMotion(
      short: short ?? this.short,
      medium: medium ?? this.medium,
      long: long ?? this.long,
      extraLong: extraLong ?? this.extraLong,
      standard: standard ?? this.standard,
      emphasizedEnter: emphasizedEnter ?? this.emphasizedEnter,
      emphasizedExit: emphasizedExit ?? this.emphasizedExit,
      spring: spring ?? this.spring,
    );
  }

  @override
  AppMotion lerp(ThemeExtension<AppMotion>? other, double t) {
    if (other is! AppMotion) {
      return this;
    }
    return AppMotion(
      short: _lerpDuration(short, other.short, t),
      medium: _lerpDuration(medium, other.medium, t),
      long: _lerpDuration(long, other.long, t),
      extraLong: _lerpDuration(extraLong, other.extraLong, t),
      // Curves lassen sich nicht sinnvoll interpolieren -> harter Schnitt.
      standard: t < 0.5 ? standard : other.standard,
      emphasizedEnter: t < 0.5 ? emphasizedEnter : other.emphasizedEnter,
      emphasizedExit: t < 0.5 ? emphasizedExit : other.emphasizedExit,
      spring: t < 0.5 ? spring : other.spring,
    );
  }
}

Duration _lerpDuration(Duration a, Duration b, double t) {
  final micros = lerpDouble(
        a.inMicroseconds.toDouble(),
        b.inMicroseconds.toDouble(),
        t,
      ) ??
      a.inMicroseconds.toDouble();
  return Duration(microseconds: micros.round());
}

/// Elevation-Tokens (Signal-Teal-Redesign). Sparsam einsetzen — Trennung
/// erfolgt primaer ueber Border/Divider, nicht ueber Schatten. Nie auf
/// Grid/Planner-Zellen anwenden.
@immutable
class AppElevation extends ThemeExtension<AppElevation> {
  const AppElevation({
    this.flat = 0,
    this.raised = 1,
    this.floating = 3,
    this.overlay = 6,
  });

  final double flat;
  final double raised;
  final double floating;
  final double overlay;

  @override
  AppElevation copyWith({
    double? flat,
    double? raised,
    double? floating,
    double? overlay,
  }) {
    return AppElevation(
      flat: flat ?? this.flat,
      raised: raised ?? this.raised,
      floating: floating ?? this.floating,
      overlay: overlay ?? this.overlay,
    );
  }

  @override
  AppElevation lerp(ThemeExtension<AppElevation>? other, double t) {
    if (other is! AppElevation) {
      return this;
    }
    return AppElevation(
      flat: lerpDouble(flat, other.flat, t) ?? flat,
      raised: lerpDouble(raised, other.raised, t) ?? raised,
      floating: lerpDouble(floating, other.floating, t) ?? floating,
      overlay: lerpDouble(overlay, other.overlay, t) ?? overlay,
    );
  }
}

/// Icon-Groessen-Tokens (Signal-Teal-Redesign). Ersetzt hartkodierte `size:`-
/// Werte in den V2-Komponenten. Zugriff ueber `context.iconSizes`.
@immutable
class AppIconSizes extends ThemeExtension<AppIconSizes> {
  const AppIconSizes({
    this.sm = 18,
    this.md = 24,
    this.lg = 28,
    this.xl = 32,
    this.hero = 40,
  });

  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double hero;

  @override
  AppIconSizes copyWith({
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? hero,
  }) {
    return AppIconSizes(
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      hero: hero ?? this.hero,
    );
  }

  @override
  AppIconSizes lerp(ThemeExtension<AppIconSizes>? other, double t) {
    if (other is! AppIconSizes) {
      return this;
    }
    return AppIconSizes(
      sm: lerpDouble(sm, other.sm, t) ?? sm,
      md: lerpDouble(md, other.md, t) ?? md,
      lg: lerpDouble(lg, other.lg, t) ?? lg,
      xl: lerpDouble(xl, other.xl, t) ?? xl,
      hero: lerpDouble(hero, other.hero, t) ?? hero,
    );
  }
}

extension AppDesignTokensX on BuildContext {
  /// Spacing-Tokens des aktiven Themes (Fallback: Default-[AppSpacing]).
  AppSpacing get spacing =>
      Theme.of(this).extension<AppSpacing>() ?? const AppSpacing();

  /// Radius-Tokens des aktiven Themes (Fallback: Default-[AppRadii]).
  AppRadii get radii => Theme.of(this).extension<AppRadii>() ?? const AppRadii();

  /// Bewegungs-Tokens des aktiven Themes (Fallback: Default-[AppMotion]).
  AppMotion get motion =>
      Theme.of(this).extension<AppMotion>() ?? const AppMotion();

  /// Elevation-Tokens des aktiven Themes (Fallback: Default-[AppElevation]).
  AppElevation get elevation =>
      Theme.of(this).extension<AppElevation>() ?? const AppElevation();

  /// Icon-Groessen-Tokens des aktiven Themes (Fallback: Default-[AppIconSizes]).
  AppIconSizes get iconSizes =>
      Theme.of(this).extension<AppIconSizes>() ?? const AppIconSizes();
}

/// Tabellen-Ziffern (Plan-Entscheidung DS1): gleiche Ziffernbreite fuer
/// Zahlen-Rollen (Uhr, Stunden, Plan/Ist, Betraege). Verhindert „springende"
/// Zahlen bei Live-Updates/rechtsbuendigen Spalten. **Nur gezielt** auf Zahlen
/// anwenden, nie global — sonst bricht der Fliesstext-Rhythmus.
const List<FontFeature> kTabularFigures = <FontFeature>[
  FontFeature.tabularFigures(),
];

extension TabularFiguresTextStyleX on TextStyle {
  /// Kopie dieses Stils mit Tabellen-Ziffern ([kTabularFigures]).
  TextStyle get tabular => copyWith(fontFeatures: kTabularFigures);
}
