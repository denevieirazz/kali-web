import 'package:flutter/material.dart';

abstract final class CloudOSColors {
  // Obsidian Deep Black Base
  static const canvas = Color(0xFF05070B);
  static const background = Color(0xFF080B12);
  static const surface = Color(0xF00B0F19);
  static const surfaceStrong = Color(0xF8101624);
  static const elevated = Color(0xFF151D2E);
  static const elevatedHover = Color(0xFF1D283E);
  static const hover = Color(0x1F38BDF8);
  static const active = Color(0x3838BDF8);
  static const border = Color(0x2038BDF8);
  static const borderStrong = Color(0x5538BDF8);
  static const borderSubtle = Color(0x14FFFFFF);
  static const text = Color(0xFFF1F5F9);
  static const secondary = Color(0xFF94A3B8);
  static const caption = Color(0xFF64748B);
  static const textPrimary = text;
  static const textSecondary = secondary;
  static const textTertiary = caption;

  // Accents & Neon Highlights
  static const accent = Color(0xFF38BDF8);
  static const accentSoft = Color(0x2638BDF8);
  static const accentPurple = Color(0xFFC084FC);
  static const accentPurpleSoft = Color(0x26C084FC);
  static const neonCyan = Color(0xFF00E5FF);
  static const neonEmerald = Color(0xFF34D399);
  static const neonAmber = Color(0xFFFBBF24);
  static const neonRose = Color(0xFFFB7185);

  static const linux = Color(0xFFFB923C);
  static const linuxSoft = Color(0x29FB923C);
  static const windows = Color(0xFF38BDF8);
  static const windowsSoft = Color(0x2938BDF8);
  static const success = Color(0xFF34D399);
  static const successSoft = Color(0x2934D399);
  static const warning = Color(0xFFFBBF24);
  static const danger = Color(0xFFF43F5E);
  static const shadow = Color(0x80000000);
}

abstract final class CloudTheme {
  static const accentBlue = CloudOSColors.accent;
  static const surfaceDark = CloudOSColors.surface;
  static const backgroundDark = CloudOSColors.background;
}

ThemeData buildCloudOSTheme() {
  const scheme = ColorScheme.dark(
    primary: CloudOSColors.accent,
    secondary: CloudOSColors.accentPurple,
    surface: CloudOSColors.surfaceStrong,
    error: CloudOSColors.danger,
    onPrimary: Color(0xFF05070B),
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
    dividerColor: CloudOSColors.borderSubtle,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: CloudOSColors.text,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      headlineMedium: TextStyle(
        color: CloudOSColors.text,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: TextStyle(
        color: CloudOSColors.text,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        color: CloudOSColors.text,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: TextStyle(
        color: CloudOSColors.secondary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: TextStyle(color: CloudOSColors.text, fontSize: 13.5),
      bodyMedium: TextStyle(color: CloudOSColors.secondary, fontSize: 12.5),
      bodySmall: TextStyle(color: CloudOSColors.caption, fontSize: 11.5),
      labelLarge: TextStyle(
        color: CloudOSColors.text,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: TextStyle(
        color: CloudOSColors.secondary,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: TextStyle(
        color: CloudOSColors.caption,
        fontSize: 10,
        fontWeight: FontWeight.w500,
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) return CloudOSColors.caption;
        return CloudOSColors.borderStrong;
      }),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CloudOSColors.elevated.withValues(alpha: 0.65),
      hintStyle: const TextStyle(color: CloudOSColors.caption, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: CloudOSColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: CloudOSColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: CloudOSColors.accent, width: 1.3),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: CloudOSColors.elevated,
        border: Border.all(color: CloudOSColors.borderStrong),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x60000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      textStyle: const TextStyle(
        color: CloudOSColors.text,
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
      ),
      waitDuration: const Duration(milliseconds: 350),
    ),
  );
}
