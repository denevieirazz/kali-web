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
}

// File-system models live exclusively in file_models.dart. Keeping the old
// pre-V22 CloudFileItem here created two incompatible types with the same name
// and made any consumer that also used the Files V22 model ambiguous.

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

class CloudSystemSnapshot {
  const CloudSystemSnapshot({
    required this.deviceName,
    required this.networkName,
    required this.volume,
    required this.brightness,
    required this.batteryPercent,
    required this.wslAvailable,
    required this.distros,
    this.defaultDistro = '',
    this.currentWorkspace = 1,
    this.batteryAvailable = false,
    this.networkAvailable = false,
    this.volumeAvailable = false,
    this.brightnessAvailable = false,
  });

  final String deviceName;
  final String networkName;
  final double volume;
  final double brightness;
  final int batteryPercent;
  final bool wslAvailable;
  final List<String> distros;
  final String defaultDistro;
  final int currentWorkspace;
  final bool batteryAvailable;
  final bool networkAvailable;
  final bool volumeAvailable;
  final bool brightnessAvailable;
}
