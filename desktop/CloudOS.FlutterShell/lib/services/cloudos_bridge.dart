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
        currentWorkspace: (raw['currentWorkspace'] as num?)?.toInt() ?? previewSnapshot.currentWorkspace,
      );
    } on MissingPluginException {
      return previewSnapshot;
    } on PlatformException {
      return previewSnapshot;
    }
  }

  Future<bool> launchApp(String id) async {
    try {
      final result = await _channel.invokeMethod<bool>('launchApp', <String, Object?>{'id': id});
      return result ?? true;
    } on MissingPluginException {
      // Preview mode fallback: no side effects
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> setVolume(double value) async {
    try {
      final result = await _channel.invokeMethod<bool>('setVolume', <String, Object?>{'value': value});
      return result ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> setBrightness(double value) async {
    try {
      final result = await _channel.invokeMethod<bool>('setBrightness', <String, Object?>{'value': value});
      return result ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<Map<String, Object?>> getBridgeInfo() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('getBridgeInfo');
      if (raw != null) return raw;
    } on MissingPluginException {
      // Fallback preview
    } on PlatformException {
      // Fallback preview
    }
    return const <String, Object?>{
      'schema': 21,
      'version': 'v21-preview',
      'bridge_type': 'PreviewFallback',
      'channel': 'cloudos/native/v19',
      'brokerConnected': false,
      'brokerState': 'degraded',
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
      source: raw['source'] as String? ?? 'Sistema',
      icon: _resolveIcon(id, platformName),
      canLaunch: raw['canLaunch'] as bool? ?? true,
      pinned: raw['pinned'] as bool? ?? false,
      recent: raw['recent'] as bool? ?? false,
    );
  }

  AppPlatform _platformFromString(String platform) {
    switch (platform.toLowerCase()) {
      case 'linux':
        return AppPlatform.linux;
      case 'cloudos':
        return AppPlatform.cloudos;
      case 'windows':
      default:
        return AppPlatform.windows;
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
    if (normalized.contains('terminal') || normalized.contains('powershell') || normalized.contains('cmd') || normalized.contains('xterm')) {
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
}
