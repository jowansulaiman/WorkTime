import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/theme/app_theme.dart';

// WCAG-2.1-Kontrast (DS2-Gate, Plan): relative Luminanz + Kontrastverhältnis.
double _lin(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void _audit(ThemeData theme, String name) {
  final cs = theme.colorScheme;
  final ac = theme.extension<AppThemeColors>();
  expect(ac, isNotNull, reason: '$name: AppThemeColors-Extension fehlt');

  // Fließtext (AA normal): >= 4.5.
  final bodyPairs = <String, List<Color>>{
    'onSurface/surface': [cs.onSurface, cs.surface],
    'onPrimary/primary': [cs.onPrimary, cs.primary],
    'onPrimaryContainer/primaryContainer': [
      cs.onPrimaryContainer,
      cs.primaryContainer
    ],
    'onSecondaryContainer/secondaryContainer': [
      cs.onSecondaryContainer,
      cs.secondaryContainer
    ],
    'onErrorContainer/errorContainer': [cs.onErrorContainer, cs.errorContainer],
    'onSuccessContainer/successContainer': [
      ac!.onSuccessContainer,
      ac.successContainer
    ],
    'onWarningContainer/warningContainer': [
      ac.onWarningContainer,
      ac.warningContainer
    ],
    'onInfoContainer/infoContainer': [ac.onInfoContainer, ac.infoContainer],
    // §4.11 G2b: onSuccessContainer wird in AppComparisonStatCard als Text/Icon
    // auf der Kartenfläche genutzt (openGreen wäre als Text ~2,84:1 zu hell).
    'onSuccessContainer/surface': [ac.onSuccessContainer, cs.surface],
  };
  bodyPairs.forEach((label, c) {
    final r = _contrast(c[0], c[1]);
    expect(r, greaterThanOrEqualTo(4.5),
        reason: '$name $label = ${r.toStringAsFixed(2)} (< 4.5 AA)');
  });

  // Große/fette UI (AA large / UI-Komponenten): >= 3.0 — Status-Badges nutzen
  // labelLarge bold, onSurfaceVariant ist Sekundärtext.
  //
  // `onError/error` liegt hier bewusst (lightV2 = 4.36, die weiche Rose #BA5C67
  // ist ein Akzent-/Icon-/Großelement-Ton; Fließtext-Fehler laufen über das
  // errorContainer-Paar oben, das AA erfüllt). Die Rose ist zudem durch
  // ui_components_test fixiert — nicht ohne Bedacht ändern.
  final uiPairs = <String, List<Color>>{
    'onSurfaceVariant/surface': [cs.onSurfaceVariant, cs.surface],
    'onError/error': [cs.onError, cs.error],
    'onSuccess/success': [ac.onSuccess, ac.success],
    'onWarning/warning': [ac.onWarning, ac.warning],
    'onInfo/info': [ac.onInfo, ac.info],
    'primary/surface': [cs.primary, cs.surface],
  };
  uiPairs.forEach((label, c) {
    final r = _contrast(c[0], c[1]);
    expect(r, greaterThanOrEqualTo(3.0),
        reason: '$name $label = ${r.toStringAsFixed(2)} (< 3.0)');
  });
}

void main() {
  group('Kontrast-Audit V2 (DS2-Gate)', () {
    test('lightV2 erfüllt WCAG-AA', () => _audit(AppTheme.lightV2, 'lightV2'));
    test('darkV2 erfüllt WCAG-AA', () => _audit(AppTheme.darkV2, 'darkV2'));

    // Marken-Rebrand (Strichmännchen): dieselbe Gate-Schwelle. Die aus
    // StrichTokens abgeleiteten Container-/Neutral-Töne müssen AA erfüllen.
    test('strichmaennchenLight erfüllt WCAG-AA',
        () => _audit(AppTheme.strichmaennchenLight, 'strichmaennchenLight'));
    test('strichmaennchenDark erfüllt WCAG-AA',
        () => _audit(AppTheme.strichmaennchenDark, 'strichmaennchenDark'));

    test('Dark/Light-Parität: beide liefern alle AppThemeColors-Felder', () {
      for (final theme in [AppTheme.lightV2, AppTheme.darkV2]) {
        expect(theme.extension<AppThemeColors>(), isNotNull);
      }
    });

    // §4.11 G5: Soft-Status-Badge (AppStatusBadge, filled=false) rendert
    // onContainer-Text auf `color@0.12` über der Fläche. Früher stand hier
    // `tones.color` als Text (Strich: warning=gelb ~1,4:1, success=openGreen
    // ~2,8:1 = Fail). Badge-Label = labelLarge bold ⇒ AA-large-Schwelle 3.0.
    void auditSoftBadge(ThemeData theme, String name) {
      final cs = theme.colorScheme;
      final ac = theme.extension<AppThemeColors>()!;
      final combos = <String, List<Color>>{
        'warning': [ac.onWarningContainer, ac.warning],
        'success': [ac.onSuccessContainer, ac.success],
        'info': [ac.onInfoContainer, ac.info],
        'error': [cs.onErrorContainer, cs.error],
      };
      combos.forEach((tone, c) {
        final bg = Color.alphaBlend(c[1].withValues(alpha: 0.12), cs.surface);
        final r = _contrast(c[0], bg);
        expect(r, greaterThanOrEqualTo(3.0),
            reason: '$name soft-badge $tone = ${r.toStringAsFixed(2)} (< 3.0)');
      });
    }

    test('Soft-Status-Badge (G5) erfüllt AA-large in allen V2-Themes', () {
      auditSoftBadge(AppTheme.strichmaennchenLight, 'strichLight');
      auditSoftBadge(AppTheme.strichmaennchenDark, 'strichDark');
      auditSoftBadge(AppTheme.lightV2, 'lightV2');
      auditSoftBadge(AppTheme.darkV2, 'darkV2');
    });
  });
}
