import 'dart:io';

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
    } on TypeError {
      return previewApps;
    }
  }

  Future<CloudSystemSnapshot> loadSystemSnapshot() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('getSystemSnapshot');
      if (raw == null) return previewSnapshot;
      return CloudSystemSnapshot(
        deviceName: raw['deviceName'] as String? ?? previewSnapshot.deviceName,
        userName: raw['userName'] as String? ?? previewSnapshot.userName,
        sessionId: (raw['sessionId'] as num?)?.toInt() ?? previewSnapshot.sessionId,
        batteryAvailable: raw['batteryAvailable'] as bool? ?? previewSnapshot.batteryAvailable,
        batteryPercent: ((raw['batteryPercent'] as num?)?.toInt() ?? previewSnapshot.batteryPercent).clamp(0, 100).toInt(),
        networkAvailable: raw['networkAvailable'] as bool? ?? previewSnapshot.networkAvailable,
        networkName: raw['networkName'] as String? ?? previewSnapshot.networkName,
        volumeAvailable: raw['volumeAvailable'] as bool? ?? previewSnapshot.volumeAvailable,
        volume: ((raw['volume'] as num?)?.toDouble() ?? previewSnapshot.volume).clamp(0.0, 1.0).toDouble(),
        brightnessAvailable: raw['brightnessAvailable'] as bool? ?? previewSnapshot.brightnessAvailable,
        brightness: ((raw['brightness'] as num?)?.toDouble() ?? previewSnapshot.brightness).clamp(0.0, 1.0).toDouble(),
        wslAvailable: raw['wslAvailable'] as bool? ?? previewSnapshot.wslAvailable,
        distros: (raw['distros'] as List<Object?>?)?.whereType<String>().where((value) => value.trim().isNotEmpty).toList() ??
            previewSnapshot.distros,
        currentWorkspace: ((raw['currentWorkspace'] as num?)?.toInt() ?? previewSnapshot.currentWorkspace).clamp(1, 4).toInt(),
      );
    } on MissingPluginException {
      return previewSnapshot;
    } on PlatformException {
      return previewSnapshot;
    } on TypeError {
      return previewSnapshot;
    }
  }

  Future<bool> launchApp(String id) async {
    if (id.trim().isEmpty) return false;
    try {
      final result = await _channel.invokeMethod<bool>('launchApp', <String, Object?>{'id': id});
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> setVolume(double value) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'setVolume',
        <String, Object?>{'value': value.clamp(0.0, 1.0).toDouble()},
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> setBrightness(double value) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'setBrightness',
        <String, Object?>{'value': value.clamp(0.0, 1.0).toDouble()},
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<Map<String, Object?>> getBridgeInfo() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('getBridgeInfo');
      if (raw != null) return raw;
    } on MissingPluginException {
      // Conservative fallback below.
    } on PlatformException {
      // Conservative fallback below.
    } on TypeError {
      // Conservative fallback below.
    }
    return const <String, Object?>{
      'schema': 21,
      'version': 'v21-preview',
      'bridge_type': 'PreviewFallback',
      'brokerConnected': false,
      'brokerState': 'degraded',
      'channel': 'cloudos/native/v19',
      'arbitrary_command_api': false,
    };
  }

  CloudApp _appFromNative(Map<Object?, Object?> raw) {
    final platformName = raw['platform'] as String? ?? 'windows';
    final id = raw['id'] as String? ?? 'app';
    final name = raw['name'] as String? ?? id;

    return CloudApp(
      id: id,
      name: name,
      platform: _platformFromString(platformName),
      subtitle: raw['subtitle'] as String? ?? '',
      distro: raw['distro'] as String?,
      category: raw['category'] as String? ?? 'Utilitários',
      icon: _resolveIcon(id, platformName),
      isPinned: raw['pinned'] as bool? ?? false,
      isRecent: raw['recent'] as bool? ?? false,
    );
  }

  CloudAppPlatform _platformFromString(String platform) {
    switch (platform.toLowerCase()) {
      case 'linux':
        return CloudAppPlatform.linux;
      case 'cloudos':
        return CloudAppPlatform.cloudos;
      case 'windows':
      default:
        return CloudAppPlatform.windows;
    }
  }

  IconData _resolveIcon(String id, String platform) {
    final normalized = id.toLowerCase();
    if (normalized.contains('files') || normalized.contains('explorer')) {
      return Icons.folder_rounded;
    }
    if (normalized.contains('browser') || normalized.contains('chrome') || normalized.contains('edge')) {
      return Icons.public_rounded;
    }
    if (normalized.contains('terminal') ||
        normalized.contains('powershell') ||
        normalized.contains('cmd') ||
        normalized.contains('xterm')) {
      return Icons.terminal_rounded;
    }
    if (normalized.contains('calc')) {
      return Icons.calculate_rounded;
    }
    if (normalized.contains('settings') || normalized.contains('config')) {
      return Icons.settings_rounded;
    }
    if (normalized.contains('drive')) {
      return Icons.cloud_queue_rounded;
    }
    if (normalized.contains('trash') || normalized.contains('recycle')) {
      return Icons.delete_outline_rounded;
    }
    if (normalized.contains('vscode') || normalized.contains('code')) {
      return Icons.code_rounded;
    }
    if (normalized.contains('notepad')) {
      return Icons.edit_note_rounded;
    }
    if (normalized.contains('taskmgr')) {
      return Icons.monitor_heart_rounded;
    }
    if (normalized.contains('gimp') || normalized.contains('image')) {
      return Icons.brush_rounded;
    }
    if (normalized.contains('wireshark') || normalized.contains('zenmap')) {
      return Icons.security_rounded;
    }
    if (platform.toLowerCase() == 'linux') {
      return Icons.auto_awesome_mosaic_rounded;
    }
    return Icons.apps_rounded;
  }

  static final previewSnapshot = CloudSystemSnapshot(
    deviceName: Platform.environment['COMPUTERNAME'] ?? 'CloudOS Desktop',
    userName: Platform.environment['USERNAME'] ?? 'User',
    networkName: 'Broker offline',
    volume: 0,
    brightness: 0,
    batteryPercent: 100,
    wslAvailable: false,
    distros: const <String>[],
    batteryAvailable: false,
    networkAvailable: false,
    volumeAvailable: false,
    brightnessAvailable: false,
    currentWorkspace: 1,
  );

  // Degraded mode only advertises the one surface that the Flutter shell can
  // provide without the native MethodChannel/System Broker being available.
  static const previewApps = <CloudApp>[
    CloudApp(
      id: 'cloudos:files',
      name: 'Arquivos',
      icon: Icons.folder_rounded,
      platform: CloudAppPlatform.cloudos,
      subtitle: 'Arquivos locais',
      category: 'Sistema',
      isPinned: true,
      isRecent: true,
    ),
  ];

  static Map<String, List<CloudFileItem>> get previewFiles {
    final profile = Platform.environment['USERPROFILE'] ?? r'C:\Users';
    return <String, List<CloudFileItem>>{
      'home': <CloudFileItem>[
        CloudFileItem(
          name: 'Documentos',
          path: '$profile\\Documents',
          isFolder: true,
          sizeFormatted: 'Pasta',
          modifiedFormatted: 'Local',
          source: CloudFileSource.windows,
          icon: Icons.folder_special_rounded,
        ),
        CloudFileItem(
          name: 'Downloads',
          path: '$profile\\Downloads',
          isFolder: true,
          sizeFormatted: 'Pasta',
          modifiedFormatted: 'Local',
          source: CloudFileSource.windows,
          icon: Icons.download_rounded,
        ),
      ],
    };
  }

  static const previewNotifications = <CloudNotification>[
    CloudNotification(
      id: 'notif-1',
      title: 'CloudOS V21',
      message: 'Interface V21 ativa. O estado do System Broker aparece no cartão do sistema.',
      time: 'agora',
      icon: Icons.cloud_rounded,
      source: 'CloudOS Core',
      category: 'Sistema',
    ),
  ];
}
