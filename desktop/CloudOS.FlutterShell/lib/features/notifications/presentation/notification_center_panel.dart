import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../models/cloud_notification.dart';
import '../../../widgets/glass_surface.dart';
import '../domain/notification_date_formatter.dart';
import 'widgets/notification_card.dart';
import 'widgets/notification_empty_state.dart';

class NotificationCenterPanel extends StatelessWidget {
  const NotificationCenterPanel({
    required this.notifications,
    required this.onDismiss,
    required this.onClearAll,
    super.key,
  });

  final List<CloudNotification> notifications;
  final ValueChanged<String> onDismiss;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final dateString = formatNotificationDate(DateTime.now());

    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 16, 68),
        child: SizedBox(
          width: 390,
          child: GlassSurface(
            borderRadius: 16,
            blur: 24,
            color: const Color(0xF4121A25),
            borderColor: CloudOSColors.borderStrong,
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _NotificationHeader(
                  dateString: dateString,
                  canClear: notifications.isNotEmpty,
                  onClearAll: onClearAll,
                ),
                const SizedBox(height: 12),
                if (notifications.isEmpty)
                  const NotificationEmptyState()
                else
                  for (final item in notifications) ...<Widget>[
                    NotificationCard(
                      notification: item,
                      onDismiss: () => onDismiss(item.id),
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationHeader extends StatelessWidget {
  const _NotificationHeader({
    required this.dateString,
    required this.canClear,
    required this.onClearAll,
  });

  final String dateString;
  final bool canClear;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Centro de Notificações',
                style: TextStyle(
                  color: CloudOSColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dateString,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CloudOSColors.caption,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        if (canClear)
          TextButton(
            onPressed: onClearAll,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text(
              'Limpar Tudo',
              style: TextStyle(fontSize: 11.5, color: CloudOSColors.accent),
            ),
          ),
      ],
    );
  }
}
