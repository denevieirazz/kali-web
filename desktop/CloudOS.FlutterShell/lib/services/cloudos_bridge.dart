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
      subtitle: 'WebView2 Isolado',
      category: 'Internet',
      isPinned: true,
      isRecent: true,
    ),
    CloudApp(
      id: 'terminal',
      name: 'Terminal ConPTY',
      icon: Icons.terminal_rounded,
      platform: CloudAppPlatform.cloudos,
      subtitle: 'PowerShell 7 / WSL',
      category: 'Desenvolvimento',
      isPinned: true,
      isRecent: true,
    ),
    CloudApp(
      id: 'vscode',
      name: 'Visual Studio Code',
      icon: Icons.code_rounded,
      platform: CloudAppPlatform.windows,
      subtitle: 'Microsoft Windows',
      category: 'Desenvolvimento',
      isPinned: true,
      isRecent: true,
    ),
    CloudApp(
      id: 'ubuntu-terminal',
      name: 'Ubuntu Terminal',
      icon: Icons.terminal_rounded,
      platform: CloudAppPlatform.linux,
      subtitle: 'Linux WSL2 • Ubuntu',
      distro: 'Ubuntu',
      category: 'Linux / WSL',
      isPinned: true,
      isRecent: true,
    ),
    CloudApp(
      id: 'settings',
      name: 'Configurações',
      icon: Icons.settings_rounded,
      platform: CloudAppPlatform.cloudos,
      subtitle: 'Painel do Sistema',
      category: 'Sistema',
      isPinned: true,
      isRecent: false,
    ),
    CloudApp(
      id: 'sysmon',
      name: 'Monitor de Recursos',
      icon: Icons.speed_rounded,
      platform: CloudAppPlatform.cloudos,
      subtitle: 'CPU • RAM • Handles',
      category: 'Sistema',
      isPinned: true,
      isRecent: false,
    ),
    CloudApp(
      id: 'notepad',
      name: 'Editor de Notas',
      icon: Icons.edit_note_rounded,
      platform: CloudAppPlatform.cloudos,
      subtitle: 'Editor Rápido',
      category: 'Produtividade',
      isPinned: false,
      isRecent: true,
    ),
    CloudApp(
      id: 'calc',
      name: 'Calculadora',
      icon: Icons.calculate_rounded,
      platform: CloudAppPlatform.cloudos,
      subtitle: 'Utilitário',
      category: 'Utilitários',
      isPinned: false,
      isRecent: false,
    ),
    CloudApp(
      id: 'gimp',
      name: 'GIMP Image Editor',
      icon: Icons.brush_rounded,
      platform: CloudAppPlatform.linux,
      subtitle: 'WSLg GUI App',
      distro: 'Ubuntu',
      category: 'Criatividade',
      isPinned: false,
      isRecent: false,
    ),
    CloudApp(
      id: 'wireshark',
      name: 'Wireshark',
      icon: Icons.troubleshoot_rounded,
      platform: CloudAppPlatform.windows,
      subtitle: 'Windows Win32',
      category: 'Segurança',
      isPinned: false,
      isRecent: false,
    ),
  ];

  static const previewFiles = <String, List<CloudFileItem>>{
    'home': <CloudFileItem>[
      CloudFileItem(
        name: 'Documentos',
        path: 'C:\\Users\\dougl\\Documents',
        isFolder: true,
        sizeFormatted: '24 pastas',
        modifiedFormatted: 'Hoje, 14:20',
        source: CloudFileSource.windows,
        icon: Icons.folder_special_rounded,
      ),
      CloudFileItem(
        name: 'Downloads',
        path: 'C:\\Users\\dougl\\Downloads',
        isFolder: true,
        sizeFormatted: '18 itens',
        modifiedFormatted: 'Hoje, 11:05',
        source: CloudFileSource.windows,
        icon: Icons.download_rounded,
      ),
      CloudFileItem(
        name: 'CloudOS Drive',
        path: 'CloudOS://Drive/Home',
        isFolder: true,
        sizeFormatted: '1.2 GB',
        modifiedFormatted: 'Ontem',
        source: CloudFileSource.cloudDrive,
        icon: Icons.cloud_circle_rounded,
      ),
      CloudFileItem(
        name: 'Ubuntu Home',
        path: '\\\\wsl.localhost\\Ubuntu\\home\\dougl',
        isFolder: true,
        sizeFormatted: '12 pastas',
        modifiedFormatted: 'Ontem',
        source: CloudFileSource.linux,
        icon: Icons.terminal_rounded,
      ),
    ],
  };

  static const previewNotifications = <CloudNotification>[
    CloudNotification(
      id: 'notif-1',
      title: 'CloudOS V21 Pronto',
      message: 'System Broker e Event Bus ativos com suporte a Windows e Linux WSL.',
      time: 'agora',
      icon: Icons.cloud_done_rounded,
      source: 'CloudOS Core',
      category: 'Sistema',
    ),
    CloudNotification(
      id: 'notif-2',
      title: 'Subsistema Linux (WSL2)',
      message: 'Ubuntu 24.04 LTS ativo. Aplicativos gráficos WSLg disponíveis no Start.',
      time: '5 min',
      icon: Icons.terminal_rounded,
      source: 'WSL2 / Ubuntu',
      category: 'Linux',
    ),
  ];
}
