import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/shell_models.dart';
import '../models/system_settings_models.dart';
import '../models/desktop_services_models.dart';
import '../models/recovery_models.dart';
import '../models/wsl_distro.dart';
import '../shell/window_manager/cloud_window.dart';
import 'bridge/cloud_app_mapper.dart';
import 'bridge/cloud_file_mapper.dart';
import 'bridge/cloud_notification_mapper.dart';
import 'bridge/cloudos_preview_data.dart';

export '../models/system_settings_models.dart';
export '../models/desktop_services_models.dart';
export '../models/recovery_models.dart';
export '../models/wsl_distro.dart';
export '../shell/window_manager/cloud_window.dart';

class TerminalDataEvent {
  const TerminalDataEvent({required this.sessionId, required this.data});

  final String sessionId;
  final String data;
}

class TerminalExitEvent {
  const TerminalExitEvent({required this.sessionId, required this.exitCode});

  final String sessionId;
  final int exitCode;
}

class DisplayChangeEvent {
  const DisplayChangeEvent({this.width, this.height, this.dpi});
  final double? width;
  final double? height;
  final int? dpi;
}

class FileOperationProgressEvent {
  const FileOperationProgressEvent({
    required this.jobId,
    required this.status,
    required this.filesCompleted,
    required this.filesTotal,
    required this.bytesCompleted,
    required this.bytesTotal,
    required this.currentItem,
    this.errorMessage,
  });

  final String jobId;
  final String status;
  final int filesCompleted;
  final int filesTotal;
  final int bytesCompleted;
  final int bytesTotal;
  final String currentItem;
  final String? errorMessage;
}

class CloudDriveInfo {
  const CloudDriveInfo({
    required this.mountPath,
    required this.label,
    required this.driveType,
    required this.totalBytes,
    required this.freeBytes,
    required this.totalFormatted,
    required this.freeFormatted,
    required this.entryId,
  });

  final String mountPath;
  final String label;
  final String driveType;
  final int totalBytes;
  final int freeBytes;
  final String totalFormatted;
  final String freeFormatted;
  final String entryId;

  factory CloudDriveInfo.fromMap(Map<Object?, Object?> map) {
    return CloudDriveInfo(
      mountPath: map['mountPath'] as String? ?? '',
      label: map['label'] as String? ?? '',
      driveType: map['driveType'] as String? ?? 'fixed',
      totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
      freeBytes: (map['freeBytes'] as num?)?.toInt() ?? 0,
      totalFormatted: map['totalFormatted'] as String? ?? '',
      freeFormatted: map['freeFormatted'] as String? ?? '',
      entryId: map['entryId'] as String? ?? '',
    );
  }
}

class PerformanceProfileInfo {
  const PerformanceProfileInfo({
    this.profile = 'balanced',
    this.totalRamMb = 0,
    this.freeRamMb = 0,
    this.memoryLoadPercent = 0,
    this.cpuCores = 0,
    this.onBattery = false,
    this.batteryPercent = -1,
    this.isLowEndHardware = false,
  });

  final String profile;
  final int totalRamMb;
  final int freeRamMb;
  final int memoryLoadPercent;
  final int cpuCores;
  final bool onBattery;
  final int batteryPercent;
  final bool isLowEndHardware;

  bool get isEconomy => profile == 'economy';

  static const defaultBalanced = PerformanceProfileInfo();

  factory PerformanceProfileInfo.fromMap(Map<Object?, Object?> map) {
    return PerformanceProfileInfo(
      profile: map['profile'] as String? ?? 'balanced',
      totalRamMb: (map['totalRamMb'] as num?)?.toInt() ?? 0,
      freeRamMb: (map['freeRamMb'] as num?)?.toInt() ?? 0,
      memoryLoadPercent: (map['memoryLoadPercent'] as num?)?.toInt() ?? 0,
      cpuCores: (map['cpuCores'] as num?)?.toInt() ?? 0,
      onBattery: map['onBattery'] as bool? ?? false,
      batteryPercent: (map['batteryPercent'] as num?)?.toInt() ?? -1,
      isLowEndHardware: map['isLowEndHardware'] as bool? ?? false,
    );
  }
}

