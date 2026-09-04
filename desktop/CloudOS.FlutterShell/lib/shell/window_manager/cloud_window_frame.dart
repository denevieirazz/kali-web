import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../widgets/glass_surface.dart';
import 'cloud_window.dart';
import 'window_resize_guard.dart';

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
    this.onSnapLeft,
    this.onSnapRight,
    super.key,
  });

  final CloudWindow window;
  final Widget child;
  final VoidCallback onFocus;
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;
  final ValueChanged<Offset> onMove;
  final void Function(Offset delta, bool left, bool top, bool right, bool bottom)
      onResize;
  final VoidCallback? onSnapLeft;
  final VoidCallback? onSnapRight;

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
                _buildHeader(context),
                Expanded(
                  child: ClipRect(child: child),
                ),
              ],
            ),
            if (!window.isMaximized) ..._buildResizeHandles(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
          if (onSnapLeft != null || onSnapRight != null) ...<Widget>[
            PopupMenuButton<String>(
              tooltip: 'Organizar tela (Snap)',
              icon: const Icon(
                Icons.vertical_split_rounded,
                size: 16,
                color: CloudOSColors.caption,
              ),
              padding: EdgeInsets.zero,
              color: const Color(0xFF161E2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                if (onSnapLeft != null)
                  const PopupMenuItem<String>(
                    value: 'left',
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.align_horizontal_left_rounded,
                          size: 16,
                          color: CloudOSColors.accent,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Dividir à Esquerda (50%)',
                          style: TextStyle(
                            color: CloudOSColors.text,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (onSnapRight != null)
                  const PopupMenuItem<String>(
                    value: 'right',
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.align_horizontal_right_rounded,
                          size: 16,
                          color: CloudOSColors.accent,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Dividir à Direita (50%)',
                          style: TextStyle(
                            color: CloudOSColors.text,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              onSelected: (val) {
                if (val == 'left') onSnapLeft?.call();
                if (val == 'right') onSnapRight?.call();
              },
            ),
            const SizedBox(width: 2),
          ],
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

  void _emitResize(
    BuildContext context,
    Offset delta,
    bool left,
    bool top,
    bool right,
    bool bottom,
  ) {
    if (!canResizeTowardViewportEdge(
      viewportSize: MediaQuery.sizeOf(context),
      windowPosition: window.position,
      right: right,
      bottom: bottom,
    )) {
      return;
    }

    onResize(delta, left, top, right, bottom);
  }

  List<Widget> _buildResizeHandles(BuildContext context) {
    return <Widget>[
      Positioned(
        left: 0,
        top: _handleSize,
        bottom: _handleSize,
        width: _handleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) => _emitResize(
              context,
              details.delta,
              true,
              false,
              false,
              false,
            ),
          ),
        ),
      ),
      Positioned(
        right: 0,
        top: _handleSize,
        bottom: _handleSize,
        width: _handleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) => _emitResize(
              context,
              details.delta,
              false,
              false,
              true,
              false,
            ),
          ),
        ),
      ),
      Positioned(
        left: _handleSize,
        right: _handleSize,
        top: 0,
        height: _handleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) => _emitResize(
              context,
              details.delta,
              false,
              true,
              false,
              false,
            ),
          ),
        ),
      ),
      Positioned(
        left: _handleSize,
        right: _handleSize,
        bottom: 0,
        height: _handleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) => _emitResize(
              context,
              details.delta,
              false,
              false,
              false,
              true,
            ),
          ),
        ),
      ),
      Positioned(
        left: 0,
        top: 0,
        width: _handleSize,
        height: _handleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpLeftDownRight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) => _emitResize(
              context,
              details.delta,
              true,
              true,
              false,
              false,
            ),
          ),
        ),
      ),
      Positioned(
        right: 0,
        top: 0,
        width: _handleSize,
        height: _handleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpRightDownLeft,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) => _emitResize(
              context,
              details.delta,
              false,
              true,
              true,
              false,
            ),
          ),
        ),
      ),
      Positioned(
        left: 0,
        bottom: 0,
        width: _handleSize,
        height: _handleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpRightDownLeft,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) => _emitResize(
              context,
              details.delta,
              true,
              false,
              false,
              true,
            ),
          ),
        ),
      ),
      Positioned(
        right: 0,
        bottom: 0,
        width: _handleSize,
        height: _handleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpLeftDownRight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) => _emitResize(
              context,
              details.delta,
              false,
              false,
              true,
              true,
            ),
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
