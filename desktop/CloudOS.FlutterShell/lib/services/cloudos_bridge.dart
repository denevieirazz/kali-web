import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/shell_models.dart';

class CloudOSBridge {
  const CloudOSBridge({
    MethodChannel channel = const MethodChannel('cloudos/native/v19'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<List<CloudApp>> loadApps() async {
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('getApps');
      if (raw == null || raw.isEmpty) return previewApps;
      return raw.map(_appFromNative).toList(growable: false);
    } on MissingPluginException {
      return previewApps;
    } on PlatformException {
      return previewApps;
    }
  }

  Future<CloudSystemSnapshot> loadSystemSnapshot() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('getSystemSnapshot');
      if (raw == null) return previewSnapshot;
      return CloudSystemSnapshot(
        deviceName: raw['deviceName'] as String? ?? previewSnapshot.deviceName,
        networkName: raw['networkName'] as String? ?? previewSnapshot.networkName,
        volume: (raw['volume'] as num?)?.toDouble() ?? previewSnapshot.volume,
        brightness: (raw['brightness'] as num?)?.toDouble() ?? previewSnapshot.brightness,
        batteryPercent: (raw['batteryPercent'] as num?)?.toInt() ?? previewSnapshot.batteryPercent,
        wslAvailable: raw['wslAvailable'] as bool? ?? previewSnapshot.wslAvailable,
        distros: (raw['distros'] as List<Object?>?)?.whereType<String>().toList() ??
            previewSnapshot.distros,
      );
    } on MissingPluginException {
      return previewSnapshot;
    } on PlatformException {
      return previewSnapshot;
    }
  }

  Future<void> launchApp(String id) async {
    try {
      await _channel.invokeMethod<void>('launchApp', <String, Object?>{'id': id});
    } on MissingPluginException {
      // Preview mode intentionally has no side effects.
    } on PlatformException {
      // Native launch errors are surfaced by the real host in the next stage.
    }
  }

  CloudApp _appFromNative(Map<Object?, Object?> raw) {
    final platformName = raw['platform'] as String? ?? 'windows';
    final platform = switch (platformName.toLowerCase()) {
      'linux' => CloudAppPlatform.linux,
      'cloudos' => CloudAppPlatform.cloudos,
      _ => CloudAppPlatform.windows,
    };
    return CloudApp(
      id: raw['id'] as String? ?? raw['name'] as String? ?? 'app',
      name: raw['name'] as String? ?? 'Aplicativo',
      icon: _fallbackIcon(platform),
      platform: platform,
      subtitle: raw['subtitle'] as String?,
      distro: raw['distro'] as String?,
    );
  }

  static IconData _fallbackIcon(CloudAppPlatform platform) {
    return switch (platform) {
      CloudAppPlatform.windows => Icons.window_rounded,
      CloudAppPlatform.linux => Icons.terminal_rounded,
      CloudAppPlatform.cloudos => Icons.cloud_rounded,
    };
  }

  static const previewSnapshot = CloudSystemSnapshot(
    deviceName: 'CloudOS Desktop',
    networkName: 'CloudOS Network',
    volume: 0.68,
    brightness: 0.78,
    batteryPercent: 86,
    wslAvailable: true,
    distros: <String>['Ubuntu'],
  );

  static const previewApps = <CloudApp>[
    CloudApp(
      id: 'files',
      name: 'Arquivos',
      icon: Icons.folder_rounded,
      platform: CloudAppPlatform.cloudos,
      subtitle: 'Windows + Linux',
    ),
    CloudApp(
      id: 'browser',
      name: 'Browser',
      icon: Icons.public_rounded,
      platform: CloudAppPlatform.cloudos,
      subtitle: 'WebView2',
    ),
    CloudApp(
      id: 'terminal',
      name: 'Terminal',
      icon: Icons.terminal_rounded,
      platform: CloudAppPlatform.cloudos,
      subtitle: 'PowerShell + WSL',
    ),
    CloudApp(
      id: 'settings',
      name: 'Configurações',
      icon: Icons.settings_rounded,
      platform: CloudAppPlatform.cloudos,
    ),
    CloudApp(
      id: 'vscode',
      name: 'Visual Studio Code',
      icon: Icons.code_rounded,
      platform: CloudAppPlatform.windows,
      subtitle: 'Windows',
    ),
    CloudApp(
      id: 'explorer',
      name: 'Explorer',
      icon: Icons.folder_copy_rounded,
      platform: CloudAppPlatform.windows,
      subtitle: 'Windows',
    ),
    CloudApp(
      id: 'ubuntu-terminal',
      name: 'Ubuntu',
      icon: Icons.terminal_rounded,
      platform: CloudAppPlatform.linux,
      subtitle: 'Linux • WSLg',
      distro: 'Ubuntu',
    ),
    CloudApp(
      id: 'linux-files',
      name: 'Linux Files',
      icon: Icons.folder_special_rounded,
      platform: CloudAppPlatform.linux,
      subtitle: 'Ubuntu • WSL',
      distro: 'Ubuntu',
    ),
  ];
}