class CloudOSBridge {
  const CloudOSBridge({
    MethodChannel channel = const MethodChannel('cloudos/native/v19'),
  }) : _channel = channel;

  final MethodChannel _channel;
  static bool _handlerInitialized = false;
  static final StreamController<TerminalDataEvent> _terminalDataController =
      StreamController<TerminalDataEvent>.broadcast();
  static final StreamController<TerminalExitEvent> _terminalExitController =
      StreamController<TerminalExitEvent>.broadcast();
  static final StreamController<DisplayChangeEvent> _displayChangeController =
      StreamController<DisplayChangeEvent>.broadcast();
  static final StreamController<FileOperationProgressEvent>
      _fileOperationProgressController =
      StreamController<FileOperationProgressEvent>.broadcast();

  Stream<TerminalDataEvent> get terminalDataStream {
    _ensureChannelHandler();
    return _terminalDataController.stream;
  }

  Stream<TerminalExitEvent> get terminalExitStream {
    _ensureChannelHandler();
    return _terminalExitController.stream;
  }

  Stream<DisplayChangeEvent> get onDisplayChanged {
    _ensureChannelHandler();
    return _displayChangeController.stream;
  }

  Stream<FileOperationProgressEvent> get onFileOperationProgress {
    _ensureChannelHandler();
    return _fileOperationProgressController.stream;
  }

