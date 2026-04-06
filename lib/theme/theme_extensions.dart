import 'package:flutter/material.dart';

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
