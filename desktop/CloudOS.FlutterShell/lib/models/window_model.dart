import 'package:flutter/material.dart';

class CloudWindow {
  CloudWindow({
    required this.id,
    required this.appId,
    required this.title,
    required this.icon,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.minimized = false,
    this.maximized = false,
    this.focused = true,
    this.isResizable = true,
    this.workspaceIndex = 1,
    this.minWidth = 360.0,
    this.minHeight = 280.0,
    this.customParams = const <String, dynamic>{},
    this.previousX = 100.0,
    this.previousY = 60.0,
    this.previousWidth = 800.0,
    this.previousHeight = 560.0,
  });

  final String id;
  final String appId;
  String title;
  IconData icon;
  double x;
  double y;
  double width;
  double height;
  bool minimized;
  bool maximized;
  bool focused;
  final bool isResizable;
  int workspaceIndex;
  final double minWidth;
  final double minHeight;
  final Map<String, dynamic> customParams;

  double previousX;
  double previousY;
  double previousWidth;
  double previousHeight;

  CloudWindow copyWith({
    String? title,
    IconData? icon,
    double? x,
    double? y,
    double? width,
    double? height,
    bool? minimized,
    bool? maximized,
    bool? focused,
    int? workspaceIndex,
    Map<String, dynamic>? customParams,
  }) {
    return CloudWindow(
      id: id,
      appId: appId,
      title: title ?? this.title,
      icon: icon ?? this.icon,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      minimized: minimized ?? this.minimized,
      maximized: maximized ?? this.maximized,
      focused: focused ?? this.focused,
      isResizable: isResizable,
      workspaceIndex: workspaceIndex ?? this.workspaceIndex,
      minWidth: minWidth,
      minHeight: minHeight,
      customParams: customParams ?? this.customParams,
      previousX: previousX,
      previousY: previousY,
      previousWidth: previousWidth,
      previousHeight: previousHeight,
    );
  }
}
