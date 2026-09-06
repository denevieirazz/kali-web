import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';

class QuickToggleTile extends StatelessWidget {
  const QuickToggleTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.active,
    this.enabled = true,
    this.showChevron = false,
    this.onTap,
    super.key,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool active;
  final bool enabled;
  final bool showChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveOnTap = enabled ? onTap : null;
    final foreground = enabled
        ? CloudOSColors.secondary
        : CloudOSColors.secondary.withValues(alpha: 0.45);
    final labelColor = enabled
        ? CloudOSColors.text
        : CloudOSColors.text.withValues(alpha: 0.45);
    final activeState = enabled && active;

    return InkWell(
      onTap: effectiveOnTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: activeState
              ? CloudOSColors.accentSoft
              : CloudOSColors.elevated.withValues(alpha: enabled ? 0.4 : 0.22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: activeState ? CloudOSColors.accent : CloudOSColors.border,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              color: activeState ? CloudOSColors.accent : foreground,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: labelColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground.withValues(alpha: enabled ? 0.82 : 0.60),
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),
            if (showChevron) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: foreground.withValues(alpha: 0.75),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
