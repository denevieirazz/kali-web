import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';

class TaskbarTaskButton extends StatelessWidget {
  const TaskbarTaskButton({
    required this.tooltip,
    required this.icon,
    this.onPressed,
    this.active = false,
    this.accent = false,
    this.isRunning = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;
  final bool accent;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final background = active
        ? CloudOSColors.active
        : accent
            ? CloudOSColors.accentSoft
            : Colors.transparent;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 40,
          height: 38,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? CloudOSColors.borderStrong : Colors.transparent,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 20,
                color: accent
                    ? CloudOSColors.accent
                    : active
                        ? CloudOSColors.text
                        : CloudOSColors.secondary,
              ),
              if (isRunning && !active)
                Positioned(
                  bottom: 3,
                  child: Container(
                    width: 14,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: CloudOSColors.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
