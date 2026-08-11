import 'package:flutter/material.dart';

abstract final class AppColors {
  static const brand = Color(0xFF087F82);
  static const primary = Color(0xFF075B68);
  static const primaryForeground = Color(0xFFFFFFFF);
  static const secondary = Color(0xFFDBF3F1);
  static const selected = Color(0xFFE3F5F7);
  static const information = Color(0xFF1769AA);
  static const success = Color(0xFF237A52);
  static const warning = Color(0xFF9A6500);
  static const emergency = Color(0xFFC73838);
  static const destructive = Color(0xFFB4232C);
  static const disabled = Color(0xFF9AA7B2);
  static const border = Color(0xFFD9E2E8);
  static const divider = Color(0xFFE8EDF1);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceRaised = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF4F7F9);
  static const textPrimary = Color(0xFF102A3A);
  static const textSecondary = Color(0xFF4F6471);
  static const textMuted = Color(0xFF71838E);
  static const focus = Color(0xFF168DA0);
  static const overlay = Color(0xFF0C2734);
  static const scrim = Color(0x99071824);
}

abstract final class AppSpacing {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x10 = 40.0;
  static const x12 = 48.0;
}

abstract final class AppRadius {
  static const compact = 6.0;
  static const control = 8.0;
  static const panel = 12.0;
  static const sheet = 16.0;
}

class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.information,
    required this.success,
    required this.warning,
    required this.emergency,
    required this.disabled,
    required this.mutedSurface,
    required this.mutedText,
  });

  final Color information;
  final Color success;
  final Color warning;
  final Color emergency;
  final Color disabled;
  final Color mutedSurface;
  final Color mutedText;

  static const light = AppSemanticColors(
    information: AppColors.information,
    success: AppColors.success,
    warning: AppColors.warning,
    emergency: AppColors.emergency,
    disabled: AppColors.disabled,
    mutedSurface: AppColors.surfaceMuted,
    mutedText: AppColors.textMuted,
  );

  @override
  AppSemanticColors copyWith({
    Color? information,
    Color? success,
    Color? warning,
    Color? emergency,
    Color? disabled,
    Color? mutedSurface,
    Color? mutedText,
  }) => AppSemanticColors(
    information: information ?? this.information,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    emergency: emergency ?? this.emergency,
    disabled: disabled ?? this.disabled,
    mutedSurface: mutedSurface ?? this.mutedSurface,
    mutedText: mutedText ?? this.mutedText,
  );

  @override
  AppSemanticColors lerp(
    covariant ThemeExtension<AppSemanticColors>? other,
    double t,
  ) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      information: Color.lerp(information, other.information, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      emergency: Color.lerp(emergency, other.emergency, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      mutedSurface: Color.lerp(mutedSurface, other.mutedSurface, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
    );
  }
}
