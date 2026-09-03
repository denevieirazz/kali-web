import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../models/cloud_system_snapshot.dart';
import '../../../services/cloudos_bridge.dart';
import '../../terminal/domain/wsl_runtime_policy.dart';

class SettingsWindow extends StatefulWidget {
  const SettingsWindow({
    this.snapshot = CloudOSBridge.degradedSnapshot,
    this.bridge = const CloudOSBridge(),
    super.key,
  });

  final CloudSystemSnapshot snapshot;
  final CloudOSBridge bridge;

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow> {
  int _selectedCategory = 0;
  final List<_SettingsCategory> _categories = const <_SettingsCategory>[
    _SettingsCategory('Sistema', Icons.laptop_windows_rounded),
    _SettingsCategory('Áudio e Vídeo', Icons.tune_rounded),
    _SettingsCategory('Rede e Internet', Icons.wifi_rounded),
    _SettingsCategory('WSL e Linux', Icons.terminal_rounded),
    _SettingsCategory('Sobre o CloudOS', Icons.info_outline_rounded),
  ];

  late double _volume;
  late double _brightness;

  @override
  void initState() {
    super.initState();
    _volume = widget.snapshot.volume;
    _brightness = widget.snapshot.brightness;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF10141D),
      child: Row(
        children: <Widget>[
          _buildSidebar(),
          const VerticalDivider(width: 1, color: CloudOSColors.border),
          Expanded(child: _buildCategoryContent()),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 200,
      color: const Color(0xFF131822),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Configurações',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = _selectedCategory == index;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _selectedCategory = index),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? CloudOSColors.accentSoft
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            cat.icon,
                            size: 18,
                            color: isSelected
                                ? CloudOSColors.accent
                                : CloudOSColors.caption,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              cat.title,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? Colors.white
                                    : CloudOSColors.secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryContent() {
    switch (_selectedCategory) {
      case 0:
        return _buildSystemSection();
      case 1:
        return _buildAudioVideoSection();
      case 2:
        return _buildNetworkSection();
      case 3:
        return _buildWslSection();
      case 4:
      default:
        return _buildAboutSection();
    }
  }

  Widget _buildSystemSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const Text(
          'Informações do Sistema',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        _buildInfoCard('Nome do Dispositivo', widget.snapshot.deviceName),
        _buildInfoCard(
          'Workspace Ativo',
          'Área de Trabalho ${widget.snapshot.currentWorkspace}',
        ),
        _buildInfoCard(
          'Bateria',
          widget.snapshot.batteryAvailable
              ? '${widget.snapshot.batteryPercent}%'
              : 'Alimentação CA (Conectado)',
        ),
        _buildInfoCard(
          'Autoridade Nativa',
          'CloudOS Core C++/Win32 (Supervised)',
        ),
        _buildInfoCard('Apresentação', 'CloudOS V21 Flutter Engine Desktop'),
      ],
    );
  }

  Widget _buildAudioVideoSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const Text(
          'Áudio e Vídeo',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Volume do Sistema',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            const Icon(
              Icons.volume_down_rounded,
              color: CloudOSColors.secondary,
              size: 20,
            ),
            Expanded(
              child: Slider(
                value: _volume,
                min: 0.0,
                max: 1.0,
                activeColor: CloudOSColors.accent,
                onChanged: (v) {
                  setState(() => _volume = v);
                  widget.bridge.setVolume(v);
                },
              ),
            ),
            Text(
              '${(_volume * 100).round()}%',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Brilho do Display',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            const Icon(
              Icons.brightness_low_rounded,
              color: CloudOSColors.secondary,
              size: 20,
            ),
            Expanded(
              child: Slider(
                value: _brightness,
                min: 0.0,
                max: 1.0,
                activeColor: CloudOSColors.accent,
                onChanged: (b) {
                  setState(() => _brightness = b);
                  widget.bridge.setBrightness(b);
                },
              ),
            ),
            Text(
              '${(_brightness * 100).round()}%',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNetworkSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const Text(
          'Rede e Internet',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        _buildInfoCard(
          'Status da Conexão',
          widget.snapshot.networkAvailable
              ? 'Conectado à Internet'
              : 'Desconectado',
        ),
        _buildInfoCard('Adaptador / Rede', widget.snapshot.networkName),
        _buildInfoCard('Tipo de Interface', 'Wi-Fi / Ethernet Dual Protocol'),
      ],
    );
  }

