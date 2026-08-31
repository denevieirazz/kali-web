import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import 'glass_surface.dart';

class NotificationCenterPanel extends StatelessWidget {
  const NotificationCenterPanel({super.key});

  static const notifications = <CloudNotification>[
    CloudNotification(
      title: 'CloudOS',
      message: 'O ambiente Windows + Linux está pronto para uso.',
      time: 'agora',
      icon: Icons.cloud_done_rounded,
    ),
    CloudNotification(
      title: 'Ubuntu',
      message: 'WSL2 detectado. Aplicativos Linux podem aparecer no Start.',
      time: '2 min',
      icon: Icons.terminal_rounded,
    ),
    CloudNotification(
      title: 'Atualizações',
      message: 'Nenhuma ação é executada automaticamente no modo preview.',
      time: '8 min',
      icon: Icons.system_update_alt_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 18, 76),
        child: SizedBox(
          width: 390,
          child: GlassSurface(
            borderRadius: 24,
            blur: 30,
            color: const Color(0xF014202B),
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text('Notificações', style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    TextButton(onPressed: () {}, child: const Text('Limpar')),
                  ],
                ),
                const SizedBox(height: 8),
                for (final notification in notifications) ...<Widget>[
                  _NotificationCard(notification: notification),
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

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification});

  final CloudNotification notification;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CloudOSColors.surface.withValues(alpha: 0.82),
        border: Border.all(color: CloudOSColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: CloudOSColors.accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(notification.icon, size: 19, color: CloudOSColors.accent),
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
                        style: const TextStyle(color: CloudOSColors.text, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(notification.time, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 4),
                Text(notification.message, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
