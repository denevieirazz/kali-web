import 'package:flutter/widgets.dart';

const double cloudWindowMinimumWidth = 420;
const double cloudWindowMinimumHeight = 300;
const double cloudTaskbarReservedHeight = 56;

bool canResizeTowardViewportEdge({
  required Size viewportSize,
  required Offset windowPosition,
  required bool right,
  required bool bottom,
}) {
  if (right &&
      viewportSize.width - windowPosition.dx < cloudWindowMinimumWidth) {
    return false;
  }

  if (bottom &&
      viewportSize.height - cloudTaskbarReservedHeight - windowPosition.dy <
          cloudWindowMinimumHeight) {
    return false;
  }

  return true;
}
