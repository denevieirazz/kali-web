import 'package:flutter/services.dart';

import '../models/shell_models.dart';
import 'bridge/cloud_app_mapper.dart';
import 'bridge/cloud_file_mapper.dart';
import 'bridge/cloud_notification_mapper.dart';
import 'bridge/cloudos_preview_data.dart';

class CloudOSBridge {
  const CloudOSBridge({
    MethodChannel channel = const MethodChannel('cloudos/native/v19'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<List<CloudApp>?> tryLoadApps() async {
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('getApps');
      if (raw == null || raw.isEmpty) return null;
      return raw.map(cloudAppFromNative).toList(growable: false);
    } on MissingPluginException {
      return previewApps;
    } on PlatformException {
      return null;
    }
  }

  Future<List<CloudApp>> loadApps() async {
    return await tryLoadApps() ?? const <CloudApp>[];
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

  Future<CloudSystemSnapshot?> tryLoadSystemSnapshot() async {
    try {
      final raw =
          await _channel.invokeMapMethod<String, Object?>('getSystemSnapshot');
      if (raw == null) return null;
      return CloudSystemSnapshot(
        deviceName:
            raw['deviceName'] as String? ?? degradedSnapshot.deviceName,
        networkAvailable: raw['networkAvailable'] as bool? ??
            degradedSnapshot.networkAvailable,
        networkName:
            raw['networkName'] as String? ?? degradedSnapshot.networkName,
        volumeAvailable: raw['volumeAvailable'] as bool? ??
            degradedSnapshot.volumeAvailable,
        volume:
            (raw['volume'] as num?)?.toDouble() ?? degradedSnapshot.volume,
        brightnessAvailable: raw['brightnessAvailable'] as bool? ??
            degradedSnapshot.brightnessAvailable,
        brightness: (raw['brightness'] as num?)?.toDouble() ??
            degradedSnapshot.brightness,
        batteryAvailable: raw['batteryAvailable'] as bool? ??
            degradedSnapshot.batteryAvailable,
        batteryPercent: (raw['batteryPercent'] as num?)?.toInt() ??
            degradedSnapshot.batteryPercent,
        wslAvailable:
            raw['wslAvailable'] as bool? ?? degradedSnapshot.wslAvailable,
        distros: (raw['distros'] as List<Object?>?)
                ?.whereType<String>()
                .toList() ??
            degradedSnapshot.distros,
        currentWorkspace: (raw['currentWorkspace'] as num?)?.toInt() ??
            degradedSnapshot.currentWorkspace,
      );
    } on MissingPluginException {
      return previewSnapshot;
    } on PlatformException {
      return null;
    }
  }

  Future<CloudSystemSnapshot> loadSystemSnapshot() async {
    return await tryLoadSystemSnapshot() ?? degradedSnapshot;
  }

  Future<CloudNotificationState?> tryLoadNotificationState() async {
    try {
      final raw =
          await _channel.invokeMapMethod<Object?, Object?>('getNotificationState');
      if (raw == null) return null;
      return cloudNotificationStateFromNative(raw);
    } on MissingPluginException {
      return previewNotificationState;
    } on PlatformException {
      return null;
    }
  }

  Future<CloudNotificationState> loadNotificationState() async {
    return await tryLoadNotificationState() ?? CloudNotificationState.empty;
  }

  Future<bool> markNotificationsRead() async {
    try {
      final result = await _channel.invokeMethod<bool>('markNotificationsRead');
      return result ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> dismissNotification(String id) async {
    if (id.isEmpty) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'dismissNotification',
        <String, Object?>{'id': id},
      );
      return result ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> clearNotifications() async {
    try {
      final result = await _channel.invokeMethod<bool>('clearNotifications');
      return result ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<Map<String, bool>?> tryLoadShellSurfaceStates() async {
    try {
      final raw = await _channel
          .invokeMapMethod<String, Object?>('getShellSurfaceStates');
      if (raw == null) return null;
      return <String, bool>{
        'browser': raw['browser'] as bool? ?? false,
        'terminal': raw['terminal'] as bool? ?? false,
      };
    } on MissingPluginException {
      return const <String, bool>{'browser': false, 'terminal': false};
    } on PlatformException {
      return null;
    }
  }

  Future<Map<String, bool>> loadShellSurfaceStates() async {
    return await tryLoadShellSurfaceStates() ??
        const <String, bool>{'browser': false, 'terminal': false};
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
      'shell_notification_authority': false,
      'files_capability_actions': false,
    };
  }

  static const previewSnapshot = CloudOSPreviewData.snapshot;
  static const degradedSnapshot = CloudSystemSnapshot(
    deviceName: 'CloudOS Desktop',
    networkAvailable: false,
    networkName: 'Indisponível',
    volumeAvailable: false,
    volume: 0,
    brightnessAvailable: false,
    brightness: 0,
    batteryAvailable: false,
    batteryPercent: 0,
    wslAvailable: false,
    distros: <String>[],
    currentWorkspace: 1,
  );
  static const previewApps = CloudOSPreviewData.apps;
  static const previewFiles = CloudOSPreviewData.files;
  static const previewNotifications = CloudOSPreviewData.notifications;

  static CloudNotificationState get previewNotificationState =>
      CloudNotificationState(
        revision: 0,
        unreadCount: previewNotifications.length,
        items: previewNotifications,
      );
}
