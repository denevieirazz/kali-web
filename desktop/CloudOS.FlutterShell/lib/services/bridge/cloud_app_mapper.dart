import 'package:flutter/material.dart';

import '../../models/shell_models.dart';

CloudApp cloudAppFromNative(Map<Object?, Object?> raw) {
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
