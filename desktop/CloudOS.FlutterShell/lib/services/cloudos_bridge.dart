import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/file_models.dart';
import '../models/shell_models.dart' hide CloudFileItem;

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

class CloudOSBridgeException implements Exception {
  const CloudOSBridgeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message.isEmpty ? code : '$code: $message';
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

  Stream<TerminalDataEvent> get terminalDataStream {
    _ensureChannelHandler();
    return _terminalDataController.stream;
  }

  Stream<TerminalExitEvent> get terminalExitStream {
    _ensureChannelHandler();
    return _terminalExitController.stream;
  }

  void _ensureChannelHandler() {
    if (_handlerInitialized) return;
    _handlerInitialized = true;
    _channel.setMethodCallHandler((call) async {
      final method = call.method;
      final args = call.arguments;

      if (method == 'terminal.onData' && args is Map) {
        final sid = args['sessionId'] as String? ?? '';
        final data = args['data'] as String? ?? '';
        _terminalDataController.add(TerminalDataEvent(sessionId: sid, data: data));
      } else if (method == 'terminal.onExit' && args is Map) {
        final sid = args['sessionId'] as String? ?? '';
        final code = (args['exitCode'] as num?)?.toInt() ?? 0;
        _terminalExitController.add(TerminalExitEvent(sessionId: sid, exitCode: code));
      }
    });
  }

  Future<List<CloudApp>> loadApps() async {
    try {
      final payload = await invokeBrokerRpc(
        'apps.list',
        const <String, Object?>{},
      );
      final raw = payload['apps'];
      if (raw is! List<Object?>) return const <CloudApp>[];
      return raw
          .whereType<Map<String, Object?>>()
          .map((entry) => _appFromNative(entry))
          .toList(growable: false);
    } on CloudOSBridgeException {
      return const <CloudApp>[];
    }
  }

  Future<CloudSystemSnapshot> loadSystemSnapshot() async {
    try {
      final raw = await invokeBrokerRpc(
        'system.snapshot',
        const <String, Object?>{},
      );
      return CloudSystemSnapshot(
        deviceName:
            raw['deviceName'] as String? ?? unavailableSnapshot.deviceName,
        networkName:
            raw['networkName'] as String? ?? unavailableSnapshot.networkName,
        volume:
            (raw['volume'] as num?)?.toDouble() ?? unavailableSnapshot.volume,
        brightness:
            (raw['brightness'] as num?)?.toDouble() ??
            unavailableSnapshot.brightness,
        batteryPercent:
            (raw['batteryPercent'] as num?)?.toInt() ??
            unavailableSnapshot.batteryPercent,
        wslAvailable: raw['wslAvailable'] as bool? ?? false,
        distros:
            (raw['distros'] as List<Object?>?)?.whereType<String>().toList() ??
            const <String>[],
        defaultDistro: raw['defaultDistro'] as String? ?? '',
        // Workspace belongs to WindowManager + Session V3. Older Brokers may
        // still send this field, but the shell does not use it as authority.
        currentWorkspace: (raw['currentWorkspace'] as num?)?.toInt() ?? 0,
        batteryAvailable: raw['batteryAvailable'] as bool? ?? false,
        networkAvailable: raw['networkAvailable'] as bool? ?? false,
        volumeAvailable: raw['volumeAvailable'] as bool? ?? false,
        brightnessAvailable: raw['brightnessAvailable'] as bool? ?? false,
      );
    } on CloudOSBridgeException {
      return unavailableSnapshot;
    }
  }

