import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';

class NotificationEmptyState extends StatelessWidget {
  const NotificationEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.notifications_off_outlined,
            size: 36,
            color: CloudOSColors.caption,
          ),
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
    );
  }
}
