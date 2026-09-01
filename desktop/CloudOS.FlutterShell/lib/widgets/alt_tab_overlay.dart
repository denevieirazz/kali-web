import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/cloudos_theme.dart';
import '../models/window_model.dart';

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

    return GestureDetector(
      onTap: onClose,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black.withValues(alpha: 0.4),
        alignment: Alignment.center,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xF20C101C),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: CloudOSColors.accent.withValues(alpha: 0.4), width: 1.5),
                boxShadow: const <BoxShadow>[
                  BoxShadow(color: Colors.black87, blurRadius: 40, offset: Offset(0, 16)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text(
                    'Alternador de Janelas • CloudOS Alt+Tab',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(windows.length, (index) {
                      final win = windows[index];
                      final isSelected = index == selectedIndex;
                      return GestureDetector(
                        onTap: () => onSelect(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: isSelected ? CloudOSColors.accent.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? CloudOSColors.accent : Colors.white.withValues(alpha: 0.08),
                              width: isSelected ? 2.0 : 1.0,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Icon(win.icon, size: 32, color: isSelected ? CloudOSColors.accent : Colors.white70),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  win.title,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected ? Colors.white : Colors.white60,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
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
