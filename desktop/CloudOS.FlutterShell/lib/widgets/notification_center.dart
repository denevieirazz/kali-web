import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import '../services/cloudos_bridge.dart';
import 'glass_surface.dart';

class NotificationCenterPanel extends StatefulWidget {
  const NotificationCenterPanel({
    this.initialNotifications,
    this.onNotificationsChanged,
    super.key,
  });

  final List<CloudNotification>? initialNotifications;
  final ValueChanged<List<CloudNotification>>? onNotificationsChanged;

  @override
  State<NotificationCenterPanel> createState() => _NotificationCenterPanelState();
}

class _NotificationCenterPanelState extends State<NotificationCenterPanel> {
  late List<CloudNotification> items = List<CloudNotification>.from(
    widget.initialNotifications ?? CloudOSBridge.previewNotifications,
  );

  @override
  void didUpdateWidget(covariant NotificationCenterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialNotifications != widget.initialNotifications && widget.initialNotifications != null) {
      items = List<CloudNotification>.from(widget.initialNotifications!);
    }
  }

  void _publishChange() {
    widget.onNotificationsChanged?.call(List<CloudNotification>.unmodifiable(items));
  }

  void _dismiss(String id) {
    setState(() {
      items.removeWhere((n) => n.id == id);
    });
    _publishChange();
  }

  void _clearAll() {
    if (items.isEmpty) return;
    setState(items.clear);
    _publishChange();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const weekdays = <String>[
      'Segunda-feira',
      'Terça-feira',
      'Quarta-feira',
      'Quinta-feira',
      'Sexta-feira',
      'Sábado',
      'Domingo',
    ];
    const months = <String>[
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    final dateString = '${weekdays[now.weekday - 1]}, ${now.day} de ${months[now.month - 1]}';

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
                Row(
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
                            style: const TextStyle(color: CloudOSColors.caption, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    if (items.isNotEmpty)
                      TextButton(
                        onPressed: _clearAll,
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
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    alignment: Alignment.center,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.notifications_off_outlined, size: 36, color: CloudOSColors.caption),
                        SizedBox(height: 8),
                        Text(
                          'Sem novas notificações',
                          style: TextStyle(
                            color: CloudOSColors.secondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Tudo atualizado por aqui',
                          style: TextStyle(color: CloudOSColors.caption, fontSize: 11),
                        ),
                      ],
                    ),
                  )
                else
                  for (final item in items) ...<Widget>[
                    _NotificationCard(
                      notification: item,
                      onDismiss: () => _dismiss(item.id),
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

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onDismiss,
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
            child: Icon(notification.icon, size: 17, color: CloudOSColors.accent),
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
                      style: const TextStyle(color: CloudOSColors.caption, fontSize: 10.5),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: onDismiss,
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.close_rounded, size: 14, color: CloudOSColors.caption),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  notification.message,
                  style: const TextStyle(color: CloudOSColors.secondary, fontSize: 11.5),
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
