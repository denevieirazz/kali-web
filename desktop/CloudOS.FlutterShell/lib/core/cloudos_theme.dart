import 'package:flutter/material.dart';

abstract final class CloudOSColors {
  static const canvas = Color(0xFF090D13);
  static const background = Color(0xFF0F151F);
  static const surface = Color(0xEE161F2C);
  static const surfaceStrong = Color(0xF81C2636);
  static const elevated = Color(0xFF222F42);
  static const elevatedHover = Color(0xFF2B3A50);
  static const hover = Color(0x1F5DA9FF);
  static const active = Color(0x385DA9FF);
  static const border = Color(0x2E728DA6);
  static const borderStrong = Color(0x528CA8C4);
  static const text = Color(0xFFF0F4F8);
  static const secondary = Color(0xFFAEC0D2);
  static const caption = Color(0xFF768A9E);
  static const accent = Color(0xFF4C9AFF);
  static const accentSoft = Color(0x294C9AFF);
  static const linux = Color(0xFFE9963F);
  static const linuxSoft = Color(0x29E9963F);
  static const windows = Color(0xFF00A4EF);
  static const windowsSoft = Color(0x2900A4EF);
  static const success = Color(0xFF43C780);
  static const successSoft = Color(0x2943C780);
  static const warning = Color(0xFFE6A23C);
  static const danger = Color(0xFFF25D6B);
  static const shadow = Color(0x40000000);
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
          BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      textStyle: const TextStyle(color: CloudOSColors.text, fontSize: 11.5, fontWeight: FontWeight.w500),
      waitDuration: const Duration(milliseconds: 350),
    ),
  );
}
