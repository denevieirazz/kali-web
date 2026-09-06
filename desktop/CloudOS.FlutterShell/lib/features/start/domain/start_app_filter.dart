import 'package:flutter/material.dart';

import '../../../models/shell_models.dart';

const startFilters = <String>[
  'Todos',
  'Abertos',
  'CloudOS',
  'Windows',
  'Linux / WSL',
  'Produtividade',
  'Sistema',
  'Utilitários',
];

const _deepSearchLocations = <CloudApp>[
  CloudApp(
    id: 'cloudos:settings:display',
    name: 'Configurações: Vídeo e Resolução',
    subtitle: 'Ajuste de resolução, taxa de atualização e dimensionamento de tela',
    icon: Icons.monitor_rounded,
    platform: CloudAppPlatform.cloudos,
    category: 'Sistema',
  ),
  CloudApp(
    id: 'cloudos:settings:sound',
    name: 'Configurações: Áudio e Volume',
    subtitle: 'Dispositivos de saída, entrada e níveis de volume do sistema',
    icon: Icons.volume_up_rounded,
    platform: CloudAppPlatform.cloudos,
    category: 'Sistema',
  ),
  CloudApp(
    id: 'cloudos:settings:network',
    name: 'Configurações: Rede e Internet',
    subtitle: 'Wi-Fi, Ethernet, adaptadores e conexões ativas de rede',
    icon: Icons.wifi_rounded,
    platform: CloudAppPlatform.cloudos,
    category: 'Sistema',
  ),
  CloudApp(
    id: 'cloudos:settings:bluetooth',
    name: 'Configurações: Dispositivos Bluetooth',
    subtitle: 'Gerenciamento de periféricos e pareamento Bluetooth sem fio',
    icon: Icons.bluetooth_rounded,
    platform: CloudAppPlatform.cloudos,
    category: 'Sistema',
  ),
  CloudApp(
    id: 'cloudos:settings:storage',
    name: 'Configurações: Armazenamento e Discos',
    subtitle: 'Uso de disco, partições locais e espaço de armazenamento',
    icon: Icons.storage_rounded,
    platform: CloudAppPlatform.cloudos,
    category: 'Sistema',
  ),
  CloudApp(
    id: 'cloudos:settings:power',
    name: 'Configurações: Bateria e Energia',
    subtitle: 'Plano de energia, tempo de suspensão e status de carregamento',
    icon: Icons.battery_charging_full_rounded,
    platform: CloudAppPlatform.cloudos,
    category: 'Sistema',
  ),
  CloudApp(
    id: 'cloudos:settings:performance',
    name: 'Configurações: Perfil de Desempenho',
    subtitle: 'Alternar entre perfis Econômico, Equilibrado e Alto Desempenho',
    icon: Icons.speed_rounded,
    platform: CloudAppPlatform.cloudos,
    category: 'Sistema',
  ),
  CloudApp(
    id: 'cloudos:settings:wsl',
    name: 'Configurações: Subsistema Linux (WSL2)',
    subtitle: 'Distribuições instaladas, status e reinicialização do WSL',
    icon: Icons.terminal_rounded,
    platform: CloudAppPlatform.cloudos,
    category: 'Sistema',
  ),
  CloudApp(
    id: 'cloudos:settings:recovery',
    name: 'Configurações: Recuperação e Shell',
    subtitle: 'Modo de segurança, integridade do sistema e restauração Explorer',
    icon: Icons.security_rounded,
    platform: CloudAppPlatform.cloudos,
    category: 'Sistema',
  ),
  CloudApp(
    id: 'cloudos:settings:about',
    name: 'Configurações: Sobre o CloudOS',
    subtitle: 'Versão RC1, arquitetura, build e termos de licenciamento',
    icon: Icons.info_outline_rounded,
    platform: CloudAppPlatform.cloudos,
    category: 'Sistema',
  ),
  CloudApp(
    id: 'files:downloads',
    name: 'Pasta: Downloads',
    subtitle: 'Pasta de arquivos transferidos e downloads do usuário',
    icon: Icons.download_rounded,
    platform: CloudAppPlatform.cloudos,
    category: 'Produtividade',
  ),
  CloudApp(
    id: 'files:documents',
    name: 'Pasta: Documentos',
    subtitle: 'Pasta de documentos pessoais e arquivos de trabalho',
    icon: Icons.folder_rounded,
    platform: CloudAppPlatform.cloudos,
    category: 'Produtividade',
  ),
  CloudApp(
    id: 'files:desktop',
    name: 'Pasta: Área de Trabalho',
    subtitle: 'Pasta de arquivos da Área de Trabalho local',
    icon: Icons.desktop_windows_rounded,
    platform: CloudAppPlatform.cloudos,
    category: 'Produtividade',
  ),
  CloudApp(
    id: 'cloudos:trash',
    name: 'Pasta: Lixeira',
    subtitle: 'Itens excluídos e gerenciamento da Lixeira do sistema',
    icon: Icons.delete_outline_rounded,
    platform: CloudAppPlatform.cloudos,
    category: 'Utilitários',
  ),
];

List<CloudApp> filterStartApps({
  required List<CloudApp> apps,
  required String query,
  required String selectedFilter,
  bool includeDeepLocations = false,
}) {
  final normalized = query.trim().toLowerCase();
  final allCandidates = (includeDeepLocations && normalized.isNotEmpty)
      ? <CloudApp>[...apps, ..._deepSearchLocations.where((loc) => !apps.any((a) => a.id == loc.id))]
      : apps;

  return allCandidates
      .where((app) {
        final matchesQuery =
            normalized.isEmpty ||
            app.name.toLowerCase().contains(normalized) ||
            (app.subtitle?.toLowerCase().contains(normalized) ?? false) ||
            (app.distro?.toLowerCase().contains(normalized) ?? false) ||
            app.category.toLowerCase().contains(normalized);

        if (!matchesQuery) return false;
        if (selectedFilter == 'Todos') return true;
        if (selectedFilter == 'Abertos') return false;
        if (selectedFilter == 'CloudOS') {
          return app.platform == CloudAppPlatform.cloudos;
        }
        if (selectedFilter == 'Windows') {
          return app.platform == CloudAppPlatform.windows;
        }
        if (selectedFilter == 'Linux / WSL' || selectedFilter == 'Linux') {
          return app.platform == CloudAppPlatform.linux;
        }
        return app.category == selectedFilter;
      })
      .toList(growable: false);
}
