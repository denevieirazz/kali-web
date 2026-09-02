import 'package:flutter/material.dart';

export 'file_models.dart' show CloudFileItem;

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

// File-system models live exclusively in file_models.dart. CloudFileItem is
// re-exported above only for source compatibility with older imports; there is
// one declaration/type in the Flutter shell.

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
    // Deprecated compatibility field. Workspace authority lives in
    // WindowManager + Session V3. A value of 0 means "not provided by Broker".
    this.currentWorkspace = 0,
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

  CloudSystemSnapshot copyWith({
    String? deviceName,
    String? networkName,
    double? volume,
    double? brightness,
    int? batteryPercent,
    bool? wslAvailable,
    List<String>? distros,
    String? defaultDistro,
    int? currentWorkspace,
    bool? batteryAvailable,
    bool? networkAvailable,
    bool? volumeAvailable,
    bool? brightnessAvailable,
  }) {
    return CloudSystemSnapshot(
      deviceName: deviceName ?? this.deviceName,
      networkName: networkName ?? this.networkName,
      volume: volume ?? this.volume,
      brightness: brightness ?? this.brightness,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      wslAvailable: wslAvailable ?? this.wslAvailable,
      distros: List<String>.unmodifiable(distros ?? this.distros),
      defaultDistro: defaultDistro ?? this.defaultDistro,
      currentWorkspace: currentWorkspace ?? this.currentWorkspace,
      batteryAvailable: batteryAvailable ?? this.batteryAvailable,
      networkAvailable: networkAvailable ?? this.networkAvailable,
      volumeAvailable: volumeAvailable ?? this.volumeAvailable,
      brightnessAvailable: brightnessAvailable ?? this.brightnessAvailable,
    );
  }

  /// Normalizes untrusted/native values before they reach desktop chrome.
  CloudSystemSnapshot normalized() {
    final cleanDistros = <String>[];
    final seen = <String>{};
    for (final raw in distros) {
      final distro = raw.trim();
      if (distro.isEmpty || distro.length > 256) continue;
      final key = distro.toLowerCase();
      if (seen.add(key)) cleanDistros.add(distro);
    }

    final cleanDefault = defaultDistro.trim();
    final cleanBattery = batteryAvailable
        ? batteryPercent.clamp(0, 100).toInt()
        : -1;

    return CloudSystemSnapshot(
      deviceName: deviceName.trim(),
      networkName: networkAvailable ? networkName.trim() : '',
      volume: volume.isFinite ? volume.clamp(0.0, 1.0).toDouble() : 0.0,
      brightness:
          brightness.isFinite ? brightness.clamp(0.0, 1.0).toDouble() : 0.0,
      batteryPercent: cleanBattery,
      wslAvailable: wslAvailable,
      distros: List<String>.unmodifiable(cleanDistros),
      defaultDistro: cleanDefault,
      currentWorkspace:
          currentWorkspace >= 1 && currentWorkspace <= 4 ? currentWorkspace : 0,
      batteryAvailable: batteryAvailable,
      networkAvailable: networkAvailable,
      volumeAvailable: volumeAvailable,
      brightnessAvailable: brightnessAvailable,
    );
  }
}
