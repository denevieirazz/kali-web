import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/cloudos_theme.dart';
import '../models/window_model.dart';
import '../services/window_manager.dart';

class WindowFrame extends StatelessWidget {
  const WindowFrame({
    super.key,
    required this.window,
    required this.windowManager,
    required this.viewportSize,
    required this.child,
  });

  final CloudWindow window;
  final WindowManager windowManager;
  final Size viewportSize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isFocused = window.focused;
    final isMaximized = window.maximized;

    return Positioned(
      left: window.x,
      top: window.y,
      width: window.width,
      height: window.height,
      child: GestureDetector(
        onTapDown: (_) => windowManager.focusWindow(window.id),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isMaximized ? 0 : 14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              decoration: BoxDecoration(
                color: isFocused
                    ? const Color(0xE60A0E18)
                    : const Color(0xD9080B14),
                borderRadius: BorderRadius.circular(isMaximized ? 0 : 14),
                border: Border.all(
                  color: isFocused
                      ? CloudOSColors.accent.withValues(alpha: 0.65)
                      : Colors.white.withValues(alpha: 0.08),
                  width: isFocused ? 1.5 : 1.0,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: isFocused
                        ? CloudOSColors.accent.withValues(alpha: 0.22)
                        : Colors.black.withValues(alpha: 0.5),
                    blurRadius: isFocused ? 32 : 16,
                    spreadRadius: isFocused ? 1 : 0,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: <Widget>[
                  // Conteúdo Principal da Janela
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // Barra de Título Ultra Dark
                      _buildTitleBar(context, isFocused, isMaximized),
                      // Área de Conteúdo
                      Expanded(
                        child: Container(
                          color: const Color(0xFF060910).withValues(alpha: 0.95),
                          child: child,
                        ),
                      ),
                    ],
                  ),

                  // Alças de redimensionamento nos cantos e bordas (somente se não maximizado)
                  if (!isMaximized && window.isResizable) ...<Widget>[
                    // Canto Inferior Direito
                    Positioned(
                      right: 0,
                      bottom: 0,
                      width: 18,
                      height: 18,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeDownRight,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            windowManager.resizeWindow(
                              window.id,
                              window.width + details.delta.dx,
                              window.height + details.delta.dy,
                              viewportSize,
                            );
                          },
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                    ),
                    // Borda Direita
                    Positioned(
                      right: 0,
                      top: 38,
                      bottom: 18,
                      width: 6,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeRight,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            windowManager.resizeWindow(
                              window.id,
                              window.width + details.delta.dx,
                              window.height,
                              viewportSize,
                            );
                          },
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                    ),
                    // Borda Inferior
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 0,
                      height: 6,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeDown,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            windowManager.resizeWindow(
                              window.id,
                              window.width,
                              window.height + details.delta.dy,
                              viewportSize,
                            );
                          },
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context, bool isFocused, bool isMaximized) {
    return GestureDetector(
      onDoubleTap: () => windowManager.toggleMaximizeWindow(window.id, viewportSize),
      onPanUpdate: (details) {
        windowManager.moveWindow(window.id, details.delta, viewportSize);
      },
      onPanEnd: (_) {
        windowManager.onWindowDragEnd(window.id, viewportSize);
      },
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isFocused
              ? const Color(0xFF101524).withValues(alpha: 0.95)
              : const Color(0xFF0C101A).withValues(alpha: 0.9),
          border: Border(
            bottom: BorderSide(
              color: isFocused
                  ? CloudOSColors.accent.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.06),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            // Glow Dots Window Controls (Traffic Lights Estilizados)
            _buildTrafficDot(
              color: const Color(0xFFFB7185),
              borderColor: const Color(0xFFF43F5E),
              tooltip: 'Fechar',
              onTap: () => windowManager.closeWindow(window.id),
            ),
            const SizedBox(width: 7),
            _buildTrafficDot(
              color: const Color(0xFFFBBF24),
              borderColor: const Color(0xFFF59E0B),
              tooltip: 'Minimizar',
              onTap: () => windowManager.minimizeWindow(window.id),
            ),
            const SizedBox(width: 7),
            _buildTrafficDot(
              color: const Color(0xFF34D399),
              borderColor: const Color(0xFF10B981),
              tooltip: isMaximized ? 'Restaurar' : 'Maximizar',
              onTap: () => windowManager.toggleMaximizeWindow(window.id, viewportSize),
            ),
            const SizedBox(width: 14),

            // Ícone e Título da Janela
            Icon(
              window.icon,
              size: 15,
              color: isFocused ? CloudOSColors.accent : Colors.white60,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                window.title,
                style: TextStyle(
                  color: isFocused ? Colors.white : Colors.white60,
                  fontSize: 12,
                  fontWeight: isFocused ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Quick Snap Buttons (Snapping Rápido 50/50 na Titlebar)
            Tooltip(
              message: 'Encaixar à Esquerda (50%)',
              child: InkWell(
                onTap: () => windowManager.snapWindowLeft(window.id, viewportSize),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Icon(Icons.align_horizontal_left_rounded, size: 14, color: Colors.white.withValues(alpha: 0.5)),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Encaixar à Direita (50%)',
              child: InkWell(
                onTap: () => windowManager.snapWindowRight(window.id, viewportSize),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Icon(Icons.align_horizontal_right_rounded, size: 14, color: Colors.white.withValues(alpha: 0.5)),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Badge de Status Focado
            if (isFocused)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: CloudOSColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: CloudOSColors.accent.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  'ATIVO',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: CloudOSColors.accent,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrafficDot({
    required Color color,
    required Color borderColor,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.85),
            shape: BoxShape.circle,
            border: Border.all(color: borderColor.withValues(alpha: 0.9), width: 1),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 4,
                spreadRadius: 0.5,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
