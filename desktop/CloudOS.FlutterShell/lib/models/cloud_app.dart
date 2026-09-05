import 'package:flutter/material.dart';

enum CloudAppPlatform { windows, linux, cloudos }

class CloudApp {
  const CloudApp({
    required this.id,
    required this.name,
    required this.icon,
    required this.platform,
    this.subtitle,
    this.distro,
    this.category = 'Produtividade',
    this.isPinned = true,
    this.isRecent = false,
    this.canLaunch = true,
    this.displayName,
    this.launchTarget,
    this.source,
    this.availability = 'ready',
    this.capabilities = const <String>[],
  });

  final String id;
  final String name;
  final IconData icon;
  final CloudAppPlatform platform;
  final String? subtitle;
  final String? distro;
  final String category;
  final bool isPinned;
  final bool isRecent;
  final bool canLaunch;
  final String? displayName;
  final String? launchTarget;
  final String? source;
  final String availability;
  final List<String> capabilities;
}
