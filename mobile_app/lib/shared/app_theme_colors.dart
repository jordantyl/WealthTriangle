import 'package:flutter/material.dart';

/// Semantic colors for the "dashboard" style screens (Market Intel, Event
/// Calendar, Academy) that used to hardcode dark-only Color(0xFF...)
/// literals, so they looked broken (or just stayed dark) when the user
/// switched the app to light mode. Use `context.appColors.xxx` instead of
/// a literal hex color and it'll flip automatically with the theme toggle.
class AppColors {
  final Color background; // page background
  final Color surface; // card / container background
  final Color surfaceAlt; // nested / secondary container background
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
  });

  static const dark = AppColors(
    background: Color(0xFF0D1117),
    surface: Color(0xFF1A2332),
    surfaceAlt: Color(0xFF2A3A4A),
    border: Color(0xFF2A3A4A),
    textPrimary: Colors.white,
    textSecondary: Colors.white70,
    textTertiary: Colors.white38,
  );

  static const light = AppColors(
    background: Color(0xFFF5F6F8),
    surface: Colors.white,
    surfaceAlt: Color(0xFFEDEFF2),
    border: Color(0xFFDADEE3),
    textPrimary: Color(0xFF1A1D21),
    textSecondary: Color(0xFF5B6470),
    textTertiary: Color(0xFF9AA3AF),
  );
}

extension AppColorsContext on BuildContext {
  AppColors get appColors =>
      Theme.of(this).brightness == Brightness.dark ? AppColors.dark : AppColors.light;
}
