import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';

class TaskbarTaskButton extends StatelessWidget {
  const TaskbarTaskButton({
    required this.tooltip,
    required this.icon,
    this.onPressed,
    this.onClose,
    this.label,
    this.active = false,
    this.accent = false,
    this.isRunning = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final VoidCallback? onClose;
  final String? label;
  final bool active;
  final bool accent;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final showRunningTask = isRunning && label != null;
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
        child: Container(
          width: showRunningTask ? 126 : 40,
          height: 38,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? CloudOSColors.borderStrong : Colors.transparent,
            ),
          ),
          child: showRunningTask
              ? Stack(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(9, 0, 4, 2),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            icon,
                            size: 19,
                            color: active
                                ? CloudOSColors.text
                                : CloudOSColors.secondary,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              label!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: active
                                    ? CloudOSColors.text
                                    : CloudOSColors.secondary,
                                fontSize: 11,
                                fontWeight: active
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          Tooltip(
                            message: 'Fechar $label',
                            child: InkWell(
                              key: ValueKey<String>('taskbar-close-$label'),
                              onTap: onClose,
                              borderRadius: BorderRadius.circular(6),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close_rounded,
                                  color: CloudOSColors.secondary,
                                  size: 15,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 2,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: CloudOSColors.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                )
              : Icon(
                  icon,
                  size: 20,
                  color: accent
                      ? CloudOSColors.accent
                      : active
                      ? CloudOSColors.text
                      : CloudOSColors.secondary,
                ),
        ),
      ),
    );
  }
}
