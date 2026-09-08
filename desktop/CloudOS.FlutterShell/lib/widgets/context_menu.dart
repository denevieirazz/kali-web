import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/cloudos_theme.dart';

class ContextMenuItemData {
  const ContextMenuItemData({
    required this.title,
    required this.icon,
    this.onTap,
    this.shortcut,
    this.isDestructive = false,
    this.isDivider = false,
    this.color,
  });

  final String title;
  final IconData icon;
  final VoidCallback? onTap;
  final String? shortcut;
  final bool isDestructive;
  final bool isDivider;
  final Color? color;
}

class ContextMenuOverlay extends StatelessWidget {
  const ContextMenuOverlay({
    super.key,
    required this.position,
    required this.items,
    required this.onDismiss,
  });

  final Offset position;
  final List<ContextMenuItemData> items;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    const menuWidth = 230.0;
    final menuHeight = items.length * 36.0 + 16.0;

    final left = position.dx + menuWidth > size.width
        ? (size.width - menuWidth - 12.0).clamp(0.0, double.infinity)
        : position.dx;
    final top = position.dy + menuHeight > (size.height - 48.0)
        ? (size.height - 48.0 - menuHeight - 12.0).clamp(0.0, double.infinity)
        : position.dy;

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            onSecondaryTap: onDismiss,
            child: Container(color: Colors.transparent),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: menuWidth,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                decoration: BoxDecoration(
                  color: const Color(0xF00D111D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 1,
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x80000000),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: items.map((item) {
                    if (item.isDivider) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Divider(height: 1, color: Color(0x1AFFFFFF)),
                      );
                    }
                    final itemColor = item.isDestructive
                        ? CloudOSColors.danger
                        : (item.color ?? Colors.white);

                    return InkWell(
                      onTap: () {
                        onDismiss();
                        item.onTap?.call();
                      },
                      borderRadius: BorderRadius.circular(6),
                      hoverColor: CloudOSColors.accent.withValues(alpha: 0.15),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        child: Row(
                          children: <Widget>[
                            Icon(item.icon, size: 15, color: itemColor),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item.title,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: itemColor,
                                ),
                              ),
                            ),
                            if (item.shortcut != null)
                              Text(
                                item.shortcut!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white38,
                                  fontFamily: 'Consolas',
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
