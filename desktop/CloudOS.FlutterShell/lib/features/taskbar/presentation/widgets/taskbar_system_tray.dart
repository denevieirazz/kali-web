import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';

class TaskbarSystemTray extends StatelessWidget {
  const TaskbarSystemTray({
    required this.quickSettingsOpen,
    required this.notificationsOpen,
    required this.notificationCount,
    required this.onQuickSettings,
    required this.onNotifications,
    super.key,
  });

  final bool quickSettingsOpen;
  final bool notificationsOpen;
  final int notificationCount;
  final VoidCallback onQuickSettings;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _TrayQuickGroup(
          onPressed: onQuickSettings,
          active: quickSettingsOpen,
        ),
        const SizedBox(width: 6),
        _ClockButton(onPressed: onNotifications),
        const SizedBox(width: 4),
        _NotificationTrayButton(
          active: notificationsOpen,
          count: notificationCount,
          onPressed: onNotifications,
        ),
      ],
    );
  }
}

class _TrayQuickGroup extends StatelessWidget {
  const _TrayQuickGroup({required this.onPressed, required this.active});

  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Configurações Rápidas (Ctrl+Alt+Q)',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: active ? CloudOSColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? CloudOSColors.borderStrong : Colors.transparent,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.wifi_rounded, size: 15, color: CloudOSColors.secondary),
              SizedBox(width: 6),
              Icon(Icons.volume_up_rounded, size: 15, color: CloudOSColors.secondary),
              SizedBox(width: 6),
              Icon(Icons.battery_5_bar_rounded, size: 15, color: CloudOSColors.secondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationTrayButton extends StatelessWidget {
  const _NotificationTrayButton({
    required this.active,
    required this.count,
    required this.onPressed,
  });

  final bool active;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Notificações',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: active ? CloudOSColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? CloudOSColors.borderStrong : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                count > 0 ? Icons.notifications_rounded : Icons.notifications_none_rounded,
                size: 16,
                color: count > 0 ? CloudOSColors.accent : CloudOSColors.secondary,
              ),
              if (count > 0) ...<Widget>[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: CloudOSColors.accent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ClockButton extends StatelessWidget {
  const _ClockButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = now.year.toString();

    return Tooltip(
      message: 'Calendário e Notificações',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                '$hour:$minute',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: CloudOSColors.text,
                ),
              ),
              Text(
                '$day/$month/$year',
                style: const TextStyle(
                  fontSize: 9.5,
                  color: CloudOSColors.caption,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
