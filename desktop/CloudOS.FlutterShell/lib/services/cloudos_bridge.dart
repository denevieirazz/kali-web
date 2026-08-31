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
      'schema': 20,
      'version': 'v20-preview',
      'bridge_type': 'PreviewFallback',
      'channel': 'cloudos/native/v19',
      'arbitrary_command_api': false,
    };
  }

  CloudApp _appFromNative(Map<Object?, Object?> raw) {
    final platformName = raw['platform'] as String? ?? 'windows';
    final platform = switch (platformName.toLowerCase()) {
      'linux' => CloudAppPlatform.linux,
      'cloudos' => CloudAppPlatform.cloudos,
      _ => CloudAppPlatform.windows,
    };
    final id = raw['id'] as String? ?? raw['name'] as String? ?? 'app';
    final name = raw['name'] as String? ?? 'Aplicativo';
    final subtitle = raw['subtitle'] as String?;
    final distro = raw['distro'] as String?;
    final category = raw['category'] as String? ??
        (platform == CloudAppPlatform.linux ? 'Linux / WSL' : 'Produtividade');
    final isPinned = raw['pinned'] as bool? ?? (raw['isPinned'] as bool? ?? false);
    final isRecent = raw['recent'] as bool? ?? (raw['isRecent'] as bool? ?? false);

    return CloudApp(
      id: id,
      name: name,
      icon: _resolveIcon(id, name, platform),
      platform: platform,
      subtitle: subtitle,
      distro: distro,
      category: category,
      isPinned: isPinned,
      isRecent: isRecent,
    );
  }

  static IconData _resolveIcon(String id, String name, CloudAppPlatform platform) {
    final lower = '${id.toLowerCase()} ${name.toLowerCase()}';
    if (lower.contains('code') || lower.contains('vscode')) return Icons.code_rounded;
    if (lower.contains('terminal') || lower.contains('powershell') || lower.contains('cmd') || lower.contains('bash')) {
      return Icons.terminal_rounded;
    }
    if (lower.contains('browser') || lower.contains('chrome') || lower.contains('edge') || lower.contains('web')) {
      return Icons.language_rounded;
    }
    if (lower.contains('file') || lower.contains('arquivo') || lower.contains('drive') || lower.contains('explorer')) {
      return Icons.folder_rounded;
    }
    if (lower.contains('gimp') || lower.contains('paint') || lower.contains('photo') || lower.contains('draw')) {
      return Icons.palette_rounded;
    }
    if (lower.contains('calc') || lower.contains('calculadora')) return Icons.calculate_rounded;
    if (lower.contains('setting') || lower.contains('config')) return Icons.settings_rounded;
    if (lower.contains('wireshark') || lower.contains('nmap') || lower.contains('zenmap') || lower.contains('security')) {
      return Icons.security_rounded;
    }
    if (lower.contains('trash') || lower.contains('lixeira')) return Icons.delete_outline_rounded;
    if (lower.contains('app') || lower.contains('store')) return Icons.apps_rounded;
    return _fallbackIcon(platform);
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
      CloudFileItem(
        name: 'projeto_cloudos_v19.dart',
        path: 'CloudOS://Drive/Home/Projects/projeto_cloudos_v19.dart',
        isFolder: false,
        sizeFormatted: '14.2 KB',
        modifiedFormatted: '31 Ago 2026',
        source: CloudFileSource.cloudDrive,
        icon: Icons.code_rounded,
        extension: 'dart',
      ),
      CloudFileItem(
        name: 'arquitetura_sistema.pdf',
        path: 'C:\\Users\\dougl\\Documents\\arquitetura_sistema.pdf',
        isFolder: false,
        sizeFormatted: '2.4 MB',
        modifiedFormatted: '28 Ago 2026',
        source: CloudFileSource.windows,
        icon: Icons.picture_as_pdf_rounded,
        extension: 'pdf',
      ),
      CloudFileItem(
        name: 'wallpaper_cloudos_dark.png',
        path: 'C:\\Users\\dougl\\Pictures\\wallpaper_cloudos_dark.png',
        isFolder: false,
        sizeFormatted: '3.8 MB',
        modifiedFormatted: '25 Ago 2026',
        source: CloudFileSource.windows,
        icon: Icons.image_rounded,
        extension: 'png',
      ),
      CloudFileItem(
        name: 'analise_seguranca.log',
        path: '\\\\wsl.localhost\\Ubuntu\\var\\log\\analise.log',
        isFolder: false,
        sizeFormatted: '68 KB',
        modifiedFormatted: '20 Ago 2026',
        source: CloudFileSource.linux,
        icon: Icons.description_rounded,
        extension: 'log',
      ),
    ],
  };

  static const previewNotifications = <CloudNotification>[
    CloudNotification(
      id: 'notif-1',
      title: 'CloudOS V19 Pronto',
      message: 'Camada de apresentação Flutter inicializada com suporte a Windows e Linux WSL.',
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
    CloudNotification(
      id: 'notif-3',
      title: 'CloudOS Drive Sincronizado',
      message: 'Armazenamento isolado e lixeira transacional operando sem divergências.',
      time: '20 min',
      icon: Icons.sync_rounded,
      source: 'CloudOS Drive',
      category: 'Armazenamento',
    ),
  ];
}
