import 'package:flutter/material.dart';

abstract final class CloudOSColors {
  static const canvas = Color(0xFF071018);
  static const background = Color(0xFF0B141E);
  static const surface = Color(0xD9182430);
  static const surfaceStrong = Color(0xF2202E3B);
  static const elevated = Color(0xF72A3948);
  static const hover = Color(0xFF314354);
  static const active = Color(0xFF3A5064);
  static const border = Color(0x336F879C);
  static const borderStrong = Color(0x667A95AC);
  static const text = Color(0xFFF4F7FA);
  static const secondary = Color(0xFFB7C3CE);
  static const caption = Color(0xFF8293A3);
  static const accent = Color(0xFF5DA9FF);
  static const accentSoft = Color(0x335DA9FF);
  static const linux = Color(0xFFFFB45C);
  static const success = Color(0xFF62D99A);
  static const warning = Color(0xFFFFC857);
  static const danger = Color(0xFFFF6B7A);
}

ThemeData buildCloudOSTheme() {
  const scheme = ColorScheme.dark(
    primary: CloudOSColors.accent,
    secondary: CloudOSColors.accent,
    surface: CloudOSColors.surfaceStrong,
    error: CloudOSColors.danger,
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: CloudOSColors.text,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: CloudOSColors.canvas,
    fontFamily: 'Segoe UI',
    visualDensity: VisualDensity.standard,
    dividerColor: CloudOSColors.border,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: CloudOSColors.text,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineMedium: TextStyle(
        color: CloudOSColors.text,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleLarge: TextStyle(
        color: CloudOSColors.text,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        color: CloudOSColors.text,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(color: CloudOSColors.text, fontSize: 14),
      bodyMedium: TextStyle(color: CloudOSColors.secondary, fontSize: 13),
      bodySmall: TextStyle(color: CloudOSColors.caption, fontSize: 12),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CloudOSColors.elevated.withValues(alpha: 0.72),
      hintStyle: const TextStyle(color: CloudOSColors.caption),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CloudOSColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CloudOSColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CloudOSColors.accent, width: 1.4),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: CloudOSColors.elevated,
        border: Border.all(color: CloudOSColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: CloudOSColors.text, fontSize: 12),
    ),
  );
}
