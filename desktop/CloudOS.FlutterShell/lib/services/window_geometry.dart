import 'package:flutter/painting.dart';

class WindowGeometryPolicy {
  const WindowGeometryPolicy({
    this.taskbarHeight = 48,
    this.minVisibleTitleWidth = 100,
    this.titleBarHeight = 40,
    this.edgeThreshold = 10,
    this.cornerThreshold = 42,
  });

  final double taskbarHeight;
  final double minVisibleTitleWidth;
  final double titleBarHeight;
  final double edgeThreshold;
  final double cornerThreshold;
}

enum WindowSnapTarget {
  none,
  maximize,
  left,
  right,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class WindowGeometry {
  const WindowGeometry({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  Rect get rect => Rect.fromLTWH(x, y, width, height);

  WindowGeometry copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return WindowGeometry(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  @override
  String toString() => 'WindowGeometry($x, $y, $width, $height)';
}

/// Pure geometry engine used by WindowManager and unit tests.
///
/// Keeping geometry independent from widgets makes DPI/resolution recovery,
/// snap layout and bounds logic deterministic and testable.
class WindowGeometryEngine {
  const WindowGeometryEngine({
    this.policy = const WindowGeometryPolicy(),
  });

  final WindowGeometryPolicy policy;

  Size workArea(Size viewport) {
    final width = _finiteNonNegative(viewport.width);
    final height = _finiteNonNegative(viewport.height - policy.taskbarHeight);
    return Size(width, height);
  }

  WindowGeometry clampToViewport({
    required WindowGeometry geometry,
    required Size viewport,
    required double minWidth,
    required double minHeight,
  }) {
    final area = workArea(viewport);
    final safeMinWidth = _finitePositive(minWidth, 240)
        .clamp(120.0, _max(120, area.width))
        .toDouble();
    final safeMinHeight = _finitePositive(minHeight, 180)
        .clamp(100.0, _max(100, area.height))
        .toDouble();
    final width = _finitePositive(geometry.width, safeMinWidth)
        .clamp(safeMinWidth, _max(safeMinWidth, area.width))
        .toDouble();
    final height = _finitePositive(geometry.height, safeMinHeight)
        .clamp(safeMinHeight, _max(safeMinHeight, area.height))
        .toDouble();

    // Keep at least a title-bar sized strip reachable after resolution/DPI
    // changes. Full containment is used whenever the window fits naturally.
    final maxX = _max(
      0,
      area.width - _min(width, policy.minVisibleTitleWidth),
    );
    final maxY = _max(0, area.height - policy.titleBarHeight);
    final x = _finite(geometry.x, 0).clamp(0.0, maxX).toDouble();
    final y = _finite(geometry.y, 0).clamp(0.0, maxY).toDouble();
    return WindowGeometry(x: x, y: y, width: width, height: height);
  }

  WindowGeometry resizeFromBottomRight({
    required WindowGeometry geometry,
    required double requestedWidth,
    required double requestedHeight,
    required Size viewport,
    required double minWidth,
    required double minHeight,
  }) {
    final area = workArea(viewport);
    final safeMinWidth = _finitePositive(minWidth, 240);
    final safeMinHeight = _finitePositive(minHeight, 180);
    final maxWidth = _max(safeMinWidth, area.width - geometry.x);
    final maxHeight = _max(safeMinHeight, area.height - geometry.y);
    return geometry.copyWith(
      width: _finitePositive(requestedWidth, geometry.width)
          .clamp(safeMinWidth, maxWidth)
          .toDouble(),
      height: _finitePositive(requestedHeight, geometry.height)
          .clamp(safeMinHeight, maxHeight)
          .toDouble(),
    );
  }

  WindowGeometry moveBy({
    required WindowGeometry geometry,
    required Offset delta,
    required Size viewport,
  }) {
    final area = workArea(viewport);
    final dx = delta.dx.isFinite ? delta.dx : 0.0;
    final dy = delta.dy.isFinite ? delta.dy : 0.0;
    final maxX = _max(0, area.width - policy.minVisibleTitleWidth);
    final maxY = _max(0, area.height - policy.titleBarHeight);
    return geometry.copyWith(
      x: (geometry.x + dx).clamp(0.0, maxX).toDouble(),
      y: (geometry.y + dy).clamp(0.0, maxY).toDouble(),
    );
  }

  WindowSnapTarget detectSnapTarget({
    required WindowGeometry geometry,
    required Size viewport,
  }) {
    final area = workArea(viewport);
    if (area.width <= 0 || area.height <= 0) return WindowSnapTarget.none;

    final nearLeft = geometry.x <= policy.edgeThreshold;
    final nearRight =
        geometry.x + geometry.width >= area.width - policy.edgeThreshold;
    final nearTop = geometry.y <= policy.edgeThreshold;
    final nearBottom = geometry.y + policy.titleBarHeight >=
        area.height - policy.cornerThreshold;

    final titleCenterX = geometry.x + geometry.width / 2;
    final titleCenterY = geometry.y + policy.titleBarHeight / 2;
    final cornerLeft = titleCenterX <= policy.cornerThreshold || nearLeft;
    final cornerRight =
        titleCenterX >= area.width - policy.cornerThreshold || nearRight;
    final cornerTop = titleCenterY <= policy.cornerThreshold || nearTop;
    final cornerBottom =
        titleCenterY >= area.height - policy.cornerThreshold || nearBottom;

    if (cornerLeft && cornerTop && nearLeft && nearTop) {
      return WindowSnapTarget.topLeft;
    }
    if (cornerRight && cornerTop && nearRight && nearTop) {
      return WindowSnapTarget.topRight;
    }
    if (cornerLeft && cornerBottom && nearLeft) {
      return WindowSnapTarget.bottomLeft;
    }
    if (cornerRight && cornerBottom && nearRight) {
      return WindowSnapTarget.bottomRight;
    }
    if (nearTop) return WindowSnapTarget.maximize;
    if (nearLeft) return WindowSnapTarget.left;
    if (nearRight) return WindowSnapTarget.right;
    return WindowSnapTarget.none;
  }

  WindowGeometry geometryForSnap({
    required WindowSnapTarget target,
    required Size viewport,
  }) {
    final area = workArea(viewport);
    final halfWidth = area.width / 2;
    final halfHeight = area.height / 2;
    return switch (target) {
      WindowSnapTarget.maximize => WindowGeometry(
          x: 0,
          y: 0,
          width: area.width,
          height: area.height,
        ),
      WindowSnapTarget.left => WindowGeometry(
          x: 0,
          y: 0,
          width: halfWidth,
          height: area.height,
        ),
      WindowSnapTarget.right => WindowGeometry(
          x: halfWidth,
          y: 0,
          width: halfWidth,
          height: area.height,
        ),
      WindowSnapTarget.topLeft => WindowGeometry(
          x: 0,
          y: 0,
          width: halfWidth,
          height: halfHeight,
        ),
      WindowSnapTarget.topRight => WindowGeometry(
          x: halfWidth,
          y: 0,
          width: halfWidth,
          height: halfHeight,
        ),
      WindowSnapTarget.bottomLeft => WindowGeometry(
          x: 0,
          y: halfHeight,
          width: halfWidth,
          height: halfHeight,
        ),
      WindowSnapTarget.bottomRight => WindowGeometry(
          x: halfWidth,
          y: halfHeight,
          width: halfWidth,
          height: halfHeight,
        ),
      WindowSnapTarget.none => WindowGeometry(
          x: 0,
          y: 0,
          width: _min(area.width, _max(360, area.width * .72)),
          height: _min(area.height, _max(280, area.height * .72)),
        ),
    };
  }

  bool approximatelyEqual(
    WindowGeometry a,
    WindowGeometry b, {
    double tolerance = 0.75,
  }) {
    return (a.x - b.x).abs() <= tolerance &&
        (a.y - b.y).abs() <= tolerance &&
        (a.width - b.width).abs() <= tolerance &&
        (a.height - b.height).abs() <= tolerance;
  }

  double _finite(double value, double fallback) =>
      value.isFinite ? value : fallback;

  double _finiteNonNegative(double value) {
    if (!value.isFinite || value < 0) return 0;
    return value;
  }

  double _finitePositive(double value, double fallback) {
    if (!value.isFinite || value <= 0) return fallback;
    return value;
  }

  double _min(double a, double b) => a < b ? a : b;
  double _max(double a, double b) => a > b ? a : b;
}
