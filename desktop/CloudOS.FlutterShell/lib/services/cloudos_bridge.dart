import 'package:flutter/services.dart';

import '../models/shell_models.dart';
import 'bridge/cloud_app_mapper.dart';
import 'bridge/cloud_file_mapper.dart';
import 'bridge/cloudos_preview_data.dart';

class CloudOSBridge {
  const CloudOSBridge({
    MethodChannel channel = const MethodChannel('cloudos/native/v19'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<List<CloudApp>> loadApps() async {
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('getApps');
      if (raw == null || raw.isEmpty) return previewApps;
      return raw.map(cloudAppFromNative).toList(growable: false);
    } on MissingPluginException {
      return previewApps;
    } on PlatformException {
      return previewApps;
    }
  }

  Future<List<CloudFileItem>> loadFiles(String location) async {
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'getFiles',
        <String, Object?>{'location': location},
      );
      if (raw == null) return const <CloudFileItem>[];
      return raw.map(cloudFileFromNative).toList(growable: false);
    } on MissingPluginException {
      return previewFiles[location] ?? const <CloudFileItem>[];
    } on PlatformException {
      return const <CloudFileItem>[];
    }
  }

  Future<List<CloudFileItem>> loadFilesEntry(String entryId) async {
    if (entryId.isEmpty) return const <CloudFileItem>[];
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'getFilesEntry',
        <String, Object?>{'entryId': entryId},
      );
      if (raw == null) return const <CloudFileItem>[];
      return raw.map(cloudFileFromNative).toList(growable: false);
    } on MissingPluginException {
      return const <CloudFileItem>[];
    } on PlatformException {
      return const <CloudFileItem>[];
    }
  }

  Future<bool> openFileEntry(String entryId) async {
    if (entryId.isEmpty) return false;
    try {
      final opened = await _channel.invokeMethod<bool>(
        'openFileEntry',
        <String, Object?>{'entryId': entryId},
      );
      return opened ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<CloudSystemSnapshot> loadSystemSnapshot() async {
    try {
      final raw =
          await _channel.invokeMapMethod<String, Object?>('getSystemSnapshot');
      if (raw == null) return previewSnapshot;
      return CloudSystemSnapshot(
        deviceName:
            raw['deviceName'] as String? ?? previewSnapshot.deviceName,
        networkAvailable: raw['networkAvailable'] as bool? ??
            previewSnapshot.networkAvailable,
        networkName:
            raw['networkName'] as String? ?? previewSnapshot.networkName,
        volumeAvailable: raw['volumeAvailable'] as bool? ??
            previewSnapshot.volumeAvailable,
        volume:
            (raw['volume'] as num?)?.toDouble() ?? previewSnapshot.volume,
        brightnessAvailable: raw['brightnessAvailable'] as bool? ??
            previewSnapshot.brightnessAvailable,
        brightness: (raw['brightness'] as num?)?.toDouble() ??
            previewSnapshot.brightness,
        batteryPercent: (raw['batteryPercent'] as num?)?.toInt() ??
            previewSnapshot.batteryPercent,
        wslAvailable:
            raw['wslAvailable'] as bool? ?? previewSnapshot.wslAvailable,
        distros: (raw['distros'] as List<Object?>?)
                ?.whereType<String>()
                .toList() ??
            previewSnapshot.distros,
        currentWorkspace: (raw['currentWorkspace'] as num?)?.toInt() ??
            previewSnapshot.currentWorkspace,
      );
    } on MissingPluginException {
      return previewSnapshot;
    } on PlatformException {
      return previewSnapshot;
    }
  }

  Future<Map<String, bool>> loadShellSurfaceStates() async {
    try {
      final raw = await _channel
          .invokeMapMethod<String, Object?>('getShellSurfaceStates');
      return <String, bool>{
        'browser': raw?['browser'] as bool? ?? false,
        'terminal': raw?['terminal'] as bool? ?? false,
      };
    } on MissingPluginException {
      return const <String, bool>{'browser': false, 'terminal': false};
    } on PlatformException {
      return const <String, bool>{'browser': false, 'terminal': false};
    }
  }

  Future<bool> focusShellSurface(String id) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'focusShellSurface',
        <String, Object?>{'id': id},
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> closeShellSurface(String id) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'closeShellSurface',
        <String, Object?>{'id': id},
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<int?> getCurrentWorkspace() async {
    try {
      final workspace = await _channel.invokeMethod<int>('getCurrentWorkspace');
      if (workspace != null && workspace >= 1 && workspace <= 4) {
        return workspace;
      }
    } on MissingPluginException {
      // Preview mode has no authoritative NativeShell workspace.
    } on PlatformException {
      // Preserve the last presentation state if NativeShell is unavailable.
    }
    return null;
  }

  Future<bool> switchWorkspace(int workspace) async {
    if (workspace < 1 || workspace > 4) return false;
    try {
      final applied = await _channel.invokeMethod<int>(
        'switchWorkspace',
        <String, Object?>{'workspace': workspace},
      );
      return applied == workspace;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> launchApp(String id) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'launchApp',
        <String, Object?>{'id': id},
      );
      return result ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> setVolume(double value) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'setVolume',
        <String, Object?>{'value': value},
      );
      return result ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> setBrightness(double value) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'setBrightness',
        <String, Object?>{'value': value},
      );
      return result ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<Map<String, Object?>> getBridgeInfo() async {
    try {
      final raw =
          await _channel.invokeMapMethod<String, Object?>('getBridgeInfo');
      if (raw != null) return raw;
    } on MissingPluginException {
      // Preview fallback is intentional when the native host is unavailable.
    } on PlatformException {
      // Preview fallback is intentional when the native bridge rejects a call.
    }
    return const <String, Object?>{
      'schema': 21,
      'version': 'v21-preview',
      'bridge_type': 'PreviewFallback',
      'brokerConnected': false,
      'brokerState': 'degraded',
      'channel': 'cloudos/native/v19',
      'arbitrary_command_api': false,
      'shell_surface_lifecycle': false,
      'shell_workspace_control': false,
      'files_capability_actions': false,
    };
  }

  static const previewSnapshot = CloudOSPreviewData.snapshot;
  static const previewApps = CloudOSPreviewData.apps;
  static const previewFiles = CloudOSPreviewData.files;
  static const previewNotifications = CloudOSPreviewData.notifications;
}
