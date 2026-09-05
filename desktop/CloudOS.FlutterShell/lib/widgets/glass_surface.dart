import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    super.key,
    this.padding = EdgeInsets.zero,
    this.borderRadius = 14,
    this.blur = 18,
    this.color = CloudOSColors.surface,
    this.borderColor = CloudOSColors.border,
    this.shadow = true,
  });

  /// Permite desativar o shader de blur em computadores fracos ou no perfil econômico.
  static bool disableBlur = false;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double blur;
  final Color color;
  final Color borderColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final effectiveBlur = disableBlur ? 0.0 : blur;

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius,
        border: Border.all(color: borderColor, width: 1),
        boxShadow: shadow
            ? const <BoxShadow>[
                BoxShadow(
                  color: Color(0x50000000),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );

    if (effectiveBlur > 0) {
      content = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: effectiveBlur, sigmaY: effectiveBlur),
          child: content,
        ),
      );
    } else {
      content = ClipRRect(borderRadius: radius, child: content);
    }

    return RepaintBoundary(child: content);
  }
}
