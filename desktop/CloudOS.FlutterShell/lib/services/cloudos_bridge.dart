import 'package:flutter/services.dart';

import '../models/shell_models.dart';
import 'bridge/cloud_app_mapper.dart';
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

  Future<CloudSystemSnapshot> loadSystemSnapshot() async {
    try {
      final raw =
          await _channel.invokeMapMethod<String, Object?>('getSystemSnapshot');
      if (raw == null) return previewSnapshot;
      return CloudSystemSnapshot(
        deviceName:
            raw['deviceName'] as String? ?? previewSnapshot.deviceName,
        networkName:
            raw['networkName'] as String? ?? previewSnapshot.networkName,
        volume:
            (raw['volume'] as num?)?.toDouble() ?? previewSnapshot.volume,
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
    };
  }

  static const previewSnapshot = CloudOSPreviewData.snapshot;
  static const previewApps = CloudOSPreviewData.apps;
  static const previewFiles = CloudOSPreviewData.files;
  static const previewNotifications = CloudOSPreviewData.notifications;
}