  Widget _buildWslSection() {
    final policy = WslRuntimePolicy(
      wslAvailable: widget.snapshot.wslAvailable,
      installedDistros: widget.snapshot.distros,
      defaultDistro: widget.snapshot.defaultDistro,
    );

    final engineStatus = !policy.wslAvailable
        ? 'Indisponível'
        : policy.hasInstalledDistros
        ? 'Detectado • ${policy.installedDistros.length} distro(s) registrada(s)'
        : 'Detectado • nenhuma distro registrada';

    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const Text(
          'Linux Runtime / WSL',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'O CloudOS só marca uma distribuição como disponível quando ela é realmente reportada pelo System Broker.',
          style: TextStyle(color: CloudOSColors.caption, fontSize: 12),
        ),
        const SizedBox(height: 16),
        _buildInfoCard('Engine WSL', engineStatus),
        _buildInfoCard(
          'Distro padrão',
          policy.defaultDistro.isEmpty
              ? 'Não configurada'
              : policy.defaultDistro,
        ),
        _buildInfoCard(
          'Runtime de segurança',
          policy.kaliInstalled
              ? policy.preferredSecurityDistro
              : 'Kali Linux não instalada',
        ),
        const SizedBox(height: 12),
        const Text(
          'Distribuições detectadas:',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (!policy.wslAvailable)
          const _RuntimeNotice(
            icon: Icons.error_outline_rounded,
            title: 'WSL indisponível',
            message:
                'O Windows não reportou um runtime WSL disponível. Sessões Linux permanecem desativadas.',
          )
        else if (!policy.hasInstalledDistros)
          const _RuntimeNotice(
            icon: Icons.info_outline_rounded,
            title: 'Nenhuma distro detectada',
            message:
                'O WSL existe, mas o Broker não reportou nenhuma distribuição registrada. O CloudOS não abrirá uma sessão Linux falsa.',
          )
        else
          for (final distro in policy.installedDistros)
            _buildDistroCard(distro, policy),
        if (policy.wslAvailable && !policy.kaliInstalled) ...<Widget>[
          const SizedBox(height: 8),
          const _RuntimeNotice(
            icon: Icons.security_rounded,
            title: 'Kali não instalada',
            message:
                'O backend de segurança continua indisponível até uma distribuição Kali real ser instalada e detectada. Ubuntu ou outra distro não será renomeada para Kali.',
          ),
        ],
      ],
    );
  }

  Widget _buildDistroCard(String distro, WslRuntimePolicy policy) {
    final isDefault = distro == policy.defaultDistro;
    final isSecurity = WslRuntimePolicy.isKali(distro);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF18202E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CloudOSColors.border),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.terminal_rounded,
            color: CloudOSColors.linux,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  distro,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Registrada no WSL',
                  style: TextStyle(
                    color: CloudOSColors.caption,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          if (isDefault) const _RuntimeBadge(label: 'Padrão'),
          if (isDefault && isSecurity) const SizedBox(width: 6),
          if (isSecurity) const _RuntimeBadge(label: 'Segurança'),
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: CloudOSColors.accentSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CloudOSColors.accent),
              ),
              child: const Icon(
                Icons.cloud_done_rounded,
                color: CloudOSColors.accent,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'CloudOS',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Versão 21.0.0 (Build Modular AI)',
                  style: TextStyle(
                    fontSize: 12,
                    color: CloudOSColors.caption,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildInfoCard(
          'Arquitetura',
          'Shell Visual Única com Window Manager Interno',
        ),
        _buildInfoCard(
          'Engine Gráfica',
          'Flutter Windows Embedder (Seamless Canvas)',
        ),
        _buildInfoCard(
          'System Broker',
          'CloudOS.SystemBroker.exe V21 (Named Pipe IPC)',
        ),
        _buildInfoCard(
          'Supervisor',
          'CloudOS.Supervisor.exe V11 (Headless Watchdog)',
        ),
        _buildInfoCard('Licença', 'Proprietário • Douglas (Administrador)'),
      ],
    );
  }

  Widget _buildInfoCard(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF151C28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CloudOSColors.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: CloudOSColors.secondary,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuntimeNotice extends StatelessWidget {
  const _RuntimeNotice({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF171D28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CloudOSColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: CloudOSColors.caption),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: const TextStyle(
                    color: CloudOSColors.caption,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RuntimeBadge extends StatelessWidget {
  const _RuntimeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: CloudOSColors.accentSoft,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: CloudOSColors.accent,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingsCategory {
  const _SettingsCategory(this.title, this.icon);

  final String title;
  final IconData icon;
}
