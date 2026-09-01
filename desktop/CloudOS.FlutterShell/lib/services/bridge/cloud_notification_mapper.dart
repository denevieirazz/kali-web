import 'package:flutter/material.dart';

import '../../models/cloud_notification.dart';

CloudNotificationState cloudNotificationStateFromNative(
  Map<Object?, Object?> raw,
) {
  final rawItems = raw['items'];
  final items = <CloudNotification>[];
  if (rawItems is List) {
    for (final rawItem in rawItems) {
      if (rawItem is Map) {
        final item = Map<Object?, Object?>.from(rawItem);
        final severity = (item['severity'] as num?)?.toInt() ?? 0;
        items.add(
          CloudNotification(
            id: item['id'] as String? ?? '',
            title: item['title'] as String? ?? 'CloudOS',
            message: item['message'] as String? ?? '',
            time: item['time'] as String? ?? '--:--',
            icon: severity > 0
                ? Icons.warning_amber_rounded
                : Icons.notifications_rounded,
            source: 'CloudOS',
            category: severity > 0 ? 'Alerta' : 'Sistema',
            severity: severity,
            read: item['read'] as bool? ?? false,
          ),
        );
      }
    }
  }

  return CloudNotificationState(
    revision: (raw['revision'] as num?)?.toInt() ?? 0,
    unreadCount: (raw['unreadCount'] as num?)?.toInt() ?? 0,
    items: List<CloudNotification>.unmodifiable(items),
  );
}
