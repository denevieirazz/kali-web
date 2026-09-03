import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../widgets/glass_surface.dart';
import 'cloud_window.dart';

class AltTabSwitcher extends StatelessWidget {
  const AltTabSwitcher({
    required this.windows,
    required this.selectedIndex,
    required this.onSelect,
    super.key,
  });

  final List<CloudWindow> windows;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (windows.isEmpty) return const SizedBox.shrink();

    return Center(
      child: GlassSurface(
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'Alternador de Janelas CloudOS (Alt+Tab)',
              style: TextStyle(
                color: CloudOSColors.caption,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List<Widget>.generate(windows.length, (index) {
                final win = windows[index];
                final isSelected = index == selectedIndex;
                return GestureDetector(
                  onTap: () => onSelect(index),
                  child: Container(
                    width: 110,
                    height: 90,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? CloudOSColors.accentSoft
                          : const Color(0xFF141A26),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? CloudOSColors.accent
                            : CloudOSColors.border,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          win.icon,
                          size: 32,
                          color: isSelected
                              ? CloudOSColors.accent
                              : CloudOSColors.secondary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          win.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isSelected ? Colors.white : CloudOSColors.text,
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
    );
  }
}
