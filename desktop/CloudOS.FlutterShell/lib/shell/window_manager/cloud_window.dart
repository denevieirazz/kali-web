import 'package:flutter/material.dart';

enum CloudWindowType {
  files,
  terminal,
  browser,
  settings,
}

class CloudWindow {
  CloudWindow({
    required this.id,
    required this.title,
    required this.icon,
    required this.type,
    required this.position,
    required this.size,
    this.minSize = const Size(420, 300),
    this.isMinimized = false,
    this.isMaximized = false,
    this.preMaximizedPosition,
    this.preMaximizedSize,
    this.zIndex = 0,
  });

  final String id;
  final String title;
  final IconData icon;
  final CloudWindowType type;
  Offset position;
  Size size;
  final Size minSize;
  bool isMinimized;
  bool isMaximized;
  Offset? preMaximizedPosition;
  Size? preMaximizedSize;
  int zIndex;

  CloudWindow copyWith({
    String? id,
    String? title,
    IconData? icon,
    CloudWindowType? type,
    Offset? position,
    Size? size,
    Size? minSize,
    bool? isMinimized,
    bool? isMaximized,
    Offset? preMaximizedPosition,
    Size? preMaximizedSize,
    int? zIndex,
  }) {
    return CloudWindow(
      id: id ?? this.id,
      title: title ?? this.title,
      icon: icon ?? this.icon,
      type: type ?? this.type,
      position: position ?? this.position,
      size: size ?? this.size,
      minSize: minSize ?? this.minSize,
      isMinimized: isMinimized ?? this.isMinimized,
      isMaximized: isMaximized ?? this.isMaximized,
      preMaximizedPosition: preMaximizedPosition ?? this.preMaximizedPosition,
      preMaximizedSize: preMaximizedSize ?? this.preMaximizedSize,
      zIndex: zIndex ?? this.zIndex,
    );
  }
}
