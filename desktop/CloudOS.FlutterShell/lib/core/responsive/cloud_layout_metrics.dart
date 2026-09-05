import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cloud_breakpoints.dart';

class CloudLayoutMetrics {
  const CloudLayoutMetrics({
    required this.screenWidth,
    required this.screenHeight,
  });

  factory CloudLayoutMetrics.fromConstraints(BoxConstraints constraints) {
    return CloudLayoutMetrics(
      screenWidth: constraints.maxWidth,
      screenHeight: constraints.maxHeight,
    );
  }

  factory CloudLayoutMetrics.fromSize(Size size) {
    return CloudLayoutMetrics(
      screenWidth: size.width,
      screenHeight: size.height,
    );
  }

  final double screenWidth;
  final double screenHeight;

  bool get isPortrait => screenHeight > screenWidth;
  bool get isLandscape => !isPortrait;

  CloudBreakpoint get breakpoint =>
      CloudBreakpoint.fromWidth(screenWidth, isPortrait: isPortrait);

  bool get isCompact => breakpoint.isCompact;
  bool get isMedium => breakpoint.isMedium;
  bool get isLarge => breakpoint.isLarge;
  bool get isWide => breakpoint.isWide;

  double get taskbarHeight => isCompact ? 46.0 : 52.0;

  double get workAreaHeight => math.max(100.0, screenHeight - taskbarHeight);
  double get workAreaWidth => screenWidth;

  Size get workAreaSize => Size(workAreaWidth, workAreaHeight);

  // Start Panel dimensions
  double get startPanelWidth {
    if (screenWidth < 600) return math.max(320.0, screenWidth - 32.0);
    if (screenWidth < 900) return math.min(540.0, screenWidth - 32.0);
    return 620.0;
  }

  double get startPanelHeight {
    return math.min(680.0, math.max(400.0, workAreaHeight * 0.72));
  }

  // Quick Settings dimensions
  double get quickSettingsWidth {
    return math.min(380.0, math.max(290.0, screenWidth - 32.0));
  }

  double get quickSettingsHeight {
    return math.min(540.0, math.max(320.0, workAreaHeight - 48.0));
  }

  // Window bounds constraints
  static const double minWindowWidth = 360.0;
  static const double minWindowHeight = 260.0;

  Size clampWindowSize(Size requested) {
    final maxW = math.max(minWindowWidth, workAreaWidth);
    final maxH = math.max(minWindowHeight, workAreaHeight);
    final clampedW = requested.width.clamp(math.min(minWindowWidth, maxW), maxW).toDouble();
    final clampedH = requested.height.clamp(math.min(minWindowHeight, maxH), maxH).toDouble();
    return Size(clampedW, clampedH);
  }

  Offset clampWindowOffset(Offset requested, Size windowSize) {
    final maxLeft = math.max(0.0, workAreaWidth - windowSize.width);
    final maxTop = math.max(0.0, workAreaHeight - windowSize.height);
    final clampedX = requested.dx.clamp(0.0, maxLeft).toDouble();
    final clampedY = requested.dy.clamp(0.0, maxTop).toDouble();
    return Offset(clampedX, clampedY);
  }

  Size defaultWindowSize(String id) {
    return switch (id) {
      'files' => Size(
          math.min(960.0, math.max(minWindowWidth, workAreaWidth * 0.8)),
          math.min(600.0, math.max(minWindowHeight, workAreaHeight * 0.75)),
        ),
      'terminal' => Size(
          math.min(840.0, math.max(minWindowWidth, workAreaWidth * 0.75)),
          math.min(520.0, math.max(minWindowHeight, workAreaHeight * 0.65)),
        ),
      'browser' => Size(
          math.min(980.0, math.max(minWindowWidth, workAreaWidth * 0.85)),
          math.min(640.0, math.max(minWindowHeight, workAreaHeight * 0.8)),
        ),
      'settings' => Size(
          math.min(800.0, math.max(minWindowWidth, workAreaWidth * 0.7)),
          math.min(560.0, math.max(minWindowHeight, workAreaHeight * 0.7)),
        ),
      'notes' => Size(
          math.min(760.0, math.max(minWindowWidth, workAreaWidth * 0.65)),
          math.min(500.0, math.max(minWindowHeight, workAreaHeight * 0.6)),
        ),
      'calculator' => Size(
          math.min(420.0, math.max(300.0, workAreaWidth * 0.45)),
          math.min(480.0, math.max(minWindowHeight, workAreaHeight * 0.55)),
        ),
      'task_manager' => Size(
          math.min(800.0, math.max(minWindowWidth, workAreaWidth * 0.7)),
          math.min(520.0, math.max(minWindowHeight, workAreaHeight * 0.65)),
        ),
      _ => Size(
          math.min(800.0, math.max(minWindowWidth, workAreaWidth * 0.7)),
          math.min(520.0, math.max(minWindowHeight, workAreaHeight * 0.65)),
        ),
    };
  }

  Offset defaultWindowOffset(String id, Size size) {
    final remainingW = math.max(0.0, workAreaWidth - size.width);
    final remainingH = math.max(0.0, workAreaHeight - size.height);
    final step = switch (id) {
      'files' => 0.0,
      'terminal' => 40.0,
      'browser' => 80.0,
      'settings' => 120.0,
      'notes' => 160.0,
      'calculator' => 200.0,
      'task_manager' => 240.0,
      _ => 60.0,
    };
    final x = (remainingW * 0.2 + step).clamp(0.0, remainingW);
    final y = (remainingH * 0.2 + step).clamp(0.0, remainingH);
    return Offset(x, y);
  }
}
