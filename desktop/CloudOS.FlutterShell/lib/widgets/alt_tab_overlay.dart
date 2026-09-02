import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../models/window_model.dart';

/// Responsive task-switcher surface. Selection semantics are owned by the
/// shell/WindowManager; this widget only renders typed window state.
class AltTabOverlay extends StatelessWidget {
  const AltTabOverlay({
    super.key,
    required this.windows,
    required this.selectedIndex,
    required this.onSelect,
    required this.onClose,
  });

  final List<CloudWindow> windows;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (windows.isEmpty) return const SizedBox.shrink();
    final media = MediaQuery.sizeOf(context);
    final safeSelected = selectedIndex.clamp(0, windows.length - 1).toInt();
    final maxWidth = (media.width - 48).clamp(320.0, 980.0).toDouble();
    final cardWidth = media.width < 900 ? 126.0 : 154.0;

    return GestureDetector(
      onTap: onClose,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black.withValues(alpha: 0.42),
        alignment: Alignment.center,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Container(
              constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 360),
              padding: const EdgeInsets.fromLTRB(20, 17, 20, 18),
              decoration: BoxDecoration(
                color: const Color(0xF20C101C),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: CloudOSColors.accent.withValues(alpha: 0.4),
                  width: 1.25,
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Colors.black87,
                    blurRadius: 44,
                    offset: Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.flip_to_front_rounded,
                        size: 18,
                        color: CloudOSColors.accent,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Alternador de Janelas',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      Text(
                        '${safeSelected + 1}/${windows.length}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Colors.white38,
                          fontFamily: 'Consolas',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 174,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: windows.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 9),
                      itemBuilder: (context, index) {
                        return SizedBox(
                          width: cardWidth,
                          child: _AltTabCard(
                            window: windows[index],
                            selected: index == safeSelected,
                            onTap: () => onSelect(index),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 11),
                  const Row(
                    children: <Widget>[
                      _HintKey('Alt+Tab'),
                      SizedBox(width: 6),
                      Text(
                        'próxima',
                        style: TextStyle(fontSize: 10, color: Colors.white30),
                      ),
                      SizedBox(width: 14),
                      _HintKey('Shift+Alt+Tab'),
                      SizedBox(width: 6),
                      Text(
                        'anterior',
                        style: TextStyle(fontSize: 10, color: Colors.white30),
                      ),
                      SizedBox(width: 14),
                      _HintKey('Esc'),
                      SizedBox(width: 6),
                      Text(
                        'cancelar',
                        style: TextStyle(fontSize: 10, color: Colors.white30),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AltTabCard extends StatelessWidget {
  const _AltTabCard({
    required this.window,
    required this.selected,
    required this.onTap,
  });

  final CloudWindow window;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: selected
                ? CloudOSColors.accent.withValues(alpha: 0.17)
                : Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? CloudOSColors.accent
                  : Colors.white.withValues(alpha: 0.075),
              width: selected ? 1.7 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? CloudOSColors.accent.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.045),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      window.icon,
                      size: 24,
                      color: selected ? CloudOSColors.accent : Colors.white70,
                    ),
                  ),
                  const Spacer(),
                  if (window.minimized)
                    const _StatusBadge(
                      text: 'MIN',
                      icon: Icons.remove_rounded,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                window.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.18,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? Colors.white : Colors.white70,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.grid_view_rounded,
                    size: 10,
                    color: Colors.white.withValues(alpha: 0.28),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Workspace ${window.workspaceIndex}',
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: Colors.white30,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.text, required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 9, color: Colors.white38),
          const SizedBox(width: 2),
          Text(
            text,
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: Colors.white38,
            ),
          ),
        ],
      ),
    );
  }
}

class _HintKey extends StatelessWidget {
  const _HintKey(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9,
          color: Colors.white54,
          fontFamily: 'Consolas',
        ),
      ),
    );
  }
}
