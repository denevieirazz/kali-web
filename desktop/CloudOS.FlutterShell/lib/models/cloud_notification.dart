import 'package:flutter/material.dart';

class CloudNotification {
  const CloudNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.time,
    required this.icon,
    this.source = 'Sistema',
    this.category = 'Geral',
    this.severity = 0,
    this.read = false,
  });

  final String id;
  final String title;
  final String message;
  final String time;
  final IconData icon;
  final String source;
  final String category;
  final int severity;
  final bool read;

  CloudNotification copyWith({bool? read}) {
    return CloudNotification(
      id: id,
      title: title,
      message: message,
      time: time,
      icon: icon,
      source: source,
      category: category,
      severity: severity,
      read: read ?? this.read,
    );
  }
}

class CloudNotificationState {
  const CloudNotificationState({
    required this.revision,
    required this.unreadCount,
    required this.items,
  });

  static const empty = CloudNotificationState(
    revision: 0,
    unreadCount: 0,
    items: <CloudNotification>[],
  );

  final int revision;
  final int unreadCount;
  final List<CloudNotification> items;

  CloudNotificationState copyWith({
    int? revision,
    int? unreadCount,
    List<CloudNotification>? items,
  }) {
    return CloudNotificationState(
      revision: revision ?? this.revision,
      unreadCount: unreadCount ?? this.unreadCount,
      items: items ?? this.items,
    );
  }
}
