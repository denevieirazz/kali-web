import 'package:flutter/material.dart';
import '../core/cloudos_theme.dart';
import '../models/file_models.dart';
import '../models/shell_models.dart';
import '../services/cloudos_bridge.dart';

class SettingsWindow extends StatefulWidget {
  const SettingsWindow({
    super.key,
    required this.bridge,
  });

  final CloudOSBridge bridge;

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow> {
  int _selectedPageIndex = 0;
  CloudSystemSnapshot _snapshot = CloudOSBridge.unavailableSnapshot;
  List<DriveInfoModel> _drives = const <DriveInfoModel>[];
  double _volume = 0.5;
  bool _nightLight = false;
  bool _darkTheme = true;
  bool _glassEffects = true;

  final List<Map<String, dynamic>> _pages = <Map<String, dynamic>>[
    <String, dynamic>{'title': 'Sistema', 'icon': Icons.computer_rounded},
    <String, dynamic>{'title': 'Tela', 'icon': Icons.desktop_windows_rounded},
    <String, dynamic>{'title': 'Som', 'icon': Icons.volume_up_rounded},
    <String, dynamic>{'title': 'Rede & Internet', 'icon': Icons.wifi_rounded},
    <String, dynamic>{'title': 'Bluetooth', 'icon': Icons.bluetooth_rounded},
    <String, dynamic>{'title': 'Energia & Bateria', 'icon': Icons.battery_charging_full_rounded},
    <String, dynamic>{'title': 'Armazenamento', 'icon': Icons.storage_rounded},
    <String, dynamic>{'title': 'Personalização', 'icon': Icons.palette_rounded},
    <String, dynamic>{'title': 'WSL (Linux)', 'icon': Icons.auto_awesome_mosaic_rounded},
    <String, dynamic>{'title': 'Sobre o CloudOS', 'icon': Icons.info_outline_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final snap = await widget.bridge.loadSystemSnapshot();
    final drives = await widget.bridge.getDrives();
    if (!mounted) return;
    setState(() {
      _snapshot = snap;
      _drives = drives;
      _volume = snap.volume;
    });
  }

  void _onVolumeChanged(double val) {
    setState(() => _volume = val);
    widget.bridge.setVolume(val).then((ok) {
      if (!ok && mounted) {
        setState(() => _volume = _snapshot.volume);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        // Menu Lateral de Navegação
        Container(
          width: 220,
          color: const Color(0xFF131620),
          child: Column(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(16),
                alignment: Alignment.centerLeft,
                child: const Text(
                  'Configurações',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _pages.length,
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    final isSelected = index == _selectedPageIndex;
                    return InkWell(
                      onTap: () => setState(() => _selectedPageIndex = index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected ? CloudOSColors.accent.withValues(alpha: 0.18) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? Border.all(color: CloudOSColors.accent.withValues(alpha: 0.4))
                              : null,
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              page['icon'] as IconData,
                              size: 17,
                              color: isSelected ? CloudOSColors.accent : Colors.white60,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                page['title'] as String,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: isSelected ? Colors.white : Colors.white70,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Área Central de Conteúdo
        Expanded(
          child: Container(
            color: const Color(0xFF171A26),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: _buildPageContent(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPageContent() {
    switch (_selectedPageIndex) {
      case 0:
        return _buildSystemPage();
      case 1:
        return _buildDisplayPage();
      case 2:
        return _buildSoundPage();
      case 3:
        return _buildNetworkPage();
      case 4:
        return _buildBluetoothPage();
      case 5:
        return _buildPowerPage();
      case 6:
        return _buildStoragePage();
      case 7:
        return _buildPersonalizationPage();
      case 8:
        return _buildWslPage();
      case 9:
      default:
        return _buildAboutPage();
    }
  }

  Widget _buildCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2232),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildSystemPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCard(
          title: 'Especificações do Dispositivo',
          child: Column(
            children: <Widget>[
              _buildInfoRow('Nome do Computador', _snapshot.deviceName),
              _buildInfoRow('Edição do Sistema', 'CloudOS V22.1 (Host Windows 11)'),
              _buildInfoRow('System Broker', 'V21 IPC (Conectado / Ativo)'),
              _buildInfoRow('Sessão', 'Área de Trabalho 1'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDisplayPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCard(
          title: 'Configurações de Tela',
          child: Column(
            children: <Widget>[
              _buildInfoRow('Resolução Ativa', '1920 x 1080 (Recomendada)'),
              _buildInfoRow('Escala da Interface', '100% (Padrão)'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Luz Noturna', style: TextStyle(fontSize: 13, color: Colors.white)),
                subtitle: const Text('Reduz a fadiga visual usando cores mais quentes', style: TextStyle(fontSize: 11, color: Colors.white60)),
                value: _nightLight,
                onChanged: (val) => setState(() => _nightLight = val),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSoundPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCard(
          title: 'Saída de Áudio do Sistema',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.volume_up_rounded, size: 20, color: CloudOSColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Slider(
                      value: _volume,
                      min: 0.0,
                      max: 1.0,
                      activeColor: CloudOSColors.accent,
                      onChanged: _onVolumeChanged,
                    ),
                  ),
                  Text('${(_volume * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white)),
                ],
              ),
              const SizedBox(height: 8),
              _buildInfoRow('Dispositivo Padrão', 'Alto-falantes (Realtek High Definition Audio)'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCard(
          title: 'Status da Conexão',
          child: Column(
            children: <Widget>[
              _buildInfoRow('Rede Atual', _snapshot.networkName),
              _buildInfoRow('Tipo de Conexão', 'Ethernet / Wi-Fi 6'),
              _buildInfoRow('Status do Broker', _snapshot.networkAvailable ? 'Conectado à Internet' : 'Desconectado'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBluetoothPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCard(
          title: 'Dispositivos Bluetooth',
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Adaptador Bluetooth Ativo', style: TextStyle(fontSize: 13, color: Colors.white70)),
              SizedBox(height: 8),
              Text('Pronto para emparelhamento.', style: TextStyle(fontSize: 11.5, color: Colors.white54)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPowerPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCard(
          title: 'Bateria e Energia',
          child: Column(
            children: <Widget>[
              _buildInfoRow('Fonte de Energia', 'Conectado à Tomada (Desktop AC)'),
              _buildInfoRow('Status da Bateria', _snapshot.batteryPercent >= 0 ? '${_snapshot.batteryPercent}%' : 'Alimentação Direta'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStoragePage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCard(
          title: 'Unidades de Armazenamento',
          child: _drives.isEmpty
              ? const Text('Carregando drives do sistema...', style: TextStyle(color: Colors.white60))
              : Column(
                  children: _drives.map((d) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.storage_rounded, size: 22, color: CloudOSColors.accent),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text('${d.label} (${d.letter})', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                Text('Espaço livre: ${d.freeFormatted} de ${d.totalFormatted} (${d.filesystem})', style: const TextStyle(fontSize: 11.5, color: Colors.white60)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildPersonalizationPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCard(
          title: 'Aparência e Tema',
          child: Column(
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tema Escuro (Dark Glass)', style: TextStyle(fontSize: 13, color: Colors.white)),
                value: _darkTheme,
                onChanged: (val) => setState(() => _darkTheme = val),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Efeitos de Transparência Glassmorphism', style: TextStyle(fontSize: 13, color: Colors.white)),
                value: _glassEffects,
                onChanged: (val) => setState(() => _glassEffects = val),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWslPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCard(
          title: 'Subsistema Windows para Linux (WSL2)',
          child: Column(
            children: <Widget>[
              _buildInfoRow('WSL Instalado', _snapshot.wslAvailable ? 'Sim (Versão 2)' : 'Não detectado'),
              _buildInfoRow('Distribuições', _snapshot.distros.isEmpty ? 'Nenhuma instalada' : _snapshot.distros.join(', ')),
              _buildInfoRow('Acesso UNC', _snapshot.distros.isNotEmpty ? r'\\wsl.localhost\' + _snapshot.distros.first : r'\\wsl.localhost'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAboutPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCard(
          title: 'CloudOS Desktop V22.1',
          child: Column(
            children: <Widget>[
              _buildInfoRow('Versão', '22.1.0-release'),
              _buildInfoRow('Protocolo Broker', 'V21 IPC (Named Pipe restrito)'),
              _buildInfoRow('Arquitetura', 'x64 (Nativa Windows + Flutter Presentation)'),
              _buildInfoRow('Compilação', 'Release x64 MSBuild / Flutter SDK 3.47.2'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 12.5, color: Colors.white60)),
          Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }
}
