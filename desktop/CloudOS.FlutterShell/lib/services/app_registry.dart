import 'package:flutter/material.dart';

enum AppCategory {
  system,
  productivity,
  utilities,
  development,
}

class AppDefinition {
  const AppDefinition({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.isInternal,
    this.category = AppCategory.productivity,
    this.defaultWidth = 840.0,
    this.defaultHeight = 580.0,
    this.isSingleton = false,
    this.pinned = false,
  });

  final String id;
  final String name;
  final String subtitle;
  final IconData icon;
  final bool isInternal;
  final AppCategory category;
  final double defaultWidth;
  final double defaultHeight;
  final bool isSingleton;
  final bool pinned;
}

class AppRegistry {
  static const List<AppDefinition> definedApps = <AppDefinition>[
    AppDefinition(
      id: 'cloudos:files',
      name: 'Arquivos',
      subtitle: 'Explorador Unificado Windows + Linux',
      icon: Icons.folder_rounded,
      isInternal: true,
      category: AppCategory.system,
      defaultWidth: 920.0,
      defaultHeight: 620.0,
      isSingleton: false,
      pinned: true,
    ),
    AppDefinition(
      id: 'cloudos:terminal',
      name: 'Terminal',
      subtitle: 'Console PowerShell, CMD & WSL',
      icon: Icons.terminal_rounded,
      isInternal: true,
      category: AppCategory.development,
      defaultWidth: 860.0,
      defaultHeight: 520.0,
      isSingleton: false,
      pinned: true,
    ),
    AppDefinition(
      id: 'cloudos:browser',
      name: 'Navegador',
      subtitle: 'Navegador Web Integrado',
      icon: Icons.language_rounded,
      isInternal: true,
      category: AppCategory.productivity,
      defaultWidth: 980.0,
      defaultHeight: 640.0,
      isSingleton: false,
      pinned: true,
    ),
    AppDefinition(
      id: 'cloudos:settings',
      name: 'Configurações',
      subtitle: 'Painel de Controle e Ajustes do CloudOS',
      icon: Icons.settings_rounded,
      isInternal: true,
      category: AppCategory.system,
      defaultWidth: 880.0,
      defaultHeight: 580.0,
      isSingleton: true,
      pinned: true,
    ),
    AppDefinition(
      id: 'cloudos:system-monitor',
      name: 'Monitor do Sistema',
      subtitle: 'CPU, RAM, Disco, Rede e Processos',
      icon: Icons.monitor_heart_rounded,
      isInternal: true,
      category: AppCategory.system,
      defaultWidth: 840.0,
      defaultHeight: 540.0,
      isSingleton: true,
      pinned: true,
    ),
    AppDefinition(
      id: 'cloudos:projects',
      name: 'Projetos',
      subtitle: 'Gerenciador de Workspaces e Repositórios',
      icon: Icons.account_tree_rounded,
      isInternal: true,
      category: AppCategory.development,
      defaultWidth: 860.0,
      defaultHeight: 560.0,
      isSingleton: true,
      pinned: true,
    ),
    AppDefinition(
      id: 'cloudos:drive',
      name: 'CloudOS Drive',
      subtitle: 'Armazenamento Local do CloudOS',
      icon: Icons.cloud_queue_rounded,
      isInternal: true,
      category: AppCategory.productivity,
      defaultWidth: 860.0,
      defaultHeight: 560.0,
      isSingleton: true,
      pinned: true,
    ),
    AppDefinition(
      id: 'wsl:terminal',
      name: 'WSL Linux',
      subtitle: 'Terminal WSL integrado quando uma distro estiver disponível',
      icon: Icons.terminal_rounded,
      isInternal: true,
      category: AppCategory.development,
      defaultWidth: 860.0,
      defaultHeight: 520.0,
      pinned: true,
    ),
    AppDefinition(
      id: 'cloudos:notepad',
      name: 'Bloco de Notas',
      subtitle: 'Editor de Texto & Código com Abas',
      icon: Icons.edit_note_rounded,
      isInternal: true,
      category: AppCategory.productivity,
      defaultWidth: 840.0,
      defaultHeight: 560.0,
      isSingleton: false,
      pinned: true,
    ),
    AppDefinition(
      id: 'windows:vscode',
      name: 'Visual Studio Code',
      subtitle: 'Aplicação Externa (Windows)',
      icon: Icons.code_rounded,
      isInternal: false,
      category: AppCategory.development,
      pinned: false,
    ),
    AppDefinition(
      id: 'windows:taskmgr',
      name: 'Gerenciador de Tarefas',
      subtitle: 'Aplicação Externa (Windows)',
      icon: Icons.speed_rounded,
      isInternal: false,
      category: AppCategory.system,
      pinned: false,
    ),
    AppDefinition(
      id: 'windows:explorer',
      name: 'Explorador do Windows',
      subtitle: 'Aplicação Externa (Windows)',
      icon: Icons.folder_open_rounded,
      isInternal: false,
      category: AppCategory.system,
      pinned: false,
    ),
  ];

  static AppDefinition? findById(String id) {
    final normalized = id.toLowerCase();
    for (final app in definedApps) {
      if (app.id.toLowerCase() == normalized) return app;
    }
    if (normalized == 'files') return findById('cloudos:files');
    if (normalized == 'terminal') return findById('cloudos:terminal');
    if (normalized == 'browser') return findById('cloudos:browser');
    if (normalized == 'settings') return findById('cloudos:settings');
    if (normalized == 'system-monitor') return findById('cloudos:system-monitor');
    if (normalized == 'projects') return findById('cloudos:projects');
    if (normalized == 'drive') return findById('cloudos:drive');
    if (normalized == 'notepad') return findById('cloudos:notepad');
    if (normalized.startsWith('wsl:')) return findById('wsl:terminal');
    return null;
  }
}
