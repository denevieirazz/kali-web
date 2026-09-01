import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';
import '../../../../models/shell_models.dart';

class NotificationCard extends StatelessWidget {
  const NotificationCard({
    required this.notification,
    required this.onDismiss,
    super.key,
  });

  final CloudNotification notification;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: CloudOSColors.elevated.withValues(alpha: 0.45),
        border: Border.all(color: CloudOSColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: CloudOSColors.accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              notification.icon,
              size: 17,
              color: CloudOSColors.accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        notification.title,
                        style: const TextStyle(
                          color: CloudOSColors.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      notification.time,
                      style: const TextStyle(
                        color: CloudOSColors.caption,
                        fontSize: 10.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: onDismiss,
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: CloudOSColors.caption,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  notification.message,
                  style: const TextStyle(
                    color: CloudOSColors.secondary,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: CloudOSColors.border.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    notification.source,
                    style: const TextStyle(
                      color: CloudOSColors.caption,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
