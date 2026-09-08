import 'package:flutter/material.dart';

import '../models/search_models.dart';

/// One source of truth for Settings search metadata.
///
/// These descriptors do not claim a capability exists. They only deep-link to
/// pages that already render capability truth from the System Broker.
class SearchSettingsCatalog {
  const SearchSettingsCatalog._();

  static const List<SearchSettingsDescriptor> pages = <SearchSettingsDescriptor>[
    SearchSettingsDescriptor(
      id: 'system',
      title: 'Sistema',
      description: 'Nome do dispositivo, System Broker e informações do sistema',
      icon: Icons.computer_rounded,
      keywords: <String>[
        'sistema',
        'computador',
        'dispositivo',
        'device',
        'broker',
        'protocolo',
        'workspace',
      ],
    ),
    SearchSettingsDescriptor(
      id: 'display',
      title: 'Tela',
      description: 'Brilho e recursos de exibição realmente disponíveis',
      icon: Icons.desktop_windows_rounded,
      keywords: <String>[
        'tela',
        'display',
        'monitor',
        'brilho',
        'brightness',
        'escala',
        'resolucao',
      ],
    ),
    SearchSettingsDescriptor(
      id: 'sound',
      title: 'Som',
      description: 'Volume do endpoint de áudio padrão',
      icon: Icons.volume_up_rounded,
      keywords: <String>[
        'som',
        'audio',
        'volume',
        'alto falante',
        'speaker',
        'mute',
      ],
    ),
    SearchSettingsDescriptor(
      id: 'network',
      title: 'Rede & Internet',
      description: 'Estado do adaptador de rede detectado',
      icon: Icons.wifi_rounded,
      keywords: <String>[
        'rede',
        'internet',
        'network',
        'wifi',
        'ethernet',
        'adaptador',
        'conexao',
      ],
    ),
    SearchSettingsDescriptor(
      id: 'bluetooth',
      title: 'Bluetooth',
      description: 'Disponibilidade do backend Bluetooth',
      icon: Icons.bluetooth_rounded,
      keywords: <String>[
        'bluetooth',
        'dispositivo',
        'parear',
        'wireless',
      ],
    ),
    SearchSettingsDescriptor(
      id: 'power',
      title: 'Energia & Bateria',
      description: 'Bateria e energia quando detectadas pelo sistema',
      icon: Icons.battery_charging_full_rounded,
      keywords: <String>[
        'energia',
        'bateria',
        'battery',
        'power',
        'carregamento',
        'ac',
      ],
    ),
    SearchSettingsDescriptor(
      id: 'storage',
      title: 'Armazenamento',
      description: 'Unidades reais retornadas pelo System Broker',
      icon: Icons.storage_rounded,
      keywords: <String>[
        'armazenamento',
        'storage',
        'disco',
        'disk',
        'ssd',
        'hd',
        'espaco',
        'unidade',
      ],
    ),
    SearchSettingsDescriptor(
      id: 'personalization',
      title: 'Personalização',
      description: 'Recursos de aparência disponíveis no CloudOS',
      icon: Icons.palette_rounded,
      keywords: <String>[
        'personalizacao',
        'tema',
        'theme',
        'wallpaper',
        'aparencia',
        'transparencia',
      ],
    ),
    SearchSettingsDescriptor(
      id: 'wsl',
      title: 'WSL (Linux)',
      description: 'Distribuições WSL realmente detectadas',
      icon: Icons.auto_awesome_mosaic_rounded,
      keywords: <String>[
        'wsl',
        'linux',
        'distro',
        'ubuntu',
        'kali',
        'debian',
        'subsistema',
      ],
      requiresWsl: true,
    ),
    SearchSettingsDescriptor(
      id: 'about',
      title: 'Sobre o CloudOS',
      description: 'Bridge, protocolo e estado de integração',
      icon: Icons.info_outline_rounded,
      keywords: <String>[
        'sobre',
        'about',
        'versao',
        'version',
        'bridge',
        'protocolo',
        'integracao',
      ],
    ),
  ];

  static SearchSettingsDescriptor? findById(String id) {
    final normalized = id.trim().toLowerCase();
    for (final page in pages) {
      if (page.id == normalized) return page;
    }
    return null;
  }

  static int pageIndex(String id) {
    final normalized = id.trim().toLowerCase();
    for (var index = 0; index < pages.length; index++) {
      if (pages[index].id == normalized) return index;
    }
    return 0;
  }
}