  void _ensureChannelHandler() {
    if (_handlerInitialized) return;
    _handlerInitialized = true;
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments;
      if (call.method == 'terminal.onData' && args is Map) {
        _terminalDataController.add(
          TerminalDataEvent(
            sessionId: args['sessionId'] as String? ?? '',
            data: args['data'] as String? ?? '',
          ),
        );
      } else if (call.method == 'terminal.onExit' && args is Map) {
        _terminalExitController.add(
          TerminalExitEvent(
            sessionId: args['sessionId'] as String? ?? '',
            exitCode: (args['exitCode'] as num?)?.toInt() ?? 0,
          ),
        );
      } else if (call.method == 'display.changed' || call.method == 'dpi.changed') {
        final m = args is Map ? args : const <Object?, Object?>{};
        _displayChangeController.add(
          DisplayChangeEvent(
            width: (m['width'] as num?)?.toDouble(),
            height: (m['height'] as num?)?.toDouble(),
            dpi: (m['dpi'] as num?)?.toInt() ?? (m['dpi_x'] as num?)?.toInt(),
          ),
        );
      } else if (call.method == 'files.onProgress' && args is Map) {
        _fileOperationProgressController.add(
          FileOperationProgressEvent(
            jobId: args['jobId'] as String? ?? '',
            status: args['status'] as String? ?? '',
            filesCompleted: (args['filesCompleted'] as num?)?.toInt() ?? 0,
            filesTotal: (args['filesTotal'] as num?)?.toInt() ?? 0,
            bytesCompleted: (args['bytesCompleted'] as num?)?.toInt() ?? 0,
            bytesTotal: (args['bytesTotal'] as num?)?.toInt() ?? 0,
            currentItem: args['currentItem'] as String? ?? '',
            errorMessage: args['errorMessage'] as String?,
          ),
        );
      }
    });
  }

  Future<String?> createTerminalSession({
    String shellKind = 'powershell',
    String distro = '',
    int cols = 80,
    int rows = 24,
  }) async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'terminal.createSession',
        <String, Object?>{
          'shellKind': shellKind,
          'distro': distro,
          'cols': cols,
          'rows': rows,
        },
      );
      return response?['sessionId'] as String?;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> writeTerminal(String sessionId, String data) async {
    return await _terminalBool('terminal.write', <String, Object?>{
      'sessionId': sessionId,
      'data': data,
    });
  }

  Future<bool> resizeTerminal(String sessionId, int cols, int rows) async {
    return await _terminalBool('terminal.resize', <String, Object?>{
      'sessionId': sessionId,
      'cols': cols,
      'rows': rows,
    });
  }

  Future<bool> signalTerminal(String sessionId, String signal) async {
    return await _terminalBool('terminal.signal', <String, Object?>{
      'sessionId': sessionId,
      'signal': signal,
    });
  }

  Future<bool> closeTerminal(String sessionId) async {
    return await _terminalBool('terminal.close', <String, Object?>{
      'sessionId': sessionId,
    });
  }

  Future<bool> _terminalBool(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }


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

  Future<CloudFileItem?> createFolder(String parentEntryId, String name) async {
    if (parentEntryId.isEmpty || name.isEmpty) return null;
    try {
      final res = await _channel.invokeMapMethod<Object?, Object?>(
        'createFolder',
        <String, Object?>{
          'parentEntryId': parentEntryId,
          'name': name,
        },
      );
      if (res == null) return null;
      return cloudFileFromNative(res);
    } catch (_) {
      return null;
    }
  }

  Future<CloudFileItem?> renameFile(String entryId, String newName) async {
    if (entryId.isEmpty || newName.isEmpty) return null;
    try {
      final res = await _channel.invokeMapMethod<Object?, Object?>(
        'renameFile',
        <String, Object?>{
          'entryId': entryId,
          'newName': newName,
        },
      );
      if (res == null) return null;
      return cloudFileFromNative(res);
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> deleteFiles(List<String> entryIds, {bool permanent = false}) async {
    if (entryIds.isEmpty) return const <String>[];
    try {
      final res = await _channel.invokeListMethod<String>(
        'deleteFiles',
        <String, Object?>{
          'entryIds': entryIds,
          'permanent': permanent,
        },
      );
      return res ?? const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  Future<String?> copyFiles(List<String> sourceEntryIds, String destinationEntryId) async {
    if (sourceEntryIds.isEmpty || destinationEntryId.isEmpty) return null;
    try {
      return await _channel.invokeMethod<String>(
        'copyFiles',
        <String, Object?>{
          'sourceEntryIds': sourceEntryIds,
          'destinationEntryId': destinationEntryId,
        },
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> moveFiles(List<String> sourceEntryIds, String destinationEntryId) async {
    if (sourceEntryIds.isEmpty || destinationEntryId.isEmpty) return null;
    try {
      return await _channel.invokeMethod<String>(
        'moveFiles',
        <String, Object?>{
          'sourceEntryIds': sourceEntryIds,
          'destinationEntryId': destinationEntryId,
        },
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> cancelFileOperation(String jobId) async {
    if (jobId.isEmpty) return false;
    try {
      final res = await _channel.invokeMethod<bool>(
        'cancelFileOperation',
        <String, Object?>{'jobId': jobId},
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<CloudDriveInfo>> listDrives() async {
    try {
      final res = await _channel.invokeListMethod<Map<Object?, Object?>>('listDrives');
      if (res == null) return const <CloudDriveInfo>[];
      return res.map((m) => CloudDriveInfo.fromMap(m)).toList(growable: false);
    } catch (_) {
      return const <CloudDriveInfo>[];
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
        defaultDistro: raw['defaultDistro'] as String? ?? '',
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

  Future<PerformanceProfileInfo?> tryLoadPerformanceProfile() async {
    try {
      final raw =
          await _channel.invokeMapMethod<Object?, Object?>('getPerformanceProfile');
      if (raw == null) return null;
      return PerformanceProfileInfo.fromMap(raw);
    } on MissingPluginException {
      return PerformanceProfileInfo.defaultBalanced;
    } on PlatformException {
      return null;
    }
  }

  Future<PerformanceProfileInfo> loadPerformanceProfile() async {
    return await tryLoadPerformanceProfile() ?? PerformanceProfileInfo.defaultBalanced;
  }

  Future<bool> setPerformanceProfile(String profile) async {
    try {
      return await _channel.invokeMethod<bool>(
            'setPerformanceProfile',
            <String, Object?>{'profile': profile},
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
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

  Future<bool> openWindowsSettings([String uri = 'ms-settings:']) async {
    try {
      await Process.run('cmd.exe', ['/c', 'start', '', uri]);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> restartWsl() async {
    try {
      await Process.run('cmd.exe', ['/c', 'wsl --shutdown']);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openWindowsApp(String id) async {
    try {
      final target = id.startsWith('windows:') ? id.substring('windows:'.length) : id;
      if (target == 'vscode' || target == 'code') {
        await Process.run('cmd.exe', ['/c', 'start', '', 'code']);
      } else if (target == 'explorer') {
        await Process.run('cmd.exe', ['/c', 'start', '', 'explorer.exe']);
      } else if (target == 'calc') {
        await Process.run('cmd.exe', ['/c', 'start', '', 'calc.exe']);
      } else if (target == 'taskmgr') {
        await Process.run('cmd.exe', ['/c', 'start', '', 'taskmgr.exe']);
      } else {
        await Process.run('cmd.exe', ['/c', 'start', '', target]);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> launchApp(String id) async {
    if (id.startsWith('windows:settings:')) {
      final res = await launchAppStructured(id);
      return res.launched;
    }
    if (id.startsWith('windows:') && id != 'windows:notepad') {
      return await openWindowsApp(id);
    }
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

  Future<AppLaunchStatus> launchAppStructured(String id) async {
    if (id.startsWith('windows:settings:')) {
      final sub = id.substring('windows:settings:'.length);
      final msUri = switch (sub) {
        'wifi' || 'network' => 'ms-settings:network-wifi',
        'display' => 'ms-settings:display',
        'sound' => 'ms-settings:sound',
        'bluetooth' => 'ms-settings:bluetooth',
        'power' => 'ms-settings:powersleep',
        'storage' => 'ms-settings:storagesense',
        _ => 'ms-settings:$sub',
      };
      await openWindowsSettings(msUri);
      return AppLaunchStatus(
        id: id,
        status: 'running',
        launched: true,
        platform: 'windows',
        target: msUri,
        message: 'Configurações do Windows abertas com sucesso',
      );
    }
    if (id.startsWith('windows:') && id != 'windows:notepad') {
      final ok = await openWindowsApp(id);
      return AppLaunchStatus(
        id: id,
        status: ok ? 'running' : 'failed',
        launched: ok,
        platform: 'windows',
        target: id,
        message: ok ? 'Aplicativo iniciado no Windows' : 'Falha ao iniciar aplicativo',
      );
    }
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'launchAppStructured',
        <String, Object?>{'id': id},
      );
      if (raw == null) {
        return AppLaunchStatus(
          id: id,
          status: 'failed',
          launched: false,
          platform: 'unknown',
          target: id,
          message: 'Sem resposta do broker',
        );
      }
      return AppLaunchStatus.fromMap(raw);
    } on MissingPluginException {
      return AppLaunchStatus(
        id: id,
        status: 'running',
        launched: true,
        platform: 'preview',
        target: id,
        message: 'Modo preview',
      );
    } on PlatformException catch (e) {
      return AppLaunchStatus(
        id: id,
        status: 'failed',
        launched: false,
        platform: 'unknown',
        target: id,
        message: e.message ?? 'Falha na inicialização',
      );
    }
  }

  Future<List<WslDistroInfo>> listWslDistros() async {
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>('wsl.listDistros');
      if (raw == null) return const <WslDistroInfo>[];
      final distrosRaw = raw['distros'] as List<Object?>? ?? const [];
      return distrosRaw
          .whereType<Map<Object?, Object?>>()
          .map(WslDistroInfo.fromMap)
          .toList(growable: false);
    } on MissingPluginException {
      return const <WslDistroInfo>[];
    } on PlatformException {
      return const <WslDistroInfo>[];
    }
  }

  Future<PathTranslation?> translatePath(
    String path, {
    String target = 'linux',
    String distro = '',
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'path.translate',
        <String, Object?>{
          'path': path,
          'target': target,
          'distro': distro,
        },
      );
      if (raw == null) return null;
      return PathTranslation.fromMap(raw);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<List<MountPoint>> getMountPoints() async {
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('system.getMountPoints');
      if (raw == null) return const <MountPoint>[];
      return raw.map(MountPoint.fromMap).toList(growable: false);
    } on MissingPluginException {
      return const <MountPoint>[];
    } on PlatformException {
      return const <MountPoint>[];
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

  Future<CloudWindowSnapshot?> tryLoadWindowSnapshot() async {
    try {
      final jsonStr = await _channel.invokeMethod<String>('window.getSnapshot');
      if (jsonStr == null || jsonStr.isEmpty) return null;
      return CloudWindowSnapshot.fromJsonString(jsonStr);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> focusWindow(int hwnd) async {
    try {
      final res = await _channel.invokeMethod<bool>('window.focus', <String, Object?>{
        'hwnd': hwnd,
      });
      return res ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> minimizeWindow(int hwnd) async {
    try {
      final res = await _channel.invokeMethod<bool>('window.minimize', <String, Object?>{
        'hwnd': hwnd,
      });
      return res ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> maximizeWindow(int hwnd) async {
    try {
      final res = await _channel.invokeMethod<bool>('window.maximize', <String, Object?>{
        'hwnd': hwnd,
      });
      return res ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> restoreWindow(int hwnd) async {
    try {
      final res = await _channel.invokeMethod<bool>('window.restore', <String, Object?>{
        'hwnd': hwnd,
      });
      return res ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> closeWindow(int hwnd) async {
    try {
      final res = await _channel.invokeMethod<bool>('window.close', <String, Object?>{
        'hwnd': hwnd,
      });
      return res ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> setWindowBounds(int hwnd, int x, int y, int width, int height) async {
    try {
      final res = await _channel.invokeMethod<bool>('window.setBounds', <String, Object?>{
        'hwnd': hwnd,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      });
      return res ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> snapWindow(int hwnd, String target) async {
    try {
      final res = await _channel.invokeMethod<bool>('window.snap', <String, Object?>{
        'hwnd': hwnd,
        'snap': target,
        'target': target,
      });
      return res ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> moveWindowToWorkspace(int hwnd, int workspace) async {
    try {
      final res = await _channel.invokeMethod<bool>('window.moveToWorkspace', <String, Object?>{
        'hwnd': hwnd,
        'workspace': workspace,
      });
      return res ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> setWindowFullscreen(int hwnd, bool fullscreen) async {
    try {
      final res = await _channel.invokeMethod<bool>('window.setFullscreen', <String, Object?>{
        'hwnd': hwnd,
        'fullscreen': fullscreen,
      });
      return res ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<List<CloudMonitorRecord>> listMonitors() async {
    try {
      final jsonStr = await _channel.invokeMethod<String>('monitor.list');
      if (jsonStr == null || jsonStr.isEmpty) return const <CloudMonitorRecord>[];
      final snapshot = CloudWindowSnapshot.fromJsonString(jsonStr);
      return snapshot.monitors;
    } on MissingPluginException {
      return const <CloudMonitorRecord>[];
    } on PlatformException {
      return const <CloudMonitorRecord>[];
    }
  }

  Future<Map<String, dynamic>?> invokeBrokerRpc(
    String method, [
    Map<String, dynamic>? payload,
  ]) async {
    try {
      final jsonStr = await _channel.invokeMethod<String>(
        'broker.invokeRpc',
        <String, Object?>{
          'method': method,
          'payload': payload != null ? jsonEncode(payload) : '',
        },
      );
      if (jsonStr == null || jsonStr.isEmpty) return null;
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<List<CloudDisplayMonitor>> getDisplayMonitors() async {
    final res = await invokeBrokerRpc('display.listMonitors');
    if (res == null || res['monitors'] is! List) return const [];
    return (res['monitors'] as List)
        .whereType<Map>()
        .map((m) => CloudDisplayMonitor.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<List<CloudDisplayMode>> getDisplayModes([
    String deviceName = r'\\.\DISPLAY1',
  ]) async {
    final res = await invokeBrokerRpc('display.listSupportedModes', {
      'deviceName': deviceName,
    });
    if (res == null || res['modes'] is! List) return const [];
    return (res['modes'] as List)
        .whereType<Map>()
        .map((m) => CloudDisplayMode.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<bool> setDisplayMode({
    required String deviceName,
    required int width,
    required int height,
    int frequency = 60,
    int orientation = 0,
  }) async {
    final res = await invokeBrokerRpc('display.setMode', {
      'deviceName': deviceName,
      'width': width,
      'height': height,
      'frequency': frequency,
      'orientation': orientation,
    });
    return res != null && (res['success'] as bool? ?? false);
  }

  Future<bool> restoreDisplayMode() async {
    final res = await invokeBrokerRpc('display.restore');
    return res != null && (res['success'] as bool? ?? false);
  }

  Future<CloudAudioState> getAudioState() async {
    final res = await invokeBrokerRpc('audio.getState');
    if (res == null || res['audio'] is! Map) return const CloudAudioState();
    return CloudAudioState.fromMap(Map<String, dynamic>.from(res['audio'] as Map));
  }

  Future<bool> setMasterVolume(double volume) async {
    final res = await invokeBrokerRpc('audio.setVolume', {'volume': volume});
    unawaited(setVolume(volume));
    return res != null && (res['success'] as bool? ?? false);
  }

  Future<bool> setMasterMute(bool muted) async {
    final res = await invokeBrokerRpc('audio.setMute', {'muted': muted});
    return res != null && (res['success'] as bool? ?? false);
  }

  Future<CloudPowerStatus> getPowerStatus() async {
    final res = await invokeBrokerRpc('power.getStatus');
    if (res == null || res['power'] is! Map) return const CloudPowerStatus();
    return CloudPowerStatus.fromMap(Map<String, dynamic>.from(res['power'] as Map));
  }

  Future<List<CloudNetworkInterface>> getNetworkInterfaces() async {
    final res = await invokeBrokerRpc('network.getInterfaces');
    if (res == null || res['interfaces'] is! List) return const [];
    return (res['interfaces'] as List)
        .whereType<Map>()
        .map((m) => CloudNetworkInterface.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<List<CloudWifiNetwork>> getWifiNetworks() async {
    final res = await invokeBrokerRpc('network.getWifi');
    if (res == null || res['networks'] is! List) return const [];
    return (res['networks'] as List)
        .whereType<Map>()
        .map((m) => CloudWifiNetwork.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<CloudBluetoothStatus> getBluetoothStatus() async {
    final res = await invokeBrokerRpc('bluetooth.getStatus');
    if (res == null || res['bluetooth'] is! Map) return const CloudBluetoothStatus();
    return CloudBluetoothStatus.fromMap(Map<String, dynamic>.from(res['bluetooth'] as Map));
  }

  Future<List<CloudStorageDrive>> getStorageDrives() async {
    final res = await invokeBrokerRpc('storage.getDrives');
    if (res == null || res['drives'] is! List) return const [];
    return (res['drives'] as List)
        .whereType<Map>()
        .map((m) => CloudStorageDrive.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<CloudPersonalizationSettings> getPersonalizationSettings() async {
    final res = await invokeBrokerRpc('personalization.get');
    if (res == null || res['personalization'] is! Map) return const CloudPersonalizationSettings();
    return CloudPersonalizationSettings.fromMap(Map<String, dynamic>.from(res['personalization'] as Map));
  }

  Future<bool> setPersonalizationSettings(CloudPersonalizationSettings settings) async {
    final res = await invokeBrokerRpc('personalization.set', {
      'personalization': settings.toMap(),
    });
    return res != null && (res['success'] as bool? ?? false);
  }

  Future<CloudDateTimeLocale> getDateTimeLocale() async {
    final res = await invokeBrokerRpc('datetime.get');
    if (res == null || res['datetime'] is! Map) {
      return CloudDateTimeLocale(
        localTime: DateTime.now().toIso8601String(),
        timezoneName: 'Local',
        biasMinutes: 0,
        localeName: 'pt-BR',
      );
    }
    return CloudDateTimeLocale.fromMap(Map<String, dynamic>.from(res['datetime'] as Map));
  }

  Future<CloudQuickSettingsState> getQuickSettingsState() async {
    final res = await invokeBrokerRpc('quicksettings.getState');
    if (res == null) {
      return const CloudQuickSettingsState(
        audio: CloudAudioState(),
        power: CloudPowerStatus(),
        bluetooth: CloudBluetoothStatus(),
        personalization: CloudPersonalizationSettings(),
        performanceProfile: 'balanced',
      );
    }
    return CloudQuickSettingsState.fromMap(res);
  }

  // --- CLIPBOARD (ETAPA 6) ---
  Future<List<CloudClipboardItem>> getClipboardHistory([int limit = 20]) async {
    final res = await invokeBrokerRpc('clipboard.getHistory', {'limit': limit});
    if (res == null || res['items'] is! List) return const [];
    return (res['items'] as List)
        .whereType<Map>()
        .map((m) => CloudClipboardItem.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<String> getClipboardText() async {
    final res = await invokeBrokerRpc('clipboard.getText');
    return res != null && res['text'] is String ? res['text'] as String : '';
  }

  Future<bool> setClipboardText(String text) async {
    final res = await invokeBrokerRpc('clipboard.setText', {'text': text});
    return res != null && (res['success'] as bool? ?? false);
  }

  Future<bool> clearClipboard() async {
    final res = await invokeBrokerRpc('clipboard.clear');
    return res != null && (res['success'] as bool? ?? false);
  }

  // --- OPEN WITH / FILE ASSOCIATIONS (ETAPA 6) ---
  Future<bool> openFileWith({
    required String path,
    String? appId,
  }) async {
    final res = await invokeBrokerRpc('files.openWith', {
      'path': path,
      if (appId != null && appId.isNotEmpty) 'app_id': appId,
    });
    return res != null && (res['success'] as bool? ?? false);
  }

  Future<List<CloudFileAssociation>> getFileAssociations() async {
    final res = await invokeBrokerRpc('files.getAssociations');
    if (res == null || res['associations'] is! List) return const [];
    return (res['associations'] as List)
        .whereType<Map>()
        .map((m) => CloudFileAssociation.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<bool> showOpenWithDialog(String path) async {
    final res = await invokeBrokerRpc('files.showOpenWithDialog', {
      'path': path,
    });
    return res != null && (res['success'] as bool? ?? false);
  }

  // --- DESKTOP NOTIFICATIONS (ETAPA 6) ---
  Future<int> postDesktopNotification({
    required String title,
    required String message,
    String severity = 'info',
    String appId = '',
  }) async {
    final res = await invokeBrokerRpc('notifications.post', {
      'title': title,
      'message': message,
      'severity': severity,
      'app_id': appId,
    });
    return (res != null && res['id'] is num) ? (res['id'] as num).toInt() : 0;
  }

  Future<List<CloudDesktopNotification>> listDesktopNotifications() async {
    final res = await invokeBrokerRpc('notifications.list');
    if (res == null || res['notifications'] is! List) return const [];
    return (res['notifications'] as List)
        .whereType<Map>()
        .map((m) => CloudDesktopNotification.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<bool> dismissDesktopNotification(int id) async {
    final res = await invokeBrokerRpc('notifications.dismiss', {'id': id});
    return res != null && (res['success'] as bool? ?? false);
  }

  Future<bool> clearDesktopNotifications() async {
    final res = await invokeBrokerRpc('notifications.clear');
    return res != null && (res['success'] as bool? ?? false);
  }

  Future<bool> markDesktopNotificationRead(int id) async {
    final res = await invokeBrokerRpc('notifications.markRead', {'id': id});
    return res != null && (res['success'] as bool? ?? false);
  }

  Future<bool> markAllDesktopNotificationsRead() async {
    final res = await invokeBrokerRpc('notifications.markAllRead');
    return res != null && (res['success'] as bool? ?? false);
  }

  // --- SYSTEM ACTIONS (ETAPA 6) ---
  Future<bool> lockSystem() async {
    final res = await invokeBrokerRpc('system.lock');
    return res != null && (res['success'] as bool? ?? false);
  }

  // --- RECOVERY & LIFECYCLE (ETAPA 7) ---
  Future<CloudOSRecoveryStatus?> getRecoveryStatus() async {
    final res = await invokeBrokerRpc('recovery.getStatus');
    if (res == null) return null;
    return CloudOSRecoveryStatus.fromMap(res);
  }

  Future<bool> enterSafeMode() async {
    final res = await invokeBrokerRpc('recovery.enterSafeMode');
    return res != null && (res['success'] as bool? ?? false);
  }

  Future<bool> requestShutdown() async {
    final res = await invokeBrokerRpc('system.requestShutdown');
    return res != null && (res['success'] as bool? ?? false);
  }

  // --- HARDENING & CAPABILITIES (ETAPA 8) ---
  Future<CloudOSSystemCapabilities?> getSystemCapabilities() async {
    final res = await invokeBrokerRpc('system.getCapabilities');
    if (res == null) return null;
    return CloudOSSystemCapabilities.fromMap(res);
  }

  Future<CloudHardwareMetrics?> getHardwareMetrics() async {
    final res = await invokeBrokerRpc('performance.getMetrics');
    if (res == null) return null;
    return CloudHardwareMetrics.fromMap(res);
  }

  // --- STARTUP & LIFECYCLE (ETAPA 10) ---
  Future<CloudStartupStatus> getStartupStatus() async {
    final res = await invokeBrokerRpc('startup.getStatus');
    if (res == null) return const CloudStartupStatus();
    return CloudStartupStatus.fromMap(res);
  }

  Future<bool> setStartupEnabled(bool enabled) async {
    final res = await invokeBrokerRpc('startup.setEnabled', {'enabled': enabled});
    return res != null && (res['success'] as bool? ?? false);
  }

  Future<bool> closeCloudOS() async {
    final res = await invokeBrokerRpc('system.closeCloudOS');
    return res != null && (res['success'] as bool? ?? false);
  }

  // --- SHELL REPLACEMENT & RECOVERY (ETAPA 11) ---
  Future<CloudShellStatus> getShellStatus() async {
    final res = await invokeBrokerRpc('shell.getStatus');
    if (res == null) return const CloudShellStatus();
    return CloudShellStatus.fromMap(res);
  }

  Future<bool> restoreExplorerShell() async {
    final res = await invokeBrokerRpc('shell.restoreExplorer');
    return res != null && (res['success'] as bool? ?? false);
  }

  Future<bool> setShellMode(String mode, {bool gate0Override = false}) async {
    final res = await invokeBrokerRpc('shell.setShellMode', {
      'mode': mode,
      'gate0_override': gate0Override,
    });
    return res != null && (res['success'] as bool? ?? false);
  }

  Future<bool> createShellBackup() async {
    final res = await invokeBrokerRpc('shell.createBackup');
    return res != null && (res['success'] as bool? ?? false);
  }

  Future<Map<String, Object?>> getBridgeInfo() async {
    try {
      final raw =
          await _channel.invokeMapMethod<String, Object?>('getBridgeInfo');
      if (raw != null) return raw;
      return degradedBridgeInfo;
    } on MissingPluginException {
      return previewBridgeInfo;
    } on PlatformException {
      return degradedBridgeInfo;
    }
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

  static const previewBridgeInfo = <String, Object?>{
    'schema': 21,
    'version': 'v21-preview',
    'bridge_type': 'PreviewFallback',
    'brokerConnected': false,
    'brokerState': 'preview',
    'channel': 'cloudos/native/v19',
    'arbitrary_command_api': false,
    'shell_surface_lifecycle': false,
    'shell_workspace_control': false,
    'shell_notification_authority': false,
    'files_capability_actions': false,
  };

  static const degradedBridgeInfo = <String, Object?>{
    'schema': 21,
    'version': 'v21-degraded',
    'bridge_type': 'NativeBridgeUnavailable',
    'brokerConnected': false,
    'brokerState': 'degraded',
    'channel': 'cloudos/native/v19',
    'arbitrary_command_api': false,
    'shell_surface_lifecycle': false,
    'shell_workspace_control': false,
    'shell_notification_authority': false,
    'files_capability_actions': false,
  };

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
