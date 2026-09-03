import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../widgets/glass_surface.dart';
import 'cloud_window.dart';

class CloudWindowFrame extends StatelessWidget {
  const CloudWindowFrame({
    required this.window,
    required this.child,
    required this.onFocus,
    required this.onClose,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onMove,
    required this.onResize,
    super.key,
  });

  final CloudWindow window;
  final Widget child;
  final VoidCallback onFocus;
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;
  final ValueChanged<Offset> onMove;
  final void Function(Offset delta, bool left, bool top, bool right, bool bottom) onResize;

  static const double _handleSize = 8.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onFocus,
      onTapDown: (_) => onFocus(),
      child: GlassSurface(
        borderRadius: window.isMaximized ? 0 : 12,
        child: Stack(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildHeader(),
                Expanded(
                  child: ClipRect(child: child),
                ),
              ],
            ),
            if (!window.isMaximized) ..._buildResizeHandles(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: CloudOSColors.surface.withValues(alpha: 0.8),
        border: const Border(
          bottom: BorderSide(color: CloudOSColors.border),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) => onMove(details.delta),
              onDoubleTap: onToggleMaximize,
              child: Row(
                children: <Widget>[
                  Icon(window.icon, size: 16, color: CloudOSColors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      window.title,
                      style: const TextStyle(
                        color: CloudOSColors.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _WindowButton(
            icon: Icons.remove_rounded,
            tooltip: 'Minimizar',
            onPressed: onMinimize,
          ),
          const SizedBox(width: 4),
          _WindowButton(
            icon: window.isMaximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            tooltip: window.isMaximized ? 'Restaurar' : 'Maximizar',
            onPressed: onToggleMaximize,
          ),
          const SizedBox(width: 4),
          _WindowButton(
            icon: Icons.close_rounded,
            tooltip: 'Fechar',
            isClose: true,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildResizeHandles() {
    return <Widget>[
      // Left handle
      Positioned(
        left: 0,
        top: _handleSize,
        bottom: _handleSize,
        width: _handleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) =>
                onResize(details.delta, true, false, false, false),
          ),
        ),
      ),
      // Right handle
      Positioned(
        right: 0,
        top: _handleSize,
        bottom: _handleSize,
        width: _handleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) =>
                onResize(details.delta, false, false, true, false),
          ),
        ),
      ),
      // Top handle
      Positioned(
        left: _handleSize,
        right: _handleSize,
        top: 0,
        height: _handleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) =>
                onResize(details.delta, false, true, false, false),
          ),
        ),
      ),
      // Bottom handle
      Positioned(
        left: _handleSize,
        right: _handleSize,
        bottom: 0,
        height: _handleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) =>
                onResize(details.delta, false, false, false, true),
          ),
        ),
      ),
      // Top-Left corner
      Positioned(
        left: 0,
        top: 0,
        width: _handleSize,
        height: _handleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpLeftDownRight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) =>
                onResize(details.delta, true, true, false, false),
          ),
        ),
      ),
      // Top-Right corner
      Positioned(
        right: 0,
        top: 0,
        width: _handleSize,
        height: _handleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpRightDownLeft,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) =>
                onResize(details.delta, false, true, true, false),
          ),
        ),
      ),
      // Bottom-Left corner
      Positioned(
        left: 0,
        bottom: 0,
        width: _handleSize,
        height: _handleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpRightDownLeft,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) =>
                onResize(details.delta, true, false, false, true),
          ),
        ),
      ),
      // Bottom-Right corner
      Positioned(
        right: 0,
        bottom: 0,
        width: _handleSize,
        height: _handleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpLeftDownRight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) =>
                onResize(details.delta, false, false, true, true),
          ),
        ),
      ),
    ];
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        icon: Icon(icon, size: 14),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        splashRadius: 14,
        color: isClose ? Colors.white70 : CloudOSColors.secondary,
        hoverColor: isClose
            ? Colors.redAccent.withValues(alpha: 0.8)
            : CloudOSColors.elevated,
      ),
    );
  }
}
