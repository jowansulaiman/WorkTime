import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'theme_extensions.dart';

export 'theme_extensions.dart';

abstract final class AppTheme {
  static ThemeData get light => _buildTheme(Brightness.light);
  static ThemeData get dark => _buildTheme(Brightness.dark);

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
    final textTheme = baseTextTheme
        .apply(
          fontFamily: 'NotoSans',
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
        )
        .copyWith(
          displaySmall: baseTextTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
          headlineMedium: baseTextTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
          headlineSmall: baseTextTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
          titleLarge: baseTextTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          titleMedium: baseTextTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          titleSmall: baseTextTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          labelLarge: baseTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
          bodyLarge: baseTextTheme.bodyLarge?.copyWith(height: 1.45),
          bodyMedium: baseTextTheme.bodyMedium?.copyWith(height: 1.4),
          bodySmall: baseTextTheme.bodySmall?.copyWith(height: 1.35),
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
      extensions: <ThemeExtension<dynamic>>[appColors],
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
          return textTheme.labelMedium?.copyWith(
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
}
