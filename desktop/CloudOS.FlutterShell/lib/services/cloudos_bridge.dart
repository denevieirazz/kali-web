import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/file_models.dart';
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
      // Fallback
    } on PlatformException {
      // Fallback
    }
    return const <String, Object?>{
      'schema': 22,
      'version': 'v22-preview',
      'bridge_type': 'PreviewFallback',
      'brokerConnected': false,
      'brokerState': 'degraded',
      'channel': 'cloudos/native/v19',
      'arbitrary_command_api': false,
    };
  }

  // ==========================================
  // V22 FileService RPC Methods
  // ==========================================

  Future<Map<String, Object?>?> invokeBrokerRpc(String method, Map<String, Object?> payload) async {
    try {
      final jsonStr = await _channel.invokeMethod<String>('invokeBrokerRpc', <String, Object?>{
        'method': method,
        'payload': jsonEncode(payload),
      });
      if (jsonStr == null || jsonStr.isEmpty) return null;
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, Object?>) {
        if (decoded['ok'] == true && decoded['payload'] is Map<String, Object?>) {
          return decoded['payload'] as Map<String, Object?>;
        }
      }
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<List<KnownFolderModel>> getKnownFolders() async {
    final res = await invokeBrokerRpc('files.knownFolders', const <String, Object?>{});
    if (res != null && res['folders'] is List<Object?>) {
      final list = res['folders'] as List<Object?>;
      return list
          .whereType<Map<String, Object?>>()
          .map((m) => KnownFolderModel.fromJson(m))
          .toList(growable: false);
    }
    return previewKnownFolders;
  }

  Future<List<DriveInfoModel>> getDrives() async {
    final res = await invokeBrokerRpc('files.drives', const <String, Object?>{});
    if (res != null && res['drives'] is List<Object?>) {
      final list = res['drives'] as List<Object?>;
      return list
          .whereType<Map<String, Object?>>()
          .map((m) => DriveInfoModel.fromJson(m))
          .toList(growable: false);
    }
    return previewDrives;
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
    if (sortField == FileSortField.size) sf = 'size';
    else if (sortField == FileSortField.modified) sf = 'modified';
    else if (sortField == FileSortField.type) sf = 'type';

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

    if (res != null && res['items'] is List<Object?>) {
      final list = res['items'] as List<Object?>;
      return list
          .whereType<Map<String, Object?>>()
          .map((m) => CloudFileItem.fromJson(m))
          .toList(growable: false);
    }

    return previewFiles[path] ?? previewFiles['home'] ?? <CloudFileItem>[];
  }

  Future<CloudFileItem?> getFileMetadata(String path) async {
    final res = await invokeBrokerRpc('files.metadata', <String, Object?>{'path': path});
    if (res != null) {
      return CloudFileItem.fromJson(res);
    }
    return null;
  }

  Future<bool> createFolder(String parentPath, String name) async {
    final res = await invokeBrokerRpc('files.createFolder', <String, Object?>{
      'parentPath': parentPath,
      'name': name,
    });
    return res?['ok'] == true;
  }

  Future<bool> renameItem(String path, String newName) async {
    final res = await invokeBrokerRpc('files.rename', <String, Object?>{
      'path': path,
      'newName': newName,
    });
    return res?['ok'] == true;
  }

  Future<bool> deleteItems(List<String> paths, {bool permanent = false}) async {
    final res = await invokeBrokerRpc('files.delete', <String, Object?>{
      'paths': paths,
      'permanent': permanent,
    });
    return res?['ok'] == true;
  }

  Future<String?> copyItems(List<String> sources, String destination, {String overwritePolicy = 'ask'}) async {
    final res = await invokeBrokerRpc('files.copy', <String, Object?>{
      'sources': sources,
      'destination': destination,
      'overwritePolicy': overwritePolicy,
    });
    return res?['jobId'] as String?;
  }

  Future<String?> moveItems(List<String> sources, String destination, {String overwritePolicy = 'ask'}) async {
    final res = await invokeBrokerRpc('files.move', <String, Object?>{
      'sources': sources,
      'destination': destination,
      'overwritePolicy': overwritePolicy,
    });
    return res?['jobId'] as String?;
  }

  Future<String?> searchFiles(String rootPath, String query, {bool recursive = true}) async {
    final res = await invokeBrokerRpc('files.search', <String, Object?>{
      'rootPath': rootPath,
      'query': query,
      'recursive': recursive,
    });
    return res?['jobId'] as String?;
  }

  Future<bool> openDefault(String path) async {
    final res = await invokeBrokerRpc('files.open', <String, Object?>{'path': path});
    return res?['ok'] == true;
  }

  Future<List<OpenWithAppModel>> getOpenWithList(String path) async {
    final res = await invokeBrokerRpc('files.openWith.list', <String, Object?>{'path': path});
    if (res != null && res['apps'] is List<Object?>) {
      final list = res['apps'] as List<Object?>;
      return list
          .whereType<Map<String, Object?>>()
          .map((m) => OpenWithAppModel.fromJson(m))
          .toList(growable: false);
    }
    return previewOpenWith;
  }

  Future<bool> launchOpenWith(String path, String appId, String platform, {String distro = ''}) async {
    final res = await invokeBrokerRpc('files.openWith.launch', <String, Object?>{
      'path': path,
      'appId': appId,
      'platform': platform,
      'distro': distro,
    });
    return res?['ok'] == true;
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

  static const previewSnapshot = CloudSystemSnapshot(
    deviceName: 'CloudOS Desktop',
    networkName: 'CloudOS Network • Wi-Fi 6',
    volume: 0.72,
    brightness: 0.85,
    batteryPercent: 92,
    wslAvailable: true,
    distros: <String>['Ubuntu 24.04 LTS'],
    currentWorkspace: 1,
  );

  static const previewApps = <CloudApp>[
    CloudApp(
      id: 'files',
      name: 'Arquivos',
      icon: Icons.folder_rounded,
      platform: CloudAppPlatform.cloudos,
      subtitle: 'Windows + Linux',
      category: 'Sistema',
      isPinned: true,
      isRecent: true,
    ),
    CloudApp(
      id: 'browser',
      name: 'Navegador Web',
      icon: Icons.language_rounded,
      platform: CloudAppPlatform.cloudos,
      subtitle: 'Chromium / WebView2',
      category: 'Produtividade',
      isPinned: true,
      isRecent: true,
    ),
    CloudApp(
      id: 'terminal',
      name: 'Terminal CloudOS',
      icon: Icons.terminal_rounded,
      platform: CloudAppPlatform.cloudos,
      subtitle: 'PowerShell 7 / WSL',
      category: 'Utilitários',
      isPinned: true,
      isRecent: true,
    ),
    CloudApp(
      id: 'vscode',
      name: 'Visual Studio Code',
      icon: Icons.code_rounded,
      platform: CloudAppPlatform.windows,
      subtitle: 'Code Editor',
      category: 'Produtividade',
      isPinned: true,
      isRecent: true,
    ),
    CloudApp(
      id: 'notepad',
      name: 'Bloco de Notas',
      icon: Icons.edit_note_rounded,
      platform: CloudAppPlatform.windows,
      subtitle: 'Editor de Texto',
      category: 'Produtividade',
      isPinned: true,
      isRecent: false,
    ),
    CloudApp(
      id: 'gimp',
      name: 'GIMP Image Editor',
      icon: Icons.brush_rounded,
      platform: CloudAppPlatform.linux,
      subtitle: 'Ubuntu (WSLg)',
      distro: 'Ubuntu',
      category: 'Produtividade',
      isPinned: true,
      isRecent: false,
    ),
  ];

  static const previewKnownFolders = <KnownFolderModel>[
    KnownFolderModel(id: 'home', name: 'Início', path: 'C:\\Users\\User', iconKey: 'home'),
    KnownFolderModel(id: 'desktop', name: 'Área de Trabalho', path: 'C:\\Users\\User\\Desktop', iconKey: 'desktop'),
    KnownFolderModel(id: 'documents', name: 'Documentos', path: 'C:\\Users\\User\\Documents', iconKey: 'documents'),
    KnownFolderModel(id: 'downloads', name: 'Downloads', path: 'C:\\Users\\User\\Downloads', iconKey: 'downloads'),
    KnownFolderModel(id: 'pictures', name: 'Imagens', path: 'C:\\Users\\User\\Pictures', iconKey: 'pictures'),
    KnownFolderModel(id: 'videos', name: 'Vídeos', path: 'C:\\Users\\User\\Videos', iconKey: 'videos'),
    KnownFolderModel(id: 'music', name: 'Músicas', path: 'C:\\Users\\User\\Music', iconKey: 'music'),
    KnownFolderModel(id: 'wsl:Ubuntu', name: 'Ubuntu (WSL)', path: '\\\\wsl.localhost\\Ubuntu', iconKey: 'linux'),
  ];

  static const previewDrives = <DriveInfoModel>[
    DriveInfoModel(
      letter: 'C:',
      path: 'C:\\',
      label: 'Disco Local (C:)',
      filesystem: 'NTFS',
      totalBytes: 512000000000,
      freeBytes: 256000000000,
      totalFormatted: '512.0 GB',
      freeFormatted: '256.0 GB',
      isRemovable: false,
      isReady: true,
      driveType: 'fixed',
    ),
  ];

  static const previewOpenWith = <OpenWithAppModel>[
    OpenWithAppModel(
      appId: 'windows:default',
      name: 'Aplicativo Padrão do Windows',
      platform: 'windows',
      distro: '',
      iconKey: 'window',
      isRecommended: true,
      isDefault: true,
    ),
    OpenWithAppModel(
      appId: 'windows:notepad',
      name: 'Bloco de Notas (Windows)',
      platform: 'windows',
      distro: '',
      iconKey: 'file_text',
      isRecommended: true,
      isDefault: false,
    ),
    OpenWithAppModel(
      appId: 'windows:vscode',
      name: 'Visual Studio Code',
      platform: 'windows',
      distro: '',
      iconKey: 'code',
      isRecommended: true,
      isDefault: false,
    ),
    OpenWithAppModel(
      appId: 'wsl:Ubuntu:gimp',
      name: 'GIMP Image Editor (Ubuntu)',
      platform: 'linux',
      distro: 'Ubuntu',
      iconKey: 'brush',
      isRecommended: false,
      isDefault: false,
    ),
  ];

  static const previewFiles = <String, List<CloudFileItem>>{
    'home': <CloudFileItem>[
      CloudFileItem(
        id: 'file-1',
        name: 'Projetos CloudOS',
        displayName: 'Projetos CloudOS',
        path: 'C:\\Users\\User\\Documents\\Projetos',
        canonicalPath: 'C:\\Users\\User\\Documents\\Projetos',
        locationKind: LocationKind.windows,
        fileKind: FileKind.folder,
        extension: '',
        size: 0,
        sizeFormatted: '',
        modifiedFormatted: 'Hoje, 14:20',
        createdFormatted: 'Ontem',
        isDirectory: true,
        isHidden: false,
        isReadOnly: false,
        isSystem: false,
        isSymlink: false,
        distro: '',
        iconKey: 'folder',
      ),
      CloudFileItem(
        id: 'file-2',
        name: 'Relatório de Arquitetura V22.docx',
        displayName: 'Relatório de Arquitetura V22.docx',
        path: 'C:\\Users\\User\\Documents\\Relatório.docx',
        canonicalPath: 'C:\\Users\\User\\Documents\\Relatório.docx',
        locationKind: LocationKind.windows,
        fileKind: FileKind.document,
        extension: '.docx',
        size: 1048576,
        sizeFormatted: '1.0 MB',
        modifiedFormatted: 'Hoje, 11:05',
        createdFormatted: 'Ontem',
        isDirectory: false,
        isHidden: false,
        isReadOnly: false,
        isSystem: false,
        isSymlink: false,
        distro: '',
        iconKey: 'file_document',
      ),
      CloudFileItem(
        id: 'file-3',
        name: 'linux_workspace_ubuntu',
        displayName: 'linux_workspace_ubuntu',
        path: '\\\\wsl.localhost\\Ubuntu\\home\\user',
        canonicalPath: '\\\\wsl.localhost\\Ubuntu\\home\\user',
        locationKind: LocationKind.wsl,
        fileKind: FileKind.folder,
        extension: '',
        size: 0,
        sizeFormatted: '',
        modifiedFormatted: 'Ontem, 19:42',
        createdFormatted: '2 dias atrás',
        isDirectory: true,
        isHidden: false,
        isReadOnly: false,
        isSystem: false,
        isSymlink: false,
        distro: 'Ubuntu',
        iconKey: 'folder',
      ),
      CloudFileItem(
        id: 'file-4',
        name: 'script_automacao.sh',
        displayName: 'script_automacao.sh',
        path: '\\\\wsl.localhost\\Ubuntu\\home\\user\\script.sh',
        canonicalPath: '\\\\wsl.localhost\\Ubuntu\\home\\user\\script.sh',
        locationKind: LocationKind.wsl,
        fileKind: FileKind.code,
        extension: '.sh',
        size: 4096,
        sizeFormatted: '4.0 KB',
        modifiedFormatted: '28 de Ago',
        createdFormatted: '28 de Ago',
        isDirectory: false,
        isHidden: false,
        isReadOnly: false,
        isSystem: false,
        isSymlink: false,
        distro: 'Ubuntu',
        iconKey: 'file_code',
      ),
    ],
  };

  static const previewNotifications = <CloudNotification>[
    CloudNotification(
      id: 'notif-1',
      title: 'CloudOS Atualizado',
      message: 'A versão V22 do CloudOS com Unified Files foi carregada com sucesso.',
      time: 'Agora',
      icon: Icons.system_update_rounded,
      source: 'Sistema',
      category: 'Atualizações',
    ),
    CloudNotification(
      id: 'notif-2',
      title: 'WSL2 Conectado',
      message: 'Ambiente Linux Ubuntu 24.04 LTS pronto para navegação e launch.',
      time: 'Há 5m',
      icon: Icons.terminal_rounded,
      source: 'WSL Bridge',
      category: 'Integração',
    ),
  ];
}