  Future<bool> launchApp(String id) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'launchApp',
        <String, Object?>{'id': id},
      );
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
        <String, Object?>{'value': value},
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
        <String, Object?>{'value': value},
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
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'getBridgeInfo',
      );
      if (raw != null) return raw;
    } on MissingPluginException {
      // The native runner is not registered in this process.
    } on PlatformException {
      // The native runner rejected or could not service the request.
    }
    return const <String, Object?>{
      'schema': 23,
      'version': 'unavailable',
      'bridge_type': 'Unavailable',
      'nativeBridgeAvailable': false,
      'brokerConnected': false,
      'brokerState': 'unavailable',
      'channel': 'cloudos/native/v19',
      'eventChannel': 'cloudos/native/events/v23',
      'dedicatedEventTransportAvailable': false,
      'generic_broker_rpc_restricted': true,
      'arbitrary_command_api': false,
    };
  }

  Future<bool> lockSession() async {
    try {
      final res = await _channel.invokeMethod<bool>('lockSession');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, Object?>> getSystemMetrics() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('getSystemMetrics');
      if (raw != null) return raw;
    } catch (_) {}
    return const <String, Object?>{};
  }

  // ==========================================
  // ConPTY Native Terminal Methods
  // ==========================================

  Future<String?> createTerminalSession({
    String shellKind = 'powershell',
    String distro = '',
    String workingDirectory = '',
    int cols = 80,
    int rows = 24,
  }) async {
    try {
      final res = await _channel.invokeMapMethod<String, Object?>(
        'terminal.createSession',
        <String, Object?>{
          'shellKind': shellKind,
          'distro': distro,
          'workingDirectory': workingDirectory,
          'cols': cols,
          'rows': rows,
        },
      );
      return res?['sessionId'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<bool> writeTerminal(String sessionId, String data) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        'terminal.write',
        <String, Object?>{
          'sessionId': sessionId,
          'data': data,
        },
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> resizeTerminal(String sessionId, int cols, int rows) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        'terminal.resize',
        <String, Object?>{
          'sessionId': sessionId,
          'cols': cols,
          'rows': rows,
        },
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> signalTerminal(String sessionId, String signal) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        'terminal.signal',
        <String, Object?>{
          'sessionId': sessionId,
          'signal': signal,
        },
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> closeTerminal(String sessionId) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        'terminal.close',
        <String, Object?>{
          'sessionId': sessionId,
        },
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, Object?>>> listTerminalSessions() async {
    try {
      final res = await _channel.invokeListMethod<Map<String, Object?>>(
        'terminal.listSessions',
      );
      return res ?? const <Map<String, Object?>>[];
    } catch (_) {
      return const <Map<String, Object?>>[];
    }
  }

  // ==========================================
  // V22 FileService RPC Methods
  // ==========================================

  Future<Map<String, Object?>> invokeBrokerRpc(
    String method,
    Map<String, Object?> payload,
  ) async {
    try {
      final jsonStr = await _channel.invokeMethod<String>(
        'invokeBrokerRpc',
        <String, Object?>{'method': method, 'payload': jsonEncode(payload)},
      );
      if (jsonStr == null || jsonStr.isEmpty) {
        throw const CloudOSBridgeException(
          'empty_response',
          'O broker retornou uma resposta vazia.',
        );
      }
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, Object?>) {
        if (decoded['ok'] == true &&
            decoded['payload'] is Map<String, Object?>) {
          return decoded['payload'] as Map<String, Object?>;
        }
        final error = decoded['error'];
        if (error is Map<String, Object?>) {
          throw CloudOSBridgeException(
            error['code'] as String? ?? 'broker_error',
            error['message'] as String? ?? 'O broker rejeitou a operação.',
          );
        }
      }
      throw const CloudOSBridgeException(
        'invalid_response',
        'O broker retornou JSON inválido.',
      );
    } on MissingPluginException {
      throw const CloudOSBridgeException(
        'bridge_unavailable',
        'A ponte nativa do CloudOS não está disponível.',
      );
    } on PlatformException catch (error) {
      throw CloudOSBridgeException(
        error.code,
        error.message ?? 'Falha na ponte nativa do CloudOS.',
      );
    } on FormatException {
      throw const CloudOSBridgeException(
        'invalid_json',
        'O broker retornou JSON malformado.',
      );
    }
  }

  Future<List<KnownFolderModel>> getKnownFolders() async {
    final res = await invokeBrokerRpc(
      'files.knownFolders',
      const <String, Object?>{},
    );
    if (res['folders'] is List<Object?>) {
      final list = res['folders'] as List<Object?>;
      return list
          .whereType<Map<String, Object?>>()
          .map((m) => KnownFolderModel.fromJson(m))
          .toList(growable: false);
    }
    return const <KnownFolderModel>[];
  }

  Future<List<DriveInfoModel>> getDrives() async {
    final res = await invokeBrokerRpc(
      'files.drives',
      const <String, Object?>{},
    );
    if (res['drives'] is List<Object?>) {
      final list = res['drives'] as List<Object?>;
      return list
          .whereType<Map<String, Object?>>()
          .map((m) => DriveInfoModel.fromJson(m))
          .toList(growable: false);
    }
    return const <DriveInfoModel>[];
  }

  Future<List<CloudFileItem>> listFiles(
    String path, {
    int pageSize = 200,
    String continuationToken = '',
    FileSortField sortField = FileSortField.name,
    bool ascending = true,
    bool showHidden = false,
    String searchText = '',
  }) async {
    String sf = 'name';
    if (sortField == FileSortField.size)
      sf = 'size';
    else if (sortField == FileSortField.modified)
      sf = 'modified';
    else if (sortField == FileSortField.type)
      sf = 'type';

    final res = await invokeBrokerRpc('files.list', <String, Object?>{
      'path': path,
      'pageSize': pageSize,
      'continuationToken': continuationToken,
      'sortField': sf,
      'ascending': ascending,
      'directoriesFirst': true,
      'showHidden': showHidden,
      'searchText': searchText,
    });

    if (res['items'] is List<Object?>) {
      final list = res['items'] as List<Object?>;
      return list
          .whereType<Map<String, Object?>>()
          .map((m) => CloudFileItem.fromJson(m))
          .toList(growable: false);
    }

    return const <CloudFileItem>[];
  }

  Future<CloudFileItem?> getFileMetadata(String path) async {
    final res = await invokeBrokerRpc('files.metadata', <String, Object?>{
      'path': path,
    });
    return CloudFileItem.fromJson(res);
  }

  Future<bool> createFolder(String parentPath, String name) async {
    final res = await invokeBrokerRpc('files.createFolder', <String, Object?>{
      'parentPath': parentPath,
      'name': name,
    });
    return res['ok'] == true;
  }

  Future<bool> renameItem(String path, String newName) async {
    final res = await invokeBrokerRpc('files.rename', <String, Object?>{
      'path': path,
      'newName': newName,
    });
    return res['ok'] == true;
  }

  Future<bool> deleteItems(List<String> paths, {bool permanent = false}) async {
    final res = await invokeBrokerRpc('files.delete', <String, Object?>{
      'paths': paths,
      'permanent': permanent,
    });
    return res['ok'] == true;
  }

  Future<String?> copyItems(
    List<String> sources,
    String destination, {
    String overwritePolicy = 'ask',
  }) async {
    final res = await invokeBrokerRpc('files.copy', <String, Object?>{
      'sources': sources,
      'destination': destination,
      'overwritePolicy': overwritePolicy,
    });
    return res['jobId'] as String?;
  }

  Future<String?> moveItems(
    List<String> sources,
    String destination, {
    String overwritePolicy = 'ask',
  }) async {
    final res = await invokeBrokerRpc('files.move', <String, Object?>{
      'sources': sources,
      'destination': destination,
      'overwritePolicy': overwritePolicy,
    });
    return res['jobId'] as String?;
  }

  Future<String?> searchFiles(
    String rootPath,
    String query, {
    bool recursive = true,
  }) async {
    final res = await invokeBrokerRpc('files.search', <String, Object?>{
      'rootPath': rootPath,
      'query': query,
      'recursive': recursive,
    });
    return res['jobId'] as String?;
  }

  Future<Map<String, Object?>> getJobStatus(String jobId) {
    return invokeBrokerRpc('jobs.status', <String, Object?>{'jobId': jobId});
  }

  Future<bool> cancelJob(String jobId) async {
    final res = await invokeBrokerRpc('jobs.cancel', <String, Object?>{
      'jobId': jobId,
    });
    return res['cancelled'] == true;
  }

  Future<bool> openDefault(String path) async {
    final res = await invokeBrokerRpc('files.open', <String, Object?>{
      'path': path,
    });
    return res['ok'] == true;
  }

  Future<List<OpenWithAppModel>> getOpenWithList(String path) async {
    final res = await invokeBrokerRpc('files.openWith.list', <String, Object?>{
      'path': path,
    });
    if (res['apps'] is List<Object?>) {
      final list = res['apps'] as List<Object?>;
      return list
          .whereType<Map<String, Object?>>()
          .map((m) => OpenWithAppModel.fromJson(m))
          .toList(growable: false);
    }
    return const <OpenWithAppModel>[];
  }

  Future<bool> launchOpenWith(
    String path,
    String appId,
    String platform, {
    String distro = '',
  }) async {
    final res = await invokeBrokerRpc(
      'files.openWith.launch',
      <String, Object?>{
        'path': path,
        'appId': appId,
        'platform': platform,
        'distro': distro,
      },
    );
    return res['ok'] == true;
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
    if (normalized.contains('browser') ||
        normalized.contains('chrome') ||
        normalized.contains('edge')) {
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

  static const unavailableSnapshot = CloudSystemSnapshot(
    deviceName: 'CloudOS indisponível',
    networkName: 'Rede indisponível',
    volume: 0,
    brightness: 0,
    batteryPercent: -1,
    wslAvailable: false,
    distros: <String>[],
    currentWorkspace: 0,
    batteryAvailable: false,
    networkAvailable: false,
    volumeAvailable: false,
    brightnessAvailable: false,
  );
}
