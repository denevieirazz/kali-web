import 'package:flutter/material.dart';

class StartRunningApp {
  const StartRunningApp({
    required this.id,
    required this.title,
    required this.icon,
    required this.appIds,
    this.isMinimized = false,
    this.isActive = false,
  });

  final String id;
  final String title;
  final IconData icon;
  final Set<String> appIds;
  final bool isMinimized;
  final bool isActive;

  bool matchesAppId(String appId) => appIds.contains(appId);
}
