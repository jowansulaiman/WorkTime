import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.width,
    this.height = 88,
    this.fit = BoxFit.contain,
    this.semanticsLabel = 'timework Logo',
  });

  final double? width;
  final double height;
  final BoxFit fit;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SvgPicture.asset(
      'assets/images/logo.svg',
      width: width,
      height: height,
      fit: fit,
      semanticsLabel: semanticsLabel,
      colorMapper: _AppLogoColorMapper(
        colorScheme: theme.colorScheme,
        brightness: theme.brightness,
      ),
    );
  }
}

class _AppLogoColorMapper extends ColorMapper {
  const _AppLogoColorMapper({
    required this.colorScheme,
    required this.brightness,
  });

  static const _brandBlue = Color(0xFF155E8C);
  static const _brandOrange = Color(0xFFF39A1E);
  static const _logoSurface = Color(0xFFF7FAFC);
  static const _logoOutline = Color(0xFFD9E2E8);
  static const _logoMuted = Color(0xFF6B7280);
  static const _logoShadow = Color(0xFF0F172A);

  final ColorScheme colorScheme;
  final Brightness brightness;

  bool get _isDark => brightness == Brightness.dark;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    if (!_isDark) {
      return color;
    }

    if (color.toARGB32() == _brandBlue.toARGB32()) {
      return _mix(colorScheme.primary, Colors.white, 0.16);
    }
    if (color.toARGB32() == _brandOrange.toARGB32()) {
      return _mix(colorScheme.secondary, Colors.white, 0.12);
    }
    if (color.toARGB32() == _logoSurface.toARGB32()) {
      return colorScheme.surfaceContainerHigh;
    }
    if (color.toARGB32() == _logoOutline.toARGB32()) {
      return colorScheme.outlineVariant;
    }
    if (color.toARGB32() == _logoMuted.toARGB32()) {
      return colorScheme.onSurfaceVariant;
    }
    if (color.toARGB32() == _logoShadow.toARGB32()) {
      return colorScheme.shadow.withValues(alpha: 0.45);
    }

    return color;
  }

  Color _mix(Color base, Color other, double amount) =>
      Color.lerp(base, other, amount) ?? base;
}
