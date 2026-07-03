import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'strichmaennchen_tokens.dart';
import 'theme_extensions.dart';

export 'strichmaennchen_tokens.dart';
export 'theme_extensions.dart';

abstract final class AppTheme {
  static ThemeData get light => _buildTheme(Brightness.light);
  static ThemeData get dark => _buildTheme(Brightness.dark);

  /// Signal-Teal-Redesign (`redesign_v2`): frisches M3-Expressive-Theme mit der
  /// Leitfarbe Teal. Hell und Dunkel sind unabhaengig definiert (keine
  /// Inversion). Die V1-Themes (`light`/`dark`) bleiben byte-identisch erhalten,
  /// solange das Flag nicht 100 % stabil ist.
  static ThemeData get lightV2 => _buildThemeV2(Brightness.light);
  static ThemeData get darkV2 => _buildThemeV2(Brightness.dark);

  /// Flag-gegateter Selektor fuer die Theme-Wahl in `main.dart`
  /// (Consumer2<ThemeProvider, FeatureFlagProvider>). [useV2] kommt aus dem
  /// `redesign_v2`-Flag (RedesignFlags); false -> unveraenderte V1-Optik.
  static ThemeData resolveLight({required bool useV2}) =>
      useV2 ? lightV2 : light;

  static ThemeData resolveDark({required bool useV2}) => useV2 ? darkV2 : dark;

  /// **Strichmännchen-Theme** (Marken-Rebrand, Memory `strichmaennchen-farbpalette`):
  /// nutzt die M3-Expressive-Maschinerie von V2 (Radien/Typografie/Komponenten),
  /// aber mit der 1:1 aus der Ladenseite übernommenen Palette ([StrichTokens]) —
  /// navy=primary, gold=secondary, gelb=tertiary/Aktion, rose=error,
  /// paper/white=Flächen. Bewusst **opt-in** (eigene Variante via [Theme] bzw.
  /// [StrichmaennchenTheme]), NICHT der App-Default. Für einen app-weiten Wechsel
  /// `resolveLight`/`resolveDark` auf diese Getter zeigen lassen.
  static ThemeData get strichmaennchenLight => _buildThemeV2(
        Brightness.light,
        colorSchemeOverride: _buildStrichColorScheme(Brightness.light),
        appColorsOverride: AppThemeColors.strichmaennchenLight,
      );

  static ThemeData get strichmaennchenDark => _buildThemeV2(
        Brightness.dark,
        colorSchemeOverride: _buildStrichColorScheme(Brightness.dark),
        appColorsOverride: AppThemeColors.strichmaennchenDark,
      );

  /// Strichmännchen-Theme für die gegebene [brightness].
  static ThemeData strichmaennchen(Brightness brightness) =>
      brightness == Brightness.dark ? strichmaennchenDark : strichmaennchenLight;

  static ColorScheme strichmaennchenColorScheme(Brightness brightness) =>
      _buildStrichColorScheme(brightness);

  static ThemeData theme(Brightness brightness) => _buildTheme(brightness);

