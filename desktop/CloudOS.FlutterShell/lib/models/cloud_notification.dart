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
  });

  final String id;
  final String title;
  final String message;
  final String time;
  final IconData icon;
  final String source;
  final String category;
}
