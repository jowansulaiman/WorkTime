import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/redesign_flags.dart';
import 'package:worktime_app/theme/app_theme.dart';

void main() {
  group('V2-Theme-Wahl (Signal-Teal-Redesign)', () {
    test('resolveLight/Dark schaltet zwischen V1- und V2-Leitfarbe', () {
      // V1: Navy #244A66, V2: Signal Teal #0E7C7B (hell) / #5FD4CE (dunkel).
      expect(AppTheme.resolveLight(useV2: false).colorScheme.primary,
          const Color(0xFF244A66));
      expect(AppTheme.resolveLight(useV2: true).colorScheme.primary,
          const Color(0xFF0E7C7B));
      expect(AppTheme.resolveDark(useV2: false).colorScheme.primary,
          const Color(0xFF9FC2DB));
      expect(AppTheme.resolveDark(useV2: true).colorScheme.primary,
          const Color(0xFF5FD4CE));
    });

    test('V1-Themes bleiben byte-identisch (Leitplanke)', () {
      // light/dark duerfen sich nicht veraendert haben — Leitfarbe ...
      expect(AppTheme.light.colorScheme.primary, const Color(0xFF244A66));
      expect(AppTheme.dark.colorScheme.primary, const Color(0xFF9FC2DB));
      // ... UND die V1-Radien-Defaults (stiller Regress, wenn jemand die
      // AppRadii-Default-Werte „mit-modernisiert").
      final v1Radii = AppTheme.light.extension<AppRadii>();
      expect(v1Radii?.sm, 8);
      expect(v1Radii?.md, 14);
      expect(v1Radii?.lg, 18);
      expect(v1Radii?.xl, 24);
      // V2 muss sich davon unterscheiden.
      expect(AppTheme.lightV2.extension<AppRadii>()?.xl, 28);
    });

    test('V2 deaktiviert Tonal-Tint (surfaceTint transparent)', () {
      expect(AppTheme.lightV2.colorScheme.surfaceTint, Colors.transparent);
      expect(AppTheme.darkV2.colorScheme.surfaceTint, Colors.transparent);
    });

    test('Alle TextTheme-Styles nutzen NotoSans (Web-CanvasKit-Schutz)', () {
      // Regression-Guard fuer V1 UND V2: Die per-Style-Overrides muessen vom
      // ANGEWANDTEN TextTheme ableiten, sonst tragen sie die Plattform-Font
      // (Roboto / Apple CupertinoSystemText) — auf Web-CanvasKit unsichtbar
      // (no-system-font).
      for (final theme in [
        AppTheme.light,
        AppTheme.dark,
        AppTheme.lightV2,
        AppTheme.darkV2,
      ]) {
        final tt = theme.textTheme;
        final styles = <String, TextStyle?>{
          'displaySmall': tt.displaySmall,
          'headlineMedium': tt.headlineMedium,
          'headlineSmall': tt.headlineSmall,
          'titleLarge': tt.titleLarge,
          'titleMedium': tt.titleMedium,
          'titleSmall': tt.titleSmall,
          'bodyLarge': tt.bodyLarge,
          'bodyMedium': tt.bodyMedium,
          'bodySmall': tt.bodySmall,
          'labelLarge': tt.labelLarge,
          'labelMedium': tt.labelMedium,
        };
        styles.forEach((name, style) {
          expect(style?.fontFamily, 'NotoSans',
              reason: '$name muss NotoSans tragen (Web-Sichtbarkeit)');
        });
      }
    });
  });

  group('AppThemeColors in beiden V2-Varianten (kein appColors-null-Crash)', () {
    test('lightV2/darkV2 liefern AppThemeColors in extensions:', () {
      final light = AppTheme.lightV2.extension<AppThemeColors>();
      final dark = AppTheme.darkV2.extension<AppThemeColors>();
      expect(light, isNotNull);
      expect(dark, isNotNull);
    });

    test('Status-Farben sind in V2 unveraendert gegenueber V1', () {
      // success/warning/info bleiben exakt (Ampel/Coverage/Planner getunt).
      expect(AppThemeColors.lightV2.success, const Color(0xFF187A58));
      expect(AppThemeColors.lightV2.warning, const Color(0xFFA76E00));
      expect(AppThemeColors.lightV2.info, const Color(0xFF2D6CDF));
      expect(AppThemeColors.lightV2, same(AppThemeColors.light));
      expect(AppThemeColors.darkV2, same(AppThemeColors.dark));
    });

    test('AppThemeColors im V2-Theme ist non-null (kein appColors-Crash)', () {
      // Greift die 97 appColors-Consumer ueber den Theme-Kontrakt ab.
      for (final theme in [AppTheme.lightV2, AppTheme.darkV2]) {
        final colors = theme.extension<AppThemeColors>();
        expect(colors, isNotNull);
        expect(colors!.success, isNotNull);
        expect(colors.warning, isNotNull);
        expect(colors.info, isNotNull);
        expect(colors.successContainer, isNotNull);
        expect(colors.onWarningContainer, isNotNull);
      }
    });
  });

  group('V2-Token-Extensions', () {
    test('V2-Theme liefert die groesseren V2-Radien (AppRadii.v2)', () {
      final v1Radii = AppTheme.light.extension<AppRadii>();
      final v2Radii = AppTheme.lightV2.extension<AppRadii>();
      expect(v1Radii?.xl, 24); // V1 unveraendert
      expect(v2Radii?.xl, 28); // V2 Cards/Dialoge
      expect(v2Radii?.md, 16);
      expect(v2Radii?.lg, 20);
      expect(v2Radii?.xxl, 36);
      expect(v2Radii?.xs, 8);
    });

    test('V2-Theme liefert Motion/Elevation/IconSizes-Tokens', () {
      final motion = AppTheme.lightV2.extension<AppMotion>();
      final elevation = AppTheme.lightV2.extension<AppElevation>();
      final iconSizes = AppTheme.lightV2.extension<AppIconSizes>();
      expect(motion?.medium, const Duration(milliseconds: 300));
      expect(elevation?.floating, 3);
      expect(iconSizes?.hero, 40);
      expect(iconSizes?.sm, 18);
    });

    test('AppSpacing-Ergaenzungen sind additiv (4/8-Rhythmus bleibt)', () {
      const spacing = AppSpacing();
      expect(spacing.xxs, 2);
      expect(spacing.xs, 4); // V1-Werte unveraendert
      expect(spacing.md, 16);
      expect(spacing.xxl, 48);
    });

    test('AppSpacing s6/s12 Halbschritt-Tokens (DS1)', () {
      const spacing = AppSpacing();
      expect(spacing.s6, 6);
      expect(spacing.s12, 12);
      // Entsprechen den zuvor komponierten Summen.
      expect(spacing.s6, spacing.xs + spacing.xxs);
      expect(spacing.s12, spacing.sm + spacing.xs);
      // copyWith trippt die neuen Felder round.
      expect(spacing.copyWith(s6: 7).s6, 7);
      expect(spacing.copyWith(s12: 13).s12, 13);
    });

    test('TabularFigures-Helper setzt tabularFigures (DS1)', () {
      const style = TextStyle(fontSize: 14);
      expect(style.fontFeatures, isNull);
      expect(style.tabular.fontFeatures, kTabularFigures);
      expect(kTabularFigures.single, const FontFeature.tabularFigures());
    });
  });

  group('RedesignFlags-Wertlogik', () {
    test('resolve: Server-Flag durchgereicht, Override gewinnt', () {
      // Ohne dart-define ist der Dev-Override compile-time false.
      expect(RedesignFlags.devOverride, isFalse);
      expect(RedesignFlags.resolve(serverFlag: false), isFalse);
      expect(RedesignFlags.resolve(serverFlag: true), isTrue);
    });

    test('flagKey ist redesign_v2', () {
      expect(RedesignFlags.flagKey, 'redesign_v2');
    });
  });
}