  static ColorScheme colorScheme(Brightness brightness) =>
      _buildColorScheme(brightness);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = _buildColorScheme(brightness);
    final appColors = isDark ? AppThemeColors.dark : AppThemeColors.light;
    final borderColor = colorScheme.outlineVariant.withValues(alpha: 0.7);
    final typography = Typography.material2021(platform: defaultTargetPlatform);
    final baseTextTheme = isDark ? typography.white : typography.black;
    // Erst NotoSans (+ Farben) anwenden, DANN die per-Style-Overrides vom
    // angewandten TextTheme ableiten. Sonst tragen die Overrides wieder die
    // Plattform-Font (Roboto / auf Apple CupertinoSystemText) statt NotoSans —
    // auf Web-CanvasKit (keine System-Fonts) wird der Text dann unsichtbar.
    final appliedTextTheme = baseTextTheme.apply(
      fontFamily: 'NotoSans',
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );
    final textTheme = appliedTextTheme.copyWith(
      displaySmall: appliedTextTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineMedium: appliedTextTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      headlineSmall: appliedTextTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleLarge: appliedTextTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: appliedTextTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleSmall: appliedTextTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      labelLarge: appliedTextTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      bodyLarge: appliedTextTheme.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: appliedTextTheme.bodyMedium?.copyWith(height: 1.4),
      bodySmall: appliedTextTheme.bodySmall?.copyWith(height: 1.35),
    );

    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: 'NotoSans',
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      scaffoldBackgroundColor: colorScheme.surface,
      canvasColor: colorScheme.surface,
      splashFactory: InkRipple.splashFactory,
      extensions: <ThemeExtension<dynamic>>[
        appColors,
        const AppSpacing(),
        const AppRadii(),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: borderColor),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 0.8,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          // Etwas kompakter als labelMedium (12->11, engeres Tracking), damit
          // bei 6 Tabs auch das längste Label ("Anfragen") einzeilig in die
          // schmale Handy-Kachel passt.
          return textTheme.labelMedium?.copyWith(
            fontSize: 11,
            letterSpacing: 0.1,
            color: selected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant,
          );
        }),
        height: 74,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        useIndicator: true,
        indicatorColor: colorScheme.secondaryContainer,
        selectedIconTheme:
            IconThemeData(color: colorScheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          disabledBackgroundColor: colorScheme.surfaceContainerHighest,
          disabledForegroundColor: colorScheme.onSurfaceVariant,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: colorScheme.surfaceContainerHigh,
          foregroundColor: colorScheme.onSurface,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          disabledForegroundColor: colorScheme.onSurfaceVariant,
          side: BorderSide(color: borderColor),
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(10)),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.onSurfaceVariant.withValues(alpha: 0.45);
            }
            return colorScheme.onSurfaceVariant;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.secondaryContainer;
            }
            if (states.contains(WidgetState.pressed)) {
              return colorScheme.surfaceContainerHigh;
            }
            return Colors.transparent;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        selectedColor: colorScheme.secondaryContainer,
        secondarySelectedColor: colorScheme.secondaryContainer,
        disabledColor: colorScheme.surfaceContainerHighest,
        deleteIconColor: colorScheme.onSurfaceVariant,
        labelStyle: textTheme.labelLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          color: colorScheme.onSecondaryContainer,
        ),
        side: BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: borderColor)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: colorScheme.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        minLeadingWidth: 20,
        minVerticalPadding: 8,
        titleAlignment: ListTileTitleAlignment.center,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        iconColor: colorScheme.primary,
        textColor: colorScheme.onSurface,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
      ),
      inputDecorationTheme: InputDecorationTheme(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.error, width: 1.4),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.82),
        ),
        helperStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        errorStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.error,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        prefixIconColor: colorScheme.onSurfaceVariant,
        suffixIconColor: colorScheme.onSurfaceVariant,
        alignLabelWithHint: true,
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        labelColor: colorScheme.onSecondaryContainer,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        indicator: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        splashFactory: NoSplash.splashFactory,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: borderColor),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colorScheme.primary,
        selectionColor: colorScheme.primary.withValues(alpha: 0.22),
        selectionHandleColor: colorScheme.primary,
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(999),
        thickness: const WidgetStatePropertyAll(8),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          final base = colorScheme.outline;
          final alpha = states.contains(WidgetState.dragged) ? 0.9 : 0.6;
          return base.withValues(alpha: alpha);
        }),
      ),
    );
  }

  static ColorScheme _buildColorScheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final seed = isDark ? const Color(0xFF9FC2DB) : const Color(0xFF244A66);
    final base = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

    return base.copyWith(
      primary: isDark ? const Color(0xFF9FC2DB) : const Color(0xFF244A66),
      onPrimary: isDark ? const Color(0xFF0D2231) : Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF1E3B50) : const Color(0xFFD8E7F3),
      onPrimaryContainer:
          isDark ? const Color(0xFFD8E9F4) : const Color(0xFF102332),
      secondary: isDark ? const Color(0xFF9FC3D1) : const Color(0xFF3F7C8E),
      onSecondary: isDark ? const Color(0xFF09202A) : Colors.white,
      secondaryContainer:
          isDark ? const Color(0xFF1E4254) : const Color(0xFFD8EDF3),
      onSecondaryContainer:
          isDark ? const Color(0xFFD8F0F8) : const Color(0xFF0F313F),
      tertiary: isDark ? const Color(0xFFE1C387) : const Color(0xFFA78249),
      onTertiary: isDark ? const Color(0xFF382807) : Colors.white,
      tertiaryContainer:
          isDark ? const Color(0xFF544018) : const Color(0xFFF1E3C9),
      onTertiaryContainer:
          isDark ? const Color(0xFFFFEECB) : const Color(0xFF46320A),
      error: isDark ? const Color(0xFFF3AFBA) : const Color(0xFFBA5C67),
      onError: isDark ? const Color(0xFF56121D) : Colors.white,
      errorContainer:
          isDark ? const Color(0xFF66222D) : const Color(0xFFF6DDE1),
      onErrorContainer:
          isDark ? const Color(0xFFFFDADF) : const Color(0xFF4A1620),
      surface: isDark ? const Color(0xFF0F1720) : const Color(0xFFF4F7FA),
      onSurface: isDark ? const Color(0xFFE5ECF2) : const Color(0xFF162331),
      surfaceContainerLowest:
          isDark ? const Color(0xFF0A1219) : const Color(0xFFFFFFFF),
      surfaceContainerLow:
          isDark ? const Color(0xFF121C25) : const Color(0xFFFAFCFE),
      surfaceContainer:
          isDark ? const Color(0xFF16212B) : const Color(0xFFF0F4F8),
      surfaceContainerHigh:
          isDark ? const Color(0xFF1A2631) : const Color(0xFFE8EDF3),
      surfaceContainerHighest:
          isDark ? const Color(0xFF21303C) : const Color(0xFFDFE7EE),
      onSurfaceVariant:
          isDark ? const Color(0xFFA6B4C1) : const Color(0xFF596977),
      outline: isDark ? const Color(0xFF728492) : const Color(0xFF8C9DAB),
      outlineVariant:
          isDark ? const Color(0xFF344451) : const Color(0xFFD2DCE3),
      shadow: Colors.black,
      scrim: Colors.black,
      inversePrimary:
          isDark ? const Color(0xFF244A66) : const Color(0xFF9FC2DB),
    );
  }

  // ===========================================================================
  // V2 — Signal Teal (M3 Expressive). Spiegelt die Struktur von _buildTheme /
  // _buildColorScheme, aber mit Teal-Seed, groesseren Radien (AppRadii.v2),
  // hoeherem Gewichtskontrast und den V2-Token-Extensions. Bewusst eigenstaendig
  // gehalten, damit der V1-Pfad unangetastet bleibt (Strangler).
  // ===========================================================================

  static ThemeData _buildThemeV2(
    Brightness brightness, {
    ColorScheme? colorSchemeOverride,
    AppThemeColors? appColorsOverride,
  }) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = colorSchemeOverride ?? _buildColorSchemeV2(brightness);
    final appColors = appColorsOverride ??
        (isDark ? AppThemeColors.darkV2 : AppThemeColors.lightV2);
    final borderColor = colorScheme.outlineVariant.withValues(alpha: 0.7);
    const radii = AppRadii.v2;
    final typography = Typography.material2021(platform: defaultTargetPlatform);
    final baseTextTheme = isDark ? typography.white : typography.black;
    // WICHTIG: Erst NotoSans (+ Farben) anwenden, DANN die per-Style-Overrides
    // vom BEREITS angewandten TextTheme ableiten. Wuerde man (wie urspruenglich)
    // `baseTextTheme.<style>.copyWith(...)` nutzen, traegt der Override wieder die
    // Plattform-Font (Roboto / auf Apple `CupertinoSystemText`) statt NotoSans —
    // auf Web-CanvasKit gibt es dafuer keine System-Font ⇒ unsichtbarer Text.
    final appliedTextTheme = baseTextTheme.apply(
      fontFamily: 'NotoSans',
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );
    final textTheme = appliedTextTheme.copyWith(
      displaySmall: appliedTextTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
      ),
      headlineMedium: appliedTextTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
      ),
      headlineSmall: appliedTextTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleLarge: appliedTextTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: appliedTextTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleSmall: appliedTextTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      labelLarge: appliedTextTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      bodyLarge: appliedTextTheme.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: appliedTextTheme.bodyMedium?.copyWith(height: 1.4),
      bodySmall: appliedTextTheme.bodySmall?.copyWith(height: 1.35),
    );

    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: 'NotoSans',
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      scaffoldBackgroundColor: colorScheme.surface,
      canvasColor: colorScheme.surface,
      splashFactory: InkRipple.splashFactory,
      extensions: <ThemeExtension<dynamic>>[
        appColors,
        const AppSpacing(),
        radii,
        const AppMotion(),
        const AppElevation(),
        const AppIconSizes(),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.xl),
          side: BorderSide(color: borderColor),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 0.8,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.lg),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          // Etwas kompakter als labelMedium (12->11, engeres Tracking), damit
          // bei 6 Tabs auch das längste Label ("Anfragen") einzeilig in die
          // schmale Handy-Kachel passt.
          return textTheme.labelMedium?.copyWith(
            fontSize: 11,
            letterSpacing: 0.1,
            color: selected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant,
          );
        }),
        height: 74,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        useIndicator: true,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.lg),
        ),
        selectedIconTheme:
            IconThemeData(color: colorScheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.xxl),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          disabledBackgroundColor: colorScheme.surfaceContainerHighest,
          disabledForegroundColor: colorScheme.onSurfaceVariant,
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          // Pill-CTAs (M3 Expressive) — markantes „modern"-Signal app-weit.
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: colorScheme.surfaceContainerHigh,
          foregroundColor: colorScheme.onSurface,
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          disabledForegroundColor: colorScheme.onSurfaceVariant,
          side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5)),
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radii.md),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(10)),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.onSurfaceVariant.withValues(alpha: 0.45);
            }
            return colorScheme.onSurfaceVariant;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.secondaryContainer;
            }
            if (states.contains(WidgetState.pressed)) {
              return colorScheme.surfaceContainerHigh;
            }
            return Colors.transparent;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radii.md),
            ),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.md),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        selectedColor: colorScheme.secondaryContainer,
        secondarySelectedColor: colorScheme.secondaryContainer,
        disabledColor: colorScheme.surfaceContainerHighest,
        deleteIconColor: colorScheme.onSurfaceVariant,
        labelStyle: textTheme.labelLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          color: colorScheme.onSecondaryContainer,
        ),
        side: BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.pill),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: borderColor)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radii.md),
            ),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: colorScheme.outline,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radii.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.xl),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        minLeadingWidth: 20,
        minVerticalPadding: 8,
        titleAlignment: ListTileTitleAlignment.center,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.md),
        ),
        iconColor: colorScheme.primary,
        textColor: colorScheme.onSurface,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
      ),
      inputDecorationTheme: InputDecorationTheme(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radii.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radii.md),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radii.md),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radii.md),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radii.md),
          borderSide: BorderSide(color: colorScheme.error, width: 1.4),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.82),
        ),
        helperStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        errorStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.error,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        prefixIconColor: colorScheme.onSurfaceVariant,
        suffixIconColor: colorScheme.onSurfaceVariant,
        alignLabelWithHint: true,
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        labelColor: colorScheme.onSecondaryContainer,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        unselectedLabelStyle:
            textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        indicator: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(radii.md),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        splashFactory: NoSplash.splashFactory,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.md),
          side: BorderSide(color: borderColor),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colorScheme.primary,
        selectionColor: colorScheme.primary.withValues(alpha: 0.22),
        selectionHandleColor: colorScheme.primary,
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: Radius.circular(radii.pill),
        thickness: const WidgetStatePropertyAll(8),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          final base = colorScheme.outline;
          final alpha = states.contains(WidgetState.dragged) ? 0.9 : 0.6;
          return base.withValues(alpha: alpha);
        }),
      ),
    );
  }

  static ColorScheme _buildColorSchemeV2(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    // Signal Teal als Seed; hell/dunkel unabhaengig. Fast alle Rollen werden
    // anschliessend hand-getunt (vibrant wirkt nur auf nicht-ueberschriebene
    // Rollen). surfaceTint ist transparent -> keine Tonal-Tints, ruhige Canvas.
    final seed = isDark ? const Color(0xFF5FD4CE) : const Color(0xFF0E7C7B);
    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
    );

    return base.copyWith(
      primary: isDark ? const Color(0xFF5FD4CE) : const Color(0xFF0E7C7B),
      onPrimary: isDark ? const Color(0xFF003735) : Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF00504D) : const Color(0xFF9CF0E9),
      onPrimaryContainer:
          isDark ? const Color(0xFF9CF0E9) : const Color(0xFF00201F),
      secondary: isDark ? const Color(0xFFA8CDD9) : const Color(0xFF3F7C8E),
      onSecondary: isDark ? const Color(0xFF0E303B) : Colors.white,
      secondaryContainer:
          isDark ? const Color(0xFF294A55) : const Color(0xFFC7E7F0),
      onSecondaryContainer:
          isDark ? const Color(0xFFC7E7F0) : const Color(0xFF0E303B),
      tertiary: isDark ? const Color(0xFFC9BCFF) : const Color(0xFF7A5BD6),
      onTertiary: isDark ? const Color(0xFF2C0D6B) : Colors.white,
      tertiaryContainer:
          isDark ? const Color(0xFF4A2F8A) : const Color(0xFFE7DEFF),
      onTertiaryContainer:
          isDark ? const Color(0xFFE7DEFF) : const Color(0xFF22084F),
      // Fehlerfarbe bewusst aus V1 uebernommen (gedaempftes Rose) — Cancel/
      // Ausstempeln-Hue bleibt stabil; Status liegt in AppThemeColors.
      error: isDark ? const Color(0xFFF3AFBA) : const Color(0xFFBA5C67),
      onError: isDark ? const Color(0xFF56121D) : Colors.white,
      errorContainer:
          isDark ? const Color(0xFF66222D) : const Color(0xFFF6DDE1),
      onErrorContainer:
          isDark ? const Color(0xFFFFDADF) : const Color(0xFF4A1620),
      surface: isDark ? const Color(0xFF0E1514) : const Color(0xFFF6FBFA),
      onSurface: isDark ? const Color(0xFFDDE4E2) : const Color(0xFF141D1C),
      surfaceContainerLowest:
          isDark ? const Color(0xFF090F0E) : const Color(0xFFFFFFFF),
      surfaceContainerLow:
          isDark ? const Color(0xFF131A19) : const Color(0xFFF0F7F6),
      surfaceContainer:
          isDark ? const Color(0xFF171F1E) : const Color(0xFFEAF2F1),
      surfaceContainerHigh:
          isDark ? const Color(0xFF212A28) : const Color(0xFFE3EDEC),
      surfaceContainerHighest:
          isDark ? const Color(0xFF2B3533) : const Color(0xFFDCE7E5),
      onSurfaceVariant:
          isDark ? const Color(0xFFBEC9C7) : const Color(0xFF5A6663),
      outline: isDark ? const Color(0xFF889391) : const Color(0xFF6F7977),
      outlineVariant:
          isDark ? const Color(0xFF3F4948) : const Color(0xFFBEC9C7),
      surfaceTint: Colors.transparent,
      shadow: Colors.black,
      scrim: Colors.black,
      inversePrimary:
          isDark ? const Color(0xFF0E7C7B) : const Color(0xFF5FD4CE),
    );
  }

  // ===========================================================================
  // Strichmännchen-Theme — ColorScheme aus StrichTokens (Marken-Rebrand).
  // M3 verlangt ~30 Rollen; die flache Store-Palette (11 Farben) definiert nur
  // Marken-/Statustöne, keine Container-/Neutral-Stufen. Deshalb: fromSeed(navy)
  // liefert eine harmonische Navy-Tonpalette als Basis, danach überschreiben wir
  // JEDE Rolle, für die der Store einen exakten Wert hat (primary/secondary/
  // tertiary/error/Flächen), und leiten die fehlenden Neutral-/Container-Töne
  // per Color.alphaBlend/lerp NACHVOLLZIEHBAR aus Store-Tokens ab (kein
  // erfundener Hex). outlineVariant hell = exakt `--line` (ink@14 % über paper).
  // ===========================================================================
  static ColorScheme _buildStrichColorScheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = ColorScheme.fromSeed(
      seedColor: StrichTokens.navy,
      brightness: brightness,
    );
    if (isDark) {
      // Store ist light-first (`color-scheme: light`). Der Dunkelmodus leitet
      // sich aus den DUNKELFLÄCHEN der Store-Seite ab: Navy-Grund, warmweißer
      // Text, Gold/Gelb als helle Akzente.
      return base.copyWith(
        primary: StrichTokens.gold,
        onPrimary: StrichTokens.navy,
        primaryContainer: Color.lerp(
          StrichTokens.navy,
          StrichTokens.navySoft,
          0.6,
        ),
        onPrimaryContainer: StrichTokens.paper,
        secondary: StrichTokens.yellow,
        onSecondary: StrichTokens.ink,
        tertiary: const Color(0xFF7FB0DF), // aufgehelltes --blue für Dunkel
        onTertiary: StrichTokens.navy,
        error: const Color(0xFFE4899A), // aufgehelltes --rose für Dunkel
        onError: StrichTokens.navy,
        surface: StrichTokens.navy,
        onSurface: StrichTokens.paper,
        surfaceContainerLowest: Color.lerp(
          StrichTokens.navy,
          StrichTokens.shadow,
          0.25,
        ),
        surfaceContainerLow: StrichTokens.navy,
        surfaceContainer: Color.lerp(
          StrichTokens.navy,
          StrichTokens.navySoft,
          0.45,
        ),
        surfaceContainerHigh: StrichTokens.navySoft,
        surfaceContainerHighest: Color.lerp(
          StrichTokens.navySoft,
          StrichTokens.paper,
          0.12,
        ),
        onSurfaceVariant: Color.alphaBlend(
          StrichTokens.paper.withValues(alpha: 0.72),
          StrichTokens.navy,
        ),
        outline: Color.alphaBlend(
          StrichTokens.pureWhite.withValues(alpha: 0.30),
          StrichTokens.navy,
        ),
        outlineVariant: Color.alphaBlend(
          StrichTokens.pureWhite.withValues(alpha: 0.14),
          StrichTokens.navy,
        ),
        surfaceTint: Colors.transparent,
        shadow: StrichTokens.shadow,
        scrim: StrichTokens.shadow,
        inversePrimary: StrichTokens.navy,
      );
    }
    return base.copyWith(
      primary: StrichTokens.navy,
      onPrimary: StrichTokens.white,
      primaryContainer: Color.alphaBlend(
        StrichTokens.navy.withValues(alpha: 0.14),
        StrichTokens.paper,
      ),
      onPrimaryContainer: StrichTokens.navy,
      secondary: StrichTokens.gold,
      onSecondary: StrichTokens.navy,
      secondaryContainer: Color.alphaBlend(
        StrichTokens.gold.withValues(alpha: 0.22),
        StrichTokens.white,
      ),
      onSecondaryContainer: Color.alphaBlend(
        StrichTokens.ink.withValues(alpha: 0.75),
        StrichTokens.gold,
      ),
      tertiary: StrichTokens.yellow, // Gelb = Aktion/Aufmerksamkeit (CTA)
      onTertiary: StrichTokens.ink,
      tertiaryContainer: Color.alphaBlend(
        StrichTokens.yellow.withValues(alpha: 0.28),
        StrichTokens.white,
      ),
      onTertiaryContainer: StrichTokens.ink,
      error: StrichTokens.rose,
      onError: StrichTokens.white,
      errorContainer: Color.alphaBlend(
        StrichTokens.rose.withValues(alpha: 0.16),
        StrichTokens.white,
      ),
      onErrorContainer: Color.alphaBlend(
        StrichTokens.ink.withValues(alpha: 0.70),
        StrichTokens.rose,
      ),
      surface: StrichTokens.paper,
      onSurface: StrichTokens.ink,
      surfaceContainerLowest: StrichTokens.white,
      surfaceContainerLow: StrichTokens.white,
      surfaceContainer: Color.lerp(
        StrichTokens.paper,
        StrichTokens.paperDeep,
        0.5,
      ),
      surfaceContainerHigh: StrichTokens.paperDeep,
      surfaceContainerHighest: Color.lerp(
        StrichTokens.paperDeep,
        StrichTokens.ink,
        0.06,
      ),
      onSurfaceVariant: Color.alphaBlend(
        StrichTokens.ink.withValues(alpha: 0.72),
        StrichTokens.paper,
      ),
      outline: Color.alphaBlend(
        StrichTokens.ink.withValues(alpha: 0.42),
        StrichTokens.paper,
      ),
      outlineVariant: Color.alphaBlend(
        StrichTokens.ink.withValues(alpha: 0.14), // = --line
        StrichTokens.paper,
      ),
      surfaceTint: Colors.transparent,
      shadow: StrichTokens.shadow,
      scrim: StrichTokens.shadow,
      inversePrimary: StrichTokens.gold,
    );
  }
}

/// Opt-in-Wrapper: hüllt [child] in das [AppTheme.strichmaennchen]-Theme der
/// aktuellen Helligkeit. So bekommen einzelne neue Screens (MHD-/Ablauf-Warnung,
/// Zeitwirtschaft-Ausbau) die Ladenseiten-Optik, ohne den App-Default zu ändern:
///
/// ```dart
/// StrichmaennchenTheme(child: Scaffold(...))
/// ```
class StrichmaennchenTheme extends StatelessWidget {
  const StrichmaennchenTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.strichmaennchen(Theme.of(context).brightness),
      child: child,
    );
  }
}
