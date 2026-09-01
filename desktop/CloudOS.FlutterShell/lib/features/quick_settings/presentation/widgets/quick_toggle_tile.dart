import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';

class QuickToggleTile extends StatelessWidget {
  const QuickToggleTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.active,
    required this.onTap,
    super.key,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? CloudOSColors.accentSoft : CloudOSColors.elevated.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? CloudOSColors.accent : CloudOSColors.border,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              color: active ? CloudOSColors.accent : CloudOSColors.secondary,
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
                    style: const TextStyle(
                      color: CloudOSColors.text,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: CloudOSColors.caption, fontSize: 9.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
