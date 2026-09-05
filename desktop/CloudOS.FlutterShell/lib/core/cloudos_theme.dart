import 'package:flutter/material.dart';

class CloudThemeConfig {
  const CloudThemeConfig({
    this.accentColor = const Color(0xFF4C9AFF),
    this.themeMode = 'dark',
    this.transparency = true,
    this.animations = true,
  });

  final Color accentColor;
  final String themeMode;
  final bool transparency;
  final bool animations;

  bool get isDark => themeMode != 'light';
  Brightness get brightness => isDark ? Brightness.dark : Brightness.light;

  CloudThemeConfig copyWith({
    Color? accentColor,
    String? themeMode,
    bool? transparency,
    bool? animations,
  }) {
    return CloudThemeConfig(
      accentColor: accentColor ?? this.accentColor,
      themeMode: themeMode ?? this.themeMode,
      transparency: transparency ?? this.transparency,
      animations: animations ?? this.animations,
    );
  }
}

final cloudThemeNotifier = ValueNotifier<CloudThemeConfig>(const CloudThemeConfig());

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
  static Color get liveAccent => cloudThemeNotifier.value.accentColor;
  static Color get liveAccentSoft => cloudThemeNotifier.value.accentColor.withValues(alpha: 0.22);
  static Color get liveCanvas => cloudThemeNotifier.value.isDark ? const Color(0xFF090D13) : const Color(0xFFF8FAFC);
  static Color get liveBackground => cloudThemeNotifier.value.isDark ? const Color(0xFF0F151F) : const Color(0xFFF1F5F9);
  static Color get liveSurface => cloudThemeNotifier.value.isDark ? const Color(0xEE161F2C) : const Color(0xFFFFFFFF);
  static Color get liveSurfaceStrong => cloudThemeNotifier.value.isDark ? const Color(0xF81C2636) : const Color(0xFFF8FAFC);
  static Color get liveElevated => cloudThemeNotifier.value.isDark ? const Color(0xFF222F42) : const Color(0xFFE2E8F0);
  static Color get liveElevatedHover => cloudThemeNotifier.value.isDark ? const Color(0xFF2B3A50) : const Color(0xFFCBD5E1);
  static Color get liveBorder => cloudThemeNotifier.value.isDark ? const Color(0x2E728DA6) : const Color(0x3394A3B8);
  static Color get liveBorderStrong => cloudThemeNotifier.value.isDark ? const Color(0x528CA8C4) : const Color(0x5564748B);
  static Color get liveText => cloudThemeNotifier.value.isDark ? const Color(0xFFF0F4F8) : const Color(0xFF0F172A);
  static Color get liveSecondary => cloudThemeNotifier.value.isDark ? const Color(0xFFAEC0D2) : const Color(0xFF475569);
  static Color get liveCaption => cloudThemeNotifier.value.isDark ? const Color(0xFF768A9E) : const Color(0xFF64748B);
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

ThemeData buildCloudOSTheme([CloudThemeConfig? config]) {
  final activeConfig = config ?? cloudThemeNotifier.value;
  final currentAccent = activeConfig.accentColor;
  final isDark = activeConfig.isDark;

  final primaryText = isDark ? const Color(0xFFF0F4F8) : const Color(0xFF0F172A);
  final secondaryText = isDark ? const Color(0xFFAEC0D2) : const Color(0xFF475569);
  final captionText = isDark ? const Color(0xFF768A9E) : const Color(0xFF64748B);

  final scheme = isDark
      ? ColorScheme.dark(
          primary: currentAccent,
          secondary: currentAccent,
          surface: CloudOSColors.surfaceStrong,
          error: CloudOSColors.danger,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: primaryText,
          onError: Colors.white,
        )
      : ColorScheme.light(
          primary: currentAccent,
          secondary: currentAccent,
          surface: const Color(0xFFFFFFFF),
          error: CloudOSColors.danger,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: primaryText,
          onError: Colors.white,
        );

  return ThemeData(
    useMaterial3: true,
    brightness: isDark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark ? const Color(0xFF090D13) : const Color(0xFFF8FAFC),
    cardColor: isDark ? const Color(0xFF141C2B) : Colors.white,
    canvasColor: isDark ? const Color(0xFF0F151F) : const Color(0xFFF1F5F9),
    dialogTheme: DialogThemeData(backgroundColor: isDark ? const Color(0xFF161F2C) : Colors.white),
    fontFamily: 'Segoe UI',
    visualDensity: VisualDensity.standard,
    dividerColor: isDark ? CloudOSColors.border : const Color(0xFFE2E8F0),
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        color: primaryText,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      headlineMedium: TextStyle(
        color: primaryText,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: TextStyle(
        color: primaryText,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        color: primaryText,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: TextStyle(
        color: secondaryText,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: TextStyle(color: primaryText, fontSize: 13.5),
      bodyMedium: TextStyle(color: secondaryText, fontSize: 12.5),
      bodySmall: TextStyle(color: captionText, fontSize: 11.5),
      labelLarge: TextStyle(
        color: primaryText,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: TextStyle(
        color: secondaryText,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: TextStyle(
        color: captionText,
        fontSize: 10,
        fontWeight: FontWeight.w500,
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) return captionText;
        return isDark ? CloudOSColors.borderStrong : const Color(0xFF94A3B8);
      }),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(6),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: isDark ? const Color(0xFF1E2430) : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isDark ? CloudOSColors.borderStrong : const Color(0xFFCBD5E1),
          width: 1,
        ),
      ),
      textStyle: TextStyle(
        color: primaryText,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? CloudOSColors.elevated.withValues(alpha: 0.65) : const Color(0xFFF1F5F9),
      hintStyle: TextStyle(color: captionText, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: isDark ? CloudOSColors.border : const Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: isDark ? CloudOSColors.border : const Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: currentAccent, width: 1.3),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? CloudOSColors.elevated : const Color(0xFF1E293B),
        border: Border.all(color: isDark ? CloudOSColors.borderStrong : const Color(0xFF475569)),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w500),
      waitDuration: const Duration(milliseconds: 350),
    ),
  );
}
