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

enum CloudFileSource { cloudDrive, windows, linux, trash }

class CloudFileItem {
  const CloudFileItem({
    required this.name,
    required this.path,
    required this.isFolder,
    required this.sizeFormatted,
    required this.modifiedFormatted,
    required this.source,
    this.icon,
    this.extension,
  });

  final String name;
  final String path;
  final bool isFolder;
  final String sizeFormatted;
  final String modifiedFormatted;
  final CloudFileSource source;
  final IconData? icon;
  final String? extension;
}

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
    this.userName = 'User',
    this.sessionId = 1,
    this.batteryAvailable = false,
    this.networkAvailable = false,
    this.volumeAvailable = false,
    this.brightnessAvailable = false,
    this.currentWorkspace = 1,
  });

  final String deviceName;
  final String userName;
  final int sessionId;
  final bool batteryAvailable;
  final int batteryPercent;
  final bool networkAvailable;
  final String networkName;
  final bool volumeAvailable;
  final double volume;
  final bool brightnessAvailable;
  final double brightness;
  final bool wslAvailable;
  final List<String> distros;
  final int currentWorkspace;
}
